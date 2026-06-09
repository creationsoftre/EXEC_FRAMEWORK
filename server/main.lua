local cfg = require "config.arenas"
local gp  = require "config.gameplay"
local gcfg = require "config.gangs"
local utils = require "shared.utils"
local DB = require "server.db"
local GangService = require "server.gangs"
local Stats = require "server.stats"
local WeaponUnlocks = require "server.weapon_unlocks"
local IdentityBridge = require "bridge.identity"
local KillfeedBridge = require "bridge.killfeed"
local NotifyBridge = require "bridge.notify"
local weaponCatalog = require "shared.weapon_catalog"
local weaponLocales = weaponCatalog.locales or {}

local weaponHashLookup = {}
local function registerWeaponName(name)
  if type(name) ~= "string" or name == "" then return end
  local hash = GetHashKey(name)
  if not hash or hash == 0 then return end
  weaponHashLookup[hash] = name
end
local function bootstrapWeaponLookup()
  local function ingest(categories)
    if not categories then return end
    for _, cat in pairs(categories) do
      if type(cat) == "table" and cat.weapons then
        for _, weaponName in ipairs(cat.weapons) do
          registerWeaponName(weaponName)
        end
      end
    end
  end
  ingest(weaponCatalog.base and weaponCatalog.base.categories)
  ingest(weaponCatalog.addon and weaponCatalog.addon.categories)
end
bootstrapWeaponLookup()

local locationTotals     = {}     -- [locKey] = int
local ffaPlayers         = {}     -- [locKey][modeKey] = { [src]=true }
local playerArena        = {}     -- [src] = { bucket, type='playground'|'session', mode, location, sessionId?, prefCategory?, prefWeapon? }
local ffaBuckets         = {}     -- [locKey][modeKey] = bucket
local sessions           = {}     -- [id] = {...}
local sessionSeq         = 1
local endWithCountdown
local respawnCfg         = (gp and gp.respawn) or {}
local respawnSpawnCfg    = (respawnCfg and respawnCfg.spawn) or {}
local combatDomeCfg      = (gp and gp.combatDome) or {}
local respawnReservations = {}
local lastRespawnByPlayer = {}


local function weaponNameFromHash(hash)
  if not hash then return nil end
  return weaponHashLookup[hash]
end

local function prettyWeaponLabel(name)
  if type(name) ~= "string" then return nil end
  local clean = name:gsub("^WEAPON_", ""):lower():gsub("_", " ")
  return clean:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end)
end

local function distanceSquared(a, b)
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  return dx * dx + dy * dy
end

local function vecFromTable(val)
  if type(val) ~= "table" then return nil end
  local x = tonumber(val.x); local y = tonumber(val.y); local z = tonumber(val.z)
  if not x or not y then return nil end
  return vector3(x, y, z or 0.0)
end

local function respawnVectorToTable(val)
  local vec = vecFromTable(val) or val
  if not vec then return nil end
  return { x = vec.x + 0.0, y = vec.y + 0.0, z = (vec.z or 0.0) + 0.0 }
end

