if SERVER then return end

NPCPassengers = NPCPassengers or {}
NPCPassengers.Modules = NPCPassengers.Modules or {}
NPCPassengers.Modules.ui = true

local ADDON_DISPLAY_NAME = "Better NPC Passengers"
local ADDON_CHAT_PREFIX = "[" .. ADDON_DISPLAY_NAME .. "] "
local DEFAULT_FONT_NAME = "Tahoma"

-- Better NPC Passengers UI
-- Dark theme settings panel with custom Metropolis font

-- Keybind system: Track key states to detect key presses
local keyStates = {}

local function GetConVarIntSafe(name, default)
    if NPCPassengers.GetConVarInt then
        return NPCPassengers.GetConVarInt(name, default or 0)
    end
    local cv = GetConVar(name)
    if not cv then return default or 0 end
    return cv:GetInt()
end

local function GetConVarBoolSafe(name, default)
    if NPCPassengers.GetConVarBool then
        return NPCPassengers.GetConVarBool(name, default == true)
    end
    local cv = GetConVar(name)
    if not cv then return default == true end
    return cv:GetBool()
end

local function GetConVarFloatSafe(name, default)
    if NPCPassengers.GetConVarFloat then
        return NPCPassengers.GetConVarFloat(name, default or 0)
    end
    local cv = GetConVar(name)
    if not cv then return default or 0 end
    return cv:GetFloat()
end

hook.Add("Think", "NPCPassengers_Keybinds", function()
    -- Helper function to check if a key was just pressed
    local function WasKeyJustPressed(keyCode)
        if keyCode <= 0 then return false end
        
        local isDown = input.IsKeyDown(keyCode)
        local wasDown = keyStates[keyCode] or false
        keyStates[keyCode] = isDown
        
        return isDown and not wasDown
    end
    
    -- Check each keybind
    local keyAttach = GetConVarIntSafe("nai_npc_key_attach", 0)
    if WasKeyJustPressed(keyAttach) then
        RunConsoleCommand("nai_npc_attach_nearest")
    end
    
    local keyDetachAll = GetConVarIntSafe("nai_npc_key_detach_all", 0)
    if WasKeyJustPressed(keyDetachAll) then
        RunConsoleCommand("nai_npc_detach_all")
    end
    
    local keyToggleAutoJoin = GetConVarIntSafe("nai_npc_key_toggle_autojoin", 0)
    if WasKeyJustPressed(keyToggleAutoJoin) then
        local currentVal = GetConVarBoolSafe("nai_npc_auto_join", true)
        RunConsoleCommand("nai_npc_auto_join", currentVal and "0" or "1")
        chat.AddText(Color(100, 200, 255), ADDON_CHAT_PREFIX, Color(255, 255, 255), "Auto-Join: ", currentVal and Color(255, 100, 100) or Color(100, 255, 100), currentVal and "OFF" or "ON")
    end
    
    local keyMenu = GetConVarIntSafe("nai_npc_key_menu", 0)
    if WasKeyJustPressed(keyMenu) then
        RunConsoleCommand("nai_passengers_menu")
    end
    
    local keyExitAll = GetConVarIntSafe("nai_npc_key_exit_all", 0)
    if WasKeyJustPressed(keyExitAll) then
        RunConsoleCommand("nai_npc_exit_all")
    end
    
    -- Debug keybinds (only if debug mode is enabled)
    if GetConVarBoolSafe("nai_npc_debug_mode", false) then
        local keyTestGesture = GetConVarIntSafe("nai_npc_key_test_gesture", 0)
        if WasKeyJustPressed(keyTestGesture) then
            net.Start("NPCPassengers_DebugTest")
            net.WriteString("gesture")
            net.SendToServer()
        end
        
        local keyResetAll = GetConVarIntSafe("nai_npc_key_reset_all", 0)
        if WasKeyJustPressed(keyResetAll) then
            net.Start("NPCPassengers_DebugTest")
            net.WriteString("reset")
            net.SendToServer()
        end
    end
end)

local selectedNPCForVehicle = nil
local selectionExpireTime = 0

-- Client-side bone manipulation for body sway
local spineBoneCache = {}
local clientSwayState = {}
local trackedPassengerNPCs = {}
local nextPassengerRefresh = 0

local cvBodySway = GetConVar("nai_npc_body_sway")
local cvBodySwayAmount = GetConVar("nai_npc_body_sway_amount")
local cvCrashFlinch = GetConVar("nai_npc_crash_flinch")
local cvCrashThreshold = GetConVar("nai_npc_crash_threshold")

local function GetClientRootVehicle(entity)
    if not IsValid(entity) then return nil end

    if entity:GetClass() == "prop_vehicle_prisoner_pod" then
        local parent = entity:GetParent()
        if IsValid(parent) then
            return parent
        end
    end

    return entity
end

local function GetPassengerControlVehicle(npc)
    if not IsValid(npc) then return nil end

    local parent = npc:GetParent()
    if not IsValid(parent) then return nil end

    return GetClientRootVehicle(parent)
end

local function IsPassengerInLocalPlayersVehicle(npc)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:InVehicle() then return false end

    local playerVehicle = GetClientRootVehicle(ply:GetVehicle())
    local passengerVehicle = GetPassengerControlVehicle(npc)
    return IsValid(playerVehicle) and IsValid(passengerVehicle) and playerVehicle == passengerVehicle
end

local function GetClientVehicleSeatIndex(vehicle, seatEntity)
    if not IsValid(vehicle) or not IsValid(seatEntity) then return nil end

    local seats = {}

    if vehicle.GetDriverSeat then
        local driverSeat = vehicle:GetDriverSeat()
        if IsValid(driverSeat) then
            seats[#seats + 1] = driverSeat
        end
    end

    for _, child in ipairs(vehicle:GetChildren()) do
        if IsValid(child) and child:GetClass() == "prop_vehicle_prisoner_pod" then
            seats[#seats + 1] = child
        end
    end

    table.sort(seats, function(a, b)
        local posA = vehicle:WorldToLocal(a:GetPos())
        local posB = vehicle:WorldToLocal(b:GetPos())
        return posA.x > posB.x
    end)

    for index, seat in ipairs(seats) do
        if seat == seatEntity then
            return index
        end
    end

    return nil
end

local function RefreshTrackedPassengers()
    for ent in pairs(trackedPassengerNPCs) do
        if not IsValid(ent) or not ent:IsNPC() or not ent:GetNWBool("IsNPCPassenger", false) then
            trackedPassengerNPCs[ent] = nil
        end
    end

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNPCPassenger", false) then
            trackedPassengerNPCs[ent] = true
        end
    end
end

-- Get spine bones for an NPC (cached)
local function GetSpineBones(npc)
    local entIdx = npc:EntIndex()
    if spineBoneCache[entIdx] then return spineBoneCache[entIdx] end
    
    local bones = {}
    local boneNames = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4"}
    for i, name in ipairs(boneNames) do
        local boneId = npc:LookupBone(name)
        if boneId and boneId >= 0 then
            table.insert(bones, {id = boneId, mult = ({0.8, 0.6, 0.4, 0.25})[i] or 0.4})
        end
    end
    
    spineBoneCache[entIdx] = bones
    return bones
end

-- Simple lerp for smooth movement
local function LerpAngle(t, current, target)
    return current + (target - current) * math.min(1, t)
end

-- Client-side body sway - calculates from vehicle velocity directly
hook.Add("Think", "NPCPassengers_ClientBodySway", function()
    local dt = FrameTime()
    if dt <= 0 then return end

    if not cvBodySway or not cvBodySway:GetBool() then return end

    local curTime = CurTime()
    if curTime >= nextPassengerRefresh then
        RefreshTrackedPassengers()
        nextPassengerRefresh = curTime + 1
    end

    local swayAmount = cvBodySwayAmount and cvBodySwayAmount:GetFloat() or 1
    local crashFlinchEnabled = cvCrashFlinch and cvCrashFlinch:GetBool() or true
    local crashThreshold = cvCrashThreshold and cvCrashThreshold:GetFloat() or 400

    for ent in pairs(trackedPassengerNPCs) do
        if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNPCPassenger", false) then
            local entIdx = ent:EntIndex()
            
            -- Get vehicle the NPC is parented to
            local vehicle = ent:GetParent()
            if not IsValid(vehicle) then continue end
            
            -- Get or find the actual vehicle entity
            if vehicle:GetClass() == "prop_vehicle_prisoner_pod" then
                vehicle = vehicle:GetParent()
            end
            if not IsValid(vehicle) then continue end
            
            -- Initialize state
            if not clientSwayState[entIdx] then
                clientSwayState[entIdx] = {
                    roll = 0, pitch = 0,
                    lastVel = Vector(0,0,0),
                    lastSpeed = 0,
                    crashLean = 0,  -- Extra forward lean from crash
                    crashRecovery = 0,
                }
            end
            local state = clientSwayState[entIdx]
            
            -- Get vehicle velocity and calculate sway
            local vel = vehicle:GetVelocity()
            local speed = vel:Length()
            local velDelta = vel - state.lastVel
            
            local vehRight = vehicle:GetRight()
            local vehForward = vehicle:GetForward()
            
            -- Detect crash: sudden forward deceleration
            local forwardDecel = -velDelta:Dot(vehForward)
            
            if crashFlinchEnabled and forwardDecel > crashThreshold and state.lastSpeed > 300 then
                -- Crash detected! Lean forward hard based on impact intensity
                local crashIntensity = math.Clamp((forwardDecel - crashThreshold) / 800, 0.3, 1)
                state.crashLean = math.max(state.crashLean, crashIntensity * 35)  -- Up to 35 degree forward lean
                state.crashRecovery = CurTime() + 0.8 + crashIntensity * 0.5  -- Recovery time based on intensity
            end
            
            -- Fade out crash lean (slow recovery, like whiplash)
            if state.crashLean > 0 then
                if CurTime() > state.crashRecovery then
                    -- Slow recovery after initial impact
                    state.crashLean = LerpAngle(dt * 2, state.crashLean, 0)
                end
            end
            
            state.lastVel = vel
            state.lastSpeed = speed
            
            -- Calculate lateral and forward sway from acceleration
            local lateralAccel = velDelta:Dot(vehRight) * 0.3 * swayAmount
            local forwardAccel = velDelta:Dot(vehForward) * 0.15 * swayAmount
            
            -- Add turn sway from angular velocity
            local turnSway = 0
            local phys = vehicle:GetPhysicsObject()
            if IsValid(phys) then
                turnSway = phys:GetAngleVelocity().y * 0.06 * swayAmount
            end
            
            local targetRoll = math.Clamp(lateralAccel + turnSway, -20, 20)
            local targetPitch = math.Clamp(-forwardAccel, -12, 12)
            
            -- Add crash lean to pitch
            targetPitch = targetPitch + state.crashLean
            
            -- Smooth interpolation (faster for crash, slower for normal)
            local lerpSpeed = state.crashLean > 5 and 12 or 6
            state.roll = LerpAngle(dt * lerpSpeed, state.roll, targetRoll)
            state.pitch = LerpAngle(dt * lerpSpeed, state.pitch, targetPitch)
            
            -- Apply bone manipulation if there's movement
            -- Note: For spine bones, roll = forward/back lean, pitch = side lean
            local bones = GetSpineBones(ent)
            if #bones > 0 and (math.abs(state.roll) > 0.5 or math.abs(state.pitch) > 0.5) then
                for _, bone in ipairs(bones) do
                    ent:ManipulateBoneAngles(bone.id, Angle(state.roll * bone.mult, 0, state.pitch * bone.mult))
                end
            end
        end
    end
end)

-- Clean up when NPCs are removed
hook.Add("EntityRemoved", "NPCPassengers_CleanBoneCache", function(ent)
    if ent:IsNPC() then
        local entIdx = ent:EntIndex()
        spineBoneCache[entIdx] = nil
        clientSwayState[entIdx] = nil
        trackedPassengerNPCs[ent] = nil
    end
end)

-- Theme colors - Modern gradient design
local Theme = {
    bg = Color(22, 22, 28),
    bgLight = Color(32, 32, 40),
    bgLighter = Color(42, 42, 52),
    bgDark = Color(15, 15, 20),
    glass = Color(18, 22, 28, 226),
    glassLight = Color(30, 34, 42, 196),
    glassDark = Color(14, 16, 22, 214),
    glassBorder = Color(116, 146, 190, 85),
    accent = Color(88, 166, 255),
    accentHover = Color(110, 180, 255),
    accentActive = Color(70, 140, 220),
    accentDark = Color(50, 110, 180),
    text = Color(230, 230, 240),
    textDim = Color(160, 160, 180),
    textBright = Color(255, 255, 255),
    success = Color(90, 200, 120),
    warning = Color(240, 180, 70),
    error = Color(220, 90, 90),
    border = Color(55, 55, 70),
    borderLight = Color(70, 70, 90),
    scrollbar = Color(70, 70, 85),
    scrollbarGrip = Color(100, 100, 125),
    shadow = Color(0, 0, 0, 120),
    glow = Color(88, 166, 255, 30),
}

-- Custom fonts (requires metropolis.ttf in resource/fonts/)
local fontName = "Metropolis"

local function GetUIFontName()
    local useDefaultFont = GetConVar("nai_npc_ui_use_default_font")
    if useDefaultFont and useDefaultFont:GetBool() then
        return DEFAULT_FONT_NAME
    end

    return fontName
end

local function CreateNaiFonts()
    local activeFontName = GetUIFontName()

    surface.CreateFont("NaiFont_Small", {
        font = activeFontName,
        size = 14,
        weight = 400,
        antialias = true,
    })

    surface.CreateFont("NaiFont_Normal", {
        font = activeFontName,
        size = 16,
        weight = 400,
        antialias = true,
    })

    surface.CreateFont("NaiFont_Medium", {
        font = activeFontName,
        size = 18,
        weight = 500,
        antialias = true,
    })

    surface.CreateFont("NaiFont_Large", {
        font = activeFontName,
        size = 22,
        weight = 600,
        antialias = true,
    })

    surface.CreateFont("NaiFont_Title", {
        font = activeFontName,
        size = 26,
        weight = 700,
        antialias = true,
    })

    surface.CreateFont("NaiFont_Bold", {
        font = activeFontName,
        size = 16,
        weight = 700,
        antialias = true,
    })
end

-- Create fonts inside Initialize so the renderer is fully ready
hook.Add("Initialize", "NPCPassengers_CreateFonts", function()
    CreateNaiFonts()
end)
-- Also create them immediately in case Initialize already fired (e.g. Lua file refresh)
CreateNaiFonts()

local function Lerp(t, a, b)
    return a + (b - a) * t
end

local function LerpColor(t, col1, col2)
    return Color(
        Lerp(t, col1.r, col2.r),
        Lerp(t, col1.g, col2.g),
        Lerp(t, col1.b, col2.b),
        Lerp(t, col1.a or 255, col2.a or 255)
    )
end

local TransparentColor = Color(0, 0, 0, 0)
local BlurMaterial = Material("pp/blurscreen")
local DrawRoundedSurface

local function WithAlpha(color, alpha)
    return Color(color.r, color.g, color.b, alpha)
end

local function AnimateButtonVisualState(button, hoverInSpeed, hoverOutSpeed, pressInSpeed, pressOutSpeed)
    local hovered = button:IsHovered()
    local pressed = button:IsDown()

    button.hoverAnim = math.Approach(button.hoverAnim or 0, hovered and 1 or 0, FrameTime() * (hovered and (hoverInSpeed or 8) or (hoverOutSpeed or 10)))
    button.pressAnim = math.Approach(button.pressAnim or 0, pressed and 1 or 0, FrameTime() * (pressed and (pressInSpeed or 18) or (pressOutSpeed or 12)))

    return button.hoverAnim, button.pressAnim
end

local function HandleButtonHoverSound(button)
    if button:IsHovered() then
        if not button.hasPlayedHoverSound then
            if GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_hover_enabled"):GetBool() then
                surface.PlaySound("nai_passengers/ui_hover.wav")
            end
            button.hasPlayedHoverSound = true
        end
    else
        button.hasPlayedHoverSound = false
    end
end

local function GetButtonPushOffset(button, distance)
    return math.floor((button.pressAnim or 0) * (distance or 2) + 0.5)
end

local function DrawClippedBlur(panel, x, y, w, h, blurAmount, blurPasses, blurAlpha)
    if not IsValid(panel) or w <= 0 or h <= 0 or (blurAmount or 0) <= 0 then
        return
    end

    local panelX, panelY = panel:LocalToScreen(0, 0)
    local clipX, clipY = panel:LocalToScreen(x, y)
    local passCount = math.max(math.floor(blurPasses or 1), 1)

    render.SetScissorRect(clipX, clipY, clipX + w, clipY + h, true)
    surface.SetDrawColor(255, 255, 255, blurAlpha or 255)
    surface.SetMaterial(BlurMaterial)

    for passIndex = 1, passCount do
        BlurMaterial:SetFloat("$blur", (blurAmount / passCount) * passIndex)
        BlurMaterial:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(-panelX, -panelY, ScrW(), ScrH())
    end

    render.SetScissorRect(0, 0, 0, 0, false)
end

local function DrawGlassSurface(panel, x, y, w, h, radius, fillColor, borderColor, blurAmount, blurPasses, blurAlpha)
    DrawClippedBlur(panel, x, y, w, h, blurAmount or 3, blurPasses or 1, blurAlpha or 160)
    DrawRoundedSurface(x, y, w, h, radius, fillColor, borderColor)
end

DrawRoundedSurface = function(x, y, w, h, radius, fillColor, borderColor)
    if borderColor then
        draw.RoundedBox(radius, x, y, w, h, borderColor)
        draw.RoundedBox(math.max(radius - 1, 0), x + 1, y + 1, math.max(w - 2, 0), math.max(h - 2, 0), fillColor)
        return
    end

    draw.RoundedBox(radius, x, y, w, h, fillColor)
end

local function IsAprilFoolsActive()
    if NPCPassengers.IsFirstApril then
        return NPCPassengers.IsFirstApril()
    end

    return false
end

local function GetAprilTripColor(offset, saturation, brightness, alpha)
    local color = HSVToColor((CurTime() * 80 + (offset or 0)) % 360, saturation or 0.85, brightness or 1)
    color.a = alpha or 255
    return color
end

local function DrawAprilTripOverlay(w, h, alpha)
    local stripeCount = 14
    local stripeWidth = math.max(math.floor(w / stripeCount), 1)

    for index = 0, stripeCount do
        local stripeColor = GetAprilTripColor(index * 30, 0.85, 1, alpha or 34)
        local drift = math.sin(CurTime() * 3.8 + index * 0.9) * 28
        surface.SetDrawColor(stripeColor)
        surface.DrawRect(index * stripeWidth + drift, 0, stripeWidth + 24, h)
    end

    for lineY = 0, h, 16 do
        local scanColor = GetAprilTripColor(lineY * 2, 0.65, 1, math.max((alpha or 34) - 6, 10))
        local driftX = math.cos(CurTime() * 4.5 + lineY * 0.05) * 22
        surface.SetDrawColor(scanColor)
        surface.DrawRect(driftX, lineY, w + 32, 3)
    end
end

local function DrawAprilGlitchText(text, font, x, y, baseColor, alignX, alignY)
    local jitterX = math.sin(CurTime() * 9 + x * 0.01) * 4
    local jitterY = math.cos(CurTime() * 7 + y * 0.02) * 3
    draw.SimpleText(text, font, x - 2 + jitterX, y + jitterY, GetAprilTripColor(0, 0.95, 1, 180), alignX, alignY)
    draw.SimpleText(text, font, x + 2 - jitterX, y - jitterY, GetAprilTripColor(160, 0.95, 1, 180), alignX, alignY)
    draw.SimpleText(text, font, x, y, baseColor, alignX, alignY)
end

local function RotatePoint(x, y, angleRadians)
    local angleCos = math.cos(angleRadians)
    local angleSin = math.sin(angleRadians)
    return x * angleCos - y * angleSin, x * angleSin + y * angleCos
end

local function DrawRotatedQuad(cx, cy, halfWidth, halfHeight, angleDegrees, color)
    local angleRadians = math.rad(angleDegrees)
    local x1, y1 = RotatePoint(-halfWidth, -halfHeight, angleRadians)
    local x2, y2 = RotatePoint(halfWidth, -halfHeight, angleRadians)
    local x3, y3 = RotatePoint(halfWidth, halfHeight, angleRadians)
    local x4, y4 = RotatePoint(-halfWidth, halfHeight, angleRadians)

    surface.SetDrawColor(color)
    draw.NoTexture()
    surface.DrawPoly({
        { x = cx + x1, y = cy + y1 },
        { x = cx + x2, y = cy + y2 },
        { x = cx + x3, y = cy + y3 },
        { x = cx + x4, y = cy + y4 },
    })
end

local function DrawAprilSpinner(cx, cy, radius, speed, colorOffset, alpha)
    local outerColor = GetAprilTripColor(colorOffset or 0, 0.95, 1, alpha or 180)
    local innerColor = GetAprilTripColor((colorOffset or 0) + 120, 0.9, 1, math.max((alpha or 180) - 55, 40))
    local spin = CurTime() * (speed or 360)

    DrawRotatedQuad(cx, cy, radius, radius * 0.38, spin, outerColor)
    DrawRotatedQuad(cx, cy, radius * 0.82, radius * 0.22, -spin * 1.45, innerColor)
end

local function DrawRotatingCross(cx, cy, size, angleDegrees, color)
    local angleRadians = math.rad(angleDegrees)
    local x1, y1 = RotatePoint(-size, -size, angleRadians)
    local x2, y2 = RotatePoint(size, size, angleRadians)
    local x3, y3 = RotatePoint(size, -size, angleRadians)
    local x4, y4 = RotatePoint(-size, size, angleRadians)

    surface.SetDrawColor(color)
    surface.DrawLine(cx + x1, cy + y1, cx + x2, cy + y2)
    surface.DrawLine(cx + x3, cy + y3, cx + x4, cy + y4)
end

local function DrawMarqueeText(panel, text, font, x, y, color, maxWidth, alignY, padding, speed)
    if not IsValid(panel) or not text or maxWidth <= 0 then
        return
    end

    surface.SetFont(font)
    local textWidth = surface.GetTextSize(text)
    if textWidth <= maxWidth then
        draw.SimpleText(text, font, x, y, color, TEXT_ALIGN_LEFT, alignY or TEXT_ALIGN_CENTER)
        return
    end

    local clipX, clipY = panel:LocalToScreen(x, y - panel:GetTall())
    local clipTop = select(2, panel:LocalToScreen(0, 0))
    local clipBottom = select(2, panel:LocalToScreen(0, panel:GetTall()))
    local screenX = select(1, panel:LocalToScreen(x, 0))
    local offsetRange = textWidth - maxWidth
    local cycle = math.max((padding or 24) + offsetRange, 1)
    local time = CurTime() * (speed or 22)
    local normalized = (math.sin(time / cycle) + 1) * 0.5
    local textOffset = math.floor(normalized * offsetRange + 0.5)

    render.SetScissorRect(screenX, clipTop, screenX + maxWidth, clipBottom, true)
    draw.SimpleText(text, font, x - textOffset, y, color, TEXT_ALIGN_LEFT, alignY or TEXT_ALIGN_CENTER)
    render.SetScissorRect(0, 0, 0, 0, false)
end

-- UI Components
local function CreateLabel(parent, text, font, color)
    local label = vgui.Create("DLabel", parent)
    label:SetText(text)
    label:SetFont(font or "DermaDefault")
    label:SetTextColor(color or Theme.text)
    label:SizeToContents()
    return label
end

local function CreateSectionHeader(parent, text)
    local header = vgui.Create("DPanel", parent)
    header.SearchSectionTitle = text
    header:SetTall(38)
    header:Dock(TOP)
    header:DockMargin(0, 15, 0, 8)
    header.Paint = function(self, w, h)
        local accentColor = IsAprilFoolsActive() and GetAprilTripColor(20, 0.9, 1, 220) or Theme.accent

        -- Gradient background
        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 80)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, 0, w, h)
        
        -- Accent line at bottom
        surface.SetDrawColor(accentColor)
        surface.DrawRect(0, h - 3, w, 3)
        
        -- Glow effect
        draw.RoundedBox(0, 0, h - 3, w, 3, Color(accentColor.r, accentColor.g, accentColor.b, Theme.glow.a or 30))
        
        -- Icon
        surface.SetDrawColor(accentColor)
        surface.SetMaterial(Material("icon16/star.png"))
        surface.DrawTexturedRect(12, (h - 16) / 2, 16, 16)

        DrawMarqueeText(self, text, "NaiFont_Medium", 36, h/2, Theme.textBright, math.max(w - 48, 0), TEXT_ALIGN_CENTER, 32, 18)
    end
    return header
