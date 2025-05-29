--!strict
-- ShardMarket: now shows ALL 12 shards with unique colours
-- and prices, plus rarity‑colour outline (client‑side).

----------------------------------------------------------------------
--  Services / modules
----------------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

local sharedFolder  = ReplicatedStorage:WaitForChild("Shared")
local Remotes       = require(sharedFolder:WaitForChild("Remotes"))
local ShardDefs     = require(sharedFolder:WaitForChild("ShardDefinitions"))
local DataManager   = require(script.Parent:WaitForChild("DataManager"))

----------------------------------------------------------------------
--  RemoteEvent: countdown
----------------------------------------------------------------------
local marketRemote = sharedFolder:FindFirstChild("MarketUpdate") or Instance.new("RemoteEvent", sharedFolder)
marketRemote.Name  = "MarketUpdate"

----------------------------------------------------------------------
--  Helper: pick a random structure by rarity weighting
----------------------------------------------------------------------
type Rarity = "Common"|"Uncommon"|"Rare"|"Legendary"
local function rollStructure(): (Rarity,string)
    -- roll rarity first
    local roll = math.random(1,100)
    local rarity: Rarity
    if roll <= 60 then       rarity = "Common"
    elseif roll <= 90 then   rarity = "Uncommon"
    elseif roll <= 99 then   rarity = "Rare"
    else                     rarity = "Legendary"
    end
    -- pick one of that rarity’s 3 structures
    local structs = ShardDefs[rarity].Structures
    local keys = {}
    for k in pairs(structs) do keys[#keys+1] = k end
    local structure = keys[math.random(1,#keys)]
    return rarity, structure
end

----------------------------------------------------------------------
--  Market objects
----------------------------------------------------------------------
local baseCrystal = ServerStorage:WaitForChild("FrostCrystal") :: BasePart
local marketTable = workspace:WaitForChild("ShardMarket")      :: Model
local marketFolder = workspace:FindFirstChild("ShardMarketItems") or Instance.new("Folder", workspace)
marketFolder.Name  = "ShardMarketItems"

-- invisible anchor for countdown billboard
local timerPart = workspace:FindFirstChild("MarketTimerPart") or (function()
    local p = Instance.new("Part")
    p.Name, p.Size, p.Transparency, p.Anchored, p.CanCollide = "MarketTimerPart", Vector3.new(2,2,2), 1, true, false
    p.Parent = workspace
    return p
end)()

local function positionTimer()
    local pp = marketTable.PrimaryPart
    if pp then timerPart.Position = pp.Position + Vector3.new(0, pp.Size.Y*0.5 + 4, 0) end
end

----------------------------------------------------------------------
--  Spawn logic
----------------------------------------------------------------------
local promptConns = {} :: {RBXScriptConnection}
local REFRESH_INTERVAL = 60
local nextRefreshTime  = os.time() + REFRESH_INTERVAL

local function broadcastTime()
    for _,plr in ipairs(Players:GetPlayers()) do
        marketRemote:FireClient(plr, nextRefreshTime)
    end
end

local function spawnShards()
    -- cleanup
    for _,c in ipairs(promptConns) do c:Disconnect() end
    promptConns = {}
    marketFolder:ClearAllChildren()

    -- positions
    positionTimer()
    local w = marketTable.PrimaryPart.Size.X
    local spacing = w/6
    local offsets = {
        Vector3.new(-2*spacing,0,0),
        Vector3.new(-spacing,0,0),
        Vector3.new(0,0,0),
        Vector3.new(spacing,0,0),
        Vector3.new(2*spacing,0,0),
    }

    ------------------------------------------------------------------
    -- Five random shards
    ------------------------------------------------------------------
    for i = 1,5 do
        local rarity, structure = rollStructure()
        local sInfo   = ShardDefs[rarity].Structures[structure]
        local crystal = baseCrystal:Clone()

        crystal.Color    = sInfo.Color or ShardDefs[rarity].Color
        crystal.Anchored = true
        crystal.Name     = structure
        crystal:SetAttribute("Cost",    sInfo.Cost)
        crystal:SetAttribute("Rarity",  rarity)
        crystal:SetAttribute("Structure", structure)

        -- position
        local pp   = marketTable.PrimaryPart
        local base = pp.Position + offsets[i]
        local yOff = crystal.Size.Y*0.5
        crystal.CFrame = CFrame.new(base + Vector3.new(0, pp.Size.Y*0.5 + yOff, 0))
        crystal.Parent = marketFolder

        -- prompt
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Buy"
        prompt.ObjectText = structure:gsub("(%l)(%u)","%1 %2") .. " Shard"
        prompt.MaxActivationDistance = 12
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.Enabled = false
        prompt.Parent  = crystal

        local conn = prompt.Triggered:Connect(function(player: Player)
            local profile = DataManager.GetProfile(player)
            if not profile then return end

            local balance = player.leaderstats.Cash.Value
            local price   = crystal:GetAttribute("Cost") or 0
            if balance < price then return end

            -------------- deduct
            profile.Data.Cash = balance - price
            player.leaderstats.Cash.Value = profile.Data.Cash
            player:SetAttribute("Cash", profile.Data.Cash)

            -------------- inventory + tool
            table.insert(profile.Data.Inventory, rarity)                -- profile still stores rarity
            DataManager.GiveShardTool(player, rarity, structure)        -- tool shows structure

            marketRemote:FireClient(player, nextRefreshTime, profile.Data.Inventory)
            crystal:Destroy()
        end)
        promptConns[#promptConns+1] = conn
    end
end

spawnShards()
broadcastTime()

task.spawn(function()
    while true do
        task.wait(REFRESH_INTERVAL)
        nextRefreshTime = os.time() + REFRESH_INTERVAL
        spawnShards()
        broadcastTime()
    end
end)

Players.PlayerAdded:Connect(function(p) marketRemote:FireClient(p, nextRefreshTime) end)
