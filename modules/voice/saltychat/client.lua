local RESOURCE = 'saltychat'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Voice', RESOURCE, false) then return end

-- SaltyChat exposes the range distance and radio channel as exports and reports everything else
-- through client events, so those are cached here. Its range index is 0-based; o-link's is 1-based.
local INGAME = 2 -- GameInstanceState.Ingame

local res = exports[RESOURCE]
local pluginState, talking, rangeIndex, rangeCount, transmitting

local function Reset()
    pluginState, talking, rangeIndex, rangeCount, transmitting = nil, false, nil, nil, false
end
Reset()

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

olink._register('voice', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return table
    GetState = function()
        if not isStarted() then
            return { connected = false, talking = false, range = {}, radio = { active = false } }
        end

        local okRange, distance = pcall(function() return res:GetVoiceRange() end)
        local okChannel, channel = pcall(function() return res:GetRadioChannel(true) end)
        if not okChannel or channel == '' then channel = nil end

        return {
            -- No plugin-state event yet means o-link started after the plugin connected.
            connected = pluginState == nil or pluginState == INGAME,
            talking = talking,
            range = {
                index = rangeIndex,
                count = rangeCount,
                distance = okRange and tonumber(distance) or nil,
            },
            radio = { active = transmitting, channel = channel },
        }
    end,
}, RESOURCE)

AddEventHandler('SaltyChat_PluginStateChanged', function(state)
    pluginState = tonumber(state)
end)

AddEventHandler('SaltyChat_TalkStateChanged', function(isTalking)
    talking = isTalking and true or false
end)

AddEventHandler('SaltyChat_VoiceRangeChanged', function(_, index, availableVoiceRanges)
    index = tonumber(index)
    rangeIndex = index and index + 1 or nil
    rangeCount = tonumber(availableVoiceRanges)
end)

AddEventHandler('SaltyChat_RadioTrafficStateChanged', function(_, primaryTransmit, _, secondaryTransmit)
    transmitting = (primaryTransmit or secondaryTransmit) and true or false
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == RESOURCE then Reset() end
end)
