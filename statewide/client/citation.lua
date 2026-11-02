local open = nil

local function close()
  if not open then return end
  open = nil
  SetNuiFocus(false, false)
  SendNUIMessage({ type = 'citation:hide' })
end

RegisterNetEvent('statewide:client:citation', function(p)
  if type(p) ~= 'table' or type(p.citation) ~= 'table' or not Pure.isRecordId(p.citation.id) then return end
  open = p.citation.id
  SetNuiFocus(true, true)
  SendNUIMessage({ type = 'citation:show', citation = p.citation, total = p.total, labels = p.labels, canSign = p.canSign == true })
end)

RegisterNetEvent('statewide:client:citationHide', close)

RegisterNetEvent('statewide:client:citationIdle', function()
  if open then SendNUIMessage({ type = 'citation:idle' }) end
end)

RegisterNUICallback('citation', function(data, cb)
  cb({})
  if type(data) ~= 'table' or not open or data.id ~= open then return end
  local action = Pure.citationAction(data)
  if not action then return end
  if action.kind == 'close' then close() end
  TriggerServerEvent('statewide:citation', { action = action.kind, id = action.id, signature = action.signature })
end)
