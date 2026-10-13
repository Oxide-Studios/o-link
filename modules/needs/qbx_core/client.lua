if not olink._guardImpl('Needs', 'qbx_core', 'qbx_core') then return end
if not olink._hasOverride('Needs') and GetResourceState('oxide-needs') == 'started' then return end

-- qbx_core mirrors hunger, thirst and stress onto replicated player state bags (what qbx_hud reads).
local NEEDS = { hunger = true, thirst = true, stress = true }
local current = {}

---@param needType string
---@return number|nil
local function Read(needType)
    return tonumber(LocalPlayer.state[needType])
end

olink._register('needs', {
    GetResourceName = function() return 'qbx_core' end,

    ---@param needType string 'hunger'|'thirst'|'stress'
    ---@return number|nil 0-100
    Get = function(needType)
        if not NEEDS[needType] then return nil end
        return Read(needType)
    end,

    ---@return { hunger: number|nil, thirst: number|nil, stress: number|nil }
    GetAll = function()
        return { hunger = Read('hunger'), thirst = Read('thirst'), stress = Read('stress') }
    end,
}, 'qbx_core')

for needType in pairs(NEEDS) do
    -- The handler runs before the bag is written, so the new value comes from the argument.
    AddStateBagChangeHandler(needType, ('player:%s'):format(cache.serverId), function(_, _, value)
        value = tonumber(value)
        if not value or value == current[needType] then return end
        current[needType] = value
        local needs = { hunger = Read('hunger'), thirst = Read('thirst'), stress = Read('stress') }
        needs[needType] = value
        TriggerEvent('olink:client:needsChanged', needs)
    end)
end

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
