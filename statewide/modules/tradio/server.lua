Tradio = {}

local cfg = Config.tradio
local T = TradioPure
local EXPORTS = 'tRadio'
local CAD_RESOURCES = { 'lacore', 'SonoranCAD', 'ImperialCAD', 'wasabi_mdt', 'tk_mdt', 'ps-mdt' }
local failed = {}
local ready = false
local warned = {}
local lines, gone, bridged = {}, {}, {}
local capNotedAt
local panicSeen, panicCooldown, mirrored, callsigns = {}, {}, {}, {}
local played = {}
local created, relayed = {}, {}
local onRadio = {}
local ackSeen, panicCall = nil, {}
local RELAYED_MAX = 512
local PLAYED_SECONDS = 600
local PLAYED_MAX = 256
local EXPIRE_SECONDS = 300
local FORGET_SECONDS = 3600
local PENDING_WAIT_MS = 250
local PENDING_TRIES = 40

local function clock()
  return GetGameTimer() / 1000
end

local guard = T.loopGuard(clock)

local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(line)
end

function Tradio.call(name, ...)
  local args = table.pack(...)
  local ok, res = pcall(function() return exports[EXPORTS][name](exports[EXPORTS], table.unpack(args, 1, args.n)) end)
  if ok then return res end
  if not failed[name] then
    failed[name] = true
    print(('^1%s^7'):format(L('tradio_export_failed', name, tostring(res))))
  end
  return nil
end

function Tradio.ready()
  return ready
end

local function checkConflicts()
  local ours = Config.commands['911']
  if ours and ours.enabled then
    local ok, list = pcall(GetRegisteredCommands)
    for _, cmd in ipairs(ok and type(list) == 'table' and list or {}) do
      if type(cmd) == 'table' and cmd.name == ours.name and cmd.resource == cfg.resourceName then
        warnOnce('clash', '^3' .. L('tradio_911_clash', ours.name) .. '^7')
      end
    end
  end
  for _, name in ipairs(CAD_RESOURCES) do
    if GetResourceState(name) == 'started' then warnOnce('cad:' .. name, '^3' .. L('tradio_cad_mirror', name) .. '^7') end
  end
end

local function refresh()
  local was = ready
  ready = false
  if not Modules.active.tradio then return end
  if GetResourceState(cfg.resourceName) ~= 'started' then
    return warnOnce('idle', '^3' .. L('tradio_idle', cfg.resourceName) .. '^7')
  end
  local version = GetResourceMetadata(cfg.resourceName, 'version', 0)
  local gate = T.versionGate(version)
  if gate == 'old' then
    return warnOnce('old:' .. tostring(version), '^3' .. L('tradio_old', tostring(version)) .. '^7')
  end
  if gate == 'unknown' then warnOnce('unknown', '^3' .. L('tradio_unknown_version', cfg.resourceName) .. '^7') end
  ready = true
  checkConflicts()
  if not was and Tradio.started then Tradio.started() end
end

local function note(number, body)
  return api('POST', '/calls/{number}/notes', 'calls', { params = { number = number }, body = { body = body }, retry = false })
end

local function settled(entry)
  for _ = 1, PENDING_TRIES do
    if not entry.pending then break end
    Wait(PENDING_WAIT_MS)
  end
  return entry.number and entry or nil
end

local function underCap()
  local now = clock()
  if Pure.windowAllow(bridged, now, tonumber(cfg.bridgePerMinute) or 10, 60) then return true end
  return false, not capNotedAt or now - capNotedAt >= 60
end

local function point(v)
  if v == nil or type(v) == 'string' then return nil end
  local ok, x, y = pcall(function() return v.x, v.y end)
  if ok and type(x) == 'number' and type(y) == 'number' then return { x = x, y = y } end
  return nil
end

