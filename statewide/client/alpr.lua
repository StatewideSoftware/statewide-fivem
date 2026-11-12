local SOUNDS = {}
for _, name in pairs(Pure.ALPR_SOUNDS) do SOUNDS[name] = true end

RegisterNetEvent('statewide:client:alpr', function(alert)
  if type(alert) ~= 'table' or type(alert.text) ~= 'string' then return end
  Notify.show(alert.text, 'alert')
  if type(alert.sound) == 'string' and SOUNDS[alert.sound] then
    SendNUIMessage({ type = 'alpr:tone', sound = alert.sound })
  end
end)
