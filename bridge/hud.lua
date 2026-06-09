local integrationConfig = require 'config.integrations'

local HudBridge = {}
local hudConfig = (integrationConfig and integrationConfig.hud) or {}

local function normalizeArguments(value)
  if value == nil then return {} end
  if type(value) == 'table' then return value end
  return { value }
end

-- CAPO: HUD visibility should be changed through this bridge instead of hard-coding a HUD resource.
local function callHudTarget(hudTarget)
  if hudConfig.provider == 'none' or not hudTarget then return false end

  if hudTarget.type == 'event' and hudTarget.name then
    TriggerEvent(hudTarget.name, table.unpack(normalizeArguments(hudTarget.args)))
    return true
  end

  if hudTarget.type == 'export' and hudTarget.name then
    local hudResource = hudTarget.resource or hudConfig.resource
    if not hudResource or GetResourceState(hudResource) ~= 'started' then return false end
    local resourceExports = exports[hudResource]
    local hudExport = resourceExports and resourceExports[hudTarget.name]
    if type(hudExport) ~= 'function' then return false end
    local success, errorMessage = pcall(hudExport, table.unpack(normalizeArguments(hudTarget.args)))
    if not success then
      print(('[exec_framework] HUD bridge failed (%s:%s): %s'):format(hudResource, hudTarget.name, errorMessage))
      return false
    end
    return true
  end

  return false
end

function HudBridge.Hide()
  return callHudTarget(hudConfig.hide)
end

function HudBridge.Show()
  return callHudTarget(hudConfig.show)
end

function HudBridge.SetVisible(visible)
  if visible then
    return HudBridge.Show()
  end
  return HudBridge.Hide()
end

return HudBridge
