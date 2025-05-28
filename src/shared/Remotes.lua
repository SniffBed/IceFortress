-- src/shared/Remotes.lua
-- Shared Remote definitions for client↔︎server communication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ensure a RemoteEvents folder exists
local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    or Instance.new("Folder", ReplicatedStorage)
folder.Name = "RemoteEvents"

local function getEvent(name)
    local ev = folder:FindFirstChild(name)
    if not ev then
        ev = Instance.new("RemoteEvent")
        ev.Name = name
        ev.Parent = folder
    end
    return ev
end

local function getFunction(name)
    local fn = folder:FindFirstChild(name)
    if not fn then
        fn = Instance.new("RemoteFunction")
        fn.Name = name
        fn.Parent = folder
    end
    return fn
end

-- Define the exact remotes your game uses:
local InventoryUpdate = getEvent("InventoryUpdate")
local PlaceShard      = getEvent("PlaceShard")
local GetProfileData  = getFunction("GetProfileData")

-- Server handler for initial data requests
if RunService:IsServer() then
    GetProfileData.OnServerInvoke = function(player)
        -- your existing ProfileStore-based retrieval here
    end
end

return {
    InventoryUpdate = InventoryUpdate,
    PlaceShard      = PlaceShard,
    GetProfileData  = GetProfileData,
}