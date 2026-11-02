Commands = {}
Handlers = {}

local lastUse = {}
local gate = Pure.newGate()
local running = {}
local queue = {}
Commands.shown = {}
Commands.free = {}

local function now()
  return GetGameTimer() / 1000
end

function Commands.cooldown(src, bucket)
  lastUse[src] = lastUse[src] or {}
  local ok, left = Pure.useCooldown(lastUse[src], bucket, now(), Config.cooldowns[bucket])
  if not ok then
    Notify.player(src, L('cooldown', left), 'error')
    return false
  end
  return true
end

function Commands.cooldownReady(src, bucket)
  local ok, left = Pure.cooldown((lastUse[src] or {})[bucket], now(), Config.cooldowns[bucket] or 0)
  if not ok then Notify.player(src, L('cooldown', left), 'error') end
  return ok
end

function Commands.cooldownStart(src, bucket)
  lastUse[src] = lastUse[src] or {}
  lastUse[src][bucket] = now()
end

function Commands.usage(src, action, name)
  local key = 'cmd_' .. action .. '_example'
  if Locale[key] then return Notify.player(src, L(key, name), 'error') end
  Notify.player(src, L('usage', name), 'error')
end

function Commands.requireUnit(src)
  local p = State.peek(src)
  if p and p.unit then return p.unit end
  Notify.player(src, L('not_on_duty'), 'error')
  return nil
end

function Commands.civilian(src)
  local p = State.peek(src)
  if not (p and p.unit) then return true end
  Notify.player(src, L('civ_on_duty', p.unit.callsign, Config.commands.offduty.name), 'error')
  return false
end

function Commands.sameAccount(src, account)
  return Pure.sameAccount(Identity.getAccount(src), account)
end

function Commands.offDuty(src, account, reason)
  local res = api('DELETE', '/units/duty/{discordId}', 'units', { params = { discordId = Pure.playerSlot(account) }, query = { reason = reason }, as = account })
  if res.status == 204 or (res.problem and res.problem.code == 'not_found') then
    if Commands.sameAccount(src, account) then State.setUnit(src, nil) end
    State.release(account.discordId)
  end
  return res
end

function Commands.disconnect(account, priority)
  local res = api('POST', '/units/{discordId}/connection', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { connected = false }, as = account, priority = priority })
  if (res.status == 200 and res.data and type(res.data.unit) ~= 'table') or (res.problem and res.problem.code == 'not_found') then
    State.release(account.discordId)
  end
  return res
end

local dropping = {}

local function onlineAs(account, gone)
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    if src ~= gone and Pure.sameAccount(Identity.getAccount(src), account) then return src end
  end
  return nil
end

function Commands.lateAnswer(account, template, res)
  local src = onlineAs(account)
  if not src then return end
  State.refresh(src)
  local key, arg = Pure.lateNotice(template, res and res.data)
  Notify.player(src, L(key, arg), 'success')
end

function Commands.droppedAnswer(account, template, window)
  local src = onlineAs(account)
  if not src then return end
  State.refresh(src)
  local p = State.peek(src)
  local unit = p and p.unit
  local call
  if template == '/calls/traffic-stop' and unit and Pure.isCallNumber(unit.callNumber) then
    local res = api('GET', '/calls/{number}', 'calls', { params = { number = unit.callNumber } })
    call = res.status == 200 and res.data and res.data.call or nil
  end
  local me = { discordId = account.discordId, callsign = unit and unit.callsign }
  local key, arg = Pure.confirmLanded(template, window, unit, call, me)
  if key then return Notify.player(src, L(key, arg), 'success') end
  Notify.player(src, L('err_unanswered'), 'error')
end

function Commands.inCommand()
  return running[coroutine.running()] ~= nil
end

Http.onLate = Commands.lateAnswer
Http.onDropped = Commands.droppedAnswer
Http.inCommand = Commands.inCommand

function Commands.reportDrop(account, gone)
  local slot = Pure.playerItem(account)
  local mine = {}
  dropping[slot] = mine
  local attempt = 0
  while dropping[slot] == mine do
    local back = onlineAs(account, gone)
    if back then
      if attempt > 0 then State.refresh(back) end
      break
    end
    attempt = attempt + 1
    local res = Commands.disconnect(account, attempt > 1 and 'low' or nil)
    if Pure.dropSettled(res) then
      back = onlineAs(account, gone)
      if back and res.status == 200 then State.refresh(back) end
      break
    end
    Wait(math.floor(Pure.backoff(attempt, math.random()) * 1000))
  end
  if dropping[slot] == mine then dropping[slot] = nil end
