local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
	TPWalk = true,
	TPWalkSpeed = 1,
	TPJump = true,
	TPJumpSpeed = 50,
}

-- TPWalk Variables
local tpwalkRunning = false
local tpwalkConnection

-- TPJump Variables
local tpJumpHeartbeat
local tpJumpInputBegan
local tpJumpInputEnded
local isJumping = false

-- TPJump Functions
local function disableTPJump()
	if tpJumpHeartbeat then
		tpJumpHeartbeat:Disconnect()
		tpJumpHeartbeat = nil
	end
	if tpJumpInputBegan then
		tpJumpInputBegan:Disconnect()
		tpJumpInputBegan = nil
	end
	if tpJumpInputEnded then
		tpJumpInputEnded:Disconnect()
		tpJumpInputEnded = nil
	end
	isJumping = false
end

local function enableTPJump()
	disableTPJump()

	tpJumpInputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			isJumping = true
		end
	end)

	tpJumpInputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space then
			isJumping = false
		end
	end)

	tpJumpHeartbeat = RunService.Heartbeat:Connect(function(deltaTime)
		local character = LocalPlayer.Character
		if not character then return end

		local rootPart = character:FindFirstChild("HumanoidRootPart")

		if isJumping and rootPart then
			rootPart.CFrame = rootPart.CFrame + Vector3.new(0, CONFIG.TPJumpSpeed * deltaTime, 0)
			local currentVel = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity = Vector3.new(currentVel.X, 0, currentVel.Z)
		end
	end)
end

-- TPWalk Functions
local function enableTPWalk(character)
	if tpwalkConnection then
		tpwalkConnection:Disconnect()
	end

	tpwalkRunning = true
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")

	if not humanoid then
		return
	end

	tpwalkConnection = RunService.Heartbeat:Connect(function(delta)
		if not tpwalkRunning then return end

		local currentChar = LocalPlayer.Character
		local currentHum = currentChar and currentChar:FindFirstChildWhichIsA("Humanoid")

		if not currentChar or not currentHum or currentHum ~= humanoid then
			if tpwalkConnection then
				tpwalkConnection:Disconnect()
			end
			return
		end

		if humanoid.MoveDirection.Magnitude > 0 then
			currentChar:TranslateBy(humanoid.MoveDirection * CONFIG.TPWalkSpeed * delta * 10)
		end
	end)
end

local function disableTPWalk()
	tpwalkRunning = false
	if tpwalkConnection then
		tpwalkConnection:Disconnect()
		tpwalkConnection = nil
	end
end

-- Setup
local function setupCharacter(character)
	if not character:FindFirstChildOfClass("Humanoid") then
		character:WaitForChild("Humanoid", 10)
	end

	if CONFIG.TPJump then
		enableTPJump()
	end

	if CONFIG.TPWalk then
		enableTPWalk(character)
	end
end

local function initialize()
	if LocalPlayer.Character then
		setupCharacter(LocalPlayer.Character)
	end

	LocalPlayer.CharacterAdded:Connect(function(character)
		setupCharacter(character)
	end)
end

initialize()

_G.ToggleTPJump = function()
	CONFIG.TPJump = not CONFIG.TPJump
	if CONFIG.TPJump then
		enableTPJump()
	else
		disableTPJump()
	end
end

_G.ToggleTPWalk = function()
	CONFIG.TPWalk = not CONFIG.TPWalk
	if CONFIG.TPWalk then
		if LocalPlayer.Character then
			enableTPWalk(LocalPlayer.Character)
		end
	else
		disableTPWalk()
	end
end

_G.SetTPWalkSpeed = function(speed)
	CONFIG.TPWalkSpeed = speed
	if CONFIG.TPWalk and LocalPlayer.Character then
		disableTPWalk()
		enableTPWalk(LocalPlayer.Character)
	end
end