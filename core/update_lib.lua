-- Shared pieces of the two update checks: o-link's own updater
-- (core/version_check.lua) and the catalogue notice (core/catalogue_check.lua).
-- Server-only, because PerformHttpRequest is.

local HEADERS = { ['User-Agent'] = 'o-link-update-check' }

olink._update = {}

---"X.Y.Z" -> { X, Y, Z }; missing parts default to 0. Returns nil when unusable.
---@param version string
---@return table?
function olink._update.parse(version)
    if type(version) ~= 'string' then return nil end
    local parts = {}
    for n in version:gmatch('%d+') do
        parts[#parts + 1] = tonumber(n)
    end
    if #parts == 0 then return nil end
    return parts
end

---Returns 1 if a > b, -1 if a < b, 0 if equal.
---@param a table
---@param b table
---@return number
function olink._update.compare(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

---Blocking GET. Returns code, body.
---@param url string
---@return number, string?
function olink._update.httpGet(url)
    local p = promise.new()
    PerformHttpRequest(url, function(code, body)
        p:resolve({ code = code, body = body })
    end, 'GET', '', HEADERS)
    local res = Citizen.Await(p)
    return res.code, res.body
end
