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
}

-- Icons for the "Special" champion spells
PriestPower_ChampionIcons = {
    ["Proclaim"] = "Interface\\Icons\\Spell_Holy_ProclaimChampion",
    ["Grace"] = "Interface\\Icons\\Spell_Holy_ChampionsGrace",
    ["Empower"] = "Interface\\Icons\\Spell_Holy_EmpowerChampion",
}

AllPriests = {}
CurrentBuffs = {}
IsPriest = false
PP_DebugEnabled = false

function PP_Debug(msg)
    if PP_DebugEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00a[PP Debug]|r "..tostring(msg))
    end
end

-- Scanning/Logic
function PriestPower_OnLoad()
    this:RegisterEvent("SPELLS_CHANGED")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("PARTY_MEMBERS_CHANGED")
    this:RegisterEvent("PLAYER_LOGIN")
    
    SlashCmdList["PRIESTPOWER"] = function(msg)
        PriestPower_SlashCommandHandler(msg)
    end
    SLASH_PRIESTPOWER1 = "/pp" 
    SLASH_PRIESTPOWER2 = "/priestpower"
    SLASH_PRIESTPOWER3 = "/prp"

    SLASH_PRIESTPOWER3 = "/prp"

    DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded. Type /pp to open, /pp debug to toggle logs.")
end

function PriestPower_OnUpdate(tdiff)
    PP_NextScan = PP_NextScan - tdiff
    if PP_NextScan < 0 and IsPriest then
        PriestPower_ScanRaid()
        -- PriestPower_UpdateUI() -- Triggering UI update on scan might be heavy, usually optional
        PP_NextScan = PP_PerUser.scanfreq
    end
end

