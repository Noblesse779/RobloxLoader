--[[
	Lobby : แท่นทีม 1-6 คน
	- ยืนบนแท่นให้ครบจำนวน => นับถอยหลัง => วาปทั้งทีมไปเซิร์ฟเวอร์เกมส่วนตัว (Reserved Server)
	- ถ้าเทสใน Studio หรือ Teleport ไม่ได้ => เล่นในเซิร์ฟเวอร์นี้เลย
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("HorrorShared"):WaitForChild("Config"))
local Remotes = require(script.Parent.Remotes)

local Lobby = {}

local function rootOf(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root
	end
	return nil
end

local function onPad(pad, root)
	local rel = root.Position - pad.Center
	return math.abs(rel.X) <= 6 and math.abs(rel.Z) <= 6 and rel.Y > 0 and rel.Y < 10
end

local function launch(pad, members, Run)
	pad.Launching = true
	pad.Status.Text = "กำลังเข้าเกม..."
	for _, p in ipairs(members) do
		Remotes.Transition:FireClient(p)
	end

	if not RunService:IsStudio() then
		local options = Instance.new("TeleportOptions")
		options.ShouldReserveServer = true
		options:SetTeleportData({ partySize = #members })
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, members, options)
		end)
		if ok then
			task.delay(15, function()
				pad.Launching = false
			end)
			return
		end
		warn("[Lobby] Teleport failed, starting game in this server instead: " .. tostring(err))
	end

	Run.start(members)
	pad.Launching = false
end

function Lobby.init(map, Run, isGameServer)
	local pads = map.Lobby.Pads

	if isGameServer then
		for _, pad in ipairs(pads) do
			pad.Status.Text = "รอเพื่อนร่วมทีม..."
		end
		return
	end

	local lastFullWarn = {}

	task.spawn(function()
		while true do
			local claimed = {}
			for _, pad in ipairs(pads) do
				local members = {}
				for _, p in ipairs(Players:GetPlayers()) do
					if not claimed[p] and not p:GetAttribute("InRun") then
						local root = rootOf(p)
						if root and onPad(pad, root) then
							if #members < pad.Size then
								table.insert(members, p)
								claimed[p] = true
							elseif not lastFullWarn[p] or os.clock() - lastFullWarn[p] > 3 then
								lastFullWarn[p] = os.clock()
								Remotes.Notify:FireClient(p, "แท่นนี้เต็มแล้ว ลองแท่นอื่นนะ", Color3.fromRGB(255, 120, 120))
							end
						end
					end
				end

				if pad.Launching then
					continue -- กำลังวาปอยู่
				end
				if Run.Active then
					pad.CountStart = nil
					pad.Status.Text = "มีทีมกำลังเล่นอยู่..."
				elseif #members == pad.Size then
					pad.CountStart = pad.CountStart or os.clock()
					local remaining = math.ceil(Config.LobbyCountdown - (os.clock() - pad.CountStart))
					pad.Status.Text = "เริ่มใน " .. math.max(remaining, 0) .. " วิ!"
					if remaining <= 0 then
						pad.CountStart = nil
						task.spawn(launch, pad, members, Run)
					end
				else
					pad.CountStart = nil
					pad.Status.Text = #members .. "/" .. pad.Size .. " คน"
				end
			end
			task.wait(0.25)
		end
	end)
end

return Lobby
