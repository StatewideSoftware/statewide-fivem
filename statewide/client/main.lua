local lastSent

local function postal()
  local res = Config.postalResource
  if not res or GetResourceState(res) ~= 'started' then return nil end
  local ok, value = pcall(function() return exports[res]:getPostal() end)
  if ok and (type(value) == 'string' or type(value) == 'number') then return tostring(value) end
  return nil
end

local function labels()
  local c = GetEntityCoords(PlayerPedId())
  local streetHash, crossHash = GetStreetNameAtCoord(c.x, c.y, c.z)
  local street = GetStreetNameFromHashKey(streetHash)
  local cross = crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or nil
  return street, cross, postal(), GetNameOfZone(c.x, c.y, c.z)
end

local labelsRunning = false

local function onDuty()
  return LocalPlayer.state['statewide:unit'] ~= nil
end

local function sendLabels()
  local street, cross, code, zone = labels()
  local key = ('%s|%s|%s|%s'):format(street or '', cross or '', code or '', zone or '')
  if key == lastSent then return end
  lastSent = key
  TriggerServerEvent('statewide:labels', street, cross, code, zone)
end

local function watchLabels()
  if labelsRunning then return end
  labelsRunning = true
  CreateThread(function()
    repeat
      Wait(Config.labels.minSeconds * 1000)
      if onDuty() then sendLabels() end
    until not onDuty()
    labelsRunning = false
    lastSent = nil
  end)
end

AddStateBagChangeHandler('statewide:unit', nil, function(bagName, _, value)
  if value ~= nil and bagName == ('player:%d'):format(GetPlayerServerId(PlayerId())) then watchLabels() end
end)

RegisterNetEvent('statewide:client:labelsAt', function(token, x, y, z)
  if type(token) ~= 'number' or not Pure.validCoords({ x = x, y = y, z = z }) then return end
  local streetHash, crossHash = GetStreetNameAtCoord(x + 0.0, y + 0.0, (z or 0.0) + 0.0)
  local street = GetStreetNameFromHashKey(streetHash)
  local cross = crossHash ~= 0 and GetStreetNameFromHashKey(crossHash) or nil
  TriggerServerEvent('statewide:labelsAt', token, street, cross, GetNameOfZone(x + 0.0, y + 0.0, (z or 0.0) + 0.0))
end)

RegisterNetEvent('statewide:client:labels', function()
  local street, cross, code, zone = labels()
  lastSent = ('%s|%s|%s|%s'):format(street or '', cross or '', code or '', zone or '')
  TriggerServerEvent('statewide:labels', street, cross, code, zone)
end)

CreateThread(function()
  Wait(1000)
  if onDuty() then watchLabels() end
end)

CreateThread(function()
  Wait(1000)
  local resolved = Pure.resolveCommands(Config.commands)
  if not resolved then return end
  for _, c in ipairs(resolved) do
    local params = {}
    for p in (Locale['cmd_' .. c.action .. '_params'] or ''):gmatch('%S+') do params[#params + 1] = { name = p, help = p } end
    for _, name in ipairs(c.names) do
      TriggerEvent('chat:addSuggestion', '/' .. name, Locale['cmd_' .. c.action] or '', params)
    end
  end
end)

local function callBlip(p)
  local blip = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z or 0.0)
  SetBlipSprite(blip, 280)
  SetBlipColour(blip, 1)
  SetBlipScale(blip, 1.0)
  SetBlipFlashes(blip, true)
  SetBlipAsShortRange(blip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName('911 ' .. tostring(p.number or ''))
  EndTextCommandSetBlipName(blip)
  SetTimeout(Config.blips.seconds * 1000, function()
    if DoesBlipExist(blip) then RemoveBlip(blip) end
  end)
end

RegisterNetEvent('statewide:client:911', function(p)
  if type(p) ~= 'table' then return end
  Notify.show(L('push_911', Pure.push911Detail(p)), 'alert')
  if Config.blips.call911 and Pure.validCoords(p.coords) then callBlip(p) end
end)

RegisterNetEvent('statewide:client:311', function(p)
  if type(p) ~= 'table' then return end
  Notify.show(L('push_311', Pure.push911Detail(p)), 'info')
end)

RegisterNetEvent('statewide:client:panic', function(p)
  if type(p) ~= 'table' then return end
  if p.masked then return Notify.show(L('push_panic_masked', Pure.maskedPanicDetail(p, L('push_unit'))), 'alert') end
  Notify.show(L('push_panic', Pure.panicDetail(p)), 'alert')
end)

local units = {}
local unitState = {}

RegisterNetEvent('statewide:client:units', function(msg)
  local list = Pure.applyUnits(unitState, msg)
  if not list then return TriggerServerEvent('statewide:unitsSync') end
  units = list
  TriggerEvent('statewide:units', list)
end)

exports('getUnits', function()
  return units
end)

RegisterNetEvent('statewide:client:attached', function(p)
  if type(p) ~= 'table' then return end
  Notify.show(L('push_attached', Pure.attachedDetail(p)), 'info')
end)

RegisterNetEvent('statewide:client:waypoint', function(p)
  if type(p) ~= 'table' or not Pure.validCoords(p) then return end
  SetNewWaypoint(p.x + 0.0, p.y + 0.0)
  Notify.show(L('push_waypoint', type(p.label) == 'string' and p.label:sub(1, 40) or ''), 'info')
end)

RegisterNetEvent('statewide:client:callClosed', function(p)
  if type(p) ~= 'table' then return end
  local key, args = Pure.closedLine(p)
  Notify.show(L(key, table.unpack(args)), 'info')
end)

RegisterNetEvent('statewide:client:forcedOff', function(p)
  if type(p) ~= 'table' then return end
  Notify.show(L('push_forced_off', p.by or 'dispatch'), 'alert')
end)

RegisterNetEvent('statewide:client:vehicleInfo', function()
  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if not vehicle or vehicle == 0 then return TriggerServerEvent('statewide:vehicle') end
  local model = GetEntityModel(vehicle)
  local make = GetMakeNameFromVehicleModel(model)
  local display = GetDisplayNameFromVehicleModel(model)
  TriggerServerEvent('statewide:vehicle', Pure.vehicleLabel(make, GetLabelText(make)), Pure.vehicleLabel(display, GetLabelText(display)), display)
end)
