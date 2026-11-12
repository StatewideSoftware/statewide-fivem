Wraith = { flagged = {}, native = false }

local cfg = Config.wraith
local rates, cams, alerted, lockSeen, lockWindow, hitWindow = {}, {}, {}, {}, {}, {}
local dedup = {}
local ALERTED_MAX = 256
local PAGES_MAX = 200

local function clock()
  return GetGameTimer() / 1000
end

local function words()
  local out = { front = L('alpr_front'), rear = L('alpr_rear') }
  for _, f in ipairs(Pure.ALPR_FLAGS) do out[f] = L('alpr_flag_' .. f) end
  return out
end

local function underRate(src)
  local now = clock()
  local r = rates[src]
  if not r or now - r.start >= 1 then
    rates[src] = { start = now, n = 1 }
    return true
  end
  r.n = r.n + 1
  return r.n <= (tonumber(cfg.readsPerSecond) or 4)
end

local function ignoredClass(extra)
  if type(extra) ~= 'table' then return false end
  local class = extra.class
  if type(class) ~= 'number' or class % 1 ~= 0 or class < 0 or class > 22 then return false end
  for _, c in ipairs(cfg.ignoreClasses or {}) do
    if c == class then return true end
  end
  return false
end

function Wraith.detect()
  local ok, version = pcall(GetResourceMetadata, cfg.resource, 'version', 0)
  Wraith.native = ok and Pure.radarNative(version) or false
  return Wraith.native
end

local function nearby(ped, key)
  local me = GetEntityCoords(ped)
  local limit = tonumber(cfg.proximityMeters) or 100
  for _, veh in ipairs(GetAllVehicles() or {}) do
    if Pure.plateKey(GetVehicleNumberPlateText(veh)) == key then
      local at = GetEntityCoords(veh)
      local dx, dy, dz = at.x - me.x, at.y - me.y, at.z - me.z
      if dx * dx + dy * dy + dz * dz <= limit * limit then return true end
    end
  end
  return false
end

local function reportedNear(ped, key, netId)
  if not netId then return false end
  local veh = NetworkGetEntityFromNetworkId(netId)
  if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return false end
  if Pure.plateKey(GetVehicleNumberPlateText(veh)) ~= key then return false end
  local me, at = GetEntityCoords(ped), GetEntityCoords(veh)
  local limit = tonumber(cfg.proximityMeters) or 100
  local dx, dy, dz = at.x - me.x, at.y - me.y, at.z - me.z
  return dx * dx + dy * dy + dz * dz <= limit * limit
end

local function reader(src, cam, plate, extra)
  if not Modules.active.wraith then return nil end
  if not Pure.alprCam(cam) then return nil end
  local norm = Pure.normalizePlate(plate)
  if not norm then return nil end
  local p = State.peek(src)
  if not (p and p.unit) then return nil end
  local account = Identity.getAccount(src)
  if not account then return nil end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 then return nil end
  if ignoredClass(extra) then return nil end
  local read = { p = p, account = account, ped = ped, car = veh, plate = norm, key = Pure.plateKey(norm) }
  if Wraith.native then
    local info = Pure.radarInfo(extra)
    read.netId = info and info.netId
  end
  return read
end

local function accept(src, cam, plate, extra)
  if not Modules.active.wraith then return nil end
  if not underRate(src) then return nil end
  return reader(src, cam, plate, extra)
end

local function near(read)
  return cfg.proximityCheck ~= true or reportedNear(read.ped, read.key, read.netId) or nearby(read.ped, read.key)
end

local function window(store, src, limit)
  store[src] = store[src] or {}
  return Pure.windowAllow(store[src], clock(), tonumber(limit) or 0, 60)
end

local function camState(src, cam)
  cams[src] = cams[src] or {}
  cams[src][cam] = cams[src][cam] or {}
  return cams[src][cam]
end

