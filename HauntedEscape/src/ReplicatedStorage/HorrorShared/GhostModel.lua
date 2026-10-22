--[[
	GhostModel : สร้างโมเดลผีจากพาร์ทล้วน ๆ (ไม่ต้องใช้ asset)
	ใช้ทั้งฝั่งเซิร์ฟเวอร์ (ผีไล่) และฝั่งไคลเอนต์ (ผีตุ้งแช่)
	ด้านหน้าของผี = LookVector ของ PrimaryPart
]]

local GhostModel = {}

GhostModel.HeadHeight = 3.2 -- ระยะจากจุดกลางตัวถึงหัว (คูณ scale)

local function add(model, root, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

function GhostModel.create(opts)
	opts = opts or {}
	local s = opts.scale or 1
	local skin = opts.color or Color3.fromRGB(225, 225, 232)
	local black = Color3.fromRGB(8, 8, 10)

	local model = Instance.new("Model")
	model.Name = opts.name or "Ghost"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 2) * s
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root

	-- ตัว (ชุดขาวยาว)
	local body = add(model, root, "Body", Vector3.new(3, 5.5, 2.6) * s, CFrame.new(0, -0.4 * s, 0), skin, nil, "Ellipsoid")
	body.Transparency = 0.15

	-- ชายผ้าขาด ๆ ด้านล่าง
	for i = -1, 1 do
		add(model, root, "Rag", Vector3.new(0.7, 2.2, 0.4) * s,
			CFrame.new(i * 0.9 * s, -2.9 * s, -0.4 * s) * CFrame.Angles(0, 0, math.rad(i * 12)), skin).Transparency = 0.3
	end

	-- หัว
	local h = GhostModel.HeadHeight * s
	add(model, root, "Head", Vector3.new(2.3, 2.6, 2.3) * s, CFrame.new(0, h, 0), skin, nil, "Ellipsoid")

	-- ตาดำโบ๋ + ลูกตาแดง
	for _, x in ipairs({ -0.45, 0.45 }) do
		add(model, root, "Eye", Vector3.new(0.65, 0.8, 0.4) * s, CFrame.new(x * s, h + 0.25 * s, -1.0 * s), black, nil, "Ellipsoid")
		add(model, root, "Pupil", Vector3.new(0.22, 0.22, 0.22) * s, CFrame.new(x * s, h + 0.25 * s, -1.2 * s),
			Color3.fromRGB(255, 20, 20), Enum.Material.Neon, Enum.PartType.Ball)
		-- คราบเลือดไหลจากตา
		add(model, root, "Blood", Vector3.new(0.12, 0.9, 0.1) * s, CFrame.new(x * s, h - 0.4 * s, -1.08 * s),
			Color3.fromRGB(120, 0, 0))
	end

	-- ปากอ้ากว้าง
	add(model, root, "Mouth", Vector3.new(0.55, 0.9, 0.4) * s, CFrame.new(0, h - 0.6 * s, -0.98 * s), black, nil, "Ellipsoid")

	-- ผมดำยาว
	add(model, root, "HairBack", Vector3.new(2.5, 4.5, 0.6) * s, CFrame.new(0, h - 1.2 * s, 0.85 * s), black)
	add(model, root, "HairTop", Vector3.new(2.5, 0.8, 2.4) * s, CFrame.new(0, h + 1.05 * s, 0.05 * s), black)
	for _, x in ipairs({ -1.15, 1.15 }) do
		add(model, root, "HairSide", Vector3.new(0.45, 4.2, 1.8) * s, CFrame.new(x * s, h - 1.0 * s, -0.1 * s), black)
	end

	-- แขนยื่นมาข้างหน้า
	for _, x in ipairs({ -1.5, 1.5 }) do
		add(model, root, "Arm", Vector3.new(0.45, 0.45, 3.2) * s,
			CFrame.new(x * s, 1.2 * s, -1.5 * s) * CFrame.Angles(math.rad(-10), math.rad(-x * 4), 0), skin)
		add(model, root, "Hand", Vector3.new(0.6, 0.25, 0.9) * s, CFrame.new(x * s, 1.0 * s, -3.2 * s), skin)
	end

	-- แสงแดงจาง ๆ รอบตัว
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 60, 60)
	glow.Range = 10 * s
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = root

	return model
end

return GhostModel
