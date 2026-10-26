-- ตัดไม้: ถือขวานไปตัดต้นไม้ใกล้สุด วนไปเรื่อยๆ จนได้ไม้ตามที่ตั้ง / กระเป๋าเต็ม
-- อ่านจากโค้ดเกม (PlayerScripts["Survival System"].WoodcuttingClient + WoodcuttingConfig):
--   ต้นไม้ = CollectionService tag "ChoppableTree"  Attribute Harvested = ตัดแล้ว (เกิดใหม่ 60 วิ)
--   ตัด = ถือขวาน (tag "SurvivalAxe") แล้วกด (tool:Activate) เกมส่ง Remotes.Chop / SwingEnded เอง
--     ระยะ 7 ดีเล 0.75  ขวานธรรมดาฟัน 6 ครั้ง ได้ไม้ 1–2  Upgrade Axe ฟัน 3 ครั้ง ได้ 1–4
--   ไม้ (Wood) ขายไม่ได้ ใช้คราฟของ (โต๊ะคราฟ / แคมป์ไฟ / Pickaxe ฯลฯ)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.WoodRun = (env.WoodRun or 0) + 1
local RUN = env.WoodRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.WoodRun == RUN
end

local Survival = ReplicatedStorage:WaitForChild("Survival System")
local Config = require(Survival:WaitForChild("WoodcuttingConfig"))
local Remotes = Survival:WaitForChild("Remotes")

local status = "-"
local auto = {
    on = false,
    walk = true, -- เดินไปตัด (false = วาร์ป)
    target = 0, -- ตัดจนได้ไม้กี่ชิ้นแล้วหยุด (0 = ไม่จำกัด ตัดจนกระเป๋าเต็ม)
    dist = 2, -- วาร์ปตัด: ยืนห่างลำต้นกี่ studs
    chopped = 0,
}

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

local function count(name)
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    local v = inv and inv:FindFirstChild(name)
    return (v and v:IsA("IntValue")) and v.Value or 0
end

local function bagFull()
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    if not inv then return false end
    return (inv:GetAttribute("Total") or 0) >= (inv:GetAttribute("Capacity") or 100)
end

