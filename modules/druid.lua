-- ClassPower: Druid Module
-- Full buff management for Druid class

local Druid = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Druid.Spells = {
    MOTW = "Mark of the Wild",
    GOTW = "Gift of the Wild",
    THORNS = "Thorns",
    EMERALD = "Emerald Blessing",
    INNERVATE = "Innervate",
}

Druid.BuffIcons = {
    [0] = "Interface\\Icons\\Spell_Nature_Regeneration",         -- Mark of the Wild
    [1] = "Interface\\Icons\\Spell_Nature_Thorns",               -- Thorns
}

Druid.BuffIconsGroup = {
    [0] = "Interface\\Icons\\Spell_Nature_GiftOfTheWild",        -- Gift of the Wild
}

Druid.SpecialIcons = {
    ["Emerald"] = "Interface\\Icons\\Spell_Nature_ProtectionformNature",
    ["Innervate"] = "Interface\\Icons\\Spell_Nature_Lightning",
}

-- Buff type constants
Druid.BUFF_MOTW = 0
Druid.BUFF_THORNS = 1

-----------------------------------------------------------------------------------
-- State
-----------------------------------------------------------------------------------

Druid.AllDruids = {}
Druid.CurrentBuffs = {}
Druid.CurrentBuffsByName = {}
Druid.Assignments = {}
Druid.LegacyAssignments = {}
Druid.RankInfo = {}

-- Timers
Druid.NextScan = 10
Druid.UpdateTimer = 0
Druid.LastRequest = 0
Druid.RosterDirty = false
Druid.RosterTimer = 0.5

-- Context for dropdowns
Druid.ContextName = nil
Druid.AssignMode = "Innervate"

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Druid:OnLoad()
    CP_Debug("Druid:OnLoad()")
    
    -- Initial spell scan
    self:ScanSpells()
    self:ScanRaid()
    
    -- Create UI
    self:CreateBuffBar()
    self:CreateConfigWindow()
    
    -- Create dropdown
    if not getglobal("ClassPowerDruidDropDown") then
        CreateFrame("Frame", "ClassPowerDruidDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerDruidDropDown, function(level) Druid:InnervateDropDown_Initialize(level) end, "MENU")
    
    -- Request sync from other druids
    self:RequestSync()
end

function Druid:OnEvent(event)
    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        self:ScanSpells()
        self:ScanRaid()
        if event == "PLAYER_ENTERING_WORLD" then
            self:RequestSync()
        end
        
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        if event == "RAID_ROSTER_UPDATE" then
            self.RosterDirty = true
            self.RosterTimer = 0.5
        else
            self:ScanRaid()
            self:UpdateUI()
        end
        
        if event == "RAID_ROSTER_UPDATE" then
            if GetTime() - self.LastRequest > 5 then
                self:RequestSync()
                self.LastRequest = GetTime()
            end
        end
    end
end

function Druid:OnUpdate(elapsed)
    if not elapsed then elapsed = 0.01 end
    
    -- Spell scan timer
    self.NextScan = self.NextScan - elapsed
    if self.NextScan <= 0 then
        self.NextScan = CP_PerUser.scanfreq or 10
        self:ScanSpells()
    end
    
    -- Delayed roster scan
    if self.RosterDirty then
        self.RosterTimer = self.RosterTimer - elapsed
        if self.RosterTimer <= 0 then
            self.RosterDirty = false
            self.RosterTimer = 0.5
            self:ScanRaid()
            self:UpdateUI()
        end
    end
    
    -- UI refresh (1s interval)
    self.UpdateTimer = self.UpdateTimer - elapsed
    if self.UpdateTimer <= 0 then
        self.UpdateTimer = 1.0
        
        if self.BuffBar and self.BuffBar:IsVisible() then
            self:ScanRaid()
            self:UpdateBuffBar()
        end
        
        if self.ConfigWindow and self.ConfigWindow:IsVisible() then
            self:UpdateConfigGrid()
        end
    end
end

function Druid:OnSlashCommand(msg)
    if msg == "innervate" then
        local pname = UnitName("player")
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Innervate"]
        if target then
            ClearTarget()
            TargetByName(target, true)
            if UnitName("target") == target then
                CastSpellByName(self.Spells.INNERVATE)
                TargetLastTarget()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target "..target)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Innervate target assigned!")
        end
    elseif msg == "emerald" then
        CastSpellByName(self.Spells.EMERALD)
    elseif msg == "checkbuffs" then
        local unit = "player"
        if UnitExists("target") then unit = "target" end
        DEFAULT_CHAT_FRAME:AddMessage("Buffs on "..UnitName(unit)..":")
        for i=1,32 do
            local b = UnitBuff(unit, i)
            if b then
                DEFAULT_CHAT_FRAME:AddMessage(i..": "..b)
            end
        end
    else
        -- Toggle config window
        if self.ConfigWindow then
            if self.ConfigWindow:IsVisible() then
                self.ConfigWindow:Hide()
            else
                self.ConfigWindow:Show()
                self:UpdateConfigGrid()
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- Spell Scanning
-----------------------------------------------------------------------------------

