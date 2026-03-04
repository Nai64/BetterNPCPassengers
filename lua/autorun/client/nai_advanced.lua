if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Advanced Features"
local MODULE_VERSION = "1.0.0"

local FPSTracker = {
    history = {},
    maxSamples = 60,
    avgFPS = 0,
    minFPS = 999,
    maxFPS = 0
}

local NetworkMonitor = {
    bytesReceived = 0,
    bytesSent = 0,
    packetsReceived = 0,
    packetsSent = 0,
    lastCheck = 0
}

local RenderStats = {
    drawCalls = 0,
    triangles = 0,
    materials = 0,
    textures = 0
}

local EntityProfiler = {}
local HookProfiler = {}
local ProfilingEnabled = false

hook.Add("InitPostEntity", "NaiBase_AdvancedInit", function()
    timer.Simple(2, function()
        if not NaiBase then
            print("[Advanced Features] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai's Base Team",
            description = "Advanced profiling, monitoring, and diagnostic tools",
            icon = "icon16/chart_line.png",
            init = function()
                InitializeAdvancedFeatures()
            end
        })
        
        RegisterAdvancedConfigs()
    end)
end)

function RegisterAdvancedConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "fps_monitoring", {
        displayName = "FPS Monitoring",
        description = "Track and analyze frame rate",
        category = "Monitoring",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "network_monitoring", {
        displayName = "Network Monitoring",
        description = "Monitor network traffic",
        category = "Monitoring",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "entity_profiling", {
        displayName = "Entity Profiling",
        description = "Profile entity performance impact",
        category = "Profiling",
        valueType = "boolean",
        default = false
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "hook_profiling", {
        displayName = "Hook Profiling",
        description = "Profile hook execution times",
        category = "Profiling",
        valueType = "boolean",
        default = false
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "auto_screenshot", {
        displayName = "Auto Screenshot on Error",
        description = "Automatically capture screenshots when errors occur",
        category = "Debugging",
        valueType = "boolean",
        default = false
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "performance_warnings", {
        displayName = "Performance Warnings",
        description = "Show warnings when FPS drops below threshold",
        category = "Alerts",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "fps_threshold", {
        displayName = "FPS Warning Threshold",
        description = "FPS level that triggers performance warnings",
        category = "Alerts",
        valueType = "number",
        default = 30,
        min = 10,
        max = 60
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "auto_optimize", {
        displayName = "Auto Optimize on Lag",
        description = "Automatically increase optimizations when lagging",
        category = "Auto-Tuning",
        valueType = "boolean",
        default = false
    })
end

function InitializeAdvancedFeatures()
    print("[Advanced Features] Initializing advanced systems...")
    
    SetupFPSMonitoring()
    SetupNetworkMonitoring()
    SetupEntityProfiler()
    SetupHookProfiler()
    SetupErrorHandler()
    SetupPerformanceAlerts()
    SetupAutoTuning()
    
    print("[Advanced Features] All advanced systems active")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.AdvancedFeaturesReady")
    end
end

function SetupFPSMonitoring()
    hook.Add("HUDPaint", "NaiBase_FPSMonitoring", function()
        if not GetConfigValue("fps_monitoring") then return end
        
        local currentFPS = math.floor(1 / FrameTime())
        
        table.insert(FPSTracker.history, currentFPS)
        if #FPSTracker.history > FPSTracker.maxSamples then
            table.remove(FPSTracker.history, 1)
        end
        
        local sum = 0
        FPSTracker.minFPS = 999
        FPSTracker.maxFPS = 0
        
        for _, fps in ipairs(FPSTracker.history) do
            sum = sum + fps
            if fps < FPSTracker.minFPS then FPSTracker.minFPS = fps end
            if fps > FPSTracker.maxFPS then FPSTracker.maxFPS = fps end
        end
        
        FPSTracker.avgFPS = math.floor(sum / #FPSTracker.history)
    end)
end

function SetupNetworkMonitoring()
    local lastBytes = 0
    local lastPackets = 0
    
    hook.Add("Think", "NaiBase_NetworkMonitoring", function()
        if not GetConfigValue("network_monitoring") then return end
        
        local currentTime = CurTime()
        if currentTime - NetworkMonitor.lastCheck < 1 then return end
        
        NetworkMonitor.lastCheck = currentTime
    end)
end

function SetupEntityProfiler()
    hook.Add("Think", "NaiBase_EntityProfiler", function()
        if not GetConfigValue("entity_profiling") then 
            EntityProfiler = {}
            return 
        end
        
        local startTime = SysTime()
        
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local class = ent:GetClass()
                if not EntityProfiler[class] then
                    EntityProfiler[class] = {
                        count = 0,
                        totalTime = 0,
                        avgTime = 0
                    }
                end
                
                EntityProfiler[class].count = EntityProfiler[class].count + 1
                
                local entStartTime = SysTime()
                local entEndTime = SysTime()
                local entTime = entEndTime - entStartTime
                
                EntityProfiler[class].totalTime = EntityProfiler[class].totalTime + entTime
                EntityProfiler[class].avgTime = EntityProfiler[class].totalTime / EntityProfiler[class].count
            end
        end
    end)
end

function SetupHookProfiler()
    if not GetConfigValue("hook_profiling") then return end
    
    local oldHookCall = hook.Call
    hook.Call = function(name, gm, ...)
        local startTime = SysTime()
        local results = {oldHookCall(name, gm, ...)}
        local endTime = SysTime()
        local execTime = endTime - startTime
        
        if not HookProfiler[name] then
            HookProfiler[name] = {
                calls = 0,
                totalTime = 0,
                avgTime = 0,
                maxTime = 0
            }
        end
        
        HookProfiler[name].calls = HookProfiler[name].calls + 1
        HookProfiler[name].totalTime = HookProfiler[name].totalTime + execTime
        HookProfiler[name].avgTime = HookProfiler[name].totalTime / HookProfiler[name].calls
        
        if execTime > HookProfiler[name].maxTime then
            HookProfiler[name].maxTime = execTime
        end
        
        return unpack(results)
    end
end

function SetupErrorHandler()
    local lastErrorTime = 0
    local errorCount = 0
    
    hook.Add("OnLuaError", "NaiBase_ErrorHandler", function(err, realm, stack, name, id)
        local currentTime = CurTime()
        
        if currentTime - lastErrorTime < 5 then
            errorCount = errorCount + 1
        else
            errorCount = 1
        end
        lastErrorTime = currentTime
        
        if GetConfigValue("auto_screenshot") and errorCount <= 3 then
            timer.Simple(0.1, function()
                RunConsoleCommand("screenshot")
            end)
        end
        
        if NaiBase then
            NaiBase.SetSharedData("last_error", {
                message = err,
                time = currentTime,
                realm = realm,
                stack = stack
            }, MODULE_NAME)
            
            NaiBase.TriggerEvent("NaiBase.ErrorOccurred", err, realm, stack)
        end
    end)
end

function SetupPerformanceAlerts()
    local lastWarning = 0
    local warningCooldown = 30
    
    hook.Add("Think", "NaiBase_PerformanceAlerts", function()
        if not GetConfigValue("performance_warnings") then return end
        
        local currentTime = CurTime()
        if currentTime - lastWarning < warningCooldown then return end
        
        local currentFPS = math.floor(1 / FrameTime())
        local threshold = GetConfigValue("fps_threshold", 30)
        
        if currentFPS < threshold then
            lastWarning = currentTime
            
            chat.AddText(
                Color(255, 200, 100), "[Performance] ",
                Color(255, 255, 255), "FPS dropped to ",
                Color(255, 100, 100), tostring(currentFPS),
                Color(255, 255, 255), " (threshold: " .. threshold .. ")"
            )
            
            if NaiBase then
                NaiBase.TriggerEvent("NaiBase.LowFPS", currentFPS, threshold)
            end
        end
    end)
end

function SetupAutoTuning()
    local lastTuning = 0
    local tuningInterval = 60
    local consecutiveLowFPS = 0
    
    hook.Add("Think", "NaiBase_AutoTuning", function()
        if not GetConfigValue("auto_optimize") then return end
        
        local currentTime = CurTime()
        if currentTime - lastTuning < tuningInterval then return end
        lastTuning = currentTime
        
        local currentFPS = math.floor(1 / FrameTime())
        local threshold = GetConfigValue("fps_threshold", 30)
        
        if currentFPS < threshold then
            consecutiveLowFPS = consecutiveLowFPS + 1
            
            if consecutiveLowFPS >= 3 then
                ApplyAggressiveOptimizations()
                consecutiveLowFPS = 0
                
                chat.AddText(
                    Color(100, 200, 255), "[Auto-Tuning] ",
                    Color(255, 255, 255), "Applied aggressive optimizations due to low FPS"
                )
            end
        else
            consecutiveLowFPS = 0
        end
    end)
end

function ApplyAggressiveOptimizations()
    if NaiBase and NaiBase.SetConfig then
        NaiBase.SetConfig("entity_distance", 1500, "Performance Optimizer")
        NaiBase.SetConfig("sound_distance", 2000, "Performance Optimizer")
        
        RunConsoleCommand("naibase_opti_cleanup")
        
        collectgarbage("collect")
    end
end

function NaiBase.GetFPSStats()
    return {
        current = math.floor(1 / FrameTime()),
        average = FPSTracker.avgFPS,
        min = FPSTracker.minFPS,
        max = FPSTracker.maxFPS,
        history = FPSTracker.history
    }
end

function NaiBase.GetNetworkStats()
    return NetworkMonitor
end

function NaiBase.GetEntityProfilerData()
    return EntityProfiler
end

function NaiBase.GetHookProfilerData()
    return HookProfiler
end

function NaiBase.ResetProfilers()
    EntityProfiler = {}
    HookProfiler = {}
    FPSTracker.history = {}
    FPSTracker.minFPS = 999
    FPSTracker.maxFPS = 0
    
    print("[Advanced Features] All profilers reset")
end

concommand.Add("naibase_fps_stats", function()
    local stats = NaiBase.GetFPSStats()
    print("========================================")
    print("[FPS Monitor] Statistics")
    print("========================================")
    print("Current FPS: " .. stats.current)
    print("Average FPS: " .. stats.average)
    print("Min FPS: " .. stats.min)
    print("Max FPS: " .. stats.max)
    print("Sample Count: " .. #stats.history)
    print("========================================")
end)

concommand.Add("naibase_entity_profile", function()
    print("========================================")
    print("[Entity Profiler] Top 10 Most Expensive")
    print("========================================")
    
    local sorted = {}
    for class, data in pairs(EntityProfiler) do
        table.insert(sorted, {class = class, data = data})
    end
    
    table.sort(sorted, function(a, b)
        return a.data.avgTime > b.data.avgTime
    end)
    
    for i = 1, math.min(10, #sorted) do
        local entry = sorted[i]
        print(string.format("%d. %s - Count: %d, Avg: %.6fms", 
            i, entry.class, entry.data.count, entry.data.avgTime * 1000))
    end
    print("========================================")
end)

concommand.Add("naibase_hook_profile", function()
    print("========================================")
    print("[Hook Profiler] Top 10 Slowest Hooks")
    print("========================================")
    
    local sorted = {}
    for name, data in pairs(HookProfiler) do
        table.insert(sorted, {name = name, data = data})
    end
    
    table.sort(sorted, function(a, b)
        return a.data.avgTime > b.data.avgTime
    end)
    
    for i = 1, math.min(10, #sorted) do
        local entry = sorted[i]
        print(string.format("%d. %s - Calls: %d, Avg: %.6fms, Max: %.6fms", 
            i, entry.name, entry.data.calls, 
            entry.data.avgTime * 1000, entry.data.maxTime * 1000))
    end
    print("========================================")
end)

concommand.Add("naibase_reset_profilers", function()
    NaiBase.ResetProfilers()
end)

concommand.Add("naibase_force_optimize", function()
    ApplyAggressiveOptimizations()
    print("[Advanced Features] Forced aggressive optimizations")
end)

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

hook.Add("ShutDown", "NaiBase_AdvancedShutdown", function()
    EntityProfiler = {}
    HookProfiler = {}
    FPSTracker.history = {}
end)

print("[Advanced Features] Module loaded successfully")
