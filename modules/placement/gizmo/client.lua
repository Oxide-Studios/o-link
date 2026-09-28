-- Fine-placement gizmo for the placement builders (ported from scenedirector's
-- custom translate gizmo). FiveM disables the native DrawGizmo input on
-- production builds, so we draw our own handles with DrawLine and take mouse
-- input from o-link's transparent NUI overlay (web/app.js) — the browser
-- reliably receives clicks the game's cursor mode swallows.
--
-- Matrix-only: the gizmo never touches entities. It manipulates an abstract
-- pose { x, y, z, heading } and streams every change through onUpdate; the
-- placement draw loop applies the pose to its preview each frame, which keeps
-- the anim-ped bone compensation working unchanged. Screen placements pass
-- `size` to get two extra gold edge handles that drag width/height.
--
-- PlacementGizmo.Begin({
--     matrix   = { x, y, z, heading, pitch? },
--     colors   = { axes = { {r,g,b} X, Y, Z }, size = {r,g,b} },  -- the placement palette
--     rotate   = bool,                    -- false: scroll-rotate disabled (coord)
--     tilt     = bool,                    -- true: Ctrl+Scroll adjusts pose.pitch (screens)
--     size     = nil | { w, h, min, max, heading = fn() -> deg, pitch = fn() -> deg },
--     onUpdate = fn(pose),                -- fires on every pose change
--     onSize   = fn(w, h),                -- fires on every size change
--     onKey    = fn(key, mods),           -- forwarded arrows/space from the overlay
--     onLook   = fn(looking),             -- look-mode toggled (RMB)
--     onDone   = fn(outcome),             -- 'confirm' | 'cancel' | 'reaim'
-- })
--
-- Input is fed in by the olinkGizmo* NUI callbacks registered at the bottom.
-- RMB toggles LOOK MODE: NUI focus is released so the player can move/look
-- freely without losing the session; RMB or Enter (game controls) re-captures.
-- Focus ownership: Begin takes NUI focus; EVERY end path (all three outcomes
-- and external Cancel) releases it before onDone fires — consumers can't.

PlacementGizmo = {}

local active = false
local outcome = nil            -- 'confirm' | 'cancel' | 'reaim'
local looking = false          -- RMB look mode: focus released, session alive
local opts = nil
local pose = nil               -- { x, y, z, heading, pitch }
local cursor = { x = 0.5, y = 0.5 }
local hoverId = nil            -- 1=X, 2=Y, 3=Z, 'w', 'h'
local grabId = nil
local grabOrigin = nil         -- { x, y, z } pose snapshot at grab (axis drag)
local grabParam = 0.0
local grabLen = 1.0            -- handle length snapshot at grab (keeps drag linear)
local grabSize = 0.0           -- w/h snapshot at grab (size drag)
local grabDir = nil            -- outward direction snapshot at grab (size drag)
local grabAnchor = nil         -- edge-midpoint snapshot at grab (size drag)

-- r/g/b and SIZE_* are set per session from Begin's `colors`.
local AXES = {
    { dir = vector3(1, 0, 0) },
    { dir = vector3(0, 1, 0) },
    { dir = vector3(0, 0, 1) },
}

local SIZE_R, SIZE_G, SIZE_B
local HIT_PX = 16  -- cursor-to-handle pixel threshold for hover/grab

local endSession -- fwd (used by the look-mode control reads)

local function applyPose()
    if opts.onUpdate then opts.onUpdate(pose) end
end

-- Handle length in metres, scaled by camera distance so it stays a constant on-screen
-- size (this same length is used for the drag mapping, so sensitivity is screen-consistent).
local function handleLength()
    local cam = GetFinalRenderedCamCoord()
    local d = #(cam - vector3(pose.x, pose.y, pose.z))
    return math.max(0.4, d * 0.11)
end

local function project(p)
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    return onScreen, sx, sy
end

-- Pixel distance from the streamed cursor to the screen segment a→b (both normalized).
local function cursorDistPx(ax, ay, bx, by)
    local w, h = GetActiveScreenResolution()
    local cx, cy = cursor.x * w, cursor.y * h
    local pax, pay = ax * w, ay * h
    local dx, dy = (bx - ax) * w, (by - ay) * h
    local len2 = dx * dx + dy * dy
    local t = 0.0
    if len2 > 0 then t = ((cx - pax) * dx + (cy - pay) * dy) / len2 end
    t = math.max(0.0, math.min(1.0, t))
    local ex, ey = cx - (pax + t * dx), cy - (pay + t * dy)
    return math.sqrt(ex * ex + ey * ey)
