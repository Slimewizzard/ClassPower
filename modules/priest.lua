-- ClassPower: Priest Module
-- Full buff management for Priest class

local Priest = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Priest.Spells = {
    FORTITUDE = "Power Word: Fortitude",
    P_FORTITUDE = "Prayer of Fortitude",
    SPIRIT = "Divine Spirit",
    P_SPIRIT = "Prayer of Spirit",
    SHADOW_PROT = "Shadow Protection",
    P_SHADOW_PROT = "Prayer of Shadow Protection",
    PROCLAIM = "Proclaim Champion",
    GRACE = "Champion's Grace",
    EMPOWER = "Empower Champion",
    REVIVE = "Revive Champion",
    ENLIGHTEN = "Enlighten",
}

Priest.BuffIcons = {
    [0] = "Interface\\Icons\\Spell_Holy_WordFortitude",
    [1] = "Interface\\Icons\\Spell_Holy_DivineSpirit",
    [2] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
}

Priest.BuffIconsGroup = {
    [0] = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    [1] = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",
    [2] = "Interface\\Icons\\Spell_Holy_PrayerOfShadowProtection",
}

Priest.ChampionIcons = {
    ["Proclaim"] = "Interface\\Icons\\Spell_Holy_ProclaimChampion",
    ["Grace"] = "Interface\\Icons\\Spell_Holy_ChampionsGrace",
    ["Empower"] = "Interface\\Icons\\Spell_Holy_EmpowerChampion",
    ["Revive"] = "Interface\\Icons\\spell_holy_revivechampion",
    ["Enlighten"] = "Interface\\Icons\\btnholyscriptures",
}

Priest.SpellDurations = {
    ["Proclaim"] = 7200,
    ["Grace"] = 1800,
    ["Empower"] = 600,
}

-- Buff type constants
Priest.BUFF_FORT = 0
Priest.BUFF_SPIRIT = 1
Priest.BUFF_SHADOW = 2

-----------------------------------------------------------------------------------
-- State
-----------------------------------------------------------------------------------

Priest.AllPriests = {}
Priest.CurrentBuffs = {}
Priest.CurrentBuffsByName = {}
Priest.Assignments = {}
Priest.LegacyAssignments = {}
Priest.BuffTimers = {}
Priest.RankInfo = {}

-- Timers
Priest.NextScan = 10
Priest.UpdateTimer = 0
Priest.LastRequest = 0
Priest.RosterDirty = false
Priest.RosterTimer = 0.5

-- Context for dropdowns
Priest.ContextName = nil
Priest.AssignMode = "Champ"

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Priest:OnLoad()
    CP_Debug("Priest:OnLoad()")
    
    -- Migrate old saved variables if they exist
    self:MigrateSavedVars()
    
    -- Initial spell scan
    self:ScanSpells()
    self:ScanRaid()
    
    -- Create UI
    self:CreateBuffBar()
    self:CreateConfigWindow()
    
    -- Create dropdown
    if not getglobal("ClassPowerPriestDropDown") then
        CreateFrame("Frame", "ClassPowerPriestDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerPriestDropDown, function(level) Priest:ChampDropDown_Initialize(level) end, "MENU")
    
    -- Request sync from other priests
    self:RequestSync()
end

function Priest:MigrateSavedVars()
    -- Migrate from old PriestPower saved vars
    if PriestPower_Assignments then
        self.Assignments = PriestPower_Assignments
    end
    if PriestPower_LegacyAssignments then
        self.LegacyAssignments = PriestPower_LegacyAssignments
    end
    if PP_BuffTimers then
        self.BuffTimers = PP_BuffTimers
    end
    if PP_PerUser then
        for k, v in pairs(PP_PerUser) do
            CP_PerUser[k] = v
        end
    end
end

function Priest:OnEvent(event)
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
        
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
        -- arg1 is passed through OnEvent
    end
end

function Priest:OnUpdate(elapsed)
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

function Priest:OnSlashCommand(msg)
    if msg == "revive" or msg == "reviveChamp" then
        local pname = UnitName("player")
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Champ"]
        if target then
            ClearTarget()
            TargetByName(target, true)
            if UnitName("target") == target then
                CastSpellByName(self.Spells.REVIVE)
                TargetLastTarget()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target "..target)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Champion Assigned!")
        end
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

