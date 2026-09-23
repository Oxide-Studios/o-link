-- In-world placement builder for admin/editor tools.
-- First-party, native-based (+ ox_lib for model load / poly preview) — no external resource dependency.
-- Ported from the copy previously forked into oxide-developer / oxide-police / oxide-dealerships so
-- consumers stop rebuilding it. Every customer already runs o-link, so it lives here.
--
-- AWAIT-STYLE API: the builder blocks and RETURNS the captured value. o-link exports run in o-link's
-- VM and a Lua callback argument won't marshal across the resource boundary, so callback-style
-- (onConfirm/onCancel) can't work cross-resource — the consumer awaits the return instead:
--     local coords = olink.placement.GhostPed({ model = 'a_m_y_business_03' })  -- {x,y,z,w} or nil
--
-- Controls: mouse aim to position, scroll wheel to rotate heading (LSHIFT = fine 1°),
--           LMB confirm, Enter opens the fine-tune gizmo (mouse-drag axes to move,
--           scroll rotate, arrows nudge with Space step size, gold edge handles
--           resize screens; Enter confirm, Backspace re-aim, ESC cancel),
--           RMB / ESC cancel. Polygon: freecam + Enter place / arrows nudge / Space save.
-- On-screen help renders in o-link's own NUI hint card (web/); the gizmo
-- (modules/placement/gizmo/client.lua) takes mouse input through the same
-- page's transparent capture layer.

if not olink._guardImpl('Placement', 'placement', false) then return end

local active = false
local polyActive = false
local polyCancel = nil
local previewEntity = nil
local previewModelHash = nil
local previewAnimMode = false
-- GhostObject previews a rigid group of props: { { entity, offset, quat }, ... }
local previewGroup = {}
local previewGroupHashes = {}
local currentPromise = nil

-- SKEL_Pelvis: the body-center bone the anim compensation tracks.
local PELVIS_BONE = 11816
-- Bones sampled for the vertical compensation (pelvis, L/R foot, head): the
-- lowest posed one is rested just above the aimed surface. Ported from
-- scenedirector's AutoGround; 0.10 ≈ bone-to-skin distance.
local BODY_BONES = { 11816, 14201, 52301, 31086 }
local BONE_SKIN = 0.10

local ROT_STEP = 5.0
local ROT_STEP_FINE = 1.0
local RAYCAST_DIST = 200.0
local MARKER_R, MARKER_G, MARKER_B = 232, 176, 68

