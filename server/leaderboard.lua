local cfg = require "config.leaderboard"
local DB = require "server.db"
local defs = require "shared.leaderboard_defs"

local json = json

local TOP_ENTRIES = (cfg and cfg.topEntries) or 10
local TOP_AWARDS = (cfg and cfg.topAwards) or math.min(5, TOP_ENTRIES)
local CACHE_SECONDS = (cfg and cfg.cacheSeconds) or 60

local MODE_ORDER = defs.MODE_ORDER
local MODE_SPECS = defs.MODE_SPECS
local AWARD_ORDER = defs.AWARD_ORDER
local AWARD_SPECS = defs.AWARD_SPECS

local Leaderboard = {}

local cache = { data = nil, expiresAt = nil }

local function minMatchesForMode(mode)
  if not cfg then return 0 end
  local rules = cfg.minMatches
  local value

  if type(rules) == 'number' then
    value = rules
  elseif type(rules) == 'table' then
    if type(rules.perMode) == 'table' and type(rules.perMode[mode]) == 'number' then
      value = rules.perMode[mode]
    elseif type(rules[mode]) == 'number' then
      value = rules[mode]
    elseif type(rules.default) == 'number' then
      value = rules.default
    end
  end

  if type(value) ~= 'number' then
    return 0
  end

  if value < 0 then
    value = 0
  end

  return math.floor(value + 0.0001)
end

local function toIsoString(ts)
  if ts == nil or ts == '' then return nil end
  if type(ts) == 'number' then
    return os.date('!%Y-%m-%dT%H:%M:%SZ', ts)
  end
  if type(ts) ~= 'string' then
    ts = tostring(ts)
  end
  if ts:find('T', 1, true) then return ts end
  return ts:gsub(' ', 'T') .. 'Z'
end

local function safeDecode(payload)
  if not payload or payload == '' then return {} end
  local ok, result = pcall(json.decode, payload)
  if not ok or type(result) ~= 'table' then
    return {}
  end
  return result
end

local function buildModeBuckets()
  local buckets = {}
  for _, key in ipairs(MODE_ORDER) do
    local spec = MODE_SPECS[key]
    if spec then
      buckets[key] = {
        key = key,
        label = spec.label,
        entityType = spec.entityType,
        metricOrder = spec.metricOrder,
        metrics = spec.metrics,
        entries = {},
        capturedAt = nil,
        minMatches = minMatchesForMode(key),
        filteredCount = 0,
      }
    end
  end
  return buckets
end

local function mapPerMode(rows)
  local buckets = buildModeBuckets()
  local latest = nil

  local function metricCompare(aEntry, bEntry, key, direction)
    if not key then return nil end
    local dir = direction == 'asc' and 'asc' or 'desc'
    local aVal = aEntry.metrics and tonumber(aEntry.metrics[key])
    local bVal = bEntry.metrics and tonumber(bEntry.metrics[key])
    if aVal == nil then
      aVal = dir == 'asc' and math.huge or -math.huge
    end
    if bVal == nil then
      bVal = dir == 'asc' and math.huge or -math.huge
    end
    if aVal == bVal then
      return nil
    end
    if dir == 'asc' then
      return aVal < bVal
    end
    return aVal > bVal
  end

  for _, row in ipairs(rows or {}) do
    local spec = MODE_SPECS[row.mode]
    local bucket = spec and buckets[row.mode]
    if bucket then
      if row.captured_at then
        if not bucket.capturedAt or row.captured_at > bucket.capturedAt then
          bucket.capturedAt = row.captured_at
        end
        if not latest or row.captured_at > latest then
          latest = row.captured_at
        end
      end

      local rawMetrics = safeDecode(row.metrics)
      local matchesPlayed = tonumber(rawMetrics.games) or 0
      local requiredMatches = bucket.minMatches or 0
      if matchesPlayed < requiredMatches then
        bucket.filteredCount = (bucket.filteredCount or 0) + 1
      else
        local filtered = {}
        for _, key in ipairs(spec.metricOrder) do
          local value = rawMetrics[key]
          if value ~= nil then
            filtered[key] = value
          end
        end
        if filtered.games == nil and rawMetrics.games ~= nil then
          filtered.games = rawMetrics.games
        end
        bucket.entries[#bucket.entries+1] = {
          entityType = row.entity_type,
          entityId = row.entity_id,
          name = row.entity_name,
          metrics = filtered,
          capturedAt = row.captured_at,
          matches = matchesPlayed,
        }
      end
    end
  end

  for key, spec in pairs(MODE_SPECS) do
    local bucket = buckets[key]
    local entries = bucket.entries
    if #entries > 0 then
      table.sort(entries, function(a, b)
        local result = metricCompare(a, b, spec.sortKey, spec.sortDirection)
        if result ~= nil then
          return result
        end

        if spec.tieBreakers then
          for _, rule in ipairs(spec.tieBreakers) do
            result = metricCompare(a, b, rule.key, rule.direction or spec.sortDirection)
            if result ~= nil then
              return result
            end
          end
        end

        local aGames = tonumber(a.metrics and a.metrics.games) or 0
        local bGames = tonumber(b.metrics and b.metrics.games) or 0
        if aGames ~= bGames then
          return aGames > bGames
        end

        return (a.name or '') < (b.name or '')
      end)
      local limit = spec.limit or TOP_ENTRIES
      if #entries > limit then
        for i = #entries, limit + 1, -1 do
          entries[i] = nil
        end
      end
      for idx, entry in ipairs(entries) do
        entry.rank = idx
      end
    end
    bucket.capturedAt = toIsoString(bucket.capturedAt)
  end

  return buckets, toIsoString(latest)
