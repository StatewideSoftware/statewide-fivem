Pure = {}

local DEPT_RESPONDERS = { LEO = true, FIRE = true, EMS = true }

Pure.LOCATIONS_MAX = 128
Pure.COORD_LIMIT = 16000
Pure.LOCATION_MAX = 120
Pure.QUEUE_MAX = 50

function Pure.discordFromIdentifiers(identifiers)
  for _, id in ipairs(identifiers or {}) do
    local d = type(id) == 'string' and id:match('^discord:(%d+)$')
    if d and #d >= 15 and #d <= 22 then return d end
  end
  return nil
end

function Pure.licenseFromIdentifiers(identifiers)
  for _, id in ipairs(identifiers or {}) do
    local l = type(id) == 'string' and id:match('^license:(%x+)$')
    if l and #l == 40 then return 'license:' .. l:lower() end
  end
  return nil
end

function Pure.identityConfig(cfg)
  if type(cfg) ~= 'table' then return { requireDiscord = false, allowLink = false } end
  return { requireDiscord = cfg.requireDiscord == true, allowLink = cfg.allowLink == true }
end

function Pure.joinRefusal(cfg, identifiers)
  if not Pure.identityConfig(cfg).requireDiscord then return nil end
  if Pure.discordFromIdentifiers(identifiers) then return nil end
  return 'join_no_discord'
end

function Pure.playerIds(identifiers)
  return { discordId = Pure.discordFromIdentifiers(identifiers), license = Pure.licenseFromIdentifiers(identifiers) }
end

