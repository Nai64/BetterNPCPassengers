
if SERVER then
    AddCSLuaFile()
end

NaiBase = NaiBase or {}
NaiBase.Version = "1.0.0"
NaiBase.Modules = NaiBase.Modules or {}
NaiBase.Hooks = NaiBase.Hooks or {}
NaiBase.Config = NaiBase.Config or {}

NaiBase.DiscoveredEvents = NaiBase.DiscoveredEvents or {}
NaiBase.DiscoveredConVars = NaiBase.DiscoveredConVars or {}
NaiBase.DiscoveredData = NaiBase.DiscoveredData or {}

CreateConVar("naibase_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable debug mode for Nai's Base")

NaiBase.Colors = {
    Primary = Color(100, 200, 255),
    Success = Color(100, 255, 100),
    Warning = Color(255, 200, 100),
    Error = Color(255, 100, 100),
    Info = Color(200, 200, 200)
}

-- Module Registration System
-- Allows addons to register themselves with the base system
function NaiBase.RegisterModule(moduleName, moduleData)
    if not moduleName or moduleName == "" then
        ErrorNoHalt("[Nai's Base] Cannot register module: Invalid name\n")
        return false
    end
    
    if NaiBase.Modules[moduleName] then
        MsgC(NaiBase.Colors.Warning, "[Nai's Base] Warning: Module '" .. moduleName .. "' is being re-registered\n")
    end
    
    NaiBase.Modules[moduleName] = {
        name = moduleName,
        version = moduleData.version or "1.0.0",
        author = moduleData.author or "Unknown",
        description = moduleData.description or "No description provided",
        icon = moduleData.icon or "icon16/package.png",
        loaded = true,
        loadTime = os.time(),
        init = moduleData.init,
        shutdown = moduleData.shutdown,
        data = moduleData.data or {}
    }
    
    MsgC(NaiBase.Colors.Success, "[Nai's Base] Module '" .. moduleName .. "' v" .. NaiBase.Modules[moduleName].version .. " registered successfully\n")
    
    if moduleData.init and isfunction(moduleData.init) then
        local success, err = pcall(moduleData.init)
        if not success then
            ErrorNoHalt("[Nai's Base] Module '" .. moduleName .. "' init failed: " .. tostring(err) .. "\n")
        end
    end
    
    return true
end

-- Get a registered module
function NaiBase.GetModule(moduleName)
    return NaiBase.Modules[moduleName]
end

-- Check if a module is loaded
function NaiBase.IsModuleLoaded(moduleName)
    return NaiBase.Modules[moduleName] ~= nil and NaiBase.Modules[moduleName].loaded == true
end

-- Get all registered modules
function NaiBase.GetAllModules()
    return NaiBase.Modules
end

-- Configuration System
-- Allows modules to store and retrieve configuration values with validation, categories, and more

NaiBase.ConfigMeta = NaiBase.ConfigMeta or {}
NaiBase.ConfigCallbacks = NaiBase.ConfigCallbacks or {}
NaiBase.ConfigDefaults = NaiBase.ConfigDefaults or {}
NaiBase.ConfigPresets = NaiBase.ConfigPresets or {}

function NaiBase.RegisterConfig(moduleName, key, data)
    moduleName = moduleName or "global"
    local configKey = moduleName .. "." .. key
    
    NaiBase.ConfigMeta[configKey] = {
        module = moduleName,
        key = key,
        displayName = data.displayName or key,
        description = data.description or "",
        category = data.category or "General",
        valueType = data.valueType or "any", -- string, number, boolean, any
        default = data.default,
        min = data.min,
        max = data.max,
        options = data.options, -- For dropdown/select
        readonly = data.readonly or false,
        hidden = data.hidden or false,
        advanced = data.advanced or false,
        requiresRestart = data.requiresRestart or false,
        validator = data.validator, -- Custom validation function
        onChange = data.onChange, -- Callback when value changes
    }
    
    if data.default ~= nil then
        if not NaiBase.ConfigDefaults[moduleName] then
            NaiBase.ConfigDefaults[moduleName] = {}
        end
        NaiBase.ConfigDefaults[moduleName][key] = data.default
        
        if NaiBase.GetConfig(key, nil, moduleName) == nil then
            NaiBase.SetConfig(key, data.default, moduleName)
        end
    end
    
    return true