-- ---------------------------------------------------------------------------
-- NUI hint card (o-link's own ui_page, web/). Pushed on state transitions
-- only, never per frame. lines = { { { key, desc, tone }, ... }, ... } with
-- tones 'pink' | 'green' | 'neutral'.
-- ---------------------------------------------------------------------------
local KIND_BRAND = {
    coord   = { icon = 'pin', label = 'Position' },
    ped     = { icon = 'user', label = 'Character' },
    vehicle = { icon = 'car', label = 'Vehicle' },
    screen  = { icon = 'screen', label = 'Screen Panel' },
    object  = { icon = 'cube', label = 'Object' },
}

local function pushHints(spec)
    SendNUIMessage({
        action = 'olink:placement:hints',
        data = spec and {
            visible = true,
            icon = spec.icon,
            label = spec.label,
            phase = spec.phase,
            phaseHot = spec.phaseHot or false,
            lines = spec.lines,
        } or { visible = false },
    })
end

local function aimHints(kind, scrW, scrH, snapOnly)
    local lines = {}
    if snapOnly then
        -- Snap points fix position and heading, so rotation and fine-tune don't apply.
        local brand = KIND_BRAND[kind]
        return { icon = brand.icon, label = brand.label, phase = 'Aim at a slot', lines = {
            { { key = 'LMB', desc = 'confirm', tone = 'green' } },
            { { key = 'RMB / ESC / Bksp', desc = 'cancel', tone = 'neutral' } },
        } }
    end
    if kind ~= 'coord' then
        local rot = {
            { key = 'Scroll', desc = 'rotate', tone = 'pink' },
            { key = 'Shift+Scroll', desc = 'rotate fine', tone = 'pink' },
        }
        if kind == 'screen' then
            rot[#rot + 1] = { key = 'Ctrl+Scroll', desc = 'tilt', tone = 'pink' }
        end
        lines[#lines + 1] = rot
    end
    if kind == 'screen' then
        lines[#lines + 1] = {
            { key = '↑↓←→', desc = ('resize (%.2f × %.2fm)'):format(scrW, scrH), tone = 'pink' },
            { key = 'Shift', desc = 'fine', tone = 'pink' },
        }
    end
    lines[#lines + 1] = {
        { key = 'Enter', desc = 'fine-tune', tone = 'green' },
        { key = 'LMB', desc = 'confirm', tone = 'green' },
    }
    lines[#lines + 1] = {
        { key = 'RMB / ESC / Bksp', desc = 'cancel', tone = 'neutral' },
    }
    local brand = KIND_BRAND[kind]
    return { icon = brand.icon, label = brand.label, phase = 'Aim', lines = lines }
end

local function gizmoHints(kind, step)
    local lines = {}
    lines[#lines + 1] = {
        { key = 'Drag', desc = 'axis to move', tone = 'pink' },
        { key = '↑↓←→', desc = 'nudge', tone = 'pink' },
        { key = 'Ctrl+↑↓', desc = 'up / down', tone = 'pink' },
    }
    local second = {}
    if kind ~= 'coord' then
        second[#second + 1] = { key = 'Scroll', desc = 'rotate', tone = 'pink' }
    end
    if kind == 'screen' then
        second[#second + 1] = { key = 'Ctrl+Scroll', desc = 'tilt', tone = 'pink' }
    end
    second[#second + 1] = { key = 'Space', desc = ('step %.2fm'):format(step), tone = 'pink' }
    lines[#lines + 1] = second
    if kind == 'screen' then
        lines[#lines + 1] = {
            { key = 'Drag', desc = 'gold handle resize', tone = 'pink' },
            { key = 'Shift+↑↓←→', desc = 'resize', tone = 'pink' },
        }
    end
    lines[#lines + 1] = {
        { key = 'RMB', desc = 'move camera', tone = 'pink' },
        { key = 'Enter', desc = 'confirm', tone = 'green' },
        { key = 'Bksp', desc = 're-aim', tone = 'neutral' },
        { key = 'ESC', desc = 'cancel', tone = 'neutral' },
    }
    local brand = KIND_BRAND[kind]
    return { icon = brand.icon, label = brand.label, phase = 'Fine-tune', phaseHot = true, lines = lines }
end

-- RMB look mode: the gizmo stays alive while the player repositions.
local function lookHints(kind)
    local brand = KIND_BRAND[kind]
    return {
        icon = brand.icon,
        label = brand.label,
        phase = 'Move Camera',
        phaseHot = true,
        lines = {
            {
                { key = 'WASD / Mouse', desc = 'move & look freely', tone = 'pink' },
            },
            {
                { key = 'RMB / Enter', desc = 'resume fine-tune', tone = 'green' },
                { key = 'Bksp', desc = 're-aim', tone = 'neutral' },
                { key = 'ESC', desc = 'cancel', tone = 'neutral' },
            },
        },
    }
end

local function unloadModel()
    if previewModelHash then
        SetModelAsNoLongerNeeded(previewModelHash)
        previewModelHash = nil
    end
    for _, hash in ipairs(previewGroupHashes) do
        SetModelAsNoLongerNeeded(hash)
    end
    previewGroupHashes = {}
end

-- Entity-picker outline target; cleared through resolve() so external Cancel
-- and resource stops never leave a lingering outline on a world entity.
local outlinedEntity = nil

local function clearOutline()
    if outlinedEntity then
        if DoesEntityExist(outlinedEntity) then
            SetEntityDrawOutline(outlinedEntity, false)
        end
        outlinedEntity = nil
    end
end

local function destroyPreview()
    previewAnimMode = false
    for _, part in ipairs(previewGroup) do
        if DoesEntityExist(part.entity) then DeleteEntity(part.entity) end
    end
    previewGroup = {}
    if previewEntity and DoesEntityExist(previewEntity) then
        if IsEntityAVehicle(previewEntity) then
            DeleteEntity(previewEntity)
        else
            DeletePed(previewEntity)
        end
    end
    previewEntity = nil
end

local function ghostify(entity)
    SetEntityAlpha(entity, 150, false)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)
    if IsEntityAPed(entity) then
        SetBlockingOfNonTemporaryEvents(entity, true)
        TaskStandStill(entity, -1)
    elseif IsEntityAVehicle(entity) then
        SetVehicleEngineOn(entity, false, true, true)
        SetVehicleDoorsLocked(entity, 2)
        SetVehicleNumberPlateText(entity, 'PREVIEW')
    end
end

-- Cast a ray from the gameplay camera; fall back to a point along the forward
-- vector so the marker still tracks when aiming at the sky. MLO interior props
-- are unreliable ray targets regardless of probe type — the fine-nudge phase
-- is the supported way to place onto them.
local function raycastFromCamera()
    local camCoord = GetGameplayCamCoord()
    local camRot   = GetGameplayCamRot(2)
    local rx = math.rad(camRot.x)
    local rz = math.rad(camRot.z)
    local cosX = math.cos(rx)
    local fwd = vector3(-math.sin(rz) * math.abs(cosX), math.cos(rz) * math.abs(cosX), math.sin(rx))
    local endPos = camCoord + fwd * RAYCAST_DIST

    local handle = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, endPos.x, endPos.y, endPos.z, -1, PlayerPedId(), 0)
    local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(handle)
    if hit == 1 or hit == true then
        return true, hitCoords, hitEntity
    end
    return false, endPos, nil
end

local function resolve(result)
    if not active then return end
    active = false
    pushHints(nil)
    -- A live gizmo session (external Cancel, resource stop) tears down through
    -- the gizmo's own end path, which releases NUI focus; its onDone then
    -- re-enters resolve and no-ops on the active guard above.
    if PlacementGizmo.IsActive() then
        PlacementGizmo.Cancel()
    end
    destroyPreview()
    clearOutline()
    unloadModel()
    local p = currentPromise
    currentPromise = nil
    if p then p:resolve(result) end
end

-- Screen quad basis: horizontal right from heading, up tilted around it by
-- pitch (up*cos + (right × up)*sin). Shared by the ghost preview and the live
-- CreateScreen panels so both agree on orientation.
local function quadBasis(heading, pitch)
    local rad = math.rad(heading)
    local pit = math.rad(pitch or 0.0)
    local right = vector3(math.cos(rad), math.sin(rad), 0.0)
    local up = vector3(
        math.sin(rad) * math.sin(pit),
        -math.cos(rad) * math.sin(pit),
        math.cos(pit)
    )
    return right, up
end

-- Translucent quad preview for screen-panel placement (both faces + edges).
local function drawGhostQuad(center, heading, pitch, width, height)
    local r, u = quadBasis(heading, pitch)
    local right = r * (width / 2)
    local up = u * (height / 2)
    local tl, tr = center - right + up, center + right + up
    local bl, br = center - right - up, center + right - up

    DrawPoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z, MARKER_R, MARKER_G, MARKER_B, 110)
    DrawPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z, MARKER_R, MARKER_G, MARKER_B, 110)
    DrawPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, MARKER_R, MARKER_G, MARKER_B, 110)
    DrawPoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, MARKER_R, MARKER_G, MARKER_B, 110)
    DrawLine(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, MARKER_R, MARKER_G, MARKER_B, 220)
    DrawLine(tr.x, tr.y, tr.z, br.x, br.y, br.z, MARKER_R, MARKER_G, MARKER_B, 220)
    DrawLine(br.x, br.y, br.z, bl.x, bl.y, bl.z, MARKER_R, MARKER_G, MARKER_B, 220)
    DrawLine(bl.x, bl.y, bl.z, tl.x, tl.y, tl.z, MARKER_R, MARKER_G, MARKER_B, 220)
end

-- Quaternions are {x, y, z, w}. Heading is a right-handed rotation about +Z,
-- matching SetEntityHeading and GetOffsetFromEntityInWorldCoords.
local function quatMul(a, b)
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end

local function quatAxis(ax, ay, az, degrees)
    local half = math.rad(degrees) * 0.5
    local s = math.sin(half)
    return { ax * s, ay * s, az * s, math.cos(half) }
end

local function quatRotate(q, v)
    local tx = 2.0 * (q[2] * v[3] - q[3] * v[2])
    local ty = 2.0 * (q[3] * v[1] - q[1] * v[3])
    local tz = 2.0 * (q[1] * v[2] - q[2] * v[1])
    return {
        v[1] + q[4] * tx + (q[2] * tz - q[3] * ty),
        v[2] + q[4] * ty + (q[3] * tx - q[1] * tz),
        v[3] + q[4] * tz + (q[1] * ty - q[2] * tx),
    }
end

-- Group offsets/rotations arrive from another resource's VM as vector3 or plain tables.
local function readVec(v)
    if v == nil then return { 0.0, 0.0, 0.0 } end
    return { (tonumber(v.x or v[1]) or 0.0) + 0.0, (tonumber(v.y or v[2]) or 0.0) + 0.0, (tonumber(v.z or v[3]) or 0.0) + 0.0 }
end

-- Local rotation of one group member: `quat` wins; otherwise `rotation` degrees
-- applied about local X, then Y, then Z.
local function readLocalQuat(def)
    local q = def.quat
    if q ~= nil then
        return { (tonumber(q.x or q[1]) or 0.0) + 0.0, (tonumber(q.y or q[2]) or 0.0) + 0.0,
            (tonumber(q.z or q[3]) or 0.0) + 0.0, (tonumber(q.w or q[4]) or 1.0) + 0.0 }
    end
    local r = readVec(def.rotation)
    return quatMul(quatAxis(0, 0, 1, r[3]), quatMul(quatAxis(0, 1, 0, r[2]), quatAxis(1, 0, 0, r[1])))
end

local function applyGroupPose(anchor, heading, valid)
    local hq = quatAxis(0, 0, 1, heading)
    for _, part in ipairs(previewGroup) do
        if DoesEntityExist(part.entity) then
            local o = quatRotate(hq, part.offset)
            local wq = quatMul(hq, part.quat)
            SetEntityCoordsNoOffset(part.entity, anchor.x + o[1], anchor.y + o[2], anchor.z + o[3], false, false, false)
            SetEntityQuaternion(part.entity, wq[1], wq[2], wq[3], wq[4])
            if valid then
                SetEntityDrawOutlineColor(80, 220, 120, 255)
            else
                SetEntityDrawOutlineColor(230, 70, 70, 255)
            end
        end
    end
end

-- Shared loop for point/ped/vehicle/screen placement. Two phases: aim (preview
-- follows the crosshair raycast) and, after Enter, a gizmo fine-tune phase
-- (mouse-drag axes to move, scroll rotate, arrow-key nudging with Space step
-- cycling, gold edge handles resize screens) — fine-tune is what makes MLO
-- interiors workable when the ray snags the wrong surface.
---@param kind 'ped' | 'vehicle' | 'coord' | 'screen' | 'object'
local function startLoop(kind, o)
    local currentHeading = (o.initialHeading or GetEntityHeading(PlayerPedId())) or 0.0
    local cur = nil
    local phase = 'aim' -- 'aim' | 'gizmo'
    local NUDGE_STEPS = { 0.01, 0.05, 0.25, 1.0 }
    local stepIdx = 2
    -- Standing peds rest their feet on the ground hit (SetEntityCoords handles the
    -- body offset), so the default lift is 0. Consumers can still raise or lower the
    -- preview with o.zOffset; anim previews measure the posed skeleton instead.
    local zOffset = (kind == 'ped' or kind == 'object') and (tonumber(o.zOffset) or 0.0) or 0.0
    -- Objects can be limited to a reach from the player; out of reach tints the
    -- ghost red and confirm is ignored.
    local maxDistance = kind == 'object' and tonumber(o.maxDistance) or nil
    local placeOk = true
    -- Snap points ({ x, y, z, w, id }) pull the ghost onto the nearest one in
    -- range, taking its position and heading. snapOnly refuses anything else.
    local snaps = kind == 'object' and o.snaps or nil
    local snapOnly = snaps ~= nil and o.snapOnly == true
    local snapRadius = tonumber(o.snapRadius) or 0.75
    local snapped = nil
    -- Screen quads are resizable while aiming (arrow keys) and via the gizmo's
    -- gold handles; the chosen size is returned so consumers can store it per
    -- placement.
    local scrW = tonumber(o.width) or 1.6
    local scrH = tonumber(o.height) or 0.9
    -- Screen tilt (deg, ±90): Ctrl+Scroll in both phases; seeded on re-picks.
    local currentPitch = (kind == 'screen') and (tonumber(o.pitch) or 0.0) or 0.0

    local function confirmAndResolve()
        local result
        if kind == 'coord' then
            result = {
                x = tonumber(('%.4f'):format(cur.x)) + 0.0,
                y = tonumber(('%.4f'):format(cur.y)) + 0.0,
                z = tonumber(('%.4f'):format(cur.z)) + 0.0,
            }
        elseif previewAnimMode and previewEntity and DoesEntityExist(previewEntity) then
            -- Anim preview: capture the compensated ENTITY transform,
            -- so TaskPlayAnim + SetEntityCoordsNoOffset at these coords
            -- reproduces the previewed body position exactly.
            local ec = GetEntityCoords(previewEntity)
            result = {
                x = tonumber(('%.4f'):format(ec.x)) + 0.0,
                y = tonumber(('%.4f'):format(ec.y)) + 0.0,
                z = tonumber(('%.4f'):format(ec.z)) + 0.0,
                w = tonumber(('%.2f'):format(GetEntityHeading(previewEntity))) + 0.0,
            }
        else
            result = {
                x = tonumber(('%.4f'):format(cur.x)) + 0.0,
                y = tonumber(('%.4f'):format(cur.y)) + 0.0,
                z = tonumber(('%.4f'):format(cur.z)) + 0.0,
                w = tonumber(('%.2f'):format(currentHeading)) + 0.0,
            }
            if kind == 'object' and snapped then
                result.x, result.y, result.z = snapped.x, snapped.y, snapped.z
                result.w = snapped.w
                result.snap = snapped.id
            elseif kind == 'object' then
                result.z = tonumber(('%.4f'):format(cur.z + zOffset)) + 0.0
            elseif kind == 'screen' then
                -- The preview centered the quad on the aim point;
                -- store the anchor BELOW it by the consumer's zOffset
                -- so CreateScreen (anchor + zOffset) lands the live
                -- panel exactly where the ghost was.
                result.z = tonumber(('%.4f'):format(cur.z - (tonumber(o.zOffset) or 0.0))) + 0.0
                result.width = tonumber(('%.2f'):format(scrW)) + 0.0
                result.height = tonumber(('%.2f'):format(scrH)) + 0.0
                result.pitch = tonumber(('%.2f'):format(currentPitch)) + 0.0
            end
        end
        resolve(result)
    end

    -- Arrows/space forwarded by the gizmo's NUI overlay (game controls are
    -- dead under NUI focus); mirrors the old frozen-phase nudge scheme.
    local function onGizmoKey(key, mods)
        if key == 'Space' then
            stepIdx = (stepIdx % #NUDGE_STEPS) + 1
            pushHints(gizmoHints(kind, NUDGE_STEPS[stepIdx]))
            return
        end
        local step = NUDGE_STEPS[stepIdx]
        local dx, dy, dz = 0.0, 0.0, 0.0
        if key == 'ArrowUp' then
            if mods.ctrl then dz = step else dy = step end
        elseif key == 'ArrowDown' then
            if mods.ctrl then dz = -step else dy = -step end
        elseif key == 'ArrowLeft' then
            dx = -step
        elseif key == 'ArrowRight' then
            dx = step
        else
            return
        end
        PlacementGizmo.Nudge(dx, dy, dz)
    end

    -- The gizmo has already released NUI focus by the time this fires.
    local function onGizmoDone(outcome)
        if not active then return end
        if outcome == 'confirm' and not placeOk then
            phase = 'aim'
            pushHints(aimHints(kind, scrW, scrH, snapOnly))
        elseif outcome == 'confirm' then
            confirmAndResolve()
        elseif outcome == 'reaim' then
            phase = 'aim'
            pushHints(aimHints(kind, scrW, scrH, snapOnly))
        else
            resolve(nil)
        end
    end

    local function enterGizmo()
        phase = 'gizmo'
        pushHints(gizmoHints(kind, NUDGE_STEPS[stepIdx]))
        PlacementGizmo.Begin({
            matrix = { x = cur.x, y = cur.y, z = cur.z, heading = currentHeading, pitch = currentPitch },
            rotate = kind ~= 'coord',
            tilt = kind == 'screen',
            size = kind == 'screen' and {
                w = scrW,
                h = scrH,
                min = 0.2,
                max = 8.0,
                heading = function() return currentHeading end,
                pitch = function() return currentPitch end,
            } or nil,
            -- The gizmo pose IS `cur` (the anchor point). The draw thread below
            -- keeps applying it to the preview each frame, so the anim-ped bone
            -- compensation and the ghost quad behave exactly as in aim phase.
            onUpdate = function(pose)
                cur = vector3(pose.x, pose.y, pose.z)
                currentHeading = pose.heading
                currentPitch = pose.pitch or currentPitch
            end,
            onSize = function(w, h)
                scrW, scrH = w, h
            end,
            onKey = onGizmoKey,
            -- RMB look mode: camera control back to the player, session intact.
            onLook = function(isLooking)
                pushHints(isLooking and lookHints(kind) or gizmoHints(kind, NUDGE_STEPS[stepIdx]))
            end,
            onDone = onGizmoDone,
        })
    end

    pushHints(aimHints(kind, scrW, scrH, snapOnly))

    CreateThread(function()
        while active do
            if phase == 'aim' then
                local _, hitCoords = raycastFromCamera()
                cur = hitCoords
            end

            if kind == 'object' then
                local anchor, heading = vector3(cur.x, cur.y, cur.z + zOffset), currentHeading
                snapped = nil
                if snaps then
                    local bestDist
                    for _, s in ipairs(snaps) do
                        local d = #(vector3(s.x, s.y, s.z) - cur)
                        if d <= snapRadius and (not bestDist or d < bestDist) then
                            snapped, bestDist = s, d
                        end
                    end
                    if snapped then
                        anchor, heading = vector3(snapped.x, snapped.y, snapped.z), snapped.w
                    end
                end
                placeOk = (not snapOnly or snapped ~= nil)
                    and (not maxDistance or #(anchor - GetEntityCoords(PlayerPedId())) <= maxDistance)
                applyGroupPose(anchor, heading, placeOk)
            elseif previewEntity and DoesEntityExist(previewEntity) then
                local px, py, pz = cur.x, cur.y, cur.z + zOffset
                if previewAnimMode then
                    -- Anim clips pose the body away from the entity origin —
                    -- lying clips keep the origin at STANDING pelvis height
                    -- (~1m above the visible body) and often off-center too.
                    -- Measure the posed skeleton each frame and shift the
                    -- entity so the BODY lands on the crosshair: pelvis
                    -- centers XY, the lowest bone rests on the aimed surface.
                    -- Measurements include current heading/pose, so rotation
                    -- self-corrects a frame later.
                    local ec = GetEntityCoords(previewEntity)
                    local pelvis = GetPedBoneCoords(previewEntity, PELVIS_BONE, 0.0, 0.0, 0.0)
                    px = cur.x - (pelvis.x - ec.x)
                    py = cur.y - (pelvis.y - ec.y)
                    local lowest
                    for _, bone in ipairs(BODY_BONES) do
                        local c = GetPedBoneCoords(previewEntity, bone, 0.0, 0.0, 0.0)
                        if not lowest or c.z < lowest then lowest = c.z end
                    end
                    if lowest then
                        pz = ec.z + (cur.z + zOffset + BONE_SKIN - lowest)
                    end
                    -- The bone math above produces an absolute ENTITY-ORIGIN z, so it
                    -- must be applied without the ground offset SetEntityCoords adds.
                    SetEntityCoordsNoOffset(previewEntity, px, py, pz)
                else
                    -- SetEntityCoords (NOT NoOffset) rests a ped's FEET on z. NoOffset
                    -- puts the origin — the waist — on z, burying the ped to the waist,
                    -- which no per-model constant can correct for. Ported from
                    -- scenedirector's ghost_placer, which had the same bug.
                    SetEntityCoords(previewEntity, px, py, pz, false, false, false, false)
                end
                if kind ~= 'coord' then
                    SetEntityHeading(previewEntity, currentHeading)
                end
            end

            if kind == 'screen' then
                -- The quad centers on the crosshair itself (aim where the
                -- screen should BE); no ground marker — the anchor point is
                -- derived from the panel, not the other way around.
                drawGhostQuad(vector3(cur.x, cur.y, cur.z), currentHeading, currentPitch, scrW, scrH)
            elseif kind == 'coord' then
                -- Translucent sphere + bright center dot on the aimed point — a
                -- flat disc reads as a floor decal and vanishes against walls,
                -- props, and slopes.
                DrawMarker(28, cur.x, cur.y, cur.z, 0, 0, 0, 0, 0, 0,
                    0.5, 0.5, 0.5, MARKER_R, MARKER_G, MARKER_B, 90, false, false, 2, false, nil, nil, false)
                DrawMarker(28, cur.x, cur.y, cur.z, 0, 0, 0, 0, 0, 0,
                    0.1, 0.1, 0.1, MARKER_R, MARKER_G, MARKER_B, 200, false, false, 2, false, nil, nil, false)
            elseif kind == 'ped' then
                -- Ground ring under the ghost ped; lift it a hair so it
                -- doesn't z-fight the floor it's drawn on. Vehicle previews
                -- draw nothing extra — the ghost is the marker.
                local groundZ = cur.z + 0.02
                DrawMarker(
                    1, cur.x, cur.y, groundZ, 0, 0, 0, 0, 0, 0,
                    0.9, 0.9, 0.08, MARKER_R, MARKER_G, MARKER_B, 130,
                    false, false, 2, false, nil, nil, false
                )
            end

            Wait(0)
        end
    end)

    CreateThread(function()
        while active do
            DisableControlAction(0, 14, true)   -- wheel next
            DisableControlAction(0, 15, true)   -- wheel prev
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 22, true)   -- space
            DisableControlAction(0, 36, true)   -- lctrl
            DisableControlAction(0, 172, true)  -- arrow up
            DisableControlAction(0, 173, true)  -- arrow down
            DisableControlAction(0, 174, true)  -- arrow left
            DisableControlAction(0, 175, true)  -- arrow right
            DisableControlAction(0, 201, true)  -- enter
            DisableControlAction(0, 202, true)  -- backspace
            DisablePlayerFiring(PlayerId(), true)

            -- Game-control input only exists in the aim phase; during the
            -- gizmo phase every input arrives through the NUI overlay instead.
            if phase == 'aim' then
                if kind ~= 'coord' then
                    local fine = IsControlPressed(0, 21) -- LSHIFT
                    local step = fine and ROT_STEP_FINE or ROT_STEP
                    -- Screens: LCTRL+Scroll tilts (pitch) instead of rotating.
                    local tiltMode = kind == 'screen'
                        and (IsDisabledControlPressed(0, 36) or IsControlPressed(0, 36))
                    local wheelDown = IsControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 14)
                    local wheelUp = IsControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 15)
                    if tiltMode then
                        if wheelDown then
                            currentPitch = math.max(-90.0, currentPitch - step)
                        elseif wheelUp then
                            currentPitch = math.min(90.0, currentPitch + step)
                        end
                    else
                        if wheelDown then
                            currentHeading = (currentHeading - step) % 360.0
                        end
                        if wheelUp then
                            currentHeading = (currentHeading + step) % 360.0
                        end
                    end
                end

                if kind == 'screen' then
                    local step = (IsDisabledControlPressed(0, 21) or IsControlPressed(0, 21)) and 0.01 or 0.05
                    local resized = true
                    if IsDisabledControlJustPressed(0, 172) then
                        scrH = math.min(8.0, scrH + step)
                    elseif IsDisabledControlJustPressed(0, 173) then
                        scrH = math.max(0.2, scrH - step)
                    elseif IsDisabledControlJustPressed(0, 175) then
                        scrW = math.min(8.0, scrW + step)
                    elseif IsDisabledControlJustPressed(0, 174) then
                        scrW = math.max(0.2, scrW - step)
                    else
                        resized = false
                    end
                    if resized then
                        pushHints(aimHints(kind, scrW, scrH, snapOnly)) -- live size readout
                    end
                end

                local enter = IsDisabledControlJustPressed(0, 201)
                local lmb = IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24)
                if cur and lmb and placeOk then
                    confirmAndResolve()
                    return
                elseif cur and enter and not snapOnly then
                    enterGizmo()
                end

                -- 202 (FRONTEND_CANCEL) fires for both Backspace and ESC; ESC also
                -- fires 200 (PAUSE_ALTERNATE). The distinction only matters during
                -- fine-tune, where the browser reports the real key — here in the
                -- aim phase both cancel.
                local esc = IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 200)
                if esc or IsDisabledControlJustPressed(0, 202)
                    or IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25) then
                    resolve(nil)
                    return
                end
            end

            Wait(0)
        end
    end)
