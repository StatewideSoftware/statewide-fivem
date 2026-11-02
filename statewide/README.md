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
- Night's ERS: callouts, pullovers and records become CAD records (see Night's ERS).
- Lookups and civilians: `/plate`, `/name`, `/regveh`, `/setciv` and the other civilian commands (see Commands).
- License cards: `/id` and `/giveid` show a character's license card over the game view (see License card).
- Unit tracking: on-duty positions reach the live map every few seconds, and a unit can hide itself with
  `/tracking off` where the community allows it.
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

## Commands

Every command is registered server side from `Config.commands` in `shared/config.lua`. Rename an action, add aliases
or turn it off; chat suggestions follow the configured names. Two actions may not share a name. If they do, the console
prints the clash and registers no command until it is fixed.

```lua
Config.commands.duty = { name = 'clockin', aliases = { 'onduty' }, enabled = true }
Config.commands.regveh.enabled = false
```

| Action | Default | What it does |
| --- | --- | --- |
| `duty` | `/duty <department> [callsign]` | Signs on duty (department abbreviation). With no callsign, your roster callsign is used, else the one from your last shift there. |
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
| `Config.cooldowns` | `default` 2, `911` 30, `311` 30, `panic` 30, `plate` 5, `name` 5, `ts` 10, `note` 5, `link` 10 | Seconds between uses per player. `default` applies to every command, and a player's next command waits until the last one has finished. `911` and `911a` share the `911` cooldown, `311` and `311a` the `311` one; `panic` counts only when raising. The API limit is per key, so one player spamming would slow the whole server down. |
| `Config.chat` | `{66, 135, 245}`, `CAD` | Chat line color and prefix. |

### Duty and units

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.stateBag` | `'auto'` | What the `statewide:unit` state bag carries: `'auto'`, `'full'` or `'minimal'` (see Exports). |
| `Config.attach` | `waypoint = true`, `onScene = true` | When a unit is attached to a call, `waypoint` sets the officer's GPS to the call. `onScene` switches an en route unit to On Scene once it is inside the community's On scene within distance (MDT settings, Arrival) for two position reads in a row; the server reads the position, and an empty distance in the CAD turns it off. A manual status change after the attach is never overridden. |

### 911

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.blips` | `call911 = true`, `seconds = 120` | A 911 from in game drops a blip at the caller for on-duty LEO and Fire/EMS for `seconds`. |
| `Config.scriptCalls` | `allow = {}`, `cooldown = 60` | Resources allowed to raise a 911 with the `create911` export, by resource name, and the seconds between calls per resource (see Exports). The empty list turns the export off. |

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
| `Config.modules` | `ers = 'auto'` | Optional integrations. `'auto'` turns one on when its resource is started (now or later), `true` forces it on, `false` leaves it off and registers nothing. |
| `Config.ers` | see Night's ERS | The Night's ERS integration. |

### Optional features

| Setting | Default | What it does |
| --- | --- | --- |
| `Config.citation` | `enabled = true`, `cooldown = 2`, `inventory = 'ox_inventory'`, `item = nil` | When an officer asks for a signature on a citation, the cited player gets the sheet in game, if they are on the server with Discord; a player signed in through a linked game account opens it with `/citations`. The API key needs the `civilian` scope. `item` names an item in an inventory resource with the ox_inventory server exports (`CanCarryItem`, `AddItem`); with it set and that resource started, Keep adds one item per citation, its metadata `citation`, `number`, `label`, `description` and `fine`. Without it Keep only records the keep and fires `statewide:citationKept`. `cooldown` is the seconds between two presses on the sheet. |
| `Config.idCard` | `handover = false`, `distance = 3.0`, `seconds = 15`, `defaultType = 'driver'`, `nui = true` | `distance` is how close, in meters, the other player must be for `/giveid` (and for `/id` with `handover` on, which also plays the hand-over animation). The card closes after `seconds`, on a second `/id`, with `/hideid`, or with Escape or Backspace. `defaultType` is the license `/id` shows with no type: `'driver'` matches the codes `DL`, `DRV` and `DRIVER` or a license whose name starts with Driver; anything else is a license type code. `nui = false` prints the card to chat instead. |
| `Config.photoHosts` | `'.statewide.gg'`, `'.r2.cloudflarestorage.com'` | Hosts the license card loads a character photo from, over https. A leading dot allows every subdomain. A photo link on any other host shows No photo. Add your storage host if you run your own CAD. |
| `Config.photoDevHttp` | `false` | For local development only. `true` lets the card load a photo over plain `http` from `localhost` or `127.0.0.1`, and only when that host is also in `Config.photoHosts` (add `'localhost'` there). Every other photo needs https on a listed host. Leave it `false` on a live server. |

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
loaded after 10 seconds, the window shows an error with a **Close** button. While it is signing in or showing an error,
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

