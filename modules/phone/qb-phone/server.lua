if not olink._guardImpl('Phone', 'qb-phone', 'qb-phone') then return end
if not olink._hasOverride('Phone') and GetResourceState('lb-phone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('gksphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('okokPhone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('qs-smartphone-pro') == 'started' then return end
if not olink._hasOverride('Phone') and GetResourceState('yseries') == 'started' then return end
-- oxide-phone depends on o-link, so it is never started yet at this point; it
-- registers later in folder order and must not be overwritten.
if not olink._hasOverride('Phone') and GetResourceState('oxide-phone') ~= 'missing' then return end

---@param charinfo any players.charinfo column (JSON text or decoded table)
---@return string|false
local function phoneFromCharinfo(charinfo)
    if type(charinfo) == 'string' then
        local ok, decoded = pcall(json.decode, charinfo)
        if not ok or type(decoded) ~= 'table' then return false end
        charinfo = decoded
    end
    return type(charinfo) == 'table' and charinfo.phone and tostring(charinfo.phone) or false
end

---@param identifier string citizenid
---@return string|false
local function phoneByCitizenId(identifier)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
    if not row then return false end
    return phoneFromCharinfo(row.charinfo)
end

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

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        local identifier = olink.character.GetIdentifier(src)
        if not identifier then return false end
        return phoneByCitizenId(identifier)
    end,

    ---@param number string
    ---@return number|nil
    GetSourceByNumber = function(number)
        if type(number) ~= 'string' and type(number) ~= 'number' then return nil end
        local row = MySQL.single.await(
            "SELECT citizenid FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) = ? LIMIT 1",
            { tostring(number) })
        if not row or not row.citizenid then return nil end

        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if src and olink.character.GetIdentifier(src) == row.citizenid then return src end
        end
        return nil
    end,

    ---@param identifier string citizenid
    ---@return string[]
    GetNumbersByIdentifier = function(identifier)
        if type(identifier) ~= 'string' then return {} end
        local number = phoneByCitizenId(identifier)
        return number and { number } or {}
    end,

    ---@param src number
    ---@param sender string display name
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, sender, title, message)
        local identifier = olink.character.GetIdentifier(src)
        if not identifier then return false end
        exports['qb-phone']:sendNewMailToOffline(identifier, { sender = sender, subject = title, message = message })
        return true
    end,

    ---@param identifier string citizenid
    ---@param sender string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmailOffline = function(identifier, sender, title, message)
        if type(identifier) ~= 'string' then return false end
        exports['qb-phone']:sendNewMailToOffline(identifier, { sender = sender, subject = title, message = message })
        return true
    end,

    ---qb-phone has no service SMS; a named sender goes to mail.
    ---@param src number
    ---@param sender string
    ---@param message string
    ---@return boolean
    SendMessage = function(src, sender, message)
        return olink.phone.SendEmail(src, sender, sender, message)
    end,
})

olink._phone.RegisterEmailRelay('qb-phone')