end

-- Streamed props register through the archetype path only, so either check
-- passing means the model can load. Times out to nil rather than erroring: an
-- error here would surface in the consumer's awaiting thread.
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) and not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(0)
    end
    return hash
end

-- ---------------------------------------------------------------------------
-- Public builders (await-style)
-- ---------------------------------------------------------------------------

---Raycast-only point picker. Returns { x, y, z } or nil.
local function Coord(o)
    if active then return nil end
    o = o or {}
    active = true
    currentPromise = promise.new()
    startLoop('coord', o)
    return Citizen.Await(currentPromise)
end

---Raycast entity picker: the entity under the crosshair highlights with an
---outline and LMB snaps to its center. Returns { x, y, z, w } — the entity's
---origin and heading — or nil. For points that belong to a prop/ped/vehicle
---already placed in the world (stashes, doors, machines): the stored point
---lands exactly on the entity no matter where the ray grazed it.
local function Entity()
    if active then return nil end
    active = true
    currentPromise = promise.new()

    pushHints({
        icon = 'cube',
        label = 'Entity',
        phase = 'Aim',
        lines = {
            { { key = 'LMB', desc = 'select entity', tone = 'green' } },
            { { key = 'RMB / ESC', desc = 'cancel', tone = 'neutral' } },
        },
    })

    CreateThread(function()
        while active do
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 202, true)
            DisablePlayerFiring(PlayerId(), true)

            local hit, hitCoords, hitEntity = raycastFromCamera()
            local target, targetCoords = nil, nil
            if hit and hitEntity and hitEntity ~= 0 and hitEntity ~= PlayerPedId()
                and DoesEntityExist(hitEntity) then
                target = hitEntity
                targetCoords = GetEntityCoords(hitEntity)
            end

            if outlinedEntity ~= target then
                clearOutline()
                if target then
                    SetEntityDrawOutline(target, true)
                    SetEntityDrawOutlineColor(MARKER_R, MARKER_G, MARKER_B, 255)
                    SetEntityDrawOutlineShader(1)
                    outlinedEntity = target
                end
            end

            if target then
                DrawMarker(28, targetCoords.x, targetCoords.y, targetCoords.z, 0, 0, 0, 0, 0, 0,
                    0.15, 0.15, 0.15, MARKER_R, MARKER_G, MARKER_B, 200, false, false, 2, false, nil, nil, false)
            elseif hit then
                DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z, 0, 0, 0, 0, 0, 0,
                    0.1, 0.1, 0.1, MARKER_R, MARKER_G, MARKER_B, 120, false, false, 2, false, nil, nil, false)
            end

            if target and (IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24)) then
                local heading = GetEntityHeading(target)
                resolve({
                    x = tonumber(('%.4f'):format(targetCoords.x)) + 0.0,
                    y = tonumber(('%.4f'):format(targetCoords.y)) + 0.0,
                    z = tonumber(('%.4f'):format(targetCoords.z)) + 0.0,
                    w = tonumber(('%.2f'):format(heading)) + 0.0,
                })
                return
            end

            if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25)
                or IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 200)
                or IsDisabledControlJustPressed(0, 202) then
                resolve(nil)
                return
            end

            Wait(0)
        end
    end)

    return Citizen.Await(currentPromise)
