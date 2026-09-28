-- Default helptext fallback (client). Delegates to the active framework's helptext methods.

if not olink._guardImpl('HelpText', '_default', false) then return end
if not olink._hasOverride('HelpText') and GetResourceState('cd_drawtextui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('jg-textui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('lab-HintUI') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('lation_ui') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('okokTextUI') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('ox_lib') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('oxide-helptext') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('ZSX_UIV2') == 'started' then return end
if not olink._hasOverride('HelpText') and GetResourceState('zsxui') == 'started' then return end

local function Show(message, position)
    if olink.framework and type(olink.framework.ShowHelpText) == 'function' then
        return olink.framework.ShowHelpText(olink._helptextText(message), olink._helptextPosition(message, position))
    end
end

local function Hide()
    if olink.framework and type(olink.framework.HideHelpText) == 'function' then
        return olink.framework.HideHelpText()
    end
end

olink._registerDefault('helptext', {
    Show = Show,
    Hide = Hide,
}, '_default')

RegisterNetEvent('o-link:client:helptextShow', function(message, position)
    Show(message, position)
end)

RegisterNetEvent('o-link:client:helptextHide', function()
    Hide()
end)
