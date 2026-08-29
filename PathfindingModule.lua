--!strict
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

export type PhysicsConfig = {
	TargetSpeed: number,
	GroundAccel: number,
	AirAccel: number,
	Friction: number,
	StopSpeed: number,
	WaypointReachDist: number,
	FinalReachDist: number,
}

local PathfindingModule = {}
PathfindingModule.__index = PathfindingModule

local DEFAULT_PHYSICS: PhysicsConfig = {
	TargetSpeed = 35,
	GroundAccel = 25,
	AirAccel = 2,
	Friction = 6,
	StopSpeed = 1.5,
	WaypointReachDist = 1.5,
	FinalReachDist = 2.0,
}

local DEFAULT_PATH_PARAMS = {
	AgentRadius = 2.5,
	AgentHeight = 5,
	AgentCanJump = true,
	WaypointSpacing = 3,
}

-- Private Physics Helpers
local function isGrounded(character: Model, root: BasePart): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
	return result ~= nil and result.Instance ~= nil and result.Instance.CanCollide
end

local function applyFriction(velocity: Vector3, grounded: boolean, config: PhysicsConfig, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.1 then return Vector3.zero end
	
	local drop = 0
	if grounded then
		local control = math.max(speed, config.StopSpeed)
		drop = control * config.Friction * dt
	end
	
	local newSpeed = math.max(speed - drop, 0)
	if newSpeed ~= speed then
		return velocity * (newSpeed / speed)
	end
	return velocity
end

local function applyAccel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, grounded: boolean, config: PhysicsConfig, dt: number): Vector3
	local currentSpeed = velocity:Dot(wishDir)
	local addSpeed = wishSpeed - currentSpeed
	if addSpeed <= 0 then return velocity end
	
	local accelRate = grounded and config.GroundAccel or config.AirAccel
	local accelAmount = math.min(accelRate * dt * wishSpeed, addSpeed)
	return velocity + (wishDir * accelAmount)
end

local function calculateYVelocity(currentY: number, targetY: number): number
	local heightDiff = targetY - currentY
	if heightDiff > 0.5 then
		return math.sqrt(2 * Workspace.Gravity * (heightDiff + 1.5))
	end
	return 0
end

-- Constructor
function PathfindingModule.new(customPhysics: PhysicsConfig?)
	local self = setmetatable({}, PathfindingModule)
	self.PhysicsConfig = customPhysics or DEFAULT_PHYSICS
	self.ActiveConnection = nil :: RBXScriptConnection?
	self.IsNavigating = false
	self.CurrentVelocity = Vector3.zero
	return self
end

-- Core Path Execution (Asynchronous Task)
function PathfindingModule:WalkToAsync(target: Vector3 | CFrame, shouldCancelCallback: (() -> boolean)?): boolean
	self:Stop()
	
	local char = LocalPlayer.Character
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return false end

	local targetPos = typeof(target) == "CFrame" and target.Position or target
	self.IsNavigating = true
	hum.PlatformStand = true

	local waypoints: { PathWaypoint }? = nil
	local attempts = 0

	-- Path Calculation & Dynamic Recovery
	while self.IsNavigating do
		if shouldCancelCallback and shouldCancelCallback() then
			self:Stop()
			return false
		end
		
		attempts += 1
		local path = PathfindingService:CreatePath(DEFAULT_PATH_PARAMS)
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

		-- Apply vertical unstick boost every 3 failed attempts
		if attempts % 3 == 0 then
			root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 45, root.AssemblyLinearVelocity.Z)
		end
		task.wait(0.3)
	end

	if not self.IsNavigating or not waypoints then return false end

	local currentWaypointIndex = 1
	local forceJump = false
	local doneSignal = Instance.new("BindableEvent")

	self.ActiveConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.IsNavigating or not root or not char or (shouldCancelCallback and shouldCancelCallback()) then
			self:Stop()
			doneSignal:Fire(false)
			return
		end

		if currentWaypointIndex > #waypoints then
			self:Stop()
			if typeof(target) == "CFrame" then
				root.CFrame = CFrame.new(root.Position) * target.Rotation
			end
			doneSignal:Fire(true)
			return
		end

		local wp = waypoints[currentWaypointIndex]
		local wpPos = wp.Position
		local isLast = (currentWaypointIndex == #waypoints)
		local reachDist = isLast and self.PhysicsConfig.FinalReachDist or self.PhysicsConfig.WaypointReachDist
		local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)

		if flatDelta.Magnitude < reachDist then
			if wp.Action == Enum.PathWaypointAction.Jump then
				forceJump = true
			end
			currentWaypointIndex += 1
			if currentWaypointIndex > #waypoints then return end
			
			local nextWp = waypoints[currentWaypointIndex]
			wpPos = nextWp.Position
			flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)
		end

		local moveDirection = flatDelta.Magnitude > 0.01 and flatDelta.Unit or Vector3.zero
		local groundedState = isGrounded(char, root)

		self.CurrentVelocity = applyFriction(self.CurrentVelocity, groundedState, self.PhysicsConfig, dt)
		self.CurrentVelocity = applyAccel(self.CurrentVelocity, moveDirection, self.PhysicsConfig.TargetSpeed, groundedState, self.PhysicsConfig, dt)

		-- Dynamic Y-Velocity Execution
		local yVel = root.AssemblyLinearVelocity.Y
		if groundedState then
			if forceJump then
				yVel = 45
				forceJump = false
			else
				local boost = calculateYVelocity(root.Position.Y, wpPos.Y)
				if boost > 0 then yVel = boost end
			end
		end

		if moveDirection.Magnitude > 0 then
			root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, root.Position + moveDirection), dt * 10)
		end

		root.AssemblyLinearVelocity = Vector3.new(self.CurrentVelocity.X, yVel, self.CurrentVelocity.Z)
	end)

	local success = doneSignal.Event:Wait()
	doneSignal:Destroy()
	return success
end

function PathfindingModule:Stop()
	self.IsNavigating = false
	self.CurrentVelocity = Vector3.zero
	
	if self.ActiveConnection then
		self.ActiveConnection:Disconnect()
		self.ActiveConnection = nil
	end

	local char = LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if root then root.AssemblyLinearVelocity = Vector3.zero end
		if hum then hum.PlatformStand = false end
	end
end

return PathfindingModule
