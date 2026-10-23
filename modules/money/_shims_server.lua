-- Underscore prefix keeps this out of the `**/server.lua` adapter glob so it
-- loads once via its explicit fxmanifest entry, after the money and inventory adapters.

---Report money taken from a player that could not be given back: an error log, and an alert
---to every admin online so it can be paid back by hand.
---@param src number
---@param charId string|nil
---@param account string
---@param amount number
---@param reason string
function olink._flagRefundOwed(src, charId, account, amount, reason)
    olink.logger.Error('o-link', 'money', 'refund failed, the player is owed this amount', {
        src = src, charId = charId, account = account, amount = amount, reason = reason,
    })
    local message = ('[o-link] Refund failed: %s is owed $%s %s (%s).'):format(tostring(charId or src), amount, account, reason)
    for _, playerId in ipairs(olink.framework.GetPlayers() or {}) do
        if olink.framework.IsAdmin(playerId) then
            olink.notify.Send(playerId, message, 'error')
        end
    end
end
