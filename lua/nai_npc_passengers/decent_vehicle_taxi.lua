if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.decent_vehicle_taxi = true

-- Player-Driven Taxi System
-- Players drive taxis, NPCs get in as passengers

local IsValid = IsValid
local CurTime = CurTime
local math = math
local pairs = pairs
local ipairs = ipairs

local taxiPassengers = {} -- NPC passengers waiting for taxis
local taxiStations = {} -- Taxi station entities

-- Random station names
local stationNouns = {
    "Plaza", "Square", "Center", "Terminal", "Hub", "Station", "Stop", "Point",
    "Market", "Mall", "District", "Quarter", "Zone", "Sector", "Area", "Corner",
    "Crossroads", "Junction", "Intersection", "Loop", "Circle", "Park", "Gardens",
    "Avenue", "Boulevard", "Street", "Road", "Lane", "Drive", "Way", "Place",
    "Tower", "Complex", "Building", "Hall", "Office", "Exchange", "Depot"
}

local stationAdjectives = {
    "Central", "North", "South", "East", "West", "Main", "Grand", "Royal",
    "Imperial", "Metropolitan", "Downtown", "Uptown", "Midtown", "Old", "New",
    "Upper", "Lower", "Inner", "Outer", "East", "West", "North", "South",
    "Prime", "Elite", "Premium", "Gold", "Silver", "Bronze", "Star", "Sun",
    "Moon", "Sky", "Cloud", "River", "Lake", "Ocean", "Bay", "Harbor", "Port"
}

