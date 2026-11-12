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
  clockin    = { name = 'clockin',    aliases = {}, enabled = true },
  clockout   = { name = 'clockout',   aliases = {}, enabled = true },
  mugshot    = { name = 'mugshot',    aliases = {}, enabled = true },
}
Config.cooldowns = { default = 2, ['911'] = 30, ['311'] = 30, panic = 30, plate = 5, name = 5, ts = 10, note = 5, link = 10, mugshot = 10 }
Config.chat = { color = { 66, 135, 245 }, prefix = 'CAD' }

Config.stateBag = 'auto'
Config.attach = { waypoint = true, onScene = true }
Config.clockIn = { reportSeconds = 60, jobs = {} }

Config.blips = { call911 = true, seconds = 120 }
Config.scriptCalls = { allow = {}, cooldown = 60 }
Config.witness = {
  enabled = false,
  interval = 500,
  delay = 8,
  radius = 60.0,
  minWitnesses = 1,
  areaRadius = 150.0,
  perMinute = 4,
  playerPerMinute = 2,
  plateChance = 30,
  shots = {
    enabled = true, chance = 80, cooldown = 120, confirm = 2, confirmSeconds = 10,
    ignore = { 'WEAPON_UNARMED', 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_PETROLCAN', 'WEAPON_HAZARDCAN',
      'WEAPON_FERTILIZERCAN', 'WEAPON_FLARE', 'WEAPON_SNOWBALL', 'WEAPON_BALL' },
  },
  crash = { enabled = true, chance = 60, cooldown = 120, damage = 50.0, minSpeed = 15.0 },
  reckless = { enabled = true, chance = 40, cooldown = 300, speed = 45.0, seconds = 10, pavementSpeed = 12.0, pavementSeconds = 3, samples = 3 },
  wreck = { enabled = true, chance = 100, cooldown = 300, delay = 120, engineHealth = 100.0, bodyHealth = 300.0, distance = 30.0 },
  quietZones = {
    { x = 441.0, y = -982.0, radius = 70.0 },
    { x = 1853.0, y = 3687.0, radius = 50.0 },
    { x = -448.0, y = 6012.0, radius = 50.0 },
    { x = 13.0, y = -1097.0, radius = 30.0 },
    { x = 821.0, y = -2163.0, radius = 30.0 },
  },
}

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

Config.modules = { ers = 'auto', wraith = 'auto', lbphone = 'auto', phoneapp = 'auto', nat = 'auto', c7fw = false }
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
Config.wraith = {
  resource = 'wk_wars2x',
  readsPerSecond = 4,
  lookupsPerMinute = 6,
  hitsPerMinute = 12,
  dedupSeconds = 90,
  alertCooldownSeconds = 300,
  proximityCheck = true,
  proximityMeters = 100,
  lockOnHit = false,
  radarAlerts = true,
  debug = false,
  alertOn = { stolen = true, bolo = true, ownerWarrant = true, registration = true, insurance = true, notRegistered = false },
  ignoreClasses = { 13, 14, 15, 16, 21, 22 },
}
Config.lbPhone = {
  resource = 'lb-phone',
  companies = { police = 'leo', ambulance = 'ems', fire = 'fire' },
  dispatchNumber = '911',
  callerWindowSeconds = 600,
  maxCallerNotes = 20,
  noteCooldownSeconds = 10,
  maxTextLength = 500,
  syncPhoneNumber = true,
}
Config.phoneApp = { defaultApp = true, requestIntervalMs = 500 }

Config.citation = { enabled = true, cooldown = 2, inventory = 'ox_inventory', item = nil }
Config.idCard = { handover = false, distance = 3.0, seconds = 15, defaultType = 'driver', nui = true }
Config.photoHosts = { '.statewide.gg', '.r2.cloudflarestorage.com' }
Config.photoDevHttp = false
Config.registration = {
  mode = 'prompt',
  grace = 30,
  gated = { 'tablet', 'id', 'giveid' },
  skipClasses = { 18 },
  skipPopulation = { 1, 2, 3, 4, 5 },
  skipModels = {
    'police', 'police2', 'police3', 'police4', 'policeb', 'policet', 'policeold1', 'policeold2', 'pranger', 'polgauntlet',
    'sheriff', 'sheriff2', 'fbi', 'fbi2', 'riot', 'riot2', 'polmav', 'pbus', 'lguard',
    'ambulance', 'firetruk', 'predator',
  },
}
Config.mugshot = { enabled = 'auto', resource = 'screenshot-basic', distance = 3.0, client = 'suspect', quality = 0.85 }

Config.framework = { allow = {}, connectors = {} }
Config.nat = {
  resource = 'framework',
  departments = { civ_level = 'civilian' },
  autoDuty = true,
  pollSeconds = 3,
  dateOrder = 'dmy',
}
Config.c7fw = {
  resource = 'c7-scripts-framework-v3',
  departments = { civilian = 'civilian' },
  autoDuty = true,
  dateOrder = 'dmy',
}
Config.sync = {
  enabled = false,
  framework = 'standalone',
  resyncOnStart = true,
  flushSeconds = 2,
  pageSize = 100,
  dateOrder = 'dmy',
  genders = { m = 'Male', f = 'Female', male = 'Male', female = 'Female', ['0'] = 'Male', ['1'] = 'Female' },
  standalone = {
    characters = { table = 'characters', id = 'id', owner = 'identifier', firstName = 'firstname', lastName = 'lastname', dob = 'dateofbirth', gender = 'sex',
        heightCm = 'height', phone = 'phone_number' },
    vehicles = { table = 'vehicles', id = 'id', owner = 'character_id', plate = 'plate', model = 'model', make = false, color = false, year = false },
    licenses = { table = 'licenses', id = 'id', owner = 'character_id', type = 'type', class = false, expiresOn = false },
  },
}
