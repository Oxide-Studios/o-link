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

    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        TriggerServerEvent('o-link:phone:okokPhone:sendEmail', { email = sender, title = title, message = message })
        return true
    end,

    ---okokPhone publishes its open state as a read-only state bag.
    ---@return boolean
    IsOpen = function()
        return LocalPlayer.state['okokPhone:isOpen'] == true
    end,
})