end

Handlers.duty = function(src, args, name)
  local department, callsign = Pure.dutyArgs(args)
  if not department then return Commands.usage(src, 'duty', name) end
  local account = Identity.require(src)
  if not account then return end
  local res = api('POST', '/units/duty', 'units', { body = Pure.withPlayer(account, { department = department, callsign = callsign }), as = account })
  if res.status ~= 201 then return Notify.problem(src, res) end
  local p = State.get(src)
  p.discordId, p.account, p.membershipId = account.discordId, account, res.data.unit.membershipId
  State.setUnit(src, res.data.unit)
  State.claim(account.discordId)
  Notify.player(src, L('duty_on', res.data.unit.callsign, res.data.unit.department.abbreviation), 'success')
  if Ers then Ers.cadDuty(src, res.data.unit) end
end

Handlers.offduty = function(src)
  local account = Identity.require(src)
  if not account then return end
  local res = Commands.offDuty(src, account, 'manual')
  if res.status == 204 then
    if Ers then Ers.cadDuty(src, nil) end
    return Notify.player(src, L('duty_off'), 'success')
  end
  if res.problem and res.problem.code == 'not_found' then return Notify.player(src, L('not_on_duty'), 'error') end
  Notify.problem(src, res)
end

Handlers.status = function(src, args, name)
  local code = args[1]
  if not code then return Commands.usage(src, 'status', name) end
  local account = Identity.require(src)
  if not account then return end
  local res = api('PATCH', '/units/{discordId}/status', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { code = code }, as = account })
  if res.status ~= 200 then
    if res.problem and res.problem.code == 'validation_failed' and res.problem.detail then
      return Notify.player(src, L('status_unknown', res.problem.detail), 'error')
    end
    return Notify.problem(src, res)
  end
  State.setUnit(src, res.data.unit)
  Notify.player(src, L('status_set', res.data.unit.status.code), 'success')
end

function Commands.setPanic(src, account, active)
  local coords = active and State.readCoords(src)
  local body = active and Pure.panicBody(true, State.get(src).labels, Locations.serverPostal(coords), coords) or Pure.panicBody(false)
  local res = api('POST', '/units/{discordId}/panic', 'units', { params = { discordId = Pure.playerSlot(account) }, body = body, as = account })
  if res.status ~= 200 then
    if active and res.problem and res.problem.unanswered then return Notify.player(src, L('panic_unanswered', Config.commands.clearpanic.name), 'error') end
    return Notify.problem(src, res)
  end
  State.setUnit(src, res.data.unit)
  if not active then return Notify.player(src, L('panic_off'), 'success') end
  if res.data.callNumber then return Notify.player(src, L('panic_on', res.data.callNumber), 'alert') end
  Notify.player(src, L('panic_on_nocall'), 'alert')
end

local function panicCommand(src, action)
  local account = Identity.require(src)
  if not account then return end
  local p = State.peek(src)
  if p and p.unit and (p.unit.isPanic or action == 'clearpanic') then
    State.refresh(src)
    p = State.peek(src)
  end
  local what = Pure.panicAction(p and p.unit, action)
  if what == 'off_duty' then return Notify.player(src, L('not_on_duty'), 'error') end
  if what == 'none' then return Notify.player(src, L('panic_none'), 'info') end
  if what == 'clear' then return Commands.setPanic(src, account, false) end
  if not Commands.cooldown(src, 'panic') then return end
  Commands.setPanic(src, account, true)
end

Handlers.panic = function(src) panicCommand(src, 'panic') end
Handlers.clearpanic = function(src) panicCommand(src, 'clearpanic') end

local function locationOf(src, coords)
  local labels = Locations.fetchLabels(src)
  return Pure.locationText(labels) or L('unknown_location'), Pure.preferPostal(Locations.serverPostal(coords), labels), labels
end