local function bridge(c)
  local key = T.lineKey(c)
  if not key or gone[key] then return nil end
  if lines[key] then return settled(lines[key]) end
  local body = T.describe911(c, Locations.serverPostal(point(c.coords)))
  local caller = Pure.callerKey(c.callerNumber)
  local open = Callers.find(caller)
  if open then
    lines[key] = { number = open, at = clock(), created = false }
    Callers.touch(caller)
    note(open, body.description)
    return lines[key]
  end
  local ok, tell = underCap()
  if not ok then
    if tell then
      capNotedAt = clock()
      print('^3' .. L('tradio_911_cap', tostring(c.callerNumber)) .. '^7')
    end
    return nil
  end
  local entry = { at = clock(), created = true, pending = true }
  lines[key] = entry
  local res = api('POST', '/calls/911', 'calls', { body = body, retry = false })
  entry.pending = nil
  if res.status ~= 201 or not res.data or type(res.data.number) ~= 'string' then
    lines[key] = nil
    return nil
  end
  entry.number = res.data.number
  created[entry.number] = clock()
  Callers.open(caller, entry.number)
  return entry
end

local function answered(c)
  local entry = bridge(c)
  if not entry or entry.answered then return end
  entry.answered = true
  api('PATCH', '/calls/{number}', 'calls', { params = { number = entry.number }, body = { opened = true }, retry = false })
end

local function ended(c)
  local key = T.lineKey(c)
  local entry = key and lines[key]
  if not entry then return end
  entry = settled(entry)
  lines[key], gone[key] = nil, clock()
  if entry and entry.created then note(entry.number, L('tradio_911_ended')) end
end

function Tradio.sweep()
  local now = clock()
  for key, entry in pairs(lines) do
    if not entry.pending and not entry.answered and now - entry.at >= EXPIRE_SECONDS then
      lines[key], gone[key] = nil, now
      if entry.created and entry.number then note(entry.number, L('tradio_911_expired')) end
    elseif entry.answered and now - entry.at >= FORGET_SECONDS then
      lines[key] = nil
    end
  end
  for key, at in pairs(gone) do
    if now - at >= FORGET_SECONDS then gone[key] = nil end
  end
  for number, at in pairs(created) do
    if now - at >= FORGET_SECONDS then created[number] = nil end
  end
end

local function radioPanic(src)
  if guard.suppressed('radio', src) then return end
  local p = State.peek(src)
  if not (p and p.unit) or p.unit.isPanic then return end
  local account = Identity.getAccount(src)
  if not account then return end
  if not Pure.useCooldown(panicCooldown, src, clock(), tonumber(Config.cooldowns.panic) or 30) then return end
  guard.mark('radio', src)
  CreateThread(function()
    local ok, err = pcall(Commands.setPanic, src, account, true)
    if not ok then print(('^1[statewide] tRadio panic: %s^7'):format(err)) end
  end)
end

local function ackNote(src, by)
  local p = State.peek(src)
  local unit = p and p.unit
  if not unit then return end
  local number = panicCall[src] or (unit.isPanic and unit.callNumber)
  if type(number) ~= 'string' or number == '' then return end
  local sign = type(unit.callsign) == 'string' and unit.callsign ~= '' and unit.callsign or tostring(src)
  local body = by ~= '' and L('tradio_panic_acked', sign, by) or L('tradio_panic_acked_radio', sign)
  CreateThread(function()
    local ok, err = pcall(note, number, body)
    if not ok then print(('^1[statewide] tRadio ack: %s^7'):format(err)) end
  end)
end

local function acks(cur)
  if cfg.ackNotes ~= true then return end
  local added, seen = T.diffAcks(ackSeen, cur)
  local primed = ackSeen ~= nil
  ackSeen = seen
  if not primed then return end
  for _, a in ipairs(added) do ackNote(a.sid, a.by) end
end

function Tradio.poll()
  if not ready then return end
  local cur = {}
  for _, f in ipairs(T.allFrequencies(cfg.frequencies)) do
    local meta = Tradio.call('getChannelPanicMeta', f)
    if type(meta) ~= 'table' then return end
    for sid, entry in pairs(meta) do cur[sid] = entry end
  end
  local added
  added, panicSeen = T.diffPanics(panicSeen, cur)
  for _, src in ipairs(added) do radioPanic(src) end
  acks(cur)
end

