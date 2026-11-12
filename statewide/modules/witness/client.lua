local cfg = Config.witness
local LEAVE_MS = 3000

local seen = { weapon = 0, ammo = -1, vehicle = 0, body = 1000.0, speed = 0.0, fast = 0, off = 0, left = nil }

local function on(kind)
  return type(cfg[kind]) == 'table' and cfg[kind].enabled ~= false
end

local function shot(ped)
  local weapon = GetSelectedPedWeapon(ped)
  local ammo = GetAmmoInPedWeapon(ped, weapon)
  local fired = IsPedShooting(ped) or (weapon == seen.weapon and ammo < seen.ammo)
  seen.weapon, seen.ammo = weapon, ammo
  return on('shots') and fired and IsPedArmed(ped, 4) and 'shots' or nil
end

local function wrecked(veh)
  local w = cfg.wreck
  return GetVehicleEngineHealth(veh) <= w.engineHealth or GetVehicleBodyHealth(veh) <= w.bodyHealth
end

local function onRoad(veh)
  local c = GetEntityCoords(veh, false)
  return IsPointOnRoad(c.x, c.y, c.z, veh)
end

local function abandoned(ped)
  local l = seen.left
  if not l or GetGameTimer() < l.at then return nil end
  seen.left = nil
  if not on('wreck') or not DoesEntityExist(l.vehicle) or GetVehiclePedIsIn(ped, false) == l.vehicle then return nil end
  if GetPedInVehicleSeat(l.vehicle, -1) ~= 0 or not wrecked(l.vehicle) or not onRoad(l.vehicle) then return nil end
  return 'wreck'
end

local function driving(ped)
  local veh = GetVehiclePedIsIn(ped, false)
  if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return 0 end
  return veh
end

local function road(ped, interval)
  local veh = driving(ped)
  if veh == 0 then
    if seen.vehicle ~= 0 then seen.left = { vehicle = seen.vehicle, at = GetGameTimer() + LEAVE_MS } end
    seen.vehicle, seen.fast, seen.off = 0, 0, 0
    return abandoned(ped)
  end
  local speed, body = GetEntitySpeed(veh), GetVehicleBodyHealth(veh)
  local crashed = veh == seen.vehicle and seen.body - body >= cfg.crash.damage and seen.speed >= cfg.crash.minSpeed
  local r = cfg.reckless
  seen.fast = speed >= r.speed and seen.fast + interval or 0
  seen.off = (speed >= r.pavementSpeed and not onRoad(veh)) and seen.off + interval or 0
  seen.vehicle, seen.body, seen.speed = veh, body, speed
  if crashed and on('crash') then return 'crash' end
  if on('reckless') and (seen.fast >= r.seconds * 1000 or seen.off >= r.pavementSeconds * 1000) then
    seen.fast, seen.off = 0, 0
    return 'reckless'
  end
  return nil
end

local function tick(interval)
  local ped = PlayerPedId()
  if IsEntityDead(ped) then return end
  local fired = shot(ped)
  local kind = road(ped, interval)
  kind = fired or kind
  if kind then TriggerServerEvent('statewide:witness:hint', kind) end
end

CreateThread(function()
  if type(cfg) ~= 'table' or cfg.enabled ~= true then return end
  local interval = math.max(500, math.floor(tonumber(cfg.interval) or 500))
  while true do
    Wait(interval)
    tick(interval)
  end
end)
