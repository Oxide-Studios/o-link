-- Quasar Smartphone V3 and Lite; see server.lua for the detection and doc links.

if not olink._guardImpl('Phone', 'qs-smartphone', 'qs-smartphone') then return end

local RESOURCE = 'qs-smartphone'

---@return boolean
local function isV3()
    local ok, fn = pcall(function() return exports[RESOURCE].IsPhoneOpen end)
    return ok and fn ~= nil
end

---Lite mail can only be sent from the client, through its own server event.
local function sendLiteMail(sender, subject, message)
    TriggerServerEvent('qs-smartphone:server:sendNewMail', { sender = sender, subject = subject, message = message, button = {} })
end

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

    ---V3 mail is server-only, so it goes through o-link's validated relay.
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(sender, title, message)
        if isV3() then
            TriggerServerEvent('o-link:phone:qs-smartphone:sendEmail', { email = sender, title = title, message = message })
        else
            sendLiteMail(sender, title, message)
        end
        return true
    end,

    ---@return boolean
    IsOpen = function()
        if isV3() then return exports[RESOURCE]:IsPhoneOpen() == true end
        local ok, open = pcall(function() return exports[RESOURCE]:InPhone() end)
        return ok and open == true
    end,
})

RegisterNetEvent('o-link:phone:qs-smartphone:liteMail', function(data)
    if type(data) ~= 'table' then return end
    sendLiteMail(data.sender, data.subject, data.message)
end)
