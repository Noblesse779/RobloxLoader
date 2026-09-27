--[[
	🌈 Rainbow Obby — แมพอ็อบบี้ (ปาร์คัวร์) 8 ด่าน สร้างอัตโนมัติ

	วิธีใช้:
	1. เปิด Roblox Studio → New → Baseplate
	2. หน้าต่าง Explorer: คลิกขวา ServerScriptService → Insert Object → Script
	3. ลบโค้ดเดิมใน Script ออก แล้ววางโค้ดทั้งไฟล์นี้ลงไป
	4. กด Play — แมพจะถูกสร้างขึ้นเองตอนเริ่มเกม

	ถ้าใน Workspace มีโฟลเดอร์ชื่อ RainbowObby อยู่แล้ว สคริปต์จะใช้แมพนั้นแทนการสร้างใหม่
	(ใช้ตอนอยากแต่งแมพเองใน Studio — ดูขั้นตอนใน README.md)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

-- ============================================================
-- ตั้งค่า
-- ============================================================

local MAP_NAME = "RainbowObby"
local BASE_Y = 60 -- ความสูงพื้นล็อบบี้
local LAVA_Y = BASE_Y - 40 -- ความสูงทะเลลาวาด้านล่าง (โดนแล้วตาย)
local RESPAWN_OFFSET = Vector3.new(0, 4, 0)
local FACE_FORWARD = CFrame.Angles(0, math.rad(-90), 0) -- หันด้านหน้าไปทาง +X (ทิศที่ผู้เล่นวิ่งไป)

local RAINBOW = {
	Color3.fromRGB(255, 89, 94), -- แดง
	Color3.fromRGB(255, 146, 76), -- ส้ม
	Color3.fromRGB(255, 202, 58), -- เหลือง
	Color3.fromRGB(138, 201, 38), -- เขียว
	Color3.fromRGB(38, 196, 185), -- ฟ้าอมเขียว
	Color3.fromRGB(25, 130, 196), -- น้ำเงิน
	Color3.fromRGB(106, 76, 147), -- ม่วง
	Color3.fromRGB(241, 91, 181), -- ชมพู
}
local KILL_COLOR = Color3.fromRGB(255, 40, 40)
local CHECKPOINT_COLOR = Color3.fromRGB(120, 230, 150)
local GOLD = Color3.fromRGB(255, 200, 40)
local WHITE = Color3.fromRGB(245, 245, 245)

-- ============================================================
-- ตัวช่วยสร้างชิ้นส่วน
-- ============================================================

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

-- สร้าง Part แบบยึดติด (Anchored) ผิวเรียบ; props.Attributes ใช้บอกหน้าที่ของชิ้นส่วนตอนเล่น
local function makePart(parent, props)
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		part.Shape = props.Shape
	end
	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Attributes" and key ~= "Shape" then
			part[key] = value
		end
	end
	for name, value in pairs(props.Attributes or {}) do
		part:SetAttribute(name, value)
	end
	part.Parent = parent
	return part
end

-- แท่นที่ผิวด้านบนอยู่ที่ตำแหน่ง top พอดี
local function platform(parent, top, size, color, props)
	props = props or {}
	props.Size = size
	props.Color = color
	props.CFrame = CFrame.new(top.X, top.Y - size.Y / 2, top.Z)
	return makePart(parent, props)
end

local function killBrick(parent, center, size)
	return makePart(parent, {
		Name = "KillBrick",
		Size = size,
		CFrame = CFrame.new(center),
		Color = KILL_COLOR,
		Material = Enum.Material.Neon,
		Attributes = { Kill = true },
	})
end

-- ส่วนที่มองไม่เห็น ใช้เป็นจุดยึดของ constraint
local function hiddenAnchor(parent, name, cframe)
	return makePart(parent, {
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})
end

local function addBillboard(part, title, subtitle)
	local gui = create("BillboardGui", {
		Name = "Label",
		Size = UDim2.new(0, 280, 0, 70),
		StudsOffset = Vector3.new(0, 7, 0),
		MaxDistance = 90,
	}, part)
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		Text = title,
	}, gui)
	if subtitle then
		create("TextLabel", {
			Position = UDim2.new(0, 0, 0.6, 0),
			Size = UDim2.new(1, 0, 0.4, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 240, 150),
			TextStrokeTransparency = 0.2,
			Text = subtitle,
		}, gui)
	end
