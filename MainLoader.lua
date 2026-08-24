-- Clean existing instance
if _G.AutoTrain_Cleanup then _G.AutoTrain_Cleanup() end

-- Fetch Remote Modules
local baseUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/"
local State = loadstring(game:HttpGet(baseUrl .. "StateModule.lua"))()

-- Initialize UI
local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local Toggles = Library.Toggles

-- Load Handlers
local PathModule = loadstring(game:HttpGet(baseUrl .. "PathfindingModule.lua"))().Init(State, Toggles)
local TrainModule = loadstring(game:HttpGet(baseUrl .. "TrainModule.lua"))().Init(State, Toggles, PathModule)

-- Setup Cleanup
local function killScriptAndGui()
    TrainModule.StopAutoTrain()
    PathModule.StopPathfinding()
    _G.AutoTrain_Cleanup = nil
    if Library and Library.Unload then Library:Unload() end
end
_G.AutoTrain_Cleanup = killScriptAndGui

-- Window UI
local Window = Library:CreateWindow({ Title = 'Auto-Train Manager', Center = true, AutoShow = true })
local Tab = Window:AddTab('Main Controls'):AddLeftGroupbox('Automations')

Tab:AddToggle('AutoTrainToggle', {
    Text = 'Auto Train', Default = false,
    Callback = function(v) if v then TrainModule.StartAutoTrain() else TrainModule.StopAutoTrain() end end
})

Tab:AddToggle('NavToggle', {
    Text = 'Navigate to Vendor', Default = false,
    Callback = function(v) if v then PathModule.NavigateToVendor() else PathModule.StopPathfinding() end end
})

Tab:AddButton({ Text = 'Unload Script', Func = killScriptAndGui })
