ErsMap = {}

ErsMap.RAW_MAX = 256
ErsMap.KEYS_MAX = 200

ErsMap.LICENSE_FIELDS = { 'License_Car', 'License_Bike', 'License_Truck', 'License_Boat', 'License_Pilot' }

local TRUE_WORDS = { ['true'] = true, yes = true, y = true, ['1'] = true, valid = true }
local FALSE_WORDS = { ['false'] = true, no = true, n = true, ['0'] = true, invalid = true }

function ErsMap.bool(v)
  if type(v) == 'boolean' then return v end
  if type(v) == 'number' then return v ~= 0 end
  if type(v) ~= 'string' then return nil end
  local w = v:lower():gsub('^%s+', ''):gsub('%s+$', '')
  if TRUE_WORDS[w] then return true end
  if FALSE_WORDS[w] then return false end
  return nil
end

function ErsMap.oversized(t)
  if type(t) ~= 'table' then return true end
  local n = 0
  for k, v in pairs(t) do
    n = n + 1
    if n > ErsMap.KEYS_MAX then return true end
    if type(k) == 'string' and #k > ErsMap.RAW_MAX then return true end
    if type(v) == 'string' and #v > ErsMap.RAW_MAX then return true end
  end
  return false
end

local function text(v, max)
  if type(v) == 'number' then v = tostring(v) end
  if type(v) ~= 'string' or #v > ErsMap.RAW_MAX then return nil end
  return Pure.clean(v, max)
end
ErsMap.text = text

local STATUS_WORDS = {
  { 'revoked', 'revoked' }, { 'stolen', 'revoked' }, { 'suspend', 'suspended' }, { 'disqualif', 'suspended' },
  { 'expired', 'expired' }, { 'valid', 'valid' }, { 'international', 'valid' }, { 'active', 'valid' },
}

function ErsMap.licenseStatus(word, isValid)
  local status
  if type(word) == 'string' then
    local w = word:lower()
    if w:find('invalid', 1, true) or w:find('none', 1, true) or w:find('no licen', 1, true) then
      status = w:find('invalid', 1, true) and 'suspended' or nil
    else
      for _, pair in ipairs(STATUS_WORDS) do
        if w:find(pair[1], 1, true) then status = pair[2] break end
      end
    end
  elseif word == true then
    status = 'valid'
  end
  local valid = ErsMap.bool(isValid)
  if status == nil and valid == true then status = 'valid' end
  if status == 'valid' and valid == false then status = 'suspended' end
  return status
end

