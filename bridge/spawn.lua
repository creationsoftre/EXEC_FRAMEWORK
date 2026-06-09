local integrationConfig = require 'config.integrations'

local SpawnBridge = {}
local spawnConfig = (integrationConfig and integrationConfig.spawn) or {}

local function asVector3(point)
  if not point then return nil end
  if type(point) == 'vector3' then return point end
  if type(point) == 'table' or type(point) == 'userdata' then
    local x = tonumber(point.x or point[1])
    local y = tonumber(point.y or point[2])
    local z = tonumber(point.z or point[3])
    if x and y and z then return vector3(x, y, z) end
  end
  return nil
end

function SpawnBridge.DisableAutoSpawn()
  local spawnResource = spawnConfig.resource or 'spawnmanager'
  if spawnConfig.provider == 'none' or GetResourceState(spawnResource) ~= 'started' then return false end
  local success = pcall(function()
    exports[spawnResource]:setAutoSpawn(false)
  end)
  return success
end

function SpawnBridge.IsSpawnResource(resourceName)
  return resourceName == (spawnConfig.resource or 'spawnmanager')
end

-- CAPO: Respawn placement is centralized here for compatibility with spawnmanager or custom revive scripts.
function SpawnBridge.PlacePed(ped, point, heading)
  local target = asVector3(point)
  if ped == 0 or not target then return nil end

  local customPlacePed = spawnConfig.placePed
  if spawnConfig.provider == 'custom' and type(customPlacePed) == 'table' then
    if customPlacePed.type == 'event' and customPlacePed.name then
      TriggerEvent(customPlacePed.name, ped, target, heading)
      return target
    end
    if customPlacePed.type == 'export' and customPlacePed.resource and customPlacePed.name and GetResourceState(customPlacePed.resource) == 'started' then
      local resourceExports = exports[customPlacePed.resource]
      local placePedExport = resourceExports and resourceExports[customPlacePed.name]
      if type(placePedExport) == 'function' then
        local success, placedPoint = pcall(placePedExport, ped, target, heading)
        if success and placedPoint then return placedPoint end
      end
    end
  end

  local success, placedPoint = pcall(function()
    return exports.exec_framework:PlacePedAtPoint(ped, target, heading)
  end)
  if success and placedPoint then return placedPoint end

  RequestCollisionAtCoord(target.x, target.y, target.z)
  NetworkResurrectLocalPlayer(target.x, target.y, target.z, heading or 0.0, true, false)
  SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)

  local timeout = GetGameTimer() + 750
  while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
    Wait(0)
    RequestCollisionAtCoord(target.x, target.y, target.z)
  end

  SetEntityHeading(ped, heading or GetEntityHeading(ped))
  SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  return target
end

return SpawnBridge
