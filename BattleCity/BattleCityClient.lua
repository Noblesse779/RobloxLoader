-- BattleCityClient (LocalScript) — วางที่ StarterPlayer > StarterPlayerScripts
-- ฝั่งผู้เล่น: กล้องมองทั้งสนาม, ส่งปุ่มกดให้ server, วาด HUD และหน้าจอต่างๆ แบบเครื่อง NES (ชื่อในเกม "TANK CITY")
-- คุยกับ server ผ่าน ReplicatedStorage.BattleCity (attribute + RemoteEvent "Input") และ attribute BattleCitySlot ของผู้เล่นเท่านั้น
-- ทุกค่าจาก server อาจยังไม่มา (nil) หรือมาไม่เรียงลำดับ จึงอ่านแบบมีค่าเริ่มต้นเสมอ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer

---------------------------------------------------------------- ค่าคงที่
local MARGIN = 8 -- ขอบรอบสนามที่ต้องเห็นเสมอ (stud)
local TILT = 0.03 -- เอียงกล้องนิดเดียว ให้ "ขึ้นบนจอ" = -Z ชัดเจน
-- มุมกล้องแคบ (กล้องอยู่สูง) ภาพเกือบแบนแบบ 2D ของ NES: กำแพงขอบสนามไม่เอียงออก ต้นไม้บังรถถังสนิท
local CAMERA_FOV = 25
local HOLE_TOP = 8 -- ช่องมองสนามต้องรวมของสูงสุด 8 stud เหนือพื้น (กำแพง 6, ต้นไม้ 6.2, ไอเท็ม 7.5)
local HUD_SIDE = 0.2 -- จอแนวนอน: เว้นข้างละ 20% ของความสูงจอไว้ให้แผงข้าง
local HUD_TOP = 0.22 -- จอแนวตั้ง: เว้นบน/ล่างไว้ให้ HUD และปุ่มสัมผัส
local DEFAULT_CENTER = Vector3.new(52, 1, 52)
local DEFAULT_SIZE = Vector3.new(104, 0, 104)

local CURTAIN_TIME = 0.5 -- ม่านปิด/เปิดตอนเริ่มด่าน (วินาที)
local GAMEOVER_RISE = 2.5 -- ตัวหนังสือ GAME OVER ลอยจากล่างขึ้นกลางสนาม
local TALLY_HEAD = 0.5 -- หน้าสรุปคะแนน: รอก่อนเริ่มนับแถวแรก
local TALLY_STEP = 0.12 -- นับทีละคันทุก 0.12 วิ
local TALLY_ROWMAX = 0.8 -- แถวหนึ่งนับไม่เกิน 0.8 วิ (หน้าสรุปมีเวลาแค่ 6 วิ)
local TALLY_GAP = 0.2
local TALLY_BONUS_DELAY = 0.4
local KIND_POINTS = { 100, 200, 300, 400 }
local KIND_KEYS = { "b", "f", "p", "a" }

-- สีจากพาเลตต์ NES
local C = {
	gray = Color3.fromRGB(99, 99, 99),
	black = Color3.fromRGB(0, 0, 0),
	white = Color3.fromRGB(255, 255, 255),
	red = Color3.fromRGB(181, 49, 32),
	orange = Color3.fromRGB(234, 158, 34),
	brick = Color3.fromRGB(228, 92, 16),
	yellow = Color3.fromRGB(232, 208, 32),
	green = Color3.fromRGB(0, 168, 0),
	dark = Color3.fromRGB(24, 24, 24),
}
local FONT = Enum.Font.Arcade
local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right
local Z_BACK, Z_FIELD, Z_HUD, Z_TOUCH, Z_CURTAIN, Z_SCREEN, Z_TOP = 1, 2, 3, 4, 6, 7, 9

-- รูป pixel art ทำจากสี่เหลี่ยม { x, y, w, h } บนตารางเล็กๆ
local ICON_TANK = { { 0, 1, 2, 6 }, { 5, 1, 2, 6 }, { 2, 2, 3, 4 }, { 3, 0, 1, 3 } } -- 7x7
local KIND_ICONS = { -- 9x9 รถถังแต่ละชนิดในหน้าสรุป
	{ { 0, 2, 2, 7 }, { 7, 2, 2, 7 }, { 2, 3, 5, 5 }, { 4, 0, 1, 4 } }, -- basic
	{ { 1, 1, 2, 8 }, { 6, 1, 2, 8 }, { 3, 3, 3, 5 }, { 4, 0, 1, 4 } }, -- fast ตัวเพรียว
	{ { 0, 3, 2, 6 }, { 7, 3, 2, 6 }, { 2, 4, 5, 4 }, { 4, 0, 1, 5 } }, -- power ลำกล้องยาว
	{ { 0, 1, 2, 8 }, { 7, 1, 2, 8 }, { 2, 2, 5, 7 }, { 3.5, 0, 2, 3 } }, -- armor ตัวหนา
}
local ARROW_LEFT = { { 0, 3, 1, 2 }, { 1, 2, 1, 4 }, { 2, 1, 1, 6 }, { 3, 3, 5, 2 } } -- 8x8
local ARROW_RIGHT = { { 7, 3, 1, 2 }, { 6, 2, 1, 4 }, { 5, 1, 1, 6 }, { 0, 3, 5, 2 } }
local FLAG_POLE = { { 3, 0, 2, 16 } } -- 16x16
local FLAG_CLOTH = { { 5, 1, 9, 7 } }
local TRI = { -- 5x5 ลูกศรบนปุ่มทิศ (index = dir + 1)
	{ { 2, 1, 1, 1 }, { 1, 2, 3, 1 }, { 0, 3, 5, 1 } },
	{ { 1, 0, 1, 5 }, { 2, 1, 1, 3 }, { 3, 2, 1, 1 } },
	{ { 0, 1, 5, 1 }, { 1, 2, 3, 1 }, { 2, 3, 1, 1 } },
	{ { 3, 0, 1, 5 }, { 2, 1, 1, 3 }, { 1, 2, 1, 1 } },
}

---------------------------------------------------------------- ตัวช่วยทั่วไป
-- error ในตัวจัดการ event ไม่ควรทำให้ทั้งเกมพัง: เตือนครั้งเดียวต่อจุดแล้วทำงานต่อ
local reported = {}
local function report(where, err)
	if not reported[where] then
		reported[where] = true
		warn("BattleCityClient [" .. where .. "]: " .. tostring(err))
	end
end
local function guard(where, fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			report(where, err)
		end
	end
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function fmtInt(v)
	if type(v) ~= "number" or v ~= v then
		return "0"
	end
	if v < 0 then
		v = 0
	end
	if v > 999999999 then
		v = 999999999
	end
	return tostring(math.floor(v))
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

-- ค่าจาก folder ของ server (อาจยังไม่มี)
local folder = nil
local inputRemote = nil

local function attr(name)
	if folder == nil then
		return nil
	end
	return folder:GetAttribute(name)
end
local function num(name, default)
	local v = attr(name)
	if type(v) == "number" and v == v and v > -1e15 and v < 1e15 then
		return v
	end
	return default
end
local function str(name)
	local v = attr(name)
	if type(v) == "string" then
		return v
	end
	return nil
end
local function getSlot()
	local v = player:GetAttribute("BattleCitySlot")
	if type(v) == "number" then
		return v
	end
	return nil
end

local function mapGeometry()
	local c = attr("MapCenter")
	local s = attr("MapSize")
	if typeof(c) ~= "Vector3" then
		c = DEFAULT_CENTER
	end
	if typeof(s) ~= "Vector3" or s.X <= 0 or s.Z <= 0 then
		s = DEFAULT_SIZE
	end
	return c, s
end

---------------------------------------------------------------- สร้าง GUI
local function make(className, name, parent, props)
	local o = Instance.new(className)
	o.Name = name
	if props then
		for k, v in pairs(props) do
			o[k] = v
		end
	end
	o.Parent = parent
	return o
end

local function box(name, parent, color, z, transparency)
	return make("Frame", name, parent, {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z,
	})
end

local function holder(name, parent, z) -- frame โปร่งใสไว้จัดกลุ่ม
	return box(name, parent, C.black, z, 1)
end

local function label(name, parent, s, color, z, align)
	return make("TextLabel", name, parent, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT,
		Text = s,
		TextColor3 = color,
		TextScaled = true,
		TextXAlignment = align or CENTER,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z,
	})
