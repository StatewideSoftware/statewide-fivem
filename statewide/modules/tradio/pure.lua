TradioPure = {}

TradioPure.TONES = {
  'PTT', 'PTT_TRUNKED', 'PTT_PATCHED', 'PTT_END', 'PTT_END_TRUNKED', 'PTT_END_PATCHED',
  'TX_START', 'TX_START_TRUNKED', 'TX_START_PATCHED', 'TX_END', 'TX_END_TRUNKED', 'TX_END_PATCHED',
  'BEEP', 'BONK', 'CHIRP', 'ECHO', 'PANIC',
  'EMERGENCY_ENTRY', 'EMERGENCY_EXIT', 'EMERGENCY_REJECT', 'EMERGENCY_NO_ACK', 'EMERGENCY_NO_EMERGENCY',
  'CONSOLE_ACK', 'MAN_DOWN_CONTINUOUS', 'MENU_INACTIVE_EXIT', 'TOT_WARN', 'TOT_EXPIRED',
  'ALERT_A', 'ALERT_B', 'ALERT_C', 'ALERT_SIGNAL3', 'PRIORITY', 'PRIORITY_REPEAT',
  'RING_OUT', 'RING_IN', 'GUNSHOT', 'EXPLOSION',
}

TradioPure.MESSAGE_MAX = 200
TradioPure.GUARD_SECONDS = 30
TradioPure.MIN_VERSION = { 7, 0 }
TradioPure.STATUS_MAX = 48

local function clean(v, max)
  if type(v) == 'number' then v = tostring(math.tointeger(v) or v) end
  if type(v) ~= 'string' then return '' end
  v = v:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return v:sub(1, max)
end

TradioPure.isServerSource = Pure.isServerSource

function TradioPure.describe911(call, postal)
  if type(call) ~= 'table' then return nil end
  local number = clean(call.callerNumber, 32)
  if number == '' then number = 'unknown' end
  local message = clean(call.message, TradioPure.MESSAGE_MAX)
  local description = message ~= '' and ('tRadio 911 %s: %s'):format(number, message) or ('tRadio 911 %s'):format(number)
  local body = { description = description, anonymous = false, location = 'Unknown' }
  if type(postal) == 'string' and postal ~= '' then
    body.postal = postal
    body.location = ('Near postal %s'):format(postal)
  end
  return body
end

function TradioPure.lineKey(call)
  if type(call) ~= 'table' then return nil end
  local number, at = clean(call.callerNumber, 32), clean(call.createdAt, 40)
  if number == '' or at == '' then return nil end
  return number .. '|' .. at
end

local OTHER = { radio = 'cad', cad = 'radio' }

function TradioPure.loopGuard(now)
  local marks = { radio = {}, cad = {} }
  local guard = {}
  function guard.mark(origin, key)
    if marks[origin] then marks[origin][key] = now() end
  end
  function guard.suppressed(origin, key)
    local other = OTHER[origin]
    local at = other and marks[other][key]
    if not at then return false end
    if now() - at < TradioPure.GUARD_SECONDS then return true end
    marks[other][key] = nil
    return false
  end
  return guard
end

local function serverId(v)
  local n = math.tointeger(tonumber(v))
  if n and n > 0 then return n end
  return nil
end

