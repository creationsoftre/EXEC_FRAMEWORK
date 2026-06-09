
-- exec_framework/client/passive.lua
local cfg = require 'config.gameplay'
local InventoryBridge = require 'bridge.inventory'

local passiveReasons, isPassive = {}, false
local controlsSuppressed = false
local lastSentPassiveState = nil
local lastSentPassiveAlpha = nil
local lastSentPassiveOpaque = nil
local lastAppliedAlpha = nil
local remotePassiveStates = {}
local indicatorState = { visible = nil, subtext = nil }
local appearanceUiOpen = false

local PASSIVE_SUBTEXT = {
  respawn = 'Respawn Grace',
  ['session-start'] = 'Match Grace',
  ['session-oob'] = 'Combat Boundary',
  ['hub-passive'] = 'Hub Safe',
  ['appearance-menu'] = 'Appearance Menu',
  green = 'Safe Zone',
}
local PASSIVE_PRIORITY = { 'respawn', 'session-start', 'session-oob', 'appearance-menu', 'hub-passive', 'green' }

local function resolveIndicatorSubtext()
  for _, reason in ipairs(PASSIVE_PRIORITY) do
    if passiveReasons[reason] then
      return PASSIVE_SUBTEXT[reason] or 'Combat disabled'
    end
  end
  return 'Combat disabled'
end

local function pushIndicator(active)
  local nuiFocused = IsNuiFocused and IsNuiFocused()
  local hiddenByUi = IsPauseMenuActive() or nuiFocused or appearanceUiOpen
  local visible = active and cfg.passive.indicator and not hiddenByUi
  local subtext = visible and resolveIndicatorSubtext() or nil
  if indicatorState.visible == visible and indicatorState.subtext == subtext then return end
  SendNUIMessage({
    action = 'passive:update',
    payload = {
      visible = visible,
      title = 'Passive Mode',
      subtext = subtext,
    }
  })
  indicatorState.visible = visible
  indicatorState.subtext = subtext
end

local function sanitizeAlpha(value)
  local alpha = tonumber(value)
  if not alpha then return nil end
  alpha = math.floor(alpha)
  if alpha < 0 then return nil end
  if alpha > 255 then alpha = 255 end
  return alpha
end

local function resolvePassiveAlpha()
  if appearanceUiOpen then return nil end
  for _, entry in pairs(passiveReasons) do
    if type(entry) == 'table' and entry.opaque then
      return nil
    end
  end
  local chosen = nil
  for _, entry in pairs(passiveReasons) do
    if type(entry) == 'table' and entry.alpha ~= nil then
      if chosen == nil or entry.alpha < chosen then
        chosen = entry.alpha
      end
    end
  end
  if chosen ~= nil then return chosen end
  return sanitizeAlpha(cfg.passive and cfg.passive.ghostAlpha)
end

local function resolveForceUnarmed()
  for _, entry in pairs(passiveReasons) do
    if type(entry) == 'table' and not entry.allowControls then
      local forceUnarmed = entry.forceUnarmed
      if forceUnarmed == nil then
        forceUnarmed = cfg.passive.forceUnarmed
      end
      if forceUnarmed then
        return true
      end
    end
  end
  return false
end

local function broadcastPassiveState(active, alpha)
  local opaque = false
  if not active then
    alpha = nil
    opaque = false
  else
    for _, entry in pairs(passiveReasons) do
      if type(entry) == 'table' and entry.opaque then
        opaque = true
        break
      end
    end
    if appearanceUiOpen then opaque = true end
    alpha = sanitizeAlpha(alpha or resolvePassiveAlpha())
  end
  if lastSentPassiveState == active and lastSentPassiveAlpha == alpha and lastSentPassiveOpaque == opaque then return end
  TriggerServerEvent('exec:passive:syncState', active, alpha, opaque)
  lastSentPassiveState = active
  lastSentPassiveAlpha = alpha
  lastSentPassiveOpaque = opaque
end

