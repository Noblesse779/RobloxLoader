-- Server-authoritative player settings.
-- Never let a LocalScript set Humanoid.WalkSpeed directly -- a modified client could
-- send anything. The client only *requests* a value here; the server clamps and applies it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local MIN_WALK_SPEED = 8
local MAX_WALK_SPEED = 50

local setWalkSpeed = Remotes.getOrCreate("SetWalkSpeed")

setWalkSpeed.OnServerEvent:Connect(function(player, requestedSpeed)
	if typeof(requestedSpeed) ~= "number" then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = math.clamp(requestedSpeed, MIN_WALK_SPEED, MAX_WALK_SPEED)
end)
