-- Default money fallback (client): no framework keeps balances, so every account reads 0.

if not olink._guardImpl('Money', '_default', false) then return end
if not olink._hasOverride('Money') and GetResourceState('es_extended') == 'started' then return end
if not olink._hasOverride('Money') and GetResourceState('qb-core') == 'started' then return end
if not olink._hasOverride('Money') and GetResourceState('qbx_core') == 'started' then return end
if not olink._hasOverride('Money') and GetResourceState('oxide-core') == 'started' then return end

olink._registerDefault('money', {
    GetResourceName = function() return '_default' end,
    GetBalance = function() return 0 end,
}, '_default')
