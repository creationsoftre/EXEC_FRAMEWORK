local function asVector3(point)
  if not point then return nil end
  if type(point) == 'vector3' then return point end
  if type(point) == 'userdata' and point.x and point.y and point.z then return point end
  if type(point) == 'table' then
    local x = tonumber(point.x or point[1])
    local y = tonumber(point.y or point[2])
    local z = tonumber(point.z or point[3])
    if x and y and z then return vector3(x, y, z) end
  end
  return nil
end

local function resolveGroundPoint(point, zHint)
  point = asVector3(point)
  if not point then return nil end
  local x, y = point.x + 0.0, point.y + 0.0
  local z = (point.z or zHint or 0.0) + 0.0
  local ok, ground = GetGroundZFor_3dCoord(x, y, (zHint or z) + 20.0, false)
  if ok then
    z = ground + 0.65
  end
  return vector3(x, y, z)
end

local function placePedAtPoint(ped, point, heading)
  point = asVector3(point)
  if ped == 0 or not point then return nil end

  local x = point.x + 0.0
  local y = point.y + 0.0
  local z = (point.z or 0.0) + 0.0
  RequestCollisionAtCoord(x, y, z)
  SetEntityCoordsNoOffset(ped, x, y, z + 2.0, false, false, false)

  local timeout = GetGameTimer() + 2500
  while GetGameTimer() < timeout do
    RequestCollisionAtCoord(x, y, z)
    local ok, ground = GetGroundZFor_3dCoord(x, y, z + 60.0, false)
    if ok then
      z = ground + 0.9
      break
    end
    if HasCollisionLoadedAroundEntity(ped) then
      local resolved = resolveGroundPoint(vector3(x, y, z), z)
      if resolved then
        z = (resolved.z or z) + 0.25
        break
      end
    end
    Wait(50)
  end

  RequestCollisionAtCoord(x, y, z)
  NetworkResurrectLocalPlayer(x, y, z, heading or 0.0, true, false)
  SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)

  timeout = GetGameTimer() + 1000
  while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
    Wait(0)
    RequestCollisionAtCoord(x, y, z)
  end

  SetEntityHeading(ped, heading or GetEntityHeading(ped))
  SetEntityVelocity(ped, 0.0, 0.0, 0.0)
  return vector3(x, y, z)
end

exports('ResolveGroundPoint', resolveGroundPoint)
exports('PlacePedAtPoint', placePedAtPoint)
