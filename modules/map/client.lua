olink._register('map', {
    GetConfig = function(override, defaultMode)
        return OlinkMap.GetConfig(override, defaultMode or GlobalState['o-link:map:mode'])
    end,
    IsMode = OlinkMap.IsMode,
}, 'o-link')
