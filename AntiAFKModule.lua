--!strict
local AntiAFKModule = {}
AntiAFKModule.__index = AntiAFKModule

local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

function AntiAFKModule.Init(State, Toggles)
    local self = setmetatable({}, AntiAFKModule)
    self.State = State
    self.Toggles = Toggles
    self.Player = Players.LocalPlayer
    
    self.Running = false
    self.Thread = nil :: thread?
    self.IdledConnection = nil :: RBXScriptConnection?
    
    return self
end

function AntiAFKModule:Start()
    if self.Running then return end
    self.Running = true
    if self.State then self.State.AntiAfkActive = true end

    -- Strategy 1: Bypass Roblox's built-in Idle Kick Kickout (Primary)
    self.IdledConnection = self.Player.Idled:Connect(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
        task.wait(0.2)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
    end)

    -- Strategy 2: Periodic Input Simulation Loop (Backup - every 3 minutes)
    self.Thread = task.spawn(function()
        while self.Running do
            task.wait(180)
            if self.Running then
                -- Tap 'W' key briefly to emulate user activity
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                task.wait(0.2)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end
        end
    end)
end

function AntiAFKModule:Stop()
    self.Running = false
    if self.State then self.State.AntiAfkActive = false end

    if self.IdledConnection then
        self.IdledConnection:Disconnect()
        self.IdledConnection = nil
    end

    if self.Thread then
        task.cancel(self.Thread)
        self.Thread = nil
    end
end

return AntiAFKModule
