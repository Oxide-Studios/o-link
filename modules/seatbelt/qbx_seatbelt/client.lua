local RESOURCE = 'qbx_seatbelt'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Seatbelt', RESOURCE, false) then return end
-- An installed oxide-vehicles owns the seatbelt unless Config.Overrides.Seatbelt says otherwise.
if not olink._hasOverride('Seatbelt') and GetResourceState('oxide-vehicles') ~= 'missing' then return end

-- qbx_seatbelt keeps the belt on the player's `seatbelt` state bag, which qbx_hud reads too.
local last = false

olink._register('seatbelt', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return boolean
    IsOn = function()
        return LocalPlayer.state.seatbelt and true or false
    end,
}, RESOURCE)

-- The handler runs before the bag is written, so the new value comes from the argument.
AddStateBagChangeHandler('seatbelt', ('player:%s'):format(cache.serverId), function(_, _, value)
    if olink.seatbelt.GetResourceName() ~= RESOURCE then return end
    local on = value and true or false
    if on == last then return end
    last = on
    TriggerEvent('olink:client:seatbeltChanged', on)
end)
