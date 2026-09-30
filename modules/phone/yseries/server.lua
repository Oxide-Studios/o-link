-- API: https://teamsgg.dev/docs/paid-scripts/phone/exports/server-side

if not olink._guardImpl('Phone', 'yseries', 'yseries') then return end

local function sendMail(number, sender, title, message)
    local _, received = exports.yseries:SendMail({
        title = title,
        sender = olink._phone.SenderAddress(sender),
        senderDisplayName = sender,
        content = message,
    }, 'phoneNumber', number)
    return received and true or false
end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState('yseries') == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return 'yseries'
    end,

    ---@return string
    GetResourceName = function()
        return 'yseries'
    end,

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        return exports.yseries:GetPhoneNumberBySourceId(src) or false
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        return tonumber(exports.yseries:GetPlayerSourceIdByPhoneNumber(number))
    end,

    ---@param identifier string
    ---@return string[]
    GetNumbersByIdentifier = function(identifier)
        local number = exports.yseries:GetPhoneNumberByIdentifier(identifier)
        return number and { number } or {}
    end,

    ---YSeries has an address field (`sender`) and a name field (`senderDisplayName`).
    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        local number = exports.yseries:GetPhoneNumberBySourceId(src)
        if not number then return false end
        return sendMail(number, sender, title, message)
    end,

    ---@param identifier string
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmailOffline = function(identifier, sender, title, message)
        local number = exports.yseries:GetPhoneNumberByIdentifier(identifier)
        if not number then return false end
        return sendMail(number, sender, title, message)
    end,

    ---SendMessageTo's sender is a phone number, so a named service goes to mail.
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
        exports.yseries:SendNotification({
            app = data.app,
            title = data.title,
            text = data.message,
            icon = data.icon,
        }, 'source', src)
        return true
    end,
})

olink._phone.RegisterEmailRelay('yseries')
