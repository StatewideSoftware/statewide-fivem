PhoneApp = {}

local cfg = Config.phoneApp or {}
local INTERVAL_MS = math.max(250, tonumber(cfg.requestIntervalMs) or 500)
local ID_MAX = 2147483647
local last, busy, seen, watching, shown = {}, {}, {}, {}, {}

local function failure(key, ...)
  return Pure.phoneResult({ { text = L(key, ...), kind = 'error' } })
end

local function problem(res)
  return Pure.phoneResult({ { text = Pure.problemMessage(res and res.problem, Locale), kind = 'error' } })
end

local function captured(src, fn, ...)
  local messages, data = Notify.capture(src, fn, ...)
  return Pure.phoneResult(messages, data)
end

local function push(src, data)
  if seen[src] then TriggerClientEvent('statewide:client:phonePush', src, data) end
end

local function answer(res, shape)
  if res.status ~= 200 or type(res.data) ~= 'table' then return problem(res) end
  return Pure.phoneResult({}, shape(res.data))
end

local RUN = {}

RUN.me = function(src)
  local p = State.peek(src)
  if not p then
    State.refresh(src)
    p = State.peek(src)
  end
  local c = p and p.character
  return Pure.phoneResult({}, {
    onDuty = p ~= nil and p.unit ~= nil,
    unit = Pure.phoneViewUnit(p and p.unit),
    character = c and { name = Pure.truncate((c.firstName or '') .. ' ' .. (c.lastName or ''), 80), ssn = c.ssn } or nil,
  })
end

RUN.characters = function(_, _, account)
  local res = api('GET', '/characters', 'civilian', { query = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  return answer(res, function(data) return Pure.phoneViewCharacters(data.characters) end)
end

RUN.setActive = function(src, args)
  return captured(src, Actions.setciv, src, args.ssn)
end

RUN.profile = function(_, args, account)
  local res = api('GET', '/characters/{ssn}/profile', 'civilian', { params = { ssn = args.ssn }, query = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  local result = answer(res, Pure.phoneViewProfile)
  if result.ok and not result.data then return failure('phone_failed') end
  return result
end

RUN.my911 = function(src, _, account)
  local res = api('GET', '/players/{discordId}/911', 'civilian', { params = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  return answer(res, function(data)
    local calls = Pure.phoneView911(data.calls)
    local numbers = {}
    for i = 1, #calls do numbers[calls[i].number] = true end
    watching[src] = numbers
    return calls
  end)
end

RUN.call = function(src, _, account)
  State.refresh(src)
  local p = State.peek(src)
  local number = p and p.unit and p.unit.callNumber
  if not Pure.isCallNumber(number) then return Pure.phoneResult({}, nil) end
  local res = api('GET', '/calls/{number}', 'calls', { params = { number = number }, query = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  return answer(res, Pure.phoneViewCall)
end

RUN.statusCodes = function(_, _, account)
  local res = api('GET', '/status-codes', 'units', { query = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  return answer(res, function(data) return Pure.phoneViewStatusCodes(data.codes) end)
end

RUN.status = function(src, args)
  return captured(src, Actions.status, src, args.code)
end

RUN.panic = function(src)
  local ok, why, left = Commands.enter(src)
  if not ok then return why == 'cooldown' and failure('cooldown', left) or failure('busy') end
  local fine, result = pcall(captured, src, Actions.panic, src, 'panic')
  Commands.leave(src)
  if not fine then error(result, 0) end
  return result
end

RUN.plate = function(src, args)
  return captured(src, Actions.plate, src, args.plate)
end

RUN.name = function(src, args)
  return captured(src, Actions.name, src, args.first, args.last)
end

local function run(src, action, args, spec)
  local account = Identity.getAccount(src)
  if not account then return failure('no_discord') end
  if spec.officer then
    local p = State.peek(src)
    if not (p and p.unit) then return failure('not_on_duty') end
  end
  return RUN[action](src, args, account)
end

local function reply(src, id, result)
  TriggerClientEvent('statewide:client:phone', src, id, result)
end

local function onPhone(msg)
  local src = tonumber(source)
  if not src or src <= 0 or not Modules.active.phoneapp then return end
  if type(msg) ~= 'table' then return end
  local id = msg.id
  if math.type(id) ~= 'integer' or id < 1 or id > ID_MAX then return end
  local args, spec = Pure.validatePhoneAction(msg.action, msg.args)
  local urgent = args ~= nil and spec.urgent == true
  if not urgent then
    local now = GetGameTimer()
    if busy[src] or (last[src] and now - last[src] < INTERVAL_MS) then return reply(src, id, failure('busy')) end
    last[src] = now
  end
  if not args then return reply(src, id, failure(spec == 'unknown_action' and 'phone_unknown' or 'phone_bad_args')) end
  if not urgent then busy[src] = true end
  seen[src] = true
  CreateThread(function()
    local ok, result = pcall(run, src, msg.action, args, spec)
    if not urgent then busy[src] = nil end
    if not ok then
      print(('^1[statewide] phone app: %s^7'):format(result))
      result = failure('phone_failed')
    end
    reply(src, id, result)
  end)
end

local function fromServer(fn)
  return function(payload)
    if not Pure.isServerSource(source) or not Modules.active.phoneapp then return end
    fn(payload)
  end
end

local function callChanged(payload)
  if type(payload) ~= 'table' or not Pure.isCallNumber(payload.number) then return end
  for src, numbers in pairs(watching) do
    if numbers[payload.number] then push(src, { type = 'my911' }) end
  end
end

local function callOpened(payload)
  callChanged(payload)
end

local OFFICER_PUSHES = { attached = true, callClosed = true, forcedOff = true }

local function officerSink(src, name)
  if Modules.active.phoneapp and OFFICER_PUSHES[name] then push(src, { type = 'call' }) end
end

local function unitChanged(src, unit)
  if not Modules.active.phoneapp or not seen[src] then return end
  local view = Pure.phoneViewUnit(unit)
  local key = Pure.phoneUnitKey(view)
  if shown[src] == key then return end
  shown[src] = key
  push(src, { type = 'unit', unit = view, onDuty = unit ~= nil })
end

local function characterChanged(src)
  if Modules.active.phoneapp then push(src, { type = 'character' }) end
end

function PhoneApp.register()
  RegisterNetEvent('statewide:phone', onPhone)
  AddEventHandler('statewide:callOpened', fromServer(callOpened))
  AddEventHandler('statewide:callClosed', fromServer(callChanged))
  AddEventHandler('statewide:attached', fromServer(callChanged))
  AddEventHandler('statewide:detached', fromServer(callChanged))
  Notify.addSink(officerSink)
  State.onUnitChange(unitChanged)
  State.onCharacterChange(characterChanged)
  AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    last[src], busy[src], seen[src], watching[src], shown[src] = nil, nil, nil, nil, nil
  end)
end

PhoneApp.run = run

local lbphoneOff = ErsMap.mode((Config.modules or {}).lbphone, 'started') == 'off'
Modules.resolve('phoneapp', PhoneApp.register, lbphoneOff and L('phoneapp_absent', Config.lbPhone.resource) or false)
