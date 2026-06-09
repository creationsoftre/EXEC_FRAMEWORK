local cfg  = require "config.arenas"
local weaponCatalog = require "shared.weapon_catalog"
local AppearanceBridge = require "bridge.appearance"
local InventoryBridge = require "bridge.inventory"
local SpawnBridge = require "bridge.spawn"
local addonConfig = weaponCatalog.addon or {}
local acfg = require "config.attachments"
local gcfg = require "config.gameplay"
local menuCfg = (gcfg and gcfg.menu) or {}
local combatCfg = (gcfg and gcfg.combat) or {}
local combatDomeCfg = (gcfg and gcfg.combatDome) or {}
local oneShotHeadshotsEnabled = combatCfg.oneShotHeadshots ~= false
local cfgA = cfg

local ALL_CATEGORIES = {}
for key, cat in pairs(weaponCatalog.categories or {}) do
  ALL_CATEGORIES[key] = cat
end
for key, cat in pairs(addonConfig.categories or {}) do
  ALL_CATEGORIES[key] = cat
end
local ALL_LOCALES = weaponCatalog.locales or {}
local addonAttachments = addonConfig.attachments or {}
local addonUnlocks = addonConfig.unlocks or {}
local playerUnlocks = {}
local addonWeaponSet = {}

for _, weapon in ipairs(addonConfig.weapons or {}) do
  if type(weapon) == "table" and weapon.code then
    local code = type(weapon.code) == "string" and weapon.code:upper() or nil
    if code then
      if not code:find("WEAPON_", 1, true) then
        code = "WEAPON_" .. code
      end
      addonWeaponSet[code] = true
    end
  end
end

local CATEGORY_CHILDREN = {}
local CATEGORY_PARENTS = {}
local CATEGORY_GROUPS = {}

