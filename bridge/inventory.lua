local integrationConfig = require 'config.integrations'

local InventoryBridge = {}
local inventoryConfig = (integrationConfig and integrationConfig.inventory) or {}

local function defaultAmmo()
  return math.max(tonumber(inventoryConfig.defaultAmmo) or 0, 9999)
end

local function weaponHash(weaponNameOrHash)
  if type(weaponNameOrHash) == 'number' then return weaponNameOrHash end
  if type(weaponNameOrHash) ~= 'string' then return nil end
  local weaponName = weaponNameOrHash:upper()
  if not weaponName:find('^WEAPON_') then weaponName = 'WEAPON_' .. weaponName end
  return joaat(weaponName)
end

local function callCustomTarget(targetConfig, ...)
  if type(targetConfig) ~= 'table' then return false end

  if targetConfig.type == 'event' and targetConfig.name then
    TriggerEvent(targetConfig.name, ...)
    return true
  end

  if targetConfig.type == 'export' and targetConfig.resource and targetConfig.name then
    if GetResourceState(targetConfig.resource) ~= 'started' then return false end
    local resourceExports = exports[targetConfig.resource]
    local targetExport = resourceExports and resourceExports[targetConfig.name]
    if type(targetExport) ~= 'function' then return false end
    local success, errorMessage = pcall(targetExport, ...)
    if not success then
      print(('[exec_framework] inventory bridge failed (%s:%s): %s'):format(targetConfig.resource, targetConfig.name, errorMessage))
    end
    return success
  end

  return false
end

-- CAPO: Native weapon handling lives here so inventory-backed loadouts can be added cleanly later.
function InventoryBridge.GiveWeapon(ped, weaponNameOrHash, ammo, equipNow)
  if inventoryConfig.provider == 'none' then return nil end
  local hash = weaponHash(weaponNameOrHash)
  if not hash then return nil end
  local ammoCount = tonumber(ammo) or defaultAmmo()

  if inventoryConfig.provider == 'native' or inventoryConfig.provider == nil then
    if not HasPedGotWeapon(ped, hash, false) then
      GiveWeaponToPed(ped, hash, ammoCount, false, equipNow ~= false)
    end
    SetPedAmmo(ped, hash, ammoCount)
    if equipNow ~= false then
      SetCurrentPedWeapon(ped, hash, true)
    end
    return hash
  end

  if inventoryConfig.provider == 'custom' and callCustomTarget(inventoryConfig.giveWeapon, ped, hash, ammoCount, equipNow ~= false) then
    return hash
  end

  return nil
end

function InventoryBridge.ClearWeapons(ped, removeAmmo)
  if inventoryConfig.provider == 'none' then return false end
  if inventoryConfig.provider == 'custom' and callCustomTarget(inventoryConfig.clearWeapons, ped, removeAmmo ~= false) then return true end
  RemoveAllPedWeapons(ped, removeAmmo ~= false)
  return true
end

function InventoryBridge.SetCurrentWeapon(ped, weaponNameOrHash)
  if inventoryConfig.provider == 'none' then return nil end
  local hash = weaponHash(weaponNameOrHash)
  if not hash then return nil end
  if inventoryConfig.provider == 'custom' and callCustomTarget(inventoryConfig.setCurrentWeapon, ped, hash) then
    return hash
  end
  SetCurrentPedWeapon(ped, hash, true)
  return hash
end

function InventoryBridge.SetAmmo(ped, weaponNameOrHash, ammo)
  if inventoryConfig.provider == 'none' then return nil end
  local hash = weaponHash(weaponNameOrHash)
  if not hash then return nil end
  local ammoCount = tonumber(ammo) or defaultAmmo()
  if inventoryConfig.provider == 'custom' and callCustomTarget(inventoryConfig.setAmmo, ped, hash, ammoCount) then
    return hash
  end
  SetPedAmmo(ped, hash, ammoCount)
  return hash
end

function InventoryBridge.SetVitals(ped, health, armor)
  if inventoryConfig.provider == 'none' then return false end
  if inventoryConfig.provider == 'custom' and callCustomTarget(inventoryConfig.setVitals, ped, health, armor) then return true end
  SetPedArmour(ped, armor or 100)
  local maxHealth = GetEntityMaxHealth(ped)
  SetEntityHealth(ped, math.min(health or 200, maxHealth))
  return true
end

function InventoryBridge.DefaultAmmo()
  return defaultAmmo()
end

return InventoryBridge