function TradioPure.diffPanics(prev, cur)
  prev = type(prev) == 'table' and prev or {}
  local seen, added = {}, {}
  if type(cur) ~= 'table' then return added, seen end
  for key, entry in pairs(cur) do
    local sid = serverId(key)
    if sid and type(entry) == 'table' and entry.source ~= 'export' then
      seen[sid] = true
      if not prev[sid] then added[#added + 1] = sid end
    end
  end
  table.sort(added)
  return added, seen
end

local function appendUnique(out, have, list)
  if type(list) ~= 'table' then return end
  for _, f in ipairs(list) do
    local key = tostring(f)
    if (type(f) == 'string' or type(f) == 'number') and not have[key] then
      have[key] = true
      out[#out + 1] = f
    end
  end
end

function TradioPure.frequenciesFor(map, departmentCode)
  if type(map) ~= 'table' then return {} end
  local list = (departmentCode ~= nil and map[departmentCode]) or map['*']
  local out = {}
  appendUnique(out, {}, list)
  return out
end

local function sortedKeys(map)
  local keys = {}
  for k in pairs(map) do
    if type(k) == 'string' then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

function TradioPure.allFrequencies(map)
  local out, have = {}, {}
  if type(map) ~= 'table' then return out end
  for _, k in ipairs(sortedKeys(map)) do appendUnique(out, have, map[k]) end
  return out
end

function TradioPure.validateTones(tones, catalog)
  local known, bad = {}, {}
  for _, key in ipairs(catalog or {}) do known[key] = true end
  if type(tones) ~= 'table' then return bad end
  for _, event in ipairs(sortedKeys(tones)) do
    local entry = tones[event]
    local tone = type(entry) == 'table' and entry.tone or nil
    if tone and not known[tone] then bad[#bad + 1] = ('%s=%s'):format(event, tostring(tone)) end
  end
  return bad
end

function TradioPure.toneTargets(event, cfg)
  if type(cfg) ~= 'table' or type(cfg.tones) ~= 'table' then return nil end
  local entry = cfg.tones[event]
  if type(entry) ~= 'table' or type(entry.tone) ~= 'string' or entry.tone == '' then return nil end
  local frequencies
  if type(entry.departments) == 'table' and #entry.departments > 0 then
    frequencies = {}
    local have = {}
    for _, code in ipairs(entry.departments) do appendUnique(frequencies, have, TradioPure.frequenciesFor(cfg.frequencies, code)) end
  else
    frequencies = TradioPure.allFrequencies(cfg.frequencies)
  end
  return { tone = entry.tone, frequencies = frequencies }
end

function TradioPure.signalFrequencies(map, signal)
  if type(signal) ~= 'table' then return {} end
  if signal.scope == 'department' then return TradioPure.frequenciesFor(map, signal.departmentCode) end
  return TradioPure.allFrequencies(map)
end

function TradioPure.listsPlayer(list, src)
  if type(list) ~= 'table' then return false end
  if serverId(list[src]) == src then return true end
  for _, v in pairs(list) do
    if serverId(v) == src then return true end
  end
  return false
end

function TradioPure.versionGate(v)
  local major, minor = tostring(v or ''):match('^v?(%d+)%.(%d+)')
  if not major then return 'unknown' end
  major, minor = tonumber(major), tonumber(minor)
  local want = TradioPure.MIN_VERSION
  if major ~= want[1] then return major > want[1] and 'ok' or 'old' end
  return minor >= want[2] and 'ok' or 'old'
end

function TradioPure.aiCall(payload)
  if type(payload) ~= 'table' then return nil end
  local number = clean(payload.number, 32)
  if number == '' then return nil end
  local nature = clean(payload.nature, TradioPure.MESSAGE_MAX)
  local message = nature ~= '' and ('911 call %s: %s'):format(number, nature) or ('911 call %s'):format(number)
  local place, postal = clean(payload.location, 120), clean(payload.postal, 16)
  local location
  if place ~= '' and postal ~= '' then
    location = ('%s (postal %s)'):format(place, postal)
  elseif place ~= '' then
    location = place
  elseif postal ~= '' then
    location = ('Postal %s'):format(postal)
  end
  local out = { source = 'CAD', message = message:sub(1, TradioPure.MESSAGE_MAX), location = location }
  out.priority = math.type(payload.priority) == 'integer' and payload.priority or nil
  if type(payload.x) == 'number' and type(payload.y) == 'number' then out.x, out.y = payload.x, payload.y end
  return out
end

function TradioPure.statusValue(v)
  local out = clean(v, TradioPure.STATUS_MAX)
  if out == '' then return nil end
  return out
end

function TradioPure.sameStatus(a, b)
  a, b = TradioPure.statusValue(a), TradioPure.statusValue(b)
  return a ~= nil and b ~= nil and a:lower() == b:lower()
end

local function ackName(v)
  if type(v) == 'table' then
    for _, k in ipairs({ 'callsign', 'name', 'by' }) do
      local name = clean(v[k], 64)
      if name ~= '' then return name end
    end
    return ''
  end
  if type(v) == 'string' then return clean(v, 64) end
  return ''
end

function TradioPure.ackedBy(entry)
  if type(entry) ~= 'table' then return nil end
  local a = entry.acked
  if a ~= nil and a ~= false and a ~= 0 and a ~= '' then return ackName(a) end
  if entry.phase == 'acked' then return '' end
  return nil
end

function TradioPure.diffAcks(prev, cur)
  prev = type(prev) == 'table' and prev or {}
  local seen, added = {}, {}
  if type(cur) ~= 'table' then return added, seen end
  for key, entry in pairs(cur) do
    local sid = serverId(key)
    local by = sid and TradioPure.ackedBy(entry)
    if by then
      seen[sid] = true
      if not prev[sid] then added[#added + 1] = { sid = sid, by = by } end
    end
  end
  table.sort(added, function(a, b) return a.sid < b.sid end)
  return added, seen
end

return TradioPure
