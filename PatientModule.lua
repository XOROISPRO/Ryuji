--!strict
local PatientModule = {}
PatientModule.__index = PatientModule

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Require your PathfindingModule here (adjust path if needed, e.g., script.Parent.PathfindingModule)
local PathfindingModule = require(script.Parent:WaitForChild("PathfindingModule"))

local fireproximityprompt = fireproximityprompt or fire_proximity_prompt

function PatientModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, PatientModule)
	self.State = State
	self.Toggles = Toggles
	
	-- Automatically initialize the engine inside PatientModule!
	self.PathEngine = PathfindingModule.Init(State, Toggles)

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
