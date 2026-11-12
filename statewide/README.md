# Statewide: FiveM CAD and MDT resource

A free, open source CAD and MDT for FiveM. This resource connects your server to your community's Statewide CAD:
duty, unit status, panic, 911 and 311 calls, traffic stops, plate and name lookups, civilian commands and live CAD
events in game. It is one server-side resource, MIT licensed, with no dependency but OneSync. It talks only to the
Statewide API (`/api/v1`) with your community's API key.

## Features

- In-game MDT tablet: `F6` or `/tablet` opens the CAD's MDT over the game, signed in as the player (see Tablet).
- Dispatch: units sign on with `/duty`, change status, attach to calls and press panic. Dispatchers see them on the
  live map with position, heading, speed and vehicle type (see Locations).
- 911 and 311: `/911`, `/911a`, `/311` and `/311a` open calls at the caller's street and postal. A call HUD lists
  open calls with attach keys (see Call HUD), and other resources can raise calls with the `create911` export.
- Witness calls: gunfire, crashes, reckless driving and wrecks seen by people nearby reach dispatch and DOT, off
  until you turn them on (see Witness calls).
- Night's ERS: callouts, pullovers and records become CAD records (see Night's ERS).
- LB Phone: texts to police, ambulance or fire become 911 calls, dispatch replies reach the caller's phone, and
  officers get attach and panic alerts on their phone (see LB Phone).
- Statewide phone app: an app inside LB Phone for a player's characters, vehicles, licenses, tickets and 911 calls,
  and on duty their call, status, panic and lookups (see Statewide phone app).
- Lookups and civilians: `/plate`, `/name`, `/regveh`, `/setciv` and the other civilian commands (see Commands).
- License cards: `/id` and `/giveid` show a character's license card over the game view (see License card).
- Booking photos: `/mugshot` puts a photo of the suspect on their character and the open arrest, with the optional
  `screenshot-basic` resource (see Booking photos).
- Unit tracking: on-duty positions reach the live map every few seconds, and a unit can hide itself with
  `/tracking off` where the community allows it.
- Frameworks: a character picked in NAT Framework V2 or C7 Framework V3 (off by default) becomes the player's CAD
  character, and a department character signs the player on in that department. Any other framework connects with
  three exports (see Connect your framework).
- Events and exports for your own resources (see Events for other resources and Exports).

## Requirements

- A FiveM server with OneSync on.
- A Statewide community and an API key created by its owner.
- Players run Discord when they join. The CAD knows them by their Discord account, and that account must be a member of
  your community. A player without Discord can sign in to the tablet with a linked game account.

## Install

1. Copy this folder into your server's `resources/` and keep its name, `statewide`.
2. In the CAD, open **Settings > API keys** and create a key for this server with the scopes **units**, **calls**,
   **lookup**, **civilian** and **tablet** (drop the ones you do not use; the console says which scope a refused call
   needed). Each game server needs its own key, because every server on a key shares that key's limits.
3. Add to `server.cfg`, after OneSync is on:

   ```cfg
   set onesync on
   set statewide_api_url "https://api.statewide.gg"
   set statewide_api_key "sw_live_..."
   add_convar_permission statewide read statewide_api_key
   set statewide_location_interval 3
   ensure statewide
   ```

   Use `set`, never `setr`. A replicated convar is sent to every client. The key never leaves the server.
   `add_convar_permission` limits reading the key to this resource; without it, every resource on the server can read it.
4. Restart. The console prints `[statewide] connected to <community>`; a warning follows when this resource is older
   than the API's `minResourceVersion`.

The resource keeps a random server id in its resource storage (`statewide:server_id`) and sends it with its heartbeat
every 5 minutes; a beat the CAD did not answer is sent once more 10 s later. When one key reports two server ids within 15 minutes, the CAD's API keys page warns that the key is
in use on more than one game server.

| Convar | Default | |
| --- | --- | --- |
| `statewide_api_url` | none | The API origin (`https://api.statewide.gg`, or your custom host). The resource calls `<url>/api/v1/...`. |
| `statewide_api_key` | none | This server's own API key. Server only, and a different key on each game server. |
| `statewide_location_interval` | `3` | Seconds between position reads (minimum 2). Only units that moved, turned or changed vehicle are sent, plus one keepalive every 10 seconds. |
| `statewide_http_concurrency` | `8` | Most requests to the CAD in flight at once (1 to 32). Others wait, urgent ones first. |

Nothing else is required. Postals, city and county come from the community's own lists (see Locations); a
`nearest-postal` resource is used for postals when it is running.

## Updates

On start and every 6 hours the resource asks the CAD API (the same `/health` call it already makes, to no other host)
for the newest published release. When yours is older it prints one console line with the version, its date and the
download link, and prints another only when a newer release comes out or the server restarts. It never downloads,
replaces or restarts anything: copy the new release over this folder and restart the resource yourself. The API keys
page in the CAD shows "Update available" beside a key whose server last reported an older version. The warning about
a version older than the API's `minResourceVersion` is separate and stays.

## Commands

Every command is registered server side from `Config.commands` in `shared/config.lua`. Rename an action, add aliases
or turn it off; chat suggestions follow the configured names. Two actions may not share a name. If they do, the console
prints the clash and registers no command until it is fixed.

```lua
Config.commands.duty = { name = 'signon', aliases = { 'onduty' }, enabled = true }
Config.commands.regveh.enabled = false
```

| Action | Default | What it does |
| --- | --- | --- |
| `duty` | `/duty <department> [callsign]` | Signs on duty (department abbreviation). With no callsign, your roster callsign is used, else the one from your last shift there. |
| `clockin` | `/clockin [department]` | Clocks in for duty time without a unit in the CAD. Name the department when you hold seats in more than one. The time shows in the department's duty reports, and a unit you sign on during it is not counted twice. A department that signs units on with a clock-in (CAD, Manage, Duty settings) also signs you on with your roster callsign. |
| `clockout` | `/clockout` | Clocks out, and signs off the unit the clock-in signed on. Leaving the server clocks you out at once; if the server stops without saying so, the CAD clocks you out 5 minutes after it last saw you. |
| `offduty` | `/offduty` | Signs off. Leaving the server keeps your unit, status and call for the community's **Keep a dropped unit for** time (CAD admin, MDT settings; 5 minutes by default) and rejoining in time takes them back; at 0 leaving signs off at once. |
| `status` | `/status <code>` | Sets the unit status by its code or label. A radio 10-code works too (`10-8` available, `10-6` busy, `10-7` unavailable, `10-97` or `10-76` en route, `10-23` on scene, `10-41` on duty, `10-42` off duty) when the community has no code of that name. An unknown code lists the ones that work. |
| `911` | `/911 <message>` | A 911 call at your street and postal, as your active character. With no dispatcher on duty, on-duty LEO and Fire/EMS also get it in chat. |
| `911a` | `/911a <message>` | An anonymous 911. Locked while you are on duty. |
| `311` | `/311 <message>` | A non-emergency call as your active character (no chat fallback). |
| `311a` | `/311a <message>` | An anonymous non-emergency call. Locked while you are on duty. |
| `ts` | `/ts [plate] [occupants]` | Starts a traffic stop with your unit on scene, and shows the plate return. The first word is the plate (up to 8 characters); the rest says who is in the vehicle (up to 60) and goes in the call description. |
| `panic` | `/panic` | Raises your panic, or clears it when you are already in panic. |
| `clearpanic` | `/clearpanic` | Clears your panic (nothing is sent when you are not in panic). |
| `plate` | `/plate <plate>` | Vehicle lookup as your unit. |
| `name` | `/name <first> <last>` | Person lookup as your unit. |
| `regveh` | `/regveh [year] [make] [model] [color]` | Registers the vehicle you are sitting in to your active character. With no arguments it reads the make, model, color and plate from the game. Anything you type replaces the value read, in that order: `/regveh Vapid Dominator Red`. A four-digit year first (1900 to 2100) is saved as the model year: `/regveh 2019 Vapid Dominator Red`, or `/regveh 2019` to keep what the game reads. Locked while you are on duty. |
| `regcarjack` | `/regcarjack` | Registers the car you carjacked to a made-up owner, with the make, model, color and plate the game reports. A witness reports it stolen on 911 at that spot. Driver seat only, locked while you are on duty. |
| `regparkedveh` | `/regparkedveh` | Registers the parked car you took to a made-up owner, who may report it stolen on 311 a few minutes later. Driver seat only, locked while you are on duty. |
| `setciv` | `/setciv <ssn>` | Sets your active character. Locked while you are on duty. |
| `getciv` | `/getciv` | Shows your active character. |
| `clearciv` | `/clearciv` | Clears your active character. Locked while you are on duty. |
| `id` | `/id [type]` | Shows your active character's driver license card; run it again to put the card away, for you and whoever you handed it to. `type` picks another license the character holds by its code: `/id cdl`, `/id boat`, `/id hunt`, `/id fish`. With `Config.idCard.handover = true` the nearest player within `Config.idCard.distance` sees it too. |
| `giveid` | `/giveid [type]` | Hands your license card to the nearest player within `Config.idCard.distance` (3 m by default) and plays the hand-over animation. With nobody that close, chat says so. |
| `hideid` | `/hideid` | Closes your ID card, for you and whoever you showed it to with `/id` or `/giveid`. |
| `attach` | `/attach <call number>` | Attaches your unit to a call (`26-000123`). |
| `note` | `/note <text>` | Adds a note to the call your unit is on, as your unit. Up to 500 characters. |
| `tracking` | `/tracking [on\|off]` | Hides your unit from the CAD live map until you sign off (`off`), or shows it again (`on`); with no argument it toggles. Every sign-on starts visible. Dispatch still sees your street and postal, and a hidden tag on your unit. A community that requires tracking refuses `off`. |
| `citations` | `/citations` | Opens the citations an officer asked you to sign, newest first, as a paper sheet. Type your character's full name and press Sign, press Keep to keep it as an item, or Close to leave it unsigned for later (on the CAD or with `/citations`). |
| `callhud` | `/callhud` | Hides the call HUD for you, or shows it again. The choice is kept by your FiveM license on the server, through reconnects and restarts. With `Config.callHud.enabled = false` it stays off for everyone. |
| `mugshot` | `/mugshot <ssn or id>` | Takes a booking photo of the suspect standing next to you, by their character's SSN or their server id. Needs a unit on duty, `records.create` and the **lookup** scope on the key, and the `screenshot-basic` resource (see Booking photos). |
| `link` | `/link <code>` | Links this game account to your Statewide account with a code from your profile page on the community website (10 minutes, single use). The server reads your FiveM license itself and the CAD links it to the account that made the code, then names that account in chat. Needs the **units** or **civilian** scope; off with `Config.identity.allowLink = false`. |

