--!strict
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local PathfindingModule = {}

-- Engine Configuration Parameters
local PATH_PARAMS = {
	AgentRadius = 2.5,
	AgentHeight = 5,
	AgentCanJump = true,
	WaypointSpacing = 3,
}

local PHYSICS_CFG = {
	targetSpeed = 35,
	groundAccel = 25,
	airAccel = 2,
	friction = 6,
	stopSpeed = 1.5,
	waypointReachDist = 1.5,
	finalReachDist = 2.0,
}

function PathfindingModule.Init(State: any, Toggles: any)
	local Module = {}

	local function getChar(): (Model?, Humanoid?, BasePart?)
		local char = localPlayer.Character
		if not char then return nil, nil, nil end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		return char, hum, root
	end

	local function grounded(character: Model, root: BasePart): boolean
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = Workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
		return result ~= nil and result.Instance ~= nil and result.Instance.CanCollide
	end

	local function applyFriction(velocity: Vector3, isGrounded: boolean, dt: number): Vector3
		local speed = velocity.Magnitude
		if speed < 0.1 then return Vector3.zero end

		local drop = 0
		if isGrounded then
			local control = math.max(speed, PHYSICS_CFG.stopSpeed)
			drop = control * PHYSICS_CFG.friction * dt
		end

		local newSpeed = math.max(speed - drop, 0)
		if newSpeed ~= speed then
			return velocity * (newSpeed / speed)
		end
		return velocity
	end

	local function accel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, isGrounded: boolean, dt: number): Vector3
		local cur = velocity:Dot(wishDir)
		local add = wishSpeed - cur
		if add <= 0 then return velocity end

		local accelRate = isGrounded and PHYSICS_CFG.groundAccel or PHYSICS_CFG.airAccel
		local accelSpeed = math.min(accelRate * dt * wishSpeed, add)
		return velocity + (wishDir * accelSpeed)
	end

	local function calculateYVelocity(currentY: number, targetY: number): number
		local heightDiff = targetY - currentY
		if heightDiff > 0.5 then
			return math.sqrt(2 * Workspace.Gravity * (heightDiff + 1.5))
		end
		return 0
	end

	function Module.StopPathfinding()
		State.Navigating = false
		State.Velocity = Vector3.zero

		local _, hum, root = getChar()
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if hum then
			hum.PlatformStand = false
		end

		if State.Connections then
			for key, conn in pairs(State.Connections) do
				conn:Disconnect()
				State.Connections[key] = nil
			end
		end

		if Toggles and Toggles.NavToggle then
			Toggles.NavToggle:SetValue(false)
		end
	end

	-- Universal WalkTo method: Accepts Vector3 or CFrame positions
	function Module.WalkTo(target: Vector3 | CFrame, onArrivalCallback: (() -> ())?): boolean
		Module.StopPathfinding()

		local targetPos = typeof(target) == "CFrame" and target.Position or target
		local char, humanoid, root = getChar()

		if not char or not humanoid or not root then
			return false
		end

		State.Navigating = true
		if Toggles and Toggles.NavToggle then
			Toggles.NavToggle:SetValue(true)
		end

		humanoid.PlatformStand = true

		local waypoints = nil
		local attempts = 0

		-- Persistent Pathfinding Computation (No straight-line fallbacks)
		while State.Navigating do
			attempts += 1
			local path = PathfindingService:CreatePath(PATH_PARAMS)

			local ok, _ = pcall(function()
				path:ComputeAsync(root.Position, targetPos)
			end)

			if ok and path.Status == Enum.PathStatus.Success then
				local wps = path:GetWaypoints()
				if #wps > 0 then
					waypoints = wps
					break
				end
			end

			-- Unstick jump pop every 3 failed pathing attempts
			if attempts % 3 == 0 and root then
				root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 45, root.AssemblyLinearVelocity.Z)
			end

			task.wait(0.3)
		end

		if not State.Navigating or not waypoints then
			return false
		end

		local currentWaypointIndex = 1
		local forceJump = false
		local targetY: number? = nil

		State.Connections["Heartbeat"] = RunService.Heartbeat:Connect(function(dt)
			if not State.Navigating or not root or not char then return end

			if currentWaypointIndex > #waypoints then
				Module.StopPathfinding()
				if typeof(target) == "CFrame" then
					root.CFrame = CFrame.new(root.Position) * target.Rotation
				end
				if onArrivalCallback then
					onArrivalCallback()
				end
				return
			end

			local wp = waypoints[currentWaypointIndex]
			local wpPos = wp.Position
			targetY = wpPos.Y

			local isLast = currentWaypointIndex == #waypoints
			local reachDist = isLast and PHYSICS_CFG.finalReachDist or PHYSICS_CFG.waypointReachDist

			local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)

			if flatDelta.Magnitude < reachDist then
				if wp.Action == Enum.PathWaypointAction.Jump then
					forceJump = true
				end

				currentWaypointIndex += 1
				if currentWaypointIndex > #waypoints then return end

				local nextWp = waypoints[currentWaypointIndex]
				targetY = nextWp.Position.Y
				flatDelta = Vector3.new(nextWp.Position.X - root.Position.X, 0, nextWp.Position.Z - root.Position.Z)
			end

			local moveDirection = flatDelta.Magnitude > 0.01 and flatDelta.Unit or Vector3.zero
			local isGrounded = grounded(char, root)

			State.Velocity = applyFriction(State.Velocity, isGrounded, dt)
			State.Velocity = accel(State.Velocity, moveDirection, PHYSICS_CFG.targetSpeed, isGrounded, dt)

			-- Dynamic Y Velocity Calculation
			local yVel = root.AssemblyLinearVelocity.Y
			if isGrounded then
				if forceJump then
					yVel = 45
					forceJump = false
				elseif targetY then
					local dynamicBoost = calculateYVelocity(root.Position.Y, targetY)
					if dynamicBoost > 0 then
						yVel = dynamicBoost
					end
				end
			end

			if moveDirection.Magnitude > 0 then
				root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, root.Position + moveDirection), dt * 10)
			end

			root.AssemblyLinearVelocity = Vector3.new(State.Velocity.X, yVel, State.Velocity.Z)
		end)

		-- Block thread until arrival or cancellation
		while State.Navigating do
			task.wait()
		end

		return true
	end

	return Module
end

return PathfindingModule