function Priest:ScanSpells()
    local info = {
        [0] = { rank = 0, talent = 0, name = "Fortitude" },
        [1] = { rank = 0, talent = 0, name = "Spirit" },
        [2] = { rank = 0, talent = 0, name = "Shadow" },
        ["Proclaim"] = false,
        ["Grace"] = false,
        ["Empower"] = false,
        ["Revive"] = false,
        ["Enlighten"] = false,
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
        
        -- Fortitude
        if spellName == self.Spells.FORTITUDE then
            if rank > info[0].rank then info[0].rank = rank end
        elseif spellName == self.Spells.P_FORTITUDE then
            info[0].talent = 1
        end
        
        -- Spirit
        if spellName == self.Spells.SPIRIT then
            if rank > info[1].rank then info[1].rank = rank end
        elseif spellName == self.Spells.P_SPIRIT then
            info[1].talent = 1
        end
        
        -- Shadow Protection
        if spellName == self.Spells.SHADOW_PROT then
            if rank > info[2].rank then info[2].rank = rank end
        elseif spellName == self.Spells.P_SHADOW_PROT then
            info[2].talent = 1
        end
        
        -- Champion spells
        if spellName == self.Spells.PROCLAIM or spellName == "Holy Champion" then
            info["Proclaim"] = true
        end
        if spellName == self.Spells.GRACE then info["Grace"] = true end
        if spellName == self.Spells.EMPOWER then info["Empower"] = true end
        if spellName == self.Spells.REVIVE then info["Revive"] = true end
        if spellName == self.Spells.ENLIGHTEN then info["Enlighten"] = true end
        
        i = i + 1
    end
    
    self.AllPriests[UnitName("player")] = info
    self.RankInfo = info
end

-----------------------------------------------------------------------------------
-- Raid/Buff Scanning
-----------------------------------------------------------------------------------

function Priest:ScanRaid()
    self.CurrentBuffs = {}
    for i = 1, 8 do self.CurrentBuffs[i] = {} end
    self.CurrentBuffsByName = {}
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local foundPriests = {}
    
    if UnitClass("player") == "Priest" then
        foundPriests[UnitName("player")] = true
    end
    
    local function ProcessUnit(unit, name, subgroup, class)
        local isValid = (unit == "player") or string.find(unit, "^party%d+$") or string.find(unit, "^raid%d+$")
        if not isValid or not UnitExists(unit) then return end
        
        if name and class == "PRIEST" then
            foundPriests[name] = true
            if not self.AllPriests[name] then
                self.AllPriests[name] = {
                    [0] = { rank = 0, talent = 0, name = "Fortitude" },
                    [1] = { rank = 0, talent = 0, name = "Spirit" },
                    [2] = { rank = 0, talent = 0, name = "Shadow" },
                    ["Proclaim"] = false,
                    ["Grace"] = false,
                    ["Empower"] = false,
                    ["Revive"] = false,
                    ["Enlighten"] = false,
                }
            end
        end
        
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            local buffInfo = {
                name = name,
                class = class,
                visible = UnitIsVisible(unit),
                dead = UnitIsDeadOrGhost(unit),
                hasFort = false,
                hasSpirit = false,
                hasShadow = false,
                hasProclaim = false,
                hasGrace = false,
                hasEmpower = false,
                hasEnlighten = false,
            }
            
            local b = 1
            while true do
                local bname = UnitBuff(unit, b)
                if not bname then break end
                
                bname = string.lower(bname)
                
                if string.find(bname, "fortitude") then buffInfo.hasFort = true end
                if string.find(bname, "spirit") or string.find(bname, "inspiration") then buffInfo.hasSpirit = true end
                if string.find(bname, "shadow") and (string.find(bname, "protection") or string.find(bname, "antishadow")) then
                    buffInfo.hasShadow = true
                end
                if string.find(bname, "proclaimchampion") or string.find(bname, "holychampion") then buffInfo.hasProclaim = true end
                if string.find(bname, "championsgrace") then buffInfo.hasGrace = true end
                if string.find(bname, "empowerchampion") then buffInfo.hasEmpower = true end
                if string.find(bname, "btnholyscriptures") or string.find(bname, "enlighten") then buffInfo.hasEnlighten = true end
                
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
    
    -- Cleanup priests who left
    for name, _ in pairs(self.AllPriests) do
        if not foundPriests[name] then
            self.AllPriests[name] = nil
            self.Assignments[name] = nil
        end
    end
end

-----------------------------------------------------------------------------------
-- Sync Protocol
-----------------------------------------------------------------------------------

function Priest:RequestSync()
    ClassPower_SendMessage("REQ")
end

function Priest:SendSelf()
    local pname = UnitName("player")
    local myRanks = self.AllPriests[pname]
    if not myRanks then return end
    
    local msg = "SELF "
    
    for i = 0, 2 do
        if myRanks[i] then
            msg = msg .. myRanks[i].rank .. myRanks[i].talent
        else
            msg = msg .. "00"
        end
    end
    
    msg = msg .. (myRanks["Proclaim"] and "1" or "0")
    msg = msg .. (myRanks["Grace"] and "1" or "0")
    msg = msg .. (myRanks["Empower"] and "1" or "0")
    msg = msg .. (myRanks["Revive"] and "1" or "0")
    msg = msg .. (myRanks["Enlighten"] and "1" or "0")
    
    msg = msg .. "@"
    
    local assigns = self.Assignments[pname]
    for i = 1, 8 do
        local val = 0
        if assigns and assigns[i] then val = assigns[i] end
        msg = msg .. val
    end
    
    msg = msg .. "@"
    
    local champ = "nil"
    if self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Champ"] then
        champ = self.LegacyAssignments[pname]["Champ"]
    end
    msg = msg .. champ
    
    ClassPower_SendMessage(msg)
end

function Priest:OnAddonMessage(sender, msg)
    if sender == UnitName("player") then return end
    
    if msg == "REQ" then
        self:SendSelf()
        
    elseif string.find(msg, "^SELF") then
        local _, _, ranks, assigns, champ = string.find(msg, "SELF (.-)@(.-)@(.*)")
        if not ranks then return end
        
        self.AllPriests[sender] = self.AllPriests[sender] or {}
        local info = self.AllPriests[sender]
        
        for id = 0, 2 do
            local r = string.sub(ranks, id*2+1, id*2+1)
            local t = string.sub(ranks, id*2+2, id*2+2)
            if r ~= "n" then
                info[id] = { rank = tonumber(r) or 0, talent = tonumber(t) or 0 }
            end
        end
        
        info["Proclaim"] = (string.sub(ranks, 7, 7) == "1")
        info["Grace"] = (string.sub(ranks, 8, 8) == "1")
        info["Empower"] = (string.sub(ranks, 9, 9) == "1")
        info["Revive"] = (string.sub(ranks, 10, 10) == "1")
        info["Enlighten"] = (string.sub(ranks, 11, 11) == "1")
        
        self.Assignments[sender] = self.Assignments[sender] or {}
        for gid = 1, 8 do
            local val = string.sub(assigns, gid, gid)
            if val ~= "n" and val ~= "" then
                self.Assignments[sender][gid] = tonumber(val)
            end
        end
        
        self.LegacyAssignments[sender] = self.LegacyAssignments[sender] or {}
        if champ and champ ~= "" and champ ~= "nil" then
            self.LegacyAssignments[sender]["Champ"] = champ
        else
            self.LegacyAssignments[sender]["Champ"] = nil
        end
        
    elseif string.find(msg, "^ASSIGN ") then
        local _, _, name, class, skill = string.find(msg, "^ASSIGN (.-) (.-) (.*)")
        if name and class and skill then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                self.Assignments[name][tonumber(class)] = tonumber(skill)
                self:UpdateUI()
            end
        end
        
    elseif string.find(msg, "^ASSIGNCHAMP ") then
        local _, _, name, target = string.find(msg, "^ASSIGNCHAMP (.-) (.*)")
        if name and target then
            if sender == name or ClassPower_IsPromoted(sender) then
                if target == "nil" or target == "" then target = nil end
                self.LegacyAssignments[name] = self.LegacyAssignments[name] or {}
                self.LegacyAssignments[name]["Champ"] = target
                self:UpdateUI()
            end
        end
        
    elseif string.find(msg, "^CLEAR ") then
        local _, _, target = string.find(msg, "^CLEAR (.*)")
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

function Priest:CreateBuffBar()
    if getglobal("ClassPowerPriestBuffBar") then 
        self.BuffBar = getglobal("ClassPowerPriestBuffBar")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerPriestBuffBar", UIParent)
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
        Priest:SaveBuffBarPosition()
    end)
    
    -- Resize grip
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Priest:SaveBuffBarPosition()
    end)
    
    -- Create HUD rows
    for i = 1, 10 do
        local row = self:CreateHUDRow(f, "ClassPowerHUDRow"..i, i)
        row:Hide()
    end
    
    -- Restore position
    if CP_PerUser.Point then
        f:ClearAllPoints()
        f:SetPoint(CP_PerUser.Point, "UIParent", CP_PerUser.RelativePoint or "CENTER", CP_PerUser.X or 0, CP_PerUser.Y or 0)
    else
        f:SetPoint("CENTER", 0, 0)
    end
    
    if CP_PerUser.Scale then
        f:SetScale(CP_PerUser.Scale)
    else
        f:SetScale(0.7)
    end
    
    self.BuffBar = f
