local blips = {}
local keys = {}

local function addBlip(m)
  local kind = Pure.SCENE_MARKER_KINDS[m.kind]
  local blip = AddBlipForCoord(m.x, m.y, 0.0)
  SetBlipSprite(blip, kind.sprite)
  SetBlipColour(blip, kind.colour)
  SetBlipScale(blip, 0.9)
  SetBlipAsShortRange(blip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(Pure.sceneBlipName(m))
  EndTextCommandSetBlipName(blip)
  return blip
end

local function dropBlip(id)
  local blip = blips[id]
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
  blips[id] = nil
  keys[id] = nil
end

RegisterNetEvent('statewide:client:sceneMarkers', function(list)
  if type(list) ~= 'table' then return end
  local add, remove = Pure.sceneBlipChanges(keys, list)
  for _, id in ipairs(remove) do dropBlip(id) end
  for _, m in ipairs(add) do
    blips[m.id] = addBlip(m)
    keys[m.id] = Pure.sceneBlipKey(m)
  end
end)

AddEventHandler('onResourceStop', function(name)
  if name ~= GetCurrentResourceName() then return end
  for id in pairs(blips) do dropBlip(id) end
end)
