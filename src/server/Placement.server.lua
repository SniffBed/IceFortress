--!strict
-- Placement.server.lua – preserves per-shard offsets across rejoins
-- Fixed to handle overlapping cylinders and other complex models correctly
-- 
-- IMPORTANT: Roblox cylinders have rotated axes!
-- For cylinders: Size.X = height (Y-axis), Size.Y/Z = diameter
-- This is different from normal parts where Size.Y = height
-- We detect cylinders by checking if part.Shape == Enum.PartType.Cylinder or if they have a CylinderMesh

-- services / modules
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local Remotes     = require(Shared:WaitForChild("Remotes"))
local ShardDefs   = require(Shared:WaitForChild("ShardDefinitions"))
local DataManager = require(game:GetService("ServerScriptService")
    :WaitForChild("Server"):WaitForChild("DataManager"))

-- references
local BASE_CRYSTAL = ServerStorage:WaitForChild("FrostCrystal") :: Model
local placedFolder = Workspace:FindFirstChild("PlacedShards") or Instance.new("Folder", Workspace)
placedFolder.Name  = "PlacedShards"
-- reference to the game’s baseplate (for placement checks)
local baseplate = Workspace:FindFirstChild("Baseplate")

-- utility functions

local function firstStructure(rarity: string): string
    for k in pairs(ShardDefs[rarity].Structures) do return k end
    return "Unknown"
end

