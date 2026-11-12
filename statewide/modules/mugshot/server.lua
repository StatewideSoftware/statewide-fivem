Mugshot = { pending = {}, STAGE_MS = 5000, CAPTURE_MS = 15000 }

local function settings()
  return Config.mugshot or {}
end

function Mugshot.mode()
  local c = settings()
  return Pure.mugshotMode(c.enabled, GetResourceState(c.resource or 'screenshot-basic'))
end

local function distance()
  return tonumber(settings().distance) or 3.0
end

function Mugshot.inReach(officer, suspect)
  return Pure.withinReach(State.readCoords(officer), State.readCoords(suspect), distance(), GetPlayerRoutingBucket(officer), GetPlayerRoutingBucket(suspect))
end

function Mugshot.suspect(src, target)
  if target.id then
    if target.id == src or not GetPlayerName(target.id) then return nil end
    return target.id
  end
  local others = {}
  for _, s in ipairs(GetPlayers()) do
    local other = tonumber(s)
    if other ~= src then others[#others + 1] = { src = other, coords = State.readCoords(other), bucket = GetPlayerRoutingBucket(other) } end
  end
  return Pure.nearestPlayer(State.readCoords(src), others, distance(), GetPlayerRoutingBucket(src))
end

local function waitFor(entry, key, ms)
  local stop = GetGameTimer() + ms
  while entry[key] == nil and GetGameTimer() < stop do Wait(50) end
  return entry[key]
end

function Mugshot.capture(asked, suspect)
  local token = Pure.newServerId(math.random)
  local entry = { src = asked }
  Mugshot.pending[token] = entry
  TriggerClientEvent('statewide:client:mugshot', asked, { token = token, target = suspect })
  local image
  if waitFor(entry, 'ready', Mugshot.STAGE_MS) == true then
    local ok = pcall(function()
      exports[settings().resource or 'screenshot-basic']:requestClientScreenshot(asked, { encoding = 'jpg', quality = Pure.mugshotQuality(settings().quality) }, function(err, data)
        entry.image = (not err and type(data) == 'string') and data or false
      end)
    end)
    if ok then image = waitFor(entry, 'image', Mugshot.CAPTURE_MS) end
  end
  Mugshot.pending[token] = nil
  TriggerClientEvent('statewide:client:mugshotDone', asked, token)
  return image or nil
end

RegisterNetEvent('statewide:mugshot', function(p)
  local src = tonumber(source)
  if not src or src <= 0 or type(p) ~= 'table' or type(p.token) ~= 'string' then return end
  local entry = Mugshot.pending[p.token]
  if not entry or entry.src ~= src or entry.ready ~= nil then return end
  entry.ready = p.ready == true
end)

local function tooFar(src)
  Notify.player(src, L('mugshot_too_far', distance()), 'error')
end

local function book(src, args, name)
  if Mugshot.mode() ~= 'on' then return Notify.player(src, L('mugshot_off'), 'error') end
  local target = Pure.mugshotTarget(args[1])
  if not target then return Commands.usage(src, 'mugshot', name) end
  if target.id == src then return Notify.player(src, L('mugshot_self'), 'error') end
  local account = Identity.require(src)
  if not account then return end
  if not Commands.requireUnit(src) then return end
  if not Commands.cooldown(src, 'mugshot') then return end
  local suspect = Mugshot.suspect(src, target)
  if not suspect then return Notify.player(src, L('mugshot_none_near', distance()), 'error') end
  if not Mugshot.inReach(src, suspect) then return tooFar(src) end
  local suspectAccount = Identity.getAccount(suspect)
  if not suspectAccount then return Notify.player(src, L('mugshot_no_account'), 'error') end
  local body = Pure.withPlayer(account, { suspect = Pure.playerItem(suspectAccount), ssn = target.ssn })
  local res = api('POST', '/mugshots/tickets', 'lookup', { body = body, as = account, retry = false })
  if res.status ~= 201 or type(res.data) ~= 'table' or type(res.data.character) ~= 'table' then return Notify.problem(src, res) end
  local ticket, character = res.data.ticket, res.data.character
  local who = Pure.truncate(character.name or '?', 64)
  Notify.player(src, L('mugshot_taking', who), 'info')
  local image
  for _, side in ipairs(Pure.mugshotOrder(settings().client)) do
    if not Mugshot.inReach(src, suspect) then return tooFar(src) end
    image = Pure.mugshotImage(Mugshot.capture(side == 'suspect' and suspect or src, suspect), Pure.MUGSHOT_MAX_BASE64)
    if image then break end
  end
  if not image then return Notify.player(src, L('mugshot_failed'), 'error') end
  local upload = Pure.withPlayer(account, { ticket = ticket, characterId = character.id, image = image })
  local up = api('POST', '/mugshots', 'lookup', { body = upload, as = account, retry = false, deadline = 30 })
  if up.status ~= 200 or type(up.data) ~= 'table' then return Notify.problem(src, up) end
  if type(up.data.arrest) == 'table' then return Notify.player(src, L('mugshot_done_arrest', who), 'success') end
  Notify.player(src, L('mugshot_done', who), 'success')
end

if settings().enabled ~= false and settings().enabled ~= 'off' then Handlers.mugshot = book end
