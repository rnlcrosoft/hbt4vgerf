local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if character.Parent and humanoid.Health > 0 then
			humanoid.UseJumpPower = true
			humanoid.JumpPower = 50
		else
			if connection then 
				connection:Disconnect() 
			end
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)