end

-- Pixel distance from the streamed cursor to a projected world point.
local function cursorPointDistPx(p)
    local ok, sx, sy = project(p)
    if not ok then return nil end
    local w, h = GetActiveScreenResolution()
    local ex, ey = cursor.x * w - sx * w, cursor.y * h - sy * h
    return math.sqrt(ex * ex + ey * ey)
end

-- Cursor's parameter along an axis screen-line (0 = origin, 1 = origin + dir*len).
-- Returns nil when the axis is near edge-on (its screen projection is too short to map).
local function cursorParam(origin, dir, len)
    local oOk, ox, oy = project(origin)
    local tOk, tx, ty = project(origin + dir * len)
    if not oOk or not tOk then return nil end
    local w, h = GetActiveScreenResolution()
    local dx, dy = (tx - ox) * w, (ty - oy) * h
    local len2 = dx * dx + dy * dy
    if len2 < 36 then return nil end  -- < ~6px on screen
    local cx, cy = cursor.x * w, cursor.y * h
    return ((cx - ox * w) * dx + (cy - oy * h) * dy) / len2
end

-- Gold width/height handles: cubes at the quad's right-edge and top-edge
-- midpoints, dragged outward along the edge normal. Edge-midpoint anchoring
-- (plus point hit-testing with priority over the axes) keeps them usable even
-- when the quad's local right/up happens to align with a world translate axis.
-- The H handle rides the TILTED up vector so it stays on the quad's top edge.
local function sizeHandles()
    local s = opts.size
    if not s then return nil end
    local hdg = math.rad((s.heading and s.heading() or 0.0))
    local pit = math.rad((s.pitch and s.pitch() or 0.0))
    local origin = vector3(pose.x, pose.y, pose.z)
    local right = vector3(math.cos(hdg), math.sin(hdg), 0.0)
    -- up rotated around `right` by pitch: up*cos(p) + (right × up)*sin(p)
    local up = vector3(
        math.sin(hdg) * math.sin(pit),
        -math.cos(hdg) * math.sin(pit),
        math.cos(pit)
    )
    return {
        w = { anchor = origin + right * (s.w / 2), dir = right },
        h = { anchor = origin + up * (s.h / 2), dir = up },
    }
end

local function nearestHandle(origin, len)
    -- Size handles first: small, specific targets that win over an axis line
    -- passing through the same pixels.
    local sh = sizeHandles()
    if sh then
        local best, pick = HIT_PX, nil
        for id, hnd in pairs(sh) do
            local d = cursorPointDistPx(hnd.anchor)
            if d and d < best then best = d; pick = id end
        end
        if pick then return pick end
    end

    local best, pick = HIT_PX, nil
    for i, ax in ipairs(AXES) do
        local oOk, ox, oy = project(origin)
        local tOk, tx, ty = project(origin + ax.dir * len)
        if oOk and tOk then
            local d = cursorDistPx(ox, oy, tx, ty)
            if d < best then best = d; pick = i end
        end
    end
    return pick
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function setCapture(enabled)
    SendNUIMessage({ action = 'olink:placement:gizmo', data = { enabled = enabled } })
    SetNuiFocus(enabled, enabled)
end

---RMB from the overlay: release focus so the player can move/look freely; the
---session (pose, size, step) stays alive. Game controls resume it (below).
local lookStartedAt = 0
function PlacementGizmo.StartLook()
    if not active or looking then return end
    looking = true
    lookStartedAt = GetGameTimer()
    grabId = nil
    grabOrigin = nil
    hoverId = nil
    setCapture(false)
    if opts.onLook then opts.onLook(true) end
end

local function resumeFromLook()
    if not active or not looking then return end
    looking = false
    cursor.x, cursor.y = 0.5, 0.5
    setCapture(true)
    if opts.onLook then opts.onLook(false) end
end

-- Look-mode game controls (the placement loop's DisableControlAction batch is
-- still running, so read the disabled variants): RMB / Enter re-capture,
-- ESC cancels, Backspace re-aims — same 200/202 disambiguation as aim phase.
local function handleLookControls()
    -- Grace window: the RMB press that ENTERED look mode surfaces to the game
    -- as a fresh press when focus releases — don't let it bounce us back.
    if GetGameTimer() - lookStartedAt < 300 then return end
    if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25)
        or IsDisabledControlJustPressed(0, 201) then
        resumeFromLook()
        return
    end
    local esc = IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 200)
    local backspace = IsDisabledControlJustPressed(0, 202) and not esc
    if esc then
        endSession('cancel')
    elseif backspace then
        endSession('reaim')
    end
