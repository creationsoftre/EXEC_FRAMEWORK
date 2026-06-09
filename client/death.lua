-- exec_framework/client/death.lua
local gameplay = require 'config.gameplay'
local arenas   = require 'config.arenas'
local InventoryBridge = require 'bridge.inventory'
local SpawnBridge = require 'bridge.spawn'
local domeCfg  = (gameplay and gameplay.combatDome) or {}

math.randomseed(GetGameTimer())

local dead = false
local deathZone = nil
local respawnCfg = gameplay.respawn or {}
local sampCfg    = (respawnCfg and respawnCfg.spawn) or {}
local manualCfg  = (respawnCfg and respawnCfg.manual) or {}
local promptCfg  = (manualCfg and manualCfg.prompt) or {}
local manualControl = tonumber(manualCfg.control) or 38
local manualKeyLabel = manualCfg.keyLabel or 'E'
local promptEnabled = (promptCfg.enabled ~= false)
local promptTitle = promptCfg.title or 'You are down'
local promptPrefix = promptCfg.prefix or 'Press'
local promptSuffix = promptCfg.suffix or 'to revive'
local promptVisible = nil
local respawnInProgress = false
local deathPos = nil

-- Keep combat firing working (prevents "can't shoot at players")
CreateThread(function()
  while true do
    NetworkSetFriendlyFireOption(true)
    SetCanAttackFriendly(PlayerPedId(), true, true)
    Wait(2000)
  end
end)

local function isManualRespawn()
  return respawnCfg and respawnCfg.enabled and respawnCfg.mode == 'manual'
end

local function disableSpawnmanagerAutoSpawn()
  if not isManualRespawn() then return end
  SpawnBridge.DisableAutoSpawn()
end

local function setDeathPrompt(visible)
  if not promptEnabled or not isManualRespawn() then
    visible = false
  end
  if promptVisible == visible then return end
  SendNUIMessage({
    action = 'deathPrompt:update',
    payload = {
      visible = visible,
      title = promptTitle,
      prefix = promptPrefix,
      suffix = promptSuffix,
      keyLabel = manualKeyLabel,
    }
  })
  promptVisible = visible
end

CreateThread(function()
  if not isManualRespawn() then return end
  Wait(0)
  disableSpawnmanagerAutoSpawn()
end)

AddEventHandler('onClientResourceStart', function(resource)
  if not SpawnBridge.IsSpawnResource(resource) then return end
  CreateThread(function()
    Wait(0)
    disableSpawnmanagerAutoSpawn()
  end)
end)

-- -------- zone helpers --------
local function findZoneForPos(pos)
  if not arenas or not arenas.groups then return nil end
  for gKey, group in pairs(arenas.groups) do
    for lKey, loc in pairs(group.locations or {}) do
      local center, r = loc.center, (loc.arenaRadius or 120.0)
      if center and #(pos - center) <= r + 0.5 then
        return {
          groupKey   = gKey,
          locKey     = lKey,
          center     = center,
          heading    = loc.heading or 0.0,
          domeRadius = loc.domeRadius or 0.0,
          arenaRadius= loc.arenaRadius or 120.0,
          spawns     = loc.spawns,
          label      = (loc.label or lKey)
        }
      end
    end
  end
  return nil
end

