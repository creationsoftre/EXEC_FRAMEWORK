local DB = require 'server.db'
local gcfg = require 'config.gangs'
local utils = require 'shared.utils'
local Identity = require 'server.identity'
local NotifyBridge = require 'bridge.notify'

local GangService = {}

local gangs = {}
local memberIndex = {} -- [citizenid] = { gangId = id, member = table }
local memberRefreshAttempts = {}
local pendingInvites = {}

local defaultRanks = gcfg.defaults and gcfg.defaults.ranks or {
  boss = 'Boss',
  underboss = 'Underboss',
  hitman = 'Hitman',
  footsoldier = 'Foot Soldier'
}

local defaultUnderbossPerms = gcfg.defaults and gcfg.defaults.underbossPerms or {
  renameRanks = false,
  manageMembers = false,
  viewDetails = true,
  dissolve = false
}

local maxMembers = gcfg.limits and gcfg.limits.maxMembers or 20
local maxUnderboss = gcfg.limits and gcfg.limits.underboss or 3
local inviteExpirySeconds = (gcfg.invite and gcfg.invite.expirySeconds) or 60

local json = json

local function deepCopy(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local result = {}
  for k,v in pairs(tbl) do
    if type(v) == 'table' then
      result[k] = deepCopy(v)
    else
      result[k] = v
    end
  end
  return result
end

local function resolvePlayerIdentity(src)
  local identifier, citizenId, license = Identity.ensureIdentifier(src)
  citizenId = citizenId or identifier or license
  license = license or identifier or citizenId
  if not citizenId or citizenId == '' then
    return nil, nil
  end
  return citizenId, license or ''
end

local function resolveCitizenId(src)
  local citizenId = resolvePlayerIdentity(src)
  return citizenId
end

local function notify(src, msg, typ)
  local presets = {
    success = { type = 'success', icon = 'check-circle', iconColor = '#39FF14' },
    error = { type = 'error', icon = 'times-circle', iconColor = '#FF3B3B' },
    warning = { type = 'warning', icon = 'exclamation-triangle', iconColor = '#FFB020' },
    inform = { type = 'info', icon = 'info-circle', iconColor = '#39FF14' },
    info = { type = 'info', icon = 'info-circle', iconColor = '#39FF14' },
  }
  local preset = presets[typ or 'inform'] or presets.inform
  NotifyBridge.Send(src, {
    title = 'Gangs',
    description = msg,
    type = preset.type,
    icon = preset.icon,
    iconColor = preset.iconColor,
    duration = 4500,
    alignIcon = 'center',
    style = {
      backgroundColor = '#1A1B1E',
      color = '#FFFFFF',
      border = '1px solid #2A2C30',
      borderRadius = '8px',
      boxShadow = '0 10px 28px rgba(0, 0, 0, 0.6)',
    }
  })
end

local function applyDefaults(row)
  row.rank_labels = row.rank_labels and json.decode(row.rank_labels) or deepCopy(defaultRanks)
  row.underboss_perms = row.underboss_perms and json.decode(row.underboss_perms) or deepCopy(defaultUnderbossPerms)
end

local function normalizeGangRow(row)
  if type(row) ~= 'table' then return end
  local leader = row.leader_citizenid
  if not leader or leader == '' then
    leader = row.leader_char
  end
  if not leader or leader == '' then
    leader = row.leader_license
  end
  if leader and leader ~= '' then
    leader = tostring(leader)
    row.leader_citizenid = leader
    if not row.leader_char or row.leader_char == '' then
      row.leader_char = leader
    end
  else
    row.leader_citizenid = ''
  end
  row.leader_license = row.leader_license or ''
end

local function normalizeMemberRow(row)
  if type(row) ~= 'table' then return nil end
  local citizenId = row.citizenid
  if not citizenId or citizenId == '' then
    citizenId = row.char_id
  end
  if not citizenId or citizenId == '' then
    citizenId = row.license
  end
  if not citizenId or citizenId == '' then
    return nil
  end
  citizenId = tostring(citizenId)
  row.citizenid = citizenId
  row.char_id = row.char_id and row.char_id ~= '' and row.char_id or citizenId
  row.license = row.license or ''
  return citizenId
end

local function loadGangs()
  gangs = {}
  memberIndex = {}
  memberRefreshAttempts = {}

  local gangRows = DB.query('SELECT * FROM exec_gangs', {})
  for _, row in ipairs(gangRows) do
    normalizeGangRow(row)
    applyDefaults(row)
    row.members = {}
    row.memberCount = 0
    gangs[row.id] = row
  end

  local memberRows = DB.query('SELECT * FROM exec_gangmembers', {})
  for _, row in ipairs(memberRows) do
    local gang = gangs[row.gang_id]
    if gang then
      local citizenId = normalizeMemberRow(row)
      if citizenId then
        gang.members[citizenId] = row
        gang.memberCount = gang.memberCount + 1
        memberIndex[citizenId] = { gangId = row.gang_id, member = row }
      end
    end
  end
end

local function getGang(id)
  return gangs[id]
end

local function getMemberByCitizenId(citizenId)
  if not citizenId or citizenId == '' then return nil, nil end
  local entry = memberIndex[citizenId]
  if entry then
    return gangs[entry.gangId], entry.member
  end
end

local function isAdmin(src)
  local config = gcfg.admin or {}
  if config.identifiers then
    local ids = GetPlayerIdentifiers(src)
    for _, id in ipairs(ids) do
      for _, allow in ipairs(config.identifiers) do
        if id == allow then
          return true
        end
      end
    end
  end
  if config.ace and config.ace ~= '' then
    if IsPlayerAceAllowed(src, config.ace) then
      return true
    end
  end
  return false
end

local function syncPlayerGang(src)
  local citizenId = resolveCitizenId(src)
  if not citizenId then
    TriggerClientEvent('exec:gang:sync', src, nil)
    return
  end
  local entry = memberIndex[citizenId]
  if not entry then
    local attempts = memberRefreshAttempts[citizenId] or 0
    if attempts < 1 then
      loadGangs()
      entry = memberIndex[citizenId]
      if entry then
        memberRefreshAttempts[citizenId] = nil
      else
        memberRefreshAttempts[citizenId] = attempts + 1
      end
    end
  else
    memberRefreshAttempts[citizenId] = nil
  end
  if not entry then
    TriggerClientEvent('exec:gang:sync', src, nil)
    return
  end
  local gang = gangs[entry.gangId]
  if not gang then
    loadGangs()
    entry = memberIndex[citizenId]
    if entry then
      gang = gangs[entry.gangId]
      if gang then
        memberRefreshAttempts[citizenId] = nil
      end
    end
  end
  if not entry or not gang then
    TriggerClientEvent('exec:gang:sync', src, nil)
    return
  end
  local member = entry.member
  if not member then
    TriggerClientEvent('exec:gang:sync', src, nil)
    return
  end
  if member.pendingLeaderTransfer and not member.pendingLeaderTransfer.sent then
    local pending = member.pendingLeaderTransfer
    if pending.data then
      TriggerClientEvent('exec:gang:leaderTransferPrompt', src, pending.data)
    end
    pending.sent = true
  end
  local isLeader = (gang.leader_citizenid == citizenId)
  local isUnderboss = (member.rank == 'underboss')
  local perms
  if isLeader then
    perms = { renameRanks = true, manageMembers = true, viewDetails = true, dissolve = true }
  elseif isUnderboss then
    perms = deepCopy(gang.underboss_perms)
  else
    perms = { renameRanks = false, manageMembers = false, viewDetails = true, dissolve = false }
  end
  TriggerClientEvent('exec:gang:sync', src, {
    gangId = gang.id,
    gangName = gang.name,
    rank = member.rank,
    rankLabels = gang.rank_labels,
    strikes = gang.strikes,
    wins = gang.wins,
    losses = gang.losses,
    active = gang.active == 1,
    isLeader = isLeader,
    isUnderboss = isUnderboss,
    permissions = perms
  })
end


local function onlineSourceForCitizen(citizenId)
  if not citizenId or citizenId == '' then return nil end
  for _, sid in ipairs(GetPlayers()) do
    local num = tonumber(sid)
    if num then
      local currentCitizen = resolveCitizenId(num)
      if currentCitizen == citizenId then
        return num
      end
    end
  end
end

local function broadcastGang(gang)
  for _, member in pairs(gang.members) do
    local src = onlineSourceForCitizen(member.citizenid)
    if src then
      syncPlayerGang(src)
    end
  end
end

local function clearInvitesForGang(gangId, reason)
  if not gangId then return end
  for citizenId, invite in pairs(pendingInvites) do
    if invite.gangId == gangId then
      pendingInvites[citizenId] = nil
      local targetSrc = onlineSourceForCitizen(citizenId)
      if targetSrc and reason then
        notify(targetSrc, reason, 'inform')
      end
    end
  end
end

local function clearInviteForCitizen(citizenId, reason)
  if not citizenId then return end
  local invite = pendingInvites[citizenId]
  if not invite then return end
  pendingInvites[citizenId] = nil
  local targetSrc = onlineSourceForCitizen(citizenId)
  if targetSrc and reason then
    notify(targetSrc, reason, 'inform')
  end
end

local function countByRank(gang, rank)
  local count = 0
  for _, member in pairs(gang.members) do
    if member.rank == rank then count = count + 1 end
  end
  return count
end

local function canPromoteToUnderboss(gang)
  return countByRank(gang, 'underboss') < maxUnderboss
end

local function addMember(gang, citizenId, license, name, rank)
  if not citizenId or citizenId == '' then
    return false, 'Invalid member identifier'
  end
  citizenId = tostring(citizenId)
  if gang.memberCount >= maxMembers and rank ~= 'boss' then
    return false, 'Gang member limit reached'
  end
  if memberIndex[citizenId] then
    return false, 'Player already in a gang'
  end
  pendingInvites[citizenId] = nil
  local memberId = DB.insert([[INSERT INTO exec_gangmembers (gang_id, citizenid, license, char_id, member_name, rank)
    VALUES (?, ?, ?, ?, ?, ?)]], { gang.id, citizenId, license or '', citizenId, name or '', rank })
  if not memberId then
    return false, 'Database error'
  end
  local member = {
    id = memberId,
    gang_id = gang.id,
    citizenid = citizenId,
    license = license or '',
    char_id = citizenId,
    member_name = name or '',
    rank = rank,
    wins = 0,
    losses = 0,
    kills = 0,
    deaths = 0,
    joined_at = os.date('%Y-%m-%d %H:%M:%S'),
    last_active = os.date('%Y-%m-%d %H:%M:%S')
  }
  gang.members[citizenId] = member
  gang.memberCount = gang.memberCount + 1
  memberIndex[citizenId] = { gangId = gang.id, member = member }
  return true
end

local function removeMember(gang, citizenId)
  if not citizenId or citizenId == '' then return end
  citizenId = tostring(citizenId)
  DB.exec('DELETE FROM exec_gangmembers WHERE gang_id = ? AND citizenid = ?', { gang.id, citizenId })
  gang.members[citizenId] = nil
  gang.memberCount = math.max(0, gang.memberCount - 1)
  memberIndex[citizenId] = nil
end

local function gangSummary(row)
  local leaderSrc = onlineSourceForCitizen(row.leader_citizenid)
  local leaderName = leaderSrc and GetPlayerName(leaderSrc) or 'Offline'
  return {
    id = row.id,
    name = row.name,
    active = row.active == 1,
    strikes = row.strikes,
    wins = row.wins,
    losses = row.losses,
    leader = leaderName,
    leaderOnline = leaderSrc ~= nil,
    memberCount = row.memberCount,
    rankLabels = row.rank_labels,
    underbossPerms = row.underboss_perms
  }
end

local function memberPayload(gang)
  local list = {}
  for _, member in pairs(gang.members) do
    local src = onlineSourceForCitizen(member.citizenid)
    local displayId = member.citizenid or member.license
    list[#list+1] = {
      citizenid = member.citizenid,
      license = member.license,
      name = src and GetPlayerName(src) or (member.member_name ~= '' and member.member_name or displayId),
      rank = member.rank,
      wins = member.wins,
      losses = member.losses,
      kills = member.kills,
      deaths = member.deaths,
      joined_at = member.joined_at,
      last_active = member.last_active,
      online = src ~= nil,
      source = src
    }
  end
  table.sort(list, function(a, b)
    if a.rank == b.rank then
      return a.name < b.name
    end
    local order = { boss = 1, underboss = 2, hitman = 3, footsoldier = 4 }
    return (order[a.rank] or 99) < (order[b.rank] or 99)
  end)
  return list
end

local function saveGangRanks(gang)
  DB.exec('UPDATE exec_gangs SET rank_labels = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    { json.encode(gang.rank_labels), gang.id })
end

local function saveUnderbossPerms(gang)
  DB.exec('UPDATE exec_gangs SET underboss_perms = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    { json.encode(gang.underboss_perms), gang.id })
end

local function updateGangField(gang, field, value)
  DB.exec(('UPDATE exec_gangs SET %s = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?'):format(field), { value, gang.id })
  gang[field] = value
end

local function setMemberRank(gang, member, rank)
  DB.exec('UPDATE exec_gangmembers SET rank = ?, last_active = CURRENT_TIMESTAMP WHERE id = ?', { rank, member.id })
  member.rank = rank
end

local function setMemberName(gang, member, name)
  member.member_name = name or member.member_name
  DB.exec('UPDATE exec_gangmembers SET member_name = ? WHERE id = ?', { member.member_name, member.id })
end

local function resolveMemberBySource(src)
  local citizenId = resolveCitizenId(src)
  if not citizenId then return nil, nil end
  local entry = memberIndex[citizenId]
  if not entry then
    local attempts = memberRefreshAttempts[citizenId] or 0
    if attempts < 1 then
      loadGangs()
      entry = memberIndex[citizenId]
      if entry then
        memberRefreshAttempts[citizenId] = nil
      else
        memberRefreshAttempts[citizenId] = attempts + 1
      end
    end
  else
    memberRefreshAttempts[citizenId] = nil
  end
  if not entry then return nil, nil end
  local gang = gangs[entry.gangId]
  if not gang then
    loadGangs()
    entry = memberIndex[citizenId]
    if entry then
      gang = gangs[entry.gangId]
      if gang then
        memberRefreshAttempts[citizenId] = nil
      end
    else
      gang = nil
    end
  end
  if not gang or not entry or not entry.member then return nil, nil end
  return gang, entry.member
end

AddEventHandler('playerDropped', function()
  local src = source
  local gang, member = resolveMemberBySource(src)
  if gang and member then
    member.last_active = os.date('%Y-%m-%d %H:%M:%S')
    DB.exec('UPDATE exec_gangmembers SET last_active = CURRENT_TIMESTAMP WHERE id = ?', { member.id })
  end
end)

GangService.init = function()
  loadGangs()
  for _, sid in ipairs(GetPlayers()) do
    syncPlayerGang(tonumber(sid))
  end
end

GangService.getGangForSource = function(src)
  local gang, member = resolveMemberBySource(src)
  if not gang then return nil, nil end
  return gang, member
end

GangService.getGangForLicense = function(identifier)
  if not identifier then return nil, nil end
  return getMemberByCitizenId(identifier)
end

GangService.getGangForCitizenId = function(citizenId)
  if not citizenId then return nil, nil end
  return getMemberByCitizenId(citizenId)
end

GangService.getGangNameForSource = function(src)
  local gang = GangService.getGangForSource(src)
  if gang then
    return gang.name
  end
end

AddEventHandler('playerJoining', function()
  local src = source
  CreateThread(function()
    Wait(1000)
    syncPlayerGang(src)
  end)
end)

lib.callback.register('exec:gang:getAdminData', function(src)
  if not isAdmin(src) then
    return { ok = false, error = 'You do not have permission.' }
  end
  local list = {}
  for _, gang in pairs(gangs) do
    list[#list+1] = gangSummary(gang)
  end
  table.sort(list, function(a,b) return a.name < b.name end)
  return { ok = true, gangs = list, defaults = { ranks = defaultRanks, underboss = defaultUnderbossPerms } }
end)

lib.callback.register('exec:gang:create', function(src, payload)
  if not isAdmin(src) then return { ok = false, error = 'No permission.' } end
  local name = (payload and payload.name or ''):match('^%s*(.-)%s*$')
  local leaderSrc = tonumber(payload and payload.leader)
  if not name or name == '' then return { ok=false, error='Gang name required.' } end
  if not leaderSrc or not GetPlayerName(leaderSrc) then return { ok=false, error='Leader must be online.' } end
  local citizenId, license = resolvePlayerIdentity(leaderSrc)
  if not citizenId then return { ok=false, error='Unable to determine leader identity.' } end
  local gangExisting, memberExisting = resolveMemberBySource(leaderSrc)
  if memberExisting then return { ok=false, error='Leader is already in a gang.' } end

  local gangId = DB.insert([[INSERT INTO exec_gangs (name, leader_citizenid, leader_license, leader_char, rank_labels, underboss_perms)
    VALUES (?, ?, ?, ?, ?, ?)]],
    { name, citizenId, license or '', citizenId, json.encode(defaultRanks), json.encode(defaultUnderbossPerms) })
  if not gangId then return { ok=false, error='Failed to create gang.' } end

  local gang = {
    id = gangId,
    name = name,
    leader_citizenid = citizenId,
    leader_license = license or '',
    leader_char = citizenId,
    strikes = 0,
    wins = 0,
    losses = 0,
    active = 1,
    rank_labels = deepCopy(defaultRanks),
    underboss_perms = deepCopy(defaultUnderbossPerms),
    members = {},
    memberCount = 0
  }
  gangs[gangId] = gang

  local ok, err = addMember(gang, citizenId, license, GetPlayerName(leaderSrc), 'boss')
  if not ok then
    gangs[gangId] = nil
    DB.exec('DELETE FROM exec_gangs WHERE id = ?', { gangId })
    return { ok=false, error=err }
  end

  syncPlayerGang(leaderSrc)
  return { ok=true }
end)

lib.callback.register('exec:gang:delete', function(src, payload)
  if not isAdmin(src) then return { ok=false, error='No permission.' } end
  local gang = gangs[payload and payload.gangId]
  if not gang then return { ok=false, error='Gang not found.' } end
  DB.exec('DELETE FROM exec_gangs WHERE id = ?', { gang.id })
  clearInvitesForGang(gang.id, ('Invite to %s is no longer available.'):format(gang.name or 'a gang'))
  gangs[gang.id] = nil
  loadGangs()
  for _, sid in ipairs(GetPlayers()) do
    syncPlayerGang(tonumber(sid))
  end
  return { ok=true }
end)

lib.callback.register('exec:gang:setActive', function(src, payload)
  if not isAdmin(src) then return { ok=false, error='No permission.' } end
  local gang = gangs[payload and payload.gangId]
  if not gang then return { ok=false, error='Gang not found.' } end
  local active = payload and payload.active and 1 or 0
  updateGangField(gang, 'active', active)
  broadcastGang(gang)
  return { ok=true }
end)

lib.callback.register('exec:gang:setLeader', function(src, payload)
  local requestedGangId = payload and payload.gangId
  local gang
  local callerIsAdmin = isAdmin(src)
  if requestedGangId then
    gang = gangs[requestedGangId]
    if not gang then return { ok=false, error='Gang not found.' } end
    if not callerIsAdmin then
      return { ok=false, error='No permission.' }
    end
  else
    gang = select(1, resolveMemberBySource(src))
    if not gang then return { ok=false, error='Gang not found.' } end
    if not callerIsAdmin then
      local citizenId = resolveCitizenId(src)
      if not citizenId or gang.leader_citizenid ~= citizenId then
        return { ok=false, error='Only the leader can transfer ownership.' }
      end
    end
  end

  local newCitizenId
  local newLicense
  local newName
  local newSrc
  local targetCitizen = payload and (payload.leaderCitizen or payload.citizenId or payload.citizen)
  if targetCitizen then
    targetCitizen = tostring(targetCitizen)
    local member = gang.members[targetCitizen]
    if not member then
      return { ok=false, error='Target is not a gang member.' }
    end
    newCitizenId = member.citizenid
    newLicense = member.license
    newName = (member.member_name and member.member_name ~= '' and member.member_name) or newCitizenId
    newSrc = onlineSourceForCitizen(newCitizenId)
  else
    local target = payload and payload.leader
    if type(target) == 'string' then
      target = tonumber(target)
    end
    if type(target) ~= 'number' or not GetPlayerName(target) then
      return { ok=false, error='Player must be online.' }
    end
    newSrc = target
    newCitizenId, newLicense = resolvePlayerIdentity(target)
    if not newCitizenId then return { ok=false, error='Cannot resolve identifier.' } end
    newName = GetPlayerName(target)
  end

  if gang.leader_citizenid == newCitizenId then
    return { ok=false, error='Player is already the leader.' }
  end

  local memberRecord = gang.members[newCitizenId]
  if not memberRecord then
    if not callerIsAdmin then
      return { ok=false, error='Target must already be in the gang.' }
    end
    local ok, err = addMember(gang, newCitizenId, newLicense, newName, 'hitman')
    if not ok then return { ok=false, error=err } end
    memberRecord = gang.members[newCitizenId]
  else
    setMemberName(gang, memberRecord, newName)
  end

  local oldLeaderCitizen = gang.leader_citizenid
  gang.leader_citizenid = newCitizenId
  gang.leader_license = newLicense or gang.leader_license or ''
  gang.leader_char = newCitizenId
  DB.exec('UPDATE exec_gangs SET leader_citizenid = ?, leader_license = ?, leader_char = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    { newCitizenId, newLicense or '', newCitizenId, gang.id })

  for _, member in pairs(gang.members) do
    if member.citizenid == newCitizenId then
      setMemberRank(gang, member, 'boss')
      member.pendingLeaderTransfer = nil
    elseif member.citizenid == oldLeaderCitizen then
      setMemberRank(gang, member, 'hitman')
    end
  end

  local oldLeaderMember = oldLeaderCitizen and gang.members[oldLeaderCitizen] or nil
  if oldLeaderMember and oldLeaderCitizen ~= newCitizenId then
    local pendingData = {
      gangId = gang.id,
      gangName = gang.name,
      newLeader = newName,
      canUnderboss = canPromoteToUnderboss(gang),
      underbossLimit = maxUnderboss,
      underbossCount = countByRank(gang, 'underboss')
    }
    oldLeaderMember.pendingLeaderTransfer = { data = pendingData, sent = false }
    local oldLeaderSrc = onlineSourceForCitizen(oldLeaderCitizen)
    if oldLeaderSrc then
      TriggerClientEvent('exec:gang:leaderTransferPrompt', oldLeaderSrc, pendingData)
      oldLeaderMember.pendingLeaderTransfer.sent = true
      notify(oldLeaderSrc, ('%s is now leading %s.'):format(newName, gang.name), 'inform')
    end
  end

  broadcastGang(gang)

  if newSrc then
    notify(newSrc, ('You are now the leader of %s.'):format(gang.name), 'success')
    syncPlayerGang(newSrc)
  end

  return { ok=true }
end)

lib.callback.register('exec:gang:updateRanks', function(src, payload)
  local gang
  local member
  if isAdmin(src) and payload and payload.gangId then
    gang = gangs[payload.gangId]
  else
    gang, member = resolveMemberBySource(src)
    if not gang then return { ok=false, error='Not part of a gang.' } end
    local citizenId = resolveCitizenId(src)
    if gang.leader_citizenid ~= citizenId then
      local perms = gang.underboss_perms or {}
      if member.rank ~= 'underboss' or not perms.renameRanks then
        return { ok=false, error='Permission denied.' }
      end
    end
  end
  if not gang then return { ok=false, error='Gang not found.' } end
  local ranks = payload and payload.ranks
  if not ranks or type(ranks) ~= 'table' then return { ok=false, error='Invalid data.' } end
  for key, label in pairs(defaultRanks) do
    local newLabel = ranks[key]
    if newLabel and newLabel ~= '' then
      gang.rank_labels[key] = newLabel
    else
      gang.rank_labels[key] = defaultRanks[key]
    end
  end
  saveGangRanks(gang)
  broadcastGang(gang)
  return { ok=true }
end)

lib.callback.register('exec:gang:underbossPerms', function(src, payload)
  local gang, member = resolveMemberBySource(src)
  if not gang then return { ok=false, error='Not part of a gang.' } end
  if gang.leader_citizenid ~= resolveCitizenId(src) then
    return { ok=false, error='Only the gang leader can change permissions.' }
  end
  local perms = payload and payload.perms
  if not perms or type(perms) ~= 'table' then return { ok=false, error='Invalid permissions.' } end
  gang.underboss_perms = {
    renameRanks = perms.renameRanks and true or false,
    manageMembers = perms.manageMembers and true or false,
    viewDetails = perms.viewDetails ~= false,
    dissolve = perms.dissolve and true or false
  }
  saveUnderbossPerms(gang)
  broadcastGang(gang)
  return { ok=true }
end)

lib.callback.register('exec:gang:strike', function(src, payload)
  if not isAdmin(src) then return { ok=false, error='No permission.' } end
  local gang = gangs[payload and payload.gangId]
  if not gang then return { ok=false, error='Gang not found.' } end
  local amount = tonumber(payload and payload.amount) or 0
  if payload and payload.remove then
    gang.strikes = math.max(0, gang.strikes - math.abs(amount))
  else
    gang.strikes = gang.strikes + math.abs(amount)
  end
  updateGangField(gang, 'strikes', gang.strikes)
  broadcastGang(gang)
  return { ok=true, strikes = gang.strikes }
end)

lib.callback.register('exec:gang:getLeaderData', function(src)
  local gang, member = resolveMemberBySource(src)
  if not gang or not member then
    return { ok=false, error='You are not part of a gang.' }
  end
  local citizenId = resolveCitizenId(src)
  local isLeader = gang.leader_citizenid == citizenId
  local isUnderboss = member.rank == 'underboss'
  local perms
  if isLeader then
    perms = { renameRanks = true, manageMembers = true, viewDetails = true, dissolve = true }
  elseif isUnderboss then
    perms = deepCopy(gang.underboss_perms)
  else
    perms = { renameRanks = false, manageMembers = false, viewDetails = true, dissolve = false }
  end
  if not perms.viewDetails then
    return { ok=false, error='Permission denied.' }
  end
  local result = {
    ok = true,
    gang = {
      id = gang.id,
      name = gang.name,
      strikes = gang.strikes,
      wins = gang.wins,
      losses = gang.losses,
      active = gang.active == 1,
      rankLabels = gang.rank_labels,
      underbossPerms = gang.underboss_perms,
      memberCount = gang.memberCount
    },
    rank = member.rank,
    isLeader = isLeader,
    isUnderboss = isUnderboss,
    permissions = perms,
    members = memberPayload(gang)
  }
  syncPlayerGang(src)
  return result
end)

RegisterNetEvent('exec:gang:leaderTransferDecision', function(payload)
  local src = source
  local gangId = payload and payload.gangId
  local accept = payload and payload.accept
  if not gangId then return end
  local gang = gangs[gangId]
  if not gang then return end
  local citizenId = resolveCitizenId(src)
  if not citizenId then return end
  local member = gang.members[citizenId]
  if not member or not member.pendingLeaderTransfer then return end

  member.pendingLeaderTransfer = nil

  if accept then
    if member.rank ~= 'underboss' then
      if canPromoteToUnderboss(gang) then
        setMemberRank(gang, member, 'underboss')
        notify(src, ('You remain in %s as an Underboss.'):format(gang.name), 'success')
      else
        notify(src, ('Underboss slots are full. You remain in %s.'):format(gang.name), 'inform')
      end
    else
      notify(src, ('You remain in %s as an Underboss.'):format(gang.name), 'success')
    end
  else
    removeMember(gang, citizenId)
    notify(src, ('You have left %s.'):format(gang.name), 'inform')
  end

  broadcastGang(gang)
  syncPlayerGang(src)
end)

RegisterNetEvent('exec:gang:respondInvite', function(payload)
  local src = source
  local gangId = payload and payload.gangId
  local accept = payload and payload.accept
  local citizenId, license = resolvePlayerIdentity(src)
  if not citizenId then return end
  local invite = pendingInvites[citizenId]
  if not invite or (gangId and invite.gangId ~= gangId) then
    if accept then
      notify(src, 'This invite is no longer valid.', 'error')
    end
    return
  end

  pendingInvites[citizenId] = nil

  if invite.expiresAt and invite.expiresAt < os.time() then
    notify(src, 'This invite has expired.', 'error')
    local inviterSrc = onlineSourceForCitizen(invite.invitedByCitizen)
    if inviterSrc then
      notify(inviterSrc, ('Invite for %s expired.'):format(GetPlayerName(src) or citizenId), 'inform')
    end
    return
  end

  local gang = gangs[invite.gangId]
  if not gang then
    notify(src, 'That gang no longer exists.', 'error')
    return
  end

  if not accept then
    notify(src, ('You declined the invite to %s.'):format(gang.name), 'inform')
    local inviterSrc = onlineSourceForCitizen(invite.invitedByCitizen)
    if inviterSrc then
      notify(inviterSrc, ('%s declined your invite.'):format(GetPlayerName(src) or citizenId), 'inform')
    end
    return
  end

  if memberIndex[citizenId] then
    notify(src, 'You are already in a gang.', 'error')
    return
  end

  if gang.memberCount >= maxMembers then
    notify(src, 'Gang is full.', 'error')
    local inviterSrc = onlineSourceForCitizen(invite.invitedByCitizen)
    if inviterSrc then
      notify(inviterSrc, ('Invite failed: %s joined another gang or the gang is full.'):format(GetPlayerName(src) or citizenId), 'error')
    end
    return
  end

  local ok, err = addMember(gang, citizenId, invite.inviteeLicense or license, GetPlayerName(src), 'footsoldier')
  if not ok then
    notify(src, err or 'Failed to join gang.', 'error')
    return
  end

  notify(src, ('You joined %s.'):format(gang.name), 'success')
  local inviterSrc = onlineSourceForCitizen(invite.invitedByCitizen)
  if inviterSrc then
    notify(inviterSrc, ('%s accepted your invite.'):format(GetPlayerName(src) or citizenId), 'success')
  end

  broadcastGang(gang)
  syncPlayerGang(src)
end)

local function promoteMember(gang, member)
  if member.rank == 'footsoldier' then
    setMemberRank(gang, member, 'hitman')
    return true
  elseif member.rank == 'hitman' then
    if not canPromoteToUnderboss(gang) then
      return false, 'Underboss limit reached.'
    end
    setMemberRank(gang, member, 'underboss')
    return true
  elseif member.rank == 'underboss' then
    return false, 'Cannot promote further.'
  elseif member.rank == 'boss' then
    return false, 'Leader rank cannot be promoted.'
  end
  return false, 'Invalid rank.'
end

local function demoteMember(gang, member)
  if member.rank == 'underboss' then
    setMemberRank(gang, member, 'hitman')
    return true
  elseif member.rank == 'hitman' then
    setMemberRank(gang, member, 'footsoldier')
    return true
  elseif member.rank == 'footsoldier' then
    return false, 'Cannot demote further.'
  elseif member.rank == 'boss' then
    return false, 'Leader cannot be demoted.'
  end
  return false, 'Invalid rank.'
end

lib.callback.register('exec:gang:memberAction', function(src, payload)
  local gang, actor = resolveMemberBySource(src)
  if not gang then return { ok=false, error='You are not part of a gang.' } end
  local citizenId = resolveCitizenId(src)
  local perms
  if gang.leader_citizenid == citizenId then
    perms = { manageMembers = true }
  elseif actor.rank == 'underboss' then
    perms = gang.underboss_perms or {}
  else
    return { ok=false, error='Permission denied.' }
  end
  if not perms.manageMembers then
    return { ok=false, error='Permission denied.' }
  end
  local targetId = payload and (payload.citizenid or payload.license)
  if not targetId then return { ok=false, error='Invalid member.' } end
  local target = gang.members[targetId]
  if not target then return { ok=false, error='Member not found.' } end
  if target.citizenid == gang.leader_citizenid then
    return { ok=false, error='Cannot modify the leader.' }
  end
  local action = payload.action
  if action == 'promote' then
    local ok, err = promoteMember(gang, target)
    if not ok then return { ok=false, error=err } end
  elseif action == 'demote' then
    local ok, err = demoteMember(gang, target)
    if not ok then return { ok=false, error=err } end
  elseif action == 'remove' then
    removeMember(gang, target.citizenid)
  else
    return { ok=false, error='Unknown action.' }
  end
  broadcastGang(gang)
  local tgtSrc = onlineSourceForCitizen(target.citizenid)
  if tgtSrc then syncPlayerGang(tgtSrc) end
  return { ok=true }
end)

lib.callback.register('exec:gang:invite', function(src, payload)
  local gang, member = resolveMemberBySource(src)
  if not gang then return { ok=false, error='You are not part of a gang.' } end
  local citizenId, _ = resolvePlayerIdentity(src)
  if not citizenId then return { ok=false, error='Unable to resolve your identity.' } end
  local isLeader = gang.leader_citizenid == citizenId
  local isUnderboss = member.rank == 'underboss'
  if not isLeader and not isUnderboss then
    return { ok=false, error='Permission denied.' }
  end

  local target = tonumber(payload and payload.serverId)
  if not target or not GetPlayerName(target) then
    return { ok=false, error='Player must be online.' }
  end
  if target == src then
    return { ok=false, error='You cannot invite yourself.' }
  end

  local targetCitizen, targetLicense = resolvePlayerIdentity(target)
  if not targetCitizen then
    return { ok=false, error='Unable to resolve player identity.' }
  end
  if memberIndex[targetCitizen] then
    return { ok=false, error='Player is already in a gang.' }
  end
  if gang.memberCount >= maxMembers then
    return { ok=false, error='Gang member limit reached.' }
  end

  clearInviteForCitizen(targetCitizen)
  pendingInvites[targetCitizen] = {
    gangId = gang.id,
    gangName = gang.name,
    inviteeLicense = targetLicense or '',
    invitedByCitizen = citizenId,
    invitedByName = GetPlayerName(src) or (member.member_name ~= '' and member.member_name or citizenId),
    expiresAt = inviteExpirySeconds > 0 and (os.time() + inviteExpirySeconds) or nil
  }

  TriggerClientEvent('exec:gang:invitePrompt', target, {
    gangId = gang.id,
    gangName = gang.name,
    invitedBy = GetPlayerName(src) or 'Gang Member',
    expireSeconds = inviteExpirySeconds > 0 and inviteExpirySeconds or nil
  })

  notify(src, ('Invite sent to %s.'):format(GetPlayerName(target) or targetCitizen), 'inform')
  return { ok=true }
end)

lib.callback.register('exec:gang:dissolve', function(src)
  local gang, member = resolveMemberBySource(src)
  if not gang then return { ok=false, error='Not part of a gang.' } end
  local citizenId = resolveCitizenId(src)
  local perms
  if gang.leader_citizenid == citizenId then
    perms = { dissolve = true }
  elseif member.rank == 'underboss' then
    perms = gang.underboss_perms or {}
  else
    return { ok=false, error='Permission denied.' }
  end
  if not perms.dissolve then
    return { ok=false, error='Permission denied.' }
  end
  DB.exec('DELETE FROM exec_gangs WHERE id = ?', { gang.id })
  clearInvitesForGang(gang.id, ('Invite to %s is no longer available.'):format(gang.name or 'a gang'))
  gangs[gang.id] = nil
  loadGangs()
  for _, sid in ipairs(GetPlayers()) do
    syncPlayerGang(tonumber(sid))
  end
  return { ok=true }
end)

RegisterNetEvent('exec_multichar:clearActiveCharacter', function()
  TriggerClientEvent('exec:gang:sync', source, nil)
end)

RegisterNetEvent('exec:gang:requestSync', function()
  syncPlayerGang(source)
end)

return GangService



