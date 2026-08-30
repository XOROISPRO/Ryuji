local InjuredCitizenModule = {}
InjuredCitizenModule.__index = InjuredCitizenModule

local Workspace = game:GetService("Workspace")

local HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 0, 0)
local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local HIGHLIGHT_FILL_TRANSPARENCY = 0.5
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

local BILLBOARD_SIZE = UDim2.new(0, 300, 0, 100)
local BILLBOARD_MAX_DISTANCE = math.huge

function InjuredCitizenModule.Init(State, Toggles)
    local self = setmetatable({}, InjuredCitizenModule)
    self.State = State
    self.Toggles = Toggles
    self.Connections = {}
    self.CreatedHighlights = {}
    return self
end

local function applyInjuredEffects(model)
    if not model:IsA("Model") or model.Name ~= "InjuredCitizen" then return end

    -- 1. Add Highlight if missing
    if not model:FindFirstChildOfClass("Highlight") then
        local highlight = Instance.new("Highlight")
        highlight.Name = "InjuredCitizenHighlight"
        highlight.FillColor = HIGHLIGHT_FILL_COLOR
        highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
        highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
        highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = model
    end

    -- 2. Modify DeathTimer BillboardGui
    local billboard = model:WaitForChild("DeathTimer", 5)
    if billboard and billboard:IsA("BillboardGui") then
        billboard.Size = BILLBOARD_SIZE
        billboard.MaxDistance = BILLBOARD_MAX_DISTANCE
        billboard.AlwaysOnTop = true

        for _, descendant in ipairs(billboard:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                descendant.TextScaled = true
                descendant.Size = UDim2.fromScale(1, 1)
            end
        end
    end
end

function InjuredCitizenModule:Start()
    self:Stop() -- Clear previous connections if re-enabled

    local livingBeings = Workspace:FindFirstChild("LivingBeings")
    if not livingBeings then return end

    -- Process existing entities
    for _, child in ipairs(livingBeings:GetChildren()) do
        if child.Name == "InjuredCitizen" then
            task.spawn(applyInjuredEffects, child)
        end
    end

    -- Listen for newly spawned entities
    local conn = livingBeings.ChildAdded:Connect(function(child)
        if child.Name == "InjuredCitizen" then
            task.spawn(applyInjuredEffects, child)
        end
    end)
    table.insert(self.Connections, conn)
end

function InjuredCitizenModule:Stop()
    -- Disconnect event listeners
    for _, conn in ipairs(self.Connections) do
        conn:Disconnect()
    end
    self.Connections = {}

    -- Clean up created highlights
    local livingBeings = Workspace:FindFirstChild("LivingBeings")
    if livingBeings then
        for _, child in ipairs(livingBeings:GetChildren()) do
            if child.Name == "InjuredCitizen" then
                local hl = child:FindFirstChild("InjuredCitizenHighlight")
                if hl then
                    hl:Destroy()
                end
            end
        end
    end
end

return InjuredCitizenModule