end

local function CreateSubHeader(parent, text)
    local header = vgui.Create("DPanel", parent)
    header.SearchSectionTitle = text
    header:SetTall(28)
    header:Dock(TOP)
    header:DockMargin(5, 12, 5, 6)
    header.Paint = function(self, w, h)
        local accentColor = IsAprilFoolsActive() and GetAprilTripColor(100, 0.9, 1, 220) or Theme.accent

        -- Left accent bar
        draw.RoundedBox(2, 0, 0, 4, h, accentColor)
        
        -- Bottom gradient line
        local gradientMat = Material("vgui/gradient-r")
        surface.SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 60)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, h - 2, w, 2)

        DrawMarqueeText(self, text, "NaiFont_Bold", 12, h/2 - 2, accentColor, math.max(w - 18, 0), TEXT_ALIGN_CENTER, 28, 18)
    end
    return header
end

local function CreateHelpText(parent, text)
    local help = vgui.Create("DLabel", parent)
    help.SearchHelpText = text
    help:SetText(text)
    help:SetFont("NaiFont_Small")
    help:SetTextColor(Theme.textDim)
    help:SetWrap(true)
    help:SetAutoStretchVertical(true)
    help:Dock(TOP)
    help:DockMargin(5, 0, 5, 6)
    return help
end

