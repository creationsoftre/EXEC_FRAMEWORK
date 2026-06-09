local cfg = require 'config.arenas'

lib.callback.register('exec:listGroups', function(src)
  local out = {}
  if cfg.groups then
    for gk, g in pairs(cfg.groups) do
      out[#out+1] = { key=gk, label=g.label, icon=g.icon }
    end
  else
    out[#out+1] = { key='city', label='City', icon='city' }
  end
  table.sort(out, function(a,b) return a.label < b.label end)
  return out
end)

lib.callback.register('exec:listLocationsInGroup', function(src, groupKey)
  local out = {}
  local group = (cfg.groups and cfg.groups[groupKey]) and cfg.groups[groupKey] or { locations = cfg.city }
  for key, loc in pairs(group.locations or {}) do
    out[#out+1] = { key=key, label=loc.label, icon=loc.icon, supports=loc.supports }
  end
  table.sort(out, function(a,b) return a.label < b.label end)
  return out
end)
