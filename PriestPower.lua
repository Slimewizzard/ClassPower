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

    if PP_DebugEnabled then PP_Debug("PriestPower OnLoad") end
end

function PriestPower_OnEvent(event)
    if event == "PLAYER_LOGIN" then
        UIDropDownMenu_Initialize(PriestPowerChampDropDown, PriestPower_ChampDropDown_Initialize, "MENU")
        
        local _, class = UnitClass("player")
        if class == "PRIEST" then
            IsPriest = true
            PriestPower_ScanSpells()
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded.")
        else
            IsPriest = false
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded. Not a Priest (Disabled).")
        end
        
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if IsPriest then PriestPower_ScanSpells() end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        PriestPower_ScanRaid()
        PriestPower_UpdateUI()
    elseif event == "CHAT_MSG_ADDON" then
        PriestPower_ParseMessage(arg1, arg2, arg4)
    end
end

function PriestPower_OnUpdate(elapsed)
    -- Stub for now, can handle timers later
    PP_NextScan = PP_NextScan - elapsed
    if PP_NextScan <= 0 then
        PP_NextScan = PP_PerUser.scanfreq
        PriestPower_ScanRaid()
        PriestPower_UpdateUI()
    end
end

function PriestPower_UpdateBuffBar()
    -- Hide all first
    local i = 1
    while true do
        local btn = getglobal("PriestPowerBuffButton"..i)
        if not btn then break end
        btn:Hide()
        i = i + 1
    end
    getglobal("PriestPowerBuffBarChamp"):Hide()
    
    local pname = UnitName("player")
    local assigns = PriestPower_Assignments[pname]
    
    local btnIdx = 1
    
    if assigns then
        for gid = 1, 8 do
             if assigns[gid] and assigns[gid] > 0 then
                 local val = assigns[gid]
                 
                 -- Bit 1: Fortitude
                 if math.mod(val, 2) == 1 then
                     local btn = getglobal("PriestPowerBuffButton"..btnIdx)
                     if btn then
                         btn:Show()
                         getglobal(btn:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[0])
                         btn.tooltipText = "Group "..gid..": Fortitude"
                         
                         local missing = 0
                         local total = 0
                         if CurrentBuffs[gid] then
                            for _, member in CurrentBuffs[gid] do
                                total = total + 1
                                if not member.hasFort and not member.dead then missing = missing + 1 end
                            end
                         end
                         
                         local text = getglobal(btn:GetName().."Text")
                         if missing > 0 then
                             text:SetText(missing)
                             text:SetTextColor(1,0,0)
                         else
                             text:SetText(total)
                             text:SetTextColor(0,1,0)
                         end
                         
                         btnIdx = btnIdx + 1
                     end
                 end
                 
                 -- Bit 2: Spirit
                 if val >= 2 then
                     local btn = getglobal("PriestPowerBuffButton"..btnIdx)
                     if btn then
                         btn:Show()
                         getglobal(btn:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[1])
                         btn.tooltipText = "Group "..gid..": Spirit"
                         
                         local missing = 0
                         local total = 0
                         if CurrentBuffs[gid] then
                            for _, member in CurrentBuffs[gid] do
                                total = total + 1
                                if not member.hasSpirit and not member.dead then missing = missing + 1 end
                            end
                         end
                         
                         local text = getglobal(btn:GetName().."Text")
                         if missing > 0 then
                             text:SetText(missing)
                             text:SetTextColor(1,0,0)
                         else
                             text:SetText(total)
                             text:SetTextColor(0,1,0)
                         end
                         
                         btnIdx = btnIdx + 1
                     end
                 end
             end
        end
    end
    
    -- Champion
    if PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"] then
        local champFrame = getglobal("PriestPowerBuffBarChamp")
        champFrame:Show()
        
        -- Anchor it dynamically
        if btnIdx > 1 then
            champFrame:SetPoint("TOP", "PriestPowerBuffButton"..(btnIdx-1), "BOTTOM", 0, -5)
        else
            champFrame:SetPoint("TOPLEFT", "PriestPowerBuffBar", "TOPLEFT", 10, -15)
        end
        
        -- Update Champ Button Status
        local target = PriestPower_LegacyAssignments[pname]["Champ"]
        local status = CurrentBuffsByName[target]
        
        local label = getglobal("PriestPowerBuffBarChampName")
        if label then label:SetText(target) end
        
        local btnP = getglobal("PriestPowerBuffBarChampProclaim")
        local btnG = getglobal("PriestPowerBuffBarChampGrace")
        local btnE = getglobal("PriestPowerBuffBarChampEmpower")
        
        getglobal(btnP:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Proclaim"])
        getglobal(btnG:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Grace"])
        getglobal(btnE:GetName().."Icon"):SetTexture(PriestPower_ChampionIcons["Empower"])
        
        if status and status.hasProclaim then getglobal(btnP:GetName().."Text"):SetText("") 
        else getglobal(btnP:GetName().."Text"):SetText("|cffff0000X|r") end
        
        -- Ideally show timers here too, but simple check for now
    end
    
    -- Resize Container
    local height = 20 + ((btnIdx-1) * 32)
    if PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"] then
        height = height + 50
    end
    if height < 30 then height = 30 end
    PriestPowerBuffBar:SetHeight(height)
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

CurrentBuffsByName = {}

function PriestPower_ScanRaid()
    if not IsPriest then return end
    
    -- Reset
    CurrentBuffs = {}
    for i=1, 8 do CurrentBuffs[i] = {} end
    CurrentBuffsByName = {}
    
    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then return end 

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
                
                if string.find(bname, "Fortitude") then buffInfo.hasFort = true end
                if string.find(bname, "Spirit") or string.find(bname, "Inspiration") then buffInfo.hasSpirit = true end
                
                if string.find(bname, "Proclaim Champion") or string.find(bname, "Holy Champion") then buffInfo.hasProclaim = true end
                if string.find(bname, "Champion's Grace") then buffInfo.hasGrace = true end
                if string.find(bname, "Empower Champion") then buffInfo.hasEmpower = true end
                
                b = b + 1
            end
            
            table.insert(CurrentBuffs[subgroup], buffInfo)
            CurrentBuffsByName[name] = buffInfo
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
            else
                if champText then champText:SetText("") end
                iconP:Hide()
                iconG:Hide()
                iconE:Hide()
            end
        end
        i = i + 1
    end
    
    for k = i, 5 do getglobal("PriestPowerFramePlayer"..k):Hide() end
    
    PriestPower_UpdateBuffBar()
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

-- Context for Dropdown (Which priest are we assigning for?)
PriestPower_ContextName = nil

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
    ToggleDropDownMenu(1, nil, PriestPowerChampDropDown, btn:GetName(), 0, 0)
end

function PriestPower_AssignChamp_OnClick()
    local targetName = this.value
    local pname = PriestPower_ContextName
    
    if not pname then return end
    
    if targetName == "CLEAR" then
        PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}
        PriestPower_LegacyAssignments[pname]["Champ"] = nil
        DEFAULT_CHAT_FRAME:AddMessage("Cleared Champion for "..pname)
        PriestPower_SendMessage("ASSIGNCHAMP "..pname.." nil")
    else
        PriestPower_LegacyAssignments[pname] = PriestPower_LegacyAssignments[pname] or {}
        PriestPower_LegacyAssignments[pname]["Champ"] = targetName
        DEFAULT_CHAT_FRAME:AddMessage("Assigned Champion for "..pname..": "..targetName)
        PriestPower_SendMessage("ASSIGNCHAMP "..pname.." "..targetName)
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
        -- If in party (Debug/5-man)
        local numParty = GetNumPartyMembers()
        if numParty > 0 then
             -- Add Player
             info = {}
             info.text = UnitName("player")
             info.value = UnitName("player")
             info.func = PriestPower_AssignChamp_OnClick
             UIDropDownMenu_AddButton(info)
             
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
