--[[
	Ghosts : AI ผี (ลอยได้, ไล่ตามผู้เล่นด้วย Pathfinding, ทำดาเมจเมื่อเข้าใกล้)
	ผีทุกตัวอยู่ใน workspace.HorrorGhosts (ไคลเอนต์ใช้เช็คระยะเพื่อเล่นเสียงหัวใจ)
]]

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GhostModel = require(ReplicatedStorage:WaitForChild("HorrorShared"):WaitForChild("GhostModel"))

local Ghosts = {}
Ghosts.list = {}
Ghosts.onPlayerHit = nil -- function(player, ghost)

local ghostFolder = Instance.new("Folder")
ghostFolder.Name = "HorrorGhosts"
ghostFolder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local PATH_INTERVAL = 0.5
local ATTACK_COOLDOWN = 1.2

local function aliveRoot(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root, hum
	end
	return nil
end

local function makeHealthBar(g)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.new(4 * g.scale, 0, 0.45, 0)
	bb.StudsOffset = Vector3.new(0, 5.6 * g.scale, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 80
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
	fill.BorderSizePixel = 0
	fill.Parent = back
	bb.Parent = g.root
	g.healthFill = fill
end

function Ghosts.spawn(opts)
	local scale = opts.scale or 1
	local model = GhostModel.create({ scale = scale, name = opts.name or "Ghost", color = opts.color })
	local hover = 3.5 * scale
	local pos = opts.position + Vector3.new(0, hover, 0)
	model:PivotTo(CFrame.new(pos))
	model:SetAttribute("Stage", opts.stage)

	local g = {
		model = model,
		root = model.PrimaryPart,
		pos = pos,
		look = Vector3.new(0, 0, -1),
		hover = hover,
		scale = scale,
		stage = opts.stage,
		speed = opts.speed or 12,
		damage = opts.damage or 25,
		detect = opts.detectRange or 60,
		patrol = opts.patrolPoints or {},
		onDeath = opts.onDeath,
		waypoints = nil,
		wpIndex = 1,
		computing = false,
		lastCompute = 0,
		hitTimes = {},
		alive = true,
		invulnerable = opts.health == nil,
		bobT = math.random() * 10,
	}
	if opts.health then
		g.health = opts.health
		g.maxHealth = opts.health
		makeHealthBar(g)
	end
	model.Parent = ghostFolder
	table.insert(Ghosts.list, g)
	return g
end

local function computePath(g, goal)
	if g.computing then
		return
	end
	g.computing = true
	g.lastCompute = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = false,
			AgentCanClimb = false,
			WaypointSpacing = 4,
		})
		local start = g.pos - Vector3.new(0, g.hover, 0)
		local ok = pcall(function()
			path:ComputeAsync(start, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			g.waypoints = path:GetWaypoints()
			g.wpIndex = 2
		else
			g.waypoints = nil
		end
		g.computing = false
	end)
end

local function nearestTarget(g)
	local best, bestRoot, bestDist
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRun") and player:GetAttribute("Stage") == g.stage then
			local root = aliveRoot(player)
			if root then
				local d = (root.Position - g.pos).Magnitude
				if d < g.detect and (not bestDist or d < bestDist) then
					best, bestRoot, bestDist = player, root, d
				end
			end
		end
	end
	return best, bestRoot, bestDist
end

local function hasLineOfSight(g, root)
	local filter = { ghostFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filter
	return workspace:Raycast(g.pos, root.Position - g.pos, rayParams) == nil
end

local function step(g, dt)
	local player, root, dist = nearestTarget(g)
	local speed = g.speed
	local goal

	if player then
		if dist < 16 and hasLineOfSight(g, root) then
			-- เห็นตัวแล้ว พุ่งตรงเข้าหา
			goal = root.Position + Vector3.new(0, g.hover - 3, 0)
			g.waypoints = nil
		elseif os.clock() - g.lastCompute > PATH_INTERVAL then
			computePath(g, root.Position - Vector3.new(0, 3, 0))
		end
	else
		speed *= 0.55
		local done = not g.waypoints or g.wpIndex > #g.waypoints
		if done and not g.computing and #g.patrol > 0 and os.clock() - g.lastCompute > 1 then
			computePath(g, g.patrol[math.random(#g.patrol)])
		end
	end

	if not goal and g.waypoints and g.wpIndex <= #g.waypoints then
		goal = g.waypoints[g.wpIndex].Position + Vector3.new(0, g.hover, 0)
		local flat = Vector3.new(goal.X - g.pos.X, 0, goal.Z - g.pos.Z)
		if flat.Magnitude < 1.5 then
			g.wpIndex += 1
		end
	elseif not goal and player then
		-- หาทางไม่ได้ => ลอยทะลุกำแพงเข้าไปเลย (ก็ผีนี่นา)
		goal = root.Position + Vector3.new(0, g.hover - 3, 0)
	end

	if goal then
		local delta = goal - g.pos
		local d = delta.Magnitude
		if d > 0.05 then
			g.pos += delta.Unit * math.min(d, speed * dt)
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 0.1 then
				g.look = flat.Unit
			end
		end
	end

	g.bobT += dt
	local p = g.pos + Vector3.new(0, math.sin(g.bobT * 2.5) * 0.35 * g.scale, 0)
	g.model:PivotTo(CFrame.lookAt(p, p + g.look))

	-- โจมตี
	if player and root then
		if (root.Position - g.pos).Magnitude < 4.5 * g.scale then
			local last = g.hitTimes[player]
			if not last or os.clock() - last > ATTACK_COOLDOWN then
				g.hitTimes[player] = os.clock()
				local _, hum = aliveRoot(player)
				if hum then
					hum:TakeDamage(g.damage)
				end
				if Ghosts.onPlayerHit then
					Ghosts.onPlayerHit(player, g)
				end
			end
		end
	end
end

local function removeFromList(g)
	for i, other in ipairs(Ghosts.list) do
		if other == g then
			table.remove(Ghosts.list, i)
			return
		end
	end
end

function Ghosts.kill(g, silent)
	if not g.alive then
		return
	end
	g.alive = false
	removeFromList(g)
	for _, d in ipairs(g.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	task.delay(0.7, function()
		g.model:Destroy()
	end)
	if g.onDeath and not silent then
		task.spawn(g.onDeath, g)
	end
end

function Ghosts.damage(g, amount)
	if not g.alive or g.invulnerable then
		return
	end
	g.health -= amount
	if g.healthFill then
		g.healthFill.Size = UDim2.fromScale(math.clamp(g.health / g.maxHealth, 0, 1), 1)
	end
	-- กระเด็นถอยหลัง + กะพริบขาว
	g.pos -= g.look * 3
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 240, 180)
	hl.FillTransparency = 0.2
	hl.OutlineTransparency = 1
	hl.Parent = g.model
	TweenService:Create(hl, TweenInfo.new(0.3), { FillTransparency = 1 }):Play()
	task.delay(0.35, function()
		hl:Destroy()
	end)
	if g.health <= 0 then
		Ghosts.kill(g)
	end
end

function Ghosts.inRange(stage, position, range)
	local result = {}
	for _, g in ipairs(Ghosts.list) do
		if g.alive and g.stage == stage and (g.pos - position).Magnitude <= range + 2 * g.scale then
			table.insert(result, g)
		end
	end
	return result
end

function Ghosts.forStage(stage)
	local result = {}
	for _, g in ipairs(Ghosts.list) do
		if g.stage == stage then
			table.insert(result, g)
		end
	end
	return result
end

function Ghosts.clearStage(stage)
	for _, g in ipairs(Ghosts.forStage(stage)) do
		Ghosts.kill(g, true)
	end
end

local warned = false
RunService.Heartbeat:Connect(function(dt)
	for i = #Ghosts.list, 1, -1 do
		local g = Ghosts.list[i]
		if g and g.alive then
			local ok, err = pcall(step, g, dt)
			if not ok and not warned then
				warned = true
				warn("[Ghosts] " .. tostring(err))
			end
		end
	end
end)

return Ghosts
