Config = {}

Config.serverStatus = true

Config.identity = { requireDiscord = false, allowLink = true }

Config.commands = {
  duty       = { name = 'duty',       aliases = {}, enabled = true },
  offduty    = { name = 'offduty',    aliases = {}, enabled = true },
  status     = { name = 'status',     aliases = {}, enabled = true },
  ['911']    = { name = '911',        aliases = {}, enabled = true },
  ['911a']   = { name = '911a',       aliases = {}, enabled = true },
  ['311']    = { name = '311',        aliases = {}, enabled = true },
  ['311a']   = { name = '311a',       aliases = {}, enabled = true },
  ts         = { name = 'ts',         aliases = {}, enabled = true },
  panic      = { name = 'panic',      aliases = {}, enabled = true },
  clearpanic = { name = 'clearpanic', aliases = {}, enabled = true },
  plate      = { name = 'plate',      aliases = {}, enabled = true },
  name       = { name = 'name',       aliases = {}, enabled = true },
  regveh     = { name = 'regveh',     aliases = {}, enabled = true },
  regcarjack = { name = 'regcarjack', aliases = {}, enabled = true },
  regparkedveh = { name = 'regparkedveh', aliases = {}, enabled = true },
  setciv     = { name = 'setciv',     aliases = {}, enabled = true },
  getciv     = { name = 'getciv',     aliases = {}, enabled = true },
  clearciv   = { name = 'clearciv',   aliases = {}, enabled = true },
  id         = { name = 'id',         aliases = {}, enabled = true },
  hideid     = { name = 'hideid',     aliases = {}, enabled = true },
  giveid     = { name = 'giveid',     aliases = {}, enabled = true },
  attach     = { name = 'attach',     aliases = {}, enabled = true },
  note       = { name = 'note',       aliases = {}, enabled = true },
  tracking   = { name = 'tracking',   aliases = {}, enabled = true },
  citations  = { name = 'citations',  aliases = {}, enabled = true },
  callhud    = { name = 'callhud',    aliases = {}, enabled = true },
  link       = { name = 'link',       aliases = {}, enabled = true },
}
Config.cooldowns = { default = 2, ['911'] = 30, ['311'] = 30, panic = 30, plate = 5, name = 5, ts = 10, note = 5, link = 10 }
Config.chat = { color = { 66, 135, 245 }, prefix = 'CAD' }

Config.stateBag = 'auto'
Config.attach = { waypoint = true, onScene = true }

Config.blips = { call911 = true, seconds = 120 }
Config.scriptCalls = { allow = {}, cooldown = 60 }

Config.tablet = {
  enabled = true,
  command = 'tablet',
  key = 'F6',
  cooldown = 5,
  vehicleOnly = false,
  vehicleClasses = { 18 },
  vehicleModels = {},
  scale = 'auto',
  requireDuty = true,
  keepMinutes = 30,
}

Config.callHud = {
  enabled = true,
  cooldown = 3,
  keys = { prev = 'PAGEUP', next = 'PAGEDOWN', attach = 'HOME', details = 'END' },
}

Config.locationInterval = 3
Config.positions = { metres = 2, degrees = 15, keepalive = 10 }
Config.labels = { minSeconds = 2, maxLength = 64 }
Config.postalResource = 'nearest-postal'
Config.sceneMarkers = { blips = true, everyone = false, allow = {}, cooldown = 5 }

Config.modules = { ers = 'auto' }
Config.ers = {
  calloutPriority = 2,
  closeOnComplete = true,
  closeOnEnd = false,
  disposition = 'HND',
  pulloverNature = nil,
  pulloverPriority = nil,
  closeOnPulloverEnd = false,
  pursuitStatus = nil,
  hospitalNote = true,
  registerRecords = true,
  dateOrder = 'dmy',
  licenses = { License_Car = 'DL', License_Bike = 'MC', License_Truck = 'CDL', License_Boat = 'BOAT', License_Pilot = 'PILOT' },
  dutySync = { police = false, fire = false, ambulance = false, tow = false },
  pushShift = false,
  hidePanels = true,
  offerTimeout = 15000,
  cooldown = 3,
  calloutCooldown = 20,
}

Config.citation = { enabled = true, cooldown = 2, inventory = 'ox_inventory', item = nil }
Config.idCard = { handover = false, distance = 3.0, seconds = 15, defaultType = 'driver', nui = true }
Config.photoHosts = { '.statewide.gg', '.r2.cloudflarestorage.com' }
Config.photoDevHttp = false
