Ers = { calls = {}, RESOURCE = 'night_ers' }

local cfg = Config.ers
local lastUse, keyed, warnedAt, busy, pursuit, shift = {}, {}, {}, {}, {}, {}
local seen = { people = {}, plates = {}, n = 0 }
local SEEN_MAX = 2000
local offers = {}
local OFFER_GRACE_MS = 5000

local function now()
  return GetGameTimer() / 1000
end

local function warn(src, what)
  local t = now()
  if warnedAt[src] and t - warnedAt[src] < 60 then return end
  warnedAt[src] = t
  print(('^3[statewide] ERS event dropped for player %s: %s^7'):format(tostring(src), Pure.truncate(what, 80)))
end

local function officer(src)
  local p = State.peek(src)
  local account = Identity.getAccount(src)
  if not account or not (p and p.unit) then return nil end
  return p, account
end

local function onShift(src, service)
  local current = shift[src]
  if current == false then return false end
  return current == nil or service == nil or current == service
end

local function lawUnit(p)
  return p.unit.department ~= nil and p.unit.department.type == 'LEO'
end

local function allowed(src, bucket, seconds)
  lastUse[src] = lastUse[src] or {}
  return (Pure.useCooldown(lastUse[src], bucket, now(), seconds or cfg.cooldown))
end

local function firstSight(src, key)
  keyed[src] = keyed[src] or {}
  return (Pure.useKeyedCooldown(keyed[src], key, now(), 30, Pure.KEYED_COOLDOWN_MAX))
end

local function serial(src, fn, ...)
  if not Modules.active.ers then return end
  local args = table.pack(...)
  CreateThread(function()
    local deadline = GetGameTimer() + 15000
    while busy[src] and GetGameTimer() < deadline do Wait(50) end
    busy[src] = true
    local ok, err = pcall(fn, src, table.unpack(args, 1, args.n))
    busy[src] = nil
    if not ok then print(('^1[statewide] ERS: %s^7'):format(err)) end
  end)
end

local function fromClient(name, fn)
  RegisterNetEvent(name, function(...)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    serial(src, fn, ...)
  end)
end

local function fromServer(name, fn)
  AddEventHandler(name, function(target, ...)
    local origin = tonumber(source)
    local src = tonumber(target)
    if origin and origin > 0 and src ~= origin then return warn(origin, name .. ' for another player') end
    if not src or src <= 0 then return end
    serial(src, fn, ...)
  end)
end

local function slot(src)
  Ers.calls[src] = Ers.calls[src] or {}
  return Ers.calls[src]
end

local function gone(res)
  local code = res.problem and res.problem.code
  return code == 'call_closed' or code == 'not_found'
end

function Ers.note(number, account, text)
  if not number then return end
  local body = account and Pure.withPlayer(account, { body = text }) or { body = text }
  return api('POST', '/calls/{number}/notes', 'calls', { params = { number = number }, body = body, as = account })
end

function Ers.close(number)
  local res = api('POST', '/calls/{number}/close', 'calls', { params = { number = number }, body = { disposition = cfg.disposition, note = L('ers_close_note') } })
  if res.problem and res.problem.code == 'validation_failed' then
    print(('^3[statewide] ERS could not close %s: set Config.ers.disposition to a disposition in the CAD (now %s).^7'):format(number, tostring(cfg.disposition)))
  end
  return res
end

local function setStatus(src, account, body)
  local res = api('PATCH', '/units/{discordId}/status', 'units', { params = { discordId = Pure.playerSlot(account) }, body = body, as = account })
  if res.status == 200 and res.data then State.setUnit(src, res.data.unit) end
  return res
end

local function unsure(before, from)
  return { before = before, from = from, to = os.time() }
end