end

function Priest:CreateHUDRow(parent, name, id)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(140)
    f:SetHeight(34)
    
    local label = f:CreateFontString(f:GetName().."Label", "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", f, "LEFT", 5, 0)
    
    if id == 9 then
        label:SetText("Chmp")
    elseif id == 10 then
        label:SetText("Enlt")
    else
        label:SetText("Grp "..id)
    end
    
    -- Standard buff buttons for groups 1-8
    if id <= 8 then
        local fort = CP_CreateHUDButton(f, name.."Fort")
        fort:SetPoint("LEFT", f, "LEFT", 40, 0)
        fort:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local spirit = CP_CreateHUDButton(f, name.."Spirit")
        spirit:SetPoint("LEFT", fort, "RIGHT", 2, 0)
        spirit:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local shadow = CP_CreateHUDButton(f, name.."Shadow")
        shadow:SetPoint("LEFT", spirit, "RIGHT", 2, 0)
        shadow:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
    end
    
    -- Champion buttons for row 9
    if id == 9 then
        local proc = CP_CreateHUDButton(f, name.."Proclaim")
        proc:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(proc:GetName().."Icon"):SetTexture(self.ChampionIcons["Proclaim"])
        proc:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local grace = CP_CreateHUDButton(f, name.."Grace")
        grace:SetPoint("LEFT", proc, "RIGHT", 2, 0)
        getglobal(grace:GetName().."Icon"):SetTexture(self.ChampionIcons["Grace"])
        grace:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local emp = CP_CreateHUDButton(f, name.."Empower")
        emp:SetPoint("LEFT", grace, "RIGHT", 2, 0)
        getglobal(emp:GetName().."Icon"):SetTexture(self.ChampionIcons["Empower"])
        emp:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local rev = CP_CreateHUDButton(f, name.."Revive")
        rev:SetPoint("LEFT", emp, "RIGHT", 2, 0)
        getglobal(rev:GetName().."Icon"):SetTexture(self.ChampionIcons["Revive"])
        rev:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        f:SetWidth(180)
    end
    
    -- Enlighten button for row 10
    if id == 10 then
        local en = CP_CreateHUDButton(f, name.."Enlighten")
        en:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(en:GetName().."Icon"):SetTexture(self.ChampionIcons["Enlighten"])
        en:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
    end
    
    return f
