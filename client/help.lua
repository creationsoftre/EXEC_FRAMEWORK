-- Hub keybind overlay (NUI)
local gameplay = require "config.gameplay"
local leaderboardCfg = require "config.leaderboard"
local arenas = require "config.arenas"

local hubCfg = gameplay.hubHelp or {}
local enabled = hubCfg.enabled ~= false
local showInHubOnly = hubCfg.showInHubOnly ~= false
local command = hubCfg.command or "exec_hubhelp"
local keybind = hubCfg.keybind or "H"
local title = hubCfg.title or "Hub Controls"
local showToggle = hubCfg.showToggle ~= false
local toggleLabel = hubCfg.toggleLabel or "Toggle Keybinds"

local hubActive = false
local userHidden = false
local multicharOpen = false
local appearanceOpen = false

local function keyLabel(value, fallback)
  if type(value) == "string" and value ~= "" then
    return value:upper()
  end
  return fallback
end

local function buildItems()
  local items = {}
  if type(hubCfg.items) == "table" then
    for _, item in ipairs(hubCfg.items) do
      if type(item) == "table" then
        local key = keyLabel(item.key, nil)
        local label = item.label
        if key and label and label ~= "" then
          items[#items + 1] = { key = key, label = label }
        end
      end
    end
  end

  if #items == 0 then
    local menuKey = keyLabel(gameplay.menu and gameplay.menu.keybind, "M")
    local menuLabel = (gameplay.menu and gameplay.menu.keybindLabel) or "Open EXEC Menu"
    items[#items + 1] = { key = menuKey, label = menuLabel }

    local lbKey = keyLabel(leaderboardCfg and leaderboardCfg.keybind, "L")
    local lbLabel = (leaderboardCfg and leaderboardCfg.keybindLabel) or "Open Leaderboard"
    items[#items + 1] = { key = lbKey, label = lbLabel }

    items[#items + 1] = { key = "G", label = "Toggle Scoreboard" }

    if showToggle then
      items[#items + 1] = { key = keyLabel(keybind, "H"), label = toggleLabel }
    end
  end

  return items
end

local items = buildItems()

local function pushHelp()
  if not enabled then
    SendNUIMessage({ action = "hubHelp:update", payload = { visible = false } })
    return
  end

  local visible = not userHidden
  if showInHubOnly then
    visible = visible and hubActive
  end
  if multicharOpen or appearanceOpen then
    visible = false
  end

  SendNUIMessage({
    action = "hubHelp:update",
    payload = {
      visible = visible,
      title = title,
      items = items,
    }
  })
end

RegisterCommand(command, function()
  if not enabled then return end
  userHidden = not userHidden
  pushHelp()
end, false)

RegisterKeyMapping(command, "Toggle Hub Keybinds", "keyboard", keybind)

RegisterNetEvent("exec:hub:state", function(state)
  hubActive = state and true or false
  pushHelp()
end)

RegisterNetEvent('exec_multichar:openMenu', function()
  multicharOpen = true
  pushHelp()
end)

RegisterNetEvent('exec_multichar:selected', function()
  multicharOpen = false
  pushHelp()
end)

RegisterNetEvent('exec_multichar:readyForPvp', function()
  multicharOpen = false
  pushHelp()
end)

RegisterNetEvent('exec_multichar:uiState', function(isOpen)
  multicharOpen = isOpen and true or false
  pushHelp()
end)

RegisterNetEvent('fivem-appearance:client:open', function()
  appearanceOpen = true
  pushHelp()
end)

RegisterNetEvent('fivem-appearance:client:close', function()
  appearanceOpen = false
  pushHelp()
end)

RegisterNetEvent('exec:appearance:open', function()
  appearanceOpen = true
  pushHelp()
end)

RegisterNetEvent('exec:appearance:close', function()
  appearanceOpen = false
  pushHelp()
end)

CreateThread(function()
  Wait(0)
  pushHelp()
end)

CreateThread(function()
  if not showInHubOnly then return end
  local hub = arenas and arenas.hub
  if not hub or not hub.spawn or not hub.radius then return end
  local hubPos = hub.spawn
  local radius = hub.radius or 60.0
  while true do
    local ped = PlayerPedId()
    if ped ~= 0 then
      local pos = GetEntityCoords(ped)
      local inside = #(pos - hubPos) <= radius
      if inside ~= hubActive then
        hubActive = inside
        pushHelp()
      end
    end
    Wait(1000)
  end
end)

AddEventHandler("onResourceStop", function(res)
  if res == GetCurrentResourceName() then
    SendNUIMessage({ action = "hubHelp:update", payload = { visible = false } })
  end
end)
