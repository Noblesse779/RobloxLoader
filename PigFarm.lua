-- ตีหมูอัตโนมัติ
-- อ่านจากโค้ดเกม (PlayerScripts["Monster System"].CombatClient + WeaponConfig):
--   ถือดาบ (Tool ที่ Attribute MonsterWeapon = true และชื่ออยู่ใน WeaponConfig.Weapons)
--   ฟัน = ReplicatedStorage["Monster System"].Remotes.Attack:FireServer() ไม่มีค่าอะไร
--   เซิร์ฟเวอร์หาเป้าเอง: หมูที่อยู่ในระยะดาบ (Range) และอยู่ข้างหน้าเรา (FrontDot 0.2)
--   ฟันได้ทุก Cooldown วิ (ดาบส่วนใหญ่ 0.35) และไม่เกิน 5 ครั้ง/วิ
--   หมูอยู่ใน workspace["Monster System"].ActiveMonsters (ลูกน้องหมู / หัวหน้าหมู / KingPig)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.PigRun = (env.PigRun or 0) + 1
local RUN = env.PigRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.PigRun == RUN
end

local System = ReplicatedStorage:WaitForChild("Monster System")
local WeaponConfig = require(System:WaitForChild("WeaponConfig"))
local AttackRemote = System:WaitForChild("Remotes"):WaitForChild("Attack")
local ActiveMonsters = workspace:WaitForChild("Monster System"):WaitForChild("ActiveMonsters")

