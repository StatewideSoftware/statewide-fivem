local lastOpen = {}

RegisterNetEvent('statewide:tablet', function()
  local src = tonumber(source)
  if not src or src <= 0 or not Config.tablet.enabled then return end
  local now = GetGameTimer() / 1000
  if not Pure.cooldown(lastOpen[src], now, Config.tablet.cooldown) then
    return TriggerClientEvent('statewide:client:tablet', src, { error = 'cooldown' })
  end
  lastOpen[src] = now
  local account = Identity.getAccount(src)
  if not account then return TriggerClientEvent('statewide:client:tablet', src, { error = 'no_discord' }) end
  CreateThread(function()
    local res = api('POST', '/tablet/code', 'tablet', { body = Pure.tabletCodeBody(account, Config.tablet, GetPlayerName(src)), as = account, retry = false })
    local payload = res.status == 201 and Pure.tabletPayload(res.data) or nil
    if payload then
      TriggerClientEvent('statewide:client:tablet', src, payload)
    else
      TriggerClientEvent('statewide:client:tablet', src, { error = Pure.tabletError(res) })
    end
  end)
end)

AddEventHandler('playerDropped', function()
  lastOpen[tonumber(source)] = nil
end)
