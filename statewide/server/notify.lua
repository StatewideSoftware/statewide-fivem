Notify = {}

local function valid(src)
  src = tonumber(src)
  return src and src > 0 and src or nil
end

function Notify.player(src, text, kind)
  src = valid(src)
  if src then TriggerClientEvent('statewide:client:notify', src, text, kind or 'info') end
end

function Notify.push(src, name, payload)
  src = valid(src)
  if src then TriggerClientEvent('statewide:client:' .. name, src, payload) end
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
