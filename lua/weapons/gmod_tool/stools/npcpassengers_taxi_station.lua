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

    panel:AddControl("PropSelect", {
        Label = "Model",
        ConVar = "npcpassengers_taxi_station_model",
        Category = "Taxi Stations",
        Models = {
            ["models/props_c17/streetsign004c.mdl"] = "Street Sign",
            ["models/props_c17/gravestone003a.mdl"] = "Gravestone",
            ["models/props_combine/combine_barricade_short02a.mdl"] = "Barricade",
            ["models/props_junk/trafficcone001a.mdl"] = "Traffic Cone",
            ["models/props_c17/pulleywheels_large01.mdl"] = "Pulley Wheel"
        }
    })

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

            -- Draw station label
            surface.SetFont("Trebuchet24")
            local text = "Taxi Station"
            local w, h = surface.GetTextSize(text)

            draw.RoundedBox(4, pos.x - w/2 - 8, pos.y - h - 15, w + 16, h + 25, Color(0, 0, 0, 220))
            draw.DrawText(text, "Trebuchet24", pos.x, pos.y - h - 10, Color(255, 200, 0), TEXT_ALIGN_CENTER)

            -- Draw vertical arrows (more prominent)
            local arrowHeight = 80
            local arrowWidth = 12
            local centerX = pos.x
            local centerY = pos.y

            -- Top arrow (pointing up)
            surface.SetDrawColor(255, 200, 0, 255)
            surface.DrawRect(centerX - arrowWidth/2, centerY - arrowHeight + 15, arrowWidth, arrowHeight - 25)
            draw.NoTexture()
            surface.SetDrawColor(255, 200, 0, 255)
            local topArrowPoly = {
                {x = centerX - arrowWidth, y = centerY - arrowHeight + 20},
                {x = centerX + arrowWidth, y = centerY - arrowHeight + 20},
                {x = centerX, y = centerY - arrowHeight - 15}
            }
            surface.DrawPoly(topArrowPoly)

            -- Bottom arrow (pointing down)
            surface.SetDrawColor(255, 200, 0, 255)
            surface.DrawRect(centerX - arrowWidth/2, centerY + 15, arrowWidth, arrowHeight - 25)
            draw.NoTexture()
            surface.SetDrawColor(255, 200, 0, 255)
            local bottomArrowPoly = {
                {x = centerX - arrowWidth, y = centerY + arrowHeight - 20},
                {x = centerX + arrowWidth, y = centerY + arrowHeight - 20},
                {x = centerX, y = centerY + arrowHeight + 15}
            }
            surface.DrawPoly(bottomArrowPoly)

            -- Center indicator
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawRect(centerX - 3, centerY - 3, 6, 6)

            -- Distance indicator
            local dist = ply:EyePos():Distance(trace.HitPos)
            surface.SetFont("Trebuchet18")
            local distText = math.Round(dist) .. " units"
            local distW, distH = surface.GetTextSize(distText)
            draw.RoundedBox(4, centerX - distW/2 - 5, centerY + arrowHeight + 25, distW + 10, distH + 10, Color(0, 0, 0, 180))
            draw.DrawText(distText, "Trebuchet18", centerX, centerY + arrowHeight + 30, Color(255, 255, 255), TEXT_ALIGN_CENTER)

            -- Station name preview
            local stationName = self:GetClientInfo("station_name")
            if stationName and stationName ~= "" then
                surface.SetFont("Trebuchet18")
                local nameText = "Name: " .. stationName
                local nameW, nameH = surface.GetTextSize(nameText)
                draw.RoundedBox(4, centerX - nameW/2 - 5, centerY - arrowHeight - 45, nameW + 10, nameH + 10, Color(0, 0, 0, 180))
                draw.DrawText(nameText, "Trebuchet18", centerX, centerY - arrowHeight - 40, Color(100, 255, 100), TEXT_ALIGN_CENTER)
            end
        end
    end

    function TOOL:Think()
        -- Update tool info
    end
end
