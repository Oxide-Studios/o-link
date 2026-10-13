-- Default voice fallback (client): FiveM's built-in voice chat, read through natives. It has one
-- proximity range and no radio.

if not olink._guardImpl('Voice', '_default', false) then return end

olink._registerDefault('voice', {
    GetResourceName = function() return '_default' end,

    ---@return table
    GetState = function()
        return {
            connected = MumbleIsConnected() and true or false,
            talking = NetworkIsPlayerTalking(PlayerId()) and true or false,
            range = { index = 1, count = 1, distance = MumbleGetTalkerProximity() },
            radio = { active = false },
        }
    end,
}, '_default')
