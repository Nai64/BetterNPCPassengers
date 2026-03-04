if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Resource Monitor"
local MODULE_VERSION = "1.0.0"

local ResourceData = {
    cpu = {
        usage = 0,
        history = {},
        maxHistory = 100
    },
    memory = {
        current = 0,
        peak = 0,
        history = {},
        maxHistory = 100
    },
    entities = {
        count = 0,
        limit = 8192,
        breakdown = {}
    },
    network = {
        ping = 0,
        loss = 0,
        inRate = 0,
        outRate = 0
    }
}

hook.Add("InitPostEntity", "NaiBase_ResourceMonitorInit", function()
    timer.Simple(2.5, function()
        if not NaiBase then
            print("[Resource Monitor] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai's Base Team",
            description = "Real-time system resource monitoring and analysis",
            icon = "icon16/chart_bar.png",
            init = function()
                InitializeResourceMonitor()
            end
        })
        
        RegisterResourceConfigs()
    end)
end)

function RegisterResourceConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "show_overlay", {
        displayName = "Show Resource Overlay",
        description = "Display resource usage on screen",
        category = "Display",
        valueType = "boolean",
        default = false
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "overlay_position", {
        displayName = "Overlay Position",
        description = "Screen position for overlay",
        category = "Display",
        valueType = "string",
        default = "top_right",
        options = {
            {value = "top_left", text = "Top Left"},
            {value = "top_right", text = "Top Right"},
            {value = "bottom_left", text = "Bottom Left"},
            {value = "bottom_right", text = "Bottom Right"}
        }
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "update_rate", {
        displayName = "Update Rate",
        description = "Seconds between resource updates",
        category = "Performance",
        valueType = "number",
        default = 0.5,
        min = 0.1,
        max = 5
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "track_entity_breakdown", {
        displayName = "Track Entity Breakdown",
        description = "Monitor entity counts by class",
        category = "Tracking",
        valueType = "boolean",
        default = true
    })
end

function InitializeResourceMonitor()
    print("[Resource Monitor] Initializing resource tracking...")
    
    SetupResourceTracking()
    SetupOverlay()
    
    print("[Resource Monitor] Resource tracking active")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.ResourceMonitorReady")
    end
end

function SetupResourceTracking()
    local lastUpdate = 0
    
    hook.Add("Think", "NaiBase_ResourceTracking", function()
        local updateRate = GetConfigValue("update_rate", 0.5)
        local currentTime = CurTime()
        
        if currentTime - lastUpdate < updateRate then return end
        lastUpdate = currentTime
        
        local memUsage = collectgarbage("count")
        ResourceData.memory.current = memUsage
        if memUsage > ResourceData.memory.peak then
            ResourceData.memory.peak = memUsage
        end
        
        table.insert(ResourceData.memory.history, memUsage)
        if #ResourceData.memory.history > ResourceData.memory.maxHistory then
            table.remove(ResourceData.memory.history, 1)
        end
        
        local frameTime = FrameTime()
        local cpuEstimate = math.Clamp((frameTime / 0.016) * 100, 0, 100)
        ResourceData.cpu.usage = cpuEstimate
        
        table.insert(ResourceData.cpu.history, cpuEstimate)
        if #ResourceData.cpu.history > ResourceData.cpu.maxHistory then
            table.remove(ResourceData.cpu.history, 1)
        end
        
        ResourceData.entities.count = #ents.GetAll()
        
        if GetConfigValue("track_entity_breakdown") then
            ResourceData.entities.breakdown = {}
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) then
                    local class = ent:GetClass()
                    ResourceData.entities.breakdown[class] = (ResourceData.entities.breakdown[class] or 0) + 1
                end
            end
        end
        
        if LocalPlayer():IsValid() then
            ResourceData.network.ping = LocalPlayer():Ping()
            ResourceData.network.loss = LocalPlayer():PacketLoss()
        end
    end)
end

function SetupOverlay()
    hook.Add("HUDPaint", "NaiBase_ResourceOverlay", function()
        if not GetConfigValue("show_overlay") then return end
        
        local x, y = GetOverlayPosition()
        local boxWidth = 250
        local boxHeight = 120
        
        draw.RoundedBox(6, x, y, boxWidth, boxHeight, Color(30, 30, 35, 230))
        draw.RoundedBox(6, x + 2, y + 2, boxWidth - 4, 20, Color(100, 200, 255, 100))
        
        draw.SimpleText("Resource Monitor", "DermaDefault", x + 10, y + 5, Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        local yOffset = y + 30
        local lineHeight = 18
        
        local fps = math.floor(1 / FrameTime())
        local fpsColor = fps > 60 and Color(100, 255, 100) or (fps > 30 and Color(255, 200, 100) or Color(255, 100, 100))
        draw.SimpleText("FPS: " .. fps, "DermaDefault", x + 10, yOffset, fpsColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        yOffset = yOffset + lineHeight
        
        local memColor = ResourceData.memory.current > 500000 and Color(255, 100, 100) or Color(200, 200, 200)
        draw.SimpleText(string.format("Memory: %.1f MB", ResourceData.memory.current / 1024), "DermaDefault", x + 10, yOffset, memColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        yOffset = yOffset + lineHeight
        
        local entColor = ResourceData.entities.count > 1000 and Color(255, 200, 100) or Color(200, 200, 200)
        draw.SimpleText("Entities: " .. ResourceData.entities.count, "DermaDefault", x + 10, yOffset, entColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        yOffset = yOffset + lineHeight
        
        local pingColor = ResourceData.network.ping > 100 and Color(255, 100, 100) or Color(100, 255, 100)
        draw.SimpleText("Ping: " .. ResourceData.network.ping .. " ms", "DermaDefault", x + 10, yOffset, pingColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        yOffset = yOffset + lineHeight
        
        draw.SimpleText("Loss: " .. string.format("%.1f%%", ResourceData.network.loss), "DermaDefault", x + 10, yOffset, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end)
end

function GetOverlayPosition()
    local position = GetConfigValue("overlay_position", "top_right")
    local margin = 10
    local boxWidth = 250
    local boxHeight = 120
    
    if position == "top_left" then
        return margin, margin
    elseif position == "top_right" then
        return ScrW() - boxWidth - margin, margin
    elseif position == "bottom_left" then
        return margin, ScrH() - boxHeight - margin
    else
        return ScrW() - boxWidth - margin, ScrH() - boxHeight - margin
    end
end

function NaiBase.GetResourceData()
    return ResourceData
end

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

concommand.Add("naibase_resources", function()
    print("========================================")
    print("[Resource Monitor] Current Status")
    print("========================================")
    print(string.format("CPU Usage: %.1f%%", ResourceData.cpu.usage))
    print(string.format("Memory: %.2f MB (Peak: %.2f MB)", ResourceData.memory.current / 1024, ResourceData.memory.peak / 1024))
    print(string.format("Entities: %d / %d", ResourceData.entities.count, ResourceData.entities.limit))
    print(string.format("Network - Ping: %d ms, Loss: %.1f%%", ResourceData.network.ping, ResourceData.network.loss))
    print("========================================")
end)

concommand.Add("naibase_entity_breakdown", function()
    print("========================================")
    print("[Resource Monitor] Entity Breakdown")
    print("========================================")
    
    local sorted = {}
    for class, count in pairs(ResourceData.entities.breakdown) do
        table.insert(sorted, {class = class, count = count})
    end
    
    table.sort(sorted, function(a, b) return a.count > b.count end)
    
    for i = 1, math.min(15, #sorted) do
        print(string.format("%d. %s: %d", i, sorted[i].class, sorted[i].count))
    end
    print("========================================")
end)

print("[Resource Monitor] Module loaded successfully")
