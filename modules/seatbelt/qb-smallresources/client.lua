local RESOURCE = 'qb-smallresources'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Seatbelt', RESOURCE, false) then return end
-- An installed oxide-vehicles owns the seatbelt unless Config.Overrides.Seatbelt says otherwise.
if not olink._hasOverride('Seatbelt') and GetResourceState('oxide-vehicles') ~= 'missing' then return end

local last = false

olink._register('seatbelt', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return boolean
    IsOn = function()
        if GetResourceState(RESOURCE) ~= 'started' then return false end
        local ok, result = pcall(function() return exports[RESOURCE]:HasSeatbeltOn() end)
        return ok and result and true or false
    end,
}, RESOURCE)

-- Fired with the new state on every toggle and with false when the player leaves the vehicle.
AddEventHandler('seatbelt:client:ToggleSeatbelt', function(on)
    if olink.seatbelt.GetResourceName() ~= RESOURCE then return end
    on = on and true or false
    if on == last then return end
    last = on
    TriggerEvent('olink:client:seatbeltChanged', on)
end)
