--[[
    VJ Base SNPC Compatibility
    --------------------------
    Provides proper passenger support for VJ Base SNPCs (DrVrej's framework).

    VJ NPCs have their own AI loop on top of GMod's NPC system. Standard freeze
    techniques (m_bNPCFreeze, SCHED_NPC_FREEZE) don't fully stop them — VJ keeps
    running custom schedules, idle behavior, touch handlers, etc.

    The proper way to halt a VJ SNPC is:
      - Set ent.VJ_IsBeingControlled = true (skips most VJ AI checks)
      - Call ent:SetState(VJ_STATE_FREEZE) (stops tasks/schedules)
      - Set ent.vjstopschedule / vjstopanim (legacy fallback)

    On detach, all of these must be restored to their previous values so the
    NPC resumes normal VJ behavior.
]]

NPCPassengers = NPCPassengers or {}
NPCPassengers.VJBase = NPCPassengers.VJBase or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.vj_base = true

local VJBase = NPCPassengers.VJBase

-- Detection ------------------------------------------------------------

-- Returns true if the entity is a VJ Base SNPC
function VJBase.IsVJSNPC(ent)
    if not IsValid(ent) then return false end
    if not ent:IsNPC() then return false end
    return ent.IsVJBaseSNPC == true
        or ent.IsVJBaseSNPC_Human == true
        or ent.IsVJBaseSNPC_Animal == true
        or ent.IsVJBaseSNPC_Tank == true
end

-- Detects VJ Base "vehicle" SNPCs (tanks, gunships, etc) which we don't want
-- to treat as passengers since they're vehicles themselves.
function VJBase.IsVJVehicleEntity(ent)
    if not IsValid(ent) then return false end
    return ent.VJ_ID_Vehicle == true or ent.IsVJBaseSNPC_Tank == true
end

-- State save / restore -------------------------------------------------

-- Snapshot the relevant VJ state before we override it. Returns a table
-- that should be passed back to RestoreState() on detach.
function VJBase.SaveState(npc)
    if not VJBase.IsVJSNPC(npc) then return nil end

    local state = {
        IsBeingControlled  = npc.VJ_IsBeingControlled,
        IsBeingControlledT = npc.VJ_IsBeingControlled_Tool,
        StopSchedule       = npc.vjstopschedule,
        StopAnim           = npc.vjstopanim,
        AIState            = npc.AIState,
        Behavior           = npc.Behavior,
        DisableWandering   = npc.DisableWandering,
    }
    return state
end

-- Freeze a VJ SNPC for passenger use. Stops VJ AI loop, idle behavior,
-- and animation overrides while keeping the NPC alive and responsive
-- to direct calls (sequence playback, etc).
function VJBase.FreezeForPassenger(npc)
    if not VJBase.IsVJSNPC(npc) then return end

    -- Primary: tell VJ this NPC is under external control. VJ AI checks
    -- this flag everywhere and skips its update loop when set.
    npc.VJ_IsBeingControlled = true
    npc.VJ_IsBeingControlled_Tool = true

    -- Secondary: legacy stop flags (older VJ versions)
    npc.vjstopschedule = true
    npc.vjstopanim = true
    npc.DisableWandering = true

    -- Stop any currently running VJ schedule / animation
    if npc.SetVJStopSchedule then
        local ok = pcall(npc.SetVJStopSchedule, npc)
        if not ok and npc.VJ_TASK_FACE_X then
            -- Fallback: clear via TaskComplete if SetVJStopSchedule errors
            pcall(function() npc:TaskComplete() end)
        end
    end
    if npc.StopAnimation then
        pcall(npc.StopAnimation, npc)
    end

    -- Set VJ state to FREEZE so internal task scheduler halts.
    -- VJ_STATE_FREEZE is the canonical frozen state for VJ NPCs.
    if npc.SetState and VJ_STATE_FREEZE then
        pcall(npc.SetState, npc, VJ_STATE_FREEZE)
    end

    -- Clear any active VJ enemy/target so they don't try to act on it
    if npc.VJ_TaskTarget then npc.VJ_TaskTarget = NULL end
    if npc.VJ_TheController then npc.VJ_TheController = NULL end

    -- Stop medic / healing routines if active
    if npc.MedicData then
        npc.MedicData.Status = nil
        npc.MedicData.Target = NULL
    end

    -- Stop any controller-style behavior (e.g. boss controllers)
    if npc.VJ_ST_HoldingPosition ~= nil then
        npc.VJ_ST_HoldingPosition = false
    end
end

-- Restore VJ state when the NPC detaches and resumes normal AI.
function VJBase.RestoreState(npc, savedState)
    if not VJBase.IsVJSNPC(npc) then return end

    if savedState then
        npc.VJ_IsBeingControlled = savedState.IsBeingControlled or false
        npc.VJ_IsBeingControlled_Tool = savedState.IsBeingControlledT or false
        npc.vjstopschedule = savedState.StopSchedule or false
        npc.vjstopanim = savedState.StopAnim or false
        npc.DisableWandering = savedState.DisableWandering or false
    else
        npc.VJ_IsBeingControlled = false
        npc.VJ_IsBeingControlled_Tool = false
        npc.vjstopschedule = false
        npc.vjstopanim = false
        npc.DisableWandering = false
    end

    -- Reset state back to NONE so VJ AI resumes
    if npc.SetState and VJ_STATE_NONE then
        pcall(npc.SetState, npc, VJ_STATE_NONE)
    end

    -- Re-trigger VJ's relationship cache so it knows about current entities
    if npc.DoCacheClasses then
        pcall(npc.DoCacheClasses, npc)
    end
end

-- Friendly checks ------------------------------------------------------

-- VJ uses VJ_NPC_Class (table of class strings) for faction matching, not
-- GMod's Disposition system. Two VJ NPCs sharing any class string are allies.
function VJBase.AreVJAllies(npc1, npc2)
    if not (VJBase.IsVJSNPC(npc1) and VJBase.IsVJSNPC(npc2)) then return false end

    local c1 = npc1.VJ_NPC_Class
    local c2 = npc2.VJ_NPC_Class
    if not (istable(c1) and istable(c2)) then return false end

    for _, class1 in ipairs(c1) do
        for _, class2 in ipairs(c2) do
            if class1 == class2 then return true end
        end
    end
    return false
end

-- Player-NPC friendly check via VJ class system. Players in CLASS_PLAYER_ALLY
-- are allied with player-friendly VJ classes.
function VJBase.IsFriendlyToPlayer(npc, ply)
    if not VJBase.IsVJSNPC(npc) then return nil end -- nil = let caller decide
    if not IsValid(ply) or not ply:IsPlayer() then return nil end

    local plyClass = ply.VJ_NPC_Class
    local npcClass = npc.VJ_NPC_Class

    if not (istable(plyClass) and istable(npcClass)) then return nil end

    for _, c1 in ipairs(plyClass) do
        for _, c2 in ipairs(npcClass) do
            if c1 == c2 then return true end
        end
    end

    -- Check VJ behavior — passive NPCs aren't hostile to players
    if npc.Behavior == VJ_BEHAVIOR_PASSIVE or npc.Behavior == VJ_BEHAVIOR_PASSIVE_NATURE then
        return true
    end

    return false
end

-- Damage handling ------------------------------------------------------

-- VJ SNPCs sometimes ignore TakeDamageInfo in odd states. Make sure damage
-- gets through when killing them due to vehicle destruction.
function VJBase.ForceKill(npc, attacker, inflictor, dmgType)
    if not VJBase.IsVJSNPC(npc) then return false end
    if npc:Health() <= 0 then return true end

    -- VJ has its own death handler — temporarily clear control flag so it
    -- processes the damage normally
    npc.VJ_IsBeingControlled = false

    local dmg = DamageInfo()
    dmg:SetDamage(npc:Health() + 9999)
    dmg:SetDamageType(dmgType or DMG_BLAST)
    dmg:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
    dmg:SetInflictor(IsValid(inflictor) and inflictor or game.GetWorld())
    npc:TakeDamageInfo(dmg)
    return true
end

-- Sit pose helper ------------------------------------------------------

-- VJ SNPCs override animations every tick via their Think loop. Force the
-- sit sequence to stick by also setting it through VJ's animation override
-- system (when available).
function VJBase.ApplySitSequence(npc, sitSeq)
    if not VJBase.IsVJSNPC(npc) then return end
    if not sitSeq or sitSeq < 0 then return end

    -- VJ stores last played anim — overriding it prevents VJ from replaying
    -- its own idle anim over our sit pose.
    if npc.AnimTbl_IdleStand then
        npc.VJ_OldAnimTbl_IdleStand = npc.AnimTbl_IdleStand
        npc.AnimTbl_IdleStand = {sitSeq}
    end

    -- Lock playback rate to 0 (sit pose is held statically)
    npc:SetPlaybackRate(0)

    -- Tell VJ not to interrupt this animation
    if npc.PlayingAnim_StopFunc then
        npc.PlayingAnim_StopFunc = function() end
    end
end

function VJBase.RestoreAnimTable(npc)
    if not VJBase.IsVJSNPC(npc) then return end

    if npc.VJ_OldAnimTbl_IdleStand then
        npc.AnimTbl_IdleStand = npc.VJ_OldAnimTbl_IdleStand
        npc.VJ_OldAnimTbl_IdleStand = nil
    end

    if npc.PlayingAnim_StopFunc then
        npc.PlayingAnim_StopFunc = nil
    end
end
