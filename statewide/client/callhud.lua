local COMMANDS = { prev = 'callhud_prev', next = 'callhud_next', attach = 'callhud_attach', details = 'callhud_details' }
local list, index, details, changedAt = {}, nil, false, 0

local function keyOf(action)
  local raw = GetControlInstructionalButton(0, GetHashKey(COMMANDS[action]) | 0x80000000, true)
  return Pure.keyLabel(raw, Config.callHud.keys[action])
end

local function render()
  local view = Pure.hudView(list, index)
  if not view then return SendNUIMessage({ type = 'callhud:hide' }) end
  SendNUIMessage({
    type = 'callhud:show',
    view = view,
    details = details,
    keys = { prev = keyOf('prev'), next = keyOf('next'), attach = keyOf('attach'), details = keyOf('details') },
    labels = {
      title = L('callhud_title'),
      attach = L('callhud_attach'),
      attached = L('callhud_attached'),
      details = L('callhud_details'),
      units = L('callhud_units'),
    },
  })
end

RegisterNetEvent('statewide:client:callHud', function(incoming)
  if type(incoming) ~= 'table' then return end
  local before = index and list[index]
  local clean = {}
  for _, c in ipairs(incoming) do
    if type(c) == 'table' and Pure.isCallNumber(c.number) then clean[#clean + 1] = c end
  end
  list = clean
  index = Pure.hudSelect(list, before and before.number, index)
  local after = index and list[index]
  if (before and before.number) ~= (after and after.number) then
    changedAt = GetGameTimer()
    details = false
  end
  render()
end)

local function move(step)
  local nextIndex = Pure.hudMove(list, index, step)
  if not nextIndex or nextIndex == index then return end
  index = nextIndex
  details = false
  render()
end

local function attach()
  local c = index and list[index]
  if not c or c.attached or GetGameTimer() - changedAt < 1000 then return end
  TriggerServerEvent('statewide:callHud', c.number)
end

local function toggleDetails()
  if not (index and list[index]) then return end
  details = not details
  render()
end

if Config.callHud.enabled then
  RegisterCommand(COMMANDS.prev, function() move(-1) end, false)
  RegisterCommand(COMMANDS.next, function() move(1) end, false)
  RegisterCommand(COMMANDS.attach, attach, false)
  RegisterCommand(COMMANDS.details, toggleDetails, false)
  for action, command in pairs(COMMANDS) do
    RegisterKeyMapping(command, L('cmd_callhud_' .. action), 'keyboard', Config.callHud.keys[action])
  end
  CreateThread(function()
    Wait(1000)
    for _, command in pairs(COMMANDS) do TriggerEvent('chat:removeSuggestion', '/' .. command) end
  end)
end
