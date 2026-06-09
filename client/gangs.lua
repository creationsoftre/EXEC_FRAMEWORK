local gcfg = require 'config.gangs'

local myGang = nil
local gangSyncRequested = false

local function requestGangSync(force)
  if gangSyncRequested and not force then return end
  gangSyncRequested = true
  TriggerServerEvent('exec:gang:requestSync')
end

local function sync(data)
  myGang = data
  gangSyncRequested = false
  if not data and lib and lib.hideContext then
    lib.hideContext()
  end
end

RegisterNetEvent('exec:gang:sync', sync)

local function notifyError(msg)
  lib.notify({ title = 'Gangs', description = msg, type = 'error' })
end

local function notifySuccess(msg)
  lib.notify({ title = 'Gangs', description = msg, type = 'success' })
end

local function ensureAdminData(cb)
  lib.callback('exec:gang:getAdminData', false, function(resp)
    if not resp or resp.ok == false then
      notifyError(resp and resp.error or 'Unable to load gang data.')
      return
    end
    cb(resp)
  end)
end

local function openRankRenameDialog(initial)
  local result = lib.inputDialog('Rename Ranks', {
    { type = 'input', label = 'Boss', default = initial.boss or '' },
    { type = 'input', label = 'Underboss', default = initial.underboss or '' },
    { type = 'input', label = 'Hitman', default = initial.hitman or '' },
    { type = 'input', label = 'Foot Soldier', default = initial.footsoldier or '' }
  })
  if not result then return nil end
  return {
    boss = result[1] or initial.boss,
    underboss = result[2] or initial.underboss,
    hitman = result[3] or initial.hitman,
    footsoldier = result[4] or initial.footsoldier
  }
end

local function openAdminGangMenu(gang, defaults)
  local options = {}

  options[#options+1] = {
    title = 'Delete Gang',
    icon = 'trash',
    description = 'Remove this gang permanently.',
    onSelect = function()
      if lib.alertDialog({ header = 'Delete Gang', content = 'Delete ' .. gang.name .. '?', cancel = true, centered = true }) ~= 'confirm' then
        return
      end
      lib.callback('exec:gang:delete', false, function(resp)
        if resp and resp.ok then
          notifySuccess('Gang deleted.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to delete gang.')
        end
      end, { gangId = gang.id })
    end
  }

  options[#options+1] = {
    title = gang.active and 'Disable Gang' or 'Enable Gang',
    icon = gang.active and 'pause-circle' or 'play-circle',
    onSelect = function()
      lib.callback('exec:gang:setActive', false, function(resp)
        if resp and resp.ok then
          notifySuccess(gang.active and 'Gang disabled.' or 'Gang enabled.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to update gang.')
        end
      end, { gangId = gang.id, active = not gang.active })
    end
  }

  options[#options+1] = {
    title = 'Change Rank Names',
    icon = 'pen',
    onSelect = function()
      local newRanks = openRankRenameDialog(gang.rankLabels or defaults.ranks)
      if not newRanks then return end
      lib.callback('exec:gang:updateRanks', false, function(resp)
        if resp and resp.ok then
          notifySuccess('Rank names updated.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to update ranks.')
        end
      end, { gangId = gang.id, ranks = newRanks })
    end
  }

  options[#options+1] = {
    title = 'Change Leader',
    icon = 'crown',
    description = 'Set a new leader by server ID (must be online).',
    onSelect = function()
      local input = lib.inputDialog('Change Leader', {
        { type = 'number', label = 'Server ID', min = 1 }
      })
      if not input then return end
      lib.callback('exec:gang:setLeader', false, function(resp)
        if resp and resp.ok then
          notifySuccess('Leader updated.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to change leader.')
        end
      end, { gangId = gang.id, leader = input[1] })
    end
  }

  options[#options+1] = {
    title = 'Add Strikes',
    icon = 'exclamation-triangle',
    onSelect = function()
      local input = lib.inputDialog('Add Strikes', {
        { type = 'number', label = 'Amount', min = 1, default = 1 }
      })
      if not input then return end
      lib.callback('exec:gang:strike', false, function(resp)
        if resp and resp.ok then
          notifySuccess('Strikes updated.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to update strikes.')
        end
      end, { gangId = gang.id, amount = input[1], remove = false })
    end
  }

  options[#options+1] = {
    title = 'Remove Strikes',
    icon = 'exclamation-triangle',
    onSelect = function()
      local input = lib.inputDialog('Remove Strikes', {
        { type = 'number', label = 'Amount', min = 1, default = 1 }
      })
      if not input then return end
      lib.callback('exec:gang:strike', false, function(resp)
        if resp and resp.ok then
          notifySuccess('Strikes updated.')
          ensureAdminData(function(data) openAdminMenu(data) end)
        else
          notifyError(resp and resp.error or 'Failed to update strikes.')
        end
      end, { gangId = gang.id, amount = input[1], remove = true })
    end
  }

  lib.registerContext({ id = 'exec_gangs_admin_manage_' .. gang.id, title = gang.name .. ' (Admin)', options = options })
  lib.showContext('exec_gangs_admin_manage_' .. gang.id)
