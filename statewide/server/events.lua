Events = {}

local callers = {}
local waiting = {}
local refreshing = {}
local duty = {}
local pending = {}

local function queuePush(src, item)
  if not item then return end
  local list = pending[src]
  if list then
    list[#list + 1] = item
    return
  end
  local items = { item }
  pending[src] = items
  SetTimeout(Pure.PUSH_WINDOW_MS, function()
    if pending[src] ~= items then return end
    pending[src] = nil
    for _, line in ipairs(Pure.coalescePushes(items, Pure.PUSH_NOTES_MAX)) do
      Notify.player(src, L(line.key, table.unpack(line.args)), 'info')
    end
  end)
end

local function refreshSoon(src)
  if refreshing[src] then return end
  refreshing[src] = true
  CreateThread(function()
    Wait(500)
    refreshing[src] = nil
    local ev = duty[src]
    duty[src] = nil
    if ev then
      local p = State.peek(src)
      queuePush(src, Pure.dutyItem(ev.type, ev.payload, p and p.unit))
    end
    State.refresh(src)
  end)
end

local function statusChanged(src, payload)
  local p = State.peek(src)
  local u = p and p.unit
  if not u then return true end
  return not (u.status and u.status.code == payload.status and u.callNumber == payload.attachedCallNumber)
end

function Events.rememberCaller(number, coords)
  if number and coords then callers[number] = { coords = coords, at = GetGameTimer() } end
end

function Events.awaitUnits(number, src)
  local account = Identity.getAccount(src)
  if not number or not account then return end
  local p = State.peek(src)
  waiting[number] = { src = tonumber(src), account = account, discordId = account.discordId, membershipId = p and p.membershipId, at = GetGameTimer() }
end

local function forEachMember(payload, fn)
  for src, p in pairs(State.all()) do
    if Pure.namesPlayer(payload.membershipId, payload.discordId, p) then fn(src, p) end
  end
end

local function handle(ev)
  if CallHud then CallHud.changed(ev) end
  local route = Pure.EVENT_ROUTES[ev.type]
  if not route or type(ev.payload) ~= 'table' then return end
  if route.markers then return SceneMarkers and SceneMarkers.apply(ev) end
  if route.settings then
    if not State.setIsolation(ev.payload.agencyIsolation) then return end
    return CreateThread(function()
      for _, p in ipairs(State.connected()) do
        State.refresh(p.src, 'low')
        Wait(100)
      end
    end)
  end
  if route.citation then
    TriggerEvent(route.event, State.copy(ev.payload))
    local handed = { recordId = ev.payload.recordId, number = ev.payload.number }
    return forEachMember(ev.payload, function(src) CreateThread(function() Citations.offer(src, 'push', handed) end) end)
  end
  if route.refresh then
    if ev.type == 'unit.signed_on' or ev.type == 'unit.signed_off' then State.noteDuty(ev.payload.discordId, ev.type == 'unit.signed_on') end
    for _, src in ipairs(Pure.refreshTargets(ev.type, ev.payload, State.connected())) do
      if ev.type == 'character.active_changed' then
        local p = State.peek(src)
        if Pure.characterChanged(p and p.character, ev.payload) then refreshSoon(src) end
      else
        if ev.type ~= 'unit.status' then duty[src] = ev end
        if ev.type ~= 'unit.status' or statusChanged(src, ev.payload) then refreshSoon(src) end
      end
    end
    return
  end
  TriggerEvent(route.event, State.copy(ev.payload))
  local recipients = Pure.selectRecipients(ev.type, ev.payload, State.onDuty())
  if route.queue then
    for _, dst in ipairs(recipients) do
      queuePush(dst, Pure.queueItem(ev.type, ev.payload, State.viewer(dst), State.isolation()))
      if ev.type == 'call.unit_detached' then refreshSoon(dst) end
    end
    return
  end
  if ev.type == 'call.unit_attached' then
    local caller = Pure.takeCaller(waiting, ev.payload.number, ev.payload, Identity.getAccount)
    if caller then Notify.player(caller, L('call_responding', ev.payload.number), 'success') end
  elseif ev.type == 'call.closed' and ev.payload.number then
    waiting[ev.payload.number] = nil
  end
  local push = Pure.pushPayload(ev.type, ev.payload)
  if ev.type == 'call.unit_attached' then Arrival.attached(recipients, ev.payload) end
  if ev.type == 'unit.forced_off' then
    forEachMember(ev.payload, function(src)
      State.setUnit(src, nil)
      refreshSoon(src)
    end)
    for _, dst in ipairs(recipients) do Notify.push(dst, route.push, Pure.pushPayload(ev.type, ev.payload, State.viewer(dst), State.isolation())) end
    return
  elseif ev.type == 'unit.panic' then
    forEachMember(ev.payload, function(src, p)
      if p.unit then
        p.unit.isPanic = true
        State.touch(src)
      end
    end)
    State.broadcastSoon()
    local ref = { departmentId = ev.payload.departmentId, departmentType = ev.payload.departmentType, department = ev.payload.department }
    for _, dst in ipairs(recipients) do Notify.push(dst, route.push, Pure.panicPushFor(push, ref, State.viewer(dst), State.isolation())) end
    return
  elseif ev.type == 'call.911' then
    local at = Pure.callCoords(ev.payload)
    if at then
      callers[ev.payload.number] = nil
      if Config.blips.call911 then push.coords = at end
      for _, dst in ipairs(recipients) do Notify.push(dst, route.push, push) end
      return
    end
    return CreateThread(function()
      Wait(250)
      local caller = callers[ev.payload.number]
      callers[ev.payload.number] = nil
      if caller and Config.blips.call911 then push.coords = caller.coords end
      for _, dst in ipairs(Pure.selectRecipients(ev.type, ev.payload, State.onDuty())) do Notify.push(dst, route.push, push) end
    end)
  end
  for _, dst in ipairs(recipients) do Notify.push(dst, route.push, push) end
end

Events.handle = handle

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  pending[src] = nil
  duty[src] = nil
end)

function Events.start(generation)
  CreateThread(function()
    local cursor
    local failures = 0
    while Lifecycle.generation == generation do
      local query = { wait = 4 }
      if cursor then query.after = cursor end
      local ok, res = pcall(function() return api('GET', '/events', 'calls', { query = query, retry = false }) end)
      if Lifecycle.generation ~= generation then return end
      if ok and res.status == 200 and res.data then
        failures = 0
        for _, ev in ipairs(res.data.events or {}) do
          local handled, err = pcall(handle, ev)
          if not handled then print(('^1[statewide] event %s: %s^7'):format(tostring(ev.type), err)) end
        end
        cursor = res.data.cursor or cursor
      elseif ok and res.problem and res.problem.code == 'resync' and res.problem.cursor then
        failures = 0
        cursor = res.problem.cursor
        CreateThread(Lifecycle.reconcile)
        Wait(1000)
      else
        failures = failures + 1
        local delay = Pure.backoff(failures, math.random())
        if ok and res.problem and res.problem.retryAfter then delay = math.max(delay, res.problem.retryAfter) end
        Wait(math.floor(delay * 1000))
      end
      local now = GetGameTimer()
      for number, c in pairs(callers) do
        if now - c.at > 120000 then callers[number] = nil end
      end
      for number, w in pairs(waiting) do
        if now - w.at > 3600000 then waiting[number] = nil end
      end
    end
  end)
end
