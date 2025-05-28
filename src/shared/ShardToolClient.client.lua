--!strict
-- ShardToolClient
-- LocalScript that lives INSIDE every shard Tool.
-- When the tool is equipped, left‑clicking places that shard at the
-- surface point under the mouse cursor.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local sharedFolder       = ReplicatedStorage:WaitForChild("Shared")
local Remotes            = require(sharedFolder:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local tool   = script.Parent

--------------------------------------------------------------------
-- Helper: send placement request
--------------------------------------------------------------------
local function requestPlace(hitPos: Vector3)
    local rarity = tool:GetAttribute("Rarity")
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
