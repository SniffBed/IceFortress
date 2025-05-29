--!strict
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer
local tool   = script.Parent
local rarity = tool:GetAttribute("Rarity")   -- cached once

--------------------------------------------------------------------
local function requestPlace(hitPos: Vector3)
    if rarity then
        Remotes.PlaceShard:FireServer(rarity, hitPos)
    end
end

--------------------------------------------------------------------
-- Mouse handling when equipped
--------------------------------------------------------------------
tool.Equipped:Connect(function(mouse)
    -- Left click (mouse.Button1Down) places the shard
    mouse.Button1Down:Connect(function()
        -- Raycast from mouse to find the exact surface point
        local unitRay   = mouse.UnitRay
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = { player.Character }
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist

        local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
        if result then
            requestPlace(result.Position)
        end
    end)
end)
