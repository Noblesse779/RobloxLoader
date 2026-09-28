-- Client-side lock-on assist: every player gets the same targeting helper.
-- Tab cycles the nearest players in range; a marker shows who's targeted; clicking
-- fires an attack *request*. The server (CombatServer.server.lua) decides if it lands.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local attackRequest = Remotes.wait("AttackRequest")
local localPlayer = Players.LocalPlayer

local lockedTarget = nil
local marker = nil

local function getHRP(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function createMarker()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LockOnMarker"
	billboard.Size = UDim2.new(0, 50, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Text = "v"
	icon.TextColor3 = Color3.fromRGB(255, 90, 90)
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold
	icon.Parent = billboard

	return billboard
end

local function clearTarget()
	if marker then
		marker:Destroy()
		marker = nil
	end
	lockedTarget = nil
end

local function cycleTarget()
	local myHRP = getHRP(localPlayer)
	if not myHRP then
		return
	end

	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			local hrp = getHRP(player)
			if hrp then
				local distance = (hrp.Position - myHRP.Position).Magnitude
				if distance <= CombatConfig.MaxLockOnDistance then
					table.insert(candidates, { player = player, hrp = hrp, distance = distance })
				end
			end
		end
	end

	if #candidates == 0 then
		clearTarget()
		return
	end

	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	local currentIndex = 0
	for i, candidate in ipairs(candidates) do
		if candidate.player == lockedTarget then
			currentIndex = i
			break
		end
	end

	local nextCandidate = candidates[(currentIndex % #candidates) + 1]
	clearTarget()
	lockedTarget = nextCandidate.player
	marker = createMarker()
	marker.Parent = nextCandidate.hrp
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab then
		cycleTarget()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and lockedTarget then
		attackRequest:FireServer(lockedTarget)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if player == lockedTarget then
		clearTarget()
	end
end)

RunService.RenderStepped:Connect(function()
	if not lockedTarget then
		return
	end
	local hrp = getHRP(lockedTarget)
	local myHRP = getHRP(localPlayer)
	if not hrp or not myHRP or (hrp.Position - myHRP.Position).Magnitude > CombatConfig.MaxLockOnDistance then
		clearTarget()
	end
end)
