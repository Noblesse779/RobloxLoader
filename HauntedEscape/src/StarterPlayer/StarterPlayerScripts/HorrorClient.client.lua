--[[
	HAUNTED ESCAPE - Client
	วาง LocalScript นี้ (ชื่อ HorrorClient) ไว้ใน StarterPlayer > StarterPlayerScripts
	หน้าที่: UI, ตุ้งแช่, แสงแต่ละด่าน, วิ่ง/สตามิน่า, ไฟฉาย, เสียงหัวใจเมื่อผีใกล้, หน้าจบ
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("HorrorShared")
local Config = require(Shared:WaitForChild("Config"))
local GhostModel = require(Shared:WaitForChild("GhostModel"))
local Remotes = ReplicatedStorage:WaitForChild("HorrorRemotes")

local currentStage = 0
local HEAD = GhostModel.HeadHeight

-- ================= เสียง =================

local sounds = {}
local function makeSound(name, looped, volume)
	local id = Config.Sounds[name]
	if id == nil or id == "" then
		return
	end
	if tonumber(id) then
		id = "rbxassetid://" .. id
	end
	local s = Instance.new("Sound")
	s.Name = "Horror_" .. name
	s.SoundId = id
	s.Looped = looped
	s.Volume = volume
	s.Parent = SoundService
	sounds[name] = s
end
makeSound("Jumpscare", false, 1)
makeSound("Whisper", false, 0.8)
makeSound("Heartbeat", true, 0)
makeSound("Ambience", true, 0.4)
makeSound("LobbyMusic", true, 0.35)
makeSound("Pickup", false, 0.7)
makeSound("Door", false, 0.8)
makeSound("Portal", false, 0.8)
makeSound("Hit", false, 0.9)
makeSound("Victory", false, 0.8)

local function play(name)
	local s = sounds[name]
	if s then
		s:Play()
	end
end

-- ================= UI =================

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, scale)
	return make("UICorner", { CornerRadius = UDim.new(scale or 0.5, 0) }, parent)
end

local gui = make("ScreenGui", {
	Name = "HorrorUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
}, player:WaitForChild("PlayerGui"))

-- vignette แดงตอนผีอยู่ใกล้
local function edgeGradient(rotation)
	local f = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	make("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.22, 1),
			NumberSequenceKeypoint.new(0.78, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, f)
	return f
end
local vignettes = { edgeGradient(0), edgeGradient(90) }

-- หัวข้อด่าน + เป้าหมาย
local stageTitle = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 44),
	Size = UDim2.new(0.6, 0, 0, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(230, 40, 40),
	TextStrokeTransparency = 0.3,
	Text = "",
}, gui)
local objectiveLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.new(0.7, 0, 0, 24),
	BackgroundTransparency = 0.45,
	BackgroundColor3 = Color3.new(0, 0, 0),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	Visible = false,
}, gui)
corner(objectiveLabel, 0.3)
make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, objectiveLabel)

-- การแจ้งเตือน
local notifyList = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 115),
	Size = UDim2.new(0.6, 0, 0, 200),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, notifyList)
local notifyOrder = 0

local function notify(text, color)
	notifyOrder += 1
	local label = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color or Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		Text = text,
		LayoutOrder = notifyOrder,
	}, notifyList)
	local items = notifyList:GetChildren()
	local count = 0
	for _, c in ipairs(items) do
		if c:IsA("TextLabel") then
			count += 1
		end
	end
	if count > 5 then
		for _, c in ipairs(items) do
			if c:IsA("TextLabel") and c ~= label then
				c:Destroy()
				break
			end
		end
	end
	task.delay(4, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.6)
			label:Destroy()
		end
	end)
end

-- สตามิน่า
local staminaBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.new(0.22, 0, 0, 8),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
}, gui)
corner(staminaBack, 1)
local staminaFill = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(230, 230, 230),
	BorderSizePixel = 0,
}, staminaBack)
corner(staminaFill, 1)

make("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -14),
	Size = UDim2.new(0, 260, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(200, 200, 200),
	TextStrokeTransparency = 0.4,
	Text = "[Shift] วิ่ง    [F] ไฟฉาย",
}, gui)

local lobbyHint = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -120),
	Size = UDim2.new(0.6, 0, 0, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 220, 120),
	TextStrokeTransparency = 0.3,
	Text = "ยืนบนแท่นตามจำนวนคนในทีมเพื่อเริ่มเกม",
}, gui)