end

function openAdminMenu(data)
  local options = {
    {
      title = 'Create Gang',
      icon = 'plus',
      onSelect = function()
        local input = lib.inputDialog('Create Gang', {
          { type = 'input', label = 'Gang Name' },
          { type = 'number', label = 'Leader Server ID', min = 1 }
        })
        if not input then return end
        lib.callback('exec:gang:create', false, function(resp)
          if resp and resp.ok then
            notifySuccess('Gang created.')
            ensureAdminData(function(newData) openAdminMenu(newData) end)
          else
            notifyError(resp and resp.error or 'Failed to create gang.')
          end
        end, { name = input[1], leader = input[2] })
      end
    }
  }

  local seen = {}
  for _, gang in ipairs(data.gangs or {}) do
    if gang.id and not seen[gang.id] then
      seen[gang.id] = true
      options[#options+1] = {
        title = gang.name,
        description = string.format('Members: %d | Strikes: %d | Active: %s', gang.memberCount or 0, gang.strikes or 0, gang.active and 'Yes' or 'No'),
        icon = gang.active and 'users' or 'user-slash',
        onSelect = function()
          openAdminGangMenu(gang, data.defaults or { ranks = {} })
        end
      }
    end
  end

  lib.registerContext({ id = 'exec_gangs_admin_root', title = 'Gang Administration', options = options })
  lib.showContext('exec_gangs_admin_root')
end

local function startAdminMenu()
  ensureAdminData(function(data)
    openAdminMenu(data)
  end)
end

local function openMemberActions(member)
  local actions = {
    {
      title = 'Promote', icon = 'arrow-up', onSelect = function()
        lib.callback('exec:gang:memberAction', false, function(resp)
          if resp and resp.ok then
            notifySuccess('Member promoted.')
          else
            notifyError(resp and resp.error or 'Failed to promote member.')
          end
        end, { citizenid = member.citizenid, license = member.license, action = 'promote' })
      end
    },
    {
      title = 'Demote', icon = 'arrow-down', onSelect = function()
        lib.callback('exec:gang:memberAction', false, function(resp)
          if resp and resp.ok then
            notifySuccess('Member demoted.')
          else
            notifyError(resp and resp.error or 'Failed to demote member.')
          end
        end, { citizenid = member.citizenid, license = member.license, action = 'demote' })
      end
    },
    {
      title = 'Remove', icon = 'user-xmark', onSelect = function()
        if lib.alertDialog({ header = 'Remove Member', content = 'Remove ' .. member.name .. ' from the gang?', cancel = true, centered = true }) ~= 'confirm' then
          return
        end
        lib.callback('exec:gang:memberAction', false, function(resp)
          if resp and resp.ok then
            notifySuccess('Member removed.')
          else
            notifyError(resp and resp.error or 'Failed to remove member.')
          end
        end, { citizenid = member.citizenid, license = member.license, action = 'remove' })
      end
    }
  }
  lib.registerContext({ id = 'exec_gang_member_actions', title = member.name, options = actions })
  lib.showContext('exec_gang_member_actions')
end