end

local function addFloorNumber(part, text)
	local gui = create("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
	}, part)
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextTransparency = 0.35,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
	}, gui)
end

-- ============================================================
-- ด่านต่าง ๆ
-- ทุกฟังก์ชันรับ start = จุดขอบหน้าของแท่นก่อนหน้า (ระดับผิวบน)
-- และคืนค่าจุดขอบของแท่นถัดไป (จุดเซฟ หรือ เส้นชัย)
-- ============================================================

-- ด่าน 1: กระโดดข้ามแท่นเล็ก ๆ ค่อย ๆ สูงขึ้น
local function buildEasyJumps(folder, start, color)
	local heights = { 0, 1, 2, 1, 3 }
	local sideOffsets = { 0, 3, -3, 2, 0 }
	local x = start.X
	for i = 1, #heights do
		x = x + 5
		platform(folder, Vector3.new(x + 3, start.Y + heights[i], start.Z + sideOffsets[i]), Vector3.new(6, 1, 6), color)
		x = x + 6
	end
	return Vector3.new(x + 5, start.Y + 3, start.Z)
end

-- ด่าน 2: ทางเดินที่มีบล็อกลาวา ต้องกระโดดข้ามหรือเดินอ้อม
local function buildLavaWalk(folder, start, color)
	local length, width = 48, 8
	local y, z = start.Y, start.Z
	platform(folder, Vector3.new(start.X + length / 2, y, z), Vector3.new(length, 1, width), color)

	-- { ระยะจากต้นทาง, ตำแหน่งซ้าย-ขวา, ขนาด }
	local obstacles = {
		{ 8, 0, Vector3.new(2, 1, width) }, -- แถบเต็มทาง ต้องกระโดดข้าม
		{ 16, -2, Vector3.new(4, 3, 4) }, -- ก้อนฝั่งซ้าย เดินอ้อมขวา
		{ 24, 2, Vector3.new(4, 3, 4) }, -- ก้อนฝั่งขวา เดินอ้อมซ้าย
		{ 32, 0, Vector3.new(2, 1, width) },
		{ 40, -3, Vector3.new(2, 3, 2) }, -- เสาสองข้าง ลอดตรงกลาง
		{ 40, 3, Vector3.new(2, 3, 2) },
	}
	for _, o in ipairs(obstacles) do
		killBrick(folder, Vector3.new(start.X + o[1], y + o[3].Y / 2, z + o[2]), o[3])
	end
	return Vector3.new(start.X + length, y, z)
end

