-- ClassPower: Paladin Module
-- Buff management for Paladin class (Blessings by Class, Auras, Judgements)

local Paladin = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

-- Class IDs (matches PallyPower order for compatibility)
Paladin.ClassIDs = {
    [0] = "WARRIOR",
    [1] = "ROGUE",
    [2] = "PRIEST",
    [3] = "DRUID",
    [4] = "PALADIN",
    [5] = "HUNTER",
    [6] = "MAGE",
    [7] = "WARLOCK",
    [8] = "SHAMAN",
    [9] = "PET",
}

Paladin.ClassNames = {
    [0] = "Warrior",
    [1] = "Rogue",
    [2] = "Priest",
    [3] = "Druid",
    [4] = "Paladin",
    [5] = "Hunter",
    [6] = "Mage",
    [7] = "Warlock",
    [8] = "Shaman",
    [9] = "Pet",
}

-- Class textures (use built-in class icons or custom)
Paladin.ClassTextures = {
    [0] = "Interface\\Icons\\INV_Sword_27",        -- Warrior
    [1] = "Interface\\Icons\\INV_ThrowingKnife_04", -- Rogue
    [2] = "Interface\\Icons\\INV_Staff_30",        -- Priest
    [3] = "Interface\\Icons\\Ability_Druid_Maul",  -- Druid
    [4] = "Interface\\Icons\\INV_Hammer_01",       -- Paladin
    [5] = "Interface\\Icons\\INV_Weapon_Bow_07",   -- Hunter
    [6] = "Interface\\Icons\\INV_Staff_13",        -- Mage
    [7] = "Interface\\Icons\\Spell_Shadow_DeathCoil", -- Warlock
    [8] = "Interface\\Icons\\Spell_Nature_BloodLust", -- Shaman
    [9] = "Interface\\Icons\\Ability_Hunter_BeastCall", -- Pet
}

-- Blessings (Greater and Normal versions)
Paladin.Blessings = {
    [0] = { 
        greater = "Greater Blessing of Wisdom", 
        normal = "Blessing of Wisdom",
        short = "Wis",
    },
    [1] = { 
        greater = "Greater Blessing of Might", 
        normal = "Blessing of Might",
        short = "Mgt",
    },
    [2] = { 
        greater = "Greater Blessing of Salvation", 
        normal = "Blessing of Salvation",
        short = "Sal",
    },
    [3] = { 
        greater = "Greater Blessing of Light", 
        normal = "Blessing of Light",
        short = "Lgt",
    },
    [4] = { 
        greater = "Greater Blessing of Kings", 
        normal = "Blessing of Kings",
        short = "Kng",
    },
    [5] = { 
        greater = "Greater Blessing of Sanctuary", 
        normal = "Blessing of Sanctuary",
        short = "San",
    },
}

-- Blessing Icons (Greater blessings)
Paladin.BlessingIcons = {
    [0] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom",
    [1] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",  -- Might
    [2] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation",
    [3] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofLight",
    [4] = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
    [5] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSanctuary",
}

-- Normal blessing icons (5-min)
Paladin.NormalBlessingIcons = {
    [0] = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    [1] = "Interface\\Icons\\Spell_Holy_FistOfJustice",
    [2] = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
    [3] = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
    [4] = "Interface\\Icons\\Spell_Magic_MageArmor",
    [5] = "Interface\\Icons\\Spell_Nature_LightningShield",
}

-- Auras
Paladin.Auras = {
    [0] = { name = "Devotion Aura", short = "Dev" },
    [1] = { name = "Retribution Aura", short = "Ret" },
    [2] = { name = "Concentration Aura", short = "Con" },
    [3] = { name = "Shadow Resistance Aura", short = "ShR" },
    [4] = { name = "Frost Resistance Aura", short = "FrR" },
    [5] = { name = "Fire Resistance Aura", short = "FiR" },
    [6] = { name = "Sanctity Aura", short = "San" },
}

Paladin.AuraIcons = {
    [0] = "Interface\\Icons\\Spell_Holy_DevotionAura",
    [1] = "Interface\\Icons\\Spell_Holy_AuraOfLight",
    [2] = "Interface\\Icons\\Spell_Holy_MindSooth",
    [3] = "Interface\\Icons\\Spell_Shadow_SealOfKings",
    [4] = "Interface\\Icons\\Spell_Frost_WizardMark",
    [5] = "Interface\\Icons\\Spell_Fire_SealOfFire",
    [6] = "Interface\\Icons\\Spell_Holy_MindVision",
}

-- Judgements
Paladin.Judgements = {
    [0] = { name = "Judgement of Light", short = "Lgt" },
    [1] = { name = "Judgement of Wisdom", short = "Wis" },
    [2] = { name = "Judgement of the Crusader", short = "Cru" },
    [3] = { name = "Judgement of Justice", short = "Jus" },
}

Paladin.JudgementIcons = {
    [0] = "Interface\\Icons\\Spell_Holy_HealingAura",  -- Judgement of Light (Seal of Light icon)
    [1] = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
    [2] = "Interface\\Icons\\Spell_Holy_HolySmite",
    [3] = "Interface\\Icons\\Spell_Holy_SealOfWrath",
}

-----------------------------------------------------------------------------------
-- State
-----------------------------------------------------------------------------------

Paladin.AllPaladins = {}
Paladin.CurrentBuffsByClass = {}  -- { [classID] = { { name, unit, hasWisdom, hasMight, ... }, ... } }
Paladin.Assignments = {}          -- { [paladinName] = { [classID] = blessingID, ... } }
Paladin.AuraAssignments = {}      -- { [paladinName] = auraID }
Paladin.JudgementAssignments = {} -- { [paladinName] = judgementID }
Paladin.BuffTimestamps = {}       -- { [playerName] = { [blessingID] = { startTime=X, isGreater=bool } } }
Paladin.RankInfo = {}
Paladin.SymbolCount = 0           -- Symbol of Kings count
Paladin.TankList = {}             -- { "TankName1", "TankName2", ... } - tanks skip Salvation

-- Estimated durations
Paladin.BuffDurations = {
    Normal = 600,   -- 10 min
    Greater = 1800, -- 30 min
}

function Paladin:GetEstimatedTimeRemaining(playerName, blessingID)
    if not self.BuffTimestamps[playerName] then return nil end
    local startInfo = self.BuffTimestamps[playerName][blessingID]
    if not startInfo then return nil end
    
    local elapsed = GetTime() - startInfo.startTime
    local duration = startInfo.isGreater and self.BuffDurations.Greater or self.BuffDurations.Normal
    local remaining = duration - elapsed
    
    if remaining < 0 then remaining = 0 end
    return remaining
end

function Paladin:GetClassMinTimeRemaining(classID, blessingID)
    local minTime = nil
    if not self.CurrentBuffsByClass[classID] then return nil end
    
    for _, member in pairs(self.CurrentBuffsByClass[classID]) do
        if not member.dead then
            -- Only check if they HAVE the blessing
            if member[blessingID] then
                local remaining = self:GetEstimatedTimeRemaining(member.name, blessingID)
                if remaining then
                    if not minTime or remaining < minTime then
                        minTime = remaining
                    end
                end
            end
        end
    end
    return minTime
end

-- Timers
Paladin.UpdateTimer = 0
Paladin.LastRequest = 0
Paladin.RosterDirty = false
Paladin.RosterTimer = 0.5
Paladin.UIDirty = false

