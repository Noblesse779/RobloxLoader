--[[
	MapBuilder : สร้างแมพทั้งหมดด้วยโค้ด (ล็อบบี้, ด่าน 1-4, หน้าจบ)
	ทุกอย่างอยู่ใน workspace.HorrorMap
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("HorrorShared"):WaitForChild("Config"))

local MapBuilder = {}

local M = Enum.Material
local FLICKER_TAG = "HorrorFlicker"

-- ================= Helpers =================

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function invisible(parent, size, cf, collide)
	return part(parent, size, cf, Color3.new(), M.SmoothPlastic, {
		Transparency = 1,
		CanCollide = collide == true,
		CanQuery = collide == true,
		CanTouch = false,
		CastShadow = false,
	})
end

local function light(parent, color, range, brightness, flicker)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = true
	l:SetAttribute("BaseBrightness", brightness)
	l.Parent = parent
	if flicker then
		CollectionService:AddTag(l, FLICKER_TAG)
	end
	return l
end

-- ป้ายพร้อมข้อความ entries = { {Text=, Font=, Color=, Weight=} }
local function sign(parent, size, cf, entries, bg)
	local p = part(parent, size, cf, bg or Color3.fromRGB(22, 16, 18), M.Wood)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = p
	local total = 0
	for _, e in ipairs(entries) do
		total += e.Weight or 1
	end
	local y = 0
	for _, e in ipairs(entries) do
		local w = (e.Weight or 1) / total
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.94, w)
		t.Position = UDim2.fromScale(0.03, y)
		t.Text = e.Text
		t.Font = e.Font or Enum.Font.GothamBlack
		t.TextColor3 = e.Color or Color3.fromRGB(200, 20, 20)
		t.TextScaled = true
		t.TextStrokeTransparency = 0.4
		t.Parent = sg
		y += w
	end
	return p
end

-- ตัวหนังสือเลือดบนผนัง (แผ่นใส ลอยหน้าผนังเล็กน้อย)
local function writing(parent, pos, facing, text, width)
	local p = invisible(parent, Vector3.new(width or 12, 5, 0.1), CFrame.lookAt(pos, pos + facing))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 1
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(140, 0, 0)
	t.TextScaled = true
	t.Rotation = math.random(-6, 6)
	t.Parent = sg
	return p
end

-- พื้นแบบ Terrain (หญ้า/โคลนสวยกว่าพาร์ทมาก) ผิวบนอยู่ที่ y ของ center
local function ground(center, sizeXZ, material)
	workspace.Terrain:FillBlock(CFrame.new(center - Vector3.new(0, 4, 0)), Vector3.new(sizeXZ.X, 8, sizeXZ.Y), material)
end

local function deadTree(parent, pos, rng)
	local h = rng:NextNumber(16, 30)
	local w = rng:NextNumber(1.6, 2.8)
	local color = Color3.fromRGB(42, 33, 27)
	part(parent, Vector3.new(w, h, w),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 6.28), rng:NextNumber(-0.08, 0.08)),
		color, M.Wood)
	for _ = 1, rng:NextInteger(2, 4) do
		local bh = rng:NextNumber(h * 0.45, h * 0.9)
		local len = rng:NextNumber(5, 10)
		local cf = CFrame.new(pos + Vector3.new(0, bh, 0))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			* CFrame.Angles(math.rad(rng:NextNumber(35, 65)), 0, 0)
			* CFrame.new(0, len / 2, 0)
		part(parent, Vector3.new(w * 0.35, len, w * 0.35), cf, color, M.Wood, { CanCollide = false })
	end
end

local function lampPost(parent, pos, color)
	part(parent, Vector3.new(0.8, 9, 0.8), CFrame.new(pos + Vector3.new(0, 4.5, 0)), Color3.fromRGB(30, 26, 22), M.Wood)
	part(parent, Vector3.new(1.6, 0.3, 1.6), CFrame.new(pos + Vector3.new(0, 9.1, 0)), Color3.fromRGB(25, 25, 25), M.Metal)
	local bulb = part(parent, Vector3.new(1, 1.2, 1), CFrame.new(pos + Vector3.new(0, 8.4, 0)), color, M.Neon, { CanCollide = false })
	light(bulb, color, 20, 1.3, true)
	return bulb
end

local function portal(parent, base, color, s)
	s = s or 1
	local model = Instance.new("Model")
	model.Name = "Portal"
	local stone = Color3.fromRGB(45, 42, 48)
	part(model, Vector3.new(2, 13, 2) * s, base * CFrame.new(-5.5 * s, 6.5 * s, 0), stone, M.Slate)
	part(model, Vector3.new(2, 13, 2) * s, base * CFrame.new(5.5 * s, 6.5 * s, 0), stone, M.Slate)
	part(model, Vector3.new(13, 2, 2.4) * s, base * CFrame.new(0, 14 * s, 0), stone, M.Slate)
	local core = part(model, Vector3.new(9, 12, 0.6) * s, base * CFrame.new(0, 6.5 * s, 0), color, M.Neon, {
		Name = "PortalCore",
		CanCollide = false,
		Transparency = 0.3,
	})
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Rate = 25
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Parent = core
	light(core, color, 22, 2.5, false)
	core:SetAttribute("Active", true)
	model.Parent = parent
	return core
end

function MapBuilder.setPortal(core, active)
	core:SetAttribute("Active", active)
	core.Transparency = active and 0.3 or 1
	for _, c in ipairs(core:GetChildren()) do
		if c:IsA("ParticleEmitter") or c:IsA("Light") then
			c.Enabled = active
		end
	end
end

local function makeDoor(parent, size, cf, color, actionText)
	local door = part(parent, size, cf, color, M.WoodPlanks, { Name = "ExitDoor" })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = "ประตูทางออก"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	local obj = { Part = door, Prompt = prompt, IsOpen = false }
	function obj.open()
		obj.IsOpen = true
		prompt.Enabled = false
		door.CanCollide = false
		TweenService:Create(door, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
			CFrame = cf * CFrame.new(0, -(size.Y + 0.5), 0),
		}):Play()
	end
	function obj.close()
		obj.IsOpen = false
		prompt.Enabled = true
		door.CanCollide = true
		door.CFrame = cf
	end
	return obj
end