end

-- วางด้วย Scale ล้วนบน "ผ้าใบ" ขนาด cw x ch (หน่วยพิกเซล NES) -> ย่อขยายตามจอเองทั้งมือถือและคอม
local function place(g, cw, ch, x, y, w, h)
	g.Position = UDim2.fromScale(x / cw, y / ch)
	g.Size = UDim2.fromScale(w / cw, h / ch)
end

local function aspect(g, ratio)
	return make("UIAspectRatioConstraint", "Aspect", g, { AspectRatio = ratio })
end

local function noInput(g) -- ของตกแต่งไม่รับการแตะ ให้ปุ่มแม่รับแทน
	pcall(function()
		g.Interactable = false
	end)
end

local function drawRects(parent, gw, gh, rects, color, z, prefix)
	for i, r in ipairs(rects) do
		local f = box((prefix or "Px") .. i, parent, color, z)
		place(f, gw, gh, r[1], r[2], r[3], r[4])
		noInput(f)
	end
end

local function brickText(name, parent, s, z) -- ตัวหนังสือสีอิฐแบบ GAME OVER ของ NES
	local t = label(name, parent, s, C.brick, z)
	t.TextStrokeColor3 = C.red
	t.TextStrokeTransparency = 0
	return t
end

local function fullScreen(name, color, z) -- จอดำเต็มจอ + กล่องเนื้อหาสัดส่วนจอ NES (256x240)
	local screen = box(name, nil, color, z)
	screen.Size = UDim2.fromScale(1, 1)
	screen.Visible = false
	local content = holder("Content", screen, 1)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	aspect(content, 256 / 240)
	return screen, content
end

local playerGui = player:WaitForChild("PlayerGui")
do
	local old = playerGui:FindFirstChild("BattleCityHUD")
	if old then
		old:Destroy() -- กัน HUD ซ้อนถ้าสคริปต์ถูกรันซ้ำ
	end
end

local ui = {} -- เก็บอ้างอิง GUI ทั้งหมดในตารางเดียว (กันชนลิมิต upvalue ของ Lua 5.1)

local gui = Instance.new("ScreenGui")
gui.Name = "BattleCityHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)
pcall(function()
	gui.ClipToDeviceSafeArea = false
end)
gui.IgnoreGuiInset = true -- พิกัด GUI = พิกัดจอ 3D ตรงกัน จึงวาง HUD รอบสนามได้แม่น
ui.gui = gui

-- พื้นเทา 4 ชิ้นรอบช่องสนาม: จอทั้งจอเป็นสีเทาแบบ NES เห็น 3D เฉพาะในสนาม
ui.backdrop = {}
for _, n in ipairs({ "BackdropLeft", "BackdropRight", "BackdropTop", "BackdropBottom" }) do
	ui.backdrop[n] = box(n, gui, C.gray, Z_BACK)
end

-- กรอบตรงกับพื้นสนามบนจอ (ไว้ให้ GAME OVER ลอยขึ้นในสนาม ถูกตัดที่ขอบเหมือน NES)
ui.field = holder("FieldFrame", gui, Z_FIELD)
ui.field.ClipsDescendants = true
ui.gameOverRise = holder("GameOverRise", ui.field, 1)
ui.gameOverRise.AnchorPoint = Vector2.new(0.5, 0.5)
ui.gameOverRise.Size = UDim2.fromScale(0.24, 0.12)
ui.gameOverRise.Position = UDim2.fromScale(0.5, 1.2)
ui.gameOverRise.Visible = false
place(brickText("Line1", ui.gameOverRise, "GAME", 1), 1, 2, 0, 0, 1, 1)
place(brickText("Line2", ui.gameOverRise, "OVER", 1), 1, 2, 0, 1, 1, 1)

-- คะแนน 1P / HI / 2P (จอนอน: คอลัมน์ซ้ายของสนาม, จอตั้ง: แถบบนสนาม)
ui.scoreArea = holder("ScoreArea", gui, Z_HUD)
ui.scoreAspect = aspect(ui.scoreArea, 48 / 80)
ui.label1P = label("Label1P", ui.scoreArea, "1P", C.black, 1, LEFT)
ui.score1P = label("Score1P", ui.scoreArea, "0", C.white, 1, RIGHT)
ui.labelHI = label("LabelHI", ui.scoreArea, "HI", C.black, 1, LEFT)
ui.scoreHI = label("ScoreHI", ui.scoreArea, "20000", C.orange, 1, RIGHT)
ui.label2P = label("Label2P", ui.scoreArea, "2P", C.black, 1, LEFT)
ui.score2P = label("Score2P", ui.scoreArea, "0", C.white, 1, RIGHT)

-- แผงข้างสีเทาแบบ NES: ไอคอนศัตรูที่เหลือ 20 ตัว, IP/IIP + ชีวิต, ธง + เลขด่าน
ui.panel = holder("SidePanel", gui, Z_HUD)
ui.panelAspect = aspect(ui.panel, 32 / 208)
ui.reserveFrame = holder("ReserveIcons", ui.panel, 1)
ui.reserveFrame.Size = UDim2.fromScale(1, 1)
ui.reserve = {}
for k = 1, 20 do
	local icon = holder("Reserve" .. k, ui.reserveFrame, 1)
	drawRects(icon, 7, 7, ICON_TANK, C.black, 1)
	icon.Visible = false
	ui.reserve[k] = icon
