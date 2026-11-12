C7fw = {}

local cfg = Config.c7fw or {}
local resource = cfg.resource or 'c7-scripts-framework-v3'
local warned = {}

local function warnOnce(key, line)
  if warned[key] then return end
  warned[key] = true
  print(('^3[statewide] %s^7'):format(line))
end

local function options()
  return { label = 'c7fw', map = cfg.departments, autoDuty = cfg.autoDuty ~= false }
end

local function copyOf(src)
  local ok, char = pcall(function() return exports[resource]:GetCharCopy(src) end)
  if not ok then
    warnOnce('export', ('c7fw module: %s GetCharCopy failed: %s'):format(resource, tostring(char)))
    return nil
  end
  if type(char) == 'string' then
    local decoded, value = pcall(json.decode, char)
    char = decoded and value or nil
  end
  if type(char) ~= 'table' then return nil end
  return char
end

function C7fw.load(src)
  src = tonumber(src)
  if not src or src <= 0 or not Modules.active.c7fw then return end
  local char = copyOf(src)
  if not char then return Framework.apply(src, nil, options()) end
  local character = Pure.normalizeC7(char, cfg.dateOrder)
  if not character then return Framework.refused('c7fw', src, 'validation') end
  local discord = Framework.discordOf(src)
  if not discord then return Notify.player(src, L('no_discord'), 'error') end
  if character.discordId ~= discord then return Framework.refused('c7fw', src, 'not_owner') end
  character.discordId = nil
  Framework.apply(src, character, options())
end

function C7fw.unload(src)
  src = tonumber(src)
  if not src or src <= 0 or not Modules.active.c7fw then return end
  Framework.apply(src, nil, options())
end

local function trigger(fn)
  return function(src)
    if not Pure.isServerSource(source) then return end
    CreateThread(function()
      local ok, err = pcall(fn, src)
      if not ok then print(('^1[statewide] c7fw module: %s^7'):format(tostring(err))) end
    end)
  end
end

function C7fw.start()
  local players = GetPlayers()
  for i = 1, #players do
    local src = tonumber(players[i])
    CreateThread(function()
      local ok, err = pcall(C7fw.load, src)
      if not ok then print(('^1[statewide] c7fw module: %s^7'):format(tostring(err))) end
    end)
  end
end

AddEventHandler('C7FW:PLAYER_LOADED', trigger(C7fw.load))
AddEventHandler('C7FW:PLAYER_UNLOADED', trigger(C7fw.unload))
AddEventHandler('c7fw:CharacterModified', trigger(C7fw.load))

Modules.resolve('c7fw', C7fw.start, ('[statewide] c7fw module: not detected (%s is not started)'):format(resource))
