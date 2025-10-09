-- Invisible toggle (safe, still works with voice chat)
-- Press F to toggle invisible / visible

local player = game.Players.LocalPlayer
local UIS = game:GetService("UserInputService")
local invisible = false

function setTransparency(val)
	local character = player.Character
	if not character then return end

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = val
		end
	end
end

function removeExtras()
	local character = player.Character
	if not character then return end

	for _, obj in pairs(character:GetChildren()) do
		if obj:IsA("Clothing") or obj:IsA("ShirtGraphic") then
			obj:Destroy()
		end
	end

	if character:FindFirstChild("Head") then
		for _, v in pairs(character.Head:GetChildren()) do
			if v:IsA("Decal") then
				v:Destroy()
			end
		end
	end
end

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F then
		invisible = not invisible
		if invisible then
			removeExtras()
			setTransparency(1)
			print("✅ หายตัวแล้ว (ยังพูดได้)")
		else
			setTransparency(0)
			print("👁 กลับมามองเห็นอีกครั้ง")
		end
	end
end)
