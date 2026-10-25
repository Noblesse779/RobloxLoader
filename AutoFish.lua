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
local HOOK_REACTION = 0.3 -- (โหมด remote) ปลากินแล้วรอกี่วินาทีก่อนส่ง "Hook" (ให้ดูเหมือนคนกด)
local HOOK_COOLDOWN = 1   -- ยิง "Hook" ซ้ำได้ทุกกี่วินาที ตอนป้าย Bang ยังขึ้นอยู่
local SKIP_MINIGAME = true      -- true = ข้ามมินิเกมดึงปลา (ยิง "Reel", true เอง) ถ้าเซิร์ฟเวอร์ไม่ให้ปลาจะเล่นมินิเกมต่อให้
local SKIP_MINIGAME_DELAY = 2.8 -- ตวัดแล้วรอกี่วินาทีก่อนยิง (2.7 วิบางรอบไม่ได้ปลา, 2.8 วิได้ทุกรอบ)
local AFTER_CATCH_DELAY = 2 -- ได้ปลาแล้วรอกี่วินาทีก่อนโยนใหม่ (ถ้าโยนไม่ออกเพราะหน้าต่างโชว์ปลาบัง ให้เพิ่ม)
local READY_TIMEOUT = 5   -- หลังได้ปลา รอปุ่มกลับเป็น "เหวี่ยง" นานสุดกี่วินาที ก่อนลองเหวี่ยงต่อเลย
local CAST_DELAY = 0.5    -- ก่อนเหวี่ยงแต่ละครั้งรออีกกี่วินาที
local RECAST_RIGHT_AWAY = true -- ได้ปลาแล้วโยนต่อเลยโดยไม่รอปุ่มกลับเป็น "เหวี่ยง" (false = รอปุ่มก่อน)
local BITE_TIMEOUT = 30   -- โยนแล้วรอปลากินนานสุดกี่วินาที ก่อนโยนใหม่
-- วิธีสั่งงาน: "play"   = กดปุ่ม เหวี่ยง ของเกมเหมือนคนเล่น (ชาร์จ, ตวัด, เล่นมินิเกม) <- แนะนำ
--             "remote" = ยิง Remotes.Fishing.Action ตรงๆ ข้ามการชาร์จและมินิเกม (เซิร์ฟเวอร์อาจไม่ให้ปลา)
local INPUT_MODE = "play"
local REEL_TIMEOUT = 25   -- (โหมด play) เล่นมินิเกมนานสุดกี่วินาที
local CAST_DISTANCE = 20  -- (โหมด remote) ให้เบ็ดตกห่างจากตัวกี่ studs ข้างหน้า
local CAST_PERFECT = true -- (โหมด remote) ค่าตัวที่ 3 ของ "Cast" ที่เกมส่งตอนเหวี่ยงเข้า PerfectZone
local REEL_FINISH_DELAY = 0 -- (โหมด remote) หลัง Hook รอกี่วินาทีแล้วส่ง "Reel", true (ข้ามมินิเกม ได้ปลาเลย)
                            -- ถ้าเซิร์ฟเวอร์ไม่ให้ปลา ให้เพิ่มเป็น 0.5 / 1 / 2
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

-- เครื่องหมาย ! บนหัวตัวละคร (BillboardGui) = ปลากินเหยื่อ
local function bangOverHead()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and d.Text:match("^%s*!+%s*$") then
            local bb = d:FindFirstAncestorWhichIsA("BillboardGui")
            if bb and bb.Enabled then
                return true
            end
        end
    end
    return false
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

-- ปลากินเหยื่อหรือยัง: ใช้ปุ่ม "กดเลย!" เป็นหลัก (แม่นสุด)
-- หน้าจอ Reel ไม่ใช้แล้ว เพราะบางทีมัน Visible ค้างอยู่ ทำให้ Hook ทั้งที่ปลายังไม่กิน
local function isBite()
    if getActionLabel() then
        return actionSaysBite()
    end
    return bangOverHead()
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