local function GetRandomStationName()
    return string.format("%s-%s",
        stationAdjectives[math.random(#stationAdjectives)],
        stationNouns[math.random(#stationNouns)])
end

-- Create taxi station entity
local function CreateTaxiStation(pos, name)
    local station = ents.Create("prop_physics")
    station:SetModel("models/props_c17/streetsign004c.mdl")
    station:SetPos(pos)
    station:SetAngles(Angle(0, 0, 0))
    station:Spawn()
    station:SetMoveType(MOVETYPE_NONE)
    station:SetSolid(SOLID_VPHYSICS)
    station:SetUseType(SIMPLE_USE)
    station:PhysicsInitStatic(SOLID_VPHYSICS)
    station:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    station.IsTaxiStation = true
    station.StationName = name or GetRandomStationName()

    taxiStations[#taxiStations + 1] = station
    return station
end

-- Find or create taxi stations on the map
local function EnsureTaxiStations()
    if #taxiStations > 0 then return taxiStations end

    -- Try to find existing taxi stations
    for _, ent in ipairs(ents.GetAll()) do
        if ent.IsTaxiStation then
            taxiStations[#taxiStations + 1] = ent
        end
    end

    -- If no stations exist, create some at spawn points
    if #taxiStations == 0 then
        local spawnPoints = spawnpoints or {}
        if #spawnPoints > 0 then
            for i = 1, math.min(3, #spawnPoints) do
                local pos = spawnPoints[i].pos or Vector(0, 0, 0)
                CreateTaxiStation(pos + Vector(0, 0, 50))
            end
        else
            -- Fallback: create stations at origin offsets
            CreateTaxiStation(Vector(0, 200, 0))
            CreateTaxiStation(Vector(0, -200, 0))
            CreateTaxiStation(Vector(200, 0, 0))
        end
    end

    return taxiStations
end

-- Get nearest taxi station to an entity
local function GetNearestTaxiStation(ent)
    EnsureTaxiStations()
    if #taxiStations == 0 then return nil end

    local entPos = ent:GetPos()
    local nearestStation = nil
    local nearestDist = math.huge

    for _, station in ipairs(taxiStations) do
        if not IsValid(station) then continue end
        local dist = entPos:Distance(station:GetPos())
        if dist < nearestDist then
            nearestDist = dist
            nearestStation = station
        end
    end

    return nearestStation
end

-- Get random taxi station (for destination selection)
local function GetRandomTaxiStation(excludeStation)
    EnsureTaxiStations()
    if #taxiStations == 0 then return nil end
    if #taxiStations == 1 and taxiStations[1] == excludeStation then return nil end

    local available = {}
    for _, station in ipairs(taxiStations) do
        if station ~= excludeStation then
            available[#available + 1] = station
        end
    end

    if #available == 0 then return nil end
    return available[math.random(#available)]
end

-- Get taxi station by name
local function GetTaxiStationByName(name)
    EnsureTaxiStations()
    for _, station in ipairs(taxiStations) do
        if station.StationName == name then
            return station
        end
    end
    return nil
end

-- Get all taxi station names
local function GetAllTaxiStationNames()
    EnsureTaxiStations()
    local names = {}
    for _, station in ipairs(taxiStations) do
        if station.StationName then
            names[#names + 1] = station.StationName
        end
    end
    return names
end

-- Assign NPC as taxi passenger (from context menu)
function NPCPassengers.AssignPassenger(npc, ply, destinationName)
    if not IsValid(npc) then return false end

    local station = GetNearestTaxiStation(npc)
    if not station then
        if IsValid(ply) then
            ply:ChatPrint("No taxi stations available!")
        end
        return false
    end

    -- Get destination by name if provided, otherwise random
    local destination
    if destinationName then
        destination = GetTaxiStationByName(destinationName)
    else
        destination = GetRandomTaxiStation(station)
    end

    if not destination then
        if IsValid(ply) then
            ply:ChatPrint("No destination available!")
        end
        return false
    end

    -- Store taxi request data
    taxiPassengers[npc] = {
        station = station,
        state = "walking_to_station",
        startTime = CurTime(),
        destination = destination
    }

    -- Make NPC walk to station
    npc:SetLastPosition(station:GetPos())
    npc:SetSchedule(SCHED_FORCED_GO)

    -- Disable AI behavior to prevent staring at player
    npc:SetNPCState(NPC_STATE_IDLE)

    if IsValid(ply) then
        local destName = destination.StationName or "Unknown"
        ply:ChatPrint("NPC assigned as taxi passenger! Walking to " .. station.StationName .. ", destination: " .. destName)
    end

    return true
end

-- Main taxi system think hook
hook.Add("Think", "NPCPassengers_TaxiIntegration", function()
    if not NPCPassengers.IsAddonEnabled() then return end

    local curTime = CurTime()

    -- Process taxi passengers
    for npc, data in pairs(taxiPassengers) do
        if not IsValid(npc) then
            taxiPassengers[npc] = nil
            continue
        end

        if data.state == "walking_to_station" then
            local station = data.station
            if not IsValid(station) then
                taxiPassengers[npc] = nil
                continue
            end

            local dist = npc:GetPos():Distance(station:GetPos())

            -- Check if NPC arrived at station
            if dist < 50 then
                data.state = "waiting_for_taxi"
                data.waitStartTime = curTime

                -- Make NPC wait
                npc:SetSchedule(SCHED_IDLE_STAND)
            elseif curTime - data.startTime > 30 then
                -- Timeout, give up
                taxiPassengers[npc] = nil
            else
                -- Keep walking
                if npc:IsCurrentSchedule(SCHED_IDLE_STAND) or npc:IsCurrentSchedule(SCHED_ALERT_STAND) then
                    npc:SetLastPosition(station:GetPos())
                    npc:SetSchedule(SCHED_FORCED_GO)
                end
            end
        elseif data.state == "waiting_for_taxi" then
            -- Wait for player to arrive with vehicle
            if curTime - data.waitStartTime > 120 then
                -- Timeout waiting for taxi
                taxiPassengers[npc] = nil
            end
        elseif data.state == "in_taxi" then
            -- NPC is in vehicle, check if arrived at destination
            if not IsValid(data.vehicle) then
                taxiPassengers[npc] = nil
                continue
            end

            local destination = data.destination
            if not IsValid(destination) then
                taxiPassengers[npc] = nil
                continue
            end

            local vehiclePos = data.vehicle:GetPos()
            local dist = vehiclePos:Distance(destination:GetPos())

            if dist < 300 then
                -- Arrived at destination, detach NPC
                if NPCPassengers and NPCPassengers.DetachNPC then
                    NPCPassengers.DetachNPC(npc)
                end

                -- Make NPC walk away from station
                local walkDir = (vehiclePos - destination:GetPos()):GetNormal()
                npc:SetPos(destination:GetPos() + walkDir * 150)
                npc:SetLastPosition(destination:GetPos() + walkDir * 300)
                npc:SetSchedule(SCHED_FORCED_GO)

                -- Remove from taxi passengers
                taxiPassengers[npc] = nil

                -- Notify player
                local ply = data.player
                if IsValid(ply) then
                    ply:ChatPrint("Taxi passenger dropped off at " .. destination.StationName)
                end
            end
        end
    end
end)

-- Player enters vehicle near station - pick up waiting passengers
hook.Add("PlayerEnteredVehicle", "NPCPassengers_TaxiPickup", function(ply, vehicle, role)
    if not NPCPassengers.IsAddonEnabled() then return end

    local station = GetNearestTaxiStation(vehicle)
    if not IsValid(station) then return end

    local vehiclePos = vehicle:GetPos()
    local pickupRadius = 200

    -- Find waiting passengers at this station
    for npc, data in pairs(taxiPassengers) do
        if not IsValid(npc) then continue end
        if data.state ~= "waiting_for_taxi" then continue end
        if data.station ~= station then continue end

        local npcPos = npc:GetPos()
        local dist = vehiclePos:Distance(npcPos)

        if dist < pickupRadius then
            -- Attach NPC to vehicle
            if NPCPassengers and NPCPassengers.AttachPassenger then
                NPCPassengers.AttachPassenger(npc, vehicle)
            end

            -- Update passenger state
            data.state = "in_taxi"
            data.vehicle = vehicle
            data.player = ply

            ply:ChatPrint("Picked up taxi passenger! Destination: " .. (data.destination.StationName or "Unknown"))
        end
    end
end)

-- Export functions
NPCPassengers.IsDecentVehicleLoaded = function() return true end
NPCPassengers.FindTaxiStations = EnsureTaxiStations
NPCPassengers.GetNearestTaxiStation = GetNearestTaxiStation
NPCPassengers.GetTaxiStationByName = GetTaxiStationByName
NPCPassengers.GetAllTaxiStationNames = GetAllTaxiStationNames
NPCPassengers.CreateTaxiStation = CreateTaxiStation
NPCPassengers.AssignPassenger = NPCPassengers.AssignPassenger

-- Create global reference for main.lua
NPCTaxi = {
    AssignPassenger = NPCPassengers.AssignPassenger,
    GetAllTaxiStationNames = GetAllTaxiStationNames,
    GetTaxiStationByName = GetTaxiStationByName
}
