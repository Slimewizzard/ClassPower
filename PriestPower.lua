-- PriestPower
-- 1.12.1 / Turtle WoW Addon
-- Lua 5.0

-- Create the main addon frame to handle events
local frame = CreateFrame("Frame")

-- Register the event that fires when the addon is fully loaded
frame:RegisterEvent("ADDON_LOADED")

-- Event Handler
frame:SetScript("OnEvent", function()
    -- Check if our addon is the one being loaded
    if (event == "ADDON_LOADED" and arg1 == "PriestPower") then
        -- Initialize SavedVariables if they don't exist
        if (PriestPowerDB == nil) then
            PriestPowerDB = {}
        end
        
        -- Print a welcome message to the default chat frame
        if (DEFAULT_CHAT_FRAME) then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r initialized successfully.")
        end
        
        -- We can unregister the event now if we don't need it anymore
        -- frame:UnregisterEvent("ADDON_LOADED") 
    end
end)

-- Slash Command Handler
SLASH_PRIESTPOWER1 = "/pp"
SLASH_PRIESTPOWER2 = "/priestpower"

SlashCmdList["PRIESTPOWER"] = function(msg)
    if (msg == "" or msg == nil) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r Usage:")
        DEFAULT_CHAT_FRAME:AddMessage("/pp status - Check status")
    elseif (msg == "status") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r is running.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffe00aPriestPower|r: Unknown command.")
    end
end
