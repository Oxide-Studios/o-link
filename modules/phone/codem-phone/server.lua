if not olink._guardImpl('Phone', 'codem-phone', 'codem-phone') then return end

local function normalizeSenderName(email)
    if type(email) ~= 'string' then
        return 'System'
    end

    email = email:gsub('^%s+', ''):gsub('%s+$', '')
    if email == '' then
        return 'System'
    end

    return email
end

local function normalizeMailboxLocalPart(value)
    if type(value) ~= 'string' then
        return 'system'
    end

    local localPart = value:lower()
    localPart = localPart:gsub('@.*$', '')
    localPart = localPart:gsub('[^a-z0-9._-]', '.')
    localPart = localPart:gsub('%.+', '.')
    localPart = localPart:gsub('^%.+', '')
    localPart = localPart:gsub('%.+$', '')

    if localPart == '' then
        return 'system'
    end

    return localPart
end

local function buildMailData(email, title, message)
    local senderName = normalizeSenderName(email)
    local senderMailbox = normalizeMailboxLocalPart(email)

    return {
        sender_name = senderName,
        sender_email = ('%s@codem.com'):format(senderMailbox),
        sender_identifier = senderMailbox,
        title = tostring(title or ''),
        description = tostring(message or ''),
        can_reply = false,
    }
end

local function sendMailWithExport(exportName, ...)
    local args = { ... }
    return pcall(function()
        return exports['codem-phone'][exportName](exports['codem-phone'], table.unpack(args))
    end)
end

local function logBridgeResult(method, target, result)
    local status = result and result.success == true and 'success' or 'failed'
    local reason = result and result.message or 'no result'
    print(('[o-link][codem-phone] %s %s for %s (%s)'):format(method, status, tostring(target), tostring(reason)))
end

olink._register('phone', {
    ---@return string
    GetPhoneName = function()
        return 'codem-phone'
    end,

    ---@return string
    GetResourceName = function()
        return 'codem-phone'
    end,

    ---@param src number
    ---@return string|boolean
    GetPlayerPhone = function(src)
        local identifier = olink.character.GetIdentifier(src)
        if identifier then
            local okByIdentifier, phoneNumber = pcall(function()
                return exports['codem-phone']:GetPhoneNumberByIdentifier(identifier)
            end)
            if okByIdentifier and phoneNumber then
                return phoneNumber
            end
        end

        local playerKey = ('playerID%s'):format(src)
        if PlayerToPhone and PlayerToPhone[playerKey] then
            return PlayerToPhone[playerKey]
        end

        return false
    end,

    ---@param src number
    ---@param email string
    ---@param title string
    ---@param message string
    ---@return boolean
    SendEmail = function(src, email, title, message)
        local identifier = olink.character.GetIdentifier(src)
        local phoneNumber = olink.phone.GetPlayerPhone(src)
        local playerEmail = false

        if MySQL and identifier then
            local okMail, resultMail = pcall(function()
                local row = MySQL.single.await(
                    'SELECT email FROM codem_mphone_data WHERE owner = ?',
                    { identifier }
                )
                return row and row.email or false
            end)

            if okMail and resultMail then
                playerEmail = resultMail
            end
        end

        local mailData = buildMailData(email, title, message)

        local okPlayer, resultPlayer = sendMailWithExport('SendMailToPlayer', src, mailData)
        if okPlayer and resultPlayer and resultPlayer.success == true then
            logBridgeResult('SendMailToPlayer', src, resultPlayer)
            return true
        end
        logBridgeResult('SendMailToPlayer', src, resultPlayer)

        if identifier then
            local okIdentifier, resultIdentifier = sendMailWithExport('SendMailToIdentifier', identifier, mailData)
            if okIdentifier and resultIdentifier and resultIdentifier.success == true then
                logBridgeResult('SendMailToIdentifier', identifier, resultIdentifier)
                return true
            end
            logBridgeResult('SendMailToIdentifier', identifier, resultIdentifier)
        end

        if playerEmail then
            local okEmail, resultEmail = sendMailWithExport('SendMailToEmail', playerEmail, mailData)
            if okEmail and resultEmail and resultEmail.success == true then
                logBridgeResult('SendMailToEmail', playerEmail, resultEmail)
                return true
            end
            logBridgeResult('SendMailToEmail', playerEmail, resultEmail)
        end

        if phoneNumber then
            local okNumber, resultNumber = sendMailWithExport('SendMailToPhone', phoneNumber, mailData)
            if okNumber and resultNumber and resultNumber.success == true then
                logBridgeResult('SendMailToPhone', phoneNumber, resultNumber)
                return true
            end
            logBridgeResult('SendMailToPhone', phoneNumber, resultNumber)
        end

        return false
    end,
})

RegisterNetEvent('o-link:phone:codem-phone:sendEmail', function(data)
    local src = source
    olink.phone.SendEmail(src, data.email, data.title, data.message)
end)
