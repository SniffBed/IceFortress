--!strict
----------------------------------------------------------------------
-- ProfileAdmin.server.lua
--  Chat command for whitelisted admins to wipe profiles.
--
--  Usage in chat
--    /rp                     – wipe **your own** profile      (legacy)
--    /rp  SomeUserName       – wipe the named user’s profile
--    /resetprofile           – same as /rp
--    /resetprofile SomeName  – same as /rp <SomeName>
--
--  Behaviour
--    • If the target player is **online**:
--        – Sets a WipeProfile flag on that player
--        – Ends their ProfileStore session (if loaded)
--        – Kicks them so DataManager.onPlayerRemoving can delete the key
--    • If the target player is **offline**:
--        – Resolves their UserId via GetUserIdFromNameAsync
--        – Removes the DataStore key immediately
----------------------------------------------------------------------
------------------------  CONFIGURATION  -----------------------------
local ADMINS: {number} = {
	2464074222,      -- << replace with your Roblox UserId(s)
}
local DATASTORE_NAME = "PlayerStore" -- must match ProfileStore.New(...)
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

-- Wipes an **online** player (flag + kick)
local function wipeOnlinePlayer(target: Player)
	target:SetAttribute("WipeProfile", true)

	local profile = DataManager.GetProfile(target)
	if profile then
		profile:EndSession() -- save & release lock
	end

	target:Kick("Profile wiped by admin. Re-join to start fresh.")
end

-- Wipes an **offline** player by UserId
local function wipeOfflineUserId(userId: number)
	local success, err = pcall(function()
		playerStore:RemoveAsync(tostring(userId))
	end)
	if not success then
		warn(("ProfileAdmin: failed to wipe UserId %d – %s"):format(userId, err))
	end
end

------------------------  CHAT COMMAND HOOK  -------------------------
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(rawMsg: string)
		----------------------------------------------------------------------
		-- 1. Gate-keep: correct command & sender is admin
		----------------------------------------------------------------------
		local lower = string.lower(rawMsg)
		if not (
			lower:sub(1, 3)  == "/rp"
			or lower:sub(1, 14) == "/resetprofile"
		) or not isAdmin(player.UserId) then
			return
		end

		----------------------------------------------------------------------
		-- 2. Parse arguments  (/rp [username])
		----------------------------------------------------------------------
		local parts = string.split(rawMsg, " ")
		local targetName = parts[2] -- may be nil

		-- Default to sender if no argument supplied
		if not targetName or targetName == "" then
			wipeOnlinePlayer(player)
			return
		end

		----------------------------------------------------------------------
		-- 3. Attempt to locate target **online** first
		----------------------------------------------------------------------
		local targetPlayer = Players:FindFirstChild(targetName)
		if targetPlayer then
			wipeOnlinePlayer(targetPlayer)
			return
		end

		----------------------------------------------------------------------
		-- 4. Otherwise resolve **offline** user and wipe DataStore key
		----------------------------------------------------------------------
		local success, userIdOrErr = pcall(function()
			return Players:GetUserIdFromNameAsync(targetName)
		end)

		if success and typeof(userIdOrErr) == "number" and userIdOrErr > 0 then
			wipeOfflineUserId(userIdOrErr)
			player:SendSystemMessage(
				("ProfileAdmin: wiped offline profile for %s (UserId %d)")
				:format(targetName, userIdOrErr),
				"System"
			)
		else
			player:SendSystemMessage(
				("ProfileAdmin: could not find user '%s'"):format(targetName),
				"System"
			)
		end
	end)
end)

----------------------------------------------------------------------
-- DataManager should still delete the key on PlayerRemoving when
-- WipeProfile == true, exactly as in the original script.
----------------------------------------------------------------------
