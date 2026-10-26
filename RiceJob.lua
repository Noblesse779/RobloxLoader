-- เควสปลูกข้าว (ลุงหมา) อัตโนมัติ
-- อ่านจากโค้ดเกม (PlayerScripts.RiceQuestSystem.RiceQuestClient + RiceQuestConfig):
--   คุย: ProximityPrompt workspace["ลุงหมา"].Head.RiceQuestPrompt -> Remotes.OpenDialogue { kind, token }
--        kind = "Question" -> Request("Accept", token) -> { ok, token } -> Request("FinishIntro", token) = ได้ข้าว 10 ต้น
--        kind = "Reward" (ได้เงิน) / อื่นๆ = ยังมีข้าวเหลือ (remaining)
--   ปลูก: ถือ Tool ข้าว (Attribute RiceQuestTool + InventoryOwner) ยืนในแปลง workspace.RiceZone -> Request("UseRice")
--         ห่างต้นอื่น >= 3 studs, ระหว่างปลูกห้ามขยับเกิน 4 studs, LocalPlayer.RiceActionBusy = กำลังทำท่า
--   เก็บ: ต้นใน workspace.RiceCrops ที่ OwnerUserId = เรา และ ReadyAt <= เวลาเซิร์ฟเวอร์ -> Request("UseRice", ต้น) ในระยะ 7

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.RiceRun = (env.RiceRun or 0) + 1
local RUN = env.RiceRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.RiceRun == RUN
end

local System = ReplicatedStorage:WaitForChild("RiceQuestSystem")
local Config = require(System:WaitForChild("RiceQuestConfig"))
local Remotes = System:WaitForChild("Remotes")
local RiceCrops = workspace:WaitForChild("RiceCrops")

local status = "-"
local auto = { on = false, planted = 0, harvested = 0 }

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function waitFor(timeout, check)
    local t = os.clock() + timeout
    while os.clock() < t do
        if check() then return true end
        task.wait(0.1)
    end
    return check()
end

local function request(action, arg)
    local ok, res = pcall(function() return Remotes.Request:InvokeServer(action, arg) end)
    if ok and type(res) == "table" then return res end
    return { ok = false, message = ok and "-" or tostring(res) }
end

-- เซิร์ฟเวอร์ส่งมาตอนกดคุยกับลุงหมา
local dialogue = { data = nil, at = 0 }
local conn = Remotes.OpenDialogue.OnClientEvent:Connect(function(d)
    if type(d) == "table" then dialogue.data, dialogue.at = d, os.clock() end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    conn:Disconnect()
end)

