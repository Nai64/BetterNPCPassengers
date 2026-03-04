if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Performance Optimizer"
local MODULE_VERSION = "1.0.0"

local OptimizationStats = {
    entitiesOptimized = 0,
    soundsCulled = 0,
    particlesCulled = 0,
    memoryFreed = 0,
    lastCleanup = 0
}

local EntityCache = {}
local SoundCache = {}
local LastOptimizationTime = 0
local OptimizationInterval = 1

hook.Add("InitPostEntity", "NaiBase_OptimizationInit", function()
    timer.Simple(1.5, function()
        if not NaiBase then
            print("[Performance Optimizer] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai",
            description = "Advanced performance optimization without graphics reduction",
            icon = "icon16/lightning.png",
            init = function()
                InitializeOptimization()
            end
        })
        
        RegisterOptimizationConfigs()
    end)
end)

function RegisterOptimizationConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "enabled", {
        displayName = "Enable Optimizations",
        description = "Master switch for all performance optimizations",
        category = "General",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "entity_optimization", {
        displayName = "Entity Optimization",
        description = "Optimize distant entity updates",
        category = "Entities",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "entity_distance", {
        displayName = "Entity Optimization Distance",
        description = "Distance beyond which entities are optimized",
        category = "Entities",
        valueType = "number",
        default = 2000,
        min = 500,
        max = 10000
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "sound_culling", {
        displayName = "Sound Culling",
        description = "Reduce distant sound updates",
        category = "Audio",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "sound_distance", {
        displayName = "Sound Culling Distance",
        description = "Distance beyond which sounds are culled",
        category = "Audio",
        valueType = "number",
        default = 3000,
        min = 1000,
        max = 8000
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "particle_optimization", {
        displayName = "Particle Optimization",
        description = "Optimize particle effects at distance",
        category = "Effects",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "network_optimization", {
        displayName = "Network Optimization",
        description = "Reduce unnecessary network updates",
        category = "Network",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "physics_optimization", {
        displayName = "Physics Optimization",
        description = "Optimize physics calculations for distant objects",
        category = "Physics",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "memory_management", {
        displayName = "Memory Management",
        description = "Automatic memory cleanup",
        category = "Memory",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "cleanup_interval", {
        displayName = "Cleanup Interval",
        description = "Seconds between automatic cleanups",
        category = "Memory",
        valueType = "number",
        default = 300,
        min = 60,
        max = 600
    })
end

function InitializeOptimization()
    print("[Performance Optimizer] Initializing optimization systems...")
    
    SetupEntityOptimization()
    SetupSoundOptimization()
    SetupParticleOptimization()
    SetupNetworkOptimization()
    SetupPhysicsOptimization()
    SetupMemoryManagement()
    
    print("[Performance Optimizer] All optimization systems active")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.OptimizationReady")
    end
end

function SetupEntityOptimization()
    hook.Add("Think", "NaiBase_EntityOptimization", function()
        if not GetConfigValue("entity_optimization") then return end
        
        local currentTime = CurTime()
        if currentTime - LastOptimizationTime < OptimizationInterval then return end
        LastOptimizationTime = currentTime
        
        local localPlayer = LocalPlayer()
        if not IsValid(localPlayer) then return end
        
        local playerPos = localPlayer:GetPos()
        local optimizationDist = GetConfigValue("entity_distance", 2000)
        local optimizationDistSqr = optimizationDist * optimizationDist
        
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent ~= localPlayer then
                local entPos = ent:GetPos()
                local distSqr = playerPos:DistToSqr(entPos)
                
                if distSqr > optimizationDistSqr then
                    if not EntityCache[ent] then
                        EntityCache[ent] = {
                            lastUpdate = currentTime,
                            optimized = false
                        }
                    end
                    
                    if not EntityCache[ent].optimized then
                        OptimizeEntity(ent)
                        EntityCache[ent].optimized = true
                        OptimizationStats.entitiesOptimized = OptimizationStats.entitiesOptimized + 1
                    end
                else
                    if EntityCache[ent] and EntityCache[ent].optimized then
                        RestoreEntity(ent)
                        EntityCache[ent].optimized = false
                    end
                end
            end
        end
    end)
end

function OptimizeEntity(ent)
    if not IsValid(ent) then return end
    
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        if not ent.NaiBase_OriginalCollisionGroup then
            ent.NaiBase_OriginalCollisionGroup = ent:GetCollisionGroup()
        end
    end
end

function RestoreEntity(ent)
    if not IsValid(ent) then return end
    
    if ent.NaiBase_OriginalCollisionGroup then
        ent:SetCollisionGroup(ent.NaiBase_OriginalCollisionGroup)
        ent.NaiBase_OriginalCollisionGroup = nil
    end
end

function SetupSoundOptimization()
    local lastSoundCheck = 0
    
    hook.Add("Think", "NaiBase_SoundOptimization", function()
        if not GetConfigValue("sound_culling") then return end
        
        local currentTime = CurTime()
        if currentTime - lastSoundCheck < 0.5 then return end
        lastSoundCheck = currentTime
        
        local localPlayer = LocalPlayer()
        if not IsValid(localPlayer) then return end
        
        local playerPos = localPlayer:GetPos()
        local soundDist = GetConfigValue("sound_distance", 3000)
        local soundDistSqr = soundDist * soundDist
        
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local entPos = ent:GetPos()
                local distSqr = playerPos:DistToSqr(entPos)
                
                if distSqr > soundDistSqr then
                    if not SoundCache[ent] then
                        SoundCache[ent] = true
                        ent:StopSound("*")
                        OptimizationStats.soundsCulled = OptimizationStats.soundsCulled + 1
                    end
                else
                    SoundCache[ent] = nil
                end
            end
        end
    end)
end

function SetupParticleOptimization()
    if not GetConfigValue("particle_optimization") then return end
    
    local oldEmitEffect = util.Effect
    
    util.Effect = function(name, data, ...)
        if not GetConfigValue("particle_optimization") then
            return oldEmitEffect(name, data, ...)
        end
        
        local localPlayer = LocalPlayer()
        if not IsValid(localPlayer) then
            return oldEmitEffect(name, data, ...)
        end
        
        local effectPos = data:GetOrigin()
        local playerPos = localPlayer:GetPos()
        local distSqr = playerPos:DistToSqr(effectPos)
        
        if distSqr > 4000000 then
            OptimizationStats.particlesCulled = OptimizationStats.particlesCulled + 1
            return
        end
        
        return oldEmitEffect(name, data, ...)
    end
end

function SetupNetworkOptimization()
    if not GetConfigValue("network_optimization") then return end
    
    local NetworkThrottle = {}
    
    net.Receive = net.Receive or function() end
    local oldNetReceive = net.Receive
    
    net.Receive = function(messageName, callback)
        return oldNetReceive(messageName, function(len, ply)
            local currentTime = CurTime()
            
            if not NetworkThrottle[messageName] then
                NetworkThrottle[messageName] = {
                    lastReceive = 0,
                    count = 0
                }
            end
            
            local throttle = NetworkThrottle[messageName]
            
            if currentTime - throttle.lastReceive < 0.01 then
                throttle.count = throttle.count + 1
                if throttle.count > 10 then
                    return
                end
            else
                throttle.count = 0
            end
            
            throttle.lastReceive = currentTime
            
            return callback(len, ply)
        end)
    end
end

function SetupPhysicsOptimization()
    hook.Add("PhysicsSimulate", "NaiBase_PhysicsOptimization", function(phys, deltatime)
        if not GetConfigValue("physics_optimization") then return end
        
        local ent = phys:GetEntity()
        if not IsValid(ent) then return end
        
        local localPlayer = LocalPlayer()
        if not IsValid(localPlayer) then return end
        
        local distSqr = ent:GetPos():DistToSqr(localPlayer:GetPos())
        
        if distSqr > 10000000 then
            phys:Sleep()
            return true
        end
    end)
end

function SetupMemoryManagement()
    local lastCleanup = 0
    
    hook.Add("Think", "NaiBase_MemoryManagement", function()
        if not GetConfigValue("memory_management") then return end
        
        local currentTime = CurTime()
        local cleanupInterval = GetConfigValue("cleanup_interval", 300)
        
        if currentTime - lastCleanup < cleanupInterval then return end
        lastCleanup = currentTime
        
        PerformMemoryCleanup()
    end)
    
    timer.Create("NaiBase_MemoryCleanup", GetConfigValue("cleanup_interval", 300), 0, function()
        if GetConfigValue("memory_management") then
            PerformMemoryCleanup()
        end
    end)
end

function PerformMemoryCleanup()
    local beforeMem = collectgarbage("count")
    
    for ent, data in pairs(EntityCache) do
        if not IsValid(ent) then
            EntityCache[ent] = nil
        end
    end
    
    for ent, _ in pairs(SoundCache) do
        if not IsValid(ent) then
            SoundCache[ent] = nil
        end
    end
    
    collectgarbage("collect")
    
    local afterMem = collectgarbage("count")
    local freedMem = beforeMem - afterMem
    
    OptimizationStats.memoryFreed = OptimizationStats.memoryFreed + freedMem
    OptimizationStats.lastCleanup = CurTime()
    
    print(string.format("[Performance Optimizer] Memory cleanup: %.2f KB freed", freedMem))
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.MemoryCleanup", freedMem)
    end
end

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

function NaiBase.GetOptimizationStats()
    return {
        entitiesOptimized = OptimizationStats.entitiesOptimized,
        soundsCulled = OptimizationStats.soundsCulled,
        particlesCulled = OptimizationStats.particlesCulled,
        memoryFreed = OptimizationStats.memoryFreed,
        lastCleanup = OptimizationStats.lastCleanup,
        cachedEntities = table.Count(EntityCache),
        cachedSounds = table.Count(SoundCache)
    }
end

concommand.Add("naibase_opti_stats", function()
    print("========================================")
    print("[Performance Optimizer] Statistics")
    print("========================================")
    print("Entities Optimized: " .. OptimizationStats.entitiesOptimized)
    print("Sounds Culled: " .. OptimizationStats.soundsCulled)
    print("Particles Culled: " .. OptimizationStats.particlesCulled)
    print(string.format("Memory Freed: %.2f KB", OptimizationStats.memoryFreed))
    print("Last Cleanup: " .. (CurTime() - OptimizationStats.lastCleanup) .. " seconds ago")
    print("========================================")
    print("Cached Entities: " .. table.Count(EntityCache))
    print("Cached Sounds: " .. table.Count(SoundCache))
    print("========================================")
end)

concommand.Add("naibase_opti_reset", function()
    OptimizationStats = {
        entitiesOptimized = 0,
        soundsCulled = 0,
        particlesCulled = 0,
        memoryFreed = 0,
        lastCleanup = CurTime()
    }
    EntityCache = {}
    SoundCache = {}
    
    print("[Performance Optimizer] Statistics reset")
end)

concommand.Add("naibase_opti_cleanup", function()
    PerformMemoryCleanup()
    print("[Performance Optimizer] Manual cleanup executed")
end)

hook.Add("ShutDown", "NaiBase_OptimizationShutdown", function()
    if timer.Exists("NaiBase_MemoryCleanup") then
        timer.Remove("NaiBase_MemoryCleanup")
    end
    
    EntityCache = {}
    SoundCache = {}
end)

print("[Performance Optimizer] Module loaded successfully")
