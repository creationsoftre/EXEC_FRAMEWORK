local cfg = require "config.leaderboard"

local cooldownMs = ((cfg and cfg.cooldownSeconds) or 0) * 1000
local lastRequest = 0
local isOpen = false

local function notify(title, description, typ)
  lib.notify({ title = title, description = description, type = typ or 'inform' })
end

local function closeLeaderboard()
  if not isOpen then return end
  isOpen = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'leaderboard:close' })
end

RegisterNUICallback('leaderboardClose', function(_, cb)
  closeLeaderboard()
  cb({})
end)

local function openLeaderboard()
  if isOpen then
    closeLeaderboard()
    return
  end

  local now = GetGameTimer()
  if cooldownMs > 0 and (now - lastRequest) < cooldownMs then
    local remaining = math.ceil((cooldownMs - (now - lastRequest)) / 1000)
    notify('Leaderboard', ('Please wait %ds before refreshing.'):format(remaining), 'error')
    return
  end

  lastRequest = now

  lib.callback('exec:getGlobalLeaderboard', false, function(data)
    if not data then
      notify('Leaderboard', 'No leaderboard data available.', 'error')
      return
    end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'leaderboard:open', payload = data })
  end)
end

if cfg and cfg.command and cfg.command ~= '' then
  RegisterCommand(cfg.command, openLeaderboard, false)
  if cfg.keybind and cfg.keybind ~= false then
    RegisterKeyMapping(cfg.command, cfg.keybindLabel or 'Open EXEC Leaderboard', 'keyboard', cfg.keybind)
  end
end

RegisterNetEvent('exec:leaderboard:open', openLeaderboard)
RegisterNetEvent('exec:leaderboard:close', closeLeaderboard)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    closeLeaderboard()
  end
end)

RegisterNetEvent('exec:character:reset', closeLeaderboard)