end

function Priest:SaveBuffBarPosition()
    if not self.BuffBar then return end
    
    local point, _, relativePoint, x, y = self.BuffBar:GetPoint()
    CP_PerUser.Point = point
    CP_PerUser.RelativePoint = relativePoint
    CP_PerUser.X = x
    CP_PerUser.Y = y
    CP_PerUser.Scale = self.BuffBar:GetScale()
end

function Priest:UpdateBuffBar()
    if not self.BuffBar then return end
    
    local f = self.BuffBar
    local pname = UnitName("player")
    local assigns = self.Assignments[pname]
    
    local lastRow = nil
    local count = 0
    
    for i = 1, 10 do
        local row = getglobal("ClassPowerHUDRow"..i)
        if not row then break end
        
        local showRow = false
        
        if i == 9 then
            -- Champion row
            local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Champ"]
            if target then
                local status = self.CurrentBuffsByName[target]
                local btnP = getglobal(row:GetName().."Proclaim")
                local btnG = getglobal(row:GetName().."Grace")
                local btnE = getglobal(row:GetName().."Empower")
                local btnR = getglobal(row:GetName().."Revive")
                
                if status and status.dead then
                    btnP:Hide(); btnG:Hide(); btnE:Hide(); btnR:Show()
                    btnR.tooltipText = "Champion: "..target.." (DEAD)"
                    showRow = true
                else
                    btnR:Hide()
                    
                    if not status or not status.hasProclaim then
                        btnP:Show()
                        btnP.tooltipText = "Proclaim: "..target
                        getglobal(btnP:GetName().."Text"):SetText("0/1")
                        getglobal(btnP:GetName().."Text"):SetTextColor(1,0,0)
                        showRow = true
                    else
                        btnP:Hide()
                    end
                    
                    if status and (status.hasGrace or status.hasEmpower) then
                        btnG:Hide(); btnE:Hide()
                    else
                        btnG:Show(); btnE:Show()
                        btnG.tooltipText = "Grace: "..target
                        btnE.tooltipText = "Empower: "..target
                        showRow = true
                    end
                end
            end
            
        elseif i == 10 then
            -- Enlighten row
            local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Enlighten"]
            if target then
                local status = self.CurrentBuffsByName[target]
                local btnEn = getglobal(row:GetName().."Enlighten")
                
                if not status or not status.hasEnlighten then
                    btnEn:Show()
                    btnEn.tooltipText = "Enlighten: "..target
                    getglobal(btnEn:GetName().."Text"):SetText("0/1")
                    getglobal(btnEn:GetName().."Text"):SetTextColor(1,0,0)
                    showRow = true
                else
                    btnEn:Hide()
                end
            end
            
        elseif assigns and assigns[i] and assigns[i] > 0 then
            -- Group buff rows
            local val = assigns[i]
            local fS = math.mod(val, 4)
            local sS = math.mod(math.floor(val/4), 4)
            local shS = math.mod(math.floor(val/16), 4)
            
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
                            icon:SetTexture(self.BuffIconsGroup[typeIdx])
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
            
            local f1 = UpdateHUD(getglobal(row:GetName().."Fort"), fS, 0, "hasFort", "Fortitude")
            local f2 = UpdateHUD(getglobal(row:GetName().."Spirit"), sS, 1, "hasSpirit", "Spirit")
            local f3 = UpdateHUD(getglobal(row:GetName().."Shadow"), shS, 2, "hasShadow", "Shadow")
            showRow = f1 or f2 or f3
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
    
    -- Resize frame
    local newHeight = 25 + (count * 34)
    if newHeight < 40 then newHeight = 40 end
    f:SetHeight(newHeight)
end

