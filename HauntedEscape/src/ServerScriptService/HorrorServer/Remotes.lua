--[[
	Remotes : สร้าง RemoteEvent ทั้งหมดไว้ที่ ReplicatedStorage.HorrorRemotes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = {
	"Jumpscare", -- server -> client (ชนิดตุ้งแช่)
	"Notify", -- server -> client (ข้อความ, สี)
	"StageChanged", -- server -> client (ด่าน, ชื่อด่าน, เป้าหมาย)
	"Objective", -- server -> client (ข้อความเป้าหมาย)
	"Transition", -- server -> client (จอดำตอนวาป)
	"GameEnded", -- server -> client (เวลาที่ใช้)
	"PlaySound", -- server -> client (ชื่อเสียงใน Config.Sounds)
	"Flashlight", -- client -> server (เปิด/ปิดไฟฉาย)
	"ReturnToLobby", -- client -> server
}

local folder = ReplicatedStorage:FindFirstChild("HorrorRemotes") or Instance.new("Folder")
folder.Name = "HorrorRemotes"

local Remotes = {}
for _, name in ipairs(NAMES) do
	local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	Remotes[name] = r
end
folder.Parent = ReplicatedStorage

return Remotes
