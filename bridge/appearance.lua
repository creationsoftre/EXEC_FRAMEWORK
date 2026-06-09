local integrationConfig = require 'config.integrations'

local AppearanceBridge = {}
local appearanceConfig = (integrationConfig and integrationConfig.appearance) or {}

local function isResourceStarted(resourceName)
  return resourceName and GetResourceState(resourceName) == 'started'
end

local function copyTable(source)
  local copied = {}
  if type(source) ~= 'table' then return copied end
  for key, value in pairs(source) do
    copied[key] = value
  end
  return copied
end

local function resolveAppearanceOptions(overrideOptions)
  local options = copyTable(appearanceConfig.options)
  if next(options) == nil then
    options = {
      ped = true,
      headBlend = true,
      faceFeatures = true,
      headOverlays = true,
      components = true,
      props = true,
      tattoos = true,
    }
  end

  if type(overrideOptions) == 'table' then
    for key, value in pairs(overrideOptions) do
      options[key] = value
    end
  end

  return options
end

local function completeAppearanceOpen(providerName, onComplete, appearance)
  TriggerEvent('exec:appearance:close', providerName)
  if onComplete then onComplete(appearance) end
end

local function captureCurrentAppearance(appearance)
  local appearanceResource = appearanceConfig.resource or appearanceConfig.provider
  local captured = nil

  if appearanceConfig.provider == 'fivem-appearance' and isResourceStarted(appearanceResource) then
    pcall(function()
      local resourceExports = exports[appearanceResource]
      if resourceExports and type(resourceExports.getPedAppearance) == 'function' then
        captured = resourceExports:getPedAppearance(PlayerPedId())
      end
    end)
  end

  local out = type(captured) == 'table' and captured or appearance
  if type(out) ~= 'table' then out = {} end

  local ped = PlayerPedId()
  if ped ~= 0 and DoesEntityExist(ped) then
    out._execModelHash = GetEntityModel(ped)
    if appearanceConfig.provider == 'fivem-appearance' and isResourceStarted(appearanceResource) then
      pcall(function()
        local resourceExports = exports[appearanceResource]
        if resourceExports and type(resourceExports.getPedModel) == 'function' then
          out._execModel = resourceExports:getPedModel(ped)
        end
      end)
    end
  end

  return out
end

function AppearanceBridge.IsAvailable()
  if appearanceConfig.provider == 'none' then return false end
  local appearanceResource = appearanceConfig.resource or appearanceConfig.provider
  if not isResourceStarted(appearanceResource) then return false end
  if appearanceConfig.provider == 'fivem-appearance' then
    local resourceExports = exports[appearanceResource]
    return resourceExports and type(resourceExports.startPlayerCustomization) == 'function'
  end
  return true
end

-- CAPO: Every appearance provider should emit the same framework open/close events from this bridge.
function AppearanceBridge.Open(onComplete, appearanceOptions)
  if appearanceConfig.provider == 'none' then
    return false, 'disabled'
  end

  local appearanceResource = appearanceConfig.resource or appearanceConfig.provider
  local resolvedOptions = resolveAppearanceOptions(appearanceOptions)

  if appearanceConfig.provider == 'fivem-appearance' then
    if not AppearanceBridge.IsAvailable() then
      return false, 'unavailable'
    end

    local function finishAppearance(appearance)
      completeAppearanceOpen(appearanceConfig.provider, onComplete, appearance)
    end

    TriggerEvent('exec:appearance:open', appearanceConfig.provider)
    local success, errorMessage = pcall(function()
      exports['fivem-appearance']:startPlayerCustomization(finishAppearance, resolvedOptions)
    end)

    if not success then
      TriggerEvent('exec:appearance:close', appearanceConfig.provider)
      return false, errorMessage
    end
    return true
  end

  local openTarget = appearanceConfig.open
  if type(openTarget) ~= 'table' then
    return false, 'missing_config'
  end

  if openTarget.type == 'event' and openTarget.name then
    TriggerEvent('exec:appearance:open', appearanceConfig.provider)
    TriggerEvent(openTarget.name, function(appearance)
      completeAppearanceOpen(appearanceConfig.provider, onComplete, appearance)
    end, resolvedOptions)
    return true
  end

  if openTarget.type == 'export' and openTarget.name then
    appearanceResource = openTarget.resource or appearanceResource
    if not isResourceStarted(appearanceResource) then return false, 'unavailable' end
    local resourceExports = exports[appearanceResource]
    local openAppearanceExport = resourceExports and resourceExports[openTarget.name]
    if type(openAppearanceExport) ~= 'function' then return false, 'unavailable' end
    TriggerEvent('exec:appearance:open', appearanceConfig.provider)
    local success, errorMessage = pcall(openAppearanceExport, function(appearance)
      completeAppearanceOpen(appearanceConfig.provider, onComplete, appearance)
    end, resolvedOptions)
    if not success then
      TriggerEvent('exec:appearance:close', appearanceConfig.provider)
      return false, errorMessage
    end
    return true
  end

  return false, 'unsupported'
end

function AppearanceBridge.Save(citizenId, appearance)
  local saveEventName = appearanceConfig.saveEvent
  if type(saveEventName) ~= 'string' or saveEventName == '' or not citizenId then return false end
  TriggerServerEvent(saveEventName, citizenId, captureCurrentAppearance(appearance))
  return true
end

return AppearanceBridge