local function channelOf(src, unit)
  for _, f in ipairs(T.allFrequencies(cfg.frequencies)) do
    if T.listsPlayer(Tradio.call('getAllUsersInChannel', f), src) then return f end
  end
  local dept = unit and unit.department and unit.department.abbreviation
  return T.frequenciesFor(cfg.frequencies, dept)[1]
end

local function eachPlayer(payload, fn)
  if type(payload) ~= 'table' then return end
  for src, p in pairs(State.all()) do
    if Pure.namesPlayer(payload.membershipId, payload.discordId, p) then fn(tonumber(src), p) end
  end
end

local function cadPanic(payload)
  eachPlayer(payload, function(src, p)
    if type(payload.callNumber) == 'string' and payload.callNumber ~= '' then panicCall[src] = payload.callNumber end
    if guard.suppressed('cad', src) then return end
    local f = channelOf(src, p.unit)
    if not f then return end
    guard.mark('cad', src)
    mirrored[src] = f
    Tradio.call('setChannelPanic', f, src, true, { mode = 'alarm' })
  end)
end

local function cadPanicCleared(payload)
  eachPlayer(payload, function(src, p)
    panicCall[src] = nil
    local f = mirrored[src] or channelOf(src, p.unit)
    mirrored[src] = nil
    if f then Tradio.call('setChannelPanic', f, src, false) end
  end)
end

local function syncCallsign(src, unit)
  local sign = unit and unit.callsign
  if type(sign) == 'string' and sign ~= '' then
    if callsigns[src] == sign then return end
    callsigns[src] = sign
    Tradio.call('setCallsign', src, sign)
  elseif not unit and callsigns[src] then
    callsigns[src] = nil
    Tradio.call('setCallsign', src, nil)
  end
end

local function codeOf(unit)
  return T.statusValue(unit and type(unit.status) == 'table' and unit.status.code)
end

local function pushStatus(src, unit)
  if cfg.statusSync ~= true then return end
  local code = codeOf(unit)
  if not code then
    onRadio[src] = nil
    return
  end
  if onRadio[src] == nil then onRadio[src] = T.statusValue(Tradio.call('getUnitStatus', src)) or false end
  if T.sameStatus(onRadio[src], code) then return end
  onRadio[src] = code
  Tradio.call('setUnitStatus', src, code)
end

local function unitChanged(src, unit)
  if not ready or not src then return end
  syncCallsign(src, unit)
  pushStatus(src, unit)
end

local function radioStatus(serverId, value)
  if cfg.statusSync ~= true then return end
  local src = math.tointeger(tonumber(serverId))
  value = T.statusValue(value)
  if not src or src <= 0 or not value then return end
  if T.sameStatus(onRadio[src], value) then return end
  local p = State.peek(src)
  if not (p and p.unit) then return end
  onRadio[src] = value
  if T.sameStatus(codeOf(p.unit), value) then return end
  local account = Identity.getAccount(src)
  if not account then return end
  local res = api('PATCH', '/units/{discordId}/status', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { code = value }, as = account, retry = false })
  if res.status == 200 and res.data and type(res.data.unit) == 'table' then return State.setUnit(src, res.data.unit) end
  local why = res.problem and (res.problem.code or res.problem.detail) or tostring(res.status)
  warnOnce('status:' .. src .. ':' .. value, '^3' .. L('tradio_status_refused', value, src, tostring(why)) .. '^7')
end

function Tradio.started()
  for src, p in pairs(State.all()) do
    if p.unit then unitChanged(tonumber(src), p.unit) end
  end
end

local function once(key)
  return Pure.useKeyedCooldown(played, key, clock(), PLAYED_SECONDS, PLAYED_MAX)
end

local function playTone(event, key, frequencies)
  local target = T.toneTargets(event, cfg)
  if not target or not once(event .. ':' .. key) then return end
  for _, f in ipairs(frequencies or target.frequencies) do Tradio.call('playToneOnChannel', f, target.tone) end
end

local function priorityCall(payload)
  if type(payload) ~= 'table' or payload.priority ~= 1 or type(payload.number) ~= 'string' then return end
  playTone('call.p1', payload.number)
end

