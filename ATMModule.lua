--!strict
local ATMModule = {}
ATMModule.__index = ATMModule

local Players = game:GetService("Players")

local firesignal = firesignal or function(signal)
	if getconnections then
		for _, connection in ipairs(getconnections(signal)) do
			if connection.Fire then
				connection:Fire()
			elseif connection.Function then
				connection.Function()
			end
		end
	end
end

-- Uses Roblox's native button:Activate()
local function triggerGuiActivation(button: Instance)
	if not button or not button:IsA("GuiButton") then return end
	
	-- Standard Roblox method
	pcall(function()
		(button :: GuiButton):Activate()
	end)

	-- Direct Activated signal backup for custom UI listeners
	if firesignal and button.Activated then
		firesignal(button.Activated)
	end
end

function ATMModule.Init(State: any, Toggles: any, PathfindingModule: any)
	local self = setmetatable({}, ATMModule)
	self.State = State
	self.Toggles = Toggles
	self.PathfindingModule = PathfindingModule
	self.Player = Players.LocalPlayer

	self.ATM_STAND_CFRAME = CFrame.new(866.421997, 101.868713, -921.240356, 0.00871905126, -4.68019046e-09, 0.999961972, 1.93347383e-08, 1, 4.51178117e-09, -0.999961972, 1.92946654e-08, 0.00871905126)
	self.TARGET_ATM_PIVOT = CFrame.new(862.994568, 101.668419, -921.223633, -1, 0, -0, 0, 0, -1, 0, -1, -0)

	self.DEBUG = true
	self.Running = false
	self.TaskThread = nil :: thread?

	return self
end

function ATMModule:DPrint(...)
	if self.DEBUG then print("[ATM Service]", ...) end
end

function ATMModule:FindTargetATM(): ClickDetector?
	local interactables = workspace:FindFirstChild("Interactables")
	local atmsFolder = interactables and interactables:FindFirstChild("ATMs")
	if not atmsFolder then return nil end

	local targetPos = self.TARGET_ATM_PIVOT.Position
	local bestATM: Instance? = nil
	local bestDist = math.huge

	for _, atm in ipairs(atmsFolder:GetChildren()) do
		local pivot = atm:GetPivot()
		local dist = (pivot.Position - targetPos).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestATM = atm
		end
	end

	if bestATM and bestDist < 2 then
		local hitbox = bestATM:FindFirstChild("Hitbox")
		local cd = hitbox and hitbox:FindFirstChildWhichIsA("ClickDetector")
		if cd then return cd end
	end
	return nil
end

function ATMModule:ExecuteATMTransaction()
	self:DPrint("Executing ATM UI actions...")
	local playerGui = self.Player:WaitForChild("PlayerGui")
	local atmTab = playerGui:WaitForChild("HUD"):WaitForChild("Tabs"):WaitForChild("ATM")

	-- 1. Deposit 1,000,000
	task.wait(2)
	local amountBox = atmTab:WaitForChild("AmountBox") :: TextBox
	amountBox.Text = "1000000"
	task.wait(2)
	triggerGuiActivation(atmTab:WaitForChild("Deposit"))

	-- 2. Switch to Transfer Tab
	task.wait(2)
	triggerGuiActivation(atmTab:WaitForChild("Transfer"))

	-- 3. Fill Details & Confirm
	task.wait(2)
	local transferFrame = atmTab:WaitForChild("TransferFrame")
	local transferAmountBox = transferFrame:WaitForChild("AmountBox") :: TextBox
	local usernameBox = transferFrame:WaitForChild("Username") :: TextBox
	transferAmountBox.Text = "1000000"
	usernameBox.Text = "jotla13"
	
	task.wait(2)
	triggerGuiActivation(transferFrame:WaitForChild("Confirm"))
	self:DPrint("ATM Transfer Complete.")
end

function ATMModule:Start(onComplete: (() -> ())?)
	if self.Running then return end
	
	if not self.PathfindingModule or type(self.PathfindingModule.WalkTo) ~= "function" then
		warn("[ATM Service] Cannot start: PathfindingModule is nil or invalid!")
		return
	end

	self.Running = true

	self.TaskThread = task.spawn(function()
		self:DPrint("Starting ATM Sequence...")
		
		local arrived = self.PathfindingModule:WalkTo(self.ATM_STAND_CFRAME)
		if not arrived or not self.Running then return end

		local clickDetector = self:FindTargetATM()
		if clickDetector and fireclickdetector then
			fireclickdetector(clickDetector)
			task.wait(2)
			if self.Running then self:ExecuteATMTransaction() end
		end

		self.Running = false
		self.TaskThread = nil
		
		if onComplete then onComplete() end
	end)
end

function ATMModule:Stop()
	self.Running = false
	
	if self.PathfindingModule and type(self.PathfindingModule.StopPathfinding) == "function" then
		self.PathfindingModule:StopPathfinding()
	end
	
	if self.TaskThread and coroutine.running() ~= self.TaskThread then
		task.cancel(self.TaskThread)
		self.TaskThread = nil
	end
end

return ATMModule
