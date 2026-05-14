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
local taxiStations = {} -- Taxi station entities (current map only)
local persistedStations = {} -- Persisted station data from SQL
local droppedOffCooldowns = {} -- Cooldowns for NPCs recently dropped off

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

-- SQL Database for taxi stations
local DB_NAME = "npc_passengers_taxi"
local STATION_TABLE = "taxi_stations"

local function InitializeDatabase()
    if not sql.TableExists(DB_NAME) then
        sql.Query("CREATE TABLE " .. DB_NAME .. " (id INTEGER PRIMARY KEY, map TEXT, name TEXT, pos_x REAL, pos_y REAL, pos_z REAL, ang_y REAL, ang_p REAL, ang_r REAL, model TEXT)")
    end
end

-- Save station to database
local function SaveStationToDB(station)
    if not IsValid(station) then return end

    local pos = station:GetPos()
    local ang = station:GetAngles()
    local map = game.GetMap()

    -- Check if station already exists in DB
    local existing = sql.Query("SELECT id FROM " .. DB_NAME .. " WHERE map = " .. sql.SQLStr(map) .. " AND name = " .. sql.SQLStr(station.StationName or ""))

    if existing and #existing > 0 then
        -- Update existing station
        sql.Query("UPDATE " .. DB_NAME .. " SET pos_x = " .. pos.x .. ", pos_y = " .. pos.y .. ", pos_z = " .. pos.z .. ", ang_y = " .. ang.y .. ", ang_p = " .. ang.p .. ", ang_r = " .. ang.r .. ", model = " .. sql.SQLStr(station:GetModel()) .. " WHERE id = " .. existing[1].id)
    else
        -- Insert new station
        sql.Query("INSERT INTO " .. DB_NAME .. " (map, name, pos_x, pos_y, pos_z, ang_y, ang_p, ang_r, model) VALUES (" .. sql.SQLStr(map) .. ", " .. sql.SQLStr(station.StationName or "") .. ", " .. pos.x .. ", " .. pos.y .. ", " .. pos.z .. ", " .. ang.y .. ", " .. ang.p .. ", " .. ang.r .. ", " .. sql.SQLStr(station:GetModel()) .. ")")
    end
end

-- Remove station from database
local function RemoveStationFromDB(station)
    if not IsValid(station) then return end

    local map = game.GetMap()
    sql.Query("DELETE FROM " .. DB_NAME .. " WHERE map = " .. sql.SQLStr(map) .. " AND name = " .. sql.SQLStr(station.StationName or ""))
end

-- Load stations from database for current map
local function LoadStationsFromDB()
    InitializeDatabase()

    local map = game.GetMap()
    local results = sql.Query("SELECT * FROM " .. DB_NAME .. " WHERE map = " .. sql.SQLStr(map))

    if not results or #results == 0 then return {} end

    local stations = {}
    for _, row in ipairs(results) do
        stations[#stations + 1] = {
            name = row.name,
            pos = Vector(row.pos_x, row.pos_y, row.pos_z),
            ang = Angle(row.ang_p, row.ang_y, row.ang_r),
            model = row.model
        }
    end

    return stations
end

