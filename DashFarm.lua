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
    autoUpgrade = false,
    escapeChase = false,  -- มีตัวไล่ -> วาร์ปกลับฐานทันที
    chaseResult = false,  -- (ทดลอง) มีตัวไล่ -> ส่ง ChaseResult(true) บอกว่าหนีรอดเลย
    returnToBase = true,  -- บินจบแล้ววาร์ปกลับฐานก่อน (ส่งตัวละครที่ได้) แล้วค่อยไปแท่นชาร์จ
    upgradePick = {},        -- แท่นที่เลือกให้อัพก่อน: [ชื่อเต็มของแท่น] = true
    upgradeOnlyPicked = false, -- true = อัพเฉพาะตัวที่เลือก
    upgradeEvery = 5, -- กดป้ายอัพเกรดทุกกี่วิ (เงินไม่พอ เกมไม่ให้อัพเอง)
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

-- บินจบแล้วทำอะไรต่อ (กำหนดจริงในส่วนหนีตัวไล่ ข้างล่าง)
local afterDash = function() end

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
    afterDash()
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
            -- ปุ่ม "สถานที่" (E) เกมสร้าง/เปิดตอนถือตัวละครอยู่ เลยไม่หาปุ่มตรงนี้
            table.insert(empty, { stand = d })
        end
    end
    return empty
end

-- กดปุ่มในแมพ ลองทีละวิธีจนตัวละครหายจากมือ (= วางสำเร็จ)
local function pressKey(key, hold)
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait(hold)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
end

local function triggerPrompt(prompt, tool)
    local function placed()
        return tool.Parent == nil
            or not (tool:IsDescendantOf(LocalPlayer.Character or game) or tool:IsDescendantOf(LocalPlayer))
    end
    local hold = (prompt.HoldDuration or 0) + 0.15

    -- 1) คำสั่งของ executor
    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
        if waitFor(0.8, placed) then return true end
    end
    -- 2) กดปุ่ม E จริง (ปุ่ม "สถานที่" ขึ้นบนจออยู่แล้ว)
    pressKey(prompt.KeyboardKeyCode or Enum.KeyCode.E, hold)
    if waitFor(0.8, placed) then return true end
    -- 3) สั่งกดผ่าน prompt โดยตรง
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(hold)
        prompt:InputHoldEnd()
    end)
    return waitFor(0.8, placed)
end

-- ปุ่มที่ "ขึ้นบนจอ" ตอนนี้ (ตัวเดียวกับที่ผู้เล่นเห็นแล้วกด E)
local ProximityPromptService = game:GetService("ProximityPromptService")
local shownPrompt
ProximityPromptService.PromptShown:Connect(function(prompt)
    shownPrompt = prompt
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
    if shownPrompt == prompt then
        shownPrompt = nil
    end
end)

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
        shownPrompt = nil
        hrp.CFrame = slot.stand:GetPivot() + Vector3.new(0, 3, 0)
        -- รอปุ่ม "สถานที่" ขึ้นบนจอ แล้วกดปุ่มตัวนั้นเลย
        setStatus("รอปุ่มสถานที่ขึ้น: " .. slot.stand.Name)
        if waitFor(2, function() return shownPrompt ~= nil end) then
            setStatus(("กดปุ่ม \"%s\""):format(shownPrompt.ActionText))
            if triggerPrompt(shownPrompt, tool) then
                placed += 1
            else
                setStatus("ปุ่มขึ้นแต่วางไม่ได้ที่ " .. slot.stand.Name)
            end
            task.wait(0.4)
        else
            setStatus("ปุ่มวางไม่ขึ้นที่ " .. slot.stand.Name)
            task.wait(0.3)
        end
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

---------------------------------------------------------------- หนีตัวไล่
-- ได้ตัวละครแล้วบางครั้งมีตัวอนิเมะไล่ยิงพลังใส่ ต้องกลับถึงฐานก่อนโดนยิง
-- ตัวไล่น่าจะอยู่ใน workspace.AI (โฟลเดอร์ที่เห็นในรายชื่อแมพ)
-- กลับถึงฐานแล้วเกมส่ง Events.ChaseResult(true) เอง
local function baseCFrame()
    local plot = getMyPlot()
    if not plot then return nil end
    return plot:GetPivot() + Vector3.new(0, 6, 0)
