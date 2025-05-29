--!strict
-- Central catalogue of every shard’s data + helper utilities.

----------------------------------------------------------------
-- ▼ Constants
----------------------------------------------------------------
local MAX_STAGE              = 10
local DEFAULT_STAGE_DURATION = 300

local RARITY_WEIGHTS = {
    Common    = 60,
    Uncommon  = 30,
    Rare      = 9,
    Legendary = 1,
}
local RARITY_COLORS = {
    Common    = Color3.fromRGB(200,200,200),
    Uncommon  = Color3.fromRGB(0,255,0),
    Rare      = Color3.fromRGB(0,170,255),
    Legendary = Color3.fromRGB(255,170,0),
}

----------------------------------------------------------------
-- ▼ Structure catalogue
----------------------------------------------------------------
local STRUCTURES = {
    Common = {
        IcePillar     = { Cost = 10,  BaseIncome = 1,   GrowthTime = 10 },
        SnowMound     = { Cost = 15,  BaseIncome = 0.5, GrowthTime = 10 },
        FrozenCube    = { Cost = 20,  BaseIncome = 0.8, GrowthTime = 10 },
    },
    Uncommon = {
        CrystalSpire   = { Cost = 250,  BaseIncome = 5,  GrowthTime = 360 },
        IceArchway     = { Cost = 200,  BaseIncome = 4,  GrowthTime = 420 },
        FrozenFountain = { Cost = 300,  BaseIncome = 6,  GrowthTime = 480 },
    },
    Rare = {
        GlacialTower = { Cost = 2_500, BaseIncome = 25, GrowthTime = 540 },
        IceBridge     = { Cost = 2_000, BaseIncome = 20, GrowthTime = 600 },
        CrystalDome   = { Cost = 3_000, BaseIncome = 30, GrowthTime = 660 },
    },
    Legendary = {
        IcePalace     = { Cost = 25_000, BaseIncome = 100, GrowthTime = 720 },
        FrostThrone   = { Cost = 35_000, BaseIncome = 150, GrowthTime = 780 },
        AuroraGateway = { Cost = 50_000, BaseIncome = 200, GrowthTime = 840 },
    },
}

----------------------------------------------------------------
-- ▼ Export table scaffold
----------------------------------------------------------------
local ShardDefs: any = {
    MAX_STAGE              = MAX_STAGE,
    DEFAULT_STAGE_DURATION = DEFAULT_STAGE_DURATION,
    RarityColors           = RARITY_COLORS,
    RarityWeights          = RARITY_WEIGHTS,
}

for rarity, structs in pairs(STRUCTURES) do
    ShardDefs[rarity] = {
        Color      = RARITY_COLORS[rarity],
        Weight     = RARITY_WEIGHTS[rarity],
        Structures = structs,
    }
end

----------------------------------------------------------------
-- ▼ Helper: stage duration lookup
----------------------------------------------------------------
function ShardDefs:GetStageDuration(rarity: string, structureName: string?): number
    local rDef = self[rarity]
    if not rDef then return DEFAULT_STAGE_DURATION end
    if structureName then
        local sDef = rDef.Structures[structureName]
        return (sDef and sDef.GrowthTime) or DEFAULT_STAGE_DURATION
    else
        local fastest = math.huge
        for _, sDef in pairs(rDef.Structures) do
            if sDef.GrowthTime < fastest then fastest = sDef.GrowthTime end
        end
        return fastest ~= math.huge and fastest or DEFAULT_STAGE_DURATION
    end
end

----------------------------------------------------------------
-- ▼ Server‑only: cache stage models + auto‑colour structures
----------------------------------------------------------------
local RunService = game:GetService("RunService")
if RunService:IsServer() then
    local ServerStorage = game:GetService("ServerStorage")
    local modelsRoot    = ServerStorage:WaitForChild("ShardModels")

    for rarity, rDef in pairs(ShardDefs) do
        if typeof(rDef) == "table" and rDef.Structures then
            local rarityFolder = modelsRoot:FindFirstChild(rarity)
            if rarityFolder then
                for structName, sDef in pairs(rDef.Structures) do
                    local structFolder = rarityFolder:FindFirstChild(structName)
                    if structFolder then
                        ---------------------------- stage cache
                        sDef.Stages = {} :: {[number]: {Instance}}
                        for stage = 1, MAX_STAGE do
                            local stageFolder = structFolder:FindFirstChild("Stage"..stage)
                            if stageFolder then
                                sDef.Stages[stage] = stageFolder:GetChildren()
                            end
                        end
                        ---------------------------- auto‑colour (first Stage1 part)
                        if #sDef.Stages[1] > 0 then
                            local model: Model = sDef.Stages[1][1]
                            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                            if part then sDef.Color = part.Color end
                        end
                    end
                end
            end
        end
    end
end

return ShardDefs
