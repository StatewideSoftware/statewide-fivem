Callers = {}

local open = {}

local function window()
  local cfg = Config.lbPhone
  return tonumber(cfg and cfg.callerWindowSeconds) or 600
end

local function clock()
  return GetGameTimer() / 1000
end

function Callers.find(key)
  local entry = key and open[key]
  if not entry then return nil end
  if Pure.callerWindowOpen(entry.at, clock(), window()) then return entry.number end
  open[key] = nil
  return nil
end

function Callers.open(key, number)
  if not key or type(number) ~= 'string' then return end
  open[key] = { number = number, at = clock() }
end

function Callers.clear(key)
  if key then open[key] = nil end
end

function Callers.touch(key)
  local entry = key and open[key]
  if entry then entry.at = clock() end
end

AddEventHandler('statewide:callClosed', function(payload)
  if type(payload) ~= 'table' or type(payload.number) ~= 'string' then return end
  for key, entry in pairs(open) do
    if entry.number == payload.number then open[key] = nil end
  end
end)
