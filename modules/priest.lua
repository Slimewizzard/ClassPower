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
Priest.BuffTimers = {} -- Legacy, replaced by BuffTimestamps
Priest.BuffTimestamps = {} -- Stores GetTime() when buffs are first seen
Priest.RankInfo = {}

-- Estimated durations (seconds)
Priest.BuffDurations = {
    Fortitude = 1800,       -- 30 min
    PrayerFort = 3600,      -- 60 min
    Spirit = 1800,          -- 30 min
    PrayerSpirit = 3600,    -- 60 min
    Shadow = 600,           -- 10 min
    PrayerShadow = 1200,    -- 20 min
    Proclaim = 7200,        -- 2 hours
    Grace = 1800,           -- 30 min
    Empower = 600,          -- 10 min
    Revive = 0,             -- Instant
    Enlighten = 1800,       -- 30 min (guess)
}

function Priest:GetEstimatedTimeRemaining(playerName, buffType)
    if not self.BuffTimestamps[playerName] then return nil end
    local tsData = self.BuffTimestamps[playerName][buffType]
    if not tsData then return nil end
    
    local startTime = 0
    local isPrayer = false
    
    if type(tsData) == "table" then
        startTime = tsData.start
        isPrayer = tsData.isPrayer
    else
        startTime = tsData
    end
    
    local duration = self.BuffDurations[buffType] or 1800
    
    if isPrayer then
        if buffType == "Fortitude" then duration = self.BuffDurations.PrayerFort end
        if buffType == "Spirit" then duration = self.BuffDurations.PrayerSpirit end
        if buffType == "Shadow" then duration = self.BuffDurations.PrayerShadow end
    end
    
    local elapsed = GetTime() - startTime
    local remaining = duration - elapsed
    
    if remaining < 0 then remaining = 0 end
    return remaining
end

function Priest:GetGroupMinTimeRemaining(groupId, buffType)
    local minTime = nil
    
    if not self.CurrentBuffs[groupId] then return nil end
    
    for _, member in self.CurrentBuffs[groupId] do
        if not member.dead then
            local remaining = self:GetEstimatedTimeRemaining(member.name, buffType)
            if remaining then
                if not minTime or remaining < minTime then
                    minTime = remaining
                end
            end
        end
    end
    
    return minTime
end

-- Timers
Priest.UpdateTimer = 0
Priest.LastRequest = 0
Priest.RosterDirty = false
Priest.RosterTimer = 0.5
Priest.UIDirty = false  -- New: only update UI when data changed

-- Distributed Scanning
Priest.ScanIndex = 1
Priest.ScanStepSize = 5
Priest.ScanFrequency = 0.1 -- Process batch every 0.1s
Priest.ScanTimer = 0

-- Context for dropdowns
Priest.ContextName = nil
Priest.AssignMode = "Champ"

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Priest:OnLoad()
    CP_Debug("Priest:OnLoad()")
    
    -- Load saved assignments first
    self:LoadAssignments()
    
    -- Migrate old saved variables if they exist (fallback compatibility)
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
    if event == "SPELLS_CHANGED" then
        -- Only scan spells when they actually change
        self:ScanSpells()
        self.UIDirty = true
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ScanSpells()
        self:ScanRaid()
        self:RequestSync()
        self.UIDirty = true
        
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        if event == "RAID_ROSTER_UPDATE" then
            self.RosterDirty = true
            self.RosterTimer = 0.5
        else
            self:ScanRaid()
            self.UIDirty = true
        end
        
        -- Update button visibility when roster/rank changes
        self:UpdateLeaderButtons()
        
        if event == "RAID_ROSTER_UPDATE" then
            if GetTime() - self.LastRequest > 5 then
                self:RequestSync()
                self.LastRequest = GetTime()
            end
        end
        
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
        -- Mark dirty so next scan picks up the change
        self.UIDirty = true
    end
end

function Priest:OnUpdate(elapsed)
    if not elapsed then elapsed = 0.01 end
    
    -- Delayed roster scan (after raid roster changes)
    if self.RosterDirty then
        self.RosterTimer = self.RosterTimer - elapsed
        if self.RosterTimer <= 0 then
            self.RosterDirty = false
            self.RosterTimer = 0.5
            self:ScanRaid()
            self.UIDirty = true
        end
    end
    
    -- UI refresh (1s interval if timers shown, else 5s)
    self.UpdateTimer = self.UpdateTimer - elapsed
    if self.UpdateTimer <= 0 then
        local displayMode = CP_PerUser.BuffDisplayMode
        if displayMode == "always" or displayMode == "timer" then
            self.UpdateTimer = 1.0
        else
            self.UpdateTimer = 5.0
        end
        
        -- Only scan and update if UI is visible
        local needsScan = false
        if self.BuffBar and self.BuffBar:IsVisible() then
            needsScan = true
        end
        if self.ConfigWindow and self.ConfigWindow:IsVisible() then
            needsScan = true
        end
        
        if needsScan then
            self:ScanRaid()
            self:UpdateUI()
        end
    -- Also update immediately if dirty flag is set and UI is visible
    elseif self.UIDirty then
        self.UIDirty = false
        if (self.BuffBar and self.BuffBar:IsVisible()) or 
           (self.ConfigWindow and self.ConfigWindow:IsVisible()) then
            self:UpdateUI()
        end
    end
    
    -- Background distributed scanning
    self.ScanTimer = self.ScanTimer - elapsed
    if self.ScanTimer <= 0 then
        self.ScanTimer = self.ScanFrequency
        self:ScanStep()
    end
end

function Priest:OnUnitUpdate(unit, name, event)
    if not name then return end
    
    if event == "UNIT_AURA" then
        -- Only trigger a partial scan for this unit
        self:ScanUnit(unit, name)
        self.UIDirty = true
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

-- Show config window (called by admin panel)
function Priest:ShowConfig()
    if not self.ConfigWindow then
        self:CreateConfigWindow()
    end
    -- Request fresh sync and scan when opened via admin
    self:ScanRaid()
    self:RequestSync()
    self.ConfigWindow:Show()
    self:UpdateConfigGrid()
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