end

function NaiBase.ValidateConfig(moduleName, key, value)
    local configKey = moduleName .. "." .. key
    local meta = NaiBase.ConfigMeta[configKey]
    
    if not meta then return true, value end -- No validation rules
    
    if meta.valueType ~= "any" and type(value) ~= meta.valueType then
        return false, "Invalid type (expected " .. meta.valueType .. ")"
    end
    
    if meta.valueType == "number" then
        if meta.min and value < meta.min then
            value = meta.min
        end
        if meta.max and value > meta.max then
            value = meta.max
        end
    end
    
    if meta.options then
        local valid = false
        for _, option in ipairs(meta.options) do
            if option.value == value or option == value then
                valid = true
                break
            end
        end
        if not valid then
            return false, "Value not in allowed options"
        end
    end
    
    if meta.validator then
        local success, result = pcall(meta.validator, value)
        if not success or result == false then
            return false, "Custom validation failed"
        end
    end
    
    return true, value
end

function NaiBase.SetConfig(key, value, moduleName)
    moduleName = moduleName or "global"
    
    local valid, validatedValue = NaiBase.ValidateConfig(moduleName, key, value)
    if not valid then
        NaiBase.LogWarning("Config validation failed for " .. moduleName .. "." .. key .. ": " .. validatedValue)
        return false
    end
    value = validatedValue
    
    local configKey = moduleName .. "." .. key
    local meta = NaiBase.ConfigMeta[configKey]
    if meta and meta.readonly then
        NaiBase.LogWarning("Cannot modify readonly config: " .. configKey)
        return false
    end
    
    local configKey = moduleName .. "." .. key
    local meta = NaiBase.ConfigMeta[configKey]
    if meta and meta.readonly then
        NaiBase.LogWarning("Cannot modify readonly config: " .. configKey)
        return false
    end
    
    if moduleName == "global" and key == "debug_mode" then
        local cv = GetConVar("naibase_debug")
        if cv then
            RunConsoleCommand("naibase_debug", value and "1" or "0")
            return true
        end
    end
    
    if not NaiBase.Config[moduleName] then
        NaiBase.Config[moduleName] = {}
    end
    
    local oldValue = NaiBase.Config[moduleName][key]
    
    if not NaiBase.DiscoveredData[configKey] then
        NaiBase.DiscoveredData[configKey] = {
            module = moduleName,
            key = key,
            type = type(value),
            category = "config",
            lastUpdated = os.time()
        }
    end
    NaiBase.DiscoveredData[configKey].type = type(value)
    NaiBase.DiscoveredData[configKey].lastUpdated = os.time()
    
    NaiBase.Config[moduleName][key] = value
    
    if meta and meta.onChange then
        pcall(meta.onChange, value, oldValue)
    end
    
    local callbackKey = moduleName .. "." .. key
    if NaiBase.ConfigCallbacks[callbackKey] then
        for _, callback in ipairs(NaiBase.ConfigCallbacks[callbackKey]) do
            pcall(callback, value, oldValue)
        end
    end
    
    return true
end

function NaiBase.OnConfigChange(moduleName, key, callback)
    local configKey = moduleName .. "." .. key
    if not NaiBase.ConfigCallbacks[configKey] then
        NaiBase.ConfigCallbacks[configKey] = {}
    end
    table.insert(NaiBase.ConfigCallbacks[configKey], callback)
end

function NaiBase.ResetConfig(key, moduleName)
    moduleName = moduleName or "global"
    if NaiBase.ConfigDefaults[moduleName] and NaiBase.ConfigDefaults[moduleName][key] ~= nil then
        return NaiBase.SetConfig(key, NaiBase.ConfigDefaults[moduleName][key], moduleName)
    end
    return false
end

function NaiBase.ResetModuleConfigs(moduleName)
    if not NaiBase.ConfigDefaults[moduleName] then return false end
    
    for key, default in pairs(NaiBase.ConfigDefaults[moduleName]) do
        NaiBase.SetConfig(key, default, moduleName)
    end
    return true
end