end
local function livesGroup(name, text)
	-- กลุ่ม 24x16: ป้าย "IP" แถวบน, ไอคอนรถถัง + จำนวนชีวิตแถวล่าง
	local g = holder(name, ui.panel, 1)
	-- "IP" กว้าง 16, "IIP" กว้าง 24 -> ตัวอักษรสูงเท่ากัน
	place(label("Label", g, text, C.black, 1, LEFT), 24, 16, 4 - (#text - 2) * 4, 0, 16 + (#text - 2) * 8, 8)
	local icon = holder("Icon", g, 1)
	place(icon, 24, 16, 4, 8, 7, 7)
	drawRects(icon, 7, 7, ICON_TANK, C.brick, 1)
	local lives = label("Lives", g, "0", C.black, 1, LEFT)
	place(lives, 24, 16, 12, 8, 12, 8)
	return g, lives
end
ui.ipGroup, ui.ipLives = livesGroup("IPGroup", "IP")
ui.iipGroup, ui.iipLives = livesGroup("IIPGroup", "IIP")
ui.stageGroup = holder("StageGroup", ui.panel, 1)
do
	local flag = holder("Flag", ui.stageGroup, 1)
	place(flag, 16, 24, 0, 0, 16, 16)
	drawRects(flag, 16, 16, FLAG_POLE, C.black, 1, "Pole")
	drawRects(flag, 16, 16, FLAG_CLOTH, C.brick, 1, "Cloth")
	ui.stageNum = label("StageNum", ui.stageGroup, "1", C.black, 1, RIGHT)
	place(ui.stageNum, 16, 24, 0, 16, 16, 8)
end

-- คำแนะนำปุ่ม (เฉพาะเครื่องที่มีคีย์บอร์ด และไม่มีจอสัมผัส)
ui.help = holder("HelpText", gui, Z_HUD)
ui.help.Visible = UserInputService.KeyboardEnabled == true
place(label("Move", ui.help, "MOVE: WASD / ARROWS", C.black, 1, LEFT), 1, 2, 0, 0, 1, 1)
place(label("Fire", ui.help, "FIRE: SPACE / J / Z", C.black, 1, LEFT), 1, 2, 0, 1, 1, 1)

-- ปุ่มสัมผัส: สร้างเฉพาะเครื่องที่มีจอสัมผัส
ui.touch = UserInputService.TouchEnabled == true
ui.dpadArms = {}
if ui.touch then
	ui.help.Visible = false
	ui.dpad = holder("DPad", gui, Z_TOUCH)
	ui.dpad.Active = true
	aspect(ui.dpad, 1)
	local armCell = { { 1, 0 }, { 2, 1 }, { 1, 2 }, { 0, 1 } } -- ขึ้น ขวา ลง ซ้าย บนตาราง 3x3
	for d = 0, 3 do
		local arm = box("Arm" .. d, ui.dpad, C.dark, 1, 0.3)
		place(arm, 3, 3, armCell[d + 1][1], armCell[d + 1][2], 1, 1)
		noInput(arm)
		local tri = holder("Arrow", arm, 2)
		place(tri, 5, 5, 1, 1, 3, 3)
		noInput(tri)
		drawRects(tri, 5, 5, TRI[d + 1], C.white, 2)
		ui.dpadArms[d] = arm
	end
	local hub = box("Hub", ui.dpad, C.dark, 1, 0.3)
	place(hub, 3, 3, 1, 1, 1, 1)
	noInput(hub)

	ui.fire = box("FireButton", gui, C.red, Z_TOUCH, 0.15)
	ui.fire.Active = true
	aspect(ui.fire, 1)
	make("UICorner", "Corner", ui.fire, { CornerRadius = UDim.new(0.5, 0) })
	make("UIStroke", "Stroke", ui.fire, { Color = C.white, Thickness = 2 })
	local fl = label("Label", ui.fire, "FIRE", C.white, 2)
	place(fl, 10, 10, 1.5, 3, 7, 4)
	noInput(fl)
end

-- ม่านเริ่มด่าน: เทาปิดจากบน-ล่าง โชว์ "STAGE n" แล้วเปิด
ui.intro = holder("IntroOverlay", gui, Z_CURTAIN)
ui.intro.Size = UDim2.fromScale(1, 1)
ui.intro.Visible = false
-- ม่านปิดทับจอดำ (เหมือน NES ที่ปิดทับหน้าจอเดิม) แผนที่ใหม่จะโผล่ตอนม่านเปิดเท่านั้น
ui.introBacking = box("Backing", ui.intro, C.black, 1)
ui.introBacking.Size = UDim2.fromScale(1, 1)
ui.curtainTop = box("CurtainTop", ui.intro, C.gray, 2)
ui.curtainTop.Size = UDim2.fromScale(1, 0.51)
ui.curtainTop.Position = UDim2.fromScale(0, -0.51)
ui.curtainBottom = box("CurtainBottom", ui.intro, C.gray, 2)
ui.curtainBottom.Size = UDim2.fromScale(1, 0.51)
ui.curtainBottom.Position = UDim2.fromScale(0, 1)
ui.stageBox = holder("StageTextBox", ui.intro, 3)
ui.stageBox.AnchorPoint = Vector2.new(0.5, 0.5)
ui.stageBox.Position = UDim2.fromScale(0.5, 0.5)
ui.stageBox.Size = UDim2.fromScale(0.45, 0.06)
ui.stageBox.Visible = false
aspect(ui.stageBox, 8)
ui.stageText = label("StageText", ui.stageBox, "STAGE 1", C.black, 3)
ui.stageText.Size = UDim2.fromScale(1, 1)

-- หน้าสรุปคะแนนท้ายด่าน (จอดำ) จัดตามตำแหน่งจริงบนจอ NES 256x240
do
	local screen, content = fullScreen("TallyScreen", C.black, Z_SCREEN)
	screen.Parent = gui
	local T = { screen = screen, rows = {} }
	local function lab(name, s, color, x, y, w, h, align)
		local l = label(name, content, s, color, 1, align)
		place(l, 256, 240, x, y, w, h)
		return l
	end
	T.hiLabel = lab("HiLabel", "HI-SCORE", C.red, 40, 20, 88, 8, RIGHT)
	T.hiValue = lab("HiValue", "20000", C.orange, 140, 20, 80, 8, LEFT)
	T.stage = lab("StageLabel", "STAGE 1", C.white, 80, 40, 96, 8, CENTER)
	T.p1Name = lab("P1Name", "I-PLAYER", C.red, 16, 60, 88, 8, RIGHT)
	T.p1Score = lab("P1Score", "0", C.orange, 16, 72, 88, 8, RIGHT)
	T.p2Name = lab("P2Name", "II-PLAYER", C.red, 152, 60, 88, 8, RIGHT)
	T.p2Score = lab("P2Score", "0", C.orange, 152, 72, 88, 8, RIGHT)
	for r = 1, 4 do
		local rowFrame = holder("Row" .. r, content, 1)
		place(rowFrame, 256, 240, 0, 88 + (r - 1) * 24, 256, 16)
		local row = { frame = rowFrame }
		local function rl(name, s, x, w, align)
			local l = label(name, rowFrame, s, C.white, 1, align)
			place(l, 256, 16, x, 4, w, 8)
			return l
		end
		row.p1Pts = rl("P1Pts", "0", 8, 56, RIGHT)
		row.p1Word = rl("P1Word", "PTS", 68, 24, LEFT)
		row.p1Kills = rl("P1Kills", "0", 92, 18, RIGHT)
		row.arrowLeft = holder("ArrowLeft", rowFrame, 1)
		place(row.arrowLeft, 256, 16, 112, 4, 8, 8)
		drawRects(row.arrowLeft, 8, 8, ARROW_LEFT, C.white, 1)
		local icon = holder("Icon", rowFrame, 1)
		place(icon, 256, 16, 121, 1, 14, 14)
		drawRects(icon, 9, 9, KIND_ICONS[r], C.white, 1)
		row.arrowRight = holder("ArrowRight", rowFrame, 1)
		place(row.arrowRight, 256, 16, 136, 4, 8, 8)
		drawRects(row.arrowRight, 8, 8, ARROW_RIGHT, C.white, 1)
		row.p2Kills = rl("P2Kills", "0", 146, 18, RIGHT)
		row.p2Pts = rl("P2Pts", "0", 166, 48, RIGHT)
		row.p2Word = rl("P2Word", "PTS", 218, 24, LEFT)
		T.rows[r] = row
	end
	local line = box("Line", content, C.white, 1)
	place(line, 256, 240, 96, 186, 64, 2)
	T.totalLabel = lab("TotalLabel", "TOTAL", C.white, 40, 192, 48, 8, LEFT)
	T.totalP1 = lab("TotalP1", "0", C.white, 92, 192, 18, 8, RIGHT)
	T.totalP2 = lab("TotalP2", "0", C.white, 146, 192, 18, 8, RIGHT)
	local function bonusBox(name, x)
		local g = holder(name, content, 1)
		place(g, 256, 240, x, 212, 112, 8)
		place(label("Label", g, "BONUS", C.red, 1, LEFT), 112, 8, 0, 0, 44, 8)
		local v = label("Value", g, "1000 PTS", C.white, 1, LEFT)
		place(v, 112, 8, 50, 0, 62, 8)
		g.Visible = false
		return g, v
	end
	T.bonusP1, T.bonusP1Value = bonusBox("BonusP1", 8)
	T.bonusP2, T.bonusP2Value = bonusBox("BonusP2", 136)
	ui.tally = T
end

-- จอ GAME OVER ใหญ่ตอนจบเกม
do
	local screen, content = fullScreen("FinalScreen", C.black, Z_SCREEN)
	screen.Parent = gui
	place(brickText("Line1", content, "GAME", 1), 256, 240, 48, 72, 160, 44)
	place(brickText("Line2", content, "OVER", 1), 256, 240, 48, 124, 160, 44)
	ui.final = screen
end

-- จอรอผู้เล่น / กำลังโหลด
do
	local screen, content = fullScreen("WaitingScreen", C.black, Z_SCREEN)
	screen.Parent = gui
	place(brickText("Title1", content, "TANK", 1), 256, 240, 40, 48, 176, 40)
	place(brickText("Title2", content, "CITY", 1), 256, 240, 40, 96, 176, 40)
	ui.waitingText = label("WaitingText", content, "LOADING...", C.white, 1)
	place(ui.waitingText, 256, 240, 16, 168, 224, 10)
	ui.waiting = screen
	screen.Visible = true
end

ui.spectator = label("SpectatorLabel", gui, "SPECTATING (2 players max)", C.white, Z_TOP)
ui.spectator.TextStrokeTransparency = 0
ui.spectator.TextWrapped = true
ui.spectator.Visible = false

gui.Parent = playerGui

---------------------------------------------------------------- จัดวาง HUD ตามขนาดจอ
local function setRect(g, vpX, vpY, x, y, w, h)
	g.AnchorPoint = Vector2.new(0, 0)
	g.Position = UDim2.fromScale(x / vpX, y / vpY)
	g.Size = UDim2.fromScale(math.max(w, 0) / vpX, math.max(h, 0) / vpY)
end

local function fitBox(maxW, maxH, ratio) -- กล่องใหญ่สุดสัดส่วน ratio (กว้าง/สูง) ที่ใส่ใน maxW x maxH ได้
	maxW, maxH = math.max(maxW, 0), math.max(maxH, 0)
	local w, h = maxW, maxW / ratio
	if h > maxH then
		h = maxH
		w = h * ratio
	end
	return w, h
end

local function arrangeScore(landscape)
	if landscape then
		ui.scoreAspect.AspectRatio = 48 / 80
		place(ui.label1P, 48, 80, 0, 0, 48, 8)
		place(ui.score1P, 48, 80, 0, 10, 48, 8)
		place(ui.labelHI, 48, 80, 0, 28, 48, 8)
		place(ui.scoreHI, 48, 80, 0, 38, 48, 8)
		place(ui.label2P, 48, 80, 0, 56, 48, 8)
		place(ui.score2P, 48, 80, 0, 66, 48, 8)
	else
		ui.scoreAspect.AspectRatio = 208 / 10
		place(ui.label1P, 208, 10, 0, 1, 16, 8)
		place(ui.score1P, 208, 10, 18, 1, 50, 8)
		place(ui.labelHI, 208, 10, 74, 1, 16, 8)
		place(ui.scoreHI, 208, 10, 92, 1, 50, 8)
		place(ui.label2P, 208, 10, 148, 1, 16, 8)
		place(ui.score2P, 208, 10, 166, 1, 42, 8)
	end
	local numAlign = landscape and RIGHT or LEFT
	ui.score1P.TextXAlignment = numAlign
	ui.scoreHI.TextXAlignment = numAlign
	ui.score2P.TextXAlignment = numAlign
end

local function arrangePanel(landscape)
	-- ไอคอนเรียงเป็นคู่ (ซ้าย-ขวา) จากบนลงล่างแบบ NES; ตัวท้ายๆ หายก่อน
	if landscape then
		ui.panelAspect.AspectRatio = 32 / 208
		for k = 1, 20 do
			place(ui.reserve[k], 32, 208, 8 + 8 * ((k - 1) % 2), 16 + 8 * math.floor((k - 1) / 2), 7, 7)
		end
		place(ui.ipGroup, 32, 208, 4, 128, 24, 16)
		place(ui.iipGroup, 32, 208, 4, 152, 24, 16)
		place(ui.stageGroup, 32, 208, 8, 176, 16, 24)
	else
		-- จอตั้ง: แผงกลายเป็นแถบแนวนอน (คู่ไอคอนเรียงซ้ายไปขวา)
		ui.panelAspect.AspectRatio = 208 / 24
		for k = 1, 20 do
			place(ui.reserve[k], 208, 24, 8 + 8 * math.floor((k - 1) / 2), 4 + 8 * ((k - 1) % 2), 7, 7)
		end
		place(ui.ipGroup, 208, 24, 100, 4, 24, 16)
		place(ui.iipGroup, 208, 24, 128, 4, 24, 16)
		place(ui.stageGroup, 208, 24, 164, 0, 16, 24)
	end
end

local function relayout(vpX, vpY, floor, hole)
	local landscape = vpX >= vpY
	local unit = math.min(vpX, vpY)
	local gap = math.max(3, unit * 0.015)
	local pad = math.max(6, unit * 0.03)
	local floorW, floorH = floor.x1 - floor.x0, floor.y1 - floor.y0
	-- ความสูงแถบปุ่มของ Roblox ด้านบนจอ (พิกัด GUI ของเราเริ่มที่ขอบจอบนสุด)
	local topInset = 0
	pcall(function()
		topInset = GuiService:GetGuiInset().Y
	end)

	local b = ui.backdrop
	setRect(b.BackdropLeft, vpX, vpY, 0, 0, hole.x0, vpY)
	setRect(b.BackdropRight, vpX, vpY, hole.x1, 0, vpX - hole.x1, vpY)
	setRect(b.BackdropTop, vpX, vpY, hole.x0, 0, hole.x1 - hole.x0, hole.y0)
	setRect(b.BackdropBottom, vpX, vpY, hole.x0, hole.y1, hole.x1 - hole.x0, vpY - hole.y1)
	setRect(ui.field, vpX, vpY, floor.x0, floor.y0, floorW, floorH)

	-- ปุ่มสัมผัส: D-pad ล่างซ้าย, FIRE ล่างขวา (ทับสนามได้ถ้าจอแคบ ซึ่งยอมรับได้)
	local dpadSize, fireSize = 0, 0
	if ui.dpad then
		local gutter
		if landscape then
			gutter = math.min(hole.x0, vpX - hole.x1)
		else
			gutter = vpY - hole.y1
		end
		dpadSize = clamp(gutter - 2 * pad, unit * 0.25, unit * 0.42)
		fireSize = dpadSize * 0.62
		setRect(ui.dpad, vpX, vpY, pad, vpY - pad - dpadSize, dpadSize, dpadSize)
		setRect(ui.fire, vpX, vpY, vpX - pad - fireSize, vpY - pad - (dpadSize + fireSize) / 2, fireSize, fireSize)
	end

	arrangeScore(landscape)
	arrangePanel(landscape)
	if landscape then
		-- แผงข้างชิดขวาของสนามแบบ NES (สูงเท่าสนาม) ถ้ามีปุ่ม FIRE ให้หลบ
		local rightX = hole.x1 + gap
		local wMax = floorH * 32 / 208
		local pw, ph = fitBox(math.min(vpX - gap - rightX, wMax), floorH, 32 / 208)
		if ui.dpad then
			local fireTop = vpY - pad - (dpadSize + fireSize) / 2
			local aw, ah = fitBox(math.min(vpX - pad - fireSize - gap - rightX, wMax), floorH, 32 / 208)
			local bw, bh = fitBox(math.min(vpX - gap - rightX, wMax), fireTop - gap - floor.y0, 32 / 208)
			if aw >= bw then
				pw, ph = aw, ah
			else
				pw, ph = bw, bh
			end
		end
		setRect(ui.panel, vpX, vpY, rightX, floor.y0, pw, ph)

		-- คะแนนชิดซ้ายของสนาม, คำแนะนำปุ่มมุมล่างซ้าย
		local leftW = hole.x0 - 2 * gap
		local helpH = unit * 0.07
		local bottom = vpY - gap
		if ui.dpad then
			bottom = vpY - pad - dpadSize - gap
		else
			bottom = vpY - gap - helpH - gap
		end
		local top = math.max(floor.y0, topInset + gap) -- ไม่ทับปุ่มเมนูของ Roblox มุมบนซ้าย
		local sw, sh = fitBox(math.min(leftW, floorH * 48 / 208), bottom - top, 48 / 80)
		setRect(ui.scoreArea, vpX, vpY, hole.x0 - gap - sw, top, sw, sh)
		setRect(ui.help, vpX, vpY, gap, vpY - gap - helpH, leftW, helpH)
		setRect(ui.spectator, vpX, vpY, gap, top + sh + 3 * gap, leftW, unit * 0.08)
	else
		-- จอตั้ง: คะแนน + แผง (แนวนอน) อยู่เหนือสนาม กว้างเท่าสนาม
		local cx = (floor.x0 + floor.x1) / 2
		local s = math.max(0, math.min(floorW / 208, (hole.y0 - gap - math.max(gap, topInset)) / 36))
		local w = 208 * s
		setRect(ui.scoreArea, vpX, vpY, cx - w / 2, hole.y0 - gap - 36 * s, w, 10 * s)
		setRect(ui.panel, vpX, vpY, cx - w / 2, hole.y0 - gap - 24 * s, w, 24 * s)
		local below = hole.y1 + gap
		local lh = math.max(0, math.min(unit * 0.07, (vpY - below) * 0.3))
		setRect(ui.spectator, vpX, vpY, floor.x0, below, floorW, lh)
		setRect(ui.help, vpX, vpY, floor.x0, vpY - gap - lh, floorW, lh)
	end
end

---------------------------------------------------------------- กล้อง
local function cameraHeight(vpX, vpY, fov, size)
	-- หาความสูงที่ทำให้สนาม + ขอบ MARGIN อยู่ในพื้นที่ที่เหลือหลังเว้นที่ให้ HUD (ทั้งจอนอน/จอตั้ง)
	local availX, availY = vpX, vpY
	if vpX >= vpY then
		availX = math.max(vpX - 2 * HUD_SIDE * vpY, vpX * 0.5)
	else
		availY = math.max(vpY - 2 * HUD_TOP * vpX, vpY * 0.5)
	end
	local studsPerPx = math.max((size.X + 2 * MARGIN) / availX, (size.Z + 2 * MARGIN) / availY)
	local tanV = math.tan(math.rad(fov) / 2)
	-- กล้องเอียง ขอบล่างของสนามจึงใกล้กล้องกว่าและดูใหญ่ขึ้นเล็กน้อย: เผื่อสัดส่วนนี้ไว้
	studsPerPx = studsPerPx / (1 - TILT * tanV)
	return (studsPerPx * vpY / 2) / tanV
end

local function screenRect(cf, fov, vpX, vpY, center, size, top)
	-- กรอบสี่เหลี่ยมบนจอที่ครอบสนาม (พื้น ถึงความสูง top) — คำนวณ perspective เอง
	local tanV = math.tan(math.rad(fov) / 2)
	local ratio = vpX / vpY
	local x0, z0 = center.X - size.X / 2, center.Z - size.Z / 2
	local r = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
	for _, y in ipairs({ center.Y, center.Y + top }) do
		for _, x in ipairs({ x0, x0 + size.X }) do
			for _, z in ipairs({ z0, z0 + size.Z }) do
				local q = cf:PointToObjectSpace(Vector3.new(x, y, z))
				local depth = math.max(-q.Z, 0.01)
				local sx = (q.X / (depth * tanV * ratio) + 1) / 2 * vpX
				local sy = (1 - q.Y / (depth * tanV)) / 2 * vpY
				r.x0, r.x1 = math.min(r.x0, sx), math.max(r.x1, sx)
				r.y0, r.y1 = math.min(r.y0, sy), math.max(r.y1, sy)
			end
		end
	end
	r.x0, r.y0 = clamp(r.x0, 0, vpX), clamp(r.y0, 0, vpY)
	r.x1, r.y1 = clamp(r.x1, r.x0, vpX), clamp(r.y1, r.y0, vpY)
	return r
end

local lastView = {}
local function updateCamera()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X < 2 or vp.Y < 2 then
		return
	end
	local center, size = mapGeometry()
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	if math.abs(cam.FieldOfView - CAMERA_FOV) > 0.01 then
		cam.FieldOfView = CAMERA_FOV
	end
	local fov = cam.FieldOfView
	local h = cameraHeight(vp.X, vp.Y, fov, size)
	local cf = CFrame.lookAt(center + Vector3.new(0, h, h * TILT), center)
	cam.CFrame = cf
	-- จัด HUD ใหม่เฉพาะตอนจอ/แมพ/มุมกล้องเปลี่ยน
	local v = lastView
	if v.x ~= vp.X or v.y ~= vp.Y or v.fov ~= fov or v.cx ~= center.X or v.cy ~= center.Y or v.cz ~= center.Z
		or v.sx ~= size.X or v.sz ~= size.Z then
		lastView = { x = vp.X, y = vp.Y, fov = fov, cx = center.X, cy = center.Y, cz = center.Z, sx = size.X, sz = size.Z }
		relayout(vp.X, vp.Y, screenRect(cf, fov, vp.X, vp.Y, center, size, 0),
			screenRect(cf, fov, vp.X, vp.Y, center, size, HOLE_TOP))
	end
end

---------------------------------------------------------------- HUD จาก attribute
local tallyData = nil

local function toNum(v)
	if type(v) == "number" and v == v and v > -1e15 and v < 1e15 then
		return v
	end
	return 0
end

local function normPlayer(p)
	if type(p) ~= "table" then
		return nil
	end
	local k = p.kills
	if type(k) ~= "table" then
		k = {}
	end
	local pt = p.points
	if type(pt) ~= "table" then
		pt = {}
	end
	local out = { kills = {}, points = {}, total = 0 }
	for i = 1, 4 do
		local kv = k[i]
		if kv == nil then
			kv = k[KIND_KEYS[i]]
		end
		out.kills[i] = math.max(0, math.floor(toNum(kv)))
		local pv = pt[i]
		if pv == nil then
			pv = pt[KIND_KEYS[i]]
		end
		if pv == nil then
			out.points[i] = out.kills[i] * KIND_POINTS[i]
		else
			out.points[i] = math.max(0, math.floor(toNum(pv)))
		end
		out.total = out.total + out.kills[i]
	end
	if type(p.totalKills) == "number" then
		out.total = math.max(0, math.floor(toNum(p.totalKills)))
	end
	out.score = math.max(0, math.floor(toNum(p.score)))
	out.bonus = math.max(0, math.floor(toNum(p.bonus)))
	return out
end

local function parseTally(s)
	-- Tally อาจเป็น "" หรือ JSON เสีย: คืน nil แทนการ error
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(s)
	end)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local players = data.players
	if type(players) ~= "table" then
		players = {}
	end
	local out = { players = {} }
	if type(data.stageNumber) == "number" then
		out.stage = data.stageNumber
	end
	for slot = 1, 2 do
		-- server อาจส่งเป็น array [p1, p2] หรือ object {"1": ..} / {"P1": ..} (เมื่อเหลือแค่ผู้เล่นช่อง 2)
		local p = players[slot]
		if p == nil then
			p = players[tostring(slot)]
		end
		if p == nil then
			p = players["P" .. slot]
		end
		out.players[slot] = normPlayer(p)
	end
	return out
end

local function refreshHud()
	local slot = getSlot()
	local p1Present = attr("P1Present") == true
	local p2Present = attr("P2Present") == true

	ui.score1P.Text = fmtInt(num("P1Score", 0))
	ui.score2P.Text = fmtInt(num("P2Score", 0))
	ui.scoreHI.Text = fmtInt(num("HiScore", 20000))
	ui.label2P.Visible = p2Present
	ui.score2P.Visible = p2Present
	-- ป้ายของตัวเองใช้สีรถถังตัวเอง จะได้รู้ว่าเราเป็นใคร
	ui.label1P.TextColor3 = (slot == 1) and C.yellow or C.black
	ui.label2P.TextColor3 = (slot == 2) and C.green or C.black

	local left = math.floor(clamp(num("EnemiesLeft", 0), 0, 20))
	for k = 1, 20 do
		ui.reserve[k].Visible = k <= left
	end

	ui.ipGroup.Visible = p1Present or not p2Present
	ui.iipGroup.Visible = p2Present
	ui.ipLives.Text = fmtInt(num("P1Lives", 0))
	ui.iipLives.Text = fmtInt(num("P2Lives", 0))

	local stage = fmtInt(num("Stage", 1))
	ui.stageNum.Text = stage
	ui.stageText.Text = "STAGE " .. stage

	ui.spectator.Visible = slot == 0
end

---------------------------------------------------------------- หน้าจอตามช่วงเกม (phase)
local phaseState = { dirty = true, seenAt = 0, staleStart = nil, enteredStart = nil }
local tweens = {}

local function currentPhase()
	return str("Phase")
end

local function phaseStart()
	-- ใช้ PhaseStartedAt ของ server; ถ้ายังเป็นค่าของ phase ก่อน (มาไม่พร้อมกัน) ใช้เวลาที่เราเห็น phase แทนไปก่อน
	local s = attr("PhaseStartedAt")
	if type(s) ~= "number" or s ~= s then
		return phaseState.seenAt
	end
	if phaseState.staleStart ~= nil and s == phaseState.staleStart then
		return phaseState.seenAt
	end
	return s
end

local function elapsed()
	return math.max(0, serverNow() - phaseStart())
end

local function stopTweens()
	for _, tw in ipairs(tweens) do
		tw:Cancel()
	end
	tweens = {}
end

local function tweenTo(obj, goal, time)
	if time <= 0.001 then
		for k, v in pairs(goal) do
			obj[k] = v
		end
		return
	end
	local tw = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), goal)
	table.insert(tweens, tw)
	tw:Play()
