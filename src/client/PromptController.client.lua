--!strict
-- Client‑side controller:
--   • Finds the player’s HumanoidRootPart every frame
--   • Enables the ProximityPrompt on ONLY the nearest shard
--   • Ignores frames before the ShardMarketItems folder exists

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")

local player      = Players.LocalPlayer
local rootPart: BasePart?   -- will be set / updated below

--------------------------------------------------------------------
-- Helper: always have an up‑to‑date HumanoidRootPart reference
--------------------------------------------------------------------
local function refreshRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart
end

-- Initial fetch
refreshRoot()
-- Update after respawn
player.CharacterAdded:Connect(function()
    refreshRoot()
end)

--------------------------------------------------------------------
-- Per‑frame loop: enable nearest prompt
--------------------------------------------------------------------
local PROMPT_FOLDER_NAME = "ShardMarketItems"
local CHECK_RADIUS       = 12.0   -- must match prompt.MaxActivationDistance

RunService.Heartbeat:Connect(function()
    -- Bail if no character root yet
    if not rootPart or not rootPart.Parent then return end

    -- Wait until the server spawns the market folder
    local marketFolder = workspace:FindFirstChild(PROMPT_FOLDER_NAME)
    if not marketFolder then return end     -- skip this frame

    ----------------------------------------------------------------
    -- Pass 1: find the closest prompt within range
    ----------------------------------------------------------------
    local nearestPrompt: ProximityPrompt? = nil
    local nearestDist    = CHECK_RADIUS + 0.1

    for _, shard in ipairs(marketFolder:GetChildren()) do
        if shard:IsA("BasePart") then
            local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                local dist = (shard.Position - rootPart.Position).Magnitude
                if dist <= prompt.MaxActivationDistance and dist < nearestDist then
                    nearestPrompt = prompt
                    nearestDist   = dist
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Pass 2: enable only the nearest prompt, disable the rest
    ----------------------------------------------------------------
    for _, shard in ipairs(marketFolder:GetChildren()) do
        local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
        if prompt then
            prompt.Enabled = (prompt == nearestPrompt)
        end
    end
end)
