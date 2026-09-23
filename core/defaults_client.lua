-- Default stub implementations for every client-side o-link namespace.
-- Loaded BEFORE any real implementation so consumers always see callable
-- functions when no provider is installed. Real implementations registered
-- via `olink._register` overwrite these.

local function stub(namespace, methods, defaults)
    olink._registerDefault(namespace, olink._buildStub(namespace, methods, defaults))
end

stub('framework', {
    'GetName', 'GetIsPlayerLoaded', 'ShowHelpText', 'HideHelpText',
}, {
    GetName = 'none',
    GetIsPlayerLoaded = false,
})

stub('character', {
    'GetIdentifier', 'GetName', 'GetMetadata',
})

stub('job', {
    'Get', 'GetDuty',
}, {
    GetDuty = false,
})

stub('multichar', {
    'GetResourceName', 'OnboardNewCharacter', 'SpawnCharacter',
}, {
    GetResourceName = 'none',
    OnboardNewCharacter = function(_, _, onDone) if onDone then onDone(true) end end,
    -- Default: not handled, so the caller falls back to its own teleport.
    SpawnCharacter = false,
})

stub('inventory', {
    'GetResourceName',
    'GetPlayerInventory', 'GetItemCount', 'HasItem', 'GetItemInfo',
    'GetImagePath', 'Items',
}, {
    GetResourceName = 'none',
    GetPlayerInventory = function() return {} end,
    GetItemCount = 0,
    HasItem = false,
    GetItemInfo = function() return {} end,
    GetImagePath = '',
    Items = function() return {} end,
})

stub('notify', {
    'Send',
})

stub('helptext', {
    'Show', 'Hide',
})

stub('target', {
    'AddBoxZone', 'AddSphereZone', 'RemoveZone', 'AddLocalEntity',
    'RemoveLocalEntity', 'AddModel', 'RemoveModel', 'AddGlobalPed',
    'RemoveGlobalPed', 'AddGlobalVehicle', 'RemoveGlobalVehicle',
    'AddNetworkedEntity', 'RemoveNetworkedEntity', 'DisableTargeting',
    'AddGlobalPlayer', 'RemoveGlobalPlayer',
})

stub('progressbar', {
    'Open',
}, {
    Open = false,
})

stub('vehiclekey', {
    'Give', 'Remove', 'GetResourceName', 'GiveKeys', 'RemoveKeys',
}, {
    GetResourceName = 'none',
})

stub('fuel', {
    'GetFuel', 'GetResourceName', 'SetFuel',
}, {
    GetFuel = 0,
    GetResourceName = 'none',
    SetFuel = false,
})

stub('weather', {
    'GetResourceName', 'GetApiVersion', 'ToggleSync', 'IsReady', 'GetWeather', 'GetTime', 'IsBlackout', 'GetForecast', 'GetCurrentZone', 'GetWind', 'GetSeason', 'GetTemperature', 'GetTemperatureAt', 'GetSnowLevel', 'GetSnowLevelAt', 'GetFronts', 'GetCurrentFront', 'IsSyncEnabled', 'GetConditionsAt', 'GetWindAt', 'IsRainingAt', 'IsSnowOnGround', 'IsCovered', 'GetExposureAt', 'RegisterExposureEntity', 'UnregisterExposureEntity', 'GetWeatherData', 'IsTimeFrozen', 'GetRoadConditionsAt',
}, {
    GetResourceName = 'none',
    GetApiVersion = 0,
    GetTime = function() return { hour = 12, minute = 0 } end,
    GetWeather = 'CLEAR',
    ToggleSync = false,
    IsReady = false,
})

stub('input', {
    'GetResourceName', 'Open',
}, {
    GetResourceName = 'none',
    Open = function() return nil end,
})

stub('menu', {
    'GetResourceName', 'Open', 'OpenMenu',
}, {
    GetResourceName = 'none',
})

stub('radial', {
    'GetResourceName', 'Register', 'Unregister', 'Open', 'Close',
    'IsOpen', 'GetCurrentId', 'AddItem', 'RemoveItem', 'ClearItems',
    'Disable', 'Refresh', 'RegisterRadial', 'AddRadialItem',
    'RemoveRadialItem', 'ClearRadialItems', 'HideRadial',
    'DisableRadial', 'GetCurrentRadialId',
}, {
    GetResourceName = 'none',
    Register = false,
    Unregister = false,
    Open = false,
    Close = false,
    IsOpen = false,
    AddItem = false,
    RemoveItem = false,
    ClearItems = false,
    Disable = false,
    Refresh = false,
    RegisterRadial = false,
    AddRadialItem = false,
    RemoveRadialItem = false,
    ClearRadialItems = false,
    HideRadial = false,
    DisableRadial = false,
})

stub('zones', {
    'Create', 'Destroy', 'DestroyByResource', 'Get', 'All',
}, {
    Destroy = false,
    DestroyByResource = false,
    All = function() return {} end,
})

