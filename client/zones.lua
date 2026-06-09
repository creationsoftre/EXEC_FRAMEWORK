local cfg = require 'config.arenas'
local g = require 'config.gameplay'
local combatDomeCfg = (g and g.combatDome) or {}
local focusedLocation = nil

AddEventHandler('exec:safeMode', function(state)
  local ped = PlayerPedId()
  SetEntityInvincible(ped, state)
  SetPedCanRagdoll(ped, not state)
end)

RegisterNetEvent('exec:zoneMarker:setFocus', function(location)
  focusedLocation = type(location) == 'string' and location or nil
end)

RegisterNetEvent('exec:zoneMarker:clearFocus', function()
  focusedLocation = nil
end)

CreateThread(function()
  while true do
    Wait(0)
    local markerCfg = g.zoneMarker
    if markerCfg and markerCfg.enabled then
      local function resolveMarkerRadius(loc)
        local base = tonumber(loc and loc.domeRadius) or 25.0
        if markerCfg.matchCombatBoundary ~= false
          and combatDomeCfg.enabled ~= false
          and tonumber(loc and loc.domeRadius)
          and tonumber(loc.domeRadius) > 0 then
          base = base + (tonumber(combatDomeCfg.entryBuffer) or 0.75)
        end
        return base
      end

      local function iterLocations()
        if cfg.groups then
          for _, group in pairs(cfg.groups) do
            for locKey, l in pairs(group.locations) do coroutine.yield(locKey, l) end
          end
        else
          for locKey, l in pairs(cfg.city) do coroutine.yield(locKey, l) end
        end
      end
      local radiusScale = markerCfg.radiusScale or 1.0
      local markerType = markerCfg.type or 28
      for locKey, loc in coroutine.wrap(iterLocations) do
        if loc.showMarker ~= false then
          if markerCfg.focusActiveZoneOnly ~= false and focusedLocation and locKey ~= focusedLocation then
            goto continue
          end
          local baseRadius = resolveMarkerRadius(loc)
          local sizeXY = baseRadius * radiusScale * 2.0
          local col = markerCfg.color or { r = 0, g = 150, b = 255 }
          local alpha = markerCfg.alpha or 100
          local usePreciseActiveZone = markerCfg.preciseActiveZone ~= false
            and focusedLocation ~= nil
            and locKey == focusedLocation
            and markerCfg.matchCombatBoundary ~= false
          if usePreciseActiveZone then
            DrawMarker(1, loc.center.x, loc.center.y, loc.center.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sizeXY, sizeXY, markerCfg.preciseHeight or 3.0, col.r, col.g, col.b, markerCfg.preciseAlpha or alpha, false, true, 2, nil, nil, false)
            if markerCfg.showGroundRing ~= false then
              DrawMarker(1, loc.center.x, loc.center.y, loc.center.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sizeXY, sizeXY, markerCfg.ringHeight or 0.18, col.r, col.g, col.b, markerCfg.ringAlpha or alpha, false, true, 2, nil, nil, false)
            end
          elseif markerCfg.shape == 'sphere' or markerCfg.shape == 'dome' then
            local verticalScale = markerCfg.verticalScale or (markerCfg.shape == 'dome' and 1.5 or 1.0)
            local sizeZ = sizeXY * verticalScale
            local zOff = markerCfg.zOffset
            if zOff == nil then
              zOff = (markerCfg.shape == 'dome') and (sizeZ * 0.5) or 0.5
            end
            DrawMarker(markerType, loc.center.x, loc.center.y, loc.center.z + zOff, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sizeXY, sizeXY, sizeZ, col.r, col.g, col.b, alpha, false, true, 2, nil, nil, false)
            if markerCfg.showGroundRing ~= false then
              DrawMarker(1, loc.center.x, loc.center.y, loc.center.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sizeXY, sizeXY, markerCfg.ringHeight or 0.18, col.r, col.g, col.b, markerCfg.ringAlpha or alpha, false, true, 2, nil, nil, false)
            end
          else
            local height = markerCfg.height or 3.0
            local zOff = markerCfg.zOffset or 0.5
            DrawMarker(markerType, loc.center.x, loc.center.y, loc.center.z + zOff, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sizeXY, sizeXY, height, col.r, col.g, col.b, alpha, false, true, 2, nil, nil, false)
          end
        end
        ::continue::
      end
    end
  end
end)







