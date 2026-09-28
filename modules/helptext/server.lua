-- Server-side helptext relay.
-- Triggers client events so server code can show/hide helptext on a player. The calling
-- resource travels with the event so providers that track ownership (oxide-helptext) can use it.

olink._register('helptext', {
    ---@param src number
    ---@param message string|table
    ---@param position string|nil
    Show = function(src, message, position)
        TriggerClientEvent('o-link:client:helptextShow', src, message, position, GetInvokingResource())
    end,

    ---@param src number
    ---@param id any
    Hide = function(src, id)
        TriggerClientEvent('o-link:client:helptextHide', src, id, GetInvokingResource())
    end,
})
