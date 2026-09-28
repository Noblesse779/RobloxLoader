-- Authoritative combat validation for the lock-on system.
-- The client only tells the server *who it wants to attack*; every check that decides
-- whether the attack actually lands (range, line of sight, cooldown) happens here.
-- This is what keeps the lock-on assist fair -- a modified client can request an attack
-- on anyone, but the server will simply ignore it if the request doesn't check out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local attackRequest = Remotes.getOrCreate("AttackRequest")
local lastAttack = {}

local function getHRP(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

attackRequest.OnServerEvent:Connect(function(attacker, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == attacker then
		return
	end

	local now = os.clock()
	if lastAttack[attacker.UserId] and now - lastAttack[attacker.UserId] < CombatConfig.AttackCooldown then
		return
	end

	local attackerHRP = getHRP(attacker)
	local targetHRP = getHRP(target)
	local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")

	if not (attackerHRP and targetHRP and targetHumanoid) or targetHumanoid.Health <= 0 then
		return
	end

	local offset = targetHRP.Position - attackerHRP.Position
	if offset.Magnitude > CombatConfig.MaxAttackRange then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { attacker.Character, target.Character }
	if workspace:Raycast(attackerHRP.Position, offset, raycastParams) then
		return -- something is blocking line of sight
	end

	lastAttack[attacker.UserId] = now
	targetHumanoid:TakeDamage(CombatConfig.AttackDamage)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttack[player.UserId] = nil
end)
