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
    self.DEBUG = true
    
    -- Target References
    self.JobsRelated = workspace:WaitForChild("Ignore"):WaitForChild("Interactables"):WaitForChild("JobsRelated")
    self.DirtsFolder = self.JobsRelated:WaitForChild("Dirts")
    self.JobBorders = self.JobsRelated:WaitForChild("Job Borders")
    
    -- Updated Correct Job Board Location
    self.ReturnCFrame = CFrame.new(
        332.598724, 101.868713, 308.419708, 
        0.993266642, -2.84389445e-09, 0.11585056, 
        1.42587266e-08, 1, -9.77019283e-08, 
        -0.11585056, 9.86959492e-08, 0.993266642
    )
    
    -- Zone Boundary Config
    self.ZoneCFrame = CFrame.new(169.400146, 115.595703, 642.775269, 1, -0, 0, 0, 1, -0, 0, 0, 1)
    self.ZoneSize = Vector3.new(325, 50, 400)
    
    -- Physics Parameters
    self.CONFIRM_TIME = 0.5
    self.POLL_TIME = 0.2
    self.MAX_SPEED = 24
    self.ACCEL = 10
    self.AIR_ACCEL = 2
    self.FRICTION = 6
    self.STOP_SPEED = 1.5
    self.WAYPOINT_REACH_DIST = 1
    self.FINAL_REACH_DIST = 1
    
    -- Execution States
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

function JobBoardDirtModule:DPrint(...)
    if self.DEBUG then print("[JobBoardDirt]", ...) end
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
        clickDetector:RightMouseClick()
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

function JobBoardDirtModule:IsInsideZone(position: Vector3): boolean
    local localPos = self.ZoneCFrame:PointToObjectSpace(position)
    local halfSize = self.ZoneSize / 2
    
    return math.abs(localPos.X) <= halfSize.X and
           math.abs(localPos.Y) <= halfSize.Y and
           math.abs(localPos.Z) <= halfSize.Z
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
    self:DPrint("Walking to target:", targetPos)
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
    local ok, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    
    if ok and path.Status == Enum.PathStatus.Success then
        self.MoveState.waypoints = path:GetWaypoints()
        self:DPrint("Path computed successfully with", #self.MoveState.waypoints, "waypoints.")
    else
        self:DPrint("Path computing failed. Using direct fallback vector.", tostring(err))
        self.MoveState.waypoints = {targetPos}
    end
    
    self.MoveState.waypointIndex = 1
    self.MoveState.done = false
    
    while not self.MoveState.done and self.Running do
        task.wait()
    end
    self:DPrint("Reached target position.")
end

-- Poster Discovery
function JobBoardDirtModule:GetRequiredDirtAmount(): (number, ClickDetector?, Instance?)
    self:DPrint("Locating main Job Board via WorldPivot...")
    
    local targetPivotPos = Vector3.new(329.766632, 103.041214, 305.412903)
    local targetBorder: Instance? = nil

    -- Find the specific Border matching the WorldPivot position
    for _, border in ipairs(self.JobBorders:GetChildren()) do
        local pivot = border:GetPivot()
        if (pivot.Position - targetPivotPos).Magnitude < 1 then
            targetBorder = border
            break
        end
    end

    if not targetBorder then
        -- Fallback: Use the child directly named "Border" if pivot matching fails
        targetBorder = self.JobBorders:FindFirstChild("Border")
    end

    if not targetBorder then
        self:DPrint("ERROR: Could not locate the target Job Board border!")
        return 0, nil, nil
    end

    local postersFolder = targetBorder:FindFirstChild("Posters", true)
    if not postersFolder then
        self:DPrint("ERROR: Could not find 'Posters' folder in target border!")
        return 0, nil, nil
    end

    -- Dynamically fetch descendants of Posters every cycle
    self:DPrint("Scanning posters dynamically...")
    for _, poster in ipairs(postersFolder:GetChildren()) do
        local surfaceGui = poster:FindFirstChildWhichIsA("SurfaceGui", true)
        local infoLabel = surfaceGui and surfaceGui:FindFirstChild("Info")
        
        if infoLabel and infoLabel:IsA("TextLabel") then
            local text = infoLabel.Text
            self:DPrint("Checking poster text:", text)
            
            if text:find("Clean") and text:find("Dirt") then
                -- Match digits inside RichText tags or standard string
                local amountStr = text:match("<font[^>]*>(%d+)</font>") 
                    or text:match("Clean%s*(%d+)%s*Dirt") 
                    or text:match("(%d+)")
                
                if amountStr then
                    local amount = tonumber(amountStr) or 0
                    local clickDetector = poster:FindFirstChildWhichIsA("ClickDetector", true)
                    self:DPrint(string.format("Found valid Dirt Job! Amount: %d", amount))
                    return amount, clickDetector, poster
                end
            end
        end
    end

    self:DPrint("No active Dirt Job posters found on board.")
    return 0, nil, nil
end

function JobBoardDirtModule:CollectDirt(dirt: Instance)
    self:DPrint("Collecting dirt item:", dirt:GetFullName())
    local prompt = dirt:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then 
        triggerPrompt(prompt, self.Player) 
    end
    
    while self.Running and dirt:FindFirstChildWhichIsA("ProximityPrompt", true) do
        local currentPrompt = dirt:FindFirstChildWhichIsA("ProximityPrompt", true)
        if currentPrompt then 
            triggerPrompt(currentPrompt, self.Player) 
        end
        task.wait(self.POLL_TIME)
    end
    task.wait(self.CONFIRM_TIME)
    self:DPrint("Cleared dirt item.")
end

-- Execution Loop
function JobBoardDirtModule:Start()
    if self.Running then return end
    self.Running = true
    self:DPrint("Job Board Dirt Module initialized & starting loop.")

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
            -- Step 1: Walk to board
            self:DPrint("Moving to Job Board CFrame...")
            self:WalkTo(self.ReturnCFrame.Position, hrp, hum)
            
            -- Step 2: Search for job poster
            local neededAmount, clickDetector, poster = self:GetRequiredDirtAmount()
            
            if clickDetector then
                self:DPrint("Interacting with poster ClickDetector...")
                fireClickDetector(clickDetector)
                task.wait(1)
            end
            
            if neededAmount <= 0 then
                self:DPrint("No dirt needed or poster unreadable. Retrying in 3s...")
                task.wait(3)
                continue
            end
            
            -- Step 3: Collect dirt within zone
            local collected = 0
            self:DPrint(string.format("Collecting %d dirt items...", neededAmount))
            
            while collected < neededAmount and self.Running do
                local targetDirt = self:GetNearestDirtInZone(hrp.Position)
                if not targetDirt then 
                    self:DPrint("No valid dirt found inside defined zone bounds!")
                    break 
                end
                
                self:WalkTo(targetDirt:GetPivot().Position, hrp, hum)
                if self.Running then
                    self:CollectDirt(targetDirt)
                    collected += 1
                    self:DPrint(string.format("Progress: %d/%d collected.", collected, neededAmount))
                end
            end
            
            -- Step 4: Return to board and complete job
            if self.Running and collected >= neededAmount then
                self:DPrint("Collection complete! Returning to Job Board...")
                self:WalkTo(self.ReturnCFrame.Position, hrp, hum)
                
                if clickDetector then
                    self:DPrint("Submitting job via ClickDetector...")
                    fireClickDetector(clickDetector)
                    task.wait(1.5)
                end
                self:DPrint("Job cycle completed successfully!")
            end
            
            task.wait(2)
        end
    end)
end

function JobBoardDirtModule:Stop()
    self:DPrint("Stopping Job Board Dirt Module...")
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
