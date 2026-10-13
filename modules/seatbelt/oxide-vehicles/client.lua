local RESOURCE = 'oxide-vehicles'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Seatbelt', RESOURCE, false) then return end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

---@return boolean
local function IsOn()
    if not isStarted() then return false end
    local ok, result = pcall(function() return res:IsSeatbeltOn() end)
    return ok and result and true or false
end

olink._register('seatbelt', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return boolean
    IsOn = IsOn,
}, RESOURCE)

-- oxide-vehicles has no seatbelt event, so the change event is polled while seated. The belt
-- comes off when the player leaves the vehicle, which the last poll after exiting reports.
CreateThread(function()
    local last = false
    while true do
        if olink.seatbelt.GetResourceName() ~= RESOURCE then return end
        local on = (last or cache.vehicle) and IsOn() or false
        if on ~= last then
            last = on
            TriggerEvent('olink:client:seatbeltChanged', on)
        end
        Wait(cache.vehicle and 250 or 1000)
    end
end)
