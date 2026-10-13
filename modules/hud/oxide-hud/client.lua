local RESOURCE = 'oxide-hud'

-- Circular provider: oxide-hud depends on o-link, so it is never started when this file
-- loads. Registration happens now; every call checks the resource at call time and answers
-- with the `_default` behaviour while oxide-hud is not running.
if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Hud', RESOURCE, false) then return end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

---Run `method` on the `_default` provider, or return `fallback` if it did not load.
local function default(method, fallback, ...)
    local impl = olink._hudDefault
    if not impl then return fallback end
    return impl[method](...)
end

local function call(fn)
    local ok, result = pcall(fn)
    if ok then return result end
end

olink._register('hud', {
    ---@return string
    GetResourceName = function()
        if isStarted() then return RESOURCE end
        return default('GetResourceName', 'none')
    end,

    ---Register a panel the HUD places and the player can move in the HUD editor. `resource`
    ---is filled with the caller so the panel goes when that resource stops.
    ---@param def table { id, label, anchor?, size? = { w, h }, offset? = { x, y }, overlay?, essential?, shareSpot? }
    ---@return table|false position
    RegisterWidget = function(def)
        if type(def) ~= 'table' then return false end
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        copy.resource = type(copy.resource) == 'string' and copy.resource or GetInvokingResource()
        if not isStarted() then return default('RegisterWidget', false, copy) end
        local result = call(function() return res:RegisterPanel(copy) end)
        return type(result) == 'table' and result or false
    end,

    ---@param id string
    ---@return boolean
    UnregisterWidget = function(id)
        if not isStarted() then return default('UnregisterWidget', false, id) end
        return call(function() return res:UnregisterPanel(id) end) and true or false
    end,

    ---@param id string
    ---@return table|nil position
    GetWidgetPosition = function(id)
        if not isStarted() then return default('GetWidgetPosition', nil, id) end
        local result = call(function() return res:GetPanelPosition(id) end)
        return type(result) == 'table' and result or nil
    end,

    ---Hide or show the HUD for the calling resource. The HUD stays hidden while any resource
    ---holds it hidden, and a resource's hold ends when it stops.
    ---@param visible boolean
    ---@return boolean
    SetVisible = function(visible)
        if not isStarted() then return default('SetVisible', false, visible) end
        local owner = GetInvokingResource() or GetCurrentResourceName()
        return call(function() return res:SetHiddenBy(owner, not visible) end) and true or false
    end,

    ---@return boolean visible, string|nil reason
    IsVisible = function()
        if not isStarted() then return default('IsVisible', true) end
        local state = call(function() return res:GetVisibility() end)
        if type(state) ~= 'table' then return true, nil end
        return state.visible and true or false, state.reason
    end,

    ---@return table { measured, screen, safeZone, areas }
    GetReservedAreas = function()
        if not isStarted() then return default('GetReservedAreas', { measured = false, areas = {} }) end
        local result = call(function() return res:GetReservedAreas() end)
        if type(result) == 'table' then return result end
        return default('GetReservedAreas', { measured = false, areas = {} })
    end,

    ---The server's accent colour and the shades derived from it, or nil when none is set.
    ---@return table|nil { accent, light, dark, contrast } as '#rrggbb'
    GetTheme = function()
        if not isStarted() then return default('GetTheme', nil) end
        local result = call(function() return res:GetTheme() end)
        return type(result) == 'table' and result or nil
    end,
}, RESOURCE)