end

local function renderThread()
    while active do
        Wait(0)

        local len = handleLength()
        local origin = vector3(pose.x, pose.y, pose.z)

        if looking then
            handleLookControls()
        elseif grabId == 'w' or grabId == 'h' then
            -- Drag along the snapshot edge direction; the handle rides the
            -- half-extent edge, so a drag of d grows the dimension by 2d.
            local t = cursorParam(grabAnchor, grabDir, grabLen)
            if t then
                local s = opts.size
                local nv = clamp(grabSize + (t - grabParam) * grabLen * 2.0, s.min or 0.2, s.max or 8.0)
                if grabId == 'w' then s.w = nv else s.h = nv end
                if opts.onSize then opts.onSize(s.w, s.h) end
            end
        elseif grabId then
            local t = cursorParam(vector3(grabOrigin.x, grabOrigin.y, grabOrigin.z), AXES[grabId].dir, grabLen)
            if t then
                local np = vector3(grabOrigin.x, grabOrigin.y, grabOrigin.z) + AXES[grabId].dir * ((t - grabParam) * grabLen)
                pose.x, pose.y, pose.z = np.x, np.y, np.z
                applyPose()
            end
        else
            hoverId = nearestHandle(origin, len)
        end

        for i, ax in ipairs(AXES) do
            local tip = origin + ax.dir * len
            local hot = (grabId == i) or (not grabId and hoverId == i)
            local rr = hot and math.min(255, ax.r + 35) or ax.r
            local gg = hot and math.min(255, ax.g + 35) or ax.g
            local bb = hot and math.min(255, ax.b + 35) or ax.b
            DrawLine(origin.x, origin.y, origin.z, tip.x, tip.y, tip.z, rr, gg, bb, hot and 255 or 190)
            DrawMarker(28, tip.x, tip.y, tip.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                len * 0.09, len * 0.09, len * 0.09, rr, gg, bb, hot and 230 or 150,
                false, false, 2, false, nil, nil, false)
        end

        local sh = sizeHandles()
        if sh then
            for id, hnd in pairs(sh) do
                local hot = (grabId == id) or (not grabId and hoverId == id)
                local sz = len * (hot and 0.13 or 0.11)
                DrawMarker(28, hnd.anchor.x, hnd.anchor.y, hnd.anchor.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    sz, sz, sz, SIZE_R, SIZE_G, SIZE_B, hot and 245 or 180,
                    false, false, 2, false, nil, nil, false)
            end
        end
    end
end

function PlacementGizmo.IsActive() return active end

function PlacementGizmo.SetCursor(nx, ny)
    if nx then cursor.x = nx end
    if ny then cursor.y = ny end
end

function PlacementGizmo.Grab()
    if not active then return end
    local len = handleLength()
    local origin = vector3(pose.x, pose.y, pose.z)
    local pick = nearestHandle(origin, len)
    if not pick then return end
    grabId = pick
    grabLen = len
    if pick == 'w' or pick == 'h' then
        local hnd = sizeHandles()[pick]
        grabSize = pick == 'w' and opts.size.w or opts.size.h
        grabDir = hnd.dir
        grabAnchor = hnd.anchor
        grabParam = cursorParam(grabAnchor, grabDir, len) or 0.0
    else
        grabOrigin = { x = pose.x, y = pose.y, z = pose.z }
        grabParam = cursorParam(origin, AXES[pick].dir, len) or 0.0
    end
end

function PlacementGizmo.Release()
    grabId = nil
    grabOrigin = nil
    grabDir = nil
    grabAnchor = nil
end

function PlacementGizmo.Rotate(delta, fine, tilt)
    if not active or delta == 0 then return end
    local step = fine and 1.0 or 5.0
    if tilt then
        if not opts.tilt then return end
        pose.pitch = math.max(-90.0, math.min(90.0, (pose.pitch or 0.0) + (delta > 0 and step or -step)))
    else
        if opts.rotate == false then return end
        pose.heading = (pose.heading + (delta > 0 and step or -step)) % 360.0
    end
    applyPose()
end

---Keyboard nudge from the placement loop (step size lives there, not here).
function PlacementGizmo.Nudge(dx, dy, dz)
    if not active then return end
    pose.x, pose.y, pose.z = pose.x + dx, pose.y + dy, pose.z + dz
    applyPose()
