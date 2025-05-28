--!strict
-- Placement.server.lua  – spawns a shard part, starts its income loop,
-- and keeps Cash + MoneyPerMinute in sync.

----------------------------------------------------------------------
--  Services / modules
----------------------------------------------------------------------
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")
local Workspace          = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes      = require(sharedFolder:WaitForChild("Remotes"))

local serverFolder = game:GetService("ServerScriptService"):WaitForChild("Server")
local DataManager  = require(serverFolder:WaitForChild("DataManager"))

----------------------------------------------------------------------
--  References
----------------------------------------------------------------------
local PART_NAME   = "FrostCrystal"                      -- model in ServerStorage
local baseCrystal = ServerStorage:WaitForChild(PART_NAME) :: BasePart

local placedFolder = Workspace:FindFirstChild("PlacedShards")
    or Instance.new("Folder", Workspace)
placedFolder.Name = "PlacedShards"

----------------------------------------------------------------------
--  Constants
----------------------------------------------------------------------
local RARITY_COLORS = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(0, 255, 0),
    Rare      = Color3.fromRGB(0, 170, 255),
    Legendary = Color3.fromRGB(255, 170, 0),
}

-- Lowest income per minute in each tier (from the design table)
local INCOME_PER_MIN = {
    Common    = 1,    -- Snow Pile
    Uncommon  = 5,      -- Ice Archway
    Rare      = 25,     -- Ice Bridge
    Legendary = 100,    -- Ice Palace
}

----------------------------------------------------------------------
--  Helper: remove one shard Tool so hotbar updates
----------------------------------------------------------------------
local function destroyOneTool(player: Player, rarity: string)
    local name = rarity .. "Shard"
    for _, container in ipairs({ player.Backpack, player.Character }) do
        local t = container and container:FindFirstChild(name)
        if t and t:IsA("Tool") then
            t:Destroy()
            break
        end
    end
end

----------------------------------------------------------------------
--  Remote handler
----------------------------------------------------------------------
Remotes.PlaceShard.OnServerEvent:Connect(function(player: Player, arg1, hitPos: Vector3)
    print(("» [PlaceShard] %s | arg=%s"):format(player.Name, tostring(arg1)))

    -- 1) profile
    local profile = DataManager.GetProfile(player)
    if not profile then return end
    local data = profile.Data

    -- 2) resolve rarity + remove from inventory
    local rarity: string?
    if typeof(arg1) == "string" then
        rarity = arg1
        for i, r in ipairs(data.Inventory) do
            if r == rarity then table.remove(data.Inventory, i) break end
        end
    elseif typeof(arg1) == "number" then
        rarity = data.Inventory[arg1]
        table.remove(data.Inventory, arg1)
    end
    if not rarity then return end

    Remotes.InventoryUpdate:FireClient(player, data.Inventory)
    destroyOneTool(player, rarity)

    ------------------------------------------------------------------
    -- 3) clone & place
    ------------------------------------------------------------------
    local part = baseCrystal:Clone()
    part.Name      = rarity .. "ShardPlaced"
    part.Color     = RARITY_COLORS[rarity] or part.Color
    part.Anchored  = true

    local finalPos = hitPos + Vector3.new(0, part.Size.Y * 0.5, 0)
    part.CFrame    = CFrame.new(finalPos)
    part.Parent    = placedFolder
    print(("   ✔ placed %s at %.1f, %.1f, %.1f"):format(part.Name, finalPos.X, finalPos.Y, finalPos.Z))

    ------------------------------------------------------------------
    -- 4) bump Money‑per‑Minute attribute once
    ------------------------------------------------------------------
    local incPerMin = INCOME_PER_MIN[rarity] or 0
    local newMPM    = (player:GetAttribute("MoneyPerMinute") or 0) + incPerMin
    player:SetAttribute("MoneyPerMinute", newMPM)

    ------------------------------------------------------------------
    -- 5) shard income loop (3‑second ticks)
    ------------------------------------------------------------------
    local carry = 0   -- fractional dollars
    task.spawn(function()
        while part.Parent do
            task.wait(3)
            local perTick = incPerMin / 20          -- 60 s / 3 s = 20 ticks
            carry += perTick
            if carry >= 1 then
                local whole = math.floor(carry)
                carry -= whole

                -- deposit
                local prof = DataManager.GetProfile(player)
                if not prof then break end
                prof.Data.Cash += whole

                local cashVal = player:FindFirstChild("leaderstats") and
                                player.leaderstats:FindFirstChild("Cash")
                if cashVal then cashVal.Value = prof.Data.Cash end
                player:SetAttribute("Cash", prof.Data.Cash)
            end
        end
    end)
end)
