local Status = {}

local INTERVAL_MS = 60000

local function beat(online)
  local players = online and #GetPlayers() or 0
  return api('PUT', '/server/status', 'units', { body = Pure.heartbeatPayload(players, GetConvarInt('sv_maxclients', 48), online), retry = false })
end

function Status.start(generation)
  if not Config.serverStatus then return end
  CreateThread(function()
    while Lifecycle.generation == generation do
      local res = beat(true)
      if res.problem and res.problem.code == 'scope_denied' then return end
      Wait(INTERVAL_MS)
    end
  end)
end

AddEventHandler('txAdmin:events:serverShuttingDown', function()
  local s = tonumber(source)
  if not Config.serverStatus or (s ~= nil and s > 0) then return end
  CreateThread(function() beat(false) end)
end)

Status.start(Lifecycle.generation)
