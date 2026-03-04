if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Console Logger"
local MODULE_VERSION = "1.0.0"

local LogData = {
    entries = {},
    maxEntries = 500,
    filters = {},
    categories = {
        ["error"] = {color = Color(255, 100, 100), count = 0},
        ["warning"] = {color = Color(255, 200, 100), count = 0},
        ["info"] = {color = Color(100, 200, 255), count = 0},
        ["success"] = {color = Color(100, 255, 100), count = 0},
        ["debug"] = {color = Color(200, 200, 200), count = 0}
    },
    searchTerm = "",
    autoScroll = true
}

hook.Add("InitPostEntity", "NaiBase_ConsoleLoggerInit", function()
    timer.Simple(4, function()
        if not NaiBase then
            print("[Console Logger] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai's Base Team",
            description = "Advanced console logging with filtering and search",
            icon = "icon16/page_white_text.png",
            init = function()
                InitializeConsoleLogger()
            end
        })
        
        RegisterLoggerConfigs()
    end)
end)

function RegisterLoggerConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "enable_logging", {
        displayName = "Enable Logging",
        description = "Capture console output",
        category = "General",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "max_entries", {
        displayName = "Max Log Entries",
        description = "Maximum number of log entries to keep",
        category = "Storage",
        valueType = "number",
        default = 500,
        min = 100,
        max = 5000
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "log_errors", {
        displayName = "Log Errors",
        description = "Capture error messages",
        category = "Filters",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "log_warnings", {
        displayName = "Log Warnings",
        description = "Capture warning messages",
        category = "Filters",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "log_info", {
        displayName = "Log Info",
        description = "Capture info messages",
        category = "Filters",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "auto_export", {
        displayName = "Auto Export on Error",
        description = "Automatically save logs when errors occur",
        category = "Export",
        valueType = "boolean",
        default = false
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "timestamp_format", {
        displayName = "Timestamp Format",
        description = "Format for log timestamps",
        category = "Display",
        valueType = "string",
        default = "%H:%M:%S",
        options = {
            {value = "%H:%M:%S", text = "HH:MM:SS"},
            {value = "%Y-%m-%d %H:%M:%S", text = "YYYY-MM-DD HH:MM:SS"},
            {value = "%I:%M:%S %p", text = "12-hour with AM/PM"}
        }
    })
end

function InitializeConsoleLogger()
    print("[Console Logger] Initializing logging systems...")
    
    SetupLogCapture()
    SetupErrorCapture()
    
    print("[Console Logger] Logging systems active")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.ConsoleLoggerReady")
    end
end

function SetupLogCapture()
    local oldMsgC = MsgC
    local oldprint = print
    
    MsgC = function(...)
        if GetConfigValue("enable_logging") then
            CaptureLog("info", {...})
        end
        return oldMsgC(...)
    end
    
    print = function(...)
        if GetConfigValue("enable_logging") then
            CaptureLog("info", {...})
        end
        return oldprint(...)
    end
end

function SetupErrorCapture()
    hook.Add("OnLuaError", "NaiBase_ConsoleLogger", function(err, realm, stack, name, id)
        if not GetConfigValue("log_errors") then return end
        
        CaptureLog("error", {
            Color(255, 100, 100), "[LUA ERROR] ",
            color_white, err,
            Color(150, 150, 150), " (", realm, ")"
        })
        
        if GetConfigValue("auto_export") then
            timer.Simple(0.5, function()
                ExportLogs(true)
            end)
        end
        
        if NaiBase then
            NaiBase.TriggerEvent("NaiBase.ErrorLogged", err, realm)
        end
    end)
end

function CaptureLog(category, args)
    local timestamp = os.date(GetConfigValue("timestamp_format", "%H:%M:%S"))
    
    local message = ""
    for _, arg in ipairs(args) do
        if type(arg) == "string" then
            message = message .. arg
        elseif type(arg) ~= "table" then
            message = message .. tostring(arg)
        end
    end
    
    table.insert(LogData.entries, {
        timestamp = timestamp,
        realTime = CurTime(),
        category = category,
        message = message,
        args = args
    })
    
    LogData.maxEntries = GetConfigValue("max_entries", 500)
    
    if #LogData.entries > LogData.maxEntries then
        table.remove(LogData.entries, 1)
    end
    
    if LogData.categories[category] then
        LogData.categories[category].count = LogData.categories[category].count + 1
    end
end

function ExportLogs(errorMode)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = "naibase_logs_" .. timestamp .. ".txt"
    
    if errorMode then
        filename = "naibase_error_logs_" .. timestamp .. ".txt"
    end
    
    local content = "Nai's Base Console Logs\n"
    content = content .. "Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    content = content .. "Total Entries: " .. #LogData.entries .. "\n"
    content = content .. "========================================\n\n"
    
    for _, entry in ipairs(LogData.entries) do
        content = content .. "[" .. entry.timestamp .. "] "
        content = content .. "[" .. string.upper(entry.category) .. "] "
        content = content .. entry.message .. "\n"
    end
    
    file.Write(filename, content)
    print("[Console Logger] Logs exported to: " .. filename)
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.LogsExported", filename)
    end
    
    return filename
end

function NaiBase.GetLogEntries(category, limit)
    local entries = {}
    
    for i = #LogData.entries, 1, -1 do
        local entry = LogData.entries[i]
        
        if not category or entry.category == category then
            table.insert(entries, entry)
            
            if limit and #entries >= limit then
                break
            end
        end
    end
    
    return entries
end

function NaiBase.SearchLogs(searchTerm)
    local results = {}
    
    searchTerm = string.lower(searchTerm)
    
    for _, entry in ipairs(LogData.entries) do
        if string.find(string.lower(entry.message), searchTerm, 1, true) then
            table.insert(results, entry)
        end
    end
    
    return results
end

function NaiBase.ClearLogs()
    LogData.entries = {}
    for category, data in pairs(LogData.categories) do
        data.count = 0
    end
    print("[Console Logger] All logs cleared")
end

function NaiBase.GetLogStats()
    local stats = {
        totalEntries = #LogData.entries,
        byCategory = {}
    }
    
    for category, data in pairs(LogData.categories) do
        stats.byCategory[category] = data.count
    end
    
    return stats
end

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

concommand.Add("naibase_logs_export", function()
    ExportLogs(false)
end)

concommand.Add("naibase_logs_clear", function()
    NaiBase.ClearLogs()
end)

concommand.Add("naibase_logs_stats", function()
    local stats = NaiBase.GetLogStats()
    
    print("========================================")
    print("[Console Logger] Statistics")
    print("========================================")
    print("Total Entries: " .. stats.totalEntries)
    print("\nBy Category:")
    
    for category, count in pairs(stats.byCategory) do
        print("  " .. category .. ": " .. count)
    end
    
    print("========================================")
end)

concommand.Add("naibase_logs_search", function(ply, cmd, args)
    if #args == 0 then
        print("[Console Logger] Usage: naibase_logs_search <search term>")
        return
    end
    
    local searchTerm = table.concat(args, " ")
    local results = NaiBase.SearchLogs(searchTerm)
    
    print("========================================")
    print("[Console Logger] Search Results for: " .. searchTerm)
    print("========================================")
    print("Found " .. #results .. " entries")
    print("")
    
    for i = 1, math.min(20, #results) do
        local entry = results[i]
        print("[" .. entry.timestamp .. "] " .. entry.message)
    end
    
    if #results > 20 then
        print("\n... and " .. (#results - 20) .. " more results")
    end
    
    print("========================================")
end)

concommand.Add("naibase_logs_errors", function()
    local errors = NaiBase.GetLogEntries("error", 20)
    
    print("========================================")
    print("[Console Logger] Recent Errors")
    print("========================================")
    
    if #errors == 0 then
        print("No errors logged")
    else
        for i, entry in ipairs(errors) do
            print("[" .. entry.timestamp .. "] " .. entry.message)
        end
    end
    
    print("========================================")
end)

print("[Console Logger] Module loaded successfully")
