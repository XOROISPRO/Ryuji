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

	local function getChar(): (Model, Humanoid, BasePart)
		local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		local root = char:WaitForChild("HumanoidRootPart") :: BasePart
		return char, hum, root
	end

	function Module.GetMacroState(): boolean
		return localPlayer:GetAttribute("autoMacro") == true
	end

	-- Direct Macro Switcher (Disables/Enables game macro system)
	function Module.SetMacroActive(enabled: boolean)
		State.MacroActive = enabled
		pcall(function()
			macroScript:SetAttribute("AutoUseVests", enabled)
			macroScript:SetAttribute("AutoUseMask", enabled)
		end)
		if Module.GetMacroState() ~= enabled then
			localPlayer:SetAttribute("autoMacro", enabled)
		end
	end

	-- Universal Macro Lock Listener
	function Module.EnsureMacroState(expectedState: boolean)
		Module.SetMacroActive(expectedState)
		if not State.MacroLockConnection then
			State.MacroLockConnection = localPlayer:GetAttributeChangedSignal("autoMacro"):Connect(function()
				local targetState = (State.AutoTrain and not State.Navigating and (State.MacroActive == true))
				if Module.GetMacroState() ~= targetState then
					Module.SetMacroActive(targetState)
				end
			end)
		end
	end

	function Module.UnlockMacroEnforcement()
		if State.MacroLockConnection then
			State.MacroLockConnection:Disconnect()
			State.MacroLockConnection = nil
		end
	end

	function Module.UseEquippedTool(): boolean
		Module.EnsureMacroState(false)
		local char = localPlayer.Character
		if not char then return false end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			tool:Activate()
			return true
		end
		return false
	end

	function Module.UnequipAllTools()
		Module.EnsureMacroState(false)
		local _, hum, _ = getChar()
		if hum then
			pcall(function() hum:UnequipTools() end)
			task.wait(0.2)
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

	function Module.CountTotalFoodInInventory(): number
		local char = localPlayer.Character
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		local count = 0

		if char then
			for _, tool in ipairs(char:GetChildren()) do
				if tool:IsA("Tool") and table.find(FOOD_ITEMS, tool.Name) then
					count += getItemQuantity(tool)
				end
			end
		end

		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and table.find(FOOD_ITEMS, tool.Name) then
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
		Module.EnsureMacroState(false)
		if Module.IsFoodEquipped() then return true end

		local _, hum, _ = getChar()
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		if not backpack or not hum then return false end

		for attempt = 1, 3 do
			Module.EnsureMacroState(false)
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and table.find(FOOD_ITEMS, tool.Name) then
					hum:EquipTool(tool)
					task.wait(0.3)
					if Module.IsFoodEquipped() then return true end
				end
			end
			task.wait(0.2)
		end

		return Module.IsFoodEquipped()
	end

	function Module.EquipSleepingBag(): boolean
		Module.EnsureMacroState(false)
		local char = localPlayer.Character
		local backpack = localPlayer:FindFirstChildOfClass("Backpack")
		local _, hum, _ = getChar()

		if not char or not hum then return false end

		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") and tool.Name == "Sleeping Bag" then
				return true
			end
		end

		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if tool:IsA("Tool") and tool.Name == "Sleeping Bag" then
					hum:EquipTool(tool)
					task.wait(0.3)
					return true
				end
			end
		end

		return false
	end

	function Module.BuySteakInteraction(clicksToBuy: number)
		Module.EnsureMacroState(false)
		local ignoreFolder = Workspace:FindFirstChild("Ignore")
		local interactables = ignoreFolder and ignoreFolder:FindFirstChild("Interactables")
		local buyablesFolder = interactables and interactables:FindFirstChild("Buyables")
		local steakObject = buyablesFolder and buyablesFolder:FindFirstChild("Steak")
		local steakDetector = steakObject and steakObject:FindFirstChildOfClass("ClickDetector")

		if steakDetector and fireclickdetector then
			print(string.format("[Store] Firing Steak ClickDetector %d time(s)...", clicksToBuy))
			for i = 1, clicksToBuy do
				if not State.AutoTrain and not State.Navigating then break end
				Module.EnsureMacroState(false)
				fireclickdetector(steakDetector)
				task.wait(0.25)
			end
		else
			warn("[Store] Steak ClickDetector unavailable or execution platform unsupported.")
		end
	end

	function Module.TryRemoteBuy(): boolean
		Module.EnsureMacroState(false)
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
		print(string.format("[Store] Updated Steak Count: %d/%d", updatedSteaks, MIN_STEAK_THRESHOLD))
		if updatedSteaks > initialSteaks or updatedSteaks >= MIN_STEAK_THRESHOLD then
			return true
		end

		return false
	end

	function Module.HandleRestockFlow()
		Module.EnsureMacroState(false)
		if Module.CountSteaksInInventory() >= MIN_STEAK_THRESHOLD then
			print("[Restock] Inventory satisfied limit. Skipping restock navigation.")
			return
		end

		print("[Restock] Attempting remote buy before walking...")
		if Module.TryRemoteBuy() then
			print("[Restock] Food count satisfied via remote buy! Skipping vendor navigation.")
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
			Module.EnsureMacroState(false)
			task.wait(0.5)
			timeout += 0.5
			if timeout >= 20 then
				warn("[Restock] Navigation timed out! Cancelling path...")
				if PathModule then PathModule.StopPathfinding() end
				break
			end
		until reachedVendor or not State.AutoTrain
	end

	function Module.StopAutoTrain()
		State.AutoTrain = false
		State.MacroActive = false
		Module.UnlockMacroEnforcement()
		Module.SetMacroActive(false)

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
		State.AutoTrain = true
		State.MacroActive = true

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
					print("[Anti-AFK] Pulse sent.")
				end
			end
		end)

		State.TrainThread = task.spawn(function()
			print("[AutoTrain] Initialized.")
			Module.EnsureMacroState(true)

			while State.AutoTrain do
				task.wait(1)
				if not State.AutoTrain then break end

				-- OPERATION 1: SLEEPING
				local currentFatigue = Module.GetFatiguePercent()
				if currentFatigue and currentFatigue >= MAX_FATIGUE_THRESHOLD then
					print(string.format("[AutoTrain] Fatigue high (%.1f%%)! Pausing macro...", currentFatigue))
					Module.EnsureMacroState(false)
					Module.UnequipAllTools()
					task.wait(1)

					while State.AutoTrain do
						Module.EnsureMacroState(false)
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
							local elapsed = 0

							while State.AutoTrain do
								task.wait(3)
								elapsed += 3
								Module.EnsureMacroState(false)

								local liveFatigue = Module.GetFatiguePercent() or lastFatigue
								if elapsed % 6 == 0 then
									print(string.format("[AutoTrain] Resting... Fatigue: %.1f%%", liveFatigue))
								end

								if liveFatigue <= MIN_FATIGUE_TARGET then
									fatigueNow = liveFatigue
									break
								end

								if liveFatigue < lastFatigue then
									stuckCounter = 0
									lastFatigue = liveFatigue
								else
									stuckCounter += 1
									warn(string.format("[AutoTrain] Fatigue stuck at %.1f%% (%d/3)...", liveFatigue, stuckCounter))
								end

								if stuckCounter >= 3 then
									warn("[AutoTrain] Progress halted! Resetting sleeping state...")
									break
								end
							end
						else
							warn("[AutoTrain] Sleeping Bag missing! Retrying in 3s...")
							task.wait(3)
						end
					end

					if State.AutoTrain then
						Module.UnequipAllTools()
						Module.EnsureMacroState(true)
					end
				end

				if not State.AutoTrain then break end

				-- OPERATION 2: EATING & RESTOCKING
				local currentHunger = Module.GetHungerPercent()
				if currentHunger and currentHunger <= MIN_HUNGER_THRESHOLD then
					print("[AutoTrain] Hunger low! Pausing macro completely...")
					
					-- FORCE DISABLE MACRO BEFORE DOING ANYTHING ELSE
					Module.EnsureMacroState(false)
					Module.UnequipAllTools()
					task.wait(0.5)

					print("[AutoTrain] Triggering pre-buy check before eating...")
					Module.TryRemoteBuy()

					if not Module.EquipFood() then
						Module.HandleRestockFlow()
						if not State.AutoTrain then break end
						task.wait(1)
					end

					local failedEquipAttempts = 0
					while State.AutoTrain do
						Module.EnsureMacroState(false)
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
						Module.EnsureMacroState(true)
					end
				end

				-- OPERATION 3: ACTIVE MACRO TRAINING
				if State.AutoTrain and not State.Navigating then
					Module.EnsureMacroState(true)
				end
			end
		end)
	end

	-- Lock initial state strictly to false across system boot
	State.MacroActive = false
	Module.SetMacroActive(false)
	Module.EnsureMacroState(false)

	return Module
end

return TrainModule