-- แฟลชแดง / จอดำ
local flashFrame = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(200, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 20,
}, gui)
local blackFrame = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 30,
}, gui)

-- หน้าผีตุ้งแช่ (วาดด้วย Frame ล้วน)
local scareFrame = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 25,
}, gui)
local face = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromScale(0.9, 0.9),
	BackgroundColor3 = Color3.fromRGB(215, 215, 205),
	BorderSizePixel = 0,
	ZIndex = 26,
}, scareFrame)
make("UIAspectRatioConstraint", { AspectRatio = 0.78 }, face)
corner(face, 0.5)
local function facePart(props)
	props.BorderSizePixel = 0
	props.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	props.ZIndex = props.ZIndex or 27
	return make("Frame", props, face)
end
for _, x in ipairs({ 0.3, 0.7 }) do
	local eye = facePart({ Position = UDim2.fromScale(x, 0.4), Size = UDim2.fromScale(0.26, 0.17), BackgroundColor3 = Color3.new(0, 0, 0) })
	corner(eye, 0.5)
	local pupil = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.22, 0.32),
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 28,
	}, eye)
	corner(pupil, 0.5)
	facePart({ Position = UDim2.fromScale(x, 0.6), Size = UDim2.fromScale(0.025, 0.25), BackgroundColor3 = Color3.fromRGB(120, 0, 0) })
end
local mouth = facePart({ Position = UDim2.fromScale(0.5, 0.76), Size = UDim2.fromScale(0.3, 0.26), BackgroundColor3 = Color3.new(0, 0, 0) })
corner(mouth, 0.5)
local mouthInner = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.6),
	Size = UDim2.fromScale(0.6, 0.5),
	BackgroundColor3 = Color3.fromRGB(90, 0, 0),
	BorderSizePixel = 0,
	ZIndex = 28,
}, mouth)
corner(mouthInner, 0.5)
facePart({ Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(1.15, 0.3), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 29 })
facePart({ Position = UDim2.fromScale(0.02, 0.55), Size = UDim2.fromScale(0.2, 1.1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 29 })
facePart({ Position = UDim2.fromScale(0.98, 0.55), Size = UDim2.fromScale(0.2, 1.1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 29 })

-- รูปตุ้งแช่ (ถ้าใส่ไว้ใน Config.Images.Jumpscare จะใช้รูปนี้แทนหน้าที่วาดด้วยโค้ด)
local function imageId(id)
	if id == nil or id == "" then
		return nil
	end
	return tonumber(id) and ("rbxassetid://" .. id) or id
end
local scareImageId = imageId(Config.Images and Config.Images.Jumpscare)
local scareImage = make("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = scareImageId or "",
	ScaleType = Enum.ScaleType.Crop,
	Visible = scareImageId ~= nil,
	ZIndex = 30,
}, scareFrame)
if scareImageId then
	face.Visible = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ scareImage })
		end)
	end)
end

-- หน้าจบ
local endFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 260),
	BackgroundColor3 = Color3.fromRGB(15, 12, 14),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 40,
}, gui)
corner(endFrame, 0.06)
make("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Thickness = 2 }, endFrame)
make("UISizeConstraint", { MaxSize = Vector2.new(420, 260) }, endFrame)
make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.06),
	Size = UDim2.fromScale(0.9, 0.3),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 215, 90),
	Text = "หนีรอดสำเร็จ!",
	ZIndex = 41,
}, endFrame)
local endTime = make("TextLabel", {
	Position = UDim2.fromScale(0.05, 0.38),
	Size = UDim2.fromScale(0.9, 0.16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	ZIndex = 41,
}, endFrame)
local endButton = make("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.64),
	Size = UDim2.fromScale(0.6, 0.22),
	BackgroundColor3 = Color3.fromRGB(150, 20, 20),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "กลับล็อบบี้",
	AutoButtonColor = true,
	ZIndex = 41,
}, endFrame)
corner(endButton, 0.25)
make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, endButton)

endButton.Activated:Connect(function()
	endButton.Text = "กำลังกลับ..."
	Remotes.ReturnToLobby:FireServer()
end)

-- ================= เอฟเฟกต์ =================

local camera = workspace.CurrentCamera
local shakeUntil, shakeMag = 0, 0
local function shake(duration, magnitude)
	shakeUntil = os.clock() + duration
	shakeMag = magnitude
end
RunService:BindToRenderStep("HorrorShake", Enum.RenderPriority.Camera.Value + 1, function()
	if os.clock() < shakeUntil then
		local m = shakeMag
		camera.CFrame = camera.CFrame
			* CFrame.Angles(math.rad((math.random() - 0.5) * m), math.rad((math.random() - 0.5) * m), 0)
	end
end)