end

local function curtainPos(closed) -- closed 0 = เปิดสุด, 1 = ปิดสนิท
	return UDim2.fromScale(0, -0.51 + 0.51 * closed), UDim2.fromScale(0, 1 - 0.51 * closed)
end

local function setCurtain(closed)
	local top, bottom = curtainPos(closed)
	ui.curtainTop.Position = top
	ui.curtainBottom.Position = bottom
end

local function enterPhase()
	-- เริ่มแอนิเมชันของ phase จาก "จังหวะที่ถูกต้อง" (คนที่เข้ากลาง phase ก็เห็นตรงกัน)
	phaseState.dirty = false
	phaseState.enteredStart = attr("PhaseStartedAt")
	stopTweens()
	local phase = currentPhase()
	local e = elapsed()
	if phase == "intro" then
		local c = clamp(e / CURTAIN_TIME, 0, 1)
		setCurtain(c)
		local top, bottom = curtainPos(1)
		tweenTo(ui.curtainTop, { Position = top }, (1 - c) * CURTAIN_TIME)
		tweenTo(ui.curtainBottom, { Position = bottom }, (1 - c) * CURTAIN_TIME)
	elseif phase == "playing" then
		local o = clamp(e / CURTAIN_TIME, 0, 1)
		setCurtain(1 - o)
		local top, bottom = curtainPos(0)
		tweenTo(ui.curtainTop, { Position = top }, (1 - o) * CURTAIN_TIME)
		tweenTo(ui.curtainBottom, { Position = bottom }, (1 - o) * CURTAIN_TIME)
	else
		setCurtain(0)
	end
	if phase == "gameOver" then
		local r = clamp(e / GAMEOVER_RISE, 0, 1)
		ui.gameOverRise.Position = UDim2.fromScale(0.5, 1.2 - 0.7 * r)
		tweenTo(ui.gameOverRise, { Position = UDim2.fromScale(0.5, 0.5) }, (1 - r) * GAMEOVER_RISE)
	else
		ui.gameOverRise.Position = UDim2.fromScale(0.5, 1.2)
	end