local function adopt(p, account, s, field, want)
  local pending = s[field]
  if pending == nil then return nil end
  s[field] = nil
  local current = p and p.unit and p.unit.callNumber
  if not current or current == pending.before then return nil end
  local res = api('GET', '/calls/{number}', 'calls', { params = { number = current } })
  local call = res.status == 200 and type(res.data) == 'table' and res.data.call or nil
  local me = { discordId = account and account.discordId, callsign = p.unit.callsign }
  return Pure.adoptCall(pending.before, current, call, want, pending, me)
end

local function calloutNumber(p, account, s)
  if not s.callout then s.callout = adopt(p, account, s, 'calloutUnsure', 'ers') end
  return s.callout
end

local function offerAnswer(src, o, body)
  body.offerId = o.offerId
  local params = { discordId = Pure.playerSlot(o.account) }
  local res = api('POST', '/units/{discordId}/ers-offer', 'units', { params = params, as = o.account, body = body })
  if body.stage == nil or not (res.problem and res.problem.code == 'validation_failed') then return end
  api('POST', '/units/{discordId}/ers-offer', 'units', { params = params, as = o.account, body = { offerId = o.offerId, ok = body.ok, reason = body.reason } })
end

local function offerAccepted(src, calloutId)
  local o = offers[src]
  if not o or (o.calloutId and calloutId and o.calloutId ~= calloutId) then return end
  o.accepted = true
  if not o.delivered then return end
  offers[src] = nil
  offerAnswer(src, o, { ok = true, stage = 'accepted' })
end

local function accepted(src, data)
  local c, why = ErsMap.callout(data)
  if c then offerAccepted(src, c.id) end
  local p, account = officer(src)
  if not p then return warn(src, 'callout accepted while not on duty in the CAD') end
  if not onShift(src) then return warn(src, 'callout accepted while off shift in ERS') end
  if not c then return warn(src, 'callout payload refused (' .. why .. ')') end
  local s = slot(src)
  if calloutNumber(p, account, s) then return end
  lastUse[src] = lastUse[src] or {}
  local ready, left = Pure.cooldown(lastUse[src].calloutCreated, now(), cfg.calloutCooldown or 0)
  if not ready then return Notify.player(src, L('cooldown', left), 'error') end
  if not allowed(src, 'callout') then return end
  local before = p.unit.callNumber
  local startedAt = os.time()
  local place = p.labels
  if c.pos then
    place = Locations.labelsAt(src, c.pos) or {}
    place.postal = Locations.serverPostal(c.pos)
  end
  local body = ErsMap.callBody(c, Pure.playerItem(account), place, cfg.calloutPriority)
  local res = api('POST', '/calls', 'calls', { body = body })
  if res.problem and res.problem.code == 'validation_failed' and (body.postal or body.zoneCode) then
    local plain = {}
    for k, v in pairs(body) do plain[k] = v end
    plain.postal, plain.zoneCode = nil, nil
    res = api('POST', '/calls', 'calls', { body = plain })
  end
  if res.status ~= 201 then
    if Pure.outcomeUnknown(res) then s.calloutUnsure = unsure(before, startedAt) end
    return Notify.problem(src, res)
  end
  s.calloutUnsure = nil
  lastUse[src].calloutCreated = now()
  s.callout = res.data.call.number
  Notify.player(src, L('ers_call_created', s.callout), 'info')
end

local function arrived(src)
  local p, account = officer(src)
  local s = slot(src)
  local number = p and calloutNumber(p, account, s)
  if not number or s.arrived == number then return end
  if not onShift(src) then return warn(src, 'arrival while off shift in ERS') end
  if not allowed(src, 'arrived') then return end
  s.arrived = number
  setStatus(src, account, { meaning = 'on_scene' })
  if gone(Ers.note(number, account, L('ers_note_arrived'))) then s.callout = nil end
end

local function completed(src)
  local p, account = officer(src)
  local s = slot(src)
  local number = calloutNumber(p, account, s)
  if not number then return end
  s.callout = nil
  if cfg.closeOnComplete then return Ers.close(number) end
  Ers.note(number, account, L('ers_note_completed'))
end

