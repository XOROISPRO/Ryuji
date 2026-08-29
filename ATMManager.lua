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
    self.TargetThreshold = 100000 -- Set threshold (100k or 1m)
    self.WatcherThread = nil :: thread?

    return self
end

local function parseCash(text: string): number
    local cleaned = string.gsub(text, "%D", "") -- Remove non-digits (₩, commas, spaces)
    return tonumber(cleaned) or 0
end

function ATMManager:GetPlayerCash(): number
    local playerGui = self.Player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end

    local cashLabel = playerGui:FindFirstChild("HUD") 
        and playerGui.HUD:FindFirstChild("Bars")
        and playerGui.HUD.Bars:FindFirstChild("MainHUD")
        and playerGui.HUD.Bars.MainHUD:FindFirstChild("Cash")

    if cashLabel and cashLabel:IsA("TextLabel") then
        return parseCash(cashLabel.Text)
    end
    return 0
end

function ATMManager:Start()
    if self.Running then return end
    self.Running = true

    self.WatcherThread = task.spawn(function()
        print("[ATM Manager] Passive cash monitoring enabled.")
        while self.Running do
            task.wait(1)

            if not self.IsProcessing then
                local currentCash = self:GetPlayerCash()
                if currentCash >= self.TargetThreshold then
                    self.IsProcessing = true
                    print(("[ATM Manager] Cash threshold reached (%d >= %d). Triggering ATM sequence..."):format(currentCash, self.TargetThreshold))

                    -- 1. Pause PatientModule if it's running
                    local patientWasActive = self.Toggles.PatientToggle and self.Toggles.PatientToggle.Value or false
                    if patientWasActive then
                        print("[ATM Manager] Pausing PatientModule...")
                        self.PatientModule:Stop()
                        task.wait(0.5)
                    end

                    -- 2. Run ATMModule and wait for completion
                    self.ATMModule:Start(function()
                        print("[ATM Manager] ATMModule finished execution.")

                        -- 3. Resume PatientModule if it was active before
                        if patientWasActive and self.Running then
                            print("[ATM Manager] Resuming PatientModule...")
                            task.wait(0.5)
                            self.PatientModule:Start()
                        end

                        self.IsProcessing = false
                    end)
                end
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
    print("[ATM Manager] Passive cash monitoring stopped.")
end

return ATMManager