local function call911(payload)
  if type(payload) ~= 'table' or type(payload.number) ~= 'string' then return end
  playTone('call.911', payload.number)
end

local function bridging()
  for _, entry in pairs(lines) do
    if entry.pending then return true end
  end
  return false
end

local function relay(payload)
  if cfg.aiRelay ~= true then return end
  local c = T.aiCall(payload)
  if not c then return end
  for _ = 1, PENDING_TRIES do
    if not bridging() then break end
    Wait(PENDING_WAIT_MS)
  end
  if created[payload.number] then return end
  if not Pure.useKeyedCooldown(relayed, payload.number, clock(), FORGET_SECONDS, RELAYED_MAX) then return end
  if c.x then
    c.coords = vector3(c.x, c.y, 0.0)
    c.x, c.y = nil, nil
  end
  TriggerEvent('tradio:ai:call', c)
end

local function signal(payload, active)
  if type(payload) ~= 'table' or type(payload.signalId) ~= 'string' then return end
  local key = (active and 'on:' or 'off:') .. payload.signalId
  local frequencies = T.signalFrequencies(cfg.frequencies, payload)
  if active then playTone('signal.declared', payload.signalId, frequencies) end
  local name = cfg.signalAlert
  if type(name) ~= 'string' or name == '' or not once('alert:' .. key) then return end
  for _, f in ipairs(frequencies) do Tradio.call('setAlertOnChannel', f, active == true, name) end
end

local function fromServer(label, fn)
  return function(payload, extra)
    if not T.isServerSource(source) or not ready then return end
    CreateThread(function()
      local ok, err = pcall(fn, payload, extra)
      if not ok then print(('^1[statewide] tRadio %s: %s^7'):format(label, err)) end
    end)
  end
end

local function every(seconds, fn)
  CreateThread(function()
    while true do
      Wait(math.floor(seconds * 1000))
      if ready then
        local ok, err = pcall(fn)
        if not ok then print(('^1[statewide] tRadio: %s^7'):format(err)) end
      end
    end
  end)
end

function Tradio.attach()
  AddEventHandler('tradio:911:noDispatcherOnline', fromServer('911', bridge))
  AddEventHandler('tradio:911:answered', fromServer('911', answered))
  AddEventHandler('tradio:911:ended', fromServer('911', ended))
  AddEventHandler('statewide:panic', fromServer('panic', cadPanic))
  AddEventHandler('statewide:panicCleared', fromServer('panic', cadPanicCleared))
  AddEventHandler('statewide:priorityCall', fromServer('tone', priorityCall))
  AddEventHandler('statewide:911', fromServer('tone', call911))
  AddEventHandler('statewide:911', fromServer('relay', relay))
  AddEventHandler('statewide:signal', fromServer('alert', signal))
  AddEventHandler('tradio:ai:unitStatusChanged', fromServer('status', radioStatus))
  State.onUnitChange(unitChanged)
  AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    panicCooldown[src], mirrored[src], onRadio[src], panicCall[src] = nil, nil, nil, nil
    if callsigns[src] then
      callsigns[src] = nil
      if ready then Tradio.call('setCallsign', src, nil) end
    end
  end)
  every(15, Tradio.sweep)
  every(math.max(1, tonumber(cfg.panicPollSeconds) or 2), Tradio.poll)
end

function Tradio.register()
  for _, bad in ipairs(T.validateTones(cfg.tones, T.TONES)) do
    print('^3' .. L('tradio_bad_tone', bad) .. '^7')
  end
  AddEventHandler('onResourceStart', function(name)
    if name == cfg.resourceName then refresh() end
  end)
  AddEventHandler('onResourceStop', function(name)
    if name ~= cfg.resourceName then return end
    ready = false
    for k in pairs(callsigns) do callsigns[k] = nil end
    for k in pairs(mirrored) do mirrored[k] = nil end
    for k in pairs(onRadio) do onRadio[k] = nil end
    panicSeen, ackSeen = {}, nil
  end)
  Tradio.attach()
  refresh()
end

if type(cfg) == 'table' and cfg.enabled == true then
  Modules.resolve('tradio', Tradio.register, L('tradio_absent', cfg.resourceName))
end
