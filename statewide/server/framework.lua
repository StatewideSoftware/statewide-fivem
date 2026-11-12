Framework = {}

local own = GetCurrentResourceName()
local sessions = {}
local queues = {}
local working = {}
local epochs = {}
local refusals = {}
local unmapped = {}
local RETRY_SECONDS = { 5, 15, 45 }
local QUEUE_MAX = 16

local function now()
  return GetGameTimer() / 1000
end

local function connected(src)
  src = tonumber(src)
  return src ~= nil and src > 0 and GetPlayerName(src) ~= nil
end

local function codeOf(res)
  return res and res.problem and res.problem.code or ('http_' .. tostring(res and res.status))
end

local function transient(res)
  return Pure.syncTransient(tonumber(res and res.status) or 0)
end

function Framework.refused(label, src, code)
  if Pure.refusalThrottle(refusals, tostring(src), code, now(), 60) then
    print(('^3[statewide] framework %s refused for %s: %s^7'):format(tostring(label), tostring(src), tostring(code)))
  end
end

local function discordAccount(src)
  local account = Identity.getAccount(src)
  if account and account.discordId then return account end
  return nil
end

local function live(src, job)
  return (epochs[src] or 0) == job.epoch
end

local function store(src, job, session)
  if live(src, job) then sessions[src] = session end
end

local function signOff(src, account, session, job)
  local res = Commands.offDuty(src, account, 'manual')
  if res.status == 204 or codeOf(res) == 'not_found' then
    session.signedOn = nil
    if Ers and live(src, job) then Ers.cadDuty(src, nil) end
    return true
  end
  Framework.refused(job.label, src, codeOf(res))
  return false, transient(res)
end

local function clearCharacter(src, account, job)
  local res = api('DELETE', '/characters/active', 'civilian', { query = { discordId = Pure.playerSlot(account) }, as = account })
  if res.status == 204 then
    if live(src, job) then State.setCharacter(src, nil) end
    return true
  end
  Framework.refused(job.label, src, codeOf(res))
  if live(src, job) then Notify.problem(src, res) end
  return false, transient(res)
end

local function activate(src, account, c, job)
  local item = Pure.withPlayer(account, { externalId = c.externalId, firstName = c.firstName, lastName = c.lastName, dob = c.dob, gender = c.gender })
  local pushed = api('POST', '/sync/characters', 'sync', { body = { source = c.externalSource, items = { item } }, as = account })
  local result = pushed.status == 200 and pushed.data and pushed.data.results and pushed.data.results[1]
  if not result then
    Framework.refused(job.label, src, codeOf(pushed))
    return false, transient(pushed)
  end
  if not result.ssn or (result.outcome ~= 'created' and result.outcome ~= 'updated' and result.outcome ~= 'unchanged') then
    local code = result.outcome == 'unlinked' and 'not_member' or tostring(result.reason or result.outcome)
    Framework.refused(job.label, src, code)
    if code == 'not_member' and live(src, job) then Notify.player(src, L('err_not_member'), 'error') end
    return false
  end
  if not live(src, job) then return true end
  local res = api('PUT', '/characters/active', 'civilian', { body = Pure.withPlayer(account, { ssn = result.ssn }), as = account })
  if not live(src, job) then return true end
  if res.status ~= 200 then
    Framework.refused(job.label, src, codeOf(res))
    Notify.problem(src, res)
    return false, transient(res)
  end
  local cad = res.data.character
  State.setCharacter(src, { id = cad.id, ssn = cad.ssn, firstName = cad.firstName, lastName = cad.lastName, dob = cad.dob })
  Notify.player(src, L('setciv_done', cad.firstName, cad.lastName), 'success')
  TriggerEvent('statewide:characterLinked', tonumber(src), { ssn = cad.ssn, externalSource = c.externalSource, externalId = c.externalId, created = result.outcome == 'created' })
  return true
end

local function signOn(src, account, session, department, callsign, job)
  local res = Commands.signOn(src, account, department, callsign)
  if res.status == 201 then
    session.signedOn = true
    return true
  end
  local code = codeOf(res)
  Framework.refused(job.label, src, code)
  if code == 'validation_failed' and not callsign and live(src, job) then
    Notify.player(src, L('framework_callsign', department, Config.commands.duty.name, department), 'error')
  end
  return false, transient(res)
end

local function runCharacter(src, account, job)
  local prev = sessions[src]
  local actions, nextSession = Pure.frameworkTransition(prev, job.character, job.map, job.autoDuty)
  if job.clear and #actions == 0 and not (prev and prev.role == 'civilian') then actions = { { kind = 'clearCharacter' } } end
  local retry = false
  for i = 1, #actions do
    local a = actions[i]
    local ok, again = true, false
    if a.kind == 'unmapped' then
      local key = job.label .. '|' .. tostring(a.key)
      if not unmapped[key] then
        unmapped[key] = true
        print(('^3[statewide] framework %s: department key %s is not mapped; add it to Config.%s.departments.^7'):format(job.label, tostring(a.key), job.label))
      end
      return false
    elseif a.kind == 'signOff' then
      ok, again = signOff(src, account, prev, job)
    elseif a.kind == 'clearCharacter' then
      ok, again = clearCharacter(src, account, job)
    elseif a.kind == 'activate' then
      ok, again = activate(src, account, a.character, job)
    elseif a.kind == 'signOn' then
      ok, again = signOn(src, account, nextSession, a.department, a.callsign, job)
    end
    if not ok and again then retry = true end
  end
  if retry then return true end
  store(src, job, nextSession)
  return false