local function ended(src)
  local p, account = officer(src)
  local s = slot(src)
  local number = calloutNumber(p, account, s)
  if not number then return end
  s.callout = nil
  if cfg.closeOnEnd then return Ers.close(number) end
  if not account then return end
  Ers.note(number, account, L('ers_note_cleared'))
  api('DELETE', '/calls/{number}/units/{discordId}', 'calls', { params = { number = number, discordId = Pure.playerSlot(account) }, as = account })
end

local function pullover(src, _, vehicleData)
  local p, account = officer(src)
  if not p then return warn(src, 'pullover while not on duty in the CAD') end
  if not lawUnit(p) or not onShift(src, 'police') then return warn(src, 'pullover outside a police shift') end
  if vehicleData ~= nil and ErsMap.oversized(vehicleData) then return warn(src, 'pullover payload refused (shape)') end
  if not allowed(src, 'pullover', Config.cooldowns.ts) then return end
  local s = slot(src)
  if s.stop then return end
  local plate = type(vehicleData) == 'table' and ErsMap.plate(vehicleData.license_plate) or nil
  local before = p.unit.callNumber
  local startedAt = os.time()
  local res = api('POST', '/calls/traffic-stop', 'calls', { body = Pure.withPlayer(account, Pure.trafficStopBody(nil, plate, Locations.fetchLabels(src), State.readCoords(src))), as = account })
  if res.status ~= 201 then
    if Pure.outcomeUnknown(res) then s.stopUnsure = unsure(before, startedAt) end
    return Notify.problem(src, res)
  end
  s.stopUnsure = nil
  s.stop = res.data.number
  local patch = {}
  if cfg.pulloverNature then patch.nature = ErsMap.text(cfg.pulloverNature, 60) end
  if cfg.pulloverPriority then patch.priority = cfg.pulloverPriority end
  if next(patch) then api('PATCH', '/calls/{number}', 'calls', { params = { number = s.stop }, body = patch }) end
  Notify.player(src, L('ers_stop_created', s.stop), 'success')
  if res.data.vehicleReturn then Commands.showVehicle(src, res.data.vehicleReturn) end
end

local function pulloverEnded(src)
  local p, account = officer(src)
  local s = slot(src)
  local number = s.stop or adopt(p, account, s, 'stopUnsure', 'traffic_stop')
  s.stopUnsure = nil
  if not number then return end
  s.stop = nil
  if cfg.closeOnPulloverEnd then return Ers.close(number) end
  if not account then return end
  Ers.note(number, account, L('ers_note_pullover_end'))
  api('DELETE', '/calls/{number}/units/{discordId}', 'calls', { params = { number = number, discordId = Pure.playerSlot(account) }, as = account })
end

local function activeCall(src, p)
  local s = slot(src)
  return s.stop or s.callout or (p and p.unit and p.unit.callNumber)
end

local function pursuitStarted(src)
  local p, account = officer(src)
  if not p then return warn(src, 'pursuit while not on duty in the CAD') end
  if not lawUnit(p) or not onShift(src, 'police') then return warn(src, 'pursuit outside a police shift') end
  if pursuit[src] ~= nil or not allowed(src, 'pursuit') then return end
  local open = true
  local status = ErsMap.text(cfg.pursuitStatus, 20)
  if status then
    local before = p.unit.status and p.unit.status.code
    if setStatus(src, account, { code = status }).status == 200 and before then open = before end
  end
  pursuit[src] = open
  Ers.note(activeCall(src, p), account, L('ers_note_pursuit'))
end

local function pursuitEnded(src)
  local before = pursuit[src]
  if before == nil then return end
  pursuit[src] = nil
  local p, account = officer(src)
  if not p then return end
  if type(before) == 'string' then setStatus(src, account, { code = before }) end
  Ers.note(activeCall(src, p), account, L('ers_note_pursuit_end'))
end

