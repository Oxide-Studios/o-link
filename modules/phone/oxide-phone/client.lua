local RESOURCE = 'oxide-phone'

-- Pure adapter: see server.lua for the registration rules.
if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Phone', RESOURCE, false) then return end
for _, other in ipairs({ 'gksphone', 'lb-phone', 'okokPhone', 'qs-smartphone', 'qs-smartphone-pro', 'yseries' }) do
    if not olink._hasOverride('Phone') and GetResourceState(other) == 'started' then return end
end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

---Run an oxide-phone export call; `fallback` when the phone is not running or the call fails.
local function call(fallback, fn)
    if not isStarted() then return fallback end
    local ok, result = pcall(fn)
    if not ok or result == nil then return fallback end
    return result
end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return call(false, function() return res:IsAvailable() end) == true
    end,

    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return string
    GetPhoneName = function() return RESOURCE end,

    ---Mail to the local player, through o-link's validated server relay.
    ---@param sender string
    ---@param subject string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, subject, message)
        if not isStarted() then return false end
        TriggerServerEvent('o-link:phone:oxide-phone:sendEmail', { email = sender, title = subject, message = message })
        return true
    end,

    ---@return boolean
    IsOpen = function()
        return call(false, function() return res:IsOpen() end) == true
    end,

    ---Register an app the phone can host. `def.resource` is required: by the time the
    ---call reaches the phone the invoking resource is o-link itself.
    ---@param def table { id, label, icon, resource, url?, query?, requires?, order?, color?, iconImage?, iconBackground?, readyTimeoutMs?, description?, tagline?, category?, publisher?, version?, links?, permissions? }
    ---@return boolean
    RegisterApp = function(def)
        if type(def) ~= 'table' then return false end
        return call(false, function() return res:RegisterApp(def) end) == true
    end,

    ---@param id string
    ---@return boolean
    UnregisterApp = function(id)
        return call(false, function() return res:UnregisterApp(id) end) == true
    end,

    ---@param appId? string
    ---@return boolean
    Open = function(appId)
        return call(false, function() return res:Open(appId) end) == true
    end,

    ---@return boolean
    Close = function()
        return call(false, function() return res:Close() end) == true
    end,

    ---@param appId string
    ---@return boolean
    CloseApp = function(appId)
        return call(false, function() return res:CloseApp(appId) end) == true
    end,

    ---@return string|nil
    GetCurrentApp = function()
        local app = call(nil, function() return res:GetCurrentApp() end)
        return type(app) == 'string' and app or nil
    end,

    ---Relay a `{ action, data }` message into the app on screen; queued until it is ready.
    ---@param appId string
    ---@param message table
    ---@return boolean
    Send = function(appId, message)
        if type(message) ~= 'table' then return false end
        return call(false, function() return res:Send(appId, message) end) == true
    end,

    ---@param appId string
    ---@param count number
    ---@return boolean
    SetBadge = function(appId, count)
        return call(false, function() return res:SetBadge(appId, count) end) == true
    end,

    ---@param def table { id, label, resource, type, sizes?, icon?, color?, app?, requires?, order?, data?, url?, query?, readyTimeoutMs? }
    ---@return boolean
    RegisterWidget = function(def)
        if type(def) ~= 'table' then return false end
        return call(false, function() return res:RegisterWidget(def) end) == true
    end,

    ---@param id string
    ---@return boolean
    UnregisterWidget = function(id)
        return call(false, function() return res:UnregisterWidget(id) end) == true
    end,

    ---@param id string
    ---@param data table|nil
    ---@return boolean
    SetWidgetData = function(id, data)
        if data ~= nil and type(data) ~= 'table' then return false end
        return call(false, function() return res:SetWidgetData(id, data) end) == true
    end,

    ---@param def table { app, message, title?, icon?, id?, data?, sound?, toast? }
    ---@return string|false id in the form `app:id`
    Notify = function(def)
        if type(def) ~= 'table' then return false end
        local id = call(false, function() return res:Notify(def) end)
        return type(id) == 'string' and id or false
    end,

    ---@param id string
    ---@return boolean
    DismissNotification = function(id)
        return call(false, function() return res:DismissNotification(id) end) == true
    end,

    ---@param appId? string nil = every app
    ---@return boolean
    ClearNotifications = function(appId)
        return call(false, function() return res:ClearNotifications(appId) end) == true
    end,
}, RESOURCE)
