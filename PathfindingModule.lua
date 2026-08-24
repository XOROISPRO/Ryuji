--!strict
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PathfindingModule = {}

-- Constants
local TARGET_CFRAME = CFrame.new(
	665.411133, 101.890839, -898.212219,
	0.712382495, 5.50751338e-08, -0.701791406,
	-8.13938499e-08, 1, -4.14428092e-09,
	0.701791406, 6.00738161e-08, 0.712382495
)

local PATH_PARAMS = {
	AgentRadius = 3.5,
	AgentHeight = 5.5,
	AgentCanJump = true,
	WaypointSpacing = 4,
}

local PHYSICS_CFG = { targetSpeed = 55, groundAccel = 30, friction = 4, stopSpeed = 5 }
local DEFAULT_WALKSPEED = 16

function PathfindingModule.Init(State: any, Toggles: any, TrainModule: any)
	local Module = {}

	local function getChar(): (Model, Humanoid, BasePart)
		local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		local root = char:WaitForChild("HumanoidRootPart") :: BasePart
		return char, hum, root
	end

	local function setKeyState(keyCode: Enum.KeyCode, press: boolean)
		if State.ActiveKeys[keyCode] == press then return end
		State.ActiveKeys[keyCode] = press
		VirtualInputManager:SendKeyEvent(press, keyCode, false, game)
	end

	local function releaseAllKeys()
		for key, isPressed in pairs(State.ActiveKeys) do
			if isPressed then
				VirtualInputManager:SendKeyEvent(false, key, false, game)
				State.ActiveKeys[key] = false
			end
		end
	end

	local function applyFriction(dt: number)
		local speed = State.Velocity.Magnitude
		if speed < 0.1 then
			State.Velocity = Vector3.zero
			return
		end
		local control = math.max(speed, PHYSICS_CFG.stopSpeed)
		local drop = control * PHYSICS_CFG.friction * dt
		local newSpeed = math.max(speed - drop, 0)
		if newSpeed ~= speed then
			State.Velocity = State.Velocity * (newSpeed / speed)
		end
	end

	local function accel(wishDir: Vector3, wishSpeed: number, dt: number)
		local cur = State.Velocity:Dot(wishDir)
		local add = wishSpeed - cur
		if add <= 0 then return end
		local accelSpeed = math.min(PHYSICS_CFG.groundAccel * dt * wishSpeed, add)
		State.Velocity = State.Velocity + (wishDir * accelSpeed)
	end

	function Module.StopPathfinding()
		State.Navigating = false
		releaseAllKeys()
		State.Velocity = Vector3.zero
		local _, hum, root = getChar()
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if hum then
			hum.PlatformStand = false
			hum.WalkSpeed = DEFAULT_WALKSPEED
		end
		for key, conn in pairs(State.Connections) do
			conn:Disconnect()
			State.Connections[key] = nil
		end
		
		if Toggles and Toggles.NavToggle then
			Toggles.NavToggle:SetValue(false)
		end
	end

	function Module.NavigateToCFrame(targetCFrame: CFrame, onArrivalCallback: (() -> ())?)
		Module.StopPathfinding()
		TrainModule.UnequipAllTools()
		State.Navigating = true
		if Toggles and Toggles.NavToggle then Toggles.NavToggle:SetValue(true) end

		local _, humanoid, root = getChar()
		humanoid.PlatformStand = true

		State.CurrentPath = PathfindingService:CreatePath(PATH_PARAMS)
		local waypoints = {}
		local success, err

		for attempt = 1, 3 do
			success, err = pcall(function()
				State.CurrentPath:ComputeAsync(root.Position, targetCFrame.Position)
			end)
			if success and State.CurrentPath.Status == Enum.PathStatus.Success then
				waypoints = State.CurrentPath:GetWaypoints()
				if #waypoints > 0 then break end
			end
			task.wait(0.2)
		end

		if not success or #waypoints == 0 then
			warn("[Pathfinding Engine] Path computation failed. Fallback executed.")
			Module.StopPathfinding()
			if onArrivalCallback then onArrivalCallback() end
			return
		end

		local currentWaypointIndex = 2

		State.Connections["Blocked"] = State.CurrentPath.Blocked:Connect(function(blockedIndex)
			if blockedIndex >= currentWaypointIndex and State.Navigating then
				Module.NavigateToCFrame(targetCFrame, onArrivalCallback)
			end
		end)

		State.Connections["Heartbeat"] = RunService.Heartbeat:Connect(function(dt)
			if not State.Navigating then return end
			TrainModule.EnsureMacroDisabled()

			if currentWaypointIndex > #waypoints then
				releaseAllKeys()
				root.CFrame = CFrame.new(root.Position) * targetCFrame.Rotation
				Module.StopPathfinding()
				task.defer(function()
					TrainModule.TryRemoteBuy()
					if onArrivalCallback then onArrivalCallback() end
				end)
				return
			end

			local currentPos = root.Position
			local targetPos = waypoints[currentWaypointIndex].Position
			local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
			local flatCurrent = Vector3.new(currentPos.X, 0, currentPos.Z)

			if (flatTarget - flatCurrent).Magnitude <= 1.5 then
				currentWaypointIndex += 1
				return
			end

			local moveDirection = (flatTarget - flatCurrent).Unit
			local camCFrame = camera.CFrame
			local camLook = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
			local camRight = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z).Unit

			local forwardDot = moveDirection:Dot(camLook)
			local rightDot = moveDirection:Dot(camRight)

			setKeyState(Enum.KeyCode.W, forwardDot > 0.3)
			setKeyState(Enum.KeyCode.S, forwardDot < -0.3)
			setKeyState(Enum.KeyCode.D, rightDot > 0.3)
			setKeyState(Enum.KeyCode.A, rightDot < -0.3)

			if waypoints[currentWaypointIndex].Action == Enum.PathWaypointAction.Jump or (targetPos.Y - currentPos.Y) > 2 then
				if humanoid.FloorMaterial ~= Enum.Material.Air then
					setKeyState(Enum.KeyCode.Space, true)
					task.delay(0.1, function()
						setKeyState(Enum.KeyCode.Space, false)
					end)
				end
			end

			if moveDirection.Magnitude > 0 then
				root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, root.Position + moveDirection), dt * 10)
			end

			applyFriction(dt)
			accel(moveDirection, PHYSICS_CFG.targetSpeed, dt)
			State.Velocity = Vector3.new(State.Velocity.X, root.AssemblyLinearVelocity.Y, State.Velocity.Z)
			root.AssemblyLinearVelocity = State.Velocity
		end)
	end

	Module.TARGET_CFRAME = TARGET_CFRAME
	return Module
end

return PathfindingModule
