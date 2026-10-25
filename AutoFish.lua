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
local PERFECT_AIM = 0.5   -- ปล่อยเมื่อปลายแถบถึงตำแหน่งไหนของ PerfectZone (0 = ขอบซ้าย, 0.5 = กลาง)
local CAST_TIMEOUT = 5    -- กดค้างนานสุดกี่วินาที กันลูปค้าง
local POWER_APPEAR_TIMEOUT = 1.5 -- กดแล้วรอหลอด Power ขึ้นกี่วินาที
local CHARGE_TIME = 1.0   -- (โหมด remote) กดค้างชาร์จกี่วินาทีก่อนส่ง Cast
local MIN_BITE_WAIT = 1.5 -- โยนแล้วอย่างน้อยกี่วินาทีถึงเริ่มเช็คว่าปลากิน
local BITE_TEXT = "กดเลย"   -- ข้อความบนปุ่มตอนปลากินเหยื่อ
local HOOK_REACTION = 0.3 -- (โหมด remote) ปลากินแล้วรอกี่วินาทีก่อนส่ง "Hook" (ให้ดูเหมือนคนกด)
local HOOK_COOLDOWN = 1   -- ยิง "Hook" ซ้ำได้ทุกกี่วินาที ตอนป้าย Bang ยังขึ้นอยู่
local READY_TIMEOUT = 10  -- หลังได้ปลา รอปุ่มกลับเป็น "เหวี่ยง" นานสุดกี่วินาที
local CAST_DELAY = 0.5    -- ก่อนเหวี่ยงแต่ละครั้งรออีกกี่วินาที
local RECAST_RIGHT_AWAY = true -- ได้ปลาแล้วโยนต่อเลยโดยไม่รอปุ่มกลับเป็น "เหวี่ยง" (false = รอปุ่มก่อน)
local BITE_TIMEOUT = 30   -- โยนแล้วรอปลากินนานสุดกี่วินาที ก่อนโยนใหม่
-- วิธีสั่งงาน: "remote" = ยิง Remotes.Fishing.Action ตรงๆ ("Cast" / "Hook" / "Reel") ไม่ต้องพึ่งเมาส์
--             "mouse"  = จำลองคลิกเมาส์ (mouse1press หรือ VirtualInputManager)
local INPUT_MODE = "remote"
local CAST_DISTANCE = 20  -- (โหมด remote) ให้เบ็ดตกห่างจากตัวกี่ studs ข้างหน้า
local CAST_PERFECT = true -- (โหมด remote) ค่าตัวที่ 3 ของ "Cast" ที่เกมส่งตอนเหวี่ยงเข้า PerfectZone
local REEL_FINISH_DELAY = 0 -- (โหมด remote) หลัง Hook รอกี่วินาทีแล้วส่ง "Reel", true (ข้ามมินิเกม ได้ปลาเลย)
                            -- ถ้าเซิร์ฟเวอร์ไม่ให้ปลา ให้เพิ่มเป็น 0.5 / 1 / 2
local USE_EXECUTOR_MOUSE = true -- (โหมด mouse) false = บังคับใช้ VirtualInputManager แทน mouse1press
local REEL_HOLD = false   -- false = คลิกทีละครั้ง, true = กดค้างตอน Zone ต้องเลื่อนหาปลา (ลองสลับถ้าแบบแรกไม่ได้ผล)
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

-- คลิกกลางจอแทนมุม (0,0) ที่เป็น topbar
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

local function setMouse(down)
    local x, y = screenCenter()
    if USE_EXECUTOR_MOUSE and hasMouse1 then
        -- ย้ายเมาส์ไปกลางจอก่อน ไม่งั้นจะไปกดโดนปุ่ม ON/OFF ของเราเอง
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
local function getActionLabel()
    if actionLabel and actionLabel.Parent then
        return actionLabel
    end
    actionLabel = nil
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton"))
            and (d.Text:find("เหวี่ยง", 1, true) or d.Text:find(BITE_TEXT, 1, true)) then
            actionLabel = d
            break
        end
    end
    return actionLabel
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
        setStatus("ชาร์จ รอเข้า PerfectZone")
        waitFor(myId, CAST_TIMEOUT, function()
            return not isShown(track) or castReady(track)
        end)
    end
    setMouse(false) -- ปล่อยเสมอ ไม่ให้เมาส์ค้าง
    return appeared
end

local function cast(myId)
    if INPUT_MODE == "remote" and getActionRemote() then
        return castRemote()
    end
    return castMouse(myId)
end
-- ปลากินเบ็ด: ถ้าป้าย Bang (!) ขึ้น ให้ยิง "Hook" ตามที่เกมส่งตอนกดตวัดเบ็ด
local lastHook = 0
local function tryHook()
    local catchUI = getCatchUI()
    local bang = catchUI and catchUI:FindFirstChild("Bang")
    if bang and isShown(bang) and os.clock() - lastHook > HOOK_COOLDOWN then
        lastHook = os.clock()
        local remote = getActionRemote()
        if remote then
            remote:FireServer("Hook")
        else
            clickMouse()
        end
        return true
    end
    return false
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
    return label ~= nil and label.Text:find("เหวี่ยง", 1, true) ~= nil and isShown(label)
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

-- ลูปการทำงานหลัก
local function autoFishLoop(myId)
    if INPUT_MODE == "remote" and getActionRemote() then
        while isActive(myId) do
            remoteRound(myId)
        end
        return
    end

    while isActive(myId) do
        if isReeling() then
            if tryHook() then
                setStatus("ปลากิน! ตวัดเบ็ด (Hook)")
            else
                setStatus("กำลังดึงปลา")
                reelStep()
            end
            task.wait(0.05)
        else
            if mouseHeld then
                setMouse(false) -- จบช่วงดึงปลาแล้ว ปล่อยเมาส์
                task.wait(0.5)
            end

            if cast(myId) then
                setStatus("เหวี่ยงแล้ว รอปลากิน")
                -- รอปลากินเบ็ด (หน้าจอ Reel ขึ้น) ระหว่างนี้ห้ามคลิก ไม่งั้นจะดึงเบ็ดกลับ
                waitFor(myId, BITE_TIMEOUT, isReeling)
            else
                -- กดแล้วหลอด Power ไม่ขึ้น (ยังไม่ได้ถือเบ็ด? หรือเกมไม่รับคลิก)
                setStatus(getCastUI() and "กดแล้ว Power ไม่ขึ้น" or "หา FishingHud.Root.Power ไม่เจอ")
                task.wait(1)
            end
        end
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
