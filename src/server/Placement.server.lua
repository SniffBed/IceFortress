--!strict
-- Placement.server.lua – income starts at Stage 10; uses tool‑passed structure.

----------------------------------------------------------------------
-- Services / modules
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
-- References
----------------------------------------------------------------------
local BASE_CRYSTAL = ServerStorage:WaitForChild("FrostCrystal") :: Model
local placedFolder = Workspace:FindFirstChild("PlacedShards") or Instance.new("Folder", Workspace)
placedFolder.Name  = "PlacedShards"

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function removeTool(player: Player, rarity: string, structure: string)
    for _,bag in ipairs({player.Backpack, player.Character}) do
        for _,t in ipairs(bag:GetChildren()) do
            if t:IsA("Tool")
               and t:GetAttribute("Rarity")    == rarity
               and t:GetAttribute("Structure") == structure then
                t:Destroy(); return
            end
        end
    end
end

local function vec(tbl): Vector3
    return Vector3.new(tbl.x, tbl.y, tbl.z)
end

----------------------------------------------------------------------
-- Income loop (starts ONLY at Stage 10)
----------------------------------------------------------------------
local function startIncome(container: Model, player: Player, incPerMin: number)
    player:SetAttribute("MoneyPerMinute",
        (player:GetAttribute("MoneyPerMinute") or 0) + incPerMin)

    task.spawn(function()
        local carry = 0
        while container.Parent do
            task.wait(3)
            carry += incPerMin / 20
            if carry >= 1 then
                local whole = math.floor(carry); carry -= whole
                local prof  = DataManager.GetProfile(player)
                if not prof then break end
                prof.Data.Cash += whole
                local ls = player:FindFirstChild("leaderstats")
                if ls then ls.Cash.Value = prof.Data.Cash end
                player:SetAttribute("Cash", prof.Data.Cash)
            end
        end
    end)
end

----------------------------------------------------------------------
-- Spawn container
----------------------------------------------------------------------
local function spawnContainer(player: Player, rarity: string, structure: string, stage: number, pos: Vector3)
    local container = Instance.new("Model")
    container.Name, container.Parent = structure, placedFolder
    container:SetAttribute("Owner", player.UserId)

    local modelSrc = ShardDefs[rarity].Structures[structure].Stages[stage][1] or BASE_CRYSTAL
    local model    = modelSrc:Clone(); model.Parent = container

    local cf, sz   = model:GetBoundingBox()
    local rot      = cf - cf.Position
    model:PivotTo(CFrame.new(pos.X, pos.Y + sz.Y*0.5, pos.Z) * rot)

    if stage == ShardDefs.MAX_STAGE then
        startIncome(container, player, ShardDefs[rarity].Structures[structure].BaseIncome)
    end
    return container
end

----------------------------------------------------------------------
-- Growth swap
----------------------------------------------------------------------
local function grow(container: Model, rec, player: Player)
    local rarity, struct = rec.rarity, rec.structure
    local nextStage      = rec.stage + 1
    if nextStage > ShardDefs.MAX_STAGE then return end

    local variants = ShardDefs[rarity].Structures[struct].Stages[nextStage]
    if not variants or #variants == 0 then return end

    local oldCF, oldSz  = container:GetBoundingBox()
    local groundY       = oldCF.Position.Y - oldSz.Y*0.5
    for _,c in ipairs(container:GetChildren()) do c:Destroy() end
    local model = variants[math.random(#variants)]:Clone(); model.Parent = container
    local newCF, newSz  = model:GetBoundingBox()
    model:PivotTo(CFrame.new(oldCF.Position.X, groundY + newSz.Y*0.5, oldCF.Position.Z) * (newCF - newCF.Position))

    rec.stage, rec.lastStageTime = nextStage, os.time()
    if Remotes.ShardGrew then
        Remotes.ShardGrew:FireAllClients(container, rarity, struct, nextStage)
    end

    if nextStage == ShardDefs.MAX_STAGE then
        startIncome(container, player, ShardDefs[rarity].Structures[struct].BaseIncome)
    else
        task.delay(ShardDefs:GetStageDuration(rarity, struct), function()
            if container.Parent then grow(container, rec, player) end
        end)
    end
end

----------------------------------------------------------------------
-- Remote: PlaceShard  (now receives rarity, structure, pos)
----------------------------------------------------------------------
Remotes.PlaceShard.OnServerEvent:Connect(function(player: Player, rarity: string, structure: string, pos: Vector3)
    local profile = DataManager.GetProfile(player); if not profile then return end
    -- remove one inventory entry of that rarity
    for i,r in ipairs(profile.Data.Inventory) do if r==rarity then table.remove(profile.Data.Inventory,i); break end end
    Remotes.InventoryUpdate:FireClient(player, profile.Data.Inventory)
    removeTool(player, rarity, structure)

    local record = {
        id            = HttpService:GenerateGUID(false),
        rarity        = rarity,
        structure     = structure,
        stage         = 1,
        pos           = {x=pos.X, y=pos.Y, z=pos.Z},
        lastStageTime = os.time(),
    }
    table.insert(profile.Data.PlacedShards, record)

    local container = spawnContainer(player, rarity, structure, 1, pos)

    task.delay(ShardDefs:GetStageDuration(rarity, structure), function()
        if container.Parent then grow(container, record, player) end
    end)
end)

----------------------------------------------------------------------
-- Restoration on rejoin
----------------------------------------------------------------------
Players.PlayerAdded:Connect(function(pl)
    repeat task.wait() until DataManager.GetProfile(pl)
    local profile = DataManager.GetProfile(pl)
    pl:SetAttribute("MoneyPerMinute", 0)

    for _,rec in ipairs(profile.Data.PlacedShards) do
        local pos = vec(rec.pos)
        local cont= spawnContainer(pl, rec.rarity, rec.structure, rec.stage, pos)
        if rec.stage < ShardDefs.MAX_STAGE then
            local wait = math.max(ShardDefs:GetStageDuration(rec.rarity, rec.structure)
                        - (os.time()-rec.lastStageTime), 0)
            task.delay(wait,function() if cont.Parent then grow(cont,rec,pl) end end)
        end
    end
end)
