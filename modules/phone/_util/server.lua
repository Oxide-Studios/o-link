-- Helpers shared by the phone adapters. Loaded guard-free before the adapter
-- folders (the phone glob is sorted and `_` sorts first).

olink._phone = olink._phone or {}
local P = olink._phone

local MAIL_DOMAIN = 'service.com'
local MAX_LOCAL_PART = 48
local ADDRESS_PATTERN = '^[%w%._%+%-]+@[%w%-]+%.[%w%.%-]+$'

---Consumers pass a display name ("Pizza This - Vespucci") as the mail sender.
---Vendors whose sender field is an address get a slug instead
---(`pizza-this-vespucci@service.com`); a real address passes through lowercased.
---@param sender any
---@return string
function P.SenderAddress(sender)
    local text = type(sender) == 'string' and sender or ''
    local lowered = text:lower()
    if lowered:match(ADDRESS_PATTERN) then return lowered end

    local slug = lowered:gsub('[^a-z0-9]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
    if #slug > MAX_LOCAL_PART then
        slug = slug:sub(1, MAX_LOCAL_PART):gsub('%-+$', '')
    end
    if slug == '' then slug = 'noreply' end
    return slug .. '@' .. MAIL_DOMAIN
end

local RELAY_LIMITS = { email = 100, title = 100, message = 2000 }
local RELAY_COOLDOWN_MS = 5000
local lastRelay = {}

---Register the net event a provider's client `SendEmail` relays through. The
---payload is untrusted: types, lengths and a per-source cooldown are enforced
---before it reaches the server `SendEmail`.
---@param provider string adapter folder name, e.g. 'lb-phone'
function P.RegisterEmailRelay(provider)
    RegisterNetEvent(('o-link:phone:%s:sendEmail'):format(provider), function(data)
        local src = source
        if not src or src == 0 or type(data) ~= 'table' then return end
        if type(data.email) ~= 'string' or type(data.title) ~= 'string' or type(data.message) ~= 'string' then return end

        local now = GetGameTimer()
        if lastRelay[src] and (now - lastRelay[src]) < RELAY_COOLDOWN_MS then return end
        lastRelay[src] = now

        olink.phone.SendEmail(src,
            data.email:sub(1, RELAY_LIMITS.email),
            data.title:sub(1, RELAY_LIMITS.title),
            data.message:sub(1, RELAY_LIMITS.message))
    end)
end

AddEventHandler('playerDropped', function()
    lastRelay[source] = nil
end)
