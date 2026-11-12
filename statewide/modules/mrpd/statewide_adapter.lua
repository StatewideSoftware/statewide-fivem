local STATEWIDE = 'statewide'

if not IsDuplicityVersion() then return end

local officers = setmetatable({}, { __mode = 'k' })

local function defaults()
  if type(DefaultCapabilities) == 'function' then
    local ok, res = pcall(DefaultCapabilities)
    return ok and res or nil
  end
  return DefaultCapabilities
end

local function closed(t)
  local out = {}
  for k, v in pairs(type(t) == 'table' and t or {}) do
    if type(v) == 'table' then
      out[k] = closed(v)
    elseif type(v) == 'boolean' then
      out[k] = false
    else
      out[k] = v
    end
  end
  return out
end

local function meta()
  if GetResourceState(STATEWIDE) ~= 'started' then return nil end
  local ok, res = pcall(function() return exports[STATEWIDE]:mrpd_meta(defaults()) end)
  if ok and type(res) == 'table' then return res end
  return nil
end

local function call(method, ctx, ...)
  local args = table.pack(...)
  return pcall(function() return exports[STATEWIDE]:mrpd_call(method, ctx, table.unpack(args, 1, args.n)) end)
end

local function framework(name, ...)
  local f = rawget(_G, 'Framework')
  if type(f) ~= 'table' or type(f[name]) ~= 'function' then return nil end
  local ok, res = pcall(f[name], ...)
  if ok then return res end
  return nil
end

local function acting()
  return { actingSrc = officers[coroutine.running()] }
end

local function gate(method)
  return function(src, ...)
    officers[coroutine.running()] = src
    local ok, res = call(method, {}, src, ...)
    return ok and res == true
  end
end

local function read(method)
  return function(...)
    local ok, res = call(method, acting(), ...)
    if ok then return res end
    return nil
  end
end

local function write(method)
  return function(...)
    local ok, res, reason = call(method, acting(), ...)
    if not ok then return false, 'unavailable' end
    if res == true then return true end
    return false, reason or 'failed'
  end
end

local info = meta()

local Adapter = {
  id = 'statewide',
  label = 'Statewide CAD',
  priority = 50,
  capabilities = info and info.enabled == true and type(info.capabilities) == 'table' and info.capabilities or closed(defaults()),
}

function Adapter.detect()
  local m = meta()
  return m ~= nil and m.enabled == true
end

Adapter.hasTerminalAccess = gate('hasTerminalAccess')
Adapter.hasFeature = gate('hasFeature')

function Adapter.getOfficerInfo(src, ...)
  local ctx = acting()
  ctx.cid = framework('resolveIdentifier', src)
  local ok, res = call('getOfficerInfo', ctx, src, ...)
  if ok then return res end
  return nil
end

function Adapter.getCitizenByCid(cid, ...)
  local ctx = acting()
  ctx.cidSource = framework('identifierToSource', cid)
  local ok, res = call('getCitizenByCid', ctx, cid, ...)
  if ok then return res end
  return nil
end

Adapter.getOnDutyOfficers = read('getOnDutyOfficers')
Adapter.getRoster = read('getRoster')
Adapter.searchCitizens = read('searchCitizens')
Adapter.lookupPlate = read('lookupPlate')
Adapter.getFlaggedPlates = read('getFlaggedPlates')
Adapter.searchWeapons = read('searchWeapons')
Adapter.getWeapon = read('getWeapon')
Adapter.getBolos = read('getBolos')
Adapter.getDispatches = read('getDispatches')
Adapter.getVehicleStats = read('getVehicleStats')
Adapter.getFleetData = read('getFleetData')
Adapter.respondDispatch = write('respondDispatch')

RegisterPoliceAdapter(Adapter)