function NaiBase.SavePreset(moduleName, presetName)
    if not NaiBase.Config[moduleName] then return false end
    
    if not NaiBase.ConfigPresets[moduleName] then
        NaiBase.ConfigPresets[moduleName] = {}
    end
    
    NaiBase.ConfigPresets[moduleName][presetName] = table.Copy(NaiBase.Config[moduleName])
    NaiBase.Log("Saved preset '" .. presetName .. "' for " .. moduleName, NaiBase.Colors.Success)
    return true
end

function NaiBase.LoadPreset(moduleName, presetName)
    if not NaiBase.ConfigPresets[moduleName] or not NaiBase.ConfigPresets[moduleName][presetName] then
        return false
    end
    
    for key, value in pairs(NaiBase.ConfigPresets[moduleName][presetName]) do
        NaiBase.SetConfig(key, value, moduleName)
    end
    
    NaiBase.Log("Loaded preset '" .. presetName .. "' for " .. moduleName, NaiBase.Colors.Success)
    return true
end

function NaiBase.GetPresets(moduleName)
    return NaiBase.ConfigPresets[moduleName] or {}
end

function NaiBase.ExportConfigs(moduleName)
    local data = moduleName and NaiBase.Config[moduleName] or NaiBase.Config
    return util.TableToJSON(data, true)
end

function NaiBase.ImportConfigs(jsonStr, moduleName)
    local success, data = pcall(util.JSONToTable, jsonStr)
    if not success or not data then return false end
    
    if moduleName then
        for key, value in pairs(data) do
            NaiBase.SetConfig(key, value, moduleName)
        end
    else
        for module, configs in pairs(data) do
            for key, value in pairs(configs) do
                NaiBase.SetConfig(key, value, module)
            end
        end
    end
    
    return true
end

function NaiBase.GetConfigMeta(moduleName, key)
    local configKey = moduleName .. "." .. key
    return NaiBase.ConfigMeta[configKey]
end

function NaiBase.GetModuleConfigMeta(moduleName)
    local grouped = {}
    
    for configKey, meta in pairs(NaiBase.ConfigMeta) do
        if meta.module == moduleName then
            local category = meta.category or "General"
            if not grouped[category] then
                grouped[category] = {}
            end
            table.insert(grouped[category], meta)
        end
    end
    
    return grouped
end

function NaiBase.GetConfig(key, default, moduleName)
    moduleName = moduleName or "global"
    
    if moduleName == "global" and key == "debug_mode" then
        local cv = GetConVar("naibase_debug")
        if cv then
            return cv:GetBool()
        end
    end
    
    if NaiBase.Config[moduleName] and NaiBase.Config[moduleName][key] ~= nil then
        return NaiBase.Config[moduleName][key]
    end
    
    if default == nil and NaiBase.ConfigDefaults[moduleName] then
        default = NaiBase.ConfigDefaults[moduleName][key]
    end
    
    return default
end

-- Event System
-- Custom event dispatcher for inter-module communication
function NaiBase.RegisterEvent(eventName, callback, moduleName)
    if not eventName or not isfunction(callback) then
        ErrorNoHalt("[Nai's Base] Invalid event registration\n")
        return false
    end
    
    moduleName = moduleName or "unknown"
    
    if not NaiBase.DiscoveredEvents[eventName] then
        NaiBase.DiscoveredEvents[eventName] = {
            name = eventName,
            firstTriggered = 0,
            triggerCount = 0,
            listeners = {}
        }
    end
    table.insert(NaiBase.DiscoveredEvents[eventName].listeners, moduleName)
    
    if not NaiBase.Hooks[eventName] then
        NaiBase.Hooks[eventName] = {}
    end
    
    table.insert(NaiBase.Hooks[eventName], {
        callback = callback,
        module = moduleName
    })
    
    return true
end

function NaiBase.TriggerEvent(eventName, ...)
    if not NaiBase.DiscoveredEvents[eventName] then
        NaiBase.DiscoveredEvents[eventName] = {
            name = eventName,
            firstTriggered = os.time(),
            triggerCount = 0,
            listeners = {}
        }
    end
    NaiBase.DiscoveredEvents[eventName].triggerCount = NaiBase.DiscoveredEvents[eventName].triggerCount + 1
    
    if not NaiBase.Hooks[eventName] then
        return
    end
    
    for _, hook in ipairs(NaiBase.Hooks[eventName]) do
        local success, err = pcall(hook.callback, ...)
        if not success then
            ErrorNoHalt("[Nai's Base] Event '" .. eventName .. "' callback error from '" .. hook.module .. "': " .. tostring(err) .. "\n")
        end
    end
