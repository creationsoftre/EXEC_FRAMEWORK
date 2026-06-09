local arenas = require "config.arenas"
local gameplay = require "config.gameplay"
local leaderboardCfg = require "config.leaderboard"

local bracketLabels = {}
for _, b in ipairs(arenas.brackets or {}) do
  bracketLabels[b.key] = b.label
end

local function resolveLocationLabel(locKey)
  if arenas.groups then
    for _, group in pairs(arenas.groups) do
      if group.locations and group.locations[locKey] then
        return group.locations[locKey].label or locKey
      end
    end
  elseif arenas.city and arenas.city[locKey] then
    return arenas.city[locKey].label or locKey
  end
  return locKey
end

local function modeLabel(modeKey)
  local mode = arenas.modes[modeKey]
  return (mode and mode.label) or modeKey
end

local function teamDisplayName(team)
  if type(team) ~= 'table' then return nil end
  if team.gangName and team.gangName ~= '' then return team.gangName end
  if team.label and team.label ~= '' then return team.label end
  if team.baseLabel and team.baseLabel ~= '' then return team.baseLabel end
  if team.key and team.key ~= '' then return team.key end
end

local function deriveVersusLabel(bracket, teams)
  if bracket ~= '1v1' and bracket ~= 'gangwar' then return nil end
  if type(teams) ~= 'table' or #teams == 0 then return nil end
  local left = teamDisplayName(teams[1])
  local right = teamDisplayName(teams[2])
  local fallbackLeft = bracket == 'gangwar' and 'Gang A' or 'Team A'
  local fallbackRight = bracket == 'gangwar' and 'Gang B' or 'Team B'
  left = (left and left ~= '') and left or fallbackLeft
  right = (right and right ~= '') and right or fallbackRight
  return string.format('%s vs %s', left, right)
end

local function newState()
  return {
    forceHidden = false,
    pauseHidden = false,
    visible = false,
    isSession = false,
    sessionId = nil,
    modeKey = nil,
    modeLabel = nil,
    locationKey = nil,
    locationLabel = nil,
    bracket = nil,
    bracketLabel = nil,
    bracketBaseLabel = nil,
    players = 0,
    minPlayers = 0,
    maxPlayers = 0,
    countdown = nil,
    firstTo = 30,
    status = "idle",
    scores = {},
    teams = nil,
    myTeam = nil,
    hardcore = false,
    myKills = 0,
    winner = nil,
    endingTimer = nil,
  }
end

local state = newState()

local function pushUiColors()
  SendNUIMessage({
    action = 'exec:uiColors',
    payload = {
      scoreboard = gameplay and gameplay.uiColors or {},
      leaderboard = leaderboardCfg and leaderboardCfg.uiColors or {},
    }
  })
end

local function pushState()
  SendNUIMessage({
    action = 'scoreboard:update',
    payload = {
      visible = state.visible and not (state.forceHidden or state.pauseHidden),
      isSession = state.isSession,
      sessionId = state.sessionId,
      modeLabel = state.modeLabel,
      locationLabel = state.locationLabel,
      bracketLabel = state.bracketLabel,
      status = state.status,
      players = state.players,
      minPlayers = state.minPlayers,
      maxPlayers = state.maxPlayers,
      countdown = state.countdown,
      endingTimer = state.endingTimer,
      firstTo = state.firstTo,
      myKills = state.myKills,
      winner = state.winner,
      leaderboard = state.scores,
      teams = state.teams,
      myTeam = state.myTeam,
      hardcore = state.hardcore,
      myServerId = GetPlayerServerId(PlayerId()),
    }
  })
end

local function resetState()
  local fresh = newState()
  for k in pairs(state) do
    state[k] = nil
  end
  for k, v in pairs(fresh) do
    state[k] = v
  end
  pushState()
end

CreateThread(function()
  Wait(0)
  SetNuiFocus(false, false)
  pushUiColors()
  resetState()
end)

