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
        print(string.format("[PickStageModel] Using BASE_CRYSTAL for %s/%s stage %d", rarity, structure, stage))
        return BASE_CRYSTAL
    end
    local selected = list[math.random(#list)]:Clone()
    print(string.format("[PickStageModel] Selected model '%s' for %s/%s stage %d",
        selected.Name or "unnamed", rarity, structure, stage))
    
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
            
            if isCylinder then
                print(string.format("  - CYLINDER '%s': Position(%.2f, %.2f, %.2f), Size(%.2f height, %.2f diam, %.2f diam)",
                    part.Name, part.Position.X, part.Position.Y, part.Position.Z,
                    part.Size.X, part.Size.Y, part.Size.Z))
            else
                print(string.format("  - Part '%s': Position(%.2f, %.2f, %.2f), Size(%.2f, %.2f, %.2f), Type: %s",
                    part.Name, part.Position.X, part.Position.Y, part.Position.Z,
                    part.Size.X, part.Size.Y, part.Size.Z, part.ClassName))
            end
        end
    end
    print(string.format("  Total parts in model: %d", partCount))
    
    return selected
end

local function removeTool(plr: Player, rarity: string, structure: string)
    for _,bag in ipairs({plr.Backpack, plr.Character}) do
        for _,tool in ipairs(bag:GetChildren()) do
            if tool:IsA("Tool")
                and tool:GetAttribute("Rarity")==rarity
                and tool:GetAttribute("Structure")==structure then
                tool:Destroy()
                print(string.format("[RemoveTool] Removed %s/%s tool from %s", rarity, structure, plr.Name))
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
    
    print("[GetActualBounds] Calculating bounds for model...")
    
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
                -- For cylinders: Size.X is height (Y-axis), Size.Y/Z are diameter
                print(string.format("  CYLINDER '%s': Pos(%.2f, %.2f, %.2f), Size(%.2f, %.2f, %.2f)",
                    part.Name, pos.X, pos.Y, pos.Z, size.X, size.Y, size.Z))
                print("    -> Swapping axes: X=height, Y/Z=diameter")
                
                -- Swap the axes for cylinders
                partMinX = pos.X - size.Z/2  -- Z becomes X width
                partMinY = pos.Y - size.X/2  -- X becomes Y height
                partMinZ = pos.Z - size.Y/2  -- Y becomes Z depth
                partMaxX = pos.X + size.Z/2
                partMaxY = pos.Y + size.X/2
                partMaxZ = pos.Z + size.Y/2
                
                print(string.format("    -> Actual bounds: Y from %.2f to %.2f (bottom: %.2f)",
                    partMinY, partMaxY, partMinY))
            else
                -- Normal parts
                partMinX = pos.X - size.X/2
                partMinY = pos.Y - size.Y/2
                partMinZ = pos.Z - size.Z/2
                partMaxX = pos.X + size.X/2
                partMaxY = pos.Y + size.Y/2
                partMaxZ = pos.Z + size.Z/2
                
                print(string.format("  Part '%s': Pos(%.2f, %.2f, %.2f), Size(%.2f, %.2f, %.2f), Bottom Y: %.2f",
                    part.Name, pos.X, pos.Y, pos.Z, size.X, size.Y, size.Z, partMinY))
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
    
    print(string.format("  Calculated bounds - Center: (%.2f, %.2f, %.2f), Size: (%.2f, %.2f, %.2f)",
        center.X, center.Y, center.Z, size.X, size.Y, size.Z))
    print(string.format("  Actual bottom Y: %.2f (from %d parts)", minY, partCount))
    
    -- Compare with GetBoundingBox for debugging
    local bbCF, bbSize = model:GetBoundingBox()
    print(string.format("  GetBoundingBox - Center: (%.2f, %.2f, %.2f), Size: (%.2f, %.2f, %.2f)",
        bbCF.Position.X, bbCF.Position.Y, bbCF.Position.Z, bbSize.X, bbSize.Y, bbSize.Z))
    print(string.format("  GetBoundingBox bottom Y: %.2f", bbCF.Position.Y - bbSize.Y/2))
    print(string.format("  Difference in Y: %.2f", (bbCF.Position.Y - bbSize.Y/2) - minY))
    
    return center, size, minY  -- Return center, size, and actual bottom Y
end

-- income loop (starts at Stage 10)
local function startIncome(container: Model, plr: Player, incPerMin: number)
    plr:SetAttribute("MoneyPerMinute",
        (plr:GetAttribute("MoneyPerMinute") or 0) + incPerMin)
    
    print(string.format("[StartIncome] Starting income for %s: %d/min", plr.Name, incPerMin))
    
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
        print(string.format("[Income] Stopped for %s", plr.Name))
    end)
end

-- spawn container
local function spawnContainer(plr, rarity, struct, stage, pos)
    print(string.format("\n[SpawnContainer] === SPAWNING %s/%s STAGE %d ===", rarity, struct, stage))
    print(string.format("  Target position: (%.2f, %.2f, %.2f)", pos.X, pos.Y, pos.Z))
    
    local cont = Instance.new("Model")
    cont.Name, cont.Parent = struct, placedFolder
    cont:SetAttribute("Owner", plr.UserId)
    
    local model = pickStageModel(rarity, struct, stage)
    model.Parent = cont
    
    -- Get actual bounds instead of using GetBoundingBox
    local center, size, actualBottomY = getActualBounds(model)
    
    -- Calculate offset to place bottom at target position
    local offsetY = pos.Y - actualBottomY
    
    print(string.format("  Positioning calculations:"))
    print(string.format("    - Target ground Y: %.2f", pos.Y))
    print(string.format("    - Model bottom Y: %.2f", actualBottomY))
    print(string.format("    - Offset Y needed: %.2f", offsetY))
    
    -- Move the model to the correct position
    print("  Moving parts...")
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local oldPos = part.Position
            part.Position = part.Position + Vector3.new(pos.X - center.X, offsetY, pos.Z - center.Z)
            print(string.format("    - '%s': (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)",
                part.Name, oldPos.X, oldPos.Y, oldPos.Z, part.Position.X, part.Position.Y, part.Position.Z))
        end
    end
    
    -- Verify final position
    local finalCenter, finalSize, finalBottomY = getActualBounds(model)
    print(string.format("  Final verification:"))
    print(string.format("    - Final center: (%.2f, %.2f, %.2f)", finalCenter.X, finalCenter.Y, finalCenter.Z))
    print(string.format("    - Final bottom Y: %.2f", finalBottomY))
    print(string.format("    - Bottom Y error: %.2f", math.abs(finalBottomY - pos.Y)))
    
    if stage == ShardDefs.MAX_STAGE then
        startIncome(cont, plr, ShardDefs[rarity].Structures[struct].BaseIncome)
    end
    
    print(string.format("[SpawnContainer] === COMPLETE ===\n"))
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
    
    print(string.format("  Current state:"))
    print(string.format("    - Center: (%.2f, %.2f, %.2f)", oldCenter.X, oldCenter.Y, oldCenter.Z))
    print(string.format("    - Size: (%.2f, %.2f, %.2f)", oldSize.X, oldSize.Y, oldSize.Z))
    print(string.format("    - Ground Y to maintain: %.2f", groundY))
    
    -- Clear old model
    print("  Clearing old model...")
    for _, c in ipairs(cont:GetChildren()) do
        print(string.format("    - Destroying: %s", c.Name))
        c:Destroy()
    end
    
    -- Add new model
    local variant = pickStageModel(rarity, struct, nextStage)
    variant.Parent = cont
    
    -- Get actual bounds of new model
    local newCenter, newSize, newBottomY = getActualBounds(variant)
    
    -- Calculate offset to maintain ground level
    local offsetY = groundY - newBottomY
    
    print(string.format("  Growth calculations:"))
    print(string.format("    - New model bottom Y: %.2f", newBottomY))
    print(string.format("    - Ground Y to maintain: %.2f", groundY))
    print(string.format("    - Offset Y needed: %.2f", offsetY))
    
    -- Move all parts to maintain ground position
    print("  Repositioning parts...")
    for _, part in ipairs(variant:GetDescendants()) do
        if part:IsA("BasePart") then
            local oldPos = part.Position
            part.Position = part.Position + Vector3.new(oldCenter.X - newCenter.X, offsetY, oldCenter.Z - newCenter.Z)
            print(string.format("    - '%s': (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)",
                part.Name, oldPos.X, oldPos.Y, oldPos.Z, part.Position.X, part.Position.Y, part.Position.Z))
        end
    end
    
    -- Verify final position
    local finalCenter, finalSize, finalBottomY = getActualBounds(variant)
    print(string.format("  Final verification:"))
    print(string.format("    - Final center: (%.2f, %.2f, %.2f)", finalCenter.X, finalCenter.Y, finalCenter.Z))
    print(string.format("    - Final bottom Y: %.2f", finalBottomY))
    print(string.format("    - Ground Y maintained: %s (error: %.2f)",
        math.abs(finalBottomY - groundY) < 0.01 and "YES" or "NO", math.abs(finalBottomY - groundY)))
    
    -- Update timing
    local dur = ShardDefs:GetStageDuration(rarity, struct)
    local baseT = rec.nextGrowthTime or os.time()
    rec.stage = nextStage
    rec.nextGrowthTime = (nextStage == ShardDefs.MAX_STAGE) and nil or (baseT + dur)
    
    print(string.format("  Timing update:"))
    print(string.format("    - Stage duration: %d seconds", dur))
    print(string.format("    - Next growth time: %s", tostring(rec.nextGrowthTime)))
    print(string.format("[Growth] %s → Stage %d | nextGrowthTime=%s",
        rec.id, nextStage, tostring(rec.nextGrowthTime)))
    
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
    print(string.format("\n[PlaceShard] === PLACE REQUEST ==="))
    print(string.format("  Player: %s", plr.Name))
    print(string.format("  Rarity: %s, Structure: %s", rarity, struct))
    print(string.format("  Hit position: (%.2f, %.2f, %.2f)", hitPos.X, hitPos.Y, hitPos.Z))
    
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
    
    -- remove inventory entry
    local removed = false
    for i, r in ipairs(profile.Data.Inventory) do
        if r == rarity then
            table.remove(profile.Data.Inventory, i)
            removed = true
            print(string.format("  Removed from inventory at index %d", i))
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
    print(string.format("\n[PlayerAdded] %s joined", plr.Name))
    
    repeat task.wait() until DataManager.GetProfile(plr)
    local profile = DataManager.GetProfile(plr)
    plr:SetAttribute("MoneyPerMinute", 0)
    
    print(string.format("  Restoring %d placed shards", #profile.Data.PlacedShards))
    
    for i, rec in ipairs(profile.Data.PlacedShards) do
        print(string.format("  [%d] Restoring %s: %s/%s stage %d at (%.2f, %.2f, %.2f)",
            i, rec.id, rec.rarity, rec.structure, rec.stage, rec.pos.x, rec.pos.y, rec.pos.z))
        
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