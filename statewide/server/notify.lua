Notify = {}

local function valid(src)
  src = tonumber(src)
  return src and src > 0 and src or nil
end

local captures = {}

function Notify.player(src, text, kind)
  src = valid(src)
  if not src then return end
  local box = captures[coroutine.running()]
  if box and box.src == src then
    box[#box + 1] = { text = text, kind = kind or 'info' }
    return
  end
  TriggerClientEvent('statewide:client:notify', src, text, kind or 'info')
end

function Notify.capture(src, fn, ...)
  local co = coroutine.running()
  local box = { src = valid(src) }
  captures[co] = box
  local ok, data = pcall(fn, ...)
  captures[co] = nil
  if not ok then error(data, 0) end
  return box, data
end

local sinks = {}

function Notify.addSink(fn)
  sinks[#sinks + 1] = fn
end

function Notify.push(src, name, payload)
  src = valid(src)
  if not src then return end
  TriggerClientEvent('statewide:client:' .. name, src, payload)
  for i = 1, #sinks do
    local ok, err = pcall(sinks[i], src, name, payload)
    if not ok then print(('^1[statewide] notify sink: %s^7'):format(err)) end
  end
end

function Notify.problem(src, res)
  local problem = res and res.problem
  if problem and problem.code == 'on_duty' then
    State.refresh(src)
    if not Commands.civilian(src) then return end
  elseif problem and problem.code == 'unit_busy' then
    State.refresh(src)
    local p = State.peek(src)
    local number = p and p.unit and p.unit.callNumber
    if number then return Notify.player(src, L('err_unit_busy_call', number), 'error') end
  end
  Notify.player(src, Pure.problemMessage(problem, Locale), 'error')
end
