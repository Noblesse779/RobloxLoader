--[[
BattleCityServer (Script ใน ServerScriptService)
ตัวเชื่อมระหว่างตัวจำลองเกม (BattleCityCore) กับโลก Roblox
- รับ input จากผู้เล่นผ่าน ReplicatedStorage.BattleCity.Input (RemoteEvent)
- เดินเกมทีละ TICK คงที่ใน Heartbeat แล้ววาดทุกอย่างเป็น Part ใน workspace.BattleCity
- ส่งสถานะ (เฟส, ด่าน, คะแนน, ชีวิต ...) ให้ client ผ่าน Attribute ของ ReplicatedStorage.BattleCity
วางคู่กับ ModuleScript BattleCityCore และ BattleCityStages ใน ServerScriptService
ทุก Part เป็นของประดับล้วน (Anchored, ไม่ชน, ไม่ถูก raycast) เพราะฟิสิกส์ทั้งหมดอยู่ใน Core
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

-- ปิดตัวละครก่อน require (require อาจรอ) ผู้เล่นที่เข้ามาระหว่างนั้นจะได้ไม่เกิดเป็นคน
Players.CharacterAutoLoads = false

local Core = require(script.Parent:WaitForChild("BattleCityCore"))
local Stages = require(script.Parent:WaitForChild("BattleCityStages"))
if type(Stages) ~= "table" then
	Stages = {}
end

-- เสียง: ใส่ id ของเสียงเอง (เช่น "rbxassetid://123" หรือแค่ตัวเลข) ว่างไว้ = ไม่เล่น
local SOUNDS = {
	fire = "", -- ยิงกระสุน
	brick = "", -- กระสุนโดนอิฐ
	steel = "", -- กระสุนโดนเหล็ก/ขอบสนาม
	armor = "", -- ยิงโดนรถถังหุ้มเกราะแต่ยังไม่ตาย
	shield = "", -- กระสุนโดนโล่
	explosion = "", -- รถถังระเบิด
	powerupSpawn = "", -- ไอเทมโผล่
	powerup = "", -- เก็บไอเทม
	extraLife = "", -- ได้ชีวิตเพิ่ม
	baseDestroyed = "", -- นกอินทรีโดนยิง
	playerDied = "", -- ผู้เล่นตาย
	stageStart = "", -- เริ่มด่าน
	gameOver = "", -- เกมจบ
}

---------------------------------------------------------------------------
-- ค่าคงที่การวาด (1 พิกเซล NES = 0.5 stud, มุมสนามอยู่ที่ (0, FLOOR_Y, 0))
---------------------------------------------------------------------------

local STUD = 0.5
local FLOOR_Y = 1
local WALL_H = 6
local TREE_Y = FLOOR_Y + 6.2 -- ป่าอยู่สูงกว่ารถถัง/กระสุน จึงบังจากกล้องด้านบนได้แบบ NES
local BULLET_Y = FLOOR_Y + 2
local POWERUP_Y = FLOOR_Y + 7.5 -- ไอเทมลอยเหนือป่า มองเห็นเสมอ
local EXPLOSION_Y = FLOOR_Y + 3
local SPAWN_Y = FLOOR_Y + 1.5
local FIELD_STUDS = Core.FIELD * STUD -- 104
local GRID_N = Core.GRID_N
local MICRO_STUDS = Core.MICRO * STUD -- 2
local MAX_EFFECTS_PER_FRAME = 24 -- กันเอฟเฟกต์ล้นถ้ามีเหตุการณ์มากผิดปกติ
local BULLET_POOL_MAX = 16
-- ไอคอนบนหน้าบนของ Part: ถ้าใน Studio เห็นไอคอนกลับหัว ให้เปลี่ยนเป็น 180
local TOP_ICON_ROTATION = 0

local CELL = Core.CELL
local EMPTY, BRICK, STEEL, WATER, TREES, ICE, BASE = CELL.EMPTY, CELL.BRICK, CELL.STEEL, CELL.WATER, CELL.TREES, CELL.ICE, CELL.BASE

local floor = math.floor

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local C = {
	floor = rgb(0, 0, 0),
	frame = rgb(116, 116, 116),
	brickA = rgb(168, 72, 24),
	brickB = rgb(140, 56, 16),
	steelA = rgb(204, 204, 204),
	steelB = rgb(180, 180, 180),
	waterA = rgb(40, 80, 216),
	waterB = rgb(72, 120, 248),
	treesA = rgb(40, 132, 40),
	treesB = rgb(24, 104, 32),
	iceA = rgb(222, 236, 252),
	iceB = rgb(196, 216, 240),
	eagle = rgb(236, 188, 56),
	eagleDead = rgb(64, 64, 64),
	bullet = rgb(240, 240, 240),
	shield = rgb(96, 224, 255),
	spawnStar = rgb(200, 232, 255),
	spawnCore = rgb(255, 255, 255),
	explosion = rgb(255, 136, 32),
	explosionCore = rgb(255, 236, 160),
	powerupTile = rgb(236, 236, 236),
	powerupText = rgb(200, 24, 24),
	score = rgb(255, 255, 255),
}

-- สีหลักของรถถังแต่ละแบบ (เขียว/เหลือง/เงิน/เทา ของรถถังหุ้มเกราะไล่ตาม hp)
local TANK_COLORS = {
	p1 = rgb(236, 200, 48),
	p2 = rgb(56, 176, 72),
	enemy = rgb(188, 188, 188),
	red = rgb(216, 40, 16),
	armor4 = rgb(40, 160, 128), -- เขียวอมฟ้า ให้ต่างจากผู้เล่น 2
	armor3 = rgb(224, 192, 64),
	armor2 = rgb(188, 188, 188),
	armor1 = rgb(120, 120, 120),
}
local ARMOR_KEYS = { "armor1", "armor2", "armor3", "armor4" }

-- ไอคอนไอเทม
local POWERUP_ICONS = {
	star = "⭐",
	grenade = "💣",
	helmet = "🛡️",
	shovel = "🧱",
	timer = "⏰",
	tank = "1UP",
}

-- หมุนตามทิศ (0 ขึ้น = -Z, 1 ขวา = +X, 2 ลง = +Z, 3 ซ้าย = -X)
local ROT = {}
for d = 0, 3 do
	ROT[d] = CFrame.Angles(0, -d * math.pi / 2, 0)
end

local function toStudX(px)
	return px * STUD
end

---------------------------------------------------------------------------
-- โฟลเดอร์ / RemoteEvent
---------------------------------------------------------------------------

local remoteFolder = ReplicatedStorage:FindFirstChild("BattleCity")
if remoteFolder and not remoteFolder:IsA("Folder") then
	remoteFolder:Destroy()
	remoteFolder = nil
end
local newRemoteFolder = remoteFolder == nil
if newRemoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "BattleCity"
end
remoteFolder:SetAttribute("MapCenter", Vector3.new(FIELD_STUDS / 2, FLOOR_Y, FIELD_STUDS / 2))
remoteFolder:SetAttribute("MapSize", Vector3.new(FIELD_STUDS, 0, FIELD_STUDS))
if newRemoteFolder then
	remoteFolder.Parent = ReplicatedStorage
end

local inputEvent = remoteFolder:FindFirstChild("Input")
if inputEvent and not inputEvent:IsA("RemoteEvent") then
	inputEvent:Destroy()
	inputEvent = nil
end
if not inputEvent then
	inputEvent = Instance.new("RemoteEvent")
	inputEvent.Name = "Input"
	inputEvent.Parent = remoteFolder
end

-- ของเก่าจากรอบก่อน (เช่นกด Run ซ้ำ) ลบทิ้งแล้วสร้างใหม่ทั้งหมด
local oldWorld = workspace:FindFirstChild("BattleCity")
if oldWorld then
	oldWorld:Destroy()
end
local worldFolder = Instance.new("Folder")
worldFolder.Name = "BattleCity"
local fieldFolder = Instance.new("Folder")
fieldFolder.Name = "Field"
fieldFolder.Parent = worldFolder
local dynamicFolder = Instance.new("Folder")
dynamicFolder.Name = "Dynamic"
dynamicFolder.Parent = worldFolder

---------------------------------------------------------------------------
-- เครื่องมือสร้าง Part
---------------------------------------------------------------------------

-- Part ประดับ: ไม่มีฟิสิกส์เลย (ต้องปิด CanCollide ก่อน CanQuery ถึงจะมีผล) ผู้เรียกตั้ง Parent เป็นอย่างสุดท้าย
local function newPart(name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	return p
end

-- ตั้ง property ที่บางเวอร์ชัน/บางโหมดอาจไม่มีหรือห้ามตั้ง (เช่นเรื่อง streaming) โดยไม่ให้สคริปต์พัง
local function trySet(inst, prop, value)
	pcall(function()
		inst[prop] = value
	end)
end

-- ป้ายบนหน้าบนของ Part (ใช้กับนกอินทรีและไอเทม)
local function addTopLabel(part, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Icon"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor or C.score
	label.Rotation = TOP_ICON_ROTATION
	label.Parent = gui
	gui.Parent = part
	return gui, label
end

---------------------------------------------------------------------------
-- กรอบสนาม / พื้น / นกอินทรี
---------------------------------------------------------------------------

local floorPart
do
	local frame = Instance.new("Model")
	frame.Name = "Frame"
	-- กรอบ/พื้นต้องเห็นตลอดแม้เปิด StreamingEnabled
	trySet(frame, "ModelStreamingMode", Enum.ModelStreamingMode.Persistent)
	floorPart = newPart("Floor", Vector3.new(FIELD_STUDS, 1, FIELD_STUDS),
		CFrame.new(FIELD_STUDS / 2, FLOOR_Y - 0.5, FIELD_STUDS / 2), C.floor)
	floorPart.Parent = frame
	-- กรอบสีเทากว้าง ๆ รอบสนาม ให้จอแนวนอน/แนวตั้งเห็นเป็นสีเทาเหมือนหน้าจอ NES
	local W = 160
	local pieces = {
		{ "BorderTop", -W, -W, FIELD_STUDS + W, 0 },
		{ "BorderBottom", -W, FIELD_STUDS, FIELD_STUDS + W, FIELD_STUDS + W },
		{ "BorderLeft", -W, 0, 0, FIELD_STUDS },
		{ "BorderRight", FIELD_STUDS, 0, FIELD_STUDS + W, FIELD_STUDS },
	}
	for _, b in ipairs(pieces) do
		local x0, z0, x1, z1 = b[2], b[3], b[4], b[5]
		local p = newPart(b[1], Vector3.new(x1 - x0, 1, z1 - z0),
			CFrame.new((x0 + x1) / 2, FLOOR_Y - 0.5, (z0 + z1) / 2), C.frame)
		p.Parent = frame
	end
	frame.PrimaryPart = floorPart
	frame.Parent = fieldFolder
end

local eagleModel, eagleBody, eagleLabel, eagleGlow
do
	local base = Core.POS.BASE
	local cx, cz = toStudX(base.x + 8), toStudX(base.y + 8)
	eagleModel = Instance.new("Model")
	eagleModel.Name = "Eagle"
	eagleBody = newPart("Body", Vector3.new(7.6, 2.5, 7.6), CFrame.new(cx, FLOOR_Y + 1.25, cz), C.eagle)
	local _, label = addTopLabel(eagleBody, "🦅", C.score)
	eagleLabel = label
	eagleBody.Parent = eagleModel
	-- แผ่นเรืองแสงใต้ฐาน ให้เห็นขอบทองชัด ๆ จากกล้องด้านบน
	eagleGlow = newPart("Glow", Vector3.new(8, 0.3, 8), CFrame.new(cx, FLOOR_Y + 0.15, cz), C.eagle, Enum.Material.Neon)
	eagleGlow.Parent = eagleModel
	eagleModel.PrimaryPart = eagleBody
	eagleModel.Parent = fieldFolder
end

worldFolder.Parent = workspace

---------------------------------------------------------------------------
-- ตัวเกม
---------------------------------------------------------------------------

local sim = Core.new({ stages = Stages, seed = (tonumber(os.time()) or 1) % 2147483646 + 1 })
local TICK = tonumber(sim.config and sim.config.TICK) or 1 / 60
if not (TICK > 0) then
	TICK = 1 / 60
end
local SPAWN_ANIM_TIME = tonumber(sim.config and sim.config.SPAWN_ANIM_TIME) or 1

local simTime = 0 -- เวลาของเกม (ใช้กะพริบ/อนิเมชัน ให้ตรงกับเกมเสมอ)
local frameStamp = 0 -- นับเฟรม: ใช้ตรวจว่าของชิ้นไหนหายไปจาก state แล้ว

---------------------------------------------------------------------------
-- เสียง
---------------------------------------------------------------------------

local soundObjects = {}
local soundStamp = {} -- [key] = เฟรมที่เล่นล่าสุด (เล่นเสียงเดียวกันได้เฟรมละครั้ง)

local function soundIdOf(v)
	if type(v) == "number" then
		return "rbxassetid://" .. tostring(floor(v))
	end
	if type(v) ~= "string" or v == "" then
		return ""
	end
	if string.match(v, "^%d+$") then
		return "rbxassetid://" .. v
	end
	return v
end

local function playSound(key)
	if not key or soundStamp[key] == frameStamp then
		return
	end
	local id = soundIdOf(SOUNDS[key])
	if id == "" then
		return
	end
	soundStamp[key] = frameStamp
	local s = soundObjects[key]
	if not s or not s.Parent then
		s = Instance.new("Sound")
		s.Name = "Sound_" .. key
		s.SoundId = id
		s.Volume = 0.6
		s.Parent = worldFolder -- อยู่ใน Folder (ไม่ใช่ Part) = เสียงได้ยินทั้งแมพ
		soundObjects[key] = s
	end
	s:Play()
end

local HIT_SOUNDS = { brick = "brick", steel = "steel", border = "steel", armor = "armor", shield = "shield" }

---------------------------------------------------------------------------
-- แผนที่: 1 Part ต่อ 1 ช่องย่อย (2x2 stud) ใช้ Part เดิมซ้ำถ้าแค่เปลี่ยนชนิด
---------------------------------------------------------------------------

local cellParts = {} -- [idx] = Part
local shownKind = {} -- [idx] = ชนิดที่วาดอยู่ (EMPTY = ไม่มี Part)
local waterParts = {} -- [idx] = Part (ไว้ทำน้ำกระเพื่อม)
local waterPhase = 0

local CELL_MATERIAL = {
	[BRICK] = Enum.Material.Brick,
	[STEEL] = Enum.Material.DiamondPlate,
	[WATER] = Enum.Material.Glass,
	[TREES] = Enum.Material.Grass,
	[ICE] = Enum.Material.Ice,
}

-- ขนาด/ตำแหน่ง/สีของช่องย่อย (i, j) ตามชนิด
local function cellLook(i, j, kind)
	local x0, x1 = i * MICRO_STUDS, (i + 1) * MICRO_STUDS
	local z0, z1 = j * MICRO_STUDS, (j + 1) * MICRO_STUDS
	local checker = (i + j) % 2 == 0
	local y, h, color
	if kind == BRICK then
		-- เว้นร่องปูนแนวนอน + สลับสีเว้นก้อน = ลายก่ออิฐ
		z0, z1 = z0 + 0.1, z1 - 0.1
		y, h = FLOOR_Y + WALL_H / 2, WALL_H
		color = checker and C.brickA or C.brickB
	elseif kind == STEEL then
		-- เว้นร่องรอบบล็อก 8px ให้เห็นเป็นแผ่นเหล็กทีละแผ่นแบบ NES
		if i % 2 == 0 then
			x0 = x0 + 0.15
		else
			x1 = x1 - 0.15
		end
		if j % 2 == 0 then
			z0 = z0 + 0.15
		else
			z1 = z1 - 0.15
		end
		y, h = FLOOR_Y + WALL_H / 2, WALL_H
		color = (i % 2 == 0 and j % 2 == 0) and C.steelA or C.steelB
	elseif kind == WATER then
		y, h = FLOOR_Y + 0.1, 0.2
		color = ((i + j + waterPhase) % 2 == 0) and C.waterA or C.waterB
	elseif kind == TREES then
		y, h = TREE_Y, 0.4
		color = checker and C.treesA or C.treesB
	else -- ICE
		y, h = FLOOR_Y + 0.05, 0.1
		color = checker and C.iceA or C.iceB
	end
	return CFrame.new((x0 + x1) / 2, y, (z0 + z1) / 2), Vector3.new(x1 - x0, h, z1 - z0), color
end

local function syncCell(i, j)
	local idx = j * GRID_N + i + 1
	local kind = sim.grid[idx] or EMPTY
	if not CELL_MATERIAL[kind] then
		kind = EMPTY -- BASE วาดเป็นนกอินทรีแยกต่างหาก
	end
	local cur = shownKind[idx] or EMPTY
	if cur == kind then
		return
	end
	local part = cellParts[idx]
	if kind == EMPTY then
		if part then
			part:Destroy()
		end
		cellParts[idx] = nil
	else
		local cf, size, color = cellLook(i, j, kind)
		if part then
			-- ใช้ Part เดิม (เช่นพลั่วสลับอิฐ/เหล็ก) แค่เปลี่ยนหน้าตา
			part.Material = CELL_MATERIAL[kind]
			part.Color = color
			part.Size = size
			part.CFrame = cf
		else
			part = newPart("C" .. i .. "_" .. j, size, cf, color, CELL_MATERIAL[kind])
			part.Parent = fieldFolder
			cellParts[idx] = part
		end
	end
	if kind == WATER then
		waterParts[idx] = part
	else
		waterParts[idx] = nil
	end
	shownKind[idx] = kind
end

local function syncAllCells()
	for j = 0, GRID_N - 1 do
		for i = 0, GRID_N - 1 do
			syncCell(i, j)
		end
	end
end

local function animateWater()
	local ph = floor(simTime / 0.75) % 2
	if ph == waterPhase then
		return
	end
	waterPhase = ph
	for idx, part in pairs(waterParts) do
		local i = (idx - 1) % GRID_N
		local j = (idx - 1 - i) / GRID_N
		part.Color = ((i + j + ph) % 2 == 0) and C.waterA or C.waterB
	end
end

local eagleWrecked = false
local function syncEagle()
	local wrecked = sim.baseDestroyed == true
	if wrecked == eagleWrecked then
		return
	end
	eagleWrecked = wrecked
	if wrecked then
		eagleBody.Color = C.eagleDead
		eagleGlow.Transparency = 1
		eagleLabel.Text = "🏳️"
	else
		eagleBody.Color = C.eagle
		eagleGlow.Transparency = 0
		eagleLabel.Text = "🦅"
	end
end

---------------------------------------------------------------------------
-- ย้าย Part ทีละหลายชิ้นในครั้งเดียว (เร็วกว่าตั้ง CFrame ทีละชิ้น)
---------------------------------------------------------------------------

local moveParts, moveCFs = {}, {}
local function queueMove(part, cf)
	local n = #moveParts + 1
	moveParts[n] = part
	moveCFs[n] = cf
end
local function clearMoves()
	for k = #moveParts, 1, -1 do
		moveParts[k] = nil
		moveCFs[k] = nil
	end
end
local function flushMoves()
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFs)
		clearMoves()
	end
end

---------------------------------------------------------------------------
-- รถถัง: Model ต่อคัน (Root ล่องหนที่พื้น = PrimaryPart, ตีนตะขาบ, ตัวถัง, ป้อม, ลำกล้อง)
---------------------------------------------------------------------------

-- ชิ้นส่วน: { ชื่อ, กว้าง X, สูง Y, ยาว Z, x, ก้นชิ้นสูงจากพื้น, z, บทบาทสี } (หน้ารถ = -Z)
local function playerShape(level)
	local lv = floor(tonumber(level) or 0)
	if lv < 0 then
		lv = 0
	elseif lv > 3 then
		lv = 3
	end
	local hullW = lv >= 3 and 4.6 or 4.2
	local turret = lv >= 2 and 3.4 or 3.0
	local bw = lv >= 3 and 0.9 or (lv >= 1 and 0.75 or 0.6)
	local tip = lv >= 1 and -3.9 or -3.4
	local tz = 0.6
	local s = {
		{ "TreadL", 1.7, 1.5, 7.6, -2.95, 0, 0, "tread" },
		{ "TreadR", 1.7, 1.5, 7.6, 2.95, 0, 0, "tread" },
		{ "Hull", hullW, 1.6, 6.2, 0, 0.4, 0.2, "main" },
		{ "Turret", turret, 1.1, turret, 0, 2.0, tz, "light" },
		{ "Hatch", 1.2, 0.3, 1.2, 0, 3.1, tz + 0.3, "dark" },
		{ "Barrel", bw, bw, tz - tip, 0, 2.55 - bw / 2, (tz + tip) / 2, "barrel" },
	}
	if lv >= 3 then
		-- ดาว 3: ติดเกราะข้างให้ดูหนักขึ้น
		s[#s + 1] = { "PlateL", 0.5, 0.6, 6.0, -2.95, 1.5, 0, "dark" }
		s[#s + 1] = { "PlateR", 0.5, 0.6, 6.0, 2.95, 1.5, 0, "dark" }
	end
	return s
end

local ENEMY_SHAPES = {
	basic = {
		{ "TreadL", 1.6, 1.4, 7.2, -3.0, 0, 0, "tread" },
		{ "TreadR", 1.6, 1.4, 7.2, 3.0, 0, 0, "tread" },
		{ "Hull", 4.4, 1.4, 5.8, 0, 0.4, 0.1, "main" },
		{ "Turret", 2.8, 1.0, 2.8, 0, 1.8, 0.5, "light" },
		{ "Barrel", 0.6, 0.6, 4.1, 0, 2.0, -1.55, "barrel" },
	},
	fast = { -- เพรียว ยาว ป้อมเล็กอยู่ท้าย
		{ "TreadL", 1.2, 1.2, 7.6, -2.3, 0, 0, "tread" },
		{ "TreadR", 1.2, 1.2, 7.6, 2.3, 0, 0, "tread" },
		{ "Hull", 3.4, 1.2, 6.6, 0, 0.3, 0.2, "main" },
		{ "Nose", 2.6, 0.9, 0.7, 0, 0.3, -3.45, "dark" },
		{ "Turret", 2.2, 0.9, 2.4, 0, 1.5, 1.4, "light" },
		{ "Barrel", 0.5, 0.5, 4.4, 0, 1.7, -0.8, "barrel" },
	},
	power = { -- ลำกล้องยาวพร้อมปากกระบอก
		{ "TreadL", 1.6, 1.5, 7.4, -3.0, 0, 0, "tread" },
		{ "TreadR", 1.6, 1.5, 7.4, 3.0, 0, 0, "tread" },
		{ "Hull", 4.4, 1.6, 6.0, 0, 0.4, 0.3, "main" },
		{ "Turret", 3.0, 1.2, 3.0, 0, 2.0, 1.0, "light" },
		{ "Barrel", 0.7, 0.7, 5.4, 0, 2.25, -1.7, "barrel" },
		{ "Muzzle", 1.1, 1.1, 0.7, 0, 2.05, -4.05, "dark" },
	},
	armor = { -- อ้วน ตีนตะขาบกว้าง มีแผ่นเกราะ
		{ "TreadL", 2.0, 1.8, 7.6, -2.8, 0, 0, "tread" },
		{ "TreadR", 2.0, 1.8, 7.6, 2.8, 0, 0, "tread" },
		{ "Hull", 3.6, 2.0, 6.6, 0, 0.4, 0, "main" },
		{ "PlateL", 0.6, 0.7, 6.4, -2.8, 1.8, 0, "dark" },
		{ "PlateR", 0.6, 0.7, 6.4, 2.8, 1.8, 0, "dark" },
		{ "PlateF", 3.6, 1.0, 0.6, 0, 0.6, -3.4, "dark" },
		{ "Turret", 3.6, 1.3, 3.6, 0, 2.4, 0.5, "light" },
		{ "Barrel", 0.9, 0.9, 4.3, 0, 2.6, -1.65, "barrel" },
	},
}

local BLACK, WHITE = rgb(0, 0, 0), rgb(255, 255, 255)
local palettes = {}
for key, c in pairs(TANK_COLORS) do
	palettes[key] = {
		main = c,
		light = c:Lerp(WHITE, 0.3),
		dark = c:Lerp(BLACK, 0.5),
		barrel = c:Lerp(BLACK, 0.15),
		tread = c:Lerp(BLACK, 0.62),
		tread2 = c:Lerp(BLACK, 0.42),
	}
end

local tankViews = {} -- [id] = view

local function shapeKeyOf(t)
	if t.team == "player" then
		return "player" .. tostring(floor(tonumber(t.level) or 0))
	end
	if ENEMY_SHAPES[t.kind] then
		return t.kind
	end
	return "basic"
end

local function paintKeyOf(t)
	-- รถถังถือไอเทม: กะพริบแดง ~6 ครั้งต่อวินาที
	if t.bonus and floor(simTime * 12) % 2 == 0 then
		return "red"
	end
	if t.team == "player" then
		return t.slot == 2 and "p2" or "p1"
	end
	if t.kind == "armor" then
		local hp = floor(tonumber(t.hp) or 1)
		if hp < 1 then
			hp = 1
		elseif hp > 4 then
			hp = 4
		end
		return ARMOR_KEYS[hp]
	end
	return "enemy"
end

local function tankPivot(t)
	local dir = t.dir
	if not ROT[dir] then
		dir = 0
	end
	return CFrame.new(toStudX(t.x + 8), FLOOR_Y, toStudX(t.y + 8)) * ROT[dir]
end

local function paintTank(v, key, treadsOnly)
	local pal = palettes[key] or palettes.enemy
	v.paintKey = key
	for k, part in ipairs(v.parts) do
		local role = v.roles[k]
		if role == "tread" then
			part.Color = (v.treadPhase == 1) and pal.tread2 or pal.tread
		elseif role and not treadsOnly then
			part.Color = pal[role]
		end
	end
end

local function createTankView(t, shapeKey)
	local shape
	if t.team == "player" then
		shape = playerShape(t.level)
	else
		shape = ENEMY_SHAPES[shapeKey] or ENEMY_SHAPES.basic
	end
	local pivot = tankPivot(t)
	local model = Instance.new("Model")
	model.Name = "Tank" .. tostring(t.id)
	trySet(model, "ModelStreamingMode", Enum.ModelStreamingMode.Atomic) -- ส่งถึง client ทั้งคันพร้อมกัน
	local root = newPart("Root", Vector3.new(1, 0.2, 1), pivot, C.floor)
	root.Transparency = 1
	root.Parent = model
	local v = {
		model = model,
		root = root,
		parts = { root },
		offsets = { CFrame.new() },
		roles = { false },
		shapeKey = shapeKey,
		treadPhase = 0,
		hidden = false,
		x = t.x,
		y = t.y,
		dir = t.dir,
		stamp = frameStamp,
	}
	local pal = palettes.enemy
	for _, s in ipairs(shape) do
		local off = CFrame.new(s[5], s[6] + s[3] / 2, s[7])
		local role = s[8]
		local material = Enum.Material.SmoothPlastic
		if role == "tread" then
			material = Enum.Material.DiamondPlate
		end
		local part = newPart(s[1], Vector3.new(s[2], s[3], s[4]), pivot * off, pal[role] or pal.main, material)
		part.Parent = model
		local n = #v.parts + 1
		v.parts[n] = part
		v.offsets[n] = off
		v.roles[n] = role
	end
	model.PrimaryPart = root
	paintTank(v, paintKeyOf(t), false)
	model.Parent = dynamicFolder
	return v
end

local function destroyTankView(v)
	if v.model then
		v.model:Destroy()
	end
	v.model = nil
end

local function setShield(v, on)
	if on then
		if not v.shield then
			-- ลูกบอลโล่: ยอดต่ำกว่าป่า (FLOOR_Y + 6.2) ป่าจึงยังบังรถถังที่มีโล่ได้
			local off = CFrame.new(0, 1.5, 0)
			local cf = tankPivot({ x = v.x, y = v.y, dir = v.dir }) * off
			local s = newPart("Shield", Vector3.new(8.8, 8.8, 8.8), cf, C.shield, Enum.Material.Neon)
			s.Shape = Enum.PartType.Ball
			s.Transparency = 0.7
			s.Parent = v.model
			v.shield = s
			v.shieldOffset = off
			v.shieldLow = false
		end
		-- โล่กะพริบเร็ว ๆ แบบ NES
		local low = floor(simTime * 20) % 2 == 0
		if low ~= v.shieldLow then
			v.shieldLow = low
			v.shield.Transparency = low and 0.85 or 0.62
		end
	elseif v.shield then
		v.shield:Destroy()
		v.shield = nil
	end
end

local function updateTankView(v, t)
	if t.x ~= v.x or t.y ~= v.y or t.dir ~= v.dir then
		v.x, v.y, v.dir = t.x, t.y, t.dir
		local pivot = tankPivot(t)
		for k, part in ipairs(v.parts) do
			queueMove(part, pivot * v.offsets[k])
		end
		if v.shield then
			queueMove(v.shield, pivot * v.shieldOffset)
		end
	end
	-- ตีนตะขาบสลับสีตอนวิ่ง = ล้อหมุน (ทาสีใหม่เฉพาะชิ้นที่เปลี่ยน ลดของที่ต้องส่งให้ client)
	local key = paintKeyOf(t)
	local tp = v.treadPhase
	if t.moving then
		tp = floor(simTime * 12) % 2
	end
	if key ~= v.paintKey then
		v.treadPhase = tp
		paintTank(v, key, false)
	elseif tp ~= v.treadPhase then
		v.treadPhase = tp
		paintTank(v, key, true)
	end
	setShield(v, (tonumber(t.shield) or 0) > 0)
	-- โดนเพื่อนยิงจนแข็ง: กะพริบหายไป-มา
	local hidden = (tonumber(t.frozen) or 0) > 0 and floor(simTime * 8) % 2 == 1
	if hidden ~= v.hidden then
		v.hidden = hidden
		for k, part in ipairs(v.parts) do
			if v.roles[k] then
				part.Transparency = hidden and 1 or 0
			end
		end
	end
end

local function syncTanks()
	for _, t in ipairs(sim.tanks) do
		local v = tankViews[t.id]
		local shapeKey = shapeKeyOf(t)
		if v and v.shapeKey ~= shapeKey then
			-- เก็บดาวแล้วรูปร่างเปลี่ยน: สร้างใหม่ (เกิดไม่บ่อย)
			destroyTankView(v)
			v = nil
		end
		if not v then
			v = createTankView(t, shapeKey)
			tankViews[t.id] = v
		end
		v.stamp = frameStamp
		updateTankView(v, t)
	end
	for id, v in pairs(tankViews) do
		if v.stamp ~= frameStamp then
			destroyTankView(v)
			tankViews[id] = nil
		end
	end
end

---------------------------------------------------------------------------
-- กระสุน (เก็บ Part ที่เลิกใช้ไว้ใช้ซ้ำ)
---------------------------------------------------------------------------

local bulletViews = {} -- [id] = { part, x, y, stamp }
local bulletPool = {}

local function bulletCFrame(b)
	local dir = b.dir
	if not ROT[dir] then
		dir = 0
	end
	return CFrame.new(toStudX(b.x), BULLET_Y, toStudX(b.y)) * ROT[dir]
end

local function syncBullets()
	for _, b in ipairs(sim.bullets) do
		local v = bulletViews[b.id]
		if not v then
			local cf = bulletCFrame(b)
			local part = table.remove(bulletPool)
			if part then
				part.CFrame = cf
			else
				part = newPart("Bullet", Vector3.new(1, 1, 1.4), cf, C.bullet, Enum.Material.Neon)
			end
			part.Name = "Bullet" .. tostring(b.id)
			part.Parent = dynamicFolder
			v = { part = part, x = b.x, y = b.y }
			bulletViews[b.id] = v
		elseif v.x ~= b.x or v.y ~= b.y then
			v.x, v.y = b.x, b.y
			queueMove(v.part, bulletCFrame(b))
		end
		v.stamp = frameStamp
	end
	for id, v in pairs(bulletViews) do
		if v.stamp ~= frameStamp then
			bulletViews[id] = nil
			if #bulletPool < BULLET_POOL_MAX then
				v.part.Parent = nil
				bulletPool[#bulletPool + 1] = v.part
			else
				v.part:Destroy()
			end
		end
	end
end

---------------------------------------------------------------------------
-- ดาวกะพริบตอนรถถังกำลังเกิด
---------------------------------------------------------------------------

local spawnViews = {}
local STAR_ANGLES = { 0, math.pi / 2, math.pi / 4, 3 * math.pi / 4 }

local function createSpawnView(s)
	local model = Instance.new("Model")
	model.Name = "Spawn" .. tostring(s.id)
	trySet(model, "ModelStreamingMode", Enum.ModelStreamingMode.Atomic)
	local base = CFrame.new(toStudX(s.x + 8), SPAWN_Y, toStudX(s.y + 8))
	local core = newPart("Core", Vector3.new(1.2, 1.2, 1.2), base, C.spawnCore, Enum.Material.Neon)
	core.Shape = Enum.PartType.Ball
	core.Parent = model
	local v = { model = model, core = core, bars = {}, offsets = {}, size = -1 }
	for k, a in ipairs(STAR_ANGLES) do
		local off = CFrame.Angles(0, a, 0)
		local bar = newPart("Ray" .. k, Vector3.new(0.5, 0.25, 2), base * off, C.spawnStar, Enum.Material.Neon)
		bar.Parent = model
		v.bars[k] = bar
		v.offsets[k] = off
	end
	model.PrimaryPart = core
	model.Parent = dynamicFolder
	return v
end

local function updateSpawnView(v, s)
	local elapsed = SPAWN_ANIM_TIME - (tonumber(s.t) or 0)
	-- ดาวพองยุบ 4 ครั้งต่อวินาทีและหมุน (คล้ายประกายตอนเกิดใน NES)
	local ph = (elapsed * 4) % 1
	local scale = 0.3 + 0.7 * (1 - math.abs(2 * ph - 1))
	local len = floor((1.5 + 6.5 * scale) * 20 + 0.5) / 20
	if len ~= v.size then
		v.size = len
		for k, bar in ipairs(v.bars) do
			local l = (k <= 2) and len or len * 0.7
			bar.Size = Vector3.new(0.5, 0.25, l)
		end
	end
	local base = CFrame.new(toStudX(s.x + 8), SPAWN_Y, toStudX(s.y + 8)) * CFrame.Angles(0, elapsed * 5, 0)
	queueMove(v.core, base)
	for k, bar in ipairs(v.bars) do
		queueMove(bar, base * v.offsets[k])
	end
end

local function syncSpawns()
	for _, s in ipairs(sim.spawns) do
		local v = spawnViews[s.id]
		if not v then
			v = createSpawnView(s)
			spawnViews[s.id] = v
		end
		v.stamp = frameStamp
		updateSpawnView(v, s)
	end
	for id, v in pairs(spawnViews) do
		if v.stamp ~= frameStamp then
			v.model:Destroy()
			spawnViews[id] = nil
		end
	end
end

---------------------------------------------------------------------------
-- ไอเทม (ลอยเหนือป่า กะพริบ)
---------------------------------------------------------------------------

local powerView = nil -- { id, part, gui, visible }

local function destroyPowerView()
	if powerView then
		powerView.part:Destroy()
		powerView = nil
	end
end

local function syncPowerup()
	local pu = sim.powerup
	if not pu then
		destroyPowerView()
		return
	end
	if powerView and powerView.id ~= pu.id then
		destroyPowerView()
	end
	if not powerView then
		local cf = CFrame.new(toStudX(pu.x + 8), POWERUP_Y, toStudX(pu.y + 8))
		local part = newPart("Powerup", Vector3.new(7.4, 0.3, 7.4), cf, C.powerupTile)
		part:SetAttribute("Kind", tostring(pu.kind))
		local gui = addTopLabel(part, POWERUP_ICONS[pu.kind] or "?", C.powerupText)
		part.Parent = dynamicFolder
		powerView = { id = pu.id, part = part, gui = gui, visible = true }
	end
	local visible = floor(simTime * 5) % 2 == 0
	if visible ~= powerView.visible then
		powerView.visible = visible
		powerView.part.Transparency = visible and 0 or 1
		powerView.gui.Enabled = visible
	end
end

---------------------------------------------------------------------------
-- เอฟเฟกต์ระเบิด / ป้ายคะแนน (ลบตัวเองด้วย Debris)
---------------------------------------------------------------------------

local function spawnBall(cf, color, s0, s1, duration, transparency)
	local p = newPart("Explosion", Vector3.new(s0, s0, s0), cf, color, Enum.Material.Neon)
	p.Shape = Enum.PartType.Ball
	p.Transparency = transparency or 0
	p.Parent = dynamicFolder
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(s1, s1, s1), Transparency = 1 }):Play()
	Debris:AddItem(p, duration + 0.05)
end

local function spawnExplosion(x, y, big)
	local cf = CFrame.new(toStudX(x), EXPLOSION_Y, toStudX(y))
	if big then
		spawnBall(cf, C.explosion, 2, 12, 0.5, 0.1)
		spawnBall(cf, C.explosionCore, 1, 6, 0.35, 0)
	else
		spawnBall(cf, C.explosion, 0.8, 3.6, 0.25, 0)
	end
end

local function spawnScore(x, y, points)
	local anchor = newPart("Score", Vector3.new(0.2, 0.2, 0.2), CFrame.new(toStudX(x), POWERUP_Y + 1, toStudX(y)), C.score)
	anchor.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Name = "Popup"
	bb.Size = UDim2.fromScale(10, 4) -- หน่วยเป็น stud: ย่อขยายตามกล้อง
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.Text = tostring(floor(tonumber(points) or 0))
	label.TextScaled = true
	label.TextColor3 = C.score
	label.TextStrokeTransparency = 0
	label.Parent = bb
	bb.Parent = anchor
	anchor.Parent = dynamicFolder
	Debris:AddItem(anchor, 1)
end

---------------------------------------------------------------------------
-- Attribute สถานะเกม (ตั้งเฉพาะค่าที่เปลี่ยน)
---------------------------------------------------------------------------

local attrCache = {}
local function setAttr(name, value)
	if attrCache[name] ~= value then
		attrCache[name] = value
		remoteFolder:SetAttribute(name, value)
	end
end

local SLOT_ATTRS = {
	{ present = "P1Present", lives = "P1Lives", score = "P1Score", name = "P1Name" },
	{ present = "P2Present", lives = "P2Lives", score = "P2Score", name = "P2Name" },
}

local slotPlayer = {} -- [1|2] = Player
local slotOf = {} -- [Player] = 0 (ผู้ชม) / 1 / 2
local spectators = {} -- ผู้ชมเรียงตามลำดับที่เข้ามา

local function numArray(t)
	local out = {}
	if type(t) == "table" then
		for k = 1, 4 do
			out[k] = tonumber(t[k]) or 0
		end
	end
	return out
end

-- JSON ของตารางสรุปคะแนน: ทำสำเนาเฉพาะค่าที่ต้องใช้ และช่องผู้เล่นที่ไม่มีใส่ false (JSON array มีรูไม่ได้)
local function tallyJson(t)
	if type(t) ~= "table" then
		return ""
	end
	local src = type(t.players) == "table" and t.players or {}
	local maxSlot = 0
	for slot = 1, 2 do
		if type(src[slot]) == "table" then
			maxSlot = slot
		end
	end
	local players = {}
	for slot = 1, maxSlot do
		local p = src[slot]
		if type(p) == "table" then
			players[slot] = {
				kills = numArray(p.kills),
				points = numArray(p.points),
				totalKills = tonumber(p.totalKills) or 0,
				score = tonumber(p.score) or 0,
				bonus = tonumber(p.bonus) or 0,
			}
		else
			players[slot] = false
		end
	end
	local data = {
		stageNumber = tonumber(t.stageNumber) or 0,
		gameOver = t.gameOver == true,
		players = players,
	}
	local ok, s = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if ok and type(s) == "string" then
		return s
	end
	return ""
end

local lastPhase = nil
local phaseEventSeen = false
local lastTally = false

local function syncAttributes()
	local phase = tostring(sim.phase)
	if phase ~= lastPhase or phaseEventSeen then
		lastPhase = phase
		phaseEventSeen = false
		setAttr("Phase", phase)
		setAttr("PhaseStartedAt", workspace:GetServerTimeNow() - (tonumber(sim.phaseTime) or 0))
	end
	setAttr("Stage", tonumber(sim.stageNumber) or 1)
	setAttr("StageName", tostring(sim.stageName or ""))
	setAttr("EnemiesLeft", tonumber(sim.enemiesInReserve) or 0)
	for slot = 1, 2 do
		local names = SLOT_ATTRS[slot]
		local p = sim.players[slot]
		setAttr(names.present, p ~= nil)
		setAttr(names.lives, p and tonumber(p.lives) or 0)
		setAttr(names.score, p and tonumber(p.score) or 0)
		local pl = slotPlayer[slot]
		local name = ""
		if p and pl then
			name = pl.DisplayName
			if type(name) ~= "string" or name == "" then
				name = pl.Name
			end
		end
		setAttr(names.name, name)
	end
	setAttr("HiScore", tonumber(sim.hiScore) or 0)
	setAttr("GameOver", sim.isGameOver == true)
	if sim.tally ~= lastTally then
		lastTally = sim.tally
		setAttr("Tally", tallyJson(sim.tally))
	end
end

---------------------------------------------------------------------------
-- อีเวนต์จาก Core
---------------------------------------------------------------------------

local needFullSync = false

local function handleEvents(events)
	local effects = 0
	for _, ev in ipairs(events) do
		local ty = ev.type
		if ty == "cell" then
			local i, j = tonumber(ev.i), tonumber(ev.j)
			if i and j and i >= 0 and j >= 0 and i < GRID_N and j < GRID_N and i == floor(i) and j == floor(j) then
				syncCell(i, j)
			end
		elseif ty == "stage" then
			needFullSync = true
		elseif ty == "explosion" then
			if effects < MAX_EFFECTS_PER_FRAME then
				effects = effects + 1
				spawnExplosion(tonumber(ev.x) or 0, tonumber(ev.y) or 0, ev.big == true)
			end
			if ev.big then
				playSound("explosion")
			end
		elseif ty == "score" then
			if effects < MAX_EFFECTS_PER_FRAME then
				effects = effects + 1
				spawnScore(tonumber(ev.x) or 0, tonumber(ev.y) or 0, ev.points)
			end
		elseif ty == "phase" then
			phaseEventSeen = true
			if ev.phase == "intro" then
				playSound("stageStart")
			elseif ev.phase == "gameOver" then
				playSound("gameOver")
			end
		elseif ty == "fire" then
			playSound("fire")
		elseif ty == "hit" then
			playSound(HIT_SOUNDS[ev.what])
		elseif ty == "powerupSpawn" then
			playSound("powerupSpawn")
		elseif ty == "powerupTaken" then
			playSound("powerup")
		elseif ty == "extraLife" then
			playSound("extraLife")
		elseif ty == "baseDestroyed" then
			playSound("baseDestroyed")
		elseif ty == "playerDied" then
			playSound("playerDied")
		end
	end
end

---------------------------------------------------------------------------
-- ผู้เล่น / ช่องผู้เล่น / ผู้ชม
---------------------------------------------------------------------------

local function destroyCharacter(player)
	local ch = player.Character
	if ch then
		ch:Destroy()
	end
end

local function assignSlot(player, slot)
	slotOf[player] = slot
	if slot == 1 or slot == 2 then
		slotPlayer[slot] = player
		sim:addPlayer(slot)
	else
		spectators[#spectators + 1] = player
	end
	player:SetAttribute("BattleCitySlot", slot)
end

local function onPlayerAdded(player)
	if slotOf[player] ~= nil then
		return -- เจอแล้วจากลูปผู้เล่นที่อยู่ก่อนสคริปต์เริ่ม
	end
	if player.Parent ~= Players then
		return -- ออกไปแล้วก่อน handler ได้ทำงาน (SignalBehavior = Deferred)
	end
	-- เป็นรถถัง ไม่ใช่คน: ลบตัวละครที่อาจเกิดไปแล้ว และที่จะเกิดทีหลัง
	destroyCharacter(player)
	-- ไม่มีตัวละคร: ให้ StreamingEnabled ส่งของรอบ ๆ สนามแทน
	trySet(player, "ReplicationFocus", floorPart)
	player.CharacterAdded:Connect(function(ch)
		task.defer(function()
			if ch.Parent then
				ch:Destroy()
			end
		end)
	end)
	local slot = 0
	if not slotPlayer[1] then
		slot = 1
	elseif not slotPlayer[2] then
		slot = 2
	end
	assignSlot(player, slot)
end

local function onPlayerRemoving(player)
	local slot = slotOf[player]
	slotOf[player] = nil
	for k = #spectators, 1, -1 do
		if spectators[k] == player then
			table.remove(spectators, k)
		end
	end
	if slot ~= 1 and slot ~= 2 then
		return
	end
	if slotPlayer[slot] == player then
		slotPlayer[slot] = nil
	end
	sim:removePlayer(slot)
	-- ผู้ชมคนแรกที่ยังอยู่ได้ขึ้นมาเล่นแทน
	while #spectators > 0 do
		local nextPlayer = table.remove(spectators, 1)
		if nextPlayer.Parent == Players and slotOf[nextPlayer] == 0 then
			assignSlot(nextPlayer, slot)
			break
		end
	end
end

-- กันพลาด: คนถือช่องที่หลุดออกจากเกมไปแล้วโดยไม่มี PlayerRemoving มาถึงเรา
local function sweepGonePlayers()
	for slot = 1, 2 do
		local pl = slotPlayer[slot]
		if pl and pl.Parent ~= Players then
			onPlayerRemoving(pl)
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- input จาก client: ตรวจทุกค่า เพราะคนโกงส่งอะไรมาก็ได้
inputEvent.OnServerEvent:Connect(function(player, dir, fire)
	local slot = slotOf[player]
	if slot ~= 1 and slot ~= 2 then
		return
	end
	if type(dir) ~= "number" or dir ~= dir or dir ~= floor(dir) or dir < -1 or dir > 3 then
		return
	end
	if type(fire) ~= "boolean" then
		return
	end
	sim:setInput(slot, dir, fire)
end)

---------------------------------------------------------------------------
-- วนเกมทุกเฟรม
---------------------------------------------------------------------------

local acc = 0

local function runFrame(dt)
	if type(dt) ~= "number" or dt ~= dt or dt < 0 then
		dt = 0
	end
	acc = acc + dt
	if acc > 0.25 then
		acc = 0.25 -- กันเฟรมกระตุกนาน ๆ แล้วเกมเร่งตามไม่ทัน
	end
	sweepGonePlayers()
	local steps = 0
	while acc >= TICK - 1e-6 and steps < 30 do
		acc = acc - TICK
		steps = steps + 1
		sim:step(TICK)
	end
	if acc < 0 then
		acc = 0
	end
	simTime = tonumber(sim.time) or simTime
	frameStamp = frameStamp + 1
	handleEvents(sim:popEvents())
	if needFullSync then
		needFullSync = false
		syncAllCells()
	end
	syncEagle()
	animateWater()
	syncTanks()
	syncBullets()
	syncSpawns()
	syncPowerup()
	flushMoves()
	syncAttributes()
end

local errorCount = 0
RunService.Heartbeat:Connect(function(dt)
	local ok, err = pcall(runFrame, dt)
	if not ok then
		-- อย่าให้ error ครั้งเดียวทำให้ภาพค้าง: เฟรมหน้าซิงก์แผนที่ใหม่ทั้งหมด
		needFullSync = true
		clearMoves()
		errorCount = errorCount + 1
		if errorCount <= 5 then
			warn("[BattleCity] " .. tostring(err))
		end
	end
end)

syncAttributes()
