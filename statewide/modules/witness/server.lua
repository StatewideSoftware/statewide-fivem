Witness = {}

local HINT_SECONDS = 1
local PENDING_MAX = 8
local SEEN_MAX = 256
local SAMPLE_MS = 2000
local SAMPLE_MAX = 5
local CRASH_WINDOW = 6
local hints, cooldowns, incidents, sent, refusals, shots, quota = {}, {}, {}, {}, {}, {}, {}
local samples = {}
local wrecks = { n = 0 }
local pending = 0
local ignored

local function cfg()
  return Config.witness
end

local function now()
  return GetGameTimer() / 1000
end

local function hash(v)
  v = math.tointeger(v)
  return v and v & 0xffffffff or nil
end

local function kindOn(kind)
  local c = cfg()
  return type(c) == 'table' and c.enabled == true and type(c[kind]) == 'table' and c[kind].enabled ~= false
end

local function ignoredWeapon(weapon)
  if not ignored then
    ignored = {}
    for _, name in ipairs(cfg().shots.ignore or {}) do ignored[hash(GetHashKey(name))] = true end
  end
  weapon = hash(weapon)
  return not weapon or weapon == 0 or ignored[weapon] == true
end

local function remember(store, key, value)
  if store[key] == nil then
    if store.n >= SEEN_MAX then
      for k in pairs(store) do if k ~= 'n' then store[k] = nil end end
      store.n = 0
    end
    store.n = store.n + 1
  end
  store[key] = value
end

local function point(v)
  return v and { x = v.x, y = v.y, z = v.z } or nil
end

local function templates()
  local types = {}
  for _, t in ipairs({ 'automobile', 'bike', 'quadbike', 'bicycle', 'boat', 'heli', 'plane', 'trailer', 'default' }) do types[t] = L('witness_type_' .. t) end
  return { vehicle = L('witness_vehicle'), plate = L('witness_plate'), types = types, place = L('witness_place'), seen = L('witness_seen') }
end

local function describe(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
  local primary = GetVehicleColours(veh)
  local showPlate = Pure.witnessChance(cfg().plateChance, math.random(100))
  return Pure.witnessVehicle({ color = Paint[primary], vtype = GetVehicleType(veh), plate = GetVehicleNumberPlateText(veh) }, templates(), showPlate)
end

local function driving(ped)
  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
  if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
  return veh
end

local read = {}

function read.shots(ped)
  if ignoredWeapon(GetSelectedPedWeapon(ped)) then return nil end
  local veh = GetVehiclePedIsIn(ped, false)
  return { coords = point(GetEntityCoords(ped)), vehicle = describe(veh) }
end

function read.crash(ped)
  local veh = driving(ped)
  local c = cfg().crash
  if not veh then return nil end
  local current = { body = GetVehicleBodyHealth(veh), engine = GetVehicleEngineHealth(veh) }
  if not Pure.crashSeen(samples[veh], now(), current, c.damage, CRASH_WINDOW, c.minSpeed) then return nil end
  samples[veh] = nil
  return { coords = point(GetEntityCoords(veh)), vehicle = describe(veh) }
end

function read.reckless(ped)
  local r = cfg().reckless
  local veh = driving(ped)
  if not veh or GetEntitySpeed(veh) < r.pavementSpeed then return nil end
  local need = math.max(2, r.samples or 3)
  if not Pure.sustained(samples[veh], now(), r.pavementSpeed, need, need * SAMPLE_MS / 1000 + 1) then return nil end
  samples[veh] = nil
  return { coords = point(GetEntityCoords(veh)), vehicle = describe(veh) }
end

function read.wreck(ped)
  local veh = GetVehiclePedIsIn(ped, true)
  if not veh or veh == 0 or not DoesEntityExist(veh) or wrecks[veh] then return nil end
  if GetPedInVehicleSeat(veh, -1) ~= 0 then return nil end
  if not Pure.wrecked(GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh), cfg().wreck) then return nil end
  local at, by = point(GetEntityCoords(veh)), point(GetEntityCoords(ped))
  local dx, dy = at.x - by.x, at.y - by.y
  local reach = cfg().wreck.distance
  if dx * dx + dy * dy > reach * reach then return nil end
  remember(wrecks, veh, true)
  return { coords = at, entity = veh, vehicle = describe(veh) }
end

local function sampling()
  local c = cfg()
  return type(c) == 'table' and c.enabled == true and (kindOn('crash') or kindOn('reckless'))
end

function Witness.sample()
  local t, kept = now(), {}
  for _, s in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(s)
    local veh = ped and ped ~= 0 and driving(ped)
    if veh then
      local list = samples[veh] or {}
      Pure.witnessSample(list, { at = t, body = GetVehicleBodyHealth(veh), engine = GetVehicleEngineHealth(veh), speed = GetEntitySpeed(veh) }, SAMPLE_MAX)
      kept[veh] = list
    end
  end
  samples = kept
end

function Witness.sampleLoop()
  while true do
    Wait(SAMPLE_MS)
    if sampling() then pcall(Witness.sample) elseif next(samples) then samples = {} end
  end
end

local function witnessed(coords, bucket)
  local c = cfg()
  local need, r2, n = math.max(1, c.minWitnesses or 1), c.radius * c.radius, 0
  local peds = GetAllPeds()
  for i = 1, #peds do
    local p = peds[i]
    local at = GetEntityCoords(p)
    local dx, dy = at.x - coords.x, at.y - coords.y
    if dx * dx + dy * dy <= r2 and not IsPedAPlayer(p) and Pure.ambientPed(GetEntityPopulationType(p)) and GetEntityHealth(p) > 0 and GetEntityRoutingBucket(p) == bucket then
      n = n + 1
      if n >= need then return true end
    end
  end
  return false