Any text goes through `/911`, `/911a`, `/311` and `/311a`, however short. A command typed without what it needs answers with
one example, such as `Say what's happening, for example: /911 shots fired near Legion Square.` When the CAD refuses
a field, chat shows its reason, such as the colors the community allows.

When the CAD does not answer `/ts`, `/attach` or `/status`, the resource checks your unit 5 s later: chat shows the
usual line if it went through, otherwise `The CAD did not answer. Check your unit before trying again.`

`/setciv`, `/clearciv`, `/regveh`, `/regcarjack`, `/regparkedveh`, `/911a` and `/311a` are for civilian play. While you have a unit on duty they answer
`You're on duty as 1A-12. Go off duty with /offduty to play a civilian.` The CAD refuses them too, so the lock holds
for a unit signed on from the web MDT. `/911` and `/311` work on or off duty, but they need an active character and, in a
community with a Civilian department, a seat there. Off duty, pick a character with `/setciv` or call with `/911a`.
On duty with no character, the refusal says to go off duty first: `You have no active character. Go off duty with
/offduty, then pick one with /setciv <ssn>.`

`/regveh` reads the vehicle's primary paint and names it with one of thirteen colors: Black, White, Silver, Gray,
Red, Blue, Green, Yellow, Orange, Brown, Purple, Pink or Gold. Makes and colors are matched to the community's lists
without regard to case and saved as the list spells them. A make or color the lists lack is added to them, marked
From the game, unless the community turned off **Add vehicle makes and colors from the game** under **Settings >
General**. With it off the CAD refuses and chat lists the values it accepts.