local function redFlash(strength)
	flashFrame.BackgroundTransparency = 1 - (strength or 0.6)
	TweenService:Create(flashFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

local function fadeBlack(duration)
	blackFrame.BackgroundTransparency = 0
	task.delay(duration or 0.9, function()
		TweenService:Create(blackFrame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end)
end

local function showFace(duration)
	play("Jumpscare")
	scareFrame.Visible = true
	face.Size = UDim2.fromScale(0.25, 0.25)
	TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.1, 1.1) }):Play()
	scareImage.Size = UDim2.fromScale(0.4, 0.4)
	scareImage.Rotation = math.random(-8, 8)
	TweenService:Create(scareImage, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.25, 1.25) }):Play()
	redFlash(0.7)
	shake(duration, 7)
	task.delay(duration, function()
		scareFrame.Visible = false
	end)
end

local function flatLook()
	local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

local function localGhost(cf)
	local m = GhostModel.create({ name = "ScareGhost" })
	m:PivotTo(cf)
	m.Parent = workspace
	return m
end

local function tweenModel(model, target, time, style)
	local v = Instance.new("CFrameValue")
	v.Value = model:GetPivot()
	local conn = v.Changed:Connect(function(cf)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)
	local tw = TweenService:Create(v, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = target })
	tw.Completed:Connect(function()
		conn:Disconnect()
		v:Destroy()
	end)
	tw:Play()
	return tw
end

-- ปิด/เปิดไฟทั้งด่านเฉพาะเครื่องเรา
local function setStageLights(enabled, saved)
	local map = workspace:FindFirstChild("HorrorMap")
	local folderName = currentStage == 5 and "Ending" or ("Stage" .. currentStage)
	local stageFolder = map and map:FindFirstChild(folderName)
	saved = saved or {}
	if stageFolder then
		for _, d in ipairs(stageFolder:GetDescendants()) do
			if d:IsA("Light") then
				if not enabled then
					saved[d] = d.Enabled
					d.Enabled = false
				elseif saved[d] ~= nil then
					d.Enabled = saved[d]
				end
			end
		end
	end
	local head = player.Character and player.Character:FindFirstChild("Head")
	local flash = head and head:FindFirstChild("Flashlight")
	if flash then
		if not enabled then
			saved.__flash = flash.Enabled
			flash.Enabled = false
		elseif saved.__flash ~= nil then
			flash.Enabled = saved.__flash
		end
	end
	return saved
end

-- ================= ตุ้งแช่ =================

local scares = {}

function scares.Face()
	showFace(0.9)
end

function scares.Rush()
	local camPos = camera.CFrame.Position
	local look = flatLook()
	local start = camPos + look * 45 - Vector3.new(0, HEAD, 0)
	local finish = camPos + look * 2.6 - Vector3.new(0, HEAD, 0)
	local g = localGhost(CFrame.lookAt(start, start - look))
	play("Whisper")
	local tw = tweenModel(g, CFrame.lookAt(finish, finish - look), 0.55)
	tw.Completed:Wait()
	showFace(0.7)
	g:Destroy()
end

function scares.Blackout()
	local saved = setStageLights(false)
	local oldAmbient, oldOutdoor, oldBrightness = Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.Brightness = 0
	play("Whisper")
	notify("...ไฟดับ...", Color3.fromRGB(255, 60, 60))
	task.wait(2.3)
	Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.Brightness = oldAmbient, oldOutdoor, oldBrightness
	setStageLights(true, saved)
	local camPos = camera.CFrame.Position
	local look = flatLook()
	local pos = camPos + look * 4 - Vector3.new(0, HEAD, 0)
	local g = localGhost(CFrame.lookAt(pos, pos - look))
	play("Jumpscare")
	redFlash(0.5)
	shake(0.8, 6)
	task.wait(0.8)
	g:Destroy()
end

function scares.Drop()
	local camPos = camera.CFrame.Position
	local look = flatLook()
	local base = camPos + look * 6 - Vector3.new(0, HEAD, 0)
	local top = base + Vector3.new(0, 25, 0)
	local g = localGhost(CFrame.lookAt(top, top - look))
	play("Jumpscare")
	local tw = tweenModel(g, CFrame.lookAt(base, base - look), 0.25)
	tw.Completed:Wait()
	shake(0.6, 6)
	redFlash(0.5)
	task.wait(0.9)
	g:Destroy()
