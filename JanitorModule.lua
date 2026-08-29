--!strict
local JanitorModule = {}
JanitorModule.__index = JanitorModule

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- Fallback check for VirtualInputManager vs standard keypress functions
local VirtualInputManager = game:GetService("VirtualInputManager")

function JanitorModule.Init(State, Toggles)
    local self = setmetatable({}, JanitorModule)
    self.State = State
    self.Toggles = Toggles
    self.Player = Players.LocalPlayer
    self.DirtFolder = workspace:WaitForChild("Ignore"):WaitForChild("Interactables"):WaitForChild("JobsRelated"):WaitForChild("Janitor"):WaitForChild("Dirt")

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
    self.DEBUG = true -- Set to true to track Anti-AFK events in output

    -- Internal State
    self.Running = false
    self.MoveConnection = nil :: RBXScriptConnection?
    self.CharConnection = nil :: RBXScriptConnection?
    self.TaskThread = nil :: thread?
    self.AntiAFKThread = nil :: thread?

    self.MoveState = {
        velocity = Vector3.new(),
        waypoints = nil,
        waypointIndex = 1,
        done = true,
    }

    return self
end

function JanitorModule:DPrint(...)
    if self.DEBUG then print("[Janitor]", ...) end
end

local function sendKeypress()
    local success, err = pcall(function()
        if typeof(keypress) == "function" and typeof(keyrelease) == "function" then
            -- Standard executor keypress fallback
            keypress(0x57) -- 'W' Keycode
            task.wait(0.2)
            keyrelease(0x57)
        else
            -- VirtualInputManager method
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
            task.wait(0.2)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
        end
    end)
    return success, err
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

local function grounded(character: Model, root: BasePart): (boolean, Vector3?)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
    if result and result.Instance and result.Instance.CanCollide then
        return true, result.Position
    end
    return false, nil
end

local function applyFriction(velocity: Vector3, isGrounded: boolean, friction: number, stopSpeed: number, dt: number): Vector3
    local speed = velocity.Magnitude
    if speed < 0.1 then return Vector3.new() end

    local drop = 0
    if isGrounded then
        local control = math.max(speed, stopSpeed)
        drop = control * friction * dt
    end

    local newSpeed = math.max(speed - drop, 0)
    if newSpeed ~= speed then
        return velocity * (newSpeed / speed)
    end
    return velocity
end

local function accel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, accelRate: number, dt: number): Vector3
    local cur = velocity:Dot(wishDir)
    local add = wishSpeed - cur
    if add <= 0 then return velocity end

    local accelSpeed = math.min(accelRate * dt * wishSpeed, add)
    return velocity + wishDir * accelSpeed
end

-- Movement Mechanics
function JanitorModule:GetWishDirFromPath(root: BasePart, humanoid: Humanoid): (Vector3, number)
    local state = self.MoveState
    if not state.waypoints or state.waypointIndex > #state.waypoints then
        return Vector3.new(), 0
    end

    local wp = state.waypoints[state.waypointIndex]
    local wpPos = typeof(wp) == "Vector3" and wp or (wp :: PathWaypoint).Position
    local isLast = state.waypointIndex == #state.waypoints
    local reachDist = isLast and self.FINAL_REACH_DIST or self.WAYPOINT_REACH_DIST

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

    if flatDelta.Magnitude < 0.01 then
        return Vector3.new(), 0
    end

    return flatDelta.Unit, self.MAX_SPEED
end

function JanitorModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number)
    local isGrounded = grounded(character, root)
    local accelRate = isGrounded and self.ACCEL or self.AIR_ACCEL

    self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
    self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, wishSpeed, accelRate, dt)
    root.AssemblyLinearVelocity = Vector3.new(self.MoveState.velocity.X, root.AssemblyLinearVelocity.Y, self.MoveState.velocity.Z)
end

function JanitorModule:GetPrompt(dirt: Instance): ProximityPrompt?
    return dirt:FindFirstChildWhichIsA("ProximityPrompt", true)
end

function JanitorModule:GetNearestDirt(fromPos: Vector3): Instance?
    local best, bestDist = nil, math.huge
    for _, d in ipairs(self.DirtFolder:GetChildren()) do
        if self:GetPrompt(d) then
            local dist = (d:GetPivot().Position - fromPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                best = d
            end
        end
    end
    return best
end

function JanitorModule:WaitPromptGone(dirt: Instance)
    local prompt = self:GetPrompt(dirt)
    if prompt then
        triggerPrompt(prompt, self.Player)
    end

    while self.Running do
        if not self:GetPrompt(dirt) then
            task.wait(self.CONFIRM_TIME)
            if not self:GetPrompt(dirt) then return end
        else
            local currentPrompt = self:GetPrompt(dirt)
            if currentPrompt then
                triggerPrompt(currentPrompt, self.Player)
            end
            task.wait(self.POLL_TIME)
        end
    end
end

function JanitorModule:WalkTo(targetPos: Vector3, targetInstance: Instance?, char: Model, hrp: BasePart, hum: Humanoid)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
    })

    local ok, _ = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)

    if ok and path.Status == Enum.PathStatus.Success then
        self.MoveState.waypoints = path:GetWaypoints()
    else
        self.MoveState.waypoints = {targetPos}
    end

    self.MoveState.waypointIndex = 1
    self.MoveState.done = false

    local waited = 0
    while not self.MoveState.done and self.Running do
        task.wait()
        waited += 1
        if waited % 300 == 0 and targetInstance then
            local prompt = self:GetPrompt(targetInstance)
            if prompt then
                triggerPrompt(prompt, self.Player)
            end
        end
    end
end

-- Execution Controls
function JanitorModule:Start()
    if self.Running then return end
    self.Running = true

    if self.State then
        self.State.JanitorActive = true
    end

    local char = self.Player.Character or self.Player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid") :: Humanoid
    local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

    -- Movement Loop Connection
    self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
        if self.MoveState.done or not self.Running then return end
        local wishDir, wishSpeed = self:GetWishDirFromPath(hrp, hum)
        self:StepMovement(hrp, char, wishDir, wishSpeed, dt)
    end)

    self.CharConnection = char.Destroying:Connect(function()
        self:Stop()
    end)

    -- Background Anti-AFK Loop
    self.AntiAFKThread = task.spawn(function()
        self:DPrint("Anti-AFK Loop Started.")
        while self.Running do
            task.wait(60) -- Send every minute
            if self.Running then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                    task.wait(0.2)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                end)
                self:DPrint("Anti-AFK pulse sent.")
            end
        end
    end)

    -- Main Processing Thread
    self.TaskThread = task.spawn(function()
        while self.Running do
            local target = self:GetNearestDirt(hrp.Position)
            if not target then
                self:DPrint("No more dirt found, pausing.")
                task.wait(1)
                continue
            end

            self:WalkTo(target:GetPivot().Position, target, char, hrp, hum)

            if self.Running then
                self:WaitPromptGone(target)
            end
        end
    end)
end

function JanitorModule:Stop()
    self.Running = false
    self.MoveState.done = true

    if self.State then
        self.State.JanitorActive = false
    end

    if self.MoveConnection then
        self.MoveConnection:Disconnect()
        self.MoveConnection = nil
    end

    if self.CharConnection then
        self.CharConnection:Disconnect()
        self.CharConnection = nil
    end

    if self.TaskThread then
        task.cancel(self.TaskThread)
        self.TaskThread = nil
    end

    if self.AntiAFKThread then
        task.cancel(self.AntiAFKThread)
        self.AntiAFKThread = nil
    end
end

return JanitorModule
