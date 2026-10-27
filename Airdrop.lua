-- แอร์ดรอป: มีกล่องตกเมื่อไหร่ พักงานอื่น ไปที่กล่อง เปิดมินิเกม ให้ผู้เล่นพิมพ์รหัสเอง แล้วกลับไปทำงานเดิม
-- อ่านจากโค้ดเกม (PlayerScripts.AirdropSystem.AirDropClient + AirdropConfig):
--   กล่องมีปุ่ม E "เปิดมินิเกมส์" (ObjectText "Airdrop") ระยะ 15 studs
--   กดแล้วเซิร์ฟเวอร์ส่ง LES_AirDrop.OpenUI(dropId, model, code, info) = หน้าต่างพิมพ์รหัส
--   ออกห่างกล่องเกิน 15 studs = ออกจากมินิเกม  จบ = LES_AirDrop.CloseUI(dropId, ผล, ...)
--   แข่งกับผู้เล่นคนอื่น (ผู้ชนะ 5 คนแรก) สคริปต์ไม่พิมพ์รหัสให้: พาไปถึงกล่อง + เปิดหน้าต่าง ส่วนพิมพ์รหัสผู้เล่นทำเอง
-- งานอื่นในตัวรวม (ตีหมู / ปลูกข้าว) ดู env.AirdropBusy แล้วพักรอ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.AirdropRun = (env.AirdropRun or 0) + 1
local RUN = env.AirdropRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.AirdropRun == RUN
end
env.AirdropBusy = false

local Net = ReplicatedStorage:WaitForChild("LES_AirDrop")
local PROMPT_RANGE = 15

local status = "-"
local auto = { on = false, walk = false, got = 0, type = false, reset = true } -- type = พิมพ์รหัสให้ / reset = จบแล้วรีตัว

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function waitFor(timeout, check)
    local t = os.clock() + timeout
    while os.clock() < t do
        if check() then return true end
        task.wait(0.1)
    end
    return check()
end

---------------------------------------------------------------- หากล่อง
-- เก็บปุ่มของกล่องไว้ตอนมันโผล่ (ไม่ต้องไล่หาทั้งแมพทุกครั้ง)
local prompts = {}
local function isAirdropPrompt(p)
    if not p:IsA("ProximityPrompt") then return false end
    local text = (p.ActionText .. " " .. p.ObjectText):lower()
    return text:find("มินิเกม", 1, true) ~= nil or text:find("airdrop", 1, true) ~= nil
end
local function track(p)
    if isAirdropPrompt(p) then prompts[p] = true end
end
for _, d in ipairs(workspace:GetDescendants()) do track(d) end
local addConn = workspace.DescendantAdded:Connect(track)

local session = { dropId = nil, openAt = 0, closeAt = 0, result = nil, code = nil, roundAt = 0 }
local conns = {
    addConn,
    Net:WaitForChild("OpenUI").OnClientEvent:Connect(function(dropId, _, code)
        session.dropId, session.openAt = dropId, os.clock()
        session.code, session.roundAt = code, os.clock()
    end),
    -- รอบใหม่ = รหัสใหม่
    Net:WaitForChild("NextRound").OnClientEvent:Connect(function(dropId, code)
        if dropId == session.dropId and code then
            session.code, session.roundAt = code, os.clock()
        end
    end),
    Net:WaitForChild("CloseUI").OnClientEvent:Connect(function(dropId, result)
        if dropId == session.dropId then
            session.closeAt, session.result = os.clock(), result
        end
    end),
}
task.spawn(function()
    while alive() do task.wait(1) end
    for _, c in ipairs(conns) do c:Disconnect() end
    env.AirdropBusy = false
end)

local done = setmetatable({}, { __mode = "k" }) -- กล่องที่ไปแล้ว (ชนะ/แพ้/โดนล็อก) ไม่ไปซ้ำ

local function promptPart(p)
    local parent = p.Parent
    if parent and parent:IsA("Attachment") then parent = parent.Parent end
    if parent and parent:IsA("BasePart") then return parent end
    local model = p:FindFirstAncestorWhichIsA("Model")
    return model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
end

local function currentDrop()
    for p in pairs(prompts) do
        if not p:IsDescendantOf(workspace) then
            prompts[p] = nil
        elseif p.Enabled and not done[p] and promptPart(p) then
            return p
        end
    end
end

local function riding()
    local ref = LocalPlayer:FindFirstChild("BuffaloRideMount")
    return ref and ref.Value ~= nil
end

