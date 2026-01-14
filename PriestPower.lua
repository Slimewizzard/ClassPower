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

PP_NextScan = PP_PerUser.scanfreq
PP_PREFIX = "PRPWR"

-- Spell Constants
-- 0: Fortitude, 1: Spirit, 2: Shadow Prot
PriestPower_BuffIcon = {
    [0] = "Interface\\Icons\\Spell_Holy_WordFortitude",
    [1] = "Interface\\Icons\\Spell_Holy_DivineSpirit",
    [2] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    [3] = "Interface\\Icons\\Spell_Holy_ProclaimChampion", 
    [4] = "Interface\\Icons\\Spell_Holy_MindVision", -- Enlighten
}

-- Icons for the "Special" champion spells
PriestPower_ChampionIcons = {
    ["Proclaim"] = "Interface\\Icons\\Spell_Holy_ProclaimChampion",
    ["Grace"] = "Interface\\Icons\\Spell_Holy_ChampionsGrace",
    ["Empower"] = "Interface\\Icons\\Spell_Holy_EmpowerChampion",
    ["Revive"] = "Interface\\Icons\\Spell_Holy_Resurrection",
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
        -- Reset BuffBar position and scale
        if PP_PerUser then
            PP_PerUser.Point = nil
            PP_PerUser.RelativePoint = nil
            PP_PerUser.X = nil
            PP_PerUser.Y = nil
            PP_PerUser.Scale = 0.7
        end
        local bar = getglobal("PriestPowerBuffBar")
        if bar then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            bar:SetScale(0.7)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r BuffBar reset to default position and scale.")
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
function PriestPower_OnLoad()
    this:RegisterEvent("SPELLS_CHANGED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("PARTY_MEMBERS_CHANGED")
    this:RegisterEvent("PLAYER_LOGIN")
    this:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    
    SlashCmdList["PRIESTPOWER"] = function(msg)
        PriestPower_SlashCommandHandler(msg)
    end
    SLASH_PRIESTPOWER1 = "/prip" 
    SLASH_PRIESTPOWER2 = "/priestpower"
    SLASH_PRIESTPOWER3 = "/prp"

    if PP_DebugEnabled then PP_Debug("PriestPower OnLoad") end
    
    -- message("PriestPower Loaded Successfully") 
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
        UIDropDownMenu_Initialize(PriestPowerChampDropDown, PriestPower_ChampDropDown_Initialize, "MENU")
        
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
                hasProclaim = false,
                hasGrace = false,
                hasEmpower = false
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
        if i > 10 then break end 
        
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
                
                local iconFort = getglobal(btnFort:GetName().."Icon")
                local iconSpirit = getglobal(btnSpirit:GetName().."Icon")
                
                local textFort = getglobal(btnFort:GetName().."Text")
                local textSpirit = getglobal(btnSpirit:GetName().."Text")
                
                -- Default text
                textFort:SetText("")
                textSpirit:SetText("")
                
                -- Check Assignment
                local assignVal = 0
                if PriestPower_Assignments[name] and PriestPower_Assignments[name][gid] then
                    assignVal = PriestPower_Assignments[name][gid]
                end
                
                -- VAL: 0=None, 1=Fort, 2=Spirit, 3=Both
                -- Fort Logic (Bit 1)
                if math.mod(assignVal, 2) == 1 then
                    iconFort:SetTexture(PriestPower_BuffIcon[0]) -- Fort Icon
                    iconFort:Show()
                    btnFort:SetAlpha(1.0)
                    
                    -- Status Check (How many have it?)
                    local missing = 0
                    local total = 0
                    if CurrentBuffs[gid] then
                        for _, member in CurrentBuffs[gid] do
                            total = total + 1
                            if not member.hasFort and not member.dead then missing = missing + 1 end
                        end
                    end
                    if total > 0 then textFort:SetText( (total-missing).."/"..total ) end
                    if missing > 0 then textFort:SetTextColor(1, 0, 0) else textFort:SetTextColor(0, 1, 0) end
                    
                else
                    iconFort:Hide()
                    btnFort:SetAlpha(0.2) -- Dimmed if not assigned
                end
                
                -- Spirit Logic (Bit 2)
                if assignVal >= 2 then
                    iconSpirit:SetTexture(PriestPower_BuffIcon[1]) -- Spirit Icon
                    iconSpirit:Show()
                    btnSpirit:SetAlpha(1.0)
                    
                    local missing = 0
                    local total = 0
                    if CurrentBuffs[gid] then
                        for _, member in CurrentBuffs[gid] do
                            total = total + 1
                            if not member.hasSpirit and not member.dead then missing = missing + 1 end
                        end
                    end
                    if total > 0 then textSpirit:SetText( (total-missing).."/"..total ) end
                    if missing > 0 then textSpirit:SetTextColor(1, 0, 0) else textSpirit:SetTextColor(0, 1, 0) end

                else
                    iconSpirit:Hide()
                    btnSpirit:SetAlpha(0.2)
                end
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
    
    for k = i, 10 do getglobal("PriestPowerFramePlayer"..k):Hide() end
    
    PriestPower_UpdateBuffBar()
end

-- ... [Snip: OnClick Handlers] ...


-----------------------------------------------------------------------------------
-- New Config Window Implementation (Pure Lua)
-----------------------------------------------------------------------------------

function PriestPowerConfig_Create()
    if getglobal("PriestPowerConfigBase") then return end
    
    local f = CreateFrame("Frame", "PriestPowerConfigBase", UIParent)
    f:SetWidth(1000)
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
    
    -- Title
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -18)
    t:SetText("PriestPower Configuration")
    
    -- Close Button
    local close = CreateFrame("Button", "$parentClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- Drag Scripts
    f:SetScript("OnMouseDown", function() if arg1=="LeftButton" then this:StartMoving() end end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Resize Grip (Bottom Right)
    local grip = CreateFrame("Button", "$parentResizeGrip", f)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", -15, 15)
    grip:SetNormalTexture("Interface\\AddOns\\PriestPower\\PriestPower-ResizeGrip.tga")
    grip:SetScript("OnMouseDown", function() 
        this:GetParent():StartSizing("BOTTOMRIGHT") 
    end)
    grip:SetScript("OnMouseUp", function() 
        this:GetParent():StopMovingOrSizing() 
    end)

    -- Container for ScrollFrame (if needed, but user just wanted scalable window)
    -- For now, fixed list of rows inside the scalable frame.
    
    -- Row Creation Helper
    local function CreateConfigRow(i)
        local row = CreateFrame("Frame", "PriestPowerFramePlayer"..i, f)
        row:SetWidth(1000)
        row:SetHeight(56)
        
        -- Name Label
        local nameParams = { "TOPLEFT", 25, -15 }
        local nameStr = row:CreateFontString("$parentName", "OVERLAY", "GameFontHighlightSmall")
        nameStr:SetPoint(unpack(nameParams))
        nameStr:SetWidth(100); nameStr:SetHeight(16); nameStr:SetJustifyH("LEFT")
        nameStr:SetText("Priest "..i)
        
        -- Clear Button
        local clear = CreateFrame("Button", "$parentClear", row, "PriestPowerClearButtonTemplate")
        clear:SetPoint("TOPLEFT", 5, -14)
        
        -- Capability Icons Frame
        local caps = CreateFrame("Frame", "$parentCap", row)
        caps:SetWidth(140); caps:SetHeight(42)
        caps:SetPoint("TOPLEFT", 110, -12)
        
        local function CreateCapIcon(suffix, relTo)
            local btn = CreateFrame("Button", "$parent"..suffix, caps, "PriestPowerCapabilityIconTemplate")
            if relTo then btn:SetPoint("LEFT", relTo, "RIGHT", 0, 0)
            else btn:SetPoint("LEFT", 0, 0) end
            return btn
        end
        local cF = CreateCapIcon("Fort", nil)
        local cS = CreateCapIcon("Spirit", cF)
        local cSh = CreateCapIcon("Shadow", cS)
        local cP = CreateCapIcon("Proclaim", cSh)
        local cG = CreateCapIcon("Grace", cP)
        local cE = CreateCapIcon("Empower", cG)
        local cR = CreateCapIcon("Revive", cE)
        local cEn = CreateCapIcon("Enlighten", cR)
        
        -- Group Buttons (1-8)
        local lastGrp = nil
        for g=1, 8 do
            local grp = CreateFrame("Frame", "$parentGroup"..g, row, "PriestPowerGroupTemplate")
            if lastGrp then grp:SetPoint("TOPLEFT", lastGrp, "TOPRIGHT", 0, 0)
            else grp:SetPoint("TOPLEFT", 260, -5) end
            lastGrp = grp
        end
        
        -- Champion Assignment
        local champ = CreateFrame("Frame", "$parentChamp", row, "PriestPowerChampionTemplate")
        champ:SetPoint("TOPLEFT", lastGrp, "TOPRIGHT", 20, 0)
        -- Label
        local cl = row:CreateFontString("$parentChampName", "OVERLAY", "GameFontHighlightSmall")
        cl:SetPoint("TOPLEFT", 740, -15)
        cl:SetWidth(80); cl:SetHeight(16); cl:SetJustifyH("RIGHT")
        cl:SetText("Champion")
        
        -- Enlighten Assignment
        local enlight = CreateFrame("Frame", "$parentEnlighten", row, "PriestPowerEnlightenTemplate")
        enlight:SetPoint("TOPLEFT", champ, "TOPRIGHT", 5, 0)
         -- Label
        local el = row:CreateFontString("$parentEnlightenName", "OVERLAY", "GameFontHighlightSmall")
        el:SetPoint("TOPLEFT", 840, -15)
        el:SetWidth(80); el:SetHeight(16); el:SetJustifyH("RIGHT")
        el:SetText("Enlighten")
        
        return row
    end
    
    -- Create 40 Rows (Hidden by default)
    for i=1, 40 do
        local row = CreateConfigRow(i)
        if i==1 then row:SetPoint("TOPLEFT", 20, -50)
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
    
    -- Toggle Bits
    -- Fort = 1, Spirit = 2
    if isFort then
        if math.mod(cur, 2) == 1 then cur = cur - 1 else cur = cur + 1 end
    else
        if cur >= 2 then cur = cur - 2 else cur = cur + 2 end
    end
    
    PriestPower_Assignments[pname] = PriestPower_Assignments[pname] or {}
    PriestPower_Assignments[pname][gid] = cur
    
    PriestPower_SendMessage("ASSIGN "..pname.." "..gid.." "..cur)
    PriestPower_UpdateUI()
end

function PriestPowerSubButton_OnEnter(btn)
     GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
     local isFort = string.find(btn:GetName(), "Fort")
     if isFort then
         GameTooltip:SetText("Power Word: Fortitude")
     else
         GameTooltip:SetText("Divine Spirit")
     end
     GameTooltip:AddLine("Click to toggle assignment for this Group.")
     GameTooltip:Show()
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
    
    ToggleDropDownMenu(1, nil, PriestPowerChampDropDown, btn:GetName(), 0, 0)
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
    
    ToggleDropDownMenu(1, nil, PriestPowerChampDropDown, btn:GetName(), 0, 0)
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
    
    -- Option to Clear
    info = {}
    info.text = ">> Clear Assignment <<"
    info.value = "CLEAR"
    info.func = PriestPower_AssignChamp_OnClick
    UIDropDownMenu_AddButton(info)
    
    -- List Raid Members
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        -- Sort or Group logic could go here, for now flat list
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            if name then
                info = {}
                info.text = "["..subgroup.."] "..name.." ("..class..")"
                info.value = name
                info.func = PriestPower_AssignChamp_OnClick
                
                -- Check Checked
                if PriestPower_ContextName and PriestPower_LegacyAssignments[PriestPower_ContextName] and 
                   PriestPower_LegacyAssignments[PriestPower_ContextName]["Champ"] == name then
                    info.checked = 1
                end
                
                UIDropDownMenu_AddButton(info)
            end
        end
    else
    else
        -- If in party (Debug/5-man) or Solo
        local numParty = GetNumPartyMembers()
        
         -- Add Player (Always available in Party/Solo)
         local info = {}
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
    local lbl = f:CreateFontString("$parentTitle", "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", 0, -2)
    lbl:SetText("PriestPower")
    
    -- 5. Resize Grip (Custom Button)
    local grip = CreateFrame("Button", "$parentResizeGrip", f)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\AddOns\\PriestPower\\Images\\ResizeGrip")
    -- Or use standard texture if custom one missing, e.g. ChatFrame
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    grip:SetScript("OnMouseDown", function()
        local p = this:GetParent()
        p.isResizing = true
        p.startScale = p:GetScale()
        p.cursorStartX, p.cursorStartY = GetCursorPosition()
        this:SetScript("OnUpdate", PriestPowerBuffBar_ResizeUpdate)
    end)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        PriestPowerBuffBar_SavePosition()
    end)
    
    -- 6. Pre-create Row Frames (Pool of 9)
    -- Rows 1-8: Group Buffs
    -- Row 9: Champion
    -- Row 10: Enlighten
    for i=1, 10 do
        local row = CreateFrame("Frame", "PriestPowerHUDRow"..i, f)
        row:SetWidth(110)
        row:SetHeight(30)
        
        -- Special width for Row 9 (Champ) due to 3 buttons
        if i == 9 then row:SetWidth(150) end
        row:SetPoint("TOPLEFT", 10, -20) -- Temp anchor
        row:Hide()
        
        -- Label ("Grp X")
        local l = row:CreateFontString("$parentLabel", "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("LEFT", 0, 0)
        l:SetJustifyH("LEFT")
        -- Helper to create button
        local function CreateBuffBtn(suffix)
            local b = CreateFrame("Button", "PriestPowerHUDRow"..i..suffix, row) 
            b:SetWidth(28); b:SetHeight(28)
            b:SetBackdrop(nil)
            b:SetNormalTexture("")
            b:SetPushedTexture("")
            b:SetHighlightTexture("")
            b:SetDisabledTexture("")

            local icon = b:CreateTexture("$parentIcon", "BACKGROUND")
            icon:SetAllPoints(b)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            
            local txt = b:CreateFontString("$parentText", "OVERLAY", "GameFontHighlight")
            txt:SetPoint("CENTER", 0, 0)
            txt:SetText("") 
            
            b:SetScript("OnEnter", function() 
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                if this.tooltipText then
                    GameTooltip:SetText(this.tooltipText)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function() 
                -- TBD: Implement Click to cast logic (PriestPower_BuffButton_OnClick)
                 PriestPower_BuffButton_OnClick(this)
            end)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return b
        end

        if i == 9 then
             l:SetText("Champ")
             -- Champion Buttons
             local btnP = CreateBuffBtn("Proclaim")
             btnP:SetPoint("LEFT", l, "RIGHT", 5, 0)
             getglobal(btnP:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Proclaim"])
             
             local btnG = CreateBuffBtn("Grace")
             btnG:SetPoint("LEFT", btnP, "RIGHT", 2, 0)
             getglobal(btnG:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Grace"])
             
             local btnE = CreateBuffBtn("Empower")
             btnE:SetPoint("LEFT", btnG, "RIGHT", 2, 0)
             getglobal(btnE:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Empower"])
        elseif i == 10 then
             l:SetText("Enlight")
             -- Enlighten Button
             local btnEn = CreateBuffBtn("Enlighten")
             btnEn:SetPoint("LEFT", l, "RIGHT", 5, 0)
             getglobal(btnEn:GetName().."Icon"):SetTexture("Interface\\Icons\\btnholyscriptures")
        else
            l:SetText("Grp "..i)
            
            local btnFort = CreateBuffBtn("Fort")
            btnFort:SetPoint("LEFT", l, "RIGHT", 5, 0)
            
            local btnSpirit = CreateBuffBtn("Spirit")
            btnSpirit:SetPoint("LEFT", btnFort, "RIGHT", 2, 0)
        end
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

function PriestPowerBuffBar_ResizeUpdate()
    local parent = this:GetParent()
    if not parent.isResizing then return end
    
    local cursorX, cursorY = GetCursorPosition()
    
    -- Scale logic:
    -- Calculate distance moved from start
    local diff = (cursorX - parent.cursorStartX)
    -- Normalize by UI Scale (IMPORTANT)
    diff = diff / UIParent:GetEffectiveScale()
    
    local newScale = parent.startScale + (diff * 0.002) -- Sensitivity
    
    if newScale < 0.5 then newScale = 0.5 end
    if newScale > 2.0 then newScale = 2.0 end
    
    -- Standard Scale Logic using StartSizing
    -- The base frame uses StartSizing("BOTTOMRIGHT"), which natively resizes width/height.
    -- However, the user wants "Scale" (Zoom).
    -- If we use standard StartSizing, it changes Width/Height.
    -- If we want to Zoom, we need to intercept OnSizeChanged or use a custom Drag handle.
    -- I implemented a custom Grip with OnMouseDown -> StartSizing.
    -- Wait, StartSizing resizes the dimension.
    -- IF we want to Scale, we need to calculate distance and SetScale.
    
    -- Let's stick to the custom ResizeUpdate logic I had for BuffBar if we want Scale.
    -- BUT for Config Window, usually resizing dimensions is better to see more rows?
    -- User said "scaled such easier by dragging".
    -- If I implemented StartSizing("BOTTOMRIGHT"), it changes width/height.
    -- The ROWS are fixed width (1000).
    -- So changing width of container doesn't help much unless we use a ScrollFrame.
    -- Scaling the WHOLE frame (Zoom it bigger/smaller) seems to be what is requested.
    
    -- Let's replace the Grip script in Create() to use a custom scaling loop instead of StartSizing.
    -- OR, modify the ResizeUpdate function to be generic.
    
    -- Actually, simpler: Use the ResizeGrip I added in Create().
    -- I assigned it `StartSizing`. This will resize the frame's boundary.
    -- Since content is fixed size, this just clips or adds empty space.
    -- To achieve "Zoom", we need to SetScale based on mouse movement.
    
    -- Let's use the explicit Scale Logic:
    local f = parent
    local msg = "Scale: "..format("%.2f", newScale)
    f:SetScale(newScale)
    -- Show feedback?
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
                     
                     -- PROCLAIM (0/1 or 1/1)
                     btnP:Show()
                     btnP.tooltipText = "Champion: "..target.." (Proclaim)"
                     local txtP = getglobal(btnP:GetName().."Text")
                     if status and status.hasProclaim then
                         txtP:SetText("1/1")
                         txtP:SetTextColor(0,1,0)
                     else
                         txtP:SetText("0/1")
                         txtP:SetTextColor(1,0,0)
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
                     
                     if status then
                        if status.hasGrace then
                            btnG:Show(); btnG:SetAlpha(1.0)
                            getglobal(btnG:GetName().."Text"):SetText(GetTimerText("Grace"))
                            btnE:Hide()
                            btnE:SetAlpha(0.4)
                        elseif status.hasEmpower then
                            btnE:Show(); btnE:SetAlpha(1.0)
                            btnE:ClearAllPoints(); btnE:SetPoint("LEFT", btnP, "RIGHT", 2, 0)
                            getglobal(btnE:GetName().."Text"):SetText(GetTimerText("Empower"))
                            btnG:Hide()
                            btnG:SetAlpha(0.4)
                        else
                             -- Neither
                             btnG:Show(); btnG:SetAlpha(0.4); getglobal(btnG:GetName().."Text"):SetText("")
                             btnE:Show(); btnE:SetAlpha(0.4); getglobal(btnE:GetName().."Text"):SetText("")
                        end
                     else
                         btnG:Show(); btnG:SetAlpha(0.4); getglobal(btnG:GetName().."Text"):SetText("")
                         btnE:Show(); btnE:SetAlpha(0.4); getglobal(btnE:GetName().."Text"):SetText("")
                     end
                     showRow = true
                 else
                     -- No champ assigned
                 end
            elseif i == 10 then
                 -- ENLIGHTEN ROW (Using Enlighten Assignment)
                 local target = PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Enlighten"]
                 if target then
                     local status = CurrentBuffsByName[target]
                     local btnEn = getglobal(row:GetName().."Enlighten")
                     
                     btnEn:Show()
                     btnEn.tooltipText = "Enlighten: "..target
                     local txt = getglobal(btnEn:GetName().."Text")
                     
                     if status and status.hasEnlighten then
                         txt:SetText("1/1")
                         txt:SetTextColor(0,1,0)
                     else
                         txt:SetText("0/1")
                         txt:SetTextColor(1,0,0)
                     end
                     showRow = true
                 end
            elseif assigns[i] and assigns[i] > 0 then
               local val = assigns[i]
                -- Check Fort (Bit 1)
                local btnFort = getglobal(row:GetName().."Fort")
                if math.mod(val, 2) == 1 then
                    btnFort:Show()
                    btnFort.tooltipText = "Group "..i..": Fortitude"
                    -- Update Status (Missing/Total)
                    -- (Reusing logic from old function)
                    local missing = 0; local total = 0
                    if CurrentBuffs[i] then
                        for _, m in CurrentBuffs[i] do
                            total = total + 1
                             if not m.hasFort and not m.dead then missing = missing + 1 end
                        end
                    end
                    local txt = getglobal(btnFort:GetName().."Text")
                    if total > 0 then
                        local buffed = total - missing
                        txt:SetText(buffed.."/"..total)
                        if missing > 0 then txt:SetTextColor(1,0,0) -- Red
                        else txt:SetTextColor(0,1,0) end -- Green
                    else
                        txt:SetText("")
                    end                    
                    getglobal(btnFort:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[0])
                    showRow = true
                else
                    btnFort:Hide()
                end
                
                -- Check Spirit (Bit 2)
                local btnSpirit = getglobal(row:GetName().."Spirit")
                if val >= 2 then
                    btnSpirit:Show()
                    btnSpirit.tooltipText = "Group "..i..": Spirit"
                     local missing = 0; local total = 0
                    if CurrentBuffs[i] then
                        for _, m in CurrentBuffs[i] do
                            total = total + 1
                             if not m.hasSpirit and not m.dead then missing = missing + 1 end
                        end
                    end
                    local txt = getglobal(btnSpirit:GetName().."Text")
                    if total > 0 then
                        local buffed = total - missing
                        txt:SetText(buffed.."/"..total)
                        if missing > 0 then txt:SetTextColor(1,0,0) -- Red
                        else txt:SetTextColor(0,1,0) end -- Green
                    else
                        txt:SetText("")
                    end                    getglobal(btnSpirit:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[1])
                    showRow = true
                else
                    btnSpirit:Hide()
                end
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
    local newHeight = 25 + (count * 30)
    if newHeight < 40 then newHeight = 40 end
    f:SetHeight(newHeight)
    
    -- Dynamic Width? If Champ is visible (which is row 9), widen parent?
    local lastRowIsChamp = (lastRow and lastRow:GetName() == "PriestPowerHUDRow9")
    if lastRowIsChamp then
         f:SetWidth(150)
    else
         f:SetWidth(110)
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
        if suffix == "Proclaim" then spell = "Proclaim Champion"
        elseif suffix == "Grace" then spell = "Champion's Grace"
        elseif suffix == "Empower" then spell = "Champion's Empower"
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
        local gid = i
        local spellName = nil
        local buffKey = nil
        
        if suffix == "Fort" then 
            spellName = SPELL_FORTITUDE
            buffKey = "hasFort"
        elseif suffix == "Spirit" then 
            spellName = SPELL_SPIRIT
            buffKey = "hasSpirit"
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
                         -- CheckInteractDistance("target", 4)
                         if CheckInteractDistance("target", 4) then
                             CastSpellByName(spellName)
                             -- TargetLastTarget() -- Restore target immediately?
                             -- Or wait for cast? Macro style "Cast; TargetLastTarget" usually works.
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
