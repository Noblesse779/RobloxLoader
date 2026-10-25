-- ฟาร์มแมพชาร์จพลังแล้วบิน (Dash) แบบเล่นตามกติกา
-- 1) วางตัวละครที่แข็งแกร่งสุดบนแท่นในฐานอัตโนมัติ
-- 2) ชาร์จ (กด SHIFT ค้างจนเต็ม) -> บิน -> กลับแท่นชาร์จ -> วนใหม่
-- 3) รีเบิร์ธอัตโนมัติ
-- 4) กันโดนเตะ AFK
-- ทุกฟังก์ชันปิดไว้ตอนรัน

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.DashFarmRun = (env.DashFarmRun or 0) + 1
local RUN = env.DashFarmRun -- รันสคริปต์ใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.DashFarmRun == RUN
end

local settings = {
    autoDash = false,
    autoPlace = false,
    antiAfk = false,
    autoRebirth = false,
    rebirthCheckEvery = 2, -- เช็คหลอดรีเบิร์ธทุกกี่วิ
    chargeTimeout = 20, -- ชาร์จนานสุดกี่วิ (ถ้าอ่าน % ไม่ได้ จะปล่อยตอนครบเวลานี้)
    placeEvery = 30,    -- เช็คแท่นว่าง/ตัวใหม่ทุกกี่วิ
}

local RARITY_ORDER = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
    Mythic = 6, Secret = 7, Cosmic = 8, Celestial = 9,
}

---------------------------------------------------------------- ตัวช่วย
local status = "ปิดอยู่"
local function setStatus(text)
    status = text
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

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

local function waitFor(timeout, check)
    local t = os.clock()
    while alive() and os.clock() - t < timeout do
        if check() then return true end
        task.wait(0.1)
    end
    return false
end

---------------------------------------------------------------- แท่นชาร์จ
-- หาพื้นที่ชื่อมีคำว่า charge ในแมพ หรือใช้จุดที่ผู้เล่นบันทึกไว้
local function findChargeSpot()
    if env.DashChargeSpot then
        return env.DashChargeSpot
    end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:lower():find("charge", 1, true) then
            return CFrame.new(d.Position + Vector3.new(0, 4, 0))
        end
    end
    return nil
end

-- เปอร์เซ็นต์บนหลอด "กำลังชาร์จ... 47%" (nil = อ่านไม่ได้)
local chargeLabel
local function readCharge()
    if not (chargeLabel and chargeLabel.Parent and isShown(chargeLabel)) then
        chargeLabel = nil
        for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if d:IsA("TextLabel") and isShown(d) and d.Text:match("^%s*%d+%s*%%%s*$") then
                chargeLabel = d
                break
            end
        end
    end
    local n = chargeLabel and tonumber(chargeLabel.Text:match("(%d+)%s*%%"))
    return n
end

local function setShift(down)
    VirtualInputManager:SendKeyEvent(down, Enum.KeyCode.LeftShift, false, game)
end

-- ชาร์จ -> บิน -> รอจนหยุด -> กลับแท่นชาร์จ
local dashCount = 0
local function dashRound()
    local spot = findChargeSpot()
    local hrp = getRoot()
    if not (spot and hrp) then
        setStatus("หาแท่นชาร์จไม่เจอ: ไปยืนที่แท่นแล้วกด บันทึกจุดแท่นชาร์จ")
        task.wait(2)
        return
    end

    -- กลับไปยืนที่แท่นชาร์จ
    if (hrp.Position - spot.Position).Magnitude > 8 then
        hrp.CFrame = spot
        task.wait(1)
    end

    -- ชาร์จ
    setStatus("กำลังชาร์จ...")
    setShift(true)
    local full = waitFor(settings.chargeTimeout, function()
        local n = readCharge()
        if n then setStatus(("กำลังชาร์จ... %d%%"):format(n)) end
        return n ~= nil and n >= 100
    end)
    task.wait(0.2)
    setShift(false)
    if not alive() then return end
    setStatus(full and "ชาร์จเต็ม! บิน" or "ครบเวลาชาร์จ ปล่อยเลย")

    -- รอเริ่มบิน (เคลื่อนออกจากแท่นเกิน 40 studs)
    hrp = getRoot()
    if not hrp then return end
    local startPos = hrp.Position
    if not waitFor(10, function()
        local r = getRoot()
        return r and (r.Position - startPos).Magnitude > 40
    end) then
        setStatus("ไม่ได้บิน (ชาร์จไม่ติด?) ลองใหม่")
        task.wait(1)
        return
    end

    -- รอจนบินจบ (ไม่ขยับเกิน 1 stud ติดกัน 2 วิ)
    setStatus("กำลังบิน...")
    local lastPos, still = getRoot().Position, os.clock()
    waitFor(90, function()
        local r = getRoot()
        if not r then return false end
        if (r.Position - lastPos).Magnitude > 1 then
            lastPos, still = r.Position, os.clock()
        end
        return os.clock() - still > 2
    end)
    dashCount += 1
    setStatus(("บินจบ (รอบที่ %d)"):format(dashCount))
    task.wait(2) -- รอเกมให้ตัวละคร
