LbPhone = {}

local cfg = Config.lbPhone
local P = LbPhonePure
local BOOK_MAX = 256
local NOTE_MAX = 500
local TEXT_MAX = 900
local REPLY_MAX = 300
local PENDING_WAIT_MS = 250
local PENDING_TRIES = 40
local book = P.newBook(BOOK_MAX)
local notes, pending, synced, warned = {}, {}, {}, {}

local function clock()
  return GetGameTimer() / 1000
end

local function ready()
  return Modules.active.lbphone == true and GetResourceState(cfg.resource) == 'started'
end

local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(line)
end

function LbPhone.call(name, ...)
  local res = exports[cfg.resource]
  local ok, result = pcall(function(...) return res[name](res, ...) end, ...)
  if ok then return true, result end
  warnOnce('export:' .. name, '^3' .. L('lbphone_export_failed', name, tostring(result)) .. '^7')
  return false
end

function LbPhone.tell(phone, body)
  if type(phone) ~= 'string' or type(body) ~= 'string' or body == '' or not ready() then return nil end
  local ok, sent = LbPhone.call('SendMessage', cfg.dispatchNumber, phone, body)
  if ok and sent ~= nil then
    warnOnce('path:message', '[statewide] LB Phone reply sent as a message from ' .. tostring(cfg.dispatchNumber))
    return 'message'
  end
  ok = LbPhone.call('SendNotification', phone, { app = 'Messages', title = L('lbphone_title'), content = body })
  if not ok then return nil end
  warnOnce('path:notification', '[statewide] LB Phone reply sent as a notification')
  return 'notification'
end

local function textLimit()
  return math.min(tonumber(cfg.maxTextLength) or NOTE_MAX, TEXT_MAX)
end

local ANONYMOUS_SECONDS = 30
local newCall
local anonymousAt = {}

local function placeAt(src, coords, shared)
  local p = src and State.peek(src)
  local labels = not shared and p and p.labels or nil
  if not labels and src and coords then labels = Locations.labelsAt(src, coords) end
  local postal = Pure.preferPostal(coords and Locations.serverPostal(coords), labels)
  local street = type(labels) == 'table' and Pure.locationText(labels) or nil
  return P.location(labels, postal, L('lbphone_unknown_location')), postal, labels, street
end

local function placed(call)
  if type(call) ~= 'table' or type(call.location) ~= 'string' or call.location == '' then return nil end
  local postal = type(call.postal) == 'string' and call.postal ~= '' and call.postal or nil
  if not postal or call.location == P.location(nil, postal) then return call.location end
  return L('lbphone_place', call.location, postal)
end

local function moveCall(number, src, coords)
  local location, postal, _, street = placeAt(src, coords, true)
  local at = Pure.position(coords)
  local named = (street or postal) and Pure.clean(location, 120) or nil
  if not named and not at then return nil end
  local params = { number = number }
  local res = api('PATCH', '/calls/{number}', 'calls', { params = params, body = { location = named, postal = postal, x = at and at.x, y = at and at.y }, retry = false })
  if res.problem and res.problem.code == 'validation_failed' and named and (postal or at) then
    postal = nil
    res = api('PATCH', '/calls/{number}', 'calls', { params = params, body = { location = named }, retry = false })
  end
  if res.status ~= 200 then return named end
  return placed(type(res.data) == 'table' and res.data.call) or (street and postal and L('lbphone_place', street, postal)) or named
end

