local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local EPSILON = 1e-10
local MAX_BALLISTIC_ITERATIONS = 20
local CACHE_CLEANUP_INTERVAL = 30
local VELOCITY_HISTORY_SIZE = 10

local Config = {
    Aimbot = {
        Enabled = true,
        FOV = 1000,
        Smoothness = 0.15,
        ActivationKey = Enum.UserInputType.MouseButton2,
        UsePrediction = true,
        UseAdvancedPrediction = true,
        PredictionMultiplier = 1.0,
        DefaultBulletSpeed = 4000.0,
        DefaultBulletGravity = 0.0,
        PriorityParts = {"Head", "UpperTorso", "Torso"},
        ScreenMargin = 50,

        PredictedPositionMargin = -100,
        UseKalmanFiltering = true,
        UseAccelerationPrediction = true,
        UseMovementPatternAnalysis = true,
    },
    ESP = {
        Enabled = true,
        UpdateInterval = 0.15,
        Colors = {
            Visible = Color3.fromRGB(255, 0, 0),
            Hidden = Color3.fromRGB(0, 150, 255),
            ForceField = Color3.fromRGB(255, 255, 0),
        },
        FillTransparency = 0.85,
        OutlineTransparency = 0.3,
        MaxDistance = 1000,
        HighDetailDistance = 100,
        LowDetailDistance = 500,
        BodyParts = {
            "Head",
            "UpperTorso", "LowerTorso", "Torso",
            "LeftUpperArm", "LeftLowerArm", "LeftHand",
            "RightUpperArm", "RightLowerArm", "RightHand",
            "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
            "RightUpperLeg", "RightLowerLeg", "RightFoot"
        },
    },
    GunOffset = {
        Right = 1.2,
        Up = 0.3,
        Forward = 0.5,
    },
    VisibilityCache = {
        UpdateInterval = 0.2,
        MaxAge = 5.0,
    },
}

local State = {
    playerHighlights = {},
    isAimbotActive = false,
    lastESPUpdate = 0,
    velocityHistory = {},
    currentWeaponStats = nil,
    pingHistory = {},
    averagePing = 0.0,
    frameCount = 0,
    gunPosition = nil,
    visibilityCache = {},
    visibilityCacheTimestamps = {},
    lastCacheCleanup = 0,
    raycastParams = nil,
    kalmanStates = {},
}

local Utils = {}

function Utils.isEnemy(player)
    if not player or player == LocalPlayer then return false end
    local localTeam = LocalPlayer.Team
    local playerTeam = player.Team
    if not localTeam or not playerTeam then return true end
    return localTeam ~= playerTeam
end

function Utils.getCharacter(player)
    if not player then return nil end
    local char = player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    local rootPart = char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end
    return char, humanoid, rootPart
end

function Utils.hasForceField(char)
    if not char then return false end
    return char:FindFirstChildOfClass("ForceField") ~= nil
end

function Utils.getGunPosition()
    local char = LocalPlayer.Character
    if not char then return Camera.CFrame.Position end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        local handle = tool:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            local muzzle = handle:FindFirstChild("Muzzle") or handle:FindFirstChild("MuzzleFlash")
            if muzzle and muzzle:IsA("Attachment") then
                return muzzle.WorldPosition
            end
            return handle.Position
        end
    end

    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if not torso then return Camera.CFrame.Position end

    local cameraCFrame = Camera.CFrame
    return torso.Position + 
           (cameraCFrame.RightVector * Config.GunOffset.Right) + 
           (cameraCFrame.UpVector * Config.GunOffset.Up) + 
           (cameraCFrame.LookVector * Config.GunOffset.Forward)
end

function Utils.isOnScreen(position, customMargin)
    local viewportPoint, onScreen = Camera:WorldToViewportPoint(position)

    if not onScreen then
        return false
    end

    local screenSize = Camera.ViewportSize
    local margin = customMargin or Config.Aimbot.ScreenMargin

    return viewportPoint.X >= margin and 
           viewportPoint.X <= (screenSize.X - margin) and
           viewportPoint.Y >= margin and 
           viewportPoint.Y <= (screenSize.Y - margin)
end

function Utils.getKeyBodyParts(char, distance)
    local parts = {}
    local partNames = {}

    if distance < Config.ESP.HighDetailDistance then
        partNames = Config.ESP.BodyParts
    elseif distance < Config.ESP.LowDetailDistance then
        partNames = {"Head", "UpperTorso", "Torso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg"}
    else
        partNames = {"Head", "UpperTorso", "Torso"}
    end

    for _, partName in ipairs(partNames) do
        local part = char:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end

    if #parts == 0 then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
                table.insert(parts, child)
                break
            end
        end
    end

    return parts
