local RESOURCE = 'oxide-phone'

-- Pure adapter: bail if the phone isn't installed so other adapters or the
-- `_default` fallback own the namespace. oxide-phone depends on o-link, so it is
-- never started yet here: register now and gate every call on its state.
if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Phone', RESOURCE, false) then return end
-- Another phone that is already running keeps the namespace (qb-phone instead
-- steps aside for an installed oxide-phone).
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

    ---@param src number
    ---@return string|false
    GetPlayerPhone = function(src)
        return call(false, function() return res:GetPhoneNumber(src) end)
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        return call(nil, function() return res:GetSourceByNumber(number) end)
    end,

    ---@param identifier string
    ---@return string[]
    GetNumbersByIdentifier = function(identifier)
        local numbers = call({}, function() return res:GetNumbersByIdentifier(identifier) end)
        return type(numbers) == 'table' and numbers or {}
    end,

    ---@param src number
    ---@param sender string display name
    ---@param subject string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, subject, message)
        return call(false, function() return res:SendEmail(src, sender, subject, message) end) == true
    end,

    ---@param identifier string
    ---@param sender string
    ---@param subject string
    ---@param message string
    ---@return boolean
    SendEmailOffline = function(identifier, sender, subject, message)
        return call(false, function() return res:SendEmailOffline(identifier, sender, subject, message) end) == true
    end,

    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        return call(false, function() return res:SendMessage(src, sender, message) end) == true
    end,

    ---@param src number
    ---@param data table { title, message, icon?, app? }
    ---@return boolean
    SendNotification = function(src, data)
        if type(data) ~= 'table' then return false end
        return call(false, function() return res:SendNotification(src, data) end) == true
    end,

    ---@param src number
    ---@param appId? string
    ---@return boolean
    Open = function(src, appId)
        return call(false, function() return res:Open(src, appId) end) == true
    end,

    ---@param src number
    ---@return boolean
    Close = function(src)
        return call(false, function() return res:Close(src) end) == true
    end,

    ---@param src number
    ---@param appId string
    ---@param message table { action, data }
    ---@return boolean
    Send = function(src, appId, message)
        if type(message) ~= 'table' then return false end
        return call(false, function() return res:Send(src, appId, message) end) == true
    end,

    ---@param src number
    ---@param id string
    ---@param data table|nil
    ---@return boolean
    SetWidgetData = function(src, id, data)
        if data ~= nil and type(data) ~= 'table' then return false end
        return call(false, function() return res:SetWidgetData(src, id, data) end) == true
    end,

    ---@param src number
    ---@param def table { app, message, title?, icon?, id?, data?, sound?, toast? }
    ---@return string|false
    Notify = function(src, def)
        if type(def) ~= 'table' then return false end
        local id = call(false, function() return res:Notify(src, def) end)
        return type(id) == 'string' and id or false
    end,

    ---@param src number
    ---@param id string
    ---@return boolean
    DismissNotification = function(src, id)
        return call(false, function() return res:DismissNotification(src, id) end) == true
    end,

    ---@param src number
    ---@param appId? string
    ---@return boolean
    ClearNotifications = function(src, appId)
        return call(false, function() return res:ClearNotifications(src, appId) end) == true
    end,
}, RESOURCE)

olink._phone.RegisterEmailRelay(RESOURCE)
