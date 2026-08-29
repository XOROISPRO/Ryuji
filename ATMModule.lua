--!strict
local ATMModule = {}
ATMModule.__index = ATMModule

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Ensure compatibility with environment firesignal / getconnections
local firesignal = firesignal or function(signal)
    if getconnections then
        for _, connection in ipairs(getconnections(signal)) do
            if connection.Fire then
                connection:Fire()
            elseif connection.Function then
                connection.Function()
            end
        end
    end
end

function ATMModule.Init(State, Toggles)
    local self = setmetatable({}, ATMModule)
    self.State = State
    self.Toggles = Toggles
    self.Player = Players.LocalPlayer

    -- Target CFrames & World Pivot
    self.ATM_STAND_CFRAME = CFrame.new(
        866.421997, 101.868713, -921.240356, 
        0.00871905126, -4.68019046e-09, 0.999961972, 
        1.93347383e-08, 1, 4.51178117e-09, 
        -0.999961972, 1.92946654e-08, 0.00871905126
    )

    self.TARGET_ATM_PIVOT = CFrame.new(
        862.994568, 101.668419, -921.223633, 
        -1, 0, -0, 
        0, 0, -1, 
        0, -1, -0
    )

    -- Execution Parameters (Aligned with custom movement engine)
    self.MAX_SPEED = 35
    self.ACCEL = 25
    self.AIR_ACCEL = 2
    self.FRICTION = 6
    self.STOP_SPEED = 1.5
    self.WAYPOINT_REACH_DIST = 1.5
    self.FINAL_REACH_DIST = 2
    self.DEBUG = true

    -- Internal Threading & Connections
    self.Running = false
    self.MoveConnection = nil :: RBXScriptConnection?
    self.CharConnection = nil :: RBXScriptConnection?
    self.InputConnection = nil :: RBXScriptConnection?
    self.TaskThread = nil :: thread?

    self.MoveState = {
        velocity = Vector3.new(),
        waypoints = nil,
        waypointIndex = 1,
        done = true,
        targetY = nil :: number?,
        forceJump = false,
    }

    return self
end

function ATMModule:DPrint(...)
    if self.DEBUG then print("[ATM Service]", ...) end
end

-- Helper Physics Utilities
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

local function calculateYVelocity(currentY: number, targetY: number, gravity: number): number
    local heightDiff = targetY - currentY
    if heightDiff > 0.5 then
        return math.sqrt(2 * gravity * (heightDiff + 1.5))
    end
    return 0
end

-- UI Helper Function
local function clickGuiButton(button: Instance)
    if not button then return end
    if button:IsA("GuiButton") then
        if firesignal then
            firesignal(button.MouseButton1Click)
            firesignal(button.Activated)
        end
    end
end

-- Custom Physics Movement Mechanics
function ATMModule:GetWishDirFromPath(root: BasePart): (Vector3, number)
    local state = self.MoveState
    if not state.waypoints or state.waypointIndex > #state.waypoints then
        state.targetY = nil
        return Vector3.new(), 0
    end

    local wp = state.waypoints[state.waypointIndex]
    local wpPos = typeof(wp) == "Vector3" and wp or (wp :: PathWaypoint).Position
    state.targetY = wpPos.Y

    local isLast = state.waypointIndex == #state.waypoints
    local reachDist = isLast and self.FINAL_REACH_DIST or self.WAYPOINT_REACH_DIST
    local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)

    if flatDelta.Magnitude < reachDist then
        if typeof(wp) ~= "Vector3" and (wp :: PathWaypoint).Action == Enum.PathWaypointAction.Jump then
            state.forceJump = true
        end
        state.waypointIndex += 1
        if state.waypointIndex > #state.waypoints then
            state.velocity = Vector3.new()
            state.done = true
            state.targetY = nil
            return Vector3.new(), 0
        end
        local nextWp = state.waypoints[state.waypointIndex]
        local nextPos = typeof(nextWp) == "Vector3" and nextWp or (nextWp :: PathWaypoint).Position
        state.targetY = nextPos.Y
        flatDelta = Vector3.new(nextPos.X - root.Position.X, 0, nextPos.Z - root.Position.Z)
    end

    if flatDelta.Magnitude < 0.01 then
        return Vector3.new(), 0
    end

    return flatDelta.Unit, self.MAX_SPEED
end

function ATMModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number)
    local isGrounded = grounded(character, root)
    local accelRate = isGrounded and self.ACCEL or self.AIR_ACCEL

    self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
    self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, wishSpeed, accelRate, dt)

    local yVel = root.AssemblyLinearVelocity.Y
    if isGrounded then
        if self.MoveState.forceJump then
            yVel = 45
            self.MoveState.forceJump = false
        elseif self.MoveState.targetY then
            local dynamicBoost = calculateYVelocity(root.Position.Y, self.MoveState.targetY, workspace.Gravity)
            if dynamicBoost > 0 then
                yVel = dynamicBoost
            end
        end
    end

    root.AssemblyLinearVelocity = Vector3.new(
        self.MoveState.velocity.X,
        yVel,
        self.MoveState.velocity.Z
    )
end

