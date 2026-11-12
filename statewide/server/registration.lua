Registration = {}

local BAG = 'statewide:unregistered'
local SIGNAL_GAP = 2
local state = Pure.regNew()
local models

local function now()
  return GetGameTimer() / 1000
end

local function mode()
  return Pure.regMode(Config.registration)
end

local function read(src)
  local p = State.peek(src)
  local ped = GetPlayerPed(src)
  local seen = { unit = p and p.unit, vehicle = 0 }
  if ped and ped ~= 0 then seen.vehicle = GetVehiclePedIsIn(ped, false) end
  if seen.vehicle == 0 then return p, seen end
  seen.driver = GetPedInVehicleSeat(seen.vehicle, -1) == ped
  if not seen.driver then return p, seen end
  models = models or Pure.regModelSet(Config.registration.skipModels, GetHashKey)
  seen.skipModels = models
  seen.population = GetEntityPopulationType(seen.vehicle)
  seen.model = GetEntityModel(seen.vehicle)
  seen.plate = GetVehicleNumberPlateText(seen.vehicle)
  return p, seen
end

local function lookup(account, ssn, plate)
  local res = api('GET', '/characters/{ssn}/profile', 'civilian', { params = { ssn = ssn }, query = { discordId = Pure.playerSlot(account) }, as = account })
  if res.status ~= 200 or type(res.data) ~= 'table' then return nil end
  return Pure.regPutProfile(state, ssn, plate, res.data.vehicles, now())
end

local function setLock(vehicle, locked)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
  local bag = Entity(vehicle).state
  if (bag[BAG] == true) ~= locked then bag:set(BAG, locked or nil, true) end
end

function Registration.inspect(src)
  if mode() == 'off' then return nil end
  local p, seen = read(src)
  if Pure.regSkip(Config.registration, seen) then return nil end
  local character = p and p.character
  local account = Identity.getAccount(src)
  if not (account and character and character.ssn) then return nil end
  local plate = Pure.regPlate(seen.plate)
  local key = Pure.regKey(character.ssn, plate)
  local registered = Pure.regGet(state, key, now())
  if registered == nil then
    if state.pending[key] then return nil end
    state.pending[key] = true
    local ok, found = pcall(lookup, account, character.ssn, plate)
    state.pending[key] = nil
    if not ok or found == nil then
      Pure.regPut(state, key, true, now())
      return nil
    end
    registered = found
  end
  return { registered = registered, plate = plate, key = key, vehicle = seen.vehicle, name = Pure.clean(('%s %s'):format(character.firstName or '',
      character.lastName or ''), 64) or '?' }
end

local function locked(src, v)
  if Pure.regGrace(state, v.key, now(), Config.registration.grace) then
    setLock(v.vehicle, true)
    return true
  end
  SetTimeout(math.ceil((tonumber(Config.registration.grace) or 0) * 1000) + 500, function()
    local again = Registration.inspect(src)
    if again and not again.registered then locked(src, again) end
  end)
  return false
end

function Registration.refuse(src, name)
  if mode() ~= 'enforce' or not Pure.regGated(Config.registration, name) then return false end
  local v = Registration.inspect(src)
  if not v or v.registered or not locked(src, v) then return false end
  Notify.player(src, L('reg_blocked', Config.commands.regveh.name), 'error')
  return true
end

function Registration.registered(src)
  if mode() == 'off' then return end
  local p, seen = read(src)
  local character = p and p.character
  local plate = Pure.regPlate(seen.plate)
  if not (character and character.ssn and plate) then return end
  Pure.regPut(state, Pure.regKey(character.ssn, plate), true, now())
  setLock(seen.vehicle, false)
end

RegisterNetEvent('statewide:seat', function()
  local src = tonumber(source)
  if not src or src <= 0 or mode() == 'off' then return end
  if not Pure.regSignalReady(state, src, now(), SIGNAL_GAP) then return end
  local v = Registration.inspect(src)
  if not v then return end
  if v.registered then return setLock(v.vehicle, false) end
  if mode() == 'enforce' then locked(src, v) end
  if Pure.regFirstPrompt(state, v.key) then Notify.player(src, L('reg_prompt', Config.commands.regveh.name, v.name), 'info') end
end)

AddEventHandler('playerDropped', function()
  Pure.regDrop(state, tonumber(source))
end)

for _, action in ipairs({ 'regveh', 'regcarjack', 'regparkedveh' }) do
  local handler = Handlers[action]
  if handler then
    Handlers[action] = function(src, args, name)
      if handler(src, args, name) then Registration.registered(src) end
    end
  end
end

for _, name in ipairs(Config.registration.gated or {}) do
  if name ~= 'tablet' then
    local prev = Commands.free[name]
    Commands.free[name] = function(src)
      if prev and prev(src) then return true end
      return Registration.refuse(src, name)
    end
  end
end
