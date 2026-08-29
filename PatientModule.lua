--!strict
local PatientModule = {}
PatientModule.__index = PatientModule

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

-- Ensure compatibility with environments supporting fireproximityprompt
local fireproximityprompt = fireproximityprompt or fire_proximity_prompt

function PatientModule.Init(State, Toggles)
	local self = setmetatable({}, PatientModule)
	self.State = State
	self.Toggles = Toggles
	self.Player = Players.LocalPlayer
	self.PatientFolder = workspace:WaitForChild("Ignore"):WaitForChild("NPCs"):WaitForChild("Miscs")

	-- Zone & Target Coordinates
	self.MIN_Y_HEIGHT = 140
	self.LOWER_ROOM_B_CFRAME = CFrame.new(1183.53284, 115.798248, -510.988892, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.LOWER_ROOM_C_CFRAME = CFrame.new(1183.53284, 115.798248, -402.588745, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.LOWER_ROOM_D_CFRAME = CFrame.new(1183.53284, 115.798248, -457.288818, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.ROOM_SIZE = Vector3.new(43, 30, 43)

	-- Execution Parameters
	self.MAX_INTERACT_RETRIES = 5
	self.CONFIRM_TIME = 0.5
	self.POLL_TIME = 0.2
	self.MAX_SPEED = 35
	self.ACCEL = 25
	self.AIR_ACCEL = 2
	self.FRICTION = 6
	self.STOP_SPEED = 1.5
	self.WAYPOINT_REACH_DIST = 1.5
	self.FINAL_REACH_DIST = 2
	self.DEBUG = true

	-- Internal Threading & Connections
	self.Running = false
	self.MoveConnection = nil :: RBXScriptConnection?
	self.CharConnection = nil :: RBXScriptConnection?
	self.InputConnection = nil :: RBXScriptConnection?
	self.TaskThread = nil :: thread?
	self.AntiAFKThread = nil :: thread?

	self.MoveState = {
		velocity = Vector3.new(),
		waypoints = nil,
		waypointIndex = 1,
		done = true,
	}

	return self
end

function PatientModule:DPrint(...)
	if self.DEBUG then
		print("[Patient Service]", ...)
	end
end

-- Helper Physics Utilities
local function grounded(character: Model, root: BasePart): (boolean, Vector3?)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
	if result and result.Instance and result.Instance.CanCollide then
		return true, result.Position
	end
	return false, nil
end

local function applyFriction(velocity: Vector3, isGrounded: boolean, friction: number, stopSpeed: number, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.1 then return Vector3.new() end

	local drop = 0
	if isGrounded then
		local control = math.max(speed, stopSpeed)
		drop = control * friction * dt
	end

	local newSpeed = math.max(speed - drop, 0)
	if newSpeed ~= speed then
		return velocity * (newSpeed / speed)
	end
	return velocity
end

local function accel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, accelRate: number, dt: number): Vector3
	local cur = velocity:Dot(wishDir)
	local add = wishSpeed - cur
	if add <= 0 then return velocity end

	local accelSpeed = math.min(accelRate * dt * wishSpeed, add)
	return velocity + wishDir * accelSpeed
end

-- Spatial & Instance Utilities
function PatientModule:GetPrompt(patient: Instance): ProximityPrompt?
	return patient:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function PatientModule:IsInRoom(pos: Vector3, roomCFrame: CFrame): boolean
	local roomCenter = roomCFrame.Position
	local halfSize = self.ROOM_SIZE / 2
	return math.abs(pos.X - roomCenter.X) <= halfSize.X
		and math.abs(pos.Y - roomCenter.Y) <= halfSize.Y
		and math.abs(pos.Z - roomCenter.Z) <= halfSize.Z
end

function PatientModule:NearestTop(fromPos: Vector3): Model?
	local best: Model? = nil
	local bestDist = math.huge

	for _, child in ipairs(self.PatientFolder:GetChildren()) do
		if child:IsA("Model") and child.Name == "Patient" then
			local pos = child:GetPivot().Position
			if pos.Y > self.MIN_Y_HEIGHT and self:GetPrompt(child) then
				local dist = (pos - fromPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = child
				end
			end
		end
	end
	return best
end

function PatientModule:NearestInRoom(fromPos: Vector3, roomCFrame: CFrame): Model?
	local best: Model? = nil
	local bestDist = math.huge

	for _, child in ipairs(self.PatientFolder:GetChildren()) do
		if child:IsA("Model") and child.Name == "Patient" then
			local pos = child:GetPivot().Position
			if self:IsInRoom(pos, roomCFrame) and self:GetPrompt(child) then
				local dist = (pos - fromPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = child
				end
			end
		end
	end
	return best
end

-- Custom Physics Movement Mechanics
function PatientModule:GetWishDirFromPath(root: BasePart, humanoid: Humanoid): (Vector3, number)
	local state = self.MoveState
	if not state.waypoints or state.waypointIndex > #state.waypoints then
		return Vector3.new(), 0
	end

	local wp = state.waypoints[state.waypointIndex]
	local wpPos = typeof(wp) == "Vector3" and wp or (wp :: PathWaypoint).Position
	local isLast = state.waypointIndex == #state.waypoints
	local reachDist = isLast and self.FINAL_REACH_DIST or self.WAYPOINT_REACH_DIST

	local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)

	if flatDelta.Magnitude < reachDist then
		if typeof(wp) ~= "Vector3" and (wp :: PathWaypoint).Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		state.waypointIndex += 1
		if state.waypointIndex > #state.waypoints then
			state.velocity = Vector3.new()
			state.done = true
			return Vector3.new(), 0
		end

		local nextWp = state.waypoints[state.waypointIndex]
		local nextPos = typeof(nextWp) == "Vector3" and nextWp or (nextWp :: PathWaypoint).Position
		flatDelta = Vector3.new(nextPos.X - root.Position.X, 0, nextPos.Z - root.Position.Z)
	end

	if flatDelta.Magnitude < 0.01 then
		return Vector3.new(), 0
	end

	return flatDelta.Unit, self.MAX_SPEED
end

function PatientModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number)
	local isGrounded = grounded(character, root)
	local accelRate = isGrounded and self.ACCEL or self.AIR_ACCEL

	self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
	self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, wishSpeed, accelRate, dt)

	root.AssemblyLinearVelocity = Vector3.new(
		self.MoveState.velocity.X,
		root.AssemblyLinearVelocity.Y,
		self.MoveState.velocity.Z
	)
end

function PatientModule:WalkTo(targetPos: Vector3, isRetry: boolean?, hrp: BasePart, hum: Humanoid)
	self:DPrint("walkTo called, target =", tostring(targetPos), "isRetry =", tostring(isRetry))

	local wps = nil
	local pathAttempts = 0

	-- Keep trying until a valid path is successfully computed (No straight-line fallback)
	while self.Running do
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
		})

		local ok, err = pcall(function()
			path:ComputeAsync(hrp.Position, targetPos)
		end)

		if ok and path.Status == Enum.PathStatus.Success then
			wps = path:GetWaypoints()
			self:DPrint(("path computed, %d waypoints"):format(#wps))
			break
		else
			pathAttempts += 1
			self:DPrint(("path FAILED (attempt %d, status=%s), retrying pathfinding..."):format(
				pathAttempts,
				path and tostring(path.Status) or "nil"
			))

			-- Nudge character with a jump if pathfinding keeps failing
			if pathAttempts % 3 == 0 then
				self:DPrint("Path blocked repeatedly; forcing a jump nudge.")
				hum.Jump = true
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
				task.wait(0.1)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
			end

			task.wait(0.5)
		end
	end

	if not self.Running or not wps then return end

	self.MoveState.waypoints = wps
	self.MoveState.waypointIndex = 1
	self.MoveState.done = false

	local holdingW = not isRetry
	if holdingW then
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
	end

	local waited = 0
	while not self.MoveState.done and self.Running do
		task.wait()
		waited += 1

		if waited >= 600 and holdingW then
			self:DPrint("Reached over 600 frames in motion; releasing W key to prevent collision.")
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			holdingW = false
		end

		if waited % 300 == 0 then
			self:DPrint("Still walking Space Initiated.")
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
			task.wait(0.1)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
			if holdingW and waited < 600 and not self.MoveState.done and self.Running then
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
			end
		end
	end

	if holdingW then
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
	end

	self:DPrint("walkTo finished")
end

-- Interactions & Room Sequences
function PatientModule:InteractWithPatient(patient: Model, hrp: BasePart, hum: Humanoid)
	local retries = 0

	while self.Running do
		local prompt = self:GetPrompt(patient)
		if not prompt then break end

		retries += 1
		self:DPrint(("Interacting with patient (Attempt %d): %s"):format(retries, patient:GetFullName()))

		-- Direct interaction call replacing key inputs
		fireproximityprompt(prompt)

		local elapsed = 0
		local cleared = false
		while elapsed < self.CONFIRM_TIME do
			task.wait(self.POLL_TIME)
			elapsed += self.POLL_TIME
			if not self:GetPrompt(patient) then
				cleared = true
				break
			end
		end

		if cleared then
			self:DPrint("Patient interaction successful and verified.")
			return
		end

		self:DPrint("Interaction unconfirmed. Initiating retry sequence...")
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
		task.wait(0.1)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		task.wait(0.5)

		if retries >= self.MAX_INTERACT_RETRIES then
			self:DPrint("Max retry attempts reached for patient:", patient:GetFullName())
			break
		end

		self:WalkTo(patient:GetPivot().Position, true, hrp, hum)
	end
end

function PatientModule:ProcessLowerRoom(roomName: string, roomCFrame: CFrame, hrp: BasePart, hum: Humanoid)
	self:DPrint(("Moving to %s CFrame..."):format(roomName))
	self:WalkTo(roomCFrame.Position, false, hrp, hum)

	while self.Running do
		local roomPatient = self:NearestInRoom(hrp.Position, roomCFrame)
		if not roomPatient then
			self:DPrint(("%s completely cleared."):format(roomName))
			break
		end

		self:DPrint(("Found patient in %s: %s"):format(roomName, roomPatient:GetFullName()))
		self:WalkTo(roomPatient:GetPivot().Position, false, hrp, hum)
		if self.Running and self:GetPrompt(roomPatient) then
			self:InteractWithPatient(roomPatient, hrp, hum)
		end
		task.wait(0.1)
	end
end

-- Module Execution & Lifecycle Methods
function PatientModule:Start()
	if self.Running then return end
	self.Running = true

	if self.State then
		self.State.PatientActive = true
	end

	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	-- Movement Loop Connection
	self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
		if self.MoveState.done or not self.Running then return end
		local wishDir, wishSpeed = self:GetWishDirFromPath(hrp, hum)
		self:StepMovement(hrp, char, wishDir, wishSpeed, dt)
	end)

	-- Manual Abort Keybind Connection (Ctrl + E)
	self.InputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.E and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			self:DPrint("Loop manually stopped via Ctrl+E.")
			self:Stop()
		end
	end)

	self.CharConnection = char.Destroying:Connect(function()
		self:Stop()
	end)

	-- Background Anti-AFK Loop (Every 60s)
	self.AntiAFKThread = task.spawn(function()
		self:DPrint("Anti-AFK Loop Started.")
		while self.Running do
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
			task.wait(0.2)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			task.wait(60)
		end
	end)

	-- Main Processing Thread
	self.TaskThread = task.spawn(function()
		self:DPrint("Starting Patient Handler Service...")

		while self.Running do
			-- 1. Clear all patients in Top area
			self:DPrint("Checking Top area for patients...")
			local foundTop = false
			while self.Running do
				local topPatient = self:NearestTop(hrp.Position)
				if not topPatient then break end

				foundTop = true
				self:DPrint("Found top patient:", topPatient:GetFullName())
				self:WalkTo(topPatient:GetPivot().Position, false, hrp, hum)

				if self.Running and self:GetPrompt(topPatient) then
					self:InteractWithPatient(topPatient, hrp, hum)
				end
				task.wait(0.1)
			end

			if not foundTop then
				self:DPrint("No top patients remaining.")
			end

			-- 2. Process Bottom B
			if self.Running then
				self:DPrint("Moving to Bottom B...")
				self:ProcessLowerRoom("Bottom B", self.LOWER_ROOM_B_CFRAME, hrp, hum)
			end

			-- 3. Process Bottom C
			if self.Running then
				self:DPrint("Moving to Bottom C...")
				self:ProcessLowerRoom("Bottom C", self.LOWER_ROOM_C_CFRAME, hrp, hum)
			end

			-- 4. Process Bottom D
			if self.Running then
				self:DPrint("Moving to Bottom D...")
				self:ProcessLowerRoom("Bottom D", self.LOWER_ROOM_D_CFRAME, hrp, hum)
			end

			task.wait(0.5)
		end

		self:DPrint("Patient servicing loop completed.")
	end)
end

function PatientModule:Stop()
	self.Running = false
	self.MoveState.done = true

	if self.State then
		self.State.PatientActive = false
	end

	VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)

	if self.MoveConnection then
		self.MoveConnection:Disconnect()
		self.MoveConnection = nil
	end
	if self.CharConnection then
		self.CharConnection:Disconnect()
		self.CharConnection = nil
	end
	if self.InputConnection then
		self.InputConnection:Disconnect()
		self.InputConnection = nil
	end
	if self.TaskThread then
		task.cancel(self.TaskThread)
		self.TaskThread = nil
	end
	if self.AntiAFKThread then
		task.cancel(self.AntiAFKThread)
		self.AntiAFKThread = nil
	end
end

return PatientModule