local function startLeaderMenu()
  lib.callback('exec:gang:getLeaderData', false, function(resp)
    if not resp or resp.ok == false then
      notifyError(resp and resp.error or 'Unable to load gang data.')
      return
    end

    local gang = resp.gang
    local perms = resp.permissions or {}
    local options = {}

    if perms.renameRanks then
      options[#options+1] = {
        title = 'Change Rank Names',
        icon = 'pen',
        onSelect = function()
          local newRanks = openRankRenameDialog(gang.rankLabels)
          if not newRanks then return end
          lib.callback('exec:gang:updateRanks', false, function(result)
            if result and result.ok then
              notifySuccess('Rank names updated.')
            else
              notifyError(result and result.error or 'Failed to update ranks.')
            end
          end, { ranks = newRanks })
        end
      }
    end

    if perms.manageMembers then
      options[#options+1] = {
        title = 'Manage Members',
        icon = 'users-gear',
        onSelect = function()
          local memberOptions = {}
          for _, member in ipairs(resp.members or {}) do
            memberOptions[#memberOptions+1] = {
              title = string.format('%s [%s]%s', member.name, member.rank:upper(), member.online and ' (Online)' or ''),
              description = string.format('Wins: %d | Losses: %d | Kills: %d | Deaths: %d', member.wins or 0, member.losses or 0, member.kills or 0, member.deaths or 0),
              onSelect = function()
                openMemberActions(member)
              end
            }
          end
          if #memberOptions == 0 then
            lib.notify({ title = 'Gangs', description = 'No members found.', type = 'inform' })
            return
          end
          lib.registerContext({ id = 'exec_gang_manage_members', title = 'Gang Members', options = memberOptions })
          lib.showContext('exec_gang_manage_members')
        end
      }
    end

    if perms.viewDetails then
      options[#options+1] = {
        title = 'Gang Details',
        icon = 'info-circle',
        onSelect = function()
          local lines = {
            'Name: ' .. gang.name,
            'Members: ' .. (gang.memberCount or 0),
            'Strikes: ' .. (gang.strikes or 0),
            'Gang Wars Won: ' .. (gang.wins or 0),
            'Gang Wars Lost: ' .. (gang.losses or 0)
          }
          lib.notify({ title = 'Gang Details', description = table.concat(lines, '\n'), type = 'inform', duration = 8000 })
        end
      }
    end

    if perms.dissolve then
      options[#options+1] = {
        title = 'Dissolve Gang',
        icon = 'skull-crossbones',
        onSelect = function()
          if lib.alertDialog({ header = 'Dissolve Gang', content = 'This will dissolve the gang. Continue?', cancel = true, centered = true }) ~= 'confirm' then
            return
          end
          lib.callback('exec:gang:dissolve', false, function(result)
            if result and result.ok then
              notifySuccess('Gang dissolved.')
            else
              notifyError(result and result.error or 'Failed to dissolve gang.')
            end
          end)
        end
      }
    end

    if resp.isLeader or resp.isUnderboss then
      options[#options+1] = {
        title = 'Invite Member',
        icon = 'user-plus',
        description = 'Invite a player to join the gang.',
        onSelect = function()
          local input = lib.inputDialog('Invite Player', {
            { type = 'number', label = 'Server ID', min = 1 }
          })
          if not input or not input[1] then return end
          lib.callback('exec:gang:invite', false, function(result)
            if result and result.ok then
              notifySuccess('Invite sent.')
            else
              notifyError(result and result.error or 'Failed to send invite.')
            end
          end, { serverId = input[1] })
        end
      }
    end

    if resp.isLeader then
      options[#options+1] = {
        title = 'Transfer Leadership',
        icon = 'crown',
        onSelect = function()
          local transferOptions = {}
          for _, memberData in ipairs(resp.members or {}) do
            if memberData.rank ~= 'boss' then
              transferOptions[#transferOptions+1] = {
                title = string.format('%s [%s]', memberData.name, memberData.rank:upper()),
                description = memberData.online and 'Online' or 'Offline',
                onSelect = function()
                  if lib.alertDialog({
                    header = 'Transfer Leadership',
                    content = string.format('Transfer leadership to %s?', memberData.name),
                    cancel = true,
                    centered = true
                  }) ~= 'confirm' then
                    return
                  end
                  lib.callback('exec:gang:setLeader', false, function(result)
                    if result and result.ok then
                      notifySuccess('Leadership transferred.')
                    else
                      notifyError(result and result.error or 'Failed to transfer leadership.')
                    end
                  end, { leaderCitizen = memberData.citizenid })
                end
              }
            end
          end
          if #transferOptions == 0 then
            lib.notify({ title = 'Gangs', description = 'No eligible members to transfer leadership to.', type = 'inform' })
            return
          end
          lib.registerContext({ id = 'exec_gang_transfer_leadership', title = 'Transfer Leadership', options = transferOptions })
          lib.showContext('exec_gang_transfer_leadership')
        end
      }
      options[#options+1] = {
        title = 'Set Underboss Permissions',
        icon = 'user-shield',
        onSelect = function()
          local current = gang.underbossPerms or {}
          local state = {
            renameRanks = current.renameRanks and true or false,
            manageMembers = current.manageMembers and true or false,
            viewDetails = current.viewDetails ~= false,
            dissolve = current.dissolve and true or false
          }
          local permDefs = {
            { key = 'renameRanks', label = 'Rename Rank Names' },
            { key = 'manageMembers', label = 'Manage Members' },
            { key = 'viewDetails', label = 'View Details' },
            { key = 'dissolve', label = 'Dissolve Gang' },
          }
          local menuId = 'exec_gang_underboss_perms'

          local function render()
            local opts = {}
            for _, def in ipairs(permDefs) do
              local enabled = state[def.key] == true
              opts[#opts+1] = {
                title = (enabled and '[Enabled] ' or '') .. def.label,
                description = enabled and 'Disable permission' or 'Enable permission',
                onSelect = function()
                  state[def.key] = not enabled
                  render()
                end
              }
            end
            opts[#opts+1] = {
              title = 'Save Changes',
              icon = 'save',
              onSelect = function()
                local payload = {
                  renameRanks = state.renameRanks and true or false,
                  manageMembers = state.manageMembers and true or false,
                  viewDetails = state.viewDetails ~= false,
                  dissolve = state.dissolve and true or false
                }
                lib.callback('exec:gang:underbossPerms', false, function(result)
                  if result and result.ok then
                    notifySuccess('Underboss permissions updated.')
                    startLeaderMenu()
                  else
                    notifyError(result and result.error or 'Failed to update permissions.')
                  end
                end, { perms = payload })
              end
            }
            opts[#opts+1] = {
              title = 'Cancel',
              icon = 'ban',
              onSelect = function()
                lib.showContext('exec_gang_leader_menu')
              end
            }

            lib.registerContext({ id = menuId, title = 'Underboss Permissions', options = opts })
            lib.showContext(menuId)
          end

          render()
        end
      }
    end

    lib.registerContext({ id = 'exec_gang_leader_menu', title = gang.name .. ' Gang', options = options })
    lib.showContext('exec_gang_leader_menu')
  end)
