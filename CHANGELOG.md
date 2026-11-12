# Changelog

Downloads for every version are on the [releases page](https://github.com/StatewideSoftware/statewide-fivem/releases).

## 1.3.0

- New `/clockin [department]` and `/clockout` clock you in for duty time without a unit in the CAD. Name the department
  when you hold seats in more than one. The time shows in the department's duty reports, and a unit you sign on during
  it is not counted twice. A department that signs units on with a clock-in also signs you on with your roster
  callsign. Leaving the server clocks you out at once. `Config.clockIn.jobs` maps framework jobs to departments, so a
  QBCore, Qbox or ESX duty toggle clocks the player in and out. The new `isClockedIn` export reports it.
- The server checks for a newer release on start and every 6 hours, through the same CAD `/health` call and no other
  host. When one is out it prints one console line with the version, its date and the download link, and prints again
  only for a newer release or after a restart. Nothing is downloaded or replaced. The API keys page in the CAD shows
  "Update available" beside a key whose server runs an older version.
- Street labels drop every hidden formatting character and blank space the CAD refuses, so one player's label can no
  longer hold up location updates for everyone. If the CAD still refuses part of a location batch, only that player's
  labels are left out and the other units' positions are stored. The console line for a refused batch prints at most
  once a minute and never shows label text.
- Bystanders call 911 about shots fired, crashes and reckless driving they see; the CAD drops reports the server can't
  back up.
- A civilian who gets into an unregistered car of their own is asked to register it. Communities can make it a
  requirement.
- With LB Phone, players text 911, add notes to their call, get replies from dispatch and share their location; officers
  get call alerts on their phone.
- The Statewide app for LB Phone: civilian and on-duty tabs, live 911 status, status changes, panic, and plate and name
  lookups for members with lookup access.
- Map it: send a call's location to your own in-game map as a waypoint.
- With Wraith ARS 2X, the plate reader warns on-duty officers about stolen, wanted, BOLO and unregistered plates, and a
  plate lock shows the full return.
- NAT Framework V2 servers sync characters and duty with the CAD.
- Officers can take a booking photo in game that lands on the character and the arrest (needs screenshot-basic).
- The tablet no longer times out the first time it opens on a cold server.
- Calls sent by other resources show their SCRIPT tag, and their map blip sits at the coordinates they sent.

## 1.2.0

- The release zip now includes the `modules` folder with the Night ERS integration, which the 1.1.0 zip left out.
- New `/callhud` hides the call HUD for you or shows it again. The choice is kept per player through reconnects and restarts.
- New `/note <text>` adds a note to the call your unit is on (`Config.commands.note`, `Config.cooldowns.note = 5`).
- New `/link <code>` links your game account with a code from your profile page on the community website, when the
  tablet cannot open (`Config.commands.link`, `Config.cooldowns.link = 10`).
- The game server hands each player's tablet its own tablet token, and the tablet passes it to the MDT inside it. The
  CAD accepts the tablet's MDT only with that token. A link code for a player with no linked account goes to the MDT
  the same way and never appears in a web address.
- Linking a game account from the tablet needs 1.2.0. With an older resource the tablet tells a player with no linked
  account that the server needs this update; players already linked keep signing in.
- `/status 10-97` now sets En route, matching the 10-code list in the starter pack. `10-23` stays On scene.
- Notes on your call, a clear by dispatch or another unit, and a sign-on or sign-off made on the web MDT or by a
  dispatcher now reach you in chat. Bursts are folded: the three newest notes, a count for the rest.
- The player who placed a `/911`, `/911a` or `/311` call is told once when the first unit attaches.
- Non-emergency calls (`/311`, `/311a`, the website's Non-emergency choice and a parked car reported stolen) now
  reach on-duty LEO and dispatch units in chat. New server event `statewide:311` for other resources.
- New server events `statewide:detached` and `statewide:callNote` for other resources.
- Attaching a unit to a call sets the officer's GPS waypoint to the call. An en route unit inside the community's On
  scene within distance switches to On Scene once (`Config.attach`).
- Calls and units get a postal, area, city and county without a postal resource. The CAD takes the nearest postal on
  the community's list to the position the server reads, and the area, city and county from the game zone and the
  community's Areas list. A running postal resource still sets the postal.
- New `/311a` places an anonymous non-emergency call (`Config.commands['311a']`, shares the `311` cooldown). Locked
  while you are on duty.
- `/regveh` takes a model year first: `/regveh 2019 Vapid Dominator Red`.
- A player who crashes or quits while on duty keeps their unit, status and call for the community's **Keep a dropped
  unit for** time (5 minutes by default). Dispatch and the MDT show the unit with a DC badge; rejoining in time takes it
  back with no new sign-on. At 0 a drop signs off at once, as before.
- A drop the CAD did not hear about during an outage is reported again until the CAD takes it, so a unit no longer
  stays on duty with no player until the resource restarts.
- Every request to the CAD ends after 15 s. A command that changes something then says the CAD is slow and tells you
  when a late answer shows it went through; a command typed meanwhile gets an answer instead of silence.
- A `/911` or `/311` the CAD refuses (no active character, for one) no longer starts the cooldown.
- With a community key the CAD cross-checks a Discord player's `license:` identifier and refuses a player whose license
  is linked to another account. Players with no `license:` identifier are not affected.
- Players who joined with a license only now get attach, close, citation and ERS pushes. Event payloads that name a
  player carry `membershipId` beside `discordId`.
- ERS: with `closeOnPulloverEnd` off, the end of a pullover clears the unit from the stop and leaves the stop open for
  dispatch, so the next callout is no longer refused.
- The tablet opens only an `https://` sign-in link (plain `http://` for `localhost` and `127.0.0.1` only).
- The README install block adds `add_convar_permission statewide read statewide_api_key`, so other resources cannot
  read the API key.
- A unit hidden from the live map with `/tracking` keeps telling the CAD it is still there, so a hidden unit standing
  still is no longer signed off for inactivity.
- After a rejoin the resource knows the unit is still hidden from the live map, so a bare `/tracking` shows it again
  instead of hiding it a second time.
- ERS: a callout a dispatcher sends from the board is reported as delivered when it reaches the player, then as
  accepted when the player takes it, or as no answer when the offer runs out (`Config.ers.offerTimeout` plus 5 s). It
  was reported as accepted on delivery.
- ERS: the CAD call for an accepted callout takes its street, zone and postal from the callout's position, as its map
  pin and waypoint do, instead of from where the officer stood.
- Escape closes the ID card without also opening the pause menu.
- The 911 blip takes the caller's position from the call itself, so a slow answer to the caller's `/911` no longer
  loses the blip.
- When several citations are handed over in a row, the notice and the sheet name the one just handed, not an earlier
  one still waiting.
- `/id` or `/hideid` puts a shown card away at once, even right after it was shown. Showing a card keeps the command
  cooldown.
- Chat shows much longer CAD answers, such as the full list of makes a community allows, where it used to cut them
  partway. The game notification above the map shows a shortened line.
- `/tracking off` in a community that turned hiding off says so, instead of a general permission refusal.
- A `/panic` the CAD did not answer says the panic may have gone through; `/clearpanic` checks the unit with the CAD
  before saying you are not in panic.

## 1.1.0

- `/id` shows a license card over the game view: photo, license number, class, endorsements, status, names, date of
  birth, sex, address, hair, eyes, height, weight, issued and expiry dates. The mouse and keyboard stay in the game.
- `/id` again puts the card away, for you and everyone you showed it to. Escape, Backspace, `/hideid` or
  `Config.idCard.seconds` close it for the viewer.
- `/id cdl`, `/id boat`, `/id hunt`, `/id fish` (or any license code the community uses) show that license instead of
  the driver license. A license the character does not hold says so in chat.
- New `/giveid` hands your card to the nearest player within `Config.idCard.distance` (3 m) with the hand-over
  animation. `Config.commands.giveid` renames or turns it off; `Config.idCard.handover` still makes `/id` hand over too.
- `Config.idCard.nui = false` prints the card to chat instead.
- Night's ERS integration (`Config.modules.ers`, on when `night_ers` runs). Accepted callouts become CAD calls with the
  unit as primary and a map pin; arriving sets on scene; completing closes the call. Pullovers open traffic stops,
  pursuits can set a status and restore it, and hospital drop-offs note the EMS unit's call. Peds and vehicles ERS
  generates are registered once with their licenses, insurance, registration, stolen flag and BOLO. ERS shifts can
  sign units on and off (`Config.ers.dutySync`), and `/duty` can start the ERS shift (`pushShift`). Dispatchers can
  send an ERS callout to a unit from the dispatch board. ERS's own vehicle and ID panels are hidden.
- The resource reports its version and optional modules to the CAD every 5 minutes.

## 1.0.3

- `/regveh` with no arguments registers the vehicle you are in with the make, model, color and plate the game reports.
  Typed values still win: `/regveh Vapid Dominator Red`.
- Makes and colors match the community's lists without regard to case. One the lists lack is added, marked From the
  game, unless the community turned that off; then chat lists the allowed values.
- When the CAD refuses a field, chat shows its reason instead of "The CAD did not accept that input."
- `/setciv`, `/clearciv`, `/regveh` and `/911a` are refused while you are on duty, with your callsign and the
  `/offduty` command. `/911` and `/311` stay open.
- `/attach` to a call while your unit is on another names that call: "Your unit is already attached to 26-000003.
  Detach on the MDT first."

## 1.0.2

- The in-game MDT stays loaded when the tablet closes, and opens again instantly. A new sign-in is asked for only on
  the first open, after an error, or when the MDT's session has ended.
- Signing in from the tablet goes straight to your unit's MDT when you have one unit on duty.
- `Config.tablet.scale = 'auto'` sizes the MDT from your screen height. **A-** and **A+** in the tablet bar make it
  smaller or larger, and the choice is remembered.
- New `Config.tablet.requireDuty`, on by default. The MDT opens only for players with a unit on duty. Others see
  "You are not on duty" with the next step. Set it to `false` to keep the 1.0.1 behavior.
- MDT alert sounds play in the tablet without a click first.
- Signing on or off on the web MDT or the tablet now reaches the game within one poll, so `/panic`, the live map
  and 911 alerts work without rejoining.
- `/status 10-8` works in communities whose codes are words like `AVAIL`; the code's label works too. An unknown code
  lists the ones that do.
- `/911`, `/911a` and `/311` send any text, however short. With no text they show an example.
- Every command typed without what it needs answers with one example instead of a `Usage:` line.
- `/311` has its own cooldown (`Config.cooldowns['311'] = 30`) and no longer waits on a recent `/911`.
- Clearer copy: no active character, no dispatcher on duty, and the unit alert for a 911 with no dispatcher
  (`911 · no dispatcher · <street>: <text>`).
- The tablet takes messages only from the game, so another resource's page can no longer send it to a different site.

Settings added in 1.0.2: `Config.tablet.scale`, `Config.tablet.requireDuty`, `Config.cooldowns['311']`.

## 1.0.1

- The in-game MDT tablet no longer opens to a black window. The tablet shows the MDT once the page reports that it
  loaded; if that takes more than 10 seconds, it shows an error with a Close button instead.
- Escape and the tablet key (F6 by default) close the tablet while it is signing in or showing an error.
- Stopping or restarting the resource always gives the mouse and keyboard back to the game.
- The screen no longer turns near-black as soon as the resource starts: the tablet page stays fully transparent until
  the tablet opens.

## 1.0.0

- First public release. Duty and unit status, panic, 911, 911a and 311 calls, traffic stops, plate and name lookups,
  civilian commands, live CAD events in game, read-only exports for other resources and the in-game MDT tablet.