CreateThread(function()
  local wasPaused = false
  while true do
    Wait(250)
    local isPaused = IsPauseMenuActive()
    if isPaused ~= wasPaused then
      wasPaused = isPaused
      state.pauseHidden = isPaused
      if state.visible then
        pushState()
      end
    end
  end
end)


RegisterCommand("exec_score", function()
  if not state.visible then return end
  state.forceHidden = not state.forceHidden
  pushState()
end, false)
RegisterKeyMapping("exec_score", "Toggle EXEC Scoreboard", "keyboard", "G")

RegisterNetEvent("exec:attachArenaHUD", function(mode, location, bracket, firstTo)
  state.visible = true
  state.forceHidden = false
  state.modeKey = mode
  state.modeLabel = modeLabel(mode)
  state.locationKey = location
  state.locationLabel = resolveLocationLabel(location)
  state.bracket = bracket or "ffa"
  state.bracketBaseLabel = bracketLabels[state.bracket] or ((state.bracket == "ffa") and "Playground" or state.bracket)
  state.bracketLabel = state.bracketBaseLabel
  state.isSession = state.bracket ~= "ffa"
  state.sessionId = nil
  state.players = 0
  state.minPlayers = 0
  state.maxPlayers = 0
  state.countdown = nil
  state.scores = {}
  state.myKills = 0
  state.winner = nil
  state.endingTimer = nil
  state.status = state.isSession and "waiting" or "playground"

  local sessionFirstTo = tonumber(firstTo)
  local modeInfo = arenas.modes[mode]
  if sessionFirstTo then
    state.firstTo = sessionFirstTo
  elseif modeInfo and modeInfo.firstTo then
    state.firstTo = modeInfo.firstTo
  else
    state.firstTo = 30
  end

  pushState()
end)

RegisterNetEvent("exec:detachArenaHUD", function()
  state.visible = false
  state.forceHidden = false
  state.isSession = false
  state.sessionId = nil
  state.status = "idle"
  state.scores = {}
  state.teams = nil
  state.myTeam = nil
  state.hardcore = false
  state.bracketLabel = nil
  state.bracketBaseLabel = nil
  pushState()
end)

RegisterNetEvent("exec:sessionLobbyUpdate", function(payload)
  if not payload or not state.isSession then return end
  if state.sessionId and payload.sessionId ~= state.sessionId then return end
  state.sessionId = payload.sessionId or state.sessionId
  state.players = payload.players or state.players
  state.minPlayers = payload.min or state.minPlayers
  state.maxPlayers = payload.max or state.maxPlayers
  state.firstTo = tonumber(payload.firstTo) or state.firstTo
  state.countdown = payload.countdown
  state.teams = payload.teams or state.teams
  state.hardcore = payload.hardcore or false
  if payload.teams then
    local myId = GetPlayerServerId(PlayerId())
    state.myTeam = nil
    for _, team in ipairs(payload.teams) do
      if team.members then
        for _, member in ipairs(team.members) do
          if member.id == myId then
            state.myTeam = team.key
            break
          end
        end
        if state.myTeam then break end
      end
    end
    local versus = deriveVersusLabel(state.bracket, payload.teams)
    if versus then
      state.bracketLabel = versus
    elseif state.bracketBaseLabel then
      state.bracketLabel = state.bracketBaseLabel
    end
  else
    state.myTeam = nil
    if state.bracketBaseLabel then
      state.bracketLabel = state.bracketBaseLabel
    end
  end
  if payload.active then
    state.status = "live"
  else
    if payload.countdown and payload.countdown > 0 then
      state.status = "countdown"
    else
      state.status = "waiting"
    end
  end
  pushState()
end)

RegisterNetEvent("exec:countdown", function(sessionId, seconds, players, minPlayers, maxPlayers)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.countdown = seconds or state.countdown
  state.players = players or state.players
  state.minPlayers = minPlayers or state.minPlayers
  state.maxPlayers = maxPlayers or state.maxPlayers
  state.status = "countdown"
  pushState()
end)