local function after911(src, res, location, text, origin, coords)
  Events.awaitUnits(res.data.number, src)
  local dispatchers = api('GET', '/dispatchers/active', 'calls', { retry = false })
  local noDispatcher = dispatchers.status == 200 and dispatchers.data and dispatchers.data.active == false
  if origin == 'non_emergency' then
    Notify.player(src, L('call_311_sent', res.data.number), 'success')
    if noDispatcher then Notify.player(src, L('no_dispatch_311'), 'info') end
    return
  end
  Events.rememberCaller(res.data.number, coords)
  Notify.player(src, L('call_sent', res.data.number), 'success')
  if not noDispatcher then return end
  for _, dst in ipairs(Pure.selectRecipients('fallback911', {}, State.onDuty())) do
    Notify.player(dst, L('fallback_911', location, Pure.truncate(text, 200)), 'alert')
  end
  Notify.player(src, L('no_dispatch'), 'info')
end

local function post911(body, account)
  local res = api('POST', '/calls/911', 'calls', { body = body, as = account })
  if res.problem and res.problem.code == 'validation_failed' and body.postal then
    body.postal = nil
    res = api('POST', '/calls/911', 'calls', { body = body, as = account })
  end
  return res
end

Commands.after911 = after911
Commands.post911 = post911

local QUEUE_MAX_AGE = 540
local draining = false
local drainFailures = 0

local function queueWarn(err)
  print(('^1[statewide] 911 queue: %s^7'):format(tostring(err)))
end

local function dropNotice(item)
  if Commands.sameAccount(item.src, item.account) then Notify.player(item.src, L('queue_dropped'), 'error') end
end

local function drainStep(step)
  for i = 1, #step.dropped do dropNotice(step.dropped[i]) end
  if not step.outcome then return end
  if step.outcome == 'error' then return queueWarn(step.error) end
  local item = step.item
  if not Commands.sameAccount(item.src, item.account) then return end
  if step.outcome == 'sent' then return after911(item.src, step.result, item.location, item.text, item.origin, item.coords) end
  if not Pure.queueNotify(step.outcome) then return end
  Notify.problem(item.src, step.result)
end

local function drainOnce()
  local attempt = 0
  while #queue > 0 do
    attempt = attempt + 1
    Wait(math.floor(Pure.backoff(attempt, math.random()) * 1000))
    local step = Pure.queueStep(queue, post911, os.time(), QUEUE_MAX_AGE)
    if step.outcome and step.outcome ~= 'retry' then attempt = 0 end
    local ok, err = pcall(drainStep, step)
    if not ok then queueWarn(err) end
  end
end

local function drainQueue()
  if draining then return end
  draining = true
  local ok, err = pcall(drainOnce)
  draining = false
  if ok then
    drainFailures = 0
  else
    drainFailures = drainFailures + 1
    queueWarn(err)
  end
  if #queue == 0 then return end
  CreateThread(function()
    Wait(math.floor(Pure.backoff(drainFailures + 1, math.random()) * 1000))
    drainQueue()
  end)
end

function Commands.send911(src, args, name, action, anonymous, origin)
  local text = Pure.clean(table.concat(args, ' '), 1000)
  if not text then return Commands.usage(src, action, name) end
  local account = Identity.require(src)
  local bucket = Pure.callBucket(action)
  if not account or not Commands.cooldownReady(src, bucket) then return end
  local coords = State.readCoords(src)
  local location, postal, labels = locationOf(src, coords)
  local body = Pure.withPlayer(account, Pure.call911Body({
    text = text, location = location, postal = postal, anonymous = anonymous, origin = origin, coords = coords, zoneCode = labels and labels.zone,
    clientRef = Pure.clientRef(account.discordId, os.time(), math.random(0, 0xffffff)),
  }))
  local res = post911(body, account)
  if res.status == 201 then
    Commands.cooldownStart(src, bucket)
    return after911(src, res, location, text, origin, coords)
  end
  if not Pure.retryable(res.status) then
    local p = State.peek(src)
    local key = Pure.callRefusalKey(res.problem, p and p.unit)
    if key then return Notify.player(src, L(key, Config.commands.offduty.name, Config.commands.setciv.name), 'error') end
    return Notify.problem(src, res)
  end
  local item = { src = src, account = account, body = body, location = location, text = text, origin = origin, coords = coords, at = os.time() }
  if not Pure.queuePush(queue, item, Pure.QUEUE_MAX) then return Notify.problem(src, res) end
  Commands.cooldownStart(src, bucket)
  Notify.player(src, L('queued_911'), 'info')
  if Pure.queueActive(queue, draining) then CreateThread(drainQueue) end
