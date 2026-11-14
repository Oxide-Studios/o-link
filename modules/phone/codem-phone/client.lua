if not olink._guardImpl('Phone', 'codem-phone', 'codem-phone') then return end

olink._register('phone', {
    ---@return string
    GetPhoneName = function()
        return 'codem-phone'
    end,

    ---@return string
    GetResourceName = function()
        return 'codem-phone'
    end,

    ---@param email string
    ---@param title string
    ---@param message string
    SendEmail = function(email, title, message)
        TriggerServerEvent('o-link:phone:codem-phone:sendEmail', { email = email, title = title, message = message })
    end,
})
