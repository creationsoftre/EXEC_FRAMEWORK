local g = require 'config.gameplay'
local wcfg = require 'config.weapons'

local reticleCfg = wcfg.reticle or {}
local allowedReticleWeapons = {}
local movementCfg = g.playerMovement or {}
local environmentCfg = g.environment or {}
local vehicleCfg = environmentCfg.vehicles or {}
local pedCfg = environmentCfg.peds or {}
local weatherCfg = environmentCfg.weather or {}
local timeCfg = environmentCfg.time or {}

local function sanitizeSprintMultiplier(value)
  local mul = tonumber(value)
  if not mul then return 1.0 end
  if mul < 1.0 then mul = 1.0 end
  if mul > 1.49 then mul = 1.49 end
  return mul
end

local function sanitizeWeatherType(value)
  if type(value) ~= 'string' then return nil end
  local trimmed = value:match('^%s*(.-)%s*$')
  if not trimmed or trimmed == '' then return nil end
  return trimmed:upper()
end

local function sanitizeTimeComponent(value, max)
  local num = tonumber(value)
  if not num then return 0 end
  num = math.floor(num)
  if num < 0 then num = 0 end
  return num % (max + 1)
end

local function resolveBool(primary, fallback, default)
  if primary ~= nil then return primary and true or false end
  if fallback ~= nil then return fallback and true or false end
  return default and true or false
end

local unlimitedSprintEnabled = movementCfg.unlimitedSprint
if unlimitedSprintEnabled == nil then
  if g.enableInfiniteSprint ~= nil then
    unlimitedSprintEnabled = g.enableInfiniteSprint and true or false
  else
    unlimitedSprintEnabled = false
  end
end

local sprintMultiplier = movementCfg.sprintMultiplier
if sprintMultiplier == nil then sprintMultiplier = g.sprintMultiplier end
sprintMultiplier = sanitizeSprintMultiplier(sprintMultiplier)
local sprintMultiplierEnabled = math.abs(sprintMultiplier - 1.0) > 0.01
local vehiclesEnabled = resolveBool(vehicleCfg.enabled, g.enableTraffic, false)
local pedsEnabled = resolveBool(pedCfg.enabled, g.enablePeds, false)
local vehicleCleanupRadius = tonumber(vehicleCfg.cleanupRadius) or 250.0
if vehicleCleanupRadius < 25.0 then vehicleCleanupRadius = 25.0 end
local vehicleCleanupMs = math.floor((tonumber(vehicleCfg.cleanupSeconds) or 4.0) * 1000)
if vehicleCleanupMs < 500 then vehicleCleanupMs = 500 end

local weatherType = sanitizeWeatherType(weatherCfg.type)
local weatherEnabled = weatherCfg.enabled and weatherType ~= nil
local weatherTransition = tonumber(weatherCfg.transitionSeconds) or 0.0
if weatherTransition < 0 then weatherTransition = 0 end
local weatherRefreshMs = math.max(5000, math.floor((weatherCfg.refreshSeconds or 120) * 1000))

local timeEnabled = timeCfg.enabled and true or false
local freezeTime = timeCfg.freeze
if freezeTime == nil then freezeTime = true end
freezeTime = freezeTime and true or false
local timeRate = tonumber(timeCfg.rate) or 1.0
if timeRate <= 0 then timeRate = 1.0 end
local timeUpdateInterval = tonumber(timeCfg.updateSeconds) or 1.0
if timeUpdateInterval < 0.25 then timeUpdateInterval = 0.25 end
local baseHour = sanitizeTimeComponent(timeCfg.hour, 23)
local baseMinute = sanitizeTimeComponent(timeCfg.minute, 59)
local baseSecond = sanitizeTimeComponent(timeCfg.second, 59)
local baseSeconds = (baseHour * 60 + baseMinute) * 60 + baseSecond
local currentClockSeconds = baseSeconds

local function sanitizeWeaponCode(code)
  if type(code) ~= 'string' then return nil end
  local upper = code:upper()
  if not upper:find('WEAPON_', 1, true) then
    upper = 'WEAPON_' .. upper
  end
  return upper
end

local function allowReticleForWeapon(code)
  if not code then return end
  if type(code) == 'number' then
    allowedReticleWeapons[code] = true
    return
  end
  local key = sanitizeWeaponCode(code)
  if not key then return end
  allowedReticleWeapons[GetHashKey(key)] = true
end

local processedCategories = {}

local function allowCategoryWeapons(catKey)
  if processedCategories[catKey] then return end
  processedCategories[catKey] = true
  local categories = wcfg.categories or {}
  local cat = categories[catKey]
  if not cat or type(cat.weapons) ~= 'table' then return end
  for _, weapon in ipairs(cat.weapons) do
    allowReticleForWeapon(weapon)
  end
end

