if CLIENT then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.decent_vehicle_taxi = true

-- Decent Vehicle Taxi Integration
-- Allows NPC passengers to use taxi stations and ride with Decent Vehicle taxi drivers

local IsValid = IsValid
local CurTime = CurTime
local math = math
local pairs = pairs
local ipairs = ipairs

local taxiPassengers = {} -- NPC passengers waiting for taxis
local taxiDestinations = {} -- Taxi station entities
local decentVehicleLoaded = false

-- Check if Decent Vehicle addon is loaded
local function IsDecentVehicleLoaded()
    if decentVehicleLoaded then return true end
    
    -- Check for Decent Vehicle global
    if DecentVehicle and DecentVehicleDestination then
        decentVehicleLoaded = true
        return true
    end
    
    -- Check for taxi station entities
    for _, ent in ipairs(ents.GetAll()) do
        if ent:GetClass() == "ent_dvtaxi_station" then
            decentVehicleLoaded = true
            return true
        end
    end
    
    return false
end

-- Find all taxi stations on the map
local function FindTaxiStations()
    taxiDestinations = {}
    for _, ent in ipairs(ents.GetAll()) do
        if ent:GetClass() == "ent_dvtaxi_station" and IsValid(ent) then
            taxiDestinations[#taxiDestinations + 1] = ent
        end
    end
    return taxiDestinations
end

-- Get nearest taxi station to an NPC
local function GetNearestTaxiStation(npc)
    if #taxiDestinations == 0 then
        FindTaxiStations()
    end
    
    if #taxiDestinations == 0 then return nil end
    
    local npcPos = npc:GetPos()
    local nearestStation = nil
    local nearestDist = math.huge
    
    for _, station in ipairs(taxiDestinations) do
        if not IsValid(station) then continue end
        local dist = npcPos:Distance(station:GetPos())
        if dist < nearestDist then
            nearestDist = dist
            nearestStation = station
        end
    end
    
    return nearestStation
end

-- Make NPC go to taxi station
function NPCPassengers.SendNPCtoTaxiStation(npc)
    if not IsDecentVehicleLoaded() then return false end
    if not IsValid(npc) then return false end
    
    local station = GetNearestTaxiStation(npc)
    if not station then return false end
    
    -- Store taxi request data
    taxiPassengers[npc] = {
        station = station,
        state = "walking_to_station",
        startTime = CurTime()
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
    if #taxiDestinations == 0 then
        FindTaxiStations()
    end
    
    if #taxiDestinations == 0 then return false end
    
    return true
end

-- Hook into passenger system to add taxi behavior
hook.Add("Think", "NPCPassengers_TaxiIntegration", function()
    if not IsAddonEnabled() then return end
    if not IsDecentVehicleLoaded() then return end
    
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
            -- Wait for taxi driver to arrive
            -- This would integrate with Decent Vehicle's taxi system
            if curTime - data.waitStartTime > 60 then
                -- Timeout waiting for taxi
                taxiPassengers[npc] = nil
            end
        end
    end
end)

-- Register taxi stations when they spawn
hook.Add("OnEntityCreated", "NPCPassengers_TaxiStationTracker", function(ent)
    if not IsValid(ent) then return end
    if ent:GetClass() == "ent_dvtaxi_station" then
        taxiDestinations[#taxiDestinations + 1] = ent
    end
end)

-- Clean up when stations are removed
hook.Add("EntityRemoved", "NPCPassengers_TaxiStationCleanup", function(ent)
    if not IsValid(ent) then return end
    if ent:GetClass() == "ent_dvtaxi_station" then
        for i, station in ipairs(taxiDestinations) do
            if station == ent then
                table.remove(taxiDestinations, i)
                break
            end
        end
    end
end)

-- Export functions
NPCPassengers.IsDecentVehicleLoaded = IsDecentVehicleLoaded
NPCPassengers.FindTaxiStations = FindTaxiStations
NPCPassengers.GetNearestTaxiStation = GetNearestTaxiStation
