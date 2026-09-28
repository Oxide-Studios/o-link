if not olink._guardImpl('HelpText', 'zsxui', 'ZSX_UIV2') then return end

olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    Show = function(message, position)
        exports['ZSX_UIV2']:TextUI_Persistent(nil, olink._helptextText(message), nil, nil, nil)
    end,

    Hide = function()
        exports['ZSX_UIV2']:TextUI_RemovePersistent(false)
    end,
})

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    olink.helptext.Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    olink.helptext.Hide()
end)
