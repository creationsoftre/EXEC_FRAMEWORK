local integrationConfig = require 'config.integrations'

local IdentityBridge = {}
local identityConfig = (integrationConfig and integrationConfig.identity) or {}

local function isValidText(value)
  return type(value) == 'string' and value ~= ''
end

local function resourceIsStarted(resourceName)
  return resourceName and GetResourceState(resourceName) == 'started'
end

local function findIdentifier(playerSource, prefix)
  if type(playerSource) ~= 'number' or playerSource <= 0 then return nil end
  local identifiers = GetPlayerIdentifiers(playerSource)
  if type(identifiers) ~= 'table' then return nil end
  local expectedPrefix = prefix .. ':'

  for _, identifier in ipairs(identifiers) do
    if type(identifier) == 'string' and identifier:sub(1, #expectedPrefix) == expectedPrefix then
      return identifier
    end
  end

  return nil
end

local function getStateValue(playerSource, stateKey)
  local player = Player and Player(playerSource)
  local stateBag = player and player.state
  local value = stateBag and stateBag[stateKey]
  return isValidText(value) and value or nil
end

local function getCitizenIdFromState(playerSource)
  local stateKeys = identityConfig.citizenStateKeys or { 'execCitizenId', 'citizenid', 'citizenId' }
  for _, stateKey in ipairs(stateKeys) do
    local citizenId = getStateValue(playerSource, stateKey)
    if citizenId then return citizenId end
  end
  return nil
end

-- CAPO: Character identity is resolved here so multichar can be replaced without rewriting gameplay systems.
local function getCitizenIdFromMultichar(playerSource)
  local multicharResource = identityConfig.resource or 'exec_multichar'
  if not resourceIsStarted(multicharResource) then return nil end

  local success, citizenId = pcall(function()
    local resourceExports = exports[multicharResource]
    local getActiveCitizenId = resourceExports and resourceExports.GetActiveCitizenId
    if type(getActiveCitizenId) ~= 'function' then return nil end
    return getActiveCitizenId(playerSource)
  end)

  return success and isValidText(citizenId) and citizenId or nil
end

function IdentityBridge.GetCitizenId(playerSource)
  if identityConfig.provider == 'none' then return nil end

  local citizenId = getCitizenIdFromState(playerSource)
  if citizenId then return citizenId end

  if identityConfig.provider == 'exec_multichar' or identityConfig.provider == nil then
    citizenId = getCitizenIdFromMultichar(playerSource)
    if citizenId then return citizenId end
  end

  citizenId = findIdentifier(playerSource, 'citizenid') or findIdentifier(playerSource, 'char')
  if citizenId then
    local separator = citizenId:find(':', 1, true)
    return separator and citizenId:sub(separator + 1) or citizenId
  end

  return nil
end

function IdentityBridge.GetLicense(playerSource)
  local playerToken = GetPlayerToken and GetPlayerToken(playerSource, 0) or nil
  return findIdentifier(playerSource, 'license')
      or findIdentifier(playerSource, 'license2')
      or findIdentifier(playerSource, 'fivem')
      or findIdentifier(playerSource, 'steam')
      or (playerToken and ('token:' .. playerToken))
      or ((type(playerSource) == 'number' and playerSource > 0) and ('net:' .. tostring(playerSource)) or nil)
end

function IdentityBridge.Resolve(playerSource)
  local citizenId = IdentityBridge.GetCitizenId(playerSource)
  local license = IdentityBridge.GetLicense(playerSource)
  return {
    source = playerSource,
    citizenId = citizenId,
    license = license,
    identifier = citizenId or license,
  }
end

function IdentityBridge.EnsureIdentifier(playerSource)
  local identity = IdentityBridge.Resolve(playerSource)
  return identity.identifier, identity.citizenId, identity.license
end

IdentityBridge.getCitizenId = IdentityBridge.GetCitizenId
IdentityBridge.getLicense = IdentityBridge.GetLicense
IdentityBridge.resolve = IdentityBridge.Resolve
IdentityBridge.ensureIdentifier = IdentityBridge.EnsureIdentifier

function IdentityBridge.ReleaseSelectorBucket(playerSource, targetBucket)
  if identityConfig.provider == 'none' then
    SetPlayerRoutingBucket(playerSource, tonumber(targetBucket) or 0)
    return false
  end

  local multicharResource = identityConfig.resource or 'exec_multichar'
  if resourceIsStarted(multicharResource) then
    local success = pcall(function()
      local releaseSelectorBucket = exports[multicharResource] and exports[multicharResource].ReleaseSelectorBucket
      if type(releaseSelectorBucket) == 'function' then
        releaseSelectorBucket(playerSource, targetBucket or 0)
      else
        SetPlayerRoutingBucket(playerSource, tonumber(targetBucket) or 0)
      end
    end)
    if success then return true end
  end

  SetPlayerRoutingBucket(playerSource, tonumber(targetBucket) or 0)
  return false
end

return IdentityBridge
