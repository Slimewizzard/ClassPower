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
PP_DebugFakeMembers = true
PP_BuffTimers = {}

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
    SLASH_PRIESTPOWER1 = "/pp" 
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
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded.")
        else
            IsPriest = false
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r loaded. Not a Priest (Disabled).")
        end
        
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        if IsPriest then 
            PriestPower_ScanSpells() 
            if event == "PLAYER_ENTERING_WORLD" then PriestPower_RequestSend() end
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        PriestPower_ScanRaid()
        PriestPower_UpdateUI()
        if event == "RAID_ROSTER_UPDATE" then PriestPower_RequestSend() end
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

function PriestPower_OnUpdate(elapsed)
    if not PP_PerUser then return end
    
    -- Scan Logic
    PP_NextScan = PP_NextScan - elapsed
    if PP_NextScan <= 0 then
        PP_NextScan = PP_PerUser.scanfreq
        PriestPower_ScanRaid()
        -- PriestPower_UpdateUI() -- Moved to 1s timer below or keep?
        -- ScanRaid updates data, UI updates visual.
    end
    
    -- UI Refresh Logic (1s interval)
    PP_UpdateTimer = PP_UpdateTimer - elapsed
    if PP_UpdateTimer <= 0 then
        PP_UpdateTimer = 1.0
        
        -- Refresh Buff Bar for Timers
        if PriestPowerBuffBar:IsVisible() then
            PriestPower_UpdateBuffBar() 
        end
        
        -- Refresh Main Frame if visible (for status updates)
        if PriestPowerFrame:IsVisible() then
            PriestPower_UpdateUI()
        end
    end
end

