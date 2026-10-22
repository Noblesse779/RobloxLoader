--[[
	Run : ควบคุมการเล่น 1 รอบ (ทีมเดียวต่อเซิร์ฟเวอร์)
	ด่าน 1 -> 2 -> 3 -> 4 -> หน้าจบ(5)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HorrorShared"):WaitForChild("Config"))
local MapBuilder = require(script.Parent.MapBuilder)
local Ghosts = require(script.Parent.Ghosts)
local Remotes = require(script.Parent.Remotes)

local Run = {
	Active = false,
	Finished = false,
	Stage = 0,
	Id = 0,
	Players = {}, -- [player] = true
	PartySize = 1,
	StartTime = 0,
	Objective = "",
	Advancing = false,
	IsGameServer = false,
}

local Map
local RED = Color3.fromRGB(255, 70, 70)
local GREEN = Color3.fromRGB(110, 255, 130)
local GOLD = Color3.fromRGB(255, 215, 90)

-- ================= Utilities =================

local function runPlayers()
	local list = {}
	for p in pairs(Run.Players) do
		if p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function notifyAll(msg, color)
	for _, p in ipairs(runPlayers()) do
		Remotes.Notify:FireClient(p, msg, color)
	end
end

local function soundAll(name)
	for _, p in ipairs(runPlayers()) do
		Remotes.PlaySound:FireClient(p, name)
	end
end

local function setObjective(text)
	Run.Objective = text
	for _, p in ipairs(runPlayers()) do
		Remotes.Objective:FireClient(p, text)
	end
end

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then
			return p
		end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function shuffle(t)
	local c = table.clone(t)
	for i = #c, 2, -1 do
		local j = math.random(i)
		c[i], c[j] = c[j], c[i]
	end
	return c
end

local function ghostCount(cfg)
	return cfg.Count + math.floor((Run.PartySize - 1) / cfg.ExtraPer)
end

local function spawnCFrame(stage, index)
	local base = Map.Stages[stage].Spawn.CFrame
	local i = (index or 1) - 1
	return base * CFrame.new(((i % 3) - 1) * 4, 0, -math.floor(i / 3) * 4)
end

local function teleportPlayer(p, stage, index)
	local char = p.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char:PivotTo(spawnCFrame(stage, index))
	end
end

local function indexOf(p)
	local i = 0
	for _, other in ipairs(runPlayers()) do
		i += 1
		if other == p then
			return i
		end
	end
	return 1
end

-- ช่วยให้โค้ดที่หน่วงเวลาไว้ไม่ทำงานถ้ารอบ/ด่านเปลี่ยนไปแล้ว
local function stillValid(id, stage)
	return Run.Active and Run.Id == id and Run.Stage == stage
end

-- ================= อาวุธ (ด่าน 3) =================

local function makeWeapon()
	local tool = Instance.new("Tool")
	tool.Name = Config.Weapon.Name
	tool.CanBeDropped = false
	tool.ToolTip = "คลิกเพื่อขับไล่ผี"
	tool:SetAttribute("HorrorWeapon", true)
	tool.Grip = CFrame.new(0, -0.6, 0)

	local gold = Color3.fromRGB(255, 210, 90)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 3, 0.4)
	handle.Color = gold
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local bar = Instance.new("Part")
	bar.Name = "Bar"
	bar.Size = Vector3.new(1.8, 0.4, 0.4)
	bar.Color = gold
	bar.Material = Enum.Material.Metal
	bar.CanCollide = false
	bar.Massless = true
	bar.CFrame = handle.CFrame * CFrame.new(0, 0.7, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = bar
	weld.Parent = handle
	bar.Parent = tool
	local l = Instance.new("PointLight")
	l.Color = gold
	l.Range = 8
	l.Brightness = 1
	l.Parent = handle

	local last = 0
	tool.Activated:Connect(function()
		if os.clock() - last < Config.Weapon.Cooldown then
			return
		end
		last = os.clock()
		local char = tool.Parent
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		-- แสงศักดิ์สิทธิ์
		local burst = Instance.new("Part")
		burst.Shape = Enum.PartType.Ball
		burst.Size = Vector3.new(2, 2, 2)
		burst.Color = gold
		burst.Material = Enum.Material.Neon
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.Transparency = 0.3
		burst.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 5)
		burst.Parent = workspace
		TweenService:Create(burst, TweenInfo.new(0.35), { Size = Vector3.new(14, 14, 14), Transparency = 1 }):Play()
		Debris:AddItem(burst, 0.4)

		for _, g in ipairs(Ghosts.inRange(3, root.Position, Config.Weapon.Range)) do
			local to = g.pos - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude < 5 or root.CFrame.LookVector:Dot(flat.Unit) > 0.2 then
				Ghosts.damage(g, Config.Weapon.Damage)
			end
		end
	end)
	return tool
end

local function applyLoadout(p)
	local wantWeapon = Run.Players[p] == true and Run.Stage == 3
	local backpack = p:FindFirstChildOfClass("Backpack")
	local existing = {}
	for _, container in ipairs({ backpack, p.Character }) do
		if container then
			for _, c in ipairs(container:GetChildren()) do
				if c:IsA("Tool") and c:GetAttribute("HorrorWeapon") then
					table.insert(existing, c)
				end
			end
		end
	end
	if wantWeapon then
		if #existing == 0 and backpack then
			makeWeapon().Parent = backpack
		end
	else
		for _, t in ipairs(existing) do
			t:Destroy()
		end
	end
end

-- ================= การตั้งค่าแต่ละด่าน =================

local setup, cleanup = {}, {}

local function spawnChasers(stage, cfg, id)
	local s = Map.Stages[stage]
	task.delay(Config.Ghosts.SpawnDelay, function()
		if not stillValid(id, stage) then
			return
		end
		for i = 1, ghostCount(cfg) do
			Ghosts.spawn({
				position = s.GhostSpawns[((i - 1) % #s.GhostSpawns) + 1],
				stage = stage,
				speed = cfg.Speed,
				damage = cfg.Damage,
				detectRange = cfg.DetectRange,
				patrolPoints = s.Patrol,
				name = "Ghost",
			})
		end
		notifyAll("ได้ยินเสียงอะไรบางอย่าง... มันกำลังมา", RED)
		soundAll("Whisper")
	end)
end

-- ----- ด่าน 1 -----
setup[1] = function()
	Run.Triggered = {}
	MapBuilder.setPortal(Map.Stages[1].Portal, true)
	Run.Objective = Config.Stages[1].Objective
end

-- ----- ด่าน 2 -----
setup[2] = function(id)
	local s = Map.Stages[2]
	Run.HasKey = false
	s.Door.close()
	MapBuilder.setPortal(s.Portal, false)

	local spot = s.KeySpots[math.random(#s.KeySpots)]
	local key, prompt = MapBuilder.makePickup(s.Dynamic, spot, "Key")
	prompt.Triggered:Connect(function(p)
		if not Run.Players[p] or Run.HasKey or not stillValid(id, 2) then
			return
		end
		Run.HasKey = true
		key:Destroy()
		soundAll("Pickup")
		notifyAll(p.DisplayName .. " เจอกุญแจแล้ว! รีบไปที่ประตูทางออกทางทิศเหนือ", GOLD)
		setObjective("นำกุญแจไปไขประตูทางออก (สุดทางทิศเหนือ)")
		-- ผีโกรธ วิ่งเร็วขึ้น
		for _, g in ipairs(Ghosts.forStage(2)) do
			g.speed += 2
			g.detect += 40
		end
		Remotes.Jumpscare:FireClient(p, "Whisper")
	end)

	spawnChasers(2, Config.Ghosts.Stage2, id)
	Run.Objective = Config.Stages[2].Objective
end

-- ----- ด่าน 3 -----
local function spawnStage3Ghost(id, index)
	local s = Map.Stages[3]
	local cfg = Config.Ghosts.Stage3
	Ghosts.spawn({
		position = s.GhostSpawns[((index - 1) % #s.GhostSpawns) + 1],
		stage = 3,
		speed = cfg.Speed,
		damage = cfg.Damage,
		detectRange = cfg.DetectRange,
		health = cfg.Health,
		patrolPoints = s.Patrol,
		name = "Ghost",
		onDeath = function()
			if not stillValid(id, 3) or Run.BossDead then
				return
			end
			task.delay(cfg.RespawnDelay, function()
				if stillValid(id, 3) and not Run.BossDead then
					spawnStage3Ghost(id, math.random(#s.GhostSpawns))
				end
			end)
		end,
	})
end

local function updateCandleObjective()
	local total = Config.Quest.Candles
	if Run.CandlesPlaced >= total then
		return
	end
	setObjective(string.format("เทียนวิญญาณ: เก็บแล้ว %d  |  วางแล้ว %d/%d  (นำไปวางที่แท่นบูชา)", Run.CandlesFound, Run.CandlesPlaced, total))
end

setup[3] = function(id)
	local s = Map.Stages[3]
	Run.CandlesFound, Run.CandlesHeld, Run.CandlesPlaced = 0, 0, 0
	Run.BossSpawned, Run.BossDead = false, false
	for k = 1, Config.Quest.Candles do
		s.SetSlotLit(k, false)
	end
	s.AltarPrompt.Enabled = true
	MapBuilder.setPortal(s.Portal, false)

	local spots = shuffle(s.CandleSpots)
	for i = 1, math.min(Config.Quest.Candles, #spots) do
		local candle, prompt = MapBuilder.makePickup(s.Dynamic, spots[i], "Candle")
		prompt.Triggered:Connect(function(p)
			if not Run.Players[p] or not candle.Parent or not stillValid(id, 3) then
				return
			end
			candle:Destroy()
			Run.CandlesFound += 1
			Run.CandlesHeld += 1
			soundAll("Pickup")
			notifyAll(p.DisplayName .. " เก็บเทียนวิญญาณได้ (" .. Run.CandlesFound .. "/" .. Config.Quest.Candles .. ")", Color3.fromRGB(140, 210, 255))
			updateCandleObjective()
		end)
	end

	task.delay(Config.Ghosts.SpawnDelay, function()
		if not stillValid(id, 3) then
			return
		end
		for i = 1, ghostCount(Config.Ghosts.Stage3) do
			spawnStage3Ghost(id, i)
		end
		notifyAll("วิญญาณร้ายตื่นแล้ว! ใช้ไม้กางเขน (คลิก) ขับไล่มัน", RED)
	end)

	Run.Objective = string.format("เก็บเทียนวิญญาณ %d เล่ม แล้วนำไปวางที่แท่นบูชากลางสุสาน", Config.Quest.Candles)
end

local function onAltar(p)
	local s = Map.Stages[3]
	if not Run.Players[p] or Run.Stage ~= 3 or Run.BossSpawned then
		return
	end
	if Run.CandlesHeld <= 0 then
		Remotes.Notify:FireClient(p, "ยังไม่มีเทียนวิญญาณ... ไปหามาก่อน", RED)
		return
	end
	for _ = 1, Run.CandlesHeld do
		Run.CandlesPlaced += 1
		s.SetSlotLit(Run.CandlesPlaced, true)
	end
	Run.CandlesHeld = 0
	updateCandleObjective()

	if Run.CandlesPlaced < Config.Quest.Candles then
		notifyAll("วางเทียนแล้ว " .. Run.CandlesPlaced .. "/" .. Config.Quest.Candles, Color3.fromRGB(140, 210, 255))
		return
	end

	-- ครบแล้ว => บอสเกิด
	Run.BossSpawned = true
	s.AltarPrompt.Enabled = false
	local id = Run.Id
	for _, other in ipairs(runPlayers()) do
		Remotes.Jumpscare:FireClient(other, "Face")
	end
	notifyAll("พิธีกรรมสำเร็จ... แต่ผีเจ้าที่ตื่นขึ้นมาแล้ว!! สู้กับมัน!", RED)
	setObjective("ปราบผีเจ้าที่ให้ได้!")
	local cfg = Config.Ghosts.Boss
	Ghosts.spawn({
		position = s.BossSpawn,
		stage = 3,
		scale = cfg.Scale,
		speed = cfg.Speed,
		damage = cfg.Damage,
		detectRange = cfg.DetectRange,
		health = cfg.Health + cfg.HealthPerPlayer * (Run.PartySize - 1),
		patrolPoints = s.Patrol,
		color = Color3.fromRGB(200, 170, 170),
		name = "BossGhost",
		onDeath = function()
			if not stillValid(id, 3) then
				return
			end
			Run.BossDead = true
			Ghosts.clearStage(3)
			MapBuilder.setPortal(s.Portal, true)
			soundAll("Portal")
			notifyAll("ปราบผีเจ้าที่ได้แล้ว! ประตูวาปเปิดทางทิศเหนือ", GREEN)
			setObjective("ไปที่ประตูวาปทางทิศเหนือของสุสาน")
		end,
	})
end

-- ----- ด่าน 4 -----
local function updateFuseObjective()
	setObjective(string.format("ฟิวส์: เก็บแล้ว %d  |  ใส่แล้ว %d/%d  (เครื่องปั่นไฟอยู่ที่จุดเริ่มต้น)", Run.FusesFound, Run.FusesPlaced, Config.Quest.Fuses))
end

setup[4] = function(id)
	local s = Map.Stages[4]
	Run.FusesFound, Run.FusesHeld, Run.FusesPlaced = 0, 0, 0
	Run.Powered = false
	Run.Triggered = {}
	s.Door.close()
	s.SetPowered(false)
	for k = 1, Config.Quest.Fuses do
		s.SetFuseSlot(k, false)
	end
	s.GeneratorPrompt.Enabled = true
	MapBuilder.setPortal(s.Portal, false)

	local spots = shuffle(s.FuseSpots)
	for i = 1, math.min(Config.Quest.Fuses, #spots) do
		local fuse, prompt = MapBuilder.makePickup(s.Dynamic, spots[i], "Fuse")
		prompt.Triggered:Connect(function(p)
			if not Run.Players[p] or not fuse.Parent or not stillValid(id, 4) then
				return
			end
			fuse:Destroy()
			Run.FusesFound += 1
			Run.FusesHeld += 1
			soundAll("Pickup")
			notifyAll(p.DisplayName .. " เจอฟิวส์! (" .. Run.FusesFound .. "/" .. Config.Quest.Fuses .. ")", GREEN)
			updateFuseObjective()
			-- เก็บของแล้วโดนตุ้งแช่บ้าง
			if math.random() < 0.5 then
				Remotes.Jumpscare:FireClient(p, "Behind")
			end
		end)
	end

	spawnChasers(4, Config.Ghosts.Stage4, id)
	Run.Objective = string.format("หาฟิวส์ %d อัน มาใส่เครื่องปั่นไฟที่จุดเริ่มต้น แล้วหนีออกไป", Config.Quest.Fuses)
end

local function onGenerator(p)
	local s = Map.Stages[4]
	if not Run.Players[p] or Run.Stage ~= 4 or Run.Powered then
		return
	end
	if Run.FusesHeld <= 0 then
		Remotes.Notify:FireClient(p, "ยังไม่มีฟิวส์... ไปหาในตึกก่อน", RED)
		return
	end
	for _ = 1, Run.FusesHeld do
		Run.FusesPlaced += 1
		s.SetFuseSlot(Run.FusesPlaced, true)
	end
	Run.FusesHeld = 0
	if Run.FusesPlaced < Config.Quest.Fuses then
		updateFuseObjective()
		notifyAll("ใส่ฟิวส์แล้ว " .. Run.FusesPlaced .. "/" .. Config.Quest.Fuses, GREEN)
		return
	end

	Run.Powered = true
	s.GeneratorPrompt.Enabled = false
	s.SetPowered(true)
	s.Door.open()
	MapBuilder.setPortal(s.Portal, true)
	soundAll("Door")
	for _, other in ipairs(runPlayers()) do
		Remotes.Jumpscare:FireClient(other, "Rush")
	end
	for _, g in ipairs(Ghosts.forStage(4)) do
		g.speed = Config.Ghosts.Stage4.RageSpeed
		g.detect = 999
	end
	notifyAll("ไฟมาแล้ว! ประตูทางออกเปิดแล้ว วิ่งไปทางทิศเหนือ!! ผีคลั่งแล้ว!", RED)
	setObjective("วิ่งไปที่ประตูทางออกทางทิศเหนือ แล้วเข้าประตูวาป!")
end

-- ----- หน้าจบ -----
setup[5] = function()
	Run.Finished = true
	Run.Objective = Config.Stages[5].Objective
	local elapsed = os.clock() - Run.StartTime
	task.delay(1.5, function()
		for _, p in ipairs(runPlayers()) do
			Remotes.GameEnded:FireClient(p, elapsed, Run.IsGameServer and not RunService:IsStudio())
		end
	end)
end

cleanup[2] = function()
	Map.Stages[2].Dynamic:ClearAllChildren()
end
cleanup[3] = function()
	Map.Stages[3].Dynamic:ClearAllChildren()
end
cleanup[4] = function()
	Map.Stages[4].Dynamic:ClearAllChildren()
end

-- ================= Flow =================

local function enterStage(stage)
	local prev = Run.Stage
	Run.Stage = stage
	if prev >= 1 then
		Ghosts.clearStage(prev)
		if cleanup[prev] then
			cleanup[prev]()
		end
	end
	setup[stage](Run.Id)
	for i, p in ipairs(runPlayers()) do
		p:SetAttribute("Stage", stage)
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = hum.MaxHealth
		end
		teleportPlayer(p, stage, i)
		applyLoadout(p)
		Remotes.StageChanged:FireClient(p, stage, Config.Stages[stage].Name, Run.Objective)
	end
end

function Run.start(players)
	if Run.Active or #players == 0 then
		return false
	end
	Run.Active = true
	Run.Finished = false
	Run.Advancing = false
	Run.Id += 1
	Run.Stage = 0
	Run.Players = {}
	Run.PartySize = #players
	Run.StartTime = os.clock()
	for _, p in ipairs(players) do
		Run.Players[p] = true
		p:SetAttribute("InRun", true)
		Remotes.Transition:FireClient(p)
	end
	task.wait(0.8)
	enterStage(1)
	return true
end

function Run.addPlayer(p)
	if not Run.Active or Run.Players[p] then
		return
	end
	Run.Players[p] = true
	p:SetAttribute("InRun", true)
	p:SetAttribute("Stage", Run.Stage)
	teleportPlayer(p, Run.Stage, indexOf(p))
	applyLoadout(p)
	Remotes.StageChanged:FireClient(p, Run.Stage, Config.Stages[Run.Stage].Name, Run.Objective)
end

function Run.reset()
	Run.Id += 1
	for stage = 1, 4 do
		Ghosts.clearStage(stage)
		if cleanup[stage] then
			cleanup[stage]()
		end
	end
	Map.Stages[2].Door.close()
	Map.Stages[4].Door.close()
	Map.Stages[4].SetPowered(false)
	for stage = 2, 4 do
		MapBuilder.setPortal(Map.Stages[stage].Portal, false)
	end
	MapBuilder.setPortal(Map.Stages[1].Portal, true)
	for p in pairs(Run.Players) do
		p:SetAttribute("InRun", nil)
		p:SetAttribute("Stage", nil)
	end
	Run.Players = {}
	Run.Active = false
	Run.Finished = false
	Run.Stage = 0
	Run.Advancing = false
end

local function sendToLobby(p)
	Run.Players[p] = nil
	p:SetAttribute("InRun", nil)
	p:SetAttribute("Stage", nil)
	applyLoadout(p)
	local char = p.Character
	if char then
		char:PivotTo(Map.Lobby.Spawn.CFrame + Vector3.new(math.random(-3, 3), 4, math.random(-3, 3)))
	end
	Remotes.StageChanged:FireClient(p, 0, "ล็อบบี้", "")
	if #runPlayers() == 0 then
		Run.reset()
	end
end

-- ================= Init =================

local function onCharacter(p, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local head = char:WaitForChild("Head", 10)
	if not hum or not head then
		return
	end
	hum.WalkSpeed = Config.WalkSpeed

	local flash = Instance.new("SpotLight")
	flash.Name = "Flashlight"
	flash.Range = 55
	flash.Angle = 50
	flash.Brightness = 2.5
	flash.Color = Color3.fromRGB(255, 244, 214)
	flash.Shadows = true
	flash.Face = Enum.NormalId.Front
	flash.Parent = head

	hum.Died:Connect(function()
		if Run.Players[p] and Run.Active and not Run.Finished then
			notifyAll(p.DisplayName .. " ถูกผีจับได้แล้ว...", RED)
		end
	end)

	if Run.Players[p] and Run.Stage >= 1 then
		task.delay(0.15, function()
			if Run.Players[p] and p.Character == char then
				teleportPlayer(p, Run.Stage, indexOf(p))
				applyLoadout(p)
			end
		end)
	end
end

function Run.init(map, isGameServer)
	Map = map
	Run.IsGameServer = isGameServer

	Ghosts.onPlayerHit = function(p)
		Remotes.Jumpscare:FireClient(p, "Hit")
	end

	-- ประตูวาปทุกด่าน
	for stage = 1, 4 do
		local core = Map.Stages[stage].Portal
		core.Touched:Connect(function(hit)
			local p = playerFromHit(hit)
			if not p or not Run.Players[p] or not Run.Active then
				return
			end
			if Run.Stage ~= stage or not core:GetAttribute("Active") or Run.Advancing then
				return
			end
			Run.Advancing = true
			local id = Run.Id
			notifyAll(p.DisplayName .. " เข้าประตูวาป! กำลังวาปทั้งทีม...", Color3.fromRGB(200, 140, 255))
			for _, other in ipairs(runPlayers()) do
				Remotes.Transition:FireClient(other)
				Remotes.PlaySound:FireClient(other, "Portal")
			end
			task.delay(0.8, function()
				if Run.Active and Run.Id == id and Run.Stage == stage then
					enterStage(stage + 1)
				end
				Run.Advancing = false
			end)
		end)
	end

	-- จุดตุ้งแช่ (ด่าน 1 และ 4)
	for _, stage in ipairs({ 1, 4 }) do
		for _, trig in ipairs(Map.Stages[stage].Triggers) do
			trig.Touched:Connect(function(hit)
				local p = playerFromHit(hit)
				if not p or not Run.Players[p] or p:GetAttribute("Stage") ~= stage then
					return
				end
				Run.Triggered = Run.Triggered or {}
				Run.Triggered[trig] = Run.Triggered[trig] or {}
				if Run.Triggered[trig][p] then
					return
				end
				Run.Triggered[trig][p] = true
				Remotes.Jumpscare:FireClient(p, trig:GetAttribute("ScareType"))
			end)
		end
	end

	-- ประตูด่าน 2
	local s2 = Map.Stages[2]
	s2.Door.Prompt.Triggered:Connect(function(p)
		if not Run.Players[p] or Run.Stage ~= 2 or s2.Door.IsOpen then
			return
		end
		if not Run.HasKey then
			Remotes.Notify:FireClient(p, "ประตูล็อกอยู่... ต้องหากุญแจก่อน", RED)
			return
		end
		s2.Door.open()
		MapBuilder.setPortal(s2.Portal, true)
		soundAll("Door")
		notifyAll(p.DisplayName .. " ไขประตูแล้ว! รีบเข้าประตูวาป!", GREEN)
		setObjective("เข้าประตูวาปหลังประตูทางออก")
	end)

	-- ประตูด่าน 4 (เปิดเองเมื่อไฟมา)
	Map.Stages[4].Door.Prompt.Triggered:Connect(function(p)
		if Run.Players[p] and Run.Stage == 4 and not Run.Powered then
			Remotes.Notify:FireClient(p, "ประตูไฟฟ้าไม่ทำงาน... ต้องใส่ฟิวส์ให้เครื่องปั่นไฟก่อน", RED)
		end
	end)

	Map.Stages[3].AltarPrompt.Triggered:Connect(onAltar)
	Map.Stages[4].GeneratorPrompt.Triggered:Connect(onGenerator)

	-- ไฟฉาย
	Remotes.Flashlight.OnServerEvent:Connect(function(p, on)
		local head = p.Character and p.Character:FindFirstChild("Head")
		local flash = head and head:FindFirstChild("Flashlight")
		if flash then
			flash.Enabled = on == true
		end
	end)

	-- กลับล็อบบี้หลังจบเกม
	Remotes.ReturnToLobby.OnServerEvent:Connect(function(p)
		if not Run.Players[p] or not Run.Finished then
			return
		end
		if Run.IsGameServer and not RunService:IsStudio() then
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { p })
			end)
			if ok then
				return
			end
			warn("[Run] Teleport to lobby failed: " .. tostring(err))
		end
		sendToLobby(p)
	end)

	local function hookPlayer(p)
		p.CharacterAdded:Connect(function(char)
			onCharacter(p, char)
		end)
		if p.Character then
			task.spawn(onCharacter, p, p.Character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end

	Players.PlayerRemoving:Connect(function(p)
		if Run.Players[p] then
			Run.Players[p] = nil
			if Run.Active and #runPlayers() == 0 then
				Run.reset()
			end
		end
	end)
end

return Run
