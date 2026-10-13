-- oxide-core syncs the needs keys of the character metadata to the `oxide:metadata` bag, so this
-- guards on oxide-core: oxide-needs depends on o-link and is never started when o-link loads.
if not olink._guardImpl('Needs', 'oxide-needs', 'oxide-core') then return end
if GetResourceState('oxide-needs') == 'missing' then return end

local NEEDS = { hunger = true, thirst = true, stress = true }
local current = {}

---@return table
local function GetMetadata()
    local metadata = LocalPlayer.state['oxide:metadata']
    return type(metadata) == 'table' and metadata or {}
end

olink._register('needs', {
    GetResourceName = function() return 'oxide-needs' end,

    ---@param needType string 'hunger'|'thirst'|'stress'
    ---@return number|nil 0-100
    Get = function(needType)
        if not NEEDS[needType] then return nil end
        return tonumber(GetMetadata()[needType])
    end,

    ---@return { hunger: number|nil, thirst: number|nil, stress: number|nil }
    GetAll = function()
        local metadata = GetMetadata()
        return { hunger = tonumber(metadata.hunger), thirst = tonumber(metadata.thirst), stress = tonumber(metadata.stress) }
    end,
}, 'oxide-needs')

AddStateBagChangeHandler('oxide:metadata', ('player:%s'):format(cache.serverId), function(_, _, value)
    if type(value) ~= 'table' then
        current = {}
        return
    end
    local changed = false
    for needType in pairs(NEEDS) do
        local need = tonumber(value[needType])
        if need and need ~= current[needType] then
            current[needType] = need
            changed = true
        end
    end
    if changed then
        TriggerEvent('olink:client:needsChanged', { hunger = current.hunger, thirst = current.thirst, stress = current.stress })
    end
end)
