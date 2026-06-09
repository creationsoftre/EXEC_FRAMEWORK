local base = require "config.weapons"

local function emptyAddon()
  return { weapons = {}, categories = {}, locales = {}, attachments = {}, unlocks = {} }
end

local function logAddonIssue(message)
  if type(message) ~= "string" or message == "" then return end
  if type(print) == "function" then
    print(("[exec_framework] %s"):format(message))
  end
end

local function loadAddonConfig()
  local ok, mod = pcall(require, "config.addon_weapons")
  if ok and type(mod) == "table" then
    if mod.enabled == false then
      return emptyAddon()
    end
    return mod
  end

  if not ok and mod then
    logAddonIssue(("Failed to require config.addon_weapons (%s)"):format(tostring(mod)))
  end

  local canLoadFile = type(GetCurrentResourceName) == "function"
    and type(LoadResourceFile) == "function"
    and type(load) == "function"

  if canLoadFile then
    local resourceName = GetCurrentResourceName()
    local raw = LoadResourceFile(resourceName, "config/addon_weapons.lua")
    if raw and raw ~= "" then
      local chunk, compileErr = load(raw, ("@%s/config/addon_weapons.lua"):format(resourceName))
      if chunk then
        local okChunk, data = pcall(chunk)
        if okChunk and type(data) == "table" then
          if data.enabled == false then
            return emptyAddon()
          end
          return data
        else
          logAddonIssue(("Failed to evaluate config/addon_weapons.lua (%s)"):format(tostring(data)))
        end
      else
        logAddonIssue(("Failed to compile config/addon_weapons.lua (%s)"):format(tostring(compileErr)))
      end
    end
  end

  return emptyAddon()
end

local addon = loadAddonConfig()

addon.categories = addon.categories or {}
addon.locales = addon.locales or {}
addon.attachments = addon.attachments or {}
addon.unlocks = addon.unlocks or {}

if type(addon.weapons) == "table" then
  for _, weapon in ipairs(addon.weapons) do
    if type(weapon) == "table" and type(weapon.code) == "string" then
      if weapon.label and addon.locales[weapon.code] == nil then
        addon.locales[weapon.code] = weapon.label
      end
      if type(weapon.attachments) == "table" and addon.attachments[weapon.code] == nil then
        addon.attachments[weapon.code] = weapon.attachments
      end
      if type(weapon.unlock) == "table" and addon.unlocks[weapon.code] == nil then
        addon.unlocks[weapon.code] = weapon.unlock
      end
    end
  end
end

local categories = {}
for key, cat in pairs(base.categories or {}) do
  categories[key] = cat
end
for key, cat in pairs(addon.categories) do
  categories[key] = cat
end

local locales = {}
for key, value in pairs(base.locales or {}) do
  locales[key] = value
end
for key, value in pairs(addon.locales) do
  locales[key] = value
end

return {
  base = base,
  addon = addon,
  categories = categories,
  locales = locales,
}