-- ด่าน 3: สะพานแคบซิกแซก
local function buildNarrowBeams(folder, start, color)
	local w = 1.5
	local y, z0 = start.Y, start.Z
	local x0 = start.X + 2
	local points = { { 0, 0 }, { 12, 0 }, { 12, 8 }, { 26, 8 }, { 26, -8 }, { 38, -8 }, { 38, 0 }, { 44, 0 } }
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		platform(
			folder,
			Vector3.new(x0 + (a[1] + b[1]) / 2, y, z0 + (a[2] + b[2]) / 2),
			Vector3.new(math.abs(b[1] - a[1]) + w, 1, math.abs(b[2] - a[2]) + w),
			color
		)
	end
	return Vector3.new(x0 + points[#points][1] + w / 2 + 2, y, z0)
end

-- ด่าน 4: พื้นแก้วที่จางหายไปหลังเหยียบ ต้องรีบวิ่งต่อ
local function buildFadingTiles(folder, start, color)
	local sideOffsets = { 0, 2, -2, 0, 2, -2, 0 }
	local x = start.X
	for _, side in ipairs(sideOffsets) do
		x = x + 4
		platform(folder, Vector3.new(x + 2.5, start.Y, start.Z + side), Vector3.new(5, 1, 5), color, {
			Name = "FadingTile",
			Material = Enum.Material.Glass,
			Attributes = { Fade = true },
		})
		x = x + 5
	end
	return Vector3.new(x + 4, start.Y, start.Z)
end

-- ด่าน 5: ปีนบันไดโครงเหล็กขึ้นหอคอย
local function buildTrussTower(folder, start, color)
	local y, z = start.Y, start.Z
	local x0 = start.X + 3
	local climb = 24
	platform(folder, Vector3.new(x0 + 6, y, z), Vector3.new(12, 1, 10), color)
	-- TrussPart ต้องมีขนาดเป็นเลขคู่; สูงกว่าหอคอยนิดหน่อยให้ก้าวขึ้นง่าย
	makePart(folder, {
		ClassName = "TrussPart",
		Name = "ClimbTruss",
		Size = Vector3.new(2, climb + 2, 2),
		CFrame = CFrame.new(x0 + 11, y + (climb + 2) / 2, z),
		Color = WHITE,
		Material = Enum.Material.Metal,
	})
	platform(folder, Vector3.new(x0 + 16, y + climb, z), Vector3.new(8, climb + 20, 8), color, {
		Name = "Tower",
		Material = Enum.Material.Brick,
	})
	return Vector3.new(x0 + 20 + 3, y + climb, z)
end

-- ด่าน 6: แพลตฟอร์มเลื่อนซ้าย-ขวา (ใช้ฟิสิกส์ พาผู้เล่นเคลื่อนไปด้วย)
local function buildMovingPlatforms(folder, start, color)
	local range = 10
	local x = start.X
	for i = 1, 3 do
		x = x + 5
		local mover = platform(folder, Vector3.new(x + 4, start.Y, start.Z), Vector3.new(8, 1, 8), color, {
			Name = "MovingPlatform",
			Anchored = false,
			Attributes = { MoveRange = range, MoveDelay = (i - 1) * 1.2 },
		})
		local anchor = hiddenAnchor(folder, "SliderAnchor", mover.CFrame)
		-- หมุนแกน X ของ Attachment ให้ชี้ไปทาง Z = ทิศที่แพลตฟอร์มเลื่อน
		local slideAxis = CFrame.Angles(0, math.rad(-90), 0)
		create("PrismaticConstraint", {
			Attachment0 = create("Attachment", { CFrame = slideAxis }, anchor),
			Attachment1 = create("Attachment", { CFrame = slideAxis }, mover),
			ActuatorType = Enum.ActuatorType.Servo,
			LimitsEnabled = true,
			LowerLimit = -range,
			UpperLimit = range,
			Speed = 6,
			ServoMaxForce = 1e7,
		}, mover)
		x = x + 8
	end
	return Vector3.new(x + 5, start.Y, start.Z)
end

-- ด่าน 7: พื้นวงกลมที่มีคานลาวาหมุนรอบ ต้องกระโดดข้าม
local function buildSpinner(folder, start, color)
	local radius = 16
	local y, z = start.Y, start.Z
	local center = Vector3.new(start.X + 3 + radius, y, z)
	-- Cylinder มีแกนยาวตามแกน X จึงต้องหมุนให้ตั้งขึ้นเป็นพื้นกลม
	makePart(folder, {
		Name = "SpinnerFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, y - 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
	})
	makePart(folder, {
		Name = "SpinnerPole",
		Size = Vector3.new(3, 6, 3),
		CFrame = CFrame.new(center.X, y + 3, z),
		Color = WHITE,
	})
	local hub = hiddenAnchor(folder, "SpinnerHub", CFrame.new(center.X, y + 1.5, z))
	local bar = makePart(folder, {
		Name = "SpinnerBar",
		Size = Vector3.new(radius * 2, 1.2, 1.2),
		CFrame = hub.CFrame,
		Anchored = false,
		CanCollide = false,
		Color = KILL_COLOR,
		Material = Enum.Material.Neon,
		Attributes = { Kill = true, Spinner = true },
	})
	-- หมุนแกน X ของ Attachment ให้ตั้งขึ้น = แกนหมุนของคาน
	local spinAxis = CFrame.Angles(0, 0, math.rad(90))
	create("HingeConstraint", {
		Attachment0 = create("Attachment", { CFrame = spinAxis }, hub),
		Attachment1 = create("Attachment", { CFrame = spinAxis }, bar),
		ActuatorType = Enum.ActuatorType.Motor,
		AngularVelocity = 1.6,
		MotorMaxTorque = 1e9,
	}, bar)
	return Vector3.new(center.X + radius + 3, y, z)
end

-- ด่าน 8: กระโดดบนเสาเล็ก ๆ ระยะไกล
local function buildPillarJumps(folder, start, color)
	-- { ช่องว่างก่อนถึงเสา, ความสูงเพิ่มจากจุดเริ่ม, ตำแหน่งซ้าย-ขวา }
	local steps = { { 6, 1, 0 }, { 7, 2, 3 }, { 7.5, 2, -2 }, { 6, 3, 1 }, { 7.5, 3, -3 }, { 6, 4, 0 } }
	local x = start.X
	for _, s in ipairs(steps) do
		x = x + s[1]
		platform(folder, Vector3.new(x + 1.5, start.Y + s[2], start.Z + s[3]), Vector3.new(3, 30, 3), color, {
			Name = "Pillar",
		})
		x = x + 3
	end
	return Vector3.new(x + 6, start.Y + 4, start.Z)
end

-- สีพื้นของแต่ละด่านเลี่ยงสีแดง เพราะแดงเรือง = ลาวา (โดนแล้วตาย)
local STAGES = {
	{ title = "กระโดดสบาย ๆ", color = Color3.fromRGB(255, 202, 58), build = buildEasyJumps },
	{ title = "ทางเดินลาวา", color = Color3.fromRGB(90, 175, 255), build = buildLavaWalk },
	{ title = "สะพานแคบ", color = Color3.fromRGB(255, 146, 76), build = buildNarrowBeams },
	{ title = "พื้นแก้วหายได้", color = Color3.fromRGB(150, 225, 255), build = buildFadingTiles },
	{ title = "ปีนหอคอย", color = Color3.fromRGB(38, 196, 185), build = buildTrussTower },
	{ title = "แพลตฟอร์มเลื่อน", color = Color3.fromRGB(80, 100, 230), build = buildMovingPlatforms },
	{ title = "คานหมุนมรณะ", color = Color3.fromRGB(150, 110, 210), build = buildSpinner },
	{ title = "กระโดดเสาขั้นเทพ", color = Color3.fromRGB(241, 91, 181), build = buildPillarJumps },
}

-- ============================================================
-- ล็อบบี้ จุดเซฟ เส้นชัย ลาวา
-- ============================================================

local function buildLobby(folder)
	local size = 40
	platform(folder, Vector3.new(0, BASE_Y, 0), Vector3.new(size, 1, size), Color3.fromRGB(235, 235, 245), {
		Name = "LobbyFloor",
	})
	local spawn = makePart(folder, {
		ClassName = "SpawnLocation",
		Name = "LobbySpawn",
		Size = Vector3.new(10, 0.4, 10),
		CFrame = CFrame.new(0, BASE_Y + 0.2, 0) * FACE_FORWARD,
		Color = CHECKPOINT_COLOR,
		Duration = 0,
		Neutral = true,
		Attributes = { LobbySpawn = true },
	})
	addBillboard(spawn, "🌈 RAINBOW OBBY", "ด่าน 1 • " .. STAGES[1].title .. " →")

	-- เสาไฟสายรุ้งรอบล็อบบี้ (เว้นทางออกด้านหน้าไว้)
	for i, color in ipairs(RAINBOW) do
		local angle = (i - 0.5) / #RAINBOW * math.pi * 2
		local top = Vector3.new(math.cos(angle) * 17, BASE_Y + 8, math.sin(angle) * 17)
		platform(folder, top, Vector3.new(2, 8, 2), color, { Name = "LobbyLight", Material = Enum.Material.Neon })
	end
	return Vector3.new(size / 2, BASE_Y, 0)
end

local function buildCheckpoint(folder, index, edge, nextTitle)
	local checkpoint = makePart(folder, {
		Name = "Checkpoint" .. index,
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(edge.X + 5, edge.Y - 0.5, edge.Z) * FACE_FORWARD,
		Color = CHECKPOINT_COLOR,
		Attributes = { Checkpoint = index },
	})
	addFloorNumber(checkpoint, tostring(index))
	addBillboard(checkpoint, "จุดเซฟ " .. index, "ต่อไป: ด่าน " .. (index + 1) .. " • " .. nextTitle)
	return Vector3.new(edge.X + 10, edge.Y, edge.Z)
end

local function buildFinish(folder, edge)
	local size = 24
	local center = Vector3.new(edge.X + size / 2, edge.Y, edge.Z)
	platform(folder, center, Vector3.new(size, 1, size), GOLD, { Name = "FinishFloor", Material = Enum.Material.Foil })

	local pad = makePart(folder, {
		Name = "WinPad",
		Size = Vector3.new(8, 0.4, 8),
		CFrame = CFrame.new(center.X, center.Y + 0.2, center.Z),
		Color = Color3.fromRGB(255, 230, 120),
		Material = Enum.Material.Neon,
		Attributes = { Finish = true },
	})
	addBillboard(pad, "🏆 เส้นชัย!", "เหยียบแท่นทองเพื่อรับชัยชนะ")
	create("ParticleEmitter", {
		Name = "Confetti",
		Rate = 3,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(30, 45),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -35, 0),
		RotSpeed = NumberRange.new(-180, 180),
		Size = NumberSequence.new(0.7),
		LightEmission = 0.4,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RAINBOW[1]),
			ColorSequenceKeypoint.new(0.5, RAINBOW[4]),
			ColorSequenceKeypoint.new(1, RAINBOW[7]),
		}),
	}, pad)

	-- เสาทองสี่มุม มีไฟสายรุ้งด้านบน
	local corners = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	for i, corner in ipairs(corners) do
		local offset = Vector3.new(corner[1] * (size / 2 - 1.5), 0, corner[2] * (size / 2 - 1.5))
		platform(folder, center + offset + Vector3.new(0, 10, 0), Vector3.new(2, 10, 2), GOLD, { Name = "FinishPillar" })
		platform(folder, center + offset + Vector3.new(0, 11, 0), Vector3.new(2.6, 1, 2.6), RAINBOW[i * 2], {
			Name = "FinishLight",
			Material = Enum.Material.Neon,
		})
	end
	return edge.X + size
