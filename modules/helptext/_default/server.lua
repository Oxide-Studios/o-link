-- Default helptext fallback (server). Relays show/hide events to client.

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

olink._registerDefault('helptext', {
    GetResourceName = function() return '_default' end,

    Show = function(src, message, position)
        TriggerClientEvent('o-link:client:helptextShow', src, message, position, GetInvokingResource())
    end,

    Hide = function(src, id)
        TriggerClientEvent('o-link:client:helptextHide', src, id, GetInvokingResource())
    end,
})
