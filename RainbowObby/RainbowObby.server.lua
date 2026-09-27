--[[
	🌈 Rainbow Obby 100 — แมพอ็อบบี้ 100 ด่าน ยากขึ้นเรื่อย ๆ สร้างอัตโนมัติ

	มีอะไรบ้าง
	- 100 ด่านไม่ซ้ำกัน จากกลไก 18 แบบ ค่อย ๆ เพิ่มทีละแบบและยากขึ้นตามลำดับ (ง่าย → นรก)
	- จุดเซฟทุกด่าน และบันทึกความคืบหน้า ออกเกมแล้วกลับมาเล่นต่อได้
	- กระดานอันดับ "ผู้ชนะมากที่สุด" ในล็อบบี้
	- ขาย "ข้ามด่าน" ด้วย Robux: ยืนบนจุดเซฟแล้วกด E
	- เพลงประกอบ

	วิธีใช้
	1. Roblox Studio → Explorer → ServerScriptService → + → Script
	2. ลบโค้ดเดิม แล้ววางโค้ดทั้งไฟล์นี้ให้ครบตั้งแต่บรรทัดแรกจนบรรทัดสุดท้าย
	3. กด Play แมพจะถูกสร้างตอนเริ่มเกม

	ก่อนเผยแพร่เกม ดูหัวข้อ "ตั้งค่า" ด้านล่าง และ README.md
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

-- ============================================================
-- ตั้งค่า (แก้ได้)
-- ============================================================

-- เลข Developer Product ของ "ข้ามด่าน" (วิธีสร้างอยู่ใน README.md)
-- 0 = ยังไม่ขาย: ใน Studio กด E ที่จุดเซฟเพื่อข้ามฟรีไว้ทดสอบ ส่วนในเกมจริงจะไม่มีปุ่มข้ามด่าน
local SKIP_STAGE_PRODUCT_ID = 0

-- เพลงประกอบ: ใส่เลข Asset ID ของเพลงจาก Toolbox ได้หลายเพลง จะเล่นวนตามลำดับ
local MUSIC_IDS = {
	127298405859408, -- "Obby Music! Background Song Track Vibe" จาก Creator Store
}
local MUSIC_VOLUME = 0.35

local STAGE_COUNT = 100
local STAGES_PER_ROW = 10 -- แมพวางเป็นแถวซิกแซก แถวละกี่ด่าน
local ROW_SPACING = 70
-- เปลี่ยนเลขนี้จะได้หน้าตาด่านชุดใหม่ (จุดเซฟที่ผู้เล่นบันทึกไว้จะไม่ตรงกับด่านเดิม)
local MAP_SEED = 20260927
local SAVE_NAME = "RainbowObby100" -- ชื่อที่ใช้บันทึกข้อมูลผู้เล่นใน DataStore

-- ============================================================
-- ค่าคงที่
-- ============================================================

local MAP_NAME = "RainbowObby100"
local BASE_Y = 60 -- ความสูงพื้นล็อบบี้
local LAVA_Y = BASE_Y - 40
local FALL_LIMIT = 35 -- ตกต่ำกว่าจุดเซฟเกินนี้ = ตาย จะได้เกิดใหม่เร็ว ไม่ต้องรอตกถึงลาวา
local BOOST_TIME = 3 -- วินาทีที่แท่นกระโดดสูง/แท่นเร่งความเร็วมีผล
local RESPAWN_OFFSET = Vector3.new(0, 4, 0)
local FACE_FORWARD = CFrame.Angles(0, math.rad(-90), 0) -- หันด้านหน้าไปทางที่ผู้เล่นเดิน

-- ค่ามาตรฐานของตัวละคร Roblox ใช้คำนวณว่ากระโดดได้ไกลแค่ไหน
local WALK_SPEED = 16
local JUMP_HEIGHT = 7.2
local GRAVITY = 196.2

local KILL_COLOR = Color3.fromRGB(255, 40, 40)
local CHECKPOINT_COLOR = Color3.fromRGB(120, 230, 150)
local GOLD = Color3.fromRGB(255, 200, 40)
local WHITE = Color3.fromRGB(245, 245, 245)
local WALKWAY_COLOR = Color3.fromRGB(225, 228, 240)
local RAINBOW = {
	Color3.fromRGB(255, 146, 76),
	Color3.fromRGB(255, 202, 58),
	Color3.fromRGB(138, 201, 38),
	Color3.fromRGB(38, 196, 185),
	Color3.fromRGB(25, 130, 196),
	Color3.fromRGB(106, 76, 147),
	Color3.fromRGB(241, 91, 181),
}

local TIERS = {
	{ upTo = 20, name = "ง่าย", color = Color3.fromRGB(140, 235, 140) },
	{ upTo = 40, name = "ปานกลาง", color = Color3.fromRGB(255, 225, 90) },
	{ upTo = 60, name = "ยาก", color = Color3.fromRGB(255, 165, 70) },
	{ upTo = 80, name = "ยากมาก", color = Color3.fromRGB(255, 110, 110) },
	{ upTo = math.huge, name = "นรก", color = Color3.fromRGB(215, 130, 255) },
}

-- ============================================================
-- ตัวช่วยทั่วไป
-- ============================================================

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

local function tierOf(stageIndex)
	for _, tier in ipairs(TIERS) do
		if stageIndex <= tier.upTo then
			return tier
		end
	end
end

-- สีพื้นของแต่ละด่าน ไล่เฉดสายรุ้งแต่เลี่ยงสีแดง (แดงเรือง = ลาวา)
local function stageColor(index)
	local hue = 0.1 + 0.78 * ((index * 0.618034) % 1)
	return Color3.fromHSV(hue, 0.55, 0.95)
end

-- ระยะช่องว่างที่กระโดดข้ามได้อย่างปลอดภัย เมื่อจุดลงสูงกว่าจุดกระโดด rise studs (ติดลบ = กระโดดลง)
local function safeGap(rise, speed)
	local v0 = math.sqrt(2 * GRAVITY * JUMP_HEIGHT)
	local disc = v0 * v0 - 2 * GRAVITY * rise
	if disc < 0 then
		return 0
	end
	local airTime = (v0 + math.sqrt(disc)) / GRAVITY
	return (speed or WALK_SPEED) * airTime * 0.85
end

-- ช่องว่างแนวหน้าระหว่างแท่น ที่ยังกระโดดถึงแม้แท่นจะเยื้องซ้าย-ขวา
-- คืนค่า (ช่องว่างแนวหน้า, ตำแหน่งซ้าย-ขวาที่ปรับให้กระโดดถึงแล้ว)
local function jumpGap(desired, prevZ, prevSize, z, size, rise)
	local reach = safeGap(rise)
	local overlap = (prevSize + size) / 2
	local maxSide = reach * 0.6
	if math.abs(z - prevZ) - overlap > maxSide then
		z = prevZ + (z > prevZ and 1 or -1) * (overlap + maxSide)
	end
	local sideGap = math.max(math.abs(z - prevZ) - overlap, 0)
	local forward = math.sqrt(math.max(reach * reach - sideGap * sideGap, 1))
	return math.min(desired, forward), z
end

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

-- สร้าง Part แบบยึดติด ผิวเรียบ; props.Attributes บอกหน้าที่ของชิ้นส่วนตอนเล่น
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

-- ส่วนที่มองไม่เห็น ใช้เป็นจุดยึดของ constraint
local function hiddenAnchor(parent, name, cframe)
	return makePart(parent, {
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	})
end

local function addBillboard(part, title, subtitle, subtitleColor)
	local gui = create("BillboardGui", {
		Name = "Label",
		Size = UDim2.new(0, 300, 0, 70),
		StudsOffset = Vector3.new(0, 7, 0),
		MaxDistance = 90,
	}, part)
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0.58, 0),
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
			TextColor3 = subtitleColor or Color3.fromRGB(255, 240, 150),
			TextStrokeTransparency = 0.2,
			Text = subtitle,
		}, gui)
	end