end

-- Commands and keybinds
if gcfg.admin and gcfg.admin.command then
  RegisterCommand(gcfg.admin.command, startAdminMenu, false)
  if gcfg.admin.keybind and gcfg.admin.keybind ~= false then
    RegisterKeyMapping(gcfg.admin.command, 'Open Gang Admin Menu', 'keyboard', gcfg.admin.keybind)
  end
end

if gcfg.leader and gcfg.leader.command then
  RegisterCommand(gcfg.leader.command, startLeaderMenu, false)
  if gcfg.leader.keybind and gcfg.leader.keybind ~= false then
    RegisterKeyMapping(gcfg.leader.command, 'Open Gang Menu', 'keyboard', gcfg.leader.keybind)
  end
end

AddEventHandler('onResourceStart', function(resource)
  if resource == GetCurrentResourceName() then
    CreateThread(function()
      Wait(500)
      requestGangSync(true)
    end)
  end
end)

AddEventHandler('playerSpawned', function()
  if myGang then return end
  CreateThread(function()
    Wait(750)
    requestGangSync(false)
  end)
end)

RegisterNetEvent('exec:gang:openMenu', function()
  if not myGang then
    notifyError('You are not part of a gang.')
    requestGangSync(false)
    return
  end
  startLeaderMenu()
end)

RegisterNetEvent('exec:gang:invitePrompt', function(data)
  if not data or not data.gangId then return end
  if myGang and myGang.gangId then
    notifyError('You are already in a gang.')
    TriggerServerEvent('exec:gang:respondInvite', { gangId = data.gangId, accept = false })
    return
  end
  local inviter = data.invitedBy or 'Another player'
  local gangName = data.gangName or 'a gang'
  local lines = {
    string.format('%s invited you to join %s.', inviter, gangName)
  }
  if data.expireSeconds and data.expireSeconds > 0 then
    lines[#lines+1] = string.format('Invite expires in %ds.', data.expireSeconds)
  end
  local choice = lib.alertDialog({
    header = 'Gang Invitation',
    content = table.concat(lines, '\n'),
    centered = true,
    cancel = true,
    confirm = 'Join Gang'
  })
  local accept = choice == 'confirm'
  TriggerServerEvent('exec:gang:respondInvite', { gangId = data.gangId, accept = accept })
  if accept then
    CreateThread(function()
      Wait(500)
      requestGangSync(true)
    end)
  end
end)

RegisterNetEvent('exec:gang:leaderTransferPrompt', function(data)
  if not data then return end
  local content = string.format('Leadership of %s has been transferred to %s.', data.gangName or 'your gang', data.newLeader or 'another member')
  local limit = tonumber(data.underbossLimit)
  if limit and limit <= 0 then limit = nil end
  local used = tonumber(data.underbossCount) or 0
  if data.canUnderboss then
    content = content .. '\nStay with the gang as an Underboss?'
  else
    content = content .. '\nUnderboss slots are full; staying will keep you as a senior member.'
  end
  if limit then
    content = content .. string.format('\nSlots used: %d/%d.', used, limit)
  end
  content = content .. '\n\nSelect Cancel to leave the gang.'
  local choice = lib.alertDialog({
    header = 'Leadership Transfer',
    content = content,
    centered = true,
    cancel = true,
    confirm = data.canUnderboss and 'Stay as Underboss' or 'Stay in Gang'
  })
  local accept = choice == 'confirm' or choice == nil
  TriggerServerEvent('exec:gang:leaderTransferDecision', { gangId = data.gangId, accept = accept })
end)

RegisterNetEvent('exec:character:reset', function()
  myGang = nil
  gangSyncRequested = false
end)

exports('GetGangState', function()
  return myGang
end)

exports('OpenGangMenu', function()
  if not myGang then
    notifyError('You are not part of a gang.')
    requestGangSync(false)
    return false
  end
  startLeaderMenu()
  return true
end)

