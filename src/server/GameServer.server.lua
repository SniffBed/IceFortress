--!strict
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local placeRemote = Remotes:WaitForChild("PlaceCrystal") :: RemoteEvent

-- Set up leaderstats for each player (to track Cash)
Players.PlayerAdded:Connect(function(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
    local cash = Instance.new("IntValue")
    cash.Name = "Cash"
    cash.Value = 0
    cash.Parent = leaderstats
end)

-- Handle placement requests from clients
placeRemote.OnServerEvent:Connect(function(player, position: Vector3)
    -- Clone the FrostCrystal part and place it at the given position
    local crystalTemplate = ServerStorage:FindFirstChild("FrostCrystal")
    if crystalTemplate and crystalTemplate:IsA("BasePart") then
        local crystal = crystalTemplate:Clone()
        local yOffset = crystal.Size.Y * 0.5         -- part height / 2 :contentReference[oaicite:1]{index=1}
        local finalPos = position + Vector3.new(0, yOffset, 0)
        crystal.CFrame = CFrame.new(finalPos)
        crystal.Anchored = true
        crystal.Parent = workspace
        -- Start generating income for the player every 3 seconds
        task.spawn(function()
            while crystal.Parent ~= nil do
                player.leaderstats.Cash.Value += 1  -- add 1 cash
                task.wait(3)
            end
        end)
    end
end)
