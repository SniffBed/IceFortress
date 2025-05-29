--!strict
-- Placement.server.lua – income only after FULL growth (Stage 10)

----------------------------------------------------------------------
-- services / modules
----------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Remotes      = require(sharedFolder:WaitForChild("Remotes"))
local ShardDefs    = require(sharedFolder:WaitForChild("ShardDefinitions"))

local serverFolder = game:GetService("ServerScriptService"):WaitForChild("Server")
local DataManager  = require(serverFolder:WaitForChild("DataManager"))

----------------------------------------------------------------------
-- refs
----------------------------------------------------------------------
local BASE_CRYSTAL = ServerStorage:WaitForChild("FrostCrystal") :: Model
local placedFolder = Workspace:FindFirstChild("PlacedShards") or Instance.new("Folder", Workspace)
placedFolder.Name  = "PlacedShards"

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function destroyOneTool(plr: Player, rarity: string)
    for _,bag in ipairs({plr.Backpack, plr.Character}) do
        for _,t in ipairs(bag:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("Rarity") == rarity then t:Destroy(); return end
        end
    end
end

local function pickStructure(rarity: string): string
    for k in pairs(ShardDefs[rarity].Structures) do return k end
    return "Unknown"
end

local function vec(tbl): Vector3 return Vector3.new(tbl.x, tbl.y, tbl.z) end

----------------------------------------------------------------------
-- start passive income loop for a grown shard
----------------------------------------------------------------------
local function startIncome(container: Model, plr: Player, incPerMin: number)
    -- bump MPM once
    plr:SetAttribute("MoneyPerMinute",
        (plr:GetAttribute("MoneyPerMinute") or 0) + incPerMin
    )

    task.spawn(function()
        local carry = 0
        while container.Parent do
            task.wait(3)
            carry += incPerMin / 20
            if carry >= 1 then
                local whole = math.floor(carry); carry -= whole
                local profile = DataManager.GetProfile(plr)
                if not profile then break end
                profile.Data.Cash += whole
                local ls = plr:FindFirstChild("leaderstats")
                if ls then ls.Cash.Value = profile.Data.Cash end
                plr:SetAttribute("Cash", profile.Data.Cash)
            end
        end
    end)
end

----------------------------------------------------------------------
-- spawn container (Stage‑aware placement)
----------------------------------------------------------------------
local function spawnContainer(plr: Player, rarity: string, structure: string, stage: number, hitPos: Vector3)
    local container = Instance.new("Model")
    container.Name, container.Parent = structure, placedFolder
    container:SetAttribute("Owner", plr.UserId)

    local model = (ShardDefs[rarity].Structures[structure].Stages[stage][1] or BASE_CRYSTAL):Clone()
    model.Parent = container

    local cf, sz = model:GetBoundingBox()
    local rot    = cf - cf.Position
    model:PivotTo(CFrame.new(hitPos.X, hitPos.Y + sz.Y*0.5, hitPos.Z) * rot)

    -- if already full‑grown (restored), kick off income
    if stage == ShardDefs.MAX_STAGE then
        local inc = ShardDefs[rarity].Structures[structure].BaseIncome
        startIncome(container, plr, inc)
    end
    return container
end

----------------------------------------------------------------------
-- growth swap
----------------------------------------------------------------------
local function transformShard(container: Model, rec, plr: Player)
    local rar, struct = rec.rarity, rec.structure
    local nextStage   = rec.stage + 1
    if nextStage > ShardDefs.MAX_STAGE then return end

    local variants = ShardDefs[rar].Structures[struct].Stages[nextStage]
    if not variants or #variants == 0 then return end

    local oldCF, oldSz = container:GetBoundingBox()
    local groundY      = oldCF.Position.Y - oldSz.Y*0.5

    for _,c in ipairs(container:GetChildren()) do c:Destroy() end
    local newModel = variants[math.random(#variants)]:Clone()
    newModel.Parent = container
    local newCF, newSz = newModel:GetBoundingBox()
    newModel:PivotTo(CFrame.new(oldCF.Position.X, groundY + newSz.Y*0.5, oldCF.Position.Z) * (newCF - newCF.Position))

    rec.stage, rec.lastStageTime = nextStage, os.time()
    if Remotes.ShardGrew then
        Remotes.ShardGrew:FireAllClients(container, rar, struct, nextStage)
    end

    if nextStage == ShardDefs.MAX_STAGE then
        local inc = ShardDefs[rar].Structures[struct].BaseIncome
        startIncome(container, plr, inc)
    else
        local dur = ShardDefs:GetStageDuration(rar, struct)
        task.delay(dur, function() if container.Parent then transformShard(container, rec, plr) end end)
    end
end

----------------------------------------------------------------------
-- place shard remote
----------------------------------------------------------------------
Remotes.PlaceShard.OnServerEvent:Connect(function(plr: Player, rarity: string, hitPos: Vector3)
    local profile = DataManager.GetProfile(plr)
    if not profile then return end
    -- remove one from inventory list
    for i,r in ipairs(profile.Data.Inventory) do if r==rarity then table.remove(profile.Data.Inventory,i) break end end
    Remotes.InventoryUpdate:FireClient(plr, profile.Data.Inventory)
    destroyOneTool(plr, rarity)

    local struct = pickStructure(rarity)
    local rec = {
        id = HttpService:GenerateGUID(false),
        rarity = rarity,
        structure = struct,
        stage = 1,
        pos = {x = hitPos.X, y = hitPos.Y, z = hitPos.Z},
        lastStageTime = os.time(),
    }
    table.insert(profile.Data.PlacedShards, rec)

    local container = spawnContainer(plr, rarity, struct, 1, hitPos)

    -- schedule first growth
    local dur = ShardDefs:GetStageDuration(rarity, struct)
    task.delay(dur, function()
        if container.Parent then transformShard(container, rec, plr) end
    end)
end)

----------------------------------------------------------------------
-- restoration on rejoin
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
    repeat task.wait() until DataManager.GetProfile(plr)
    local profile = DataManager.GetProfile(plr)
    plr:SetAttribute("MoneyPerMinute", 0)

    for _,rec in ipairs(profile.Data.PlacedShards) do
        local pos = vec(rec.pos)
        local cont = spawnContainer(plr, rec.rarity, rec.structure, rec.stage, pos)

        if rec.stage < ShardDefs.MAX_STAGE then
            local dur = ShardDefs:GetStageDuration(rec.rarity, rec.structure)
            local wait = math.max(dur - (os.time()-rec.lastStageTime), 0)
            task.delay(wait, function()
                if cont.Parent then transformShard(cont, rec, plr) end
            end)
        end
    end
end)
