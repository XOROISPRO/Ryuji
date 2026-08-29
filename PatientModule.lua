--!strict
local PatientModule = {}
PatientModule.__index = PatientModule

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local fireproximityprompt = fireproximityprompt or fire_proximity_prompt

function PatientModule.Init(State, Toggles, PathfindingEngine)
	local self = setmetatable({}, PatientModule)
	self.State = State
	self.Toggles = Toggles
	self.PathEngine = PathfindingEngine
	self.Player = Players.LocalPlayer
	self.PatientFolder = workspace:WaitForChild("Ignore"):WaitForChild("NPCs"):WaitForChild("Miscs")

	-- Room Positions & Parameters
	self.MIN_Y_HEIGHT = 140
	self.LOWER_ROOM_B_CFRAME = CFrame.new(1183.53284, 115.798248, -510.988892, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.LOWER_ROOM_C_CFRAME = CFrame.new(1183.53284, 115.798248, -402.588745, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.LOWER_ROOM_D_CFRAME = CFrame.new(1183.53284, 115.798248, -457.288818, 0, 1, 0, 1, 0, 0, 0, 0, -1)
	self.ROOM_SIZE = Vector3.new(43, 30, 43)

	self.MAX_INTERACT_RETRIES = 5
	self.CONFIRM_TIME = 0.5
	self.POLL_TIME = 0.2
	self.DEBUG = true

	self.Running = false
	self.TaskThread = nil :: thread?
	self.InputConnection = nil :: RBXScriptConnection?

	return self
end

function PatientModule:DPrint(...)
	if self.DEBUG then print("[Patient Service]", ...) end
end

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

function PatientModule:InteractWithPatient(patient: Model, hrp: BasePart)
	local retries = 0
	while self.Running do
		local prompt = self:GetPrompt(patient)
		if not prompt then break end

		retries += 1
		self:DPrint(("Interacting with patient (Attempt %d): %s"):format(retries, patient:GetFullName()))
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
			self:DPrint("Patient interaction verified.")
			return
		end

		if retries >= self.MAX_INTERACT_RETRIES then
			self:DPrint("Max retry attempts reached for patient:", patient:GetFullName())
			break
		end

		-- Re-navigate to patient position via Universal Engine
		self.PathEngine.WalkTo(patient:GetPivot().Position)
	end
end

function PatientModule:ProcessLowerRoom(roomName: string, roomCFrame: CFrame, hrp: BasePart)
	self:DPrint(("Moving to %s..."):format(roomName))
	self.PathEngine.WalkTo(roomCFrame.Position)

	while self.Running do
		local roomPatient = self:NearestInRoom(hrp.Position, roomCFrame)
		if not roomPatient then
			self:DPrint(("%s completely cleared."):format(roomName))
			break
		end

		self:DPrint(("Found patient in %s: %s"):format(roomName, roomPatient:GetFullName()))
		self.PathEngine.WalkTo(roomPatient:GetPivot().Position)
		if self.Running and self:GetPrompt(roomPatient) then
			self:InteractWithPatient(roomPatient, hrp)
		end
		task.wait(0.1)
	end
end

function PatientModule:Start()
	if self.Running then return end
	self.Running = true

	local char = self.Player.Character or self.Player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	self.InputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.E and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			self:DPrint("Stopped via Ctrl+E.")
			self:Stop()
		end
	end)

	self.TaskThread = task.spawn(function()
		self:DPrint("Starting Patient Handler Service...")

		while self.Running do
			-- 1. Top Patients
			while self.Running do
				local topPatient = self:NearestTop(hrp.Position)
				if not topPatient then break end

				self:DPrint("Found top patient:", topPatient:GetFullName())
				self.PathEngine.WalkTo(topPatient:GetPivot().Position)

				if self.Running and self:GetPrompt(topPatient) then
					self:InteractWithPatient(topPatient, hrp)
				end
				task.wait(0.1)
			end

			-- 2. Bottom Rooms (B -> C -> D)
			if self.Running then self:ProcessLowerRoom("Bottom B", self.LOWER_ROOM_B_CFRAME, hrp) end
			if self.Running then self:ProcessLowerRoom("Bottom C", self.LOWER_ROOM_C_CFRAME, hrp) end
			if self.Running then self:ProcessLowerRoom("Bottom D", self.LOWER_ROOM_D_CFRAME, hrp) end

			task.wait(0.5)
		end
	end)
end

function PatientModule:Stop()
	self.Running = false
	self.PathEngine.StopPathfinding()

	if self.InputConnection then
		self.InputConnection:Disconnect()
		self.InputConnection = nil
	end
	if self.TaskThread then
		task.cancel(self.TaskThread)
		self.TaskThread = nil
	end
end

return PatientModule
