Notify = {}

local colors = { info = Config.chat.color, success = { 69, 165, 87 }, error = { 229, 72, 77 }, alert = { 247, 107, 21 } }

function Notify.show(text, kind)
  TriggerEvent('chat:addMessage', { color = colors[kind] or colors.info, args = { Config.chat.prefix, Pure.chatText(text) } })
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(Pure.feedText(text))
  EndTextCommandThefeedPostTicker(kind == 'alert', true)
end

RegisterNetEvent('statewide:client:notify', function(text, kind)
  if type(text) ~= 'string' then return end
  Notify.show(text, kind)
end)
