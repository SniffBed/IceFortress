--!strict
-- Placement.server.lua – growth timers persist exactly via nextGrowthTime

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
local DataManager  = require(game:GetService("ServerScriptService")
                        :WaitForChild("Server"):WaitForChild("DataManager"))

----------------------------------------------------------------------
-- refs
----------------------------------------------------------------------
local BASE_CRYSTAL = ServerStorage:WaitForChild("FrostCrystal") :: Model
local placedFolder = Workspace:FindFirstChild("PlacedShards") or Instance.new("Folder", Workspace)
placedFolder.Name  = "PlacedShards"

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function removeTool(plr: Player, rarity: string, struct: string)
    for _,bag in ipairs({plr.Backpack, plr.Character}) do
        for _,t in ipairs(bag:GetChildren()) do
            if t:IsA("Tool")
               and t:GetAttribute("Rarity")==rarity
               and t:GetAttribute("Structure")==struct then
                t:Destroy(); return
            end
        end
    end
end

local function vec(tbl): Vector3 return Vector3.new(tbl.x,tbl.y,tbl.z) end

----------------------------------------------------------------------
-- income loop – starts only at Stage 10
----------------------------------------------------------------------
local function startIncome(container: Model, plr: Player, inc: number)
    plr:SetAttribute("MoneyPerMinute",
        (plr:GetAttribute("MoneyPerMinute") or 0) + inc)

    task.spawn(function()
        local carry = 0
        while container.Parent do
            task.wait(3)
            carry += inc / 20
            if carry >= 1 then
                local whole = math.floor(carry); carry -= whole
                local prof  = DataManager.GetProfile(plr)
                if not prof then break end
                prof.Data.Cash += whole
                local ls = plr:FindFirstChild("leaderstats")
                if ls then ls.Cash.Value = prof.Data.Cash end
                plr:SetAttribute("Cash", prof.Data.Cash)
            end
        end
    end)
end

----------------------------------------------------------------------
-- spawn container
----------------------------------------------------------------------
local function spawnContainer(plr: Player, rarity: string, struct: string, stage: number, pos: Vector3)
    local container = Instance.new("Model")
    container.Name, container.Parent = struct, placedFolder
    container:SetAttribute("Owner", plr.UserId)

    local modelSrc = ShardDefs[rarity].Structures[struct].Stages[stage][1] or BASE_CRYSTAL
    local model    = modelSrc:Clone(); model.Parent = container

    local cf, sz   = model:GetBoundingBox()
    model:PivotTo(CFrame.new(pos.X, pos.Y + sz.Y*0.5, pos.Z) * (cf - cf.Position))

    if stage == ShardDefs.MAX_STAGE then
        startIncome(container, plr, ShardDefs[rarity].Structures[struct].BaseIncome)
    end
    return container
end

----------------------------------------------------------------------
-- grow
----------------------------------------------------------------------
local function grow(container: Model, rec, plr: Player)
    local rarity, struct = rec.rarity, rec.structure
    local curStage       = rec.stage
    local nextStage      = curStage + 1
    if nextStage > ShardDefs.MAX_STAGE then return end

    -- variants
    local variants = ShardDefs[rarity].Structures[struct].Stages[nextStage]
    if not variants or #variants==0 then return end

    -- ground anchor
    local oldCF, oldSz = container:GetBoundingBox()
    local groundY      = oldCF.Position.Y - oldSz.Y*0.5
    for _,c in ipairs(container:GetChildren()) do c:Destroy() end
    local m = variants[math.random(#variants)]:Clone(); m.Parent = container
    local newCF, newSz = m:GetBoundingBox()
    m:PivotTo(CFrame.new(oldCF.Position.X, groundY + newSz.Y*0.5, oldCF.Position.Z) * (newCF - newCF.Position))

    -- update profile
    rec.stage          = nextStage
    local dur          = ShardDefs:GetStageDuration(rarity, struct)
    rec.nextGrowthTime = os.time() + dur

    if Remotes.ShardGrew then
        Remotes.ShardGrew:FireAllClients(container, rarity, struct, nextStage)
    end

    if nextStage == ShardDefs.MAX_STAGE then
        startIncome(container, plr, ShardDefs[rarity].Structures[struct].BaseIncome)
        rec.nextGrowthTime = nil
    else
        task.delay(dur, function()
            if container.Parent then grow(container, rec, plr) end
        end)
    end
end

----------------------------------------------------------------------
-- place shard
----------------------------------------------------------------------
Remotes.PlaceShard.OnServerEvent:Connect(function(plr: Player, rarity: string, struct: string, pos: Vector3)
    local profile = DataManager.GetProfile(plr); if not profile then return end

    -- remove one rarity from inventory list
    for i,r in ipairs(profile.Data.Inventory) do if r==rarity then table.remove(profile.Data.Inventory,i); break end end
    Remotes.InventoryUpdate:FireClient(plr, profile.Data.Inventory)
    removeTool(plr, rarity, struct)

    local dur   = ShardDefs:GetStageDuration(rarity, struct)
    local rec = {
        id              = HttpService:GenerateGUID(false),
        rarity          = rarity,
        structure       = struct,
        stage           = 1,
        pos             = {x=pos.X,y=pos.Y,z=pos.Z},
        nextGrowthTime  = os.time() + dur,
    }
    table.insert(profile.Data.PlacedShards, rec)

    local cont = spawnContainer(plr, rarity, struct, 1, pos)
    task.delay(dur, function() if cont.Parent then grow(cont, rec, plr) end end)
end)

----------------------------------------------------------------------
-- restore on rejoin
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(pl)
    repeat task.wait() until DataManager.GetProfile(pl)
    local profile = DataManager.GetProfile(pl)
    pl:SetAttribute("MoneyPerMinute",0)

    for _,rec in ipairs(profile.Data.PlacedShards) do
        local pos = vec(rec.pos)
        local cont= spawnContainer(pl, rec.rarity, rec.structure, rec.stage, pos)

        if rec.nextGrowthTime then
            local wait = math.max(rec.nextGrowthTime - os.time(), 0)
            task.delay(wait, function()
                if cont.Parent then grow(cont, rec, pl) end
            end)
        end
    end
end)