do
  local categories = {}
  if type(reticleCfg.whitelistCategories) == 'table' then
    for _, cat in ipairs(reticleCfg.whitelistCategories) do
      if type(cat) == 'string' then
        categories[#categories+1] = cat
      end
    end
  end
  local hasSnipers = false
  for i=1, #categories do
    if categories[i] == 'snipers' then hasSnipers = true break end
  end
  if not hasSnipers then
    categories[#categories+1] = 'snipers'
  end
  for i=1, #categories do
    allowCategoryWeapons(categories[i])
  end
  if type(reticleCfg.whitelistWeapons) == 'table' then
    for _, weapon in ipairs(reticleCfg.whitelistWeapons) do
      allowReticleForWeapon(weapon)
    end
  end
end

local function applyWeatherOverride()
  if not weatherEnabled then return end
  ClearOverrideWeather()
  ClearWeatherTypePersist()
  if weatherTransition > 0 then
    SetWeatherTypeOvertimePersist(weatherType, weatherTransition + 0.0)
    Wait(math.floor(weatherTransition * 1000))
  end
  SetWeatherTypePersist(weatherType)
  SetWeatherTypeNowPersist(weatherType)
  SetWeatherTypeNow(weatherType)
end

local function clearWeatherOverride()
  ClearOverrideWeather()
  ClearWeatherTypePersist()
end

local function applyClockOverride(seconds)
  local total = seconds % 86400
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = math.floor(total % 60)
  NetworkOverrideClockTime(h, m, s)
end

local function vehicleHasPlayerOccupant(vehicle)
  if not DoesEntityExist(vehicle) then return false end
  for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
    local ped = GetPedInVehicleSeat(vehicle, seat)
    if ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped) then
      return true
    end
  end
  return false
end

local function cleanupAmbientVehicles()
  if vehiclesEnabled then return end
  local ped = PlayerPedId()
  if ped == 0 or not DoesEntityExist(ped) then return end
  local myVehicle = GetVehiclePedIsIn(ped, false)
  local origin = GetEntityCoords(ped)
  local radius = vehicleCleanupRadius
  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if DoesEntityExist(vehicle) and vehicle ~= myVehicle then
      local coords = GetEntityCoords(vehicle)
      if #(coords - origin) <= radius and not vehicleHasPlayerOccupant(vehicle) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
      end
    end
  end
end

CreateThread(function()
  while true do
    if not g.enableWantedLevel then
      SetMaxWantedLevel(0)
      ClearPlayerWantedLevel(PlayerId())
      SetPlayerWantedLevel(PlayerId(), 0, false)
      SetPlayerWantedLevelNow(PlayerId(), false)
      SetPoliceIgnorePlayer(PlayerPedId(), true)
      SetDispatchCopsForPlayer(PlayerId(), false)
      SetCreateRandomCops(false)
      SetCreateRandomCopsNotOnScenarios(false)
      SetCreateRandomCopsOnScenarios(false)
    else
      SetMaxWantedLevel(5)
      SetPoliceIgnorePlayer(PlayerPedId(), false)
      SetDispatchCopsForPlayer(PlayerId(), true)
    end
    SetRandomBoats(vehiclesEnabled)
    SetRandomTrains(vehiclesEnabled)
    SetGarbageTrucks(vehiclesEnabled)
    Wait(2000)
  end
end)

CreateThread(function()
  local appliedSprintMultiplier = 1.0
  local nextSprintRefresh = 0
  while true do
    Wait(0)
    local playerId = PlayerId()
    if unlimitedSprintEnabled then
      RestorePlayerStamina(playerId, 1.0)
    end
    local targetMultiplier = sprintMultiplierEnabled and sprintMultiplier or 1.0
    local now = GetGameTimer()
    if targetMultiplier ~= appliedSprintMultiplier or now >= nextSprintRefresh then
      SetRunSprintMultiplierForPlayer(playerId, targetMultiplier)
      appliedSprintMultiplier = targetMultiplier
      nextSprintRefresh = now + 5000
    end
    local tMul = vehiclesEnabled and 1.0 or 0.0
    local pMul = pedsEnabled and 1.0 or 0.0
    SetPedDensityMultiplierThisFrame(pMul)
    SetScenarioPedDensityMultiplierThisFrame(pMul, pMul)
    SetVehicleDensityMultiplierThisFrame(tMul)
    SetRandomVehicleDensityMultiplierThisFrame(tMul)
    SetParkedVehicleDensityMultiplierThisFrame(tMul)
    if not g.enableGunButting then
      local ped = PlayerPedId()
      if IsPedArmed(ped, 6) and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
      end
    end
    if not g.enableWallCover then
      DisableControlAction(0, 44, true) -- INPUT_COVER
    end
  end
end)

if not vehiclesEnabled then
  CreateThread(function()
    while true do
      cleanupAmbientVehicles()
      Wait(vehicleCleanupMs)
    end
  end)
end

CreateThread(function()
  while true do
    Wait(0)
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
      local weapon = GetSelectedPedWeapon(ped)
      if weapon ~= nil and weapon ~= `WEAPON_UNARMED` then
        if not allowedReticleWeapons[weapon] then
          HideHudComponentThisFrame(14) -- crosshair
        end
      else
        HideHudComponentThisFrame(14)
      end
    end
  end
end)

if weatherEnabled then
  CreateThread(function()
    while true do
      applyWeatherOverride()
      Wait(weatherRefreshMs)
    end
  end)
  AddEventHandler('playerSpawned', function()
    CreateThread(function()
      Wait(250)
      applyWeatherOverride()
    end)
  end)
  AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    clearWeatherOverride()
  end)
end

if timeEnabled then
  CreateThread(function()
    local updateMs = math.floor(timeUpdateInterval * 1000)
    if updateMs < 100 then updateMs = 100 end
    local currentSeconds = baseSeconds
    local lastGameTimer = GetGameTimer()
    PauseClock(true)
    while true do
      if freezeTime then
        currentSeconds = baseSeconds
        lastGameTimer = GetGameTimer()
      else
        local now = GetGameTimer()
        local delta = (now - lastGameTimer) / 1000.0
        if delta < 0 then delta = 0 end
        lastGameTimer = now
        currentSeconds = currentSeconds + (delta * timeRate)
      end
      currentSeconds = currentSeconds % 86400
      currentClockSeconds = currentSeconds
      applyClockOverride(currentSeconds)
      Wait(updateMs)
    end
  end)
  AddEventHandler('playerSpawned', function()
    CreateThread(function()
      Wait(250)
      applyClockOverride(currentClockSeconds)
    end)
  end)
  AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    PauseClock(false)
  end)
end

if sprintMultiplierEnabled then
  AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
  end)
end