end

Handlers['911'] = function(src, args, name) Commands.send911(src, args, name, '911', false) end
Handlers['911a'] = function(src, args, name)
  if Commands.civilian(src) then Commands.send911(src, args, name, '911a', true) end
end
Handlers['311'] = function(src, args, name) Commands.send911(src, args, name, '311', false, 'non_emergency') end
Handlers['311a'] = function(src, args, name)
  if Commands.civilian(src) then Commands.send911(src, args, name, '311a', true, 'non_emergency') end
end

Handlers.ts = function(src, args, name)
  local stop = Pure.trafficStopArgs(args)
  if not stop then return Commands.usage(src, 'ts', name) end
  local account = Identity.require(src)
  if not account or not Commands.requireUnit(src) or not Commands.cooldown(src, 'ts') then return end
  local body = Pure.trafficStopBody(nil, stop.plate, State.get(src).labels, State.readCoords(src), stop.occupants)
  local res = api('POST', '/calls/traffic-stop', 'calls', { body = Pure.withPlayer(account, body), as = account })
  if res.status ~= 201 then return Notify.problem(src, res) end
  Notify.player(src, L('ts_started', res.data.number), 'success')
  if res.data.vehicleReturn then Commands.showVehicle(src, res.data.vehicleReturn) end
end

function Commands.showVehicle(src, r)
  local v = r.vehicle or {}
  Notify.player(src, L('plate_return', v.plate or '?', v.color or '', v.make or '', v.model or '', v.registration or '?', v.insurance or '?'), 'info')
  if r.hits and #r.hits > 0 then Notify.player(src, L('plate_hits', table.concat(r.hits, ', ')), 'alert') end
end

