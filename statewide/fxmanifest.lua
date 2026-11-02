fx_version 'cerulean'
game 'gta5'

author 'Statewide Software'
description 'Statewide CAD bridge: duty, status, 911, panic, lookups and civilian commands over the Statewide API'
version '1.2.0'
license 'MIT'
repository 'https://github.com/StatewideSoftware/statewide-fivem'

dependencies { '/onesync' }

shared_scripts {
  'lib/pure.lua',
  'shared/config.lua',
  'shared/paint.lua',
  'shared/locale.lua',
}

server_scripts {
  'server/http.lua',
  'server/identity.lua',
  'server/notify.lua',
  'server/state.lua',
  'server/vehicles.lua',
  'server/commands.lua',
  'server/idcard.lua',
  'server/citations.lua',
  'server/arrival.lua',
  'server/locations.lua',
  'server/events.lua',
  'server/exports.lua',
  'server/script911.lua',
  'server/scenemarkers.lua',
  'server/tablet.lua',
  'server/callhud.lua',
  'modules/ers/map.lua',
  'server/modules.lua',
  'modules/ers/server.lua',
  'server/lifecycle.lua',
  'server/status.lua',
}

client_scripts {
  'client/notify.lua',
  'client/main.lua',
  'client/scenemarkers.lua',
  'client/tablet.lua',
  'client/callhud.lua',
  'client/idcard.lua',
  'client/citation.lua',
  'modules/ers/client.lua',
}

ui_page 'nui/index.html'

files {
  'nui/index.html',
  'nui/tablet.css',
  'nui/tablet.js',
  'nui/rect.js',
  'nui/callhud.js',
  'nui/callhud.css',
  'nui/frame.js',
  'nui/card.js',
  'nui/idcard.js',
  'nui/idcard.css',
  'nui/citation.js',
  'nui/citation.css',
  'nui/licence-card.js',
  'nui/licence-card.css',
  'nui/card-guilloche.svg',
  'nui/card-land.svg',
  'nui/card-holo.svg',
  'nui/card-grit.svg',
  'nui/card-star.svg',
  'nui/barlow-semi-condensed-500.woff2',
  'nui/barlow-semi-condensed-600.woff2',
  'nui/barlow-semi-condensed-700.woff2',
  'nui/barlow-semi-condensed-700i.woff2',
  'nui/barlow-semi-condensed-800i.woff2',
  'nui/herr-von-muellerhoff-400.woff2',
  'nui/ibm-plex-mono-500.woff2',
  'nui/fonts-OFL.txt',
}