end

local function goToBase()
    local hrp, base = getRoot(), baseCFrame()
    if hrp and base then
        hrp.CFrame = base
        return true
    end
    return false
end

local function chaserActive()
    local ai = workspace:FindFirstChild("AI")
    if not ai then return false end
    local hrp = getRoot()
    for _, m in ipairs(ai:GetChildren()) do
        if m:IsA("Model") then
            local pos = m:GetPivot().Position
            -- อยู่ใกล้เรา (ไล่เราอยู่) ไม่นับตัวที่ยืนเฉยๆ ไกลๆ
            if not hrp or (pos - hrp.Position).Magnitude < 400 then
                return true, m
            end
        end
    end
    return false
end

local chaseEscapes = 0
local function sendChaseResult()
    local events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
    local remote = events and events:FindFirstChild("ChaseResult")
    if remote then
        remote:FireServer(true)
        return true
    end
    return false
end

afterDash = function()
    if settings.returnToBase and goToBase() then
        setStatus("บินจบ วาร์ปกลับฐานส่งตัวละคร")
        task.wait(2)
    end
end

task.spawn(function()
    local handled = false
    while alive() do
        local active, chaser = chaserActive()
        if active and not handled and (settings.escapeChase or settings.chaseResult) then
            handled = true
            chaseEscapes += 1
            if settings.escapeChase then
                goToBase()
                setStatus("มีตัวไล่ (" .. chaser.Name .. ") วาร์ปกลับฐานแล้ว")
            end
            if settings.chaseResult then
                task.wait(0.5)
                sendChaseResult()
            end
        elseif not active then
            handled = false
        end
        task.wait(0.2)
    end
end)

---------------------------------------------------------------- อัพเกรดตัวละคร
-- ป้ายเหลือง "$150  เลเวล 1 > เลเวล 2" หน้าแท่น ต้องเอาเมาส์คลิก (ไม่มี remote ให้ดัก)
-- น่าจะเป็น ClickDetector หรือปุ่มบน SurfaceGui
local function guiText(root)
    local parts = {}
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
            table.insert(parts, d.Text)
        end
    end
    return table.concat(parts, " ")
end

local function costOf(text)
    -- "$21.6K" -> 21600
    local num = text:match("%$%s*([%d%.,]+%s*%a*)")
    return num and parseNumber(num) or math.huge
end