The server reads the model of the vehicle the player sits in. Make and model labels come from the server's model table
(`server/vehicles.lua`, the base game's vehicles with their English names) when the model is known; otherwise the
client's labels are accepted only when its model name hashes to the vehicle the server read. A vehicle that fails
that check gets no make or model, and `/regveh` asks for them as arguments.

`/regcarjack` and `/regparkedveh` are for stolen cars. A plate a player owns is refused with `That plate is already
registered.`; a plate already on a made-up owner keeps that owner. Each player may register one car a minute and hold
three at a time. Once the report time passes, a plate check shows the car stolen with the time it was reported. How
often and how soon each kind is reported, and whether the commands work at all, are set under **Settings > Civilian >
Stolen vehicles** (by default a carjacking is always reported 60 to 120 seconds later, a parked car 60% of the time
after 3 to 5 minutes). Made-up owners and their cars are deleted after 48 hours unless a report, citation, arrest or
BOLO names them.

## Settings

`shared/config.lua` is loaded on clients too, so it holds nothing secret. The API URL, the key and the location
interval are server convars (see Install).

### Connection

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.serverStatus` | `true` | Reports the player count to the CAD every 60 s for the Server Status block on your public site (see How it behaves). `false` sends nothing. |

### Identity

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.identity` | `requireDiscord = false`, `allowLink = true` | `requireDiscord = true` refuses a join from a player with no Discord identifier and tells them to start Discord, link it to FiveM and rejoin. `allowLink = true` lets a player without Discord sign in to the tablet with their account email and password instead, or link the game account with `/link` and a code from the website: when the tablet is on, a joining player with no Discord and no account linked to their license gets a chat hint to open it (default `F6`). The player's license identifier, read on the server, travels beside their Discord ID on every CAD call: the CAD records it on first sight and refuses the player when another account in the community already holds that license. |

### Commands

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.commands` | every action on | One entry per action: `name`, extra `aliases` and `enabled`. See Commands. |
| `Config.cooldowns` | `default` 2, `911` 30, `311` 30, `panic` 30, `plate` 5, `name` 5, `ts` 10, `note` 5, `link` 10, `mugshot` 10 | Seconds between uses per player. `default` applies to every command, and a player's next command waits until the last one has finished. `911` and `911a` share the `911` cooldown, `311` and `311a` the `311` one; `panic` counts only when raising. The API limit is per key, so one player spamming would slow the whole server down. |
| `Config.chat` | `{66, 135, 245}`, `CAD` | Chat line color and prefix. |

### Duty and units

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.stateBag` | `'auto'` | What the `statewide:unit` state bag carries: `'auto'`, `'full'` or `'minimal'` (see Exports). |
| `Config.attach` | `waypoint = true`, `onScene = true` | When a unit is attached to a call, `waypoint` sets the officer's GPS to the call. `onScene` switches an en route unit to On Scene once it is inside the community's On scene within distance (MDT settings, Arrival) for two position reads in a row; the server reads the position, and an empty distance in the CAD turns it off. A manual status change after the attach is never overridden. |
| `Config.clockIn` | `reportSeconds = 60`, `jobs = {}` | Every `reportSeconds` (30 to 180) the server tells the CAD which players are still on it, which keeps their clock-ins open and picks them up again after a restart. `jobs` maps framework jobs to department abbreviations, for example `{ police = 'LSPD', ambulance = 'EMS' }`: going on duty in a mapped job (QBCore and Qbox duty toggles, ESX job duty) clocks the player in there, going off duty clocks them out. Empty, frameworks clock nobody in. |

### 911

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.blips` | `call911 = true`, `seconds = 120` | A 911 from in game drops a blip at the caller for on-duty LEO and Fire/EMS for `seconds`. |
| `Config.scriptCalls` | `allow = {}`, `cooldown = 60` | Resources allowed to raise a 911 with the `create911` export, by resource name, and the seconds between calls per resource (see Exports). The empty list turns the export off. |
| `Config.witness` | `enabled = false`, one table per kind | Bystander 911 calls and DOT road reports raised by the server from what nearby people saw (see Witness calls). Off until you turn it on. |

### Tablet

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.tablet` | `enabled = true`, `command = 'tablet'`, `key = 'F6'`, `cooldown = 5`, `vehicleOnly = false`, `vehicleClasses = {18}`, `vehicleModels = {}`, `scale = 'auto'`, `requireDuty = true`, `keepMinutes = 30` | The in-game tablet (see Tablet). `key` is the default bind; players rebind it under Settings > Key Bindings > FiveM. `cooldown` is seconds between sign-ins per player. `scale` is the MDT's size: `'auto'` or a number from 0.8 to 2. `requireDuty` opens the MDT only for players with a unit on duty. `keepMinutes` is how long a closed tablet keeps the MDT loaded; `0` keeps it until the player goes off duty. |

### Call HUD

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.callHud` | `enabled = true`, `cooldown = 3`, `keys = { prev = 'PAGEUP', next = 'PAGEDOWN', attach = 'HOME', details = 'END' }` | The call HUD (see Call HUD). `keys` are the default binds; players rebind them under Settings > Key Bindings > FiveM. `cooldown` is seconds between attaches from the HUD per player. `enabled = false` turns the HUD and its keys off. |

### Map and locations

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.locationInterval` | `3` | Seconds between position reads when the `statewide_location_interval` convar is unset. |
| `Config.positions` | `metres = 2`, `degrees = 15`, `keepalive = 10` | An on-duty unit's position is sent once it has moved `metres`, turned `degrees` or got into or out of a vehicle since the last one, and at least every `keepalive` seconds while it stands still. Position, heading, speed and vehicle type (on foot, car, bike, boat, aircraft) are read on the server; the CAD live map shows them. |
| `Config.labels` | `minSeconds = 2`, `maxLength = 64` | Street labels from on-duty clients: at most one update per `minSeconds` per player, each label capped at `maxLength` characters. Off duty a client sends labels only when the server asks, for `/911` and `/311`. |
| `Config.postalResource` | `nearest-postal` | The resource postals come from, when it is running. 911 and panic use the postal its server export derives from the player's position. Without it the CAD fills postals from the community's own list. |
| `Config.sceneMarkers` | `blips = true`, `everyone = false`, `allow = {}`, `cooldown = 5` | Scene markers from the CAD (roadblocks, fire scenes and the like) show as blips for on-duty players, or for every player with `everyone = true`; `blips = false` turns them off. `allow` lists the resources that may set and clear markers with the `setSceneMarker` and `clearSceneMarker` exports, and `cooldown` is the seconds between calls per resource (see Exports). |

### Integrations

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.modules` | `ers = 'auto', wraith = 'auto', lbphone = 'auto', phoneapp = 'auto', nat = 'auto', c7fw = false` | Optional integrations. `'auto'` turns one on when its resource is started (now or later), `true` forces it on, `false` leaves it off and registers nothing. |
| `Config.ers` | see Night's ERS | The Night's ERS integration. |
| `Config.wraith` | see Wraith ALPR | Flagged plate alerts from Wraith ARS 2X. |
| `Config.lbPhone` | see LB Phone | 911 texts to LB Phone companies, replies to the caller and officer alerts on the phone. |
| `Config.phoneApp` | see Statewide phone app | The Statewide app inside LB Phone. |

### Optional features

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.citation` | `enabled = true`, `cooldown = 2`, `inventory = 'ox_inventory'`, `item = nil` | When an officer asks for a signature on a citation, the cited player gets the sheet in game, if they are on the server with Discord; a player signed in through a linked game account opens it with `/citations`. The API key needs the `civilian` scope. `item` names an item in an inventory resource with the ox_inventory server exports (`CanCarryItem`, `AddItem`); with it set and that resource started, Keep adds one item per citation, its metadata `citation`, `number`, `label`, `description` and `fine`. Without it Keep only records the keep and fires `statewide:citationKept`. `cooldown` is the seconds between two presses on the sheet. |
| `Config.idCard` | `handover = false`, `distance = 3.0`, `seconds = 15`, `defaultType = 'driver'`, `nui = true` | `distance` is how close, in meters, the other player must be for `/giveid` (and for `/id` with `handover` on, which also plays the hand-over animation). The card closes after `seconds`, on a second `/id`, with `/hideid`, or with Escape or Backspace. `defaultType` is the license `/id` shows with no type: `'driver'` matches the codes `DL`, `DRV` and `DRIVER` or a license whose name starts with Driver; anything else is a license type code. `nui = false` prints the card to chat instead. |
| `Config.photoHosts` | `'.statewide.gg'`, `'.r2.cloudflarestorage.com'` | Hosts the license card loads a character photo from, over https. A leading dot allows every subdomain. A photo link on any other host shows No photo. Add your storage host if you run your own CAD. |
| `Config.photoDevHttp` | `false` | For local development only. `true` lets the card load a photo over plain `http` from `localhost` or `127.0.0.1`, and only when that host is also in `Config.photoHosts` (add `'localhost'` there). Every other photo needs https on a listed host. Leave it `false` on a live server. |
| `Config.registration` | `mode = 'prompt'`, `grace = 30`, `gated = {'tablet', 'id', 'giveid'}`, `skipClasses = {18}`, `skipPopulation = {1, 2, 3, 4, 5}`, `skipModels = {...}` | What happens when a civilian drives a vehicle whose plate is not on their active character. `'prompt'` tells them once per vehicle to type `/regveh`; `'enforce'` also refuses the `gated` actions (`'tablet'` and any command name, such as `'id'`) after `grace` seconds, and stops the engine; `'off'` does nothing and sends no lookup. Never applies to a player with a unit on duty. The server reads the seat, plate, model and population type itself and skips ambient and parked traffic cars (`skipPopulation`, the game's population type numbers) and the models in `skipModels`; the client skips the vehicle classes in `skipClasses` before it signals. A plate is looked up once per character every 10 minutes and the answer is reused. The API key needs the `civilian` scope. A plate registered to another character shows as unregistered. |
| `Config.mugshot` | `enabled = 'auto'`, `resource = 'screenshot-basic'`, `distance = 3.0`, `client = 'suspect'`, `quality = 0.85` | Booking photos (see Booking photos). `'auto'` turns `/mugshot` on while `resource` is started; `false` removes the command. `distance` is how close, in meters, the suspect must stand. `client = 'suspect'` takes the photo on the suspect's game and, when that fails, on the officer's; `'officer'` uses only the officer's. `quality` is the JPEG quality, 0.5 to 0.95. |

### Framework sync

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.framework` | `allow = {}`, `connectors = {}` | Resources allowed to call exports, by resource name. `allow` covers the sync exports (`SyncCharacter`, `SyncVehicle`, `SyncLicense`); `connectors` covers the character and duty exports (`SetActiveCharacter`, `ClearActiveCharacter`, `SetDuty`). Any other caller is refused. The NAT and C7 modules need neither list. |
| `Config.nat` | `resource = 'framework'`, `departments = { civ_level = 'civilian' }`, `autoDuty = true`, `pollSeconds = 3`, `dateOrder = 'dmy'` | NAT Framework V2 (see Connect your framework). `departments` maps a NAT department key (`level`) to `'civilian'` or a CAD department abbreviation. `pollSeconds` is how often the played character is checked. `dateOrder` reads a DOB written as `04/05/1990` (`'dmy'` or `'mdy'`). |
| `Config.c7fw` | `resource = 'c7-scripts-framework-v3'`, `departments = { civilian = 'civilian' }`, `autoDuty = true`, `dateOrder = 'dmy'` | C7 Framework V3 (see Connect your framework). `departments` maps a C7 character department to `'civilian'` or a CAD department abbreviation. |
| `Config.sync` | `enabled = false`, `framework = 'standalone'`, `resyncOnStart = true`, `flushSeconds = 2`, `pageSize = 100`, `dateOrder = 'dmy'`, `genders = {...}`, `standalone = {...}` | Copies characters, vehicles and licenses from your framework's database into the CAD. See Framework sync. The API key needs the `sync` scope. |

## Locations

Calls from `/911`, `/911a`, `/311`, `/311a`, `/ts` and `/panic`, and on-duty units, carry a full location with no
other resource:

- Postal: the one the postal resource reports when it runs. Otherwise the CAD takes the postal on the community's
  list (**Postals** in the CAD admin) nearest to the position the server reads. A community with no list gets none.
- Area, city and county: the client sends the game's zone code (such as `LEGSQU`). The CAD finds the area with that
  zone code under **Lists > Areas** and uses its name, city and county. An area with no county set falls back to Los
  Santos County or Blaine County by zone.

## Tablet

`F6` or `/tablet` opens the CAD's MDT in a window over the game, signed in as the player. The server asks the CAD for a
one-time sign-in code for that player's Discord account (60 seconds, single use) and the window loads it. Nobody
types a password and the tablet never opens a Discord sign-in. The key needs the **tablet** scope, and the resource
folder must be named `statewide`, because the CAD allows the MDT only inside that folder's tablet. If the MDT has not
loaded after 30 seconds, the window shows an error with a **Close** button. While it is signing in or showing an error,
Escape and the tablet key close it.

Closing the tablet only hides it. The MDT stays loaded, and an open within `keepMinutes` (default 30) shows it again
where the player left it. After that the hidden MDT is unloaded to free the player's memory, and the next open signs in
again. A new sign-in code is asked for only on the first open, after an error, after the keep window, or when the MDT's
session has ended (the page checks it on every reopen). A sign-in lands on the player's unit when they have exactly one on duty, otherwise on the
MDT sign-on card. MDT alert sounds play without a click.

With `requireDuty = true` (the default) the CAD gives a sign-in code only to a player with a unit on duty in the
community (signed on with `/duty`, on the web MDT or by a dispatcher); anyone else sees "You are not on duty" with
the next step `Go on duty with /duty`. Going off duty unloads the MDT, and the next open asks again. The CAD checks
this, not the game server, so a modified client cannot skip it. Set `requireDuty = false` to let every member open it.

`scale = 'auto'` sizes the MDT from the screen height (1 at 1080p up to 1.6 at 4K). **A-** and **A+** in the title
bar make it smaller or larger in steps of 0.1, from 0.8 to 2; the choice is kept per player in client KVP
(`statewide:tablet:scale`), and **Reset** goes back to `scale`.

The window moves by its title bar and resizes from the bottom right corner (at least 800 x 500). Its position and size
are kept per player in client KVP (`statewide:tablet:rect`) and restored, clamped to the screen, on the next open;
**Reset** centers it at its default size. `Config.tablet` sets the command, the default key, the cooldown and the
vehicle rule: with `vehicleOnly = true` it opens only in a vehicle whose class is in `vehicleClasses` (default `{18}`,
emergency) or whose model is in `vehicleModels`, and leaving the vehicle closes it.

## Call HUD

On-duty LEO, Fire and EMS units see a small panel on the right of the screen with the open calls they may see in the
CAD: the shown call (number, priority, nature, location and postal) with the previous and next calls above and below
it. The call the unit is attached to comes first, then the rest by priority, newest first. Page Up and Page Down move
between calls, Home attaches the unit to the shown call and End shows or hides its description and units. The panel
shows the key each action is bound to and hides when there is no open call or the unit goes off duty. `/callhud`
hides it for that player until they run it again; while it is hidden the server sends that player no call list.

The list is the CAD's `GET /calls` for that player, so agency isolation applies. The server asks for up to 100
on-duty players in one request, and the CAD answers which calls each of them may see from its own records, so a seat
or role removed in the CAD applies on the next read. It is read again when a call is created, updated, attached or
closed, and a closed call leaves the panel at once. A change of department or call access clears the panel until the
new list arrives. The HUD takes no NUI focus and the
mouse and keyboard stay with the game. An attach from the HUD names the call the player was shown, and the server
refuses any call it did not send that player. The key needs the **calls** scope.

## Witness calls

With `Config.witness.enabled = true`, people in the street call things in. When a player fires a gun, crashes into
something, drives recklessly or leaves a wrecked vehicle on a road, and an ambient pedestrian or driver is within
`radius` metres in the same routing bucket, the server may raise a call:

| Kind | What sets it off | What the CAD gets |
| --- | --- | --- |
| `shots` | `shots.confirm` shots from a gun not in `shots.ignore` within `shots.confirmSeconds` | 911: Shots fired near the street, with the postal |
| `crash` | The driver's vehicle loses `crash.damage` body or engine health after the server saw it at `crash.minSpeed` m/s or more, and the server saw the drop | 911: Vehicle collision |
| `reckless` | `reckless.speed` m/s for `reckless.seconds`, or `reckless.pavementSpeed` m/s off the road for `reckless.pavementSeconds`, and the server read at least `reckless.pavementSpeed` m/s on its last `reckless.samples` checks | 911: Reckless driver |
| `wreck` | The driver leaves a vehicle with engine or body health at or under its limit on a road, and it is still there `wreck.delay` seconds later | DOT road report: Disabled vehicle |

Each kind has `enabled`, `chance` (0 to 100) and `cooldown` (seconds). A 911 arrives `delay` seconds after the event,
anonymous and tagged Witness in the queue and on the board. It describes a vehicle only vaguely: its color and type,
and the first three characters of the plate `plateChance` percent of the time. The location is the street and
postal at the position the server read; without `nearest-postal` the text takes the postal the CAD filled in. The
player is never named. Without `nearest-postal` the description is written once the CAD has the postal, so an edit a
dispatcher makes in that moment can be overwritten.

The client only says which kind happened. The server reads the player's position, weapon, vehicle, speed and health
itself, checks the driver's vehicle every 2 seconds for its body and engine health and speed, and checks there are ambient people
near before anything is sent, so a client cannot place a call somewhere else. Nothing is reported until the server has
looked the player up in the CAD, while the player is on duty, outside routing bucket 0, or inside a `quietZones`
circle (`x`, `y`, `radius`; the defaults cover Mission Row, Sandy Shores and Paleto Bay stations and the two
Ammu-Nation ranges). One incident of a kind within `areaRadius` metres makes one call until its cooldown ends, a
player gets at most one hint a second, the server sends at most `perMinute` calls a minute and `playerPerMinute` of
them about one player, and the CAD takes at most 6 witness calls and 6 road reports a minute per community. The
detection loop runs every `interval` milliseconds, never faster than 500.

Witness calls need the **calls** scope. Road reports also need the DOT module turned on for the community.

## License card

`/id` and `/giveid` show the card over the game view, on the right of the screen. It is the same card the CAD shows
on the character's record and in an officer's return: a driver license, commercial driver license, state ID card,
firearm permit, or the shared card for any other license type with that type's name as its title. The front carries
the photo (or a gray outline without one), the license number, class, endorsements, restrictions, status, names,
address, date of birth, sex, height, weight, hair, eyes, the issued and expiry dates, the signature and any VETERAN,
DONOR or SAFE DRIVER designation the DMV set. Suspended, revoked and expired licenses carry an overprint. Driver and
commercial licenses have a back with the barcodes, the class and endorsement legend and the icons of the holder's
outdoor licenses: press the Left or Right arrow while the card is shown to turn it over. It never takes the mouse or
keyboard: you keep driving and walking while it is shown. The hand-over target is the nearest player by server-side
position in the same routing bucket; a client never chooses it, and that player sees a smaller card held out to them. `/giveid` to the same
player works once per 10 s.

The state name, seal and colors come from the community's settings in the CAD (Settings, Civilian and DMV, License
cards). The resource reads them when it starts, so a change shows after a resource restart. The card's fonts ship in
`nui/` under the SIL Open Font License (`nui/fonts-OFL.txt`).

The server sends the card to each viewer as `statewide:client:idcard`:

```lua
{
  from = 12, own = true, handover = false,
  name = 'Ryker Cohen', firstName = 'Ryker', middleName = nil, lastName = 'Cohen', dob = '1990-04-12', sex = 'Male',
  address = '1 Grove Street, Los Santos', state = 'San Andreas', hair = 'Black', eyes = 'Brown',
  height = '6 ft 0 in', weight = '181 lb', photo = 'https://...',
  license = { type = 'DL', name = 'Driver License', number = 'D4718209', class = 'C', endorsements = { 'M' },
    status = 'valid', issued = '2026-01-04', expires = '2030-01-04' },
  card = { kind = 'driver', title = 'DRIVER LICENSE', number = 'D4718209', ... },
  theme = { stateName = 'State of San Andreas', sealUrl = nil, colors = { band = '#1d4f8f', accent = '#5b9bd5', ink = '#244e93' } },
}
```

`card` is the card as the CAD draws it (`GET /api/v1/characters/{ssn}/id-card`), `theme` the community's card theme
(`GET /api/v1/community/card-theme`). `statewide:client:hideid` with `{ from = 12 }` closes the card that player
showed. With `Config.idCard.nui = false` the card prints to chat instead; its status words are in `shared/locale.lua`
(`idcard_status_*`).

## Booking photos

`/mugshot <ssn or id>` (or **Take booking photo** on an arrest in the tablet) photographs the suspect standing next to
the officer. The photo becomes the character's photo in the CAD and the booking photo of the officer's open (unsubmitted)
arrest of that character, and shows on the civilian page, the person return and the arrest print.

The photo is taken with [screenshot-basic](https://github.com/citizenfx/screenshot-basic), which you install and start
yourself; this resource never ships or requires it. Without it, or with `Config.mugshot.enabled = false`, everything
else works and `/mugshot` says booking photos are not available.

- The officer needs a unit on duty and `records.create` in the CAD, and the key the **lookup** scope.
- The suspect must be a player with a CAD account and an active character, within `Config.mugshot.distance` meters and
  in the same routing bucket, when the command runs and again before the photo.
- The game server asks the CAD for a ticket for that officer and character, valid once for 60 seconds. It asks the
  suspect's game to frame a head-and-shoulders shot and accepts the ready answer only from the player it asked, for that
  request, then takes the screenshot through `screenshot-basic` on the server. If that fails it uses the officer's game.
- The booking photo is a capture of that client's screen: whatever the configured capturing client (`Config.mugshot.client`)
  shows while the camera is framed is what lands in the CAD.
- The image goes to the CAD from the game server with the ticket. The CAD checks it is a JPEG, PNG or WebP of at most
  2 MB, removes its metadata and stores it privately. No upload link or API key ever reaches a player.

## Night's ERS

With [Night's ERS](https://docs.nights-software.com/resources/ers/) (`night_ers`) on the server, the resource turns
ERS play into CAD records. It listens to the `ErsIntegration::*` events ERS already fires: nothing in `night_ers` is
edited and there is no dependency line. Start `night_ers` before or after `statewide`; with `Config.modules.ers =
'auto'` the module switches on when `night_ers` starts and logs one line while it waits.

Only players with a unit on duty in the CAD count. Callouts are dropped once ERS reports the player off shift, and
pullovers and pursuits count only for a law enforcement unit that ERS has not reported on another service. Shift
changes are taken from the ERS server event only. An ERS event from anyone else, or one whose data is malformed or
oversized, is dropped with at most one console warning per player per minute. Players and units are always the
event's own player on the server; nothing a client sends names another player.

| ERS event | What the CAD gets |
| --- | --- |
| A callout is accepted | A call with origin ERS: the callout name as nature, `calloutPriority`, the player's street and postal, the callout's position as the map pin, and the unit attached as primary. Offers that are not accepted are ignored. |
| Arrived at the callout | The unit's status goes to the community's on-scene status, and a note is added. |
| Callout completed | The call closes with `disposition` when `closeOnComplete` is on, otherwise a note. |
| Callout ended | With `closeOnEnd` the call closes. Otherwise a note and the unit is detached; the call stays open. ERS also fires this when a callout is cancelled, so leave `closeOnEnd` off unless that is what you want. |
| Pullover | A traffic stop like `/ts`, with the stopped vehicle's plate and the `ts` cooldown. `pulloverNature` and `pulloverPriority` replace the community's traffic stop preset. With `closeOnPulloverEnd` the stop closes when the pullover ends; without it the stop stays open for dispatch and the unit is cleared from it, so the next callout is free to start. |
| Pursuit started and ended | With `pursuitStatus` set, the unit's status changes to it and back to the one before. Both add a note to the stop or callout. |
| Patient delivered to hospital | A note on the EMS or fire unit's call, with the patient's name. |
| First interaction with a ped or vehicle | The ped and vehicle are registered once, so `/name`, `/plate` and the MDT find them. A ped with the same name and date of birth, or a vehicle with the same plate, is never created twice. |
| Shift on or off | With `dutySync` set for the service, the player signs on in that department with their roster callsign (or the callsign of their last shift there), and off again. |

### Records from ERS

| ERS field | CAD field |
| --- | --- |
| `FirstName`, `LastName`, `DOB`, `Gender`, `Address`, `City`, `PostalCode`, `PhoneNumber` | The person's name, date of birth (`dateOrder`: `'dmy'` or `'mdy'` for dates like 04/12/1990), sex and address |
| `License_Car`, `License_Bike`, `License_Truck`, `License_Boat`, `License_Pilot` | The license types in `licenses` (`DL`, `MC`, `CDL`, `BOAT`, `PILOT`). Valid, suspended, revoked or expired from the text; `_Is_Valid` false makes a valid license suspended. No license when ERS shows none. |
| `FlagsOrMarkers` | Person flags |
| `license_plate`, `make`, `model`, `color`, `build_year` | The vehicle |
| `owner_name` | The registered owner, created when the CAD has no ERS person with that name |
| `insurance` | Insured or uninsured |
| `tax`, `mot` | Registration expired when either is false, valid otherwise |
| `stolen` | The stolen flag |
| `bolo`, `bolo_description` | A vehicle BOLO on the plate |

Medical fields are not stored. License numbers, SSNs, VINs and policy numbers are generated by the CAD. People and
vehicles from ERS that no report, BOLO, warrant or call names are removed after 48 hours.

### Dispatch

A dispatcher can send an ERS callout to a unit from the dispatch board (**ERS** on the unit's row), with a callout id
such as `vehicle_theft` or none to let ERS pick one near the unit. The player gets ERS's usual accept or
decline prompt, and the dispatcher sees the answer or ERS's reason (`client_response_timeout`, `player_busy_on_callout`
and so on). The action shows while the resource reports the module, every 5 minutes.

### Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `calloutPriority` | `2` | Priority of a call from a callout (1 to 3). |
| `closeOnComplete` | `true` | Close the call when the callout is completed. |
| `closeOnEnd` | `false` | Close the call when the callout ends for any reason, including a cancel. |
| `disposition` | `'HND'` | The disposition (value or code) the module closes calls with. It must be in the community's list. |
| `pulloverNature`, `pulloverPriority` | `nil` | Replace the traffic stop preset's nature and priority for ERS pullovers. |
| `closeOnPulloverEnd` | `false` | Close the stop when the pullover ends. Off: the stop stays open and the unit is cleared from it. |
| `pursuitStatus` | `nil` | A status code to set during a pursuit. `nil` leaves the status alone. |
| `hospitalNote` | `true` | Note hospital drop-offs on the EMS or fire unit's call. |
| `registerRecords` | `true` | Register ERS peds and vehicles. |
| `dateOrder` | `'dmy'` | How to read ERS dates with slashes. |
| `licenses` | see Records from ERS | ERS license line to the community's license type code. |
| `dutySync` | every service `false` | Department abbreviation per ERS service (`police`, `fire`, `ambulance`, `tow`), for example `police = 'LSPD'`. `false` leaves that service's shifts out of the CAD. |
| `pushShift` | `false` | `/duty` and `/offduty` in a synced department also start and end the ERS shift, so one clock-in drives both. |
| `hidePanels` | `true` | Hide ERS's own vehicle and ID card panels, so the CAD's are the only ones. |
| `offerTimeout` | `15000` | Milliseconds a dispatcher's offer waits for the player's answer. |
| `cooldown` | `3` | Seconds between ERS events of one kind per player. |
| `calloutCooldown` | `20` | Seconds between accepted callouts per player. |

ERS records need the **lookup** scope on the key; the rest uses **units** and **calls**.

## Wraith ALPR

With Wraith ARS 2X (`wk_wars2x`) on the server, the plate reader warns an on-duty officer when it reads a plate the
CAD has flagged, and a plate lock shows the full return. The module listens to the `wk:onPlateScanned` and
`wk:onPlateLocked` events Wraith already sends; nothing in Wraith is edited and there is no dependency line. With
`Config.modules.wraith = 'auto'` it switches on when Wraith starts and logs `Wraith not detected` once while it waits.

Supported and tested: upstream WolfKnight98 1.3.1 and the Statewide build of Wraith (`1.3.1-statewide.1` and later).
Forks that keep the same two events work the same way as upstream.

### The Statewide build

The resource reads Wraith's manifest `version` when it starts and again whenever Wraith restarts. A version ending in
`-statewide.<n>` switches on the Statewide path; any other version keeps the upstream path, so swapping builds needs
no setting change and no restart of `statewide`. On the Statewide build:

- `lockOnHit` locks the camera through Wraith's `SetPlateLock` export. Wraith locks only a camera that still shows
  that plate and is unlocked, and never unlocks one.
- A hit also shows under the plate reader: the most serious flag as the title and the other flags below it, as a
  critical alert for stolen, owner warrant and BOLO and a warning for registration, insurance and not registered.
  `radarAlerts = false` turns this off; the chat line and notification stay.
- The plate reader's send-to-MDT button runs the same vehicle lookup as a lock, as that officer, within
  `lookupsPerMinute`, and only while the officer is on duty.
- When the read names the vehicle and the server sees that vehicle carrying the same plate, `proximityCheck` measures
  it directly instead of walking every vehicle. Anything else falls back to the walk.

On start the resource loads the community's flagged plates once and keeps them current from the CAD's event feed, so
a clean plate costs nothing and a flag set or cleared on the website applies to the next read without a restart.

| Flag | Alert | Tone |
| --- | --- | --- |
| Stolen | `STOLEN` | `alpr-stolen` |
| The registered owner has an active arrest warrant | `OWNER WARRANT` | `alpr-warrant` |
| An active vehicle BOLO on the car or plate | `BOLO` | `alpr-bolo` |
| Registration expired or suspended | `REG INVALID` | `alpr-registration` |
| Uninsured or insurance expired | `NO INSURANCE` | `alpr-insurance` |
| A flagged plate with no registered vehicle | `NOT REGISTERED` | `alpr-registration` |

A read alerts only the officer whose radar read it, in chat and as a notification, labelled by camera:
`FRONT ALPR ABC123: STOLEN, OWNER WARRANT`, with the tone of the most serious flag. A lock runs one plate lookup as
that officer, with their own lookup permission, and shows the full return.

A read counts only when the player is on duty in the CAD and sitting in a vehicle, the camera is `front` or `rear` and
the plate is 1 to 8 letters, digits or spaces (placeholders such as `NO PLATE` are dropped). Reads beyond
`readsPerSecond` are dropped. Front and rear cameras, and driver and passenger radars in one car, count once per
plate for `dedupSeconds`; one officer is alerted about a plate once per `alertCooldownSeconds` unless its flags
change.

### Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `resource` | `'wk_wars2x'` | The Wraith resource name. |
| `readsPerSecond` | `4` | Plate reads accepted per player per second. |
| `lookupsPerMinute` | `6` | Lock lookups per player per minute. |
| `hitsPerMinute` | `12` | Hits recorded in the CAD per player per minute. The CAD also accepts at most 12 a minute per unit. |
| `dedupSeconds` | `90` | Seconds a plate read in one car counts once. |
| `alertCooldownSeconds` | `300` | Seconds before the same officer is alerted about the same plate again, and between lock lookups of one plate. |
| `proximityCheck` | `true` | Act on a flagged read or a lock only when a vehicle with that plate is within `proximityMeters` of the officer. Clean reads skip the check. |
| `proximityMeters` | `100` | The distance for `proximityCheck`. |
| `lockOnHit` | `false` | Lock the camera that read a flagged plate, only while that camera is unlocked and still shows that plate. |
| `radarAlerts` | `true` | On the Statewide build, also show each hit under the plate reader. |
| `debug` | `false` | On the Statewide build, print one console line per speed lock by an on-duty officer. |
| `alertOn` | every flag `true`, `notRegistered = false` | Which flags alert (`stolen`, `ownerWarrant`, `bolo`, `registration`, `insurance`, `notRegistered`). |
| `ignoreClasses` | `{ 13, 14, 15, 16, 21, 22 }` | Vehicle classes skipped when the read carries one: cycles, boats, helicopters, planes, trains and open wheel. |

### What is logged

Each alert is recorded in the CAD with the officer's unit, plate, camera, flags, street and postal; it shows in the
officer's returns inbox as an ALPR return, and stolen, owner warrant and BOLO hits alert the dispatch board. A lock
logs one vehicle lookup as the officer. Clean plates are never sent.

The key needs the **lookup** scope.

### Another CAD's Wraith plugin

If another CAD's Wraith plugin runs on the same server, both answer the same reads and the officer gets two alerts.
Turn one of them off.

## LB Phone

With LB Phone 2.9.0 or later started on the server, a text to one of its emergency companies becomes a CAD 911
call, and the CAD answers on the caller's phone. The resource calls LB Phone's documented server exports and listens
to its documented server events. It ships no LB Phone code or files, needs no LB Phone source, and nothing in
`lb-phone` or its config is edited. LB Phone is a paid resource that you buy and install yourself. With
`Config.modules.lbphone = 'auto'` the module switches on when LB Phone starts, in any start order, and logs
`lb-phone not detected` once while it waits.

| From | To | What happens |
| --- | --- | --- |
| A text to a company in `companies` | CAD 911 queue | A pending 911: `[TEXT police] <message>`, at the street and postal of where the sender is (the postal with `nearest-postal` started, else the CAD fills it). When no street can be read, the CAD names the place from its nearest postal; with no position at all it is `Unknown (text 911)`. The `/911` cooldown applies. |
| A shared location | CAD call | On a new call, the call opens at that place. On an open call, the call, its postal and its waypoint move there and it gets a `[CALLER]` note naming the place and postal. A shared location more than 500 m from where LB Phone read the text is ignored, and the call stays at LB Phone's position. |
| Another text from the same number inside 10 minutes | CAD call | A `[CALLER]` note on that call instead of a second call. At most one every 10 seconds and 20 a call; past that the sender is told once that texts are no longer delivered. |
| A dispatcher opens the call | Caller's phone | `Dispatch has your message (call 26-000123).` |
| **Text caller** on the call in the web MDT | Caller's phone | The dispatcher's message, shown `[TO CALLER]` on the call's notes. |
| The call is closed | Caller's phone | `Call 26-000123 closed.` |
| A unit is attached, or a unit presses panic | Officer's phone | An LB Phone emergency alert with the call number, nature and postal. |
| A phone gets a number or changes it, or the player switches character | CAD character | The active character's phone number is set to the in-game number, so returns and the 911 caller field show it. |

An anonymous text opens its own `ANONYMOUS` call with no caller and no callback number, and the resource sends no
phone number with it. It never lands on another call, not even one the same player opened by name, and dispatch
cannot reply to it: there is no **Text caller**, and no opened or closed message reaches the sender. Anonymous texts
share one 30-second cooldown per company on this server, whoever sends them.

Replies go out as a message from `dispatchNumber`; when LB Phone does not deliver it (for example, the caller blocked
that number) they go out as a Messages notification. The console logs which one worked the first time each is used.

Messages from company employees are ignored, and so are texts to companies not in `companies`, from a number no
online player has equipped, or raised by a client. The module registers no net events and sends nothing to any other
player's client. A text is cut to its first 2,000 characters before it is read.

### Setting up LB Phone

- Start LB Phone 2.9.0 or later before or after this resource.
- List the company keys from your `lb-phone/config/config.lua` in `Config.lbPhone.companies`. The value is a label
  for your own reference; `false` turns a company off.
- Players see a company in the Services app through LB Phone's own company config. The module reads the texts itself,
  so it works on a standalone LB Phone with no company employees.

The key needs the **calls** scope, plus **civilian** for the phone number sync.

Confirmed with LB Phone 2.9.0: a message from `dispatchNumber` reaches the caller, and the emergency alert shows on
the lock screen.

### Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `resource` | `'lb-phone'` | The LB Phone folder name, if you renamed it. |
| `companies` | `police = 'leo', ambulance = 'ems', fire = 'fire'` | LB Phone company keys whose texts become 911 calls. |
| `dispatchNumber` | `'911'` | The number replies come from. |
| `callerWindowSeconds` | `600` | How long, since the last text or voice call, more texts from that number land on the same call. |
| `maxCallerNotes` | `20` | Most caller notes on one call. |
| `noteCooldownSeconds` | `10` | Seconds between caller notes from one number. |
| `maxTextLength` | `500` | Longest text kept; the rest is cut. |
| `syncPhoneNumber` | `true` | Set the active character's phone number to the in-game number. |

## Statewide phone app

With LB Phone 2.9.0 or later started, the resource adds a **Statewide** app to every phone. The app's page ships
inside this resource (`modules/phoneapp/ui/`); nothing loads from the internet, and the page holds no API key or CAD
address. It works the same on a standalone LB Phone: it needs none of LB Phone's framework apps (Wallet, Garage, Home
or Services). With `Config.modules.phoneapp = 'auto'` the app is added when LB Phone starts, in any start order, and
added again whenever LB Phone restarts. The `lb-phone not detected` line covers this module too.

| Tab | Shows |
| --- | --- |
| Characters | The player's characters, and **Set active** (the same as `/setciv`). |
| Vehicles | The active character's vehicles: plate, make, model, color, registration, insurance and stolen. |
| Licenses | The active character's licenses: number, status, expiry and points. |
| Tickets | The active character's citations: fine, points, court date and place, plea and case status. |
| 911 | The player's open 911 and 311 calls: number, status and how many units respond. It changes as dispatch opens, attaches to and closes the call. |

While the player has a unit on duty, **On duty** shows four more tabs:

| Tab | Does |
| --- | --- |
| My call | The attached call's number, nature, location, postal and its newest notes. |
| Status | One button per status code of the unit's department, the same as `/status`. |
| Panic | Hold the button for 1.5 seconds to raise panic, the same as `/panic`. |
| Run | A plate or a name, the same as `/plate` and `/name`; the CAD decides whether the unit may run it. |

Every action goes through the same code, cooldowns and messages as the chat commands, and its answer shows in the app
instead of chat. Creating characters, registering vehicles, applying for licenses and entering pleas stay on the
community website.

The key needs the **civilian** scope for the civilian tabs, **calls** for My call, **units** for Status and Panic and
**lookup** for Run.

### How the app talks to the server

The app calls its own resource's NUI callbacks, the client passes each request to the server on one net event, and
the answer comes back to that player only:

| Event | Direction | Payload |
| --- | --- | --- |
| `statewide:phone` | client to server | `{ id, action, args }`: `id` a whole number, `action` one of `me`, `characters`, `setActive`, `profile`, `my911`, `call`, `statusCodes`, `status`, `panic`, `plate`, `name` |
| `statewide:client:phone` | server to that client | `id, { ok, messages, data }` |
| `statewide:client:phonePush` | server to that client | `{ type }`: `unit`, `call`, `my911` or `character`, passed to the app with `SendCustomAppMessage` |

The server reads the player from `source` only; `args` holds only `ssn`, `code`, `plate`, `first` and `last`, each
length checked, and anything else is refused before any CAD request. A player gets one request every
`requestIntervalMs` and one at a time, the officer actions only with a unit on duty, and the CAD answers only for the
player's own characters and calls.

Still to confirm on a live server: that the page takes LB Phone's messages from the frame LB Phone draws, the sharpness
with `fixBlur`, and how soon a push reaches an open app.

### Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `defaultApp` | `true` | Put the app on every phone. With `false` players install it from LB Phone's app store. |
| `requestIntervalMs` | `500` | Shortest time between two requests from one player (at least 250). |

## Events for other resources

The resource long-polls the CAD (`GET /api/v1/events`, one loop, `wait=4`) and fires these **server-local** events
(they are never net events, so clients cannot fake them):

| Event | From | Payload (selected fields) |
| --- | --- | --- |
| `statewide:911` | `call.911` | `number, priority, nature, location, postal, discordIds` |
| `statewide:311` | `call.created` | `number, nature, location, postal` |
| `statewide:priorityCall` | `call.priority_created` | `number, priority, nature, location, postal, origin` |
| `statewide:panicCleared` | `unit.panic_cleared` | `discordId, callsign, department, departmentId, departmentType` |
| `statewide:signal` | `signal.declared`, `signal.cleared` | `signalId, scope, departmentCode, number, by, reason`, then `true` when declared |
| `statewide:panic` | `unit.panic` | `discordId, callsign, department, departmentId, departmentType, callNumber, location, postal` |
| `statewide:attached` | `call.unit_attached` | `number, nature, location, postal, discordId, primary` |
| `statewide:callClosed` | `call.closed` | `number, disposition, discordIds` (and `callerPhone`, see below) |
| `statewide:callOpened` | `call.opened` | `number, priority, nature, location, postal` (and `callerPhone`) |
| `statewide:callerMessage` | `call.caller_message` | `number, body` (and `callerPhone`) |
| `statewide:forcedOff` | `unit.forced_off` | `discordId, callsign, department, reason, by, byDepartmentId, byDepartmentType, byDepartment` |
| `statewide:detached` | `call.unit_detached` | `number, discordId, by, self, byDepartmentId, byDepartmentType, byDepartment, discordIds` |
| `statewide:callNote` | `call.event` | `number, kind, author, body, byDiscordId, byDepartmentId, byDepartmentType, byDepartment, discordIds` |
| `statewide:citationRequested` | `citation.signature_requested` | `recordId, number, discordId, membershipId` |

`callerPhone` is the callback number of a 911 call this server created, sent only to the key that created it,
including the sealed number of an anonymous call another source created. It stays on the server: the resource never sends it to a player's
client.

Every payload that names a player also carries `membershipId` beside `discordId` (and `membershipIds` beside
`discordIds`). `discordId` is `nil` for a player who joined with a `license:` identifier only.

Two more server-local events follow the citation sheet. `statewide:citationSigned` fires with `(source, { citation, number })` after
the CAD stored the signature. `statewide:citationKept` fires with `(source, item)` after the CAD recorded the keep,
before any item is added, so an inventory without the ox_inventory exports can hand out its own item from it. Neither
fires for a citation the CAD refused.

A sign-on, sign-off or status change made on the web MDT, the tablet or by a dispatcher (`unit.signed_on`,
`unit.signed_off`, `unit.status`) refreshes that player's duty state in game within one poll, so `/panic`, the live
map and the 911 and attach pushes follow the MDT. A sign-on or sign-off made outside the game also tells the player in
chat.

An active character set or cleared on the website or through the API (`character.active_changed`, which needs the
`civilian` scope on the key) reaches the game the same way: `/getciv` and the `/id` card show the new character within
one poll.

**Map it** on a call in the web MDT (`unit.waypoint`, which needs the `units` scope on the key) sets a GPS waypoint at
the call for the member who pressed it, with a `Waypoint set: 26-000044 (8047)` notification. The resource sends it to
the one connected player with that Discord account and to nobody else; when that player is not on the server it is
dropped. A key bound to a game server only receives waypoints for units that server signed on.

```lua
AddEventHandler('statewide:911', function(call)
  print(('911 %s at %s'):format(call.number, call.location or '?'))
end)
```

The same events reach on-duty players in chat and as a notification: 911s to LEO and Fire/EMS (with a map blip at
the caller for 120 s when the call came from in game), non-emergency calls (`/311`, the website's Non-emergency
choice, a parked car reported stolen) to LEO and dispatch, panics to every on-duty player, an attach only to the attached
player, a close to the call's units, a forced sign-off to its player, a note to the call's other units, a clear by
dispatch or another unit to the cleared unit. Under agency isolation the note's author, the unit that cleared you and the unit
that signed you off read as their department (or type), as the MDT shows them. The first unit to attach to a call placed with `/911`, `/911a` or `/311`
tells its caller once (`Call 26-000123: units responding.`). Notes, clears and duty changes that arrive together are
sent as one burst: the three newest notes, a count for the rest, one clear per call and the last duty change. With **Agency isolation** on (**Settings > Dispatch > Calls**
in the CAD), a panic from another agency's unit names only its department, or its type (LAW, FIRE, EMS) when isolation
is by department type, with no callsign or call number, as the CAD shows it. Dispatch units and players who may view
every agency see it in full.

## Framework sync

Characters, vehicles and licenses from your framework's database show up in the CAD, linked to each player's account.
Synced fields (name, date of birth, gender, height, weight and phone; plate, make, model, color and year; license class
and expiry) are read-only on the website. Flags, records, warrants, a license's status and points, and anything else the
CAD keeps stay editable there. Nothing is written back to the game database.

1. Add the `sync` scope to the resource's API key on the CAD's API keys page (owner only).
2. Start `oxmysql` before `statewide`.
3. Set `Config.sync.enabled = true` and map your tables in `Config.sync.standalone`. Each entity names its `table`, its
   `id` column and its `owner` column, then one column per field; `false` or a missing field is not synced. A character's
   `owner` holds the player's identifier (`discord:...`, `license:...` or the bare value); a vehicle's or license's
   `owner` holds the owning character's `id`. A license's `type` must match a license type name or code in the CAD.
4. Restart the resource. With `resyncOnStart`, every row is sent once after start; `statewide_resync` in the server
   console sends them again. Running it twice creates nothing new.

To send a change at once, list your framework in `Config.framework.allow` and call the export with the row as it is in
the database, right after you save it:

```lua
exports['statewide']:SyncCharacter(row)
exports['statewide']:SyncVehicle(row)
exports['statewide']:SyncLicense(row)
```

Changes are sent in batches every `flushSeconds`. A character whose player is not a member of the community yet is
skipped until the next push or resync. A character is never moved from one account to another.

## Connect your framework

When a player picks a character in their framework, the CAD follows: a civilian character becomes their active
character (`/getciv`, the `/id` card and the tablet show it), and a department character clears the active character
and signs them on in that department. Switching characters signs off the unit the resource signed on; leaving the
server signs everyone off as before. `/setciv`, `/duty` and the website keep working beside it.

The API key needs the `civilian`, `units` and `sync` scopes. Each player is known by the Discord account on their
connection, read on the server; a player without Discord gets the usual message and nothing is sent.

The first time a framework character reaches the CAD, it is linked to the player's CAD character with the same first
name, last name and date of birth, when they have exactly one, so characters made on the website keep their records.
Otherwise a new CAD character is made. A framework character already linked to another account is refused and stays
where it is. Character limits and DMV approval do not apply to these characters.

The CAD stays in charge of departments. A sign-on goes through the same check as `/duty`: a player who is not on that
department's roster in the CAD is refused, whatever department the framework gives them. Without a callsign from the
framework, the unit takes the member's roster callsign, else their last one in that department; a member with neither
is told to go on duty once with `/duty`.

Changes for one player run one at a time, in the order they came in. When the CAD cannot be reached or answers with a
server error, the change is tried again after 5, 15 and 45 seconds, then left until the player's next change; a newer
change of the same kind replaces the retry. A refusal from the CAD, such as a player who is not a member, is not
retried.

A refusal prints one console line, at most once a minute per player and reason:

```
[statewide] framework c7fw refused for 12: not_member
```

### NAT Framework V2

On by default while the NAT resource (`Config.nat.resource`, `framework` by default) and `oxmysql` are started. Every
`pollSeconds` the resource reads which character each player is playing, then loads that character from NAT's
`characters` table only when its `discord` column matches the player's own Discord account; any other character is
refused and nothing is sent. Map each department key in `Config.nat.departments`:

```lua
Config.nat.departments = {
  civ_level = 'civilian',
  lspd_level = 'LSPD',
  bcso_level = 'BCSO',
  fire_level = 'SAFD',
}
```

NAT characters carry no callsign, so the unit takes the member's roster callsign. A key with no mapping does nothing
and prints one line naming it.

### C7 Framework V3

Off by default. Set `Config.modules.c7fw = 'auto'` to turn it on while `c7-scripts-framework-v3` (`Config.c7fw.resource`) is started. The resource follows C7's character
loaded, unloaded and modified events and reads the character with C7's `GetCharCopy`, and only uses it when its Discord
account is the player's own. A department character signs on with its C7 callsign. Map each department in
`Config.c7fw.departments`:

```lua
Config.c7fw.departments = {
  civilian = 'civilian',
  LSPD = 'LSPD',
  BCSO = 'BCSO',
}
```

Starting the framework after `statewide` turns its module on without a restart, and the characters already playing are
picked up at once.

### Any other framework

List your resource in `Config.framework.connectors`, then call these server exports from it:

```lua
local cad = exports['statewide']
cad:SetActiveCharacter(source, { id = 42, firstName = 'Ryker', lastName = 'Cohen', dob = '1990-01-01', gender = 'Male' })
cad:ClearActiveCharacter(source)
cad:SetDuty(source, true, { department = 'LSPD', callsign = '1A-12' })
cad:SetDuty(source, false)
```

`id` is the character's id in your framework, `dob` is `YYYY-MM-DD`, `gender` and `callsign` are optional. Each export
checks its arguments at once and returns `true`, or `false` and one of `not_allowed`, `not_connected`, `no_discord`,
`validation` or `busy` (16 changes for that player are already waiting); the CAD request runs afterwards, so the call
never waits. A resource not on the list, or `statewide`
itself, gets `false, 'not_allowed'` and nothing is sent. `SetDuty` signs off only a unit it signed on.

After a character is made active, from any of these, the server-local event `statewide:characterLinked` fires:

```lua
AddEventHandler('statewide:characterLinked', function(src, character)
  print(('player %d is %s (%s %s), new: %s'):format(src, character.ssn, character.externalSource, character.externalId, tostring(character.created)))
end)
```

`externalSource` is `nat`, `c7fw` or `resource:<your resource>`. `getActiveCharacter`, `getUnit` and `isOnDuty` read the
result.

## Exports

Read-only copies of the server cache. They never make an HTTP request, so no other resource can use the key. The
exceptions are `create911`, `setSceneMarker` and `clearSceneMarker` below and the framework exports (see Connect your
framework), which only the resources you list can call.

```lua
local cad = exports['statewide']
cad:getUnit(source)            -- {callsign, department = {abbreviation, type}, status = {code, meaning}, isPanic, ...} or nil
cad:getActiveCharacter(source) -- {id, ssn, firstName, lastName, dob} or nil
cad:isOnDuty(source)           -- boolean
cad:isClockedIn(source)        -- boolean (clocked in with /clockin or a framework duty toggle)
cad:getPostal(source)          -- '1234' or nil (on duty, or from the player's last /911 or /311)
cad:getLocationLabels(source)  -- {street, crossStreet, postal} or nil (no city or county; same rule)
cad:getSceneMarkers()          -- {{id, kind, label, x, y}, ...} the scene markers on the map now
cad:aop()                      -- 'Blaine County' or nil, the community's current area of play
```

The current area of play is also in the server convar `statewide_aop` (empty when none is set), so another server
script reads it with `GetConvar('statewide_aop', '')`. Both follow the CAD as soon as staff change it.

### State bag and unit list for UIs

The player state bag `statewide:unit` mirrors an on-duty player's unit for every client, so `Config.stateBag` decides
what it carries:

| `Config.stateBag` | Bag value |
| --- | --- |
| `'auto'` (default) | Full when the community's agency isolation is off, minimal when it is on. The CAD sends the setting with each player's duty state and again as soon as it changes. |
| `'full'` | `{onDuty, callsign, department, status, isPanic}` for everyone. With isolation on this shows every agency's callsigns to every client, so set it only if you accept that. |
| `'minimal'` | `{onDuty, status}` only. |

Off duty the bag is `nil`. A HUD that shows callsigns should read the unit list instead. Each player gets it with only
what their own agency may see, by the CAD's isolation rules, when they are on duty or hold `agencies.view_all`. With
isolation on, an off-duty player with a seat in a department other than Civilian gets it too. With isolation off the
CAD sends no seats, so off-duty players without `agencies.view_all` get no list. Everyone else gets none, and
`getUnits` returns `{}` for them:

```lua
AddEventHandler('statewide:units', function(units) end)
local units = exports['statewide']:getUnits()
```

Each entry is `{id, onDuty, status}` plus either `callsign`, `department` and `isPanic`, or `masked = true` and the
`department` label the CAD shows for that unit. `id` is the player's server id. Within a second of any unit change the
server sends only what changed, and `statewide:units` fires with the whole updated list.

Compatibility: before this setting the bag always carried `{callsign, department, status, isPanic}`. A UI that reads
`callsign` or `department` from it keeps working while isolation is off. With isolation on it gets `nil` for both;
switch it to `statewide:units`, or set `Config.stateBag = 'full'`.

By default a client can write its own player state bag. The server puts its own value back within a second, but until
then a cheat can make a HUD show a callsign it does not have.
The resource itself never reads authority from the bag, and server code in other resources should call
`cad:isOnDuty(source)` instead. To stop clients writing state bags at all, add `setr sv_stateBagStrictMode true` to
`server.cfg`. It applies to every resource, so first check that none of yours set state bags from a client.

### create911

A server-side export that lets another resource you trust (a robbery script, a shots-fired detector) open a 911 in the
CAD. List the resource in `shared/config.lua`:

```lua
Config.scriptCalls = { allow = { 'sw-robbery' }, cooldown = 60 }
```

Then, from that resource's server code (use the folder name you installed this resource under):

```lua
local ok, reason = exports['statewide']:create911({
  text = 'Silent alarm, Fleeca Bank',
  street = 'Hawick Ave',
  crossStreet = 'Meteor St',
  postal = '7193',
  coords = vector3(-353.6, -54.1, 49.0),
}, function(result)
  if result.ok then print('911 opened: ' .. result.callNumber) else print('911 failed: ' .. result.code) end
end)
```

| Field | Rules |
| --- | --- |
| `text` | Required, 1 to 1,000 characters. |
| `street`, `crossStreet` | Optional, at most 64 characters each. The call's location is `street`, `street / crossStreet`, or `Unknown`. |
| `postal` | Optional, digits only, at most 10. A postal that is not on your community's list is dropped and the call still goes through. |
| `coords` | Optional `vector3`, used only for the map blip in game. |
| `anonymous` | Optional boolean. |

- The export returns `true` once the call is on its way, or `false` and a reason: `not_allowed` (the resource is not
  on the list, or the call came from inside this resource), `validation` (a field breaks the rules above) or
  `cooldown` (that resource called less than `cooldown` seconds ago).
- The callback is optional and runs when the CAD answers, with `{ ok = true, callNumber = '26-000123' }` or
  `{ ok = false, code = 'rate_limited' }`. An error inside it is caught and printed, and never stops this resource.
- Dispatch sees the call in the 911 queue with Source `SCRIPT`, and the call's Info tab names the resource. On-duty
  units get the same chat line and blip as a `/911`, and with no dispatcher on duty the same fallback alert.
- The call uses this server's API key, so it counts against the same rate limit as every other request and is logged
  under the key in the CAD audit log with the resource name. The key itself never leaves this resource.
- Each refusal prints one console line, `[statewide] create911 refused from <resource>: <reason>`, at most once a
  minute per resource and reason.

### setSceneMarker and clearSceneMarker

Server-side exports that let a resource you trust put a scene marker on the CAD's live map, and every on-duty player's
map as a blip, then take it off again. List the resource in `shared/config.lua`:

```lua
Config.sceneMarkers = { blips = true, everyone = false, allow = { 'sw-fires' }, cooldown = 5 }
```

Then, from that resource's server code:

```lua
local cad = exports['statewide']
cad:setSceneMarker({
  kind = 'fire_scene',
  label = 'Structure fire, Grove St',
  coords = vector3(-50.4, -1755.2, 29.4),
}, function(result)
  if result.ok then markerId = result.id else print('marker failed: ' .. result.code) end
end)

cad:clearSceneMarker(markerId, function(result) end)
```

| Field | Rules |
| --- | --- |
| `kind` | Required: `roadblock`, `fire_scene`, `crime_scene`, `hazard`, `staging` or `landing_zone`. The community chooses which kinds it uses under **Settings > MDT**; a kind it turned off answers `validation_failed`. |
| `label` | Optional, at most 60 characters. Without one the blip and the map show the kind's name. |
| `coords` | Required `vector3` (or `x` and `y` fields). Only `x` and `y` are kept. |

- Both exports return `true` once the request is on its way, or `false` and a reason: `not_allowed`, `validation` or
  `cooldown`, as for `create911`. The callback gets `{ ok = true, id = '<marker id>' }` or `{ ok = false, code = 'limit_reached' }`
  (a community holds at most 50 markers).
- A marker set by dispatch in the CAD reaches the game the same way, and so does a clear: the blip appears and goes away
  for every player who sees the markers, within a few seconds. Markers stay until they are cleared, also across restarts.
- The requests use this server's API key with the **calls** scope, and the CAD audit log lists them under the key.

## How it behaves

- Identity comes only from the player's `discord:` and `license:` identifiers, read on the server. Command text and street labels from
  clients are length capped and rate limited, and nothing else a client sends is trusted. Vehicle make and model are
  read on the server (see Commands).
- With a community key the resource sends a Discord player's `license:` identifier beside their Discord ID. The CAD
  records it on first sight and refuses a player whose license is linked to another account (`identity_mismatch`), with
  an audit row and a staff alert. A player with no `license:` identifier is never refused for it.
- `/link` sends only the license read on the server and the code the player typed. The code names the account that
  made it, so a shared code can link a game account only to that account, and never one another account already holds.
- The tablet's NUI (`nui/`) holds no key, loads nothing remote but the sign-in link the server sends, and takes
  messages only from the game, never from another resource's page. The
  `statewide:tablet` net event carries no data, and each player may open the tablet once per `Config.tablet.cooldown`.
- The call HUD shows only calls the CAD returns for that player. Its one net event, `statewide:callHud`, carries a call
  number that must be one the server sent that player, at most once per `Config.callHud.cooldown`.
- Positions, speed and vehicle type are read on the server (OneSync). On-duty clients send only street, cross street, postal
  and zone labels, when they change, through the one net event `statewide:labels` (rate limited and length capped); an
  off-duty client sends them once when the server asks for a `/911` or `/311`. When an officer accepts an ERS callout,
  the server asks that officer's client for the street and zone at the callout's position; the answer comes back on
  `statewide:labelsAt` and is taken only from that player, once, for that ask. On-duty units' changed
  labels and positions go to the CAD every interval, in `PATCH /units/locations` batches of at most 128 units.
- The server keeps one unit list per agency view and updates only the entries of units that changed, then sends only
  those changes, on a latent event that does not block the player's connection. Its one net event,
  `statewide:unitsSync`, carries no data and only asks the server to resend that player's list in full, at most once
  every 5 seconds.
- Vehicle registration (`Config.registration`) uses one more net event, `statewide:seat`, with no data. The client sends it when its player takes a driver seat; the server then reads the seat, vehicle, plate, model and population type itself, at most once every 2 seconds per player, and does nothing at all when the mode is `'off'`. In `'enforce'` the server refuses the gated actions whether or not the client sent it, and sets the `statewide:unregistered` bag on the vehicle so the driver's client stops the engine; the refusal does not depend on that bag.
- Each player who gets the unit list has their seats and `agencies.view_all` read again from the CAD at least every
  120 s, spread across players, and at once when a dispatcher forces them off duty. A player who loses a seat or
  `agencies.view_all` gets a full masked list on the next send. The `statewide:unit` bag is set only when its value
  changes, so a recheck that finds nothing new sends nothing to other clients.
- At most `statewide_http_concurrency` requests to the CAD are in flight at once. A request holds its place until
  FXServer hands back the answer, even after the resource stops waiting at 15 s. Panic, duty and status changes, 911
  calls and the event stream go first. Reads for joining players and the 120 s recheck go last and never take the last
  two places (one when the setting is 2 or 3), so a panic during a full server restart is sent at once. Reads for joining
  players and reports of dropped units go out ten per second: players with a unit on duty first, then players who held
  a responder seat in the last 30 days (their Discord IDs, kept in server KVP `statewide:responders`), then everyone
  else.
- Server status: every 60 s the resource sends `PUT /server/status` with only the number of connected players and
  `sv_maxclients`, never names, identifiers or addresses; on a txAdmin shutdown warning it sends the server as offline.
  The key needs the **units** scope; without it the console says so once and the reports stop. In the CAD, choose under
  **Site > Server Status** whether the server shows on your public site, its name there and its cfx.re join code for the
  Connect button. A server that stops reporting shows offline after three minutes.
- Errors: FXServer hands Lua only `HTTP <status>: <body>` on a refusal; the resource reads the problem code from it
  and shows the player a line from `shared/locale.lua`. FXServer drops a call after 5 s when the CAD has sent nothing back,
  and the resource stops waiting after 15 s for an answer that has started. Either way a command that changes something
  tells the player the CAD is slow, and tells them again when a late answer shows it went through (with the call number
  for `/ts` and `/attach`; a `/status` typed as a code, a label or a radio code counts as through when the unit shows it); a call FXServer dropped gets no late answer. A lookup says the CAD did not answer. A command typed while
  the player's last one is still out is answered with a wait line. A 429 on a
  player's command goes back to the player at once; a background call waits `retryAfter` and retries once when that
  is 5 s or less; a failed read (a 5xx or no connection on a GET) is retried
  once after about a second. A write is never sent twice, except a report of a dropped unit (below).
- The events loop backs off from 1 to 30 s on errors and adopts the server's cursor on `410 resync`.
- When the CAD does not answer a 911, 911a or 311, the call is saved and resent with backoff for up to 9 minutes;
  each call carries a `clientRef`, so a resend never opens a second call.
- A unit status changed in the CAD reaches the cache within a second, so exports and the state bag stay right, and
  `/panic` re-reads the unit before it clears a panic, so a panic cleared on the web is raised again, not cleared.
- `statewide_api_url` must be `https://`. Plain `http://` works only for `localhost` and `127.0.0.1`; anything else is refused with one console line, so the API key never travels in clear text. The tablet opens only an `https://` sign-in link (plain `http://` on those two hosts only).
- A player who leaves with a unit on duty is reported to the CAD (`POST /units/{discordId}/connection`); the CAD,
  never the game server, decides from the community's grace whether the unit is kept with a DC badge or signed off.
  When the CAD does not answer, the report is resent with backoff (at most 30 s apart) until the CAD takes it or the
  player is back in game. The CAD applies a report once however often it arrives, and a player who rejoins while one
  was out is read again, so a late report never leaves them marked dropped.
- On start, and after the events cursor resyncs, it signs off game units this server signed on whose player is no
  longer connected (units from other servers on the same key are left alone); on a txAdmin shutdown warning it signs off
  every unit it knows.

## Attributions

Written from scratch. Command and event ideas were studied, never copied, from public CAD integrations; no code from
ImperialCAD or SonoranCADFiveM is included, and nothing from `ox_lib`, `qb-core` or `qbx_core` is vendored. Wraith ARS
2X event names and arguments are used for compatibility only; Wraith is MIT licensed by WolfKnight98 and is not
bundled. The ALPR tones are original. FXServer behavior (the 5 s no-body timeout, `errorData` on errors,
`PerformHttpRequestAwait`) follows `citizenfx/fivem` (MIT). The make and model names in `server/vehicles.lua` are the
game's own English text, listed from the public `DurtyFree/gta-v-data-dumps` vehicle data. The phone app's
registration follows the field set of `lbphone/lb-phone-app-template` (MIT, Copyright (c) 2023 LB); no template code,
LB Phone code or LB Phone file is included.

## Links

- Website: [statewide.gg](https://statewide.gg)
- Install guide and full documentation: [docs.statewide.gg](https://docs.statewide.gg/developers/fivem-resource)
- Help and announcements: the [Statewide Discord](https://discord.gg/xZHGHVAe3V)
- Bugs in this resource: [open an issue](https://github.com/StatewideSoftware/statewide-fivem/issues) with your server
  console output, and remove your API key from anything you paste.

## License

MIT. See [LICENSE](LICENSE).
