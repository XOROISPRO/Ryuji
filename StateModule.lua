-- Host on GitHub Raw / Gist
local State = {
    AutoTrain = false,
    Navigating = false,
    Connections = {},
    ActiveKeys = {},
    Velocity = Vector3.zero,
    TrainThread = nil,
    AntiAfkThread = nil,
    CurrentPath = nil,
    MacroLockConnection = nil
}

return State
