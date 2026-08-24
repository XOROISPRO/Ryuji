local TrainModule = {}

function TrainModule.Init(State, Toggles, PathModule)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local localPlayer = Players.LocalPlayer
    local macroScript = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client"):WaitForChild("Main"):WaitForChild("Core2"):WaitForChild("macro")

    function TrainModule.SetMacroState(shouldEnable)
        pcall(function()
            macroScript:SetAttribute("AutoUseVests", shouldEnable)
            macroScript:SetAttribute("AutoUseMask", shouldEnable)
        end)
        localPlayer:SetAttribute("autoMacro", shouldEnable)
    end

    function TrainModule.StopAutoTrain()
        State.AutoTrain = false
        TrainModule.SetMacroState(false)

        if State.TrainThread then task.cancel(State.TrainThread) State.TrainThread = nil end
        PathModule.StopPathfinding()

        if Toggles and Toggles.AutoTrainToggle then Toggles.AutoTrainToggle:SetValue(false) end
    end

    function TrainModule.StartAutoTrain()
        TrainModule.StopAutoTrain()
        State.AutoTrain = true
        if Toggles and Toggles.AutoTrainToggle then Toggles.AutoTrainToggle:SetValue(true) end

        State.TrainThread = task.spawn(function()
            TrainModule.SetMacroState(true)
            while State.AutoTrain do
                task.wait(1)
                -- Hunger/Fatigue loop logic goes here
            end
        end)
    end

    return TrainModule
end

return TrainModule
