local gameplay = require 'config.gameplay'
local InventoryBridge = require 'bridge.inventory'

local respawnCfg = gameplay.respawn or {}
local restoreCfg = respawnCfg.restoreLastWeapon or {}
local MIN_AMMO = 9999

local lastWeapon = nil
local lastAmmo = nil
local pendingWeapon = nil
local awaitingRespawnLoadout = false

local function debugWeapon(message)
  if not (gameplay.debug and gameplay.debug.weapon) and GetConvarInt('exec_debug_weapon', 0) ~= 1 then return end
  print(('[exec_framework:weapon] %s'):format(message))
end

local function configuredDelays(key, fallback)
  local delays = restoreCfg[key]
  if type(delays) ~= 'table' or #delays == 0 then return fallback end
  return delays
end

local function validWeapon(hash)
  return hash and hash ~= 0 and hash ~= `WEAPON_UNARMED`
end

local function maxAmmo()
  return math.max(tonumber(restoreCfg.defaultAmmo) or 0, MIN_AMMO)
end

local function rememberWeapon(hash, ammo)
  if not validWeapon(hash) then return false end
  lastWeapon = hash
  lastAmmo = ammo or maxAmmo()
  return true
end

local function rememberCurrent()
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end
  local weapon = GetSelectedPedWeapon(ped)
  if not validWeapon(weapon) then return false end
  return rememberWeapon(weapon, GetAmmoInPedWeapon(ped, weapon))
end

local function restoreInHand(preferredWeapon)
  local weapon = pendingWeapon
  if not validWeapon(weapon) then weapon = preferredWeapon end
  if not validWeapon(weapon) then weapon = lastWeapon end
  if not validWeapon(weapon) then return false end

  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return false end

  local ammo = maxAmmo()
  InventoryBridge.GiveWeapon(ped, weapon, ammo, true)
  rememberWeapon(weapon, ammo)
  TriggerEvent('exec:weapon:restoredWeapon', weapon)
  if pendingWeapon == weapon then pendingWeapon = nil end
  debugWeapon(('restored %s'):format(weapon))
  return true
end

local function restoreAfterMove(preferredWeapon, delays)
  restoreInHand(preferredWeapon)
  delays = delays or configuredDelays('moveRestoreDelaysMs', { 150, 450 })
  for i = 1, #delays do
    local delay = tonumber(delays[i]) or 0
    SetTimeout(delay, function()
      restoreInHand(preferredWeapon)
    end)
  end
end

local function beginRespawnRestore(useCurrentAsPending)
  if useCurrentAsPending ~= false then
    rememberCurrent()
    if validWeapon(lastWeapon) then
      pendingWeapon = lastWeapon
    end
  end
  awaitingRespawnLoadout = true
  TriggerServerEvent('exec:requestRespawnLoadout')
  local delays = configuredDelays('respawnRestoreDelaysMs', { 450, 1200 })
  for i = 1, #delays do
    SetTimeout(tonumber(delays[i]) or 0, restoreInHand)
  end
  SetTimeout(3000, function()
    awaitingRespawnLoadout = false
  end)
end

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
      local weapon = GetSelectedPedWeapon(ped)
      if validWeapon(weapon) then
        rememberWeapon(weapon, GetAmmoInPedWeapon(ped, weapon))
      end
    end
    Wait(200)
  end
end)

CreateThread(function()
  while true do
    if restoreCfg.enabled and restoreCfg.refillOnEmpty ~= false then
      local ped = PlayerPedId()
      if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
        local weapon = GetSelectedPedWeapon(ped)
        local limit = maxAmmo()
        if validWeapon(weapon) then
          if not HasPedGotWeapon(ped, weapon, false) then
            InventoryBridge.GiveWeapon(ped, weapon, limit, true)
          end
          local ammo = GetAmmoInPedWeapon(ped, weapon)
          if ammo ~= limit then
            InventoryBridge.SetAmmo(ped, weapon, limit)
            rememberWeapon(weapon, limit)
            TriggerEvent('exec:weapon:restoredWeapon', weapon)
          end
        elseif validWeapon(lastWeapon) and lastAmmo and lastAmmo <= 0 then
          InventoryBridge.GiveWeapon(ped, lastWeapon, limit, true)
          rememberWeapon(lastWeapon, limit)
          TriggerEvent('exec:weapon:restoredWeapon', lastWeapon)
        end
      end
    end
    Wait(200)
  end
end)

AddEventHandler('exec:loadout:equippedWeapon', function(weaponHash)
  if validWeapon(weaponHash) then
    rememberWeapon(weaponHash, maxAmmo())
  end

  if not awaitingRespawnLoadout then return end
  local key = pendingWeapon and 'pendingLoadoutRestoreDelaysMs' or 'loadoutRestoreDelaysMs'
  local fallback = pendingWeapon and { 0, 250, 900 } or { 0, 250 }
  restoreAfterMove(weaponHash, configuredDelays(key, fallback))
  SetTimeout(1000, function()
    awaitingRespawnLoadout = false
  end)
end)

RegisterNetEvent('exec:weapon:rememberCurrent', rememberCurrent)
RegisterNetEvent('exec:weapon:restoreInHand', restoreInHand)
RegisterNetEvent('exec:weapon:restoreAfterMove', restoreAfterMove)
RegisterNetEvent('exec:weapon:beginRespawnRestore', beginRespawnRestore)

exports('RememberCurrentWeapon', rememberCurrent)
exports('RememberWeapon', rememberWeapon)
exports('RestoreWeaponInHand', restoreInHand)
exports('RestoreWeaponAfterMove', restoreAfterMove)
exports('BeginRespawnWeaponRestore', beginRespawnRestore)
exports('GetLastWeapon', function()
  return lastWeapon, lastAmmo
end)
