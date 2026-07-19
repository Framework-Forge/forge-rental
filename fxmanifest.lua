fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Forge - PierreMoraes'
description 'Sistema de aluguel de veiculos para FiveM by Forge.'
version '0.1.0'

shared_scripts {
    '@pr_bridge/init.lua',
    'core/init.lua',
}

client_scripts {
    'modules/**/client.lua',
}

server_scripts {
    'modules/**/server.lua',
}

files {
    'data/config.json',
    'data/debts.json',
    'locales/*.json',
}

dependencies {
    'pr_bridge',
    'ox_lib',
}