end

local function updateTally(e)
	local T = ui.tally
	local d = tallyData
	local p1 = d and d.players[1]
	local p2 = d and d.players[2]
	local hi = num("HiScore", 20000)
	if p1 and p1.score > hi then
		hi = p1.score
	end
	if p2 and p2.score > hi then
		hi = p2.score
	end
	T.hiValue.Text = fmtInt(hi)
	T.stage.Text = "STAGE " .. fmtInt((d and d.stage) or num("Stage", 1))
	T.p1Name.Visible = p1 ~= nil
	T.p1Score.Visible = p1 ~= nil
	T.p2Name.Visible = p2 ~= nil
	T.p2Score.Visible = p2 ~= nil
	if p1 then
		T.p1Score.Text = fmtInt(p1.score)
	end
	if p2 then
		T.p2Score.Text = fmtInt(p2.score)
	end

	-- นับทีละแถว (basic, fast, power, armor) ทั้งสองฝั่งพร้อมกันแบบ NES
	local t = TALLY_HEAD
	for r = 1, 4 do
		local row = T.rows[r]
		local k1 = p1 and p1.kills[r] or 0
		local k2 = p2 and p2.kills[r] or 0
		local kmax = math.max(k1, k2)
		local dur = math.min(kmax * TALLY_STEP, TALLY_ROWMAX)
		local step = 1
		if kmax > 0 then
			step = dur / kmax
		end
		local counted = math.floor((e - t) / step + 1e-6)
		row.frame.Visible = e >= t
		row.p1Pts.Visible = p1 ~= nil
		row.p1Word.Visible = p1 ~= nil
		row.p1Kills.Visible = p1 ~= nil
		row.arrowLeft.Visible = p1 ~= nil
		row.p2Pts.Visible = p2 ~= nil
		row.p2Word.Visible = p2 ~= nil
		row.p2Kills.Visible = p2 ~= nil
		row.arrowRight.Visible = p2 ~= nil
		if p1 then
			local c = clamp(counted, 0, k1)
			row.p1Kills.Text = fmtInt(c)
			row.p1Pts.Text = fmtInt((c >= k1) and p1.points[r] or c * KIND_POINTS[r])
		end
		if p2 then
			local c = clamp(counted, 0, k2)
			row.p2Kills.Text = fmtInt(c)
			row.p2Pts.Text = fmtInt((c >= k2) and p2.points[r] or c * KIND_POINTS[r])
		end
		t = t + dur + TALLY_GAP
	end
	local showTotal = e >= t
	T.totalLabel.Visible = showTotal
	T.totalP1.Visible = showTotal and p1 ~= nil
	T.totalP2.Visible = showTotal and p2 ~= nil
	if p1 then
		T.totalP1.Text = fmtInt(p1.total)
	end
	if p2 then
		T.totalP2.Text = fmtInt(p2.total)
	end
	local showBonus = e >= t + TALLY_BONUS_DELAY
	T.bonusP1.Visible = showBonus and p1 ~= nil and p1.bonus > 0
	T.bonusP2.Visible = showBonus and p2 ~= nil and p2.bonus > 0
	if p1 then
		T.bonusP1Value.Text = fmtInt(p1.bonus) .. " PTS"
	end
	if p2 then
		T.bonusP2Value.Text = fmtInt(p2.bonus) .. " PTS"
	end