end

endSession = function(oc)
    if not active then return end
    outcome = oc
    active = false
end

---Forwarded keys from the NUI overlay (game controls are dead under NUI focus).
function PlacementGizmo.Key(key, mods)
    if not active then return end
    if key == 'Enter' then endSession('confirm') return end
    if key == 'Escape' then endSession('cancel') return end
    if key == 'Backspace' then endSession('reaim') return end
    -- Shift+arrows resize when size handles exist (keyboard fallback for the
    -- gold handles); plain arrows/space go to the placement loop's nudge.
    if opts.size and mods and mods.shift and key:sub(1, 5) == 'Arrow' then
        local s = opts.size
        local step = 0.05
        if key == 'ArrowUp' then s.h = clamp(s.h + step, s.min or 0.2, s.max or 8.0)
        elseif key == 'ArrowDown' then s.h = clamp(s.h - step, s.min or 0.2, s.max or 8.0)
        elseif key == 'ArrowRight' then s.w = clamp(s.w + step, s.min or 0.2, s.max or 8.0)
        elseif key == 'ArrowLeft' then s.w = clamp(s.w - step, s.min or 0.2, s.max or 8.0) end
        if opts.onSize then opts.onSize(s.w, s.h) end
        return
    end
    if opts.onKey then opts.onKey(key, mods or {}) end
end

function PlacementGizmo.Cancel()
    endSession('cancel')
end

function PlacementGizmo.Begin(o)
    if active then return false end
    o = o or {}
    if type(o.matrix) ~= 'table' or type(o.colors) ~= 'table' then return false end

    for i, rgb in ipairs(o.colors.axes) do
        AXES[i].r, AXES[i].g, AXES[i].b = rgb[1], rgb[2], rgb[3]
    end
    SIZE_R, SIZE_G, SIZE_B = o.colors.size[1], o.colors.size[2], o.colors.size[3]

    opts = o
    outcome = nil
    looking = false
    grabId = nil
    grabOrigin = nil
    hoverId = nil
    cursor.x, cursor.y = 0.5, 0.5
    pose = {
        x = o.matrix.x + 0.0,
        y = o.matrix.y + 0.0,
        z = o.matrix.z + 0.0,
        heading = (o.matrix.heading or 0.0) + 0.0,
        pitch = (o.matrix.pitch or 0.0) + 0.0,
    }

    active = true
    setCapture(true)

    CreateThread(function()
        renderThread()

        -- Release capture + focus BEFORE onDone: o-link owns the focus it took,
        -- whatever path ended the session. (Idempotent if look mode already
        -- released it.)
        setCapture(false)
        looking = false

        local done = opts and opts.onDone
        local oc = outcome or 'cancel'
        opts = nil
        pose = nil
        grabId = nil
        hoverId = nil

        if done then done(oc) end
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- NUI input bridge (streamed by web/app.js while the capture layer is enabled)
-- ---------------------------------------------------------------------------

RegisterNUICallback('olinkGizmoCursor', function(data, cb)
    if PlacementGizmo.IsActive() and type(data) == 'table' then
        PlacementGizmo.SetCursor(tonumber(data.x), tonumber(data.y))
    end
    cb({ ok = true })
end)

RegisterNUICallback('olinkGizmoGrab', function(data, cb)
    if PlacementGizmo.IsActive() then
        if type(data) == 'table' then
            PlacementGizmo.SetCursor(tonumber(data.x), tonumber(data.y))
        end
        PlacementGizmo.Grab()
    end
    cb({ ok = true })
end)

RegisterNUICallback('olinkGizmoRelease', function(_, cb)
    PlacementGizmo.Release()
    cb({ ok = true })
end)

RegisterNUICallback('olinkGizmoWheel', function(data, cb)
    if PlacementGizmo.IsActive() and type(data) == 'table' then
        PlacementGizmo.Rotate(tonumber(data.delta) or 0, data.fine == true, data.ctrl == true)
    end
    cb({ ok = true })
end)

RegisterNUICallback('olinkGizmoLook', function(_, cb)
    PlacementGizmo.StartLook()
    cb({ ok = true })
end)

RegisterNUICallback('olinkGizmoKey', function(data, cb)
    if PlacementGizmo.IsActive() and type(data) == 'table' and type(data.key) == 'string' then
        PlacementGizmo.Key(data.key, { ctrl = data.ctrl == true, shift = data.shift == true })
    end
    cb({ ok = true })
end)
