Lifecycle = { generation = 0 }

local function fromPlayer()
  local s = tonumber(source)
  return s ~= nil and s > 0
end

function Lifecycle.checkVersion()
  local res = api('GET', '/health', 'any')
  if res.status ~= 200 or not res.data then return end
  print(('[statewide] connected to %s (API v%s), resource %s'):format(res.data.community and res.data.community.name or '?', res.data.apiVersion or '?', Http.version))
  if Pure.versionLessThan(Http.version, res.data.minResourceVersion) then
    print(('^3[statewide] this resource (%s) is older than the oldest version the API supports (%s): update it.^7'):format(Http.version, res.data.minResourceVersion))
  end
end

function Lifecycle.reconcile()
  if SceneMarkers then SceneMarkers.load() end
  local connected, everyone = {}, {}
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    local account = Identity.getAccount(src)
    if account then
      everyone[#everyone + 1] = src
      if account.discordId then connected[account.discordId] = src end
      local p = State.get(src)
      if not Pure.sameAccount(p.account, account) then p.membershipId = nil end
      p.discordId, p.account = account.discordId, account
    end
  end
  local res = api('GET', '/units', 'units')
  if res.status ~= 200 or not res.data then return end
  State.noteUnits(res.data.units)
  for _, discordId in ipairs(Pure.staleGameUnits(res.data.units, connected, State.ours())) do
    local off = api('DELETE', '/units/duty/{discordId}', 'units', { params = { discordId = discordId }, query = { reason = 'game_drop' } })
    if off.status == 204 or (off.problem and off.problem.code == 'not_found') then State.release(discordId) end
  end
  local ranked = Pure.rankOrder(everyone, function(src)
    local p = State.peek(src)
    return State.joinRank(p and p.discordId)
  end)
  for _, src in ipairs(ranked) do
    State.refresh(src, 'low')
    Wait(100)
  end
  if CallHud then CallHud.refreshAll() end
end

function Lifecycle.start()
  Lifecycle.generation = Lifecycle.generation + 1
  local generation = Lifecycle.generation
  Commands.register()
  Events.start(generation)
  Locations.start(generation)
  Modules.start(generation)
  State.revalidate(generation)
  CreateThread(function()
    Lifecycle.checkVersion()
    Commands.loadCardTheme()
    Lifecycle.reconcile()
  end)
end

AddEventHandler('playerJoining', function()
  local src = tonumber(source)
  local token = State.join(src)
  local account = Identity.getAccount(src)
  local discordId = account and account.discordId
  Http.pace(function()
    if State.token(src) == token then State.refresh(src, 'low') end
  end, function()
    return State.joinRank(discordId)
  end)
end)

Lifecycle.SIGN_OFF_BATCH = 10
Lifecycle.SIGN_OFF_GAP_MS = 1000

AddEventHandler('txAdmin:events:serverShuttingDown', function()
  if fromPlayer() then return end
  local units = {}
  for src, p in pairs(State.all()) do
    local account = Pure.accountOfState(p)
    if p.unit and account then units[#units + 1] = { src = src, account = account } end
  end
  CreateThread(function()
    for i, batch in ipairs(Pure.chunk(units, Lifecycle.SIGN_OFF_BATCH)) do
      if i > 1 then Wait(Lifecycle.SIGN_OFF_GAP_MS) end
      for _, u in ipairs(batch) do
        CreateThread(function() Commands.offDuty(u.src, u.account, 'game_drop') end)
      end
    end
  end)
end)

Lifecycle.start()
