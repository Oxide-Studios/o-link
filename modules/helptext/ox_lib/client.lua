if not olink._guardImpl('HelpText', 'ox_lib', 'ox_lib') then return end
if not olink._hasOverride('HelpText') and GetResourceState('cd_drawtextui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('jg-textui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('lab-HintUI') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('lation_ui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('okokTextUI') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('oxide-helptext') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('ZSX_UIV2') == 'started' then return end

olink._register('helptext', {
    ---@param message string|table
    ---@param position string|nil
    Show = function(message, position)
        lib.showTextUI(olink._helptextText(message), { position = olink._helptextPosition(message, position) })
    end,

    Hide = function()
        lib.hideTextUI()
    end,
})

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    olink.helptext.Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    olink.helptext.Hide()
end)