end

---Ghost ped picker. Returns { x, y, z, w } or nil.
---o.anim = { dict, clip } plays a looped pose on the preview so consumers can
---aim animation-facing placements (beds, chairs). The placement loop measures
---the posed pelvis every frame and shifts the entity so the VISIBLE BODY —
---not the ped origin — stays centered on the aim point regardless of the
---clip's authored root offset. The returned coords are then the compensated
---ENTITY position/heading: replaying the same clip via TaskPlayAnim +
---SetEntityCoordsNoOffset at exactly those coords reproduces what the admin
---saw. Without an anim the returned coords are the raw surface hit — the point
---the ped's FEET rest on, so consumers spawn with CreatePed/SetEntityCoords at
---that z and must NOT subtract a body-height fudge. o.zOffset (default 0)
---raises or lowers the preview off that surface.
local function GhostPed(o)
    if active then return nil end
    o = o or {}
    local hash = loadModel(o.model or 'a_m_y_business_03')
    if not hash then return nil end

    active = true
    currentPromise = promise.new()
    previewModelHash = hash
    local pc = GetEntityCoords(PlayerPedId())
    previewEntity = CreatePed(4, hash, pc.x, pc.y, pc.z, 0.0, false, false)
    if not previewEntity or previewEntity == 0 then
        active = false
        currentPromise = nil
        unloadModel()
        return nil
    end
    ghostify(previewEntity)
    if type(o.anim) == 'table' and o.anim.dict and (o.anim.clip or o.anim.name) then
        local clip = o.anim.clip or o.anim.name
        RequestAnimDict(o.anim.dict)
        local deadline = GetGameTimer() + 2000
        while not HasAnimDictLoaded(o.anim.dict) and GetGameTimer() < deadline do Wait(10) end
        if HasAnimDictLoaded(o.anim.dict) and previewEntity and DoesEntityExist(previewEntity) then
            TaskPlayAnim(previewEntity, o.anim.dict, clip, 8.0, 8.0, -1, 1, 0.0, false, false, false)
            previewAnimMode = true
        end
    end
    startLoop('ped', o)
    return Citizen.Await(currentPromise)
