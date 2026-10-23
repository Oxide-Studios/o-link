if not olink._guardImpl('Vehicles', 'qbx_vehicles', 'qbx_core') then return end

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

---Resolve a plate to a qbx_vehicles vehicleId using the canonical export when
---available, falling back to a scalar query for older qbx_vehicles versions.
---@param plate string
---@return integer|nil
local function ResolveVehicleIdByPlate(plate)
    local ok, id = pcall(function() return exports.qbx_vehicles:GetVehicleIdByPlate(plate) end)
    if ok and id then return tonumber(id) end
    return tonumber(MySQL.scalar.await('SELECT id FROM player_vehicles WHERE plate = ?', { plate }))
end

---Check if a plate exists in player_vehicles using the canonical export when
---available, falling back to a scalar query.
---@param plate string
---@return boolean
local function PlateExists(plate)
    local ok, exists = pcall(function() return exports.qbx_vehicles:DoesPlayerVehiclePlateExist(plate) end)
    if ok and exists ~= nil then return exists == true end
    return MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }) ~= nil
end

---QB-ecosystem plate format: 1 digit, 2 letters, 3 digits, 2 letters.
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
            if not PlateExists(plate) then return plate end
        end
        return ''
    end,

    ---@param charId string citizenid
    ---@param model string
    ---@param plate string
    ---@param props table|nil ox_lib vehicle properties
    ---@param vehicleType string|nil unused — qbx_vehicles derives type from the model
    ---@return boolean
    RegisterVehicle = function(charId, model, plate, props, vehicleType)
        plate = NormalizePlate(plate)
        if not charId or not model or not plate or plate == '' then return false end
        if PlateExists(plate) then return false end

        props = type(props) == 'table' and props or {}
        props.plate = plate
        -- No garage in the request → row is created with state OUT; the caller
        -- spawns the vehicle itself.
        local ok, vehicleId = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({
                model     = model,
                citizenid = charId,
                props     = props,
            })
        end)
        return ok and tonumber(vehicleId) ~= nil
    end,

    ---@param plate string
    ---@return boolean
    UnregisterVehicle = function(plate)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end
        local vehicleId = ResolveVehicleIdByPlate(plate)
        if not vehicleId then return false end
        local ok, success = pcall(function()
            return exports.qbx_vehicles:DeletePlayerVehicles('vehicleId', vehicleId)
        end)
        return ok and success == true
    end,

    ---@param plate string
    ---@param fee number|nil
    ---@param lot string|nil
    ---@return boolean
    ImpoundVehicle = function(plate, fee, lot)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end
        if not PlateExists(plate) then return false end

        local sets = { 'state = ?', 'depotprice = ?' }
        local params = { 2, tonumber(fee) or 0 }
        if lot and lot ~= '' then
            sets[#sets + 1] = 'garage = ?'
            params[#params + 1] = lot
        end

        -- Prefer keying on the primary id when we can resolve it (canonical,
        -- avoids any plate-trim mismatch); fall back to plate when not.
        local vehicleId = ResolveVehicleIdByPlate(plate)
        local query, whereValue
        if vehicleId then
            query = ('UPDATE player_vehicles SET %s WHERE id = ?'):format(table.concat(sets, ', '))
            whereValue = vehicleId
        else
            query = ('UPDATE player_vehicles SET %s WHERE plate = ?'):format(table.concat(sets, ', '))
            whereValue = plate
        end
        params[#params + 1] = whereValue

        local affected = MySQL.update.await(query, params)
        if (affected or 0) <= 0 then return false end

        if vehicleId then
            -- Mirror qbx_vehicles' SaveVehicle behavior so any cache listener
            -- (qbx_garages, etc.) invalidates against the new state.
            TriggerEvent('qbx_vehicles:server:vehicleSaved', vehicleId)
        end
        return true
    end,

    ---@param plate string
    ---@return boolean
    ReleaseImpound = function(plate)
        plate = NormalizePlate(plate)
        if not plate or plate == '' then return false end

        local vehicleId = ResolveVehicleIdByPlate(plate)
        local query, whereValue
        if vehicleId then
            query = 'UPDATE player_vehicles SET state = ? WHERE id = ?'
            whereValue = vehicleId
        else
            query = 'UPDATE player_vehicles SET state = ? WHERE plate = ?'
            whereValue = plate
        end

        local affected = MySQL.update.await(query, { 1, whereValue })
        if (affected or 0) <= 0 then return false end

        if vehicleId then
            TriggerEvent('qbx_vehicles:server:vehicleSaved', vehicleId)
        end
        return true
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
        local results
        local ok = pcall(function()
            results = exports.qbx_vehicles:GetPlayerVehicles({
                citizenid = charId,
                states    = { 2 },
                garage    = (lot and lot ~= '') and lot or nil,
            })
        end)
        if not ok or type(results) ~= 'table' then return {} end
        local out = {}
        for i, v in ipairs(results) do
            local props = v.props
            if not props and v.modelData then props = v.modelData end
            out[i] = {
                id          = v.id,
                plate       = (v.props and v.props.plate) or v.plate,
                model       = (v.props and v.props.model) or v.modelName,
                vehicleType = v.vehicleType or 'car',
                fee         = v.depotPrice or 0,
                props       = props,
                lot         = v.garage,
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
        local player
        local okGet = pcall(function() player = exports.qbx_core:GetPlayer(src) end)
        if not okGet or not player then return false, 'no_player' end

        local vehicle
        local okFind = pcall(function()
            vehicle = exports.qbx_vehicles:GetPlayerVehicle(tonumber(vehicleId), {
                citizenid = player.PlayerData.citizenid,
                states    = { 2 },
                garage    = (lot and lot ~= '') and lot or nil,
            })
        end)
        if not okFind or not vehicle then return false, 'not_found' end

        -- Cash goes through o-link so a cash item pays too; the bank stays the framework's own.
        local fee = tonumber(vehicle.depotPrice) or 0
        local paidFrom
        if fee > 0 then
            if (olink.money.GetBalance(src, 'cash') or 0) >= fee and olink.money.Remove(src, 'cash', fee, 'oxide-impound') then
                paidFrom = 'cash'
            elseif player.Functions.RemoveMoney('bank', fee, 'oxide-impound') then
                paidFrom = 'bank'
            else
                return false, 'no_funds'
            end
        end

        local saved
        local okSave = pcall(function()
            saved = exports.qbx_vehicles:SaveVehicle(vehicle, { state = 0 })
        end)
        if not okSave or not saved then
            if paidFrom then
                local refunded
                if paidFrom == 'cash' then
                    refunded = olink.money.Add(src, 'cash', fee, 'oxide-impound-refund')
                else
                    refunded = player.Functions.AddMoney('bank', fee, 'oxide-impound-refund') ~= false
                end
                if not refunded then olink._flagRefundOwed(src, player.PlayerData.citizenid, paidFrom, fee, 'impound release failed') end
            end
            return false, 'save_failed'
        end
        return true, nil
    end,
})
