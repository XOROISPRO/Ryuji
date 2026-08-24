--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local macroScript = ReplicatedStorage:WaitForChild("Modules")
	:WaitForChild("Client")
	:WaitForChild("Main")
	:WaitForChild("Core2")
	:WaitForChild("macro")

local TrainModule = {}

-- Constants
local FOOD_ITEMS = { "Boba Tea", "Coffee", "Steak", "Dango" }
local REQUIRED_TRAINING_TOOLS = { "Jumping Rope", "One Hand Pushups" }
local MIN_MONEY_LIMIT = 1000

local MAX_STEAK_TARGET = 11
local MIN_STEAK_THRESHOLD = 10
local MIN_HUNGER_THRESHOLD = 25
local MIN_EAT_TARGET = 70
local MAX_FATIGUE_THRESHOLD = 80
local MIN_FATIGUE_TARGET = 0

function TrainModule.Init(State: any, Toggles: any)
	local Module = {}
	local PathModule: any = nil

	function Module.SetPathModule(pm: any)
		PathModule = pm
	end

	local function getChar(): (Model, Humanoid, BasePart)?
		local char = localPlayer.Character
		if not char then return nil end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and root then
			return char, hum, root
		end
		return nil
	end

	-- Checks player's Yen / Money value
	function Module.GetPlayerMoney(): number
		local moneyAttr = localPlayer:GetAttribute("Yen") 
			or localPlayer:GetAttribute("Money") 
			or localPlayer:GetAttribute("yen") 
			or localPlayer:GetAttribute("money")

		if moneyAttr and type(moneyAttr) == "number" then
			return moneyAttr
		end

		-- Fallback Leaderstats check
		local leaderstats = localPlayer:FindFirstChild("leaderstats")
		if leaderstats then
			local yenVal = leaderstats:FindFirstChild("Yen") or leaderstats:FindFirstChild("Money")
			if yenVal and yenVal:IsA("ValueBase") then
				return tonumber(yenVal.Value) or 0
			end
		end

		return 0
	end

	-- Checks if player has both Jumping Rope and One Hand Pushups
	function Module.HasRequiredTrainingTools(): (boolean, string?)
		local char = localPlayer.Character
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		
		for _, requiredTool in ipairs(REQUIRED_TRAINING_TOOLS) do
			local found = false

			if char and char:FindFirstChild(requiredTool) then
				found = true
			elseif backpack and backpack:FindFirstChild(requiredTool) then
				found = true
			end

			if not found then
				return false, requiredTool
			end
		end

		return true, nil
	end

	-- Check if player is dead or missing humanoid
	function Module.IsDead(): boolean
		local char = localPlayer.Character
		if not char then return true end
		
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
			return true
		end

		return false
	end

	-- Kick Safety Checks Handler
	function Module.CheckKickConditions(): boolean
		-- 1. Check Death State
		if Module.IsDead() then
			local msg = "[AutoTrain Kick] Character died."
			warn(msg)
			localPlayer:Kick(msg)
			return true
		end

		-- 2. Check Required Tools
		local hasTools, missingTool = Module.HasRequiredTrainingTools()
		if not hasTools then
			local msg = string.format("[AutoTrain Kick] Missing required training tool: '%s'", tostring(missingTool))
			warn(msg)
			localPlayer:Kick(msg)
			return true
		end

		-- 3. Check Money Balance
		local currentMoney = Module.GetPlayerMoney()
		if currentMoney <= MIN_MONEY_LIMIT then
			local msg = string.format("[AutoTrain Kick] Money is too low ($%d <= $%d)", currentMoney, MIN_MONEY_LIMIT)
			warn(msg)
			localPlayer:Kick(msg)
			return true
		end

		return false
	end

	-- Setup active Death Listener on Humanoid directly
	function Module.SetupDeathConnection()
		if State.DeathConnection then
			State.DeathConnection:Disconnect()
			State.DeathConnection = nil
		end

		local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?

		if hum then
			State.DeathConnection = hum.Died:Connect(function()
				if State.AutoTrain then
					local msg = "[AutoTrain Kick] Character died."
					warn(msg)
					localPlayer:Kick(msg)
				end
			end)
		end
	end

	-- Checks if macro attribute is explicitly false or nil
	function Module.IsMacroDisabled(): boolean
		local attr = localPlayer:GetAttribute("autoMacro")
		return attr == false or attr == nil
	end

	-- Forcefully disables macro and waits until the state is verified false/nil
	function Module.VerifyMacroDisabled(): boolean
		State.MacroActive = false

		for attempt = 1, 5 do
			localPlayer:SetAttribute("autoMacro", false)

			pcall(function()
				macroScript:SetAttribute("AutoUseVests", false)
				macroScript:SetAttribute("AutoUseMask", false)
			end)

			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)

			task.wait(0.1)

			if Module.IsMacroDisabled() then
				return true
			end
		end

		return Module.IsMacroDisabled()
	end

	-- Sets active state strictly for training
	function Module.SetMacroActive(enabled: boolean)
		if enabled then
			State.MacroActive = true
			localPlayer:SetAttribute("autoMacro", true)
			pcall(function()
				macroScript:SetAttribute("AutoUseVests", true)
				macroScript:SetAttribute("AutoUseMask", true)
			end)
		else
			Module.VerifyMacroDisabled()
		end
	end

	function Module.UnequipAllTools()
		Module.VerifyMacroDisabled()
		local res = getChar()
		if res then
			local _, hum, _ = res
			pcall(function() hum:UnequipTools() end)
			task.wait(0.3)
		end
	end

	function Module.GetHungerPercent(): number?
		local attrHunger = localPlayer:GetAttribute("Hunger") or localPlayer:GetAttribute("hunger")
		if attrHunger and type(attrHunger) == "number" then return attrHunger end

		local success, text = pcall(function()
			return playerGui.HUD.Bars.MainHUD.HungerDisplay.Text
		end)
		if success and text then
			local rawNum = string.match(text, "%d+")
			if rawNum then return tonumber(rawNum) end
		end
		return nil
	end

	function Module.GetFatiguePercent(): number?
		local attrFatigue = localPlayer:GetAttribute("Fatigue") or localPlayer:GetAttribute("fatigue")
		if attrFatigue and type(attrFatigue) == "number" then return attrFatigue end

		local success, text = pcall(function()
			return playerGui.HUD.Bars.MainHUD.FatigueStamina.Text
		end)
		if success and text then
			local fatigueVal = string.match(text, "Fatigue:%s*(%d+%.?%d*)")
			if fatigueVal then return tonumber(fatigueVal) end
		end
		return nil
	end

	local function getItemQuantity(tool: Instance): number
		local qtyAttr = tool:GetAttribute("Quantity") or tool:GetAttribute("quantity") or tool:GetAttribute("Amount")
		if qtyAttr and type(qtyAttr) == "number" then return qtyAttr end
		return 1
	end

	function Module.CountSteaksInInventory(): number
		local char = localPlayer.Character
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		local count = 0

		if char then
			for _, tool in ipairs(char:GetChildren()) do
				if tool:IsA("Tool") and tool.Name == "Steak" then
					count += getItemQuantity(tool)
				end
			end
		end

		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and tool.Name == "Steak" then
					count += getItemQuantity(tool)
				end
			end
		end

		return count
	end

	function Module.IsFoodEquipped(): boolean
		local char = localPlayer.Character
		if not char then return false end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and table.find(FOOD_ITEMS, tool.Name) then
				return true
			end
		end
		return false
	end

	function Module.EquipFood(): boolean
		if not Module.VerifyMacroDisabled() then
			warn("[AutoTrain] Could not verify macro disabled before equipping food!")
			return false
		end

		if Module.IsFoodEquipped() then return true end

		local res = getChar()
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		if not backpack or not res then return false end

		local char, hum, _ = res

		for attempt = 1, 3 do
			Module.VerifyMacroDisabled()
			hum:UnequipTools()
			task.wait(0.2)

			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and table.find(FOOD_ITEMS, tool.Name) then
					tool.Parent = char
					task.wait(0.3)
					if Module.IsFoodEquipped() then return true end
				end
			end
			task.wait(0.2)
		end

		return Module.IsFoodEquipped()
	end

	function Module.EquipSleepingBag(): boolean
		if not Module.VerifyMacroDisabled() then
			warn("[AutoTrain] Could not verify macro disabled before equipping Sleeping Bag!")
			return false
		end

		local char = localPlayer.Character
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		local res = getChar()

		if not char or not res then return false end

		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and tool.Name == "Sleeping Bag" then
				return true
			end
		end

		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and tool.Name == "Sleeping Bag" then
					tool.Parent = char
					task.wait(0.3)
					return true
				end
			end
		end

		return false
	end

	function Module.UseEquippedTool(): boolean
		Module.VerifyMacroDisabled()
		local char = localPlayer.Character
		if not char then return false end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			tool:Activate()
			return true
		end
		return false
	end

	function Module.BuySteakInteraction(clicksToBuy: number)
		Module.VerifyMacroDisabled()
		local ignoreFolder = Workspace:FindFirstChild("Ignore")
		local interactables = ignoreFolder and ignoreFolder:FindFirstChild("Interactables")
		local buyablesFolder = interactables and interactables:FindFirstChild("Buyables")
		local steakObject = buyablesFolder and buyablesFolder:FindFirstChild("Steak")
		local steakDetector = steakObject and steakObject:FindFirstChildOfClass("ClickDetector")

		if steakDetector and fireclickdetector then
			print(string.format("[Store] Firing Steak ClickDetector %d time(s)...", clicksToBuy))
			for i = 1, clicksToBuy do
				if not State.AutoTrain and not State.Navigating then break end
				Module.VerifyMacroDisabled()
				fireclickdetector(steakDetector)
				task.wait(0.25)
			end
		end
	end

	function Module.TryRemoteBuy(): boolean
		Module.VerifyMacroDisabled()
		local initialSteaks = Module.CountSteaksInInventory()
		if initialSteaks >= MIN_STEAK_THRESHOLD then
			print(string.format("[Store] Steak limit reached (%d/%d). Skipping buy.", initialSteaks, MIN_STEAK_THRESHOLD))
			return true
		end

		local needed = MAX_STEAK_TARGET - initialSteaks
		if needed > 0 then
			print(string.format("[Store] Attempting remote buy for %d steak(s)...", needed))
			Module.BuySteakInteraction(needed)
			task.wait(0.5)
		end

		local updatedSteaks = Module.CountSteaksInInventory()
		if updatedSteaks > initialSteaks or updatedSteaks >= MIN_STEAK_THRESHOLD then
			return true
		end

		return false
	end

	function Module.HandleRestockFlow()
		Module.VerifyMacroDisabled()
		if Module.CountSteaksInInventory() >= MIN_STEAK_THRESHOLD then
			return
		end

		if Module.TryRemoteBuy() then
			return
		end

		warn("[Restock] Remote buy ineffective. Navigating to vendor...")
		local reachedVendor = false
		if PathModule then
			PathModule.NavigateToCFrame(PathModule.TARGET_CFRAME, function()
				reachedVendor = true
			end)
		end

		local timeout = 0
		repeat
			Module.VerifyMacroDisabled()
			task.wait(0.5)
			timeout += 0.5
			if timeout >= 20 then
				if PathModule then PathModule.StopPathfinding() end
				break
			end
		until reachedVendor or not State.AutoTrain
	end

	function Module.StopAutoTrain()
		State.AutoTrain = false
		Module.VerifyMacroDisabled()

		if State.DeathConnection then
			State.DeathConnection:Disconnect()
			State.DeathConnection = nil
		end

		if State.TrainThread then
			task.cancel(State.TrainThread)
			State.TrainThread = nil
		end

		if State.AntiAfkThread then
			task.cancel(State.AntiAfkThread)
			State.AntiAfkThread = nil
		end

		if PathModule then
			PathModule.StopPathfinding()
		end

		if Toggles and Toggles.AutoTrainToggle then
			Toggles.AutoTrainToggle:SetValue(false)
		end

		print("[AutoTrain] System Stopped.")
	end

	function Module.StartAutoTrain()
		Module.StopAutoTrain()

		-- PRE-CHECK: KICK IMMEDIATELY IF DEAD OR REQUIREMENTS ARE NOT MET
		if Module.CheckKickConditions() then
			return
		end

		State.AutoTrain = true
		Module.SetupDeathConnection()

		if Toggles and Toggles.AutoTrainToggle then
			Toggles.AutoTrainToggle:SetValue(true)
		end

		State.AntiAfkThread = task.spawn(function()
			while State.AutoTrain do
				task.wait(300)
				if State.AutoTrain then
					VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
					task.wait(0.5)
					VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
				end
			end
		end)

		State.TrainThread = task.spawn(function()
			print("[AutoTrain] Initialized.")

			while State.AutoTrain do
				task.wait(1)
				if not State.AutoTrain then break end

				-- CONTINUOUS SAFETY CHECK
				if Module.CheckKickConditions() then
					break
				end

				-- OPERATION 1: SLEEPING
				local currentFatigue = Module.GetFatiguePercent()
				if currentFatigue and currentFatigue >= MAX_FATIGUE_THRESHOLD then
					print(string.format("[AutoTrain] Fatigue high (%.1f%%)! Verifying macro disabled...", currentFatigue))
					Module.VerifyMacroDisabled()
					Module.UnequipAllTools()
					task.wait(0.5)

					while State.AutoTrain do
						if Module.CheckKickConditions() then break end

						if not Module.IsMacroDisabled() then
							Module.VerifyMacroDisabled()
						end

						local fatigueNow = Module.GetFatiguePercent() or 0
						if fatigueNow <= MIN_FATIGUE_TARGET then
							print("[AutoTrain] Rest complete!")
							break
						end

						Module.UnequipAllTools()
						task.wait(0.5)

						if Module.EquipSleepingBag() then
							task.wait(0.3)
							Module.UseEquippedTool()

							local lastFatigue = fatigueNow
							local stuckCounter = 0

							while State.AutoTrain do
								task.wait(3)

								if Module.CheckKickConditions() then break end

								if not Module.IsMacroDisabled() then
									Module.VerifyMacroDisabled()
								end

								local liveFatigue = Module.GetFatiguePercent() or lastFatigue
								if liveFatigue <= MIN_FATIGUE_TARGET then
									fatigueNow = liveFatigue
									break
								end

								if liveFatigue < lastFatigue then
									stuckCounter = 0
									lastFatigue = liveFatigue
								else
									stuckCounter += 1
								end

								if stuckCounter >= 3 then
									warn("[AutoTrain] Fatigue stuck! Resetting state...")
									break
								end
							end
						else
							task.wait(3)
						end
					end

					if State.AutoTrain then
						Module.UnequipAllTools()
						task.wait(0.5)
					end
				end

				if not State.AutoTrain then break end

				-- OPERATION 2: EATING & RESTOCKING
				local currentHunger = Module.GetHungerPercent()
				if currentHunger and currentHunger <= MIN_HUNGER_THRESHOLD then
					print("[AutoTrain] Hunger low! Verifying macro disabled...")

					Module.VerifyMacroDisabled()
					Module.UnequipAllTools()
					task.wait(0.5)

					Module.TryRemoteBuy()

					if not Module.EquipFood() then
						Module.HandleRestockFlow()
						if not State.AutoTrain then break end
						task.wait(1)
					end

					local failedEquipAttempts = 0
					while State.AutoTrain do
						if Module.CheckKickConditions() then break end

						if not Module.IsMacroDisabled() then
							warn("[AutoTrain] Macro re-enabled unexpectedly! Force disabling...")
							Module.VerifyMacroDisabled()
						end

						local hungerNow = Module.GetHungerPercent() or 0
						if hungerNow >= MIN_EAT_TARGET then
							print(string.format("[AutoTrain] Restored Hunger to %d%%.", hungerNow))
							break
						end

						if not Module.EquipFood() then
							failedEquipAttempts += 1
							warn(string.format("[AutoTrain] Equip food failed (%d/3)...", failedEquipAttempts))
							if failedEquipAttempts >= 3 then
								warn("[AutoTrain] Restocking food...")
								Module.UnequipAllTools()
								Module.HandleRestockFlow()
								if not State.AutoTrain then break end
								task.wait(1)
								failedEquipAttempts = 0
							end
							task.wait(0.5)
						else
							failedEquipAttempts = 0
							Module.UseEquippedTool()
							task.wait(0.8)
						end
					end

					if State.AutoTrain then
						Module.UnequipAllTools()
						task.wait(0.5)
					end
				end

				-- OPERATION 3: ACTIVE MACRO TRAINING
				if State.AutoTrain and not State.Navigating then
					Module.SetMacroActive(true)
				end
			end
		end)
	end

	-- Initialize default state strictly disabled
	Module.VerifyMacroDisabled()

	return Module
end

return TrainModule
