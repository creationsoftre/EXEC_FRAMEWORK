local integrationConfig = require 'config.integrations'

local TargetBridge = {}
local targetConfig = (integrationConfig and integrationConfig.target) or {}

-- CAPO: Use this bridge for future hub NPCs, props, or zone interactions instead of calling a target script directly.
function TargetBridge.AddEntity(entity, options)
  if targetConfig.provider == 'none' then return false end

  if targetConfig.provider == 'ox_target' then
    local targetResource = targetConfig.resource or 'ox_target'
    if GetResourceState(targetResource) ~= 'started' then return false end
    local success, errorMessage = pcall(function()
      exports[targetResource]:addLocalEntity(entity, options)
    end)
    if not success then
      print(('[exec_framework] target bridge failed (%s:addLocalEntity): %s'):format(targetResource, errorMessage))
    end
    return success
  end

  if targetConfig.provider == 'qb-target' then
    local targetResource = targetConfig.resource or 'qb-target'
    if GetResourceState(targetResource) ~= 'started' then return false end
    local success, errorMessage = pcall(function()
      exports[targetResource]:AddTargetEntity(entity, { options = options })
    end)
    if not success then
      print(('[exec_framework] target bridge failed (%s:AddTargetEntity): %s'):format(targetResource, errorMessage))
    end
    return success
  end

  if targetConfig.provider == 'custom' and type(targetConfig.addEntity) == 'table' then
    local customTarget = targetConfig.addEntity
    if customTarget.type == 'event' and customTarget.name then
      TriggerEvent(customTarget.name, entity, options)
      return true
    end
    if customTarget.type == 'export' and customTarget.resource and customTarget.name and GetResourceState(customTarget.resource) == 'started' then
      local resourceExports = exports[customTarget.resource]
      local addEntityExport = resourceExports and resourceExports[customTarget.name]
      if type(addEntityExport) == 'function' then
        local success = pcall(addEntityExport, entity, options)
        return success
      end
    end
  end

  return false
end

function TargetBridge.RemoveEntity(entity)
  if targetConfig.provider == 'ox_target' then
    local targetResource = targetConfig.resource or 'ox_target'
    if GetResourceState(targetResource) == 'started' then
      local success, errorMessage = pcall(function()
        exports[targetResource]:removeLocalEntity(entity)
      end)
      if not success then
        print(('[exec_framework] target bridge failed (%s:removeLocalEntity): %s'):format(targetResource, errorMessage))
      end
      return success
    end
  end
  if targetConfig.provider == 'custom' and type(targetConfig.removeEntity) == 'table' then
    local customTarget = targetConfig.removeEntity
    if customTarget.type == 'event' and customTarget.name then
      TriggerEvent(customTarget.name, entity)
      return true
    end
    if customTarget.type == 'export' and customTarget.resource and customTarget.name and GetResourceState(customTarget.resource) == 'started' then
      local resourceExports = exports[customTarget.resource]
      local removeEntityExport = resourceExports and resourceExports[customTarget.name]
      if type(removeEntityExport) == 'function' then
        local success = pcall(removeEntityExport, entity)
        return success
      end
    end
  end
  return false
end

return TargetBridge