local function CreateCheckbox(parent, label, convar)
    local container = vgui.Create("DPanel", parent)
    container.SearchLabel = label
    container.SearchConVar = convar
    container:SetTall(32)
    container:Dock(TOP)
    container:DockMargin(5, 3, 5, 3)
    container.hasPlayedHoverSound = false
    container.Paint = function(self, w, h)
        if self:IsHovered() then
            draw.RoundedBox(6, 0, 0, w, h, Theme.bgLight)
            if not self.hasPlayedHoverSound then
                if GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_hover_enabled"):GetBool() then
                    surface.PlaySound("nai_passengers/ui_hover.wav")
                end
                self.hasPlayedHoverSound = true
            end
        else
            self.hasPlayedHoverSound = false
        end
    end
    
    local checkbox = vgui.Create("DCheckBox", container)
    checkbox:SetPos(8, 6)
    checkbox:SetSize(20, 20)
    checkbox:SetConVar(convar)
    checkbox.Paint = function(self, w, h)
        local isChecked = self:GetChecked()
        local col = isChecked and Theme.accent or Theme.bgLighter
        
        -- Outer glow for checked state
        if isChecked then
            draw.RoundedBox(6, -2, -2, w + 4, h + 4, Theme.glow)
        end
        
        draw.RoundedBox(5, 0, 0, w, h, col)
        
        if isChecked then
            draw.SimpleText("v", "NaiFont_Bold", w/2, h/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Border
        surface.SetDrawColor(isChecked and Theme.accentHover or Theme.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    
    checkbox.OnChange = function(self, val)
        if IsValid(LocalPlayer()) and GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_click_enabled"):GetBool() then
            LocalPlayer():EmitSound("nai_passengers/ui_click.wav", 75, val and 100 or 80)
        end
    end
    
    local lbl = CreateLabel(container, label, "NaiFont_Normal", Theme.text)
    lbl:SetPos(36, 6)
    lbl:SetMouseInputEnabled(true)
    lbl:SetCursor("hand")
    lbl.DoClick = function()
        checkbox:Toggle()
    end
    
    container.OnMousePressed = function()
        checkbox:Toggle()
    end
    
    return container, checkbox
end

local function CreateSlider(parent, label, convar, min, max, decimals)
    local container = vgui.Create("DPanel", parent)
    container.SearchLabel = label
    container.SearchConVar = convar
    container:SetTall(52)
    container:Dock(TOP)
    container:DockMargin(5, 3, 5, 3)
    container.Paint = function() end
    
    local lbl = CreateLabel(container, label, "NaiFont_Normal", Theme.text)
    lbl:Dock(TOP)
    lbl:SetTall(20)
    
    local sliderContainer = vgui.Create("DPanel", container)
    sliderContainer:Dock(TOP)
    sliderContainer:SetTall(28)
    sliderContainer:DockMargin(0, 2, 0, 0)
    sliderContainer.Paint = function() end
    
    local slider = vgui.Create("DNumSlider", sliderContainer)
    slider:Dock(FILL)
    slider:SetMin(min)
    slider:SetMax(max)
    slider:SetDecimals(decimals or 0)
    slider:SetConVar(convar)
    slider.Label:SetVisible(false)
    
    -- Force sync with ConVar value on creation (delayed to ensure ConVar is ready)
    timer.Simple(0, function()
        if IsValid(slider) then
            local cv = GetConVar(convar)
            if cv then
                slider:SetValue(cv:GetFloat())
            end
        end
    end)
    
    slider.Slider.Paint = function(self, w, h)
        local trackY = h / 2
        draw.RoundedBox(3, 0, trackY - 3, w, 6, Theme.bgLighter)
        
        local frac = math.Clamp((slider:GetValue() - min) / (max - min), 0, 1)
        local filledW = w * frac
        draw.RoundedBox(3, 0, trackY - 3, filledW, 6, Theme.accent)
    end
    
    slider.Slider.Knob:SetSize(14, 14)
    slider.Slider.Knob.Paint = function(self, w, h)
        draw.RoundedBox(7, 0, 0, w, h, Theme.accent)
        if self:IsHovered() then
            draw.RoundedBox(7, 0, 0, w, h, Theme.accentHover)
        end
    end
    
    slider.TextArea:SetWide(60)
    slider.TextArea:SetTextColor(Theme.text)
    slider.TextArea.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
        self:DrawTextEntryText(Theme.text, Theme.accent, Theme.text)
    end
    
    return container, slider
end

local function CreateComboBox(parent, label, convar, options)
    local container = vgui.Create("DPanel", parent)
    container.SearchLabel = label
    container.SearchConVar = convar
    container:SetTall(54)
    container:Dock(TOP)
    container:DockMargin(5, 3, 5, 3)
    container.Paint = function() end
    
    local lbl = CreateLabel(container, label, "NaiFont_Normal", Theme.text)
    lbl:SetPos(0, 0)
    
    local combo = vgui.Create("DComboBox", container)
    combo:SetPos(0, 22)
    combo:SetSize(300, 26)
    combo:SetTextColor(Theme.text)
    combo:SetFont("NaiFont_Normal")
    combo:SetSortItems(false)
    
    combo.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
        surface.SetDrawColor(Theme.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("v", "NaiFont_Small", w - 15, h/2, Theme.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    for _, opt in ipairs(options) do
        combo:AddChoice(opt.label, opt.value)
    end
    
    local currentVal = GetConVar(convar):GetInt()
    for _, opt in ipairs(options) do
        if opt.value == currentVal then
            combo:SetValue(opt.label)
            break
        end
    end
    
    combo.OnSelect = function(self, index, value, data)
        RunConsoleCommand(convar, tostring(data))
    end
    
    return container, combo
end

local function CreateButton(parent, text, callback)
    local btn = vgui.Create("DButton", parent)
    btn.SearchLabel = text
    btn:SetText(text)
    btn:SetFont("NaiFont_Medium")
    btn:SetTall(40)
    btn:Dock(TOP)
    btn:DockMargin(8, 6, 8, 6)
    btn:SetTextColor(TransparentColor)
    btn.hoverAnim = 0
    btn.pressAnim = 0
    btn.hasPlayedHoverSound = false
    
    btn.Paint = function(self, w, h)
        AnimateButtonVisualState(self, 6, 8, 18, 12)
        HandleButtonHoverSound(self)

        local pushOffset = GetButtonPushOffset(self, 2)
        local bgColor = LerpColor(self.hoverAnim, Theme.accent, Theme.accentHover)
        bgColor = LerpColor(self.pressAnim, bgColor, Theme.accentActive)
        local blurStrength = (self.hoverAnim * 1.8) + (self.pressAnim * 2.8)

        if blurStrength > 0.05 then
            DrawClippedBlur(self, 0, pushOffset, w, h, blurStrength, 1, 56 + (self.hoverAnim * 24) + (self.pressAnim * 40))
        end

        if self.hoverAnim > 0 then
            local glowAlpha = 50 * self.hoverAnim
            draw.RoundedBox(8, -2, -2 + pushOffset, w + 4, h + 4, ColorAlpha(Theme.accent, glowAlpha))
        end

        draw.RoundedBox(8, 2, 2 - self.pressAnim, w, h, Theme.shadow)
        draw.RoundedBox(7, 0, pushOffset, w, h, WithAlpha(bgColor, 222))

        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(255, 255, 255, 15)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, pushOffset, w, h / 2)

        surface.SetDrawColor(Theme.accentHover.r, Theme.accentHover.g, Theme.accentHover.b, 60)
        surface.DrawOutlinedRect(0, pushOffset, w, h, 1)
        draw.SimpleText(self:GetText(), "NaiFont_Medium", w / 2, (h / 2) + pushOffset, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    btn.DoClick = function()
        if GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_click_enabled"):GetBool() then
            surface.PlaySound("nai_passengers/ui_click.wav")
        end
        if callback then callback() end
    end
    
    return btn
end

local function CreateSpacer(parent, height)
    local spacer = vgui.Create("DPanel", parent)
    spacer:SetTall(height or 10)
    spacer:Dock(TOP)
    spacer.Paint = function() end
    return spacer
end

local function StyleScrollbar(sbar)
    sbar:SetWide(8)
    sbar:SetHideButtons(true)
    sbar.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.bgDark)
    end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        local col = self:IsHovered() and Theme.accentHover or Theme.scrollbarGrip
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
end

-- Main Settings Panel
local settingsFrame = nil

local function AreUIAnimationsEnabled()
    local cvar = GetConVar("nai_npc_ui_animations")
    return cvar and cvar:GetBool()
end

local function AnimateSettingsFrameIn(frame, targetX, targetY)
    if not IsValid(frame) then
        return
    end

    if not AreUIAnimationsEnabled() then
        frame:SetPos(targetX, targetY)
        frame:SetAlpha(255)
        return
    end

    frame:Stop()
    frame:SetAlpha(0)
    frame:SetPos(targetX, ScrH() + 24)
    frame:AlphaTo(255, 0.18, 0)
    frame:MoveTo(targetX, targetY, 0.22, 0, 0.22)
end

local function OpenSettingsPanel()
    if IsValid(settingsFrame) then
        settingsFrame:Remove()
    end
    
    local panelWidth = GetConVar("nai_npc_ui_panel_width"):GetInt()
    local panelHeight = GetConVar("nai_npc_ui_panel_height"):GetInt()
    
    settingsFrame = vgui.Create("DFrame")
    settingsFrame:SetSize(panelWidth, panelHeight)
    settingsFrame:Center()
    local targetX, targetY = settingsFrame:GetPos()
    settingsFrame:SetTitle("")
    settingsFrame:SetDraggable(true)
    settingsFrame:SetDeleteOnClose(true)
    settingsFrame.isClosingAnimated = false

    local defaultClose = settingsFrame.Close
    settingsFrame.Close = function(self)
        if not IsValid(self) then
            return
        end

        if self.isClosingAnimated then
            return
        end

        if not AreUIAnimationsEnabled() then
            defaultClose(self)
            return
        end

        self.isClosingAnimated = true
        self:SetMouseInputEnabled(false)
        self:SetKeyboardInputEnabled(false)
        self:Stop()
        local closeX = self:GetX()
        self:AlphaTo(0, 0.14, 0)
        self:MoveTo(closeX, ScrH() + 24, 0.18, 0, 0.18, function()
            if IsValid(self) then
                defaultClose(self)
            end
        end)
    end
    settingsFrame:MakePopup()
    AnimateSettingsFrameIn(settingsFrame, targetX, targetY)
    
    settingsFrame.Paint = function(self, w, h)
        local aprilMode = IsAprilFoolsActive()

        -- Outer shadow
        draw.RoundedBox(14, 4, 4, w, h, Color(0, 0, 0, 140))

        DrawGlassSurface(self, 0, 0, w, h, 12, Theme.glass, Theme.glassBorder, 5.2, 2, 180)
        draw.RoundedBox(12, 1, 1, w - 2, h - 2, WithAlpha(Theme.bg, 120))

        if aprilMode then
            DrawAprilTripOverlay(w, h, 18)
            DrawAprilSpinner(78, 25, 20, 340, 35, 150)
            DrawAprilSpinner(w - 88, 25, 18, 460, 230, 165)
        end

        DrawClippedBlur(self, 0, 0, w, 50, 3.4, 1, 120)
        local gradientMat = Material("vgui/gradient-d")
        local headerAccent = aprilMode and GetAprilTripColor(40, 0.85, 1, 200) or Theme.accentDark
        surface.SetDrawColor(headerAccent.r, headerAccent.g, headerAccent.b, 120)
        surface.SetMaterial(gradientMat)
        draw.RoundedBoxEx(12, 0, 0, w, 50, WithAlpha(Theme.bgDark, 176), true, true, false, false)
        surface.DrawTexturedRect(0, 0, w, 50)
        
        -- Accent line under header
        local accentLine = aprilMode and GetAprilTripColor(120, 0.9, 1, 255) or Theme.accent
        surface.SetDrawColor(accentLine)
        surface.DrawRect(0, 50, w, 2)
        
        -- Title text with shadow
        local jitterX = aprilMode and math.sin(CurTime() * 8) * 3 or 0
        local jitterY = aprilMode and math.cos(CurTime() * 10) * 2 or 0
        local titleColor = aprilMode and GetAprilTripColor(200, 0.85, 1, 255) or Theme.textBright
        if aprilMode then
            DrawAprilGlitchText(ADDON_DISPLAY_NAME .. " Settings", "NaiFont_Title", 20 + jitterX, 25 + jitterY, titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(ADDON_DISPLAY_NAME .. " Settings", "NaiFont_Title", 21 + jitterX, 26 + jitterY, Color(0, 0, 0, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(ADDON_DISPLAY_NAME .. " Settings", "NaiFont_Title", 20 + jitterX, 25 + jitterY, titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        
        -- Version badge
        local versionW = 45
        local versionH = 20
        local versionX = w - versionW - 50
        local versionY = 15
        if aprilMode then
            DrawAprilSpinner(versionX + versionW / 2, versionY + versionH / 2, 18, 620, 290, 190)
            DrawRotatedQuad(versionX + versionW / 2, versionY + versionH / 2, versionW * 0.6, versionH * 0.55, CurTime() * 250, GetAprilTripColor(280, 0.8, 1, 220))
        else
            draw.RoundedBox(10, versionX, versionY, versionW, versionH, Theme.accentDark)
        end
        draw.SimpleText("v" .. NPCPassengers.Version, "NaiFont_Small", versionX + versionW/2, versionY + versionH/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if aprilMode then
            DrawAprilGlitchText("APRIL MODE", "NaiFont_Small", w - 125, 25, GetAprilTripColor(20, 0.95, 1, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    
    settingsFrame.btnClose:SetVisible(false)
    settingsFrame.btnMaxim:SetVisible(false)
    settingsFrame.btnMinim:SetVisible(false)
    
    local closeBtn = vgui.Create("DButton", settingsFrame)
    closeBtn:SetPos(settingsFrame:GetWide() - 38, 12)
    closeBtn:SetSize(28, 28)
    closeBtn:SetText("")
    closeBtn.hoverAnim = 0
    closeBtn.pressAnim = 0
    closeBtn.Paint = function(self, w, h)
        local aprilMode = IsAprilFoolsActive()
        AnimateButtonVisualState(self, 8, 10, 18, 12)

        local pushOffset = GetButtonPushOffset(self, 2)
        local baseColor = aprilMode and GetAprilTripColor(330, 0.9, 1, 255) or Theme.bgLight
        local hoverColor = aprilMode and GetAprilTripColor(40, 0.9, 1, 255) or Theme.error
        local col = LerpColor(self.hoverAnim, baseColor, hoverColor)
        local pressedColor = aprilMode and GetAprilTripColor(10, 0.95, 0.9, 255) or Color(170, 72, 72)
        col = LerpColor(self.pressAnim, col, pressedColor)
        DrawClippedBlur(self, 0, pushOffset, w, h, 2.4 + (self.hoverAnim * 1.2) + (self.pressAnim * 1.6), 1, 70 + (self.pressAnim * 50))
        draw.RoundedBox(6, 0, pushOffset, w, h, WithAlpha(col, 220))

        if aprilMode then
            DrawAprilSpinner(w / 2, (h / 2) + pushOffset, 11, 920, 70, 125)
        end
        
        local iconColor = aprilMode and GetAprilTripColor(120, 0.2, 1, 255) or Theme.textBright
        if aprilMode then
            DrawRotatingCross(w / 2, (h / 2) + pushOffset, 7, CurTime() * 720 + self.hoverAnim * 50, iconColor)
        else
            surface.SetDrawColor(iconColor)
            surface.DrawLine(8, 8 + pushOffset, w - 8, h - 8 + pushOffset)
            surface.DrawLine(w - 8, 8 + pushOffset, 8, h - 8 + pushOffset)
        end
    end
    closeBtn.DoClick = function()
        if IsValid(settingsFrame) then
            settingsFrame:Close()
        end
    end

    local navContainer, sidebar, contentArea, searchBox, searchEntry, searchSuggestions, searchMatches, searchStatus, searchClearBtn
    local ClearSearchSuggestions

    local function FocusSearchEntry()
        if not IsValid(searchEntry) then
            return
        end

        searchEntry:RequestFocus()
        searchEntry:SetCaretPos(string.len(searchEntry:GetValue() or ""))
    end

    local function ClearSearchQuery(keepFocus)
        if not IsValid(searchEntry) then
            return
        end

        searchEntry:SetText("")
        ClearSearchSuggestions()

        if IsValid(searchStatus) then
            searchStatus:SetText("Ctrl+F to focus search")
            searchStatus:SetTextColor(Theme.textDim)
            searchStatus:SizeToContents()
        end

        if IsValid(searchClearBtn) then
            searchClearBtn:SetVisible(false)
        end

        if keepFocus then
            FocusSearchEntry()
        end
    end

    local function UpdateSearchSuggestionsLayout()
        if not IsValid(searchSuggestions) or not IsValid(sidebar) then
            return
        end

        local suggestionX = 8
        local suggestionY = 56
        local suggestionW = math.max(sidebar:GetWide() - 24, 120)

        if IsValid(searchBox) then
            suggestionY = searchBox:GetY() + searchBox:GetTall() + 4
        end

        searchSuggestions:SetPos(suggestionX, suggestionY)
        searchSuggestions:SetWide(suggestionW)
        searchSuggestions:MoveToFront()
    end

    -- Live resize: reflow all major child panels when the frame dimensions change
    settingsFrame.PerformLayout = function(self, w, h)
        if IsValid(navContainer) then
            navContainer:SetSize(w - 20, h - 68)
        end
        if IsValid(sidebar) then
            sidebar:SetSize(270, h - 68)
        end
        if IsValid(contentArea) then
            contentArea:SetSize(w - 298, h - 64)
        end
        if IsValid(closeBtn) then
            closeBtn:SetPos(w - 38, 12)
        end

        UpdateSearchSuggestionsLayout()
    end

    -- Side panel navigation system
    navContainer = vgui.Create("DPanel", settingsFrame)
    navContainer:SetPos(10, 58)
    navContainer:SetSize(panelWidth - 20, panelHeight - 68)
    navContainer.Paint = function(self, w, h)
        DrawGlassSurface(self, 0, 0, w, h, 8, Theme.glassLight, WithAlpha(Theme.glassBorder, 58), 4.2, 2, 160)
        if IsAprilFoolsActive() then
            DrawAprilTripOverlay(w, h, 14)
        end
    end
    
    -- Left sidebar for navigation
    sidebar = vgui.Create("DScrollPanel", navContainer)
    sidebar:SetPos(0, 0)
    sidebar:SetSize(270, panelHeight - 68)
    sidebar.Paint = function(self, w, h)
        DrawClippedBlur(self, 0, 0, w, h, 3.4, 1, 135)
        draw.RoundedBoxEx(8, 0, 0, w, h, Theme.glassDark, true, false, true, false)
        if IsAprilFoolsActive() then
            DrawAprilTripOverlay(w, h, 16)
        end
        
        -- Right border with glow
        local accentColor = IsAprilFoolsActive() and GetAprilTripColor(320, 0.85, 1, 140) or Color(Theme.accent.r, Theme.accent.g, Theme.accent.b, 80)
        surface.SetDrawColor(accentColor)
        surface.DrawRect(w - 2, 0, 2, h)
    end
    StyleScrollbar(sidebar:GetVBar())
    
    -- Right content area
    contentArea = vgui.Create("DPanel", navContainer)
    contentArea:SetPos(278, 0)
    contentArea:SetSize(panelWidth - 298, panelHeight - 64)
    contentArea.Paint = function() end
    
    local currentPanel = nil
    local navButtons = {}
    searchMatches = {}
    
    -- Function to create nav button
    local function CreateNavButton(label, icon)
        local btn = vgui.Create("DButton", sidebar)
        btn:SetText("")
        btn:Dock(TOP)
        btn:DockMargin(8, 4, 8, 4)
        btn:SetTall(46)
        btn.isActive = false
        btn.hoverAnim = 0
        btn.pressAnim = 0
        btn.activeAnim = 0
        btn.iconPath = icon
        btn.hasPlayedHoverSound = false
        
        btn.Paint = function(self, w, h)
            local aprilMode = IsAprilFoolsActive()
            if self.isActive then
                self.activeAnim = math.Approach(self.activeAnim, 1, FrameTime() * 10)
            else
                self.activeAnim = math.Approach(self.activeAnim, 0, FrameTime() * 10)
            end

            AnimateButtonVisualState(self, 8, 10, 18, 12)
            HandleButtonHoverSound(self)

            local pushOffset = GetButtonPushOffset(self, 2)
            local bgCol = Theme.bgLight
            local accentColor = aprilMode and GetAprilTripColor(30 + self:GetY(), 0.9, 1, 255) or Theme.accent
            local accentHoverColor = aprilMode and GetAprilTripColor(90 + self:GetY(), 0.9, 1, 255) or Theme.accentHover
            if self.activeAnim > 0 then
                bgCol = LerpColor(self.activeAnim, Theme.bgLight, accentColor)
            elseif self.hoverAnim > 0 then
                bgCol = LerpColor(self.hoverAnim, Theme.bgLight, Theme.bgLighter)
            end
            bgCol = LerpColor(self.pressAnim, bgCol, aprilMode and GetAprilTripColor(0, 0.95, 0.86, 255) or Theme.accentActive)

            local blurStrength = (self.activeAnim * 2.2) + (self.hoverAnim * 1.2) + (self.pressAnim * 2.6)
            if blurStrength > 0.08 then
                DrawClippedBlur(self, 0, pushOffset, w, h, blurStrength, 1, 46 + (self.activeAnim * 36) + (self.pressAnim * 40))
            end

            draw.RoundedBox(6, 0, pushOffset, w, h, WithAlpha(bgCol, 210))

            if self.activeAnim > 0 then
                local lineW = 4
                draw.RoundedBox(2, 0, pushOffset, lineW, h, accentHoverColor)
                surface.SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 60 * self.activeAnim)
                surface.DrawRect(-2, pushOffset, w + 4, h)
            end

            if self.hoverAnim > 0 and not self.isActive then
                surface.SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 40 * self.hoverAnim)
                surface.DrawRect(0, h - 2 + pushOffset, w, 2)
            end

            local iconCol = self.isActive and Theme.textBright or (self:IsHovered() and Theme.text or Theme.textDim)
            surface.SetDrawColor(iconCol)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(12, ((h - 18) / 2) + pushOffset, 18, 18)

            local textCol = self.isActive and Theme.textBright or (self:IsHovered() and Theme.text or Theme.textDim)
            DrawMarqueeText(self, label, "NaiFont_Normal", 38, (h / 2) + pushOffset, textCol, math.max(w - 50, 0), TEXT_ALIGN_CENTER, 28, 18)
        end
        
        table.insert(navButtons, btn)
        return btn
    end
    
    -- Function to switch panels
    local function SwitchToPanel(panel, activeBtn, suppressSound)
        if not suppressSound and GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_click_enabled"):GetBool() then
            surface.PlaySound("nai_passengers/ui_click.wav")
        end
        
        if IsValid(currentPanel) then
            currentPanel:SetVisible(false)
        end
        currentPanel = panel
        panel:SetVisible(true)
        
        for _, btn in ipairs(navButtons) do
            btn.isActive = false
        end

        if IsValid(activeBtn) then
            activeBtn.isActive = true
        end
    end
    
    -- Helper to create content panel
    local function CreateContentPanel()
        local panel = vgui.Create("DScrollPanel", contentArea)
        panel:Dock(FILL)
        panel:SetVisible(false)
        panel.Paint = function() end
        StyleScrollbar(panel:GetVBar())
        return panel
    end

    local SEARCH_SUGGESTION_LIMIT = 4

    local function NormalizeSearchText(text)
        local normalized = string.lower(tostring(text or ""))
        normalized = string.gsub(normalized, "[_%-%./]", " ")
        normalized = string.gsub(normalized, "%s+", " ")
        return string.Trim(normalized)
    end

    local function BuildSearchKeywords(entry)
        return NormalizeSearchText(table.concat({
            entry.panelName or "",
            entry.section or "",
            entry.title or "",
            entry.description or "",
            entry.convar or ""
        }, " "))
    end

    local function ScrollToSearchTarget(panel, target)
        if not IsValid(panel) or not IsValid(target) then
            return
        end

        panel:InvalidateLayout(true)

        local canvas = panel:GetCanvas()
        local y = 0
        local current = target

        while IsValid(current) and current ~= canvas do
            y = y + current:GetY()
            current = current:GetParent()
        end

        local maxScroll = math.max(canvas:GetTall() - panel:GetTall(), 0)
        panel:GetVBar():AnimateTo(math.Clamp(y - 20, 0, maxScroll), 0.2, 0, 0.2)
    end

    local function CollectSearchEntries()
        local entries = {}

        for _, panel in ipairs(contentArea:GetChildren()) do
            if panel.SearchPanelName and panel.GetCanvas then
                local currentSection = panel.SearchPanelName
                local lastEntry = nil

                for _, child in ipairs(panel:GetCanvas():GetChildren()) do
                    if child.SearchSectionTitle then
                        currentSection = child.SearchSectionTitle
                        lastEntry = nil
                    elseif child.SearchLabel then
                        local entry = {
                            panel = panel,
                            button = panel.SearchNavButton,
                            target = child,
                            panelName = panel.SearchPanelName,
                            section = currentSection,
                            title = child.SearchLabel,
                            description = child.SearchDescription or "",
                            convar = child.SearchConVar or ""
                        }

                        entry.keywords = BuildSearchKeywords(entry)
                        table.insert(entries, entry)
                        lastEntry = entry
                    elseif child.SearchHelpText and lastEntry then
                        if lastEntry.description == "" then
                            lastEntry.description = child.SearchHelpText
                        else
                            lastEntry.description = lastEntry.description .. " " .. child.SearchHelpText
                        end

                        lastEntry.keywords = BuildSearchKeywords(lastEntry)
                    end
                end
            end
        end

        return entries
    end

    local function ScoreSearchEntry(entry, query)
        local title = NormalizeSearchText(entry.title)
        local section = NormalizeSearchText(entry.section)
        local panelName = NormalizeSearchText(entry.panelName)
        local description = NormalizeSearchText(entry.description)
        local score = 0

        if title == query then
            score = score + 120
        end
        if string.sub(title, 1, #query) == query then
            score = score + 60
        end
        if string.find(title, query, 1, true) then
            score = score + 40
        end
        if string.find(section, query, 1, true) then
            score = score + 20
        end
        if string.find(panelName, query, 1, true) then
            score = score + 15
        end
        if string.find(description, query, 1, true) then
            score = score + 10
        end

        return score
    end

    local function GetSearchMatches(rawQuery, limit)
        local query = NormalizeSearchText(rawQuery)

        if query == "" then
            return {}
        end

        local matches = {}
        for _, entry in ipairs(CollectSearchEntries()) do
            if string.find(entry.keywords, query, 1, true) then
                entry.score = ScoreSearchEntry(entry, query)
                table.insert(matches, entry)
            end
        end

        table.sort(matches, function(a, b)
            if a.score == b.score then
                return a.title < b.title
            end

            return a.score > b.score
        end)

        if limit and #matches > limit then
            for index = #matches, limit + 1, -1 do
                matches[index] = nil
            end
        end

        return matches
    end

    ClearSearchSuggestions = function()
        searchMatches = {}

        if not IsValid(searchSuggestions) then
            return
        end

        for _, child in ipairs(searchSuggestions:GetChildren()) do
            child:Remove()
        end

        searchSuggestions:SetVisible(false)
        searchSuggestions:SetTall(0)
    end

    local function OpenSearchMatch(entry)
        if not entry then
            return
        end

        ClearSearchSuggestions()

        if IsValid(searchEntry) then
            ClearSearchQuery(false)
        end

        SwitchToPanel(entry.panel, entry.button)

        timer.Simple(0, function()
            ScrollToSearchTarget(entry.panel, entry.target)
        end)
    end

    local function AddSearchSuggestion(parent, entry, rank)
        local result = vgui.Create("DButton", parent)
        result:SetText("")
        result:SetTall(52)
        result:Dock(TOP)
        result:DockMargin(0, rank == 1 and 0 or 4, 0, 0)
        result.hoverAnim = 0
        result.pressAnim = 0

        result.Paint = function(self, w, h)
            AnimateButtonVisualState(self, 10, 12, 18, 12)

            local pushOffset = GetButtonPushOffset(self, 2)
            local bgCol = LerpColor(self.hoverAnim, Theme.bgDark, Theme.bgLighter)
            bgCol = LerpColor(self.pressAnim, bgCol, Theme.bg)
            DrawClippedBlur(self, 0, pushOffset, w, h, 2 + (self.hoverAnim * 1.2) + (self.pressAnim * 2), 1, 44 + (self.pressAnim * 36))
            DrawRoundedSurface(0, pushOffset, w, h, 8, WithAlpha(bgCol, 208), self:IsHovered() and Theme.accentHover or Theme.border)

            draw.SimpleText(tostring(rank), "NaiFont_Small", 14, (h / 2) + pushOffset, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            DrawMarqueeText(self, entry.title, "NaiFont_Normal", 34, 17 + pushOffset, Theme.textBright, math.max(w - 46, 0), TEXT_ALIGN_TOP, 28, 18)
            DrawMarqueeText(self, entry.panelName .. " / " .. entry.section, "NaiFont_Small", 34, 34 + pushOffset, Theme.textDim, math.max(w - 46, 0), TEXT_ALIGN_TOP, 28, 18)
        end

        result.DoClick = function()
            OpenSearchMatch(entry)
        end

        return result
    end

    local function UpdateSearchSuggestions(rawQuery)
        if not IsValid(searchSuggestions) then
            return
        end

        ClearSearchSuggestions()

        local allMatches = GetSearchMatches(rawQuery)
        local totalMatches = #allMatches

        if IsValid(searchStatus) then
            if NormalizeSearchText(rawQuery) == "" then
                searchStatus:SetText("Ctrl+F to focus search")
                searchStatus:SetTextColor(Theme.textDim)
            elseif totalMatches == 0 then
                searchStatus:SetText("No matching settings")
                searchStatus:SetTextColor(Theme.textDim)
            else
                searchStatus:SetText(string.format("Showing top %d of %d matches", math.min(totalMatches, SEARCH_SUGGESTION_LIMIT), totalMatches))
                searchStatus:SetTextColor(Theme.textDim)
            end
            searchStatus:SizeToContents()
        end

        if IsValid(searchClearBtn) then
            searchClearBtn:SetVisible(NormalizeSearchText(rawQuery) ~= "")
        end

        searchMatches = allMatches
        if #searchMatches > SEARCH_SUGGESTION_LIMIT then
            for index = #searchMatches, SEARCH_SUGGESTION_LIMIT + 1, -1 do
                searchMatches[index] = nil
            end
        end

        if #searchMatches == 0 then
            if NormalizeSearchText(rawQuery) == "" then
                return
            end

            local emptyState = vgui.Create("DPanel", searchSuggestions)
            emptyState:SetTall(34)
            emptyState:Dock(TOP)
            emptyState.Paint = function(self, w, h)
                DrawRoundedSurface(0, 0, w, h, 8, Theme.bgDark, Theme.border)
                draw.SimpleText("No matching settings", "NaiFont_Small", 12, h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            searchSuggestions:SetVisible(true)
            searchSuggestions:SetTall(34)
            UpdateSearchSuggestionsLayout()
            return
        end

        local totalHeight = 0
        for index, entry in ipairs(searchMatches) do
            AddSearchSuggestion(searchSuggestions, entry, index)
            totalHeight = totalHeight + 52 + (index == 1 and 0 or 4)
        end

        searchSuggestions:SetVisible(true)
        searchSuggestions:SetTall(totalHeight)
        UpdateSearchSuggestionsLayout()
    end

    searchBox = vgui.Create("DPanel", sidebar)
    searchBox:Dock(TOP)
    searchBox:DockMargin(8, 10, 8, 12)
    searchBox:SetTall(42)
    searchBox.Paint = function(self, w, h)
        local borderColor = self:IsHovered() and Theme.accentHover or Theme.border
        if IsAprilFoolsActive() then
            borderColor = GetAprilTripColor(200, 0.9, 1, 255)
        end
        DrawGlassSurface(self, 0, 0, w, h, 10, Theme.glassLight, borderColor, 3.4, 1, 145)
        if IsAprilFoolsActive() then
            DrawAprilTripOverlay(w, h, 18)
        end
    end
    searchBox.PaintOver = function(self, w, h)
        surface.SetDrawColor(Theme.textDim)
        surface.SetMaterial(Material("icon16/magnifier.png"))
        surface.DrawTexturedRect(12, (h - 16) / 2, 16, 16)
    end

    searchEntry = vgui.Create("DTextEntry", searchBox)
    searchEntry:Dock(FILL)
    searchEntry:DockMargin(36, 6, 34, 6)
    searchEntry:SetFont("NaiFont_Normal")
    searchEntry:SetTextColor(Theme.text)
    searchEntry:SetDrawBackground(false)
    searchEntry:SetUpdateOnType(true)
    searchEntry.Paint = function(self, w, h)
        self:DrawTextEntryText(Theme.text, Theme.accent, Theme.text)

        if self:GetValue() == "" and not self:HasFocus() then
            draw.SimpleText("Search settings...", "NaiFont_Normal", 0, h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    searchEntry.OnKeyCodeTyped = function(self, key)
        if key == KEY_ESCAPE and self:GetValue() ~= "" then
            ClearSearchQuery(true)
            return true
        end
    end

    searchClearBtn = vgui.Create("DButton", searchBox)
    searchClearBtn:SetText("")
    searchClearBtn:SetSize(18, 18)
    searchClearBtn:SetVisible(false)
    searchClearBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and Theme.textBright or Theme.textDim
        draw.SimpleText("x", "NaiFont_Bold", w / 2, h / 2 - 1, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    searchClearBtn.DoClick = function()
        ClearSearchQuery(true)
    end

    searchBox.PerformLayout = function(self, w, h)
        if IsValid(searchClearBtn) then
            searchClearBtn:SetPos(w - 24, math.floor((h - searchClearBtn:GetTall()) / 2))
        end
    end

    searchStatus = vgui.Create("DLabel", sidebar)
    searchStatus:SetText("Ctrl+F to focus search")
    searchStatus:SetFont("NaiFont_Small")
    searchStatus:SetTextColor(Theme.textDim)
    searchStatus:Dock(TOP)
    searchStatus:DockMargin(12, -6, 12, 10)
    searchStatus:SizeToContents()

    searchSuggestions = vgui.Create("DPanel", navContainer)
    searchSuggestions:SetTall(0)
    searchSuggestions:SetWide(0)
    searchSuggestions:SetVisible(false)
    searchSuggestions:DockPadding(6, 6, 6, 6)
    searchSuggestions.Paint = function(self, w, h)
        DrawGlassSurface(self, 0, 0, w, h, 10, Theme.glassLight, Theme.border, 4, 2, 160)
        if IsAprilFoolsActive() then
            DrawAprilTripOverlay(w, h, 20)
            DrawAprilSpinner(24, h / 2, 11, 740, 10, 150)
            DrawAprilSpinner(w - 24, h / 2, 11, 880, 200, 150)
        end
    end
    UpdateSearchSuggestionsLayout()

    searchEntry.OnChange = function(self)
        UpdateSearchSuggestions(self:GetValue())
    end
    searchEntry.OnEnter = function(self)
        if searchMatches[1] then
            OpenSearchMatch(searchMatches[1])
        end
    end
    settingsFrame.OnKeyCodePressed = function(self, key)
        if key == KEY_F and (input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)) then
            FocusSearchEntry()
            return
        end

        if key == KEY_ESCAPE and IsValid(searchEntry) and searchEntry:GetValue() ~= "" then
            ClearSearchQuery(false)
        end
    end
    
    -- General Tab
    local generalPanel = CreateContentPanel()
    generalPanel.SearchPanelName = "General"
    local generalBtn = CreateNavButton("General", "icon16/cog.png")
    generalPanel.SearchNavButton = generalBtn
    generalBtn.DoClick = function() SwitchToPanel(generalPanel, generalBtn) end
    
    CreateSectionHeader(generalPanel, "General Settings")
    
    CreateCheckbox(generalPanel, "Allow Multiple Passengers", "nai_npc_allow_multiple")
    CreateHelpText(generalPanel, "Let multiple NPCs ride in the same vehicle.")
    
    CreateSpacer(generalPanel, 5)
    
    CreateComboBox(generalPanel, "Exit Behavior", "nai_npc_exit_mode", {
        { label = "Leave when player exits", value = 0 },
        { label = "Leave when vehicle is attacked", value = 1 },
        { label = "Never leave automatically", value = 2 },
    })
    CreateHelpText(generalPanel, "When should NPC passengers exit the vehicle?")
    
    CreateSpacer(generalPanel, 10)
    CreateSectionHeader(generalPanel, "Timing")
    
    CreateSlider(generalPanel, "Max Attach Distance", "nai_npc_max_attach_dist", 100, 2000, 0)
    CreateHelpText(generalPanel, "Maximum distance (units) to attach NPC to vehicle.")
    
    CreateSlider(generalPanel, "Detach Delay", "nai_npc_detach_delay", 0, 10, 1)
    CreateHelpText(generalPanel, "Seconds to wait before detaching after player leaves.")
    
    CreateSlider(generalPanel, "AI Restore Delay", "nai_npc_ai_delay", 0, 10, 1)
    CreateHelpText(generalPanel, "Seconds to wait before restoring NPC AI after detaching.")
    
    CreateSlider(generalPanel, "Cooldown Time", "nai_npc_cooldown", 0, 10, 1)
    CreateHelpText(generalPanel, "Cooldown between attaching NPCs to same vehicle.")
    
    CreateSlider(generalPanel, "Passenger Limit", "nai_npc_passenger_limit", 1, 20, 0)
    CreateHelpText(generalPanel, "Max NPCs allowed in vehicle.")
    
    -- Auto-Join Tab
    local autoJoinPanel = CreateContentPanel()
    autoJoinPanel.SearchPanelName = "Auto-Join"
    local autoJoinBtn = CreateNavButton("Auto-Join", "icon16/group.png")
    autoJoinPanel.SearchNavButton = autoJoinBtn
    autoJoinBtn.DoClick = function() SwitchToPanel(autoJoinPanel, autoJoinBtn) end
    
    CreateSectionHeader(autoJoinPanel, "Auto-Join (Squad Behavior)")
    CreateHelpText(autoJoinPanel, "Friendly NPCs will automatically board your vehicle when you enter it - just like squad mechanics in Half-Life 2!")
    
    CreateSpacer(autoJoinPanel, 5)
    
    CreateCheckbox(autoJoinPanel, "Enable Auto-Join", "nai_npc_auto_join")
    CreateHelpText(autoJoinPanel, "Nearby friendly NPCs will automatically join when you enter a vehicle.")
    
    CreateSlider(autoJoinPanel, "Auto-Join Range", "nai_npc_auto_join_range", 100, 2000, 0)
    CreateHelpText(autoJoinPanel, "Maximum distance to find NPCs for auto-joining.")
    
    CreateSlider(autoJoinPanel, "Max Auto-Join NPCs", "nai_npc_auto_join_max", 1, 10, 0)
    CreateHelpText(autoJoinPanel, "Maximum number of NPCs that can auto-join at once.")
    
    CreateCheckbox(autoJoinPanel, "Squad Members Only", "nai_npc_auto_join_squad_only")
    CreateHelpText(autoJoinPanel, "Only NPCs with a squad name will auto-join (for HL2-style squads).")

    -- Passengers Tab
    local passengersPanel = CreateContentPanel()
    passengersPanel.SearchPanelName = "Passengers"
    local passengersBtn = CreateNavButton("Passengers", "icon16/group_gear.png")
    passengersPanel.SearchNavButton = passengersBtn

    local passengerControlList
    local passengersCurrentVehicleOnly = false
    local currentVehicleOnlyBtn
    local passengerOverviewPanel
    local passengerCardIcons = {}
    local passengerCardIconsLoaded = false

    local passengerStatusColors = {
        calm = Color(105, 208, 140),
        alert = Color(255, 191, 84),
        scared = Color(255, 110, 110),
        drowsy = Color(124, 177, 255),
        dead = Color(112, 118, 130),
        default = Color(180, 180, 180),
    }

    local passengerStatusLabels = {
        calm = "Calm",
        alert = "Alert",
        scared = "Scared",
        drowsy = "Drowsy",
        dead = "Dead",
        default = "Unknown",
    }

    local function LoadPassengerCardIcons()
        if passengerCardIconsLoaded then
            return
        end

        passengerCardIconsLoaded = true
        for _, iconName in ipairs({"passenger", "calm", "alert", "scared", "drowsy", "dead"}) do
            local material = Material("nai_passengers/icon_" .. iconName .. ".png", "smooth mips")
            if not material:IsError() then
                passengerCardIcons[iconName] = material
            end
        end
    end

    local function GetPassengerCardStatus(npc)
        if not IsValid(npc) then
            return "default", 0
        end

        local alertThreshold = GetConVar("nai_npc_hud_alert_threshold")
        local fearThreshold = GetConVar("nai_npc_hud_fear_threshold")
        local drowsyThreshold = GetConVar("nai_npc_hud_drowsy_threshold")
        local drowsyTime = GetConVar("nai_npc_drowsy_time")

        local alertLevel = npc:GetNWFloat("NPCPassengerAlertLevel", 0)
        local fearLevel = npc:GetNWFloat("NPCPassengerFearLevel", 0)
        local isDrowsy = npc:GetNWBool("NPCPassengerIsDrowsy", false)
        local calmTime = npc:GetNWFloat("NPCPassengerCalmTime", 0)

        local at = alertThreshold and alertThreshold:GetFloat() or 0.3
        local ft = fearThreshold and fearThreshold:GetFloat() or 0.5
        local dt = drowsyThreshold and drowsyThreshold:GetFloat() or 0.7
        local drowsyTimeVal = drowsyTime and drowsyTime:GetFloat() or 60

        if npc:Health() <= 0 or not npc:Alive() then
            return "dead", 1
        elseif fearLevel >= ft then
            return "scared", fearLevel
        elseif alertLevel >= at then
            return "alert", alertLevel
        elseif isDrowsy or (drowsyTimeVal > 0 and calmTime / drowsyTimeVal >= dt) then
            return "drowsy", calmTime / math.max(1, drowsyTimeVal)
        else
            return "calm", 0
        end
    end

    local function GetPassengerCardDisplayName(npc)
        if not IsValid(npc) then return "Unknown" end

        local targetName = npc:GetNWString("targetname", "")
        if targetName == "" and npc.GetInternalVariable then
            targetName = npc:GetInternalVariable("m_iName") or ""
        end
        if targetName and targetName ~= "" then return targetName end

        local classNames = {
            ["npc_citizen"] = "Citizen",
            ["npc_alyx"] = "Alyx",
            ["npc_barney"] = "Barney",
            ["npc_monk"] = "Father Grigori",
            ["npc_eli"] = "Eli",
            ["npc_kleiner"] = "Dr. Kleiner",
            ["npc_mossman"] = "Dr. Mossman",
            ["npc_breen"] = "Dr. Breen",
            ["npc_vortigaunt"] = "Vortigaunt",
            ["npc_dog"] = "Dog",
        }

        return classNames[npc:GetClass() or ""] or string.upper(string.Replace(npc:GetClass() or "unknown", "npc_", ""))
    end

    local function DrawInfoPill(x, y, w, h, text, fillColor, textColor)
        draw.RoundedBox(6, x, y, w, h, fillColor)
        draw.SimpleText(text, "NaiFont_Small", x + w / 2, y + h / 2, textColor or Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function UpdatePassengerOverview(passengers, currentVehicle)
        if not IsValid(passengerOverviewPanel) then
            return
        end

        passengerOverviewPanel.totalPassengers = #passengers
        passengerOverviewPanel.currentVehiclePassengers = 0
        passengerOverviewPanel.scaredPassengers = 0
        passengerOverviewPanel.drowsyPassengers = 0

        for _, npc in ipairs(passengers) do
            local status = GetPassengerCardStatus(npc)
            if currentVehicle and GetPassengerControlVehicle(npc) == currentVehicle then
                passengerOverviewPanel.currentVehiclePassengers = passengerOverviewPanel.currentVehiclePassengers + 1
            end
            if status == "scared" then
                passengerOverviewPanel.scaredPassengers = passengerOverviewPanel.scaredPassengers + 1
            elseif status == "drowsy" then
                passengerOverviewPanel.drowsyPassengers = passengerOverviewPanel.drowsyPassengers + 1
            end
        end

        passengerOverviewPanel:InvalidateLayout(true)
    end

    local function RefreshPassengersControlList()
        if not IsValid(passengerControlList) then
            return
        end

        LoadPassengerCardIcons()
        passengerControlList:Clear()

        local passengers = {}
        local ply = LocalPlayer()
        local currentVehicle = IsValid(ply) and ply:InVehicle() and GetClientRootVehicle(ply:GetVehicle()) or nil

        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNPCPassenger", false) then
                local passengerVehicle = GetPassengerControlVehicle(ent)
                if not passengersCurrentVehicleOnly or (IsValid(currentVehicle) and passengerVehicle == currentVehicle) then
                    passengers[#passengers + 1] = ent
                end
            end
        end

        table.sort(passengers, function(a, b)
            local vehicleA = GetPassengerControlVehicle(a)
            local vehicleB = GetPassengerControlVehicle(b)
            local aInCurrent = IsValid(currentVehicle) and vehicleA == currentVehicle
            local bInCurrent = IsValid(currentVehicle) and vehicleB == currentVehicle

            if aInCurrent ~= bInCurrent then
                return aInCurrent
            end

            local classA = a:GetClass() or ""
            local classB = b:GetClass() or ""
            if classA == classB then
                return a:EntIndex() < b:EntIndex()
            end

            return classA < classB
        end)

        UpdatePassengerOverview(passengers, currentVehicle)

        if #passengers == 0 then
            local noPassengers = vgui.Create("DLabel", passengerControlList)
            noPassengers:SetFont("NaiFont_Normal")
            noPassengers:SetTextColor(Theme.textDim)
            noPassengers:Dock(TOP)
            noPassengers:DockMargin(10, 10, 10, 10)
            noPassengers:SetWrap(true)
            noPassengers:SetAutoStretchVertical(true)

            if passengersCurrentVehicleOnly and not IsValid(currentVehicle) then
                noPassengers:SetText("No current vehicle detected. Sit in a vehicle or disable the current-vehicle filter.")
            elseif passengersCurrentVehicleOnly then
                noPassengers:SetText("No passengers found in your current vehicle.")
            else
                noPassengers:SetText("No passengers found. NPCs need to be riding in a vehicle before they can be managed here.")
            end

            return
        end

        for _, npc in ipairs(passengers) do
            local passengerVehicle = GetPassengerControlVehicle(npc)
            local matchingVehicle = IsPassengerInLocalPlayersVehicle(npc)
            local status, intensity = GetPassengerCardStatus(npc)
            local statusColor = passengerStatusColors[status] or passengerStatusColors.default
            local statusLabel = passengerStatusLabels[status] or passengerStatusLabels.default
            local currentSeat = GetClientVehicleSeatIndex(passengerVehicle, npc:GetParent()) or 1
            local maxHealth = math.max(npc:GetMaxHealth(), 1)
            local healthValue = math.max(npc:Health(), 0)
            local healthFrac = math.Clamp(healthValue / maxHealth, 0, 1)
            local seatChoices = math.max(currentSeat + 2, 8)

            local npcPanel = vgui.Create("DPanel", passengerControlList)
            npcPanel:Dock(TOP)
            npcPanel:SetTall(176)
            npcPanel:DockMargin(8, 6, 8, 6)
            npcPanel.Paint = function(self, w, h)
                if not IsValid(npc) then return end

                draw.RoundedBox(10, 0, 0, w, h, Theme.bgLighter)
                draw.RoundedBox(10, 0, 0, 10, h, statusColor)

                local gradientMat = Material("vgui/gradient-r")
                surface.SetDrawColor(statusColor.r, statusColor.g, statusColor.b, 35)
                surface.SetMaterial(gradientMat)
                surface.DrawTexturedRect(0, 0, w, h)

                local passengerName = GetPassengerCardDisplayName(npc)
                draw.SimpleText(passengerName, "NaiFont_Bold", 76, 18, Theme.textBright)

                if passengerCardIcons[status] then
                    surface.SetFont("NaiFont_Bold")
                    local nameWidth = surface.GetTextSize(passengerName)
                    surface.SetDrawColor(255, 255, 255, 255)
                    surface.SetMaterial(passengerCardIcons[status])
                    surface.DrawTexturedRect(76 + nameWidth + 8, 11, 22, 22)
                end

                draw.SimpleText((npc:GetClass() or "npc") .. "  |  #" .. npc:EntIndex(), "NaiFont_Small", 76, 38, Theme.textDim)
                draw.SimpleText(IsValid(passengerVehicle) and ("Vehicle: " .. passengerVehicle:GetClass()) or "Vehicle: Unknown", "NaiFont_Small", 76, 58, Theme.text)

                DrawInfoPill(76, 82, 92, 22, "Seat " .. currentSeat, Color(30, 36, 44, 240), Theme.textBright)
                DrawInfoPill(176, 82, 96, 22, statusLabel, Color(statusColor.r, statusColor.g, statusColor.b, 220), Theme.bgDark)
                DrawInfoPill(280, 82, 118, 22, matchingVehicle and "Same Vehicle" or "Other Vehicle", matchingVehicle and Color(46, 78, 62, 230) or Color(54, 58, 68, 230), matchingVehicle and Theme.success or Theme.textDim)
                DrawInfoPill(406, 82, 86, 22, npc:GetNWBool("NPCPassengerHidden", false) and "Hidden" or "Visible", Color(30, 36, 44, 230), Theme.textBright)

                local healthBarX = 76
                local healthBarY = 114
                local healthBarW = w - 100
                draw.RoundedBox(6, healthBarX, healthBarY, healthBarW, 14, Theme.bgDark)
                draw.RoundedBox(6, healthBarX, healthBarY, math.max(healthBarW * healthFrac, 10), 14, Color(112, 214, 136))
                draw.SimpleText(string.format("Health %d / %d", healthValue, maxHealth), "NaiFont_Small", healthBarX + 10, healthBarY + 7, Theme.bgDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local intensityBarX = 76
                local intensityBarY = 138
                local intensityBarW = w - 100
                draw.RoundedBox(6, intensityBarX, intensityBarY, intensityBarW, 10, Theme.bgDark)
                draw.RoundedBox(6, intensityBarX, intensityBarY, math.max(intensityBarW * math.Clamp(intensity, 0.05, 1), 8), 10, Color(statusColor.r, statusColor.g, statusColor.b, 225))
                draw.SimpleText(string.format("Status intensity %.0f%%", math.Clamp(intensity, 0, 1) * 100), "NaiFont_Small", intensityBarX + intensityBarW, intensityBarY - 8, Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            end

            local seatCombo = vgui.Create("DComboBox", npcPanel)
            seatCombo:SetPos(76, 148)
            seatCombo:SetSize(112, 24)
            seatCombo:SetFont("NaiFont_Small")
            for seatNumber = 1, seatChoices do
                seatCombo:AddChoice("Seat " .. seatNumber, seatNumber)
            end
            seatCombo:ChooseOptionID(currentSeat)
            seatCombo:SetValue("Seat " .. currentSeat)

            local assignBtn = vgui.Create("DButton", npcPanel)
            assignBtn:SetPos(198, 146)
            assignBtn:SetSize(136, 28)
            assignBtn:SetFont("NaiFont_Normal")
            assignBtn:SetTextColor(TransparentColor)
            assignBtn:SetText("Assign Seat")
            assignBtn.hoverAnim = 0
            assignBtn.pressAnim = 0
            assignBtn.Paint = function(self, w, h)
                local enabled = IsValid(npc) and IsPassengerInLocalPlayersVehicle(npc)
                AnimateButtonVisualState(self, 8, 10, 18, 12)

                local pushOffset = GetButtonPushOffset(self, enabled and 2 or 0)
                local baseColor = enabled and Theme.accent or Theme.bgDark
                local hoverColor = enabled and Theme.accentHover or Theme.bgDark
                local color = LerpColor(self.hoverAnim, baseColor, hoverColor)
                if enabled then
                    color = LerpColor(self.pressAnim, color, Theme.accentActive)
                    DrawClippedBlur(self, 0, pushOffset, w, h, 2 + (self.hoverAnim * 1.2) + (self.pressAnim * 1.8), 1, 42 + (self.pressAnim * 34))
                end
                draw.RoundedBox(4, 0, pushOffset, w, h, WithAlpha(color, enabled and 214 or 236))
                draw.SimpleText(self:GetText(), "NaiFont_Normal", w / 2, (h / 2) + pushOffset, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            assignBtn.DoClick = function()
                if not IsValid(npc) then return end
                if not IsPassengerInLocalPlayersVehicle(npc) then
                    chat.AddText(Color(255, 180, 120), ADDON_CHAT_PREFIX, Theme.text, "Sit in the same vehicle to reassign this passenger.")
                    return
                end

                local _, seatNumber = seatCombo:GetSelected()
                seatNumber = seatNumber or 1

                net.Start("NPCPassengers_AssignSeat")
                    net.WriteEntity(npc)
                    net.WriteUInt(seatNumber, 8)
                net.SendToServer()

                timer.Simple(0.15, function()
                    if IsValid(passengerControlList) then
                        RefreshPassengersControlList()
                    end
                end)
            end

            local detachBtn = vgui.Create("DButton", npcPanel)
            detachBtn:SetPos(344, 146)
            detachBtn:SetSize(104, 28)
            detachBtn:SetFont("NaiFont_Normal")
            detachBtn:SetTextColor(TransparentColor)
            detachBtn:SetText("Detach")
            detachBtn.hoverAnim = 0
            detachBtn.pressAnim = 0
            detachBtn.Paint = function(self, w, h)
                AnimateButtonVisualState(self, 8, 10, 18, 12)

                local pushOffset = GetButtonPushOffset(self, 2)
                local color = LerpColor(self.hoverAnim, Theme.bgDark, Theme.error)
                color = LerpColor(self.pressAnim, color, Color(140, 60, 60))
                DrawClippedBlur(self, 0, pushOffset, w, h, 2 + (self.hoverAnim * 1.2) + (self.pressAnim * 2), 1, 40 + (self.pressAnim * 34))
                draw.RoundedBox(4, 0, pushOffset, w, h, WithAlpha(color, 214))
                draw.SimpleText(self:GetText(), "NaiFont_Normal", w / 2, (h / 2) + pushOffset, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            detachBtn.DoClick = function()
                if not IsValid(npc) then return end

                net.Start("NPCPassengers_RemovePassenger")
                    net.WriteEntity(npc)
                net.SendToServer()

                timer.Simple(0.15, function()
                    if IsValid(passengerControlList) then
                        RefreshPassengersControlList()
                    end
                end)
            end
        end
    end

    passengersBtn.DoClick = function()
        SwitchToPanel(passengersPanel, passengersBtn)
        RefreshPassengersControlList()
    end

    CreateSectionHeader(passengersPanel, "Passenger Controls")
    CreateHelpText(passengersPanel, "Manage active passengers, reassign seats, and detach riders without leaving the settings panel.")

    passengerOverviewPanel = vgui.Create("DPanel", passengersPanel)
    passengerOverviewPanel:SetTall(104)
    passengerOverviewPanel:Dock(TOP)
    passengerOverviewPanel:DockMargin(8, 6, 8, 6)
    passengerOverviewPanel.totalPassengers = 0
    passengerOverviewPanel.currentVehiclePassengers = 0
    passengerOverviewPanel.scaredPassengers = 0
    passengerOverviewPanel.drowsyPassengers = 0
    passengerOverviewPanel.Paint = function(self, w, h)
        DrawGlassSurface(self, 0, 0, w, h, 10, Theme.glassDark, WithAlpha(Theme.glassBorder, 40), 3.8, 1, 140)

        local gradientMat = Material("vgui/gradient-r")
        surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 42)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, 0, w, h)

        draw.SimpleText("Passenger Operations", "NaiFont_Bold", 16, 18, Theme.textBright)
        draw.SimpleText("Live overview for all currently attached riders", "NaiFont_Small", 16, 40, Theme.textDim)

        DrawInfoPill(16, 62, 120, 26, "Total: " .. self.totalPassengers, Theme.bgLighter, Theme.textBright)
        DrawInfoPill(146, 62, 172, 26, "Current Vehicle: " .. self.currentVehiclePassengers, Color(38, 58, 72, 220), Theme.textBright)
        DrawInfoPill(328, 62, 116, 26, "Scared: " .. self.scaredPassengers, Color(98, 40, 40, 220), Theme.textBright)
        DrawInfoPill(454, 62, 122, 26, "Drowsy: " .. self.drowsyPassengers, Color(44, 60, 92, 220), Theme.textBright)
    end

    CreateButton(passengersPanel, "Refresh Passenger List", RefreshPassengersControlList)

    currentVehicleOnlyBtn = CreateButton(passengersPanel, "Show Current Vehicle Only: OFF", function()
        passengersCurrentVehicleOnly = not passengersCurrentVehicleOnly
        currentVehicleOnlyBtn:SetText("Show Current Vehicle Only: " .. (passengersCurrentVehicleOnly and "ON" or "OFF"))
        RefreshPassengersControlList()
    end)

    CreateButton(passengersPanel, "Make Current Vehicle Passengers Exit", function()
        if not LocalPlayer():InVehicle() then
            chat.AddText(Color(255, 180, 120), ADDON_CHAT_PREFIX, Theme.text, "You need to be in a vehicle to use this.")
            return
        end

        RunConsoleCommand("nai_npc_detach_all")
        timer.Simple(0.15, function()
            if IsValid(passengerControlList) then
                RefreshPassengersControlList()
            end
        end)
    end)

    passengerControlList = vgui.Create("DScrollPanel", passengersPanel)
    passengerControlList:SetTall(420)
    passengerControlList:Dock(TOP)
    passengerControlList:DockMargin(5, 5, 5, 5)
    StyleScrollbar(passengerControlList:GetVBar())
    passengerControlList.Paint = function(self, w, h)
        DrawGlassSurface(self, 0, 0, w, h, 6, Theme.glassDark, WithAlpha(Theme.glassBorder, 34), 3.2, 1, 132)
    end
    
    -- Position Tab
    local posPanel = CreateContentPanel()
    posPanel.SearchPanelName = "Position"
    local posBtn = CreateNavButton("Position", "icon16/arrow_out.png")
    posPanel.SearchNavButton = posBtn
    posBtn.DoClick = function() SwitchToPanel(posPanel, posBtn) end
    
    CreateSectionHeader(posPanel, "Position Offsets")
    CreateHelpText(posPanel, "Fine-tune NPC positioning in vehicles. Use these to fix floating or clipping issues.")
    
    CreateSlider(posPanel, "Height Offset", "nai_npc_height_offset", -50, 50, 0)
    CreateSlider(posPanel, "Forward Offset", "nai_npc_forward_offset", -50, 50, 0)
    CreateSlider(posPanel, "Right Offset", "nai_npc_right_offset", -50, 50, 0)
    
    CreateSpacer(posPanel, 10)
    CreateSectionHeader(posPanel, "Angle Offsets")
    CreateHelpText(posPanel, "Adjust NPC rotation in vehicles.")
    
    CreateSlider(posPanel, "Yaw (Rotation)", "nai_npc_yaw_offset", -180, 180, 0)
    CreateSlider(posPanel, "Pitch (Tilt Forward)", "nai_npc_pitch_offset", -45, 45, 0)
    CreateSlider(posPanel, "Roll (Tilt Sideways)", "nai_npc_roll_offset", -45, 45, 0)
    
    CreateSpacer(posPanel, 15)
    CreateButton(posPanel, "Reset Position & Angles", function()
        RunConsoleCommand("nai_npc_height_offset", "-3")
        RunConsoleCommand("nai_npc_forward_offset", "0")
        RunConsoleCommand("nai_npc_right_offset", "0")
        RunConsoleCommand("nai_npc_yaw_offset", "0")
        RunConsoleCommand("nai_npc_pitch_offset", "0")
        RunConsoleCommand("nai_npc_roll_offset", "0")
        settingsFrame:Close()
        timer.Simple(0.1, OpenSettingsPanel)
    end)
    
    -- Speech & Behavior Tab
    local speechPanel = CreateContentPanel()
    speechPanel.SearchPanelName = "Behaviour"
    local speechBtn = CreateNavButton("Behaviour", "icon16/sound.png")
    speechPanel.SearchNavButton = speechBtn
    speechBtn.DoClick = function() SwitchToPanel(speechPanel, speechBtn) end
    
    CreateSectionHeader(speechPanel, "NPC Speech (Advanced)")
    CreateHelpText(speechPanel, "Configure how NPCs vocalize while riding in vehicles. HL2-style citizen voices!")
    
    CreateSpacer(speechPanel, 5)
    
    CreateCheckbox(speechPanel, "Enable NPC Speech", "nai_npc_speech_enabled")
    CreateHelpText(speechPanel, "Master toggle for all NPC speech. Disable to silence passengers completely.")
    
    CreateSlider(speechPanel, "Speech Volume", "nai_npc_speech_volume", 0, 100, 0)
    CreateHelpText(speechPanel, "How loud NPC voices are (0 = silent, 100 = full volume).")
    
    CreateSlider(speechPanel, "Pitch Variation (+/-)", "nai_npc_speech_pitch_var", 0, 20, 0)
    CreateHelpText(speechPanel, "Random pitch variation for more natural voices. 0 = monotone, higher = more variety.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Crash Reactions")
    
    CreateCheckbox(speechPanel, "Enable Crash Sounds", "nai_npc_speech_crash")
    CreateHelpText(speechPanel, "NPCs grunt/yelp when vehicle decelerates sharply (crashes, hard braking).")
    
    CreateSlider(speechPanel, "Crash Sensitivity", "nai_npc_speech_crash_threshold", 100, 1000, 0)
    CreateHelpText(speechPanel, "Deceleration needed to trigger crash sounds. Lower = more sensitive.")
    
    CreateSlider(speechPanel, "Crash Sound Cooldown", "nai_npc_speech_crash_cooldown", 0.5, 5, 1)
    CreateHelpText(speechPanel, "Minimum seconds between crash sounds per NPC.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Idle Chatter")
    
    CreateCheckbox(speechPanel, "Enable Idle Chatter", "nai_npc_speech_idle")
    CreateHelpText(speechPanel, "NPCs occasionally speak while riding - comments, questions, observations.")
    
    CreateSlider(speechPanel, "Chatter Chance", "nai_npc_speech_idle_chance", 0, 1, 2)
    CreateHelpText(speechPanel, "Probability of chatter per check. 0 = never, 1 = always tries to speak.")
    
    CreateSlider(speechPanel, "Chatter Interval", "nai_npc_speech_idle_interval", 5, 60, 0)
    CreateHelpText(speechPanel, "Minimum seconds between idle chatter attempts.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Board/Exit Sounds")
    
    CreateCheckbox(speechPanel, "Enable Board/Exit Sounds", "nai_npc_speech_board")
    CreateHelpText(speechPanel, "NPCs speak when entering and exiting vehicles.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Ambient Sounds")
    
    CreateCheckbox(speechPanel, "Enable Ambient Sounds", "nai_npc_ambient_sounds")
    CreateHelpText(speechPanel, "Occasional coughs, sighs, hums - background life sounds.")
    
    CreateSlider(speechPanel, "Ambient Sound Interval", "nai_npc_ambient_interval", 10, 120, 0)
    CreateHelpText(speechPanel, "Average seconds between ambient sounds.")
    
    CreateSpacer(speechPanel, 15)
    CreateSectionHeader(speechPanel, "Animation & Behavior")
    CreateHelpText(speechPanel, "Fine-tune NPC animations and head movement.")
    
    CreateSpacer(speechPanel, 5)
    
    CreateCheckbox(speechPanel, "Enable Head/Eye Looking", "nai_npc_head_look")
    CreateHelpText(speechPanel, "NPCs naturally look around, at the player, out windows, etc.")
    
    CreateSlider(speechPanel, "Head Smoothness", "nai_npc_head_smooth", 0.1, 1, 2)
    CreateHelpText(speechPanel, "How smoothly the head moves. Lower = snappier, higher = floaty.")
    
    CreateCheckbox(speechPanel, "Enable Blinking", "nai_npc_blink")
    CreateHelpText(speechPanel, "NPCs blink realistically while sitting.")
    
    CreateCheckbox(speechPanel, "Enable Breathing", "nai_npc_breathing")
    CreateHelpText(speechPanel, "Subtle breathing animation on NPC heads.")
    
    CreateSlider(speechPanel, "Walk Timeout", "nai_npc_walk_timeout", 1, 15, 0)
    CreateHelpText(speechPanel, "Seconds before NPC gives up walking to vehicle.")
    
    CreateSpacer(speechPanel, 15)
    CreateSectionHeader(speechPanel, "Advanced Realism")
    CreateHelpText(speechPanel, "Physics-based reactions and awareness systems for ultimate immersion.")
    
    CreateSpacer(speechPanel, 5)
    CreateSubHeader(speechPanel, "Gesture Animations")
    
    CreateCheckbox(speechPanel, "Enable Talking Gestures", "nai_npc_talking_gestures")
    CreateHelpText(speechPanel, "NPCs randomly play hand gestures and body animations while riding.")
    
    CreateSlider(speechPanel, "Gesture Chance (%)", "nai_npc_gesture_chance", 1, 50, 0)
    CreateHelpText(speechPanel, "Percent chance to play a gesture each interval.")
    
    CreateSlider(speechPanel, "Gesture Interval", "nai_npc_gesture_interval", 3, 30, 0)
    CreateHelpText(speechPanel, "Seconds between gesture opportunity checks.")
    
    CreateCheckbox(speechPanel, "Enable Crash Flinch", "nai_npc_crash_flinch")
    CreateHelpText(speechPanel, "NPCs flinch and lurch forward when vehicle crashes or brakes hard.")
    
    CreateSlider(speechPanel, "Crash Sensitivity", "nai_npc_crash_threshold", 200, 800, 0)
    CreateHelpText(speechPanel, "Velocity change needed to trigger flinch (lower = more sensitive).")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Body Physics")
    
    CreateCheckbox(speechPanel, "Enable Body Sway", "nai_npc_body_sway")
    CreateHelpText(speechPanel, "NPCs lean into turns, brace during acceleration/braking.")
    
    CreateSlider(speechPanel, "Sway Intensity", "nai_npc_body_sway_amount", 0.1, 3, 1)
    CreateHelpText(speechPanel, "How much NPCs sway with vehicle movement.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Threat Awareness")
    
    CreateCheckbox(speechPanel, "Enable Threat Awareness", "nai_npc_threat_awareness")
    CreateHelpText(speechPanel, "NPCs automatically look toward nearby enemies.")
    
    CreateSlider(speechPanel, "Threat Detection Range", "nai_npc_threat_range", 500, 5000, 0)
    CreateHelpText(speechPanel, "How far NPCs can detect threats for head tracking.")
    
    CreateCheckbox(speechPanel, "Combat Alertness", "nai_npc_combat_alert")
    CreateHelpText(speechPanel, "NPCs become tense and reactive when enemies are near.")

    CreateCheckbox(speechPanel, "NPCs shoot from vehicles (Experimental)", "nai_npc_passenger_combat")
    CreateHelpText(speechPanel, "Disabled by default. Enable this to let armed passengers fire from inside vehicles.")

    CreateSlider(speechPanel, "Passenger Combat Range", "nai_npc_passenger_combat_range", 500, 5000, 0)
    CreateHelpText(speechPanel, "How far armed passengers can acquire targets.")

    CreateSlider(speechPanel, "Passenger Accuracy", "nai_npc_passenger_combat_accuracy", 0.1, 1, 2)
    CreateHelpText(speechPanel, "Higher values tighten shot spread for armed passengers.")

    CreateSlider(speechPanel, "Passenger Damage Multiplier", "nai_npc_passenger_combat_damage", 0.25, 3, 2)
    CreateHelpText(speechPanel, "Scales the damage dealt by passenger-fired shots.")
    
    CreateCheckbox(speechPanel, "Passenger Interaction", "nai_npc_passenger_interaction")
    CreateHelpText(speechPanel, "Multiple passengers look at and occasionally chat with each other.")
    
    CreateSpacer(speechPanel, 10)
    CreateSubHeader(speechPanel, "Emotional States")
    
    CreateCheckbox(speechPanel, "Enable Fear Reactions", "nai_npc_fear_reactions")
    CreateHelpText(speechPanel, "NPCs get scared by dangerous driving - wide eyes, panicked sounds.")
    
    CreateSlider(speechPanel, "Fear Speed Threshold", "nai_npc_fear_speed", 400, 2000, 0)
    CreateHelpText(speechPanel, "Speed (units/sec) at which NPCs start getting nervous.")
    
    CreateCheckbox(speechPanel, "Enable Drowsiness", "nai_npc_drowsiness")
    CreateHelpText(speechPanel, "NPCs get sleepy on long, calm rides - slow blinks, head nods.")
    
    CreateSlider(speechPanel, "Drowsy Time", "nai_npc_drowsy_time", 20, 180, 0)
    CreateHelpText(speechPanel, "Seconds of calm riding before drowsiness kicks in.")
    
    -- Tank/LVS Tab
    local tankPanel = CreateContentPanel()
    tankPanel.SearchPanelName = "Tank/LVS"
    local tankBtn = CreateNavButton("Tank/LVS", "icon16/shield.png")
    tankPanel.SearchNavButton = tankBtn
    tankBtn.DoClick = function() SwitchToPanel(tankPanel, tankBtn) end
    
    CreateSectionHeader(tankPanel, "Tank / LVS Vehicle Settings")
    CreateHelpText(tankPanel, "Settings for tanks, APCs, and LVS vehicles.")
    
    CreateSpacer(tankPanel, 5)
    
    CreateCheckbox(tankPanel, "Hide NPCs in Enclosed Vehicles", "nai_npc_hide_in_tanks")
    CreateHelpText(tankPanel, "Make NPC passengers invisible when inside tanks and APCs.")
    
    CreateSpacer(tankPanel, 10)
    CreateSubHeader(tankPanel, "NPC Auto-Driver")
    
    CreateCheckbox(tankPanel, "Enable Auto-Drive", "nai_npc_driver_enabled")
    CreateHelpText(tankPanel, "Allow NPCs in driver seat to automatically drive toward enemies.")
    
    CreateSlider(tankPanel, "Detection Range", "nai_npc_driver_range", 500, 10000, 0)
    CreateHelpText(tankPanel, "Maximum range for driver to detect enemies.")
    
    CreateSlider(tankPanel, "Engage Distance", "nai_npc_driver_engage_distance", 200, 2000, 0)
    CreateHelpText(tankPanel, "Distance to maintain from enemies.")
    
    CreateSlider(tankPanel, "Drive Speed", "nai_npc_driver_speed", 0.1, 1, 2)
    CreateHelpText(tankPanel, "Throttle amount (0.1 = slow, 1 = full speed).")
    
    CreateSlider(tankPanel, "Reverse Distance", "nai_npc_driver_reverse_distance", 100, 800, 0)
    CreateHelpText(tankPanel, "Distance at which to reverse away from enemies.")
    
    CreateSpacer(tankPanel, 10)
    CreateSubHeader(tankPanel, "Turret Control (Experimental)")
    
    CreateCheckbox(tankPanel, "Enable Turret Control", "nai_npc_turret_enabled")
    CreateHelpText(tankPanel, "Allow NPCs to control turrets on LVS vehicles.")
    
    CreateSlider(tankPanel, "Target Range", "nai_npc_turret_range", 500, 10000, 0)
    CreateSlider(tankPanel, "Accuracy", "nai_npc_turret_accuracy", 0, 1, 2)
    CreateSlider(tankPanel, "Reaction Time", "nai_npc_turret_reaction_time", 0, 3, 2)
    CreateSlider(tankPanel, "Fire Delay", "nai_npc_turret_fire_delay", 0.05, 1, 2)
    CreateSlider(tankPanel, "Aim Speed", "nai_npc_turret_aim_speed", 1, 20, 1)
    
    CreateCheckbox(tankPanel, "Lead Targets", "nai_npc_turret_lead_targets")
    CreateCheckbox(tankPanel, "Allow Friendly Fire", "nai_npc_turret_friendly_fire")
    
    -- HUD Tab
    local hudPanel = CreateContentPanel()
    hudPanel.SearchPanelName = "HUD"
    local hudBtn = CreateNavButton("HUD", "icon16/eye.png")
    hudPanel.SearchNavButton = hudBtn
    hudBtn.DoClick = function() SwitchToPanel(hudPanel, hudBtn) end
    
    CreateSectionHeader(hudPanel, "HUD Display")
    
    CreateCheckbox(hudPanel, "Enable Passenger HUD", "nai_npc_hud_enabled")
    CreateHelpText(hudPanel, "Shows passenger status (emotions, alertness) on screen while driving.")
    
    CreateCheckbox(hudPanel, "Only Show When In Vehicle", "nai_npc_hud_only_vehicle")
    CreateCheckbox(hudPanel, "Show Calm Passengers", "nai_npc_hud_show_calm")
    CreateCheckbox(hudPanel, "Show Context Hints", "nai_npc_hud_hints")
    CreateCheckbox(hudPanel, "Show Target Debug", "nai_npc_hud_target_debug")
    CreateCheckbox(hudPanel, "Play Success/Fail Cues", "nai_npc_client_cues")
    CreateHelpText(hudPanel, "When disabled, only shows passengers with non-calm status.")
    
    CreateSpacer(hudPanel, 10)
    CreateSectionHeader(hudPanel, "HUD Position & Style")
    
    -- Position dropdown
    local posLabel = vgui.Create("DLabel", hudPanel)
    posLabel:SetText("HUD Position")
    posLabel:SetFont("NaiFont_Normal")
    posLabel:SetTextColor(Theme.text)
    posLabel:Dock(TOP)
    posLabel:DockMargin(10, 8, 10, 2)
    
    local posCombo = vgui.Create("DComboBox", hudPanel)
    posCombo.SearchLabel = "HUD Position"
    posCombo.SearchConVar = "nai_npc_hud_position"
    posCombo:Dock(TOP)
    posCombo:DockMargin(10, 0, 10, 5)
    posCombo:SetTall(28)
    posCombo:SetFont("NaiFont_Normal")
    posCombo:SetTextColor(Theme.text)
    posCombo:AddChoice("Top Left", 0)
    posCombo:AddChoice("Top Right", 1)
    posCombo:AddChoice("Bottom Left", 2)
    posCombo:AddChoice("Bottom Right", 3)
    posCombo.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
        if self:IsMenuOpen() then
            surface.SetDrawColor(Theme.accent)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
    end
    local currentPos = GetConVar("nai_npc_hud_position"):GetInt()
    local posNames = {[0] = "Top Left", [1] = "Top Right", [2] = "Bottom Left", [3] = "Bottom Right"}
    posCombo:SetValue(posNames[currentPos] or "Top Right")
    posCombo.OnSelect = function(self, index, value, data)
        RunConsoleCommand("nai_npc_hud_position", tostring(data))
    end
    
    CreateSlider(hudPanel, "HUD Scale", "nai_npc_hud_scale", 0.5, 2, 2)
    CreateSlider(hudPanel, "HUD Opacity", "nai_npc_hud_opacity", 0.3, 1, 2)
    
    CreateSpacer(hudPanel, 10)
    CreateSectionHeader(hudPanel, "Emotion Thresholds")
    CreateHelpText(hudPanel, "When emotion levels exceed these thresholds, passengers show that status in the HUD.")
    
    CreateSlider(hudPanel, "Alert Threshold", "nai_npc_hud_alert_threshold", 0.1, 1, 2)
    CreateHelpText(hudPanel, "Alert level needed to show 'ALERT' status (threat detected).")
    
    CreateSlider(hudPanel, "Fear Threshold", "nai_npc_hud_fear_threshold", 0.1, 1, 2)
    CreateHelpText(hudPanel, "Fear level needed to show 'SCARED' status (dangerous driving).")
    
    CreateSlider(hudPanel, "Drowsy Threshold", "nai_npc_hud_drowsy_threshold", 0.3, 1, 2)
    CreateHelpText(hudPanel, "Calm time ratio needed to show 'DROWSY' status (long calm ride).")
    
    CreateSpacer(hudPanel, 15)
    CreateSectionHeader(hudPanel, "Emotion Actions")
    CreateHelpText(hudPanel, "Choose what action passengers take when experiencing each emotional state.")
    
    -- Action choices table
    local actionChoices = {
        {name = "Do Nothing", value = 0},
        {name = "Exit Vehicle", value = 1},
        {name = "Play Sound", value = 2},
        {name = "Duck / Crouch", value = 3},
        {name = "Look Around", value = 4},
        {name = "Cover Face", value = 5},
        {name = "Fall Asleep", value = 6}
    }
    
    -- Helper function to create action dropdown
    local function CreateActionDropdown(parent, label, convar)
        local container = vgui.Create("DPanel", parent)
        container.SearchLabel = label
        container.SearchConVar = convar
        container:Dock(TOP)
        container:DockMargin(10, 8, 10, 0)
        container:SetTall(28)
        container.Paint = function() end
        
        local lbl = vgui.Create("DLabel", container)
        lbl:SetText(label)
        lbl:SetFont("NaiFont_Normal")
        lbl:SetTextColor(Theme.text)
        lbl:Dock(LEFT)
        lbl:SetWide(150)
        
        local combo = vgui.Create("DComboBox", container)
        combo:Dock(FILL)
        combo:SetFont("NaiFont_Normal")
        combo:SetTextColor(Theme.text)
        combo.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
            if self:IsMenuOpen() then
                surface.SetDrawColor(Theme.accent)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
        end
        
        for _, choice in ipairs(actionChoices) do
            combo:AddChoice(choice.name, choice.value)
        end
        
        local cv = GetConVar(convar)
        local currentVal = cv and cv:GetInt() or 0
        for _, choice in ipairs(actionChoices) do
            if choice.value == currentVal then
                combo:SetValue(choice.name)
                break
            end
        end
        
        combo.OnSelect = function(self, index, value, data)
            RunConsoleCommand(convar, tostring(data))
        end
        
        return container
    end
    
    CreateActionDropdown(hudPanel, "If Calm:", "nai_npc_action_calm")
    CreateActionDropdown(hudPanel, "If Alert:", "nai_npc_action_alert")
    CreateActionDropdown(hudPanel, "If Scared:", "nai_npc_action_scared")
    CreateActionDropdown(hudPanel, "If Drowsy:", "nai_npc_action_drowsy")
    
    CreateSpacer(hudPanel, 5)
    CreateHelpText(hudPanel, "Note: Some actions may not be visible depending on NPC model support.")
    
    -- Keybinds Tab
    local keybindsPanel = CreateContentPanel()
    keybindsPanel.SearchPanelName = "Keybinds"
    local keybindsBtn = CreateNavButton("Keybinds", "icon16/keyboard.png")
    keybindsPanel.SearchNavButton = keybindsBtn
    keybindsBtn.DoClick = function() SwitchToPanel(keybindsPanel, keybindsBtn) end
    local keybindButtons = {}
    
    -- Helper function to create keybind button
    local function CreateKeybindButton(parent, label, convar, description)
        local container = vgui.Create("DPanel", parent)
        container.SearchLabel = label
        container.SearchDescription = description
        container.SearchConVar = convar
        container:Dock(TOP)
        container:DockMargin(10, 5, 10, 0)
        container:SetTall(50)
        container.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
        end
        
        local lbl = vgui.Create("DLabel", container)
        lbl:SetText(label)
        lbl:SetFont("NaiFont_Bold")
        lbl:SetTextColor(Theme.text)
        lbl:SetPos(10, 8)
        lbl:SizeToContents()
        
        local desc = vgui.Create("DLabel", container)
        desc:SetText(description)
        desc:SetFont("NaiFont_Small")
        desc:SetTextColor(Theme.textDim)
        desc:SetPos(10, 26)
        desc:SizeToContents()
        
        local btn = vgui.Create("DButton", container)
        btn:SetFont("NaiFont_Normal")
        btn:SetTextColor(TransparentColor)
        btn:SetSize(120, 35)
        btn.isBinding = false
        btn.hoverAnim = 0
        btn.pressAnim = 0
        
        -- Load saved keybind
        local cvar = GetConVar(convar)
        if cvar then
            local savedKey = cvar:GetInt()
            if savedKey > 0 then
                btn:SetText(input.GetKeyName(savedKey) or "Not Bound")
            else
                btn:SetText("Not Bound")
            end
        else
            btn:SetText("Not Bound")
        end
        
        btn.Paint = function(self, w, h)
            AnimateButtonVisualState(self, 8, 10, 18, 12)

            local pushOffset = GetButtonPushOffset(self, self.isBinding and 0 or 2)
            local col = Color(60, 60, 70)
            if self.isBinding then
                col = Theme.accentActive
            else
                col = LerpColor(self.hoverAnim, Color(60, 60, 70), Theme.accent)
                col = LerpColor(self.pressAnim, col, Color(50, 50, 60))
                DrawClippedBlur(self, 0, pushOffset, w, h, 1.8 + (self.hoverAnim * 1.1) + (self.pressAnim * 1.8), 1, 36 + (self.pressAnim * 28))
            end
            draw.RoundedBox(4, 0, pushOffset, w, h, WithAlpha(col, self.isBinding and 228 or 214))
            draw.SimpleText(self:GetText(), "NaiFont_Normal", w / 2, (h / 2) + pushOffset, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        btn.DoClick = function()
            if btn.isBinding then return end
            btn.isBinding = true
            btn:SetText("Press a key...")
            btn:RequestFocus()
        end
        
        btn.OnKeyCodePressed = function(self, key)
            if not self.isBinding then return end
            
            -- Ignore mouse buttons and escape
            if key == KEY_ESCAPE or key == MOUSE_LEFT or key == MOUSE_RIGHT or key == MOUSE_MIDDLE then
                self.isBinding = false
                -- Restore previous binding
                local cvar = GetConVar(convar)
                if cvar then
                    local savedKey = cvar:GetInt()
                    if savedKey > 0 then
                        self:SetText(input.GetKeyName(savedKey) or "Not Bound")
                    else
                        self:SetText("Not Bound")
                    end
                else
                    self:SetText("Not Bound")
                end
                return
            end
            
            -- Save the keybind
            RunConsoleCommand(convar, tostring(key))
            self:SetText(input.GetKeyName(key) or "Key " .. key)
            self.isBinding = false
        end
        
        -- Right click to unbind
        btn.DoRightClick = function()
            RunConsoleCommand(convar, "0")
            btn:SetText("Not Bound")
        end
        
        -- Align button to right side after container is sized
        container.PerformLayout = function(self, w, h)
            btn:SetPos(w - 130, 8)
        end

        keybindButtons[convar] = btn
        
        return container
    end
    
    CreateSectionHeader(keybindsPanel, "Action Keybinds")
    CreateHelpText(keybindsPanel, "Set custom keybinds for NPC passenger actions. Click a button and press a key to bind.")
    
    local keybindConvars = {
        {name = "Attach Nearest NPC", cvar = "nai_npc_key_attach", desc = "Attach the nearest friendly NPC to your vehicle"},
        {name = "Detach All Passengers", cvar = "nai_npc_key_detach_all", desc = "Remove all NPCs from your vehicle"},
        {name = "Toggle Auto-Join", cvar = "nai_npc_key_toggle_autojoin", desc = "Enable/disable automatic NPC boarding"},
        {name = "Open Settings Menu", cvar = "nai_npc_key_menu", desc = "Open the Better NPC Passengers settings panel"},
        {name = "Quick Attach Mode", cvar = "nai_npc_key_quick_attach", desc = "Hold to quickly attach NPCs you're looking at"},
    }
    
    for _, keybind in ipairs(keybindConvars) do
        CreateKeybindButton(keybindsPanel, keybind.name, keybind.cvar, keybind.desc)
    end
    
    CreateSpacer(keybindsPanel, 10)
    CreateSectionHeader(keybindsPanel, "Vehicle Control")
    
    local vehicleKeybinds = {
        {name = "NPCs Exit Vehicle", cvar = "nai_npc_key_exit_all", desc = "Command all passengers to exit the vehicle"},
        {name = "NPCs Hold Fire", cvar = "nai_npc_key_hold_fire", desc = "Tell gunner NPCs to stop firing"},
        {name = "NPCs Open Fire", cvar = "nai_npc_key_open_fire", desc = "Tell gunner NPCs to engage targets"},
        {name = "Cycle Passenger View", cvar = "nai_npc_key_cycle_view", desc = "Cycle camera through passengers"},
    }
    
    for _, keybind in ipairs(vehicleKeybinds) do
        CreateKeybindButton(keybindsPanel, keybind.name, keybind.cvar, keybind.desc)
    end
    
    CreateSpacer(keybindsPanel, 10)
    CreateSectionHeader(keybindsPanel, "Debug Controls")
    CreateHelpText(keybindsPanel, "Debug keybinds only work when Debug Mode is enabled.")
    
    local debugKeybinds = {
        {name = "Test Random Gesture", cvar = "nai_npc_key_test_gesture", desc = "Play a random gesture on nearest passenger"},
        {name = "Reset All NPCs", cvar = "nai_npc_key_reset_all", desc = "Reset animation states for all passengers"},
        {name = "Toggle Debug HUD", cvar = "nai_npc_key_debug_hud", desc = "Show debug information overlay"},
    }
    
    for _, keybind in ipairs(debugKeybinds) do
        CreateKeybindButton(keybindsPanel, keybind.name, keybind.cvar, keybind.desc)
    end

    CreateSpacer(keybindsPanel, 8)
    CreateButton(keybindsPanel, "Apply Recommended Keybinds", function()
        local recommendedKeys = {
            nai_npc_key_attach = KEY_G,
            nai_npc_key_detach_all = KEY_J,
            nai_npc_key_toggle_autojoin = KEY_H,
            nai_npc_key_menu = KEY_F6,
            nai_npc_key_exit_all = KEY_Y,
            nai_npc_key_cycle_view = KEY_V,
        }

        for convar, keyCode in pairs(recommendedKeys) do
            RunConsoleCommand(convar, tostring(keyCode))
            local button = keybindButtons[convar]
            if IsValid(button) then
                button.isBinding = false
                button:SetText(input.GetKeyName(keyCode) or ("Key " .. keyCode))
            end
        end

        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "Recommended keybinds applied.")
    end)

    CreateSpacer(keybindsPanel, 4)
    CreateButton(keybindsPanel, "Clear All Keybinds", function()
        for convar, button in pairs(keybindButtons) do
            RunConsoleCommand(convar, "0")
            if IsValid(button) then
                button.isBinding = false
                button:SetText("Not Bound")
            end
        end

        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "All keybinds cleared.")
    end)
    
    CreateSpacer(keybindsPanel, 10)
    local infoLabel = vgui.Create("DLabel", keybindsPanel)
    infoLabel:SetText("Tip: Right-click a keybind to unbind it. Press ESC while binding to cancel.")
    infoLabel:SetFont("NaiFont_Small")
    infoLabel:SetTextColor(Color(150, 150, 165))
    infoLabel:Dock(TOP)
    infoLabel:DockMargin(10, 5, 10, 10)
    infoLabel:SetWrap(true)
    infoLabel:SetAutoStretchVertical(true)
    
    -- Debugging Tab
    local debugPanel = CreateContentPanel()
    debugPanel.SearchPanelName = "Debugging"
    local debugBtn = CreateNavButton("Debugging", "icon16/bug.png")
    debugPanel.SearchNavButton = debugBtn
    debugBtn.DoClick = function() SwitchToPanel(debugPanel, debugBtn) end
    
    CreateSectionHeader(debugPanel, "Debug Tools")
    CreateHelpText(debugPanel, "Advanced debugging tools for testing NPC behavior. Enable Debug Mode in settings first.")
    
    CreateSpacer(debugPanel, 5)
    
    CreateCheckbox(debugPanel, "Enable Debug Mode", "nai_npc_debug_mode")
    CreateHelpText(debugPanel, "Shows debug test buttons and enables debug commands.")
    
    CreateSpacer(debugPanel, 15)
    CreateSectionHeader(debugPanel, "Passenger Status Control")
    CreateHelpText(debugPanel, "Manually set passenger status for testing. Click 'Refresh List' to see current passengers.")
    
    local passengerListPanel = vgui.Create("DScrollPanel", debugPanel)
    passengerListPanel:Dock(TOP)
    passengerListPanel:SetTall(400)
    passengerListPanel:DockMargin(5, 5, 5, 5)
    StyleScrollbar(passengerListPanel:GetVBar())
    passengerListPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
    end
    
    local function RefreshPassengerList()
        passengerListPanel:Clear()
        
        -- Request passenger list from server
        local passengers = {}
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNPCPassenger", false) then
                table.insert(passengers, ent)
            end
        end
        
        if #passengers == 0 then
            local noPassengers = vgui.Create("DLabel", passengerListPanel)
            noPassengers:SetText("No passengers found. NPCs must be in a vehicle.")
            noPassengers:SetFont("NaiFont_Normal")
            noPassengers:SetTextColor(Theme.textDim)
            noPassengers:Dock(TOP)
            noPassengers:DockMargin(10, 10, 10, 10)
            noPassengers:SetWrap(true)
            noPassengers:SetAutoStretchVertical(true)
            return
        end
        
        for _, npc in ipairs(passengers) do
            if not IsValid(npc) then continue end
            
            local npcPanel = vgui.Create("DPanel", passengerListPanel)
            npcPanel:Dock(TOP)
            npcPanel:SetTall(90)
            npcPanel:DockMargin(8, 4, 8, 4)
            npcPanel.Paint = function(self, w, h)
                if not IsValid(npc) then return end
                
                draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
                
                -- NPC info
                local npcName = npc:GetClass() .. " #" .. npc:EntIndex()
                draw.SimpleText(npcName, "NaiFont_Bold", 10, 10, Theme.textBright)
                
                local vehicle = npc:GetParent()
                if IsValid(vehicle) then
                    draw.SimpleText("Vehicle: " .. vehicle:GetClass(), "NaiFont_Small", 10, 30, Theme.textDim)
                end
            end
            
            -- Status buttons
            local statusButtons = {
                {name = "Calm", status = "calm", col = Color(100, 200, 100)},
                {name = "Alert", status = "alert", col = Color(255, 200, 100)},
                {name = "Scared", status = "scared", col = Color(255, 100, 100)},
                {name = "Drowsy", status = "drowsy", col = Color(150, 150, 200)},
                {name = "Dead", status = "dead", col = Color(80, 80, 90)},
            }
            
            local xPos = 10
            for _, btnData in ipairs(statusButtons) do
                local statusBtn = vgui.Create("DButton", npcPanel)
                statusBtn:SetPos(xPos, 55)
                statusBtn:SetSize(90, 28)
                statusBtn:SetText(btnData.name)
                statusBtn:SetFont("NaiFont_Normal")
                statusBtn:SetTextColor(Theme.textBright)
                statusBtn.Paint = function(self, w, h)
                    local col = btnData.col
                    if self:IsHovered() then
                        col = Color(math.min(col.r + 30, 255), math.min(col.g + 30, 255), math.min(col.b + 30, 255))
                    end
                    if self:IsDown() then
                        col = Color(math.max(col.r - 30, 0), math.max(col.g - 30, 0), math.max(col.b - 30, 0))
                    if not IsValid(npc) then return end
                    
                    end
                    draw.RoundedBox(4, 0, 0, w, h, col)
                end
                statusBtn.DoClick = function()
                    net.Start("NPCPassengers_SetStatus")
                    net.WriteInt(npc:EntIndex(), 32)
                    net.WriteString(btnData.status)
                    net.SendToServer()
                end
                
                xPos = xPos + 95
            end
        end
    end
    
    local refreshBtn = CreateButton(debugPanel, "Refresh Passenger List", RefreshPassengerList)
    
    CreateSpacer(debugPanel, 15)
    CreateSectionHeader(debugPanel, "Quick Test Buttons")
    
    CreateButton(debugPanel, "Test Flinch Gesture", function()
        net.Start("NPCPassengers_DebugTest")
        net.WriteString("flinch")
        net.SendToServer()
    end)
    
    CreateButton(debugPanel, "Test Random Gesture", function()
        net.Start("NPCPassengers_DebugTest")
        net.WriteString("gesture")
        net.SendToServer()
    end)
    
    CreateButton(debugPanel, "Reset All States", function()
        net.Start("NPCPassengers_DebugTest")
        net.WriteString("reset")
        net.SendToServer()
    end)
    
    -- NPC Driver Tab
    local driverPanel = CreateContentPanel()
    driverPanel.SearchPanelName = "NPC Driver"
    local driverBtn = CreateNavButton("NPC Driver", "icon16/car.png")
    driverPanel.SearchNavButton = driverBtn
    driverBtn.DoClick = function() SwitchToPanel(driverPanel, driverBtn) end
    
    CreateSectionHeader(driverPanel, "NPC Driver System")
    
    -- Work In Progress Panel
    local wipPanel = vgui.Create("DPanel", driverPanel)
    wipPanel:SetTall(200)
    wipPanel:Dock(TOP)
    wipPanel:DockMargin(10, 10, 10, 10)
    wipPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Theme.bgDark)
        
        -- Rotating Icon
        local angle = (CurTime() * 60) % 360
        surface.SetDrawColor(Theme.accent)
        surface.SetMaterial(Material("icon16/hourglass.png"))
        surface.DrawTexturedRectRotated(w / 2, 62, 64, 64, angle)
        
        draw.SimpleText("Work In Progress", "NaiFont_Title", w/2, 110, Theme.textBright, TEXT_ALIGN_CENTER)
        draw.SimpleText("This feature is currently under development", "NaiFont_Normal", w/2, 140, Theme.textDim, TEXT_ALIGN_CENTER)
        draw.SimpleText("Check back in a future update!", "NaiFont_Normal", w/2, 165, Theme.textDim, TEXT_ALIGN_CENTER)
    end
    
    -- Interface Tab
    local interfacePanel = CreateContentPanel()
    interfacePanel.SearchPanelName = "Interface"
    local interfaceBtn = CreateNavButton("Interface", "icon16/application_view_tile.png")
    interfacePanel.SearchNavButton = interfaceBtn
    interfaceBtn.DoClick = function() SwitchToPanel(interfacePanel, interfaceBtn) end
    
    CreateSectionHeader(interfacePanel, "UI Sound Settings")
    CreateHelpText(interfacePanel, "Configure sound effects for buttons, checkboxes, and other UI elements")
    
    CreateCheckbox(interfacePanel, "Enable UI Sounds", "nai_npc_ui_sounds_enabled")
    CreateHelpText(interfacePanel, "Master switch for all UI sound effects")
    
    CreateSlider(interfacePanel, "UI Sounds Volume", "nai_npc_ui_sounds_volume", 0, 2, 1)
    CreateHelpText(interfacePanel, "Volume multiplier for UI sounds (1.0 = normal, 2.0 = double)")
    
    CreateCheckbox(interfacePanel, "Button Hover Sounds", "nai_npc_ui_hover_enabled")
    CreateHelpText(interfacePanel, "Play sound when hovering over buttons")
    
    CreateCheckbox(interfacePanel, "Button Click Sounds", "nai_npc_ui_click_enabled")
    CreateHelpText(interfacePanel, "Play sound when clicking buttons and checkboxes")
    
    CreateSpacer(interfacePanel, 10)
    CreateSectionHeader(interfacePanel, "Context Menu Options")
    CreateHelpText(interfacePanel, "Choose which options appear when right-clicking NPCs")
    
    CreateCheckbox(interfacePanel, "Show 'Make Passenger'", "nai_npc_context_make_passenger")
    CreateHelpText(interfacePanel, "Add NPC as passenger to your current vehicle")
    
    CreateCheckbox(interfacePanel, "Show 'Make Passenger For Vehicle'", "nai_npc_context_make_passenger_vehicle")
    CreateHelpText(interfacePanel, "Add NPC to a specific vehicle (click NPC, then vehicle)")
    
    CreateCheckbox(interfacePanel, "Show 'Detach Passenger'", "nai_npc_context_detach")
    CreateHelpText(interfacePanel, "Remove NPC from vehicle")

    CreateButton(interfacePanel, "Enable All Context Menu Options", function()
        RunConsoleCommand("nai_npc_context_make_passenger", "1")
        RunConsoleCommand("nai_npc_context_make_passenger_vehicle", "1")
        RunConsoleCommand("nai_npc_context_detach", "1")
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "All context menu options enabled.")
    end)

    CreateButton(interfacePanel, "Hide All Context Menu Options", function()
        RunConsoleCommand("nai_npc_context_make_passenger", "0")
        RunConsoleCommand("nai_npc_context_make_passenger_vehicle", "0")
        RunConsoleCommand("nai_npc_context_detach", "0")
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "All context menu options hidden.")
    end)
    
    CreateSpacer(interfacePanel, 10)
    CreateSectionHeader(interfacePanel, "Settings Panel Preferences")
    
    CreateCheckbox(interfacePanel, "Show Welcome Screen on Updates", "nai_npc_ui_show_welcome")
    CreateHelpText(interfacePanel, "Display welcome panel when addon is updated to a new version")

    local _, defaultFontCheckbox = CreateCheckbox(interfacePanel, "Use Default Font Instead of Metropolis", "nai_npc_ui_use_default_font")
    CreateHelpText(interfacePanel, "Switch the UI to Garry's Mod default fonts if you prefer cleaner fallback rendering.")

    CreateCheckbox(interfacePanel, "Enable April Fools Chaos", "nai_npc_april_fools")
    CreateHelpText(interfacePanel, "Master switch for the LSD UI, cursed face poser, and passenger explosion gag.")

    local defaultFontOnChange = defaultFontCheckbox.OnChange
    defaultFontCheckbox.OnChange = function(self, val)
        if defaultFontOnChange then
            defaultFontOnChange(self, val)
        end

        CreateNaiFonts()

        if IsValid(settingsFrame) then
            settingsFrame:InvalidateLayout(true)
        end
    end
    
    local _, widthSlider = CreateSlider(interfacePanel, "Panel Width", "nai_npc_ui_panel_width", 800, 1400, 0)
    CreateHelpText(interfacePanel, "Width of the settings panel")
    widthSlider.OnValueChanged = function(_, val)
        if IsValid(settingsFrame) then
            settingsFrame:SetSize(math.floor(val), settingsFrame:GetTall())
            settingsFrame:InvalidateLayout(true)
        end
    end

    local _, heightSlider = CreateSlider(interfacePanel, "Panel Height", "nai_npc_ui_panel_height", 600, 900, 0)
    CreateHelpText(interfacePanel, "Height of the settings panel")
    heightSlider.OnValueChanged = function(_, val)
        if IsValid(settingsFrame) then
            settingsFrame:SetSize(settingsFrame:GetWide(), math.floor(val))
            settingsFrame:InvalidateLayout(true)
        end
    end

    local function ApplyPanelSizePreset(width, height)
        RunConsoleCommand("nai_npc_ui_panel_width", tostring(width))
        RunConsoleCommand("nai_npc_ui_panel_height", tostring(height))

        if IsValid(widthSlider) then
            widthSlider:SetValue(width)
        end

        if IsValid(heightSlider) then
            heightSlider:SetValue(height)
        end

        if IsValid(settingsFrame) then
            settingsFrame:SetSize(width, height)
            settingsFrame:Center()
            settingsFrame:InvalidateLayout(true)
        end
    end

    CreateButton(interfacePanel, "Set Compact Panel Size", function()
        ApplyPanelSizePreset(900, 650)
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "Panel size set to compact.")
    end)

    CreateButton(interfacePanel, "Set Default Panel Size", function()
        ApplyPanelSizePreset(950, 700)
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "Panel size set to default.")
    end)

    CreateButton(interfacePanel, "Set Large Panel Size", function()
        ApplyPanelSizePreset(1200, 800)
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "Panel size set to large.")
    end)

    CreateButton(interfacePanel, "Center Panel Now", function()
        if IsValid(settingsFrame) then
            settingsFrame:Center()
            settingsFrame:InvalidateLayout(true)
            chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "Panel centered.")
        end
    end)
    
    CreateCheckbox(interfacePanel, "Enable UI Animations", "nai_npc_ui_animations")
    CreateHelpText(interfacePanel, "Smooth transitions and hover effects (may impact performance)")
    
    CreateCheckbox(interfacePanel, "Show Tooltips", "nai_npc_ui_tooltips")
    CreateHelpText(interfacePanel, "Display helpful tooltips when hovering over settings")
    
    CreateSpacer(interfacePanel, 10)
    CreateSectionHeader(interfacePanel, "Performance & Technical")
    
    CreateButton(interfacePanel, "Reset All UI Settings to Default", function()
        RunConsoleCommand("nai_npc_ui_sounds_enabled", "1")
        RunConsoleCommand("nai_npc_ui_sounds_volume", "1")
        RunConsoleCommand("nai_npc_ui_hover_enabled", "1")
        RunConsoleCommand("nai_npc_ui_click_enabled", "1")
        RunConsoleCommand("nai_npc_context_make_passenger", "1")
        RunConsoleCommand("nai_npc_context_make_passenger_vehicle", "1")
        RunConsoleCommand("nai_npc_context_detach", "1")
        RunConsoleCommand("nai_npc_ui_show_welcome", "1")
        RunConsoleCommand("nai_npc_ui_panel_width", "950")
        RunConsoleCommand("nai_npc_ui_panel_height", "700")
        RunConsoleCommand("nai_npc_ui_use_default_font", "0")
        RunConsoleCommand("nai_npc_ui_animations", "1")
        RunConsoleCommand("nai_npc_ui_tooltips", "1")

        if IsValid(widthSlider) then
            widthSlider:SetValue(950)
        end

        if IsValid(heightSlider) then
            heightSlider:SetValue(700)
        end

        if IsValid(settingsFrame) then
            settingsFrame:SetSize(950, 700)
            settingsFrame:Center()
            settingsFrame:InvalidateLayout(true)
        end

        CreateNaiFonts()
        chat.AddText(Theme.success, ADDON_CHAT_PREFIX, Theme.text, "All UI settings reset to defaults!")
    end)
    
    CreateSpacer(interfacePanel, 10)
    
    local infoPanel = vgui.Create("DPanel", interfacePanel)
    infoPanel:SetTall(100)
    infoPanel:Dock(TOP)
    infoPanel:DockMargin(5, 0, 5, 5)
    infoPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
        
        surface.SetDrawColor(Theme.accent)
        surface.SetMaterial(Material("icon16/information.png"))
        surface.DrawTexturedRect(15, 15, 16, 16)
        
        draw.SimpleText("Interface Settings Info", "NaiFont_Bold", 38, 18, Theme.accent)
        
        local infoLines = {
            "These settings control the addon's user interface behavior",
            "Changes to panel size require closing and reopening the menu",
            "Disabling sounds or animations can improve performance on low-end systems"
        }
        
        local y = 45
        for _, line in ipairs(infoLines) do
            draw.SimpleText("- " .. line, "NaiFont_Small", 20, y, Theme.textDim)
            y = y + 16
        end
    end
    
    -- Simulate Tab
    local simulatePanel = CreateContentPanel()
    simulatePanel.SearchPanelName = "Simulate"
    local simulateBtn = CreateNavButton("Simulate", "icon16/wand.png")
    simulatePanel.SearchNavButton = simulateBtn
    simulateBtn.DoClick = function() SwitchToPanel(simulatePanel, simulateBtn) end
    
    CreateSectionHeader(simulatePanel, "Simulation System")
    
    -- Work In Progress Panel
    local wipPanel2 = vgui.Create("DPanel", simulatePanel)
    wipPanel2:SetTall(200)
    wipPanel2:Dock(TOP)
    wipPanel2:DockMargin(10, 10, 10, 10)
    wipPanel2.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Theme.bgDark)
        
        -- Rotating Icon
        local angle = (CurTime() * 60) % 360
        surface.SetDrawColor(Theme.accent)
        surface.SetMaterial(Material("icon16/hourglass.png"))
        surface.DrawTexturedRectRotated(w / 2, 62, 64, 64, angle)
        
        draw.SimpleText("Work In Progress", "NaiFont_Title", w/2, 110, Theme.textBright, TEXT_ALIGN_CENTER)
        draw.SimpleText("This feature is currently under development", "NaiFont_Normal", w/2, 140, Theme.textDim, TEXT_ALIGN_CENTER)
        draw.SimpleText("Check back in a future update!", "NaiFont_Normal", w/2, 165, Theme.textDim, TEXT_ALIGN_CENTER)
    end
    
    -- Modules Tab
    local modulesPanel = CreateContentPanel()
    modulesPanel.SearchPanelName = "Modules"
    local modulesBtn = CreateNavButton("Modules", "icon16/plugin.png")
    modulesPanel.SearchNavButton = modulesBtn
    modulesBtn.DoClick = function() SwitchToPanel(modulesPanel, modulesBtn) end
    
    CreateSectionHeader(modulesPanel, "Modules System")
    
    -- Work In Progress Panel
    local wipPanel3 = vgui.Create("DPanel", modulesPanel)
    wipPanel3:SetTall(200)
    wipPanel3:Dock(TOP)
    wipPanel3:DockMargin(10, 10, 10, 10)
    wipPanel3.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Theme.bgDark)
        
        -- Rotating Icon
        local angle = (CurTime() * 60) % 360
        surface.SetDrawColor(Theme.accent)
        surface.SetMaterial(Material("icon16/hourglass.png"))
        surface.DrawTexturedRectRotated(w / 2, 62, 64, 64, angle)
        
        draw.SimpleText("Work In Progress", "NaiFont_Title", w/2, 110, Theme.textBright, TEXT_ALIGN_CENTER)
        draw.SimpleText("This feature is currently under development", "NaiFont_Normal", w/2, 140, Theme.textDim, TEXT_ALIGN_CENTER)
        draw.SimpleText("Check back in a future update!", "NaiFont_Normal", w/2, 165, Theme.textDim, TEXT_ALIGN_CENTER)
    end
    
    -- Help Tab
    local helpPanel = CreateContentPanel()
    helpPanel.SearchPanelName = "Help"
    local helpBtn = CreateNavButton("Help", "icon16/help.png")
    helpPanel.SearchNavButton = helpBtn
    helpBtn.DoClick = function() SwitchToPanel(helpPanel, helpBtn) end
    
    CreateSectionHeader(helpPanel, "Frequently Asked Questions")
    CreateHelpText(helpPanel, "Quick answers to common questions and troubleshooting.")
    
    CreateSpacer(helpPanel, 5)
    
    -- Helper function to create expandable FAQ item
    local function CreateFAQ(parent, iconPath, question, answer)
        local isExpanded = false
        
        local container = vgui.Create("DPanel", parent)
        container:Dock(TOP)
        container:DockMargin(8, 3, 8, 0)
        container.Paint = function() end
        
        -- Header button
        local header = vgui.Create("DButton", container)
        header:Dock(TOP)
        header:SetTall(35)
        header:SetText("")
        header.Paint = function(self, w, h)
            local col = self:IsHovered() and Theme.bgLighter or Theme.bgDark
            draw.RoundedBox(6, 0, 0, w, h, col)
            
            -- Icon
            surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 255)
            surface.SetMaterial(Material(iconPath))
            surface.DrawTexturedRect(12, (h - 16) / 2, 16, 16)
            
            -- Question text
            draw.SimpleText(question, "NaiFont_Bold", 40, h/2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            
            -- Arrow indicator
            local arrow = isExpanded and "v" or ">" 
            draw.SimpleText(arrow, "NaiFont_Normal", w - 15, h/2, Theme.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Answer panel
        local answerPanel = vgui.Create("DPanel", container)
        answerPanel:Dock(TOP)
        answerPanel:DockMargin(0, 2, 0, 0)
        answerPanel:SetVisible(false)
        answerPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Theme.bgLighter)
        end
        
        local answerLabel = vgui.Create("DLabel", answerPanel)
        answerLabel:SetText(answer)
        answerLabel:SetFont("NaiFont_Normal")
        answerLabel:SetTextColor(Theme.textDim)
        answerLabel:SetWrap(true)
        answerLabel:SetAutoStretchVertical(true)
        answerLabel:Dock(FILL)
        answerLabel:DockMargin(15, 10, 15, 10)
        
        -- Toggle function
        header.DoClick = function()
            isExpanded = not isExpanded
            answerPanel:SetVisible(isExpanded)
            
            if isExpanded then
                -- Delay height calculation to next frame for proper wrapping
                timer.Simple(0, function()
                    if not IsValid(answerLabel) then return end
                    answerLabel:SetWide(answerPanel:GetWide() - 30) -- Account for margins
                    answerLabel:SizeToContentsY()
                    local labelHeight = answerLabel:GetTall()
                    answerPanel:SetTall(labelHeight + 20)
                    container:SetTall(37 + labelHeight + 20)
                    parent:InvalidateLayout(true)
                end)
            else
                answerPanel:SetTall(0)
                container:SetTall(35)
                parent:InvalidateLayout(true)
            end
        end
        
        container:SetTall(35)
        
        return container
    end
    
    -- FAQ Items
    CreateFAQ(helpPanel, "icon16/car.png", "How do I add NPCs to my vehicle?",
        "Right-click on a friendly NPC while near your vehicle. They'll automatically walk over and board. You can also enable Auto-Join in the settings to have NPCs automatically board when you enter a vehicle.")
    
    CreateFAQ(helpPanel, "icon16/cross.png", "How do I remove passengers from my vehicle?",
        "Right-click them again while they're in the vehicle, or use the 'Detach All' keybind (set in Keybinds tab). Dead passengers can be removed by holding R near them.")
    
    CreateFAQ(helpPanel, "icon16/error.png", "My NPCs are floating or clipping through the vehicle!",
        "Go to the Position tab and adjust the Height/Forward/Right offsets. Each vehicle model is different, so you may need to fine-tune these values. Use the debugging panel to test positions in real-time.")
    
    CreateFAQ(helpPanel, "icon16/sound_mute.png", "NPCs aren't making any sounds!",
        "Check the Behaviour tab and make sure 'Enable NPC Speech' is turned on. Also verify that Speech Volume is above 0. Some NPC models may not have voice lines available.")
    
    CreateFAQ(helpPanel, "icon16/group.png", "Can I have multiple NPCs in one vehicle?",
        "Yes! Set the 'Passenger Limit' in General settings. The addon will distribute NPCs around the vehicle automatically. For specific seat positions, adjust offsets in the Position tab.")
    
    CreateFAQ(helpPanel, "icon16/user_go.png", "How does Auto-Join work?",
        "When enabled in the Auto-Join tab, nearby friendly NPCs will automatically board your vehicle when you enter it - just like squad mechanics in Half-Life 2. You can set the detection range and limit how many NPCs can auto-join.")
    
    CreateFAQ(helpPanel, "icon16/user_delete.png", "What happens when passengers die?",
        "Dead passengers will show a red glow effect and display a skull icon on the HUD. Get close to your vehicle and hold R to remove their bodies. The bodies will be ejected with physics.")
    
    CreateFAQ(helpPanel, "icon16/emoticon_smile.png", "What do the passenger statuses mean?",
        "CALM: Relaxed, no threats nearby\nALERT: Enemy detected, NPC is tracking threats\nSCARED: Dangerous driving (high speed, crashes)\nDROWSY: Long calm ride, NPC is getting sleepy\nDEAD: Health reached zero")
    
    CreateFAQ(helpPanel, "icon16/keyboard.png", "My keybinds aren't working!",
        "Go to the Keybinds tab and make sure you've actually set the keybinds (they're unbound by default). Click the button next to each action and press your desired key. Right-click to unbind.")
    
    CreateFAQ(helpPanel, "icon16/bug.png", "The addon isn't working at all / I'm getting errors!",
        "1. Make sure you're using friendly NPCs (Combine NPCs won't work)\n2. Check console for errors (press ~)\n3. Try resetting all settings with 'nai_npc_reset' in console\n4. Verify the addon is enabled in the Addons menu\n5. Make sure your vehicle has physics and isn't frozen")
    
    CreateFAQ(helpPanel, "icon16/lightbulb.png", "Can NPCs shoot from the vehicle?",
        "Not currently. NPCs will track enemies and react to threats, but won't fire weapons while seated. This feature may be added in future updates.")
    
    CreateFAQ(helpPanel, "icon16/stop.png", "How do I stop NPCs from auto-joining?",
        "Disable 'Enable Auto-Join' in the Auto-Join settings tab. You can also toggle it with a keybind (set in Keybinds tab).")
    
    CreateFAQ(helpPanel, "icon16/cog.png", "Where are the settings saved?",
        "All settings are saved as ConVars in your GMod config. They persist between sessions and are specific to your client.")
    
    CreateFAQ(helpPanel, "icon16/drive.png", "Does this work with all vehicles?",
        "It works with most vehicles that have physics. Tanks, APCs, cars, boats, etc. Some modded vehicles may require position adjustments.")
    
    CreateFAQ(helpPanel, "icon16/weather_lightning.png", "NPCs are acting weird after crashes!",
        "This is normal - they react with fear to dangerous driving. Lower the Fear Threshold in HUD settings if you want them less reactive.")
    
    CreateFAQ(helpPanel, "icon16/arrow_rotate_clockwise.png", "How do I reset just one setting?",
        "Use the console command for that specific setting. All commands start with 'nai_npc_'. Type 'find nai_npc' in console to see all available commands.")
    
    CreateFAQ(helpPanel, "icon16/server.png", "Does this work in multiplayer?",
        "Yes! The addon works on both singleplayer and multiplayer servers. Each player controls their own passengers.")
    
    CreateSpacer(helpPanel, 10)
    CreateSectionHeader(helpPanel, "Still Need Help?")
    
    local helpBox = vgui.Create("DPanel", helpPanel)
    helpBox:Dock(TOP)
    helpBox:DockMargin(8, 5, 8, 5)
    helpBox:SetTall(80)
    helpBox.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
        
        surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 255)
        surface.SetMaterial(Material("icon16/comment.png"))
        surface.DrawTexturedRect(15, 15, 16, 16)
        
        draw.SimpleText("Console Commands for Debugging:", "NaiFont_Bold", 40, 18, Theme.text)
        
        local y = 45
        draw.SimpleText("nai_npc_debug_mode 1", "NaiFont_Normal", 40, y, Theme.textDim)
        draw.SimpleText("- Enable debug mode to see detailed info", "NaiFont_Small", 220, y, Color(120, 120, 135))
    end
    
    -- About Tab
    local aboutPanel = CreateContentPanel()
    aboutPanel.SearchPanelName = "About"
    local aboutBtn = CreateNavButton("About", "icon16/information.png")
    aboutPanel.SearchNavButton = aboutBtn
    aboutBtn.DoClick = function() SwitchToPanel(aboutPanel, aboutBtn) end
    
    CreateSectionHeader(aboutPanel, "About " .. ADDON_DISPLAY_NAME .. " v" .. NPCPassengers.Version)
    
    local aboutText = vgui.Create("DPanel", aboutPanel)
    aboutText:SetTall(160)
    aboutText:Dock(TOP)
    aboutText:DockMargin(5, 5, 5, 5)
    aboutText.Paint = function(self, w, h)
        -- Gradient background
        draw.RoundedBox(8, 0, 0, w, h, Theme.bgDark)
        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(Theme.accentDark.r, Theme.accentDark.g, Theme.accentDark.b, 40)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, 0, w, h)
        
        -- Border
        surface.SetDrawColor(Theme.borderLight)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        
        local y = 20
        draw.SimpleText(ADDON_DISPLAY_NAME, "NaiFont_Title", w/2, y, Theme.accent, TEXT_ALIGN_CENTER)
        y = y + 32
        draw.SimpleText("Advanced passenger system with emotional AI and realistic physics", "NaiFont_Normal", w/2, y, Theme.text, TEXT_ALIGN_CENTER)
        y = y + 30
        
        -- Feature highlights
        local features = {
            "Status System: CALM / ALERT / SCARED / DROWSY / DEAD",
            "Performance: seat caching, throttled timers, optimized client hooks",
            "Vehicle filtering, boarding retry cooldown, squad-only auto-join"
        }
        
        for _, feature in ipairs(features) do
            draw.SimpleText(feature, "NaiFont_Small", w/2, y, Theme.textDim, TEXT_ALIGN_CENTER)
            y = y + 20
        end
    end
    
    CreateSpacer(aboutPanel, 10)
    CreateSectionHeader(aboutPanel, "Actions")
    
    CreateButton(aboutPanel, "Show Welcome Screen", function()
        settingsFrame:Close()
        timer.Simple(0.1, function() ShowWelcomePanel(true) end)
    end)

    CreateButton(aboutPanel, "Open GitHub Page", function()
        gui.OpenURL("https://github.com/Nai64/BetterNPCPassengers")
    end)
    
    CreateButton(aboutPanel, "Reset ALL Settings to Defaults", function()
        RunConsoleCommand("nai_npc_reset")
        settingsFrame:Close()
        timer.Simple(0.1, OpenSettingsPanel)
    end)
    
    -- Start with General panel active
    SwitchToPanel(generalPanel, generalBtn)
    timer.Simple(0, function()
        if IsValid(searchEntry) then
            FocusSearchEntry()
        end
    end)
end

concommand.Add("nai_passengers_menu", OpenSettingsPanel)

concommand.Add("nai_npc_reset", function()
    -- Delegate all ConVar resets to the server-side handler so that
    -- replicated ConVars are actually changed (clients cannot change them directly)
    RunConsoleCommand("nai_npc_server_reset")
end)

-- Spawn menu entry
hook.Add("PopulateToolMenu", "NPCPassengerOptions", function()
        spawnmenu.AddToolMenuOption("Utilities", ADDON_DISPLAY_NAME, "NPCPassengers", ADDON_DISPLAY_NAME, "", "", function(panel)
        panel:ClearControls()
        
        panel:Help(ADDON_DISPLAY_NAME .. " lets friendly NPCs ride in your vehicles!")
        panel:Help("")
        
        local openBtn = panel:Button("Open Settings Panel")
        openBtn.DoClick = function()
            OpenSettingsPanel()
        end
        
        panel:Help("")
        panel:Help("Or use console command: nai_passengers_menu")
    end)
end)

-- Q menu bar dropdown
hook.Add("PopulateMenuBar", "NPCPassengersMenuBar", function(menubar)
    local m = menubar:AddOrGetMenu(ADDON_DISPLAY_NAME)
    
    m:AddOption("Open Settings", function()
        OpenSettingsPanel()
    end):SetIcon("icon16/cog.png")
    
    m:AddSpacer()
    
    m:AddOption("Reset All Settings", function()
        RunConsoleCommand("nai_npc_reset")
    end):SetIcon("icon16/arrow_refresh.png")
end)

-- Right-click context menu options
properties.Add("nai_make_passenger", {
    MenuLabel = "Make Passenger",
    Order = 1500,
    MenuIcon = "icon16/car.png",

    Filter = function(self, ent, ply)
        if not GetConVar("nai_npc_context_make_passenger"):GetBool() then return false end
        if not IsValid(ent) then return false end
        if not ent:IsNPC() then return false end
        return true
    end,

    Action = function(self, ent)
        net.Start("NPCPassengers_MakePassenger")
            net.WriteEntity(ent)
        net.SendToServer()
    end
})

--[[ NPC DRIVER CONTEXT MENU (DISABLED)
properties.Add("nai_make_driver", {
    MenuLabel = "Make NPC Driver for This Vehicle",
    Order = 1501,
    MenuIcon = "icon16/car_go.png",

    Filter = function(self, ent, ply)
        if not IsValid(ent) then return false end
        if not ent:IsNPC() then return false end
        if not GetConVar("nai_npc_driver_enabled"):GetBool() then return false end
        return true
    end,

    Action = function(self, ent)
        net.Start("NPCPassengers_MakeDriver")
            net.WriteEntity(ent)
        net.SendToServer()
    end
})
--]]

properties.Add("nai_select_for_vehicle", {
    MenuLabel = "Make Passenger For Vehicle...",
    Order = 1502,
    MenuIcon = "icon16/car_add.png",

    Filter = function(self, ent, ply)
        if not GetConVar("nai_npc_context_make_passenger_vehicle"):GetBool() then return false end
        if not IsValid(ent) then return false end
        if not ent:IsNPC() then return false end
        return true
    end,

    Action = function(self, ent)
        selectedNPCForVehicle = ent
        selectionExpireTime = CurTime() + 30
        chat.AddText(Color(100, 200, 100), ADDON_CHAT_PREFIX, Color(255, 255, 255), "NPC selected! Now right-click on a vehicle and select 'Add Selected NPC'")
    end
})

properties.Add("nai_add_selected_to_vehicle", {
    MenuLabel = "Add Selected NPC Here",
    Order = 1503,
    MenuIcon = "icon16/user_add.png",

    Filter = function(self, ent, ply)
        if not IsValid(ent) then return false end
        if not IsValid(selectedNPCForVehicle) then return false end
        if CurTime() > selectionExpireTime then
            selectedNPCForVehicle = nil
            return false
        end
        if ent:IsVehicle() then return true end
        if ent.LVS or ent.IsLVS then return true end
        if ent.IsSimfphyscar then return true end
        if ent.IsGlideVehicle then return true end
        if ent.IsSligWolf or ent.sligwolf or ent.SligWolf then return true end
        local class = ent:GetClass() or ""
        if string.find(class, "lvs_") then return true end
        if string.find(class, "gmod_sent_vehicle") then return true end
        if string.find(class, "sligwolf_") then return true end
        if string.find(class, "sw_") then return true end
        return false
    end,

    Action = function(self, ent)
        if IsValid(selectedNPCForVehicle) then
            net.Start("NPCPassengers_MakePassengerForVehicle")
                net.WriteEntity(selectedNPCForVehicle)
                net.WriteEntity(ent)
            net.SendToServer()
            chat.AddText(Color(100, 200, 100), ADDON_CHAT_PREFIX, Color(255, 255, 255), "Adding NPC to vehicle...")
            selectedNPCForVehicle = nil
        end
    end
})

properties.Add("nai_cancel_selection", {
    MenuLabel = "Cancel NPC Selection",
    Order = 1503,
    MenuIcon = "icon16/cancel.png",

    Filter = function(self, ent, ply)
        if not IsValid(selectedNPCForVehicle) then return false end
        if CurTime() > selectionExpireTime then
            selectedNPCForVehicle = nil
            return false
        end
        return true
    end,

    Action = function(self, ent)
        selectedNPCForVehicle = nil
        chat.AddText(Color(255, 200, 100), ADDON_CHAT_PREFIX, Color(255, 255, 255), "NPC selection cancelled")
    end
})

properties.Add("nai_remove_passenger", {
    MenuLabel = "Remove Passenger",
    Order = 1504,
    MenuIcon = "icon16/car_delete.png",

    Filter = function(self, ent, ply)
        if not GetConVar("nai_npc_context_detach"):GetBool() then return false end
        if not IsValid(ent) then return false end
        if not ent:IsNPC() then return false end
        return true
    end,

    Action = function(self, ent)
        net.Start("NPCPassengers_RemovePassenger")
            net.WriteEntity(ent)
        net.SendToServer()
    end
})

properties.Add("nai_assign_seat", {
    MenuLabel = "Assign to Seat...",
    Order = 1505,
    MenuIcon = "icon16/car_go.png",

    Filter = function(self, ent, ply)
        if not GetConVar("nai_npc_context_detach"):GetBool() then return false end
        if not IsValid(ent) then return false end
        if not ent:IsNPC() then return false end
        if not ent:IsNPC() or ent:Health() <= 0 then return false end
        if not ply:InVehicle() then return false end
        return true
    end,

    Action = function(self, ent)
        local menu = DermaMenu()
        for i = 1, 8 do
            menu:AddOption("Seat " .. i, function()
                net.Start("NPCPassengers_AssignSeat")
                    net.WriteEntity(ent)
                    net.WriteUInt(i, 8)
                net.SendToServer()
            end)
        end
        menu:Open()
    end
})

-- F7 hotkey
hook.Add("PlayerButtonDown", "NPCPassengersQuickMenu", function(ply, button)
    if button == KEY_F7 and IsFirstTimePredicted() then
        OpenSettingsPanel()
    end
end)

-- C menu icon (top left corner)
list.Set("DesktopWindows", "NPCPassengersDesktop", {
    title = ADDON_DISPLAY_NAME,
    icon = "icon64/npc_passengers.png",
    init = function(icon, window)
        window:Remove() -- Close the default window
        OpenSettingsPanel()
    end
})
-- Startup welcome panel
local WELCOME_VERSION = "2.4" -- Change this when you want to show the popup again after updates

function ShowWelcomePanel(forceShow)
    local dontShow = cookie.GetString("nai_passengers_hide_welcome", "0")
    local lastVersion = cookie.GetString("nai_passengers_last_version", "")
    
    if not forceShow and dontShow == "1" and lastVersion == WELCOME_VERSION then return end
    
    local frame = vgui.Create("DFrame")
    frame:SetSize(620, 560)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(true)
    frame:MakePopup()
    frame:SetDeleteOnClose(true)
    
    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 4, 4, w, h, Color(0, 0, 0, 100))
        draw.RoundedBox(10, 0, 0, w, h, Theme.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 44, Theme.bgDark, true, true, false, false)
        draw.SimpleText(ADDON_DISPLAY_NAME, "NaiFont_Title", 15, 22, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("v" .. WELCOME_VERSION, "NaiFont_Small", w - 50, 22, Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    
    frame.btnClose:SetVisible(false)
    frame.btnMaxim:SetVisible(false)
    frame.btnMinim:SetVisible(false)
    
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetPos(frame:GetWide() - 40, 10)
    closeBtn:SetSize(26, 26)
    closeBtn:SetText("")
    closeBtn.Paint = function(self, w, h)
        local col = Theme.textDim
        if self:IsHovered() then col = Theme.error end
        draw.SimpleText("X", "NaiFont_Large", w/2, h/2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        frame:Close()
    end
    
    local content = vgui.Create("DScrollPanel", frame)
    content:SetPos(15, 54)
    content:SetSize(590, 440)
    content.Paint = function() end
    
    local sbar = content:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function(s, w, h) draw.RoundedBox(3, 0, 0, w, h, Theme.bgDark) end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(3, 0, 0, w, h, Theme.scrollbarGrip) end
    
    -- Hey there header
    local heyHeader = vgui.Create("DLabel", content)
    heyHeader:SetFont("NaiFont_Large")
    heyHeader:SetTextColor(Theme.textBright)
    heyHeader:SetText("Hey there!")
    heyHeader:Dock(TOP)
    heyHeader:DockMargin(0, 5, 0, 8)
    heyHeader:SizeToContents()
    
    local msg1 = vgui.Create("DLabel", content)
    msg1:SetFont("NaiFont_Normal")
    msg1:SetTextColor(Theme.text)
    msg1:SetText("Before complaining about the passenger sitting on top of vehicle,\nplease open the settings. You can do it, I believe in you.")
    msg1:SetWrap(true)
    msg1:SetAutoStretchVertical(true)
    msg1:Dock(TOP)
    msg1:DockMargin(0, 0, 0, 12)
    
    -- Settings button
    local settingsBtn = vgui.Create("DButton", content)
    settingsBtn:SetText("Open Settings")
    settingsBtn:SetFont("NaiFont_Medium")
    settingsBtn:SetTall(38)
    settingsBtn:Dock(TOP)
    settingsBtn:DockMargin(0, 0, 0, 15)
    settingsBtn:SetTextColor(TransparentColor)
    settingsBtn.hoverAnim = 0
    settingsBtn.pressAnim = 0
    settingsBtn.Paint = function(self, w, h)
        AnimateButtonVisualState(self, 5, 5, 18, 12)

        local pushOffset = GetButtonPushOffset(self, 2)
        local bgColor = LerpColor(self.hoverAnim, Theme.accent, Theme.accentHover)
        bgColor = LerpColor(self.pressAnim, bgColor, Theme.accentActive)
        DrawClippedBlur(self, 0, pushOffset, w, h, 2 + (self.hoverAnim * 1.2) + (self.pressAnim * 2), 1, 46 + (self.pressAnim * 34))
        draw.RoundedBox(6, 0, pushOffset, w, h, WithAlpha(bgColor, 220))
        draw.SimpleText(self:GetText(), "NaiFont_Medium", w / 2, (h / 2) + pushOffset, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    settingsBtn.DoClick = function()
        frame:Close()
        OpenSettingsPanel()
    end
    
    -- Divider
    local div1 = vgui.Create("DPanel", content)
    div1:SetTall(1)
    div1:Dock(TOP)
    div1:DockMargin(0, 5, 0, 15)
    div1.Paint = function(s, w, h)
        surface.SetDrawColor(Theme.border)
        surface.DrawRect(0, 0, w, h)
    end
    
    local msg2 = vgui.Create("DLabel", content)
    msg2:SetFont("NaiFont_Normal")
    msg2:SetTextColor(Theme.textDim)
    msg2:SetText("This addon is still far from being PERFECT, please do not hesitate to\nreport bugs and suggest new features. I read all of your comments!")
    msg2:SetWrap(true)
    msg2:SetAutoStretchVertical(true)
    msg2:Dock(TOP)
    msg2:DockMargin(0, 0, 0, 15)
    
    local changelogHeader = vgui.Create("DPanel", content)
    changelogHeader:SetTall(30)
    changelogHeader:Dock(TOP)
    changelogHeader:DockMargin(0, 0, 0, 8)
    changelogHeader.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.accent)
        draw.SimpleText("Update Changelog (v" .. WELCOME_VERSION .. ")", "NaiFont_Medium", 12, h/2, Theme.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    
    local changelog = vgui.Create("DPanel", content)
    changelog:SetTall(185)
    changelog:Dock(TOP)
    changelog:DockMargin(0, 0, 0, 10)
    changelog.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
        local changes = {
            "+ Performance: vehicle seat layout cached, rebuilt only on change",
            "+ Performance: animation maintenance throttled per passenger",
            "+ Performance: client body-sway uses tracked table, no ents.GetAll()",
            "+ Vehicle allow/deny filter convars with CSV wildcard support",
            "+ Boarding retry cooldown on repeated board failures",
            "+ Squad-only auto-join mode (nai_npc_auto_join_squad_only)",
            "+ Global enable/disable toggle (nai_npc_enabled)",
            "* Fix: first-board failures due to uninitialized seat list",
            "* Removed Nai Base API dependency (internal rename only)",
            "* ConVar names (nai_npc_*) unchanged - existing configs preserved",
        }
        for i, line in ipairs(changes) do
            local col = Theme.text
            if string.sub(line, 1, 1) == "*" then col = Theme.textDim end
            draw.SimpleText(line, "NaiFont_Small", 12, 10 + (i - 1) * 17, col, TEXT_ALIGN_LEFT)
        end
    end
    
    local bottomPanel = vgui.Create("DPanel", frame)
    bottomPanel:SetPos(15, frame:GetTall() - 55)
    bottomPanel:SetSize(590, 45)
    bottomPanel.Paint = function() end
    
    -- Don't show again checkbox
    local dontShowCheck = vgui.Create("DCheckBox", bottomPanel)
    dontShowCheck:SetPos(0, 12)
    dontShowCheck:SetSize(20, 20)
    dontShowCheck:SetValue(false)
    dontShowCheck.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Theme.bgLighter)
        if self:GetChecked() then
            draw.RoundedBox(3, 3, 3, w - 6, h - 6, Theme.accent)
            draw.SimpleText("v", "NaiFont_Normal", w/2, h/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        surface.SetDrawColor(Theme.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    
    local dontShowLabel = vgui.Create("DLabel", bottomPanel)
    dontShowLabel:SetPos(28, 12)
    dontShowLabel:SetText("Don't show this again")
    dontShowLabel:SetFont("NaiFont_Normal")
    dontShowLabel:SetTextColor(Theme.textDim)
    dontShowLabel:SizeToContents()
    dontShowLabel:SetMouseInputEnabled(true)
    dontShowLabel:SetCursor("hand")
    dontShowLabel.DoClick = function()
        dontShowCheck:Toggle()
    end
    
    -- OK button
    local okBtn = vgui.Create("DButton", bottomPanel)
    okBtn:SetPos(bottomPanel:GetWide() - 120, 5)
    okBtn:SetSize(120, 36)
    okBtn:SetText("Got it!")
    okBtn:SetFont("NaiFont_Medium")
    okBtn:SetTextColor(TransparentColor)
    okBtn.hoverAnim = 0
    okBtn.pressAnim = 0
    okBtn.Paint = function(self, w, h)
        AnimateButtonVisualState(self, 5, 5, 18, 12)

        local pushOffset = GetButtonPushOffset(self, 2)
        local bgColor = LerpColor(self.hoverAnim, Theme.success, Color(100, 200, 120))
        bgColor = LerpColor(self.pressAnim, bgColor, Color(60, 160, 80))
        DrawClippedBlur(self, 0, pushOffset, w, h, 2 + (self.hoverAnim * 1.1) + (self.pressAnim * 2), 1, 44 + (self.pressAnim * 30))
        draw.RoundedBox(6, 0, pushOffset, w, h, WithAlpha(bgColor, 220))
        draw.SimpleText(self:GetText(), "NaiFont_Medium", w / 2, (h / 2) + pushOffset, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    okBtn.DoClick = function()
        if dontShowCheck:GetChecked() then
            cookie.Set("nai_passengers_hide_welcome", "1")
            cookie.Set("nai_passengers_last_version", WELCOME_VERSION)
        end
        frame:Close()
    end
end

-- Show welcome panel shortly after game loads
hook.Add("InitPostEntity", "NPCPassengersWelcome", function()
    timer.Simple(3, ShowWelcomePanel)
end)

--[[
    ========================================
    PASSENGER STATUS HUD
    ========================================
]]

local hudIcons = {}
local hudIconsLoaded = false

-- Try to load custom icons, fallback to built-in drawing
local function LoadHUDIcons()
    if hudIconsLoaded then return end
    hudIconsLoaded = true
    
    local iconNames = {"calm", "alert", "scared", "drowsy", "dead", "passenger"}
    for _, name in ipairs(iconNames) do
        local path = "nai_passengers/icon_" .. name .. ".png"
        local mat = Material(path, "smooth mips")
        if not mat:IsError() then
            hudIcons[name] = mat
        end
    end
end

-- Status colors
local StatusColors = {
    calm = Color(80, 200, 120),      -- Green
    alert = Color(255, 180, 50),     -- Yellow/Orange
    scared = Color(255, 80, 80),     -- Red
    drowsy = Color(100, 150, 255),   -- Blue
    dead = Color(60, 60, 70),        -- Dark Gray (Dead)
    default = Color(180, 180, 180),  -- Gray
}

-- Get passenger emotional state
local function GetPassengerStatus(npc)
    if not IsValid(npc) then return "default", 0 end
    
    local alertThreshold = GetConVar("nai_npc_hud_alert_threshold")
    local fearThreshold = GetConVar("nai_npc_hud_fear_threshold")
    local drowsyThreshold = GetConVar("nai_npc_hud_drowsy_threshold")
    
    local alertLevel = npc:GetNWFloat("NPCPassengerAlertLevel", 0)
    local fearLevel = npc:GetNWFloat("NPCPassengerFearLevel", 0)
    local isDrowsy = npc:GetNWBool("NPCPassengerIsDrowsy", false)
    local calmTime = npc:GetNWFloat("NPCPassengerCalmTime", 0)
    local drowsyTime = GetConVar("nai_npc_drowsy_time")
    
    -- Priority: Dead > Scared > Alert > Drowsy > Calm
    local at = alertThreshold and alertThreshold:GetFloat() or 0.3
    local ft = fearThreshold and fearThreshold:GetFloat() or 0.5
    local dt = drowsyThreshold and drowsyThreshold:GetFloat() or 0.7
    local drowsyTimeVal = drowsyTime and drowsyTime:GetFloat() or 60
    
    -- Check if dead
    if npc:Health() <= 0 or not npc:Alive() then
        return "dead", 1
    elseif fearLevel >= ft then
        return "scared", fearLevel
    elseif alertLevel >= at then
        return "alert", alertLevel
    elseif isDrowsy or (drowsyTimeVal > 0 and calmTime / drowsyTimeVal >= dt) then
        return "drowsy", calmTime / math.max(1, drowsyTimeVal)
    else
        return "calm", 0
    end
end

-- Get NPC display name
local function GetNPCDisplayName(npc)
    if not IsValid(npc) then return "Unknown" end
    
    -- Try to get targetname (map-placed NPCs)
    local targetName = npc:GetNWString("targetname", "")
    if targetName == "" and npc.GetInternalVariable then
        targetName = npc:GetInternalVariable("m_iName") or ""
    end
    if targetName and targetName ~= "" then return targetName end
    
    -- Use class-based names
    local class = npc:GetClass() or "unknown"
    local classNames = {
        ["npc_citizen"] = "Citizen",
        ["npc_alyx"] = "Alyx",
        ["npc_barney"] = "Barney",
        ["npc_monk"] = "Father Grigori",
        ["npc_eli"] = "Eli",
        ["npc_kleiner"] = "Dr. Kleiner",
        ["npc_mossman"] = "Dr. Mossman",
        ["npc_breen"] = "Dr. Breen",
        ["npc_vortigaunt"] = "Vortigaunt",
        ["npc_dog"] = "Dog",
    }
    
    if classNames[class] then return classNames[class] end
    
    -- Try model-based name
    local model = npc:GetModel() or ""
    if string.find(model, "female") then
        return "Citizen (F)"
    elseif string.find(model, "male") then
        return "Citizen (M)"
    elseif string.find(model, "medic") then
        return "Medic"
    elseif string.find(model, "rebel") then
        return "Rebel"
    end
    
    return "Passenger"
end

-- Draw status icon (fallback if no custom icon)
local function DrawStatusIcon(x, y, size, status, progress)
    local color = StatusColors[status] or StatusColors.default
    
    -- Shake effect for scared status
    local shakeX, shakeY = 0, 0
    if status == "scared" then
        local shakeIntensity = 2
        shakeX = math.sin(CurTime() * 30) * shakeIntensity
        shakeY = math.cos(CurTime() * 40) * shakeIntensity
    end
    
    -- Check for custom icon
    if hudIcons[status] then
        surface.SetMaterial(hudIcons[status])
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x + shakeX, y + shakeY, size, size)
    else
        -- Fallback: Draw colored circle with symbol
        draw.RoundedBox(size / 2, x + shakeX, y + shakeY, size, size, color)
        
        local symbols = {
            calm = "*",
            alert = "!",
            scared = "!!",
            drowsy = "Z",
            dead = "X",
            default = "?"
        }
        
        local symbol = symbols[status] or "?"
        draw.SimpleText(symbol, "NaiFont_Medium", x + size / 2 + shakeX, y + size / 2 + shakeY, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- Main HUD drawing
local hudPassengers = {}
local lastHUDUpdate = 0
local smoothedIntensity = {}  -- Table to store smoothed intensity values per NPC
local smoothedHealth = {}     -- Table to store smoothed health values per NPC

-- Dead passenger ejection prompt
local ejectPromptData = {
    count = 0,
    showTime = 0,
    lookingAt = false,
    lastPress = 0,
    holdProgress = 0,
    holdStartTime = 0,
    isHolding = false,
    requiredHoldTime = 1.5  -- 1.5 seconds to eject
}

local clientCueData = {
    text = "",
    success = true,
    expireAt = 0
}

net.Receive("NPCPassengers_ClientCue", function()
    local success = net.ReadBool()
    local msg = net.ReadString()

    if GetConVarBoolSafe("nai_npc_client_cues", true) then
        surface.PlaySound(success and "buttons/button15.wav" or "buttons/button10.wav")
    end

    clientCueData.text = msg or ""
    clientCueData.success = success
    clientCueData.expireAt = CurTime() + 2.2
end)

net.Receive("NPCPassengers_EjectPrompt", function()
    ejectPromptData.count = net.ReadInt(8)
    ejectPromptData.lookingAt = net.ReadBool()
    ejectPromptData.showTime = CurTime()
end)

-- Detect R key HOLD to eject dead passengers
hook.Add("Think", "NPCPassengers_EjectKeyCheck", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then 
        ejectPromptData.isHolding = false
        ejectPromptData.holdProgress = 0
        return 
    end
    
    -- MUST be on foot to eject
    if ply:InVehicle() then 
        ejectPromptData.isHolding = false
        ejectPromptData.holdProgress = 0
        return 
    end
    
    -- Check if prompt is currently visible (within last 0.5 seconds)
    if CurTime() - ejectPromptData.showTime > 0.5 then 
        ejectPromptData.isHolding = false
        ejectPromptData.holdProgress = 0
        return 
    end
    if ejectPromptData.count <= 0 then 
        ejectPromptData.isHolding = false
        ejectPromptData.holdProgress = 0
        return 
    end
    
    -- MUST be alive to eject
    if not ply:Alive() then
        ejectPromptData.isHolding = false
        ejectPromptData.holdProgress = 0
        return
    end
    
    -- Check if R key is being held
    if input.IsKeyDown(KEY_R) then
        if not ejectPromptData.isHolding then
            -- Just started holding
            ejectPromptData.isHolding = true
            ejectPromptData.holdStartTime = CurTime()
            ejectPromptData.holdProgress = 0
        else
            -- Continue holding - update progress
            local holdTime = CurTime() - ejectPromptData.holdStartTime
            ejectPromptData.holdProgress = math.min(holdTime / ejectPromptData.requiredHoldTime, 1)
            
            -- If held long enough, eject!
            if ejectPromptData.holdProgress >= 1 then
                -- Send eject request to server
                net.Start("NPCPassengers_EjectDead")
                net.SendToServer()
                
                -- Clear prompt and reset
                ejectPromptData.count = 0
                ejectPromptData.showTime = 0
                ejectPromptData.isHolding = false
                ejectPromptData.holdProgress = 0
                
                -- Play satisfying sound
                surface.PlaySound("buttons/lever7.wav")
            end
        end
    else
        -- Key released - reset hold
        if ejectPromptData.isHolding then
            ejectPromptData.isHolding = false
            ejectPromptData.holdProgress = 0
        end
    end
end)

-- Draw ejection prompt
hook.Add("HUDPaint", "NPCPassengers_EjectPrompt", function()
    if CurTime() - ejectPromptData.showTime > 0.5 then return end
    if ejectPromptData.count <= 0 then return end
    
    local scrW, scrH = ScrW(), ScrH()
    local centerX = scrW / 2
    local centerY = scrH / 2 + 100
    
    -- Background box
    local textWidth = 350
    local textHeight = 80
    local boxX = centerX - textWidth / 2
    local boxY = centerY - textHeight / 2
    
    -- Pulsing glow effect
    local pulse = math.abs(math.sin(CurTime() * 3)) * 50 + 205
    
    -- Draw outer glow
    draw.RoundedBox(12, boxX - 4, boxY - 4, textWidth + 8, textHeight + 8, Color(200, 50, 50, pulse * 0.3))
    
    -- Draw main box
    draw.RoundedBox(10, boxX, boxY, textWidth, textHeight, Color(40, 25, 25, 240))
    
    -- Draw border
    draw.RoundedBox(10, boxX - 2, boxY - 2, textWidth + 4, textHeight + 4, Color(200, 50, 50, 0))
    surface.SetDrawColor(200, 50, 50, pulse)
    surface.DrawOutlinedRect(boxX - 1, boxY - 1, textWidth + 2, textHeight + 2, 2)
    
    -- Skull icon
    draw.SimpleText("[DEAD]", "NaiFont_Bold", centerX, boxY + 20, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Text
    local deadText = ejectPromptData.count .. " Dead Passenger" .. (ejectPromptData.count > 1 and "s" or "")
    draw.SimpleText(deadText, "NaiFont_Bold", centerX, boxY + 38, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Instruction with hold progress
    if ejectPromptData.isHolding and ejectPromptData.holdProgress > 0 then
        -- Show progress bar when holding
        local barWidth = 250
        local barHeight = 16
        local barX = centerX - barWidth / 2
        local barY = boxY + 54
        
        -- Progress bar background
        draw.RoundedBox(8, barX, barY, barWidth, barHeight, Color(20, 20, 25, 200))
        
        -- Progress bar fill
        local fillWidth = barWidth * ejectPromptData.holdProgress
        local fillColor = Color(
            math.Lerp(ejectPromptData.holdProgress, 255, 100),
            math.Lerp(ejectPromptData.holdProgress, 100, 255),
            100
        )
        draw.RoundedBox(8, barX, barY, fillWidth, barHeight, fillColor)
        
        -- Progress text
        local progressPercent = math.floor(ejectPromptData.holdProgress * 100)
        draw.SimpleText(progressPercent .. "%", "NaiFont_Small", centerX, barY + barHeight / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        -- Show instruction when not holding
        local keyColor = ejectPromptData.lookingAt and Color(100, 255, 100) or Color(255, 200, 100)
        local instruction = "Hold [R] to Remove Bodies"
        draw.SimpleText(instruction, "NaiFont_Normal", centerX, boxY + 58, keyColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

hook.Add("HUDPaint", "NPCPassengers_StatusHUD", function()
    -- Check if HUD is enabled
    local hudEnabled = GetConVar("nai_npc_hud_enabled")
    if not hudEnabled or not hudEnabled:GetBool() then return end
    
    -- Check if player should see HUD
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local onlyInVehicle = GetConVar("nai_npc_hud_only_vehicle")
    if onlyInVehicle and onlyInVehicle:GetBool() then
        if not ply:InVehicle() then return end
    end
    
    -- Load icons
    LoadHUDIcons()
    
    -- Get settings
    local positionCV = GetConVar("nai_npc_hud_position")
    local scaleCV = GetConVar("nai_npc_hud_scale")
    local opacityCV = GetConVar("nai_npc_hud_opacity")
    local showCalmCV = GetConVar("nai_npc_hud_show_calm")
    
    local position = positionCV and positionCV:GetInt() or 1
    local scale = scaleCV and scaleCV:GetFloat() or 1
    local opacity = opacityCV and opacityCV:GetFloat() or 0.85
    local showCalm = showCalmCV and showCalmCV:GetBool() or true
    
    -- Update passenger list periodically
    if CurTime() - lastHUDUpdate > 0.25 then
        lastHUDUpdate = CurTime()
        hudPassengers = {}
        
        -- Clean up smoothed values for invalid/removed NPCs
        local validNPCs = {}
        
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNPCPassenger", false) then
                local status, intensity = GetPassengerStatus(ent)
                if showCalm or status ~= "calm" then
                    local health = ent:Health()
                    local maxHealth = ent:GetMaxHealth()
                    table.insert(hudPassengers, {
                        npc = ent,
                        name = GetNPCDisplayName(ent),
                        status = status,
                        intensity = intensity,
                        health = health,
                        maxHealth = maxHealth,
                        healthPercent = maxHealth > 0 and (health / maxHealth) or 1,
                    })
                    validNPCs[ent:EntIndex()] = true
                end
            end
        end
        
        -- Remove smoothed values for NPCs that no longer exist
        for npcID, _ in pairs(smoothedIntensity) do
            if not validNPCs[npcID] then
                smoothedIntensity[npcID] = nil
                smoothedHealth[npcID] = nil
            end
        end
    end
    
    -- No passengers to show
    if #hudPassengers == 0 then return end
    
    -- Calculate dimensions
    local baseWidth = 220
    local baseHeight = 58
    local padding = 8
    local iconSize = 28
    local barHeight = 8
    
    local panelWidth = baseWidth * scale
    local entryHeight = baseHeight * scale
    local totalHeight = (#hudPassengers * entryHeight) + (padding * 2 * scale) + (24 * scale)
    
    -- Position calculation
    local scrW, scrH = ScrW(), ScrH()
    local margin = 20
    local startX, startY
    
    if position == 0 then -- Top Left
        startX = margin
        startY = margin
    elseif position == 1 then -- Top Right
        startX = scrW - panelWidth - margin
        startY = margin
    elseif position == 2 then -- Bottom Left
        startX = margin
        startY = scrH - totalHeight - margin
    else -- Bottom Right
        startX = scrW - panelWidth - margin
        startY = scrH - totalHeight - margin
    end
    
    -- Draw background panel
    local bgColor = Color(25, 25, 30, 255 * opacity)
    local headerColor = Color(40, 40, 50, 255 * opacity)
    local borderColor = Color(70, 130, 180, 200 * opacity)
    
    -- Draw rounded border first (larger box with border color)
    draw.RoundedBox(8 * scale, startX - 2, startY - 2, panelWidth + 4, totalHeight + 4, borderColor)
    
    -- Main background on top
    draw.RoundedBox(8 * scale, startX, startY, panelWidth, totalHeight, bgColor)
    
    -- Header
    draw.RoundedBoxEx(8 * scale, startX, startY, panelWidth, 24 * scale, headerColor, true, true, false, false)
    
    -- Header text
    draw.SimpleText("Passengers", "NaiFont_Bold", startX + padding * scale, startY + 12 * scale, Color(220, 220, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(tostring(#hudPassengers), "NaiFont_Small", startX + panelWidth - padding * scale, startY + 12 * scale, Color(150, 150, 165), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    
    -- Draw each passenger
    local entryY = startY + 24 * scale + padding * scale
    
    for i, pdata in ipairs(hudPassengers) do
        if not IsValid(pdata.npc) then continue end
        
        local entryX = startX + padding * scale
        local entryW = panelWidth - (padding * 2 * scale)
        
        -- Entry background (subtle)
        local entryBgColor = Color(35, 35, 42, 200 * opacity)
        draw.RoundedBox(4 * scale, entryX, entryY, entryW, entryHeight - 4 * scale, entryBgColor)
        
        -- Status icon
        local statusColor = StatusColors[pdata.status] or StatusColors.default
        DrawStatusIcon(entryX + 4 * scale, entryY + 4 * scale, iconSize * scale, pdata.status, pdata.intensity)
        
        -- Name
        local textX = entryX + iconSize * scale + 10 * scale
        draw.SimpleText(pdata.name, "NaiFont_Normal", textX, entryY + 6 * scale, Color(220, 220, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        -- Status text (right side, same line as name)
        local statusText = string.upper(pdata.status)
        draw.SimpleText(statusText, "NaiFont_Small", entryX + entryW - 4 * scale, entryY + 8 * scale, statusColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        
        -- Intensity bar (below name) - SMOOTH INTERPOLATION
        local barX = textX
        local barY = entryY + 22 * scale
        local barW = entryW - (iconSize * scale + 14 * scale)
        local barH = barHeight * scale
        
        -- Smoothly interpolate intensity
        local npcID = pdata.npc:EntIndex()
        smoothedIntensity[npcID] = smoothedIntensity[npcID] or pdata.intensity
        local targetIntensity = pdata.intensity
        local lerpSpeed = FrameTime() * 3  -- Adjust for smoothness (higher = faster)
        smoothedIntensity[npcID] = Lerp(lerpSpeed, smoothedIntensity[npcID], targetIntensity)
        
        -- Bar background
        draw.RoundedBox(barH / 2, barX, barY, barW, barH, Color(20, 20, 25, 200))
        
        -- Bar fill (using smoothed value)
        local fillW = math.Clamp(smoothedIntensity[npcID], 0, 1) * barW
        if fillW > 2 then
            draw.RoundedBox(barH / 2, barX, barY, fillW, barH, statusColor)
        end
        
        -- Health Bar (below intensity bar) - SMOOTH INTERPOLATION
        local healthBarY = entryY + 34 * scale
        local healthBarW = barW
        local healthPercent = pdata.healthPercent or 1
        
        -- Smoothly interpolate health
        smoothedHealth[npcID] = smoothedHealth[npcID] or healthPercent
        local targetHealth = healthPercent
        local healthLerpSpeed = FrameTime() * 2  -- Slower for health (more dramatic)
        smoothedHealth[npcID] = Lerp(healthLerpSpeed, smoothedHealth[npcID], targetHealth)
        
        local smoothHealth = smoothedHealth[npcID]
        
        -- Determine health bar color (using smoothed value)
        local healthColor
        if smoothHealth > 0.75 then
            healthColor = Color(50, 200, 50)  -- Green (healthy)
        elseif smoothHealth > 0.4 then
            healthColor = Color(220, 180, 50)  -- Yellow (injured)
        else
            healthColor = Color(220, 50, 50)  -- Red (critical)
        end
        
        -- Health bar background
        draw.RoundedBox(barH / 2, barX, healthBarY, healthBarW, barH, Color(20, 20, 25, 200))
        
        -- Health bar fill (using smoothed value)
        local healthFillW = math.Clamp(smoothHealth, 0, 1) * healthBarW
        if healthFillW > 2 then
            draw.RoundedBox(barH / 2, barX, healthBarY, healthFillW, barH, healthColor)
            
            -- Healing indicator (pulsing glow when health is between 40-99%)
            if smoothHealth > 0.4 and smoothHealth < 0.99 then
                local pulse = math.abs(math.sin(CurTime() * 3)) * 100
                draw.RoundedBox(barH / 2, barX, healthBarY, healthFillW, barH, Color(100, 255, 100, pulse))
            end
        end
        
        -- Health text (HP) - centered on health bar
        local healthText = string.format("%d/%d", pdata.health or 0, pdata.maxHealth or 100)
        draw.SimpleText(healthText, "DermaDefaultBold", barX + healthBarW - 2 * scale, healthBarY + 1 * scale, Color(255, 255, 255, 220), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        
        entryY = entryY + entryHeight
    end
end)

hook.Add("HUDPaint", "NPCPassengers_ClientHints", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local showHints = GetConVarBoolSafe("nai_npc_hud_hints", true)
    local showTargetDebug = GetConVarBoolSafe("nai_npc_hud_target_debug", false)
    if not showHints and not showTargetDebug then return end

    local scrW, scrH = ScrW(), ScrH()
    local centerX = scrW * 0.5
    local y = scrH - 120

    if showHints and clientCueData.expireAt > CurTime() and clientCueData.text ~= "" then
        local col = clientCueData.success and Color(120, 240, 120) or Color(255, 140, 140)
        draw.SimpleText(clientCueData.text, "NaiFont_Normal", centerX, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        y = y - 22
    end

    if showTargetDebug then
        local tr = ply:GetEyeTrace()
        local ent = tr and tr.Entity
        if IsValid(ent) and ent:IsNPC() then
            local status = "none"
            if ent:GetNWBool("IsNPCPassenger", false) then
                local emotion = "calm"
                if ent:GetNWBool("NPCPassengerIsDrowsy", false) then
                    emotion = "drowsy"
                elseif ent:GetNWFloat("NPCPassengerFearLevel", 0) > 0.5 then
                    emotion = "scared"
                elseif ent:GetNWFloat("NPCPassengerAlertLevel", 0) > 0.3 then
                    emotion = "alert"
                end
                status = "passenger:" .. emotion
            end

            local veh = ent:GetParent()
            local vehText = IsValid(veh) and (veh:GetClass() or "unknown") or "none"
            draw.SimpleText("target npc " .. ent:GetClass() .. " | " .. status .. " | seat " .. vehText, "NaiFont_Small", centerX, y, Color(160, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)

-- NPC Driver Debug HUD
hook.Add("HUDPaint", "NPCPassengers_DriverDebug", function()
    if not GetConVar("nai_npc_driver_debug"):GetBool() then return end
    if not GetConVar("nai_npc_driver_enabled"):GetBool() then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    -- Draw debug info for nearby NPCs that are drivers
    for _, npc in ipairs(ents.FindInSphere(ply:GetPos(), 2000)) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        
        -- Check if NPC has a vehicle parent (indicating it might be a driver)
        local parent = npc:GetParent()
        if not IsValid(parent) or not parent:IsVehicle() then continue end
        
        local vehicle = parent
        local vehPos = vehicle:GetPos()
        local screenPos = vehPos:ToScreen()
        
        if not screenPos.visible then continue end
        
        -- Draw vehicle info
        local vehVel = vehicle:GetVelocity()
        local speed = math.Round(vehVel:Length())
        
        draw.SimpleText("NPC Driver", "DermaDefault", screenPos.x, screenPos.y - 40, Color(100, 200, 255), TEXT_ALIGN_CENTER)
        draw.SimpleText("Speed: " .. speed .. " u/s", "DermaDefault", screenPos.x, screenPos.y - 25, Color(255, 255, 255), TEXT_ALIGN_CENTER)
        draw.SimpleText("NPC: " .. npc:GetClass(), "DermaDefault", screenPos.x, screenPos.y - 10, Color(200, 200, 200), TEXT_ALIGN_CENTER)
    end
end)
