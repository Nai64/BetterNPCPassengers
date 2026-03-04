if SERVER then return end

_G.NaiBaseKillswitch = _G.NaiBaseKillswitch or false

concommand.Add("naibase_kill", function(ply, cmd, args)
    local value = tonumber(args[1] or "0")
    
    if value == 1 then
        _G.NaiBaseKillswitch = true
        print("[Nai's Base] KILLSWITCH ACTIVATED - All features disabled")
        
        hook.Remove("InitPostEntity", "NaiBase_AdvancedInit")
        hook.Remove("InitPostEntity", "NaiBase_AudioManagerInit")
        hook.Remove("InitPostEntity", "NaiBase_BenchmarkInit")
        hook.Remove("InitPostEntity", "NaiBase_ConsoleLoggerInit")
        hook.Remove("InitPostEntity", "NaiBase_InitGUI")
        hook.Remove("InitPostEntity", "NaiBase_OptimizationInit")
        hook.Remove("InitPostEntity", "NaiBase_ResourceMonitorInit")
        
        hook.Remove("Think", "NaiBase_ResourceTracking")
        hook.Remove("Think", "NaiBase_OptimizationThink")
        hook.Remove("Think", "NaiBase_AdvancedThink")
        hook.Remove("Think", "NaiBase_BenchmarkThink")
        
        hook.Remove("HUDPaint", "NaiBase_ResourceOverlay")
        hook.Remove("HUDPaint", "NaiBase_BenchmarkOverlay")
        
        hook.Remove("EntityEmitSound", "NaiBase_AudioManager")
        
        timer.Remove("NaiBase_AutoCleanup")
        timer.Remove("NaiBase_NetworkCheck")
        timer.Remove("NaiBase_EntityProfiler")
        
        if NaiBaseMainMenu and IsValid(NaiBaseMainMenu) then
            NaiBaseMainMenu:Close()
        end
        
    elseif value == 0 then
        _G.NaiBaseKillswitch = false
        print("[Nai's Base] Killswitch deactivated - Please restart map or game to re-enable features")
    else
        print("[Nai's Base] Usage: naibase_kill <0|1>")
        print("  1 = Disable all features")
        print("  0 = Deactivate killswitch (requires restart)")
    end
end)

function NaiBase_IsKillswitchActive()
    return _G.NaiBaseKillswitch == true
end

print("[Nai's Base] Killswitch system loaded")
