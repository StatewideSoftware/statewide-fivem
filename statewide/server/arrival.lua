Arrival = {}

local targets = {}

function Arrival.attached(recipients, payload)
  local t = GetGameTimer() / 1000
  local push = Config.attach.waypoint and Pure.waypointPush(payload) or nil
  local target = Config.attach.onScene and Pure.arrivalTarget(payload, t) or nil
  for _, src in ipairs(recipients) do
    if push then TriggerClientEvent('statewide:client:waypoint', src, push) end
    targets[src] = target and State.copy(target) or nil
  end
end

local function arrive(src, target, account)
  CreateThread(function()
    local res = api('PATCH', '/units/{discordId}/status', 'units', {
      params = { discordId = Pure.playerSlot(account) },
      body = { meaning = 'on_scene', arrivedAt = target.callNumber },
      as = account,
      retry = false,
    })
    if targets[src] ~= target then return end
    if Pure.arrivalResult(target, res.status, GetGameTimer() / 1000) == 'done' then
      targets[src] = nil
      if res.status == 200 then Notify.player(src, L('push_on_scene', target.callNumber), 'success') end
    end
  end)
end

function Arrival.check()
  local t = GetGameTimer() / 1000
  for src, target in pairs(targets) do
    local p = State.peek(src)
    local unit = p and p.unit
    local step = Pure.arrivalStep(target, unit, unit and State.readCoords(src), t)
    if step == 'drop' then
      targets[src] = nil
    elseif step == 'fire' then
      local account = unit.discordId and { discordId = unit.discordId } or Pure.accountOfState(p)
      if account then
        target.pending = true
        arrive(src, target, account)
      else
        targets[src] = nil
      end
    end
  end
end

AddEventHandler('playerDropped', function()
  targets[tonumber(source)] = nil
end)
