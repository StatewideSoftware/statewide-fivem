local card, closeAt = nil, 0

local function statusWord(status)
  return Locale['idcard_status_' .. tostring(status)] or status
end

local function hide()
  if not card then return end
  card = nil
  if Config.idCard.nui ~= false then SendNUIMessage({ type = 'idcard:hide' }) end
end

local function watch(payload)
  CreateThread(function()
    while card == payload do
      DisableControlAction(0, 200, true)
      local escapeHeld = IsDisabledControlPressed(0, 200)
      if GetGameTimer() >= closeAt and not escapeHeld then return hide() end
      if IsControlJustPressed(0, 174) or IsControlJustPressed(0, 175) then SendNUIMessage({ type = 'idcard:flip' }) end
      if IsDisabledControlJustReleased(0, 200) or IsControlJustPressed(0, 194) then
        hide()
        if payload.own then TriggerServerEvent('statewide:idcard') end
        return
      end
      Wait(0)
    end
  end)
end

local function chatCard(payload)
  local l = payload.license
  Notify.show(L('id_card', payload.name, payload.dob or '?'), 'info')
  Notify.show(L('id_license', l.name or '', l.number or '', statusWord(l.status) or ''), 'info')
end

local function show(payload)
  if Config.idCard.nui == false or type(payload.card) ~= 'table' then return chatCard(payload) end
  card, closeAt = payload, GetGameTimer() + Config.idCard.seconds * 1000
  SendNUIMessage({ type = 'idcard:show', card = payload.card, theme = payload.theme, handed = payload.own ~= true,
    hosts = Config.photoHosts, devHttp = Config.photoDevHttp == true,
  })
  watch(payload)
end

local function handOver()
  local dict = 'mp_common'
  RequestAnimDict(dict)
  local deadline = GetGameTimer() + 1000
  while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(10) end
  if HasAnimDictLoaded(dict) then
    TaskPlayAnim(PlayerPedId(), dict, 'givetake1_a', 8.0, -8.0, 1500, 48, 0.0, false, false, false)
    RemoveAnimDict(dict)
  end
end

RegisterNetEvent('statewide:client:idcard', function(payload)
  if type(payload) ~= 'table' or type(payload.name) ~= 'string' or type(payload.license) ~= 'table' then return end
  if payload.handover then CreateThread(handOver) end
  show(payload)
end)

RegisterNetEvent('statewide:client:idcardGiven', function()
  CreateThread(handOver)
end)

RegisterNetEvent('statewide:client:hideid', function(p)
  if type(p) == 'table' and card and card.from == p.from then hide() end
end)
