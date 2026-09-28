if not olink._guardImpl('HelpText', 'cd_drawtextui', 'cd_drawtextui') then return end

olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    Show = function(message, position)
        TriggerEvent('cd_drawtextui:ShowUI', 'show', olink._helptextText(message))
    end,

    Hide = function()
        TriggerEvent('cd_drawtextui:HideUI')
    end,
})

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    olink.helptext.Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    olink.helptext.Hide()
end)
