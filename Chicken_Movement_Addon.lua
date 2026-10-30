-- Chicken movement controls. Standalone, no downloaded dependencies.
-- Client speed can be overridden/rejected by the game server.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")
local old = guiParent:FindFirstChild("ChickenMovementAddon")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "ChickenMovementAddon"
gui.ResetOnSpawn = false
gui.Parent = guiParent
local alive, enabled, returning = true, false, false
local speed, threshold = 16, 8
local savedHumanoid, originalSpeed, lastApplied
local function restore()
    if savedHumanoid and savedHumanoid.Parent and savedHumanoid.WalkSpeed == lastApplied then
        savedHumanoid.WalkSpeed = originalSpeed
    end
    savedHumanoid, originalSpeed, lastApplied = nil, nil, nil
end
gui.Destroying:Connect(function() alive = false; restore() end)
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(350, 370)
frame.Position = UDim2.new(0.05, 0, 0.25, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 29, 23)
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
local layout = Instance.new("UIListLayout", frame)
layout.Padding = UDim.new(0, 8)
local padding = Instance.new("UIPadding", frame)
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
local function row(class, text)
    local item = Instance.new(class)
    item.Size = UDim2.new(1, 0, 0, 36)
    item.BackgroundColor3 = Color3.fromRGB(38, 52, 41)
    item.TextColor3 = Color3.fromRGB(232, 244, 234)
    item.TextSize = 16
    item.Font = Enum.Font.Gotham
    item.Text = text
    item.Parent = frame
    Instance.new("UICorner", item).CornerRadius = UDim.new(0, 8)
    return item
end
row("TextLabel", "CHICKEN • การเคลื่อนที่")
local toggle = row("TextButton", "ปรับความเร็ว: ปิด")
toggle.Activated:Connect(function()
    enabled = not enabled
    toggle.Text = "ปรับความเร็ว: " .. (enabled and "เปิด" or "ปิด")
    if not enabled then restore() end
end)
local input = row("TextBox", "16")
input.ClearTextOnFocus = false
input.PlaceholderText = "ความเร็ว 8–32"
input.FocusLost:Connect(function()
    speed = math.clamp(tonumber(input.Text) or speed, 8, 32)
    input.Text = tostring(speed)
end)
local deposit = row("TextButton", "ส่งของเมื่อครบจำนวน: ปิด")
deposit.Activated:Connect(function()
    returning = not returning
    deposit.Text = "ส่งของเมื่อครบจำนวน: " .. (returning and "เปิด" or "ปิด")
end)
local carryInput = row("TextBox", "8")
carryInput.ClearTextOnFocus = false
carryInput.PlaceholderText = "จำนวนที่แบกก่อนส่ง"
carryInput.FocusLost:Connect(function()
    threshold = math.clamp(math.floor(tonumber(carryInput.Text) or threshold), 1, 100)
    carryInput.Text = tostring(threshold)
end)
local recall = row("TextButton", "เรียกไก่กลับคอก")
local status = row("TextLabel", "พร้อม • God Mode ยังไม่รองรับ")
recall.Activated:Connect(function()
    local ok, err = pcall(function()
        local feature = player.PlayerScripts.Features.Chicken
        local controller = require(feature.controllers.ChickenController)
        if controller:setOrder("coop") then
            require(feature.ChickenMode).order("coop")
        end
    end)
    status.Text = ok and "ส่งคำสั่งกลับคอกแล้ว" or "เรียกกลับไม่สำเร็จ"
    if not ok then warn(err) end
end)
local close = row("TextButton", "ปิดหน้าต่างและหยุดส่วนเสริม")
close.Activated:Connect(function() gui:Destroy() end)
local deliveryActive, deliveryStarted, initialCarry = false, 0, 0
task.spawn(function()
    while alive do
        local ok, err = pcall(function()
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if enabled and humanoid then
                if savedHumanoid ~= humanoid then
                    restore()
                    savedHumanoid, originalSpeed = humanoid, humanoid.WalkSpeed
                end
                if humanoid.WalkSpeed ~= speed then humanoid.WalkSpeed = speed end
                lastApplied = speed
            end
            local carry = tonumber(player:GetAttribute("scrapCarry")) or 0
            if not returning or not root or not humanoid or carry <= 0 then
                deliveryActive = false
                return
            end
            if carry < threshold and not deliveryActive then return end
            if not deliveryActive then
                deliveryActive, deliveryStarted, initialCarry = true, os.clock(), carry
            end
            local recyclers = workspace:FindFirstChild("Recyclers")
            local plot = player:GetAttribute("Plot")
            local machine = recyclers and plot and recyclers:FindFirstChild("Recycler" .. tostring(plot))
            local origin = machine and machine:GetAttribute("Origin")
            if typeof(origin) ~= "CFrame" then
                status.Text = "หาเครื่องบดของแปลงนี้ไม่พบ"
                return
            end
            local target = origin.Position + Vector3.new(0, 3, 0)
            humanoid:MoveTo(target)
            if carry < initialCarry then
                deliveryActive = false
                status.Text = "ส่งของแล้ว • เหลือ " .. carry
            elseif os.clock() - deliveryStarted > 25 then
                returning, deliveryActive = false, false
                deposit.Text = "ส่งของเมื่อครบจำนวน: ปิด"
                status.Text = "ส่งไม่สำเร็จ • ตรวจทางเดิน/เครื่องบด"
            else
                status.Text = "กำลังเดินส่งของ • แบก " .. carry
            end
        end)
        if not ok then status.Text = "เกิดข้อผิดพลาด • ดู Console"; warn(err) end
        task.wait(0.5)
    end
end)