end

function scares.Behind()
	local camPos = camera.CFrame.Position
	local look = flatLook()
	local pos = camPos - look * 5 - Vector3.new(0, HEAD, 0)
	local g = localGhost(CFrame.lookAt(pos, pos + look))
	play("Whisper")
	notify("...หันหลังมาสิ...", Color3.fromRGB(255, 60, 60))
	local headPos = pos + Vector3.new(0, HEAD, 0)
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		local toGhost = headPos - camera.CFrame.Position
		if toGhost.Magnitude > 0.1 and camera.CFrame.LookVector:Dot(toGhost.Unit) > 0.6 then
			showFace(0.8)
			break
		end
		task.wait()
	end
	g:Destroy()
end

function scares.Whisper()
	play("Whisper")
	notify("...เราเห็นแกแล้ว...", Color3.fromRGB(255, 60, 60))
	shake(0.4, 2)
end

function scares.Hit()
	play("Hit")
	redFlash(0.65)
	shake(0.35, 4)
end

Remotes.Jumpscare.OnClientEvent:Connect(function(kind)
	local fn = scares[kind]
	if fn then
		task.spawn(fn)
	end
end)

-- ================= แสงแต่ละด่าน =================

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or make("Atmosphere", {}, Lighting)
local cc = make("ColorCorrectionEffect", { Name = "HorrorCC" }, Lighting)
local bloom = make("BloomEffect", { Name = "HorrorBloom", Intensity = 0.7, Size = 28, Threshold = 1.4 }, Lighting)
local dof = make("DepthOfFieldEffect", {
	Name = "HorrorDOF",
	FarIntensity = 0.35,
	FocusDistance = 12,
	InFocusRadius = 28,
	NearIntensity = 0,
}, Lighting)

-- หมอกลอยต่ำ + ฝุ่นรอบตัวผู้เล่น (เห็นแค่เครื่องเรา)
local fxPart = make("Part", {
	Name = "HorrorFX",
	Size = Vector3.new(60, 1, 60),
	Transparency = 1,
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
}, workspace)
local mist = make("ParticleEmitter", {
	Texture = "rbxasset://textures/particles/smoke_main.dds",
	Color = ColorSequence.new(Color3.fromRGB(160, 165, 175)),
	LightInfluence = 1,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Size = NumberSequence.new(12, 20),
	Lifetime = NumberRange.new(8, 12),
	Rate = 6,
	Speed = NumberRange.new(0.5, 1.5),
	SpreadAngle = Vector2.new(180, 0),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-8, 8),
	EmissionDirection = Enum.NormalId.Top,
	Enabled = false,
}, fxPart)
local dust = make("ParticleEmitter", {
	Color = ColorSequence.new(Color3.fromRGB(230, 225, 210)),
	LightInfluence = 1,
	LightEmission = 0.2,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Size = NumberSequence.new(0.08),
	Lifetime = NumberRange.new(6, 10),
	Rate = 25,
	Speed = NumberRange.new(0.2, 0.6),
	SpreadAngle = Vector2.new(180, 180),
	Enabled = false,
}, fxPart)
RunService.RenderStepped:Connect(function()
	local camPos = camera.CFrame.Position
	fxPart.CFrame = CFrame.new(camPos.X, camPos.Y - 4, camPos.Z)
end)

local PRESETS = {
	[0] = { Clock = 0, Brightness = 1, Ambient = Color3.fromRGB(60, 48, 60), Outdoor = Color3.fromRGB(60, 48, 60), Fog = Color3.fromRGB(25, 15, 25), Density = 0.3, Sat = -0.1, Contrast = 0.05, Tint = Color3.fromRGB(255, 235, 235) },
	[1] = { Clock = 0, Brightness = 0.6, Ambient = Color3.fromRGB(18, 18, 24), Outdoor = Color3.fromRGB(32, 32, 44), Fog = Color3.fromRGB(10, 10, 16), Density = 0.6, Sat = -0.35, Contrast = 0.15, Tint = Color3.fromRGB(215, 225, 255) },
	[2] = { Clock = 0, Brightness = 0.3, Ambient = Color3.fromRGB(8, 7, 8), Outdoor = Color3.fromRGB(8, 7, 8), Fog = Color3.fromRGB(5, 4, 4), Density = 0.45, Sat = -0.3, Contrast = 0.2, Tint = Color3.fromRGB(255, 225, 205) },
	[3] = { Clock = 0, Brightness = 0.7, Ambient = Color3.fromRGB(20, 26, 20), Outdoor = Color3.fromRGB(38, 50, 40), Fog = Color3.fromRGB(20, 40, 28), Density = 0.55, Sat = -0.25, Contrast = 0.15, Tint = Color3.fromRGB(215, 255, 220) },
	[4] = { Clock = 0, Brightness = 0.3, Ambient = Color3.fromRGB(8, 13, 9), Outdoor = Color3.fromRGB(8, 13, 9), Fog = Color3.fromRGB(4, 8, 5), Density = 0.45, Sat = -0.4, Contrast = 0.2, Tint = Color3.fromRGB(210, 255, 215) },
	[5] = { Clock = 6.6, Brightness = 2.2, Ambient = Color3.fromRGB(130, 120, 110), Outdoor = Color3.fromRGB(150, 140, 130), Fog = Color3.fromRGB(255, 210, 170), Density = 0.25, Sat = 0.1, Contrast = 0, Tint = Color3.fromRGB(255, 245, 230) },
}