-- ของที่เก็บได้ (กุญแจ / เทียน / ฟิวส์)
function MapBuilder.makePickup(parent, pos, kind)
	local model = Instance.new("Model")
	model.Name = kind
	local main, objectText, lightColor
	if kind == "Key" then
		local gold = Color3.fromRGB(255, 200, 60)
		main = part(model, Vector3.new(0.35, 0.35, 1.8), CFrame.new(pos + Vector3.new(0, 0.3, 0)), gold, M.Metal, { CanCollide = false })
		part(model, Vector3.new(0.3, 1.1, 1.1), CFrame.new(pos + Vector3.new(0, 0.3, -1.2)), gold, M.Metal, { CanCollide = false })
		part(model, Vector3.new(0.3, 0.5, 0.25), CFrame.new(pos + Vector3.new(0, 0.05, 0.7)), gold, M.Metal, { CanCollide = false })
		objectText, lightColor = "กุญแจประตูทางออก", gold
	elseif kind == "Candle" then
		main = part(model, Vector3.new(0.6, 1.6, 0.6), CFrame.new(pos + Vector3.new(0, 0.8, 0)), Color3.fromRGB(235, 230, 215), M.SmoothPlastic, { CanCollide = false })
		local flame = part(model, Vector3.new(0.35, 0.5, 0.35), CFrame.new(pos + Vector3.new(0, 1.85, 0)), Color3.fromRGB(120, 200, 255), M.Neon, { CanCollide = false })
		local fire = Instance.new("Fire")
		fire.Size = 1
		fire.Heat = 3
		fire.Color = Color3.fromRGB(120, 200, 255)
		fire.SecondaryColor = Color3.fromRGB(255, 255, 255)
		fire.Parent = flame
		objectText, lightColor = "เทียนวิญญาณ", Color3.fromRGB(120, 200, 255)
	else -- Fuse
		main = part(model, Vector3.new(0.8, 1.6, 0.8), CFrame.new(pos + Vector3.new(0, 0.8, 0)), Color3.fromRGB(200, 190, 60), M.Metal, { CanCollide = false })
		part(model, Vector3.new(0.95, 0.25, 0.95), CFrame.new(pos + Vector3.new(0, 1.55, 0)), Color3.fromRGB(170, 170, 175), M.Metal, { CanCollide = false })
		part(model, Vector3.new(0.95, 0.25, 0.95), CFrame.new(pos + Vector3.new(0, 0.05, 0)), Color3.fromRGB(170, 170, 175), M.Metal, { CanCollide = false })
		part(model, Vector3.new(0.85, 0.2, 0.85), CFrame.new(pos + Vector3.new(0, 0.8, 0)), Color3.fromRGB(60, 255, 90), M.Neon, { CanCollide = false })
		objectText, lightColor = "ฟิวส์", Color3.fromRGB(60, 255, 90)
	end
	model.PrimaryPart = main
	light(main, lightColor, 10, 1.5, false)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "เก็บ"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = main
	model.Parent = parent
	return model, prompt
end

-- ================= Maze (ใช้ในด่าน 2 และ 4) =================

