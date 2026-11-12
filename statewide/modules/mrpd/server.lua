Mrpd = {}

local M = MrpdMap
local cfg = Config.mrpd or {}
local STALE_MS = 300000
local LOG_SECONDS = 60
local TTL = { units = 15, bolos = 30, calls = 10 }
local KINDS = { hasTerminalAccess = 'gate', hasFeature = 'gate', respondDispatch = 'write' }
local memos = { units = {}, bolos = {}, calls = {} }
local logged = {}
local windows = {}
local registered = false

local function clock()
  return GetGameTimer() / 1000
end

function Mrpd.resource()
  return type(cfg.resource) == 'string' and cfg.resource or 'prompt_mrpd_terminal'
end

function Mrpd.enabled()
  return cfg.enabled == true and M.enabled((Config.modules or {}).mrpd, GetResourceState(Mrpd.resource()))
end

function Mrpd.clear()
  memos.units, memos.bolos, memos.calls = {}, {}, {}
end

local function officer(src)
  src = tonumber(src)
  if not src then return nil end
  local p = State.peek(src)
  if type(p) ~= 'table' or type(p.discordId) ~= 'string' or type(p.account) ~= 'table' then return nil end
  if p.account.discordId ~= p.discordId then return nil end
  if type(p.checkedAt) ~= 'number' or GetGameTimer() - p.checkedAt > STALE_MS then return nil end
  local u = p.unit
  if type(u) ~= 'table' or type(u.department) ~= 'table' or u.department.type ~= 'LEO' then return nil end
  if u.canLookup ~= true then return nil end
  return p, src
end

local function acting(ctx)
  return officer(ctx.actingSrc)
end

local function allowed(src)
  return M.allow(windows, src, tonumber(cfg.lookupsPerMinute) or 20, clock())
end

local function ok(res)
  return type(res) == 'table' and res.status == 200 and type(res.data) == 'table'
end

