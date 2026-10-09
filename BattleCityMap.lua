-- Script (ฝั่ง Server): สร้างแมพสไตล์ Battle City จากตารางตัวอักษร
-- วางไว้ที่ ServerScriptService แล้วกด Play — แมพจะถูกสร้างไว้ที่ workspace.BattleCityMap
-- แก้ด่านได้ที่ LAYOUT ด้านล่าง (ทุกแถวต้องยาวเท่ากัน)
-- ใช้คู่กับ BattleCityCamera.lua (กล้องมองจากด้านบนแบบเกมต้นฉบับ)

local PhysicsService = game:GetService("PhysicsService")

local TILE = 8         -- ขนาด 1 ช่อง (stud)
local WALL_HEIGHT = 6  -- ความสูงกำแพง (ต้องสูงกว่ารถถัง ป่าจะได้บังรถถังได้)
local FLOOR_Y = 1      -- ความสูงผิวพื้นแมพ (สูงกว่า Baseplate 1 stud กันภาพกระพริบ)
local CORNER = Vector3.new(0, 0, 0) -- มุมซ้ายบนของแมพ (ใช้แค่ X กับ Z)

-- ความหมายของตัวอักษร
--   .  ทางว่าง
--   B  กำแพงอิฐ (ยิงพังได้ แบ่งเป็น 4 ก้อนย่อยเหมือนต้นฉบับ)
--   S  กำแพงเหล็ก (ยิงพังได้เฉพาะรถถังดาว 3 ดวง)
--   W  น้ำ (รถถังข้ามไม่ได้ แต่กระสุนบินผ่านได้)
--   T  ป่า (บังรถถังจากกล้องด้านบน ขับทะลุได้)
--   I  น้ำแข็ง (พื้นลื่น)
--   E  ฐานนกอินทรี
--   P  จุดเกิดผู้เล่น
--   N  จุดเกิดรถถังศัตรู
local LAYOUT = {
	"N.....N.....N",
	".B.B.B.B.B.B.",
	".B.B.B.B.B.B.",
	".B.B.BSB.B.B.",
	".B.B.III.B.B.",
	"TT...B.B...TT",
	"S.BB.....BB.S",
	"..W..B.B..W..",
	".B.B.BBB.B.B.",
	".B.B.B.B.B.B.",
	".B.B.....B.B.",
	".B.B.BBB.B.B.",
	"....PBEBP....",
}

