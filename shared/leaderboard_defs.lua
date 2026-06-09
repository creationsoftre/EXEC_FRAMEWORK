local defs = {}

defs.MODE_ORDER = { '1v1', '2v2', '3v3', '5v5', 'gangwar', 'ffa', 'global' }

local commonMetrics = {
  wins = { label = 'Wins', format = 'int' },
  games = { label = 'Matches', format = 'int' },
  kills = { label = 'Kills', format = 'int' },
  deaths = { label = 'Deaths', format = 'int' },
  kdr = { label = 'K/D', format = 'float', decimals = 2 },
  win_rate = { label = 'Win Rate', format = 'percent', decimals = 1 },
  kills_per_min = { label = 'Kills/Min', format = 'float', decimals = 2 },
}

local function defaultTeamTieBreakers()
  return {
    { key = 'win_rate', direction = 'desc' },
    { key = 'kdr', direction = 'desc' },
    { key = 'kills', direction = 'desc' },
    { key = 'games', direction = 'desc' },
  }
end

defs.MODE_SPECS = {
  ['1v1'] = {
    label = '1v1',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = defaultTeamTieBreakers(),
  },
  ['2v2'] = {
    label = '2v2',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = defaultTeamTieBreakers(),
  },
  ['3v3'] = {
    label = '3v3',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = defaultTeamTieBreakers(),
  },
  ['5v5'] = {
    label = '5v5',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = defaultTeamTieBreakers(),
  },
  gangwar = {
    label = 'Gang Wars',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = defaultTeamTieBreakers(),
  },
  ffa = {
    label = 'FFA',
    entityType = 'player',
    metricOrder = { 'kills', 'games', 'kdr', 'kills_per_min' },
    metrics = commonMetrics,
    sortKey = 'kills',
    sortDirection = 'desc',
    tieBreakers = {
      { key = 'kills_per_min', direction = 'desc' },
      { key = 'kdr', direction = 'desc' },
      { key = 'games', direction = 'desc' },
    },
  },
  global = {
    label = 'Global',
    entityType = 'player',
    metricOrder = { 'wins', 'games', 'kills', 'kdr', 'win_rate', 'kills_per_min' },
    metrics = commonMetrics,
    sortKey = 'wins',
    sortDirection = 'desc',
    tieBreakers = {
      { key = 'win_rate', direction = 'desc' },
      { key = 'kdr', direction = 'desc' },
      { key = 'kills', direction = 'desc' },
      { key = 'kills_per_min', direction = 'desc' },
      { key = 'games', direction = 'desc' },
    },
  },
}

defs.AWARD_ORDER = { 'most_wins', 'most_kills', 'best_kdr' }

defs.AWARD_SPECS = {
  most_wins = {
    label = 'Most Wins',
    metric = 'wins',
    format = 'int',
    description = 'Highest total wins across all ranked matches.',
    sortDirection = 'desc',
  },
  most_kills = {
    label = 'Top Fragger',
    metric = 'kills',
    format = 'int',
    description = 'Most eliminations recorded overall.',
    sortDirection = 'desc',
  },
  best_kdr = {
    label = 'Best K/D',
    metric = 'kdr',
    format = 'float',
    decimals = 2,
    description = 'Best kill/death ratio (min 5 matches).',
    sortDirection = 'desc',
    minGames = 5,
  },
}

return defs
