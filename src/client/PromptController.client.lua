--!strict
-- Enables only the nearest prompt and outlines it with rarity colour.
-- Uses Glass material method for transparent parts

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Replicated  = game:GetService("ReplicatedStorage")

local player      = Players.LocalPlayer
local rootPart: BasePart?

local RARITY_COLORS = require(Replicated:WaitForChild("Shared"):WaitForChild("ShardDefinitions")).RarityColors

local function refreshRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
end

refreshRoot()
player.CharacterAdded:Connect(refreshRoot)

-- Function to setup Glass material for transparent highlighting
local function setupTransparentGlass(shard)
    -- Store original material and reflectance
    if not shard:GetAttribute("OriginalMaterial") then
        shard:SetAttribute("OriginalMaterial", shard.Material.Name)
        shard:SetAttribute("OriginalReflectance", shard.Reflectance)
    end
    
    -- Change to Glass material with very low reflectance
    -- This allows highlights to work while keeping transparency
    shard.Material = Enum.Material.Glass
    shard.Reflectance = 0  -- Remove glass shininess without extreme values
end

-- Function to restore original material
local function restoreOriginalMaterial(shard)
    local originalMaterial = shard:GetAttribute("OriginalMaterial")
    local originalReflectance = shard:GetAttribute("OriginalReflectance")
    
    if originalMaterial then
        shard.Material = Enum.Material[originalMaterial]
        shard.Reflectance = originalReflectance or 0
    end
end

--------------------------------------------------------------------
-- Per‐frame loop
--------------------------------------------------------------------

local PROMPT_FOLDER = "ShardMarketItems"
local RADIUS        = 12

RunService.Heartbeat:Connect(function()
    if not rootPart or not rootPart.Parent then return end
    
    local folder = workspace:FindFirstChild(PROMPT_FOLDER)
    if not folder then return end
    
    local nearest, dist = nil, RADIUS+0.1
    
    for _,shard in ipairs(folder:GetChildren()) do
        if shard:IsA("BasePart") then
            local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                local d = (shard.Position - rootPart.Position).Magnitude
                if d <= prompt.MaxActivationDistance and d < dist then
                    nearest, dist = prompt, d
                end
            end
        end
    end
    
    for _,shard in ipairs(folder:GetChildren()) do
        if shard:IsA("BasePart") then
            local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                local enable = (prompt == nearest)
                prompt.Enabled = enable
                
                -- outline logic
                local hl = shard:FindFirstChild("ShopHighlight") :: Highlight?
                if enable then
                    -- If part is transparent, convert to Glass material for highlighting
                    if shard.Transparency > 0 then
                        setupTransparentGlass(shard)
                    end
                    
                    if not hl then
                        hl = Instance.new("Highlight")
                        hl.Name = "ShopHighlight"
                        hl.FillTransparency = 1
                        hl.OutlineTransparency = 0
                        hl.Adornee = shard
                        hl.Parent = shard
                    end
                    local rarity = shard:GetAttribute("Rarity") or "Common"
                    hl.OutlineColor = RARITY_COLORS[rarity] or Color3.new(1,1,1)
                elseif hl then
                    hl:Destroy()
                    -- Restore original material when highlight is removed
                    if shard.Transparency > 0 then
                        restoreOriginalMaterial(shard)
                    end
                end
            end
        end
    end
end)