Config = {}

-- Force a specific implementation for any bridged namespace.
-- Values use implementation folder names and are matched case-insensitively.
-- Leave keys unset or nil to keep normal auto-detection and priority behavior.
-- Notify auto-detection treats ox_lib as a fallback. If multiple non-ox_lib
-- notify resources are running, set Notify explicitly.
Config.Overrides = {
    -- Framework         = 'oxide-core',
    -- Character         = 'oxide-core',
    -- Multichar         = 'oxide-core',
    -- Job               = 'oxide-core',
    -- Money             = 'oxide-accounts',
    -- Inventory         = 'oxide-inventory',
    -- Vehicles          = 'oxide-vehicles',
    -- VehicleProperties = 'vehicleproperties',
    -- VehicleOwnership  = 'oxide-vehicles',
    -- Notify            = 'oxide-notify',
    -- HelpText          = 'ox_lib',
    -- Target            = 'ox_target',
    -- ProgressBar       = 'ox_lib',
    -- VehicleKey        = 'oxide-vehicles',
    -- Fuel              = 'oxide-vehicles',
    -- Weather           = 'oxide-weather',
    -- Input             = 'ox_lib',
    -- Menu              = 'oxide-menu',
    -- Radial            = 'oxide-menu',
    -- Zones             = 'oxlib',
    -- Phone             = 'oxide-phone',
    -- Clothing          = 'oxide-clothing',
    -- Dispatch          = '_default',
    -- Doorlock          = 'ox_doorlock',
    -- Housing           = 'ps-housing',
    -- BossMenu          = 'qbx_management',
    -- Skills            = '_default',
    -- Death             = 'oxide-death',
    -- Needs             = 'oxide-needs',
    -- Gang              = 'oxide-core',
    -- Tablet            = 'oxide-tablet',
}

Config.Debug = true

-- On startup, o-link checks its public GitHub repo for a newer release and
-- prints a notice to the server console. Set to false to disable the check.
Config.CheckForUpdates = true

-- When true, a detected update is downloaded and written over o-link's own
-- files automatically (your config.lua is never touched). The new files take
-- effect on your next full server restart -- o-link never restarts anything
-- itself, as that would desync resources that cache its exports. Leave false
-- to be notified only. Has no effect unless CheckForUpdates is also true.
Config.AutoDownloadUpdates = false

-- `/oxide:diag` writes a support snapshot (server info, framework, which
-- resource provides each bridged namespace, versions, resource states) to
-- o-link/diag/. Attach that file to a support ticket. Console always has
-- access; in game the player needs the ace below or a framework admin.
Config.Diag = {
    -- Extra ace that grants access. Set to '' to rely on the admin check alone.
    RequireAce = 'command.oxide:diag',
    -- How many captured errors to include (needs oxide-logger installed).
    RecentErrors = 50,
    -- Single-level dir only. SaveResourceFile auto-creates ONE parent dir, so
    -- multi-level paths like 'data/diag' silently fail.
    SnapshotDir = 'diag',
}

-- When set, every `olink.inventory.GetImagePath` call returns `<base>/<item>.png`.
-- Example: 'https://r2.qbox.re/myserver/inventory/'
Config.ImageBaseUrl = nil

-- Persisted map mode. Change it with olink:mapmode.
Config.MapMode = 'combined'