function Druid:ScanSpells()
    local info = {
        [0] = { rank = 0, talent = 0, name = "MotW" },   -- Mark/Gift
        [1] = { rank = 0, talent = 0, name = "Thorns" }, -- Thorns
        ["Emerald"] = false,
        ["Innervate"] = false,
    }
    
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        
        local rank = 0
        if spellRank then
            _, _, rank = string.find(spellRank, "Rank (%d+)")
            rank = tonumber(rank) or 0
        end
        
        -- Mark of the Wild
        if spellName == self.Spells.MOTW then
            if rank > info[0].rank then info[0].rank = rank end
        elseif spellName == self.Spells.GOTW then
            info[0].talent = 1
        end
        
        -- Thorns
        if spellName == self.Spells.THORNS then
            if rank > info[1].rank then info[1].rank = rank end
        end
        
        -- Special spells
        if spellName == self.Spells.EMERALD then info["Emerald"] = true end
        if spellName == self.Spells.INNERVATE then info["Innervate"] = true end
        
        i = i + 1
    end
    
    self.AllDruids[UnitName("player")] = info
    self.RankInfo = info
end

-----------------------------------------------------------------------------------
-- Raid/Buff Scanning
-----------------------------------------------------------------------------------

function Druid:ScanRaid()
    self.CurrentBuffs = {}
    for i = 1, 8 do self.CurrentBuffs[i] = {} end
    self.CurrentBuffsByName = {}
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local foundDruids = {}
    
    if UnitClass("player") == "Druid" then
        foundDruids[UnitName("player")] = true
    end
    
    local function ProcessUnit(unit, name, subgroup, class)
        local isValid = (unit == "player") or string.find(unit, "^party%d+$") or string.find(unit, "^raid%d+$")
        if not isValid or not UnitExists(unit) then return end
        
        if name and class == "DRUID" then
            foundDruids[name] = true
            if not self.AllDruids[name] then
                self.AllDruids[name] = {
                    [0] = { rank = 0, talent = 0, name = "MotW" },
                    [1] = { rank = 0, talent = 0, name = "Thorns" },
                    ["Emerald"] = false,
                    ["Innervate"] = false,
                }
            end
        end
        
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            local buffInfo = {
                name = name,
                class = class,
                visible = UnitIsVisible(unit),
                dead = UnitIsDeadOrGhost(unit),
                hasMotW = false,
                hasThorns = false,
                hasEmerald = false,
            }
            
            local b = 1
            while true do
                local bname = UnitBuff(unit, b)
                if not bname then break end
                
                bname = string.lower(bname)
                
                if string.find(bname, "wild") or string.find(bname, "gift") then buffInfo.hasMotW = true end
                if string.find(bname, "thorns") then buffInfo.hasThorns = true end
                if string.find(bname, "emerald") or string.find(bname, "protectionformnature") then buffInfo.hasEmerald = true end
                
                b = b + 1
            end
            
            if not self.CurrentBuffs[subgroup] then self.CurrentBuffs[subgroup] = {} end
            table.insert(self.CurrentBuffs[subgroup], buffInfo)
            self.CurrentBuffsByName[name] = buffInfo
        end
    end
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            ProcessUnit("raid"..i, name, subgroup, class)
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            ProcessUnit("party"..i, name, 1, class)
        end
        local _, pClass = UnitClass("player")
        ProcessUnit("player", UnitName("player"), 1, pClass)
    end
    
    -- Cleanup druids who left
    for name, _ in pairs(self.AllDruids) do
        if not foundDruids[name] then
            self.AllDruids[name] = nil
            self.Assignments[name] = nil
        end
    end
end

-----------------------------------------------------------------------------------
-- Sync Protocol
-----------------------------------------------------------------------------------

function Druid:RequestSync()
    ClassPower_SendMessage("DREQ")
end

function Druid:SendSelf()
    local pname = UnitName("player")
    local myRanks = self.AllDruids[pname]
    if not myRanks then return end
    
    local msg = "DSELF "
    for i = 0, 1 do
        if myRanks[i] then
            msg = msg .. myRanks[i].rank .. myRanks[i].talent
        else
            msg = msg .. "00"
        end
    end
    
    msg = msg .. (myRanks["Emerald"] and "1" or "0")
    msg = msg .. (myRanks["Innervate"] and "1" or "0") .. "@"
    
    local assigns = self.Assignments[pname]
    for i = 1, 8 do
        local val = 0
        if assigns and assigns[i] then val = assigns[i] end
        msg = msg .. val
    end
    msg = msg .. "@"
    
    local innerv = "nil"
    if self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Innervate"] then
        innerv = self.LegacyAssignments[pname]["Innervate"]
    end
    msg = msg .. innerv
    
    ClassPower_SendMessage(msg)
end

