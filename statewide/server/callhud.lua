CallHud = {}

local raw = {}
local sent = {}
local seq = {}
local view = {}
local gone = {}
local lastAttach = {}
local hidden = {}
local queue, queued, first, last = {}, {}, 1, 0
local working, allDue = false, false
local batches = true
local READS_PER_SECOND = 10
local PLAYERS_PER_READ = 100

local function eligible(p)
  return Config.callHud.enabled and p ~= nil and p.unit ~= nil and Pure.accountOfState(p) ~= nil and Pure.hudEligible(p.unit)
end

local function licenseOf(src)
  return Pure.licenseFromIdentifiers(GetPlayerIdentifiers(src))
end

local function hiddenKey(license)
  return 'statewide:callhud:off:' .. license
end

local function optedOut(src)
  if hidden[src] == nil then
    local license = licenseOf(src)
    hidden[src] = license ~= nil and GetResourceKvpInt(hiddenKey(license)) == 1
  end
  return hidden[src]
end

local function current(src)
  local p = State.peek(src)
  if gone[src] or optedOut(src) or not eligible(p) then return nil end
  return p
end

local function sortedJoin(list)
  local out = {}
  if type(list) == 'table' then
    for i = 1, #list do out[i] = tostring(list[i]) end
  end
  table.sort(out)
  return table.concat(out, ',')
end

local function viewKey(p)
  if not p then return nil end
  local d = type(p.unit.department) == 'table' and p.unit.department or {}
  local a = type(p.agency) == 'table' and p.agency or {}
  return table.concat({
    Pure.playerItem(Pure.accountOfState(p)), tostring(d.id), tostring(d.type), tostring(a.isolation), tostring(a.viewAll == true),
    sortedJoin(a.departmentIds), sortedJoin(a.departmentTypes),
  }, '|')
end

local function push(src)
  if gone[src] then return end
  if optedOut(src) then
    if sent[src] and #sent[src].list > 0 then
      sent[src] = { key = json.encode({}), list = {} }
      TriggerClientEvent('statewide:client:callHud', src, {})
    end
    return
  end
  local p = current(src)
  local list = {}
  if p and raw[src] then list = Pure.hudCalls(raw[src], p.discordId, p.unit.callNumber) end
  local key = json.encode(list)
  if sent[src] and sent[src].key == key then return end
  sent[src] = { key = key, list = list }
  TriggerClientEvent('statewide:client:callHud', src, list)
end

function CallHud.list(src)
  return sent[src] and sent[src].list or {}
end

local function warn(err)
  print(('^3[statewide] call HUD: %s^7'):format(tostring(err)))
end

local function enqueue(src)
  src = tonumber(src)
  if not src or queued[src] or gone[src] then return end
  queued[src] = true
  last = last + 1
  queue[last] = src
end

local kick

function CallHud.refreshSoon(src)
  enqueue(src)
  kick()
end

local function invalidate(src)
  seq[src] = (seq[src] or 0) + 1
  view[src] = nil
  raw[src] = nil
  if sent[src] then push(src) end
  CallHud.refreshSoon(src)
end

local function begin(src, p)
  seq[src] = (seq[src] or 0) + 1
  view[src] = viewKey(p)
  return seq[src]
end

local function settled(src, mine)
  if seq[src] ~= mine or gone[src] then return false end
  if viewKey(current(src)) ~= view[src] then
    invalidate(src)
    return false
  end
  return true
end

local function readOne(src, p)
  local mine = begin(src, p)
  local ok, res = pcall(function()
    local account = Pure.accountOfState(p)
    return api('GET', '/calls', 'calls', { query = { discordId = Pure.playerSlot(account) }, as = account, retry = false })
  end)
  if not settled(src, mine) then return end
  if ok and type(res) == 'table' then
    if res.status == 200 and type(res.data) == 'table' and type(res.data.calls) == 'table' then
      raw[src] = res.data.calls
    elseif type(res.problem) == 'table' and res.problem.code == 'not_member' then
      raw[src] = nil
    end
  end
  push(src)
end

local function readMany(list)
  local ids, mine = {}, {}
  for i, item in ipairs(list) do
    ids[i] = item.p.discordId
    mine[i] = begin(item.src, item.p)
  end
  local ok, res = pcall(function()
    return api('GET', '/calls', 'calls', { query = { discordIds = table.concat(ids, ',') }, retry = false })
  end)
  local data = ok and type(res) == 'table' and res.status == 200 and type(res.data) == 'table' and res.data or nil
  if data and (type(data.views) ~= 'table' or type(data.players) ~= 'table') then
    batches = false
    warn('the CAD does not answer one read for many players; reading each player alone')
    for _, item in ipairs(list) do enqueue(item.src) end
    return
  end
  local viewOf = {}
  if data then
    for _, entry in ipairs(data.players) do
      if type(entry) == 'table' and type(entry.discordId) == 'string' and type(entry.view) == 'number' then viewOf[entry.discordId] = math.tointeger(entry.view) end
    end
  end
  for i, item in ipairs(list) do
    if settled(item.src, mine[i]) then
      if data then
        local index = viewOf[ids[i]]
        local shown = index and data.views[index + 1]
        raw[item.src] = type(shown) == 'table' and type(shown.calls) == 'table' and shown.calls or nil
      end
      push(item.src)
    end
  end
