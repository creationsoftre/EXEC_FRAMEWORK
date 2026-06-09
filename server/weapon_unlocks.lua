local DB = require "server.db"
local weaponCatalog = require "shared.weapon_catalog"

local WeaponUnlocks = {}

local cache = {}
local skuIndex = {}

local function sanitizeWeaponCode(code)
  if type(code) ~= "string" then return nil end
  local up = code:upper()
  if not up:find("^WEAPON_") then
    up = "WEAPON_" .. up
  end
  return up
end

local function ensureSkuIndex()
  skuIndex = {}
  local unlocks = (weaponCatalog.addon and weaponCatalog.addon.unlocks) or {}
  for weaponCode, meta in pairs(unlocks) do
    if type(meta) == "table" and meta.tebexSku and meta.tebexSku ~= "" then
      local code = sanitizeWeaponCode(weaponCode)
      skuIndex[tostring(meta.tebexSku)] = code
    end
  end
end

ensureSkuIndex()

local function identifiersTableLicense(identifiers)
  if type(identifiers) ~= "table" then return nil end
  for _, key in ipairs({ "license", "license2" }) do
    local value = identifiers[key]
    if type(value) == "string" and value ~= "" then
      return value
    end
  end
  for _, value in pairs(identifiers) do
    if type(value) == "string" and value:find("^license[2]?:") then
      return value
    end
  end
  return nil
end

local function licenseFromSource(src)
  if not src then return nil end
  local ids = GetPlayerIdentifiers(src)
  for _, id in ipairs(ids) do
    if id:sub(1, 8) == "license:" then
      return id
    end
  end
  for _, id in ipairs(ids) do
    if id:sub(1, 9) == "license2:" then
      return id
    end
  end
  return nil
end

local function purchaseSku(purchase)
  if type(purchase) ~= "table" then return nil end
  if purchase.sku then return tostring(purchase.sku) end
  if purchase.package and purchase.package.sku then
    return tostring(purchase.package.sku)
  end
  if purchase.package_id then return tostring(purchase.package_id) end
  if purchase.product_id then return tostring(purchase.product_id) end
  if purchase.package and purchase.package.id then
    return tostring(purchase.package.id)
  end
  return nil
end

local function purchaseLicense(purchase)
  if type(purchase) ~= "table" then return nil end
  if purchase.license and purchase.license:find("^license") then
    return purchase.license
  end
  if purchase.player and purchase.player.identifiers then
    local lic = identifiersTableLicense(purchase.player.identifiers)
    if lic then return lic end
  end
  if purchase.identifiers then
    local lic = identifiersTableLicense(purchase.identifiers)
    if lic then return lic end
  end
  if purchase.player and purchase.player.id and purchase.player.id:find("^license") then
    return purchase.player.id
  end
  return nil
end

local function payloadFromCache(map)
  local payload = {}
  for code, data in pairs(map) do
    payload[code] = data.unlocked and true or false
  end
  return payload
end

function WeaponUnlocks.rebuildSkuIndex()
  ensureSkuIndex()
end

function WeaponUnlocks.licenseFromSource(src)
  return licenseFromSource(src)
end

function WeaponUnlocks.licenseFromPurchase(purchase)
  return purchaseLicense(purchase)
end

function WeaponUnlocks.skuFromPurchase(purchase)
  return purchaseSku(purchase)
end

function WeaponUnlocks.licenseFromIdentifiers(identifiers)
  return identifiersTableLicense(identifiers)
end

function WeaponUnlocks.weaponForSku(sku)
  if not sku then return nil end
  return skuIndex[tostring(sku)]
end

function WeaponUnlocks.unlocksFor(license)
  if not license then return {} end
  if cache[license] then
    return cache[license]
  end
  local rows = DB.query([[SELECT weapon_code, unlocked, tebex_sku, meta
    FROM exec_weapon_unlocks
    WHERE license = ?]], { license }) or {}
  local map = {}
  for _, row in ipairs(rows) do
    map[row.weapon_code] = {
      unlocked = row.unlocked == 1,
      tebexSku = row.tebex_sku,
      meta = row.meta and json.decode(row.meta) or nil
    }
  end
  cache[license] = map
  return map
end

function WeaponUnlocks.payloadFor(license)
  return payloadFromCache(WeaponUnlocks.unlocksFor(license))
end

function WeaponUnlocks.pushToSource(src)
  if not src then return end
  local license = licenseFromSource(src)
  if not license then return end
  TriggerClientEvent("exec:weaponUnlocks:sync", src, WeaponUnlocks.payloadFor(license))
end

function WeaponUnlocks.pushToLicense(license)
  if not license then return end
  local payload = WeaponUnlocks.payloadFor(license)
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if src and licenseFromSource(src) == license then
      TriggerClientEvent("exec:weaponUnlocks:sync", src, payload)
    end
  end
end

function WeaponUnlocks.pushToAll()
  for _, id in ipairs(GetPlayers()) do
    WeaponUnlocks.pushToSource(tonumber(id))
  end
end

function WeaponUnlocks.setLicenseWeapon(license, weaponCode, unlocked, opts)
  weaponCode = sanitizeWeaponCode(weaponCode)
  if not license or not weaponCode then
    return false, "invalid_arguments"
  end
  local meta = opts and opts.meta or nil
  local metaJson = meta and json.encode(meta) or nil
  DB.exec([[INSERT INTO exec_weapon_unlocks (license, weapon_code, unlocked, tebex_sku, meta)
    VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE unlocked = VALUES(unlocked), tebex_sku = VALUES(tebex_sku),
      meta = VALUES(meta), updated_at = CURRENT_TIMESTAMP]], {
        license,
        weaponCode,
        unlocked and 1 or 0,
        opts and opts.tebexSku or nil,
        metaJson
      })
  cache[license] = cache[license] or {}
  cache[license][weaponCode] = {
    unlocked = unlocked and true or false,
    tebexSku = opts and opts.tebexSku or nil,
    meta = meta
  }
  WeaponUnlocks.pushToLicense(license)
  return true
end

function WeaponUnlocks.unlockBySku(license, sku, meta)
  if not license or not sku then
    return false, "invalid_purchase"
  end
  local weaponCode = WeaponUnlocks.weaponForSku(sku)
  if not weaponCode then
    return false, "unknown_sku"
  end
  return WeaponUnlocks.setLicenseWeapon(license, weaponCode, true, {
    tebexSku = tostring(sku),
    meta = meta
  })
end

return WeaponUnlocks
