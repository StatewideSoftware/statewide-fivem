# statewide-fivem

The FiveM resource for [Statewide](https://statewide.gg) CAD. It connects your FiveM server to your community's CAD:
duty, unit status, panic, 911 and 311 calls, traffic stops, plate and name lookups, civilian commands, CAD events in
game and the in-game MDT tablet. It needs nothing but OneSync and is MIT licensed.

## Requirements

- A FiveM server with OneSync on.
- A Statewide community and an API key created by its owner.
- Each player has a Statewide account in your community. Players who run Discord are known by it when they join;
  anyone else links once with `/link` and the code from their profile on your community's website.

## Install

1. Download `statewide-<version>.zip` from the latest
   [release](https://github.com/StatewideSoftware/statewide-fivem/releases/latest).
2. Unzip it into your server's `resources` folder. You get one folder, `statewide`. Keep that name. The in-game
   tablet only opens from a resource named `statewide`.
3. In the CAD, open **Settings > API keys** and create a key with the scopes **units**, **calls**, **lookup**,
   **civilian** and **tablet**. Leave out a scope you do not use; the server console names the scope a refused call
   needed.
4. Add these lines to `server.cfg`, after OneSync is on:

   ```cfg
   set onesync on
   set statewide_api_url "https://api.statewide.gg"
   set statewide_api_key "sw_live_..."
   add_convar_permission statewide read statewide_api_key
   set statewide_location_interval 3
   ensure statewide
   ```

5. Restart the server. The console prints `[statewide] connected to <community>`.

Always set the key with `set`, never `setr`. A `setr` convar is sent to every player's game, and anyone could copy
the key. The resource reads the key only on the server.

The `add_convar_permission` line restricts reading the key to this resource. Without it, every other resource on your
server can read the key. Keep the folder name `statewide` so the line matches.

## server.cfg convars

| Convar | Default | What it sets |
| --- | --- | --- |
| `statewide_api_url` | none | The API address, `https://api.statewide.gg`, or your community's own API host. |
| `statewide_api_key` | none | Your community API key. Server only. |
| `statewide_location_interval` | `3` | Seconds between unit location updates, at least 2. |
| `statewide_http_concurrency` | `8` | Most requests to the CAD in flight at once, 1 to 32. |

Commands, cooldowns, chat colors and the tablet key live in `statewide/shared/config.lua`. The
[resource README](statewide/README.md) lists every setting, command, event and export.

## Update

1. Download the new `statewide-<version>.zip` from
   [releases](https://github.com/StatewideSoftware/statewide-fivem/releases).
2. Copy your `statewide/shared/config.lua` somewhere safe if you changed it.
3. Replace the `statewide` folder with the new one, then put your settings back into the new `shared/config.lua`. Read
   the release notes first. A release that adds a setting says so.
4. Restart the resource (`restart statewide`) or the server.

The console warns when your copy is older than the oldest version the API supports. Update when you see that line.

## Support

- Guides: [docs.statewide.gg](https://docs.statewide.gg/developers/fivem-resource)
- Help and announcements: the [Statewide Discord](https://discord.gg/xZHGHVAe3V)
- Bugs in this resource: [open an issue](https://github.com/StatewideSoftware/statewide-fivem/issues) with your server
  console output. Remove your API key from anything you paste.

## License

MIT. See [LICENSE](LICENSE).
