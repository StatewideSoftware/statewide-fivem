# Contributing

## Issues

Open an issue with what you did, what you expected and the server console output. Leave your API key out of anything
you paste. Report a security problem privately through the repository's **Security** tab, not in a public issue.

## Pull requests

- Keep each pull request to one change.
- Lua runs on FiveM's Lua 5.4. Every file must pass `luac5.4 -p`.
- The API key stays on the server: `statewide_api_key` must never appear under `client/`, `shared/`, `lib/` or `nui/`,
  and the key is never set with `setr`.
- Test the change on a server with a Statewide community before you open the pull request, and say how you tested it.

By contributing you agree your work is released under the MIT license of this repository.
