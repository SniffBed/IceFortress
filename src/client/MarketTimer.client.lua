--!strict
-- MarketTimer.client.lua
-- Renders a floating countdown above the shard market.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder  = ReplicatedStorage:WaitForChild("Shared")
local Remotes       = require(sharedFolder:WaitForChild("Remotes"))

local player    = Players.LocalPlayer
local timerPart = workspace:WaitForChild("MarketTimerPart") :: BasePart

--------------------------------------------------------------------
-- BillboardGui
--------------------------------------------------------------------
local billboard = Instance.new("BillboardGui")
billboard.Size                     = UDim2.new(0, 200, 0, 50)
billboard.StudsOffsetWorldSpace    = Vector3.new(0, 1, 0)
billboard.AlwaysOnTop              = true
billboard.Name                     = "MarketCountdown"
billboard.Parent                   = timerPart

local label = Instance.new("TextLabel")
label.Size               = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.TextColor3         = Color3.new(1,1,1)
label.TextStrokeTransparency = 0
label.Font               = Enum.Font.SourceSansBold
label.TextScaled         = true
label.Parent             = billboard

--------------------------------------------------------------------
-- Listen for refresh‑time broadcasts
--------------------------------------------------------------------
local nextRefresh = os.time() + 60   -- sensible default

local function handleMarketUpdate(...)
    local a, b = ...
    -- If server sent only the timestamp
    if typeof(a) == "number" and b == nil then
        nextRefresh = a
    -- If server sent (itemName, timestamp)
    elseif typeof(b) == "number" then
        nextRefresh = b
    end
end

local marketEvent = sharedFolder:WaitForChild("MarketUpdate") :: RemoteEvent
marketEvent.OnClientEvent:Connect(handleMarketUpdate)

--------------------------------------------------------------------
-- Countdown render
--------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    local remaining = math.max(0, nextRefresh - os.time())
    label.Text = string.format("Next refresh in %ds", remaining)
end)