end

---------------------------------------------------------------- วางตัวละครที่แข็งแกร่งสุด
-- ตัวละครในกระเป๋า = Tool ใน Backpack
-- ความแรง = Revenue / BaseRevenue (เงินต่อวินาที) ถ้าไม่มีใช้ Rarity
local function toolPower(tool)
    for _, key in ipairs({ "Revenue", "BaseRevenue", "Income", "Value" }) do
        local v = tool:GetAttribute(key)
        if typeof(v) == "number" then return v end
    end
    local rarity = tool:GetAttribute("Rarity")
    if rarity and RARITY_ORDER[rarity] then
        return RARITY_ORDER[rarity]
    end
    return nil
end

local function isCharacterTool(tool)
    if not tool:IsA("Tool") then return false end
    return tool:GetAttribute("IsBrainrot") == true or toolPower(tool) ~= nil
end

local function getCharacterTools()
    local list = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, t in ipairs(backpack:GetChildren()) do
            if isCharacterTool(t) then table.insert(list, t) end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if isCharacterTool(t) then table.insert(list, t) end
        end
    end
    table.sort(list, function(a, b)
        return (toolPower(a) or 0) > (toolPower(b) or 0)
    end)
    return list
end

local function getMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    return plots and plots:FindFirstChild("Base_" .. LocalPlayer.UserId)
end

-- แท่นที่มีตัวละครวางอยู่แล้ว (WorkingBrainrots มี attribute Place = ชื่อเต็มของแท่น)
local function occupiedStands()
    local used = {}
    local folder = workspace:FindFirstChild("WorkingBrainrots")
    if folder then
        for _, b in ipairs(folder:GetChildren()) do
            local place = b:GetAttribute("Place")
            if place then used[place] = true end
        end
    end
    return used
end

local function getEmptyStands()
    local plot = getMyPlot()
    if not plot then return {}, "หาฐานของเราไม่เจอ (Plots.Base_" .. LocalPlayer.UserId .. ")" end
    local used = occupiedStands()
    local empty = {}
    for _, d in ipairs(plot:GetDescendants()) do
        if d:IsA("Model") and d.Name:match("^ModelStand") and not used[d:GetFullName()] then
            local prompt = d:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and prompt.Enabled then
                table.insert(empty, { stand = d, prompt = prompt })
            end
        end
    end
    return empty
end

