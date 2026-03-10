--[[
    NPC Passenger Auto-Drive System
    When an NPC is in the driver seat, the vehicle automatically drives toward enemies
]]

if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.lvs_driver = true
NPCPassengers.DriverNPCs = NPCPassengers.DriverNPCs or {}

-- Configuration convars
NPCPassengers.cv_driver_enabled = CreateConVar("nai_npc_driver_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable NPC auto-driving")
NPCPassengers.cv_driver_range = CreateConVar("nai_npc_driver_range", "4000", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Range to detect enemies for driving")
NPCPassengers.cv_driver_engage_distance = CreateConVar("nai_npc_driver_engage_distance", "800", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Distance to maintain from enemy")
NPCPassengers.cv_driver_speed = CreateConVar("nai_npc_driver_speed", "0.7", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Throttle amount (0-1)")
NPCPassengers.cv_driver_reverse_distance = CreateConVar("nai_npc_driver_reverse_distance", "300", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Distance at which to reverse away")

local driverNPCs = NPCPassengers.DriverNPCs

-- Known hostile NPC classes
local hostileClasses = {
    ["npc_combine_s"] = true,
    ["npc_metropolice"] = true,
    ["npc_hunter"] = true,
    ["npc_strider"] = true,
    ["npc_helicopter"] = true,
    ["npc_combinegunship"] = true,
    ["npc_antlion"] = true,
    ["npc_antlionguard"] = true,
    ["npc_zombie"] = true,
    ["npc_fastzombie"] = true,
    ["npc_poisonzombie"] = true,
    ["npc_zombine"] = true,
    ["npc_headcrab"] = true,
    ["npc_headcrab_fast"] = true,
    ["npc_headcrab_black"] = true,
    ["npc_manhack"] = true,
    ["npc_turret_floor"] = true,
    ["npc_rollermine"] = true,
}

--[[
    Check if an entity is an enemy
]]
local function IsEnemy(ent, npc)
    if not IsValid(ent) then return false end
    if ent == npc then return false end
    if not ent:IsNPC() and not ent:IsPlayer() then return false end
    if ent:Health() <= 0 then return false end
    
    -- Check if it's a passenger (don't target other passengers)
    if NPCPassengers.IsPassenger and NPCPassengers.IsPassenger(ent) then
        return false
    end
    
    -- Check for hostile NPC classes
    local class = ent:GetClass()
    if hostileClasses[class] then
        return true
    end
    
    -- Check disposition
    if ent:IsNPC() then
        local disp = ent:Disposition(npc)
        if disp == D_HT or disp == D_FR then
            return true
        end
    end
    
    -- Check if hostile to players
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ent:IsNPC() then
            local disp = ent:Disposition(ply)
            if disp == D_HT then
                return true
            end
        end
    end
    
    return false
end

--[[
    Find enemies in range
]]
local function FindEnemiesInRange(pos, range, npc)
    local enemies = {}
    
    for _, ent in ipairs(ents.GetAll()) do
        if IsEnemy(ent, npc) then
            local dist = pos:Distance(ent:GetPos())
            if dist <= range then
                table.insert(enemies, {
                    entity = ent,
                    distance = dist,
                    position = ent:GetPos()
                })
            end
        end
    end
    
    -- Sort by distance
    table.sort(enemies, function(a, b)
        return a.distance < b.distance
    end)
    
    return enemies
end

--[[
    Calculate steering to face a target
    Returns: steer (-1 to 1), angleDiff (degrees), isFacingTarget (bool)
]]
local function CalculateSteering(vehicle, targetPos)
    local vehPos = vehicle:GetPos()
    local vehAng = vehicle:GetAngles()
    
    -- Get direction to target in local space (much more reliable)
    local toTarget = targetPos - vehPos
    local localDir = vehicle:WorldToLocal(vehPos + toTarget) -- Local direction
    
    -- Calculate angle using local coordinates
    -- In Source engine: X is forward, Y is left, Z is up
    local angleDiff = math.deg(math.atan2(-localDir.y, localDir.x))
    
    -- Also calculate using world angles as backup
    local worldAngleDiff = math.AngleDifference(vehAng.y, (toTarget:Angle()).y)
    
    -- Use the more stable calculation
    if math.abs(angleDiff) > 170 or math.abs(angleDiff) < 10 then
        -- Use world calculation for edge cases
        angleDiff = -worldAngleDiff
    end
    
    -- Check if roughly facing target
    local isFacingTarget = math.abs(angleDiff) < 25
    
    -- Convert to steering input (-1 to 1)
    -- Use a tighter angle for more responsive steering
    local steer = math.Clamp(angleDiff / 30, -1, 1)
    
    -- Make steering more aggressive when angle is large
    if math.abs(angleDiff) > 45 then
        steer = angleDiff > 0 and 1 or -1
    end
    
    return steer, angleDiff, isFacingTarget
end

--[[
    Check if path to target is blocked
]]
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

--[[
    Check if an LVS vehicle is an air vehicle (plane/helicopter)
]]
local function IsLVSAirVehicle(vehicle)
    if not IsValid(vehicle) then return false end
    
    -- Check for common air vehicle indicators
    if vehicle.IsAircraft then return true end
    if vehicle.IsPlane then return true end  
    if vehicle.IsHelicopter then return true end
    if vehicle.GetIsAirborne and vehicle:GetIsAirborne() then return true end
    
    -- Check class name for air vehicle patterns
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
    
    -- Check if SetSteer expects a vector (test by checking for flight-related methods)
    if vehicle.SetPitch or vehicle.SetRoll or vehicle.GetAltitude then
        return true
    end
    
    return false
end

--[[
    Apply vehicle controls for LVS
]]
local function ApplyLVSControls(vehicle, throttle, steer, handbrake)
    -- LVS uses networked variables and driver input simulation
    if vehicle.SetThrottle then
        vehicle:SetThrottle(throttle)
    end
    
    -- Check if this is an air vehicle - they use Vector for SetSteer
    if IsLVSAirVehicle(vehicle) then
        -- Air vehicles: SetSteer expects Vector(pitch, yaw, roll)
        -- For NPC driving, we'll just do basic yaw steering, no pitch/roll
        if vehicle.SetSteer then
            -- Safely call SetSteer with a Vector for air vehicles
            local ok, err = pcall(function()
                vehicle:SetSteer(Vector(0, steer, 0))  -- pitch=0, yaw=steer, roll=0
            end)
            if not ok then
                -- Fallback: try as number if Vector fails
                pcall(function() vehicle:SetSteer(steer) end)
            end
        end
    else
        -- Ground vehicles: SetSteer expects a number
        if vehicle.SetSteer then
            vehicle:SetSteer(steer)
        end
    end
    
    if vehicle.SetHandbrake then
        vehicle:SetHandbrake(handbrake)
    end
    
    -- Also try direct AI control methods
    if vehicle.SetAIThrottle then
        vehicle:SetAIThrottle(throttle)
    end
    if vehicle.SetAISteering then
        vehicle:SetAISteering(steer)
    end
    
    -- Set AI mode if available (only enable when actually driving)
    if vehicle.SetAI then
        vehicle:SetAI(true)
    end
    
    -- Store AI input for vehicles that check it
    vehicle._AIThrottle = throttle
    vehicle._AISteering = steer
    vehicle._AIHandbrake = handbrake
    vehicle._npcDriver = true
end

--[[
    Completely stop and disable LVS vehicle AI
]]
local function StopLVSVehicle(vehicle)
    if not IsValid(vehicle) then return end
    
    -- Stop movement
    if vehicle.SetThrottle then
        vehicle:SetThrottle(0)
    end
    
    -- Handle SetSteer for both air and ground vehicles
    if vehicle.SetSteer then
        if IsLVSAirVehicle(vehicle) then
            -- Air vehicles expect Vector
            pcall(function() vehicle:SetSteer(Vector(0, 0, 0)) end)
        else
            -- Ground vehicles expect number
            pcall(function() vehicle:SetSteer(0) end)
        end
    end
    
    if vehicle.SetHandbrake then
        vehicle:SetHandbrake(true)
    end
    
    -- IMPORTANT: Disable AI mode completely
    if vehicle.SetAI then
        vehicle:SetAI(false)
    end
    if vehicle.SetAIThrottle then
        vehicle:SetAIThrottle(0)
    end
    if vehicle.SetAISteering then
        vehicle:SetAISteering(0)
    end
    
    -- Disable AI gunners as well
    if vehicle.SetAIGunners then
        vehicle:SetAIGunners(false)
    end
    
    -- Clear all AI-related variables
    vehicle._AIThrottle = nil
    vehicle._AISteering = nil
    vehicle._AIHandbrake = nil
    vehicle._npcDriver = nil
    vehicle._AIFireInput = nil
    
    -- Stop any gunner entities attached to this vehicle
    for _, child in ipairs(vehicle:GetChildren()) do
        if IsValid(child) and string.find(child:GetClass() or "", "gunner") then
            child._AIFireInput = false
            child._ai_look_dir = nil
            child._attackStarted = nil
            if child.WeaponsFinish then
                pcall(child.WeaponsFinish, child)
            end
            if child.GetActiveWeapon then
                local curWeapon = child:GetActiveWeapon()
                if curWeapon and curWeapon.FinishAttack then
                    pcall(curWeapon.FinishAttack, child)
                end
            end
        end
    end
end

--[[
    Apply vehicle controls for Simfphys
]]
local function ApplySimfphysControls(vehicle, throttle, steer, handbrake)
    if vehicle.SetThrottle then
        vehicle:SetThrottle(throttle)
    end
    if vehicle.SetSteering then
        vehicle:SetSteering(steer)
    elseif vehicle.SetSteer then
        vehicle:SetSteer(steer)
    end
    if vehicle.SetHandBrake then
        vehicle:SetHandBrake(handbrake)
    elseif vehicle.SetHandbrake then
        vehicle:SetHandbrake(handbrake)
    end
    
    -- Simfphys AI inputs
    vehicle.PressedKeys = vehicle.PressedKeys or {}
    if throttle > 0.1 then
        vehicle.PressedKeys["W"] = true
        vehicle.PressedKeys["S"] = false
    elseif throttle < -0.1 then
        vehicle.PressedKeys["W"] = false
        vehicle.PressedKeys["S"] = true
    else
        vehicle.PressedKeys["W"] = false
        vehicle.PressedKeys["S"] = false
    end
    
    if steer < -0.1 then
        vehicle.PressedKeys["A"] = true
        vehicle.PressedKeys["D"] = false
    elseif steer > 0.1 then
        vehicle.PressedKeys["A"] = false
        vehicle.PressedKeys["D"] = true
    else
        vehicle.PressedKeys["A"] = false
        vehicle.PressedKeys["D"] = false
    end
    
    vehicle.PressedKeys["Space"] = handbrake
end

--[[
    Apply vehicle controls for generic vehicles
]]
local function ApplyGenericControls(vehicle, throttle, steer, handbrake)
    -- For Pod-based vehicles, we need to simulate keypresses
    if vehicle.SetVehicleParams then
        local params = vehicle:GetVehicleParams()
        if params and params.steering then
            params.steering.degrees = steer * 45
        end
    end
    
    -- Try to set steering directly
    if vehicle.SetSteering then
        vehicle:SetSteering(steer, 0)
    end
    
    -- For vehicles with SetThrottle
    if vehicle.SetThrottle then
        vehicle:SetThrottle(throttle)
    end
    
    -- Store for any vehicle that might check
    vehicle._AIThrottle = throttle
    vehicle._AISteering = steer
end

--[[
    Get vehicle type
]]
local function GetVehicleType(vehicle)
    if not IsValid(vehicle) then return "unknown" end
    
    local class = vehicle:GetClass()
    
    if vehicle.LVS or vehicle.IsLVS or string.find(class, "lvs_") then
        return "lvs"
    elseif vehicle.IsSimfphyscar or vehicle.IsSimfphys or string.find(class, "gmod_sent_vehicle_fphysics") then
        return "simfphys"
    elseif vehicle.IsGlideVehicle or string.find(class, "glide_") then
        return "glide"
    elseif vehicle:IsVehicle() then
        return "generic"
    end
    
    return "unknown"
end

--[[
    Create a driver controller for an NPC
]]
local function CreateDriverController(npc, vehicle, seat)
    local controller = {
        npc = npc,
        vehicle = vehicle,
        seat = seat,
        vehicleType = GetVehicleType(vehicle),
        currentTarget = nil,
        lastTargetUpdate = 0,
        stuckTime = 0,
        lastPos = vehicle:GetPos(),
        isReversing = false,
        reverseTimer = 0,
        scanTimer = 0,
        idleTime = 0,
        patrolAngle = 0,
    }
    
    return controller
end

--[[
    Main think function for driver AI
]]
local function DriverThink(controller, dt)
    if not IsValid(controller.npc) or not IsValid(controller.vehicle) then
        return false -- Remove controller
    end
    
    -- Check if NPC is dead - stop the vehicle and remove controller
    if controller.npc:Health() <= 0 then
        -- Stop the vehicle when driver dies
        if controller.vehicleType == "lvs" then
            StopLVSVehicle(controller.vehicle)
        elseif controller.vehicleType == "simfphys" then
            ApplySimfphysControls(controller.vehicle, 0, 0, true)
        else
            ApplyGenericControls(controller.vehicle, 0, 0)
        end
        controller.vehicle._npcDriver = nil
        return false -- Remove controller
    end
    
    if not NPCPassengers.cv_driver_enabled:GetBool() then
        return true
    end
    
    local curTime = CurTime()
    local vehicle = controller.vehicle
    local npc = controller.npc
    local vehPos = vehicle:GetPos()
    
    -- Scan for enemies periodically
    controller.scanTimer = controller.scanTimer - dt
    if controller.scanTimer <= 0 then
        controller.scanTimer = 0.5
        
        local range = NPCPassengers.cv_driver_range:GetFloat()
        local enemies = FindEnemiesInRange(vehPos, range, npc)
        
        if #enemies > 0 then
            controller.currentTarget = enemies[1]
            controller.idleTime = 0
        else
            controller.currentTarget = nil
            controller.idleTime = controller.idleTime + 0.5
        end
    end
    
    local throttle = 0
    local steer = 0
    local handbrake = false
    
    if controller.currentTarget and IsValid(controller.currentTarget.entity) then
        local targetPos = controller.currentTarget.entity:GetPos()
        local dist = vehPos:Distance(targetPos)
        
        local engageDistance = NPCPassengers.cv_driver_engage_distance:GetFloat()
        local reverseDistance = NPCPassengers.cv_driver_reverse_distance:GetFloat()
        local maxSpeed = NPCPassengers.cv_driver_speed:GetFloat()
        
        -- Calculate steering
        local isFacingTarget
        steer, angleDiff, isFacingTarget = CalculateSteering(vehicle, targetPos)
        
        -- Check if we're stuck
        local moved = vehPos:Distance(controller.lastPos)
        if moved < 5 then
            controller.stuckTime = controller.stuckTime + dt
        else
            controller.stuckTime = 0
        end
        controller.lastPos = vehPos
        
        -- Stuck avoidance - reverse and turn
        if controller.stuckTime > 2 then
            controller.isReversing = true
            controller.reverseTimer = 1.5
            controller.stuckTime = 0
        end
        
        if controller.isReversing then
            controller.reverseTimer = controller.reverseTimer - dt
            throttle = -0.6
            steer = steer -- Keep same steer direction while reversing for tank-style
            
            if controller.reverseTimer <= 0 then
                controller.isReversing = false
            end
        elseif dist < reverseDistance then
            -- Too close, reverse away
            throttle = -0.5
            -- Keep steering toward target while reversing
        elseif dist < engageDistance then
            -- At engagement range, just turn to face enemy (tank behavior)
            if not isFacingTarget then
                -- Need to turn - apply slight throttle to help tank rotate
                throttle = 0.15
                -- Full steering when not facing target
                steer = angleDiff > 0 and 1 or -1
            else
                throttle = 0
                handbrake = true
            end
        elseif not isFacingTarget and math.abs(angleDiff) > 60 then
            -- Very off-target, stop and rotate first!
            throttle = 0.1 -- Minimal movement to help turning
            steer = angleDiff > 0 and 1 or -1 -- Full lock steering
        elseif dist < engageDistance * 1.5 then
            -- Approaching engagement range, slow down
            local speedFactor = (dist - engageDistance) / (engageDistance * 0.5)
            throttle = maxSpeed * math.Clamp(speedFactor, 0.2, 0.5)
            -- Only move if somewhat facing target
            if not isFacingTarget then
                throttle = throttle * 0.3
            end
        else
            -- Far from enemy, drive toward them
            -- IMPORTANT: Only drive forward if facing the right direction!
            if isFacingTarget then
                throttle = maxSpeed
            elseif math.abs(angleDiff) < 45 then
                -- Somewhat facing, drive slower
                throttle = maxSpeed * 0.5
            else
                -- Not facing target at all - rotate first, minimal forward
                throttle = 0.15
                steer = angleDiff > 0 and 1 or -1
            end
            
            -- Check for obstacles
            if IsPathBlocked(vehicle, targetPos) then
                -- Try to steer around
                steer = steer + (steer > 0 and 0.5 or -0.5)
                steer = math.Clamp(steer, -1, 1)
            end
        end
    else
        -- No target - idle patrol behavior
        if controller.idleTime > 3 then
            -- Random slow patrol
            controller.patrolAngle = controller.patrolAngle + dt * 10
            steer = math.sin(controller.patrolAngle * 0.1) * 0.3
            throttle = 0.15
        else
            -- Just stop
            throttle = 0
            steer = 0
            handbrake = true
        end
    end
    
    -- Apply controls based on vehicle type
    if controller.vehicleType == "lvs" then
        ApplyLVSControls(vehicle, throttle, steer, handbrake)
    elseif controller.vehicleType == "simfphys" then
        ApplySimfphysControls(vehicle, throttle, steer, handbrake)
    else
        ApplyGenericControls(vehicle, throttle, steer, handbrake)
    end
    
    return true
end

--[[
    Register an NPC as a driver
]]
function NPCPassengers.RegisterDriverNPC(npc, vehicle, seat)
    if not IsValid(npc) or not IsValid(vehicle) then return end
    
    -- Check if this is the driver seat
    local isDriverSeat = false
    
    if IsValid(seat) then
        -- Check various methods to identify driver seat
        if seat == vehicle then
            isDriverSeat = true
        elseif vehicle.GetDriverSeat and vehicle:GetDriverSeat() == seat then
            isDriverSeat = true
        elseif seat.GetVehicle and seat:GetVehicle() == vehicle then
            isDriverSeat = true
        elseif seat.lvsGetPodIndex and seat:lvsGetPodIndex() == 1 then
            isDriverSeat = true -- Pod 1 is usually driver in LVS
        end
    end
    
    -- Also check if this is the main vehicle entity (driver seat on some vehicles)
    if seat == vehicle then
        isDriverSeat = true
    end
    
    if not isDriverSeat then
        return
    end
    
    local npcId = npc:EntIndex()
    
    -- Don't register twice
    if driverNPCs[npcId] then return end
    
    local controller = CreateDriverController(npc, vehicle, seat)
    driverNPCs[npcId] = controller
end

--[[
    Unregister an NPC driver
]]
function NPCPassengers.UnregisterDriverNPC(npc)
    if not IsValid(npc) then return end
    
    local npcId = npc:EntIndex()
    local controller = driverNPCs[npcId]
    
    if controller then
        -- Stop the vehicle completely
        if IsValid(controller.vehicle) then
            if controller.vehicleType == "lvs" then
                StopLVSVehicle(controller.vehicle)
            elseif controller.vehicleType == "simfphys" then
                ApplySimfphysControls(controller.vehicle, 0, 0, true)
            else
                ApplyGenericControls(controller.vehicle, 0, 0)
            end
            controller.vehicle._npcDriver = nil
        end
        
        driverNPCs[npcId] = nil
    end
end

--[[
    Main think hook
]]
local lastThink = CurTime()
hook.Add("Think", "NPCPassengers_DriverThink", function()
    if not NPCPassengers.cv_driver_enabled:GetBool() then return end
    
    local curTime = CurTime()
    local dt = curTime - lastThink
    lastThink = curTime
    
    -- Process all driver NPCs
    local toRemove = {}
    
    for npcId, controller in pairs(driverNPCs) do
        local keepActive = DriverThink(controller, dt)
        if not keepActive then
            table.insert(toRemove, npcId)
        end
    end
    
    -- Remove inactive controllers
    for _, npcId in ipairs(toRemove) do
        driverNPCs[npcId] = nil
    end
end)

-- Cleanup on entity removal
hook.Add("EntityRemoved", "NPCPassengers_DriverCleanup", function(ent)
    if ent:IsNPC() then
        local npcId = ent:EntIndex()
        if driverNPCs[npcId] then
            -- Stop the vehicle before removing controller
            local controller = driverNPCs[npcId]
            if IsValid(controller.vehicle) then
                if controller.vehicleType == "lvs" then
                    StopLVSVehicle(controller.vehicle)
                elseif controller.vehicleType == "simfphys" then
                    ApplySimfphysControls(controller.vehicle, 0, 0, true)
                else
                    ApplyGenericControls(controller.vehicle, 0, 0)
                end
                controller.vehicle._npcDriver = nil
            end
            driverNPCs[npcId] = nil
        end
    end
end)

-- Cleanup when NPC dies (but entity still exists)
hook.Add("OnNPCKilled", "NPCPassengers_DriverDeathCleanup", function(npc, attacker, inflictor)
    if not IsValid(npc) then return end
    
    local npcId = npc:EntIndex()
    local controller = driverNPCs[npcId]
    
    if controller then
        -- Stop the vehicle when driver is killed
        if IsValid(controller.vehicle) then
            if controller.vehicleType == "lvs" then
                StopLVSVehicle(controller.vehicle)
            elseif controller.vehicleType == "simfphys" then
                ApplySimfphysControls(controller.vehicle, 0, 0, true)
            else
                ApplyGenericControls(controller.vehicle, 0, 0)
            end
            controller.vehicle._npcDriver = nil
        end
        
        driverNPCs[npcId] = nil
    end
end)
