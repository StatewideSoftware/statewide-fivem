local cfg = Config.phoneApp or {}
local LB = Config.lbPhone and Config.lbPhone.resource or 'lb-phone'
local IDENTIFIER = 'statewide'
local RESOURCE = GetCurrentResourceName()
local APP_SIZE_KB = 120
local REGISTER_DELAY_MS = 500
local TIMEOUT_MS = 10000
local PENDING_MAX = 4
local ID_MAX = 2147483647
local nextId, open = 0, 0
local pending = {}

local function lbCall(name, ...)
  local ok, a, b = pcall(function(...)
    local res = exports[LB]
    return res[name](res, ...)
  end, ...)
  if not ok then return false, nil, a end
  return true, a, b
end

local function settle(id, result)
  local cb = pending[id]
  if not cb then return end
  pending[id] = nil
  open = open - 1
  cb(result)
end

local function dropPending()
  for id in pairs(pending) do settle(id, { ok = false, messages = { { text = L('phone_timeout'), kind = 'error' } } }) end
end

local function addApp()
  if GetResourceState(LB) ~= 'started' then return end
  local called, added, err = lbCall('AddCustomApp', {
    identifier = IDENTIFIER,
    name = L('phone_app_name'),
    description = L('phone_app_description'),
    developer = 'Statewide',
    defaultApp = cfg.defaultApp ~= false,
    size = APP_SIZE_KB,
    images = {},
    ui = RESOURCE .. '/modules/phoneapp/ui/index.html',
    icon = 'https://cfx-nui-' .. RESOURCE .. '/modules/phoneapp/ui/icon.png',
    fixBlur = true,
    onClose = dropPending,
  })
  if not called or added == false then print(L('phoneapp_add_failed', tostring(err))) end
end

local function addLater()
  CreateThread(function()
    Wait(REGISTER_DELAY_MS)
    addApp()
  end)
end

if (Config.modules or {}).phoneapp ~= false and (Config.modules or {}).phoneapp ~= 'off' then
  if GetResourceState(LB) == 'started' then addLater() end

  AddEventHandler('onResourceStart', function(name)
    if name == LB then addLater() end
  end)

  AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE and GetResourceState(LB) == 'started' then lbCall('RemoveCustomApp', IDENTIFIER) end
  end)

  RegisterNUICallback('phoneBoot', function(_, cb)
    cb({ lb = LB })
  end)

  RegisterNUICallback('phone', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false, messages = { { text = L('phone_bad_args'), kind = 'error' } } }) end
    local args, why = Pure.validatePhoneAction(data.action, data.args)
    if args and not why.urgent and open >= PENDING_MAX then return cb({ ok = false, messages = { { text = L('busy'), kind = 'error' } } }) end
    if not args then return cb({ ok = false, messages = { { text = L(why == 'unknown_action' and 'phone_unknown' or 'phone_bad_args'), kind = 'error' } } }) end
    nextId = nextId % ID_MAX + 1
    local id = nextId
    pending[id] = cb
    open = open + 1
    TriggerServerEvent('statewide:phone', { id = id, action = data.action, args = args })
    SetTimeout(TIMEOUT_MS, function()
      settle(id, { ok = false, messages = { { text = L('phone_timeout'), kind = 'error' } } })
    end)
  end)

  RegisterNetEvent('statewide:client:phone', function(id, result)
    if type(result) ~= 'table' then return end
    settle(id, result)
  end)

  RegisterNetEvent('statewide:client:phonePush', function(data)
    if type(data) ~= 'table' or GetResourceState(LB) ~= 'started' then return end
    lbCall('SendCustomAppMessage', IDENTIFIER, data)
  end)
end
