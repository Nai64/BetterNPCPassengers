if NaiBase_IsKillswitchActive and NaiBase_IsKillswitchActive() then return end

surface.CreateFont("NaiBase_Title", {
    font = "Metropolis",
    size = 28,
    weight = 600
})

surface.CreateFont("NaiBase_Large", {
    font = "Metropolis",
    size = 20,
    weight = 500
})

surface.CreateFont("NaiBase_Default", {
    font = "Metropolis",
    size = 16,
    weight = 400
})

surface.CreateFont("NaiBase_Small", {
    font = "Metropolis",
    size = 14,
    weight = 400
})

hook.Add("InitPostEntity", "NaiBase_InitGUI", function()
    timer.Simple(1, function()
        if not NaiBase then
            print("[Nai's Base GUI] Base system not found!")
            return
        end
        
        print("[Nai's Base GUI] GUI system loaded")
    end)
end)

local Icons = {
    modules = Material("icon16/package.png"),
    settings = Material("icon16/cog.png"),
    events = Material("icon16/transmit.png"),
    data = Material("icon16/database.png"),
    optimizer = Material("icon16/lightning.png"),
    resources = Material("icon16/chart_bar.png"),
    audio = Material("icon16/sound.png"),
    benchmark = Material("icon16/time.png"),
    logger = Material("icon16/page_white_text.png"),
    advanced = Material("icon16/chart_line.png"),
    help = Material("icon16/help.png"),
    about = Material("icon16/information.png")
}

local function LerpColor(t, col1, col2)
    return Color(
        Lerp(t, col1.r, col2.r),
        Lerp(t, col1.g, col2.g),
        Lerp(t, col1.b, col2.b),
        Lerp(t, col1.a or 255, col2.a or 255)
    )
end

local GUI_Colors = {
    Background = Color(30, 30, 35),
    Sidebar = Color(25, 25, 30),
    Header = Color(40, 40, 45),
    Accent = Color(100, 200, 255),
    Text = Color(255, 255, 255),
    TextDark = Color(150, 150, 150),
    ButtonHover = Color(50, 50, 55),
    Success = Color(100, 255, 100),
    Warning = Color(255, 200, 100),
    Error = Color(255, 100, 100)
}

local CurrentPage = "modules"