end

local function buildLava(folder, mapEndX)
	local length = mapEndX + 200
	makePart(folder, {
		Name = "Lava",
		Size = Vector3.new(length, 2, 400),
		CFrame = CFrame.new(mapEndX / 2, LAVA_Y - 1, 0),
		Color = Color3.fromRGB(255, 90, 0),
		Material = Enum.Material.CrackedLava,
		Attributes = { Kill = true },
	})
end

local function buildMap()
	local map = create("Folder", { Name = MAP_NAME }, nil)
	local edge = buildLobby(create("Folder", { Name = "Lobby" }, map))
	for i, stage in ipairs(STAGES) do
		local folder = create("Folder", { Name = string.format("Stage%02d", i) }, map)
		edge = stage.build(folder, edge, stage.color)
		if i < #STAGES then
			edge = buildCheckpoint(folder, i, edge, STAGES[i + 1].title)
		end
	end
	local mapEndX = buildFinish(create("Folder", { Name = "Finish" }, map), edge)
	buildLava(map, mapEndX)
	-- ใส่เข้า Workspace ทีเดียวตอนท้าย ฟิสิกส์ของชิ้นที่ขยับได้จะได้เริ่มพร้อมกัน
	map.Parent = workspace
	return map
end

-- ============================================================
-- ระบบเกม
-- ============================================================