local function respawnDistance(a, b)
  if not a or not b then return math.huge end
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  local dz = (a.z or 0.0) - (b.z or 0.0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function respawnHorizontalDistance(a, b)
  if not a or not b then return math.huge end
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  return math.sqrt(dx * dx + dy * dy)
end

local function respawnNowMs()
  return GetGameTimer()
end

local function respawnReservationMs()
  return math.max(1000, math.floor((tonumber(respawnSpawnCfg.reservationSeconds) or 8.0) * 1000))
end

local function respawnRepeatAvoidMs()
  return math.max(1000, math.floor((tonumber(respawnSpawnCfg.repeatAvoidSeconds) or 30.0) * 1000))
end

local function respawnVariantRadius()
  return math.max(0.0, tonumber(respawnSpawnCfg.singleSpawnVariantRadius) or 4.5)
end

local function respawnZoneKey(zone)
  if type(zone) ~= "table" then return "unknown" end
  local groupKey = tostring(zone.groupKey or "zone")
  local location = zone.location or zone.locKey
  if type(location) == "string" and location ~= "" then
    return ("%s:%s"):format(groupKey, location)
  end
  local center = vecFromTable(zone.center) or zone.center
  if center then
    return ("%s:%.2f:%.2f:%.2f:%.2f"):format(groupKey, center.x or 0.0, center.y or 0.0, center.z or 0.0, tonumber(zone.arenaRadius) or 0.0)
  end
  return groupKey .. ":fallback"
end

local function cleanupRespawnReservations(zoneKey)
  local now = respawnNowMs()
  if zoneKey then
    local zoneReservations = respawnReservations[zoneKey]
    if not zoneReservations then return end
    for slotKey, entry in pairs(zoneReservations) do
      if type(entry) ~= "table" or tonumber(entry.expiresAt) == nil or entry.expiresAt <= now then
        zoneReservations[slotKey] = nil
      end
    end
    if not next(zoneReservations) then
      respawnReservations[zoneKey] = nil
    end
    return
  end

  for key in pairs(respawnReservations) do
    cleanupRespawnReservations(key)
  end
end

local function clearRespawnReservationsForSource(src)
  for zoneKey, zoneReservations in pairs(respawnReservations) do
    for slotKey, entry in pairs(zoneReservations) do
      if entry and entry.src == src then
        zoneReservations[slotKey] = nil
      end
    end
    if not next(zoneReservations) then
      respawnReservations[zoneKey] = nil
    end
  end
end

local function respawnVariantOffsets()
  local radius = respawnVariantRadius()
  local diagonal = radius * 0.70710678
  return {
    vector3(0.0, 0.0, 0.0),
    vector3(radius, 0.0, 0.0),
    vector3(-radius, 0.0, 0.0),
    vector3(0.0, radius, 0.0),
    vector3(0.0, -radius, 0.0),
    vector3(diagonal, diagonal, 0.0),
    vector3(diagonal, -diagonal, 0.0),
    vector3(-diagonal, diagonal, 0.0),
    vector3(-diagonal, -diagonal, 0.0),
  }
end

local function respawnUsesOuterShell(zone)
  return combatDomeCfg.enabled ~= false
    and respawnSpawnCfg.respectDomeAsNoSpawn ~= false
    and type(zone) == "table"
    and vecFromTable(zone.center)
    and tonumber(zone.domeRadius) ~= nil
    and tonumber(zone.domeRadius) > 0
    and combatDomeCfg.respawnOutside ~= false
end

local function buildOuterShellCandidates(zone)
  local candidates = {}
  local center = vecFromTable(zone and zone.center)
  if not center then return candidates end

  local inner = (tonumber(zone.domeRadius) or 0.0) + (tonumber(respawnSpawnCfg.innerBuffer) or 5.0)
  local arenaRadius = tonumber(zone.arenaRadius) or (inner + 24.0)
  local outer = math.max(inner + 4.0, arenaRadius - (tonumber(respawnSpawnCfg.edgeBuffer) or 4.0))
  local radius = inner + ((outer - inner) * 0.45)
  if radius > outer then radius = outer end
  if radius < inner then radius = inner end

  local offsets = 12
  for i = 1, offsets do
    local angle = ((i - 1) / offsets) * (math.pi * 2.0)
    candidates[#candidates + 1] = {
      slotKey = ("shell:%d"):format(i),
      point = vector3(
        center.x + math.cos(angle) * radius,
        center.y + math.sin(angle) * radius,
        center.z + 0.0
      ),
    }
  end

  return candidates
end

local function buildRespawnCandidates(zone)
  local candidates = {}
  if type(zone) ~= "table" then return candidates end

  local bases = {}
  if type(zone.spawns) == "table" and #zone.spawns > 0 then
    for index = 1, #zone.spawns do
      local point = vecFromTable(zone.spawns[index]) or zone.spawns[index]
      if point then
        bases[#bases + 1] = point
      end
    end
  end

  local center = vecFromTable(zone.center) or zone.center
  if #bases == 0 and center then
    bases[1] = center
  end
  if #bases == 0 then
    return candidates
  end

  local useOuterShell = respawnUsesOuterShell(zone)
  local minimumShellDistance = useOuterShell and ((tonumber(zone.domeRadius) or 0.0) + (tonumber(respawnSpawnCfg.innerBuffer) or 5.0)) or nil
  local useVariants = (#bases <= 1)
  local offsets = useVariants and respawnVariantOffsets() or nil
  for baseIndex, base in ipairs(bases) do
    if useVariants and offsets then
      for variantIndex, offset in ipairs(offsets) do
        local candidate = {
          slotKey = ("%d:%d"):format(baseIndex, variantIndex),
          point = vector3(base.x + offset.x, base.y + offset.y, (base.z or 0.0) + offset.z),
        }
        if not minimumShellDistance or respawnHorizontalDistance(candidate.point, center) >= minimumShellDistance then
          candidates[#candidates + 1] = candidate
        end
      end
    else
      local candidate = {
        slotKey = tostring(baseIndex),
        point = vector3(base.x + 0.0, base.y + 0.0, (base.z or 0.0) + 0.0),
      }
      if not minimumShellDistance or respawnHorizontalDistance(candidate.point, center) >= minimumShellDistance then
        candidates[#candidates + 1] = candidate
      end
    end
  end

  if #candidates == 0 and useOuterShell then
    candidates = buildOuterShellCandidates(zone)
  end

  return candidates
end

local function resolveSessionCombatRadius(zone)
  if type(zone) ~= "table" or not zone.center then return nil end
  if combatDomeCfg.enabled ~= false and tonumber(zone.domeRadius) and tonumber(zone.domeRadius) > 0 then
    return tonumber(zone.domeRadius), tonumber(combatDomeCfg.entryBuffer) or 0.75
  end
  if zone.groupKey == 'city' then
    return zone.sessionRadius or zone.domeRadius or zone.arenaRadius or 60.0, zone.sessionBuffer or 0.75
  end
  return nil
end

local function shuffleArray(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
end

local function respawnNearestDistance(point, points)
  if type(points) ~= "table" or #points == 0 then
    return math.huge
  end
  local nearest = math.huge
  for i = 1, #points do
    local distance = respawnDistance(point, points[i])
    if distance < nearest then
      nearest = distance
    end
  end
  return nearest
end

local function collectRespawnOccupiedPoints(src, zone, zoneKey)
  local points = {}
  local bucket = GetPlayerRoutingBucket(src)
  local location = zone and (zone.location or zone.locKey) or nil

  for _, pidRaw in ipairs(GetPlayers()) do
    local pid = tonumber(pidRaw)
    if pid and pid ~= src then
      local sameBucket = (bucket ~= 0 and GetPlayerRoutingBucket(pid) == bucket)
      local arena = playerArena[pid]
      local sameLocation = location and arena and arena.location == location
      if sameBucket or sameLocation then
        local ped = GetPlayerPed(pid)
        if ped and ped ~= 0 then
          local coords = GetEntityCoords(ped)
          if coords then
            points[#points + 1] = coords
          end
        end
      end
    end
  end

  cleanupRespawnReservations(zoneKey)
  local reservations = respawnReservations[zoneKey]
  if reservations then
    local now = respawnNowMs()
    for _, entry in pairs(reservations) do
      if entry and entry.src ~= src and entry.point and entry.expiresAt and entry.expiresAt > now then
        points[#points + 1] = entry.point
      end
    end
  end

  return points
end

local function pickRespawnCandidate(src, zone)
  local zoneKey = respawnZoneKey(zone)
  local candidates = buildRespawnCandidates(zone)
  if #candidates == 0 then return nil end

  cleanupRespawnReservations(zoneKey)
  shuffleArray(candidates)

  local minDistance = tonumber(respawnSpawnCfg.minDistanceFromPlayers) or 18.0
  local occupied = collectRespawnOccupiedPoints(src, zone, zoneKey)
  local last = lastRespawnByPlayer[src]
  local now = respawnNowMs()
  local lastSlotKey = nil
  if last and last.zoneKey == zoneKey and tonumber(last.expiresAt) and last.expiresAt > now then
    lastSlotKey = last.slotKey
  end

  local zoneReservations = respawnReservations[zoneKey] or {}
  local buckets = {
    ideal = {},
    safe = {},
    repeatOnly = {},
    reserved = {},
  }

  for _, candidate in ipairs(candidates) do
    local reservation = zoneReservations[candidate.slotKey]
    local reservedByOther = reservation and reservation.src ~= src and reservation.expiresAt and reservation.expiresAt > now
    local repeated = (lastSlotKey ~= nil and candidate.slotKey == lastSlotKey)
    candidate.nearest = respawnNearestDistance(candidate.point, occupied)
    local farEnough = candidate.nearest == math.huge or candidate.nearest >= minDistance

    if not reservedByOther and not repeated and farEnough then
      buckets.ideal[#buckets.ideal + 1] = candidate
    elseif not reservedByOther and not repeated then
      buckets.safe[#buckets.safe + 1] = candidate
    elseif not reservedByOther then
      buckets.repeatOnly[#buckets.repeatOnly + 1] = candidate
    else
      buckets.reserved[#buckets.reserved + 1] = candidate
    end
  end

  local function chooseBest(list)
    if #list == 0 then return nil end
    local best = {}
    local bestNearest = -1.0
    for _, candidate in ipairs(list) do
      if candidate.nearest > bestNearest then
        bestNearest = candidate.nearest
        best = { candidate }
      elseif math.abs(candidate.nearest - bestNearest) < 0.01 then
        best[#best + 1] = candidate
      end
    end
    return best[math.random(#best)]
  end

  local chosen = chooseBest(buckets.ideal)
    or chooseBest(buckets.safe)
    or chooseBest(buckets.repeatOnly)
    or chooseBest(buckets.reserved)
  if not chosen then return nil end

  respawnReservations[zoneKey] = respawnReservations[zoneKey] or {}
  respawnReservations[zoneKey][chosen.slotKey] = {
    src = src,
    point = chosen.point,
    expiresAt = now + respawnReservationMs(),
  }
  lastRespawnByPlayer[src] = {
    zoneKey = zoneKey,
    slotKey = chosen.slotKey,
    point = chosen.point,
    expiresAt = now + respawnRepeatAvoidMs(),
  }

  return chosen.point
end

local function midpoint(a, b)
  if a and b then
    return vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, ((a.z or 0.0) + (b.z or 0.0)) * 0.5)
  end
  return a or b or nil
end

local function measureDistance(a, b)
  if not a or not b then return nil end
  local dx = (a.x or 0.0) - (b.x or 0.0)
  local dy = (a.y or 0.0) - (b.y or 0.0)
  local dz = (a.z or 0.0) - (b.z or 0.0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function sessionPlayerSet(s)
  local out = {}
  if not s or not s.players then return out end
  for pid in pairs(s.players) do
    out[pid] = true
  end
  return out
end

local function playgroundPlayerSet(location, mode)
  local out = {}
  if type(ffaPlayers) ~= "table" then return out end
  local byLocation = ffaPlayers[location]
  local roster = byLocation and byLocation[mode]
  if not roster then return out end
  for pid, active in pairs(roster) do
    if active then
      out[pid] = true
    end
  end
  return out
end

local function pushKillfeed(payload)
  KillfeedBridge.Push(payload)
end

local function emitKillfeedEvent(s, killer, victimSrc, details, zone, killerPos, victimPos, killerTeam, victimTeam)
  if not s then return end
  details = details or {}
  local killerName = GetPlayerName(killer) or ("[" .. killer .. "]")
  local victimName = GetPlayerName(victimSrc) or ("[" .. victimSrc .. "]")
  local origin = midpoint(killerPos, victimPos) or (zone and zone.center)
  local distance = tonumber(details.distance) or measureDistance(killerPos, victimPos)
  local weaponHash = tonumber(details.weaponHash) or 0
  local weaponName = weaponNameFromHash(weaponHash)
  local weaponLabel = details.weaponLabel
  if (not weaponLabel or weaponLabel == "" or weaponLabel == "NULL") and weaponName then
    weaponLabel = weaponLocales[weaponName] or prettyWeaponLabel(weaponName)
  end

  pushKillfeed({
    sessionId = s.id,
    bucket = s.bucket,
    location = s.location,
    bracket = s.bracket,
    mode = s.mode,
    killer = { id = killer, name = killerName, team = killerTeam },
    victim = { id = victimSrc, name = victimName, team = victimTeam },
    weapon = {
      hash = weaponHash,
      name = weaponName,
      label = weaponLabel,
      slug = details.weaponSlug,
    },
    distance = distance,
    headshot = details.headshot and true or false,
    origin = origin,
    coords = { killer = killerPos, victim = victimPos },
    zone = zone,
    players = sessionPlayerSet(s),
  })
end

local addonConfig = weaponCatalog.addon or {}
local ALL_CATEGORIES = {}
for key, cat in pairs(weaponCatalog.categories or {}) do
  ALL_CATEGORIES[key] = cat
end
for key, cat in pairs(addonConfig.categories or {}) do
  ALL_CATEGORIES[key] = cat
end
local CATEGORY_CHILDREN = {}
local CATEGORY_PARENTS = {}

do
  for key, cat in pairs(ALL_CATEGORIES) do
    local parent = cat.inherit or cat.parent
    if parent then
      CATEGORY_CHILDREN[parent] = CATEGORY_CHILDREN[parent] or {}
      CATEGORY_CHILDREN[parent][#CATEGORY_CHILDREN[parent]+1] = key
      CATEGORY_PARENTS[key] = parent
    end
  end
  for _, list in pairs(CATEGORY_CHILDREN) do
    table.sort(list)
  end
end
local function expandCategoryList(list)
  local seen, out = {}, {}
  local function addCategory(key)
    if not key or seen[key] or not ALL_CATEGORIES[key] then return end
    seen[key] = true
    out[#out+1] = key
    local parent = CATEGORY_PARENTS[key]
    if parent then
      addCategory(parent)
    end
    local children = CATEGORY_CHILDREN[key]
    if children then
      for _, child in ipairs(children) do
        addCategory(child)
      end
    end
  end
  if list and #list > 0 then
    for _, key in ipairs(list) do
      addCategory(key)
    end
  else
    for key,_ in pairs(ALL_CATEGORIES) do
      addCategory(key)
    end
  end
  table.sort(out)
  return out
end

local function resolveCategoryPreference(lockKey, desired)
  if not lockKey then return desired end
  local expanded = expandCategoryList({ lockKey })
  if desired then
    for _, key in ipairs(expanded) do
      if key == desired then
        return desired
      end
    end
  end
  return expanded[1]
end

-- Identifier helpers
local function findIdentifier(src, typ)
  for _, v in ipairs(GetPlayerIdentifiers(src)) do
    if v and v:sub(1, #typ + 1) == (typ .. ":") then return v end
  end
end
local function bestIdentifier(src)
  return findIdentifier(src, "license") or findIdentifier(src, "license2")
      or findIdentifier(src, "fivem")   or findIdentifier(src, "steam")
      or (GetPlayerToken and GetPlayerToken(src, 0) and ("token:" .. GetPlayerToken(src, 0)))
      or ("net:" .. tostring(src))
end

local function hasWeaponUnlockAdmin(src)
  if src == 0 then return true end
  local adminCfg = (gcfg and gcfg.admin) or {}
  if adminCfg.identifiers then
    local ids = GetPlayerIdentifiers(src)
    for _, id in ipairs(ids) do
      for _, allow in ipairs(adminCfg.identifiers) do
        if id == allow then
          return true
        end
      end
    end
  end
  if adminCfg.ace and adminCfg.ace ~= '' and IsPlayerAceAllowed(src, adminCfg.ace) then
    return true
  end
  if IsPlayerAceAllowed(src, "command.exec_weaponlock") then
    return true
  end
  return false
end

-- ===== State =====
local used               = utils.newSet()
local function nextBucket() local b=2000 while used:contains(b) do b=b+1 end used:add(b) return b end
local function freeBucket(b) if b then used:remove(b) end end


AddEventHandler('playerJoining', function()
  local src = source
  CreateThread(function()
    Wait(750)
    WeaponUnlocks.pushToSource(src)
  end)
end)

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    CreateThread(function()
      Wait(1000)
      WeaponUnlocks.pushToAll()
    end)
  end
end)

local function findLocation(locKey)
  if cfg.groups then
    for gKey, group in pairs(cfg.groups) do
      if group.locations and group.locations[locKey] then
        return gKey, group.locations[locKey]
      end
    end
  elseif cfg.city and cfg.city[locKey] then
    return 'city', cfg.city[locKey]
  end
  return nil, nil
end

local function sessionZonePayload(s)
  if not s or not s.location then return nil end
  local groupKey, loc = findLocation(s.location)
  if not loc or not loc.center then return nil end
  return {
    center = loc.center,
    domeRadius = loc.domeRadius,
    arenaRadius = loc.arenaRadius,
    spawns = loc.spawns,
    heading = loc.heading,
    groupKey = groupKey,
    sessionRadius = loc.sessionRadius,
    sessionBuffer = loc.sessionBuffer,
    location = s.location,
  }
end

local TEAM_CONFIG = {
  ['1v1'] = { teamSize = 1 },
  ['2v2'] = { teamSize = 2 },
  ['3v3'] = { teamSize = 3 },
  ['5v5'] = { teamSize = 5 },
  gangwar   = { teamSize = 10 },
}

local TEAM_ORDER = { 'alpha', 'bravo' }
local TEAM_LABELS = { alpha = 'Team A', bravo = 'Team B' }

local function firstTeamMemberId(team)
  if not team or not team.members then return nil end
  for pid,_ in pairs(team.members) do
    return pid
  end
  return nil
end

local function refreshTeamLabel(s, key)
  if not s or not s.teams then return end
  local team = s.teams[key]
  if not team then return end

  local defaultLabel = team.baseLabel or TEAM_LABELS[key] or key
  team.gangId = nil
  team.gangName = nil

  if s.bracket == '1v1' then
    local memberId = firstTeamMemberId(team)
    if memberId then
      team.label = GetPlayerName(memberId) or ('[' .. memberId .. ']')
    else
      team.label = defaultLabel
    end
  elseif s.bracket == 'gangwar' then
    local memberId = firstTeamMemberId(team)
    if memberId and GangService and GangService.getGangForSource then
      local gang = GangService.getGangForSource(memberId)
      if gang then
        team.label = gang.name or defaultLabel
        team.gangId = gang.id
        team.gangName = gang.name
      else
        team.label = defaultLabel
      end
    else
      team.label = defaultLabel
    end
  else
    team.label = team.label or defaultLabel
  end
end

local function refreshAllTeamLabels(s)
  if not s or not s.teams then return end
  for _, key in ipairs(TEAM_ORDER) do
    if s.teams[key] then
      refreshTeamLabel(s, key)
    end
  end
end

local function isTeamBracket(bracket)
  return TEAM_CONFIG[bracket] ~= nil
end

local function teamSizeFor(bracket)
  local cfg = TEAM_CONFIG[bracket]
  return cfg and cfg.teamSize or 0
end

local function countTeamMembers(team)
  local count = 0
  if not team or not team.members then return 0 end
  for _ in pairs(team.members) do count = count + 1 end
  return count
end

local function sessionTeamCounts(s)
  local counts = {}
  if not s or not s.teams then return counts end
  for _, key in ipairs(TEAM_ORDER) do
    local team = s.teams[key]
    counts[key] = countTeamMembers(team)
  end
  return counts
end

local function findTeamWithSpace(s)
  if not s or not s.teams then return nil end
  local bestKey, bestCount = nil, nil
  local maxSize = s.teamSize or 0
  for _, key in ipairs(TEAM_ORDER) do
    local team = s.teams[key]
    local count = countTeamMembers(team)
    if (not bestKey) or count < bestCount then
      if maxSize == 0 or count < maxSize then
        bestKey, bestCount = key, count
      end
    end
  end
  return bestKey
end

local function teamHasSpace(s, teamKey)
  if not s or not s.teams or not teamKey then return false end
  local team = s.teams[teamKey]
  if not team then return false end
  local maxSize = s.teamSize or 0
  if maxSize == 0 then return true end
  return countTeamMembers(team) < maxSize
end

local function isSessionBalanced(s)
  if not s or not s.teams then return true end
  local counts = sessionTeamCounts(s)
  local target = nil
  for _, key in ipairs(TEAM_ORDER) do
    local count = counts[key] or 0
    if not target then
      target = count
    else
      if count ~= target then return false end
    end
  end
  return target and target > 0 or false
end

local sessionRules
local bracketRule
local bracketCap
local bracketMin
local sessionCountdownSeconds
local sessionPlayerCount
local broadcastSession
local broadcastLobby
local buildScoreEntries
local pushScoreboard
local cancelCountdown
local startCountdown
local ensureSessionState

local function _ensureFFA(locKey, modeKey)
  ffaPlayers[locKey] = ffaPlayers[locKey] or {}
  ffaPlayers[locKey][modeKey] = ffaPlayers[locKey][modeKey] or {}
end
local function _incLocation(locKey) locationTotals[locKey] = (locationTotals[locKey] or 0) + 1 end
local function _decLocation(locKey)
  if locationTotals[locKey] then locationTotals[locKey] = math.max(0, locationTotals[locKey]-1) end
end

local function removeSessionMember(s, pid)
  if not s or not s.players or not s.players[pid] then return nil end
  local info = s.players[pid]
  local teamKey = info and info.team or nil
  s.players[pid] = nil

  if teamKey and s.teams and s.teams[teamKey] then
    local team = s.teams[teamKey]
    team.members[pid] = nil
    if team.leader == pid then
      team.leader = nil
      for memberId,_ in pairs(team.members) do
        team.leader = memberId
        break
      end
    end
    refreshTeamLabel(s, teamKey)
  end

  return teamKey
end

local function destroyEmptySession(s)
  if not s or next(s.players or {}) then return false end
  if not s.ended then
    if cancelCountdown then cancelCountdown(s) end
    if s.bucket then freeBucket(s.bucket) end
    sessions[s.id] = nil
  end
  return true
end

local function debugSession(message)
  if not (gp.debug and gp.debug.session) and GetConvarInt('exec_debug_session', 0) ~= 1 then return end
  print(('[exec_framework:session] %s'):format(message))
end

local function buildLiveCountsSummary()
  local totals = {}
  local ffaByLocation = {}
  local online = {}
  for _, playerId in ipairs(GetPlayers()) do
    online[tonumber(playerId)] = true
  end

  for pid, arena in pairs(playerArena) do
    local bucket = online[pid] and GetPlayerRoutingBucket(pid) or 0
    local stale = (not online[pid]) or bucket == 0 or (arena and arena.bucket and bucket ~= arena.bucket)

    if stale then
      debugSession(('pruning stale arena state for %s'):format(pid))
      if arena and arena.type == "session" and arena.sessionId then
        local s = sessions[arena.sessionId]
        if s and s.players and s.players[pid] then
          removeSessionMember(s, pid)
          destroyEmptySession(s)
        end
      end
      playerArena[pid] = nil
      if arena and arena.type == "playground" and ffaPlayers[arena.location] and ffaPlayers[arena.location][arena.mode] then
        ffaPlayers[arena.location][arena.mode][pid] = nil
      end
    elseif arena and arena.location then
      totals[arena.location] = (totals[arena.location] or 0) + 1

      if arena.type == "playground" and arena.mode then
        ffaByLocation[arena.location] = ffaByLocation[arena.location] or {}
        ffaByLocation[arena.location][arena.mode] = (ffaByLocation[arena.location][arena.mode] or 0) + 1
      end
    end
  end

  locationTotals = totals

  return {
    totals = totals,
    ffa = ffaByLocation,
  }
end

local function resetAllState()
  used               = utils.newSet()
  locationTotals     = {}
  ffaPlayers         = {}
  playerArena        = {}
  ffaBuckets         = {}
  sessions           = {}
  sessionSeq         = 1
  respawnReservations = {}
  lastRespawnByPlayer = {}
end

CreateThread(function()
  while true do
    local interval = (((gp or {}).session or {}).cleanupIntervalSeconds or 15) * 1000
    Wait(math.max(5000, math.floor(interval)))
    buildLiveCountsSummary()
  end
end)

-- DB migrations + clean reset on resource start
AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  DB.runMigrations()
  GangService.init()
  local ok, err = pcall(Stats.rebuild)
  if not ok then
    print(("[exec_framework] Failed to rebuild leaderboard cache: %s"):format(err))
  end
  resetAllState()
  -- push all current players to hub & clear their buckets
  for _, sid in ipairs(GetPlayers()) do
    sid = tonumber(sid)
    if sid then
      SetPlayerRoutingBucket(sid, 0)
      TriggerClientEvent("exec:returnToHub", sid, cfg.hub)
    end
  end
end)

-- Best-effort cleanup if stopping
AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, sid in ipairs(GetPlayers()) do
    sid = tonumber(sid)
    if sid then SetPlayerRoutingBucket(sid, 0) end
  end
end)

-- Allowed categories for a context (Sandbox = all)
local function allowedCategoriesFor(src, a)
  if not a or a.mode == "sandbox" then
    return expandCategoryList(nil)
  end

  local locTbl
  if cfg.groups then
    for _, group in pairs(cfg.groups) do
      if group.locations and group.locations[a.location] then locTbl = group.locations[a.location] break end
    end
  else
    locTbl = cfg.city and cfg.city[a.location]
  end
  if not locTbl then return expandCategoryList(nil) end

  local cats = nil
  if a.type == "playground" then
    cats = locTbl.restrictions and locTbl.restrictions.playground and locTbl.restrictions.playground.categories
  else
    local pubpriv = "public"
    if a.sessionId then
      local s = sessions[a.sessionId]
      if s and s.private then pubpriv = "private" end
    end
    cats = locTbl.restrictions and locTbl.restrictions.session and locTbl.restrictions.session[pubpriv] and locTbl.restrictions.session[pubpriv].categories
  end
  return expandCategoryList(cats)
end

local function effectiveCategoryFor(src, a)
  local m = a.mode and cfg.modes[a.mode]
  if m and m.categoryLock then
    return resolveCategoryPreference(m.categoryLock, a.prefCategory)
  end
  local allowed = allowedCategoriesFor(src, a)
  local pref = a.prefCategory
  if pref then
    for _, k in ipairs(allowed) do if k == pref then return pref end end
  end
  return allowed[1]
end

local function noOpponentsResult()
  return { label = 'No Opponents', noContest = true }
end

local function resolveForfeitResult(s, leavingPid, leavingTeam)
  if not s or not s.active then return noOpponentsResult() end

  if s.teams and leavingTeam then
    local leavingScore = (s.teamKills and s.teamKills[leavingTeam]) or 0
    local leaderKey = nil
    local leaderScore = leavingScore

    for key, team in pairs(s.teams) do
      if key ~= leavingTeam then
        local memberCount = 0
        for _ in pairs(team.members or {}) do
          memberCount = memberCount + 1
        end
        if memberCount > 0 then
          local score = (s.teamKills and s.teamKills[key]) or 0
          if score > leaderScore then
            leaderScore = score
            leaderKey = key
          elseif score == leaderScore then
            leaderKey = nil
          end
        end
      end
    end

    if leaderKey then
      local label = (s.teams[leaderKey] and s.teams[leaderKey].label) or leaderKey
      return { label = label, teamKey = leaderKey }
    end

    return noOpponentsResult()
  end

  local leavingScore = (leavingPid and s.kills and s.kills[leavingPid]) or 0
  local leaderPid = nil
  local leaderScore = leavingScore
  for pid,_ in pairs(s.players or {}) do
    if pid ~= leavingPid then
      local score = (s.kills and s.kills[pid]) or 0
      if score > leaderScore then
        leaderScore = score
        leaderPid = pid
      elseif score == leaderScore then
        leaderPid = nil
      end
    end
  end

  if leaderPid then
    local label = GetPlayerName(leaderPid) or ('[' .. leaderPid .. ']')
    return { label = label, playerId = leaderPid }
  end

  return noOpponentsResult()
end

-- Remove player from current arena (updates counts too)
local function removeFromCurrent(src)
  local a = playerArena[src]; if not a then return end
  if a.type == "playground" then
    if ffaPlayers[a.location] and ffaPlayers[a.location][a.mode] then
      ffaPlayers[a.location][a.mode][src] = nil
    end
    _decLocation(a.location)
  elseif a.type == "session" then
    local s = sessions[a.sessionId]
    if s and s.players[src] then
      local wasActive = s.active
      local teamKey = removeSessionMember(s, src)
      _decLocation(a.location)
      if not destroyEmptySession(s) then
        if not s.ended then
          if wasActive then
            if s.teams then
              local emptyTeam = nil
              for key, team in pairs(s.teams) do
                local memberCount = 0
                for pid,_ in pairs(team.members) do
                  memberCount = memberCount + 1
                end
                if memberCount == 0 then
                  emptyTeam = key
                end
              end
              if emptyTeam then
                local result = resolveForfeitResult(s, src, teamKey)
                playerArena[src] = nil
                CreateThread(function()
                  endWithCountdown(s, result)
                end)
                return
              end
            elseif s.bracket == '1v1' then
              local remaining = {}
              for pid,_ in pairs(s.players) do
                remaining[#remaining+1] = pid
              end
              if #remaining < 2 then
                local result = resolveForfeitResult(s, src)
                playerArena[src] = nil
                CreateThread(function()
                  endWithCountdown(s, result)
                end)
                return
              end
            end
          end
          pushScoreboard(s)
          ensureSessionState(s)
        end
      end
    end
  end
  playerArena[src] = nil
end

-- Buckets
local function ensureFfaBucket(locKey, modeKey)
  ffaBuckets[locKey] = ffaBuckets[locKey] or {}
  if not ffaBuckets[locKey][modeKey] then
    ffaBuckets[locKey][modeKey] = nextBucket()
  end
  return ffaBuckets[locKey][modeKey]
end

-- Ready from multichar
RegisterNetEvent("exec:ready", function(charData)
  local src = source
  IdentityBridge.ReleaseSelectorBucket(src, 0)
  TriggerClientEvent("exec:spawnAtHub", src, cfg.hub)
end)

RegisterNetEvent("exec_multichar:clearActiveCharacter", function()
  local src = source
  local hadArena = playerArena[src] ~= nil
  removeFromCurrent(src)
  if hadArena then
    TriggerClientEvent("exec:character:reset", src)
  end
end)

lib.callback.register("exec:logoutForMultichar", function(src)
  removeFromCurrent(src)
  clearRespawnReservationsForSource(src)
  lastRespawnByPlayer[src] = nil
  SetPlayerRoutingBucket(src, 0)
  TriggerClientEvent("exec:character:reset", src)
  TriggerClientEvent("exec_killfeed:clear", src)
  return { ok = true }
end)

-- Player preference (category/weapon) with UNIFORM locks + weaponLock
RegisterNetEvent("exec:setPreferredCategory", function(category, weapon)
  local src = source
  playerArena[src] = playerArena[src] or {}
  local a = playerArena[src]

  -- store preference (used for respawns)
  a.prefCategory = category
  a.prefWeapon   = weapon

  -- If we don't have mode/location yet, just store
  if not a.mode then return end

  if a.mode == "gun_game" then
    -- hard lock: ignore changes (client menu is disabled)
    return
  end

  local m = cfg.modes[a.mode]
  if m and m.weaponLock then
    -- hard lock to a specific gun
    a.prefCategory = resolveCategoryPreference(m.categoryLock, a.prefCategory or category)
    a.prefWeapon   = m.weaponLock
    TriggerClientEvent("exec:applyLoadout", src, a.mode, a.type=="session", a.prefCategory, a.prefWeapon)
    return
  end

  if m and m.categoryLock then
    -- Any category-locked mode: clamp to the locked family (allows add-on subcategories)
    local lockedCategory = resolveCategoryPreference(m.categoryLock, category)
    a.prefCategory = lockedCategory
    TriggerClientEvent("exec:applyLoadout", src, a.mode, a.type=="session", lockedCategory, weapon)
    return
  end

  -- Unlocked mode (incl. Sandbox): clamp to allowed set by location/privacy
  local allowed = allowedCategoriesFor(src, a)
  local valid=false; for _, k in ipairs(allowed) do if k == category then valid=true break end end
  if not valid then
    a.prefCategory = allowed[1]
  end
  TriggerClientEvent("exec:applyLoadout", src, a.mode, a.type=="session", a.prefCategory, weapon)
end)

-- ===== Playground (FFA) =====
lib.callback.register("exec:joinPlayground", function(src, payload)
  -- remove from prior arena first (fixes counts when switching)
  removeFromCurrent(src)

  -- resolve location & mode
  local loc = nil
  for _, g in pairs(cfg.groups) do
    if g.locations and g.locations[payload.location] then loc = g.locations[payload.location] break end
  end
  if not loc then return { ok=false, error="Invalid location" } end
  local mode = cfg.modes[payload.mode]
  if not mode then return { ok=false, error="Invalid mode" } end

  local b = ensureFfaBucket(payload.location, payload.mode)
  SetPlayerRoutingBucket(src, b)

  playerArena[src] = {
    bucket=b, type="playground", mode=payload.mode, location=payload.location,
    prefCategory=playerArena[src] and playerArena[src].prefCategory,
    prefWeapon=playerArena[src] and playerArena[src].prefWeapon
  }

  _ensureFFA(payload.location, payload.mode)
  ffaPlayers[payload.location][payload.mode][src] = true
  _incLocation(payload.location)

  local cat = effectiveCategoryFor(src, playerArena[src])
  local lockedWeapon = mode and mode.weaponLock or nil
  local zonePayload = sessionZonePayload({ location = payload.location })
  TriggerClientEvent("exec:joinMatch", src, { bucket=b, mode=payload.mode, location=payload.location, bracket="ffa", scoring=false, category=cat, weapon=lockedWeapon, zone=zonePayload })
  TriggerClientEvent("exec:zonePopulation", src, payload.location, locationTotals[payload.location] or 0)
  return { ok=true, bucket=b }
end)

-- ===== Sessions =====
sessionRules = (gp.session and gp.session.brackets) or {}

function bracketRule(bracket)
  return sessionRules and sessionRules[bracket] or nil
end

function bracketCap(bracket)
  local rule = bracketRule(bracket)
  if rule and rule.max then return rule.max end
  if bracket == '1v1' then return 2 end
  if bracket == '2v2' then return 4 end
  if bracket == '3v3' then return 6 end
  if bracket == 'gangwar' then return 20 end
  if bracket == '5v5' then return 20 end
  return 24
end

function bracketMin(bracket)
  local rule = bracketRule(bracket)
  if rule and rule.min then return rule.min end
  if bracket == '1v1' then return 2 end
  if bracket == '2v2' then return 4 end
  if bracket == '3v3' then return 6 end
  if bracket == 'gangwar' then return 10 end
  if bracket == '5v5' then return 10 end
  local cap = bracketCap(bracket)
  return math.max(2, math.floor(cap / 2))
end

function sessionCountdownSeconds()
  return (gp.session and gp.session.countdownSeconds) or gp.sessionCountdownSeconds or 60
end

local function preMatchCountdownSeconds()
  return (gp.session and gp.session.preMatchCountdownSeconds) or gp.preMatchCountdownSeconds or 3
end

function sessionPlayerCount(s)
  local count = 0
  for _ in pairs(s.players) do count = count + 1 end
  return count
end

function broadcastSession(s, eventName, ...)
  for pid,_ in pairs(s.players) do
    TriggerClientEvent(eventName, pid, s.id, ...)
  end
end

local function buildTeamSnapshot(s)
  if not s or not s.teams then return nil end
  local snapshot = {}
  local maxSize = s.teamSize or teamSizeFor(s.bracket)
  for _, key in ipairs(TEAM_ORDER) do
    local team = s.teams[key]
    if team then
      refreshTeamLabel(s, key)
      local members = {}
      local memberCount = 0
      for pid,_ in pairs(team.members) do
        memberCount = memberCount + 1
        members[#members+1] = {
          id = pid,
          name = GetPlayerName(pid) or ("["..pid.."]"),
          kills = s.kills[pid] or 0,
          leader = team.leader == pid,
          host = (s.owner == pid)
        }
      end
      table.sort(members, function(a,b)
        if a.kills == b.kills then
          return a.name < b.name
        end
        return a.kills > b.kills
      end)
      local maxSlots = (maxSize and maxSize > 0) and maxSize or nil
      snapshot[#snapshot+1] = {
        key = key,
        label = team.label or TEAM_LABELS[key] or key,
        baseLabel = team.baseLabel or TEAM_LABELS[key] or key,
        gangId = team.gangId,
        gangName = team.gangName,
        kills = s.teamKills and (s.teamKills[key] or 0) or 0,
        members = members,
        count = memberCount,
        max = maxSlots,
        leader = team.leader
      }
    end
  end
  return snapshot
end

local function buildLobbyPayload(s)
  if not s then return nil end
  return {
    sessionId = s.id,
    players   = sessionPlayerCount(s),
    min       = bracketMin(s.bracket),
    max       = bracketCap(s.bracket),
    countdown = s.countdown,
    active    = s.active or false,
    bracket   = s.bracket,
    mode      = s.mode,
    firstTo   = s.firstTo,
    host      = s.owner,
    private   = s.private,
    hardcore  = s.hardcore or false,
    teams     = buildTeamSnapshot(s),
    teamKills = s.teamKills,
    teamSize  = s.teamSize or teamSizeFor(s.bracket),
    balanced  = isSessionBalanced(s),
  }
end

function broadcastLobby(s)
  local payload = buildLobbyPayload(s)
  if not payload then return end
  for pid,_ in pairs(s.players) do
    TriggerClientEvent('exec:sessionLobbyUpdate', pid, payload)
  end
end
lib.callback.register("exec:getSessionLobby", function(src, sessionId)
  local s = sessions[sessionId]
  if not s or not s.players[src] then return nil end
  return buildLobbyPayload(s)
end)
function buildScoreEntries(s)
  local entries = {}
  for pid, info in pairs(s.players) do
    local name = GetPlayerName(pid) or ('['..pid..']')
    entries[#entries+1] = { id = pid, name = name, kills = s.kills[pid] or 0, team = info and info.team }
  end
  table.sort(entries, function(a,b)
    if a.kills == b.kills then
      return a.name < b.name
    end
    return a.kills > b.kills
  end)
  return entries
end


function pushScoreboard(s)
  local entries = buildScoreEntries(s)
  local teams = buildTeamSnapshot(s)
  for pid,_ in pairs(s.players) do
    TriggerClientEvent('exec:scoreboardUpdate', pid, s.id, entries, s.firstTo, teams)
  end
end

function cancelCountdown(s)
  local players = sessionPlayerCount(s)
  local minPlayers = bracketMin(s.bracket)
  if not s.countdown and not s.prestarting then return end
  s.countdown = nil
  s.prestarting = nil
  broadcastSession(s, 'exec:countdownCancelled', players, minPlayers)
  broadcastLobby(s)
end

local function beginSessionMatch(s)
  if not s or s.ended then return end
  s.countdown = nil
  s.prestarting = nil
  s.active = true
  s.started = os.time()
  s.kills = s.kills or {}
  s.matchStats = {
    players = {},
    started = s.started
  }
  for pid,_ in pairs(s.players) do
    s.kills[pid] = 0
    s.matchStats.players[pid] = { kills = 0, deaths = 0 }
  end
  if s.teams then
    s.teamKills = s.teamKills or { alpha = 0, bravo = 0 }
    s.teamKills.alpha = 0
    s.teamKills.bravo = 0
  end
  broadcastLobby(s)
  broadcastSession(s, 'exec:matchBegan')
  pushScoreboard(s)
  broadcastSession(s, 'exec:matchGo', 2000)
end

local function beginSessionPreStart(s)
  if not s or s.ended then return end
  if sessionPlayerCount(s) < bracketMin(s.bracket) then
    cancelCountdown(s)
    return
  end

  s.countdown = nil
  s.prestarting = true

  local zone = sessionZonePayload(s)
  if zone then
    for pid,_ in pairs(s.players) do
      TriggerClientEvent('exec:sessionPreStart', pid, s.id, zone)
    end
  end
  Wait(1000)

  local seconds = math.max(1, math.floor(tonumber(preMatchCountdownSeconds()) or 3))
  for remaining = seconds, 1, -1 do
    if not s or s.ended then return end
    if sessionPlayerCount(s) < bracketMin(s.bracket) then
      cancelCountdown(s)
      return
    end
    broadcastSession(s, 'exec:preMatchCountdown', remaining)
    Wait(1000)
  end

  beginSessionMatch(s)
end

function startCountdown(s)
  s.countdown = sessionCountdownSeconds()
  s.active = false
  s.prestarting = nil
  broadcastLobby(s)
  broadcastSession(s, 'exec:countdown', s.countdown, sessionPlayerCount(s), bracketMin(s.bracket), bracketCap(s.bracket))
  CreateThread(function()
    while s and s.countdown and s.countdown > 0 do
      Wait(1000)
      if not s or s.ended then return end
      if sessionPlayerCount(s) < bracketMin(s.bracket) then
        cancelCountdown(s)
        return
      end
      s.countdown = s.countdown - 1
      broadcastSession(s, 'exec:countdown', s.countdown, sessionPlayerCount(s), bracketMin(s.bracket), bracketCap(s.bracket))
    end
    if not s or s.ended then return end
    if not s.countdown then return end
    beginSessionPreStart(s)
  end)
end

function ensureSessionState(s)
  if not s or s.ended then return end
  local count = sessionPlayerCount(s)
  local minPlayers = bracketMin(s.bracket)
  if s.prestarting then
    if count < minPlayers or (s.teams and not isSessionBalanced(s)) then
      cancelCountdown(s)
    else
      broadcastLobby(s)
    end
    return
  end
  if s.teams then
    if s.active then
      broadcastLobby(s)
      return
    end

    local balanced = isSessionBalanced(s)
    if count >= minPlayers and balanced then
      if not s.countdown then
        startCountdown(s)
      end
    else
      if s.countdown then
        cancelCountdown(s)
      end
    end
    broadcastLobby(s)
    return
  end
  if s.active then
    broadcastLobby(s)
    return
  end
  if count >= minPlayers then
    if not s.countdown then
      startCountdown(s)
    else
      broadcastLobby(s)
    end
  else
    cancelCountdown(s)
    broadcastLobby(s)
  end
end

lib.callback.register("exec:createSession", function(src, payload)
  local prevCategory = playerArena[src] and playerArena[src].prefCategory or nil
  local prevWeapon = playerArena[src] and playerArena[src].prefWeapon or nil
  -- remove from prior arena first (fixes counts when switching)
  removeFromCurrent(src)

  local groupKey, loc = findLocation(payload.location)
  if not loc then return { ok=false, error="Invalid location" } end
  local mode = cfg.modes[payload.mode]
  if not mode then return { ok=false, error="Invalid mode" } end
  if payload.bracket == "ffa" then return { ok=false, error="Use Playground for FFA" } end

  local id = sessionSeq; sessionSeq = sessionSeq + 1
  local b = nextBucket()
  local isTeam = isTeamBracket(payload.bracket)
  local teamSize = isTeam and teamSizeFor(payload.bracket) or nil
  local firstTo = math.floor(tonumber(payload.firstTo) or tonumber(mode.firstTo) or 30)
  firstTo = math.max(1, math.min(firstTo, 100))
  local teams = nil
  local teamKills = nil
  if isTeam then
    teams = {}
    for _, key in ipairs(TEAM_ORDER) do
      local base = TEAM_LABELS[key] or key
      teams[key] = { key = key, label = base, baseLabel = base, members = {}, leader = nil }
    end
    teamKills = { alpha = 0, bravo = 0 }
  end

  sessions[id] = {
    id=id, owner=src, private=payload.private and true or false,
    invites={}, players={}, location=payload.location, mode=payload.mode,
    bracket=payload.bracket, bucket=b, firstTo=firstTo,
    kills={}, started=os.time(), active=false, countdown=nil,
    teams=teams, teamKills=teamKills, teamSize=teamSize, hardcore=false, overrideStart=false, groupKey=groupKey
  }
  local zonePayload = sessionZonePayload(sessions[id])
  SetPlayerRoutingBucket(src, b)

  local assignedTeam = nil
  if isTeam then
    assignedTeam = TEAM_ORDER[1]
    local team = sessions[id].teams[assignedTeam]
    team.members[src] = true
    team.leader = team.leader or src
    refreshAllTeamLabels(sessions[id])
  end

  sessions[id].players[src] = { team = assignedTeam }
  playerArena[src] = {
    bucket=b, type="session", mode=payload.mode, location=payload.location, sessionId=id, team=assignedTeam,
    prefCategory=prevCategory,
    prefWeapon=prevWeapon
  }

  _incLocation(payload.location)

  local cat = effectiveCategoryFor(src, playerArena[src])
  local lockedWeapon = mode and mode.weaponLock or nil
  TriggerClientEvent("exec:joinMatch", src, {
    bucket=b, mode=payload.mode, location=payload.location, bracket=payload.bracket,
    scoring=true, sessionId=id, private=sessions[id].private, category=cat, weapon=lockedWeapon, team=assignedTeam,
    firstTo=sessions[id].firstTo, zone=zonePayload
  })

  pushScoreboard(sessions[id])
  broadcastLobby(sessions[id])
  TriggerClientEvent("exec:zonePopulation", src, payload.location, locationTotals[payload.location] or 0)
  return { ok=true, sessionId=id }
end)

lib.callback.register("exec:listSessions", function(src, payload)
  buildLiveCountsSummary()
  local out = {}
  for id, s in pairs(sessions) do
    if s.location == payload.location and s.bracket == payload.bracket then
      local count = 0; for _ in pairs(s.players) do count = count + 1 end
      out[#out+1] = {
        id = id, owner = GetPlayerName(s.owner) or ("["..s.owner.."]"),
        mode = s.mode, private = s.private, players = count, cap = bracketCap(s.bracket), min = bracketMin(s.bracket)
      }
    end
  end
  table.sort(out, function(a,b) return a.id < b.id end)
  return out
end)

lib.callback.register("exec:joinSession", function(src, id)
  local prevCategory = playerArena[src] and playerArena[src].prefCategory or nil
  local prevWeapon = playerArena[src] and playerArena[src].prefWeapon or nil
  -- remove from prior arena first (fixes counts when switching)
  removeFromCurrent(src)

  local s = sessions[id]; if not s then return { ok=false, error="Session not found" } end
  local lic = bestIdentifier(src)
  local invite = lic and s.invites[lic] or nil
  local inviteTeam = nil
  if s.private and src ~= s.owner and not invite then
    return { ok=false, error="Invite only" }
  end
  if invite and type(invite) == 'table' then
    inviteTeam = invite.team
  end

  if s.active or s.prestarting then
    return { ok=false, error="Match already started" }
  end

  local count=0; for _ in pairs(s.players) do count = count + 1 end
  local cap = bracketCap(s.bracket)
  if count >= cap then return { ok=false, error="Session full" } end

  local assignedTeam = nil
  if s.teams then
    if inviteTeam and teamHasSpace(s, inviteTeam) then
      assignedTeam = inviteTeam
    else
      assignedTeam = findTeamWithSpace(s)
    end
    if not assignedTeam then return { ok=false, error="Teams are full" } end
  end

  SetPlayerRoutingBucket(src, s.bucket)
  s.players[src] = { team = assignedTeam }
  if lic then s.invites[lic] = nil end
  if assignedTeam then
    local team = s.teams[assignedTeam]
    team.members[src] = true
    if not team.leader then team.leader = src end
    refreshTeamLabel(s, assignedTeam)
  end

  playerArena[src] = {
    bucket=s.bucket, type="session", mode=s.mode, location=s.location, sessionId=s.id, team=assignedTeam,
    prefCategory=prevCategory, prefWeapon=prevWeapon
  }

  _incLocation(s.location)

  local cat = effectiveCategoryFor(src, playerArena[src])
  local mode = cfg.modes[s.mode]
  local lockedWeapon = mode and mode.weaponLock or nil
  local zonePayload = sessionZonePayload(s)
  TriggerClientEvent("exec:joinMatch", src, {
    bucket=s.bucket, mode=s.mode, location=s.location, bracket=s.bracket,
    scoring=true, sessionId=s.id, private=s.private, category=cat, weapon=lockedWeapon, team=assignedTeam,
    firstTo=s.firstTo, zone=zonePayload
  })

  pushScoreboard(s)
  ensureSessionState(s)
  if s.countdown then
    TriggerClientEvent("exec:countdown", src, s.id, s.countdown, sessionPlayerCount(s), bracketMin(s.bracket), bracketCap(s.bracket))
  elseif s.active then
    TriggerClientEvent("exec:matchBegan", src, s.id)
    local zone = sessionZonePayload(s)
    if zone then
      TriggerClientEvent("exec:sessionTeleport", src, zone)
    end
  end
  TriggerClientEvent("exec:zonePopulation", src, s.location, locationTotals[s.location] or 0)
  return { ok=true }
end)

lib.callback.register("exec:searchInvitees", function(src, payload)
  payload = payload or {}
  local sessionId = payload.sessionId
  local query = payload.query and tostring(payload.query) or ''
  local s = sessions[sessionId]
  if not s or not s.players[src] then return {} end

  local inviterInfo = s.players[src]
  local teamKey = inviterInfo and inviterInfo.team or nil
  local allowed = src == s.owner
  if s.teams and not allowed then
    if teamKey and s.teams[teamKey] and s.teams[teamKey].leader == src then
      allowed = true
    end
  end
  if not allowed then return {} end

  local results = {}
  local lowerQuery = query:lower()
  local maxResults = 20
  for _, pidStr in ipairs(GetPlayers()) do
    local pid = tonumber(pidStr)
    if pid and pid ~= src then
      if not s.players[pid] then
        local arena = playerArena[pid]
        if not arena or arena.type ~= 'session' then
          local name = GetPlayerName(pid)
          local matches = false
          if lowerQuery == '' then
            matches = true
          else
            if name and name:lower():find(lowerQuery, 1, true) then
              matches = true
            elseif pidStr:find(lowerQuery, 1, true) then
              matches = true
            end
          end
          if matches then
            local lic = bestIdentifier(pid)
            local alreadyInvited = lic and s.invites[lic] ~= nil
            results[#results+1] = {
              id = pid,
              name = name or ('['..pid..']'),
              invited = alreadyInvited
            }
            if #results >= maxResults then break end
          end
        end
      end
    end
  end

  table.sort(results, function(a,b)
    return a.name:lower() < b.name:lower()
  end)

  return results
end)

RegisterNetEvent("exec:inviteToSession", function(sessionId, targetSrc)
  local src = source
  local s = sessions[sessionId]; if not s then return end
  if not s.players[src] then return end
  targetSrc = tonumber(targetSrc); if not targetSrc then return end
  if s.players[targetSrc] then return end
  local lic = bestIdentifier(targetSrc); if not lic then return end

  local inviterInfo = s.players[src]
  local teamKey = inviterInfo and inviterInfo.team or nil
  local allowed = src == s.owner
  if s.teams then
    if not allowed and teamKey and s.teams[teamKey] and s.teams[teamKey].leader == src then
      allowed = true
    end
  end
  if not allowed then return end

  s.invites[lic] = { team = teamKey }
  TriggerClientEvent("exec:receiveInvite", targetSrc, {
    sessionId=sessionId, owner=GetPlayerName(src) or ("["..src.."]"),
    location=s.location, mode=s.mode, bracket=s.bracket, private=s.private, team=teamKey
  })
end)
RegisterNetEvent("exec:sessionSetTeam", function(sessionId, teamKey)
  teamKey = teamKey or 'alpha'
  local src = source
  local s = sessions[sessionId]; if not s or not s.players[src] then return end
  if not s.teams or s.active then return end
  if s.countdown and s.countdown <= 15 then
    TriggerClientEvent('exec:sessionNotify', src, { type = 'error', message = 'Teams are locked for the final 15 seconds.' })
    return
  end
  local info = s.players[src]
  if not s.teams[teamKey] then return end
  if info.team == teamKey then return end
  if not teamHasSpace(s, teamKey) then
    TriggerClientEvent('exec:sessionNotify', src, { type = 'error', message = 'Team is full.' })
    return
  end
  local previous = info.team
  if previous and s.teams[previous] then
    s.teams[previous].members[src] = nil
    if s.teams[previous].leader == src then
      s.teams[previous].leader = nil
      for pid,_ in pairs(s.teams[previous].members) do
        s.teams[previous].leader = pid
        break
      end
    end
    refreshTeamLabel(s, previous)
  end
  info.team = teamKey
  s.teams[teamKey].members[src] = true
  if not s.teams[teamKey].leader then
    s.teams[teamKey].leader = src
  end
  refreshTeamLabel(s, teamKey)
  if playerArena[src] then
    playerArena[src].team = teamKey
  end
  if s.countdown and not isSessionBalanced(s) then
    cancelCountdown(s)
  end
  pushScoreboard(s)
  broadcastLobby(s)
  ensureSessionState(s)
  TriggerClientEvent('exec:sessionTeamChanged', src, s.id, teamKey)
  local label = (s.teams[teamKey] and s.teams[teamKey].label) or teamKey
  TriggerClientEvent('exec:sessionNotify', src, { type = 'success', message = ('Joined %s'):format(label) })
end)

RegisterNetEvent("exec:sessionStart", function(sessionId, overrideStart)
  local src = source
  local s = sessions[sessionId]; if not s or s.owner ~= src then return end
  if s.active or s.countdown or s.prestarting then return end
  local override = overrideStart and true or false
  if s.teams then
    if not override and not isSessionBalanced(s) then
      TriggerClientEvent('exec:sessionNotify', src, { type = 'error', message = 'Teams must be balanced before starting.' })
      return
    end
  else
    if not override then
      local minPlayers = bracketMin(s.bracket)
      if sessionPlayerCount(s) < minPlayers then
        TriggerClientEvent('exec:sessionNotify', src, { type = 'error', message = 'Not enough players to start.' })
        return
      end
    end
  end
  startCountdown(s)
  broadcastLobby(s)
  TriggerClientEvent('exec:sessionNotify', src, { type = 'success', message = 'Match countdown started.' })
end)

RegisterNetEvent("exec:sessionToggleHardcore", function(sessionId)
  local src = source
  local s = sessions[sessionId]; if not s or s.owner ~= src then return end
  s.hardcore = not s.hardcore
  broadcastLobby(s)
  local enabled = s.hardcore and 'enabled' or 'disabled'
  for pid,_ in pairs(s.players) do
    TriggerClientEvent('exec:sessionHardcore', pid, s.id, s.hardcore)
    TriggerClientEvent('exec:sessionNotify', pid, { type = 'info', message = ('Hardcore mode %s'):format(enabled) })
  end
end)

lib.callback.register("exec:listSessionMembers", function(src, sessionId)
  local s = sessions[sessionId]; if not s then return {} end
  local out = {}
  for pid,_ in pairs(s.players) do
    local info = s.players[pid]
    out[#out+1] = { id = pid, name = GetPlayerName(pid) or ("["..pid.."]"), team = info and info.team }
  end
  table.sort(out, function(a,b) return a.id < b.id end)
  return out
end)

lib.callback.register("exec:reserveRespawnPoint", function(src, zone)
  clearRespawnReservationsForSource(src)
  local point = pickRespawnCandidate(src, zone)
  return respawnVectorToTable(point)
end)

RegisterNetEvent("exec:kickFromSession", function(sessionId, targetSrc)
  local src = source
  local s = sessions[sessionId]; if not s or s.owner ~= src then return end
  targetSrc = tonumber(targetSrc)
  if not targetSrc or not s.players[targetSrc] then return end
  removeFromCurrent(targetSrc)
  SetPlayerRoutingBucket(targetSrc, 0)
  TriggerClientEvent("exec:returnToHub", targetSrc, cfg.hub)
end)

RegisterNetEvent("exec:leaveMatch", function()
  local src = source
  removeFromCurrent(src)
  SetPlayerRoutingBucket(src, 0)
  TriggerClientEvent("exec:returnToHub", src, cfg.hub)
end)
AddEventHandler("playerDropped", function()
  local src = source
  removeFromCurrent(src)
  clearRespawnReservationsForSource(src)
  lastRespawnByPlayer[src] = nil
end)

-- ===== End flow (winner + end countdown) =====
endWithCountdown = function(s, winner)
  if not s or s.ended then return end
  s.ended = true
  winner = winner or {}
  local winnerLabel = winner.label or 'Winner'
  local secs = gp.endCountdownSeconds or 5
  for i=secs,1,-1 do
    for pid,_ in pairs(s.players) do
      TriggerClientEvent("exec:endingIn", pid, s.id, i, winnerLabel)
    end
    Wait(1000)
  end
  local ok, err = pcall(Stats.recordMatch, s, winner)
  if not ok then
    print(("[exec_framework] Failed to record match stats: %s"):format(err))
  end
  s.matchStats = nil
  for pid,_ in pairs(s.players) do
    TriggerClientEvent("exec:matchEnded", pid, s.bucket, winnerLabel)
    TriggerClientEvent("exec:returnToHub", pid, cfg.hub)
    SetPlayerRoutingBucket(pid, 0)
    local arena = playerArena[pid]
    if arena and arena.type == "session" and arena.sessionId == s.id then
      _decLocation(arena.location)
      playerArena[pid] = nil
    end
  end
  DB.insert([[INSERT INTO exec_matches (mode, bracket, location, bucket, winner_json) VALUES (?,?,?,?,?)]],
            { s.mode, s.bracket, s.location, s.bucket, json.encode({ name = winnerLabel, noContest = winner.noContest == true }) })
  freeBucket(s.bucket); sessions[s.id] = nil
end

RegisterNetEvent("exec:serverKill", function(victimSrc, info)
  local killer = source
  local killDetails = type(info) == "table" and info or {}
  local ka, va = playerArena[killer], playerArena[victimSrc]
  if not ka or not va then return end
  if ka.bucket ~= GetPlayerRoutingBucket(killer) or va.bucket ~= GetPlayerRoutingBucket(victimSrc) then return end
  if ka.type == "playground" then
    if va.type ~= "playground" then return end
    local zone = sessionZonePayload({ location = ka.location })
    local killerPed = GetPlayerPed(killer)
    local victimPed = GetPlayerPed(victimSrc)
    local killerPos = killerPed ~= 0 and GetEntityCoords(killerPed) or nil
    local victimPos = victimPed ~= 0 and GetEntityCoords(victimPed) or nil
    local baseRadius, buffer = resolveSessionCombatRadius(zone)
    if zone and zone.center and baseRadius then
      local radiusSq = (baseRadius + buffer) * (baseRadius + buffer)
      if killerPos and distanceSquared(killerPos, zone.center) > radiusSq then return end
      if victimPos and distanceSquared(victimPos, zone.center) > radiusSq then return end
    end
    local eventKillerPos = vecFromTable(killDetails.killerCoords) or killerPos
    local eventVictimPos = vecFromTable(killDetails.victimCoords) or victimPos
    local fakeSession = {
      id = 0,
      bucket = ka.bucket,
      location = ka.location,
      bracket = 'ffa',
      mode = ka.mode,
      players = playgroundPlayerSet(ka.location, ka.mode),
    }
    emitKillfeedEvent(fakeSession, killer, victimSrc, killDetails, zone, eventKillerPos, eventVictimPos)
    return
  end
  if ka.type ~= "session" then return end

  local s = sessions[ka.sessionId]; if not s or not s.active then return end

  local zone = sessionZonePayload(s)
  local killerPed = GetPlayerPed(killer)
  local victimPed = GetPlayerPed(victimSrc)
  local killerPos = killerPed ~= 0 and GetEntityCoords(killerPed) or nil
  local victimPos = victimPed ~= 0 and GetEntityCoords(victimPed) or nil

  local baseRadius, buffer = resolveSessionCombatRadius(zone)
  if zone and zone.center and baseRadius then
    local radiusSq = (baseRadius + buffer) * (baseRadius + buffer)
    if killerPos and distanceSquared(killerPos, zone.center) > radiusSq then return end
    if victimPos and distanceSquared(victimPos, zone.center) > radiusSq then return end
  end

  local eventKillerPos = vecFromTable(killDetails.killerCoords) or killerPos
  local eventVictimPos = vecFromTable(killDetails.victimCoords) or victimPos

  local killerInfo = s.players[killer]
  local victimInfo = s.players[victimSrc]
  local killerTeam = killerInfo and killerInfo.team
  local victimTeam = victimInfo and victimInfo.team

  local function trackStats(kId, vId)
    local stats = s.matchStats
    if not stats or not stats.players then return end
    stats.players[kId] = stats.players[kId] or { kills = 0, deaths = 0 }
    stats.players[kId].kills = (stats.players[kId].kills or 0) + 1
    stats.players[vId] = stats.players[vId] or { kills = 0, deaths = 0 }
    stats.players[vId].deaths = (stats.players[vId].deaths or 0) + 1
  end

  if s.teams and killerTeam and victimTeam then
    if killerTeam == victimTeam then
      if s.hardcore then
        s.kills[killer] = math.max(0, (s.kills[killer] or 0) - 1)
        if s.teamKills and s.teamKills[killerTeam] then
          s.teamKills[killerTeam] = math.max(0, (s.teamKills[killerTeam] or 0) - 1)
        end
        TriggerClientEvent("exec:onKillConfirmed", killer, s.kills[killer], s.firstTo)
        pushScoreboard(s)
      end
      return
    end

    s.kills[killer] = (s.kills[killer] or 0) + 1
    if s.teamKills then
      s.teamKills[killerTeam] = (s.teamKills[killerTeam] or 0) + 1
    end
    trackStats(killer, victimSrc)
    TriggerClientEvent("exec:onKillConfirmed", killer, s.kills[killer], s.firstTo)
    pushScoreboard(s)
    emitKillfeedEvent(s, killer, victimSrc, killDetails, zone, eventKillerPos, eventVictimPos, killerTeam, victimTeam)
    local teamScore = s.teamKills and s.teamKills[killerTeam] or 0
    if teamScore >= s.firstTo then
      local teamLabel = (s.teams[killerTeam] and s.teams[killerTeam].label) or killerTeam
      endWithCountdown(s, { label = teamLabel, teamKey = killerTeam })
    end
    return
  end

  s.kills[killer] = (s.kills[killer] or 0) + 1
  local current = s.kills[killer]
  trackStats(killer, victimSrc)
  TriggerClientEvent("exec:onKillConfirmed", killer, current, s.firstTo)
  pushScoreboard(s)
  emitKillfeedEvent(s, killer, victimSrc, killDetails, zone, eventKillerPos, eventVictimPos, killerTeam, victimTeam)
  if current >= s.firstTo then
    local winner = GetPlayerName(killer) or ("["..killer.."]")
    endWithCountdown(s, { label = winner, playerId = killer })
  end
end)


RegisterNetEvent("exec:requestRespawnLoadout", function()
  local src = source
  local a = playerArena[src]
  if not a then return end
  local m = cfg.modes[a.mode] or {}
  local cat = resolveCategoryPreference(m.categoryLock, a.prefCategory)
  local w   = (m.weaponLock)   or (a.prefWeapon)
  if not cat then
    local allowed = allowedCategoriesFor(src, a)
    cat = allowed[1]
  end
  TriggerClientEvent("exec:applyLoadout", src, a.mode, a.type == "session", cat, w)
end)

-- Counts summary callback for menus
lib.callback.register("exec:getCountsSummary", function(src)
  return buildLiveCountsSummary()
end)

local function notifyWeaponUnlockAdmin(src, message, typ)
  if src == 0 then
    print(("[exec_framework] %s"):format(message))
  else
    NotifyBridge.Send(src, {
      title = "Weapon Unlocks",
      description = message,
      type = typ or "inform"
    })
  end
end

local function parseLockArg(value)
  if type(value) ~= "string" then return nil end
  local normalized = value:lower()
  if normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "lock" or normalized == "locked" then
    return true
  end
  if normalized == "false" or normalized == "0" or normalized == "no" or normalized == "unlock" or normalized == "unlocked" then
    return false
  end
  return nil
end

local function resolveWeaponUnlockLicense(target)
  if type(target) ~= "string" or target == "" then return nil end
  if target:find("^license[2]?:") then
    return target
  end
  if target:find("^{.+}$") then
    return nil, "unresolved_placeholder"
  end

  local maybeServerId = tonumber(target)
  if maybeServerId and GetPlayerName(maybeServerId) then
    return WeaponUnlocks.licenseFromSource(maybeServerId)
  end

  local targetLower = target:lower()
  for _, id in ipairs(GetPlayers()) do
    local playerSrc = tonumber(id)
    if playerSrc then
      local playerName = GetPlayerName(playerSrc)
      if playerName and playerName:lower() == targetLower then
        return WeaponUnlocks.licenseFromSource(playerSrc)
      end
      for _, identifier in ipairs(GetPlayerIdentifiers(playerSrc)) do
        local identifierLower = identifier:lower()
        local identifierValue = identifierLower:match("^[^:]+:(.+)$")
        if identifierLower == targetLower or identifierValue == targetLower then
          return WeaponUnlocks.licenseFromSource(playerSrc)
        end
      end
    end
  end

  return nil
end

RegisterCommand("exec_weaponlock", function(src, args)
  if not hasWeaponUnlockAdmin(src) then
    notifyWeaponUnlockAdmin(src, "You do not have permission to run this command.", "error")
    return
  end
  local target = args[1]
  local weaponCode = args[2]
  local flag = args[3]
  if not target or not weaponCode or not flag then
    notifyWeaponUnlockAdmin(src, "Usage: /exec_weaponlock <license|playerId> <weapon> <lock|unlock>", "error")
    return
  end
  local license, resolveErr = resolveWeaponUnlockLicense(target)
  if not license then
    if resolveErr == "unresolved_placeholder" then
      notifyWeaponUnlockAdmin(src, ("Tebex sent '%s' literally. Enable online command delivery or use a supported Tebex variable like {hexid} or {username}."):format(target), "error")
    else
      notifyWeaponUnlockAdmin(src, ("Could not resolve '%s' to an online player license. Use a server ID, license:, steam:/fivem: identifier, or exact online username."):format(target), "error")
    end
    return
  end
  local shouldLock = parseLockArg(flag)
  if shouldLock == nil then
    notifyWeaponUnlockAdmin(src, "Lock flag must be lock/unlock or true/false.", "error")
    return
  end
  local ok, err = WeaponUnlocks.setLicenseWeapon(license, weaponCode, not shouldLock, {
    meta = {
      admin = src,
      locked = shouldLock,
      timestamp = os.time()
    }
  })
  if not ok then
    notifyWeaponUnlockAdmin(src, ("Failed to update entitlement: %s"):format(err or "unknown error"), "error")
    return
  end
  local action = shouldLock and "locked" or "unlocked"
  notifyWeaponUnlockAdmin(src, ("Marked %s as %s for %s"):format(weaponCode, action, license), shouldLock and "warning" or "success")
end, false)

local function handleTebexPurchase(purchase, srcHint)
  if type(purchase) ~= "table" then return end
  local license = WeaponUnlocks.licenseFromPurchase(purchase) or (srcHint and WeaponUnlocks.licenseFromSource(srcHint))
  if not license then return end
  local sku = WeaponUnlocks.skuFromPurchase(purchase)
  if not sku then return end
  local ok, err = WeaponUnlocks.unlockBySku(license, sku, {
    transaction = purchase.transaction or purchase.tx_id or purchase.txid or purchase.id,
    package = purchase.package and purchase.package.name or nil,
    amount = purchase.amount,
    source = "tebex"
  })
  if not ok then
    print(("[exec_framework] Tebex purchase for SKU %s ignored: %s"):format(sku, err or "unknown error"))
  end
end

RegisterNetEvent("tebex:playerPurchasedPackage", function(purchase)
  local src = source > 0 and source or nil
  local ok, err = pcall(handleTebexPurchase, purchase, src)
  if not ok then
    print(("[exec_framework] Tebex handler error: %s"):format(err))
  end
end)

RegisterNetEvent("sv_tebex_bought", function(...)
  local args = { ... }
  if #args == 1 and type(args[1]) == "table" then
    handleTebexPurchase(args[1], source)
    return
  end
  local sku
  local transaction
  local playerSrc
  for _, value in ipairs(args) do
    if type(value) == "number" and GetPlayerName(value) then
      playerSrc = value
    elseif not sku then
      sku = value
    else
      transaction = transaction or value
    end
  end
  playerSrc = playerSrc or (type(source) == "number" and source or nil)
  if not sku then
    print("[exec_framework] sv_tebex_bought missing SKU argument, skipping")
    return
  end
  local license = playerSrc and WeaponUnlocks.licenseFromSource(playerSrc)
  if not license then
    print("[exec_framework] sv_tebex_bought missing license, skipping")
    return
  end
  local ok, err = WeaponUnlocks.unlockBySku(license, sku, {
    transaction = transaction or "sv_tebex_bought",
    source = "tebex"
  })
  if not ok then
    print(("[exec_framework] sv_tebex_bought failed for SKU %s: %s"):format(sku, err or "unknown error"))
  end
end)


























