-- ClassPower Core Framework
-- Modular buff management system for Turtle WoW (1.12.1)
-- Supports: Priest, Druid, Mage, Shaman (and more via modules)

ClassPower = {}
ClassPower.modules = {}
ClassPower.activeModule = nil
ClassPower.loadedModules = {}  -- Track which modules have been initialized (lazy load)
ClassPower.version = "2.0"

-- Saved Variables (Renamed from PriestPower)
CP_PerUser = CP_PerUser or {}
ClassPower_Assignments = ClassPower_Assignments or {}
ClassPower_Assignments = ClassPower_Assignments or {}
ClassPower_LegacyAssignments = ClassPower_LegacyAssignments or {}
ClassPower_TankList = ClassPower_TankList or {} -- List of {name="Name", role="MT", mark=1}

-- Global reference
ClassPower.TankList = ClassPower_TankList

-- Configuration defaults
local DEFAULT_CONFIG = {
    scanfreq = 10,
    scanperframe = 1,
    smartbuffs = 1,
    Scale = 0.7,
    ConfigScale = 0.8,
    BuffDisplayMode = "missing",  -- "always" | "timer" | "missing"
    TimerThresholdMinutes = 5,
    TimerThresholdSeconds = 0,
}

-- Prefix for addon messages
CP_PREFIX = "CLPWR"

-- Debug
CP_DebugEnabled = false

function CP_Debug(msg)
    if CP_DebugEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[CP Debug]|r "..tostring(msg))
    end
end

-----------------------------------------------------------------------------------
-- Module Registration System
-----------------------------------------------------------------------------------

function ClassPower:RegisterModule(classToken, module)
    self.modules[classToken] = module
    CP_Debug("Registered module for: "..classToken)
end

function ClassPower:GetModule(classToken)
    return self.modules[classToken]
end

function ClassPower:LoadActiveModule()
    local _, class = UnitClass("player")
    
    if self.modules[class] then
        self.activeModule = self.modules[class]
        self.playerClass = class
        
        if self.activeModule.OnLoad then
            self.activeModule:OnLoad()
        end
        self.loadedModules[class] = true  -- Mark as loaded
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r "..self.version.." loaded for |cffffffff"..class.."|r.")
        return true
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r "..self.version.." loaded. |cffff6600"..class.." module not yet implemented.|r")
        return false
    end
end

-- Lazy load a module (only called when needed)
function ClassPower:EnsureModuleLoaded(classToken)
    if self.loadedModules[classToken] then return true end
    
    local module = self.modules[classToken]
    if not module then return false end
    
    if module.OnLoad then
        CP_Debug("Lazy loading module: "..classToken)
        module:OnLoad()
    end
    self.loadedModules[classToken] = true
    return true
end

-- Switch to viewing a different module's config (for leaders/assists)
function ClassPower:SwitchViewModule(classToken)
    if not ClassPower_IsPromoted() and classToken ~= self.playerClass then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Requires leader/assist to view other classes.")
        return
    end
    
    -- Lazy load the module if not yet initialized
    if not self:EnsureModuleLoaded(classToken) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..classToken.." module not available.")
        return
    end
    
    -- Hide all other config windows
    for token, mod in pairs(self.modules) do
        if mod.ConfigWindow and mod.ConfigWindow:IsVisible() then
            mod.ConfigWindow:Hide()
        end
    end
    
    -- Show target module's config
    local module = self.modules[classToken]
    if module.ShowConfig then
        module:ShowConfig()
    elseif module.ConfigWindow then
        module.ConfigWindow:Show()
        if module.UpdateConfigGrid then
            module:UpdateConfigGrid()
        end
    end
    
    -- Hide admin window if open (DISABLED per user request)
    -- if self.AdminWindow and self.AdminWindow:IsVisible() then
    --     self.AdminWindow:Hide()
    -- end
end

function ClassPower:ShowAdminWindow()
    if not self.AdminWindow then
        self:CreateAdminWindow()
    end
    self.AdminWindow:Show()
end

-- "Unload" a module (hide UI, stop updates)
function ClassPower:CloseModule(classToken)
    local module = self.modules[classToken]
    if not module then return end
    
    -- Hide UI
    if module.ConfigWindow then
        module.ConfigWindow:Hide()
    end
    if module.BuffBar then
        module.BuffBar:Hide()
    end
    
    -- Stop updates (if not active class)
    if classToken ~= self.playerClass then
        self.loadedModules[classToken] = false
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Closed "..classToken.." module.")
end

-----------------------------------------------------------------------------------
-- Permission Helpers (Reusable)
-----------------------------------------------------------------------------------