---------------------------------------------------------------- ไปที่กล่อง
local function goTo(pos)
    local hrp, hum = getRoot(), getHum()
    if not (hrp and hum) then return false end
    local function near()
        local h = getRoot()
        return h and (Vector3.new(pos.X, h.Position.Y, pos.Z) - h.Position).Magnitude <= 8
    end
    if not auto.walk then
        local away = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
        away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
        local stand = pos + away * 5 + Vector3.new(0, 3, 0)
        hrp.CFrame = CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.4)
        return true
    end
    local t = os.clock()
    while alive() and auto.on and os.clock() - t < 120 do
        if near() then
            hum:MoveTo(hrp.Position)
            return true
        end
        local points = { pos }
        local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
        if pcall(function() path:ComputeAsync(hrp.Position, pos) end) and path.Status == Enum.PathStatus.Success then
            points = {}
            for _, wp in ipairs(path:GetWaypoints()) do table.insert(points, wp) end
        end
        for _, wp in ipairs(points) do
            if near() then break end
            local target = typeof(wp) == "Vector3" and wp or wp.Position
            if typeof(wp) ~= "Vector3" and wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
            hum:MoveTo(target)
            local last, lastMove = hrp.Position, os.clock()
            while alive() and os.clock() - lastMove < 1.5 do
                if near() or (Vector3.new(target.X, hrp.Position.Y, target.Z) - hrp.Position).Magnitude < 2 then break end
                if (hrp.Position - last).Magnitude > 0.4 then last, lastMove = hrp.Position, os.clock() end
                task.wait(0.1)
            end
            if os.clock() - lastMove >= 1.5 then
                hum.Jump = true
                break -- ติด: คำนวณทางใหม่
            end
        end
    end
    return near()
end

