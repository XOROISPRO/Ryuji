--!strict
local MapCleanerModule = {}
MapCleanerModule.__index = MapCleanerModule

function MapCleanerModule.Init(State, Toggles)
    local self = setmetatable({}, MapCleanerModule)
    self.State = State
    self.Toggles = Toggles
    
    -- Targeted Part Configuration
    self.TargetCFrame = CFrame.new(
        682.881714, 107.716339, -920.858521, 
        0.707134247, 0, 0.707079291, 
        0, 1, 0, 
        -0.707079291, 0, 0.707134247
    )
    self.TargetColor = Color3.fromRGB(193, 217, 185)
    self.Epsilon = 0.01

    return self
end

function MapCleanerModule:CleanTargetPart(): boolean
    local defaultFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Default")
    if not defaultFolder then
        warn("[MapCleaner] workspace.Map.Default not found!")
        return false
    end

    for _, child in ipairs(defaultFolder:GetChildren()) do
        if child:IsA("BasePart") then
            local posDiff = (child.CFrame.Position - self.TargetCFrame.Position).Magnitude
            if posDiff < self.Epsilon and child.Color == self.TargetColor then
                print("[MapCleaner] Found target part: " .. child:GetFullName() .. " - Destroying...")
                child:Destroy()
                return true
            end
        end
    end

    warn("[MapCleaner] Target part not found in workspace.Map.Default.")
    return false
end

return MapCleanerModule
