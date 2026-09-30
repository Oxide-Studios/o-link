-- API: https://docs.lbscripts.com/phone/exports/server-exports/

if not olink._guardImpl('Phone', 'lb-phone', 'lb-phone') then return end

local function sendMail(number, sender, title, message)
    local address = exports['lb-phone']:GetEmailAddress(number)
    if not address then return false end
    local success = exports['lb-phone']:SendMail({
        to = address,
        sender = sender,
        subject = title,
        message = message,
    })
    return success and true or false
end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState('lb-phone') == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return 'lb-phone'
    end,

    ---@return string
    GetResourceName = function()
        return 'lb-phone'
    end,

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        return exports['lb-phone']:GetEquippedPhoneNumber(src) or false
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        return tonumber(exports['lb-phone']:GetSourceFromNumber(number))
    end,

    ---GetEquippedPhoneNumber also accepts a character identifier.
    ---@param identifier string
    ---@return string[]
    GetNumbersByIdentifier = function(identifier)
        local number = exports['lb-phone']:GetEquippedPhoneNumber(identifier)
        return number and { number } or {}
    end,

    ---LB's `sender` is shown as-is (its own qb-phone shim passes display names).
    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        local number = exports['lb-phone']:GetEquippedPhoneNumber(src)
        if not number then return false end
        return sendMail(number, sender, title, message)
    end,

    ---@param identifier string
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmailOffline = function(identifier, sender, title, message)
        local number = exports['lb-phone']:GetEquippedPhoneNumber(identifier)
        if not number then return false end
        return sendMail(number, sender, title, message)
    end,

    ---LB's SendMessage needs a sender phone number, so a named service goes to mail.
    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        return olink.phone.SendEmail(src, sender, sender, message)
    end,

    ---@param src number
    ---@param data table { title, message, icon?, app? }
    ---@return boolean
    SendNotification = function(src, data)
        if type(data) ~= 'table' then return false end
        local id = exports['lb-phone']:SendNotification(src, {
            app = data.app,
            title = data.title,
            content = data.message,
            thumbnail = data.icon,
        })
        return id ~= nil
    end,
})

olink._phone.RegisterEmailRelay('lb-phone')
