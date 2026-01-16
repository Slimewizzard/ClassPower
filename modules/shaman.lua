-- ClassPower: Shaman Module (Stub)
-- Buff management for Shaman class

local Shaman = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Shaman.Totems = {
    STRENGTH = "Strength of Earth Totem",
    GRACE = "Grace of Air Totem",
    WINDFURY = "Windfury Totem",
    MANA_SPRING = "Mana Spring Totem",
    HEALING_STREAM = "Healing Stream Totem",
}

Shaman.BuffIcons = {
    STRENGTH = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
    GRACE = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",
    WINDFURY = "Interface\\Icons\\Spell_Nature_Windfury",
    MANA_SPRING = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
}

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Shaman:OnLoad()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Shaman module is a stub. Implementation coming soon!")
end

function Shaman:OnSlashCommand(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Shaman config not yet implemented.")
end

function Shaman:ResetUI()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Shaman UI reset (stub).")
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("SHAMAN", Shaman)
