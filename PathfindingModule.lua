--!strict
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local PathfindingModule = {}
PathfindingModule.__index = PathfindingModule

PathfindingModule.TARGET_CFRAME = CFrame.new(866.421997, 101.868713, -921.240356)

local PATH_PARAMS = {
	AgentRadius = 2.0,
	AgentHeight = 5.0,
	AgentCanJump = true,
	WaypointSpacing = 3,
}

local SETTINGS = {
	WalkSpeed = 35,
	WaypointReachDist = 2.5,
	JumpImpulse = 48,
}

local function getChar(): (Model?, Humanoid?, BasePart?)
	local char = localPlayer.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, hum, root
end

-- Raycast scaled correctly to prevent false air checks
local function isGrounded(char: Model, root: BasePart): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -3.0, 0), rayParams)
	return result ~= nil and result.Instance ~= nil and result.Instance.CanCollide
end

-- Wall check forward to trigger smooth jumps over obstacles
local function isFacingObstacle(char: Model, root: BasePart, moveDir: Vector3): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = Workspace:Raycast(root.Position, moveDir * 2.5, rayParams)
	return result ~= nil and result.Instance ~= nil and result.Instance.CanCollide
end

function PathfindingModule.Init(State: any, Toggles: any, TrainModule: any?)
	local self = setmetatable({}, PathfindingModule)
	self.State = State
	self.Toggles = Toggles
	self.TrainModule = TrainModule
	return self
end

function PathfindingModule:StopPathfinding()
	-- Guard against calling as dot-syntax or uninitialized state
	local selfTable = (type(self) == "table" and self.State) and self or PathfindingModule
	
	if selfTable.State then
		selfTable.State.Navigating = false
	end
	
	local _, _, root = getChar()
	if root then 
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
	
	if selfTable.State and selfTable.State.Connections then
		for key, conn in pairs(selfTable.State.Connections) do
			if conn then conn:Disconnect() end
			selfTable.State.Connections[key] = nil
		end
	end
	
	if selfTable.Toggles and selfTable.Toggles.NavToggle then
		selfTable.Toggles.NavToggle:SetValue(false)
	end
end

function PathfindingModule:WalkTo(target: Vector3 | CFrame, onArrivalCallback: (() -> ())?): boolean
	self:StopPathfinding()
	
	if self.TrainModule and self.TrainModule.VerifyMacroDisabled then
		self.TrainModule.VerifyMacroDisabled()
	end

	local targetPos = typeof(target) == "CFrame" and target.Position or target
	local char, humanoid, root = getChar()
	if not char or not humanoid or not root then return false end

	self.State.Navigating = true
	if self.Toggles and self.Toggles.NavToggle then
		self.Toggles.NavToggle:SetValue(true)
	end

	local path = PathfindingService:CreatePath(PATH_PARAMS)
	local ok, _ = pcall(function()
		path:ComputeAsync(root.Position, targetPos)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		self:StopPathfinding()
		return false
	end

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		self:StopPathfinding()
		return false
	end

	local currentWPIndex = 1
	local lastJumpTime = 0

	self.State.Connections["Heartbeat"] = RunService.Heartbeat:Connect(function(dt)
		if not self.State.Navigating or not root or not char then return end

		local currentPos = root.Position
		local targetWP = waypoints[currentWPIndex]

		if not targetWP then
			self:StopPathfinding()
			if typeof(target) == "CFrame" then
				root.CFrame = CFrame.new(root.Position) * target.Rotation
			end
			if onArrivalCallback then onArrivalCallback() end
			return
		end

		local wpPos = targetWP.Position
		local flatDelta = Vector3.new(wpPos.X - currentPos.X, 0, wpPos.Z - currentPos.Z)
		local dist = flatDelta.Magnitude

		-- Advance to next waypoint if reached
		if dist <= SETTINGS.WaypointReachDist then
			currentWPIndex += 1
			return
		end

		local moveDir = flatDelta.Unit
		local currentYVel = root.AssemblyLinearVelocity.Y

		-- Jump condition based on explicit path waypoint OR forward wall collision
		if (targetWP.Action == Enum.PathWaypointAction.Jump or isFacingObstacle(char, root, moveDir)) 
			and isGrounded(char, root) 
			and (tick() - lastJumpTime) > 0.3 then
			
			currentYVel = SETTINGS.JumpImpulse
			lastJumpTime = tick()
		end

		-- Rotate character smooth toward direction of velocity
		root.CFrame = root.CFrame:Lerp(CFrame.lookAt(currentPos, currentPos + moveDir), dt * 15)

		-- Direct physics drive without platformstand conflicts
		root.AssemblyLinearVelocity = Vector3.new(
			moveDir.X * SETTINGS.WalkSpeed,
			currentYVel,
			moveDir.Z * SETTINGS.WalkSpeed
		)
	end)

	-- Yield thread safety guard
	while self.State.Navigating do
		task.wait(0.05)
	end
	
	return true
end

function PathfindingModule:NavigateToCFrame(targetCFrame: CFrame, onArrivalCallback: (() -> ())?)
	task.spawn(function()
		self:WalkTo(targetCFrame, onArrivalCallback)
	end)
end

return PathfindingModule
