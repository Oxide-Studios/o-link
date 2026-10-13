-- Screen maths for the hud namespace. Every size and offset is in vh (percent of the
-- screen height), so a panel keeps its proportions at any resolution: the screen is
-- `100 * width / height` vh wide and 100 vh tall. An anchor pins one of nine points of a
-- panel to the same point of the screen; offsets are measured inward from that edge, and
-- from the centre line (positive right / down) on a centred axis.

local Hud = {}

Hud.GAP = 1

local AXES = {
    ['top-left'] = { 'start', 'start' },
    ['top'] = { 'middle', 'start' },
    ['top-right'] = { 'end', 'start' },
    ['left'] = { 'start', 'middle' },
    ['center'] = { 'middle', 'middle' },
    ['right'] = { 'end', 'middle' },
    ['bottom-left'] = { 'start', 'end' },
    ['bottom'] = { 'middle', 'end' },
    ['bottom-right'] = { 'end', 'end' },
}

---@param anchor any
---@return boolean
function Hud.IsAnchor(anchor)
    return type(anchor) == 'string' and AXES[anchor] ~= nil
end

local function round(n)
    return math.floor(n * 100 + 0.5) / 100
end
Hud.Round = round

local function toStart(kind, offset, size, span)
    if kind == 'start' then return offset end
    if kind == 'end' then return span - offset - size end
    return span / 2 + offset - size / 2
end

local function toOffset(kind, start, size, span)
    if kind == 'start' then return start end
    if kind == 'end' then return span - start - size end
    return start + size / 2 - span / 2
end

---Screen size in vh from a pixel resolution.
---@param pixelWidth number
---@param pixelHeight number
---@return table { w, h, pixelWidth, pixelHeight }
function Hud.Screen(pixelWidth, pixelHeight)
    pixelWidth = tonumber(pixelWidth) or 1920
    pixelHeight = tonumber(pixelHeight) or 1080
    if pixelWidth <= 0 then pixelWidth = 1920 end
    if pixelHeight <= 0 then pixelHeight = 1080 end
    return { w = round(100 * pixelWidth / pixelHeight), h = 100, pixelWidth = pixelWidth, pixelHeight = pixelHeight }
end

---The rect a panel covers when pinned at `anchor` with offsets `x`, `y`.
---@return table { x, y, w, h }
function Hud.Rect(anchor, x, y, w, h, screen)
    local axes = AXES[anchor] or AXES['top-left']
    return {
        x = toStart(axes[1], x or 0, w, screen.w),
        y = toStart(axes[2], y or 0, h, screen.h),
        w = w,
        h = h,
    }
end

---The offsets that pin `rect` at `anchor`.
---@return number x, number y
function Hud.Offset(anchor, rect, screen)
    local axes = AXES[anchor] or AXES['top-left']
    return toOffset(axes[1], rect.x, rect.w, screen.w), toOffset(axes[2], rect.y, rect.h, screen.h)
end

---Keep a rect on screen. A rect larger than the screen keeps its top-left corner on it.
---@return table rect
function Hud.Clamp(rect, screen)
    return {
        x = math.max(0, math.min(rect.x, screen.w - rect.w)),
        y = math.max(0, math.min(rect.y, screen.h - rect.h)),
        w = rect.w,
        h = rect.h,
    }
end

---@return boolean
function Hud.Overlaps(a, b, gap)
    gap = gap or 0
    return a.x < b.x + b.w + gap and b.x < a.x + a.w + gap
        and a.y < b.y + b.h + gap and b.y < a.y + a.h + gap
end

---The GTA safe zone: the inner rect the game keeps its own HUD in.
---@param size number GetSafeZoneSize(), 1.0 at the widest setting
---@return table rect
function Hud.SafeZone(size, screen)
    size = tonumber(size) or 1.0
    if size > 1 then size = 1 end
    if size < 0.5 then size = 0.5 end
    local margin = (1 - size) / 2
    return {
        x = round(screen.w * margin),
        y = round(screen.h * margin),
        w = round(screen.w * size),
        h = round(screen.h * size),
    }
end

---Offsets of the safe zone's corner for `anchor`, plus the standard gap.
---@return number x, number y
function Hud.SafeOffset(anchor, safe)
    local axes = AXES[anchor] or AXES['top-left']
    local x = axes[1] == 'middle' and 0 or safe.x + Hud.GAP
    local y = axes[2] == 'middle' and 0 or safe.y + Hud.GAP
    return x, y
end

---Place a panel clear of `obstacles`. It starts at `x`, `y` and moves away from its
---anchor's edge (down for top and centre rows, up for the bottom row) past every rect it
---overlaps, then is kept on screen.
---@param obstacles table[] rects to keep clear of
---@return number x, number y
function Hud.Place(anchor, w, h, x, y, obstacles, screen)
    local axes = AXES[anchor] or AXES['top-left']
    local up = axes[2] == 'end'
    local rect = Hud.Clamp(Hud.Rect(anchor, x, y, w, h, screen), screen)
    for _ = 1, #obstacles + 1 do
        local hit
        for _, other in ipairs(obstacles) do
            if Hud.Overlaps(rect, other) then
                if not hit then
                    hit = other
                elseif up and other.y < hit.y then
                    hit = other
                elseif not up and other.y + other.h > hit.y + hit.h then
                    hit = other
                end
            end
        end
        if not hit then break end
        rect.y = up and hit.y - Hud.GAP - h or hit.y + hit.h + Hud.GAP
        if rect.y < 0 or rect.y + h > screen.h then
            rect = Hud.Clamp(rect, screen)
            break
        end
    end
    return Hud.Offset(anchor, rect, screen)
end

---The position table every hud provider returns.
---@return table { id, anchor, x, y, w, h, left, top, moved }
function Hud.Position(id, anchor, x, y, w, h, screen, moved)
    local rect = Hud.Clamp(Hud.Rect(anchor, x, y, w, h, screen), screen)
    local ox, oy = Hud.Offset(anchor, rect, screen)
    return {
        id = id,
        anchor = anchor,
        x = round(ox),
        y = round(oy),
        w = round(w),
        h = round(h),
        left = round(rect.x),
        top = round(rect.y),
        moved = moved and true or false,
    }
end

---Validate a RegisterWidget definition into { id, label, resource, anchor, w, h, overlay, x?, y? }.
---@return table|false def, string|nil reason
function Hud.Normalize(def, resource)
    if type(def) ~= 'table' then return false, 'def' end
    local id = def.id
    if type(id) ~= 'string' or #id < 1 or #id > 64 or not id:match('^[%w_%-%.:]+$') then return false, 'id' end
    if type(def.label) ~= 'string' or def.label == '' then return false, 'label' end
    local anchor = def.anchor
    if anchor == nil then anchor = 'top-left' end
    if not Hud.IsAnchor(anchor) then return false, 'anchor' end

    local size = type(def.size) == 'table' and def.size or {}
    local w, h = tonumber(size.w), tonumber(size.h)
    if not w or w <= 0 then w = 20 end
    if not h or h <= 0 then h = 10 end

    local out = {
        id = id,
        label = def.label,
        resource = type(def.resource) == 'string' and def.resource or resource,
        anchor = anchor,
        w = math.min(w, 400),
        h = math.min(h, 100),
        overlay = def.overlay == true,
    }
    if type(def.offset) == 'table' then
        local x, y = tonumber(def.offset.x), tonumber(def.offset.y)
        if x and y then out.x, out.y = x, y end
    end
    return out
end

olink._hud = Hud
