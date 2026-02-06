local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
	SitWalk = true,
	CustomAnimation = true,
	CustomAnimationId = "rbxassetid://73753845465382"
}

local customAnimTrack

local function isR15(character)
	local humanoid = character:FindFirstChildOfClass('Humanoid')
	if humanoid then
		return humanoid.RigType == Enum.HumanoidRigType.R15
	end
	return false
end

-- SitWalk Functions
local function enableSitWalk(character)
	task.wait(0.1)

	local anims = character:WaitForChild("Animate", 5)
	if not anims then
		return
	end

	local sitFolder = anims:WaitForChild("sit", 5)
	if not sitFolder then
		return
	end

	local sitAnim = sitFolder:FindFirstChildOfClass("Animation")
	if not sitAnim then
		return
	end

	local sit = sitAnim.AnimationId

	local idle = anims:FindFirstChild("idle")
	local walk = anims:FindFirstChild("walk")
	local run = anims:FindFirstChild("run")
	local jump = anims:FindFirstChild("jump")

	if idle then
		local idleAnim = idle:FindFirstChildOfClass("Animation")
		if idleAnim then idleAnim.AnimationId = sit end
	end
	if walk then
		local walkAnim = walk:FindFirstChildOfClass("Animation")
		if walkAnim then walkAnim.AnimationId = sit end
	end
	if run then
		local runAnim = run:FindFirstChildOfClass("Animation")
		if runAnim then runAnim.AnimationId = sit end
	end
	if jump then
		local jumpAnim = jump:FindFirstChildOfClass("Animation")
		if jumpAnim then jumpAnim.AnimationId = sit end
	end

	local humanoid = character:FindFirstChildOfClass('Humanoid')
	if humanoid then
		if isR15(character) then
			humanoid.HipHeight = 0.5
		else
			humanoid.HipHeight = -1.5
		end
	end
end

local function applyCustomAnimation(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = CONFIG.CustomAnimationId

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	if customAnimTrack then
		customAnimTrack:Stop()
	end

	customAnimTrack = animator:LoadAnimation(animation)
	customAnimTrack.Looped = true
	customAnimTrack.Priority = Enum.AnimationPriority.Action
	customAnimTrack:Play()
end

-- Setup
local function setupCharacter(character)
	if not character:FindFirstChildOfClass("Humanoid") then
		character:WaitForChild("Humanoid", 10)
	end

	if CONFIG.SitWalk then
		task.spawn(function()
			enableSitWalk(character)
		end)
	end

	if CONFIG.CustomAnimation then
		task.spawn(function()
			applyCustomAnimation(character)
		end)
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

_G.ToggleCustomAnimation = function()
	CONFIG.CustomAnimation = not CONFIG.CustomAnimation
	if CONFIG.CustomAnimation then
		if LocalPlayer.Character then
			applyCustomAnimation(LocalPlayer.Character)
		end
	else
		if customAnimTrack then
			customAnimTrack:Stop()
		end
	end
end

_G.SetCustomAnimationId = function(animId)
	CONFIG.CustomAnimationId = animId
	if CONFIG.CustomAnimation and LocalPlayer.Character then
		applyCustomAnimation(LocalPlayer.Character)
	end
end