local function collectOtherPlayers(excludePed)
  local pts = {}
  for _, id in ipairs(GetActivePlayers()) do
    local ped = GetPlayerPed(id)
    if ped ~= excludePed and DoesEntityExist(ped) and not IsEntityDead(ped) then
      pts[#pts+1] = GetEntityCoords(ped)
    end
  end
  return pts
end

local function groundAt(x, y, zStart, zProbe)
  local top = (zStart or 30.0) + (zProbe or 60.0)
  for dz = 0, 120, 5 do
    local z = top - dz
    local ok, gz = GetGroundZFor_3dCoord(x+0.0, y+0.0, z, false)
    if ok then return gz end
  end
  return zStart or 30.0
end

local function sampleInRing(center, inner, outer)
  local t = 2.0 * math.pi * math.random()
  local r = inner + (outer - inner) * math.sqrt(math.random())
  return vector3(center.x + r * math.cos(t), center.y + r * math.sin(t), center.z)
end

local function isFarFromAll(p, pts, minDist)
  for i=1, #pts do
    if #(p - pts[i]) < minDist then return false end
  end
  return true
end

local function nearestDistance(p, pts)
  local nearest = 99999.0
  for i=1, #pts do
    local d = #(p - pts[i])
    if d < nearest then nearest = d end
  end
  return nearest
end

local function randomRespawnInZone(zone)
  local inner = 0.0
  if sampCfg.respectDomeAsNoSpawn and domeCfg.enabled ~= false and domeCfg.respawnOutside ~= false then
    inner = (zone.domeRadius or 0.0) + (sampCfg.innerBuffer or 0.0)
  end
  local outer   = math.max(inner + 5.0, (zone.arenaRadius or 120.0) - (sampCfg.edgeBuffer or 0.0))
  local tries   = sampCfg.tries or 24
  local minDist = sampCfg.minDistanceFromPlayers or 18.0
  local zProbe  = sampCfg.zProbe or 60.0
  local lift    = sampCfg.offsetAboveGround or 0.6
  local others  = collectOtherPlayers(PlayerPedId())

  if zone.spawns and #zone.spawns > 0 then
    local best, bestMin = nil, -1.0
    local startIdx = math.random(#zone.spawns)
    for i=0, #zone.spawns - 1 do
      local idx = ((startIdx + i - 1) % #zone.spawns) + 1
      local pos = zone.spawns[idx]
      if pos then
        local p = vector3(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0)
        local dx = p.x - zone.center.x
        local dy = p.y - zone.center.y
        local inShell = inner <= 0.0 or math.sqrt((dx * dx) + (dy * dy)) >= inner
        if inShell and isFarFromAll(p, others, minDist) then
          return p
        elseif inShell then
          local nearest = nearestDistance(p, others)
          if nearest > bestMin then bestMin = nearest; best = p end
        end
      end
    end
    if best then return best end
  end

  local best, bestMin = nil, -1.0
  for i=1, tries do
    local p = sampleInRing(zone.center, inner, outer)
    local gz = groundAt(p.x, p.y, zone.center.z, zProbe)
    p = vector3(p.x, p.y, gz + lift)
    if isFarFromAll(p, others, minDist) then
      return p
    else
      local nearest = nearestDistance(p, others)
      if nearest > bestMin then bestMin = nearest; best = p end
    end
  end
  return best or (sampleInRing(zone.center, inner + 8.0, outer))
end

local function applyGrace()
  if not respawnCfg or not respawnCfg.enabled then return end
  local secs = respawnCfg.seconds or 5
  local alpha = respawnCfg.ghostAlpha
  if alpha == nil and gameplay and gameplay.passive then
    alpha = gameplay.passive.ghostAlpha
  end
  if alpha ~= nil then
    TriggerEvent('exec:passive:start', secs, 'respawn', {
      alpha = alpha,
      forceUnarmed = respawnCfg.forceUnarmed == true,
    })
  else
    TriggerEvent('exec:passive:start', secs, 'respawn', {
      forceUnarmed = respawnCfg.forceUnarmed == true,
    })
  end
  if respawnCfg.forceUnarmed then InventoryBridge.SetCurrentWeapon(PlayerPedId(), `WEAPON_UNARMED`) end
end

local function shouldRandomize(groupKey)
  if respawnCfg.alwaysRandomize ~= false then
    return true
  end
  local list = respawnCfg.randomizeInGroups or {}
  for i=1, #list do if list[i] == groupKey then return true end end
  return false
end

local function requestReservedRespawnPoint(zone)
  if type(zone) ~= 'table' then return nil end
  local ok, result = pcall(function()
    return lib.callback.await('exec:reserveRespawnPoint', false, zone)
  end)
  if not ok or type(result) ~= 'table' then return nil end
  local x = tonumber(result.x)
  local y = tonumber(result.y)
  local z = tonumber(result.z)
  if not x or not y or not z then return nil end
  return vector3(x, y, z)
end

local function resolveRandomRespawnPoint(zone)
  if not zone then return nil end
  return requestReservedRespawnPoint(zone) or randomRespawnInZone(zone)
end

exports('GetRandomRespawnPoint', resolveRandomRespawnPoint)

local function placePedSafely(ped, target, heading)
  return SpawnBridge.PlacePed(ped, target, heading)
end

local function resolveManualRespawnTarget()
  local z = deathZone
  local heading = 0.0
  if z then
    heading = z.heading or 0.0
    if shouldRandomize(z.groupKey) then
      local p = resolveRandomRespawnPoint(z)
      return p, heading
    end
    if z.center then
      local offset = (z.domeRadius or 25.0) + 5.0
      return z.center + vector3(offset, 0.0, 0.0), heading
    end
  end
  local hub = arenas and arenas.hub
  if hub and hub.spawn then
    local spawn = hub.spawn
    return vector3(spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0), (hub.heading or 0.0)
  end
  local fallback = deathPos or GetEntityCoords(PlayerPedId())
  return fallback, GetEntityHeading(PlayerPedId())
end

local function performManualRespawn()
  if respawnInProgress or not isManualRespawn() or not dead then return end
  respawnInProgress = true
  local ped = PlayerPedId()
  local target, heading = resolveManualRespawnTarget()
  if target then
    placePedSafely(ped, target, heading)
  end
  ClearPedTasksImmediately(ped)
  ClearPedBloodDamage(ped)
  InventoryBridge.ClearWeapons(ped, false)
  TriggerEvent('exec:combatDome:resetLife')
  TriggerEvent('exec:weapon:beginRespawnRestore', false)
  applyGrace()
  dead = false
  deathZone = nil
  deathPos = nil
  setDeathPrompt(false)
  respawnInProgress = false
end

-- Track death + zone at death
CreateThread(function()
  while true do
    local ped = PlayerPedId()
    if IsEntityDead(ped) and not dead then
      dead = true
      deathPos = GetEntityCoords(ped)
      deathZone = findZoneForPos(deathPos)
      TriggerEvent('exec:weapon:rememberCurrent')
      setDeathPrompt(true)
    elseif dead and not IsEntityDead(ped) then
      dead = false
      deathZone = nil
      deathPos = nil
      setDeathPrompt(false)
    end
    Wait(50)
  end
end)

-- Manual respawn input
CreateThread(function()
  while true do
    if isManualRespawn() and dead then
      if IsControlJustPressed(0, manualControl) or IsDisabledControlJustPressed(0, manualControl) then
        performManualRespawn()
      end
      Wait(0)
    else
      Wait(200)
    end
  end
end)

-- After ANY respawn (spawnmanager, revive scripts, etc.), reposition if needed
AddEventHandler('playerSpawned', function()
  if not respawnCfg or respawnCfg.mode ~= 'auto' then return end
  local z = deathZone  -- may be nil if you died outside arenas
  if not z then return end

  -- wait a moment so spawnmanager finishes placing the ped
  Wait(math.floor((respawnCfg.delaySeconds or 1.25) * 1000))

  local target = nil
  if shouldRandomize(z.groupKey) then
    target = resolveRandomRespawnPoint(z)
  end

  if target then
    local ped = PlayerPedId()
    placePedSafely(ped, target, z.heading or 0.0)
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, 200)
    InventoryBridge.ClearWeapons(ped, false)
    TriggerEvent('exec:combatDome:resetLife')
  end

  TriggerEvent('exec:weapon:beginRespawnRestore', false)

  applyGrace()

  -- clear the remembered zone
  deathZone = nil
end)