-- รวบรวมป้ายอัพเกรดรอบฐานของเรา: { kind, target, part, cost }
-- หาทั้ง ClickDetector และปุ่มบน SurfaceGui/BillboardGui ที่อยู่ในรัศมีของฐาน
-- (ป้ายอาจไม่ได้อยู่ในโฟลเดอร์ฐานตรงๆ) ค้นทั้งแมพหนัก เลยเก็บผลไว้ 30 วิ
local upgradeCache, upgradeCacheAt, upgradeDebug = nil, 0, ""
local function findUpgradeTargets()
    if upgradeCache and os.clock() - upgradeCacheAt < 30 then
        return upgradeCache
    end
    local plot = getMyPlot()
    if not plot then return nil, "หาฐานของเราไม่เจอ" end

    -- ทางตรง: Plots.Base_<id>.ModelStands(_Floor2...).ModelStandN.Upgrade.ClickDetector
    local direct = {}
    for _, group in ipairs(plot:GetChildren()) do
        if group.Name:match("^ModelStands") then
            for _, stand in ipairs(group:GetChildren()) do
                local up = stand:FindFirstChild("Upgrade")
                local cd = up and up:FindFirstChildWhichIsA("ClickDetector", true)
                if cd then
                    local text = guiText(up)
                    table.insert(direct, {
                        kind = "click", target = cd,
                        part = cd.Parent:IsA("BasePart") and cd.Parent or up:FindFirstChildWhichIsA("BasePart", true),
                        cost = costOf(text), text = text,
                        stand = stand, standKey = stand:GetFullName(),
                    })
                end
            end
        end
    end
    if #direct > 0 then
        table.sort(direct, function(x, y) return x.cost < y.cost end)
        upgradeDebug = ("ป้ายอัพเกรด %d แท่น (ModelStand.Upgrade)"):format(#direct)
        upgradeCache, upgradeCacheAt = direct, os.clock()
        return direct
    end

    -- สำรอง: ค้นรอบฐาน
    local center = plot:GetPivot().Position
    local radius = plot:GetExtentsSize().Magnitude / 2 + 25
    local function near(part)
        return part and part:IsA("BasePart") and (part.Position - center).Magnitude <= radius
    end

    local list, seen = {}, {}
    local clickCount, guiCount = 0, 0

    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ClickDetector") then
            local part = d.Parent
            if near(part) and not seen[d] then
                clickCount += 1
                seen[d] = true
                local holder = part.Parent or part
                local text = guiText(part) .. " " .. guiText(holder)
                table.insert(list, { kind = "click", target = d, part = part, cost = costOf(text), text = text })
            end
        end
    end

    local function scanGui(root)
        for _, g in ipairs(root:GetDescendants()) do
            if g:IsA("SurfaceGui") or g:IsA("BillboardGui") then
                local part = g.Adornee or g:FindFirstAncestorWhichIsA("BasePart")
                if near(part) then
                    local text = guiText(g)
                    if text:find("เลเวล", 1, true) or text:find(">", 1, true) then
                        guiCount += 1
                        local button = g:FindFirstChildWhichIsA("GuiButton", true)
                        local item = { kind = button and "button" or "partclick", target = button,
                            part = part, cost = costOf(text), text = text }
                        if not seen[button or part] then
                            seen[button or part] = true
                            table.insert(list, item)
                        end
                    end
                end
            end
        end
    end
    scanGui(workspace)
    scanGui(LocalPlayer.PlayerGui)

    table.sort(list, function(x, y) return x.cost < y.cost end) -- ถูกสุดก่อน
    upgradeDebug = ("ClickDetector %d  •  ป้ายข้อความ %d"):format(clickCount, guiCount)
    if list[1] then
        upgradeDebug ..= "\nตัวอย่าง: " .. list[1].part:GetFullName()
    end
    upgradeCache, upgradeCacheAt = list, os.clock()
    return list
end

local function clickPart(part)
    -- คลิกเมาส์ที่ตำแหน่งชิ้นส่วนบนจอ (ใช้เมื่อไม่มีคำสั่งของ executor)
    local cam = workspace.CurrentCamera
    local pos, onScreen = cam:WorldToViewportPoint(part.Position)
    if not onScreen then return false end
    local inset = game:GetService("GuiService"):GetGuiInset()
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y + inset.Y, 0, true, game, 1)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y + inset.Y, 0, false, game, 1)
    return true
end

local function pressUpgrade(item)
    if item.kind == "partclick" then
        return clickPart(item.part)
    end
    if item.kind == "click" then
        if typeof(fireclickdetector) == "function" then
            return pcall(fireclickdetector, item.target)
        end
        return clickPart(item.part)
    end
    -- ปุ่มบน SurfaceGui
    local button = item.target
    if typeof(firesignal) == "function" then
        if pcall(firesignal, button.MouseButton1Click) then return true end
    end
    if typeof(getconnections) == "function" then
        local ok = pcall(function()
            for _, c in ipairs(getconnections(button.MouseButton1Click)) do
                c:Fire()
            end
        end)
        if ok then return true end
    end
    return clickPart(item.part)
end

local upgradeCount = 0
local upgradeInfo = "-"
-- ตัวละครที่วางอยู่บนแท่น: WorkingBrainrots มี attribute Place = ชื่อเต็มของแท่น
local function placedByStand()
    local map = {}
    local folder = workspace:FindFirstChild("WorkingBrainrots")
    if folder then
        for _, b in ipairs(folder:GetChildren()) do
            local place = b:GetAttribute("Place")
            if place then map[place] = b end
        end
    end
    return map
end

