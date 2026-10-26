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
local auto = { on = false, walk = true, target = "ทุกตัว", swings = 0, kills = 0 }

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

local function nearestPig()
    local hrp = getRoot()
    if not hrp then return nil end
    local best, bestDist
    for _, m in ipairs(ActiveMonsters:GetChildren()) do
        local hum = m:FindFirstChildOfClass("Humanoid")
        local root = monsterRoot(m)
        if hum and hum.Health > 0 and root and wanted(m) then
            local d = (root.Position - hrp.Position).Magnitude
            if not bestDist or d < bestDist then best, bestDist = m, d end
        end
    end
    return best
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

local function fight(pig)
    local tool, stats = equipWeapon()
    if not tool then
        status = "ไม่มีดาบ (ซื้อที่ลุงน้อยขายอาวุธ)"
        return false
    end
    local pigHum = pig:FindFirstChildOfClass("Humanoid")
    local reach = math.max(2.5, math.min(stats.Range - 1.5, 4))
    status = ("ตี %s (%s)"):format(pig.Name, tool.Name)
    local started = os.clock()
    while alive() and auto.on and pig.Parent and pigHum and pigHum.Health > 0 do
        local hrp, hum, root = getRoot(), getHum(), monsterRoot(pig)
        if not (hrp and hum and hum.Health > 0 and root) then break end
        if tool.Parent ~= LocalPlayer.Character then
            tool, stats = equipWeapon()
            if not tool then break end
        end
        local offset = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
        local dist = offset.Magnitude
        local dir = dist > 0.1 and offset.Unit or Vector3.new(0, 0, 1)
        if dist > stats.Range - 0.5 then
            if auto.walk then
                walkToward(root.Position + dir * reach)
            else
                local stand = root.Position + dir * reach
                hrp.CFrame = CFrame.lookAt(stand, Vector3.new(root.Position.X, stand.Y, root.Position.Z))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        else
            if auto.walk then hum:MoveTo(hrp.Position) end
            face(root.Position)
            swing(stats)
        end
        if os.clock() - started > 60 then break end -- ตีไม่ตายใน 1 นาที (ติด/หนี) ไปตัวอื่น
        task.wait(0.05)
    end
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
            local best, bestDist
            for _, m in ipairs(ActiveMonsters:GetChildren()) do
                local h = m:FindFirstChildOfClass("Humanoid")
                local root = monsterRoot(m)
                if h and h.Health > 0 and root and wanted(m) then
                    local d = (root.Position - hrp.Position).Magnitude
                    if not bestDist or d < bestDist then best, bestDist = root, d end
                end
            end
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

local function autoLoop()
    while alive() and auto.on do
        local hum = getHum()
        if not (hum and hum.Health > 0) then
            status = "รอเกิดใหม่..."
            task.wait(1)
        elseif not equipWeapon() then
            -- ถือดาบดีสุดให้ได้ก่อน แล้วค่อยไปหาหมู
            status = "ไม่มีดาบ / หยิบดาบไม่ได้ (ซื้อที่ลุงน้อยขายอาวุธ)"
            task.wait(1)
        else
            local pig = nearestPig()
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
            statusPara:SetDesc(("%s\nดาบ: %s  •  หมูในแมพ: %d\nฟันไป %d ครั้ง  •  ฆ่าไป %d ตัว"):format(
                status, tool and tool.Name or "ไม่มี", count, auto.swings, auto.kills))
        end)
        task.wait(0.5)
    end
    if alive() then env.PigRun += 1 end
end)
