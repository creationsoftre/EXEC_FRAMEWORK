local DB = require 'server.db'
local defs = require 'shared.leaderboard_defs'
local Identity = require 'server.identity'

local Stats = {}

local json = json

local MODE_ORDER = defs.MODE_ORDER
local MODE_SPECS = defs.MODE_SPECS
local AWARD_ORDER = defs.AWARD_ORDER
local AWARD_SPECS = defs.AWARD_SPECS

local function resolveIdentity(src)
  local identifier, citizenId, license = Identity.ensureIdentifier(src)
  citizenId = citizenId or identifier or license
  license = license or identifier or citizenId
  if not citizenId then
    return nil, nil
  end
  return citizenId, license or ''
end

local function ensurePlayer(citizenId, license, name)
  if not citizenId then return end
  DB.exec([[
    INSERT INTO exec_players (citizenid, license, display_name)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE
      license = VALUES(license),
      display_name = VALUES(display_name)
  ]], { citizenId, license or '', name or '' })
end

local function upsertStat(citizenId, license, mode, kills, deaths, wins, losses, timePlayed)
  if not citizenId then return end
  DB.exec([[
    INSERT INTO exec_stats (citizenid, license, mode, kills, deaths, wins, losses, time_played, last_played)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON DUPLICATE KEY UPDATE
      kills = kills + VALUES(kills),
      deaths = deaths + VALUES(deaths),
      wins = wins + VALUES(wins),
      losses = losses + VALUES(losses),
      time_played = time_played + VALUES(time_played),
      last_played = CURRENT_TIMESTAMP
  ]], { citizenId, license or '', mode, kills, deaths, wins, losses, timePlayed })
end

local function computeMetrics(row)
  local kills = tonumber(row.kills) or 0
  local deaths = tonumber(row.deaths) or 0
  local wins = tonumber(row.wins) or 0
  local losses = tonumber(row.losses) or 0
  local timePlayed = tonumber(row.time_played) or 0
  local games = wins + losses

  local kdr = 0.0
  if deaths <= 0 then
    kdr = kills
  else
    kdr = kills / deaths
  end

  local winRate = 0.0
  if games > 0 then
    winRate = wins / games
  end

  local killsPerMinute = 0.0
  if timePlayed > 0 then
    killsPerMinute = kills / (timePlayed / 60.0)
  end

  return {
    wins = wins,
    losses = losses,
    games = games,
    kills = kills,
    deaths = deaths,
    kdr = kdr,
    win_rate = winRate,
    kills_per_min = killsPerMinute,
    time_played = timePlayed,
  }
end

local function insertProfileRow(entityType, entityId, entityName, modeKey, metrics, capturedAt)
  DB.exec([[
    INSERT INTO exec_stat_profiles (entity_type, entity_id, entity_name, mode, metrics, captured_at)
    VALUES (?, ?, ?, ?, ?, ?)
  ]], { entityType, entityId, entityName, modeKey, json.encode(metrics), capturedAt })
end