end

local function refuse(code)
  if Pure.refusalThrottle(refusals, 'witness', code, now(), 300) then
    print(('^3[statewide] witness report refused: %s^7'):format(tostring(code)))
  end
end

local function placeOf(src, coords)
  local labels = Locations.labelsAt(src, coords)
  local location = Pure.locationText(labels) or L('unknown_location')
  return location, Pure.preferPostal(Locations.serverPostal(coords), labels), labels
end

local function postReport(body)
  local res = api('POST', '/dot/reports', 'calls', { body = body })
  if res.problem and res.problem.code == 'validation_failed' and body.postal then
    body.postal = nil
    res = api('POST', '/dot/reports', 'calls', { body = body })
  end
  return res
end

local function stillWrecked(seen)
  local veh = seen.entity
  if not DoesEntityExist(veh) or GetPedInVehicleSeat(veh, -1) ~= 0 then return false end
  if not Pure.wrecked(GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh), cfg().wreck) then return false end
  local at = GetEntityCoords(veh)
  local dx, dy = at.x - seen.coords.x, at.y - seen.coords.y
  return dx * dx + dy * dy <= 100
end

local function fileWreck(src, seen)
  if not stillWrecked(seen) then return end
  local location, postal = placeOf(src, seen.coords)
  local text = Pure.witnessText(L('witness_wreck'), location, postal, seen.vehicle, templates())
  local res = postReport({ type = L('witness_wreck_type'), location = Pure.clean(location, 120) or L('unknown_location'), postal = postal, description = text })
  if res.status ~= 201 then refuse(res.problem and res.problem.code or ('http_' .. tostring(res.status))) end
end

local function cadPostal(number)
  local res = api('GET', '/calls/{number}', 'calls', { params = { number = number }, retry = false })
  local c = res.status == 200 and type(res.data) == 'table' and res.data.call
  return type(c) == 'table' and Pure.postalCode(c.postal) or nil
end

local function withCadPostal(kind, location, seen, body, number, sentPostal)
  if body.postal then return body.description end
  local postal = cadPostal(number)
  if not postal and not sentPostal then return body.description end
  local text = Pure.witnessText(L('witness_' .. kind), location, postal, seen.vehicle, templates())
  if text == body.description then return text end
  local res = api('PATCH', '/calls/{number}', 'calls', { params = { number = number }, body = { description = text }, retry = false })
  return res.status == 200 and text or body.description
end

local function call(src, kind, seen)
  local location, postal, labels = placeOf(src, seen.coords)
  local text = Pure.witnessText(L('witness_' .. kind), location, postal, seen.vehicle, templates())
  local body = Pure.witness911Body({ description = text, location = location, postal = postal, coords = seen.coords, zoneCode = labels and labels.zone })
  local res = Commands.post911(body)
  if res.status == 201 and res.data and type(res.data.number) == 'string' then
    local described = withCadPostal(kind, location, seen, body, res.data.number, postal)
    return Commands.after911(nil, res, body.location, described, 'witness', seen.coords)
  end
  refuse(res.problem and res.problem.code or ('http_' .. tostring(res.status)))
end

local function report(src, kind, seen)
  Wait(math.floor((kind == 'wreck' and cfg().wreck.delay or cfg().delay) * 1000))
  if kind == 'wreck' then return fileWreck(src, seen) end
  call(src, kind, seen)
end

local function schedule(src, kind, seen)
  local held = kind ~= 'wreck'
  if held then pending = pending + 1 end
  CreateThread(function()
    local ok, err = pcall(report, src, kind, seen)
    if held then pending = pending - 1 end
    if not ok then print(('^3[statewide] witness report error: %s^7'):format(tostring(err))) end
  end)
end

function Witness.hint(src, kind)
  kind = Pure.witnessKind(kind)
  if not kind or not kindOn(kind) then return end
  local t = now()
  hints[src] = hints[src] or {}
  if not Pure.useCooldown(hints[src], 'hint', t, HINT_SECONDS) then return end
  local p = State.peek(src)
  if not p or not p.checkedAt or p.unit then return end
  if GetPlayerRoutingBucket(src) ~= 0 then return end
  local c, k = cfg(), cfg()[kind]
  cooldowns[src] = cooldowns[src] or {}
  if not Pure.cooldown(cooldowns[src][kind], t, k.cooldown or 0) then return end
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or not DoesEntityExist(ped) then return end
  local seen = read[kind](ped)
  if not seen or not seen.coords then return end
  if kind == 'shots' then
    shots[src] = shots[src] or {}
    if not Pure.corroborated(shots[src], t, math.max(1, k.confirm or 2), k.confirmSeconds or 10) then return end
  end
  local at = seen.coords
  if Pure.inQuietZone(c.quietZones, at.x, at.y) then return end
  if not Pure.witnessIncident(incidents, kind, at.x, at.y, t, c.areaRadius, k.cooldown or 0) then return end
  if not witnessed(at, 0) then return end
  cooldowns[src][kind] = t
  if not Pure.witnessChance(k.chance, math.random(100)) then return end
  if kind ~= 'wreck' and pending >= PENDING_MAX then return end
  quota[src] = quota[src] or {}
  if not Pure.witnessWindow(quota[src], t, c.playerPerMinute or 2, 60) then return end
  if not Pure.witnessWindow(sent, t, c.perMinute, 60) then
    table.remove(quota[src])
    return
  end
  schedule(src, kind, seen)
end

RegisterNetEvent('statewide:witness:hint', function(kind)
  local src = tonumber(source)
  if not src or src <= 0 then return end
  Witness.hint(src, kind)
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  hints[src], cooldowns[src], shots[src], quota[src] = nil, nil, nil, nil
end)

CreateThread(Witness.sampleLoop)