## Events for other resources

The resource long-polls the CAD (`GET /api/v1/events`, one loop, `wait=4`) and fires these **server-local** events
(they are never net events, so clients cannot fake them):

| Event | From | Payload (selected fields) |
| --- | --- | --- |
| `statewide:911` | `call.911` | `number, priority, nature, location, postal, discordIds` |
| `statewide:311` | `call.created` | `number, nature, location, postal` |
| `statewide:panic` | `unit.panic` | `discordId, callsign, department, departmentId, departmentType, callNumber, location, postal` |
| `statewide:attached` | `call.unit_attached` | `number, nature, location, postal, discordId, primary` |
| `statewide:callClosed` | `call.closed` | `number, disposition, discordIds` |
| `statewide:forcedOff` | `unit.forced_off` | `discordId, callsign, department, reason, by, byDepartmentId, byDepartmentType, byDepartment` |
| `statewide:detached` | `call.unit_detached` | `number, discordId, by, self, byDepartmentId, byDepartmentType, byDepartment, discordIds` |
| `statewide:callNote` | `call.event` | `number, kind, author, body, byDiscordId, byDepartmentId, byDepartmentType, byDepartment, discordIds` |
| `statewide:citationRequested` | `citation.signature_requested` | `recordId, number, discordId, membershipId` |

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

## Exports

Read-only copies of the server cache. They never make an HTTP request, so no other resource can use the key. The
exceptions are `create911`, `setSceneMarker` and `clearSceneMarker` below, which only the resources you list can call.

```lua
local cad = exports['statewide']
cad:getUnit(source)            -- {callsign, department = {abbreviation, type}, status = {code, meaning}, isPanic, ...} or nil
cad:getActiveCharacter(source) -- {id, ssn, firstName, lastName, dob} or nil
cad:isOnDuty(source)           -- boolean
cad:getPostal(source)          -- '1234' or nil (on duty, or from the player's last /911 or /311)
cad:getLocationLabels(source)  -- {street, crossStreet, postal} or nil (no city or county; same rule)
cad:getSceneMarkers()          -- {{id, kind, label, x, y}, ...} the scene markers on the map now
```

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
  for `/ts` and `/attach`); a call FXServer dropped gets no late answer. A lookup says the CAD did not answer. A command typed while
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
ImperialCAD or SonoranCADFiveM is included, and nothing from `ox_lib`, `qb-core` or `qbx_core` is vendored. FXServer
behavior (the 5 s no-body timeout, `errorData` on errors, `PerformHttpRequestAwait`) follows `citizenfx/fivem` (MIT).
The make and model names in `server/vehicles.lua` are the game's own English text, listed from the public
`DurtyFree/gta-v-data-dumps` vehicle data.

## Links

- Website: [statewide.gg](https://statewide.gg)
- Install guide and full documentation: [docs.statewide.gg](https://docs.statewide.gg/developers/fivem-resource)
- Help and announcements: the [Statewide Discord](https://discord.gg/xZHGHVAe3V)
- Bugs in this resource: [open an issue](https://github.com/StatewideSoftware/statewide-fivem/issues) with your server
  console output, and remove your API key from anything you paste.

## License

MIT. See [LICENSE](LICENSE).