-- จุดที่จะให้เบ็ดตก: ข้างหน้าตัวละคร CAST_DISTANCE studs แล้วยิง ray ลงหาผิวน้ำ/พื้น
local function getCastTarget()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local ahead = hrp.Position + hrp.CFrame.LookVector * CAST_DISTANCE
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    params.IgnoreWater = false
    local hit = workspace:Raycast(ahead + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0), params)
    if hit then
        return hit.Position
    end
    return Vector3.new(ahead.X, hrp.Position.Y - 3, ahead.Z)
end

-- โยนเบ็ดแบบ remote: ยิง "Cast", ตำแหน่ง, true ตรงๆ (เหมือนที่เกมส่งตอนปล่อยเข้า PerfectZone)
local function castRemote()
    local remote = getActionRemote()
    local target = getCastTarget()
    if not (remote and target) then return false end
    setStatus("เหวี่ยง (remote)")
    remote:FireServer("Cast", target, CAST_PERFECT)
    return true
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

-- โหมด remote: Cast -> รอปลากิน -> Hook -> รอ -> Reel true (ตามลำดับที่ดักได้จาก Remote Spy)
local function actionReady()
    local label = getActionLabel()
    return label ~= nil and label.Text:match("^%s*เหวี่ยง%s*$") ~= nil and isShown(label)
end

local justCaught = false -- รอบก่อนเพิ่งส่ง "Reel", true (ปลาเด้งเข้าตัว) ไป