function Priest:ScanUnit(unit, name)
    if not unit or not name then return end
    
    local subgroup = 1
    local class = nil
    
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local rname, _, rsub, _, _, rclass = GetRaidRosterInfo(i)
            if rname == name then
                subgroup = rsub
                class = rclass
                break
            end
        end
    else
        _, class = UnitClass(unit)
    end
    
    if class == "PRIEST" then
        self.AllPriests[name] = self.AllPriests[name] or {
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
            
            -- Fortitude
            if string.find(bname, "wordfortitude") then 
                buffInfo.hasFort = true
                buffInfo.isPrayerFort = false 
            elseif string.find(bname, "prayeroffortitude") then 
                buffInfo.hasFort = true 
                buffInfo.isPrayerFort = true 
            end
            
            -- Spirit
            if string.find(bname, "divinespirit") then 
                buffInfo.hasSpirit = true
                buffInfo.isPrayerSpirit = false
            elseif string.find(bname, "prayerofspirit") then 
                buffInfo.hasSpirit = true
                buffInfo.isPrayerSpirit = true 
            elseif string.find(bname, "inspiration") then
                 buffInfo.hasSpirit = true
            end

            -- Shadow Protection
            if string.find(bname, "antishadow") then
                buffInfo.hasShadow = true
                buffInfo.isPrayerShadow = false
            elseif string.find(bname, "prayerofshadowprotection") then
                buffInfo.hasShadow = true
                buffInfo.isPrayerShadow = true
            end
            
            if string.find(bname, "proclaimchampion") or string.find(bname, "holychampion") then buffInfo.hasProclaim = true end
            if string.find(bname, "championsgrace") then buffInfo.hasGrace = true end
            if string.find(bname, "empowerchampion") then buffInfo.hasEmpower = true end
            if string.find(bname, "btnholyscriptures") or string.find(bname, "enlighten") then buffInfo.hasEnlighten = true end
            
            b = b + 1
        end
        
        -- Update timestamps
        if not self.BuffTimestamps[name] then self.BuffTimestamps[name] = {} end
        local ts = self.BuffTimestamps[name]
        
        local function UpdateTS(key, hasBuff, isPrayer)
            if hasBuff then
                local now = GetTime()
                if not ts[key] then 
                    ts[key] = { start = now, isPrayer = isPrayer }
                elseif type(ts[key]) == "number" then
                    ts[key] = { start = ts[key], isPrayer = isPrayer }
                elseif ts[key].isPrayer ~= isPrayer then
                    ts[key] = { start = now, isPrayer = isPrayer }
                end
            else
                ts[key] = nil
            end
        end
        
        if UnitIsVisible(unit) then
            UpdateTS("Fortitude", buffInfo.hasFort, buffInfo.isPrayerFort)
            UpdateTS("Spirit", buffInfo.hasSpirit, buffInfo.isPrayerSpirit)
            UpdateTS("Shadow", buffInfo.hasShadow, buffInfo.isPrayerShadow)
            UpdateTS("Proclaim", buffInfo.hasProclaim)
            UpdateTS("Grace", buffInfo.hasGrace)
            UpdateTS("Empower", buffInfo.hasEmpower)
            UpdateTS("Enlighten", buffInfo.hasEnlighten)
        end
        
        -- Update the specific entry in CurrentBuffs
        self.CurrentBuffs[subgroup] = self.CurrentBuffs[subgroup] or {}
        local found = false
        for i, m in ipairs(self.CurrentBuffs[subgroup]) do
            if m.name == name then
                self.CurrentBuffs[subgroup][i] = buffInfo
                found = true
                break
            end
        end
        if not found then
            table.insert(self.CurrentBuffs[subgroup], buffInfo)
        end
        self.CurrentBuffsByName[name] = buffInfo
    end
end

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
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            self:ScanUnit("raid"..i, name)
            if class == "PRIEST" then foundPriests[name] = true end
        end
    elseif numParty > 0 then
        self:ScanUnit("player", UnitName("player"))
        if UnitClass("player") == "Priest" then foundPriests[UnitName("player")] = true end
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            self:ScanUnit("party"..i, name)
            if class == "PRIEST" then foundPriests[name] = true end
        end
    else
        self:ScanUnit("player", UnitName("player"))
        if UnitClass("player") == "Priest" then foundPriests[UnitName("player")] = true end
    end
    
    -- Cleanup priests who left
    for name, _ in pairs(self.AllPriests) do
        if not foundPriests[name] then
            self.AllPriests[name] = nil
            self.Assignments[name] = nil
        end
    end
    
    self.ScanIndex = 1
end

function Priest:ScanStep()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local count = 0
    if numRaid > 0 then
        while count < self.ScanStepSize do
            if self.ScanIndex > numRaid then self.ScanIndex = 1 end
            local name = GetRaidRosterInfo(self.ScanIndex)
            if name then
                self:ScanUnit("raid"..self.ScanIndex, name)
                count = count + 1
            end
            self.ScanIndex = self.ScanIndex + 1
            if self.ScanIndex > numRaid then break end
        end
    elseif numParty > 0 then
        if self.ScanIndex > (numParty + 1) then self.ScanIndex = 1 end
        if self.ScanIndex == 1 then
            self:ScanUnit("player", UnitName("player"))
        else
            local idx = self.ScanIndex - 1
            self:ScanUnit("party"..idx, UnitName("party"..idx))
        end
        self.ScanIndex = self.ScanIndex + 1
    end
    
    self.UIDirty = true
end

-----------------------------------------------------------------------------------
-- Auto-Assign
-----------------------------------------------------------------------------------

function Priest:AutoAssign()
    if not ClassPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Auto-assign requires Leader/Assist.")
        return
    end
    
    -- Get active groups (groups with players)
    local activeGroups = ClassPower_GetActiveGroups()
    if table.getn(activeGroups) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No groups with players found.")
        return
    end
    
    -- Get Priests with Prayer buffs for each type
    -- Buff types: 0=Fort, 1=Spirit, 2=Shadow
    -- talent = 1 means they have Prayer version
    local priestsByBuff = {
        [0] = {}, -- Priests with Prayer of Fortitude
        [1] = {}, -- Priests with Prayer of Spirit
        [2] = {}, -- Priests with Prayer of Shadow Protection
    }
    
    for priestName, info in pairs(self.AllPriests) do
        for buffType = 0, 2 do
            if info[buffType] and info[buffType].talent == 1 then
                table.insert(priestsByBuff[buffType], priestName)
            end
        end
    end
    
    -- Clear all group assignments first
    for priestName, _ in pairs(self.AllPriests) do
        self.Assignments[priestName] = self.Assignments[priestName] or {}
        for g = 1, 8 do
            self.Assignments[priestName][g] = 0
        end
    end
    
    -- Assign each buff type
    local buffNames = { [0] = "Fort", [1] = "Spirit", [2] = "Shadow" }
    local msgs = {}
    
    for buffType = 0, 2 do
        local priests = priestsByBuff[buffType]
        if table.getn(priests) > 0 then
            local assignments = ClassPower_DistributeGroups(priests, activeGroups)
            
            -- Apply assignments (bit flags: Fort=1, Spirit=2, Shadow=4)
            local bitFlag = 2 ^ buffType
            
            for priestName, groups in pairs(assignments) do
                for _, g in ipairs(groups) do
                    -- Add this buff type to existing assignment
                    local current = self.Assignments[priestName][g] or 0
                    -- Check if bit already set
                    local hasBit = (math.mod(math.floor(current / bitFlag), 2) == 1)
                    if not hasBit then
                        self.Assignments[priestName][g] = current + bitFlag
                    end
                end
            end
            
            -- Build report message
            for priestName, groups in pairs(assignments) do
                if table.getn(groups) > 0 then
                    local groupStr = ""
                    for i, g in ipairs(groups) do
                        if i > 1 then groupStr = groupStr .. "," end
                        groupStr = groupStr .. g
                    end
                    table.insert(msgs, priestName .. " " .. buffNames[buffType] .. " G" .. groupStr)
                end
            end
        end
    end
    
    -- Report what was done
    if table.getn(msgs) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Auto-assigned: " .. table.concat(msgs, " | "))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Priests with Prayer buffs found.")
    end
    
    -- Batch Sync
    for priestName, _ in pairs(self.AllPriests) do
        self:SendBatchAssignments(priestName)
    end
    
    -- Update UI
    self:SaveAssignments()
    self.UIDirty = true
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Priest:SendBatchAssignments(pname)
    if not pname then pname = UnitName("player") end
    local assigns = self.Assignments[pname] or {}
    local msg = "PRASSIGNS " .. pname
    
    for i = 1, 8 do
        msg = msg .. " " .. (assigns[i] or 0)
    end
    
    -- Add Champ and Enlighten
    local legacy = self.LegacyAssignments[pname] or {}
    msg = msg .. " " .. (legacy["Champ"] or "nil")
    msg = msg .. " " .. (legacy["Enlighten"] or "nil")
    
    ClassPower_SendMessage(msg)
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
                -- Only update if we don't have an existing non-zero value (preserves raid leader's assignments)
                local existing = self.Assignments[sender][gid]
                if not existing or existing == 0 then
                    self.Assignments[sender][gid] = tonumber(val)
                end
            end
        end
        
        self.LegacyAssignments[sender] = self.LegacyAssignments[sender] or {}
        if champ and champ ~= "" and champ ~= "nil" then
            self.LegacyAssignments[sender]["Champ"] = champ
        else
            self.LegacyAssignments[sender]["Champ"] = nil
        end
        self.UIDirty = true
    elseif string.find(msg, "^PRASSIGNS ") then
        local _, _, name, g1, g2, g3, g4, g5, g6, g7, g8, champ, enlight = string.find(msg, "^PRASSIGNS (.-) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (.-) (.*)")
        if name and g1 then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = {
                    [1] = tonumber(g1), [2] = tonumber(g2), [3] = tonumber(g3), [4] = tonumber(g4),
                    [5] = tonumber(g5), [6] = tonumber(g6), [7] = tonumber(g7), [8] = tonumber(g8)
                }
                self.LegacyAssignments[name] = self.LegacyAssignments[name] or {}
                self.LegacyAssignments[name]["Champ"] = (champ == "nil") and nil or champ
                self.LegacyAssignments[name]["Enlighten"] = (enlight == "nil") and nil or enlight
                
                self.UIDirty = true
                self:SaveAssignments()
                self:UpdateConfigGrid()
                self:UpdateBuffBar()
            end
        end
    elseif string.find(msg, "^ASSIGN ") or string.find(msg, "^PRASSIGN ") then
        local _, _, name, gid, val = string.find(msg, " (.-) (%d+) (%d+)")
        if name and gid and val then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                self.Assignments[name][tonumber(gid)] = tonumber(val)
                self.UIDirty = true
                self:SaveAssignments()
            end
        end
    elseif string.find(msg, "^ASSIGNCHAMP ") or string.find(msg, "^PRCHAMP ") then
        local _, _, name, target = string.find(msg, " (.-) (.*)")
        if name and target then
            if sender == name or ClassPower_IsPromoted(sender) then
                if target == "nil" or target == "" then target = nil end
                self.LegacyAssignments[name] = self.LegacyAssignments[name] or {}
                self.LegacyAssignments[name]["Champ"] = target
                self.UIDirty = true
                self:SaveAssignments()
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
                self.UIDirty = true
                self:SaveAssignments()
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
        if arg1 == "RightButton" then
            -- Right-click opens config
            if Priest.ConfigWindow then
                if Priest.ConfigWindow:IsVisible() then
                    Priest.ConfigWindow:Hide()
                else
                    Priest.ConfigWindow:Show()
                    Priest:UpdateConfigGrid()
                end
            end
        else
            Priest:SaveBuffBarPosition()
        end
    end)
    
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Priest:SaveBuffBarPosition()
    end)
    
    for i = 1, 10 do
        local row = self:CreateHUDRow(f, "ClassPowerHUDRow"..i, i)
        row:Hide()
    end
    
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
    
    if id <= 8 then
        local fort = CP_CreateHUDButton(f, name.."Fort")
        fort:SetPoint("LEFT", f, "LEFT", 40, 0)
        fort:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local spirit = CP_CreateHUDButton(f, name.."Spirit")
        spirit:SetPoint("LEFT", fort, "RIGHT", 50, 0)
        spirit:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local shadow = CP_CreateHUDButton(f, name.."Shadow")
        shadow:SetPoint("LEFT", spirit, "RIGHT", 50, 0)
        shadow:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
    end
    
    if id == 9 then
        local proc = CP_CreateHUDButton(f, name.."Proclaim")
        proc:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(proc:GetName().."Icon"):SetTexture(self.ChampionIcons["Proclaim"])
        proc:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local grace = CP_CreateHUDButton(f, name.."Grace")
        grace:SetPoint("LEFT", proc, "RIGHT", 50, 0)
        getglobal(grace:GetName().."Icon"):SetTexture(self.ChampionIcons["Grace"])
        grace:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local emp = CP_CreateHUDButton(f, name.."Empower")
        emp:SetPoint("LEFT", grace, "RIGHT", 50, 0)
        getglobal(emp:GetName().."Icon"):SetTexture(self.ChampionIcons["Empower"])
        emp:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
        
        local rev = CP_CreateHUDButton(f, name.."Revive")
        rev:SetPoint("LEFT", emp, "RIGHT", 50, 0)
        getglobal(rev:GetName().."Icon"):SetTexture(self.ChampionIcons["Revive"])
        rev:SetScript("OnClick", function() Priest:BuffButton_OnClick(this) end)
    end
    
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
    
    local maxRowWidth = 145 -- Minimum width
    local lastRow = nil
    
    local displayMode = CP_PerUser.BuffDisplayMode or "missing"
    local thresholdSeconds = ((CP_PerUser.TimerThresholdMinutes or 5) * 60) + (CP_PerUser.TimerThresholdSeconds or 0)
    
    local ROW_BASE_X = {40, 108, 176, 244} -- X positions for buttons 1, 2, 3, 4
    
    for i = 1, 10 do
        local row = getglobal("ClassPowerHUDRow"..i)
        if not row then break end
        
        local showRow = false
        local currentRowWidth = 0
        
        -- Helper to check buttons
        local function CheckButton(btn, idx, missingCount, totalCount, minTime, label)
            if not btn then return false end
            
            local shouldShow = false
            if displayMode == "always" then
                shouldShow = (totalCount > 0)
            elseif displayMode == "timer" then
                if missingCount > 0 then
                    shouldShow = true
                elseif minTime and minTime <= thresholdSeconds then
                    shouldShow = true
                end
            else -- missing
                shouldShow = (totalCount > 0 and missingCount > 0)
            end
            
            if shouldShow then
                btn:Show()
                local txt = getglobal(btn:GetName().."Text")
                local icon = getglobal(btn:GetName().."Icon")
                
                -- Display format
                if displayMode == "always" or displayMode == "timer" then
                    if minTime and minTime > 0 and missingCount == 0 then
                         txt:SetText(CP_FormatTime(minTime))
                         txt:SetTextColor(0, 1, 0)
                    elseif missingCount > 0 then
                        if minTime and minTime > 0 then
                            txt:SetText(missingCount.." ("..CP_FormatTime(minTime)..")")
                        else
                             txt:SetText(missingCount.."/"..totalCount) -- Shortened for space
                        end
                        txt:SetTextColor(1, 0, 0)
                    else
                         txt:SetText(totalCount.."/"..totalCount)
                         txt:SetTextColor(0, 1, 0)
                    end
                else
                    txt:SetText((totalCount-missingCount).."/"..totalCount)
                    txt:SetTextColor(1, 0, 0)
                end
                
                local btnWidth = ROW_BASE_X[idx] + 25 + txt:GetStringWidth()
                if btnWidth > currentRowWidth then currentRowWidth = btnWidth end
                return true
            else
                btn:Hide()
                return false
            end
        end
        
        if i == 9 then
            -- Champion Row
            local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Champ"]
            if target then
                local status = self.CurrentBuffsByName[target]
                
                -- Dead check
                local isDead = (status and status.dead)
                local btnR = getglobal(row:GetName().."Revive")
                if isDead then
                     btnR:Show()
                     btnR.tooltipText = "Champion: "..target.." (DEAD)"
                     currentRowWidth = ROW_BASE_X[4] + 25
                     showRow = true
                else
                     btnR:Hide()
                     
                     -- Proclaim (Btn 1)
                     local hasProclaim = status and status.hasProclaim
                     local timeProclaim = self:GetEstimatedTimeRemaining(target, "Proclaim")
                     local btnP = getglobal(row:GetName().."Proclaim")
                     local showP = CheckButton(btnP, 1, hasProclaim and 0 or 1, 1, timeProclaim, "Proclaim")
                     if showP then btnP.tooltipText = "Proclaim: "..target end
                     
                     -- Grace (Btn 2)
                     local hasGrace = status and status.hasGrace
                     local timeGrace = self:GetEstimatedTimeRemaining(target, "Grace")
                     local btnG = getglobal(row:GetName().."Grace")
                     local showG = CheckButton(btnG, 2, hasGrace and 0 or 1, 1, timeGrace, "Grace")
                     if showG then btnG.tooltipText = "Grace: "..target end
                     
                     -- Empower (Btn 3)
                     local hasEmpower = status and status.hasEmpower
                     local timeEmpower = self:GetEstimatedTimeRemaining(target, "Empower")
                     local btnE = getglobal(row:GetName().."Empower")
                     local showE = CheckButton(btnE, 3, hasEmpower and 0 or 1, 1, timeEmpower, "Empower")
                     if showE then btnE.tooltipText = "Empower: "..target end
                     
                     showRow = showP or showG or showE
                end
            end
            
        elseif i == 10 then
            -- Enlighten Row (Btn 1)
            local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Enlighten"]
            if target then
                local status = self.CurrentBuffsByName[target]
                local hasEnlighten = status and status.hasEnlighten
                local timeEnlighten = self:GetEstimatedTimeRemaining(target, "Enlighten")
                local btnEn = getglobal(row:GetName().."Enlighten")
                
                showRow = CheckButton(btnEn, 1, hasEnlighten and 0 or 1, 1, timeEnlighten, "Enlighten")
                if showRow then btnEn.tooltipText = "Enlighten: "..target end
            end
            
        elseif assigns and assigns[i] and assigns[i] > 0 then
            -- Group Rows
            local val = assigns[i]
            local fS = math.mod(val, 2)
            local sS = math.mod(math.floor(val/2), 2)
            local shS = math.mod(math.floor(val/4), 2)
            
            local function GetStats(buffKey, buffType)
                 local missing = 0
                 local total = 0
                 if self.CurrentBuffs[i] then
                     for _, m in self.CurrentBuffs[i] do
                         total = total + 1
                         if not m[buffKey] and not m.dead then missing = missing + 1 end
                     end
                 end
                 local minTime = self:GetGroupMinTimeRemaining(i, buffType)
                 return missing, total, minTime
            end
            
            -- Fort (Btn 1)
            if fS > 0 then
                local missing, total, minTime = GetStats("hasFort", "Fortitude")
                local btn = getglobal(row:GetName().."Fort")
                if CheckButton(btn, 1, missing, total, minTime, "Fortitude") then
                    showRow = true
                    btn.tooltipText = "Group "..i..": Fortitude"
                    local icon = getglobal(btn:GetName().."Icon")
                    icon:SetTexture(self.BuffIconsGroup[0])
                end
            else
                getglobal(row:GetName().."Fort"):Hide()
            end
            
            -- Spirit (Btn 2)
            if sS > 0 then
                local missing, total, minTime = GetStats("hasSpirit", "Spirit")
                local btn = getglobal(row:GetName().."Spirit")
                if CheckButton(btn, 2, missing, total, minTime, "Spirit") then
                    showRow = true
                    btn.tooltipText = "Group "..i..": Spirit"
                    local icon = getglobal(btn:GetName().."Icon")
                    icon:SetTexture(self.BuffIconsGroup[1])
                end
            else
                 getglobal(row:GetName().."Spirit"):Hide()
            end
            
            -- Shadow (Btn 3)
            if shS > 0 then
                local missing, total, minTime = GetStats("hasShadow", "Shadow")
                local btn = getglobal(row:GetName().."Shadow")
                if CheckButton(btn, 3, missing, total, minTime, "Shadow") then
                    showRow = true
                    btn.tooltipText = "Group "..i..": Shadow"
                    local icon = getglobal(btn:GetName().."Icon")
                    icon:SetTexture(self.BuffIconsGroup[2])
                end
             else
                 getglobal(row:GetName().."Shadow"):Hide()
             end
        end
        
        if showRow then
            row:Show()
            row:ClearAllPoints()
            if lastRow then
                row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -20)
            end
            lastRow = row
            if currentRowWidth > maxRowWidth then maxRowWidth = currentRowWidth end
        else
            row:Hide()
        end
    end
    
    -- Optimize size updates
    local newHeight = 25
    if lastRow then
        newHeight = (lastRow:GetBottom() and (f:GetTop() - lastRow:GetBottom()) or 40) + 5
    end
    
    if math.abs(f:GetWidth() - maxRowWidth) > 1 then
        f:SetWidth(maxRowWidth)
    end
    if math.abs(f:GetHeight() - newHeight) > 1 then
        f:SetHeight(newHeight)
    end
