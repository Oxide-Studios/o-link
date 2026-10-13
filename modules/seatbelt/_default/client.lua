-- Default seatbelt fallback (client): no seatbelt system is running, so the belt is never on.

if not olink._guardImpl('Seatbelt', '_default', false) then return end

olink._registerDefault('seatbelt', {
    GetResourceName = function() return '_default' end,
    IsOn = function() return false end,
}, '_default')
