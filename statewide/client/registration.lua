local BAG = 'statewide:unregistered'

local function skipped(vehicle)
  local class = GetVehicleClass(vehicle)
  for _, c in ipairs(Config.registration.skipClasses or {}) do
    if c == class then return true end
  end
  return false
end

CreateThread(function()
  local last = 0
  while Pure.regMode(Config.registration) ~= 'off' do
    Wait(1000)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
      last = 0
    elseif vehicle ~= last and GetPedInVehicleSeat(vehicle, -1) == ped then
      last = vehicle
      if LocalPlayer.state['statewide:unit'] == nil and not skipped(vehicle) then TriggerServerEvent('statewide:seat') end
    end
  end
end)

local holding = {}

AddStateBagChangeHandler(BAG, nil, function(bagName, _, value)
  if value ~= true then return end
  local vehicle = GetEntityFromStateBagName(bagName)
  if not vehicle or vehicle == 0 or holding[vehicle] then return end
  holding[vehicle] = true
  CreateThread(function()
    while DoesEntityExist(vehicle) and Entity(vehicle).state[BAG] == true do
      if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() and GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
      Wait(500)
    end
    holding[vehicle] = nil
  end)
end)
