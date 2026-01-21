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
    [0] = "Interface\\Icons\\Spell_Nature_Regeneration",         -- Gift of the Wild (same icon as MotW)
}

Druid.SpecialIcons = {
    ["Emerald"] = "Interface\\Icons\\Spell_Nature_ProtectionformNature",
    ["Innervate"] = "Interface\\Icons\\Spell_Nature_Lightning",
    ["Thorns"] = "Interface\\Icons\\Spell_Nature_Thorns",
}

-- Buff type constants
Druid.BUFF_MOTW = 0
Druid.BUFF_THORNS = 1

-- Buff durations in seconds (for timer calculations)
-- Using Gift of the Wild duration (60 min) since that's what's typically cast in groups
Druid.BuffDurations = {
    MotW = 1800,      -- 30 minutes (Mark)
    GotW = 3600,      -- 60 minutes (Gift)
    Thorns = 600,     -- 10 minutes
    Emerald = 1800,   -- 30 minutes (estimate)
}
-- Tooltip scanner for distinguishing Mark vs Gift
local scanTooltip = CreateFrame("GameTooltip", "ClassPowerDruidScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-----------------------------------------------------------------------------------
-- State
-----------------------------------------------------------------------------------

Druid.AllDruids = {}
Druid.CurrentBuffs = {}
Druid.CurrentBuffsByName = {}
Druid.Assignments = {}
Druid.LegacyAssignments = {}
Druid.ThornsList = {}  -- New: list of players assigned for Thorns
Druid.InnervateThreshold = {}  -- Mana % threshold for Innervate (0-100)
Druid.RankInfo = {}

-- Buff timing tracking (when we first saw a buff on someone)
Druid.BuffTimestamps = {}  -- [playerName][buffType] = GetTime() when first seen

-- Timers
Druid.UpdateTimer = 0
Druid.LastRequest = 0
Druid.RosterDirty = false
Druid.RosterTimer = 0.5
Druid.UIDirty = false  -- Only update UI when data changed

-- Distributed Scanning
Druid.ScanIndex = 1
Druid.ScanGroup = 1
Druid.ScanStepSize = 5
Druid.ScanFrequency = 0.1 -- Process batch every 0.1s
Druid.ScanTimer = 0

-- Texture Cache for deep optimization
Druid.UnitTextureCache = {}

-- Context for dropdowns
Druid.ContextName = nil
Druid.AssignMode = "Innervate"

-----------------------------------------------------------------------------------
-- Gear Scanning
-----------------------------------------------------------------------------------

function Druid:ScanGear()
    local cenarionCount = 0
    local stormrageCount = 0
    
    for i = 1, 19 do -- Scan all slots
        local link = GetInventoryItemLink("player", i)
        if link then
            local _, _, name = string.find(link, "%[(.+)%]")
            if name then
                if string.find(name, "Cenarion") then cenarionCount = cenarionCount + 1 end
                if string.find(name, "Stormrage") then stormrageCount = stormrageCount + 1 end
            end
        end
    end
    
    -- Default 10 min
    local newDuration = 600 
    
    if stormrageCount >= 3 then
        -- Turtle WoW: T2 3-set gives +100% duration (20 min)
        newDuration = 1200
    elseif cenarionCount >= 3 then
        -- T1 3-set gives +50% duration (15 min)
        newDuration = 900
    end
    
    if self.BuffDurations.Thorns ~= newDuration then
        self.BuffDurations.Thorns = newDuration
        ClassPower_Debug("Thorns duration updated to "..newDuration.."s (Cenarion: "..cenarionCount..", Stormrage: "..stormrageCount..")")
    end
end

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Druid:OnLoad()
    ClassPower_Debug("Druid:OnLoad()")
    
    -- Load saved Thorns list
    if ClassPower_PerUser.DruidThornsList then
        self.ThornsList = ClassPower_PerUser.DruidThornsList
    end
    
    -- Load saved Innervate thresholds
    if ClassPower_PerUser.DruidInnervateThreshold then
        self.InnervateThreshold = ClassPower_PerUser.DruidInnervateThreshold
    end
    
    -- Load saved group assignments and Innervate target
    self:LoadAssignments()
    
    -- Initial scans
    self:ScanSpells()
    self:ScanGear()
    self:ScanRaid()
    
    -- Create Event Frame for inventory changes
    if not self.EventFrame then
        self.EventFrame = CreateFrame("Frame")
        self.EventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self.EventFrame:SetScript("OnEvent", function()
            if event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
                Druid:ScanGear()
            end
        end)
    end
    
    -- Create UI
    self:CreateBuffBar()
    self:CreateConfigWindow()
    
    -- Create dropdown
    if not getglobal("ClassPowerDruidDropDown") then
        CreateFrame("Frame", "ClassPowerDruidDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerDruidDropDown, function(level) Druid:TargetDropDown_Initialize(level) end, "MENU")
    
    -- Request sync from other druids
    self:RequestSync()
end

function Druid:OnEvent(event)
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
    end
end

function Druid:OnUpdate(elapsed)
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
    
    -- Determine refresh interval based on display mode
    local displayMode = ClassPower_PerUser.BuffDisplayMode or "missing"
    local refreshInterval = 5.0  -- Default 5 seconds for "missing" mode
    if displayMode == "always" or displayMode == "timer" then
        refreshInterval = 1.0  -- 1 second for timer modes
    end
    
    -- Throttled UI Updates
    self.ThrottleTimer = (self.ThrottleTimer or 0) - elapsed
    if self.ThrottleTimer <= 0 then
        if self.UIDirty then
            self.UIDirty = false
            if (self.BuffBar and self.BuffBar:IsVisible()) or 
               (self.ConfigWindow and self.ConfigWindow:IsVisible()) then
                self:UpdateUI()
            end
        end
        self.ThrottleTimer = 1.0 -- Reset timer (max 1 update/sec)
    end
    
    -- UI refresh
    self.UpdateTimer = self.UpdateTimer - elapsed
    if self.UpdateTimer <= 0 then
        self.UpdateTimer = refreshInterval
        
        -- Only scan and update if UI exists (not just visible - need data to show content)
        local needsScan = false
        if self.BuffBar then
            needsScan = true
        end
        if self.ConfigWindow and self.ConfigWindow:IsVisible() then
            needsScan = true
        end
        

        if needsScan then
            self:ScanRaid()
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

function Druid:OnUnitUpdate(unit, name, event)
    if not name then return end
    
    -- Removed UNIT_AURA scanning (Polling Mode)
    
    if event == "UNIT_MANA" or event == "UNIT_MAXMANA" then
        -- Only trigger UI update if this is our Innervate target
        local pname = UnitName("player")
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Innervate"]
        if name == target then
            self.UIDirty = true
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
    elseif msg == "thorns" then
        -- Cast thorns on first person in list missing it
        local pname = UnitName("player")
        local thornsList = self.ThornsList[pname]
        if thornsList then
            for _, target in ipairs(thornsList) do
                local status = self.CurrentBuffsByName[target]
                if status and not status.hasThorns and not status.dead then
                    ClearTarget()
                    TargetByName(target, true)
                    if UnitName("target") == target then
                        CastSpellByName(self.Spells.THORNS)
                        TargetLastTarget()
                        return
                    end
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: All Thorns targets are buffed!")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Thorns targets assigned!")
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
function Druid:ShowConfig()
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

function Druid:ScanUnit(unit, name)
    if not unit or not name then return end
    
    -- Get subgroup and class if not already known
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
    
    if class == "DRUID" then
        self.AllDruids[name] = self.AllDruids[name] or {
            [0] = { rank = 0, talent = 0, name = "MotW" },
            [1] = { rank = 0, talent = 0, name = "Thorns" },
            ["Emerald"] = false,
            ["Innervate"] = false,
        }
    end

    if subgroup and subgroup >= 1 and subgroup <= 8 then
        local buffInfo = {
            name = name,
            class = class,
            visible = UnitIsVisible(unit),
            dead = UnitIsDeadOrGhost(unit),
            hasMotW = false,
            hasThorns = false,
            hasEmerald = false,
        }
        
        -- Initialize timestamp tracking for this player
        if not self.BuffTimestamps[name] then
            self.BuffTimestamps[name] = {}
        end
        
        -- Check Texture Cache
        local b = 1
        local textureHash = ""
        while true do
            local tex = UnitBuff(unit, b)
            if not tex then break end
            textureHash = textureHash .. tex
            b = b + 1
        end
        
        -- If textures haven't changed AND we have cached buff info, skip heavy scanning
        if self.UnitTextureCache[name] == textureHash then
            local prev = self.CurrentBuffsByName[name]
            if prev then
                -- Update simple flags
                prev.visible = UnitIsVisible(unit)
                prev.dead = UnitIsDeadOrGhost(unit)
                -- Add to CurrentBuffs (may have been cleared by ScanRaid)
                self.CurrentBuffs[subgroup] = self.CurrentBuffs[subgroup] or {}
                local found = false
                for i, m in ipairs(self.CurrentBuffs[subgroup]) do
                    if m.name == name then
                        self.CurrentBuffs[subgroup][i] = prev
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(self.CurrentBuffs[subgroup], prev)
                end
                return  -- Only return early if we had cached data to use
            end
            -- If prev is nil, fall through to full scan below
        end
        self.UnitTextureCache[name] = textureHash

        b = 1
        local foundTextures = ""
        while true do
            local buffTexture = UnitBuff(unit, b)
            if not buffTexture then break end
            
            buffTexture = string.lower(buffTexture)
            foundTextures = foundTextures .. buffTexture
            
            -- Mark of the Wild & Gift of the Wild both use: Spell_Nature_Regeneration
            if string.find(buffTexture, "regeneration") then 
                buffInfo.hasMotW = true
                -- Distinguish Gift vs Mark using tooltip only if something changed or timestamp missing
                if not self.BuffTimestamps[name].MotW then
                    scanTooltip:SetUnitBuff(unit, b)
                    local tipText = ClassPowerDruidScanTooltipTextLeft1:GetText()
                    local isGift = (tipText == "Gift of the Wild")
                    self.BuffTimestamps[name].MotW = GetTime()
                    self.BuffTimestamps[name].isGift = isGift
                end
            end
            
            -- Thorns: Spell_Nature_Thorns
            if string.find(buffTexture, "thorns") then 
                buffInfo.hasThorns = true
                if not self.BuffTimestamps[name].Thorns then
                    self.BuffTimestamps[name].Thorns = GetTime()
                end
            end
            
            -- Emerald Blessing: Spell_Nature_ProtectionformNature
            if string.find(buffTexture, "protectionformnature") then 
                buffInfo.hasEmerald = true
                if not self.BuffTimestamps[name].Emerald then
                    self.BuffTimestamps[name].Emerald = GetTime()
                end
            end
            
            b = b + 1
        end

        -- Texture count/content change detection for resetting timestamps
        -- (Simple version: if they don't have the buff, clear the timestamp)
        if not buffInfo.hasMotW then self.BuffTimestamps[name].MotW = nil end
        if not buffInfo.hasThorns then self.BuffTimestamps[name].Thorns = nil end
        if not buffInfo.hasEmerald then self.BuffTimestamps[name].Emerald = nil end

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

function Druid:ScanRaid()
    -- Full scan resets everything and does it all at once (for roster changes)
    self.CurrentBuffs = {}
    for i = 1, 8 do self.CurrentBuffs[i] = {} end
    self.CurrentBuffsByName = {}
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local foundDruids = {}
    

    if UnitClass("player") == "Druid" then
        foundDruids[UnitName("player")] = true
    end

    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
            self:ScanUnit("raid"..i, name)
            if class == "DRUID" then foundDruids[name] = true end
        end
    elseif numParty > 0 then
        self:ScanUnit("player", UnitName("player"))
        if UnitClass("player") == "Druid" then foundDruids[UnitName("player")] = true end
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            self:ScanUnit("party"..i, name)
            if class == "DRUID" then foundDruids[name] = true end
        end
    else
        self:ScanUnit("player", UnitName("player"))
        if UnitClass("player") == "Druid" then foundDruids[UnitName("player")] = true end
    end
    
    -- Cleanup druids who left
    for name, _ in pairs(self.AllDruids) do
        if not foundDruids[name] then
            self.AllDruids[name] = nil
            self.Assignments[name] = nil
        end
    end
    
    self.ScanIndex = 1
end

function Druid:ScanStep()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local count = 0
    local stepSize = ClassPower_PerUser.scanperframe or 1
    
    if numRaid > 0 then
        while count < stepSize do
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
        -- Party scanning is small enough to do in one step usually, but keep logic consistent
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
-- Thorns List Management
-----------------------------------------------------------------------------------

function Druid:AddToThornsList(druidName, targetName)
    if not druidName or not targetName then return end
    
    self.ThornsList[druidName] = self.ThornsList[druidName] or {}
    
    -- Check if already in list
    for _, name in ipairs(self.ThornsList[druidName]) do
        if name == targetName then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..targetName.." is already in Thorns list.")
            return
        end
    end
    
    table.insert(self.ThornsList[druidName], targetName)
    self:SaveThornsList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Added "..targetName.." to Thorns list.")
end

function Druid:RemoveFromThornsList(druidName, targetName)
    if not druidName or not targetName then return end
    if not self.ThornsList[druidName] then return end
    
    for i, name in ipairs(self.ThornsList[druidName]) do
        if name == targetName then
            table.remove(self.ThornsList[druidName], i)
            self:SaveThornsList()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Removed "..targetName.." from Thorns list.")
            return
        end
    end
end

function Druid:ClearThornsList(druidName)
    if not druidName then return end
    self.ThornsList[druidName] = {}
    self:SaveThornsList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared Thorns list.")
end

function Druid:SaveThornsList()
    ClassPower_PerUser.DruidThornsList = self.ThornsList
end

function Druid:SaveInnervateThreshold()
    ClassPower_PerUser.DruidInnervateThreshold = self.InnervateThreshold
end

function Druid:GetInnervateThreshold(druidName)
    return self.InnervateThreshold[druidName] or 0
end

function Druid:SetInnervateThreshold(druidName, value)
    if not druidName then return end
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    self.InnervateThreshold[druidName] = value
    self:SaveInnervateThreshold()
end

function Druid:GetTargetManaPercent(targetName)
    -- Find the unit for this target and return their mana %
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name = UnitName("raid"..i)
            if name == targetName then
                local mana = UnitMana("raid"..i)
                local manaMax = UnitManaMax("raid"..i)
                if manaMax > 0 then
                    return math.floor((mana / manaMax) * 100)
                end
                return 100
            end
        end
    elseif numParty > 0 then
        if UnitName("player") == targetName then
            local mana = UnitMana("player")
            local manaMax = UnitManaMax("player")
            if manaMax > 0 then
                return math.floor((mana / manaMax) * 100)
            end
            return 100
        end
        for i = 1, numParty do
            local name = UnitName("party"..i)
            if name == targetName then
                local mana = UnitMana("party"..i)
                local manaMax = UnitManaMax("party"..i)
                if manaMax > 0 then
                    return math.floor((mana / manaMax) * 100)
                end
                return 100
            end
        end
    end
    
    return 100  -- Default to 100% if not found
end

function Druid:GetThornsListCount(druidName)
    if not self.ThornsList[druidName] then return 0 end
    return table.getn(self.ThornsList[druidName])
end

function Druid:GetThornsMissing(druidName)
    if not self.ThornsList[druidName] then return 0, 0 end
    
    local missing = 0
    local total = 0
    
    for _, targetName in ipairs(self.ThornsList[druidName]) do
        local status = self.CurrentBuffsByName[targetName]
        if status then
            total = total + 1
            if not status.hasThorns and not status.dead then
                missing = missing + 1
            end
        end
    end
    
    return missing, total
end

-- Estimate remaining time for a buff on a player (educated guess based on when we first saw it)
function Druid:GetEstimatedTimeRemaining(playerName, buffType)
    if not self.BuffTimestamps[playerName] then return nil end
    if not self.BuffTimestamps[playerName][buffType] then return nil end
    
    local duration = self.BuffDurations[buffType] or 1800
    
    -- Adjust duration for Gift of the Wild (60m) vs Mark (30m)
    if buffType == "MotW" and self.BuffTimestamps[playerName].isGift then
        duration = self.BuffDurations.GotW
    end
    local firstSeen = self.BuffTimestamps[playerName][buffType]
    local elapsed = GetTime() - firstSeen
    local remaining = duration - elapsed
    
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Get minimum time remaining for MotW across a group
function Druid:GetGroupMinTimeRemaining(groupIndex)
    local minTime = nil
    
    if not self.CurrentBuffs[groupIndex] then return nil end
    
    for _, m in pairs(self.CurrentBuffs[groupIndex]) do
        if m.hasMotW and not m.dead then
            local remaining = self:GetEstimatedTimeRemaining(m.name, "MotW")
            if remaining then
                if not minTime or remaining < minTime then
                    minTime = remaining
                end
            end
        end
    end
    
    return minTime
end

-- Get minimum time remaining for Thorns across the Thorns list
function Druid:GetThornsListMinTimeRemaining(druidName)
    local minTime = nil
    
    if not self.ThornsList[druidName] then return nil end
    
    for _, targetName in ipairs(self.ThornsList[druidName]) do
        local status = self.CurrentBuffsByName[targetName]
        if status and status.hasThorns and not status.dead then
            local remaining = self:GetEstimatedTimeRemaining(targetName, "Thorns")
            if remaining then
                if not minTime or remaining < minTime then
                    minTime = remaining
                end
            end
        end
    end
    
    return minTime
end

-- Get Innervate cooldown remaining in seconds, or 0 if ready
function Druid:GetInnervateCooldown()
    -- Find Innervate spell slot
    local i = 1
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        
        if spellName == self.Spells.INNERVATE then
            local start, duration = GetSpellCooldown(i, BOOKTYPE_SPELL)
            if start and start > 0 and duration and duration > 0 then
                local remaining = (start + duration) - GetTime()
                if remaining > 0 then
                    return remaining
                end
            end
            return 0
        end
        i = i + 1
    end
    return 0
end

-----------------------------------------------------------------------------------
-- Auto-Assign
-----------------------------------------------------------------------------------

function Druid:AutoAssign()
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
    
    -- Get Druids with Gift of the Wild (talent = 1 means they have Gift)
    local druidsWithGift = {}
    for druidName, info in pairs(self.AllDruids) do
        if info[0] and info[0].talent == 1 then
            table.insert(druidsWithGift, druidName)
        end
    end
    
    if table.getn(druidsWithGift) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Druids with Gift of the Wild found.")
        return
    end
    
    -- Distribute groups among Druids
    local assignments = ClassPower_DistributeGroups(druidsWithGift, activeGroups)
    
    -- Apply assignments and broadcast
    for druidName, groups in pairs(assignments) do
        -- Clear existing group assignments for this druid
        self.Assignments[druidName] = self.Assignments[druidName] or {}
        local assignStr = ""
        
        for g = 1, 8 do
            local assigned = 0
            for _, ag in ipairs(groups) do
                if ag == g then assigned = 1 break end
            end
            self.Assignments[druidName][g] = assigned
            assignStr = assignStr .. assigned
        end
        
        -- Broadcast batch assignment
        ClassPower_SendMessage("DASSIGNS "..druidName.." "..assignStr)
    end
    
    -- Report what was done
    local msg = "|cff00ff00ClassPower|r: Auto-assigned groups: "
    for druidName, groups in pairs(assignments) do
        if table.getn(groups) > 0 then
            local groupStr = ""
            for i, g in ipairs(groups) do
                if i > 1 then groupStr = groupStr .. "," end
                groupStr = groupStr .. g
            end
            msg = msg .. druidName .. " -> G" .. groupStr .. "  "
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(msg)
    
    -- Sync Thorns from Tank List (for current player)
    self:SyncThornsWithTanks()
    
    -- Update UI
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
    
    -- Save assignments
    self:SaveAssignments()
end

function Druid:SyncThornsWithTanks()
    if not ClassPower_TankList then return end
    
    local pname = UnitName("player")
    if not self.ThornsList[pname] then self.ThornsList[pname] = {} end
    
    local count = 0
    for _, tank in ipairs(ClassPower_TankList) do
        -- Check if already in list
        local found = false
        for _, tName in ipairs(self.ThornsList[pname]) do
            if tName == tank.name then 
                found = true 
                break 
            end
        end
        
        if not found then
            table.insert(self.ThornsList[pname], tank.name)
            count = count + 1
        end
    end
    
    if count > 0 then
        self:SaveThornsList()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Added "..count.." tanks to your Thorns list.")
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
        self.UIDirty = true
    elseif string.find(msg, "^DASSIGNS ") then
        local _, _, name, assignStr = string.find(msg, "^DASSIGNS (.-) (.*)")
        if name and assignStr then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                for gid = 1, 8 do
                    local val = string.sub(assignStr, gid, gid)
                    if val ~= "n" and val ~= "" then
                        self.Assignments[name][gid] = tonumber(val)
                    else
                        self.Assignments[name][gid] = 0
                    end
                end
                self.UIDirty = true
                if name == UnitName("player") then self:SaveAssignments() end
            end
        end
    elseif string.find(msg, "^DASSIGN ") then
        local _, _, name, grp, skill = string.find(msg, "^DASSIGN (.-) (.-) (.*)")
        if name and grp and skill then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                self.Assignments[name][tonumber(grp)] = tonumber(skill)
                self.UIDirty = true
                if name == UnitName("player") then self:SaveAssignments() end
            end
        end
    elseif string.find(msg, "^DASSIGNTARGET ") then
        local _, _, name, target = string.find(msg, "^DASSIGNTARGET (.-) (.*)")
        if name and target then
            if sender == name or ClassPower_IsPromoted(sender) then
                if target == "nil" or target == "" then target = nil end
                self.LegacyAssignments[name] = self.LegacyAssignments[name] or {}
                self.LegacyAssignments[name]["Innervate"] = target
                self.UIDirty = true
            end
        end
    elseif string.find(msg, "^DCLEAR ") then
        local _, _, target = string.find(msg, "^DCLEAR (.*)")
        if target then
            if sender == target or ClassPower_IsPromoted(sender) then
                self.Assignments[target] = {}
                self.LegacyAssignments[target] = {}
                self.ThornsList[target] = {}
                self:SaveThornsList()
                if target == UnitName("player") then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Assignments cleared by "..sender)
                end
                self.UIDirty = true
            end
        end
    elseif string.find(msg, "^DTHORNS ") then
        local _, _, cmd, target, param = string.find(msg, "^DTHORNS ([^ ]+) ([^ ]+) (.*)")
        -- Try 2-arg match if 3-arg failed (e.g. CLEAR)
        if not cmd then 
             _, _, cmd, target = string.find(msg, "^DTHORNS ([^ ]+) (.*)")
        end
        
        if cmd and target then
            if sender == target or ClassPower_IsPromoted(sender) then
                if cmd == "ADD" and param then
                    self:AddToThornsList(target, param)
                    self.UIDirty = true
                elseif cmd == "REMOVE" and param then
                    self:RemoveFromThornsList(target, param)
                    self.UIDirty = true
                elseif cmd == "CLEAR" then
                    self:ClearThornsList(target)
                    self.UIDirty = true
                end
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
        self.BuffBar:Show()  -- Ensure it's visible
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
        if arg1 == "RightButton" then
            -- Right-click opens config
            if Druid.ConfigWindow then
                if Druid.ConfigWindow:IsVisible() then
                    Druid.ConfigWindow:Hide()
                else
                    Druid.ConfigWindow:Show()
                    Druid:UpdateConfigGrid()
                end
            end
        else
            Druid:SaveBuffBarPosition()
        end
    end)
    
    local grip = ClassPower_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Druid:SaveBuffBarPosition()
    end)
    
    -- Create rows: 8 groups + 1 Thorns row + 1 Emerald row + 1 Innervate row
    for i = 1, 11 do
        local row = self:CreateHUDRow(f, "ClassPowerDruidHUDRow"..i, i)
        row:Hide()
    end
    
    if ClassPower_PerUser.DruidPoint then
        f:ClearAllPoints()
        f:SetPoint(ClassPower_PerUser.DruidPoint, "UIParent", ClassPower_PerUser.DruidRelativePoint or "CENTER", ClassPower_PerUser.DruidX or 0, ClassPower_PerUser.DruidY or 0)
    else
        f:SetPoint("CENTER", 0, 0)
    end
    
    if ClassPower_PerUser.DruidScale then
        f:SetScale(ClassPower_PerUser.DruidScale)
    else
        f:SetScale(0.7)
    end
    
    f:Show()  -- Ensure BuffBar is visible
    self.BuffBar = f
