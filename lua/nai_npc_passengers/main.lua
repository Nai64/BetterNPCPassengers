if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.main = true

local friendlyPassengers = {}
local pendingPassengers = {}
local vehicleCooldowns = {}
local animationTimers = {}
local npcLookState = {}
local npcBoardRetryState = {}
local vehicleSeatCache = {}
local addonWasEnabled = true

local PASSENGER_ANIM_INTERVAL = 0.05
local PASSENGER_MAINTENANCE_INTERVAL = 0.35
local PASSENGER_HEADLOOK_INTERVAL = 0.05
local PASSENGER_TRANSFORM_SYNC_INTERVAL = 0.1

NPCPassengers.LVSCompatResolvers = NPCPassengers.LVSCompatResolvers or {}

-- Forward declare StartAnimationEnforcement
local StartAnimationEnforcement
local DetachNPC
local ResetPassengerState

local function IsDebugModeEnabled()
    if NPCPassengers.GetConVarBool then
        return NPCPassengers.GetConVarBool("nai_npc_debug_mode", false)
    end
    if NPCPassengers.cv_debug_mode then
        return NPCPassengers.cv_debug_mode:GetBool()
    end
    return false
end

local function IsVerboseDebugEnabled()
    if NPCPassengers.GetConVarBool then
        return NPCPassengers.GetConVarBool("nai_npc_debug_verbose", false)
    end
    if NPCPassengers.cv_debug_verbose then
        return NPCPassengers.cv_debug_verbose:GetBool()
    end
    return false
end

local function IsAddonEnabled()
    if NPCPassengers.GetConVarBool then
        return NPCPassengers.GetConVarBool("nai_npc_enabled", true)
    end
    if NPCPassengers.cv_enabled then
        return NPCPassengers.cv_enabled:GetBool()
    end
    return true
end

