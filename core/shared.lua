olink = {}

local capabilities = {}
local moduleKinds = {}
local moduleOwners = {}
local warnedCalls = {}

local side = IsDuplicityVersion() and 'server' or 'client'

---Print a one-time warning when a stub function is called because no real implementation is loaded.
---@param namespace string
---@param fn string
function olink._warnMissing(namespace, fn)
    local key = namespace .. '.' .. fn
    if warnedCalls[key] then return end
    warnedCalls[key] = true
    local kind = moduleKinds[namespace]
    if kind == 'fallback' then
        print(('^3[o-link] %s: olink.%s() was called with only fallback defaults loaded for "%s". Returning fallback values. Use olink.supports(%q) to guard optional features.^0')
            :format(side, key, namespace, key))
        return
    end

    print(('^3[o-link] %s: olink.%s() was called but no "%s" module is loaded. Returning defaults. Use olink.supports(%q) to guard optional features.^0')
        :format(side, key, namespace, key))
end

local overrideKeyMap = {
    framework = 'Framework',
    character = 'Character',
    multichar = 'Multichar',
    job = 'Job',
    money = 'Money',
    inventory = 'Inventory',
    vehicles = 'Vehicles',
    vehicleproperties = 'VehicleProperties',
    vehicleownership = 'VehicleOwnership',
    notify = 'Notify',
    banking = 'Banking',
    helptext = 'HelpText',
    target = 'Target',
    progressbar = 'ProgressBar',
    vehiclekey = 'VehicleKey',
    fuel = 'Fuel',
    weather = 'Weather',
    input = 'Input',
    menu = 'Menu',
    radial = 'Radial',
    zones = 'Zones',
    placement = 'Placement',
    phone = 'Phone',
    clothing = 'Clothing',
    dispatch = 'Dispatch',
    doorlock = 'Doorlock',
    housing = 'Housing',
    bossmenu = 'BossMenu',
    skills = 'Skills',
    death = 'Death',
    needs = 'Needs',
    gang = 'Gang',
    logger = 'Logger',
    tablet = 'Tablet',
    hud = 'Hud',
}

local function normalizeName(value)
    return type(value) == 'string' and value:lower() or nil
end

---@param namespace string
---@param impl table
---@param implName string|nil
local function applyCompat(namespace, impl, implName)
    local ns = normalizeName(namespace)

    if ns == 'notify' then
        if implName and type(impl.GetResourceName) ~= 'function' then
            impl.GetResourceName = function()
                return implName
            end
        end

        if side == 'client' then
            if type(impl.Send) == 'function' and type(impl.SendNotify) ~= 'function' then
                impl.SendNotify = function(message, notifType, duration)
                    return impl.Send(message, notifType, duration, nil, nil)
                end
            end

            if type(impl.Send) == 'function' and type(impl.SendNotification) ~= 'function' then
                impl.SendNotification = function(title, message, notifType, duration, props)
                    return impl.Send(message, notifType, duration, title, props)
                end
            end

            if implName == '_default' and type(impl.ShowHelpText) ~= 'function' then
                impl.ShowHelpText = function(message, position)
                    return olink.helptext.Show(message, position)
                end
            end

            if implName == '_default' and type(impl.HideHelpText) ~= 'function' then
                impl.HideHelpText = function()
                    return olink.helptext.Hide()
                end
            end
        else
            if type(impl.SendNotify) ~= 'function' then
                if type(impl.SendNotification) == 'function' then
                    impl.SendNotify = function(src, message, notifType, duration)
                        return impl.SendNotification(src, nil, message, notifType, duration)
                    end
                elseif type(impl.Send) == 'function' then
                    impl.SendNotify = function(src, message, notifType, duration)
                        return impl.Send(src, message, notifType, duration)
                    end
                end
            end

            if type(impl.ShowHelpText) ~= 'function' then
                impl.ShowHelpText = function(src, message, position)
                    return olink.helptext.Show(src, message, position)
                end
            end

            if type(impl.HideHelpText) ~= 'function' then
                impl.HideHelpText = function(src)
                    return olink.helptext.Hide(src)
                end
            end
        end
    elseif ns == 'helptext' then
        if implName and type(impl.GetResourceName) ~= 'function' then
            impl.GetResourceName = function()
                return implName
            end
        end

        if type(impl.Show) == 'function' and type(impl.ShowHelpText) ~= 'function' then
            impl.ShowHelpText = impl.Show
        end

        if type(impl.Hide) == 'function' and type(impl.HideHelpText) ~= 'function' then
            impl.HideHelpText = impl.Hide
        end
    elseif ns == 'clothing' then
        if implName and type(impl.GetResourceName) ~= 'function' then
            impl.GetResourceName = function()
                return implName
            end
        end

        -- Server SetAppearance accepts two payload shapes. Bare clothing
        -- (`{components, props}` with positional updateBackup/save) runs the
        -- backend's own applier. A canonical payload carrying hair/overlays/etc.
        -- (with an opts table) is merged over the current look and persisted
        -- through the creator-appearance writer, then re-rendered live. Rich looks
        -- persist only when opts.save is set, and merge only when the backend can
        -- supply a rich base, so a partial edit leaves unedited fields intact.
        if side == 'server' and type(impl.SetAppearance) == 'function' then
            local rawSet = impl.SetAppearance
            impl.SetAppearance = function(src, data, a3, a4)
                local opts
                if type(a3) == 'table' then
                    opts = a3
                else
                    opts = { backup = a3, save = a4 }
                end

                local A = olink._appearance
                if not (A and A.isRich(data)) then
                    return rawSet(src, data, opts.backup, opts.save)
                end

                local payload = data
                if type(olink.clothing.GetCanonicalAppearance) == 'function' then
                    local base = olink.clothing.GetCanonicalAppearance(src)
                    if type(base) == 'table' then payload = A.merge(base, data) end
                end

                local persisted = false
                if opts.save == true and type(olink.clothing.SaveCreatorAppearance) == 'function' then
                    persisted = olink.clothing.SaveCreatorAppearance(src, payload, true) and true or false
                end
                if opts.save == true and not persisted then
                    -- Backend can't store rich appearance; persist clothing only.
                    local norm = A.normalize(payload)
                    rawSet(src, {
                        components = A.componentsToArray(norm.components),
                        props = A.propsToArray(norm.props),
                    }, opts.backup, true)
                    olink._warnMissing('clothing', 'SaveCreatorAppearance')
                end

                TriggerClientEvent('o-link:client:clothing:setAppearance', src, payload)
                return payload
            end
        end
    end
