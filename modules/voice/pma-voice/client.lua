local RESOURCE = 'pma-voice'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Voice', RESOURCE, false) then return end

-- pma-voice publishes its state on the local player's bags (`proximity`, `radioChannel`,
-- `radioActive`), so reading them at call time works whether it starts before or after o-link.
olink._register('voice', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---@return table
    GetState = function()
        local running = GetResourceState(RESOURCE) == 'started'
        local state = LocalPlayer.state
        local proximity = type(state.proximity) == 'table' and state.proximity or {}
        local channel = state.radioChannel
        if channel == 0 then channel = nil end

        return {
            connected = running and MumbleIsConnected() and true or false,
            talking = running and MumbleIsPlayerTalking(PlayerId()) and true or false,
            range = {
                index = tonumber(proximity.index) or GetConvarInt('voice_defaultVoiceMode', 2),
                label = type(proximity.mode) == 'string' and proximity.mode or nil,
                distance = tonumber(proximity.distance),
            },
            radio = {
                active = running and state.radioActive and true or false,
                channel = running and channel or nil,
            },
        }
    end,
}, RESOURCE)