end

local function updateOverlays()
	if phaseState.dirty then
		enterPhase()
	end
	local phase = currentPhase()
	local e = elapsed()
	ui.intro.Visible = phase == "intro" or (phase == "playing" and e < CURTAIN_TIME)
	ui.introBacking.Visible = phase == "intro"
	ui.stageBox.Visible = phase == "intro" and e >= CURTAIN_TIME
	ui.gameOverRise.Visible = phase == "gameOver"
	ui.tally.screen.Visible = phase == "tally"
	if phase == "tally" then
		updateTally(e)
	end
	ui.final.Visible = phase == "final"
	ui.waiting.Visible = folder == nil or phase == nil or phase == "waiting"
	if folder == nil then
		ui.waitingText.Text = "LOADING..."
	else
		ui.waitingText.Text = "WAITING FOR PLAYERS"
	end
end

local function onAttributeChanged(name)
	if name == "Phase" then
		phaseState.staleStart = phaseState.enteredStart
		phaseState.seenAt = serverNow()
		phaseState.dirty = true
	elseif name == "PhaseStartedAt" then
		phaseState.dirty = true
	elseif name == "Tally" then
		tallyData = parseTally(attr("Tally"))
	end
	refreshHud()
end

---------------------------------------------------------------- ปุ่มกด -> server
-- ทิศ: 0 ขึ้น, 1 ขวา, 2 ลง, 3 ซ้าย, -1 ไม่กด
local KEY_DIR = {
	[Enum.KeyCode.W] = 0, [Enum.KeyCode.Up] = 0, [Enum.KeyCode.DPadUp] = 0,
	[Enum.KeyCode.D] = 1, [Enum.KeyCode.Right] = 1, [Enum.KeyCode.DPadRight] = 1,
	[Enum.KeyCode.S] = 2, [Enum.KeyCode.Down] = 2, [Enum.KeyCode.DPadDown] = 2,
	[Enum.KeyCode.A] = 3, [Enum.KeyCode.Left] = 3, [Enum.KeyCode.DPadLeft] = 3,
}
local FIRE_KEYS = {
	[Enum.KeyCode.Space] = true, [Enum.KeyCode.J] = true, [Enum.KeyCode.Z] = true,
	[Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.ButtonX] = true, [Enum.KeyCode.ButtonR2] = true,
}