local function triggerPrompt(prompt)
    if typeof(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
        return
    end
    prompt:InputHoldBegin()
    task.wait(prompt.HoldDuration + 0.1)
    prompt:InputHoldEnd()
end

local placedCount = 0
local function placeStrongest()
    local tools = getCharacterTools()
    if #tools == 0 then
        return 0, "ไม่มีตัวละครในกระเป๋า"
    end
    local empty, err = getEmptyStands()
    if err then return 0, err end
    if #empty == 0 then
        return 0, "แท่นเต็มแล้ว"
    end

    local hrp, hum = getRoot(), getHumanoid()
    if not (hrp and hum) then return 0, "ไม่มีตัวละคร" end
    local back = hrp.CFrame
    local placed = 0
    for i, slot in ipairs(empty) do
        local tool = tools[i]
        if not tool or not alive() then break end
        setStatus(("วาง %s (%s)"):format(tool.Name, tostring(toolPower(tool) or "?")))
        hum:EquipTool(tool)
        task.wait(0.3)
        hrp = getRoot()
        if not hrp then break end
        hrp.CFrame = slot.stand:GetPivot() + Vector3.new(0, 3, 0)
        task.wait(0.4)
        triggerPrompt(slot.prompt)
        task.wait(0.6)
        placed += 1
    end
    hum:UnequipTools()
    hrp = getRoot()
    if hrp then hrp.CFrame = back end
    placedCount += placed
    return placed
end

---------------------------------------------------------------- รีเบิร์ธ
-- ReplicatedStorage.RemoteGUI.URebirth:FireServer() (ดักจาก Remote Spy ตอนกดรีเบิร์ธ)
local rebirthCount = 0
local function rebirth()
    local folder = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteGUI")
    local remote = folder and folder:FindFirstChild("URebirth")
    if not remote then
        setStatus("หา RemoteGUI.URebirth ไม่เจอ")
        return false
    end
    remote:FireServer()
    rebirthCount += 1
    return true
end

-- อ่านหลอดในหน้าต่างการเกิดใหม่ "ระดับพลัง 53 / 1K" -> พลังตอนนี้, พลังที่ต้องการ
local SUFFIX = {
    K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18,
    SX = 1e21, SP = 1e24, OC = 1e27, NO = 1e30, DC = 1e33,
}
local function parseNumber(text)
    if not text then return nil end
    local num, suffix = text:gsub(",", ""):match("([%d%.]+)%s*(%a*)")
    num = tonumber(num)
    if not num then return nil end
    if suffix and suffix ~= "" then
        local mult = SUFFIX[suffix:upper()]
        if not mult then return nil end
        num *= mult
    end
    return num
end

local rebirthLabel
local function readRebirthBar()
    if not (rebirthLabel and rebirthLabel.Parent) then
        rebirthLabel = nil
        for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text:find("ระดับพลัง", 1, true) and d.Text:find("/", 1, true) then
                rebirthLabel = d
                break
            end
        end
    end
    if not rebirthLabel then return nil end
    -- RichText อาจมีแท็ก <b> ปน ลบออกก่อน
    local text = rebirthLabel.Text:gsub("<[^>]->", "")
    local have, need = text:match("ระดับพลัง%s*([%d%.,]+%s*%a*)%s*/%s*([%d%.,]+%s*%a*)")
    return parseNumber(have), parseNumber(need)
end

local rebirthInfo = "-"
task.spawn(function()
    while alive() do
        if settings.autoRebirth then
            local have, need = readRebirthBar()
            if not need then
                rebirthInfo = "อ่านหลอดไม่ได้: เปิดหน้าต่างการเกิดใหม่สักครั้ง"
            else
                rebirthInfo = ("พลัง %s / %s"):format(tostring(have), tostring(need))
                if have and have >= need then
                    rebirth()
                    rebirthInfo = "หลอดเต็ม รีเบิร์ธแล้ว!"
                    task.wait(5) -- รอเกมรีเซ็ตพลังและอัปเดตหลอดใหม่
                end
            end
        end
        task.wait(math.max(1, settings.rebirthCheckEvery))
    end
end)

---------------------------------------------------------------- ลูปหลัก
local lastPlace = 0
task.spawn(function()
    while alive() do
        local didSomething = false
        if settings.autoPlace and os.clock() - lastPlace > settings.placeEvery then
            lastPlace = os.clock()
            local n, why = placeStrongest()
            if n > 0 then
                setStatus(("วางตัวละครแล้ว %d ตัว"):format(n))
            elseif why then
                setStatus("วางตัวละคร: " .. why)
            end
            didSomething = true
        end
        if settings.autoDash then
            dashRound()
            didSomething = true
        end
        if not didSomething then
            if not settings.autoDash and not settings.autoPlace then
                setStatus("ปิดอยู่")
            end
            task.wait(0.5)
        end
    end
    setShift(false)
end)

-- กันโดนเตะ AFK
local VirtualUser = game:GetService("VirtualUser")
local afkConn = LocalPlayer.Idled:Connect(function()
    if settings.antiAfk and alive() then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

---------------------------------------------------------------- หน้าต่าง (Fluent)
local FLUENT_URL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
local FLUENT_CACHE = "AutoFish/fluent.lua" -- ใช้ไฟล์เดียวกับตัวตกปลา
local function loadFluent(useCache)
    local canCache = typeof(readfile) == "function" and typeof(writefile) == "function"
        and typeof(isfile) == "function"
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
local ok, Fluent = pcall(loadFluent, true)
if not ok or typeof(Fluent) ~= "table" then
    ok, Fluent = pcall(loadFluent, false)
end
if not ok or typeof(Fluent) ~= "table" then
    warn("[DashFarm] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

if env.DashFarmFluent then
    pcall(function() env.DashFarmFluent:Destroy() end)
end
env.DashFarmFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "ฟาร์มพลัง",
    SubTitle = "Dash Farm",
    TabWidth = 150,
    Size = UDim2.fromOffset(560, 420),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})
local Tabs = {
    main = Window:AddTab({ Title = "หลัก", Icon = "zap" }),
    chars = Window:AddTab({ Title = "ตัวละคร", Icon = "users" }),
    safe = Window:AddTab({ Title = "ความปลอดภัย", Icon = "shield" }),
}

-- หลัก
local dashSection = Tabs.main:AddSection("ชาร์จ + บิน")
dashSection:AddToggle("DFDash", { Title = "ชาร์จและบินอัตโนมัติ", Default = false })
    :OnChanged(function(v) settings.autoDash = v end)
local statusPara = dashSection:AddParagraph({ Title = "สถานะ", Content = status })
dashSection:AddInput("DFChargeTimeout", {
    Title = "ชาร์จนานสุด (วินาที)",
    Default = tostring(settings.chargeTimeout),
    Numeric = true,
    Finished = true,
    Callback = function(v) settings.chargeTimeout = tonumber(v) or settings.chargeTimeout end,
})
dashSection:AddButton({
    Title = "บันทึกจุดแท่นชาร์จ",
    Description = "ยืนบนแท่นชาร์จแล้วกด (ใช้ตอนสคริปต์หาแท่นเองไม่เจอ)",
    Callback = function()
        local hrp = getRoot()
        if hrp then
            env.DashChargeSpot = hrp.CFrame
            Fluent:Notify({ Title = "บันทึกแล้ว", Content = "จุดแท่นชาร์จ", Duration = 4 })
        end
    end,
})

local rebirthSection = Tabs.main:AddSection("รีเบิร์ธ")
rebirthSection:AddToggle("DFRebirth", {
    Title = "รีเบิร์ธอัตโนมัติเมื่อหลอดเต็ม",
    Description = "ดูหลอด \"ระดับพลัง X / Y\" ในหน้าต่างการเกิดใหม่ เต็มเมื่อไหร่รีเบิร์ธให้",
    Default = false,
}):OnChanged(function(v) settings.autoRebirth = v end)
rebirthSection:AddButton({
    Title = "รีเบิร์ธตอนนี้",
    Callback = function()
        if rebirth() then
            Fluent:Notify({ Title = "รีเบิร์ธ", Content = "ส่งคำสั่งรีเบิร์ธแล้ว", Duration = 4 })
        end
    end,
})

-- ตัวละคร
local charSection = Tabs.chars:AddSection("วางตัวที่แข็งแกร่งสุด")
charSection:AddToggle("DFPlace", {
    Title = "วางตัวละครอัตโนมัติ",
    Description = "เจอแท่นว่างในฐาน เอาตัวที่เงินต่อวินาทีสูงสุดไปวาง",
    Default = false,
}):OnChanged(function(v) settings.autoPlace = v end)
charSection:AddButton({
    Title = "วางตอนนี้เลย",
    Callback = function()
        task.spawn(function()
            local n, why = placeStrongest()
            Fluent:Notify({
                Title = "วางตัวละคร",
                Content = n > 0 and ("วางแล้ว %d ตัว"):format(n) or (why or "ไม่ได้วาง"),
                Duration = 5,
            })
        end)
    end,
})
local charsPara = charSection:AddParagraph({ Title = "ในกระเป๋า (เรียงจากแรงสุด)", Content = "-" })

-- ความปลอดภัย
local afkSection = Tabs.safe:AddSection("กันโดนเตะ")
afkSection:AddToggle("DFAfk", { Title = "กันโดนเตะ AFK", Default = false })
    :OnChanged(function(v) settings.antiAfk = v end)

Window:SelectTab(1)

-- อัปเดตข้อความในหน้าต่าง
task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            statusPara:SetDesc(("%s\nบินแล้ว %d รอบ  •  วางตัวละครแล้ว %d ตัว  •  รีเบิร์ธ %d ครั้ง\nรีเบิร์ธ: %s")
                :format(status, dashCount, placedCount, rebirthCount, rebirthInfo))
        end)
        local lines = {}
        for i, t in ipairs(getCharacterTools()) do
            if i > 8 then break end
            table.insert(lines, ("%d. %s  (%s)"):format(i, t.Name, tostring(toolPower(t) or "?")))
        end
        pcall(function()
            charsPara:SetDesc(#lines > 0 and table.concat(lines, "\n") or "ไม่เจอตัวละครในกระเป๋า")
        end)
        task.wait(1)
    end
    -- ปิดหน้าต่าง = หยุดทุกอย่าง
    if alive() then
        env.DashFarmRun += 1
    end
    setShift(false)
    afkConn:Disconnect()
end)