end

local WeaponSystem = {}

function WeaponSystem.update()
    local char = LocalPlayer.Character
    if not char then
        State.currentWeaponStats = {
            velocity = Config.Aimbot.DefaultBulletSpeed,
            gravity = Config.Aimbot.DefaultBulletGravity,
        }
        return
    end

    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then
        State.currentWeaponStats = {
            velocity = Config.Aimbot.DefaultBulletSpeed,
            gravity = Config.Aimbot.DefaultBulletGravity,
        }
        return
    end

    local gravity = Config.Aimbot.DefaultBulletGravity
    local pg = tool:GetAttribute("ProjectileGravity")
    if pg then
        if typeof(pg) == "Vector3" then
            gravity = pg.Y
        elseif typeof(pg) == "number" then
            gravity = pg
        end
    end

    State.currentWeaponStats = {
        velocity = tool:GetAttribute("Velocity") or Config.Aimbot.DefaultBulletSpeed,
        gravity = gravity,
        toolName = tool.Name,
    }
end

local VisibilitySystem = {}

function VisibilitySystem.getRaycastParams()
    if not State.raycastParams then
        State.raycastParams = RaycastParams.new()
        State.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        State.raycastParams.IgnoreWater = true
        State.raycastParams.RespectCanCollide = true 
    end

    local filterList = {}
    if LocalPlayer.Character then
        table.insert(filterList, LocalPlayer.Character)
    end
    State.raycastParams.FilterDescendantsInstances = filterList

    return State.raycastParams
end

function VisibilitySystem.isValidObstacle(part)
    if not part then return false end

    if not part.CanCollide then
        return false
    end

    if part.Transparency >= 0.95 then
        return false
    end

    local partName = part.Name:lower()
    if partName:find("effect") or 
       partName:find("particle") or 
       partName:find("beam") or 
       partName:find("light") or
       partName:find("sound") or
       partName:find("attachment") then
        return false
    end

    local parent = part.Parent
    if parent then
        local parentName = parent.Name:lower()
        if parentName:find("effect") or 
           parentName:find("particle") or
           parentName:find("fx") or
           parentName:find("visual") then
            return false
        end
    end

    return true
end

function VisibilitySystem.performRaycast(origin, targetPos, targetChar)
    local direction = targetPos - origin
    local distance = direction.Magnitude

    if distance > Config.ESP.MaxDistance or distance < EPSILON then
        return false
    end

    local params = VisibilitySystem.getRaycastParams()
    local currentOrigin = origin
    local remainingDirection = direction
    local maxIterations = 10 

    local iteration = 0

    while iteration < maxIterations do
        iteration = iteration + 1

        local result = workspace:Raycast(currentOrigin, remainingDirection, params)

        if not result then
            return true
        end

        if targetChar and result.Instance:IsDescendantOf(targetChar) then
            return true
        end

        if VisibilitySystem.isValidObstacle(result.Instance) then
            return false
        end

        local filterList = params.FilterDescendantsInstances
        table.insert(filterList, result.Instance)
        params.FilterDescendantsInstances = filterList

        local traveledDistance = result.Distance
        local remainingDistance = remainingDirection.Magnitude - traveledDistance

        if remainingDistance < EPSILON then
            return true
        end

        currentOrigin = result.Position + (remainingDirection.Unit * 0.01)
        remainingDirection = remainingDirection.Unit * remainingDistance
    end

    return true
end

function VisibilitySystem.checkVisibility(gunPos, part, targetChar)
    if not part or not part:IsA("BasePart") then
        return false
    end

    local partPos = part.Position
    local distance = (partPos - gunPos).Magnitude

    if distance > Config.ESP.MaxDistance then
        return false
    end

    return VisibilitySystem.performRaycast(gunPos, partPos, targetChar)
end

function VisibilitySystem.getCacheKey(player, partName)
    return tostring(player.UserId) .. "_" .. partName
end

function VisibilitySystem.getVisibility(player, partName, gunPos, part, char)
    local cacheKey = VisibilitySystem.getCacheKey(player, partName)
    local currentTime = tick()
    local lastUpdate = State.visibilityCacheTimestamps[cacheKey] or 0

    if currentTime - lastUpdate < Config.VisibilityCache.UpdateInterval then
        local cachedValue = State.visibilityCache[cacheKey]
        if cachedValue ~= nil then
            return cachedValue
        end
    end

    local isVisible = VisibilitySystem.checkVisibility(gunPos, part, char)
    State.visibilityCache[cacheKey] = isVisible
    State.visibilityCacheTimestamps[cacheKey] = currentTime
 
    return isVisible
