if SERVER then return end

-- NPC Passengers UI
-- Dark theme settings panel with custom Metropolis font

-- Keybind system: Track key states to detect key presses
local keyStates = {}

hook.Add("Think", "NaiPassengers_Keybinds", function()
    -- Helper function to check if a key was just pressed
    local function WasKeyJustPressed(keyCode)
        if keyCode <= 0 then return false end
        
        local isDown = input.IsKeyDown(keyCode)
        local wasDown = keyStates[keyCode] or false
        keyStates[keyCode] = isDown
        
        return isDown and not wasDown
    end
    
    -- Check each keybind
    local keyAttach = GetConVar("nai_npc_key_attach"):GetInt()
    if WasKeyJustPressed(keyAttach) then
        RunConsoleCommand("nai_npc_attach_nearest")
    end
    
    local keyDetachAll = GetConVar("nai_npc_key_detach_all"):GetInt()
    if WasKeyJustPressed(keyDetachAll) then
        RunConsoleCommand("nai_npc_detach_all")
    end
    
    local keyToggleAutoJoin = GetConVar("nai_npc_key_toggle_autojoin"):GetInt()
    if WasKeyJustPressed(keyToggleAutoJoin) then
        local currentVal = GetConVar("nai_npc_auto_join"):GetBool()
        RunConsoleCommand("nai_npc_auto_join", currentVal and "0" or "1")
        chat.AddText(Color(100, 200, 255), "[NPC Passengers] ", Color(255, 255, 255), "Auto-Join: ", currentVal and Color(255, 100, 100) or Color(100, 255, 100), currentVal and "OFF" or "ON")
    end
    
    local keyMenu = GetConVar("nai_npc_key_menu"):GetInt()
    if WasKeyJustPressed(keyMenu) then
        RunConsoleCommand("nai_passengers_menu")
    end
    
    local keyExitAll = GetConVar("nai_npc_key_exit_all"):GetInt()
    if WasKeyJustPressed(keyExitAll) then
        RunConsoleCommand("nai_npc_exit_all")
    end
    
    -- Debug keybinds (only if debug mode is enabled)
    local debugMode = GetConVar("nai_npc_debug_mode")
    if debugMode and debugMode:GetBool() then
        local keyTestGesture = GetConVar("nai_npc_key_test_gesture"):GetInt()
        if WasKeyJustPressed(keyTestGesture) then
            net.Start("NaiPassengers_DebugTest")
            net.WriteString("gesture")
            net.SendToServer()
        end
        
        local keyResetAll = GetConVar("nai_npc_key_reset_all"):GetInt()
        if WasKeyJustPressed(keyResetAll) then
            net.Start("NaiPassengers_DebugTest")
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
hook.Add("Think", "NaiPassengers_ClientBodySway", function()
    local dt = FrameTime()
    if dt <= 0 then return end
    
    local bodySwayCV = GetConVar("nai_npc_body_sway")
    local bodySwayAmountCV = GetConVar("nai_npc_body_sway_amount")
    local crashFlinchCV = GetConVar("nai_npc_crash_flinch")
    local crashThresholdCV = GetConVar("nai_npc_crash_threshold")
    
    if not bodySwayCV or not bodySwayCV:GetBool() then return end
    
    local swayAmount = bodySwayAmountCV and bodySwayAmountCV:GetFloat() or 1
    local crashFlinchEnabled = crashFlinchCV and crashFlinchCV:GetBool() or true
    local crashThreshold = crashThresholdCV and crashThresholdCV:GetFloat() or 400
    
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNaiPassenger", false) then
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
hook.Add("EntityRemoved", "NaiPassengers_CleanBoneCache", function(ent)
    if ent:IsNPC() then
        local entIdx = ent:EntIndex()
        spineBoneCache[entIdx] = nil
        clientSwayState[entIdx] = nil
    end
end)

-- Theme colors - Modern gradient design
local Theme = {
    bg = Color(22, 22, 28),
    bgLight = Color(32, 32, 40),
    bgLighter = Color(42, 42, 52),
    bgDark = Color(15, 15, 20),
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

-- Custom fonts (requires Metropolis.otf in resource/fonts/)
local fontName = "Metropolis"

surface.CreateFont("NaiFont_Small", {
    font = fontName,
    size = 14,
    weight = 400,
    antialias = true,
})

surface.CreateFont("NaiFont_Normal", {
    font = fontName,
    size = 16,
    weight = 400,
    antialias = true,
})

surface.CreateFont("NaiFont_Medium", {
    font = fontName,
    size = 18,
    weight = 500,
    antialias = true,
})

surface.CreateFont("NaiFont_Large", {
    font = fontName,
    size = 22,
    weight = 600,
    antialias = true,
})

surface.CreateFont("NaiFont_Title", {
    font = fontName,
    size = 26,
    weight = 700,
    antialias = true,
})

surface.CreateFont("NaiFont_Bold", {
    font = fontName,
    size = 16,
    weight = 700,
    antialias = true,
})

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
    header:SetTall(38)
    header:Dock(TOP)
    header:DockMargin(0, 15, 0, 8)
    header.Paint = function(self, w, h)
        -- Gradient background
        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 80)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, 0, w, h)
        
        -- Accent line at bottom
        surface.SetDrawColor(Theme.accent)
        surface.DrawRect(0, h - 3, w, 3)
        
        -- Glow effect
        draw.RoundedBox(0, 0, h - 3, w, 3, Theme.glow)
        
        -- Icon
        surface.SetDrawColor(Theme.accent)
        surface.SetMaterial(Material("icon16/star.png"))
        surface.DrawTexturedRect(12, (h - 16) / 2, 16, 16)
        
        draw.SimpleText(text, "NaiFont_Medium", 36, h/2, Theme.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return header
end

local function CreateSubHeader(parent, text)
    local header = vgui.Create("DPanel", parent)
    header:SetTall(28)
    header:Dock(TOP)
    header:DockMargin(5, 12, 5, 6)
    header.Paint = function(self, w, h)
        -- Left accent bar
        draw.RoundedBox(2, 0, 0, 4, h, Theme.accent)
        
        -- Bottom gradient line
        local gradientMat = Material("vgui/gradient-r")
        surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 60)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, h - 2, w, 2)
        
        draw.SimpleText(text, "NaiFont_Bold", 12, h/2 - 2, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return header
end

local function CreateHelpText(parent, text)
    local help = vgui.Create("DLabel", parent)
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
            draw.SimpleText("✓", "NaiFont_Bold", w/2, h/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
        draw.SimpleText("▼", "NaiFont_Small", w - 15, h/2, Theme.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
    btn:SetText(text)
    btn:SetFont("NaiFont_Medium")
    btn:SetTall(40)
    btn:Dock(TOP)
    btn:DockMargin(8, 6, 8, 6)
    btn:SetTextColor(Theme.textBright)
    btn.hoverAnim = 0
    btn.clickAnim = 0
    btn.hasPlayedHoverSound = false
    
    btn.Paint = function(self, w, h)
        -- Hover animation and sound
        if self:IsHovered() then
            self.hoverAnim = math.Approach(self.hoverAnim, 1, FrameTime() * 6)
            if not self.hasPlayedHoverSound then
                if GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_hover_enabled"):GetBool() then
                    local volume = GetConVar("nai_npc_ui_sounds_volume"):GetFloat()
                    surface.PlaySound("nai_passengers/ui_hover.wav")
                end
                self.hasPlayedHoverSound = true
            end
        else
            self.hoverAnim = math.Approach(self.hoverAnim, 0, FrameTime() * 8)
            self.hasPlayedHoverSound = false
        end
        
        -- Click animation
        if self:IsDown() then
            self.clickAnim = 1
        else
            self.clickAnim = math.Approach(self.clickAnim, 0, FrameTime() * 12)
        end
        
        -- Background with glow
        local bgColor = LerpColor(self.hoverAnim, Theme.accent, Theme.accentHover)
        if self.clickAnim > 0 then
            bgColor = Theme.accentActive
        end
        
        -- Outer glow on hover
        if self.hoverAnim > 0 then
            local glowAlpha = 50 * self.hoverAnim
            draw.RoundedBox(8, -2, -2, w + 4, h + 4, ColorAlpha(Theme.accent, glowAlpha))
        end
        
        -- Shadow
        draw.RoundedBox(8, 2, 2, w, h, Theme.shadow)
        
        -- Main button
        draw.RoundedBox(7, 0, 0, w, h, bgColor)
        
        -- Subtle gradient overlay
        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(255, 255, 255, 15)
        surface.SetMaterial(gradientMat)
        surface.DrawTexturedRect(0, 0, w, h / 2)
        
        -- Border highlight
        surface.SetDrawColor(Theme.accentHover.r, Theme.accentHover.g, Theme.accentHover.b, 60)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
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

local function OpenSettingsPanel()
    if IsValid(settingsFrame) then
        settingsFrame:Remove()
    end
    
    local panelWidth = GetConVar("nai_npc_ui_panel_width"):GetInt()
    local panelHeight = GetConVar("nai_npc_ui_panel_height"):GetInt()
    
    settingsFrame = vgui.Create("DFrame")
    settingsFrame:SetSize(panelWidth, panelHeight)
    settingsFrame:Center()
    settingsFrame:SetTitle("")
    settingsFrame:SetDraggable(true)
    settingsFrame:MakePopup()
    settingsFrame:SetDeleteOnClose(true)
    
    settingsFrame.Paint = function(self, w, h)
        -- Outer shadow
        draw.RoundedBox(14, 4, 4, w, h, Color(0, 0, 0, 140))
        
        -- Main background
        draw.RoundedBox(12, 0, 0, w, h, Theme.bg)
        
        -- Header gradient
        local gradientMat = Material("vgui/gradient-d")
        surface.SetDrawColor(Theme.accentDark.r, Theme.accentDark.g, Theme.accentDark.b, 120)
        surface.SetMaterial(gradientMat)
        draw.RoundedBoxEx(12, 0, 0, w, 50, Theme.bgDark, true, true, false, false)
        surface.DrawTexturedRect(0, 0, w, 50)
        
        -- Accent line under header
        surface.SetDrawColor(Theme.accent)
        surface.DrawRect(0, 50, w, 2)
        
        -- Title text with shadow
        draw.SimpleText("NPC Passengers Settings", "NaiFont_Title", 21, 26, Color(0, 0, 0, 100), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("NPC Passengers Settings", "NaiFont_Title", 20, 25, Theme.textBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        -- Version badge
        local versionW = 45
        local versionH = 20
        local versionX = w - versionW - 50
        local versionY = 15
        draw.RoundedBox(10, versionX, versionY, versionW, versionH, Theme.accentDark)
        draw.SimpleText("v2.3 PreAlpha Test", "NaiFont_Small", versionX + versionW/2, versionY + versionH/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    settingsFrame.btnClose:SetVisible(false)
    settingsFrame.btnMaxim:SetVisible(false)
    settingsFrame.btnMinim:SetVisible(false)
    
    local closeBtn = vgui.Create("DButton", settingsFrame)
    closeBtn:SetPos(settingsFrame:GetWide() - 38, 12)
    closeBtn:SetSize(28, 28)
    closeBtn:SetText("")
    closeBtn.hoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        if self:IsHovered() then
            self.hoverAnim = math.Approach(self.hoverAnim, 1, FrameTime() * 8)
        else
            self.hoverAnim = math.Approach(self.hoverAnim, 0, FrameTime() * 10)
        end
        
        local col = LerpColor(self.hoverAnim, Theme.bgLight, Theme.error)
        draw.RoundedBox(6, 0, 0, w, h, col)
        
        -- X icon
        surface.SetDrawColor(Theme.textBright)
        surface.DrawLine(8, 8, w - 8, h - 8)
        surface.DrawLine(w - 8, 8, 8, h - 8)
    end
    closeBtn.DoClick = function()
        settingsFrame:Close()
    end
    
    -- Side panel navigation system
    local navContainer = vgui.Create("DPanel", settingsFrame)
    navContainer:SetPos(10, 58)
    navContainer:SetSize(930, 632)
    navContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Theme.bgLight)
    end
    
    -- Left sidebar for navigation
    local sidebar = vgui.Create("DScrollPanel", navContainer)
    sidebar:SetPos(0, 0)
    sidebar:SetSize(270, 632)
    sidebar.Paint = function(self, w, h)
        draw.RoundedBoxEx(8, 0, 0, w, h, Theme.bgDark, true, false, true, false)
        
        -- Right border with glow
        surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 80)
        surface.DrawRect(w - 2, 0, 2, h)
    end
    StyleScrollbar(sidebar:GetVBar())
    
    -- Right content area
    local contentArea = vgui.Create("DPanel", navContainer)
    contentArea:SetPos(278, 0)
    contentArea:SetSize(652, 636)
    contentArea.Paint = function() end
    
    local currentPanel = nil
    local navButtons = {}
    
    -- Function to create nav button
    local function CreateNavButton(label, icon)
        local btn = vgui.Create("DButton", sidebar)
        btn:SetText("")
        btn:Dock(TOP)
        btn:DockMargin(8, 4, 8, 4)
        btn:SetTall(46)
        btn.isActive = false
        btn.hoverAnim = 0
        btn.activeAnim = 0
        btn.iconPath = icon
        btn.hasPlayedHoverSound = false
        
        btn.Paint = function(self, w, h)
            -- Animation states
            if self.isActive then
                self.activeAnim = math.Approach(self.activeAnim, 1, FrameTime() * 10)
            else
                self.activeAnim = math.Approach(self.activeAnim, 0, FrameTime() * 10)
            end
            
            if self:IsHovered() then
                self.hoverAnim = math.Approach(self.hoverAnim, 1, FrameTime() * 8)
                if not self.hasPlayedHoverSound then
                    if GetConVar("nai_npc_ui_sounds_enabled"):GetBool() and GetConVar("nai_npc_ui_hover_enabled"):GetBool() then
                        surface.PlaySound("nai_passengers/ui_hover.wav")
                    end
                    self.hasPlayedHoverSound = true
                end
            else
                self.hoverAnim = math.Approach(self.hoverAnim, 0, FrameTime() * 10)
                self.hasPlayedHoverSound = false
            end
            
            -- Background
            local bgCol = Theme.bgLight
            if self.activeAnim > 0 then
                bgCol = LerpColor(self.activeAnim, Theme.bgLight, Theme.accent)
            elseif self.hoverAnim > 0 then
                bgCol = LerpColor(self.hoverAnim, Theme.bgLight, Theme.bgLighter)
            end
            
            draw.RoundedBox(6, 0, 0, w, h, bgCol)
            
            -- Active indicator line
            if self.activeAnim > 0 then
                local lineW = 4
                draw.RoundedBox(2, 0, 0, lineW, h, Theme.accentHover)
                
                -- Glow effect
                surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 60 * self.activeAnim)
                surface.DrawRect(-2, 0, w + 4, h)
            end
            
            -- Hover line
            if self.hoverAnim > 0 and not self.isActive then
                surface.SetDrawColor(Theme.accent.r, Theme.accent.g, Theme.accent.b, 40 * self.hoverAnim)
                surface.DrawRect(0, h - 2, w, 2)
            end
            
            -- Icon with color
            local iconCol = self.isActive and Theme.textBright or (self:IsHovered() and Theme.text or Theme.textDim)
            surface.SetDrawColor(iconCol)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(12, (h - 18) / 2, 18, 18)
            
            -- Text
            local textCol = self.isActive and Theme.textBright or (self:IsHovered() and Theme.text or Theme.textDim)
            draw.SimpleText(label, "NaiFont_Normal", 38, h/2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            -- Text
            local textCol = self.isActive and Theme.textBright or (self:IsHovered() and Theme.text or Theme.textDim)
            draw.SimpleText(label, "NaiFont_Normal", 38, h/2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        
        table.insert(navButtons, btn)
        return btn
    end
    
    -- Function to switch panels
    local function SwitchToPanel(panel, activeBtn)
        surface.PlaySound("nai_passengers/ui_click.wav")
        
        if IsValid(currentPanel) then
            currentPanel:SetVisible(false)
        end
        currentPanel = panel
        panel:SetVisible(true)
        
        for _, btn in ipairs(navButtons) do
            btn.isActive = false
        end
        activeBtn.isActive = true
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
    
    -- General Tab
    local generalPanel = CreateContentPanel()
    local generalBtn = CreateNavButton("General", "icon16/cog.png")
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
    local autoJoinBtn = CreateNavButton("Auto-Join", "icon16/group.png")
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
    
    -- Position Tab
    local posPanel = CreateContentPanel()
    local posBtn = CreateNavButton("Position", "icon16/arrow_out.png")
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
    local speechBtn = CreateNavButton("Behaviour", "icon16/sound.png")
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
    local tankBtn = CreateNavButton("Tank/LVS", "icon16/shield.png")
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
    local hudBtn = CreateNavButton("HUD", "icon16/eye.png")
    hudBtn.DoClick = function() SwitchToPanel(hudPanel, hudBtn) end
    
    CreateSectionHeader(hudPanel, "HUD Display")
    
    CreateCheckbox(hudPanel, "Enable Passenger HUD", "nai_npc_hud_enabled")
    CreateHelpText(hudPanel, "Shows passenger status (emotions, alertness) on screen while driving.")
    
    CreateCheckbox(hudPanel, "Only Show When In Vehicle", "nai_npc_hud_only_vehicle")
    CreateCheckbox(hudPanel, "Show Calm Passengers", "nai_npc_hud_show_calm")
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
    local keybindsBtn = CreateNavButton("Keybinds", "icon16/keyboard.png")
    keybindsBtn.DoClick = function() SwitchToPanel(keybindsPanel, keybindsBtn) end
    
    -- Helper function to create keybind button
    local function CreateKeybindButton(parent, label, convar, description)
        local container = vgui.Create("DPanel", parent)
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
        btn:SetTextColor(Theme.text)
        btn:SetSize(120, 35)
        btn.isBinding = false
        
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
            local col = Color(60, 60, 70)
            if self.isBinding then
                col = Theme.accentActive
            elseif self:IsHovered() then
                col = Theme.accent
            end
            if self:IsDown() and not self.isBinding then col = Color(50, 50, 60) end
            draw.RoundedBox(4, 0, 0, w, h, col)
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
        
        return container
    end
    
    CreateSectionHeader(keybindsPanel, "Action Keybinds")
    CreateHelpText(keybindsPanel, "Set custom keybinds for NPC passenger actions. Click a button and press a key to bind.")
    
    local keybindConvars = {
        {name = "Attach Nearest NPC", cvar = "nai_npc_key_attach", desc = "Attach the nearest friendly NPC to your vehicle"},
        {name = "Detach All Passengers", cvar = "nai_npc_key_detach_all", desc = "Remove all NPCs from your vehicle"},
        {name = "Toggle Auto-Join", cvar = "nai_npc_key_toggle_autojoin", desc = "Enable/disable automatic NPC boarding"},
        {name = "Open Settings Menu", cvar = "nai_npc_key_menu", desc = "Open the NPC Passengers settings panel"},
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
    local debugBtn = CreateNavButton("Debugging", "icon16/bug.png")
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
            if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNaiPassenger", false) then
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
                    net.Start("NaiPassengers_SetStatus")
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
        net.Start("NaiPassengers_DebugTest")
        net.WriteString("flinch")
        net.SendToServer()
    end)
    
    CreateButton(debugPanel, "Test Random Gesture", function()
        net.Start("NaiPassengers_DebugTest")
        net.WriteString("gesture")
        net.SendToServer()
    end)
    
    CreateButton(debugPanel, "Reset All States", function()
        net.Start("NaiPassengers_DebugTest")
        net.WriteString("reset")
        net.SendToServer()
    end)
    
    -- NPC Driver Tab
    local driverPanel = CreateContentPanel()
    local driverBtn = CreateNavButton("NPC Driver", "icon16/car.png")
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
    local interfaceBtn = CreateNavButton("Interface", "icon16/application_view_tile.png")
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
    
    CreateSpacer(interfacePanel, 10)
    CreateSectionHeader(interfacePanel, "Settings Panel Preferences")
    
    CreateCheckbox(interfacePanel, "Show Welcome Screen on Updates", "nai_npc_ui_show_welcome")
    CreateHelpText(interfacePanel, "Display welcome panel when addon is updated to a new version")
    
    CreateSlider(interfacePanel, "Panel Width", "nai_npc_ui_panel_width", 800, 1400, 0)
    CreateHelpText(interfacePanel, "Width of the settings panel (requires reopening menu)")
    
    CreateSlider(interfacePanel, "Panel Height", "nai_npc_ui_panel_height", 600, 900, 0)
    CreateHelpText(interfacePanel, "Height of the settings panel (requires reopening menu)")
    
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
        RunConsoleCommand("nai_npc_ui_animations", "1")
        RunConsoleCommand("nai_npc_ui_tooltips", "1")
        chat.AddText(Theme.success, "[NPC Passengers] ", Theme.text, "All UI settings reset to defaults!")
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
            draw.SimpleText("• " .. line, "NaiFont_Small", 20, y, Theme.textDim)
            y = y + 16
        end
    end
    
    -- Simulate Tab
    local simulatePanel = CreateContentPanel()
    local simulateBtn = CreateNavButton("Simulate", "icon16/wand.png")
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
    local modulesBtn = CreateNavButton("Modules", "icon16/plugin.png")
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
    local helpBtn = CreateNavButton("Help", "icon16/help.png")
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
            local arrow = isExpanded and "▼" or "▶"
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
    local aboutBtn = CreateNavButton("About", "icon16/information.png")
    aboutBtn.DoClick = function() SwitchToPanel(aboutPanel, aboutBtn) end
    
    CreateSectionHeader(aboutPanel, "About NPC Passengers v2.3")
    
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
        draw.SimpleText("NPC Passengers", "NaiFont_Title", w/2, y, Theme.accent, TEXT_ALIGN_CENTER)
        y = y + 32
        draw.SimpleText("Advanced passenger system with emotional AI and realistic physics", "NaiFont_Normal", w/2, y, Theme.text, TEXT_ALIGN_CENTER)
        y = y + 30
        
        -- Feature highlights
        local features = {
            "Status System: CALM/ALERT/SCARED/DROWSY/DEAD",
            "Auto-Join: Squad behavior for automatic boarding",
            "Crash Damage: Realistic injury system with body removal"
        }
        
        for _, feature in ipairs(features) do
            draw.SimpleText(feature, "NaiFont_Small", w/2, y, Theme.textDim, TEXT_ALIGN_CENTER)
            y = y + 20
        end
    end
    
    CreateSpacer(aboutPanel, 10)
    CreateSectionHeader(aboutPanel, "What's New in v2.3")
    
    local whatsNew = vgui.Create("DPanel", aboutPanel)
    whatsNew:SetTall(110)
    whatsNew:Dock(TOP)
    whatsNew:DockMargin(5, 0, 5, 5)
    whatsNew.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgLighter)
        
        local y = 12
        local updates = {
            "Passenger status system with real-time HUD",
            "Crash damage mechanics with varying injury",
            "Dead body management (hold R to remove)",
            "Body physics: sway, flinch, drowsy animations",
            "Modern UI with help system (17+ FAQs)"
        }
        
        for i, update in ipairs(updates) do
            -- Checkmark icon
            surface.SetDrawColor(Theme.success)
            surface.SetMaterial(Material("icon16/tick.png"))
            surface.DrawTexturedRect(15, y - 6, 16, 16)
            
            draw.SimpleText(update, "NaiFont_Normal", 38, y, Theme.text)
            y = y + 20
        end
    end
    
    CreateSpacer(aboutPanel, 10)
    CreateSectionHeader(aboutPanel, "Actions")
    
    CreateButton(aboutPanel, "Show Welcome Screen", function()
        settingsFrame:Close()
        timer.Simple(0.1, function() ShowWelcomePanel(true) end)
    end)
    
    CreateButton(aboutPanel, "Reset ALL Settings to Defaults", function()
        RunConsoleCommand("nai_npc_reset")
        settingsFrame:Close()
        timer.Simple(0.1, OpenSettingsPanel)
    end)
    
    CreateSpacer(aboutPanel, 10)
    
    CreateSectionHeader(aboutPanel, "Quick Reference")
    
    CreateHelpText(aboutPanel, "Essential Console Commands:")
    
    local cmdPanel = vgui.Create("DPanel", aboutPanel)
    cmdPanel:SetTall(110)
    cmdPanel:Dock(TOP)
    cmdPanel:DockMargin(5, 0, 5, 5)
    cmdPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
        
        local commands = {
            {"nai_passengers_menu", "Open settings panel (or press F7)"},
            {"nai_npc_reset", "Reset all settings to defaults"},
            {"nai_passengers_list", "List all current passengers"},
            {"nai_npc_auto_join 1/0", "Toggle auto-join on/off"},
        }
        
        local y = 12
        for _, cmd in ipairs(commands) do
            draw.SimpleText(cmd[1], "NaiFont_Bold", 12, y, Theme.accent)
            draw.SimpleText("- " .. cmd[2], "NaiFont_Normal", 200, y, Theme.textDim)
            y = y + 24
        end
    end
    
    CreateSpacer(aboutPanel, 10)
    
    local tipsPanel = vgui.Create("DPanel", aboutPanel)
    tipsPanel:SetTall(70)
    tipsPanel:Dock(TOP)
    tipsPanel:DockMargin(5, 0, 5, 5)
    tipsPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.accentDark)
        
        -- Icon
        surface.SetDrawColor(Theme.textBright)
        surface.SetMaterial(Material("icon16/lightbulb.png"))
        surface.DrawTexturedRect(15, 15, 16, 16)
        
        draw.SimpleText("Pro Tips", "NaiFont_Bold", 38, 18, Theme.textBright)
        
        local tips = {
            "Press F7 anywhere to quickly access settings",
            "Check the Help tab for answers to common questions"
        }
        
        local y = 42
        for _, tip in ipairs(tips) do
            draw.SimpleText(tip, "NaiFont_Small", 20, y, Theme.text)
            y = y + 16
        end
    end
    
    -- Start with General panel active
    SwitchToPanel(generalPanel, generalBtn)
end

concommand.Add("nai_passengers_menu", OpenSettingsPanel)

concommand.Add("nai_npc_reset", function()
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
    RunConsoleCommand("nai_npc_hud_alert_threshold", "0.3")
    RunConsoleCommand("nai_npc_hud_fear_threshold", "0.5")
    RunConsoleCommand("nai_npc_hud_drowsy_threshold", "0.7")
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
end)

-- Spawn menu entry
hook.Add("PopulateToolMenu", "NaiNPCPassengerOptions", function()
    spawnmenu.AddToolMenuOption("Utilities", "Nai's Addons", "NPCPassengers", "NPC Passengers", "", "", function(panel)
        panel:ClearControls()
        
        panel:Help("NPC Passengers lets friendly NPCs ride in your vehicles!")
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
hook.Add("PopulateMenuBar", "NaiNPCPassengersMenuBar", function(menubar)
    local m = menubar:AddOrGetMenu("NPC Passengers")
    
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
        net.Start("NaiMakePassenger")
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
        net.Start("NaiMakeDriver")
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
        chat.AddText(Color(100, 200, 100), "[NPC Passengers] ", Color(255, 255, 255), "NPC selected! Now right-click on a vehicle and select 'Add Selected NPC'")
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
            net.Start("NaiMakePassengerForVehicle")
                net.WriteEntity(selectedNPCForVehicle)
                net.WriteEntity(ent)
            net.SendToServer()
            chat.AddText(Color(100, 200, 100), "[NPC Passengers] ", Color(255, 255, 255), "Adding NPC to vehicle...")
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
        chat.AddText(Color(255, 200, 100), "[NPC Passengers] ", Color(255, 255, 255), "NPC selection cancelled")
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
        net.Start("NaiRemovePassenger")
            net.WriteEntity(ent)
        net.SendToServer()
    end
})

-- F7 hotkey
hook.Add("PlayerButtonDown", "NaiPassengersQuickMenu", function(ply, button)
    if button == KEY_F7 and IsFirstTimePredicted() then
        OpenSettingsPanel()
    end
end)

-- C menu icon (top left corner)
list.Set("DesktopWindows", "NaiNPCPassengers", {
    title = "NPC Passengers",
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
        draw.SimpleText("NPC Passengers", "NaiFont_Title", 15, 22, Theme.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
        draw.SimpleText("✕", "NaiFont_Large", w/2, h/2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
    settingsBtn:SetTextColor(Theme.textBright)
    settingsBtn.hoverAnim = 0
    settingsBtn.Paint = function(self, w, h)
        if self:IsHovered() then
            self.hoverAnim = math.Approach(self.hoverAnim, 1, FrameTime() * 5)
        else
            self.hoverAnim = math.Approach(self.hoverAnim, 0, FrameTime() * 5)
        end
        local bgColor = LerpColor(self.hoverAnim, Theme.accent, Theme.accentHover)
        if self:IsDown() then bgColor = Theme.accentActive end
        draw.RoundedBox(6, 0, 0, w, h, bgColor)
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
    changelog:SetTall(170)
    changelog:Dock(TOP)
    changelog:DockMargin(0, 0, 0, 10)
    changelog.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Theme.bgDark)
        local changes = {
            "+ Passenger status system: CALM/ALERT/SCARED/DROWSY/DEAD",
            "+ Crash damage with realistic injury system",
            "+ Dead body management (Hold R to remove)",
            "+ Advanced body physics: sway, flinch, drowsy states",
            "+ Real-time passenger HUD",
            "+ Modern settings UI with help system",
            "+ Make Passenger For Vehicle context option",
            "* Improved vehicle compatibility (Simfphys/LVS/SligWolf)",
            "* Enhanced NPC look system with threat tracking",
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
            draw.SimpleText("✓", "NaiFont_Normal", w/2, h/2, Theme.textBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
    okBtn:SetTextColor(Theme.textBright)
    okBtn.hoverAnim = 0
    okBtn.Paint = function(self, w, h)
        if self:IsHovered() then
            self.hoverAnim = math.Approach(self.hoverAnim, 1, FrameTime() * 5)
        else
            self.hoverAnim = math.Approach(self.hoverAnim, 0, FrameTime() * 5)
        end
        local bgColor = LerpColor(self.hoverAnim, Theme.success, Color(100, 200, 120))
        if self:IsDown() then bgColor = Color(60, 160, 80) end
        draw.RoundedBox(6, 0, 0, w, h, bgColor)
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
hook.Add("InitPostEntity", "NaiPassengersWelcome", function()
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
    
    local alertLevel = npc:GetNWFloat("NaiAlertLevel", 0)
    local fearLevel = npc:GetNWFloat("NaiFearLevel", 0)
    local isDrowsy = npc:GetNWBool("NaiIsDrowsy", false)
    local calmTime = npc:GetNWFloat("NaiCalmTime", 0)
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
            calm = "●",
            alert = "!",
            scared = "⚠",
            drowsy = "Z",
            dead = "✕",
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

net.Receive("NaiPassengers_EjectPrompt", function()
    ejectPromptData.count = net.ReadInt(8)
    ejectPromptData.lookingAt = net.ReadBool()
    ejectPromptData.showTime = CurTime()
end)

-- Detect R key HOLD to eject dead passengers
hook.Add("Think", "NaiPassengers_EjectKeyCheck", function()
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
                net.Start("NaiPassengers_EjectDead")
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
hook.Add("HUDPaint", "NaiPassengers_EjectPrompt", function()
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
    draw.SimpleText("💀", "DermaLarge", centerX, boxY + 20, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
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

hook.Add("HUDPaint", "NaiPassengers_StatusHUD", function()
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
            if IsValid(ent) and ent:IsNPC() and ent:GetNWBool("IsNaiPassenger", false) then
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

-- NPC Driver Debug HUD
hook.Add("HUDPaint", "NaiPassengers_DriverDebug", function()
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
        
        draw.SimpleText("🚗 NPC Driver", "DermaDefault", screenPos.x, screenPos.y - 40, Color(100, 200, 255), TEXT_ALIGN_CENTER)
        draw.SimpleText("Speed: " .. speed .. " u/s", "DermaDefault", screenPos.x, screenPos.y - 25, Color(255, 255, 255), TEXT_ALIGN_CENTER)
        draw.SimpleText("NPC: " .. npc:GetClass(), "DermaDefault", screenPos.x, screenPos.y - 10, Color(200, 200, 200), TEXT_ALIGN_CENTER)
    end
end)
