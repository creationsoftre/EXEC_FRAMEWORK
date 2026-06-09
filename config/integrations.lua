return {
  -- CAPO: Change providers here when wiring EXEC into another server stack.
  hud = {
    provider = 'exec_hud', -- exec_hud, custom, none
    resource = 'exec_hud',
    hide = { type = 'export', name = 'HideHud' },
    show = { type = 'export', name = 'ShowHud' },
  },

  appearance = {
    provider = 'fivem-appearance', -- fivem-appearance, custom, none
    resource = 'fivem-appearance',
    open = { type = 'export', name = 'startPlayerCustomization' },
    saveEvent = 'exec_multichar:saveAppearance',
    options = {
      ped = true,
      headBlend = true,
      faceFeatures = true,
      headOverlays = true,
      components = true,
      props = true,
      tattoos = true,
    },
  },

  killfeed = {
    provider = 'exec_killfeed', -- exec_killfeed, custom, none
    targets = {
      { type = 'event', name = 'exec_killfeed:onKill' },
    },
  },

  notify = {
    provider = 'ox_lib', -- ox_lib, custom, none
    clientEvent = 'ox_lib:notify',
  },

  identity = {
    provider = 'exec_multichar', -- exec_multichar, state, custom, none
    resource = 'exec_multichar',
    citizenStateKeys = { 'execCitizenId', 'citizenid', 'citizenId' },
  },

  inventory = {
    provider = 'native', -- native, custom, none
    defaultAmmo = 9999,
    -- custom examples:
    -- giveWeapon = { type = 'export', resource = 'my_inventory', name = 'GiveWeapon' },
    -- clearWeapons = { type = 'event', name = 'my_inventory:clearWeapons' },
    -- setCurrentWeapon = { type = 'export', resource = 'my_inventory', name = 'SetCurrentWeapon' },
    -- setAmmo = { type = 'export', resource = 'my_inventory', name = 'SetAmmo' },
    -- setVitals = { type = 'event', name = 'my_hud_or_ambulance:setVitals' },
  },

  target = {
    provider = 'none', -- ox_target, qb-target, custom, none
    resource = nil,
    -- custom examples:
    -- addEntity = { type = 'export', resource = 'my_target', name = 'AddEntity' },
    -- removeEntity = { type = 'export', resource = 'my_target', name = 'RemoveEntity' },
  },

  voice = {
    provider = 'native', -- native, pma-voice, mumble-voip, custom, none
    talkingStateKey = nil,
    -- custom example:
    -- isTalking = { type = 'export', resource = 'my_voice', name = 'IsTalking' },
  },

  spawn = {
    provider = 'spawnmanager', -- spawnmanager, native, custom, none
    resource = 'spawnmanager',
    autoSpawn = false,
    -- custom example:
    -- placePed = { type = 'export', resource = 'my_spawn', name = 'PlacePed' },
  },
}
