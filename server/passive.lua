local passiveStates = {}

local function sanitizeAlpha(value)
  local alpha = tonumber(value)
  if not alpha then return nil end
  alpha = math.floor(alpha)
  if alpha < 0 then return nil end
  if alpha > 255 then alpha = 255 end
  return alpha
end

RegisterNetEvent('exec:passive:syncState', function(active, alpha, opaque)
  local src = source
  local isPassive = active and true or false
  local alphaValue = sanitizeAlpha(alpha)
  local isOpaque = opaque == true

  if isPassive then
    passiveStates[src] = { isPassive = true, alpha = alphaValue, opaque = isOpaque }
  else
    passiveStates[src] = nil
  end

  TriggerClientEvent('exec:passive:remoteState', -1, src, isPassive, alphaValue, isOpaque)
end)

RegisterNetEvent('exec:passive:requestSync', function()
  local src = source
  local snapshot = {}
  for playerId, data in pairs(passiveStates) do
    if data and data.isPassive then
      snapshot[#snapshot+1] = { id = playerId, active = true, alpha = data.alpha, opaque = data.opaque == true }
    end
  end
  TriggerClientEvent('exec:passive:remoteSnapshot', src, snapshot)
end)

AddEventHandler('playerDropped', function()
  local src = source
  local data = passiveStates[src]
  if data and data.isPassive then
    TriggerClientEvent('exec:passive:remoteState', -1, src, false, nil)
  end
  passiveStates[src] = nil
end)