end

local function runDuty(src, account, job)
  local s = sessions[src]
  if job.onDuty then
    if s and s.signedOn and s.department == job.department and s.callsign == job.callsign then return false end
    if s and s.signedOn then
      local ok, again = signOff(src, account, s, job)
      if not ok then return again == true end
    end
    if not s or s.role ~= 'department' then
      s = { role = 'duty', externalSource = job.label }
      store(src, job, s)
    end
    s.department, s.callsign = job.department, job.callsign
    local _, again = signOn(src, account, s, job.department, job.callsign, job)
    return again == true
  end
  if not (s and s.signedOn) then return false end
  local ok, again = signOff(src, account, s, job)
  if ok and s.role == 'duty' then store(src, job, nil) end
  return again == true
end

local function kindOf(job)
  return job.duty ~= nil and 'duty' or 'character'
end

local function superseded(src, job)
  local q = queues[src]
  if not q then return true end
  local kind = kindOf(job)
  for i = 1, #q do
    if kindOf(q[i]) == kind then return true end
  end
  return false
end

local function pause(src, job, seconds)
  for _ = 1, seconds * 4 do
    if not live(src, job) or superseded(src, job) then return false end
    Wait(250)
  end
  return live(src, job) and not superseded(src, job)
end

local function settle(src, job)
  local attempt = 0
  while live(src, job) and connected(src) do
    local account = discordAccount(src)
    if not account then
      Notify.player(src, L('no_discord'), 'error')
      return
    end
    local ok, again = pcall(job.duty ~= nil and runDuty or runCharacter, src, account, job)
    if not ok then
      print(('^1[statewide] framework %s: %s^7'):format(tostring(job.label), tostring(again)))
      return
    end
    if not again then return end
    attempt = attempt + 1
    local delay = RETRY_SECONDS[attempt]
    if not delay then
      Framework.refused(job.label, src, 'retries_exhausted')
      return
    end
    if not pause(src, job, delay) then return end
  end
end

local function work(src)
  local q = queues[src]
  while q and #q > 0 do
    settle(src, table.remove(q, 1))
    q = queues[src]
  end
  queues[src] = nil
  working[src] = nil
end

local function enqueue(src, job)
  src = tonumber(src)
  local q = queues[src]
  if not q then
    q = {}
    queues[src] = q
  end
  if #q >= QUEUE_MAX then
    Framework.refused(job.label, src, 'busy')
    return false
  end
  job.epoch = epochs[src] or 0
  q[#q + 1] = job
  if working[src] then return true end
  working[src] = true
  CreateThread(function() work(src) end)
  return true
end

function Framework.apply(src, character, opts)
  opts = opts or {}
  return enqueue(src, { character = character, map = opts.map, autoDuty = opts.autoDuty ~= false, clear = opts.clear == true, label = opts.label or 'framework' })
end

function Framework.duty(src, onDuty, department, callsign, label)
  return enqueue(src, { duty = onDuty == true, onDuty = onDuty == true, department = department, callsign = callsign, label = label or 'framework' })
end

function Framework.session(src)
  return sessions[tonumber(src)]
end

function Framework.discordOf(src)
  local account = discordAccount(src)
  return account and account.discordId or nil
end

local function allowed(resource)
  for _, name in ipairs((Config.framework or {}).connectors or {}) do
    if name == resource then return true end
  end
  return false
end

local function refuse(resource, reason)
  if Pure.refusalThrottle(refusals, tostring(resource), reason, now(), 60) then
    print(('^3[statewide] framework export refused from %s: %s^7'):format(tostring(resource), reason))
  end
  return false, reason
end

local function ready(resource, src)
  if not connected(src) then return refuse(resource, 'not_connected') end
  if not discordAccount(src) then return refuse(resource, 'no_discord') end
  return true
end

exports('SetActiveCharacter', function(src, data)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  local ok, why = ready(resource, src)
  if not ok then return false, why end
  local character = Pure.validateFrameworkCharacter(data, resource)
  if not character then return refuse(resource, 'validation') end
  if not Framework.apply(src, character, { label = 'resource:' .. resource, autoDuty = false }) then return false, 'busy' end
  return true
end)

exports('ClearActiveCharacter', function(src)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  local ok, why = ready(resource, src)
  if not ok then return false, why end
  if not Framework.apply(src, nil, { label = 'resource:' .. resource, autoDuty = false, clear = true }) then return false, 'busy' end
  return true
end)

exports('SetDuty', function(src, onDuty, data)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  local ok, why = ready(resource, src)
  if not ok then return false, why end
  if onDuty == true then
    local department, callsign = Pure.frameworkDutyArgs(data)
    if not department then return refuse(resource, 'validation') end
    if not Framework.duty(src, true, department, callsign, 'resource:' .. resource) then return false, 'busy' end
    return true
  end
  if onDuty ~= false then return refuse(resource, 'validation') end
  if not Framework.duty(src, false, nil, nil, 'resource:' .. resource) then return false, 'busy' end
  return true
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  epochs[src] = (epochs[src] or 0) + 1
  sessions[src] = nil
  queues[src] = nil
end)
