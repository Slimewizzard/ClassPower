-- ClassPower: Druid Module (Stub)
-- Buff management for Druid class

local Druid = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Druid.Spells = {
    MOTW = "Mark of the Wild",
    GOTW = "Gift of the Wild",
    THORNS = "Thorns",
}

Druid.BuffIcons = {
    MOTW = "Interface\\Icons\\Spell_Nature_Regeneration",
    GOTW = "Interface\\Icons\\Spell_Nature_GiftOfTheWild",
    THORNS = "Interface\\Icons\\Spell_Nature_Thorns",
}

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Druid:OnLoad()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Druid module is a stub. Implementation coming soon!")
end

function Druid:OnSlashCommand(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Druid config not yet implemented.")
end

function Druid:ResetUI()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Druid UI reset (stub).")
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("DRUID", Druid)
