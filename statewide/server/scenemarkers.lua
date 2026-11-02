SceneMarkers = {}

local own = GetCurrentResourceName()
local markers = {}
local sent = {}
local cooldowns = {}
local refusals = {}

local function cfg()
  return Config.sceneMarkers or {}
end

local function now()
  return GetGameTimer() / 1000
end

function SceneMarkers.syncAll()
  local list = Pure.sceneMarkerList(markers)
  local key = json.encode(list)
  local settings = cfg()
  for src, p in pairs(State.all()) do
    local shown = Pure.sceneMarkersVisible(settings, p.unit)
    local k = shown and key or '[]'
    if sent[src] ~= k then
      sent[src] = k
      TriggerClientEvent('statewide:client:sceneMarkers', src, shown and list or {})
    end
  end
end

function SceneMarkers.load()
  local res = api('GET', '/scene-markers', 'calls')
  if res.status ~= 200 or not res.data then return false end
  markers = Pure.sceneMarkerSet(res.data.markers)
  SceneMarkers.syncAll()
  return true
end

function SceneMarkers.apply(ev)
  if Pure.applySceneMarkerEvent(markers, ev.type, ev.payload) then SceneMarkers.syncAll() end
end

AddEventHandler('playerDropped', function()
  sent[tonumber(source)] = nil
end)

local function listed(resource)
  for _, name in ipairs(cfg().allow or {}) do
    if name == resource then return true end
  end
  return false
end

local function refuse(action, resource, reason)
  if Pure.refusalThrottle(refusals, action .. ':' .. tostring(resource), reason, now(), 60) then
    print(('^3[statewide] %s refused from %s: %s^7'):format(action, tostring(resource), reason))
  end
  return false, reason
end

local function reply(cb, result)
  if cb == nil then return end
  local ok, err = pcall(cb, result)
  if not ok then print(('^3[statewide] scene marker callback error: %s^7'):format(tostring(err))) end
end

local function allowed(action, resource)
  if not Pure.useCooldown(cooldowns, resource, now(), cfg().cooldown or 5) then return refuse(action, resource, 'cooldown') end
  return true
end

function SceneMarkers.list()
  return Pure.sceneMarkerList(markers)
end

exports('setSceneMarker', function(data, cb)
  local resource = GetInvokingResource()
  if not resource or resource == own or not listed(resource) then return refuse('setSceneMarker', resource or own, 'not_allowed') end
  local ok, reason = allowed('setSceneMarker', resource)
  if not ok then return false, reason end
  local body = Pure.buildSceneMarker(data)
  if not body then return refuse('setSceneMarker', resource, 'validation') end
  CreateThread(function()
    local res = api('POST', '/scene-markers', 'calls', { body = body })
    local m = res.status == 201 and res.data and Pure.sceneMarker(res.data.marker)
    if m then
      if not markers[m.id] then
        markers[m.id] = m
        SceneMarkers.syncAll()
      end
      return reply(cb, { ok = true, id = m.id })
    end
    local code = res.problem and res.problem.code or ('http_' .. tostring(res.status))
    refuse('setSceneMarker', resource, code)
    reply(cb, { ok = false, code = code })
  end)
  return true
end)

exports('clearSceneMarker', function(id, cb)
  local resource = GetInvokingResource()
  if not resource or resource == own or not listed(resource) then return refuse('clearSceneMarker', resource or own, 'not_allowed') end
  local ok, reason = allowed('clearSceneMarker', resource)
  if not ok then return false, reason end
  if not Pure.isSceneMarkerId(id) then return refuse('clearSceneMarker', resource, 'validation') end
  CreateThread(function()
    local res = api('DELETE', '/scene-markers/{markerId}', 'calls', { params = { markerId = id } })
    local gone = res.status == 204 or (res.problem and res.problem.code == 'not_found')
    if gone and markers[id] then
      markers[id] = nil
      SceneMarkers.syncAll()
    end
    if res.status == 204 then return reply(cb, { ok = true }) end
    local code = res.problem and res.problem.code or ('http_' .. tostring(res.status))
    refuse('clearSceneMarker', resource, code)
    reply(cb, { ok = false, code = code })
  end)
  return true
end)
