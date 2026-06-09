local integrationConfig = require 'config.integrations'
local gameplayConfig = require 'config.gameplay'

local KillfeedBridge = {}
local killfeedConfig = (integrationConfig and integrationConfig.killfeed) or {}

-- CAPO: Kill payloads leave the framework here, so external killfeeds only need config entries.
local function getKillfeedTargets()
  if killfeedConfig.provider == 'none' then return {} end
  if type(killfeedConfig.targets) == 'table' and #killfeedConfig.targets > 0 then
    return killfeedConfig.targets
  end
  if type(gameplayConfig.killfeeds) == 'table' and #gameplayConfig.killfeeds > 0 then
    return gameplayConfig.killfeeds
  end
  return { { type = 'event', name = 'exec_killfeed:onKill' } }
end

function KillfeedBridge.Push(killPayload)
  local wasDispatched = false

  for _, killfeedTarget in ipairs(getKillfeedTargets()) do
    local targetType = killfeedTarget.type or 'event'
    if targetType == 'event' and killfeedTarget.name then
      TriggerEvent(killfeedTarget.name, killPayload)
      wasDispatched = true
    elseif targetType == 'export' and killfeedTarget.resource and killfeedTarget.name then
      if GetResourceState(killfeedTarget.resource) == 'started' then
        local resourceExports = exports[killfeedTarget.resource]
        local killfeedExport = resourceExports and resourceExports[killfeedTarget.name]
        if type(killfeedExport) == 'function' then
          local success, errorMessage = pcall(killfeedExport, resourceExports, killPayload)
          if not success then
            print(('[exec_framework] killfeed bridge failed (%s:%s): %s'):format(killfeedTarget.resource, killfeedTarget.name, errorMessage))
          end
          wasDispatched = true
        end
      end
    end
  end

  return wasDispatched
end

return KillfeedBridge
