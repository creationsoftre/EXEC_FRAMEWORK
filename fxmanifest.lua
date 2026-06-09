fx_version 'cerulean'
game 'gta5'

name 'exec_framework'
author 'WickmanCapo'
description 'PvP framework for EXEC RZ.'
version '3.8.4'

ui_page 'html/scoreboard.html'

files {
  'config/*.lua',
  'bridge/*.lua',
  'html/scoreboard.html',
  'html/scoreboard.css',
  'html/leaderboard.css',
  'html/leaderboard.js',
  'html/scoreboard.js'
}

shared_scripts {
  '@ox_lib/init.lua',
  'shared/utils.lua',
  'shared/leaderboard_defs.lua',
  'shared/weapon_catalog.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/db.lua',
  'server/routes.lua',
  'server/gangs.lua',
  'server/weapon_unlocks.lua',
  'server/stats.lua',
  'server/leaderboard.lua',
  'server/passive.lua',
  'server/main.lua'
}

client_scripts {
  'client/ui_theme.lua',
  'client/zones.lua',
  'client/placement.lua',
  'client/weapon_state.lua',
  'client/loadout.lua',
  'client/scoreboard.lua',
  'client/help.lua',
  'client/gangs.lua',
  'client/leaderboard.lua',
  'client/main.lua',
  'client/gameplay.lua',
  'client/passive.lua',
  'client/death.lua',
}

dependencies { 'ox_lib', 'oxmysql' }

escrow_ignore {
  '.git',
  '.git/**',
  'database/*.sql',
  'config/*.lua',
  'bridge/*.lua'
}
