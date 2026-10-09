-- LocalScript: กล้องมองจากด้านบนแบบ Battle City เห็นทั้งแมพในจอเดียว
-- วางไว้ที่ StarterPlayer > StarterPlayerScripts (ใช้คู่กับ BattleCityMap.lua)

local RunService = game:GetService("RunService")

local camera = workspace.CurrentCamera
local map = workspace:WaitForChild("BattleCityMap")

local center = map:GetAttribute("Center")
local size = map:GetAttribute("Size")
local MARGIN = 8 -- เผื่อขอบรอบแมพ (stud)

local function updateCamera()
	local viewport = camera.ViewportSize
	if viewport.Y == 0 then
		return
	end

	-- ยกกล้องให้สูงพอเห็นทั้งแมพ ทั้งจอแนวนอน (คอม) และแนวตั้ง (มือถือ)
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local tanH = tanV * viewport.X / viewport.Y
	local height = math.max((size.Z / 2 + MARGIN) / tanV, (size.X / 2 + MARGIN) / tanH)

	-- เอียงกล้องนิดเดียว (ไม่มองลงตรง 100%) ปุ่ม WASD จะได้ยังเดินตามทิศบนจอ
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, height, height * 0.03), center)
end

-- ตั้งกล้องทุกเฟรมหลังสคริปต์กล้องปกติของ Roblox จะได้ไม่ถูกเขียนทับตอนเกิดใหม่
RunService:BindToRenderStep("BattleCityCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
