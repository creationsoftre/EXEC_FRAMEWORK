local utils = {}

function utils.newSet()
  local t = {}; t._ = {}
  function t:add(v) self._[v] = true end
  function t:remove(v) self._[v] = nil end
  function t:contains(v) return self._[v] ~= nil end
  return t
end

return utils
