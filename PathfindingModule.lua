local PathModule = {}

function PathModule.Init(State, Toggles)
    local Players = game:GetService("Players")
    local PathfindingService = game:GetService("PathfindingService")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    local TARGET_CFRAME = CFrame.new(665.411133, 101.890839, -898.212219)
    local PATH_PARAMS = { AgentRadius = 3.5, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 4 }
    local PHYSICS_CFG = { targetSpeed = 55, groundAccel = 30, friction = 4, stopSpeed = 5 }

    local function getChar()
        local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
        return char, char:WaitForChild("Humanoid"), char:WaitForChild("HumanoidRootPart")
    end

    function PathModule.StopPathfinding()
        State.Navigating = false
        State.Velocity = Vector3.zero
        local _, hum, root = getChar()
        if root then root.AssemblyLinearVelocity = Vector3.zero end
        if hum then hum.PlatformStand = false hum.WalkSpeed = 16 end

        for key, conn in pairs(State.Connections) do
            conn:Disconnect()
            State.Connections[key] = nil
        end
        if Toggles and Toggles.NavToggle then Toggles.NavToggle:SetValue(false) end
    end

    function PathModule.NavigateToVendor(onArrivalCallback)
        PathModule.StopPathfinding()
        State.Navigating = true
        if Toggles and Toggles.NavToggle then Toggles.NavToggle:SetValue(true) end

        local _, humanoid, root = getChar()
        humanoid.PlatformStand = true
        State.CurrentPath = PathfindingService:CreatePath(PATH_PARAMS)
        State.CurrentPath:ComputeAsync(root.Position, TARGET_CFRAME.Position)
        
        local waypoints = State.CurrentPath:GetWaypoints()
        local currentWaypointIndex = 2

        State.Connections["Heartbeat"] = RunService.Heartbeat:Connect(function(dt)
            if not State.Navigating then return end
            if currentWaypointIndex > #waypoints then
                root.CFrame = CFrame.new(root.Position) * TARGET_CFRAME.Rotation
                PathModule.StopPathfinding()
                if onArrivalCallback then onArrivalCallback() end
                return
            end

            local targetPos = waypoints[currentWaypointIndex].Position
            local moveDirection = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Unit

            if (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude <= 1.5 then
                currentWaypointIndex += 1
            end

            root.AssemblyLinearVelocity = moveDirection * PHYSICS_CFG.targetSpeed
        end)
    end

    return PathModule
end

return PathModule
