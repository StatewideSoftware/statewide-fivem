Http = {}

local resource = GetCurrentResourceName()
Http.version = GetResourceMetadata(resource, 'version', 0) or '0.0.0'

local warned = {}
local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(('^3[statewide] %s^7'):format(line))
end

local function decode(body)
  if not body or body == '' then return nil end
  local ok, out = pcall(json.decode, body)
  return ok and out or nil
end

local gate = Pure.httpGate(Pure.httpConcurrency(GetConvar('statewide_http_concurrency', tostring(Pure.HTTP_CONCURRENCY))))
local inflight, sweeping = {}, false

local function wake(tickets)
  for i = 1, #tickets do
    local p = tickets[i].wake
    if p then p:resolve(true) end
  end
end

local function acquire(class)
  local ticket = Pure.httpGateJoin(gate, class)
  if not ticket.go then
    ticket.wake = promise.new()
    Citizen.Await(ticket.wake)
  end
  return ticket
end

local function release(ticket)
  inflight[ticket] = nil
  wake(Pure.httpGateRelease(gate, ticket))
end

local function sweep()
  local told = false
  while next(inflight) do
    Wait(Pure.HTTP_SLOT_CEILING_S * 250)
    local now = GetGameTimer()
    local expired = {}
    for ticket, at in pairs(inflight) do
      if now - at >= Pure.HTTP_SLOT_CEILING_S * 1000 then expired[#expired + 1] = ticket end
    end
    if #expired > 0 and not told then
      told = true
      print(('^3[statewide] an HTTP request never returned after %d s; its queue slot is freed.^7'):format(Pure.HTTP_SLOT_CEILING_S))
    end
    for i = 1, #expired do release(expired[i]) end
  end
  sweeping = false
end

local function send(url, method, data, headers, deadline, class, late)
  local ticket = acquire(class)
  local done, out = false, nil
  inflight[ticket] = GetGameTimer()
  PerformHttpRequest(url, function(status, body, respHeaders, errorData)
    release(ticket)
    if done then
      local code = tonumber(status) or 0
      if late and code >= 200 and code < 300 then CreateThread(function() late({ status = code, data = decode(body) }) end) end
      return
    end
    done, out = true, { status = status, body = body, headers = respHeaders, errorData = errorData }
  end, method, data, headers, { followLocation = false })
  if not done and not sweeping then
    sweeping = true
    CreateThread(sweep)
  end
  local stop = GetGameTimer() + deadline * 1000
  while not done and GetGameTimer() < stop do Wait(50) end
  if done then return out end
  done = true
  return { status = 0, timedOut = true }
end

local function request(method, template, scope, opts)
  opts = opts or {}
  local base = GetConvar('statewide_api_url', ''):gsub('/+$', '')
  local key = GetConvar('statewide_api_key', '')
  if base == '' or key == '' then
    warnOnce('config', 'statewide_api_url and statewide_api_key must be set in server.cfg (set, never setr).')
    return { status = 0, problem = { status = 0, code = 'not_configured' } }
  end
  if Pure.insecureUrl(base) then
    warnOnce('insecure', ('statewide_api_url %s is not https: requests are refused so the API key never travels in clear text.'):format(base))
    return { status = 0, problem = { status = 0, code = 'not_configured' } }
  end
  local url = base .. '/api/v1' .. Pure.buildPath(template, opts.params, opts.query)
  local headers = {
    ['Authorization'] = 'Bearer ' .. key,
    ['User-Agent'] = 'statewide-fivem/' .. Http.version,
    ['Accept'] = 'application/json',
  }
  for k, v in pairs(Pure.playerHeaders(opts.as) or {}) do headers[k] = v end
  local data = ''
  if opts.body ~= nil then
    headers['Content-Type'] = 'application/json'
    data = json.encode(opts.body)
  end
  local deadline = tonumber(opts.deadline) or Pure.HTTP_DEADLINE_S
  local class = Pure.httpClass(method, template, opts.priority)
  local watched = Pure.lateWatched(method, template, opts.as ~= nil and Http.inCommand ~= nil and Http.inCommand())
  local late = watched and function(res)
    if Http.onLate then Http.onLate(opts.as, template, res) end
  end or nil
  local from = os.time()
  for attempt = 1, 2 do
    local r = send(url, method, data, headers, deadline, class, late)
    local status = tonumber(r.status) or 0
    if status >= 200 and status < 300 then return { status = status, data = decode(r.body) } end
    local problem = Pure.parseHttpError(r.errorData)
    if problem.status == 0 and status >= 400 then problem.status = status end
    local aborted = not r.timedOut and status == 0 and Pure.httpAborted(r.errorData)
    if status == 0 and not r.timedOut and not aborted then problem.network = true end
    if r.timedOut or aborted then
      problem.timedOut = true
      problem.pending = watched or nil
      if aborted and watched then
        problem.pending = Pure.confirmable(template) or nil
        problem.unanswered = not problem.pending or nil
      end
      local waited = aborted and math.min(deadline, Pure.HTTP_NO_RESPONSE_S) or deadline
      warnOnce('timeout', ('The CAD did not answer %s %s within %d s; later stalls are not logged.'):format(method, template, waited))
    end
    local wait = Pure.retryWait(method, problem, attempt, opts.retry, math.random(), opts.as ~= nil)
    if wait then
      Wait(math.floor(wait * 1000))
    else
      if problem.code == 'scope_denied' then
        warnOnce('scope:' .. scope, ('The API key lacks the "%s" scope (%s %s). Add it on the key in the CAD.'):format(scope, method, template))
      elseif problem.code == 'invalid_key' then
        warnOnce('invalid_key', 'The API key is missing, disabled or revoked (401 invalid_key).')
      elseif problem.code == 'module_disabled' then
        warnOnce('module:' .. template, ('%s %s: the community has that module turned off.'):format(method, template))
      end
      if aborted and problem.pending then
        local ctx = { from = from, params = opts.params, body = opts.body }
        CreateThread(function()
          Wait(Pure.HTTP_NO_RESPONSE_S * 1000)
          ctx.to = os.time()
          if Http.onDropped then Http.onDropped(opts.as, template, ctx) end
        end)
      end
      return { status = problem.status, problem = problem }
    end
  end
end

function Http.concurrency()
  return gate.max
end

function Http.peak()
  return gate.peak
end

function Http.active()
  return gate.active
end

function api(method, template, scope, opts)
  return request(method, template, scope, opts)
end

Http.request = api

Http.PACE_MS = 100
local paced, pacing = {}, false

function Http.pace(fn, rank)
  paced[#paced + 1] = { fn = fn, rank = rank }
  if pacing then return end
  pacing = true
  CreateThread(function()
    while #paced > 0 do
      local job = table.remove(paced, Pure.pacePick(paced))
      CreateThread(job.fn)
      Wait(Http.PACE_MS)
    end
    pacing = false
  end)
end
