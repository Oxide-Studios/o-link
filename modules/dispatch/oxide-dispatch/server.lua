local RESOURCE = 'oxide-dispatch'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Dispatch', RESOURCE, false) then return end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

olink._register('dispatch', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---Server-authored alert (911, panic, manual, system).
    ---@param data table
    ---@return table|nil
    CreateAlert = function(data)
        if not isStarted() then return nil end
        local ok, result = pcall(function() return res:CreateAlert(data) end)
        return ok and result or nil
    end,

    ---A 911/311 call from a player's phone, through oxide-dispatch's civilian call pipeline
    ---(categories, zone blacklist, replies to the caller).
    ---@param src number
    ---@param payload { channel: '911'|'311', category?: string, message?: string, anonymous?: boolean, number?: string }
    ---@return table|false { alertId }, string|nil err
    CivilianCall = function(src, payload)
        if not isStarted() then return false, 'unavailable' end
        local ok, alertId, err = pcall(function() return res:CivilianCall(src, payload) end)
        if not ok then return false, 'unavailable' end
        if not alertId then return false, type(err) == 'string' and err or 'rejected' end
        return { alertId = alertId }
    end,

    ---@param jobFilter? string|string[]
    ---@return table[]
    GetActiveAlerts = function(jobFilter)
        if not isStarted() then return {} end
        local ok, result = pcall(function() return res:GetActiveAlerts(jobFilter) end)
        return ok and result or {}
    end,

    ---@param alertId integer
    ---@return table|nil
    GetAlert = function(alertId)
        if not isStarted() then return nil end
        local ok, result = pcall(function() return res:GetAlert(alertId) end)
        return ok and result or nil
    end,

    ---@param alertId integer
    ---@param src integer
    ---@return boolean, string|nil
    RespondToAlert = function(alertId, src)
        if not isStarted() then return false, 'unavailable' end
        local ok, success, err = pcall(function() return res:RespondToAlert(alertId, src) end)
        if not ok then return false, 'unavailable' end
        return success, err
    end,

    ---@param alertId integer
    ---@param src integer
    ---@return boolean
    StopResponding = function(alertId, src)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:StopResponding(alertId, src) end)
        return ok and result == true
    end,

    ---@param alertId integer
    ---@param src integer
    ---@param status 'responding'|'on_scene'|'cleared'
    ---@return boolean
    UpdateResponderStatus = function(alertId, src, status)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:UpdateResponderStatus(alertId, src, status) end)
        return ok and result == true
    end,

    ---@param alertId integer
    ---@param src? integer
    ---@param reason? string
    ---@return boolean, string|nil
    CloseAlert = function(alertId, src, reason)
        if not isStarted() then return false, 'unavailable' end
        local ok, success, err = pcall(function() return res:CloseAlert(alertId, src, reason) end)
        if not ok then return false, 'unavailable' end
        return success, err
    end,

    ---Persist a callsign to character metadata.
    ---@param src integer
    ---@param callsign string
    ---@return boolean, string|nil
    SetCallsign = function(src, callsign)
        if not isStarted() then return false, 'unavailable' end
        local ok, success, err = pcall(function() return res:SetCallsign(src, callsign) end)
        if not ok then return false, 'unavailable' end
        return success, err
    end,

    ---Set an officer's status (broadcasts to other police).
    ---@param src integer
    ---@param statusId 'available'|'busy'|'code4'|'10-7'
    ---@return boolean, string|nil
    SetOfficerStatus = function(src, statusId)
        if not isStarted() then return false, 'unavailable' end
        local ok, success, err = pcall(function() return res:SetOfficerStatus(src, statusId) end)
        if not ok then return false, 'unavailable' end
        return success, err
    end,

    ---Read an officer's current status record.
    ---@param src integer
    ---@return table|nil
    GetOfficerStatus = function(src)
        if not isStarted() then return nil end
        local ok, result = pcall(function() return res:GetOfficerStatus(src) end)
        return ok and result or nil
    end,

    ---Trigger panic on behalf of an officer (server-authoritative).
    ---@param src integer
    ---@return boolean, string|nil
    TriggerPanic = function(src)
        if not isStarted() then return false, 'unavailable' end
        local ok, success, err = pcall(function() return res:TriggerPanic(src) end)
        if not ok then return false, 'unavailable' end
        return success, err
    end,
}, RESOURCE)