function Priest:BuffButton_OnClick(btn)
    local name = btn:GetName()
    local _, _, rowStr, suffix = string.find(name, "ClassPowerHUDRow(%d+)(.*)")
    if not rowStr then return end
    
    local i = tonumber(rowStr)
    local pname = UnitName("player")
    
    if i == 9 then
        -- Champion cast
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Champ"]
        if not target then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Champion Assigned!")
            return
        end
        
        local spell = nil
        if suffix == "Proclaim" then spell = self.Spells.PROCLAIM
        elseif suffix == "Grace" then spell = self.Spells.GRACE
        elseif suffix == "Empower" then spell = self.Spells.EMPOWER
        elseif suffix == "Revive" then spell = self.Spells.REVIVE
        end
        
        if spell then
            ClearTarget()
            TargetByName(target, true)
            if UnitName("target") == target then
                CastSpellByName(spell)
                TargetLastTarget()
                self:ScanRaid()
                self:UpdateBuffBar()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target "..target)
            end
        end
        
    elseif i == 10 then
        -- Enlighten cast
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Enlighten"]
        if not target then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Enlighten target!")
            return
        end
        
        ClearTarget()
        TargetByName(target, true)
        if UnitName("target") == target then
            CastSpellByName(self.Spells.ENLIGHTEN)
            TargetLastTarget()
            self:ScanRaid()
            self:UpdateBuffBar()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target "..target)
        end
        
    else
        -- Group buff cast
        local gid = i
        local spellName = nil
        local buffKey = nil
        local isRightClick = (arg1 == "RightButton")
        
        if suffix == "Fort" then
            buffKey = "hasFort"
            spellName = isRightClick and self.Spells.FORTITUDE or self.Spells.P_FORTITUDE
        elseif suffix == "Spirit" then
            buffKey = "hasSpirit"
            spellName = isRightClick and self.Spells.SPIRIT or self.Spells.P_SPIRIT
        elseif suffix == "Shadow" then
            buffKey = "hasShadow"
            spellName = isRightClick and self.Spells.SHADOW_PROT or self.Spells.P_SHADOW_PROT
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

-----------------------------------------------------------------------------------
-- UI: Config Window with Full Grid
-----------------------------------------------------------------------------------

function Priest:CreateConfigWindow()
    if getglobal("ClassPowerPriestConfig") then 
        self.ConfigWindow = getglobal("ClassPowerPriestConfig")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerPriestConfig", UIParent)
    f:SetWidth(920)
    f:SetHeight(400)
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
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("ClassPower - Priest Configuration")
    
    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Drag
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Resize Grip
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 15)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        CP_PerUser.ConfigScale = p:GetScale()
    end)
    
    -- Header Row
    local headerY = -45
    
    -- "Priest" label
    local lblPriest = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblPriest:SetPoint("TOPLEFT", f, "TOPLEFT", 30, headerY)
    lblPriest:SetText("Priest")
    
    -- "Capabilities" label
    local lblCaps = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblCaps:SetPoint("TOPLEFT", f, "TOPLEFT", 130, headerY)
    lblCaps:SetText("Spells")
    
    -- Group headers (1-8)
    for g = 1, 8 do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 240 + (g-1)*70, headerY)
        lbl:SetText("Grp "..g)
    end
    
    -- Champion header
    local lblChamp = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblChamp:SetPoint("TOPLEFT", f, "TOPLEFT", 810, headerY)
    lblChamp:SetText("Champ")
    
    -- Enlighten header
    local lblEnlight = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblEnlight:SetPoint("TOPLEFT", f, "TOPLEFT", 870, headerY)
    lblEnlight:SetText("Enlt")
    
    -- Create priest rows (up to 10)
    for i = 1, 10 do
        self:CreateConfigRow(f, i)
    end
    
    -- Apply saved scale
    if CP_PerUser.ConfigScale then
        f:SetScale(CP_PerUser.ConfigScale)
    else
        f:SetScale(0.8)
    end
    
    f:Hide()
    self.ConfigWindow = f
end

