if not olink._guardImpl('Needs', 'es_extended', 'es_extended') then return end
if not olink._hasOverride('Needs') and GetResourceState('oxide-needs') == 'started' then return end

-- esx_status reports every status about once a second on a 0-1,000,000 scale; o-link normalizes
-- to 0-100 like the server adapter. Stock ESX has no stress, so it stays nil unless a status
-- named `stress` is registered.
local ESX_MAX = 1000000

local NEEDS = { hunger = true, thirst = true, stress = true }
local current = {}

olink._register('needs', {
    GetResourceName = function() return 'es_extended' end,

    ---@param needType string 'hunger'|'thirst'|'stress'
    ---@return number|nil 0-100
    Get = function(needType)
        if not NEEDS[needType] then return nil end
        return current[needType]
    end,

    ---@return { hunger: number|nil, thirst: number|nil, stress: number|nil }
    GetAll = function()
        return { hunger = current.hunger, thirst = current.thirst, stress = current.stress }
    end,
}, 'es_extended')

AddEventHandler('esx_status:onTick', function(statuses)
    if type(statuses) ~= 'table' then return end
    local changed = false
    for _, status in ipairs(statuses) do
        if type(status) == 'table' and NEEDS[status.name] then
            local percent = tonumber(status.percent) or ((tonumber(status.val) or 0) / ESX_MAX * 100)
            local value = math.floor(percent + 0.5)
            if value ~= current[status.name] then
                current[status.name] = value
                changed = true
            end
        end
    end
    if changed then
        TriggerEvent('olink:client:needsChanged', { hunger = current.hunger, thirst = current.thirst, stress = current.stress })
    end
end)

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
