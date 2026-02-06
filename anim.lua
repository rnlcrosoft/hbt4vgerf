local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
  InfJump = true,
  SitWalk = true,
  TPWalk = true,
  TPWalkSpeed = 1,
  CustomAnimation = true,
  CustomAnimationId = "rbxassetid://73753845465382"
}

local infJumpConnection
local tpwalkRunning = false
local tpwalkConnection
local customAnimTrack

local function isR15(character)
  local humanoid = character:FindFirstChildOfClass('Humanoid')
  if humanoid then
    return humanoid.RigType == Enum.HumanoidRigType.R15
  end
  return false
end

local function enableInfJump()
  if infJumpConnection then
    infJumpConnection:Disconnect()
  end
  
  infJumpConnection = UserInputService.JumpRequest:Connect(function()
    local character = LocalPlayer.Character
    if character then
      local humanoid = character:FindFirstChildOfClass("Humanoid")
      if humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
      end
    end
  end)
end

local function disableInfJump()
  if infJumpConnection then
    infJumpConnection:Disconnect()
    infJumpConnection = nil
  end
end

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

local function setupCharacter(character)
  if not character:FindFirstChildOfClass("Humanoid") then
    character:WaitForChild("Humanoid", 10)
  end
  
  if CONFIG.InfJump then
    enableInfJump()
  end
  
  if CONFIG.SitWalk then
    task.spawn(function()
      enableSitWalk(character)
    end)
  end
  
  if CONFIG.TPWalk then
    enableTPWalk(character)
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

_G.ToggleInfJump = function()
  CONFIG.InfJump = not CONFIG.InfJump
  if CONFIG.InfJump then
    enableInfJump()
  else
    disableInfJump()
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