local status = "-"
local auto = {
    on = false, walk = true, target = "ทุกตัว", swings = 0, kills = 0,
    dist = 4, -- ยืนห่างหมูกี่ studs (ไม่เกินระยะดาบ ไม่งั้นเซิร์ฟเวอร์ไม่นับ)
    side = "หลัง", -- ยืนตรงไหนของหมู: หน้า / หลัง / บน / ล่าง
    sell = false, -- กระเป๋าเต็มแล้วไปขายเนื้อ
    sold = 0, -- ขายได้กี่บาทแล้ว
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

---------------------------------------------------------------- ดาบ
local function weaponTools()
    local list = {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("MonsterWeapon") == true and WeaponConfig.Weapons[t.Name] then
                    table.insert(list, t)
                end
            end
        end
    end
    -- ดาเมจมากสุดก่อน
    table.sort(list, function(a, b)
        return WeaponConfig.Weapons[a.Name].Damage > WeaponConfig.Weapons[b.Name].Damage
    end)
    return list
end

-- ดาบที่ดีที่สุดที่เรามี (LocalPlayer.CollectionState = ของที่ซื้อแล้ว แบบเดียวกับร้านอาวุธใช้)
local function bestOwnedWeapon()
    local owned = LocalPlayer:FindFirstChild("CollectionState")
    local best, bestDmg
    if owned then
        for name, w in pairs(WeaponConfig.Weapons) do
            local flag = owned:FindFirstChild(name)
            if flag and flag:IsA("BoolValue") and flag.Value and (not bestDmg or w.Damage > bestDmg) then
                best, bestDmg = name, w.Damage
            end
        end
    end
    return best, bestDmg
end

-- ให้ดาบที่ดีที่สุดมาอยู่ในช่องลัด (เป็น Tool) ถ้ายังค้างในกระเป๋าเกม เอาออกมาแบบปลูกข้าว
local lastEnsure = 0
local function ensureWeapon()
    local tools = weaponTools()
    local have = tools[1] and WeaponConfig.Weapons[tools[1].Name].Damage or nil
    local best, bestDmg = bestOwnedWeapon()
    if have and (not bestDmg or have >= bestDmg) then return true end -- ดีสุดอยู่ในมือ/ช่องลัดแล้ว
    if not best or os.clock() - lastEnsure < 5 then return have ~= nil end
    lastEnsure = os.clock()
    local inv = ReplicatedStorage:FindFirstChild("InventorySystem")
    local remote = inv and inv:FindFirstChild("Remotes") and inv.Remotes:FindFirstChild("SetHotbar")
    if not remote then return have ~= nil end
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
    if not seen[best] then table.insert(names, best) end
    status = "เอา " .. best .. " (ดาบดีสุด) ออกมาไว้ช่องลัด..."
    remote:FireServer(names)
    waitFor(3, function()
        local t = weaponTools()[1]
        return t ~= nil and t.Name == best
    end)
    return #weaponTools() > 0
end

-- ถือดาบในมือ คืนค่า (tool, ค่าดาบจาก WeaponConfig)
local function equipWeapon()
    if not ensureWeapon() then return nil end
    local tool = weaponTools()[1]
    local hum = getHum()
    if not (tool and hum) then return nil end
    if tool.Parent ~= LocalPlayer.Character then
        hum:EquipTool(tool)
        if not waitFor(2, function() return tool.Parent == LocalPlayer.Character end) then return nil end
        task.wait(WeaponConfig.EquipDelay or 0.3) -- เกมไม่ให้ฟันทันทีหลังหยิบ
    end
    return tool, WeaponConfig.Weapons[tool.Name]
end

---------------------------------------------------------------- หมู
local function wanted(model)
    if auto.target == "ทุกตัว" then return true end
    local n = model.Name
    if auto.target == "ลูกน้องหมู" then return n:find("ลูกน้อง", 1, true) ~= nil end
    if auto.target == "หัวหน้าหมู" then return n:find("หัวหน้า", 1, true) ~= nil end
    if auto.target == "ราชาหมู (บอส)" then return n == "KingPig" end
    return true
end

local function monsterRoot(m)
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
end

-- เลือกเป้า: ตัวเก่งสุดก่อน (เลือดเต็มมากสุด = บอส > มินิบอส > ลูกน้อง) ตัวเก่งเท่ากันเอาเลือดเหลือน้อยสุด
-- maxDist = ระยะไกลสุดที่นับ (Kill Aura ใช้ระยะดาบ)
local function pickPig(maxDist)
    local hrp = getRoot()
    if not hrp then return nil end
    local best, bestMax, bestHp, bestDist
    for _, m in ipairs(ActiveMonsters:GetChildren()) do
        local hum = m:FindFirstChildOfClass("Humanoid")
        local root = monsterRoot(m)
        if hum and hum.Health > 0 and root and wanted(m) then
            local d = (root.Position - hrp.Position).Magnitude
            if not maxDist or d <= maxDist then
                local better = not best
                    or hum.MaxHealth > bestMax
                    or (hum.MaxHealth == bestMax and hum.Health < bestHp)
                    or (hum.MaxHealth == bestMax and hum.Health == bestHp and d < bestDist)
                if better then
                    best, bestMax, bestHp, bestDist = m, hum.MaxHealth, hum.Health, d
                end
            end
        end
    end
    return best, bestDist
end

---------------------------------------------------------------- เดิน / วาร์ป
local function walkToward(pos)
    local hum, hrp = getHum(), getRoot()
    if not (hum and hrp) then return end
    -- ไกล: หาทางอ้อม ใกล้: เดินตรงเข้าไป (หมูขยับตลอด หาทางใหม่บ่อยๆ ไม่คุ้ม)
    if (pos - hrp.Position).Magnitude > 25 then
        local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
        if pcall(function() path:ComputeAsync(hrp.Position, pos) end) and path.Status == Enum.PathStatus.Success then
            local wps = path:GetWaypoints()
            local wp = wps[math.min(3, #wps)]
            if wp then
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                hum:MoveTo(wp.Position)
                return
            end
        end
    end
    hum:MoveTo(pos)
end

-- หันหน้าเข้าหาหมู (เซิร์ฟเวอร์นับเฉพาะหมูที่อยู่ข้างหน้า)
local function face(pos)
    local hrp = getRoot()
    if not hrp then return end
    local flat = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
    if (flat - hrp.Position).Magnitude > 0.1 then
        hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
    end
end

---------------------------------------------------------------- ฟัน
local lastSwing = 0
local function swing(stats)
    -- รอครบดีเลของดาบ + เผื่อนิดหน่อย และไม่เกินจำนวนครั้ง/วิ ที่เกมยอม
    local gap = math.max(stats.Cooldown + 0.03, 1 / (WeaponConfig.RequestsPerSecond or 5))
    if os.clock() - lastSwing < gap then return false end
    lastSwing = os.clock()
    AttackRemote:FireServer()
    auto.swings += 1
    return true
end

-- จุดยืนรอบหมู (หน้า/หลัง ตามทิศที่หมูหันอยู่, บน/ล่าง ตรงหัว/ใต้เท้า)
local function standPoint(root, dist)
    if auto.side == "หน้า" then return (root.CFrame * CFrame.new(0, 0, -dist)).Position end
    if auto.side == "บน" then return root.Position + Vector3.new(0, dist, 0) end
    if auto.side == "ล่าง" then return root.Position - Vector3.new(0, dist, 0) end
    return (root.CFrame * CFrame.new(0, 0, dist)).Position -- หลัง
end

-- ยืนบน/ใต้หมูต้องทะลุพื้น/ตัวหมู: ปิดชนฝั่งเราทุกเฟรมระหว่างตี (Humanoid เปิดกลับเองทุกเฟรม เลิกแล้วกลับปกติ)
local RunService = game:GetService("RunService")
local noclip = false
local noclipConn = RunService.Stepped:Connect(function()
    if not noclip then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    noclipConn:Disconnect()
end)

local function fight(pig)
    local tool, stats = equipWeapon()
    if not tool then
        status = "ไม่มีดาบ (ซื้อที่ลุงน้อยขายอาวุธ)"
        return false
    end
    local pigHum = pig:FindFirstChildOfClass("Humanoid")
    status = ("ตี %s (%s)"):format(pig.Name, tool.Name)
    local started, lastCheck = os.clock(), os.clock()
    while alive() and auto.on and pig.Parent and pigHum and pigHum.Health > 0 do
        local hrp, hum, root = getRoot(), getHum(), monsterRoot(pig)
        if not (hrp and hum and hum.Health > 0 and root) then break end
        if tool.Parent ~= LocalPlayer.Character then
            tool, stats = equipWeapon()
            if not tool then break end
        end
        local vertical = auto.side == "บน" or auto.side == "ล่าง"
        local d = math.clamp(auto.dist, 1, stats.Range - 0.5)
        local stand = standPoint(root, d)
        local toPig = (root.Position - hrp.Position).Magnitude
        if vertical or not auto.walk then
            -- วาร์ปไปจุดยืนทุกเฟรม (หมูขยับตาม) บน/ล่างใช้วาร์ปเสมอ เดินไปไม่ได้
            noclip = vertical
            local look = vertical and root.Position or Vector3.new(root.Position.X, stand.Y, root.Position.Z)
            hrp.CFrame = CFrame.lookAt(stand, look) -- บน/ล่าง ก้ม/เงยหน้าหาหมู ให้นับว่าหมูอยู่ข้างหน้า
            hrp.AssemblyLinearVelocity = Vector3.zero
            swing(stats)
        else
            noclip = false
            if (Vector3.new(stand.X, hrp.Position.Y, stand.Z) - hrp.Position).Magnitude > 1.5 then
                walkToward(stand)
            else
                hum:MoveTo(hrp.Position)
            end
            if toPig <= stats.Range - 0.3 then
                face(root.Position)
                swing(stats)
            end
        end
        if os.clock() - started > 60 then break end -- ตีไม่ตายใน 1 นาที (ติด/หนี) ไปตัวอื่น
        -- มีตัวเก่งกว่าโผล่มา (เช่นมินิบอส/บอสเกิด) เปลี่ยนไปตีตัวนั้นก่อน
        if os.clock() - lastCheck > 1 then
            lastCheck = os.clock()
            local top = pickPig()
            local topHum = top and top:FindFirstChildOfClass("Humanoid")
            if topHum and topHum.MaxHealth > pigHum.MaxHealth then break end
        end
        RunService.Heartbeat:Wait()
    end
    noclip = false
    if pigHum and pigHum.Health <= 0 then
        auto.kills += 1
        return true
    end
    return false
end

-- Kill Aura: ยืนอยู่กับที่ หมูตัวไหนเดินเข้ามาในระยะดาบ หันไปฟันเอง (ระยะเกินดาบเซิร์ฟเวอร์ไม่นับ)
local aura = { on = false }
local function auraLoop()
    while alive() and aura.on do
        local hrp, hum = getRoot(), getHum()
        if hrp and hum and hum.Health > 0 and not auto.on and not equipWeapon() then
            status = "Kill Aura: ไม่มีดาบ / หยิบดาบไม่ได้"
            task.wait(1)
        elseif hrp and hum and hum.Health > 0 and not auto.on then
            local held = weaponTools()[1]
            local range = held and WeaponConfig.Weapons[held.Name].Range + 1 or 0
            local pig = pickPig(range)
            local best = pig and monsterRoot(pig)
            local bestDist = best and (best.Position - hrp.Position).Magnitude
            local stats = best and WeaponConfig.Weapons[(weaponTools()[1] or {}).Name or ""]
            if best and stats and bestDist <= stats.Range + 1 then
                local tool
                tool, stats = equipWeapon()
                if tool then
                    face(best.Position)
                    if swing(stats) then status = "Kill Aura: ฟัน" end
                end
            elseif not auto.on then
                status = "Kill Aura: รอหมูเข้ามาในระยะ"
            end
        end
        task.wait(0.05)
    end
end

---------------------------------------------------------------- ขายเนื้อเมื่อกระเป๋าเต็ม
-- อ่านจากโค้ดเกม (PlayerGui.SellHubGui.SellHubClient + SellHubConfig):
--   กระเป๋า: LocalPlayer.InventoryState  Attribute Total / Capacity, ของแต่ละอย่าง = IntValue ชื่อของ
--   ร้านเนื้อ: workspace.sellmeatpart.SellMeatPrompt (ต้องอยู่ห่างไม่เกิน SaleDistance 15)
--   กดปุ่ม -> เซิร์ฟเวอร์ส่ง SellHubSystem.Remotes.Open(ส่วนร้าน, { shopId, ... })
--   ขาย: Request:InvokeServer("SellAll", nil, nil, GUID, shopId)  ปิด: Request:InvokeServer("Close", nil, nil, nil, shopId)
local HttpService = game:GetService("HttpService")
local SellHub = ReplicatedStorage:WaitForChild("SellHubSystem")
local SellRemotes = SellHub:WaitForChild("Remotes")
local SellConfig = require(SellHub:WaitForChild("SellHubConfig"))
local MEAT_ITEMS = SellConfig.Shops.Meat.Order -- Meat / Large Meat / Animal Skin

local opened = { shopId = nil, at = 0 }
local openConn = SellRemotes:WaitForChild("Open").OnClientEvent:Connect(function(_, state)
    if type(state) == "table" and state.shopId then
        opened.shopId, opened.at = state.shopId, os.clock()
    end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    openConn:Disconnect()
end)

local function bagState()
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    if not inv then return 0, 100, 0 end
    local meat = 0
    for _, name in ipairs(MEAT_ITEMS) do
        local v = inv:FindFirstChild(name)
        if v and v:IsA("IntValue") and not v:GetAttribute("SaleLocked") then meat += v.Value end
    end
    return inv:GetAttribute("Total") or 0, inv:GetAttribute("Capacity") or 100, meat
end

local function bagFull()
    local total, cap, meat = bagState()
    return meat > 0 and total >= cap
end

-- ไปให้ถึงระยะ (เดิน/วาร์ป ตามที่เลือก)
local function goNear(pos, within)
    local hrp = getRoot()
    if not hrp then return false end
    if not auto.walk then
        local away = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
        away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
        local stand = pos + away * math.min(4, within - 1) + Vector3.new(0, 3, 0)
        hrp.CFrame = CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.4)
        return true
    end
    local t = os.clock()
    while alive() and auto.on and os.clock() - t < 90 do
        hrp = getRoot()
        if not hrp then return false end
        if (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude <= within then
            local hum = getHum()
            if hum then hum:MoveTo(hrp.Position) end
            return true
        end
        walkToward(pos)
        task.wait(0.3)
    end
    return false
end

local function sellMeat()
    local part = workspace:FindFirstChild(SellConfig.Shops.Meat.PartName or "sellmeatpart")
    local prompt = part and part:FindFirstChild(SellConfig.Shops.Meat.PromptName or "SellMeatPrompt")
    if not prompt then
        status = "หาร้านขายเนื้อไม่เจอ"
        return false
    end
    status = auto.walk and "กระเป๋าเต็ม: เดินไปขายเนื้อ..." or "กระเป๋าเต็ม: วาร์ปไปขายเนื้อ..."
    if not goNear(part.Position, math.min(prompt.MaxActivationDistance, SellConfig.SaleDistance or 15) - 2) then
        status = "ไปร้านขายเนื้อไม่ถึง"
        return false
    end
    local askedAt = os.clock()
    if typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
    if not waitFor(4, function() return opened.at >= askedAt end) then
        status = "กดขายเนื้อแล้วร้านไม่เปิด"
        return false
    end
    local shopId = opened.shopId
    local before = select(3, bagState())
    -- เกมเก็บของในมือก่อนขายเสมอ (ถือดาบอยู่อาจขายไม่ได้) แล้วลองส่งซ้ำได้ 3 ครั้ง ด้วยรหัสเดิม
    local hum = getHum()
    if hum then hum:UnequipTools() end
    local guid = HttpService:GenerateGUID(false)
    local ok, res
    for _ = 1, 3 do
        ok, res = pcall(function()
            return SellRemotes.Request:InvokeServer("SellAll", nil, nil, guid, shopId)
        end)
        if ok then break end
        task.wait(0.3)
    end
    pcall(function() SellRemotes.Request:InvokeServer("Close", nil, nil, nil, shopId) end)
    pcall(function() -- ปิดหน้าต่างร้านบนจอ (เกมเปิดให้ตอนกดปุ่ม)
        local gui = LocalPlayer.PlayerGui:FindFirstChild("SellHubGui")
        if gui then gui.Enabled = false end
        if LocalPlayer:GetAttribute("UIBusyOwner") == "SellHub" then
            LocalPlayer:SetAttribute("UIBusy", false)
            LocalPlayer:SetAttribute("UIBusyOwner", nil)
        end
    end)
    if ok and type(res) == "table" and res.ok then
        auto.sold += tonumber(res.totalMoney) or 0
        status = ("ขายเนื้อ %s ชิ้น ได้ %s บาท"):format(tostring(res.soldCount), tostring(res.totalMoney))
        return true
    end
    status = "ขายไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and (res.reason or res.message) or res)
    return select(3, bagState()) < before
end

local function autoLoop()
    while alive() and auto.on do
        local hum = getHum()
        if not (hum and hum.Health > 0) then
            status = "รอเกิดใหม่..."
            task.wait(1)
        elseif auto.sell and bagFull() then
            if not sellMeat() then task.wait(3) end
        elseif not equipWeapon() then
            -- ถือดาบดีสุดให้ได้ก่อน แล้วค่อยไปหาหมู
            status = "ไม่มีดาบ / หยิบดาบไม่ได้ (ซื้อที่ลุงน้อยขายอาวุธ)"
            task.wait(1)
        else
            local pig = pickPig()
            if pig then
                fight(pig)
            else
                status = "ไม่มีหมูให้ตี รอเกิด..."
                task.wait(1)
            end
        end
        task.wait(0.1)
    end
    local hum, hrp = getHum(), getRoot()
    if hum and hrp and auto.walk then hum:MoveTo(hrp.Position) end
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
        warn("[PigFarm] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.PigFluent then
        pcall(function() env.PigFluent:Destroy() end)
    end
    env.PigFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ตีหมู",
        SubTitle = "Monster",
        TabWidth = 150,
        Size = UDim2.fromOffset(540, 380),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("ตีหมู")
section:AddToggle("PigAuto", {
    Title = "ตีหมูอัตโนมัติ",
    Description = "ถือดาบ -> ไปหาหมูตัวที่ใกล้สุด -> ฟันตามดีเลดาบ -> ตายแล้วไปตัวต่อไป",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) end
end)
section:AddToggle("PigAura", {
    Title = "Kill Aura",
    Description = "ยืนอยู่กับที่ หมูเข้ามาในระยะดาบเมื่อไหร่ หันไปฟันเอง (เปิดพร้อมตีอัตโนมัติ จะใช้ตีอัตโนมัติ)",
    Default = false,
}):OnChanged(function(v)
    aura.on = v
    if v then task.spawn(auraLoop) end
end)
section:AddDropdown("PigTarget", {
    Title = "ตีตัวไหน",
    Values = { "ทุกตัว", "ลูกน้องหมู", "หัวหน้าหมู", "ราชาหมู (บอส)" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.target = v
end)
section:AddDropdown("PigMove", {
    Title = "วิธีไป",
    Description = "เดิน = ช้ากว่าแต่ปลอดภัย (กันโดนแบน) • วาร์ป = เร็ว",
    Values = { "เดิน", "วาร์ป" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.walk = v ~= "วาร์ป"
end)
section:AddSlider("PigDist", {
    Title = "ระยะห่างจากหมู",
    Description = "ไกลขึ้น = โดนหมูตีน้อยลง (ไม่เกินระยะดาบ: Katana 5 • Dark Surge/Ice Axe 15)",
    Default = 4,
    Min = 1,
    Max = 20,
    Rounding = 1,
}):OnChanged(function(v)
    auto.dist = v
end)
section:AddDropdown("PigSide", {
    Title = "ยืนตรงไหนของหมู",
    Description = "หลัง = หมูหันมาตีช้า • บน/ล่าง = ลอยอยู่เหนือหัว/ใต้พื้น (ใช้วาร์ปเสมอ)",
    Values = { "หลัง", "หน้า", "บน", "ล่าง" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.side = v
end)
section:AddToggle("PigSell", {
    Title = "ขายเนื้อเมื่อกระเป๋าเต็ม",
    Description = "กระเป๋าเต็ม -> ไปร้านขายเนื้อหมู ขาย Meat / Large Meat / Animal Skin ทั้งหมด -> กลับมาตีต่อ (ของที่ล็อกขายไว้ไม่ขาย)",
    Default = false,
}):OnChanged(function(v)
    auto.sell = v
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local tool = weaponTools()[1]
            local count = 0
            for _, m in ipairs(ActiveMonsters:GetChildren()) do
                local h = m:FindFirstChildOfClass("Humanoid")
                if h and h.Health > 0 and wanted(m) then count += 1 end
            end
            local total, cap, meat = bagState()
            statusPara:SetDesc(("%s\nดาบ: %s  •  หมูในแมพ: %d\nฟันไป %d ครั้ง  •  ฆ่าไป %d ตัว\nกระเป๋า %d/%d (เนื้อ %d)  •  ขายได้ %d บาท"):format(
                status, tool and tool.Name or "ไม่มี", count, auto.swings, auto.kills, total, cap, meat, auto.sold))
        end)
        task.wait(0.5)
    end
    if alive() then env.PigRun += 1 end
end)
