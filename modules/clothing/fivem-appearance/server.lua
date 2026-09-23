if not olink._guardImpl('Clothing', 'fivem-appearance', 'fivem-appearance') then return end
if not olink._hasOverride('Clothing') and GetResourceState('rcore_clothing') == 'started' then return end
if not olink._hasOverride('Clothing') and GetResourceState('17mov_CharacterSystem') == 'started' then return end

local Players = {}

local function getFullAppearanceData(src)
    src = tonumber(src)
    if not src then return end
    local charId = olink.character.GetIdentifier(src)
    if not charId then return end
    if Players[charId] then return Players[charId] end

    local model, skinData
    if olink.framework.GetName() == 'es_extended' then
        local result = MySQL.query.await('SELECT skin FROM users WHERE identifier = ?', { charId })
        if not result or not result[1] then return end
        model = GetEntityModel(GetPlayerPed(src))
        skinData = json.decode(result[1].skin)
    else
        local result = MySQL.query.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = ?', { charId, 1 })
        if not result or not result[1] then return end
        model = result[1].model
        skinData = json.decode(result[1].skin)
    end

    Players[charId] = { model = model, skin = skinData, converted = skinData }
    return Players[charId]
end

-- Must write to the same store getFullAppearanceData reads from.
local function saveSkin(charId, encoded)
    if olink.framework.GetName() == 'es_extended' then
        MySQL.update.await('UPDATE users SET skin = ? WHERE identifier = ?', { encoded, charId })
    else
        MySQL.update.await('UPDATE playerskins SET skin = ? WHERE citizenid = ? AND active = ?', { encoded, charId, 1 })
    end
end

