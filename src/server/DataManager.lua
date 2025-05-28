--!strict
-- DataManager.lua
-- Loads & saves player profiles via ProfileStore and gives shard Tools
-- to populate the Roblox hotbar.

----------------------------------------------------------------------
--  Services / modules
----------------------------------------------------------------------
local Players            = game:GetService("Players")
local ServerScriptService= game:GetService("ServerScriptService")
local DataStoreService   = game:GetService("DataStoreService")

local serverFolder       = ServerScriptService:WaitForChild("Server")
local ProfileStore       = require(serverFolder:WaitForChild("ProfileStore"))

----------------------------------------------------------------------
--  Profile schema
----------------------------------------------------------------------
export type ProfileData = {
    Cash: number,
    Inventory: { string }
}
local PROFILE_TEMPLATE: ProfileData = {
    Cash = 1000,
    Inventory = {}
}

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
local Profiles: { [Player]: any } = {}

----------------------------------------------------------------------
--  Utility: create a shard Tool so it shows in the hotbar
----------------------------------------------------------------------
local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local scriptTemplate = sharedFolder:WaitForChild("ShardToolClient") :: LocalScript

-- Clone a visible crystal so the player actually holds it
local baseCrystal = game:GetService("ServerStorage"):WaitForChild("FrostCrystal") :: BasePart
local RARITY_COLORS = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(0, 255, 0),
    Rare      = Color3.fromRGB(0, 170, 255),
    Legendary = Color3.fromRGB(255, 170, 0),
}

local scriptTemplate = sharedFolder:WaitForChild("ShardToolClient") :: LocalScript

----------------------------------------------------------------
-- Utility: create a shard Tool so it shows in the hotbar
----------------------------------------------------------------
local function giveShardTool(player: Player, rarity: string)
    ------------------------------------------------------------
    -- Build the Tool shell
    ------------------------------------------------------------
    local tool = Instance.new("Tool")
    tool.Name           = rarity .. "Shard"
    tool.RequiresHandle = true
    tool.CanBeDropped   = false
    tool:SetAttribute("Rarity", rarity)

    -- ▶ Shift the crystal 0.5 stud forward from the hand
    tool.GripPos = Vector3.new(0, 0, 0.5)   -- ← adjust to taste

    ------------------------------------------------------------
    -- Visible Handle (clone the crystal model)
    ------------------------------------------------------------
    local handle = baseCrystal:Clone()
    handle.Name       = "Handle"
    handle.Color      = RARITY_COLORS[rarity] or handle.Color
    handle.Anchored   = false
    handle.CanCollide = false
    handle.Massless   = true
    handle.Parent     = tool

    ------------------------------------------------------------
    -- Placement LocalScript
    ------------------------------------------------------------
    scriptTemplate:Clone().Parent = tool

    ------------------------------------------------------------
    -- Put in Backpack & StarterGear
    ------------------------------------------------------------
    tool.Parent = player.Backpack
    tool:Clone().Parent = player.StarterGear
end

----------------------------------------------------------------------
--  Public getter
----------------------------------------------------------------------
local function GetProfile(player: Player)
    return Profiles[player]
end

----------------------------------------------------------------------
--  Player join
----------------------------------------------------------------------
local function onPlayerAdded(player: Player)
    local profile = PlayerStore:StartSessionAsync(tostring(player.UserId), {
        Cancel = function() return player.Parent ~= Players end
    })
    if not profile then
        player:Kick("Data load failure — please rejoin")
        return
    end

    profile:AddUserId(player.UserId)
    profile:Reconcile()
    Profiles[player] = profile

    -- Leaderstats setup
    local leaderstats = Instance.new("Folder")
    leaderstats.Name  = "leaderstats"
    leaderstats.Parent = player

    local cashVal     = Instance.new("IntValue")
    cashVal.Name      = "Cash"
    cashVal.Value     = profile.Data.Cash
    cashVal.Parent    = leaderstats

    player:SetAttribute("Cash", profile.Data.Cash)
    player:SetAttribute("MoneyPerMinute", 0)

    -- Give tools for each saved shard
    for _, rarity in ipairs(profile.Data.Inventory) do
        giveShardTool(player, rarity)
    end
end

----------------------------------------------------------------------
--  Player leave  (also handles /rp wipe flag)
----------------------------------------------------------------------
local playerStoreRaw = DataStoreService:GetDataStore("PlayerStore")  -- raw key access

local function onPlayerRemoving(player: Player)
    local profile = Profiles[player]

    -- Admin wipe?
    if player:GetAttribute("WipeProfile") then
        pcall(function()
            playerStoreRaw:RemoveAsync(tostring(player.UserId))
        end)
    end

    -- Save latest cash & release session
    if profile then
        local cashVal = player:FindFirstChild("leaderstats") and
                        player.leaderstats:FindFirstChild("Cash")
        if cashVal then
            profile.Data.Cash = cashVal.Value
        end
        profile:EndSession()
        Profiles[player] = nil
    end
end

----------------------------------------------------------------------
--  Connections
----------------------------------------------------------------------
for _, plr in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

return {
    GetProfile      = GetProfile,
    GiveShardTool   = giveShardTool   -- <- expose for ShardMarket
}

