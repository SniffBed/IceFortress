--!strict
-- DataManager.lua  ▸ loads / saves profiles and hands out shard Tools

----------------------------------------------------------------------
-- Services / modules
----------------------------------------------------------------------
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")

local serverFolder = ServerScriptService:WaitForChild("Server")
local ProfileStore = require(serverFolder:WaitForChild("ProfileStore"))
local ShardDefs    = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShardDefinitions"))

----------------------------------------------------------------------
-- Profile schema
----------------------------------------------------------------------
export type ProfileData = {
    Cash: number,
    Inventory: { string },
    PlacedShards: { [number]: any },
}
local PROFILE_TEMPLATE: ProfileData = {
    Cash         = 1000,
    Inventory    = {},
    PlacedShards = {},
}

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
local Profiles: { [Player]: any } = {}

----------------------------------------------------------------------
-- Shared assets
----------------------------------------------------------------------
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local clientScript = sharedFolder:WaitForChild("ShardToolClient") :: LocalScript
local baseCrystal  = ServerStorage:WaitForChild("FrostCrystal")   :: Model

----------------------------------------------------------------------
-- prettify "IcePillar" -> "Ice Pillar"
----------------------------------------------------------------------
local function prettify(str: string): string
    return (str:gsub("(%l)(%u)", "%1 %2"))
end

----------------------------------------------------------------------
-- First structure of a rarity (fallback when none passed)
----------------------------------------------------------------------
local function firstStructure(rarity: string): string
    for k in pairs(ShardDefs[rarity].Structures) do
        return k
    end
    return "Unknown"
end

----------------------------------------------------------------------
-- GiveShardTool
----------------------------------------------------------------------
local function GiveShardTool(player: Player, rarity: string, structureName: string?)
    structureName = structureName or firstStructure(rarity)
    local displayName = prettify(structureName) .. " Shard"

    ------------------------------ Tool shell
    local tool = Instance.new("Tool")
    tool.Name           = displayName
    tool.ToolTip        = displayName
    tool.RequiresHandle = true
    tool.CanBeDropped   = false
    tool.GripPos        = Vector3.new(0,0,0.5)
    tool:SetAttribute("Rarity",    rarity)
    tool:SetAttribute("Structure", structureName)

    ------------------------------ Handle
    local handle = baseCrystal:Clone()
    handle.Name       = "Handle"
    handle.Color      = ShardDefs[rarity].Structures[structureName].Color
                        or ShardDefs[rarity].Color
    handle.Anchored   = false
    handle.CanCollide = false
    handle.Massless   = true
    handle.Parent     = tool

    ------------------------------ LocalScript
    clientScript:Clone().Parent = tool

    ------------------------------ Equip
    tool.Parent = player.Backpack
    tool:Clone().Parent = player.StarterGear
end

----------------------------------------------------------------------
-- Public accessor
----------------------------------------------------------------------
local function GetProfile(plr: Player)  return Profiles[plr] end

----------------------------------------------------------------------
-- Player join / leave (unchanged)
----------------------------------------------------------------------
local function onPlayerAdded(plr: Player)
    local profile = PlayerStore:StartSessionAsync(tostring(plr.UserId), { Cancel=function() return plr.Parent~=Players end })
    if not profile then plr:Kick("Data load failure") return end
    profile:AddUserId(plr.UserId) ; profile:Reconcile() ; Profiles[plr] = profile

    local stats = Instance.new("Folder", plr); stats.Name = "leaderstats"
    local cash  = Instance.new("IntValue", stats); cash.Name, cash.Value = "Cash", profile.Data.Cash
    plr:SetAttribute("Cash", profile.Data.Cash); plr:SetAttribute("MoneyPerMinute",0)

    for _,rarity in ipairs(profile.Data.Inventory) do
        GiveShardTool(plr, rarity)
    end
end

local rawStore = DataStoreService:GetDataStore("PlayerStore")
local function onPlayerRemoving(plr: Player)
    local profile = Profiles[plr]
    if plr:GetAttribute("WipeProfile") then pcall(function() rawStore:RemoveAsync(tostring(plr.UserId)) end) end
    if profile then
        local cashVal = plr:FindFirstChild("leaderstats") and plr.leaderstats:FindFirstChild("Cash")
        if cashVal then profile.Data.Cash = cashVal.Value end
        profile:EndSession(); Profiles[plr] = nil
    end
end

for _,p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded,p) end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

return {
    GetProfile    = GetProfile,
    GiveShardTool = GiveShardTool,
}
