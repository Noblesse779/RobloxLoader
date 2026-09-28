-- Script (ฝั่ง Server): โหลด/บันทึก Score ของผู้เล่นด้วย DataStore
-- วางไว้ที่ ServerScriptService
-- ต้อง Publish เกม และเปิด Game Settings > Security > "Enable Studio Access to API Services" ถึงจะทดสอบใน Studio ได้
--
-- Score เก็บเป็น Attribute บน Player ซึ่ง Server ตั้งค่าแล้วจะส่งไปให้ Client อัตโนมัติ
-- ถ้า Client แก้ค่าเอง จะเปลี่ยนแค่บนเครื่องตัวเอง ไม่ส่งกลับมาที่ Server
-- เพิ่มคะแนนต้องทำฝั่ง Server เท่านั้น เช่น
--   player:SetAttribute("Score", player:GetAttribute("Score") + 10)
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local scoreStore = DataStoreService:GetDataStore("PlayerScore")

-- เก็บว่าผู้เล่นคนไหนโหลดข้อมูลสำเร็จแล้ว
-- ถ้าโหลดไม่สำเร็จ จะไม่บันทึกทับ เพื่อไม่ให้คะแนนจริงถูกเขียนทับเป็น 0
local loaded = {}

local function loadScore(player)
	local ok, result = pcall(function()
		return scoreStore:GetAsync(tostring(player.UserId))
	end)

	-- ผู้เล่นออกไปแล้วระหว่างรอโหลด
	if not player.Parent then
		return
	end

	if ok then
		player:SetAttribute("Score", result or 0)
		loaded[player] = true
	else
		warn("โหลด Score ไม่สำเร็จ:", player.Name, result)
		player:SetAttribute("Score", 0)
	end
end

local function saveScore(player)
	if not loaded[player] then
		return
	end

	local score = player:GetAttribute("Score") or 0
	local ok, err = pcall(function()
		scoreStore:SetAsync(tostring(player.UserId), score)
	end)

	if not ok then
		warn("บันทึก Score ไม่สำเร็จ:", player.Name, err)
	end
end

Players.PlayerAdded:Connect(loadScore)

-- เผื่อมีผู้เล่นเข้ามาก่อนสคริปต์นี้เริ่มทำงาน
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadScore, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveScore(player)
	loaded[player] = nil
end)

-- ตอนเซิร์ฟเวอร์ปิด บันทึกให้ทุกคนก่อน
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveScore(player)
	end
end)