local function pickStageModel(rarity: string, structure: string, stage: number): Model
    local sDef = ShardDefs[rarity].Structures[structure]
        or ShardDefs[rarity].Structures[firstStructure(rarity)]
    local list = sDef and sDef.Stages[stage]
    if not list or #list == 0 then
        return BASE_CRYSTAL
    end
    local selected = list[math.random(#list)]:Clone()

    -- Log model structure
    local partCount = 0
    for _, part in ipairs(selected:GetDescendants()) do
        if part:IsA("BasePart") then
            partCount = partCount + 1
            
            -- Check if this is a cylinder
            local isCylinder = false
            if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
                isCylinder = true
            elseif part:FindFirstChildOfClass("CylinderMesh") then
                isCylinder = true
            elseif part.Name:lower():find("cylinder") then
                -- Fallback: check if the part name contains "cylinder"
                isCylinder = true
            end
        end
    end
    return selected
end

local function removeTool(plr: Player, rarity: string, structure: string)
    for _,bag in ipairs({plr.Backpack, plr.Character}) do
        for _,tool in ipairs(bag:GetChildren()) do
            if tool:IsA("Tool")
                and tool:GetAttribute("Rarity")==rarity
                and tool:GetAttribute("Structure")==structure then
                tool:Destroy()
                return
            end
        end
    end
end

-- Utility function to get actual bounds of a model
local function getActualBounds(model: Model)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local partCount = 0   
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            partCount = partCount + 1
            local pos = part.Position
            local size = part.Size
            
            -- Check if this is a cylinder (CylinderMesh or Shape property)
            local isCylinder = false
            if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
                isCylinder = true
            elseif part:FindFirstChildOfClass("CylinderMesh") then
                isCylinder = true
            elseif part.Name:lower():find("cylinder") then
                -- Fallback: check if the part name contains "cylinder"
                isCylinder = true
                print("    -> Detected as cylinder based on name")
            end
            
            local partMinX, partMinY, partMinZ
            local partMaxX, partMaxY, partMaxZ
            
            if isCylinder then
                -- Swap the axes for cylinders
                partMinX = pos.X - size.Z/2  -- Z becomes X width
                partMinY = pos.Y - size.X/2  -- X becomes Y height
                partMinZ = pos.Z - size.Y/2  -- Y becomes Z depth
                partMaxX = pos.X + size.Z/2
                partMaxY = pos.Y + size.X/2
                partMaxZ = pos.Z + size.Y/2

            else
                -- Normal parts
                partMinX = pos.X - size.X/2
                partMinY = pos.Y - size.Y/2
                partMinZ = pos.Z - size.Z/2
                partMaxX = pos.X + size.X/2
                partMaxY = pos.Y + size.Y/2
                partMaxZ = pos.Z + size.Z/2
            end
            
            -- Update overall bounds
            minX = math.min(minX, partMinX)
            minY = math.min(minY, partMinY)
            minZ = math.min(minZ, partMinZ)
            maxX = math.max(maxX, partMaxX)
            maxY = math.max(maxY, partMaxY)
            maxZ = math.max(maxZ, partMaxZ)
        end
    end
    
    local center = Vector3.new((minX + maxX)/2, (minY + maxY)/2, (minZ + maxZ)/2)
    local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)

    return center, size, minY  -- Return center, size, and actual bottom Y
end

--------------------------------------------------------------------
-- canPlace → true if the shard’s final-stage footprint is clear   --
--------------------------------------------------------------------
local function canPlace(plr: Player, rarity: string, struct: string, pos: Vector3): boolean    -- clone the final-stage model (largest footprint)
    local probe = pickStageModel(rarity, struct, 10):Clone()
    probe.Parent = Workspace

    -- move probe so its actual bottom sits on pos
    local center, size, bottomY = getActualBounds(probe)
    local offsetY = pos.Y - bottomY
    for _, p in ipairs(probe:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Position += Vector3.new(pos.X - center.X, offsetY, pos.Z - center.Z)
            p.CanQuery = false -- exclude from overlap test
        end
    end

    -- invisible part matching probe’s bounding box
    local region = Instance.new("Part")
    region.Size = size
    region.CFrame = CFrame.new(Vector3.new(pos.X, pos.Y + size.Y/2, pos.Z))
    region.Anchored, region.Transparency, region.CanCollide = true, 1, false
    region.Parent = Workspace

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {probe, region, baseplate}

    local collisions = Workspace:GetPartsInPart(region, params)
    local blocked = false
    for _, part in ipairs(collisions) do
        -- ignore parts belonging to the placing player’s own character
        if not (plr.Character and part:IsDescendantOf(plr.Character)) then
            blocked = true
            break
        end
    end
    
    region:Destroy()
    probe:Destroy()
    return not blocked
end

-- income loop (starts at Stage 10)
local function startIncome(container: Model, plr: Player, incPerMin: number)
    plr:SetAttribute("MoneyPerMinute",
        (plr:GetAttribute("MoneyPerMinute") or 0) + incPerMin)
    task.spawn(function()
        local carry = 0
        while container.Parent do
            task.wait(3)
            carry += incPerMin / 20
            if carry >= 1 then
                local whole = math.floor(carry)
                carry -= whole
                local prof = DataManager.GetProfile(plr)
                if not prof then break end
                prof.Data.Cash += whole
                if plr:FindFirstChild("leaderstats") then
                    plr.leaderstats.Cash.Value = prof.Data.Cash
                end
                plr:SetAttribute("Cash", prof.Data.Cash)
            end
        end
    end)
end

-- spawn container
local function spawnContainer(plr, rarity, struct, stage, pos)
    local cont = Instance.new("Model")
    cont.Name, cont.Parent = struct, placedFolder
    cont:SetAttribute("Owner", plr.UserId)
    
    local model = pickStageModel(rarity, struct, stage)
    model.Parent = cont
    
    -- Get actual bounds instead of using GetBoundingBox
    local center, size, actualBottomY = getActualBounds(model)
    
    -- Calculate offset to place bottom at target position
    local offsetY = pos.Y - actualBottomY
    
    -- Move the model to the correct position
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local oldPos = part.Position
            part.Position = part.Position + Vector3.new(pos.X - center.X, offsetY, pos.Z - center.Z)
        end
    end

    if stage == ShardDefs.MAX_STAGE then
        startIncome(cont, plr, ShardDefs[rarity].Structures[struct].BaseIncome)
    end
    return cont
end

-- grow (keeps original cadence)
local function grow(cont, rec, plr)
    local rarity, struct = rec.rarity, rec.structure
    local nextStage = rec.stage + 1
    if nextStage > ShardDefs.MAX_STAGE then return end
    
    print(string.format("\n[Grow] === GROWING %s/%s FROM STAGE %d TO %d ===", rarity, struct, rec.stage, nextStage))
    
    -- Get old position before destroying
    local oldCenter, oldSize, oldBottomY = getActualBounds(cont)
    local groundY = oldBottomY  -- The ground level to maintain
    
    -- Clear old model
    for _, c in ipairs(cont:GetChildren()) do
        c:Destroy()
    end
    
    -- Add new model
    local variant = pickStageModel(rarity, struct, nextStage)
    variant.Parent = cont
    
    -- Get actual bounds of new model
    local newCenter, newSize, newBottomY = getActualBounds(variant)
    
    -- Calculate offset to maintain ground level
    local offsetY = groundY - newBottomY
    
    -- Move all parts to maintain ground position
    for _, part in ipairs(variant:GetDescendants()) do
        if part:IsA("BasePart") then
            local oldPos = part.Position
            part.Position = part.Position + Vector3.new(oldCenter.X - newCenter.X, offsetY, oldCenter.Z - newCenter.Z)
        end
    end

    -- Update timing
    local dur = ShardDefs:GetStageDuration(rarity, struct)
    local baseT = rec.nextGrowthTime or os.time()
    rec.stage = nextStage
    rec.nextGrowthTime = (nextStage == ShardDefs.MAX_STAGE) and nil or (baseT + dur)
    
    if Remotes.ShardGrew then
        Remotes.ShardGrew:FireAllClients(cont, rarity, struct, nextStage)
        print("  Fired ShardGrew remote to all clients")
    end
    
    if nextStage == ShardDefs.MAX_STAGE then
        startIncome(cont, plr, ShardDefs[rarity].Structures[struct].BaseIncome)
    else
        local wait = rec.nextGrowthTime - os.time()
        print(string.format("  Scheduling next growth in %.2f seconds", wait))
        task.delay(wait, function() if cont.Parent then grow(cont, rec, plr) end end)
    end
    
    print(string.format("[Grow] === COMPLETE ===\n"))
end

-- place shard
Remotes.PlaceShard.OnServerEvent:Connect(function(plr, rarity: string, struct: string, hitPos: Vector3)  
    local profile = DataManager.GetProfile(plr)
    if not profile then
        print("  ERROR: No profile found")
        return
    end
    
    if not ShardDefs[rarity] then
        print("  ERROR: Invalid rarity")
        return
    end
    
    if not ShardDefs[rarity].Structures[struct] then
        struct = firstStructure(rarity)
        print(string.format("  Structure not found, using default: %s", struct))
    end

    ----------------------------------------------------------------
    -- placement validation (baseplate only & no overlap)          --
    ----------------------------------------------------------------
    if not baseplate then
        warn("Baseplate not found – cannot validate placement")
        return
    end
    local baseTop = baseplate.Position.Y + baseplate.Size.Y/2
    if math.abs(hitPos.Y - baseTop) > 0.1 then
        local msg = "Must place on baseplate top surface"
        print("  ERROR: "..msg)
        Remotes.PlacementError:FireClient(plr, msg)   -- NEW
        return
    end
    if not canPlace(plr, rarity, struct, hitPos) then
        local msg = "Space occupied – placement rejected"
        print("  ERROR: "..msg)
        Remotes.PlacementError:FireClient(plr, msg)   -- NEW
        return
    end

    -- remove inventory entry
    local removed = false
    for i, r in ipairs(profile.Data.Inventory) do
        if r == rarity then
            table.remove(profile.Data.Inventory, i)
            removed = true
            break
        end
    end
    
    if not removed then
        print("  WARNING: Item not found in inventory")
    end
    
    Remotes.InventoryUpdate:FireClient(plr, profile.Data.Inventory)
    removeTool(plr, rarity, struct)
    
    local dur = ShardDefs:GetStageDuration(rarity, struct)
    local rec = {
        id             = HttpService:GenerateGUID(false),
        rarity         = rarity,
        structure      = struct,
        stage          = 1,
        pos            = {x=hitPos.X, y=hitPos.Y, z=hitPos.Z},
        nextGrowthTime = os.time() + dur,
    }
    
    table.insert(profile.Data.PlacedShards, rec)
    print(string.format("  Created record: ID=%s, Duration=%d seconds", rec.id, dur))
    print(string.format("[Growth] %s placed | nextGrowthTime=%s", rec.id, rec.nextGrowthTime))
    
    local cont = spawnContainer(plr, rarity, struct, 1, hitPos)
    
    print(string.format("  Scheduling first growth in %d seconds", dur))
    task.delay(dur, function()
        if cont.Parent then
            print(string.format("  Growth timer triggered for %s", rec.id))
            grow(cont, rec, plr)
        else
            print(string.format("  Growth timer: Container destroyed for %s", rec.id))
        end
    end)
    
    print(string.format("[PlaceShard] === COMPLETE ===\n"))
end)

-- restore on re-join
Players.PlayerAdded:Connect(function(plr)
    repeat task.wait() until DataManager.GetProfile(plr)
    local profile = DataManager.GetProfile(plr)
    plr:SetAttribute("MoneyPerMinute", 0)
    
    print(string.format("  Restoring %d placed shards", #profile.Data.PlacedShards))
    
    for i, rec in ipairs(profile.Data.PlacedShards) do
        local pos = Vector3.new(rec.pos.x, rec.pos.y, rec.pos.z)
        local cont = spawnContainer(plr, rec.rarity, rec.structure, rec.stage, pos)
        
        if rec.nextGrowthTime then
            local wait = rec.nextGrowthTime - os.time()
            print(string.format("    Next growth in %.2f seconds", wait))
            
            if wait <= 0 then
                print("    Missed growth(s) while offline - growing immediately")
                grow(cont, rec, plr)
            else
                print(string.format("[Growth] restoring %s | wait %.2fs (next=%s)",
                    rec.id, wait, rec.nextGrowthTime))
                task.delay(wait, function()
                    if cont.Parent then
                        print(string.format("    Restoration growth timer triggered for %s", rec.id))
                        grow(cont, rec, plr)
                    end
                end)
            end
        else
            print("    Already at max stage")
        end
    end
    
    print(string.format("[PlayerAdded] Restoration complete for %s\n", plr.Name))
end)