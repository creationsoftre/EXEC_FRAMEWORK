return {
  categories = {
    pistols = {
      label = 'Pistols', ammo = 200,
      weapons = { 'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_APPISTOL' }
    },
    melee = {
      label = 'Melee', ammo = 0,
      weapons = { 'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE' }
    },
    shotguns = {
      label = 'Shotguns', ammo = 80,
      weapons = { 'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2', 'WEAPON_SAWNOFFSHOTGUN' }
    },
    smgs = {
      label = 'SMGs', ammo = 200,
      weapons = { 'WEAPON_SMG', 'WEAPON_MICROSMG', 'WEAPON_MINISMG', 'WEAPON_SMG_MK2' }
    },
    rifles = {
      label = 'Assault Rifles', ammo = 200,
      weapons = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE' }
    },
    snipers = {
      label = 'Snipers', ammo = 60,
      weapons = { 'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2' }
    },
    explosives = {
      label = 'Explosives', ammo = 12,
      weapons = { 'WEAPON_GRENADE', 'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE' }
    },
    heavy = {
      label = 'Heavy', ammo = 60,
      weapons = { 'WEAPON_RPG', 'WEAPON_MINIGUN', 'WEAPON_COMBATMG' }
    },
  },

  reticle = {
    whitelistCategories = { 'snipers' },
    whitelistWeapons = {},
  },

  locales = {
    WEAPON_PISTOL             = 'Pistol',
    WEAPON_COMBATPISTOL       = 'Combat Pistol',
    WEAPON_PISTOL_MK2         = 'Pistol Mk II',
    WEAPON_APPISTOL           = 'AP Pistol',
    WEAPON_KNIFE              = 'Knife',
    WEAPON_BAT                = 'Baseball Bat',
    WEAPON_MACHETE            = 'Machete',
    WEAPON_SWITCHBLADE        = 'Switchblade',
    WEAPON_PUMPSHOTGUN        = 'Pump Shotgun',
    WEAPON_PUMPSHOTGUN_MK2    = 'Pump Shotgun Mk II',
    WEAPON_SAWNOFFSHOTGUN     = 'Sawed-Off Shotgun',
    WEAPON_SMG                = 'SMG',
    WEAPON_MICROSMG           = 'Micro SMG',
    WEAPON_MINISMG            = 'Mini SMG',
    WEAPON_SMG_MK2            = 'SMG Mk II',
    WEAPON_ASSAULTRIFLE       = 'Assault Rifle',
    WEAPON_CARBINERIFLE       = 'Carbine Rifle',
    WEAPON_CARBINERIFLE_MK2   = 'Carbine Rifle Mk II',
    WEAPON_ADVANCEDRIFLE      = 'Advanced Rifle',
    WEAPON_SNIPERRIFLE        = 'Sniper Rifle',
    WEAPON_HEAVYSNIPER        = 'Heavy Sniper',
    WEAPON_HEAVYSNIPER_MK2    = 'Heavy Sniper Mk II',
    WEAPON_GRENADE            = 'Grenade',
    WEAPON_STICKYBOMB         = 'Sticky Bomb',
    WEAPON_PROXMINE           = 'Proximity Mine',
    WEAPON_RPG                = 'RPG',
    WEAPON_MINIGUN            = 'Minigun',
    WEAPON_COMBATMG           = 'Combat MG',
    WEAPON_MARKSMANRIFLE      = 'Marksman Rifle',
  }
}