local function remoteRound(myId)
    local remote = getActionRemote()

    if justCaught and RECAST_RIGHT_AWAY then
        -- ปลาเด้งเข้าตัวแล้ว โยนต่อเลยไม่ต้องรอปุ่ม
        justCaught = false
    else
        -- รอให้ปุ่มกลับมาเป็น "เหวี่ยง" ก่อน
        setStatus("รอปุ่ม เหวี่ยง พร้อม")
        if not waitFor(myId, READY_TIMEOUT, actionReady) and getActionLabel() then
            setStatus("ปุ่มไม่กลับเป็น เหวี่ยง: " .. getActionLabel().Text)
        end
    end
    if not isActive(myId) then return end
    task.wait(CAST_DELAY)
    if not isActive(myId) then return end

    -- ชาร์จหลอดให้เหมือนคนกดค้าง (หลอดบนจอไม่ขยับเพราะไม่ได้กดจริง แต่ส่ง Cast แบบเพอร์เฟกต์)
    setStatus(("ชาร์จ %.1f วิ"):format(CHARGE_TIME))
    waitFor(myId, CHARGE_TIME, function() return false end)
    if not isActive(myId) then return end

    if not castRemote() then
        setStatus("หา HumanoidRootPart ไม่เจอ")
        task.wait(1)
        return
    end

    setStatus("เหวี่ยงแล้ว รอปลากิน")
    -- ข้ามสถานะค้างจากรอบก่อน: รอให้สัญญาณปลากินหายก่อน แล้วค่อยรอปลากินรอบใหม่
    waitFor(myId, 2, function() return not isBite() end)
    -- ปลาไม่กินเร็วขนาดนี้ กันสัญญาณหลอก
    waitFor(myId, MIN_BITE_WAIT, function() return false end)
    if not waitFor(myId, BITE_TIMEOUT, isBite) then
        return -- ไม่มีปลากิน โยนใหม่
    end

    setStatus("ปลากิน! Hook")
    task.wait(HOOK_REACTION)
    if not isActive(myId) then return end
    remote:FireServer("Hook")

    if REEL_FINISH_DELAY > 0 then
        setStatus(("ดึงปลา รอ %.1f วิ"):format(REEL_FINISH_DELAY))
        waitFor(myId, REEL_FINISH_DELAY, function() return false end)
        if not isActive(myId) then return end
    end
    remote:FireServer("Reel", true) -- ปลาเด้งเข้าตัว
    justCaught = true
    setStatus("ได้ปลาแล้ว โยนต่อ")
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
local function catchPopupShown()
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text:find("ขายได้", 1, true)
            and d.Text:find("เหรียญ", 1, true) and isShown(d) then
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
    if INPUT_MODE == "remote" and getActionRemote() then
        while isActive(myId) do
            remoteRound(myId)
        end
        return
    end

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
do
    local RunService = game:GetService("RunService")

    local TOGGLE_KEY = Enum.KeyCode.F -- ปุ่มเปิด/ปิดตกปลา
    local HIDE_KEY = Enum.KeyCode.H   -- ปุ่มซ่อน/แสดงหน้าต่าง

    local settings = {
        antiAfk = true,
        speedOn = false, speed = 32,
        jumpOn = false, jump = 100,
        stopFish = 0,    -- 0 = ไม่จำกัด
        stopMinutes = 0, -- 0 = ไม่จำกัด
        autoSell = true,
        sellAt = 100,    -- ปลาในกระเป๋าครบกี่ตัวแล้วขายทั้งหมด
        sellTravel = "walk", -- ไปร้านยังไง: "walk" = เดินไป (เนียนกว่า), "warp" = วาร์ป (เร็วกว่า)
        breakOn = false, breakEvery = 25, breakSeconds = 30, -- พักทุกประมาณกี่ตัว / พักประมาณกี่วิ (สุ่ม ±30-40%)
        nearbyOn = false, nearbyRange = 30, -- มีผู้เล่นอื่นเข้ามาใกล้กี่ studs ให้พัก
        rareAlert = true, rareStop = false, -- เตือน / หยุด เมื่อได้ปลาที่ไม่ใช่ระดับ "ทั่วไป"
    }

    -- ชื่อระดับความหายากที่รู้จัก (ถ้าเกมมีชื่ออื่นเพิ่มเข้าไปได้)
    local RARITIES = { "ทั่วไป", "พิเศษ", "หายาก", "ยอดเยี่ยม", "มหากาพย์", "ตำนาน", "ในตำนาน", "เทพ", "เทพเจ้า", "ลึกลับ" }

    ---------------------------------------------------------------- UI
    local FULL_HEIGHT = 470

    MainFrame.Size = UDim2.new(0, 220, 0, FULL_HEIGHT)
    ToggleButton.Size = UDim2.new(1, -10, 0, 45)
    ToggleButton.Position = UDim2.new(0, 5, 0, 25)
    StatusLabel.Position = UDim2.new(0, 5, 0, 72)

    -- เลื่อนขึ้นลงได้ (ตั้งค่าเยอะ หน้าต่างจะได้ไม่ยาวเกินจอ)
    local Extras = Instance.new("ScrollingFrame")
    Extras.Size = UDim2.new(1, -6, 1, -98)
    Extras.Position = UDim2.new(0, 5, 0, 95)
    Extras.BackgroundTransparency = 1
    Extras.BorderSizePixel = 0
    Extras.ScrollBarThickness = 4
    Extras.CanvasSize = UDim2.new()
    Extras.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Extras.Parent = MainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = Extras

    local order = 0
    local function nextOrder()
        order += 1
        return order
    end

    local function makeLabel(text, height, color)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -6, 0, height or 18)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = color or Color3.fromRGB(220, 220, 220)
        l.Font = Enum.Font.SourceSans
        l.TextSize = 14
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.LayoutOrder = nextOrder()
        l.Parent = Extras
        return l
    end

    local function makeRow()
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 24)
        row.BackgroundTransparency = 1
        row.LayoutOrder = nextOrder()
        row.Parent = Extras
        return row
    end

    -- ปุ่มเปิด/ปิด: เขียว = เปิด, เทา = ปิด
    local function makeToggle(parent, text, get, set, width)
        local b = Instance.new("TextButton")
        b.Size = width or UDim2.new(1, 0, 1, 0)
        b.Font = Enum.Font.SourceSansBold
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Parent = parent
        local function refresh()
            b.Text = text .. ": " .. (get() and "เปิด" or "ปิด")
            b.BackgroundColor3 = get() and Color3.fromRGB(40, 150, 60) or Color3.fromRGB(70, 70, 70)
        end
        b.MouseButton1Click:Connect(function()
            set(not get())
            refresh()
        end)
        refresh()
        return b
    end

    -- ช่องพิมพ์ตัวเลข
    local function makeNumberBox(parent, value, onChange, size, position)
        local box = Instance.new("TextBox")
        box.Size = size
        box.Position = position or UDim2.new()
        box.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.Font = Enum.Font.SourceSans
        box.TextSize = 14
        box.Text = tostring(value)
        box.ClearTextOnFocus = false
        box.Parent = parent
        box.FocusLost:Connect(function()
            local n = tonumber(box.Text)
            if n and n >= 0 then
                onChange(n)
            end
            box.Text = tostring(n and n >= 0 and n or value)
            value = tonumber(box.Text)
        end)
        return box
    end

    local function labelInRow(row, text, width)
        local l = Instance.new("TextLabel")
        l.Size = width
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = Color3.fromRGB(220, 220, 220)
        l.Font = Enum.Font.SourceSans
        l.TextSize = 14
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = row
        return l
    end

    -- 2) สถิติ
    local statsLabel = makeLabel("", 72, Color3.fromRGB(150, 220, 255))

    local resetRow = makeRow()
    local resetButton = Instance.new("TextButton")
    resetButton.Size = UDim2.new(1, 0, 1, 0)
    resetButton.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
    resetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetButton.Font = Enum.Font.SourceSansBold
    resetButton.TextSize = 14
    resetButton.Text = "รีเซ็ตสถิติ"
    resetButton.Parent = resetRow

    -- 1) กัน AFK
    makeToggle(makeRow(), "กันโดนเตะ AFK",
        function() return settings.antiAfk end,
        function(v) settings.antiAfk = v end)

    -- 6) วิ่งเร็ว / กระโดดสูง
    local speedRow = makeRow()
    makeToggle(speedRow, "วิ่งเร็ว",
        function() return settings.speedOn end,
        function(v) settings.speedOn = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(speedRow, settings.speed, function(n) settings.speed = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    local jumpRow = makeRow()
    makeToggle(jumpRow, "กระโดดสูง",
        function() return settings.jumpOn end,
        function(v) settings.jumpOn = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(jumpRow, settings.jump, function(n) settings.jump = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- 4) ตั้งเวลาหยุด (0 = ไม่จำกัด)
    local stopFishRow = makeRow()
    labelInRow(stopFishRow, "หยุดเมื่อได้ปลา (ตัว)", UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(stopFishRow, settings.stopFish, function(n) settings.stopFish = math.floor(n) end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    local stopTimeRow = makeRow()
    labelInRow(stopTimeRow, "หยุดเมื่อครบ (นาที)", UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(stopTimeRow, settings.stopMinutes, function(n) settings.stopMinutes = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- 7) ขายปลาอัตโนมัติ
    local sellRow = makeRow()
    makeToggle(sellRow, "ขายเมื่อครบ",
        function() return settings.autoSell end,
        function(v) settings.autoSell = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(sellRow, settings.sellAt, function(n) settings.sellAt = math.max(1, math.floor(n)) end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    local sellNowRow = makeRow()
    local sellNowButton = Instance.new("TextButton")
    sellNowButton.Size = UDim2.new(1, 0, 1, 0)
    sellNowButton.BackgroundColor3 = Color3.fromRGB(150, 110, 30)
    sellNowButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    sellNowButton.Font = Enum.Font.SourceSansBold
    sellNowButton.TextSize = 14
    sellNowButton.Text = "ขายปลาทั้งหมดตอนนี้"
    sellNowButton.Parent = sellNowRow

    local shopRow = makeRow()
    local shopButton = Instance.new("TextButton")
    shopButton.Size = UDim2.new(1, 0, 1, 0)
    shopButton.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
    shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    shopButton.Font = Enum.Font.SourceSansBold
    shopButton.TextSize = 14
    shopButton.Parent = shopRow

    -- วิธีไปร้าน: กดสลับ เดิน <-> วาร์ป
    local travelRow = makeRow()
    local travelButton = Instance.new("TextButton")
    travelButton.Size = UDim2.new(1, 0, 1, 0)
    travelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    travelButton.Font = Enum.Font.SourceSansBold
    travelButton.TextSize = 14
    travelButton.Parent = travelRow
    local function refreshTravel()
        local walk = settings.sellTravel == "walk"
        travelButton.Text = "ไปร้านโดย: " .. (walk and "เดิน (เนียน)" or "วาร์ป (เร็ว)")
        travelButton.BackgroundColor3 = walk and Color3.fromRGB(40, 110, 150) or Color3.fromRGB(150, 70, 40)
    end
    travelButton.MouseButton1Click:Connect(function()
        settings.sellTravel = settings.sellTravel == "walk" and "warp" or "walk"
        refreshTravel()
    end)
    refreshTravel()

    local bagLabel = makeLabel("", 18, Color3.fromRGB(255, 220, 120))

    -- 8) พักเป็นระยะ
    local breakRow = makeRow()
    makeToggle(breakRow, "พักทุก (ตัว)",
        function() return settings.breakOn end,
        function(v) settings.breakOn = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(breakRow, settings.breakEvery, function(n) settings.breakEvery = math.max(1, math.floor(n)) end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    local breakTimeRow = makeRow()
    labelInRow(breakTimeRow, "พักนาน (วินาที)", UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(breakTimeRow, settings.breakSeconds, function(n) settings.breakSeconds = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- 9) หยุดเมื่อมีคนใกล้
    local nearbyRow = makeRow()
    makeToggle(nearbyRow, "พักเมื่อมีคนใกล้",
        function() return settings.nearbyOn end,
        function(v) settings.nearbyOn = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(nearbyRow, settings.nearbyRange, function(n) settings.nearbyRange = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- 10) ปลาหายาก
    makeToggle(makeRow(), "เตือนเมื่อได้ปลาหายาก",
        function() return settings.rareAlert end,
        function(v) settings.rareAlert = v end)
    makeToggle(makeRow(), "หยุดเมื่อได้ปลาหายาก",
        function() return settings.rareStop end,
        function(v) settings.rareStop = v end)

    -- 3) บอกปุ่มลัด
    makeLabel(("%s = เปิด/ปิดตกปลา   %s = ซ่อนหน้าต่าง"):format(TOGGLE_KEY.Name, HIDE_KEY.Name),
        16, Color3.fromRGB(160, 160, 160))

    ---------------------------------------------------------------- 5) ย่อหน้าต่าง
    local minimized = false
    local MinButton = Instance.new("TextButton")
    MinButton.Size = UDim2.new(0, 20, 0, 20)
    MinButton.Position = UDim2.new(1, -20, 0, 0)
    MinButton.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    MinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    MinButton.Font = Enum.Font.SourceSansBold
    MinButton.TextSize = 16
    MinButton.Text = "–"
    MinButton.Parent = TitleBar

    local function refreshTitle()
        if minimized then
            TitleBar.Text = "Auto Fish " .. (isAutoFishing and "(ON)" or "(OFF)")
        else
            TitleBar.Text = "Auto Fish"
        end
    end

    MinButton.MouseButton1Click:Connect(function()
        minimized = not minimized
        ToggleButton.Visible = not minimized
        StatusLabel.Visible = not minimized
        Extras.Visible = not minimized
        MainFrame.Size = UDim2.new(0, 220, 0, minimized and 20 or FULL_HEIGHT)
        MinButton.Text = minimized and "+" or "–"
        refreshTitle()
    end)

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

    ToggleButton.MouseButton1Click:Connect(clearPauses)

    ---------------------------------------------------------------- 3) ปุ่มลัด
    connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end -- กำลังพิมพ์แชท/ช่องตัวเลขอยู่
        if input.KeyCode == TOGGLE_KEY then
            clearPauses()
            setEnabled(not isAutoFishing)
        elseif input.KeyCode == HIDE_KEY then
            ScreenGui.Enabled = not ScreenGui.Enabled
        end
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
            if hum then
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
            task.wait(0.25)
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

    local function findPopupLabels()
        local sell, isNew
        for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
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

    local StarterGui = game:GetService("StarterGui")
    local function notify(title, text)
        pcall(function()
            StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 10 })
        end)
        -- กระพริบแถบหัวหน้าต่าง
        task.spawn(function()
            for _ = 1, 6 do
                TitleBar.BackgroundColor3 = Color3.fromRGB(200, 150, 0)
                task.wait(0.25)
                TitleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
                task.wait(0.25)
            end
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
            task.wait(0.5)
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

    local function refreshShopButton()
        shopButton.Text = env.AutoFishShopCFrame and "บันทึกจุดร้านแล้ว (กดเพื่อบันทึกใหม่)"
            or "บันทึกจุดร้าน (ยืนที่ร้านแล้วกด)"
    end
    refreshShopButton()

    shopButton.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            env.AutoFishShopCFrame = hrp.CFrame
            bagLabel.Text = "บันทึกจุดร้านแล้ว"
            refreshShopButton()
        end
    end)

    local function getRoot()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- เดินไปจุดหมายด้วยระบบหาทางของ Roblox (ข้ามสิ่งกีดขวาง/กระโดดได้)
    local PathfindingService = game:GetService("PathfindingService")
    local WALK_TIMEOUT = 60 -- เดินนานสุดกี่วินาทีต่อเที่ยว

    local function walkTo(target, timeout)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (hum and hrp) then return false end

        local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
        local ok = pcall(function()
            path:ComputeAsync(hrp.Position, target)
        end)
        local waypoints
        if ok and path.Status == Enum.PathStatus.Success then
            waypoints = path:GetWaypoints()
        else
            -- หาทางไม่เจอ: เดินตรงไปเลย
            waypoints = { { Position = target, Action = Enum.PathWaypointAction.Walk } }
        end

        local deadline = os.clock() + timeout
        for _, wp in ipairs(waypoints) do
            if wp.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
            local started = os.clock()
            local lastMove = 0
            while true do
                local flat = (hrp.Position - wp.Position) * Vector3.new(1, 0, 1)
                if flat.Magnitude < 3 then break end
                if os.clock() > deadline then return false end
                if os.clock() - started > 8 then break end -- ติดอยู่จุดนี้ ข้ามไปจุดถัดไป
                if os.clock() - lastMove > 1 then
                    hum:MoveTo(wp.Position)
                    lastMove = os.clock()
                end
                task.wait(0.1)
            end
        end
        return ((hrp.Position - target) * Vector3.new(1, 0, 1)).Magnitude <= SHOP_RANGE
    end

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
                        if hrp then
                            hrp.CFrame = back -- กลับจุดเดิม หันหน้าเข้าน้ำเหมือนเดิม
                        end
                        task.wait(0.8)
                    else
                        bagLabel.Text = "เดินไปขายที่ร้าน..."
                        if walkTo(shop.Position, WALK_TIMEOUT) then
                            task.wait(0.5)
                            sellRequest(ids)
                        else
                            bagLabel.Text = "เดินไปร้านไม่ถึง (ทางตัน?) ลองใช้วาร์ป"
                        end
                        walkTo(back.Position, WALK_TIMEOUT)
                        hrp = getRoot()
                        if hrp then
                            -- หันหน้ากลับทางเดิม (หมุนตัวอยู่กับที่ ไม่ได้วาร์ป)
                            hrp.CFrame = CFrame.new(hrp.Position) * back.Rotation
                        end
                        task.wait(0.5)
                    end
                end
                resumeFishing("sell")
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
            if not selling then
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
end