---------------------------------------------------------------- ขวาน
local function tools()
    local list = {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") then table.insert(list, t) end
            end
        end
    end
    return list
end

local function hitsOf(name)
    return Config.AxeHitsRequired[name] or Config.HitsRequired
end

local function axes()
    local list = {}
    for _, t in ipairs(tools()) do
        if CollectionService:HasTag(t, Config.AxeTag) then table.insert(list, t) end
    end
    table.sort(list, function(a, b) return hitsOf(a.Name) < hitsOf(b.Name) end) -- ฟันน้อยครั้งสุดก่อน
    return list
end

-- เอาขวานจากกระเป๋าเกม (คอลเลกชั่น) ออกมาช่องลัด แบบเดียวกับขุดเหมือง
local lastPull = 0
local function pullAxe()
    if os.clock() - lastPull < 5 then return end
    lastPull = os.clock()
    local owned = LocalPlayer:FindFirstChild("CollectionState")
    local inv = ReplicatedStorage:FindFirstChild("InventorySystem")
    local remotes = inv and inv:FindFirstChild("Remotes")
    if not (owned and remotes) then return end
    local best
    for _, name in ipairs({ "Upgrade Axe", "Axe" }) do
        local flag = owned:FindFirstChild(name)
        if flag and flag:IsA("BoolValue") and flag.Value then best = name break end
    end
    if not best then return end
    local have = axes()[1]
    if have and hitsOf(have.Name) <= hitsOf(best) then return end
    local names, seen = {}, {}
    for _, t in ipairs(tools()) do
        if not seen[t.Name] then
            seen[t.Name] = true
            table.insert(names, t.Name)
        end
    end
    if not seen[best] then
        if #names >= 5 then table.remove(names, 1) end -- ช่องลัดมี 5 ช่อง
        table.insert(names, best)
    end
    remotes.SetHotbar:FireServer(names)
    if not waitFor(2, function() return axes()[1] ~= nil and axes()[1].Name == best end) and remotes:FindFirstChild("EquipItem") then
        remotes.EquipItem:FireServer(best)
        waitFor(2, function() return axes()[1] ~= nil end)
    end
end

local function equipAxe()
    pullAxe()
    local axe = axes()[1]
    local hum = getHum()
    if not (axe and hum) then return nil end
    if axe.Parent ~= LocalPlayer.Character then
        hum:EquipTool(axe)
        if not waitFor(2, function() return axe.Parent == LocalPlayer.Character end) then return nil end
        task.wait(0.2)
    end
    return axe
end

---------------------------------------------------------------- เดิน / วาร์ป
local function goNear(pos, within)
    local hrp, hum = getRoot(), getHum()
    if not (hrp and hum) then return false end
    local function near()
        local h = getRoot()
        return h and (Vector3.new(pos.X, h.Position.Y, pos.Z) - h.Position).Magnitude <= within
    end
    if near() then return true end
    local t = os.clock()
    while alive() and auto.on and os.clock() - t < 90 do
        if near() then
            hum:MoveTo(hrp.Position)
            return true
        end
        local points = { pos }
        local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
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

-- ค้างตัวไว้ที่จุดยืนทุกเฟรมตอนวาร์ปตัด (ไม่ Anchored เพราะเกมไม่ให้ตัดตอนตัว Anchored)
local holdCF
local holdConn = RunService.Heartbeat:Connect(function()
    if not holdCF then return end
    local hrp = getRoot()
    if hrp then
        hrp.CFrame = holdCF
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    holdConn:Disconnect()
    holdCF = nil
end)

---------------------------------------------------------------- ต้นไม้
local hitAt = setmetatable({}, { __mode = "k" }) -- ต้นที่เพิ่งโดนฟัน (เกมส่ง TreeEffect "Hit")
local swingId = 2000000 -- รหัสท่าฟันตอนส่งรีโมทเอง (เลขสูง ไม่ชนกับที่เกมนับ)
local effConn = Remotes:WaitForChild("TreeEffect").OnClientEvent:Connect(function(tree, kind)
    if kind == "Hit" and typeof(tree) == "Instance" then hitAt[tree] = os.clock() end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    effConn:Disconnect()
end)

local function choppable(tree)
    return tree:IsA("Model") and tree:IsDescendantOf(workspace) and not tree:GetAttribute("Harvested")
        and not tree:GetAttribute("TutorialRole")
end

local function trunkPos(tree)
    -- จุดโคนต้น: ใช้ชิ้นที่ต่ำสุด (ลำต้น) แทนจุดกลางทั้งต้น (สูงขึ้นไปในพุ่มใบ)
    local pivot = tree:GetPivot().Position
    local low
    for _, p in ipairs(tree:GetDescendants()) do
        if p:IsA("BasePart") and (not low or p.Position.Y < low.Position.Y) then low = p end
    end
    return low and Vector3.new(low.Position.X, low.Position.Y, low.Position.Z) or pivot
end

local function pickTree()
    local hrp = getRoot()
    if not hrp then return nil end
    local best, bestDist
    for _, tree in ipairs(CollectionService:GetTagged(Config.TreeTag)) do
        if choppable(tree) then
            local d = (tree:GetPivot().Position - hrp.Position).Magnitude
            if not bestDist or d < bestDist then best, bestDist = tree, d end
        end
    end
    return best
end

local function chopTree(tree, axe)
    local pos = trunkPos(tree)
    local within = math.max(2, Config.Reach - 3)
    status = (auto.walk and "เดิน" or "วาร์ป") .. "ไปตัดไม้..."
    if auto.walk then
        if not goNear(pos, within) then
            status = "ไปที่ต้นไม้ไม่ถึง"
            return false
        end
    end
    status = "ตัดไม้..."
    local started, tries, direct = os.clock(), 0, false
    while alive() and auto.on and choppable(tree) and not env.AirdropBusy do
        if axe.Parent ~= LocalPlayer.Character then
            axe = equipAxe()
            if not axe then break end
        end
        local hrp, hum = getRoot(), getHum()
        if not (hrp and hum) then break end
        if auto.walk then
            if (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude > within + 2 then
                if not goNear(pos, within) then break end
            end
            hum:MoveTo(hrp.Position)
            local flat = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
            if (flat - hrp.Position).Magnitude > 0.1 then hrp.CFrame = CFrame.lookAt(hrp.Position, flat) end
        else
            -- วาร์ปตัด: ยืนข้างลำต้นตามระยะที่ตั้ง บนพื้นจริง หันหน้าเข้าต้น
            local away = Vector3.new((holdCF and holdCF.Position or hrp.Position).X - pos.X, 0, (holdCF and holdCF.Position or hrp.Position).Z - pos.Z)
            away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
            local stand = pos + away * (1.5 + math.clamp(auto.dist, 0, Config.Reach - 2))
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { LocalPlayer.Character, tree }
            local hit = workspace:Raycast(stand + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
            if hit then stand = Vector3.new(stand.X, hit.Position.Y + 3, stand.Z) end
            holdCF = CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
            hrp.CFrame = holdCF
        end
        if not direct then
            -- กดรัวๆ ให้เกมกันกดซ้ำเองตามดีเล 0.75 ได้ฟันทันทีที่ฟันได้
            axe:Activate()
            task.wait(0.05)
            tries += 1
            if tries >= 60 and hitAt[tree] == nil then direct = true end -- กดแล้วต้นไม่สั่น: ส่งรีโมทเอง
        else
            swingId += 1
            local id, t0 = swingId, os.clock()
            Remotes.Chop:FireServer(id)
            task.wait(Config.HitDelay + 0.05)
            Remotes.SwingEnded:FireServer(id)
            task.wait(math.max(0.02, Config.SwingCooldown + 0.02 - (os.clock() - t0)))
        end
        if os.clock() - started > 30 then break end -- ตัดไม่ล้มใน 30 วิ ไปต้นอื่น
    end
    holdCF = nil
    if not choppable(tree) then
        auto.chopped += 1
        return true
    end
    return false
end

---------------------------------------------------------------- วนอัตโนมัติ
local startWood = 0
local function autoLoop()
    startWood = count("Wood")
    while alive() and auto.on do
        local hum = getHum()
        if env.AirdropBusy then
            status = "พักให้แอร์ดรอป..."
            task.wait(0.5)
        elseif not (hum and hum.Health > 0) then
            status = "รอเกิดใหม่..."
            task.wait(1)
        elseif LocalPlayer:FindFirstChild("BuffaloRideMount") and LocalPlayer.BuffaloRideMount.Value then
            status = "ลงจากช้างก่อน (กด Spacebar)"
            task.wait(1)
        elseif bagFull() then
            status = "กระเป๋าเต็ม หยุดตัด"
            task.wait(2)
        elseif auto.target > 0 and count("Wood") - startWood >= auto.target then
            status = ("ได้ไม้ครบ %d ชิ้นแล้ว หยุดตัด"):format(auto.target)
            task.wait(2)
        else
            local axe = equipAxe()
            if not axe then
                status = "ไม่มีขวาน"
                task.wait(2)
            else
                local tree = pickTree()
                if tree then
                    chopTree(tree, axe)
                else
                    status = "ไม่มีต้นไม้ให้ตัด รอเกิดใหม่..."
                    task.wait(2)
                end
            end
        end
        task.wait(0.1)
    end
    holdCF = nil
    local h, hrp = getHum(), getRoot()
    if h and hrp and auto.walk then h:MoveTo(hrp.Position) end
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
        warn("[Woodcut] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.WoodFluent then
        pcall(function() env.WoodFluent:Destroy() end)
    end
    env.WoodFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ตัดไม้",
        SubTitle = "Woodcutting",
        TabWidth = 150,
        Size = UDim2.fromOffset(540, 360),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("ตัดไม้")
section:AddToggle("WoodAuto", {
    Title = "ตัดไม้อัตโนมัติ",
    Description = "ถือขวานดีสุด -> ตัดต้นไม้ใกล้สุด -> ต้นต่อไป จนได้ไม้ครบ / กระเป๋าเต็ม",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) else holdCF = nil end
end)
section:AddDropdown("WoodMove", {
    Title = "วิธีไป",
    Description = "เดิน = ช้ากว่าแต่ปลอดภัย (กันโดนแบน) • วาร์ป = เร็ว",
    Values = { "เดิน", "วาร์ป" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.walk = v ~= "วาร์ป"
end)
section:AddSlider("WoodDist", {
    Title = "วาร์ปตัด: ระยะห่างจากต้นไม้",
    Description = "ใช้ตอนเลือกวาร์ป • ห่างจากลำต้น (ระยะตัดของเกม 7)",
    Default = 2,
    Min = 0,
    Max = 5,
    Rounding = 1,
}):OnChanged(function(v)
    auto.dist = v
end)
section:AddSlider("WoodTarget", {
    Title = "ตัดให้ได้ไม้กี่ชิ้นแล้วหยุด",
    Description = "0 = ไม่จำกัด ตัดจนกระเป๋าเต็ม (นับจากตอนเปิดสวิตช์)",
    Default = 0,
    Min = 0,
    Max = 500,
    Rounding = 0,
}):OnChanged(function(v)
    auto.target = v
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local axe = axes()[1]
            local inv = LocalPlayer:FindFirstChild("InventoryState")
            statusPara:SetDesc(("%s\nขวาน: %s  •  ไม้ในกระเป๋า: %d\nตัดไปแล้ว %d ต้น  •  กระเป๋า %d/%d"):format(
                status, axe and axe.Name or "ไม่มี", count("Wood"), auto.chopped,
                inv and inv:GetAttribute("Total") or 0, inv and inv:GetAttribute("Capacity") or 0))
        end)
        task.wait(0.5)
    end
    if alive() then env.WoodRun += 1 end
end)