---------------------------------------------------------------- เปิดมินิเกม รอผู้เล่นพิมพ์รหัส
local function handle(prompt)
    local part = promptPart(prompt)
    if not part then return end
    env.AirdropBusy = true -- งานอื่นพักรอ
    -- กล่องค่อยๆ ร่วงจากฟ้า (~18 วิ) รอให้ลงพื้นก่อน ไม่งั้นวาร์ปไปค้างกลางอากาศ
    status = "แอร์ดรอปกำลังตกจากฟ้า รอลงพื้น..."
    local lastY, still = part.Position.Y, os.clock()
    waitFor(30, function()
        if not part.Parent then return true end
        if math.abs(part.Position.Y - lastY) > 0.2 then
            lastY, still = part.Position.Y, os.clock()
        end
        return os.clock() - still > 1
    end)
    if not part.Parent then
        env.AirdropBusy = false
        return
    end
    status = auto.walk and "แอร์ดรอปมาแล้ว! เดินไปที่กล่อง..." or "แอร์ดรอปมาแล้ว! วาร์ปไปที่กล่อง..."
    if not goTo(part.Position) then
        status = "ไปที่กล่องไม่ถึง"
        env.AirdropBusy = false
        return
    end
    local hum = getHum()
    if hum then hum:UnequipTools() end
    local askedAt = os.clock()
    session.result = nil
    if typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
    if not waitFor(5, function() return session.openAt >= askedAt end) then
        status = "กดเปิดมินิเกมแล้วไม่ขึ้น (กล่องอาจยังไม่ลงพื้น)"
        env.AirdropBusy = false
        task.wait(2)
        return
    end
    status = auto.type and "พิมพ์รหัสให้..." or "พิมพ์รหัสในหน้าต่างแอร์ดรอปได้เลย (ห้ามเดินออกเกิน 15 studs)"
    -- พิมพ์รหัสให้: เร็วประมาณคนพิมพ์ (ตัวละ 0.15–0.25 วิ) ไม่ส่งทันทีที่เห็นรหัส ส่งรอบละครั้งพอ
    if auto.type then
        task.spawn(function()
            local sent = 0
            while alive() and auto.type and session.closeAt < askedAt and prompt:IsDescendantOf(workspace) do
                if session.code and session.roundAt > sent then
                    local code, round = tostring(session.code), session.roundAt
                    task.wait(#code * (0.15 + math.random() * 0.1) + 0.3)
                    if session.roundAt == round and session.closeAt < askedAt then
                        Net.SubmitGuess:FireServer(session.dropId, code)
                        status = "ส่งรหัส " .. code
                    end
                    sent = round
                end
                task.wait(0.1)
            end
        end)
    end
    -- รอจนจบ: เกมปิดเอง / ผู้เล่นกดปิด / กล่องหาย / หมดเวลากล่อง (180 วิ)
    local gui = LocalPlayer.PlayerGui:FindFirstChild("LES_AirDrop_UI")
    local mini = gui and gui:FindFirstChild("AirDropMiniGame")
    -- หน้าต่างมินิเกมหายต้องหายติดกัน 3 วิ ถึงนับว่าจบ (กันกระพริบระหว่างรอบแล้วนึกว่าจบ)
    local hiddenSince
    waitFor(180, function()
        if mini and not mini.Visible and os.clock() - askedAt > 1 then
            hiddenSince = hiddenSince or os.clock()
        else
            hiddenSince = nil
        end
        return not alive() or session.closeAt >= askedAt or not prompt:IsDescendantOf(workspace)
            or (hiddenSince ~= nil and os.clock() - hiddenSince > 3)
    end)
    done[prompt] = true
    if session.result == "win" then
        auto.got += 1
        status = "ได้แอร์ดรอปแล้ว! กลับไปทำงานต่อ"
    else
        status = "จบแอร์ดรอป (" .. tostring(session.result or "ออกเอง") .. ") กลับไปทำงานต่อ"
    end
    -- รีตัว: ตายแล้วเกิดใหม่ที่จุดเกิด (ไม่ยืนค้างที่กล่อง) งานอื่นรอจนเกิดใหม่ก่อน
    -- รีตัวตอนชนะ (ผ่านครบ 5 รอบ เกมแจ้ง win รอให้ของเข้ากระเป๋าก่อน)
    -- หรือผู้ชนะครบ 5 คนแล้ว (limit) ยืนต่อก็ไม่ได้อะไร
    local oldChar = LocalPlayer.Character
    if auto.reset and (session.result == "win" or session.result == "limit") and oldChar and not riding() then
        local inv = LocalPlayer:FindFirstChild("InventoryState")
        local total = inv and inv:GetAttribute("Total") or 0
        if session.result == "win" then
            waitFor(5, function()
                return inv ~= nil and (inv:GetAttribute("Total") or 0) > total
            end)
            task.wait(1)
        end
        status = status .. " (รีตัว)"
        local hum = getHum()
        if hum then hum.Health = 0 end
        pcall(function() oldChar:BreakJoints() end)
        waitFor(15, function()
            local c = LocalPlayer.Character
            return c ~= oldChar and c ~= nil and c:FindFirstChild("HumanoidRootPart") ~= nil
        end)
        task.wait(1)
    end
    env.AirdropBusy = false
end

local function autoLoop()
    while alive() and auto.on do
        local prompt = currentDrop()
        if prompt and not riding() then
            handle(prompt)
        elseif prompt then
            status = "แอร์ดรอปมาแล้ว แต่ขี่ช้างอยู่ (ไม่วาร์ปตอนขี่ ช้างจะจม)"
        elseif not env.AirdropBusy then
            status = "รอแอร์ดรอป..."
        end
        task.wait(1)
    end
    env.AirdropBusy = false
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
-- เปิดผ่านตัวรวม (BaanLung.lua) จะส่งแท็บ + Fluent มาให้: ใช้แท็บนั้น ไม่สร้างหน้าต่างเอง
local HUB_TAB, HUB_FLUENT = ...
local Fluent, Window, Tabs
if HUB_TAB then
    Fluent, Tabs = HUB_FLUENT, { main = HUB_TAB }
else
    local ok
    ok, Fluent = pcall(loadFluent, true)
    if not ok or typeof(Fluent) ~= "table" then
        ok, Fluent = pcall(loadFluent, false)
    end
    if not ok or typeof(Fluent) ~= "table" then
        warn("[Airdrop] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.AirdropFluent then
        pcall(function() env.AirdropFluent:Destroy() end)
    end
    env.AirdropFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "แอร์ดรอป",
        SubTitle = "Airdrop",
        TabWidth = 150,
        Size = UDim2.fromOffset(540, 320),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("แอร์ดรอป")
section:AddToggle("AirdropAuto", {
    Title = "ไปแอร์ดรอปอัตโนมัติ",
    Description = "กล่องตกเมื่อไหร่ พักงานอื่น ไปที่กล่องแล้วเปิดมินิเกมให้ พิมพ์รหัสเอง เสร็จแล้วกลับไปทำงานเดิม",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) else env.AirdropBusy = false end
end)
section:AddToggle("AirdropType", {
    Title = "พิมพ์รหัสให้",
    Description = "ใส่รหัสที่โชว์บนจอให้ครบ 5 รอบ ด้วยความเร็วประมาณคนพิมพ์ ไม่ต้องเฝ้า",
    Default = false,
}):OnChanged(function(v)
    auto.type = v
end)
section:AddToggle("AirdropReset", {
    Title = "เก็บเสร็จแล้วรีตัว",
    Description = "ชนะครบ 5 รอบได้ของเข้ากระเป๋าแล้ว หรือผู้ชนะครบ 5 คนแล้ว = ตายเกิดใหม่ (แพ้ไม่รีตัว) งานอื่นรอจนเกิดใหม่",
    Default = true,
}):OnChanged(function(v)
    auto.reset = v
end)
section:AddDropdown("AirdropMove", {
    Title = "วิธีไป",
    Description = "เดิน = ช้ากว่าแต่ปลอดภัย • วาร์ป = ถึงก่อนคนอื่น",
    Values = { "วาร์ป", "เดิน" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.walk = v == "เดิน"
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            statusPara:SetDesc(("%s\nกล่องในแมพ: %s  •  ได้ไปแล้ว %d กล่อง"):format(
                status, currentDrop() and "มี" or "ไม่มี", auto.got))
        end)
        task.wait(0.5)
    end
    if alive() then env.AirdropRun += 1 end
end)