local function closeOnShiftEnd(src)
  local s = slot(src)
  s.callout, s.arrived, s.calloutUnsure, s.stopUnsure = nil, nil, nil, nil
  local before = pursuit[src]
  if before == nil then return end
  pursuit[src] = nil
  local p, account = officer(src)
  local status = ErsMap.text(cfg.pursuitStatus, 20)
  local current = p and p.unit.status and p.unit.status.code
  if type(before) == 'string' and status and current == status then setStatus(src, account, { code = before }) end
end

local function hospital(src, pedData)
  if not cfg.hospitalNote then return end
  local p, account = officer(src)
  if not p or not p.unit.department or not ErsMap.MEDICAL[p.unit.department.type] then return end
  local name = '?'
  if type(pedData) == 'table' and not ErsMap.oversized(pedData) then
    name = ErsMap.text(((pedData.FirstName or '') .. ' ' .. (pedData.LastName or '')), 81) or '?'
  end
  Ers.note(activeCall(src, p), account, L('ers_note_hospital', name))
end

local function remember(kind, key)
  if seen.n >= SEEN_MAX then seen.people, seen.plates, seen.n = {}, {}, 0 end
  seen[kind][key] = true
  seen.n = seen.n + 1
end

local function firstPed(src, pedData)
  if not cfg.registerRecords then return end
  local _, account = officer(src)
  if not account then return end
  local body, why = ErsMap.person(pedData, cfg)
  if not body then
    if why == 'shape' then warn(src, 'ped payload refused (shape)') end
    return
  end
  local key = ('%s|%s|%s'):format(body.firstName:lower(), body.lastName:lower(), body.dob)
  if seen.people[key] or not firstSight(src, 'ped:' .. key) then return end
  Pure.withPlayer(account, body)
  local res = api('POST', '/ers/people', 'lookup', { body = body, as = account })
  if res.status == 200 or res.status == 201 then remember('people', key) end
end

local function firstVehicle(src, vehicleData)
  if not cfg.registerRecords then return end
  local _, account = officer(src)
  if not account then return end
  local body, why, bolo = ErsMap.vehicle(vehicleData)
  if not body then
    if why == 'shape' then warn(src, 'vehicle payload refused (shape)') end
    return
  end
  if seen.plates[body.plate] or not firstSight(src, 'veh:' .. body.plate) then return end
  Pure.withPlayer(account, body)
  local res = api('POST', '/ers/vehicles', 'lookup', { body = body, as = account })
  if res.status ~= 200 and res.status ~= 201 then return end
  remember('plates', body.plate)
  if res.status == 201 and bolo then
    api('POST', '/bolos', 'calls', { body = { kind = 'vehicle', plate = body.plate, description = bolo, origin = 'ers' } })
  end
end

local function toggleShift(src, isOnShift, serviceType)
  if type(isOnShift) ~= 'boolean' or type(serviceType) ~= 'string' or not ErsMap.SERVICES[serviceType] then return end
  shift[src] = isOnShift and serviceType or false
  if not isOnShift then closeOnShiftEnd(src) end
  local department = ErsMap.dutyDepartment(cfg.dutySync, serviceType)
  if not department or not allowed(src, 'shift') then return end
  local account = Identity.getAccount(src)
  if not account then return end
  local unit = (State.peek(src) or {}).unit
  if isOnShift then
    if unit then return end
    local res = api('POST', '/units/duty', 'units', { body = Pure.withPlayer(account, { department = department }), as = account })
    if res.status == 201 then
      local p = State.get(src)
      p.discordId, p.account, p.membershipId = account.discordId, account, res.data.unit.membershipId
      State.setUnit(src, res.data.unit)
      State.claim(account.discordId)
      return Notify.player(src, L('ers_duty_on', res.data.unit.callsign, res.data.unit.department.abbreviation), 'success')
    end
    if res.problem and res.problem.code == 'validation_failed' then
      return Notify.player(src, L('ers_duty_callsign', department, Config.commands.duty.name, department), 'error')
    end
    return Notify.problem(src, res)
  end
  local abbreviation = unit and unit.department and unit.department.abbreviation
  if type(abbreviation) ~= 'string' or abbreviation:upper() ~= department:upper() then return end
  local res = Commands.offDuty(src, account, 'manual')
  if res.status == 204 then Notify.player(src, L('ers_duty_off'), 'success') end
