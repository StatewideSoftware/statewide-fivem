Locations = {}

local dirty = {}
local lastLabels = {}
local lastSent = {}
local lastBeat = {}
local inFlight = false

function Locations.serverPostal(coords)
  local res = Config.postalResource
  if type(coords) ~= 'table' or type(res) ~= 'string' or GetResourceState(res) ~= 'started' then return nil end
  local ok, value = pcall(function() return exports[res]:getPostalServer({ coords.x, coords.y }) end)
  return ok and Pure.postalCode(value) or nil
end

function Locations.forget(src)
  lastSent[tonumber(src)] = nil
  lastBeat[tonumber(src)] = nil
end

function Locations.markDirty(src)
  dirty[tonumber(src)] = true
end

Locations.LABELS_WAIT_MS = 1500
local asked = {}

function Locations.fetchLabels(src)
  src = tonumber(src)
  local p = State.get(src)
  if p.unit and p.labels then return p.labels end
  p.labels = nil
  local at = GetGameTimer()
  asked[src] = at
  TriggerClientEvent('statewide:client:labels', src)
  while asked[src] == at and GetGameTimer() - at < Locations.LABELS_WAIT_MS do Wait(50) end
  if asked[src] == at then asked[src] = nil end
  return State.get(src).labels
end

local places = {}
local placeSeq = 0

function Locations.labelsAt(src, pos)
  src = tonumber(src)
  placeSeq = placeSeq + 1
  local ask = { token = placeSeq }
  places[src] = ask
  TriggerClientEvent('statewide:client:labelsAt', src, ask.token, pos.x + 0.0, pos.y + 0.0, type(pos.z) == 'number' and pos.z + 0.0 or nil)
  local at = GetGameTimer()
  while places[src] == ask and not ask.done and GetGameTimer() - at < Locations.LABELS_WAIT_MS do Wait(50) end
  if places[src] == ask then places[src] = nil end
  return ask.labels
end

RegisterNetEvent('statewide:labelsAt', function(token, street, crossStreet, zone)
  local src = tonumber(source)
  if not src or src <= 0 then return end
  local ask = places[src]
  if not ask or ask.done or ask.token ~= token then return end
  ask.done = true
  ask.labels = Pure.cleanLabels(street, crossStreet, nil, Config.labels.maxLength, zone)
end)

RegisterNetEvent('statewide:labels', function(street, crossStreet, postal, zone)
  local src = tonumber(source)
  if not src or src <= 0 then return end
  local t = GetGameTimer() / 1000
  local answer = asked[src] ~= nil
  if not answer and lastLabels[src] and t - lastLabels[src] < Config.labels.minSeconds - 0.5 then return end
  asked[src] = nil
  local labels = Pure.cleanLabels(street, crossStreet, postal, Config.labels.maxLength, zone)
  if not labels then return end
  lastLabels[src] = t
  local p = State.get(src)
  local old = p.labels
  if old and old.street == labels.street and old.crossStreet == labels.crossStreet and old.postal == labels.postal and old.zone == labels.zone then return end
  p.labels = labels
  dirty[src] = true
end)

local function readMotion(src, pos)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return end
  local vehicle = GetVehiclePedIsIn(ped, false)
  local inVehicle = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
  pos.movement = inVehicle and Pure.movementFromType(GetVehicleType(vehicle) or 'automobile') or 'foot'
  pos.speed = Pure.speed(GetEntityVelocity(inVehicle and vehicle or ped))
end

local LEGACY_PROBE_SECONDS = 600
local legacySince = nil

local function post(batch, legacy)
  local units = {}
  for i, e in ipairs(batch) do
    local body = e.body
    if legacy then
      body = {}
      for k, v in pairs(e.body) do
        if k ~= 'movement' and k ~= 'speed' then body[k] = v end
      end
    end
    units[i] = body
  end
  return api('PATCH', '/units/locations', 'units', { body = { units = units }, retry = false })
end

local function send(batch, t)
  for _, e in ipairs(batch) do dirty[e.src] = nil end
  local legacy = legacySince ~= nil and t - legacySince < LEGACY_PROBE_SECONDS
  local res = post(batch, legacy)
  if not legacy and (res.status == 400 or res.status == 422) then
    local retry = post(batch, true)
    if retry.status == 200 then legacySince = t end
    res = retry
  end
  if res.status == 200 or not Pure.retryable(res.status) then
    for _, e in ipairs(batch) do
      if e.pos then lastSent[e.src] = e.pos end
      if e.beat then lastBeat[e.src] = t end
    end
    if res.status ~= 200 then
      print(('^3[statewide] location batch of %d refused (HTTP %d); dropped until labels change^7'):format(#batch, res.status))
    end
    return
  end
  for _, e in ipairs(batch) do dirty[e.src] = true end
end

function Locations.flush()
  if inFlight then return end
  local entries = {}
  local t = GetGameTimer() / 1000
  for src, p in pairs(State.all()) do
    local who = p.unit and (p.unit.discordId and { discordId = p.unit.discordId } or Pure.accountOfState(p))
    if who then
      local hidden = p.trackingHidden == true
      local pos = not hidden and Pure.position(State.readCoords(src)) or nil
      if pos then readMotion(src, pos) end
      local moved = Pure.shouldSend(lastSent[src], pos, t, Config.positions)
      local beat = hidden and Pure.keepaliveDue(lastBeat[src], t, Config.positions)
      local labels = dirty[src] and p.labels
      if labels or moved or beat then
        local body = Pure.withPlayer(who)
        if labels then body.location, body.postal, body.zoneCode = Pure.locationText(labels), labels.postal, labels.zone end
        if pos and p.labels and p.labels.postal then body.postal = p.labels.postal end
        if pos then body.x, body.y, body.heading, body.movement, body.speed = pos.x, pos.y, pos.heading, pos.movement, pos.speed end
        if pos then pos.at = t end
        entries[#entries + 1] = { src = src, body = body, pos = pos, beat = hidden }
      end
    end
  end
  if #entries == 0 then return end
  inFlight = true
  for _, batch in ipairs(Pure.chunk(entries, Pure.LOCATIONS_MAX)) do send(batch, t) end
  inFlight = false
end

function Locations.start(generation)
  CreateThread(function()
    while Lifecycle.generation == generation do
      local seconds = math.max(2, GetConvarInt('statewide_location_interval', Config.locationInterval))
      Wait(seconds * 1000)
      if Lifecycle.generation ~= generation then return end
      local ok, err = pcall(Locations.flush)
      if not ok then
        inFlight = false
        print(('^1[statewide] location batch: %s^7'):format(err))
      end
      local checked, failure = pcall(Arrival.check)
      if not checked then print(('^1[statewide] arrival check: %s^7'):format(failure)) end
    end
  end)
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  dirty[src] = nil
  lastLabels[src] = nil
  lastSent[src] = nil
  lastBeat[src] = nil
  asked[src] = nil
  places[src] = nil
end)
