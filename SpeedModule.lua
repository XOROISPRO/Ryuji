--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local gui = localPlayer:WaitForChild("PlayerGui")

local SpeedModule = {}

function SpeedModule.Init(State: any?, Library: any?, Toggles: any?, useUILibrary: boolean?)
	local Module = {}
	
	-- MAINLOADER VARIABLE CHECK
	-- If useUILibrary is explicitly provided as a boolean, use it.
	-- Otherwise, check if Library is available.
	local activeUI = if useUILibrary ~= nil then useUILibrary else (Library ~= nil)

	-- State Variables
	local scriptEnabled = true
	local velocity = Vector3.zero
	local moveDir = Vector3.zero
	local speedMode = "normal" -- normal | fast | super | dynamic | standby
	local lastSpeedMode = "normal"
	local baseWalkSpeed = 16

	local cfg = {
		groundAccel = 50,
		runSpeed = 23,
		fastSpeed = 60,
		superFastSpeed = 105,
		dynamicMultiplier = 1.2,
		friction = 4,
		stopSpeed = 5,
		minSpeedThreshold = 11,
		minSpeedOverride = 18,
	}

	local MODE_COLORS = {
		OFF = Color3.fromRGB(150, 150, 150),
		NORMAL = Color3.fromRGB(255, 255, 255),
		FAST = Color3.fromRGB(255, 220, 0),
		SUPER = Color3.fromRGB(255, 60, 60),
		DYNAMIC = Color3.fromRGB(100, 200, 255),
		STANDBY = Color3.fromRGB(200, 150, 255),
		TRIGGERED = Color3.fromRGB(160, 30, 255)
	}

	local connections = {} :: { [string]: RBXScriptConnection }
	local screenGui: ScreenGui? = nil
	local toggleButton: TextButton? = nil

	local function getChar(): (Model, Humanoid, BasePart)
		local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		local root = char:WaitForChild("HumanoidRootPart") :: BasePart
		return char, hum, root
	end

	local function getCurrentTargetSpeed(): (number, boolean)
		if speedMode == "fast" then 
			return cfg.fastSpeed, false 
		elseif speedMode == "super" then 
			return cfg.superFastSpeed, false 
		elseif speedMode == "dynamic" then 
			return baseWalkSpeed * cfg.dynamicMultiplier, false 
		elseif speedMode == "standby" then 
			if baseWalkSpeed < cfg.minSpeedThreshold then 
				return cfg.minSpeedOverride, true 
			end 
			return baseWalkSpeed, false 
		end 
		return cfg.runSpeed, false 
	end

	local function updateUI()
		local currentSpeed, isTriggered = getCurrentTargetSpeed()
		local modeUpper = speedMode:upper()

		if activeUI and Toggles then
			if Toggles.SpeedToggle then
				Toggles.SpeedToggle:SetValue(scriptEnabled)
			end
		elseif toggleButton then
			if not scriptEnabled then
				toggleButton.BackgroundColor3 = MODE_COLORS.OFF
				toggleButton.Text = "MODE: OFF\nSpeed: 16"
				return
			end

			local activeColor = MODE_COLORS[modeUpper] or MODE_COLORS.NORMAL
			if speedMode == "standby" then
				if isTriggered then
					activeColor = MODE_COLORS.TRIGGERED
					toggleButton.Text = string.format("MODE: STANDBY [ACTIVE]\nSpeed: %.1f", currentSpeed)
				else
					activeColor = MODE_COLORS.STANDBY
					toggleButton.Text = string.format("MODE: STANDBY\nSpeed: %.1f", currentSpeed)
				end
			else
				toggleButton.Text = string.format("MODE: %s\nSpeed: %.1f", modeUpper, currentSpeed)
			end
			toggleButton.BackgroundColor3 = activeColor
		end
	end

	local function buildStandaloneGui()
		local existing = gui:FindFirstChild("SourceDBG")
		if existing then existing:Destroy() end

		local g = Instance.new("ScreenGui", gui)
		g.ResetOnSpawn = false
		g.Name = "SourceDBG"

		local toggle = Instance.new("TextButton", g)
		toggle.Size = UDim2.new(0, 110, 0, 36)
		toggle.Position = UDim2.new(0, 12, 1, -48)
		toggle.TextColor3 = Color3.fromRGB(25, 25, 25)
		toggle.Font = Enum.Font.SourceSansBold
		toggle.TextSize = 12
		toggle.BorderSizePixel = 0
		toggleButton = toggle

		local corner = Instance.new("UICorner", toggle)
		corner.CornerRadius = UDim.new(0, 8)

		local padding = Instance.new("UIPadding", toggle)
		padding.PaddingTop = UDim.new(0, 2)
		padding.PaddingBottom = UDim.new(0, 2)

		toggle.MouseButton1Click:Connect(function()
			local _, hum, _ = getChar()
			scriptEnabled = not scriptEnabled
			if not scriptEnabled and hum then
				hum.WalkSpeed = baseWalkSpeed
				velocity = Vector3.zero
			end
			updateUI()
		end)

		screenGui = g
		updateUI()
	end

	local function applyFriction(dt: number)
		local speed = velocity.Magnitude
		if speed < 0.1 then
			velocity = Vector3.zero
			return
		end
		local control = math.max(speed, cfg.stopSpeed)
		local drop = control * cfg.friction * dt
		local newSpeed = math.max(speed - drop, 0)
		if newSpeed ~= speed then
			velocity = velocity * (newSpeed / speed)
		end
	end

	local function accel(wishDir: Vector3, wishSpeed: number, accelRate: number, dt: number)
		local cur = velocity:Dot(wishDir)
		local add = wishSpeed - cur
		if add <= 0 then return end
		local accelSpeed = math.min(accelRate * dt * wishSpeed, add)
		velocity = velocity + wishDir * accelSpeed
	end

	local function process(dt: number)
		if not scriptEnabled then return end
		local _, humanoid, root = getChar()
		if not humanoid or not root or humanoid.Health <= 0 then return end

		if humanoid.WalkSpeed > 0 then 
			baseWalkSpeed = humanoid.WalkSpeed 
		end

		if speedMode == "standby" and baseWalkSpeed >= cfg.minSpeedThreshold then 
			humanoid.WalkSpeed = baseWalkSpeed 
			velocity = Vector3.zero 
			updateUI() 
			return 
		end 

		humanoid.WalkSpeed = 0 
		local cam = Workspace.CurrentCamera 
		local fwd = cam.CFrame.LookVector 
		local right = cam.CFrame.RightVector 
		fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit 
		right = Vector3.new(right.X, 0, right.Z).Unit 

		local input = Vector3.zero 
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then input += fwd end 
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then input -= fwd end 
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then input -= right end 
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then input += right end 
		if input.Magnitude > 0 then input = input.Unit end 
		moveDir = input 

		applyFriction(dt) 
		local targetSpeed = getCurrentTargetSpeed() 
		accel(moveDir, targetSpeed, cfg.groundAccel, dt) 
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, root.AssemblyLinearVelocity.Y, velocity.Z) 
		updateUI()
	end

	function Module.SetEnabled(state: boolean)
		scriptEnabled = state
		local _, hum, _ = getChar()
		if not scriptEnabled and hum then
			hum.WalkSpeed = baseWalkSpeed
			velocity = Vector3.zero
		end
		updateUI()
	end

	function Module.SetSpeedMode(mode: string)
		speedMode = mode
		updateUI()
	end

	function Module.Destroy()
		for _, conn in pairs(connections) do
			if conn then conn:Disconnect() end
		end
		if screenGui then screenGui:Destroy() end
		local _, hum, _ = getChar()
		if hum then hum.WalkSpeed = baseWalkSpeed end
		_G.SpeedModuleInstance = nil
	end

	if not activeUI then
		buildStandaloneGui()
	end

	connections["Input"] = UserInputService.InputBegan:Connect(function(i, gpe)
		if gpe then return end
		local altHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if altHeld and i.KeyCode == Enum.KeyCode.RightShift then
			Module.Destroy()
			return
		end

		if altHeld and ctrlHeld then
			scriptEnabled = not scriptEnabled
			if not scriptEnabled then
				lastSpeedMode = speedMode
				speedMode = "normal"
				velocity = Vector3.zero
				local _, hum, _ = getChar()
				if hum then hum.WalkSpeed = baseWalkSpeed end
			else
				speedMode = lastSpeedMode
			end
			updateUI()
			return
		end

		if altHeld then
			if i.KeyCode == Enum.KeyCode.X then
				speedMode = (speedMode == "fast") and "normal" or "fast"
				updateUI()
			elseif i.KeyCode == Enum.KeyCode.C then
				speedMode = (speedMode == "super") and "normal" or "super"
				updateUI()
			elseif i.KeyCode == Enum.KeyCode.G then
				speedMode = (speedMode == "dynamic") and "normal" or "dynamic"
				updateUI()
			elseif i.KeyCode == Enum.KeyCode.Y then
				speedMode = (speedMode == "standby") and "normal" or "standby"
				updateUI()
			end
		end
	end)

	connections["Heartbeat"] = RunService.Heartbeat:Connect(process)

	local function setupHumanoidListeners(h: Humanoid)
		connections["SpeedChanged"] = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if scriptEnabled and h.WalkSpeed > 0 then
				baseWalkSpeed = h.WalkSpeed
			end
		end)
	end

	local _, initialHum, _ = getChar()
	if initialHum then setupHumanoidListeners(initialHum) end

	connections["CharAdded"] = localPlayer.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		velocity = Vector3.zero
		baseWalkSpeed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
		setupHumanoidListeners(hum)
	end)

	_G.SpeedModuleInstance = Module
	return Module
end

return SpeedModule
