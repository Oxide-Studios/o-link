-- Quasar Smartphone PRO; see server.lua for the doc link.

if not olink._guardImpl('Phone', 'qs-smartphone-pro', 'qs-smartphone-pro') then return end

local RESOURCE = 'qs-smartphone-pro'

olink._register('phone', {
    ---@return boolean
    IsAvailable = function()
        return GetResourceState(RESOURCE) == 'started'
    end,

    ---@return string
    GetPhoneName = function()
        return RESOURCE
    end,

    ---@return string
    GetResourceName = function()
        return RESOURCE
    end,

    ---PRO's documented client mail path is its own `phone:sendNewMail` server event.
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        TriggerServerEvent('phone:sendNewMail', { sender = sender, subject = title, message = message })
        return true
    end,

    ---@return boolean
    IsOpen = function()
        return exports[RESOURCE]:InPhone() == true
    end,
})