do
  for key, cat in pairs(ALL_CATEGORIES) do
    local parent = cat.inherit or cat.parent
    if parent then
      CATEGORY_CHILDREN[parent] = CATEGORY_CHILDREN[parent] or {}
      CATEGORY_CHILDREN[parent][#CATEGORY_CHILDREN[parent]+1] = key
      CATEGORY_PARENTS[key] = parent
    end

    if cat.group then
      local group = CATEGORY_GROUPS[cat.group]
      if not group then
        group = {
          keys = {},
          label = cat.groupLabel or cat.label or cat.group,
          description = cat.groupDescription,
          icon = cat.groupIcon or "star"
        }
        CATEGORY_GROUPS[cat.group] = group
      end
      group.keys[#group.keys+1] = key
      if cat.groupLabel then group.label = cat.groupLabel end
      if cat.groupDescription and not group.description then
        group.description = cat.groupDescription
      end
      if cat.groupIcon then group.icon = cat.groupIcon end
    end
  end

  for _, list in pairs(CATEGORY_CHILDREN) do
    table.sort(list)
  end
  for _, group in pairs(CATEGORY_GROUPS) do
    table.sort(group.keys, function(a, b) return a < b end)
  end
end

local function expandCategoriesList(list)
  local seen, out = {}, {}

  local function addCategory(key)
    if not key or seen[key] or not ALL_CATEGORIES[key] then return end
    seen[key] = true
    out[#out+1] = key
    local parent = CATEGORY_PARENTS[key]
    if parent then
      addCategory(parent)
    end
    local children = CATEGORY_CHILDREN[key]
    if children then
      for _, child in ipairs(children) do
        addCategory(child)
      end
    end
  end

  if list and #list > 0 then
    for _, key in ipairs(list) do
      addCategory(key)
    end
  else
    for key,_ in pairs(ALL_CATEGORIES) do
      addCategory(key)
    end
  end

  table.sort(out)
  return out, seen
end

local function collectCategoryFamily(categoryKey)
  local cat = ALL_CATEGORIES[categoryKey]
  if not cat then return {}, categoryKey end

  local root = categoryKey
  while CATEGORY_PARENTS[root] do
    root = CATEGORY_PARENTS[root]
  end

  local ordered = {}
  local visited = {}
  local function addBranch(key)
    if not key or visited[key] or not ALL_CATEGORIES[key] then return end
    visited[key] = true
    ordered[#ordered+1] = key
    local children = CATEGORY_CHILDREN[key]
    if children then
      for _, child in ipairs(children) do
        addBranch(child)
      end
    end
  end
  addBranch(root)

  local family = {}
  local seen = {}
  if visited[categoryKey] then
    family[#family+1] = categoryKey
    seen[categoryKey] = true
  end
  for _, key in ipairs(ordered) do
    if not seen[key] then
      family[#family+1] = key
      seen[key] = true
    end
  end

  return family, root
end

local function sanitizeWeaponCode(code)
  if type(code) ~= 'string' then return code end
  local upper = code:upper()
  if not upper:find('WEAPON_', 1, true) then
    upper = 'WEAPON_' .. upper
  end
  return upper
end

local function ensureWeaponAssetLoaded(weaponHash, timeoutMs)
  if not weaponHash or weaponHash == 0 then return false end

  timeoutMs = timeoutMs or 5000

  if lib and lib.requestWeaponAsset then
    local ok, _ = pcall(lib.requestWeaponAsset, weaponHash, timeoutMs)
    if ok then return true end
  end

  if type(HasWeaponAssetLoaded) ~= "function" or type(RequestWeaponAsset) ~= "function" then
    return true
  end

  if HasWeaponAssetLoaded(weaponHash) then
    return true
  end

  RequestWeaponAsset(weaponHash, 31, 0)

  local hasTimer = type(GetGameTimer) == "function"
  local deadline = hasTimer and (GetGameTimer() + timeoutMs) or nil

  while not HasWeaponAssetLoaded(weaponHash) do
    if deadline and GetGameTimer() >= deadline then
      return false
    end
    Wait(0)
  end

  return true
end

local weaponLocaleByCode, weaponLocaleByHash = {}, {}
local weaponCodeByHash = {}

local attachmentsByWeapon = {}

local function ingestAttachments(map)
  for weaponCode, list in pairs(map or {}) do
    local sanitized = sanitizeWeaponCode(weaponCode)
    if sanitized and type(list) == 'table' then
      local processed = attachmentsByWeapon[sanitized] or {}
      local before = #processed
      for _, entry in ipairs(list) do
        if entry and entry.component then
          processed[#processed+1] = {
            label = entry.label or entry.component,
            component = entry.component,
            componentHash = GetHashKey(entry.component),
            slot = entry.slot,
            defaultOn = entry.defaultOn and true or false,
            previewModel = entry.previewModel,
            previewAttachBone = entry.previewAttachBone,
          }
        end
      end
      if #processed > before then
        attachmentsByWeapon[sanitized] = processed
        local hash = GetHashKey(sanitized)
        if not weaponCodeByHash[hash] then
          weaponCodeByHash[hash] = sanitized
        end
      end
    end
  end
end

do
  for name, label in pairs(ALL_LOCALES) do
    local key = sanitizeWeaponCode(name)
    if key and label then
      local hash = GetHashKey(key)
      weaponLocaleByCode[key] = label
      weaponLocaleByHash[hash] = label
      weaponCodeByHash[hash] = key
    end
  end
end

do
  for _, cat in pairs(ALL_CATEGORIES) do
    for _, weapon in ipairs(cat.weapons or {}) do
      local entry = weapon
      local inlineAttachments = nil
      if type(entry) == "table" then
        inlineAttachments = entry.attachments
        entry = entry.code or entry.weapon or entry[1]
      end
      local code = sanitizeWeaponCode(entry)
      if code then
        if type(inlineAttachments) == 'table' and #inlineAttachments > 0 then
          ingestAttachments({ [code] = inlineAttachments })
        end
        local hash = GetHashKey(code)
        if not weaponCodeByHash[hash] then
          weaponCodeByHash[hash] = code
        end
      end
    end
  end
end

local function weaponDisplayInfo(weapon)
  if not weapon then return weapon, 'Unarmed' end
  local code = weapon
  local hash
  if type(code) == 'string' then
    code = sanitizeWeaponCode(code)
    hash = GetHashKey(code)
  elseif type(code) == 'number' then
    hash = code
  else
    return weapon, tostring(weapon)
  end

  local label = weaponLocaleByHash[hash]
  if not label and type(code) == 'string' then
    label = weaponLocaleByCode[code]
  end
  if not label and hash ~= 0 then
    local display = GetWeaponDisplayNameFromHash(hash)
    if display and display ~= '' then
      local text = GetLabelText(display)
      if text and text ~= '' and text ~= 'CInvalid' then
        label = text
      end
    end
  end
  if not label then
    if type(code) == 'string' then
      label = code
    else
      label = tostring(hash)
    end
  end
  return code, label
end

if acfg and acfg.weapons then
  ingestAttachments(acfg.weapons)
end
ingestAttachments(addonAttachments)
do
  local generatedAddonAttachments = {}
  for _, weapon in ipairs(addonConfig.weapons or {}) do
    if type(weapon) == "table" and weapon.code and type(weapon.attachments) == "table" and addonAttachments[weapon.code] == nil then
      generatedAddonAttachments[weapon.code] = weapon.attachments
    end
  end
  ingestAttachments(generatedAddonAttachments)
end

do
  local normalized = {}
  for weaponCode, data in pairs(addonUnlocks or {}) do
    local sanitized = sanitizeWeaponCode(weaponCode)
    if sanitized then
      normalized[sanitized] = data
    end
  end
  addonUnlocks = normalized
end

local PREVIEW_ATTACHMENTS_MENU = "exec_weapon_preview_attachments"
local getAttachmentState
local weaponPreviewState = {
  active = false,
  attachments = {},
  activeComponents = {},
  zoomDistance = 1.6,
  heightOffset = 0.25,
  returnContext = nil,
}

local function syncPreviewAttachmentState(entry, enable)
  if not entry or not entry.component or not getAttachmentState then return end
  local weaponCode = weaponPreviewState.weaponCode and sanitizeWeaponCode(weaponPreviewState.weaponCode) or nil
  if not weaponCode then return end

  local defs = attachmentsByWeapon[weaponCode] or {}
  local state = getAttachmentState(weaponCode)
  local weaponHash = GetHashKey(weaponCode)
  local ped = PlayerPedId()
  local hasWeapon = ped ~= 0 and HasPedGotWeapon(ped, weaponHash, false)
  enable = enable and true or false

  if enable and entry.slot then
    for _, other in ipairs(defs) do
      if other ~= entry and other.slot ~= nil and other.slot == entry.slot then
        state[other.component] = false
        if hasWeapon and HasPedGotWeaponComponent(ped, weaponHash, other.componentHash) then
          RemoveWeaponComponentFromPed(ped, weaponHash, other.componentHash)
        end
      end
    end
  end

  state[entry.component] = enable
  if not hasWeapon then return end

  if enable then
    if not HasPedGotWeaponComponent(ped, weaponHash, entry.componentHash) then
      GiveWeaponComponentToPed(ped, weaponHash, entry.componentHash)
    end
  elseif HasPedGotWeaponComponent(ped, weaponHash, entry.componentHash) then
    RemoveWeaponComponentFromPed(ped, weaponHash, entry.componentHash)
  end
end

local function clearPreviewAttachmentState()
  local weaponCode = weaponPreviewState.weaponCode and sanitizeWeaponCode(weaponPreviewState.weaponCode) or nil
  if not weaponCode or not getAttachmentState then return end

  local defs = attachmentsByWeapon[weaponCode] or {}
  local state = getAttachmentState(weaponCode)
  local weaponHash = GetHashKey(weaponCode)
  local ped = PlayerPedId()
  local hasWeapon = ped ~= 0 and HasPedGotWeapon(ped, weaponHash, false)

  for _, entry in ipairs(defs) do
    state[entry.component] = false
    if hasWeapon and HasPedGotWeaponComponent(ped, weaponHash, entry.componentHash) then
      RemoveWeaponComponentFromPed(ped, weaponHash, entry.componentHash)
    end
  end
end

local function hideWeaponPreviewHelp()
  if weaponPreviewState.helpVisible and lib and lib.hideTextUI then
    lib.hideTextUI()
  end
  weaponPreviewState.helpVisible = false
end

local function showWeaponPreviewHelp(label)
  if not lib or not lib.showTextUI then return end
  local text = ("Inspecting %s\nScroll: Zoom | A/D: Rotate | W/S: Tilt | E: Attachments | Backspace: Close")
    :format(label or "Weapon")
  lib.showTextUI(text, { position = 'top-center', icon = 'gun' })
  weaponPreviewState.helpVisible = true
end

local function refreshWeaponPreviewCamera()
  if not weaponPreviewState.active or not DoesCamExist(weaponPreviewState.cam) then return end
  local origin = weaponPreviewState.origin or vector3(0.0, 0.0, 0.0)
  local distance = weaponPreviewState.zoomDistance or 1.6
  local height = weaponPreviewState.heightOffset or 0.25
  local cam = weaponPreviewState.cam
  SetCamCoord(cam, origin.x, origin.y - distance, origin.z + height)
  PointCamAtCoord(cam, origin.x, origin.y, origin.z)
end

local function ensureModelLoaded(modelHash, timeoutMs)
  if not modelHash or modelHash == 0 then return false end
  if HasModelLoaded(modelHash) then return true end
  if not IsModelInCdimage(modelHash) then return false end

  RequestModel(modelHash)
  timeoutMs = timeoutMs or 5000
  local deadline = GetGameTimer() + timeoutMs
  while not HasModelLoaded(modelHash) do
    if GetGameTimer() >= deadline then
      return false
    end
    Wait(0)
  end
  return true
end

local function clearPreviewAttachments()
  if not weaponPreviewState.active or not DoesEntityExist(weaponPreviewState.object) then return end
  for componentHash, meta in pairs(weaponPreviewState.activeComponents or {}) do
    RemoveWeaponComponentFromWeaponObject(weaponPreviewState.object, componentHash)
    if meta and meta.previewObject and DoesEntityExist(meta.previewObject) then
      DeleteEntity(meta.previewObject)
    end
  end
  weaponPreviewState.activeComponents = {}
end

local function previewComponentIsPedOnly(entry)
  if not entry then return false end
  if entry.slot == "skin" then return true end

  local component = entry.component
  return type(component) == "string" and component:upper():find("VARMOD", 1, true) ~= nil
end

local function previewWeaponSupportsComponent(componentHash, entry)
  if previewComponentIsPedOnly(entry) then return false end
  local weaponHash = weaponPreviewState.weaponHash
  local weaponCode = weaponPreviewState.weaponCode and sanitizeWeaponCode(weaponPreviewState.weaponCode) or nil
  if weaponCode and addonWeaponSet[weaponCode] then
    return componentHash and componentHash ~= 0
  end
  return weaponHash and componentHash and componentHash ~= 0 and DoesWeaponTakeWeaponComponent(weaponHash, componentHash)
end

local function createManualPreviewComponent(entry)
  if not entry or not entry.previewModel or not DoesEntityExist(weaponPreviewState.object) then return nil end

  local modelHash = GetHashKey(entry.previewModel)
  if not ensureModelLoaded(modelHash, 1500) then return nil end

  local origin = weaponPreviewState.origin or GetEntityCoords(weaponPreviewState.object)
  local componentObject = CreateObjectNoOffset(modelHash, origin.x, origin.y, origin.z, false, false, false)
  if not componentObject or componentObject == 0 then return nil end

  SetEntityAsMissionEntity(componentObject, true, true)
  SetEntityCollision(componentObject, false, false)
  FreezeEntityPosition(componentObject, true)

  local boneIndex = -1
  if entry.previewAttachBone then
    boneIndex = GetEntityBoneIndexByName(weaponPreviewState.object, entry.previewAttachBone)
  end

  AttachEntityToEntity(
    componentObject,
    weaponPreviewState.object,
    boneIndex,
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    false, false, false, false, 2, true
  )
  SetModelAsNoLongerNeeded(modelHash)
  return componentObject
end

local function removePreviewSlotComponents(slot, exceptHash)
  if not slot then return end
  for _, entry in ipairs(weaponPreviewState.attachments or {}) do
    if entry and entry.slot == slot and entry.componentHash and entry.componentHash ~= exceptHash then
      RemoveWeaponComponentFromWeaponObject(weaponPreviewState.object, entry.componentHash)
    end
  end
  for hash, meta in pairs(weaponPreviewState.activeComponents or {}) do
    if meta.slot == slot and hash ~= exceptHash then
      if meta.previewObject and DoesEntityExist(meta.previewObject) then
        DeleteEntity(meta.previewObject)
      end
      weaponPreviewState.activeComponents[hash] = nil
    end
  end
end

local function setPreviewComponent(componentHash, entry, enable, persist)
  if not componentHash or not weaponPreviewState.active or not DoesEntityExist(weaponPreviewState.object) then return end
  if not previewWeaponSupportsComponent(componentHash, entry) then
    if persist then
      syncPreviewAttachmentState(entry, enable)
      if previewComponentIsPedOnly(entry) and lib and lib.notify then
        lib.notify({ title = "Preview", description = "Finish applied to equipped weapon; it is not shown on the preview model.", type = "inform" })
      elseif lib and lib.notify then
        lib.notify({ title = "Preview", description = "That attachment is not supported by this weapon preview.", type = "error" })
      end
    end
    return
  end
  weaponPreviewState.activeComponents = weaponPreviewState.activeComponents or {}
  if enable then
    local slot = entry and entry.slot
    removePreviewSlotComponents(slot, componentHash)
    local previewObject = nil
    local useManualPreview = entry and not entry.defaultOn and entry.previewModel and weaponPreviewState.weaponCode and addonWeaponSet[sanitizeWeaponCode(weaponPreviewState.weaponCode)]
    if useManualPreview then
      previewObject = createManualPreviewComponent(entry)
    end
    if not previewObject then
      GiveWeaponComponentToWeaponObject(weaponPreviewState.object, componentHash)
    end
    weaponPreviewState.activeComponents[componentHash] = { slot = slot, previewObject = previewObject }
  else
    RemoveWeaponComponentFromWeaponObject(weaponPreviewState.object, componentHash)
    local meta = weaponPreviewState.activeComponents[componentHash]
    if meta and meta.previewObject and DoesEntityExist(meta.previewObject) then
      DeleteEntity(meta.previewObject)
    end
    weaponPreviewState.activeComponents[componentHash] = nil
  end
  if persist then
    syncPreviewAttachmentState(entry, enable)
  end
end

local function applyPreviewDefaults()
  local attachments = weaponPreviewState.attachments or {}
  if not attachments then return end
  weaponPreviewState.activeComponents = {}
  local previewWeaponCode = weaponPreviewState.weaponCode and sanitizeWeaponCode(weaponPreviewState.weaponCode) or nil
  local savedState = previewWeaponCode and getAttachmentState(previewWeaponCode) or nil
  local ped = PlayerPedId()
  local currentWeaponHash = ped ~= 0 and GetSelectedPedWeapon(ped) or nil
  local previewWeaponHash = previewWeaponCode and GetHashKey(previewWeaponCode) or nil
  local mirrorEquipped = ped ~= 0 and previewWeaponHash and currentWeaponHash == previewWeaponHash
  for _, entry in ipairs(attachments) do
    local shouldEnable = false
    if entry then
      if savedState and savedState[entry.component] ~= nil then
        shouldEnable = savedState[entry.component] == true
      elseif mirrorEquipped and entry.componentHash and HasPedGotWeaponComponent(ped, previewWeaponHash, entry.componentHash) then
        shouldEnable = true
      elseif entry.defaultOn then
        shouldEnable = true
      end
    end
    if entry and shouldEnable then
      local hash = entry.componentHash or (entry.component and GetHashKey(entry.component))
      if hash then
        setPreviewComponent(hash, entry, true, false)
      end
    end
  end
end

local openWeaponPreviewAttachmentsMenu
local refreshWeaponPreviewAttachmentsMenu

openWeaponPreviewAttachmentsMenu = function()
  if not weaponPreviewState.active then return end
  local attachments = weaponPreviewState.attachments or {}
  if not attachments or #attachments == 0 then
    lib.notify({ title = "Preview", description = "No attachments available for this weapon.", type = "inform" })
    return
  end

  local options = {}
  for _, entry in ipairs(attachments) do
    local hash = entry.componentHash or (entry.component and GetHashKey(entry.component))
    local supported = hash and previewWeaponSupportsComponent(hash, entry)
    if supported then
      local enabled = hash and weaponPreviewState.activeComponents and weaponPreviewState.activeComponents[hash]
      options[#options+1] = {
        title = entry.label or entry.component or "Attachment",
        description = entry.slot and ("Slot: " .. entry.slot) or nil,
        icon = enabled and "toggle-on" or "toggle-off",
        onSelect = function()
          if hash then
            setPreviewComponent(hash, entry, not enabled, true)
            refreshWeaponPreviewAttachmentsMenu()
          end
        end
      }
    end
  end

  if #options == 0 then
    lib.notify({ title = "Preview", description = "No previewable attachments available for this weapon.", type = "inform" })
    return
  end

  options[#options+1] = {
    title = "Clear Attachments",
    icon = "rotate-left",
    description = "Remove all applied attachments",
    onSelect = function()
      clearPreviewAttachments()
      clearPreviewAttachmentState()
      refreshWeaponPreviewAttachmentsMenu()
    end
  }

  lib.registerContext({
    id = PREVIEW_ATTACHMENTS_MENU,
    title = ("Attachments - %s"):format(weaponPreviewState.label or weaponPreviewState.weaponCode or "Weapon"),
    options = options
  })
  weaponPreviewState.attachmentsMenuOpen = true
  lib.showContext(PREVIEW_ATTACHMENTS_MENU)
end

refreshWeaponPreviewAttachmentsMenu = function()
  if weaponPreviewState.attachmentsMenuOpen and lib and lib.hideContext then
    lib.hideContext()
    weaponPreviewState.attachmentsMenuOpen = false
  end
  SetTimeout(35, openWeaponPreviewAttachmentsMenu)
end

local function closeWeaponPreview(skipReturn)
  if not weaponPreviewState.active then return end
  hideWeaponPreviewHelp()
  if weaponPreviewState.attachmentsMenuOpen and lib and lib.hideContext then
    lib.hideContext()
    weaponPreviewState.attachmentsMenuOpen = false
  end
  if DoesCamExist(weaponPreviewState.cam) then
    RenderScriptCams(false, true, 250, true, true)
    DestroyCam(weaponPreviewState.cam, false)
  end
  clearPreviewAttachments()
  if DoesEntityExist(weaponPreviewState.object) then
    DeleteEntity(weaponPreviewState.object)
  end
  local ped = PlayerPedId()
  if weaponPreviewState.pedFrozen and DoesEntityExist(ped) then
    FreezeEntityPosition(ped, false)
  end
  weaponPreviewState.active = false
  weaponPreviewState.object = nil
  weaponPreviewState.cam = nil
  weaponPreviewState.weaponCode = nil
  weaponPreviewState.weaponHash = nil
  weaponPreviewState.attachments = {}
  weaponPreviewState.activeComponents = {}
  local returnContext = weaponPreviewState.returnContext
  weaponPreviewState.returnContext = nil
  if not skipReturn and returnContext then
    SetTimeout(200, function()
      lib.showContext(returnContext)
    end)
  end
end

local function weaponPreviewTick()
  while weaponPreviewState.active do
    Wait(0)
    if not weaponPreviewState.active then break end
    if not DoesEntityExist(weaponPreviewState.object) or not DoesCamExist(weaponPreviewState.cam) then
      closeWeaponPreview()
      break
    end

    DisableControlAction(0, 30, true)
    DisableControlAction(0, 31, true)
    DisableControlAction(0, 32, true)
    DisableControlAction(0, 33, true)
    DisableControlAction(0, 34, true)
    DisableControlAction(0, 35, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 68, true)
    DisableControlAction(0, 38, true) -- INPUT_PICKUP (E)
    DisableControlAction(0, 51, true) -- INPUT_CONTEXT (E)
    DisableControlAction(0, 37, true) -- INPUT_SELECT_WEAPON (weapon wheel)
    DisableControlAction(0, 14, true) -- weapon wheel next
    DisableControlAction(0, 15, true) -- weapon wheel prev
    DisablePlayerFiring(PlayerId(), true)

    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not weaponPreviewState.pedFrozen then
      FreezeEntityPosition(ped, true)
      weaponPreviewState.pedFrozen = true
    end

    local rotateSpeed = 0.75
    if IsDisabledControlPressed(0, 34) then
      weaponPreviewState.rotation = (weaponPreviewState.rotation or 0.0) + rotateSpeed
      SetEntityHeading(weaponPreviewState.object, weaponPreviewState.rotation)
    elseif IsDisabledControlPressed(0, 35) then
      weaponPreviewState.rotation = (weaponPreviewState.rotation or 0.0) - rotateSpeed
      SetEntityHeading(weaponPreviewState.object, weaponPreviewState.rotation)
    end

    local heightStep = 0.003
    if IsDisabledControlPressed(0, 32) then
      weaponPreviewState.heightOffset = math.min((weaponPreviewState.heightOffset or 0.25) + heightStep, 0.65)
      refreshWeaponPreviewCamera()
    elseif IsDisabledControlPressed(0, 33) then
      weaponPreviewState.heightOffset = math.max((weaponPreviewState.heightOffset or 0.25) - heightStep, -0.1)
      refreshWeaponPreviewCamera()
    end

    if IsDisabledControlJustPressed(0, 241) then
      weaponPreviewState.zoomDistance = math.max(0.75, (weaponPreviewState.zoomDistance or 1.6) - 0.1)
      refreshWeaponPreviewCamera()
    elseif IsDisabledControlJustPressed(0, 242) then
      weaponPreviewState.zoomDistance = math.min(3.0, (weaponPreviewState.zoomDistance or 1.6) + 0.1)
      refreshWeaponPreviewCamera()
    end

    if IsDisabledControlJustPressed(0, 51) then
      openWeaponPreviewAttachmentsMenu()
    elseif IsDisabledControlJustPressed(0, 202) or IsDisabledControlJustPressed(0, 200) then
      closeWeaponPreview()
      break
    end
  end
end

local function openWeaponPreview(weaponCode, label)
  weaponCode = sanitizeWeaponCode(weaponCode)
  if not weaponCode then return end
  closeWeaponPreview(true)

  local ped = PlayerPedId()
  if ped == 0 then return end

  local pos = GetEntityCoords(ped)
  local forward = GetEntityForwardVector(ped)
  local origin = vector3(pos.x + forward.x * 0.8, pos.y + forward.y * 0.8, pos.z + 0.65)
  local weaponHash = GetHashKey(weaponCode)
  if not ensureWeaponAssetLoaded(weaponHash, 5000) then
    lib.notify({ title = "Preview", description = "Unable to load weapon model for preview.", type = "error" })
    return
  end

  local object = CreateWeaponObject(weaponHash, 1, origin.x, origin.y, origin.z, true, 0.0, 0.0)
  if not object or object == 0 then
    lib.notify({ title = "Preview", description = "Unable to create weapon preview.", type = "error" })
    return
  end
  SetEntityAsMissionEntity(object, true, true)
  SetEntityCollision(object, false, false)
  FreezeEntityPosition(object, true)
  SetEntityHeading(object, 0.0)

  local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  if not cam then
    DeleteEntity(object)
    lib.notify({ title = "Preview", description = "Unable to create preview camera.", type = "error" })
    return
  end
  SetCamFov(cam, 50.0)

  weaponPreviewState.active = true
  weaponPreviewState.weaponCode = weaponCode
  weaponPreviewState.weaponHash = weaponHash
  weaponPreviewState.label = label or weaponCode
  weaponPreviewState.object = object
  weaponPreviewState.cam = cam
  weaponPreviewState.origin = origin
  weaponPreviewState.rotation = 0.0
  weaponPreviewState.zoomDistance = 1.6
  weaponPreviewState.heightOffset = 0.25
  weaponPreviewState.attachments = attachmentsByWeapon[weaponCode] or {}
  weaponPreviewState.activeComponents = {}
  weaponPreviewState.pedFrozen = false
  weaponPreviewState.attachmentsMenuOpen = false

  refreshWeaponPreviewCamera()
  SetCamActive(cam, true)
  RenderScriptCams(true, true, 250, true, true)
  applyPreviewDefaults()
  showWeaponPreviewHelp(weaponPreviewState.label)

  CreateThread(weaponPreviewTick)
end

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    closeWeaponPreview(true)
  end
end)

RegisterNetEvent('exec:weaponUnlocks:sync', function(payload)
  playerUnlocks = {}
  for weaponCode, state in pairs(payload or {}) do
    local sanitized = sanitizeWeaponCode(weaponCode)
    if sanitized then
      playerUnlocks[sanitized] = state and true or false
    end
  end
end)

local savedAttachments = {}
local savedWeaponTints = {}
local MAX_WEAPON_PRESETS = 5
local savedWeaponPresets = {}

local encodeJson = (json and json.encode) or (lib and lib.json and lib.json.encode)
local decodeJson = (json and json.decode) or (lib and lib.json and lib.json.decode)

local STANDARD_WEAPON_TINT_LABELS = {
  [0] = "Default",
  [1] = "Green",
  [2] = "Gold",
  [3] = "Pink",
  [4] = "Army",
  [5] = "LSPD",
  [6] = "Orange",
  [7] = "Platinum",
}

local MK2_WEAPON_TINT_LABELS = {
  [0] = "Classic Black",
  [1] = "Classic Gray",
  [2] = "Classic Two-Tone",
  [3] = "Classic White",
  [4] = "Classic Beige",
  [5] = "Classic Green",
  [6] = "Classic Blue",
  [7] = "Classic Earth",
  [8] = "Classic Brown & Black",
  [9] = "Red Contrast",
  [10] = "Blue Contrast",
  [11] = "Yellow Contrast",
  [12] = "Orange Contrast",
  [13] = "Bold Pink",
  [14] = "Bold Purple & Yellow",
  [15] = "Bold Orange",
  [16] = "Bold Green & Purple",
  [17] = "Bold Red Features",
  [18] = "Bold Green Features",
  [19] = "Bold Cyan Features",
  [20] = "Bold Yellow Features",
  [21] = "Bold Red & White",
  [22] = "Bold Blue & White",
  [23] = "Metallic Gold",
  [24] = "Metallic Platinum",
  [25] = "Metallic Gray & Lilac",
  [26] = "Metallic Purple & Lime",
  [27] = "Metallic Red",
  [28] = "Metallic Green",
  [29] = "Metallic Blue",
  [30] = "Metallic White & Aqua",
  [31] = "Metallic Orange & Yellow",
}

local function trim(value)
  if type(value) ~= 'string' then return value end
  return value:match('^%s*(.-)%s*$')
end

local function currentPresetTimestamp()
  if type(GetCloudTimeAsInt) == 'function' then
    local ok, value = pcall(GetCloudTimeAsInt)
    if ok and type(value) == 'number' then
      return value
    end
  end
  if type(GetNetworkTime) == 'function' then
    local ok, value = pcall(GetNetworkTime)
    if ok and type(value) == 'number' then
      return value
    end
  end
  if type(GetGameTimer) == 'function' then
    local ok, value = pcall(GetGameTimer)
    if ok and type(value) == 'number' then
      return math.floor(value)
    end
  end
  return 0
end

local function cloneAttachmentStateTable(source)
  local copy = {}
  if not source then return copy end
  for component, state in pairs(source) do
    if state ~= nil then
      copy[component] = state and true or false
    end
  end
  return copy
end

local function getWeaponTintCount(weaponHash)
  if not weaponHash or weaponHash == 0 then return 0 end
  if type(GetWeaponTintCount) ~= 'function' then return 0 end
  local ok, count = pcall(GetWeaponTintCount, weaponHash)
  count = ok and tonumber(count) or 0
  return count and math.max(0, math.floor(count)) or 0
end

local function weaponSupportsTints(weaponHash)
  return getWeaponTintCount(weaponHash) > 1
end

local function weaponTintLabel(weaponCode, tintIndex, tintCount)
  local labels = (weaponCode and weaponCode:find("_MK2", 1, true)) and MK2_WEAPON_TINT_LABELS or STANDARD_WEAPON_TINT_LABELS
  if tintCount and tintCount > 8 then
    labels = MK2_WEAPON_TINT_LABELS
  end
  return labels[tintIndex] or ("Tint " .. tostring(tintIndex))
end

local function persistSavedWeaponTints()
  if not encodeJson then return end
  local ok, encoded = pcall(encodeJson, savedWeaponTints)
  if ok and encoded then
    SetResourceKvp('exec_weapon_tints', encoded)
  end
end

local function loadSavedWeaponTints()
  savedWeaponTints = {}
  if not decodeJson then return end
  local raw = GetResourceKvpString('exec_weapon_tints')
  if not raw or raw == '' then return end
  local ok, data = pcall(decodeJson, raw)
  if not ok or type(data) ~= 'table' then return end
  for weaponCode, tintIndex in pairs(data) do
    local sanitized = sanitizeWeaponCode(weaponCode)
    tintIndex = tonumber(tintIndex)
    if sanitized and tintIndex then
      savedWeaponTints[sanitized] = math.max(0, math.floor(tintIndex))
    end
  end
end

local function setWeaponTintState(weaponCode, tintIndex, persist)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  tintIndex = tonumber(tintIndex)
  if not weaponCode or not tintIndex then return false end
  tintIndex = math.max(0, math.floor(tintIndex))
  savedWeaponTints[weaponCode] = tintIndex
  if persist ~= false then
    persistSavedWeaponTints()
  end
  return true
end

local function applyWeaponTint(ped, weaponHash, weaponCode, tintIndex)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  tintIndex = tonumber(tintIndex)
  if not ped or ped == 0 or not weaponHash or weaponHash == 0 or not weaponCode or not tintIndex then return false end
  tintIndex = math.max(0, math.floor(tintIndex))
  local tintCount = getWeaponTintCount(weaponHash)
  if tintCount <= 1 or tintIndex >= tintCount then return false end
  SetPedWeaponTintIndex(ped, weaponHash, tintIndex)
  return true
end

local function applySavedWeaponTint(ped, weaponHash, weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return false end
  local tintIndex = savedWeaponTints[weaponCode]
  if tintIndex == nil then return false end
  return applyWeaponTint(ped, weaponHash, weaponCode, tintIndex)
end

loadSavedWeaponTints()

local function sanitizePresetEntry(entry)
  if type(entry) ~= 'table' then return nil end
  if type(entry.weaponCode) ~= 'string' then return nil end
  if type(entry.attachments) ~= 'table' then return nil end
  entry.weaponCode = sanitizeWeaponCode(entry.weaponCode)
  if not entry.weaponCode then return nil end
  entry.name = trim(entry.name or '')
  if entry.name == '' then entry.name = nil end
  entry.weaponLabel = trim(entry.weaponLabel or '')
  if entry.weaponLabel == '' then entry.weaponLabel = nil end
  entry.attachments = cloneAttachmentStateTable(entry.attachments)
  entry.tint = entry.tint ~= nil and math.max(0, math.floor(tonumber(entry.tint) or 0)) or nil
  entry.updatedAt = tonumber(entry.updatedAt) or currentPresetTimestamp()
  entry.id = entry.id or string.format('%s_%d_%d', entry.weaponCode, entry.updatedAt, math.random(1000, 9999))
  return entry
end

local function persistSavedWeaponPresets()
  while #savedWeaponPresets > MAX_WEAPON_PRESETS do
    table.remove(savedWeaponPresets, #savedWeaponPresets)
  end
  if not encodeJson then return end
  local ok, encoded = pcall(encodeJson, savedWeaponPresets)
  if ok and encoded then
    SetResourceKvp('exec_weapon_presets', encoded)
  end
end

local function loadSavedWeaponPresets()
  savedWeaponPresets = {}
  if not decodeJson then return end
  local raw = GetResourceKvpString('exec_weapon_presets')
  if not raw or raw == '' then return end
  local ok, data = pcall(decodeJson, raw)
  if not ok or type(data) ~= 'table' then return end
  for _, entry in ipairs(data) do
    local preset = sanitizePresetEntry(entry)
    if preset then
      savedWeaponPresets[#savedWeaponPresets+1] = preset
    end
    if #savedWeaponPresets >= MAX_WEAPON_PRESETS then
      break
    end
  end
end

loadSavedWeaponPresets()

local function weaponCodeFromHash(hash)
  if not hash or hash == 0 then return nil end
  local cached = weaponCodeByHash[hash]
  if cached then return cached end
  for code, _ in pairs(attachmentsByWeapon) do
    local wHash = GetHashKey(code)
    weaponCodeByHash[wHash] = weaponCodeByHash[wHash] or code
    if wHash == hash then
      return code
    end
  end
  return nil
end

local function isWeaponUnlocked(code)
  code = sanitizeWeaponCode(code)
  if not code then return true end
  local override = playerUnlocks[code]
  if override == true then return true end
  if override == false then return false end
  local unlock = addonUnlocks[code]
  if not unlock then return true end
  if unlock.locked == false then return true end
  if unlock.alwaysLocked then return false end
  return true
end

exports('IsWeaponUnlocked', function(weaponCode)
  return isWeaponUnlocked(weaponCode)
end)

getAttachmentState = function(weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return nil end
  local state = savedAttachments[weaponCode]
  if not state then
    state = {}
    savedAttachments[weaponCode] = state
  end
  return state
end

local function applySavedAttachments(ped, weaponHash, weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return end
  local defs = attachmentsByWeapon[weaponCode]
  if not defs or #defs == 0 then return end
  local state = getAttachmentState(weaponCode)
  for _, def in ipairs(defs) do
    local shouldEnable = state[def.component]
    if shouldEnable == nil and def.defaultOn then
      shouldEnable = true
      state[def.component] = true
    end
    if shouldEnable then
      if not HasPedGotWeaponComponent(ped, weaponHash, def.componentHash) then
        GiveWeaponComponentToPed(ped, weaponHash, def.componentHash)
      end
    elseif shouldEnable == false then
      if HasPedGotWeaponComponent(ped, weaponHash, def.componentHash) then
        RemoveWeaponComponentFromPed(ped, weaponHash, def.componentHash)
      end
    end
  end
end

local function setAttachmentState(ped, weaponHash, weaponCode, def, enable)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode or not def then return end
  local defs = attachmentsByWeapon[weaponCode]
  if not defs or #defs == 0 then return end
  local state = getAttachmentState(weaponCode)
  enable = enable and true or false

  if enable and def.slot then
    for _, other in ipairs(defs) do
      if other ~= def and other.slot ~= nil and other.slot == def.slot then
        if HasPedGotWeaponComponent(ped, weaponHash, other.componentHash) then
          RemoveWeaponComponentFromPed(ped, weaponHash, other.componentHash)
        end
        state[other.component] = false
      end
    end
  end

  state[def.component] = enable
  if enable then
    if not HasPedGotWeaponComponent(ped, weaponHash, def.componentHash) then
      GiveWeaponComponentToPed(ped, weaponHash, def.componentHash)
    end
  else
    if HasPedGotWeaponComponent(ped, weaponHash, def.componentHash) then
      RemoveWeaponComponentFromPed(ped, weaponHash, def.componentHash)
    end
  end
end

local function setAttachmentStateForWeapon(weaponCode, attachments)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return nil end
  local state = getAttachmentState(weaponCode)
  for component in pairs(state) do
    state[component] = nil
  end
  if attachments then
    for component, value in pairs(attachments) do
      state[component] = value and true or false
    end
  end
  return state
end

local function getWeaponPresets(weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  local list = {}
  for index, preset in ipairs(savedWeaponPresets) do
    if not weaponCode or preset.weaponCode == weaponCode then
      list[#list+1] = { index = index, preset = preset }
    end
  end
  return list
end

local function captureAttachmentsForWeapon(ped, weaponHash, weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return nil end
  local defs = attachmentsByWeapon[weaponCode]
  local captured = {}
  for _, def in ipairs(defs or {}) do
    local hasComponent = HasPedGotWeaponComponent(ped, weaponHash, def.componentHash)
    captured[def.component] = hasComponent and true or false
  end
  return captured
end

local function newPresetId(weaponCode)
  return string.format('%s_%d_%d', weaponCode or 'weapon', GetGameTimer(), math.random(1000, 9999))
end

local function saveCurrentWeaponPreset(weaponCode, weaponLabel, weaponHash)
  weaponCode = sanitizeWeaponCode(weaponCode)
  if not weaponCode then return false end
  if #savedWeaponPresets >= MAX_WEAPON_PRESETS then
    lib.notify({ title = "Saved Weapons", description = "Preset limit reached.", type = "error" })
    return false
  end
  local ped = PlayerPedId()
  if ped == 0 then return false end
  weaponHash = weaponHash or GetHashKey(weaponCode)
  if not HasPedGotWeapon(ped, weaponHash, false) then
    lib.notify({ title = "Saved Weapons", description = "Equip this weapon before saving.", type = "error" })
    return false
  end
  InventoryBridge.SetCurrentWeapon(ped, weaponHash)
  local captured = captureAttachmentsForWeapon(ped, weaponHash, weaponCode)
  if not captured then
    lib.notify({ title = "Saved Weapons", description = "No attachments to save for this weapon.", type = "error" })
    return false
  end
  local defaultName = string.format("%s %d", weaponLabel or weaponCode, (#savedWeaponPresets % MAX_WEAPON_PRESETS) + 1)
  local input = lib.inputDialog('Save Weapon Preset', {
    { type = 'input', label = 'Preset Name', default = defaultName, max = 24 }
  })
  if not input then return false end
  local name = trim(input[1] or '') or ''
  if name == '' then name = defaultName end
  if #savedWeaponPresets >= MAX_WEAPON_PRESETS then
    lib.notify({ title = "Saved Weapons", description = "Preset limit reached.", type = "error" })
    return false
  end
  local preset = {
    id = newPresetId(weaponCode),
    weaponCode = weaponCode,
    weaponLabel = weaponLabel,
    name = name,
    attachments = captured,
    tint = weaponSupportsTints(weaponHash) and GetPedWeaponTintIndex(ped, weaponHash) or nil,
    updatedAt = currentPresetTimestamp()
  }
  savedWeaponPresets[#savedWeaponPresets+1] = preset
  setAttachmentStateForWeapon(weaponCode, captured)
  if preset.tint ~= nil then
    setWeaponTintState(weaponCode, preset.tint)
  end
  persistSavedWeaponPresets()
  lib.notify({ title = "Saved Weapons", description = string.format("Saved preset '%s'.", name), type = "success" })
  return true
end

local function applyWeaponPreset(preset)
  if not preset then return false end
  local weaponCode = sanitizeWeaponCode(preset.weaponCode)
  if not weaponCode then return false end
  setAttachmentStateForWeapon(weaponCode, preset.attachments)
  if preset.tint ~= nil then
    setWeaponTintState(weaponCode, preset.tint)
  end
  local ped = PlayerPedId()
  if ped == 0 then return false end
  local weaponHash = GetHashKey(weaponCode)
  local hasWeapon = HasPedGotWeapon(ped, weaponHash, false)
  if hasWeapon then
    InventoryBridge.SetCurrentWeapon(ped, weaponHash)
    local defs = attachmentsByWeapon[weaponCode]
    if defs then
      for _, def in ipairs(defs) do
        local desired = preset.attachments and preset.attachments[def.component]
        if desired == nil and def.defaultOn then
          desired = true
        end
        desired = desired and true or false
        setAttachmentState(ped, weaponHash, weaponCode, def, desired)
      end
    end
    if preset.tint ~= nil then
      applyWeaponTint(ped, weaponHash, weaponCode, preset.tint)
    end
    lib.notify({
      title = "Saved Weapons",
      description = string.format("Applied preset '%s'.", preset.name or preset.weaponLabel or weaponCode),
      type = "success"
    })
    preset.updatedAt = currentPresetTimestamp()
    persistSavedWeaponPresets()
    return true
  else
    lib.notify({
      title = "Saved Weapons",
      description = string.format("Preset '%s' ready. Equip %s to apply attachments.", preset.name or weaponCode, preset.weaponLabel or weaponCode),
      type = "inform"
    })
    preset.updatedAt = currentPresetTimestamp()
    persistSavedWeaponPresets()
    return false
  end
end

local openWeaponPresetQuickMenu
local openManageWeaponPresetsMenu
local openSinglePresetManageMenu

openWeaponPresetQuickMenu = function(weaponCode, weaponLabel, parentContextId)
  weaponCode = sanitizeWeaponCode(weaponCode)
  if not weaponCode then return end
  local presets = getWeaponPresets(weaponCode)
  if #presets == 0 then
    lib.notify({ title = "Saved Weapons", description = "No presets saved for this weapon.", type = "inform" })
    return
  end
  local contextId = string.format('exec_weapon_presets_%s', weaponCode)
  local options = {}
  for _, entry in ipairs(presets) do
    local preset = entry.preset
    local title = preset.name or preset.weaponLabel or preset.weaponCode
    options[#options+1] = {
      title = title,
      icon = 'star',
      description = string.format("Apply saved configuration for %s.", preset.weaponLabel or preset.weaponCode),
      onSelect = function()
        applyWeaponPreset(preset)
      end
    }
  end
  lib.registerContext({
    id = contextId,
    title = string.format("Saved Presets - %s", weaponLabel or weaponCode),
    menu = parentContextId,
    options = options
  })
  lib.showContext(contextId)
end

openSinglePresetManageMenu = function(index, weaponCode, weaponLabel, weaponHash, manageContextId, parentContextId)
  local preset = savedWeaponPresets[index]
  if not preset then return end
  local detailId = string.format('exec_weapon_preset_detail_%d', index)
  local options = {}
  options[#options+1] = {
    title = "Apply Preset",
    icon = 'star',
    description = "Apply this preset to your weapon.",
    onSelect = function()
      applyWeaponPreset(preset)
    end
  }
  options[#options+1] = {
    title = "Modify Attachments",
    icon = 'wrench',
    description = "Apply this preset and open the attachments menu.",
    onSelect = function()
      if applyWeaponPreset(preset) then
        SetTimeout(150, function()
          openWeaponAttachmentsMenu()
        end)
      end
    end
  }
  options[#options+1] = {
    title = "Rename Preset",
    icon = 'pen',
    onSelect = function()
      local input = lib.inputDialog('Rename Preset', {
        { type = 'input', label = 'Preset Name', default = preset.name or preset.weaponLabel or preset.weaponCode, max = 24 }
      })
      if not input then return end
      local name = trim(input[1] or '') or ''
      if name == '' then
        lib.notify({ title = "Saved Weapons", description = "Name cannot be empty.", type = "error" })
        return
      end
      preset.name = name
      preset.updatedAt = currentPresetTimestamp()
      persistSavedWeaponPresets()
      lib.notify({ title = "Saved Weapons", description = "Preset renamed.", type = "success" })
      SetTimeout(0, function()
        openSinglePresetManageMenu(index, weaponCode, weaponLabel, weaponHash, manageContextId, parentContextId)
      end)
    end
  }

  local ped = PlayerPedId()
  local sameWeapon = preset.weaponCode == sanitizeWeaponCode(weaponCode)
  local canOverwrite = sameWeapon and ped ~= 0 and HasPedGotWeapon(ped, weaponHash or GetHashKey(preset.weaponCode), false)
  options[#options+1] = {
    title = "Overwrite with Current Setup",
    icon = 'rotate',
    description = canOverwrite and "Replace this preset with your current attachments." or "Equip this weapon to overwrite the preset.",
    disabled = not canOverwrite,
    onSelect = function()
      if not canOverwrite then return end
      local hash = weaponHash or GetHashKey(preset.weaponCode)
      InventoryBridge.SetCurrentWeapon(ped, hash)
      local captured = captureAttachmentsForWeapon(ped, hash, preset.weaponCode)
      if not captured then
        lib.notify({ title = "Saved Weapons", description = "Unable to capture attachments.", type = "error" })
        return
      end
      preset.attachments = captured
      preset.tint = weaponSupportsTints(hash) and GetPedWeaponTintIndex(ped, hash) or nil
      preset.updatedAt = currentPresetTimestamp()
      setAttachmentStateForWeapon(preset.weaponCode, captured)
      if preset.tint ~= nil then
        setWeaponTintState(preset.weaponCode, preset.tint)
      end
      persistSavedWeaponPresets()
      lib.notify({ title = "Saved Weapons", description = "Preset updated.", type = "success" })
      SetTimeout(0, function()
        openSinglePresetManageMenu(index, weaponCode, weaponLabel, weaponHash, manageContextId, parentContextId)
      end)
    end
  }

  options[#options+1] = {
    title = "Delete Preset",
    icon = 'trash',
    description = "Remove this saved preset.",
    onSelect = function()
      if lib.alertDialog({ header = 'Delete Preset', content = 'Delete this saved preset?', centered = true, cancel = true }) ~= 'confirm' then
        return
      end
      table.remove(savedWeaponPresets, index)
      persistSavedWeaponPresets()
      lib.notify({ title = "Saved Weapons", description = "Preset deleted.", type = "inform" })
      SetTimeout(0, function()
        openManageWeaponPresetsMenu(weaponCode, weaponLabel, weaponHash, parentContextId)
      end)
    end
  }

  lib.registerContext({
    id = detailId,
    title = preset.name or preset.weaponLabel or preset.weaponCode,
    menu = manageContextId,
    options = options
  })
  lib.showContext(detailId)
end

openManageWeaponPresetsMenu = function(weaponCode, weaponLabel, weaponHash, parentContextId)
  weaponCode = sanitizeWeaponCode(weaponCode)
  local contextId = weaponCode and string.format('exec_manage_weapon_presets_%s', weaponCode) or 'exec_manage_weapon_presets'
  local options = {}
  if #savedWeaponPresets < MAX_WEAPON_PRESETS then
    options[#options+1] = {
      title = "Save Current Setup",
      icon = 'save',
      description = "Save the currently equipped attachments as a new preset.",
      onSelect = function()
        if saveCurrentWeaponPreset(weaponCode, weaponLabel, weaponHash) then
          SetTimeout(100, function()
            openManageWeaponPresetsMenu(weaponCode, weaponLabel, weaponHash, parentContextId)
          end)
        end
      end
    }
  end

  if #savedWeaponPresets == 0 then
    options[#options+1] = { title = "No presets saved.", disabled = true }
  else
    for index, preset in ipairs(savedWeaponPresets) do
      local title = preset.name or preset.weaponLabel or preset.weaponCode
      options[#options+1] = {
        title = title,
        icon = 'gun',
        description = string.format("Weapon: %s", preset.weaponLabel or preset.weaponCode),
        onSelect = function()
          openSinglePresetManageMenu(index, weaponCode or preset.weaponCode, weaponLabel, weaponHash or GetHashKey(weaponCode or preset.weaponCode), contextId, parentContextId)
        end
      }
    end
  end

  lib.registerContext({
    id = contextId,
    title = string.format("Saved Weapons (%d/%d)", #savedWeaponPresets, MAX_WEAPON_PRESETS),
    menu = parentContextId,
    options = options
  })
  lib.showContext(contextId)
end


local function anyAttachmentAvailable(weaponCode)
  weaponCode = weaponCode and sanitizeWeaponCode(weaponCode) or nil
  if not weaponCode then return false end
  local defs = attachmentsByWeapon[weaponCode]
  return (defs ~= nil and #defs > 0) or weaponSupportsTints(GetHashKey(weaponCode))
end

local function openWeaponTintMenu(weaponCode, weaponLabel, weaponHash, parentContextId)
  weaponCode = sanitizeWeaponCode(weaponCode)
  if not weaponCode or not weaponHash then return end
  local ped = PlayerPedId()
  if ped == 0 or not HasPedGotWeapon(ped, weaponHash, false) then
    return lib.notify({ title = "Tints", description = "Equip this weapon first.", type = "inform" })
  end

  local tintCount = getWeaponTintCount(weaponHash)
  if tintCount <= 1 then
    return lib.notify({ title = "Tints", description = "No tints available for this weapon.", type = "inform" })
  end

  local currentTint = GetPedWeaponTintIndex(ped, weaponHash)
  if savedWeaponTints[weaponCode] ~= nil and savedWeaponTints[weaponCode] ~= currentTint then
    applySavedWeaponTint(ped, weaponHash, weaponCode)
    currentTint = GetPedWeaponTintIndex(ped, weaponHash)
  end

  local contextId = "exec_weapon_tints_" .. weaponCode
  local options = {}
  for tintIndex = 0, tintCount - 1 do
    local label = weaponTintLabel(weaponCode, tintIndex, tintCount)
    local selected = tintIndex == currentTint
    options[#options+1] = {
      title = selected and ("[Selected] " .. label) or label,
      icon = selected and 'check' or 'palette',
      description = selected and "Current tint" or "Apply tint",
      onSelect = function()
        local activePed = PlayerPedId()
        if activePed == 0 then return end
        local currentHash = GetSelectedPedWeapon(activePed)
        if currentHash ~= weaponHash then
          return lib.notify({ title = "Tints", description = "Weapon changed.", type = "warning" })
        end
        if applyWeaponTint(activePed, weaponHash, weaponCode, tintIndex) then
          setWeaponTintState(weaponCode, tintIndex)
          lib.notify({ title = "Tints", description = ("Applied %s."):format(label), type = "success" })
        else
          lib.notify({ title = "Tints", description = "That tint is not supported by this weapon.", type = "error" })
        end
        Wait(50)
        openWeaponTintMenu(weaponCode, weaponLabel, weaponHash, parentContextId)
      end
    }
  end

  lib.registerContext({
    id = contextId,
    title = ("Tints - %s"):format(weaponLabel or weaponCode),
    menu = parentContextId,
    options = options
  })
  lib.showContext(contextId)
end

local function openWeaponAttachmentsMenu()
  local ped = PlayerPedId()
  if ped == 0 then return end
  local weaponHash = GetSelectedPedWeapon(ped)
  if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then
    return lib.notify({ title = "Attachments", description = "Equip a weapon first.", type = "inform" })
  end
  local weaponCode = weaponCodeFromHash(weaponHash)
  if not weaponCode then
    return lib.notify({ title = "Attachments", description = "No attachments available for this weapon.", type = "inform" })
  end
  local defs = attachmentsByWeapon[weaponCode] or {}
  local tintCount = getWeaponTintCount(weaponHash)
  if #defs == 0 and tintCount <= 1 then
    return lib.notify({ title = "Attachments", description = "No attachments or tints configured for this weapon.", type = "inform" })
  end

  local _, weaponLabel = weaponDisplayInfo(weaponCode)
  local contextId = "exec_attachments_" .. weaponCode
  local options = {}
  local state = getAttachmentState(weaponCode)

  if tintCount > 1 then
    local currentTint = GetPedWeaponTintIndex(ped, weaponHash)
    local savedTint = savedWeaponTints[weaponCode]
    if savedTint ~= nil and savedTint ~= currentTint then
      applySavedWeaponTint(ped, weaponHash, weaponCode)
      currentTint = GetPedWeaponTintIndex(ped, weaponHash)
    end
    options[#options+1] = {
      title = "Weapon Tint",
      icon = 'palette',
      description = ("Current: %s"):format(weaponTintLabel(weaponCode, currentTint, tintCount)),
      onSelect = function()
        openWeaponTintMenu(weaponCode, weaponLabel, weaponHash, contextId)
      end
    }
  end

  for _, def in ipairs(defs) do
    local entry = def
    local installed = HasPedGotWeaponComponent(ped, weaponHash, entry.componentHash)
    local saved = state[entry.component]
    if saved == true and not installed then
      GiveWeaponComponentToPed(ped, weaponHash, entry.componentHash)
      installed = true
    elseif saved == false and installed then
      RemoveWeaponComponentFromPed(ped, weaponHash, entry.componentHash)
      installed = false
    elseif saved == nil and entry.defaultOn and not installed then
      GiveWeaponComponentToPed(ped, weaponHash, entry.componentHash)
      installed = true
      state[entry.component] = true
    end
    local title = installed and ("[Equipped] " .. entry.label) or entry.label
    local description = installed and "Remove attachment" or "Equip attachment"
    options[#options+1] = {
      title = title,
      icon = installed and 'check' or 'plus',
      description = description,
      onSelect = function()
        local activePed = PlayerPedId()
        if activePed == 0 then return end
        local currentHash = GetSelectedPedWeapon(activePed)
        if not currentHash or currentHash == `WEAPON_UNARMED` then
          return lib.notify({ title = "Attachments", description = "Weapon changed.", type = "warning" })
        end
        local enable = not HasPedGotWeaponComponent(activePed, currentHash, entry.componentHash)
        setAttachmentState(activePed, currentHash, weaponCode, entry, enable)
        lib.notify({
          title = "Attachments",
          description = string.format("%s %s", enable and "Equipped" or "Removed", entry.label),
          type = enable and "success" or "inform"
        })
        Wait(50)
        openWeaponAttachmentsMenu()
      end
    }
  end

  local presetsForWeapon = getWeaponPresets(weaponCode)
  if #presetsForWeapon > 0 then
    options[#options+1] = {
      title = "Apply Saved Preset",
      icon = 'star',
      description = "Apply one of your saved setups.",
      onSelect = function()
        openWeaponPresetQuickMenu(weaponCode, weaponLabel, contextId)
      end
    }
  end

  options[#options+1] = {
    title = "Clear Attachments",
    icon = 'rotate-left',
    description = "Remove all applied attachments.",
    onSelect = function()
      local activePed = PlayerPedId()
      if activePed == 0 then return end
      local currentHash = GetSelectedPedWeapon(activePed)
      if not currentHash or currentHash == `WEAPON_UNARMED` then
        return lib.notify({ title = "Attachments", description = "Weapon changed.", type = "warning" })
      end
      for _, entry in ipairs(defs) do
        if HasPedGotWeaponComponent(activePed, currentHash, entry.componentHash) then
          setAttachmentState(activePed, currentHash, weaponCode, entry, false)
        end
      end
      lib.notify({ title = "Attachments", description = "All attachments cleared.", type = "inform" })
      Wait(75)
      openWeaponAttachmentsMenu()
    end
  }

  local remainingSlots = math.max(0, MAX_WEAPON_PRESETS - #savedWeaponPresets)
  options[#options+1] = {
    title = "Save Current Setup",
    icon = 'save',
    description = remainingSlots > 0 and string.format("Save this configuration (%d slot%s remaining).", remainingSlots, remainingSlots == 1 and "" or "s") or "Preset limit reached.",
    disabled = remainingSlots <= 0,
    onSelect = function()
      if saveCurrentWeaponPreset(weaponCode, weaponLabel, weaponHash) then
        SetTimeout(100, openWeaponAttachmentsMenu)
      end
    end
  }

  options[#options+1] = {
    title = "Manage Saved Weapons",
    icon = 'list',
    description = "Rename, delete, or modify saved presets.",
    onSelect = function()
      openManageWeaponPresetsMenu(weaponCode, weaponLabel, weaponHash, contextId)
    end
  }

  lib.registerContext({ id = contextId, title = ("Attachments - %s"):format(weaponLabel), options = options })
  lib.showContext(contextId)
end

AddEventHandler('exec:loadout:equippedWeapon', function(weaponHash, weaponCode)
  local ped = PlayerPedId()
  if ped == 0 then return end
  if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return end
  weaponCode = weaponCode or weaponCodeFromHash(weaponHash)
  applySavedAttachments(ped, weaponHash, weaponCode)
  applySavedWeaponTint(ped, weaponHash, weaponCode)
end)

AddEventHandler('exec:weapon:restoredWeapon', function(weaponHash)
  local ped = PlayerPedId()
  if ped == 0 then return end
  if not weaponHash or weaponHash == 0 or weaponHash == `WEAPON_UNARMED` then return end
  applySavedWeaponTint(ped, weaponHash, weaponCodeFromHash(weaponHash))
end)

local sessionRules = (gcfg.session and gcfg.session.brackets) or {}
local TEAM_LABELS = { alpha = 'Team A', bravo = 'Team B' }

local function bracketRule(bracket)
  return sessionRules and sessionRules[bracket] or nil
end

local function bracketCap(bracket)
  local rule = bracketRule(bracket)
  if rule and rule.max then return rule.max end
  if bracket == '1v1' then return 2 end
  if bracket == '2v2' then return 4 end
  if bracket == '3v3' then return 6 end
  if bracket == 'gangwar' then return 20 end
  if bracket == '5v5' then return 20 end
  return 24
end

local function bracketMin(bracket)
  local rule = bracketRule(bracket)
  if rule and rule.min then return rule.min end
  if bracket == '1v1' then return 2 end
  if bracket == '2v2' then return 4 end
  if bracket == '3v3' then return 6 end
  if bracket == 'gangwar' then return 10 end
  if bracket == '5v5' then return 10 end
  local cap = bracketCap(bracket)
  return math.max(2, math.floor(cap / 2))
end


local function findLocationConfig(locKey)
  if not locKey then return nil, nil end
  if cfgA.groups then
    for gKey, g in pairs(cfgA.groups) do
      if g.locations and g.locations[locKey] then
        return g.locations[locKey], gKey
      end
    end
  elseif cfgA.city and cfgA.city[locKey] then
    return cfgA.city[locKey], 'city'
  end
  return nil, nil
end

local function horizontalDistance(a, b)
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  return math.sqrt(dx * dx + dy * dy)
end
local function ensureVector3(v)
  if v == nil then return nil end

  -- FiveM usually returns "vector3" from type(), but some builds say "userdata"
  if type(v) == 'vector3' then return v end
  if type(v) == 'userdata' and v.x and v.y and v.z then return v end

  if type(v) == 'table' then
    local x = (v.x ~= nil) and v.x or v[1]
    local y = (v.y ~= nil) and v.y or v[2]
    local z = (v.z ~= nil) and v.z or v[3]
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then return vector3(x, y, z) end
    return nil
  end

  -- optional: parse "x,y,z" or "x y z"
  if type(v) == 'string' then
    local sx, sy, sz = v:match('^%s*(-?[%d%.]+)%s*[, ]%s*(-?[%d%.]+)%s*[, ]%s*(-?[%d%.]+)%s*$')
    local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
    if x and y and z then return vector3(x, y, z) end
  end

  return nil
end

local currentSession

local function buildZoneContext(locationKey, rawZone)
  local loc, configGroup = findLocationConfig(locationKey or (rawZone and rawZone.location))
  local zone = {
    location = locationKey or (rawZone and rawZone.location),
    groupKey = configGroup,
    center = nil,
    heading = nil,
    domeRadius = nil,
    arenaRadius = nil,
    sessionRadius = nil,
    sessionBuffer = nil,
    spawns = nil,
  }

  if rawZone and type(rawZone) == 'table' then
    zone.location = zone.location or rawZone.location or rawZone.locKey
    zone.groupKey = rawZone.groupKey or rawZone.group or rawZone.group_key or zone.groupKey
    zone.center = ensureVector3(rawZone.center) or zone.center
    zone.heading = rawZone.heading or zone.heading
    zone.domeRadius = tonumber(rawZone.domeRadius) or zone.domeRadius
    zone.arenaRadius = tonumber(rawZone.arenaRadius) or zone.arenaRadius
    zone.sessionRadius = tonumber(rawZone.sessionRadius) or zone.sessionRadius
    zone.sessionBuffer = tonumber(rawZone.sessionBuffer) or zone.sessionBuffer
    if type(rawZone.spawns) == 'table' and #rawZone.spawns > 0 then
      zone.spawns = {}
      for i = 1, #rawZone.spawns do
        local vec = ensureVector3(rawZone.spawns[i])
        if vec then
          zone.spawns[#zone.spawns + 1] = vec
        end
      end
      if #zone.spawns == 0 then zone.spawns = nil end
    end
  end

  if loc then
    zone.location = zone.location or locationKey
    zone.groupKey = zone.groupKey or configGroup
    zone.center = zone.center or ensureVector3(loc.center)
    zone.heading = zone.heading or loc.heading
    zone.domeRadius = zone.domeRadius or tonumber(loc.domeRadius)
    zone.arenaRadius = zone.arenaRadius or tonumber(loc.arenaRadius)
    zone.sessionRadius = zone.sessionRadius or tonumber(loc.sessionRadius)
    zone.sessionBuffer = zone.sessionBuffer or tonumber(loc.sessionBuffer)
    if not zone.spawns and type(loc.spawns) == 'table' and #loc.spawns > 0 then
      zone.spawns = {}
      for i = 1, #loc.spawns do
        local vec = ensureVector3(loc.spawns[i])
        if vec then
          zone.spawns[#zone.spawns + 1] = vec
        end
      end
      if #zone.spawns == 0 then zone.spawns = nil end
    end
  end

  if not zone.center then return nil end
  return zone
end

local function isCombatDomeActive(zone)
  return combatDomeCfg.enabled ~= false
    and type(zone) == 'table'
    and zone.center ~= nil
    and tonumber(zone.domeRadius) ~= nil
    and tonumber(zone.domeRadius) > 0
end

local function markerBoundaryRadius(zone)
  if not zone then return nil end
  local markerCfg = (gcfg and gcfg.zoneMarker) or {}
  local scale = tonumber(markerCfg.radiusScale) or 1.0
  local radius = nil
  if isCombatDomeActive(zone) then
    radius = (tonumber(zone.domeRadius) or 25.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75)
  else
    radius = tonumber(zone.domeRadius) or tonumber(zone.sessionRadius) or tonumber(zone.arenaRadius) or 25.0
  end
  return radius * scale
end

local function domeNotifyAllowed()
  local now = GetGameTimer()
  local cooldown = tonumber(combatDomeCfg.notifyCooldownMs) or 3000
  local lastAt = currentSession and currentSession.lastBoundaryNotifyAt or 0
  if lastAt ~= 0 and (now - lastAt) < cooldown then
    return false
  end
  if currentSession then
    currentSession.lastBoundaryNotifyAt = now
  end
  return true
end

local function notifyCombatDome(description, typ, gated)
  if gated and not domeNotifyAllowed() then return end
  lib.notify({
    title = 'Combat Dome',
    description = description,
    type = typ or 'inform'
  })
end

local function resetCombatDomeState()
  currentSession.combatEntered = false
  currentSession.lastBoundarySnapAt = 0
  currentSession.lastBoundaryNotifyAt = 0
  currentSession.entryNotified = false
end

local function setCurrentSessionZone(zone)
  if currentSession then
    currentSession.zone = zone
  end
  return zone
end

local function getCurrentSessionZone(rawZone)
  if not currentSession or not currentSession.location then return nil end
  if rawZone then
    return setCurrentSessionZone(buildZoneContext(currentSession.location, rawZone))
  end
  return currentSession.zone or setCurrentSessionZone(buildZoneContext(currentSession.location, nil))
end

local function resolveGroundPoint(point, zHint)
  if not point then return nil end
  local x, y = point.x + 0.0, point.y + 0.0
  local z = (point.z or zHint or 0.0) + 0.0
  local ok, ground = GetGroundZFor_3dCoord(x, y, (zHint or z) + 20.0, false)
  if ok then
    z = ground + 0.65
  end
  return vector3(x, y, z)
end

local function computeFallbackOuterShellSpawn(zone)
  if not zone or not zone.center then return nil end
  local domeRadius = tonumber(zone.domeRadius) or 0.0
  local innerBuffer = (((gcfg or {}).respawn or {}).spawn or {}).innerBuffer or 5.0
  local edgeBuffer = (((gcfg or {}).respawn or {}).spawn or {}).edgeBuffer or 4.0
  local inner = domeRadius + innerBuffer
  local outer = math.max(inner + 4.0, (tonumber(zone.arenaRadius) or (inner + 20.0)) - edgeBuffer)
  local radius = inner + ((outer - inner) * 0.45)
  local angle = math.random() * math.pi * 2.0
  return resolveGroundPoint(vector3(
    zone.center.x + math.cos(angle) * radius,
    zone.center.y + math.sin(angle) * radius,
    zone.center.z
  ), zone.center.z)
end

local function requestArenaSpawnPoint(zone)
  if not zone or not zone.center then return nil end
  local zoneData = {
    center = zone.center,
    heading = zone.heading,
    domeRadius = zone.domeRadius,
    arenaRadius = zone.arenaRadius,
    sessionRadius = zone.sessionRadius,
    sessionBuffer = zone.sessionBuffer,
    spawns = zone.spawns,
    groupKey = zone.groupKey,
    location = zone.location,
    locKey = zone.location,
  }
  local ok, result = pcall(function()
    return exports.exec_framework:GetRandomRespawnPoint(zoneData)
  end)
  result = ok and ensureVector3(result) or nil
  if result then
    return resolveGroundPoint(result, zone.center.z)
  end
  if isCombatDomeActive(zone) and combatDomeCfg.respawnOutside ~= false then
    return computeFallbackOuterShellSpawn(zone)
  end
  if zone.spawns and #zone.spawns > 0 then
    return resolveGroundPoint(zone.spawns[math.random(#zone.spawns)], zone.center.z)
  end
  return resolveGroundPoint(zone.center, zone.center.z)
end

local function requestMatchmakingSpawnPoint(zone)
  if not zone or not zone.center then return nil end
  local radius = markerBoundaryRadius(zone)
  if zone.spawns and #zone.spawns > 0 then
    local candidates = {}
    for i = 1, #zone.spawns do
      local spawn = zone.spawns[i]
      if not radius or horizontalDistance(spawn, zone.center) <= math.max(1.0, radius - 1.0) then
        candidates[#candidates + 1] = spawn
      end
    end
    if #candidates > 0 then
      return resolveGroundPoint(candidates[math.random(#candidates)], zone.center.z)
    end
  end
  return resolveGroundPoint(zone.center, zone.center.z)
end

local function placePedAtArenaPoint(ped, point, heading)
  return SpawnBridge.PlacePed(ped, point, heading)
end

local function computeCombatReturnPoint(zone, position)
  if not zone or not zone.center then return nil end
  local center = zone.center
  local inset = tonumber(combatDomeCfg.returnInset) or 1.5
  local targetRadius = math.max(1.0, (tonumber(zone.domeRadius) or 0.0) - inset)
  local dx = (position.x or center.x) - center.x
  local dy = (position.y or center.y) - center.y
  local magnitude = math.sqrt((dx * dx) + (dy * dy))
  if magnitude < 0.001 then
    dx, dy, magnitude = 1.0, 0.0, 1.0
  end
  local point = vector3(
    center.x + ((dx / magnitude) * targetRadius),
    center.y + ((dy / magnitude) * targetRadius),
    center.z
  )
  return resolveGroundPoint(point, center.z)
end

local function computeZoneReturnPoint(zone, position, radius)
  if not zone or not zone.center then return nil end
  local center = zone.center
  local targetRadius = math.max(1.0, (tonumber(radius) or 1.0) - 1.5)
  local dx = (position.x or center.x) - center.x
  local dy = (position.y or center.y) - center.y
  local magnitude = math.sqrt((dx * dx) + (dy * dy))
  if magnitude < 0.001 then
    dx, dy, magnitude = 1.0, 0.0, 1.0
  end
  return resolveGroundPoint(vector3(
    center.x + ((dx / magnitude) * targetRadius),
    center.y + ((dy / magnitude) * targetRadius),
    center.z
  ), center.z)
end

local function defaultSessionState(overrides)
  local state = {
    active=false, sessionId=nil, team=nil, isHost=false, isTeamLeader=false, hardcore=false, teams=nil, bracket=nil, location=nil, mode=nil, private=false,
    zone=nil, combatEntered=false, lastBoundarySnapAt=0, lastBoundaryNotifyAt=0, entryNotified=false, isPlayground=false,
  }
  if type(overrides) == 'table' then
    for key, value in pairs(overrides) do
      state[key] = value
    end
  end
  return state
end

local function setSessionState(overrides)
  currentSession = defaultSessionState(overrides)
  return currentSession
end

local function clearSessionState()
  return setSessionState()
end

local function isSessionMatchmaking()
  return currentSession and currentSession.sessionId ~= nil and not currentSession.active and not currentSession.isPlayground
end

local function hasArenaState()
  return currentSession and (currentSession.active or currentSession.isPlayground or currentSession.sessionId ~= nil) and currentSession.location ~= nil
end

local function isLiveSessionMatch()
  return currentSession and currentSession.active and currentSession.sessionId ~= nil and not currentSession.isPlayground
end

currentSession = defaultSessionState()
local preMatchLocked = false
local preMatchLockToken = 0

local function setPreMatchLocked(flag)
  local ped = PlayerPedId()
  preMatchLocked = flag and true or false
  if ped ~= 0 then
    FreezeEntityPosition(ped, preMatchLocked)
    SetPlayerControl(PlayerId(), not preMatchLocked, 0)
    if not preMatchLocked then
      ClearPedTasksImmediately(ped)
      SetEntityVelocity(ped, 0.0, 0.0, 0.0)
    end
  end
end

local function startPreMatchLock()
  preMatchLockToken = preMatchLockToken + 1
  setPreMatchLocked(true)
  TriggerEvent('exec:passive:start', 0, 'session-start', {
    forceUnarmed = false,
    opaque = true,
  })
  local token = preMatchLockToken
  CreateThread(function()
    while preMatchLocked and token == preMatchLockToken do
      Wait(0)
      local ped = PlayerPedId()
      if ped ~= 0 then
        FreezeEntityPosition(ped, true)
      end
      DisableAllControlActions(0)
      EnableControlAction(0, 1, true)   -- look left/right
      EnableControlAction(0, 2, true)   -- look up/down
      EnableControlAction(0, 245, true) -- chat
      EnableControlAction(0, 200, true) -- pause
      DisablePlayerFiring(PlayerId(), true)
    end
  end)
end

local function stopPreMatchLock()
  preMatchLockToken = preMatchLockToken + 1
  TriggerEvent('exec:passive:stop', 'session-start')
  setPreMatchLocked(false)
  CreateThread(function()
    local untilAt = GetGameTimer() + 1250
    while GetGameTimer() < untilAt do
      local ped = PlayerPedId()
      if ped ~= 0 then
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true, 0)
        EnableAllControlActions(0)
      end
      Wait(0)
    end
  end)
end

local function applySessionSnapshot(snapshot)
  if not snapshot or not currentSession then return end

  currentSession.sessionId = snapshot.sessionId or currentSession.sessionId
  currentSession.active = snapshot.active and true or false
  if snapshot.private ~= nil then
    currentSession.private = snapshot.private and true or false
  end
  currentSession.host = snapshot.host or currentSession.host
  currentSession.countdown = snapshot.countdown or currentSession.countdown
  currentSession.hardcore = snapshot.hardcore and true or false
  currentSession.players = snapshot.players or currentSession.players
  currentSession.minPlayers = snapshot.min or currentSession.minPlayers
  currentSession.maxPlayers = snapshot.max or currentSession.maxPlayers
  currentSession.firstTo = tonumber(snapshot.firstTo) or currentSession.firstTo
  currentSession.bracket = snapshot.bracket or currentSession.bracket
  currentSession.mode = snapshot.mode or currentSession.mode
  if snapshot.location and snapshot.location ~= currentSession.location then
    currentSession.location = snapshot.location
    currentSession.zone = nil
  elseif snapshot.location then
    currentSession.location = snapshot.location
  end
  if snapshot.zone then
    currentSession.zone = buildZoneContext(currentSession.location, snapshot.zone) or currentSession.zone
  end
  currentSession.teams = snapshot.teams or currentSession.teams
  currentSession.teamSize = snapshot.teamSize or currentSession.teamSize
  currentSession.balanced = snapshot.balanced

  local myId = GetPlayerServerId(PlayerId())
  currentSession.isHost = snapshot.host == myId
  currentSession.isTeamLeader = false
  local teamKey = nil

  if snapshot.teams then
    for _, team in ipairs(snapshot.teams) do
      if team.members then
        for _, member in ipairs(team.members) do
          if member.id == myId then
            teamKey = team.key
            if member.leader then currentSession.isTeamLeader = true end
            if member.host then currentSession.isHost = true end
          end
        end
      end
    end
  end

  if teamKey then
    currentSession.team = teamKey
  end
end

local recentKillVictims = {}

local PASSIVE_REASON_OOB = 'session-oob'
local PASSIVE_GHOST_ALPHA = 120
local sessionOutOfBounds = false
local hubPassive = false
local appearanceMenuOpen = false
CreateThread(function()
  Wait(0)
  SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
  SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0)
end)

local function updateGhostVisual()
  local ped = PlayerPedId()
  if ped == 0 then return end
  if appearanceMenuOpen then
    ResetEntityAlpha(ped)
  elseif sessionOutOfBounds or hubPassive then
    SetEntityAlpha(ped, PASSIVE_GHOST_ALPHA, false)
  else
    ResetEntityAlpha(ped)
  end
end

local function setAppearanceMenuPassive(flag)
  if appearanceMenuOpen == flag then return end
  appearanceMenuOpen = flag
  if flag then
    TriggerEvent('exec:passive:start', 0, 'appearance-menu', {
      allowControls = true,
      opaque = true,
      forceUnarmed = false,
    })
  else
    TriggerEvent('exec:passive:stop', 'appearance-menu')
  end
  updateGhostVisual()
end

local function setSessionOutOfBounds(flag)
  if sessionOutOfBounds == flag then return end
  sessionOutOfBounds = flag
  if flag then
    TriggerEvent('exec:passive:start', 0, PASSIVE_REASON_OOB, {
      alpha = PASSIVE_GHOST_ALPHA,
      forceUnarmed = false,
    })
  else
    TriggerEvent('exec:passive:stop', PASSIVE_REASON_OOB)
  end
  updateGhostVisual()
end

local function setHubPassive(flag)
  if hubPassive == flag then return end
  hubPassive = flag
  if flag then
    TriggerEvent('exec:passive:start', 0, 'hub-passive', {
      allowControls = true,
      alpha = PASSIVE_GHOST_ALPHA,
      forceUnarmed = false,
    })
    SetPlayerWeaponDamageModifier(PlayerId(), 0.0)
    SetPlayerMeleeWeaponDamageModifier(PlayerId(), 0.0)
  else
    TriggerEvent('exec:passive:stop', 'hub-passive')
    SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
    SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0)
  end
  TriggerEvent('exec:hub:state', hubPassive)
  updateGhostVisual()
end

local function pickCitySpawn(zone)
  local candidates = zone.spawns
  if not candidates or #candidates == 0 then
    local radius = math.max(4.0, (zone.domeRadius or 25.0) * 0.55)
    candidates = {
      vector3(zone.center.x + radius, zone.center.y, zone.center.z),
      vector3(zone.center.x - radius, zone.center.y, zone.center.z),
      vector3(zone.center.x, zone.center.y + radius, zone.center.z),
      vector3(zone.center.x, zone.center.y - radius, zone.center.z)
    }
  end
  local choice = candidates[math.random(#candidates)]
  if not choice then return zone.center end
  local x, y, z = choice.x + 0.0, choice.y + 0.0, choice.z + 0.0
  local ok, ground = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
  if ok then
    z = ground + 0.65
  end
  return vector3(x, y, z)
end

-- === counts for menus ===
local function getCounts(cb)
  lib.callback("exec:getCountsSummary", false, function(sum)
    cb(sum or { totals = {}, ffa = {} })
  end)
end

-- Allowed categories for client menus (Sandbox = all)
local function computeAllowedCategoriesForClient(context)
  local cats = nil
  if context.mode ~= "sandbox" then
    local locTbl = nil
    if cfgA.groups then
      for _, g in pairs(cfgA.groups) do
        if g.locations and g.locations[context.location or ""] then locTbl = g.locations[context.location]; break end
      end
    else
      locTbl = cfgA.city and cfgA.city[context.location or ""]
    end

    if locTbl then
      if context.type == "playground" then
        cats = locTbl.restrictions and locTbl.restrictions.playground and locTbl.restrictions.playground.categories
      else
        local key = (context.private and "private") or "public"
        cats = locTbl.restrictions and locTbl.restrictions.session and locTbl.restrictions.session[key] and locTbl.restrictions.session[key].categories
      end
    end
  end

  return expandCategoriesList(cats)
end

-- Uniform lock info:
--  - Any categoryLock => filter menu to that single category (menu enabled)
--  - weaponLock       => hard-lock (menu disabled)
--  - Gun Game         => hard-lock (menu disabled)
local function getModeLockInfo()
  local mode = currentSession.mode
  if not mode then return nil end
  local m = cfg.modes and cfg.modes[mode]

  if mode == "gun_game" then
    return { type="hard", reason="Gun Game locks progression weapons" }
  end

  if m and m.weaponLock then
    return { type="hard", reason="Locked to specific weapon" }
  end

  if m and m.categoryLock then
    local cat = ALL_CATEGORIES[m.categoryLock]
    local label = (cat and cat.label) or m.categoryLock
    return { type="filter", key=m.categoryLock, reason=("Locked to %s"):format(label) }
  end
  return nil
end

local function openCategoryWeaponsMenu(categoryKey)
  local cat = ALL_CATEGORIES[categoryKey]
  if not cat then return end

  local familyKeys = collectCategoryFamily(categoryKey)
  if cat.group == "addon" then
    familyKeys = { categoryKey }
  end
  local opts = {}
  local seenWeapons = {}
  local parentContextId = "exec_weapons_" .. categoryKey

  local function equipWeaponSelection(sourceKey, code, label, unlockMeta)
    if not code then return end
    if not isWeaponUnlocked(code) then
      local reason = (unlockMeta and unlockMeta.hint) or 'Purchase required to unlock.'
      lib.notify({ title="Loadout", description=reason, type="error" })
      return
    end
    TriggerServerEvent("exec:setPreferredCategory", sourceKey, code)
    TriggerEvent("exec:applyLoadout", currentSession.mode or "sandbox", currentSession.active, sourceKey, code)
    lib.notify({ title="Loadout", description=("Selected %s"):format(label), type="success" })
    if parentContextId then
      SetTimeout(200, function()
        lib.showContext(parentContextId)
      end)
    end
  end

  local function openWeaponActionMenu(sourceKey, code, label, unlocked, unlockMeta)
    local actionContextId = ("exec_weapon_action_%s_%s"):format(sourceKey or "base", code or "weapon")
    local options = {
      {
        title = "Preview Weapon",
        icon = "eye",
        description = "Inspect the 3D model and attachments",
        onSelect = function()
          weaponPreviewState.returnContext = parentContextId
          if lib and lib.hideContext then
            lib.hideContext()
          end
          openWeaponPreview(code, label)
        end
      }
    }

    if unlocked then
      options[#options+1] = {
        title = "Equip Weapon",
        icon = "gun",
        description = "Apply this weapon to your loadout",
        onSelect = function()
          equipWeaponSelection(sourceKey, code, label, unlockMeta)
        end
      }
    else
      options[#options+1] = {
        title = "Locked",
        icon = "lock",
        description = (unlockMeta and unlockMeta.hint) or 'Purchase required to unlock.',
        disabled = true
      }
    end

    lib.registerContext({
      id = actionContextId,
      title = ("%s Options"):format(label or code),
      menu = parentContextId,
      options = options
    })
    lib.showContext(actionContextId)
  end

  local function appendWeapon(sourceKey, weaponEntry)
    local weaponCode = weaponEntry
    local labelOverride = nil
    local descriptionOverride = nil
    if type(weaponEntry) == 'table' then
      weaponCode = weaponEntry.code or weaponEntry.weapon or weaponEntry[1]
      labelOverride = weaponEntry.label
      descriptionOverride = weaponEntry.description
    end
    local code, label = weaponDisplayInfo(weaponCode)
    if labelOverride then label = labelOverride end
    if code and not seenWeapons[code] then
      seenWeapons[code] = true
      local unlocked = isWeaponUnlocked(code)
      local unlockMeta = addonUnlocks[code]
      local optionTitle = label
      if not unlocked then
        optionTitle = label .. " [Locked]"
      end
      local description = descriptionOverride or (type(code) == 'string' and code or nil)
      local sourceLabel = nil
      if sourceKey ~= categoryKey then
        local sourceCat = ALL_CATEGORIES[sourceKey]
        sourceLabel = (sourceCat and sourceCat.label) or sourceKey
      end
      if sourceLabel then
        if description then
          description = ("%s | %s"):format(description, sourceLabel)
        else
          description = sourceLabel
        end
      end
      if not unlocked then
        description = (unlockMeta and unlockMeta.hint) or description or 'Purchase required to unlock.'
      end
      local hint = "Select for preview/equip options"
      if description and #description > 0 then
        description = ("%s\n%s"):format(description, hint)
      else
        description = hint
      end
      opts[#opts+1] = {
        title = optionTitle,
        description = description,
        icon = unlocked and "gun" or "lock",
        onSelect=function()
          if not code then return end
          openWeaponActionMenu(sourceKey, code, label, unlocked, unlockMeta)
        end
      }
    end
  end

  for _, key in ipairs(familyKeys) do
    local familyCat = ALL_CATEGORIES[key]
    if familyCat then
      for _, weaponEntry in ipairs(familyCat.weapons or {}) do
        appendWeapon(key, weaponEntry)
      end
    end
  end

  if #opts == 0 then
    lib.notify({ title="Weapons", description="No weapons available for this category.", type="inform" })
    return
  end

  lib.registerContext({ id="exec_weapons_"..categoryKey, title=cat.label or categoryKey, options=opts })
  lib.showContext("exec_weapons_"..categoryKey)
end

local function createCategoryOption(categoryKey, allowedSet)
  local cat = ALL_CATEGORIES[categoryKey]
  if not cat then return nil end
  local allowedNow = not allowedSet or allowedSet[categoryKey]
  return {
    title = (cat.label or categoryKey) .. (allowedNow and "" or "  [locked]"),
    description = allowedNow and (cat.description or "Select and re-equip") or "Restricted here",
    icon = cat.icon or "crosshairs",
    disabled = not allowedNow,
    onSelect = function()
      if not allowedNow then return end
      openCategoryWeaponsMenu(categoryKey)
    end
  }
end

local function openCategoryGroupMenu(groupKey, allowedSet)
  local group = CATEGORY_GROUPS[groupKey]
  if not group then return end
  local opts = {}
  for _, catKey in ipairs(group.keys or {}) do
    local entry = createCategoryOption(catKey, allowedSet)
    if entry then
      opts[#opts+1] = entry
    end
  end
  if #opts == 0 then
    lib.notify({ title="Weapons", description="No categories available in this group.", type="inform" })
    return
  end
  local id = "exec_weapons_group_"..groupKey
  lib.registerContext({
    id = id,
    title = group.label or ("Group: " .. groupKey),
    options = opts
  })
  lib.showContext(id)
end

-- Weapons menu honoring uniform locks
local function openWeaponsMenu()
  local context = {
    type     = (currentSession.active and "session" or "playground"),
    private  = currentSession.active and (currentSession.private==true),
    location = currentSession.location,
    mode     = currentSession.mode
  }

  local lock = getModeLockInfo()
  if lock and lock.type == "hard" then
    lib.notify({ title="Weapons", description=("Disabled: %s"):format(lock.reason), type="warning" })
    return
  end

  local allowed, allowedSet = computeAllowedCategoriesForClient(context)
  allowedSet = allowedSet or {}

  if lock and lock.type == "filter" and lock.key then
    allowed, allowedSet = expandCategoriesList({ lock.key })
    allowedSet = allowedSet or {}
  end

  local options = {}
  local categoryKeys = {}
  for key,_ in pairs(ALL_CATEGORIES) do
    local cat = ALL_CATEGORIES[key]
    if cat and cat.group == "addon" then
      categoryKeys[#categoryKeys+1] = key
    end
  end
  table.sort(categoryKeys)

  local grouped = {}
  for _, key in ipairs(categoryKeys) do
    local cat = ALL_CATEGORIES[key]
    if cat then
      if cat.group and CATEGORY_GROUPS[cat.group] then
        if not grouped[cat.group] then
          grouped[cat.group] = true
          local group = CATEGORY_GROUPS[cat.group]
          local anyAllowed = false
          for _, childKey in ipairs(group.keys) do
            if allowedSet[childKey] then
              anyAllowed = true
              break
            end
          end
          options[#options+1] = {
            title = group.label or ("Group: " .. cat.group),
            description = group.description or "Additional loadouts",
            icon = group.icon or "star",
            disabled = not anyAllowed,
            onSelect = function()
              if not anyAllowed then return end
              openCategoryGroupMenu(cat.group, allowedSet)
            end
          }
        end
      else
        local option = createCategoryOption(key, allowedSet)
        if option then
          options[#options+1] = option
        end
      end
    end
  end

  local title = "Weapons"
  if lock and lock.type == "filter" and lock.reason then title = title .. " - " .. lock.reason end
  lib.registerContext({ id="exec_weapons", title=title, options=options })
  lib.showContext("exec_weapons")
end

local function openSkinMenu()
  if isLiveSessionMatch() then
    return lib.notify({ title = "Appearance", description = "Appearance is disabled during live matches.", type = "error" })
  end

  if not AppearanceBridge.IsAvailable() then
    return lib.notify({ title = "Appearance", description = "Appearance menu unavailable.", type = "error" })
  end
  if appearanceMenuOpen then return end

  local citizenId = nil
  local state = LocalPlayer and LocalPlayer.state
  if state then
    local cid = state.execCitizenId
    if type(cid) == 'string' and cid ~= '' then citizenId = cid end
  end

  setAppearanceMenuPassive(true)
  local ok, err = AppearanceBridge.Open(function(app)
    setAppearanceMenuPassive(false)
    updateGhostVisual()
    if not app then
      return lib.notify({ title = "Appearance", description = "No changes applied.", type = "inform" })
    end
    if citizenId then
      AppearanceBridge.Save(citizenId, app)
      lib.notify({ title = "Appearance", description = "Appearance saved.", type = "success" })
    else
      lib.notify({ title = "Appearance", description = "Applied locally (no character id to save).", type = "inform" })
    end
  end)
  if not ok then
    setAppearanceMenuPassive(false)
    lib.notify({ title = "Appearance", description = "Failed to open appearance menu.", type = "error" })
    print(('[exec_framework] failed to open appearance menu: %s'):format(err))
  end
end

-- Location menu (Playground + Sessions)
local function openLocationMenu(locKey)
  local loc = nil
  if cfg.groups then
    for _, g in pairs(cfg.groups) do
      if g.locations and g.locations[locKey] then loc = g.locations[locKey] break end
    end
  else
    loc = cfg.city[locKey]
  end
  if not loc then return end

  getCounts(function(sum)
    local totalHere = (sum.totals and sum.totals[locKey]) or 0
    local modeOpts = {}
    for _, mKey in ipairs(loc.supports or {}) do
      local modeDef = cfg.modes[mKey]
      if modeDef then
        local ffaCount = (sum.ffa and sum.ffa[locKey] and sum.ffa[locKey][mKey]) or 0
        modeOpts[#modeOpts+1] = {
          title = ("%s (Playground)"):format(modeDef.label),
          icon="gamepad",
          description = ("Drop-in FFA - %d playing here"):format(ffaCount),
          onSelect = function()
            lib.callback("exec:joinPlayground", false, function(res)
              if not res or not res.ok then
                lib.notify({title="Join Failed", description=res and res.error or "Unknown error", type="error"})
              end
            end, { location = locKey, mode = mKey })
          end
        }
      else
        print(("[exec_framework] Unknown mode '%s' referenced by location '%s'"):format(tostring(mKey), tostring(locKey)))
      end
    end

    local brackets = {}
    for _, b in ipairs(cfg.brackets) do
      if b.key ~= "ffa" then
        brackets[#brackets+1] = {
          title = b.label,
          icon  = "users",
          description = ("Sessions in zone: %d | Need %d to launch"):format(totalHere, bracketMin(b.key)),
          onSelect = function()
            lib.callback("exec:listSessions", false, function(rows)
              local sessOpts = {}
              sessOpts[#sessOpts+1] = {
                title = "Create Session",
                icon  = "plus",
                description = ("Create %s session (needs %d players to start)."):format(b.label, bracketMin(b.key)),
                onSelect = function()
                  local sel = lib.inputDialog("Create Session", {
                    { type="select", label="Mode", options=(function()
                      local o = {}
                      for _, mk in ipairs(loc.supports or {}) do
                        local def = cfg.modes[mk]
                        if def then
                          o[#o+1] = { label = def.label, value = mk }
                        end
                      end
                      if #o == 0 then
                        o[#o+1] = { label = "Sandbox", value = "sandbox" }
                      end
                      return o
                    end)() },
                    { type="select", label="Privacy", options={ {label="Public", value=false}, {label="Private", value=true} }, default=false },
                    { type="number", label="First to", default=30, min=1, max=100 }
                  })
                  if not sel then return end
                  lib.callback("exec:createSession", false, function(res)
                    if not res or not res.ok then
                      lib.notify({title="Create Failed", description=res and res.error or "Unknown error", type="error"})
                    end
                  end, { location=locKey, bracket=b.key, mode=sel[1], private=sel[2], firstTo=tonumber(sel[3]) or 30 })
                end
              }
              for _, s in ipairs(rows or {}) do
                local cap = s.cap or bracketCap(s.bracket)
                local minPlayers = s.min or bracketMin(s.bracket)
                local status = s.private and "[Private]" or "Public"
                local need = (minPlayers or 0) - (s.players or 0)
                local readyText = (need <= 0) and "Ready" or ("Needs " .. tostring(need) .. " more")
                local modeLabel = (cfg.modes[s.mode] and cfg.modes[s.mode].label) or (s.mode or "Unknown")
                sessOpts[#sessOpts+1] = {
                  title = ("%s - %s [%d/%d] %s"):format(modeLabel, s.owner, s.players, cap, status),
                  description = ("Start at %d players - %s"):format(minPlayers, readyText),
                  onSelect = function()
                    lib.callback("exec:joinSession", false, function(res)
                      if not res or not res.ok then
                        lib.notify({title="Join Failed", description=res and res.error or "Unknown error", type="error"})
                      end
                    end, s.id)
                  end
                }
              end
              lib.registerContext({ id="exec_sessions_"..b.key, title=("Sessions - %s - %s"):format(loc.label, b.label), options=sessOpts })
              lib.showContext("exec_sessions_"..b.key)
            end, { location = locKey, bracket = b.key })
          end
        }
      end
    end

    lib.registerContext({
      id="exec_loc_"..locKey,
      title=("Arena - %s (Players here: %d)"):format(loc.label, totalHere),
      options = {
        { title="Playground (FFA)", icon="gamepad", description="Drop-in, no score", menu="exec_loc_modes_"..locKey },
        { title="Sessions", icon="users", description="Create/Join 1v1, 2v2, 3v3, 5v5, Gang War", menu="exec_loc_sessions_"..locKey }
      }
    })
    lib.registerContext({ id="exec_loc_modes_"..locKey, title=("Playground - %s"):format(loc.label), options = modeOpts })
    lib.registerContext({ id="exec_loc_sessions_"..locKey, title=("Sessions - %s"):format(loc.label), options = brackets })
    lib.showContext("exec_loc_"..locKey)
  end)
end

local forceOpenMenu = false
local openMenuControl = nil
local multicharOpen = false
local function getMenuKeyHint()
  if menuCfg.keybind and menuCfg.keybind ~= '' and menuCfg.keybind ~= false then
    return tostring(menuCfg.keybind):upper()
  end
  if openMenuControl == 38 then return 'E' end
  if openMenuControl == 244 then return 'M' end
  return nil
end

RegisterNetEvent('exec_multichar:openMenu', function()
  multicharOpen = true
  forceOpenMenu = false
end)

RegisterNetEvent('exec_multichar:selected', function()
  multicharOpen = false
end)

RegisterNetEvent('exec_multichar:readyForPvp', function()
  multicharOpen = false
end)

RegisterNetEvent('exec_multichar:uiState', function(isOpen)
  multicharOpen = isOpen and true or false
  if multicharOpen then
    forceOpenMenu = false
  end
end)

if menuCfg.control ~= false then
  openMenuControl = tonumber(menuCfg.control) or 244
end

local menuCommand = nil
if menuCfg.command ~= false then
  menuCommand = menuCfg.command or "exec_menu"
  RegisterCommand(menuCommand, function()
    forceOpenMenu = true
  end, false)

  if menuCfg.keybind ~= false then
    RegisterKeyMapping(menuCommand, menuCfg.keybindLabel or "Open EXEC Menu", "keyboard", menuCfg.keybind or "M")
  end
end

-- Main menu (configurable keybind/command)
CreateThread(function()
  while true do
    Wait(0)
    if multicharOpen then
      forceOpenMenu = false
    elseif ((openMenuControl and IsControlJustPressed(0, openMenuControl)) or forceOpenMenu) then
      forceOpenMenu = false
      lib.callback("exec:listGroups", false, function(groups)
        local gopts = {}
        for _, g in ipairs(groups or {}) do
          gopts[#gopts+1] = { title=g.label, icon=g.icon or "map", onSelect=function()
            lib.callback("exec:listLocationsInGroup", false, function(locs)
              getCounts(function(latest)
                local options = {}
                for _, l in ipairs(locs or {}) do
                  local total = (latest.totals and latest.totals[l.key]) or 0
                  options[#options+1] = { title=("%s  (%d)"):format(l.label, total), icon=l.icon or "location-dot", onSelect=function() openLocationMenu(l.key) end }
                end
                lib.registerContext({ id="exec_locations_"..g.key, title=("Locations - %s"):format(g.label), options=options })
                lib.showContext("exec_locations_"..g.key)
              end)
            end, g.key)
          end }
        end

        local main = {}
        main[#main+1] = { title="Locations", icon="map", onSelect=function()
          lib.registerContext({ id="exec_locations_root", title="Locations", options=gopts })
          lib.showContext("exec_locations_root")
        end }

        local lock = getModeLockInfo()
        if lock and lock.type == "hard" then
          main[#main+1] = { title="Weapons", icon="crosshairs", description=("Disabled: %s"):format(lock.reason), disabled=true }
        else
          main[#main+1] = { title="Weapons", icon="crosshairs", onSelect=function() openWeaponsMenu() end }
        end

        local attachmentsLabel = nil
        do
            local ped = PlayerPedId()
            if ped ~= 0 then
              local currentWeaponHash = GetSelectedPedWeapon(ped)
              if currentWeaponHash and currentWeaponHash ~= 0 and currentWeaponHash ~= `WEAPON_UNARMED` then
                local code = weaponCodeFromHash(currentWeaponHash)
                if code and anyAttachmentAvailable(code) then
                  local _, wLabel = weaponDisplayInfo(currentWeaponHash)
                  attachmentsLabel = wLabel
                end
              end
            end
          end
          if attachmentsLabel then
            main[#main+1] = {
              title = "Attachments",
              icon = "list",
              description = ("Configure attachments for %s"):format(attachmentsLabel),
              onSelect = function()
                openWeaponAttachmentsMenu()
              end
            }
          end

          if isLiveSessionMatch() then
            main[#main+1] = {
              title = "Appearance",
              icon = "ban",
              description = "Disabled during live matches.",
              disabled = true
            }
          else
            main[#main+1] = {
              title = "Appearance",
              icon = "user",
              description = "Open the skin/appearance menu.",
              onSelect = function()
                openSkinMenu()
              end
            }
          end

          do
            local gangState = nil
            local ok, data = pcall(function()
              if exports and exports.exec_framework and exports.exec_framework.GetGangState then
                return exports.exec_framework:GetGangState()
              end
            end)
            if ok then gangState = data end
            if gangState and gangState.gangId then
              local rankText = nil
              if gangState.rank and gangState.rankLabels and gangState.rankLabels[gangState.rank] then
                rankText = gangState.rankLabels[gangState.rank]
              elseif gangState.rank then
                rankText = string.upper(gangState.rank)
              end
              local gangDesc
              if gangState.gangName and rankText then
                gangDesc = string.format("%s (%s)", gangState.gangName, rankText)
              elseif gangState.gangName then
                gangDesc = gangState.gangName
              else
                gangDesc = "Manage your gang"
              end
              main[#main+1] = {
                title = "Gang Menu",
                icon = "users",
                description = gangDesc,
                onSelect = function()
                  local success, opened = pcall(function()
                    if exports and exports.exec_framework and exports.exec_framework.OpenGangMenu then
                      return exports.exec_framework:OpenGangMenu()
                    end
                  end)
                  if not success then
                    lib.notify({ title = "Gangs", description = "Unable to open gang menu.", type = "error" })
                    return
                  end
                  if opened == false then
                    return
                  end
                end
              }
            end
          end

          main[#main+1] = {
            title = "Return to Hub",
            icon = "home",
            description = "Teleport back to the EXEC hub",
            onSelect = function()
              stopPreMatchLock()
              setSessionOutOfBounds(false)
              TriggerServerEvent('exec:leaveMatch')
              lib.hideContext()
            end
          }

          if currentSession and currentSession.sessionId then
            main[#main+1] = {
              title = "Session Controls",
              icon = "users",
              onSelect = function()
                if not currentSession or not currentSession.sessionId then
                  return lib.notify({ title = "Session", description = "No active session.", type = "inform" })
                end

                local sessionId = currentSession.sessionId
                lib.callback("exec:getSessionLobby", false, function(snapshot)
                  local data = snapshot or currentSession
                  if snapshot then
                    applySessionSnapshot(snapshot)
                    data = currentSession
                  end

                  if not data or data.sessionId ~= sessionId then
                    return
                  end

                  local session = data
                  local options = {}

                  if session.isHost and not session.active then
                    options[#options+1] = {
                      title = "Start Match",
                      icon = "play",
                      description = session.balanced and "Start lobby countdown." or "Teams must be balanced to start.",
                      disabled = not session.balanced,
                      onSelect = function()
                        TriggerServerEvent('exec:sessionStart', session.sessionId, false)
                      end
                    }
                    options[#options+1] = {
                      title = "Force Start (Override)",
                      icon = "fast-forward",
                      description = "Override balance checks and start the match now.",
                      onSelect = function()
                        TriggerServerEvent('exec:sessionStart', session.sessionId, true)
                      end
                    }
                    options[#options+1] = {
                      title = session.hardcore and "Disable Hardcore" or "Enable Hardcore",
                      icon = "skull",
                      description = "Toggle friendly fire with team-kill penalties.",
                      onSelect = function()
                        TriggerServerEvent('exec:sessionToggleHardcore', session.sessionId)
                      end
                    }
                  end

                  if session.teams and not session.active then
                    options[#options+1] = { title = "Teams", icon = "layers", disabled = true }
                    for _, team in ipairs(session.teams) do
                      local label = team.gangName or team.label or TEAM_LABELS[team.key] or team.key
                      local count = team.count or 0
                      local max = team.max or 0
                      local full = max > 0 and count >= max
                      local description = max > 0 and string.format("Slots: %d/%d", count, max) or string.format("Players: %d", count)
                      options[#options+1] = {
                        title = label,
                        description = description,
                        icon = team.key == 'alpha' and 'flag' or 'flag-checkered',
                        disabled = (team.key == session.team) or full,
                        onSelect = function()
                          TriggerServerEvent('exec:sessionSetTeam', session.sessionId, team.key)
                        end
                      }
                    end
                  end

                  if session.isHost or session.isTeamLeader then
                    options[#options+1] = {
                      title = "Invite Player (Search)",
                      icon = "user-search",
                      description = "Search the player list and send an invite.",
                      onSelect = function()
                        local input = lib.inputDialog("Invite Player", {
                          { type = "input", label = "Player name or ID", placeholder = "Leave empty to list all" }
                        })
                        if not input then return end
                        local query = input[1] or ''
                        lib.callback("exec:searchInvitees", false, function(players)
                          if not players or #players == 0 then
                            return lib.notify({ title = "Invite", description = "No players found.", type = "inform" })
                          end
                          local opts = {}
                          for _, entry in ipairs(players) do
                            local desc = entry.invited and "Already invited" or "Send session invite"
                            opts[#opts+1] = {
                              title = string.format("%s [%d]", entry.name, entry.id),
                              icon = entry.invited and "check" or "user-plus",
                              description = desc,
                              disabled = entry.invited,
                              onSelect = function()
                                if entry.invited then return end
                                TriggerServerEvent('exec:inviteToSession', session.sessionId, entry.id)
                                lib.notify({ title = "Invite", description = string.format("Invited %s", entry.name), type = "success" })
                              end
                            }
                          end
                          lib.registerContext({ id = "exec_invite_search", title = "Invite Player", options = opts })
                          lib.showContext("exec_invite_search")
                        end, { sessionId = session.sessionId, query = query })
                      end
                    }
                  end

                  if session.isHost then
                    options[#options+1] = {
                      title = "Manage Players",
                      icon = "user-x",
                      onSelect = function()
                        lib.callback('exec:listSessionMembers', false, function(members)
                          if not members or #members == 0 then
                            return lib.notify({ title = "Manage", description = "No members", type = "inform" })
                          end
                          local opts = {}
                          for _, m in ipairs(members) do
                            if m.id ~= GetPlayerServerId(PlayerId()) then
                              opts[#opts+1] = {
                                title = string.format("%s [%d]", m.name, m.id),
                                icon = "user-xmark",
                                onSelect = function()
                                  TriggerServerEvent('exec:kickFromSession', session.sessionId, m.id)
                                end
                              }
                            end
                          end
                          lib.registerContext({ id = "exec_kick_menu", title = "Kick Player (Host Only)", options = opts })
                          lib.showContext("exec_kick_menu")
                        end, session.sessionId)
                      end
                    }
                  end

                  options[#options+1] = {
                    title = "Leave Session",
                    icon = "log-out",
                    onSelect = function()
                      stopPreMatchLock()
                      setSessionOutOfBounds(false)
                      TriggerServerEvent('exec:leaveMatch')
                      lib.hideContext()
                    end
                  }

                  lib.registerContext({ id = "exec_session_menu", title = "Session Controls", options = options })
                  lib.showContext("exec_session_menu")
                end, sessionId)
              end
            }
          end
          lib.registerContext({ id="exec_main", title="EXEC Menu", options=main })
          lib.showContext("exec_main")
      end)
    end
  end
end)

-- Spawn/join/return handlers
RegisterNetEvent("exec:spawnAtHub", function(hub)
  stopPreMatchLock()
  local ped = PlayerPedId()
  local spawn = hub and hub.spawn
  if spawn then
    placePedAtArenaPoint(ped, vector3(spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0), hub.heading or 0.0)
  end
  SetEntityVisible(ped, true, false)
  FreezeEntityPosition(ped, false)
  SetPlayerControl(PlayerId(), true, 0)
  ResetEntityAlpha(ped)
  ClearPedTasksImmediately(ped)
  TriggerEvent("exec:safeMode", true)
  setSessionOutOfBounds(false)
  setHubPassive(true)
  local hint = getMenuKeyHint()
  local desc = hint and ("Open EXEC Menu with [%s]."):format(hint) or "Open the EXEC Menu via your keybind/command."
  lib.notify({ title="EXEC Hub", description=desc, type="inform" })
end)

RegisterNetEvent("exec:joinMatch", function(data)
  stopPreMatchLock()
  local ped = PlayerPedId()
  if ped == 0 then return end

  local zone = buildZoneContext(data.location, data.zone)
  if not zone then
    TriggerEvent('exec:returnToHub', cfg.hub)
    lib.notify({ title = 'EXEC', description = 'Arena not found, returning to hub.', type = 'error' })
    return
  end

  local entry = data.scoring and requestMatchmakingSpawnPoint(zone) or requestArenaSpawnPoint(zone)
  if not entry then
    TriggerEvent('exec:returnToHub', cfg.hub)
    lib.notify({ title = 'EXEC', description = 'Unable to position you in this arena. Returning to hub.', type = 'error' })
    return
  end

  local heading = zone.heading or GetEntityHeading(ped)

  entry = placePedAtArenaPoint(ped, entry, heading) or entry
  ClearPedTasksImmediately(ped)
  TriggerEvent("exec:safeMode", false)
  setHubPassive(false)
  setSessionOutOfBounds(false)
  TriggerEvent("exec:applyLoadout", data.mode, data.scoring, data.category, data.weapon)
  SetTimeout(500, function()
    if currentSession and currentSession.location == data.location then
      TriggerEvent("exec:applyLoadout", data.mode, data.scoring, data.category, data.weapon)
    end
  end)

  if data.scoring then
    setSessionState({
      active = data.active == true,
      sessionId = data.sessionId,
      private = data.private == true,
      bracket = data.bracket,
      location = data.location,
      mode = data.mode,
      zone = zone,
      team = data.team,
      firstTo = tonumber(data.firstTo) or 30,
      isHost = false,
      isTeamLeader = false,
      hardcore = false,
      teams = nil,
      isPlayground = false,
      combatEntered = false,
      lastBoundarySnapAt = 0,
      lastBoundaryNotifyAt = 0,
      entryNotified = false,
    })
    setCurrentSessionZone(zone)
    resetCombatDomeState()
    if isCombatDomeActive(zone) and combatDomeCfg.passiveOutside ~= false then
      local outside = horizontalDistance(entry, zone.center) > ((zone.domeRadius or 0.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75))
      setSessionOutOfBounds(outside)
    end
    TriggerEvent('exec:zoneMarker:setFocus', data.location)
    TriggerEvent("exec:attachArenaHUD", currentSession.mode, currentSession.location, currentSession.bracket, currentSession.firstTo)
  else
    -- keep mode & location for FFA weapon logic
    setSessionState({
      active = false,
      sessionId = nil,
      location = data.location,
      mode = data.mode,
      zone = zone,
      team = nil,
      isPlayground = true,
      combatEntered = false,
      lastBoundarySnapAt = 0,
      lastBoundaryNotifyAt = 0,
      entryNotified = false,
    })
    setCurrentSessionZone(zone)
    if isCombatDomeActive(zone) and combatDomeCfg.passiveOutside ~= false then
      local outside = horizontalDistance(entry, zone.center) > ((zone.domeRadius or 0.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75))
      setSessionOutOfBounds(outside)
    end
    TriggerEvent('exec:zoneMarker:setFocus', data.location)
    TriggerEvent("exec:detachArenaHUD")
  end
end)
RegisterNetEvent("exec:reattachHUDIfSession", function()
  if currentSession.active then
    TriggerEvent("exec:attachArenaHUD", currentSession.mode, currentSession.location, currentSession.bracket, currentSession.firstTo)
  end
end)
RegisterNetEvent("exec:sessionLobbyUpdate", function(payload)
  if not payload then return end
  if not currentSession.sessionId or payload.sessionId ~= currentSession.sessionId then return end
  payload.sessionId = payload.sessionId or currentSession.sessionId
  applySessionSnapshot(payload)
end)

RegisterNetEvent("exec:sessionTeamChanged", function(sessionId, teamKey)
  if not currentSession.sessionId or sessionId ~= currentSession.sessionId then return end
  currentSession.team = teamKey
  currentSession.isTeamLeader = false
end)

RegisterNetEvent("exec:sessionHardcore", function(sessionId, enabled)
  if not currentSession.sessionId or sessionId ~= currentSession.sessionId then return end
  currentSession.hardcore = enabled and true or false
end)

RegisterNetEvent("exec:countdown", function(sessionId)
  if currentSession.sessionId and sessionId and sessionId ~= currentSession.sessionId then return end
  if currentSession.sessionId then
    currentSession.active = false
  end
end)

RegisterNetEvent("exec:matchBegan", function(sessionId)
  if currentSession.sessionId and sessionId and sessionId ~= currentSession.sessionId then return end
  if currentSession.sessionId then
    currentSession.active = true
  end
end)

RegisterNetEvent("exec:sessionNotify", function(message)
  if type(message) == 'table' then
    lib.notify({
      title = message.title or 'Session',
      description = message.description or message.message or '',
      type = message.type or 'inform'
    })
  elseif type(message) == 'string' then
    lib.notify({ title = 'Session', description = message, type = 'inform' })
  end
end)

RegisterNetEvent("exec:character:reset", function()
  stopPreMatchLock()
  TriggerEvent("exec:detachArenaHUD")
  TriggerEvent('exec:zoneMarker:clearFocus')
  setSessionOutOfBounds(false)
  setHubPassive(false)
  clearSessionState()
  TriggerEvent("exec:safeMode", false)
  TriggerEvent("exec:applyLoadout", nil)

  local ped = PlayerPedId()
  if ped ~= 0 then
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    ResetEntityAlpha(ped)
    ClearPedTasksImmediately(ped)
    InventoryBridge.ClearWeapons(ped, true)
  end
end)

RegisterNetEvent("exec:returnToHub", function(hub)
  stopPreMatchLock()
  TriggerEvent("exec:detachArenaHUD")
  local ped = PlayerPedId()
  local spawn = hub and hub.spawn
  if spawn then
    placePedAtArenaPoint(ped, vector3(spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0), hub.heading or 0.0)
  end
  SetEntityVisible(ped, true, false)
  FreezeEntityPosition(ped, false)
  SetPlayerControl(PlayerId(), true, 0)
  ResetEntityAlpha(ped)
  ClearPedTasksImmediately(ped)
  TriggerEvent("exec:safeMode", true)
  clearSessionState()
  TriggerEvent('exec:zoneMarker:clearFocus')
  setSessionOutOfBounds(false)
  setHubPassive(true)
end)

RegisterNetEvent('exec:combatDome:resetLife', function()
  resetCombatDomeState()
  setSessionOutOfBounds(false)
end)

-- Invite helpers
RegisterCommand("exec_invite", function(_, args)
  local sid = tonumber(args[0]) or tonumber(args[1])
  if not sid then
    return lib.notify({title="Invite", description="Usage: /exec_invite [server id]", type="inform"})
  end
  TriggerServerEvent("exec:inviteToSession", currentSession.sessionId or -1, sid)
end, false)

RegisterNetEvent("exec:receiveInvite", function(info)
  local labelLoc = (function()
    if cfg.groups then
      for _, g in pairs(cfg.groups) do
        if g.locations and g.locations[info.location] then return g.locations[info.location].label end
      end
    else
      if cfg.city and cfg.city[info.location] then return cfg.city[info.location].label end
    end
    return info.location
  end)()
  local accept = lib.alertDialog({
    header = "EXEC Invite",
    content = ("%s invited you to a %s at %s (%s). Join?"):format(info.owner, info.bracket, labelLoc, ((cfg.modes and cfg.modes[info.mode]) or {}).label or info.mode),
    centered = true,
    cancel = true,
    labels = { confirm="Join", cancel="Ignore" }
  })
  if accept == "confirm" then
    lib.callback("exec:joinSession", false, function(res)
      if not res or not res.ok then
        lib.notify({title="Join Failed", description=res and res.error or "Unknown error", type="error"})
      end
    end, info.sessionId)
  end
end)







local function slugifyWeaponLabel(label)
  if type(label) ~= "string" then return nil end
  local slug = label:lower()
  slug = slug:gsub("mk%s*ii", "mk2")
  slug = slug:gsub("mk%s*i", "mk1")
  slug = slug:gsub("[^%w%s]", " ")
  slug = slug:gsub("%s+", "_")
  return slug
end

local function captureKillDetails(victimPed, args)
  local me = PlayerPedId()
  local killerCoords = GetEntityCoords(me)
  local victimCoords = victimPed ~= 0 and GetEntityCoords(victimPed) or killerCoords

  local weaponHash = GetSelectedPedWeapon(me)
  if not weaponHash or weaponHash == 0 then
    weaponHash = args and args[3] or 0
  end

  local displayName = nil
  if weaponHash ~= 0 and type(GetWeaponDisplayNameFromHash) == "function" then
    displayName = GetWeaponDisplayNameFromHash(weaponHash)
  end
  local label = displayName and GetLabelText(displayName) or nil
  if not label or label == "NULL" or label == "" then
    label = displayName and displayName:gsub("^WT_", ""):gsub("_", " ") or nil
  end
  local slug = slugifyWeaponLabel(label)

  local headshot = false
  if victimPed ~= 0 then
    local success, bone = GetPedLastDamageBone(victimPed)
    headshot = success and bone == 31086
  end

  local distance = nil
  if killerCoords and victimCoords then
    local dx = killerCoords.x - victimCoords.x
    local dy = killerCoords.y - victimCoords.y
    local dz = killerCoords.z - victimCoords.z
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  return {
    weaponHash = weaponHash,
    weaponLabel = label,
    weaponSlug = slug,
    headshot = headshot,
    distance = distance,
    killerCoords = { x = killerCoords.x, y = killerCoords.y, z = killerCoords.z },
    victimCoords = { x = victimCoords.x, y = victimCoords.y, z = victimCoords.z },
  }
end

local function isPlayerKill(attacker)
  local me = PlayerPedId()
  if attacker == me then return true end
  if IsEntityAVehicle(attacker) then
    return GetPedInVehicleSeat(attacker, -1) == me
  end
  return false
end

local function pruneKillCache(now)
  for sid, ts in pairs(recentKillVictims) do
    if now - ts > 4000 then recentKillVictims[sid] = nil end
  end
end

local function registerKill(serverId, details)
  if not serverId or serverId <= 0 then return end
  local now = GetGameTimer()
  pruneKillCache(now)
  if recentKillVictims[serverId] and (now - recentKillVictims[serverId]) < 750 then return end
  recentKillVictims[serverId] = now
  TriggerServerEvent('exec:serverKill', serverId, details or {})
end

local function isHeadshotPed(ped)
  if ped == 0 or not DoesEntityExist(ped) then return false end
  local success, bone = GetPedLastDamageBone(ped)
  return success and bone == 31086
end

CreateThread(function()
  local applied = nil
  local lastPed = 0
  while true do
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) and (applied ~= oneShotHeadshotsEnabled or ped ~= lastPed) then
      SetPedSuffersCriticalHits(ped, oneShotHeadshotsEnabled)
      applied = oneShotHeadshotsEnabled
      lastPed = ped
    end
    Wait(1000)
  end
end)

AddEventHandler('onResourceStop', function(resName)
  if resName ~= GetCurrentResourceName() then return end
  local ped = PlayerPedId()
  if ped ~= 0 and DoesEntityExist(ped) then
    SetPedSuffersCriticalHits(ped, true)
  end
end)

local function isLocalPedInvincible(ped)
  if ped == 0 or ped ~= PlayerPedId() then return false end
  if type(GetPlayerInvincible) == 'function' then
    local ok, value = pcall(GetPlayerInvincible, PlayerId())
    if ok and value then
      return true
    end
  end
  return false
end

AddEventHandler('gameEventTriggered', function(name, args)
  if name ~= 'CEventNetworkEntityDamage' then return end
  if not currentSession or (not currentSession.active and not currentSession.isPlayground) then return end
  local victim = args[1]
  local attacker = args[2]
  local localPed = PlayerPedId()
  local isHeadshot = oneShotHeadshotsEnabled and isHeadshotPed(victim)

  if isHeadshot and victim == localPed and not IsEntityDead(victim) and not isLocalPedInvincible(victim) then
    SetEntityHealth(victim, 0)
  end

  local fatal = args[6]
  if not isPlayerKill(attacker) then return end
  if victim == PlayerPedId() then return end
  if not IsEntityAPed(victim) or not IsPedAPlayer(victim) then return end
  local victimIdx = NetworkGetPlayerIndexFromPed(victim)
  if victimIdx == -1 then return end
  local serverId = GetPlayerServerId(victimIdx)
  if not serverId or serverId <= 0 then return end
  local killDetails = captureKillDetails(victim, args)
  if not fatal and not isHeadshot then return end
  if not IsEntityDead(victim) then
    SetTimeout(75, function()
      if not currentSession or not currentSession.active then return end
      local playerIdx = GetPlayerFromServerId(serverId)
      if playerIdx == -1 then return end
      local ped = GetPlayerPed(playerIdx)
      if ped == 0 then return end
      if not IsEntityDead(ped) then return end
      registerKill(serverId, killDetails)
    end)
    return
  end
  registerKill(serverId, killDetails)
end)

local function boundarySnapReady()
  local now = GetGameTimer()
  local lastSnap = currentSession.lastBoundarySnapAt or 0
  local cooldown = tonumber(combatDomeCfg.snapbackCooldownMs) or 750
  if lastSnap ~= 0 and (now - lastSnap) < cooldown then return false end
  currentSession.lastBoundarySnapAt = now
  return true
end

local function debugBoundary(message)
  if not (gcfg.debug and gcfg.debug.boundary) and GetConvarInt('exec_debug_boundary', 0) ~= 1 then return end
  print(('[exec_framework:boundary] %s'):format(message))
end

local function snapBackToZone(zone, ped, pos, radius, message)
  if not boundarySnapReady() then return end
  local target = computeZoneReturnPoint(zone, pos, radius)
  if not target then return end
  local weaponHash = GetSelectedPedWeapon(ped)
  placePedAtArenaPoint(ped, target, GetEntityHeading(ped))
  TriggerEvent('exec:weapon:restoreAfterMove', weaponHash)
  debugBoundary(('snapback to %s radius %.2f'):format(zone.location or 'zone', radius or 0.0))
  notifyCombatDome(message, 'error', true)
end

local function handleMatchmakingBoundary(zone, ped, pos)
  local baseRadius = markerBoundaryRadius(zone) or zone.sessionRadius or zone.arenaRadius or zone.domeRadius or 60.0
  if horizontalDistance(pos, zone.center) > baseRadius then
    snapBackToZone(zone, ped, pos, baseRadius, 'You cannot leave the session zone during matchmaking.')
  end
  setSessionOutOfBounds(false)
end

local function handlePreEntryBoundary(zone, distance, entryLimit)
  if distance <= entryLimit then
    currentSession.combatEntered = true
    setSessionOutOfBounds(false)
    if combatDomeCfg.notifyOnEntry ~= false and not currentSession.entryNotified then
      currentSession.entryNotified = true
      notifyCombatDome('Combat live. Leaving the dome will return you to the fight.', 'inform', false)
    end
  else
    setSessionOutOfBounds(combatDomeCfg.passiveOutside ~= false)
  end
end

local function handleLiveCombatBoundary(zone, ped, pos, distance, exitLimit)
  setSessionOutOfBounds(false)
  if combatDomeCfg.lockAfterEntry == false or combatDomeCfg.snapbackOnExit == false or distance <= exitLimit then return end
  if not boundarySnapReady() then return end
  local target = computeCombatReturnPoint(zone, pos)
  if not target then return end
  local weaponHash = GetSelectedPedWeapon(ped)
  placePedAtArenaPoint(ped, target, GetEntityHeading(ped))
  TriggerEvent('exec:weapon:restoreAfterMove', weaponHash)
  debugBoundary(('combat snapback to %s'):format(zone.location or 'zone'))
  if combatDomeCfg.notifyOnExit ~= false then
    notifyCombatDome('You cannot leave the combat dome after entering it.', 'error', true)
  end
end

local function handleCombatDomeBoundary(zone, ped, pos, matchmaking)
  local entryLimit = (zone.domeRadius or 0.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75)
  local exitLimit = (zone.domeRadius or 0.0) + (tonumber(combatDomeCfg.exitBuffer) or 1.0)
  local distance = horizontalDistance(pos, zone.center)

  if matchmaking then
    handleMatchmakingBoundary(zone, ped, pos)
  elseif not currentSession.combatEntered then
    handlePreEntryBoundary(zone, distance, entryLimit)
  else
    handleLiveCombatBoundary(zone, ped, pos, distance, exitLimit)
  end
end

local function handleRadiusBoundary(zone, ped, pos, matchmaking)
  local baseRadius = matchmaking and (markerBoundaryRadius(zone) or zone.sessionRadius or zone.domeRadius or zone.arenaRadius or 60.0) or (zone.sessionRadius or zone.domeRadius or zone.arenaRadius or 60.0)
  local buffer = matchmaking and 0.0 or (zone.sessionBuffer or 0.75)
  local outside = horizontalDistance(pos, zone.center) > (baseRadius + buffer)

  if outside and matchmaking then
    snapBackToZone(zone, ped, pos, baseRadius, 'You cannot leave the session zone during matchmaking.')
    setSessionOutOfBounds(false)
  elseif outside then
    setSessionOutOfBounds(true)
  else
    setSessionOutOfBounds(false)
  end
end

CreateThread(function()
  while true do
    Wait(150)
    local matchmaking = isSessionMatchmaking()
    if hasArenaState() then
      local zone = getCurrentSessionZone()
      local ped = PlayerPedId()
      if zone and zone.center and ped ~= 0 and not IsEntityDead(ped) then
        local pos = GetEntityCoords(ped)
        if isCombatDomeActive(zone) then
          handleCombatDomeBoundary(zone, ped, pos, matchmaking)
        elseif zone.groupKey == 'city' or matchmaking then
          handleRadiusBoundary(zone, ped, pos, matchmaking)
        else
          setSessionOutOfBounds(false)
        end
      else
        setSessionOutOfBounds(false)
      end
    else
      setSessionOutOfBounds(false)
    end
  end
end)

RegisterNetEvent('exec:sessionTeleport', function(zone)
  if not currentSession or not currentSession.active then return end
  local ped = PlayerPedId()
  if ped == 0 then return end

  local zoneData = getCurrentSessionZone(zone)
  if not zoneData or not zoneData.center then return end

  local destination = requestArenaSpawnPoint(zoneData) or zoneData.center
  if not destination then return end

  local heading = zoneData.heading or GetEntityHeading(ped)
  destination = placePedAtArenaPoint(ped, destination, heading) or destination
  ClearPedTasksImmediately(ped)
  ClearPedBloodDamage(ped)
  TriggerEvent('exec:combatDome:resetLife')
  if isCombatDomeActive(zoneData) and combatDomeCfg.passiveOutside ~= false then
    local outside = horizontalDistance(destination, zoneData.center) > ((zoneData.domeRadius or 0.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75))
    setSessionOutOfBounds(outside)
  end
  TriggerEvent('exec:weapon:beginRespawnRestore', false)
  local respawn = gcfg.respawn or {}
  local grace = respawn.seconds or 0
  if grace > 0 then
    TriggerEvent('exec:passive:start', grace, 'session-start', {
      forceUnarmed = respawn.forceUnarmed == true,
    })
  end
end)

RegisterNetEvent('exec:sessionPreStart', function(sessionId, zone)
  if not currentSession or not currentSession.sessionId then return end
  if currentSession.sessionId and sessionId and currentSession.sessionId ~= sessionId then return end
  local ped = PlayerPedId()
  if ped == 0 then return end

  local zoneData = getCurrentSessionZone(zone)
  if not zoneData or not zoneData.center then return end

  local destination = requestMatchmakingSpawnPoint(zoneData) or zoneData.center
  if not destination then return end

  local heading = zoneData.heading or GetEntityHeading(ped)
  destination = placePedAtArenaPoint(ped, destination, heading) or destination
  ClearPedTasksImmediately(ped)
  ClearPedBloodDamage(ped)
  TriggerEvent('exec:combatDome:resetLife')
  if isCombatDomeActive(zoneData) and combatDomeCfg.passiveOutside ~= false then
    local outside = horizontalDistance(destination, zoneData.center) > ((zoneData.domeRadius or 0.0) + (tonumber(combatDomeCfg.entryBuffer) or 0.75))
    setSessionOutOfBounds(outside)
  end
  TriggerEvent('exec:weapon:beginRespawnRestore', false)
  startPreMatchLock()
end)

RegisterNetEvent('exec:countdownCancelled', function()
  stopPreMatchLock()
  if currentSession and currentSession.sessionId then
    currentSession.active = false
  end
end)

RegisterNetEvent('exec:matchGo', function(_, duration)
  if currentSession and currentSession.sessionId then
    currentSession.active = true
  end
  stopPreMatchLock()
end)






