local function applyRemotePassiveState(serverId)
  serverId = tonumber(serverId)
  if not serverId then return end

  local entry = remotePassiveStates[serverId]
  local playerIndex = GetPlayerFromServerId(serverId)
  if playerIndex == -1 then return end

  local ped = GetPlayerPed(playerIndex)
  if ped == 0 or not DoesEntityExist(ped) then return end

  if entry and entry.isPassive then
    if entry.opaque then
      ResetEntityAlpha(ped)
    else
      local alpha = sanitizeAlpha(entry.alpha)
      if not alpha then
        alpha = sanitizeAlpha(cfg.passive and cfg.passive.ghostAlpha)
      end
      if alpha then SetEntityAlpha(ped, alpha, false) end
    end
    if cfg.passive.noCollision then
      local myPed = PlayerPedId()
      if myPed ~= 0 and DoesEntityExist(myPed) then
        SetEntityNoCollisionEntity(myPed, ped, true)
        SetEntityNoCollisionEntity(ped, myPed, true)
      end
    end
  else
    ResetEntityAlpha(ped)
    if cfg.passive.noCollision then
      local myPed = PlayerPedId()
      if myPed ~= 0 and DoesEntityExist(myPed) then
        SetEntityNoCollisionEntity(myPed, ped, false)
        SetEntityNoCollisionEntity(ped, myPed, false)
      end
    end
  end
end

local function setInvincible(ped, on)
  SetEntityInvincible(ped, on)
  SetPedCanRagdoll(ped, not on)
  SetEntityProofs(ped, on, on, on, on, on, on, on, on)
end

local function resetPassiveState()
  passiveReasons = {}
  isPassive = false
  controlsSuppressed = false
  lastSentPassiveState = nil
  lastSentPassiveAlpha = nil
  lastSentPassiveOpaque = nil
  lastAppliedAlpha = nil
  remotePassiveStates = {}
  pushIndicator(false)
  local ped = PlayerPedId()
  if ped ~= 0 and DoesEntityExist(ped) then
    ResetEntityAlpha(ped)
    setInvincible(ped, false)
  end
  TriggerServerEvent('exec:passive:syncState', false, nil)
  TriggerServerEvent('exec:passive:requestSync')
end

RegisterNetEvent('exec:character:reset', resetPassiveState)

local function recompute()
  local now = GetGameTimer()
  local active = false
  local allowControls = true

  for reason, entry in pairs(passiveReasons) do
    if type(entry) ~= 'table' then
      passiveReasons[reason] = nil
    else
      local expires = entry.expires or 0
      if expires ~= 0 and expires <= now then
        passiveReasons[reason] = nil
      else
        active = true
        if not entry.allowControls then allowControls = false end
      end
    end
  end

  local ped = PlayerPedId()
  local targetAlpha = active and resolvePassiveAlpha() or nil
  local forceUnarmed = active and resolveForceUnarmed() or false

  if active ~= isPassive then
    isPassive = active
    if ped ~= 0 and DoesEntityExist(ped) then
      if active then
        if forceUnarmed then InventoryBridge.SetCurrentWeapon(ped, `WEAPON_UNARMED`) end
        if cfg.passive.invincible then setInvincible(ped, true) end
        if targetAlpha ~= nil then
          SetEntityAlpha(ped, targetAlpha, false)
          lastAppliedAlpha = targetAlpha
        else
          ResetEntityAlpha(ped)
          lastAppliedAlpha = nil
        end
      else
        setInvincible(ped, false)
        ResetEntityAlpha(ped)
        lastAppliedAlpha = nil
        SetPlayerCanDoDriveBy(PlayerId(), true)
      end
    end
  end

  if ped ~= 0 and DoesEntityExist(ped) then
    if active then
      if cfg.passive.invincible then setInvincible(ped, true) end
      if targetAlpha ~= lastAppliedAlpha then
        if targetAlpha ~= nil then
          SetEntityAlpha(ped, targetAlpha, false)
          lastAppliedAlpha = targetAlpha
        else
          ResetEntityAlpha(ped)
          lastAppliedAlpha = nil
        end
      end
    else
      if cfg.passive.invincible then setInvincible(ped, false) end
      if lastAppliedAlpha ~= nil then
        ResetEntityAlpha(ped)
        lastAppliedAlpha = nil
      end
    end
  else
    lastAppliedAlpha = nil
  end

  broadcastPassiveState(active, targetAlpha)

  controlsSuppressed = isPassive and (cfg.passive.disableControls and not allowControls)
  pushIndicator(active)
end

local function start(reason, seconds, options)
  reason = reason or 'custom'
  local alpha = nil
  if options then
    alpha = options.alpha or options.ghostAlpha
    alpha = sanitizeAlpha(alpha)
  end
  passiveReasons[reason] = {
    expires = (seconds and seconds > 0) and (GetGameTimer() + seconds * 1000) or 0,
    allowControls = options and options.allowControls or false,
    alpha = alpha,
    opaque = options and options.opaque == true,
    forceUnarmed = options and options.forceUnarmed,
  }
  recompute()
end