local function addNote(number, key, sender, src, company, msg)
  Callers.touch(key)
  local text = P.text(msg.text, math.min(textLimit(), NOTE_MAX))
  if not text and not msg.shared then return end
  local entry = notes[number] or {}
  notes[number] = entry
  local gate = P.noteGate(entry, clock(), tonumber(cfg.noteCooldownSeconds) or 10, tonumber(cfg.maxCallerNotes) or 20)
  if gate == 'capped' then return LbPhone.tell(sender, L('lbphone_notes_capped', number)) end
  if gate ~= 'ok' then return end
  if msg.shared then
    local place = moveCall(number, src, msg.coords)
    text = text or (place and L('lbphone_shared_note', place)) or L('lbphone_shared')
  end
  local res = api('POST', '/calls/{number}/notes', 'calls', { params = { number = number }, body = { body = Pure.clean(text, NOTE_MAX), kind = 'caller' }, retry = false })
  if res.status == 201 then return end
  local code = res.problem and res.problem.code
  if code == 'limit_reached' then
    entry.count = math.huge
    if entry.told then return end
    entry.told = true
    return LbPhone.tell(sender, L('lbphone_notes_capped', number))
  end
  if code == 'call_closed' or code == 'not_found' then
    Callers.clear(key)
    notes[number] = nil
    return newCall(key, sender, src, company, msg)
  end
end

local function bodyFor(src, company, msg)
  local text = P.text(msg.text, textLimit()) or (msg.shared and L('lbphone_shared')) or nil
  local description = text and P.describe(company, text, textLimit())
  if not description then return nil end
  local location, postal, labels, street = placeAt(src, msg.coords, msg.shared)
  local body = Pure.call911Body({
    text = description, location = location, postal = postal, anonymous = msg.anonymous, coords = msg.coords,
    zoneCode = labels and labels.zone,
  })
  if not street and not postal and body.x then body.location = nil end
  return body, location, description
end

local function post911(body, account)
  local res = Commands.post911(body, account)
  if body.location or not (res.problem and res.problem.code == 'validation_failed') then return res end
  body.location = L('lbphone_unknown_location')
  return Commands.post911(body, account)
end

local function claimAnonymous(company)
  local held = anonymousAt[company]
  if not Pure.cooldown(held, clock(), ANONYMOUS_SECONDS) then return false, held end
  anonymousAt[company] = clock()
  return true, held
end

newCall = function(key, sender, src, company, msg)
  local account, held
  if msg.anonymous then
    local ok
    ok, held = claimAnonymous(company)
    if not ok then return end
  else
    account = Identity.getAccount(src)
    if not account then return LbPhone.tell(sender, L('lbphone_not_sent')) end
    if not Commands.cooldownReady(src, Pure.callBucket('911')) then return end
  end
  local body, location, description = bodyFor(src, company, msg)
  if not body then
    if msg.anonymous then anonymousAt[company] = held end
    return
  end
  body.clientRef = Pure.clientRef(account and account.discordId, os.time(), math.random(0, 0xffffff))
  if account then
    Pure.withPlayer(account, body)
    body.callerPhone = sender
  end
  if key then pending[key] = true end
  local ok, res = pcall(post911, body, account)
  if key then pending[key] = nil end
  local created = ok and res.status == 201 and type(res.data) == 'table' and type(res.data.number) == 'string'
  if msg.anonymous and not created then anonymousAt[company] = held end
  if not ok then error(res, 0) end
  if not created then
    if src and not Pure.retryable(res.status) then Notify.problem(src, res) end
    return LbPhone.tell(sender, L('lbphone_not_sent'))
  end
  local number = res.data.number
  if msg.anonymous then return Commands.after911(nil, res, location, description, '911', msg.coords) end
  Commands.cooldownStart(src, Pure.callBucket('911'))
  Callers.open(key, number)
  P.remember(book, number, { phone = sender, key = key })
  Commands.after911(src, res, location, description, '911', msg.coords)
end

local function settle(key)
  for _ = 1, PENDING_TRIES do
    if not pending[key] then return end
    Wait(PENDING_WAIT_MS)
  end
end

local function companyMessage(company, sender, msg)
  if msg.anonymous then return newCall(nil, nil, nil, company, msg) end
  local found, from = LbPhone.call('GetSourceFromNumber', sender)
  local src = found and tonumber(from) or nil
  if not src or src <= 0 then return end
  local key = Pure.callerKey(sender)
  settle(key)
  if pending[key] then return end
  local open = Callers.find(key)
  if open then return addNote(open, key, sender, src, company, msg) end
  newCall(key, sender, src, company, msg)
end

