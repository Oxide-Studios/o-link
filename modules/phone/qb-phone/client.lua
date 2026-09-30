if not olink._guardImpl('Phone', 'qb-phone', 'qb-phone') then return end
if not olink._hasOverride('Phone') and GetResourceState('lb-phone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('gksphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('okokPhone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone-pro') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('yseries') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('oxide-phone') ~= 'missing' then return end

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState('qb-phone') == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return 'qb-phone'
    end,

    ---@return string
    GetResourceName = function()
        return 'qb-phone'
    end,

    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        TriggerServerEvent('o-link:phone:qb-phone:sendEmail', { email = sender, title = title, message = message })
        return true
    end,
})