local checkpoints = {} -- [เลขจุดเซฟ] = Part
local lastCheckpoint = 0
local lobbySpawn = nil

local function getCharacterFromHit(hit)
	local character = hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character, humanoid
	end
	return nil
end

local function getStats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return nil
	end
	return stats:FindFirstChild("Stage"), stats:FindFirstChild("Wins")
end

-- ข้อความเด้งบนจอของผู้เล่นคนเดียว
local function notify(player, text, color)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local old = playerGui:FindFirstChild("ObbyNotice")
	if old then
		old:Destroy()
	end
	local gui = create("ScreenGui", { Name = "ObbyNotice", ResetOnSpawn = false }, playerGui)
	local label = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 0),
		Size = UDim2.new(0.5, 0, 0, 56),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color,
		Text = text,
	}, gui)
	create("UICorner", { CornerRadius = UDim.new(0, 12) }, label)
	Debris:AddItem(gui, 2.5)
end

local function sendToCheckpoint(player)
	local character = player.Character
	local stage = getStats(player)
	if not character or not stage then
		return
	end
	local target = checkpoints[stage.Value] or lobbySpawn
	if target then
		character:PivotTo(target.CFrame + RESPAWN_OFFSET)
	end
end

local function onKillTouched(hit)
	local _, humanoid = getCharacterFromHit(hit)
	if humanoid then
		humanoid.Health = 0
	end
end

