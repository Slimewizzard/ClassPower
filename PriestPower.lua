-- PriestPower - Core Logic
-- Adapted from PallyPower for Turtle WoW

PriestPower = {}
PriestPower_Assignments = {} -- [PriestName][ClassID] = SpellID
PriestPower_LegacyAssignments = {} -- [PriestName]["Champ"] = PlayerName

-- Configuration
PP_PerUser = {
    scanfreq = 10,
    scanperframe = 1,
    smartbuffs = 1,
}

-- UI CONSTRUCTORS (Replacing XML Templates)
function PP_CreateSubButton(parent, name)
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
    btn:SetScript("OnClick", function() PriestPowerSubButton_OnClick(this) end)
    btn:SetScript("OnEnter", function() PriestPowerSubButton_OnEnter(this) end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    return btn
end

function PP_CreateGroupFrame(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(76); f:SetHeight(42)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    
    local fort = PP_CreateSubButton(f, name.."Fort")
    fort:SetPoint("LEFT", 1, 0)
    
    local spirit = PP_CreateSubButton(f, name.."Spirit")
    spirit:SetPoint("LEFT", fort, "RIGHT", 0, 0)
    
    local shadow = PP_CreateSubButton(f, name.."Shadow")
    shadow:SetPoint("LEFT", spirit, "RIGHT", 0, 0)
    
    return f
end

function PP_CreateChampionFrame(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(80); f:SetHeight(42)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    
    -- (Label removed)
    
    local function CreateChampSub(suffix, rel, off)
        local btn = PP_CreateSubButton(f, name..suffix)
        btn:ClearAllPoints()
        if rel then btn:SetPoint("LEFT", rel, "RIGHT", 0, 0)
        else btn:SetPoint("LEFT", off, 0) end
        btn:SetScript("OnClick", function() PriestPowerChampButton_OnClick(this) end)
        return btn
    end
    
    local p = CreateChampSub("Proclaim", nil, 2)
    local g = CreateChampSub("Grace", p)
    local e = CreateChampSub("Empower", g)
    
    return f
end

function PP_CreateEnlightenFrame(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(40); f:SetHeight(42)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    
    -- (Label removed)
    
    local btn = PP_CreateSubButton(f, name.."Enlighten")
    btn:SetPoint("CENTER", f, "CENTER", 0, 0)
    btn:SetScript("OnClick", function() PriestPowerEnlightenButton_OnClick(this) end)
    
    return f
end

function PP_CreateCapabilityIcon(parent, name)
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

function PP_CreateClearButton(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(14); btn:SetHeight(14)
    btn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    btn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    local ht = btn:GetHighlightTexture()
    if ht then ht:SetBlendMode("ADD") end
    
    btn:SetScript("OnClick", function() PriestPower_ClearButton_OnClick() end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear Assignments")
        GameTooltip:AddLine("Requires Leader/Assist", 1, 0, 0)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    return btn
end

function PP_CreateResizeGrip(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(16); btn:SetHeight(16)
    btn:SetNormalTexture("Interface\\AddOns\\PriestPower\\PriestPower-ResizeGrip.tga")
    
    btn:SetScript("OnMouseDown", function() 
        if arg1 == "LeftButton" then
            local p = this:GetParent()
            p.isResizing = true
            p.startScale = p:GetScale()
            p.cursorStartX, p.cursorStartY = GetCursorPosition()
            this:SetScript("OnUpdate", PriestPower_UI_OnScaleUpdate)
        end
    end)
    btn:SetScript("OnMouseUp", function() 
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        
        -- Save scales
        if p:GetName() == "PriestPowerBuffBar" then
            PriestPowerBuffBar_SavePosition()
        elseif p:GetName() == "PriestPowerConfigBase" then
            PP_PerUser.ConfigScale = p:GetScale()
        end
    end)
    return btn
end

function PP_CreateHUDButton(parent, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetWidth(30); btn:SetHeight(30)
    
    local icon = btn:CreateTexture(btn:GetName().."Icon", "BACKGROUND")
    icon:SetAllPoints(btn)
    
    local txt = btn:CreateFontString(btn:GetName().."Text", "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
    
    local nt = btn:CreateTexture(btn:GetName().."NormalTexture")
    nt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    nt:SetWidth(54); nt:SetHeight(54)
    nt:SetPoint("CENTER", btn, "CENTER", 0, -1)
    btn:SetNormalTexture(nt)
    
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function() PriestPower_BuffButton_OnClick(this) end)
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

function PP_CreateHUDRow(parent, name, id)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(140); f:SetHeight(34)
    
    local label = f:CreateFontString(f:GetName().."Label", "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", f, "LEFT", 5, 0)
    label:SetText("Grp "..id)
    
    local fort = PP_CreateHUDButton(f, name.."Fort")
    fort:SetPoint("LEFT", f, "LEFT", 40, 0)
    
    local spirit = PP_CreateHUDButton(f, name.."Spirit")
    spirit:SetPoint("LEFT", fort, "RIGHT", 2, 0)
    
    local shadow = PP_CreateHUDButton(f, name.."Shadow")
    shadow:SetPoint("LEFT", spirit, "RIGHT", 2, 0)
    
    -- Champion specific buttons if Row 9
    if id == 9 then
        label:SetText("Chmp")
        local proc = PP_CreateHUDButton(f, name.."Proclaim")
        proc:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(proc:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Proclaim"])
        
        local grace = PP_CreateHUDButton(f, name.."Grace")
        grace:SetPoint("LEFT", proc, "RIGHT", 2, 0)
        getglobal(grace:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Grace"])
        
        local emp = PP_CreateHUDButton(f, name.."Empower")
        emp:SetPoint("LEFT", grace, "RIGHT", 2, 0)
        getglobal(emp:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Empower"])
        
        local rev = PP_CreateHUDButton(f, name.."Revive")
        rev:SetPoint("LEFT", emp, "RIGHT", 2, 0)
        getglobal(rev:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Revive"])
        f:SetWidth(180)
    end
    -- EnlightenRow
    if id == 10 then
        label:SetText("Enlight")
        local en = PP_CreateHUDButton(f, name.."Enlighten")
        en:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(en:GetName().."Icon"):SetTexture("Interface\\Icons\\btnholyscriptures")
    end
    
    f:Hide()
    return f
end

PP_NextScan = PP_PerUser.scanfreq
PP_PREFIX = "PRPWR"

-- Buff Types
PP_BUFF_FORT = 0
PP_BUFF_SPIRIT = 1
PP_BUFF_SHADOW = 2
PP_BUFF_CHAMP = 3
PP_BUFF_ENLIGHT = 4

-- Icons for the "Special" champion spells
PriestPower_ChampionIcons = {
    ["Proclaim"] = "Interface\\Icons\\Spell_Holy_ProclaimChampion",
    ["Grace"] = "Interface\\Icons\\Spell_Holy_ChampionsGrace",
    ["Empower"] = "Interface\\Icons\\Spell_Holy_EmpowerChampion",
    ["Revive"] = "Interface\\Icons\\spell_holy_revivechampion",
    ["Enlighten"] = "Interface\\Icons\\Spell_Holy_MindVision",
}

AllPriests = {}
CurrentBuffs = {}
IsPriest = false
PP_DebugEnabled = false
PP_DebugFakeMembers = true
PP_BuffTimers = {}
PP_WasInGroup = false

function PriestPower_IsPromoted(name)
    if not name then name = UnitName("player") end
    
    if GetNumRaidMembers() > 0 then
        for i=1, GetNumRaidMembers() do
            local n, rank = GetRaidRosterInfo(i)
            if n == name then
                -- Rank: 0=Member, 1=Assistant, 2=Leader
                return (rank > 0)
            end
        end
    elseif GetNumPartyMembers() > 0 then
        if name == UnitName("player") then
            return IsPartyLeader()
        else
            -- Impossible to check remote party leader easily without sync?
            -- Actually IsPartyLeader() only works for player. 
            -- But usually only player permission matters for UI.
            -- For remote parsing, maybe assume trust or check if sender says "I am leader"? 
            -- For now strict: Only trust self if leader in party.
            -- Wait, GetPartyLeaderIndex()? 
            if GetPartyLeaderIndex() == 0 then -- Player is leader
                 return (name == UnitName("player"))
            else
                 -- Someone else is leader.
                 -- If name matches party leader?
                 -- GetPartyLeaderIndex returns index 1-4 or 0.
                 local index = GetPartyLeaderIndex()
                 if index > 0 then
                    return (name == UnitName("party"..index))
                 end
            end
        end
    end
    return false
end

function PriestPower_IsLeader()
    if IsPartyLeader() then return true end
    if IsRaidLeader() then return true end
    if GetPartyLeaderIndex() == 0 then return true end
    return false
end

function PP_Debug(msg)
    if PP_DebugEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00a[PP Debug]|r "..tostring(msg))
    end
end

-- Spell Durations (in seconds)
PP_SpellDuration = {
    ["Proclaim"] = 7200, -- 2 Hours
    ["Grace"] = 1800,    -- 30 Minutes
    ["Empower"] = 600,   -- 10 Minutes
}

function PriestPower_ClearAssignments(targetName)
    if not targetName then return end
    
    PriestPower_Assignments[targetName] = {}
    PriestPower_LegacyAssignments[targetName] = {}
    
    PriestPower_SendMessage("CLEAR "..targetName)
    DEFAULT_CHAT_FRAME:AddMessage("Cleared Assignments for "..targetName)
    PriestPower_UpdateUI()
end

function PriestPower_ClearButton_OnClick()
   local parent = this:GetParent()
   local pname = getglobal(parent:GetName().."Name"):GetText()
   
   if not pname then return end
   
   if PriestPower_IsPromoted() then
       PriestPower_ClearAssignments(pname)
   else
       DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: Permission Denied.")
   end
end

function PriestPower_SlashCommandHandler(msg)
    if msg == "debug" then
        PP_DebugEnabled = not PP_DebugEnabled
        if PP_DebugEnabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r Debug Enabled.")
            PP_Debug("Debug Mode Active")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r Debug Disabled.")
        end
    elseif msg == "reset" then
        if PP_PerUser then
            PP_PerUser.Point = nil
            PP_PerUser.RelativePoint = nil
            PP_PerUser.X = nil
            PP_PerUser.Y = nil
            PP_PerUser.Scale = 0.7
            PP_PerUser.ConfigScale = 0.8
        end
        local bar = getglobal("PriestPowerBuffBar")
        if bar then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            bar:SetScale(0.7)
        end
        if PriestPowerConfigBase then
            PriestPowerConfigBase:SetScale(0.8)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r UI reset to default position and scale.")
    elseif msg == "revive" or msg == "reviveChamp" then
        local pname = UnitName("player")
        local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"]
        if target then
             ClearTarget()
             TargetByName(target, true)
             if UnitName("target") == target then
                 CastSpellByName(SPELL_REVIVE)
                 TargetLastTarget()
             else
                 DEFAULT_CHAT_FRAME:AddMessage("PriestPower: Could not target "..target)
             end
        else
            DEFAULT_CHAT_FRAME:AddMessage("PriestPower: No Champion Assigned!")
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
        if PriestPowerConfigBase and PriestPowerConfigBase:IsVisible() then
            PriestPowerConfigBase:Hide()
        else
            PriestPowerConfig_Create()
            PriestPowerConfigBase:Show()
            PriestPower_UpdateUI()
        end
    end
end

-- Scanning/Logic
function PriestPower_OnLoad(frame)
    if not frame then frame = this end
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    
    SlashCmdList["PRIESTPOWER"] = function(msg)
        PriestPower_SlashCommandHandler(msg)
    end
    SLASH_PRIESTPOWER1 = "/prip" 
    SLASH_PRIESTPOWER2 = "/priestpower"
    SLASH_PRIESTPOWER3 = "/prp"

    if PP_DebugEnabled then PP_Debug("PriestPower OnLoad") end
end



function PriestPower_OnEvent(event)
    if event == "PLAYER_LOGIN" then
        if not PP_PerUser then
            PP_PerUser = {
                scanfreq = 10,
                scanperframe = 1,
                smartbuffs = 1,
            }
        end
        UIDropDownMenu_Initialize(PriestPowerChampDropDown, PriestPower_ChampDropDown_Combined, "MENU")
        
        local _, class = UnitClass("player")
        if class == "PRIEST" then
            IsPriest = true
            PriestPower_ScanSpells()
            PriestPower_ScanRaid() -- Populate buff data immediately
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded.")
            
            -- Create BuffWindow (Lua-based)
            PriestPower_CreateBuffBar()
            -- Create Config Window (Lua-based)
            PriestPowerConfig_Create()
        else
            IsPriest = false
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded. Not a Priest (Disabled).")
        end
        
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if IsPriest then 
            PriestPower_ScanSpells() 
            PriestPower_ScanRaid() -- Ensure roster is scanned on zone change/reload
            if event == "PLAYER_ENTERING_WORLD" then PriestPower_RequestSend() end
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        PriestPower_ScanRaid()
        PriestPower_UpdateUI()
        
        if event == "RAID_ROSTER_UPDATE" then
            PP_RosterDirty = true
            PP_RosterTimer = 0.5
        else
            PriestPower_ScanRaid()
            PriestPower_UpdateUI()
        end
        
        if event == "RAID_ROSTER_UPDATE" then
            if GetTime() - PP_LastRequest > 5 then
                PriestPower_RequestSend()
                PP_LastRequest = GetTime()
            end
        end
        
        -- Auto-reset removed in favor of manual clear
        PP_WasInGroup = (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0)

        -- Init saved vars
        if not PP_PerUser then PP_PerUser = { Scale = 0.7 } end
        

        
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
        PriestPower_ParseSpellMessage(arg1)
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == PP_PREFIX then
            PriestPower_ParseMessage(arg4, arg2)
        end
    end
end

-- Global timer for UI refresh
PP_UpdateTimer = 0
PP_LastRequest = 0

function PriestPower_OnUpdate(elapsed)
    if not PP_PerUser then return end
    
    -- Scan Logic
    PP_NextScan = PP_NextScan - elapsed
    if PP_NextScan <= 0 then
        PP_NextScan = PP_PerUser.scanfreq or 10
        PriestPower_ScanSpells()
    end

    -- Delayed Roster Scan
    if PP_RosterDirty then
        if not PP_RosterTimer then PP_RosterTimer = 0.5 end
        PP_RosterTimer = PP_RosterTimer - elapsed
        if PP_RosterTimer <= 0 then
             PP_RosterDirty = false
             PP_RosterTimer = 0.5
             PriestPower_ScanRaid()
             PriestPower_UpdateUI()
        end
    end
    
    -- UI Refresh Logic (1s interval)
    PP_UpdateTimer = PP_UpdateTimer - elapsed
    if PP_UpdateTimer <= 0 then
        PP_UpdateTimer = 1.0
        
        -- Refresh Buff Bar for Timers
        if PriestPowerBuffBar:IsVisible() then
             PriestPower_ScanRaid() -- Update Buff Data (UnitBuffs) every second
             PriestPower_UpdateBuffBar() 
        end
        
        -- Refresh Main Frame if visible (for status updates)
        -- Refresh Main Frame if visible (for status updates)
        if PriestPowerConfigBase and PriestPowerConfigBase:IsVisible() then
            PriestPower_UpdateUI()
        end
    end
end



function PriestPower_ScanSpells()
    local RankInfo = {
        [0] = { rank = 0, talent = 0, name = "Fortitude" }, -- talent=1 means Has Prayer
        [1] = { rank = 0, talent = 0, name = "Spirit" },
        [2] = { rank = 0, talent = 0, name = "Shadow" },
        ["Proclaim"] = false,
        ["Grace"] = false,
        ["Empower"] = false,
        ["Revive"] = false,
        ["Enlighten"] = false
    }
    
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        
        -- Parse Rank
        local rank = 0
        if spellRank then
            _, _, rank = string.find(spellRank, "Rank (%d+)")
            if rank then rank = tonumber(rank) else rank = 0 end
        end

        -- Fortitude
        if spellName == SPELL_FORTITUDE then
            if rank > RankInfo[0].rank then RankInfo[0].rank = rank end
        elseif spellName == SPELL_P_FORTITUDE then
            RankInfo[0].talent = 1
        end

        -- Spirit
        if spellName == SPELL_SPIRIT then
             if rank > RankInfo[1].rank then RankInfo[1].rank = rank end
        elseif spellName == SPELL_P_SPIRIT then
            RankInfo[1].talent = 1
        end

        -- Shadow Protection
        if spellName == SPELL_SHADOW_PROT then
             if rank > RankInfo[2].rank then RankInfo[2].rank = rank end
        elseif spellName == SPELL_P_SHADOW_PROT then
            RankInfo[2].talent = 1
        end
        
        -- Champion Spells
        if spellName == SPELL_PROCLAIM or spellName == "Holy Champion" then RankInfo["Proclaim"] = true end
        if spellName == SPELL_GRACE then RankInfo["Grace"] = true end
        if spellName == SPELL_EMPOWER then RankInfo["Empower"] = true end
        if spellName == SPELL_REVIVE then RankInfo["Revive"] = true end
        if spellName == SPELL_ENLIGHTEN then RankInfo["Enlighten"] = true end
        
        i = i + 1
    end
    
    AllPriests[UnitName("player")] = RankInfo
    -- Consider broadcasting self here or waiting for REQ
end

CurrentBuffsByName = {}

function PriestPower_ScanRaid()
    if not IsPriest then return end

    -- Reset
    CurrentBuffs = {}
    for i=1, 8 do CurrentBuffs[i] = {} end
    CurrentBuffsByName = {}
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local foundPriests = {}
    if UnitClass("player") == "Priest" then
        foundPriests[UnitName("player")] = true
    end
    
    -- Helper to process unit
    local function ProcessUnit(unit, name, subgroup, class)
         -- Guard: Check if unit ID is valid pattern (player, partyN, raidN)
         -- UnitExists might error on invalid strings in 1.12
         local isValid = (unit == "player") or string.find(unit, "^party%d+$") or string.find(unit, "^raid%d+$")
         if not isValid then return end
         if not UnitExists(unit) then return end
         if name and class == "PRIEST" then
             foundPriests[name] = true
             if not AllPriests[name] then
                 -- Initialize with empty/defaults if new
                 AllPriests[name] = {
                    [0] = { rank = 0, talent = 0, name = "Fortitude" },
                    [1] = { rank = 0, talent = 0, name = "Spirit" },
                    [2] = { rank = 0, talent = 0, name = "Shadow" },
                    ["Proclaim"] = false,
                    ["Grace"] = false,
                    ["Empower"] = false,
                    ["Revive"] = false,
                    ["Enlighten"] = false
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
                hasEnlighten = false
            }
            
            -- Check Buffs
            local b = 1
            while true do
                local bname = UnitBuff(unit, b)
                if not bname then break end
                
                -- Normalize to lowercase for safe matching
                bname = string.lower(bname)
                
                if string.find(bname, "fortitude") then buffInfo.hasFort = true end
                if string.find(bname, "spirit") or string.find(bname, "inspiration") then buffInfo.hasSpirit = true end
                if string.find(bname, "shadow") and (string.find(bname, "protection") or string.find(bname, "antishadow")) then buffInfo.hasShadow = true end
                
                if string.find(bname, "proclaimchampion") or string.find(bname, "holychampion") then buffInfo.hasProclaim = true end
                if string.find(bname, "championsgrace") then buffInfo.hasGrace = true end
                if string.find(bname, "empowerchampion") then buffInfo.hasEmpower = true end
                -- Enlighten (Icon: btnholyscriptures)
                if string.find(bname, "btnholyscriptures") or string.find(bname, "enlighten") then buffInfo.hasEnlighten = true end
                
                b = b + 1
            end
            
            -- Timer Logic
            if not PP_BuffTimers then PP_BuffTimers = {} end
            if not PP_BuffTimers[name] then PP_BuffTimers[name] = {} end
            local timers = PP_BuffTimers[name]
            
            -- Proclaim
            if buffInfo.hasProclaim then
                if not timers["Proclaim"] then
                    timers["Proclaim"] = time() + 7200 -- Fallback default
                end
            else
                timers["Proclaim"] = nil
            end
            
            -- Grace - Only clear if gone, set by combat log
            if not buffInfo.hasGrace then timers["Grace"] = nil end
            
            -- Empower - Only clear if gone, set by combat log
            if not buffInfo.hasEmpower then timers["Empower"] = nil end
            
            if not CurrentBuffs[subgroup] then CurrentBuffs[subgroup] = {} end
            table.insert(CurrentBuffs[subgroup], buffInfo)
            CurrentBuffsByName[name] = buffInfo
        end
    end

    if numRaid > 0 then
        for i = 1, numRaid do
            local unit = "raid"..i
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            ProcessUnit(unit, name, subgroup, class)
        end
    elseif numParty > 0 then
         -- Party handling
         for i = 1, numParty do
             local unit = "party"..i
             local name = UnitName(unit)
             local _, class = UnitClass(unit)
             ProcessUnit(unit, name, 1, class)
         end
         -- Process self for party
         local _, pClass = UnitClass("player")
         ProcessUnit("player", UnitName("player"), 1, pClass)
    end
    
    -- Start cleanup of left priests
    for name, _ in pairs(AllPriests) do
        if not foundPriests[name] then
             AllPriests[name] = nil
             PriestPower_Assignments[name] = nil
             -- Keep legacy?
        end
    end
end

function PriestPower_SendMessage(msg)
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(PP_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(PP_PREFIX, msg, "PARTY")
    end
end

function PriestPower_RequestSend()
    PriestPower_SendMessage("REQ")
end

function PriestPower_SendSelf()
    if not IsPriest then return end
    -- Ensure scan
    PriestPower_ScanSpells()
    
    local pname = UnitName("player")
    local myRanks = AllPriests[pname]
    if not myRanks then return end
    
    local msg = "SELF "
    -- Ranks: Fort(0) Spirit(1) Shadow(2) -> 2 chars each (rank+talent)
    for i=0,2 do
        if myRanks[i] then 
            msg = msg .. myRanks[i].rank .. myRanks[i].talent 
        else 
            msg = msg .. "00" 
        end
    end
    -- Champion Flags (P G E R)
    msg = msg .. (myRanks["Proclaim"] and "1" or "0")
    msg = msg .. (myRanks["Grace"] and "1" or "0")
    msg = msg .. (myRanks["Empower"] and "1" or "0")
    msg = msg .. (myRanks["Revive"] and "1" or "0")
    msg = msg .. (myRanks["Enlighten"] and "1" or "0")
    
    msg = msg .. "@"
    
    -- Assignments (Groups 1-8)
    local assigns = PriestPower_Assignments[pname]
    for i=1,8 do
        local val = 0
        if assigns and assigns[i] then val = assigns[i] end
        msg = msg .. val
    end
    
    msg = msg .. "@"
    
    -- Champ Assignment
    local champ = "nil"
    if PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"] then
        champ = PriestPower_LegacyAssignments[pname]["Champ"]
    end
    msg = msg .. champ
    
    PriestPower_SendMessage(msg)
end

-- Protocol: SELF <ranks>@<assigns>@<champ>
-- ranks: FSR pger e (Fort Spirit Shadow Proclaim Grace Empower Revive Enlighten)

function PriestPower_ParseMessage(sender, msg)
    if sender == UnitName("player") then return end 
    
    if msg == "REQ" then
        PriestPower_SendSelf()
    elseif string.find(msg, "^SELF") then
        local _, _, ranks, assigns, champ = string.find(msg, "SELF (.-)@(.-)@(.*)")
        
        if not ranks then return end
        
        AllPriests[sender] = AllPriests[sender] or {}
        local info = AllPriests[sender]
        
        for id = 0, 2 do
            local r = string.sub(ranks, id*2+1, id*2+1)
            local t = string.sub(ranks, id*2+2, id*2+2)
            if r ~= "n" then
                info[id] = { rank = tonumber(r) or 0, talent = tonumber(t) or 0 }
            end
        end
        
        info["Proclaim"] = (string.sub(ranks, 7, 7) == "1")
        info["Grace"]    = (string.sub(ranks, 8, 8) == "1")
        info["Empower"]  = (string.sub(ranks, 9, 9) == "1")
        info["Revive"]   = (string.sub(ranks, 10, 10) == "1")
        info["Enlighten"] = (string.sub(ranks, 11, 11) == "1")
        
        PriestPower_Assignments[sender] = PriestPower_Assignments[sender] or {}
        for gid = 1, 8 do
             local val = string.sub(assigns, gid, gid)
             if val ~= "n" and val ~= "" then
                 PriestPower_Assignments[sender][gid] = tonumber(val)
             end
        end
        
        PriestPower_LegacyAssignments[sender] = PriestPower_LegacyAssignments[sender] or {}
        if champ and champ ~= "" and champ ~= "nil" then
            PriestPower_LegacyAssignments[sender]["Champ"] = champ
        else
            PriestPower_LegacyAssignments[sender]["Champ"] = nil
        end
        
        -- PriestPower_UpdateUI()
        
    elseif string.find(msg, "^ASSIGN ") then
        local _, _, name, class, skill = string.find(msg, "^ASSIGN (.-) (.-) (.*)")
        -- Sec Check: name=Target, sender=Sender
        -- If Sender != Target and Sender != Promoted -> Ignore
        if name and class and skill then
            if sender == name or PriestPower_IsPromoted(sender) then
                PriestPower_Assignments[name] = PriestPower_Assignments[name] or {}
                PriestPower_Assignments[name][tonumber(class)] = tonumber(skill)
                PriestPower_UpdateUI()
            else
                -- Ignore unauthorized assignment
            end
        end
        
    elseif string.find(msg, "^ASSIGNCHAMP ") then
        local _, _, name, target = string.find(msg, "^ASSIGNCHAMP (.-) (.*)")
        if name and target then
            if sender == name or PriestPower_IsPromoted(sender) then
                if target == "nil" or target == "" then target = nil end
                PriestPower_LegacyAssignments[name] = PriestPower_LegacyAssignments[name] or {}
                PriestPower_LegacyAssignments[name]["Champ"] = target
                PriestPower_UpdateUI()
            end
        end
        
    elseif string.find(msg, "^CLEAR ") then
        local _, _, target = string.find(msg, "^CLEAR (.*)")
        if target then
            if sender == target or PriestPower_IsPromoted(sender) then
                PriestPower_Assignments[target] = {}
                PriestPower_LegacyAssignments[target] = {}
                if target == UnitName("player") then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: Your assignments were cleared by "..sender)
                end
                PriestPower_UpdateUI()
            end
        end
    end
end

function PriestPower_ParseSpellMessage(msg)
    if not msg then return end
    
    -- Format: You cast Spell on Target.
    local _, _, spell, target = string.find(msg, "^You cast (.*) on (.*)%.$")
    
    if spell and target then
        local duration = nil
        local key = nil
        
        if spell == "Champion's Grace" then
            key = "Grace"
            duration = PP_SpellDuration["Grace"]
        elseif spell == "Empower Champion" then
            key = "Empower"
            duration = PP_SpellDuration["Empower"]
        elseif spell == "Proclaim Champion" then
             key = "Proclaim"
             duration = PP_SpellDuration["Proclaim"]
        end
        
        if key and duration then
             if not PP_BuffTimers then PP_BuffTimers = {} end
             if not PP_BuffTimers[target] then PP_BuffTimers[target] = {} end
             
             PP_BuffTimers[target][key] = time() + duration
             PriestPower_UpdateUI()
        end
    end
end

function PriestPower_UpdateUI()
    if not PriestPower_Assignments then PriestPower_Assignments = {} end
    if not PriestPower_LegacyAssignments then PriestPower_LegacyAssignments = {} end
    local i = 1
    for name, info in pairs(AllPriests) do
        if i > 40 then break end 
        
        local frame = getglobal("PriestPowerFramePlayer"..i)
        if frame then
            frame:Show()
            getglobal(frame:GetName().."Name"):SetText(name)
            
            -- Clear Button
            local btnClear = getglobal(frame:GetName().."Clear")
            if PriestPower_IsPromoted() then
                btnClear:Show()
            else
                btnClear:Hide()
            end

            -- Capability Icons (Learned Spells)
            local capFrame = getglobal(frame:GetName().."Cap")
            
            local function UpdateCapIcon(key, icon, rank, talent, isBool)
                local btn = getglobal(capFrame:GetName()..key)
                local tex = getglobal(btn:GetName().."Icon")
                local txt = getglobal(btn:GetName().."Rank")
                
                tex:SetTexture(icon)
                
                local hasSpell = false
                local rankText = ""
                
                if isBool then
                    if info[key] then hasSpell = true end
                else
                    -- Indexed (0,1,2)
                    if info[key] and info[key].rank > 0 then 
                        hasSpell = true 
                        if info[key].talent > 0 then
                            rankText = "+" -- Talent/Imp
                        end
                        -- rankText = rankText .. info[key].rank
                    end
                end
                
                if hasSpell then
                    tex:SetDesaturated(0)
                    btn:SetAlpha(1.0)
                    txt:SetText(rankText)
                    btn.tooltipText = key .. (rankText ~= "" and " (Talented)" or "")
                else
                    tex:SetDesaturated(1)
                    btn:SetAlpha(0.4)
                    txt:SetText("")
                    btn.tooltipText = key .. " (Not Learned)"
                end
            end
            
            -- Fort (0)
            -- Override to use correct index check since function is generic
            local rInfo = info[0] or {rank=0, talent=0}
            local btn = getglobal(capFrame:GetName().."Fort")
            local tex = getglobal(btn:GetName().."Icon")
            local txt = getglobal(btn:GetName().."Rank")
            tex:SetTexture(PriestPower_BuffIcon[0])
            btn.tooltipText = "Power Word: Fortitude"
            if rInfo.rank > 0 then
                tex:SetDesaturated(0); btn:SetAlpha(1.0)
                txt:SetText(rInfo.talent > 0 and "+" or "")
            else 
                tex:SetDesaturated(1); btn:SetAlpha(0.4); txt:SetText("") 
            end

            -- Spirit (1)
            rInfo = info[1] or {rank=0, talent=0}
            btn = getglobal(capFrame:GetName().."Spirit")
            tex = getglobal(btn:GetName().."Icon")
            txt = getglobal(btn:GetName().."Rank")
            tex:SetTexture(PriestPower_BuffIcon[1])
            btn.tooltipText = "Divine Spirit"
            if rInfo.rank > 0 then
                 tex:SetDesaturated(0); btn:SetAlpha(1.0)
                 txt:SetText(rInfo.talent > 0 and "+" or "")
            else 
                 tex:SetDesaturated(1); btn:SetAlpha(0.4); txt:SetText("") 
            end

            -- Shadow (2)
            rInfo = info[2] or {rank=0, talent=0}
            btn = getglobal(capFrame:GetName().."Shadow")
            tex = getglobal(btn:GetName().."Icon")
            txt = getglobal(btn:GetName().."Rank")
            tex:SetTexture(PriestPower_BuffIcon[2])
            btn.tooltipText = "Shadow Protection"
            if rInfo.rank > 0 then
                 tex:SetDesaturated(0); btn:SetAlpha(1.0)
                 txt:SetText(rInfo.talent > 0 and "+" or "")
            else 
                 tex:SetDesaturated(1); btn:SetAlpha(0.4); txt:SetText("") 
            end
            
            -- Champions & Enlighten (Bool)
            local function SetBoolCap(key, iconName, label)
                local b = getglobal(capFrame:GetName()..key)
                local t = getglobal(b:GetName().."Icon")
                t:SetTexture(PriestPower_ChampionIcons[iconName])
                b.tooltipText = label
                if info[iconName] then
                    t:SetDesaturated(0); b:SetAlpha(1.0)
                else
                    t:SetDesaturated(1); b:SetAlpha(0.4)
                end
            end
            
            SetBoolCap("Proclaim", "Proclaim", SPELL_PROCLAIM)
            SetBoolCap("Grace", "Grace", SPELL_GRACE)
            SetBoolCap("Empower", "Empower", SPELL_EMPOWER)
            SetBoolCap("Revive", "Revive", SPELL_REVIVE)
            SetBoolCap("Enlighten", "Enlighten", SPELL_ENLIGHTEN)
            
            
            -- Group Buttons (1-8)
            for gid = 1, 8 do
                local groupFrame = getglobal(frame:GetName().."Group"..gid)
                local btnFort = getglobal(groupFrame:GetName().."Fort")
                local btnSpirit = getglobal(groupFrame:GetName().."Spirit")
                local btnShadow = getglobal(groupFrame:GetName().."Shadow")
                
                -- Check Assignment
                local assignVal = 0
                if PriestPower_Assignments[name] and PriestPower_Assignments[name][gid] then
                    assignVal = PriestPower_Assignments[name][gid]
                end
                
                local fState = math.mod(assignVal, 4)
                local sState = math.mod(math.floor(assignVal/4), 4)
                local shState = math.mod(math.floor(assignVal/16), 4)
                
                local function UpdateBtn(btn, state, typeIdx, buffKey)
                    local icon = getglobal(btn:GetName().."Icon")
                    local text = getglobal(btn:GetName().."Text")
                    text:SetText("")
                    if state > 0 then
                        if state == 1 then icon:SetTexture(PriestPower_BuffIconGroup[typeIdx])
                        else icon:SetTexture(PriestPower_BuffIcon[typeIdx]) end
                        icon:Show(); btn:SetAlpha(1.0)
                        -- Status
                        local missing = 0; local total = 0
                        if CurrentBuffs[gid] then
                            for _, member in CurrentBuffs[gid] do
                                total = total + 1
                                if not member[buffKey] and not member.dead then missing = missing + 1 end
                            end
                        end
                        if total > 0 then 
                            text:SetText((total-missing).."/"..total)
                            if missing > 0 then text:SetTextColor(1, 0, 0) else text:SetTextColor(0, 1, 0) end
                        end
                    else
                        icon:Hide(); btn:SetAlpha(0.2)
                    end
                end
                
                UpdateBtn(btnFort, fState, 0, "hasFort")
                UpdateBtn(btnSpirit, sState, 1, "hasSpirit")
                UpdateBtn(btnShadow, shState, 2, "hasShadow")
            end
            
            -- Champion Button Cluster
            local champFrame = getglobal(frame:GetName().."Champ")
            local btnP = getglobal(champFrame:GetName().."Proclaim")
            local btnG = getglobal(champFrame:GetName().."Grace")
            local btnE = getglobal(champFrame:GetName().."Empower")
            
            local iconP = getglobal(btnP:GetName().."Icon")
            local iconG = getglobal(btnG:GetName().."Icon")
            local iconE = getglobal(btnE:GetName().."Icon")
            
            local champText = getglobal(frame:GetName().."ChampName")

            -- Get Trigger (Assignment)
            local champTarget = nil
            if PriestPower_LegacyAssignments[name] then
                 champTarget = PriestPower_LegacyAssignments[name]["Champ"]
            end
            
            -- Set Icons
            iconP:SetTexture(PriestPower_ChampionIcons["Proclaim"])
            iconG:SetTexture(PriestPower_ChampionIcons["Grace"])
            iconE:SetTexture(PriestPower_ChampionIcons["Empower"])
            
            if champTarget then
                if champText then champText:SetText(champTarget) end
                
                -- Check Status in CurrentBuffsByName
                local status = CurrentBuffsByName[champTarget]
                
                -- Proclaim
                iconP:Show()
                if status and status.hasProclaim then
                     btnP:SetAlpha(1.0)
                     getglobal(btnP:GetName().."Text"):SetText("")
                else
                     btnP:SetAlpha(1.0)
                     getglobal(btnP:GetName().."Text"):SetText("|cffff0000X|r") -- Red X if missing
                end

                -- Grace
                iconG:Show()
                if status and status.hasGrace then
                     btnG:SetAlpha(1.0)
                     getglobal(btnG:GetName().."Text"):SetText("")
                else
                     btnG:SetAlpha(0.6) -- Needs refresh?
                     -- getglobal(btnG:GetName().."Text"):SetText("|cffff0000X|r")
                     getglobal(btnG:GetName().."Text"):SetText("")
                end
                
                -- Empower
                iconE:Show()
                if status and status.hasEmpower then
                     btnE:SetAlpha(1.0)
                     getglobal(btnE:GetName().."Text"):SetText("")
                else
                     btnE:SetAlpha(0.6)
                     getglobal(btnE:GetName().."Text"):SetText("")
                end
                
                -- Enlighten (Config UI Update)
                -- We are iterating frames: PriestPowerFramePlayerXEnlighten
                local btnEnFrame = getglobal("PriestPowerFramePlayer"..i.."Enlighten")
                if btnEnFrame then
                     local userEnlightenData = PriestPower_LegacyAssignments[name] and PriestPower_LegacyAssignments[name]["Enlighten"]
                     local btnEnBtn = getglobal(btnEnFrame:GetName().."Enlighten")
                     if userEnlightenData then
                          -- Show assigned name or check status?
                          -- Config UI usually shows icons.
                          -- Tooltip shows name. Text?
                          -- Champion assignment doesn't show name on button text (it's in tooltip).
                          -- But we might want to show "Assigned" state visually.
                          btnEnBtn:SetAlpha(1.0)
                     else
                          btnEnBtn:SetAlpha(0.6)
                     end
                     btnEnBtn.tooltipText = "Enlighten: "..(userEnlightenData or "None")
                end
                
            else
                if champText then champText:SetText("") end
                if enlightText then enlightText:SetText("") end
                iconP:Hide()
                iconG:Hide()
                iconE:Hide()
                -- Hide Enlighten icon? 
                -- We only added the button to the frame, we didn't add separate icons like Champion has P/G/E.
                -- Use alpha to show availability.
            end
        end
        i = i + 1
    end
    
    for k = i, 40 do 
        local fptr = getglobal("PriestPowerFramePlayer"..k)
        if fptr then fptr:Hide() end
    end
    
    PriestPower_UpdateBuffBar()
end

-- ... [Snip: OnClick Handlers] ...


-----------------------------------------------------------------------------------
-- New Config Window Implementation (Pure Lua)
-----------------------------------------------------------------------------------

function PriestPowerConfig_Create()
    if getglobal("PriestPowerConfigBase") then return end
    
    local f = CreateFrame("Frame", "PriestPowerConfigBase", UIParent)
    f:SetWidth(1050)
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
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:Hide()
    
    -- Apply Saved Scale
    if PP_PerUser and PP_PerUser.ConfigScale then
        f:SetScale(PP_PerUser.ConfigScale)
    else
        f:SetScale(0.8) -- Default zoomed out slightly for big window
    end
    
    -- Title
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", f, "TOP", 0, -18)
    t:SetText("PriestPower Configuration")
    
    -- Close Button
    local close = CreateFrame("Button", f:GetName().."Close", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Drag Scripts
    f:SetScript("OnMouseDown", function() if arg1=="LeftButton" then this:StartMoving() end end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Resize Grip (Bottom Right)
    local grip = PP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 15)

    -- Container for ScrollFrame (if needed, but user just wanted scalable window)
    -- For now, fixed list of rows inside the scalable frame.
    
    -- Row Creation Helper
    local function CreateConfigRow(i)
        local row = CreateFrame("Frame", "PriestPowerFramePlayer"..i, f)
        row:SetWidth(1050)
        row:SetHeight(56)
        
        -- Name Label
        local nameStr = row:CreateFontString(row:GetName().."Name", "OVERLAY", "GameFontHighlightSmall")
        nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 25, -15)
        nameStr:SetWidth(100); nameStr:SetHeight(16); nameStr:SetJustifyH("LEFT")
        nameStr:SetText("Priest "..i)
        
        -- Clear Button
        local clear = PP_CreateClearButton(row, row:GetName().."Clear")
        clear:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -14)
        
        -- Capability Icons Frame
        local caps = CreateFrame("Frame", row:GetName().."Cap", row)
        caps:SetWidth(140); caps:SetHeight(42)
        caps:SetPoint("TOPLEFT", row, "TOPLEFT", 110, -12)
        
        local function CreateCap(suffix, relTo, onClick)
            local btn = PP_CreateCapabilityIcon(caps, caps:GetName()..suffix)
            if relTo then btn:SetPoint("LEFT", relTo, "RIGHT", 0, 0)
            else btn:SetPoint("LEFT", caps, "LEFT", 0, 0) end
            if onClick then
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                btn:SetScript("OnClick", function() onClick(this) end)
            end
            return btn
        end
        local cF = CreateCap("Fort", nil, nil)
        local cS = CreateCap("Spirit", cF, nil)
        local cSh = CreateCap("Shadow", cS, nil)
        local cP = CreateCap("Proclaim", cSh, PriestPowerChampButton_OnClick)
        local cG = CreateCap("Grace", cP, PriestPowerChampButton_OnClick)
        local cE = CreateCap("Empower", cG, PriestPowerChampButton_OnClick)
        local cR = CreateCap("Revive", cE, nil)
        local cEn = CreateCap("Enlighten", cR, PriestPowerEnlightenButton_OnClick)
        
        -- Group Buttons (1-8)
        local lastGrp = nil
        for g=1, 8 do
            local grp = PP_CreateGroupFrame(row, row:GetName().."Group"..g)
            if lastGrp then grp:SetPoint("TOPLEFT", lastGrp, "TOPRIGHT", 0, 0)
            else grp:SetPoint("TOPLEFT", row, "TOPLEFT", 260, -5) end
            lastGrp = grp
        end
        
        -- Champion Assignment
        local champ = PP_CreateChampionFrame(row, row:GetName().."Champ")
        champ:SetPoint("TOPLEFT", lastGrp, "TOPRIGHT", 20, 0)
        
        -- (Champion Label removed)
        
        -- Enlighten Assignment
        local enlight = PP_CreateEnlightenFrame(row, row:GetName().."Enlighten")
        enlight:SetPoint("TOPLEFT", champ, "TOPRIGHT", 5, 0)
        
        -- (Enlighten Label removed)
        
        return row
    end
    
    -- Create 40 Rows (Hidden by default)
    for i=1, 40 do
        local row = CreateConfigRow(i)
        if i==1 then row:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
        else row:SetPoint("TOPLEFT", getglobal("PriestPowerFramePlayer"..(i-1)), "BOTTOMLEFT", 0, 0) end
        row:Hide()
    end
end


function PriestPowerSubButton_OnClick(btn)
    -- Name format: PriestPowerFramePlayer1Group1Fort
    local parentName = btn:GetParent():GetName() -- ...Group1
    local grandParentName = btn:GetParent():GetParent():GetName() -- ...Player1
    
    local _, _, pid = string.find(grandParentName, "Player(%d+)")
    local _, _, gid = string.find(parentName, "Group(%d+)")
    
    pid = tonumber(pid)
    gid = tonumber(gid)
    local isFort = string.find(btn:GetName(), "Fort")
    local isSpirit = string.find(btn:GetName(), "Spirit")
    local isShadow = string.find(btn:GetName(), "Shadow")
    
    local pname = getglobal("PriestPowerFramePlayer"..pid.."Name"):GetText()
    
    -- Permission Check
    if pname ~= UnitName("player") and not PriestPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: You must be promoted to assign others.")
        return
    end
    
    -- Current Value
    local cur = 0
    if PriestPower_Assignments[pname] and PriestPower_Assignments[pname][gid] then
        cur = PriestPower_Assignments[pname][gid]
    end
    
    -- Decode (2 bits per buff)
    local f = math.mod(cur, 4)
    local s = math.mod(math.floor(cur/4), 4)
    local sh = math.mod(math.floor(cur/16), 4)
    
    -- Cycle: 0 -> 1 (Group) -> 2 (Single) -> 0
    if isFort then f = math.mod(f + 1, 3)
    elseif isSpirit then s = math.mod(s + 1, 3)
    elseif isShadow then sh = math.mod(sh + 1, 3) end
    
    -- Re-encode
    cur = f + (s * 4) + (sh * 16)
    
    PriestPower_Assignments[pname] = PriestPower_Assignments[pname] or {}
    PriestPower_Assignments[pname][gid] = cur
    
    PriestPower_SendMessage("ASSIGN "..pname.." "..gid.." "..cur)
    PriestPower_UpdateUI()
end

function PriestPowerSubButton_OnEnter(btn)
     GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
     local isFort = string.find(btn:GetName(), "Fort")
     local isSpirit = string.find(btn:GetName(), "Spirit")
     local isShadow = string.find(btn:GetName(), "Shadow")
     
     local label = "Unknown"
     if isFort then label = "Fortitude"
     elseif isSpirit then label = "Spirit"
     elseif isShadow then label = "Shadow Protection" end
     
     GameTooltip:SetText(label)
     GameTooltip:AddLine("Click to toggle:")
     GameTooltip:AddLine("Off -> Group -> Single", 1, 1, 1)
     GameTooltip:Show()
end

-----------------------------------------------------------------------------------
-- Custom Scrollable Player Selection Frame
-----------------------------------------------------------------------------------

PP_SCROLL_ROWS = 10  -- Number of visible rows
PP_ROW_HEIGHT = 20

function PP_CreatePlayerSelectFrame()
    if getglobal("PPPlayerSelectFrame") then return end
    
    local f = CreateFrame("Frame", "PPPlayerSelectFrame", UIParent)
    f:SetWidth(220)
    f:SetHeight(30 + (PP_SCROLL_ROWS * PP_ROW_HEIGHT))
    f:SetPoint("CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("Select Target")
    f.title = title
    
    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    
    -- Clear Assignment Button
    local clearBtn = CreateFrame("Button", "PPPlayerSelectClear", f, "UIPanelButtonTemplate")
    clearBtn:SetWidth(100)
    clearBtn:SetHeight(20)
    clearBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        PP_SelectPlayer("CLEAR")
    end)
    
    -- Scroll Frame Container
    local scrollContainer = CreateFrame("Frame", nil, f)
    scrollContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -52)
    scrollContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 8)
    
    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "PPPlayerSelectScroll", scrollContainer, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(PP_ROW_HEIGHT, PP_UpdatePlayerSelectList)
    end)
    
    -- Create Row Buttons
    for i = 1, PP_SCROLL_ROWS do
        local row = CreateFrame("Button", "PPPlayerSelectRow"..i, scrollContainer)
        row:SetWidth(180)
        row:SetHeight(PP_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, -((i-1) * PP_ROW_HEIGHT))
        
        -- Highlight Texture
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hl:SetBlendMode("ADD")
        
        -- Text
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", 5, 0)
        text:SetJustifyH("LEFT")
        row.text = text
        
        -- Check Mark (for current selection)
        local check = row:CreateTexture(nil, "OVERLAY")
        check:SetWidth(14)
        check:SetHeight(14)
        check:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:Hide()
        row.check = check
        
        row:SetScript("OnClick", function()
            if this.playerName then
                PP_SelectPlayer(this.playerName)
            end
        end)
        
        row:Hide()
    end
    
    -- Movable
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    f:Hide()
end

-- Data for selection
PP_PlayerList = {}

function PP_PopulatePlayerList()
    PP_PlayerList = {}
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid > 0 then
        -- Raid: Sort by group then name
        local byGroup = {}
        for g = 1, 8 do byGroup[g] = {} end
        
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            if name and subgroup >= 1 and subgroup <= 8 then
                table.insert(byGroup[subgroup], { name = name, class = class, group = subgroup })
            end
        end
        
        for g = 1, 8 do
            for _, p in ipairs(byGroup[g]) do
                table.insert(PP_PlayerList, p)
            end
        end
    elseif numParty > 0 then
        -- Party
        local _, pClass = UnitClass("player")
        table.insert(PP_PlayerList, { name = UnitName("player"), class = pClass or "Unknown", group = 1 })
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            if name then
                table.insert(PP_PlayerList, { name = name, class = class or "Unknown", group = 1 })
            end
        end
    else
        -- Solo
        local _, pClass = UnitClass("player")
        table.insert(PP_PlayerList, { name = UnitName("player"), class = pClass or "Unknown", group = 1 })
    end
end

function PP_UpdatePlayerSelectList()
    local scrollFrame = getglobal("PPPlayerSelectScroll")
    if not scrollFrame then return end
    
    local totalItems = table.getn(PP_PlayerList)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    
    FauxScrollFrame_Update(scrollFrame, totalItems, PP_SCROLL_ROWS, PP_ROW_HEIGHT)
    
    -- Force scrollbar to always be visible
    local scrollBar = getglobal("PPPlayerSelectScrollScrollBar")
    if scrollBar then
        scrollBar:Show()
    end
    
    local mode = PriestPower_AssignMode or "Champ"
    local currentAssignment = nil
    if PriestPower_ContextName and PriestPower_LegacyAssignments[PriestPower_ContextName] then
        currentAssignment = PriestPower_LegacyAssignments[PriestPower_ContextName][mode]
    end
    
    for i = 1, PP_SCROLL_ROWS do
        local row = getglobal("PPPlayerSelectRow"..i)
        local idx = offset + i
        
        if idx <= totalItems then
            local p = PP_PlayerList[idx]
            row.playerName = p.name
            row.text:SetText("["..p.group.."] "..p.name.." ("..p.class..")")
            
            -- Show check if currently assigned
            if p.name == currentAssignment then
                row.check:Show()
            else
                row.check:Hide()
            end
            
            row:Show()
        else
            row.playerName = nil
            row:Hide()
        end
    end
end

function PP_ShowPlayerSelect(anchorFrame, priestName, mode)
    PP_CreatePlayerSelectFrame()
    
    PriestPower_ContextName = priestName
    PriestPower_AssignMode = mode or "Champ"
    
    local f = getglobal("PPPlayerSelectFrame")
    f.title:SetText("Select "..mode.." Target")
    
    -- Position near anchor
    f:ClearAllPoints()
    if anchorFrame then
        f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
    else
        f:SetPoint("CENTER", 0, 0)
    end
    
    PP_PopulatePlayerList()
    PP_UpdatePlayerSelectList()
    
    f:Show()
end

function PP_SelectPlayer(playerName)
    local pname = PriestPower_ContextName
    local mode = PriestPower_AssignMode or "Champ"
    
    if not pname then return end
    
    PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}
    
    if playerName == "CLEAR" then
        PriestPower_LegacyAssignments[pname][mode] = nil
        DEFAULT_CHAT_FRAME:AddMessage("Cleared "..mode.." for "..pname)
        if mode == "Champ" then
            PriestPower_SendMessage("ASSIGNCHAMP "..pname.." nil")
        end
    else
        PriestPower_LegacyAssignments[pname][mode] = playerName
        DEFAULT_CHAT_FRAME:AddMessage("Assigned "..mode.." for "..pname..": "..playerName)
        if mode == "Champ" then
            PriestPower_SendMessage("ASSIGNCHAMP "..pname.." "..playerName)
        end
    end
    
    PriestPower_UpdateUI()
    
    local f = getglobal("PPPlayerSelectFrame")
    if f then f:Hide() end
end

-- Context for Dropdown (Which priest are we assigning for?)
PriestPower_ContextName = nil
PriestPower_AssignMode = "Champ" -- "Champ" or "Enlighten"

function PriestPowerChampButton_OnClick(btn)
    local grandParent = btn:GetParent():GetParent() -- PriestPowerFramePlayerX OR PriestPowerBuffBar
    local pname = nil
    
    if grandParent:GetName() == "PriestPowerBuffBar" then
        pname = UnitName("player")
    else
        local _, _, pid = string.find(grandParent:GetName(), "Player(%d+)")
        if pid then
            pid = tonumber(pid)
            pname = getglobal("PriestPowerFramePlayer"..pid.."Name"):GetText()
        end
    end
    
    if not pname then return end

    PriestPower_ContextName = pname
    PriestPower_AssignMode = "Champ"
    
    -- Permission Check
    if pname ~= UnitName("player") and not PriestPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: You must be promoted to assign others.")
        return
    end
    
    PP_ShowPlayerSelect(btn, pname, "Champ")
end

function PriestPowerEnlightenButton_OnClick(btn)
    local grandParent = btn:GetParent():GetParent()
    local pname = nil
    
    if grandParent:GetName() == "PriestPowerBuffBar" then
        pname = UnitName("player")
    else
        local _, _, pid = string.find(grandParent:GetName(), "Player(%d+)")
        if pid then
            pid = tonumber(pid)
            pname = getglobal("PriestPowerFramePlayer"..pid.."Name"):GetText()
        end
    end
    
    if not pname then return end

    PriestPower_ContextName = pname
    PriestPower_AssignMode = "Enlighten"
    
    if pname ~= UnitName("player") and not PriestPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: You must be promoted to assign others.")
        return
    end
    
    PP_ShowPlayerSelect(btn, pname, "Enlighten")
end

function PriestPower_AssignChamp_OnClick()
    local targetName = this.value
    local pname = PriestPower_ContextName
    local mode = PriestPower_AssignMode or "Champ"
    
    if not pname then return end
    
    PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}

    if targetName == "CLEAR" then
        PriestPower_LegacyAssignments[pname][mode] = nil
        DEFAULT_CHAT_FRAME:AddMessage("Cleared "..mode.." for "..pname)
        -- PriestPower_SendMessage("ASSIGNCHAMP "..pname.." nil") -- Need new message for Enlighten?
        -- Reusing ASSIGNCHAMP logic might overwrite. Ideally custom message.
        -- But for now, local state. To sync, we DO need a new message or parameter.
        -- For simplicity (User hasn't asked for sync protocol update yet), assume local for now or partial sync.
        -- Legacy ASSIGNCHAMP handled only Champ.
        -- If we want to sync Enlighten, we need "ASSIGNENLIGHTEN"?
        -- Let's stick to local + basic sync if mode is Champ.
        if mode == "Champ" then
             PriestPower_SendMessage("ASSIGNCHAMP "..pname.." nil")
        end
    else
        PriestPower_LegacyAssignments[pname][mode] = targetName
        DEFAULT_CHAT_FRAME:AddMessage("Assigned "..mode.." for "..pname..": "..targetName)
        if mode == "Champ" then
             PriestPower_SendMessage("ASSIGNCHAMP "..pname.." "..targetName)
        end
    end
    
    PriestPower_UpdateUI()
    CloseDropDownMenus()
end

function PriestPower_ChampDropDown_Initialize()
    local info = {}
    local mode = PriestPower_AssignMode or "Champ"
    
    -- Option to Clear
    info = {}
    info.text = ">> Clear Assignment <<"
    info.value = "CLEAR"
    info.func = PriestPower_AssignChamp_OnClick
    UIDropDownMenu_AddButton(info)
    
    -- List Raid Members by Group (Submenus)
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        -- Build group tables
        local groups = {}
        for g = 1, 8 do groups[g] = {} end
        
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            if name and subgroup >= 1 and subgroup <= 8 then
                table.insert(groups[subgroup], { name = name, class = class })
            end
        end
        
        -- Create submenu for each non-empty group
        for g = 1, 8 do
            if table.getn(groups[g]) > 0 then
                info = {}
                info.text = "Group "..g.." ("..table.getn(groups[g])..")"
                info.hasArrow = 1
                info.notCheckable = 1
                info.value = g
                UIDropDownMenu_AddButton(info)
            end
        end
    else
        -- If in party (Debug/5-man) or Solo
        local numParty = GetNumPartyMembers()
        
        -- Add Player (Always available in Party/Solo)
        info = {}
        info.text = UnitName("player")
        info.value = UnitName("player")
        info.func = PriestPower_AssignChamp_OnClick
        UIDropDownMenu_AddButton(info)
         
        if numParty > 0 then
            for i=1, numParty do
                local name = UnitName("party"..i)
                if name then
                    info = {}
                    info.text = name
                    info.value = name
                    info.func = PriestPower_AssignChamp_OnClick
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
    end
end

-- Submenu for each raid group
function PriestPower_ChampDropDown_GroupInit(level)
    if level ~= 2 then return end
    
    local groupID = UIDROPDOWNMENU_MENU_VALUE
    if not groupID or type(groupID) ~= "number" then return end
    
    local mode = PriestPower_AssignMode or "Champ"
    
    for i = 1, GetNumRaidMembers() do
        local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
        if name and subgroup == groupID then
            local info = {}
            info.text = name.." ("..class..")"
            info.value = name
            info.func = PriestPower_AssignChamp_OnClick
            
            -- Check if currently assigned
            if PriestPower_ContextName and PriestPower_LegacyAssignments[PriestPower_ContextName] and 
               PriestPower_LegacyAssignments[PriestPower_ContextName][mode] == name then
                info.checked = 1
            end
            
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

-- Combined initializer that handles both levels
function PriestPower_ChampDropDown_Combined(level)
    if not level then level = 1 end
    
    if level == 1 then
        PriestPower_ChampDropDown_Initialize()
    elseif level == 2 then
        PriestPower_ChampDropDown_GroupInit(level)
    end
end


-----------------------------------------------------------------------------------
-- Frame Position & Scaling
-----------------------------------------------------------------------------------



-----------------------------------------------------------------------------------
-- New BuffBar Implementation (Pure Lua)
-----------------------------------------------------------------------------------

function PriestPowerBuffBar_Create()
    if getglobal("PriestPowerBuffBar") then return end
    
    -- 1. Main Frame
    local f = CreateFrame("Frame", "PriestPowerBuffBar", UIParent)
    f:SetFrameStrata("LOW")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetWidth(120)
    f:SetHeight(30)
    
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0,0,0,0.5)
    
    -- 2. Drag & Resize Logic variables
    f.isResizing = false
    f.startScale = 1.0

    -- 3. Scripts
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            this:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function() 
        this:StopMovingOrSizing()
        PriestPowerBuffBar_SavePosition()
    end)
    f:SetScript("OnHide", function() this:StopMovingOrSizing() end)
    
    -- HOOK: Run global update loop
    -- Use anonymous function to pass 'arg1' (elapsed) explicitly, as SetScript might not pass it directly or correctly in 1.12
    f:SetScript("OnUpdate", function() PriestPower_OnUpdate(arg1) end)

    -- 4. Title Header
    local lbl = f:CreateFontString(f:GetName().."Title", "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", f, "TOP", 0, -2)
    lbl:SetText("PriestPower")
    
    -- 5. Resize Grip (Custom Button)
    local grip = PP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    -- Remove old texture/script as PP_CreateResizeGrip handles it
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    -- 6. Pre-create Row Frames (Pool of 9)
    -- Rows 1-8: Group Buffs
    -- Row 9: Champion
    -- Row 10: Enlighten
    for i=1, 10 do
        local row = PP_CreateHUDRow(f, "PriestPowerHUDRow"..i, i)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -20) -- Temp anchor
        
        -- Special width for Row 9 (Champ) due to 3 action buttons + revive
        if i == 9 then row:SetWidth(150) end
        
        row:Hide()
    end
    
    
    -- Restoring Position
    PriestPowerBuffBar_RestorePosition()
end

function PriestPowerBuffBar_SavePosition()
    if not PriestPowerBuffBar then return end
    if not PP_PerUser then PP_PerUser = {} end

    -- Save relative to UIParent center or bottomleft?
    -- Safest is standard GetPoint
    local point, relativeTo, relativePoint, xOfs, yOfs = PriestPowerBuffBar:GetPoint()
    PP_PerUser.Point = point
    PP_PerUser.RelativePoint = relativePoint
    PP_PerUser.X = xOfs
    PP_PerUser.Y = yOfs
    PP_PerUser.Scale = PriestPowerBuffBar:GetScale()
end

function PriestPowerBuffBar_RestorePosition()
    if not PriestPowerBuffBar then return end
    if not PP_PerUser then PP_PerUser = { Scale = 0.7 } end
    
    if PP_PerUser.Point then
        PriestPowerBuffBar:ClearAllPoints()
        PriestPowerBuffBar:SetPoint(PP_PerUser.Point, "UIParent", PP_PerUser.RelativePoint, PP_PerUser.X, PP_PerUser.Y)
    else
        PriestPowerBuffBar:SetPoint("CENTER", 0, 0)
    end
    
    if PP_PerUser.Scale then
        PriestPowerBuffBar:SetScale(PP_PerUser.Scale)
    end
end

function PriestPower_UI_OnScaleUpdate()
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


function PriestPower_UpdateBuffBar()
    -- Renamed locally, but public API kept same for compatibility
    if not getglobal("PriestPowerBuffBar") then return end
    
    local f = PriestPowerBuffBar
    
    local pname = UnitName("player")
    local assigns = PriestPower_Assignments[pname]
    
    local lastRow = nil
    local count = 0
    

    if assigns or (PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"]) then
        for i=1, 10 do
            local row = getglobal("PriestPowerHUDRow"..i)
            local showRow = false
            
            if i == 9 then
                 -- CHAMPION ROW
                 local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"]
                 if target then
                     local status = CurrentBuffsByName[target]
                     local btnP = getglobal(row:GetName().."Proclaim")
                     local btnG = getglobal(row:GetName().."Grace")
                     local btnE = getglobal(row:GetName().."Empower")
                     local btnR = getglobal(row:GetName().."Revive")
                     
                     -- PROCLAIM (0/1 or 1/1)
                     local hasProclaim = (status and status.hasProclaim)
                     if hasProclaim then
                         btnP:Hide()
                     else
                         btnP:Show()
                         btnP.tooltipText = "Champion: "..target.." (Proclaim)"
                         local txtP = getglobal(btnP:GetName().."Text")
                         txtP:SetText("0/1")
                         txtP:SetTextColor(1,0,0)
                         showRow = true
                     end
                     
                     -- GRACE / EMPOWER (Timers)
                     local function GetTimerText(key)
                         if PP_BuffTimers[target] and PP_BuffTimers[target][key] then
                             local rem = PP_BuffTimers[target][key] - time()
                             if rem > 3600 then return math.ceil(rem/3600).."h"
                             elseif rem > 60 then return math.ceil(rem/60).."m"
                             elseif rem > 0 then return math.ceil(rem).."s"
                             end
                         end
                         return ""
                     end
                     
                     -- Anchoring G/E (Side by side default)
                     btnG:ClearAllPoints(); btnG:SetPoint("LEFT", btnP, "RIGHT", 2, 0)
                     btnE:ClearAllPoints(); btnE:SetPoint("LEFT", btnG, "RIGHT", 2, 0)
                     
                     if status and status.dead then
                         btnP:Hide(); btnG:Hide(); btnE:Hide(); btnR:Show()
                         btnR.tooltipText = "Champion: "..target.." (DEAD - Revive)"
                         showRow = true
                     elseif status then
                        btnR:Hide()
                        if status.hasGrace or status.hasEmpower then
                            btnG:Hide()
                            btnE:Hide()
                        else
                            btnG:Show(); btnG:SetAlpha(1.0); getglobal(btnG:GetName().."Text"):SetText("")
                            btnE:Show(); btnE:SetAlpha(1.0); getglobal(btnE:GetName().."Text"):SetText("")
                            showRow = true
                        end
                     else
                         btnR:Hide()
                         -- No status (not in raid? or not scanned) -> Show both as available/missing
                         btnG:Show(); btnG:SetAlpha(1.0); getglobal(btnG:GetName().."Text"):SetText("")
                         btnE:Show(); btnE:SetAlpha(1.0); getglobal(btnE:GetName().."Text"):SetText("")
                         showRow = true
                     end
                 else
                     -- No champ assigned
                 end
            elseif i == 10 then
                 -- ENLIGHTEN ROW (Using Enlighten Assignment)
                 local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Enlighten"]
                 if target then
                     local status = CurrentBuffsByName[target]
                     local btnEn = getglobal(row:GetName().."Enlighten")
                     
                     local hasEnlighten = (status and status.hasEnlighten)
                     if hasEnlighten then
                         btnEn:Hide()
                     else
                         btnEn:Show()
                         btnEn.tooltipText = "Enlighten: "..target
                         local txt = getglobal(btnEn:GetName().."Text")
                         txt:SetText("0/1")
                         txt:SetTextColor(1,0,0)
                         showRow = true
                     end
                     showRow = true
                 end
            elseif assigns[i] and assigns[i] > 0 then
                 local val = assigns[i]
                 local fS = math.mod(val, 4)
                 local sS = math.mod(math.floor(val/4), 4)
                 local shS = math.mod(math.floor(val/16), 4)
                 
                 local function UpdateHUD(btn, state, typeIdx, buffKey, label)
                     if not btn then return end
                     if state > 0 then
                         local missing = 0; local total = 0
                         if CurrentBuffs[i] then
                             for _, m in CurrentBuffs[i] do
                                 total = total + 1
                                 if not m[buffKey] and not m.dead then missing = missing + 1 end
                             end
                         end
                         
                         btn.assignmentState = state
                         
                         if missing > 0 then
                             btn:Show()
                             btn.tooltipText = "Group "..i..": "..label.."\nLeft-click: Group Buff\nRight-click: Spot-buff ("..missing.." missing)"
                             local txt = getglobal(btn:GetName().."Text")
                             local icon = getglobal(btn:GetName().."Icon")
                             local buffed = total - missing
                             txt:SetText(buffed.."/"..total)
                             txt:SetTextColor(1,0,0)
                             
                             if state == 1 then
                                 icon:SetTexture(PriestPower_BuffIconGroup[typeIdx])
                             else
                                 icon:SetTexture(PriestPower_BuffIcon[typeIdx])
                             end
                             showRow = true
                         else
                             btn:Hide()
                         end
                     else
                         btn:Hide()
                     end
                 end
                 
                 UpdateHUD(getglobal(row:GetName().."Fort"), fS, 0, "hasFort", "Fortitude")
                 UpdateHUD(getglobal(row:GetName().."Spirit"), sS, 1, "hasSpirit", "Spirit")
                 UpdateHUD(getglobal(row:GetName().."Shadow"), shS, 2, "hasShadow", "Shadow")
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
    end
    
    -- Resize Main Frame
    local newHeight = 25 + (count * 34)
    if newHeight < 40 then newHeight = 40 end
    f:SetHeight(newHeight)
    
    -- Dynamic Width? If Champ is visible (which is row 9), widen parent?
    local lastRowIsChamp = (lastRow and lastRow:GetName() == "PriestPowerHUDRow9")
    local lastRowIsEnlight = (lastRow and lastRow:GetName() == "PriestPowerHUDRow10")
    if lastRowIsChamp or lastRowIsEnlight then
         f:SetWidth(185)
    else
         f:SetWidth(145)
    end
end

function PriestPower_BuffButton_OnClick(btn)
    local name = btn:GetName()
    -- Format: PriestPowerHUDRow{i}{Suffix}
    local _, _, rowStr, suffix = string.find(name, "PriestPowerHUDRow(%d+)(.*)")
    if not rowStr then return end
    
    local i = tonumber(rowStr)
    local pname = UnitName("player")
    
    if i == 9 then
        -- Champion Logic
        local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"]
        if not target then
            DEFAULT_CHAT_FRAME:AddMessage("PriestPower: No Champion Assigned!")
            return
        end
        
        -- Mapping Suffix to Spell Name
        -- Proclaim -> "Proclaim Champion"
        -- Grace -> "Champion's Grace"
        -- Empower -> "Champion's Empower"
        local spell = nil
        if suffix == "Proclaim" then spell = SPELL_PROCLAIM
        elseif suffix == "Grace" then spell = SPELL_GRACE
        elseif suffix == "Empower" then spell = SPELL_EMPOWER
        elseif suffix == "Revive" then spell = SPELL_REVIVE
        end
        
        if spell then
            -- Simple Target-Cast-TargetLast logic
            -- Note: In 1.12, CastSpellByName works but requires target.
            -- Check if target is in range? (Can't easily without targeting)
            
            ClearTarget()
            TargetByName(target, true)
            if UnitName("target") == target then
                CastSpellByName(spell)
                TargetLastTarget()
                -- Force Scan 
                PriestPower_ScanRaid()
                PriestPower_UpdateBuffBar() 
            else
                DEFAULT_CHAT_FRAME:AddMessage("PriestPower: Could not target "..target)
            end
        end
    elseif i == 10 then
        -- Enlighten Logic (Using Enlighten Assignment)
        local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Enlighten"]
        if not target then
            DEFAULT_CHAT_FRAME:AddMessage("PriestPower: No Target Assigned for Enlighten!")
            return
        end
        
        if suffix == "Enlighten" then
             ClearTarget()
             TargetByName(target, true)
             if UnitName("target") == target then
                 CastSpellByName("Enlighten")
                 TargetLastTarget()
                 -- Force Scan
                 PriestPower_ScanRaid()
                 PriestPower_UpdateBuffBar() 
             else
                 DEFAULT_CHAT_FRAME:AddMessage("PriestPower: Could not target "..target)
             end
        end
    else
        -- Group Buff Logic
        -- Left-click = Group Buff (Prayer of X)
        -- Right-click = Single Buff (spot-buff one person)
        local gid = i
        local spellName = nil
        local buffKey = nil
        local isRightClick = (arg1 == "RightButton")
        
        -- Determine which buff type was clicked
        if suffix == "Fort" then 
            buffKey = "hasFort"
            if isRightClick then
                spellName = SPELL_FORTITUDE -- Single target
            else
                spellName = SPELL_P_FORTITUDE -- Group buff
            end
        elseif suffix == "Spirit" then 
            buffKey = "hasSpirit"
            if isRightClick then
                spellName = SPELL_SPIRIT -- Single target
            else
                spellName = SPELL_P_SPIRIT -- Group buff
            end
        elseif suffix == "Shadow" then
            buffKey = "hasShadow"
            if isRightClick then
                spellName = SPELL_SHADOW_PROT -- Single target
            else
                spellName = SPELL_P_SHADOW_PROT -- Group buff
            end
        end
        
        if spellName and CurrentBuffs[gid] then
             -- Iterate members in group
             local castDone = false
             for _, member in CurrentBuffs[gid] do
                 -- Check eligibility: Visible, Alive, Missing Buff
                 if member.visible and not member.dead and not member[buffKey] then
                     -- Potential candidate
                     ClearTarget()
                     TargetByName(member.name, true)
                     
                     -- Verify Target
                     if UnitExists("target") and UnitName("target") == member.name then
                         -- Check Range (28 yards approx)
                         if CheckInteractDistance("target", 4) then
                             CastSpellByName(spellName)
                             TargetLastTarget()
                             -- Force Scan to update "1/5" text immediately (local client state)
                             PriestPower_ScanRaid()
                             PriestPower_UpdateBuffBar() 
                             castDone = true
                             break -- Stop loop, one cast per click
                         else
                             -- Out of range, skip to next
                             ClearTarget()
                         end
                     end
                 end
             end
             
             if not castDone then
                 DEFAULT_CHAT_FRAME:AddMessage("PriestPower: No eligible targets in range for Group "..gid)
                 TargetLastTarget() -- Restore if we messed with target but didn't cast
             end
        else
            DEFAULT_CHAT_FRAME:AddMessage("PriestPower: Unknown Button ("..suffix..")")
        end
    end
end



-- Hook for creation
function PriestPower_CreateBuffBar()
    PriestPowerBuffBar_Create()
end

-- Initialize
local ep = CreateFrame("Frame", "PriestPowerEventFrame", UIParent)
ep:SetScript("OnEvent", function() PriestPower_OnEvent(event) end)
PriestPower_OnLoad(ep)

-- Dropdown Frame
if not getglobal("PriestPowerChampDropDown") then
    CreateFrame("Frame", "PriestPowerChampDropDown", UIParent, "UIDropDownMenuTemplate")
end
