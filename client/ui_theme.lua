ExecUI = ExecUI or {}
local NotifyBridge = require 'bridge.notify'

ExecUI.colors = {
  primary = '#39FF14',
  primarySoft = '#2EE60F',
  primaryGlow = '#66FF33',
  background = '#0E0E10',
  secondary = '#141517',
  panel = '#1A1B1E',
  text = '#FFFFFF',
  secondaryText = '#A8A8A8',
  mutedText = '#6B6B6B',
  disabledText = '#4A4A4A',
  hover = '#52FF2F',
  active = '#2BFF00',
  border = '#2A2C30',
  divider = '#232428',
  success = '#39FF14',
  error = '#FF3B3B',
  warning = '#FFB020',
  info = '#3FA9FF',
  panelGlass = 'rgba(20, 21, 23, 0.85)',
  darkOverlay = 'rgba(0, 0, 0, 0.6)',
  greenGlowSoft = 'rgba(57, 255, 20, 0.15)',
  greenGlowStrong = 'rgba(57, 255, 20, 0.35)',
}

ExecUI.iconColors = {
  default = ExecUI.colors.primary,
  success = ExecUI.colors.success,
  error = ExecUI.colors.error,
  warning = ExecUI.colors.warning,
  info = ExecUI.colors.info,
  destructive = ExecUI.colors.error,
  muted = ExecUI.colors.secondaryText,
}

ExecUI.notifyPresets = {
  success = { icon = 'check-circle', iconColor = ExecUI.colors.success, type = 'success' },
  error = { icon = 'times-circle', iconColor = ExecUI.colors.error, type = 'error' },
  warning = { icon = 'exclamation-triangle', iconColor = ExecUI.colors.warning, type = 'warning' },
  info = { icon = 'info-circle', iconColor = ExecUI.colors.primary, type = 'info' },
  inform = { icon = 'info-circle', iconColor = ExecUI.colors.primary, type = 'info' },
}

local destructiveWords = {
  'delete', 'remove', 'dissolve', 'kick', 'clear', 'cancel', 'leave', 'disable'
}

local defaultIcons = {
  create = 'plus',
  save = 'save',
  saved = 'save',
  update = 'sync',
  rename = 'pen',
  change = 'pen',
  preview = 'eye',
  attachments = 'list',
  attachment = 'list',
  weapons = 'crosshairs',
  weapon = 'crosshairs',
  loadout = 'crosshairs',
  session = 'users',
  sessions = 'users',
  location = 'map-marker-alt',
  locations = 'map-marker-alt',
  playground = 'map',
  invite = 'user-plus',
  gang = 'users',
  gangs = 'users',
  member = 'user',
  members = 'users',
  leaderboard = 'star',
  appearance = 'user',
  details = 'info-circle',
  manage = 'cog',
  host = 'crown',
  join = 'sign-in-alt',
  select = 'check',
  selected = 'check',
  equip = 'check',
  enabled = 'check',
  disabled = 'ban',
  back = 'arrow-left',
}

local iconAliases = {
  ['fast-forward'] = 'forward-fast',
  layers = 'layer-group',
  ['user-search'] = 'user-plus',
  ['user-x'] = 'user-xmark',
  ['log-out'] = 'right-from-bracket',
}

local function copy(data)
  if type(data) ~= 'table' then return data end
  local out = {}
  for k, v in pairs(data) do
    out[k] = v
  end
  return out
end

local function lower(value)
  return tostring(value or ''):lower()
end

function ExecUI.isDestructive(text)
  local haystack = lower(text)
  for _, word in ipairs(destructiveWords) do
    if haystack:find(word, 1, true) then
      return true
    end
  end
  return false
end

function ExecUI.inferIcon(text, fallback)
  local haystack = lower(text)
  for key, icon in pairs(defaultIcons) do
    if haystack:find(key, 1, true) then
      return icon
    end
  end
  return fallback
end