end

function Druid:CreateHUDRow(parent, name, id)
    local f = CreateFrame("Frame", name, parent)
    f:SetWidth(140)
    f:SetHeight(34)
    
    local label = f:CreateFontString(f:GetName().."Label", "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", f, "LEFT", 5, 0)
    
    if id == 9 then
        label:SetText("Thrns")
    elseif id == 10 then
        label:SetText("Emrld")
    elseif id == 11 then
        label:SetText("Innerv")
    else
        label:SetText("Grp "..id)
    end
    
    if id <= 8 then
        local motw = ClassPower_CreateHUDButton(f, name.."MotW")
        motw:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(motw:GetName().."Icon"):SetTexture(self.BuffIcons[0])
        motw:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    if id == 9 then
        -- Thorns row - shows missing thorns from list
        local thorns = ClassPower_CreateHUDButton(f, name.."Thorns")
        thorns:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(thorns:GetName().."Icon"):SetTexture(self.SpecialIcons["Thorns"])
        thorns:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    if id == 10 then
        local emerald = ClassPower_CreateHUDButton(f, name.."Emerald")
        emerald:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(emerald:GetName().."Icon"):SetTexture(self.SpecialIcons["Emerald"])
        emerald:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    if id == 11 then
        -- Innervate row - shows when target mana is below threshold
        local innervate = ClassPower_CreateHUDButton(f, name.."Innervate")
        innervate:SetPoint("LEFT", f, "LEFT", 40, 0)
        getglobal(innervate:GetName().."Icon"):SetTexture(self.SpecialIcons["Innervate"])
        innervate:SetScript("OnClick", function() Druid:BuffButton_OnClick(this) end)
    end
    
    return f