end

local function addTopText(part, text)
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
		TextTransparency = 0.3,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
	}, gui)
end

-- ============================================================
-- ตัวช่วยสร้างด่าน
-- ทุกด่านสร้างในพิกัดของด่านเอง: +X = ทางเดินหน้า, +Y = ขึ้น, Z = ซ้าย-ขวา
-- จุด (0, 0, 0) คือขอบหน้าของแท่นก่อนหน้า (ระดับผิวบน)
-- ctx = { folder = โฟลเดอร์ของด่าน, frame = CFrame ของจุดเริ่ม, color = สีด่าน }
-- ============================================================

local function place(ctx, localCFrame, props)
	props.CFrame = ctx.frame * localCFrame
	return makePart(ctx.folder, props)
end

-- แท่นที่ผิวด้านบนอยู่ที่ top พอดี
local function plat(ctx, top, size, props)
	props = props or {}
	props.Size = size
	props.Color = props.Color or ctx.color
	return place(ctx, CFrame.new(top.X, top.Y - size.Y / 2, top.Z), props)
end

local function lava(ctx, center, size)
	return place(ctx, CFrame.new(center), {
		Name = "Lava",
		Size = size,
		Color = KILL_COLOR,
		Material = Enum.Material.Neon,
		Attributes = { Kill = true },
	})
end

local function hazardProps(name)
	return {
		Name = name,
		Color = KILL_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Attributes = { Kill = true },
	}
end

local AXES = {
	X = { vector = Vector3.new(1, 0, 0), rotation = CFrame.new() },
	Y = { vector = Vector3.new(0, 1, 0), rotation = CFrame.Angles(0, 0, math.rad(90)) },
	Z = { vector = Vector3.new(0, 0, 1), rotation = CFrame.Angles(0, math.rad(-90), 0) },
}

-- ชิ้นที่เลื่อนไปมาด้วยฟิสิกส์ระหว่างระยะ a กับ b ตามแกน axis (พาผู้เล่นที่ยืนอยู่ไปด้วย)
local function mover(ctx, top, size, axis, a, b, speed, delayTime, props)
	props = props or {}
	props.Name = props.Name or "MovingPlatform"
	props.Size = size
	props.Anchored = false
	props.Color = props.Color or ctx.color
	props.Attributes = props.Attributes or {}
	props.Attributes.MoveA = a
	props.Attributes.MoveB = b
	props.Attributes.MoveDelay = delayTime
	local home = Vector3.new(top.X, top.Y - size.Y / 2, top.Z)
	local part = place(ctx, CFrame.new(home + AXES[axis].vector * a), props)
	local anchor = hiddenAnchor(ctx.folder, "SliderAnchor", ctx.frame * CFrame.new(home))
	-- หมุนแกน X ของ Attachment ให้ชี้ไปตามแกนที่จะเลื่อน
	local rotation = AXES[axis].rotation
	create("PrismaticConstraint", {
		Attachment0 = create("Attachment", { CFrame = rotation }, anchor),
		Attachment1 = create("Attachment", { CFrame = rotation }, part),
		ActuatorType = Enum.ActuatorType.Servo,
		LimitsEnabled = true,
		LowerLimit = math.min(a, b),
		UpperLimit = math.max(a, b),
		Speed = speed,
		ServoMaxForce = 1e7,
		TargetPosition = a,
	}, part)
	return part
end

-- คานลาวาหมุนรอบจุด center (crossed = คานไขว้เป็นรูป +)
local function spinnerBars(ctx, center, length, speed, crossed)
	local hub = hiddenAnchor(ctx.folder, "SpinnerHub", ctx.frame * CFrame.new(center))
	local function bar(rotation)
		return place(ctx, CFrame.new(center) * rotation, {
			Name = "SpinnerBar",
			Size = Vector3.new(length, 1.2, 1.2),
			Anchored = false,
			CanCollide = false,
			Color = KILL_COLOR,
			Material = Enum.Material.Neon,
			Attributes = { Kill = true, Spinner = true },
		})
	end
	local main = bar(CFrame.new())
	if crossed then
		create("WeldConstraint", { Part0 = main, Part1 = bar(CFrame.Angles(0, math.rad(90), 0)) }, main)
	end
	-- หมุนแกน X ของ Attachment ให้ตั้งขึ้น = แกนหมุนของคาน
	local spinAxis = CFrame.Angles(0, 0, math.rad(90))
	create("HingeConstraint", {
		Attachment0 = create("Attachment", { CFrame = spinAxis }, hub),
		Attachment1 = create("Attachment", { CFrame = spinAxis }, main),
		ActuatorType = Enum.ActuatorType.Motor,
		AngularVelocity = speed,
		MotorMaxTorque = 1e9,
	}, main)
end

local function roundEven(n)
	return 2 * math.floor(n / 2 + 0.5)
end

-- ============================================================
-- กลไกของด่าน 18 แบบ (เรียงตามลำดับที่ผู้เล่นจะได้เจอครั้งแรก)
-- build(ctx, d, rng): d = ความยาก 0 (ด่าน 1) ถึง 1 (ด่าน 100), rng = ตัวสุ่มของด่านนั้น
-- คืนค่าจุดขอบของแท่นถัดไป (จุดเซฟ) ในพิกัดของด่าน
-- ============================================================