end

local function dequeue()
  local src = queue[first]
  queue[first] = nil
  first = first + 1
  queued[src] = nil
  return src
end

local function take()
  local many = {}
  while first <= last do
    local src = dequeue()
    local p = current(src)
    if not p then
      raw[src], view[src] = nil, nil
      if sent[src] then push(src) end
    elseif batches and p.discordId then
      many[#many + 1] = { src = src, p = p }
      if #many >= PLAYERS_PER_READ then break end
    else
      if #many > 0 then
        enqueue(src)
        break
      end
      return function() readOne(src, p) end
    end
  end
  if #many > 0 then return function() readMany(many) end end
  return nil
end

local function work()
  repeat
    local n = 0
    while first <= last and n < READS_PER_SECOND do
      local run = take()
      if run then
        local ok, err = pcall(run)
        if not ok then warn(err) end
        n = n + 1
      end
    end
    Wait(1000)
  until first > last
end

kick = function()
  if working or first > last then return end
  working = true
  CreateThread(function()
    local ok, err = pcall(work)
    working = false
    if not ok then warn(err) end
  end)
end

function CallHud.refresh(src)
  src = tonumber(src)
  if not src then return end
  local p = current(src)
  if not p then
    raw[src], view[src] = nil, nil
    if sent[src] then push(src) end
    return
  end
  if batches and p.discordId then return readMany({ { src = src, p = p } }) end
  readOne(src, p)
end

function CallHud.refreshAll()
  if allDue then return end
  allDue = true
  CreateThread(function()
    local ok, err = pcall(function()
      Wait(1000)
      allDue = false
      local units = State.onDuty()
      for i = 1, #units do enqueue(units[i].src) end
    end)
    allDue = false
    if not ok then warn(err) end
    kick()
  end)
end

function CallHud.closed(number)
  if not Pure.isCallNumber(number) then return end
  for src, calls in pairs(raw) do
    local kept = {}
    for _, c in ipairs(calls) do
      if type(c) ~= 'table' or c.number ~= number then kept[#kept + 1] = c end
    end
    if #kept ~= #calls then
      raw[src] = kept
      push(src)
    end
  end
end

function CallHud.changed(ev)
  if not Config.callHud.enabled or not Pure.HUD_EVENTS[ev.type] then return end
  if ev.type == 'call.closed' and type(ev.payload) == 'table' then CallHud.closed(ev.payload.number) end
  CallHud.refreshAll()
end

function CallHud.unitChanged(src)
  src = tonumber(src)
  if not src or gone[src] then return end
  if viewKey(current(src)) ~= view[src] then return invalidate(src) end
  if raw[src] then push(src) end
end

RegisterNetEvent('statewide:callHud', function(number)
  local src = tonumber(source)
  if not src or src <= 0 or not Config.callHud.enabled then return end
  if not Pure.isCallNumber(number) or not Pure.hudHas(CallHud.list(src), number) then return end
  local now = GetGameTimer() / 1000
  if not Pure.cooldown(lastAttach[src], now, Config.callHud.cooldown) then
    return Notify.player(src, L('callhud_cooldown'), 'error')
  end
  lastAttach[src] = now
  CreateThread(function()
    Handlers.attach(src, { number }, Config.commands.attach.name)
    CallHud.refreshSoon(src)
  end)
end)

Handlers.callhud = function(src, _, name)
  if not Config.callHud.enabled then return Notify.player(src, L('callhud_server_off'), 'error') end
  local license = licenseOf(src)
  if not license then return Notify.player(src, L('callhud_no_license'), 'error') end
  local off = not optedOut(src)
  if off then
    SetResourceKvpInt(hiddenKey(license), 1)
  else
    DeleteResourceKvp(hiddenKey(license))
  end
  hidden[src] = off
  if off then
    raw[src], view[src] = nil, nil
    push(src)
    return Notify.player(src, L('callhud_hidden', name), 'success')
  end
  CallHud.refreshSoon(src)
  Notify.player(src, L('callhud_shown'), 'success')
end

local function forget(src)
  raw[src], sent[src], seq[src], view[src], lastAttach[src], hidden[src] = nil, nil, nil, nil, nil, nil
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  gone[src] = true
  forget(src)
end)

AddEventHandler('playerJoining', function()
  local src = tonumber(source)
  if not src then return end
  gone[src] = nil
  forget(src)
end)
