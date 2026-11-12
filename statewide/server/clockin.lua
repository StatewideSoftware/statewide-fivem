ClockIn = {}

local clocked = {}

ClockIn.BATCH = 128

local function now()
  return GetGameTimer()
end

local function remember(src, account, department, via, signedOn)
  clocked[src] = { account = account, department = department, via = via, signedOn = signedOn, at = now() }
end

function ClockIn.get(src)
  return clocked[tonumber(src)]
end

function ClockIn.clockIn(src, department, via)
  local account = Identity.require(src)
  if not account then return nil end
  local res = api('POST', '/duty/clock-in', 'units', { body = Pure.withPlayer(account, { department = department }), as = account })
  if res.status ~= 200 or not res.data or type(res.data.clockIn) ~= 'table' then
    Notify.problem(src, res)
    return res
  end
  local ci = res.data.clockIn
  local abbreviation = ci.department and ci.department.abbreviation or department
  local held = clocked[src]
  remember(src, account, abbreviation, via, held ~= nil and held.signedOn or false)
  Notify.player(src, L(ci.opened == false and 'clockin_already' or 'clockin_on', abbreviation), 'success')
  local p = State.peek(src)
  if ci.signOn == true and not (p and p.unit) then
    local on = Commands.signOn(src, account, abbreviation)
    if on.status == 201 and clocked[src] then clocked[src].signedOn = true end
  end
  return res
end

function ClockIn.clockOut(src)
  local held = clocked[src]
  local account = held and held.account or Identity.require(src)
  if not account then return nil end
  local res = api('DELETE', '/duty/clock-in/{discordId}', 'units', { params = { discordId = Pure.playerSlot(account) }, as = account })
  local missing = res.problem and res.problem.code == 'not_found'
  if res.status == 204 or missing then clocked[src] = nil end
  if held and held.signedOn and Commands.sameAccount(src, account) then
    local p = State.peek(src)
    if p and p.unit then
      local off = Commands.offDuty(src, account, 'manual')
      if off.status == 204 and Ers then Ers.cadDuty(src, nil) end
    end
  end
  if res.status == 204 then
    Notify.player(src, L('clockin_off'), 'success')
  elseif missing then
    Notify.player(src, L('not_clocked_in'), 'error')
  else
    Notify.problem(src, res)
  end
  return res
end

Handlers.clockin = function(src, args)
  ClockIn.clockIn(src, Pure.clockInArgs(args), 'command')
end

Handlers.clockout = function(src)
  ClockIn.clockOut(src)
end

function ClockIn.report()
  local started = now()
  local players, slots = {}, {}
  for _, s in ipairs(GetPlayers()) do
    local src = tonumber(s)
    local account = src and Identity.getAccount(src)
    local item = account and Pure.playerItem(account)
    if item then
      players[#players + 1] = Pure.withPlayer(account, {})
      slots[item] = src
    end
  end
  if #players == 0 then return end
  local answered = {}
  for _, batch in ipairs(Pure.chunk(players, ClockIn.BATCH)) do
    local res = api('POST', '/duty/clock-ins/seen', 'units', { body = { players = batch }, retry = false })
    if res.status ~= 200 then return end
    for src, department in pairs(Pure.clockedIn(res.data, slots)) do answered[src] = department end
  end
  for src, department in pairs(answered) do
    local held = clocked[src]
    if held then
      held.department = department
    else
      remember(src, Identity.getAccount(src), department, 'report', false)
    end
  end
  for src, held in pairs(clocked) do
    if not answered[src] and held.at < started then clocked[src] = nil end
  end
end

function ClockIn.watch(generation)
  CreateThread(function()
    while Lifecycle.generation == generation do
      pcall(ClockIn.report)
      Wait(Pure.clockInReportSeconds(Config.clockIn) * 1000)
    end
  end)
end

local function frameworkJob(src)
  for _, name in ipairs({ 'qbx_core', 'qb-core' }) do
    if GetResourceState(name) == 'started' then
      local ok, player = pcall(function() return exports[name]:GetPlayer(src) end)
      local data = ok and type(player) == 'table' and player.PlayerData
      if type(data) == 'table' and type(data.job) == 'table' then return data.job end
    end
  end
  return nil
end

local function jobDuty(src, job, onDuty)
  if not Pure.CLOCK_IN_FRAMEWORKS[GetInvokingResource() or ''] then return end
  src = tonumber(src)
  if not src or src <= 0 or type(job) ~= 'table' then return end
  local department = Pure.frameworkDuty(Config.clockIn and Config.clockIn.jobs, job.name, onDuty)
  local held = clocked[src]
  if department then
    if held and held.department:upper() == department:upper() then return end
    CreateThread(function()
      if held then ClockIn.clockOut(src) end
      ClockIn.clockIn(src, department, 'framework')
    end)
  elseif held and held.via ~= 'command' then
    CreateThread(function() ClockIn.clockOut(src) end)
  end
end

AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
  jobDuty(src, frameworkJob(tonumber(src)), onDuty == true)
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
  jobDuty(src, job, type(job) == 'table' and job.onduty == true)
end)

AddEventHandler('esx:setJob', function(src, job)
  jobDuty(src, job, type(job) == 'table' and job.onDuty == true)
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  local held = src and clocked[src]
  if not held then return end
  clocked[src] = nil
  if not held.account then return end
  CreateThread(function()
    api('DELETE', '/duty/clock-in/{discordId}', 'units', { params = { discordId = Pure.playerSlot(held.account) }, as = held.account })
  end)
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
  local s = tonumber(source)
  if s ~= nil and s > 0 then return end
  local held = {}
  for _, h in pairs(clocked) do
    if h.account then held[#held + 1] = h.account end
  end
  CreateThread(function()
    for i, batch in ipairs(Pure.chunk(held, Lifecycle.SIGN_OFF_BATCH or 10)) do
      if i > 1 then Wait(Lifecycle.SIGN_OFF_GAP_MS or 1000) end
      for _, account in ipairs(batch) do
        CreateThread(function() api('DELETE', '/duty/clock-in/{discordId}', 'units', { params = { discordId = Pure.playerSlot(account) }, as = account }) end)
      end
    end
  end)
end)