function PriestPower_OnEvent(event)
    PP_Debug("Event Fired: " .. tostring(event))
    if (event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD") then
        PriestPower_ScanSpells()
    end
    
    if (event == "PLAYER_LOGIN") then
        local _, class = UnitClass("player")
        if class == "PRIEST" then
            IsPriest = true
            PriestPower_ScanSpells()
        else
            IsPriest = false
        end
    end

    if (event == "CHAT_MSG_ADDON" and arg1 == PP_PREFIX and (arg3 == "PARTY" or arg3 == "RAID")) then
        PriestPower_ParseMessage(arg4, arg2)
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
        ["Revive"] = false
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
        if spellName == SPELL_PROCLAIM then RankInfo["Proclaim"] = true end
        if spellName == SPELL_GRACE then RankInfo["Grace"] = true end
        if spellName == SPELL_EMPOWER then RankInfo["Empower"] = true end
        if spellName == SPELL_REVIVE then RankInfo["Revive"] = true end
        
        i = i + 1
    end
    
    AllPriests[UnitName("player")] = RankInfo
    -- Consider broadcasting self here or waiting for REQ
end

function PriestPower_ScanRaid()
    if not IsPriest then return end
    
    -- Reset CurrentBuffs: Index 1-8 for groups
    CurrentBuffs = {}
    for i=1, 8 do CurrentBuffs[i] = {} end
    
    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then return end -- Only Raid logic supported for Groups 1-8 for now

    for i = 1, numRaid do
        local unit = "raid"..i
        local name, _, subgroup = GetRaidRosterInfo(i)
        
        if name and subgroup and subgroup >= 1 and subgroup <= 8 then
            local buffInfo = {
                name = name,
                class = UnitClass(unit),
                visible = UnitIsVisible(unit),
                dead = UnitIsDeadOrGhost(unit),
                hasFort = false,
                hasSpirit = false
            }
            
            -- Check Buffs
            local b = 1
            while true do
                local bname = UnitBuff(unit, b)
                if not bname then break end
                
                if string.find(bname, "Fortitude") then buffInfo.hasFort = true end
                if string.find(bname, "Spirit") or string.find(bname, "Inspiration") then buffInfo.hasSpirit = true end
                
                b = b + 1
            end
            
            table.insert(CurrentBuffs[subgroup], buffInfo)
        end
    end
end

function PriestPower_SendSelf()
    if not AllPriests[UnitName("player")] then return end
    
    local RankInfo = AllPriests[UnitName("player")]
    local msg = "SELF "
    
    for id = 0, 2 do
        if RankInfo[id] then
            msg = msg .. RankInfo[id].rank .. RankInfo[id].talent
        else
            msg = msg .. "nn"
        end
    end
    
    local p = RankInfo["Proclaim"] and "1" or "0"
    local g = RankInfo["Grace"] and "1" or "0"
    local e = RankInfo["Empower"] and "1" or "0"
    local r = RankInfo["Revive"] and "1" or "0"
    msg = msg .. p .. g .. e .. r
    
    msg = msg .. "@"
    
    if PriestPower_Assignments[UnitName("player")] then
        for id = 0, 9 do
            local val = PriestPower_Assignments[UnitName("player")][id]
            if val then msg = msg .. val else msg = msg .. "n" end
        end
    else
        for id = 0, 9 do msg = msg .. "n" end
    end
    
    if PriestPower_LegacyAssignments[UnitName("player")] and PriestPower_LegacyAssignments[UnitName("player")]["Champ"] then
         msg = msg .. "$" .. PriestPower_LegacyAssignments[UnitName("player")]["Champ"]
    end

    PriestPower_SendMessage(msg)
end

function PriestPower_SendMessage(msg)
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(PP_PREFIX, msg, "RAID")
    else
        SendAddonMessage(PP_PREFIX, msg, "PARTY")
    end
end

function PriestPower_ParseMessage(sender, msg)
    if sender == UnitName("player") then return end 
    
    if msg == "REQ" then
        PriestPower_SendSelf()
    elseif string.find(msg, "^SELF") then
        local _, _, ranks, assigns, champ = string.find(msg, "SELF ([0-9n]*)@([0-9n]*)$?(.*)")
        
        if not ranks then return end
        
        AllPriests[sender] = AllPriests[sender] or {}
        local info = AllPriests[sender]
        
        for id = 0, 2 do
            local r = string.sub(ranks, id*2+1, id*2+1)
            local t = string.sub(ranks, id*2+2, id*2+2)
            if r ~= "n" then
                info[id] = { rank = tonumber(r), talent = tonumber(t) }
            end
        end
        
        info["Proclaim"] = (string.sub(ranks, 7, 7) == "1")
        info["Grace"]    = (string.sub(ranks, 8, 8) == "1")
        info["Empower"]  = (string.sub(ranks, 9, 9) == "1")
        info["Revive"]   = (string.sub(ranks, 10, 10) == "1")
        
        PriestPower_Assignments[sender] = PriestPower_Assignments[sender] or {}
        for id = 0, 9 do
             local val = string.sub(assigns, id+1, id+1)
             if val ~= "n" then
                 PriestPower_Assignments[sender][id] = tonumber(val)
             end
        end
        
        PriestPower_LegacyAssignments[sender] = PriestPower_LegacyAssignments[sender] or {}
        if champ and champ ~= "" then
            PriestPower_LegacyAssignments[sender]["Champ"] = champ
        else
            PriestPower_LegacyAssignments[sender]["Champ"] = nil
        end
        
        -- PriestPower_UpdateUI()
        
    elseif string.find(msg, "^ASSIGN ") then
        local _, _, name, class, skill = string.find(msg, "^ASSIGN (.*) (.*) (.*)")
        if name and class and skill then
            PriestPower_Assignments[name] = PriestPower_Assignments[name] or {}
            PriestPower_Assignments[name][tonumber(class)] = tonumber(skill)
             PriestPower_UpdateUI()
        end
        
    elseif string.find(msg, "^ASSIGNCHAMP ") then
        local _, _, name, target = string.find(msg, "^ASSIGNCHAMP (.*) (.*)")
        if name and target then
            if target == "nil" or target == "" then target = nil end
            PriestPower_LegacyAssignments[name] = PriestPower_LegacyAssignments[name] or {}
            PriestPower_LegacyAssignments[name]["Champ"] = target
             PriestPower_UpdateUI()
        end
    end
end

function PriestPower_UpdateUI()
    local i = 1
    for name, info in AllPriests do
        if i > 5 then break end 
        
        local frame = getglobal("PriestPowerFramePlayer"..i)
        if frame then
            frame:Show()
            getglobal(frame:GetName().."Name"):SetText(name)
            
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
            
            -- Champion Button logic remains same
            local champIcon = getglobal(frame:GetName().."ChampIcon")
            
            if not champIcon then
                -- PP_Debug("Could not find icon: " .. frame:GetName().."ChampIcon")
            else
                local champTarget = nil
                if PriestPower_LegacyAssignments[name] then
                     champTarget = PriestPower_LegacyAssignments[name]["Champ"]
                end
                if champTarget then
                    champIcon:SetTexture(PriestPower_ChampionIcons["Proclaim"])
                    champIcon:Show()
                else
                    champIcon:Hide()
                end
            end
        end
        i = i + 1
    end
    
    for k = i, 5 do getglobal("PriestPowerFramePlayer"..k):Hide() end
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

function PriestPowerChampButton_OnClick(btn)
    local _, _, pid = string.find(btn:GetName(), "PriestPowerFramePlayer(%d+)")
    pid = tonumber(pid)
    local pname = getglobal("PriestPowerFramePlayer"..pid.."Name"):GetText()
    
    if UnitExists("target") and UnitIsFriend("player", "target") and UnitIsPlayer("target") then
        local targetName = UnitName("target")
        PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}
        PriestPower_LegacyAssignments[pname]["Champ"] = targetName
        
        DEFAULT_CHAT_FRAME:AddMessage("Assigned Champion for "..pname..": "..targetName)
        PriestPower_SendMessage("ASSIGNCHAMP "..pname.." "..targetName)
    else
        PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}
        PriestPower_LegacyAssignments[pname]["Champ"] = nil
        PriestPower_SendMessage("ASSIGNCHAMP "..pname.." nil")
    end
    PriestPower_UpdateUI()
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
    else
        if PriestPowerFrame:IsVisible() then
            PriestPowerFrame:Hide()
        else
            PriestPowerFrame:Show()
            PriestPower_UpdateUI()
        end
    end
end
