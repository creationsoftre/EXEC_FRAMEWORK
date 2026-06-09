-- exec_framework/config/gameplay.lua
return {
  greenZones = {
    { label = 'Hub', center = vec3(-1037.6, -2737.9, 20.2), radius = 80.0 },
  },

  zoneMarker = {
    enabled = true,
    shape = 'dome',
    radiusScale = 1.0,
    verticalScale = 1.0,
    color = { r = 57, g = 255, b = 20 },
    alpha = 100,
    matchCombatBoundary = true,  -- use the same radius the combat-dome logic uses so visuals and rules stay aligned
    focusActiveZoneOnly = true,  -- when you are inside a zone, only draw that zone's combat boundary
    preciseActiveZone = true,    -- active combat zones use a precise cylinder/ring instead of the loose debug sphere shell
    preciseHeight = 3.0,
    preciseAlpha = 70,
    showGroundRing = true,       -- draw a crisp floor ring at the exact combat boundary to reduce ambiguity
    ringHeight = 0.18,
    ringAlpha = 125,
  },

  menu = {
    command = 'exec_menu',
    keybind = 'M',                 -- default key for opening the EXEC menu
    keybindLabel = 'Open Menu',
    control = 244,                 -- INPUT_INTERACTION_MENU (M)
  },

  hubHelp = {
    enabled = true,
    showInHubOnly = true,
    command = 'exec_hubhelp',
    keybind = 'H',
    title = 'Hub Controls',
    showToggle = true,
    toggleLabel = 'Toggle Hub Controls',
  },

  uiColors = {
    text = '#FFFFFF',
    muted = '#A8A8A8',
    accent = '#39FF14',
    accentSoft = 'rgba(57, 255, 20, 0.15)',
    accentStrong = 'rgba(57, 255, 20, 0.35)',
    live = '#39FF14',
    ending = '#FFB020',
    waiting = 'rgba(20, 21, 23, 0.85)',
    rowBg = 'rgba(20, 21, 23, 0.85)',
    rowBgSelf = 'rgba(57, 255, 20, 0.15)',
    bgDark = 'rgba(20, 21, 23, 0.85)',
    bgDarker = 'rgba(14, 14, 16, 0.94)',
    stroke = '#2A2C30',
    strokeStrong = 'rgba(57, 255, 20, 0.35)',
  },

  session = {
    countdownSeconds = 60,
    preMatchCountdownSeconds = 3,
    cleanupIntervalSeconds = 15,
    brackets = {
      ["1v1"] = { min = 2, max = 2 },
      ["2v2"] = { min = 4, max = 4 },
      ["3v3"] = { min = 6, max = 6 },
      gangwar    = { min = 10, max = 20 },
      ["5v5"]   = { min = 10, max = 20 },
    },
  },

  playerMovement = {
    unlimitedSprint = true,  -- true keeps stamina full at all times
    sprintMultiplier = 1.0,   -- 1.0 is default, clamp between 1.0 and 1.49
  },

  combat = {
    oneShotHeadshots = true, -- true makes any player headshot lethal regardless of weapon or distance
  },

  combatDome = {
    enabled = true,             -- turns dome-based combat flow on for arenas that define a domeRadius
    respawnOutside = true,      -- respawn/join players in the outer shell instead of directly inside the combat dome
    passiveOutside = true,      -- players outside the dome stay passive and cannot shoot into the fight
    lockAfterEntry = true,      -- once a player enters the dome, they are committed for that life
    snapbackOnExit = true,      -- stepping back out after entry teleports the player to the inner edge of the dome
    entryBuffer = 0.75,         -- forgiving buffer when deciding if the player has entered the dome
    exitBuffer = 1.0,           -- how far outside the dome a committed player may drift before being returned
    returnInset = 1.5,          -- how far inside the dome to place the player when snapping them back in
    notifyOnEntry = true,       -- show a one-time message when the player commits to combat
    notifyOnExit = true,        -- show a warning when a committed player is pushed back inside
    notifyCooldownMs = 3000,    -- minimum delay between dome warnings
    snapbackCooldownMs = 750,   -- minimum delay between boundary snapback teleports
  },

  debug = {
    weapon = false,
    session = false,
    boundary = false,
  },

  environment = {
    vehicles = {
      enabled = false,          -- false removes ambient traffic and cleans up parked/empty vehicles nearby
      cleanupRadius = 250.0,    -- radius around the player to clear ambient vehicles when disabled
      cleanupSeconds = 4.0,     -- how often to sweep nearby ambient vehicles
    },

    peds = {
      enabled = false,          -- false disables ambient/world ped population
    },

    weather = {
      enabled = true,           -- force a specific weather type
      type = 'EXTRASUNNY',       -- e.g. CLEAR, RAIN, THUNDER, XMAS
      transitionSeconds = 1.0,   -- blend duration when applying new weather
      refreshSeconds = 30,       -- reapply interval to prevent drift
    },

    time = {
      enabled = true,            -- override the session clock
      hour = 12,
      minute = 0,
      second = 0,
      freeze = true,             -- true = keep time fixed at the values above
      rate = 1.0,                -- when not frozen, 1.0 is real-time speed
      updateSeconds = 1.0,       -- how often to resync the clock
    },
  },

  passive = {
    enableInGreen   = true,
    invincible      = true,
    noCollision     = false,
    disableControls = true,
    forceUnarmed    = true,
    indicator       = true,
    ghostAlpha      = -1,
  },

  respawn = {
    enabled              = true,
    mode                 = 'manual', -- manual = press key, auto = spawnmanager/other
    alwaysRandomize      = true,     -- true randomizes arena respawns for every supported zone
    manual = {
      control = 38,                  -- INPUT_CONTEXT (E)
      keyLabel = 'E',
      prompt = {
        enabled = true,
        title = 'You are down',
        prefix = 'Press',
        suffix = 'to revive',
      },
    },
    delaySeconds         = 1.25,     -- small delay before post-spawn reposition
    seconds              = 5,        -- spawn grace/passive
    invincible           = true,
    disableControls      = true,
    forceUnarmed         = false,    -- false keeps the restored weapon equipped during respawn grace

    -- legacy allowlist used only when alwaysRandomize = false
    randomizeInGroups    = { 'city', 'red' },

    spawn = {
      minDistanceFromPlayers = 18.0,
      tries                   = 32,
      innerBuffer             = 5.0,   -- margin outside the dome
      edgeBuffer              = 4.0,   -- margin inside arenaRadius
      zProbe                  = 60.0,
      respectDomeAsNoSpawn    = true,
      offsetAboveGround       = 0.6,
      reservationSeconds      = 8.0,   -- temporarily reserve the chosen respawn so near-simultaneous revives do not overlap
      repeatAvoidSeconds      = 30.0,  -- avoid reusing the same reserved spawn for this player within this window
      singleSpawnVariantRadius= 4.5,   -- when a zone only has one configured spawn, fan out nearby variants instead of reusing the exact point
    },

    restoreLastWeapon = {
      enabled      = true,
      defaultAmmo  = 9999, -- also used as the max/refill amount
      refillOnEmpty= true,
      moveRestoreDelaysMs = { 150, 450 },
      respawnRestoreDelaysMs = { 450, 1200 },
      loadoutRestoreDelaysMs = { 0, 250 },
      pendingLoadoutRestoreDelaysMs = { 0, 250, 900 },
    },
  },

  -- legacy; ignored in AUTO
  instantRevive = { enabled = false },

  -- Legacy killfeed integrations. Prefer config/integrations.lua for new installs.
  -- Add events or exports to receive kill payloads.
  -- Supported entries:
  --   { type = 'event', name = 'resource:eventName' }
  --   { type = 'export', resource = 'resourceName', name = 'ExportFunction' }
  killfeeds = {
    { type = 'event', name = 'exec_killfeed:onKill' },
  },
}