end

---Ghost screen-panel picker: a translucent quad, CENTERED ON THE CROSSHAIR,
---previews where a CreateScreen panel will float — aim directly at where the
---screen should be. Arrow keys resize while aiming (LSHIFT fine); Ctrl+Scroll
---tilts; the gizmo's gold edge handles resize during fine-tune. Returns
---{ x, y, z, w, width, height, pitch } or nil; z is the anchor BELOW the quad
---center by o.zOffset, so CreateScreen with the returned coords/size/pitch and
---the SAME zOffset lands the live panel exactly on the preview.
---o = { width?, height?, zOffset?, initialHeading?, pitch? } (width/height/pitch seed re-picks)
local function GhostScreen(o)
    if active then return nil end
    o = o or {}
    active = true
    currentPromise = promise.new()
    startLoop('screen', o)
    return Citizen.Await(currentPromise)
end

---Ghost vehicle picker. Returns { x, y, z, w } or nil.
local function GhostVehicle(o)
    if active then return nil end
    o = o or {}
    if type(o.model) ~= 'string' or o.model == '' then return nil end
    local hash = loadModel(o.model)
    if not hash then return nil end

    active = true
    currentPromise = promise.new()
    previewModelHash = hash
    local pc = GetEntityCoords(PlayerPedId())
    previewEntity = CreateVehicle(hash, pc.x, pc.y, pc.z, 0.0, false, false)
    if not previewEntity or previewEntity == 0 then
        active = false
        currentPromise = nil
        unloadModel()
        return nil
    end
    ghostify(previewEntity)
    startLoop('vehicle', o)
    return Citizen.Await(currentPromise)
end

