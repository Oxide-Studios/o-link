-- Default needs fallback (client): no needs system is running, so every need is unknown.

if not olink._guardImpl('Needs', '_default', false) then return end
if not olink._hasOverride('Needs') and GetResourceState('es_extended') == 'started' then return end
if not olink._hasOverride('Needs') and GetResourceState('qb-core') == 'started' then return end
if not olink._hasOverride('Needs') and GetResourceState('qbx_core') == 'started' then return end
if not olink._hasOverride('Needs') and GetResourceState('oxide-needs') == 'started' then return end

olink._registerDefault('needs', {
    GetResourceName = function() return '_default' end,
    Get = function() return nil end,
    GetAll = function() return {} end,
}, '_default')
