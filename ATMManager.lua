--!strict
local ATMManager = {}
ATMManager.__index = ATMManager

local Players = game:GetService("Players")

function ATMManager.Init(State, Toggles, PatientModule, ATMModule)
    local self = setmetatable({}, ATMManager)
    self.State = State
    self.Toggles = Toggles
    self.PatientModule = PatientModule
    self.ATMModule = ATMModule
    self.Player = Players.LocalPlayer

    self.Running = false
    self.IsProcessing = false
    self.TargetThreshold = 1000000 -- 1,000,000 Cash
    self.DEBUG = true
    self.WatcherThread = nil :: thread?

    return self
end

function ATMManager:DPrint(...)
    if self.DEBUG then
        print("[ATM Manager Debug]", ...)
    end
end

local function parseCash(text: string): number
    -- Strips everything that isn't a digit (removes ₩, $, commas, spaces, letters, etc.)
    local cleaned = string.gsub(text, "%D", "")
    return tonumber(cleaned) or 0
end

function ATMManager:GetPlayerCash(): (number, string)
    local playerGui = self.Player:FindFirstChild("PlayerGui")
    if not playerGui then
        return 0, "PlayerGui not found"
    end

    -- Drill down through the hierarchy safely
    local hud = playerGui:FindFirstChild("HUD")
    if not hud then return 0, "HUD not found in PlayerGui" end

    local bars = hud:FindFirstChild("Bars")
    if not bars then return 0, "Bars not found in HUD" end

    local mainHud = bars:FindFirstChild("MainHUD")
    if not mainHud then return 0, "MainHUD not found in Bars" end

    local cashLabel = mainHud:FindFirstChild("Cash")
    if not cashLabel then return 0, "Cash element not found in MainHUD" end

    -- Handle TextLabel or TextButton
    local rawText = ""
    if cashLabel:IsA("TextLabel") or cashLabel:IsA("TextButton") then
        rawText = cashLabel.Text
    else
        return 0, "Cash element is not a TextLabel/TextButton (Type: " .. cashLabel.ClassName .. ")"
    end

    local numericCash = parseCash(rawText)
    return numericCash, rawText
end

function ATMManager:Start()
    if self.Running then return end
    self.Running = true

    self.WatcherThread = task.spawn(function()
        self:DPrint("Passive cash monitoring started. Threshold set to:", self.TargetThreshold)
        
        while self.Running do
            task.wait(2) -- Polls every 2 seconds

            if not self.IsProcessing then
                local currentCash, rawText = self:GetPlayerCash()
                
                -- Printed details on every poll check
                self:DPrint(string.format("Raw Text: '%s' | Parsed Cash: %d | Threshold: %d", tostring(rawText), currentCash, self.TargetThreshold))

                if currentCash >= self.TargetThreshold then
                    self.IsProcessing = true
                    self:DPrint(string.format("Threshold MET! (%d >= %d). Initiating transition...", currentCash, self.TargetThreshold))

                    -- 1. Pause PatientModule if it's running
                    local patientWasActive = self.Toggles.PatientToggle and self.Toggles.PatientToggle.Value or false
                    if patientWasActive then
                        self:DPrint("PatientModule is active. Stopping PatientModule before starting ATM sequence...")
                        self.PatientModule:Stop()
                        task.wait(1)
                    else
                        self:DPrint("PatientModule is not active.")
                    end

                    -- 2. Run ATMModule and wait for completion
                    self:DPrint("Launching ATMModule...")
                    self.ATMModule:Start(function()
                        self:DPrint("ATMModule sequence complete.")

                        -- 3. Resume PatientModule if it was active before
                        if patientWasActive and self.Running then
                            self:DPrint("Resuming PatientModule...")
                            task.wait(1)
                            self.PatientModule:Start()
                        end

                        self.IsProcessing = false
                    end)
                end
            else
                self:DPrint("ATM sequence currently processing, skipping poll...")
            end
        end
    end)
end

function ATMManager:Stop()
    self.Running = false
    self.IsProcessing = false
    if self.WatcherThread then
        task.cancel(self.WatcherThread)
        self.WatcherThread = nil
    end
    self:DPrint("Passive cash monitoring stopped.")
end

return ATMManager