function Druid:OnAddonMessage(sender, msg)
    if sender == UnitName("player") then return end
    
    if msg == "DREQ" then
        self:SendSelf()
    elseif string.find(msg, "^DSELF") then
        local _, _, ranks, assigns, innerv = string.find(msg, "DSELF (.-)@(.-)@(.*)")
        if not ranks then return end
        
        self.AllDruids[sender] = self.AllDruids[sender] or {}
        local info = self.AllDruids[sender]
        
        for id = 0, 1 do
            local r = string.sub(ranks, id*2+1, id*2+1)
            local t = string.sub(ranks, id*2+2, id*2+2)
            if r ~= "n" then
                info[id] = { rank = tonumber(r) or 0, talent = tonumber(t) or 0 }
            end
        end
        
        info["Emerald"] = (string.sub(ranks, 5, 5) == "1")
        info["Innervate"] = (string.sub(ranks, 6, 6) == "1")
        
        self.Assignments[sender] = self.Assignments[sender] or {}
        for gid = 1, 8 do
            local val = string.sub(assigns, gid, gid)
            if val ~= "n" and val ~= "" then
                self.Assignments[sender][gid] = tonumber(val)
            end
        end
        
        self.LegacyAssignments[sender] = self.LegacyAssignments[sender] or {}
        if innerv and innerv ~= "" and innerv ~= "nil" then
            self.LegacyAssignments[sender]["Innervate"] = innerv
        else
            self.LegacyAssignments[sender]["Innervate"] = nil
        end
    elseif string.find(msg, "^DASSIGN ") then
        local _, _, name, grp, skill = string.find(msg, "^DASSIGN (.-) (.-) (.*)")
        if name and grp and skill then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                self.Assignments[name][tonumber(grp)] = tonumber(skill)
                self:UpdateUI()
            end
        end
    elseif string.find(msg, "^DASSIGNTARGET ") then
        local _, _, name, target = string.find(msg, "^DASSIGNTARGET (.-) (.*)")
        if name and target then
            if sender == name or ClassPower_IsPromoted(sender) then
                if target == "nil" or target == "" then target = nil end
                self.LegacyAssignments[name] = self.LegacyAssignments[name] or {}
                self.LegacyAssignments[name]["Innervate"] = target
                self:UpdateUI()
            end
        end
    elseif string.find(msg, "^DCLEAR ") then
        local _, _, target = string.find(msg, "^DCLEAR (.*)")
        if target then
            if sender == target or ClassPower_IsPromoted(sender) then
                self.Assignments[target] = {}
                self.LegacyAssignments[target] = {}
                if target == UnitName("player") then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Assignments cleared by "..sender)
                end
                self:UpdateUI()
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- UI: Buff Bar
-----------------------------------------------------------------------------------

function Druid:CreateBuffBar()
    if getglobal("ClassPowerDruidBuffBar") then 
        self.BuffBar = getglobal("ClassPowerDruidBuffBar")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerDruidBuffBar", UIParent)
    f:SetFrameStrata("LOW")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetWidth(145)
    f:SetHeight(40)
    
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -4)
    title:SetText("ClassPower")
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
        Druid:SaveBuffBarPosition()
    end)
    
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Druid:SaveBuffBarPosition()
    end)
    
    -- Create rows: 8 groups + 1 Emerald row
    for i = 1, 9 do
        local row = self:CreateHUDRow(f, "ClassPowerDruidHUDRow"..i, i)
        row:Hide()
    end
    
    if CP_PerUser.DruidPoint then
        f:ClearAllPoints()
        f:SetPoint(CP_PerUser.DruidPoint, "UIParent", CP_PerUser.DruidRelativePoint or "CENTER", CP_PerUser.DruidX or 0, CP_PerUser.DruidY or 0)
    else
        f:SetPoint("CENTER", 0, 0)
    end
    
    if CP_PerUser.DruidScale then
        f:SetScale(CP_PerUser.DruidScale)
    else
        f:SetScale(0.7)
    end
    
    self.BuffBar = f
end

function Druid:CreateHUDRow(parent, name, id)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(140)
    f:SetHeight(34)
    
    local label = f:CreateFontString(f:GetName().."Label", "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", f, "LEFT", 5, 0)
    
    if id == 9 then
        label:SetText("Emrld")
    else
        label:SetText("Grp "..id)
    end
    
    if id <= 8 then
        local motw = CP_CreateHUDButton(f, name.."MotW")
        motw:SetPoint("LEFT", f, "LEFT", 40, 0)
        motw:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
        
        local thorns = CP_CreateHUDButton(f, name.."Thorns")
        thorns:SetPoint("LEFT", motw, "RIGHT", 2, 0)
        thorns:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    if id == 9 then
        local emerald = CP_CreateHUDButton(f, name.."Emerald")
        emerald:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(emerald:GetName().."Icon"):SetTexture(self.SpecialIcons["Emerald"])
        emerald:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    return f
end

function Druid:SaveBuffBarPosition()
    if not self.BuffBar then return end
    local point, _, relativePoint, x, y = self.BuffBar:GetPoint()
    CP_PerUser.DruidPoint = point
    CP_PerUser.DruidRelativePoint = relativePoint
    CP_PerUser.DruidX = x
    CP_PerUser.DruidY = y
    CP_PerUser.DruidScale = self.BuffBar:GetScale()