-- Restore station from database
local function RestoreStation(stationData)
    -- Use default model if saved model is invalid
    local validModel = (stationData.model and stationData.model ~= "" and util.IsValidModel(stationData.model)) and stationData.model or "models/props_combine/combine_barricade_short02a.mdl"
    
    local station = ents.Create("prop_physics")
    station:SetModel(validModel)
    station:SetPos(stationData.pos)
    station:SetAngles(stationData.ang)
    station:Spawn()
    
    -- Don't set MOVETYPE_NONE or PhysicsInitStatic
    station:SetSolid(SOLID_VPHYSICS)
    station:SetUseType(SIMPLE_USE)
    
    -- Disable motion so it stays in place
    local phys = station:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end

    station.IsTaxiStation = true
    station.StationName = stationData.name

    taxiStations[#taxiStations + 1] = station
    return station
end

-- Create taxi station entity
local function CreateTaxiStation(pos, name, model)
    local station = ents.Create("prop_physics")
    -- Use default model if none provided or if model is invalid
    local validModel = (model and model ~= "" and util.IsValidModel(model)) and model or "models/props_combine/combine_barricade_short02a.mdl"
    station:SetModel(validModel)
    station:SetPos(pos)
    station:SetAngles(Angle(0, 0, 0))
    station:Spawn()
    
    -- Don't set MOVETYPE_NONE or PhysicsInitStatic, let it be a normal physics prop
    station:SetSolid(SOLID_VPHYSICS)
    station:SetUseType(SIMPLE_USE)
    
    -- Disable motion so it stays in place
    local phys = station:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end

    station.IsTaxiStation = true
    station.StationName = name or GetRandomStationName()

    taxiStations[#taxiStations + 1] = station

    -- Save to database
    SaveStationToDB(station)

    return station
end

-- Find or create taxi stations on the map
local function EnsureTaxiStations()
    if #taxiStations > 0 then return taxiStations end

    -- Try to find existing taxi stations in the map
    for _, ent in ipairs(ents.GetAll()) do
        if ent.IsTaxiStation then
            taxiStations[#taxiStations + 1] = ent
        end
    end

    -- Load stations from database for current map
    local savedStations = LoadStationsFromDB()
    if #savedStations > 0 then
        for _, stationData in ipairs(savedStations) do
            -- Check if station already exists in map (avoid duplicates)
            local exists = false
            for _, existingStation in ipairs(taxiStations) do
                if IsValid(existingStation) and existingStation.StationName == stationData.name then
                    exists = true
                    break
                end
            end

            if not exists then
                RestoreStation(stationData)
            end
        end
    end

    -- If still no stations exist, create some at spawn points
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

-- Get all taxi station names (only valid stations in current map)
local function GetAllTaxiStationNames()
    EnsureTaxiStations()
    local names = {}
    for _, station in ipairs(taxiStations) do
        if IsValid(station) and station.StationName then
            names[#names + 1] = station.StationName
        end
    end
    return names
end

-- Remove taxi station (from both map and database)
function NPCPassengers.RemoveTaxiStation(station)
    if not IsValid(station) then return end

    -- Remove from database
    RemoveStationFromDB(station)

    -- Remove from local table
    for i, s in ipairs(taxiStations) do
        if s == station then
            table.remove(taxiStations, i)
            break
        end
    end

    -- Remove entity
    station:Remove()
end

-- Clear all taxi stations for current map
function NPCPassengers.ClearAllTaxiStations()
    local map = game.GetMap()

    -- Remove from database
    sql.Query("DELETE FROM " .. DB_NAME .. " WHERE map = " .. sql.SQLStr(map))

    -- Remove all entities
    for _, station in ipairs(taxiStations) do
        if IsValid(station) then
            station:Remove()
        end
    end

    -- Clear local table
    taxiStations = {}
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

    -- Make NPC walk to station using standard AI (no schedule/state modifications)
    npc:SetLastPosition(station:GetPos())

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
            elseif curTime - data.startTime > 30 then
                -- Timeout, give up
                taxiPassengers[npc] = nil
            else
                -- Keep walking using standard AI
                npc:SetLastPosition(station:GetPos())
            end
        elseif data.state == "waiting_for_taxi" then
            -- Check for nearby player vehicles to pick up NPC
            local station = data.station
            if not IsValid(station) then
                taxiPassengers[npc] = nil
                continue
            end

            local npcPos = npc:GetPos()
            local pickupRadius = 250

            -- Check all players for nearby vehicles
            for _, ply in ipairs(player.GetAll()) do
                if not IsValid(ply) then continue end
                local vehicle = ply:GetVehicle()
                if not IsValid(vehicle) then continue end

                local vehiclePos = vehicle:GetPos()
                local dist = vehiclePos:Distance(npcPos)

                if dist < pickupRadius then
                    -- Check if NPC is in cooldown (recently dropped off)
                    local npcId = npc:EntIndex()
                    if droppedOffCooldowns[npcId] and droppedOffCooldowns[npcId] > curTime then
                        continue -- Skip pickup, NPC is in cooldown
                    end

                    -- Attach NPC to vehicle
                    if NPCPassengers and NPCPassengers.AttachPassenger then
                        NPCPassengers.AttachPassenger(npc, vehicle)
                    end

                    -- Update passenger state
                    data.state = "in_taxi"
                    data.vehicle = vehicle
                    data.player = ply

                    ply:ChatPrint("Picked up taxi passenger! Destination: " .. (data.destination.StationName or "Unknown"))
                    break
                end
            end

            -- Timeout waiting for taxi
            if curTime - data.waitStartTime > 120 then
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

                -- Make NPC walk away from station using standard AI
                local walkDir = (vehiclePos - destination:GetPos()):GetNormal()
                npc:SetPos(destination:GetPos() + walkDir * 150)
                npc:SetLastPosition(destination:GetPos() + walkDir * 300)

                -- Remove from taxi passengers
                taxiPassengers[npc] = nil

                -- Notify player
                local ply = data.player
                if IsValid(ply) then
                    ply:ChatPrint("Taxi passenger dropped off at " .. destination.StationName)
                end

                -- Allow NPC to be picked up again immediately (but with taxi cooldown)
                if NPCPassengers and NPCPassengers.ClearBoardRetryState then
                    NPCPassengers.ClearBoardRetryState(npc)
                end

                -- Set taxi pickup cooldown to prevent immediate re-attachment
                droppedOffCooldowns[npc:EntIndex()] = curTime + 5 -- 5 second cooldown
            end
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
NPCPassengers.RemoveTaxiStation = NPCPassengers.RemoveTaxiStation
NPCPassengers.ClearAllTaxiStations = NPCPassengers.ClearAllTaxiStations
NPCPassengers.AssignPassenger = NPCPassengers.AssignPassenger

-- Create global reference for main.lua
NPCTaxi = {
    AssignPassenger = NPCPassengers.AssignPassenger,
    GetAllTaxiStationNames = GetAllTaxiStationNames,
    GetTaxiStationByName = GetTaxiStationByName
}
