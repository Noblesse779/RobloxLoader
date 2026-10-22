--[[
	HAUNTED ESCAPE - Server
	วางสคริปต์นี้ (ชื่อ HorrorServer) ไว้ใน ServerScriptService
	โดยมี ModuleScript ลูก: MapBuilder, Ghosts, Remotes, Run, Lobby
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HorrorShared"):WaitForChild("Config"))
local MapBuilder = require(script.MapBuilder)
local Run = require(script.Run)
local Lobby = require(script.Lobby)
local Remotes = require(script.Remotes)

Players.RespawnTime = Config.RespawnTime

-- แสงพื้นฐาน (ไคลเอนต์จะปรับตามด่านอีกที)
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.GlobalShadows = true
Lighting.Ambient = Color3.fromRGB(30, 28, 36)
Lighting.OutdoorAmbient = Color3.fromRGB(30, 28, 36)

local map = MapBuilder.build()

-- Reserved Server (ที่ล็อบบี้สร้างให้ทีม) => เป็นเซิร์ฟเวอร์เกม
local isGameServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

Run.init(map, isGameServer)
Lobby.init(map, Run, isGameServer)

if isGameServer then
	local expected

	local function readPartySize(p)
		local ok, data = pcall(function()
			return p:GetJoinData().TeleportData
		end)
		if ok and type(data) == "table" and tonumber(data.partySize) then
			expected = math.max(expected or 0, tonumber(data.partySize))
		end
	end

	Players.PlayerAdded:Connect(function(p)
		readPartySize(p)
		if Run.Active then
			-- หลุดแล้วกลับเข้ามาใหม่ => ต่อด่านเดิม
			if not p.Character then
				p.CharacterAdded:Wait()
			end
			task.wait(0.5)
			Run.addPlayer(p)
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		readPartySize(p)
	end

	task.spawn(function()
		while #Players:GetPlayers() == 0 do
			Players.PlayerAdded:Wait()
		end
		local t0 = os.clock()
		while #Players:GetPlayers() < (expected or 1) and os.clock() - t0 < Config.WaitForPartyTimeout do
			for _, p in ipairs(Players:GetPlayers()) do
				Remotes.Notify:FireClient(p, string.format("รอเพื่อนร่วมทีม %d/%d ...", #Players:GetPlayers(), expected or 1), Color3.fromRGB(255, 220, 120))
			end
			task.wait(2)
		end
		-- รอให้ตัวละครโหลดครบ
		local deadline = os.clock() + 10
		repeat
			local ready = true
			for _, p in ipairs(Players:GetPlayers()) do
				if not p.Character then
					ready = false
				end
			end
			task.wait(0.5)
		until ready or os.clock() > deadline
		task.wait(1.5)
		Run.start(Players:GetPlayers())
	end)
end
