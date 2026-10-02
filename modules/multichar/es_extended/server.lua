local RESOURCE = 'es_extended'

if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Multichar', RESOURCE, RESOURCE) then return end

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

local ESX
CreateThread(function()
    while GetResourceState(RESOURCE) ~= 'started' do Wait(100) end
    local ok, framework = pcall(function() return exports[RESOURCE]:getSharedObject() end)
    if ok then ESX = framework end
end)

-- Sub-identifier prefix esx_multicharacter would use. ESX servers can change
-- this in esx_multicharacter's config, but the default has been 'char' for
-- years. Override here only if you actually changed Server.prefix.
local PREFIX = 'char'

---Mirrors ESX.GetIdentifier without depending on the async cross-VM snapshot
---of the ESX object (which may be nil at the moment List runs and was the root
---cause of "no characters showing up" on freshly-booted ESX servers). Reads
---the player's license identifier and strips the literal "license:" prefix so
---the result matches what esx_multicharacter wrote into users.identifier
---(format: "char<slot>:<stripped_license>").
---@param src number
---@return string|nil
local function baseIdentifier(src)
    local raw = GetPlayerIdentifierByType(src, 'license')
    if not raw then return nil end
    return (raw:gsub('^license:', ''))
end

local function charIdentifier(slot, base)
    return ('%s%s:%s'):format(PREFIX, slot, base)
end

-- `users.ssn` only exists on ESX Legacy 1.13.3+ and is added by a KVP-gated
-- migration, so even newer servers can lack it. Every query touching ssn must
-- gate on this; when absent, toSlot falls back to the full identifier.
local ssnColumnExists
local function hasSsnColumn()
    if ssnColumnExists == nil then
        local count = MySQL.scalar.await([[
            SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'users'
              AND COLUMN_NAME = 'ssn'
        ]])
        ssnColumnExists = (count or 0) > 0
    end
    return ssnColumnExists
end

---Mirrors `Core.generateSSN()` from es_extended/server/functions.lua. ESX uses
---US Social Security Number format (XXX-XX-XXXX) with the historically
---blocked combinations excluded (area 666, the 987-65-432X range, the three
---well-known reserved SSNs). Core is es_extended-private and not exposed via
---getSharedObject, so we duplicate the logic here to keep the adapter
---self-contained.
---@return string
local function generateSSN()
    local reserved = {
        ['078-05-1120'] = true,
        ['219-09-9999'] = true,
        ['123-45-6789'] = true,
    }
    while true do
        local area = math.random(1, 899)
        if area ~= 666 then
            local group = math.random(1, 99)
            local serial = math.random(1, 9999)
            local skipReservedRange = area == 987 and group == 65 and serial >= 4320 and serial <= 4329
            if not skipReservedRange then
                local candidate = ('%03d-%02d-%04d'):format(area, group, serial)
                if not reserved[candidate] then
                    local exists = MySQL.scalar.await('SELECT 1 FROM `users` WHERE `ssn` = ? LIMIT 1', { candidate })
                    if not exists then return candidate end
                end
            end
        end
    end
end

