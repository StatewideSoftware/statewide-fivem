local GIVE_SECONDS = 10
local gives = {}
local theme

function Commands.loadCardTheme()
  local res = api('GET', '/community/card-theme', 'civilian')
  if res.status == 200 and res.data then theme = Pure.cardTheme(res.data.theme, Config.photoHosts, Config.photoDevHttp == true) end
  return theme
end

local function now()
  return GetGameTimer() / 1000
end

local function out(src)
  local s = Commands.shown[src]
  if s and now() - s.at < Config.idCard.seconds then return s end
  Commands.shown[src] = nil
  return nil
end

local function remember(src, target)
  local s = out(src) or { targets = {} }
  s.at = now()
  if target then
    local known = false
    for _, t in ipairs(s.targets) do known = known or t == target end
    if not known then s.targets[#s.targets + 1] = target end
  end
  Commands.shown[src] = s
end

local function takeBack(src)
  local s = Commands.shown[src]
  Notify.push(src, 'hideid', { from = src })
  for _, target in ipairs(s and s.targets or {}) do Notify.push(target, 'hideid', { from = src }) end
  Commands.shown[src] = nil
end

local function nearest(src)
  local others = {}
  for _, s in ipairs(GetPlayers()) do
    local other = tonumber(s)
    if other ~= src then others[#others + 1] = { src = other, coords = State.readCoords(other), bucket = GetPlayerRoutingBucket(other) } end
  end
  return Pure.nearestPlayer(State.readCoords(src), others, Config.idCard.distance, GetPlayerRoutingBucket(src))
end

local function typeLabel(wanted)
  if wanted:lower() == 'driver' then return wanted:lower() end
  return wanted:upper()
end

local function cardFor(src, arg)
  local account = Identity.require(src)
  if not account then return nil end
  local c = Commands.activeCharacter(src)
  if not c then return Notify.player(src, L('id_none'), 'error') end
  local wanted = Pure.clean(arg, 20) or Config.idCard.defaultType or 'driver'
  local res = api('GET', '/characters/{ssn}/id-card', 'civilian', { params = { ssn = c.ssn }, query = { discordId = Pure.playerSlot(account) }, as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  local license = Pure.pickLicense(res.data.licenses, wanted)
  if not license then return Notify.player(src, L('id_no_license', typeLabel(wanted)), 'error') end
  local payload = Pure.idCardPayload(res.data, license, Config.photoHosts, Config.photoDevHttp == true)
  payload.from = src
  payload.theme = theme or Commands.loadCardTheme()
  return payload
end

Handlers.id = function(src, args)
  if out(src) then return takeBack(src) end
  local payload = cardFor(src, args[1])
  if not payload then return end
  local target = Config.idCard.handover and nearest(src) or nil
  payload.own, payload.handover = true, target ~= nil
  Notify.push(src, 'idcard', payload)
  if target then
    payload.own, payload.handover = nil, nil
    Notify.push(target, 'idcard', payload)
  end
  remember(src, target)
end

local function throttled(src, target, use)
  local key = src .. ':' .. target
  local ok, left
  if use then ok, left = Pure.useCooldown(gives, key, now(), GIVE_SECONDS) else ok, left = Pure.cooldown(gives[key], now(), GIVE_SECONDS) end
  if not ok then Notify.player(src, L('cooldown', left), 'error') end
  return not ok
end

Handlers.giveid = function(src, args)
  local first = nearest(src)
  if not first then return Notify.player(src, L('id_nobody'), 'error') end
  if throttled(src, first) then return end
  local payload = cardFor(src, args[1])
  if not payload then return end
  local target = nearest(src)
  if not target then return Notify.player(src, L('id_nobody'), 'error') end
  if throttled(src, target, true) then return end
  Notify.push(target, 'idcard', payload)
  Notify.push(src, 'idcardGiven', {})
  Notify.player(src, L('id_given', Pure.clean(GetPlayerName(target), 32) or tostring(target)), 'success')
  remember(src, target)
end

Handlers.hideid = function(src)
  takeBack(src)
end

local function closeCard(src)
  if not out(src) then return false end
  takeBack(src)
  return true
end

Commands.free.id = closeCard
Commands.free.hideid = closeCard

RegisterNetEvent('statewide:idcard', function()
  local src = tonumber(source)
  local s = src and Commands.shown[src]
  if s and #s.targets == 0 then Commands.shown[src] = nil end
end)

AddEventHandler('playerDropped', function()
  local src = tostring(source)
  for key in pairs(gives) do
    local giver, target = key:match('^(%d+):(%d+)$')
    if giver == src or target == src then gives[key] = nil end
  end
end)
