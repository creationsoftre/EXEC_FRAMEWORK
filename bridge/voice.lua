local integrationConfig = require 'config.integrations'

local VoiceBridge = {}
local voiceConfig = (integrationConfig and integrationConfig.voice) or {}

-- CAPO: Voice state is normalized here so HUDs and gameplay can support pma/mumble/native talking checks.
function VoiceBridge.IsTalking(playerId)
  if voiceConfig.provider == 'none' then return false end

  local stateKey = voiceConfig.talkingStateKey
  if stateKey and LocalPlayer and LocalPlayer.state[stateKey] ~= nil then
    return LocalPlayer.state[stateKey] and true or false
  end

  local customTalking = voiceConfig.isTalking
  if voiceConfig.provider == 'custom' and type(customTalking) == 'table' then
    if customTalking.type == 'event' and customTalking.name then
      local handled = false
      local talking = false
      TriggerEvent(customTalking.name, playerId or PlayerId(), function(result)
        handled = true
        talking = result and true or false
      end)
      if handled then return talking end
    end
    if customTalking.type == 'export' and customTalking.resource and customTalking.name and GetResourceState(customTalking.resource) == 'started' then
      local resourceExports = exports[customTalking.resource]
      local isTalkingExport = resourceExports and resourceExports[customTalking.name]
      if type(isTalkingExport) == 'function' then
        local success, talking = pcall(isTalkingExport, playerId or PlayerId())
        if success then return talking and true or false end
      end
    end
  end

  return NetworkIsPlayerTalking(playerId or PlayerId()) and true or false
end

return VoiceBridge
