-- LocalScript: แสดงข้อมูลพื้นฐานฝั่ง Client + บันทึกข้อมูลที่ Server ส่งมาผ่าน RemoteEvent
-- วางไว้ที่ StarterPlayer > StarterPlayerScripts
-- Score มาจาก Server (ดู ScoreData_Script.txt) ฝั่ง Client แค่อ่านมาแสดง

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. ข้อมูลพื้นฐานของผู้เล่น (อยู่บนเครื่อง Client)
-- ใช้ลิสต์แทน dictionary เพื่อให้ print ออกมาตามลำดับเสมอ (pairs ไม่รับประกันลำดับ)
local basicData = {
	{ "UserId", player.UserId },
	{ "Name", player.Name },
	{ "DisplayName", player.DisplayName },
	{ "AccountAge", player.AccountAge },
	{ "MembershipType", player.MembershipType.Name },
}
print("===== ข้อมูลพื้นฐานบน Client =====")
for _, entry in ipairs(basicData) do
	print(entry[1] .. ":", entry[2])
end

-- 2. บันทึกแค่ "อะไรอยู่จุดไหน" ในแมพ — ชื่อ + ตำแหน่งของแต่ละชิ้น ไม่เก็บเนื้อโมเดล/เนื้อไฟล์ใด ๆ
-- สแกนครั้งเดียวตอนเริ่ม ถ้าเปิด StreamingEnabled อาจนับได้ไม่ครบ (ของที่ยังไม่ stream เข้ามาจะไม่ถูกนับ)
local mapItems = {} -- { {Name=..., ClassName=..., Position=Vector3}, ... }

