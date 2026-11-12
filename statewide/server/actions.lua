Actions = {}

function Actions.duty(src, department, callsign)
  local account = Identity.require(src)
  if not account then return nil end
  local res = Commands.signOn(src, account, department, callsign)
  return res.status == 201 and res.data.unit or nil
end

function Actions.status(src, code)
  local account = Identity.require(src)
  if not account then return nil end
  local res = api('PATCH', '/units/{discordId}/status', 'units', { params = { discordId = Pure.playerSlot(account) }, body = { code = code }, as = account })
  if res.status ~= 200 then
    if res.problem and res.problem.code == 'validation_failed' and res.problem.detail then
      return Notify.player(src, L('status_unknown', res.problem.detail), 'error')
    end
    return Notify.problem(src, res)
  end
  State.setUnit(src, res.data.unit)
  Notify.player(src, L('status_set', res.data.unit.status.code), 'success')
  return res.data.unit
end

function Actions.panic(src, action)
  local account = Identity.require(src)
  if not account then return nil end
  local p = State.peek(src)
  if p and p.unit and (p.unit.isPanic or action == 'clearpanic') then
    State.refresh(src)
    p = State.peek(src)
  end
  local what = Pure.panicAction(p and p.unit, action)
  if what == 'off_duty' then return Notify.player(src, L('not_on_duty'), 'error') end
  if what == 'none' then return Notify.player(src, L('panic_none'), 'info') end
  if what == 'clear' then return Commands.setPanic(src, account, false) end
  if not Commands.cooldown(src, 'panic') then return nil end
  return Commands.setPanic(src, account, true)
end

function Actions.plate(src, plate)
  local account = Identity.require(src)
  if not account or not Commands.cooldown(src, 'plate') then return nil end
  local res = api('GET', '/lookup/vehicle', 'lookup', { query = { discordId = Pure.playerSlot(account), plate = plate }, as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  local first = res.data.results and res.data.results[1]
  if not first then return Notify.player(src, L('plate_none'), 'info') end
  Commands.showVehicle(src, first)
  return first
end

function Actions.name(src, first, last)
  local account = Identity.require(src)
  if not account or not Commands.cooldown(src, 'name') then return nil end
  local res = api('GET', '/lookup/person', 'lookup', { query = { discordId = Pure.playerSlot(account), first = first, last = last }, as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  if not res.data.results or #res.data.results == 0 then return Notify.player(src, L('name_none'), 'info') end
  Notify.player(src, L('name_return', res.data.summary), res.data.hit and 'alert' or 'info')
  return res.data
end

function Actions.setciv(src, ssn)
  if not Commands.civilian(src) then return nil end
  local account = Identity.require(src)
  if not account then return nil end
  local res = api('PUT', '/characters/active', 'civilian', { body = Pure.withPlayer(account, { ssn = ssn }), as = account })
  if res.status ~= 200 then return Notify.problem(src, res) end
  local c = res.data.character
  State.setCharacter(src, { id = c.id, ssn = c.ssn, firstName = c.firstName, lastName = c.lastName, dob = c.dob })
  Notify.player(src, L('setciv_done', c.firstName, c.lastName), 'success')
  return c
end
