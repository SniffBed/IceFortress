--!strict
-- InventoryAndPlacement.client.lua
-- Heads‑up display:
--   • Bottom‑left  : Cash balance
--   • Bottom‑right : Income per minute (MoneyPerMinute attribute)
-- Inventory itself is handled by Tools in the default Roblox hotbar.

--------------------------------------------------------------------
--  Services & shared remotes
--------------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes      = require(sharedFolder:WaitForChild("Remotes"))

--------------------------------------------------------------------
--  Build HUD ScreenGui
--------------------------------------------------------------------
local hudGui = Instance.new("ScreenGui")
hudGui.Name           = "HUD"
hudGui.ResetOnSpawn   = false
hudGui.IgnoreGuiInset = false
hudGui.Parent         = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
--  Cash label  (bottom‑left)
--------------------------------------------------------------------
local cashLabel = Instance.new("TextLabel")
cashLabel.Name                   = "CashLabel"
cashLabel.Size                   = UDim2.new(0, 200, 0, 40)
cashLabel.Position               = UDim2.new(0, 10, 1, -50)
cashLabel.BackgroundTransparency = 0.3
cashLabel.BackgroundColor3       = Color3.new(0,0,0)
cashLabel.TextColor3             = Color3.new(1,1,1)
cashLabel.Font                   = Enum.Font.SourceSansBold
cashLabel.TextSize               = 24
cashLabel.TextXAlignment         = Enum.TextXAlignment.Left
cashLabel.Text                   = "Cash: $0"
cashLabel.Parent                 = hudGui

--------------------------------------------------------------------
--  Money‑per‑minute label  (bottom‑right)
--------------------------------------------------------------------
local mpmLabel = Instance.new("TextLabel")
mpmLabel.Name                   = "MPMLabel"
mpmLabel.Size                   = UDim2.new(0, 250, 0, 40)
mpmLabel.Position               = UDim2.new(1, -260, 1, -50) -- 10 px from right
mpmLabel.BackgroundTransparency = 0.3
mpmLabel.BackgroundColor3       = Color3.new(0,0,0)
mpmLabel.TextColor3             = Color3.new(1,1,1)
mpmLabel.Font                   = Enum.Font.SourceSansBold
mpmLabel.TextSize               = 24
mpmLabel.TextXAlignment         = Enum.TextXAlignment.Right
mpmLabel.Text                   = "Income: $0 / min"
mpmLabel.Parent                 = hudGui

--------------------------------------------------------------------
--  Helper updaters
--------------------------------------------------------------------
local function updateCashDisplay(amount: number)
    cashLabel.Text = string.format("Cash: $%d", amount)
end

local function updateMPMDisplay(rate: number)
    mpmLabel.Text = string.format("Income: $%g / min", rate)
end

--------------------------------------------------------------------
--  Initial fetch from server
--------------------------------------------------------------------
local ok, data = pcall(function()
    return Remotes.GetProfileData:InvokeServer()
end)
if ok and typeof(data) == "table" then
    if typeof(data.Cash) == "number"   then updateCashDisplay(data.Cash) end
    if typeof(data.Income) == "number" then updateMPMDisplay(data.Income) end
end

--------------------------------------------------------------------
--  Attribute listeners
--------------------------------------------------------------------
-- Cash
player:GetAttributeChangedSignal("Cash"):Connect(function()
    local value = player:GetAttribute("Cash")
    if typeof(value) == "number" then updateCashDisplay(value) end
end)
updateCashDisplay(player:GetAttribute("Cash") or 0)

-- Money per minute
player:GetAttributeChangedSignal("MoneyPerMinute"):Connect(function()
    local value = player:GetAttribute("MoneyPerMinute")
    if typeof(value) == "number" then updateMPMDisplay(value) end
end)
updateMPMDisplay(player:GetAttribute("MoneyPerMinute") or 0)
