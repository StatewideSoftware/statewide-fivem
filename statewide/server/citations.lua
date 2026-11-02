Citations = {}

local offers = {}
local busy = {}
local last = {}
local asks = {}

local function now()
  return GetGameTimer() / 1000
end

local function enabled()
  return Config.citation ~= nil and Config.citation.enabled ~= false
end

local function labels()
  return {
    title = L('citation_title'), sign = L('citation_sign'), keep = L('citation_keep'), close = L('citation_close'),
    name = L('citation_name'), note = L('citation_note'), fine = L('citation_fine'), points = L('citation_points'),
    jail = L('citation_jail'), officer = L('citation_officer'), location = L('citation_location'),
    person = L('citation_person'), date = L('citation_date'),
  }
end

local function show(src, offer)
  local c = offer.list[1]
  if not c then
    offers[src] = nil
    return Notify.push(src, 'citationHide', {})
  end
  Notify.push(src, 'citation', { citation = c, total = #offer.list, labels = labels(), canSign = true })
end

local function drop(offer, id)
  for i, c in ipairs(offer.list) do
    if c.id == id then return table.remove(offer.list, i) end
  end
  return nil
end

local function find(offer, id)
  for _, c in ipairs(offer.list) do
    if c.id == id then return c end
  end
  return nil
end

local function handedFirst(list, handed)
  if type(handed) ~= 'table' then return nil end
  for i, c in ipairs(list) do
    if c.id == handed.recordId then
      table.remove(list, i)
      table.insert(list, 1, c)
      return c.number
    end
  end
  return Pure.clean(handed.number, 30)
end

function Citations.offer(src, how, handed)
  local quiet = how ~= 'command'
  src = tonumber(src)
  if not src or not enabled() then return end
  local account = Identity.getAccount(src)
  if not account then
    if not quiet then Notify.player(src, L('no_discord'), 'error') end
    return
  end
  local ask = (asks[src] or 0) + 1
  asks[src] = ask
  local res = api('GET', '/citations', 'civilian', { query = { discordId = Pure.playerSlot(account) }, as = account })
  if not GetPlayerName(src) or asks[src] ~= ask then return end
  if res.status ~= 200 or not res.data then
    if not quiet then Notify.problem(src, res) end
    return
  end
  local list = Pure.citationList(res.data.citations)
  if #list == 0 then
    offers[src] = nil
    Notify.push(src, 'citationHide', {})
    if not quiet then Notify.player(src, L('citation_none'), 'info') end
    return
  end
  local number = handedFirst(list, handed)
  local offer = { account = account, list = list }
  offers[src] = offer
  if how == 'push' then Notify.player(src, L('citation_handed', number or list[1].number or ''), 'info') end
  show(src, offer)
end

local function inventory()
  local cfg = Config.citation
  if type(cfg.item) ~= 'string' or cfg.item == '' or type(cfg.inventory) ~= 'string' then return nil end
  if GetResourceState(cfg.inventory) ~= 'started' then return nil end
  return cfg.inventory
end

local function refuse(src, res)
  Notify.problem(src, res)
  if res.problem and (res.problem.code == 'citation_refused' or res.problem.code == 'not_found') then return Citations.offer(src, 'again') end
  Notify.push(src, 'citationIdle', {})
end

local function keep(src, offer, c)
  local inv = inventory()
  local item = Pure.citationItem(c, L('citation_item', c.number or ''))
  if inv then
    local ok, can = pcall(function() return exports[inv]:CanCarryItem(src, Config.citation.item, 1, item) end)
    if not ok or not can then
      Notify.push(src, 'citationIdle', {})
      return Notify.player(src, L('citation_full'), 'error')
    end
  end
  local res = api('POST', '/citations/keep', 'civilian', { body = Pure.withPlayer(offer.account, { recordId = c.id }), as = offer.account })
  if res.status ~= 200 then return refuse(src, res) end
  drop(offer, c.id)
  if inv then
    local ok, added, reason = pcall(function() return exports[inv]:AddItem(src, Config.citation.item, 1, item) end)
    if not ok or not added then print(('^3[statewide] citation item for %s not added: %s^7'):format(src, tostring(ok and reason or added))) end
  end
  TriggerEvent('statewide:citationKept', src, State.copy(item))
  Notify.player(src, L('citation_kept', c.number or ''), 'success')
  show(src, offer)
end

local function sign(src, offer, c, action)
  local body = Pure.withPlayer(offer.account, { recordId = c.id, signature = action.signature, version = c.version })
  local res = api('POST', '/citations/sign', 'civilian', { body = body, as = offer.account })
  if res.status ~= 200 then return refuse(src, res) end
  drop(offer, c.id)
  TriggerEvent('statewide:citationSigned', src, { citation = c.id, number = c.number })
  Notify.player(src, L('citation_signed', c.number or ''), 'success')
  show(src, offer)
end

local function decline(src, offer, c)
  drop(offer, c.id)
  Notify.player(src, L('citation_declined', c.number or '', Config.commands.citations.name), 'info')
  show(src, offer)
end

local ACTIONS = { sign = sign, keep = keep, close = decline }

Handlers.citations = function(src)
  Citations.offer(src, 'command')
end

RegisterNetEvent('statewide:citation', function(data)
  local src = tonumber(source)
  if not src or src <= 0 or not enabled() then return end
  local action = Pure.citationAction(data)
  if not action then return end
  local offer = offers[src]
  local c = offer and find(offer, action.id)
  if not c then return Notify.push(src, 'citationHide', {}) end
  if busy[src] then return end
  if not Pure.useCooldown(last, src, now(), Config.citation.cooldown or 2) then return end
  if not Commands.sameAccount(src, offer.account) then
    offers[src] = nil
    return Notify.push(src, 'citationHide', {})
  end
  busy[src] = true
  CreateThread(function()
    local ok, err = pcall(ACTIONS[action.kind], src, offer, c, action)
    busy[src] = nil
    if not ok then print(('^1[statewide] citation %s: %s^7'):format(action.kind, err)) end
  end)
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  offers[src], busy[src], last[src], asks[src] = nil, nil, nil, nil
end)
