if not olink._guardImpl('HelpText', 'oxide-helptext', 'oxide-helptext') then return end

local RESOURCE = 'oxide-helptext'
local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

-- oxide-helptext keeps one set of prompts per resource, so the consumer that called the bridge
-- is passed as the owner; server relays pass the server resource that sent them.
olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    ---@param owner string|nil
    Show = function(message, position, owner)
        if not isStarted() then return end
        owner = owner or GetInvokingResource()
        pcall(function() res:Show(message, position, owner) end)
    end,

    ---@param id any
    ---@param owner string|nil
    Hide = function(id, owner)
        if not isStarted() then return end
        owner = owner or GetInvokingResource()
        pcall(function() res:Hide(id, owner) end)
    end,
}, RESOURCE)

RegisterNetEvent('o-link:client:helptextShow', function(message, position, owner)
    olink.helptext.Show(message, position, owner)
end)

RegisterNetEvent('o-link:client:helptextHide', function(id, owner)
    olink.helptext.Hide(id, owner)
end)
