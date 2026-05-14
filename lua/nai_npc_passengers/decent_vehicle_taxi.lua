if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.decent_vehicle_taxi = true

-- Standalone Taxi System
-- NPCs can use taxis to travel between taxi stations without requiring Decent Vehicle addon

local IsValid = IsValid
local CurTime = CurTime
local math = math
local pairs = pairs
local ipairs = ipairs

local taxiPassengers = {} -- NPC passengers waiting for taxis
local taxiStations = {} -- Taxi station entities
local taxiDrivers = {} -- Taxi driver NPCs

-- Random station names (improved from Decent Vehicle)
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
    station:SetModel("models/props_c17/streetsign004c.mdl") -- Temporary model
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

-- Create taxi driver NPC
local function CreateTaxiDriver(pos, vehicle)
    local driver = ents.Create("npc_citizen")
    driver:SetPos(pos)
    driver:SetAngles(Angle(0, 0, 0))
    driver:Spawn()
    driver:SetModel("models/player/odessa.mdl")
    driver:Give("weapon_pistol")
    driver:SetHealth(100)

    driver.IsTaxiDriver = true
    driver.TaxiVehicle = vehicle
    driver.CurrentPassenger = nil
    driver.DestinationStation = nil
    driver.State = "idle" -- idle, finding_vehicle, picking_up, transporting, returning
    driver.PendingPassenger = nil
    driver.PendingDestination = nil

    taxiDrivers[driver] = true
    return driver
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

-- Get nearest taxi station to an NPC
local function GetNearestTaxiStation(npc)
    EnsureTaxiStations()
    if #taxiStations == 0 then return nil end
    
    local npcPos = npc:GetPos()
    local nearestStation = nil
    local nearestDist = math.huge
    
    for _, station in ipairs(taxiStations) do
        if not IsValid(station) then continue end
        local dist = npcPos:Distance(station:GetPos())
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

-- Make NPC go to taxi station
function NPCPassengers.SendNPCtoTaxiStation(npc)
    if not IsValid(npc) then return false end

    local station = GetNearestTaxiStation(npc)
    if not station then return false end

    -- Store taxi request data
    taxiPassengers[npc] = {
        station = station,
        state = "walking_to_station",
        startTime = CurTime(),
        destination = GetRandomTaxiStation(station)
    }

    -- Make NPC walk to station
    npc:SetLastPosition(station:GetPos())
    npc:SetSchedule(SCHED_FORCED_GO)

    return true
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

-- Check if NPC should use taxi
local function ShouldNPCUseTaxi(npc)
    if not NPCPassengers.cv_taxi_enabled:GetBool() then return false end
    
    -- Random chance from ConVar
    local taxiChance = NPCPassengers.cv_taxi_chance:GetFloat()
    if math.random() > taxiChance then return false end
    
    -- Only civilians should use taxis
    local class = npc:GetClass()
    if string.find(class, "police") or string.find(class, "combine") then
        return false
    end
    
    -- Must have taxi stations available
    EnsureTaxiStations()
    if #taxiStations == 0 then return false end
    
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
                
                -- Try to find or create a taxi driver
                local driver = NPCPassengers.FindOrCreateTaxiDriver(station)
                if driver then
                    NPCPassengers.AssignPassengerToTaxi(driver, npc, data.destination)
                end
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
            -- Wait for taxi driver to arrive
            if curTime - data.waitStartTime > 60 then
                -- Timeout waiting for taxi
                taxiPassengers[npc] = nil
            end
        end
    end
    
    -- Process taxi drivers
    for driver, _ in pairs(taxiDrivers) do
        if not IsValid(driver) then
            taxiDrivers[driver] = nil
            continue
        end
        
        NPCPassengers.UpdateTaxiDriver(driver, curTime)
    end
end)

-- Find or create a taxi driver for a station
function NPCPassengers.FindOrCreateTaxiDriver(station)
    -- Find idle taxi driver near station
    for driver, _ in pairs(taxiDrivers) do
        if not IsValid(driver) then continue end
        if driver.State == "idle" and IsValid(driver.TaxiVehicle) then
            local dist = driver:GetPos():Distance(station:GetPos())
            if dist < 1000 then
                return driver
            end
        end
    end

    -- Create new taxi driver if none available
    local driver = CreateTaxiDriver(station:GetPos() + Vector(0, 100, 0), nil)
    driver.State = "finding_vehicle"
    return driver
