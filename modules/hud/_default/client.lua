-- Default HUD (client): no HUD resource hosts panels. A panel sits where its resource asks;
-- one registered without an offset is placed clear of the areas a typical server HUD uses
-- (both top corners and the minimap), inside the GTA safe zone. There is no HUD to hide, so
-- SetVisible and KeepVisible return false and IsVisible stays true, and no server accent, so
-- GetTheme is nil.

local Hud = olink._hud

-- Most servers keep their own HUD stack (name, job, money, IDs, logo) and the chat in the
-- top corners. vh, like every hud size.
local CORNER_W, CORNER_H = 45, 28

-- The stock minimap is 0.15 of a 16:9 screen wide and 0.188888 high, plus the health and
-- armour bars under it; in vh that is the same at every resolution.
local MINIMAP_W, MINIMAP_H = 26.67, 20.4

local panels, order = {}, {}

local function currentScreen()
    local w, h = GetActiveScreenResolution()
    return Hud.Screen(w, h)
end

local function estimates(screen)
    local areas = {
        { id = 'estimate:top-left', kind = 'estimate', x = 0, y = 0, w = CORNER_W, h = CORNER_H },
        { id = 'estimate:top-right', kind = 'estimate', x = Hud.Round(screen.w - CORNER_W), y = 0, w = CORNER_W, h = CORNER_H },
    }
    if IsMinimapRendering() then
        SetScriptGfxAlign(string.byte('L'), string.byte('B'))
        local left, top = GetScriptGfxPosition(-0.0045, -0.188888)
        ResetScriptGfxAlign()
        areas[#areas + 1] = {
            id = 'minimap', kind = 'minimap',
            x = Hud.Round(left * screen.w), y = Hud.Round(top * screen.h),
            w = MINIMAP_W, h = MINIMAP_H,
        }
    end
    return areas
end

local function removePanel(id)
    if not panels[id] then return false end
    panels[id] = nil
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i) end
    end
    return true
end

---Positions of every registered panel: those with an offset first, as asked, then the rest
---in registration order, each clear of the estimates and the panels before it. Overlays keep
---clear of the estimates only, and no panel moves for them. `essential` and `shareSpot` are
---accepted and ignored: there is no editor to hide panels in.
local function layout()
    local screen = currentScreen()
    local safe = Hud.SafeZone(GetSafeZoneSize(), screen)
    local fixed = estimates(screen)
    local taken = estimates(screen)
    local out = {}

    local function add(p, pos)
        out[pos.id] = pos
        if not p.overlay then taken[#taken + 1] = { x = pos.left, y = pos.top, w = pos.w, h = pos.h } end
    end

    for _, id in ipairs(order) do
        local p = panels[id]
        if p.x then add(p, Hud.Position(id, p.anchor, p.x, p.y, p.w, p.h, screen)) end
    end
    for _, id in ipairs(order) do
        local p = panels[id]
        if not p.x then
            local sx, sy = Hud.SafeOffset(p.anchor, safe)
            local x, y = Hud.Place(p.anchor, p.w, p.h, sx, sy, p.overlay and fixed or taken, screen)
            add(p, Hud.Position(id, p.anchor, x, y, p.w, p.h, screen))
        end
    end
    return out, screen, safe
end

local Default = {
    ---@return string
    GetResourceName = function() return '_default' end,

    ---@param def table { id, label, anchor?, size? = { w, h }, offset? = { x, y }, overlay?, essential?, shareSpot?, resource? }
    ---@return table|false position
    RegisterWidget = function(def)
        local p = Hud.Normalize(def, GetInvokingResource())
        if not p then return false end
        if not panels[p.id] then order[#order + 1] = p.id end
        panels[p.id] = p
        return (layout())[p.id] or false
    end,

    ---@param id string
    ---@return boolean
    UnregisterWidget = function(id)
        return removePanel(id)
    end,

    ---@param id string
    ---@return table|nil position
    GetWidgetPosition = function(id)
        if not panels[id] then return nil end
        return (layout())[id]
    end,

    ---@return boolean
    SetVisible = function()
        return false
    end,

    ---@return boolean
    KeepVisible = function()
        return false
    end,

    ---@return boolean visible, string|nil reason
    IsVisible = function()
        return true, nil
    end,

    ---@return table { measured, screen, safeZone, areas }
    GetReservedAreas = function()
        local positions, screen, safe = layout()
        local areas = estimates(screen)
        for _, id in ipairs(order) do
            local pos = positions[id]
            areas[#areas + 1] = { id = id, kind = panels[id].overlay and 'overlay' or 'panel', resource = panels[id].resource, x = pos.left, y = pos.top, w = pos.w, h = pos.h }
        end
        return { measured = false, screen = screen, safeZone = safe, areas = areas }
    end,

    ---@return nil
    GetTheme = function()
        return nil
    end,
}

-- The oxide-hud adapter answers with these while oxide-hud is not running.
olink._hudDefault = Default

AddEventHandler('onClientResourceStop', function(resource)
    for _, id in ipairs({ table.unpack(order) }) do
        if panels[id] and panels[id].resource == resource then removePanel(id) end
    end
end)

if not olink._guardImpl('Hud', '_default', false) then return end
if not olink._hasOverride('Hud') and GetResourceState('oxide-hud') ~= 'missing' then return end

olink._registerDefault('hud', Default, '_default')