local function applyLighting(stage)
	local p = PRESETS[stage] or PRESETS[0]
	Lighting.ClockTime = p.Clock
	Lighting.Brightness = p.Brightness
	Lighting.Ambient = p.Ambient
	Lighting.OutdoorAmbient = p.Outdoor
	Lighting.FogColor = p.Fog
	Lighting.FogStart = 0
	Lighting.FogEnd = 80 + (1 - p.Density) * 400
	atmosphere.Density = p.Density
	atmosphere.Offset = 0
	atmosphere.Color = p.Fog
	atmosphere.Decay = p.Fog
	atmosphere.Glare = 0
	atmosphere.Haze = stage == 5 and 1 or 2.5
	cc.Saturation = p.Sat
	cc.Contrast = p.Contrast
	cc.TintColor = p.Tint
	local inGame = stage >= 1 and stage <= 4
	mist.Enabled = stage == 1 or stage == 3
	dust.Enabled = stage ~= 5
	bloom.Intensity = stage == 5 and 0.4 or 0.8
	dof.FarIntensity = inGame and 0.4 or 0.15
	dof.InFocusRadius = (stage == 2 or stage == 4) and 20 or 35
end

-- ไฟกะพริบ (ทำฝั่งไคลเอนต์เพื่อไม่ให้หนักเน็ต)
task.spawn(function()
	while true do
		for _, l in ipairs(CollectionService:GetTagged("HorrorFlicker")) do
			if l:IsA("Light") then
				local base = l:GetAttribute("BaseBrightness") or 1
				local r = math.random()
				if r < 0.05 then
					l.Brightness = 0
				elseif r < 0.12 then
					l.Brightness = base * (0.3 + math.random() * 0.5)
				else
					l.Brightness = base
				end
			end
		end
		task.wait(0.1)
	end
end)

-- ================= กล้อง / เสียงบรรยากาศ =================

local function setCameraForStage(stage)
	local inGame = stage >= 1 and stage <= 4
	if Config.FirstPerson and inGame then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		if player.CameraMode == Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMinZoomDistance = 10
			task.delay(0.1, function()
				player.CameraMinZoomDistance = 0.5
			end)
		end
	end
end

local function setAmbience(stage)
	local amb, lobby = sounds.Ambience, sounds.LobbyMusic
	if amb then
		if stage >= 1 and stage <= 4 then
			if not amb.IsPlaying then
				amb:Play()
			end
		else
			amb:Stop()
		end
	end
	if lobby then
		if stage == 0 then
			if not lobby.IsPlaying then
				lobby:Play()
			end
		else
			lobby:Stop()
		end
	end
end

local function updateHud()
	local inGame = currentStage >= 1
	objectiveLabel.Visible = inGame and objectiveLabel.Text ~= ""
	lobbyHint.Visible = not inGame and not player:GetAttribute("InRun")
	if not inGame then
		stageTitle.Text = Config.GameTitle
	end
end

local function enterStage(stage, name, objective)
	currentStage = stage
	applyLighting(stage)
	setCameraForStage(stage)
	setAmbience(stage)
	stageTitle.Text = name or ""
	objectiveLabel.Text = objective or ""
	if stage ~= 5 then
		endFrame.Visible = false
	end
	updateHud()
	if stage >= 1 then
		stageTitle.TextTransparency = 1
		TweenService:Create(stageTitle, TweenInfo.new(1.2), { TextTransparency = 0 }):Play()
	end
end