Handlers.plate = function(src, args, name)
  if not args[1] then return Commands.usage(src, 'plate', name) end
  local account = Identity.require(src)
  if not account or not Commands.cooldown(src, 'plate') then return end
  local res = api('GET', '/lookup/vehicle', 'lookup', { query = { discordId = Pure.playerSlot(account), plate = table.concat(args, ' ') }, as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  local first = res.data.results and res.data.results[1]
  if not first then return Notify.player(src, L('plate_none'), 'info') end
  Commands.showVehicle(src, first)
end

Handlers.name = function(src, args, name)
  if not args[1] or not args[2] then return Commands.usage(src, 'name', name) end
  local account = Identity.require(src)
  if not account or not Commands.cooldown(src, 'name') then return end
  local res = api('GET', '/lookup/person', 'lookup', { query = { discordId = Pure.playerSlot(account), first = args[1], last = table.concat(args, ' ', 2) }, as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  if not res.data.results or #res.data.results == 0 then return Notify.player(src, L('name_none'), 'info') end
  Notify.player(src, L('name_return', res.data.summary), res.data.hit and 'alert' or 'info')
end

local vehicleAsks = {}

function Commands.askVehicle(src)
  local p = promise.new()
  vehicleAsks[src] = p
  TriggerClientEvent('statewide:client:vehicleInfo', src)
  SetTimeout(3000, function()
    if vehicleAsks[src] == p then
      vehicleAsks[src] = nil
      p:resolve({})
    end
  end)
  return Citizen.Await(p)
end

RegisterNetEvent('statewide:vehicle', function(make, model, raw)
  local src = tonumber(source)
  local p = src and vehicleAsks[src]
  if not p then return end
  vehicleAsks[src] = nil
  p:resolve({ make = make, model = model, raw = raw })
end)

local vehicleIndex

function Commands.vehicleLabels(src, vehicle)
  vehicleIndex = vehicleIndex or Pure.vehicleIndex(Vehicles, GetHashKey)
  return Pure.vehicleLabels(GetEntityModel(vehicle), vehicleIndex, function() return Commands.askVehicle(src) end, GetHashKey)
end

Handlers.regveh = function(src, args, name)
  if not Commands.civilian(src) then return end
  local account = Identity.require(src)
  if not account then return end
  local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)
  if not vehicle or vehicle == 0 then return Notify.player(src, L('regveh_no_vehicle'), 'error') end
  local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local year, rest = Pure.regvehArgs(args)
  local detected = { color = Paint[GetVehicleColours(vehicle)] }
  if not rest[2] then
    local labels = Commands.vehicleLabels(src, vehicle)
    detected.make, detected.model = labels.make, labels.model
  end
  local body = Pure.regvehBody(nil, plate, rest, detected, year)
  if not body then return Commands.usage(src, 'regveh', name) end
  local res = api('POST', '/vehicles', 'civilian', { body = Pure.withPlayer(account, body), as = account })
  if res.status ~= 201 then return Notify.problem(src, res) end
  Notify.player(src, L('regveh_done', res.data.vehicle.plate), 'success')
end

function Commands.registerAiVehicle(src, scenario)
  local ped = GetPlayerPed(src)
  local vehicle = GetVehiclePedIsIn(ped, false)
  local p = State.peek(src)
  local why = Pure.aiVehicleRefusal(p and p.unit, vehicle, vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped)
  if why == 'on_duty' then return Commands.civilian(src) end
  if why == 'no_vehicle' then return Notify.player(src, L('regveh_no_vehicle'), 'error') end
  if why == 'not_driver' then return Notify.player(src, L('aiveh_not_driver'), 'error') end
  local account = Identity.require(src)
  if not account then return end
  local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local detected = Commands.vehicleLabels(src, vehicle)
  detected.color = Paint[GetVehicleColours(vehicle)]
  local labels = Locations.fetchLabels(src)
  local body = Pure.aiVehicleBody(nil, plate, scenario, detected, labels, Pure.preferPostal(Locations.serverPostal(State.readCoords(src)), labels))
  if not body then return Notify.player(src, L('aiveh_unreadable'), 'error') end
  local res = api('POST', '/vehicles/stolen', 'civilian', { body = Pure.withPlayer(account, body), as = account })
  if res.status ~= 201 then
    local key = Pure.aiVehicleProblem(res.problem)
    if key then return Notify.player(src, L(key), 'error') end
    return Notify.problem(src, res)
  end
  Notify.player(src, L('aiveh_done', res.data.owner.name), 'success')
end

Handlers.regcarjack = function(src) Commands.registerAiVehicle(src, 'carjack') end
Handlers.regparkedveh = function(src) Commands.registerAiVehicle(src, 'parked') end

Handlers.setciv = function(src, args, name)
  local ssn = args[1] and args[1]:gsub('-', '')
  if not ssn or not ssn:match('^%d%d%d%d%d%d%d%d%d$') then return Commands.usage(src, 'setciv', name) end
  if not Commands.civilian(src) then return end
  local account = Identity.require(src)
  if not account then return end
  local res = api('PUT', '/characters/active', 'civilian', { body = Pure.withPlayer(account, { ssn = ssn }), as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  local c = res.data.character
  State.setCharacter(src, { id = c.id, ssn = c.ssn, firstName = c.firstName, lastName = c.lastName, dob = c.dob })
  Notify.player(src, L('setciv_done', c.firstName, c.lastName), 'success')
end

function Commands.activeCharacter(src)
  local p = State.get(src)
  if not p.character then State.refresh(src) end
  return p.character
end

Handlers.attach = function(src, args, name)
  local number = args[1]
  if not Pure.isCallNumber(number) then return Commands.usage(src, 'attach', name) end
  local account = Identity.require(src)
  if not account or not Commands.requireUnit(src) then return end
  local res = api('POST', '/calls/{number}/units', 'calls', { params = { number = number }, body = Pure.withPlayer(account), as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  Notify.player(src, L('attach_done', res.data.call.number), 'success')
end

Handlers.note = function(src, args, name)
  local text, why = Pure.noteText(args)
  if why == 'too_long' then return Notify.player(src, L('note_too_long', Pure.NOTE_MAX), 'error') end
  if not text then return Commands.usage(src, 'note', name) end
  local account = Identity.require(src)
  if not account or not Commands.requireUnit(src) or not Commands.cooldown(src, 'note') then return end
  State.refresh(src)
  local p = State.peek(src)
  local number = p and p.unit and p.unit.callNumber
  if not number then return Notify.player(src, L('note_no_call'), 'error') end
  local res = api('POST', '/calls/{number}/notes', 'calls', { params = { number = number }, body = Pure.withPlayer(account, { body = text }), as = account })
  if res.status ~= 201 then return Notify.problem(src, res) end
  Notify.player(src, L('note_done', number), 'success')
end

Handlers.getciv = function(src)
  local p = State.peek(src)
  local c = p and p.character
  if not c then return Notify.player(src, L('getciv_none'), 'info') end
  Notify.player(src, L('getciv_line', c.firstName, c.lastName, c.dob or '?', c.ssn or '?'), 'info')
end

Handlers.clearciv = function(src)
  if not Commands.civilian(src) then return end
  local account = Identity.require(src)
  if not account then return end
  local res = api('DELETE', '/characters/active', 'civilian', { query = { discordId = Pure.playerSlot(account) }, as = account })
  if res.status ~= 204 then return Notify.problem(src, res) end
  State.setCharacter(src, nil)
  Notify.player(src, L('clearciv_done'), 'success')
end

Handlers.tracking = function(src, args, name)
  local account = Identity.require(src)
  if not account or not Commands.requireUnit(src) then return end
  local p = State.get(src)
  local hidden = Pure.trackingArg(args[1], p.trackingHidden)
  if hidden == nil then return Commands.usage(src, 'tracking', name) end
  local res = api('PATCH', '/units/{discordId}/tracking', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { hidden = hidden }, as = account })
  if res.status ~= 200 then
    if res.problem and res.problem.code == 'permission_denied' and res.problem.reason == 'tracking_required' then return Notify.player(src, L('tracking_required'), 'error') end
    return Notify.problem(src, res)
  end
  p.trackingHidden = hidden
  Locations.forget(src)
  Notify.player(src, L(hidden and 'tracking_hidden' or 'tracking_shown'), 'success')
end

Handlers.link = function(src, args, name)
  if not Pure.identityConfig(Config.identity).allowLink then return Notify.player(src, L('link_off'), 'error') end
  local code = Pure.linkArg(args)
  if not code then return Commands.usage(src, 'link', name) end
  local license = Pure.licenseFromIdentifiers(GetPlayerIdentifiers(src))
  if not license then return Notify.player(src, L('link_no_license'), 'error') end
  if not Commands.cooldown(src, 'link') then return end
  local res = api('POST', '/players/link', 'units', { body = { license = license, code = code }, retry = false })
  if res.status ~= 200 or not res.data then
    local key = Pure.linkRefusalKey(res.problem)
    if key then return Notify.player(src, L(key), 'error') end
    return Notify.problem(src, res)
  end
  Identity.forget(src)
  State.refresh(src)
  Notify.player(src, L('link_done', Pure.truncate(res.data.name, 64) or '?'), 'success')
end

function Commands.register()
  local resolved, err = Pure.resolveCommands(Config.commands)
  if not resolved then
    print(('^1[statewide] commands not registered: %s^7'):format(err))
    return false
  end
  for _, c in ipairs(resolved) do
    local handler = Handlers[c.action]
    if handler then
      for _, name in ipairs(c.names) do
        RegisterCommand(name, function(src, args)
          if src <= 0 then return end
          local free = Commands.free[c.action]
          if free and free(src) then return end
          local ok, why, left = Pure.gateEnter(gate, src, now(), Config.cooldowns.default or 2)
          if not ok then
            if why == 'cooldown' then Notify.player(src, L('cooldown', left), 'error') end
            if why == 'busy' then Notify.player(src, L('busy'), 'error') end
            return
          end
          CreateThread(function()
            local co = coroutine.running()
            running[co] = src
            local fine, failure = pcall(handler, src, args, name)
            running[co] = nil
            Pure.gateLeave(gate, src)
            if not fine then print(('^1[statewide] /%s: %s^7'):format(name, failure)) end
          end)
        end, false)
      end
    end
  end
  return true
end

AddEventHandler('playerDropped', function()
  local src = source
  local p = State.peek(src)
  local account = Pure.accountOfState(p) or Identity.getAccount(src)
  local signOff = p and p.unit and account
  State.forget(src)
  Identity.forget(src)
  lastUse[src] = nil
  Pure.gateForget(gate, src)
  Commands.shown[src] = nil
  vehicleAsks[src] = nil
  if signOff then Http.pace(function() Commands.reportDrop(account, tonumber(src)) end, Pure.JOIN_RANK.unit) end
end)
