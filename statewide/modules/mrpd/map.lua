MrpdMap = {}

MrpdMap.TRUE_CAPS = { 'dispatch', 'dispatchFeed', 'bolos', 'weapons', 'flagPlates', 'licenses', 'criminalRecords' }
MrpdMap.WRITES = { 'respond_dispatch' }
MrpdMap.SEARCH_MAX = 100

local function str(v)
  if type(v) == 'string' and v ~= '' then return v end
  if type(v) == 'number' then return tostring(v) end
  return nil
end

local function list(v)
  return type(v) == 'table' and v or {}
end

local function has(t, value)
  for _, v in ipairs(list(t)) do
    if v == value then return true end
  end
  return false
end

local function fullName(p)
  if type(p) ~= 'table' then return nil end
  local first, last = str(p.firstName), str(p.lastName)
  if first and last then return first .. ' ' .. last end
  return first or last
end

function MrpdMap.isSsn(v)
  local s = str(v)
  if not s then return false end
  s = s:gsub('[%s%-]', '')
  return s:match('^[1-9]%d%d%d%d%d%d%d%d$') ~= nil
end

local function digits(v)
  return (str(v) or ''):gsub('[%s%-]', '')
end

function MrpdMap.clean(v, max)
  local s = str(v)
  if not s then return nil end
  s = s:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  if s == '' then return nil end
  return s:sub(1, max or MrpdMap.SEARCH_MAX)
end

function MrpdMap.parseSearch(query)
  local q = MrpdMap.clean(query)
  if not q then return nil end
  if MrpdMap.isSsn(q) then return { ssn = digits(q) } end
  local first, rest = q:match('^(%S+)%s+(.+)$')
  if first then return { first = first, last = rest } end
  return { last = q }
end

function MrpdMap.citizenCid(person)
  if type(person) ~= 'table' then return nil end
  return str(person.externalId) or str(person.ssn)
end