end

local function mapAwards(rows)
  local buckets = {}
  for _, key in ipairs(AWARD_ORDER) do
    local spec = AWARD_SPECS[key]
    if spec then
      buckets[key] = {
        key = key,
        label = spec.label,
        format = spec.format,
        decimals = spec.decimals,
        suffix = spec.suffix,
        description = spec.description,
        sortDirection = spec.sortDirection,
        entries = {},
        capturedAt = nil,
        minMatches = math.max(spec.minGames or 0, minMatchesForMode('global')),
        filteredCount = 0,
      }
    end
  end

  local latest = nil
  for _, row in ipairs(rows or {}) do
    local spec = AWARD_SPECS[row.award_key]
    local bucket = spec and buckets[row.award_key]
    if bucket then
      local extra = safeDecode(row.extra)
      local gamesPlayed = tonumber(extra and extra.games) or 0
      local requiredGames = bucket.minMatches or 0
      if gamesPlayed < requiredGames then
        bucket.filteredCount = (bucket.filteredCount or 0) + 1
      else
        local entry = {
          entityType = row.entity_type,
          entityId = row.entity_id,
          name = row.entity_name,
          value = tonumber(row.value) or row.value,
          extra = extra,
          capturedAt = row.captured_at,
        }
        bucket.entries[#bucket.entries+1] = entry
        if row.captured_at then
          if not bucket.capturedAt or row.captured_at > bucket.capturedAt then
            bucket.capturedAt = row.captured_at
          end
          if not latest or row.captured_at > latest then
            latest = row.captured_at
          end
        end
      end
    end
  end

  for key, bucket in pairs(buckets) do
    local spec = AWARD_SPECS[key]
    local entries = bucket.entries
    if #entries > 0 then
      table.sort(entries, function(a, b)
        local aVal = tonumber(a.value)
        local bVal = tonumber(b.value)
        if aVal == nil then
          aVal = spec.sortDirection == 'asc' and math.huge or -math.huge
        end
        if bVal == nil then
          bVal = spec.sortDirection == 'asc' and math.huge or -math.huge
        end
        if aVal == bVal then
          local aGames = tonumber(a.extra and a.extra.games) or 0
          local bGames = tonumber(b.extra and b.extra.games) or 0
          if aGames ~= bGames then
            return aGames > bGames
          end
          return (a.name or '') < (b.name or '')
        end
        if spec.sortDirection == 'asc' then
          return aVal < bVal
        end
        return aVal > bVal
      end)
      local limit = spec.limit or TOP_AWARDS
      if #entries > limit then
        for i = #entries, limit + 1, -1 do
          entries[i] = nil
        end
      end
      for idx, entry in ipairs(entries) do
        entry.rank = idx
      end
    end
    bucket.capturedAt = toIsoString(bucket.capturedAt)
  end

  return buckets, toIsoString(latest)
end

local function safeQuery(sql)
  local ok, rows = pcall(DB.query, sql, {})
  if not ok or type(rows) ~= 'table' then
    return {}
  end
  return rows
end

AddEventHandler('exec:leaderboard:invalidate', function()
  cache.data = nil
  cache.expiresAt = nil
end)

function Leaderboard.fetch()
  local now = os.time()
  if cache.data and cache.expiresAt and cache.expiresAt > now then
    return cache.data
  end

  local profileRows = safeQuery([[SELECT entity_type, entity_id, entity_name, mode, metrics, captured_at FROM exec_stat_profiles]])
  local awardRows = safeQuery([[SELECT award_key, entity_type, entity_id, entity_name, value, extra, captured_at FROM exec_stat_awards]])

  local perMode, perModeTs = mapPerMode(profileRows)
  local awards, awardsTs = mapAwards(awardRows)

  local generatedAt = perModeTs or awardsTs
  if perModeTs and awardsTs then
    generatedAt = perModeTs > awardsTs and perModeTs or awardsTs
  end

  local payload = {
    generatedAt = generatedAt,
    modeOrder = MODE_ORDER,
    awardOrder = AWARD_ORDER,
    perMode = perMode,
    awards = awards,
  }

  if CACHE_SECONDS > 0 then
    cache.data = payload
    cache.expiresAt = now + CACHE_SECONDS
  end

  return payload
end

lib.callback.register('exec:getGlobalLeaderboard', function(src)
  return Leaderboard.fetch()
end)

return Leaderboard
