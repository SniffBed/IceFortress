--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local placeRemote = Remotes:WaitForChild("PlaceCrystal") :: RemoteEvent

-- Listen for left-click input (mouse or tap)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end  -- ignore if typing in chat or UI
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        -- Get mouse screen position and cast a ray into the 3D world
        local mousePos = UserInputService:GetMouseLocation()
        local viewportRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        local rayParams = RaycastParams.new()
        local player = Players.LocalPlayer
        if player.Character then
            rayParams.FilterDescendantsInstances = {player.Character}
            rayParams.FilterType = Enum.RaycastFilterType.Exclude  -- ignore player's character
        end
        local result = workspace:Raycast(viewportRay.Origin, viewportRay.Direction * 1000, rayParams)
        if result and result.Instance then
            -- Only place on the base terrain/part (e.g. Baseplate)
            if result.Instance.Name == "Baseplate" then
                placeRemote:FireServer(result.Position)  -- send placement request to server
            end
        end
    end
end)
