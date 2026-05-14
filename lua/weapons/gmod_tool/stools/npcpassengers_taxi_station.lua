TOOL.Category = "NPC Passengers"
TOOL.Name = "#tool.npcpassengers_taxi_station.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.npcpassengers_taxi_station.name", "Taxi Station")
    language.Add("tool.npcpassengers_taxi_station.desc", "Create a taxi station for NPC taxi system")
    language.Add("tool.npcpassengers_taxi_station.0", "Left-click to place a taxi station. Right-click to remove.")
    language.Add("tool.npcpassengers_taxi_station.left", "Place Taxi Station")
    language.Add("tool.npcpassengers_taxi_station.right", "Remove Taxi Station")
end

TOOL.ClientConVar["model"] = "models/props_c17/streetsign004c.mdl"
TOOL.ClientConVar["station_name"] = ""

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Description = "#tool.npcpassengers_taxi_station.desc"
    })

    panel:AddControl("TextBox", {
        Label = "Station Name (optional)",
        Command = "npcpassengers_taxi_station_station_name",
        MaxLength = 50
    })

    -- Add label for model selection
    panel:AddControl("Label", {
        Text = "Model Selection:"
    })

    -- Use DComboBox for model selection instead of PropSelect
    local comboBox = vgui.Create("DComboBox", panel)
    comboBox:SetTall(30)
    comboBox:Dock(TOP)
    comboBox:SetValue("models/props_c17/streetsign004c.mdl")

    local models = {
        "models/props_c17/streetsign004c.mdl",
        "models/props_c17/gravestone003a.mdl",
        "models/props_combine/combine_barricade_short02a.mdl",
        "models/props_junk/trafficcone001a.mdl",
        "models/props_c17/pulleywheels_large01.mdl"
    }

    local modelNames = {
        "Street Sign",
        "Gravestone",
        "Barricade",
        "Traffic Cone",
        "Pulley Wheel"
    }

    for i, model in ipairs(models) do
        comboBox:AddChoice(modelNames[i], model)
    end

    comboBox.OnSelect = function(index, value, data)
        RunConsoleCommand("npcpassengers_taxi_station_model", data)
    end

    panel:AddItem(comboBox)

    panel:AddControl("Label", {
        Text = "Left Click: Place station\nRight Click: Remove station\nReload: Remove all stations"
    })
end

function TOOL:LeftClick(trace)
    if not trace.HitPos then return false end
    if trace.Entity and trace.Entity:IsPlayer() then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    local name = self:GetClientInfo("station_name")
    local model = self:GetClientInfo("model")

    -- Create taxi station
    if NPCPassengers and NPCPassengers.CreateTaxiStation then
        local station = NPCPassengers.CreateTaxiStation(trace.HitPos, name ~= "" and name or nil)

        if IsValid(station) then
            if model and model ~= "" then
                station:SetModel(model)
            end

            -- Play sound effect
            ply:EmitSound("buttons/button14.wav")

            -- Create visual effect
            local effectdata = EffectData()
            effectdata:SetOrigin(trace.HitPos)
            effectdata:SetScale(1)
            util.Effect("cball_explode", effectdata)

            ply:ChatPrint("Taxi station created: " .. (station.StationName or "Unknown"))
            return true
        else
            ply:ChatPrint("Failed to create taxi station!")
            ply:EmitSound("buttons/button10.wav")
            return false
        end
    else
        ply:ChatPrint("Taxi system not available!")
        ply:EmitSound("buttons/button10.wav")
        return false
    end
end

function TOOL:RightClick(trace)
    if not trace.Hit then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()

    -- Check if clicking on a taxi station
    if trace.Entity and trace.Entity.IsTaxiStation then
        local name = trace.Entity.StationName or "Unknown"
        trace.Entity:Remove()

        -- Play sound effect
        ply:EmitSound("buttons/button15.wav")

        ply:ChatPrint("Taxi station removed: " .. name)
        return true
    end

    return false
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()

    -- Remove all taxi stations
    if NPCPassengers and NPCPassengers.FindTaxiStations then
        local stations = NPCPassengers.FindTaxiStations()
        local count = 0

        for _, station in ipairs(stations) do
            if IsValid(station) and station.IsTaxiStation then
                local name = station.StationName or "Unknown"
                station:Remove()
                count = count + 1
            end
        end

        -- Play sound effect
        if count > 0 then
            ply:EmitSound("buttons/button15.wav")
        else
            ply:EmitSound("buttons/button10.wav")
        end

        ply:ChatPrint("Removed " .. count .. " taxi station(s)")
        return true
    end

    return false
end

function TOOL:DrawToolScreen(width, height)
    surface.SetDrawColor(50, 50, 50, 255)
    surface.DrawRect(0, 0, width, height)

    surface.SetDrawColor(255, 200, 0, 255)
    surface.DrawRect(width/2 - 2, height/2 - 2, 4, 4)

    draw.DrawText("TAXI STATION", "Trebuchet24", width/2, height/2 - 40, Color(255, 255, 255), TEXT_ALIGN_CENTER)
    draw.DrawText("Left Click: Place", "Trebuchet18", width/2, height/2 + 10, Color(200, 200, 200), TEXT_ALIGN_CENTER)
    draw.DrawText("Right Click: Remove", "Trebuchet18", width/2, height/2 + 30, Color(200, 200, 200), TEXT_ALIGN_CENTER)
    draw.DrawText("Reload: Clear All", "Trebuchet18", width/2, height/2 + 50, Color(200, 200, 200), TEXT_ALIGN_CENTER)
end

if CLIENT then
    function TOOL:DrawHUD()
        local ply = LocalPlayer()
        local trace = ply:GetEyeTrace()

        if trace.Hit and not trace.HitSky then
            local pos = trace.HitPos:ToScreen()

            -- Check if looking at a taxi station
            if trace.Entity and trace.Entity.IsTaxiStation then
                local stationName = trace.Entity.StationName or "Unknown"
                surface.SetFont("Trebuchet24")
                local w, h = surface.GetTextSize(stationName)

                -- Draw name tag above the prop
                draw.RoundedBox(8, pos.x - w/2 - 8, pos.y - h - 40, w + 16, h + 20, Color(0, 0, 0, 220))
                draw.RoundedBox(8, pos.x - w/2 - 6, pos.y - h - 38, w + 12, h + 16, Color(255, 200, 0, 200))
                draw.DrawText(stationName, "Trebuchet24", pos.x, pos.y - h - 30, Color(255, 255, 255), TEXT_ALIGN_CENTER)
            end
        end
    end

    function TOOL:Think()
        -- Update tool info
    end
end
