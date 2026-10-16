local RESOURCE = 'qbx_seatbelt'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Seatbelt', RESOURCE, false) then return end
-- An installed oxide-vehicles owns the seatbelt unless Config.Overrides.Seatbelt says otherwise.
if not olink._hasOverride('Seatbelt') and GetResourceState('oxide-vehicles') ~= 'missing' then return end

-- qbx_seatbelt keeps the belt on the player's `seatbelt` state bag, which qbx_hud reads too, and a
-- racing harness on `harness`. The seatbelt stays false while the harness is on, so either one
-- counts as buckled, as qb-smallresources reports it.
local last = false

olink._register('seatbelt', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return boolean
    IsOn = function()
        local state = LocalPlayer.state
        return (state.seatbelt or state.harness) and true or false
    end,
}, RESOURCE)

-- A handler runs before its bag is written, so the changed bag's value comes from the argument.
local function watch(key, other)
    AddStateBagChangeHandler(key, ('player:%s'):format(cache.serverId), function(_, _, value)
        if olink.seatbelt.GetResourceName() ~= RESOURCE then return end
        local on = (value or LocalPlayer.state[other]) and true or false
        if on == last then return end
        last = on
        TriggerEvent('olink:client:seatbeltChanged', on)
    end)
end

watch('seatbelt', 'harness')
watch('harness', 'seatbelt')
