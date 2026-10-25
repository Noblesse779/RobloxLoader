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
    -- PlayerGui.FishingHud.Reel (ข้างในมี Water > Fish, Zone และ Progress > Fill)
    local hud = LocalPlayer.PlayerGui:FindFirstChild("FishingHud")
    return hud and hud:FindFirstChild("Reel")
end

-- โครงสร้าง: Power > Track > Fill (แถบที่ยืดตามแรงชาร์จ), PerfectZone (โซนแรงพอดี)
local CAST_TARGET = 0.9   -- ใช้เมื่อหา PerfectZone ไม่เจอ: ชาร์จหลอดถึง 90%
local PERFECT_AIM = 0.2   -- ปล่อยเมื่อปลายแถบถึงตำแหน่งไหนของ PerfectZone (0 = ขอบซ้าย, 0.5 = กลาง)
                          -- ถ้าเบ็ดไปไกลเกิน (ปล่อยเลยจุดเหลือง) ให้ลดลง, ถ้าปล่อยก่อนถึงให้เพิ่ม
local CAST_TIMEOUT = 5    -- กดค้างนานสุดกี่วินาที กันลูปค้าง
local POWER_APPEAR_TIMEOUT = 0.5 -- กดแล้วรอหลอด Power ขึ้นกี่วินาที
local CHARGE_TIME = 1.0   -- ถ้าไม่เห็นหลอด Power: กดค้างชาร์จกี่วินาทีแล้วปล่อย
local MIN_BITE_WAIT = 1.5 -- โยนแล้วอย่างน้อยกี่วินาทีถึงเริ่มเช็คว่าปลากิน
local BITE_TEXT = "กดเลย"   -- ข้อความบนปุ่มตอนปลากินเหยื่อ
local HOOK_REACTION = 0.3 -- ปลากินแล้วรอกี่วินาทีก่อนกดตวัด (ให้ดูเหมือนคนกด)
local SKIP_MINIGAME = true      -- true = ข้ามมินิเกมดึงปลา (ยิง "Reel", true เอง) ถ้าเซิร์ฟเวอร์ไม่ให้ปลาจะเล่นมินิเกมต่อให้
local SKIP_MINIGAME_DELAY = 2.8 -- ตวัดแล้วรอกี่วินาทีก่อนยิง (2.7 วิบางรอบไม่ได้ปลา, 2.8 วิได้ทุกรอบ)
local AFTER_CATCH_DELAY = 2 -- ได้ปลาแล้วรอกี่วินาทีก่อนโยนใหม่ (ถ้าโยนไม่ออกเพราะหน้าต่างโชว์ปลาบัง ให้เพิ่ม)
local READY_TIMEOUT = 5   -- หลังได้ปลา รอปุ่มกลับเป็น "เหวี่ยง" นานสุดกี่วินาที ก่อนลองเหวี่ยงต่อเลย
local CAST_DELAY = 0.5    -- ก่อนเหวี่ยงแต่ละครั้งรออีกกี่วินาที
local BITE_TIMEOUT = 30   -- โยนแล้วรอปลากินนานสุดกี่วินาที ก่อนโยนใหม่
local REEL_TIMEOUT = 25   -- (โหมด play) เล่นมินิเกมนานสุดกี่วินาที
local USE_EXECUTOR_MOUSE = false -- true = ใช้ mouse1press ของ executor แทน VirtualInputManager
local REEL_HOLD = true    -- true = กดค้างตอน Zone ต้องเลื่อนหาปลา, false = คลิกทีละครั้ง (ลองสลับถ้าแบบแรกไม่ได้ผล)
local REEL_INVERT = false -- true ถ้าคลิกแล้ว Zone เลื่อนไปทางตรงข้ามกับที่ควร

-- ลบ UI เก่าถ้ารันสคริปต์ซ้ำ
local old = CoreGui:FindFirstChild("AutoFishUI")
if old then old:Destroy() end

-- สร้างหน้าต่าง UI เปิด-ปิด
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFishUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Enabled = false -- ซ่อนไว้ก่อน ใช้หน้าต่าง Fluent แทน (แสดงเฉพาะตอนโหลด Fluent ไม่ได้)
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 170, 0, 100)
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
ToggleButton.Size = UDim2.new(1, -10, 1, -50)
ToggleButton.Position = UDim2.new(0, 5, 0, 25)
ToggleButton.Text = "เริ่มตกปลา (OFF)"
ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.Font = Enum.Font.SourceSansBold
ToggleButton.TextSize = 16
ToggleButton.Parent = MainFrame

-- บรรทัดสถานะ บอกว่าสคริปต์กำลังทำอะไร (ช่วยหาว่าติดตรงไหน)
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -10, 0, 20)
StatusLabel.Position = UDim2.new(0, 5, 1, -22)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "สถานะ: ปิดอยู่"
StatusLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
StatusLabel.Font = Enum.Font.SourceSans
StatusLabel.TextSize = 13
StatusLabel.TextScaled = true
StatusLabel.Parent = MainFrame

local function setStatus(text)
    StatusLabel.Text = "สถานะ: " .. text
end

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

local GuiService = game:GetService("GuiService")
local getPressPoint -- กำหนดทีหลัง (ต้องใช้ฟังก์ชันหาปุ่ม)

local function screenCenter()
    local size = workspace.CurrentCamera.ViewportSize
    return size.X / 2, size.Y / 2
end

-- ใช้ mouse1press/mouse1release ของ executor ถ้ามี (เกมส่วนใหญ่รับ)
-- ถ้าไม่มีค่อยใช้ VirtualInputManager
local hasMouse1 = typeof(mouse1press) == "function" and typeof(mouse1release) == "function"
local hasMoveAbs = typeof(mousemoveabs) == "function"

local actionRemote
local function getActionRemote()
    if not actionRemote then
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local fishing = remotes and remotes:FindFirstChild("Fishing")
        actionRemote = fishing and fishing:FindFirstChild("Action")
    end
    return actionRemote
end

local pressX, pressY
local function setMouse(down)
    -- กดที่ปุ่ม เหวี่ยง ของเกม (ถ้าหาไม่เจอค่อยกดกลางจอ) จุดเดิมทั้งตอนกดและปล่อย
    if down or not pressX then
        pressX, pressY = getPressPoint()
    end
    local x, y = pressX, pressY
    if USE_EXECUTOR_MOUSE and hasMouse1 then
        -- ย้ายเมาส์ไปที่ปุ่มก่อน ไม่งั้นจะไปกดโดนปุ่ม ON/OFF ของเราเอง
        if down and hasMoveAbs then
            mousemoveabs(x, y)
        end
        if down then mouse1press() else mouse1release() end
    else
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, down, game, 1)
    end
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
local function center(gui)
    return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

-- ปลายแถบ Fill ถึงจุดที่ต้องการปล่อยหรือยัง
local function castReady(track)
    local fill = track:FindFirstChild("Fill")
    if not fill then return true end
    local zone = track:FindFirstChild("PerfectZone")
    if zone and zone.Visible then
        local fillEnd = fill.AbsolutePosition.X + fill.AbsoluteSize.X
        local aim = zone.AbsolutePosition.X + zone.AbsoluteSize.X * PERFECT_AIM
        return fillEnd >= aim
    end
    return fill.Size.X.Scale >= CAST_TARGET
end

-- เช็คว่า UI แสดงบนจอจริงไหม (ไล่ดู Visible ทุกชั้นขึ้นไปจนถึง ScreenGui.Enabled)
local function isShown(gui)
    while gui do
        if gui:IsA("ScreenGui") then
            return gui.Enabled
        elseif gui:IsA("GuiObject") and not gui.Visible then
            return false
        end
        gui = gui.Parent
    end
    return false
end

local function isReeling()
    local catchUI = getCatchUI()
    return catchUI ~= nil and isShown(catchUI)
end

-- ปุ่มแอคชันของเกม: ปกติเขียน "เหวี่ยง" พอปลากินจะเปลี่ยนเป็นสีแดง เขียน "กดเลย!"
local actionLabel
local lastLabelScan = 0
local function getActionLabel()
    -- ใช้ตัวเดิมถ้ายังอยู่และยังแสดงบนจอ (เกมอาจสร้างปุ่มใหม่หลังได้ปลา)
    if actionLabel and actionLabel.Parent and isShown(actionLabel) then
        return actionLabel
    end
    -- สแกนใหม่ไม่เกินวินาทีละ 2 ครั้ง
    if os.clock() - lastLabelScan < 0.5 then
        return actionLabel
    end
    lastLabelScan = os.clock()

    local fallback
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton"))
            and (d.Text:match("^%s*เหวี่ยง%s*$") or d.Text:find(BITE_TEXT, 1, true)) then
            -- ต้องตรงคำว่า "เหวี่ยง" เป๊ะ ไม่งั้นจะไปเจอป้าย "แรงเหวี่ยง" บนหลอดชาร์จ
            if isShown(d) then
                actionLabel = d
                return d
            end
            fallback = fallback or d
        end
    end
    if fallback or not (actionLabel and actionLabel.Parent) then
        actionLabel = fallback
    end
    return actionLabel
end

-- ตัวปุ่มที่ต้องกด: GuiButton ที่ครอบข้อความ ถ้าไม่มีก็ใช้กรอบที่ครอบข้อความ
local function getActionButton()
    local label = getActionLabel()
    if not label then return nil end
    if label:IsA("GuiButton") then return label end
    return label:FindFirstAncestorWhichIsA("GuiButton")
        or (label.Parent and label.Parent:IsA("GuiObject") and label.Parent)
        or label
end

getPressPoint = function()
    local button = getActionButton()
    if not button then
        return screenCenter()
    end
    local c = button.AbsolutePosition + button.AbsoluteSize / 2
    local sg = button:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.IgnoreGuiInset then
        -- AbsolutePosition ไม่นับแถบ topbar แต่การคลิกนับ เลยต้องบวกเพิ่ม
        c += GuiService:GetGuiInset()
    end
    return c.X, c.Y
end

local function actionSaysBite()
    local label = getActionLabel()
    return label ~= nil and label.Text:find(BITE_TEXT, 1, true) ~= nil and isShown(label)
end

-- รอจนกว่าเงื่อนไขจะเป็นจริง หรือหมดเวลา / ถูกปิด
local function waitFor(myId, timeout, check)
    local elapsed = 0
    while isActive(myId) and elapsed < timeout do
        if check() then return true end
        elapsed += task.wait()
    end
    return false
end

