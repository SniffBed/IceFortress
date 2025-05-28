--!strict
----------------------------------------------------------------------
-- ProfileAdmin.server.lua
--  Chat command for whitelisted admins to wipe ONLY their own profile.
--  Usage in chat:  /resetprofile   or   /rp
--  Effect:
--    • Sets a flag on the player
--    • Kicks them
--    • DataManager.onPlayerRemoving sees the flag, removes the DataStore key,
--      and releases the ProfileStore session.
----------------------------------------------------------------------

------------------------  CONFIGURATION  -----------------------------
local ADMINS: {number} = {
    2464074222,     -- << replace with your Roblox UserId(s)
}
local DATASTORE_NAME = "PlayerStore"  -- must match the name used in ProfileStore.New(...)
---------------------------------------------------------------------

-- Services / modules
local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local playerStore       = DataStoreService:GetDataStore(DATASTORE_NAME)

local serverFolder      = game:GetService("ServerScriptService"):WaitForChild("Server")
local DataManager       = require(serverFolder:WaitForChild("DataManager"))

------------------------  HELPER FUNCTIONS  --------------------------
local function isAdmin(userId: number): boolean
    for _, id in ipairs(ADMINS) do
        if id == userId then
            return true
        end
    end
    return false
end

------------------------  CHAT COMMAND HOOK  -------------------------
Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        local cmd = msg:lower()
        if (cmd == "/resetprofile" or cmd == "/rp") and isAdmin(player.UserId) then
            ----------------------------------------------------------------
            -- 1. Flag the player so DataManager wipes the key on removal
            ----------------------------------------------------------------
            player:SetAttribute("WipeProfile", true)

            ----------------------------------------------------------------
            -- 2. End active ProfileStore session (if loaded) to avoid locks
            ----------------------------------------------------------------
            local profile = DataManager.GetProfile(player)
            if profile then
                profile:EndSession()   -- saves and releases lock
            end

            ----------------------------------------------------------------
            -- 3. Kick the player (actual key removal happens in onPlayerRemoving)
            ----------------------------------------------------------------
            player:Kick("Profile wiped. Rejoin to start fresh.")
        end
    end)
end)

----------------------------------------------------------------------
-- DataManager must delete the key when WipeProfile attribute is set
-- (The following snippet shows how your onPlayerRemoving should look.)
--   local wipeFlag = player:GetAttribute("WipeProfile")
--   if wipeFlag == true then
--       playerStore:RemoveAsync(tostring(player.UserId))
--   end
----------------------------------------------------------------------