local function parseSlotFromIdentifier(identifier)
    local s = identifier:sub(#PREFIX + 1, identifier:find(':') - 1)
    return tonumber(s)
end

local function normalizeGender(sex)
    if type(sex) == 'number' then return sex end
    sex = tostring(sex or ''):lower()
    if sex == 'f' or sex == 'female' then return 1 end
    return 0
end

local function toSlot(row)
    local first = row.firstname or ''
    local last = row.lastname or ''
    return {
        charId     = row.identifier,
        -- ESX Legacy 1.13.3+ adds `ssn` as a short public-facing ID. On older
        -- ESX (or before the migration runs) fall back to the full identifier
        -- so the field is never blank.
        stateId    = row.ssn or row.identifier,
        firstName  = row.firstname,
        lastName   = row.lastname,
        fullName   = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', ''),
        dob        = row.dateofbirth,
        gender     = normalizeGender(row.sex),
        -- Position is stored in `users.position` as a JSON blob, not as
        -- separate x/y/z/heading columns. esx_multicharacter doesn't load it
        -- in its list query either; we resolve it inside Select instead.
        position   = nil,
        lastPlayed = nil,
        _slot      = parseSlotFromIdentifier(row.identifier) or 1,
    }
end

---ESX's Database:DeleteCharacter cascades a transaction across every table
---with a varchar(60) identifier/owner column. We discover those columns the
---same way esx_multicharacter does on boot (INFORMATION_SCHEMA scan) so the
---cascade stays accurate even when servers add custom tables.
---@return table[] rows-of {tableName, columnName}
local function discoverCascadeTables()
    local length = 42 + #PREFIX
    local rows = MySQL.query.await([[
        SELECT TABLE_NAME AS tableName, COLUMN_NAME AS columnName
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND DATA_TYPE = 'varchar'
          AND COLUMN_NAME IN ('identifier', 'owner')
          AND CHARACTER_MAXIMUM_LENGTH >= ?
    ]], { length })
    return rows or {}
end

---Last saved position for a character. es_extended keeps it as a JSON blob in
---users.position ({x, y, z, heading}); the table has no x/y/z/heading columns,
---so that blob is the only place to read it from. Falls back to the first
---configured default spawn when the row has none.
---@param identifier string
---@return table|nil { x, y, z, w }
local function savedPosition(identifier)
    local row = MySQL.single.await('SELECT position FROM users WHERE identifier = ?', { identifier })
    if row and row.position then
        local decoded = type(row.position) == 'string' and json.decode(row.position) or row.position
        if decoded and decoded.x then
            return { x = decoded.x, y = decoded.y, z = decoded.z, w = decoded.heading or decoded.w or 0.0 }
        end
    end
    if ESX and ESX.GetConfig then
        local spawn = ESX.GetConfig().DefaultSpawns and ESX.GetConfig().DefaultSpawns[1]
        if spawn then return { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.heading } end
    end
    return nil
end

olink._register('multichar', {
    GetResourceName = function() return RESOURCE end,

    List = function(src)
        if not isStarted() then return {} end
        local base = baseIdentifier(src)
        if not base then return {} end

        -- Mirrors esx_multicharacter's `Database:GetPlayerInfo` byte-for-byte:
        --   SELECT identifier, accounts, job, job_grade, firstname, lastname,
        --          dateofbirth, sex, skin, disabled FROM users
        --   WHERE identifier LIKE ? LIMIT ?
        -- plus `ssn` (when the schema has it) so we can surface a short
        -- public-facing State ID. Disabled chars are returned (matching
        -- native — the UI decides how to render them) rather than filtered
        -- out in the WHERE clause.
        local likeFilter = ('%s%%:%s'):format(PREFIX, base)
        local rows = MySQL.query.await(
            ('SELECT identifier, %saccounts, job, job_grade, firstname, lastname, dateofbirth, sex, skin, disabled FROM users WHERE identifier LIKE ? LIMIT ?')
                :format(hasSsnColumn() and 'ssn, ' or ''),
            { likeFilter, 50 }
        )
        if not rows then return {} end

        local result = {}
        for _, row in ipairs(rows) do
            result[#result + 1] = toSlot(row)
        end
        table.sort(result, function(a, b) return (a._slot or 0) < (b._slot or 0) end)
        for _, slot in ipairs(result) do slot._slot = nil end
        return result
    end,

    Create = function(src, data)
        if not isStarted() then return { ok = false, error = 'es_extended not started' } end

        local base = baseIdentifier(src)
        if not base then return { ok = false, error = 'No identifier' } end

        local likeFilter = ('%s%%:%s'):format(PREFIX, base)
        local existing = MySQL.query.await(
            'SELECT identifier FROM users WHERE identifier LIKE ?',
            { likeFilter }
        ) or {}

        local taken = {}
        for _, row in ipairs(existing) do
            local s = parseSlotFromIdentifier(row.identifier)
            if s then taken[s] = true end
        end

        -- First empty slot. oxide-multichar's Config.MaxCharacters caps how
        -- many tiles the UI shows, so by the time Create is called we know
        -- the player still has room — just find the lowest free slot.
        local slot
        for i = 1, 99 do
            if not taken[i] then slot = i break end
        end
        if not slot then return { ok = false, error = 'No free slot' } end

        local identifier = charIdentifier(slot, base)
        local sex = (tonumber(data.gender) == 1) and 'f' or 'm'

        -- ssn is generated here because we bypass es_extended's createESXPlayer
        -- (which would normally generate it). The 1.13.3+ schema declares ssn
        -- NOT NULL UNIQUE, so omitting it there leaves the column empty on lax
        -- MySQL configs and breaks every consumer that looks the player up by
        -- ssn.
        local columns = { 'identifier', 'accounts', 'firstname', 'lastname', 'dateofbirth', 'sex', 'height' }
        local values = {
            identifier,
            json.encode({ bank = 0, money = 0, black_money = 0 }),
            data.firstName,
            data.lastName,
            data.dob,
            sex,
            tonumber(data.height) or 180,
        }
        if hasSsnColumn() then
            table.insert(columns, 2, 'ssn')
            table.insert(values, 2, generateSSN())
        end

        local ok = pcall(function()
            MySQL.insert.await(
                ('INSERT INTO users (%s) VALUES (%s)'):format(
                    table.concat(columns, ', '),
                    ('?, '):rep(#columns - 1) .. '?'
                ),
                values
            )
        end)
        if not ok then return { ok = false, error = 'INSERT failed' } end

        TriggerEvent('esx_identity:completedRegistration', src, {
            firstname   = data.firstName,
            lastname    = data.lastName,
            dateofbirth = data.dob,
            sex         = sex,
            height      = tonumber(data.height) or 180,
        })

        return { ok = true, charId = identifier }
    end,

    Select = function(src, charId)
        if not isStarted() then return { ok = false, error = 'es_extended not started' } end

        local identifier = tostring(charId)
        local base = baseIdentifier(src)
        if not base or not identifier:find(base, 1, true) then
            return { ok = false, error = 'Character not owned' }
        end

        -- Short-circuit if the player is already loaded as this character.
        -- oxide-multichar's creator flow calls Create immediately before Select,
        -- and if esx_multicharacter is still installed its
        -- esx_identity:completedRegistration handler will have already fired
        -- esx:onPlayerJoined during Create. Re-triggering it would double-load.
        if ESX and ESX.GetPlayerFromId then
            local okPlayer, xPlayer = pcall(function() return ESX.GetPlayerFromId(src) end)
            if okPlayer and xPlayer and xPlayer.identifier == identifier then
                return { ok = true, position = savedPosition(identifier) }
            end
        end

        -- es_extended's onPlayerJoined handler builds the full identifier as
        -- `char .. ":" .. ESX.GetIdentifier(src)` itself, so we pass only the
        -- slot prefix ("char1") — matching what esx_multicharacter does in
        -- CharacterChosen. Passing the full identifier here would double-up
        -- and the subsequent loadESXPlayer query would return no rows.
        local slot = parseSlotFromIdentifier(identifier)
        local charPrefix = slot and (PREFIX .. slot) or identifier

        SetPlayerRoutingBucket(src, 0)
        TriggerEvent('esx:onPlayerJoined', src, charPrefix)

        return { ok = true, position = savedPosition(identifier) }
    end,

    Delete = function(src, charId)
        if not isStarted() then return false end
        local identifier = tostring(charId)
        local base = baseIdentifier(src)
        if not base or not identifier:find(base, 1, true) then return false end

        local cascade = discoverCascadeTables()
        if #cascade == 0 then
            local affected = MySQL.update.await('DELETE FROM users WHERE identifier = ?', { identifier })
            return (affected or 0) > 0
        end

        local queries = {}
        for _, t in ipairs(cascade) do
            queries[#queries + 1] = {
                query = ('DELETE FROM `%s` WHERE `%s` = ?'):format(t.tableName, t.columnName),
                values = { identifier },
            }
        end
        local ok = MySQL.transaction.await(queries)
        return ok and true or false
    end,

    ---Returns the number of existing characters. The maximum is configured in
    ---oxide-multichar's config.lua (Config.MaxCharacters); this adapter never
    ---touches slot-max policy.
    GetSlotInfo = function(src)
        if not isStarted() then return { used = 0 } end
        local base = baseIdentifier(src)
        if not base then return { used = 0 } end

        local likeFilter = ('%s%%:%s'):format(PREFIX, base)
        local row = MySQL.single.await(
            'SELECT COUNT(*) AS used FROM users WHERE identifier LIKE ? AND COALESCE(disabled, 0) = 0',
            { likeFilter }
        )
        return { used = (row and row.used) or 0 }
    end,

    Logout = function(src)
        if not isStarted() then return false end
        TriggerEvent('esx:playerLogout', src)
        TriggerClientEvent('o-link:multichar:startSelect', src)
        return true
    end,
})
