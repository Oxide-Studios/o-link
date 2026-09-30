-- API: https://teamsgg.dev/docs/paid-scripts/phone/exports/client-side/general

if not olink._guardImpl('Phone', 'yseries', 'yseries') then return end

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

    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        TriggerServerEvent('o-link:phone:yseries:sendEmail', { email = sender, title = title, message = message })
        return true
    end,

    ---@return boolean
    IsOpen = function()
        return exports.yseries:IsOpen() == true
    end,
})
