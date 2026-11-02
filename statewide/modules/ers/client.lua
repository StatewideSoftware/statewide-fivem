local ERS = 'night_ers'

local function hidePanels()
  local setting = Config.modules and Config.modules.ers
  if setting == false or setting == 'off' or not Config.ers.hidePanels then return end
  if GetResourceState(ERS) ~= 'started' then return end
  Wait(2000)
  pcall(function() exports[ERS]:SetERSVehicleInfoDisplay(false) end)
  pcall(function() exports[ERS]:SetERSIDCardInfoDisplay(false) end)
end

CreateThread(hidePanels)

AddEventHandler('onClientResourceStart', function(name)
  if name == ERS then CreateThread(hidePanels) end
end)