end

function Druid:SaveBuffBarPosition()
    if not self.BuffBar then return end
    local point, _, relativePoint, x, y = self.BuffBar:GetPoint()
    ClassPower_PerUser.DruidPoint = point
    ClassPower_PerUser.DruidRelativePoint = relativePoint
    ClassPower_PerUser.DruidX = x
    ClassPower_PerUser.DruidY = y
    ClassPower_PerUser.DruidScale = self.BuffBar:GetScale()
end

function Druid:UpdateBuffBar()
    if not self.BuffBar then return end
    
    local f = self.BuffBar
    local pname = UnitName("player")
    local assigns = self.Assignments[pname]
    
    local lastRow = nil
    local count = 0
    
    for i = 1, 11 do
        local row = getglobal("ClassPowerDruidHUDRow"..i)
        if not row then break end
        
        local showRow = false
        
        if i == 9 then
            -- Thorns List row
            local btnThorns = getglobal(row:GetName().."Thorns")
            local missing, total = self:GetThornsMissing(pname)
            
            local displayMode = ClassPower_PerUser.BuffDisplayMode or "missing"
            local minTimeRemaining = self:GetThornsListMinTimeRemaining(pname)
            local thresholdSeconds = ((ClassPower_PerUser.TimerThresholdMinutes or 5) * 60) + (ClassPower_PerUser.TimerThresholdSeconds or 0)
            
            local shouldShow = false
            if displayMode == "always" then
                shouldShow = (total > 0)
            elseif displayMode == "timer" then
                if missing > 0 then
                    shouldShow = true
                elseif minTimeRemaining and minTimeRemaining <= thresholdSeconds then
                    shouldShow = true
                end
            else -- "missing" mode
                shouldShow = (total > 0 and missing > 0)
            end
            
            if shouldShow then
                btnThorns:Show()
                btnThorns.tooltipText = "Thorns List"
                local txt = getglobal(btnThorns:GetName().."Text")
                local icon = getglobal(btnThorns:GetName().."Icon")
                
                -- Display format based on mode
                if displayMode == "always" or displayMode == "timer" then
                    -- Show timer + missing count
                    if minTimeRemaining and minTimeRemaining > 0 and missing == 0 then
                        -- All buffed, show time remaining
                        txt:SetText(ClassPower_FormatTime(minTimeRemaining))
                        txt:SetTextColor(0, 1, 0)
                    elseif missing > 0 then
                        -- Some missing
                        if minTimeRemaining and minTimeRemaining > 0 then
                            txt:SetText(missing.." ("..ClassPower_FormatTime(minTimeRemaining)..")")
                        else
                            txt:SetText(missing.." miss")
                        end
                        txt:SetTextColor(1, 0, 0)
                    else
                        txt:SetText(total.."/"..total)
                        txt:SetTextColor(0, 1, 0)
                    end
                else
                    -- Original missing mode display
                    txt:SetText((total-missing).."/"..total)
                    txt:SetTextColor(1, 0, 0)
                end
                
                showRow = true
            else
                btnThorns:Hide()
            end
        elseif i == 10 then
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
        elseif i == 11 then
            -- Innervate row - show when target mana is below threshold
            local btnInn = getglobal(row:GetName().."Innervate")
            local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Innervate"]
            local threshold = self:GetInnervateThreshold(pname)
            local hasInnervate = self.RankInfo and self.RankInfo["Innervate"]
            
            if hasInnervate and target and threshold > 0 then
                local manaPercent = self:GetTargetManaPercent(target)
                local status = self.CurrentBuffsByName[target]
                
                if status and not status.dead and manaPercent <= threshold then
                    -- Target needs Innervate - check if on cooldown
                    local cooldownRemaining = self:GetInnervateCooldown()
                    local icon = getglobal(btnInn:GetName().."Icon")
                    local txt = getglobal(btnInn:GetName().."Text")
                    
                    btnInn:Show()
                    
                    if cooldownRemaining > 0 then
                        -- On cooldown - show dimmed with CD timer
                        btnInn.tooltipText = "Innervate: "..target.." ("..manaPercent.."%)\nCooldown: "..ClassPower_FormatTime(cooldownRemaining)
                        if icon then icon:SetVertexColor(0.5, 0.5, 0.5) end  -- 50% dimmed
                        txt:SetText(ClassPower_FormatTime(cooldownRemaining))
                        txt:SetTextColor(0.7, 0.7, 0.7)  -- Gray text for CD
                    else
                        -- Ready to cast - show normal
                        btnInn.tooltipText = "Innervate: "..target.." ("..manaPercent.."%)"
                        if icon then icon:SetVertexColor(1, 1, 1) end  -- Full brightness
                        txt:SetText(manaPercent.."%")
                        txt:SetTextColor(1, 0.5, 0)  -- Orange when ready
                    end
                    
                    showRow = true
                else
                    btnInn:Hide()
                    -- Reset icon color when hidden
                    local icon = getglobal(btnInn:GetName().."Icon")
                    if icon then icon:SetVertexColor(1, 1, 1) end
                end
            else
                btnInn:Hide()
            end
        elseif assigns and assigns[i] and assigns[i] > 0 then
            -- Group assigned - show based on display mode
            local btnMotW = getglobal(row:GetName().."MotW")
            if btnMotW then
                local missing = 0
                local total = 0
                if self.CurrentBuffs[i] then
                    for _, m in pairs(self.CurrentBuffs[i]) do
                        total = total + 1
                        if not m.hasMotW and not m.dead then missing = missing + 1 end
                    end
                end
                
                local displayMode = ClassPower_PerUser.BuffDisplayMode or "missing"
                local minTimeRemaining = self:GetGroupMinTimeRemaining(i)
                local thresholdSeconds = ((ClassPower_PerUser.TimerThresholdMinutes or 5) * 60) + (ClassPower_PerUser.TimerThresholdSeconds or 0)
                
                local shouldShow = false
                if displayMode == "always" then
                    -- Always show assigned groups
                    shouldShow = (total > 0)
                elseif displayMode == "timer" then
                    -- Show if missing OR if time remaining is below threshold
                    if missing > 0 then
                        shouldShow = true
                    elseif minTimeRemaining and minTimeRemaining <= thresholdSeconds then
                        shouldShow = true
                    end
                else -- "missing" mode (default)
                    shouldShow = (missing > 0)
                end
                
                if shouldShow then
                    btnMotW:Show()
                    btnMotW.tooltipText = "Group "..i..": Mark of the Wild\nLeft-click: Gift (group)\nRight-click: Mark (single)"
                    local txt = getglobal(btnMotW:GetName().."Text")
                    local icon = getglobal(btnMotW:GetName().."Icon")
                    icon:SetTexture(self.BuffIcons[0])
                    
                    -- Display format based on mode
                    if displayMode == "always" or displayMode == "timer" then
                        -- Show timer + missing count
                        if minTimeRemaining and minTimeRemaining > 0 and missing == 0 then
                            -- All buffed, show time remaining
                            txt:SetText(ClassPower_FormatTime(minTimeRemaining))
                            txt:SetTextColor(0, 1, 0)  -- Green when all buffed
                        elseif missing > 0 then
                            -- Some missing
                            if minTimeRemaining and minTimeRemaining > 0 then
                                txt:SetText(missing.." ("..ClassPower_FormatTime(minTimeRemaining)..")")
                            else
                                txt:SetText(missing.." miss")
                            end
                            txt:SetTextColor(1, 0, 0)  -- Red when missing
                        else
                            txt:SetText(total.."/"..total)
                            txt:SetTextColor(0, 1, 0)
                        end
                    else
                        -- Original missing mode display
                        txt:SetText((total-missing).."/"..total)
                        txt:SetTextColor(1, 0, 0)
                    end
                    
                    showRow = true
                else
                    btnMotW:Hide()
                end
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
    
    -- Dynamic height (only update if changed)
    local newHeight = 25 + (count * 34)
    if newHeight < 40 then newHeight = 40 end
    if f:GetHeight() ~= newHeight then
        f:SetHeight(newHeight)
    end
    
    -- Dynamic width based on actual text content
    -- Calculate: label(40) + button(30) + padding(4) + text width + right margin(10)
    local maxTextWidth = 0
    for i = 1, 11 do
        local row = getglobal("ClassPowerDruidHUDRow"..i)
        if row and row:IsVisible() then
            -- Check MotW button text
            local btnMotW = getglobal(row:GetName().."MotW")
            if btnMotW and btnMotW:IsVisible() then
                local txt = getglobal(btnMotW:GetName().."Text")
                if txt then
                    local textWidth = txt:GetStringWidth() or 0
                    if textWidth > maxTextWidth then maxTextWidth = textWidth end
                end
            end
            -- Check Thorns button text
            local btnThorns = getglobal(row:GetName().."Thorns")
            if btnThorns and btnThorns:IsVisible() then
                local txt = getglobal(btnThorns:GetName().."Text")
                if txt then
                    local textWidth = txt:GetStringWidth() or 0
                    if textWidth > maxTextWidth then maxTextWidth = textWidth end
                end
            end
            -- Check Emerald button text
            local btnEmerald = getglobal(row:GetName().."Emerald")
            if btnEmerald and btnEmerald:IsVisible() then
                local txt = getglobal(btnEmerald:GetName().."Text")
                if txt then
                    local textWidth = txt:GetStringWidth() or 0
                    if textWidth > maxTextWidth then maxTextWidth = textWidth end
                end
            end
            -- Check Innervate button text
            local btnInn = getglobal(row:GetName().."Innervate")
            if btnInn and btnInn:IsVisible() then
                local txt = getglobal(btnInn:GetName().."Text")
                if txt then
                    local textWidth = txt:GetStringWidth() or 0
                    if textWidth > maxTextWidth then maxTextWidth = textWidth end
                end
            end
        end
    end
    
    -- Width = left padding(5) + label width(35) + button(30) + gap(4) + text + right padding(10)
    local newWidth = 5 + 35 + 30 + 4 + maxTextWidth + 10
    if newWidth < 80 then newWidth = 80 end  -- Minimum width
    if count > 0 and f:GetWidth() ~= newWidth then
        f:SetWidth(newWidth)
    end
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
    f:SetWidth(860)
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
        ClassPower_PerUser.DruidConfigScale = p:GetScale()
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
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 165 + (g-1)*52, headerY)
        lbl:SetText("G"..g)
    end
    
    local lblThorns = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblThorns:SetPoint("TOPLEFT", f, "TOPLEFT", 590, headerY)
    lblThorns:SetText("Thorns")
    
    local lblInnerv = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblInnerv:SetPoint("TOPLEFT", f, "TOPLEFT", 660, headerY)
    lblInnerv:SetText("Innerv")
    
    local lblMana = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblMana:SetPoint("TOPLEFT", f, "TOPLEFT", 720, headerY)
    lblMana:SetText("Mana%")
    
    for i = 1, 10 do
        self:CreateConfigRow(f, i)
    end
    
    if ClassPower_PerUser.DruidConfigScale then
        f:SetScale(ClassPower_PerUser.DruidConfigScale)
    else
        f:SetScale(1.0)
    end
    
    -- Settings button at bottom-left
    local settingsBtn = CreateFrame("Button", f:GetName().."SettingsBtn", f, "UIPanelButtonTemplate")
    settingsBtn:SetWidth(80)
    settingsBtn:SetHeight(22)
    settingsBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 15)
    settingsBtn:SetText("Settings...")
    settingsBtn:SetScript("OnClick", function()
        ClassPower_ShowSettingsPanel()
    end)
    settingsBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Display Settings")
        GameTooltip:AddLine("Configure buff bar display mode", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("and timer thresholds.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Auto-Assign button (only visible for leaders/assists)
    local autoBtn = CreateFrame("Button", f:GetName().."AutoAssignBtn", f, "UIPanelButtonTemplate")
    autoBtn:SetWidth(90)
    autoBtn:SetHeight(22)
    autoBtn:SetPoint("LEFT", settingsBtn, "RIGHT", 10, 0)
    autoBtn:SetText("Auto-Assign")
    autoBtn:SetScript("OnClick", function()
        Druid:AutoAssign()
    end)
    autoBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Assign Groups")
        GameTooltip:AddLine("Automatically distribute groups", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("among Druids with Gift of the Wild.", 0.7, 0.7, 0.7)
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
    closeModBtn:SetHeight(22)
    closeModBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 15)
    closeModBtn:SetText("Close Module")
    closeModBtn:SetScript("OnClick", function()
        ClassPower:CloseModule("DRUID")
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
            if UnitClass("player") ~= "Druid" then
                closeBtn:Show()
            else
                closeBtn:Hide()
            end
        end
    end)
    
    f:Hide()
    self.ConfigWindow = f
end

function Druid:CreateConfigRow(parent, rowIndex)
    local rowName = "CPDruidRow"..rowIndex
    local row = CreateFrame("Frame", rowName, parent)
    row:SetWidth(790)
    row:SetHeight(44)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -65 - (rowIndex-1)*46)
    
    local clearBtn = ClassPower_CreateClearButton(row, rowName.."Clear")
    clearBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    clearBtn:SetScript("OnClick", function() Druid:ClearButton_OnClick(this) end)
    
    local nameStr = row:CreateFontString(rowName.."Name", "OVERLAY", "GameFontHighlight")
    nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 15, -14)
    nameStr:SetWidth(65)
    nameStr:SetHeight(16)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("")
    
    local caps = CreateFrame("Frame", rowName.."Caps", row)
    caps:SetWidth(65)
    caps:SetHeight(22)
    caps:SetPoint("TOPLEFT", row, "TOPLEFT", 80, -12)
    
    local function CreateCapIcon(suffix, xOffset)
        local btn = ClassPower_CreateCapabilityIcon(caps, rowName.."Cap"..suffix)
        btn:SetWidth(16)
        btn:SetHeight(16)
        local icon = getglobal(btn:GetName().."Icon")
        if icon then icon:SetWidth(14); icon:SetHeight(14) end
        btn:SetPoint("TOPLEFT", caps, "TOPLEFT", xOffset, 0)
        return btn
    end
    
    CreateCapIcon("MotW", 0)
    CreateCapIcon("Thorns", 16)
    CreateCapIcon("Emerald", 32)
    CreateCapIcon("Innervate", 48)
    
    for g = 1, 8 do
        local grpFrame = CreateFrame("Frame", rowName.."Group"..g, row)
        grpFrame:SetWidth(48)
        grpFrame:SetHeight(42)
        grpFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 150 + (g-1)*52, 0)
        grpFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        grpFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        -- MotW button only (Thorns handled via list now)
        local btnMotW = CreateFrame("Button", rowName.."Group"..g.."MotW", grpFrame)
        btnMotW:SetWidth(28); btnMotW:SetHeight(28)
        btnMotW:SetPoint("CENTER", grpFrame, "CENTER", 0, 0)
        local motwBg = btnMotW:CreateTexture(btnMotW:GetName().."Background", "BACKGROUND")
        motwBg:SetAllPoints(btnMotW); motwBg:SetTexture(0.1, 0.1, 0.1, 0.5)
        local motwIcon = btnMotW:CreateTexture(btnMotW:GetName().."Icon", "OVERLAY")
        motwIcon:SetWidth(26); motwIcon:SetHeight(26); motwIcon:SetPoint("CENTER", btnMotW, "CENTER", 0, 0)
        local motwTxt = btnMotW:CreateFontString(btnMotW:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
        motwTxt:SetPoint("BOTTOM", btnMotW, "BOTTOM", 0, -10); motwTxt:SetJustifyH("CENTER")
        btnMotW:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btnMotW:SetScript("OnClick", function() Druid:SubButton_OnClick(this) end)
        btnMotW:SetScript("OnEnter", function() Druid:SubButton_OnEnter(this) end)
        btnMotW:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    -- Thorns List button
    local thornsBtn = CreateFrame("Button", rowName.."ThornsList", row)
    thornsBtn:SetWidth(28); thornsBtn:SetHeight(28)
    thornsBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 575, -6)
    local thornsBg = thornsBtn:CreateTexture(thornsBtn:GetName().."Background", "BACKGROUND")
    thornsBg:SetAllPoints(thornsBtn); thornsBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    local thornsIcon = thornsBtn:CreateTexture(thornsBtn:GetName().."Icon", "OVERLAY")
    thornsIcon:SetWidth(26); thornsIcon:SetHeight(26); thornsIcon:SetPoint("CENTER", thornsBtn, "CENTER", 0, 0)
    local thornsTxt = thornsBtn:CreateFontString(thornsBtn:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
    thornsTxt:SetPoint("CENTER", thornsBtn, "CENTER", 0, 0)
    thornsBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    thornsBtn:SetScript("OnClick", function() Druid:ThornsButton_OnClick(this) end)
    thornsBtn:SetScript("OnEnter", function() Druid:ThornsButton_OnEnter(this) end)
    thornsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local thornsCount = row:CreateFontString(rowName.."ThornsCount", "OVERLAY", "GameFontHighlightSmall")
    thornsCount:SetPoint("TOP", thornsBtn, "BOTTOM", 0, -2)
    thornsCount:SetWidth(50)
    thornsCount:SetText("")
    
    -- Innervate target button
    local innervBtn = CreateFrame("Button", rowName.."Innervate", row)
    innervBtn:SetWidth(28); innervBtn:SetHeight(28)
    innervBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 645, -6)
    local innervBg = innervBtn:CreateTexture(innervBtn:GetName().."Background", "BACKGROUND")
    innervBg:SetAllPoints(innervBtn); innervBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    local innervIcon = innervBtn:CreateTexture(innervBtn:GetName().."Icon", "OVERLAY")
    innervIcon:SetWidth(26); innervIcon:SetHeight(26); innervIcon:SetPoint("CENTER", innervBtn, "CENTER", 0, 0)
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
    
    -- Innervate mana threshold slider
    local thresholdSlider = CreateFrame("Slider", rowName.."InnervateThreshold", row, "OptionsSliderTemplate")
    thresholdSlider:SetWidth(60)
    thresholdSlider:SetHeight(14)
    thresholdSlider:SetPoint("TOPLEFT", row, "TOPLEFT", 700, -10)
    thresholdSlider:SetMinMaxValues(0, 100)
    thresholdSlider:SetValueStep(5)
    thresholdSlider:SetValue(0)
    thresholdSlider:SetOrientation("HORIZONTAL")
    
    -- Hide the default min/max text
    getglobal(thresholdSlider:GetName().."Low"):SetText("")
    getglobal(thresholdSlider:GetName().."High"):SetText("")
    getglobal(thresholdSlider:GetName().."Text"):SetText("")
    
    -- Create our own value display
    local thresholdValue = row:CreateFontString(rowName.."ThresholdValue", "OVERLAY", "GameFontHighlightSmall")
    thresholdValue:SetPoint("TOP", thresholdSlider, "BOTTOM", 0, 0)
    thresholdValue:SetText("0%")
    
    thresholdSlider:SetScript("OnValueChanged", function()
        local val = math.floor(this:GetValue())
        getglobal(this:GetParent():GetName().."ThresholdValue"):SetText(val.."%")
        Druid:ThresholdSlider_OnChange(this, val)
    end)
    thresholdSlider:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Innervate Mana Threshold")
        GameTooltip:AddLine("Show Innervate button when target", 1, 1, 1)
        GameTooltip:AddLine("mana drops below this percentage.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Set to 0 to disable.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    thresholdSlider:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
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
                    displayName = string.sub(druidName, 1, 9)..". "
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
            self:UpdateThornsButton(rowIndex, druidName)
            self:UpdateInnervateButton(rowIndex, druidName)
        end
        rowIndex = rowIndex + 1
    end
    
    for i = rowIndex, 10 do
        local row = getglobal("CPDruidRow"..i)
        if row then row:Hide() end
    end
    
    -- Add extra height for settings button at bottom
    local newHeight = 80 + (rowIndex - 1) * 46 + 40  -- +40 for settings button
    if newHeight < 180 then newHeight = 180 end  -- Minimum to fit settings button
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
        
        local prefix = "CPDruidRow"..rowIndex.."Group"..g
        
        local btn = getglobal(prefix.."MotW")
        if not btn then return end
        local icon = getglobal(btn:GetName().."Icon")
        local text = getglobal(btn:GetName().."Text")
        
        if val > 0 then
            -- Assigned - show the icon
            icon:SetTexture(self.BuffIcons[0])
            icon:Show()
            btn:SetAlpha(1.0)
            
            local missing = 0
            local total = 0
            if self.CurrentBuffs[g] then
                for _, m in self.CurrentBuffs[g] do
                    total = total + 1
                    if not m.hasMotW and not m.dead then missing = missing + 1 end
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
            -- Not assigned
            icon:Hide()
            text:SetText("")
            btn:SetAlpha(0.3)
        end
    end
end

function Druid:UpdateThornsButton(rowIndex, druidName)
    local btn = getglobal("CPDruidRow"..rowIndex.."ThornsList")
    local countLabel = getglobal("CPDruidRow"..rowIndex.."ThornsCount")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    icon:SetTexture(self.SpecialIcons["Thorns"])
    
    local listCount = self:GetThornsListCount(druidName)
    local missing, total = self:GetThornsMissing(druidName)
    
    if listCount > 0 then
        icon:Show()
        btn:SetAlpha(1.0)
        if countLabel then 
            countLabel:SetText((total-missing).."/"..total) 
            if missing > 0 then
                countLabel:SetTextColor(1, 0, 0)
            else
                countLabel:SetTextColor(0, 1, 0)
            end
        end
        local text = getglobal(btn:GetName().."Text")
        if missing > 0 then
            text:SetText("|cffff0000!|r")
        else
            text:SetText("")
        end
    else
        icon:Show()
        btn:SetAlpha(0.3)
        if countLabel then countLabel:SetText("") end
        getglobal(btn:GetName().."Text"):SetText("")
    end
end

function Druid:UpdateInnervateButton(rowIndex, druidName)
    local btn = getglobal("CPDruidRow"..rowIndex.."Innervate")
    local nameLabel = getglobal("CPDruidRow"..rowIndex.."InnervateName")
    local thresholdSlider = getglobal("CPDruidRow"..rowIndex.."InnervateThreshold")
    local thresholdValue = getglobal("CPDruidRow"..rowIndex.."ThresholdValue")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local target = self.LegacyAssignments[druidName] and self.LegacyAssignments[druidName]["Innervate"]
    local threshold = self:GetInnervateThreshold(druidName)
    
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
    
    -- Update threshold slider
    if thresholdSlider then
        thresholdSlider:SetValue(threshold)
        if thresholdValue then
            thresholdValue:SetText(threshold.."%")
        end
        -- Only allow editing own threshold
        if druidName == UnitName("player") then
            thresholdSlider:EnableMouse(true)
            thresholdSlider:SetAlpha(1.0)
        else
            thresholdSlider:EnableMouse(false)
            thresholdSlider:SetAlpha(0.5)
        end
    end
end

function Druid:ThresholdSlider_OnChange(slider, value)
    local sliderName = slider:GetName()
    local _, _, rowIdx = string.find(sliderName, "CPDruidRow(%d+)InnervateThreshold")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    if not druidName then return end
    
    -- Only allow editing own threshold
    if druidName ~= UnitName("player") then
        return
    end
    
    self:SetInnervateThreshold(druidName, value)
    self:UpdateBuffBar()
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
        -- Thorns
        local thornsList = self.ThornsList[pname]
        if thornsList then
            local isRightClick = (arg1 == "RightButton")
            local bestTarget = nil
            local minTime = 999999

            for _, target in ipairs(thornsList) do
                local status = self.CurrentBuffsByName[target]
                if status and status.visible and not status.dead then
                    -- Check status
                    local missing = not status.hasThorns
                    
                    if isRightClick then
                        -- Right-click: Only target missing
                        if missing then
                            bestTarget = target
                            break -- Found one, that's enough
                        end
                    else
                        -- Left-click: Force refresh (smart priority)
                        -- Prioritize missing (-1), then lowest duration
                        local remaining = self:GetEstimatedTimeRemaining(target, "Thorns")
                        if missing then remaining = -1 end
                        if not remaining then remaining = 0 end -- Should have timestamp if hasThorns, but safety fallback
                        
                        if remaining < minTime then
                            minTime = remaining
                            bestTarget = target
                        end
                    end
                end
            end
            
            if bestTarget then
                ClearTarget()
                TargetByName(bestTarget, true)
                if UnitName("target") == bestTarget then
                    if CheckInteractDistance("target", 4) then
                        CastSpellByName(self.Spells.THORNS)
                        
                        -- Optimistic timestamp update for forced refresh
                        if self.BuffTimestamps[bestTarget] then
                            self.BuffTimestamps[bestTarget].Thorns = GetTime()
                        end

                        TargetLastTarget()
                        self:ScanRaid()
                        self:UpdateBuffBar()
                        return
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: " .. bestTarget .. " is out of range!")
                    end
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target " .. bestTarget)
                end
                TargetLastTarget()
            else
                if isRightClick then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: All Thorns targets are buffed!")
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Thorns targets need refresh!")
                end
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Thorns targets assigned!")
        end
    elseif i == 10 then
        -- Emerald Blessing - just cast it (self-cast raid buff)
        CastSpellByName(self.Spells.EMERALD)
    elseif i == 11 then
        -- Innervate - cast on assigned target
        local target = self.LegacyAssignments[pname] and self.LegacyAssignments[pname]["Innervate"]
        if target then
            ClearTarget()
            TargetByName(target, true)
            if UnitName("target") == target then
                if CheckInteractDistance("target", 4) then
                    CastSpellByName(self.Spells.INNERVATE)
                    TargetLastTarget()
                    self:ScanRaid()
                    self:UpdateBuffBar()
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..target.." is out of range!")
                    TargetLastTarget()
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Could not target "..target)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Innervate target assigned!")
        end
    else
        -- Group buff (MotW/GotW)
        local gid = i
        local assigns = self.Assignments[pname]
        local val = assigns and assigns[gid] or 0
        
        if val == 0 then return end  -- Not assigned to this group
        
        -- Left-click = Gift of the Wild (if learned), Right-click = Mark of the Wild (single)
        local isRightClick = (arg1 == "RightButton")
        local hasGift = self.RankInfo and self.RankInfo[0] and self.RankInfo[0].talent == 1
        local spellName
        
        if isRightClick then
            spellName = self.Spells.MOTW  -- Always use single target on right-click
        elseif hasGift then
            spellName = self.Spells.GOTW  -- Use Gift if learned
        else
            spellName = self.Spells.MOTW  -- Fall back to Mark if Gift not learned
        end
        
        ClassPower_Debug("Druid BuffButton: hasGift="..tostring(hasGift)..", spell="..tostring(spellName)..", group="..gid)
        
        if self.CurrentBuffs[gid] then
            ClassPower_Debug("Group "..gid.." has data, checking members...")
            
            -- For Gift (left-click): target anyone visible and alive in range
            -- For Mark (right-click): target someone missing the buff
            for _, member in self.CurrentBuffs[gid] do
                ClassPower_Debug("  Checking: "..member.name..", hasMotW="..tostring(member.hasMotW)..", visible="..tostring(member.visible)..", dead="..tostring(member.dead))
                
                -- For Mark (right-click), skip if they already have the buff
                -- For Gift (left-click), we can target anyone
                local isValidTarget = member.visible and not member.dead
                if isRightClick and member.hasMotW then
                    isValidTarget = false  -- Right-click only targets missing buff
                end
                
                if isValidTarget then
                    ClearTarget()
                    TargetByName(member.name, true)
                    if UnitExists("target") and UnitName("target") == member.name then
                        if CheckInteractDistance("target", 4) then
                            ClassPower_Debug("Casting "..spellName.." on "..member.name)
                            CastSpellByName(spellName)
                            TargetLastTarget()
                            
                            -- Reset timestamps for group when casting Gift of the Wild
                            if spellName == self.Spells.GOTW and self.CurrentBuffs[gid] then
                                for _, m in pairs(self.CurrentBuffs[gid]) do
                                    if self.BuffTimestamps[m.name] then
                                        self.BuffTimestamps[m.name].MotW = GetTime()
                                    end
                                end
                            end
                            
                            self:ScanRaid()
                            self:UpdateBuffBar()
                            return
                        else
                            -- Out of range, restore target and try next
                            ClassPower_Debug(member.name.." out of range")
                            TargetLastTarget()
                        end
                    else
                        -- Couldn't target, restore and try next
                        ClassPower_Debug("Could not target "..member.name)
                        TargetLastTarget()
                    end
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No targets in range for Group "..gid)
        else
            ClassPower_Debug("No buff data for group "..gid)
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
    self.ThornsList[druidName] = {}
    self:SaveThornsList()
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
    
    -- Simple toggle: 0 = off, 1 = assigned
    if cur == 0 then
        cur = 1
    else
        cur = 0
    end
    
    self.Assignments[druidName][grpIdx] = cur
    ClassPower_SendMessage("DASSIGN "..druidName.." "..grpIdx.." "..cur)
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Druid:SubButton_OnEnter(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Mark of the Wild")
    GameTooltip:AddLine("Click to toggle assignment", 1, 1, 1)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("On HUD:", 1, 0.8, 0)
    GameTooltip:AddLine("Left-click: Gift of the Wild (group)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Mark of the Wild (single)", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Druid:ThornsButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPDruidRow(%d+)ThornsList")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    if not druidName then return end
    
    -- Only allow self to manage own thorns list (unless promoted)
    if druidName ~= UnitName("player") and not ClassPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted (Leader/Assist) to manage others' Thorns list.")
        return
    end
    
    self.ContextName = druidName
    self.AssignMode = "Thorns"
    ToggleDropDownMenu(1, nil, ClassPowerDruidDropDown, btn, 0, 0)
end

function Druid:ThornsButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPDruidRow(%d+)ThornsList")
    if not rowIdx then return end
    
    local nameStr = getglobal("CPDruidRow"..rowIdx.."Name")
    local druidName = nameStr and nameStr:GetText()
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Thorns List")
    
    local thornsList = self.ThornsList[druidName]
    if thornsList and table.getn(thornsList) > 0 then
        GameTooltip:AddLine("Assigned targets:", 1, 1, 1)
        for _, name in ipairs(thornsList) do
            local status = self.CurrentBuffsByName[name]
            if status then
                if status.hasThorns then
                    GameTooltip:AddLine("  "..name.." |cff00ff00(buffed)|r", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("  "..name.." |cffff0000(missing)|r", 0.7, 0.7, 0.7)
                end
            else
                GameTooltip:AddLine("  "..name.." |cffffff00(not in raid)|r", 0.7, 0.7, 0.7)
            end
        end
    else
        GameTooltip:AddLine("Click to add targets", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Left-click: Add target", 0, 1, 0)
    GameTooltip:AddLine("Right-click on name: Remove", 1, 0.5, 0)
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

function Druid:UpdateLeaderButtons()
    if not self.ConfigWindow then return end
    
    local autoBtn = getglobal(self.ConfigWindow:GetName().."AutoAssignBtn")
    
    if ClassPower_IsPromoted() then
        if autoBtn then autoBtn:Show() end
    else
        if autoBtn then autoBtn:Hide() end
    end
end

function Druid:ResetUI()
    ClassPower_PerUser.DruidPoint = nil
    ClassPower_PerUser.DruidRelativePoint = nil
    ClassPower_PerUser.DruidX = nil
    ClassPower_PerUser.DruidY = nil
    ClassPower_PerUser.DruidScale = 0.7
    ClassPower_PerUser.DruidConfigScale = 1.0
    
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
-- Target Dropdown (Innervate & Thorns)
-----------------------------------------------------------------------------------

function Druid:TargetDropDown_Initialize(level)
    if not level then level = 1 end
    local info = {}
    local mode = self.AssignMode or "Innervate"
    
    if level == 1 then
        -- Clear option
        info = {}
        if mode == "Thorns" then
            info.text = ">> Clear All <<"
        else
            info.text = ">> Clear <<"
        end
        info.value = "CLEAR"
        info.func = function() Druid:AssignTarget_OnClick() end
        UIDropDownMenu_AddButton(info)
        
        -- For Thorns mode, show current list with remove option
        if mode == "Thorns" then
            local pname = self.ContextName or UnitName("player")
            local thornsList = self.ThornsList[pname]
            if thornsList and table.getn(thornsList) > 0 then
                info = {}
                info.text = "-- Current List --"
                info.isTitle = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info)
                
                for _, name in ipairs(thornsList) do
                    info = {}
                    info.text = "|cffff6600- "..name.."|r"
                    info.value = "REMOVE:"..name
                    info.func = function() Druid:AssignTarget_OnClick() end
                    UIDropDownMenu_AddButton(info)
                end
                
                info = {}
                info.text = "-- Add New --"
                info.isTitle = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info)
            end
            
            -- Add Tanks from TankList Option
            if ClassPower_TankList and table.getn(ClassPower_TankList) > 0 then
                info = {}
                info.text = "|cff00ff00+ Add All Tanks|r"
                info.value = "ADDTANKS"
                info.func = function() Druid:AssignTarget_OnClick() end
                UIDropDownMenu_AddButton(info)
            end
        end
        
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
    
    if mode == "Thorns" then
        -- Handle Thorns list
        if targetName == "ADDTANKS" then
            if ClassPower_TankList then
                local count = 0
                for _, tank in ipairs(ClassPower_TankList) do
                    -- Check if not already in list to avoid spamming "Added" messages locally if possible
                    -- But AddToThornsList handles duplicates gracefully (prints message though)
                    self:AddToThornsList(pname, tank.name)
                    ClassPower_SendMessage("DTHORNS ADD "..pname.." "..tank.name)
                    count = count + 1
                end
                if count > 0 then
                     DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Added all tanks to " .. pname .. "'s Thorns list.")
                     self:UpdateUI()
                end
            end
        elseif targetName == "CLEAR" then
            self:ClearThornsList(pname)
            ClassPower_SendMessage("DTHORNS CLEAR "..pname)
        elseif string.find(targetName, "^REMOVE:") then
            local _, _, removeName = string.find(targetName, "^REMOVE:(.*)")
            if removeName then
                self:RemoveFromThornsList(pname, removeName)
                ClassPower_SendMessage("DTHORNS REMOVE "..pname.." "..removeName)
            end
        else
            self:AddToThornsList(pname, targetName)
            ClassPower_SendMessage("DTHORNS ADD "..pname.." "..targetName)
        end
    else
        -- Handle Innervate (single target)
        self.LegacyAssignments[pname] = self.LegacyAssignments[pname] or {}
        
        if targetName == "CLEAR" then
            self.LegacyAssignments[pname]["Innervate"] = nil
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared Innervate for "..pname)
            ClassPower_SendMessage("DASSIGNTARGET "..pname.." nil")
        else
            self.LegacyAssignments[pname]["Innervate"] = targetName
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: "..pname.." Innervate = "..targetName)
            ClassPower_SendMessage("DASSIGNTARGET "..pname.." "..targetName)
        end
    end
    
    self:UpdateUI()
    CloseDropDownMenus()
    
    -- Save if this is for the current player
    if pname == UnitName("player") then
        self:SaveAssignments()
    end
end

-----------------------------------------------------------------------------------
-- Persistence (Save/Load Assignments)
-----------------------------------------------------------------------------------

function Druid:SaveAssignments()
    local pname = UnitName("player")
    if not pname then return end
    
    -- Initialize saved variable if needed
    if not ClassPower_DruidAssignments then
        ClassPower_DruidAssignments = {}
    end
    
    -- Save current player's group assignments (1-8)
    ClassPower_DruidAssignments.Assignments = self.Assignments[pname] or {}
    
    -- Save Innervate target
    local legacyData = self.LegacyAssignments[pname]
    if legacyData and legacyData["Innervate"] then
        ClassPower_DruidAssignments.InnervateTarget = legacyData["Innervate"]
    else
        ClassPower_DruidAssignments.InnervateTarget = nil
    end
    
    ClassPower_Debug("Druid: Saved assignments for "..pname)
end

function Druid:LoadAssignments()
    local pname = UnitName("player")
    if not pname then return end
    
    -- Check if we have saved data
    if not ClassPower_DruidAssignments then
        ClassPower_Debug("Druid: No saved assignments found")
        return
    end
    
    -- Load group assignments (1-8)
    if ClassPower_DruidAssignments.Assignments then
        self.Assignments[pname] = {}
        for grp = 1, 8 do
            local val = ClassPower_DruidAssignments.Assignments[grp]
            if val ~= nil then
                self.Assignments[pname][grp] = val
            end
        end
        ClassPower_Debug("Druid: Loaded group assignments")
    end
    
    -- Load Innervate target
    if ClassPower_DruidAssignments.InnervateTarget then
        self.LegacyAssignments[pname] = self.LegacyAssignments[pname] or {}
        self.LegacyAssignments[pname]["Innervate"] = ClassPower_DruidAssignments.InnervateTarget
        ClassPower_Debug("Druid: Loaded Innervate target: "..ClassPower_DruidAssignments.InnervateTarget)
    end
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("DRUID", Druid)