-- Context for dropdowns
Paladin.ContextName = nil
Paladin.ContextClass = nil

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Paladin:OnLoad()
    CP_Debug("Paladin:OnLoad()")
    
    -- Load saved assignments before anything else
    self:LoadAssignments()
    
    -- Initial spell scan
    self:ScanSpells()
    self:ScanRaid()
    self:ScanInventory()
    
    -- Create UI
    self:CreateBuffBar()
    self:CreateConfigWindow()
    
    -- Create dropdowns
    if not getglobal("ClassPowerPaladinAuraDropDown") then
        CreateFrame("Frame", "ClassPowerPaladinAuraDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerPaladinAuraDropDown, function(level) Paladin:AuraDropDown_Initialize(level) end, "MENU")
    
    if not getglobal("ClassPowerPaladinJudgeDropDown") then
        CreateFrame("Frame", "ClassPowerPaladinJudgeDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerPaladinJudgeDropDown, function(level) Paladin:JudgeDropDown_Initialize(level) end, "MENU")
    
    -- Tank List dropdown
    if not getglobal("ClassPowerPaladinTankDropDown") then
        CreateFrame("Frame", "ClassPowerPaladinTankDropDown", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ClassPowerPaladinTankDropDown, function(level) Paladin:TankDropDown_Initialize(level) end, "MENU")
    
    -- Load saved tank list
    self:LoadTankList()
    
    -- Request sync from other paladins
    self:RequestSync()
end

function Paladin:OnEvent(event)
    if event == "SPELLS_CHANGED" then
        self:ScanSpells()
        self:ScanInventory()
        self.UIDirty = true
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ScanSpells()
        self:ScanRaid()
        self:ScanInventory()
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
        
    elseif event == "BAG_UPDATE" then
        self:ScanInventory()
    end
end

function Paladin:OnUpdate(elapsed)
    if not elapsed then elapsed = 0.01 end
    
    -- Delayed roster scan
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
    elseif self.UIDirty then
        self.UIDirty = false
        if (self.BuffBar and self.BuffBar:IsVisible()) or 
           (self.ConfigWindow and self.ConfigWindow:IsVisible()) then
            self:UpdateUI()
        end
    end
end

function Paladin:OnSlashCommand(msg)
    if msg == "report" then
        self:ReportAssignments()
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
function Paladin:ShowConfig()
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

function Paladin:ScanSpells()
    local info = {}
    
    -- Initialize blessing info
    for id = 0, 5 do
        info[id] = nil
    end
    
    -- Scan for auras
    info.auras = {}
    for id = 0, 6 do
        info.auras[id] = false
    end
    
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        
        local rank = 0
        if spellRank then
            local _, _, r = string.find(spellRank, "Rank (%d+)")
            rank = tonumber(r) or 0
        end
        
        -- Check for Greater Blessings (preferred)
        for id = 0, 5 do
            if spellName == self.Blessings[id].greater then
                if not info[id] or rank > info[id].rank then
                    info[id] = { rank = rank, talent = 0, spellID = i, hasGreater = true }
                end
            end
        end
        
        -- Check for Normal Blessings (fallback if no Greater)
        for id = 0, 5 do
            if spellName == self.Blessings[id].normal then
                if not info[id] then
                    info[id] = { rank = rank, talent = 0, spellID = i, hasGreater = false }
                elseif not info[id].hasGreater and rank > info[id].rank then
                    info[id].rank = rank
                    info[id].spellID = i
                end
            end
        end
        
        -- Check for Auras
        for id = 0, 6 do
            if spellName == self.Auras[id].name then
                info.auras[id] = true
            end
        end
        
        i = i + 1
    end
    
    -- Check talents for improved blessings
    local numTabs = GetNumTalentTabs()
    for t = 1, numTabs do
        local numTalents = GetNumTalents(t)
        for ti = 1, numTalents do
            local nameTalent, _, _, _, currRank, _ = GetTalentInfo(t, ti)
            if nameTalent and string.find(nameTalent, "Improved Blessings") then
                if info[0] then info[0].talent = currRank end
                if info[1] then info[1].talent = currRank end
            end
        end
    end
    
    self.AllPaladins[UnitName("player")] = info
    self.RankInfo = info
    
    -- Debug: Show what blessings were found
    CP_Debug("Paladin:ScanSpells() found:")
    for id = 0, 5 do
        if info[id] then
            CP_Debug("  Blessing "..id.." ("..self.Blessings[id].short.."): rank "..info[id].rank..", greater="..(info[id].hasGreater and "yes" or "no"))
        end
    end
    
    -- Initialize assignments if needed
    if not self.Assignments[UnitName("player")] then
        self.Assignments[UnitName("player")] = {}
        for classID = 0, 9 do
            self.Assignments[UnitName("player")][classID] = -1
        end
    end
end

function Paladin:ScanInventory()
    local oldCount = self.SymbolCount
    self.SymbolCount = 0
    
    for bag = 0, 4 do
        local bagSlots = GetContainerNumSlots(bag)
        if bagSlots then
            for slot = 1, bagSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Symbol of Kings") then
                    local _, count = GetContainerItemInfo(bag, slot)
                    self.SymbolCount = self.SymbolCount + (count or 0)
                end
            end
        end
    end
    
    if self.SymbolCount ~= oldCount then
        self:SendSymbolCount()
    end
    
    if self.AllPaladins[UnitName("player")] then
        self.AllPaladins[UnitName("player")].symbols = self.SymbolCount
    end
end

-----------------------------------------------------------------------------------
-- Raid/Buff Scanning
-----------------------------------------------------------------------------------

function Paladin:ScanRaid()
    self.CurrentBuffsByClass = {}
    for classID = 0, 9 do
        self.CurrentBuffsByClass[classID] = {}
    end
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local foundPaladins = {}
    
    if UnitClass("player") == "Paladin" then
        foundPaladins[UnitName("player")] = true
    end
    
    local function UpdateTS(name, bID, hasBuff, isGreater)
        if not self.BuffTimestamps then self.BuffTimestamps = {} end
        if not self.BuffTimestamps[name] then self.BuffTimestamps[name] = {} end
        if hasBuff then
            if not self.BuffTimestamps[name][bID] then
                self.BuffTimestamps[name][bID] = { startTime = GetTime(), isGreater = isGreater }
            else
                -- Update isGreater status if it changed
                if self.BuffTimestamps[name][bID].isGreater ~= isGreater then
                    self.BuffTimestamps[name][bID].isGreater = isGreater
                    self.BuffTimestamps[name][bID].startTime = GetTime()
                end
            end
        else
            self.BuffTimestamps[name][bID] = nil
        end
    end
    
    local function ProcessUnit(unit, name, class)
        if not UnitExists(unit) or not name then return end
        
        local classID = self:GetClassID(class)
        if classID < 0 then return end
        
        if class == "PALADIN" then
            foundPaladins[name] = true
            if not self.AllPaladins[name] then
                self.AllPaladins[name] = {}
                for id = 0, 5 do
                    self.AllPaladins[name][id] = nil
                end
                self.AllPaladins[name].auras = {}
            end
        end
        
        local buffInfo = {
            name = name,
            unit = unit,
            class = class,
            visible = UnitIsVisible(unit),
            dead = UnitIsDeadOrGhost(unit),
        }
        
        for bID = 0, 5 do
            buffInfo[bID] = false
        end
        
        local isGreater = {}
        
        local b = 1
        while true do
            local buffTexture = UnitBuff(unit, b)
            if not buffTexture then break end
            
            buffTexture = string.lower(buffTexture)
            
            -- Wisdom: Normal=SealOfWisdom, Greater=GreaterBlessingofWisdom
            if string.find(buffTexture, "wisdom") then 
                buffInfo[0] = true 
                isGreater[0] = string.find(buffTexture, "greater") 
            end
            
            -- Might: Normal=FistOfJustice, Greater=GreaterBlessingofKings
            if string.find(buffTexture, "fistofjustice") or string.find(buffTexture, "greaterblessingofkings") then 
                buffInfo[1] = true
                isGreater[1] = string.find(buffTexture, "greater")
            end
            
            -- Salvation: Normal=SealOfSalvation, Greater=GreaterBlessingofSalvation
            if string.find(buffTexture, "salvation") then 
                buffInfo[2] = true
                isGreater[2] = string.find(buffTexture, "greater")
            end
            
            -- Light: Normal=PrayerOfHealing02, Greater=GreaterBlessingofLight
            if string.find(buffTexture, "prayerofhealing") or string.find(buffTexture, "greaterblessingoflight") then 
                buffInfo[3] = true 
                isGreater[3] = string.find(buffTexture, "greater")
            end
            
            -- Kings: Normal=MageArmor, Greater=Magic_GreaterBlessingofKings
            if string.find(buffTexture, "magearmor") or string.find(buffTexture, "magic_greaterblessingofkings") then 
                buffInfo[4] = true 
                isGreater[4] = string.find(buffTexture, "greater")
            end
            
            -- Sanctuary: Normal=LightningShield, Greater=GreaterBlessingofSanctuary
            if string.find(buffTexture, "lightningshield") or string.find(buffTexture, "sanctuary") then 
                buffInfo[5] = true
                isGreater[5] = string.find(buffTexture, "greater") or string.find(buffTexture, "sanctuary") -- Sanctuary is in both names, but LightningShield is normal
                if string.find(buffTexture, "lightningshield") then isGreater[5] = false end
            end
            
            b = b + 1
        end
        
        -- Update Timestamps (only if visible, otherwise we can't trust UnitBuff absence)
        if UnitIsVisible(unit) then
            for bID = 0, 5 do
                UpdateTS(name, bID, buffInfo[bID], isGreater[bID])
            end
        end
        
        table.insert(self.CurrentBuffsByClass[classID], buffInfo)
    end
    
    local function ProcessPet(unit)
        if not UnitExists(unit) then return end
        local name = UnitName(unit)
        if not name then return end
        
        local buffInfo = {
            name = name,
            unit = unit,
            class = "PET",
            visible = UnitIsVisible(unit),
            dead = UnitIsDeadOrGhost(unit),
        }
        
        for bID = 0, 5 do
            buffInfo[bID] = false
        end
        
        local isGreater = {}
        
        local b = 1
        while true do
            local buffTexture = UnitBuff(unit, b)
            if not buffTexture then break end
            buffTexture = string.lower(buffTexture)
            
            if string.find(buffTexture, "wisdom") then buffInfo[0] = true; isGreater[0] = string.find(buffTexture, "greater") end
            if string.find(buffTexture, "fistofjustice") or string.find(buffTexture, "greaterblessingofkings") then buffInfo[1] = true; isGreater[1] = string.find(buffTexture, "greater") end
            if string.find(buffTexture, "salvation") then buffInfo[2] = true; isGreater[2] = string.find(buffTexture, "greater") end
            if string.find(buffTexture, "prayerofhealing") or string.find(buffTexture, "greaterblessingoflight") then buffInfo[3] = true; isGreater[3] = string.find(buffTexture, "greater") end
            if string.find(buffTexture, "magearmor") or string.find(buffTexture, "magic_greaterblessingofkings") then buffInfo[4] = true; isGreater[4] = string.find(buffTexture, "greater") end
            if string.find(buffTexture, "lightningshield") or string.find(buffTexture, "sanctuary") then 
                buffInfo[5] = true
                isGreater[5] = (not string.find(buffTexture, "lightningshield"))
            end
            
            b = b + 1
        end
        
        -- Update Timestamps (only if visible)
        if UnitIsVisible(unit) then
            for bID = 0, 5 do
                UpdateTS(name, bID, buffInfo[bID], isGreater[bID])
            end
        end
        
        table.insert(self.CurrentBuffsByClass[9], buffInfo)
    end
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            ProcessUnit("raid"..i, name, class)
            
            local petUnit = "raidpet"..i
            if UnitExists(petUnit) then
                ProcessPet(petUnit)
            end
        end
    elseif numParty > 0 then
        local _, pClass = UnitClass("player")
        ProcessUnit("player", UnitName("player"), pClass)
        
        if UnitExists("pet") then ProcessPet("pet") end
        
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            ProcessUnit("party"..i, name, class)
            
            local petUnit = "partypet"..i
            if UnitExists(petUnit) then ProcessPet(petUnit) end
        end
    else
        local _, pClass = UnitClass("player")
        ProcessUnit("player", UnitName("player"), pClass)
        if UnitExists("pet") then ProcessPet("pet") end
    end
    
    for name, _ in pairs(self.AllPaladins) do
        if not foundPaladins[name] then
            self.AllPaladins[name] = nil
            self.Assignments[name] = nil
            self.AuraAssignments[name] = nil
            self.JudgementAssignments[name] = nil
        end
    end
end

function Paladin:GetClassID(class)
    for id, name in pairs(self.ClassIDs) do
        if name == class then
            return id
        end
    end
    return -1
end

-----------------------------------------------------------------------------------
-- Tank List (for Salvation exemptions)
-----------------------------------------------------------------------------------

function Paladin:IsTank(playerName)
    for _, tank in ipairs(self.TankList) do
        if tank == playerName then
            return true
        end
    end
    return false
end

function Paladin:AddToTankList(playerName)
    if not self:IsTank(playerName) then
        table.insert(self.TankList, playerName)
        self:SaveTankList()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Added "..playerName.." to Tank List")
    end
end

function Paladin:RemoveFromTankList(playerName)
    for i, tank in ipairs(self.TankList) do
        if tank == playerName then
            table.remove(self.TankList, i)
            self:SaveTankList()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Removed "..playerName.." from Tank List")
            return
        end
    end
end

function Paladin:ClearTankList()
    self.TankList = {}
    self:SaveTankList()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Tank List cleared")
end

function Paladin:SaveTankList()
    CP_PerUser.PaladinTankList = self.TankList
end

function Paladin:LoadTankList()
    if CP_PerUser.PaladinTankList then
        self.TankList = CP_PerUser.PaladinTankList
    end
end

-----------------------------------------------------------------------------------
-- Auto-Assign
-----------------------------------------------------------------------------------

-- Class needs reference (blessing IDs: 0=Wisdom, 1=Might, 2=Salvation, 3=Light, 4=Kings, 5=Sanctuary)
Paladin.ClassBlessingNeeds = {
    -- [classID] = { blessingID = true/false }
    [0] = { [0]=false, [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Warrior (no Wisdom)
    [1] = { [0]=false, [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Rogue (no Wisdom)
    [2] = { [0]=true,  [1]=false, [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Priest (no Might)
    [3] = { [0]=true,  [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Druid (all)
    [4] = { [0]=true,  [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Paladin (all)
    [5] = { [0]=true,  [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Hunter (all - uses mana)
    [6] = { [0]=true,  [1]=false, [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Mage (no Might)
    [7] = { [0]=true,  [1]=false, [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Warlock (no Might)
    [8] = { [0]=true,  [1]=true,  [2]=true,  [3]=true, [4]=true, [5]=true  }, -- Shaman (all)
    [9] = { [0]=false, [1]=true,  [2]=false, [3]=false,[4]=true, [5]=false }, -- Pet (Kings, Might only)
}

function Paladin:AutoAssign()
    if not ClassPower_IsPromoted() then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Auto-assign requires Leader/Assist.")
        return
    end
    
    -- Load tank list
    self:LoadTankList()
    
    -- Get list of classes present in raid
    local classesPresent = {}
    for classID = 0, 9 do
        if self.CurrentBuffsByClass[classID] and table.getn(self.CurrentBuffsByClass[classID]) > 0 then
            classesPresent[classID] = true
        end
    end
    
    -- Get list of Paladins and their capabilities
    local paladins = {}
    for paladinName, info in pairs(self.AllPaladins) do
        local pdata = {
            name = paladinName,
            blessings = {},
            hasImprovedBlessings = false,
        }
        for bID = 0, 5 do
            if info[bID] then
                pdata.blessings[bID] = true
                -- Check for Improved Blessings talent
                if info[bID].talent and info[bID].talent > 0 then
                    pdata.hasImprovedBlessings = true
                end
            end
        end
        table.insert(paladins, pdata)
    end
    
    if table.getn(paladins) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No Paladins found.")
        return
    end
    
    -- Clear all existing blessing assignments
    for _, pdata in ipairs(paladins) do
        self.Assignments[pdata.name] = {}
        for classID = 0, 9 do
            self.Assignments[pdata.name][classID] = -1
        end
    end
    
    -- Track which Paladins are assigned to which blessings
    local blessingAssignments = {} -- { [blessingID] = paladinName }
    local usedPaladins = {}
    
    -- Priority: Salvation(2) > Kings(4) > Might(1)/Wisdom(0) > Light(3) > Sanctuary(5)
    local priorityOrder = { 2, 4, 1, 0, 3, 5 }
    
    -- Find a free Paladin with the blessing
    local function findPaladinWithBlessing(blessingID, preferImproved)
        -- First pass: Look for unused paladins
        for _, pdata in ipairs(paladins) do
            if pdata.blessings[blessingID] and not usedPaladins[pdata.name] then
                if preferImproved and pdata.hasImprovedBlessings then
                    return pdata
                end
                return pdata -- Return first unused match
            end
        end
        
        -- Second pass: Reuse paladins
        for _, pdata in ipairs(paladins) do
            if pdata.blessings[blessingID] then
                return pdata
            end
        end
        return nil
    end
    
    -- Check tank status for each class
    local classSkipsSalvation = {}
    for classID = 0, 9 do
        local members = self.CurrentBuffsByClass[classID]
        if members and table.getn(members) > 0 then
            local allTanks = true
            for _, info in ipairs(members) do
                if not self:IsTank(info.name) then
                    allTanks = false
                    break
                end
            end
            if allTanks then
                classSkipsSalvation[classID] = true
            end
        end
    end
    
    local classesSatisfied = {}

    -- Assign blessings in priority order
    for _, bID in ipairs(priorityOrder) do
        -- Special handling for Might/Wisdom overlap on hybrids
        local preferImproved = (bID == 0 or bID == 1) -- Prefer improved for Might/Wisdom
        
        local paladin = findPaladinWithBlessing(bID, preferImproved)
        if paladin then
            usedPaladins[paladin.name] = true
            blessingAssignments[bID] = paladin.name
            
            -- Assign this blessing to all classes that need it
            for classID = 0, 9 do
                if classesPresent[classID] and not classesSatisfied[classID] then
                    local needs = self.ClassBlessingNeeds[classID]
                    -- Skip Salvation if class is all tanks
                    local skipSalvation = (bID == 2 and classSkipsSalvation[classID])
                    
                    -- For Paladin Tanks (ID 4), prefer Sanctuary(5) over Might(1)/Wisdom(0)/Light(3)
                    -- Kings(4) is still preferred as it is higher priority than 1/0/3/5.
                    local skipForTank = false
                    if classID == 4 and classSkipsSalvation[classID] and (bID == 1 or bID == 0 or bID == 3) then
                        skipForTank = true
                    end
                    
                    if needs and needs[bID] and not skipSalvation and not skipForTank then
                        self.Assignments[paladin.name][classID] = bID
                        classesSatisfied[classID] = true
                    end
                end
            end
        end
    end
    
    -- Broadcast assignments
    for paladinName, assigns in pairs(self.Assignments) do
        for classID = 0, 9 do
            local bID = assigns[classID]
            if bID and bID >= 0 then
                ClassPower_SendMessage("PASSIGN "..paladinName.." "..classID.." "..bID)
            end
        end
    end
    
    -- Report
    local msgs = {}
    for bID, paladinName in pairs(blessingAssignments) do
        table.insert(msgs, paladinName.." -> "..self.Blessings[bID].short)
    end
    
    if table.getn(msgs) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Auto-assigned: "..table.concat(msgs, ", "))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No blessings could be assigned.")
    end
    
    -- Update UI
    self:UpdateConfigGrid()
end

-----------------------------------------------------------------------------------
-- Sync Protocol
-----------------------------------------------------------------------------------

function Paladin:RequestSync()
    ClassPower_SendMessage("PREQ")
end

function Paladin:SendSelf()
    local pname = UnitName("player")
    local myInfo = self.AllPaladins[pname]
    if not myInfo then return end
    
    local msg = "PSELF "
    
    for id = 0, 5 do
        if myInfo[id] then
            msg = msg .. (myInfo[id].rank or 0) .. (myInfo[id].talent or 0)
        else
            msg = msg .. "nn"
        end
    end
    msg = msg .. "@"
    
    local assigns = self.Assignments[pname] or {}
    for classID = 0, 9 do
        local bid = assigns[classID]
        if bid and bid >= 0 then
            msg = msg .. bid
        else
            msg = msg .. "n"
        end
    end
    msg = msg .. "@"
    
    local aura = self.AuraAssignments[pname]
    if aura and aura >= 0 then
        msg = msg .. aura
    else
        msg = msg .. "n"
    end
    msg = msg .. "@"
    
    local judge = self.JudgementAssignments[pname]
    if judge and judge >= 0 then
        msg = msg .. judge
    else
        msg = msg .. "n"
    end
    
    ClassPower_SendMessage(msg)
end

function Paladin:SendSymbolCount()
    ClassPower_SendMessage("PSYM "..self.SymbolCount)
end

function Paladin:OnAddonMessage(sender, msg)
    if sender == UnitName("player") then return end
    
    if msg == "PREQ" then
        self:SendSelf()
        self:SendSymbolCount()
        
    elseif string.find(msg, "^PSELF") then
        local _, _, blessings, classAssigns, aura, judge = string.find(msg, "PSELF (.-)@(.-)@(.-)@(.*)")
        if not blessings then return end
        
        self.AllPaladins[sender] = self.AllPaladins[sender] or {}
        local info = self.AllPaladins[sender]
        
        for id = 0, 5 do
            local r = string.sub(blessings, id*2+1, id*2+1)
            local t = string.sub(blessings, id*2+2, id*2+2)
            if r ~= "n" then
                info[id] = { rank = tonumber(r) or 0, talent = tonumber(t) or 0 }
            else
                info[id] = nil
            end
        end
        
        self.Assignments[sender] = self.Assignments[sender] or {}
        for classID = 0, 9 do
            local val = string.sub(classAssigns, classID + 1, classID + 1)
            if val ~= "n" and val ~= "" then
                self.Assignments[sender][classID] = tonumber(val) or -1
            else
                self.Assignments[sender][classID] = -1
            end
        end
        
        if aura and aura ~= "n" and aura ~= "" then
            self.AuraAssignments[sender] = tonumber(aura)
        else
            self.AuraAssignments[sender] = nil
        end
        
        if judge and judge ~= "n" and judge ~= "" then
            self.JudgementAssignments[sender] = tonumber(judge)
        else
            self.JudgementAssignments[sender] = nil
        end
        
        self.UIDirty = true
        
    elseif string.find(msg, "^PASSIGN ") then
        local _, _, name, classID, blessID = string.find(msg, "^PASSIGN (.-) (.-) (.*)")
        if name and classID and blessID then
            if sender == name or ClassPower_IsPromoted(sender) then
                self.Assignments[name] = self.Assignments[name] or {}
                self.Assignments[name][tonumber(classID)] = tonumber(blessID)
                self.UIDirty = true
            end
        end
        
    elseif string.find(msg, "^PAURA ") then
        local _, _, name, auraID = string.find(msg, "^PAURA (.-) (.*)")
        if name and auraID then
            if sender == name or ClassPower_IsPromoted(sender) then
                if auraID == "n" then
                    self.AuraAssignments[name] = nil
                else
                    self.AuraAssignments[name] = tonumber(auraID)
                end
                self.UIDirty = true
            end
        end
        
    elseif string.find(msg, "^PJUDGE ") then
        local _, _, name, judgeID = string.find(msg, "^PJUDGE (.-) (.*)")
        if name and judgeID then
            if sender == name or ClassPower_IsPromoted(sender) then
                if judgeID == "n" then
                    self.JudgementAssignments[name] = nil
                else
                    self.JudgementAssignments[name] = tonumber(judgeID)
                end
                self.UIDirty = true
            end
        end
        
    elseif string.find(msg, "^PSYM ") then
        local _, _, count = string.find(msg, "^PSYM (.*)")
        if count and self.AllPaladins[sender] then
            self.AllPaladins[sender].symbols = tonumber(count) or 0
        end
        
    elseif string.find(msg, "^PCLEAR ") then
        local _, _, target = string.find(msg, "^PCLEAR (.*)")
        if target then
            if sender == target or ClassPower_IsPromoted(sender) then
                self.Assignments[target] = {}
                for classID = 0, 9 do
                    self.Assignments[target][classID] = -1
                end
                self.AuraAssignments[target] = nil
                self.JudgementAssignments[target] = nil
                if target == UnitName("player") then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Assignments cleared by "..sender)
                end
                self.UIDirty = true
            end
        end
    end
end

-----------------------------------------------------------------------------------
-- Assignment Helpers
-----------------------------------------------------------------------------------

function Paladin:CanBuff(paladinName, blessingID)
    -- -1 means "none" which is always valid
    if blessingID < 0 or blessingID > 5 then return true end
    
    local info = self.AllPaladins[paladinName]
    
    -- If we don't have info about this paladin's blessings yet,
    -- assume they can cast all blessings (we'll find out when they sync)
    if not info then return true end
    
    -- Check if paladin has this blessing (either normal or greater)
    -- If info[blessingID] exists, they have it
    -- If info doesn't have numeric keys yet (just joined), allow all
    if info[blessingID] then
        return true
    end
    
    -- Check if this paladin has ANY blessing info - if not, allow all
    local hasAnyBlessingInfo = false
    for id = 0, 5 do
        if info[id] ~= nil then
            hasAnyBlessingInfo = true
            break
        end
    end
    
    -- If we have no blessing info for this paladin, assume they can do everything
    if not hasAnyBlessingInfo then
        return true
    end
    
    return false
end

function Paladin:NeedsBuff(classID, blessingID)
    -- -1 means "none" which is always valid to cycle to
    if blessingID < 0 then return true end
    
    -- Smart buffs: Skip inappropriate blessings
    -- No Wisdom for Warriors and Rogues (they don't use mana)
    if (classID == 0 or classID == 1) and blessingID == 0 then
        return false
    end
    
    -- No Might for casters (Priests, Mages, Warlocks)
    if (classID == 2 or classID == 6 or classID == 7) and blessingID == 1 then
        return false
    end
    
    return true
end

function Paladin:CycleBlessingForward(paladinName, classID)
    if not self.Assignments[paladinName] then
        self.Assignments[paladinName] = {}
    end
    
    local cur = self.Assignments[paladinName][classID] or -1
    local found = false
    
    -- Try to find next valid blessing
    for test = cur + 1, 5 do
        if self:CanBuff(paladinName, test) and self:NeedsBuff(classID, test) then
            cur = test
            found = true
            break
        end
    end
    
    -- If nothing found, wrap to -1 (none)
    if not found then
        cur = -1
    end
    
    self.Assignments[paladinName][classID] = cur
    ClassPower_SendMessage("PASSIGN "..paladinName.." "..classID.." "..cur)
    self:UpdateUI()
    
    -- Save if this is for the current player
    if paladinName == UnitName("player") then
        self:SaveAssignments()
    end
end

function Paladin:CycleBlessingForwardAllClasses(paladinName, referenceClassID)
    if not self.Assignments[paladinName] then
        self.Assignments[paladinName] = {}
    end
    
    -- Get current blessing for this class (use Paladin class=4 as reference if possible since all blessings work on Paladins)
    local cur = self.Assignments[paladinName][referenceClassID] or -1
    local found = false
    local newBlessing = -1
    
    -- Find next valid blessing that the paladin knows (ignore smart buffs for mass assignment)
    for test = cur + 1, 5 do
        if self:CanBuff(paladinName, test) then
            newBlessing = test
            found = true
            break
        end
    end
    
    -- If nothing found, wrap to -1 (none)
    if not found then
        newBlessing = -1
    end
    
    -- Apply to ALL classes
    for classID = 0, 9 do
        self.Assignments[paladinName][classID] = newBlessing
        ClassPower_SendMessage("PASSIGN "..paladinName.." "..classID.." "..newBlessing)
    end
    
    if newBlessing >= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Set "..self.Blessings[newBlessing].short.." for all classes")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared blessing for all classes")
    end
    
    self:UpdateUI()
    
    -- Save if this is for the current player
    if paladinName == UnitName("player") then
        self:SaveAssignments()
    end
end

-----------------------------------------------------------------------------------
-- UI: Buff Bar
-----------------------------------------------------------------------------------

function Paladin:CreateBuffBar()
    if getglobal("ClassPowerPaladinBuffBar") then 
        self.BuffBar = getglobal("ClassPowerPaladinBuffBar")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerPaladinBuffBar", UIParent)
    f:SetFrameStrata("LOW")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetWidth(160)
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
    title:SetText("Paladin")
    f.title = title
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
        if arg1 == "RightButton" then
            -- Right-click opens config
            if Paladin.ConfigWindow then
                if Paladin.ConfigWindow:IsVisible() then
                    Paladin.ConfigWindow:Hide()
                else
                    Paladin.ConfigWindow:Show()
                    Paladin:UpdateConfigGrid()
                end
            end
        else
            Paladin:SaveBuffBarPosition()
        end
    end)
    
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Paladin:SaveBuffBarPosition()
    end)
    
    for i = 0, 11 do
        local row = self:CreateHUDRow(f, "ClassPowerPaladinHUDRow"..i, i)
        row:Hide()
    end
    
    if CP_PerUser.PaladinPoint then
        f:ClearAllPoints()
        f:SetPoint(CP_PerUser.PaladinPoint, "UIParent", CP_PerUser.PaladinRelativePoint or "CENTER", 
                   CP_PerUser.PaladinX or 0, CP_PerUser.PaladinY or 0)
    else
        f:SetPoint("CENTER", 0, 0)
    end
    
    if CP_PerUser.PaladinScale then
        f:SetScale(CP_PerUser.PaladinScale)
    else
        f:SetScale(0.7)
    end
    
    self.BuffBar = f
end

function Paladin:CreateHUDRow(parent, name, id)
    local f = CreateFrame("Button", name, parent)
    f:SetWidth(150)
    f:SetHeight(34)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    local classIcon = f:CreateTexture(f:GetName().."ClassIcon", "ARTWORK")
    classIcon:SetWidth(24)
    classIcon:SetHeight(24)
    classIcon:SetPoint("LEFT", f, "LEFT", 5, 0)
    
    local buffIcon = f:CreateTexture(f:GetName().."BuffIcon", "ARTWORK")
    buffIcon:SetWidth(24)
    buffIcon:SetHeight(24)
    buffIcon:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
    
    local text = f:CreateFontString(f:GetName().."Text", "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", buffIcon, "RIGHT", 4, 0)
    -- text:SetWidth(50) -- Dynamic width
    text:SetJustifyH("LEFT")
    
    f:SetScript("OnClick", function() Paladin:HUDRow_OnClick(this) end)
    f:SetScript("OnEnter", function() Paladin:HUDRow_OnEnter(this) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    f.classID = id
    f.blessingID = -1
    f.need = {}
    f.have = {}
    f.dead = {}
    
    return f
end

function Paladin:SaveBuffBarPosition()
    if not self.BuffBar then return end
    local point, _, relativePoint, x, y = self.BuffBar:GetPoint()
    CP_PerUser.PaladinPoint = point
    CP_PerUser.PaladinRelativePoint = relativePoint
    CP_PerUser.PaladinX = x
    CP_PerUser.PaladinY = y
    CP_PerUser.PaladinScale = self.BuffBar:GetScale()
end

function Paladin:SaveConfigPosition()
    if not self.ConfigWindow then return end
    CP_PerUser.PaladinConfigScale = self.ConfigWindow:GetScale()
end

function Paladin:UpdateBuffBar()
    if not self.BuffBar then return end
    
    local f = self.BuffBar
    local pname = UnitName("player")
    local assigns = self.Assignments[pname] or {}
    
    f.title:SetText("Paladin ("..self.SymbolCount..")")
    
    local lastRow = nil
    local count = 0
    
    for classID = 0, 9 do
        local row = getglobal("ClassPowerPaladinHUDRow"..classID)
        if not row then break end
        
        local blessingID = assigns[classID]
        local showRow = false
        
        if blessingID and blessingID >= 0 then
            local members = self.CurrentBuffsByClass[classID] or {}
            local nneed = 0
            local nhave = 0
            local ndead = 0
            
            row.need = {}
            row.have = {}
            row.dead = {}
            
            for _, member in pairs(members) do
                if member.visible then
                    if not member[blessingID] then
                        if member.dead then
                            ndead = ndead + 1
                            table.insert(row.dead, member.name)
                        else
                            nneed = nneed + 1
                            table.insert(row.need, member.name)
                        end
                    else
                        nhave = nhave + 1
                        table.insert(row.have, member.name)
                    end
                end
            end
            
            if nneed > 0 or nhave > 0 then
                showRow = true
                row.classID = classID
                row.blessingID = blessingID
                
                local classIcon = getglobal(row:GetName().."ClassIcon")
                local buffIcon = getglobal(row:GetName().."BuffIcon")
                local text = getglobal(row:GetName().."Text")
                
                classIcon:SetTexture(self.ClassTextures[classID])
                buffIcon:SetTexture(self.BlessingIcons[blessingID])
                
                if ndead > 0 then
                    text:SetText(nneed.." ("..ndead..")")
                else
                    text:SetText(nneed)
                end
                
                if nhave == 0 then
                    text:SetTextColor(1, 0, 0)
                elseif nneed > 0 then
                    text:SetTextColor(1, 1, 0)
                else
                    text:SetTextColor(0, 1, 0)
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
    
    local newHeight = 25 + (count * 34)
    if newHeight < 40 then newHeight = 40 end
    f:SetHeight(newHeight)
end

function Paladin:HUDRow_OnClick(row)
    if not row.blessingID or row.blessingID < 0 then return end
    
    local pname = UnitName("player")
    local myInfo = self.AllPaladins[pname]
    if not myInfo or not myInfo[row.blessingID] then return end
    
    local isRightClick = (arg1 == "RightButton")
    local spellName = isRightClick and self.Blessings[row.blessingID].normal or self.Blessings[row.blessingID].greater
    
    local members = self.CurrentBuffsByClass[row.classID] or {}
    for _, member in pairs(members) do
        if member.visible and not member.dead then
            local shouldCast = false
            if isRightClick then
                if not member[row.blessingID] then shouldCast = true end
            else
                shouldCast = true -- Always try to cast Greater Blessing if button clicked
            end
            
            if shouldCast then
                ClearTarget()
                TargetByName(member.name, true)
                if UnitName("target") == member.name then
                    if CheckInteractDistance("target", 4) then
                        CastSpellByName(spellName)
                        
                        -- Reset timestamps for responsiveness
                        if not isRightClick then
                             -- Greater Blessing: Reset for everyone in class
                             if self.BuffTimestamps then
                                 for _, m in pairs(members) do
                                     if not self.BuffTimestamps[m.name] then self.BuffTimestamps[m.name] = {} end
                                     -- Assume success and update timer
                                     self.BuffTimestamps[m.name][row.blessingID] = { startTime = GetTime(), isGreater = true }
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
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: No targets in range for "..self.ClassNames[row.classID])
end

function Paladin:HUDRow_OnEnter(row)
    if not row.blessingID or row.blessingID < 0 then return end
    
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.ClassNames[row.classID]..": "..self.Blessings[row.blessingID].short, 1, 1, 1)
    GameTooltip:AddLine("Have: "..table.concat(row.have or {}, ", "), 0.5, 1, 0.5)
    GameTooltip:AddLine("Need: "..table.concat(row.need or {}, ", "), 1, 0.5, 0.5)
    GameTooltip:AddLine("Dead: "..table.concat(row.dead or {}, ", "), 1, 0, 0)
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Left-click: Greater Blessing", 0, 1, 0)
    GameTooltip:AddLine("Right-click: Normal Blessing", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-----------------------------------------------------------------------------------
-- UI: Config Window
-----------------------------------------------------------------------------------

function Paladin:CreateConfigWindow()
    if getglobal("ClassPowerPaladinConfig") then 
        self.ConfigWindow = getglobal("ClassPowerPaladinConfig")
        return 
    end
    
    local f = CreateFrame("Frame", "ClassPowerPaladinConfig", UIParent)
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
    title:SetText("ClassPower - Paladin Configuration")
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    
    -- Add resize grip for scaling
    local grip = CP_CreateResizeGrip(f, f:GetName().."ResizeGrip")
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    grip:SetScript("OnMouseUp", function()
        local p = this:GetParent()
        p.isResizing = false
        this:SetScript("OnUpdate", nil)
        Paladin:SaveConfigPosition()
    end)
    
    local headerY = -48
    
    local lblPaladin = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblPaladin:SetPoint("TOPLEFT", f, "TOPLEFT", 25, headerY)
    lblPaladin:SetText("Paladin")
    
    -- Sym header with tooltip
    local lblSymFrame = CreateFrame("Frame", nil, f)
    lblSymFrame:SetWidth("30")
    lblSymFrame:SetHeight("16")
    lblSymFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 95, headerY)
    
    local lblSymbols = lblSymFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblSymbols:SetAllPoints(lblSymFrame)
    lblSymbols:SetText("Sym")
    
    lblSymFrame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Symbol of Kings", 1, 1, 1)
        GameTooltip:AddLine("Reagent count for Greater Blessings", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Each Greater Blessing consumes one Symbol.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Buy from reagent vendors (~1g each).", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    lblSymFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local classX = 125
    for classID = 0, 9 do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", classX + (classID * 48), headerY)
        lbl:SetText(string.sub(self.ClassNames[classID], 1, 3))
    end
    
    local lblAura = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblAura:SetPoint("TOPLEFT", f, "TOPLEFT", classX + (10 * 48), headerY)
    lblAura:SetText("Aura")
    
    local lblJudge = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblJudge:SetPoint("TOPLEFT", f, "TOPLEFT", classX + (10 * 48) + 50, headerY)
    lblJudge:SetText("Judge")
    
    for i = 1, 10 do
        self:CreateConfigRow(f, i)
    end
    
    -- Apply saved scale
    if CP_PerUser.PaladinConfigScale then
        f:SetScale(CP_PerUser.PaladinConfigScale)
    else
        f:SetScale(1.0)
    end
    
    -- Add Settings button
    local btnSettings = CreateFrame("Button", "CPPaladinSettingsBtn", f, "UIPanelButtonTemplate")
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
        Paladin:AutoAssign()
    end)
    autoBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Assign Blessings")
        GameTooltip:AddLine("Automatically distribute blessings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("based on class needs and priority.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Priority: Salv > Kings > Might/Wis > Light > Sanc", 1, 0.82, 0)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Requires Leader/Assist", 1, 0.5, 0)
        GameTooltip:Show()
    end)
    autoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Tank List button
    local tankBtn = CreateFrame("Button", f:GetName().."TankListBtn", f, "UIPanelButtonTemplate")
    tankBtn:SetWidth(80)
    tankBtn:SetHeight(24)
    tankBtn:SetPoint("LEFT", autoBtn, "RIGHT", 10, 0)
    tankBtn:SetText("Tank List")
    tankBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, ClassPowerPaladinTankDropDown, this, 0, 0)
    end)
    tankBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tank List")
        GameTooltip:AddLine("Players on this list will skip", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Salvation assignments.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Current: "..table.getn(Paladin.TankList).." tanks", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    tankBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Update visibility based on promotion status
    f:SetScript("OnShow", function()
        local autoAssignBtn = getglobal(this:GetName().."AutoAssignBtn")
        local tankListBtn = getglobal(this:GetName().."TankListBtn")
        if ClassPower_IsPromoted() then
            if autoAssignBtn then autoAssignBtn:Show() end
            if tankListBtn then tankListBtn:Show() end
        else
            if autoAssignBtn then autoAssignBtn:Hide() end
            if tankListBtn then tankListBtn:Hide() end
        end
    end)
    
    f:Hide()
    self.ConfigWindow = f
end

function Paladin:CreateConfigRow(parent, rowIndex)
    local rowName = "CPPaladinRow"..rowIndex
    local row = CreateFrame("Frame", rowName, parent)
    row:SetWidth(730)
    row:SetHeight(60)  -- Height for name + capability icons + class buttons
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -65 - (rowIndex-1)*62)
    
    local clearBtn = CP_CreateClearButton(row, rowName.."Clear")
    clearBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
    clearBtn:SetScript("OnClick", function() Paladin:ClearButton_OnClick(this) end)
    
    -- Paladin name (top line)
    local nameStr = row:CreateFontString(rowName.."Name", "OVERLAY", "GameFontHighlight")
    nameStr:SetPoint("TOPLEFT", row, "TOPLEFT", 15, -4)
    nameStr:SetWidth(65)
    nameStr:SetHeight(14)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("")
    
    -- Symbol count (next to name)
    local symStr = row:CreateFontString(rowName.."Symbols", "OVERLAY", "GameFontHighlightSmall")
    symStr:SetPoint("TOPLEFT", row, "TOPLEFT", 83, -4)
    symStr:SetWidth(25)
    symStr:SetText("")
    symStr:SetTextColor(1, 1, 0.5)
    
    -- Capability icons row (below name, shows which blessings the paladin knows)
    local capX = 15
    for blessID = 0, 5 do
        local capIcon = CreateFrame("Frame", rowName.."Cap"..blessID, row)
        capIcon:SetWidth(16)
        capIcon:SetHeight(16)
        capIcon:SetPoint("TOPLEFT", row, "TOPLEFT", capX + (blessID * 17), -18)
        
        local tex = capIcon:CreateTexture(capIcon:GetName().."Icon", "ARTWORK")
        tex:SetWidth(14)
        tex:SetHeight(14)
        tex:SetPoint("CENTER", capIcon, "CENTER", 0, 0)
        tex:SetTexture(self.NormalBlessingIcons[blessID])
        
        local rankText = capIcon:CreateFontString(capIcon:GetName().."Rank", "OVERLAY", "GameFontNormalSmall")
        rankText:SetPoint("BOTTOMRIGHT", capIcon, "BOTTOMRIGHT", 3, -3)
        rankText:SetText("")
        
        capIcon:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local bID = blessID
            GameTooltip:SetText(Paladin.Blessings[bID].normal, 1, 1, 1)
            GameTooltip:Show()
        end)
        capIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    -- Class assignment buttons (start after capability icons area)
    local classX = 110
    for classID = 0, 9 do
        local btn = CreateFrame("Button", rowName.."Class"..classID, row)
        btn:SetWidth(44)
        btn:SetHeight(40)
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", classX + (classID * 48), -16)
        
        local bg = btn:CreateTexture(btn:GetName().."Background", "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture(0.1, 0.1, 0.1, 0.5)
        
        local icon = btn:CreateTexture(btn:GetName().."Icon", "ARTWORK")
        icon:SetWidth(32)
        icon:SetHeight(32)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:EnableMouseWheel(true)
        btn:SetScript("OnClick", function() Paladin:ClassButton_OnClick(this) end)
        btn:SetScript("OnMouseWheel", function() Paladin:ClassButton_OnMouseWheel(this, arg1) end)
        btn:SetScript("OnEnter", function() Paladin:ClassButton_OnEnter(this) end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    local auraBtn = CreateFrame("Button", rowName.."Aura", row)
    auraBtn:SetWidth(44)
    auraBtn:SetHeight(40)
    auraBtn:SetPoint("TOPLEFT", row, "TOPLEFT", classX + (10 * 48), -16)
    
    local auraBg = auraBtn:CreateTexture(auraBtn:GetName().."Background", "BACKGROUND")
    auraBg:SetAllPoints(auraBtn)
    auraBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    
    local auraIcon = auraBtn:CreateTexture(auraBtn:GetName().."Icon", "ARTWORK")
    auraIcon:SetWidth(32)
    auraIcon:SetHeight(32)
    auraIcon:SetPoint("CENTER", auraBtn, "CENTER", 0, 0)
    
    auraBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    auraBtn:SetScript("OnClick", function() Paladin:AuraButton_OnClick(this) end)
    auraBtn:SetScript("OnEnter", function() Paladin:AuraButton_OnEnter(this) end)
    auraBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local judgeBtn = CreateFrame("Button", rowName.."Judge", row)
    judgeBtn:SetWidth(44)
    judgeBtn:SetHeight(40)
    judgeBtn:SetPoint("TOPLEFT", row, "TOPLEFT", classX + (10 * 48) + 50, -16)
    
    local judgeBg = judgeBtn:CreateTexture(judgeBtn:GetName().."Background", "BACKGROUND")
    judgeBg:SetAllPoints(judgeBtn)
    judgeBg:SetTexture(0.1, 0.1, 0.1, 0.5)
    
    local judgeIcon = judgeBtn:CreateTexture(judgeBtn:GetName().."Icon", "ARTWORK")
    judgeIcon:SetWidth(32)
    judgeIcon:SetHeight(32)
    judgeIcon:SetPoint("CENTER", judgeBtn, "CENTER", 0, 0)
    
    judgeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    judgeBtn:SetScript("OnClick", function() Paladin:JudgeButton_OnClick(this) end)
    judgeBtn:SetScript("OnEnter", function() Paladin:JudgeButton_OnEnter(this) end)
    judgeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    row.classID = rowIndex - 1
    
    return row
end

-----------------------------------------------------------------------------------
-- Config Grid Updates
-----------------------------------------------------------------------------------

function Paladin:UpdateConfigGrid()
    if not self.ConfigWindow then return end
    
    local rowIndex = 1
    for paladinName, info in pairs(self.AllPaladins) do
        if rowIndex > 10 then break end
        
        local row = getglobal("CPPaladinRow"..rowIndex)
        if row then
            row:Show()
            row.paladinName = paladinName  -- Store for click handlers
            
            local nameStr = getglobal("CPPaladinRow"..rowIndex.."Name")
            if nameStr then
                local displayName = paladinName
                if string.len(paladinName) > 8 then
                    displayName = string.sub(paladinName, 1, 7)..".."
                end
                nameStr:SetText(displayName)
                
                if ClassPower_IsPromoted() or paladinName == UnitName("player") then
                    nameStr:SetTextColor(1, 1, 1)
                else
                    nameStr:SetTextColor(0.5, 0.5, 0.5)
                end
            end
            
            local symStr = getglobal("CPPaladinRow"..rowIndex.."Symbols")
            if symStr then
                symStr:SetText(info.symbols or 0)
            end
            
            local clearBtn = getglobal("CPPaladinRow"..rowIndex.."Clear")
            if clearBtn then
                if ClassPower_IsPromoted() or paladinName == UnitName("player") then
                    clearBtn:Show()
                else
                    clearBtn:Hide()
                end
            end
            
            self:UpdateCapabilityIcons(rowIndex, paladinName)
            self:UpdateClassButtons(rowIndex, paladinName)
            self:UpdateAuraButton(rowIndex, paladinName)
            self:UpdateJudgeButton(rowIndex, paladinName)
        end
        
        rowIndex = rowIndex + 1
    end
    
    for i = rowIndex, 10 do
        local row = getglobal("CPPaladinRow"..i)
        if row then row:Hide() end
    end
    
    local newHeight = 80 + (rowIndex - 1) * 62 + 40 -- +40 for Settings button
    if newHeight < 180 then newHeight = 180 end
    self.ConfigWindow:SetHeight(newHeight)
end

function Paladin:UpdateCapabilityIcons(rowIndex, paladinName)
    local info = self.AllPaladins[paladinName]
    
    for blessID = 0, 5 do
        local capIcon = getglobal("CPPaladinRow"..rowIndex.."Cap"..blessID)
        if not capIcon then return end
        
        local tex = getglobal(capIcon:GetName().."Icon")
        local rankText = getglobal(capIcon:GetName().."Rank")
        
        if info and info[blessID] then
            -- Paladin has this blessing
            tex:SetTexture(self.NormalBlessingIcons[blessID])
            tex:SetAlpha(1.0)
            capIcon:SetAlpha(1.0)
            
            -- Show rank and talent info
            local rankStr = ""
            if info[blessID].rank then
                rankStr = tostring(info[blessID].rank)
            end
            
            -- Add + if they have talent points in improved blessings
            if info[blessID].talent and info[blessID].talent > 0 then
                rankStr = rankStr .. "+"
                rankText:SetTextColor(0, 1, 0)  -- Green for talented
            else
                rankText:SetTextColor(1, 1, 1)  -- White for normal
            end
            
            rankText:SetText(rankStr)
        else
            -- Paladin doesn't have this blessing
            tex:SetTexture(self.NormalBlessingIcons[blessID])
            tex:SetAlpha(0.2)
            capIcon:SetAlpha(0.3)
            rankText:SetText("")
        end
    end
end

function Paladin:UpdateClassButtons(rowIndex, paladinName)
    local assigns = self.Assignments[paladinName] or {}
    
    for classID = 0, 9 do
        local btn = getglobal("CPPaladinRow"..rowIndex.."Class"..classID)
        if not btn then return end
        
        local icon = getglobal(btn:GetName().."Icon")
        local blessingID = assigns[classID]
        
        if blessingID and blessingID >= 0 then
            -- Assigned: show blessing icon at full opacity
            icon:SetTexture(self.BlessingIcons[blessingID])
            icon:SetAlpha(1.0)
            btn:SetAlpha(1.0)
        else
            -- Not assigned: show class icon, dimmed
            icon:SetTexture(self.ClassTextures[classID])
            icon:SetAlpha(1.0)
            btn:SetAlpha(0.4)
        end
    end
end

function Paladin:UpdateAuraButton(rowIndex, paladinName)
    local btn = getglobal("CPPaladinRow"..rowIndex.."Aura")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local auraID = self.AuraAssignments[paladinName]
    
    if auraID and auraID >= 0 then
        icon:SetTexture(self.AuraIcons[auraID])
        icon:SetAlpha(1.0)
        btn:SetAlpha(1.0)
    else
        icon:SetTexture("Interface\\Icons\\Spell_Holy_DevotionAura")
        icon:SetAlpha(1.0)
        btn:SetAlpha(0.4)
    end
end

function Paladin:UpdateJudgeButton(rowIndex, paladinName)
    local btn = getglobal("CPPaladinRow"..rowIndex.."Judge")
    if not btn then return end
    
    local icon = getglobal(btn:GetName().."Icon")
    local judgeID = self.JudgementAssignments[paladinName]
    
    if judgeID and judgeID >= 0 then
        icon:SetTexture(self.JudgementIcons[judgeID])
        icon:SetAlpha(1.0)
        btn:SetAlpha(1.0)
    else
        icon:SetTexture("Interface\\Icons\\Spell_Holy_RighteousnessAura")
        icon:SetAlpha(1.0)
        btn:SetAlpha(0.4)
    end
end

-----------------------------------------------------------------------------------
-- Click Handlers
-----------------------------------------------------------------------------------

function Paladin:GetPaladinNameFromRow(rowIndex)
    local index = 1
    for name, _ in pairs(self.AllPaladins) do
        if index == rowIndex then
            return name
        end
        index = index + 1
    end
    return nil
end

function Paladin:ClearButton_OnClick(btn)
    local rowName = btn:GetParent():GetName()
    local _, _, rowIdx = string.find(rowName, "CPPaladinRow(%d+)")
    if not rowIdx then return end
    
    local paladinName = self:GetPaladinNameFromRow(tonumber(rowIdx))
    if not paladinName then return end
    
    if not ClassPower_IsPromoted() and paladinName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Permission denied.")
        return
    end
    
    self.Assignments[paladinName] = {}
    for classID = 0, 9 do
        self.Assignments[paladinName][classID] = -1
    end
    self.AuraAssignments[paladinName] = nil
    self.JudgementAssignments[paladinName] = nil
    
    ClassPower_SendMessage("PCLEAR "..paladinName)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Cleared all assignments for "..paladinName)
    
    self:UpdateConfigGrid()
    self:UpdateBuffBar()
end

function Paladin:ClassButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx, classID = string.find(btnName, "CPPaladinRow(%d+)Class(%d+)")
    if not rowIdx or not classID then return end
    
    rowIdx = tonumber(rowIdx)
    classID = tonumber(classID)
    
    local paladinName = self:GetPaladinNameFromRow(rowIdx)
    if not paladinName then return end
    
    if not ClassPower_IsPromoted() and paladinName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    if arg1 == "RightButton" then
        self.Assignments[paladinName] = self.Assignments[paladinName] or {}
        self.Assignments[paladinName][classID] = -1
        ClassPower_SendMessage("PASSIGN "..paladinName.." "..classID.." -1")
        self:UpdateUI()
    elseif IsShiftKeyDown() then
        self:CycleBlessingForwardAllClasses(paladinName, classID)
    else
        self:CycleBlessingForward(paladinName, classID)
    end
end

function Paladin:ClassButton_OnMouseWheel(btn, delta)
    local btnName = btn:GetName()
    local _, _, rowIdx, classID = string.find(btnName, "CPPaladinRow(%d+)Class(%d+)")
    if not rowIdx or not classID then return end
    
    rowIdx = tonumber(rowIdx)
    classID = tonumber(classID)
    
    local paladinName = self:GetPaladinNameFromRow(rowIdx)
    if not paladinName then return end
    
    if not ClassPower_IsPromoted() and paladinName ~= UnitName("player") then
        return
    end
    
    if IsShiftKeyDown() then
        self:CycleBlessingForwardAllClasses(paladinName, classID)
    else
        self:CycleBlessingForward(paladinName, classID)
    end
end

function Paladin:ClassButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx, classID = string.find(btnName, "CPPaladinRow(%d+)Class(%d+)")
    if not rowIdx or not classID then return end
    
    classID = tonumber(classID)
    rowIdx = tonumber(rowIdx)
    
    local paladinName = self:GetPaladinNameFromRow(rowIdx)
    if not paladinName then return end
    
    local assigns = self.Assignments[paladinName] or {}
    local blessingID = assigns[classID]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.ClassNames[classID], 1, 1, 1)
    
    if blessingID and blessingID >= 0 then
        GameTooltip:AddLine("Assigned: "..self.Blessings[blessingID].short, 0, 1, 0)
    else
        GameTooltip:AddLine("Not assigned", 0.5, 0.5, 0.5)
    end
    
    GameTooltip:AddLine(" ", 1, 1, 1)
    GameTooltip:AddLine("Click or scroll to cycle blessings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift+Click: Set for ALL classes", 0, 1, 0)
    GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function Paladin:AuraButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPaladinRow(%d+)Aura")
    if not rowIdx then return end
    
    local paladinName = self:GetPaladinNameFromRow(tonumber(rowIdx))
    if not paladinName then return end
    
    if not ClassPower_IsPromoted() and paladinName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.ContextName = paladinName
    ToggleDropDownMenu(1, nil, ClassPowerPaladinAuraDropDown, btn, 0, 0)
end

function Paladin:AuraButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPaladinRow(%d+)Aura")
    if not rowIdx then return end
    
    local paladinName = self:GetPaladinNameFromRow(tonumber(rowIdx))
    local auraID = paladinName and self.AuraAssignments[paladinName]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Aura Assignment", 1, 1, 1)
    
    if auraID and auraID >= 0 then
        GameTooltip:AddLine(self.Auras[auraID].name, 0, 1, 0)
    else
        GameTooltip:AddLine("Not assigned", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

function Paladin:JudgeButton_OnClick(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPaladinRow(%d+)Judge")
    if not rowIdx then return end
    
    local paladinName = self:GetPaladinNameFromRow(tonumber(rowIdx))
    if not paladinName then return end
    
    if not ClassPower_IsPromoted() and paladinName ~= UnitName("player") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: You must be promoted to assign others.")
        return
    end
    
    self.ContextName = paladinName
    ToggleDropDownMenu(1, nil, ClassPowerPaladinJudgeDropDown, btn, 0, 0)
end

function Paladin:JudgeButton_OnEnter(btn)
    local btnName = btn:GetName()
    local _, _, rowIdx = string.find(btnName, "CPPaladinRow(%d+)Judge")
    if not rowIdx then return end
    
    local paladinName = self:GetPaladinNameFromRow(tonumber(rowIdx))
    local judgeID = paladinName and self.JudgementAssignments[paladinName]
    
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Judgement Assignment", 1, 1, 1)
    
    if judgeID and judgeID >= 0 then
        GameTooltip:AddLine(self.Judgements[judgeID].name, 0, 1, 0)
    else
        GameTooltip:AddLine("Not assigned", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

-----------------------------------------------------------------------------------
-- Dropdowns
-----------------------------------------------------------------------------------

function Paladin:AuraDropDown_Initialize(level)
    local info = {}
    
    info.text = ">> Clear <<"
    info.value = -1
    info.func = function() Paladin:AuraDropDown_OnClick(this.value) end
    UIDropDownMenu_AddButton(info)
    
    for id = 0, 6 do
        info = {}
        info.text = self.Auras[id].name
        info.value = id
        info.icon = self.AuraIcons[id]
        info.func = function() Paladin:AuraDropDown_OnClick(this.value) end
        UIDropDownMenu_AddButton(info)
    end
end

function Paladin:AuraDropDown_OnClick(auraID)
    local pname = self.ContextName
    if not pname then return end
    
    if auraID == -1 then
        self.AuraAssignments[pname] = nil
        ClassPower_SendMessage("PAURA "..pname.." n")
    else
        self.AuraAssignments[pname] = auraID
        ClassPower_SendMessage("PAURA "..pname.." "..auraID)
    end
    
    self:UpdateUI()
    CloseDropDownMenus()
    
    -- Save if this is for the current player
    if pname == UnitName("player") then
        self:SaveAssignments()
    end
end

function Paladin:JudgeDropDown_Initialize(level)
    local info = {}
    
    info.text = ">> Clear <<"
    info.value = -1
    info.func = function() Paladin:JudgeDropDown_OnClick(this.value) end
    UIDropDownMenu_AddButton(info)
    
    for id = 0, 3 do
        info = {}
        info.text = self.Judgements[id].name
        info.value = id
        info.icon = self.JudgementIcons[id]
        info.func = function() Paladin:JudgeDropDown_OnClick(this.value) end
        UIDropDownMenu_AddButton(info)
    end
end

function Paladin:JudgeDropDown_OnClick(judgeID)
    local pname = self.ContextName
    if not pname then return end
    
    if judgeID == -1 then
        self.JudgementAssignments[pname] = nil
        ClassPower_SendMessage("PJUDGE "..pname.." n")
    else
        self.JudgementAssignments[pname] = judgeID
        ClassPower_SendMessage("PJUDGE "..pname.." "..judgeID)
    end
    
    self:UpdateUI()
    CloseDropDownMenus()
    
    -- Save if this is for the current player
    if pname == UnitName("player") then
        self:SaveAssignments()
    end
end

function Paladin:TankDropDown_Initialize(level)
    local info = {}
    
    -- Header
    info.text = "Tank List (Skip Salvation)"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
    
    -- Clear all option
    info = {}
    info.text = "|cffff6600Clear All Tanks|r"
    info.notCheckable = true
    info.func = function()
        Paladin:ClearTankList()
        CloseDropDownMenus()
    end
    UIDropDownMenu_AddButton(info)
    
    -- Separator
    info = {}
    info.text = ""
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
    
    -- Current tanks (with remove option)
    if table.getn(self.TankList) > 0 then
        info = {}
        info.text = "-- Current Tanks --"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        for _, tankName in ipairs(self.TankList) do
            info = {}
            info.text = tankName .. " |cffff0000[Remove]|r"
            info.value = tankName
            info.notCheckable = true
            info.func = function()
                Paladin:RemoveFromTankList(this.value)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
        
        -- Separator
        info = {}
        info.text = ""
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
    end
    
    -- Add raid members (Warriors, Druids, Paladins - potential tanks)
    info = {}
    info.text = "-- Add Tank --"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info)
    
    -- Get raid/party members
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local function AddMember(name, class)
        if not name then return end
        -- Only show if not already a tank
        if self:IsTank(name) then return end
        
        -- Show class-appropriate members (Warriors, Druids, Paladins are common tanks)
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or {r=1, g=1, b=1}
        local colorCode = string.format("|cff%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
        
        local memberInfo = {}
        memberInfo.text = colorCode .. name .. "|r"
        memberInfo.value = name
        memberInfo.notCheckable = true
        memberInfo.func = function()
            Paladin:AddToTankList(this.value)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(memberInfo)
    end
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            AddMember(name, class)
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local name = UnitName("party"..i)
            local _, class = UnitClass("party"..i)
            AddMember(name, class)
        end
        local _, pClass = UnitClass("player")
        AddMember(UnitName("player"), pClass)
    end
end

-----------------------------------------------------------------------------------
-- Update UI
-----------------------------------------------------------------------------------

function Paladin:UpdateBuffBar()
    if not self.BuffBar then return end
    
    local f = self.BuffBar
    local pname = UnitName("player")
    local assigns = self.Assignments[pname] or {}
    
    local displayMode = CP_PerUser.BuffDisplayMode or "missing"
    local thresholdSeconds = ((CP_PerUser.TimerThresholdMinutes or 5) * 60) + (CP_PerUser.TimerThresholdSeconds or 0)
    
    local maxRowWidth = 120 -- Start smaller to allow shrinking, but keep minimum
    local lastRow = nil
    local visibleRows = {}
    
    -- Pass 1: Update Content & Calculate Max Width
    for classID = 0, 9 do
        local row = getglobal("ClassPowerPaladinHUDRow"..classID)
        
        if row then
            local showRow = false
            local blessingID = assigns[classID]
            
            if blessingID and blessingID >= 0 then
                -- Check stats
                local total = 0
                local missing = 0
                if self.CurrentBuffsByClass[classID] then
                    for _, m in pairs(self.CurrentBuffsByClass[classID]) do
                        total = total + 1
                        if not m.dead then
                             if not m[blessingID] then missing = missing + 1 end
                        end
                    end
                end
                
                local minTime = self:GetClassMinTimeRemaining(classID, blessingID)
                
                -- Determine visibility
                if displayMode == "always" then
                    showRow = (total > 0)
                elseif displayMode == "timer" then
                     if missing > 0 then
                         showRow = true
                     elseif minTime and minTime <= thresholdSeconds then
                         showRow = true
                     end
                else -- missing
                     showRow = (missing > 0)
                end
                
                if showRow then
                    -- Update Row Content
                    row:Show()
                    table.insert(visibleRows, row)
                    
                    local classIcon = getglobal(row:GetName().."ClassIcon")
                    local buffIcon = getglobal(row:GetName().."BuffIcon")
                    local text = getglobal(row:GetName().."Text")
                    
                    classIcon:SetTexture(self.ClassTextures[classID])
                    buffIcon:SetTexture(self.BlessingIcons[blessingID])
                    
                    -- Update Text
                    if displayMode == "always" or displayMode == "timer" then
                         if minTime and minTime > 0 and missing == 0 then
                              text:SetText(CP_FormatTime(minTime))
                              text:SetTextColor(0, 1, 0)
                         elseif missing > 0 then
                              if minTime and minTime > 0 then
                                   text:SetText(missing.." ("..CP_FormatTime(minTime)..")")
                              else
                                   text:SetText(missing.."/"..total)
                              end
                              text:SetTextColor(1, 0, 0)
                         else
                              text:SetText(total.."/"..total)
                              text:SetTextColor(0, 1, 0)
                         end
                    else
                         text:SetText(missing.."/"..total)
                         text:SetTextColor(1, 0, 0)
                    end
                    
                    -- Store state
                    row.blessingID = blessingID
                    
                    -- Width Calculation (Padding: 5+24+4+24+4 + Text + 5 Padding = 66 + Text)
                    local width = text:GetStringWidth() or 0
                    local w = 66 + width
                    if w > maxRowWidth then maxRowWidth = w end
                    
                else
                    row:Hide()
                end
            else
                row:Hide()
            end
        end
    end
    
    -- Pass 2: Layout & Width Application
    for _, row in ipairs(visibleRows) do
        row:SetWidth(maxRowWidth - 10) -- Row is slightly narrower than container (padding)
        
        if lastRow then
            row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, 0)
        else
            -- First row: Move down to avoid title overlap (Title is at -4)
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -20)
        end
        lastRow = row
    end
    
    -- Resize Container
    if math.abs(f:GetWidth() - maxRowWidth) > 1 then
         f:SetWidth(maxRowWidth)
    end
    
    local newHeight = 10
    local numRows = table.getn(visibleRows)
    if numRows > 0 then
        -- 20px top padding + rows * 34px + 5px bottom padding
        newHeight = 25 + (numRows * 34)
    else
        newHeight = 40
    end
    f:SetHeight(newHeight)
end

function Paladin:UpdateUI()
    self:UpdateBuffBar()
    if self.ConfigWindow and self.ConfigWindow:IsVisible() then
        self:UpdateConfigGrid()
    end
end

function Paladin:UpdateLeaderButtons()
    if not self.ConfigWindow then return end
    
    local autoBtn = getglobal(self.ConfigWindow:GetName().."AutoAssignBtn")
    local tankBtn = getglobal(self.ConfigWindow:GetName().."TankListBtn")
    
    if ClassPower_IsPromoted() then
        if autoBtn then autoBtn:Show() end
        if tankBtn then tankBtn:Show() end
    else
        if autoBtn then autoBtn:Hide() end
        if tankBtn then tankBtn:Hide() end
    end
end

function Paladin:ResetUI()
    CP_PerUser.PaladinPoint = nil
    CP_PerUser.PaladinRelativePoint = nil
    CP_PerUser.PaladinX = nil
    CP_PerUser.PaladinY = nil
    CP_PerUser.PaladinScale = 0.7
    CP_PerUser.PaladinConfigScale = 1.0
    
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

function Paladin:ReportAssignments()
    local msgType = "PARTY"
    if GetNumRaidMembers() > 0 then
        msgType = "RAID"
    end
    
    SendChatMessage("--- Paladin Assignments ---", msgType)
    
    for pname, assigns in pairs(self.Assignments) do
        local blessings = {}
        for classID = 0, 9 do
            local bid = assigns[classID]
            if bid and bid >= 0 then
                table.insert(blessings, self.Blessings[bid].short)
            end
        end
        
        local blessStr = table.getn(blessings) > 0 and table.concat(blessings, ", ") or "None"
        local auraStr = ""
        if self.AuraAssignments[pname] then
            auraStr = " | "..self.Auras[self.AuraAssignments[pname]].short
        end
        
        SendChatMessage(pname..": "..blessStr..auraStr, msgType)
    end
    
    SendChatMessage("--- End Assignments ---", msgType)
end

-----------------------------------------------------------------------------------
-- Persistence (Save/Load Assignments)
-----------------------------------------------------------------------------------

function Paladin:SaveAssignments()
    local pname = UnitName("player")
    if not pname then return end
    
    -- Initialize saved variable if needed
    if not CP_PaladinAssignments then
        CP_PaladinAssignments = {}
    end
    
    -- Save current player's assignments
    CP_PaladinAssignments.Assignments = self.Assignments[pname] or {}
    CP_PaladinAssignments.AuraAssignment = self.AuraAssignments[pname]
    CP_PaladinAssignments.JudgementAssignment = self.JudgementAssignments[pname]
    
    CP_Debug("Paladin: Saved assignments for "..pname)
end

function Paladin:LoadAssignments()
    local pname = UnitName("player")
    if not pname then return end
    
    -- Check if we have saved data
    if not CP_PaladinAssignments then
        CP_Debug("Paladin: No saved assignments found")
        return
    end
    
    -- Load assignments for current player
    if CP_PaladinAssignments.Assignments then
        self.Assignments[pname] = {}
        for classID = 0, 9 do
            local bid = CP_PaladinAssignments.Assignments[classID]
            if bid ~= nil then
                self.Assignments[pname][classID] = bid
            else
                self.Assignments[pname][classID] = -1
            end
        end
        CP_Debug("Paladin: Loaded blessing assignments")
    end
    
    if CP_PaladinAssignments.AuraAssignment ~= nil then
        self.AuraAssignments[pname] = CP_PaladinAssignments.AuraAssignment
        CP_Debug("Paladin: Loaded aura assignment: "..tostring(CP_PaladinAssignments.AuraAssignment))
    end
    
    if CP_PaladinAssignments.JudgementAssignment ~= nil then
        self.JudgementAssignments[pname] = CP_PaladinAssignments.JudgementAssignment
        CP_Debug("Paladin: Loaded judgement assignment: "..tostring(CP_PaladinAssignments.JudgementAssignment))
    end
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("PALADIN", Paladin)