local function setupCheckpoint(checkpoint, index)
	checkpoint.Touched:Connect(function(hit)
		local character = getCharacterFromHit(hit)
		local player = character and Players:GetPlayerFromCharacter(character)
		local stage = player and getStats(player)
		-- ต้องผ่านจุดเซฟตามลำดับ ข้ามด่านไม่ได้
		if stage and stage.Value == index - 1 then
			stage.Value = index
			notify(player, "✅ เซฟแล้ว! ผ่านด่าน " .. index, CHECKPOINT_COLOR)
		end
	end)
end

local function setupFadingTile(tile)
	tile.Transparency = 0
	tile.CanCollide = true
	local busy = false
	tile.Touched:Connect(function(hit)
		if busy or not getCharacterFromHit(hit) then
			return
		end
		busy = true
		TweenService:Create(tile, TweenInfo.new(0.8), { Transparency = 0.8 }):Play()
		task.wait(0.8)
		tile.CanCollide = false
		tile.Transparency = 1
		task.wait(2.5)
		tile.Transparency = 0
		tile.CanCollide = true
		busy = false
	end)
end

local function setupMovingPlatform(mover)
	local slider = mover:FindFirstChildOfClass("PrismaticConstraint")
	if not slider then
		return
	end
	-- ให้เซิร์ฟเวอร์คุมฟิสิกส์ ทุกคนจะเห็นแพลตฟอร์มตรงกันไม่กระตุก
	pcall(function()
		mover:SetNetworkOwner(nil)
	end)
	local range = mover:GetAttribute("MoveRange")
	local travelTime = range * 2 / slider.Speed
	task.spawn(function()
		task.wait(mover:GetAttribute("MoveDelay") or 0)
		local target = range
		while mover.Parent do
			slider.TargetPosition = target
			task.wait(travelTime + 1)
			target = -target
		end
	end)
end

local function setupWinPad(pad)
	local confetti = pad:FindFirstChildOfClass("ParticleEmitter")
	pad.Touched:Connect(function(hit)
		local character = getCharacterFromHit(hit)
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local stage, wins = getStats(player)
		if not stage or stage.Value ~= lastCheckpoint then
			return
		end
		stage.Value = 0
		wins.Value = wins.Value + 1
		if confetti then
			confetti:Emit(80)
		end
		notify(player, "🏆 ชนะแล้ว! (รวม " .. wins.Value .. " ครั้ง) กำลังกลับจุดเริ่ม...", GOLD)
		task.delay(3, function()
			if player.Parent then
				sendToCheckpoint(player)
			end
		end)
	end)
end

local function wireMap(map)
	for _, obj in ipairs(map:GetDescendants()) do
		if obj:IsA("BasePart") then
			if obj:GetAttribute("Kill") then
				obj.Touched:Connect(onKillTouched)
			end
			if obj:GetAttribute("Spinner") then
				pcall(function()
					obj:SetNetworkOwner(nil)
				end)
			end
			if obj:GetAttribute("Fade") then
				setupFadingTile(obj)
			end
			if obj:GetAttribute("MoveRange") then
				setupMovingPlatform(obj)
			end
			if obj:GetAttribute("Finish") then
				setupWinPad(obj)
			end
			if obj:GetAttribute("LobbySpawn") then
				lobbySpawn = obj
			end
			local index = obj:GetAttribute("Checkpoint")
			if index then
				checkpoints[index] = obj
				lastCheckpoint = math.max(lastCheckpoint, index)
				setupCheckpoint(obj, index)
			end
		end
	end

	-- ปิดจุดเกิดอื่น (เช่น SpawnLocation ของเทมเพลต Baseplate) ให้ทุกคนเกิดที่ล็อบบี้
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("SpawnLocation") and not obj:IsDescendantOf(map) then
			obj.Enabled = false
		end
	end
end

local function onPlayerAdded(player)
	local stats = create("Folder", { Name = "leaderstats" }, player)
	create("IntValue", { Name = "Stage", Value = 0 }, stats)
	create("IntValue", { Name = "Wins", Value = 0 }, stats)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1) -- รอให้ Roblox วางตัวละครที่จุดเกิดก่อน แล้วค่อยย้ายไปจุดเซฟ
		sendToCheckpoint(player)
	end)
end

-- ============================================================
-- เริ่มเกม
-- ============================================================

Lighting.ClockTime = 14

local map = workspace:FindFirstChild(MAP_NAME) or buildMap()
wireMap(map)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
