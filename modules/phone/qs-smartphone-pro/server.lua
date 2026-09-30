-- Quasar Smartphone PRO (resource `qs-smartphone-pro`).
-- API: https://github.com/imnotquasar/docs (player-systems/smartphone-pro)

if not olink._guardImpl('Phone', 'qs-smartphone-pro', 'qs-smartphone-pro') then return end

local RESOURCE = 'qs-smartphone-pro'

---@param identifier string
---@param mustBeOwner boolean true ignores phones the character only holds (e.g. stolen)
---@return string|false
local function numberByIdentifier(identifier, mustBeOwner)
    if type(identifier) ~= 'string' then return false end
    return exports[RESOURCE]:GetPhoneNumberFromIdentifier(identifier, mustBeOwner) or false
end

---@param src number
---@return string|false
local function playerNumber(src)
    return numberByIdentifier(olink.character.GetIdentifier(src), false)
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

    ---@param src number
    ---@return string|false
    GetPlayerPhone = function(src)
        return playerNumber(src)
    end,

    ---@param identifier string
    ---@return string[]
    GetNumbersByIdentifier = function(identifier)
        local number = numberByIdentifier(identifier, true)
        return number and { number } or {}
    end,

    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        exports[RESOURCE]:sendNewMail(src, { sender = sender, subject = title, message = message })
        return true
    end,

    ---PRO's app messages take an app name, not a service name, so a named sender goes to mail.
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
        local number = playerNumber(src)
        if not number then return false end
        exports[RESOURCE]:sendNotificationOld(number, {
            app = data.app,
            msg = data.message,
            head = data.title,
        }, false)
        return true
    end,
})