olink._register('clothing', {
    ---@return string
    GetResourceName = function()
        return 'fivem-appearance'
    end,

    ---@param src number
    ---@param fullData boolean|nil
    ---@return table|nil
    GetAppearance = function(src, fullData)
        local data = getFullAppearanceData(src)
        if not data then return nil end
        return fullData and data or data.converted
    end,

    ---Rich canonical snapshot (merge base for partial appearance edits).
    ---fivem-appearance stores the illenium-shape skin, so invert it into canonical.
    ---@param src number
    ---@return table|nil
    GetCanonicalAppearance = function(src)
        local data = getFullAppearanceData(src)
        if not data or type(data.skin) ~= 'table' then return nil end
        return OlinkIlleniumToCanonical(data.skin)
    end,

    ---@param src number
    ---@param data table
    ---@param updateBackup boolean|nil
    ---@param save boolean|nil
    ---@return table|nil
    SetAppearance = function(src, data, updateBackup, save)
        src = tonumber(src)
        if not src then return end
        local charId = olink.character.GetIdentifier(src)
        if not charId then return end
        -- Re-read DB before a fresh backup; cache isn't invalidated on external writes.
        if not Players[charId] or not Players[charId].backup then
            Players[charId] = nil
        end
        local current = getFullAppearanceData(src)
        if not current then return end

        -- Merge slot-wise onto the stored look. A top-level assign would replace
        -- the whole components array, dropping every slot this patch never
        -- mentioned — buying one t-shirt would strip the rest of the outfit.
        local merged = OlinkIlleniumApplyPatch(current.skin, data)

        if not Players[charId].backup or updateBackup then
            Players[charId].backup = current.converted
        end
        Players[charId].skin = merged
        Players[charId].model = GetEntityModel(GetPlayerPed(src))
        -- The merged look, never the incoming patch: GetAppearance feeds outfit
        -- saves and consumers' own change diffing, both of which need the whole
        -- outfit rather than whichever slots the last edit happened to touch.
        Players[charId].converted = merged

        if save then
            saveSkin(charId, json.encode(merged))
        end
        -- Send the caller's payload, not the merged look: a partial edit is already
        -- rendered on the ped, and re-applying every stored slot would strip anything
        -- another script put on unpersisted (a job uniform, say).
        TriggerClientEvent('o-link:client:clothing:setAppearance', src, data)
        return Players[charId]
    end,

    ---@param src number
    ---@param data table
    SetAppearanceExt = function(src, data)
        local isMale = olink.clothing.IsMale(src)
        local tbl = isMale and data.male or data.female
        olink.clothing.SetAppearance(src, tbl)
    end,

    ---@param src number
    ---@return table|nil
    Revert = function(src)
        src = tonumber(src)
        if not src then return end
        local current = getFullAppearanceData(src)
        if not current or not current.backup then return end
        return olink.clothing.SetAppearance(src, current.backup)
    end,

    ---@param src number
    OpenMenu = function(src)
        src = tonumber(src)
        if not src then return end
        TriggerClientEvent('qb-clothing:client:openMenu', src)
    end,

    ---@param src number
    ---@return boolean
    IsMale = function(src)
        src = tonumber(src)
        if not src then return false end
        local data = getFullAppearanceData(src)
        if data and data.model then
            return data.model == GetHashKey('mp_m_freemode_01')
        end
        local ped = GetPlayerPed(src)
        if not ped or not DoesEntityExist(ped) then return false end
        return GetEntityModel(ped) == GetHashKey('mp_m_freemode_01')
    end,

    ---Persist a full look produced by oxide-multichar's built-in creator.
    ---fivem-appearance stores the rich appearance object directly, so the
    ---translated illenium-shape skin is written to the framework's backing store
    ---(ESX `users.skin`, otherwise `playerskins`).
    ---@param src number
    ---@param data table canonical creator appearance
    ---@param save boolean|nil unused (always persists)
    ---@return boolean
    SaveCreatorAppearance = function(src, data, save)
        src = tonumber(src)
        if not src or type(data) ~= 'table' then return false end
        local charId = olink.character.GetIdentifier(src)
        if not charId then return false end

        local skin = OlinkCreatorToIllenium(data)
        local encoded = json.encode(skin)

        if olink.framework.GetName() == 'es_extended' then
            MySQL.update.await('UPDATE users SET skin = ? WHERE identifier = ?', { encoded, charId })
        else
            local affected = MySQL.update.await(
                'UPDATE playerskins SET skin = ?, model = ? WHERE citizenid = ? AND active = ?',
                { encoded, skin.model, charId, 1 }
            )
            if not affected or affected == 0 then
                MySQL.insert.await(
                    'INSERT INTO playerskins (citizenid, model, skin, active) VALUES (?, ?, ?, ?)',
                    { charId, skin.model, encoded, 1 }
                )
            end
        end

        Players[charId] = nil
        return true
    end,

})

-- Native tattoo store (tattoos live in the fivem-appearance skin blob). The bridge
-- router (_tattoos/server.lua) dispatches here when this backend is active.
olink._nativeTattoos = olink._nativeTattoos or {}
olink._nativeTattoos['fivem-appearance'] = {
    Get = function(src)
        local data = getFullAppearanceData(src)
        return (data and type(data.skin) == 'table' and data.skin.tattoos) or {}
    end,
    Save = function(src, tattoos)
        local charId = olink.character.GetIdentifier(tonumber(src))
        if not charId then return false end
        Players[charId] = nil
        local current = getFullAppearanceData(src)
        if not current or type(current.skin) ~= 'table' then return false end

        current.skin.tattoos = tattoos
        saveSkin(charId, json.encode(current.skin))
        Players[charId] = nil
        return true
    end,
}

AddEventHandler('olink:server:playerReady', function(src)
    src = tonumber(src)
    if not src then return end
    getFullAppearanceData(src)
end)

AddEventHandler('olink:server:playerUnload', function(src)
    src = tonumber(src)
    if not src then return end
    local charId = olink.character.GetIdentifier(src)
    if charId then Players[charId] = nil end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src then getFullAppearanceData(src) end
    end
end)
