local BossBillModule = {}
BossBillModule.__index = BossBillModule

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

function BossBillModule.Init(State, Toggles)
    local self = setmetatable({}, BossBillModule)
    self.State = State
    self.Toggles = Toggles
    self.Connection = nil
    self.CurrentBoss = nil
    self.CreatedGui = nil
    return self
end

local function applyBossUI(bossModel)
    -- Locate target part to attach GUI (HumanoidRootPart, Head, or PrimaryPart)
    local targetPart = bossModel:FindFirstChild("HumanoidRootPart") 
        or bossModel:FindFirstChild("Head") 
        or bossModel.PrimaryPart

    if not targetPart then return nil end

    -- Check for existing custom GUI or create a new BillboardGui
    local billboard = targetPart:FindFirstChild("BossBillDisplay")
    if not billboard then
        billboard = Instance.new("BillboardGui")
        billboard.Name = "BossBillDisplay"
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 1000000
        billboard.Size = UDim2.new(4, 0, 1, 0)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = targetPart

        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "BossLabel"
        textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        textLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        textLabel.Size = UDim2.new(1, 0, 0.5, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        textLabel.TextScaled = true
        textLabel.Font = Enum.Font.SourceSansBold
        
        -- Text set to Parent.Name (BossBill or whatever parent model contains it)
        textLabel.Text = bossModel.Parent and bossModel.Parent.Name or bossModel.Name
        textLabel.Parent = billboard
    else
        billboard.MaxDistance = 1000000
    end

    return billboard
end

function BossBillModule:Start()
    if self.Connection then return end

    self.Connection = RunService.Heartbeat:Connect(function()
        local pickleFolder = Workspace:FindFirstChild("LivingBeings")
            and Workspace.LivingBeings:FindFirstChild("Mobs")
            and Workspace.LivingBeings.Mobs:FindFirstChild("Pickle")

        if pickleFolder then
            local boss = pickleFolder:FindFirstChild("BossBill")
            if boss then
                self.CurrentBoss = boss
                self.CreatedGui = applyBossUI(boss)
            end
        end
    end)
end

function BossBillModule:Stop()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end

    if self.CreatedGui then
        self.CreatedGui:Destroy()
        self.CreatedGui = nil
    end
    self.CurrentBoss = nil
end

return BossBillModule