end

-- Utility Functions
function NaiBase.Log(message, color)
    color = color or NaiBase.Colors.Info
    MsgC(color, "[Nai's Base] " .. tostring(message) .. "\n")
end

function NaiBase.LogError(message)
    ErrorNoHalt("[Nai's Base] ERROR: " .. tostring(message) .. "\n")
end

function NaiBase.LogSuccess(message)
    NaiBase.Log(message, NaiBase.Colors.Success)
end

function NaiBase.LogWarning(message)
    NaiBase.Log(message, NaiBase.Colors.Warning)
end

-- Debug System
NaiBase.SetConfig("debug_mode", false, "global")

function NaiBase.Debug(message, moduleName)
    if NaiBase.GetConfig("debug_mode", false, "global") then
        local prefix = moduleName and ("[" .. moduleName .. "] ") or ""
        MsgC(NaiBase.Colors.Info, "[Nai's Base Debug] " .. prefix .. tostring(message) .. "\n")
    end
end

-- Data Sharing System
-- Allows modules to share data with each other
NaiBase.SharedData = NaiBase.SharedData or {}

function NaiBase.SetSharedData(key, value, moduleName)
    moduleName = moduleName or "global"
    
    if not NaiBase.SharedData[moduleName] then
        NaiBase.SharedData[moduleName] = {}
    end
    
    local dataKey = moduleName .. "." .. key
    if not NaiBase.DiscoveredData[dataKey] then
        NaiBase.DiscoveredData[dataKey] = {
            module = moduleName,
            key = key,
            type = type(value),
            lastUpdated = os.time()
        }
    end
    NaiBase.DiscoveredData[dataKey].type = type(value)
    NaiBase.DiscoveredData[dataKey].lastUpdated = os.time()
    
    NaiBase.SharedData[moduleName][key] = value
    NaiBase.TriggerEvent("NaiBase.DataChanged", moduleName, key, value)
end

function NaiBase.GetSharedData(key, moduleName)
    moduleName = moduleName or "global"
    
    if NaiBase.SharedData[moduleName] then
        return NaiBase.SharedData[moduleName][key]
    end
    
    return nil
end

-- Console Command for listing modules
concommand.Add("naibase_list", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("You don't have permission to use this command")
        return
    end
    
    MsgC(NaiBase.Colors.Primary, "[Nai's Base System]\n")
    MsgC(NaiBase.Colors.Info, "Version: " .. NaiBase.Version .. "\n")
    MsgC(NaiBase.Colors.Info, "Loaded Modules: " .. table.Count(NaiBase.Modules) .. "\n\n")
    
    for name, module in pairs(NaiBase.Modules) do
        MsgC(NaiBase.Colors.Primary, "Ã¢â‚¬Â¢ " .. name .. "\n")
        MsgC(NaiBase.Colors.Info, "  Version: " .. module.version .. "\n")
        MsgC(NaiBase.Colors.Info, "  Author: " .. module.author .. "\n")
        MsgC(NaiBase.Colors.Info, "  Description: " .. module.description .. "\n")
        MsgC(NaiBase.Colors.Info, "  Icon: " .. module.icon .. "\n\n")
    end
end)

