-- API: https://fivemphone.com (Notion, "Exports | Statebags | API")

if not olink._guardImpl('Phone', 'okokPhone', 'okokPhone') then return end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState('okokPhone') == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return 'okokPhone'
    end,

    ---@return string
    GetResourceName = function()
        return 'okokPhone'
    end,

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        return exports.okokPhone:getPhoneNumberFromSource(src) or false
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        return tonumber(exports.okokPhone:getSourceFromPhoneNumber(number))
    end,

    ---okok's `sender` is an address, so display names become a slug address.
    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        local playerEmail = exports.okokPhone:getEmailAddressFromSource(src)
        if not playerEmail then return false end
        local id = exports.okokPhone:sendEmail({
            sender = olink._phone.SenderAddress(sender),
            recipients = { playerEmail },
            subject = title,
            body = message,
        })
        return id ~= nil and id ~= false
    end,

    ---okok's message sender is "phone number or whatever you want".
    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        local number = exports.okokPhone:getPhoneNumberFromSource(src)
        if not number then return false end
        local result = exports.okokPhone:sendMessage({
            sender = sender,
            receiver = number,
            message = message,
        })
        return result ~= nil and result ~= false
    end,

    ---@param src number
    ---@param data table { title, message, icon?, app? }
    ---@return boolean
    SendNotification = function(src, data)
        if type(data) ~= 'table' then return false end
        local number = exports.okokPhone:getPhoneNumberFromSource(src)
        if not number then return false end
        exports.okokPhone:pushNotifyViaPhoneNumber(number, {
            app = data.app,
            title = data.title,
            message = data.message,
            img = data.icon,
            type = 'normal',
        })
        return true
    end,
})

olink._phone.RegisterEmailRelay('okokPhone')