function NaiBase.OpenGUI()
    if not NaiBase then
        chat.AddText(Color(255, 100, 100), "[Nai's Base] ", Color(255, 255, 255), "Base system not loaded!")
        return
    end
    
    if IsValid(NaiBase.Frame) then
        NaiBase.Frame:Remove()
    end
    
    local frame = vgui.Create("DFrame")
    frame:SetSize(900, 600)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    NaiBase.Frame = frame
    
    frame.Paint = function(self, w, h)
        draw.RoundedBox(0, 4, 4, w, h, Color(0, 0, 0, 100))
        
        draw.RoundedBox(0, 0, 0, w, h, GUI_Colors.Background)
        
        draw.RoundedBox(0, 0, 0, w, 50, GUI_Colors.Header)
        
        for i = 0, 50 do
            local alpha = 50 - i
            surface.SetDrawColor(ColorAlpha(GUI_Colors.Accent, alpha))
            surface.DrawLine(0, i, w, i)
        end
        
        draw.SimpleText("Nai's Base Manager", "NaiBase_Title", 17, 12, Color(0, 0, 0, 80), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Nai's Base Manager", "NaiBase_Title", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        local versionText = "v" .. (NaiBase.Version or "1.0.0")
        local vw = surface.GetTextSize(versionText) * 0.7
        draw.RoundedBox(8, 13, 36, vw + 12, 18, Color(20, 20, 25))
        draw.SimpleText(versionText, "NaiBase_Small", 19, 38, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("X")
    closeBtn:SetPos(frame:GetWide() - 40, 10)
    closeBtn:SetSize(30, 30)
    closeBtn:SetFont("NaiBase_Large")
    closeBtn:SetTextColor(GUI_Colors.Text)
    closeBtn.HoverLerp = 0
    closeBtn.Paint = function(self, w, h)
        local hoverTarget = self:IsHovered() and 1 or 0
        self.HoverLerp = Lerp(FrameTime() * 10, self.HoverLerp, hoverTarget)
        
        if self.HoverLerp > 0 then
            local rotAngle = self.HoverLerp * 90
            draw.NoTexture()
            surface.SetDrawColor(ColorAlpha(Color(255, 100, 100), 255 * self.HoverLerp))
            
            local centerX, centerY = w/2, h/2
            local size = w * 0.8
            draw.RoundedBox(6, (w - size)/2, (h - size)/2, size, size, ColorAlpha(Color(255, 100, 100), 200 * self.HoverLerp))
        end
    end
    closeBtn.DoClick = function()
        frame:Remove()
    end
    
    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(0, 50)
    sidebar:SetSize(180, frame:GetTall() - 50)
    sidebar.Paint = function(self, w, h)
        draw.RoundedBox(0, 0, 0, w, h, GUI_Colors.Sidebar)
    end
    
    local content = vgui.Create("DPanel", frame)
    content:SetPos(180, 50)
    content:SetSize(frame:GetWide() - 180, frame:GetTall() - 50)
    content.Paint = function(self, w, h)
        surface.SetDrawColor(GUI_Colors.Sidebar)
        surface.DrawLine(0, 0, 0, h)
    end
    
    local pages = {
        {name = "Modules", id = "modules", icon = Icons.modules},
        {name = "Settings", id = "settings", icon = Icons.settings},
        {name = "Events", id = "events", icon = Icons.events},
        {name = "Data", id = "data", icon = Icons.data},
        {name = "Optimizer", id = "optimizer", icon = Icons.optimizer},
        {name = "Resources", id = "resources", icon = Icons.resources},
        {name = "Audio", id = "audio", icon = Icons.audio},
        {name = "Benchmark", id = "benchmark", icon = Icons.benchmark},
        {name = "Logger", id = "logger", icon = Icons.logger},
        {name = "Advanced", id = "advanced", icon = Icons.advanced},
        {name = "Help", id = "help", icon = Icons.help},
        {name = "About", id = "about", icon = Icons.about}
    }
    
    local function CreatePage(pageId)
        content:Clear()
        CurrentPage = pageId
        
        if pageId == "modules" then
            NaiBase.CreateModulesPage(content)
        elseif pageId == "settings" then
            NaiBase.CreateSettingsPage(content)
        elseif pageId == "events" then
            NaiBase.CreateEventsPage(content)
        elseif pageId == "data" then
            NaiBase.CreateDataPage(content)
        elseif pageId == "optimizer" then
            NaiBase.CreateOptimizerPage(content)
        elseif pageId == "resources" then
            NaiBase.CreateResourcesPage(content)
        elseif pageId == "audio" then
            NaiBase.CreateAudioPage(content)
        elseif pageId == "benchmark" then
            NaiBase.CreateBenchmarkPage(content)
        elseif pageId == "logger" then
            NaiBase.CreateLoggerPage(content)
        elseif pageId == "advanced" then
            NaiBase.CreateAdvancedPage(content)
        elseif pageId == "help" then
            NaiBase.CreateHelpPage(content)
        elseif pageId == "about" then
            NaiBase.CreateAboutPage(content)
        end
    end
    
    local yPos = 10
    for _, page in ipairs(pages) do
        local btn = vgui.Create("DButton", sidebar)
        btn:SetPos(10, yPos)
        btn:SetSize(160, 40)
        btn:SetText("")
        
        local pageIcon = page.icon
        btn.HoverLerp = 0
        btn.AccentLerp = 0
        
        btn.Paint = function(self, w, h)
            local isActive = CurrentPage == page.id
            local targetHover = self:IsHovered() and 1 or 0
            local targetAccent = isActive and 1 or 0
            
            self.HoverLerp = Lerp(FrameTime() * 8, self.HoverLerp, targetHover)
            self.AccentLerp = Lerp(FrameTime() * 10, self.AccentLerp, targetAccent)
            
            local bgAlpha = 0 + (55 * self.HoverLerp) + (55 * self.AccentLerp)
            local bgColor = Color(50 + bgAlpha * 0.2, 50 + bgAlpha * 0.2, 55 + bgAlpha * 0.2, 255)
            
            local slideOffset = 8 * self.HoverLerp
            
            draw.RoundedBox(6, 2 + slideOffset, 2, w, h, Color(0, 0, 0, 30))
            
            if isActive or self:IsHovered() then
                draw.RoundedBoxEx(6, slideOffset, 0, w, h, bgColor, false, true, false, true)
            end
            
            if self.AccentLerp > 0 then
                local accentWidth = 4 * self.AccentLerp
                draw.RoundedBox(0, 0, 0, accentWidth, h, GUI_Colors.Accent)
            end
            
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(pageIcon)
            surface.DrawTexturedRect(12 + slideOffset, h/2 - 8, 16, 16)
            
            draw.SimpleText(page.name, "NaiBase_Default", 35 + slideOffset, h/2, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        
        btn.DoClick = function()
            CreatePage(page.id)
        end
        
        yPos = yPos + 45
    end
    
    CreatePage(CurrentPage)
end

function NaiBase.CreateModulesPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 10)
    header:SetTall(45)
    header.Paint = function(self, w, h)
        draw.SimpleText("Loaded Modules", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(table.Count(NaiBase.Modules) .. " modules active", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    for name, module in pairs(NaiBase.Modules) do
        local modulePanel = vgui.Create("DPanel", scroll)
        modulePanel:Dock(TOP)
        modulePanel:DockMargin(0, 0, 0, 10)
        modulePanel:SetTall(100)
        modulePanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 2, 2, w, h, Color(0, 0, 0, 50))
            
            draw.RoundedBox(6, 0, 0, w, h, GUI_Colors.Header)
            
            if module.loaded then
                draw.RoundedBox(0, 0, 0, 3, h, GUI_Colors.Success)
            end
            
            local iconMat = Material(module.icon or "icon16/package.png")
            if iconMat and not iconMat:IsError() then
                surface.SetDrawColor(GUI_Colors.Accent)
                surface.SetMaterial(iconMat)
                surface.DrawTexturedRect(15, 12, 24, 24)
            end
            
            draw.SimpleText(name, "NaiBase_Large", 48, 11, Color(0, 0, 0, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(name, "NaiBase_Large", 47, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            draw.SimpleText("Version: " .. module.version, "NaiBase_Small", 47, 36, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText("Author: " .. module.author, "NaiBase_Small", 15, 52, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(module.description, "NaiBase_Default", 15, 72, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            local statusText = module.loaded and "ACTIVE" or "INACTIVE"
            local statusColor = module.loaded and GUI_Colors.Success or GUI_Colors.Error
            local badgeW = 70
            local badgeH = 22
            local badgeX = w - badgeW - 10
            local badgeY = 12
            
            draw.RoundedBox(4, badgeX, badgeY, badgeW, badgeH, Color(20, 20, 25))
            
            draw.RoundedBox(4, badgeX + 8, badgeY + 8, 6, 6, statusColor)
            
            draw.SimpleText(statusText, "NaiBase_Small", badgeX + 20, badgeY + 11, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    
    if table.Count(NaiBase.Modules) == 0 then
        local noModules = vgui.Create("DLabel", scroll)
        noModules:Dock(TOP)
        noModules:SetText("No modules loaded yet.")
        noModules:SetFont("NaiBase_Large")
        noModules:SetTextColor(GUI_Colors.TextDark)
        noModules:SetContentAlignment(5)
        noModules:SetTall(100)
    end
end

function NaiBase.CreateSettingsPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 15)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Global Settings", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Configure Nai's Base and loaded modules", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        draw.RoundedBox(4, 0, 48, w, 18, ColorAlpha(GUI_Colors.Header, 100))
        draw.SimpleText("Quick Actions:", "NaiBase_Small", 8, 51, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local actionBar = vgui.Create("DPanel", header)
    actionBar:SetPos(110, 48)
    actionBar:SetSize(600, 18)
    actionBar.Paint = function() end
    
    local function CreateQuickButton(text, x, callback)
        local btn = vgui.Create("DButton", actionBar)
        btn:SetPos(x, 0)
        btn:SetSize(100, 18)
        btn:SetText(text)
        btn:SetFont("NaiBase_Small")
        btn:SetTextColor(GUI_Colors.Text)
        btn.hoverAnim = 0
        btn.Paint = function(self, w, h)
            local target = self:IsHovered() and 1 or 0
            self.hoverAnim = Lerp(FrameTime() * 8, self.hoverAnim, target)
            
            local col = LerpColor(self.hoverAnim, ColorAlpha(GUI_Colors.Header, 150), GUI_Colors.Accent)
            draw.RoundedBox(3, 0, 0, w, h, col)
        end
        btn.DoClick = callback
        return btn
    end
    
    CreateQuickButton("Export All", 0, function()
        local json = NaiBase.ExportConfigs()
        SetClipboardText(json)
        chat.AddText(GUI_Colors.Accent, "[NaiBase] ", color_white, "Configs exported to clipboard!")
    end)
    
    CreateQuickButton("Import", 110, function()
        Derma_StringRequest("Import Configs", "Paste JSON config data:", "", function(text)
            if NaiBase.ImportConfigs(text) then
                chat.AddText(GUI_Colors.Success, "[NaiBase] ", color_white, "Configs imported successfully!")
                timer.Simple(0.5, function() NaiBase.OpenGUI() end) -- Refresh GUI
            else
                chat.AddText(GUI_Colors.Error, "[NaiBase] ", color_white, "Import failed - invalid JSON")
            end
        end)
    end)
    
    CreateQuickButton("Reset All", 220, function()
        Derma_Query("Reset all settings to defaults?", "Confirm Reset", 
            "Reset", function()
                for moduleName, _ in pairs(NaiBase.ConfigDefaults) do
                    NaiBase.ResetModuleConfigs(moduleName)
                end
                chat.AddText(GUI_Colors.Success, "[NaiBase] ", color_white, "All configs reset!")
                timer.Simple(0.5, function() NaiBase.OpenGUI() end)
            end,
            "Cancel")
    end)
    
    local debugPanel = vgui.Create("DPanel", scroll)
    debugPanel:Dock(TOP)
    debugPanel:DockMargin(0, 0, 0, 10)
    debugPanel:SetTall(50)
    debugPanel.hoverAnim = 0
    debugPanel.Paint = function(self, w, h)
        local hoverTarget = self:IsHovered() and 1 or 0
        self.hoverAnim = Lerp(FrameTime() * 8, self.hoverAnim, hoverTarget)
        
        draw.RoundedBox(8, 2, 2, w, h, Color(0, 0, 0, 50))
        
        local brightness = 40 + (5 * self.hoverAnim)
        draw.RoundedBox(8, 0, 0, w, h, Color(brightness, brightness, brightness + 5))
    end
    
    local checkbox = vgui.Create("DCheckBox", debugPanel)
    checkbox:SetPos(12, 15)
    checkbox:SetSize(20, 20)
    checkbox:SetConVar("naibase_debug")
    checkbox.CheckLerp = 0
    checkbox.HoverLerp = 0
    
    checkbox.Paint = function(self, w, h)
        local target = self:GetChecked() and 1 or 0
        self.CheckLerp = Lerp(FrameTime() * 10, self.CheckLerp, target)
        
        local hoverTarget = (self:IsHovered() or debugPanel:IsHovered()) and 1 or 0
        self.HoverLerp = Lerp(FrameTime() * 8, self.HoverLerp, hoverTarget)
        
        draw.RoundedBox(4, 1, 1, w, h, Color(0, 0, 0, 80))
        
        local bgBrightness = 50 + (10 * self.HoverLerp)
        draw.RoundedBox(4, 0, 0, w, h, Color(bgBrightness, bgBrightness, bgBrightness + 5))
        
        local borderColor = self:GetChecked() and GUI_Colors.Accent or Color(100, 100, 105)
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
        
        if self.CheckLerp > 0 then
            local fillColor = ColorAlpha(GUI_Colors.Accent, 255 * self.CheckLerp)
            draw.RoundedBox(2, 3, 3, w - 6, h - 6, fillColor)
            
            if self.CheckLerp > 0.3 then
                surface.SetDrawColor(255, 255, 255, 255 * self.CheckLerp)
                local cx, cy = w/2, h/2
                surface.DrawLine(cx - 6, cy, cx - 2, cy + 4)
                surface.DrawLine(cx - 6, cy - 1, cx - 2, cy + 3)
                surface.DrawLine(cx - 2, cy + 4, cx + 6, cy - 4)
                surface.DrawLine(cx - 2, cy + 3, cx + 6, cy - 5)
            end
        end
        
        if self.HoverLerp > 0 then
            draw.RoundedBox(4, -2, -2, w + 4, h + 4, ColorAlpha(GUI_Colors.Accent, 30 * self.HoverLerp))
        end
    end
    
    checkbox.OnChange = function(self, val)
        NaiBase.SetConfig("debug_mode", val, "global")
    end
    
    local label = vgui.Create("DLabel", debugPanel)
    label:SetPos(40, 10)
    label:SetFont("NaiBase_Default")
    label:SetTextColor(GUI_Colors.Text)
    label:SetText("Debug Mode")
    label:SizeToContents()
    label:SetMouseInputEnabled(true)
    label:SetCursor("hand")
    label.DoClick = function()
        checkbox:Toggle()
    end
    
    local desc = vgui.Create("DLabel", debugPanel)
    desc:SetPos(40, 28)
    desc:SetFont("NaiBase_Small")
    desc:SetTextColor(GUI_Colors.TextDark)
    desc:SetText("Enable verbose logging for debugging")
    desc:SizeToContents()
    
    debugPanel.OnMousePressed = function()
        checkbox:Toggle()
    end
    
    local modulesHeader = vgui.Create("DLabel", scroll)
    modulesHeader:Dock(TOP)
    modulesHeader:DockMargin(0, 20, 0, 10)
    modulesHeader:SetText("Module Settings")
    modulesHeader:SetFont("NaiBase_Large")
    modulesHeader:SetTextColor(GUI_Colors.Text)
    modulesHeader:SetTall(28)
    
    for moduleName, _ in pairs(NaiBase.Modules) do
        local configMeta = NaiBase.GetModuleConfigMeta and NaiBase.GetModuleConfigMeta(moduleName) or {}
        local hasConfigs = false
        
        for _ in pairs(configMeta) do
            hasConfigs = true
            break
        end
        
        if not hasConfigs and NaiBase.Config[moduleName] and table.Count(NaiBase.Config[moduleName]) > 0 then
            hasConfigs = true
        end
        
        if hasConfigs then
            local modulePanel = vgui.Create("DCollapsibleCategory", scroll)
            modulePanel:Dock(TOP)
            modulePanel:DockMargin(0, 0, 0, 5)
            
            local totalSettings = 0
            for _ in pairs(configMeta) do
                totalSettings = totalSettings + 1
            end
            for _ in pairs(NaiBase.Config[moduleName] or {}) do
                totalSettings = totalSettings + 1
            end
            
            modulePanel:SetLabel(moduleName .. " (" .. totalSettings .. " settings)")
            modulePanel:SetExpanded(false)
            
            local moduleScroll = vgui.Create("DScrollPanel")
            moduleScroll:DockMargin(5, 5, 5, 5)
            moduleScroll:SetTall(400)
            
            local resetBtn = vgui.Create("DButton", moduleScroll)
            resetBtn:Dock(TOP)
            resetBtn:DockMargin(5, 5, 5, 10)
            resetBtn:SetTall(24)
            resetBtn:SetText("Reset " .. moduleName .. " to Defaults")
            resetBtn:SetFont("NaiBase_Small")
            resetBtn:SetTextColor(GUI_Colors.Text)
            resetBtn.hoverAnim = 0
            resetBtn.Paint = function(self, w, h)
                local target = self:IsHovered() and 1 or 0
                self.hoverAnim = Lerp(FrameTime() * 8, self.hoverAnim, target)
                
                local col = LerpColor(self.hoverAnim, ColorAlpha(GUI_Colors.Header, 200), ColorAlpha(GUI_Colors.Error, 200))
                draw.RoundedBox(4, 0, 0, w, h, col)
            end
            resetBtn.DoClick = function()
                NaiBase.ResetModuleConfigs(moduleName)
                chat.AddText(GUI_Colors.Success, "[NaiBase] ", color_white, moduleName .. " configs reset!")
                timer.Simple(0.2, function() NaiBase.OpenGUI() end)
            end
            
            if table.Count(configMeta) > 0 then
                for categoryName, settings in pairs(configMeta) do
                    local catHeader = vgui.Create("DPanel", moduleScroll)
                    catHeader:Dock(TOP)
                    catHeader:DockMargin(5, 5, 5, 5)
                    catHeader:SetTall(24)
                    catHeader.Paint = function(self, w, h)
                        draw.RoundedBox(4, 0, 0, w, h, ColorAlpha(GUI_Colors.Accent, 100))
                        draw.SimpleText(categoryName, "NaiBase_Default", 8, h/2, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                    
                    for _, meta in ipairs(settings) do
                        if not meta.hidden then
                            local settingPanel = vgui.Create("DPanel", moduleScroll)
                            settingPanel:Dock(TOP)
                            settingPanel:DockMargin(8, 2, 8, 2)
                            settingPanel:SetTall(meta.description ~= "" and 50 or 30)
                            settingPanel.Paint = function(self, w, h)
                                draw.RoundedBox(4, 0, 0, w, h, ColorAlpha(GUI_Colors.Header, 150))
                                
                                draw.SimpleText(meta.displayName, "NaiBase_Small", 8, 6, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                                
                                if meta.description ~= "" then
                                    draw.SimpleText(meta.description, "NaiBase_Small", 8, 22, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                                end
                                
                                local currentVal = NaiBase.GetConfig(meta.key, meta.default, moduleName)
                                local valStr = tostring(currentVal)
                                if meta.valueType == "boolean" then
                                    valStr = currentVal and "âœ“ Enabled" or "âœ— Disabled"
                                end
                                draw.SimpleText(valStr, "NaiBase_Small", w - 8, 6, meta.readonly and GUI_Colors.TextDark or GUI_Colors.Accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                                
                                if meta.readonly then
                                    draw.SimpleText("[Read-Only]", "NaiBase_Small", w - 8, 22, Color(150, 150, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                                elseif meta.requiresRestart then
                                    draw.SimpleText("[Restart Required]", "NaiBase_Small", w - 8, 22, GUI_Colors.Warning, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                                end
                            end
                        end
                    end
                end
            else
                for key, value in pairs(NaiBase.Config[moduleName] or {}) do
                    local configItem = vgui.Create("DLabel", moduleScroll)
                    configItem:SetText(key .. " = " .. tostring(value))
                    configItem:SetFont("NaiBase_Small")
                    configItem:SetTextColor(GUI_Colors.TextDark)
                    configItem:Dock(TOP)
                    configItem:SetTall(22)
                    configItem:DockMargin(5, 2, 5, 2)
                end
            end
            
            modulePanel:SetContents(moduleScroll)
        end
    end
end

function NaiBase.CreateEventsPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(45)
    header.Paint = function(self, w, h)
        local discovered = NaiBase.GetDiscoveredEvents and NaiBase.GetDiscoveredEvents() or {}
        local totalEvents = table.Count(discovered)
        draw.SimpleText("Discovered Events", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(totalEvents .. " events auto-discovered", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local discovered = NaiBase.GetDiscoveredEvents and NaiBase.GetDiscoveredEvents() or {}
    
    for eventName, eventData in pairs(discovered) do
        local eventPanel = vgui.Create("DPanel", scroll)
        eventPanel:Dock(TOP)
        eventPanel:DockMargin(0, 0, 0, 10)
        
        local listenerCount = #(eventData.listeners or {})
        local panelHeight = 70 + (listenerCount * 18)
        eventPanel:SetTall(panelHeight)
        eventPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 2, 2, w, h, Color(0, 0, 0, 50))
            
            draw.RoundedBox(6, 0, 0, w, h, GUI_Colors.Header)
            
            local iconMat = Material("icon16/transmit.png")
            surface.SetDrawColor(GUI_Colors.Accent)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(15, 12, 16, 16)
            
            draw.SimpleText(eventName, "NaiBase_Default", 38, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            local stats = string.format("%d listener(s) â€¢ Triggered %d times", listenerCount, eventData.triggerCount or 0)
            draw.SimpleText(stats, "NaiBase_Small", 38, 32, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            local yOffset = 52
            for _, listenerName in ipairs(eventData.listeners or {}) do
                draw.SimpleText("â€¢ " .. listenerName, "NaiBase_Small", 25, yOffset, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                yOffset = yOffset + 18
            end
        end
    end
    
    if table.Count(discovered) == 0 then
        local noEvents = vgui.Create("DLabel", scroll)
        noEvents:Dock(TOP)
        noEvents:SetText("No events discovered yet. Events are auto-discovered when triggered.")
        noEvents:SetFont("NaiBase_Large")
        noEvents:SetTextColor(GUI_Colors.TextDark)
        noEvents:SetContentAlignment(5)
        noEvents:SetTall(100)
    end
end

function NaiBase.CreateDataPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(45)
    header.Paint = function(self, w, h)
        local discovered = NaiBase.GetDiscoveredData and NaiBase.GetDiscoveredData() or {}
        local totalData = table.Count(discovered)
        draw.SimpleText("Discovered Data", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(totalData .. " data keys auto-discovered", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local discovered = NaiBase.GetDiscoveredData and NaiBase.GetDiscoveredData() or {}
    local groupedData = {}
    
    for dataKey, dataInfo in pairs(discovered) do
        local moduleName = dataInfo.module
        if not groupedData[moduleName] then
            groupedData[moduleName] = {}
        end
        table.insert(groupedData[moduleName], {
            key = dataInfo.key,
            type = dataInfo.type,
            category = dataInfo.category or "data",
            lastUpdated = dataInfo.lastUpdated
        })
    end
    
    for moduleName, moduleDataList in pairs(groupedData) do
        local dataPanel = vgui.Create("DCollapsibleCategory", scroll)
        dataPanel:Dock(TOP)
        dataPanel:DockMargin(0, 0, 0, 5)
        dataPanel:SetLabel(moduleName .. " (" .. table.Count(moduleDataList) .. " items)")
        dataPanel:SetExpanded(false)
        
        local dataListLayout = vgui.Create("DListLayout")
        dataListLayout:DockMargin(10, 5, 10, 5)
        
        for _, dataInfo in pairs(moduleDataList) do
            local dataItem = vgui.Create("DPanel", dataListLayout)
            dataItem:Dock(TOP)
            dataItem:SetTall(20)
            dataItem.Paint = function(self, w, h)
                draw.SimpleText(dataInfo.key .. ":", "NaiBase_Default", 5, 2, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText("[" .. dataInfo.type .. "]", "NaiBase_Small", 150, 2, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
        
        dataPanel:SetContents(dataListLayout)
    end
    
    if table.Count(NaiBase.SharedData) == 0 then
        local noData = vgui.Create("DLabel", scroll)
        noData:Dock(TOP)
        noData:SetText("No shared data yet.")
        noData:SetFont("NaiBase_Large")
        noData:SetTextColor(GUI_Colors.TextDark)
        noData:SetContentAlignment(5)
        noData:SetTall(100)
    end
end

function NaiBase.CreateHelpPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(45)
    header.Paint = function(self, w, h)
        draw.SimpleText("Help & Documentation", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Everything you need to know about Nai's Base API", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local helpSections = {
        {
            title = "Getting Started",
            items = {
                "Nai's Base is a foundation system for creating interconnected GMOD addons",
                "All registered modules share a common event system, config storage, and data exchange",
                "Use the Modules page to see what's loaded and their current status",
                "Events, Settings, and Data pages show real-time information from active modules"
            }
        },
        {
            title = "Console Commands",
            items = {
                "naibase_list - Display all registered modules with version info",
                "naibase_discover - Show all tracked events, ConVars, and data keys",
                "naibase_gui - Open this management interface",
                "lua_run NaiBase.TriggerEvent(\"name\", ...) - Manually trigger events (server)",
                "lua_run_cl NaiBase.TriggerEvent(\"name\", ...) - Trigger events (client)"
            }
        },
        {
            title = "Module Registration",
            items = {
                "NaiBase.RegisterModule(name, data) - Register your addon with the system",
                "Required fields: version, author, description",
                "Optional fields: icon (material path), realm, init (callback function)",
                "Example: NaiBase.RegisterModule(\"My Addon\", {version=\"1.0\", author=\"You\", ...})",
                "Use init callback to run code when your module loads"
            }
        },
        {
            title = "Configuration System",
            items = {
                "NaiBase.SetConfig(key, value, module) - Store configuration values",
                "NaiBase.GetConfig(key, default, module) - Retrieve config values",
                "Configs are persistent and accessible by all modules",
                "Use module parameter to namespace your configs: SetConfig(\"speed\", 100, \"MyAddon\")",
                "Listen for changes with RegisterEvent(\"NaiBase.DataChanged\", callback)"
            }
        },
        {
            title = "Event System",
            items = {
                "NaiBase.RegisterEvent(name, callback, module) - Listen for events",
                "NaiBase.TriggerEvent(name, ...) - Fire events with optional data",
                "Events are tracked and shown in the Events page with trigger counts",
                "Example: TriggerEvent(\"Player.Spawned\", ply, pos, team)",
                "Multiple modules can listen to the same event",
                "Built-in events: NaiBase.BaseLoaded, NaiBase.DataChanged, NaiBase.ModuleLoaded"
            }
        },
        {
            title = "Data Sharing",
            items = {
                "NaiBase.SetSharedData(key, value, module) - Share data between modules",
                "NaiBase.GetSharedData(key, module) - Access shared data from any module",
                "Perfect for exposing API functions or live statistics",
                "Example: SetSharedData(\"player_count\", 10, \"MyAddon\")",
                "Data is tracked in real-time and displayed on the Data page"
            }
        },
        {
            title = "Debugging & Logging",
            items = {
                "NaiBase.Log(message, color) - Print colored console messages",
                "NaiBase.LogError(message) - Print error messages with ErrorNoHalt",
                "NaiBase.LogSuccess(message) - Print success messages in green",
                "NaiBase.LogWarning(message) - Print warning messages in yellow",
                "NaiBase.Debug(message, module) - Print debug info (only when debug mode enabled)",
                "Enable debug: NaiBase.SetConfig(\"debug_mode\", true, \"global\")"
            }
        },
        {
            title = "Advanced Features",
            items = {
                "Module icons: Use icon16/*.png materials for visual identification",
                "Realm detection: Modules auto-detect SERVER/CLIENT/SHARED",
                "Version checking: NaiBase.Version contains current API version",
                "Module queries: NaiBase.GetModule(name), IsModuleLoaded(name)",
                "ConVar tracking: Modules can register their ConVars for GUI display",
                "Centralized management: All modules in one interface"
            }
        },
        {
            title = "Best Practices",
            items = {
                "Always check if NaiBase exists: if NaiBase then ... end",
                "Use descriptive event names: \"Addon.ActionPerformed\" format",
                "Namespace your configs with module names to avoid conflicts",
                "Trigger events at key moments in your addon's lifecycle",
                "Update shared data when important values change",
                "Use icons for better visual distinction in the Modules list",
                "Document your events and shared data for other developers"
            }
        }
    }
    
    for _, section in ipairs(helpSections) do
        local sectionPanel = vgui.Create("DPanel", scroll)
        sectionPanel:Dock(TOP)
        sectionPanel:DockMargin(0, 0, 0, 15)
        sectionPanel:SetTall(50 + (#section.items * 20))
        sectionPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, GUI_Colors.Header)
            draw.SimpleText(section.title, "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            
            local yOffset = 36
            for _, item in ipairs(section.items) do
                draw.SimpleText("â€¢ " .. item, "NaiBase_Small", 25, yOffset, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                yOffset = yOffset + 20
            end
        end
    end
end

function NaiBase.CreateResourcesPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Resource Monitor", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("System resource tracking and analysis", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local statsPanel = vgui.Create("DPanel", scroll)
    statsPanel:Dock(TOP)
    statsPanel:DockMargin(0, 0, 0, 15)
    statsPanel:SetTall(180)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Live Resources", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetResourceData then
            local data = NaiBase.GetResourceData()
            local yPos = 40
            local spacing = 25
            
            local fps = math.floor(1 / FrameTime())
            local fpsColor = fps > 60 and GUI_Colors.Success or (fps > 30 and GUI_Colors.Warning or GUI_Colors.Error)
            draw.SimpleText("FPS: " .. fps, "NaiBase_Default", 15, yPos, fpsColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            draw.SimpleText(string.format("Memory: %.1f MB / Peak: %.1f MB", data.memory.current / 1024, data.memory.peak / 1024), "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            local entColor = data.entities.count > 1000 and GUI_Colors.Warning or GUI_Colors.Text
            draw.SimpleText("Entities: " .. data.entities.count .. " / " .. data.entities.limit, "NaiBase_Default", 15, yPos, entColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            local pingColor = data.network.ping > 100 and GUI_Colors.Error or GUI_Colors.Success
            draw.SimpleText("Network: Ping " .. data.network.ping .. "ms, Loss " .. string.format("%.1f%%", data.network.loss), "NaiBase_Default", 15, yPos, pingColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Resource Monitor module not loaded", "NaiBase_Default", 15, 40, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    
    local controlPanel = vgui.Create("DPanel", scroll)
    controlPanel:Dock(TOP)
    controlPanel:DockMargin(0, 0, 0, 15)
    controlPanel:SetTall(100)
    controlPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Display Control", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local overlayCheck = vgui.Create("DCheckBoxLabel", controlPanel)
    overlayCheck:SetPos(15, 40)
    overlayCheck:SetText("Show On-Screen Overlay")
    overlayCheck:SetValue(NaiBase.GetConfig("show_overlay", false, "Resource Monitor"))
    overlayCheck:SetTextColor(GUI_Colors.Text)
    overlayCheck.OnChange = function(self, val)
        NaiBase.SetConfig("show_overlay", val, "Resource Monitor")
    end
    
    local cmdBtn = vgui.Create("DButton", controlPanel)
    cmdBtn:SetPos(15, 65)
    cmdBtn:SetSize(150, 25)
    cmdBtn:SetText("View Entity Breakdown")
    cmdBtn:SetTextColor(GUI_Colors.Text)
    cmdBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Accent or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    cmdBtn.DoClick = function()
        RunConsoleCommand("naibase_entity_breakdown")
    end
end

function NaiBase.CreateAudioPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Audio Manager", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Advanced audio control and optimization", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local statsPanel = vgui.Create("DPanel", scroll)
    statsPanel:Dock(TOP)
    statsPanel:DockMargin(0, 0, 0, 15)
    statsPanel:SetTall(120)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Audio Statistics", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetAudioStats then
            local stats = NaiBase.GetAudioStats()
            local yPos = 40
            
            draw.SimpleText("Active Sounds: " .. stats.currentSounds .. " / " .. stats.maxSounds, "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Muted Sounds: " .. stats.mutedSounds, "NaiBase_Default", 15, yPos, GUI_Colors.Warning, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Master Volume: " .. math.floor(stats.masterVolume * 100) .. "%", "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Audio Manager module not loaded", "NaiBase_Default", 15, 40, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    
    local controlPanel = vgui.Create("DPanel", scroll)
    controlPanel:Dock(TOP)
    controlPanel:DockMargin(0, 0, 0, 15)
    controlPanel:SetTall(150)
    controlPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Audio Settings", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local cullCheck = vgui.Create("DCheckBoxLabel", controlPanel)
    cullCheck:SetPos(15, 40)
    cullCheck:SetText("Distance Sound Culling")
    cullCheck:SetValue(NaiBase.GetConfig("distance_culling", true, "Audio Manager"))
    cullCheck:SetTextColor(GUI_Colors.Text)
    cullCheck.OnChange = function(self, val)
        NaiBase.SetConfig("distance_culling", val, "Audio Manager")
    end
    
    local spamCheck = vgui.Create("DCheckBoxLabel", controlPanel)
    spamCheck:SetPos(15, 65)
    spamCheck:SetText("Auto-Mute Spam Protection")
    spamCheck:SetValue(NaiBase.GetConfig("auto_mute_spam", true, "Audio Manager"))
    spamCheck:SetTextColor(GUI_Colors.Text)
    spamCheck.OnChange = function(self, val)
        NaiBase.SetConfig("auto_mute_spam", val, "Audio Manager")
    end
    
    local dopplerCheck = vgui.Create("DCheckBoxLabel", controlPanel)
    dopplerCheck:SetPos(15, 90)
    dopplerCheck:SetText("Doppler Effect (3D Audio)")
    dopplerCheck:SetValue(NaiBase.GetConfig("doppler_effect", true, "Audio Manager"))
    dopplerCheck:SetTextColor(GUI_Colors.Text)
    dopplerCheck.OnChange = function(self, val)
        NaiBase.SetConfig("doppler_effect", val, "Audio Manager")
    end
    
    local unmuteBtn = vgui.Create("DButton", controlPanel)
    unmuteBtn:SetPos(15, 115)
    unmuteBtn:SetSize(150, 25)
    unmuteBtn:SetText("Unmute All Sounds")
    unmuteBtn:SetTextColor(GUI_Colors.Text)
    unmuteBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Success or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    unmuteBtn.DoClick = function()
        RunConsoleCommand("naibase_audio_unmute_all")
        chat.AddText(GUI_Colors.Success, "[Audio] ", color_white, "All sounds unmuted")
    end
end

function NaiBase.CreateBenchmarkPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Benchmark Tool", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Performance testing and analysis", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local statusPanel = vgui.Create("DPanel", scroll)
    statusPanel:Dock(TOP)
    statusPanel:DockMargin(0, 0, 0, 15)
    statusPanel:SetTall(100)
    statusPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Benchmark Status", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.IsBenchmarkRunning and NaiBase.IsBenchmarkRunning() then
            draw.SimpleText("Status: RUNNING", "NaiBase_Default", 15, 40, GUI_Colors.Warning, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Status: Ready", "NaiBase_Default", 15, 40, GUI_Colors.Success, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        
        if NaiBase.GetBenchmarkResults then
            local results = NaiBase.GetBenchmarkResults()
            if table.Count(results) > 0 then
                draw.SimpleText("Last run: " .. table.Count(results) .. " tests completed", "NaiBase_Small", 15, 65, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
    end
    
    local controlPanel = vgui.Create("DPanel", scroll)
    controlPanel:Dock(TOP)
    controlPanel:DockMargin(0, 0, 0, 15)
    controlPanel:SetTall(100)
    controlPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Run Benchmarks", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local runBtn = vgui.Create("DButton", controlPanel)
    runBtn:SetPos(15, 40)
    runBtn:SetSize(150, 25)
    runBtn:SetText("Run Full Benchmark")
    runBtn:SetTextColor(GUI_Colors.Text)
    runBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Accent or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    runBtn.DoClick = function()
        if NaiBase.RunBenchmark then
            NaiBase.RunBenchmark()
            chat.AddText(GUI_Colors.Accent, "[Benchmark] ", color_white, "Starting full benchmark suite...")
        end
    end
    
    local resultsBtn = vgui.Create("DButton", controlPanel)
    resultsBtn:SetPos(175, 40)
    resultsBtn:SetSize(150, 25)
    resultsBtn:SetText("View Results")
    resultsBtn:SetTextColor(GUI_Colors.Text)
    resultsBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Success or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    resultsBtn.DoClick = function()
        RunConsoleCommand("naibase_benchmark_results")
    end
    
    local listBtn = vgui.Create("DButton", controlPanel)
    listBtn:SetPos(335, 40)
    listBtn:SetSize(150, 25)
    listBtn:SetText("List Tests")
    listBtn:SetTextColor(GUI_Colors.Text)
    listBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Warning or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    listBtn.DoClick = function()
        RunConsoleCommand("naibase_benchmark_list")
    end
    
    local resultsPanel = vgui.Create("DPanel", scroll)
    resultsPanel:Dock(TOP)
    resultsPanel:DockMargin(0, 0, 0, 15)
    resultsPanel:SetTall(250)
    resultsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Recent Results", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetBenchmarkResults then
            local results = NaiBase.GetBenchmarkResults()
            if table.Count(results) > 0 then
                local yPos = 40
                for testId, result in pairs(results) do
                    draw.SimpleText(result.name .. ": " .. result.score .. "/sec", "NaiBase_Small", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    yPos = yPos + 20
                    if yPos > h - 30 then break end
                end
            else
                draw.SimpleText("No results yet. Run a benchmark to see results.", "NaiBase_Small", 15, 40, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
        end
    end
end

function NaiBase.CreateLoggerPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Console Logger", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Advanced console logging and search", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local statsPanel = vgui.Create("DPanel", scroll)
    statsPanel:Dock(TOP)
    statsPanel:DockMargin(0, 0, 0, 15)
    statsPanel:SetTall(150)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Logger Statistics", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetLogStats then
            local stats = NaiBase.GetLogStats()
            local yPos = 40
            
            draw.SimpleText("Total Entries: " .. stats.totalEntries, "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Errors: " .. (stats.byCategory.error or 0), "NaiBase_Default", 15, yPos, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Warnings: " .. (stats.byCategory.warning or 0), "NaiBase_Default", 15, yPos, GUI_Colors.Warning, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Info: " .. (stats.byCategory.info or 0), "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Console Logger module not loaded", "NaiBase_Default", 15, 40, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    
    local controlPanel = vgui.Create("DPanel", scroll)
    controlPanel:Dock(TOP)
    controlPanel:DockMargin(0, 0, 0, 15)
    controlPanel:SetTall(100)
    controlPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Quick Actions", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local exportBtn = vgui.Create("DButton", controlPanel)
    exportBtn:SetPos(15, 40)
    exportBtn:SetSize(120, 25)
    exportBtn:SetText("Export Logs")
    exportBtn:SetTextColor(GUI_Colors.Text)
    exportBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Accent or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    exportBtn.DoClick = function()
        RunConsoleCommand("naibase_logs_export")
        chat.AddText(GUI_Colors.Success, "[Logger] ", color_white, "Logs exported to file")
    end
    
    local clearBtn = vgui.Create("DButton", controlPanel)
    clearBtn:SetPos(145, 40)
    clearBtn:SetSize(120, 25)
    clearBtn:SetText("Clear Logs")
    clearBtn:SetTextColor(GUI_Colors.Text)
    clearBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Error or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    clearBtn.DoClick = function()
        RunConsoleCommand("naibase_logs_clear")
        chat.AddText(GUI_Colors.Warning, "[Logger] ", color_white, "All logs cleared")
    end
    
    local errorsBtn = vgui.Create("DButton", controlPanel)
    errorsBtn:SetPos(275, 40)
    errorsBtn:SetSize(120, 25)
    errorsBtn:SetText("View Errors")
    errorsBtn:SetTextColor(GUI_Colors.Text)
    errorsBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Warning or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    errorsBtn.DoClick = function()
        RunConsoleCommand("naibase_logs_errors")
    end
    
    local enableCheck = vgui.Create("DCheckBoxLabel", controlPanel)
    enableCheck:SetPos(15, 70)
    enableCheck:SetText("Enable Logging")
    enableCheck:SetValue(NaiBase.GetConfig("enable_logging", true, "Console Logger"))
    enableCheck:SetTextColor(GUI_Colors.Text)
    enableCheck.OnChange = function(self, val)
        NaiBase.SetConfig("enable_logging", val, "Console Logger")
    end
end

function NaiBase.CreateAdvancedPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Advanced Features", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Profiling and diagnostic tools", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local fpsPanel = vgui.Create("DPanel", scroll)
    fpsPanel:Dock(TOP)
    fpsPanel:DockMargin(0, 0, 0, 15)
    fpsPanel:SetTall(140)
    fpsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("FPS Monitoring", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetFPSStats then
            local stats = NaiBase.GetFPSStats()
            local yPos = 40
            
            local fpsColor = stats.current > 60 and GUI_Colors.Success or (stats.current > 30 and GUI_Colors.Warning or GUI_Colors.Error)
            draw.SimpleText("Current: " .. stats.current .. " FPS", "NaiBase_Default", 15, yPos, fpsColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Average: " .. stats.average .. " FPS", "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 25
            
            draw.SimpleText("Range: " .. stats.min .. " - " .. stats.max .. " FPS", "NaiBase_Default", 15, yPos, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Advanced Features module not loaded", "NaiBase_Default", 15, 40, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    
    local profilingPanel = vgui.Create("DPanel", scroll)
    profilingPanel:Dock(TOP)
    profilingPanel:DockMargin(0, 0, 0, 15)
    profilingPanel:SetTall(150)
    profilingPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Profiling Tools", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local entityCheck = vgui.Create("DCheckBoxLabel", profilingPanel)
    entityCheck:SetPos(15, 40)
    entityCheck:SetText("Entity Profiling")
    entityCheck:SetValue(NaiBase.GetConfig("entity_profiling", false, "Advanced Features"))
    entityCheck:SetTextColor(GUI_Colors.Text)
    entityCheck.OnChange = function(self, val)
        NaiBase.SetConfig("entity_profiling", val, "Advanced Features")
    end
    
    local hookCheck = vgui.Create("DCheckBoxLabel", profilingPanel)
    hookCheck:SetPos(15, 65)
    hookCheck:SetText("Hook Profiling")
    hookCheck:SetValue(NaiBase.GetConfig("hook_profiling", false, "Advanced Features"))
    hookCheck:SetTextColor(GUI_Colors.Text)
    hookCheck.OnChange = function(self, val)
        NaiBase.SetConfig("hook_profiling", val, "Advanced Features")
    end
    
    local entityBtn = vgui.Create("DButton", profilingPanel)
    entityBtn:SetPos(15, 95)
    entityBtn:SetSize(150, 25)
    entityBtn:SetText("Entity Profile Results")
    entityBtn:SetTextColor(GUI_Colors.Text)
    entityBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Accent or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    entityBtn.DoClick = function()
        RunConsoleCommand("naibase_entity_profile")
    end
    
    local hookBtn = vgui.Create("DButton", profilingPanel)
    hookBtn:SetPos(175, 95)
    hookBtn:SetSize(150, 25)
    hookBtn:SetText("Hook Profile Results")
    hookBtn:SetTextColor(GUI_Colors.Text)
    hookBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Success or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    hookBtn.DoClick = function()
        RunConsoleCommand("naibase_hook_profile")
    end
    
    local alertsPanel = vgui.Create("DPanel", scroll)
    alertsPanel:Dock(TOP)
    alertsPanel:DockMargin(0, 0, 0, 15)
    alertsPanel:SetTall(120)
    alertsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Performance Alerts", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local alertCheck = vgui.Create("DCheckBoxLabel", alertsPanel)
    alertCheck:SetPos(15, 40)
    alertCheck:SetText("Enable Performance Warnings")
    alertCheck:SetValue(NaiBase.GetConfig("performance_warnings", true, "Advanced Features"))
    alertCheck:SetTextColor(GUI_Colors.Text)
    alertCheck.OnChange = function(self, val)
        NaiBase.SetConfig("performance_warnings", val, "Advanced Features")
    end
    
    local autoCheck = vgui.Create("DCheckBoxLabel", alertsPanel)
    autoCheck:SetPos(15, 65)
    autoCheck:SetText("Auto-Optimize on Lag")
    autoCheck:SetValue(NaiBase.GetConfig("auto_optimize", false, "Advanced Features"))
    autoCheck:SetTextColor(GUI_Colors.Text)
    autoCheck.OnChange = function(self, val)
        NaiBase.SetConfig("auto_optimize", val, "Advanced Features")
    end
end

function NaiBase.CreateOptimizerPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local header = vgui.Create("DPanel", scroll)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 20)
    header:SetTall(70)
    header.Paint = function(self, w, h)
        draw.SimpleText("Performance Optimizer", "NaiBase_Large", 0, 0, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Real-time performance monitoring and optimization controls", "NaiBase_Small", 0, 26, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local statsPanel = vgui.Create("DPanel", scroll)
    statsPanel:Dock(TOP)
    statsPanel:DockMargin(0, 0, 0, 15)
    statsPanel:SetTall(200)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Live Statistics", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        if NaiBase.GetOptimizationStats then
            local stats = NaiBase.GetOptimizationStats()
            local yPos = 40
            local spacing = 28
            
            draw.SimpleText("Entities Optimized: " .. stats.entitiesOptimized, "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            draw.SimpleText("Sounds Culled: " .. stats.soundsCulled, "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            draw.SimpleText("Particles Culled: " .. stats.particlesCulled, "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            draw.SimpleText(string.format("Memory Freed: %.2f KB", stats.memoryFreed), "NaiBase_Default", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + spacing
            
            local lastCleanup = math.floor(CurTime() - stats.lastCleanup)
            draw.SimpleText("Last Cleanup: " .. lastCleanup .. " seconds ago", "NaiBase_Default", 15, yPos, GUI_Colors.TextDark, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Optimizer module not loaded", "NaiBase_Default", 15, 40, GUI_Colors.Error, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    
    local actionPanel = vgui.Create("DPanel", scroll)
    actionPanel:Dock(TOP)
    actionPanel:DockMargin(0, 0, 0, 15)
    actionPanel:SetTall(60)
    actionPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Quick Actions", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    local btnX = 15
    local btnY = 35
    local btnWidth = 120
    local btnHeight = 20
    local btnSpacing = 130
    
    local cleanupBtn = vgui.Create("DButton", actionPanel)
    cleanupBtn:SetPos(btnX, btnY)
    cleanupBtn:SetSize(btnWidth, btnHeight)
    cleanupBtn:SetText("Force Cleanup")
    cleanupBtn:SetFont("NaiBase_Small")
    cleanupBtn:SetTextColor(GUI_Colors.Text)
    cleanupBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Success or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    cleanupBtn.DoClick = function()
        RunConsoleCommand("naibase_opti_cleanup")
        chat.AddText(GUI_Colors.Success, "[Optimizer] ", color_white, "Manual cleanup executed")
    end
    
    local resetBtn = vgui.Create("DButton", actionPanel)
    resetBtn:SetPos(btnX + btnSpacing, btnY)
    resetBtn:SetSize(btnWidth, btnHeight)
    resetBtn:SetText("Reset Stats")
    resetBtn:SetFont("NaiBase_Small")
    resetBtn:SetTextColor(GUI_Colors.Text)
    resetBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Warning or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    resetBtn.DoClick = function()
        RunConsoleCommand("naibase_opti_reset")
        chat.AddText(GUI_Colors.Warning, "[Optimizer] ", color_white, "Statistics reset")
    end
    
    local refreshBtn = vgui.Create("DButton", actionPanel)
    refreshBtn:SetPos(btnX + btnSpacing * 2, btnY)
    refreshBtn:SetSize(btnWidth, btnHeight)
    refreshBtn:SetText("Refresh Display")
    refreshBtn:SetFont("NaiBase_Small")
    refreshBtn:SetTextColor(GUI_Colors.Text)
    refreshBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and GUI_Colors.Accent or GUI_Colors.Sidebar
        draw.RoundedBox(4, 0, 0, w, h, col)
    end
    refreshBtn.DoClick = function()
        NaiBase.OpenGUI()
        timer.Simple(0, function()
            if IsValid(NaiBase.Frame) then
                for _, child in ipairs(NaiBase.Frame:GetChildren()) do
                    if child.GetChildren then
                        for _, subChild in ipairs(child:GetChildren()) do
                            if subChild.ClassName == "DButton" and subChild:GetText() == "Optimizer" then
                                subChild:DoClick()
                            end
                        end
                    end
                end
            end
        end)
    end
    
    local infoPanel = vgui.Create("DPanel", scroll)
    infoPanel:Dock(TOP)
    infoPanel:DockMargin(0, 0, 0, 10)
    infoPanel:SetTall(150)
    infoPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, GUI_Colors.Header)
        draw.SimpleText("Active Optimizations", "NaiBase_Default", 15, 10, GUI_Colors.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        local opts = {
            {"Entity Optimization", "entity_optimization"},
            {"Sound Culling", "sound_culling"},
            {"Particle Optimization", "particle_optimization"},
            {"Network Optimization", "network_optimization"},
            {"Physics Optimization", "physics_optimization"},
            {"Memory Management", "memory_management"}
        }
        
        local yPos = 40
        for _, opt in ipairs(opts) do
            local enabled = NaiBase.GetConfig(opt[2], true, "Performance Optimizer")
            local statusColor = enabled and GUI_Colors.Success or GUI_Colors.Error
            local statusText = enabled and "[ON] Enabled" or "[OFF] Disabled"
            
            draw.SimpleText(opt[1] .. ": ", "NaiBase_Small", 15, yPos, GUI_Colors.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(statusText, "NaiBase_Small", 200, yPos, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            yPos = yPos + 20
        end
    end
end

function NaiBase.CreateAboutPage(parent)
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 20, 20, 20)
    
    local centerPanel = vgui.Create("DPanel", scroll)
    centerPanel:Dock(TOP)
    centerPanel:SetTall(400)
    centerPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, w/2 - 200, 50, 400, 300, GUI_Colors.Header)
        
        draw.SimpleText("Nai's Base", "NaiBase_Title", w/2, 100, GUI_Colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("Base API System", "NaiBase_Large", w/2, 135, GUI_Colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        
        draw.SimpleText("Version " .. (NaiBase.Version or "1.0.0"), "NaiBase_Default", w/2, 175, GUI_Colors.TextDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        
        draw.SimpleText("A comprehensive foundation system for", "NaiBase_Default", w/2, 210, GUI_Colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("creating interconnected Garry's Mod addons", "NaiBase_Default", w/2, 232, GUI_Colors.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        
        draw.SimpleText("Features:", "NaiBase_Default", w/2, 270, GUI_Colors.Accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("Module Registration â€¢ Configuration System", "NaiBase_Small", w/2, 292, GUI_Colors.TextDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("Event Dispatcher â€¢ Data Sharing â€¢ Debug Tools", "NaiBase_Small", w/2, 310, GUI_Colors.TextDark, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

concommand.Add("naibase_gui", function()
    NaiBase.OpenGUI()
end)

list.Set("DesktopWindows", "NaiBaseManager", {
    title = "Nai's Base",
    icon = "icon64/nbic.png",
    width = 960,
    height = 700,
    onewindow = true,
    init = function(icon, window)
        window:Remove()
        NaiBase.OpenGUI()
    end
})

hook.Add("AddToolMenuTabs", "NaiBase_AddMenuTab", function()
    spawnmenu.AddToolTab("Nai's Base", "Nai's Base", "icon16/cog.png")
end)

hook.Add("AddToolMenuCategories", "NaiBase_AddMenuCategory", function()
    spawnmenu.AddToolCategory("Nai's Base", "manager", "Manager")
end)

hook.Add("PopulateToolMenu", "NaiBase_PopulateMenu", function()
    spawnmenu.AddToolMenuOption("Nai's Base", "manager", "naibase_open", "Open Manager", "", "", function(panel)
        panel:ClearControls()
        
        panel:Help("Nai's Base API System")
        panel:Help("Manage modules, settings, and configurations")
        
        panel:Button("Open Manager", "naibase_gui")
        
        panel:Help(" ")
        panel:CheckBox("Debug Mode", "naibase_debug_cvar")
        
        panel:Help(" ")
        panel:Help("Console Commands:")
        panel:Help("â€¢ naibase_list - List modules")
        panel:Help("â€¢ naibase_gui - Open manager")
    end)
end)

CreateClientConVar("naibase_debug_cvar", "0", true, false, "Enable Nai's Base debug mode")

cvars.AddChangeCallback("naibase_debug_cvar", function(convar, oldValue, newValue)
    if NaiBase then
        NaiBase.SetConfig("debug_mode", newValue == "1", "global")
    end
end, "NaiBase_DebugSync")