local function toLicenses(v)
  local out = {}
  for _, l in ipairs(list(v)) do
    if type(l) == 'table' then out[#out + 1] = { code = str(l.code), name = str(l.name), status = str(l.status) } end
  end
  return out
end

local function toWarrants(v)
  local out = {}
  for _, w in ipairs(list(v)) do
    if type(w) == 'table' then out[#out + 1] = { number = str(w.number), kind = str(w.kind), status = str(w.status) } end
  end
  return out
end

local function toVehicles(v)
  local out = {}
  for _, x in ipairs(list(v)) do
    if type(x) == 'table' then out[#out + 1] = { plate = str(x.plate), model = MrpdMap.model(x), color = str(x.color) } end
  end
  return out
end

function MrpdMap.model(v)
  if type(v) ~= 'table' then return nil end
  local make, model = str(v.make), str(v.model)
  if make and model then return make .. ' ' .. model end
  return make or model
end

function MrpdMap.toProfile(result)
  if type(result) ~= 'table' then return nil end
  local p = result.person
  if type(p) ~= 'table' then p = result end
  local cid = MrpdMap.citizenCid(p)
  if not cid then return nil end
  return {
    cid = cid,
    ssn = str(p.ssn),
    firstname = str(p.firstName),
    lastname = str(p.lastName),
    name = fullName(p),
    dob = str(p.dob),
    status = str(p.status),
    flags = list(p.flags),
    cautions = list(result.cautions),
    hits = list(result.hits),
    licenses = toLicenses(result.licenses),
    warrants = toWarrants(result.warrants),
    vehicles = toVehicles(result.vehicles),
  }
end

function MrpdMap.vehicleFlag(ret)
  if type(ret) ~= 'table' then return false, nil end
  for _, b in ipairs(list(ret.bolos)) do
    if type(b) == 'table' then return true, str(b.description) or 'BOLO' end
  end
  local v = ret.vehicle
  if type(v) == 'table' and has(v.flags, 'stolen') then return true, 'STOLEN' end
  return false, nil
end

function MrpdMap.toPlate(ret)
  if type(ret) ~= 'table' or type(ret.vehicle) ~= 'table' then return nil end
  local v = ret.vehicle
  local owner = type(ret.owner) == 'table' and ret.owner or {}
  local person = type(owner.person) == 'table' and owner.person or nil
  local business = type(owner.business) == 'table' and owner.business or nil
  local flagged, reason = MrpdMap.vehicleFlag(ret)
  return {
    plate = str(v.plate),
    vin = str(v.vin),
    model = MrpdMap.model(v),
    color = str(v.color),
    registration = str(v.registration),
    insurance = str(v.insurance),
    owner = fullName(person) or (business and str(business.name)) or nil,
    ownerCid = MrpdMap.citizenCid(person),
    isFlagged = flagged,
    flagReason = reason,
  }
end

function MrpdMap.toWeapon(res)
  if type(res) ~= 'table' or type(res.firearm) ~= 'table' then return nil end
  local f = res.firearm
  local owner = type(res.owner) == 'table' and res.owner or nil
  return {
    serial = str(f.serial),
    model = MrpdMap.model(f),
    type = str(f.type),
    status = str(f.status),
    isStolen = f.status == 'stolen',
    owner = fullName(owner),
    ownerCid = MrpdMap.citizenCid(owner),
  }
end

function MrpdMap.toBolo(b)
  if type(b) ~= 'table' or not str(b.id) then return nil end
  return {
    id = str(b.id),
    kind = str(b.kind),
    subject = str(b.subject),
    plate = str(b.plate),
    vehicle = str(b.vehicle),
    description = str(b.description),
    callNumber = str(b.callNumber),
    createdAt = str(b.createdAt),
    expiresAt = str(b.expiresAt),
  }
end

function MrpdMap.toBolos(bolos)
  local out = {}
  for _, b in ipairs(list(bolos)) do
    local m = MrpdMap.toBolo(b)
    if m then out[#out + 1] = m end
  end
  return out
end

function MrpdMap.flaggedPlates(bolos)
  local out, seen = {}, {}
  for _, b in ipairs(list(bolos)) do
    local plate = type(b) == 'table' and b.kind == 'vehicle' and str(b.plate)
    if plate and not seen[plate] then
      seen[plate] = true
      out[#out + 1] = { plate = plate, reason = str(b.description) or 'BOLO' }
    end
  end
  return out
end

local function where(location, postal)
  local l, p = str(location), str(postal)
  if l and p then return l .. ' (' .. p .. ')' end
  return l or p or ''
end

function MrpdMap.toDispatch(call)
  if type(call) ~= 'table' or not str(call.number) then return nil end
  return {
    id = str(call.number),
    number = str(call.number),
    title = str(call.nature) or str(call.number),
    priority = tonumber(call.priority),
    status = str(call.status),
    location = where(call.location, call.postal),
    description = str(call.description),
    createdAt = str(call.createdAt),
  }
end

function MrpdMap.toDispatches(calls)
  local out = {}
  for _, c in ipairs(list(calls)) do
    local m = MrpdMap.toDispatch(c)
    if m then out[#out + 1] = m end
  end
  return out
end

function MrpdMap.officerCid(unit, ctxCid)
  local cid = str(ctxCid)
  if cid then return cid end
  local d = type(unit) == 'table' and str(unit.discordId)
  return d and ('discord:' .. d) or nil
end

function MrpdMap.toOfficer(unit, ctxCid)
  if type(unit) ~= 'table' then return nil end
  local dept = type(unit.department) == 'table' and unit.department or {}
  local status = type(unit.status) == 'table' and unit.status or {}
  return {
    cid = MrpdMap.officerCid(unit, ctxCid),
    name = str(unit.name),
    callsign = str(unit.callsign),
    department = str(dept.abbreviation),
    status = str(status.label) or str(status.code),
    onDuty = true,
  }
end

function MrpdMap.dispatchPush(kind, payload)
  if type(payload) ~= 'table' then return nil end
  local title
  if kind == 'panic' then
    title = 'PANIC ' .. (str(payload.callsign) or '')
  else
    local number = str(payload.number)
    if not number then return nil end
    title = number .. ' ' .. (str(payload.nature) or (kind == '911' and '911' or 'Call'))
  end
  title = title:gsub('%s+$', '')
  return { title = title, location = where(payload.location, payload.postal) }
end

function MrpdMap.memo(store, key, ttl, now, fetch)
  local e = store[key]
  if e and now - e.at < ttl then return e.value end
  local value = fetch()
  if value ~= nil then store[key] = { at = now, value = value } end
  return value
end

function MrpdMap.enabled(setting, resourceState)
  if setting == false or setting == 'off' then return false end
  if setting == true or setting == 'on' then return true end
  return resourceState == 'started' or resourceState == 'starting'
end

local function falsify(t, depth)
  local out = {}
  for k, v in pairs(t) do
    if type(v) == 'table' and depth < 4 then
      out[k] = falsify(v, depth + 1)
    elseif type(v) == 'boolean' then
      out[k] = false
    elseif type(v) ~= 'function' then
      out[k] = v
    end
  end
  return out
end

local function setTrue(t, key, depth)
  local found = false
  for k, v in pairs(t) do
    if k == key and type(v) ~= 'table' then
      t[k] = true
      found = true
    elseif type(v) == 'table' and depth < 4 and setTrue(v, key, depth + 1) then
      found = true
    end
  end
  return found
end

function MrpdMap.capabilities(defaults, writesOn)
  local caps = type(defaults) == 'table' and falsify(defaults, 1) or {}
  for _, key in ipairs(MrpdMap.TRUE_CAPS) do
    if not setTrue(caps, key, 1) then caps[key] = true end
  end
  if type(caps.writes) ~= 'table' then caps.writes = {} end
  for _, key in ipairs(MrpdMap.WRITES) do caps.writes[key] = writesOn ~= false end
  return caps
end

function MrpdMap.featureAllowed(key, writesOn)
  if type(key) ~= 'string' then return false end
  if key == 'respond_dispatch' then return writesOn ~= false end
  for _, k in ipairs(MrpdMap.TRUE_CAPS) do
    if k == key then return true end
  end
  return false
end

function MrpdMap.allow(store, key, limit, now, window)
  window = window or 60
  local e = store[key]
  if not e or now - e.at >= window then
    e = { at = now, n = 0 }
    store[key] = e
  end
  if e.n >= limit then return false end
  e.n = e.n + 1
  return true
end

function MrpdMap.callNumberIn(isCallNumber, ...)
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    if type(v) == 'table' then v = v.number or v.id end
    if isCallNumber(v) then return v end
  end
  return nil
end

return MrpdMap
