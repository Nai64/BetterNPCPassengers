if SERVER then return end
if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

local MODULE_NAME = "Audio Manager"
local MODULE_VERSION = "1.0.0"

local AudioConfig = {
    masterVolume = 1.0,
    musicVolume = 1.0,
    ambientVolume = 1.0,
    voiceVolume = 1.0,
    effectsVolume = 1.0,
    maxSounds = 128,
    currentSounds = 0,
    soundCache = {},
    mutedSounds = {}
}

local SoundHistory = {}
local SpatialSounds = {}

hook.Add("InitPostEntity", "NaiBase_AudioManagerInit", function()
    timer.Simple(3, function()
        if not NaiBase then
            print("[Audio Manager] Warning: NaiBase not loaded, running standalone")
            return
        end
        
        NaiBase.RegisterModule(MODULE_NAME, {
            version = MODULE_VERSION,
            author = "Nai's Base Team",
            description = "Advanced audio control and 3D sound optimization",
            icon = "icon16/sound.png",
            init = function()
                InitializeAudioManager()
            end
        })
        
        RegisterAudioConfigs()
    end)
end)

function RegisterAudioConfigs()
    if not NaiBase or not NaiBase.RegisterConfig then return end
    
    NaiBase.RegisterConfig(MODULE_NAME, "master_volume", {
        displayName = "Master Volume",
        description = "Global volume multiplier",
        category = "Volume",
        valueType = "number",
        default = 1.0,
        min = 0.0,
        max = 2.0
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "distance_culling", {
        displayName = "Distance Sound Culling",
        description = "Stop distant sounds automatically",
        category = "Optimization",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "cull_distance", {
        displayName = "Cull Distance",
        description = "Distance in units to cull sounds",
        category = "Optimization",
        valueType = "number",
        default = 4000,
        min = 1000,
        max = 10000
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "max_simultaneous", {
        displayName = "Max Simultaneous Sounds",
        description = "Maximum number of sounds playing at once",
        category = "Optimization",
        valueType = "number",
        default = 64,
        min = 16,
        max = 256
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "doppler_effect", {
        displayName = "Doppler Effect",
        description = "Enable doppler shift for moving sounds",
        category = "3D Audio",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "reverb_enabled", {
        displayName = "Environmental Reverb",
        description = "Apply reverb based on environment",
        category = "3D Audio",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "auto_mute_spam", {
        displayName = "Auto-Mute Spam",
        description = "Automatically mute repeatedly spammed sounds",
        category = "Protection",
        valueType = "boolean",
        default = true
    })
    
    NaiBase.RegisterConfig(MODULE_NAME, "spam_threshold", {
        displayName = "Spam Threshold",
        description = "Sound plays per second to consider spam",
        category = "Protection",
        valueType = "number",
        default = 5,
        min = 2,
        max = 20
    })
end

function InitializeAudioManager()
    print("[Audio Manager] Initializing audio systems...")
    
    SetupVolumeControl()
    SetupDistanceCulling()
    SetupSoundLimiting()
    SetupSpamProtection()
    Setup3DAudio()
    
    print("[Audio Manager] Audio systems active")
    
    if NaiBase then
        NaiBase.TriggerEvent("NaiBase.AudioManagerReady")
    end
end

function SetupVolumeControl()
    hook.Add("EntityEmitSound", "NaiBase_VolumeControl", function(data)
        local masterVol = GetConfigValue("master_volume", 1.0)
        
        if data.Volume then
            data.Volume = data.Volume * masterVol
        end
        
        return true
    end)
end

function SetupDistanceCulling()
    hook.Add("EntityEmitSound", "NaiBase_DistanceCulling", function(data)
        if not GetConfigValue("distance_culling") then return end
        
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        if data.Pos then
            local dist = ply:GetPos():Distance(data.Pos)
            local cullDist = GetConfigValue("cull_distance", 4000)
            
            if dist > cullDist then
                return false
            end
            
            local distFactor = 1 - (dist / cullDist)
            if data.Volume then
                data.Volume = data.Volume * distFactor
            end
        end
        
        return true
    end)
end

function SetupSoundLimiting()
    local activeSounds = {}
    
    hook.Add("EntityEmitSound", "NaiBase_SoundLimiting", function(data)
        local maxSounds = GetConfigValue("max_simultaneous", 64)
        
        table.insert(activeSounds, {
            time = CurTime(),
            sound = data.SoundName
        })
        
        for i = #activeSounds, 1, -1 do
            if CurTime() - activeSounds[i].time > 5 then
                table.remove(activeSounds, i)
            end
        end
        
        if #activeSounds > maxSounds then
            return false
        end
        
        AudioConfig.currentSounds = #activeSounds
        return true
    end)
end

function SetupSpamProtection()
    local soundCounts = {}
    local lastCleanup = 0
    
    hook.Add("EntityEmitSound", "NaiBase_SpamProtection", function(data)
        if not GetConfigValue("auto_mute_spam") then return end
        
        local soundName = data.SoundName
        
        if AudioConfig.mutedSounds[soundName] then
            return false
        end
        
        if not soundCounts[soundName] then
            soundCounts[soundName] = {
                count = 0,
                lastTime = 0,
                muted = false
            }
        end
        
        local currentTime = CurTime()
        local soundData = soundCounts[soundName]
        
        if currentTime - soundData.lastTime < 1 then
            soundData.count = soundData.count + 1
        else
            soundData.count = 1
        end
        
        soundData.lastTime = currentTime
        
        local threshold = GetConfigValue("spam_threshold", 5)
        if soundData.count > threshold then
            AudioConfig.mutedSounds[soundName] = true
            print("[Audio Manager] Muted spam sound: " .. soundName)
            
            timer.Simple(30, function()
                AudioConfig.mutedSounds[soundName] = nil
                print("[Audio Manager] Unmuted: " .. soundName)
            end)
            
            return false
        end
        
        if currentTime - lastCleanup > 10 then
            for name, data in pairs(soundCounts) do
                if currentTime - data.lastTime > 10 then
                    soundCounts[name] = nil
                end
            end
            lastCleanup = currentTime
        end
        
        return true
    end)
end

function Setup3DAudio()
    hook.Add("EntityEmitSound", "NaiBase_3DAudio", function(data)
        if not GetConfigValue("doppler_effect") then return end
        
        if data.Entity and IsValid(data.Entity) then
            local ent = data.Entity
            local vel = ent:GetVelocity()
            
            if vel:Length() > 100 then
                local ply = LocalPlayer()
                if IsValid(ply) then
                    local toPlayer = (ply:GetPos() - ent:GetPos()):GetNormalized()
                    local velToward = vel:Dot(toPlayer)
                    
                    local dopplerShift = 1 + (velToward / 10000)
                    dopplerShift = math.Clamp(dopplerShift, 0.8, 1.2)
                    
                    if data.Pitch then
                        data.Pitch = data.Pitch * dopplerShift
                    end
                end
            end
        end
        
        return true
    end)
end

function NaiBase.GetAudioStats()
    return {
        currentSounds = AudioConfig.currentSounds,
        maxSounds = GetConfigValue("max_simultaneous", 64),
        mutedSounds = table.Count(AudioConfig.mutedSounds),
        masterVolume = GetConfigValue("master_volume", 1.0)
    }
end

function NaiBase.MuteSound(soundName)
    AudioConfig.mutedSounds[soundName] = true
    print("[Audio Manager] Manually muted: " .. soundName)
end

function NaiBase.UnmuteSound(soundName)
    AudioConfig.mutedSounds[soundName] = nil
    print("[Audio Manager] Manually unmuted: " .. soundName)
end

function NaiBase.UnmuteAllSounds()
    AudioConfig.mutedSounds = {}
    print("[Audio Manager] All sounds unmuted")
end

function GetConfigValue(key, default)
    if NaiBase and NaiBase.GetConfig then
        return NaiBase.GetConfig(key, default, MODULE_NAME)
    end
    return default
end

concommand.Add("naibase_audio_stats", function()
    print("========================================")
    print("[Audio Manager] Statistics")
    print("========================================")
    print("Active Sounds: " .. AudioConfig.currentSounds)
    print("Max Simultaneous: " .. GetConfigValue("max_simultaneous", 64))
    print("Muted Sounds: " .. table.Count(AudioConfig.mutedSounds))
    print("Master Volume: " .. GetConfigValue("master_volume", 1.0))
    print("========================================")
end)

concommand.Add("naibase_audio_muted", function()
    print("========================================")
    print("[Audio Manager] Muted Sounds")
    print("========================================")
    
    local count = 0
    for soundName, _ in pairs(AudioConfig.mutedSounds) do
        count = count + 1
        print(count .. ". " .. soundName)
    end
    
    if count == 0 then
        print("No sounds are currently muted")
    end
    print("========================================")
end)

concommand.Add("naibase_audio_unmute_all", function()
    NaiBase.UnmuteAllSounds()
end)

print("[Audio Manager] Module loaded successfully")