---------------------------------------------------------------- ข้าวในกระเป๋า / ต้นข้าวของเรา
local function riceTools()
    local list = {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("RiceQuestTool") == true
                    and t:GetAttribute("InventoryOwner") == LocalPlayer.UserId then
                    table.insert(list, t)
                end
            end
        end
    end
    return list
end

-- ข้าวอยู่ในกระเป๋าของเกม (ไม่ใช่ Backpack) ต้องเอาออกมาไว้ช่องลัดก่อนถึงจะกลายเป็น Tool
-- เกมส่ง InventorySystem.Remotes.SetHotbar:FireServer({ ชื่อของในช่องลัดทั้งหมด })
-- ส่งรายการเดิมที่อยู่ในช่องลัด (Tool ที่มีอยู่) + "Rice" จะได้ไม่ไปลบของอื่นออกจากช่องลัด
local function ensureRiceTool()
    if #riceTools() > 0 then return true end
    local inv = ReplicatedStorage:FindFirstChild("InventorySystem")
    local remote = inv and inv:FindFirstChild("Remotes") and inv.Remotes:FindFirstChild("SetHotbar")
    if not remote then return false end
    local names, seen = {}, {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and not seen[t.Name] then
                    seen[t.Name] = true
                    table.insert(names, t.Name)
                end
            end
        end
    end
    if not seen[Config.ToolName] then table.insert(names, Config.ToolName) end
    status = "เอาข้าวออกมาไว้ช่องลัด..."
    remote:FireServer(names)
    return waitFor(3, function() return #riceTools() > 0 end)
end

local function cropPart(model)
    local p = model:FindFirstChild("Handle") or model:FindFirstChildWhichIsA("BasePart", true)
    return p and p:IsA("BasePart") and p or nil
end

-- ต้นของเรา: { model, part, ready, left }
local function myCrops()
    local now = workspace:GetServerTimeNow()
    local list = {}
    for _, m in ipairs(RiceCrops:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            local part = cropPart(m)
            local readyAt = m:GetAttribute("ReadyAt") or math.huge
            if part then
                table.insert(list, {
                    model = m,
                    part = part,
                    ready = readyAt <= now and not m:GetAttribute("Harvesting"),
                    left = math.max(0, readyAt - now),
                })
            end
        end
    end
    return list
end

local function busy()
    return LocalPlayer:GetAttribute("RiceActionBusy") == true
end

---------------------------------------------------------------- ย้ายตัว (เดินเท้าเท่านั้น)
local function groundAt(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, RiceCrops }
    params.IgnoreWater = true -- นาข้าวมีน้ำ ยืนบนดินใต้น้ำ
    local hit = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
    return hit and hit.Position
end

local function moveTo(pos)
    local hrp = getRoot()
    if not hrp then return false end
    if LocalPlayer:FindFirstChild("BuffaloRideMount") and LocalPlayer.BuffaloRideMount.Value then
        status = "ลงจากช้างก่อน (กด Spacebar)"
        return false
    end
    local ground = groundAt(pos) or pos
    hrp.CFrame = CFrame.new(ground + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.Position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.35)
    return true
end

---------------------------------------------------------------- คุยกับลุงหมา (รับข้าว / รับเงิน)
local function npc()
    return workspace:FindFirstChild(Config.NpcName)
end

local function talk()
    local model = npc()
    local head = model and model:FindFirstChild("Head")
    local prompt = head and head:FindFirstChild("RiceQuestPrompt")
    if not prompt then
        status = "หาลุงหมาไม่เจอ"
        return false
    end
    -- ยืนห่างหัว 5 studs (ต้องอยู่ในระยะคุย 10 / 14)
    local hrp = getRoot()
    if not hrp then return false end
    local away = hrp.Position - head.Position
    away = Vector3.new(away.X, 0, away.Z)
    away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
    if (hrp.Position - head.Position).Magnitude > 8 then
        if not moveTo(head.Position + away * 5) then return false end
    end
    local askedAt = os.clock()
    status = "คุยกับลุงหมา..."
    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
    end
    if not waitFor(4, function() return dialogue.at >= askedAt end) then
        status = "กดคุยแล้วลุงหมาไม่ตอบ"
        return false
    end
    local d = dialogue.data
    if d.kind ~= "Question" then
        status = d.kind == "Reward" and ("ได้เงินจากลุงหมา " .. tostring(d.amount) .. " บาท")
            or ("ลุงหมา: ยังมีข้าวเหลือ " .. tostring(d.remaining or "?") .. " ต้น")
        return d.kind == "Reward"
    end
    local res = request("Accept", d.token)
    if not res.ok then
        status = "รับข้าวไม่สำเร็จ: " .. tostring(res.message)
        return false
    end
    -- เกมรอลุงพูดจบ 2 ประโยคก่อนส่ง FinishIntro: ลองส่งเลย ไม่ได้ค่อยรอแล้วส่งใหม่
    local fin = request("FinishIntro", res.token)
    if not fin.ok then
        task.wait(Config.IntroLineSeconds * 2 + 0.5)
        fin = request("FinishIntro", res.token)
    end
    if not waitFor(4, function() return #riceTools() > 0 end) then
        status = "รับงานแล้วแต่ข้าวไม่เข้ากระเป๋า: " .. tostring(fin.message)
        return false
    end
    status = "ได้ข้าว " .. #riceTools() .. " ต้นแล้ว"
    return true
end

---------------------------------------------------------------- ปลูก
local function zone()
    local z = workspace:FindFirstChild(Config.ZoneName)
    return z and z:IsA("BasePart") and z or nil
end

-- สุ่มจุดในแปลงที่ห่างต้นอื่นเกินระยะขั้นต่ำ
local function plantSpot()
    local z = zone()
    if not z then return nil end
    local spacing = (Config.MinimumPlantSpacing or 3) + 0.8
    local others = {}
    for _, m in ipairs(RiceCrops:GetChildren()) do
        local p = m:IsA("Model") and cropPart(m)
        if p then table.insert(others, p.Position) end
    end
    local hx, hz = z.Size.X / 2 - 2, z.Size.Z / 2 - 2
    for _ = 1, 60 do
        local spot = (z.CFrame * CFrame.new(math.random() * 2 * hx - hx, 0, math.random() * 2 * hz - hz)).Position
        local ok = true
        for _, o in ipairs(others) do
            if (Vector3.new(o.X, 0, o.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < spacing then
                ok = false
                break
            end
        end
        if ok then return spot end
    end
end

local function plantOne()
    local tool = riceTools()[1]
    if not tool then return false end
    local spot = plantSpot()
    if not spot then
        status = "หาที่ว่างในแปลงไม่เจอ"
        return false
    end
    if not moveTo(spot) then return false end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if tool.Parent ~= LocalPlayer.Character then
        hum:EquipTool(tool)
        task.wait(0.3)
    end
    local before = #riceTools()
    status = "ปลูกข้าว..."
    local res = request("UseRice")
    -- รอท่าปลูกจบ (ห้ามขยับระหว่างนี้)
    waitFor(Config.AnimationTimeout or 12, function() return not busy() end)
    if not res.ok and #riceTools() >= before then
        status = "ปลูกไม่สำเร็จ: " .. tostring(res.message)
        return false
    end
    auto.planted += 1
    status = "ปลูกแล้ว เหลือข้าว " .. #riceTools() .. " ต้น"
    return true
end

---------------------------------------------------------------- เก็บ
local function harvest(crop)
    local hrp = getRoot()
    if not hrp then return false end
    if (hrp.Position - crop.part.Position).Magnitude > (Config.HarvestDistance or 7) - 2 then
        if not moveTo(crop.part.Position + Vector3.new(2, 0, 0)) then return false end
    end
    status = "เก็บข้าว..."
    local res = request("UseRice", crop.model)
    waitFor(Config.AnimationTimeout or 12, function() return not busy() end)
    if not res.ok and crop.model.Parent then
        status = "เก็บไม่สำเร็จ: " .. tostring(res.message)
        return false
    end
    auto.harvested += 1
    status = "เก็บแล้ว"
    return true
end

---------------------------------------------------------------- วนอัตโนมัติ
local function autoLoop()
    while alive() and auto.on do
        if busy() then
            task.wait(0.3)
        else
            local crops = myCrops()
            local ready
            for _, c in ipairs(crops) do
                if c.ready then ready = c break end
            end
            if ready then
                if not harvest(ready) then task.wait(1) end
            elseif #riceTools() > 0 or (LocalPlayer:GetAttribute("RiceQuestActive") == true and ensureRiceTool()) then
                if not plantOne() then task.wait(1) end
            elseif #crops == 0 and ensureRiceTool() then
                -- ยังมีข้าวในกระเป๋า (เอาออกมาช่องลัดได้) ปลูกต่อรอบหน้า
            elseif #crops == 0 then
                -- ปลูก/เก็บหมดแล้ว: ไปหาลุงหมา รับเงิน/รับข้าวรอบใหม่
                if not talk() then task.wait(3) end
                task.wait(1)
            else
                local soon = math.huge
                for _, c in ipairs(crops) do soon = math.min(soon, c.left) end
                status = ("รอข้าวโต %d ต้น (ต้นแรกอีก %d วิ)"):format(#crops, math.ceil(soon))
                task.wait(1)
            end
        end
        task.wait(0.2)
    end
end

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
    warn("[RiceJob] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

if env.RiceFluent then
    pcall(function() env.RiceFluent:Destroy() end)
end
env.RiceFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "ปลูกข้าว",
    SubTitle = "ลุงหมา",
    TabWidth = 150,
    Size = UDim2.fromOffset(540, 340),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})
local Tabs = {
    main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
}

local section = Tabs.main:AddSection("ปลูกข้าว")
section:AddToggle("RiceAuto", {
    Title = "ปลูกข้าวอัตโนมัติ",
    Description = "รับข้าวจากลุงหมา -> ปลูกในแปลงจนหมด -> รอโตแล้วเก็บ -> รับรอบใหม่ วนไปเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) end
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

Window:SelectTab(1)

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local crops = myCrops()
            local ready = 0
            for _, c in ipairs(crops) do
                if c.ready then ready += 1 end
            end
            statusPara:SetDesc(("%s\nข้าวในกระเป๋า: %d  •  ต้นในแปลง: %d (พร้อมเก็บ %d)\nปลูกไปแล้ว %d  •  เก็บไปแล้ว %d"):format(
                status, #riceTools(), #crops, ready, auto.planted, auto.harvested))
        end)
        task.wait(0.5)
    end
    if alive() then env.RiceRun += 1 end
end)
