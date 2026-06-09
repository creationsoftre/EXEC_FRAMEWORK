local arenas = require "config.arenas"
local gameplay = require "config.gameplay"
local weaponCatalog = require "shared.weapon_catalog"
local InventoryBridge = require "bridge.inventory"
local categories = weaponCatalog.categories or {}

local MIN_AMMO = 9999

local function spawnAmmoCount()
  local respawn = gameplay.respawn or {}
  local restore = respawn.restoreLastWeapon or {}
  local configured = tonumber(restore.defaultAmmo) or 0
  return math.max(configured, MIN_AMMO)
end

local function toWeaponHash(w)
  if not w then return nil end
  if type(w) == "number" then return w end
  if type(w) == "string" then
    local up = w:upper()
    if not up:find("^WEAPON_") then up = "WEAPON_" .. up end
    return joaat(up)
  end
  return nil
end

local function sanitizeWeaponCode(code)
  if type(code) ~= "string" then return nil end
  local up = code:upper()
  if not up:find("^WEAPON_") then up = "WEAPON_" .. up end
  return up
end

local function firstWeaponInCategory(catKey)
  local cat = categories[catKey]
  if not cat or not cat.weapons or #cat.weapons == 0 then return nil end
  local entry = cat.weapons[1]
  if type(entry) == "table" then
    entry = entry.code or entry.weapon or entry[1]
  end
  return sanitizeWeaponCode(entry) or entry
end

local function ensureHasWeapon(ped, weaponNameOrHash)
  local hash = toWeaponHash(weaponNameOrHash)
  if not hash then return nil end
  local ammo = spawnAmmoCount()
  return InventoryBridge.GiveWeapon(ped, hash, ammo, true)
end

local function clearAllWeapons(ped)
  InventoryBridge.ClearWeapons(ped, true)
end

local function setVitals(ped, m)
  local armor = (m and m.armor) or 100
  local hp    = (m and m.health) or 200
  InventoryBridge.SetVitals(ped, hp, armor)
end

-- Public: apply loadout
RegisterNetEvent("exec:applyLoadout", function(modeKey, scoring, categoryKey, weaponName)
  local ped = PlayerPedId()
  if not modeKey then
    clearAllWeapons(ped)
    return
  end

  local mode = arenas.modes[modeKey] or {}
  setVitals(ped, mode)

  -- pick effective category/weapon
  local effCategory = categoryKey
  local effWeapon   = weaponName

  if mode.weaponLock then
    effCategory = mode.categoryLock or effCategory
    effWeapon   = mode.weaponLock
  elseif mode.categoryLock then
    effCategory = mode.categoryLock
    if not effWeapon then
      -- fall back to first in category
      effWeapon = firstWeaponInCategory(effCategory)
    end
  else
    -- sandbox or unlocked: if no weapon, pick first in chosen category
    if not effWeapon and effCategory then
      effWeapon = firstWeaponInCategory(effCategory)
    end
  end

  if effWeapon and type(effWeapon) == 'string' then
    effWeapon = sanitizeWeaponCode(effWeapon) or effWeapon
  end

  clearAllWeapons(ped)

  if effWeapon then
    local hash = ensureHasWeapon(ped, effWeapon)
    if hash then
      InventoryBridge.SetCurrentWeapon(ped, hash)
      TriggerEvent("exec:loadout:equippedWeapon", hash, effWeapon)
    end
  else
    TriggerEvent("exec:loadout:equippedWeapon", nil, nil)
  end
end)