-- โยนเบ็ดแบบเมาส์: กดค้างเอง -> รอหลอด Power ขึ้น -> ปล่อยตอนเข้า PerfectZone
local function castMouse(myId)
    setStatus("กดค้างเพื่อเหวี่ยง...")
    setMouse(true)

    local track
    local appeared = waitFor(myId, POWER_APPEAR_TIMEOUT, function()
        local castUI = getCastUI()
        track = castUI and castUI:FindFirstChild("Track")
        return track ~= nil and track:FindFirstChild("Fill") ~= nil and isShown(castUI)
    end)

    if appeared then
        setStatus("ชาร์จ รอเข้าจุดเหลือง")
        waitFor(myId, CAST_TIMEOUT, function()
            return not isShown(track) or castReady(track)
        end)
    else
        -- ไม่เห็นหลอด: กดค้างตามเวลาแทน
        setStatus(("ชาร์จ %.1f วิ (ไม่เห็นหลอด)"):format(CHARGE_TIME))
        waitFor(myId, math.max(0, CHARGE_TIME - POWER_APPEAR_TIMEOUT), function() return false end)
    end
    setMouse(false) -- ปล่อยเสมอ ไม่ให้เมาส์ค้าง

    -- ถ้าเกมยังไม่รับการปล่อย (หลอด Power ยังค้าง / คันเบ็ดยกค้าง) ส่งปล่อยซ้ำ
    for i = 1, 3 do
        local castUI = getCastUI()
        if not (castUI and isShown(castUI)) then break end
        task.wait(0.3)
        castUI = getCastUI()
        if not (castUI and isShown(castUI)) then break end
        setStatus(("ปล่อยซ้ำ %d"):format(i))
        if hasMouse1 then pcall(mouse1release) end
        local x, y = getPressPoint()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end
    return true
end

-- ดึงปลา: ประคอง Zone ให้อยู่ตรงปลา
local function reelStep()
    local water = getCatchUI():FindFirstChild("Water")
    local fish = water and water:FindFirstChild("Fish")
    local zone = water and water:FindFirstChild("Zone")
    if not (fish and zone) then return end

    local fishPos = center(fish)
    local zonePos = center(zone)

    -- แนวตั้ง: คลิกแล้ว Zone ขึ้น -> คลิกเมื่อ Zone อยู่ต่ำกว่าปลา (Y มากกว่า)
    -- แนวนอน: คลิกแล้ว Zone ไปขวา -> คลิกเมื่อ Zone อยู่ซ้ายของปลา
    local needPush
    if water.AbsoluteSize.Y > water.AbsoluteSize.X then
        needPush = zonePos.Y > fishPos.Y
    else
        needPush = zonePos.X < fishPos.X
    end
    if REEL_INVERT then
        needPush = not needPush
    end

    if REEL_HOLD then
        if needPush ~= mouseHeld then
            setMouse(needPush)
        end
    elseif needPush then
        clickMouse()
    end
end

-- ปุ่มกลับมาเป็น "เหวี่ยง" = พร้อมเหวี่ยงรอบใหม่
local function actionReady()
    local label = getActionLabel()
    return label ~= nil and label.Text:match("^%s*เหวี่ยง%s*$") ~= nil and isShown(label)
end

-- ===== ตรวจว่าได้ปลาแล้ว =====
-- ตอนได้ปลา เกมจะยิง Remotes.Fishing.Action:FireServer("Reel", true) แล้วหน้าต่างโชว์ปลาเด้งขึ้น
-- ดักการยิง remote ตัวนี้ด้วย hookmetamethod (ถ้า executor รองรับ)
local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.AutoFishLastCatch = env.AutoFishLastCatch or 0

if not env.AutoFishCatchHooked and typeof(hookmetamethod) == "function"
    and typeof(getnamecallmethod) == "function" then
    local remote = getActionRemote()
    if remote then
        env.AutoFishCatchHooked = true
        local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if self == remote and getnamecallmethod() == "FireServer" then
                local action, value = ...
                if action == "Reel" and value == true then
                    env.AutoFishLastCatch = os.clock()
                end
            end
            return oldNamecall(self, ...)
        end))
    end
end

-- สำรอง: ดูหน้าต่างโชว์ปลา (บรรทัด "ขายได้ ... เหรียญ") แค่ดูเฉยๆ ไม่คลิก
local popupGui -- ScreenGui ของหน้าต่างโชว์ปลา (จำไว้ จะได้ไม่ต้องค้นทั้ง PlayerGui ทุกครั้ง)
local function catchPopupShown()
    local root = (popupGui and popupGui.Parent) and popupGui or LocalPlayer.PlayerGui
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:find("ขายได้", 1, true)
            and d.Text:find("เหรียญ", 1, true) and isShown(d) then
            popupGui = d:FindFirstAncestorWhichIsA("ScreenGui")
            return true
        end
    end
    return false
end

local function caughtSince(t)
    return env.AutoFishLastCatch > t or catchPopupShown()
end

local skipReadyWait = false -- รอบก่อนได้ปลา -> โยนต่อเลยไม่ต้องรอปุ่ม

-- โหมด play: เล่นเหมือนคนกดปุ่มเอง
-- เหวี่ยง (กดค้างชาร์จถึงจุดเหลือง) -> รอปุ่ม "กดเลย!" -> กดตวัด -> เล่นมินิเกมจนจบ
local function playRound(myId)
    setStatus("รอปุ่ม เหวี่ยง พร้อม")
    if skipReadyWait then
        skipReadyWait = false
    elseif not waitFor(myId, READY_TIMEOUT, actionReady) then
        if not isActive(myId) then return end
        -- ปุ่มไม่กลับเป็น "เหวี่ยง" (อาจมีหน้าต่างโชว์ปลาบังอยู่) ลองกดปุ่ม 1 ครั้งแล้วเหวี่ยงต่อเลย
        local label = getActionLabel()
        setStatus(label and ("ปุ่มขึ้นว่า: " .. label.Text .. " ลองเหวี่ยงต่อ") or "หาปุ่ม เหวี่ยง ไม่เจอ")
        if not label then
            task.wait(1)
            return
        end
        clickMouse()
        task.wait(1)
        if not isActive(myId) then return end
    end
    task.wait(CAST_DELAY)
    if not isActive(myId) then return end

    -- 1) เหวี่ยง
    local roundStart = os.clock()
    castMouse(myId)
    if not isActive(myId) then return end

    -- 2) รอปลากิน
    setStatus("เหวี่ยงแล้ว รอปลากิน")
    waitFor(myId, MIN_BITE_WAIT, function() return false end)
    if not waitFor(myId, BITE_TIMEOUT, actionSaysBite) then
        return -- ไม่มีปลากิน (หรือเบ็ดไม่ออก) ลองใหม่
    end

    -- 3) ตวัดเบ็ด
    setStatus("ปลากิน! ตวัด")
    task.wait(HOOK_REACTION)
    if not isActive(myId) then return end
    clickMouse()

    -- 4ก) ลองข้ามมินิเกม: ยิง "Reel", true เอง แล้วดูว่าหน้าต่างโชว์ปลาขึ้นไหม
    if SKIP_MINIGAME and getActionRemote() then
        setStatus(("ข้ามมินิเกม รอ %.1f วิ"):format(SKIP_MINIGAME_DELAY))
        waitFor(myId, SKIP_MINIGAME_DELAY, function() return false end)
        if not isActive(myId) then return end
        getActionRemote():FireServer("Reel", true)
        if waitFor(myId, 2, catchPopupShown) then
            setStatus(("ข้ามได้! โยนใหม่ใน %.1f วิ"):format(AFTER_CATCH_DELAY))
            waitFor(myId, AFTER_CATCH_DELAY, function() return false end)
            skipReadyWait = true
            return
        end
        if not isActive(myId) then return end
        setStatus("ข้ามไม่ได้ เล่นมินิเกมแทน")
    end

    -- 4) มินิเกม: ประคอง Zone ให้อยู่ตรงปลา จนปุ่มกลับเป็น "เหวี่ยง"
    if not (SKIP_MINIGAME and getActionRemote()) then
        setStatus("เล่นมินิเกม")
    end
    waitFor(myId, 1, function() return not actionSaysBite() end)
    local caught = false
    waitFor(myId, REEL_TIMEOUT, function()
        if caughtSince(roundStart) then
            caught = true
            return true
        end
        if actionReady() then return true end
        if isReeling() then
            reelStep()
        end
        return false
    end)
    if mouseHeld then
        setMouse(false)
    end

    if caught then
        -- 5) ได้ปลาแล้ว (ยิง "Reel", true / หน้าต่างโชว์ปลาขึ้น) รอแป๊บแล้วโยนใหม่เลย
        setStatus(("ได้ปลา! โยนใหม่ใน %.1f วิ"):format(AFTER_CATCH_DELAY))
        waitFor(myId, AFTER_CATCH_DELAY, function() return false end)
        skipReadyWait = true
    else
        setStatus("จบรอบ")
    end
end

-- ลูปการทำงานหลัก
local function autoFishLoop(myId)
    while isActive(myId) do
        playRound(myId)
    end
    if mouseHeld then
        setMouse(false)
    end
end

local function setEnabled(on)
    isAutoFishing = on
    runId += 1
    if on then
        ToggleButton.Text = "กำลังตกปลา (ON)"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(40, 180, 40)
        local myId = runId
        task.spawn(function()
            local ok, err = pcall(autoFishLoop, myId)
            if not ok then
                warn("[AutoFish] " .. tostring(err))
                setStatus("error: " .. tostring(err))
                if mouseHeld then setMouse(false) end
            end
        end)
    else
        ToggleButton.Text = "เริ่มตกปลา (OFF)"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        setStatus("ปิดอยู่")
        if mouseHeld then
            setMouse(false)
        end
    end
end

-- ระบบเปิด-ปิดเมื่อกดปุ่ม
ToggleButton.MouseButton1Click:Connect(function()
    setEnabled(not isAutoFishing)
end)