Remotes.StageChanged.OnClientEvent:Connect(function(stage, name, objective)
	fadeBlack(0.6)
	enterStage(stage, name, objective)
	if stage == 5 then
		play("Victory")
	end
end)

Remotes.Objective.OnClientEvent:Connect(function(text)
	objectiveLabel.Text = text
	updateHud()
end)

Remotes.Notify.OnClientEvent:Connect(function(text, color)
	notify(text, color)
end)

Remotes.Transition.OnClientEvent:Connect(function()
	blackFrame.BackgroundTransparency = 1
	TweenService:Create(blackFrame, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	task.delay(2.5, function()
		if blackFrame.BackgroundTransparency < 0.05 then
			TweenService:Create(blackFrame, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		end
	end)
end)

Remotes.PlaySound.OnClientEvent:Connect(function(name)
	play(name)
end)

Remotes.GameEnded.OnClientEvent:Connect(function(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	endTime.Text = string.format("ใช้เวลา %d นาที %02d วินาที", m, s)
	endButton.Text = "กลับล็อบบี้"
	endFrame.Visible = true
end)

player:GetAttributeChangedSignal("InRun"):Connect(updateHud)

-- ================= วิ่ง + ไฟฉาย =================

local stamina = Config.StaminaMax
local sprintHeld = false
local exhausted = false
local flashlightOn = true

ContextActionService:BindAction("HorrorSprint", function(_, state)
	if state == Enum.UserInputState.Begin then
		sprintHeld = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sprintHeld = false
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("HorrorSprint", "วิ่ง")
ContextActionService:SetPosition("HorrorSprint", UDim2.new(1, -170, 1, -150))

ContextActionService:BindAction("HorrorFlashlight", function(_, state)
	if state == Enum.UserInputState.Begin then
		flashlightOn = not flashlightOn
		Remotes.Flashlight:FireServer(flashlightOn)
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
ContextActionService:SetTitle("HorrorFlashlight", "ไฟฉาย")
ContextActionService:SetPosition("HorrorFlashlight", UDim2.new(1, -230, 1, -90))

player.CharacterAdded:Connect(function()
	flashlightOn = true
	stamina = Config.StaminaMax
	exhausted = false
end)

-- ================= Loop หลัก =================

local heartbeatSound = sounds.Heartbeat

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")

	-- วิ่ง
	if hum then
		local moving = hum.MoveDirection.Magnitude > 0.1
		if exhausted and stamina > Config.StaminaMax * 0.3 then
			exhausted = false
		end
		if sprintHeld and moving and not exhausted and stamina > 0 then
			hum.WalkSpeed = Config.SprintSpeed
			stamina = math.max(0, stamina - Config.StaminaDrain * dt)
			if stamina <= 0 then
				exhausted = true
			end
		else
			hum.WalkSpeed = Config.WalkSpeed
			stamina = math.min(Config.StaminaMax, stamina + Config.StaminaRegen * dt)
		end
	end
	staminaFill.Size = UDim2.fromScale(stamina / Config.StaminaMax, 1)
	staminaFill.BackgroundColor3 = exhausted and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(230, 230, 230)
	staminaBack.Visible = stamina < Config.StaminaMax - 0.5

	-- ผีอยู่ใกล้ => ขอบจอแดง + หัวใจเต้น
	local intensity = 0
	if root and currentStage >= 1 and currentStage <= 4 then
		local folder = workspace:FindFirstChild("HorrorGhosts")
		if folder then
			for _, g in ipairs(folder:GetChildren()) do
				if g:GetAttribute("Stage") == currentStage and g.PrimaryPart then
					local d = (g.PrimaryPart.Position - root.Position).Magnitude
					intensity = math.max(intensity, math.clamp(1 - (d - 8) / 45, 0, 1))
				end
			end
		end
	end
	local pulse = 0.75 + 0.25 * math.sin(os.clock() * (6 + intensity * 6))
	for _, v in ipairs(vignettes) do
		v.BackgroundTransparency = 1 - intensity * 0.65 * pulse
	end
	if heartbeatSound then
		if intensity > 0 then
			if not heartbeatSound.IsPlaying then
				heartbeatSound:Play()
			end
			heartbeatSound.Volume = intensity
			heartbeatSound.PlaybackSpeed = 1 + intensity * 0.6
		elseif heartbeatSound.IsPlaying then
			heartbeatSound:Stop()
		end
	end
end)

-- เริ่มต้น
enterStage(player:GetAttribute("Stage") or 0, nil, nil)
stageTitle.Text = currentStage == 0 and Config.GameTitle or stageTitle.Text