local function rebuildProfilesAndAwards()
  local rows = DB.query([[
    SELECT s.citizenid, s.license, s.mode, s.kills, s.deaths, s.wins, s.losses, s.time_played,
           p.display_name
    FROM exec_stats s
    LEFT JOIN exec_players p ON p.citizenid = s.citizenid
  ]], {})

  DB.exec('DELETE FROM exec_stat_profiles', {})
  DB.exec('DELETE FROM exec_stat_awards', {})

  local perMode = {}
  local global = {}

  for _, row in ipairs(rows or {}) do
    local modeKey = row.mode
    local spec = MODE_SPECS[modeKey]
    if spec then
      perMode[modeKey] = perMode[modeKey] or {}
      perMode[modeKey][#perMode[modeKey]+1] = row
    end

    local citizenId = row.citizenid or ''
    local key = citizenId ~= '' and citizenId or (row.license or '')
    if key ~= '' then
      local agg = global[key]
      if not agg then
        agg = {
          citizenid = citizenId ~= '' and citizenId or nil,
          license = row.license,
          display_name = row.display_name,
          kills = 0,
          deaths = 0,
          wins = 0,
          losses = 0,
          time_played = 0,
        }
        global[key] = agg
      end
      agg.display_name = row.display_name or agg.display_name
      agg.kills = agg.kills + (tonumber(row.kills) or 0)
      agg.deaths = agg.deaths + (tonumber(row.deaths) or 0)
      agg.wins = agg.wins + (tonumber(row.wins) or 0)
      agg.losses = agg.losses + (tonumber(row.losses) or 0)
      agg.time_played = agg.time_played + (tonumber(row.time_played) or 0)
    end
  end

  local capturedAt = os.date('%Y-%m-%d %H:%M:%S')

  for modeKey, rowsForMode in pairs(perMode) do
    for _, row in ipairs(rowsForMode) do
      local metrics = computeMetrics(row)
      local entityId = (row.citizenid and row.citizenid ~= '' and row.citizenid) or (row.license or '')
      if entityId ~= '' then
        local name = row.display_name or entityId
        insertProfileRow('player', entityId, name, modeKey, metrics, capturedAt)
      end
    end
  end

  for key, agg in pairs(global) do
    local entityId = agg.citizenid or agg.license or key
    if entityId ~= '' then
      local name = agg.display_name or entityId
      local metrics = computeMetrics(agg)
      insertProfileRow('player', entityId, name, 'global', metrics, capturedAt)
      agg.metrics = metrics
      agg.entityId = entityId
      agg.name = name
    end
  end

  for _, awardKey in ipairs(AWARD_ORDER) do
    local spec = AWARD_SPECS[awardKey]
    if spec then
      local entries = {}
      for key, agg in pairs(global) do
        local metrics = agg.metrics or computeMetrics(agg)
        local value = metrics[spec.metric]
        local games = metrics.games or ((agg.wins or 0) + (agg.losses or 0))
        if value ~= nil then
          if not spec.minGames or (games and games >= spec.minGames) then
            local entityId = agg.entityId or agg.citizenid or agg.license or key
            if entityId ~= '' then
              entries[#entries+1] = {
                entityId = entityId,
                name = agg.name or agg.display_name or entityId or key,
                value = value,
                games = games,
              }
            end
          end
        end
      end
      table.sort(entries, function(a, b)
        if spec.sortDirection == 'asc' then
          if a.value == b.value then
            return a.name < b.name
          end
          return a.value < b.value
        end
        if a.value == b.value then
          return a.name < b.name
        end
        return a.value > b.value
      end)

      local limit = spec.limit or 5
      for idx = 1, math.min(#entries, limit) do
        local entry = entries[idx]
        DB.exec([[
          INSERT INTO exec_stat_awards (award_key, entity_type, entity_id, entity_name, value, extra, captured_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
          awardKey,
          'player',
          entry.entityId,
          entry.name,
          entry.value,
          json.encode({ games = entry.games }),
          capturedAt,
        })
      end
    end
  end

  DB.exec([[
    INSERT INTO exec_unique (key_name, value)
    VALUES ('leaderboard_generated_at', JSON_OBJECT('timestamp', ?))
    ON DUPLICATE KEY UPDATE value = VALUES(value)
  ]], { capturedAt })
  TriggerEvent('exec:leaderboard:invalidate')
end

function Stats.recordMatch(session, result)
  if not session or not session.players then return end

  local matchStats = session.matchStats or {}
  local startedAt = matchStats.started or session.started or os.time()
  local duration = math.max(1, os.time() - startedAt)
  local winners = {}
  local noContest = result and result.noContest == true

  if result and not noContest then
    if result.playerId then
      winners[result.playerId] = true
    end
    if result.teamKey then
      for pid, info in pairs(session.players) do
        if info and info.team == result.teamKey then
          winners[pid] = true
        end
      end
    end
  end

  local modeKey = session.bracket or session.mode or 'global'
  for pid, _ in pairs(session.players) do
    local citizenId, license = resolveIdentity(pid)
    if citizenId then
      local name = GetPlayerName(pid) or ('[' .. pid .. ']')
      ensurePlayer(citizenId, license, name)

      local entry = matchStats.players and matchStats.players[pid] or {}
      local kills = entry.kills or 0
      local deaths = entry.deaths or 0
      local win = (not noContest and winners[pid]) and 1 or 0
      local loss = (not noContest and not winners[pid]) and 1 or 0

      upsertStat(citizenId, license, modeKey, kills, deaths, win, loss, duration)
    end
  end

  rebuildProfilesAndAwards()
end

function Stats.rebuild()
  rebuildProfilesAndAwards()
end

return Stats
