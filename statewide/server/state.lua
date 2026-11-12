State = {}

local players = {}
local KVP_UNITS = 'statewide:units'
local ours

local function loadOurs()
  if ours then return ours end
  ours = {}
  local ok, list = pcall(json.decode, GetResourceKvpString(KVP_UNITS) or '[]')
  if ok and type(list) == 'table' then
    for _, d in ipairs(list) do
      if type(d) == 'string' then ours[d] = true end
    end
  end
  return ours
end

local function saveOurs()
  local list = {}
  for d in pairs(ours) do list[#list + 1] = d end
  table.sort(list)
  SetResourceKvp(KVP_UNITS, json.encode(list))
end

function State.ours()
  return loadOurs()
end

function State.claim(discordId)
  if not discordId then return end
  loadOurs()[discordId] = true
  saveOurs()
end

function State.release(discordId)
  if not discordId or not loadOurs()[discordId] then return end
  ours[discordId] = nil
  saveOurs()
end

local roster = {}
local KVP_RESPONDERS = 'statewide:responders'
local responders
local savingResponders
State.RESPONDERS_SAVE_MS = 10000

local function loadResponders()
  if responders then return responders end
  local ok, map = pcall(function() return json.decode(GetResourceKvpString(KVP_RESPONDERS) or '{}') end)
  responders = Pure.pruneResponders(ok and map or nil, os.time(), Pure.RESPONDER_MAX_AGE_S, Pure.RESPONDER_CAP)
  return responders
end

local function saveRespondersSoon()
  if savingResponders then return end
  savingResponders = true
  SetTimeout(State.RESPONDERS_SAVE_MS, function()
    savingResponders = nil
    responders = Pure.pruneResponders(loadResponders(), os.time(), Pure.RESPONDER_MAX_AGE_S, Pure.RESPONDER_CAP)
    pcall(function() SetResourceKvp(KVP_RESPONDERS, json.encode(responders)) end)
  end)
end

function State.noteUnits(units)
  roster = Pure.unitRoster(units)
end

function State.noteDuty(discordId, onDuty)
  if type(discordId) ~= 'string' then return end
  roster[discordId] = onDuty and true or nil
end

function State.noteResponder(discordId, isResponder)
  if Pure.noteResponder(loadResponders(), discordId, isResponder, os.time()) then saveRespondersSoon() end
end

function State.joinRank(discordId)
  return Pure.joinRank(discordId, roster, loadOurs(), loadResponders())
end

local function copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
State.copy = copy

function State.get(src)
  src = tonumber(src)
  local p = players[src]
  if not p then
    p = {}
    if src and GetPlayerName(src) then players[src] = p end
  end
  return p
end

function State.peek(src)
  return players[tonumber(src)]
end

local isolation

function State.isolation()
  return isolation
end

local BAG_KEY = 'statewide:unit'
local bagSet = {}
local bagRevert = {}
State.BAG_REVERT_MS = 1000

local function setBag(src, value)
  local ok, bag = pcall(function() return Player(src).state end)
  if not ok or not bag then return end
  bagSet[src] = { value = value }
  local fine, err = pcall(bag.set, bag, BAG_KEY, value, true)
  if not fine then
    bagSet[src] = nil
    error(err, 0)
  end
end

local function mirror(src, unit)
  if not src then return end
  local value = Pure.unitBag(unit, Pure.stateBagMode(Config.stateBag, isolation))
  local last = bagSet[src]
  if last and Pure.sameBag(last.value, value) then return end
  setBag(src, value)
end

AddStateBagChangeHandler(BAG_KEY, nil, function(bagName, _, value)
  local src = tonumber(type(bagName) == 'string' and bagName:match('^player:(%d+)$'))
  local last = src and bagSet[src]
  if not last or bagRevert[src] or Pure.sameBag(last.value, value) then return end
  bagRevert[src] = true
  SetTimeout(State.BAG_REVERT_MS, function()
    bagRevert[src] = nil
    local now = bagSet[src]
    if now then setBag(src, now.value) end
  end)
end)

State.UNITS_DEBOUNCE_MS = 1000
State.UNITS_BPS = 50000
State.UNITS_RESYNC_S = 5

local UNITS_EVENT = 'statewide:client:units'
local scopes = {}
local lastSent = {}
local version = 0
local dirty = {}
local keyCache = {}

local function scopeKey(src, p)
  local c = keyCache[src]
  if c and c.agency == p.agency and c.mode == isolation then return c.key end
  local key = Pure.unitScope(p.agency, isolation)
  keyCache[src] = { agency = p.agency, mode = isolation, key = key }
  return key
end

function State.touch(src)
  src = tonumber(src)
  if src then dirty[src] = true end
end

local function formsOf(src, unit, cache)
  local f = cache[src]
  if not f then
    f = Pure.unitForms(src, unit, isolation)
    cache[src] = f
  end
  return f
end

local function pick(f, viewer)
  if Pure.isMasked(f.ref, viewer, isolation) then return f.masked end
  return f.visible
end

local function onDutyForms(cache)
  local list = {}
  for src, p in pairs(players) do
    if p.unit then list[#list + 1] = formsOf(src, p.unit, cache) end
  end
  table.sort(list, function(a, b) return a.src < b.src end)
  return list
end

local function buildScope(viewer, base)
  local view, byId = {}, {}
  for i = 1, #base do
    local e = pick(base[i], viewer)
    view[i] = e
    byId[e.id] = e
  end
  version = version + 1
  return { v = version, viewer = viewer, byId = byId, full = { v = version, full = view } }
end

local function updateScope(s, changed, cache)
  local set, remove = {}, {}
  for i = 1, #changed do
    local src = changed[i]
    local p = players[src]
    local old = s.byId[src]
    if p and p.unit then
      local e = pick(formsOf(src, p.unit, cache), s.viewer)
      if not old or not Pure.sameUnitEntry(old, e) then
        s.byId[src] = e
        set[#set + 1] = e
      end
    elseif old then
      s.byId[src] = nil
      remove[#remove + 1] = src
    end
  end
  if #set == 0 and #remove == 0 then return end
  local base = s.v
  version = version + 1
  s.v = version
  s.full = nil
  s.diff = { v = version, base = base, set = set, remove = remove }
end

local function fullOf(s)
  if not s.full then s.full = { v = s.v, full = Pure.sortedUnits(s.byId) } end
  return s.full
end

local function sendUnits(src, msg)
  TriggerLatentClientEvent(UNITS_EVENT, src, State.UNITS_BPS, msg)
end

local failed = {}

local function failOnce(kind, err)
  local key = kind .. ':' .. (tostring(err):gsub('%d+', '#'))
  if failed[key] then return end
  failed[key] = true
  print(('^1[statewide] %s: %s^7'):format(kind, tostring(err)))
end

local function sendViews(changed)
  local built, cache, base = {}, {}, nil
  for src, p in pairs(players) do
    if Pure.receivesUnits(p) then
      local key = scopeKey(src, p)
      local s = built[key]
      if not s then
        s = scopes[key]
        if s then
          if #changed > 0 then updateScope(s, changed, cache) end
        else
          base = base or onDutyForms(cache)
          s = buildScope(p.agency, base)
        end
        built[key] = s
      end
      local last = lastSent[src]
      if not last or last.key ~= key or last.v ~= s.v then
        local msg = (last and last.key == key and s.diff and last.v == s.diff.base and s.diff.v == s.v) and s.diff or fullOf(s)
        lastSent[src] = { key = key, v = s.v }
        sendUnits(src, msg)
      end
    elseif lastSent[src] then
      lastSent[src] = nil
      version = version + 1
      sendUnits(src, { v = version, full = {} })
    end
  end
  scopes = built
end

local broadcasting, rebuilding

function State.broadcast()
  local changed = {}
  for src in pairs(dirty) do changed[#changed + 1] = src end
  table.sort(changed)
  dirty = {}
  local ok, err = pcall(sendViews, changed)
  if ok then
    rebuilding = nil
  else
    failOnce('unit list broadcast', err)
    scopes, lastSent, keyCache = {}, {}, {}
    if not rebuilding then
      rebuilding = true
      State.broadcastSoon()
    end
  end
  if SceneMarkers then SceneMarkers.syncAll() end
end

function State.broadcastSoon()
  if broadcasting then return end
  broadcasting = true
  SetTimeout(State.UNITS_DEBOUNCE_MS, function()
    broadcasting = nil
    State.broadcast()
  end)
end

local resyncAt = {}

RegisterNetEvent('statewide:unitsSync', function()
  local src = tonumber(source)
  if not src or src <= 0 or not players[src] then return end
  local now = GetGameTimer() / 1000
  if not Pure.cooldown(resyncAt[src], now, State.UNITS_RESYNC_S) then return end
  resyncAt[src] = now
  lastSent[src] = nil
  State.broadcastSoon()
end)

function State.viewer(src)
  local p = players[tonumber(src)]
  return p and p.agency
end

local function applyMode(mode)
  if not mode or mode == isolation then return end
  isolation = mode
  for s, other in pairs(players) do
    if other.unit then mirror(s, other.unit) end
  end
end

function State.setAgency(src, agency)
  local p = State.get(src)
  p.agency = type(agency) == 'table' and agency or nil
  applyMode(p.agency and Pure.isolationMode(p.agency.isolation))
  State.broadcastSoon()
  if CallHud then CallHud.unitChanged(src) end
end

function State.setIsolation(mode)
  mode = Pure.isolationMode(mode)
  if not mode then return false end
  for src, p in pairs(players) do
    if p.agency then
      p.agency.isolation = mode
      State.setAgency(src, p.agency)
    end
  end
  applyMode(mode)
  State.broadcastSoon()
  return true
end

local unitListeners = {}

function State.onUnitChange(cb)
  unitListeners[#unitListeners + 1] = cb
end

function State.setUnit(src, unit)
  if unit and unit.status and unit.status.meaning == 'off_duty' then unit = nil end
  local p = State.get(src)
  local before = p.unit
  local was = before ~= nil
  p.unit = unit
  for _, cb in ipairs(unitListeners) do
    local ok, err = pcall(cb, tonumber(src), unit, before)
    if not ok then print(('^1[statewide] unit change: %s^7'):format(err)) end
  end
  State.noteDuty(p.discordId, unit ~= nil)
  State.touch(src)
  mirror(tonumber(src), unit)
  State.broadcastSoon()
  if not unit and was then
    State.release(p.discordId)
    if Config.tablet.requireDuty then TriggerClientEvent('statewide:client:tablet', tonumber(src), { drop = true }) end
  end
  if (unit ~= nil) ~= was then
    p.trackingHidden = nil
    if not unit then p.labels = nil end
    if Locations then Locations.forget(src) end
  end
  if unit and type(unit.mapHidden) == 'boolean' then p.trackingHidden = unit.mapHidden or nil end
  if unit and not was and Locations then Locations.markDirty(src) end
  if CallHud then CallHud.unitChanged(src) end
end

local characterListeners = {}

function State.onCharacterChange(cb)
  characterListeners[#characterListeners + 1] = cb
end

function State.setCharacter(src, character)
  local p = State.get(src)
  local before = p.character
  p.character = character
  if (before and before.id) == (character and character.id) then return end
  for _, cb in ipairs(characterListeners) do
    local ok, err = pcall(cb, tonumber(src), character, before)
    if not ok then print(('^1[statewide] character change: %s^7'):format(err)) end
  end
end

local function readopt(account, unit)
  if not Pure.dropped(unit) then return unit end
  local res = api('POST', '/units/{discordId}/connection', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { connected = true }, as = account })
  if res.status == 200 and res.data then
    local back = type(res.data.unit) == 'table' and res.data.unit or nil
    if back then State.claim(account.discordId) else State.release(account.discordId) end
    return back
  end
  if res.problem and res.problem.code == 'not_found' then
    State.release(account.discordId)
    return nil
  end
  return unit
end

local tokens = {}

function State.join(src)
  src = tonumber(src)
  tokens[src] = (tokens[src] or 0) + 1
  return tokens[src]
end

function State.token(src)
  return tokens[tonumber(src)]
end

function State.refresh(src, priority)
  local token = tokens[tonumber(src)]
  local res, account = Identity.resolve(src, function(a)
    return api('GET', '/players/{discordId}', 'units', { params = { discordId = Pure.playerSlot(a) }, as = a, priority = priority })
  end)
  if not res then return nil end
  if tokens[tonumber(src)] ~= token or not Pure.sameAccount(Identity.getAccount(src), account) then return res end
  if res.status == 200 and res.data and Pure.dropped(res.data.unit) then
    res.data.unit = readopt(account, res.data.unit)
    if tokens[tonumber(src)] ~= token or not Pure.sameAccount(Identity.getAccount(src), account) then return res end
  end
  if res.status == 200 and res.data then
    local p = State.get(src)
    p.discordId = account.discordId
    p.membershipId = type(res.data.member) == 'table' and res.data.member.membershipId or nil
    p.account = account
    p.checkedAt = GetGameTimer()
    State.setAgency(src, res.data.agency)
    State.setUnit(src, res.data.unit)
    State.setCharacter(src, res.data.activeCharacter)
    State.noteResponder(account.discordId, Pure.receivesUnits(p))
  elseif res.problem and (res.problem.code == 'not_member' or res.problem.code == 'identity_mismatch') then
    local p = State.get(src)
    p.membershipId = nil
    p.checkedAt = GetGameTimer()
    State.setAgency(src, nil)
    State.setUnit(src, nil)
    State.setCharacter(src, nil)
    if res.problem.code == 'not_member' then State.noteResponder(account.discordId, false) end
  end
  return res
end

State.REVALIDATE_S = 120
State.REVALIDATE_FLOOR_MS = 250

function State.revalidateNext(now)
  local due = {}
  for src, p in pairs(players) do
    if Pure.receivesUnits(p) then due[#due + 1] = { src = src, checkedAt = p.checkedAt } end
  end
  return Pure.revalidateNext(due, now, State.REVALIDATE_S * 1000, State.REVALIDATE_FLOOR_MS)
end

function State.revalidate(generation)
  CreateThread(function()
    while Lifecycle.generation == generation do
      local ok, out = pcall(function()
        local src, waitMs = State.revalidateNext(GetGameTimer())
        if src then
          local p = players[src]
          if p then p.checkedAt = GetGameTimer() end
          State.refresh(src, 'low')
        end
        return waitMs
      end)
      if not ok then failOnce('agency recheck', out) end
      Wait(ok and out or State.REVALIDATE_FLOOR_MS)
    end
  end)
end

function State.forget(src)
  State.join(src)
  State.touch(src)
  players[tonumber(src)] = nil
  bagSet[tonumber(src)] = nil
  keyCache[tonumber(src)] = nil
  lastSent[tonumber(src)] = nil
  resyncAt[tonumber(src)] = nil
  State.broadcastSoon()
end

function State.onDuty()
  local out = {}
  for src, p in pairs(players) do
    if p.unit then out[#out + 1] = { src = src, discordId = p.unit.discordId or p.discordId, membershipId = p.unit.membershipId or p.membershipId,
        deptType = p.unit.department and p.unit.department.type } end
  end
  table.sort(out, function(a, b) return a.src < b.src end)
  return out
end

function State.all()
  return players
end

function State.connected()
  local out = {}
  for src, p in pairs(players) do
    if p.discordId or p.membershipId then out[#out + 1] = { src = src, discordId = p.discordId, membershipId = p.membershipId } end
  end
  table.sort(out, function(a, b) return a.src < b.src end)
  return out
end

function State.readCoords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
  local c = GetEntityCoords(ped)
  local p = State.get(src)
  p.coords = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }
  return p.coords
end