function Priest:CreateConfigRow(parent, rowIndex)
    local rowName = "CPPriestRow"..rowIndex
    local row = CreateFrame("Frame", rowName, parent)
    row:SetWidth(880)
    row:SetHeight(42)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -55 - (rowIndex-1)*44)
    
    -- Clear Button
    local clearBtn = CP_CreateClearButton(row, rowName.."Clear", function()
        Priest:ClearButton_OnClick(this)
    end)
    clearBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    
    -- Priest Name
    local nameStr = row:CreateFontString(rowName.."Name", "OVERLAY", "GameFontHighlightSmall")
    nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 18, -15)
    nameStr:SetWidth(100)
    nameStr:SetHeight(16)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("")
    
    -- Capability Icons Frame (Fort, Spirit, Shadow, Proclaim, Grace, Empower, Revive, Enlighten)
    local caps = CreateFrame("Frame", rowName.."Caps", row)
    caps:SetWidth(130)
    caps:SetHeight(20)
    caps:SetPoint("TOPLEFT", row, "TOPLEFT", 110, -12)
    
    local function CreateCapIcon(suffix, xOffset)
        local btn = CP_CreateCapabilityIcon(caps, rowName.."Cap"..suffix)
        btn:SetPoint("TOPLEFT", caps, "TOPLEFT", xOffset, 0)
        return btn
    end
    
    CreateCapIcon("Fort", 0)
    CreateCapIcon("Spirit", 18)
    CreateCapIcon("Shadow", 36)
    CreateCapIcon("Proclaim", 58)
    CreateCapIcon("Grace", 76)
    CreateCapIcon("Empower", 94)
    CreateCapIcon("Revive", 112)
    
    -- Group Buttons (1-8) - Each group has Fort/Spirit/Shadow sub-buttons
    for g = 1, 8 do
        local grpFrame = CreateFrame("Frame", rowName.."Group"..g, row)
        grpFrame:SetWidth(68)
        grpFrame:SetHeight(42)
        grpFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 220 + (g-1)*70, 0)
        grpFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        grpFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        -- Fort button
        local btnFort = CP_CreateSubButton(grpFrame, rowName.."Group"..g.."Fort")
        btnFort:SetPoint("LEFT", grpFrame, "LEFT", 2, 0)
        btnFort:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnFort:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnFort:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Spirit button
        local btnSpirit = CP_CreateSubButton(grpFrame, rowName.."Group"..g.."Spirit")
        btnSpirit:SetPoint("LEFT", btnFort, "RIGHT", 0, 0)
        btnSpirit:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnSpirit:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnSpirit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- Shadow button
        local btnShadow = CP_CreateSubButton(grpFrame, rowName.."Group"..g.."Shadow")
        btnShadow:SetPoint("LEFT", btnSpirit, "RIGHT", 0, 0)
        btnShadow:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnShadow:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnShadow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    -- Champion Button
    local champBtn = CP_CreateSubButton(row, rowName.."Champ")
    champBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 795, -9)
    champBtn:SetScript("OnClick", function() Priest:ChampButton_OnClick(this) end)
    champBtn:SetScript("OnEnter", function() Priest:ChampButton_OnEnter(this) end)
    champBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Champion Name Label
    local champName = row:CreateFontString(rowName.."ChampName", "OVERLAY", "GameFontHighlightSmall")
    champName:SetPoint("TOP", champBtn, "BOTTOM", 0, -2)
    champName:SetWidth(50)
    champName:SetText("")
    
    -- Enlighten Button
    local enlightBtn = CP_CreateSubButton(row, rowName.."Enlighten")
    enlightBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 855, -9)
    enlightBtn:SetScript("OnClick", function() Priest:EnlightenButton_OnClick(this) end)
    enlightBtn:SetScript("OnEnter", function() Priest:EnlightenButton_OnEnter(this) end)
    enlightBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Enlighten Name Label
    local enlightName = row:CreateFontString(rowName.."EnlightenName", "OVERLAY", "GameFontHighlightSmall")
    enlightName:SetPoint("TOP", enlightBtn, "BOTTOM", 0, -2)
    enlightName:SetWidth(50)
    enlightName:SetText("")
    
    row:Hide()
    return row
end

function Priest:UpdateConfigGrid()
    if not self.ConfigWindow then return end
    
    local rowIndex = 1
    
    for priestName, info in pairs(self.AllPriests) do
        if rowIndex > 10 then break end
        
        local row = getglobal("CPPriestRow"..rowIndex)
        if row then
            row:Show()
            
            -- Set priest name
            local nameStr = getglobal("CPPriestRow"..rowIndex.."Name")
            if nameStr then nameStr:SetText(priestName) end
            
            -- Show/hide clear button based on permission
            local clearBtn = getglobal("CPPriestRow"..rowIndex.."Clear")
            if clearBtn then
                if ClassPower_IsPromoted() or priestName == UnitName("player") then
                    clearBtn:Show()
                else
                    clearBtn:Hide()
                end
            end
            
            -- Update capability icons
            self:UpdateCapabilityIcons(rowIndex, priestName, info)
            
            -- Update group buttons
            self:UpdateGroupButtons(rowIndex, priestName)
            
            -- Update champion button
            self:UpdateChampButton(rowIndex, priestName)
            
            -- Update enlighten button
            self:UpdateEnlightenButton(rowIndex, priestName)
        end
        
        rowIndex = rowIndex + 1
    end
    
    -- Hide unused rows
    for i = rowIndex, 10 do
        local row = getglobal("CPPriestRow"..i)
        if row then row:Hide() end
    end
    
    -- Adjust window height
    local newHeight = 70 + (rowIndex - 1) * 44
    if newHeight < 120 then newHeight = 120 end
    self.ConfigWindow:SetHeight(newHeight)
end

function Priest:UpdateCapabilityIcons(rowIndex, priestName, info)
    local prefix = "CPPriestRow"..rowIndex.."Cap"
    
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
    
    -- Standard buffs (0=Fort, 1=Spirit, 2=Shadow)
    local fortInfo = info[0] or { rank = 0, talent = 0 }
    SetIcon("Fort", self.BuffIcons[0], fortInfo.rank > 0, 
        "Fortitude R"..fortInfo.rank..(fortInfo.talent > 0 and " (Prayer)" or ""))
    
    local spiritInfo = info[1] or { rank = 0, talent = 0 }
    SetIcon("Spirit", self.BuffIcons[1], spiritInfo.rank > 0,
        "Spirit R"..spiritInfo.rank..(spiritInfo.talent > 0 and " (Prayer)" or ""))
    
    local shadowInfo = info[2] or { rank = 0, talent = 0 }
    SetIcon("Shadow", self.BuffIcons[2], shadowInfo.rank > 0,
        "Shadow R"..shadowInfo.rank..(shadowInfo.talent > 0 and " (Prayer)" or ""))
    
    -- Champion spells
    SetIcon("Proclaim", self.ChampionIcons["Proclaim"], info["Proclaim"], "Proclaim Champion")
    SetIcon("Grace", self.ChampionIcons["Grace"], info["Grace"], "Champion's Grace")
    SetIcon("Empower", self.ChampionIcons["Empower"], info["Empower"], "Empower Champion")
    SetIcon("Revive", self.ChampionIcons["Revive"], info["Revive"], "Revive Champion")