local function remember(src, key, flags)
  local list = alerted[src]
  if not list then
    list = { n = 0, at = {} }
    alerted[src] = list
  end
  if not list.at[key] then
    if list.n >= ALERTED_MAX then
      list.at, list.n = {}, 0
    end
    list.n = list.n + 1
  end
  list.at[key] = { at = clock(), signature = Pure.alprSignature(flags) }
end

local function postHit(src, read, cam, flags)
  if not window(hitWindow, src, cfg.hitsPerMinute) then return end
  local labels = read.p.labels or {}
  local body = Pure.withPlayer(read.account, {
    plate = read.key, cam = cam, flags = flags,
    street = labels.street, crossStreet = labels.crossStreet, postal = labels.postal,
  })
  CreateThread(function()
    local ok, err = pcall(function() return api('POST', '/alpr/hits', 'lookup', { body = body, as = read.account, retry = false }) end)
    if not ok then print(('^1[statewide] ALPR hit post: %s^7'):format(err)) end
  end)
end

local function nativeLock(src, cam, plate)
  local ok, err = pcall(function() return exports[cfg.resource]:SetPlateLock(src, cam, plate, true) end)
  if not ok then print(('^1[statewide] Wraith lock: %s^7'):format(err)) end
end

local function radarAlert(src, cam, plate, flags)
  if cfg.radarAlerts == false then return end
  local alert = Pure.alprAlert(cam, plate, flags, words())
  if alert then TriggerClientEvent('wk:showAlert', src, alert) end
end

local function autoLock(src, cam, plate)
  if cfg.lockOnHit ~= true then return end
  if Wraith.native then return nativeLock(src, cam, plate) end
  local state = camState(src, cam)
  if not Pure.canAutoLock(state, plate) then return end
  local ok, err = pcall(TriggerClientEvent, 'wk:togglePlateLock', src, cam, false, true)
  if ok then
    state.locked = true
  else
    print(('^1[statewide] Wraith lock: %s^7'):format(err))
  end
end

local function scanned(src, cam, plate, extra)
  local read = accept(src, cam, plate, extra)
  if not read then return end
  local state = camState(src, cam)
  state.plate, state.locked = read.plate, false
  local flags = Pure.alprFlags(Wraith.flagged[read.key], cfg.alertOn, os.time())
  if #flags == 0 or not near(read) then return end
  local now = clock()
  local key = Pure.dedupKey(NetworkGetNetworkIdFromEntity(read.car), read.key)
  if not key or not Pure.useKeyedCooldown(dedup, key, now, tonumber(cfg.dedupSeconds) or 90, 512) then return end
  local list = alerted[src]
  if not Pure.shouldAlert(list and list.at[read.key], now, flags, tonumber(cfg.alertCooldownSeconds)) then return end
  remember(src, read.key, flags)
  local _, sound = Pure.alprSeverity(flags)
  Notify.push(src, 'alpr', { text = Pure.alprText(cam, read.plate, flags, words()), sound = sound })
  if Wraith.native then radarAlert(src, cam, read.plate, flags) end
  postHit(src, read, cam, flags)
  autoLock(src, cam, read.plate)
end

local function showReturn(src, cam, read)
  local camWord = words()[cam]
  local res = api('GET', '/lookup/vehicle', 'lookup', { query = { discordId = Pure.playerSlot(read.account), plate = read.key, partial = 'false' }, as = read.account })
  if res.status ~= 200 or not res.data then return Notify.problem(src, res) end
  local first = res.data.results and res.data.results[1]
  if not first then return Notify.player(src, L('alpr_lock_none', camWord, read.plate), 'info') end
  local flags = Pure.alprFlags(Wraith.flagged[read.key], cfg.alertOn, os.time())
  local _, sound = Pure.alprSeverity(flags)
  Notify.push(src, 'alpr', { text = L('alpr_lock', camWord, read.plate), sound = sound })
  Commands.showVehicle(src, first)
end

