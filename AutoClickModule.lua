-- Save this file as "AutoClickModule.lua" in your GitHub repo: XOROISPRO/Ryuji/main/
local VirtualInputManager = game:GetService("VirtualInputManager")

local AutoClickModule = {}
local active = false
local clickInterval = 0.1
local clickThread = nil

function AutoClickModule.Init(State, Toggles)
    return AutoClickModule
end

function AutoClickModule.SetInterval(val)
    clickInterval = math.clamp(val, 0.01, 10)
end

function AutoClickModule.Start()
    if active then return end
    active = true
    clickThread = task.spawn(function()
        while active do
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            task.wait(clickInterval)
        end
    end)
end

function AutoClickModule.Stop()
    active = false
    if clickThread then
        task.cancel(clickThread)
        clickThread = nil
    end
end

return AutoClickModule