local rows = #LAYOUT
local cols = #LAYOUT[1]
for i, line in ipairs(LAYOUT) do
	assert(#line == cols, ("LAYOUT แถวที่ %d ยาว %d ตัว แต่ควรยาว %d ตัว"):format(i, #line, cols))
end

-- น้ำ: รถถังชน แต่กระสุนไม่ชน
-- (ตอนเขียนระบบกระสุน ให้ตั้ง RaycastParams.CollisionGroup = "Bullet")
for _, group in ipairs({ "Water", "Bullet" }) do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end
PhysicsService:CollisionGroupSetCollidable("Water", "Bullet", false)

local mapWidth = cols * TILE
local mapDepth = rows * TILE
local mapCenter = Vector3.new(CORNER.X + mapWidth / 2, FLOOR_Y, CORNER.Z + mapDepth / 2)
local wallY = FLOOR_Y + WALL_HEIGHT / 2
local half = TILE / 2

local oldMap = workspace:FindFirstChild("BattleCityMap")
if oldMap then
	oldMap:Destroy()
end

local mapFolder = Instance.new("Folder")
mapFolder.Name = "BattleCityMap"
-- ให้ฝั่ง Client (กล้อง) รู้ว่าแมพอยู่ตรงไหน ใหญ่แค่ไหน
mapFolder:SetAttribute("Center", mapCenter)
mapFolder:SetAttribute("Size", Vector3.new(mapWidth, 0, mapDepth))

-- สร้าง Part แล้วติด Tag ตามชื่อ ระบบอื่นจะได้เช็กง่าย ๆ เช่น hit:HasTag("Brick")
local function makePart(name, size, position, props, className)
	local part = Instance.new(className or "Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part:AddTag(name)
	part.Parent = mapFolder
	return part
end

local function tileCenter(row, col, y)
	return Vector3.new(CORNER.X + (col - 0.5) * TILE, y, CORNER.Z + (row - 0.5) * TILE)
end

local BRICK_OFFSETS = {
	Vector3.new(-1, 0, -1),
	Vector3.new(1, 0, -1),
	Vector3.new(-1, 0, 1),
	Vector3.new(1, 0, 1),
}

local builders = {
	B = function(row, col)
		-- อิฐ 1 ช่อง = 4 ก้อนย่อย ยิงโดนก้อนไหนก็พังเฉพาะก้อนนั้น
		for _, offset in ipairs(BRICK_OFFSETS) do
			makePart("Brick", Vector3.new(half, WALL_HEIGHT, half), tileCenter(row, col, wallY) + offset * (half / 2), {
				Color = Color3.fromRGB(176, 88, 40),
				Material = Enum.Material.Brick,
			})
		end
	end,

	S = function(row, col)
		makePart("Steel", Vector3.new(TILE, WALL_HEIGHT, TILE), tileCenter(row, col, wallY), {
			Color = Color3.fromRGB(190, 190, 200),
			Material = Enum.Material.DiamondPlate,
		})
	end,

	W = function(row, col)
		makePart("Water", Vector3.new(TILE, 0.4, TILE), tileCenter(row, col, FLOOR_Y + 0.2), {
			Color = Color3.fromRGB(40, 100, 220),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		-- ผนังล่องหนกันรถถังขับลงน้ำ
		makePart("WaterBarrier", Vector3.new(TILE, WALL_HEIGHT, TILE), tileCenter(row, col, wallY), {
			Transparency = 1,
			CollisionGroup = "Water",
		})
	end,

	T = function(row, col)
		-- ป่าลอยอยู่เหนือหัวรถถัง กล้องด้านบนจะมองไม่เห็นรถถังที่ซ่อนอยู่ข้างใต้
		makePart("Forest", Vector3.new(TILE, 1, TILE), tileCenter(row, col, FLOOR_Y + WALL_HEIGHT + 0.5), {
			Color = Color3.fromRGB(46, 140, 46),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end,

	I = function(row, col)
		makePart("Ice", Vector3.new(TILE, 0.1, TILE), tileCenter(row, col, FLOOR_Y + 0.05), {
			Color = Color3.fromRGB(200, 230, 255),
			Material = Enum.Material.Ice,
			-- แรงเสียดทาน 0 = ลื่น (มีผลกับรถถังที่ขับด้วยฟิสิกส์)
			CustomPhysicalProperties = PhysicalProperties.new(0.9, 0, 0, 100, 1),
		})
	end,

	E = function(row, col)
		local base = makePart("Base", Vector3.new(TILE, WALL_HEIGHT, TILE), tileCenter(row, col, wallY), {
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Neon,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.Parent = base
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "🦅"
		label.TextScaled = true
		label.Parent = gui
	end,

	P = function(row, col)
		makePart("PlayerSpawn", Vector3.new(TILE, 0.2, TILE), tileCenter(row, col, FLOOR_Y + 0.1), {
			Color = Color3.fromRGB(255, 220, 0),
			Transparency = 0.3,
			Neutral = true,
		}, "SpawnLocation")
	end,

	N = function(row, col)
		makePart("EnemySpawn", Vector3.new(TILE, 0.2, TILE), tileCenter(row, col, FLOOR_Y + 0.1), {
			Color = Color3.fromRGB(220, 50, 50),
			Transparency = 0.5,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end,
}

-- พื้นสีดำแบบต้นฉบับ
makePart("Floor", Vector3.new(mapWidth, 1, mapDepth), mapCenter - Vector3.new(0, 0.5, 0), {
	Color = Color3.fromRGB(15, 15, 15),
	Material = Enum.Material.SmoothPlastic,
})

-- ขอบแมพ 4 ด้าน (ยิงไม่พัง)
local border = half
local borderProps = {
	Color = Color3.fromRGB(120, 120, 120),
	Material = Enum.Material.Slate,
}
makePart("Border", Vector3.new(mapWidth + 2 * border, WALL_HEIGHT, border), Vector3.new(mapCenter.X, wallY, CORNER.Z - border / 2), borderProps)
makePart("Border", Vector3.new(mapWidth + 2 * border, WALL_HEIGHT, border), Vector3.new(mapCenter.X, wallY, CORNER.Z + mapDepth + border / 2), borderProps)
makePart("Border", Vector3.new(border, WALL_HEIGHT, mapDepth), Vector3.new(CORNER.X - border / 2, wallY, mapCenter.Z), borderProps)
makePart("Border", Vector3.new(border, WALL_HEIGHT, mapDepth), Vector3.new(CORNER.X + mapWidth + border / 2, wallY, mapCenter.Z), borderProps)

for row, line in ipairs(LAYOUT) do
	for col = 1, cols do
		local char = line:sub(col, col)
		local build = builders[char]
		if build then
			build(row, col)
		elseif char ~= "." then
			warn(("ไม่รู้จักตัวอักษร '%s' ที่แถว %d ช่อง %d"):format(char, row, col))
		end
	end
end

-- ใส่เข้า workspace ทีเดียวตอนสร้างเสร็จ ผู้เล่นจะได้เห็นแมพครบในครั้งเดียว
mapFolder.Parent = workspace
print(("✅ สร้างแมพ Battle City แล้ว (%d x %d ช่อง)"):format(cols, rows))