end

-----------------------------------------------------------------------------------
-- UI: Config Window
-----------------------------------------------------------------------------------

function Priest:CreateConfigWindow()
    if getglobal("ClassPowerPriestConfig") then 
        self.ConfigWindow = getglobal("ClassPowerPriestConfig")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerPriestConfig", UIParent)
    f:SetWidth(920)
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
    title:SetText("ClassPower - Priest Configuration")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Scale Handle (bottom-right corner)
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
        CP_PerUser.ConfigScale = p:GetScale()
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
    
    local lblPriest = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblPriest:SetPoint("TOPLEFT", f, "TOPLEFT", 25, headerY)
    lblPriest:SetText("Priest")
    
    local lblCaps = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblCaps:SetPoint("TOPLEFT", f, "TOPLEFT", 90, headerY)
    lblCaps:SetText("Spells")
    
    for g = 1, 8 do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 210 + (g-1)*68, headerY)
        lbl:SetText("G"..g)
    end
    
    local lblChamp = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblChamp:SetPoint("TOPLEFT", f, "TOPLEFT", 765, headerY)
    lblChamp:SetText("Champ")
    
    local lblEnlight = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblEnlight:SetPoint("TOPLEFT", f, "TOPLEFT", 835, headerY)
    lblEnlight:SetText("Enlt")
    
    for i = 1, 10 do
        self:CreateConfigRow(f, i)
    end
    
    if CP_PerUser.ConfigScale then
        f:SetScale(CP_PerUser.ConfigScale)
    else
        f:SetScale(1.0)
    end
    
    -- Add Settings button
    local btnSettings = CreateFrame("Button", "CPPriestSettingsBtn", f, "UIPanelButtonTemplate")
    btnSettings:SetWidth(100)
    btnSettings:SetHeight(24)
    btnSettings:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 15)
    btnSettings:SetText("Settings...")
    btnSettings:SetScript("OnClick", function()
        CP_ShowSettingsPanel()
    end)
    
    -- Auto-Assign button (only visible for leaders/assists)
    local autoBtn = CreateFrame("Button", f:GetName().."AutoAssignBtn", f, "UIPanelButtonTemplate")
    autoBtn:SetWidth(90)
    autoBtn:SetHeight(24)
    autoBtn:SetPoint("LEFT", btnSettings, "RIGHT", 10, 0)
    autoBtn:SetText("Auto-Assign")
    autoBtn:SetScript("OnClick", function()
        Priest:AutoAssign()
    end)
    autoBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Assign Groups")
        GameTooltip:AddLine("Automatically distribute groups", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("among Priests with Prayer buffs.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Requires Leader/Assist", 1, 0.5, 0)
        GameTooltip:Show()
    end)
    autoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Close Module Button (for admin usage)
    local closeModBtn = CreateFrame("Button", f:GetName().."CloseModuleBtn", f, "UIPanelButtonTemplate")
    closeModBtn:SetWidth(90)
    closeModBtn:SetHeight(24)
    closeModBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 15)
    closeModBtn:SetText("Close Module")
    closeModBtn:SetScript("OnClick", function()
        ClassPower:CloseModule("PRIEST")
    end)
    closeModBtn:Hide()

    -- Update visibility based on promotion status
    f:SetScript("OnShow", function()
        local autoAssignBtn = getglobal(this:GetName().."AutoAssignBtn")
        if autoAssignBtn then
            if ClassPower_IsPromoted() then
                autoAssignBtn:Show()
            else
                autoAssignBtn:Hide()
            end
        end
        
        -- Close Module Visibility (only if not player class)
        local closeBtn = getglobal(this:GetName().."CloseModuleBtn")
        if closeBtn then
            if UnitClass("player") ~= "Priest" then
                closeBtn:Show()
            else
                closeBtn:Hide()
            end
        end
    end)
    
    f:Hide()
    self.ConfigWindow = f