function PriestPower_UpdateBuffBar()
    getglobal("PriestPowerBuffBarChamp"):Hide()
    
    local pname = UnitName("player")
    local assigns = PriestPower_Assignments[pname]
    
    local btnIdx = 1
    
     -- Hide all rows first? Iterate and set based on assign
     local lastVisibleRow = nil
     
     if assigns then
         for gid = 1, 8 do
             local row = getglobal("PriestPowerHUDRow"..gid)
             if row then
                 if assigns[gid] and assigns[gid] > 0 then
                      row:Show()
                      lastVisibleRow = row
                      getglobal(row:GetName().."Label"):SetText("Grp "..gid)
                      
                      local val = assigns[gid]
                      
                      -- Fortitude (Bit 1)
                      local btnFort = getglobal(row:GetName().."Fort")
                      if math.mod(val, 2) == 1 then
                          btnFort:Show()
                          getglobal(btnFort:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[0])
                          btnFort.tooltipText = "Group "..gid..": Fortitude"
                          
                          local missing = 0
                          local total = 0
                          if CurrentBuffs[gid] then
                              for _, member in CurrentBuffs[gid] do
                                  total = total + 1
                                  if not member.hasFort and not member.dead then missing = missing + 1 end
                              end
                          end
                          
                          local text = getglobal(btnFort:GetName().."Text")
                          if missing > 0 then
                              text:SetText(missing)
                              text:SetTextColor(1,0,0)
                          else
                              text:SetText(total)
                              text:SetTextColor(0,1,0)
                          end
                      else
                          btnFort:Hide()
                      end
                      
                      -- Spirit (Bit 2, val >= 2)
                      local btnSpirit = getglobal(row:GetName().."Spirit")
                      if val >= 2 then
                          btnSpirit:Show()
                          getglobal(btnSpirit:GetName().."Icon"):SetTexture(PriestPower_BuffIcon[1])
                          btnSpirit.tooltipText = "Group "..gid..": Spirit"
                          
                          local missing = 0
                          local total = 0
                          if CurrentBuffs[gid] then
                              for _, member in CurrentBuffs[gid] do
                                  total = total + 1
                                  if not member.hasSpirit and not member.dead then missing = missing + 1 end
                              end
                          end
                          
                          local text = getglobal(btnSpirit:GetName().."Text")
                          if missing > 0 then
                              text:SetText(missing)
                              text:SetTextColor(1,0,0)
                          else
                              text:SetText(total)
                              text:SetTextColor(0,1,0)
                          end
                      else
                          btnSpirit:Hide()
                      end
                 else
                      row:Hide()
                 end
             end
         end
     else
          -- No assigns, hide all
          for gid=1,8 do getglobal("PriestPowerHUDRow"..gid):Hide() end
     end
    
    -- Champion
    if PriestPower_LegacyAssignments[pname] and PriestPower_LegacyAssignments[pname]["Champ"] then
        local champFrame = getglobal("PriestPowerBuffBarChamp")
        champFrame:Show()
        
        -- Anchor it dynamically
        champFrame:ClearAllPoints()
        if lastVisibleRow then
            champFrame:SetPoint("TOP", lastVisibleRow, "BOTTOM", 0, -10)
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
        -- Helper Timer Function
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

        -- Proclaim
        if status and status.hasProclaim then
             btnP:SetAlpha(1.0)
             getglobal(btnP:GetName().."Text"):SetText(GetTimerText("Proclaim"))
        else
             btnP:SetAlpha(1.0)
             getglobal(btnP:GetName().."Text"):SetText("|cffff0000X|r") -- Red X if missing
        end
        
        -- Grace & Empower (Mutually Exclusive Display)
        -- Reset Anchors
        btnG:ClearAllPoints(); btnG:SetPoint("LEFT", btnP, "RIGHT", 0, 0)
        btnE:ClearAllPoints(); btnE:SetPoint("LEFT", btnG, "RIGHT", 0, 0)
        
        if status then 
            if status.hasGrace then
                btnG:Show(); btnG:SetAlpha(1.0)
                getglobal(btnG:GetName().."Text"):SetText(GetTimerText("Grace"))
                btnE:Hide()
            elseif status.hasEmpower then
                btnG:Hide()
                btnE:Show(); btnE:SetAlpha(1.0)
                -- Move Empower to Grace's spot
                btnE:ClearAllPoints(); btnE:SetPoint("LEFT", btnP, "RIGHT", 0, 0)
                getglobal(btnE:GetName().."Text"):SetText(GetTimerText("Empower"))
            else
                -- Neither active: Show both faded
                btnG:Show(); btnG:SetAlpha(0.4); getglobal(btnG:GetName().."Text"):SetText("")
                btnE:Show(); btnE:SetAlpha(0.4); getglobal(btnE:GetName().."Text"):SetText("")
            end
        else
             -- No status (target invalid/far/dead?), show faded?
             btnG:Show(); btnG:SetAlpha(0.4); getglobal(btnG:GetName().."Text"):SetText("")
             btnE:Show(); btnE:SetAlpha(0.4); getglobal(btnE:GetName().."Text"):SetText("")
        end
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
                
                if string.find(bname, "ProclaimChampion") or string.find(bname, "HolyChampion") then buffInfo.hasProclaim = true end
                if string.find(bname, "ChampionsGrace") then buffInfo.hasGrace = true end
                if string.find(bname, "EmpowerChampion") then buffInfo.hasEmpower = true end
                
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
            
            table.insert(CurrentBuffs[subgroup], buffInfo)
            CurrentBuffsByName[name] = buffInfo
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
        if name and class and skill then
            PriestPower_Assignments[name] = PriestPower_Assignments[name] or {}
            PriestPower_Assignments[name][tonumber(class)] = tonumber(skill)
             PriestPower_UpdateUI()
        end
        
    elseif string.find(msg, "^ASSIGNCHAMP ") then
        local _, _, name, target = string.find(msg, "^ASSIGNCHAMP (.-) (.*)")
        if name and target then
            if target == "nil" or target == "" then target = nil end
            PriestPower_LegacyAssignments[name] = PriestPower_LegacyAssignments[name] or {}
            PriestPower_LegacyAssignments[name]["Champ"] = target
             PriestPower_UpdateUI()
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
    
    for k = i, 10 do getglobal("PriestPowerFramePlayer"..k):Hide() end
    
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

