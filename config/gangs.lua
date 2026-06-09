return {
  admin = {
    command = 'gangadmin',
    keybind = false,
    identifiers = {'license:8da8d8b35679fc9281d641418e0629681514e56d'},
    ace = 'group.admin'
  },
  leader = {
    command = 'gangmenu',
    keybind = false
  },
  defaults = {
    ranks = {
      boss = 'Boss',
      underboss = 'Underboss',
      hitman = 'Hitman',
      footsoldier = 'Foot Soldier'
    },
    underbossPerms = {
      renameRanks = false,
      manageMembers = false,
      viewDetails = true,
      dissolve = false
    }
  },
  limits = {
    maxMembers = 20,
    underboss = 3
  },
  invite = {
    expirySeconds = 60
  }
}
