if not olink._guardImpl('HelpText', 'okokTextUI', 'okokTextUI') then return end

olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    Show = function(message, position)
        exports['okokTextUI']:Open(olink._helptextText(message), 'darkblue', olink._helptextPosition(message, position), false)
    end,

    Hide = function()
        exports['okokTextUI']:Close()
    end,
})

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    olink.helptext.Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    olink.helptext.Hide()
end)