---Ghost object picker for placeable props. Previews one model, or a rigid group
---laid out around the anchor exactly as a consumer would spawn it.
---o = { model?, objects?, initialHeading?, zOffset?, maxDistance?, snaps?, snapOnly?, snapRadius? }
---objects = { { model, offset?, rotation?, quat? }, ... } — offset is local metres,
---rotation local degrees (X, then Y, then Z), quat a local {x,y,z,w} that overrides
---rotation. Unloadable models are skipped; nil if none load.
---snaps = { { x, y, z, w, id }, ... } — aiming within snapRadius (0.75) of one locks the
---group to its position and heading; snapOnly refuses to confirm anywhere else.
---Returns { x, y, z, w, snap? }: the group anchor (surface hit + zOffset, or the snap
---point) and heading, plus the snap id when snapped.
local function GhostObject(o)
    if active then return nil end
    o = o or {}
    local defs = type(o.objects) == 'table' and o.objects or { { model = o.model } }

    local pc = GetEntityCoords(PlayerPedId())
    for _, def in ipairs(defs) do
        local hash = def.model and loadModel(def.model)
        if hash then
            previewGroupHashes[#previewGroupHashes + 1] = hash
            local entity = CreateObjectNoOffset(hash, pc.x, pc.y, pc.z, false, false, false)
            if entity and entity ~= 0 then
                ghostify(entity)
                SetEntityDrawOutline(entity, true)
                previewGroup[#previewGroup + 1] = { entity = entity, offset = readVec(def.offset), quat = readLocalQuat(def) }
            end
        end
    end
    if #previewGroup == 0 then
        unloadModel()
        return nil
    end
    SetEntityDrawOutlineShader(1)

    active = true
    currentPromise = promise.new()
    startLoop('object', o)
    return Citizen.Await(currentPromise)
end

local function IsActive()
    return active or polyActive == true
end

local function Cancel()
    if active then resolve(nil) end
    if polyActive and polyCancel then polyCancel() end
end

-- ---------------------------------------------------------------------------
-- Polygon builder (freecam zone authoring). Returns { shape, minZ, maxZ } or nil.
-- ---------------------------------------------------------------------------
local POLY_THICKNESS_DEFAULT = 6.0
local POLY_NUDGE_SPEEDS = { 0.05, 0.25, 1.0, 5.0 }
local POLY_DEFAULT_NUDGE_INDEX = 2
local POLY_FREECAM_SPEED_BASE = 0.25
local POLY_FREECAM_MOUSE_SENS = 6.0

local function polyHints(mode, numPoints, thickness, nudge)
    return {
        icon = 'polygon',
        label = 'Zone Builder',
        phase = mode == 'edit' and 'Edit' or 'Place',
        phaseHot = mode == 'edit',
        lines = {
            {
                { key = 'WASD/Q/E', desc = 'fly', tone = 'pink' },
                { key = 'Enter', desc = 'place / select', tone = 'pink' },
                { key = 'RMB', desc = 'select', tone = 'pink' },
            },
            {
                { key = '↑↓←→', desc = ('nudge %.2fm'):format(nudge), tone = 'pink' },
                { key = 'Tab', desc = 'speed', tone = 'pink' },
                { key = 'R', desc = 'mode', tone = 'pink' },
            },
            {
                { key = 'PgUp/PgDn', desc = ('thickness %.1fm'):format(thickness), tone = 'pink' },
                { key = 'P', desc = 'preview', tone = 'pink' },
            },
            {
                { key = 'Del', desc = 'remove', tone = 'neutral' },
                { key = 'Bksp', desc = 'clear all', tone = 'neutral' },
            },
            {
                { key = 'Space', desc = ('save (%d points)'):format(numPoints), tone = 'green' },
                { key = 'ESC', desc = 'cancel', tone = 'neutral' },
            },
        },
    }
end

local function loadExistingPoints(existing, fallbackZ)
    local pts = {}
    if type(existing) ~= 'table' then return pts, POLY_THICKNESS_DEFAULT end
    local shape = existing.shape or existing.points
    if type(shape) ~= 'table' then return pts, POLY_THICKNESS_DEFAULT end
    for _, p in ipairs(shape) do
        local px = tonumber(p.x or p[1])
        local py = tonumber(p.y or p[2])
        local pz = tonumber(p.z or p[3]) or fallbackZ
        if px and py then pts[#pts + 1] = vector3(px + 0.0, py + 0.0, pz + 0.0) end
    end
    local thickness
    if existing.minZ and existing.maxZ then
        thickness = (tonumber(existing.maxZ) - tonumber(existing.minZ))
    end
    if not thickness or thickness < 1.0 then thickness = POLY_THICKNESS_DEFAULT end
    return pts, thickness + 0.0
end

local function Polygon(o)
    if active or polyActive then return nil end
    o = o or {}

    polyActive = true
    local p = promise.new()

    local ped = PlayerPedId()
    local startCoords = GetEntityCoords(ped)
    local startHeading = GetEntityHeading(ped)

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)

    local points, thickness = loadExistingPoints(o.existing, startCoords.z)
    local mode = 'place'
    local selectedIdx = 0
    local nudgeIdx = POLY_DEFAULT_NUDGE_INDEX
    local debugZone = nil
    local lastHintKey = nil

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, startCoords.x, startCoords.y, startCoords.z + 1.5)
    SetCamRot(cam, 0.0, 0.0, startHeading, 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    local camRot = vector3(0.0, 0.0, startHeading)

    local function clearDebugZone()
        if debugZone and debugZone.remove then
            pcall(function() debugZone:remove() end)
            debugZone = nil
        end
    end

    local function cleanup()
        pushHints(nil)
        clearDebugZone()
        RenderScriptCams(false, true, 500, true, true)
        if cam then
            SetCamActive(cam, false)
            DestroyCam(cam, false)
            cam = nil
        end
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, false)
        polyActive = false
    end

    -- Single resolve path (save / ESC / external Cancel); guards double-fire.
    local resolved = false
    local function resolvePoly(result)
        if resolved then return end
        resolved = true
        polyCancel = nil
        cleanup()
        p:resolve(result)
    end
    polyCancel = function() resolvePoly(nil) end

    local function raycastFromCam()
        local cc = GetCamCoord(cam)
        local cr = GetCamRot(cam, 2)
        local rZ = math.rad(cr.z)
        local rX = math.rad(cr.x)
        local cosX = math.cos(rX)
        local dir = vector3(-math.sin(rZ) * cosX, math.cos(rZ) * cosX, math.sin(rX))
        local dest = cc + dir * 200.0
        local _, hit, hitCoords = GetShapeTestResult(
            StartShapeTestRay(cc.x, cc.y, cc.z, dest.x, dest.y, dest.z, 17, 0, 7)
        )
        if hit == 1 then return hitCoords end
        return nil
    end

    local function selectNearest(hitPos)
        if #points == 0 then return end
        local bestDist, bestIdx = 2.0, 0
        for i, pt in ipairs(points) do
            local d = #(pt - hitPos)
            if d < bestDist then bestDist = d; bestIdx = i end
        end
        if bestIdx > 0 then selectedIdx = bestIdx end
    end

    local function refreshPreview()
        if not debugZone then return end
        clearDebugZone()
        if #points >= 3 then
            debugZone = lib.zones.poly({ points = points, thickness = thickness, debug = true })
        end
    end

    local function togglePreview()
        if debugZone then clearDebugZone(); return end
        if #points < 3 then return end
        debugZone = lib.zones.poly({ points = points, thickness = thickness, debug = true })
    end

    local function drawPoints()
        local halfT = thickness / 2
        local numPoints = #points
        for i, pt in ipairs(points) do
            local r, g, b = 232, 176, 68
            if i == selectedIdx then r, g, b = 255, 220, 0 end
            DrawMarker(28, pt.x, pt.y, pt.z, 0,0,0, 0,0,0, 0.18, 0.18, 0.18, r, g, b, 220, false, true, 2, false, nil, nil, false)
            DrawLine(pt.x, pt.y, pt.z - halfT, pt.x, pt.y, pt.z + halfT, r, g, b, 200)
        end
        if numPoints >= 2 then
            for i = 1, numPoints do
                local p1 = points[i]
                local p2 = points[i % numPoints + 1]
                DrawLine(p1.x, p1.y, p1.z + halfT, p2.x, p2.y, p2.z + halfT, 232, 176, 68, 200)
                DrawLine(p1.x, p1.y, p1.z - halfT, p2.x, p2.y, p2.z - halfT, 232, 176, 68, 200)
            end
        end
        if numPoints >= 3 then
            for i = 2, numPoints - 1 do
                local a, b2, c = points[1], points[i], points[i + 1]
                DrawPoly(a.x, a.y, a.z + halfT, b2.x, b2.y, b2.z + halfT, c.x, c.y, c.z + halfT, 232, 176, 68, 50)
                DrawPoly(c.x, c.y, c.z + halfT, b2.x, b2.y, b2.z + halfT, a.x, a.y, a.z + halfT, 232, 176, 68, 50)
            end
        end
    end

    CreateThread(function()
        while polyActive do
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)

            local mouseX = GetDisabledControlNormal(0, 1) * POLY_FREECAM_MOUSE_SENS
            local mouseY = GetDisabledControlNormal(0, 2) * POLY_FREECAM_MOUSE_SENS
            camRot = vector3(math.max(-89.0, math.min(89.0, camRot.x - mouseY)), camRot.y, camRot.z - mouseX)
            SetCamRot(cam, camRot.x, camRot.y, camRot.z, 2)

            local rZ = math.rad(camRot.z)
            local rX = math.rad(camRot.x)
            local cosZ, sinZ = math.cos(rZ), math.sin(rZ)
            local cosX, sinX = math.cos(rX), math.sin(rX)
            local v = vector3(0, 0, 0)
            if IsDisabledControlPressed(0, 32) then v = v + vector3(-sinZ * cosX, cosZ * cosX, sinX) end
            if IsDisabledControlPressed(0, 33) then v = v + vector3( sinZ * cosX, -cosZ * cosX, -sinX) end
            if IsDisabledControlPressed(0, 34) then v = v + vector3(-cosZ, -sinZ, 0) end
            if IsDisabledControlPressed(0, 35) then v = v + vector3( cosZ,  sinZ, 0) end
            if IsDisabledControlPressed(0, 38) then v = v + vector3(0, 0, 1) end
            if IsDisabledControlPressed(0, 44) then v = v + vector3(0, 0, -1) end

            local mult = 1.0
            if IsDisabledControlPressed(0, 21) and selectedIdx == 0 then mult = 3.0 end
            if IsDisabledControlPressed(0, 36) then mult = 0.3 end

            local frameMult = GetFrameTime() * 60.0
            local pos = GetCamCoord(cam)
            local newPos = pos + (v * POLY_FREECAM_SPEED_BASE * mult * frameMult)
            SetCamCoord(cam, newPos.x, newPos.y, newPos.z)

            local hitPos = raycastFromCam()
            drawPoints()
            if hitPos then
                DrawMarker(28, hitPos.x, hitPos.y, hitPos.z, 0,0,0, 0,0,0, 0.1, 0.1, 0.1, 0, 200, 255, 220, false, true, 2, false, nil, nil, false)
            end
            -- Hint card re-pushes only when the displayed state changes.
            local hintKey = ('%s|%d|%.1f|%d'):format(mode, #points, thickness, nudgeIdx)
            if hintKey ~= lastHintKey then
                lastHintKey = hintKey
                pushHints(polyHints(mode, #points, thickness, POLY_NUDGE_SPEEDS[nudgeIdx]))
            end

            if IsDisabledControlJustPressed(0, 18) then
                if mode == 'place' and hitPos then
                    points[#points + 1] = vector3(
                        tonumber(('%.4f'):format(hitPos.x)) + 0.0,
                        tonumber(('%.4f'):format(hitPos.y)) + 0.0,
                        tonumber(('%.4f'):format(hitPos.z)) + 0.0)
                    selectedIdx = #points
                    refreshPreview()
                elseif mode == 'edit' and hitPos then
                    selectNearest(hitPos)
                end
            end
            if IsDisabledControlJustPressed(0, 25) and hitPos then selectNearest(hitPos) end

            if selectedIdx > 0 and selectedIdx <= #points then
                local nudge = POLY_NUDGE_SPEEDS[nudgeIdx]
                local pt = points[selectedIdx]
                local moved = false
                if IsDisabledControlPressed(0, 172) then
                    points[selectedIdx] = IsDisabledControlPressed(0, 21) and vector3(pt.x, pt.y, pt.z + nudge) or vector3(pt.x, pt.y + nudge, pt.z); moved = true
                end
                if IsDisabledControlPressed(0, 173) then
                    pt = points[selectedIdx]
                    points[selectedIdx] = IsDisabledControlPressed(0, 21) and vector3(pt.x, pt.y, pt.z - nudge) or vector3(pt.x, pt.y - nudge, pt.z); moved = true
                end
                if IsDisabledControlPressed(0, 174) then pt = points[selectedIdx]; points[selectedIdx] = vector3(pt.x - nudge, pt.y, pt.z); moved = true end
                if IsDisabledControlPressed(0, 175) then pt = points[selectedIdx]; points[selectedIdx] = vector3(pt.x + nudge, pt.y, pt.z); moved = true end
                if moved then refreshPreview() end
            end

            if IsDisabledControlJustPressed(0, 37) then nudgeIdx = nudgeIdx % #POLY_NUDGE_SPEEDS + 1 end
            if IsDisabledControlJustPressed(0, 45) then mode = mode == 'place' and 'edit' or 'place' end
            if IsDisabledControlJustPressed(0, 10) then thickness = math.min(50.0, thickness + (IsDisabledControlPressed(0, 21) and 5.0 or 1.0)); refreshPreview() end
            if IsDisabledControlJustPressed(0, 11) then thickness = math.max(1.0, thickness - (IsDisabledControlPressed(0, 21) and 5.0 or 1.0)); refreshPreview() end
            if IsDisabledControlJustPressed(0, 199) then togglePreview() end

            if IsDisabledControlJustPressed(0, 178) then
                if mode == 'edit' and selectedIdx > 0 and selectedIdx <= #points then
                    table.remove(points, selectedIdx)
                    if selectedIdx > #points then selectedIdx = #points end
                elseif #points > 0 then
                    points[#points] = nil
                    if selectedIdx > #points then selectedIdx = #points end
                end
                refreshPreview()
            end
            if IsDisabledControlJustPressed(0, 194) then points = {}; selectedIdx = 0; clearDebugZone() end

            if IsDisabledControlJustPressed(0, 22) and #points >= 3 then
                local sumZ, outShape = 0.0, {}
                for i, pt in ipairs(points) do
                    outShape[i] = {
                        x = tonumber(('%.4f'):format(pt.x)) + 0.0,
                        y = tonumber(('%.4f'):format(pt.y)) + 0.0,
                        z = tonumber(('%.4f'):format(pt.z)) + 0.0,
                    }
                    sumZ = sumZ + pt.z
                end
                local avgZ = sumZ / #points
                resolvePoly({
                    shape = outShape,
                    minZ  = tonumber(('%.2f'):format(avgZ - thickness / 2)) + 0.0,
                    maxZ  = tonumber(('%.2f'):format(avgZ + thickness / 2)) + 0.0,
                })
                return
            end

            if IsDisabledControlJustPressed(0, 200) then
                resolvePoly(nil)
                return
            end

            Wait(0)
        end
        -- Backstop for an external polyActive=false (resource stop): resolves
        -- the await and re-runs cleanup (idempotent) if resolvePoly already did.
        resolvePoly(nil)
    end)

    return Citizen.Await(p)
end

-- ---------------------------------------------------------------------------
-- Overlay markers: persistent editor annotations (colored ground cylinders +
-- floating labels over placed items). Grouped by id so several tools can
-- overlay at once; SetMarkers replaces the whole group. One shared draw
-- thread lives here so builder tools stop each running their own.
-- ---------------------------------------------------------------------------
local OVERLAY_DRAW_DIST = 200.0
local OVERLAY_LABEL_DIST = 30.0

local overlays = {}
local overlayThread = false

local function drawOverlayLabel(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

local function startOverlayThread()
    if overlayThread then return end
    overlayThread = true
    CreateThread(function()
        while next(overlays) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local drewAny = false
            for _, markers in pairs(overlays) do
                for _, m in ipairs(markers) do
                    local dist = #(playerCoords - vector3(m.x, m.y, m.z))
                    if dist < OVERLAY_DRAW_DIST then
                        drewAny = true
                        DrawMarker(1, m.x, m.y, m.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.scale, m.scale, 2.0, m.r, m.g, m.b, m.a,
                            false, true, 2, false, nil, nil, false)
                        if m.label and dist < OVERLAY_LABEL_DIST then
                            drawOverlayLabel(m.x, m.y, m.z + 1.5, m.label)
                        end
                    end
                end
            end
            Wait(drewAny and 0 or 250)
        end
        overlayThread = false
    end)
end

local function channel(col, key, idx, default)
    local v = col and tonumber(col[key] or col[idx])
    return v and math.floor(v) or default
end

---Replace a group's overlay markers. markers: array of
---{ coords = {x,y,z} | vector3/4, color? = {r,g,b,a?}, label?, scale? }.
---nil/empty markers clears the group.
local function SetMarkers(id, markers)
    if type(id) ~= 'string' or id == '' then return false end

    local clean = {}
    for _, m in ipairs(type(markers) == 'table' and markers or {}) do
        local c = m.coords
        local x, y, z = c and tonumber(c.x), c and tonumber(c.y), c and tonumber(c.z)
        if x and y and z then
            local col = type(m.color) == 'table' and m.color or nil
            clean[#clean + 1] = {
                x = x + 0.0, y = y + 0.0, z = z + 0.0,
                r = channel(col, 'r', 1, MARKER_R),
                g = channel(col, 'g', 2, MARKER_G),
                b = channel(col, 'b', 3, MARKER_B),
                a = channel(col, 'a', 4, 180),
                scale = tonumber(m.scale) or 1.0,
                label = type(m.label) == 'string' and m.label ~= '' and m.label or nil,
            }
        end
    end

    overlays[id] = #clean > 0 and clean or nil
    if next(overlays) then startOverlayThread() end
    return true
end

---Clear one overlay group, or every group when id is omitted.
local function ClearMarkers(id)
    if id ~= nil then
        overlays[id] = nil
    else
        overlays = {}
    end
end

-- ---------------------------------------------------------------------------
-- Screen panels: NUI pages painted onto world-space quads via DUI. No prop and
-- no NUI focus - consumers push content with SendScreenMessage and handle
-- interaction through their own target zones. One shared draw thread.
-- ---------------------------------------------------------------------------
local SCREEN_DRAW_DIST = 50.0

local screens = {}
local screenSeq = 0
local screenThread = false
local DestroyScreen

local function startScreenThread()
    if screenThread then return end
    screenThread = true
    CreateThread(function()
        while next(screens) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local drewAny = false
            for _, s in pairs(screens) do
                if #(playerCoords - s.center) < SCREEN_DRAW_DIST then
                    drewAny = true
                    local tl, tr, bl, br = s.tl, s.tr, s.bl, s.br
                    -- Front face
                    DrawSpritePoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z,
                        255, 255, 255, 255, s.txd, s.txn, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0)
                    DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z,
                        255, 255, 255, 255, s.txd, s.txn, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0)
                    -- Back face (mirrored) so the panel is visible from both sides
                    DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z,
                        255, 255, 255, 255, s.txd, s.txn, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0)
                    DrawSpritePoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z,
                        255, 255, 255, 255, s.txd, s.txn, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0)
                end
            end
            Wait(drewAny and 0 or 250)
        end
        screenThread = false
    end)
end

---Create (or replace) a world-space DUI screen. opts:
---{ id, url, coords = {x,y,z}|vector, heading? (deg the panel faces),
---  pitch? (deg tilt, ±90), width? (m, default 1.6), height? (m, default 0.9),
---  zOffset? (m), resolution? = { w, h } (px, default 1280x720) }
---Returns true on success.
local function CreateScreen(opts)
    if type(opts) ~= 'table' or type(opts.id) ~= 'string' or opts.id == '' then return false end
    if type(opts.url) ~= 'string' or opts.url == '' then return false end
    local c = opts.coords
    local x, y, z = c and tonumber(c.x), c and tonumber(c.y), c and tonumber(c.z)
    if not (x and y and z) then return false end

    if screens[opts.id] then DestroyScreen(opts.id) end

    local res = type(opts.resolution) == 'table' and opts.resolution or {}
    local resW = math.floor(tonumber(res.w or res[1]) or 1280)
    local resH = math.floor(tonumber(res.h or res[2]) or 720)

    local dui = CreateDui(opts.url, resW, resH)
    if not dui then return false end

    screenSeq = screenSeq + 1
    local txd = ('olink_screen_%d'):format(screenSeq)
    local txn = 'panel'
    local runtimeTxd = CreateRuntimeTxd(txd)
    CreateRuntimeTextureFromDuiHandle(runtimeTxd, txn, GetDuiHandle(dui))

    local width = tonumber(opts.width) or 1.6
    local height = tonumber(opts.height) or 0.9
    local center = vector3(x, y, z + (tonumber(opts.zOffset) or 0.0))
    local r, u = quadBasis(tonumber(opts.heading) or 0.0, tonumber(opts.pitch) or 0.0)
    local right = r * (width / 2)
    local up = u * (height / 2)

    screens[opts.id] = {
        dui = dui,
        txd = txd,
        txn = txn,
        center = center,
        tl = center - right + up,
        tr = center + right + up,
        bl = center - right - up,
        br = center + right - up,
    }
    startScreenThread()
    return true
end

---Push a JSON-encodable payload into a screen's DUI page (window message).
local function SendScreenMessage(id, data)
    local s = screens[id]
    if not s then return false end
    SendDuiMessage(s.dui, json.encode(data))
    return true
end

DestroyScreen = function(id)
    local s = screens[id]
    if not s then return false end
    screens[id] = nil
    if s.dui then DestroyDui(s.dui) end
    return true
end

---Destroy every screen (or use DestroyScreen(id) for one).
local function ClearScreens()
    for id in pairs(screens) do
        DestroyScreen(id)
    end
end

olink._register('placement', {
    Coord = Coord,
    Entity = Entity,
    GhostPed = GhostPed,
    GhostVehicle = GhostVehicle,
    GhostScreen = GhostScreen,
    GhostObject = GhostObject,
    Polygon = Polygon,
    IsActive = IsActive,
    Cancel = Cancel,
    SetMarkers = SetMarkers,
    ClearMarkers = ClearMarkers,
    CreateScreen = CreateScreen,
    SendScreenMessage = SendScreenMessage,
    DestroyScreen = DestroyScreen,
    ClearScreens = ClearScreens,
})

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Cancel()
        polyActive = false
        ClearScreens()
        -- Backstop: the NUI frame dies with the resource, but a focus grab
        -- taken by a live gizmo session must not outlive it.
        SetNuiFocus(false, false)
    end
end)
