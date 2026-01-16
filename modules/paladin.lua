-- ClassPower: Paladin Module (Stub)
-- Buff management for Paladin class
-- Note: Consider using PallyPower instead - this is just for consistency

local Paladin = {}

-----------------------------------------------------------------------------------
-- Spell Definitions
-----------------------------------------------------------------------------------

Paladin.Blessings = {
    MIGHT = "Blessing of Might",
    WISDOM = "Blessing of Wisdom",
    KINGS = "Blessing of Kings",
    SALVATION = "Blessing of Salvation",
    SANCTUARY = "Blessing of Sanctuary",
    LIGHT = "Blessing of Light",
    G_MIGHT = "Greater Blessing of Might",
    G_WISDOM = "Greater Blessing of Wisdom",
    G_KINGS = "Greater Blessing of Kings",
    G_SALVATION = "Greater Blessing of Salvation",
    G_SANCTUARY = "Greater Blessing of Sanctuary",
    G_LIGHT = "Greater Blessing of Light",
}

Paladin.BuffIcons = {
    MIGHT = "Interface\\Icons\\Spell_Holy_FistOfJustice",
    WISDOM = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    KINGS = "Interface\\Icons\\Spell_Magic_MageArmor",
    SALVATION = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
    SANCTUARY = "Interface\\Icons\\Spell_Nature_LightningShield",
    LIGHT = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
}

-----------------------------------------------------------------------------------
-- Module Lifecycle
-----------------------------------------------------------------------------------

function Paladin:OnLoad()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Paladin module is a stub. Consider using PallyPower instead!")
end

function Paladin:OnSlashCommand(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Paladin config not yet implemented. Try PallyPower!")
end

function Paladin:ResetUI()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ClassPower|r: Paladin UI reset (stub).")
end

-----------------------------------------------------------------------------------
-- Register Module
-----------------------------------------------------------------------------------

ClassPower:RegisterModule("PALADIN", Paladin)
