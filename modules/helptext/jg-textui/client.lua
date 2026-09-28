if not olink._guardImpl('HelpText', 'jg-textui', 'jg-textui') then return end

olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    Show = function(message, position)
        exports['jg-textui']:DrawText(olink._helptextText(message))
    end,

    Hide = function()
        exports['jg-textui']:HideText()
    end,
})

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    olink.helptext.Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    olink.helptext.Hide()
end)