function ATMModule:WalkTo(targetPos: Vector3, hrp: BasePart, hum: Humanoid)
    self:DPrint("walkTo called, target =", tostring(targetPos))
    local wps = nil
    local attempts = 0

    while self.Running do
        attempts += 1
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })
        local ok, err = pcall(function()
            path:ComputeAsync(hrp.Position, targetPos)
        end)

        if ok and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            if #waypoints > 0 then
                wps = waypoints
                self:DPrint(("path computed on attempt %d: %d waypoints"):format(attempts, #wps))
                break
            end
        end

        if attempts % 3 == 0 then
            self:DPrint("Path blocked; applying dynamic Y-velocity unstick boost.")
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 45, hrp.AssemblyLinearVelocity.Z)
        end
        task.wait(0.3)
    end

    if not self.Running or not wps then return end

    self.MoveState.waypoints = wps
    self.MoveState.waypointIndex = 1
    self.MoveState.done = false
    self.MoveState.forceJump = false

    while not self.MoveState.done and self.Running do
        task.wait()
    end

    self:DPrint("walkTo finished")
end

-- Core ATM Identification & Interaction Pipeline
function ATMModule:FindTargetATM(): ClickDetector?
    local atmsFolder = workspace:FindFirstChild("Interactables") and workspace.Interactables:FindFirstChild("ATMs")
    if not atmsFolder then
        self:DPrint("ATMs Folder not found in workspace.Interactables")
        return nil
    end

    local targetPos = self.TARGET_ATM_PIVOT.Position
    local bestATM: Instance? = nil
    local bestDist = math.huge

    for _, atm in ipairs(atmsFolder:GetChildren()) do
        local pivot = atm:GetPivot()
        local dist = (pivot.Position - targetPos).Magnitude
        
        -- Matches exact or closest ATM based on WorldPivot
        if dist < bestDist then
            bestDist = dist
            bestATM = atm
        end
    end

    if bestATM and bestDist < 2 then
        local hitbox = bestATM:FindFirstChild("Hitbox")
        if hitbox then
            local cd = hitbox:FindFirstChildWhichIsA("ClickDetector")
            if cd then
                self:DPrint("Successfully located target ATM ClickDetector:", bestATM:GetFullName())
                return cd
            end
        end
    end

    self:DPrint("Failed to locate ATM ClickDetector near specified WorldPivot.")
    return nil
end

function ATMModule:ExecuteATMTransaction()
    self:DPrint("Executing ATM UI actions...")

    local playerGui = self.Player:WaitForChild("PlayerGui")
    local atmTab = playerGui:WaitForChild("HUD"):WaitForChild("Tabs"):WaitForChild("ATM")

    -- 1. Deposit 1,000,000
    local amountBox = atmTab:WaitForChild("AmountBox") :: TextBox
    amountBox.Text = "1000000"
    task.wait(0.1)

    local depositBtn = atmTab:WaitForChild("Deposit")
    clickGuiButton(depositBtn)
    self:DPrint("Clicked Deposit.")
    task.wait(0.5)

    -- 2. Switch to Transfer Tab
    local transferBtn = atmTab:WaitForChild("Transfer")
    clickGuiButton(transferBtn)
    self:DPrint("Clicked Transfer Tab.")
    task.wait(0.5)

    -- 3. Fill Transfer Frame details
    local transferFrame = atmTab:WaitForChild("TransferFrame")
    local transferAmountBox = transferFrame:WaitForChild("AmountBox") :: TextBox
    local usernameBox = transferFrame:WaitForChild("Username") :: TextBox

    transferAmountBox.Text = "1000000"
    usernameBox.Text = "jotla13"
    task.wait(0.2)

    -- 4. Confirm Transfer
    local confirmBtn = transferFrame:WaitForChild("Confirm")
    clickGuiButton(confirmBtn)
    self:DPrint("Clicked Transfer Confirm button.")
end

-- Add this method to ATMModule.lua
function ATMModule:Start(onComplete: (() -> ())?)
    if self.Running then return end
    self.Running = true

    local char = self.Player.Character or self.Player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid") :: Humanoid
    local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

    self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
        if self.MoveState.done or not self.Running then return end
        local wishDir, wishSpeed = self:GetWishDirFromPath(hrp)
        self:StepMovement(hrp, char, wishDir, wishSpeed, dt)
    end)

    self.TaskThread = task.spawn(function()
        self:DPrint("Starting ATM Automation Sequence...")

        self:WalkTo(self.ATM_STAND_CFRAME.Position, hrp, hum)
        if not self.Running then return end

        local clickDetector = self:FindTargetATM()
        if clickDetector and fireclickdetector then
            fireclickdetector(clickDetector)
            task.wait(0.8)
        else
            self:DPrint("Error: Target ATM ClickDetector not found.")
            self:Stop()
            if onComplete then onComplete() end
            return
        end

        if self.Running then
            self:ExecuteATMTransaction()
        end

        self:DPrint("ATM Automation Sequence complete.")
        self:Stop()
        if onComplete then onComplete() end
    end)
end

function ATMModule:Stop()
    self.Running = false
    self.MoveState.done = true

    if self.MoveConnection then
        self.MoveConnection:Disconnect()
        self.MoveConnection = nil
    end

    if self.CharConnection then
        self.CharConnection:Disconnect()
        self.CharConnection = nil
    end

    if self.InputConnection then
        self.InputConnection:Disconnect()
        self.InputConnection = nil
    end

    if self.TaskThread then
        task.cancel(self.TaskThread)
        self.TaskThread = nil
    end
end

return ATMModule
