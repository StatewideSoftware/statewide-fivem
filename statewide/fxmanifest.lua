fx_version 'cerulean'
game 'gta5'

author 'Statewide Software'
description 'Statewide CAD bridge: duty, status, 911, panic, lookups and civilian commands over the Statewide API'
version '1.3.0'
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
  'server/actions.lua',
  'server/clockin.lua',
  'server/idcard.lua',
  'server/registration.lua',
  'server/citations.lua',
  'server/arrival.lua',
  'server/locations.lua',
  'server/events.lua',
  'server/exports.lua',
  'server/framework.lua',
  'server/script911.lua',
  'server/scenemarkers.lua',
  'server/tablet.lua',
  'server/callhud.lua',
  'sync/adapter.lua',
  'sync/standalone.lua',
  'modules/ers/map.lua',
  'server/modules.lua',
  'modules/nat/server.lua',
  'modules/c7fw/server.lua',
  'modules/ers/server.lua',
  'modules/witness/server.lua',
  'modules/wraith/server.lua',
  'server/callers.lua',
  'modules/tradio/pure.lua',
  'modules/tradio/server.lua',
  'modules/lbphone/pure.lua',
  'modules/lbphone/server.lua',
  'modules/phoneapp/server.lua',
  'modules/mrpd/map.lua',
  'modules/mrpd/server.lua',
  'modules/mugshot/server.lua',
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
  'client/registration.lua',
  'client/citation.lua',
  'client/alpr.lua',
  'modules/ers/client.lua',
  'modules/phoneapp/client.lua',
  'modules/witness/client.lua',
  'modules/mugshot/client.lua',
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
  'nui/alpr.js',
  'nui/tokens.css',
  'modules/phoneapp/ui/index.html',
  'modules/phoneapp/ui/app.css',
  'modules/phoneapp/ui/app.js',
  'modules/phoneapp/ui/phone.js',
  'modules/phoneapp/ui/icon.png',
  'client/sounds/alpr-stolen.mp3',
  'client/sounds/alpr-warrant.mp3',
  'client/sounds/alpr-bolo.mp3',
  'client/sounds/alpr-registration.mp3',
  'client/sounds/alpr-insurance.mp3',
}