local function getInstancePosition(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		return primary and primary.Position or nil
	end
	return nil
end

local function scanWorkspaceItems()
	table.clear(mapItems)
	for _, obj in ipairs(workspace:GetDescendants()) do
		-- สนใจเฉพาะ BasePart กับ Model ระดับบนสุด (ไม่เก็บชิ้นส่วนย่อยของ Model ซ้ำ)
		local isTopLevelModel = obj:IsA("Model") and obj.Parent == workspace
		if obj:IsA("BasePart") or isTopLevelModel then
			local position = getInstancePosition(obj)
			if position then
				table.insert(mapItems, {
					Name = obj.Name,
					ClassName = obj.ClassName,
					Position = position,
				})
			end
		end
	end

	print(string.format("\n===== รายการสิ่งของในแมพ (%d ชิ้น) =====", #mapItems))
	for _, item in ipairs(mapItems) do
		print(string.format(
			"%s (%s) @ (%.1f, %.1f, %.1f)",
			item.Name,
			item.ClassName,
			item.Position.X,
			item.Position.Y,
			item.Position.Z
		))
	end
end
scanWorkspaceItems()

-- 3. ตัวอย่างการ Preload Assets (ทำให้โหลดลงเครื่อง Client เร็วขึ้น)
local assetsToPreload = {
	-- ใส่ AssetId ที่ต้องการ preload ได้ เช่น
	-- "rbxassetid://123456789",
}
if #assetsToPreload > 0 then
	ContentProvider:PreloadAsync(assetsToPreload)
	print("\nPreload Assets เสร็จแล้ว (ถูก cache บนเครื่อง Client)")
end

-- 4. ค่าตั้งค่าชั่วคราวบน Client (ไม่ถาวร หายเมื่อออกจากเกม)
-- ข้อมูลสำคัญอย่าง Score อย่าเก็บที่นี่ เพราะผู้เล่นแก้ค่าบน Client ได้
-- clientMemory.ReceivedData คือที่เก็บข้อมูลทั้งหมดที่ Server ส่งมาให้ผ่าน RemoteEvent
local clientMemory = {
	Settings = {
		MusicVolume = 0.5,
		GraphicsQuality = 5,
	},
	ReceivedData = {}, -- เก็บข้อมูลล่าสุดที่ได้รับจาก Server แยกตามคีย์ เช่น ReceivedData["Score"]
	ReceivedLog = {}, -- เก็บประวัติทุกครั้งที่ได้รับข้อมูล (พร้อม timestamp) สำหรับ debug/ตรวจสอบย้อนหลัง
	MapItems = mapItems, -- ชื่อ+ตำแหน่งของสิ่งของในแมพ (จาก scanWorkspaceItems ด้านบน)
}

-- 4.1 ตั้งค่าจำกัดขนาด log กันไม่ให้โตไม่มีที่สิ้นสุดระหว่างเล่นนาน ๆ
local MAX_LOG_ENTRIES = 200

-- 4.2 หา RemoteEvent ที่ Server ใช้ส่งข้อมูลมาให้ Client
-- ต้องมี Instance ชื่อ "ClientDataSync" (RemoteEvent) อยู่ใต้ ReplicatedStorage
-- ฝั่ง Server ต้อง Fire ข้อมูลแบบ dictionary เช่น remote:FireClient(player, { Key = "Score", Value = 120 })
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local clientDataSyncRemote = remotesFolder and remotesFolder:WaitForChild("ClientDataSync", 10)

-- เก็บข้อมูลที่ได้รับลง clientMemory และคืนค่ากลับมาเผื่อเอาไปใช้ต่อ (เช่นอัปเดต UI ทันที)
local function saveReceivedData(payload)
	if typeof(payload) ~= "table" then
		warn("[ClientDataSync] ได้รับข้อมูลที่ไม่ใช่ table, ข้าม:", payload)
		return nil
	end

	local key = payload.Key
	local value = payload.Value
	if key == nil then
		warn("[ClientDataSync] payload ไม่มี Key, ข้าม")
		return nil
	end

	-- บันทึกค่าล่าสุดของคีย์นี้ (เขียนทับของเก่า)
	clientMemory.ReceivedData[key] = value

	-- บันทึกลง log ประวัติ พร้อมเวลาที่ได้รับ (os.time = เวลาบนเครื่อง Client)
	table.insert(clientMemory.ReceivedLog, {
		Key = key,
		Value = value,
		ReceivedAt = os.time(),
	})

	-- ตัด log ส่วนเกินทิ้งจากหัวสุด กันไม่ให้ตารางโตไม่มีที่สิ้นสุด
	if #clientMemory.ReceivedLog > MAX_LOG_ENTRIES then
		table.remove(clientMemory.ReceivedLog, 1)
	end

	print(string.format("[ClientDataSync] บันทึก %s = %s", tostring(key), tostring(value)))
	return key, value
end

if clientDataSyncRemote then
	clientDataSyncRemote.OnClientEvent:Connect(function(payload)
		saveReceivedData(payload)
	end)
	print("\n[ClientDataSync] เชื่อมต่อ RemoteEvent สำเร็จ รอรับข้อมูลจาก Server...")
else
	warn("\n[ClientDataSync] ไม่พบ ReplicatedStorage.Remotes.ClientDataSync — ข้ามการรับข้อมูลจาก Server")
end

-- 5. แสดงข้อมูลบนหน้าจอ (UI ฝั่ง Client)
-- ลบ GUI เก่าก่อน กันซ้ำในกรณีที่สคริปต์ถูกรันใหม่ (เช่น วางไว้ใน StarterGui)
local oldGui = playerGui:FindFirstChild("ClientInfoGui")
if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ClientInfoGui"
screenGui.ResetOnSpawn = false -- ไม่ให้ UI หายตอนตัวละครตายแล้วเกิดใหม่
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 420, 0, 160)
label.Position = UDim2.new(0, 20, 0, 20)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Font = Enum.Font.Gotham
label.Text = "กำลังโหลดข้อมูล Client..."
label.Parent = screenGui

-- แปลง ReceivedData ทั้งหมดเป็นข้อความหลายบรรทัดสำหรับแสดงผล
local function formatReceivedData()
	local lines = {}
	for key, value in pairs(clientMemory.ReceivedData) do
		table.insert(lines, string.format("%s: %s", tostring(key), tostring(value)))
	end
	table.sort(lines) -- เรียงตามตัวอักษรกันข้อความกระโดดไปมาทุกวินาที
	return table.concat(lines, "\n")
end

-- อัปเดตข้อความทุก 1 วินาที
-- อ่านตำแหน่งตรงนี้เลย ไม่ต้องใช้ Heartbeat เก็บทุกเฟรม เพราะแสดงผลแค่วินาทีละครั้ง
task.spawn(function()
	local lastPosition = Vector3.zero
	-- ลูปหยุดเองเมื่อ label ถูกลบออกจาก PlayerGui
	while label:IsDescendantOf(playerGui) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			lastPosition = rootPart.Position
		end

		local extraDataText = formatReceivedData()
		label.Text = string.format(
			"ชื่อ: %s\nUserId: %d\nตำแหน่งล่าสุด: (%.1f, %.1f, %.1f)\nScore: %d%s",
			player.DisplayName,
			player.UserId,
			lastPosition.X,
			lastPosition.Y,
			lastPosition.Z,
			player:GetAttribute("Score") or 0, -- Server เป็นคนตั้งค่า (Attribute ส่งจาก Server มาให้อัตโนมัติ)
			extraDataText ~= "" and ("\n" .. extraDataText) or ""
		)
		task.wait(1)
	end
end)

print("\nLocalScript เริ่มทำงานบน Client เรียบร้อย")