end

function Ers.cadDuty(src, unit)
  if not Modules.active.ers or not cfg.pushShift then return end
  local service = unit and ErsMap.serviceFor(cfg.dutySync, unit.department and unit.department.abbreviation)
  local target = unit and service or nil
  local current = shift[src] or nil
  if target == current or (unit and not service) then return end
  local ok = pcall(function()
    if current then exports[Ers.RESOURCE]:toggleShift(src, current) end
    if target then exports[Ers.RESOURCE]:toggleShift(src, target) end
  end)
  if ok then shift[src] = target end
end

local function offered(payload)
  if not Modules.active.ers then return end
  if type(payload) ~= 'table' or type(payload.offerId) ~= 'string' then return end
  if type(payload.discordId) ~= 'string' and type(payload.membershipId) ~= 'string' then return end
  if not payload.offerId:match('^%x+%-%x+%-%x+%-%x+%-%x+$') then return end
  local calloutId = payload.calloutId
  if calloutId ~= nil and (type(calloutId) ~= 'string' or not calloutId:match('^[%w_%-]+$') or #calloutId > 64) then calloutId = nil end
  local src, account
  for s, p in pairs(State.all()) do
    if p.unit and Pure.namesPlayer(payload.membershipId, payload.discordId, p) then src, account = s, Pure.accountOfState(p) end
  end
  if not src or not account then return end
  CreateThread(function()
    local o = { offerId = payload.offerId, account = account, calloutId = calloutId }
    offers[src] = o
    local called, ok, reason = pcall(function() return exports[Ers.RESOURCE]:SendCalloutOfferToPlayer(src, calloutId, cfg.offerTimeout) end)
    if not (called and ok == true) then
      if offers[src] == o then offers[src] = nil end
      return offerAnswer(src, o, { ok = false, reason = ErsMap.offerReason(false, called and reason or 'offer_failed') })
    end
    offerAnswer(src, o, { ok = true, stage = 'delivered' })
    if o.accepted then
      if offers[src] == o then offers[src] = nil end
      return offerAnswer(src, o, { ok = true, stage = 'accepted' })
    end
    if offers[src] ~= o then return end
    o.delivered = true
    SetTimeout((tonumber(cfg.offerTimeout) or 15000) + OFFER_GRACE_MS, function()
      if offers[src] ~= o or o.accepted then return end
      offers[src] = nil
      offerAnswer(src, o, { ok = false, stage = 'no_answer', reason = 'no_answer' })
    end)
  end)
end

function Ers.register()
  fromClient('ErsIntegration::OnAcceptedCalloutOffer', accepted)
  fromClient('ErsIntegration::OnArrivedAtCallout', arrived)
  fromClient('ErsIntegration::OnCalloutCompletedSuccesfully', completed)
  fromClient('ErsIntegration::OnEndedACallout', ended)
  fromClient('ErsIntegration::OnPullover', pullover)
  fromClient('ErsIntegration::OnPulloverEnded', pulloverEnded)
  fromClient('ErsIntegration::OnPursuitStarted', pursuitStarted)
  fromClient('ErsIntegration::OnPursuitEnded', pursuitEnded)
  fromServer('ErsIntegration::OnPersonDeliveredToHospital', hospital)
  fromServer('ErsIntegration::OnFirstNPCInteraction', firstPed)
  fromServer('ErsIntegration::OnFirstVehicleInteraction', firstVehicle)
  fromServer('ErsIntegration::OnToggleShift', toggleShift)
  AddEventHandler('statewide:ersOffer', offered)
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  Ers.calls[src], lastUse[src], keyed[src], warnedAt[src], busy[src], pursuit[src], shift[src], offers[src] = nil, nil, nil, nil, nil, nil, nil, nil
end)

Modules.resolve('ers', Ers.register)