local function buildMaze(f, p)
	local rng = Random.new(p.seed)
	local W, H, C, T, WH = p.W, p.H, p.C, p.thick, p.wallH
	local corner = p.corner

	-- hW[i][j] = ผนังแนวนอนที่ z = j*C ของคอลัมน์ i, vW[i][j] = ผนังแนวตั้งที่ x = i*C ของแถว j
	local hW, vW = {}, {}
	for i = 0, W - 1 do
		hW[i] = {}
		for j = 0, H do
			hW[i][j] = true
		end
	end
	for i = 0, W do
		vW[i] = {}
		for j = 0, H - 1 do
			vW[i][j] = true
		end
	end

	-- สุ่มสร้างเขาวงกต (recursive backtracker) => ทุกห้องเดินถึงกันแน่นอน
	local visited = {}
	local function key(i, j)
		return i * 1000 + j
	end
	local stack = { { p.entryI, 0 } }
	visited[key(p.entryI, 0)] = true
	while #stack > 0 do
		local cur = stack[#stack]
		local i, j = cur[1], cur[2]
		local options = {}
		if j + 1 < H and not visited[key(i, j + 1)] then
			table.insert(options, { i, j + 1, "N" })
		end
		if j - 1 >= 0 and not visited[key(i, j - 1)] then
			table.insert(options, { i, j - 1, "S" })
		end
		if i + 1 < W and not visited[key(i + 1, j)] then
			table.insert(options, { i + 1, j, "E" })
		end
		if i - 1 >= 0 and not visited[key(i - 1, j)] then
			table.insert(options, { i - 1, j, "W" })
		end
		if #options == 0 then
			table.remove(stack)
		else
			local o = options[rng:NextInteger(1, #options)]
			if o[3] == "N" then
				hW[i][j + 1] = false
			elseif o[3] == "S" then
				hW[i][j] = false
			elseif o[3] == "E" then
				vW[i + 1][j] = false
			else
				vW[i][j] = false
			end
			visited[key(o[1], o[2])] = true
			table.insert(stack, { o[1], o[2] })
		end
	end
	-- เปิดทางเพิ่มให้มีทางวน (หนีผีได้)
	for _ = 1, p.extra do
		if rng:NextNumber() < 0.5 then
			hW[rng:NextInteger(0, W - 1)][rng:NextInteger(1, H - 1)] = false
		else
			vW[rng:NextInteger(1, W - 1)][rng:NextInteger(0, H - 1)] = false
		end
	end

	-- พื้น + เพดาน
	part(f, Vector3.new(W * C + T, 1, H * C + T), CFrame.new(corner + Vector3.new(W * C / 2, -0.5, H * C / 2)), p.floorColor, p.floorMat)
	part(f, Vector3.new(W * C + T, 1, H * C + T), CFrame.new(corner + Vector3.new(W * C / 2, WH + 0.5, H * C / 2)), p.ceilColor, M.Concrete)

	-- เสามุม
	for i = 0, W do
		for j = 0, H do
			part(f, Vector3.new(T, WH, T), CFrame.new(corner + Vector3.new(i * C, WH / 2, j * C)), p.wallColor, p.wallMat)
		end
	end

	local L = C - T
	local exitI = p.exitI
	for i = 0, W - 1 do
		for j = 0, H do
			if hW[i][j] and not (j == H and i == exitI) then
				part(f, Vector3.new(L, WH, T), CFrame.new(corner + Vector3.new((i + 0.5) * C, WH / 2, j * C)), p.wallColor, p.wallMat)
			end
		end
	end
	for i = 0, W do
		for j = 0, H - 1 do
			if vW[i][j] then
				part(f, Vector3.new(T, WH, L), CFrame.new(corner + Vector3.new(i * C, WH / 2, (j + 0.5) * C)), p.wallColor, p.wallMat)
			end
		end
	end

	-- ประตูทางออก (ผนังทิศเหนือของช่อง exitI)
	local doorW, doorH = 8, 11
	local side = (L - doorW) / 2
	local dz = H * C
	local dx = (exitI + 0.5) * C
	part(f, Vector3.new(side, WH, T), CFrame.new(corner + Vector3.new(dx - doorW / 2 - side / 2, WH / 2, dz)), p.wallColor, p.wallMat)
	part(f, Vector3.new(side, WH, T), CFrame.new(corner + Vector3.new(dx + doorW / 2 + side / 2, WH / 2, dz)), p.wallColor, p.wallMat)
	part(f, Vector3.new(doorW, WH - doorH, T), CFrame.new(corner + Vector3.new(dx, doorH + (WH - doorH) / 2, dz)), p.wallColor, p.wallMat)
	local door = makeDoor(f, Vector3.new(doorW, doorH, T * 0.8), CFrame.new(corner + Vector3.new(dx, doorH / 2, dz)), p.doorColor, p.doorText)

	-- ห้องหลังประตู
	local rz = (H + 0.5) * C
	part(f, Vector3.new(C + T, 1, C), CFrame.new(corner + Vector3.new(dx, -0.5, rz)), p.floorColor, p.floorMat)
	part(f, Vector3.new(C + T, 1, C), CFrame.new(corner + Vector3.new(dx, WH + 0.5, rz)), p.ceilColor, M.Concrete)
	part(f, Vector3.new(T, WH, L), CFrame.new(corner + Vector3.new(exitI * C, WH / 2, rz)), p.wallColor, p.wallMat)
	part(f, Vector3.new(T, WH, L), CFrame.new(corner + Vector3.new((exitI + 1) * C, WH / 2, rz)), p.wallColor, p.wallMat)
	part(f, Vector3.new(C + T, WH, T), CFrame.new(corner + Vector3.new(dx, WH / 2, (H + 1) * C)), p.wallColor, p.wallMat)
	local portalBase = CFrame.lookAt(corner + Vector3.new(dx, 0, (H + 0.65) * C), corner + Vector3.new(dx, 0, 0))
	local portalCore = portal(f, portalBase, p.portalColor, 0.8)

	-- ช่องต่าง ๆ
	local function center(i, j)
		return corner + Vector3.new((i + 0.5) * C, 0, (j + 0.5) * C)
	end
	local cells, deadEnds = {}, {}
	for i = 0, W - 1 do
		for j = 0, H - 1 do
			local c = center(i, j)
			table.insert(cells, { i = i, j = j, pos = c })
			local n = (hW[i][j] and 1 or 0) + (hW[i][j + 1] and 1 or 0) + (vW[i][j] and 1 or 0) + (vW[i + 1][j] and 1 or 0)
			local special = (i == p.entryI and j == 0) or (i == exitI and j == H - 1)
			if n >= 3 and not special then
				table.insert(deadEnds, { i = i, j = j, pos = c })
			end
		end
	end

	-- ไฟเพดาน (กะพริบ)
	local lamps = {}
	for _, cell in ipairs(cells) do
		local isEntry = cell.i == p.entryI and cell.j == 0
		if isEntry or rng:NextNumber() < p.lampChance then
			local lamp = part(f, Vector3.new(2.5, 0.3, 2.5), CFrame.new(cell.pos + Vector3.new(0, WH - 0.15, 0)), p.lampColor, M.Neon, { CanCollide = false })
			local l = light(lamp, p.lampColor, 22, 0.8, true)
			table.insert(lamps, { Part = lamp, Light = l })
		end
	end

	-- ตัวหนังสือเลือดบนผนัง
	local writingsLeft = p.writings and #p.writings or 0
	local tries = 0
	while writingsLeft > 0 and tries < 200 do
		tries += 1
		local i, j = rng:NextInteger(0, W - 1), rng:NextInteger(1, H - 1)
		if hW[i][j] then
			writing(f, corner + Vector3.new((i + 0.5) * C, WH * 0.5, j * C - T / 2 - 0.06), Vector3.new(0, 0, -1), p.writings[writingsLeft], L - 4)
			writingsLeft -= 1
		end
	end

	return {
		hW = hW,
		vW = vW,
		C = C,
		T = T,
		WH = WH,
		center = center,
		cells = cells,
		deadEnds = deadEnds,
		door = door,
		portal = portalCore,
		lamps = lamps,
		entry = center(p.entryI, 0),
		rng = rng,
	}
end

-- ================= ล็อบบี้ =================

local PAD_COLORS = {
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(255, 140, 40),
	Color3.fromRGB(240, 220, 60),
	Color3.fromRGB(80, 220, 90),
	Color3.fromRGB(60, 160, 255),
	Color3.fromRGB(190, 80, 255),
}

local function buildLobby(root)
	local O = Config.Origins.Lobby
	local f = folder("Lobby", root)
	local W, D, H = 130, 110, 26
	local wallColor = Color3.fromRGB(48, 40, 44)

	part(f, Vector3.new(W, 2, D), CFrame.new(O + Vector3.new(0, -1, 0)), Color3.fromRGB(58, 40, 30), M.WoodPlanks)
	part(f, Vector3.new(14, 0.2, 66), CFrame.new(O + Vector3.new(0, 0.1, 8)), Color3.fromRGB(95, 12, 18), M.Fabric)
	part(f, Vector3.new(W, H, 2), CFrame.new(O + Vector3.new(0, H / 2, -D / 2)), wallColor, M.Brick)
	part(f, Vector3.new(W, H, 2), CFrame.new(O + Vector3.new(0, H / 2, D / 2)), wallColor, M.Brick)
	part(f, Vector3.new(2, H, D), CFrame.new(O + Vector3.new(-W / 2, H / 2, 0)), wallColor, M.Brick)
	part(f, Vector3.new(2, H, D), CFrame.new(O + Vector3.new(W / 2, H / 2, 0)), wallColor, M.Brick)
	part(f, Vector3.new(W, 2, D), CFrame.new(O + Vector3.new(0, H + 1, 0)), Color3.fromRGB(30, 24, 26), M.Wood)

	-- เสา + เทียนข้างผนัง
	for i = -2, 2 do
		for _, sd in ipairs({ -1, 1 }) do
			local x, z = sd * (W / 2 - 4), i * 20
			part(f, Vector3.new(3, H, 3), CFrame.new(O + Vector3.new(x, H / 2, z)), Color3.fromRGB(35, 30, 32), M.Marble)
			part(f, Vector3.new(0.6, 1.2, 0.6), CFrame.new(O + Vector3.new(x - sd * 1.9, 9, z)), Color3.fromRGB(240, 230, 200))
			local flame = part(f, Vector3.new(0.4, 0.6, 0.4), CFrame.new(O + Vector3.new(x - sd * 1.9, 9.9, z)), Color3.fromRGB(255, 170, 60), M.Neon, { CanCollide = false })
			light(flame, Color3.fromRGB(255, 150, 60), 16, 1.2, true)
		end
	end

	-- โคมระย้า
	local chPos = O + Vector3.new(0, H - 5, 8)
	part(f, Vector3.new(0.4, 4, 0.4), CFrame.new(chPos + Vector3.new(0, 3, 0)), Color3.fromRGB(40, 35, 25), M.Metal)
	local ch = part(f, Vector3.new(7, 0.6, 7), CFrame.new(chPos), Color3.fromRGB(70, 55, 30), M.Metal, { CanCollide = false })
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		part(f, Vector3.new(0.4, 0.8, 0.4), CFrame.new(chPos + Vector3.new(math.cos(a) * 3, 0.7, math.sin(a) * 3)), Color3.fromRGB(255, 170, 70), M.Neon, { CanCollide = false })
	end
	light(ch, Color3.fromRGB(255, 160, 90), 45, 1.1, true)

	-- รูปภาพหลอน ๆ บนผนังข้าง
	for _, sd in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -10, 10, 30 }) do
			local pos = O + Vector3.new(sd * (W / 2 - 1.2), 13, z)
			part(f, Vector3.new(0.4, 8, 6), CFrame.new(pos), Color3.fromRGB(60, 45, 20), M.Wood)
			local canvas = part(f, Vector3.new(5, 7, 0.2), CFrame.lookAt(pos - Vector3.new(sd * 0.25, 0, 0), pos - Vector3.new(sd * 5, 0, 0)), Color3.fromRGB(15, 15, 18))
			local painting = Config.Images.Painting
			if painting and painting ~= "" then
				local decal = Instance.new("Decal")
				decal.Face = Enum.NormalId.Front
				decal.Texture = tonumber(painting) and ("rbxassetid://" .. painting) or painting
				decal.Parent = canvas
			else
				for _, ez in ipairs({ -0.7, 0.7 }) do
					part(f, Vector3.new(0.2, 0.4, 0.4), CFrame.new(pos + Vector3.new(-sd * 0.4, 1, ez)), Color3.fromRGB(255, 30, 30), M.Neon, { CanCollide = false })
				end
			end
		end
	end

	-- จุดเกิด
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(O + Vector3.new(0, 0.5, 38))
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(70, 10, 15)
	spawn.Material = M.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = f

	-- ป้ายชื่อเกม
	sign(f, Vector3.new(64, 12, 1), CFrame.lookAt(O + Vector3.new(0, 20, -D / 2 + 1.6), O + Vector3.new(0, 20, 0)), {
		{ Text = Config.GameTitle, Font = Enum.Font.Creepster, Color = Color3.fromRGB(220, 20, 20), Weight = 2 },
		{ Text = Config.GameSubtitle, Color = Color3.fromRGB(230, 220, 220), Weight = 1 },
	})

	-- ป้ายวิธีเล่น (ตั้งข้างจุดเกิด หันหน้าเข้าหาผู้เล่น)
	local function standingSign(pos, entries)
		local face = CFrame.lookAt(pos, Vector3.new(O.X, pos.Y, O.Z + 38))
		sign(f, Vector3.new(16, 9, 0.6), face, entries)
		for _, x in ipairs({ -6, 6 }) do
			part(f, Vector3.new(0.6, pos.Y - O.Y, 0.6), face * CFrame.new(x, -(pos.Y - O.Y) / 2, 0.5), Color3.fromRGB(40, 30, 24), M.Wood)
		end
	end
	standingSign(O + Vector3.new(24, 7, 22), {
		{ Text = "วิธีเล่น", Color = Color3.fromRGB(255, 200, 60), Weight = 1.3 },
		{ Text = "1. ยืนบนแท่นตามจำนวนคนในทีม", Color = Color3.new(1, 1, 1) },
		{ Text = "2. คนครบ = นับถอยหลังเข้าเกม", Color = Color3.new(1, 1, 1) },
		{ Text = "[Shift] วิ่ง   [F] ไฟฉาย", Color = Color3.new(1, 1, 1) },
		{ Text = "ผ่านให้ครบ 4 ด่านเพื่อหนีให้รอด!", Color = Color3.fromRGB(255, 80, 80) },
	})
	standingSign(O + Vector3.new(-24, 7, 22), {
		{ Text = "4 ด่านแห่งความกลัว", Color = Color3.fromRGB(255, 200, 60), Weight = 1.3 },
		{ Text = "1. ทางเดินป่าช้า - ตุ้งแช่", Color = Color3.new(1, 1, 1) },
		{ Text = "2. บ้านร้าง - หากุญแจ หนีผี", Color = Color3.new(1, 1, 1) },
		{ Text = "3. สุสาน - สู้ผี ทำเควส", Color = Color3.new(1, 1, 1) },
		{ Text = "4. โรงพยาบาล - ตุ้งแช่ หนีผี หาของ", Color = Color3.new(1, 1, 1) },
	})

	-- แท่นทีม
	local pads = {}
	for idx, size in ipairs(Config.PartySizes) do
		local x = -50 + (idx - 1) * 20
		local center = O + Vector3.new(x, 0, -30)
		local glow = PAD_COLORS[((idx - 1) % #PAD_COLORS) + 1]
		local pad = part(f, Vector3.new(12, 1, 12), CFrame.new(center + Vector3.new(0, 0.5, 0)), Color3.fromRGB(25, 20, 25), M.Slate, { Name = "Pad" .. size })
		for _, e in ipairs({ { 0, 6, 12.4, 0.6 }, { 0, -6, 12.4, 0.6 }, { 6, 0, 0.6, 12.4 }, { -6, 0, 0.6, 12.4 } }) do
			part(f, Vector3.new(e[3], 0.3, e[4]), CFrame.new(center + Vector3.new(e[1], 1.1, e[2])), glow, M.Neon, { CanCollide = false })
		end
		light(pad, glow, 14, 1.5, false)

		-- ซุ้มประตูด้านหลังแท่น
		local stone = Color3.fromRGB(40, 36, 40)
		part(f, Vector3.new(2, 16, 2), CFrame.new(center + Vector3.new(-6, 8, -8)), stone, M.Slate)
		part(f, Vector3.new(2, 16, 2), CFrame.new(center + Vector3.new(6, 8, -8)), stone, M.Slate)
		part(f, Vector3.new(14, 2, 2.4), CFrame.new(center + Vector3.new(0, 17, -8)), stone, M.Slate)
		part(f, Vector3.new(10, 15, 0.4), CFrame.new(center + Vector3.new(0, 7.5, -8.6)), Color3.fromRGB(5, 5, 8), M.SmoothPlastic)
		sign(f, Vector3.new(9, 2.6, 0.3), CFrame.lookAt(center + Vector3.new(0, 17, -6.6), center + Vector3.new(0, 17, 10)), {
			{ Text = "ทีม " .. size .. " คน", Color = glow },
		}, Color3.fromRGB(15, 12, 14))

		local anchor = invisible(f, Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 7, 0)))
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(220, 90)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		bb.LightInfluence = 0
		bb.Parent = anchor
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 0.55)
		title.Text = size .. " คน"
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = glow
		title.TextStrokeTransparency = 0.3
		title.Parent = bb
		local status = Instance.new("TextLabel")
		status.BackgroundTransparency = 1
		status.Position = UDim2.fromScale(0, 0.55)
		status.Size = UDim2.fromScale(1, 0.45)
		status.Text = "0/" .. size
		status.Font = Enum.Font.GothamBold
		status.TextScaled = true
		status.TextColor3 = Color3.new(1, 1, 1)
		status.TextStrokeTransparency = 0.3
		status.Parent = bb

		pads[idx] = { Part = pad, Size = size, Center = center, Status = status, Billboard = bb }
	end

	return { Folder = f, Spawn = spawn, Pads = pads }