local function onCompanyMessage(message)
  if not Pure.isServerSource(source) or not ready() then return end
  if type(message) ~= 'table' or message.sentByEmployee ~= false then return end
  local company = P.company(cfg.companies, message.company)
  if not company then return end
  local anonymous = message.anonymous == true
  local sender = not anonymous and P.phone(message.sender) or nil
  if not anonymous and not Pure.callerKey(sender) then return end
  local rest, tagged = P.sharedLocation(message.message)
  if not P.text(rest, TEXT_MAX) and not tagged then return end
  local msg = { text = rest, coords = P.placeFor(P.point(message.coords), tagged), shared = tagged ~= nil, anonymous = anonymous }
  CreateThread(function()
    local ok, err = pcall(companyMessage, company, sender, msg)
    if not ok then print(('^1[statewide] LB Phone text: %s^7'):format(err)) end
  end)
end

local function callerOf(payload)
  local entry = P.recall(book, payload.number)
  if entry then return entry.phone end
  return P.phone(payload.callerPhone)
end

local function fromServer(fn)
  return function(payload)
    if not Pure.isServerSource(source) or not ready() or type(payload) ~= 'table' or type(payload.number) ~= 'string' then return end
    CreateThread(function()
      local ok, err = pcall(fn, payload)
      if not ok then print(('^1[statewide] LB Phone reply: %s^7'):format(err)) end
    end)
  end
end

local function opened(payload)
  LbPhone.tell(callerOf(payload), L('lbphone_opened', payload.number))
end

local function closed(payload)
  LbPhone.tell(callerOf(payload), L('lbphone_closed', payload.number))
  P.forget(book, payload.number)
  notes[payload.number] = nil
end

local function callerMessage(payload)
  LbPhone.tell(callerOf(payload), P.text(payload.body, REPLY_MAX))
end

local OFFICER_LABELS = { attached = L('lbphone_officer_attached'), panic = L('lbphone_officer_panic') }

local function officerSink(src, name, payload)
  if not ready() then return end
  local notice = P.officerNotice(name, payload, OFFICER_LABELS)
  if notice then LbPhone.call('EmergencyNotification', src, notice) end
end

local function syncPhone(src, phone)
  if cfg.syncPhoneNumber ~= true or not ready() then return end
  src = tonumber(src)
  if not src or src <= 0 then return end
  if phone == nil then
    local ok, equipped = LbPhone.call('GetEquippedPhoneNumber', src)
    phone = ok and equipped or nil
  end
  phone = P.phone(phone)
  local p = State.peek(src)
  local character = p and p.character
  if not phone or type(character) ~= 'table' or not character.id then return end
  local mark = character.id .. '|' .. phone
  if synced[src] == mark then return end
  local account = Identity.getAccount(src)
  if not account then return end
  synced[src] = mark
  local res = api('PUT', '/characters/active/phone', 'civilian', { body = Pure.withPlayer(account, { phone = phone }), as = account, retry = false })
  if res.status ~= 200 and synced[src] == mark then synced[src] = nil end
end

local function syncLater(src, phone)
  CreateThread(function()
    local ok, err = pcall(syncPhone, src, phone)
    if not ok then print(('^1[statewide] LB Phone number: %s^7'):format(err)) end
  end)
end

local function onNumber(player, number)
  if not Pure.isServerSource(source) then return end
  syncLater(player, number)
end

function LbPhone.register()
  AddEventHandler('lb-phone:newCompanyMessage', onCompanyMessage)
  AddEventHandler('lb-phone:numberChanged', onNumber)
  AddEventHandler('lb-phone:phoneNumberGenerated', onNumber)
  AddEventHandler('statewide:callOpened', fromServer(opened))
  AddEventHandler('statewide:callClosed', fromServer(closed))
  AddEventHandler('statewide:callerMessage', fromServer(callerMessage))
  Notify.addSink(officerSink)
  State.onCharacterChange(function(src, character)
    if character then syncLater(src) end
  end)
  AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then synced[src] = nil end
  end)
end

Modules.resolve('lbphone', LbPhone.register, L('lbphone_absent', cfg.resource))
