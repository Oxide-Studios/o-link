-- AddPanel: register a panel and get one table describing how to draw it, every time that
-- changes. o-link follows the HUD's events for the resource and registers its panels again when
-- the HUD (re)starts; the resource's function only passes the table to its own page (it runs in
-- the calling resource, so SendNUIMessage reaches that resource's page). Works with any hud
-- provider: without a HUD that measures its layout, `hosted` is false and the page keeps its own
-- position.

local Hud = olink._hud

-- Hide reasons a panel follows unless it says otherwise: character select, a resource's
-- full-screen view or cinematic, the pause menu, and death.
local HIDE_WITH = { 'unloaded', 'external', 'pause', 'dead' }
local FADED = '0.45'
local THEME_FIELDS = { 'accent', 'light', 'dark', 'contrast' }

local tracked = {} -- id -> { id, resource, def, onChange, hideWith, accent, sig, warned }
local positions = {} -- id -> the last position the HUD gave
local state = { hosted = false, editing = false, visible = true, reason = nil, theme = nil }

local function call(fn, ...)
    local impl = olink.hud and olink.hud[fn]
    if not impl then return nil end
    local ok, a, b = pcall(impl, ...)
    if ok then return a, b end
end

local function validTheme(theme)
    if type(theme) ~= 'table' then return nil end
    local clean = { locked = theme.locked and true or false }
    for _, field in ipairs(THEME_FIELDS) do
        local hex = theme[field]
        if type(hex) ~= 'string' or not hex:match('^#%x%x%x%x%x%x$') then return nil end
        clean[field] = hex:lower()
    end
    return clean
end

local function readHud()
    local areas = call('GetReservedAreas')
    state.hosted = type(areas) == 'table' and areas.measured and true or false
    local visible, reason = call('IsVisible')
    state.visible = visible ~= false
    state.reason = not state.visible and reason or nil
    state.theme = validTheme(call('GetTheme'))
    if not state.hosted then state.editing = false end
end

local function vh(n)
    local text = ('%.2f'):format(math.abs(n)):gsub('%.?0+$', '')
    return text .. 'vh', n < 0
end

-- One axis of the CSS: the offset from the anchored edge, or from the centre line.
local function axis(kind, offset, nearSide, farSide, style)
    local text, negative = vh(offset)
    if kind == 'start' then
        style[nearSide], style[farSide] = (negative and '-' or '') .. text, 'auto'
    elseif kind == 'end' then
        style[farSide], style[nearSide] = (negative and '-' or '') .. text, 'auto'
    else
        style[nearSide], style[farSide] = ('calc(50%% %s %s)'):format(negative and '-' or '+', text), 'auto'
    end
end

local function styleFor(pos, faded)
    local style = { left = '', right = '', top = '', bottom = '', opacity = '' }
    if not pos then return style end
    local x, y = Hud.Axes(pos.anchor)
    axis(x, tonumber(pos.x) or 0, 'left', 'right', style)
    axis(y, tonumber(pos.y) or 0, 'top', 'bottom', style)
    if faded then style.opacity = FADED end
    return style
end

local function panelState(entry)
    local pos = state.hosted and positions[entry.id] or nil
    local hidden = pos ~= nil and pos.hidden == true
    local faded = hidden and state.editing and pos.hiddenBy == 'player'
    local show = not (hidden and not faded)
    if not state.visible and entry.hideWith[state.reason] then show = false end
    return {
        id = entry.id,
        hosted = pos ~= nil,
        show = show,
        preview = state.editing and show,
        style = styleFor(pos, faded),
        theme = entry.accent and state.theme or nil,
        position = pos,
    }
end

local function signature(s)
    local t = s.theme
    local st = s.style
    return table.concat({
        tostring(s.hosted), tostring(s.show), tostring(s.preview),
        st.left, st.right, st.top, st.bottom, st.opacity,
        t and (t.accent .. t.light .. t.dark .. t.contrast .. tostring(t.locked)) or '-',
        s.position and ('%s|%s|%s|%s'):format(s.position.anchor, s.position.left, s.position.top, s.position.w) or '-',
    }, '|')