end

---Merge functions from `impl` into the namespace table. Existing entries are overwritten.
---@param namespace string
---@param impl table
---@param implName string|nil
local function mergeImpl(namespace, impl, implName)
    applyCompat(namespace, impl, implName)
    local existing = rawget(olink, namespace)
    if type(existing) ~= 'table' then
        existing = {}
        olink[namespace] = existing
    end
    for k, v in pairs(impl) do
        existing[k] = v
    end
end

---Register a real implementation for a namespace. Flips the capability flag so
---`olink.supports()` returns true for loaded functions.
---@param namespace string Module namespace (e.g. 'framework', 'character', 'job')
---@param impl table Table of functions returned by the module implementation
---@param implName string|nil
function olink._register(namespace, impl, implName)
    mergeImpl(namespace, impl, implName)
    capabilities[namespace] = true
    moduleKinds[namespace] = 'real'
    if implName then moduleOwners[namespace] = implName end
end

---Register a default/stub implementation for a namespace. Fallback namespaces
---are still considered loaded so `olink.supports()` , where defaults remain callable when no custom
---implementation is present. Real implementations loaded later overwrite these
---stubs.
---@param namespace string
---@param impl table
---@param implName string|nil
function olink._registerDefault(namespace, impl, implName)
    mergeImpl(namespace, impl, implName)
    capabilities[namespace] = true
    if moduleKinds[namespace] ~= 'real' then
        moduleKinds[namespace] = 'fallback'
        if implName then moduleOwners[namespace] = implName end
    end
end

---Build a stub table of warning-return functions for the given namespace.
---@param namespace string
---@param methods string[] List of method names to stub.
---@param defaults? table<string, any> Optional map of name -> default return value (or function returning defaults).
---@return table
function olink._buildStub(namespace, methods, defaults)
    defaults = defaults or {}
    local stub = {}
    for _, name in ipairs(methods) do
        local default = defaults[name]
        if type(default) == 'function' then
            stub[name] = function(...)
                olink._warnMissing(namespace, name)
                return default(...)
            end
        else
            local captured = default
            stub[name] = function()
                olink._warnMissing(namespace, name)
                return captured
            end
        end
    end
    return stub
end

---@param namespace string
---@return string
function olink._getOverrideKey(namespace)
    return overrideKeyMap[normalizeName(namespace)] or namespace
end

---@param namespace string
---@return string|nil
function olink._getOverride(namespace)
    local overrides = Config and Config.Overrides
    if type(overrides) ~= 'table' then return nil end

    local key = olink._getOverrideKey(namespace)
    local value = overrides[key]
    if type(value) ~= 'string' or value == '' then return nil end

    return value
end

---@param namespace string
---@param implName string
---@return boolean|nil
function olink._overrideMatches(namespace, implName)
    local override = olink._getOverride(namespace)
    if not override then return nil end

    return normalizeName(override) == normalizeName(implName)
end

---@param namespace string
---@return boolean
function olink._hasOverride(namespace)
    return olink._getOverride(namespace) ~= nil
end

---@param namespace string
---@param implName string
---@param resourceName string|false|nil
---@return boolean
function olink._guardImpl(namespace, implName, resourceName)
    local matches = olink._overrideMatches(namespace, implName)
    if matches == false then return false end

    if resourceName == false then return true end

    local state = GetResourceState(resourceName or implName)
    if state ~= 'started' and state ~= 'missing' and Config and Config.Debug then
        print(('[o-link] %s adapter "%s" skipped: resource "%s" is %s (not started)')
            :format(namespace, implName, resourceName or implName, state))
    end
    return state == 'started'
end

---Check whether a module or specific function is available.
---@param path string Dot-separated path (e.g. 'character', 'character.SetBoss')
---@return boolean
function olink.supports(path)
    local first = true
    local node = olink
    for part in path:gmatch('[^.]+') do
        if type(node) ~= 'table' then return false end
        if first then
            if not capabilities[part] then return false end
            node = rawget(olink, part)
            first = false
        else
            node = rawget(node, part)
        end
        if node == nil then return false end
    end
    return not first
end

---`provider` is the implementation name passed to `_register`. Adapters that omit
---it leave this nil, so callers fall back to the namespace's own optional
---`GetResourceName()`.
---@return table<string, { loaded: boolean, kind: string|nil, provider: string|nil }>
function olink._getCapabilities()
    local out = {}
    for namespace, loaded in pairs(capabilities) do
        out[namespace] = {
            loaded = loaded,
            kind = moduleKinds[namespace],
            provider = moduleOwners[namespace],
        }
    end
    return out
end

---Strip .png / .webp extension from an item name for image path resolution.
---@param item string
---@return string
function olink._stripExt(item)
    return item:gsub('%.png$', ''):gsub('%.webp$', '')
end

exports('olink', function()
    return olink
end)
