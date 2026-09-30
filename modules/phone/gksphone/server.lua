-- API: https://docs.gkshop.org/gksphone-v2/exports-and-events/server-exports

if not olink._guardImpl('Phone', 'gksphone', 'gksphone') then return end

local MAIL_ICON = '/html/img/icons/mail.png'

local function mailData(sender, title, message)
    return { sender = sender, image = MAIL_ICON, subject = title, message = message }
end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState('gksphone') == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return 'gksphone'
    end,

    ---@return string
    GetResourceName = function()
        return 'gksphone'
    end,

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        return exports['gksphone']:GetPhoneBySource(src) or false
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        return tonumber(exports['gksphone']:GetSourceByPhone(number))
    end,

    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        exports['gksphone']:SendNewMail(src, mailData(sender, title, message))
        return true
    end,

    ---@param identifier string citizen id / character identifier
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmailOffline = function(identifier, sender, title, message)
        exports['gksphone']:SendNewMailOffline(identifier, mailData(sender, title, message))
        return true
    end,

    ---SMS from a named service ("Delivery", "Police"): SendSystemMessage takes a
    ---sender name, not a number.
    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        local number = exports['gksphone']:GetPhoneBySource(src)
        if not number then return false end
        local result = exports['gksphone']:SendSystemMessage(number, message, sender)
        return type(result) == 'table' and result.status == true
    end,

    ---@param src number
    ---@param data table { title, message, icon?, app? }
    ---@return boolean
    SendNotification = function(src, data)
        if type(data) ~= 'table' then return false end
        exports['gksphone']:sendNotification(src, {
            title = data.title,
            message = data.message,
            icon = data.icon,
        })
        return true
    end,
})