function Pure.accountOrder(cfg, ids)
  local out = {}
  if ids.discordId then out[#out + 1] = { discordId = ids.discordId, license = ids.license } end
  if ids.license and Pure.identityConfig(cfg).allowLink then out[#out + 1] = { license = ids.license } end
  return out
end

function Pure.pickAccount(candidates, lookup)
  local last
  for _, account in ipairs(candidates) do
    local res = lookup(account)
    if res.status == 200 then return account, res, true end
    if not (res.problem and res.problem.code == 'not_member') then return candidates[1], res, nil end
    last = res
  end
  return candidates[1], last, false
end

function Pure.accountOfState(p)
  if type(p) ~= 'table' then return nil end
  return p.account or (p.discordId and { discordId = p.discordId }) or nil
end

function Pure.playerSlot(account)
  return account.discordId or 'license'
end

function Pure.withPlayer(account, body)
  body = body or {}
  body.discordId = account.discordId
  body.license = not account.discordId and account.license or nil
  return body
end

function Pure.playerItem(account)
  return account.discordId or account.license
end

function Pure.sameAccount(a, b)
  return type(a) == 'table' and type(b) == 'table' and Pure.playerItem(a) ~= nil and Pure.playerItem(a) == Pure.playerItem(b)
end

function Pure.identityKnown(ids)
  return type(ids) == 'table' and (ids.discordId ~= nil or ids.license ~= nil)
end

function Pure.playerHeaders(account)
  if type(account) ~= 'table' or type(account.license) ~= 'string' then return nil end
  return { ['Statewide-License'] = account.license }
end

function Pure.namesPlayer(membershipId, discordId, p)
  if type(p) ~= 'table' then return false end
  if membershipId ~= nil and p.membershipId ~= nil then return p.membershipId == membershipId end
  return discordId ~= nil and p.discordId == discordId
end

local function listHas(list, v)
  if v == nil or type(list) ~= 'table' then return false end
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

function Pure.inPlayers(membershipIds, discordIds, p)
  if type(p) ~= 'table' then return false end
  if type(membershipIds) == 'table' and p.membershipId ~= nil then return listHas(membershipIds, p.membershipId) end
  return listHas(discordIds, p.discordId)
end

function Pure.needsLinkHint(cfg, tabletEnabled, ids, resolved)
  return tabletEnabled == true and Pure.identityConfig(cfg).allowLink and ids ~= nil and ids.discordId == nil and ids.license ~= nil and resolved == false
end

function Pure.chunk(list, size)
  local out, cur = {}, {}
  for _, v in ipairs(list) do
    cur[#cur + 1] = v
    if #cur == size then out[#out + 1], cur = cur, {} end
  end
  if #cur > 0 then out[#out + 1] = cur end
  return out
end

local JSON_ESCAPES = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '', f = '', n = ' ', r = ' ', t = ' ' }

local function firstErrorMessage(body)
  local at = body:find('"errors"%s*:%s*%[%s*{')
  if not at then return nil end
  local _, open = body:find('"message"%s*:%s*"', at)
  if not open then return nil end
  local out, i = {}, open + 1
  while i <= #body do
    local ch = body:sub(i, i)
    if ch == '"' then return table.concat(out) end
    if ch == '\\' then
      local nx = body:sub(i + 1, i + 1)
      if nx == 'u' then
        local cp = tonumber(body:sub(i + 2, i + 5), 16)
        if cp then out[#out + 1] = utf8.char(cp) end
        i = i + 6
      else
        out[#out + 1] = JSON_ESCAPES[nx] or nx
        i = i + 2
      end
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return nil
end

function Pure.parseHttpError(errorData)
  if type(errorData) ~= 'string' then return { status = 0 } end
  local status, body = errorData:match('^HTTP (%d+): (.*)$')
  if not status then return { status = 0 } end
  local out = { status = tonumber(status), body = body }
  out.code = body:match('"code"%s*:%s*"([%w_]+)"')
  out.retryAfter = tonumber(body:match('"retryAfter"%s*:%s*(%d+)'))
  out.cursor = body:match('"cursor"%s*:%s*"(%d+)"')
  out.reason = body:match('"reason"%s*:%s*"([%w_]+)"')
  out.detail = body:match('"detail"%s*:%s*"([^"]*)"')
  out.errorMessage = firstErrorMessage(body)
  return out
end

function Pure.problemMessage(problem, locale)
  problem = problem or { status = 0 }
  if problem.pending and locale.err_pending then return locale.err_pending end
  if problem.unanswered and locale.err_unanswered then return locale.err_unanswered end
  if problem.status == 0 then return locale.err_network end
  if problem.errorMessage and problem.errorMessage ~= '' then return problem.errorMessage end
  if problem.code and problem.reason and locale['err_' .. problem.code .. '_' .. problem.reason] then
    return locale['err_' .. problem.code .. '_' .. problem.reason]
  end
  local line = problem.code and locale['err_' .. problem.code]
  if line then return line end
  return (locale.err_generic):format(problem.status)
end

function Pure.backoff(attempt, rand)
  if attempt <= 0 then return 0 end
  local base = math.min(30, 2 ^ (attempt - 1))
  local delay = base / 2 + base / 2 * rand + 0.5
  return math.max(1, math.min(30, delay))
end

function Pure.cooldown(last, now, seconds)
  if not last or seconds <= 0 or now - last >= seconds then return true, 0 end
  return false, math.ceil(seconds - (now - last))
end

function Pure.useCooldown(store, bucket, now, seconds)
  local ok, left = Pure.cooldown(store[bucket], now, seconds or 0)
  if ok then store[bucket] = now end
  return ok, left
end

Pure.KEYED_COOLDOWN_MAX = 64

function Pure.useKeyedCooldown(store, key, now, seconds, cap)
  seconds, cap = seconds or 0, math.max(1, cap or Pure.KEYED_COOLDOWN_MAX)
  store.at, store.n = store.at or {}, store.n or 0
  local ok, left = Pure.cooldown(store.at[key], now, seconds)
  if not ok then return false, left end
  if store.at[key] == nil then
    if store.n >= cap then
      for k, t in pairs(store.at) do
        if now - t >= seconds then store.at[k], store.n = nil, store.n - 1 end
      end
    end
    while store.n >= cap do
      local oldest, at
      for k, t in pairs(store.at) do
        if at == nil or t < at then oldest, at = k, t end
      end
      store.at[oldest], store.n = nil, store.n - 1
    end
    store.n = store.n + 1
  end
  store.at[key] = now
  return true, 0
end

function Pure.callBucket(action)
  if action == '311' or action == '311a' then return '311' end
  return '911'
end

function Pure.callRefusalKey(problem, unit)
  if unit and problem and problem.code == 'no_active_character' then return 'err_no_active_character_on_duty' end
  return nil
end

function Pure.resolveCommands(commands)
  local seen, out = {}, {}
  local actions = {}
  for action in pairs(commands) do actions[#actions + 1] = action end
  table.sort(actions)
  for _, action in ipairs(actions) do
    local c = commands[action]
    if c.enabled ~= false then
      local names = { c.name }
      for _, a in ipairs(c.aliases or {}) do names[#names + 1] = a end
      for _, n in ipairs(names) do
        if type(n) ~= 'string' or not n:match('^[%w_%-]+$') then return nil, ('command %s: bad name %s'):format(action, tostring(n)) end
        local k = n:lower()
        if seen[k] then return nil, ('command name /%s is used by %s and %s'):format(n, seen[k], action) end
        seen[k] = action
      end
      out[#out + 1] = { action = action, names = names }
    end
  end
  return out
end

local function semver(v)
  local a, b, c = tostring(v or ''):match('^v?(%d+)%.(%d+)%.(%d+)')
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

function Pure.versionLessThan(a, b)
  local x, y = semver(a), semver(b)
  if not x or not y then return false end
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] < y[i] end
  end
  return false
end

function Pure.selectRecipients(kind, payload, onDuty)
  local out = {}
  local function pick(fn)
    for _, u in ipairs(onDuty) do
      if fn(u) then out[#out + 1] = u.src end
    end
  end
  local function named(u) return Pure.namesPlayer(payload.membershipId, payload.discordId, u) end
  local function listed(u) return Pure.inPlayers(payload.membershipIds, payload.discordIds, u) end
  if kind == 'call.911' or kind == 'fallback911' then
    pick(function(u) return DEPT_RESPONDERS[u.deptType] end)
  elseif kind == 'call.created' then
    if payload.origin == 'non_emergency' then pick(function(u) return u.deptType == 'LEO' or u.deptType == 'DISPATCH' end) end
  elseif kind == 'unit.panic' then
    pick(function() return true end)
  elseif kind == 'call.unit_attached' or kind == 'unit.forced_off' then
    pick(named)
  elseif kind == 'call.closed' then
    pick(listed)
  elseif kind == 'call.unit_detached' then
    if type(payload.by) == 'string' and payload.self ~= true then pick(named) end
  elseif kind == 'call.event' then
    pick(function(u) return listed(u) and not Pure.namesPlayer(payload.byMembershipId, payload.byDiscordId, u) end)
  end
  return out
end

Pure.TYPE_MASK_LABELS = {
  LEO = 'LAW', FIRE = 'FIRE', EMS = 'EMS', DISPATCH = 'DISPATCH', DOT = 'DOT', DMV = 'DMV', JUDICIAL = 'JUDICIAL', CIVILIAN = 'CIV', STAFF = 'STAFF',
}

local ISOLATION_MODES = { off = true, department = true, department_type = true }

function Pure.isolationMode(v)
  return ISOLATION_MODES[v] and v or nil
end

local function has(list, v)
  if v == nil or type(list) ~= 'table' then return false end
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

function Pure.unitRef(unit)
  local d = type(unit) == 'table' and type(unit.department) == 'table' and unit.department or {}
  return { departmentId = d.id, departmentType = d.type, department = d.abbreviation }
end

function Pure.isMasked(ref, viewer, mode)
  if mode == 'off' then return false end
  if ref.departmentType == 'DISPATCH' then return false end
  if type(viewer) ~= 'table' then return true end
  if viewer.viewAll == true then return false end
  if mode == 'department_type' then return not has(viewer.departmentTypes, ref.departmentType) end
  return not has(viewer.departmentIds, ref.departmentId)
end

function Pure.maskLabel(ref, mode)
  if mode == 'department_type' then return Pure.TYPE_MASK_LABELS[ref.departmentType] end
  return ref.department
end

function Pure.stateBagMode(setting, mode)
  if setting == 'full' or setting == 'minimal' then return setting end
  return mode == 'off' and 'full' or 'minimal'
end

function Pure.unitBag(unit, bagMode)
  if not unit then return nil end
  local status = unit.status and unit.status.code
  if bagMode ~= 'full' then return { onDuty = true, status = status } end
  return {
    onDuty = true,
    callsign = unit.callsign,
    department = unit.department and unit.department.abbreviation,
    status = status,
    isPanic = unit.isPanic,
  }
end

function Pure.sameBag(a, b)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(a) do
    if not Pure.sameBag(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

Pure.JOIN_RANK = { unit = 1, responder = 2, other = 3 }

function Pure.joinRank(discordId, roster, ours, responders)
  if type(discordId) ~= 'string' then return Pure.JOIN_RANK.other end
  if (roster and roster[discordId]) or (ours and ours[discordId]) then return Pure.JOIN_RANK.unit end
  if responders and responders[discordId] then return Pure.JOIN_RANK.responder end
  return Pure.JOIN_RANK.other
end

function Pure.unitRoster(units)
  local out = {}
  for _, u in ipairs(type(units) == 'table' and units or {}) do
    if type(u) == 'table' and type(u.discordId) == 'string' then out[u.discordId] = true end
  end
  return out
end

local function rankOf(item)
  local r = item.rank
  if type(r) == 'function' then
    local ok, v = pcall(r)
    r = ok and v or nil
  end
  return tonumber(r) or Pure.JOIN_RANK.other
end

function Pure.pacePick(items)
  local best, bestRank
  for i = 1, #items do
    local r = rankOf(items[i])
    if not bestRank or r < bestRank then best, bestRank = i, r end
  end
  return best
end

function Pure.rankOrder(list, rank)
  local keyed = {}
  for i, v in ipairs(list) do keyed[i] = { v = v, i = i, r = tonumber(rank(v)) or Pure.JOIN_RANK.other } end
  table.sort(keyed, function(a, b)
    if a.r ~= b.r then return a.r < b.r end
    return a.i < b.i
  end)
  local out = {}
  for i, k in ipairs(keyed) do out[i] = k.v end
  return out
end

Pure.RESPONDER_TOUCH_S = 86400
Pure.RESPONDER_MAX_AGE_S = 30 * 86400
Pure.RESPONDER_CAP = 2000

function Pure.noteResponder(map, discordId, isResponder, now)
  if type(discordId) ~= 'string' then return false end
  local seen = map[discordId]
  if not isResponder then
    if seen == nil then return false end
    map[discordId] = nil
    return true
  end
  if type(seen) == 'number' and now - seen < Pure.RESPONDER_TOUCH_S then return false end
  map[discordId] = now
  return true
end

function Pure.pruneResponders(map, now, maxAge, cap)
  local list = {}
  for d, at in pairs(type(map) == 'table' and map or {}) do
    if type(d) == 'string' and d:match('^%d+$') and type(at) == 'number' and now - at <= maxAge then list[#list + 1] = { d = d, at = at } end
  end
  table.sort(list, function(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.d < b.d
  end)
  local out = {}
  for i = 1, math.min(#list, cap) do out[list[i].d] = list[i].at end
  return out
end

function Pure.panicPushFor(push, ref, viewer, mode)
  if not Pure.isMasked(ref, viewer, mode) then return push end
  return { masked = true, department = Pure.maskLabel(ref, mode), location = push.location, postal = push.postal }
end

function Pure.unitForms(src, unit, mode)
  local ref = Pure.unitRef(unit)
  local status = unit.status and unit.status.code
  return {
    src = src,
    ref = ref,
    visible = { id = src, onDuty = true, status = status, callsign = unit.callsign, department = ref.department, isPanic = unit.isPanic },
    masked = { id = src, onDuty = true, status = status, masked = true, department = Pure.maskLabel(ref, mode) },
  }
end

function Pure.unitsFor(viewer, mode, units)
  local out = {}
  for _, u in ipairs(units) do
    local ref = Pure.unitRef(u.unit)
    local entry = { id = u.src, onDuty = true, status = u.unit.status and u.unit.status.code }
    if Pure.isMasked(ref, viewer, mode) then
      entry.masked, entry.department = true, Pure.maskLabel(ref, mode)
    else
      entry.callsign, entry.department, entry.isPanic = u.unit.callsign, ref.department, u.unit.isPanic
    end
    out[#out + 1] = entry
  end
  return out
end

function Pure.receivesUnits(p)
  if type(p) ~= 'table' then return false end
  if p.unit then return true end
  local a = p.agency
  if type(a) ~= 'table' then return false end
  if a.viewAll == true then return true end
  if type(a.departmentTypes) == 'table' and #a.departmentTypes > 0 then
    for _, t in ipairs(a.departmentTypes) do
      if t ~= 'CIVILIAN' then return true end
    end
    return false
  end
  return type(a.departmentIds) == 'table' and #a.departmentIds > 0
end

local function scopeList(list)
  local out = {}
  if type(list) == 'table' then
    for _, v in ipairs(list) do
      local text = type(v) .. ':' .. tostring(v)
      out[#out + 1] = #text .. '#' .. text
    end
  end
  table.sort(out)
  local unique = {}
  for i = 1, #out do
    if out[i] ~= out[i - 1] then unique[#unique + 1] = out[i] end
  end
  return table.concat(unique)
end

function Pure.unitScope(viewer, mode)
  if mode == 'off' then return 'off' end
  local m = tostring(mode)
  if type(viewer) ~= 'table' then return m .. '|none' end
  if viewer.viewAll == true then return m .. '|all' end
  if mode == 'department_type' then return m .. '|t|' .. scopeList(viewer.departmentTypes) end
  return m .. '|d|' .. scopeList(viewer.departmentIds)
end

local UNIT_FIELDS = { 'status', 'masked', 'department', 'callsign', 'isPanic', 'onDuty' }

local function sameEntry(a, b)
  for i = 1, #UNIT_FIELDS do
    local k = UNIT_FIELDS[i]
    if a[k] ~= b[k] then return false end
  end
  return true
end

function Pure.unitsDiff(prevById, view)
  local byId, set, remove = {}, {}, {}
  for i = 1, #view do
    local e = view[i]
    byId[e.id] = e
    local old = prevById and prevById[e.id]
    if not old or not sameEntry(old, e) then set[#set + 1] = e end
  end
  if prevById then
    for id in pairs(prevById) do
      if not byId[id] then remove[#remove + 1] = id end
    end
    table.sort(remove)
  end
  return { byId = byId, set = set, remove = remove, changed = prevById == nil or #set > 0 or #remove > 0 }
end

Pure.sameUnitEntry = sameEntry

local function sortedUnits(byId)
  local out = {}
  for _, e in pairs(byId) do out[#out + 1] = e end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
Pure.sortedUnits = sortedUnits

function Pure.applyUnits(state, msg)
  if type(state) ~= 'table' or type(msg) ~= 'table' or type(msg.v) ~= 'number' then return nil end
  if type(msg.full) == 'table' then
    local byId = {}
    for _, e in ipairs(msg.full) do
      if type(e) == 'table' and type(e.id) == 'number' then byId[e.id] = e end
    end
    state.byId, state.v = byId, msg.v
    return sortedUnits(byId)
  end
  if type(msg.base) ~= 'number' or state.v ~= msg.base or type(state.byId) ~= 'table' then return nil end
  for _, id in ipairs(type(msg.remove) == 'table' and msg.remove or {}) do state.byId[id] = nil end
  for _, e in ipairs(type(msg.set) == 'table' and msg.set or {}) do
    if type(e) == 'table' and type(e.id) == 'number' then state.byId[e.id] = e end
  end
  state.v = msg.v
  return sortedUnits(state.byId)
end

function Pure.revalidateNext(entries, now, periodMs, floorMs)
  local n = #entries
  if n == 0 then return nil, periodMs end
  local gap = math.max(floorMs, math.floor(periodMs / n))
  local oldest
  for i = 1, n do
    local e = entries[i]
    if not oldest or (e.checkedAt or 0) < (oldest.checkedAt or 0) or ((e.checkedAt or 0) == (oldest.checkedAt or 0) and e.src < oldest.src) then oldest = e end
  end
  local due = (oldest.checkedAt or 0) + periodMs - now
  if due > 0 then return nil, math.max(floorMs, math.min(gap, due)) end
  return oldest.src, gap
end

Pure.REFRESH_EVENTS = { ['unit.status'] = true, ['unit.signed_on'] = true, ['unit.signed_off'] = true, ['character.active_changed'] = true }

function Pure.refreshTargets(kind, payload, players)
  local out = {}
  if not Pure.REFRESH_EVENTS[kind] or type(payload) ~= 'table' then return out end
  for _, p in ipairs(players) do
    if Pure.namesPlayer(payload.membershipId, payload.discordId, p) then out[#out + 1] = p.src end
  end
  return out
end

function Pure.characterChanged(cached, payload)
  return (cached and cached.id) ~= (payload and payload.characterId)
end

function Pure.urlencode(s)
  return (tostring(s):gsub('[^%w%-_%.~]', function(ch) return ('%%%02X'):format(ch:byte()) end))
end

function Pure.buildPath(template, params, query)
  local path = template:gsub('{(%w+)}', function(k)
    local v = params and params[k]
    if v == nil then error(('missing path param %s for %s'):format(k, template)) end
    return Pure.urlencode(v)
  end)
  if query then
    local keys = {}
    for k in pairs(query) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = Pure.urlencode(k) .. '=' .. Pure.urlencode(query[k]) end
    if #parts > 0 then path = path .. '?' .. table.concat(parts, '&') end
  end
  return path
end

local INVISIBLE = {
  { 0x0, 0x1f }, { 0x7f, 0x9f }, { 0xad, 0xad }, { 0x34f, 0x34f }, { 0x600, 0x605 }, { 0x61c, 0x61c }, { 0x6dd, 0x6dd },
  { 0x70f, 0x70f }, { 0x8e2, 0x8e2 }, { 0x115f, 0x1160 }, { 0x17b4, 0x17b5 }, { 0x180b, 0x180f }, { 0x200b, 0x200f },
  { 0x2028, 0x202e }, { 0x2060, 0x206f }, { 0x3164, 0x3164 }, { 0xfe00, 0xfe0f }, { 0xfeff, 0xfeff }, { 0xffa0, 0xffa0 },
  { 0xfff9, 0xfffb }, { 0x110bd, 0x110bd }, { 0x110cd, 0x110cd }, { 0x13430, 0x1343f }, { 0x1bca0, 0x1bca3 },
  { 0x1d173, 0x1d17a }, { 0xe0000, 0xe007f }, { 0xe0100, 0xe01ef },
}

local function invisible(cp)
  for i = 1, #INVISIBLE do
    local r = INVISIBLE[i]
    if cp >= r[1] and cp <= r[2] then return true end
  end
  return false
end

local function codepoints(s)
  if not utf8.len(s) then s = s:gsub('[\128-\255]', '') end
  local out = {}
  for _, cp in utf8.codes(s) do out[#out + 1] = cp end
  return out
end

local function cut(cps, max)
  local out, units = {}, 0
  for i = 1, #cps do
    local w = cps[i] > 0xffff and 2 or 1
    if units + w > max then break end
    units = units + w
    out[#out + 1] = utf8.char(cps[i])
  end
  return table.concat(out), units
end

local function unitCount(cps)
  local n = 0
  for i = 1, #cps do n = n + (cps[i] > 0xffff and 2 or 1) end
  return n
end

function Pure.clean(s, max)
  if type(s) ~= 'string' then return nil end
  local kept = {}
  for _, cp in ipairs(codepoints(s)) do
    if not invisible(cp) then kept[#kept + 1] = cp end
  end
  local text = utf8.char(table.unpack(kept)):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return nil end
  return (cut(codepoints(text), max))
end

function Pure.truncate(s, max)
  s = tostring(s or '')
  local cps = codepoints(s)
  if unitCount(cps) <= max then return utf8.char(table.unpack(cps)) end
  return cut(cps, max - 3) .. '...'
end

function Pure.locationText(labels)
  if not labels or not labels.street or labels.street == '' then return nil end
  local text = labels.street
  if labels.crossStreet and labels.crossStreet ~= '' then text = text .. ' / ' .. labels.crossStreet end
  return Pure.clean(text, Pure.LOCATION_MAX)
end

local function cleanText(v, max)
  if v == nil then return nil end
  if type(v) ~= 'string' then return false end
  return Pure.clean(v, max)
end

Pure.ZONE_MAX = 32

function Pure.cleanLabels(street, crossStreet, postal, max, zone)
  local s, c, p, z = cleanText(street, max), cleanText(crossStreet, max), cleanText(postal, 10), cleanText(zone, Pure.ZONE_MAX + 1)
  if s == false or c == false or p == false or z == false then return nil end
  if p and not p:match('^[%w%-]+$') then p = nil end
  if z and (#z > Pure.ZONE_MAX or not z:match('^[%w_]+$')) then z = nil end
  return { street = s, crossStreet = c, postal = p, zone = z }
end

local function placeOf(location)
  location = Pure.clean(location, Pure.LOCATION_MAX)
  if not location or #location < 3 then return 'Unknown location' end
  return location
end

local function round1(v)
  return math.floor(v * 10 + 0.5) / 10
end

function Pure.position(coords)
  if type(coords) ~= 'table' or type(coords.x) ~= 'number' or type(coords.y) ~= 'number' then return nil end
  if coords.x ~= coords.x or coords.y ~= coords.y or math.abs(coords.x) > Pure.COORD_LIMIT or math.abs(coords.y) > Pure.COORD_LIMIT then return nil end
  local heading = type(coords.heading) == 'number' and coords.heading == coords.heading and math.floor(coords.heading + 0.5) % 360 or nil
  return { x = round1(coords.x), y = round1(coords.y), heading = heading }
end

function Pure.moved(last, now, metres, degrees)
  if not now then return false end
  if not last then return true end
  local dx, dy = now.x - last.x, now.y - last.y
  if dx * dx + dy * dy >= metres * metres then return true end
  if not last.heading or not now.heading then return last.heading ~= now.heading end
  local d = math.abs(now.heading - last.heading) % 360
  if d > 180 then d = 360 - d end
  return d >= degrees
end

local MOVEMENT_BY_TYPE = { bike = 'bike', boat = 'boat', submarine = 'boat', heli = 'aircraft', plane = 'aircraft' }

function Pure.movementFromType(vehicleType)
  if vehicleType == nil or vehicleType == '' then return 'foot' end
  return MOVEMENT_BY_TYPE[vehicleType] or 'car'
end

function Pure.speed(v)
  if type(v) ~= 'table' or type(v.x) ~= 'number' or type(v.y) ~= 'number' or type(v.z) ~= 'number' then return nil end
  local s = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if s ~= s or s == math.huge then return nil end
  return math.min(round1(s), 1000)
end

function Pure.shouldSend(last, now, t, positions)
  if not now then return false end
  if not last then return true end
  if t - last.at >= (positions.keepalive or 10) then return true end
  if last.movement ~= now.movement then return true end
  return Pure.moved(last, now, positions.metres, positions.degrees)
end

function Pure.keepaliveDue(last, t, positions)
  return not last or t - last >= (positions.keepalive or 10)
end

function Pure.call911Body(o)
  local pos = Pure.position(o.coords)
  return {
    discordId = o.discordId,
    description = Pure.clean(o.text, 1000),
    location = placeOf(o.location),
    postal = o.postal,
    anonymous = o.anonymous == true,
    origin = o.origin == 'non_emergency' and 'non_emergency' or '911',
    clientRef = o.clientRef,
    x = pos and pos.x,
    y = pos and pos.y,
    zoneCode = o.zoneCode,
  }
end

Pure.SCRIPT_TEXT_MAX = 1000
Pure.SCRIPT_LABEL_MAX = 64

local function scriptLabel(v)
  if v == nil then return nil end
  if type(v) ~= 'string' then return false end
  local out = Pure.clean(v, Pure.SCRIPT_LABEL_MAX + 1)
  if out and unitCount(codepoints(out)) > Pure.SCRIPT_LABEL_MAX then return false end
  return out
end

local function scriptPostal(v)
  if v == nil then return nil end
  if math.type(v) == 'integer' and v >= 0 then v = tostring(v) end
  if type(v) ~= 'string' then return false end
  v = v:gsub('^%s+', ''):gsub('%s+$', '')
  if v == '' then return nil end
  if #v > 10 or not v:match('^%d+$') then return false end
  return v
end

local function scriptCoords(c)
  if c == nil then return nil end
  local t = type(c)
  if t ~= 'table' and t ~= 'vector3' then return false end
  local out = { x = c.x, y = c.y, z = c.z }
  if not Pure.validCoords(out) then return false end
  return out
end

function Pure.buildScript911(data, resource)
  if type(data) ~= 'table' or type(resource) ~= 'string' or not resource:match('^[%w_%.%-]+$') or #resource > 64 then return nil, 'validation' end
  if type(data.text) ~= 'string' then return nil, 'validation' end
  local text = Pure.clean(data.text, Pure.SCRIPT_TEXT_MAX + 1)
  if not text or unitCount(codepoints(text)) > Pure.SCRIPT_TEXT_MAX then return nil, 'validation' end
  local street, cross, postal, coords = scriptLabel(data.street), scriptLabel(data.crossStreet), scriptPostal(data.postal), scriptCoords(data.coords)
  if street == false or cross == false or postal == false or coords == false then return nil, 'validation' end
  if data.anonymous ~= nil and type(data.anonymous) ~= 'boolean' then return nil, 'validation' end
  return {
    description = text,
    location = Pure.locationText({ street = street, crossStreet = cross }) or 'Unknown',
    postal = postal,
    anonymous = data.anonymous == true,
    origin = 'script',
    sourceResource = resource,
  }, coords
end

function Pure.refusalThrottle(store, resource, reason, now, seconds)
  return (Pure.useCooldown(store, tostring(resource) .. '|' .. tostring(reason), now, seconds or 60))
end

function Pure.postalCode(value)
  if type(value) == 'table' then value = value.code end
  if type(value) == 'number' and value == value and value >= 0 and value < 1e10 then value = tostring(math.floor(value)) end
  if type(value) ~= 'string' then return nil end
  value = value:match('^%s*(.-)%s*$')
  if #value == 0 or #value > 10 or not value:match('^[%w%-]+$') then return nil end
  return value
end

function Pure.preferPostal(serverPostal, labels)
  return Pure.postalCode(serverPostal) or (labels and labels.postal) or nil
end

function Pure.panicBody(active, labels, serverPostal, coords)
  if not active then return { active = false } end
  local pos = Pure.position(coords)
  return { active = true, location = Pure.locationText(labels), postal = Pure.preferPostal(serverPostal, labels), x = pos and pos.x, y = pos and pos.y, zoneCode = labels and labels.zone }
end

Pure.MAX_SLOTS = 2048

function Pure.isServerId(v)
  return type(v) == 'string' and #v == 32 and v:match('^[0-9a-f]+$') ~= nil
end

function Pure.newServerId(rand)
  local out = {}
  for i = 1, 32 do out[i] = ('%x'):format(rand(0, 15)) end
  return table.concat(out)
end

function Pure.heartbeatPayload(players, maxPlayers, online)
  local max = math.max(1, math.min(Pure.MAX_SLOTS, math.floor(tonumber(maxPlayers) or 1)))
  local body = { players = math.max(0, math.min(max, math.floor(tonumber(players) or 0))), maxPlayers = max }
  if online == false then body.online = false end
  return body
end

function Pure.dutyArgs(args)
  local department = args and args[1]
  if not department or department == '' then return nil end
  local callsign = table.concat(args, ' ', 2):gsub('^%s+', ''):gsub('%s+$', '')
  if callsign == '' then return department, nil end
  return department, callsign
end

Pure.TS_PLATE_MAX = 8
Pure.TS_OCCUPANTS_MAX = 60

function Pure.trafficStopArgs(args)
  args = args or {}
  local plate = Pure.clean(args[1], Pure.TS_PLATE_MAX * 2)
  local occupants = Pure.clean(table.concat(args, ' ', 2), Pure.TS_OCCUPANTS_MAX * 2)
  if plate and unitCount(codepoints(plate)) > Pure.TS_PLATE_MAX then return nil end
  if occupants and unitCount(codepoints(occupants)) > Pure.TS_OCCUPANTS_MAX then return nil end
  return { plate = plate, occupants = occupants }
end

function Pure.trafficStopBody(discordId, plate, labels, coords, occupants)
  local pos = Pure.position(coords)
  return { discordId = discordId, plate = plate, occupants = occupants, location = placeOf(Pure.locationText(labels)), postal = labels and labels.postal, x = pos and pos.x, y = pos and pos.y, zoneCode = labels and labels.zone }
end

function Pure.outcomeUnknown(res)
  local problem = type(res) == 'table' and res.problem or nil
  return problem ~= nil and (problem.timedOut == true or problem.network == true)
end

Pure.ADOPT_SKEW_S = 5

function Pure.isoSeconds(text)
  if type(text) ~= 'string' then return nil end
  local y, mo, d, h, mi, s, rest = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$')
  if not y then return nil end
  rest = rest:gsub('^%.%d+', '')
  local offset
  if rest == 'Z' then
    offset = 0
  else
    local sign, oh, om = rest:match('^([%+%-])(%d%d):?(%d%d)$')
    if not sign then return nil end
    offset = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == '-' and -1 or 1)
  end
  y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or s > 60 then return nil end
  local yy = mo <= 2 and y - 1 or y
  local era = yy // 400
  local yoe = yy - era * 400
  local doy = (153 * ((mo + 9) % 12) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return (era * 146097 + doe - 719468) * 86400 + h * 3600 + mi * 60 + s - offset
end

function Pure.adoptCall(before, current, call, want, window, me)
  if type(current) ~= 'string' or current == '' or current == before then return nil end
  if type(want) ~= 'string' or type(call) ~= 'table' or call.origin ~= want then return nil end
  if type(window) ~= 'table' or type(window.from) ~= 'number' or type(window.to) ~= 'number' then return nil end
  local created = Pure.isoSeconds(call.createdAt)
  if not created or created < window.from - Pure.ADOPT_SKEW_S or created > window.to + Pure.ADOPT_SKEW_S then return nil end
  if type(call.units) == 'table' then
    local first = call.units[1]
    if type(first) ~= 'table' or type(me) ~= 'table' then return nil end
    local byId = me.discordId ~= nil and first.discordId == me.discordId
    local bySign = me.callsign ~= nil and first.callsign == me.callsign
    if not (byId or bySign) then return nil end
  end
  return current
end

function Pure.trackingArg(arg, hidden)
  if arg == nil or arg == '' then return not hidden end
  arg = arg:lower()
  if arg == 'off' or arg == 'hide' then return true end
  if arg == 'on' or arg == 'show' then return false end
  return nil
end

function Pure.retryable(status)
  return status == 0 or status == 429 or status >= 500
end

function Pure.lateWatched(method, template, player)
  return player == true and method ~= 'GET' and template ~= '/calls/911'
end

function Pure.lateNotice(template, data)
  data = type(data) == 'table' and data or {}
  if template == '/calls/traffic-stop' and data.number then return 'ts_started', data.number end
  if template == '/calls/{number}/units' and type(data.call) == 'table' and data.call.number then return 'attach_done', data.call.number end
  return 'late_done'
end

Pure.TEN_CODE_MEANINGS = {
  ['10-8'] = 'available',
  ['10-6'] = 'busy',
  ['10-7'] = 'unavailable',
  ['10-23'] = 'on_scene',
  ['10-97'] = 'en_route',
  ['10-76'] = 'en_route',
  ['10-41'] = 'on_duty',
  ['10-42'] = 'off_duty',
}

local CONFIRMABLE = { ['/calls/traffic-stop'] = true, ['/calls/{number}/units'] = true, ['/units/{discordId}/status'] = true }

function Pure.confirmable(template)
  return CONFIRMABLE[template] == true
end

function Pure.confirmLanded(template, window, unit, call, me)
  if type(window) ~= 'table' or type(unit) ~= 'table' then return nil end
  if template == '/calls/traffic-stop' then
    local number = unit.callNumber
    if type(number) ~= 'string' or type(call) ~= 'table' or call.number ~= number then return nil end
    if type(me) ~= 'table' or type(call.units) ~= 'table' then return nil end
    if not Pure.adoptCall(nil, number, call, 'traffic_stop', window, me) then return nil end
    return 'ts_started', number
  end
  if template == '/calls/{number}/units' then
    local want = type(window.params) == 'table' and window.params.number or nil
    if type(want) ~= 'string' or unit.callNumber ~= want then return nil end
    return 'attach_done', want
  end
  if template == '/units/{discordId}/status' then
    local body, status = window.body, unit.status
    if type(body) ~= 'table' or type(body.code) ~= 'string' or type(status) ~= 'table' then return nil end
    local typed = body.code:match('^%s*(.-)%s*$'):upper()
    if type(status.code) == 'string' and typed == status.code:upper() then return 'late_done' end
    local meaning = Pure.TEN_CODE_MEANINGS[typed]
    if meaning and meaning == status.meaning then return 'late_done' end
  end
  return nil
end

function Pure.dropSettled(res)
  if type(res) ~= 'table' then return false end
  local status = tonumber(res.status) or 0
  if status >= 200 and status < 300 then return true end
  if res.problem and res.problem.code == 'not_configured' then return true end
  return not Pure.retryable(status)
end

Pure.HTTP_DEADLINE_S = 15
Pure.HTTP_NO_RESPONSE_S = 5

local STALL_CODES = { [28] = true, [42] = true }

function Pure.httpAborted(errorData)
  if type(errorData) ~= 'string' or errorData:match('^HTTP %d') then return false end
  local code = tonumber(errorData:match('CURL error code (%d+)'))
  return code ~= nil and STALL_CODES[code] == true
end
Pure.HTTP_CONCURRENCY = 8

function Pure.httpConcurrency(v)
  local n = math.floor(tonumber(v) or Pure.HTTP_CONCURRENCY)
  return math.max(1, math.min(32, n))
end

Pure.HTTP_SLOT_CEILING_S = 300
Pure.HTTP_CLASS = { high = 1, normal = 2, low = 3 }

local HIGH_ROUTES = {
  ['GET /events'] = true,
  ['POST /units/{discordId}/panic'] = true,
  ['POST /units/duty'] = true,
  ['DELETE /units/duty/{discordId}'] = true,
  ['PATCH /units/{discordId}/status'] = true,
  ['POST /calls/911'] = true,
}

function Pure.httpClass(method, template, priority)
  if Pure.HTTP_CLASS[priority] then return Pure.HTTP_CLASS[priority] end
  if HIGH_ROUTES[tostring(method) .. ' ' .. tostring(template)] then return Pure.HTTP_CLASS.high end
  return Pure.HTTP_CLASS.normal
end

function Pure.httpGate(max)
  local reserve = max >= 4 and 2 or (max >= 2 and 1 or 0)
  return { max = max, reserve = reserve, active = 0, peak = 0, queues = { { head = 1, tail = 0 }, { head = 1, tail = 0 }, { head = 1, tail = 0 } } }
end

local function gateCap(g, class)
  if class == Pure.HTTP_CLASS.low then return g.max - g.reserve end
  return g.max
end

local function gateTake(g, ticket)
  g.active = g.active + 1
  if g.active > g.peak then g.peak = g.active end
  ticket.go = true
end

local function gateQueued(g, upTo)
  for c = 1, upTo do
    local q = g.queues[c]
    if q.head <= q.tail then return true end
  end
  return false
end

function Pure.httpGateJoin(g, class)
  class = g.queues[class] and class or Pure.HTTP_CLASS.normal
  local ticket = { class = class, go = false }
  if g.active < gateCap(g, class) and not gateQueued(g, class) then
    gateTake(g, ticket)
    return ticket
  end
  local q = g.queues[class]
  q.tail = q.tail + 1
  q[q.tail] = ticket
  return ticket
end

function Pure.httpGateRelease(g, ticket)
  if type(ticket) ~= 'table' or not ticket.go or ticket.released then return {} end
  ticket.released = true
  g.active = math.max(0, g.active - 1)
  local woken = {}
  for c = 1, #g.queues do
    local q = g.queues[c]
    while q.head <= q.tail and g.active < gateCap(g, c) do
      local next = q[q.head]
      q[q.head] = nil
      q.head = q.head + 1
      gateTake(g, next)
      woken[#woken + 1] = next
    end
    if q.head <= q.tail then break end
  end
  return woken
end

Pure.RETRY_WAIT_MAX = 5

function Pure.retryWait(method, problem, attempt, retry, rand, player)
  if attempt ~= 1 or retry == false or type(problem) ~= 'table' then return nil end
  local status = problem.status or 0
  if status == 429 then
    if player then return nil end
    local wait = math.max(1, problem.retryAfter or 1)
    if wait > Pure.RETRY_WAIT_MAX then return nil end
    return wait
  end
  if method == 'GET' and not problem.timedOut and ((status == 0 and problem.network) or status >= 500) then
    return 0.5 + math.max(0, math.min(1, rand or 0.5))
  end
  return nil
end

function Pure.clientRef(discordId, t, r)
  return ('%s-%x-%x'):format(discordId or 'anon', math.floor(t), math.floor(r) % 0x1000000)
end

function Pure.queuePush(queue, item, max)
  if #queue >= max then return false end
  queue[#queue + 1] = item
  return true
end

function Pure.queueExpired(queue, now, maxAge)
  local out = {}
  for i = 1, #queue do
    if now - queue[i].at > maxAge then out[#out + 1] = i end
  end
  return out
end

function Pure.queueStep(queue, send, now, maxAge)
  local step = { dropped = {} }
  local expired = Pure.queueExpired(queue, now, maxAge)
  for i = #expired, 1, -1 do
    step.dropped[#step.dropped + 1] = table.remove(queue, expired[i])
  end
  local item = queue[1]
  if not item then return step end
  step.item = item
  local ok, res = pcall(send, item.body, item.account)
  if not ok then
    table.remove(queue, 1)
    step.outcome, step.error = 'error', res
    return step
  end
  if type(res) ~= 'table' then res = { status = 0 } end
  step.result = res
  if res.status == 201 then
    table.remove(queue, 1)
    step.outcome = 'sent'
  elseif not Pure.retryable(res.status) then
    table.remove(queue, 1)
    step.outcome = 'rejected'
  else
    step.outcome = 'retry'
  end
  return step
end

function Pure.queueActive(queue, draining)
  if draining then return false end
  return #queue > 0
end

function Pure.queueNotify(outcome)
  return outcome == 'rejected'
end

function Pure.newGate()
  return { busy = {}, last = {} }
end

function Pure.gateEnter(gate, src, now, seconds)
  if gate.busy[src] then return false, 'busy' end
  local ok, left = Pure.cooldown(gate.last[src], now, seconds)
  if not ok then return false, 'cooldown', left end
  gate.busy[src], gate.last[src] = true, now
  return true
end

function Pure.gateLeave(gate, src)
  gate.busy[src] = nil
end

function Pure.gateForget(gate, src)
  gate.busy[src], gate.last[src] = nil, nil
end

function Pure.insecureUrl(url)
  if url:match('^https://') then return false end
  local host = url:match('^http://([^/:]+)')
  return not (host == 'localhost' or host == '127.0.0.1')
end

Pure.LICENSE_ALIASES = { driver = { 'DL', 'DRV', 'DRIVER' } }

local function licenseCode(l)
  return type(l) == 'table' and type(l.type) == 'string' and l.type:upper() or nil
end

function Pure.pickLicense(licenses, wanted)
  if type(wanted) ~= 'string' or wanted == '' then wanted = 'driver' end
  local key = wanted:lower()
  local codes = {}
  for _, c in ipairs(Pure.LICENSE_ALIASES[key] or { wanted }) do codes[c:upper()] = true end
  local found
  for _, l in ipairs(licenses or {}) do
    local code = licenseCode(l)
    local named = key == 'driver' and type(l.name) == 'string' and l.name:lower():match('^driver') ~= nil
    if code and (codes[code] or named) then
      if l.status == 'valid' then return l end
      found = found or l
    end
  end
  return found
end

local function text(v, max)
  if type(v) ~= 'string' then return nil end
  return Pure.clean(v, max)
end

local LOOPBACK = { localhost = true, ['127.0.0.1'] = true }

function Pure.photoUrl(url, hosts, devHttp)
  if type(url) ~= 'string' or #url > 2048 or url:find('[%s"\'<>\\]') or url:match('^%a+://[^/]*@') then return nil end
  local scheme, host = url:match('^(https?)://([^/:%?#]+)')
  if not host then return nil end
  host = host:lower()
  if scheme ~= 'https' and not (devHttp == true and LOOPBACK[host]) then return nil end
  for _, h in ipairs(hosts or {}) do
    h = type(h) == 'string' and h:lower() or ''
    if h ~= '' and (host == h or (h:sub(1, 1) == '.' and #host > #h and host:sub(-#h) == h)) then return url end
  end
  return nil
end

function Pure.idCardPayload(card, license, hosts, devHttp)
  local endorsements = {}
  for i, e in ipairs(type(license.endorsements) == 'table' and license.endorsements or {}) do
    if i > 10 then break end
    endorsements[#endorsements + 1] = text(e, 20)
  end
  return {
    name = Pure.truncate(card.name, 80),
    firstName = text(card.firstName, 40),
    middleName = text(card.middleName, 40),
    lastName = text(card.lastName, 40),
    dob = text(card.dob, 10),
    sex = text(card.sex, 20),
    address = text(card.address, 120),
    state = text(card.state, 40),
    hair = text(card.hair, 20),
    eyes = text(card.eyes, 20),
    height = text(card.height, 20),
    weight = text(card.weight, 20),
    photo = Pure.photoUrl(card.mugshotUrl, hosts, devHttp),
    card = Pure.cardModel(license.card, hosts, devHttp),
    license = {
      type = text(license.type, 8),
      name = Pure.truncate(license.name, 40),
      number = text(license.number, 30),
      class = text(license.class, 20),
      endorsements = endorsements,
      status = text(license.status, 20),
      issued = text(license.issuedOn, 10),
      expires = text(license.expiresOn, 10),
    },
  }
end

Pure.CARD_KINDS = { id = true, driver = true, cdl = true, permit = true, generic = true }

function Pure.cardModel(card, hosts, devHttp)
  if type(card) ~= 'table' or type(card.number) ~= 'string' or type(card.kind) ~= 'string' then return nil end
  local out = {}
  for k, v in pairs(card) do out[k] = v end
  out.kind = Pure.CARD_KINDS[card.kind] and card.kind or 'generic'
  out.photoUrl = Pure.photoUrl(card.photoUrl, hosts, devHttp)
  return out
end

function Pure.cardTheme(theme, hosts, devHttp)
  if type(theme) ~= 'table' then return nil end
  local colors = type(theme.colors) == 'table' and theme.colors or {}
  return {
    stateName = text(theme.stateName, 40),
    sealUrl = Pure.photoUrl(theme.sealUrl, hosts, devHttp),
    colors = { band = text(colors.band, 7), accent = text(colors.accent, 7), ink = text(colors.ink, 7) },
    verticalUnder21 = theme.verticalUnder21 == true,
    communityName = text(theme.communityName, 80),
    siteHost = text(theme.siteHost, 120),
  }
end

Pure.EVENT_ROUTES = {
  ['call.911'] = { event = 'statewide:911', push = '911' },
  ['call.created'] = { event = 'statewide:311', push = '311' },
  ['unit.panic'] = { event = 'statewide:panic', push = 'panic' },
  ['call.unit_attached'] = { event = 'statewide:attached', push = 'attached' },
  ['call.closed'] = { event = 'statewide:callClosed', push = 'callClosed' },
  ['unit.forced_off'] = { event = 'statewide:forcedOff', push = 'forcedOff' },
  ['unit.status'] = { refresh = true },
  ['unit.signed_on'] = { refresh = true },
  ['unit.signed_off'] = { refresh = true },
  ['community.settings'] = { settings = true },
  ['ers.offer'] = { event = 'statewide:ersOffer' },
  ['call.unit_detached'] = { event = 'statewide:detached', queue = true },
  ['call.event'] = { event = 'statewide:callNote', queue = true },
  ['citation.signature_requested'] = { event = 'statewide:citationRequested', citation = true },
  ['scene_marker.set'] = { markers = true },
  ['scene_marker.cleared'] = { markers = true },
  ['character.active_changed'] = { refresh = true },
}

Pure.PUSH_WINDOW_MS = 1500
Pure.PUSH_NOTES_MAX = 3
Pure.NOTE_MAX = 500

function Pure.maskBy(name, p, viewer, mode)
  if type(p) ~= 'table' or not p.byDepartmentId then return name end
  local ref = { departmentId = p.byDepartmentId, departmentType = p.byDepartmentType, department = p.byDepartment }
  if not Pure.isMasked(ref, viewer, mode) then return name end
  return Pure.maskLabel(ref, mode) or 'UNIT'
end

function Pure.queueItem(kind, p, viewer, mode)
  if type(p) ~= 'table' or type(p.number) ~= 'string' then return nil end
  if kind == 'call.unit_detached' then
    return { type = 'detached', number = p.number, by = Pure.truncate(Pure.maskBy(p.by, p, viewer, mode), 40) }
  elseif kind == 'call.event' and p.kind == 'note' and type(p.body) == 'string' then
    return { type = 'note', number = p.number, author = Pure.truncate(Pure.maskBy(p.author, p, viewer, mode), 40), body = Pure.truncate(p.body, 200) }
  end
  return nil
end

function Pure.dutyItem(kind, payload, unit)
  if type(payload) ~= 'table' then return nil end
  local held = unit and unit.callsign == payload.callsign
  if kind == 'unit.signed_on' then
    if held then return nil end
    return { type = 'duty', on = true, callsign = payload.callsign, department = payload.department }
  elseif kind == 'unit.signed_off' and held then
    return { type = 'duty', on = false }
  end
  return nil
end

function Pure.coalescePushes(items, maxNotes)
  local out, lastDuty, notes = {}, nil, {}
  for i, it in ipairs(items or {}) do
    if it.type == 'duty' then lastDuty = i elseif it.type == 'note' then notes[#notes + 1] = i end
  end
  local hidden, more = {}, {}
  for n = 1, #notes - maxNotes do
    local it = items[notes[n]]
    hidden[notes[n]] = true
    more[it.number] = (more[it.number] or 0) + 1
  end
  local detached = {}
  for i, it in ipairs(items or {}) do
    if it.type == 'duty' and i == lastDuty then
      out[#out + 1] = it.on and { key = 'duty_on', args = { it.callsign or '', it.department or '' } } or { key = 'duty_off', args = {} }
    elseif it.type == 'note' and hidden[i] then
      if more[it.number] then
        out[#out + 1] = { key = 'push_notes_more', args = { it.number, more[it.number] } }
        more[it.number] = nil
      end
    elseif it.type == 'note' then
      out[#out + 1] = { key = 'push_note', args = { Pure.noteDetail(it) } }
    elseif it.type == 'detached' and not detached[it.number] then
      detached[it.number] = true
      local by = Pure.joinParts('', it.by)
      if by == '' then out[#out + 1] = { key = 'push_detached', args = { it.number } }
      else out[#out + 1] = { key = 'push_detached_by', args = { it.number, by } } end
    end
  end
  return out
end

function Pure.takeCaller(waiting, number, attached, accountOf)
  local w = number and waiting[number]
  if not w then return nil end
  waiting[number] = nil
  if type(attached) ~= 'table' or Pure.namesPlayer(attached.membershipId, attached.discordId, w) then return nil end
  if not Pure.sameAccount(accountOf(w.src), w.account) then return nil end
  return w.src
end

function Pure.noteText(args)
  local body = Pure.clean(table.concat(args or {}, ' '), Pure.NOTE_MAX * 2)
  if not body then return nil, 'empty' end
  if unitCount(codepoints(body)) > Pure.NOTE_MAX then return nil, 'too_long' end
  return body
end

function Pure.pushPayload(kind, p, viewer, mode)
  if kind == 'unit.panic' then
    return { callsign = p.callsign, department = p.department, callNumber = p.callNumber, location = Pure.truncate(p.location, 60), postal = p.postal }
  elseif kind == 'unit.forced_off' then
    return { by = Pure.truncate(Pure.maskBy(p.by, p, viewer, mode), 40), reason = Pure.truncate(p.reason, 60) }
  end
  return {
    number = p.number,
    nature = Pure.truncate(p.nature, 40),
    postal = p.postal,
    location = Pure.truncate(p.location, 60),
    disposition = p.disposition and Pure.truncate(p.disposition, 40) or nil,
  }
end

function Pure.joinParts(sep, ...)
  local out = {}
  for i = 1, select('#', ...) do
    local v = select(i, ...)
    v = type(v) == 'string' and v:match('^%s*(.-)%s*$') or ''
    if v ~= '' then out[#out + 1] = v end
  end
  return table.concat(out, sep)
end

local function parens(v)
  local s = Pure.joinParts('', v)
  if s == '' then return nil end
  return '(' .. s .. ')'
end

function Pure.push911Detail(p)
  return Pure.joinParts(': ', p.number, Pure.joinParts(' ', p.location, parens(p.postal)))
end

function Pure.attachedDetail(p)
  return Pure.joinParts(': ', p.number, Pure.joinParts(' ', p.nature, p.location))
end

function Pure.panicDetail(p)
  return Pure.joinParts(' ', p.callsign, parens(p.department), p.location)
end

function Pure.maskedPanicDetail(p, unitWord)
  return Pure.joinParts(' ', p.department, unitWord, p.location)
end

function Pure.closedLine(p)
  local number, disposition = Pure.joinParts('', p.number), Pure.joinParts('', p.disposition)
  if disposition == '' then return 'push_closed', { number } end
  return 'push_closed_disposition', { number, disposition }
end

function Pure.noteDetail(it)
  return Pure.joinParts(': ', Pure.joinParts(', ', it.number, it.author), it.body)
end

function Pure.staleGameUnits(units, connected, ours)
  local out = {}
  for _, u in ipairs(units or {}) do
    local d = u.discordId
    if u.dutySource == 'game' and d and ours[d] and not connected[d] and not Pure.dropped(u) then out[#out + 1] = d end
  end
  return out
end

function Pure.dropped(unit)
  return type(unit) == 'table' and type(unit.disconnectedAt) == 'string'
end

function Pure.nearestPlayer(coords, others, maxDist, bucket)
  if not coords then return nil end
  local best, bestDist
  for _, o in ipairs(others or {}) do
    local c = o.coords
    if c and o.bucket == bucket then
      local dx, dy, dz = c.x - coords.x, c.y - coords.y, (c.z or 0) - (coords.z or 0)
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d <= maxDist and (not bestDist or d < bestDist) then best, bestDist = o.src, d end
    end
  end
  return best
end

function Pure.isCallNumber(s)
  return type(s) == 'string' and s:match('^%d%d%-%d%d%d%d%d%d$') ~= nil
end

function Pure.validCoords(c)
  if type(c) ~= 'table' then return false end
  for _, k in ipairs({ 'x', 'y' }) do
    local v = c[k]
    if type(v) ~= 'number' or v ~= v or v < -10000 or v > 10000 then return false end
  end
  return c.z == nil or (type(c.z) == 'number' and c.z == c.z and c.z > -1000 and c.z < 3000)
end

Pure.CHAT_MAX = 1000

Pure.FEED_MAX = 99

function Pure.validUtf8(line)
  local out, at = {}, 1
  while at <= #line do
    local _, bad = utf8.len(line, at)
    if not bad then
      out[#out + 1] = line:sub(at)
      break
    end
    out[#out + 1] = line:sub(at, bad - 1)
    out[#out + 1] = '?'
    at = bad + 1
  end
  return table.concat(out)
end

function Pure.feedText(line)
  return Pure.chatText(line, Pure.FEED_MAX)
end

function Pure.chatText(line, max)
  max = max or Pure.CHAT_MAX
  line = Pure.validUtf8(line)
  if #line <= max then return line end
  local head = line:sub(1, max - 3)
  local at = head:match('^.*()[,%s]')
  if at and at > max / 2 then head = head:sub(1, at - 1) end
  while #head > 0 and not utf8.len(head) do head = head:sub(1, -2) end
  return (head:gsub('[,%s]+$', '')) .. '...'
end

function Pure.callCoords(p)
  if type(p) ~= 'table' or not Pure.validCoords({ x = p.x, y = p.y }) then return nil end
  return { x = p.x, y = p.y }
end

function Pure.waypointPush(p)
  if type(p) ~= 'table' or not Pure.isCallNumber(p.number) then return nil end
  if not Pure.validCoords({ x = p.x, y = p.y }) then return nil end
  local postal = Pure.clean(p.postal, 8)
  return { x = p.x, y = p.y, label = postal and ('%s (%s)'):format(p.number, postal) or p.number }
end

Pure.ARRIVAL_HITS = 2
Pure.ARRIVAL_MAX_RADIUS = 1000
Pure.ARRIVAL_MAX_AGE = 3600
Pure.ARRIVAL_RETRY = 10
Pure.ARRIVAL_ATTEMPTS = 3

function Pure.arrivalTarget(p, t)
  local push = Pure.waypointPush(p)
  if not push then return nil end
  local radius = p.onSceneWithin
  if type(radius) ~= 'number' or radius ~= radius or radius < 1 or radius > Pure.ARRIVAL_MAX_RADIUS then return nil end
  return { callNumber = p.number, x = push.x, y = push.y, radius = radius, since = t, hits = 0, attempts = 0 }
end

function Pure.arrivalStep(target, unit, coords, t)
  if not unit or t - target.since > Pure.ARRIVAL_MAX_AGE then return 'drop' end
  if target.pending or (target.nextAt and t < target.nextAt) then return 'wait' end
  if unit.callNumber ~= target.callNumber then
    return target.seen and 'drop' or 'wait'
  end
  target.seen = true
  if not unit.status or unit.status.meaning ~= 'en_route' then return 'drop' end
  if not coords then return 'wait' end
  local dx, dy = coords.x - target.x, coords.y - target.y
  if dx * dx + dy * dy > target.radius * target.radius then
    target.hits = 0
    return 'wait'
  end
  target.hits = target.hits + 1
  return target.hits >= Pure.ARRIVAL_HITS and 'fire' or 'wait'
end

function Pure.arrivalResult(target, status, t)
  target.pending = nil
  status = tonumber(status) or 0
  if status == 200 or not Pure.retryable(status) then return 'done' end
  target.attempts = target.attempts + 1
  if target.attempts >= Pure.ARRIVAL_ATTEMPTS then return 'done' end
  target.hits = 0
  target.nextAt = t + Pure.ARRIVAL_RETRY
  return 'retry'
end

function Pure.panicAction(unit, action)
  if not unit then return 'off_duty' end
  if unit.isPanic then return 'clear' end
  if action == 'clearpanic' then return 'none' end
  return 'raise'
end

function Pure.locationLabels(labels)
  if not labels then return nil end
  return { street = labels.street, crossStreet = labels.crossStreet, postal = labels.postal, city = nil, county = nil }
end

Pure.TABLET_MIN_W, Pure.TABLET_MIN_H = 800, 500

function Pure.validRect(r)
  if type(r) ~= 'table' then return false end
  for _, k in ipairs({ 'x', 'y', 'w', 'h' }) do
    local v = r[k]
    if type(v) ~= 'number' or v ~= v or v < -16384 or v > 16384 then return false end
  end
  return r.w >= Pure.TABLET_MIN_W and r.h >= Pure.TABLET_MIN_H
end

function Pure.privateHost(host)
  if type(host) ~= 'string' then return false end
  if host == 'localhost' then return true end
  local a, b, c, d = host:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and b and c and d) or a > 255 or b > 255 or c > 255 or d > 255 then return false end
  return a == 127 or a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)
end

function Pure.tabletUrlSecure(url)
  if url:match('^https://') then return true end
  return Pure.privateHost(url:match('^http://([^/:]+)'))
end

function Pure.isTabletUrl(url)
  if type(url) ~= 'string' or #url > 512 or not Pure.tabletUrlSecure(url) then return false end
  return url:match('^https?://[%w%.%-]+:?%d*/auth/game%?code=[%w_%-]+$') ~= nil or Pure.isLinkOpenUrl(url)
end

function Pure.isLinkOpenUrl(url)
  return type(url) == 'string' and url:match('^https?://[%w%.%-]+:?%d*/auth/game/open$') ~= nil
end

function Pure.isTabletToken(value)
  return type(value) == 'string' and #value == 43 and value:match('^[%w_%-]+$') ~= nil
end

function Pure.tabletPayload(data)
  if type(data) ~= 'table' or not Pure.isTabletUrl(data.url) then return nil end
  if data.tabletToken ~= nil and not Pure.isTabletToken(data.tabletToken) then return nil end
  if not Pure.isLinkOpenUrl(data.url) then return { url = data.url, token = data.tabletToken } end
  if not Pure.isTabletToken(data.tabletToken) then return nil end
  if not Pure.isTabletToken(data.linkCode) then return nil end
  return { url = data.url, token = data.tabletToken, link = data.linkCode }
end

function Pure.tabletVehicleAllowed(cfg, class, model, hash)
  for _, c in ipairs(cfg.vehicleClasses or {}) do
    if c == class then return true end
  end
  for _, name in ipairs(cfg.vehicleModels or {}) do
    if hash(name) == model then return true end
  end
  return false
end

Pure.TABLET_MIN_SCALE, Pure.TABLET_MAX_SCALE = 0.8, 2

function Pure.validScale(s)
  return type(s) == 'number' and s == s and s >= Pure.TABLET_MIN_SCALE and s <= Pure.TABLET_MAX_SCALE
end

function Pure.tabletCodeBody(account, cfg, name)
  local body = Pure.withPlayer(account)
  if cfg and cfg.requireDuty == true then body.requireDuty = true end
  if body.license then body.playerName = Pure.clean(name, 32) end
  return body
end

function Pure.linkArg(args)
  if type(args) ~= 'table' then return nil end
  local code = table.concat(args, ' '):match('^%s*(.-)%s*$')
  if code == '' or #code > 32 then return nil end
  return code
end

local LINK_REFUSALS = { code_expired = 'link_code_expired', code_used = 'link_code_used', license_linked = 'link_license_linked' }

function Pure.linkRefusalKey(problem)
  if type(problem) ~= 'table' then return nil end
  if problem.code == 'link_refused' then return LINK_REFUSALS[problem.reason] or 'link_code_invalid' end
  if problem.code == 'not_member' then return 'link_not_member' end
  if problem.code == 'permission_denied' then return 'link_deleting' end
  return nil
end

function Pure.tabletError(res)
  local code = res and res.problem and res.problem.code
  if type(code) == 'string' and code:match('^[%l_]+$') then return code end
  local status = res and res.status or 0
  if status == 0 then return 'network' end
  return 'http_' .. tostring(math.floor(status))
end

function Pure.vehicleLabel(raw, label)
  if type(raw) ~= 'string' or raw == '' or raw == 'CARNOTFOUND' then return nil end
  if type(label) == 'string' and label ~= '' and label ~= 'NULL' then return label end
  return (raw:lower():gsub('^%l', string.upper))
end

local function u32(h)
  h = math.tointeger(h)
  return h and h % 0x100000000 or nil
end

function Pure.vehicleIndex(names, hash)
  local out = {}
  for name, labels in pairs(names or {}) do
    local h = u32(hash(name))
    if h and type(labels) == 'table' and type(labels[2]) == 'string' and labels[2] ~= '' then
      out[h] = { make = labels[1] ~= '' and labels[1] or nil, model = labels[2] }
    end
  end
  return out
end

function Pure.vehicleLabels(model, index, ask, hash)
  local m = u32(model)
  if not m or m == 0 then return {} end
  local known = index[m]
  if known then return { make = known.make, model = known.model } end
  local client = ask()
  local raw = type(client) == 'table' and client.raw
  if type(raw) ~= 'string' or #raw > 32 or not raw:match('^[%w_]+$') or u32(hash(raw)) ~= m then return {} end
  return { make = Pure.clean(client.make, 40), model = Pure.clean(client.model, 40) }
end

Pure.YEAR_MIN = 1900
Pure.YEAR_MAX = 2100

function Pure.regvehArgs(args)
  args = args or {}
  local year = type(args[1]) == 'string' and args[1]:match('^%d%d%d%d$') and tonumber(args[1])
  if not year or year < Pure.YEAR_MIN or year > Pure.YEAR_MAX then return nil, args end
  return year, { table.unpack(args, 2) }
end

function Pure.regvehBody(discordId, plate, args, detected, year)
  detected = detected or {}
  local body = {
    discordId = discordId,
    plate = plate,
    year = year,
    make = Pure.clean(args[1] or detected.make, 40),
    model = Pure.clean(args[2] or detected.model, 40),
    color = Pure.clean(args[3] and table.concat(args, ' ', 3) or detected.color, 40),
  }
  if not body.make or not body.model or not body.color then return nil end
  return body
end

function Pure.aiVehicleRefusal(unit, vehicle, driver)
  if unit then return 'on_duty' end
  if not vehicle or vehicle == 0 then return 'no_vehicle' end
  if not driver then return 'not_driver' end
  return nil
end

function Pure.aiVehicleBody(discordId, plate, scenario, detected, labels, postal)
  local body = Pure.regvehBody(discordId, plate, {}, detected)
  if not body or plate == '' then return nil end
  body.scenario = scenario
  body.location = placeOf(Pure.locationText(labels))
  body.postal = postal or (labels and labels.postal)
  return body
end

local AI_VEHICLE_PROBLEMS = { plate_taken = 'aiveh_player_vehicle', rate_limited = 'aiveh_cooldown', limit_reached = 'aiveh_limit' }

function Pure.aiVehicleProblem(problem)
  if not problem then return nil end
  if problem.code == 'not_eligible' and problem.reason == 'ai_vehicles_off' then return 'aiveh_off' end
  return AI_VEHICLE_PROBLEMS[problem.code]
end

Pure.HUD_MAX = 20
Pure.HUD_UNITS_MAX = 8
Pure.HUD_EVENTS = { ['call.911'] = true, ['call.unit_attached'] = true, ['call.closed'] = true, ['call.updated'] = true, ['community.settings'] = true }

function Pure.hudEligible(unit)
  local d = type(unit) == 'table' and type(unit.department) == 'table' and unit.department or {}
  return DEPT_RESPONDERS[d.type] == true
end

local function hudText(v, max)
  if type(v) ~= 'string' or v == '' then return nil end
  return Pure.truncate(v, max)
end

local function hudUnits(units, discordId)
  local out, mine = {}, false
  for _, u in ipairs(type(units) == 'table' and units or {}) do
    if type(u) == 'table' then
      if discordId and u.discordId == discordId then mine = true end
      local callsign = hudText(u.callsign, 16)
      if callsign and #out < Pure.HUD_UNITS_MAX then out[#out + 1] = callsign end
    end
  end
  return out, mine
end

function Pure.hudCalls(calls, discordId, attachedNumber)
  local out = {}
  for i, c in ipairs(type(calls) == 'table' and calls or {}) do
    if type(c) == 'table' and Pure.isCallNumber(c.number) and c.status ~= 'closed' then
      local units, mine = hudUnits(c.units, discordId)
      local priority = type(c.priority) == 'number' and math.tointeger(c.priority) or nil
      if priority and (priority < 1 or priority > 9) then priority = nil end
      out[#out + 1] = {
        number = c.number,
        priority = priority,
        nature = hudText(c.nature, 40),
        location = hudText(c.location, 60),
        postal = hudText(c.postal, 10),
        description = hudText(c.description, 240),
        units = units,
        attached = mine or c.number == attachedNumber,
        order = i,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.attached ~= b.attached then return a.attached end
    local pa, pb = a.priority or 10, b.priority or 10
    if pa ~= pb then return pa < pb end
    return a.order < b.order
  end)
  local list = {}
  for i = 1, math.min(#out, Pure.HUD_MAX) do
    out[i].order = nil
    list[i] = out[i]
  end
  return list
end

function Pure.hudHas(list, number)
  for _, c in ipairs(list or {}) do
    if c.number == number then return true end
  end
  return false
end

function Pure.hudSelect(list, number, index)
  if #list == 0 then return nil end
  for i, c in ipairs(list) do
    if c.number == number then return i end
  end
  return math.max(1, math.min(tonumber(index) or 1, #list))
end

function Pure.hudMove(list, index, step)
  if #list == 0 or not index then return nil end
  return math.max(1, math.min(index + step, #list))
end

function Pure.hudView(list, index)
  local current = index and list[index]
  if not current then return nil end
  return { index = index, total = #list, prev = list[index - 1], current = current, next = list[index + 1] }
end

Pure.CITATION_MAX = 5
Pure.CITATION_CHARGES_MAX = 20
Pure.SIGNATURE_MAX = 200
Pure.CITATION_ACTIONS = { sign = true, keep = true, close = true }

local UUID = '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'

function Pure.isRecordId(s)
  return type(s) == 'string' and s:match(UUID) ~= nil
end

local function whole(v)
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return math.floor(v)
end

local function citationOf(c)
  if type(c) ~= 'table' or not Pure.isRecordId(c.id) then return nil end
  local charges = {}
  for _, ch in ipairs(type(c.charges) == 'table' and c.charges or {}) do
    if #charges >= Pure.CITATION_CHARGES_MAX then break end
    if type(ch) == 'table' then
      charges[#charges + 1] = {
        code = text(ch.code, 20) or '', title = Pure.truncate(text(ch.title, 200) or '', 80),
        counts = whole(ch.counts), fine = whole(ch.fine), points = whole(ch.points),
      }
    end
  end
  local totals = type(c.totals) == 'table' and c.totals or {}
  return {
    id = c.id,
    number = text(c.number, 30),
    name = Pure.truncate(text(c.characterName, 200) or '', 80),
    occurredAt = text(c.occurredAt, 30),
    officer = text(c.officer, 60),
    department = text(c.department, 20),
    location = Pure.truncate(text(c.location, 300) or '', 120),
    charges = charges,
    fine = whole(totals.fine),
    jailSeconds = whole(totals.jailSeconds),
    points = whole(totals.points),
    version = text(c.version, 40),
  }
end

function Pure.citationList(list)
  local out = {}
  for _, c in ipairs(type(list) == 'table' and list or {}) do
    if #out >= Pure.CITATION_MAX then break end
    out[#out + 1] = citationOf(c)
  end
  return out
end

function Pure.citationAction(data)
  if type(data) ~= 'table' or type(data.action) ~= 'string' or not Pure.CITATION_ACTIONS[data.action] then return nil end
  if not Pure.isRecordId(data.id) then return nil end
  local out = { kind = data.action, id = data.id }
  if data.action == 'sign' then
    if type(data.signature) ~= 'string' or #data.signature > Pure.SIGNATURE_MAX * 4 then return nil end
    out.signature = Pure.clean(data.signature, Pure.SIGNATURE_MAX)
    if not out.signature then return nil end
  end
  return out
end

function Pure.citationItem(c, label)
  return {
    citation = c.id,
    number = c.number,
    label = label,
    description = ('%s, %s'):format(c.name ~= '' and c.name or '?', c.occurredAt and c.occurredAt:sub(1, 10) or '?'),
    fine = c.fine,
  }
end

function Pure.keyLabel(raw, fallback)
  if type(raw) == 'string' and raw:sub(1, 2) == 't_' and #raw > 2 then return raw:sub(3):upper() end
  return fallback
end

Pure.SCENE_MARKER_KINDS = {
  roadblock = { sprite = 41, colour = 3, name = 'Roadblock' },
  fire_scene = { sprite = 39, colour = 1, name = 'Fire scene' },
  crime_scene = { sprite = 58, colour = 0, name = 'Crime scene' },
  hazard = { sprite = 934, colour = 5, name = 'Hazard' },
  staging = { sprite = 38, colour = 3, name = 'Staging area' },
  landing_zone = { sprite = 360, colour = 0, name = 'Landing zone' },
}
Pure.SCENE_MARKER_LABEL_MAX = 60
Pure.SCENE_MARKERS_MAX = 50

local function markerId(id)
  return type(id) == 'string' and #id == 36 and id:match('^%x+%-%x+%-%x+%-%x+%-%x+$') ~= nil
end

function Pure.sceneMarker(m)
  if type(m) ~= 'table' or not markerId(m.id) or not Pure.SCENE_MARKER_KINDS[m.kind] then return nil end
  if not Pure.validCoords({ x = m.x, y = m.y }) then return nil end
  local label = Pure.clean(m.label, Pure.SCENE_MARKER_LABEL_MAX)
  return { id = m.id, kind = m.kind, label = label, x = m.x + 0.0, y = m.y + 0.0 }
end

function Pure.sceneMarkerSet(list)
  local out, n = {}, 0
  if type(list) ~= 'table' then return out end
  for _, item in ipairs(list) do
    local m = Pure.sceneMarker(item)
    if m and not out[m.id] and n < Pure.SCENE_MARKERS_MAX then
      out[m.id] = m
      n = n + 1
    end
  end
  return out
end

function Pure.applySceneMarkerEvent(markers, kind, payload)
  if type(payload) ~= 'table' then return false end
  if kind == 'scene_marker.set' then
    local m = Pure.sceneMarker(payload)
    if not m or markers[m.id] then return false end
    markers[m.id] = m
    return true
  elseif kind == 'scene_marker.cleared' then
    if not markerId(payload.id) or not markers[payload.id] then return false end
    markers[payload.id] = nil
    return true
  end
  return false
end

function Pure.sceneMarkerList(markers)
  local list = {}
  for _, m in pairs(markers) do list[#list + 1] = m end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function Pure.sceneMarkersVisible(cfg, unit)
  if type(cfg) ~= 'table' or cfg.blips == false then return false end
  return cfg.everyone == true or unit ~= nil
end

function Pure.sceneBlipName(m)
  return m.label or Pure.SCENE_MARKER_KINDS[m.kind].name
end

function Pure.sceneBlipKey(m)
  return ('%s|%s|%.1f|%.1f'):format(m.kind, m.label or '', m.x, m.y)
end

function Pure.sceneBlipChanges(current, list)
  local wanted = {}
  local add, remove = {}, {}
  for _, item in ipairs(type(list) == 'table' and list or {}) do
    local m = Pure.sceneMarker(item)
    if m and not wanted[m.id] then
      wanted[m.id] = true
      if current[m.id] ~= Pure.sceneBlipKey(m) then
        if current[m.id] then remove[#remove + 1] = m.id end
        add[#add + 1] = m
      end
    end
  end
  for id in pairs(current) do
    if not wanted[id] then remove[#remove + 1] = id end
  end
  table.sort(remove)
  return add, remove
end

function Pure.buildSceneMarker(data)
  if type(data) ~= 'table' or not Pure.SCENE_MARKER_KINDS[data.kind] then return nil, 'validation' end
  local at = type(data.coords) == 'table' and data.coords or data
  local x, y = tonumber(at.x), tonumber(at.y)
  if not x or not y or not Pure.validCoords({ x = x, y = y }) then return nil, 'validation' end
  if data.label ~= nil and type(data.label) ~= 'string' then return nil, 'validation' end
  local label = Pure.clean(data.label, Pure.SCENE_MARKER_LABEL_MAX + 1)
  if label and unitCount(codepoints(label)) > Pure.SCENE_MARKER_LABEL_MAX then return nil, 'validation' end
  return { kind = data.kind, label = label, x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10 }
end

function Pure.isSceneMarkerId(id)
  return markerId(id)
end

return Pure
