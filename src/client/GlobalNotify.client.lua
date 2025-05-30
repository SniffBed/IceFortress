--!strict
-- Shows a banner to every player when the server broadcasts a global message

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared   = ReplicatedStorage:WaitForChild("Shared")
local Remotes  = require(shared:WaitForChild("Remotes"))
local Notifier = require(script.Parent:WaitForChild("Notifier"))

Remotes.GlobalNotify.OnClientEvent:Connect(function(msg: string)
    Notifier.Show(msg)            -- shows to ALL players
end)
