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
        showRoute = false, -- แสดงจุดเส้นทาง/จุดตกปลา/จุดร้านในโลก (เห็นแค่เราคนเดียว)
        returnMode = "walk", -- ขายเสร็จแล้วกลับจุดตกปลายังไง: "walk" = เดิน, "warp" = วาร์ป, "stay" = ไม่กลับ (หยุดตกปลา)
        breakOn = false, breakEvery = 25, breakSeconds = 30, -- พักทุกประมาณกี่ตัว / พักประมาณกี่วิ (สุ่ม ±30-40%)
        nearbyOn = false, nearbyRange = 30, -- มีผู้เล่นอื่นเข้ามาใกล้กี่ studs ให้พัก
        rareAlert = false, rareStop = false, -- เตือน / หยุด เมื่อได้ปลาที่ไม่ใช่ระดับ "ทั่วไป"
    }

    -- ชื่อระดับความหายากที่รู้จัก (ถ้าเกมมีชื่ออื่นเพิ่มเข้าไปได้)
    local RARITIES = { "ทั่วไป", "พิเศษ", "หายาก", "ยอดเยี่ยม", "มหากาพย์", "ตำนาน", "ในตำนาน", "เทพ", "เทพเจ้า", "ลึกลับ" }

    ---------------------------------------------------------------- UI
    -- หน้าต่างธีมมืด: ซ้าย = ปุ่มเปิด/ปิด + สถานะ + เมนูหมวด, ขวา = การ์ดตั้งค่าของหมวดที่เลือก
    -- ลากมุมขวาล่างเพื่อปรับขนาด, ปุ่ม – ย่อเหลือแถบหัว
    local THEME = {
        bg = Color3.fromRGB(17, 17, 20),
        panel = Color3.fromRGB(23, 23, 27),
        card = Color3.fromRGB(29, 29, 34),
        input = Color3.fromRGB(21, 21, 25),
        stroke = Color3.fromRGB(48, 48, 56),
        accent = Color3.fromRGB(255, 140, 50),
        text = Color3.fromRGB(235, 235, 240),
        sub = Color3.fromRGB(150, 150, 162),
        off = Color3.fromRGB(42, 42, 48),
    }
    local FONT = Enum.Font.GothamMedium
    local FONT_BOLD = Enum.Font.GothamBold

    local function corner(gui, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8)
        c.Parent = gui
        return c
    end
    local function stroke(gui, color)
        local st = Instance.new("UIStroke")
        st.Color = color or THEME.stroke
        st.Thickness = 1
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        st.Parent = gui
        return st
    end

    local SIDEBAR_WIDTH = 175
    local HEADER_HEIGHT = 46
    local MIN_SIZE = Vector2.new(520, 320)
    local windowSize = Vector2.new(660, 410)

    MainFrame.Size = UDim2.fromOffset(windowSize.X, windowSize.Y)
    MainFrame.Position = UDim2.new(0.5, -windowSize.X / 2, 0.08, 0)
    MainFrame.BackgroundColor3 = THEME.bg
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    corner(MainFrame, 12)
    stroke(MainFrame)

    -- แถบหัว: โลโก้ + ชื่อ + เวอร์ชัน (ลากหน้าต่างจากตรงนี้)
    TitleBar.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
    TitleBar.BackgroundTransparency = 1
    TitleBar.Text = ""
    TitleBar.ZIndex = 3

    local Logo = Instance.new("TextLabel")
    Logo.Size = UDim2.fromOffset(34, 34)
    Logo.Position = UDim2.fromOffset(12, 6)
    Logo.BackgroundColor3 = THEME.accent
    Logo.Text = "🎣"
    Logo.TextSize = 20
    Logo.ZIndex = 3
    Logo.Parent = TitleBar
    corner(Logo, 9)

    local TitleText = Instance.new("TextLabel")
    TitleText.Size = UDim2.fromOffset(200, 20)
    TitleText.Position = UDim2.fromOffset(54, 5)
    TitleText.BackgroundTransparency = 1
    TitleText.Text = "ตกปลาอัตโนมัติ"
    TitleText.TextColor3 = THEME.text
    TitleText.Font = FONT_BOLD
    TitleText.TextSize = 17
    TitleText.TextXAlignment = Enum.TextXAlignment.Left
    TitleText.ZIndex = 3
    TitleText.Parent = TitleBar

    local VersionText = Instance.new("TextLabel")
    VersionText.Size = UDim2.fromOffset(200, 14)
    VersionText.Position = UDim2.fromOffset(54, 25)
    VersionText.BackgroundTransparency = 1
    VersionText.Text = "เวอร์ชัน 2.0  •  Auto Fish"
    VersionText.TextColor3 = THEME.sub
    VersionText.Font = FONT
    VersionText.TextSize = 12
    VersionText.TextXAlignment = Enum.TextXAlignment.Left
    VersionText.ZIndex = 3
    VersionText.Parent = TitleBar

    -- พื้นหลังแถบซ้าย
    local SidebarBg = Instance.new("Frame")
    SidebarBg.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
    SidebarBg.BackgroundColor3 = THEME.panel
    SidebarBg.BorderSizePixel = 0
    SidebarBg.ZIndex = 1
    SidebarBg.Parent = MainFrame

    local HeaderLine = Instance.new("Frame")
    HeaderLine.Size = UDim2.new(1, 0, 0, 1)
    HeaderLine.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
    HeaderLine.BackgroundColor3 = THEME.stroke
    HeaderLine.BorderSizePixel = 0
    HeaderLine.ZIndex = 2
    HeaderLine.Parent = MainFrame

    -- ปุ่มเปิด/ปิดตกปลา + สถานะ (อยู่บนสุดของแถบซ้าย)
    ToggleButton.Size = UDim2.fromOffset(SIDEBAR_WIDTH - 24, 38)
    ToggleButton.Position = UDim2.fromOffset(12, HEADER_HEIGHT + 12)
    ToggleButton.Font = FONT_BOLD
    ToggleButton.TextSize = 15
    ToggleButton.ZIndex = 3
    corner(ToggleButton, 8)

    StatusLabel.Size = UDim2.fromOffset(SIDEBAR_WIDTH - 24, 34)
    StatusLabel.Position = UDim2.fromOffset(12, HEADER_HEIGHT + 54)
    StatusLabel.TextScaled = false
    StatusLabel.TextWrapped = true
    StatusLabel.Font = FONT
    StatusLabel.TextSize = 12
    StatusLabel.TextColor3 = THEME.accent
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
    StatusLabel.ZIndex = 3

    local NavTitle = Instance.new("TextLabel")
    NavTitle.Size = UDim2.fromOffset(SIDEBAR_WIDTH - 24, 16)
    NavTitle.Position = UDim2.fromOffset(14, HEADER_HEIGHT + 94)
    NavTitle.BackgroundTransparency = 1
    NavTitle.Text = "เมนู"
    NavTitle.TextColor3 = THEME.sub
    NavTitle.Font = FONT
    NavTitle.TextSize = 12
    NavTitle.TextXAlignment = Enum.TextXAlignment.Left
    NavTitle.ZIndex = 3
    NavTitle.Parent = MainFrame

    -- เมนูหมวด
    local Sidebar = Instance.new("Frame")
    Sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH - 16, 1, -(HEADER_HEIGHT + 120))
    Sidebar.Position = UDim2.fromOffset(8, HEADER_HEIGHT + 114)
    Sidebar.BackgroundTransparency = 1
    Sidebar.ZIndex = 3
    Sidebar.Parent = MainFrame
    local sidebarLayout = Instance.new("UIListLayout")
    sidebarLayout.Padding = UDim.new(0, 2)
    sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sidebarLayout.Parent = Sidebar

    -- หัวข้อหน้าที่เปิดอยู่ (ขวาบน)
    local PageTitle = Instance.new("TextLabel")
    PageTitle.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 24), 0, 26)
    PageTitle.Position = UDim2.fromOffset(SIDEBAR_WIDTH + 16, HEADER_HEIGHT + 8)
    PageTitle.BackgroundTransparency = 1
    PageTitle.TextColor3 = THEME.text
    PageTitle.Font = FONT_BOLD
    PageTitle.TextSize = 19
    PageTitle.TextXAlignment = Enum.TextXAlignment.Left
    PageTitle.ZIndex = 2
    PageTitle.Parent = MainFrame

    -- พื้นที่การ์ด (ขวา)
    local PageArea = Instance.new("Frame")
    PageArea.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 20), 1, -(HEADER_HEIGHT + 46))
    PageArea.Position = UDim2.fromOffset(SIDEBAR_WIDTH + 12, HEADER_HEIGHT + 40)
    PageArea.BackgroundTransparency = 1
    PageArea.ZIndex = 2
    PageArea.Parent = MainFrame

    local pages, tabButtons = {}, {}
    local currentPage -- หน้าที่กำลังใส่ของ (ตอนสร้าง UI)
    local currentCard -- การ์ดที่กำลังใส่ของ

    local function showPage(name)
        for n, page in pairs(pages) do
            local on = n == name
            page.Visible = on
            local tab = tabButtons[n]
            tab.BackgroundTransparency = on and 0 or 1
            tab.TextColor3 = on and THEME.accent or THEME.sub
            tab:FindFirstChild("Bar").Visible = on
        end
        PageTitle.Text = name
    end

    local tabCount = 0
    local function addPage(name)
        tabCount += 1
        local page = Instance.new("ScrollingFrame")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = THEME.stroke
        page.CanvasSize = UDim2.new()
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        page.ZIndex = 2
        page.Parent = PageArea
        local l = Instance.new("UIListLayout")
        l.Padding = UDim.new(0, 8)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.Parent = page
        local pad = Instance.new("UIPadding")
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingBottom = UDim.new(0, 8)
        pad.Parent = page
        pages[name] = page

        local tab = Instance.new("TextButton")
        tab.Size = UDim2.new(1, 0, 0, 32)
        tab.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
        tab.BackgroundTransparency = 1
        tab.AutoButtonColor = false
        tab.TextColor3 = THEME.sub
        tab.Font = FONT
        tab.TextSize = 14
        tab.Text = name
        tab.TextXAlignment = Enum.TextXAlignment.Left
        tab.LayoutOrder = tabCount
        tab.ZIndex = 3
        tab.Parent = Sidebar
        corner(tab, 7)
        local tabPad = Instance.new("UIPadding")
        tabPad.PaddingLeft = UDim.new(0, 14)
        tabPad.Parent = tab
        local bar = Instance.new("Frame") -- แถบสีส้มข้างเมนูที่เลือก
        bar.Name = "Bar"
        bar.Size = UDim2.fromOffset(3, 18)
        bar.Position = UDim2.new(0, -12, 0.5, -9)
        bar.BackgroundColor3 = THEME.accent
        bar.BorderSizePixel = 0
        bar.Visible = false
        bar.ZIndex = 4
        bar.Parent = tab
        corner(bar, 2)
        tab.MouseButton1Click:Connect(function()
            showPage(name)
        end)
        tabButtons[name] = tab
        return page
    end

    local PAGE_MAIN = "📊  หลัก"
    local PAGE_SELL = "💰  ขายปลา"
    local PAGE_WALK = "🚶  เดิน / เส้นทาง"
    local PAGE_SAFE = "🛡️  ความปลอดภัย"
    local PAGE_CHAR = "🏃  ตัวละคร"
    local PAGE_ALERT = "🔔  แจ้งเตือน"
    for _, n in ipairs({ PAGE_MAIN, PAGE_SELL, PAGE_WALK, PAGE_SAFE, PAGE_CHAR, PAGE_ALERT }) do
        addPage(n)
    end
    local function setPage(name)
        currentPage = pages[name]
        currentCard = nil
    end
    setPage(PAGE_MAIN)

    ---- ปรับขนาดหน้าต่าง: ลากมุมขวาล่าง
    local ResizeHandle = Instance.new("TextButton")
    ResizeHandle.Size = UDim2.fromOffset(18, 18)
    ResizeHandle.Position = UDim2.new(1, -18, 1, -18)
    ResizeHandle.BackgroundTransparency = 1
    ResizeHandle.AutoButtonColor = false
    ResizeHandle.Text = "◢"
    ResizeHandle.TextColor3 = THEME.sub
    ResizeHandle.TextSize = 14
    ResizeHandle.ZIndex = 6
    ResizeHandle.Parent = MainFrame
    do
        local resizing, startMouse, startSize
        ResizeHandle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                startMouse = Vector2.new(input.Position.X, input.Position.Y)
                startSize = windowSize
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = Vector2.new(input.Position.X, input.Position.Y) - startMouse
                local view = workspace.CurrentCamera.ViewportSize
                windowSize = Vector2.new(
                    math.clamp(startSize.X + delta.X, MIN_SIZE.X, view.X),
                    math.clamp(startSize.Y + delta.Y, MIN_SIZE.Y, view.Y)
                )
                MainFrame.Size = UDim2.fromOffset(windowSize.X, windowSize.Y)
            end
        end)
    end

    local order = 0
    local function nextOrder()
        order += 1
        return order
    end

    -- การ์ด: กล่องมุมโค้งมีหัวข้อ ของที่สร้างต่อจากนี้จะอยู่ในการ์ดนี้ จนกว่าจะเปิดการ์ด/หน้าใหม่
    local function makeHeader(text)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = THEME.card
        card.BorderSizePixel = 0
        card.LayoutOrder = nextOrder()
        card.ZIndex = 2
        card.Parent = currentPage
        corner(card, 9)
        stroke(card)
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 12)
        pad.Parent = card
        local l = Instance.new("UIListLayout")
        l.Padding = UDim.new(0, 6)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.Parent = card

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 22)
        title.BackgroundTransparency = 1
        title.RichText = true
        title.Text = ('<font color="#FF8C32">●</font>  %s'):format(text)
        title.TextColor3 = THEME.text
        title.Font = FONT_BOLD
        title.TextSize = 15
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.LayoutOrder = 0
        title.ZIndex = 2
        title.Parent = card

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, 0, 0, 1)
        line.BackgroundColor3 = THEME.stroke
        line.BorderSizePixel = 0
        line.LayoutOrder = 1
        line.ZIndex = 2
        line.Parent = card

        currentCard = card
        return card
    end

    local function makeLabel(text, height, color)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, height or 18)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = color or THEME.sub
        l.Font = FONT
        l.TextSize = 13
        l.TextWrapped = true
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.LayoutOrder = nextOrder()
        l.ZIndex = 2
        l.Parent = currentCard or currentPage
        return l
    end

    local function makeRow()
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 30)
        row.BackgroundTransparency = 1
        row.LayoutOrder = nextOrder()
        row.ZIndex = 2
        row.Parent = currentCard or currentPage
        return row
    end

    -- ตัวเลือกเปิด/ปิด: ข้อความซ้าย + ช่องติ๊กขวา (ส้ม = เปิด)
    local function makeToggle(parent, text, get, set, width)
        local b = Instance.new("TextButton")
        b.Size = width or UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.AutoButtonColor = false
        b.Font = FONT
        b.TextSize = 14
        b.TextColor3 = THEME.text
        b.Text = text
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.ZIndex = 2
        b:SetAttribute("AF_Toggle", true)
        b.Parent = parent
        local pad = Instance.new("UIPadding")
        pad.PaddingRight = UDim.new(0, 30)
        pad.Parent = b

        local box = Instance.new("Frame")
        box.Size = UDim2.fromOffset(20, 20)
        box.AnchorPoint = Vector2.new(1, 0.5)
        box.Position = UDim2.new(1, 26, 0.5, 0)
        box.BorderSizePixel = 0
        box.ZIndex = 3
        box.Parent = b
        corner(box, 5)
        local boxStroke = stroke(box)
        local check = Instance.new("TextLabel")
        check.Size = UDim2.fromScale(1, 1)
        check.BackgroundTransparency = 1
        check.Text = "✓"
        check.TextColor3 = Color3.fromRGB(20, 20, 20)
        check.Font = FONT_BOLD
        check.TextSize = 15
        check.ZIndex = 4
        check.Parent = box

        local function refresh()
            local on = get()
            box.BackgroundColor3 = on and THEME.accent or THEME.off
            boxStroke.Color = on and THEME.accent or THEME.stroke
            check.Visible = on
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
        box.BackgroundColor3 = THEME.input
        box.TextColor3 = THEME.text
        box.Font = FONT
        box.TextSize = 14
        box.ZIndex = 2
        corner(box, 6)
        stroke(box)
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
        l.TextColor3 = THEME.text
        l.Font = FONT
        l.TextSize = 14
        l.ZIndex = 2
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = row
        return l
    end

    -- ===== หน้า หลัก =====
    makeHeader("สถิติ")
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

    -- ===== หน้า ความปลอดภัย =====
    setPage(PAGE_SAFE)
    makeHeader("กันโดนเตะ")
    -- 1) กัน AFK
    makeToggle(makeRow(), "กันโดนเตะ AFK",
        function() return settings.antiAfk end,
        function(v) settings.antiAfk = v end)

    -- ===== หน้า ตัวละคร =====
    setPage(PAGE_CHAR)
    makeHeader("ความเร็ว / กระโดด (ใส่ตัวเลขช่องขวา)")
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

    -- ===== หน้า หลัก: ตั้งเวลาหยุด =====
    setPage(PAGE_MAIN)
    makeHeader("หยุดเอง (0 = ไม่จำกัด)")
    -- 4) ตั้งเวลาหยุด (0 = ไม่จำกัด)
    local stopFishRow = makeRow()
    labelInRow(stopFishRow, "หยุดเมื่อได้ปลา (ตัว)", UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(stopFishRow, settings.stopFish, function(n) settings.stopFish = math.floor(n) end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    local stopTimeRow = makeRow()
    labelInRow(stopTimeRow, "หยุดเมื่อครบ (นาที)", UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(stopTimeRow, settings.stopMinutes, function(n) settings.stopMinutes = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- ===== หน้า ขายปลา =====
    setPage(PAGE_SELL)
    local sellCard = makeHeader("ขายอัตโนมัติ")
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

    -- ===== หน้า เดิน/เส้นทาง =====
    setPage(PAGE_WALK)
    makeHeader("ไปขาย / กลับ")
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

    -- ขายเสร็จแล้วกลับยังไง: กดสลับ เดิน -> วาร์ป -> ไม่กลับ
    local RETURN_LABELS = { walk = "เดินกลับ", warp = "วาร์ปกลับ", stay = "ไม่กลับ (หยุดตกที่ร้าน)" }
    local RETURN_NEXT = { walk = "warp", warp = "stay", stay = "walk" }
    local RETURN_COLORS = {
        walk = Color3.fromRGB(40, 110, 150),
        warp = Color3.fromRGB(150, 70, 40),
        stay = Color3.fromRGB(70, 70, 70),
    }
    local returnRow = makeRow()
    local returnButton = Instance.new("TextButton")
    returnButton.Size = UDim2.new(1, 0, 1, 0)
    returnButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    returnButton.Font = Enum.Font.SourceSansBold
    returnButton.TextSize = 14
    returnButton.Parent = returnRow
    local function refreshReturn()
        returnButton.Text = "ขายเสร็จแล้ว: " .. RETURN_LABELS[settings.returnMode]
        returnButton.BackgroundColor3 = RETURN_COLORS[settings.returnMode]
    end
    returnButton.MouseButton1Click:Connect(function()
        settings.returnMode = RETURN_NEXT[settings.returnMode]
        refreshReturn()
    end)
    refreshReturn()

    makeToggle(makeRow(), "เดินติดให้วาร์ปแทน",
        function() return settings.walkFallbackWarp end,
        function(v) settings.walkFallbackWarp = v end)

    makeHeader("เส้นทาง (บันทึกจากจุดตกปลา → ร้าน)")
    -- บันทึกเส้นทางเดิน: กดเริ่มที่จุดตกปลา เดินไปร้านเอง แล้วกดหยุดที่ร้าน
    local routeRow = makeRow()
    local routeButton = Instance.new("TextButton")
    routeButton.Size = UDim2.new(1, 0, 1, 0)
    routeButton.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
    routeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    routeButton.Font = Enum.Font.SourceSansBold
    routeButton.TextSize = 14
    routeButton.Parent = routeRow

    -- ล้างเส้นทาง (ย้ายไปตกจุดใหม่)
    local resetRouteRow = makeRow()
    local function halfButtonIn(row, text, x, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -2, 1, 0)
        b.Position = UDim2.new(x, x > 0 and 2 or 0, 0, 0)
        b.BackgroundColor3 = color
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.SourceSansBold
        b.TextSize = 14
        b.Text = text
        b.Parent = row
        return b
    end
    local clearRouteButton = halfButtonIn(resetRouteRow, "ล้างเส้นทาง+จุดตกปลา", 0, Color3.fromRGB(150, 60, 60))
    local clearAllButton = halfButtonIn(resetRouteRow, "ล้างทั้งหมด (รวมร้าน)", 0.5, Color3.fromRGB(110, 40, 40))

    -- ปุ่มเดินเอง: กลับจุดตกปลา / ไปร้าน
    local goRow = makeRow()
    local function halfButton(text, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -2, 1, 0)
        b.Position = UDim2.new(x, x > 0 and 2 or 0, 0, 0)
        b.BackgroundColor3 = Color3.fromRGB(40, 110, 150)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.SourceSansBold
        b.TextSize = 14
        b.Text = text
        b.Parent = goRow
        return b
    end
    local goBackButton = halfButton("เดินกลับจุดตกปลา", 0)
    local goShopButton = halfButton("เดินไปร้าน", 0.5)

    local drawRoute = function() end -- กำหนดจริงในส่วนการเดิน
    makeToggle(makeRow(), "แสดงเส้นทางในโลก",
        function() return settings.showRoute end,
        function(v)
            settings.showRoute = v
            drawRoute()
        end)

    setPage(PAGE_SELL)
    currentCard = sellCard
    local bagLabel = makeLabel("", 18, Color3.fromRGB(255, 220, 120))

    setPage(PAGE_SAFE)
    makeHeader("พักเป็นระยะ (สุ่มให้ไม่เท่ากัน)")
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

    makeHeader("มีผู้เล่นอื่นเข้าใกล้ (ระยะ studs)")
    -- 9) หยุดเมื่อมีคนใกล้
    local nearbyRow = makeRow()
    makeToggle(nearbyRow, "พักเมื่อมีคนใกล้",
        function() return settings.nearbyOn end,
        function(v) settings.nearbyOn = v end,
        UDim2.new(0.65, -2, 1, 0))
    makeNumberBox(nearbyRow, settings.nearbyRange, function(n) settings.nearbyRange = n end,
        UDim2.new(0.35, 0, 1, 0), UDim2.new(0.65, 2, 0, 0))

    -- ===== หน้า แจ้งเตือน =====
    setPage(PAGE_ALERT)
    makeHeader("ปลาหายาก / ปลาชนิดใหม่")
    -- 10) ปลาหายาก
    makeToggle(makeRow(), "เตือนเมื่อได้ปลาหายาก",
        function() return settings.rareAlert end,
        function(v) settings.rareAlert = v end)
    makeToggle(makeRow(), "หยุดเมื่อได้ปลาหายาก",
        function() return settings.rareStop end,
        function(v) settings.rareStop = v end)

    -- 3) บอกปุ่มลัด (หน้าหลัก)
    setPage(PAGE_MAIN)
    makeHeader("ปุ่มลัด")
    makeLabel(("%s = เปิด/ปิดตกปลา   %s = ซ่อนหน้าต่าง"):format(TOGGLE_KEY.Name, HIDE_KEY.Name),
        16, Color3.fromRGB(160, 160, 160))

    -- ปุ่มกดทั่วไปในการ์ด (ไม่ใช่ตัวเลือกติ๊ก): มุมโค้ง + ฟอนต์ธีม
    for _, d in ipairs(PageArea:GetDescendants()) do
        if d:IsA("TextButton") and not d:GetAttribute("AF_Toggle") then
            d.Font = FONT_BOLD
            d.TextSize = 13
            d.ZIndex = 2
            if not d:FindFirstChildOfClass("UICorner") then
                corner(d, 7)
            end
        end
    end

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
        TitleText.Text = minimized and ("ตกปลาอัตโนมัติ " .. (isAutoFishing and "(เปิด)" or "(ปิด)")) or "ตกปลาอัตโนมัติ"
    end

    MinButton.Size = UDim2.fromOffset(28, 28)
    MinButton.Position = UDim2.new(1, -40, 0, 9)
    MinButton.BackgroundColor3 = THEME.off
    MinButton.TextColor3 = THEME.text
    MinButton.Font = FONT_BOLD
    MinButton.ZIndex = 4
    corner(MinButton, 14)
    MinButton.MouseButton1Click:Connect(function()
        minimized = not minimized
        -- ซ่อน/แสดงทุกอย่างยกเว้นแถบหัว
        for _, gui in ipairs(MainFrame:GetChildren()) do
            if gui:IsA("GuiObject") and gui ~= TitleBar then
                gui.Visible = not minimized
            end
        end
        -- ย่อเหลือแถบหัว / ขยายกลับขนาดเดิมที่ปรับไว้
        MainFrame.Size = minimized and UDim2.fromOffset(280, HEADER_HEIGHT) or UDim2.fromOffset(windowSize.X, windowSize.Y)
        MinButton.Text = minimized and "+" or "–"
        refreshTitle()
    end)

    showPage(PAGE_MAIN)

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