local function locked(src, cam, plate, extra)
  local read = accept(src, cam, plate, extra)
  if not read then return end
  local state = camState(src, cam)
  state.plate, state.locked = read.plate, true
  if not near(read) then return end
  lockSeen[src] = lockSeen[src] or {}
  if not Pure.useKeyedCooldown(lockSeen[src], read.key, clock(), tonumber(cfg.alertCooldownSeconds) or 300, 256) then return end
  if not window(lockWindow, src, cfg.lookupsPerMinute) then return end
  showReturn(src, cam, read)
end

local function sendPlate(src, cam, plate)
  if not underRate(src) then return end
  local read = reader(src, cam, plate, nil)
  if not read or not near(read) then return end
  if not window(lockWindow, src, cfg.lookupsPerMinute) then return end
  showReturn(src, cam, read)
end

local function guarded(fn)
  return function(cam, plate, _, extra)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    CreateThread(function()
      local ok, err = pcall(fn, src, cam, plate, extra)
      if not ok then print(('^1[statewide] Wraith: %s^7'):format(err)) end
    end)
  end
end

function Wraith.load()
  if not Modules.active.wraith then return end
  local set, after = {}, nil
  for _ = 1, PAGES_MAX do
    local res = api('GET', '/plates/flagged', 'lookup', { query = after and { after = after } or nil, retry = false })
    if res.status ~= 200 or not res.data then return end
    for _, row in ipairs(res.data.plates or {}) do
      local key, entry = Pure.flaggedEntry(row)
      if key then set[key] = entry end
    end
    after = res.data.cursor
    if type(after) ~= 'string' then break end
  end
  Wraith.flagged = set
end

function Wraith.flagsChanged(payload)
  local key, entry = Pure.flaggedEntry(payload)
  if not key then return end
  Wraith.flagged[key] = #entry.flags > 0 and entry or nil
end

local function verified(fn)
  return function(...)
    if not Pure.isServerSource(source) or not Wraith.native then return end
    local args = table.pack(...)
    local src = tonumber(args[1])
    if not src or src <= 0 or src % 1 ~= 0 then return end
    args[1] = src
    CreateThread(function()
      local ok, err = pcall(fn, table.unpack(args, 1, args.n))
      if not ok then print(('^1[statewide] Wraith: %s^7'):format(err)) end
    end)
  end
end

local function plateVerified(src, plate, cam)
  sendPlate(src, cam, plate)
end

local function speedVerified(src, ant, speed, _, plate, info)
  if cfg.debug ~= true or not underRate(src) then return end
  local p = State.peek(src)
  if not (p and p.unit) or not Pure.alprCam(ant) then return end
  local unit = type(info) == 'table' and (info.unit == 'mph' or info.unit == 'kmh') and info.unit or ''
  print(('[statewide] Wraith speed lock: player %d %s %s %s %s'):format(src, ant, tostring(type(speed) == 'number' and math.tointeger(speed) or ''), unit,
      Pure.normalizePlate(plate) or ''))
end

function Wraith.register()
  Wraith.detect()
  RegisterNetEvent('wk:onPlateScanned', guarded(scanned))
  RegisterNetEvent('wk:onPlateLocked', guarded(locked))
  AddEventHandler('wk:sendPlateVerified', verified(plateVerified))
  AddEventHandler('wk:onSpeedLockedVerified', verified(speedVerified))
  CreateThread(function()
    local ok, err = pcall(Wraith.load)
    if not ok then print(('^1[statewide] Wraith: %s^7'):format(err)) end
  end)
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  rates[src], cams[src], alerted[src], lockSeen[src], lockWindow[src], hitWindow[src] = nil, nil, nil, nil, nil, nil
end)

Modules.resolve('wraith', Wraith.register, L('wraith_absent', cfg.resource))

AddEventHandler('onResourceStart', function(name)
  if name == cfg.resource then Wraith.detect() end
end)

AddEventHandler('onResourceStop', function(name)
  if name == cfg.resource then Wraith.native = false end
end)