end

-- ================= ด่าน 1 : ทางเดินป่าช้า (ตุ้งแช่) =================

local function buildStage1(root)
	local O = Config.Origins[1]
	local f = folder("Stage1", root)
	local rng = Random.new(11)
	local LEN = 420

	ground(O + Vector3.new(0, 0, LEN / 2), Vector2.new(160, LEN + 40), M.Grass)
	ground(O + Vector3.new(0, 0, LEN / 2), Vector2.new(12, LEN + 20), M.Mud)
	invisible(f, Vector3.new(2, 40, LEN + 40), CFrame.new(O + Vector3.new(-17, 20, LEN / 2)), true)
	invisible(f, Vector3.new(2, 40, LEN + 40), CFrame.new(O + Vector3.new(17, 20, LEN / 2)), true)
	invisible(f, Vector3.new(36, 40, 2), CFrame.new(O + Vector3.new(0, 20, -6)), true)
	invisible(f, Vector3.new(36, 40, 2), CFrame.new(O + Vector3.new(0, 20, LEN + 6)), true)

	-- ต้นไม้ตาย
	for z = -10, LEN + 10, 8 do
		for _, sd in ipairs({ -1, 1 }) do
			if rng:NextNumber() < 0.8 then
				deadTree(f, O + Vector3.new(sd * rng:NextNumber(9, 15.5), 0, z + rng:NextNumber(-3, 3)), rng)
			end
			deadTree(f, O + Vector3.new(sd * rng:NextNumber(20, 70), 0, z + rng:NextNumber(-3, 3)), rng)
		end
	end

	-- เสาไฟริมทาง
	for z = 30, LEN - 20, 60 do
		local sd = (z / 60) % 2 == 0 and 1 or -1
		lampPost(f, O + Vector3.new(sd * 7.5, 0, z), Color3.fromRGB(255, 160, 80))
	end

	-- ป้ายทางเข้า
	sign(f, Vector3.new(10, 4, 0.4), CFrame.lookAt(O + Vector3.new(-8, 5, 18), O + Vector3.new(-8, 5, 0)) * CFrame.Angles(0, 0, math.rad(-6)), {
		{ Text = "ทางนี้...", Color = Color3.fromRGB(170, 0, 0) },
		{ Text = "ไม่มีใครกลับมา", Color = Color3.fromRGB(170, 0, 0) },
	}, Color3.fromRGB(50, 38, 28))
	part(f, Vector3.new(0.5, 6, 0.5), CFrame.new(O + Vector3.new(-8, 3, 18.4)), Color3.fromRGB(50, 38, 28), M.Wood)

	-- ศาลพระภูมิร้างกลางทาง
	local sp = O + Vector3.new(11, 0, 185)
	part(f, Vector3.new(0.8, 5, 0.8), CFrame.new(sp + Vector3.new(0, 2.5, 0)), Color3.fromRGB(150, 140, 130), M.Concrete)
	part(f, Vector3.new(4, 0.4, 4), CFrame.new(sp + Vector3.new(0, 5.2, 0)), Color3.fromRGB(140, 130, 120), M.Concrete)
	part(f, Vector3.new(3, 2.6, 3), CFrame.new(sp + Vector3.new(0, 6.7, 0)), Color3.fromRGB(150, 60, 40), M.Wood)
	part(f, Vector3.new(3.6, 0.5, 3.6), CFrame.new(sp + Vector3.new(0, 8.2, 0)) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(120, 40, 30), M.Wood)
	local candle = part(f, Vector3.new(0.3, 0.6, 0.3), CFrame.new(sp + Vector3.new(-1.2, 5.7, -1.4)), Color3.fromRGB(255, 120, 40), M.Neon, { CanCollide = false })
	light(candle, Color3.fromRGB(255, 120, 40), 10, 1, true)

	-- ผียืนนิ่ง ๆ ไกล ๆ ในป่า (แค่บรรยากาศ)
	local GhostModel = require(ReplicatedStorage.HorrorShared.GhostModel)
	for _, z in ipairs({ 120, 240, 340 }) do
		local g = GhostModel.create({ name = "WatchingGhost" })
		local x = (z % 240 == 0) and -30 or 32
		local pos = O + Vector3.new(x, 3.5, z)
		g:PivotTo(CFrame.lookAt(pos, Vector3.new(O.X, pos.Y, pos.Z)))
		g.Parent = f
	end

	-- จุดตุ้งแช่
	local triggers = {}
	local scares = { "Face", "Rush", "Blackout", "Drop", "Behind", "Rush", "Face" }
	for k, z in ipairs({ 45, 95, 150, 205, 265, 320, 375 }) do
		local t = invisible(f, Vector3.new(32, 14, 4), CFrame.new(O + Vector3.new(0, 7, z)))
		t.Name = "ScareTrigger"
		t.CanTouch = true
		t:SetAttribute("ScareType", scares[k])
		t:SetAttribute("Stage", 1)
		table.insert(triggers, t)
	end

	-- ประตูวาปท้ายทาง
	local base = CFrame.lookAt(O + Vector3.new(0, 0, LEN - 4), O + Vector3.new(0, 0, 0))
	local portalCore = portal(f, base, Color3.fromRGB(170, 60, 255), 1)

	local spawn = invisible(f, Vector3.new(1, 1, 1), CFrame.lookAt(O + Vector3.new(0, 3, 6), O + Vector3.new(0, 3, 50)))
	spawn.Name = "StageSpawn"

	return { Folder = f, Spawn = spawn, Portal = portalCore, Triggers = triggers }
