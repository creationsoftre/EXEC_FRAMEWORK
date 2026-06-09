return {
  hub = { spawn = vector3(-1107.6542, -1496.0618, 4.8300), radius = 60.0, heading = 330.0 },

  modes = {
    -- Hard-lock to just Combat Pistol and disable the Weapons menu
    pistol_only = {
      label='Combat Pistols',
      categoryLock='pistols',
      weaponLock='WEAPON_COMBATPISTOL',   -- << add this
      armor=100, health=200, firstTo=30
    },

    sniper_only = { label='Snipers', categoryLock='snipers', armor=100, health=200, firstTo=30 },
    shotgun_only= { label='Shotguns', categoryLock='shotguns', armor=100, health=200, firstTo=30 },
    smg_only    = { label='SMGs',     categoryLock='smgs',    armor=100, health=200, firstTo=30 },
    rifle_only  = { label='ARs',      categoryLock='rifles',  armor=100, health=200, firstTo=30 },
    gun_game    = { label='Gun Game', sequence={'WEAPON_KNIFE','WEAPON_PISTOL','WEAPON_SAWNOFFSHOTGUN','WEAPON_SMG','WEAPON_ASSAULTRIFLE','WEAPON_SNIPERRIFLE'}, perLevelKills=1, armor=100, health=200, firstTo=30 },
    sandbox     = { label='Sandbox',  armor=100, health=200 }
  },


  groups = {
    city = {
      label = 'City',
      icon = 'city',
      locations = {
        legion_square = {
          label='Legion Square',
          icon='landmark',
          enabled=false,
          domeEnabled=false,
          center=vector3(189.5,-933.4,30.7), domeRadius=50.0, arenaRadius=120.0,
          sessionRadius = 34.0,
          sessionBuffer = 1.5,
          spawns = {
            vector3(201.4, -936.8, 30.0),
            vector3(178.9, -934.9, 30.1),
            vector3(189.2, -920.6, 30.2),
            vector3(190.7, -948.1, 30.1),
            vector3(203.6, -926.5, 30.1),
            vector3(176.2, -945.4, 30.2),
            vector3(200.3, -919.3, 30.1),
            vector3(180.1, -922.9, 30.1),
          },
          supports={'pistol_only','sniper_only','smg_only','rifle_only','gun_game','sandbox'},
          restrictions = {
            playground = { categories = { 'pistols','smgs','rifles','snipers','shotguns','melee' } },
            session = {
              public  = { categories = { 'pistols','smgs','rifles','snipers','shotguns','melee' } },
              private = { categories = { 'pistols','smgs','rifles','snipers','shotguns','melee','explosives','heavy' } },
            }
          }
        },
        skatepark = {
          label='Skate Park',
          icon='person-skating',
          enabled=true,
          domeEnabled=true,
          center=vector3(-941.3485, -791.2321, 15.9510), domeRadius=30.0, arenaRadius=140.0,
          sessionRadius = 32.0,
          sessionBuffer = 1.5,
          spawns = {
            vector3(-949.5, -800.2, 16.0),
            vector3(-933.8, -781.7, 16.2),
            vector3(-931.8, -800.6, 15.9),
            vector3(-952.4, -782.0, 16.1),
            vector3(-944.6, -772.5, 16.2),
            vector3(-928.9, -793.9, 15.8),
            vector3(-943.5, -808.4, 15.9),
            vector3(-955.8, -789.8, 15.8),
          },
          supports={'pistol_only','shotgun_only','rifle_only','sandbox'},
          restrictions = {
            playground = { categories = { 'pistols','shotguns','rifles','melee' } },
            session = {
              public  = { categories={'pistols','shotguns','rifles'} },
              private = { categories={'pistols','shotguns','rifles','explosives'} }
            }
          }
        },
        jungle = {
          label='Jungle',
          icon='tree',
          enabled=true,
          domeEnabled=false,
          center=vector3(435.9839, -1541.0977, 29.0140), domeRadius=30.0, arenaRadius=140.0,
          sessionRadius = 33.0,
          sessionBuffer = 1.5,
          spawns = {
            vector3(445.9, -1535.7, 29.2),
            vector3(424.8, -1534.4, 29.3),
            vector3(446.4, -1551.2, 28.9),
            vector3(425.2, -1552.0, 28.6),
            vector3(435.8, -1528.1, 29.6),
            vector3(410.8956, -1512.6613, 29.2916),
            vector3(420.1, -1542.4, 29.2),
          },
          supports={'pistol_only','shotgun_only','rifle_only','sandbox'},
          restrictions = {
            playground = { categories = { 'pistols','shotguns','rifles','melee' } },
            session = {
              public  = { categories={'pistols','shotguns','rifles'} },
              private = { categories={'pistols','shotguns','rifles','explosives'} }
            }
          }
        },
        mirror_park = {
          label='Mirror Park',
          icon='house',
          enabled=true,
          domeEnabled=true,
          center=vector3(1367.7255, -578.2282, 74.3802), domeRadius=30.0, arenaRadius=140.0,
          sessionRadius = 35.0,
          sessionBuffer = 1.5,
          spawns = {
            vector3(1378.9, -573.5, 74.5),
            vector3(1356.6, -571.8, 74.2),
            vector3(1376.2, -587.5, 74.6),
            vector3(1357.2, -588.3, 74.1),
            vector3(1368.5, -565.4, 74.4),
            vector3(1366.0, -595.6, 74.0),
            vector3(1383.5, -581.2, 74.6),
            vector3(1351.2, -580.7, 74.0),
          },
          supports={'pistol_only','shotgun_only','rifle_only','sandbox'},
          restrictions = {
            playground = { categories = { 'pistols','shotguns','rifles','melee' } },
            session = {
              public  = { categories={'pistols','shotguns','rifles'} },
              private = { categories={'pistols','shotguns','rifles','explosives'} }
            }
          }
        },
        stables = {
          label='Stables',
          icon='horse',
          enabled=true,
          domeEnabled=false,
          center=vector3(1455.5463, 1154.1289, 114.2954), domeRadius=30.0, arenaRadius=140.0,
          sessionRadius = 34.0,
          sessionBuffer = 1.5,
          spawns = {
            vector3(1486.0773, 1167.6752, 115.1049),
          },
          supports={'pistol_only','shotgun_only','rifle_only','sandbox'},
          restrictions = {
            playground = { categories = { 'pistols','shotguns','rifles','melee' } },
            session = {
              public  = { categories={'pistols','shotguns','rifles'} },
              private = { categories={'pistols','shotguns','rifles','explosives'} }
            }
          }
        },
      }
    },
    red = {
      label = 'Red Zone',
      icon = 'skull-crossbones',
      locations = {
        red_arena1 = {
          label='Death Room',
          icon='skull-crossbones',
          enabled=true,
          domeEnabled=true,
          center=vector3(3696.5718, 7580.8350, 112.5933), domeRadius=50.0, arenaRadius=120.0,
          showMarker=false,
          supports={'sandbox','pistol_only','smg_only'},
          restrictions = {
            playground = { categories = { 'pistols','smgs','melee' } },
            session = {
              public  = { categories={'pistols','smgs'} },
              private = { categories={'pistols','smgs','melee'} }
            }
          },
          spawns = {
            vector3(3720.6570, 7568.7886, 112.2625),
            vector3(3680.2361, 7560.0732, 113.5555),
            vector3(3675.5461, 7569.3071, 112.2624),
            vector3(3703.7644, 7562.1650, 117.6299),
            vector3(3690.6611, 7597.0264, 120.5926),
            vector3(3713.9636, 7599.8765, 113.5566),
          },
        }
      }
    }
  },

  brackets = {
    { key='ffa',    label='Playground (FFA)' },
    { key='1v1',    label='1v1' },
    { key='2v2',    label='2v2' },
    { key='3v3',    label='3v3' },
    { key='5v5',    label='5v5' },
    { key='gangwar',label='Gang War' },
  }
}




