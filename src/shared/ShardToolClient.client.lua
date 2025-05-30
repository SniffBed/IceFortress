--!strict
-- ShardToolClient – lives INSIDE every shard Tool.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local camera   = workspace.CurrentCamera
local Remotes           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player   = Players.LocalPlayer
local tool     = script.Parent
local rarity   = tool:GetAttribute("Rarity")     -- cached
local structure= tool:GetAttribute("Structure")  -- cached

--------------------------------------------------------------------
local function requestPlace(hitPos: Vector3)
    if rarity and structure then
        -- Send BOTH rarity and structure so server spawns the right model
        Remotes.PlaceShard:FireServer(rarity, structure, hitPos)
    end
end

local rayParams = RaycastParams.new()
rayParams.FilterDescendantsInstances = { player.Character }
rayParams.FilterType = Enum.RaycastFilterType.Blacklist

--------------------------------------------------------------------
tool.Equipped:Connect(function(mouse)
    ----------------------------------------------------------------
    -- Desktop / mouse click  ➜  skip when touch is enabled
    ----------------------------------------------------------------
    if not UserInputService.TouchEnabled then
        mouse.Button1Down:Connect(function()
            local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 1000, rayParams)
            if ray then requestPlace(ray.Position) end
        end)
    end

    ----------------------------------------------------------------
    -- Mobile / multi-touch: place ONLY on a quick, stationary tap
    ----------------------------------------------------------------
    if UserInputService.TouchEnabled then
        local startPos: {[InputObject]: Vector2} = {}
        local beganConn, endedConn

        beganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType == Enum.UserInputType.Touch then
                startPos[input] = input.Position
            end
        end)

        endedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType ~= Enum.UserInputType.Touch then return end

            local start = startPos[input]
            startPos[input] = nil
            if not start then return end

            if (input.Position - start).Magnitude > 15 then return end

            local screenRay = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
            local ray = workspace:Raycast(screenRay.Origin, screenRay.Direction * 1000, rayParams)
            if ray then requestPlace(ray.Position) end
        end)

        tool.Unequipped:Connect(function()
            if beganConn then beganConn:Disconnect() end
            if endedConn then endedConn:Disconnect() end
        end)
    end
end)