local function people(p, query)
  query.discordId = p.discordId
  query.partial = query.ssn and 'false' or 'true'
  local res = api('GET', '/lookup/person', 'lookup', { query = query, as = p.account, retry = false })
  if not ok(res) then return nil end
  local out = {}
  for _, r in ipairs(type(res.data.results) == 'table' and res.data.results or {}) do
    local m = M.toProfile(r)
    if m then out[#out + 1] = m end
  end
  return out
end

local function firearms(p, serial)
  local res = api('GET', '/lookup/firearm', 'lookup', { query = { discordId = p.discordId, serial = serial }, as = p.account, retry = false })
  if not ok(res) then return nil end
  local out = {}
  for _, r in ipairs(type(res.data.results) == 'table' and res.data.results or {}) do
    local m = M.toWeapon(r)
    if m then out[#out + 1] = m end
  end
  return out
end

local function bolos()
  return M.memo(memos.bolos, 'active', TTL.bolos, clock(), function()
    local res = api('GET', '/bolos', 'lookup', { query = { active = 'true' }, retry = false })
    return ok(res) and type(res.data.bolos) == 'table' and res.data.bolos or nil
  end)
end

local function units()
  return M.memo(memos.units, 'LEO', TTL.units, clock(), function()
    local res = api('GET', '/units', 'units', { query = { type = 'LEO' }, retry = false })
    return ok(res) and type(res.data.units) == 'table' and res.data.units or nil
  end)
end

local function onDuty(ctx)
  local _, src = acting(ctx)
  if not src then return {} end
  local viewer, mode = State.viewer(src), State.isolation()
  local out = {}
  for _, u in ipairs(units() or {}) do
    if type(u) == 'table' and not Pure.isMasked(Pure.unitRef(u), viewer, mode) then
      local m = M.toOfficer(u, nil)
      if m then out[#out + 1] = m end
    end
  end
  return out
end

local function plateOf(v)
  local s = M.clean(v, 16)
  return s and s:upper() or nil
end

local handlers = {}

function handlers.hasTerminalAccess(_, src)
  return officer(src) ~= nil
end

function handlers.hasFeature(_, src, key)
  return officer(src) ~= nil and M.featureAllowed(key, true)
end

function handlers.getOfficerInfo(ctx, src)
  local p = officer(src)
  if not p then return nil end
  return M.toOfficer(p.unit, ctx.cid)
end

handlers.getOnDutyOfficers = onDuty
handlers.getRoster = onDuty

function handlers.searchCitizens(ctx, query)
  local p, src = acting(ctx)
  local q = M.parseSearch(query)
  if not p or not q or not allowed(src) then return {} end
  return people(p, q) or {}
end

function handlers.getCitizenByCid(ctx, cid)
  local p, src = acting(ctx)
  if not p then return nil end
  local ssn
  if M.isSsn(cid) then
    ssn = tostring(cid):gsub('[%s%-]', '')
  elseif ctx.cidSource then
    local other = State.peek(ctx.cidSource)
    local c = type(other) == 'table' and other.character
    if type(c) == 'table' and M.isSsn(c.ssn) then ssn = c.ssn end
  end
  if not ssn or not allowed(src) then return nil end
  local list = people(p, { ssn = ssn })
  return list and list[1] or nil
end

function handlers.lookupPlate(ctx, plate)
  local p, src = acting(ctx)
  local key = plateOf(plate)
  if not p or not key or not allowed(src) then return nil end
  local res = api('GET', '/lookup/vehicle', 'lookup', { query = { discordId = p.discordId, plate = key, partial = 'false' }, as = p.account, retry = false })
  if not ok(res) then return nil end
  local first = type(res.data.results) == 'table' and res.data.results[1]
  return first and M.toPlate(first) or nil
end

function handlers.getFlaggedPlates(ctx)
  if not acting(ctx) then return {} end
  return M.flaggedPlates(bolos())
end

function handlers.searchWeapons(ctx, query)
  local p, src = acting(ctx)
  local serial = M.clean(query)
  if not p or not serial or not allowed(src) then return {} end
  return firearms(p, serial) or {}
end

function handlers.getWeapon(ctx, serial)
  local p, src = acting(ctx)
  serial = M.clean(serial)
  if not p or not serial or not allowed(src) then return nil end
  local list = firearms(p, serial)
  return list and list[1] or nil
end

function handlers.getBolos(ctx)
  if not acting(ctx) then return {} end
  return M.toBolos(bolos())
end

function handlers.getDispatches(ctx)
  local p = acting(ctx)
  if not p then return {} end
  local calls = M.memo(memos.calls, p.discordId, TTL.calls, clock(), function()
    local res = api('GET', '/calls', 'calls', { query = { discordId = p.discordId }, as = p.account, retry = false })
    return ok(res) and type(res.data.calls) == 'table' and res.data.calls or nil
  end)
  return M.toDispatches(calls)
end

function handlers.respondDispatch(ctx, ...)
  local p, src = acting(ctx)
  if not p then return false, 'denied' end
  local number = M.callNumberIn(Pure.isCallNumber, ...)
  if not number then return false, 'invalid' end
  if not allowed(src) then return false, 'rate_limited' end
  local res = api('POST', '/calls/{number}/units', 'calls', { params = { number = number }, body = Pure.withPlayer(p.account, {}), as = p.account, retry = false })
  if type(res) == 'table' and res.status == 200 then
    memos.calls = {}
    return true
  end
  local problem = type(res) == 'table' and res.problem or nil
  return false, problem and problem.code or 'failed'
end

function handlers.getVehicleStats()
  return {}
end

function handlers.getFleetData()
  return { ok = false }
end

local function failed(method, err)
  local now = clock()
  local at = logged[method]
  if at and now - at < LOG_SECONDS then return end
  logged[method] = now
  print(('^1[statewide] MRPD %s: %s^7'):format(method, tostring(err)))
end

local function context(ctx)
  local out = {}
  if type(ctx) ~= 'table' then return out end
  out.actingSrc = tonumber(ctx.actingSrc)
  out.cidSource = tonumber(ctx.cidSource)
  out.cid = M.clean(ctx.cid, 64)
  return out
end

function Mrpd.call(method, ctx, ...)
  local handler = type(method) == 'string' and handlers[method] or nil
  if not handler then return nil end
  local res = table.pack(pcall(handler, context(ctx), ...))
  if res[1] then return table.unpack(res, 2, res.n) end
  failed(method, res[2])
  local kind = KINDS[method]
  if kind == 'gate' then return false end
  if kind == 'write' then return false, 'error' end
  return nil
end

function Mrpd.meta(defaults)
  local on = Mrpd.enabled()
  return { enabled = on, capabilities = on and M.capabilities(defaults, true) or nil }
end

exports('mrpd_meta', function(defaults)
  local caller = GetInvokingResource()
  if not caller or caller ~= Mrpd.resource() then return nil end
  return Mrpd.meta(defaults)
end)

exports('mrpd_call', function(method, ctx, ...)
  local caller = GetInvokingResource()
  if not caller or caller ~= Mrpd.resource() or not Mrpd.enabled() then return nil end
  return Mrpd.call(method, ctx, ...)
end)

local function fromServer(kind)
  return function(payload)
    local src = source
    if src ~= nil and src ~= '' and tonumber(src) ~= 0 then return end
    if not Mrpd.enabled() then return end
    memos.calls = {}
    local push = M.dispatchPush(kind, payload)
    if push then TriggerEvent('mrpd_terminal:dispatchReceived', push) end
  end
end

local function register()
  if registered then return end
  registered = true
  AddEventHandler('statewide:911', fromServer('911'))
  AddEventHandler('statewide:panic', fromServer('panic'))
  AddEventHandler('statewide:attached', fromServer('attached'))
  AddEventHandler('playerDropped', function()
    windows[tonumber(source)] = nil
  end)
  AddEventHandler('onResourceStop', function(name)
    if name == Mrpd.resource() then Mrpd.clear() end
  end)
end

if cfg.enabled == true and (Config.modules or {}).mrpd ~= false then
  AddEventHandler('onResourceStart', function(name)
    if name == Mrpd.resource() and Mrpd.enabled() then register() end
  end)
  if Mrpd.enabled() then register() end
end
