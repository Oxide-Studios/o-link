-- Default phone fallback (client).

if not olink._guardImpl('Phone', '_default', false) then return end
if not olink._hasOverride('Phone') and GetResourceState('gksphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('lb-phone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('okokPhone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('oxide-phone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qb-phone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone-pro') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('yseries') == 'started' then return end

olink._registerDefault('phone', olink._buildStub('phone', {
    'SendEmail',
    'RegisterApp', 'UnregisterApp', 'Open', 'Close', 'CloseApp', 'GetCurrentApp', 'Send', 'SetBadge',
    'RegisterWidget', 'UnregisterWidget', 'SetWidgetData', 'Notify', 'DismissNotification', 'ClearNotifications',
}, {
    SendEmail = false,
    RegisterApp = false,
    UnregisterApp = false,
    Open = false,
    Close = false,
    CloseApp = false,
    GetCurrentApp = nil,
    Send = false,
    SetBadge = false,
    RegisterWidget = false,
    UnregisterWidget = false,
    SetWidgetData = false,
    Notify = false,
    DismissNotification = false,
    ClearNotifications = false,
}))

olink._registerDefault('phone', {
    GetResourceName = function() return '_default' end,
    GetPhoneName = function() return '_default' end,
    IsAvailable = function() return false end,
    IsOpen = function() return false end,
})