end

function Druid:UpdateBuffBar()
    if not self.BuffBar then return end
    
    local f = self.BuffBar
    local pname = UnitName("player")
    local assigns = self.Assignments[pname]
    
    local lastRow = nil
    local count = 0
    
    for i = 1, 9 do
        local row = getglobal("ClassPowerDruidHUDRow"..i)
        if not row then break end
        
        local showRow = false
        
        if i == 9 then
            -- Emerald Blessing row
            local btnEm = getglobal(row:GetName().."Emerald")
            local hasEmerald = self.RankInfo and self.RankInfo["Emerald"]
            
            if hasEmerald then
                -- Check if anyone is missing Emerald buff
                local missing = 0
                local total = 0
                for g = 1, 8 do
                    if self.CurrentBuffs[g] then
                        for _, m in self.CurrentBuffs[g] do
                            total = total + 1
                            if not m.hasEmerald and not m.dead then missing = missing + 1 end
                        end
                    end
                end
                
                if missing > 0 then
                    btnEm:Show()
                    btnEm.tooltipText = "Emerald Blessing"
                    getglobal(btnEm:GetName().."Text"):SetText((total-missing).."/"..total)
                    getglobal(btnEm:GetName().."Text"):SetTextColor(1,0,0)
                    showRow = true
                else
                    btnEm:Hide()
                end
            else
                btnEm:Hide()
            end
        elseif assigns and assigns[i] and assigns[i] > 0 then
            local val = assigns[i]
            local motwS = math.mod(val, 4)
            local thornsS = math.mod(math.floor(val/4), 4)
            
            local function UpdateHUD(btn, state, typeIdx, buffKey, label)
                if not btn then return false end
                if state > 0 then
                    local missing = 0
                    local total = 0
                    if self.CurrentBuffs[i] then
                        for _, m in self.CurrentBuffs[i] do
                            total = total + 1
                            if not m[buffKey] and not m.dead then missing = missing + 1 end
                        end
                    end
                    if missing > 0 then
                        btn:Show()
                        btn.tooltipText = "Group "..i..": "..label
                        btn.assignmentState = state
                        local txt = getglobal(btn:GetName().."Text")
                        local icon = getglobal(btn:GetName().."Icon")
                        txt:SetText((total-missing).."/"..total)
                        txt:SetTextColor(1,0,0)
                        if state == 1 then
                            icon:SetTexture(self.BuffIconsGroup[typeIdx] or self.BuffIcons[typeIdx])
                        else
                            icon:SetTexture(self.BuffIcons[typeIdx])
                        end
                        return true
                    else
                        btn:Hide()
                    end
                else
                    btn:Hide()
                end
                return false
            end
            
            local f1 = UpdateHUD(getglobal(row:GetName().."MotW"), motwS, 0, "hasMotW", "Mark of the Wild")
            local f2 = UpdateHUD(getglobal(row:GetName().."Thorns"), thornsS, 1, "hasThorns", "Thorns")
            showRow = f1 or f2
        end
        
        if showRow then
            row:Show()
            row:ClearAllPoints()
            if lastRow then
                row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -20)
            end
            lastRow = row
            count = count + 1
        else
            row:Hide()
        end
    end
    
    local newHeight = 25 + (count * 34)
    if newHeight < 40 then newHeight = 40 end
    f:SetHeight(newHeight)
end

-----------------------------------------------------------------------------------
-- UI: Config Window
-----------------------------------------------------------------------------------

function Druid:CreateConfigWindow()
    if getglobal("ClassPowerDruidConfig") then 
        self.ConfigWindow = getglobal("ClassPowerDruidConfig")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerDruidConfig", UIParent)
    f:SetWidth(780)
    f:SetHeight(450)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("ClassPower - Druid Configuration")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Scale Handle
    local scaleBtn = CreateFrame("Button", f:GetName().."ScaleButton", f)
    scaleBtn:SetWidth(16)
    scaleBtn:SetHeight(16)
    scaleBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    scaleBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    scaleBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    scaleBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    scaleBtn:SetScript("OnMouseDown", function()
        local p = this:GetParent()
        p.isScaling = true
        p.startScale = p:GetScale()
        p.cursorStartX, p.cursorStartY = GetCursorPosition()
    end)
    scaleBtn:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isScaling = false
        CP_PerUser.DruidConfigScale = p:GetScale()
    end)
    scaleBtn:SetScript("OnUpdate", function()
        local p = this:GetParent()
        if not p.isScaling then return end
        local cursorX, cursorY = GetCursorPosition()
        local diff = (cursorX - p.cursorStartX) / UIParent:GetEffectiveScale()
        local newScale = p.startScale + (diff * 0.002)
        if newScale < 0.6 then newScale = 0.6 end
        if newScale > 1.5 then newScale = 1.5 end
        p:SetScale(newScale)
    end)
    
    local headerY = -48
    
    local lblDruid = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblDruid:SetPoint("TOPLEFT", f, "TOPLEFT", 25, headerY)
    lblDruid:SetText("Druid")
    
    local lblCaps = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblCaps:SetPoint("TOPLEFT", f, "TOPLEFT", 90, headerY)
    lblCaps:SetText("Spells")
    
    for g = 1, 8 do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 180 + (g-1)*58, headerY)
        lbl:SetText("G"..g)
    end
    
    local lblInnerv = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblInnerv:SetPoint("TOPLEFT", f, "TOPLEFT", 660, headerY)
    lblInnerv:SetText("Innerv")
    
    for i = 1, 10 do
        self:CreateConfigRow(f, i)
    end
    
    if CP_PerUser.DruidConfigScale then
        f:SetScale(CP_PerUser.DruidConfigScale)
    else
        f:SetScale(1.0)
    end
    
    f:Hide()
    self.ConfigWindow = f