-- =====================================================================
-- ฟังก์ชันเสริม (แยกจากระบบตกปลา ไม่ได้แก้อะไรในส่วนตกปลา)
-- 1) กันโดนเตะ AFK  2) นับสถิติ  3) ปุ่มลัด  4) ตั้งเวลาหยุด  5) ย่อหน้าต่าง  6) วิ่งเร็ว/กระโดดสูง
-- 7) ขายปลา (วาร์ป/เดินไปร้าน)  8) พักเป็นระยะ  9) หยุดเมื่อมีคนใกล้  10) เตือนปลาหายาก
-- =====================================================================
-- อยู่ในฟังก์ชันแยก: Luau ให้ใช้ตัวแปร local ได้ไม่เกิน 200 ตัวต่อฟังก์ชัน
-- ถ้าเขียนเป็น do ... end ธรรมดา จะรวมกับตัวแปรของส่วนตกปลาจนเกิน แล้วสคริปต์ไม่รันเลย
;(function()
    local RunService = game:GetService("RunService")

    local TOGGLE_KEY = Enum.KeyCode.F -- ปุ่มเปิด/ปิดตกปลา
    local HIDE_KEY = Enum.KeyCode.H   -- ปุ่มซ่อน/แสดงหน้าต่าง

    -- ทุกฟังก์ชันปิดไว้ตอนเริ่ม เปิดเองในหน้าต่าง
    local settings = {
        antiAfk = false,
        speedOn = false, speed = 32,
        jumpOn = false, jump = 100,
        stopFish = 0,    -- 0 = ไม่จำกัด
        stopMinutes = 0, -- 0 = ไม่จำกัด
        autoSell = false,
        sellAt = 100,    -- ปลาในกระเป๋าครบกี่ตัวแล้วขายทั้งหมด
        sellTravel = "walk", -- ไปร้านยังไง: "walk" = เดินไป (เนียนกว่า), "warp" = วาร์ป (เร็วกว่า)
        walkFallbackWarp = false, -- เดินแล้วติด/ตกน้ำ ให้วาร์ปแทน (ไม่งั้นจะติดค้างอยู่ตรงนั้น)
        autoEquip = false, -- ตกปลาอยู่แล้วเบ็ดไม่อยู่ในมือ หยิบให้เอง
        autoRejoin = false, -- หลุด/โดนเตะ เข้าเกมใหม่เอง แล้วตกต่อ
        showRoute = false, -- แสดงจุดเส้นทาง/จุดตกปลา/จุดร้านในโลก (เห็นแค่เราคนเดียว)
        returnMode = "walk", -- ขายเสร็จแล้วกลับจุดตกปลายังไง: "walk" = เดิน, "warp" = วาร์ป, "stay" = ไม่กลับ (หยุดตกปลา)
        breakOn = false, breakEvery = 25, breakSeconds = 30, -- พักทุกประมาณกี่ตัว / พักประมาณกี่วิ (สุ่ม ±30-40%)
        nearbyOn = false, nearbyRange = 30, -- มีผู้เล่นอื่นเข้ามาใกล้กี่ studs ให้พัก
        rareAlert = false, rareStop = false, -- เตือน / หยุด เมื่อได้ปลาที่ไม่ใช่ระดับ "ทั่วไป"
    }

    -- ชื่อระดับความหายากที่รู้จัก (ถ้าเกมมีชื่ออื่นเพิ่มเข้าไปได้)
    local RARITIES = { "ทั่วไป", "พิเศษ", "หายาก", "ยอดเยี่ยม", "มหากาพย์", "ตำนาน", "ในตำนาน", "เทพ", "เทพเจ้า", "ลึกลับ" }

    ---------------------------------------------------------------- UI (Fluent)
    -- หน้าต่างใช้ไลบรารี Fluent (https://github.com/dawid-scripts/Fluent)
    -- ถ้าโหลดไม่ได้ จะใช้หน้าต่างเดิมแบบง่าย (มีแค่ปุ่มเปิด/ปิดตกปลา) ฟังก์ชันเสริมจะไม่ทำงาน
    local FLUENT_URL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"

    -- เก็บโค้ด Fluent ไว้ในไฟล์ รอบถัดไปโหลดจากเครื่อง ไม่ต้องดาวน์โหลดใหม่ (เปิดเร็วขึ้น)
    local FLUENT_CACHE = "AutoFish/fluent.lua"
    local canCache = typeof(readfile) == "function" and typeof(writefile) == "function"
        and typeof(isfile) == "function"
    local function loadFluent(useCache)
        local source
        if useCache and canCache and isfile(FLUENT_CACHE) then
            source = readfile(FLUENT_CACHE)
        else
            source = game:HttpGet(FLUENT_URL)
            if canCache then
                pcall(function()
                    if typeof(makefolder) == "function" and not (typeof(isfolder) == "function" and isfolder("AutoFish")) then
                        makefolder("AutoFish")
                    end
                    writefile(FLUENT_CACHE, source)
                end)
            end
        end
        return loadstring(source)()
    end
    local okFluent, Fluent = pcall(loadFluent, true)
    if not okFluent or typeof(Fluent) ~= "table" then
        okFluent, Fluent = pcall(loadFluent, false) -- ไฟล์ในเครื่องเสีย: ดาวน์โหลดใหม่
    end
    if not okFluent or typeof(Fluent) ~= "table" then
        warn("[AutoFish] โหลด Fluent ไม่ได้: " .. tostring(Fluent))
        setStatus("โหลดหน้าต่างใหม่ไม่ได้")
        ScreenGui.Enabled = true -- ใช้หน้าต่างเดิมแบบง่ายแทน
        return
    end


    -- ปิดหน้าต่าง Fluent ไปพร้อมกับสคริปต์ (รันใหม่ / ปิดสคริปต์)
    ScreenGui.AncestryChanged:Connect(function()
        if not ScreenGui.Parent then
            pcall(function() Fluent:Destroy() end)
        end
    end)

    local Window = Fluent:CreateWindow({
        Title = "ตกปลาอัตโนมัติ",
        SubTitle = "เวอร์ชัน 2.0",
        TabWidth = 160,
        Size = UDim2.fromOffset(600, 460),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = HIDE_KEY, -- กด H ซ่อน/แสดงหน้าต่าง
    })

    local Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
        sell = Window:AddTab({ Title = "ขายปลา", Icon = "coins" }),
        walk = Window:AddTab({ Title = "เดิน / เส้นทาง", Icon = "map" }),
        safe = Window:AddTab({ Title = "ความปลอดภัย", Icon = "shield" }),
        char = Window:AddTab({ Title = "ตัวละคร", Icon = "user" }),
        alert = Window:AddTab({ Title = "แจ้งเตือน", Icon = "bell" }),
        profile = Window:AddTab({ Title = "บันทึกตั้งค่า", Icon = "save" }),
    }

    -- ตัวกลางให้โค้ดส่วนอื่นใช้ได้เหมือนปุ่ม/ข้อความเดิม (.Text = ..., .MouseButton1Click:Connect)
    local function proxyButton(container, title, desc)
        local handlers = {}
        local element = container:AddButton({
            Title = title,
            Description = desc,
            Callback = function()
                for _, h in ipairs(handlers) do
                    task.spawn(h)
                end
            end,
        })
        local proxy = {
            MouseButton1Click = {
                Connect = function(_, fn)
                    table.insert(handlers, fn)
                end,
            },
        }
        return setmetatable(proxy, {
            __newindex = function(_, key, value)
                if key == "Text" then
                    pcall(function() element:SetTitle(value) end)
                end
            end,
        })
    end

    local function proxyLabel(container, title, initial)
        local element = container:AddParagraph({ Title = title, Content = initial or "-" })
        local store = { Text = initial or "" }
        return setmetatable({}, {
            __index = store,
            __newindex = function(_, key, value)
                if key == "Text" then
                    store.Text = value
                    pcall(function() element:SetDesc(value) end)
                end
            end,
        })
    end

    -- controls[ชื่อค่าใน settings] = ตัวควบคุมในหน้าต่าง (ใช้ตอนโหลดโปรไฟล์ให้ปุ่มตรงกับค่า)
    local controls = {}
    local toggleCount = 0
    local function addToggle(container, title, desc, get, set, key)
        toggleCount += 1
        local t = container:AddToggle("AFToggle" .. toggleCount, { Title = title, Description = desc, Default = get() })
        t:OnChanged(function(v)
            set(v)
        end)
        if key then
            controls[key] = { kind = "toggle", element = t }
        end
        return t
    end

    local function addNumber(container, title, value, onChange, key)
        toggleCount += 1
        local input
        input = container:AddInput("AFInput" .. toggleCount, {
            Title = title,
            Default = tostring(value),
            Numeric = true,
            Finished = true,
            Callback = function(text)
                local n = tonumber(text)
                if n and n >= 0 then
                    onChange(n)
                end
            end,
        })
        if key then
            controls[key] = { kind = "number", element = input }
        end
        return input
    end

    -- ส่วนอื่นมาเติมฟังก์ชันให้ (ส่วนพักตกปลาอยู่ข้างล่าง)
    local uiHooks = {
        fishingToggled = function(v) setEnabled(v) end,
        wantFishing = function() return isAutoFishing end,
    }

    ---- หน้า หลัก
    local fishSection = Tabs.main:AddSection("ตกปลา")
    local syncingFishing = false
    local fishingToggle = fishSection:AddToggle("AFFishing", {
        Title = "เปิดตกปลาอัตโนมัติ",
        Description = ("กด %s เปิด/ปิด  •  กด %s ซ่อนหน้าต่าง"):format(TOGGLE_KEY.Name, HIDE_KEY.Name),
        Default = false,
    })
    fishingToggle:OnChanged(function(v)
        if syncingFishing then return end
        if v ~= uiHooks.wantFishing() then
            uiHooks.fishingToggled(v)
        end
    end)

    local statusPara = fishSection:AddParagraph({ Title = "สถานะ", Content = StatusLabel.Text })
    addToggle(fishSection, "ถือเบ็ดให้เอง", "เบ็ดหลุดมือ (ตาย / วาร์ป / สลับช่อง) จะหยิบกลับมาให้",
        function() return settings.autoEquip end,
        function(v) settings.autoEquip = v end, "autoEquip")
    StatusLabel:GetPropertyChangedSignal("Text"):Connect(function()
        pcall(function() statusPara:SetDesc(StatusLabel.Text) end)
    end)

    local statsSection = Tabs.main:AddSection("สถิติ")
    local statsLabel = proxyLabel(statsSection, "ผลการตก", "-")
    local resetButton = proxyButton(statsSection, "รีเซ็ตสถิติ")

    local stopSection = Tabs.main:AddSection("หยุดเอง (0 = ไม่จำกัด)")
    addNumber(stopSection, "หยุดเมื่อได้ปลา (ตัว)", settings.stopFish, function(n) settings.stopFish = math.floor(n) end, "stopFish")
    addNumber(stopSection, "หยุดเมื่อครบ (นาที)", settings.stopMinutes, function(n) settings.stopMinutes = n end, "stopMinutes")

    -- ให้ปุ่มเปิดตกปลาตรงกับสถานะจริง (เปิด/ปิดจาก F, หยุดเอง, พัก ฯลฯ)
    -- ชื่อ refreshTitle เดิม: ลูปสถิติเรียกทุกครึ่งวิ
    local function refreshTitle()
        if Fluent.Unloaded then
            -- ผู้เล่นกดปิดหน้าต่าง Fluent = ปิดสคริปต์
            setEnabled(false)
            ScreenGui:Destroy()
            return
        end
        local want = uiHooks.wantFishing()
        if fishingToggle.Value ~= want then
            syncingFishing = true
            pcall(function() fishingToggle:SetValue(want) end)
            syncingFishing = false
        end
    end

    ---- หน้า ขายปลา
    local sellSection = Tabs.sell:AddSection("ขายอัตโนมัติ")
    addToggle(sellSection, "ขายเมื่อครบจำนวน", "ปลาในกระเป๋าครบแล้วขายทุกตัวทีเดียว",
        function() return settings.autoSell end,
        function(v) settings.autoSell = v end, "autoSell")
    addNumber(sellSection, "จำนวนที่จะขาย (ตัว)", settings.sellAt,
        function(n) settings.sellAt = math.max(1, math.floor(n)) end, "sellAt")
    local sellNowButton = proxyButton(sellSection, "ขายปลาทั้งหมดตอนนี้")
    local shopButton = proxyButton(sellSection, "บันทึกจุดร้าน", "ยืนที่ร้านแล้วกด (เซิร์ฟเวอร์ให้ขายเฉพาะใกล้ร้าน)")
    local bagLabel = proxyLabel(sellSection, "ผลการขาย", "-")

    ---- หน้า เดิน / เส้นทาง
    local SLOT_COUNT = 5
    local slotSection = Tabs.walk:AddSection("จุดที่บันทึกไว้ (แต่ละช่องมีจุดตกปลา + เส้นทาง + ร้าน)")
    local slotNames = {}
    for i = 1, SLOT_COUNT do
        slotNames[i] = "จุด " .. i
    end
    uiHooks.slotChanged = function() end -- กำหนดจริงในส่วนการเดิน
    slotSection:AddDropdown("AFSlot", {
        Title = "ใช้จุด",
        Values = slotNames,
        Default = env.AutoFishSlot or 1,
    }):OnChanged(function(v)
        local i = tonumber(tostring(v):match("%d+"))
        if i then
            uiHooks.slotChanged(i)
        end
    end)
    local slotLabel = proxyLabel(slotSection, "ข้อมูลจุดนี้", "-")
    local warpSpotButton = proxyButton(slotSection, "วาร์ปไปจุดตกปลาของช่องนี้", "หรือกด \"เดินกลับจุดตกปลา\" ด้านล่าง")

    local tripSection = Tabs.walk:AddSection("ไปขาย / กลับ")
    local TRAVEL = { ["เดินไป (เนียน)"] = "walk", ["วาร์ป (เร็ว)"] = "warp" }
    local travelDropdown = tripSection:AddDropdown("AFTravel", {
        Title = "ไปร้านโดย",
        Values = { "เดินไป (เนียน)", "วาร์ป (เร็ว)" },
        Default = settings.sellTravel == "warp" and 2 or 1,
    })
    travelDropdown:OnChanged(function(v)
        settings.sellTravel = TRAVEL[v] or settings.sellTravel
    end)
    local RETURN = { ["เดินกลับ"] = "walk", ["วาร์ปกลับ"] = "warp", ["ไม่กลับ (หยุดตกที่ร้าน)"] = "stay" }
    local returnDropdown = tripSection:AddDropdown("AFReturn", {
        Title = "ขายเสร็จแล้ว",
        Values = { "เดินกลับ", "วาร์ปกลับ", "ไม่กลับ (หยุดตกที่ร้าน)" },
        Default = settings.returnMode == "warp" and 2 or settings.returnMode == "stay" and 3 or 1,
    })
    returnDropdown:OnChanged(function(v)
        settings.returnMode = RETURN[v] or settings.returnMode
    end)
    addToggle(tripSection, "เดินติดให้วาร์ปแทน", "ตกน้ำ / ติด / หาทางไม่เจอ จะวาร์ปไปแทน",
        function() return settings.walkFallbackWarp end,
        function(v) settings.walkFallbackWarp = v end, "walkFallbackWarp")

    local routeSection = Tabs.walk:AddSection("เส้นทาง (บันทึกจากจุดตกปลา → ร้าน)")
    local routeButton = proxyButton(routeSection, "บันทึกเส้นทางเดิน",
        "ยืนที่จุดตกปลาแล้วกด เดินไปร้านเอง แล้วกดอีกครั้งที่ร้าน")
    local goBackButton = proxyButton(routeSection, "เดินกลับจุดตกปลา")
    local goShopButton = proxyButton(routeSection, "เดินไปร้าน")
    local drawRoute = function() end -- กำหนดจริงในส่วนการเดิน
    addToggle(routeSection, "แสดงเส้นทางในโลก", "เขียว = จุดตกปลา, เหลือง = ร้าน, ฟ้า = ทางเดิน (เห็นคนเดียว)",
        function() return settings.showRoute end,
        function(v)
            settings.showRoute = v
            drawRoute()
        end, "showRoute")
    local clearRouteButton = proxyButton(routeSection, "ล้างเส้นทาง + จุดตกปลา", "ย้ายไปตกจุดใหม่ (จุดร้านยังอยู่)")
    local clearAllButton = proxyButton(routeSection, "ล้างทั้งหมด (รวมจุดร้าน)")

    ---- หน้า ความปลอดภัย
    local afkSection = Tabs.safe:AddSection("กันโดนเตะ")
    addToggle(afkSection, "เข้าเกมใหม่เมื่อหลุด", "โดนเตะ/เน็ตหลุด จะเข้าเกมใหม่ แล้วโหลดตั้งค่าล่าสุดและตกต่อเอง",
        function() return settings.autoRejoin end,
        function(v) settings.autoRejoin = v end, "autoRejoin")
    addToggle(afkSection, "กันโดนเตะ AFK", nil,
        function() return settings.antiAfk end,
        function(v) settings.antiAfk = v end, "antiAfk")

    local breakSection = Tabs.safe:AddSection("พักเป็นระยะ (สุ่มให้ไม่เท่ากัน)")
    addToggle(breakSection, "พักเป็นระยะ", nil,
        function() return settings.breakOn end,
        function(v) settings.breakOn = v end, "breakOn")
    addNumber(breakSection, "พักทุก (ตัว)", settings.breakEvery,
        function(n) settings.breakEvery = math.max(1, math.floor(n)) end, "breakEvery")
    addNumber(breakSection, "พักนาน (วินาที)", settings.breakSeconds, function(n) settings.breakSeconds = n end, "breakSeconds")

    local nearbySection = Tabs.safe:AddSection("มีผู้เล่นอื่นเข้าใกล้")
    addToggle(nearbySection, "พักเมื่อมีคนใกล้", "ไม่มีใครอยู่ใกล้ครบ 5 วิ จะตกต่อเอง",
        function() return settings.nearbyOn end,
        function(v) settings.nearbyOn = v end, "nearbyOn")
    addNumber(nearbySection, "ระยะ (studs)", settings.nearbyRange, function(n) settings.nearbyRange = n end, "nearbyRange")

    ---- หน้า ตัวละคร
    local moveSection = Tabs.char:AddSection("ความเร็ว / กระโดด")
    addToggle(moveSection, "วิ่งเร็ว", nil,
        function() return settings.speedOn end,
        function(v) settings.speedOn = v end, "speedOn")
    addNumber(moveSection, "ความเร็ววิ่ง", settings.speed, function(n) settings.speed = n end, "speed")
    addToggle(moveSection, "กระโดดสูง", nil,
        function() return settings.jumpOn end,
        function(v) settings.jumpOn = v end, "jumpOn")
    addNumber(moveSection, "แรงกระโดด", settings.jump, function(n) settings.jump = n end, "jump")

    ---- ฟรีแคม
    -- ปุ่มข้างเมาส์ (Mouse4/Mouse5) Roblox ไม่ส่งมาให้สคริปต์ เลยใช้ปุ่มคีย์บอร์ดหรือปุ่มกลางเมาส์แทน
    local FREECAM_KEYS = { "P", "V", "C", "X", "Z", "G", "B", "N", "M", "ปุ่มกลางเมาส์" }
    uiHooks.freecamToggled = function() end -- กำหนดจริงในส่วนฟรีแคม
    local freecamSection = Tabs.char:AddSection("ฟรีแคม")
    local freecamToggle = freecamSection:AddToggle("AFFreecam", {
        Title = "ฟรีแคม",
        Description = "WASD เลื่อนกล้อง • Q/E ลง/ขึ้น • คลิกขวาค้างหมุนกล้อง • Shift เร็วขึ้น (ตัวละครอยู่ที่เดิม ตกปลาต่อได้)",
        Default = false,
    })
    freecamToggle:OnChanged(function(v)
        uiHooks.freecamToggled(v)
    end)
    local freecamKeyName = "P"
    freecamSection:AddDropdown("AFFreecamKey", {
        Title = "ปุ่มเปิด/ปิดฟรีแคม",
        Values = FREECAM_KEYS,
        Default = 1,
    }):OnChanged(function(v)
        freecamKeyName = v
    end)
    local freecamSpeed = 1
    freecamSection:AddInput("AFFreecamSpeed", {
        Title = "ความเร็วกล้อง",
        Default = "1",
        Numeric = true,
        Finished = true,
        Callback = function(text)
            local n = tonumber(text)
            if n and n > 0 then freecamSpeed = n end
        end,
    })

    ---- หน้า แจ้งเตือน
    local rareSection = Tabs.alert:AddSection("ปลาหายาก / ปลาชนิดใหม่")
    addToggle(rareSection, "เตือนเมื่อได้ปลาหายาก", "ระดับที่ไม่ใช่ \"ทั่วไป\" หรือปลาชนิดใหม่",
        function() return settings.rareAlert end,
        function(v) settings.rareAlert = v end, "rareAlert")
    addToggle(rareSection, "หยุดเมื่อได้ปลาหายาก", nil,
        function() return settings.rareStop end,
        function(v) settings.rareStop = v end, "rareStop")

    ---- หน้า บันทึกตั้งค่า
    local profileSection = Tabs.profile:AddSection("ชุดตั้งค่า (เก็บลงไฟล์ ออกเกมแล้วไม่หาย)")
    local PROFILE_COUNT = 3
    local profileNames = {}
    for i = 1, PROFILE_COUNT do
        profileNames[i] = "ชุดที่ " .. i
    end
    local selectedProfile = 1
    uiHooks.profileSelected = function() end -- กำหนดจริงในส่วนโปรไฟล์
    profileSection:AddDropdown("AFProfile", {
        Title = "เลือกชุด",
        Values = profileNames,
        Default = 1,
    }):OnChanged(function(v)
        selectedProfile = tonumber(tostring(v):match("%d+")) or 1
        uiHooks.profileSelected(selectedProfile)
    end)
    local profileLabel = proxyLabel(profileSection, "ข้อมูลชุดนี้", "-")
    local profileSaveButton = proxyButton(profileSection, "บันทึกตั้งค่าตอนนี้ลงชุดนี้",
        "เก็บสวิตช์ ตัวเลข วิธีเดิน และจุด 1-5 ทั้งหมด (ไม่รวมการเปิดตกปลา)")
    local profileLoadButton = proxyButton(profileSection, "ใช้ชุดนี้", "โหลดค่าที่บันทึกไว้มาใช้ทันที")
    local profileDeleteButton = proxyButton(profileSection, "ล้างข้อมูลชุดนี้")

    Window:SelectTab(1)

    -- เก็บ connection ไว้ตัดทิ้งตอนรันสคริปต์ซ้ำ (ไม่งั้นปุ่มลัดของตัวเก่าจะยังทำงาน)
    local connections = {}
    ScreenGui.AncestryChanged:Connect(function()
        if not ScreenGui.Parent then
            for _, c in ipairs(connections) do
                c:Disconnect()
            end
        end
    end)

    ---------------------------------------------------------------- ระบบพักตกปลาชั่วคราว
    -- ใช้ร่วมกันหลายอย่าง (ขายปลา / พักเป็นระยะ / มีคนใกล้) ตกปลาจะกลับมาเองเมื่อทุกเหตุผลหมดไป
    -- กดเปิด/ปิดเองเมื่อไหร่ ถือว่าผู้เล่นสั่งเอง ล้างการพักทั้งหมด
    local pause = { reasons = {}, resume = false, autoResuming = false }

    local function pauseFishing(reason)
        if pause.reasons[reason] then return end
        pause.reasons[reason] = true
        if isAutoFishing then
            pause.resume = true
            setEnabled(false)
        end
    end

    local function resumeFishing(reason)
        if not pause.reasons[reason] then return end
        pause.reasons[reason] = nil
        if next(pause.reasons) == nil and pause.resume then
            pause.resume = false
            if not isAutoFishing then
                pause.autoResuming = true
                setEnabled(true)
            end
        end
    end

    local function isPaused(reason)
        return pause.reasons[reason] ~= nil
    end

    local function clearPauses()
        pause.reasons = {}
        pause.resume = false
    end

    -- กดปุ่มเปิดตกปลาในหน้าต่างเอง = ผู้เล่นสั่งเอง ล้างการพักทั้งหมด
    uiHooks.fishingToggled = function(v)
        clearPauses()
        setEnabled(v)
    end
    -- ปุ่มในหน้าต่างแสดง "เปิด" ระหว่างพักด้วย (เดี๋ยวตกต่อเอง)
    uiHooks.wantFishing = function()
        return isAutoFishing or pause.resume
    end

    ---------------------------------------------------------------- 3) ปุ่มลัด
    connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end -- กำลังพิมพ์แชท/ช่องตัวเลขอยู่
        if input.KeyCode == TOGGLE_KEY then
            clearPauses()
            setEnabled(not isAutoFishing)
        end -- ปุ่ม H (ซ่อนหน้าต่าง) Fluent จัดการเอง
    end)

    ---------------------------------------------------------------- 1) กัน AFK
    local VirtualUser = game:GetService("VirtualUser")
    connections[#connections + 1] = LocalPlayer.Idled:Connect(function()
        if settings.antiAfk then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)

    ---------------------------------------------------------------- 6) วิ่งเร็ว / กระโดดสูง
    local defaults = {} -- ค่าเดิมของเกม เอาไว้คืนตอนปิด
    task.spawn(function()
        while ScreenGui.Parent do
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local active = settings.speedOn or settings.jumpOn or defaults.speedApplied or defaults.jumpApplied
            if hum and active then
                if defaults.hum ~= hum then
                    defaults = {
                        hum = hum,
                        speed = hum.WalkSpeed,
                        jumpPower = hum.JumpPower,
                        jumpHeight = hum.JumpHeight,
                    }
                end
                if settings.speedOn then
                    hum.WalkSpeed = settings.speed
                elseif defaults.speedApplied then
                    hum.WalkSpeed = defaults.speed
                end
                defaults.speedApplied = settings.speedOn

                if settings.jumpOn then
                    if hum.UseJumpPower then
                        hum.JumpPower = settings.jump
                    else
                        hum.JumpHeight = settings.jump ^ 2 / (2 * workspace.Gravity)
                    end
                elseif defaults.jumpApplied then
                    hum.JumpPower = defaults.jumpPower
                    hum.JumpHeight = defaults.jumpHeight
                end
                defaults.jumpApplied = settings.jumpOn
            end
            task.wait(0.5)
        end
    end)

    ---------------------------------------------------------------- 2) นับสถิติ + 4) ตั้งเวลาหยุด
    -- เก็บสถิติไว้ใน getgenv รันสคริปต์ใหม่แล้วตัวเลขไม่หาย (หายเมื่อออกเกม หรือกดรีเซ็ต)
    local stats = env.AutoFishStats or { fish = 0, coins = 0, newSpecies = 0, runTime = 0 }
    env.AutoFishStats = stats
    local bag = { count = nil, max = nil } -- จำนวนปลาในกระเป๋า (อัปเดตจากส่วนขายปลา)
    local session = { fish = 0, time = 0 }
    local wasOn = false
    local lastSeenCatch = env.AutoFishLastCatch or 0
    local lastPopupText

    local isRarity = {}
    for _, r in ipairs(RARITIES) do
        isRarity[r] = true
    end

    local statsPopupGui -- จำ ScreenGui ของหน้าต่างโชว์ปลาไว้ ไม่ต้องค้นทั้ง PlayerGui
    local function findPopupLabels()
        local sell, isNew
        local root = (statsPopupGui and statsPopupGui.Parent) and statsPopupGui or LocalPlayer.PlayerGui
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextLabel") and isShown(d) then
                if d.Text:find("ขายได้", 1, true) and d.Text:find("เหรียญ", 1, true) then
                    sell = d
                elseif d.Text:find("ชนิดใหม่", 1, true) then
                    isNew = true
                end
            end
        end
        -- หาป้ายระดับความหายากในหน้าต่างเดียวกัน
        local rarity
        if sell then
            statsPopupGui = sell:FindFirstAncestorWhichIsA("ScreenGui")
            local root = sell
            while root.Parent and not root.Parent:IsA("ScreenGui") do
                root = root.Parent
            end
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local t = d.Text:gsub("^%s+", ""):gsub("%s+$", "")
                    if isRarity[t] then
                        rarity = t
                        break
                    end
                end
            end
        end
        return sell, isNew, rarity
    end

    local function notify(title, text)
        pcall(function()
            Fluent:Notify({ Title = title, Content = text, Duration = 10 })
        end)
    end

    local breakState = { sinceBreak = 0, nextAt = nil, resumeAt = 0 }

    -- นับปลาจากหน้าต่างโชว์ปลา (ได้ปลาจริงเท่านั้น)
    local function countCatch(sell, isNew, rarity)
        stats.fish += 1
        session.fish += 1
        breakState.sinceBreak += 1
        if rarity and rarity ~= "ทั่วไป" then
            stats.rare = (stats.rare or 0) + 1
            if settings.rareAlert then
                notify("ได้ปลาหายาก!", "ระดับ: " .. rarity)
            end
            if settings.rareStop and isAutoFishing then
                clearPauses()
                setEnabled(false)
                setStatus("หยุดแล้ว: ได้ปลาระดับ " .. rarity)
            end
        elseif isNew and settings.rareAlert then
            notify("ปลาชนิดใหม่!", "เพิ่มเข้าสมุดสะสมแล้ว")
        end
        local coins = sell.Text:match("ขายได้%s*([%d,]+)")
        if coins then
            stats.coins += tonumber((coins:gsub(",", ""))) or 0
        end
        if isNew then
            stats.newSpecies += 1
        end
    end

    local function formatTime(sec)
        sec = math.floor(sec)
        return ("%02d:%02d:%02d"):format(sec // 3600, sec % 3600 // 60, sec % 60)
    end

    local function refreshStats()
        local perHour = stats.runTime > 60 and math.floor(stats.coins / stats.runTime * 3600) or 0
        statsLabel.Text = ("ปลา: %d ตัว   ชนิดใหม่: %d   หายาก: %d\nเหรียญ: %d   (%d / ชม.)\nเวลาที่เปิด: %s\nในกระเป๋า: %s / %s ตัว")
            :format(stats.fish, stats.newSpecies, stats.rare or 0, stats.coins, perHour, formatTime(stats.runTime),
                tostring(bag.count or "-"), tostring(bag.max or "-"))
    end

    resetButton.MouseButton1Click:Connect(function()
        stats = { fish = 0, coins = 0, newSpecies = 0, runTime = 0 }
        env.AutoFishStats = stats
        refreshStats()
    end)

    local hooked = env.AutoFishCatchHooked
    local checkingCatch = false
    local lastTick = os.clock()

    task.spawn(function()
        while ScreenGui.Parent do
            local now = os.clock()
            local dt = now - lastTick
            lastTick = now

            -- เริ่มรอบใหม่ทุกครั้งที่กด ON
            -- (ไม่นับตอนสคริปต์กลับมาตกเองหลังพัก/ขายปลา)
            if isAutoFishing and not wasOn then
                if pause.autoResuming then
                    pause.autoResuming = false
                else
                    session = { fish = 0, time = 0 }
                    breakState.sinceBreak = 0
                    breakState.nextAt = nil
                end
            end
            wasOn = isAutoFishing

            if isAutoFishing then
                stats.runTime += dt
                session.time += dt
            end

            -- ตรวจว่าได้ปลา
            if hooked then
                -- มีสัญญาณ "Reel", true -> รอดูหน้าต่างโชว์ปลาภายใน 3 วิ แล้วค่อยนับ
                if env.AutoFishLastCatch > lastSeenCatch and not checkingCatch then
                    lastSeenCatch = env.AutoFishLastCatch
                    checkingCatch = true
                    task.spawn(function()
                        local started = os.clock()
                        while os.clock() - started < 3 do
                            local sell, isNew, rarity = findPopupLabels()
                            if sell then
                                countCatch(sell, isNew, rarity)
                                break
                            end
                            task.wait(0.2)
                        end
                        checkingCatch = false
                    end)
                end
            elseif isAutoFishing then
                -- executor ไม่มี hook: ดูหน้าต่างโชว์ปลาที่เพิ่งเด้งขึ้น
                local sell, isNew, rarity = findPopupLabels()
                local text = sell and sell.Text
                if sell and text ~= lastPopupText then
                    countCatch(sell, isNew, rarity)
                end
                lastPopupText = text
            end

            -- 4) ครบเงื่อนไขแล้วหยุดเอง
            if isAutoFishing then
                if settings.stopFish > 0 and session.fish >= settings.stopFish then
                    clearPauses()
                    setEnabled(false)
                    setStatus(("หยุดแล้ว: ได้ปลาครบ %d ตัว"):format(settings.stopFish))
                elseif settings.stopMinutes > 0 and session.time >= settings.stopMinutes * 60 then
                    clearPauses()
                    setEnabled(false)
                    setStatus(("หยุดแล้ว: ครบ %g นาที"):format(settings.stopMinutes))
                end
            end

            -- 8) พักเป็นระยะ (สุ่มจำนวนตัวและเวลาพัก ไม่ให้เป็นจังหวะเดิมทุกครั้ง)
            if not breakState.nextAt then
                breakState.nextAt = math.max(1, math.floor(settings.breakEvery * (0.7 + math.random() * 0.6)))
            end
            if isPaused("break") then
                if not settings.breakOn or now >= breakState.resumeAt then
                    resumeFishing("break")
                else
                    setStatus(("พักสั้นๆ อีก %d วิ"):format(math.ceil(breakState.resumeAt - now)))
                end
            elseif settings.breakOn and isAutoFishing and breakState.sinceBreak >= breakState.nextAt then
                breakState.sinceBreak = 0
                breakState.nextAt = nil
                breakState.resumeAt = now + settings.breakSeconds * (0.6 + math.random() * 0.8)
                pauseFishing("break")
            end

            -- 9) มีผู้เล่นอื่นเข้ามาใกล้ -> พัก จนไม่มีใครอยู่ใกล้ครบ 5 วิ
            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local nearest
            if settings.nearbyOn and myRoot then
                for _, plr in ipairs(Players:GetPlayers()) do
                    local root = plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        local d = (root.Position - myRoot.Position).Magnitude
                        if not nearest or d < nearest then
                            nearest = d
                        end
                    end
                end
            end
            if nearest and nearest <= settings.nearbyRange then
                breakState.lastNearby = now
                if isAutoFishing then
                    pauseFishing("nearby")
                end
                if isPaused("nearby") then
                    setStatus(("พัก: มีคนอยู่ใกล้ (%d studs)"):format(math.floor(nearest)))
                end
            elseif isPaused("nearby") and (not settings.nearbyOn or now - (breakState.lastNearby or 0) > 5) then
                resumeFishing("nearby")
            end

            refreshStats()
            refreshTitle()
            task.wait(1)
        end
    end)

    ---------------------------------------------------------------- 7) ขายปลาอัตโนมัติ
    -- Inventory.Request:InvokeServer("Get") -> { Items = { {Id, Key, At, Weight?}, ... }, MaxFish, Coins }
    -- ของที่มี Weight คือปลา (คันเบ็ด/ป้าย/โหล ไม่มี Weight จะไม่ถูกขาย)
    -- ขายด้วย FishShop.Request:InvokeServer("SellIds", { id, id, ... }) แบบเดียวกับกดขายในร้าน
    local remotesFolder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    local selling = false

    local function getFishIds()
        local ok, inv = pcall(function()
            return remotesFolder.Inventory.Request:InvokeServer("Get")
        end)
        if not ok or typeof(inv) ~= "table" or typeof(inv.Items) ~= "table" then
            return nil
        end
        local ids = {}
        for _, item in ipairs(inv.Items) do
            if typeof(item) == "table" and item.Weight ~= nil and item.Id ~= nil then
                table.insert(ids, item.Id)
            end
        end
        bag.count, bag.max = #ids, inv.MaxFish
        return ids, inv.MaxFish
    end

    -- เซิร์ฟเวอร์ให้ขายได้เฉพาะตอนยืนใกล้ร้าน ("ต้องอยู่ใกล้ร้านก่อนนะ")
    -- ไปยืนที่ร้านแล้วกด "บันทึกจุดร้าน" ครั้งเดียว ตอนขายสคริปต์จะพักตกปลา วาร์ปไปขาย แล้ววาร์ปกลับจุดเดิม
    local SHOP_RANGE = 12 -- อยู่ห่างจุดร้านไม่เกินกี่ studs ถือว่าอยู่ที่ร้านแล้ว ไม่ต้องวาร์ป

    -- ===== ช่องบันทึก (จุด 1-5) =====
    -- ค่าที่ใช้งานอยู่คือ env.AutoFishRoute / AutoFishFishSpot / AutoFishShopCFrame
    -- เปลี่ยนช่อง = เก็บค่าปัจจุบันลงช่องเดิม แล้วโหลดค่าของช่องใหม่มาใช้
    env.AutoFishSlots = env.AutoFishSlots or {}
    env.AutoFishSlot = env.AutoFishSlot or 1

    local function slotInfo()
        local parts = {}
        table.insert(parts, env.AutoFishFishSpot and "✓ จุดตกปลา" or "✗ จุดตกปลา")
        table.insert(parts, env.AutoFishRoute and ("✓ เส้นทาง %d จุด"):format(#env.AutoFishRoute) or "✗ เส้นทาง")
        table.insert(parts, env.AutoFishShopCFrame and "✓ ร้าน" or "✗ ร้าน")
        return ("จุด %d:  %s"):format(env.AutoFishSlot, table.concat(parts, "   "))
    end

    -- เก็บค่าที่ใช้อยู่ลงช่องปัจจุบัน (เรียกทุกครั้งที่บันทึก/ล้าง)
    local function saveSlot()
        env.AutoFishSlots[env.AutoFishSlot] = {
            route = env.AutoFishRoute,
            spot = env.AutoFishFishSpot,
            shop = env.AutoFishShopCFrame,
        }
        slotLabel.Text = slotInfo()
    end

    local function loadSlot(i)
        local data = env.AutoFishSlots[i] or {}
        env.AutoFishSlot = i
        env.AutoFishRoute = data.route
        env.AutoFishFishSpot = data.spot
        env.AutoFishShopCFrame = data.shop
        slotLabel.Text = slotInfo()
    end

    local function refreshShopButton()
        shopButton.Text = env.AutoFishShopCFrame and "บันทึกจุดร้านแล้ว (กดเพื่อบันทึกใหม่)"
            or "บันทึกจุดร้าน (ยืนที่ร้านแล้วกด)"
        saveSlot()
    end
    refreshShopButton()

    shopButton.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            env.AutoFishShopCFrame = hrp.CFrame
            bagLabel.Text = "บันทึกจุดร้านแล้ว"
            refreshShopButton()
            drawRoute()
        end
    end)

    local function getRoot()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- ===== การเดิน =====
    -- 1) ถ้ามีเส้นทางที่บันทึกไว้ เดินตามเส้นทางนั้น (แม่นสุด ไม่ตกน้ำ)
    -- 2) ไม่มี: ให้ระบบหาทางของ Roblox หาทางเดินที่ไม่ลงน้ำ
    -- เดินแล้วลงไปว่ายน้ำ / ไม่ขยับ / หาทางไม่เจอ = ถือว่าเดินไม่สำเร็จ
    local PathfindingService = game:GetService("PathfindingService")
    local WALK_TIMEOUT = 60 -- เดินนานสุดกี่วินาทีต่อเที่ยว

    local function flatDist(a, b)
        return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
    end

    -- เดินผ่านจุดทีละจุด points = { Vector3 หรือ {Position, Action} }
    local function walkPoints(points, timeout)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) then return false end

        local deadline = os.clock() + timeout
        for _, p in ipairs(points) do
            local pos = typeof(p) == "Vector3" and p or p.Position
            if typeof(p) ~= "Vector3" and p.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
            local started = os.clock()
            local lastMove = 0
            local lastPos, lastProgress = hrp.Position, os.clock()
            while flatDist(hrp.Position, pos) > 2.5 do
                if os.clock() > deadline then return false end
                if hum:GetState() == Enum.HumanoidStateType.Swimming then
                    return false, "ตกน้ำ"
                end
                -- ไม่ขยับเลย 3 วิ = ติด
                if (hrp.Position - lastPos).Magnitude > 1 then
                    lastPos, lastProgress = hrp.Position, os.clock()
                elseif os.clock() - lastProgress > 3 then
                    return false, "เดินติด"
                end
                if os.clock() - started > 10 then
                    return false, "เดินติด"
                end
                -- ขั้นสูงกว่าเดิม -> กระโดด
                if pos.Y - hrp.Position.Y > 2.5 then
                    hum.Jump = true
                end
                if os.clock() - lastMove > 1 then
                    hum:MoveTo(pos)
                    lastMove = os.clock()
                end
                task.wait(0.1)
            end
        end
        return true
    end

    local function pathTo(target)
        local hrp = getRoot()
        if not hrp then return nil end
        local path = PathfindingService:CreatePath({
            AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
            Costs = { Water = math.huge }, -- ห้ามเดินลงน้ำ
        })
        local ok = pcall(function()
            path:ComputeAsync(hrp.Position, target)
        end)
        if ok and path.Status == Enum.PathStatus.Success then
            return path:GetWaypoints()
        end
        return nil
    end

    -- เดินไปร้าน (toShop = true) หรือเดินกลับจุดตกปลา
    local function walkTrip(target, toShop)
        local route = env.AutoFishRoute
        local hrp = getRoot()
        if not hrp then return false end
        if route and #route >= 2 then
            local startPoint = toShop and route[1] or route[#route]
            if flatDist(hrp.Position, startPoint) <= 15 then
                local points = {}
                if toShop then
                    points = route
                else
                    for i = #route, 1, -1 do
                        table.insert(points, route[i])
                    end
                end
                local ok, why = walkPoints(points, WALK_TIMEOUT)
                if not ok then return false, why end
                return walkPoints({ target }, 10)
            end
        end
        local waypoints = pathTo(target)
        if not waypoints then
            return false, "หาทางเดินไม่เจอ"
        end
        return walkPoints(waypoints, WALK_TIMEOUT)
    end

    -- ปุ่มบันทึกเส้นทาง
    local recording = false
    local function refreshRouteButton()
        if recording then
            routeButton.Text = "กำลังบันทึก... เดินไปร้านแล้วกดหยุด"
            routeButton.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
        else
            local route = env.AutoFishRoute
            routeButton.Text = route and ("มีเส้นทางแล้ว %d จุด (กดบันทึกใหม่)"):format(#route)
                or "บันทึกเส้นทางเดิน (เริ่มที่จุดตกปลา)"
            routeButton.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
            saveSlot()
        end
    end
    refreshRouteButton()

    routeButton.MouseButton1Click:Connect(function()
        if recording then
            -- หยุดบันทึก: จุดสุดท้ายคือร้าน บันทึกจุดร้านไปด้วยเลย
            recording = false
            local hrp = getRoot()
            if hrp then
                local route = env.AutoFishRecording or {}
                table.insert(route, hrp.Position)
                env.AutoFishRoute = #route >= 2 and route or nil
                env.AutoFishShopCFrame = hrp.CFrame
                refreshShopButton()
                bagLabel.Text = "บันทึกเส้นทาง + จุดร้านแล้ว"
            end
            env.AutoFishRecording = nil
            refreshRouteButton()
            drawRoute()
            return
        end
        recording = true
        env.AutoFishRecording = {}
        local startRoot = getRoot()
        if startRoot then
            env.AutoFishFishSpot = startRoot.CFrame -- จุดตกปลา + ทิศที่หันหน้า
        end
        refreshRouteButton()
        task.spawn(function()
            local route = env.AutoFishRecording
            while recording and ScreenGui.Parent do
                local hrp = getRoot()
                if hrp then
                    local last = route[#route]
                    if not last or (hrp.Position - last).Magnitude >= 3 then
                        table.insert(route, hrp.Position)
                    end
                end
                task.wait(0.15)
            end
        end)
    end)

    -- ===== แสดงเส้นทางในโลก (เห็นแค่เรา) =====
    -- เขียว = จุดตกปลา, เหลือง = จุดร้าน, ฟ้า = ทางที่บันทึกไว้
    drawRoute = function()
        local old = workspace:FindFirstChild("AutoFishRouteMarkers")
        if old then old:Destroy() end
        if not settings.showRoute then return end

        local folder = Instance.new("Folder")
        folder.Name = "AutoFishRouteMarkers"
        local function marker(pos, size, color, shape)
            local part = Instance.new("Part")
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.Material = Enum.Material.Neon
            part.Color = color
            part.Transparency = 0.3
            part.Shape = shape or Enum.PartType.Ball
            part.Size = size
            part.Position = pos
            part.Parent = folder
            return part
        end
        local route = env.AutoFishRoute
        if route then
            for i = 2, #route - 1, 2 do -- เว้นทีละจุด ไม่ให้แน่นเกิน
                marker(route[i], Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(80, 180, 255))
            end
        end
        if env.AutoFishFishSpot then
            marker(env.AutoFishFishSpot.Position + Vector3.new(0, 4, 0), Vector3.new(1.5, 1.5, 1.5),
                Color3.fromRGB(60, 220, 90))
        end
        if env.AutoFishShopCFrame then
            marker(env.AutoFishShopCFrame.Position + Vector3.new(0, 4, 0), Vector3.new(1.5, 1.5, 1.5),
                Color3.fromRGB(255, 210, 60))
        end
        folder.Parent = workspace
    end
    drawRoute()
    ScreenGui.AncestryChanged:Connect(function()
        if not ScreenGui.Parent then
            local old = workspace:FindFirstChild("AutoFishRouteMarkers")
            if old then old:Destroy() end
        end
    end)

    -- ===== ปุ่มเดินเอง =====
    local walkingByHand = false
    local function manualWalk(toShop)
        if walkingByHand or selling then return end
        local spot = toShop and env.AutoFishShopCFrame or env.AutoFishFishSpot
        if not spot then
            bagLabel.Text = toShop and "ยังไม่ได้บันทึกจุดร้าน" or "ยังไม่ได้บันทึกจุดตกปลา (บันทึกเส้นทางก่อน)"
            return
        end
        walkingByHand = true
        pauseFishing("walk")
        bagLabel.Text = toShop and "เดินไปร้าน..." or "เดินกลับจุดตกปลา..."
        local ok, why = walkTrip(spot.Position, toShop)
        local hrp = getRoot()
        if hrp then
            if ok and flatDist(hrp.Position, spot.Position) <= 3 then
                hrp.CFrame = CFrame.new(hrp.Position) * spot.Rotation -- หันหน้าทางเดิม
                bagLabel.Text = toShop and "ถึงร้านแล้ว" or "ถึงจุดตกปลาแล้ว"
            elseif settings.walkFallbackWarp then
                hrp.CFrame = spot
                bagLabel.Text = ("%s วาร์ปไปแทนแล้ว"):format(why or "เดินไม่ถึง")
            else
                bagLabel.Text = ("เดินไม่ถึง (%s)"):format(why or "?")
            end
        end
        resumeFishing("walk")
        walkingByHand = false
    end
    goBackButton.MouseButton1Click:Connect(function()
        task.spawn(manualWalk, false)
    end)
    goShopButton.MouseButton1Click:Connect(function()
        task.spawn(manualWalk, true)
    end)

    -- ล้างเส้นทาง: ย้ายไปตกจุดใหม่ แล้วบันทึกเส้นทางใหม่จากจุดนั้น
    local function clearRoute(includeShop)
        recording = false
        env.AutoFishRecording = nil
        env.AutoFishRoute = nil
        env.AutoFishFishSpot = nil
        if includeShop then
            env.AutoFishShopCFrame = nil
        end
        refreshRouteButton()
        refreshShopButton()
        drawRoute()
        bagLabel.Text = includeShop and "ล้างเส้นทาง จุดตกปลา และจุดร้านแล้ว"
            or "ล้างเส้นทางและจุดตกปลาแล้ว (จุดร้านยังอยู่)"
    end
    clearRouteButton.MouseButton1Click:Connect(function()
        clearRoute(false)
    end)
    -- เปลี่ยนช่อง
    uiHooks.slotChanged = function(i)
        if i == env.AutoFishSlot then return end
        recording = false -- กำลังบันทึกอยู่ = ยกเลิก
        env.AutoFishRecording = nil
        saveSlot()
        loadSlot(i)
        refreshRouteButton()
        refreshShopButton()
        drawRoute()
        bagLabel.Text = ("ใช้จุด %d แล้ว"):format(i)
    end

    warpSpotButton.MouseButton1Click:Connect(function()
        local spot = env.AutoFishFishSpot
        local hrp = getRoot()
        if not spot then
            bagLabel.Text = ("จุด %d ยังไม่ได้บันทึกจุดตกปลา"):format(env.AutoFishSlot)
        elseif hrp then
            hrp.CFrame = spot
            bagLabel.Text = ("วาร์ปไปจุดตกปลาของจุด %d แล้ว"):format(env.AutoFishSlot)
        end
    end)

    clearAllButton.MouseButton1Click:Connect(function()
        clearRoute(true)
    end)

    local function sellRequest(ids)
        local before = LocalPlayer:GetAttribute("Coins")
        local ok, res = pcall(function()
            return remotesFolder.FishShop.Request:InvokeServer("SellIds", ids)
        end)
        task.wait(0.5)
        local after = LocalPlayer:GetAttribute("Coins")
        if ok and not (typeof(res) == "table" and res.Ok == false) then
            local gained = (typeof(before) == "number" and typeof(after) == "number") and (after - before) or nil
            bagLabel.Text = gained and ("ขายแล้ว %d ตัว ได้ %d เหรียญ"):format(#ids, gained)
                or ("ขายแล้ว %d ตัว"):format(#ids)
            return true
        end
        bagLabel.Text = "ขายไม่สำเร็จ: " .. tostring(typeof(res) == "table" and (res.Error or res.Message) or res)
        return false
    end

    local function sellAll()
        if selling then return end
        selling = true
        local ids = getFishIds()
        if not ids then
            bagLabel.Text = "ขายไม่ได้: อ่านกระเป๋าไม่ได้"
        elseif #ids == 0 then
            bagLabel.Text = "ไม่มีปลาให้ขาย"
        else
            local shop = env.AutoFishShopCFrame
            local hrp = getRoot()
            if shop and hrp and (hrp.Position - shop.Position).Magnitude > SHOP_RANGE then
                -- พักตกปลา -> ไปร้าน (เดิน/วาร์ป) -> ขาย -> กลับจุดเดิม -> ตกปลาต่อ
                local hadFishing = isAutoFishing
                pauseFishing("sell")
                if hadFishing then
                    task.wait(1)
                end
                hrp = getRoot()
                if hrp then
                    local back = hrp.CFrame
                    if settings.sellTravel == "warp" then
                        bagLabel.Text = "วาร์ปไปขายที่ร้าน..."
                        hrp.CFrame = shop
                        task.wait(0.8)
                        sellRequest(ids)
                        hrp = getRoot()
                        if hrp and settings.returnMode ~= "stay" then
                            if settings.returnMode == "walk" then
                                walkTrip(back.Position, false)
                                hrp = getRoot()
                            end
                            if hrp then
                                if flatDist(hrp.Position, back.Position) <= 3 then
                                    hrp.CFrame = CFrame.new(hrp.Position) * back.Rotation
                                else
                                    hrp.CFrame = back -- กลับจุดเดิม หันหน้าเข้าน้ำเหมือนเดิม
                                end
                            end
                        end
                        task.wait(0.8)
                    else
                        bagLabel.Text = "เดินไปขายที่ร้าน..."
                        local reached, why = walkTrip(shop.Position, true)
                        local warped = false
                        if not reached and settings.walkFallbackWarp then
                            -- เดินติด/ตกน้ำ: วาร์ปไปร้านแทน
                            bagLabel.Text = ("%s วาร์ปไปร้านแทน"):format(why or "เดินไม่ถึง")
                            hrp = getRoot()
                            if hrp then
                                hrp.CFrame = shop
                                task.wait(0.8)
                                reached, warped = true, true
                            end
                        end
                        if reached then
                            task.wait(0.5)
                            sellRequest(ids)
                        else
                            bagLabel.Text = ("เดินไปร้านไม่ถึง (%s)"):format(why or "?")
                        end

                        -- กลับจุดตกปลา: เดินกลับ ถ้าไม่ถึง (หรือขาไปวาร์ปมา) วาร์ปกลับจุดเดิมเป๊ะ
                        local returned = false
                        if not warped and settings.returnMode == "walk" then
                            returned = walkTrip(back.Position, false)
                        end
                        hrp = getRoot()
                        if settings.returnMode == "warp" and hrp then
                            hrp.CFrame = back
                        elseif settings.returnMode == "walk" and hrp then
                            if returned and flatDist(hrp.Position, back.Position) <= 3 then
                                -- หันหน้ากลับทางเดิม (หมุนตัวอยู่กับที่ ไม่ได้วาร์ป)
                                hrp.CFrame = CFrame.new(hrp.Position) * back.Rotation
                            elseif settings.walkFallbackWarp or warped then
                                hrp.CFrame = back
                            end
                        end
                        task.wait(0.5)
                    end
                end
                if settings.returnMode == "stay" then
                    -- ไม่กลับจุดตกปลา = ไม่ตกต่อ (ยืนที่ร้านเหวี่ยงเบ็ดไม่ลงน้ำ)
                    clearPauses()
                    setStatus("ขายเสร็จ อยู่ที่ร้าน (หยุดตกปลา)")
                else
                    resumeFishing("sell")
                end
            elseif not sellRequest(ids) and not shop then
                bagLabel.Text = "ต้องอยู่ใกล้ร้าน: ไปยืนที่ร้านแล้วกด บันทึกจุดร้าน"
            end
        end
        selling = false
    end

    sellNowButton.MouseButton1Click:Connect(function()
        task.spawn(sellAll)
    end)

    -- เช็คกระเป๋าทุก 10 วิ ถ้าปลาครบจำนวนที่ตั้งไว้ ขายทั้งหมดทีเดียว
    task.spawn(function()
        while ScreenGui.Parent do
            -- ถามเซิร์ฟเวอร์เฉพาะตอนตกปลาอยู่หรือเปิดขายอัตโนมัติ (ไม่ใช้ก็ไม่ต้องถาม)
            if not selling and (isAutoFishing or settings.autoSell) then
                local ids, maxFish = getFishIds()
                if ids then
                    -- ยังไม่บันทึกจุดร้าน = ขายไม่ได้ (เซิร์ฟเวอร์ให้ขายเฉพาะใกล้ร้าน) ไม่ต้องลองให้เสียเวลา
                    if settings.autoSell and #ids >= settings.sellAt and env.AutoFishShopCFrame then
                        sellAll()
                    elseif settings.autoSell and #ids >= settings.sellAt then
                        bagLabel.Text = "ครบแล้วแต่ยังไม่บันทึกจุดร้าน"
                    end
                end
            end
            task.wait(10)
        end
    end)

    ---------------------------------------------------------------- 12) ถือเบ็ดให้เอง
    -- ตกปลาอยู่ แต่ในมือไม่มี Tool -> หยิบ Tool ที่ชื่อมีคำว่า Rod / เบ็ด จากกระเป๋า
    local function isRod(tool)
        local name = tool.Name:lower()
        return name:find("rod", 1, true) ~= nil or tool.Name:find("เบ็ด", 1, true) ~= nil
    end

    task.spawn(function()
        while ScreenGui.Parent do
            if settings.autoEquip and isAutoFishing then
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
                if hum and backpack and not char:FindFirstChildOfClass("Tool") then
                    for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") and isRod(tool) then
                            hum:EquipTool(tool)
                            setStatus("หยิบเบ็ดให้แล้ว: " .. tool.Name)
                            break
                        end
                    end
                end
            end
            task.wait(1)
        end
    end)

    ---------------------------------------------------------------- 13) บันทึกตั้งค่าลงไฟล์ (ชุดที่ 1-3)
    local HttpService = game:GetService("HttpService")
    local FOLDER = "AutoFish"
    local canFile = typeof(writefile) == "function" and typeof(readfile) == "function"
        and typeof(isfile) == "function"

    -- JSON เก็บ CFrame / Vector3 ตรงๆ ไม่ได้ แปลงเป็นตัวเลขก่อน
    local function encode(v)
        if typeof(v) == "CFrame" then
            return { __cf = { v:GetComponents() } }
        elseif typeof(v) == "Vector3" then
            return { __v3 = { v.X, v.Y, v.Z } }
        elseif typeof(v) == "table" then
            local out = {}
            for k, val in pairs(v) do
                out[tostring(k)] = encode(val)
            end
            return out
        end
        return v
    end

    local function decode(v)
        if typeof(v) ~= "table" then return v end
        if v.__cf then return CFrame.new(table.unpack(v.__cf)) end
        if v.__v3 then return Vector3.new(table.unpack(v.__v3)) end
        local out = {}
        for k, val in pairs(v) do
            out[tonumber(k) or k] = decode(val) -- คีย์ตัวเลข (ลำดับจุดในเส้นทาง) กลับเป็นตัวเลข
        end
        return out
    end

    local function profilePath(name)
        return ("%s/%s.json"):format(FOLDER, name)
    end

    local function writeProfile(name, data)
        local json = HttpService:JSONEncode(encode(data))
        if canFile then
            if typeof(makefolder) == "function" and not (typeof(isfolder) == "function" and isfolder(FOLDER)) then
                pcall(makefolder, FOLDER)
            end
            writefile(profilePath(name), json)
        else
            -- executor ไม่มี writefile: เก็บไว้ชั่วคราว (หายเมื่อออกเกม)
            env.AutoFishProfiles = env.AutoFishProfiles or {}
            env.AutoFishProfiles[name] = json
        end
    end

    local function readProfile(name)
        local json
        if canFile then
            if isfile(profilePath(name)) then
                json = readfile(profilePath(name))
            end
        elseif env.AutoFishProfiles then
            json = env.AutoFishProfiles[name]
        end
        if not json then return nil end
        local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
        return ok and decode(data) or nil
    end

    local function deleteProfile(name)
        if canFile then
            if isfile(profilePath(name)) and typeof(delfile) == "function" then
                delfile(profilePath(name))
            end
        elseif env.AutoFishProfiles then
            env.AutoFishProfiles[name] = nil
        end
    end

    -- ข้อมูลที่เก็บ: settings ทั้งหมด + จุด 1-5 + ช่องที่ใช้อยู่
    local function snapshot()
        saveSlot()
        local copy = {}
        for k, v in pairs(settings) do
            copy[k] = v
        end
        return {
            savedAt = os.date("%d/%m/%Y %H:%M"),
            settings = copy,
            slots = env.AutoFishSlots,
            slot = env.AutoFishSlot,
        }
    end

    local function labelOf(map, value)
        for label, v in pairs(map) do
            if v == value then return label end
        end
    end

    local function applyProfile(data)
        -- 1) ค่าตั้งค่า + ให้ปุ่มในหน้าต่างตรงกับค่า
        for k, v in pairs(data.settings or {}) do
            if settings[k] ~= nil and typeof(v) == typeof(settings[k]) then
                settings[k] = v
                local c = controls[k]
                if c then
                    pcall(function()
                        c.element:SetValue(c.kind == "number" and tostring(v) or v)
                    end)
                end
            end
        end
        pcall(function() travelDropdown:SetValue(labelOf(TRAVEL, settings.sellTravel)) end)
        pcall(function() returnDropdown:SetValue(labelOf(RETURN, settings.returnMode)) end)

        -- 2) จุด 1-5
        recording = false
        env.AutoFishRecording = nil
        env.AutoFishSlots = data.slots or {}
        local slot = tonumber(data.slot) or 1
        loadSlot(slot) -- ตั้ง env.AutoFishSlot ก่อน แล้วค่อยขยับเมนู (เมนูจะไม่ทับข้อมูล)
        pcall(function() Fluent.Options.AFSlot:SetValue("จุด " .. slot) end)
        refreshRouteButton()
        refreshShopButton()
        drawRoute()
    end

    local function refreshProfileLabel(i)
        local data = readProfile("profile" .. i)
        if not data then
            profileLabel.Text = ("ชุดที่ %d: ยังไม่ได้บันทึก"):format(i)
                .. (canFile and "" or "\n(executor นี้เซฟไฟล์ไม่ได้ จะเก็บไว้แค่จนออกเกม)")
            return
        end
        local on = {}
        for _, key in ipairs({ "autoSell", "antiAfk", "breakOn", "nearbyOn", "speedOn", "jumpOn",
            "rareAlert", "autoEquip", "autoRejoin" }) do
            if data.settings and data.settings[key] then
                table.insert(on, key)
            end
        end
        local slots = 0
        for _, v in pairs(data.slots or {}) do
            if v.spot or v.route or v.shop then slots += 1 end
        end
        profileLabel.Text = ("ชุดที่ %d  •  บันทึกเมื่อ %s\nจุดที่บันทึกไว้ %d ช่อง  •  เปิดอยู่ %d อย่าง")
            :format(i, tostring(data.savedAt or "?"), slots, #on)
    end

    uiHooks.profileSelected = refreshProfileLabel
    refreshProfileLabel(selectedProfile)

    profileSaveButton.MouseButton1Click:Connect(function()
        writeProfile("profile" .. selectedProfile, snapshot())
        refreshProfileLabel(selectedProfile)
        notify("บันทึกแล้ว", ("ชุดที่ %d"):format(selectedProfile))
    end)

    profileLoadButton.MouseButton1Click:Connect(function()
        local data = readProfile("profile" .. selectedProfile)
        if not data then
            notify("ยังไม่มีข้อมูล", ("ชุดที่ %d ยังไม่ได้บันทึก"):format(selectedProfile))
            return
        end
        applyProfile(data)
        notify("ใช้ตั้งค่าแล้ว", ("ชุดที่ %d"):format(selectedProfile))
    end)

    profileDeleteButton.MouseButton1Click:Connect(function()
        deleteProfile("profile" .. selectedProfile)
        refreshProfileLabel(selectedProfile)
        notify("ล้างแล้ว", ("ชุดที่ %d"):format(selectedProfile))
    end)

    ---------------------------------------------------------------- 14) เข้าเกมใหม่เมื่อหลุด
    -- หลุด -> เซฟตั้งค่าตอนนั้นลง rejoin.json -> เข้าเกมใหม่ -> (ถ้า executor มี queue_on_teleport)
    -- รันสคริปต์ให้เอง แล้วโหลด rejoin.json และเปิดตกปลาต่อ
    local SCRIPT_URL = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/AutoFish.lua"
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    local queueTeleport = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or (typeof(queueonteleport) == "function" and queueonteleport)
        or (typeof(syn) == "table" and syn.queue_on_teleport)

    local rejoining = false
    local function rejoin()
        if rejoining or not settings.autoRejoin then return end
        rejoining = true
        pcall(writeProfile, "rejoin", snapshot())
        if queueTeleport then
            pcall(queueTeleport, ("getgenv().AutoFishResume = true; loadstring(game:HttpGet(%q))()"):format(SCRIPT_URL))
        end
        task.wait(2)
        for _ = 1, 5 do
            local ok = pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
            if ok then break end
            task.wait(5)
        end
    end

    connections[#connections + 1] = GuiService.ErrorMessageChanged:Connect(function(message)
        if message and message ~= "" then
            task.spawn(rejoin)
        end
    end)

    -- รันมาจากการเข้าเกมใหม่: โหลดตั้งค่าก่อนหลุด แล้วตกต่อ
    if env.AutoFishResume then
        env.AutoFishResume = nil
        task.spawn(function()
            local data = readProfile("rejoin")
            if not data then return end
            if not LocalPlayer.Character then
                LocalPlayer.CharacterAdded:Wait()
            end
            task.wait(5) -- รอเกมโหลด
            applyProfile(data)
            local spot = env.AutoFishFishSpot
            local hrp = getRoot()
            if spot and hrp then
                hrp.CFrame = spot -- กลับจุดตกปลาเดิม
                task.wait(1)
            end
            setEnabled(true)
            notify("เข้าเกมใหม่แล้ว", "โหลดตั้งค่าก่อนหลุด และตกปลาต่อ")
        end)
    end

    ---------------------------------------------------------------- 15) ฟรีแคม
    local ContextActionService = game:GetService("ContextActionService")
    local MOVE = {
        W = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1),
        A = Vector3.new(-1, 0, 0), D = Vector3.new(1, 0, 0),
        E = Vector3.new(0, 1, 0), Q = Vector3.new(0, -1, 0),
    }
    local cam = { on = false, held = {}, pitch = 0, yaw = 0, pos = Vector3.zero }

    -- กินปุ่ม WASDQE ระหว่างฟรีแคม ตัวละครจะไม่เดินตาม
    local function sinkMove(_, state, input)
        local name = input.KeyCode.Name
        if MOVE[name] then
            cam.held[name] = state == Enum.UserInputState.Begin
        end
        return Enum.ContextActionResult.Sink
    end

    local function setFreecam(on)
        if cam.on == on then return end
        cam.on = on
        local camera = workspace.CurrentCamera
        if on then
            local cf = camera.CFrame
            cam.pos = cf.Position
            cam.pitch, cam.yaw = cf:ToEulerAnglesYXZ()
            camera.CameraType = Enum.CameraType.Scriptable
            ContextActionService:BindActionAtPriority("AFFreecam", sinkMove, false,
                Enum.ContextActionPriority.High.Value + 100,
                Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E)
        else
            ContextActionService:UnbindAction("AFFreecam")
            table.clear(cam.held)
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            camera.CameraType = Enum.CameraType.Custom
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
        -- ให้สวิตช์ในหน้าต่างตรงกับสถานะ (กดปุ่มลัดก็ขยับตาม)
        if freecamToggle.Value ~= on then
            pcall(function() freecamToggle:SetValue(on) end)
        end
    end
    uiHooks.freecamToggled = setFreecam

    connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
        if not cam.on then return end
        -- คลิกขวาค้าง = หมุนกล้อง
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
            local delta = UserInputService:GetMouseDelta()
            cam.yaw -= delta.X * 0.004
            cam.pitch = math.clamp(cam.pitch - delta.Y * 0.004, -1.45, 1.45)
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        local move = Vector3.zero
        for name, down in pairs(cam.held) do
            if down then move += MOVE[name] end
        end
        local rot = CFrame.fromEulerAnglesYXZ(cam.pitch, cam.yaw, 0)
        local fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
        cam.pos += rot:VectorToWorldSpace(move) * (40 * freecamSpeed * fast * dt)
        workspace.CurrentCamera.CFrame = CFrame.new(cam.pos) * rot
    end)

    -- ปุ่มลัดเปิด/ปิด
    connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        local hit
        if freecamKeyName == "ปุ่มกลางเมาส์" then
            hit = input.UserInputType == Enum.UserInputType.MouseButton3
        else
            hit = input.KeyCode.Name == freecamKeyName
        end
        if hit then
            setFreecam(not cam.on)
        end
    end)

    -- ปิดสคริปต์/รันใหม่ = คืนกล้องปกติ
    ScreenGui.AncestryChanged:Connect(function()
        if not ScreenGui.Parent then
            setFreecam(false)
        end
    end)
end)()