concommand.Add("naibase_discover", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("You don't have permission to use this command")
        return
    end
    
    MsgC(NaiBase.Colors.Primary, "[Nai's Base Auto-Discovery]\n\n")
    
    local events = NaiBase.GetDiscoveredEvents()
    MsgC(NaiBase.Colors.Success, "Discovered Events: " .. table.Count(events) .. "\n")
    for eventName, eventData in pairs(events) do
        MsgC(NaiBase.Colors.Info, "  Ã¢â‚¬Â¢ " .. eventName .. " (triggered " .. eventData.triggerCount .. " times, " .. #eventData.listeners .. " listeners)\n")
    end
    MsgC(NaiBase.Colors.Info, "\n")
    
    local convars = NaiBase.GetDiscoveredConVars()
    MsgC(NaiBase.Colors.Success, "Discovered ConVars: " .. table.Count(convars) .. "\n")
    for cvarName, cvarData in pairs(convars) do
        MsgC(NaiBase.Colors.Info, "  Ã¢â‚¬Â¢ " .. cvarName .. " (" .. cvarData.module .. ")\n")
    end
    MsgC(NaiBase.Colors.Info, "\n")
    
    local data = NaiBase.GetDiscoveredData()
    MsgC(NaiBase.Colors.Success, "Discovered Data Keys: " .. table.Count(data) .. "\n")
    for dataKey, dataInfo in pairs(data) do
        MsgC(NaiBase.Colors.Info, "  Ã¢â‚¬Â¢ " .. dataKey .. " [" .. dataInfo.type .. "]\n")
    end
end)

function NaiBase.DiscoverModuleConVars()
    for moduleName, moduleData in pairs(NaiBase.Modules) do
        local prefixes = {
            string.lower(string.gsub(moduleName, " ", "_")),
            string.lower(string.gsub(moduleName, " ", "")),
        }
        
        if string.find(moduleName, "NPC") or string.find(moduleName, "Passenger") then
            table.insert(prefixes, "nai_npc")
        end
        
        local testPrefixes = {"nai_npc", "naibase", "nai"}
        for _, prefix in ipairs(testPrefixes) do
            local patterns = {
                prefix .. "_*",
                prefix .. "*"
            }
            
            local commonNames = {
                "_max_attach_dist", "_debug_mode", "_allow_multiple",
                "_auto_join", "_speech_enabled", "_body_sway",
                "_hud_enabled", "_exit_mode"
            }
            
            for _, name in ipairs(commonNames) do
                local cvName = prefix .. name
                local cv = GetConVar(cvName)
                if cv then
                    if not NaiBase.DiscoveredConVars[cvName] then
                        NaiBase.DiscoveredConVars[cvName] = {
                            name = cvName,
                            module = moduleName,
                            default = cv:GetDefault(),
                            helpText = cv:GetHelpText(),
                            discovered = os.time()
                        }
                    end
                end
            end
        end
    end
    
    for _, cv in pairs(_G) do
        if type(cv) == "ConVar" or (type(cv) == "table" and cv.GetName) then
            local success, cvName = pcall(function() return cv:GetName() end)
            if success and cvName then
                for moduleName, _ in pairs(NaiBase.Modules) do
                    local prefixes = {
                        "nai_npc",
                        "naibase",
                        string.lower(string.gsub(moduleName, " ", "_"))
                    }
                    
                    for _, prefix in ipairs(prefixes) do
                        if string.StartWith(cvName, prefix) then
                            if not NaiBase.DiscoveredConVars[cvName] then
                                NaiBase.DiscoveredConVars[cvName] = {
                                    name = cvName,
                                    module = moduleName,
                                    default = cv:GetDefault(),
                                    helpText = cv:GetHelpText(),
                                    discovered = os.time()
                                }
                            end
                        end
                    end
                end
            end
        end
    end
end

function NaiBase.GetDiscoveredEvents()
    return NaiBase.DiscoveredEvents
end

function NaiBase.GetDiscoveredConVars(moduleName)
    if moduleName then
        local filtered = {}
        for name, data in pairs(NaiBase.DiscoveredConVars) do
            if data.module == moduleName then
                filtered[name] = data
            end
        end
        return filtered
    end
    return NaiBase.DiscoveredConVars
end

function NaiBase.GetDiscoveredData(moduleName)
    if moduleName then
        local filtered = {}
        for key, data in pairs(NaiBase.DiscoveredData or {}) do
            if data.module == moduleName then
                filtered[key] = data
            end
        end
        return filtered
    end
    return NaiBase.DiscoveredData or {}
end

MsgC(NaiBase.Colors.Primary, "[Nai's Base] Base API v" .. NaiBase.Version .. " loaded\n")
MsgC(NaiBase.Colors.Info, "[Nai's Base] Type 'naibase_list' in console to see loaded modules\n")

timer.Simple(0, function()
    NaiBase.TriggerEvent("NaiBase.BaseLoaded")
    NaiBase.DiscoverModuleConVars()
    MsgC(NaiBase.Colors.Success, "[Nai's Base] Auto-discovered " .. table.Count(NaiBase.DiscoveredConVars) .. " ConVars\n")
end)