function ExecUI.notify(data)
  if type(data) ~= 'table' then return end

  local payload = copy(data)
  local preset = ExecUI.notifyPresets[payload.type or 'inform'] or ExecUI.notifyPresets.info
  payload.type = preset.type
  payload.duration = payload.duration or 4500
  payload.icon = payload.icon or preset.icon
  payload.iconColor = payload.iconColor or preset.iconColor
  payload.alignIcon = payload.alignIcon or 'center'
  payload.style = payload.style or {
    backgroundColor = ExecUI.colors.panel,
    color = ExecUI.colors.text,
    border = ('1px solid %s'):format(ExecUI.colors.border),
    borderRadius = '8px',
    boxShadow = ('0 10px 28px %s'):format(ExecUI.colors.darkOverlay),
  }

  return NotifyBridge.Send(payload)
end

function ExecUI.success(title, description, options)
  local payload = copy(options or {})
  payload.title = title
  payload.description = description
  payload.type = 'success'
  return ExecUI.notify(payload)
end

function ExecUI.error(title, description, options)
  local payload = copy(options or {})
  payload.title = title
  payload.description = description
  payload.type = 'error'
  return ExecUI.notify(payload)
end

function ExecUI.info(title, description, options)
  local payload = copy(options or {})
  payload.title = title
  payload.description = description
  payload.type = 'inform'
  return ExecUI.notify(payload)
end

function ExecUI.warning(title, description, options)
  local payload = copy(options or {})
  payload.title = title
  payload.description = description
  payload.type = 'warning'
  return ExecUI.notify(payload)
end

function ExecUI.styleOption(option)
  if type(option) ~= 'table' then return option end

  local hadIcon = option.icon ~= nil
  option.icon = option.icon or ExecUI.inferIcon(option.title or option.label)
  option.icon = iconAliases[option.icon] or option.icon

  if option.arrow == nil and (option.menu or option.options) then
    option.arrow = true
  end

  if type(option.metadata) == 'table' then
    for _, entry in ipairs(option.metadata) do
      if type(entry) == 'table' then
        entry.color = entry.color or ExecUI.colors.secondaryText
      end
    end
  end

  if option.icon == nil then
    return option
  end

  if ExecUI.isDestructive(option.title or option.label) then
    option.iconColor = option.iconColor or ExecUI.iconColors.destructive
  elseif option.disabled then
    option.iconColor = option.iconColor or ExecUI.iconColors.muted
  elseif hadIcon then
    option.iconColor = option.iconColor or ExecUI.iconColors.default
  else
    option.iconColor = option.iconColor or ExecUI.iconColors.default
  end

  return option
end

function ExecUI.styleOptions(options)
  if type(options) ~= 'table' then return options end
  for _, option in ipairs(options) do
    ExecUI.styleOption(option)
  end
  return options
end

function ExecUI.context(data)
  if type(data) ~= 'table' then return data end
  data.options = ExecUI.styleOptions(data.options)
  return data
end

function ExecUI.dialogOptions(options)
  options = options or {}
  options.centered = options.centered ~= false
  options.size = options.size or 'md'
  return options
end

if lib then
  ExecUI._notify = lib.notify
  ExecUI._registerContext = lib.registerContext
  ExecUI._inputDialog = lib.inputDialog
  ExecUI._alertDialog = lib.alertDialog
  ExecUI._progressBar = lib.progressBar
  ExecUI._progressCircle = lib.progressCircle

  lib.notify = function(data)
    return ExecUI.notify(data)
  end

  lib.registerContext = function(data)
    return ExecUI._registerContext(ExecUI.context(data))
  end

  lib.inputDialog = function(heading, rows, options)
    return ExecUI._inputDialog(heading, rows, ExecUI.dialogOptions(options))
  end

  lib.alertDialog = function(data, timeout)
    if type(data) == 'table' then
      data.centered = data.centered ~= false
      data.size = data.size or 'md'
      data.labels = data.labels or {}
      data.labels.confirm = data.labels.confirm or data.confirm
      if ExecUI.isDestructive(data.header or data.content) then
        data.confirm = data.confirm or 'Confirm'
      end
    end
    return ExecUI._alertDialog(data, timeout)
  end

  if ExecUI._progressBar then
    lib.progressBar = function(data)
      if type(data) == 'table' then
        data.color = data.color or ExecUI.colors.primary
      end
      return ExecUI._progressBar(data)
    end
  end

  if ExecUI._progressCircle then
    lib.progressCircle = function(data)
      if type(data) == 'table' then
        data.color = data.color or ExecUI.colors.primary
      end
      return ExecUI._progressCircle(data)
    end
  end
end
