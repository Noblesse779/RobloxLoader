local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- [ส่วนที่ต้องแก้] ใส่ path UI จริงของเกม (ดูด้วย Dex Explorer)
-- คืนค่า nil ถ้ายังหาไม่เจอ เพื่อไม่ให้สคริปต์ error
local function getCastUI()
    -- PlayerGui.FishingHud.Root.Power
    local hud = LocalPlayer.PlayerGui:FindFirstChild("FishingHud")
    local root = hud and hud:FindFirstChild("Root")
    return root and root:FindFirstChild("Power")
end

local function getCatchUI()
    -- ตัวอย่าง: return LocalPlayer.PlayerGui:FindFirstChild("FishingUI") and LocalPlayer.PlayerGui.FishingUI:FindFirstChild("CatchBar")
    return nil
end

local CAST_BAR_NAME = "ProgressBar" -- ชื่อแถบที่ยืดตามแรงชาร์จ ซึ่งอยู่ข้างใน Power
local CAST_TARGET = 0.9   -- ชาร์จหลอดถึง 90%
local CAST_TIMEOUT = 5    -- กดค้างนานสุดกี่วินาที กันลูปค้าง

-- ลบ UI เก่าถ้ารันสคริปต์ซ้ำ
local old = CoreGui:FindFirstChild("AutoFishUI")
if old then old:Destroy() end

-- สร้างหน้าต่าง UI เปิด-ปิด
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFishUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 150, 0, 80)
MainFrame.Position = UDim2.new(0.5, -75, 0.1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainFrame.Active = true
MainFrame.Parent = ScreenGui

-- แถบหัวไว้จับลาก (ปุ่มจะกินคลิก ลากจากปุ่มไม่ได้)
local TitleBar = Instance.new("TextLabel")
TitleBar.Size = UDim2.new(1, 0, 0, 20)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
TitleBar.Text = "Auto Fish"
TitleBar.TextColor3 = Color3.fromRGB(200, 200, 200)
TitleBar.Font = Enum.Font.SourceSans
TitleBar.TextSize = 14
TitleBar.Active = true
TitleBar.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -10, 1, -30)
ToggleButton.Position = UDim2.new(0, 5, 0, 25)
ToggleButton.Text = "เริ่มตกปลา (OFF)"
ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.SourceSansBold
ToggleButton.TextSize = 16
ToggleButton.Parent = MainFrame

-- ระบบลาก UI (แทน Draggable ที่ deprecated แล้ว)
do
    local dragging, dragStart, startPos
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local isAutoFishing = false
local runId = 0 -- กันลูปซ้อนเวลากดเปิด-ปิดเร็วๆ
local mouseHeld = false

-- คลิกกลางจอแทนมุม (0,0) ที่เป็น topbar
local function screenCenter()
    local size = workspace.CurrentCamera.ViewportSize
    return size.X / 2, size.Y / 2
end

local function setMouse(down)
    local x, y = screenCenter()
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 0)
    mouseHeld = down
end

local function clickMouse()
    setMouse(true)
    task.wait(0.02)
    setMouse(false)
end

local function isActive(myId)
    return isAutoFishing and runId == myId
end

-- ใช้ AbsolutePosition/AbsoluteSize จะแม่นกว่า Position.Scale (ไม่สน AnchorPoint/Offset)
local function centerX(gui)
    return gui.AbsolutePosition.X + gui.AbsoluteSize.X / 2
end

-- ลูปการทำงานหลัก
local function autoFishLoop(myId)
    while isActive(myId) do
        local castUI = getCastUI()
        local catchUI = getCatchUI()

        -- เงื่อนไขที่ 1: ชาร์จหลอดให้ถึงจุดสีเหลืองหลังสุด
        if castUI and castUI.Visible and castUI:FindFirstChild(CAST_BAR_NAME) then
            setMouse(true) -- กดค้าง
            local elapsed = 0
            repeat
                elapsed += task.wait(0.05)
            until not isActive(myId)
                or not castUI.Visible
                or not castUI:FindFirstChild(CAST_BAR_NAME)
                or castUI[CAST_BAR_NAME].Size.X.Scale >= CAST_TARGET
                or elapsed > CAST_TIMEOUT
            setMouse(false) -- ปล่อยเสมอ ไม่ให้เมาส์ค้าง
            if isActive(myId) then
                task.wait(2) -- รอเหยื่อตกน้ำ
            end

        -- เงื่อนไขที่ 2: ประคองปลาให้อยู่ในแถบสีเขียว
        elseif catchUI and catchUI.Visible
            and catchUI:FindFirstChild("FishIcon") and catchUI:FindFirstChild("GreenBar") then
            local fishX = centerX(catchUI.FishIcon)
            local barX = centerX(catchUI.GreenBar)

            -- ถ้าแถบเขียวอยู่ซ้ายของปลา ให้คลิกเพื่อดันแถบไปทางขวา
            -- (ถ้าเกมนี้คลิกแล้วแถบไปทางซ้าย ให้กลับเครื่องหมายเป็น >)
            if barX < fishX then
                clickMouse()
            end
        end

        task.wait(0.05)
    end
end

local function setEnabled(on)
    isAutoFishing = on
    runId += 1
    if on then
        ToggleButton.Text = "กำลังตกปลา (ON)"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
        task.spawn(autoFishLoop, runId)
    else
        ToggleButton.Text = "เริ่มตกปลา (OFF)"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        if mouseHeld then
            setMouse(false)
        end
    end
end

-- ระบบเปิด-ปิดเมื่อกดปุ่ม
ToggleButton.MouseButton1Click:Connect(function()
    setEnabled(not isAutoFishing)
end)