local function shortNumber(n)
    if typeof(n) ~= "number" then return "?" end
    local units = { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
    for _, u in ipairs(units) do
        if n >= u[1] then
            return (("%.2f%s"):format(n / u[1], u[2]):gsub("%.?0+(%a)$", "%1"))
        end
    end
    return tostring(math.floor(n))
end

-- รายการตัวบนแท่นสำหรับเมนูเลือก: { label, key }
local function standChoices()
    local list = findUpgradeTargets() or {}
    local placed = placedByStand()
    local out = {}
    for _, item in ipairs(list) do
        if item.standKey then
            local b = placed[item.standKey]
            local name = b and (b:GetAttribute("DisplayName") or b:GetAttribute("BrainrotName") or b.Name)
            local num = item.stand.Name:match("%d+") or "?"
            local floor = item.stand.Name:match("_F(%d+)")
            local standLabel = floor and ("ชั้น %s แท่น %s"):format(floor, num) or ("แท่น " .. num)
            local label
            if b then
                label = ("%s: %s (%s) เลเวล %s • $%s/s"):format(standLabel, tostring(name),
                    tostring(b:GetAttribute("Rarity") or "?"), tostring(b:GetAttribute("Level") or "?"),
                    shortNumber(b:GetAttribute("Revenue")))
            else
                label = standLabel .. ": (ว่าง)"
            end
            table.insert(out, { label = label, key = item.standKey })
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function upgradeAll()
    local list, err = findUpgradeTargets()
    if not list then
        upgradeInfo = err
        return 0
    end
    if #list == 0 then
        upgradeInfo = "ไม่เจอป้ายอัพเกรดรอบฐาน (" .. upgradeDebug .. ")"
        upgradeCache = nil -- ค้นใหม่รอบหน้า
        return 0
    end
    -- เรียง: ตัวที่เลือกก่อน (ถูกสุดก่อน) แล้วค่อยตัวอื่น / หรืออัพเฉพาะตัวที่เลือก
    local picked, others = {}, {}
    for _, item in ipairs(list) do
        if item.standKey and settings.upgradePick[item.standKey] then
            table.insert(picked, item)
        else
            table.insert(others, item)
        end
    end
    local order = picked
    if not settings.upgradeOnlyPicked then
        for _, item in ipairs(others) do table.insert(order, item) end
    elseif #picked == 0 then
        upgradeInfo = "โหมดอัพเฉพาะที่เลือก แต่ยังไม่ได้เลือกตัวไหน"
        return 0
    end

    local pressed = 0
    for _, item in ipairs(order) do
        if not alive() then break end
        if pressUpgrade(item) then pressed += 1 end
        task.wait(0.15)
    end
    upgradeCount += pressed
    upgradeInfo = ("เจอป้าย %d ป้าย  •  เลือกไว้ %d ตัว  •  กดไป %d ครั้ง\n%s")
        :format(#list, #picked, pressed, upgradeDebug)
    return pressed
end

task.spawn(function()
    while alive() do
        if settings.autoUpgrade then
            upgradeAll()
        end
        task.wait(math.max(1, settings.upgradeEvery))
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

local upgradeSection = Tabs.chars:AddSection("อัพเกรดตัวละคร")
upgradeSection:AddToggle("DFUpgrade", {
    Title = "อัพเกรดอัตโนมัติ",
    Description = "กดป้ายเหลืองหน้าแท่นทุกตัว เรียงจากถูกสุด (เงินไม่พอ เกมไม่ให้อัพเอง)",
    Default = false,
}):OnChanged(function(v) settings.autoUpgrade = v end)
upgradeSection:AddButton({
    Title = "อัพเกรดตอนนี้",
    Callback = function()
        task.spawn(function()
            upgradeAll()
            Fluent:Notify({ Title = "อัพเกรด", Content = upgradeInfo, Duration = 5 })
        end)
    end,
})
local upgradePara = upgradeSection:AddParagraph({ Title = "ผลการอัพเกรด", Content = "-" })

-- เลือกตัวที่จะอัพก่อน
local labelToKey = {}
local pickDropdown = upgradeSection:AddDropdown("DFUpgradePick", {
    Title = "ตัวที่จะอัพก่อน (เลือกได้หลายตัว)",
    Description = "ตัวที่เลือกจะถูกอัพก่อนเสมอ",
    Values = {},
    Multi = true,
    Default = {},
})
pickDropdown:OnChanged(function(value)
    local pick = {}
    for label, on in pairs(value or {}) do
        if on and labelToKey[label] then
            pick[labelToKey[label]] = true
        end
    end
    settings.upgradePick = pick
end)

local function refreshPickList()
    local choices = standChoices()
    local labels, keep = {}, {}
    labelToKey = {}
    for _, c in ipairs(choices) do
        table.insert(labels, c.label)
        labelToKey[c.label] = c.key
        if settings.upgradePick[c.key] then
            keep[c.label] = true -- เลเวลเปลี่ยน ชื่อในเมนูเปลี่ยน แต่ยังเลือกแท่นเดิมไว้
        end
    end
    local saved = settings.upgradePick
    pcall(function() pickDropdown:SetValues(labels) end)
    pcall(function() pickDropdown:SetValue(keep) end)
    settings.upgradePick = saved
    return #labels
end

upgradeSection:AddDropdown("DFUpgradeMode", {
    Title = "โหมด",
    Values = { "อัพที่เลือกก่อน แล้วค่อยตัวอื่น", "อัพเฉพาะตัวที่เลือก" },
    Default = 1,
}):OnChanged(function(v)
    settings.upgradeOnlyPicked = v == "อัพเฉพาะตัวที่เลือก"
end)

upgradeSection:AddButton({
    Title = "รีเฟรชรายชื่อตัวบนแท่น",
    Description = "กดหลังวางตัวใหม่ หรือเลเวลเปลี่ยน",
    Callback = function()
        upgradeCache = nil
        local n = refreshPickList()
        Fluent:Notify({ Title = "รายชื่อตัวบนแท่น", Content = ("เจอ %d แท่น"):format(n), Duration = 4 })
    end,
})
task.delay(2, function() pcall(refreshPickList) end)

-- หนีตัวไล่
local chaseSection = Tabs.main:AddSection("หนีตัวไล่ / กลับฐาน")
chaseSection:AddToggle("DFReturnBase", {
    Title = "บินจบแล้ววาร์ปกลับฐาน",
    Description = "ส่งตัวละครที่ได้ถึงฐานก่อน แล้วค่อยไปแท่นชาร์จ (ใช้กับชาร์จอัตโนมัติ)",
    Default = settings.returnToBase,
}):OnChanged(function(v) settings.returnToBase = v end)
chaseSection:AddToggle("DFEscape", {
    Title = "มีตัวไล่ วาร์ปกลับฐานทันที",
    Description = "ตัวอนิเมะไล่ยิงพลังใส่ จะวาร์ปถึงฐานก่อนโดนยิง",
    Default = false,
}):OnChanged(function(v) settings.escapeChase = v end)
chaseSection:AddToggle("DFChaseResult", {
    Title = "(ทดลอง) บอกเซิร์ฟเวอร์ว่าหนีรอดทันที",
    Description = "ส่ง ChaseResult(true) ตอนเจอตัวไล่ ไม่ต้องกลับฐาน (เสี่ยงกว่า)",
    Default = false,
}):OnChanged(function(v) settings.chaseResult = v end)
chaseSection:AddButton({
    Title = "วาร์ปกลับฐานตอนนี้",
    Callback = function()
        if not goToBase() then
            Fluent:Notify({ Title = "กลับฐาน", Content = "หาฐานของเราไม่เจอ", Duration = 4 })
        end
    end,
})

-- ความปลอดภัย
local afkSection = Tabs.safe:AddSection("กันโดนเตะ")
afkSection:AddToggle("DFAfk", { Title = "กันโดนเตะ AFK", Default = false })
    :OnChanged(function(v) settings.antiAfk = v end)

Window:SelectTab(1)

-- อัปเดตข้อความในหน้าต่าง
task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            statusPara:SetDesc(("%s\nบินแล้ว %d รอบ  •  วางตัวละครแล้ว %d ตัว  •  รีเบิร์ธ %d ครั้ง  •  เจอตัวไล่ %d ครั้ง\nรีเบิร์ธ: %s")
                :format(status, dashCount, placedCount, rebirthCount, chaseEscapes, rebirthInfo))
        end)
        local lines = {}
        for i, t in ipairs(getCharacterTools()) do
            if i > 8 then break end
            table.insert(lines, ("%d. %s  (%s)"):format(i, t.Name, tostring(toolPower(t) or "?")))
        end
        pcall(function()
            charsPara:SetDesc(#lines > 0 and table.concat(lines, "\n") or "ไม่เจอตัวละครในกระเป๋า")
        end)
        pcall(function()
            upgradePara:SetDesc(("%s\nกดอัพเกรดไปแล้ว %d ครั้ง"):format(upgradeInfo, upgradeCount))
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
