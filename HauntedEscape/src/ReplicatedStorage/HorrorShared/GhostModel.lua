--[[
	GhostModel : สร้างโมเดลผีจากพาร์ทล้วน ๆ
	ผีผู้หญิงตัวสูงผอม คอเอียง ผมดำยาวปิดหน้า แขนยาวเกือบถึงพื้น
	ถ้าใส่รูปไว้ที่ Config.Images.GhostFace จะเอารูปนั้นมาแปะเป็นหน้า
	ใช้ทั้งฝั่งเซิร์ฟเวอร์ (ผีไล่) และฝั่งไคลเอนต์ (ผีตุ้งแช่)
	ด้านหน้าของผี = LookVector ของ PrimaryPart
]]

local Config = require(script.Parent:WaitForChild("Config"))

local GhostModel = {}

GhostModel.HeadHeight = 3.9 -- ระยะจากจุดกลางตัวถึงหัว (คูณ scale)

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
	p.CastShadow = true
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

local function imageId(id)
	if id == nil or id == "" then
		return nil
	end
	if tonumber(id) then
		return "rbxassetid://" .. id
	end
	return id
end

function GhostModel.create(opts)
	opts = opts or {}
	local s = opts.scale or 1
	local skin = opts.color or Color3.fromRGB(196, 198, 200)
	local dress = Color3.fromRGB(170, 165, 150)
	local black = Color3.fromRGB(5, 5, 6)
	local dirt = Color3.fromRGB(90, 80, 70)

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

	-- ชุดขาวเก่า ๆ ยาวลากพื้น
	add(model, root, "Dress", Vector3.new(2.4, 6.6, 1.8) * s, CFrame.new(0, -0.6 * s, 0.15 * s), dress, Enum.Material.Fabric, "Ellipsoid")
	for i = -2, 2 do
		local strip = add(model, root, "Rag", Vector3.new(0.45, 2.8 + math.abs(i) * 0.3, 0.12) * s,
			CFrame.new(i * 0.42 * s, -3.6 * s, -0.55 * s) * CFrame.Angles(math.rad(8), 0, math.rad(i * 5)), dirt, Enum.Material.Fabric)
		strip.Transparency = 0.2
	end

	-- ไหล่ห่อ ตัวโน้มไปข้างหน้า
	add(model, root, "Shoulders", Vector3.new(2.3, 0.7, 1.1) * s, CFrame.new(0, 2.5 * s, -0.25 * s) * CFrame.Angles(math.rad(-15), 0, 0), dress, Enum.Material.Fabric)
	add(model, root, "Neck", Vector3.new(0.45, 1.1, 0.45) * s, CFrame.new(0.1 * s, 3.05 * s, -0.5 * s) * CFrame.Angles(math.rad(-25), 0, math.rad(-12)), skin)

	-- หัวเอียงผิดรูป
	local h = GhostModel.HeadHeight * s
	local headCF = CFrame.new(0.25 * s, h, -0.75 * s) * CFrame.Angles(math.rad(12), 0, math.rad(-22))
	add(model, root, "Head", Vector3.new(1.55, 1.95, 1.6) * s, headCF, skin, Enum.Material.SmoothPlastic, "Ellipsoid")

	local face = imageId(Config.Images and Config.Images.GhostFace)
	if face then
		local plate = add(model, root, "FacePlate", Vector3.new(1.45, 1.8, 0.05) * s, headCF * CFrame.new(0, -0.05 * s, -0.78 * s), skin)
		plate.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Front
		decal.Texture = face
		decal.Parent = plate
	else
		-- เบ้าตาดำ + ตาเรืองแสงขาว
		for _, x in ipairs({ -0.33, 0.33 }) do
			add(model, root, "Eye", Vector3.new(0.48, 0.42, 0.3) * s, headCF * CFrame.new(x * s, 0.18 * s, -0.68 * s), black, nil, "Ellipsoid")
			add(model, root, "Pupil", Vector3.new(0.12, 0.12, 0.12) * s, headCF * CFrame.new(x * s, 0.18 * s, -0.82 * s),
				Color3.fromRGB(255, 255, 230), Enum.Material.Neon, Enum.PartType.Ball)
		end
		-- ปากฉีกกว้างแนวตั้ง
		add(model, root, "Mouth", Vector3.new(0.42, 0.85, 0.3) * s, headCF * CFrame.new(0, -0.5 * s, -0.68 * s), black, nil, "Ellipsoid")
	end

	-- ผมดำยาวปิดหน้าครึ่งนึง
	add(model, root, "HairTop", Vector3.new(1.75, 0.7, 1.75) * s, headCF * CFrame.new(0, 0.75 * s, 0.05 * s), black, Enum.Material.Fabric, "Ellipsoid")
	add(model, root, "HairBack", Vector3.new(1.8, 5.2, 0.5) * s, headCF * CFrame.new(0, -2.0 * s, 0.6 * s), black, Enum.Material.Fabric)
	local strands = { -0.75, -0.55, -0.35, 0.45, 0.65, 0.8 }
	for k, x in ipairs(strands) do
		local len = (3.2 + (k % 3) * 0.6) * s
		add(model, root, "Hair", Vector3.new(0.18 * s, len, 0.12 * s),
			headCF * CFrame.new(x * s, 0.55 * s - len / 2, -0.62 * s) * CFrame.Angles(math.rad(4), 0, math.rad((x > 0 and -1 or 1) * 3)),
			black, Enum.Material.Fabric)
	end
	for _, x in ipairs({ -0.85, 0.85 }) do
		add(model, root, "HairSide", Vector3.new(0.3, 4.4, 1.4) * s, headCF * CFrame.new(x * s, -1.6 * s, 0), black, Enum.Material.Fabric)
	end

	-- แขนยาวผิดปกติ ห้อยเกือบถึงพื้น + นิ้วยาว
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = CFrame.new(side * 1.15 * s, 2.4 * s, -0.4 * s)
		local arm = shoulder * CFrame.Angles(math.rad(-18), 0, math.rad(side * 6)) * CFrame.new(0, -2.9 * s, 0)
		add(model, root, "Arm", Vector3.new(0.32, 5.8, 0.32) * s, arm, skin)
		local hand = arm * CFrame.new(0, -3.0 * s, 0)
		add(model, root, "Hand", Vector3.new(0.4, 0.5, 0.2) * s, hand, skin)
		for f = -1, 1 do
			add(model, root, "Finger", Vector3.new(0.08, 1.1, 0.08) * s, hand * CFrame.new(f * 0.13 * s, -0.75 * s, 0) * CFrame.Angles(math.rad(10), 0, math.rad(f * 6)), skin)
		end
	end

	-- แสงสลัวรอบตัว
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(180, 200, 255)
	glow.Range = 9 * s
	glow.Brightness = 0.6
	glow.Shadows = false
	glow.Parent = root

	return model
end

return GhostModel
