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

---How an anchor pins each axis: 'start' (left or top edge), 'end' (right or bottom edge) or
---'middle' (the centre line).
---@return string x, string y
function Hud.Axes(anchor)
    local axes = AXES[anchor] or AXES['top-left']
    return axes[1], axes[2]
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

-- A panel's own half of the screen: a top-row panel starts above the middle, a bottom-row one
-- ends below it; a middle-row panel may sit anywhere.
local function inHalf(rect, row, screen)
    if row == 'start' then return rect.y <= screen.h / 2 end
    if row == 'end' then return rect.y + rect.h >= screen.h / 2 end
    return true
end

-- Move `start` away from the anchor's edge (down for top and centre rows, up for the bottom
-- row) past every rect it overlaps. nil when that leaves the screen, or the panel's half when
-- `halfOnly` (a panel centred on the top or bottom edge, kept out of the middle of the view).
local function slide(start, row, obstacles, screen, halfOnly)
    local up = row == 'end'
    local rect = { x = start.x, y = start.y, w = start.w, h = start.h }
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
        if not hit then return rect end
        rect.y = up and hit.y - Hud.GAP - rect.h or hit.y + hit.h + Hud.GAP
        if rect.y < 0 or rect.y + rect.h > screen.h or (halfOnly and not inHalf(rect, row, screen)) then return nil end
    end
    return nil
end

-- How much of `rects` the rect covers, of the ones marked essential and of the rest, in quarters
-- of its own area: a sliver more or less is not worth moving away from its spot for.
local function covered(rect, rects)
    local essential, other = 0, 0
    for _, r in ipairs(rects) do
        local w = math.min(rect.x + rect.w, r.x + r.w) - math.max(rect.x, r.x)
        local h = math.min(rect.y + rect.h, r.y + r.h) - math.max(rect.y, r.y)
        if w > 0 and h > 0 then
            if r.essential then essential = essential + w * h else other = other + w * h end
        end
    end
    local area = rect.w * rect.h
    return math.floor(essential / area * 4 + 0.5), math.floor(other / area * 4 + 0.5)
end

-- a sorts before b: its first entry that differs is smaller.
local function lower(a, b)
    for i = 1, #a do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end

-- The spot in `start`'s column and half, clear of `fixed`, that covers the least of the essential
-- rects in `obstacles`, then the least of the rest; on a tie the one nearest `start`. Tried at the
-- screen's edges, at the middle and against each obstacle's edges, with and without the gap. nil
-- when no such spot is clear of `fixed`.
local function leastCovered(start, row, obstacles, fixed, screen)
    local half = screen.h / 2
    local ys = { start.y, 0, screen.h - start.h, half, half - start.h }
    for _, o in ipairs(obstacles) do
        ys[#ys + 1] = o.y + o.h
        ys[#ys + 1] = o.y + o.h + Hud.GAP
        ys[#ys + 1] = o.y - start.h
        ys[#ys + 1] = o.y - Hud.GAP - start.h
    end
    local best
    for _, y in ipairs(ys) do
        local rect = { x = start.x, y = y, w = start.w, h = start.h }
        local usable = y >= 0 and y + start.h <= screen.h and (y == start.y or inHalf(rect, row, screen))
        if usable then
            for _, f in ipairs(fixed) do
                if Hud.Overlaps(rect, f) then
                    usable = false
                    break
                end
            end
        end
        if usable then
            local essential, other = covered(rect, obstacles)
            local cost = { essential, other, round(math.abs(y - start.y)), y }
            if not best or lower(cost, best.cost) then best = { rect = rect, cost = cost } end
        end
    end
    return best and best.rect
end

---Place a panel. It starts at `x`, `y` (kept on screen) and takes the first of: the nearest
---spot away from its anchor's edge clear of every rect in `obstacles` (on its half of the
---screen for the top and bottom anchors); when there is none, the spot on its half, clear of
---`fixed` (the HUD's own parts), that covers the least of the rest (rects marked `essential`
---last); when even `fixed` leaves no room there, the start itself. It is never clamped onto
---whatever sits at the column's far end.
---@param obstacles table[] rects to keep clear of
---@param fixed? table[] the rects among them nothing may cover; defaults to `obstacles`
---@return number x, number y
function Hud.Place(anchor, w, h, x, y, obstacles, screen, fixed)
    local axes = AXES[anchor] or AXES['top-left']
    local row = axes[2]
    local start = Hud.Clamp(Hud.Rect(anchor, x, y, w, h, screen), screen)
    local rect = slide(start, row, obstacles, screen, axes[1] == 'middle')
        or leastCovered(start, row, obstacles, fixed or obstacles, screen)
        or start
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

---@param name any
---@return boolean
function Hud.IsName(name)
    return type(name) == 'string' and #name >= 1 and #name <= 64 and name:match('^[%w_%-%.:]+$') ~= nil
end

---Validate a RegisterWidget definition into
---{ id, label, resource, anchor, w, h, overlay, essential, shareSpot?, x?, y? }.
---@return table|false def, string|nil reason
function Hud.Normalize(def, resource)
    if type(def) ~= 'table' then return false, 'def' end
    local id = def.id
    if not Hud.IsName(id) then return false, 'id' end
    if type(def.label) ~= 'string' or def.label == '' then return false, 'label' end
    local anchor = def.anchor
    if anchor == nil then anchor = 'top-left' end
    if not Hud.IsAnchor(anchor) then return false, 'anchor' end
    if def.shareSpot ~= nil and not Hud.IsName(def.shareSpot) then return false, 'shareSpot' end

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
        essential = def.essential == true,
        shareSpot = def.shareSpot,
    }
    if type(def.offset) == 'table' then
        local x, y = tonumber(def.offset.x), tonumber(def.offset.y)
        if x and y then out.x, out.y = x, y end
    end
    return out
end

olink._hud = Hud
