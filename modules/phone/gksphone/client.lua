-- API: https://docs.gkshop.org/gksphone-v2/exports-and-events/client-exports

if not olink._guardImpl('Phone', 'gksphone', 'gksphone') then return end

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

    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        return exports['gksphone']:SendNewMail({
            sender = sender,
            image = '/html/img/icons/mail.png',
            subject = title,
            message = message,
        })
    end,

    ---@return boolean
    IsOpen = function()
        return exports['gksphone']:isPhoneOpen() == true
    end,
})