end

function Druid:CreateConfigRow(parent, rowIndex)
    local rowName = "CPDruidRow"..rowIndex
    local row = CreateFrame("Frame", rowName, parent)
    row:SetWidth(750)
    row:SetHeight(44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -65 - (rowIndex-1)*46)
    
    local clearBtn = CP_CreateClearButton(row, rowName.."Clear")
    clearBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    clearBtn:SetScript("OnClick", function() Druid:ClearButton_OnClick(this) end)
    
    local nameStr = row:CreateFontString(rowName.."Name", "OVERLAY", "GameFontHighlight")
    nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 15, -14)
    nameStr:SetWidth(65)
    nameStr:SetHeight(16)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("")
    
    local caps = CreateFrame("Frame", rowName.."Caps", row)
    caps:SetWidth(80)
    caps:SetHeight(22)
    caps:SetPoint("TOPLEFT", row, "TOPLEFT", 80, -12)
    
    local function CreateCapIcon(suffix, xOffset)
        local btn = CP_CreateCapabilityIcon(caps, rowName.."Cap"..suffix)
        btn:SetWidth(16)
        btn:SetHeight(16)
        local icon = getglobal(btn:GetName().."Icon")
        if icon then icon:SetWidth(14); icon:SetHeight(14) end
        btn:SetPoint("TOPLEFT", caps, "TOPLEFT", xOffset, 0)
        return btn
    end
    
    CreateCapIcon("MotW", 0)
    CreateCapIcon("Thorns", 16)
    CreateCapIcon("Emerald", 36)
    CreateCapIcon("Innervate", 52)
    
    for g = 1, 8 do
        local grpFrame = CreateFrame("Frame", rowName.."Group"..g, row)
        grpFrame:SetWidth(54)
        grpFrame:SetHeight(42)
        grpFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 165 + (g-1)*58, 0)
        grpFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        grpFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        -- MotW button
        local btnMotW = CreateFrame("Button", rowName.."Group"..g.."MotW", grpFrame)
        btnMotW:SetWidth(24); btnMotW:SetHeight(24)
        btnMotW:SetPoint("LEFT", grpFrame, "LEFT", 2, 0)
        local motwBg = btnMotW:CreateTexture(btnMotW:GetName().."Background", "BACKGROUND")
        motwBg:SetAllPoints(btnMotW); motwBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local motwIcon = btnMotW:CreateTexture(btnMotW:GetName().."Icon", "OVERLAY")
        motwIcon:SetWidth(22); motwIcon:SetHeight(22); motwIcon:SetPoint("CENTER", btnMotW, "CENTER", 0, 0)
        local motwTxt = btnMotW:CreateFontString(btnMotW:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        motwTxt:SetPoint("BOTTOM", btnMotW, "BOTTOM", 0, -10); motwTxt:SetJustifyH("CENTER")
        btnMotW:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnMotW:SetScript("OnClick", function() Druid:SubButton_OnClick(this) end)
        btnMotW:SetScript("OnEnter", function() Druid:SubButton_OnEnter(this) end)
        btnMotW:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Thorns button
        local btnThorns = CreateFrame("Button", rowName.."Group"..g.."Thorns", grpFrame)
        btnThorns:SetWidth(24); btnThorns:SetHeight(24)
        btnThorns:SetPoint("LEFT", btnMotW, "RIGHT", 1, 0)
        local thornsBg = btnThorns:CreateTexture(btnThorns:GetName().."Background", "BACKGROUND")
        thornsBg:SetAllPoints(btnThorns); thornsBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local thornsIcon = btnThorns:CreateTexture(btnThorns:GetName().."Icon", "OVERLAY")
        thornsIcon:SetWidth(22); thornsIcon:SetHeight(22); thornsIcon:SetPoint("CENTER", btnThorns, "CENTER", 0, 0)
        local thornsTxt = btnThorns:CreateFontString(btnThorns:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        thornsTxt:SetPoint("BOTTOM", btnThorns, "BOTTOM", 0, -10); thornsTxt:SetJustifyH("CENTER")
        btnThorns:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnThorns:SetScript("OnClick", function() Druid:SubButton_OnClick(this) end)
        btnThorns:SetScript("OnEnter", function() Druid:SubButton_OnEnter(this) end)
        btnThorns:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    -- Innervate target button
    local innervBtn = CreateFrame("Button", rowName.."Innervate", row)
    innervBtn:SetWidth(24); innervBtn:SetHeight(24)
    innervBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 645, -8)
    local innervBg = innervBtn:CreateTexture(innervBtn:GetName().."Background", "BACKGROUND")
    innervBg:SetAllPoints(innervBtn); innervBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    local innervIcon = innervBtn:CreateTexture(innervBtn:GetName().."Icon", "OVERLAY")
    innervIcon:SetWidth(22); innervIcon:SetHeight(22); innervIcon:SetPoint("CENTER", innervBtn, "CENTER", 0, 0)
    local innervTxt = innervBtn:CreateFontString(innervBtn:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
    innervTxt:SetPoint("CENTER", innervBtn, "CENTER", 0, 0)
    innervBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    innervBtn:SetScript("OnClick", function() Druid:InnervateButton_OnClick(this) end)
    innervBtn:SetScript("OnEnter", function() Druid:InnervateButton_OnEnter(this) end)
    innervBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local innervName = row:CreateFontString(rowName.."InnervateName", "OVERLAY", "GameFontHighlightSmall")
    innervName:SetPoint("TOP", innervBtn, "BOTTOM", 0, -2)
    innervName:SetWidth(50)
    innervName:SetText("")
    
    row:Hide()
    return row
end

-----------------------------------------------------------------------------------
-- Config Grid Updates
-----------------------------------------------------------------------------------

function Druid:UpdateConfigGrid()
    if not self.ConfigWindow then return end
    
    local rowIndex = 1
    for druidName, info in pairs(self.AllDruids) do
        if rowIndex > 10 then break end
        
        local row = getglobal("CPDruidRow"..rowIndex)
        if row then
            row:Show()
            
            local nameStr = getglobal("CPDruidRow"..rowIndex.."Name")
            if nameStr then 
                local displayName = druidName
                if string.len(druidName) > 10 then
                    displayName = string.sub(druidName, 1, 9)..".."
                end
                nameStr:SetText(displayName) 
            end
            
            local clearBtn = getglobal("CPDruidRow"..rowIndex.."Clear")
            if clearBtn then
                if ClassPower_IsPromoted() or druidName == UnitName("player") then
                    clearBtn:Show()
                else
                    clearBtn:Hide()
                end
            end
            
            self:UpdateCapabilityIcons(rowIndex, druidName, info)
            self:UpdateGroupButtons(rowIndex, druidName)
            self:UpdateInnervateButton(rowIndex, druidName)
        end
        rowIndex = rowIndex + 1
    end
    
    for i = rowIndex, 10 do
        local row = getglobal("CPDruidRow"..i)
        if row then row:Hide() end
    end
    
    local newHeight = 80 + (rowIndex - 1) * 46
    if newHeight < 140 then newHeight = 140 end
    self.ConfigWindow:SetHeight(newHeight)
end

function Druid:UpdateCapabilityIcons(rowIndex, druidName, info)
    local prefix = "CPDruidRow"..rowIndex.."Cap"
    
    local function SetIcon(suffix, iconPath, hasSpell, tooltip)
        local btn = getglobal(prefix..suffix)
        if not btn then return end
        local tex = getglobal(btn:GetName().."Icon")
        if tex then
            tex:SetTexture(iconPath)
            if hasSpell then
                tex:SetDesaturated(nil)
                btn:SetAlpha(1.0)
            else
                tex:SetDesaturated(1)
                btn:SetAlpha(0.4)
            end
        end
        btn.tooltipText = tooltip
    end
    
    local motwInfo = info[0] or { rank = 0, talent = 0 }
    SetIcon("MotW", self.BuffIcons[0], motwInfo.rank > 0, "Mark of the Wild R"..motwInfo.rank..(motwInfo.talent > 0 and " (Gift)" or ""))
    
    local thornsInfo = info[1] or { rank = 0, talent = 0 }
    SetIcon("Thorns", self.BuffIcons[1], thornsInfo.rank > 0, "Thorns R"..thornsInfo.rank)
    
    SetIcon("Emerald", self.SpecialIcons["Emerald"], info["Emerald"], "Emerald Blessing")
    SetIcon("Innervate", self.SpecialIcons["Innervate"], info["Innervate"], "Innervate")
end

function Druid:UpdateGroupButtons(rowIndex, druidName)
    local assigns = self.Assignments[druidName] or {}
    
    for g = 1, 8 do
        local val = assigns[g] or 0
        local motwState = math.mod(val, 4)
        local thornsState = math.mod(math.floor(val/4), 4)
        
        local prefix = "CPDruidRow"..rowIndex.."Group"..g
        
        local function UpdateBtn(suffix, state, typeIdx, buffKey)
            local btn = getglobal(prefix..suffix)
            if not btn then return end
            local icon = getglobal(btn:GetName().."Icon")
            local text = getglobal(btn:GetName().."Text")
            
            if state > 0 then
                if state == 1 and self.BuffIconsGroup[typeIdx] then
                    icon:SetTexture(self.BuffIconsGroup[typeIdx])
                else
                    icon:SetTexture(self.BuffIcons[typeIdx])
                end
                icon:Show()
                btn:SetAlpha(1.0)
                
                local missing = 0
                local total = 0
                if self.CurrentBuffs[g] then
                    for _, m in self.CurrentBuffs[g] do
                        total = total + 1
                        if not m[buffKey] and not m.dead then missing = missing + 1 end
                    end
                end
                
                if total > 0 then
                    text:SetText((total-missing).."/"..total)
                    if missing > 0 then
                        text:SetTextColor(1, 0, 0)
                    else
                        text:SetTextColor(0, 1, 0)
                    end
                else
                    text:SetText("")
                end
            else
                icon:Hide()
                text:SetText("")
                btn:SetAlpha(0.3)
            end
        end
        
        UpdateBtn("MotW", motwState, 0, "hasMotW")
        UpdateBtn("Thorns", thornsState, 1, "hasThorns")
    end
end

function Druid:UpdateInnervateButton(rowIndex, druidName)
    local btn = getglobal("CPDruidRow"..rowIndex.."Innervate")
    local nameLabel = getglobal("CPDruidRow"..rowIndex.."InnervateName")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local target = self.LegacyAssignments[druidName] and self.LegacyAssignments[druidName]["Innervate"]
    
    icon:SetTexture(self.SpecialIcons["Innervate"])
    
    if target then
        icon:Show()
        btn:SetAlpha(1.0)
        if nameLabel then nameLabel:SetText(string.sub(target, 1, 8)) end
        getglobal(btn:GetName().."Text"):SetText("")
    else
        icon:Show()
        btn:SetAlpha(0.3)
        if nameLabel then nameLabel:SetText("") end
        getglobal(btn:GetName().."Text"):SetText("")
    end
end

-----------------------------------------------------------------------------------
-- Config Grid Click Handlers
-----------------------------------------------------------------------------------

function Druid:BuffButton_OnClick(btn)
    local name = btn:GetName()
    local _, _, rowStr, suffix = string.find(name, "ClassPowerDruidHUDRow(%d+)(.*)")
    if not rowStr then return end
    
    local i = tonumber(rowStr)
    local pname = UnitName("player")
    
    if i == 9 then
        -- Emerald Blessing - just cast it
        CastSpellByName(self.Spells.EMERALD)
    else
        local gid = i
        local spellName = nil
        local buffKey = nil
        local isRightClick = (arg1 == "RightButton")
        
        if suffix == "MotW" then
            buffKey = "hasMotW"
            spellName = isRightClick and self.Spells.MOTW or self.Spells.GOTW
        elseif suffix == "Thorns" then
            buffKey = "hasThorns"
            spellName = self.Spells.THORNS
        end
        
        if spellName and self.CurrentBuffs[gid] then
            for _, member in self.CurrentBuffs[gid] do
                if member.visible and not member.dead and not member[buffKey] then
                    ClearTarget()
                    TargetByName(member.name, true)
                    if UnitExists("target") and UnitName("target") == member.name then
                        if CheckInteractDistance("target", 4) then
                            CastSpellByName(spellName)
                            TargetLastTarget()
                            self:ScanRaid()
                            self:UpdateBuffBar()
                            return
                        end
                    end
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No targets in range for Group "..gid)
            TargetLastTarget()
        end
    end
end

function Druid:ClearButton_OnClick(btn)
    local rowName = btn:GetParent():GetName()
    local _, _, rowIdx = string.find(rowName, "CPDruidRow(%d+)")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    if not druidName then return end
    
    if not ClassPower_IsPromoted() and druidName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Permission denied.")
        return
    end
    
    self.Assignments[druidName] = {}
    self.LegacyAssignments[druidName] = {}
    ClassPower_SendMessage("DCLEAR "..druidName)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared assignments for "..druidName)
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Druid:SubButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx, grpIdx, buffType = string.find(btnName, "CPDruidRow(%d+)Group(%d+)(.*)")
    if not rowIdx or not grpIdx or not buffType then return end
    
    rowIdx = tonumber(rowIdx)
    grpIdx = tonumber(grpIdx)
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    if not druidName then return end
    
    if not ClassPower_IsPromoted() and druidName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.Assignments[druidName] = self.Assignments[druidName] or {}
    local cur = self.Assignments[druidName][grpIdx] or 0
    
    local motw = math.mod(cur, 4)
    local thorns = math.mod(math.floor(cur/4), 4)
    
    -- Shift-click cycles both buffs together
    if IsShiftKeyDown() then
        local maxState = motw
        if thorns > maxState then maxState = thorns end
        local newState = math.mod(maxState + 1, 3)
        motw = newState
        thorns = newState
    else
        if buffType == "MotW" then
            motw = math.mod(motw + 1, 3)
        elseif buffType == "Thorns" then
            thorns = math.mod(thorns + 1, 3)
        end
    end
    
    cur = motw + (thorns * 4)
    self.Assignments[druidName][grpIdx] = cur
    ClassPower_SendMessage("DASSIGN "..druidName.." "..grpIdx.." "..cur)
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Druid:SubButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, _, _, buffType = string.find(btnName, "CPDruidRow(%d+)Group(%d+)(.*)")
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local label = buffType or "Unknown"
    if buffType == "MotW" then label = "Mark of the Wild"
    elseif buffType == "Thorns" then label = "Thorns"
    end
    GameTooltip:SetText(label)
    GameTooltip:AddLine("Click to cycle:", 1, 1, 1)
    GameTooltip:AddLine("Off -> Group -> Single", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Shift-Click: Cycle ALL buffs", 0, 1, 0)
    GameTooltip:Show()
end

function Druid:InnervateButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPDruidRow(%d+)Innervate")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    if not druidName then return end
    
    if not ClassPower_IsPromoted() and druidName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.ContextName = druidName
    self.AssignMode = "Innervate"
    ToggleDropDownMenu(1, nil, ClassPowerDruidDropDown, btn, 0, 0)
end

function Druid:InnervateButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPDruidRow(%d+)Innervate")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    local target = self.LegacyAssignments[druidName] and self.LegacyAssignments[druidName]["Innervate"]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Innervate Assignment")
    if target then
        GameTooltip:AddLine("Target: "..target, 0, 1, 0)
    else
        GameTooltip:AddLine("Click to assign", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-----------------------------------------------------------------------------------
-- Update UI
-----------------------------------------------------------------------------------

function Druid:UpdateUI()
    self:UpdateBuffBar()
    if self.ConfigWindow and self.ConfigWindow:IsVisible() then
        self:UpdateConfigGrid()
    end
end

function Druid:ResetUI()
    CP_PerUser.DruidPoint = nil
    CP_PerUser.DruidRelativePoint = nil
    CP_PerUser.DruidX = nil
    CP_PerUser.DruidY = nil
    CP_PerUser.DruidScale = 0.7
    CP_PerUser.DruidConfigScale = 1.0
    
    if self.BuffBar then
        self.BuffBar:ClearAllPoints()
        self.BuffBar:SetPoint("CENTER", 0, 0)
        self.BuffBar:SetScale(0.7)
    end
    
    if self.ConfigWindow then
        self.ConfigWindow:ClearAllPoints()
        self.ConfigWindow:SetPoint("CENTER", 0, 0)
        self.ConfigWindow:SetScale(1.0)
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: UI reset to defaults.")
end

-----------------------------------------------------------------------------------
-- Innervate Dropdown
-----------------------------------------------------------------------------------

function Druid:InnervateDropDown_Initialize(level)
    if not level then level = 1 end
    local info = {}
    
    if level == 1 then
        info = {}
        info.text = ">> Clear <<"
        info.value = "CLEAR"
        info.func = function() Druid:AssignTarget_OnClick() end
        UIDropDownMenu_AddButton(info)
        
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            local groups = {}
            for g = 1, 8 do groups[g] = {} end
            for i = 1, numRaid do
                local name, _, subgroup = GetRaidRosterInfo(i)
                if name and subgroup >= 1 and subgroup <= 8 then
                    table.insert(groups[subgroup], name)
                end
            end
            for g = 1, 8 do
                if table.getn(groups[g]) > 0 then
                    info = {}
                    info.text = "Group "..g
                    info.hasArrow = 1
                    info.value = g
                    UIDropDownMenu_AddButton(info)
                end
            end
        else
            local numParty = GetNumPartyMembers()
            info = {}
            info.text = UnitName("player")
            info.value = UnitName("player")
            info.func = function() Druid:AssignTarget_OnClick() end
            UIDropDownMenu_AddButton(info)
            for i = 1, numParty do
                local name = UnitName("party"..i)
                if name then
                    info = {}
                    info.text = name
                    info.value = name
                    info.func = function() Druid:AssignTarget_OnClick() end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
    elseif level == 2 then
        local groupID = UIDROPDOWNMENU_MENU_VALUE
        if type(groupID) == "number" then
            for i = 1, GetNumRaidMembers() do
                local name, _, subgroup = GetRaidRosterInfo(i)
                if name and subgroup == groupID then
                    info = {}
                    info.text = name
                    info.value = name
                    info.func = function() Druid:AssignTarget_OnClick() end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end
end

function Druid:AssignTarget_OnClick()
    local targetName = this.value
    local pname = self.ContextName
    local mode = self.AssignMode or "Innervate"
    
    if not pname then pname = UnitName("player") end
    self.LegacyAssignments[pname] = self.LegacyAssignments[pname] or {}
    
    if targetName == "CLEAR" then
        self.LegacyAssignments[pname][mode] = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared "..mode.." for "..pname)
        ClassPower_SendMessage("DASSIGNTARGET "..pname.." nil")
    else
        self.LegacyAssignments[pname][mode] = targetName
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..pname.." "..mode.." = "..targetName)
        ClassPower_SendMessage("DASSIGNTARGET "..pname.." "..targetName)
    end
    
    self:UpdateUI()
    CloseDropDownMenus()
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("DRUID", Druid)
