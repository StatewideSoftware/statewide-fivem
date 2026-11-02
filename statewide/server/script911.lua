local own = GetCurrentResourceName()
local cooldowns = {}
local refusals = {}

local function now()
  return GetGameTimer() / 1000
end

local function listed(resource)
  local cfg = Config.scriptCalls or {}
  for _, name in ipairs(cfg.allow or {}) do
    if name == resource then return true end
  end
  return false
end

local function refuse(resource, reason)
  if Pure.refusalThrottle(refusals, resource, reason, now(), 60) then
    print(('^3[statewide] create911 refused from %s: %s^7'):format(tostring(resource), reason))
  end
  return false, reason
end

local function reply(cb, result)
  if cb == nil then return end
  local ok, err = pcall(cb, result)
  if not ok then print(('^3[statewide] create911 callback error: %s^7'):format(tostring(err))) end
end

exports('create911', function(data, cb)
  local resource = GetInvokingResource()
  if not resource or resource == own or not listed(resource) then return refuse(resource or own, 'not_allowed') end
  local body, coords = Pure.buildScript911(data, resource)
  if not body then return refuse(resource, 'validation') end
  local cfg = Config.scriptCalls or {}
  if not Pure.useCooldown(cooldowns, resource, now(), cfg.cooldown or 60) then return refuse(resource, 'cooldown') end
  CreateThread(function()
    local res = Commands.post911(body)
    if res.status == 201 and res.data and res.data.number then
      local done, err = pcall(Commands.after911, nil, res, body.location, body.description, 'script', coords)
      if not done then print(('^3[statewide] create911 notify error: %s^7'):format(tostring(err))) end
      return reply(cb, { ok = true, callNumber = res.data.number })
    end
    local code = res.problem and res.problem.code or ('http_' .. tostring(res.status))
    refuse(resource, code)
    reply(cb, { ok = false, code = code })
  end)
  return true
end)
