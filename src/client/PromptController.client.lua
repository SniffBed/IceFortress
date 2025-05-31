--!strict
-- Enables only the nearest prompt and outlines it with rarity colour.
-- Uses Glass material method for transparent parts
-- 2025-05-30: ObjectText = "Buy", ActionText = price
-- 2025-05-30: prettify floating label (CamelCase → spaced words)

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Replicated   = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player       = Players.LocalPlayer
local rootPart: BasePart?
local PlayerGui    = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- Shard definitions & colours
--------------------------------------------------------------------
local ShardDefs     = require(Replicated:WaitForChild("Shared"):WaitForChild("ShardDefinitions"))
local RARITY_COLORS = ShardDefs.RarityColors

--------------------------------------------------------------------
-- Helper: split CamelCase → “Camel Case”
--------------------------------------------------------------------
local function prettify(name: string): string
    return name:gsub("(%l)(%u)", "%1 %2")
end

--------------------------------------------------------------------
-- Character root-part tracking
--------------------------------------------------------------------
local function refreshRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
end
refreshRoot()
player.CharacterAdded:Connect(refreshRoot)

--------------------------------------------------------------------
-- Helpers for transparent-glass workaround
--------------------------------------------------------------------
local function setupTransparentGlass(shard)
    if not shard:GetAttribute("OriginalMaterial") then
        shard:SetAttribute("OriginalMaterial", shard.Material.Name)
        shard:SetAttribute("OriginalReflectance", shard.Reflectance)
    end
    shard.Material    = Enum.Material.Glass
    shard.Reflectance = 0
end
local function restoreOriginalMaterial(shard)
    local originalMaterial    = shard:GetAttribute("OriginalMaterial")
    local originalReflectance = shard:GetAttribute("OriginalReflectance")
    if originalMaterial then
        shard.Material    = Enum.Material[originalMaterial]
        shard.Reflectance = originalReflectance or 0
    end
end

--------------------------------------------------------------------
-- Per-frame loop
--------------------------------------------------------------------
local PROMPT_FOLDER = "ShardMarketItems"
local RADIUS        = 12

RunService.Heartbeat:Connect(function()
    if not rootPart or not rootPart.Parent then return end

    local folder = workspace:FindFirstChild(PROMPT_FOLDER)
    if not folder then return end

    --------------------------------------------------------------
    -- Pass 1: find nearest prompt & set text
    --------------------------------------------------------------
    local nearest, dist = nil, RADIUS + 0.1

    for _, shard in ipairs(folder:GetChildren()) do
        if shard:IsA("BasePart") then
            local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
                    prompt.Style = Enum.ProximityPromptStyle.Custom
                end

                -- look-up cost
                local rarity     = shard:GetAttribute("Rarity") or "Common"
                local structDef  = ShardDefs[rarity] and ShardDefs[rarity].Structures and
                                   ShardDefs[rarity].Structures[shard.Name]
                local price      = structDef and structDef.Cost or 0

                -- prompt text
                prompt.ObjectText = "Buy"
                prompt.ActionText = string.format("$%s", price)

                -- nearest?
                local d = (shard.Position - rootPart.Position).Magnitude
                if d <= prompt.MaxActivationDistance and d < dist then
                    nearest, dist = prompt, d
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Pass 2: enable/disable, outline, billboard
    ----------------------------------------------------------------
    for _, shard in ipairs(folder:GetChildren()) do
        if shard:IsA("BasePart") then
            local prompt = shard:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                local enable = (prompt == nearest)
                prompt.Enabled = enable

                ------------------------------------------------------
                -- Highlight
                ------------------------------------------------------
                local hl = shard:FindFirstChild("ShopHighlight") :: Highlight?
                if enable then
                    if shard.Transparency > 0 then
                        setupTransparentGlass(shard)
                    end
                    if not hl then
                        hl = Instance.new("Highlight")
                        hl.Name = "ShopHighlight"
                        hl.FillTransparency    = 1
                        hl.OutlineTransparency = 0
                        hl.Adornee = shard
                        hl.Parent  = shard
                    end
                    local rarity = shard:GetAttribute("Rarity") or "Common"
                    hl.OutlineColor = RARITY_COLORS[rarity] or Color3.new(1,1,1)
                elseif hl then
                    hl:Destroy()
                    if shard.Transparency > 0 then
                        restoreOriginalMaterial(shard)
                    end
                end

                ------------------------------------------------------
                -- Floating name BillboardGui
                ------------------------------------------------------
                local billboard = shard:FindFirstChild("ShardNameBillboard") :: BillboardGui?
                if enable then
                    if not billboard then
                        billboard = Instance.new("BillboardGui")
                        billboard.Name        = "ShardNameBillboard"
                        billboard.AlwaysOnTop = true
                        billboard.Size        = UDim2.new(0, 200, 0, 40)
                        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
                        billboard.Parent      = shard

                        local label = Instance.new("TextLabel")
                        label.Name                  = "NameLabel"
                        label.Size                  = UDim2.new(1, 0, 1, 0)
                        label.BackgroundTransparency= 1
                        label.Font                  = Enum.Font.GothamBold
                        label.TextScaled            = true
                        label.TextColor3            = RARITY_COLORS[shard:GetAttribute("Rarity") or "Common"]
                        label.Parent                = billboard
                    end
                    -- update text each frame (in case name / rarity changes)
                    local label = billboard:FindFirstChild("NameLabel") :: TextLabel?
                    if label then
                        label.Text      = prettify(shard.Name)
                        label.TextColor3 = RARITY_COLORS[shard:GetAttribute("Rarity") or "Common"]
                    end
                elseif billboard then
                    billboard:Destroy()
                end
            end
        end
    end
end)
