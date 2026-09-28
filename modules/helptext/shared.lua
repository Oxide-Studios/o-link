-- Shared helptext helpers. A structured prompt ({ title, text, keys, position }) only renders
-- as-is in oxide-helptext; every other provider receives it flattened to one string.

---@param message string|table|nil
---@return string
function olink._helptextText(message)
    if type(message) ~= 'table' then return tostring(message or '') end

    local parts = {}
    local text = message.text or message.message
    if text ~= nil then parts[#parts + 1] = tostring(text) end
    for _, key in ipairs(type(message.keys) == 'table' and message.keys or {}) do
        parts[#parts + 1] = ('[%s] %s'):format(key.key or '?', key.label or '')
    end

    local body = table.concat(parts, '  |  ')
    if message.title == nil then return body end
    if body == '' then return tostring(message.title) end
    return ('%s: %s'):format(message.title, body)
end

---@param message string|table|nil
---@param position string|nil
---@return string|nil
function olink._helptextPosition(message, position)
    return type(message) == 'table' and message.position or position
end
