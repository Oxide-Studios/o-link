-- oxide-needs uses o-link itself and may start after it, so this guards on oxide-core (the
-- framework it runs on) and checks oxide-needs when each call is made.
if not olink._guardImpl('Needs', 'oxide-needs', 'oxide-core') then return end
if GetResourceState('oxide-needs') == 'missing' then return end

local RESOURCE = 'oxide-needs'
local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

olink._register('needs', {
    ---@param src number
    ---@param needType string 'hunger'|'thirst'|'stress'
    ---@return number|nil
    GetNeed = function(src, needType)
        if not isStarted() then return nil end
        local ok, value = pcall(function() return res:GetNeed(src, needType) end)
        if not ok then return nil end
        return value
    end,

    ---@param src number
    ---@param needType string
    ---@param value number 0-100
    ---@return boolean
    SetNeed = function(src, needType, value)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:SetNeed(src, needType, value) end)
        return ok and result and true or false
    end,

    ---@param src number
    ---@param needType string
    ---@param amount number positive or negative
    ---@return boolean
    ModifyNeed = function(src, needType, amount)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:ModifyNeed(src, needType, amount) end)
        return ok and result and true or false
    end,
}, RESOURCE)