local MECHANICS = {
	{
		name = "กระโดดแท่น",
		build = function(ctx, d, rng)
			local count = 5 + math.floor(d * 4)
			local size = lerp(7, 3, d)
			local x, y, z = 0, 0, 0
			local prevZ, prevSize = 0, 10
			for i = 1, count do
				local rise = rng:NextInteger(-1, 2)
				local wantZ = i == count and 0 or clamp(z + rng:NextNumber(-1, 1) * lerp(2, 6, d), -8, 8)
				local gap
				gap, z = jumpGap(lerp(3.5, 7, d), prevZ, prevSize, wantZ, size, rise)
				x = x + gap
				y = y + rise
				local top = Vector3.new(x + size / 2, y, z)
				if d > 0.6 and i < count and rng:NextNumber() < 0.3 then
					local range = lerp(3, 6, d)
					mover(ctx, top, Vector3.new(size, 1, size), "Z", -range, range, lerp(4, 8, d), rng:NextNumber(0, 3))
				else
					-- ด่านยาก ๆ บางแท่นแทบมองไม่เห็น
					local ghost = d > 0.75 and rng:NextNumber() < 0.25
					plat(ctx, top, Vector3.new(size, 1, size), { Transparency = ghost and 0.7 or 0 })
				end
				prevZ, prevSize = z, size
				x = x + size
			end
			local gap = jumpGap(lerp(3.5, 6, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, y, 0)
		end,
	},
	{
		name = "บันไดลอยฟ้า",
		build = function(ctx, d, rng)
			local rise = lerp(1.5, 3.5, d)
			local count = math.min(6 + math.floor(d * 4), math.floor(20 / rise))
			local size = lerp(6, 3, d)
			local x, y, z = 0, 0, 0
			local prevZ, prevSize = 0, 10
			local side = rng:NextNumber() < 0.5 and -1 or 1
			for _ = 1, count do
				side = -side
				local gap
				gap, z = jumpGap(lerp(2, 5.5, d), prevZ, prevSize, side * lerp(1, 4, d), size, rise)
				x = x + gap
				y = y + rise
				plat(ctx, Vector3.new(x + size / 2, y, z), Vector3.new(size, 1, size))
				prevZ, prevSize = z, size
				x = x + size
			end
			local gap = jumpGap(lerp(2, 4, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, y, 0)
		end,
	},
	{
		name = "ทางเดินลาวา",
		build = function(ctx, d, rng)
			local width = lerp(10, 6, d)
			local count = 3 + math.floor(d * 6)
			local spacing = lerp(9, 7, d)
			local length = spacing * (count + 1)
			plat(ctx, Vector3.new(length / 2, 0, 0), Vector3.new(length, 1, width))
			for i = 1, count do
				local x = i * spacing
				local kind = rng:NextInteger(1, d > 0.5 and 4 or 3)
				if kind == 1 then
					-- แถบลาวาเต็มทาง ต้องกระโดดข้าม
					lava(ctx, Vector3.new(x, 0.5, 0), Vector3.new(lerp(2, 3.5, d), 1, width))
				elseif kind == 2 then
					-- ก้อนลาวาครึ่งทาง เดินอ้อม
					local side = rng:NextNumber() < 0.5 and -1 or 1
					local w = math.min(width * lerp(0.5, 0.65, d), width - 2.6)
					lava(ctx, Vector3.new(x, 1.5, side * (width - w) / 2), Vector3.new(3, 3, w))
				elseif kind == 3 then
					-- เสาลาวาสองข้าง ลอดช่องตรงกลาง
					local opening = lerp(4, 2.6, d)
					local w = (width - opening) / 2
					lava(ctx, Vector3.new(x, 1.5, -(opening + w) / 2), Vector3.new(2, 3, w))
					lava(ctx, Vector3.new(x, 1.5, (opening + w) / 2), Vector3.new(2, 3, w))
				else
					-- ก้อนลาวาเลื่อนไปมา รอจังหวะผ่าน
					local range = width / 2 - 1.25
					mover(ctx, Vector3.new(x, 3, 0), Vector3.new(2, 3, 2.5), "Z", -range, range, lerp(4, 9, d),
						rng:NextNumber(0, 3), hazardProps("LavaSlider"))
				end
			end
			return Vector3.new(length, 0, 0)
		end,
	},
	{
		name = "สะพานแคบ",
		build = function(ctx, d, rng)
			local w = lerp(3, 1.1, d)
			local segments = 4 + math.floor(d * 4)
			local function beam(x1, z1, x2, z2)
				plat(ctx, Vector3.new((x1 + x2) / 2, 0, (z1 + z2) / 2),
					Vector3.new(math.abs(x2 - x1) + w, 1, math.abs(z2 - z1) + w))
			end
			local x, z = 1 + w / 2, 0
			for i = 1, segments do
				local len = rng:NextNumber(6, 12)
				if d > 0.5 and len > 8 and rng:NextNumber() < 0.6 then
					-- สะพานขาด ต้องกระโดดข้าม
					local gap = lerp(2, 4.5, d) + w
					local half = (len - gap) / 2
					beam(x, z, x + half, z)
					beam(x + half + gap, z, x + len, z)
				else
					beam(x, z, x + len, z)
					if d > 0.65 and len >= 8 and rng:NextNumber() < 0.5 then
						-- ค้อนลาวายกขึ้นลง ลอดตอนยกขึ้น
						mover(ctx, Vector3.new(x + len / 2, 2.2, z), Vector3.new(2, 2, w + 2), "Y", 0, 7,
							lerp(6, 10, d), rng:NextNumber(0, 2), hazardProps("LavaHammer"))
					end
				end
				x = x + len
				if i < segments then
					local shift = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(4, lerp(6, 10, d))
					local newZ = clamp(z + shift, -11, 11)
					beam(x, z, x, newZ)
					z = newZ
				end
			end
			if z ~= 0 then
				beam(x, z, x, 0)
			end
			beam(x, 0, x + 3, 0)
			return Vector3.new(x + 3 + w / 2 + 2, 0, 0)
		end,
	},
	{
		name = "พื้นแก้วหายได้",
		build = function(ctx, d, rng)
			local count = 6 + math.floor(d * 5)
			local size = lerp(6, 3.5, d)
			local x, z = 0, 0
			local prevZ, prevSize = 0, 10
			for i = 1, count do
				local wantZ = i == count and 0 or clamp(z + rng:NextNumber(-1, 1) * lerp(1, 4, d), -6, 6)
				local gap
				gap, z = jumpGap(lerp(3, 6, d), prevZ, prevSize, wantZ, size, 0)
				x = x + gap
				plat(ctx, Vector3.new(x + size / 2, 0, z), Vector3.new(size, 1, size), {
					Name = "FadingTile",
					Material = Enum.Material.Glass,
					Attributes = { Fade = true, FadeDelay = lerp(1.2, 0.45, d) },
				})
				prevZ, prevSize = z, size
				x = x + size
			end
			local gap = jumpGap(lerp(3, 5, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, 0, 0)
		end,
	},
	{
		name = "ปีนหอคอย",
		build = function(ctx, d, rng)
			local towers = d > 0.5 and 2 or 1
			local x, y = 0, 0
			for _ = 1, towers do
				local climb = roundEven(towers == 1 and lerp(12, 22, d) or lerp(8, 12, d) + rng:NextNumber(0, 2))
				x = x + math.min(lerp(3, 6, d), safeGap(0))
				plat(ctx, Vector3.new(x + 6, y, 0), Vector3.new(12, 1, 10))
				-- TrussPart ต้องมีขนาดเป็นเลขคู่; สูงกว่าหอคอยนิดหน่อยให้ก้าวขึ้นง่าย
				place(ctx, CFrame.new(x + 11, y + (climb + 2) / 2, 0), {
					ClassName = "TrussPart",
					Name = "ClimbTruss",
					Size = Vector3.new(2, climb + 2, 2),
					Color = WHITE,
					Material = Enum.Material.Metal,
				})
				plat(ctx, Vector3.new(x + 16, y + climb, 0), Vector3.new(8, climb + 20, 8), {
					Name = "Tower",
					Material = Enum.Material.Brick,
				})
				x = x + 20
				y = y + climb
			end
			return Vector3.new(x + math.min(lerp(3, 5, d), safeGap(0)), y, 0)
		end,
	},
	{
		name = "แพลตฟอร์มเลื่อนข้าง",
		build = function(ctx, d, rng)
			local count = 3 + math.floor(d * 3)
			local size = lerp(8, 4.5, d)
			local range = lerp(5, 11, d)
			local x = 0
			for _ = 1, count do
				x = x + math.min(lerp(4, 6.5, d), safeGap(0))
				mover(ctx, Vector3.new(x + size / 2, 0, 0), Vector3.new(size, 1, size), "Z", -range, range,
					lerp(4, 10, d), rng:NextNumber(0, 4))
				x = x + size
			end
			return Vector3.new(x + math.min(lerp(4, 6, d), safeGap(0)), 0, 0)
		end,
	},
	{
		name = "กระโดดเสา",
		build = function(ctx, d, rng)
			local count = 5 + math.floor(d * 3)
			local top = lerp(4, 2.2, d)
			local round = d > 0.5
			local x, y, z = 0, 0, 0
			local prevZ, prevSize = 0, 10
			for i = 1, count do
				local rise = rng:NextInteger(0, d > 0.4 and 2 or 1)
				local wantZ = i == count and 0 or clamp(z + rng:NextNumber(-3, 3), -6, 6)
				local gap
				gap, z = jumpGap(lerp(4.5, 7.5, d), prevZ, prevSize, wantZ, top, rise)
				x = x + gap
				y = y + rise
				local props = { Name = "Pillar" }
				if d > 0.75 and rng:NextNumber() < 0.3 then
					props.Material = Enum.Material.Glass
					props.Attributes = { Fade = true, FadeDelay = 0.6 }
				end
				if round then
					-- เสากลม (Cylinder ต้องหมุนให้แกนตั้งขึ้น)
					props.Shape = Enum.PartType.Cylinder
					props.Size = Vector3.new(30, top, top)
					props.Color = ctx.color
					place(ctx, CFrame.new(x + top / 2, y - 15, z) * CFrame.Angles(0, 0, math.rad(90)), props)
				else
					plat(ctx, Vector3.new(x + top / 2, y, z), Vector3.new(top, 30, top), props)
				end
				prevZ, prevSize = z, top
				x = x + top
			end
			local gap = jumpGap(lerp(4, 6, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, y, 0)
		end,
	},
	{
		name = "กระโดดลงแม่น ๆ",
		build = function(ctx, d, rng)
			local count = 4 + math.floor(d * 3)
			local size = lerp(6, 2.5, d)
			local x, y, z = 0, 0, 0
			local prevZ, prevSize = 0, 10
			for i = 1, count do
				local drop = lerp(3, 5, d)
				if y - drop < -22 then
					drop = 0
				end
				local wantZ = i == count and 0 or clamp(z + rng:NextNumber(-4, 4), -8, 8)
				local gap
				gap, z = jumpGap(lerp(3, 6.5, d), prevZ, prevSize, wantZ, size, -drop)
				x = x + gap
				y = y - drop
				plat(ctx, Vector3.new(x + size / 2, y, z), Vector3.new(size, 1, size))
				prevZ, prevSize = z, size
				x = x + size
			end
			local gap = jumpGap(lerp(3, 5, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, y, 0)
		end,
	},
	{
		name = "คานหมุนมรณะ",
		build = function(ctx, d, rng)
			local discs = 1 + math.floor(d * 2.99)
			local radius = lerp(12, 17, d)
			local speed = lerp(1, 2, d) * rng:NextNumber(0.9, 1.1)
			local crossed = d > 0.35
			local x = 0
			for k = 1, discs do
				x = x + 3
				local cx = x + radius
				place(ctx, CFrame.new(cx, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), {
					Name = "SpinnerFloor",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1, radius * 2, radius * 2),
					Color = ctx.color,
				})
				place(ctx, CFrame.new(cx, 3, 0), { Name = "SpinnerPole", Size = Vector3.new(3, 6, 3), Color = WHITE })
				spinnerBars(ctx, Vector3.new(cx, 1.5, 0), radius * 2, k % 2 == 0 and -speed or speed, crossed)
				x = x + radius * 2
			end
			return Vector3.new(x + 3, 0, 0)
		end,
	},
	{
		name = "เขาวงกตลาวา",
		build = function(ctx, d, rng)
			local tile = lerp(5, 4, d)
			local cols = 6 + math.floor(d * 7)
			local rows, mid = 5, 3
			-- สุ่มทางปลอดภัยทีละคอลัมน์ ให้ต่อกันเป็นเส้นเดียวจากกลางถึงกลาง
			local safe = {}
			local row = mid
			for c = 1, cols do
				safe[c] = {}
				local target = c == cols and mid or clamp(row + rng:NextInteger(-2, 2), 1, rows)
				for r = math.min(row, target), math.max(row, target) do
					safe[c][r] = true
				end
				row = target
			end
			for c = 1, cols do
				for r = 1, rows do
					local center = Vector3.new(1 + (c - 0.5) * tile, 0, (r - mid) * tile)
					if safe[c][r] then
						plat(ctx, center, Vector3.new(tile, 1, tile))
					else
						-- ต่ำกว่าพื้นปลอดภัยเล็กน้อย เดินชิดขอบได้โดยไม่โดนลาวา
						lava(ctx, center - Vector3.new(0, 0.8, 0), Vector3.new(tile, 1, tile))
					end
				end
			end
			return Vector3.new(1 + cols * tile + 1, 0, 0)
		end,
	},
	{
		name = "สายพานไหล",
		build = function(ctx, d, rng)
			local width = lerp(10, 6, d)
			local sections = 4 + math.floor(d * 4)
			local x = 0
			for i = 1, sections do
				local len = rng:NextNumber(8, 12)
				local pushX, pushZ = 0, (i % 2 == 0 and 1 or -1) * lerp(6, 12, d)
				if d > 0.6 and rng:NextNumber() < 0.3 then
					pushX, pushZ = -lerp(4, 9, d), 0 -- สายพานดันถอยหลัง
				end
				plat(ctx, Vector3.new(x + len / 2, 0, 0), Vector3.new(len - 0.3, 1, width), {
					Name = "Conveyor",
					Material = Enum.Material.DiamondPlate,
					Color = ctx.color:Lerp(Color3.new(0, 0, 0), 0.35),
					Attributes = { ConveyorX = pushX, ConveyorZ = pushZ },
				})
				x = x + len
			end
			return Vector3.new(x + 1, 0, 0)
		end,
	},
	{
		name = "ลิฟต์ลอยฟ้า",
		build = function(ctx, d, rng)
			local count = d > 0.6 and 3 or 2
			local height = math.min(lerp(6, 10, d), 24 / count)
			local size = lerp(7, 4.5, d)
			local x, y = 0, 0
			for i = 1, count do
				x = x + math.min(lerp(2, 5, d), safeGap(0))
				mover(ctx, Vector3.new(x + size / 2, y, 0), Vector3.new(size, 1, size), "Y", 0, height,
					lerp(4, 8, d), rng:NextNumber(0, 3), { Name = "Elevator" })
				x = x + size
				y = y + height
				x = x + math.min(lerp(2, 5, d), safeGap(0))
				if i < count then
					plat(ctx, Vector3.new(x + 3, y, 0), Vector3.new(6, 1, 6))
					x = x + 6
				end
			end
			return Vector3.new(x, y, 0)
		end,
	},
	{
		name = "แท่นกระโดดสูง",
		build = function(ctx, d, rng)
			local count = d > 0.5 and 3 or 2
			local x, y = 0, 0
			for _ = 1, count do
				plat(ctx, Vector3.new(x + 5, y, 0), Vector3.new(10, 1, 8))
				local pad = plat(ctx, Vector3.new(x + 6.5, y + 0.2, 0), Vector3.new(4, 0.2, 4), {
					Name = "JumpPad",
					Color = Color3.fromRGB(80, 255, 120),
					Material = Enum.Material.Neon,
					Attributes = { JumpBoost = 24 },
				})
				addTopText(pad, "⬆")
				x = x + 10 + lerp(0, 5, d)
				local rise = math.floor(lerp(10, 14, d) + rng:NextNumber(0, 1))
				y = y + rise
				-- ผนังสูงที่กระโดดธรรมดาไม่ถึง ต้องเหยียบแท่นเขียวก่อน
				plat(ctx, Vector3.new(x + 4, y, 0), Vector3.new(8, rise + 6, 8), { Name = "Ledge" })
				x = x + 8
			end
			return Vector3.new(x + 3, y, 0)
		end,
	},
	{
		name = "แพข้ามเหว",
		build = function(ctx, d, rng)
			local legs = d > 0.5 and 2 or 1
			local size = lerp(8, 5, d)
			local x = 0
			for i = 1, legs do
				local span = lerp(16, 28, d)
				local travel = span - size - 2
				mover(ctx, Vector3.new(x + span / 2, 0, 0), Vector3.new(size, 1, size), "X", -travel / 2, travel / 2,
					lerp(5, 10, d), rng:NextNumber(0, 2), { Name = "Ferry" })
				x = x + span
				if i < legs then
					plat(ctx, Vector3.new(x + 4, 0, 0), Vector3.new(8, 1, 8))
					x = x + 8
				end
			end
			return Vector3.new(x, 0, 0)
		end,
	},
	{
		name = "กำแพงลาวากวาด",
		build = function(ctx, d, rng)
			local width = lerp(10, 8, d)
			local count = 2 + math.floor(d * 4)
			local spacing = lerp(10, 8, d)
			local length = spacing * (count + 1)
			plat(ctx, Vector3.new(length / 2, 0, 0), Vector3.new(length, 1, width))
			local range = width / 2 + 1.5
			for i = 1, count do
				mover(ctx, Vector3.new(i * spacing, 8, 0), Vector3.new(1.5, 8, 3), "Z", -range, range,
					lerp(5, 12, d), rng:NextNumber(0, 4), hazardProps("LavaWall"))
			end
			return Vector3.new(length, 0, 0)
		end,
	},
	{
		name = "ทางเร่งความเร็ว",
		build = function(ctx, d, rng)
			local jumps = d > 0.5 and 3 or 2
			local boosted = 30
			local x = 0
			for _ = 1, jumps do
				local strip = plat(ctx, Vector3.new(x + 8, 0, 0), Vector3.new(16, 1, 6), {
					Name = "SpeedStrip",
					Color = Color3.fromRGB(70, 200, 255),
					Material = Enum.Material.Neon,
					Attributes = { SpeedBoost = boosted },
				})
				addTopText(strip, "⚡ ⚡ ⚡")
				-- ช่องว่างที่วิ่งปกติกระโดดไม่ถึง ต้องใช้ความเร็วจากแถบฟ้า
				x = x + 16 + math.min(lerp(10, 13.5, d) + rng:NextNumber(-0.3, 0.3), safeGap(0, boosted))
			end
			return Vector3.new(x, 0, 0)
		end,
	},
	{
		name = "พื้นกะพริบ",
		build = function(ctx, d, rng)
			local count = 6 + math.floor(d * 4)
			local size = lerp(6, 4, d)
			-- พื้นโผล่เป็นระลอกไล่ไปข้างหน้า ต้องเดินตามจังหวะ
			local step = lerp(1, 0.6, d)
			local onTime = step * lerp(3.2, 2.4, d)
			local period = count * step + onTime + 1.5
			local x, z = 0, 0
			local prevZ, prevSize = 0, 10
			for i = 1, count do
				local wantZ = i == count and 0 or clamp(z + rng:NextNumber(-2, 2), -4, 4)
				local gap
				gap, z = jumpGap(lerp(3, 5, d), prevZ, prevSize, wantZ, size, 0)
				x = x + gap
				plat(ctx, Vector3.new(x + size / 2, 0, z), Vector3.new(size, 1, size), {
					Name = "BlinkTile",
					Attributes = { BlinkPeriod = period, BlinkOffset = (i - 1) * step, BlinkOn = onTime },
				})
				prevZ, prevSize = z, size
				x = x + size
			end
			local gap = jumpGap(lerp(3, 5, d), prevZ, prevSize, 0, 10, 0)
			return Vector3.new(x + gap, 0, 0)
		end,
	},
}

-- ลำดับด่าน: ด่าน 1-18 แนะนำกลไกใหม่ทีละแบบ จากนั้นสุ่มสลับแบบคงที่ (ทุกเซิร์ฟเวอร์ได้แมพเหมือนกัน)
-- และไม่ให้กลไกเดียวกันมาติดกันสองด่าน
local function planStages()
	local rng = Random.new(MAP_SEED)
	local order = {}
	for _, mechanic in ipairs(MECHANICS) do
		table.insert(order, mechanic)
	end
	while #order < STAGE_COUNT do
		local round = {}
		for _, mechanic in ipairs(MECHANICS) do
			table.insert(round, mechanic)
		end
		for i = #round, 2, -1 do
			local j = rng:NextInteger(1, i)
			round[i], round[j] = round[j], round[i]
		end
		if round[1] == order[#order] then
			round[1], round[2] = round[2], round[1]
		end
		for _, mechanic in ipairs(round) do
			table.insert(order, mechanic)
		end
	end
	local plan, uses = {}, {}
	for i = 1, STAGE_COUNT do
		local mechanic = order[i]
		uses[mechanic] = (uses[mechanic] or 0) + 1
		plan[i] = { mechanic = mechanic, title = mechanic.name .. " " .. uses[mechanic], tier = tierOf(i) }
	end
	return plan
end

-- ============================================================
-- ล็อบบี้ จุดเซฟ ทางเลี้ยว เส้นชัย ลาวา
-- ============================================================

local function buildLeaderboard(ctx)
	plat(ctx, Vector3.new(0, 1, -22), Vector3.new(22, 1, 3), { Name = "LeaderboardBase", Color = WHITE })
	local board = place(ctx, CFrame.new(0, 7.5, -22) * CFrame.Angles(0, math.pi, 0), {
		Name = "Leaderboard",
		Size = Vector3.new(20, 12, 1),
		Color = Color3.fromRGB(30, 34, 56),
		Attributes = { Leaderboard = true },
	})
	local gui = create("SurfaceGui", {
		Name = "Board",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
	}, board)
	create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0.05, 0, 0.03, 0),
		Size = UDim2.new(0.9, 0, 0.13, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = GOLD,
		Text = "🏆 ผู้ชนะมากที่สุด",
	}, gui)
	for i = 1, 10 do
		create("TextLabel", {
			Name = "Row" .. i,
			Position = UDim2.new(0.06, 0, 0.18 + (i - 1) * 0.072, 0),
			Size = UDim2.new(0.88, 0, 0.066, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = i <= 3 and Color3.fromRGB(255, 235, 160) or WHITE,
			Text = i .. ". -",
		}, gui)
	end
	create("TextLabel", {
		Name = "Footer",
		Position = UDim2.new(0.05, 0, 0.91, 0),
		Size = UDim2.new(0.9, 0, 0.06, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(170, 176, 200),
		Text = "กำลังโหลด...",
	}, gui)
end

local function buildLobby(folder, firstStage)
	local ctx = { folder = folder, frame = CFrame.new(0, BASE_Y, 0), color = WALKWAY_COLOR }
	local size = 48
	plat(ctx, Vector3.new(0, 0, 0), Vector3.new(size, 1, size), { Name = "LobbyFloor" })
	local spawn = place(ctx, CFrame.new(0, 0.2, 0) * FACE_FORWARD, {
		ClassName = "SpawnLocation",
		Name = "LobbySpawn",
		Size = Vector3.new(10, 0.4, 10),
		Color = CHECKPOINT_COLOR,
		Duration = 0,
		Neutral = true,
		Attributes = { LobbySpawn = true },
	})
	addBillboard(spawn, "🌈 RAINBOW OBBY " .. STAGE_COUNT .. " ด่าน",
		"ด่าน 1 • " .. firstStage.title .. " →", firstStage.tier.color)
	for i, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		plat(ctx, Vector3.new(corner[1] * 22, 8, corner[2] * 22), Vector3.new(2, 8, 2), {
			Name = "LobbyLight",
			Color = RAINBOW[i * 2 - 1],
			Material = Enum.Material.Neon,
		})
	end
	buildLeaderboard(ctx)
	return Vector3.new(size / 2, BASE_Y, 0)
end

local function buildCheckpoint(folder, index, cframe, nextStage)
	local checkpoint = makePart(folder, {
		Name = "Checkpoint" .. index,
		Size = Vector3.new(10, 1, 10),
		CFrame = cframe,
		Color = CHECKPOINT_COLOR,
		Attributes = { Checkpoint = index },
	})
	addTopText(checkpoint, tostring(index))
	addBillboard(checkpoint, "จุดเซฟ " .. index,
		"ต่อไป: ด่าน " .. (index + 1) .. " • " .. nextStage.title .. " • " .. nextStage.tier.name, nextStage.tier.color)
	return checkpoint
end

-- จบแถว: ทางเดินเลี้ยวไปแถวถัดไป แล้วหันกลับทางเดิม
local function buildTurn(folder, checkpoint, frame)
	local top = checkpoint.Position + Vector3.new(0, 0.5, 0)
	local turnCenter = top + Vector3.new(0, 0, ROW_SPACING)
	makePart(folder, {
		Name = "Walkway",
		Size = Vector3.new(6, 1, ROW_SPACING - 10),
		CFrame = CFrame.new(top.X, top.Y - 0.5, top.Z + ROW_SPACING / 2),
		Color = WALKWAY_COLOR,
	})
	makePart(folder, {
		Name = "TurnPad",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(turnCenter.X, turnCenter.Y - 0.5, turnCenter.Z),
		Color = WALKWAY_COLOR,
	})
	local wasGoingPositiveX = frame.RightVector.X > 0
	local direction = wasGoingPositiveX and -1 or 1
	local rotation = wasGoingPositiveX and CFrame.Angles(0, math.pi, 0) or CFrame.new()
	return CFrame.new(turnCenter + Vector3.new(5 * direction, 0, 0)) * rotation
end

local function buildFinish(folder, frame)
	local ctx = { folder = folder, frame = frame, color = GOLD }
	local size = 24
	local center = Vector3.new(size / 2, 0, 0)
	plat(ctx, center, Vector3.new(size, 1, size), { Name = "FinishFloor", Material = Enum.Material.Foil })
	local pad = plat(ctx, center + Vector3.new(0, 0.4, 0), Vector3.new(8, 0.4, 8), {
		Name = "WinPad",
		Color = Color3.fromRGB(255, 230, 120),
		Material = Enum.Material.Neon,
		Attributes = { Finish = true },
	})
	addBillboard(pad, "🏆 เส้นชัย!", "เหยียบแท่นทองเพื่อรับชัยชนะ", GOLD)
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
	for i, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local offset = Vector3.new(corner[1] * (size / 2 - 1.5), 0, corner[2] * (size / 2 - 1.5))
		plat(ctx, center + offset + Vector3.new(0, 10, 0), Vector3.new(2, 10, 2), { Name = "FinishPillar" })
		plat(ctx, center + offset + Vector3.new(0, 11, 0), Vector3.new(2.6, 1, 2.6), {
			Name = "FinishLight",
			Color = RAINBOW[i + 1],
			Material = Enum.Material.Neon,
		})
	end
	return frame * center
end

local function buildLava(folder, minX, maxX, minZ, maxZ)
	local margin = 80
	makePart(folder, {
		Name = "LavaSea",
		Size = Vector3.new(math.min(maxX - minX + margin * 2, 2048), 2, math.min(maxZ - minZ + margin * 2, 2048)),
		CFrame = CFrame.new((minX + maxX) / 2, LAVA_Y - 1, (minZ + maxZ) / 2),
		Color = Color3.fromRGB(255, 90, 0),
		Material = Enum.Material.CrackedLava,
		Attributes = { Kill = true },
	})
end

local function buildMap()
	local map = create("Folder", { Name = MAP_NAME }, nil)
	local plan = planStages()
	local lobbyEdge = buildLobby(create("Folder", { Name = "Lobby" }, map), plan[1])
	local frame = CFrame.new(lobbyEdge)
	local minX, maxX, minZ, maxZ = -30, 30, -30, 30
	local function track(position)
		minX, maxX = math.min(minX, position.X - 30), math.max(maxX, position.X + 30)
		minZ, maxZ = math.min(minZ, position.Z - 30), math.max(maxZ, position.Z + 30)
	end
	for i = 1, STAGE_COUNT do
		local folder = create("Folder", { Name = string.format("Stage%03d", i) }, map)
		local ctx = { folder = folder, frame = frame, color = stageColor(i) }
		local d = (i - 1) / math.max(STAGE_COUNT - 1, 1)
		local finish = plan[i].mechanic.build(ctx, d, Random.new(MAP_SEED + i * 7919))
		if i < STAGE_COUNT then
			local checkpoint = buildCheckpoint(folder, i,
				frame * CFrame.new(finish.X + 5, finish.Y - 0.5, 0) * FACE_FORWARD, plan[i + 1])
			track(checkpoint.Position)
			frame = frame * CFrame.new(finish.X + 10, finish.Y, 0)
			if i % STAGES_PER_ROW == 0 then
				frame = buildTurn(folder, checkpoint, frame)
				track(frame.Position)
			end
		else
			track(buildFinish(create("Folder", { Name = "Finish" }, map), frame * CFrame.new(finish.X, finish.Y, 0)))
		end
	end
	buildLava(map, minX, maxX, minZ, maxZ)
	-- ใส่เข้า Workspace ทีเดียวตอนท้าย ฟิสิกส์ของชิ้นที่ขยับได้จะเริ่มพร้อมกัน
	map.Parent = workspace
	return map
end

-- ============================================================
-- ระบบเกม
-- ============================================================

local checkpoints = {} -- [เลขจุดเซฟ] = Part
local lastCheckpoint = 0
local lobbySpawn = nil
local leaderboardGui = nil
local movers = {}
local blinkTiles = {}
local skipEnabled = SKIP_STAGE_PRODUCT_ID ~= 0 or RunService:IsStudio()

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

local function currentTarget(player)
	local stage = getStats(player)
	return stage and checkpoints[stage.Value] or lobbySpawn
end

local function sendToCheckpoint(player)
	local character = player.Character
	local target = currentTarget(player)
	if character and target and getStats(player) then
		character:PivotTo(target.CFrame + RESPAWN_OFFSET)
	end
end

-- ---------------- บันทึกข้อมูล ----------------

local progressStore, winsStore
do
	local ok, err = pcall(function()
		progressStore = DataStoreService:GetDataStore(SAVE_NAME .. "_Progress")
		winsStore = DataStoreService:GetOrderedDataStore(SAVE_NAME .. "_Wins")
	end)
	if not ok then
		progressStore, winsStore = nil, nil
		warn("🌈 Rainbow Obby: ใช้ DataStore ไม่ได้ (" .. tostring(err) .. ")")
	end
end

local loadedPlayers = {}
local dataWarned = false

local function warnData(err)
	if not dataWarned then
		dataWarned = true
		warn("🌈 Rainbow Obby: บันทึก/โหลดข้อมูลไม่ได้ (" .. tostring(err) .. ")"
			.. " ถ้าทดสอบใน Studio ให้เปิด Game Settings → Security → Enable Studio Access to API Services")
	end
end

local function dataKey(userId)
	return "u_" .. userId
end

local function loadPlayer(player)
	if not progressStore then
		return
	end
	local ok, data = pcall(function()
		return progressStore:GetAsync(dataKey(player.UserId))
	end)
	if not ok then
		warnData(data)
		return
	end
	if not player.Parent then
		return
	end
	loadedPlayers[player] = true
	local stage, wins = getStats(player)
	if type(data) ~= "table" or not stage then
		return
	end
	wins.Value = math.max(wins.Value, math.floor(tonumber(data.wins) or 0))
	local savedStage = clamp(math.floor(tonumber(data.stage) or 0), 0, lastCheckpoint)
	if savedStage > stage.Value then
		stage.Value = savedStage
		sendToCheckpoint(player)
		notify(player, "▶ เล่นต่อจากจุดเซฟ " .. savedStage, CHECKPOINT_COLOR)
	end
end

local function savePlayer(player)
	-- ถ้าโหลดไม่สำเร็จจะไม่บันทึกทับ กันข้อมูลเดิมหาย
	if not progressStore or not loadedPlayers[player] then
		return
	end
	local stage, wins = getStats(player)
	if not stage then
		return
	end
	local key = dataKey(player.UserId)
	local ok, err = pcall(function()
		progressStore:SetAsync(key, { stage = stage.Value, wins = wins.Value })
	end)
	if not ok then
		warnData(err)
	end
	if winsStore and wins.Value > 0 then
		pcall(function()
			winsStore:SetAsync(key, wins.Value)
		end)
	end
end

-- ---------------- กระดานอันดับ ----------------

local nameCache = {}
local lastBoardRefresh = -math.huge

local function nameOf(userId)
	if not nameCache[userId] then
		local player = Players:GetPlayerByUserId(userId)
		local name = player and player.Name
		if not name then
			local ok, result = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			name = ok and result or ("ผู้เล่น " .. userId)
		end
		nameCache[userId] = name
	end
	return nameCache[userId]
end

local function refreshLeaderboard()
	if not leaderboardGui then
		return
	end
	lastBoardRefresh = os.clock()
	local entries, global = {}, false
	if winsStore then
		local ok, pages = pcall(function()
			return winsStore:GetSortedAsync(false, 10)
		end)
		if ok then
			global = true
			for _, item in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(string.match(item.key, "%-?%d+"))
				if userId then
					table.insert(entries, { name = nameOf(userId), wins = item.value })
				end
			end
		end
	end
	if not global then
		-- ยังใช้ DataStore ไม่ได้: แสดงเฉพาะคนในเซิร์ฟเวอร์นี้
		for _, player in ipairs(Players:GetPlayers()) do
			local _, wins = getStats(player)
			if wins and wins.Value > 0 then
				table.insert(entries, { name = player.Name, wins = wins.Value })
			end
		end
		table.sort(entries, function(a, b)
			return a.wins > b.wins
		end)
	end
	for i = 1, 10 do
		local row = leaderboardGui:FindFirstChild("Row" .. i)
		local entry = entries[i]
		if row then
			row.Text = entry and string.format("%d. %s — ชนะ %d ครั้ง", i, entry.name, entry.wins) or (i .. ". -")
		end
	end
	local footer = leaderboardGui:FindFirstChild("Footer")
	if footer then
		footer.Text = global and "อันดับจากทุกเซิร์ฟเวอร์ • อัปเดตทุก 1 นาที"
			or "อันดับในเซิร์ฟเวอร์นี้ (ยังไม่ได้เปิดการบันทึกข้อมูล)"
	end
end

local function requestBoardRefresh()
	if os.clock() - lastBoardRefresh > 10 then
		task.delay(1, refreshLeaderboard)
	end
end

-- ---------------- ข้ามด่าน ----------------

local function skipStage(player)
	local stage = getStats(player)
	if not stage or stage.Value >= lastCheckpoint then
		return false
	end
	stage.Value = stage.Value + 1
	sendToCheckpoint(player)
	notify(player, "⏭ ข้ามไปจุดเซฟ " .. stage.Value .. " แล้ว!", GOLD)
	task.spawn(savePlayer, player)
	return true
end

local function onSkipPrompt(player)
	local stage = getStats(player)
	if not stage then
		return
	end
	if stage.Value >= lastCheckpoint then
		notify(player, "ด่านสุดท้ายต้องผ่านเอง สู้ ๆ! 💪", GOLD)
	elseif SKIP_STAGE_PRODUCT_ID ~= 0 then
		MarketplaceService:PromptProductPurchase(player, SKIP_STAGE_PRODUCT_ID)
	else
		skipStage(player) -- โหมดทดสอบใน Studio: ข้ามฟรี
	end
end

if SKIP_STAGE_PRODUCT_ID ~= 0 then
	local granted = {}
	MarketplaceService.ProcessReceipt = function(receipt)
		if receipt.ProductId ~= SKIP_STAGE_PRODUCT_ID then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not granted[receipt.PurchaseId] then
			local player = Players:GetPlayerByUserId(receipt.PlayerId)
			if not player then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			skipStage(player)
			granted[receipt.PurchaseId] = true
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

-- ---------------- ชิ้นส่วนในด่าน ----------------

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
			notify(player, "✅ ผ่านด่าน " .. index .. " แล้ว!", CHECKPOINT_COLOR)
		end
	end)
end

local function setupSkipPrompt(part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not skipEnabled then
		if prompt then
			prompt:Destroy()
		end
		return
	end
	prompt = prompt or create("ProximityPrompt", {
		ActionText = "ข้ามด่าน",
		ObjectText = SKIP_STAGE_PRODUCT_ID ~= 0 and "⏭ ใช้ Robux" or "⏭ ทดสอบ (ฟรีใน Studio)",
		HoldDuration = 0.3,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
	}, part)
	prompt.Triggered:Connect(onSkipPrompt)
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
		local delayTime = tile:GetAttribute("FadeDelay") or 0.8
		TweenService:Create(tile, TweenInfo.new(delayTime), { Transparency = 0.8 }):Play()
		task.wait(delayTime)
		tile.CanCollide = false
		tile.Transparency = 1
		task.wait(2.5)
		tile.Transparency = 0
		tile.CanCollide = true
		busy = false
	end)
end

local function registerMover(part)
	local slider = part:FindFirstChildOfClass("PrismaticConstraint")
	if not slider then
		return
	end
	-- ให้เซิร์ฟเวอร์คุมฟิสิกส์ ทุกคนจะเห็นตรงกันไม่กระตุก
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	local a, b = part:GetAttribute("MoveA"), part:GetAttribute("MoveB")
	table.insert(movers, {
		slider = slider,
		a = a,
		b = b,
		delay = part:GetAttribute("MoveDelay") or 0,
		pause = part:GetAttribute("MovePause") or 1,
		travel = math.abs(b - a) / slider.Speed,
	})
end

local function registerBlinkTile(tile)
	table.insert(blinkTiles, {
		part = tile,
		period = tile:GetAttribute("BlinkPeriod"),
		offset = tile:GetAttribute("BlinkOffset") or 0,
		on = tile:GetAttribute("BlinkOn"),
	})
end

local function setupConveyor(belt)
	local push = Vector3.new(belt:GetAttribute("ConveyorX") or 0, 0, belt:GetAttribute("ConveyorZ") or 0)
	belt.AssemblyLinearVelocity = belt.CFrame:VectorToWorldSpace(push)
end

local function resetBoost(humanoid, kind)
	if kind == "Jump" then
		humanoid.JumpPower = StarterPlayer.CharacterJumpPower
		humanoid.JumpHeight = StarterPlayer.CharacterJumpHeight
	else
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
	end
end

local function applyBoost(humanoid, kind, value)
	local key = kind .. "BoostUntil"
	local now = os.clock()
	local current = humanoid:GetAttribute(key)
	if current and current - now > BOOST_TIME - 0.5 then
		return -- เพิ่งได้รับไป
	end
	humanoid:SetAttribute(key, now + BOOST_TIME)
	if kind == "Jump" then
		if humanoid.UseJumpPower then
			humanoid.JumpPower = math.sqrt(2 * workspace.Gravity * value)
		else
			humanoid.JumpHeight = value
		end
	else
		humanoid.WalkSpeed = value
	end
	task.delay(BOOST_TIME + 0.1, function()
		local untilTime = humanoid:GetAttribute(key)
		if humanoid.Parent and untilTime and untilTime <= os.clock() then
			humanoid:SetAttribute(key, nil)
			resetBoost(humanoid, kind)
		end
	end)
end

local function setupBoostPad(pad)
	local kind = pad:GetAttribute("JumpBoost") and "Jump" or "Speed"
	local value = pad:GetAttribute("JumpBoost") or pad:GetAttribute("SpeedBoost")
	pad.Touched:Connect(function(hit)
		local _, humanoid = getCharacterFromHit(hit)
		if humanoid then
			applyBoost(humanoid, kind, value)
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
		notify(player, "🏆 ผ่านครบ " .. STAGE_COUNT .. " ด่าน! ชนะครั้งที่ " .. wins.Value, GOLD)
		task.spawn(savePlayer, player)
		requestBoardRefresh()
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
			if obj:GetAttribute("MoveA") then
				registerMover(obj)
			end
			if obj:GetAttribute("BlinkPeriod") then
				registerBlinkTile(obj)
			end
			if obj:GetAttribute("ConveyorX") or obj:GetAttribute("ConveyorZ") then
				setupConveyor(obj)
			end
			if obj:GetAttribute("JumpBoost") or obj:GetAttribute("SpeedBoost") then
				setupBoostPad(obj)
			end
			if obj:GetAttribute("Finish") then
				setupWinPad(obj)
			end
			if obj:GetAttribute("Leaderboard") then
				leaderboardGui = obj:FindFirstChild("Board")
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

	-- ปุ่มข้ามด่าน (กด E) ที่จุดเกิดและทุกจุดเซฟ ยกเว้นก่อนด่านสุดท้าย
	if lobbySpawn then
		setupSkipPrompt(lobbySpawn)
	end
	for index, checkpoint in pairs(checkpoints) do
		if index < lastCheckpoint then
			setupSkipPrompt(checkpoint)
		end
	end

	-- ปิดจุดเกิดอื่น (เช่น SpawnLocation ของเทมเพลต Baseplate) ให้ทุกคนเกิดที่ล็อบบี้
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("SpawnLocation") and not obj:IsDescendantOf(map) then
			obj.Enabled = false
		end
	end
end

-- แพลตฟอร์มเลื่อน + พื้นกะพริบ อัปเดตทุก 0.1 วินาทีจากเวลาเดียวกัน
local function runMachines()
	while true do
		local now = os.clock()
		for _, m in ipairs(movers) do
			local half = m.travel + m.pause
			local target = (now + m.delay) % (half * 2) < half and m.b or m.a
			if m.slider.TargetPosition ~= target then
				m.slider.TargetPosition = target
			end
		end
		for _, tile in ipairs(blinkTiles) do
			local phase = (now - tile.offset) % tile.period
			local solid = phase < tile.on
			tile.part.CanCollide = solid
			if not solid then
				tile.part.Transparency = 0.9
			elseif tile.on - phase < 0.5 then
				tile.part.Transparency = 0.5 -- ใกล้หายแล้ว
			else
				tile.part.Transparency = 0
			end
		end
		task.wait(0.1)
	end
end

-- ตกต่ำกว่าจุดเซฟมาก ๆ ให้ตายเลย ไม่ต้องรอตกถึงลาวา
local function runFallCheck()
	while true do
		task.wait(0.25)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local spawnedAt = character and character:GetAttribute("SpawnedAt")
			local target = currentTarget(player)
			if root and humanoid and humanoid.Health > 0 and target and spawnedAt and os.clock() - spawnedAt > 2 then
				if root.Position.Y < target.Position.Y - FALL_LIMIT then
					humanoid.Health = 0
				end
			end
		end
	end
end

-- ---------------- เพลง ----------------

local function startMusic()
	if #MUSIC_IDS == 0 then
		return
	end
	local sound = create("Sound", {
		Name = "ObbyMusic",
		Volume = MUSIC_VOLUME,
		Looped = #MUSIC_IDS == 1,
	}, SoundService)
	task.spawn(function()
		while true do
			for _, id in ipairs(MUSIC_IDS) do
				sound.SoundId = string.format("rbxassetid://%d", id)
				sound:Play()
				local waited = 0
				while not sound.IsLoaded and waited < 8 do
					waited = waited + task.wait(0.5)
				end
				if not sound.IsLoaded then
					warn("🌈 Rainbow Obby: โหลดเพลง " .. string.format("%d", id) .. " ไม่ได้ ลองเปลี่ยนเลขใน MUSIC_IDS (เลือกเพลงจาก Toolbox)")
				end
				if #MUSIC_IDS == 1 then
					return -- เพลงเดียว: เล่นวนไปเรื่อย ๆ
				end
				local length = sound.TimeLength > 0 and sound.TimeLength or 120
				local elapsed = 0
				while sound.IsPlaying and elapsed < length + 2 do
					elapsed = elapsed + task.wait(1)
				end
			end
		end
	end)
end

-- ---------------- ผู้เล่น ----------------

local function onCharacterAdded(player, character)
	character:SetAttribute("SpawnedAt", os.clock())
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.1) -- รอให้ Roblox วางตัวละครที่จุดเกิดก่อน แล้วค่อยย้ายไปจุดเซฟ
	sendToCheckpoint(player)
end

local function onPlayerAdded(player)
	local stats = create("Folder", { Name = "leaderstats" }, player)
	create("IntValue", { Name = "Stage", Value = 0 }, stats)
	create("IntValue", { Name = "Wins", Value = 0 }, stats)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	task.spawn(loadPlayer, player)
end

local function onPlayerRemoving(player)
	savePlayer(player)
	loadedPlayers[player] = nil
end

-- ============================================================
-- เริ่มเกม
-- ============================================================

print("🌈 Rainbow Obby: กำลังโหลดแมพ " .. STAGE_COUNT .. " ด่าน...")
Lighting.ClockTime = 14
if workspace:FindFirstChild("RainbowObby") then
	warn("🌈 Rainbow Obby: เจอแมพเวอร์ชันเก่า (RainbowObby) ใน Workspace ลบทิ้งได้เลย จะได้ไม่ทับกัน")
end

local map = workspace:FindFirstChild(MAP_NAME) or buildMap()
wireMap(map)
task.spawn(runMachines)
task.spawn(runFallCheck)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending = pending + 1
		task.spawn(function()
			savePlayer(player)
			pending = pending - 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < 25 do
		waited = waited + task.wait(0.5)
	end
end)

task.spawn(function()
	while true do
		refreshLeaderboard()
		task.wait(60)
	end
end)

task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(savePlayer, player)
		end
	end
end)

startMusic()

print(("🌈 Rainbow Obby: พร้อมเล่นแล้ว! %d ด่าน • ข้ามด่าน: %s • บันทึกข้อมูล: %s"):format(
	STAGE_COUNT,
	SKIP_STAGE_PRODUCT_ID ~= 0 and "ขายด้วย Robux" or (skipEnabled and "ฟรี (โหมดทดสอบใน Studio)" or "ปิด"),
	progressStore and "เปิด" or "ปิด"
))
