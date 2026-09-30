-- API: https://docs.lbscripts.com/phone/exports/client-exports/

if not olink._guardImpl('Phone', 'lb-phone', 'lb-phone') then return end

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

    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        TriggerServerEvent('o-link:phone:lb-phone:sendEmail', { email = sender, title = title, message = message })
        return true
    end,

    ---@return boolean
    IsOpen = function()
        return exports['lb-phone']:IsOpen() == true
    end,
})
