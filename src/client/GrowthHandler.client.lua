--!strict
-- src/client/GrowthNotifier.client.lua

local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared    = ReplicatedStorage:WaitForChild("Shared")
local Remotes   = require(shared:WaitForChild("Remotes"))

-- 1) Create the ScreenGui + TextLabel
local gui = Instance.new("ScreenGui")
gui.Name            = "GrowthNotifier"
gui.ResetOnSpawn    = false
gui.Parent          = playerGui

local label = Instance.new("TextLabel")
label.Name               = "GrowthLabel"
label.Size               = UDim2.new(0.5, 0, 0, 50)
label.Position           = UDim2.new(0.5, 0, 0, 20)
label.AnchorPoint        = Vector2.new(0.5, 0)
label.BackgroundTransparency = 1
label.TextScaled         = true
label.Font               = Enum.Font.SourceSansBold
label.TextColor3         = Color3.new(1, 1, 1)
label.TextTransparency   = 1
label.Parent             = gui

-- Helper to convert "IcePillar" → "Ice Pillar"
local function prettify(name: string): string
    return name:gsub("(%l)(%u)", "%1 %2")
end

-- 2) Listen for growth events
Remotes.ShardGrew.OnClientEvent:Connect(function(container: Instance, rarity: string, structureName: string, stage: number)
    -- Build message
    local displayName = prettify(structureName)
    label.Text = displayName .. " grew to Stage " .. stage .. "!"

    -- Fade in
    TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        TextTransparency = 0
    }):Play()

    -- Hold, then fade out
    task.delay(2, function()
        TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            TextTransparency = 1
        }):Play()
    end)
end)