local function ParseCSVPatterns(str)
    local out = {}
    if not str or str == "" then return out end
    for token in string.gmatch(str, "[^,]+") do
        token = string.Trim(string.lower(token or ""))
        if token ~= "" then
            out[#out + 1] = token
        end
    end
    return out
end

local function ValueMatchesPatterns(value, patterns)
    if #patterns == 0 then return false end
    local lowerValue = string.lower(value or "")
    for _, pattern in ipairs(patterns) do
        local luaPattern = "^" .. string.PatternSafe(pattern):gsub("%%*", ".*") .. "$"
        if string.find(lowerValue, luaPattern) then
            return true
        end
    end
    return false
end

local function IsVehicleAllowedByFilters(vehicle)
    if not IsValid(vehicle) then return false end

    local className = string.lower(vehicle:GetClass() or "")
    local modelName = string.lower(vehicle:GetModel() or "")

    local allowClasses = ParseCSVPatterns(NPCPassengers.GetConVarString and NPCPassengers.GetConVarString("nai_npc_allow_classes", "") or (GetConVar("nai_npc_allow_classes") and GetConVar("nai_npc_allow_classes"):GetString() or ""))
    local denyClasses = ParseCSVPatterns(NPCPassengers.GetConVarString and NPCPassengers.GetConVarString("nai_npc_deny_classes", "") or (GetConVar("nai_npc_deny_classes") and GetConVar("nai_npc_deny_classes"):GetString() or ""))
    local allowModels = ParseCSVPatterns(NPCPassengers.GetConVarString and NPCPassengers.GetConVarString("nai_npc_allow_models", "") or (GetConVar("nai_npc_allow_models") and GetConVar("nai_npc_allow_models"):GetString() or ""))
    local denyModels = ParseCSVPatterns(NPCPassengers.GetConVarString and NPCPassengers.GetConVarString("nai_npc_deny_models", "") or (GetConVar("nai_npc_deny_models") and GetConVar("nai_npc_deny_models"):GetString() or ""))

    if ValueMatchesPatterns(className, denyClasses) or ValueMatchesPatterns(modelName, denyModels) then
        return false
    end

    if #allowClasses > 0 and not ValueMatchesPatterns(className, allowClasses) then
        return false
    end

    if #allowModels > 0 and not ValueMatchesPatterns(modelName, allowModels) then
        return false
    end

    return true
end

local function GetVehiclePassengerLimit()
    local cap = NPCPassengers.GetConVarInt and NPCPassengers.GetConVarInt("nai_npc_max_passengers", 8) or 8
    return math.max(1, cap)
end

local function GetRetryAttemptsLimit()
    local tries = NPCPassengers.GetConVarInt and NPCPassengers.GetConVarInt("nai_npc_retry_attempts", 3) or 3
    return math.max(1, tries)
end

local function GetRetryCooldownSeconds()
    local seconds = NPCPassengers.GetConVarFloat and NPCPassengers.GetConVarFloat("nai_npc_retry_cooldown", 6) or 6
    return math.max(0.5, seconds)
end

local function IsNPCBoardCooldownActive(npc)
    if not IsValid(npc) then return true end
    local state = npcBoardRetryState[npc:EntIndex()]
    if not state then return false end
    return (state.blockedUntil or 0) > CurTime()
end

local function RegisterBoardSuccess(npc)
    if not IsValid(npc) then return end
    npcBoardRetryState[npc:EntIndex()] = nil
end

local function RegisterBoardFailure(npc)
    if not IsValid(npc) then return false end
    local npcId = npc:EntIndex()
    local state = npcBoardRetryState[npcId] or { attempts = 0, blockedUntil = 0 }
    state.attempts = (state.attempts or 0) + 1

    if state.attempts >= GetRetryAttemptsLimit() then
        state.attempts = 0
        state.blockedUntil = CurTime() + GetRetryCooldownSeconds()
        npcBoardRetryState[npcId] = state
        return true
    end

    npcBoardRetryState[npcId] = state
    return false
end

function NPCPassengers.RegisterLVSSeatResolver(pattern, resolverFn)
    if not pattern or pattern == "" or not isfunction(resolverFn) then return false end
    NPCPassengers.LVSCompatResolvers[string.lower(pattern)] = resolverFn
    return true
end

if not NPCPassengers.LVSCompatResolvers["lvs_wheeldrive"] then
    NPCPassengers.RegisterLVSSeatResolver("lvs_wheeldrive", function(vehicle)
        local seats = {}
        if not IsValid(vehicle) then return seats end

        if vehicle.GetPassengerSeats then
            for _, seat in pairs(vehicle:GetPassengerSeats()) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
        end

        if #seats == 0 and vehicle.GetGunnerSeats then
            for _, seat in pairs(vehicle:GetGunnerSeats()) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
        end

        if #seats == 0 and vehicle.GetDriverSeat then
            local driverSeat = vehicle:GetDriverSeat()
            if IsValid(driverSeat) and not IsValid(driverSeat:GetDriver()) then
                seats[#seats + 1] = driverSeat
            end
        end

        return seats
    end)
end

local function GetLVSCompatResolver(vehicle)
    if not IsValid(vehicle) then return nil end
    local className = string.lower(vehicle:GetClass() or "")
    for pattern, resolver in pairs(NPCPassengers.LVSCompatResolvers) do
        if string.find(className, pattern, 1, true) then
            return resolver
        end
    end
    return nil
end

local function SendClientCue(ply, success, msg)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    net.Start("NPCPassengers_ClientCue")
    net.WriteBool(success == true)
    net.WriteString(msg or "")
    net.Send(ply)
end

local function Phrase(key, ...)
    if NPCPassengers.GetPhrase then
        return NPCPassengers.GetPhrase(key, ...)
    end
    return key
end

-- Helper: Mark NPC as playing gesture to prevent sit pose reset
local function MarkGesturePlaying(npc, duration)
    local npcId = npc:EntIndex()
    local state = npcLookState[npcId]
    if state then
        state.isPlayingGesture = true
        state.gestureEndTime = CurTime() + duration
    end
end

-- Network strings for debug testing and HUD
util.AddNetworkString("NPCPassengers_DebugTest")
util.AddNetworkString("NPCPassengers_HUDUpdate")
util.AddNetworkString("NPCPassengers_SetStatus")
util.AddNetworkString("NPCPassengers_EjectPrompt")
util.AddNetworkString("NPCPassengers_EjectDead")
util.AddNetworkString("NPCPassengers_MakeDriver")
util.AddNetworkString("NPCPassengers_ClientCue")

-- Debug test receiver (simplified - body sway is now client-side)
net.Receive("NPCPassengers_DebugTest", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if not IsDebugModeEnabled() then return end
    
    local testType = net.ReadString()
    
    -- Find the closest passenger NPC to the player
    local closestNPC = nil
    local closestDist = math.huge
    local plyPos = ply:GetPos()
    
    for npc, data in pairs(friendlyPassengers) do
        if IsValid(npc) then
            local dist = plyPos:DistToSqr(npc:GetPos())
            if dist < closestDist then
                closestDist = dist
                closestNPC = npc
            end
        end
    end
    
    if not IsValid(closestNPC) then
        ply:ChatPrint("[NPC Passengers] No passenger NPCs found to test!")
        return
    end
    
    local npcId = closestNPC:EntIndex()
    local state = npcLookState[npcId]
    


    -- Helper function to try playing a gesture by activity
    local function TryGestureActivity(npc, activity, autoKill)
        if not activity then return false, -1 end
        local seq = npc:SelectWeightedSequence(activity)
        if seq and seq >= 0 then
            local dur = npc:SequenceDuration(seq)
            npc:AddGestureSequence(seq, autoKill ~= false)
            if dur and dur > 0.1 then MarkGesturePlaying(npc, dur) end
            return true, seq
        end
        return false, -1
    end

    -- Helper function to try playing a gesture by sequence name
    local function TryGestureSequence(npc, seqName, autoKill)
        local seq = npc:LookupSequence(seqName)
        if seq and seq >= 0 then
            local dur = npc:SequenceDuration(seq)
            npc:AddGestureSequence(seq, autoKill ~= false)
            if dur and dur > 0.1 then MarkGesturePlaying(npc, dur) end
            return true, seq
        end
        return false, -1
    end
    
    if testType == "flinch" then
        -- Flinch animation only (body sway is automatic from vehicle movement)
        closestNPC:AddGesture(ACT_GESTURE_FLINCH_CHEST, true)
        ply:ChatPrint("[Debug] Testing flinch gesture on " .. tostring(closestNPC))
        
    elseif testType == "gesture" then
        local gestures = {ACT_GESTURE_FLINCH_HEAD, ACT_GESTURE_FLINCH_CHEST, ACT_GESTURE_FLINCH_STOMACH}
        closestNPC:AddGesture(gestures[math.random(#gestures)], true)
        ply:ChatPrint("[Debug] Testing random gesture on " .. tostring(closestNPC))
        
    elseif testType == "drowsy" then
        if state then
            state.isDrowsy = true
            state.drowsyPhase = 0
            state.calmTime = 999
        end
        ply:ChatPrint("[Debug] Testing drowsy state on " .. tostring(closestNPC))
        timer.Simple(5, function()
            if state then
                state.isDrowsy = false
                state.calmTime = 0
            end
        end)
        
    elseif testType == "reset" then
        if state then
            state.fearLevel = 0
            state.isDrowsy = false
            state.calmTime = 0
            state.isFlinching = false
        end
        closestNPC:RestartGesture(ACT_IDLE)
        ply:ChatPrint("[Debug] Reset states on " .. tostring(closestNPC))
    end
end)

-- Debug: Set passenger status
net.Receive("NPCPassengers_SetStatus", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if not IsDebugModeEnabled() then return end
    
    local npcIndex = net.ReadInt(32)
    local status = net.ReadString()
    
    local npc = Entity(npcIndex)
    if not IsValid(npc) or not npc:IsNPC() then return end
    
    local state = npcLookState[npcIndex]
    if not state then return end
    
    -- Reset all states
    state.isDrowsy = false
    state.isAlerted = false
    state.alertLevel = 0
    state.fearLevel = 0
    state.calmTime = 0
    
    -- Set requested state
    if status == "calm" then
        -- Normal calm state
        state.calmTime = 0
    elseif status == "alert" then
        state.isAlerted = true
        state.alertLevel = 1
    elseif status == "scared" then
        state.fearLevel = 1
    elseif status == "drowsy" then
        state.isDrowsy = true
        state.drowsyPhase = 0
    elseif status == "dead" then
        -- Kill the NPC for testing
        local dmgInfo = DamageInfo()
        dmgInfo:SetDamage(npc:Health() + 100)
        dmgInfo:SetDamageType(DMG_GENERIC)
        npc:TakeDamageInfo(dmgInfo)
    end
    
    ply:ChatPrint("[NPC Passengers] Set " .. tostring(npc) .. " status to: " .. status)
end)

local function GetPassengerCount(vehicle)
    if not IsValid(vehicle) then return 0 end
    local count = 0
    for _, data in pairs(friendlyPassengers) do
        if IsValid(data.vehicle) and data.vehicle == vehicle then
            count = count + 1
        end
    end
    return count
end

local function ClearVehicleSeatCache(vehicle)
    if isnumber(vehicle) then
        vehicleSeatCache[vehicle] = nil
        return
    end

    if not IsValid(vehicle) then return end
    vehicleSeatCache[vehicle:EntIndex()] = nil
end

local function CollectLVSSeats(vehicle, seats)
    local resolver = GetLVSCompatResolver(vehicle)
    if resolver then
        local ok, customSeats = pcall(resolver, vehicle)
        if ok and istable(customSeats) and #customSeats > 0 then
            for _, seat in ipairs(customSeats) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
            return
        end
    end

    if vehicle.GetDriverSeat then
        local driverSeat = vehicle:GetDriverSeat()
        if IsValid(driverSeat) and not IsValid(driverSeat:GetDriver()) then
            seats[#seats + 1] = driverSeat
        end
    end
    if vehicle.GetPassengerSeats then
        for _, seat in pairs(vehicle:GetPassengerSeats()) do
            if IsValid(seat) then
                seats[#seats + 1] = seat
            end
        end
    end
    if vehicle.GetGunnerSeats then
        for _, seat in pairs(vehicle:GetGunnerSeats()) do
            if IsValid(seat) then
                seats[#seats + 1] = seat
            end
        end
    end
    if #seats == 0 then
        for _, child in ipairs(vehicle:GetChildren()) do
            if IsValid(child) and child:GetClass() == "prop_vehicle_prisoner_pod" then
                seats[#seats + 1] = child
            end
        end
    end
end

local function CollectVehicleSeats(vehicle)
    if not IsValid(vehicle) then return {} end

    local class = vehicle:GetClass() or ""
    local vehicleId = vehicle:EntIndex()
    local children = vehicle:GetChildren()
    local childCount = #children
    local cached = vehicleSeatCache[vehicleId]

    if cached and cached.childCount == childCount and cached.className == class then
        local seats = cached.seats
        local validSeats = true
        for index = 1, #seats do
            if not IsValid(seats[index]) then
                validSeats = false
                break
            end
        end
        if validSeats then
            return seats
        end
    end

    local seats = {}

    if vehicle.IsSimfphyscar then
        if vehicle.DriverSeat and IsValid(vehicle.DriverSeat) and not IsValid(vehicle.DriverSeat:GetDriver()) then
            seats[#seats + 1] = vehicle.DriverSeat
        end
        if vehicle.pSeat then
            for _, seat in pairs(vehicle.pSeat) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
        end
    elseif vehicle.LVS or vehicle.IsLVS or string.find(class, "lvs_") then
        CollectLVSSeats(vehicle, seats)
    elseif vehicle.IsGlideVehicle and vehicle.seats then
        for _, seat in ipairs(vehicle.seats) do
            if IsValid(seat) then
                seats[#seats + 1] = seat
            end
        end
    elseif vehicle.IsSligWolf or vehicle.sligwolf or vehicle.SligWolf or string.find(class, "sligwolf_") or string.find(class, "sw_") then
        if vehicle.GetSeats then
            for _, seat in pairs(vehicle:GetSeats()) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
        end
        if vehicle.Seats then
            for _, seat in pairs(vehicle.Seats) do
                if IsValid(seat) then
                    seats[#seats + 1] = seat
                end
            end
        end
        for _, child in ipairs(vehicle:GetChildren()) do
            if IsValid(child) then
                local childClass = child:GetClass()
                if childClass == "prop_vehicle_prisoner_pod" then
                    seats[#seats + 1] = child
                elseif string.find(childClass, "sligwolf_seat") then
                    for _, seatChild in ipairs(child:GetChildren()) do
                        if IsValid(seatChild) and seatChild:GetClass() == "prop_vehicle_prisoner_pod" then
                            seats[#seats + 1] = seatChild
                        end
                    end
                end
            end
        end
    else
        for _, child in ipairs(children) do
            if child:GetClass() == "prop_vehicle_prisoner_pod" then
                seats[#seats + 1] = child
            end
        end
    end

    table.sort(seats, function(a, b)
        local posA = vehicle:WorldToLocal(a:GetPos())
        local posB = vehicle:WorldToLocal(b:GetPos())
        return posA.x > posB.x
    end)

    vehicleSeatCache[vehicleId] = {
        seats = seats,
        childCount = childCount,
        className = class,
    }

    return seats
end

local function GetAvailableSeatCount(vehicle)
    if not IsValid(vehicle) then return 0 end
    if not IsAddonEnabled() then return 0 end
    if not IsVehicleAllowedByFilters(vehicle) then return 0 end

    local seats = CollectVehicleSeats(vehicle)
    local limit = GetVehiclePassengerLimit()
    local current = GetPassengerCount(vehicle)
    if current >= limit then return 0 end
    
    local available = 0
    for _, seat in ipairs(seats) do
        if not IsValid(seat:GetDriver()) then
            local isOccupied = false
            for npc, data in pairs(friendlyPassengers) do
                if data.seat == seat then
                    -- Don't count dead passengers as occupying seats
                    if not IsValid(npc) or npc:Health() > 0 then
                        isOccupied = true
                        break
                    end
                end
            end
            if not isOccupied then
                available = available + 1
            end
        end
    end
    
    return math.min(available, math.max(0, limit - current))
end

local function AddPendingPassenger(ply, npc)
    if not IsValid(ply) or not IsValid(npc) then return false end
    
    if not pendingPassengers[ply] then
        pendingPassengers[ply] = {}
    end
    
    for _, existingNpc in ipairs(pendingPassengers[ply]) do
        if existingNpc == npc then
            return false
        end
    end
    
    table.insert(pendingPassengers[ply], npc)
    return true
end

local function RemovePendingPassenger(ply, npc)
    if not pendingPassengers[ply] then return end
    
    for i, existingNpc in ipairs(pendingPassengers[ply]) do
        if existingNpc == npc then
            table.remove(pendingPassengers[ply], i)
            return
        end
    end
end

local function ClearPendingPassengers(ply)
    pendingPassengers[ply] = nil
end

local function GetPendingCount(ply)
    if not pendingPassengers[ply] then return 0 end
    return #pendingPassengers[ply]
end

local function CleanupNPCTimers(npc)
    local npcId
    if isnumber(npc) then
        npcId = npc
    elseif IsValid(npc) then
        npcId = npc:EntIndex()
    else
        return
    end
    
    if animationTimers[npcId] then
        timer.Remove("NPCPassengerAnim_" .. npcId)
        animationTimers[npcId] = nil
    end
end

local function GetRootVehicle(ent)
    if not IsValid(ent) then return nil end
    
    if ent.base and isentity(ent.base) and IsValid(ent.base) and ent.base.IsSimfphyscar then
        return ent.base
    end

    if ent.LVS and isentity(ent.LVS) and IsValid(ent.LVS) then
        return ent.LVS
    end
    
    if ent:GetClass() == "prop_vehicle_prisoner_pod" and IsValid(ent:GetParent()) then
        return ent:GetParent()
    end
    return ent
end

local function VehicleHasPlayer(vehicle)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:InVehicle() then
            local plyVeh = ply:GetVehicle()
            if plyVeh == vehicle then return true end
            if plyVeh:GetParent() == vehicle then return true end
            if plyVeh.base and isentity(plyVeh.base) and IsValid(plyVeh.base) and plyVeh.base == vehicle then return true end
            if plyVeh.LVS and isentity(plyVeh.LVS) and IsValid(plyVeh.LVS) and plyVeh.LVS == vehicle then return true end
        end
    end
    return false
end

local function IsFriendlyNPC(npc, vehicle)
    if not IsValid(npc) then return false end
    
    for _, ply in pairs(player.GetAll()) do
        if IsValid(ply) and (not vehicle or (ply:InVehicle() and ply:GetVehicle() == vehicle)) then
            if npc:Disposition(ply) == D_HT or npc:Disposition(ply) == D_FR then
                return false
            end
            if npc:GetEnemy() == ply then
                return false
            end
        end
    end
    
    return true
end

-- Check if a vehicle is enclosed (tank, APC, etc.) where NPCs should be hidden
local function IsEnclosedVehicle(vehicle)
    if not IsValid(vehicle) then return false end
    
    local class = vehicle:GetClass() or ""
    
    -- Check for common tank/enclosed vehicle patterns
    local enclosedPatterns = {
        -- Real-world tanks
        "tank", "apc", "ifv", "bmp", "btr", "t72", "t80", "t90", "m1a", "abrams",
        "leopard", "challenger", "merkava", "leclerc", "panzer", "tiger", "panther",
        "sherman", "churchill", "cromwell", "matilda", "kv1", "kv2", "is2", "is3",
        "pz38", "stug", "jagdpanzer", "hetzer", "marder", "sdkfz", "halftrack",
        "bradley", "warrior", "puma", "boxer", "stryker", "lav", "mrap",
        -- Star Wars vehicles
        "aat", "atst", "atrt", "juggernaut", "haat", "mtt", "spha",
        -- Generic enclosed markers
        "_enclosed", "_tank", "_armored", "_apc", "_ifv",
        -- LVS specific
        "lvs_wheeldrive_dc_tank", "lvs_tank", "lvs_tracked",
    }
    
    local lowerClass = string.lower(class)
    for _, pattern in ipairs(enclosedPatterns) do
        if string.find(lowerClass, pattern) then
            return true
        end
    end
    
    -- Check vehicle's internal flag if it has one
    if vehicle.IsEnclosed then
        return true
    end
    
    -- Check if vehicle has a tank track system (common in LVS tanks)
    if vehicle.HasTracks or vehicle.IsTank or vehicle.IsTracked then
        return true
    end
    
    -- Check for LVS tank-specific properties
    if vehicle.LVS or vehicle.IsLVS then
        -- LVS tanks often have these properties
        if vehicle.TurretPodIndex then
            -- Has a turret = likely a tank
            return true
        end
        -- Check if it's a tracked vehicle by looking for track-related methods
        if vehicle.GetTrackSpeed or vehicle.TrackSpeed then
            return true
        end
    end
    
    -- Check model name for tank patterns
    local model = vehicle:GetModel() or ""
    local lowerModel = string.lower(model)
    for _, pattern in ipairs(enclosedPatterns) do
        if string.find(lowerModel, pattern) then
            return true
        end
    end
    
    -- Check print name for tank keywords
    local printName = vehicle.PrintName or vehicle:GetNWString("PrintName", "") or ""
    local lowerPrintName = string.lower(printName)
    local tankKeywords = {"tank", "panzer", "apc", "ifv", "armored", "armoured"}
    for _, keyword in ipairs(tankKeywords) do
        if string.find(lowerPrintName, keyword) then
            return true
        end
    end
    
    return false
end

local VEHICLE_TYPE_LVS = "lvs"
local VEHICLE_TYPE_SIMFPHYS = "simfphys"
local VEHICLE_TYPE_GLIDE = "glide"
local VEHICLE_TYPE_GENERIC = "generic"
local VEHICLE_TYPE_SLIGWOLF = "sligwolf"

local VehicleOffsets = {
    [VEHICLE_TYPE_LVS] = { height = -12, right = 0, forward = 0, pitch = 0, yaw = 0, roll = 0, baseYaw = 0 },
    [VEHICLE_TYPE_SIMFPHYS] = { height = -10, right = 9, forward = 0, pitch = -4, yaw = 0, roll = 0, baseYaw = 90 },
    [VEHICLE_TYPE_GLIDE] = { height = -8, right = 14, forward = 0, pitch = -4, yaw = 0, roll = 0, baseYaw = 90 },
    [VEHICLE_TYPE_SLIGWOLF] = { height = -10, right = 0, forward = 0, pitch = 0, yaw = 0, roll = 0, baseYaw = 90 },
    [VEHICLE_TYPE_GENERIC] = { height = 12, right = 0, forward = 0, pitch = 0, yaw = 0, roll = 0, baseYaw = 90 },
}

local function GetVehicleType(vehicle)
    if not IsValid(vehicle) then return VEHICLE_TYPE_GENERIC end
    
    if vehicle.IsSimfphyscar then
        return VEHICLE_TYPE_SIMFPHYS
    elseif vehicle.LVS or vehicle.IsLVS then
        return VEHICLE_TYPE_LVS
    elseif vehicle.IsGlideVehicle or vehicle.GlideGetType or (vehicle.GetGlideClass and vehicle:GetGlideClass()) then
        return VEHICLE_TYPE_GLIDE
    elseif vehicle.IsSligWolf or vehicle.sligwolf or vehicle.SligWolf then
        return VEHICLE_TYPE_SLIGWOLF
    end
    
    local class = vehicle:GetClass()
    if class and string.find(class, "glide_") then
        return VEHICLE_TYPE_GLIDE
    elseif class and string.find(class, "lvs_") then
        return VEHICLE_TYPE_LVS
    elseif class and string.find(class, "gmod_sent_vehicle_fphysics") then
        return VEHICLE_TYPE_SIMFPHYS
    elseif class and (string.find(class, "sligwolf_") or string.find(class, "sw_")) then
        return VEHICLE_TYPE_SLIGWOLF
    end
    
    return VEHICLE_TYPE_GENERIC
end

local function GetVehicleOffsets(vehicleType)
    return VehicleOffsets[vehicleType] or VehicleOffsets[VEHICLE_TYPE_GENERIC]
end

local function CalculatePassengerPosition(vehicle, npc)
    if not IsAddonEnabled() then return nil, nil, nil, nil, nil end
    if not IsVehicleAllowedByFilters(vehicle) then return nil, nil, nil, nil, nil end

    local seats = CollectVehicleSeats(vehicle)
    local vehicleType = GetVehicleType(vehicle)
    
    if #seats == 0 then
        local passengerAttachments = {"vehicle_feet_passenger1", "vehicle_feet_passenger0", "passenger"}
        local hasPassengerAttachment = false
        for _, attachName in ipairs(passengerAttachments) do
            local attachId = vehicle:LookupAttachment(attachName)
            if attachId and attachId > 0 then
                local attachData = vehicle:GetAttachment(attachId)
                if attachData then
                    hasPassengerAttachment = true
                    local isOccupied = false
                    for _, data in pairs(friendlyPassengers) do
                        if data.vehicle == vehicle and not data.seat then
                            isOccupied = true
                            break
                        end
                    end
                    if not isOccupied then
                        return attachData.Pos, attachData.Ang, nil, vehicle, vehicleType
                    end
                end
            end
        end
        if not hasPassengerAttachment then
            return nil, nil, nil, nil, nil
        end
        return nil, nil, nil, nil, nil
    end
    
    for _, seat in ipairs(seats) do
        if not IsValid(seat:GetDriver()) then
            local isOccupied = false
            for _, data in pairs(friendlyPassengers) do
                if data.seat == seat then 
                    isOccupied = true 
                    break 
                end
            end
            
            if not isOccupied then
                local pos = seat:GetPos()
                local ang = seat:GetAngles()
                return pos, ang, nil, seat, vehicleType
            end
        end
    end
    
    return nil, nil, nil, nil, nil
end

local function SetNoTalkFlag(npc, enable)
    if not IsValid(npc) then return end
    npc:SetNWBool("NPCPassengerNoTalk", false)
    npc.NPCPassengerNoTalk = false
end

local function DisableNPCAI(npc)
    if not IsValid(npc) then return {} end
    
    local relationships = {}
    for _, ply in pairs(player.GetAll()) do
        if IsValid(ply) then
            relationships[ply] = npc:Disposition(ply)
            npc:AddEntityRelationship(ply, D_LI, 99)
        end
    end
    
    npc:SetEnemy(nil)
    npc:ClearEnemyMemory()
    
    npc:SetSchedule(SCHED_NPC_FREEZE)
    npc:StopMoving()
    npc:SetNPCState(NPC_STATE_IDLE)
    
    npc:SetSaveValue("m_bNPCFreeze", true)
    
    npc:Fire("SetReadinessLow")
    npc:Fire("DisableWeaponPickup")
    
    return relationships
end

local function EnableNPCAI(npc, relationships)
    if not IsValid(npc) then return end
    
    npc:SetSaveValue("m_bNPCFreeze", false)
    npc:Fire("EnableWeaponPickup")
    
    if relationships then
        for ply, disp in pairs(relationships) do
            if IsValid(ply) then
                npc:AddEntityRelationship(ply, disp, 99)
            end
        end
    end
    
    npc:SetNPCState(NPC_STATE_ALERT)
    npc:SetSchedule(SCHED_ALERT_STAND)
end

local function ForceSitAnimation(npc)
    if not IsValid(npc) then return end
    
    npc:SetEnemy(nil)
    npc:ClearEnemyMemory()
    npc:StopMoving()
    npc:SetSchedule(SCHED_NPC_FREEZE)
    npc:SetNPCState(NPC_STATE_IDLE)
    npc:SetSaveValue("m_bNPCFreeze", true)
    
    for _, ply in pairs(player.GetAll()) do
        if IsValid(ply) then
            npc:AddEntityRelationship(ply, D_LI, 99)
        end
    end
    
    local sitSeq = npc:LookupSequence("silo_sit")
    
    if sitSeq and sitSeq >= 0 then
        npc:ResetSequence(sitSeq)
    else
        npc:SetSaveValue("m_nSequence", npc:LookupSequence("silo_sit"))
        npc:SetSequence(npc:LookupSequence("silo_sit"))
        npc:ResetSequence(npc:LookupSequence("silo_sit"))
    end
    
    npc:SetPlaybackRate(0.0)
    npc:SetCycle(0.5)
    
    npc:SetSaveValue("m_flPlaybackRate", 0)
    npc:SetSaveValue("m_flCycle", 0.5)
    
    return sitSeq
end

-- npcLookState is defined at the top of the file

local function SmoothDamp(current, target, velocity, smoothTime, dt)
    smoothTime = math.max(0.0001, smoothTime)
    local omega = 2 / smoothTime
    local x = omega * dt
    local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
    local change = current - target
    local temp = (velocity + omega * change) * dt
    velocity = (velocity - omega * temp) * exp
    local output = target + (change + temp) * exp
    return output, velocity
end

local function InitializeLookState(npcId)
    local ct = CurTime()
    npcLookState[npcId] = {
        -- Head pose parameters
        targetYaw = 0,
        targetPitch = 5,
        currentYaw = 0,
        currentPitch = 5,
        velocityYaw = 0,
        velocityPitch = 0,
        -- Eye pose parameters
        eyeTargetYaw = 0,
        eyeTargetPitch = 5,
        eyeCurrentYaw = 0,
        eyeCurrentPitch = 5,
        eyeVelocityYaw = 0,
        eyeVelocityPitch = 0,
        -- Animation phases
        breathePhase = math.random() * math.pi * 2,
        idleSwayPhase = math.random() * math.pi * 2,
        -- Timers
        nextLookTime = ct + math.Rand(2, 4),
        nextGlanceTime = ct + math.Rand(1, 3),
        nextBlinkTime = ct + math.Rand(3, 7),
        -- Look state
        lookType = "forward",
        isBlinking = false,
        blinkEndTime = 0,
        blinkProgress = 0,
        lastTargetPos = nil,
        -- Threat tracking
        currentThreat = nil,
        threatLockTime = 0,
        isAlerted = false,
        alertLevel = 0,
        -- Behavioral states
        fearLevel = 0,
        calmTime = 0,
        isDrowsy = false,
        drowsyPhase = 0,
        -- Emotion action tracking
        lastEmotionAction = nil,
        lastActionTime = 0,
        -- Interaction
        nextAmbientSound = ct + math.Rand(20, 40),
        lastInteractionTime = 0,
        interactionTarget = nil,
        -- Gesture animation state
        nextGestureCheck = ct + math.Rand(5, 10),
        isPlayingGesture = false,
        gestureEndTime = 0,
        -- Crash flinch state
        lastVelocityMagnitude = 0,
        flinchEndTime = 0,
    }
    return npcLookState[npcId]
end

-- Emotion action values: 0=Do Nothing, 1=Exit Vehicle, 2=Play Sound, 3=Duck/Crouch, 4=Look Around, 5=Cover Face, 6=Fall Asleep
local EMOTION_ACTION_NONE = 0
local EMOTION_ACTION_EXIT = 1
local EMOTION_ACTION_SOUND = 2
local EMOTION_ACTION_DUCK = 3
local EMOTION_ACTION_LOOK = 4
local EMOTION_ACTION_COVER = 5
local EMOTION_ACTION_SLEEP = 6

-- Sound tables for emotion actions
local scaredSounds = {
    "vo/npc/male01/startle01.wav",
    "vo/npc/male01/startle02.wav",
    "vo/npc/male01/pain01.wav",
    "vo/npc/female01/startle01.wav",
    "vo/npc/female01/startle02.wav",
}

local alertSounds = {
    "vo/npc/male01/question01.wav",
    "vo/npc/male01/question05.wav",
    "vo/npc/female01/question01.wav",
    "vo/npc/female01/question06.wav",
}

-- Execute an emotion action for an NPC
local function ExecuteEmotionAction(npc, action, emotionType, state)
    if not IsValid(npc) then return end
    
    local curTime = CurTime()
    
    -- Cooldown between actions
    if curTime - (state.lastActionTime or 0) < 3 then return end
    
    -- Don't repeat the same action
    local actionKey = emotionType .. "_" .. action
    if state.lastEmotionAction == actionKey then return end
    
    state.lastEmotionAction = actionKey
    state.lastActionTime = curTime
    
    if action == EMOTION_ACTION_NONE then
        -- Do nothing
        return
        
    elseif action == EMOTION_ACTION_EXIT then
        -- Exit the vehicle
        local data = friendlyPassengers[npc]
        if data and IsValid(data.vehicle) then
            timer.Simple(0.5, function()
                if IsValid(npc) then
                    DetachNPC(npc)
                end
            end)
        end
        
    elseif action == EMOTION_ACTION_SOUND then
        -- Play an appropriate sound
        local soundTable = scaredSounds
        if emotionType == "alert" then
            soundTable = alertSounds
        end
        local snd = soundTable[math.random(#soundTable)]
        npc:EmitSound(snd, 70, math.random(95, 105))
        
    elseif action == EMOTION_ACTION_DUCK then
        -- Duck/crouch animation
        local duckAnims = {"crouch_in", "duck", "cower"}
        for _, anim in ipairs(duckAnims) do
            local seq = npc:LookupSequence(anim)
            if seq and seq > 0 then
                npc:AddGesture(seq)
                break
            end
        end
        
    elseif action == EMOTION_ACTION_LOOK then
        -- Look around frantically - rapid head movements
        if state then
            state.targetYaw = math.Rand(-60, 60)
            state.targetPitch = math.Rand(-10, 20)
            -- Queue another look
            timer.Simple(0.5, function()
                if state then
                    state.targetYaw = math.Rand(-60, 60)
                    state.targetPitch = math.Rand(-15, 15)
                end
            end)
        end
        
    elseif action == EMOTION_ACTION_COVER then
        -- Cover face with hands
        local coverAnims = {"fear", "cower", "flinch"}
        for _, anim in ipairs(coverAnims) do
            local seq = npc:LookupSequence(anim)
            if seq and seq > 0 then
                npc:AddGesture(seq)
                break
            end
        end
        
    elseif action == EMOTION_ACTION_SLEEP then
        -- Fall asleep behavior - close eyes, slow head drop
        if state then
            state.targetPitch = 25 -- Head drops forward
            state.isBlinking = true
            state.blinkProgress = 1 -- Eyes closed
            state.blinkEndTime = curTime + 999 -- Stay closed
        end
    end
end

-- Determine current emotion state and execute configured action
local function ProcessEmotionActions(npc, state, vehicle)
    if not IsValid(npc) or not state then return end
    
    local alertThreshold = NPCPassengers.cv_hud_alert_threshold:GetFloat()
    local fearThreshold = NPCPassengers.cv_hud_fear_threshold:GetFloat()
    local drowsyThreshold = NPCPassengers.cv_hud_drowsy_threshold:GetFloat()
    local drowsyTime = NPCPassengers.cv_drowsy_time:GetFloat()
    
    local alertLevel = state.alertLevel or 0
    local fearLevel = state.fearLevel or 0
    local calmRatio = drowsyTime > 0 and (state.calmTime or 0) / drowsyTime or 0
    
    -- Determine dominant emotion (highest priority: scared > alert > drowsy > calm)
    local emotion = "calm"
    local action = NPCPassengers.cv_action_calm:GetInt()
    
    if fearLevel >= fearThreshold then
        emotion = "scared"
        action = NPCPassengers.cv_action_scared:GetInt()
    elseif alertLevel >= alertThreshold then
        emotion = "alert"
        action = NPCPassengers.cv_action_alert:GetInt()
    elseif state.isDrowsy or calmRatio >= drowsyThreshold then
        emotion = "drowsy"
        action = NPCPassengers.cv_action_drowsy:GetInt()
    end
    
    -- Execute the action if it's not "do nothing"
    if action > 0 then
        ExecuteEmotionAction(npc, action, emotion, state)
    else
        -- Reset last action when calm so actions can trigger again
        if emotion == "calm" then
            state.lastEmotionAction = nil
        end
    end
end

-- Find nearest threat for head tracking
local function FindNearestThreat(npc, vehicle, range)
    if not IsValid(npc) or not IsValid(vehicle) then return nil end
    
    local npcPos = npc:GetPos()
    local nearestThreat = nil
    local nearestDist = range * range
    
    for _, ent in ipairs(ents.FindInSphere(npcPos, range)) do
        if IsValid(ent) and ent ~= npc and ent ~= vehicle then
            local dominated = false
            -- Check if it's an enemy NPC
            if ent:IsNPC() and ent:Health() > 0 then
                local disp = npc:Disposition(ent)
                if disp == D_HT or disp == D_FR then
                    local dist = npcPos:DistToSqr(ent:GetPos())
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestThreat = ent
                    end
                end
            end
        end
    end
    
    return nearestThreat
end

-- Find another passenger in the same vehicle for interaction
local function FindPassengerToInteract(npc, vehicle, friendlyPassengers)
    local candidates = {}
    for otherNpc, data in pairs(friendlyPassengers) do
        if IsValid(otherNpc) and otherNpc ~= npc and data.vehicle == vehicle then
            table.insert(candidates, otherNpc)
        end
    end
    if #candidates > 0 then
        return candidates[math.random(#candidates)]
    end
    return nil
end

local function GetRandomLookTarget(npc, vehicle, isGlance)
    local eyePos = npc:EyePos()
    local vehForward = IsValid(vehicle) and vehicle:GetForward() or npc:GetForward()
    local vehRight = IsValid(vehicle) and vehicle:GetRight() or npc:GetRight()
    
    if isGlance then
        local glanceType = math.random(1, 100)
        if glanceType <= 50 then
            local side = math.random() > 0.5 and 1 or -1
            return eyePos + vehForward * 200 + vehRight * side * 150 + Vector(0, 0, math.Rand(-30, -5)), "glance"
        else
            return eyePos + vehForward * 30 + vehRight * (math.random() > 0.5 and 40 or -40) + Vector(0, 0, math.Rand(-20, -5)), "glance"
        end
    end
    
    local lookType = math.random(1, 100)
    
    -- 15% look at player (down from 35%)
    if lookType <= 15 then
        local nearestPly = nil
        local nearestDist = math.huge
        for _, ply in pairs(player.GetAll()) do
            if IsValid(ply) and ply:InVehicle() then
                local dist = ply:GetPos():DistToSqr(npc:GetPos())
                if dist < nearestDist then
                    nearestDist = dist
                    nearestPly = ply
                end
            end
        end
        if nearestPly then
            local plyEye = nearestPly:EyePos()
            return plyEye + Vector(math.Rand(-5, 5), math.Rand(-5, 5), math.Rand(-15, -5)), "player"
        end
    -- 35% look out window (up from 20%)
    elseif lookType <= 50 then
        local side = math.random() > 0.5 and 1 or -1
        local dist = math.Rand(300, 1000)
        return eyePos + vehRight * side * dist + vehForward * math.Rand(50, 200) + Vector(0, 0, math.Rand(-50, -10)), "window"
    -- 25% look at road ahead (up from 20%)
    elseif lookType <= 75 then
        local dist = math.Rand(200, 600)
        return eyePos + vehForward * dist + Vector(0, 0, math.Rand(-50, -20)), "road"
    -- 15% zone out far ahead (up from 10%)
    elseif lookType <= 90 then
        return eyePos + vehForward * 1000 + Vector(0, 0, math.Rand(-30, 0)), "zoning"
    -- 7% look at interior
    elseif lookType <= 97 then
        return eyePos + vehForward * 35 + Vector(0, 0, -35), "interior"
    end
    
    -- 3% look at lap
    return eyePos + vehForward * 25 + Vector(0, 0, -50), "lap"
end

local function CalculateLookAngles(npc, targetPos)
    if not targetPos then return 0, -3 end
    
    local npcPos = npc:EyePos()
    local dirToTarget = (targetPos - npcPos):GetNormalized()
    local targetAng = dirToTarget:Angle()
    local npcAng = npc:GetAngles()
    
    local relativeYaw = math.AngleDifference(targetAng.y, npcAng.y)
    local relativePitch = targetAng.p + 5
    
    relativeYaw = math.Clamp(relativeYaw, -75, 75)
    relativePitch = math.Clamp(relativePitch, -10, 40)
    
    return relativeYaw, relativePitch
end

local function UpdateNPCHeadLook(npc, pdata)
    if not IsValid(npc) then return end
    
    local npcId = npc:EntIndex()
    local state = npcLookState[npcId]
    if not state then
        state = InitializeLookState(npcId)
    end
    
    local curTime = CurTime()
    local dt = FrameTime()
    if dt <= 0 then dt = 0.016 end
    
    local vehicle = pdata.vehicle
    local headSmoothTime = NPCPassengers.cv_head_smooth:GetFloat()
    local eyeSmoothTime = headSmoothTime * 0.375
    local blinkEnabled = NPCPassengers.cv_blink_enabled:GetBool()
    local breathingEnabled = NPCPassengers.cv_breathing:GetBool()
    
    -- Advanced realism settings (body sway handled client-side)
    local threatAwareness = NPCPassengers.cv_threat_awareness:GetBool()
    local threatRange = NPCPassengers.cv_threat_range:GetFloat()
    local combatAlert = NPCPassengers.cv_combat_alert:GetBool()
    local fearReactions = NPCPassengers.cv_fear_reactions:GetBool()
    local fearSpeedThreshold = NPCPassengers.cv_fear_speed_threshold:GetFloat()
    local drowsinessEnabled = NPCPassengers.cv_drowsiness:GetBool()
    local drowsyTime = NPCPassengers.cv_drowsy_time:GetFloat()
    local passengerInteraction = NPCPassengers.cv_passenger_interaction:GetBool()
    
    -- Gesture animation settings
    local talkingGestures = NPCPassengers.cv_talking_gestures:GetBool()
    local gestureChance = NPCPassengers.cv_gesture_chance:GetFloat()
    local gestureInterval = NPCPassengers.cv_gesture_interval:GetFloat()
    local crashFlinch = NPCPassengers.cv_crash_flinch:GetBool()
    local crashThreshold = NPCPassengers.cv_crash_threshold:GetFloat()
    
    -- Crash flinch detection - play HUGE flinch gesture on sudden deceleration
    if crashFlinch and IsValid(vehicle) then
        local currentVel = vehicle:GetVelocity():Length()
        local velChange = math.abs(currentVel - (state.lastVelocityMagnitude or 0))
        state.lastVelocityMagnitude = currentVel
        
        -- Detect sudden deceleration (crash)
        if velChange > crashThreshold and curTime > (state.flinchEndTime or 0) then
            state.flinchEndTime = curTime + math.Rand(1.5, 2.5)
            
            -- Calculate crash damage based on velocity change (varying per passenger)
            local baseDamage = math.Clamp((velChange - crashThreshold) / 50, 0, 30)
            local damageVariation = math.Rand(0.6, 1.4)  -- Random multiplier per passenger
            local finalDamage = baseDamage * damageVariation
            
            -- Extra damage for high speed crashes
            if currentVel > 500 then
                finalDamage = finalDamage * math.Rand(1.5, 2.0)  -- 50-100% more damage
            end
            
            -- Apply damage to NPC
            if finalDamage > 1 then
                local dmgInfo = DamageInfo()
                dmgInfo:SetDamage(finalDamage)
                dmgInfo:SetDamageType(DMG_CRUSH)
                dmgInfo:SetAttacker(vehicle)
                dmgInfo:SetInflictor(vehicle)
                npc:TakeDamageInfo(dmgInfo)
            end
            
            -- High speed crash = HUGE dramatic flinch with multiple gestures
            if currentVel > 500 then
                -- Play multiple flinch gestures for dramatic effect
                npc:AddGesture(ACT_GESTURE_FLINCH_CHEST, true)
                timer.Simple(0.1, function()
                    if IsValid(npc) then
                        npc:AddGesture(ACT_GESTURE_FLINCH_HEAD, true)
                    end
                end)
                timer.Simple(0.2, function()
                    if IsValid(npc) then
                        local seq = npc:LookupSequence("g_plead_01")
                        if seq and seq >= 0 then
                            npc:AddGestureSequence(seq, true)
                        end
                    end
                end)
            else
                -- Normal crash - single flinch
                local flinchActivities = {ACT_GESTURE_FLINCH_HEAD, ACT_GESTURE_FLINCH_CHEST, ACT_GESTURE_FLINCH_STOMACH}
                npc:AddGesture(flinchActivities[math.random(#flinchActivities)], true)
            end
        end
    end
    
    -- Talking gesture animations with HL2 citizen gestures
    if talkingGestures and curTime > (state.nextGestureCheck or 0) then
        state.nextGestureCheck = curTime + gestureInterval
        
        -- Random chance to play a gesture
        if math.random(100) <= gestureChance and curTime > (state.flinchEndTime or 0) then
            -- Idle gestures (calm, subtle movements)
            local idleGestures = {
                "g_point_l", "hg_nod_left", "hg_turnl", "idlenoise"
            }
            
            -- Talking gestures (expressive, conversation-like)
            local talkingGestures = {
                "bg_accentfwd", "bg_down", "bg_up_l", "g_fist", "g_fist_l", "g_fist_r",
                "g_fistshake", "g_head_back", "g_palm_out_high_l", "g_palm_out_high_r", "g_plead_01"
            }
            
            -- Pick gesture based on state (60% talking, 40% idle)
            local gestureList = math.random(100) <= 60 and talkingGestures or idleGestures
            local gestureName = gestureList[math.random(#gestureList)]
            
            local seq = npc:LookupSequence(gestureName)
            if seq and seq >= 0 then
                local dur = npc:SequenceDuration(seq)
                npc:AddGestureSequence(seq, true)
                if dur and dur > 0.1 then
                    MarkGesturePlaying(npc, dur)
                end
            end
        end
    end
    
    -- Clear gesture state when done
    if state.isPlayingGesture and curTime > state.gestureEndTime then
        state.isPlayingGesture = false
    end
    
    -- NOTE: Body sway is now calculated entirely on the client side for smooth interpolation
    
    -- Threat awareness - look at nearby enemies
    local threatOverride = false
    if threatAwareness and IsValid(vehicle) then
        -- Check for threats periodically
        if curTime > (state.threatLockTime or 0) then
            local threat = FindNearestThreat(npc, vehicle, threatRange)
            if IsValid(threat) then
                state.currentThreat = threat
                state.threatLockTime = curTime + math.Rand(1, 3)
                state.isAlerted = true
                state.alertLevel = math.min((state.alertLevel or 0) + 0.3, 1)
                state.calmTime = 0
            else
                state.currentThreat = nil
                state.threatLockTime = curTime + 0.5
            end
        end
        
        -- Look at current threat
        if IsValid(state.currentThreat) then
            local threatPos = state.currentThreat:EyePos()
            local yaw, pitch = CalculateLookAngles(npc, threatPos)
            state.targetYaw = yaw
            state.targetPitch = pitch
            state.eyeTargetYaw = math.Clamp(yaw * 1.1, -85, 85)
            state.eyeTargetPitch = math.Clamp(pitch * 1.1, -45, 25)
            state.lookType = "threat"
            threatOverride = true
            
            -- Combat alertness - faster head movement when alerted
            if combatAlert then
                headSmoothTime = headSmoothTime * 0.5
                eyeSmoothTime = eyeSmoothTime * 0.4
            end
        end
    end
    
    -- Decay alert level when no threats
    if not IsValid(state.currentThreat) then
        state.alertLevel = math.max((state.alertLevel or 0) - dt * 0.1, 0)
        if state.alertLevel <= 0 then
            state.isAlerted = false
        end
    end
    
    -- Fear reactions to high speed
    if fearReactions and IsValid(vehicle) then
        local speed = vehicle:GetVelocity():Length()
        if speed > fearSpeedThreshold then
            state.fearLevel = math.min((state.fearLevel or 0) + dt * 0.5, 1)
            -- Widen eyes (less blinking) and faster breathing when scared
            if state.fearLevel > 0.5 then
                blinkEnabled = false
                state.breathePhase = state.breathePhase + dt * 0.8
            end
        else
            state.fearLevel = math.max((state.fearLevel or 0) - dt * 0.2, 0)
        end
    end
    
    -- Drowsiness on calm long rides
    if drowsinessEnabled and not state.isAlerted and (state.fearLevel or 0) < 0.1 then
        state.calmTime = (state.calmTime or 0) + dt
        if state.calmTime > drowsyTime then
            state.isDrowsy = true
            state.drowsyPhase = (state.drowsyPhase or 0) + dt * 0.3
            
            -- Drowsy passengers: close eyes and stop blinking
            if blinkEnabled then
                -- Keep eyes closed (permanent blink state)
                state.isBlinking = true
                state.blinkProgress = 1  -- Fully closed
                state.nextBlinkTime = curTime + 9999  -- Don't blink while drowsy
            end
            
            -- Stop head movement - freeze current position
            headSmoothTime = 999  -- Extremely slow = essentially frozen
            eyeSmoothTime = 999
        end
    else
        -- Wake up when alerted or scared
        if state.isAlerted or (state.fearLevel or 0) >= 0.1 then
            state.isDrowsy = false
            state.calmTime = 0
        end
    end
    
    -- Passenger interaction - look at other passengers (skip if drowsy)
    if not state.isDrowsy and passengerInteraction and not threatOverride and math.random() < 0.02 and curTime > (state.lastInteractionTime or 0) + 10 then
        local otherPassenger = FindPassengerToInteract(npc, vehicle, friendlyPassengers)
        if IsValid(otherPassenger) then
            state.interactionTarget = otherPassenger
            state.lastInteractionTime = curTime
            state.nextLookTime = curTime + math.Rand(2, 5)
        end
    end
    
    -- Look at interaction target (skip if drowsy)
    if not state.isDrowsy and passengerInteraction and IsValid(state.interactionTarget) and not threatOverride then
        local targetPos = state.interactionTarget:EyePos()
        local yaw, pitch = CalculateLookAngles(npc, targetPos)
        state.targetYaw = yaw
        state.targetPitch = pitch
        state.lookType = "passenger"
        
        -- Clear interaction after look time expires
        if curTime > state.nextLookTime then
            state.interactionTarget = nil
        end
    end
    
    -- Standard blinking
    if blinkEnabled and not state.isDrowsy and curTime > state.nextBlinkTime and not state.isBlinking then
        state.isBlinking = true
        state.blinkProgress = 0
        state.blinkEndTime = curTime + math.Rand(0.1, 0.18)
        local blinkInterval = state.lookType == "player" and math.Rand(2, 4) or math.Rand(3, 7)
        -- Blink faster when alerted
        if state.isAlerted then
            blinkInterval = blinkInterval * 0.6
        end
        state.nextBlinkTime = curTime + blinkInterval
    end
    
    if state.isBlinking then
        state.blinkProgress = math.min(1, state.blinkProgress + dt * 12)
        if curTime > state.blinkEndTime then
            state.isBlinking = false
            state.blinkProgress = 0
        end
    end
    
    -- Eye glances - reduced frequency, eyes mostly follow head (skip if drowsy)
    if not state.isDrowsy and curTime > state.nextGlanceTime and not threatOverride then
        -- 70% of the time, eyes just follow head direction
        if math.random(100) <= 70 then
            state.eyeTargetYaw = state.targetYaw
            state.eyeTargetPitch = state.targetPitch
        else
            -- 30% of the time, quick glance elsewhere
            local glancePos = GetRandomLookTarget(npc, pdata.vehicle, true)
            if glancePos then
                local glanceYaw, glancePitch = CalculateLookAngles(npc, glancePos)
                state.eyeTargetYaw = glanceYaw
                state.eyeTargetPitch = glancePitch
            end
        end
        state.nextGlanceTime = curTime + math.Rand(2, 5)
    end
    
    -- Standard look target selection (skip if drowsy)
    if not state.isDrowsy and curTime > state.nextLookTime and not threatOverride and not IsValid(state.interactionTarget) then
        local targetPos, lookType = GetRandomLookTarget(npc, pdata.vehicle, false)
        state.lookType = lookType
        state.lastTargetPos = targetPos
        
        if targetPos then
            local yaw, pitch = CalculateLookAngles(npc, targetPos)
            state.targetYaw = yaw
            state.targetPitch = pitch
            -- Eyes follow head closely (same direction, not 1.1x offset)
            state.eyeTargetYaw = yaw
            state.eyeTargetPitch = pitch
        end
        
        local holdTimes = {
            player = {3, 6},
            window = {5, 12},  -- Look out window longer
            road = {3, 7},     -- Look at road longer
            zoning = {6, 15},  -- Zone out longer
            interior = {0.8, 2},
            lap = {2, 5},
            glance = {0.3, 0.8},
            threat = {1, 2},
            passenger = {2, 5},
        }
        local times = holdTimes[lookType] or {2, 4}
        state.nextLookTime = curTime + math.Rand(times[1], times[2])
    end
    
    -- Drowsy passengers: completely freeze all movement and physics
    if state.isDrowsy then
        -- Freeze at sleeping position - no updates at all
        state.targetYaw = 0
        state.targetPitch = -22
        state.eyeTargetYaw = 0
        state.eyeTargetPitch = -22
        
        -- Lock current values at sleep position
        state.currentYaw = 0
        state.currentPitch = -22
        state.eyeCurrentYaw = 0
        state.eyeCurrentPitch = -22
        
        -- Zero out all velocities to prevent drift
        state.velocityYaw = 0
        state.velocityPitch = 0
        state.eyeVelocityYaw = 0
        state.eyeVelocityPitch = 0
    else
        -- Normal passengers: calculate breathing and sway
        state.breathePhase = state.breathePhase + dt * 0.6
        state.idleSwayPhase = state.idleSwayPhase + dt * 0.2
        
        local breatheOffset = breathingEnabled and (math.sin(state.breathePhase) * 0.3) or 0
        local swayYaw = math.sin(state.idleSwayPhase) * 0.8
        local swayPitch = math.cos(state.idleSwayPhase * 0.5) * 0.4
        
        local headTargetYaw = state.targetYaw + swayYaw
        local headTargetPitch = state.targetPitch + swayPitch + breatheOffset
        
        state.currentYaw, state.velocityYaw = SmoothDamp(
            state.currentYaw, headTargetYaw, state.velocityYaw,
            headSmoothTime, dt
        )
        state.currentPitch, state.velocityPitch = SmoothDamp(
            state.currentPitch, headTargetPitch, state.velocityPitch,
            headSmoothTime, dt
        )
    end
    
    -- Only update eye position if not drowsy (already locked above)
    if not state.isDrowsy then
        state.eyeCurrentYaw, state.eyeVelocityYaw = SmoothDamp(
            state.eyeCurrentYaw, state.eyeTargetYaw, state.eyeVelocityYaw,
            eyeSmoothTime, dt
        )
        state.eyeCurrentPitch, state.eyeVelocityPitch = SmoothDamp(
            state.eyeCurrentPitch, state.eyeTargetPitch, state.eyeVelocityPitch,
            eyeSmoothTime, dt
        )
    end
    
    -- NOTE: Body sway is now handled entirely client-side for smooth interpolation
    
    -- Apply head pose parameters on server
    npc:SetPoseParameter("head_yaw", state.currentYaw)
    npc:SetPoseParameter("head_pitch", state.currentPitch)
    
    local eyeOffsetYaw = state.eyeCurrentYaw - state.currentYaw
    local eyeOffsetPitch = state.eyeCurrentPitch - state.currentPitch
    
    eyeOffsetYaw = math.Clamp(eyeOffsetYaw, -30, 30)
    eyeOffsetPitch = math.Clamp(eyeOffsetPitch, -20, 20)
    
    npc:SetPoseParameter("eyes_yaw", eyeOffsetYaw)
    npc:SetPoseParameter("eyes_pitch", eyeOffsetPitch)
    npc:SetPoseParameter("eyes_updown", eyeOffsetPitch)
    npc:SetPoseParameter("eyes_rightleft", eyeOffsetYaw)
    
    -- Drowsy passengers: eyes COMPLETELY closed (sleeping) - MAXIMUM POWER!
    if state.isDrowsy then
        npc:SetPoseParameter("blink", 10)  -- MAXIMUM eye closure (way beyond 1)
        npc:SetPoseParameter("eyes_updown", 20)  -- Force eyes fully down/closed
        npc:SetPoseParameter("eyes_rightleft", 0)  -- Center eyes
    elseif state.isBlinking then
        local blinkValue = state.blinkProgress < 0.3 and (state.blinkProgress / 0.3) or (1 - (state.blinkProgress - 0.3) / 0.7)
        npc:SetPoseParameter("blink", blinkValue)
    else
        npc:SetPoseParameter("blink", 0)
    end
    
    npc:SetPoseParameter("aim_yaw", state.currentYaw * 0.1)
    npc:SetPoseParameter("aim_pitch", state.currentPitch * 0.08)
    
    -- Set eye target for proper eye tracking
    if state.lastTargetPos and state.lookType == "player" then
        npc:SetEyeTarget(state.lastTargetPos)
    else
        local lookDir = Angle(-state.eyeCurrentPitch, npc:GetAngles().y + state.eyeCurrentYaw, 0)
        npc:SetEyeTarget(npc:EyePos() + lookDir:Forward() * 500)
    end
end

local function CleanupNPCLookState(npcId)
    npcLookState[npcId] = nil
end

-- Define StartAnimationEnforcement (forward declared at top of file)
StartAnimationEnforcement = function(npc)
    local npcId = npc:EntIndex()
    CleanupNPCTimers(npc)
    
    ForceSitAnimation(npc)
    
    local data = friendlyPassengers[npc]
    
    local sitSeq = npc:LookupSequence("silo_sit")
    if not sitSeq or sitSeq < 0 then
        local fallbacks = {"sit_ground", "sit_chair", "sit", "sitground_idle", "idle_sit", "crouch_idle_pistol"}
        for _, name in ipairs(fallbacks) do
            sitSeq = npc:LookupSequence(name)
            if sitSeq and sitSeq >= 0 then break end
        end
    end
    if not sitSeq or sitSeq < 0 then sitSeq = 0 end
    
    if npc.SetAutomaticFrameAdvance then
        npc:SetAutomaticFrameAdvance(false)
    end
    if npc.RemoveAllGestures then
        npc:RemoveAllGestures()
    end
    
    npc:ResetSequence(sitSeq)
    npc:SetCycle(0.5)
    npc:SetPlaybackRate(0)
    
    InitializeLookState(npcId)
    
    timer.Create("NPCPassengerAnim_" .. npcId, PASSENGER_ANIM_INTERVAL, 0, function()
        if not IsValid(npc) or not friendlyPassengers[npc] then
            timer.Remove("NPCPassengerAnim_" .. npcId)
            animationTimers[npcId] = nil
            CleanupNPCLookState(npcId)
            return
        end
        
        local pdata = friendlyPassengers[npc]
        if not pdata or not IsValid(pdata.vehicle) then return end

        local curTime = CurTime()

        if curTime >= (pdata.nextMaintenanceAt or 0) then
            npc:SetEnemy(nil)
            npc:ClearEnemyMemory()
            npc:StopMoving()
            npc:SetNPCState(NPC_STATE_SCRIPT)
            npc:CapabilitiesClear()
            npc:SetSaveValue("m_bNPCFreeze", true)
            npc:SetMoveType(MOVETYPE_NONE)

            if npc.SetAutomaticFrameAdvance then
                npc:SetAutomaticFrameAdvance(false)
            end

            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) then
                    npc:AddEntityRelationship(ply, D_LI, 99)
                end
            end

            pdata.nextMaintenanceAt = curTime + PASSENGER_MAINTENANCE_INTERVAL
        end
        
        -- Don't interfere with gestures while they're playing
        local npcId = npc:EntIndex()
        local state = npcLookState[npcId]
        local isPlayingGesture = state and state.isPlayingGesture and curTime < (state.gestureEndTime or 0)
        
        if not isPlayingGesture then
            if npc.RemoveAllGestures then
                npc:RemoveAllGestures()
            end
            
            if npc:GetSequence() ~= sitSeq then
                npc:ResetSequence(sitSeq)
            end
            
            npc:SetCycle(0.5)
            npc:SetPlaybackRate(0)
        end
        
        -- Head/eye looking behavior (can be disabled in settings)
        if NPCPassengers.cv_head_look:GetBool() and curTime >= (pdata.nextHeadLookAt or 0) then
            UpdateNPCHeadLook(npc, pdata)
            pdata.nextHeadLookAt = curTime + PASSENGER_HEADLOOK_INTERVAL
        end

        local expectedParent = pdata.seat or pdata.vehicle
        local shouldSyncTransform = npc:GetParent() ~= expectedParent or curTime >= (pdata.nextTransformSyncAt or 0)

        if shouldSyncTransform and IsValid(expectedParent) then
            if npc:GetParent() ~= expectedParent then
                npc:SetParent(expectedParent)
            end

            local basePos = pdata.baseLocalPos or Vector(0,0,0)
            local vehOffsets = GetVehicleOffsets(pdata.vehicleType or VEHICLE_TYPE_GENERIC)

            local baseAng
            if pdata.vehicleType == VEHICLE_TYPE_LVS and IsValid(pdata.vehicle) then
                local vehicleForwardAng = pdata.vehicle:GetAngles()
                baseAng = expectedParent:WorldToLocalAngles(vehicleForwardAng)
            else
                baseAng = pdata.baseLocalAng or Angle(0,0,0)
            end

            local offsetPos = Vector(
                vehOffsets.forward + NPCPassengers.cv_forward_offset:GetFloat(),
                vehOffsets.right + NPCPassengers.cv_right_offset:GetFloat(),
                vehOffsets.height + NPCPassengers.cv_height_offset:GetFloat()
            )
            npc:SetLocalPos(basePos + offsetPos)
            
            local offsetAng = Angle(
                vehOffsets.pitch + NPCPassengers.cv_pitch_offset:GetFloat(),
                vehOffsets.baseYaw + vehOffsets.yaw + NPCPassengers.cv_yaw_offset:GetFloat(),
                vehOffsets.roll + NPCPassengers.cv_roll_offset:GetFloat()
            )
            npc:SetLocalAngles(baseAng + offsetAng)

            pdata.nextTransformSyncAt = curTime + PASSENGER_TRANSFORM_SYNC_INTERVAL
        end
    end)
    
    animationTimers[npcId] = true
end

local function VehicleHasNPCAttached(vehicle)
    if not IsValid(vehicle) then return false end
    for _, data in pairs(friendlyPassengers) do
        if IsValid(data.vehicle) and data.vehicle == vehicle then
            return true
        end
    end
    return false
end

local function WalkNPCToVehicle(npc, vehicle, callback)
    if not IsValid(npc) or not IsValid(vehicle) then 
        if callback then callback(false) end
        return 
    end

    if IsNPCBoardCooldownActive(npc) then
        if callback then callback(false) end
        return
    end
    
    local vehiclePos = vehicle:GetPos()
    local vehicleRight = vehicle:GetRight()
    local targetPos = vehiclePos + vehicleRight * 80
    local enterDistance = NPCPassengers.GetConVarFloat and NPCPassengers.GetConVarFloat("nai_npc_enter_distance", 80) or 80
    
    local dist = npc:GetPos():Distance(targetPos)
    
    if dist > NPCPassengers.cv_max_dist:GetFloat() then
        if callback then callback(true) end
        return
    end
    
    if dist < enterDistance then
        if callback then callback(true) end
        return
    end
    
    npc:SetLastPosition(targetPos)
    npc:SetSchedule(SCHED_FORCED_GO)
    
    local npcId = npc:EntIndex()
    local startTime = CurTime()
    local maxWalkTime = NPCPassengers.cv_walk_timeout:GetFloat()
    
    timer.Create("NPCPassengerWalk_" .. npcId, 0.2, 0, function()
        if not IsValid(npc) or not IsValid(vehicle) then
            timer.Remove("NPCPassengerWalk_" .. npcId)
            if callback then callback(false) end
            return
        end
        
        if CurTime() - startTime > maxWalkTime then
            timer.Remove("NPCPassengerWalk_" .. npcId)
            if callback then callback(false) end
            return
        end
        
        local currentDist = npc:GetPos():Distance(targetPos)
        if currentDist < enterDistance then
            timer.Remove("NPCPassengerWalk_" .. npcId)
            npc:StopMoving()
            if callback then callback(true) end
            return
        end
        
        if npc:IsCurrentSchedule(SCHED_IDLE_STAND) or npc:IsCurrentSchedule(SCHED_ALERT_STAND) then
            npc:SetLastPosition(targetPos)
            npc:SetSchedule(SCHED_FORCED_GO)
        end
    end)
end

local function AttachNPCToVehicle(npc, vehicle, skipPlayerCheck)
    if not IsValid(npc) or not IsValid(vehicle) then return false end
    if not IsAddonEnabled() then return false end
    if not IsVehicleAllowedByFilters(vehicle) then return false end
    if not skipPlayerCheck and not VehicleHasPlayer(vehicle) then return false end
    if friendlyPassengers[npc] or npc:Health() <= 0 then return false end
    if IsNPCBoardCooldownActive(npc) then return false end

    local maxPassengers = GetVehiclePassengerLimit()
    if GetPassengerCount(vehicle) >= maxPassengers then
        return false
    end
    
    local vehicleId = vehicle:EntIndex()
    
    if not NPCPassengers.cv_multiple:GetBool() and VehicleHasNPCAttached(vehicle) then
        return false
    end
    
    if vehicleCooldowns[vehicleId] and CurTime() - vehicleCooldowns[vehicleId] < NPCPassengers.cv_cooldown:GetFloat() then
        return false
    end
    
    local passengerPos, passengerAng, settings, parentEntity, vehicleType = CalculatePassengerPosition(vehicle, npc)
    if not passengerPos then return false end
    
    local originalCollision = npc:GetCollisionGroup()
    if originalCollision == COLLISION_GROUP_IN_VEHICLE then
        originalCollision = COLLISION_GROUP_NPC
    end
    
    local parent = parentEntity or vehicle
    
    npc:SetParent(parent)
    
    local baseLocalPos = parent:WorldToLocal(passengerPos)
    local baseLocalAng
    
    if vehicleType == VEHICLE_TYPE_LVS then
        local vehicleForwardAng = vehicle:GetAngles()
        baseLocalAng = parent:WorldToLocalAngles(vehicleForwardAng)
    else
        baseLocalAng = parent:WorldToLocalAngles(passengerAng)
    end
    
    local vehOffsets = GetVehicleOffsets(vehicleType)
    
    local offsetPos = Vector(
        vehOffsets.forward + NPCPassengers.cv_forward_offset:GetFloat(),
        vehOffsets.right + NPCPassengers.cv_right_offset:GetFloat(),
        vehOffsets.height + NPCPassengers.cv_height_offset:GetFloat()
    )
    npc:SetLocalPos(baseLocalPos + offsetPos)
    
    local offsetAng = Angle(
        vehOffsets.pitch + NPCPassengers.cv_pitch_offset:GetFloat(),
        vehOffsets.baseYaw + vehOffsets.yaw + NPCPassengers.cv_yaw_offset:GetFloat(),
        vehOffsets.roll + NPCPassengers.cv_roll_offset:GetFloat()
    )
    npc:SetLocalAngles(baseLocalAng + offsetAng)
    
    npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    npc:SetMoveType(MOVETYPE_NONE)
    npc:SetSolid(SOLID_NONE)
    npc:SetNotSolid(true)
    
    -- Hide NPC if inside an enclosed vehicle (tank, APC, etc.) and setting is enabled
    local isEnclosed = NPCPassengers.cv_hide_in_tanks:GetBool() and IsEnclosedVehicle(vehicle)
    if isEnclosed then
        -- Multiple methods to ensure NPC is hidden
        npc:SetNoDraw(true)
        npc:SetRenderMode(RENDERMODE_NONE)
        npc:DrawShadow(false)
        npc:SetColor(Color(255, 255, 255, 0))
        -- Also set render FX
        npc:SetRenderFX(kRenderFxNone)
        -- Network the visibility state
        npc:SetNWBool("NPCPassengerHidden", true)
    else
        npc:SetNoDraw(false)
    end
    
    if npc.PhysicsDestroy then
        npc:PhysicsDestroy()
    end
    local phys = npc:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableCollisions(false)
        phys:Sleep()
    end
    
    npc:SetNPCState(NPC_STATE_IDLE)
    
    SetNoTalkFlag(npc, true)
    local relationships = DisableNPCAI(npc)
    ForceSitAnimation(npc)
    StartAnimationEnforcement(npc)
    
    -- Mark as passenger for client-side bone manipulation
    npc:SetNWBool("IsNPCPassenger", true)
    
    friendlyPassengers[npc] = {
        vehicle = vehicle,
        seat = (parentEntity ~= vehicle) and parentEntity or nil,
        npcId = npc:EntIndex(),
        originalCollision = originalCollision,
        settings = settings,
        lastAngleCheck = CurTime(),
        capabilities = npc:CapabilitiesGet(),
        relationships = relationships,
        baseLocalPos = baseLocalPos,
        baseLocalAng = baseLocalAng,
        vehicleType = vehicleType,
        lastVelocity = Vector(0, 0, 0),
        lastHurtSound = 0,
        lastIdleChatter = CurTime() + 10,
        isHidden = isEnclosed
    }
    
    vehicleCooldowns[vehicleId] = CurTime()
    RegisterBoardSuccess(npc)
    
    -- DISABLED: Register NPC as turret gunner for LVS vehicles
    --[[ LVS TURRET DISABLED
    if vehicleType == VEHICLE_TYPE_LVS and NPCPassengers.RegisterTurretNPC then
        timer.Simple(0.1, function()
            if IsValid(npc) and friendlyPassengers[npc] then
                NPCPassengers.RegisterTurretNPC(npc, friendlyPassengers[npc])
            end
        end)
    end
    --]]
    
    -- Register NPC as driver if in driver seat
    if NPCPassengers.RegisterDriverNPC then
        timer.Simple(0.1, function()
            if IsValid(npc) and friendlyPassengers[npc] then
                NPCPassengers.RegisterDriverNPC(npc, vehicle, parentEntity)
            end
        end)
    end
    
    -- Boarding sound
    if NPCPassengers.cv_speech_enabled:GetBool() and NPCPassengers.cv_speech_board_enabled:GetBool() then
        timer.Simple(0.3, function()
            if not IsValid(npc) then return end
            local model = npc:GetModel() or ""
            local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
            local boardSounds = isFemale and {
                "vo/npc/female01/ok01.wav",
                "vo/npc/female01/ok02.wav",
                "vo/npc/female01/lead01.wav",
                "vo/npc/female01/lead02.wav",
                "vo/npc/female01/allrightletmove.wav",
                "vo/npc/female01/letsgo01.wav",
                "vo/npc/female01/letsgo02.wav",
            } or {
                "vo/npc/male01/ok01.wav",
                "vo/npc/male01/ok02.wav",
                "vo/npc/male01/lead01.wav",
                "vo/npc/male01/lead02.wav",
                "vo/npc/male01/allrightletsmove01.wav",
                "vo/npc/male01/letsgo01.wav",
                "vo/npc/male01/letsgo02.wav",
            }
            local vol = NPCPassengers.cv_speech_volume:GetFloat()
            local pitchVar = NPCPassengers.cv_speech_pitch_variation:GetInt()
            local pitch = 100 + math.random(-pitchVar, pitchVar)
            npc:EmitSound(boardSounds[math.random(#boardSounds)], vol, pitch)
        end)
    end
    
    return true
end

DetachNPC = function(npc)
    if not IsValid(npc) or not friendlyPassengers[npc] then return false end
    
    local data = friendlyPassengers[npc]
    
    -- Exit sound (before detaching while NPC is still valid)
    if NPCPassengers.cv_speech_enabled:GetBool() and NPCPassengers.cv_speech_board_enabled:GetBool() then
        local model = npc:GetModel() or ""
        local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
        local exitSounds = isFemale and {
            "vo/npc/female01/yeah02.wav",
            "vo/npc/female01/finally.wav",
            "vo/npc/female01/answer37.wav",
            "vo/npc/female01/readywhenyouare01.wav",
            "vo/npc/female01/readywhenyouare02.wav",
        } or {
            "vo/npc/male01/yeah02.wav",
            "vo/npc/male01/finally.wav",
            "vo/npc/male01/answer37.wav",
            "vo/npc/male01/readywhenyouare01.wav",
            "vo/npc/male01/readywhenyouare02.wav",
        }
        local vol = NPCPassengers.cv_speech_volume:GetFloat()
        local pitchVar = NPCPassengers.cv_speech_pitch_variation:GetInt()
        local pitch = 100 + math.random(-pitchVar, pitchVar)
        npc:EmitSound(exitSounds[math.random(#exitSounds)], vol, pitch)
    end
    
    -- DISABLED: Unregister from turret control
    --[[ LVS TURRET DISABLED
    if NPCPassengers.UnregisterTurretNPC then
        NPCPassengers.UnregisterTurretNPC(npc)
    end
    --]]
    
    -- Unregister from driver control
    if NPCPassengers.UnregisterDriverNPC then
        NPCPassengers.UnregisterDriverNPC(npc)
    end
    
    timer.Remove("NPCPassengerAnim_" .. data.npcId)
    animationTimers[data.npcId] = nil
    CleanupNPCLookState(data.npcId)
    
    SetNoTalkFlag(npc, false)
    EnableNPCAI(npc, data.relationships)
    
    if npc:GetParent() then
        npc:SetParent(nil)
    end
    
    local originalCollision = data.originalCollision or COLLISION_GROUP_NPC
    npc:SetCollisionGroup(originalCollision)
    npc:SetNotSolid(false)
    
    -- Restore visibility if NPC was hidden
    npc:SetNoDraw(false)
    npc:SetRenderMode(RENDERMODE_NORMAL)
    npc:DrawShadow(true)
    npc:SetColor(Color(255, 255, 255, 255))
    npc:SetNWBool("NPCPassengerHidden", false)
    
    local phys = npc:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableCollisions(true)
        phys:Wake()
    end
    
    if npc.SetAutomaticFrameAdvance then
        npc:SetAutomaticFrameAdvance(true)
    end
    
    npc:SetMoveType(MOVETYPE_STEP)
    npc:SetSolid(SOLID_BBOX)
    npc:SetAngles(Angle(0, 0, 0))
    npc:SetPlaybackRate(1.0)
    npc:ResetSequence(npc:LookupSequence("idle_subtle") or npc:LookupSequence("idle") or 0)
    
    if data.capabilities then
        npc:CapabilitiesClear()
        npc:CapabilitiesAdd(data.capabilities)
    end
    
    if IsValid(data.vehicle) then
        local vehicle = data.vehicle
        local center = vehicle:LocalToWorld(vehicle:OBBCenter())
        local right = vehicle:GetRight()
        local forward = vehicle:GetForward()
        local width = vehicle:OBBMaxs().y - vehicle:OBBMins().y
        local length = vehicle:OBBMaxs().x - vehicle:OBBMins().x
        
        local dist = (width / 2) + 45
        local candidates = {
            center + right * dist,
            center - right * dist,
            center - forward * ((length / 2) + 45)
        }
        
        local foundPos = nil
        for _, pos in ipairs(candidates) do
            local tr = util.TraceHull({
                start = pos + Vector(0, 0, 10),
                endpos = pos + Vector(0, 0, 10),
                mins = npc:OBBMins(),
                maxs = npc:OBBMaxs(),
                filter = {vehicle, npc, unpack(vehicle:GetChildren())}
            })
            if not tr.Hit then
                foundPos = pos
                break
            end
        end
        
        if foundPos then
            npc:SetPos(foundPos)
        end
    end
    
    -- Clear passenger flag for client-side cleanup
    npc:SetNWBool("IsNPCPassenger", false)
    
    friendlyPassengers[npc] = nil
    
    return true
end

hook.Add("Think", "NPCPassengerThink", function()
    local enabled = IsAddonEnabled()
    if not enabled then
        if addonWasEnabled then
            ResetPassengerState("addon_disabled")
            addonWasEnabled = false
        end
        return
    end
    addonWasEnabled = true

    local passengersCopy = {}
    for npc, data in pairs(friendlyPassengers) do
        passengersCopy[npc] = data
    end
    
    local curTime = CurTime()
    
    -- Speech settings cache
    local speechEnabled = NPCPassengers.cv_speech_enabled:GetBool()
    local speechVolume = NPCPassengers.cv_speech_volume:GetFloat()
    local crashEnabled = speechEnabled and NPCPassengers.cv_speech_crash_enabled:GetBool()
    local crashThreshold = NPCPassengers.cv_speech_crash_threshold:GetFloat()
    local crashCooldown = NPCPassengers.cv_speech_crash_cooldown:GetFloat()
    local pitchVar = NPCPassengers.cv_speech_pitch_variation:GetInt()
    local idleEnabled = speechEnabled and NPCPassengers.cv_speech_idle_enabled:GetBool()
    local idleChance = NPCPassengers.cv_speech_idle_chance:GetFloat()
    local idleInterval = NPCPassengers.cv_speech_idle_interval:GetFloat()
    
    -- Advanced realism settings cache
    local ambientEnabled = speechEnabled and NPCPassengers.cv_ambient_sounds:GetBool()
    local ambientInterval = NPCPassengers.cv_ambient_interval:GetFloat()
    local fearReactions = NPCPassengers.cv_fear_reactions:GetBool()
    local fearSpeedThreshold = NPCPassengers.cv_fear_speed_threshold:GetFloat()
    
    for npc, data in pairs(passengersCopy) do
        if not IsValid(npc) or npc:Health() <= 0 then
            friendlyPassengers[npc] = nil
            CleanupNPCTimers(npc)
            if animationTimers[npc:EntIndex()] then
                animationTimers[npc:EntIndex()] = nil
            end
        elseif not IsValid(data.vehicle) then
            DetachNPC(npc)
        elseif not IsFriendlyNPC(npc, data.vehicle) then
            DetachNPC(npc)
        else
            if not npc:GetParent() then
                npc:SetParent(data.vehicle)
            end
            
            -- Ensure hidden NPCs stay hidden
            if data.isHidden and npc:GetNoDraw() == false then
                npc:SetNoDraw(true)
                npc:SetRenderMode(RENDERMODE_NONE)
                npc:DrawShadow(false)
            end
            
            -- Dead passengers glow RED for visibility
            if npc:Health() <= 0 then
                npc:SetColor(Color(255, 50, 50))
                npc:SetRenderMode(RENDERMODE_TRANSCOLOR)
                npc:SetRenderFX(kRenderFxGlowShell)
            else
                -- Alive passengers - normal appearance
                if npc:GetColor() ~= Color(255, 255, 255) then
                    npc:SetColor(Color(255, 255, 255))
                    npc:SetRenderMode(RENDERMODE_NORMAL)
                    npc:SetRenderFX(kRenderFxNone)
                end
            end
            
            local currentVel = data.vehicle:GetVelocity()
            local lastVel = data.lastVelocity or Vector(0, 0, 0)
            local decel = (lastVel - currentVel):Length()
            data.lastVelocity = currentVel
            
            -- Crash reaction sounds using NPC hurt sounds
            if crashEnabled and decel > crashThreshold and curTime - (data.lastHurtSound or 0) > crashCooldown then
                data.lastHurtSound = curTime
                
                -- Play NPC's actual hurt sound (not voice lines)
                npc:EmitSound("NPC.Pain", speechVolume, 100 + math.random(-pitchVar, pitchVar))
            end
            
            -- Idle chatter (disabled when drowsy - sleeping passengers don't talk)
            local state = npcLookState[npc:EntIndex()]
            if idleEnabled and not (state and state.isDrowsy) and curTime - (data.lastIdleChatter or 0) > idleInterval then
                if math.random() < idleChance then
                    data.lastIdleChatter = curTime
                    local model = npc:GetModel() or ""
                    local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
                    
                    local idleSounds = isFemale and {
                        "vo/npc/female01/answer14.wav",
                        "vo/npc/female01/answer20.wav",
                        "vo/npc/female01/hi01.wav",
                        "vo/npc/female01/hi02.wav",
                        "vo/npc/female01/yeah02.wav",
                        "vo/npc/female01/nice.wav",
                        "vo/npc/female01/fantastic01.wav",
                        "vo/npc/female01/fantastic02.wav",
                        "vo/npc/female01/gordead_ques05.wav",
                        "vo/npc/female01/question01.wav",
                        "vo/npc/female01/question06.wav",
                        "vo/npc/female01/question13.wav",
                        "vo/npc/female01/waitingsomebody.wav",
                    } or {
                        "vo/npc/male01/answer14.wav",
                        "vo/npc/male01/answer20.wav",
                        "vo/npc/male01/hi01.wav",
                        "vo/npc/male01/hi02.wav",
                        "vo/npc/male01/yeah02.wav",
                        "vo/npc/male01/nice.wav",
                        "vo/npc/male01/fantastic01.wav",
                        "vo/npc/male01/fantastic02.wav",
                        "vo/npc/male01/gordead_ques05.wav",
                        "vo/npc/male01/question01.wav",
                        "vo/npc/male01/question06.wav",
                        "vo/npc/male01/question13.wav",
                        "vo/npc/male01/waitingsomebody.wav",
                    }
                    
                    local pitch = 100 + math.random(-pitchVar, pitchVar)
                    npc:EmitSound(idleSounds[math.random(#idleSounds)], speechVolume * 0.8, pitch)
                else
                    data.lastIdleChatter = curTime - (idleInterval * 0.5)
                end
            end
            
            -- Ambient sounds (coughs, sighs, hums, etc.) - disabled when drowsy
            if ambientEnabled and not (state and state.isDrowsy) and curTime > (data.nextAmbientSound or 0) then
                data.nextAmbientSound = curTime + ambientInterval + math.Rand(-ambientInterval * 0.3, ambientInterval * 0.5)
                local model = npc:GetModel() or ""
                local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
                
                local ambientSounds = isFemale and {
                    "vo/npc/female01/uhuh.wav",
                    "vo/npc/female01/um01.wav",
                    "vo/npc/female01/answer29.wav",
                    "vo/npc/female01/answer30.wav",
                    "ambient/voices/cough1.wav",
                    "ambient/voices/cough2.wav",
                    "ambient/voices/cough3.wav",
                } or {
                    "vo/npc/male01/uhuh.wav",
                    "vo/npc/male01/um01.wav",
                    "vo/npc/male01/answer29.wav",
                    "vo/npc/male01/answer30.wav",
                    "ambient/voices/cough1.wav",
                    "ambient/voices/cough2.wav",
                    "ambient/voices/cough3.wav",
                    "ambient/voices/cough4.wav",
                }
                
                local pitch = 100 + math.random(-pitchVar, pitchVar)
                npc:EmitSound(ambientSounds[math.random(#ambientSounds)], speechVolume * 0.5, pitch)
            end
            
            -- Fear reaction sounds (scared by high speed)
            if fearReactions and speechEnabled then
                local speed = data.vehicle:GetVelocity():Length()
                local npcId = npc:EntIndex()
                local state = npcLookState[npcId]
                
                if state and (state.fearLevel or 0) > 0.7 and curTime > (data.lastFearSound or 0) + 5 then
                    data.lastFearSound = curTime
                    local model = npc:GetModel() or ""
                    local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
                    
                    local fearSounds = isFemale and {
                        "vo/npc/female01/ohno.wav",
                        "vo/npc/female01/no01.wav",
                        "vo/npc/female01/no02.wav",
                        "vo/npc/female01/runforyourlife01.wav",
                        "vo/npc/female01/runforyourlife02.wav",
                        "vo/npc/female01/runforyourlife03.wav",
                        "vo/npc/female01/watchout.wav",
                        "vo/npc/female01/help01.wav",
                    } or {
                        "vo/npc/male01/ohno.wav",
                        "vo/npc/male01/no01.wav",
                        "vo/npc/male01/no02.wav",
                        "vo/npc/male01/runforyourlife01.wav",
                        "vo/npc/male01/runforyourlife02.wav",
                        "vo/npc/male01/runforyourlife03.wav",
                        "vo/npc/male01/watchout.wav",
                        "vo/npc/male01/help01.wav",
                    }
                    
                    local pitch = 100 + math.random(-pitchVar, pitchVar)
                    npc:EmitSound(fearSounds[math.random(#fearSounds)], speechVolume, pitch)
                end
                
                -- Combat alert sounds (when threat detected)
                if state and state.isAlerted and curTime > (data.lastAlertSound or 0) + 8 then
                    data.lastAlertSound = curTime
                    local model = npc:GetModel() or ""
                    local isFemale = string.find(model, "female") or string.find(model, "alyx") or string.find(model, "mossman")
                    
                    local alertSounds = isFemale and {
                        "vo/npc/female01/upthere01.wav",
                        "vo/npc/female01/upthere02.wav",
                        "vo/npc/female01/overhere01.wav",
                        "vo/npc/female01/gethellout.wav",
                        "vo/npc/female01/getdown02.wav",
                        "vo/npc/female01/headsup01.wav",
                        "vo/npc/female01/headsup02.wav",
                        "vo/npc/female01/incoming02.wav",
                    } or {
                        "vo/npc/male01/upthere01.wav",
                        "vo/npc/male01/upthere02.wav",
                        "vo/npc/male01/overhere01.wav",
                        "vo/npc/male01/gethellout.wav",
                        "vo/npc/male01/getdown02.wav",
                        "vo/npc/male01/headsup01.wav",
                        "vo/npc/male01/headsup02.wav",
                        "vo/npc/male01/incoming02.wav",
                    }
                    
                    local pitch = 100 + math.random(-pitchVar, pitchVar)
                    npc:EmitSound(alertSounds[math.random(#alertSounds)], speechVolume, pitch)
                end
            end
            
            if data.settings and (curTime - (data.lastAngleCheck or 0)) > 0.5 then
                if npc:GetParent() == data.vehicle then
                    local currentAng = npc:GetLocalAngles()
                    local targetYaw = data.settings.angleAdjust.yaw
                    
                    if math.abs(math.AngleDifference(currentAng.yaw, targetYaw)) > 5 then
                        npc:SetLocalAngles(Angle(0, targetYaw, 0))
                    end
                end
                data.lastAngleCheck = CurTime()
            end
            
            -- Update NW variables for HUD (emotions/states)
            local npcId = npc:EntIndex()
            local state = npcLookState[npcId]
            if state then
                npc:SetNWFloat("NPCPassengerAlertLevel", state.alertLevel or 0)
                npc:SetNWFloat("NPCPassengerFearLevel", state.fearLevel or 0)
                npc:SetNWBool("NPCPassengerIsDrowsy", state.isDrowsy or false)
                npc:SetNWFloat("NPCPassengerCalmTime", state.calmTime or 0)
                
                -- Process emotion-triggered actions
                ProcessEmotionActions(npc, state, data.vehicle)
            end
        end
    end
end)

hook.Add("PlayerEnteredVehicle", "NPCPassengerAttach", function(ply, vehicle)
    if not IsAddonEnabled() then return end
    timer.Simple(0.05, function()
        if not IsValid(ply) or not IsValid(vehicle) then return end
        
        local rootVehicle = GetRootVehicle(vehicle)
        if not IsValid(rootVehicle) or not VehicleHasPlayer(rootVehicle) then return end
        if not IsVehicleAllowedByFilters(rootVehicle) then return end
        
        local pending = pendingPassengers[ply]
        if not pending or #pending == 0 then return end
        
        local allowMultiple = NPCPassengers.cv_multiple:GetBool()
        local toProcess = {}
        
        for i = #pending, 1, -1 do
            local npc = pending[i]
            if IsValid(npc) and not friendlyPassengers[npc] and npc:Health() > 0 then
                table.insert(toProcess, npc)
                table.remove(pending, i)
            else
                table.remove(pending, i)
            end
        end
        
        if #pending == 0 then
            pendingPassengers[ply] = nil
        end
        
        local function ProcessNextNPC(index)
            if index > #toProcess then return end
            
            local npc = toProcess[index]
            if not IsValid(npc) or not IsValid(rootVehicle) then
                ProcessNextNPC(index + 1)
                return
            end

            if IsNPCBoardCooldownActive(npc) then
                ProcessNextNPC(index + 1)
                return
            end
            
            if not allowMultiple and VehicleHasNPCAttached(rootVehicle) then
                return
            end
            
            WalkNPCToVehicle(npc, rootVehicle, function(success)
                if success and IsValid(npc) and IsValid(rootVehicle) then
                    if not allowMultiple and VehicleHasNPCAttached(rootVehicle) then
                        return
                    end
                    local attached = AttachNPCToVehicle(npc, rootVehicle)
                    if attached and IsValid(ply) then
                        local total = GetPassengerCount(rootVehicle)
                        local msg = Phrase("passenger_boarded", total)
                        ply:ChatPrint(msg)
                        SendClientCue(ply, true, msg)
                    else
                        local cooldownStarted = RegisterBoardFailure(npc)
                        if IsValid(ply) then
                            local failMsg = cooldownStarted and Phrase("passenger_cooldown") or Phrase("passenger_attach_failed")
                            SendClientCue(ply, false, failMsg)
                        end
                    end
                elseif IsValid(npc) and IsValid(ply) then
                    local cooldownStarted = RegisterBoardFailure(npc)
                    local failMsg = cooldownStarted and Phrase("passenger_cooldown") or Phrase("passenger_attach_failed")
                    SendClientCue(ply, false, failMsg)
                end
                ProcessNextNPC(index + 1)
            end)
        end
        
        ProcessNextNPC(1)
    end)
end)

--[[
    Auto-join: Friendly NPCs automatically board vehicles when player enters
]]
hook.Add("PlayerEnteredVehicle", "NPCPassengerAutoJoin", function(ply, vehicle)
    if not IsAddonEnabled() then return end
    -- Check if auto-join is enabled
    if not NPCPassengers.cv_auto_join:GetBool() then return end
    
    timer.Simple(0.2, function()
        if not IsValid(ply) or not IsValid(vehicle) then return end
        
        local rootVehicle = GetRootVehicle(vehicle)
        if not IsValid(rootVehicle) then return end
        if not IsVehicleAllowedByFilters(rootVehicle) then return end
        
        local allowMultiple = NPCPassengers.cv_multiple:GetBool()
        local maxAutoJoin = NPCPassengers.cv_auto_join_max:GetInt()
        local autoJoinRange = NPCPassengers.cv_auto_join_range:GetFloat()
        local squadOnly = NPCPassengers.cv_auto_join_squad_only:GetBool()
        
        -- Get available seat count
        local availableSeats = GetAvailableSeatCount(rootVehicle)
        if availableSeats <= 0 then return end
        
        -- If multiple passengers not allowed and already have one, skip
        if not allowMultiple and GetPassengerCount(rootVehicle) > 0 then return end
        
        -- Find nearby friendly NPCs
        local playerPos = ply:GetPos()
        local friendlyNPCs = {}
        
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) and npc:IsNPC() and npc:Health() > 0 then
                -- Skip if already a passenger
                if friendlyPassengers[npc] then continue end
                
                -- Skip if already pending
                local isPending = false
                if pendingPassengers[ply] then
                    for _, pendingNpc in ipairs(pendingPassengers[ply]) do
                        if pendingNpc == npc then
                            isPending = true
                            break
                        end
                    end
                end
                if isPending then continue end
                
                -- Check distance
                local dist = playerPos:Distance(npc:GetPos())
                if dist > autoJoinRange then continue end
                
                -- Check if friendly to player
                if not IsFriendlyNPC(npc, nil) then continue end
                
                -- Check disposition directly
                local disposition = npc:Disposition(ply)
                if disposition ~= D_LI and disposition ~= D_NU then continue end
                
                -- Squad check if enabled
                if squadOnly then
                    local npcSquad = npc:GetSquad()
                    if not npcSquad or npcSquad == "" or npcSquad == "none" then
                        continue
                    end
                end
                
                table.insert(friendlyNPCs, {
                    npc = npc,
                    distance = dist
                })
            end
        end
        
        -- Sort by distance (closest first)
        table.sort(friendlyNPCs, function(a, b)
            return a.distance < b.distance
        end)
        
        -- Limit to max auto-join and available seats
        local toJoin = math.min(#friendlyNPCs, maxAutoJoin, availableSeats)
        if toJoin <= 0 then return end
        
        -- Process NPCs sequentially
        local joinedCount = 0
        
        local function ProcessAutoJoin(index)
            if index > toJoin then
                if joinedCount > 0 and IsValid(ply) then
                    ply:ChatPrint(joinedCount .. " friendly NPC(s) are joining your vehicle!")
                end
                return
            end
            
            local npcData = friendlyNPCs[index]
            if not npcData or not IsValid(npcData.npc) or not IsValid(rootVehicle) then
                ProcessAutoJoin(index + 1)
                return
            end
            
            local npc = npcData.npc
            if IsNPCBoardCooldownActive(npc) then
                ProcessAutoJoin(index + 1)
                return
            end
            
            -- Check again that we have space
            if not allowMultiple and GetPassengerCount(rootVehicle) > 0 then
                return
            end
            
            -- Walk NPC to vehicle and attach
            WalkNPCToVehicle(npc, rootVehicle, function(success)
                if success and IsValid(npc) and IsValid(rootVehicle) then
                    -- Final space check
                    if not allowMultiple and GetPassengerCount(rootVehicle) > 0 then
                        ProcessAutoJoin(index + 1)
                        return
                    end
                    
                    local attached = AttachNPCToVehicle(npc, rootVehicle)
                    if attached then
                        joinedCount = joinedCount + 1
                    else
                        RegisterBoardFailure(npc)
                    end
                elseif IsValid(npc) then
                    RegisterBoardFailure(npc)
                end
                ProcessAutoJoin(index + 1)
            end)
        end
        
        ProcessAutoJoin(1)
    end)
end)

hook.Add("PlayerLeaveVehicle", "NPCPassengerDetach", function(ply, vehicle)
    if not IsAddonEnabled() then return end
    local exitMode = NPCPassengers.cv_exit_mode:GetInt()
    if exitMode ~= 0 then return end
    
    local rootVehicle = GetRootVehicle(vehicle)
    if not IsValid(rootVehicle) then
        rootVehicle = vehicle
    end
    
    local delay = NPCPassengers.cv_detach_delay:GetFloat()
    
    timer.Simple(delay, function()
        if VehicleHasPlayer(rootVehicle) then return end
        
        local passengersToEject = {}
        for npc, data in pairs(friendlyPassengers) do
            if data.vehicle == rootVehicle or data.vehicle == vehicle then
                table.insert(passengersToEject, npc)
            end
        end
        
        for _, npc in ipairs(passengersToEject) do
            DetachNPC(npc)
        end
    end)
end)

hook.Add("EntityTakeDamage", "NPCPassengerDeathHandler", function(target, dmginfo)
    if not IsAddonEnabled() then return end
    if friendlyPassengers[target] then
        -- Don't detach on crash damage - passengers should stay seated!
        local dmgType = dmginfo:GetDamageType()
        local isCrashDamage = bit.band(dmgType, DMG_CRUSH) > 0 or bit.band(dmgType, DMG_VEHICLE) > 0
        
        -- Only detach if they're actually dying, not from crash damage
        if not isCrashDamage and target:Health() - dmginfo:GetDamage() <= 0 then
            DetachNPC(target)
        end
        return
    end
    
    local exitMode = NPCPassengers.cv_exit_mode:GetInt()
    if exitMode == 2 then return end
    if exitMode == 0 then return end
    
    local dmgType = dmginfo:GetDamageType()
    local isCollision = bit.band(dmgType, DMG_CRUSH) > 0 or bit.band(dmgType, DMG_VEHICLE) > 0
    if isCollision then
        return
    end
    
    local attacker = dmginfo:GetAttacker()
    if not IsValid(attacker) or attacker:IsWorld() then
        return
    end
    
    local rootVehicle = GetRootVehicle(target)
    if not IsValid(rootVehicle) then
        if target:IsVehicle() then
            rootVehicle = target
        else
            return
        end
    end
    
    local passengersToEject = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == rootVehicle or data.vehicle == target or data.seat == target then
            table.insert(passengersToEject, npc)
        end
    end
    
    for _, npc in ipairs(passengersToEject) do
        DetachNPC(npc)
    end
end)

hook.Add("EntityRemoved", "NPCPassengerCleanup", function(ent)
    if not IsValid(ent) then return end
    
    local entId = ent:EntIndex()
    npcBoardRetryState[entId] = nil
    ClearVehicleSeatCache(entId)

    local parent = ent:GetParent()
    if IsValid(parent) then
        ClearVehicleSeatCache(parent)
    end
    
    if friendlyPassengers[ent] then
        -- Unregister from turret control
        if NPCPassengers.UnregisterTurretNPC then
            NPCPassengers.UnregisterTurretNPC(ent)
        end
        friendlyPassengers[ent] = nil
        CleanupNPCTimers(entId)
        CleanupNPCLookState(entId)
        if animationTimers[entId] then
            animationTimers[entId] = nil
        end
    end
    
    local passengersToCleanup = {}
    for npc, data in pairs(friendlyPassengers) do
        if IsValid(data.vehicle) and data.vehicle == ent then
            passengersToCleanup[#passengersToCleanup + 1] = npc
        end
    end
    
    for _, npc in ipairs(passengersToCleanup) do
        if IsValid(npc) then
            DetachNPC(npc)
        else
            friendlyPassengers[npc] = nil
            CleanupNPCTimers(npc)
        end
    end
    
    if animationTimers[entId] then
        timer.Remove("NPCPassengerAnim_" .. entId)
        animationTimers[entId] = nil
    end
    
    if vehicleCooldowns[entId] then
        vehicleCooldowns[entId] = nil
    end
    
    timer.Remove("NPCPassengerDetach_" .. entId)
end)

ResetPassengerState = function(reason)
    local detached = 0
    local snapshot = {}
    for npc in pairs(friendlyPassengers) do
        snapshot[#snapshot + 1] = npc
    end

    for _, npc in ipairs(snapshot) do
        if IsValid(npc) then
            if DetachNPC(npc) then
                detached = detached + 1
            end
        else
            friendlyPassengers[npc] = nil
        end
    end

    pendingPassengers = {}
    vehicleCooldowns = {}
    npcBoardRetryState = {}
    vehicleSeatCache = {}

    if IsVerboseDebugEnabled() then
        print("[npc passengers] reset state reason=" .. tostring(reason or "unknown") .. " detached=" .. tostring(detached))
    end
end

hook.Add("PostCleanupMap", "NPCPassengers_ResetCleanupMap", function()
    ResetPassengerState("post_cleanup_map")
end)

hook.Add("ShutDown", "NPCPassengers_ResetShutdown", function()
    ResetPassengerState("shutdown")
end)

util.AddNetworkString("NPCPassengers_MakePassenger")
util.AddNetworkString("NPCPassengers_RemovePassenger")
util.AddNetworkString("NPCPassengers_MakePassengerForVehicle")

net.Receive("NPCPassengers_MakePassenger", function(len, ply)
    if not IsAddonEnabled() then return end
    local ent = net.ReadEntity()
    
    if not IsValid(ent) or not IsValid(ply) then return end
    if not ent:IsNPC() then return end
    if friendlyPassengers[ent] or ent:Health() <= 0 then return end
    
    if ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        if not IsValid(vehicle) then return end
        
        local rootVehicle = GetRootVehicle(vehicle)
        if not IsVehicleAllowedByFilters(rootVehicle) then
            local msg = "vehicle blocked by passenger filter settings"
            ply:ChatPrint(msg)
            SendClientCue(ply, false, msg)
            return
        end
        local allowMultiple = NPCPassengers.cv_multiple:GetBool()

        if IsNPCBoardCooldownActive(ent) then
            local msg = Phrase("passenger_cooldown")
            ply:ChatPrint(msg)
            SendClientCue(ply, false, msg)
            return
        end
        
        if not allowMultiple and VehicleHasNPCAttached(rootVehicle) then
            ply:ChatPrint("Vehicle already has a passenger! Enable multiple passengers in settings.")
            return
        end
        
        local availableSeats = GetAvailableSeatCount(rootVehicle)
        if availableSeats <= 0 then
            ply:ChatPrint("No available seats!")
            return
        end
        
        local success = AttachNPCToVehicle(ent, rootVehicle)
        if success then
            RegisterBoardSuccess(ent)
            RemovePendingPassenger(ply, ent)
            local total = GetPassengerCount(rootVehicle)
            local remaining = GetAvailableSeatCount(rootVehicle)
            local msg = "passenger added! (" .. total .. " passengers, " .. remaining .. " seats left)"
            ply:ChatPrint(msg)
            SendClientCue(ply, true, msg)
        else
            local cooldownStarted = RegisterBoardFailure(ent)
            local msg = cooldownStarted and Phrase("passenger_cooldown") or Phrase("passenger_attach_failed")
            ply:ChatPrint(msg)
            SendClientCue(ply, false, msg)
        end
    else
        if AddPendingPassenger(ply, ent) then
            local count = GetPendingCount(ply)
            if count == 1 then
                local msg = Phrase("passenger_queue_marked")
                ply:ChatPrint(msg)
                SendClientCue(ply, true, msg)
            else
                local msg = Phrase("passenger_queue_added", count)
                ply:ChatPrint(msg)
                SendClientCue(ply, true, msg)
            end
        else
            local msg = Phrase("passenger_queue_duplicate")
            ply:ChatPrint(msg)
            SendClientCue(ply, false, msg)
        end
    end
end)

net.Receive("NPCPassengers_RemovePassenger", function(len, ply)
    local ent = net.ReadEntity()
    
    if not IsValid(ent) or not IsValid(ply) then return end
    if not ent:IsNPC() then return end
    
    if friendlyPassengers[ent] then
        local vehicle = friendlyPassengers[ent].vehicle
        DetachNPC(ent)
        local remaining = IsValid(vehicle) and GetPassengerCount(vehicle) or 0
        ply:ChatPrint("Passenger removed! (" .. remaining .. " remaining)")
    elseif pendingPassengers[ply] then
        local found = false
        for i, npc in ipairs(pendingPassengers[ply]) do
            if npc == ent then
                table.remove(pendingPassengers[ply], i)
                found = true
                break
            end
        end
        if found then
            local remaining = GetPendingCount(ply)
            ply:ChatPrint("Removed from queue! (" .. remaining .. " pending)")
        else
            ply:ChatPrint("This NPC is not a passenger!")
        end
    else
        ply:ChatPrint("This NPC is not a passenger!")
    end
end)

-- Make NPC driver via context menu
net.Receive("NPCPassengers_MakeDriver", function(len, ply)
    local npc = net.ReadEntity()
    
    if not IsValid(npc) or not IsValid(ply) then return end
    if not npc:IsNPC() then 
        ply:ChatPrint("[NPC Driver] Invalid NPC!")
        return 
    end
    
    if not NPCPassengers.cv_driver_enabled:GetBool() then
        ply:ChatPrint("[NPC Driver] Driver system is disabled in settings!")
        return
    end
    
    -- Find nearest vehicle
    local vehicle = nil
    local minDist = 500
    for _, veh in ipairs(ents.FindInSphere(npc:GetPos(), 500)) do
        if veh:IsVehicle() then
            local dist = npc:GetPos():Distance(veh:GetPos())
            if dist < minDist then
                vehicle = veh
                minDist = dist
            end
        end
    end
    
    if not IsValid(vehicle) then
        ply:ChatPrint("[NPC Driver] No vehicle nearby (within 500 units)!")
        return
    end
    
    local success, msg = NPCPassengers.MakeNPCDriver(npc, vehicle)
    if success then
        local behaviorNames = {
            [0] = "Random Cruise",
            [1] = "Follow Player",
            [2] = "Patrol Route",
            [3] = "Flee Danger",
            [4] = "Stay Parked"
        }
        local behavior = NPCPassengers.cv_driver_behavior:GetInt()
        ply:ChatPrint("[NPC Driver] " .. npc:GetClass() .. " is now a driver!")
        ply:ChatPrint("[NPC Driver] Behavior: " .. behaviorNames[behavior])
        if behavior == 4 then
            ply:ChatPrint("[NPC Driver] Note: Vehicle is set to 'Stay Parked' - change behavior in settings to make it drive!")
        end
    else
        ply:ChatPrint("[NPC Driver] Failed: " .. (msg or "Unknown error"))
    end
end)

-- New: Make NPC passenger for a specific vehicle (click NPC, then click vehicle)
net.Receive("NPCPassengers_MakePassengerForVehicle", function(len, ply)
    if not IsAddonEnabled() then return end
    local npc = net.ReadEntity()
    local vehicle = net.ReadEntity()
    
    if not IsValid(npc) or not IsValid(vehicle) or not IsValid(ply) then return end
    if not npc:IsNPC() then 
        ply:ChatPrint("Invalid NPC!")
        return 
    end
    if friendlyPassengers[npc] or npc:Health() <= 0 then 
        ply:ChatPrint("NPC is already a passenger or dead!")
        return 
    end
    
    -- Get the root vehicle
    local rootVehicle = GetRootVehicle(vehicle)
    if not IsValid(rootVehicle) then
        rootVehicle = vehicle
    end

    if not IsVehicleAllowedByFilters(rootVehicle) then
        local msg = "vehicle blocked by passenger filter settings"
        ply:ChatPrint(msg)
        SendClientCue(ply, false, msg)
        return
    end

    if IsNPCBoardCooldownActive(npc) then
        local msg = Phrase("passenger_cooldown")
        ply:ChatPrint(msg)
        SendClientCue(ply, false, msg)
        return
    end
    
    local allowMultiple = NPCPassengers.cv_multiple:GetBool()
    
    if not allowMultiple and VehicleHasNPCAttached(rootVehicle) then
        ply:ChatPrint("Vehicle already has a passenger! Enable multiple passengers in settings.")
        return
    end
    
    local availableSeats = GetAvailableSeatCount(rootVehicle)
    if availableSeats <= 0 then
        ply:ChatPrint("No available seats in this vehicle!")
        return
    end
    
    -- Use skipPlayerCheck = true since we're manually assigning
    local success = AttachNPCToVehicle(npc, rootVehicle, true)
    if success then
        RegisterBoardSuccess(npc)
        local total = GetPassengerCount(rootVehicle)
        local remaining = GetAvailableSeatCount(rootVehicle)
        local msg = "npc added to vehicle! (" .. total .. " passengers, " .. remaining .. " seats left)"
        ply:ChatPrint(msg)
        SendClientCue(ply, true, msg)
    else
        local cooldownStarted = RegisterBoardFailure(npc)
        local msg = cooldownStarted and Phrase("passenger_cooldown") or Phrase("passenger_attach_failed")
        ply:ChatPrint(msg)
        SendClientCue(ply, false, msg)
    end
end)

-- Attach the nearest friendly NPC to the player's current vehicle
concommand.Add("nai_npc_attach_nearest", function(ply)
    if not IsValid(ply) then return end
    if not ply:InVehicle() then
        ply:ChatPrint("[NPC Passengers] You must be in a vehicle!")
        return
    end

    local vehicle = GetRootVehicle(ply:GetVehicle())
    if not IsValid(vehicle) then return end

    if not IsAddonEnabled() then
        ply:ChatPrint("[NPC Passengers] Addon is disabled.")
        return
    end

    if not IsVehicleAllowedByFilters(vehicle) then
        ply:ChatPrint("[NPC Passengers] This vehicle is blocked by filter settings.")
        return
    end

    local maxDist = NPCPassengers.cv_max_dist:GetFloat()
    local nearestNPC, nearestDistSq = nil, math.huge

    for _, npc in ipairs(ents.FindInSphere(ply:GetPos(), maxDist)) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if npc:Health() <= 0 then continue end
        if friendlyPassengers[npc] then continue end
        if not IsFriendlyNPC(npc, vehicle) then continue end
        local distSq = ply:GetPos():DistToSqr(npc:GetPos())
        if distSq < nearestDistSq then
            nearestDistSq = distSq
            nearestNPC = npc
        end
    end

    if not IsValid(nearestNPC) then
        ply:ChatPrint("[NPC Passengers] No nearby friendly NPC found within " .. maxDist .. " units.")
        return
    end

    if IsNPCBoardCooldownActive(nearestNPC) then
        ply:ChatPrint("[NPC Passengers] " .. Phrase("passenger_cooldown"))
        return
    end

    WalkNPCToVehicle(nearestNPC, vehicle, function(success)
        if success and IsValid(nearestNPC) and IsValid(vehicle) then
            if AttachNPCToVehicle(nearestNPC, vehicle) then
                local msg = Phrase("passenger_boarded", GetPassengerCount(vehicle))
                if IsValid(ply) then
                    ply:ChatPrint("[NPC Passengers] " .. msg)
                    SendClientCue(ply, true, msg)
                end
            else
                local cooldownStarted = RegisterBoardFailure(nearestNPC)
                local msg = cooldownStarted and Phrase("passenger_cooldown") or Phrase("passenger_attach_failed")
                if IsValid(ply) then
                    ply:ChatPrint("[NPC Passengers] " .. msg)
                    SendClientCue(ply, false, msg)
                end
            end
        else
            if IsValid(nearestNPC) then RegisterBoardFailure(nearestNPC) end
            if IsValid(ply) then
                local msg = Phrase("passenger_attach_failed")
                ply:ChatPrint("[NPC Passengers] " .. msg)
                SendClientCue(ply, false, msg)
            end
        end
    end)
end)

-- Immediately detach all NPCs from the player's current vehicle
concommand.Add("nai_npc_detach_all", function(ply)
    if not IsValid(ply) then return end
    if not ply:InVehicle() then
        ply:ChatPrint("[NPC Passengers] You must be in a vehicle!")
        return
    end

    local vehicle = GetRootVehicle(ply:GetVehicle())
    if not IsValid(vehicle) then return end

    local toDetach = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == vehicle then
            table.insert(toDetach, npc)
        end
    end

    local count = 0
    for _, npc in ipairs(toDetach) do
        if IsValid(npc) then
            DetachNPC(npc)
            count = count + 1
        end
    end

    ply:ChatPrint("[NPC Passengers] Detached " .. count .. " passenger(s).")
    if count > 0 then SendClientCue(ply, true, "Detached " .. count .. " passenger(s).") end
end)

-- Command all passengers to exit the player's current vehicle
concommand.Add("nai_npc_exit_all", function(ply)
    if not IsValid(ply) then return end
    if not ply:InVehicle() then
        ply:ChatPrint("[NPC Passengers] You must be in a vehicle!")
        return
    end

    local vehicle = GetRootVehicle(ply:GetVehicle())
    if not IsValid(vehicle) then return end

    local toExit = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == vehicle then
            table.insert(toExit, npc)
        end
    end

    local count = 0
    for _, npc in ipairs(toExit) do
        if IsValid(npc) then
            DetachNPC(npc)
            count = count + 1
        end
    end

    ply:ChatPrint("[NPC Passengers] " .. count .. " passenger(s) exited the vehicle.")
    if count > 0 then SendClientCue(ply, true, count .. " passenger(s) exited.") end
end)

-- Server-side reset of all replicated/server-controlled ConVars
-- Called by nai_npc_reset on the client so the server can actually apply the changes
concommand.Add("nai_npc_server_reset", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[NPC Passengers] You must be an admin to reset server settings.")
        return
    end
    -- General
    RunConsoleCommand("nai_npc_max_attach_dist", "500")
    RunConsoleCommand("nai_npc_detach_delay", "0.5")
    RunConsoleCommand("nai_npc_ai_delay", "2")
    RunConsoleCommand("nai_npc_cooldown", "1")
    RunConsoleCommand("nai_npc_allow_multiple", "1")
    RunConsoleCommand("nai_npc_exit_mode", "0")
    RunConsoleCommand("nai_npc_hide_in_tanks", "1")
    -- Auto-join
    RunConsoleCommand("nai_npc_auto_join", "1")
    RunConsoleCommand("nai_npc_auto_join_range", "500")
    RunConsoleCommand("nai_npc_auto_join_max", "4")
    RunConsoleCommand("nai_npc_auto_join_squad_only", "0")
    -- Position
    RunConsoleCommand("nai_npc_height_offset", "-3")
    RunConsoleCommand("nai_npc_forward_offset", "0")
    RunConsoleCommand("nai_npc_right_offset", "0")
    RunConsoleCommand("nai_npc_yaw_offset", "0")
    RunConsoleCommand("nai_npc_pitch_offset", "0")
    RunConsoleCommand("nai_npc_roll_offset", "0")
    -- Speech
    RunConsoleCommand("nai_npc_speech_enabled", "1")
    RunConsoleCommand("nai_npc_speech_volume", "75")
    RunConsoleCommand("nai_npc_speech_crash", "1")
    RunConsoleCommand("nai_npc_speech_crash_threshold", "400")
    RunConsoleCommand("nai_npc_speech_crash_cooldown", "1.5")
    RunConsoleCommand("nai_npc_speech_idle", "1")
    RunConsoleCommand("nai_npc_speech_idle_chance", "0.3")
    RunConsoleCommand("nai_npc_speech_idle_interval", "15")
    RunConsoleCommand("nai_npc_speech_board", "1")
    RunConsoleCommand("nai_npc_speech_pitch_var", "5")
    RunConsoleCommand("nai_npc_ambient_sounds", "1")
    RunConsoleCommand("nai_npc_ambient_interval", "30")
    -- Animation
    RunConsoleCommand("nai_npc_head_look", "1")
    RunConsoleCommand("nai_npc_head_smooth", "0.4")
    RunConsoleCommand("nai_npc_blink", "1")
    RunConsoleCommand("nai_npc_breathing", "1")
    RunConsoleCommand("nai_npc_walk_timeout", "5")
    -- Advanced Realism
    RunConsoleCommand("nai_npc_talking_gestures", "1")
    RunConsoleCommand("nai_npc_gesture_chance", "15")
    RunConsoleCommand("nai_npc_gesture_interval", "8")
    RunConsoleCommand("nai_npc_crash_flinch", "1")
    RunConsoleCommand("nai_npc_crash_threshold", "400")
    RunConsoleCommand("nai_npc_body_sway", "1")
    RunConsoleCommand("nai_npc_body_sway_amount", "1")
    RunConsoleCommand("nai_npc_threat_awareness", "1")
    RunConsoleCommand("nai_npc_threat_range", "1500")
    RunConsoleCommand("nai_npc_combat_alert", "1")
    RunConsoleCommand("nai_npc_fear_reactions", "1")
    RunConsoleCommand("nai_npc_fear_speed", "800")
    RunConsoleCommand("nai_npc_drowsiness", "1")
    RunConsoleCommand("nai_npc_drowsy_time", "60")
    RunConsoleCommand("nai_npc_passenger_interaction", "1")
    -- HUD
    RunConsoleCommand("nai_npc_hud_enabled", "1")
    RunConsoleCommand("nai_npc_hud_position", "1")
    RunConsoleCommand("nai_npc_hud_scale", "1")
    RunConsoleCommand("nai_npc_hud_opacity", "0.85")
    RunConsoleCommand("nai_npc_hud_show_calm", "1")
    RunConsoleCommand("nai_npc_hud_only_vehicle", "1")
    RunConsoleCommand("nai_npc_hud_hints", "1")
    RunConsoleCommand("nai_npc_hud_target_debug", "0")
    RunConsoleCommand("nai_npc_client_cues", "1")
    RunConsoleCommand("nai_npc_hud_alert_threshold", "0.3")
    RunConsoleCommand("nai_npc_hud_fear_threshold", "0.5")
    RunConsoleCommand("nai_npc_hud_drowsy_threshold", "0.7")
    -- Addon controls
    RunConsoleCommand("nai_npc_enabled", "1")
    RunConsoleCommand("nai_npc_max_passengers", "8")
    RunConsoleCommand("nai_npc_enter_distance", "80")
    RunConsoleCommand("nai_npc_retry_attempts", "3")
    RunConsoleCommand("nai_npc_retry_cooldown", "6")
    RunConsoleCommand("nai_npc_allow_classes", "")
    RunConsoleCommand("nai_npc_deny_classes", "")
    RunConsoleCommand("nai_npc_allow_models", "")
    RunConsoleCommand("nai_npc_deny_models", "")
    RunConsoleCommand("nai_npc_debug_verbose", "0")
    -- Tank/LVS
    RunConsoleCommand("nai_npc_driver_enabled", "1")
    RunConsoleCommand("nai_npc_driver_range", "4000")
    RunConsoleCommand("nai_npc_driver_engage_distance", "800")
    RunConsoleCommand("nai_npc_driver_speed", "0.7")
    RunConsoleCommand("nai_npc_driver_reverse_distance", "300")
    RunConsoleCommand("nai_npc_turret_enabled", "1")
    RunConsoleCommand("nai_npc_turret_range", "3000")
    RunConsoleCommand("nai_npc_turret_accuracy", "0.85")
    RunConsoleCommand("nai_npc_turret_reaction_time", "0.5")
    RunConsoleCommand("nai_npc_turret_fire_delay", "0.15")
    RunConsoleCommand("nai_npc_turret_aim_speed", "5")
    RunConsoleCommand("nai_npc_turret_lead_targets", "1")
    RunConsoleCommand("nai_npc_turret_friendly_fire", "0")
    if IsValid(ply) then
        ply:ChatPrint("[NPC Passengers] All server settings reset to defaults.")
    end
end)

concommand.Add("nai_passengers_list", function(ply)
    if not IsValid(ply) then return end
    
    ply:ChatPrint("=== NPC Passengers ===")
    
    local pendingCount = GetPendingCount(ply)
    if pendingCount > 0 then
        ply:ChatPrint("Pending: " .. pendingCount .. " NPCs queued")
    end
    
    if ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        local rootVehicle = GetRootVehicle(vehicle)
        if IsValid(rootVehicle) then
            local count = GetPassengerCount(rootVehicle)
            local available = GetAvailableSeatCount(rootVehicle)
            ply:ChatPrint("Current vehicle: " .. count .. " passengers, " .. available .. " seats available")
        end
    end
    
    local totalPassengers = 0
    for _ in pairs(friendlyPassengers) do
        totalPassengers = totalPassengers + 1
    end
    ply:ChatPrint("Total passengers in world: " .. totalPassengers)
end)

concommand.Add("nai_passengers_dump_nearby", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local radius = 1000
    ply:ChatPrint(Phrase("dump_header"))

    local found = 0
    for npc, data in pairs(friendlyPassengers) do
        if not IsValid(npc) then continue end
        if npc:GetPos():DistToSqr(ply:GetPos()) > (radius * radius) then continue end

        local npcId = npc:EntIndex()
        local state = npcLookState[npcId]
        local stateName = "calm"
        if state then
            if state.isDrowsy then
                stateName = "drowsy"
            elseif (state.fearLevel or 0) > 0.5 then
                stateName = "scared"
            elseif (state.alertLevel or 0) > 0.3 then
                stateName = "alert"
            end
        end

        local hp = tostring(math.max(0, npc:Health()))
        local vehClass = IsValid(data.vehicle) and (data.vehicle:GetClass() or "unknown") or "invalid"
        local seatClass = IsValid(data.seat) and (data.seat:GetClass() or "seat") or "none"
        ply:ChatPrint(Phrase("dump_line", npc:GetClass(), stateName, hp, vehClass, seatClass))
        found = found + 1
    end

    if found == 0 then
        ply:ChatPrint(Phrase("dump_none"))
    end
end)

concommand.Add("nai_passengers_clear", function(ply)
    if not IsValid(ply) then return end
    
    ClearPendingPassengers(ply)
    ply:ChatPrint("Pending passengers cleared!")
end)

concommand.Add("nai_passengers_eject_all", function(ply)
    if not IsValid(ply) then return end
    if not ply:InVehicle() then
        ply:ChatPrint("You must be in a vehicle!")
        return
    end
    
    local vehicle = ply:GetVehicle()
    local rootVehicle = GetRootVehicle(vehicle)
    if not IsValid(rootVehicle) then return end
    
    local ejected = 0
    local toEject = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == rootVehicle then
            table.insert(toEject, npc)
        end
    end
    
    for _, npc in ipairs(toEject) do
        DetachNPC(npc)
        ejected = ejected + 1
    end
    
    ply:ChatPrint("Ejected " .. ejected .. " passenger(s)!")
end)

concommand.Add("nai_passengers_eject_dead", function(ply)
    if not IsValid(ply) then return end
    
    local vehicle = ply:GetVehicle()
    if IsValid(vehicle) then
        ply:ChatPrint("You must exit the vehicle first!")
        return
    end
    
    -- Find nearby vehicle
    local trace = ply:GetEyeTrace()
    local rootVehicle = GetRootVehicle(trace.Entity)
    
    if not IsValid(rootVehicle) then
        -- Try looking at position
        local nearbyVehicles = ents.FindInSphere(ply:GetPos(), 300)
        for _, ent in ipairs(nearbyVehicles) do
            local testVehicle = GetRootVehicle(ent)
            if IsValid(testVehicle) then
                rootVehicle = testVehicle
                break
            end
        end
    end
    
    if not IsValid(rootVehicle) then
        ply:ChatPrint("No vehicle found nearby!")
        return
    end
    
    local ejected = 0
    local toEject = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == rootVehicle and IsValid(npc) and npc:Health() <= 0 then
            table.insert(toEject, npc)
        end
    end
    
    for _, npc in ipairs(toEject) do
        DetachNPC(npc)
        ejected = ejected + 1
    end
    
    if ejected > 0 then
        ply:ChatPrint("Ejected " .. ejected .. " dead passenger(s)!")
    else
        ply:ChatPrint("No dead passengers found in vehicle.")
    end
end)

-- Interactive dead passenger ejection system
hook.Add("Think", "NPCPassengers_DeadEjectionPrompt", function()
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or ply:InVehicle() then continue end
        
        -- Check nearby vehicles FIRST (no line of sight needed!)
        local nearbyVehicles = ents.FindInSphere(ply:GetPos(), 500)
        local rootVehicle = nil
        local lookingAt = false
        
        for _, ent in ipairs(nearbyVehicles) do
            local testVehicle = GetRootVehicle(ent)
            if IsValid(testVehicle) then
                rootVehicle = testVehicle
                break
            end
        end
        
        -- Check if looking at vehicle for better feedback
        if IsValid(rootVehicle) then
            local trace = ply:GetEyeTrace()
            local tracedVehicle = GetRootVehicle(trace.Entity)
            lookingAt = (tracedVehicle == rootVehicle)
        end
        
        if IsValid(rootVehicle) then
            -- Count dead passengers
            local deadCount = 0
            for npc, data in pairs(friendlyPassengers) do
                if data.vehicle == rootVehicle and IsValid(npc) and npc:Health() <= 0 then
                    deadCount = deadCount + 1
                end
            end
            
            if deadCount > 0 then
                -- Store vehicle reference for this player
                ply.NPCDeadPassengerVehicle = rootVehicle
                ply.NPCDeadPassengerCount = deadCount
                
                -- Send prompt to client
                net.Start("NPCPassengers_EjectPrompt")
                net.WriteInt(deadCount, 8)
                net.WriteBool(lookingAt)
                net.Send(ply)
            else
                ply.NPCDeadPassengerVehicle = nil
            end
        else
            ply.NPCDeadPassengerVehicle = nil
        end
    end
end)

-- Receive eject request from client
net.Receive("NPCPassengers_EjectDead", function(len, ply)
    if not IsValid(ply) then return end
    
    local rootVehicle = ply.NPCDeadPassengerVehicle
    if not IsValid(rootVehicle) then return end
    
    -- Count dead passengers
    local deadPassengers = {}
    for npc, data in pairs(friendlyPassengers) do
        if data.vehicle == rootVehicle and IsValid(npc) and npc:Health() <= 0 then
            table.insert(deadPassengers, npc)
        end
    end
    
    if #deadPassengers > 0 then
        -- Eject all dead passengers
        for _, npc in ipairs(deadPassengers) do
            DetachNPC(npc)
            
            -- Add some physics force for dramatic effect
            local phys = npc:GetPhysicsObject()
            if IsValid(phys) then
                local dir = (ply:GetPos() - npc:GetPos()):GetNormalized()
                phys:EnableMotion(true)
                phys:EnableCollisions(true)
                phys:SetVelocity(dir * 100 + Vector(0, 0, 50))
            end
            
            -- Reset collision group so body is interactive
            npc:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        end
        
        ply:EmitSound("buttons/button14.wav", 70, 100)
        ply:ChatPrint("✓ Removed " .. #deadPassengers .. " dead passenger" .. (#deadPassengers > 1 and "s" or "") .. " from vehicle")
    end
    
    ply.NPCDeadPassengerVehicle = nil
end)

-- Prevent passengers from unparenting during collisions/physics events
hook.Add("Think", "NPCPassengers_PreventUnparenting", function()
    for npc, pdata in pairs(friendlyPassengers) do
        if IsValid(npc) and IsValid(pdata.vehicle) then
            local expectedParent = pdata.seat or pdata.vehicle
            
            -- If parent relationship broke (from collision/damage), restore it immediately
            if npc:GetParent() ~= expectedParent then
                npc:SetParent(expectedParent)
                
                -- Restore collision group
                npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
                
                -- Restore position
                if pdata.baseLocalPos then
                    npc:SetLocalPos(pdata.baseLocalPos)
                end
                if pdata.baseLocalAng then
                    npc:SetLocalAngles(pdata.baseLocalAng)
                end
            end
            
            -- Ensure collision group stays correct
            if npc:GetCollisionGroup() ~= COLLISION_GROUP_IN_VEHICLE then
                npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
            end
            
            -- Disable physics motion if it somehow got enabled
            local phys = npc:GetPhysicsObject()
            if IsValid(phys) and phys:IsMotionEnabled() then
                phys:EnableMotion(false)
                phys:EnableCollisions(false)
            end
        end
    end
end)
-- ============================================================================
-- NPC DRIVER SYSTEM
-- NPCs drive vehicles automatically based on behavior mode
-- Behavior modes: 0=Random Cruise, 1=Follow Player, 2=Patrol, 3=Flee, 4=Stay Parked
-- ============================================================================

local npcDrivers = {} -- [npc] = {vehicle, destination, state, behavior, etc}

-- Find the driver seat specifically (not passenger seats)
local function GetDriverSeat(vehicle)
    local vehicleType = GetVehicleType(vehicle)
    
    -- Simfphys vehicles
    if vehicle.IsSimfphyscar then
        if vehicle.DriverSeat and IsValid(vehicle.DriverSeat) then
            return vehicle.DriverSeat, vehicleType
        end
    end
    
    -- LVS vehicles
    if vehicle.LVS or vehicle.IsLVS or string.find(vehicle:GetClass() or "", "lvs_") then
        if vehicle.GetDriverSeat then
            local driverSeat = vehicle:GetDriverSeat()
            if IsValid(driverSeat) then
                return driverSeat, vehicleType
            end
        end
    end
    
    -- Default vehicles - check for child seats first
    for _, child in ipairs(vehicle:GetChildren()) do
        if child:GetClass() == "prop_vehicle_prisoner_pod" then
            return child, vehicleType
        end
    end
    
    -- For default GMod vehicles that ARE the seat entity themselves
    if vehicle:GetClass() == "prop_vehicle_jeep" or 
       vehicle:GetClass() == "prop_vehicle_airboat" or
       vehicle:GetClass() == "prop_vehicle_prisoner_pod" or
       string.find(vehicle:GetClass() or "", "vehicle") then
        return vehicle, vehicleType
    end
    
    return nil, vehicleType
end

-- Make NPC enter vehicle as driver (no manual destination needed - behavior is automatic)
function NPCPassengers.MakeNPCDriver(npc, vehicle)
    if not IsValid(npc) or not IsValid(vehicle) then return false end
    if not NPCPassengers.cv_driver_enabled:GetBool() then 
        return false, "NPC Driver system is disabled"
    end
    
    -- Check if NPC type is allowed
    if not NPCPassengers.cv_driver_allow_all_npcs:GetBool() then
        local class = npc:GetClass()
        if class ~= "npc_citizen" and class ~= "npc_alyx" and class ~= "npc_barney" and 
           class ~= "npc_monk" and class ~= "npc_kleiner" and class ~= "npc_eli" and
           class ~= "npc_vortigaunt" then
            return false, "This NPC type cannot drive"
        end
    end
    
    -- Check if driver seat is occupied by a player
    local driver = vehicle:GetDriver()
    if IsValid(driver) and driver:IsPlayer() then
        return false, "A player is driving"
    end
    
    -- Remove from passengers if they are one
    if friendlyPassengers[npc] then
        DetachNPC(npc)
    end
    
    -- Get the driver seat specifically
    local driverSeat, vehicleType = GetDriverSeat(vehicle)
    if not IsValid(driverSeat) then
        return false, "No driver seat found"
    end
    
    -- Check if driver seat is already occupied
    if IsValid(driverSeat:GetDriver()) then
        return false, "Driver seat is occupied"
    end
    
    -- Position and parent NPC to the driver seat
    local seatPos = driverSeat:GetPos()
    local seatAng = driverSeat:GetAngles()
    
    local originalCollision = npc:GetCollisionGroup()
    if originalCollision == COLLISION_GROUP_IN_VEHICLE then
        originalCollision = COLLISION_GROUP_NPC
    end
    
    npc:SetParent(driverSeat)
    
    local baseLocalPos = driverSeat:WorldToLocal(seatPos)
    local baseLocalAng = driverSeat:WorldToLocalAngles(seatAng)
    
    -- Get vehicle-specific offsets
    local vehOffsets = GetVehicleOffsets(vehicleType)
    
    local offsetPos = Vector(
        vehOffsets.forward + NPCPassengers.cv_forward_offset:GetFloat(),
        vehOffsets.right + NPCPassengers.cv_right_offset:GetFloat(),
        vehOffsets.height + NPCPassengers.cv_height_offset:GetFloat()
    )
    npc:SetLocalPos(baseLocalPos + offsetPos)
    
    local offsetAng = Angle(
        vehOffsets.pitch + NPCPassengers.cv_pitch_offset:GetFloat(),
        vehOffsets.baseYaw + vehOffsets.yaw + NPCPassengers.cv_yaw_offset:GetFloat(),
        vehOffsets.roll + NPCPassengers.cv_roll_offset:GetFloat()
    )
    npc:SetLocalAngles(baseLocalAng + offsetAng)
    
    npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    npc:SetMoveType(MOVETYPE_NONE)
    npc:SetSolid(SOLID_NONE)
    npc:SetNotSolid(true)
    
    if npc.PhysicsDestroy then
        npc:PhysicsDestroy()
    end
    local phys = npc:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableCollisions(false)
        phys:Sleep()
    end
    
    npc:SetNPCState(NPC_STATE_IDLE)
    
    SetNoTalkFlag(npc, true)
    local relationships = DisableNPCAI(npc)
    ForceSitAnimation(npc)
    StartAnimationEnforcement(npc)
    
    -- Mark as passenger for client-side systems
    npc:SetNWBool("IsNPCPassenger", true)
    
    -- Create passenger data entry (so driver gets all passenger behaviors)
    friendlyPassengers[npc] = {
        vehicle = vehicle,
        seat = driverSeat,
        npcId = npc:EntIndex(),
        originalCollision = originalCollision,
        settings = nil,
        lastAngleCheck = CurTime(),
        capabilities = npc:CapabilitiesGet(),
        relationships = relationships,
        baseLocalPos = baseLocalPos,
        baseLocalAng = baseLocalAng,
        vehicleType = vehicleType,
        lastVelocity = Vector(0, 0, 0),
        lastHurtSound = 0,
        lastIdleChatter = CurTime() + 10,
        isDriver = true  -- Mark as driver
    }
    
    -- Get behavior mode from settings
    local behavior = NPCPassengers.cv_driver_behavior:GetInt()
    
    -- Initialize driver data
    npcDrivers[npc] = {
        vehicle = vehicle,
        destination = nil, -- Will be set by behavior AI
        behavior = behavior, -- 0=Random, 1=Follow, 2=Patrol, 3=Flee, 4=Parked
        state = "driving",
        lastPos = vehicle:GetPos(),
        lastUpdate = CurTime(),
        nextDestTime = 0, -- When to pick new destination
        honkCooldown = 0,
        targetSpeed = 0,
        steering = 0,
        braking = false,
        stuckTime = 0,
        patrolCenter = vehicle:GetPos(), -- For patrol mode
        patrolAngle = 0 -- For patrol mode
    }
    
    -- Pick initial destination based on behavior
    NPCPassengers.PickNewDestination(npc)
    
    -- Wake up vehicle physics so it can move
    local vehPhys = vehicle:GetPhysicsObject()
    if IsValid(vehPhys) then
        vehPhys:Wake()
        vehPhys:EnableMotion(true)
    end
    
    return true
end

-- Pick new destination based on behavior mode
function NPCPassengers.PickNewDestination(npc)
    local data = npcDrivers[npc]
    if not data or not IsValid(data.vehicle) then return end
    
    local vehicle = data.vehicle
    local vehPos = vehicle:GetPos()
    local behavior = data.behavior
    
    if behavior == 0 then
        -- Random Cruise: Pick random point within wander distance
        local wanderDist = NPCPassengers.cv_driver_wander_dist:GetFloat()
        local randomAngle = math.random() * math.pi * 2
        local randomDist = math.random(wanderDist * 0.5, wanderDist)
        data.destination = vehPos + Vector(math.cos(randomAngle) * randomDist, math.sin(randomAngle) * randomDist, 0)
        data.nextDestTime = CurTime() + math.random(10, 30) -- Pick new dest in 10-30 seconds
        
    elseif behavior == 1 then
        -- Follow Player: Find nearest player vehicle and follow
        local closestPly = nil
        local closestDist = math.huge
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and IsValid(ply:GetVehicle()) then
                local dist = vehPos:Distance(ply:GetPos())
                if dist < closestDist then
                    closestDist = dist
                    closestPly = ply
                end
            end
        end
        if closestPly then
            data.destination = closestPly:GetPos()
        else
            -- No player in vehicle, cruise randomly
            local wanderDist = 500
            local randomAngle = math.random() * math.pi * 2
            data.destination = vehPos + Vector(math.cos(randomAngle) * wanderDist, math.sin(randomAngle) * wanderDist, 0)
        end
        data.nextDestTime = CurTime() + 3 -- Update frequently for following
        
    elseif behavior == 2 then
        -- Patrol: Drive in circle around patrol center
        data.patrolAngle = data.patrolAngle + 0.5
        local radius = 1000
        data.destination = data.patrolCenter + Vector(math.cos(data.patrolAngle) * radius, math.sin(data.patrolAngle) * radius, 0)
        data.nextDestTime = CurTime() + 5
        
    elseif behavior == 3 then
        -- Flee: Drive away from nearest threat
        local threats = ents.FindInSphere(vehPos, 2000)
        local closestThreat = nil
        local closestDist = math.huge
        for _, ent in ipairs(threats) do
            if IsValid(ent) and (ent:IsNPC() or ent:IsNextBot()) and ent ~= npc then
                if ent:GetClass() == "npc_zombie" or ent:GetClass() == "npc_combine_s" or 
                   ent:GetClass() == "npc_hunter" or ent:GetClass() == "npc_antlion" then
                    local dist = vehPos:Distance(ent:GetPos())
                    if dist < closestDist then
                        closestDist = dist
                        closestThreat = ent
                    end
                end
            end
        end
        if closestThreat then
            -- Drive away from threat
            local fleeDir = (vehPos - closestThreat:GetPos()):GetNormalized()
            data.destination = vehPos + fleeDir * 2000
        else
            -- No threats, cruise randomly
            local randomAngle = math.random() * math.pi * 2
            data.destination = vehPos + Vector(math.cos(randomAngle) * 1000, math.sin(randomAngle) * 1000, 0)
        end
        data.nextDestTime = CurTime() + 5
        
    elseif behavior == 4 then
        -- Stay Parked: Don't move
        data.destination = vehPos
        data.targetSpeed = 0
        data.state = "parked"
    end
end

-- Main driver think loop - controls vehicle physics
hook.Add("Think", "NPCPassengers_NPCDriver", function()
    if not NPCPassengers.cv_driver_enabled:GetBool() then return end
    
    local curTime = CurTime()
    
    for npc, data in pairs(npcDrivers) do
        if not IsValid(npc) or not IsValid(data.vehicle) then
            npcDrivers[npc] = nil
            continue
        end
        
        local vehicle = data.vehicle
        local phys = vehicle:GetPhysicsObject()
        if not IsValid(phys) then continue end
        
        -- Update every frame
        if data.state == "driving" then
            NPCPassengers.UpdateNPCDriver(npc, data, phys, curTime)
        elseif data.state == "arriving" then
            NPCPassengers.HandleArrival(npc, data, vehicle)
        end
    end
end)

-- Update driver AI and vehicle control
function NPCPassengers.UpdateNPCDriver(npc, data, phys, curTime)
    local vehicle = data.vehicle
    local vehPos = vehicle:GetPos()
    local vehAng = vehicle:GetAngles()
    local vehVel = phys:GetVelocity()
    local currentSpeed = vehVel:Length()
    
    if not IsValid(vehicle) then
        data.targetSpeed = 0
        return
    end
    
    -- If no destination, pick one now
    if not data.destination then
        NPCPassengers.PickNewDestination(npc)
        if not data.destination then
            data.targetSpeed = 0
            return
        end
    end
    
    -- Wake up physics if asleep
    if phys:IsAsleep() then
        phys:Wake()
    end
    if not phys:IsMotionEnabled() then
        phys:EnableMotion(true)
    end
    
    -- Check if time to pick new destination
    if curTime > data.nextDestTime then
        NPCPassengers.PickNewDestination(npc)
    end
    
    -- If parked, don't drive
    if data.behavior == 4 or not data.destination then
        data.targetSpeed = 0
        return
    end
    
    -- Calculate direction to destination
    local targetDir = (data.destination - vehPos):GetNormalized()
    local distToDest = vehPos:Distance(data.destination)
    
    -- Check if arrived at current waypoint
    local stopDist = NPCPassengers.cv_driver_stop_distance:GetFloat()
    if distToDest < stopDist then
        -- Pick new destination immediately
        NPCPassengers.PickNewDestination(npc)
        if not data.destination then return end
        targetDir = (data.destination - vehPos):GetNormalized()
        distToDest = vehPos:Distance(data.destination)
    end
    
    -- Calculate steering
    local forward = vehAng:Forward()
    local targetAngle = math.atan2(targetDir.y, targetDir.x)
    local currentAngle = math.atan2(forward.y, forward.x)
    local angleDiff = math.NormalizeAngle(targetAngle - currentAngle)
    
    -- Steering value (-1 to 1)
    local targetSteering = math.Clamp(angleDiff * 2, -1, 1)
    
    -- Smooth steering
    if NPCPassengers.cv_driver_smooth_steering:GetBool() then
        data.steering = math.Approach(data.steering, targetSteering, FrameTime() * 3)
    else
        data.steering = targetSteering
    end
    
    -- Calculate target speed
    local speedMult = NPCPassengers.cv_driver_speed:GetFloat()
    local skill = NPCPassengers.cv_driver_skill:GetInt() / 100
    local aggression = NPCPassengers.cv_driver_aggression:GetInt() / 100
    
    local baseSpeed = 500 * speedMult
    local turnSharpness = math.abs(angleDiff)
    
    -- Slow down for turns
    if turnSharpness > 0.5 then
        baseSpeed = baseSpeed * 0.3
    elseif turnSharpness > 0.3 then
        baseSpeed = baseSpeed * 0.6
    end
    
    -- Adjust for aggression
    baseSpeed = baseSpeed * (0.7 + aggression * 0.6)
    
    -- Brake distance check
    local brakeDistance = NPCPassengers.cv_driver_brake_distance:GetFloat()
    if distToDest < brakeDistance then
        baseSpeed = baseSpeed * (distToDest / brakeDistance)
    end
    
    data.targetSpeed = baseSpeed
    data.braking = false
    
    -- Collision avoidance
    if NPCPassengers.cv_driver_avoid_collisions:GetBool() then
        local trace = util.TraceLine({
            start = vehPos + Vector(0, 0, 50),
            endpos = vehPos + forward * 400,
            filter = {vehicle, npc},
            mask = MASK_SOLID
        })
        
        if trace.Hit then
            data.targetSpeed = data.targetSpeed * 0.3
            data.braking = true
            
            -- Honking
            if NPCPassengers.cv_driver_honk:GetBool() and curTime > data.honkCooldown then
                vehicle:EmitSound("vehicles/v8/vehicle_horn_1.wav", 75, 100)
                data.honkCooldown = curTime + 2
            end
        end
    end
    
    -- Apply vehicle controls via physics
    local throttle = 0
    if currentSpeed < data.targetSpeed then
        throttle = math.Clamp((data.targetSpeed - currentSpeed) / 200, 0, 1)
    end
    
    -- Check if this is a default GMod vehicle (uses different control method)
    local isDefaultVehicle = vehicle:GetClass() == "prop_vehicle_jeep" or 
                             vehicle:GetClass() == "prop_vehicle_airboat" or
                             string.find(vehicle:GetClass() or "", "prop_vehicle")
    
    if isDefaultVehicle then
        -- Use entity angles for default vehicles (they don't respond well to physics forces)
        local targetAng = (data.destination - vehPos):Angle()
        local newAng = LerpAngle(FrameTime() * 2, vehAng, targetAng)
        vehicle:SetAngles(Angle(0, newAng.y, 0)) -- Only yaw, keep pitch/roll at 0
        
        -- Apply velocity directly for default vehicles
        local forward = vehicle:GetForward()
        phys:SetVelocity(forward * data.targetSpeed * throttle)
    else
        -- Apply forward force for physics-based vehicles (Simfphys, LVS, etc.)
        local forwardForce = forward * throttle * 80000 * FrameTime()
        phys:ApplyForceCenter(forwardForce)
        
        -- Apply steering torque
        local steeringTorque = Vector(0, 0, data.steering * 50000 * FrameTime())
        phys:ApplyTorqueCenter(steeringTorque)
    end
    
    -- Apply braking (works for all vehicle types)
    if data.braking or currentSpeed > data.targetSpeed then
        local brakeForce = -vehVel * 0.5
        phys:ApplyForceCenter(brakeForce)
    end
    
    -- Stuck detection
    local posChange = vehPos:Distance(data.lastPos)
    if posChange < 10 and throttle > 0.3 then
        data.stuckTime = data.stuckTime + (curTime - data.lastUpdate)
    else
        data.stuckTime = 0
    end
    
    data.lastPos = vehPos
    data.lastUpdate = curTime
end

-- Handle arrival at destination
function NPCPassengers.HandleArrival(npc, data, vehicle)
    local phys = vehicle:GetPhysicsObject()
    if IsValid(phys) then
        -- Stop vehicle
        phys:SetVelocity(phys:GetVelocity() * 0.5)
        
        local currentSpeed = phys:GetVelocity():Length()
        if currentSpeed < 50 then
            phys:SetVelocity(Vector(0, 0, 0))
            data.state = "parked"
            
            -- Exit if configured
            if NPCPassengers.cv_driver_exit_on_arrival:GetBool() then
                timer.Simple(1, function()
                    if IsValid(npc) and npcDrivers[npc] then
                        NPCPassengers.StopNPCDriver(npc, true)
                    end
                end)
            end
        end
    end
end

-- Stop NPC from driving
function NPCPassengers.StopNPCDriver(npc, exitVehicle)
    if not npcDrivers[npc] then return end
    
    -- Remove driver flag from passenger data
    if friendlyPassengers[npc] then
        friendlyPassengers[npc].isDriver = false
    end
    
    -- Use existing DetachNPC function to properly exit vehicle (only if exitVehicle is true)
    if IsValid(npc) and exitVehicle then
        DetachNPC(npc)
    end
    
    npcDrivers[npc] = nil
end

-- Calculate path (simplified - just stores destination)
function NPCPassengers.CalculateDriverPath(npc)
    -- Path calculation is simplified - NPCs just drive straight to destination
    -- This could be expanded with waypoint system in the future
end

-- Console commands
concommand.Add("nai_npc_driver_force", function(ply)
    if not IsValid(ply) then return end
    
    local trace = ply:GetEyeTrace()
    local npc = trace.Entity
    
    if not IsValid(npc) or not npc:IsNPC() then
        ply:ChatPrint("[NPC Driver] Look at an NPC!")
        return
    end
    
    -- Find nearest vehicle
    local vehicle = nil
    local minDist = 500
    for _, veh in ipairs(ents.FindInSphere(npc:GetPos(), 500)) do
        if veh:IsVehicle() then
            local dist = npc:GetPos():Distance(veh:GetPos())
            if dist < minDist then
                vehicle = veh
                minDist = dist
            end
        end
    end
    
    if not IsValid(vehicle) then
        ply:ChatPrint("[NPC Driver] No vehicle nearby!")
        return
    end
    
    -- Get destination (where player is looking)
    local destTrace = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 10000,
        filter = ply
    })
    
    local success, msg = NPCPassengers.MakeNPCDriver(npc, vehicle, destTrace.HitPos)
    if success then
        ply:ChatPrint("[NPC Driver] NPC will drive to destination!")
    else
        ply:ChatPrint("[NPC Driver] Failed: " .. (msg or "Unknown error"))
    end
end)

concommand.Add("nai_npc_driver_stop_all", function(ply)
    if not IsValid(ply) then return end
    
    local count = 0
    for npc, data in pairs(npcDrivers) do
        NPCPassengers.StopNPCDriver(npc, true)
        count = count + 1
    end
    
    ply:ChatPrint("[NPC Driver] Stopped " .. count .. " driver(s)")
end)