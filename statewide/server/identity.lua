Identity = {}

local players = {}
local hinted = {}

local function entry(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  local e = players[src]
  if not e then
    local ids = Pure.playerIds(GetPlayerIdentifiers(src))
    local candidates = Pure.accountOrder(Config.identity, ids)
    e = { ids = ids, candidates = candidates, account = candidates[1] }
    if Pure.identityKnown(ids) then players[src] = e end
  end
  return e
end

function Identity.getAccount(src)
  local e = entry(src)
  return e and e.account or nil
end

function Identity.discordOf(src)
  local a = Identity.getAccount(src)
  return a and a.discordId or nil
end

function Identity.resolve(src, lookup)
  local e = entry(src)
  if not e or #e.candidates == 0 then return nil end
  local account, res, resolved = Pure.pickAccount(e.candidates, lookup)
  e.account = account
  if resolved ~= nil then e.resolved = resolved end
  return res, account
end

function Identity.require(src)
  local a = Identity.getAccount(src)
  if not a then Notify.player(src, L('no_discord'), 'error') end
  return a
end

function Identity.forget(src)
  src = tonumber(src)
  players[src] = nil
  hinted[src] = nil
end

function Identity.joinMessage(src)
  local refusal = Pure.joinRefusal(Config.identity, GetPlayerIdentifiers(src))
  return refusal and L(refusal) or nil
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
  local src = source
  if not Pure.identityConfig(Config.identity).requireDiscord then return end
  deferrals.defer()
  Wait(0)
  local ok, message = pcall(Identity.joinMessage, src)
  if not ok then message = Locale.join_no_discord end
  deferrals.done(message)
end)

Identity.SPAWN_WAIT_S = 120

local function spawned(src)
  local ped = GetPlayerPed(src)
  return ped ~= nil and ped ~= 0 and DoesEntityExist(ped)
end

function Identity.hint(src)
  if hinted[src] then return end
  local e = entry(src)
  if not e then return end
  if e.resolved == nil and e.ids.discordId == nil and State then State.refresh(src, 'low') end
  if not Pure.needsLinkHint(Config.identity, Config.tablet.enabled, e.ids, e.resolved) then return end
  hinted[src] = true
  Notify.player(src, L('link_hint', Config.tablet.key), 'info')
end

AddEventHandler('playerJoining', function()
  local src = tonumber(source)
  entry(src)
  CreateThread(function()
    for _ = 1, Identity.SPAWN_WAIT_S do
      if not GetPlayerName(src) then return end
      if spawned(src) then return Identity.hint(src) end
      Wait(1000)
    end
  end)
end)
