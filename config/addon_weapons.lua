-- Central add-on weapon configuration.
-- Add custom weapons in ADDON_WEAPONS only; categories, labels, attachments,
-- and unlock metadata are generated from that list below.

local function makeSeries(labelPrefix, componentPrefix, first, last, slot, defaultIndex, modelPrefix, attachBone)
  local items = {}
  for i = first, last do
    items[#items + 1] = {
      label = ("%s %02d"):format(labelPrefix, i),
      component = ("%s%02d"):format(componentPrefix, i),
      slot = slot,
      defaultOn = defaultIndex == i,
      previewModel = modelPrefix and ("%s%d"):format(modelPrefix, i) or nil,
      previewAttachBone = attachBone
    }
  end
  return items
end

local function makeNamedSeries(labelPrefix, componentPrefix, indexes, slot, defaultIndex, modelPrefix, attachBone)
  local items = {}
  for _, idx in ipairs(indexes or {}) do
    items[#items + 1] = {
      label = ("%s %02d"):format(labelPrefix, idx),
      component = ("%s%02d"):format(componentPrefix, idx),
      slot = slot,
      defaultOn = defaultIndex == idx,
      previewModel = modelPrefix and ("%s%d"):format(modelPrefix, idx) or nil,
      previewAttachBone = attachBone
    }
  end
  return items
end