end

-- ================= ด่าน 2 : บ้านร้าง (หากุญแจ + ผีไล่) =================

local function buildStage2(root)
	local O = Config.Origins[2]
	local f = folder("Stage2", root)
	local W, H, C = 7, 7, 20
	local corner = O + Vector3.new(-W * C / 2, 0, 0)
	local maze = buildMaze(f, {
		corner = corner, W = W, H = H, C = C, thick = 2, wallH = 14, seed = 22, extra = 9,
		entryI = 3, exitI = 3,
		floorColor = Color3.fromRGB(55, 38, 28), floorMat = M.WoodPlanks,
		wallColor = Color3.fromRGB(78, 64, 55), wallMat = M.WoodPlanks,
		ceilColor = Color3.fromRGB(35, 30, 28),
		lampChance = 0.3, lampColor = Color3.fromRGB(255, 175, 110),
		doorColor = Color3.fromRGB(70, 40, 25), doorText = "ไขกุญแจ",
		portalColor = Color3.fromRGB(170, 60, 255),
		writings = { "หนีไป...", "มันอยู่ข้างหลังแก", "ไม่มีทางออก", "ช่วยด้วย", "GET OUT", "อย่าหันไปมอง", "มันได้ยินแก", "กุญแจอยู่ไหน?" },
	})
	local rng = maze.rng

	-- โต๊ะตามทางตัน (กุญแจจะสุ่มอยู่บนโต๊ะตัวใดตัวหนึ่ง)
	local keySpots = {}
	local tableColor = Color3.fromRGB(60, 40, 28)
	for _, d in ipairs(maze.deadEnds) do
		local c = d.pos
		part(f, Vector3.new(5, 0.4, 3.5), CFrame.new(c + Vector3.new(0, 3, 0)), tableColor, M.Wood)
		for _, l in ipairs({ { -2.2, -1.4 }, { 2.2, -1.4 }, { -2.2, 1.4 }, { 2.2, 1.4 } }) do
			part(f, Vector3.new(0.4, 2.8, 0.4), CFrame.new(c + Vector3.new(l[1], 1.4, l[2])), tableColor, M.Wood)
		end
		table.insert(keySpots, c + Vector3.new(0, 3.2, 0))
	end
	if #keySpots == 0 then
		table.insert(keySpots, maze.center(W - 1, H - 1) + Vector3.new(0, 0.1, 0))
	end

	-- ของตกแต่ง: ลังไม้ตามมุมห้อง
	for _, cell in ipairs(maze.cells) do
		if rng:NextNumber() < 0.35 then
			local ox = (rng:NextNumber() < 0.5 and -1 or 1) * (C / 2 - 3.2)
			local oz = (rng:NextNumber() < 0.5 and -1 or 1) * (C / 2 - 3.2)
			part(f, Vector3.new(3, 3, 3), CFrame.new(cell.pos + Vector3.new(ox, 1.5, oz)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Color3.fromRGB(90, 65, 40), M.Wood)
		end
	end

	local ghostSpawns = {
		maze.center(0, H - 1),
		maze.center(W - 1, H - 1),
		maze.center(W - 1, 2),
		maze.center(0, 3),
	}
	local patrol = {}
	for _, cell in ipairs(maze.cells) do
		table.insert(patrol, cell.pos)
	end

	local spawn = invisible(f, Vector3.new(1, 1, 1), CFrame.lookAt(maze.entry + Vector3.new(0, 3, 0), maze.entry + Vector3.new(0, 3, 10)))
	spawn.Name = "StageSpawn"

	return {
		Folder = f,
		Spawn = spawn,
		Portal = maze.portal,
		Door = maze.door,
		KeySpots = keySpots,
		GhostSpawns = ghostSpawns,
		Patrol = patrol,
		Dynamic = folder("Dynamic", f),
	}
end

-- ================= ด่าน 3 : สุสาน (สู้ผี + เควสเทียน) =================

local function tombstone(parent, pos, rng)
	local stone = Color3.fromRGB(rng:NextInteger(85, 115), rng:NextInteger(85, 110), rng:NextInteger(85, 110))
	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0)
	local tilt = CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.12, 0.12))
	if rng:NextNumber() < 0.7 then
		local h = rng:NextNumber(3, 5)
		part(parent, Vector3.new(3, h, 0.8), base * CFrame.new(0, h / 2 - 0.3, 0) * tilt, stone, M.Slate)
	else
		part(parent, Vector3.new(0.6, 5, 0.6), base * CFrame.new(0, 2.3, 0) * tilt, stone, M.Slate)
		part(parent, Vector3.new(2.8, 0.6, 0.6), base * tilt * CFrame.new(0, 3.5, 0), stone, M.Slate)
	end
	part(parent, Vector3.new(3.2, 0.7, 6), base * CFrame.new(0, 0.3, 3.4), Color3.fromRGB(55, 42, 32), M.Ground)
