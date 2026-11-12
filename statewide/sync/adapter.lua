Sync = { adapters = {} }

local own = GetCurrentResourceName()
local queue = Pure.syncQueueNew()
local refusals = {}
local warned = {}
local flushing, resyncing = false, false
local backoff = 0

local function cfg()
  return Config.sync or {}
end

local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(('^3[statewide] %s^7'):format(line))
end

local function active()
  local c = cfg()
  if not c.enabled then return nil end
  local adapter = Sync.adapters[c.framework or 'standalone']
  if not adapter then
    warnOnce('adapter', ('Config.sync.framework %s has no adapter.'):format(tostring(c.framework)))
    return nil
  end
  return adapter
end

function Sync.register(name, adapter)
  assert(type(name) == 'string' and type(adapter) == 'table', 'Sync.register(name, adapter)')
  assert(type(adapter.source) == 'string' and type(adapter.normalize) == 'function' and type(adapter.page) == 'function', 'adapter needs source, normalize and page')
  Sync.adapters[name] = adapter
end

local function post(entity, adapter, items, runId)
  local opts = { body = { source = adapter.source, runId = runId, items = items }, deadline = 15 }
  if entity == 'characters' then return api('POST', '/sync/characters', 'sync', opts) end
  if entity == 'vehicles' then return api('POST', '/sync/vehicles', 'sync', opts) end
  return api('POST', '/sync/licenses', 'sync', opts)
end

local function report(entity, results)
  local tally = Pure.syncTally({}, results)
  if (tally.error or 0) + (tally.conflict or 0) > 0 then
    print(('^3[statewide] sync %s: %d refused, %d in conflict.^7'):format(entity, tally.error or 0, tally.conflict or 0))
  end
  return tally
end

local function flush()
  local adapter = active()
  if not adapter then return end
  for _, entity in ipairs(Pure.SYNC_ENTITIES) do
    while queue[entity].n > 0 do
      local items = Pure.syncTake(queue, entity, Pure.SYNC_PUSH_MAX)
      local res = post(entity, adapter, items)
      if res.status == 200 then
        report(entity, res.data and res.data.results)
        backoff = 0
      elseif Pure.syncTransient(tonumber(res.status) or 0) then
        Pure.syncRequeue(queue, entity, items)
        backoff = math.min(math.max(backoff * 2, 5), 300)
        return
      else
        print(('^3[statewide] sync %s push refused (%s); %d items dropped.^7'):format(entity, tostring(res.problem and res.problem.code or res.status), #items))
      end
    end
  end
end

local function scheduleFlush()
  if flushing then return end
  flushing = true
  CreateThread(function()
    Wait(math.max(1, tonumber(cfg().flushSeconds) or 2) * 1000)
    while true do
      flush()
      if backoff == 0 then break end
      Wait(backoff * 1000)
    end
    flushing = false
    for _, entity in ipairs(Pure.SYNC_ENTITIES) do
      if queue[entity].n > 0 then return scheduleFlush() end
    end
  end)
end

function Sync.push(entity, data)
  local adapter = active()
  if not adapter then return false, 'disabled' end
  local item, reason = adapter.normalize(entity, data)
  if not item then return false, reason end
  if not Pure.syncEnqueue(queue, entity, item) then return false, 'queue_full' end
  scheduleFlush()
  return true
end

local function pushPage(entity, adapter, items, runId, totals)
  for attempt = 1, 3 do
    local res = post(entity, adapter, items, runId)
    if res.status == 200 then
      Pure.syncTally(totals, res.data and res.data.results)
      return true
    end
    if not Pure.syncTransient(tonumber(res.status) or 0) then return false, res.problem and res.problem.code or res.status end
    Wait(attempt * 5000)
  end
  return false, 'unreachable'
end

function Sync.resync()
  local adapter = active()
  if not adapter then return false, 'disabled' end
  if resyncing then return false, 'running' end
  resyncing = true
  local ok, err = pcall(function()
    local started = api('POST', '/sync/runs', 'sync', { body = { source = adapter.source } })
    if started.status ~= 201 or not started.data then error(('start refused (%s)'):format(tostring(started.problem and started.problem.code or started.status)), 0) end
    local runId = started.data.run.id
    local size = math.max(1, math.min(Pure.SYNC_PUSH_MAX, tonumber(cfg().pageSize) or Pure.SYNC_PUSH_MAX))
    local totals = {}
    for _, entity in ipairs(Pure.SYNC_ENTITIES) do
      local offset, skipped = 0, 0
      while true do
        local rows, pageErr = adapter.page(entity, offset, size)
        if not rows then error(('%s read failed: %s'):format(entity, tostring(pageErr)), 0) end
        local items = {}
        for i = 1, #rows do
          local item = adapter.normalize(entity, rows[i])
          if item then items[#items + 1] = item else skipped = skipped + 1 end
        end
        if #items > 0 then
          local pushed, why = pushPage(entity, adapter, items, runId, totals)
          if not pushed then error(('%s push failed: %s'):format(entity, tostring(why)), 0) end
        end
        if #rows < size then break end
        offset = offset + size
        Wait(0)
      end
      if skipped > 0 then print(('^3[statewide] sync %s: %d rows skipped (no id, owner, name or date).^7'):format(entity, skipped)) end
    end
    api('POST', '/sync/runs/{runId}/finish', 'sync', { params = { runId = runId }, body = {} })
    print(('[statewide] sync resync done: %d created, %d updated, %d unchanged, %d unlinked, %d conflicts, %d errors.'):format(totals.created or 0, totals.updated or 0,
        totals.unchanged or 0, totals.unlinked or 0, totals.conflict or 0, totals.error or 0))
  end)
  resyncing = false
  if not ok then print(('^3[statewide] sync resync stopped: %s^7'):format(tostring(err))) end
  return ok, not ok and err or nil
end

local function allowed(resource)
  for _, name in ipairs((Config.framework or {}).allow or {}) do
    if name == resource then return true end
  end
  return false
end

local function refuse(resource, reason)
  if Pure.refusalThrottle(refusals, resource, reason, GetGameTimer() / 1000, 60) then
    print(('^3[statewide] sync export refused from %s: %s^7'):format(tostring(resource), reason))
  end
  return false, reason
end

exports('SyncCharacter', function(data)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  return Sync.push('characters', data)
end)

exports('SyncVehicle', function(data)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  return Sync.push('vehicles', data)
end)

exports('SyncLicense', function(data)
  local resource = GetInvokingResource()
  if not resource or resource == own or not allowed(resource) then return refuse(resource or own, 'not_allowed') end
  return Sync.push('licenses', data)
end)

RegisterCommand('statewide_resync', function(src)
  if src ~= 0 then return end
  CreateThread(Sync.resync)
end, true)

CreateThread(function()
  Wait(10000)
  if cfg().enabled and cfg().resyncOnStart then Sync.resync() end
end)
