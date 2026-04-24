--[[
    NPC Driver Behavior System
    Per-NPC behavior assignment: Combat, Ram, Patrol, Wander, Escort, Flee, Roadkill
    Each NPC can have its own driving style, chosen at assignment time.
]]

if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.lvs_driver = true
NPCPassengers.DriverNPCs = NPCPassengers.DriverNPCs or {}

-- Driver ConVars are created in settings.lua (shared).
-- Only the old LVS-specific convars that have no UI live here.
NPCPassengers.cv_driver_range = NPCPassengers.cv_driver_range or CreateConVar("nai_npc_driver_range", "4000", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Range to detect enemies for driving")
NPCPassengers.cv_driver_engage_distance = NPCPassengers.cv_driver_engage_distance or CreateConVar("nai_npc_driver_engage_distance", "800", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Distance to maintain from enemy")
NPCPassengers.cv_driver_reverse_distance = NPCPassengers.cv_driver_reverse_distance or CreateConVar("nai_npc_driver_reverse_distance", "300", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Distance at which to reverse away")

local driverNPCs = NPCPassengers.DriverNPCs

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior Definitions                                                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

NPCPassengers.DRIVER_BEHAVIORS = {
    { id = "combat",   name = "Combat",        icon = "icon16/shield.png",     desc = "Drive toward enemies and engage at optimal distance" },
    { id = "ram",      name = "Ram Enemies",   icon = "icon16/bomb.png",       desc = "Full speed into enemies — crash into them!" },
    { id = "patrol",   name = "Patrol",        icon = "icon16/arrow_rotate_clockwise.png", desc = "Drive in a loop around the current area" },
    { id = "wander",   name = "Wander",        icon = "icon16/world.png",      desc = "Aimlessly explore the map" },
    { id = "escort",   name = "Escort Player", icon = "icon16/group.png",      desc = "Follow and protect the nearest player" },
    { id = "flee",     name = "Flee",          icon = "icon16/arrow_out.png",  desc = "Run away from all threats" },
    { id = "roadkill", name = "Road Kill",     icon = "icon16/lightning.png",  desc = "Swerve to run over enemies on the ground" },
}

local BEHAVIOR_LOOKUP = {}
for i, b in ipairs(NPCPassengers.DRIVER_BEHAVIORS) do
    BEHAVIOR_LOOKUP[b.id] = i
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Hostile NPC Table                                                        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local hostileClasses = {
    ["npc_combine_s"] = true, ["npc_metropolice"] = true,
    ["npc_hunter"] = true, ["npc_strider"] = true,
    ["npc_helicopter"] = true, ["npc_combinegunship"] = true,
    ["npc_antlion"] = true, ["npc_antlionguard"] = true,
    ["npc_zombie"] = true, ["npc_fastzombie"] = true,
    ["npc_poisonzombie"] = true, ["npc_zombine"] = true,
    ["npc_headcrab"] = true, ["npc_headcrab_fast"] = true,
    ["npc_headcrab_black"] = true, ["npc_manhack"] = true,
    ["npc_turret_floor"] = true, ["npc_rollermine"] = true,
}

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Driver Callout Sounds                                                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local calloutSounds = {
    enemy_spotted = {
        "vo/npc/male01/watchout.wav",
        "vo/npc/male01/lookout.wav",
        "vo/npc/male01/overhere01.wav",
        "vo/npc/male01/overthere01.wav",
        "vo/npc/male01/overthere02.wav",
    },
    engaging = {
        "vo/npc/male01/letsgo01.wav",
        "vo/npc/male01/letsgo02.wav",
        "vo/npc/male01/yeah02.wav",
    },
    fleeing = {
        "vo/npc/male01/runforyourlife01.wav",
        "vo/npc/male01/runforyourlife02.wav",
        "vo/npc/male01/runforyourlife03.wav",
        "vo/npc/male01/gethellout.wav",
    },
    stuck = {
        "vo/npc/male01/uhoh.wav",
        "vo/npc/male01/answer35.wav",
    },
    ramming = {
        "vo/npc/male01/herewegoagain01.wav",
        "vo/npc/male01/charge01.wav",
        "vo/npc/male01/charge02.wav",
    },
    idle = {
        "vo/npc/male01/question01.wav",
        "vo/npc/male01/question02.wav",
        "vo/npc/male01/question06.wav",
    },
}

local hornSounds = {
    "vehicles/v8/vehicle_horn_1.wav",
}

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Utility Functions                                                        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function IsEnemy(ent, npc)
    if not IsValid(ent) then return false end
    if ent == npc then return false end
    if not ent:IsNPC() and not ent:IsPlayer() then return false end
    if ent:Health() <= 0 then return false end

    if NPCPassengers.IsPassenger and NPCPassengers.IsPassenger(ent) then
        return false
    end

    local class = ent:GetClass()
    if hostileClasses[class] then return true end

    if ent:IsNPC() then
        local disp = ent:Disposition(npc)
        if disp == D_HT or disp == D_FR then return true end
    end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ent:IsNPC() then
            local disp = ent:Disposition(ply)
            if disp == D_HT then return true end
        end
    end

    return false
end

local function FindEnemiesInRange(pos, range, npc)
    local enemies = {}
    for _, ent in ipairs(ents.FindInSphere(pos, range)) do
        if IsEnemy(ent, npc) then
            table.insert(enemies, {
                entity = ent,
                distance = pos:Distance(ent:GetPos()),
                position = ent:GetPos()
            })
        end
    end
    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    return enemies
end

local function CalculateSteering(vehicle, targetPos)
    local vehPos = vehicle:GetPos()
    local vehAng = vehicle:GetAngles()

    local toTarget = targetPos - vehPos
    local localDir = vehicle:WorldToLocal(vehPos + toTarget)
    local angleDiff = math.deg(math.atan2(-localDir.y, localDir.x))

    local worldAngleDiff = math.AngleDifference(vehAng.y, (toTarget:Angle()).y)
    if math.abs(angleDiff) > 170 or math.abs(angleDiff) < 10 then
        angleDiff = -worldAngleDiff
    end

    local isFacingTarget = math.abs(angleDiff) < 25
    local steer = math.Clamp(angleDiff / 30, -1, 1)
    if math.abs(angleDiff) > 45 then
        steer = angleDiff > 0 and 1 or -1
    end

    return steer, angleDiff, isFacingTarget
end

local function IsPathBlocked(vehicle, targetPos)
    local startPos = vehicle:GetPos() + Vector(0, 0, 30)
    local dir = (targetPos - startPos):GetNormalized()
    local tr = util.TraceLine({
        start = startPos,
        endpos = startPos + dir * 200,
        filter = vehicle,
        mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and tr.Fraction < 0.8
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Air Vehicle Detection                                                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function IsLVSAirVehicle(vehicle)
    if not IsValid(vehicle) then return false end
    if vehicle.IsAircraft or vehicle.IsPlane or vehicle.IsHelicopter then return true end
    if vehicle.GetIsAirborne and vehicle:GetIsAirborne() then return true end
    local class = vehicle:GetClass() or ""
    if string.find(class, "plane") or string.find(class, "heli") or
       string.find(class, "aircraft") or string.find(class, "jet") or
       string.find(class, "fighter") or string.find(class, "bomber") or
       string.find(class, "gunship") or string.find(class, "vtol") or
       string.find(class, "shuttle") or string.find(class, "laat") or
       string.find(class, "tie") or string.find(class, "xwing") or
       string.find(class, "awing") or string.find(class, "ywing") then
        return true
    end
    if vehicle.SetPitch or vehicle.SetRoll or vehicle.GetAltitude then return true end
    return false
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Vehicle Control Helpers                                                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ApplyLVSControls(vehicle, throttle, steer, handbrake)
    if vehicle.SetThrottle then vehicle:SetThrottle(throttle) end

    if IsLVSAirVehicle(vehicle) then
        if vehicle.SetSteer then
            local ok = pcall(function() vehicle:SetSteer(Vector(0, steer, 0)) end)
            if not ok then pcall(function() vehicle:SetSteer(steer) end) end
        end
    else
        if vehicle.SetSteer then vehicle:SetSteer(steer) end
    end

    if vehicle.SetHandbrake then vehicle:SetHandbrake(handbrake) end
    if vehicle.SetAIThrottle then vehicle:SetAIThrottle(throttle) end
    if vehicle.SetAISteering then vehicle:SetAISteering(steer) end
    if vehicle.SetAI then vehicle:SetAI(true) end

    vehicle._AIThrottle = throttle
    vehicle._AISteering = steer
    vehicle._AIHandbrake = handbrake
    vehicle._npcDriver = true
end

local function ApplySimfphysControls(vehicle, throttle, steer, handbrake)
    if vehicle.SetThrottle then vehicle:SetThrottle(throttle) end
    if vehicle.SetSteering then vehicle:SetSteering(steer)
    elseif vehicle.SetSteer then vehicle:SetSteer(steer) end
    if vehicle.SetHandBrake then vehicle:SetHandBrake(handbrake)
    elseif vehicle.SetHandbrake then vehicle:SetHandbrake(handbrake) end

    vehicle.PressedKeys = vehicle.PressedKeys or {}
    vehicle.PressedKeys["W"] = throttle > 0.1
    vehicle.PressedKeys["S"] = throttle < -0.1
    vehicle.PressedKeys["A"] = steer < -0.1
    vehicle.PressedKeys["D"] = steer > 0.1
    vehicle.PressedKeys["Space"] = handbrake
end

local function ApplyGenericControls(vehicle, throttle, steer, handbrake)
    if vehicle.SetVehicleParams then
        local params = vehicle:GetVehicleParams()
        if params and params.steering then params.steering.degrees = steer * 45 end
    end
    if vehicle.SetSteering then vehicle:SetSteering(steer, 0) end
    if vehicle.SetThrottle then vehicle:SetThrottle(throttle) end
    vehicle._AIThrottle = throttle
    vehicle._AISteering = steer
end

local function StopLVSVehicle(vehicle)
    if not IsValid(vehicle) then return end
    if vehicle.SetThrottle then vehicle:SetThrottle(0) end
    if vehicle.SetSteer then
        if IsLVSAirVehicle(vehicle) then
            pcall(function() vehicle:SetSteer(Vector(0, 0, 0)) end)
        else
            pcall(function() vehicle:SetSteer(0) end)
        end
    end
    if vehicle.SetHandbrake then vehicle:SetHandbrake(true) end
    if vehicle.SetAI then vehicle:SetAI(false) end
    if vehicle.SetAIThrottle then vehicle:SetAIThrottle(0) end
    if vehicle.SetAISteering then vehicle:SetAISteering(0) end
    if vehicle.SetAIGunners then vehicle:SetAIGunners(false) end
    vehicle._AIThrottle = nil
    vehicle._AISteering = nil
    vehicle._AIHandbrake = nil
    vehicle._npcDriver = nil
    vehicle._AIFireInput = nil

    for _, child in ipairs(vehicle:GetChildren()) do
        if IsValid(child) and string.find(child:GetClass() or "", "gunner") then
            child._AIFireInput = false
            child._ai_look_dir = nil
            child._attackStarted = nil
            if child.WeaponsFinish then pcall(child.WeaponsFinish, child) end
            if child.GetActiveWeapon then
                local curWeapon = child:GetActiveWeapon()
                if curWeapon and curWeapon.FinishAttack then pcall(curWeapon.FinishAttack, child) end
            end
        end
    end
end

local function StopVehicle(vehicle, vehicleType)
    if vehicleType == "lvs" then
        StopLVSVehicle(vehicle)
    elseif vehicleType == "simfphys" then
        ApplySimfphysControls(vehicle, 0, 0, true)
    else
        ApplyGenericControls(vehicle, 0, 0)
    end
    vehicle._npcDriver = nil
end

local function ApplyControls(vehicle, vehicleType, throttle, steer, handbrake)
    if vehicleType == "lvs" then
        ApplyLVSControls(vehicle, throttle, steer, handbrake)
    elseif vehicleType == "simfphys" then
        ApplySimfphysControls(vehicle, throttle, steer, handbrake)
    else
        ApplyGenericControls(vehicle, throttle, steer, handbrake)
    end
end

local function GetVehicleType(vehicle)
    if not IsValid(vehicle) then return "unknown" end
    local class = vehicle:GetClass()
    if vehicle.LVS or vehicle.IsLVS or string.find(class, "lvs_") then return "lvs"
    elseif vehicle.IsSimfphyscar or vehicle.IsSimfphys or string.find(class, "gmod_sent_vehicle_fphysics") then return "simfphys"
    elseif vehicle.IsGlideVehicle or string.find(class, "glide_") then return "glide"
    elseif vehicle:IsVehicle() then return "generic" end
    return "unknown"
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Callout & Horn System                                                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function PlayCallout(controller, category)
    if not NPCPassengers.cv_driver_callouts or not NPCPassengers.cv_driver_callouts:GetBool() then return end
    local curTime = CurTime()
    if curTime < (controller.nextCallout or 0) then return end

    local sounds = calloutSounds[category]
    if not sounds or #sounds == 0 then return end

    local npc = controller.npc
    if not IsValid(npc) then return end

    local snd = sounds[math.random(#sounds)]
    npc:EmitSound(snd, 70, 100 + math.random(-10, 10))
    controller.nextCallout = curTime + math.Rand(4, 8)
end

local function HonkHorn(controller)
    if not NPCPassengers.cv_driver_honk or not NPCPassengers.cv_driver_honk:GetBool() then return end
    local curTime = CurTime()
    if curTime < (controller.nextHonk or 0) then return end

    local vehicle = controller.vehicle
    if not IsValid(vehicle) then return end

    local snd = hornSounds[math.random(#hornSounds)]
    vehicle:EmitSound(snd, 80, 100 + math.random(-5, 5))
    controller.nextHonk = curTime + math.Rand(2, 5)
end

local function ToggleHeadlights(controller, on)
    if not NPCPassengers.cv_driver_headlights or not NPCPassengers.cv_driver_headlights:GetBool() then return end
    local vehicle = controller.vehicle
    if not IsValid(vehicle) then return end

    if vehicle.SetLightsEnabled then
        vehicle:SetLightsEnabled(on)
    elseif vehicle.SetHeadlightsEnabled then
        vehicle:SetHeadlightsEnabled(on)
    elseif vehicle.Fire then
        vehicle:Fire(on and "TurnOn" or "TurnOff", "", 0)
    end
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Skill-Adjusted Parameters                                                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function GetSkillParams(controller)
    local skill = (NPCPassengers.cv_driver_skill and NPCPassengers.cv_driver_skill:GetInt() or 50) / 100
    local aggression = (NPCPassengers.cv_driver_aggression and NPCPassengers.cv_driver_aggression:GetInt() or 30) / 100
    local speedMult = NPCPassengers.cv_driver_speed and NPCPassengers.cv_driver_speed:GetFloat() or 0.7

    local steerJitter = (1 - skill) * 0.15
    local reactionDelay = (1 - skill) * 0.4
    local brakingSkill = 0.5 + skill * 0.5
    local cornerSpeed = 0.3 + skill * 0.4

    return {
        speedMult = speedMult,
        skill = skill,
        aggression = aggression,
        steerJitter = steerJitter,
        reactionDelay = reactionDelay,
        brakingSkill = brakingSkill,
        cornerSpeed = cornerSpeed,
    }
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Controller Factory                                                       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function CreateDriverController(npc, vehicle, seat, behaviorId)
    return {
        npc = npc,
        vehicle = vehicle,
        seat = seat,
        vehicleType = GetVehicleType(vehicle),
        behavior = behaviorId or "combat",
        -- Targeting
        currentTarget = nil,
        lastTargetUpdate = 0,
        scanTimer = 0,
        -- Movement
        lastPos = vehicle:GetPos(),
        stuckTime = 0,
        isReversing = false,
        reverseTimer = 0,
        idleTime = 0,
        -- Patrol / Wander
        patrolCenter = vehicle:GetPos(),
        patrolAngle = math.random() * math.pi * 2,
        wanderDest = nil,
        nextWanderPick = 0,
        -- Escort
        escortTarget = nil,
        escortOffset = Vector(math.Rand(-100, 100), math.Rand(-100, 100), 0),
        -- Callouts / Horn
        nextCallout = 0,
        nextHonk = 0,
        lastCalloutCategory = "",
        -- Headlights
        headlightsOn = false,
        -- Ram
        ramTarget = nil,
        ramCooldown = 0,
        -- Roadkill
        roadkillSwerveDir = 0,
    }
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: COMBAT                                                         ║
-- ║  Drive toward enemies, maintain engagement range, reverse if too close     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkCombat(c, dt)
    local vehicle = c.vehicle
    local npc = c.npc
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)

    c.scanTimer = c.scanTimer - dt
    if c.scanTimer <= 0 then
        c.scanTimer = 0.5 + params.reactionDelay
        local range = NPCPassengers.cv_driver_range:GetFloat()
        local enemies = FindEnemiesInRange(vehPos, range, npc)
        if #enemies > 0 then
            if not c.currentTarget or not IsValid(c.currentTarget.entity) then
                PlayCallout(c, "enemy_spotted")
            end
            c.currentTarget = enemies[1]
            c.idleTime = 0
        else
            c.currentTarget = nil
            c.idleTime = c.idleTime + 0.5
        end
    end

    local throttle, steer, handbrake = 0, 0, false

    if c.currentTarget and IsValid(c.currentTarget.entity) then
        local targetPos = c.currentTarget.entity:GetPos()
        local dist = vehPos:Distance(targetPos)
        local engageDist = NPCPassengers.cv_driver_engage_distance:GetFloat()
        local reverseDist = NPCPassengers.cv_driver_reverse_distance:GetFloat()
        local maxSpeed = params.speedMult

        local isFacing
        steer, _, isFacing = CalculateSteering(vehicle, targetPos)
        steer = steer + math.Rand(-params.steerJitter, params.steerJitter)

        -- Stuck check
        local moved = vehPos:Distance(c.lastPos)
        c.stuckTime = moved < 5 and (c.stuckTime + dt) or 0
        c.lastPos = vehPos

        if c.stuckTime > 2 then
            c.isReversing = true
            c.reverseTimer = 1.5
            c.stuckTime = 0
            PlayCallout(c, "stuck")
            HonkHorn(c)
        end

        if c.isReversing then
            c.reverseTimer = c.reverseTimer - dt
            throttle = -0.6
            if c.reverseTimer <= 0 then c.isReversing = false end
        elseif dist < reverseDist then
            throttle = -0.5
        elseif dist < engageDist then
            if not isFacing then
                throttle = 0.15
                steer = steer > 0 and 1 or -1
            else
                throttle = 0
                handbrake = true
            end
            PlayCallout(c, "engaging")
        elseif not isFacing and math.abs(steer) > 0.8 then
            throttle = 0.1
        else
            throttle = isFacing and maxSpeed or (maxSpeed * 0.5)
            if IsPathBlocked(vehicle, targetPos) then
                steer = steer + (steer > 0 and 0.5 or -0.5)
                steer = math.Clamp(steer, -1, 1)
            end
        end
    else
        -- Idle: slow patrol
        if c.idleTime > 3 then
            c.patrolAngle = c.patrolAngle + dt * 10
            steer = math.sin(c.patrolAngle * 0.1) * 0.3
            throttle = 0.15
        else
            handbrake = true
        end
    end

    return throttle, steer, handbrake
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: RAM                                                            ║
-- ║  Full speed into the nearest enemy, no stopping                           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkRam(c, dt)
    local vehicle = c.vehicle
    local npc = c.npc
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)

    c.scanTimer = c.scanTimer - dt
    if c.scanTimer <= 0 then
        c.scanTimer = 0.3
        local range = NPCPassengers.cv_driver_range:GetFloat()
        local enemies = FindEnemiesInRange(vehPos, range, npc)
        if #enemies > 0 then
            if not c.ramTarget or not IsValid(c.ramTarget) then
                PlayCallout(c, "ramming")
                HonkHorn(c)
            end
            c.ramTarget = enemies[1].entity
        else
            c.ramTarget = nil
        end
    end

    local throttle, steer, handbrake = 0, 0, false

    if IsValid(c.ramTarget) then
        local targetPos = c.ramTarget:GetPos()
        steer, _, _ = CalculateSteering(vehicle, targetPos)
        throttle = 1.0 -- Full send
        steer = steer + math.Rand(-params.steerJitter * 0.5, params.steerJitter * 0.5)

        -- Stuck
        local moved = vehPos:Distance(c.lastPos)
        c.stuckTime = moved < 5 and (c.stuckTime + dt) or 0
        c.lastPos = vehPos
        if c.stuckTime > 1.5 then
            c.isReversing = true
            c.reverseTimer = 1.0
            c.stuckTime = 0
        end
        if c.isReversing then
            c.reverseTimer = c.reverseTimer - dt
            throttle = -0.8
            steer = -steer
            if c.reverseTimer <= 0 then c.isReversing = false end
        end
    else
        -- No target, wander aggressively
        c.patrolAngle = c.patrolAngle + dt * 15
        steer = math.sin(c.patrolAngle * 0.15) * 0.4
        throttle = 0.4
    end

    return throttle, steer, handbrake
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: PATROL                                                         ║
-- ║  Drive in a circle around the starting area                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkPatrol(c, dt)
    local vehicle = c.vehicle
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)

    local radius = 1200
    c.patrolAngle = c.patrolAngle + dt * 0.3 * params.speedMult
    local dest = c.patrolCenter + Vector(
        math.cos(c.patrolAngle) * radius,
        math.sin(c.patrolAngle) * radius,
        0
    )

    local steer, angleDiff, isFacing = CalculateSteering(vehicle, dest)
    steer = steer + math.Rand(-params.steerJitter, params.steerJitter)

    local throttle = params.speedMult * params.cornerSpeed
    if math.abs(angleDiff) > 30 then
        throttle = throttle * 0.5
    end

    -- Stuck
    local moved = vehPos:Distance(c.lastPos)
    c.stuckTime = moved < 5 and (c.stuckTime + dt) or 0
    c.lastPos = vehPos
    if c.stuckTime > 2 then
        c.isReversing = true
        c.reverseTimer = 1.2
        c.stuckTime = 0
    end
    if c.isReversing then
        c.reverseTimer = c.reverseTimer - dt
        throttle = -0.5
        steer = -steer
        if c.reverseTimer <= 0 then c.isReversing = false end
    end

    -- Reactively honk if something blocks the path
    if IsPathBlocked(vehicle, dest) then
        HonkHorn(c)
        steer = steer + (steer > 0 and 0.5 or -0.5)
        steer = math.Clamp(steer, -1, 1)
    end

    return throttle, steer, false
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: WANDER                                                         ║
-- ║  Pick random destinations and cruise to them                              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkWander(c, dt)
    local vehicle = c.vehicle
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)
    local curTime = CurTime()

    if not c.wanderDest or curTime > c.nextWanderPick or vehPos:Distance(c.wanderDest) < 200 then
        local wanderDist = NPCPassengers.cv_driver_wander_dist and NPCPassengers.cv_driver_wander_dist:GetFloat() or 2000
        local ang = math.random() * math.pi * 2
        local dist = math.Rand(wanderDist * 0.4, wanderDist)
        c.wanderDest = vehPos + Vector(math.cos(ang) * dist, math.sin(ang) * dist, 0)
        c.nextWanderPick = curTime + math.Rand(15, 40)

        -- Occasional idle chatter
        if math.random() < 0.3 then PlayCallout(c, "idle") end
    end

    local steer, angleDiff, isFacing = CalculateSteering(vehicle, c.wanderDest)
    steer = steer + math.Rand(-params.steerJitter, params.steerJitter)

    local throttle = params.speedMult * 0.5
    if math.abs(angleDiff) > 40 then throttle = throttle * 0.4 end

    -- Stuck
    local moved = vehPos:Distance(c.lastPos)
    c.stuckTime = moved < 5 and (c.stuckTime + dt) or 0
    c.lastPos = vehPos
    if c.stuckTime > 2.5 then
        c.isReversing = true
        c.reverseTimer = 1.5
        c.stuckTime = 0
        c.nextWanderPick = 0 -- Pick a new destination after unstuck
    end
    if c.isReversing then
        c.reverseTimer = c.reverseTimer - dt
        throttle = -0.5
        steer = -steer
        if c.reverseTimer <= 0 then c.isReversing = false end
    end

    if IsPathBlocked(vehicle, c.wanderDest) then
        HonkHorn(c)
        c.nextWanderPick = 0
    end

    return throttle, steer, false
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: ESCORT                                                         ║
-- ║  Follow the nearest player's vehicle, stay close                          ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkEscort(c, dt)
    local vehicle = c.vehicle
    local npc = c.npc
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)
    local curTime = CurTime()

    -- Find escort target (nearest player)
    if not IsValid(c.escortTarget) or curTime > (c.nextEscortRefresh or 0) then
        c.nextEscortRefresh = curTime + 2
        local best, bestDist = nil, math.huge
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local d = vehPos:Distance(ply:GetPos())
                if d < bestDist then best, bestDist = ply, d end
            end
        end
        c.escortTarget = best
    end

    local throttle, steer, handbrake = 0, 0, false

    if IsValid(c.escortTarget) then
        local targetPos = c.escortTarget:GetPos() + c.escortOffset
        local dist = vehPos:Distance(targetPos)

        steer, _, _ = CalculateSteering(vehicle, targetPos)
        steer = steer + math.Rand(-params.steerJitter, params.steerJitter)

        local followDist = 250
        if dist > followDist * 3 then
            throttle = params.speedMult -- Far away, full speed
        elseif dist > followDist then
            throttle = params.speedMult * 0.6
        elseif dist > followDist * 0.5 then
            throttle = params.speedMult * 0.2
        else
            throttle = 0
            handbrake = true
        end

        -- React to enemies threatening escort target
        local range = NPCPassengers.cv_driver_range:GetFloat()
        local enemies = FindEnemiesInRange(vehPos, range, npc)
        if #enemies > 0 and enemies[1].distance < 800 then
            -- Position between enemy and escort target
            local enemyPos = enemies[1].position
            local midpoint = (c.escortTarget:GetPos() + enemyPos) * 0.5
            steer, _, _ = CalculateSteering(vehicle, midpoint)
            throttle = params.speedMult * 0.8
            PlayCallout(c, "enemy_spotted")
            HonkHorn(c)
        end
    else
        -- No player found, idle
        handbrake = true
    end

    -- Stuck
    local moved = vehPos:Distance(c.lastPos)
    c.stuckTime = moved < 5 and throttle > 0.2 and (c.stuckTime + dt) or 0
    c.lastPos = vehPos
    if c.stuckTime > 2 then
        c.isReversing = true
        c.reverseTimer = 1.2
        c.stuckTime = 0
    end
    if c.isReversing then
        c.reverseTimer = c.reverseTimer - dt
        throttle = -0.5
        steer = -steer
        handbrake = false
        if c.reverseTimer <= 0 then c.isReversing = false end
    end

    return throttle, steer, handbrake
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: FLEE                                                           ║
-- ║  Run away from all threats as fast as possible                            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkFlee(c, dt)
    local vehicle = c.vehicle
    local npc = c.npc
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)

    c.scanTimer = c.scanTimer - dt
    if c.scanTimer <= 0 then
        c.scanTimer = 0.4
        local range = NPCPassengers.cv_driver_range:GetFloat()
        local enemies = FindEnemiesInRange(vehPos, range, npc)
        if #enemies > 0 then
            -- Average threat direction
            local threatDir = Vector(0, 0, 0)
            for _, e in ipairs(enemies) do
                threatDir = threatDir + (vehPos - e.position):GetNormalized()
            end
            threatDir:Normalize()
            c.fleeDest = vehPos + threatDir * 3000
            if not c.wasFleeing then
                PlayCallout(c, "fleeing")
                c.wasFleeing = true
            end
        else
            c.fleeDest = nil
            c.wasFleeing = false
        end
    end

    local throttle, steer, handbrake = 0, 0, false

    if c.fleeDest then
        steer, _, _ = CalculateSteering(vehicle, c.fleeDest)
        throttle = params.speedMult * (0.8 + params.aggression * 0.2) -- Near max speed
        steer = steer + math.Rand(-params.steerJitter, params.steerJitter)
    else
        -- Safe, slow cruise
        c.patrolAngle = c.patrolAngle + dt * 5
        steer = math.sin(c.patrolAngle * 0.08) * 0.2
        throttle = 0.1
    end

    -- Stuck
    local moved = vehPos:Distance(c.lastPos)
    c.stuckTime = moved < 5 and throttle > 0.2 and (c.stuckTime + dt) or 0
    c.lastPos = vehPos
    if c.stuckTime > 1.5 then
        c.isReversing = true
        c.reverseTimer = 1.0
        c.stuckTime = 0
    end
    if c.isReversing then
        c.reverseTimer = c.reverseTimer - dt
        throttle = -0.7
        steer = -steer
        if c.reverseTimer <= 0 then c.isReversing = false end
    end

    return throttle, steer, handbrake
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior: ROADKILL                                                       ║
-- ║  Actively swerve to run over enemies on the ground                        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function ThinkRoadkill(c, dt)
    local vehicle = c.vehicle
    local npc = c.npc
    local vehPos = vehicle:GetPos()
    local params = GetSkillParams(c)

    c.scanTimer = c.scanTimer - dt
    if c.scanTimer <= 0 then
        c.scanTimer = 0.25
        local range = NPCPassengers.cv_driver_range:GetFloat() * 0.7
        local enemies = FindEnemiesInRange(vehPos, range, npc)

        -- Prefer ground-level targets (not flying)
        local best = nil
        for _, e in ipairs(enemies) do
            if IsValid(e.entity) then
                local heightDiff = math.abs(e.position.z - vehPos.z)
                if heightDiff < 150 then
                    best = e
                    break
                end
            end
        end
        if best then
            if c.ramTarget ~= best.entity then
                PlayCallout(c, "ramming")
                HonkHorn(c)
            end
            c.ramTarget = best.entity
        else
            c.ramTarget = nil
        end
    end

    local throttle, steer, handbrake = 0, 0, false

    if IsValid(c.ramTarget) then
        local targetPos = c.ramTarget:GetPos()
        -- Predict target movement for interception
        local targetVel = c.ramTarget:GetVelocity()
        local timeToReach = vehPos:Distance(targetPos) / math.max(vehicle:GetVelocity():Length(), 200)
        local predictedPos = targetPos + targetVel * timeToReach * 0.6

        steer, _, _ = CalculateSteering(vehicle, predictedPos)
        throttle = 0.9 + params.aggression * 0.1
        steer = steer + math.Rand(-params.steerJitter * 0.3, params.steerJitter * 0.3)
    else
        -- Cruise and look for targets
        c.patrolAngle = c.patrolAngle + dt * 8
        steer = math.sin(c.patrolAngle * 0.12) * 0.3
        throttle = params.speedMult * 0.4
    end

    -- Stuck
    local moved = vehPos:Distance(c.lastPos)
    c.stuckTime = moved < 5 and throttle > 0.2 and (c.stuckTime + dt) or 0
    c.lastPos = vehPos
    if c.stuckTime > 1.5 then
        c.isReversing = true
        c.reverseTimer = 1.0
        c.stuckTime = 0
    end
    if c.isReversing then
        c.reverseTimer = c.reverseTimer - dt
        throttle = -0.7
        steer = -steer
        if c.reverseTimer <= 0 then c.isReversing = false end
    end

    return throttle, steer, handbrake
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Behavior Dispatcher                                                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local behaviorThinkFuncs = {
    combat   = ThinkCombat,
    ram      = ThinkRam,
    patrol   = ThinkPatrol,
    wander   = ThinkWander,
    escort   = ThinkEscort,
    flee     = ThinkFlee,
    roadkill = ThinkRoadkill,
}

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Main Think                                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local function DriverThink(controller, dt)
    if not IsValid(controller.npc) or not IsValid(controller.vehicle) then return false end

    if controller.npc:Health() <= 0 then
        StopVehicle(controller.vehicle, controller.vehicleType)
        return false
    end

    if not NPCPassengers.cv_driver_enabled:GetBool() then return true end

    local thinkFn = behaviorThinkFuncs[controller.behavior]
    if not thinkFn then return true end

    local throttle, steer, handbrake = thinkFn(controller, dt)

    -- Headlights: turn on when moving
    local shouldLight = math.abs(throttle) > 0.1
    if shouldLight ~= controller.headlightsOn then
        controller.headlightsOn = shouldLight
        ToggleHeadlights(controller, shouldLight)
    end

    ApplyControls(controller.vehicle, controller.vehicleType, throttle, steer, handbrake)
    return true
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Public API                                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

function NPCPassengers.RegisterDriverNPC(npc, vehicle, seat, behaviorId)
    if not IsValid(npc) or not IsValid(vehicle) then return end

    local isDriverSeat = false
    if IsValid(seat) then
        if seat == vehicle then isDriverSeat = true
        elseif vehicle.GetDriverSeat and vehicle:GetDriverSeat() == seat then isDriverSeat = true
        elseif seat.GetVehicle and seat:GetVehicle() == vehicle then isDriverSeat = true
        elseif seat.lvsGetPodIndex and seat:lvsGetPodIndex() == 1 then isDriverSeat = true
        end
    end
    if seat == vehicle then isDriverSeat = true end
    if not isDriverSeat then return end

    local npcId = npc:EntIndex()
    if driverNPCs[npcId] then return end

    local controller = CreateDriverController(npc, vehicle, seat, behaviorId)
    driverNPCs[npcId] = controller

    -- Turn on headlights on spawn
    ToggleHeadlights(controller, true)
    controller.headlightsOn = true

    return true
end

function NPCPassengers.UnregisterDriverNPC(npc)
    if not IsValid(npc) then return end
    local npcId = npc:EntIndex()
    local controller = driverNPCs[npcId]
    if controller then
        ToggleHeadlights(controller, false)
        StopVehicle(controller.vehicle, controller.vehicleType)
        driverNPCs[npcId] = nil
    end
end

function NPCPassengers.IsDriverNPC(npc)
    if not IsValid(npc) then return false end
    return driverNPCs[npc:EntIndex()] ~= nil
end

function NPCPassengers.GetDriverBehavior(npc)
    if not IsValid(npc) then return nil end
    local c = driverNPCs[npc:EntIndex()]
    return c and c.behavior or nil
end

function NPCPassengers.SetDriverBehavior(npc, behaviorId)
    if not IsValid(npc) then return end
    local c = driverNPCs[npc:EntIndex()]
    if c and behaviorThinkFuncs[behaviorId] then
        c.behavior = behaviorId
        -- Reset state for new behavior
        c.currentTarget = nil
        c.ramTarget = nil
        c.wanderDest = nil
        c.fleeDest = nil
        c.scanTimer = 0
        c.stuckTime = 0
        c.isReversing = false
        c.patrolCenter = c.vehicle:GetPos()
        c.patrolAngle = math.random() * math.pi * 2
    end
end

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Hooks                                                                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

local lastThink = CurTime()
hook.Add("Think", "NPCPassengers_DriverThink", function()
    if not NPCPassengers.cv_driver_enabled:GetBool() then return end

    local curTime = CurTime()
    local dt = curTime - lastThink
    lastThink = curTime

    local toRemove = {}
    for npcId, controller in pairs(driverNPCs) do
        if not DriverThink(controller, dt) then
            table.insert(toRemove, npcId)
        end
    end
    for _, npcId in ipairs(toRemove) do
        driverNPCs[npcId] = nil
    end
end)

hook.Add("EntityRemoved", "NPCPassengers_DriverCleanup", function(ent)
    if ent:IsNPC() then
        local npcId = ent:EntIndex()
        local controller = driverNPCs[npcId]
        if controller then
            StopVehicle(controller.vehicle, controller.vehicleType)
            driverNPCs[npcId] = nil
        end
    end
end)

hook.Add("OnNPCKilled", "NPCPassengers_DriverDeathCleanup", function(npc)
    if not IsValid(npc) then return end
    local npcId = npc:EntIndex()
    local controller = driverNPCs[npcId]
    if controller then
        StopVehicle(controller.vehicle, controller.vehicleType)
        driverNPCs[npcId] = nil
    end
end)

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Net: Per-NPC Behavior Assignment                                         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

util.AddNetworkString("NPCPassengers_SetDriverBehavior")

net.Receive("NPCPassengers_SetDriverBehavior", function(len, ply)
    if not IsValid(ply) then return end
    local npc = net.ReadEntity()
    local behaviorId = net.ReadString()

    if not IsValid(npc) then return end

    local c = driverNPCs[npc:EntIndex()]
    if c then
        NPCPassengers.SetDriverBehavior(npc, behaviorId)
        ply:ChatPrint("[NPC Driver] Behavior changed to: " .. behaviorId)
    end
end)
