local KVP = 'statewide:tablet:rect'
local KVP_SCALE = 'statewide:tablet:scale'
local isOpen, waiting, shown, escaping = false, false, false, false

local function savedRect()
  local raw = GetResourceKvpString(KVP)
  if not raw or raw == '' then return nil end
  local ok, r = pcall(json.decode, raw)
  if ok and Pure.validRect(r) then return r end
  return nil
end

local function savedScale()
  local s = GetResourceKvpFloat(KVP_SCALE)
  if Pure.validScale(s) then return s end
  return nil
end

local function close()
  isOpen, waiting = false, false
  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'close' })
end

local function vehicleOk()
  if not Config.tablet.vehicleOnly then return true end
  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then return false end
  return Pure.tabletVehicleAllowed(Config.tablet, GetVehicleClass(vehicle), GetEntityModel(vehicle), GetHashKey)
end

local function watchVehicle()
  CreateThread(function()
    while isOpen do
      Wait(500)
      if isOpen and not vehicleOk() then close() end
    end
  end)
end

local function watchEscape()
  if escaping then return end
  escaping = true
  CreateThread(function()
    while isOpen and not shown do
      DisableControlAction(0, 200, true)
      if IsDisabledControlJustReleased(0, 200) then close() end
      Wait(0)
    end
    escaping = false
  end)
end

local function open()
  if isOpen then return close() end
  if not vehicleOk() then return Notify.show(L('tablet_vehicle_only'), 'error') end
  isOpen, waiting, shown = true, false, false
  SetNuiFocus(true, true)
  SendNUIMessage({
    type = 'open',
    rect = savedRect(),
    scale = Config.tablet.scale,
    savedScale = savedScale(),
    key = Config.tablet.key,
    keepMinutes = Config.tablet.keepMinutes,
    labels = {
      title = L('tablet_title'),
      reset = L('tablet_reset'),
      close = L('tablet_close'),
      smaller = L('tablet_smaller'),
      larger = L('tablet_larger'),
      loading = L('tablet_loading'),
      timeoutTitle = L('tablet_err_frame_timeout'),
      timeoutNext = L('tablet_next_frame_timeout'),
    },
  })
  watchEscape()
  if Config.tablet.vehicleOnly then watchVehicle() end
end

local function errorNext(code)
  if code == 'not_on_duty' then return L('tablet_next_not_on_duty', Config.commands.duty.name) end
  return Locale['tablet_next_' .. code] or L('tablet_next_generic')
end

RegisterNetEvent('statewide:client:tablet', function(p)
  if type(p) ~= 'table' then return end
  if p.drop == true then return SendNUIMessage({ type = 'drop' }) end
  if not isOpen or not waiting then return end
  waiting = false
  local payload = Pure.tabletPayload({ url = p.url, tabletToken = p.token, linkCode = p.link })
  if payload then return SendNUIMessage({ type = 'url', url = payload.url, token = payload.token, link = payload.link }) end
  local code = type(p.error) == 'string' and p.error:match('^[%w_]+$') and p.error or 'error'
  SendNUIMessage({
    type = 'error',
    code = code,
    title = Locale['tablet_err_' .. code] or L('tablet_err_generic'),
    next = errorNext(code),
  })
end)

RegisterNUICallback('code', function(_, cb)
  cb({})
  if not isOpen then return end
  waiting, shown = true, false
  watchEscape()
  TriggerServerEvent('statewide:tablet')
end)

RegisterNUICallback('close', function(_, cb)
  close()
  cb({})
end)

RegisterNUICallback('shown', function(_, cb)
  shown = true
  cb({})
end)

RegisterNUICallback('rect', function(data, cb)
  if type(data) == 'table' and data.reset == true then
    DeleteResourceKvp(KVP)
    DeleteResourceKvp(KVP_SCALE)
  elseif Pure.validRect(data) then
    SetResourceKvp(KVP, json.encode({ x = math.floor(data.x), y = math.floor(data.y), w = math.floor(data.w), h = math.floor(data.h) }))
  end
  cb({})
end)

RegisterNUICallback('scale', function(data, cb)
  if type(data) == 'table' and Pure.validScale(data.scale) then SetResourceKvpFloat(KVP_SCALE, data.scale) end
  cb({})
end)

AddEventHandler('onResourceStop', function(name)
  if name == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)

if Config.tablet.enabled then
  RegisterCommand(Config.tablet.command, open, false)
  RegisterKeyMapping(Config.tablet.command, L('cmd_tablet'), 'keyboard', Config.tablet.key)
  CreateThread(function()
    Wait(1000)
    TriggerEvent('chat:addSuggestion', '/' .. Config.tablet.command, L('cmd_tablet'), {})
  end)
end
