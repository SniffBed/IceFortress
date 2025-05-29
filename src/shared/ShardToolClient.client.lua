--!strict
-- ShardToolClient – lives INSIDE every shard Tool.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player   = Players.LocalPlayer
local tool     = script.Parent
local rarity   = tool:GetAttribute("Rarity")     -- cached
local structure= tool:GetAttribute("Structure")  -- cached

--------------------------------------------------------------------
local function requestPlace(hitPos: Vector3)
    if rarity and structure then
        -- Send BOTH rarity and structure so server spawns the right model
        Remotes.PlaceShard:FireServer(rarity, structure, hitPos)
    end
end

--------------------------------------------------------------------
tool.Equipped:Connect(function(mouse)
    mouse.Button1Down:Connect(function()
        local ray = workspace:Raycast(
            mouse.UnitRay.Origin,
            mouse.UnitRay.Direction * 1000,
            RaycastParams.new { FilterDescendantsInstances={player.Character}, FilterType=Enum.RaycastFilterType.Blacklist }
        )
        if ray then requestPlace(ray.Position) end
    end)
end)