end

function Priest:UpdateGroupButtons(rowIndex, priestName)
    local assigns = self.Assignments[priestName] or {}
    
    for g = 1, 8 do
        local val = assigns[g] or 0
        local fState = math.mod(val, 4)
        local sState = math.mod(math.floor(val/4), 4)
        local shState = math.mod(math.floor(val/16), 4)
        
        local prefix = "CPPriestRow"..rowIndex.."Group"..g
        
        local function UpdateBtn(suffix, state, typeIdx, buffKey)
            local btn = getglobal(prefix..suffix)
            if not btn then return end
            
            local icon = getglobal(btn:GetName().."Icon")
            local text = getglobal(btn:GetName().."Text")
            
            if state > 0 then
                if state == 1 then
                    icon:SetTexture(self.BuffIconsGroup[typeIdx])
                else
                    icon:SetTexture(self.BuffIcons[typeIdx])
                end
                icon:Show()
                btn:SetAlpha(1.0)
                
                -- Count missing buffs
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
        
        UpdateBtn("Fort", fState, 0, "hasFort")
        UpdateBtn("Spirit", sState, 1, "hasSpirit")
        UpdateBtn("Shadow", shState, 2, "hasShadow")
    end
end

function Priest:UpdateChampButton(rowIndex, priestName)
    local btn = getglobal("CPPriestRow"..rowIndex.."Champ")
    local nameLabel = getglobal("CPPriestRow"..rowIndex.."ChampName")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local target = self.LegacyAssignments[priestName] and self.LegacyAssignments[priestName]["Champ"]
    
    icon:SetTexture(self.ChampionIcons["Proclaim"])
    
    if target then
        icon:Show()
        btn:SetAlpha(1.0)
        if nameLabel then 
            nameLabel:SetText(string.sub(target, 1, 8)) 
        end
        
        -- Check buff status
        local status = self.CurrentBuffsByName[target]
        local text = getglobal(btn:GetName().."Text")
        if status and status.hasProclaim then
            text:SetText("")
        else
            text:SetText("|cffff0000!|r")
        end
    else
        icon:Show()
        btn:SetAlpha(0.3)
        if nameLabel then nameLabel:SetText("") end
        getglobal(btn:GetName().."Text"):SetText("")
    end
end

function Priest:UpdateEnlightenButton(rowIndex, priestName)
    local btn = getglobal("CPPriestRow"..rowIndex.."Enlighten")
    local nameLabel = getglobal("CPPriestRow"..rowIndex.."EnlightenName")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local target = self.LegacyAssignments[priestName] and self.LegacyAssignments[priestName]["Enlighten"]
    
    icon:SetTexture(self.ChampionIcons["Enlighten"])
    
    if target then
        icon:Show()
        btn:SetAlpha(1.0)
        if nameLabel then 
            nameLabel:SetText(string.sub(target, 1, 8)) 
        end
        
        local status = self.CurrentBuffsByName[target]
        local text = getglobal(btn:GetName().."Text")
        if status and status.hasEnlighten then
            text:SetText("")
        else
            text:SetText("|cffff0000!|r")
        end
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

