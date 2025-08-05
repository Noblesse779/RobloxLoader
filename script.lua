-- ✅ แสดงข้อความใน Console
print("✅ สคริปต์เริ่มทำงานแล้ว")

-- ✅ GUI หลัก
local gui = Instance.new("ScreenGui")
gui.Name = "MyFlyGui"
gui.ResetOnSpawn = false
gui.Parent = game.CoreGui

-- ✅ ปุ่มเปิด/ปิดบิน
local toggle = false

local button = Instance.new("TextButton")
button.Parent = gui
button.Text = "🚀 เปิดบิน"
button.Size = UDim2.new(0, 200, 0, 50)
button.Position = UDim2.new(0.5, -100, 0.5, -25)
button.BackgroundColor3 = Color3.fromRGB(0, 100, 255)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextScaled = true

-- ✅ ฟังก์ชันการบิน (Simple Fly)
local uis = game:GetService("UserInputService")
local run = game:GetService("RunService")
local plr = game.Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

local flying = false
local speed = 50
local vel = Instance.new("BodyVelocity")
vel.MaxForce = Vector3.new(1, 1, 1) * math.huge
vel.Velocity = Vector3.zero
vel.Parent = hrp

-- ทิศทางการบิน
local dir = Vector3.zero

-- กดปุ่มบน GUI เพื่อเปิด/ปิดบิน
button.MouseButton1Click:Connect(function()
    toggle = not toggle
    if toggle then
        flying = true
        button.Text = "🛑 ปิดบิน"
    else
        flying = false
        button.Text = "🚀 เปิดบิน"
        vel.Velocity = Vector3.zero
    end
end)

-- ควบคุมทิศทาง WASD
uis.InputBegan:Connect(function(input)
    if not flying then return end
    if input.KeyCode == Enum.KeyCode.W then
        dir = Vector3.new(0, 0, -1)
    elseif input.KeyCode == Enum.KeyCode.S then
        dir = Vector3.new(0, 0, 1)
    elseif input.KeyCode == Enum.KeyCode.A then
        dir = Vector3.new(-1, 0, 0)
    elseif input.KeyCode == Enum.KeyCode.D then
        dir = Vector3.new(1, 0, 0)
    elseif input.KeyCode == Enum.KeyCode.Space then
        dir = Vector3.new(0, 1, 0)
    elseif input.KeyCode == Enum.KeyCode.LeftShift then
        dir = Vector3.new(0, -1, 0)
    end
end)

uis.InputEnded:Connect(function(input)
    if not flying then return end
    dir = Vector3.zero
end)

-- อัปเดตความเร็วในการบิน
run.RenderStepped:Connect(function()
    if flying then
        vel.Velocity = (plr.Character.HumanoidRootPart.CFrame:VectorToWorldSpace(dir)) * speed
    end
end)
