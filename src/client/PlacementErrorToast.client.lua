--!strict
-- Displays a banner when placement is rejected

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(shared:WaitForChild("Remotes"))
local Notifier = require(script.Parent:WaitForChild("Notifier"))


Remotes.PlacementError.OnClientEvent:Connect(function(msg: string)
    Notifier.Show("Placement failed: " .. msg)
end)
