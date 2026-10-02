-- Default phone fallback.

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
    'GetPlayerPhone', 'GetSourceByNumber', 'GetNumbersByIdentifier',
    'SendEmail', 'SendEmailOffline', 'SendMessage', 'SendNotification',
    'Open', 'Close', 'Send', 'SetWidgetData', 'Notify', 'DismissNotification', 'ClearNotifications', 'AppService',
}, {
    GetPlayerPhone = false,
    GetSourceByNumber = nil,
    GetNumbersByIdentifier = function() return {} end,
    SendEmail = false,
    SendEmailOffline = false,
    SendMessage = false,
    SendNotification = false,
    Open = false,
    Close = false,
    Send = false,
    SetWidgetData = false,
    Notify = false,
    DismissNotification = false,
    ClearNotifications = false,
    AppService = function() return false, 'unsupported' end,
}))

olink._registerDefault('phone', {
    GetResourceName = function() return '_default' end,
    GetPhoneName = function() return '_default' end,
    IsAvailable = function() return false end,
})