end

local function buildStage3(root)
	local O = Config.Origins[3]
	local f = folder("Stage3", root)
	local rng = Random.new(33)
	local S = 200
	local altar = O + Vector3.new(0, 0, 105)

	ground(O + Vector3.new(0, 0, S / 2), Vector2.new(S + 60, S + 60), M.Grass)
	ground(O + Vector3.new(0, 0, S / 2), Vector2.new(8, S), M.Mud)

	-- กำแพงล่องหน + รั้วเหล็ก
	invisible(f, Vector3.new(2, 50, S + 4), CFrame.new(O + Vector3.new(-S / 2 - 1, 25, S / 2)), true)
	invisible(f, Vector3.new(2, 50, S + 4), CFrame.new(O + Vector3.new(S / 2 + 1, 25, S / 2)), true)
	invisible(f, Vector3.new(S + 4, 50, 2), CFrame.new(O + Vector3.new(0, 25, -1)), true)
	invisible(f, Vector3.new(S + 4, 50, 2), CFrame.new(O + Vector3.new(0, 25, S + 1)), true)
	local iron = Color3.fromRGB(20, 20, 22)
	local stoneWall = Color3.fromRGB(70, 66, 62)
	for _, e in ipairs({
		{ Vector3.new(0, 0, 0), Vector3.new(S, 0, 1) },
		{ Vector3.new(0, 0, S), Vector3.new(S, 0, 1) },
		{ Vector3.new(-S / 2, 0, S / 2), Vector3.new(1, 0, S) },
		{ Vector3.new(S / 2, 0, S / 2), Vector3.new(1, 0, S) },
	}) do
		local c, sz = e[1], e[2]
		part(f, Vector3.new(sz.X, 2, sz.Z), CFrame.new(O + c + Vector3.new(0, 1, 0)), stoneWall, M.Cobblestone)
		part(f, Vector3.new(math.max(sz.X - 0.6, 0.4), 0.4, math.max(sz.Z - 0.6, 0.4)), CFrame.new(O + c + Vector3.new(0, 6, 0)), iron, M.Metal)
	end
	for t = -S / 2, S / 2, 8 do
		for _, pos in ipairs({ Vector3.new(t, 0, 0), Vector3.new(t, 0, S), Vector3.new(-S / 2, 0, t + S / 2), Vector3.new(S / 2, 0, t + S / 2) }) do
			part(f, Vector3.new(0.6, 7, 0.6), CFrame.new(O + pos + Vector3.new(0, 3.5, 0)), iron, M.Metal)
		end
	end
	for t = -S / 2 + 20, S / 2 - 20, 40 do
		lampPost(f, O + Vector3.new(t, 0, 3), Color3.fromRGB(150, 255, 160))
		lampPost(f, O + Vector3.new(t, 0, S - 3), Color3.fromRGB(150, 255, 160))
		lampPost(f, O + Vector3.new(-S / 2 + 3, 0, t + S / 2), Color3.fromRGB(150, 255, 160))
		lampPost(f, O + Vector3.new(S / 2 - 3, 0, t + S / 2), Color3.fromRGB(150, 255, 160))
	end

	-- หลุมศพ
	for z = 25, S - 25, 11 do
		for x = -S / 2 + 12, S / 2 - 12, 9 do
			local flat = Vector3.new(x, 0, z) - Vector3.new(0, 0, 105)
			if math.abs(x) > 7 and flat.Magnitude > 24 and rng:NextNumber() < 0.6 then
				tombstone(f, O + Vector3.new(x + rng:NextNumber(-2, 2), 0, z + rng:NextNumber(-2, 2)), rng)
			end
		end
	end

	-- ต้นไม้ตาย
	for _ = 1, 22 do
		local pos = O + Vector3.new(rng:NextNumber(-90, 90), 0, rng:NextNumber(15, 190))
		if (pos - altar).Magnitude > 26 and math.abs(pos.X - O.X) > 8 then
			deadTree(f, pos, rng)
		end
	end

	-- สุสานหลังเล็ก (ฮวงซุ้ย) 2 หลัง
	for _, c in ipairs({ Vector3.new(-72, 0, 175), Vector3.new(72, 0, 35) }) do
		local p = O + c
		local g = Color3.fromRGB(80, 78, 82)
		part(f, Vector3.new(16, 12, 14), CFrame.new(p + Vector3.new(0, 6, 0)), g, M.Granite)
		part(f, Vector3.new(18, 2, 16), CFrame.new(p + Vector3.new(0, 13, 0)), Color3.fromRGB(60, 58, 62), M.Slate)
		part(f, Vector3.new(12, 2, 11), CFrame.new(p + Vector3.new(0, 15, 0)), Color3.fromRGB(60, 58, 62), M.Slate)
		local dir = c.Z > 100 and -1 or 1
		part(f, Vector3.new(5, 8, 0.4), CFrame.new(p + Vector3.new(0, 4, dir * 7.1)), Color3.fromRGB(5, 5, 6))
		for _, x in ipairs({ -5, 5 }) do
			part(f, Vector3.new(1.4, 12, 1.4), CFrame.new(p + Vector3.new(x, 6, dir * 7.6)), g, M.Marble)
		end
	end

	-- แท่นบูชากลางสุสาน
	local stone = Color3.fromRGB(70, 68, 72)
	part(f, Vector3.new(18, 1.5, 18), CFrame.new(altar + Vector3.new(0, 0.75, 0)), stone, M.Slate)
	part(f, Vector3.new(12, 1, 12), CFrame.new(altar + Vector3.new(0, 2, 0)), Color3.fromRGB(90, 85, 92), M.Marble)
	local pillar = part(f, Vector3.new(2.5, 4, 2.5), CFrame.new(altar + Vector3.new(0, 4.5, 0)), Color3.fromRGB(40, 36, 40), M.Granite, { Name = "Altar" })
	local orb = part(f, Vector3.new(1.6, 1.6, 1.6), CFrame.new(altar + Vector3.new(0, 7.3, 0)), Color3.fromRGB(200, 0, 0), M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	light(orb, Color3.fromRGB(255, 0, 0), 18, 1.5, true)
	local altarPrompt = Instance.new("ProximityPrompt")
	altarPrompt.ActionText = "วางเทียน"
	altarPrompt.ObjectText = "แท่นบูชา"
	altarPrompt.HoldDuration = 1
	altarPrompt.MaxActivationDistance = 12
	altarPrompt.RequiresLineOfSight = false
	altarPrompt.Parent = pillar

	local slots = {}
	for k = 1, Config.Quest.Candles do
		local a = (k - 1) / Config.Quest.Candles * math.pi * 2
		local p = altar + Vector3.new(math.cos(a) * 4.8, 2.5, math.sin(a) * 4.8)
		part(f, Vector3.new(0.9, 1.6, 0.9), CFrame.new(p + Vector3.new(0, 0.8, 0)), Color3.fromRGB(50, 45, 50), M.Slate)
		local candle = part(f, Vector3.new(0.5, 1.2, 0.5), CFrame.new(p + Vector3.new(0, 2.2, 0)), Color3.fromRGB(235, 230, 215), M.SmoothPlastic, { CanCollide = false, Transparency = 1 })
		local flame = part(f, Vector3.new(0.3, 0.45, 0.3), CFrame.new(p + Vector3.new(0, 3.05, 0)), Color3.fromRGB(120, 200, 255), M.Neon, { CanCollide = false, Transparency = 1 })
		local l = light(flame, Color3.fromRGB(120, 200, 255), 12, 1.5, false)
		l.Enabled = false
		slots[k] = { Candle = candle, Flame = flame, Light = l }
	end
	local function setSlotLit(k, lit)
		local s = slots[k]
		if not s then
			return
		end
		s.Candle.Transparency = lit and 0 or 1
		s.Flame.Transparency = lit and 0 or 1
		s.Light.Enabled = lit
	end

	-- จุดที่เทียนอาจเกิด
	local candleSpots = {}
	local tries = 0
	while #candleSpots < 14 and tries < 500 do
		tries += 1
		local pos = O + Vector3.new(rng:NextNumber(-88, 88), 0, rng:NextNumber(25, 190))
		local ok = (pos - altar).Magnitude > 28
		for _, other in ipairs(candleSpots) do
			if (other - pos).Magnitude < 25 then
				ok = false
			end
		end
		if ok then
			table.insert(candleSpots, pos)
		end
	end

	local ghostSpawns = {
		O + Vector3.new(-80, 0, 60),
		O + Vector3.new(80, 0, 70),
		O + Vector3.new(-80, 0, 165),
		O + Vector3.new(80, 0, 150),
		O + Vector3.new(0, 0, 185),
	}
	local patrol = {}
	for _ = 1, 20 do
		table.insert(patrol, O + Vector3.new(rng:NextNumber(-85, 85), 0, rng:NextNumber(20, 190)))
	end

	local base = CFrame.lookAt(O + Vector3.new(0, 0, S - 8), O + Vector3.new(0, 0, 0))
	local portalCore = portal(f, base, Color3.fromRGB(170, 60, 255), 1)

	local spawn = invisible(f, Vector3.new(1, 1, 1), CFrame.lookAt(O + Vector3.new(0, 3, 8), O + Vector3.new(0, 3, 50)))
	spawn.Name = "StageSpawn"

	return {
		Folder = f,
		Spawn = spawn,
		Portal = portalCore,
		AltarPrompt = altarPrompt,
		SetSlotLit = setSlotLit,
		CandleSpots = candleSpots,
		GhostSpawns = ghostSpawns,
		BossSpawn = altar + Vector3.new(0, 0, 14),
		Patrol = patrol,
		Dynamic = folder("Dynamic", f),
	}
end

-- ================= ด่าน 4 : โรงพยาบาลร้าง (ตุ้งแช่ + ผีไล่ + หาฟิวส์) =================

local function buildStage4(root)
	local O = Config.Origins[4]
	local f = folder("Stage4", root)
	local W, H, C = 9, 9, 18
	local corner = O + Vector3.new(-W * C / 2, 0, 0)
	local entryI = 4
	local maze = buildMaze(f, {
		corner = corner, W = W, H = H, C = C, thick = 2, wallH = 13, seed = 44, extra = 14,
		entryI = entryI, exitI = 4,
		floorColor = Color3.fromRGB(150, 150, 140), floorMat = M.Marble,
		wallColor = Color3.fromRGB(120, 140, 125), wallMat = M.Concrete,
		ceilColor = Color3.fromRGB(90, 95, 90),
		lampChance = 0.35, lampColor = Color3.fromRGB(190, 255, 200),
		doorColor = Color3.fromRGB(110, 110, 115), doorText = "เปิดประตู",
		portalColor = Color3.fromRGB(255, 220, 120),
		writings = { "อย่าวิ่ง", "หมอยังอยู่ที่นี่", "ห้องผ่าตัด →", "ไฟดับ = ตาย", "ฉันเห็นแก", "HELP ME", "มันหิว", "ฟิวส์...", "ไม่มีใครรอด" },
	})
	local rng = maze.rng
	local C2 = C / 2

	-- ป้าย EXIT เหนือประตู
	local exitPos = corner + Vector3.new((4 + 0.5) * C, 12, H * C - 1.2)
	local exitSign = part(f, Vector3.new(5, 1.2, 0.3), CFrame.new(exitPos), Color3.fromRGB(255, 30, 30), M.Neon, { CanCollide = false })
	light(exitSign, Color3.fromRGB(255, 30, 30), 10, 1, true)

	-- เตียงคนไข้ (วางชิดผนังที่มีอยู่จริงเท่านั้น จะได้ไม่ขวางทาง)
	for _, cell in ipairs(maze.cells) do
		local hasEast = maze.vW[cell.i + 1][cell.j]
		if hasEast and rng:NextNumber() < 0.3 and not (cell.i == entryI and cell.j == 0) then
			local c = cell.pos + Vector3.new(C2 - 1 - 2.2, 0, 0)
			part(f, Vector3.new(3.6, 1.6, 7), CFrame.new(c + Vector3.new(0, 1.3, 0)), Color3.fromRGB(150, 150, 155), M.Metal)
			part(f, Vector3.new(3.3, 0.6, 6.6), CFrame.new(c + Vector3.new(0, 2.4, 0)), Color3.fromRGB(220, 215, 205), M.Fabric)
			part(f, Vector3.new(2, 0.05, 2.4), CFrame.new(c + Vector3.new(rng:NextNumber(-0.5, 0.5), 2.73, rng:NextNumber(-1.5, 1.5))), Color3.fromRGB(110, 0, 0), M.SmoothPlastic, { CanCollide = false })
		end
	end

	-- เครื่องปั่นไฟที่ห้องเริ่มต้น
	local gpos = maze.entry + Vector3.new(0, 0, -C2 + 1 + 1.8)
	local gen = part(f, Vector3.new(8, 5, 3.4), CFrame.new(gpos + Vector3.new(0, 2.5, 0)), Color3.fromRGB(150, 130, 40), M.DiamondPlate, { Name = "Generator" })
	sign(f, Vector3.new(6, 1.2, 0.2), CFrame.lookAt(gpos + Vector3.new(0, 4.3, 1.82), gpos + Vector3.new(0, 4.3, 10)), {
		{ Text = "เครื่องปั่นไฟ", Color = Color3.fromRGB(255, 230, 120) },
	}, Color3.fromRGB(30, 30, 30))
	local genSlots = {}
	for k = 1, Config.Quest.Fuses do
		local x = (k - (Config.Quest.Fuses + 1) / 2) * 1.6
		genSlots[k] = part(f, Vector3.new(0.8, 1.4, 0.2), CFrame.new(gpos + Vector3.new(x, 2.4, 1.82)), Color3.fromRGB(255, 30, 30), M.Neon, { CanCollide = false })
	end
	local genPrompt = Instance.new("ProximityPrompt")
	genPrompt.ActionText = "ใส่ฟิวส์"
	genPrompt.ObjectText = "เครื่องปั่นไฟ"
	genPrompt.HoldDuration = 1
	genPrompt.MaxActivationDistance = 10
	genPrompt.RequiresLineOfSight = false
	genPrompt.Parent = gen

	local function setFuseSlot(k, filled)
		if genSlots[k] then
			genSlots[k].Color = filled and Color3.fromRGB(60, 255, 90) or Color3.fromRGB(255, 30, 30)
		end
	end
	local function setPowered(on)
		for _, lamp in ipairs(maze.lamps) do
			local color = on and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(190, 255, 200)
			lamp.Part.Color = color
			lamp.Light.Color = color
			lamp.Light.Brightness = on and 1.6 or 0.8
			if on then
				CollectionService:RemoveTag(lamp.Light, FLICKER_TAG)
			else
				CollectionService:AddTag(lamp.Light, FLICKER_TAG)
			end
		end
	end

	-- รถเข็นตามทางตัน (ฟิวส์จะสุ่มอยู่บนรถเข็น)
	local fuseSpots = {}
	for _, d in ipairs(maze.deadEnds) do
		local c = d.pos
		part(f, Vector3.new(4, 0.4, 2.6), CFrame.new(c + Vector3.new(0, 2.8, 0)), Color3.fromRGB(170, 170, 175), M.Metal)
		part(f, Vector3.new(4, 0.3, 2.6), CFrame.new(c + Vector3.new(0, 1, 0)), Color3.fromRGB(170, 170, 175), M.Metal)
		for _, l in ipairs({ { -1.8, -1.1 }, { 1.8, -1.1 }, { -1.8, 1.1 }, { 1.8, 1.1 } }) do
			part(f, Vector3.new(0.25, 2.8, 0.25), CFrame.new(c + Vector3.new(l[1], 1.4, l[2])), Color3.fromRGB(120, 120, 125), M.Metal)
		end
		table.insert(fuseSpots, c + Vector3.new(0, 3, 0))
	end
	-- เผื่อทางตันมีน้อยกว่าจำนวนฟิวส์
	local cellsCopy = table.clone(maze.cells)
	while #fuseSpots < Config.Quest.Fuses + 2 and #cellsCopy > 0 do
		local cell = table.remove(cellsCopy, rng:NextInteger(1, #cellsCopy))
		if cell.j > 1 then
			table.insert(fuseSpots, cell.pos + Vector3.new(0, 0.1, 0))
		end
	end

	-- จุดตุ้งแช่ในตึก
	local triggers = {}
	local scares = { "Rush", "Face", "Blackout", "Drop", "Behind", "Rush", "Face", "Drop", "Blackout" }
	local pool = table.clone(maze.cells)
	for k = 1, #scares do
		local cell
		repeat
			cell = table.remove(pool, rng:NextInteger(1, #pool))
		until #pool == 0 or cell.j > 0
		local t = invisible(f, Vector3.new(C - 4, 10, C - 4), CFrame.new(cell.pos + Vector3.new(0, 5, 0)))
		t.Name = "ScareTrigger"
		t.CanTouch = true
		t:SetAttribute("ScareType", scares[k])
		t:SetAttribute("Stage", 4)
		table.insert(triggers, t)
	end

	local ghostSpawns = {
		maze.center(0, H - 1),
		maze.center(W - 1, H - 1),
		maze.center(0, 4),
		maze.center(W - 1, 4),
	}
	local patrol = {}
	for _, cell in ipairs(maze.cells) do
		table.insert(patrol, cell.pos)
	end

	local spawn = invisible(f, Vector3.new(1, 1, 1), CFrame.lookAt(maze.entry + Vector3.new(0, 3, 2), maze.entry + Vector3.new(0, 3, 12)))
	spawn.Name = "StageSpawn"

	return {
		Folder = f,
		Spawn = spawn,
		Portal = maze.portal,
		Door = maze.door,
		GeneratorPrompt = genPrompt,
		SetFuseSlot = setFuseSlot,
		SetPowered = setPowered,
		FuseSpots = fuseSpots,
		Triggers = triggers,
		GhostSpawns = ghostSpawns,
		Patrol = patrol,
		Dynamic = folder("Dynamic", f),
	}
end

-- ================= หน้าจบ =================

local function buildEnding(root)
	local O = Config.Origins[5]
	local f = folder("Ending", root)
	local rng = Random.new(55)

	ground(O + Vector3.new(0, 0, 60), Vector2.new(160, 160), M.LeafyGrass)
	ground(O + Vector3.new(0, 0, 60), Vector2.new(10, 120), M.Sand)
	invisible(f, Vector3.new(2, 40, 160), CFrame.new(O + Vector3.new(-60, 20, 60)), true)
	invisible(f, Vector3.new(2, 40, 160), CFrame.new(O + Vector3.new(60, 20, 60)), true)
	invisible(f, Vector3.new(120, 40, 2), CFrame.new(O + Vector3.new(0, 20, -4)), true)
	invisible(f, Vector3.new(120, 40, 2), CFrame.new(O + Vector3.new(0, 20, 125)), true)

	-- ต้นไม้เขียว
	for _ = 1, 26 do
		local x = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(12, 55)
		local pos = O + Vector3.new(x, 0, rng:NextNumber(5, 120))
		local h = rng:NextNumber(8, 14)
		part(f, Vector3.new(1.6, h, 1.6), CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color3.fromRGB(100, 70, 45), M.Wood)
		part(f, Vector3.new(9, 9, 9), CFrame.new(pos + Vector3.new(0, h + 2, 0)), Color3.fromRGB(60, rng:NextInteger(130, 170), 60), M.Grass, { Shape = Enum.PartType.Ball })
	end
	-- ดอกไม้
	local flowerColors = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 230, 90), Color3.fromRGB(150, 140, 255), Color3.new(1, 1, 1) }
	for _ = 1, 80 do
		local pos = O + Vector3.new(rng:NextNumber(-55, 55), 0.3, rng:NextNumber(2, 120))
		if math.abs(pos.X - O.X) > 6 then
			part(f, Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos), flowerColors[rng:NextInteger(1, #flowerColors)], M.SmoothPlastic, { CanCollide = false, Shape = Enum.PartType.Ball })
		end
	end

	-- ซุ้มประตูทางออก
	local white = Color3.fromRGB(235, 230, 220)
	part(f, Vector3.new(2, 14, 2), CFrame.new(O + Vector3.new(-7, 7, 40)), white, M.Marble)
	part(f, Vector3.new(2, 14, 2), CFrame.new(O + Vector3.new(7, 7, 40)), white, M.Marble)
	sign(f, Vector3.new(18, 4, 1.5), CFrame.lookAt(O + Vector3.new(0, 15, 40), O + Vector3.new(0, 15, 0)), {
		{ Text = "ทางออก", Color = Color3.fromRGB(60, 120, 60) },
	}, white)

	sign(f, Vector3.new(40, 14, 1), CFrame.lookAt(O + Vector3.new(0, 12, 80), O + Vector3.new(0, 12, 0)), {
		{ Text = "คุณรอดแล้ว!", Color = Color3.fromRGB(255, 220, 90), Weight = 2 },
		{ Text = "THANK YOU FOR PLAYING", Font = Enum.Font.Creepster, Color = Color3.new(1, 1, 1), Weight = 1 },
	}, Color3.fromRGB(40, 70, 40))

	local spawn = invisible(f, Vector3.new(1, 1, 1), CFrame.lookAt(O + Vector3.new(0, 3, 10), O + Vector3.new(0, 3, 50)))
	spawn.Name = "StageSpawn"
	return { Folder = f, Spawn = spawn }
end

-- ================= Build ทั้งหมด =================

function MapBuilder.build()
	if Config.RemoveBaseplate then
		local bp = workspace:FindFirstChild("Baseplate")
		if bp then
			bp:Destroy()
		end
	end
	local old = workspace:FindFirstChild("HorrorMap")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "HorrorMap"

	local map = {
		Root = root,
		Lobby = buildLobby(root),
		Stages = {
			[1] = buildStage1(root),
			[2] = buildStage2(root),
			[3] = buildStage3(root),
			[4] = buildStage4(root),
			[5] = buildEnding(root),
		},
	}
	root.Parent = workspace
	return map
end

MapBuilder.FlickerTag = FLICKER_TAG

return MapBuilder
