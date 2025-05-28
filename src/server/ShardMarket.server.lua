--!strict
-- ShardMarket.server.lua
-- Spawns 5 shards on the market table, handles purchases, and
-- broadcasts a live countdown (“Next refresh in Xs”) to all clients.

----------------------------------------------------------------------
--  Services / modules
----------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local RunService         = game:GetService("RunService")

local sharedFolder       = ReplicatedStorage:WaitForChild("Shared")
local Remotes            = require(sharedFolder:WaitForChild("Remotes"))
local DataManager        = require(script.Parent:WaitForChild("DataManager"))

----------------------------------------------------------------------
--  RemoteEvent for countdown updates  (create if missing)
----------------------------------------------------------------------
local marketRemote = sharedFolder:FindFirstChild("MarketUpdate") :: RemoteEvent?
if not marketRemote then
    marketRemote = Instance.new("RemoteEvent")
    marketRemote.Name = "MarketUpdate"
    marketRemote.Parent = sharedFolder
end

----------------------------------------------------------------------
--  Economy tables
----------------------------------------------------------------------
type Rarity = "Common" | "Uncommon" | "Rare" | "Legendary"

local RARITY_COLORS: {[Rarity]: Color3} = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(0, 255, 0),
    Rare      = Color3.fromRGB(0, 170, 255),
    Legendary = Color3.fromRGB(255, 170, 0),
}

local RARITY_COSTS: {[Rarity]: number} = {
    Common    = 10,       -- Frost Crystal
    Uncommon  = 200,      -- Ice Archway
    Rare      = 2000,     -- Ice Bridge
    Legendary = 25000,    -- Ice Palace
}

----------------------------------------------------------------------
--  Market objects
----------------------------------------------------------------------
local baseCrystal = ServerStorage:WaitForChild("FrostCrystal") :: BasePart
local marketTable = workspace:WaitForChild("ShardMarket")      :: Model

-- Folder that holds the spawned crystals
local marketFolder = workspace:FindFirstChild("ShardMarketItems") or Instance.new("Folder", workspace)
marketFolder.Name = "ShardMarketItems"

-- Invisible anchor part for the countdown BillboardGui (clients attach)
local timerPart = workspace:FindFirstChild("MarketTimerPart") :: Part?
if not timerPart then
    timerPart = Instance.new("Part")
    timerPart.Name = "MarketTimerPart"
    timerPart.Size = Vector3.new(2,2,2)
    timerPart.Transparency = 1
    timerPart.Anchored = true
    timerPart.CanCollide = false
    timerPart.Parent = workspace
end

----------------------------------------------------------------------
--  Helpers
----------------------------------------------------------------------
local function getRandomRarity(): Rarity
    local roll = math.random(1, 100)
    if roll <= 60 then return "Common"
    elseif roll <= 90 then return "Uncommon"
    elseif roll <= 99 then return "Rare"
    else return "Legendary" end
end

local function positionTimerPart()
    local pp = marketTable.PrimaryPart
    if pp then
        timerPart.Position = pp.Position + Vector3.new(0, pp.Size.Y * 0.5 + 4, 0)
    end
end

----------------------------------------------------------------------
--  Spawn shards + prompt logic
----------------------------------------------------------------------
local promptConnections = {} :: {RBXScriptConnection}
local REFRESH_INTERVAL  = 60
local nextRefreshTime   = os.time() + REFRESH_INTERVAL

local function broadcastRefreshTime()
    for _, plr in ipairs(Players:GetPlayers()) do
        marketRemote:FireClient(plr, nextRefreshTime)
    end
end

local function spawnMarketShards()
    -- cleanup
    for _, c in ipairs(promptConnections) do c:Disconnect() end
    promptConnections = {}
    marketFolder:ClearAllChildren()

    -- recompute offsets
    positionTimerPart()
    local width   = marketTable.PrimaryPart.Size.X
    local spacing = width / 6
    local offsets = {
        Vector3.new(-2*spacing,0,0),
        Vector3.new(-1*spacing,0,0),
        Vector3.new( 0,0,0),
        Vector3.new( 1*spacing,0,0),
        Vector3.new( 2*spacing,0,0),
    }

    ------------------------------------------------------------------
    -- create 5 crystals
    ------------------------------------------------------------------
    for i = 1, 5 do
        local rarity: Rarity = getRandomRarity()
        local cost          = RARITY_COSTS[rarity]
        local crystal       = baseCrystal:Clone()

        crystal.Color    = RARITY_COLORS[rarity]
        crystal.Anchored = true
        crystal.Name     = rarity .. "Shard"
        crystal:SetAttribute("Cost", cost)

        -- position
        local pp     = marketTable.PrimaryPart
        local base   = pp.Position + offsets[i]
        local yOff   = crystal.Size.Y * 0.5
        crystal.CFrame = CFrame.new(base + Vector3.new(0, pp.Size.Y * 0.5 + yOff, 0))
        crystal.Parent = marketFolder

        -- prompt
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText           = "Buy"
        prompt.ObjectText           = rarity .. " Shard"
        prompt.MaxActivationDistance= 12
        prompt.KeyboardKeyCode      = Enum.KeyCode.E
        prompt.Enabled              = false
        prompt.Parent               = crystal

        local conn = prompt.Triggered:Connect(function(player: Player)
            local profile = DataManager.GetProfile(player)
            if not profile then return end

            local cashVal = player:WaitForChild("leaderstats"):WaitForChild("Cash") :: IntValue
            local balance = cashVal.Value
            local price   = crystal:GetAttribute("Cost") or 0

            print(string.format("[Market] %s tries to buy %s ($%d) | balance=$%d",
                player.Name, rarity, price, balance))

            if balance < price then return end

            -- deduct
            local newBal = balance - price
            cashVal.Value            = newBal
            profile.Data.Cash        = newBal
            player:SetAttribute("Cash", newBal)

            -- inventory + tool
            table.insert(profile.Data.Inventory, rarity)
            DataManager.GiveShardTool(player, rarity)
            marketRemote:FireClient(player, nextRefreshTime, profile.Data.Inventory)

            crystal:Destroy()
        end)
        table.insert(promptConnections, conn)
    end
end

----------------------------------------------------------------------
--  Initialize + refresh loop
----------------------------------------------------------------------
spawnMarketShards()
broadcastRefreshTime()

task.spawn(function()
    while true do
        task.wait(REFRESH_INTERVAL)
        nextRefreshTime = os.time() + REFRESH_INTERVAL
        spawnMarketShards()
        broadcastRefreshTime()
    end
end)

----------------------------------------------------------------------
--  Send countdown to late joiners
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
    marketRemote:FireClient(plr, nextRefreshTime)
end)