function Priest:ClearButton_OnClick(btn)
    local rowName = btn:GetParent():GetName()
    local _, _, rowIdx = string.find(rowName, "CPPriestRow(%d+)")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    -- Permission check
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Permission denied.")
        return
    end
    
    self.Assignments[priestName] = {}
    self.LegacyAssignments[priestName] = {}
    
    ClassPower_SendMessage("CLEAR "..priestName)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared assignments for "..priestName)
    
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Priest:SubButton_OnClick(btn)
    local btnName = btn:GetName()
    -- Format: CPPriestRow1Group1Fort
    local _, _, rowIdx, grpIdx, buffType = string.find(btnName, "CPPriestRow(%d+)Group(%d+)(.*)")
    if not rowIdx or not grpIdx or not buffType then return end
    
    rowIdx = tonumber(rowIdx)
    grpIdx = tonumber(grpIdx)
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    -- Permission check
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    -- Get current value
    self.Assignments[priestName] = self.Assignments[priestName] or {}
    local cur = self.Assignments[priestName][grpIdx] or 0
    
    -- Decode (2 bits per buff type)
    local f = math.mod(cur, 4)
    local s = math.mod(math.floor(cur/4), 4)
    local sh = math.mod(math.floor(cur/16), 4)
    
    -- Cycle: 0 -> 1 (Group) -> 2 (Single) -> 0
    if buffType == "Fort" then
        f = math.mod(f + 1, 3)
    elseif buffType == "Spirit" then
        s = math.mod(s + 1, 3)
    elseif buffType == "Shadow" then
        sh = math.mod(sh + 1, 3)
    end
    
    -- Re-encode
    cur = f + (s * 4) + (sh * 16)
    self.Assignments[priestName][grpIdx] = cur
    
    -- Sync
    ClassPower_SendMessage("ASSIGN "..priestName.." "..grpIdx.." "..cur)
    
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Priest:SubButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, _, _, buffType = string.find(btnName, "CPPriestRow(%d+)Group(%d+)(.*)")
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    
    local label = buffType or "Unknown"
    if buffType == "Fort" then label = "Fortitude"
    elseif buffType == "Spirit" then label = "Divine Spirit"
    elseif buffType == "Shadow" then label = "Shadow Protection"
    end
    
    GameTooltip:SetText(label)
    GameTooltip:AddLine("Click to cycle:", 1, 1, 1)
    GameTooltip:AddLine("Off -> Group -> Single", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Priest:ChampButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPriestRow(%d+)Champ")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    -- Permission check
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.ContextName = priestName
    self.AssignMode = "Champ"
    
    ToggleDropDownMenu(1, nil, ClassPowerPriestDropDown, btn, 0, 0)
end

function Priest:ChampButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPriestRow(%d+)Champ")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    
    local target = self.LegacyAssignments[priestName] and self.LegacyAssignments[priestName]["Champ"]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Champion Assignment")
    if target then
        GameTooltip:AddLine("Target: "..target, 0, 1, 0)
    else
        GameTooltip:AddLine("Click to assign", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

function Priest:EnlightenButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPriestRow(%d+)Enlighten")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    -- Permission check
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.ContextName = priestName
    self.AssignMode = "Enlighten"
    
    ToggleDropDownMenu(1, nil, ClassPowerPriestDropDown, btn, 0, 0)
end

function Priest:EnlightenButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPriestRow(%d+)Enlighten")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    
    local target = self.LegacyAssignments[priestName] and self.LegacyAssignments[priestName]["Enlighten"]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Enlighten Assignment")
    if target then
        GameTooltip:AddLine("Target: "..target, 0, 1, 0)
    else
        GameTooltip:AddLine("Click to assign", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-----------------------------------------------------------------------------------
-- Update UI (delegates)
-----------------------------------------------------------------------------------

function Priest:UpdateUI()
    self:UpdateBuffBar()
    if self.ConfigWindow and self.ConfigWindow:IsVisible() then
        self:UpdateConfigGrid()
    end
end

function Priest:ResetUI()
    CP_PerUser.Point = nil
    CP_PerUser.RelativePoint = nil
    CP_PerUser.X = nil
    CP_PerUser.Y = nil
    CP_PerUser.Scale = 0.7
    CP_PerUser.ConfigScale = 0.8
    
    if self.BuffBar then
        self.BuffBar:ClearAllPoints()
        self.BuffBar:SetPoint("CENTER", 0, 0)
        self.BuffBar:SetScale(0.7)
    end
    
    if self.ConfigWindow then
        self.ConfigWindow:ClearAllPoints()
        self.ConfigWindow:SetPoint("CENTER", 0, 0)
        self.ConfigWindow:SetScale(0.8)
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: UI reset to defaults.")
end

-----------------------------------------------------------------------------------
-- Champion/Enlighten Dropdown
-----------------------------------------------------------------------------------

function Priest:ChampDropDown_Initialize(level)
    if not level then level = 1 end
    
    local info = {}
    
    if level == 1 then
        -- Clear option
        info = {}
        info.text = ">> Clear <<"
        info.value = "CLEAR"
        info.func = function() Priest:AssignTarget_OnClick() end
        UIDropDownMenu_AddButton(info)
        
        -- List players
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
            info.func = function() Priest:AssignTarget_OnClick() end
            UIDropDownMenu_AddButton(info)
            
            for i = 1, numParty do
                local name = UnitName("party"..i)
                if name then
                    info = {}
                    info.text = name
                    info.value = name
                    info.func = function() Priest:AssignTarget_OnClick() end
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
                    info.func = function() Priest:AssignTarget_OnClick() end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end
end

function Priest:AssignTarget_OnClick()
    local targetName = this.value
    local pname = self.ContextName
    local mode = self.AssignMode or "Champ"
    
    if not pname then pname = UnitName("player") end
    
    self.LegacyAssignments[pname] = self.LegacyAssignments[pname] or {}
    
    if targetName == "CLEAR" then
        self.LegacyAssignments[pname][mode] = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared "..mode.." for "..pname)
        if mode == "Champ" then
            ClassPower_SendMessage("ASSIGNCHAMP "..pname.." nil")
        end
    else
        self.LegacyAssignments[pname][mode] = targetName
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..pname.." "..mode.." = "..targetName)
        if mode == "Champ" then
            ClassPower_SendMessage("ASSIGNCHAMP "..pname.." "..targetName)
        end
    end
    
    self:UpdateUI()
    CloseDropDownMenus()
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("PRIEST", Priest)
