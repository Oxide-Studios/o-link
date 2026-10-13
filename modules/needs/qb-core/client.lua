if not olink._guardImpl('Needs', 'qb-core', 'qb-core') then return end
if not olink._hasOverride('Needs') and GetResourceState('qbx_core') == 'started' then return end
if not olink._hasOverride('Needs') and GetResourceState('oxide-needs') == 'started' then return end

local QBCore = exports['qb-core']:GetCoreObject()

local NEEDS = { hunger = true, thirst = true, stress = true }
local current = {}

---@return table|nil
local function GetMetadata()
    local playerData = QBCore.Functions.GetPlayerData()
    return playerData and playerData.metadata
end

---Merge reported values and fire `olink:client:needsChanged` when any of them moved.
---@param values table
local function Update(values)
    local changed = false
    for needType in pairs(NEEDS) do
        local value = tonumber(values[needType])
        if value and value ~= current[needType] then
            current[needType] = value
            changed = true
        end
    end
    if changed then
        TriggerEvent('olink:client:needsChanged', { hunger = current.hunger, thirst = current.thirst, stress = current.stress })
    end
end

olink._register('needs', {
    GetResourceName = function() return 'qb-core' end,

    ---@param needType string 'hunger'|'thirst'|'stress'
    ---@return number|nil 0-100
    Get = function(needType)
        if not NEEDS[needType] then return nil end
        local metadata = GetMetadata()
        return metadata and tonumber(metadata[needType]) or nil
    end,

    ---@return { hunger: number|nil, thirst: number|nil, stress: number|nil }
    GetAll = function()
        local metadata = GetMetadata() or {}
        return { hunger = tonumber(metadata.hunger), thirst = tonumber(metadata.thirst), stress = tonumber(metadata.stress) }
    end,
}, 'qb-core')

-- qb-core's decay loop and qb-smallresources consumables send the new values directly; current
-- qb-core pushes metadata edits as a single field, older builds resend the whole PlayerData.
RegisterNetEvent('hud:client:UpdateNeeds', function(hunger, thirst)
    Update({ hunger = hunger, thirst = thirst })
end)

RegisterNetEvent('hud:client:UpdateStress', function(stress)
    Update({ stress = stress })
end)

RegisterNetEvent('QBCore:Player:UpdatePlayerDataField', function(key, value)
    if key == 'metadata' and type(value) == 'table' then Update(value) end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    if type(playerData) == 'table' and type(playerData.metadata) == 'table' then Update(playerData.metadata) end
end)

AddEventHandler('olink:client:playerUnload', function()
    current = {}
end)
