fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'rsg-spots'
description 'Stalcraft-style farming spots for RedM (RSG Core)'
author 'Antigravity'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/ru.lua'
}

client_scripts {
    'client/spawner.lua',
    'client/interaction.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/loot.lua',
    'server/main.lua',
    'server/commands.lua'
}