function ClassPower_IsPromoted(name)
    if not name then name = UnitName("player") end
    
    if GetNumRaidMembers() > 0 then
        for i=1, GetNumRaidMembers() do
            local n, rank = GetRaidRosterInfo(i)
            if n == name then
                return (rank > 0)
            end
        end
    elseif GetNumPartyMembers() > 0 then
        if name == UnitName("player") then
            return IsPartyLeader()
        else
            local index = GetPartyLeaderIndex()
            if index > 0 then
                return (name == UnitName("party"..index))
            end
        end
    end
    return false
end

function ClassPower_IsLeader()
    if IsPartyLeader() then return true end
    if IsRaidLeader() then return true end
    if GetPartyLeaderIndex() == 0 then return true end
    return false
end

-----------------------------------------------------------------------------------
-- Addon Message System (Reusable)
-----------------------------------------------------------------------------------

function ClassPower_SendMessage(msg)
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(CP_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(CP_PREFIX, msg, "PARTY")
    end
end

function ClassPower_RequestSync()
    ClassPower_SendMessage("REQ")
end

-----------------------------------------------------------------------------------
-- UI Constructor Functions (Reusable)
-----------------------------------------------------------------------------------

function CP_CreateSubButton(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(24); btn:SetHeight(24)
    
    local bg = btn:CreateTexture(btn:GetName().."Background", "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture(0.1, 0.1, 0.1, 0.5)
    
    local icon = btn:CreateTexture(btn:GetName().."Icon", "OVERLAY")
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    
    local txt = btn:CreateFontString(btn:GetName().."Text", "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    txt:SetJustifyH("CENTER")
    
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    return btn
end

function CP_CreateCapabilityIcon(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(18); btn:SetHeight(18)
    
    local icon = btn:CreateTexture(btn:GetName().."Icon", "OVERLAY")
    icon:SetWidth(16); icon:SetHeight(16)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    
    local rank = btn:CreateFontString(btn:GetName().."Rank", "OVERLAY", "GameFontHighlightSmall")
    rank:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    
    btn:SetScript("OnEnter", function()
        if this.tooltipText then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.tooltipText)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    return btn
end

function CP_CreateClearButton(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(14); btn:SetHeight(14)
    btn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    btn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    local ht = btn:GetHighlightTexture()
    if ht then ht:SetBlendMode("ADD") end
    
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear Assignments")
        GameTooltip:AddLine("Requires Leader/Assist", 1, 0, 0)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    return btn
end

function CP_CreateResizeGrip(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(16); btn:SetHeight(16)
    
    btn:SetScript("OnMouseDown", function() 
        if arg1 == "LeftButton" then
            local p = this:GetParent()
            p.isResizing = true
            p.startScale = p:GetScale()
            p.cursorStartX, p.cursorStartY = GetCursorPosition()
            this:SetScript("OnUpdate", CP_OnScaleUpdate)
        end
    end)
    btn:SetScript("OnMouseUp", function() 
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
    end)
    return btn
end

function CP_OnScaleUpdate()
    local p = this:GetParent()
    if not p.isResizing then return end
    
    local cursorX, cursorY = GetCursorPosition()
    local diff = (cursorX - p.cursorStartX)
    diff = diff / UIParent:GetEffectiveScale()
    
    local newScale = p.startScale + (diff * 0.002)
    if newScale < 0.5 then newScale = 0.5 end
    if newScale > 2.0 then newScale = 2.0 end
    
    p:SetScale(newScale)
end

function CP_CreateHUDButton(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(30); btn:SetHeight(30)
    
    local icon = btn:CreateTexture(btn:GetName().."Icon", "BACKGROUND")
    icon:SetAllPoints(btn)
    
    -- Position text to the RIGHT of the button, not on top
    local txt = btn:CreateFontString(btn:GetName().."Text", "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    txt:SetJustifyH("LEFT")
    
    local nt = btn:CreateTexture(btn:GetName().."NormalTexture")
    nt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    nt:SetWidth(54); nt:SetHeight(54)
    nt:SetPoint("CENTER", btn, "CENTER", 0, -1)
    btn:SetNormalTexture(nt)
    
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function()
        if this.tooltipText then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.tooltipText)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    btn:Hide()
    return btn
end



-----------------------------------------------------------------------------------
-- Event Handler
-----------------------------------------------------------------------------------

function ClassPower_OnEvent(event)
    if event == "PLAYER_LOGIN" then
        -- Initialize saved vars
        if not CP_PerUser then
            CP_PerUser = {}
            for k, v in pairs(DEFAULT_CONFIG) do
                CP_PerUser[k] = v
            end
        end
        
        -- Load the appropriate module
        ClassPower:LoadActiveModule()
        
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == CP_PREFIX then
            -- Route to ALL loaded modules (for cross-class admin feature)
            for classToken, loaded in pairs(ClassPower.loadedModules) do
                if loaded then
                    local module = ClassPower.modules[classToken]
                    if module and module.OnAddonMessage then
                        module:OnAddonMessage(arg4, arg2)
                    end
                end
            end
        end
    else
        -- Pass other events to active module
        if ClassPower.activeModule and ClassPower.activeModule.OnEvent then
            ClassPower.activeModule:OnEvent(event)
        end
    end
end

function ClassPower_OnUpdate(elapsed)
    -- Always run active module's OnUpdate
    if ClassPower.activeModule and ClassPower.activeModule.OnUpdate then
        ClassPower.activeModule:OnUpdate(elapsed)
    end
    
    -- Also check other loaded modules with visible config windows (for admin panel)
    for classToken, loaded in pairs(ClassPower.loadedModules) do
        if loaded then
            local module = ClassPower.modules[classToken]
            -- Skip the active module (already handled above)
            if module and module ~= ClassPower.activeModule then
                -- If this module has a visible config window and UIDirty is set, update it
                if module.ConfigWindow and module.ConfigWindow:IsVisible() then
                    if module.UIDirty then
                        module.UIDirty = false
                        if module.UpdateConfigGrid then
                            module:UpdateConfigGrid()
                        end
                    end
                end
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "ClassPowerEventFrame", UIParent)
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")

eventFrame:SetScript("OnEvent", function() ClassPower_OnEvent(event) end)
eventFrame:SetScript("OnUpdate", function() ClassPower_OnUpdate(arg1) end)

-- Register slash commands
SlashCmdList["CLASSPOWER"] = ClassPower_SlashHandler
SLASH_CLASSPOWER1 = "/cp"
SLASH_CLASSPOWER2 = "/classpower"
SLASH_CLASSPOWER3 = "/prip"
SLASH_CLASSPOWER4 = "/prp"
SLASH_CLASSPOWER5 = "/priestpower"

-- Create dropdown frame for menus
if not getglobal("ClassPowerDropDown") then
    CreateFrame("Frame", "ClassPowerDropDown", UIParent, "UIDropDownMenuTemplate")
end



-----------------------------------------------------------------------------------
-- Minimap Button
-----------------------------------------------------------------------------------

function ClassPower_CreateMinimapButton()
    if getglobal("ClassPowerMinimapButton") then return end
    
    local btn = CreateFrame("Button", "ClassPowerMinimapButton", Minimap)
    btn:SetWidth(31)
    btn:SetHeight(31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    
    -- Icon
    local icon = btn:CreateTexture(btn:GetName().."Icon", "BACKGROUND")
    icon:SetTexture("Interface\\AddOns\\PriestPower\\Media\\cpwr")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    
    -- Border
    local border = btn:CreateTexture(btn:GetName().."Border", "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(56)
    border:SetHeight(56)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    
    -- Highlight
    local highlight = btn:CreateTexture(btn:GetName().."Highlight", "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetWidth(25)
    highlight:SetHeight(25)
    highlight:SetPoint("CENTER", btn, "CENTER", 0, 0)
    
    -- Position around minimap (angle in degrees)
    local function UpdatePosition(angle)
        local radius = 80
        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
        CP_PerUser.MinimapAngle = angle
    end
    
    -- Load saved position or default to top-right
    local savedAngle = CP_PerUser and CP_PerUser.MinimapAngle or 45
    UpdatePosition(savedAngle)
    
    -- Dragging
    btn:SetScript("OnDragStart", function()
        this.isDragging = true
    end)
    
    btn:SetScript("OnDragStop", function()
        this.isDragging = false
    end)
    
    btn:SetScript("OnUpdate", function()
        if not this.isDragging then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        UpdatePosition(angle)
    end)
    
    -- Click handlers
    btn:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            if IsShiftKeyDown() then
                ClassPower:ShowAdminWindow()
            else
                ClassPower_SlashHandler("")
            end
        elseif arg1 == "RightButton" then
            -- Right-click could show a menu or toggle HUD
            if ClassPower.activeModule and ClassPower.activeModule.BuffBar then
                if ClassPower.activeModule.BuffBar:IsVisible() then
                    ClassPower.activeModule.BuffBar:Hide()
                else
                    ClassPower.activeModule.BuffBar:Show()
                end
            end
        end
    end)
    
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("ClassPower")
        GameTooltip:SetText("ClassPower")
        GameTooltip:AddLine("Left-click: Open Config", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Shift+Left-click: Open Admin", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Toggle HUD", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Toggle HUD", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Create minimap button after a short delay (ensure Minimap exists)
local minimapInitFrame = CreateFrame("Frame")
minimapInitFrame:RegisterEvent("PLAYER_LOGIN")
minimapInitFrame:SetScript("OnEvent", function()
    ClassPower_CreateMinimapButton()
end)

-----------------------------------------------------------------------------------
-- Time Formatting Helper
-----------------------------------------------------------------------------------

function CP_FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds) - (m * 60)
    return string.format("%d:%02d", m, s)
end

-----------------------------------------------------------------------------------
-- Shared Settings Panel
-----------------------------------------------------------------------------------

local CP_SettingsPanel = nil

function CP_CreateSettingsPanel()
    if CP_SettingsPanel then return CP_SettingsPanel end
    
    local f = CreateFrame("Frame", "ClassPowerSettingsPanel", UIParent)
    f:SetWidth(280)
    f:SetHeight(200)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
    end)
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("ClassPower Display Settings")
    
    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Display Mode Label
    local modeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -48)
    modeLabel:SetText("Display Mode:")
    
    -- Display Mode Buttons (radio-style)
    local modes = {
        { value = "missing", label = "Show when buffs missing" },
        { value = "timer", label = "Show before expiration" },
        { value = "always", label = "Always show with timers" },
    }
    
    local lastBtn = nil
    for i, mode in ipairs(modes) do
        local btn = CreateFrame("CheckButton", "CPSettingsMode"..i, f, "UIRadioButtonTemplate")
        if i == 1 then
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -68)
        else
            btn:SetPoint("TOPLEFT", lastBtn, "BOTTOMLEFT", 0, -2)
        end
        
        local label = getglobal(btn:GetName().."Text")
        if label then
            label:SetText(mode.label)
            label:SetFontObject(GameFontHighlightSmall)
        end
        
        btn.value = mode.value
        btn:SetScript("OnClick", function()
            CP_PerUser.BuffDisplayMode = this.value
            CP_UpdateSettingsPanel()
            if ClassPower.activeModule and ClassPower.activeModule.UIDirty ~= nil then
                ClassPower.activeModule.UIDirty = true
            end
        end)
        
        lastBtn = btn
    end
    
    -- Timer Threshold section
    local threshLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    threshLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -135)
    threshLabel:SetText("Timer Threshold:")
    
    -- Minutes slider
    local minSlider = CreateFrame("Slider", "CPSettingsMinutes", f, "OptionsSliderTemplate")
    minSlider:SetWidth(90)
    minSlider:SetHeight(14)
    minSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -160)
    minSlider:SetMinMaxValues(0, 30)
    minSlider:SetValueStep(1)
    minSlider:SetValue(CP_PerUser.TimerThresholdMinutes or 5)
    
    getglobal(minSlider:GetName().."Low"):SetText("0m")
    getglobal(minSlider:GetName().."High"):SetText("30m")
    getglobal(minSlider:GetName().."Text"):SetText("Minutes")
    
    local minValue = f:CreateFontString("CPSettingsMinutesValue", "OVERLAY", "GameFontHighlightSmall")
    minValue:SetPoint("TOP", minSlider, "BOTTOM", 0, -2)
    minValue:SetText((CP_PerUser.TimerThresholdMinutes or 5).."m")
    
    minSlider:SetScript("OnValueChanged", function()
        local val = math.floor(this:GetValue())
        CP_PerUser.TimerThresholdMinutes = val
        getglobal("CPSettingsMinutesValue"):SetText(val.."m")
    end)
    
    -- Seconds slider
    local secSlider = CreateFrame("Slider", "CPSettingsSeconds", f, "OptionsSliderTemplate")
    secSlider:SetWidth(90)
    secSlider:SetHeight(14)
    secSlider:SetPoint("TOPLEFT", minSlider, "TOPRIGHT", 30, 0)
    secSlider:SetMinMaxValues(0, 59)
    secSlider:SetValueStep(5)
    secSlider:SetValue(CP_PerUser.TimerThresholdSeconds or 0)
    
    getglobal(secSlider:GetName().."Low"):SetText("0s")
    getglobal(secSlider:GetName().."High"):SetText("59s")
    getglobal(secSlider:GetName().."Text"):SetText("Seconds")
    
    local secValue = f:CreateFontString("CPSettingsSecondsValue", "OVERLAY", "GameFontHighlightSmall")
    secValue:SetPoint("TOP", secSlider, "BOTTOM", 0, -2)
    secValue:SetText((CP_PerUser.TimerThresholdSeconds or 0).."s")
    
    secSlider:SetScript("OnValueChanged", function()
        local val = math.floor(this:GetValue())
        CP_PerUser.TimerThresholdSeconds = val
        getglobal("CPSettingsSecondsValue"):SetText(val.."s")
    end)
    
    f:Hide()
    CP_SettingsPanel = f
    return f
end

function CP_UpdateSettingsPanel()
    if not CP_SettingsPanel then return end
    
    local mode = CP_PerUser.BuffDisplayMode or "missing"
    
    for i = 1, 3 do
        local btn = getglobal("CPSettingsMode"..i)
        if btn then
            btn:SetChecked(btn.value == mode)
        end
    end
    
    -- Note: Sliders don't have Enable/Disable in 1.12.1, they stay enabled
end

function CP_ToggleSettingsPanel()
    CP_CreateSettingsPanel()
    
    if CP_SettingsPanel:IsVisible() then
        CP_SettingsPanel:Hide()
    else
        -- Update values from saved vars
        local minSlider = getglobal("CPSettingsMinutes")
        local secSlider = getglobal("CPSettingsSeconds")
        
        if minSlider then
            minSlider:SetValue(CP_PerUser.TimerThresholdMinutes or 5)
        end
        if secSlider then
            secSlider:SetValue(CP_PerUser.TimerThresholdSeconds or 0)
        end
        
        CP_UpdateSettingsPanel()
        CP_SettingsPanel:Show()
    end
end

function CP_ShowSettingsPanel()
    CP_CreateSettingsPanel()
    
    local minSlider = getglobal("CPSettingsMinutes")
    local secSlider = getglobal("CPSettingsSeconds")
    
    if minSlider then
        minSlider:SetValue(CP_PerUser.TimerThresholdMinutes or 5)
    end
    if secSlider then
        secSlider:SetValue(CP_PerUser.TimerThresholdSeconds or 0)
    end
    
    CP_UpdateSettingsPanel()
    CP_SettingsPanel:Show()
end

-----------------------------------------------------------------------------------
-- Admin Window
-----------------------------------------------------------------------------------


function ClassPower:ShowAdminWindow()
    if not self.AdminWindow then
        self:CreateAdminWindow()
    end
    self.AdminWindow:Show()
end



function ClassPower:CreateAdminWindow()
    if self.AdminWindow then return end
    
    local f = CreateFrame("Frame", "ClassPowerAdminWindow", UIParent)
    f:SetWidth(280)
    f:SetHeight(160)
    f:SetPoint("CENTER", 0, 100)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -20)
    title:SetText("ClassPower Admin")
    
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Select a class module to configure")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Manage Tanks Button
    local btnTank = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnTank:SetWidth(105); btnTank:SetHeight(24)
    btnTank:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    btnTank:SetText("Manage Tanks")
    btnTank:SetScript("OnClick", function() ClassPower:ShowTankManager() end)
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Class buttons
    local classes = {
        {token = "PRIEST", label = "Priests", icon = "Interface\\Icons\\Spell_Holy_WordFortitude", implemented = true},
        {token = "DRUID", label = "Druids", icon = "Interface\\Icons\\Spell_Nature_Regeneration", implemented = true},
        {token = "PALADIN", label = "Paladins", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", implemented = true},
        {token = "MAGE", label = "Mages", icon = "Interface\\Icons\\Spell_Frost_IceStorm", implemented = false},
        {token = "SHAMAN", label = "Shamans", icon = "Interface\\Icons\\Spell_Nature_BloodLust", implemented = false},
    }
    
    local buttonWidth = 70
    local buttonHeight = 50
    local startX = 20
    
    -- Resize window to fit all buttons
    f:SetWidth(20 + (table.getn(classes) * (buttonWidth + 10)))
    
    for i, class in ipairs(classes) do
        local btn = CreateFrame("Button", f:GetName()..class.token, f)
        btn:SetWidth(buttonWidth)
        btn:SetHeight(buttonHeight)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", startX + (i-1) * (buttonWidth + 10), -60)
        
        -- Background
        local bg = btn:CreateTexture(btn:GetName().."Bg", "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture(0.1, 0.1, 0.1, 0.7)
        
        -- Icon
        local icon = btn:CreateTexture(btn:GetName().."Icon", "ARTWORK")
        icon:SetWidth(32)
        icon:SetHeight(32)
        icon:SetPoint("TOP", btn, "TOP", 0, -4)
        icon:SetTexture(class.icon)
        
        -- Dim unimplemented modules
        if not class.implemented then
            icon:SetDesaturated(1)
            icon:SetAlpha(0.5)
        end
        
        -- Label
        local label = btn:CreateFontString(btn:GetName().."Label", "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
        label:SetText(class.label)
        if not class.implemented then
            label:SetTextColor(0.5, 0.5, 0.5)
        end
        
        -- Highlight
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        local ht = btn:GetHighlightTexture()
        if ht then ht:SetBlendMode("ADD") end
        
        btn.classToken = class.token
        btn.classLabel = class.label
        btn.implemented = class.implemented
        btn:SetScript("OnClick", function()
            if this.implemented then
                ClassPower:SwitchViewModule(this.classToken)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..this.classLabel.." module not yet implemented.")
            end
        end)
        
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if this.implemented then
                GameTooltip:SetText("Open "..this.classLabel.." Configuration")
            else
                GameTooltip:SetText(this.classLabel.." (Not Implemented)")
                GameTooltip:AddLine("This class module is not yet available.", 1, 0.5, 0)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    f:Hide()
    self.AdminWindow = f
end

-----------------------------------------------------------------------------------
-- Auto-Assign Helper Functions
-----------------------------------------------------------------------------------

-- Returns a table of group IDs (1-8) that have at least one player
function ClassPower_GetActiveGroups()
    local activeGroups = {}
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid > 0 then
        local groupHasPlayers = {}
        for i = 1, numRaid do
            local _, _, subgroup = GetRaidRosterInfo(i)
            if subgroup and subgroup >= 1 and subgroup <= 8 then
                groupHasPlayers[subgroup] = true
            end
        end
        for g = 1, 8 do
            if groupHasPlayers[g] then
                table.insert(activeGroups, g)
            end
        end
    elseif numParty > 0 then
        -- In a party, everyone is effectively in group 1
        table.insert(activeGroups, 1)
    else
        -- Solo, group 1
        table.insert(activeGroups, 1)
    end
    
    return activeGroups
end

-- Distributes groups evenly among a list of players
-- Returns: { [playerName] = { group1, group2, ... }, ... }
function ClassPower_DistributeGroups(players, groups)
    local assignments = {}
    local numPlayers = table.getn(players)
    local numGroups = table.getn(groups)
    
    if numPlayers == 0 or numGroups == 0 then
        return assignments
    end
    
    -- Initialize empty assignments for each player
    for _, player in ipairs(players) do
        assignments[player] = {}
    end
    
    -- Distribute groups round-robin
    for i, group in ipairs(groups) do
        local playerIndex = math.mod(i - 1, numPlayers) + 1
        local player = players[playerIndex]
        table.insert(assignments[player], group)
    end
    
    return assignments
end


-----------------------------------------------------------------------------------
-- Tank Manager System
-----------------------------------------------------------------------------------

function ClassPower:IsTank(name)
    for _, tank in ipairs(ClassPower_TankList) do
        if tank.name == name then return true, tank end
    end
    return false, nil
end

function ClassPower:AddTank(name, role, mark)
    if not name or name == "" then return end
    
    local isTank, existing = self:IsTank(name)
    if isTank then
        -- Update existing
        existing.role = role or existing.role
        existing.mark = mark or existing.mark
    else
        -- Add new
        table.insert(ClassPower_TankList, {
            name = name,
            role = role or "MT",
            mark = mark or 0
        })
    end
    if self.TankManagerWindow and self.TankManagerWindow:IsVisible() then
        self:UpdateTankListUI()
    end
    -- Reset Paladin assignments on tank change as priorities change
    if ClassPower.modules["PALADIN"] then
        ClassPower.modules["PALADIN"].Assignments = {} -- Optional: clear assignments to force refresh
        ClassPower_SendMessage("TANKUPDATE") -- Notify modules
    end
end

function ClassPower:RemoveTank(name)
    for i, tank in ipairs(ClassPower_TankList) do
        if tank.name == name then
            table.remove(ClassPower_TankList, i)
            if self.TankManagerWindow and self.TankManagerWindow:IsVisible() then
                self:UpdateTankListUI()
            end
            ClassPower_SendMessage("TANKUPDATE")
            return
        end
    end
end

function ClassPower:AnnounceTanks()
    if table.getn(ClassPower_TankList) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("No tanks assigned.")
        return
    end
    
    local markNames = {
        "Star", "Circle", "Diamond", "Triangle", 
        "Moon", "Square", "Cross", "Skull"
    }
    SendChatMessage("--- Tank Assignments ---", "RAID")
    for _, tank in ipairs(ClassPower_TankList) do
        local markStr = ""
        if tank.mark and tank.mark > 0 then
            markStr = "("..(markNames[tank.mark] or "??")..")"
        end
        SendChatMessage(tank.name.." ["..(tank.role or "MT").."] "..markStr, "RAID")
    end
    SendChatMessage("------------------------", "RAID")
end

function ClassPower:CreateTankManagerWindow()
    if self.TankManagerWindow then return end
    
    local f = CreateFrame("Frame", "CPTankManagerFrame", UIParent)
    f:SetWidth(350)
    f:SetHeight(300)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()
    
    f:SetScript("OnMouseDown", function() if arg1=="LeftButton" then this:StartMoving() end end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("Tank Manager")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Dropdown for adding players
    local dd = CreateFrame("Frame", "CPTankAddDropDown", f, "UIDropDownMenuTemplate")
    dd:Hide()

    local function TankAddDropDown_Initialize(level)
        if not level then return end
        local info = {}
        
        if level == 1 then
            -- Group by subgroups (1-8)
            info.text = "Add Player"
            info.isTitle = 1
            info.notCheckable = 1
            UIDropDownMenu_AddButton(info, level)
            
            for g = 1, 8 do
                local hasMembers = false
                -- Quick check if group has members
                if GetNumRaidMembers() > 0 then
                    for i=1, GetNumRaidMembers() do
                        local _, _, subgroup = GetRaidRosterInfo(i)
                        if subgroup == g then hasMembers = true break end
                    end
                elseif GetNumPartyMembers() > 0 and g == 1 then
                    hasMembers = true
                end
                
                if hasMembers then
                    info = {}
                    info.text = "Group "..g
                    info.hasArrow = 1
                    info.value = g
                    info.notCheckable = 1
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        elseif level == 2 then
            local group = UIDROPDOWNMENU_MENU_VALUE
            local numRaid = GetNumRaidMembers()
            
            if numRaid > 0 then
                for i = 1, numRaid do
                    local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
                    if subgroup == group then
                        info = {}
                        info.text = name
                        local color = RAID_CLASS_COLORS[class]
                        if color then
                            info.text = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, name)
                        end
                        info.arg1 = name
                        info.func = function(arg1) -- arg1 passed from info.arg1
                            ClassPower:AddTank(arg1, "MT", 0) 
                            CloseDropDownMenus()
                        end
                        info.notCheckable = 1
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            elseif group == 1 then
                -- Party handling
                 local function AddPartyMember(unit)
                    if UnitExists(unit) then
                        local name = UnitName(unit)
                        local _, class = UnitClass(unit)
                        info = {}
                        info.text = name
                        local color = RAID_CLASS_COLORS[class]
                        if color then
                            info.text = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, name)
                        end
                        info.arg1 = name
                        info.func = function(arg1) 
                            ClassPower:AddTank(arg1, "MT", 0) 
                            CloseDropDownMenus()
                        end
                        info.notCheckable = 1
                        UIDropDownMenu_AddButton(info, level)
                    end
                 end
                 AddPartyMember("player")
                 for i=1, GetNumPartyMembers() do AddPartyMember("party"..i) end
            end
        end
    end
    
    UIDropDownMenu_Initialize(dd, TankAddDropDown_Initialize, "MENU")

    -- Dropdown for Raid Markers
    local markDD = CreateFrame("Frame", "CPTankMarkDropDown", f, "UIDropDownMenuTemplate")
    markDD:Hide()
    
    local function TankMarkDropDown_Initialize(level)
        if not level then return end
        local tankIndex = UIDROPDOWNMENU_MENU_VALUE
        if not tankIndex then return end
        
        local info = {}
        info.isTitle = 1
        info.text = "Select Mark"
        info.notCheckable = 1
        UIDropDownMenu_AddButton(info, level)
        
        -- Option to clear
        info = {}
        info.text = "None"
        info.arg1 = tankIndex
        info.arg2 = 0
        info.func = function(idx, mark)
            local t = ClassPower_TankList[idx]
            if t then
                t.mark = mark
                ClassPower:UpdateTankListUI()
            end
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info, level)
        
        local marks = {"Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull"}
        for i, name in ipairs(marks) do
            info = {}
            info.text = name
            info.arg1 = tankIndex
            info.arg2 = i
            info.func = function(idx, mark)
                local t = ClassPower_TankList[idx]
                if t then
                    t.mark = mark
                    ClassPower:UpdateTankListUI()
                end
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(markDD, TankMarkDropDown_Initialize, "MENU")

    -- Add Target Button
    local btnAdd = CreateFrame("Button", "CPTankAddBtn", f, "UIPanelButtonTemplate")
    btnAdd:SetWidth(100); btnAdd:SetHeight(24)
    btnAdd:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    btnAdd:SetText("Add Target")
    btnAdd:SetScript("OnClick", function()
        local name = UnitName("target")
        if name then
            ClassPower:AddTank(name, "MT", 0)
        else
            -- No target, show dropdown
            ToggleDropDownMenu(1, nil, dd, "CPTankAddBtn", 0, 0)
        end
    end)
    
    -- Announce Button
    local btnAnnounce = CreateFrame("Button", "CPTankAnnounceBtn", f, "UIPanelButtonTemplate")
    btnAnnounce:SetWidth(100); btnAnnounce:SetHeight(24)
    btnAnnounce:SetPoint("LEFT", btnAdd, "RIGHT", 10, 0)
    btnAnnounce:SetText("Announce")
    btnAnnounce:SetScript("OnClick", function() ClassPower:AnnounceTanks() end)

    -- ScrollFrame for List
    -- Simplified list for now: fixed 8 rows
    f.rows = {}
    local rowHeight = 24
    for i=1, 8 do
        local row = CreateFrame("Frame", nil, f)
        row:SetWidth(310)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -80 - ((i-1)*rowHeight))
        
        -- Name
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name:SetWidth(100)
        row.name:SetJustifyH("LEFT")
        
        -- Role Cycle Button (MT/OT)
        row.roleBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.roleBtn:SetWidth(40); row.roleBtn:SetHeight(20)
        row.roleBtn:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        row.roleBtn:SetScript("OnClick", function()
            local tank = ClassPower_TankList[this:GetParent().index]
            if tank then
                tank.role = (tank.role == "MT") and "OT" or "MT"
                this:SetText(tank.role)
                ClassPower:UpdateTankListUI()
            end
        end)
        
        -- Mark Cycle Button (0-8)
        row.markBtn = CreateFrame("Button", "ClassPowerTankRow"..i.."MarkBtn", row, "UIPanelButtonTemplate")
        row.markBtn:SetWidth(24); row.markBtn:SetHeight(24)
        row.markBtn:SetPoint("LEFT", row.roleBtn, "RIGHT", 5, 0)
        
        -- Mark Icon (Overlay on button)
        row.markIcon = row.markBtn:CreateTexture(nil, "OVERLAY")
        row.markIcon:SetWidth(18); row.markIcon:SetHeight(18)
        row.markIcon:SetPoint("CENTER", row.markBtn, "CENTER", 0, 0)
        
        row.markBtn:SetScript("OnClick", function()
             -- Open Dropdown
             local index = this:GetParent().index
             ToggleDropDownMenu(1, index, getglobal("CPTankMarkDropDown"), this:GetName(), 0, 0)
        end)
        
        -- Remove Button
        row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.delBtn:SetWidth(20); row.delBtn:SetHeight(20)
        row.delBtn:SetPoint("LEFT", row.markBtn, "RIGHT", 5, 0)
        row.delBtn:SetText("X")
        row.delBtn:SetScript("OnClick", function()
             local tank = ClassPower_TankList[this:GetParent().index]
             if tank then
                 ClassPower:RemoveTank(tank.name)
             end
        end)
        
        f.rows[i] = row
    end
    
    self.TankManagerWindow = f
end

function ClassPower:SetRaidIcon(texture, index)
    if not index or index == 0 then
        texture:Hide()
        return
    end
    texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local col = math.mod(index - 1, 4)
    local row = math.floor((index - 1) / 4)
    texture:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
    texture:Show()
end

function ClassPower:UpdateTankRow(row, tank)
    row.name:SetText(tank.name)
    row.roleBtn:SetText(tank.role)
    
    if tank.mark > 0 then
        ClassPower:SetRaidIcon(row.markIcon, tank.mark)
        row.markBtn:SetText("")
    else
        row.markIcon:Hide()
        row.markBtn:SetText("-")
    end
    row:Show()
end

function ClassPower:UpdateTankListUI()
    if not self.TankManagerWindow then return end
    
    for i, row in ipairs(self.TankManagerWindow.rows) do
        local tank = ClassPower_TankList[i]
        if tank then
            row.index = i
            self:UpdateTankRow(row, tank)
        else
            row:Hide()
        end
    end
end

function ClassPower:ShowTankManager()
    self:CreateTankManagerWindow()
    self:UpdateTankListUI()
    self.TankManagerWindow:Show()
end

-----------------------------------------------------------------------------------
-- Slash Command Handler
-----------------------------------------------------------------------------------



function ClassPower_SlashHandler(msg)
    local _, _, cmd, arg = string.find(msg, "^%s*(%S+)%s*(.*)$")
    if not cmd then cmd = msg end
    if not cmd or cmd == "" then
        -- Default: Open current class config
        if ClassPower.activeModule and ClassPower.activeModule.ShowConfig then
            ClassPower.activeModule:ShowConfig()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No active module loaded.")
        end
        return
    end
    
    cmd = string.lower(cmd)
    
    if cmd == "admin" then
        ClassPower:ShowAdminWindow()
        
    elseif cmd == "config" or cmd == "options" or cmd == "menu" then
        if ClassPower.activeModule and ClassPower.activeModule.ShowConfig then
            ClassPower.activeModule:ShowConfig()
        end
        
    elseif cmd == "debug" then
        if CP_PerUser.Debug then
            CP_PerUser.Debug = false
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Debug mode disabled.")
        else
            CP_PerUser.Debug = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Debug mode enabled.")
        end
        
    elseif cmd == "reset" then
        if ClassPower.activeModule and ClassPower.activeModule.ResetUI then
            ClassPower.activeModule:ResetUI()
        end
        
    elseif cmd == "scale" then
        local scale = tonumber(arg)
        if scale and scale >= 0.5 and scale <= 2.0 then
            if ClassPower.activeModule and ClassPower.activeModule.SetConfigScale then
                ClassPower.activeModule:SetConfigScale(scale)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Usage: /cp scale <0.5-2.0>")
        end
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Usage:")
        DEFAULT_CHAT_FRAME:AddMessage("  /cp - Open config")
        DEFAULT_CHAT_FRAME:AddMessage("  /cp admin - Open admin window")
        DEFAULT_CHAT_FRAME:AddMessage("  /cp debug - Toggle debug")
        DEFAULT_CHAT_FRAME:AddMessage("  /cp reset - Reset UI positions")
        DEFAULT_CHAT_FRAME:AddMessage("  /cp scale <n> - Set config scale")
    end
end
SlashCmdList["CLASSPOWER"] = ClassPower_SlashHandler

CP_Debug("ClassPower Core loaded.")

