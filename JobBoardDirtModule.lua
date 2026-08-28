--!strict
local JobBoardDirtModule = {}
JobBoardDirtModule.__index = JobBoardDirtModule

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

function JobBoardDirtModule.Init(State, Toggles)
    local self = setmetatable({}, JobBoardDirtModule)
    
    self.State = State
    self.Toggles = Toggles
    self.Player = Players.LocalPlayer
    
    -- Target References & Locations
    self.JobsRelated = workspace:WaitForChild("Ignore"):WaitForChild("Interactables"):WaitForChild("JobsRelated")
    self.DirtsFolder = self.JobsRelated:WaitForChild("Dirts")
    self.JobBorders = self.JobsRelated:WaitForChild("Job Borders")
    
    self.ReturnCFrame = CFrame.new(670.197754, 101.720299, 621.13446, 0, 0, 1, 0, 1, 0, -1, 0, 0)
    
    -- Movement / Physics Settings
    self.CONFIRM_TIME = 0.5
    self.POLL_TIME = 0.2
    self.MAX_SPEED = 24
    self.ACCEL = 10
    self.AIR_ACCEL = 2
    self.FRICTION = 6
    self.STOP_SPEED = 1.5
    self.WAYPOINT_REACH_DIST = 1
    self.FINAL_REACH_DIST = 1
    
    -- Control States
    self.Running = false
    self.MoveConnection = nil :: RBXScriptConnection?
    self.TaskThread = nil :: thread?
    
    self.MoveState = {
        velocity = Vector3.new(),
        waypoints = nil,
        waypointIndex = 1,
        done = true,
    }

    return self
end

-- Helper Utilities
local function triggerPrompt(prompt: ProximityPrompt, player: Player)
    if not prompt or not prompt.Enabled then return end
    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
    elseif typeof(firesignal) == "function" and prompt.Triggered then
        firesignal(prompt.Triggered, player)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration)
        prompt:InputHoldEnd()
    end
end

local function fireClickDetector(clickDetector: ClickDetector)
    if not clickDetector then return end
    if typeof(fireclickdetector) == "function" then
        fireclickdetector(clickDetector)
    else
        clickDetector:RightMouseClick() -- Fallback attempt
    end
end

local function grounded(character: Model, root: BasePart): boolean
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local result = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
    return (result ~= nil and result.Instance ~= nil and result.Instance.CanCollide)
end

local function applyFriction(velocity: Vector3, isGrounded: boolean, friction: number, stopSpeed: number, dt: number): Vector3
    local speed = velocity.Magnitude
    if speed < 0.1 then return Vector3.new() end
    local drop = isGrounded and (math.max(speed, stopSpeed) * friction * dt) or 0
    local newSpeed = math.max(speed - drop, 0)
    return (newSpeed ~= speed) and (velocity * (newSpeed / speed)) or velocity
end

local function accel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, accelRate: number, dt: number): Vector3
    local add = wishSpeed - velocity:Dot(wishDir)
    if add <= 0 then return velocity end
    return velocity + wishDir * math.min(accelRate * dt * wishSpeed, add)
end

-- Movement Engine
function JobBoardDirtModule:GetWishDirFromPath(root: BasePart, humanoid: Humanoid): (Vector3, number)
    local state = self.MoveState
    if not state.waypoints or state.waypointIndex > #state.waypoints then
        return Vector3.new(), 0
    end
    
    local wp = state.waypoints[state.waypointIndex]
    local wpPos = typeof(wp) == "Vector3" and wp or (wp :: PathWaypoint).Position
    local reachDist = (state.waypointIndex == #state.waypoints) and self.FINAL_REACH_DIST or self.WAYPOINT_REACH_DIST
    local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)
    
    if flatDelta.Magnitude < reachDist then
        if typeof(wp) ~= "Vector3" and (wp :: PathWaypoint).Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        state.waypointIndex += 1
        if state.waypointIndex > #state.waypoints then
            state.velocity = Vector3.new()
            state.done = true
            return Vector3.new(), 0
        end
        local nextWp = state.waypoints[state.waypointIndex]
        local nextPos = typeof(nextWp) == "Vector3" and nextWp or (nextWp :: PathWaypoint).Position
        flatDelta = Vector3.new(nextPos.X - root.Position.X, 0, nextPos.Z - root.Position.Z)
    end
    
    return (flatDelta.Magnitude < 0.01) and Vector3.new() or flatDelta.Unit, self.MAX_SPEED
end

function JobBoardDirtModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number)
    local isGrounded = grounded(character, root)
    local accelRate = isGrounded and self.ACCEL or self.AIR_ACCEL
    self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
    self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, wishSpeed, accelRate, dt)
    root.AssemblyLinearVelocity = Vector3.new(self.MoveState.velocity.X, root.AssemblyLinearVelocity.Y, self.MoveState.velocity.Z)
end

function JobBoardDirtModule:WalkTo(targetPos: Vector3, hrp: BasePart, hum: Humanoid)
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
    local ok = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    
    self.MoveState.waypoints = (ok and path.Status == Enum.PathStatus.Success) and path:GetWaypoints() or {targetPos}
    self.MoveState.waypointIndex = 1
    self.MoveState.done = false
    
    while not self.MoveState.done and self.Running do
        task.wait()
    end
end

-- Task Specific Methods
function JobBoardDirtModule:GetRequiredDirtAmount(): (number, ClickDetector?, Instance?)
    for _, border in ipairs(self.JobBorders:GetChildren()) do
        local posters = border:FindFirstChild("Border") and border.Border:FindFirstChild("Posters")
        if posters then
            for _, poster in ipairs(posters:GetChildren()) do
                local infoLabel = poster:FindFirstChild("SurfaceGui", true) and poster.SurfaceGui:FindFirstChild("Info")
                if infoLabel and infoLabel:IsA("TextLabel") then
                    -- Extract the digit wrapped inside the font tags or text
                    local amountStr = infoLabel.Text:match("Clean%s*<font[^>]*>(%d+)</font>%s*Dirt") or infoLabel.Text:match("(%d+)")
                    if amountStr then
                        local clickDetector = poster:FindFirstChildWhichIsA("ClickDetector", true)
                        return tonumber(amountStr) or 0, clickDetector, poster
                    end
                end
            end
        end
    end
    return 0, nil, nil
end

function JobBoardDirtModule:GetNearestDirt(fromPos: Vector3): Instance?
    local best, bestDist = nil, math.huge
    for _, d in ipairs(self.DirtsFolder:GetChildren()) do
        local prompt = d:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled then
            local dist = (d:GetPivot().Position - fromPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = d
            end
        end
    end
    return best
end

function JobBoardDirtModule:CollectDirt(dirt: Instance)
    local prompt = dirt:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then triggerPrompt(prompt, self.Player) end
    
    while self.Running and dirt:FindFirstChildWhichIsA("ProximityPrompt", true) do
        local currentPrompt = dirt:FindFirstChildWhichIsA("ProximityPrompt", true)
        if currentPrompt then triggerPrompt(currentPrompt, self.Player) end
        task.wait(self.POLL_TIME)
    end
    task.wait(self.CONFIRM_TIME)
end

-- Execution Loop
function JobBoardDirtModule:Start()
    if self.Running then return end
    self.Running = true

    local char = self.Player.Character or self.Player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid") :: Humanoid
    local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

    self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
        if self.MoveState.done or not self.Running then return end
        local wishDir, wishSpeed = self:GetWishDirFromPath(hrp, hum)
        self:StepMovement(hrp, char, wishDir, wishSpeed, dt)
    end)

    self.TaskThread = task.spawn(function()
        while self.Running do
            local neededAmount, clickDetector, poster = self:GetRequiredDirtAmount()
            if neededAmount <= 0 then
                task.wait(2)
                continue
            end
            
            local collected = 0
            while collected < neededAmount and self.Running do
                local targetDirt = self:GetNearestDirt(hrp.Position)
                if not targetDirt then break end
                
                self:WalkTo(targetDirt:GetPivot().Position, hrp, hum)
                if self.Running then
                    self:CollectDirt(targetDirt)
                    collected += 1
                end
            end
            
            -- Walk back to the Job Board location
            if self.Running then
                self:WalkTo(self.ReturnCFrame.Position, hrp, hum)
                
                -- Turn towards poster & Fire ClickDetector once
                if clickDetector then
                    fireClickDetector(clickDetector)
                    task.wait(1)
                end
            end
            
            task.wait(1)
        end
    end)
end

function JobBoardDirtModule:Stop()
    self.Running = false
    self.MoveState.done = true

    if self.MoveConnection then
        self.MoveConnection:Disconnect()
        self.MoveConnection = nil
    end

    if self.TaskThread then
        task.cancel(self.TaskThread)
        self.TaskThread = nil
    end
end

return JobBoardDirtModule