end

function VisibilitySystem.cleanupCache()
    local currentTime = tick()
    local maxAge = Config.VisibilityCache.MaxAge

    for key, timestamp in pairs(State.visibilityCacheTimestamps) do
        if currentTime - timestamp > maxAge then
            State.visibilityCache[key] = nil
            State.visibilityCacheTimestamps[key] = nil
        end
    end
end

local HighPrecisionMath = {}

function HighPrecisionMath.vectorMagnitude(vec)
    return math.sqrt(vec.X * vec.X + vec.Y * vec.Y + vec.Z * vec.Z)
end

function HighPrecisionMath.distance(pos1, pos2)
    local dx = pos2.X - pos1.X
    local dy = pos2.Y - pos1.Y
    local dz = pos2.Z - pos1.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function HighPrecisionMath.normalize(vec)
    local mag = HighPrecisionMath.vectorMagnitude(vec)
    if mag < EPSILON then
        return Vector3.new(0, 0, 0)
    end
    return vec / mag
end

function HighPrecisionMath.dot(v1, v2)
    return v1.X * v2.X + v1.Y * v2.Y + v1.Z * v2.Z
end

local KalmanFilter = {}

function KalmanFilter.init(player)
    if not State.kalmanStates[player] then
        State.kalmanStates[player] = {
            estimate = Vector3.new(0, 0, 0),
            errorCovariance = 1.0,
            processNoise = 0.01,
            measurementNoise = 0.1,
        }
    end
end

function KalmanFilter.update(player, measurement)
    KalmanFilter.init(player)
    local state = State.kalmanStates[player]

    local predictedEstimate = state.estimate
    local predictedCovariance = state.errorCovariance + state.processNoise

    local kalmanGain = predictedCovariance / (predictedCovariance + state.measurementNoise)
    local innovation = measurement - predictedEstimate

    state.estimate = predictedEstimate + (innovation * kalmanGain)
    state.errorCovariance = (1 - kalmanGain) * predictedCovariance

    return state.estimate
end

local VelocityTracker = {}

function VelocityTracker.update(player, currentVelocity)
    if not State.velocityHistory[player] then
        State.velocityHistory[player] = {}
    end

    local history = State.velocityHistory[player]
    local currentTime = tick()

    table.insert(history, {
        velocity = currentVelocity,
        timestamp = currentTime,
    })

    while #history > VELOCITY_HISTORY_SIZE do
        table.remove(history, 1)
    end
end

