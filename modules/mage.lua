-- ClassPower: Mage Module (Stub)
-- Buff management for Mage class

local Mage = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Mage.Spells = {
    AI = "Arcane Intellect",
    AB = "Arcane Brilliance",
    DAMPEN = "Dampen Magic",
    AMPLIFY = "Amplify Magic",
}

Mage.BuffIcons = {
    AI = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    AB = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
    DAMPEN = "Interface\\Icons\\Spell_Nature_AbolishMagic",
    AMPLIFY = "Interface\\Icons\\Spell_Holy_FlashHeal",
}

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Mage:OnLoad()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Mage module is a stub. Implementation coming soon!")
end

function Mage:OnSlashCommand(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Mage config not yet implemented.")
end

function Mage:ResetUI()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Mage UI reset (stub).")
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("MAGE", Mage)