local inp = {
	stack = {}, -- ปุ่มทิศที่กดค้าง เรียงตามลำดับกด (ตัวท้าย = กดล่าสุด ชนะ)
	fire = {}, -- [KeyCode] = true ปุ่มยิงที่กดค้าง
	stickDir = -1,
	touches = {}, -- [InputObject] = { kind = "move"|"fire", dir, order } แยกนิ้วต่อนิ้ว
	touchSeq = 0,
	lastDir = -1,
	lastFire = false,
}

local function stackRemove(key)
	for i = #inp.stack, 1, -1 do
		if inp.stack[i].key == key then
			table.remove(inp.stack, i)
		end
	end
end

local function currentInput()
	local dir = -1
	if #inp.stack > 0 then
		dir = inp.stack[#inp.stack].dir
	elseif inp.stickDir >= 0 then
		dir = inp.stickDir
	else
		local best = nil
		for _, t in pairs(inp.touches) do
			if t.kind == "move" and t.dir >= 0 and (best == nil or t.order > best.order) then
				best = t
			end
		end
		if best then
			dir = best.dir
		end
	end
	local fire = next(inp.fire) ~= nil
	if not fire then
		for _, t in pairs(inp.touches) do
			if t.kind == "fire" then
				fire = true
				break
			end
		end
	end
	return dir, fire
end

local function updateTouchVisuals(dir, fire)
	if not ui.dpad then
		return
	end
	local touchDir = -1
	local touchFire = false
	local best = nil
	for _, t in pairs(inp.touches) do
		if t.kind == "move" and t.dir >= 0 and (best == nil or t.order > best.order) then
			best = t
		elseif t.kind == "fire" then
			touchFire = true
		end
	end
	if best then
		touchDir = best.dir
	end
	for d = 0, 3 do
		ui.dpadArms[d].BackgroundColor3 = (d == touchDir) and C.gray or C.dark
	end
	ui.fire.BackgroundTransparency = touchFire and 0 or 0.15
	ui.fire.BackgroundColor3 = touchFire and C.brick or C.red
end

local function sendInput()
	-- ส่งเฉพาะตอนค่าเปลี่ยน (dir เป็นเลขเต็ม -1..3, fire เป็น boolean ตามที่ server ตรวจ)
	local dir, fire = currentInput()
	updateTouchVisuals(dir, fire)
	if inputRemote == nil then
		return
	end
	if dir ~= inp.lastDir or fire ~= inp.lastFire then
		inp.lastDir, inp.lastFire = dir, fire
		inputRemote:FireServer(dir, fire)
	end
end

local function releaseAll()
	-- หน้าต่างหลุดโฟกัส/เริ่มพิมพ์แชต: ปุ่มที่ค้างอาจไม่มี InputEnded ตามมา จึงปล่อยทั้งหมดเอง
	inp.stack = {}
	inp.fire = {}
	inp.stickDir = -1
	inp.touches = {}
	sendInput()
end

local function stickToDir(pos)
	local x, y = pos.X, pos.Y
	if math.max(math.abs(x), math.abs(y)) < 0.5 then
		return -1
	end
	if math.abs(x) > math.abs(y) then
		return (x > 0) and 1 or 3
	end
	return (y > 0) and 0 or 2 -- คันโยก y ขึ้น = บวก
end

local function inside(g, pos)
	if not g then
		return false
	end
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function dpadDir(pos)
	local p, s = ui.dpad.AbsolutePosition, ui.dpad.AbsoluteSize
	local dx = pos.X - (p.X + s.X / 2)
	local dy = pos.Y - (p.Y + s.Y / 2)
	local dead = math.min(s.X, s.Y) * 0.12
	if math.abs(dx) < dead and math.abs(dy) < dead then
		return -1
	end
	if math.abs(dx) > math.abs(dy) then
		return (dx > 0) and 1 or 3
	end
	return (dy > 0) and 2 or 0 -- จอ: y ลง = บวก
end

local function beginTouch(io, kind)
	if inp.touches[io] then
		return
	end
	inp.touchSeq = inp.touchSeq + 1
	local t = { kind = kind, dir = -1, order = inp.touchSeq }
	if kind == "move" then
		t.dir = dpadDir(io.Position)
	end
	inp.touches[io] = t
	sendInput()
end

local function moveTouch(io)
	local t = inp.touches[io]
	if t and t.kind == "move" then
		t.dir = dpadDir(io.Position)
		sendInput()
	end
end

local function endTouch(io)
	if inp.touches[io] then
		inp.touches[io] = nil
		sendInput()
	end
end

UserInputService.InputBegan:Connect(guard("InputBegan", function(io, gameProcessed)
	local kc = io.KeyCode
	if gameProcessed then
		-- ปุ่มที่ Roblox ใช้ไปแล้ว (เช่นพิมพ์แชต) ไม่นับ; ถ้าเป็นปุ่มอื่นนอกเกม (กด / หรือพิมพ์ตัวอักษร)
		-- แปลว่าเริ่มพิมพ์แชต -> ปล่อยทุกปุ่ม ไม่ให้รถถังวิ่งค้าง
		-- (ปุ่มเกมที่ถูก ContextActionService ของ Roblox ใช้ จะแค่ถูกข้าม ไม่หยุดรถถัง)
		if io.UserInputType == Enum.UserInputType.Keyboard and KEY_DIR[kc] == nil and not FIRE_KEYS[kc] then
			releaseAll()
		end
		return
	end
	local d = KEY_DIR[kc]
	if d ~= nil then
		stackRemove(kc)
		table.insert(inp.stack, { key = kc, dir = d })
		sendInput()
	elseif FIRE_KEYS[kc] then
		inp.fire[kc] = true
		sendInput()
	end
end))

UserInputService.InputEnded:Connect(guard("InputEnded", function(io)
	-- ปล่อยปุ่มเสมอแม้ gameProcessed (กดก่อนเปิดแชต แล้วไปปล่อยตอนพิมพ์)
	local kc = io.KeyCode
	if KEY_DIR[kc] ~= nil then
		stackRemove(kc)
		sendInput()
	elseif FIRE_KEYS[kc] then
		inp.fire[kc] = nil
		sendInput()
	elseif kc == Enum.KeyCode.Thumbstick1 then
		inp.stickDir = -1
		sendInput()
	end
end))

UserInputService.InputChanged:Connect(guard("InputChanged", function(io, gameProcessed)
	if io.KeyCode == Enum.KeyCode.Thumbstick1 then
		if gameProcessed then
			inp.stickDir = -1
		else
			inp.stickDir = stickToDir(io.Position)
		end
		sendInput()
	end
end))

UserInputService.WindowFocusReleased:Connect(guard("WindowFocusReleased", releaseAll))
UserInputService.TextBoxFocused:Connect(guard("TextBoxFocused", releaseAll))
UserInputService.GamepadDisconnected:Connect(guard("GamepadDisconnected", releaseAll))
pcall(function()
	GuiService.MenuOpened:Connect(guard("MenuOpened", releaseAll))
end)

if ui.dpad then
	-- แตะหลายนิ้วพร้อมกันได้: จำแต่ละนิ้วด้วย InputObject ของมันเอง
	ui.dpad.InputBegan:Connect(guard("DPadBegan", function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			beginTouch(io, "move")
		end
	end))
	ui.dpad.InputChanged:Connect(guard("DPadChanged", function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			moveTouch(io)
		end
	end))
	ui.dpad.InputEnded:Connect(guard("DPadEnded", function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			endTouch(io)
		end
	end))
	ui.fire.InputBegan:Connect(guard("FireBegan", function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			beginTouch(io, "fire")
		end
	end))
	ui.fire.InputEnded:Connect(guard("FireEnded", function(io)
		if io.UserInputType == Enum.UserInputType.Touch then
			endTouch(io)
		end
	end))
	-- สำรอง: ถ้า GUI ไม่ได้รับ event (เช่นแตะโดนลูกของปุ่ม) เช็กตำแหน่งนิ้วเอง
	UserInputService.TouchStarted:Connect(guard("TouchStarted", function(io)
		if inp.touches[io] then
			return
		end
		if inside(ui.dpad, io.Position) and ui.dpad.Visible then
			beginTouch(io, "move")
		elseif inside(ui.fire, io.Position) and ui.fire.Visible then
			beginTouch(io, "fire")
		end
	end))
	UserInputService.TouchMoved:Connect(guard("TouchMoved", moveTouch))
	UserInputService.TouchEnded:Connect(guard("TouchEnded", endTouch))
end

player:GetAttributeChangedSignal("BattleCitySlot"):Connect(guard("Slot", function()
	refreshHud()
	-- เพิ่งได้ช่องผู้เล่น (เช่นจากผู้ชม): ส่งปุ่มที่กดค้างอยู่ให้ server รู้อีกครั้ง
	if inputRemote and (inp.lastDir ~= -1 or inp.lastFire) then
		inputRemote:FireServer(inp.lastDir, inp.lastFire)
	end
end))

---------------------------------------------------------------- เริ่มทำงาน
-- ปิด UI ของ Roblox ที่ไม่ใช้ (pcall เพราะบางเวอร์ชัน/บางช่วงอาจเรียกไม่ได้)
for _, name in ipairs({ "Backpack", "Health", "EmotesMenu" }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType[name], false)
	end)
end
pcall(function()
	GuiService.TouchControlsEnabled = false -- ซ่อนจอยสัมผัสของ Roblox ใช้ D-pad ของเกมแทน
end)

refreshHud()
-- กล้องต้องตั้งหลังสคริปต์กล้องของ Roblox ทุกเฟรม จะได้ไม่ถูกเขียนทับ
RunService:BindToRenderStep("BattleCityCamera", Enum.RenderPriority.Camera.Value + 1, guard("Camera", updateCamera))
RunService.RenderStepped:Connect(guard("Overlays", updateOverlays))

folder = ReplicatedStorage:WaitForChild("BattleCity")
phaseState.seenAt = serverNow()
phaseState.dirty = true
tallyData = parseTally(attr("Tally"))
folder.AttributeChanged:Connect(guard("Attributes", onAttributeChanged))
refreshHud()

local remote = folder:WaitForChild("Input")
if remote:IsA("RemoteEvent") then
	inputRemote = remote
	sendInput() -- ถ้ากดค้างไว้ก่อน server พร้อม ส่งตอนนี้เลย
else
	report("Input", "ReplicatedStorage.BattleCity.Input is not a RemoteEvent")
end