function VelocityTracker.estimateAcceleration(player)
    local history = State.velocityHistory[player]
    if not history or #history < 2 then
        return Vector3.new(0, 0, 0)
    end

    if #history >= 3 then
        local n = #history
        local sumTime = 0
        local sumVel = Vector3.new(0, 0, 0)
        local sumTimeVel = Vector3.new(0, 0, 0)
        local sumTimeSq = 0

        local baseTime = history[1].timestamp

        for i = 1, n do
            local t = history[i].timestamp - baseTime
            local v = history[i].velocity

            sumTime = sumTime + t
            sumVel = sumVel + v
            sumTimeVel = sumTimeVel + (v * t)
            sumTimeSq = sumTimeSq + (t * t)
        end

        local denominator = n * sumTimeSq - sumTime * sumTime
        if math.abs(denominator) > EPSILON then
            local acceleration = (sumTimeVel * n - sumVel * sumTime) / denominator
            return acceleration
        end
    end

    local latest = history[#history]
    local previous = history[#history - 1]
    local deltaTime = latest.timestamp - previous.timestamp

    if deltaTime < EPSILON then
        return Vector3.new(0, 0, 0)
    end

    return (latest.velocity - previous.velocity) / deltaTime
end

function VelocityTracker.getSmoothedVelocity(player)
    local history = State.velocityHistory[player]
    if not history or #history == 0 then
        return Vector3.new(0, 0, 0)
    end

    if #history == 1 then
        return history[1].velocity
    end

    if Config.Aimbot.UseKalmanFiltering then
        local latest = history[#history].velocity
        return KalmanFilter.update(player, latest)
    end

    local totalWeight = 0.0
    local weightedSum = Vector3.new(0, 0, 0)

    for i = 1, #history do
        local weight = math.exp((i - 1) / (#history - 1))
        totalWeight = totalWeight + weight
        weightedSum = weightedSum + (history[i].velocity * weight)
    end

    return weightedSum / totalWeight
end

function VelocityTracker.cleanup()
    for player in pairs(State.velocityHistory) do
        if not player.Parent then
            State.velocityHistory[player] = nil
        end
    end
    for player in pairs(State.kalmanStates) do
        if not player.Parent then
            State.kalmanStates[player] = nil
        end
    end
end

local BallisticSolver = {}

function BallisticSolver.solveBallisticArc(shooterPos, targetPos, targetVel, bulletSpeed, gravity)
    if bulletSpeed < EPSILON then
        return targetPos, 0.0
    end

    local relativePos = targetPos - shooterPos
    local distance = HighPrecisionMath.vectorMagnitude(relativePos)
    local estimatedTime = distance / bulletSpeed

    local Vt = targetVel
    local S = bulletSpeed

    local a = Vt.X * Vt.X + Vt.Y * Vt.Y + Vt.Z * Vt.Z - S * S
    local b = 2 * (relativePos.X * Vt.X + relativePos.Y * Vt.Y + relativePos.Z * Vt.Z)
    local c = relativePos.X * relativePos.X + relativePos.Y * relativePos.Y + relativePos.Z * relativePos.Z

    local t = estimatedTime

    if math.abs(a) > EPSILON then
        local discriminant = b * b - 4 * a * c
        if discriminant >= 0 then
            local sqrtDisc = math.sqrt(discriminant)
            local t1 = (-b + sqrtDisc) / (2 * a)
            local t2 = (-b - sqrtDisc) / (2 * a)

            if t1 > 0 and t2 > 0 then
                t = math.min(t1, t2)
            elseif t1 > 0 then
                t = t1
            elseif t2 > 0 then
                t = t2
            end
        end
    elseif math.abs(b) > EPSILON then
        local candidate = -c / b
        if candidate > 0 then
            t = candidate
        end
    end

    local bestTime = t
    local bestError = math.huge

    for iteration = 1, MAX_BALLISTIC_ITERATIONS do
        local predictedPos = targetPos + Vt * bestTime

        if math.abs(gravity) > EPSILON then
            local gravityDrop = 0.5 * math.abs(gravity) * bestTime * bestTime
            predictedPos = Vector3.new(predictedPos.X, predictedPos.Y - gravityDrop, predictedPos.Z)
        end

        local newDist = HighPrecisionMath.distance(shooterPos, predictedPos)
        local newTime = newDist / S

        local error = math.abs(newTime - bestTime)

        if error < EPSILON * 10 then
            return predictedPos, bestTime
        end

        if error < bestError then
            bestError = error
            bestTime = newTime
        end
    end

    local finalPos = targetPos + Vt * bestTime
    if math.abs(gravity) > EPSILON then
        local gravityDrop = 0.5 * math.abs(gravity) * bestTime * bestTime
        finalPos = Vector3.new(finalPos.X, finalPos.Y - gravityDrop, finalPos.Z)
    end

    return finalPos, bestTime
end

local AdvancedPrediction = {}

function AdvancedPrediction.calculateAimPoint(targetPos, player, rootPart, gunPos)
    if not Config.Aimbot.UsePrediction then
        return targetPos
    end

    local weaponStats = State.currentWeaponStats
    if not weaponStats then
        return targetPos
    end

    local bulletSpeed = weaponStats.velocity
    local gravity = weaponStats.gravity
    local currentVelocity = rootPart.AssemblyLinearVelocity

    VelocityTracker.update(player, currentVelocity)

    local smoothedVelocity = currentVelocity

    if Config.Aimbot.UseAdvancedPrediction then
        smoothedVelocity = VelocityTracker.getSmoothedVelocity(player)

        if Config.Aimbot.UseAccelerationPrediction then
            local acceleration = VelocityTracker.estimateAcceleration(player)
            local accelMagnitude = HighPrecisionMath.vectorMagnitude(acceleration)

            if accelMagnitude > 1.0 then
                local initialTime = HighPrecisionMath.distance(gunPos, targetPos) / bulletSpeed
                smoothedVelocity = smoothedVelocity + (acceleration * initialTime * 0.5)
            end
        end
    end

    local adjustedVelocity = smoothedVelocity * Config.Aimbot.PredictionMultiplier

    local pingTimeCompensation = (State.averagePing / 1000.0) * 0.5
    
    local serverTargetPos = targetPos + (adjustedVelocity * pingTimeCompensation)

    local predictedPos, flightTime = BallisticSolver.solveBallisticArc(
        gunPos,
        serverTargetPos,
        adjustedVelocity,
        bulletSpeed,
        gravity
    )

    return predictedPos
end

local TargetSelector = {}

function TargetSelector.getBestTarget()
    if not Config.Aimbot.Enabled or not State.isAimbotActive then
        return nil
    end

    if not Camera or not LocalPlayer.Character then
        return nil
    end

    local gunPos = Utils.getGunPosition()
    State.gunPosition = gunPos

    local cameraPos = Camera.CFrame.Position
    local lookVector = Camera.CFrame.LookVector
    local bestTarget = nil
    local bestScore = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not Utils.isEnemy(player) then continue end

        local char, humanoid, rootPart = Utils.getCharacter(player)
        if not char then continue end
        if Utils.hasForceField(char) then continue end

        for _, partName in ipairs(Config.Aimbot.PriorityParts) do
            local part = char:FindFirstChild(partName)
            if not part or not part:IsA("BasePart") then continue end

            local partPos = part.Position

            if not Utils.isOnScreen(partPos) then continue end

            local distance = HighPrecisionMath.distance(gunPos, partPos)
            local directionToTarget = HighPrecisionMath.normalize(partPos - cameraPos)
            local dotProduct = HighPrecisionMath.dot(lookVector, directionToTarget)
            local angle = math.deg(math.acos(math.clamp(dotProduct, -1.0, 1.0)))

            if angle > Config.Aimbot.FOV then continue end

            local isVisible = VisibilitySystem.getVisibility(player, partName, gunPos, part, char)
            if not isVisible then continue end

            local predictedPos = AdvancedPrediction.calculateAimPoint(
                partPos,
                player,
                rootPart,
                gunPos
            )

            if not Utils.isOnScreen(predictedPos, Config.Aimbot.PredictedPositionMargin) then
                predictedPos = partPos
            end

            local predictedDir = HighPrecisionMath.normalize(predictedPos - cameraPos)
            local predictedDot = HighPrecisionMath.dot(lookVector, predictedDir)
            local predictedAngle = math.deg(math.acos(math.clamp(predictedDot, -1.0, 1.0)))

            local score = predictedAngle + (distance / 500.0)

            if score < bestScore then
                bestScore = score
                bestTarget = {
                    player = player,
                    part = part,
                    originalPos = partPos,
                    aimPoint = predictedPos,
                    distance = distance,
                    velocity = HighPrecisionMath.vectorMagnitude(rootPart.AssemblyLinearVelocity),
                    velocityVector = rootPart.AssemblyLinearVelocity,
                    angle = predictedAngle,
                }
            end

            break
        end
    end

    return bestTarget
end

local AimbotExecutor = {}

function AimbotExecutor.execute()
    if not Config.Aimbot.Enabled or not State.isAimbotActive then
        return
    end

    local target = TargetSelector.getBestTarget()
    if not target then
        return
    end

    local currentCFrame = Camera.CFrame
    local targetCFrame = CFrame.new(currentCFrame.Position, target.aimPoint)

    Camera.CFrame = currentCFrame:Lerp(targetCFrame, Config.Aimbot.Smoothness)
end

local ESPSystem = {}

function ESPSystem.createHighlight(part)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Part"
    highlight.Adornee = part
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = Config.ESP.FillTransparency
    highlight.OutlineTransparency = Config.ESP.OutlineTransparency

    pcall(function()
        highlight.Parent = game:GetService("CoreGui")
    end)

    return highlight
end

function ESPSystem.updatePlayerHighlights(player, char, gunPos, distance)
    if not State.playerHighlights[player] then
        State.playerHighlights[player] = {}
    end

    local bodyParts = Utils.getKeyBodyParts(char, distance)
    local activePartNames = {}
    local hasFF = Utils.hasForceField(char)

    for _, part in ipairs(bodyParts) do
        local partName = part.Name
        activePartNames[partName] = true

        if not State.playerHighlights[player][partName] then
            State.playerHighlights[player][partName] = ESPSystem.createHighlight(part)
        end

        local highlight = State.playerHighlights[player][partName]
        if highlight and highlight.Parent then
            highlight.Enabled = true
            highlight.Adornee = part

            if hasFF then
                highlight.FillColor = Config.ESP.Colors.ForceField
                highlight.OutlineColor = Config.ESP.Colors.ForceField
            else
                local isVisible = VisibilitySystem.getVisibility(player, partName, gunPos, part, char)

                if isVisible then
                    highlight.FillColor = Config.ESP.Colors.Visible
                    highlight.OutlineColor = Config.ESP.Colors.Visible
                else
                    highlight.FillColor = Config.ESP.Colors.Hidden
                    highlight.OutlineColor = Config.ESP.Colors.Hidden
                end
            end
        end
    end

    for partName, highlight in pairs(State.playerHighlights[player]) do
        if not activePartNames[partName] then
            if highlight then
                highlight:Destroy()
            end
            State.playerHighlights[player][partName] = nil
        end
    end
end

function ESPSystem.update()
    if not Config.ESP.Enabled then return end

    local currentTime = tick()
    if currentTime - State.lastESPUpdate < Config.ESP.UpdateInterval then
        return
    end
    State.lastESPUpdate = currentTime

    if not Camera or not LocalPlayer.Character then return end

    local gunPos = Utils.getGunPosition()
    local activePlayers = {}
    local playerCount = 0

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        local char = Utils.getCharacter(player)

        if not char then
            if State.playerHighlights[player] then
                for _, highlight in pairs(State.playerHighlights[player]) do
                    if highlight then
                        highlight:Destroy()
                    end
                end
                State.playerHighlights[player] = nil
            end
            continue
        end

        if not Utils.isEnemy(player) then
            if State.playerHighlights[player] then
                for _, highlight in pairs(State.playerHighlights[player]) do
                    if highlight then
                        highlight.Enabled = false
                    end
                end
            end
            continue
        end

        local rootPart = char:FindFirstChild("HumanoidRootPart")
        if not rootPart then continue end

        local distance = (rootPart.Position - gunPos).Magnitude

        if distance > Config.ESP.MaxDistance then
            if State.playerHighlights[player] then
                for _, highlight in pairs(State.playerHighlights[player]) do
                    if highlight then
                        highlight.Enabled = false
                    end
                end
            end
            continue
        end

        activePlayers[player] = true
        playerCount = playerCount + 1

        local hasFF = Utils.hasForceField(char)

        if hasFF or playerCount % 2 == State.frameCount % 2 or distance < Config.ESP.HighDetailDistance then
            ESPSystem.updatePlayerHighlights(player, char, gunPos, distance)
        end
    end

    for player, highlights in pairs(State.playerHighlights) do
        if not activePlayers[player] then
            for _, highlight in pairs(highlights) do
                if highlight then
                    highlight:Destroy()
                end
            end
            State.playerHighlights[player] = nil
        end
    end

    State.frameCount = State.frameCount + 1
end

local NetworkMonitor = {}

function NetworkMonitor.update()
    local ping = 0.0

    if LocalPlayer.GetNetworkPing then
        local success, result = pcall(function()
            return LocalPlayer:GetNetworkPing() * 1000.0
        end)
        if success and result then
            ping = result
        end
    end

    if ping > 0.0 and ping < 1000.0 then
        table.insert(State.pingHistory, {
            value = ping,
            timestamp = tick()
        })

        if #State.pingHistory > 20 then
            table.remove(State.pingHistory, 1)
        end

        local totalWeight = 0.0
        local weightedSum = 0.0

        for i = 1, #State.pingHistory do
            local weight = i / #State.pingHistory
            totalWeight = totalWeight + weight
            weightedSum = weightedSum + (State.pingHistory[i].value * weight)
        end

        State.averagePing = weightedSum / totalWeight
    end
end

local CleanupSystem = {}

function CleanupSystem.run()
    local currentTime = tick()

    if currentTime - State.lastCacheCleanup > CACHE_CLEANUP_INTERVAL then
        VisibilitySystem.cleanupCache()
        VelocityTracker.cleanup()
        State.lastCacheCleanup = currentTime
    end
end

WeaponSystem.update()

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Config.Aimbot.ActivationKey then
        State.isAimbotActive = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Config.Aimbot.ActivationKey then
        State.isAimbotActive = false
    end
end)

if LocalPlayer.Character then
    LocalPlayer.Character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.wait(0.1)
            WeaponSystem.update()
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    WeaponSystem.update()
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.wait(0.1)
            WeaponSystem.update()
        end
    end)
end)

RunService.Heartbeat:Connect(function()
    pcall(ESPSystem.update)
    pcall(NetworkMonitor.update)
    pcall(CleanupSystem.run)
end)

RunService.RenderStepped:Connect(function()
    pcall(AimbotExecutor.execute)
end)