local function appendAll(target, source)
  for _, item in ipairs(source or {}) do
    target[#target + 1] = item
  end
  return target
end

local function x17Attachments(slidePrefix, slideLabel)
  local items = {}
  appendAll(items, makeSeries('Magazine', 'COMPONENT_MARKOMODS_X17M_MAGAZINE_', 1, 7, 'mag', 1, 'markomods-x17m-magazine', 'WAPClip'))
  appendAll(items, makeSeries('Frame', 'COMPONENT_MARKOMODS_X17M_FRAME_', 1, 10, 'frame', 1, 'markomods-x17m-frame', 'WAPStock'))
  appendAll(items, makeSeries('Barrel', 'COMPONENT_MARKOMODS_X17M_BARREL_', 1, 9, 'barrel', 1, 'markomods-x17m-barrel', 'WAPBarrel'))
  appendAll(items, makeSeries(slideLabel, slidePrefix, 1, 5, 'slide', 1, slidePrefix:find('SWITCH') and 'markomods-x17m-switchslide' or 'markomods-x17m-slide', 'WAPScop'))
  appendAll(items, makeSeries('Cover', 'COMPONENT_MARKOMODS_X17M_COVER_', 1, 4, 'cover', nil, 'markomods-x17m-cover', 'WAPScop_2'))
  appendAll(items, makeSeries('Scope', 'COMPONENT_MARKOMODS_X17M_SCOPE_', 1, 4, 'optic', nil, 'markomods-x17m-scope', 'WAPScop_2'))
  appendAll(items, makeSeries('Flashlight', 'COMPONENT_MARKOMODS_X17M_FLASHLIGHT_', 1, 6, 'light', nil, 'markomods-x17m-flashlight', 'WAPFlshLasr'))
  appendAll(items, makeSeries('Muzzle', 'COMPONENT_MARKOMODS_X17M_MUZZLE_', 1, 2, 'muzzle', nil, 'markomods-x17m-muzzle', 'WAPSupp'))
  appendAll(items, makeSeries('Suppressor', 'COMPONENT_MARKOMODS_X17M_SUPPRESSOR_', 1, 4, 'muzzle', nil, 'markomods-x17m-suppressor', 'WAPSupp'))
  appendAll(items, makeNamedSeries('Shared Suppressor', 'COMPONENT_MARKOMODS_SHARED_SUPP_', { 3, 4 }, 'muzzle', nil, 'markomods-shared-supp', 'WAPSupp'))
  return items
end

local function x19Attachments()
  local items = {}
  appendAll(items, makeSeries('Magazine', 'COMPONENT_MARKOMODSX19_CLIP_', 1, 3, 'mag', 1, 'markomods-x19-mag', 'WAPClip'))
  appendAll(items, makeSeries('Barrel', 'COMPONENT_MARKOMODSX19_BARREL_', 1, 4, 'barrel', 1, 'markomods-x19-barrel', 'WAPBarrel'))
  appendAll(items, makeSeries('Slide', 'COMPONENT_MARKOMODSX19_SLIDE_', 1, 10, 'slide', 1, 'markomods-x19-slide', 'WAPScop_2'))
  appendAll(items, makeNamedSeries('Shared Pistol Flashlight', 'COMPONENT_MARKOMODS_SHARED_PFLASH_', { 1, 2, 3, 4, 6, 7, 8 }, 'light', nil, 'markomods-shared-pflash', 'WAPFlshLasr'))
  appendAll(items, makeSeries('Muzzle', 'COMPONENT_MARKOMODSX19_MUZZLE_', 1, 1, 'muzzle', nil, 'markomods-x19-muzzle', 'WAPSupp'))
  appendAll(items, makeNamedSeries('Shared Suppressor', 'COMPONENT_MARKOMODS_SHARED_SUPP_', { 2, 3, 4, 5 }, 'muzzle', nil, 'markomods-shared-supp', 'WAPSupp'))
  return items
end

local CATEGORY_DEFS = {
  addon_pistols = {
    label = 'Add-on Pistols',
    ammo = 200,
    inherit = 'pistols',
    group = 'addon',
    groupLabel = 'Add-on Weapons',
    groupDescription = 'Custom sidearms unlocked via events or Tebex purchases.',
  },

  addon_machine_pistols = {
    label = 'Add-on Machine Pistols',
    ammo = 200,
    inherit = 'smgs',
    group = 'addon',
    groupLabel = 'Add-on Weapons',
    groupDescription = 'Custom automatic sidearms and close-range weapons.',
  },
}

local ADDON_WEAPONS = {
  {
    code = 'WEAPON_X17M',
    label = 'X17 Modular',
    category = 'addon_pistols',
    attachments = x17Attachments('COMPONENT_MARKOMODS_X17M_SLIDE_', 'Slide'),
    unlock = {
      tebexSku = '7439490',
      alwaysLocked = true,
      hint = 'Purchase the X17 Modular on Tebex to unlock.'
    }
  },

  {
    code = 'WEAPON_X19',
    label = 'X19',
    category = 'addon_pistols',
    attachments = x19Attachments(),
  },

  {
    code = 'WEAPON_X17MS',
    label = 'Auto X17 Modular',
    category = 'addon_machine_pistols',
    attachments = x17Attachments('COMPONENT_MARKOMODS_X17M_SWITCHSLIDE_', 'Switch Slide'),
  },
}

local function buildConfig()
  local categories = {}
  local locales = {}
  local attachments = {}
  local unlocks = {}

  for key, def in pairs(CATEGORY_DEFS) do
    categories[key] = {
      label = def.label,
      ammo = def.ammo,
      inherit = def.inherit,
      group = def.group,
      groupLabel = def.groupLabel,
      groupDescription = def.groupDescription,
      groupIcon = def.groupIcon,
      weapons = {}
    }
  end

  for _, weapon in ipairs(ADDON_WEAPONS) do
    local code = weapon.code
    local category = categories[weapon.category]
    if code and category then
      category.weapons[#category.weapons + 1] = code
      locales[code] = weapon.label or code
      attachments[code] = weapon.attachments or {}
      if weapon.unlock then
        unlocks[code] = weapon.unlock
      end
    end
  end

  return categories, locales, attachments, unlocks
end

local categories, locales, attachments, unlocks = buildConfig()

return {
  enabled = true,
  weapons = ADDON_WEAPONS,
  categories = categories,
  locales = locales,
  attachments = attachments,
  unlocks = unlocks,
}
