Modules = { active = {} }

local HEARTBEAT_SECONDS = 300
local HEARTBEAT_RETRY_SECONDS = 10
local RESOURCES = {
  ers = 'night_ers',
  wraith = Config.wraith and Config.wraith.resource or 'wk_wars2x',
  tradio = Config.tradio and Config.tradio.resourceName or 'tRadio',
  lbphone = Config.lbPhone and Config.lbPhone.resource or 'lb-phone',
  phoneapp = Config.lbPhone and Config.lbPhone.resource or 'lb-phone',
  nat = Config.nat and Config.nat.resource or 'framework',
  c7fw = Config.c7fw and Config.c7fw.resource or 'c7-scripts-framework-v3',
}
local SERVER_ID_KEY = 'statewide:server_id'
local serverId

function Modules.resolve(name, onStart, absentLine)
  local dependency = RESOURCES[name]
  local mode = ErsMap.mode((Config.modules or {})[name], dependency and GetResourceState(dependency))
  if mode == 'off' then return false end
  local registered = false
  local function activate()
    Modules.active[name] = true
    if not registered then
      registered = true
      onStart()
    end
  end
  AddEventHandler('onResourceStart', function(started)
    if started ~= dependency or Modules.active[name] then return end
    print(('[statewide] %s module on: %s started'):format(name, dependency))
    activate()
    CreateThread(Modules.heartbeat)
  end)
  AddEventHandler('onResourceStop', function(stopped)
    if stopped ~= dependency or not Modules.active[name] then return end
    Modules.active[name] = nil
    print(('[statewide] %s module off: %s stopped'):format(name, dependency))
    CreateThread(Modules.heartbeat)
  end)
  if mode == 'on' then
    activate()
    return true
  end
  if absentLine ~= false then print(absentLine or ('[statewide] %s module waiting: %s is not started'):format(name, dependency)) end
  return false
end

function Modules.list()
  local out = {}
  for name in pairs(Modules.active) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function Modules.serverId()
  if serverId then return serverId end
  local stored = GetResourceKvpString(SERVER_ID_KEY)
  if Pure.isServerId(stored) then
    serverId = stored
  else
    serverId = Pure.newServerId(math.random)
    SetResourceKvp(SERVER_ID_KEY, serverId)
  end
  return serverId
end

local function beat()
  return api('POST', '/heartbeat', 'units', { body = { version = Http.version, modules = Modules.list(), server = Modules.serverId() }, retry = false })
end

function Modules.heartbeat()
  if not Pure.outcomeUnknown(beat()) then return end
  Wait(HEARTBEAT_RETRY_SECONDS * 1000)
  beat()
end

function Modules.start(generation)
  CreateThread(function()
    while Lifecycle.generation == generation do
      pcall(Modules.heartbeat)
      Wait(HEARTBEAT_SECONDS * 1000)
    end
  end)
end
