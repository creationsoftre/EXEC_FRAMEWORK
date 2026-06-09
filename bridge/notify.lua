local integrationConfig = require 'config.integrations'

local NotifyBridge = {}
local notifyConfig = (integrationConfig and integrationConfig.notify) or {}

-- CAPO: Client notifications pass through here so one config change can swap the notify resource.
local function sendClientNotification(notification)
  if notifyConfig.provider == 'none' then return false end

  if notifyConfig.provider == 'ox_lib' then
    if ExecUI and ExecUI._notify then
      ExecUI._notify(notification)
      return true
    end
    if lib and type(lib.notify) == 'function' then
      lib.notify(notification)
      return true
    end
  end

  if notifyConfig.provider == 'custom' then
    local customClientTarget = notifyConfig.client
    if type(customClientTarget) == 'table' and customClientTarget.type == 'event' and customClientTarget.name then
      TriggerEvent(customClientTarget.name, notification)
      return true
    end
    if type(customClientTarget) == 'table' and customClientTarget.type == 'export' and customClientTarget.resource and customClientTarget.name then
      if GetResourceState(customClientTarget.resource) ~= 'started' then return false end
      local resourceExports = exports[customClientTarget.resource]
      local notifyExport = resourceExports and resourceExports[customClientTarget.name]
      if type(notifyExport) ~= 'function' then return false end
      local success, errorMessage = pcall(notifyExport, notification)
      if not success then
        print(('[exec_framework] notify bridge failed (%s:%s): %s'):format(customClientTarget.resource, customClientTarget.name, errorMessage))
        return false
      end
      return true
    end
  end

  return false
end

function NotifyBridge.Send(target, notification)
  if type(target) == 'table' and notification == nil then
    return sendClientNotification(target)
  end

  if IsDuplicityVersion and IsDuplicityVersion() then
    if notifyConfig.provider == 'none' then return false end
    local clientEventName = notifyConfig.clientEvent or 'ox_lib:notify'
    TriggerClientEvent(clientEventName, target, notification)
    return true
  end

  return sendClientNotification(notification)
end

return NotifyBridge