end

local function push(entry, force)
    local s = panelState(entry)
    local sig = signature(s)
    if not force and sig == entry.sig then return end
    entry.sig = sig
    local ok, err = pcall(entry.onChange, s)
    if not ok and not entry.warned then
        entry.warned = true
        print(('^3[o-link] client: olink.hud.AddPanel(%q): the function from %s failed: %s^0'):format(entry.id, entry.resource, tostring(err)))
    end
end

local function pushAll()
    for _, entry in pairs(tracked) do push(entry) end
end

local function register(entry)
    local pos = call('RegisterWidget', entry.def)
    positions[entry.id] = type(pos) == 'table' and pos or nil
end

local function hideSet(list)
    local set = {}
    if list == false then return set end
    if type(list) ~= 'table' then list = HIDE_WITH end
    for _, reason in ipairs(list) do
        if type(reason) == 'string' then set[reason] = true end
    end
    return set
end

---Register a panel and call `onChange(panel)` now and whenever how to draw it changes.
---@param def table { id, label, anchor?, size?, offset?, overlay?, essential?, shareSpot?, hideWith?, accent? }
---@param onChange function|table called with { id, hosted, show, preview, style, theme, position }
---@return boolean
local function AddPanel(def, onChange)
    local kind = type(onChange)
    if type(def) ~= 'table' or (kind ~= 'function' and kind ~= 'table') then return false end
    local resource = type(def.resource) == 'string' and def.resource or GetInvokingResource() or GetCurrentResourceName()
    local clean = Hud.Normalize(def, resource)
    if not clean then return false end
    local entry = {
        id = clean.id,
        resource = resource,
        def = {
            id = clean.id, label = clean.label, resource = resource, anchor = clean.anchor,
            size = { w = clean.w, h = clean.h },
            offset = clean.x and { x = clean.x, y = clean.y } or nil,
            overlay = clean.overlay, essential = clean.essential, shareSpot = clean.shareSpot,
        },
        onChange = onChange,
        hideWith = hideSet(def.hideWith),
        accent = def.accent ~= false,
    }
    readHud()
    register(entry)
    tracked[entry.id] = entry
    push(entry, true)
    return true
end

---@param id string
---@return boolean
local function RemovePanel(id)
    if not tracked[id] then return false end
    tracked[id] = nil
    positions[id] = nil
    call('UnregisterWidget', id)
    return true
end

AddEventHandler('olink:client:hud:ready', function()
    readHud()
    for _, entry in pairs(tracked) do register(entry) end
    pushAll()
end)

AddEventHandler('olink:client:hud:layoutChanged', function(list)
    if type(list) ~= 'table' then return end
    if not state.hosted then readHud() end
    for id in pairs(tracked) do
        if type(list[id]) == 'table' then positions[id] = list[id] end
    end
    pushAll()
end)

AddEventHandler('olink:client:hud:visibilityChanged', function(visible, reason)
    state.visible = visible ~= false
    state.reason = not state.visible and reason or nil
    pushAll()
end)

AddEventHandler('olink:client:hud:editMode', function(enabled)
    state.editing = enabled == true
    pushAll()
end)

AddEventHandler('olink:client:hud:themeChanged', function(theme)
    state.theme = validTheme(theme)
    pushAll()
end)

-- The HUD stopping: every panel goes back to its own page's position. Its positions are dropped,
-- so a restarted HUD that reports a layout before it has the panels again cannot bring them back.
local function checkHosted()
    if not state.hosted then return end
    readHud()
    if state.hosted then return end
    positions = {}
    pushAll()
end

AddEventHandler('onClientResourceStop', function(resource)
    for id, entry in pairs(tracked) do
        if entry.resource == resource then
            tracked[id] = nil
            positions[id] = nil
        end
    end
    checkHosted()
    -- Read again once the stop has finished, in case the HUD still answered during it.
    if state.hosted then SetTimeout(0, checkHosted) end
end)

olink._registerDefault('hud', { AddPanel = AddPanel, RemovePanel = RemovePanel })
