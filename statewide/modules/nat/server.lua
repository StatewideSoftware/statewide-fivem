Nat = {}

local cfg = Config.nat or {}
local resource = cfg.resource or 'framework'
local SELECT = 'SELECT `id`, `discord`, `first_name`, `last_name`, `dob`, `gender`, `level` FROM `characters` WHERE `id` = ? AND (`discord` = ? OR `discord` = ?) LIMIT 1'
local seen = {}
local generation = {}
local warned = {}
local started = false

local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(('^3[statewide] %s^7'):format(line))
end

local function options()
  return { label = 'nat', map = cfg.departments, autoDuty = cfg.autoDuty ~= false }
end

local function query(sql, params)
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
  SetTimeout(15000, function() settle(false) end)
  local rows = Citizen.Await(p)
  if type(rows) ~= 'table' then return nil, 'query failed' end
  return rows
end

function Nat.sessionKey(session)
  if type(session) ~= 'table' then return false end
  local charid = session.charid
  if charid == nil then charid = session.char_id end
  if charid == nil or charid == false then return false end
  return tostring(charid) .. '|' .. tostring(session.level), charid
end

function Nat.changed(src, charid)
  local gen = (generation[src] or 0) + 1
  generation[src] = gen
  if not charid then return Framework.apply(src, nil, options()) end
  local discord = Framework.discordOf(src)
  if not discord then return Notify.player(src, L('no_discord'), 'error') end
  local rows, err = query(SELECT, { charid, discord, 'discord:' .. discord })
  if generation[src] ~= gen then return end
  if not rows then
    warnOnce('query', ('nat module could not read the characters table: %s'):format(tostring(err)))
    return
  end
  if not rows[1] then return Framework.refused('nat', src, 'not_owner') end
  local character = Pure.normalizeNat(rows[1], cfg.dateOrder)
  if not character then return Framework.refused('nat', src, 'validation') end
  Framework.apply(src, character, options())
end

local function functions()
  local ok, fns = pcall(function() return exports[resource]:getServerFunctions() end)
  if ok and type(fns) == 'table' and Pure.callable(fns.getPlayer) then return fns end
  warnOnce('exports', ('nat module: %s has no getServerFunctions().getPlayer; the module is idle.'):format(resource))
  return nil
end

function Nat.poll()
  if not Modules.active.nat then return end
  if GetResourceState('oxmysql') ~= 'started' then
    warnOnce('oxmysql', 'nat module needs oxmysql started; the module is idle.')
    return
  end
  local fns = functions()
  if not fns then return end
  local players = GetPlayers()
  for i = 1, #players do
    local src = tonumber(players[i])
    local ok, session = pcall(fns.getPlayer, src)
    local key, charid = Nat.sessionKey(ok and session or nil)
    if seen[src] ~= key then
      seen[src] = key
      CreateThread(function()
        local fine, err = pcall(Nat.changed, src, charid)
        if not fine then print(('^1[statewide] nat module: %s^7'):format(tostring(err))) end
      end)
    end
  end
end

function Nat.start()
  if started then return end
  started = true
  CreateThread(function()
    while true do
      local ok, err = pcall(Nat.poll)
      if not ok then print(('^1[statewide] nat module: %s^7'):format(tostring(err))) end
      Wait(math.max(1, tonumber(cfg.pollSeconds) or 3) * 1000)
    end
  end)
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  seen[src] = nil
  generation[src] = nil
end)

AddEventHandler('onResourceStop', function(stopped)
  if stopped == resource then seen = {} end
end)

Modules.resolve('nat', Nat.start, ('[statewide] nat module: not detected (%s is not started)'):format(resource))
