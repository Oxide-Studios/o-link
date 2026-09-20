local RESOURCE = 'oxide-tablet'

-- Pure adapter: bail if the tablet isn't installed so the defaults stub owns
-- the namespace and consumers fall back to their own UI.
if GetResourceState(RESOURCE) == 'missing' then return end
if not olink._guardImpl('Tablet', RESOURCE, false) then return end

local res = exports[RESOURCE]

local function isStarted()
    return GetResourceState(RESOURCE) == 'started'
end

olink._register('tablet', {
    ---@return string
    GetResourceName = function() return RESOURCE end,

    ---Register an app the tablet can host. `def.resource` is required: by the
    ---time the call reaches the tablet the invoking resource is o-link itself.
    ---@param def table { id, label, icon, resource, url?, query?, requires?, order?, color?, readyTimeoutMs?, description?, tagline?, category?, publisher?, version? }
    ---@return boolean
    RegisterApp = function(def)
        if type(def) ~= 'table' then return false end
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:RegisterApp(def) end)
        return ok and result == true
    end,

    ---@param id string
    ---@return boolean
    UnregisterApp = function(id)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:UnregisterApp(id) end)
        return ok and result == true
    end,

    ---Open the tablet, optionally straight into an app. Idempotent for the current app.
    ---@param appId? string
    ---@return boolean
    Open = function(appId)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:Open(appId) end)
        return ok and result == true
    end,

    ---@return boolean
    Close = function()
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:Close() end)
        return ok and result == true
    end,

    ---Return to the launcher if `appId` is the current app.
    ---@param appId string
    ---@return boolean
    CloseApp = function(appId)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:CloseApp(appId) end)
        return ok and result == true
    end,

    ---@return boolean
    IsOpen = function()
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:IsOpen() end)
        return ok and result == true
    end,

    ---@return string|nil
    GetCurrentApp = function()
        if not isStarted() then return nil end
        local ok, result = pcall(function() return res:GetCurrentApp() end)
        return ok and result or nil
    end,

    ---Relay a `{ action, data }` message into the current app's iframe.
    ---Queued by the tablet until the app reports ready.
    ---@param appId string
    ---@param message table
    ---@return boolean
    Send = function(appId, message)
        if type(message) ~= 'table' then return false end
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:Send(appId, message) end)
        return ok and result == true
    end,

    ---@param appId string
    ---@param count number
    ---@return boolean
    SetBadge = function(appId, count)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:SetBadge(appId, count) end)
        return ok and result == true
    end,

    ---The device (IMEI) the open tablet was started on; nil when closed, opened by a
    ---resource rather than an item, or the inventory cannot keep item metadata.
    ---@return table|nil { imei, name, battery }
    GetDevice = function()
        if not isStarted() then return nil end
        local ok, result = pcall(function() return res:GetDevice() end)
        return ok and type(result) == 'table' and result or nil
    end,

    ---Register a home-screen widget. `def.resource` is required, like RegisterApp.
    ---@param def table { id, label, resource, type = 'stat'|'list'|'progress'|'text'|'frame', sizes?, icon?, color?, app?, requires?, order?, data?, url?, query?, readyTimeoutMs? }
    ---@return boolean
    RegisterWidget = function(def)
        if type(def) ~= 'table' then return false end
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:RegisterWidget(def) end)
        return ok and result == true
    end,

    ---@param id string
    ---@return boolean
    UnregisterWidget = function(id)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:UnregisterWidget(id) end)
        return ok and result == true
    end,

    ---Push a widget's data. Cached by the tablet whether or not it is open; template
    ---widgets re-render, frame widgets receive { action = 'tablet:widgetData', data }.
    ---@param id string
    ---@param data table|nil
    ---@return boolean
    SetWidgetData = function(id, data)
        if data ~= nil and type(data) ~= 'table' then return false end
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:SetWidgetData(id, data) end)
        return ok and result == true
    end,

    ---Post a push notification for a registered app. Kept whether or not the tablet is
    ---open; while open it shows a banner and lands in the status-bar tray.
    ---@param def table { app, message, title?, icon?, id?, data?, sound?, toast? }
    ---@return string|false id in the form `app:id`
    Notify = function(def)
        if type(def) ~= 'table' then return false end
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:Notify(def) end)
        return ok and type(result) == 'string' and result or false
    end,

    ---@param id string the id Notify returned
    ---@return boolean
    DismissNotification = function(id)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:DismissNotification(id) end)
        return ok and result == true
    end,

    ---@param appId? string nil = every app
    ---@return boolean
    ClearNotifications = function(appId)
        if not isStarted() then return false end
        local ok, result = pcall(function() return res:ClearNotifications(appId) end)
        return ok and result == true
    end,
}, RESOURCE)
