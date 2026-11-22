-- Stellwerk-Plug-in für Lightroom Classic: nimmt Befehle von Stellwerk (Drehregler, Tasten)
-- über zwei lokale Sockets entgegen und meldet Reglerwerte zurück. Protokoll: siehe Init.lua
return {
    LrSdkVersion = 10.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'at.martindoersch.stellwerk',
    LrPluginName = 'Stellwerk',
    LrPluginInfoUrl = 'https://github.com/martindoersch/stellwerk',
    LrInitPlugin = 'Init.lua',
    LrForceInitPlugin = true,
    LrShutdownPlugin = 'Shutdown.lua',
    LrExportMenuItems = { { title = 'Stellwerk-Status', file = 'Status.lua' } },
    LrLibraryMenuItems = { { title = 'Stellwerk-Status', file = 'Status.lua' } },
    VERSION = { major = 0, minor = 1, revision = 0 },
}
