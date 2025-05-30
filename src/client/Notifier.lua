--!strict
-- Central alert-stack manager (top-center, fade in/out)

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.Parent = "GameNotifier", false, playerGui

-- Vertical stack container
local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.AnchorPoint = Vector2.new(0.5, 0)
stack.Position    = UDim2.new(0.5, 0, 0, 20)
stack.Size        = UDim2.new(1, 0, 0, 0)
stack.BackgroundTransparency = 1
stack.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Top
layout.Padding             = UDim.new(0, 8)
layout.Parent = stack

---------------------------------------------------------------------
local function show(text: string)
    -- one label per message
    local label = Instance.new("TextLabel")
    label.Size                   = UDim2.new(0.6, 0, 0, 50)
    label.BackgroundTransparency = 1
    label.TextScaled             = true
    label.Font                   = Enum.Font.SourceSansBold
    label.TextColor3             = Color3.new(1, 1, 1)
    label.TextTransparency       = 1
    label.Text                  = text
    label.Parent                = stack

    -- Fade in
    TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 0 }):Play()

    -- Hold 2 s, fade out, then remove
    task.delay(2, function()
        TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { TextTransparency = 1 }):Play()
        task.delay(0.5, function() label:Destroy() end)
    end)
end

return { Show = show }
