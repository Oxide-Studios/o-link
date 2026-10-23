if not olink._guardImpl('Vehicles', 'qb-garages', 'qb-core') then return end
if not olink._hasOverride('Vehicles') and GetResourceState('qbx_core') == 'started' then return end

local columnCache = {}

local function NormalizePlate(plate)
    return plate and tostring(plate):match('^%s*(.-)%s*$') or nil
end

local function ColumnExists(tableName, columnName)
    local key = tableName .. '.' .. columnName
    if columnCache[key] ~= nil then return columnCache[key] end
    local count = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    columnCache[key] = tonumber(count) ~= nil and tonumber(count) > 0
    return columnCache[key]
end

---qb-vehicleshop plate format: 1 digit, 2 letters, 3 digits, 2 letters.
local function RandomPlate()
    local function letters(n)
        local out = ''
        for _ = 1, n do out = out .. string.char(math.random(65, 90)) end
        return out
    end
    local function digits(n)
        local out = ''
        for _ = 1, n do out = out .. math.random(0, 9) end
        return out
    end
    return digits(1) .. letters(2) .. digits(3) .. letters(2)
end

olink._register('vehicles', {
    ---@param plate string
    ---@param limit number|nil
    ---@return table[]
    SearchByPlate = function(plate, limit)
        limit = limit or 20
        if not plate or #plate < 2 then return {} end

        local rows = MySQL.query.await([[
            SELECT pv.plate, pv.vehicle AS model, pv.state, pv.citizenid,
                   p.charinfo
            FROM player_vehicles pv
            LEFT JOIN players p ON pv.citizenid = p.citizenid
            WHERE pv.plate LIKE ?
            ORDER BY pv.plate ASC
            LIMIT ?
        ]], { '%' .. plate .. '%', limit })

        if not rows then return {} end

        local results = {}
        for _, row in ipairs(rows) do
            local charinfo = type(row.charinfo) == 'string' and json.decode(row.charinfo) or row.charinfo or {}
            results[#results + 1] = {
                plate      = row.plate,
                model      = row.model,
                type       = 'car',
                state      = row.state,
                charId     = row.citizenid,
                ownerFirst = charinfo.firstname,
                ownerLast  = charinfo.lastname,
                ownerStateId = row.citizenid,
            }
        end

        return results
    end,

    ---@param charId string citizenid
    ---@return table[]
    GetByOwner = function(charId)
        if not charId then return {} end
        local rows = MySQL.query.await('SELECT plate, vehicle AS model, state FROM player_vehicles WHERE citizenid = ? ORDER BY id DESC', { charId })
        if not rows then return {} end
        for i, row in ipairs(rows) do
            rows[i] = { plate = row.plate, model = row.model, type = 'car', state = row.state }
        end
        return rows
    end,

    ---@param plate string
    ---@return table|nil
    GetByPlate = function(plate)
        if not plate then return nil end

        local row = MySQL.single.await([[
            SELECT pv.*, p.charinfo
            FROM player_vehicles pv
            LEFT JOIN players p ON pv.citizenid = p.citizenid
            WHERE pv.plate = ?
        ]], { plate })

        if not row then return nil end

        local charinfo = type(row.charinfo) == 'string' and json.decode(row.charinfo) or row.charinfo or {}

        return {
            plate      = row.plate,
            model      = row.vehicle,
            type       = 'car',
            state      = row.state,
            charId     = row.citizenid,
            ownerFirst = charinfo.firstname,
            ownerLast  = charinfo.lastname,
            ownerStateId = row.citizenid,
            ownerDob   = charinfo.birthdate,
        }
    end,

    ---@return string unique plate, or '' when generation failed
    GeneratePlate = function()
        for _ = 1, 10 do
            local plate = RandomPlate()
            if not MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) then
                return plate
            end
        end
        return ''
    end,

    ---@param charId string citizenid
    ---@param model string
    ---@param plate string
    ---@param props table|nil
    ---@param vehicleType string|nil unused — stock player_vehicles has no type column
    ---@return boolean
    RegisterVehicle = function(charId, model, plate, props, vehicleType)
        plate = NormalizePlate(plate)
        if not charId or not model or not plate or plate == '' then return false end
        if MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) then return false end

        -- Mirrors qb-vehicleshop's insert; state 0 = out (caller spawns it),
        -- garage stays NULL until the player first stores the vehicle.
        local id = MySQL.insert.await([[
            INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state)
            VALUES ((SELECT license FROM players WHERE citizenid = @citizenid), @citizenid, @vehicle, @hash, @mods, @plate, 0)
        ]], {
            citizenid = charId,
            vehicle   = model,
            hash      = joaat(model),
            mods      = type(props) == 'table' and json.encode(props) or '{}',
            plate     = plate,
        })
        return (tonumber(id) or 0) > 0
    end,

    ---@param plate string
    ---@return boolean
    UnregisterVehicle = function(plate)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end
        local affected = MySQL.update.await('DELETE FROM player_vehicles WHERE plate = ?', { plate })
        return (affected or 0) > 0
    end,

    ---@param plate string
    ---@param fee number|nil
    ---@param lot string|nil
    ---@return boolean
    ImpoundVehicle = function(plate, fee, lot)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end
        if not MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) then return false end

        local sets = { 'state = ?' }
        local params = { 2 }
        if ColumnExists('player_vehicles', 'depotprice') then
            sets[#sets + 1] = 'depotprice = ?'
            params[#params + 1] = tonumber(fee) or 0
        end
        if lot and lot ~= '' and ColumnExists('player_vehicles', 'garage') then
            sets[#sets + 1] = 'garage = ?'
            params[#params + 1] = lot
        end
        params[#params + 1] = plate

        local affected = MySQL.update.await(('UPDATE player_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', ')), params)
        return (affected or 0) > 0
    end,

    ---@param plate string
    ---@return boolean
    ReleaseImpound = function(plate)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end
        local affected = MySQL.update.await('UPDATE player_vehicles SET state = ? WHERE plate = ?', { 1, plate })
        return (affected or 0) > 0
    end,

    ---@param plate string
    ---@return any
    GetVehicleState = function(plate)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return nil end
        return MySQL.scalar.await('SELECT state FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    end,

    ---@param plate string
    ---@param propsJson string
    ---@return boolean
    SaveVehicleProps = function(plate, propsJson)
        plate = NormalizePlate(plate)
        if not plate or plate == '' or not propsJson or not ColumnExists('player_vehicles', 'mods') then return false end
        local affected = MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { propsJson, plate })
        return (affected or 0) > 0
    end,

    ---@param charId string citizenid
    ---@param lot string|nil
    ---@return table[]
    GetImpoundedVehicles = function(charId, lot)
        if not charId then return {} end
        local query = 'SELECT id, plate, vehicle, hash, mods, garage, depotprice FROM player_vehicles WHERE citizenid = ? AND state = 2'
        local params = { charId }
        if lot and lot ~= '' then
            query = query .. ' AND garage = ?'
            params[#params + 1] = lot
        end
        local rows = MySQL.query.await(query, params) or {}
        local out = {}
        for i, row in ipairs(rows) do
            local props
            if row.mods and row.mods ~= '' then
                local okp, decoded = pcall(json.decode, row.mods)
                if okp then props = decoded end
            end
            out[i] = {
                id          = row.id,
                plate       = row.plate,
                model       = row.vehicle or row.hash,
                vehicleType = 'car',
                fee         = row.depotprice or 0,
                props       = props,
                lot         = row.garage,
            }
        end
        return out
    end,

    ---@param src number
    ---@param vehicleId number
    ---@param lot string|nil
    ---@return boolean, string|nil
    RetrieveImpounded = function(src, vehicleId, lot)
        if not src or not vehicleId then return false, 'bad_args' end
        local row = MySQL.single.await(
            'SELECT id, citizenid, depotprice FROM player_vehicles WHERE id = ? AND state = 2 LIMIT 1',
            { tonumber(vehicleId) })
        if not row then return false, 'not_found' end

        local QBCore
        local okCore = pcall(function() QBCore = exports['qb-core']:GetCoreObject() end)
        if not okCore or not QBCore then return false, 'no_core' end
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player or Player.PlayerData.citizenid ~= row.citizenid then return false, 'not_owner' end

        -- Cash goes through o-link so a cash item pays too; the bank stays the framework's own.
        local fee = tonumber(row.depotprice) or 0
        local paidFrom
        if fee > 0 then
            if (olink.money.GetBalance(src, 'cash') or 0) >= fee and olink.money.Remove(src, 'cash', fee, 'oxide-impound') then
                paidFrom = 'cash'
            elseif Player.Functions.RemoveMoney('bank', fee, 'oxide-impound') then
                paidFrom = 'bank'
            else
                return false, 'no_funds'
            end
        end

        local affected = MySQL.update.await(
            'UPDATE player_vehicles SET state = 0, depotprice = 0 WHERE id = ? AND state = 2',
            { tonumber(vehicleId) })
        if (affected or 0) <= 0 then
            -- Atomic guard tripped; refund to the account that paid
            if paidFrom then
                local refunded
                if paidFrom == 'cash' then
                    refunded = olink.money.Add(src, 'cash', fee, 'oxide-impound-refund')
                else
                    refunded = Player.Functions.AddMoney('bank', fee, 'oxide-impound-refund') ~= false
                end
                if not refunded then olink._flagRefundOwed(src, row.citizenid, paidFrom, fee, 'impound release failed') end
            end
            return false, 'race_lost'
        end
        return true, nil
    end,
})