end

function Priest:CreateConfigRow(parent, rowIndex)
    local rowName = "CPPriestRow"..rowIndex
    local row = CreateFrame("Frame", rowName, parent)
    row:SetWidth(880)
    row:SetHeight(44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -65 - (rowIndex-1)*46)
    
    local clearBtn = CP_CreateClearButton(row, rowName.."Clear")
    clearBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    clearBtn:SetScript("OnClick", function() Priest:ClearButton_OnClick(this) end)
    
    local nameStr = row:CreateFontString(rowName.."Name", "OVERLAY", "GameFontHighlight")
    nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 15, -14)
    nameStr:SetWidth(65)
    nameStr:SetHeight(16)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("")
    
    local caps = CreateFrame("Frame", rowName.."Caps", row)
    caps:SetWidth(115)
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
    
    CreateCapIcon("Fort", 0)
    CreateCapIcon("Spirit", 16)
    CreateCapIcon("Shadow", 32)
    CreateCapIcon("Proclaim", 52)
    CreateCapIcon("Grace", 68)
    CreateCapIcon("Empower", 84)
    CreateCapIcon("Revive", 100)
    
    for g = 1, 8 do
        local grpFrame = CreateFrame("Frame", rowName.."Group"..g, row)
        grpFrame:SetWidth(64)
        grpFrame:SetHeight(42)
        grpFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 195 + (g-1)*68, 0)
        grpFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        grpFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        local btnFort = CreateFrame("Button", rowName.."Group"..g.."Fort", grpFrame)
        btnFort:SetWidth(20); btnFort:SetHeight(20)
        btnFort:SetPoint("LEFT", grpFrame, "LEFT", 2, 0)
        local fortBg = btnFort:CreateTexture(btnFort:GetName().."Background", "BACKGROUND")
        fortBg:SetAllPoints(btnFort); fortBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local fortIcon = btnFort:CreateTexture(btnFort:GetName().."Icon", "OVERLAY")
        fortIcon:SetWidth(18); fortIcon:SetHeight(18); fortIcon:SetPoint("CENTER", btnFort, "CENTER", 0, 0)
        local fortTxt = btnFort:CreateFontString(btnFort:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        fortTxt:SetPoint("BOTTOM", btnFort, "BOTTOM", 0, -10); fortTxt:SetJustifyH("CENTER")
        btnFort:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnFort:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnFort:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnFort:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        local btnSpirit = CreateFrame("Button", rowName.."Group"..g.."Spirit", grpFrame)
        btnSpirit:SetWidth(20); btnSpirit:SetHeight(20)
        btnSpirit:SetPoint("LEFT", btnFort, "RIGHT", 1, 0)
        local spiritBg = btnSpirit:CreateTexture(btnSpirit:GetName().."Background", "BACKGROUND")
        spiritBg:SetAllPoints(btnSpirit); spiritBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local spiritIcon = btnSpirit:CreateTexture(btnSpirit:GetName().."Icon", "OVERLAY")
        spiritIcon:SetWidth(18); spiritIcon:SetHeight(18); spiritIcon:SetPoint("CENTER", btnSpirit, "CENTER", 0, 0)
        local spiritTxt = btnSpirit:CreateFontString(btnSpirit:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        spiritTxt:SetPoint("BOTTOM", btnSpirit, "BOTTOM", 0, -10); spiritTxt:SetJustifyH("CENTER")
        btnSpirit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnSpirit:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnSpirit:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnSpirit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        local btnShadow = CreateFrame("Button", rowName.."Group"..g.."Shadow", grpFrame)
        btnShadow:SetWidth(20); btnShadow:SetHeight(20)
        btnShadow:SetPoint("LEFT", btnSpirit, "RIGHT", 1, 0)
        local shadowBg = btnShadow:CreateTexture(btnShadow:GetName().."Background", "BACKGROUND")
        shadowBg:SetAllPoints(btnShadow); shadowBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local shadowIcon = btnShadow:CreateTexture(btnShadow:GetName().."Icon", "OVERLAY")
        shadowIcon:SetWidth(18); shadowIcon:SetHeight(18); shadowIcon:SetPoint("CENTER", btnShadow, "CENTER", 0, 0)
        local shadowTxt = btnShadow:CreateFontString(btnShadow:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        shadowTxt:SetPoint("BOTTOM", btnShadow, "BOTTOM", 0, -10); shadowTxt:SetJustifyH("CENTER")
        btnShadow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnShadow:SetScript("OnClick", function() Priest:SubButton_OnClick(this) end)
        btnShadow:SetScript("OnEnter", function() Priest:SubButton_OnEnter(this) end)
        btnShadow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    local champBtn = CreateFrame("Button", rowName.."Champ", row)
    champBtn:SetWidth(24); champBtn:SetHeight(24)
    champBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 750, -8)
    local champBg = champBtn:CreateTexture(champBtn:GetName().."Background", "BACKGROUND")
    champBg:SetAllPoints(champBtn); champBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    local champIcon = champBtn:CreateTexture(champBtn:GetName().."Icon", "OVERLAY")
    champIcon:SetWidth(22); champIcon:SetHeight(22); champIcon:SetPoint("CENTER", champBtn, "CENTER", 0, 0)
    local champTxt = champBtn:CreateFontString(champBtn:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
    champTxt:SetPoint("CENTER", champBtn, "CENTER", 0, 0)
    champBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    champBtn:SetScript("OnClick", function() Priest:ChampButton_OnClick(this) end)
    champBtn:SetScript("OnEnter", function() Priest:ChampButton_OnEnter(this) end)
    champBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local champName = row:CreateFontString(rowName.."ChampName", "OVERLAY", "GameFontHighlightSmall")
    champName:SetPoint("TOP", champBtn, "BOTTOM", 0, -2)
    champName:SetWidth(50)
    champName:SetText("")
    
    local enlightBtn = CreateFrame("Button", rowName.."Enlighten", row)
    enlightBtn:SetWidth(24); enlightBtn:SetHeight(24)
    enlightBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 820, -8)
    local enlightBg = enlightBtn:CreateTexture(enlightBtn:GetName().."Background", "BACKGROUND")
    enlightBg:SetAllPoints(enlightBtn); enlightBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    local enlightIcon = enlightBtn:CreateTexture(enlightBtn:GetName().."Icon", "OVERLAY")
    enlightIcon:SetWidth(22); enlightIcon:SetHeight(22); enlightIcon:SetPoint("CENTER", enlightBtn, "CENTER", 0, 0)
    local enlightTxt = enlightBtn:CreateFontString(enlightBtn:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
    enlightTxt:SetPoint("CENTER", enlightBtn, "CENTER", 0, 0)
    enlightBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    enlightBtn:SetScript("OnClick", function() Priest:EnlightenButton_OnClick(this) end)
    enlightBtn:SetScript("OnEnter", function() Priest:EnlightenButton_OnEnter(this) end)
    enlightBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local enlightName = row:CreateFontString(rowName.."EnlightenName", "OVERLAY", "GameFontHighlightSmall")
    enlightName:SetPoint("TOP", enlightBtn, "BOTTOM", 0, -2)
    enlightName:SetWidth(50)
    enlightName:SetText("")
    
    row:Hide()
    return row
end

-----------------------------------------------------------------------------------
-- Config Grid Updates
-----------------------------------------------------------------------------------

function Priest:UpdateConfigGrid()
    if not self.ConfigWindow then return end
    
    local rowIndex = 1
    for priestName, info in pairs(self.AllPriests) do
        if rowIndex > 10 then break end
        
        local row = getglobal("CPPriestRow"..rowIndex)
        if row then
            row:Show()
            
            local nameStr = getglobal("CPPriestRow"..rowIndex.."Name")
            if nameStr then 
                local displayName = priestName
                if string.len(priestName) > 10 then
                    displayName = string.sub(priestName, 1, 9)..".."
                end
                nameStr:SetText(displayName) 
            end
            
            local clearBtn = getglobal("CPPriestRow"..rowIndex.."Clear")
            if clearBtn then
                if ClassPower_IsPromoted() or priestName == UnitName("player") then
                    clearBtn:Show()
                else
                    clearBtn:Hide()
                end
            end
            
            self:UpdateCapabilityIcons(rowIndex, priestName, info)
            self:UpdateGroupButtons(rowIndex, priestName)
            self:UpdateChampButton(rowIndex, priestName)
            self:UpdateEnlightenButton(rowIndex, priestName)
        end
        rowIndex = rowIndex + 1
    end
    
    for i = rowIndex, 10 do
        local row = getglobal("CPPriestRow"..i)
        if row then row:Hide() end
    end
    
    local newHeight = 80 + (rowIndex - 1) * 46 + 40 -- +40 for Settings button
    if newHeight < 180 then newHeight = 180 end
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
    
    local fortInfo = info[0] or { rank = 0, talent = 0 }
    SetIcon("Fort", self.BuffIcons[0], fortInfo.rank > 0, "Fortitude R"..fortInfo.rank..(fortInfo.talent > 0 and " (Prayer)" or ""))
    
    local spiritInfo = info[1] or { rank = 0, talent = 0 }
    SetIcon("Spirit", self.BuffIcons[1], spiritInfo.rank > 0, "Spirit R"..spiritInfo.rank..(spiritInfo.talent > 0 and " (Prayer)" or ""))
    
    local shadowInfo = info[2] or { rank = 0, talent = 0 }
    SetIcon("Shadow", self.BuffIcons[2], shadowInfo.rank > 0, "Shadow R"..shadowInfo.rank..(shadowInfo.talent > 0 and " (Prayer)" or ""))
    
    SetIcon("Proclaim", self.ChampionIcons["Proclaim"], info["Proclaim"], "Proclaim Champion")
    SetIcon("Grace", self.ChampionIcons["Grace"], info["Grace"], "Champion's Grace")
    SetIcon("Empower", self.ChampionIcons["Empower"], info["Empower"], "Empower Champion")
    SetIcon("Revive", self.ChampionIcons["Revive"], info["Revive"], "Revive Champion")
end

function Priest:UpdateGroupButtons(rowIndex, priestName)
    local assigns = self.Assignments[priestName] or {}
    
    for g = 1, 8 do
        local val = assigns[g] or 0
        -- Decode states (1=Fort, 2=Spirit, 4=Shadow)
        local fState = math.mod(val, 2)
        local sState = math.mod(math.floor(val/2), 2)
        local shState = math.mod(math.floor(val/4), 2)
        
        local prefix = "CPPriestRow"..rowIndex.."Group"..g
        
        local function UpdateBtn(suffix, state, typeIdx, buffKey)
            local btn = getglobal(prefix..suffix)
            if not btn then return end
            local icon = getglobal(btn:GetName().."Icon")
            local text = getglobal(btn:GetName().."Text")
            
            if state > 0 then
                -- Assigned - always show group icon (Prayer buff)
                icon:SetTexture(self.BuffIconsGroup[typeIdx])
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
        if nameLabel then nameLabel:SetText(string.sub(target, 1, 8)) end
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
        if nameLabel then nameLabel:SetText(string.sub(target, 1, 8)) end
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

function Priest:BuffButton_OnClick(btn)
    local name = btn:GetName()
    local _, _, rowStr, suffix = string.find(name, "ClassPowerHUDRow(%d+)(.*)")
    if not rowStr then return end
    
    local i = tonumber(rowStr)
    local pname = UnitName("player")
    
    if i == 9 then
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
                if member.visible and not member.dead then
                     -- Logic:
                     -- Left-click (Group): Cast on ANYONE in range (Refresh)
                     -- Right-click (Single): Cast on MISSING person (Smart Fill)
                     
                     local shouldCast = false
                     if isRightClick then
                         if not member[buffKey] then shouldCast = true end
                     else
                         shouldCast = true -- Always try to cast group buff if button clicked
                     end
                     
                     if shouldCast then
                        ClearTarget()
                        TargetByName(member.name, true)
                        if UnitExists("target") and UnitName("target") == member.name then
                            if CheckInteractDistance("target", 4) then
                                CastSpellByName(spellName)
                                
                                -- If group buff, reset timestamps for everyone in group
                                if not isRightClick then
                                    local buffNameMap = {
                                        ["hasFort"] = "Fortitude",
                                        ["hasSpirit"] = "Spirit",
                                        ["hasShadow"] = "Shadow"
                                    }
                                    local bName = buffNameMap[buffKey]
                                    if bName then
                                        for _, m in self.CurrentBuffs[gid] do
                                            if self.BuffTimestamps[m.name] then
                                                self.BuffTimestamps[m.name][bName] = GetTime()
                                            end
                                        end
                                    end
                                end
                                
                                TargetLastTarget()
                                self:ScanRaid()
                                self:UpdateBuffBar()
                                return
                            else
                                TargetLastTarget() -- Out of range
                            end
                        else
                            TargetLastTarget() -- Could not target
                        end
                     end
                end
            end
            if isRightClick then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No targets missing buff in Group "..gid)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No targets in range for Group "..gid)
            end
            TargetLastTarget()
        end
    end
end

function Priest:ClearButton_OnClick(btn)
    local rowName = btn:GetParent():GetName()
    local _, _, rowIdx = string.find(rowName, "CPPriestRow(%d+)")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Permission denied.")
        return
    end
    
    self.Assignments[priestName] = {}
    self.LegacyAssignments[priestName] = {}
    ClassPower_SendMessage("CLEAR "..priestName)
    self:SaveAssignments()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared assignments for "..priestName)
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Priest:SubButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx, grpIdx, buffType = string.find(btnName, "CPPriestRow(%d+)Group(%d+)(.*)")
    if not rowIdx or not grpIdx or not buffType then return end
    
    rowIdx = tonumber(rowIdx)
    grpIdx = tonumber(grpIdx)
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
    if not ClassPower_IsPromoted() and priestName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.Assignments[priestName] = self.Assignments[priestName] or {}
    local cur = self.Assignments[priestName][grpIdx] or 0
    
    -- Decode current states (Bits: 1=Fort, 2=Spirit, 4=Shadow)
    local f = math.mod(cur, 2)
    local s = math.mod(math.floor(cur/2), 2)
    local sh = math.mod(math.floor(cur/4), 2)
    
    -- Shift-click toggles all three buffs together
    if IsShiftKeyDown() then
        -- If any are on, turn all off; otherwise turn all on
        if f > 0 or s > 0 or sh > 0 then
            f = 0; s = 0; sh = 0
        else
            f = 1; s = 1; sh = 1
        end
    else
        -- Simple toggle for individual buff
        if buffType == "Fort" then
            f = (f > 0) and 0 or 1
        elseif buffType == "Spirit" then
            s = (s > 0) and 0 or 1
        elseif buffType == "Shadow" then
            sh = (sh > 0) and 0 or 1
        end
    end
    
    local newVal = f + (s * 2) + (sh * 4)
    self.Assignments[priestName][grpIdx] = newVal
    
    ClassPower_SendMessage("PRASSIGN " .. priestName .. " " .. grpIdx .. " " .. newVal)
    
    self:SaveAssignments()
    self.UIDirty = true
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
    GameTooltip:AddLine("Click to toggle assignment", 1, 1, 1)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("On HUD:", 1, 0.8, 0)
    GameTooltip:AddLine("Left-click: Prayer (group buff)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Single target buff", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Shift-Click: Toggle ALL buffs", 0, 1, 0)
    GameTooltip:Show()
end

function Priest:ChampButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPriestRow(%d+)Champ")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPPriestRow"..rowIdx.."Name")
    local priestName = nameStr and nameStr:GetText()
    if not priestName then return end
    
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
-- Update UI
-----------------------------------------------------------------------------------

function Priest:UpdateUI()
    self:UpdateBuffBar()
    if self.ConfigWindow and self.ConfigWindow:IsVisible() then
        self:UpdateConfigGrid()
    end
end

function Priest:UpdateLeaderButtons()
    if not self.ConfigWindow then return end
    
    local autoBtn = getglobal(self.ConfigWindow:GetName().."AutoAssignBtn")
    
    if ClassPower_IsPromoted() then
        if autoBtn then autoBtn:Show() end
    else
        if autoBtn then autoBtn:Hide() end
    end
end

function Priest:ResetUI()
    CP_PerUser.Point = nil
    CP_PerUser.RelativePoint = nil
    CP_PerUser.X = nil
    CP_PerUser.Y = nil
    CP_PerUser.Scale = 0.7
    CP_PerUser.ConfigScale = 1.0
    
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
-- Champion Dropdown
-----------------------------------------------------------------------------------

function Priest:ChampDropDown_Initialize(level)
    if not level then level = 1 end
    local info = {}
    
    if level == 1 then
        info = {}
        info.text = ">> Clear <<"
        info.value = "CLEAR"
        info.func = function() Priest:AssignTarget_OnClick() end
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
        ClassPower_SendMessage("PRCHAMP "..pname.." nil")
    else
        self.LegacyAssignments[pname][mode] = targetName
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..pname.." "..mode.." = "..targetName)
        ClassPower_SendMessage("PRCHAMP "..pname.." "..targetName)
    end
    
    self.UIDirty = true
    self:SaveAssignments()
    self:UpdateUI()
    CloseDropDownMenus()
end

-----------------------------------------------------------------------------------
-- Persistence (Save/Load Assignments)
-----------------------------------------------------------------------------------

function Priest:SaveAssignments()
    -- Save all assignments (not just current player) for convenience
    -- This allows raid leaders to set up assignments for everyone
    PriestPower_Assignments = self.Assignments
    PriestPower_LegacyAssignments = self.LegacyAssignments
    
    -- Debug output
    for pname, assigns in pairs(self.Assignments) do
        for grp, val in pairs(assigns) do
            CP_Debug("Priest Save: "..pname.." G"..grp.." = "..tostring(val))
        end
    end
    CP_Debug("Priest: Saved assignments")
end

function Priest:LoadAssignments()
    -- Load saved assignments
    if PriestPower_Assignments then
        self.Assignments = PriestPower_Assignments
        -- Debug output
        for pname, assigns in pairs(self.Assignments) do
            for grp, val in pairs(assigns) do
                CP_Debug("Priest Load: "..pname.." G"..grp.." = "..tostring(val))
            end
        end
        CP_Debug("Priest: Loaded group assignments")
    end
    if PriestPower_LegacyAssignments then
        self.LegacyAssignments = PriestPower_LegacyAssignments
        CP_Debug("Priest: Loaded champion assignments")
    end
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("PRIEST", Priest)