local function stop(reason)
  passiveReasons[reason or 'custom'] = nil
  recompute()
end

-- Exports
exports('SetPassive', function(flag, reason, seconds, options)
  if flag then start(reason, seconds, options) else stop(reason) end
end)
exports('IsPassive', function() return isPassive end)

-- Control blocker + HUD indicator while passive
CreateThread(function()
  while true do
    if isPassive then
      if controlsSuppressed then
        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 25, true)   -- aim
        DisableControlAction(0, 142, true)  -- melee alt
        DisableControlAction(0, 257, true)  -- attack2
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 143, true)
        DisableControlAction(0, 263, true)  -- melee mouse
        DisableControlAction(0, 264, true)
        DisablePlayerFiring(PlayerId(), true)
        SetPlayerCanDoDriveBy(PlayerId(), false)
      end
      if controlsSuppressed and resolveForceUnarmed() then
        InventoryBridge.SetCurrentWeapon(PlayerPedId(), `WEAPON_UNARMED`)
      end
      Wait(0)
    else
      Wait(350)
    end
  end
end)

CreateThread(function()
  while true do
    if isPassive then
      recompute()
      Wait(250)
    else
      Wait(750)
    end
  end
end)

-- Green-zone passive toggle
if cfg.passive.enableInGreen then
  local zones = cfg.greenZones or {}
  CreateThread(function()
    local wasInside = false
    while true do
      local ped = PlayerPedId()
      local pos = GetEntityCoords(ped)
      local inside = false
      for _, z in ipairs(zones) do
        if #(pos - z.center) <= z.radius then inside = true break end
      end
      if inside and not wasInside then
        start('green', 0, { forceUnarmed = false })
      elseif not inside and wasInside then
        stop('green')
      end
      wasInside = inside
      Wait(500)
    end
  end)
end

-- Timed passive from other modules (respawn grace, etc.)
RegisterNetEvent('exec:passive:start', function(seconds, reason, options) start(reason, seconds, options) end)
RegisterNetEvent('exec:passive:stop',  function(reason) stop(reason) end)

local function setAppearanceUiOpen(open)
  local want = open and true or false
  if appearanceUiOpen == want then return end
  appearanceUiOpen = want
  recompute()
end

RegisterNetEvent('fivem-appearance:client:open', function()
  setAppearanceUiOpen(true)
end)

RegisterNetEvent('fivem-appearance:client:close', function()
  setAppearanceUiOpen(false)
end)

RegisterNetEvent('exec:appearance:open', function()
  setAppearanceUiOpen(true)
end)

RegisterNetEvent('exec:appearance:close', function()
  setAppearanceUiOpen(false)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == 'fivem-appearance' then
    setAppearanceUiOpen(false)
  end
end)

RegisterNetEvent('exec:passive:remoteSnapshot', function(list)
  remotePassiveStates = {}
  local myServerId = GetPlayerServerId(PlayerId())
  if type(list) ~= 'table' then return end
  for _, entry in ipairs(list) do
    if type(entry) == 'table' then
      local serverId = tonumber(entry.id or entry[1])
      if serverId and serverId ~= myServerId and entry.active ~= false then
        remotePassiveStates[serverId] = { isPassive = true, alpha = sanitizeAlpha(entry.alpha), opaque = entry.opaque == true }
        applyRemotePassiveState(serverId)
      end
    end
  end
end)

RegisterNetEvent('exec:passive:remoteState', function(serverId, active, alpha, opaque)
  local id = tonumber(serverId)
  if not id then return end
  if id == GetPlayerServerId(PlayerId()) then return end
  if active then
    remotePassiveStates[id] = { isPassive = true, alpha = sanitizeAlpha(alpha), opaque = opaque == true }
  else
    remotePassiveStates[id] = nil
  end
  applyRemotePassiveState(id)
end)

CreateThread(function()
  Wait(600)
  TriggerServerEvent('exec:passive:requestSync')
  broadcastPassiveState(isPassive, isPassive and resolvePassiveAlpha() or nil)
end)

CreateThread(function()
  while true do
    local myServerId = GetPlayerServerId(PlayerId())
    for serverId in pairs(remotePassiveStates) do
      if serverId ~= myServerId then
        applyRemotePassiveState(serverId)
      end
    end
    Wait(1500)
  end
end)

-- Friendly-fire keepalive: ensure combat stays enabled unless you're passive
CreateThread(function()
  while true do
    NetworkSetFriendlyFireOption(true)
    SetCanAttackFriendly(PlayerPedId(), true, true)
    Wait(2000)
  end
end)








