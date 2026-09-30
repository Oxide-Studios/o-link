-- Quasar Smartphone V3 (resource `qs-smartphone` since 2026-05-24) and the older
-- Lite build share a resource name. V3 is detected by its exports; Lite is the fallback.
-- V3 API: https://www.quasar-store.com/docs/smartphone/developer-api
-- Lite API: https://github.com/imnotquasar/docs (player-systems/smartphone-lite)

if not olink._guardImpl('Phone', 'qs-smartphone', 'qs-smartphone') then return end

local RESOURCE = 'qs-smartphone'

---Indexing a missing export raises "No such export", so this probes without calling.
---@return boolean
local function isV3()
    local ok, fn = pcall(function() return exports[RESOURCE].GetCurrentPhoneNumber end)
    return ok and fn ~= nil
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
    ---@return string|boolean
    GetPlayerPhone = function(src)
        if isV3() then
            return exports[RESOURCE]:GetCurrentPhoneNumber(src) or false
        end
        return exports['qs-base']:GetPlayerPhone(src) or false
    end,

    ---V3's SendMail has no sender field, so a sender that differs from the subject
    ---is folded into it. Lite mail can only be sent from the client.
    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        if isV3() then
            local subject = (sender and sender ~= '' and sender ~= title) and ('%s - %s'):format(sender, title) or title
            exports[RESOURCE]:SendMail(src, subject, message)
            return true
        end
        TriggerClientEvent('o-link:phone:qs-smartphone:liteMail', src, { sender = sender, subject = title, message = message, button = {} })
        return true
    end,

    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        if isV3() then
            exports[RESOURCE]:SendNewMessageFromApp(src, sender, message)
            return true
        end
        return olink.phone.SendEmail(src, sender, sender, message)
    end,

    ---@param src number
    ---@param data table { title, message, icon?, app? }
    ---@return boolean
    SendNotification = function(src, data)
        if type(data) ~= 'table' or not isV3() then return false end
        exports[RESOURCE]:sendPhoneNotification(src, {
            appId = data.app,
            title = data.title,
            text = data.message,
        })
        return true
    end,
})

olink._phone.RegisterEmailRelay('qs-smartphone')