end

-- Assign passenger to taxi driver
function NPCPassengers.AssignPassengerToTaxi(driver, npc, destination)
    if not IsValid(driver) or not IsValid(npc) then return end
    if not IsValid(destination) then return end

    -- Check if driver has a vehicle, if not, find one first
    if not IsValid(driver.TaxiVehicle) then
        driver.State = "finding_vehicle"
        -- Set the assignment data for when vehicle is found
        driver.PendingPassenger = npc
        driver.PendingDestination = destination
        return
    end

    driver.CurrentPassenger = npc
    driver.DestinationStation = destination
    driver.State = "picking_up"

    -- Update passenger state
    if taxiPassengers[npc] then
        taxiPassengers[npc].state = "assigned_to_taxi"
        taxiPassengers[npc].driver = driver
    end
end

-- Update taxi driver behavior
function NPCPassengers.UpdateTaxiDriver(driver, curTime)
    if driver.State == "idle" then
        -- Check if driver has a vehicle, if not, find one
        if not IsValid(driver.TaxiVehicle) then
            driver.State = "finding_vehicle"
        else
            -- Idle behavior - wander near station/vehicle
            if curTime % 5 < 0.1 then
                driver:SetSchedule(SCHED_IDLE_WANDER)
            end
        end

    elseif driver.State == "finding_vehicle" then
        -- Find a nearby vehicle
        local driverPos = driver:GetPos()
        local nearestVehicle = nil
        local nearestDist = math.huge

        for _, ent in ipairs(ents.FindInSphere(driverPos, 2000, driver)) do
            if IsValid(ent) and ent:IsVehicle() then
                local dist = driverPos:Distance(ent:GetPos())
                -- Check if vehicle is already being used by another taxi driver
                local alreadyUsed = false
                for otherDriver, _ in pairs(taxiDrivers) do
                    if IsValid(otherDriver) and otherDriver ~= driver and otherDriver.TaxiVehicle == ent then
                        alreadyUsed = true
                        break
                    end
                end

                if not alreadyUsed and dist < nearestDist then
                    nearestDist = dist
                    nearestVehicle = ent
                end
            end
        end

        if IsValid(nearestVehicle) and nearestDist < 500 then
            -- Enter the vehicle
            driver.TaxiVehicle = nearestVehicle
            driver:SetPos(nearestVehicle:GetPos() + Vector(0, 0, 50))
            driver:EnterVehicle(nearestVehicle)

            -- If there's a pending passenger assignment, activate it
            if IsValid(driver.PendingPassenger) and IsValid(driver.PendingDestination) then
                driver.CurrentPassenger = driver.PendingPassenger
                driver.DestinationStation = driver.PendingDestination
                driver.State = "picking_up"
                driver.PendingPassenger = nil
                driver.PendingDestination = nil

                -- Update passenger state
                if taxiPassengers[driver.CurrentPassenger] then
                    taxiPassengers[driver.CurrentPassenger].state = "assigned_to_taxi"
                    taxiPassengers[driver.CurrentPassenger].driver = driver
                end
            else
                driver.State = "idle"
            end
        elseif nearestDist > 500 then
            -- Walk towards vehicle
            driver:SetLastPosition(nearestVehicle:GetPos())
            driver:SetSchedule(SCHED_FORCED_GO)
        end

    elseif driver.State == "picking_up" then
        -- Drive to passenger location
        local passenger = driver.CurrentPassenger
        if not IsValid(passenger) then
            driver.State = "idle"
            driver.CurrentPassenger = nil
            return
        end

        if not IsValid(driver.TaxiVehicle) then
            driver.State = "finding_vehicle"
            return
        end

        -- Check if driver is in the vehicle
        local driverSeat = driver:GetVehicle()
        if not IsValid(driverSeat) or driverSeat ~= driver.TaxiVehicle then
            driver:EnterVehicle(driver.TaxiVehicle)
        end

        local passengerPos = passenger:GetPos()
        local vehiclePos = driver.TaxiVehicle:GetPos()
        local dist = vehiclePos:Distance(passengerPos)

        if dist < 200 then
            -- Arrived at passenger, pick them up
            driver.State = "transporting"

            -- Attach passenger to vehicle
            if NPCPassengers and NPCPassengers.AttachPassenger then
                NPCPassengers.AttachPassenger(passenger, driver.TaxiVehicle)
            end

            -- Update passenger state
            if taxiPassengers[passenger] then
                taxiPassengers[passenger].state = "in_taxi"
                taxiPassengers[passenger].driver = driver
            end
        else
            -- Drive towards passenger
            driver.TaxiVehicle:SetPos(vehiclePos + (passengerPos - vehiclePos):GetNormal() * 100)
        end

    elseif driver.State == "transporting" then
        -- Drive to destination station
        local destination = driver.DestinationStation
        if not IsValid(destination) then
            driver.State = "returning"
            driver.DestinationStation = nil
            return
        end

        if not IsValid(driver.TaxiVehicle) then
            driver.State = "finding_vehicle"
            return
        end

        -- Check if driver is in the vehicle
        local driverSeat = driver:GetVehicle()
        if not IsValid(driverSeat) or driverSeat ~= driver.TaxiVehicle then
            driver:EnterVehicle(driver.TaxiVehicle)
        end

        local destPos = destination:GetPos()
        local vehiclePos = driver.TaxiVehicle:GetPos()
        local dist = vehiclePos:Distance(destPos)

        if dist < 300 then
            -- Arrived at destination, drop off passenger
            local passenger = driver.CurrentPassenger
            if IsValid(passenger) then
                -- Detach passenger
                if NPCPassengers and NPCPassengers.DetachNPC then
                    NPCPassengers.DetachNPC(passenger)
                end

                -- Make passenger walk away from station
                local walkDir = (vehiclePos - destPos):GetNormal()
                passenger:SetPos(destPos + walkDir * 150)
                passenger:SetLastPosition(destPos + walkDir * 300)
                passenger:SetSchedule(SCHED_FORCED_GO)

                -- Remove from taxi passengers
                taxiPassengers[passenger] = nil
            end

            driver.State = "returning"
            driver.CurrentPassenger = nil
        else
            -- Drive towards destination
            driver.TaxiVehicle:SetPos(vehiclePos + (destPos - vehiclePos):GetNormal() * 200)
        end

    elseif driver.State == "returning" then
        -- Return to nearest station or idle
        local station = GetNearestTaxiStation(driver.TaxiVehicle or driver)
        if IsValid(station) then
            local vehiclePos = driver.TaxiVehicle and driver.TaxiVehicle:GetPos() or driver:GetPos()
            local dist = vehiclePos:Distance(station:GetPos())

            if dist < 300 then
                driver.State = "idle"
            else
                -- Drive towards station
                if IsValid(driver.TaxiVehicle) then
                    driver.TaxiVehicle:SetPos(vehiclePos + (station:GetPos() - vehiclePos):GetNormal() * 200)
                end
            end
        else
            driver.State = "idle"
        end
    end
end

-- Export functions
NPCPassengers.IsDecentVehicleLoaded = function() return true end -- Always return true now
NPCPassengers.FindTaxiStations = EnsureTaxiStations
NPCPassengers.GetNearestTaxiStation = GetNearestTaxiStation
NPCPassengers.GetTaxiStationByName = GetTaxiStationByName
NPCPassengers.GetAllTaxiStationNames = GetAllTaxiStationNames
NPCPassengers.CreateTaxiStation = CreateTaxiStation
NPCPassengers.CreateTaxiDriver = CreateTaxiDriver
NPCPassengers.AssignPassenger = NPCPassengers.AssignPassenger

-- Create global reference for main.lua
NPCTaxi = {
    AssignPassenger = NPCPassengers.AssignPassenger,
    GetAllTaxiStationNames = GetAllTaxiStationNames,
    GetTaxiStationByName = GetTaxiStationByName
}
