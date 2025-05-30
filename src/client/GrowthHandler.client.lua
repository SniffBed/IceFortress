--!strict
-- Shows a banner when any shard grows

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shared  = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(shared:WaitForChild("Remotes"))
local Notifier = require(script.Parent:WaitForChild("Notifier"))

-- Helper: "IcePillar" → "Ice Pillar"
local function prettify(name: string): string
    return name:gsub("(%l)(%u)", "%1 %2")
end

Remotes.ShardGrew.OnClientEvent:Connect(function(_, _, structureName: string, stage: number)
    local displayName = prettify(structureName)
    Notifier.Show(displayName .. " grew to Stage " .. stage .. "!")
end)
