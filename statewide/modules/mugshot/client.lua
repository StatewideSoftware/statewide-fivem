local HEAD_BONE = 31086
local RELEASE_MS = 25000
local shot

local function release(token)
  if not shot or (token and shot.token ~= token) then return end
  local s = shot
  shot = nil
  RenderScriptCams(false, false, 0, true, true)
  SetCamActive(s.cam, false)
  DestroyCam(s.cam, false)
  if not s.hudHidden then DisplayHud(true) end
  if not s.radarHidden then DisplayRadar(true) end
end

local function pedOf(target)
  if target == GetPlayerServerId(PlayerId()) then return PlayerPedId() end
  local player = GetPlayerFromServerId(target)
  if player == -1 or not NetworkIsPlayerActive(player) then return nil end
  local ped = GetPlayerPed(player)
  if ped == 0 or not DoesEntityExist(ped) then return nil end
  return ped
end

local function stage(ped)
  local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
  local forward = GetEntityForwardVector(ped)
  local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', head.x + forward.x * 1.1, head.y + forward.y * 1.1, head.z + 0.02, 0.0, 0.0, 0.0, 32.0, false, 2)
  PointCamAtCoord(cam, head.x, head.y, head.z - 0.12)
  SetCamActive(cam, true)
  RenderScriptCams(true, false, 0, true, true)
  return cam
end

RegisterNetEvent('statewide:client:mugshot', function(p)
  if type(p) ~= 'table' or type(p.token) ~= 'string' or type(p.target) ~= 'number' then return end
  release()
  local ped = pedOf(p.target)
  if not ped then return TriggerServerEvent('statewide:mugshot', { token = p.token, ready = false }) end
  shot = { token = p.token, hudHidden = IsHudHidden(), radarHidden = IsRadarHidden() }
  shot.cam = stage(ped)
  DisplayHud(false)
  DisplayRadar(false)
  Wait(250)
  TriggerServerEvent('statewide:mugshot', { token = p.token, ready = true })
  local mine = shot
  SetTimeout(RELEASE_MS, function()
    if shot == mine then release() end
  end)
end)

RegisterNetEvent('statewide:client:mugshotDone', function(token)
  if type(token) ~= 'string' then return end
  release(token)
end)

RegisterNUICallback('mugshot', function(data, cb)
  cb({})
  local ssn = type(data) == 'table' and data.ssn
  if type(ssn) ~= 'string' or not ssn:match('^%d%d%d%d%d%d%d%d%d$') then return end
  ExecuteCommand(('%s %s'):format(Config.commands.mugshot.name, ssn))
end)