RegisterNetEvent("exec:countdownCancelled", function(sessionId, players, minPlayers)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.countdown = nil
  state.players = players or state.players
  state.minPlayers = minPlayers or state.minPlayers
  if state.status ~= "live" then
    state.status = "waiting"
  end
  pushState()
end)

RegisterNetEvent("exec:matchBegan", function(sessionId)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.countdown = nil
  state.status = "live"
  state.winner = nil
  state.endingTimer = nil
  state.myKills = 0
  state.scores = {}
  pushState()
end)
RegisterNetEvent("exec:matchGo", function(sessionId, duration)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  SendNUIMessage({
    action = 'scoreboard:go',
    payload = { duration = duration }
  })
end)

RegisterNetEvent("exec:preMatchCountdown", function(sessionId, remaining)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  SendNUIMessage({
    action = 'scoreboard:preMatchCountdown',
    payload = { remaining = remaining }
  })
end)

RegisterNetEvent("exec:onKillConfirmed", function(current, goal)
  state.myKills = current or (state.myKills + 1)
  state.firstTo = goal or state.firstTo

  local myId = GetPlayerServerId(PlayerId())
  if type(state.scores) == 'table' then
    local found = false
    for _, entry in ipairs(state.scores) do
      if entry.id == myId then
        entry.kills = state.myKills
        found = true
        break
      end
    end
    if not found then
      state.scores[#state.scores+1] = {
        id = myId,
        name = GetPlayerName(PlayerId()) or ('['..myId..']'),
        kills = state.myKills,
      }
    end
  end

  pushState()
end)

RegisterNetEvent("exec:scoreboardUpdate", function(sessionId, entries, firstTo, teams)
  if state.isSession and state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.scores = entries or {}
  state.firstTo = tonumber(firstTo) or state.firstTo
  state.teams = teams or state.teams
  if state.teams then
    state.myTeam = nil
    local myId = GetPlayerServerId(PlayerId())
    for _, team in ipairs(state.teams) do
      if team.members then
        for _, member in ipairs(team.members) do
          if member.id == myId then
            state.myTeam = team.key
            break
          end
        end
        if state.myTeam == team.key then break end
      end
    end
    local versus = deriveVersusLabel(state.bracket, state.teams)
    if versus then
      state.bracketLabel = versus
    elseif state.bracketBaseLabel then
      state.bracketLabel = state.bracketBaseLabel
    end
  end
  if not state.teams and state.bracketBaseLabel then
    state.bracketLabel = state.bracketBaseLabel
  end

  pushState()
end)

RegisterNetEvent("exec:endingIn", function(sessionId, seconds, winner)
  if not state.isSession then return end
  if state.sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.status = "ending"
  state.endingTimer = seconds
  state.winner = winner
  pushState()
end)

RegisterNetEvent("exec:sessionHardcore", function(sessionId, enabled)
  if not state.isSession then return end
  if state.sessionId and sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.hardcore = enabled and true or false
  pushState()
end)

RegisterNetEvent("exec:sessionTeamChanged", function(sessionId, teamKey)
  if not state.isSession then return end
  if state.sessionId and sessionId and sessionId ~= state.sessionId then return end
  state.sessionId = sessionId or state.sessionId
  state.myTeam = teamKey
  pushState()
end)
RegisterNetEvent("exec:matchEnded", function(_, winner)
  state.visible = false
  state.isSession = false
  state.sessionId = nil
  state.status = "idle"
  state.scores = {}
  state.winner = winner
  pushState()
  if winner then
    lib.notify({ title = "Match Ended", description = ("Winner: %s"):format(winner), type = "success" })
  end
end)

RegisterNetEvent("exec:character:reset", function()
  resetState()
end)