function ErsMap.licenses(ped, codes)
  local out = {}
  for _, field in ipairs(ErsMap.LICENSE_FIELDS) do
    local code = codes and codes[field]
    if type(code) == 'string' and code:match('^[%w_%-]+$') and #code <= 16 then
      local status = ErsMap.licenseStatus(ped[field], ped[field .. '_Is_Valid'])
      if status then out[#out + 1] = { code = code, status = status } end
    end
  end
  return out
end

local function realDate(y, m, d)
  if not y or not m or not d or y < 1900 or y > 2100 or m < 1 or m > 12 or d < 1 then return nil end
  local days = { 31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if d > days[m] then return nil end
  return ('%04d-%02d-%02d'):format(y, m, d)
end

function ErsMap.dob(v, order)
  if type(v) ~= 'string' or #v > 32 then return nil end
  local y, m, d = v:match('^%s*(%d%d%d%d)[-/.](%d%d?)[-/.](%d%d?)')
  if y then return realDate(tonumber(y), tonumber(m), tonumber(d)) end
  local a, b, c = v:match('^%s*(%d%d?)[-/.](%d%d?)[-/.](%d%d%d%d)')
  if not a then return nil end
  a, b, c = tonumber(a), tonumber(b), tonumber(c)
  if order == 'mdy' then return realDate(c, a, b) or realDate(c, b, a) end
  return realDate(c, b, a) or realDate(c, a, b)
end

function ErsMap.flags(v)
  local out, seen = {}, {}
  local function add(s)
    local f = text(s, 40)
    if f and not seen[f:lower()] and #out < 8 then
      seen[f:lower()] = true
      out[#out + 1] = f
    end
  end
  if type(v) == 'string' then
    for part in v:gmatch('[^,;|]+') do add(part) end
  elseif type(v) == 'table' then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    for _, k in ipairs(keys) do
      local x = v[k]
      if type(k) == 'number' then
        if type(x) == 'string' then add(x) elseif type(x) == 'table' then add(x.label or x.name or x.text) end
      elseif type(k) == 'string' and (x == true or ErsMap.bool(x) == true) then
        add(k)
      elseif type(k) == 'string' and type(x) == 'table' and (x.active == true or x.enabled == true) then
        add(x.label or k)
      end
    end
  end
  return out
end

function ErsMap.person(ped, cfg)
  if ErsMap.oversized(ped) then return nil, 'shape' end
  cfg = cfg or {}
  local first, last = text(ped.FirstName, 40), text(ped.LastName, 40)
  local dob = ErsMap.dob(ped.DOB, cfg.dateOrder)
  if not first or not last or utf8.len(first) < 2 or utf8.len(last) < 2 then return nil, 'name' end
  if not dob then return nil, 'dob' end
  local postal = text(ped.PostalCode, 10)
  if postal and not postal:match('^[%w%-]+$') then postal = nil end
  return {
    firstName = first,
    lastName = last,
    dob = dob,
    gender = text(ped.Gender, 20),
    address = text(ped.Address, 120),
    city = text(ped.City, 40),
    postal = postal,
    phone = text(ped.PhoneNumber, 20),
    licenses = ErsMap.licenses(ped, cfg.licenses),
    flags = ErsMap.flags(ped.FlagsOrMarkers),
  }
end

function ErsMap.plate(v)
  if type(v) ~= 'string' or #v > 32 then return nil end
  local p = v:upper():gsub('[^A-Z0-9]', '')
  if p == '' or #p > 8 then return nil end
  return p
end

function ErsMap.ownerName(v)
  local name = text(v, 81)
  if not name then return nil end
  local first, last = name:match('^(%S+)%s+(.+)$')
  first, last = text(first, 40), text(last, 40)
  if not first or not last then return nil end
  return { firstName = first, lastName = last }
end

function ErsMap.vehicle(veh)
  if ErsMap.oversized(veh) then return nil, 'shape' end
  local plate = ErsMap.plate(veh.license_plate)
  if not plate then return nil, 'plate' end
  local make, model, color = text(veh.make, 40), text(veh.model, 40), text(veh.color, 40)
  if not make or not model or not color then return nil, 'vehicle' end
  local year = tonumber(veh.build_year)
  if year and (year ~= math.floor(year) or year < 1900 or year > 2100) then year = nil end
  local tax, mot = ErsMap.bool(veh.tax), ErsMap.bool(veh.mot)
  local registration
  if tax == false or mot == false then registration = 'expired' elseif tax == true or mot == true then registration = 'valid' end
  local bolo
  if ErsMap.bool(veh.bolo) == true then
    bolo = text(veh.bolo_description, 500) or 'Flagged by ERS'
    if #bolo < 5 then bolo = 'BOLO: ' .. bolo end
  end
  return {
    plate = plate,
    make = make,
    model = model,
    color = color,
    year = year,
    owner = ErsMap.ownerName(veh.owner_name),
    insured = ErsMap.bool(veh.insurance),
    registration = registration,
    stolen = ErsMap.bool(veh.stolen) == true,
  }, nil, bolo
end

function ErsMap.coords(v)
  if v == nil then return nil end
  local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
  if not ok or type(x) ~= 'number' or type(y) ~= 'number' then return nil end
  local pos = Pure.position({ x = x, y = y })
  if pos and type(z) == 'number' and z == z and z > -1000 and z < 3000 then pos.z = z end
  return pos
end

local COORD_KEYS = { 'Coordinates', 'coordinates', 'Coords', 'coords', 'Location', 'location', 'Position', 'position' }

function ErsMap.callout(data)
  if ErsMap.oversized(data) then return nil, 'shape' end
  local nature = text(data.CalloutName, 60) or text(data.calloutName, 60) or text(data.Name, 60) or text(data.name, 60)
  if not nature then return nil, 'nature' end
  local pos
  for _, k in ipairs(COORD_KEYS) do
    pos = ErsMap.coords(data[k])
    if pos then break end
  end
  local description = text(data.Description, 2000) or text(data.description, 2000)
  local id = text(data.calloutId, 64) or text(data.CalloutId, 64) or text(data.id, 64)
  return { nature = nature, description = description, pos = pos, id = id }
end

function ErsMap.callBody(c, discordId, labels, priority)
  local location = Pure.locationText(labels)
  if not location or #location < 3 then location = 'Unknown location' end
  return {
    nature = c.nature,
    priority = (priority == 1 or priority == 2 or priority == 3) and priority or 2,
    location = location,
    postal = labels and labels.postal,
    description = c.description,
    origin = 'ers',
    x = c.pos and c.pos.x,
    y = c.pos and c.pos.y,
    zoneCode = labels and labels.zone,
    units = { discordId },
  }
end

ErsMap.SERVICES = { police = true, fire = true, ambulance = true, tow = true }
ErsMap.MEDICAL = { EMS = true, FIRE = true }

function ErsMap.dutyDepartment(dutySync, service)
  if type(dutySync) ~= 'table' or not ErsMap.SERVICES[service] then return nil end
  local d = dutySync[service]
  if type(d) ~= 'string' or not d:match('^[%w%-_ ]+$') or #d > 60 then return nil end
  return d
end

function ErsMap.serviceFor(dutySync, abbreviation)
  if type(dutySync) ~= 'table' or type(abbreviation) ~= 'string' then return nil end
  local want = abbreviation:upper()
  for _, s in ipairs({ 'police', 'fire', 'ambulance', 'tow' }) do
    local d = dutySync[s]
    if type(d) == 'string' and d:upper() == want then return s end
  end
  return nil
end

function ErsMap.mode(setting, state)
  if setting == false or setting == 'off' then return 'off' end
  if setting == true or setting == 'on' then return 'on' end
  if state == 'started' or state == 'starting' then return 'on' end
  return 'absent'
end

function ErsMap.offerReason(ok, reason)
  if ok then return nil end
  local r = type(reason) == 'string' and reason:gsub('[^%w_:%. %-]', ''):sub(1, 80) or ''
  if r == '' then return 'unknown' end
  return r
end

return ErsMap
