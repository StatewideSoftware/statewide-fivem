local selects = {}

local function settings()
  local c = Config.sync or {}
  return c.standalone or {}, { dateOrder = c.dateOrder, genders = c.genders }
end

local function query(sql, params)
  if GetResourceState('oxmysql') ~= 'started' then return nil, 'oxmysql is not started' end
  local p, settled = promise.new(), false
  local function settle(rows)
    if settled then return end
    settled = true
    p:resolve(rows)
  end
  local ok, err = pcall(function()
    exports.oxmysql:query(sql, params, settle)
  end)
  if not ok then return nil, err end
  SetTimeout(30000, function() settle(false) end)
  local rows = Citizen.Await(p)
  if type(rows) ~= 'table' then return nil, 'query failed' end
  return rows
end

Sync.register('standalone', {
  source = 'standalone',
  normalize = function(entity, row)
    local maps, opts = settings()
    return Pure.syncItem(entity, row, maps[entity], opts)
  end,
  page = function(entity, offset, limit)
    local maps = settings()
    if not maps[entity] then return {} end
    local sql = selects[entity]
    if not sql then
      local err
      sql, err = Pure.syncSelect(entity, maps[entity])
      if not sql then return nil, err end
      selects[entity] = sql
    end
    return query(sql, { limit, offset })
  end,
})
