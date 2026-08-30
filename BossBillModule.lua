local BossBillModule = {}
BossBillModule.__index = BossBillModule

local Workspace = game:GetService("Workspace")

function BossBillModule.Init(State, Toggles)
    local self = setmetatable({}, BossBillModule)
    self.State = State
    self.Toggles = Toggles
    self.IsRunning = false
    self.CreatedLabel = nil
    return self
end

local function applyBossUI(bossObject, self)
    -- Handle case where BossBill IS the BillboardGui itself
    local billboard = nil
    
    if bossObject:IsA("BillboardGui") then
        billboard = bossObject
    else
        billboard = bossObject:FindFirstChildOfClass("BillboardGui")
    end

    if not billboard then return end

    -- Update max distance on target BillboardGui
    billboard.MaxDistance = 1000000

    -- Add or update the custom TextLabel inside the BillboardGui
    local textLabel = billboard:FindFirstChild("BossLabel")
    if not textLabel then
        textLabel = Instance.new("TextLabel")
        textLabel.Name = "BossLabel"
        textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        textLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        textLabel.Size = UDim2.new(1, 0, 0.5, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.SourceSansBold
        
        -- Parent.Name displays the container holding the BillboardGui
        textLabel.Text = bossObject.Parent and bossObject.Parent.Name or bossObject.Name
        textLabel.Parent = billboard
        self.CreatedLabel = textLabel
    else
        textLabel.Text = bossObject.Parent and bossObject.Parent.Name or bossObject.Name
    end
end

function BossBillModule:Start()
    if self.IsRunning then return end
    self.IsRunning = true

    task.spawn(function()
        while self.IsRunning do
            local boss = Workspace:FindFirstChild("LivingBeings")
                and Workspace.LivingBeings:FindFirstChild("Mobs")
                and Workspace.LivingBeings.Mobs:FindFirstChild("Pickle")
                and Workspace.LivingBeings.Mobs.Pickle:FindFirstChild("BossBill")

            if boss then
                applyBossUI(boss, self)
            end

            task.wait(1) -- Throttle updates to run once every second
        end
    end)
end

function BossBillModule:Stop()
    self.IsRunning = false

    if self.CreatedLabel then
        self.CreatedLabel:Destroy()
        self.CreatedLabel = nil
    end
end

return BossBillModule
