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
    station.StationName = name or ("Taxi Station " .. #taxiStations + 1)
    
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
    driver.State = "idle" -- idle, picking_up, transporting, returning
    
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
                CreateTaxiStation(pos + Vector(0, 0, 50), "Taxi Station " .. i)
            end
        else
            -- Fallback: create stations at origin offsets
            CreateTaxiStation(Vector(0, 200, 0), "Taxi Station North")
            CreateTaxiStation(Vector(0, -200, 0), "Taxi Station South")
            CreateTaxiStation(Vector(200, 0, 0), "Taxi Station East")
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
        if driver.State == "idle" then
            local dist = driver:GetPos():Distance(station:GetPos())
            if dist < 500 then
                return driver
            end
        end
    end
    
    -- Create new taxi driver if none available
    local driver = CreateTaxiDriver(station:GetPos() + Vector(0, 100, 0), nil)
    return driver
end

-- Assign passenger to taxi driver
function NPCPassengers.AssignPassengerToTaxi(driver, npc, destination)
    if not IsValid(driver) or not IsValid(npc) then return end
    
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
        -- Idle behavior - wander near station
        if curTime % 5 < 0.1 then
            driver:SetSchedule(SCHED_IDLE_WANDER)
        end
        
    elseif driver.State == "picking_up" then
        -- Drive to passenger location
        local passenger = driver.CurrentPassenger
        if not IsValid(passenger) then
            driver.State = "idle"
            driver.CurrentPassenger = nil
            return
        end
        
        local passengerPos = passenger:GetPos()
        local driverPos = driver:GetPos()
        local dist = driverPos:Distance(passengerPos)
        
        if dist < 100 then
            -- Arrived at passenger, pick them up
            driver.State = "transporting"
            
            -- Make passenger enter vehicle (if driver has one)
            if IsValid(driver.TaxiVehicle) then
                NPCPassengers.AttachPassenger(passenger, driver.TaxiVehicle)
            end
        else
            -- Move towards passenger
            driver:SetLastPosition(passengerPos)
            driver:SetSchedule(SCHED_FORCED_GO)
        end
        
    elseif driver.State == "transporting" then
        -- Drive to destination station
        local destination = driver.DestinationStation
        if not IsValid(destination) then
            driver.State = "idle"
            driver.DestinationStation = nil
            return
        end
        
        local destPos = destination:GetPos()
        local driverPos = driver:GetPos()
        local dist = driverPos:Distance(destPos)
        
        if dist < 100 then
            -- Arrived at destination, drop off passenger
            local passenger = driver.CurrentPassenger
            if IsValid(passenger) then
                -- Detach passenger
                NPCPassengers.DetachNPC(passenger)
                
                -- Make passenger walk away
                passenger:SetLastPosition(destPos + Vector(100, 0, 0))
                passenger:SetSchedule(SCHED_FORCED_GO)
                
                -- Remove from taxi passengers
                taxiPassengers[passenger] = nil
            end
            
            driver.State = "returning"
            driver.CurrentPassenger = nil
        else
            -- Move towards destination
            driver:SetLastPosition(destPos)
            driver:SetSchedule(SCHED_FORCED_GO)
        end
        
    elseif driver.State == "returning" then
        -- Return to nearest station
        local station = GetNearestTaxiStation(driver)
        if IsValid(station) then
            local dist = driver:GetPos():Distance(station:GetPos())
            if dist < 100 then
                driver.State = "idle"
            else
                driver:SetLastPosition(station:GetPos())
                driver:SetSchedule(SCHED_FORCED_GO)
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
NPCPassengers.CreateTaxiStation = CreateTaxiStation
NPCPassengers.CreateTaxiDriver = CreateTaxiDriver