stub('placement', {
    'Coord', 'Entity', 'GhostPed', 'GhostVehicle', 'GhostScreen', 'GhostObject', 'Polygon', 'IsActive', 'Cancel',
    'SetMarkers', 'ClearMarkers',
    'CreateScreen', 'SendScreenMessage', 'DestroyScreen', 'ClearScreens',
}, {
    IsActive = false,
    Cancel = false,
    SetMarkers = false,
    ClearMarkers = false,
    CreateScreen = false,
    SendScreenMessage = false,
    DestroyScreen = false,
    ClearScreens = false,
})

stub('phone', {
    'GetPhoneName', 'GetResourceName', 'SendEmail',
}, {
    GetPhoneName = 'none',
    GetResourceName = 'none',
    SendEmail = false,
})

stub('clothing', {
    'GetResourceName', 'OpenMenu', 'StartCreation', 'ApplyPlayerAppearance',
    'ApplyTattoos', 'GetAppearance', 'SetAppearance', 'RestoreAppearance', 'IsMale',
}, {
    GetResourceName = 'none',
    StartCreation = function(_, onDone) if onDone then onDone(false) end end,
    ApplyPlayerAppearance = false,
    -- Generic, framework-agnostic native impl: every backend's live tattoo
    -- preview uses this identical sequence, so it's a real default, not a stub.
    ApplyTattoos = function(ped, tattoos)
        ped = ped or PlayerPedId()
        if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
        ClearPedDecorations(ped)
        if type(tattoos) == 'table' then
            for _, t in ipairs(tattoos) do
                if t.collection and t.name then
                    AddPedDecorationFromHashes(ped, joaat(t.collection), joaat(t.name))
                end
            end
        end
        return true
    end,
    GetAppearance = function() return {} end,
    SetAppearance = false,
    RestoreAppearance = false,
    IsMale = false,
})

stub('dispatch', {
    'GetResourceName', 'SendAlert',
    'GetActiveAlerts', 'GetAlert', 'RespondToAlert',
    'StopResponding', 'UpdateResponderStatus', 'CloseAlert',
    'SetCallsign', 'SetOfficerStatus', 'TriggerPanic',
}, {
    GetResourceName = 'none',
    SendAlert = false,
    GetActiveAlerts = function() return {} end,
    RespondToAlert = false,
    StopResponding = false,
    UpdateResponderStatus = false,
    CloseAlert = false,
    SetCallsign = false,
    SetOfficerStatus = false,
    TriggerPanic = false,
})

stub('doorlock', {
    'GetClosestDoor', 'GetResourceName',
}, {
    GetResourceName = 'none',
})

stub('housing', {
    'GetResourceName',
}, {
    GetResourceName = 'none',
})

stub('bossmenu', {
    'GetResourceName',
}, {
    GetResourceName = 'none',
})

stub('skills', {
    'GetResourceName', 'GetSkillLevel',
}, {
    GetResourceName = 'none',
    GetSkillLevel = 0,
})

stub('death', {
    'GetDeathState', 'IsPlayerDead', 'IsPlayerDowned', 'SetSuppressed',
}, {
    IsPlayerDead = false,
    IsPlayerDowned = false,
    SetSuppressed = false,
})

stub('gang', {
    'GetResourceName',
    'Get', 'GetAll', 'GetGrades', 'HasPermission',
}, {
    GetResourceName = 'none',
    GetAll = function() return {} end,
    GetGrades = function() return {} end,
    HasPermission = false,
})

stub('medical', {
    'GetResourceName', 'GetConditions', 'IsInjured',
}, {
    GetResourceName = 'none',
    GetConditions = function() return {} end,
    IsInjured = false,
})

stub('tablet', {
    'GetResourceName',
    'RegisterApp', 'UnregisterApp', 'Open', 'Close', 'CloseApp',
    'IsOpen', 'GetCurrentApp', 'Send', 'SetBadge', 'GetDevice',
    'RegisterWidget', 'UnregisterWidget', 'SetWidgetData',
    'Notify', 'DismissNotification', 'ClearNotifications',
}, {
    GetResourceName = 'none',
    RegisterApp = false,
    UnregisterApp = false,
    Open = false,
    Close = false,
    CloseApp = false,
    IsOpen = false,
    GetCurrentApp = function() return nil end,
    Send = false,
    SetBadge = false,
    GetDevice = function() return nil end,
    RegisterWidget = false,
    UnregisterWidget = false,
    SetWidgetData = false,
    Notify = false,
    DismissNotification = false,
    ClearNotifications = false,
})

stub('vehicleproperties', {
    'GetVehicleProperties', 'SetVehicleProperties',
}, {
    SetVehicleProperties = false,
})

stub('logger', {
    'GetResourceName',
    'Trace', 'Debug', 'Info', 'Warn', 'Error', 'Fatal',
    'Event', 'CaptureError', 'SafeCall',
}, {
    GetResourceName = 'none',
    Trace = false,
    Debug = false,
    Info  = false,
    Warn  = false,
    Error = false,
    Fatal = false,
    Event = false,
    CaptureError = false,
    SafeCall = function(fn) if type(fn) == 'function' then local ok, r = pcall(fn) return ok and r or nil end end,
})
