
if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.lvs_turret = true
NPCPassengers.TurretNPCs = NPCPassengers.TurretNPCs or {}

local IsValid = IsValid
local math = math
local string = string
local table = table
local ipairs = ipairs
local pairs = pairs

-- Configuration convars for turret control
NPCPassengers.cv_turret_enabled = CreateConVar("nai_npc_turret_enabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable NPC turret control on LVS vehicles")
NPCPassengers.cv_turret_range = CreateConVar("nai_npc_turret_range", "3000", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum targeting range for NPC turret gunners")
NPCPassengers.cv_turret_accuracy = CreateConVar("nai_npc_turret_accuracy", "0.85", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPC turret accuracy (0-1, higher = more accurate)")
NPCPassengers.cv_turret_reaction_time = CreateConVar("nai_npc_turret_reaction_time", "0.5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Time before NPC starts tracking new targets")
NPCPassengers.cv_turret_fire_delay = CreateConVar("nai_npc_turret_fire_delay", "0.15", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Delay between NPC trigger pulls")
NPCPassengers.cv_turret_aim_speed = CreateConVar("nai_npc_turret_aim_speed", "5", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "How fast NPCs aim the turret (degrees per tick)")
NPCPassengers.cv_turret_friendly_fire = CreateConVar("nai_npc_turret_friendly_fire", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Allow NPCs to target friendlies")
NPCPassengers.cv_turret_lead_targets = CreateConVar("nai_npc_turret_lead_targets", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "NPCs lead moving targets")
NPCPassengers.cv_turret_hold_fire = CreateConVar("nai_npc_turret_hold_fire", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "When 1, turret gunners will not fire. When 0, they will fire normally.")
NPCPassengers.cv_turret_blacklist = CreateConVar("nai_npc_turret_blacklist", "", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Comma-separated list of NPC classnames to blacklist from turret control (e.g., npc_metropolice,npc_combine_s)")

-- Helper function to check if NPC is blacklisted
local function IsNPCTurretBlacklisted(npc)
    if not IsValid(npc) then return true end
    
    local blacklist = NPCPassengers.cv_turret_blacklist:GetString() or ""
    if blacklist == "" then return false end
    
    local npcClass = npc:GetClass() or ""
    local blacklistTable = string.Explode(",", blacklist)
    
    for _, blacklistedClass in ipairs(blacklistTable) do
        local trimmed = string.Trim(blacklistedClass)
        if trimmed ~= "" and npcClass == trimmed then
            return true
        end
    end
    
    return false
end

-- Console command to view current blacklist
concommand.Add("nai_npc_get_turret_blacklist", function(ply)
    local blacklist = NPCPassengers.cv_turret_blacklist:GetString() or ""
    if blacklist == "" then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Turret blacklist is empty (all NPCs allowed)")
        else
            print("[Better NPC Passengers] Turret blacklist is empty (all NPCs allowed)")
        end
    else
        local classes = string.Explode(",", blacklist)
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Blacklisted NPC classes:")
            for _, class in ipairs(classes) do
                local trimmed = string.Trim(class)
                if trimmed ~= "" then
                    ply:ChatPrint("  - " .. trimmed)
                end
            end
        else
            print("[Better NPC Passengers] Blacklisted NPC classes:")
            for _, class in ipairs(classes) do
                local trimmed = string.Trim(class)
                if trimmed ~= "" then
                    print("  - " .. trimmed)
                end
            end
        end
    end
end, nil, "View the list of blacklisted NPC classes for turret control")

-- Console command to add an NPC to the blacklist
concommand.Add("nai_npc_add_turret_blacklist", function(ply, cmd, args)
    if not args[1] then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Usage: nai_npc_add_turret_blacklist <npc_class>")
        else
            print("[Better NPC Passengers] Usage: nai_npc_add_turret_blacklist <npc_class>")
        end
        return
    end

    local npcClass = args[1]
    local blacklist = NPCPassengers.cv_turret_blacklist:GetString() or ""
    local blacklistTable = string.Explode(",", blacklist)

    -- Check if already blacklisted
    for _, existing in ipairs(blacklistTable) do
        if string.Trim(existing) == npcClass then
            if IsValid(ply) then
                ply:ChatPrint("[Better NPC Passengers] '" .. npcClass .. "' is already blacklisted")
            else
                print("[Better NPC Passengers] '" .. npcClass .. "' is already blacklisted")
            end
            return
        end
    end

    -- Add to blacklist
    if blacklist == "" then
        blacklist = npcClass
    else
        blacklist = blacklist .. "," .. npcClass
    end

    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_turret_blacklist then
        NPCPassengers.cv_turret_blacklist:SetString(blacklist)
    end

    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Added '" .. npcClass .. "' to vehicle blacklist")
    else
        print("[Better NPC Passengers] Added '" .. npcClass .. "' to vehicle blacklist")
    end
end, nil, "Add an NPC class to the vehicle blacklist")

-- Console command to remove an NPC from the blacklist
concommand.Add("nai_npc_remove_turret_blacklist", function(ply, cmd, args)
    if not args[1] then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Usage: nai_npc_remove_turret_blacklist <npc_class>")
        else
            print("[Better NPC Passengers] Usage: nai_npc_remove_turret_blacklist <npc_class>")
        end
        return
    end

    local npcClass = args[1]
    local blacklist = NPCPassengers.cv_turret_blacklist:GetString() or ""
    local blacklistTable = string.Explode(",", blacklist)
    local newTable = {}
    local found = false

    for _, existing in ipairs(blacklistTable) do
        local trimmed = string.Trim(existing)
        if trimmed == npcClass then
            found = true
        elseif trimmed ~= "" then
            table.insert(newTable, trimmed)
        end
    end

    if not found then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] '" .. npcClass .. "' is not in the blacklist")
        else
            print("[Better NPC Passengers] '" .. npcClass .. "' is not in the blacklist")
        end
        return
    end

    local newBlacklist = table.concat(newTable, ",")
    
    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_turret_blacklist then
        NPCPassengers.cv_turret_blacklist:SetString(newBlacklist)
    end

    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Removed '" .. npcClass .. "' from vehicle blacklist")
    else
        print("[Better NPC Passengers] Removed '" .. npcClass .. "' from vehicle blacklist")
    end
end, nil, "Remove an NPC class from the vehicle blacklist")

-- Console command to clear the entire blacklist
concommand.Add("nai_npc_clear_turret_blacklist", function(ply)
    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_turret_blacklist then
        NPCPassengers.cv_turret_blacklist:SetString("")
    end
    
    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Cleared vehicle blacklist (all NPCs now allowed)")
    else
        print("[Better NPC Passengers] Cleared vehicle blacklist (all NPCs now allowed)")
    end
end, nil, "Clear the entire vehicle blacklist")

-- Create whitelist convar
NPCPassengers.cv_vehicle_whitelist = CreateConVar("nai_npc_vehicle_whitelist", "", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Comma-separated list of NPC classnames to whitelist for vehicle boarding (e.g., npc_barney,npc_eli)")

-- Helper function to check if NPC is whitelisted
local function IsNPCVehicleWhitelisted(npc)
    if not IsValid(npc) then return false end
    
    local whitelist = NPCPassengers.cv_vehicle_whitelist:GetString() or ""
    if whitelist == "" then return false end
    
    local npcClass = npc:GetClass() or ""
    local whitelistTable = string.Explode(",", whitelist)
    
    for _, whitelistedClass in ipairs(whitelistTable) do
        local trimmed = string.Trim(whitelistedClass)
        if trimmed ~= "" and npcClass == trimmed then
            return true
        end
    end
    
    return false
end

-- Console command to view current whitelist
concommand.Add("nai_npc_get_vehicle_whitelist", function(ply)
    local whitelist = NPCPassengers.cv_vehicle_whitelist:GetString() or ""
    if whitelist == "" then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Vehicle whitelist is empty (no NPCs forced)")
        else
            print("[Better NPC Passengers] Vehicle whitelist is empty (no NPCs forced)")
        end
    else
        local classes = string.Explode(",", whitelist)
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Whitelisted NPC classes:")
            for _, class in ipairs(classes) do
                local trimmed = string.Trim(class)
                if trimmed ~= "" then
                    ply:ChatPrint("  - " .. trimmed)
                end
            end
        else
            print("[Better NPC Passengers] Whitelisted NPC classes:")
            for _, class in ipairs(classes) do
                local trimmed = string.Trim(class)
                if trimmed ~= "" then
                    print("  - " .. trimmed)
                end
            end
        end
    end
end, nil, "View the list of whitelisted NPC classes for vehicle boarding")

-- Console command to add an NPC to the whitelist
concommand.Add("nai_npc_add_vehicle_whitelist", function(ply, cmd, args)
    if not args[1] then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Usage: nai_npc_add_vehicle_whitelist <npc_class>")
        else
            print("[Better NPC Passengers] Usage: nai_npc_add_vehicle_whitelist <npc_class>")
        end
        return
    end

    local npcClass = args[1]
    local whitelist = NPCPassengers.cv_vehicle_whitelist:GetString() or ""
    local whitelistTable = string.Explode(",", whitelist)

    -- Check if already whitelisted
    for _, existing in ipairs(whitelistTable) do
        if string.Trim(existing) == npcClass then
            if IsValid(ply) then
                ply:ChatPrint("[Better NPC Passengers] '" .. npcClass .. "' is already whitelisted")
            else
                print("[Better NPC Passengers] '" .. npcClass .. "' is already whitelisted")
            end
            return
        end
    end

    -- Add to whitelist
    if whitelist == "" then
        whitelist = npcClass
    else
        whitelist = whitelist .. "," .. npcClass
    end

    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_vehicle_whitelist then
        NPCPassengers.cv_vehicle_whitelist:SetString(whitelist)
    end

    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Added '" .. npcClass .. "' to vehicle whitelist")
    else
        print("[Better NPC Passengers] Added '" .. npcClass .. "' to vehicle whitelist")
    end
end, nil, "Add an NPC class to the vehicle whitelist")

-- Console command to remove an NPC from the whitelist
concommand.Add("nai_npc_remove_vehicle_whitelist", function(ply, cmd, args)
    if not args[1] then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] Usage: nai_npc_remove_vehicle_whitelist <npc_class>")
        else
            print("[Better NPC Passengers] Usage: nai_npc_remove_vehicle_whitelist <npc_class>")
        end
        return
    end

    local npcClass = args[1]
    local whitelist = NPCPassengers.cv_vehicle_whitelist:GetString() or ""
    local whitelistTable = string.Explode(",", whitelist)
    local newTable = {}
    local found = false

    for _, existing in ipairs(whitelistTable) do
        local trimmed = string.Trim(existing)
        if trimmed == npcClass then
            found = true
        elseif trimmed ~= "" then
            table.insert(newTable, trimmed)
        end
    end

    if not found then
        if IsValid(ply) then
            ply:ChatPrint("[Better NPC Passengers] '" .. npcClass .. "' is not in the whitelist")
        else
            print("[Better NPC Passengers] '" .. npcClass .. "' is not in the whitelist")
        end
        return
    end

    local newWhitelist = table.concat(newTable, ",")
    
    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_vehicle_whitelist then
        NPCPassengers.cv_vehicle_whitelist:SetString(newWhitelist)
    end

    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Removed '" .. npcClass .. "' from vehicle whitelist")
    else
        print("[Better NPC Passengers] Removed '" .. npcClass .. "' from vehicle whitelist")
    end
end, nil, "Remove an NPC class from the vehicle whitelist")

-- Console command to clear the entire whitelist
concommand.Add("nai_npc_clear_vehicle_whitelist", function(ply)
    -- Directly set the convar to avoid duplicate messages
    if NPCPassengers.cv_vehicle_whitelist then
        NPCPassengers.cv_vehicle_whitelist:SetString("")
    end
    
    if IsValid(ply) then
        ply:ChatPrint("[Better NPC Passengers] Cleared vehicle whitelist")
    else
        print("[Better NPC Passengers] Cleared vehicle whitelist")
    end
end, nil, "Clear the entire vehicle whitelist")

-- Cache for performance
local turretNPCs = NPCPassengers.TurretNPCs
local activeGunners = {}
local trackedTurretTargets = {}
local nextTurretTargetRefresh = 0
local TURRET_TARGET_REFRESH_INTERVAL = 2

--[[
    Checks if an LVS vehicle has turret/weapon capability for a given seat
]]
local function LVSGetSeatWeaponInfo(vehicle, seat)
    if not IsValid(vehicle) then return nil end

    -- Check if this is an LVS vehicle
    local isLVS = vehicle.LVS or vehicle.IsLVS or string.find(vehicle:GetClass() or "", "lvs_")
    if not isLVS then
        return nil
    end

    -- Try to get pod index from seat
    local podIndex = nil

    if IsValid(seat) then
        if seat.lvsGetPodIndex then
            podIndex = seat:lvsGetPodIndex()
        elseif seat.GetPodIndex then
            podIndex = seat:GetPodIndex()
        elseif seat.PodIndex then
            podIndex = seat.PodIndex
        else
            -- Try to find the seat index manually
            if vehicle.GetPassengerSeats then
                local seats = vehicle:GetPassengerSeats()
                for i, s in pairs(seats) do
                    if s == seat then
                        podIndex = i + 1 -- Usually 1 is driver, so gunner seats start at 2
                        break
                    end
                end
            end
        end
    end
    
    -- If no seat provided or no pod index found, try to get gunner seats
    if not podIndex and vehicle.GetGunnerSeats then
        local gunnerSeats = vehicle:GetGunnerSeats()
        if gunnerSeats and #gunnerSeats > 0 then
            podIndex = 2 -- Default to first gunner seat
        end
    end

    -- Default to pod 2 (first gunner) if no index found but vehicle has weapons
    if not podIndex and vehicle.WEAPONS and table.Count(vehicle.WEAPONS) > 1 then
        podIndex = 2
    end

    -- Check if vehicle has weapons for this pod
    local hasWeapons = false
    local weaponData = nil

    if vehicle.WEAPONS then
        if podIndex and vehicle.WEAPONS[podIndex] then
            weaponData = vehicle.WEAPONS[podIndex]
            hasWeapons = table.Count(weaponData) > 0
        end
        -- Also check if there are ANY weapons we could use
        if not hasWeapons then
            for idx, weapons in pairs(vehicle.WEAPONS) do
                if table.Count(weapons) > 0 then
                    hasWeapons = true
                    weaponData = weapons
                    podIndex = idx
                    break
                end
            end
        end
    end

    -- Check for turret control
    local hasTurret = vehicle.TurretPodIndex == podIndex or vehicle.TurretPodIndex ~= nil

    -- Get weapon handler entity if exists
    local weaponHandler = nil
    if IsValid(seat) then
        if seat.lvsGetWeapon then
            weaponHandler = seat:lvsGetWeapon()
        end
    end
    if not IsValid(weaponHandler) and vehicle.GetWeaponHandler then
        weaponHandler = vehicle:GetWeaponHandler(podIndex or 1)
    end

    -- Check for gunner entities attached to the vehicle
    if not IsValid(weaponHandler) then
        for _, child in ipairs(vehicle:GetChildren()) do
            if IsValid(child) and string.find(child:GetClass() or "", "lvs_") and string.find(child:GetClass() or "", "gunner") then
                weaponHandler = child
                break
            end
        end
    end

    -- Even if no weapons found, return info for LVS vehicles so we can still aim
    -- This allows NPC head tracking toward enemies even without shooting
    return {
        podIndex = podIndex or 2,
        hasWeapons = hasWeapons,
        hasTurret = hasTurret,
        weaponData = weaponData,
        weaponHandler = weaponHandler,
        vehicle = vehicle,
        seat = seat,
        isLVS = true
    }
end

local function IsTurretTargetCandidate(ent)
    return IsValid(ent) and (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0
end

local function TrackTurretTarget(ent)
    if IsTurretTargetCandidate(ent) then
        trackedTurretTargets[ent] = true
    end
end

local function RefreshTurretTargetRegistry(forceRefresh)
    local curTime = CurTime()
    if not forceRefresh and curTime < nextTurretTargetRefresh then return end

    nextTurretTargetRefresh = curTime + TURRET_TARGET_REFRESH_INTERVAL

    for ent in pairs(trackedTurretTargets) do
        if not IsTurretTargetCandidate(ent) then
            trackedTurretTargets[ent] = nil
        end
    end

    for _, ent in ipairs(ents.GetAll()) do
        TrackTurretTarget(ent)
    end
end

-- Hostile NPC classes for enemy detection
local hostileClasses = {
    "npc_zombie", "npc_fastzombie", "npc_poisonzombie", "npc_zombine",
    "npc_headcrab", "npc_headcrab_fast", "npc_headcrab_black", "npc_headcrab_poison",
    "npc_antlion", "npc_antlionguard", "npc_antlion_worker",
    "npc_combine_s", "npc_metropolice", "npc_hunter", "npc_strider",
    "npc_manhack", "npc_stalker", "npc_turret_floor", "npc_turret_ceiling",
    "npc_clawscanner", "npc_cscanner", "npc_combinedropship", "npc_combinegunship",
    "npc_helicopter", "npc_rollermine"
}

--[[
    Gets enemies visible to the NPC within range
]]
local function FindEnemiesInRange(npc, vehicle, maxRange, originalRelationships)
    if not IsValid(npc) or not IsValid(vehicle) then return {} end
    
    local enemies = {}
    local vehiclePos = vehicle:GetPos()
    local maxRangeSqr = maxRange * maxRange
    local allowFriendlyFire = NPCPassengers.cv_turret_friendly_fire:GetBool()

    RefreshTurretTargetRegistry()
    
    -- Get the player in the vehicle to check their enemies
    local vehiclePlayer = nil
    local allPlayers = player.GetAll()
    for _, ply in ipairs(allPlayers) do
        if IsValid(ply) and ply:InVehicle() then
            local plyVeh = ply:GetVehicle()
            if IsValid(plyVeh) and (plyVeh == vehicle or plyVeh:GetParent() == vehicle) then
                vehiclePlayer = ply
                break
            end
        end
    end
    
    -- Filter targets
    for target in pairs(trackedTurretTargets) do
        if target == npc then continue end

        if target:IsNPC() and ((NPCPassengers.IsPassenger and NPCPassengers.IsPassenger(target)) or activeGunners[target] ~= nil) then
            continue
        end

        local distSqr = vehiclePos:DistToSqr(target:GetPos())
        if distSqr <= maxRangeSqr then
            -- Determine if this is an enemy
            -- Since passenger NPC has all relationships set to friendly,
            -- we need to use original relationships or check if target is hostile to player
            local isEnemy = false

            if originalRelationships then
                for ent, disp in pairs(originalRelationships) do
                    if ent == target then
                        isEnemy = (disp == D_HT or disp == D_FR)
                        break
                    end
                end
            end

            if not isEnemy and IsValid(vehiclePlayer) then
                local targetDisp = target:Disposition(vehiclePlayer)
                isEnemy = (targetDisp == D_HT or targetDisp == D_FR)

                if not isEnemy and target:IsNPC() and IsValid(target:GetEnemy()) then
                    if target:GetEnemy() == vehiclePlayer or target:GetEnemy():IsPlayer() then
                        isEnemy = true
                    end
                end
            end

            if not isEnemy then
                local targetClass = target:GetClass()
                for _, hostileClass in ipairs(hostileClasses) do
                    if targetClass == hostileClass then
                        isEnemy = true
                        break
                    end
                end
            end

            -- VJ Base NPC friendly detection: Check if target and passenger are on same team
            if not isEnemy and target:IsNPC() then
                -- Check VJ NPC faction/team (if VJ Base is installed)
                if target.VJ_NPC_Faction and npc.VJ_NPC_Faction then
                    if target.VJ_NPC_Faction == npc.VJ_NPC_Faction then
                        isEnemy = false  -- Same faction = friendly
                    end
                end

                -- Check if both are on same squad (HL2 squads)
                if not isEnemy then
                    local targetSquad = target.GetSquad and target:GetSquad() or nil
                    local npcSquad = npc.GetSquad and npc:GetSquad() or nil
                    if targetSquad and npcSquad and targetSquad ~= "" and npcSquad ~= "" and targetSquad == npcSquad then
                        isEnemy = false  -- Same squad = friendly
                    end
                end

                -- Check if target is attacking the player (definitely an enemy)
                if not isEnemy and IsValid(target:GetEnemy()) then
                    local targetEnemy = target:GetEnemy()
                    if targetEnemy:IsPlayer() or (targetEnemy:IsNPC() and targetEnemy:GetEnemy() ~= targetEnemy) then
                        -- Target is fighting player or their own allies, likely hostile
                        isEnemy = true
                    end
                end
            end

            if not allowFriendlyFire and not isEnemy then
                continue
            end

            local startPos = vehicle:LocalToWorld(vehicle:OBBCenter()) + Vector(0, 0, 50)
            local targetPos = target:WorldSpaceCenter() or target:GetPos() + Vector(0, 0, 40)

            local tr = util.TraceLine({
                start = startPos,
                endpos = targetPos,
                filter = {vehicle, npc},
                mask = MASK_SHOT
            })

            if tr.Entity == target or not tr.Hit then
                table.insert(enemies, {
                    entity = target,
                    distance = math.sqrt(distSqr),
                    position = targetPos,
                    velocity = target:GetVelocity(),
                    isEnemy = isEnemy
                })
            end
        end
    end
    
    -- Sort by distance (closest first)
    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    
    return enemies
end

--[[
    Calculate lead position for moving targets
]]
local function CalculateLeadPosition(targetPos, targetVel, muzzlePos, projectileSpeed)
    if not NPCPassengers.cv_turret_lead_targets:GetBool() then
        return targetPos
    end
    
    projectileSpeed = projectileSpeed or 10000 -- Default bullet speed
    
    local distance = muzzlePos:Distance(targetPos)
    local travelTime = distance / projectileSpeed
    
    -- Predict where target will be
    local leadPos = targetPos + (targetVel * travelTime)
    
    return leadPos
end

--[[
    Apply accuracy spread to aim direction
]]
local function ApplyAccuracySpread(aimDir, accuracy)
    local spread = (1 - accuracy) * 5 -- Max 5 degree spread at 0 accuracy
    
    local spreadAng = aimDir:Angle()
    spreadAng.p = spreadAng.p + math.Rand(-spread, spread)
    spreadAng.y = spreadAng.y + math.Rand(-spread, spread)
    
    return spreadAng:Forward()
end

--[[
    Get muzzle position for a weapon on an LVS vehicle
]]
local function GetWeaponMuzzlePos(vehicle, weaponInfo)
    local muzzlePos = vehicle:LocalToWorld(vehicle:OBBCenter()) + Vector(0, 0, 50)
    local muzzleAng = vehicle:GetAngles()
    
    -- Try to get actual muzzle attachment
    local attachmentNames = {"muzzle", "muzzle_1", "muzzle1", "gun_muzzle", "turret_muzzle"}
    
    for _, name in ipairs(attachmentNames) do
        local attachId = vehicle:LookupAttachment(name)
        if attachId and attachId > 0 then
            local attach = vehicle:GetAttachment(attachId)
            if attach then
                muzzlePos = attach.Pos
                muzzleAng = attach.Ang
                break
            end
        end
    end
    
    -- If weapon handler exists, try to get from it
    if IsValid(weaponInfo.weaponHandler) then
        local handler = weaponInfo.weaponHandler
        if handler.GetMuzzlePos then
            local pos = handler:GetMuzzlePos()
            if pos then muzzlePos = pos end
        end
    end
    
    return muzzlePos, muzzleAng
end

--[[
    Main turret control structure for an NPC gunner
]]
local function CreateTurretController(npc, passengerData)
    local vehicle = passengerData.vehicle
    local seat = passengerData.seat

    local weaponInfo = LVSGetSeatWeaponInfo(vehicle, seat)
    if not weaponInfo then return nil end

    -- Store original relationships from passenger data
    local originalRelationships = passengerData.relationships or {}

    return {
        npc = npc,
        vehicle = vehicle,
        seat = seat,
        weaponInfo = weaponInfo,
        originalRelationships = originalRelationships,
        currentTarget = nil,
        targetAcquiredTime = 0,
        lastFireTime = 0,
        lastTargetNotifyTime = 0,
        aimYaw = 0,
        aimPitch = 0,
        targetYaw = 0,
        targetPitch = 0,
        isTracking = false,
        scanTimer = 0,
        gunnerEntity = nil
    }
end

--[[
    Update turret aim towards target
]]
local function UpdateTurretAim(controller, dt)
    local vehicle = controller.vehicle
    local npc = controller.npc
    local target = controller.currentTarget
    
    if not IsValid(vehicle) or not IsValid(npc) then return end
    
    local aimSpeed = NPCPassengers.cv_turret_aim_speed:GetFloat() * dt * 60
    
    if target and IsValid(target.entity) then
        local muzzlePos = GetWeaponMuzzlePos(vehicle, controller.weaponInfo)
        local targetPos = CalculateLeadPosition(
            target.position, 
            target.velocity, 
            muzzlePos, 
            10000
        )
        
        -- Calculate angles to target in vehicle local space
        local localTargetPos = vehicle:WorldToLocal(targetPos)
        local targetAng = (localTargetPos):Angle()
        
        controller.targetYaw = math.NormalizeAngle(targetAng.y)
        controller.targetPitch = math.Clamp(-targetAng.p, -45, 45)
        controller.isTracking = true
        
        -- Make NPC look at the target
        local npcEyePos = npc:EyePos()
        local dirToTarget = (targetPos - npcEyePos):GetNormalized()
        local lookAng = dirToTarget:Angle()
        local npcAng = npc:GetAngles()
        
        -- Calculate relative yaw and pitch for NPC head
        local relativeYaw = math.AngleDifference(lookAng.y, npcAng.y)
        local relativePitch = lookAng.p
        
        relativeYaw = math.Clamp(relativeYaw, -75, 75)
        relativePitch = math.Clamp(relativePitch, -30, 30)
        
        -- Apply head pose parameters to NPC
        npc:SetPoseParameter("head_yaw", relativeYaw)
        npc:SetPoseParameter("head_pitch", relativePitch)
        npc:SetPoseParameter("aim_yaw", relativeYaw * 0.5)
        npc:SetPoseParameter("aim_pitch", relativePitch * 0.5)
        
        -- Set eye target
        npc:SetEyeTarget(targetPos)
    else
        -- Return to neutral position
        controller.targetYaw = 0
        controller.targetPitch = 0
        controller.isTracking = false
    end
    
    -- Smooth aim interpolation
    controller.aimYaw = math.ApproachAngle(controller.aimYaw, controller.targetYaw, aimSpeed)
    controller.aimPitch = math.Approach(controller.aimPitch, controller.targetPitch, aimSpeed * 0.5)
    
    -- Apply to vehicle turret if applicable
    if controller.weaponInfo.hasTurret then
        if vehicle.SetTurretYaw then
            vehicle:SetTurretYaw(controller.aimYaw)
        end
        if vehicle.SetTurretPitch then
            vehicle:SetTurretPitch(controller.aimPitch)
        end
        
        -- Also set pose parameters directly
        if vehicle.TurretYawPoseParameterName then
            vehicle:SetPoseParameter(vehicle.TurretYawPoseParameterName, controller.aimYaw)
        end
        if vehicle.TurretPitchPoseParameterName then
            vehicle:SetPoseParameter(vehicle.TurretPitchPoseParameterName, controller.aimPitch)
        end
    end
    
    -- Apply aim to weapon handler if exists
    local handler = controller.weaponInfo.weaponHandler
    if IsValid(handler) then
        if handler.SetAimVector then
            local aimAng = Angle(-controller.aimPitch, controller.aimYaw, 0)
            handler:SetAimVector(vehicle:LocalToWorldAngles(aimAng):Forward())
        end
        -- Also set the AI look direction on handler
        if target and IsValid(target.entity) then
            handler._ai_look_dir = (target.position - handler:GetPos()):GetNormalized()
        end
    end
    
    -- Also update stored gunner entity aim direction
    if IsValid(controller.gunnerEntity) and target and IsValid(target.entity) then
        controller.gunnerEntity._ai_look_dir = (target.position - controller.gunnerEntity:GetPos()):GetNormalized()
    end
end

--[[
    Attempt to fire the turret weapon
    The key challenge: LVS's GetAI() returns false if there's a driver in the seat
    We need to bypass this by calling the weapon Attack function directly
]]
local function TryFireTurret(controller)
    local curTime = CurTime()
    local fireDelay = NPCPassengers.cv_turret_fire_delay:GetFloat()
    
    if curTime - controller.lastFireTime < fireDelay then
        return false
    end
    
    if not controller.currentTarget or not IsValid(controller.currentTarget.entity) then
        return false
    end
    
    local vehicle = controller.vehicle
    local seat = controller.seat
    local weaponInfo = controller.weaponInfo
    
    -- Check if aim is close enough to target
    local aimDiff = math.abs(controller.aimYaw - controller.targetYaw) + 
                    math.abs(controller.aimPitch - controller.targetPitch)
    
    local accuracy = NPCPassengers.cv_turret_accuracy:GetFloat()
    local maxAimDiff = (1 - accuracy) * 20 + 5 -- 5-25 degrees depending on accuracy
    
    if aimDiff > maxAimDiff then
        return false -- Not aimed well enough
    end
    
    local fired = false
    
    -- Method 1: Get the gunner entity from the seat and set _AIFireInput
    local gunner = nil
    if IsValid(seat) then
        if seat.lvsGetWeapon then
            gunner = seat:lvsGetWeapon()
        elseif seat.GetWeapon then
            gunner = seat:GetWeapon()
        end
    end
    
    -- Also try to find gunner from vehicle's children
    if not IsValid(gunner) then
        for _, child in ipairs(vehicle:GetChildren()) do
            if IsValid(child) and child:GetClass() == "lvs_base_gunner" then
                -- Find the gunner associated with our seat
                if child.GetDriverSeat and child:GetDriverSeat() == seat then
                    gunner = child
                    break
                end
            end
        end
    end
    
    -- Fallback: get any gunner entity that's not already controlled
    if not IsValid(gunner) then
        for _, child in ipairs(vehicle:GetChildren()) do
            if IsValid(child) and string.find(child:GetClass(), "gunner") then
                gunner = child
                break
            end
        end
    end
    
    -- Store gunner for use in aim updates
    controller.gunnerEntity = gunner
    
    if IsValid(gunner) then
        -- Set aim direction for AI (even if we fire directly)
        local targetDir = (controller.currentTarget.position - gunner:GetPos()):GetNormalized()
        gunner._ai_look_dir = targetDir
        gunner._AIFireInput = true
        
        -- IMPORTANT: Override the GetAI method temporarily to return true
        -- This is needed because LVS checks GetAI() which returns false when there's a driver
        local originalGetAI = gunner.GetAI
        gunner.GetAI = function() return true end
        
        -- Try direct weapon attack call (most reliable method)
        if gunner.GetActiveWeapon then
            local curWeapon, selectedID = gunner:GetActiveWeapon()
            if curWeapon and curWeapon.Attack then
                -- Check cooldown
                local canFire = true
                if gunner.CanAttack then
                    canFire = gunner:CanAttack()
                end
                
                if canFire then
                    -- Set weapon as active
                    if gunner.SetSelectedWeapon and selectedID then
                        gunner:SetSelectedWeapon(selectedID)
                    end
                    gunner._activeWeapon = selectedID
                    
                    -- Start attack if not already attacking
                    if curWeapon.StartAttack and not gunner._attackStarted then
                        pcall(curWeapon.StartAttack, gunner)
                        gunner._attackStarted = true
                    end
                    
                    -- Fire!
                    local success, err = pcall(curWeapon.Attack, gunner)
                    if success then
                        fired = true
                        -- Set next attack time
                        if gunner.SetNextAttack then
                            gunner:SetNextAttack(curTime + (curWeapon.Delay or 0.1))
                        end
                        -- Handle heat buildup
                        if gunner.SetHeat and gunner.GetHeat then
                            local curHeat = gunner:GetHeat() or 0
                            local heatUp = curWeapon.HeatRateUp or 0.1
                            gunner:SetHeat(math.min(1, curHeat + heatUp))
                        end
                        -- Take ammo if needed
                        if gunner.TakeAmmo then
                            pcall(gunner.TakeAmmo, gunner)
                        end
                    end
                end
            end
        end
        
        -- Restore original GetAI
        gunner.GetAI = originalGetAI
        
        -- Also try WeaponsThink in case direct attack didn't work
        if not fired and gunner.WeaponsThink then
            pcall(gunner.WeaponsThink, gunner)
            fired = true -- Assume it worked via the think function
        end
    end
    
    -- Method 2: Try vehicle-level AI gunners
    if not fired and vehicle.SetAIGunners then
        vehicle:SetAIGunners(true)
        fired = true
    end
    
    -- Method 3: Direct weapon handler (fallback)
    if not fired and IsValid(weaponInfo.weaponHandler) then
        weaponInfo.weaponHandler._AIFireInput = true
        if weaponInfo.weaponHandler.SetAI then
            weaponInfo.weaponHandler:SetAI(true)
        end
        if weaponInfo.weaponHandler.WeaponsThink then
            pcall(weaponInfo.weaponHandler.WeaponsThink, weaponInfo.weaponHandler)
        end
        fired = true
    end
    
    -- Method 4: Try calling weapon Attack function directly on vehicle
    if not fired and vehicle.GetActiveWeapon then
        local curWeapon = vehicle:GetActiveWeapon()
        if curWeapon and curWeapon.Attack then
            pcall(curWeapon.Attack, vehicle)
            fired = true
        end
    end
    
    -- Method 5: Try weaponData Attack functions
    if not fired and weaponInfo.weaponData then
        for _, weapon in pairs(weaponInfo.weaponData) do
            if weapon.Attack and type(weapon.Attack) == "function" then
                local success, result = pcall(weapon.Attack, gunner or vehicle)
                if success then
                    fired = true
                    break
                end
            end
        end
    end
    
    if fired then
        controller.lastFireTime = curTime
    end
    
    return fired
end

--[[
    Stop firing the turret
]]
local function StopFiring(controller)
    local weaponInfo = controller.weaponInfo
    local vehicle = controller.vehicle
    local npc = controller.npc

    -- Stop the gunner entity
    if IsValid(controller.gunnerEntity) then
        controller.gunnerEntity._AIFireInput = false
        controller.gunnerEntity._attackStarted = nil
        controller.gunnerEntity._ai_look_dir = nil

        -- Finish attack if weapon has FinishAttack/StopAttack
        if controller.gunnerEntity.WeaponsFinish then
            pcall(controller.gunnerEntity.WeaponsFinish, controller.gunnerEntity)
        elseif controller.gunnerEntity.GetActiveWeapon then
            local curWeapon = controller.gunnerEntity:GetActiveWeapon()
            if curWeapon and curWeapon.FinishAttack then
                pcall(curWeapon.FinishAttack, controller.gunnerEntity)
            end
        end
    end

    if IsValid(weaponInfo.weaponHandler) then
        weaponInfo.weaponHandler._AIFireInput = false
        weaponInfo.weaponHandler._ai_look_dir = nil
        if weaponInfo.weaponHandler.SetAI then
            weaponInfo.weaponHandler:SetAI(false)
        end
        if weaponInfo.weaponHandler.FinishAttack then
            pcall(weaponInfo.weaponHandler.FinishAttack, weaponInfo.weaponHandler)
        end
    end

    -- IMPORTANT: Disable AI gunners on the vehicle
    if IsValid(vehicle) then
        if vehicle.SetAIGunners then
            vehicle:SetAIGunners(false)
        end
        vehicle._AIFireInput = nil
        
        -- Stop ALL gunner entities attached to this vehicle
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
end

--[[
    Main think function for a turret-controlling NPC
]]
local function TurretNPCThink(controller, dt)
    if not IsValid(controller.npc) or not IsValid(controller.vehicle) then
        return false -- Remove this controller
    end
    
    -- Check if NPC is dead - stop firing and remove controller
    if controller.npc:Health() <= 0 then
        StopFiring(controller)
        return false -- Remove this controller
    end
    
    local curTime = CurTime()
    local vehicle = controller.vehicle
    local npc = controller.npc
    
    -- Scan for enemies periodically
    controller.scanTimer = controller.scanTimer - dt
    if controller.scanTimer <= 0 then
        controller.scanTimer = 0.25 -- Scan 4 times per second
        
        local range = NPCPassengers.cv_turret_range:GetFloat()
        local enemies = FindEnemiesInRange(npc, vehicle, range, controller.originalRelationships)
        
        if #enemies > 0 then
            local newTarget = enemies[1]
            
            -- Check if this is a new target
            if not controller.currentTarget or
               controller.currentTarget.entity ~= newTarget.entity then
                controller.currentTarget = newTarget
                controller.targetAcquiredTime = curTime
                -- QoL: Notify when turret acquires new target
                local driver = vehicle:GetDriver()
                if IsValid(driver) and driver:IsPlayer() then
                    local targetName = newTarget.entity:GetClass() or "enemy"
                    driver:ChatPrint("[Better NPC Passengers] Turret acquired target: " .. targetName)
                end
            else
                -- Update existing target info
                controller.currentTarget.position = newTarget.position
                controller.currentTarget.velocity = newTarget.velocity
                controller.currentTarget.distance = newTarget.distance
            end
        else
            if controller.currentTarget then
                StopFiring(controller)
                -- QoL: Notify when turret loses target (rate limited to once per 5s)
                if not controller.lastTargetNotifyTime or (curTime - controller.lastTargetNotifyTime) > 5 then
                    local driver = vehicle:GetDriver()
                    if IsValid(driver) and driver:IsPlayer() then
                        driver:ChatPrint("[Better NPC Passengers] Turret lost target")
                        controller.lastTargetNotifyTime = curTime
                    end
                end
            end
            controller.currentTarget = nil
        end
    end
    
    -- Update turret aim
    UpdateTurretAim(controller, dt)

    -- Fire if target acquired and reaction time passed (and not holding fire)
    if controller.currentTarget and not NPCPassengers.cv_turret_hold_fire:GetBool() then
        local reactionTime = NPCPassengers.cv_turret_reaction_time:GetFloat()
        if curTime - controller.targetAcquiredTime >= reactionTime then
            TryFireTurret(controller)
        end
    end
    
    return true -- Keep this controller
end

--[[
    Register an NPC as a turret gunner
]]
function NPCPassengers.RegisterTurretNPC(npc, passengerData)
    if not NPCPassengers.cv_turret_enabled:GetBool() then
        -- QoL: Inform player turret system is disabled
        if IsValid(passengerData.vehicle) and IsValid(passengerData.vehicle:GetDriver()) then
            local driver = passengerData.vehicle:GetDriver()
            if IsValid(driver) and driver:IsPlayer() then
                driver:ChatPrint("[Better NPC Passengers] Turret control is disabled (nai_npc_turret_enabled = 0)")
            end
        end
        return false
    end
    if not IsValid(npc) or not passengerData then return false end
    if activeGunners[npc] then return true end
    if NPCPassengers.DriverNPCs and NPCPassengers.DriverNPCs[npc:EntIndex()] then return false end
    
    -- QoL: Check if NPC is blacklisted from turret control
    if IsNPCTurretBlacklisted(npc) then
        if IsValid(passengerData.vehicle) and IsValid(passengerData.vehicle:GetDriver()) then
            local driver = passengerData.vehicle:GetDriver()
            if IsValid(driver) and driver:IsPlayer() then
                driver:ChatPrint("[Better NPC Passengers] NPC class '" .. (npc:GetClass() or "unknown") .. "' is blacklisted from turret control")
            end
        end
        return false
    end

    local vehicle = passengerData.vehicle
    if not IsValid(vehicle) then return false end

    -- Check if this is an LVS vehicle
    local isLVS = vehicle.LVS or vehicle.IsLVS or string.find(vehicle:GetClass() or "", "lvs_")
    if not isLVS then 
        -- QoL: Inform player vehicle is not LVS
        if IsValid(vehicle:GetDriver()) then
            local driver = vehicle:GetDriver()
            if IsValid(driver) and driver:IsPlayer() then
                driver:ChatPrint("[Better NPC Passengers] Vehicle does not support turret control")
            end
        end
        return false 
    end

    local seat = passengerData.seat

    -- If no seat assigned, try to find a gunner seat on the vehicle
    if not IsValid(seat) then
        -- Check if vehicle has gunner capability
        if vehicle.GetGunnerSeats then
            local gunnerSeats = vehicle:GetGunnerSeats()
            if gunnerSeats and #gunnerSeats > 0 then
                seat = gunnerSeats[1]
            end
        end
    end

    -- If still no seat, check for turret capability on vehicle
    if not IsValid(seat) then
        if vehicle.TurretPodIndex or (vehicle.WEAPONS and table.Count(vehicle.WEAPONS) > 1) then
            -- Vehicle has turret capability, create controller without specific seat
            local controller = CreateTurretController(npc, passengerData)
            if controller then
                activeGunners[npc] = controller
                -- QoL: Notify player of successful turret assignment
                if IsValid(vehicle:GetDriver()) then
                    local driver = vehicle:GetDriver()
                    if IsValid(driver) and driver:IsPlayer() then
                        driver:ChatPrint("[Better NPC Passengers] NPC assigned to turret!")
                    end
                end
                return true
            end
        end
        return false
    end

    -- Don't register driver seat (pod 1) as turret gunner
    if seat.lvsGetPodIndex and seat:lvsGetPodIndex() == 1 then
        return false
    end

    local controller = CreateTurretController(npc, passengerData)
    if not controller then return false end

    activeGunners[npc] = controller

    -- QoL: Small delay before turret starts scanning (prevents instant target acquisition)
    controller.scanTimer = 0.5

    -- QoL: Notify player of successful turret assignment with sound and message
    if IsValid(vehicle:GetDriver()) then
        local driver = vehicle:GetDriver()
        if IsValid(driver) and driver:IsPlayer() then
            driver:ChatPrint("[Better NPC Passengers] NPC assigned to turret!")
            -- Play a subtle confirmation sound
            driver:SendLua("surface.PlaySound(\"buttons/blip1.wav\")")
        end
    end

    return true
end

--[[
    Unregister an NPC from turret control
]]
function NPCPassengers.UnregisterTurretNPC(npc)
    local controller = activeGunners[npc]
    if controller then
        StopFiring(controller)
        activeGunners[npc] = nil
    end
end

--[[
    Check if an NPC is registered as a turret gunner
]]
function NPCPassengers.IsTurretNPC(npc)
    return activeGunners[npc] ~= nil
end

--[[
    Get turret controller for an NPC
]]
function NPCPassengers.GetTurretController(npc)
    return activeGunners[npc]
end

--[[
    Main think hook for all turret NPCs
]]
local lastThinkTime = CurTime()

hook.Add("OnEntityCreated", "NPCPassengers_TurretTargetCreated", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) then
            TrackTurretTarget(ent)
        end
    end)
end)

hook.Add("EntityRemoved", "NPCPassengers_TurretTargetRemoved", function(ent)
    trackedTurretTargets[ent] = nil
end)

hook.Add("Think", "NPCPassengerTurretThink", function()
    if not NPCPassengers.cv_turret_enabled:GetBool() then return end
    
    local curTime = CurTime()
    local dt = curTime - lastThinkTime
    lastThinkTime = curTime
    
    if dt <= 0 then dt = 0.016 end
    
    local toRemove = {}
    
    for npc, controller in pairs(activeGunners) do
        if not TurretNPCThink(controller, dt) then
            table.insert(toRemove, npc)
        end
    end
    
    for _, npc in ipairs(toRemove) do
        NPCPassengers.UnregisterTurretNPC(npc)
    end
end)

-- Cleanup when NPC dies
hook.Add("OnNPCKilled", "NPCPassengers_TurretDeathCleanup", function(npc, attacker, inflictor)
    if not IsValid(npc) then return end
    
    local controller = activeGunners[npc]
    if controller then
        StopFiring(controller)
        activeGunners[npc] = nil
    end
end)
