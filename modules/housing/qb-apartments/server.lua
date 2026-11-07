-- QBCore housing provider. Bridges qb-apartments (starter apartments) and
-- qb-houses (owned homes) behind the single o-link `housing` namespace, since a
-- QBCore server commonly runs both. Each function gates on the specific resource
-- at call time so whichever of the two is installed is used.

local APARTMENTS = 'qb-apartments'
local HOUSES = 'qb-houses'

if GetResourceState(APARTMENTS) == 'missing' and GetResourceState(HOUSES) == 'missing' then return end
if not olink._guardImpl('Housing', APARTMENTS, false) then return end

-- rcore_housing `provide`s both names without their tables, so a started name
-- alone does not mean the tables exist. Cached once known.
local tableCache = {}
local function TableExists(name)
    if tableCache[name] ~= nil then return tableCache[name] end
    local count = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
    ]], { name }))
    if not count then return false end
    tableCache[name] = count > 0
    return tableCache[name]
end

local function aptStarted()
    return GetResourceState(APARTMENTS) == 'started' and TableExists('apartments')
end

local function housesStarted()
    return GetResourceState(HOUSES) == 'started' and TableExists('player_houses') and TableExists('houselocations')
end

-- Presence relay (kept from the former qb-houses adapter): mirror the player's
-- inside/outside state into the housing relay.
RegisterNetEvent('qb-houses:server:SetInsideMeta', function(insideId, bool)
    local src = source
    TriggerEvent('o-link:server:OnPlayerInside', src, bool and insideId or nil)
end)

local function getCitizenId(src)
    local ok, player = pcall(function() return exports['qb-core']:GetPlayer(src) end)
    if ok and player and player.PlayerData then return player.PlayerData.citizenid end
    return nil
end

-- Mirror qb-apartments' CreateApartmentId: a random, unused apartment name.
local function makeApartmentId(aptType)
    for _ = 1, 100 do
        local num = math.random(1, 1000000)
        local id = aptType .. num
        if not MySQL.scalar.await('SELECT 1 FROM apartments WHERE name = ?', { id }) then
            return id, num
        end
    end
end

-- qb-apartments keeps apartment definitions (label + building exterior) only in its
-- own config (no DB column, no export). Sandbox-load that config once to map
-- apartment `type` -> { label, coords } for spawn-selector markers and the
-- starter-apartment picker. Best-effort: on any failure apartments list without coords.
local function loadAptDefs()
    local src = LoadResourceFile(APARTMENTS, 'config.lua')
    if not src then return {} end

    local vec = function(x, y, z) return { x = x, y = y, z = z } end
    local env = { Apartments = {}, vector4 = vec, vector3 = vec, vec4 = vec, vec3 = vec }
    local chunk = load(src, '@qb-apartments/config.lua', 't', env)
    if not chunk or not pcall(chunk) then return {} end

    local out = {}
    for aptType, data in pairs(env.Apartments.Locations or {}) do
        local e = data.coords and data.coords.enter
        out[aptType] = {
            type = aptType,
            label = data.label or aptType,
            coords = (type(e) == 'table' and e.x) and { x = e.x, y = e.y, z = e.z } or nil,
        }
    end
    return out
end

local aptDefs = loadAptDefs()

olink._register('housing', {
    GetResourceName = function()
        if GetResourceState(APARTMENTS) == 'started' then return APARTMENTS end
        if GetResourceState(HOUSES) == 'started' then return HOUSES end
        return APARTMENTS
    end,

    GetOwnedProperties = function(src, identifier)
        local cid = identifier or getCitizenId(src)
        if not cid then return {} end
        local out = {}
        if aptStarted() then
            local rows = MySQL.query.await('SELECT name, label, type FROM apartments WHERE citizenid = ?', { cid }) or {}
            for _, a in ipairs(rows) do
                local def = aptDefs[a.type]
                out[#out + 1] = { id = a.name, kind = 'apartment', label = a.label, coords = def and def.coords }
            end
        end
        if housesStarted() then
            local rows = MySQL.query.await(
                'SELECT pl.house AS id, hl.label AS label, hl.coords AS coords FROM player_houses pl LEFT JOIN houselocations hl ON hl.name = pl.house WHERE pl.citizenid = ?',
                { cid }) or {}
            for _, h in ipairs(rows) do
                local entry = { id = h.id, kind = 'house', label = h.label or h.id }
                local ok, c = pcall(json.decode, h.coords)
                if ok and type(c) == 'table' then
                    local e = c.enter or c
                    if type(e) == 'table' and e.x then entry.coords = { x = e.x, y = e.y, z = e.z } end
                end
                out[#out + 1] = entry
            end
        end
        return out
    end,

    -- Selectable starter apartments for the multichar picker: every location
    -- qb-apartments defines, each with its building exterior for the marker.
    ListStarterApartments = function()
        if not aptStarted() then return {} end
        local out = {}
        for _, def in pairs(aptDefs) do
            out[#out + 1] = { key = def.type, label = def.label, coords = def.coords }
        end
        table.sort(out, function(a, b) return a.key < b.key end)
        return out
    end,

    -- `def` is supplied by the caller (oxide-multichar); expects `type` (a key in
    -- qb-apartments' Apartments.Locations) and `label`.
    --
    -- Entry goes through `LastLocationHouse` (new=false), NOT `SpawnInApartment`
    -- (new=true). The latter flags qb-interior's new-character state, which fires
    -- `qb-clothes:client:CreateFirstCharacter` ~750ms after the interior loads —
    -- a second clothing editor. multichar's own creator already set the look, so
    -- every o-link entry path must avoid that flag.
    CreateStartingApartment = function(src, def)
        if not aptStarted() then return false end
        local cid = getCitizenId(src)
        if not cid then return false end

        -- Already owns an apartment: enter it rather than create a duplicate.
        local existing = MySQL.single.await('SELECT name, type, label FROM apartments WHERE citizenid = ?', { cid })
        if existing then
            TriggerClientEvent('qb-apartments:client:LastLocationHouse', src, existing.type, existing.name)
            return { id = existing.name, label = existing.label }
        end

        if type(def) ~= 'table' or not def.type then return false end
        local id, num = makeApartmentId(def.type)
        if not id then return false end
        local label = ('%s %s'):format(def.label or 'Apartment', num)

        MySQL.insert.await('INSERT INTO apartments (name, type, label, citizenid) VALUES (?, ?, ?, ?)',
            { id, def.type, label, cid })
        TriggerClientEvent('qb-apartments:client:LastLocationHouse', src, def.type, id)
        TriggerClientEvent('apartments:client:SetHomeBlip', src, def.type)
        return { id = id, label = label }
    end,

    SpawnInside = function(src, id)
        if not id then return false end
        local cid = getCitizenId(src)
        if not cid then return false end

        if aptStarted() then
            local apt = MySQL.single.await('SELECT type, citizenid FROM apartments WHERE name = ?', { id })
            if apt then
                if apt.citizenid ~= cid then return false end
                -- LastLocationHouse (new=false): enter without re-opening the editor.
                TriggerClientEvent('qb-apartments:client:LastLocationHouse', src, apt.type, id)
                return true
            end
        end
        if housesStarted() then
            if MySQL.scalar.await('SELECT 1 FROM player_houses WHERE house = ? AND citizenid = ?', { id, cid }) then
                TriggerClientEvent('qb-houses:client:SpawnInApartment', src, id)
                return true
            end
        end
        return false
    end,
})
