-- ขุดเหมือง: ขุดแร่ -> วางโต๊ะคราฟ แปรรูปแร่ (5 ก้อน = 1 แท่ง/เม็ด) -> ขายลุงหมาน
-- อ่านจากโค้ดเกม (PlayerScripts["Survival System"].MiningClient / CraftingTableClient / OreVisibilityClient,
-- PlayerGui.TableCraftingGUI.CraftingClient, MiningConfig / OreMiningConfig / CraftingConfig):
--   หิน = CollectionService tag "MineableRock"  Attribute Harvested = ขุดหมดแล้ว (เกิดใหม่ 60 วิ)
--     หินแร่ (Attribute OreNode) มีชิ้นส่วนที่บอก OreType (Coal / Silver / Gold / Diamond)
--     ขุดแล้วติดคูลดาวน์เฉพาะตัวเรา: LocalPlayer.OreCooldowns[OreNodeId].Value = เวลาที่ขุดได้อีก
--   ขุด = ถือ Pickaxe (tag "SurvivalPickaxe") แล้วกด (tool:Activate) เกมส่ง Mine / SwingEnded เอง ระยะ 7 ดีเล 0.75
--   วางโต๊ะ = ถือ CraftingTable แล้วกด (เกมเรียก PlaceCraftingTable) อยู่ได้ 180 วิ วางซ้ำได้ทุก 10 วิ
--     โต๊ะอยู่ใน workspace.PlayerCraftingTables  กดปุ่มที่โต๊ะ -> OpenCraftingTable(โต๊ะ)
--   คราฟ = CraftingRemotes.Request:InvokeServer("Craft", รหัสสูตร, GUID, โต๊ะ) ยืนห่างโต๊ะไม่เกิน 10
--   ขาย = ร้านแร่ (SellHub "Ore"): Coal Nugget / Silver Ingot / Gold Ingot / Diamond Gem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.MiningRun = (env.MiningRun or 0) + 1
local RUN = env.MiningRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.MiningRun == RUN
end

local Survival = ReplicatedStorage:WaitForChild("Survival System")
local MiningConfig = require(Survival:WaitForChild("MiningConfig"))
local OreConfig = require(Survival:WaitForChild("OreMiningConfig"))
local CraftingConfig = require(Survival:WaitForChild("CraftingConfig"))
local CraftRemotes = Survival:WaitForChild("CraftingRemotes")
local SellHub = ReplicatedStorage:WaitForChild("SellHubSystem")
local SellRemotes = SellHub:WaitForChild("Remotes")
local SellConfig = require(SellHub:WaitForChild("SellHubConfig"))
local OreShop = SellConfig.Shops.Ore

-- แร่ดิบ -> สูตรแปรรูป (ถ่านขายได้เลย ไม่ต้องคราฟ)
local SMELT = {
    { item = "Diamond Nugget", recipe = "diamond_gem" },
    { item = "Gold Nugget", recipe = "gold_ingot" },
    { item = "Silver Nugget", recipe = "silver_ingot" },
}
local ORE_RANK = { Diamond = 4, Gold = 3, Silver = 2, Coal = 1 }

local status = "-"
local auto = {
    on = false,
    walk = true, -- เดินไปขุด (false = วาร์ป)
    stone = false, -- ขุดหินธรรมดาด้วย (ได้ Stone ไว้คราฟของ ขายไม่ได้)
    smelt = true, -- แปรรูปแร่ที่โต๊ะคราฟ
    sell = "เมื่อกระเป๋าเต็ม", -- ไม่ขาย / เมื่อกระเป๋าเต็ม / ทันทีที่มีของขาย
    sellNow = false,
    dist = 2, -- วาร์ปขุด: ยืนห่างผิวหินกี่ studs
    side = "ข้าง", -- วาร์ปขุด: ยืนตรงไหนของหิน ข้าง / บน / ล่าง
    mined = 0, crafted = 0, sold = 0,
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

local function bagState()
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    if not inv then return 0, 100 end
    return inv:GetAttribute("Total") or 0, inv:GetAttribute("Capacity") or 100
end

---------------------------------------------------------------- ของในมือ (Pickaxe / CraftingTable)
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

local function tierOf(name)
    local p = MiningConfig.Pickaxes[name]
    return p and p.Tier or 0
end

local function pickaxes()
    local list = {}
    for _, t in ipairs(tools()) do
        if CollectionService:HasTag(t, MiningConfig.PickaxeTag) or MiningConfig.Pickaxes[t.Name] then
            table.insert(list, t)
        end
    end
    table.sort(list, function(a, b) return tierOf(a.Name) > tierOf(b.Name) end)
    return list
end

local function findTool(name)
    for _, t in ipairs(tools()) do
        if t.Name == name then return t end
    end
end

-- เอาของจากกระเป๋าเกม (คอลเลกชั่น) ออกมาช่องลัดแบบเดียวกับปลูกข้าว/ตีหมู
local lastPull = {}
local function pullToHotbar(name)
    if os.clock() - (lastPull[name] or 0) < 5 then return false end
    lastPull[name] = os.clock()
    local inv = ReplicatedStorage:FindFirstChild("InventorySystem")
    local remote = inv and inv:FindFirstChild("Remotes") and inv.Remotes:FindFirstChild("SetHotbar")
    if not remote then return false end
    local names, seen = {}, {}
    for _, t in ipairs(tools()) do
        if not seen[t.Name] then
            seen[t.Name] = true
            table.insert(names, t.Name)
        end
    end
    if not seen[name] then
        if #names >= 5 then table.remove(names, 1) end -- ช่องลัดมี 5 ช่อง
        table.insert(names, name)
    end
    remote:FireServer(names)
    if waitFor(2, function() return findTool(name) ~= nil end) then return true end
    -- ของในคอลเลกชั่น (โต๊ะคราฟ / Pickaxe) เกมหยิบด้วย EquipItem(ชื่อ) ตอนกดในกระเป๋า
    local equipRemote = inv.Remotes:FindFirstChild("EquipItem")
    if equipRemote then equipRemote:FireServer(name) end
    return waitFor(2, function() return findTool(name) ~= nil end)
end

local function bestOwnedPickaxe()
    local owned = LocalPlayer:FindFirstChild("CollectionState")
    local best, bestTier
    if owned then
        for name, p in pairs(MiningConfig.Pickaxes) do
            local flag = owned:FindFirstChild(name)
            if flag and flag:IsA("BoolValue") and flag.Value and (not bestTier or p.Tier > bestTier) then
                best, bestTier = name, p.Tier
            end
        end
    end
    return best, bestTier
end

local function equip(tool)
    local hum = getHum()
    if not (tool and hum) then return false end
    if tool.Parent ~= LocalPlayer.Character then
        hum:EquipTool(tool)
        if not waitFor(2, function() return tool.Parent == LocalPlayer.Character end) then return false end
        task.wait(0.2)
    end
    return true
end

-- ถือ Pickaxe ที่ดีที่สุดที่มี
local function equipPickaxe()
    local have = pickaxes()[1]
    local best, bestTier = bestOwnedPickaxe()
    if best and (not have or tierOf(have.Name) < bestTier) then
        pullToHotbar(best)
        have = pickaxes()[1]
    end
    if not have then return nil end
    return equip(have) and have or nil
end

---------------------------------------------------------------- ไปที่ (เดิน/วาร์ป)
local function goNear(pos, within, warp)
    local hrp, hum = getRoot(), getHum()
    if not (hrp and hum) then return false end
    local function near()
        local h = getRoot()
        return h and (Vector3.new(pos.X, h.Position.Y, pos.Z) - h.Position).Magnitude <= within
    end
    if near() then return true end
    if warp then
        local away = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
        away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
        local stand = pos + away * math.max(2, within - 1.5) + Vector3.new(0, 3, 0)
        hrp.CFrame = CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.35)
        return true
    end
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

local function face(pos)
    local hrp = getRoot()
    if not hrp then return end
    local flat = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
    if (flat - hrp.Position).Magnitude > 0.1 then hrp.CFrame = CFrame.lookAt(hrp.Position, flat) end
end

---------------------------------------------------------------- หิน
local function oreType(rock)
    local best
    for _, c in ipairs(rock:GetChildren()) do
        local t = c:IsA("BasePart") and c:GetAttribute("OreType")
        if t and (not best or (ORE_RANK[t] or 0) > (ORE_RANK[best] or 0)) then best = t end
    end
    return best
end

local function onCooldown(rock)
    local id = rock:GetAttribute("OreNodeId")
    local cds = LocalPlayer:FindFirstChild("OreCooldowns")
    local v = id and cds and cds:FindFirstChild(tostring(id))
    return v ~= nil and workspace:GetServerTimeNow() < v.Value
end

-- หินที่เพิ่งโดนขุด (เกมส่ง RockEffect "Hit") ใช้เช็คว่าการขุดได้ผล
local MiningRemotes = Survival:WaitForChild("MiningRemotes")
local lastHit = setmetatable({}, { __mode = "k" })
local swingId = 1000000 -- รหัสท่าฟันตอนส่งรีโมทเอง (เกมเริ่มนับจาก 1 ใช้เลขสูงไม่ให้ชนกัน)
local hitConn = MiningRemotes:WaitForChild("RockEffect").OnClientEvent:Connect(function(rock, kind)
    if kind == "Hit" and typeof(rock) == "Instance" then lastHit[rock] = os.clock() end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    hitConn:Disconnect()
end)

local function mineable(rock, tier)
    if not (rock:IsA("Model") and rock:IsDescendantOf(workspace)) or rock:GetAttribute("Harvested") then return false end
    if rock:GetAttribute("TutorialRole") then return false end
    if rock:GetAttribute("OreNode") then
        if onCooldown(rock) then return false end
        local t = oreType(rock)
        if t == "Diamond" and tier < 2 then return false end -- แร่เพชรต้อง Gold Pickaxe ขึ้นไป
        return true
    end
    return auto.stone
end

-- เลือกหิน: แร่แพงสุดก่อน ราคาเท่ากันเอาที่ใกล้สุด
local function pickRock(tier)
    local hrp = getRoot()
    if not hrp then return nil end
    local best, bestRank, bestDist
    for _, rock in ipairs(CollectionService:GetTagged(MiningConfig.RockTag)) do
        if mineable(rock, tier) then
            local rank = rock:GetAttribute("OreNode") and (ORE_RANK[oreType(rock)] or 1) or 0
            local d = (rock:GetPivot().Position - hrp.Position).Magnitude
            if not best or rank > bestRank or (rank == bestRank and d < bestDist) then
                best, bestRank, bestDist = rock, rank, d
            end
        end
    end
    return best
end

-- ครึ่งความกว้างก้อนหิน (แนวราบ): หินก้อนใหญ่ จุดกลางอยู่ลึก เดินชิดแล้วก็ยังห่างจุดกลางเกินระยะ
local function rockRadius(rock)
    local ok, size = pcall(function() return rock:GetExtentsSize() end)
    return ok and math.clamp(math.min(size.X, size.Z) / 2, 0, 12) or 0
end

-- วาร์ปขุด: จุดยืนรอบก้อนหิน (ข้าง = ฝั่งที่เราอยู่, บน = เหนือยอดหิน, ล่าง = ใต้ก้นหิน มุดดิน)
local function rockStand(rock, from)
    local pos = rock:GetPivot().Position
    local ok, size = pcall(function() return rock:GetExtentsSize() end)
    size = ok and size or Vector3.new(4, 4, 4)
    local d = math.max(auto.dist, 0)
    -- บน/ล่าง: ห่างจากยอด/ก้นหินตามที่เลื่อน (เดิมโดนจำกัดไว้ที่ระยะขุด เลยเลื่อนแล้วตัวไม่ขยับ)
    local up = size.Y / 2 + d + 1.5
    if auto.side == "บน" then return pos + Vector3.new(0, up, 0), true end
    if auto.side == "ล่าง" then return pos - Vector3.new(0, up, 0), true end
    local away = Vector3.new(from.X - pos.X, 0, from.Z - pos.Z)
    away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
    local stand = pos + away * (math.min(size.X, size.Z) / 2 + d)
    -- ยืนบนพื้นจริง (จุดกลางหินอาจจมดิน/ลอย) ไม่งั้นตัวไปค้างในดินแล้วตกแมพ
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, rock }
    local hit = workspace:Raycast(stand + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
    if hit then stand = Vector3.new(stand.X, hit.Position.Y + 3, stand.Z) end
    return stand, false
end

-- ค้างตัวไว้ที่จุดยืนทุกเฟรม (ไม่ Anchored เพราะเกมไม่ให้ขุดตอนตัว Anchored) กันร่วง/ไหลออกจากระยะ
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

-- ยืนบน/ใต้หินต้องทะลุหิน/พื้น: ปิดชนฝั่งเราทุกเฟรมระหว่างขุด (เลิกแล้วกลับปกติเอง)
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

-- เลิกค้างตัว: ถ้ามุดดิน/ลอยอยู่ วางกลับขึ้นพื้นข้างหินก่อนเปิดชนคืน (ไม่งั้นตกแมพ)
local function release(rock)
    if holdCF and noclip and rock then
        local side = auto.side
        auto.side = "ข้าง"
        local ok, stand = pcall(rockStand, rock, holdCF.Position + Vector3.new(3, 0, 0))
        auto.side = side
        local hrp = getRoot()
        if ok and hrp then
            hrp.CFrame = CFrame.new(stand)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end
    holdCF = nil
    noclip = false
end

local function mineRock(rock, pick)
    local tier = tierOf(pick.Name)
    local pos = rock:GetPivot().Position
    local within = math.max(MiningConfig.Reach - 3, rockRadius(rock) + 2.5) -- ยืนชิดผิวหิน
    status = ("ไปขุด%s"):format(rock:GetAttribute("OreNode") and (" แร่ " .. tostring(oreType(rock))) or "หิน")
    if not goNear(pos, within, not auto.walk) then
        status = "ไปที่หินไม่ถึง"
        return false
    end
    status = "ขุด..."
    local started = os.clock()
    local tries, direct = 0, false
    while alive() and auto.on and mineable(rock, tier) and not env.AirdropBusy do
        if pick.Parent ~= LocalPlayer.Character and not equip(pick) then release(rock) return false end
        local hrp = getRoot()
        if not hrp then release(rock) return false end
        if auto.walk and (Vector3.new(pos.X, hrp.Position.Y, pos.Z) - hrp.Position).Magnitude > within + 2 then
            if not goNear(pos, within, not auto.walk) then return false end
        end
        local hum = getHum()
        if hum then hum:MoveTo(hrp.Position) end -- หยุดเดิน (เกมไม่ให้ขุดตอนตัวล็อก/กำลังเดินชน)
        if auto.walk then
            noclip = false
            face(pos)
        else
            -- วาร์ปขุด: ยืนตามระยะ/ด้านที่เลือก หันหน้า (ก้ม/เงย) เข้าหาหิน
            local stand, vertical = rockStand(rock, holdCF and holdCF.Position or hrp.Position)
            noclip = vertical
            holdCF = CFrame.lookAt(stand, vertical and pos or Vector3.new(pos.X, stand.Y, pos.Z))
            hrp.CFrame = holdCF
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        if not direct then
            pick:Activate() -- เกมส่ง Mine / SwingEnded เองตามจังหวะ (ดีเล 0.75)
            task.wait(MiningConfig.SwingCooldown + 0.1)
            tries += 1
            -- กด 3 ทีแล้วหินไม่สั่นเลย (เกมไม่รับการกดจากสคริปต์): ส่งรีโมทเองแบบเดียวกับเกม
            if tries >= 3 and lastHit[rock] == nil then direct = true end
        else
            swingId += 1
            local id = swingId
            MiningRemotes.Mine:FireServer(id)
            task.wait(MiningConfig.HitDelay + 0.25) -- ท่าฟันจบ
            MiningRemotes.SwingEnded:FireServer(id)
            task.wait(math.max(0.1, MiningConfig.SwingCooldown - MiningConfig.HitDelay - 0.15))
        end
        if os.clock() - started > 40 then release(rock) return false end -- ขุดไม่แตกใน 40 วิ ไปก้อนอื่น
    end
    release(rock)
    auto.mined += 1
    return true
end

---------------------------------------------------------------- โต๊ะคราฟ
local Tables = workspace:WaitForChild("PlayerCraftingTables")
local myTable -- โต๊ะที่เราวางล่าสุด
local tableArg -- ค่าที่เกมส่งมากับ OpenCraftingTable (ใช้ตอนคราฟ)
local tableOpenAt = 0
local conns = {
    CraftRemotes:WaitForChild("OpenCraftingTable").OnClientEvent:Connect(function(arg)
        tableArg, tableOpenAt = arg, os.clock()
    end),
}

local function isMine(model)
    for _, key in ipairs({ "OwnerUserId", "OwnerId", "UserId" }) do
        if model:GetAttribute(key) == LocalPlayer.UserId then return true end
    end
    for _, key in ipairs({ "Owner", "OwnerName" }) do
        local v = model:GetAttribute(key)
        if v == LocalPlayer.Name or v == LocalPlayer.DisplayName then return true end
    end
    return model == myTable
end

local function tableAlive(model)
    if not (model and model:IsDescendantOf(Tables)) then return false end
    local exp = model:GetAttribute("ExpiresAt")
    return not exp or exp - workspace:GetServerTimeNow() > 8 -- เหลือไม่ถึง 8 วิ วางใหม่ดีกว่า
end

local function findMyTable()
    if tableAlive(myTable) then return myTable end
    for _, m in ipairs(Tables:GetChildren()) do
        if isMine(m) and tableAlive(m) then
            myTable = m
            return m
        end
    end
end

local lastPlace = 0
local function placeTable()
    if os.clock() - lastPlace < (CraftingConfig.TablePlaceCooldown or 10) + 0.5 then return nil end
    local tool = findTool("CraftingTable")
    if not tool then
        pullToHotbar("CraftingTable")
        tool = findTool("CraftingTable")
    end
    if not tool then
        status = "ไม่มีโต๊ะคราฟ (คราฟที่เมนู 🔨: ไม้ 10 + หนังสัตว์ 10)"
        return nil
    end
    if not equip(tool) then return nil end
    lastPlace = os.clock()
    local before = {}
    for _, m in ipairs(Tables:GetChildren()) do before[m] = true end
    status = "วางโต๊ะคราฟ..."
    -- เหมือนที่เกมทำตอนกดใช้โต๊ะ: PlaceCraftingTable:InvokeServer() (ต้องถือโต๊ะอยู่)
    local ok, res = pcall(function() return CraftRemotes.PlaceCraftingTable:InvokeServer() end)
    if ok and type(res) == "table" and res.Message then status = "โต๊ะคราฟ: " .. tostring(res.Message) end
    local placed
    waitFor(4, function()
        local hrp = getRoot()
        for _, m in ipairs(Tables:GetChildren()) do
            if not before[m] and hrp and (m:GetPivot().Position - hrp.Position).Magnitude < 20 then
                placed = m
                return true
            end
        end
        return false
    end)
    myTable = placed or findMyTable()
    return myTable
end

local function tablePrompt(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
end

local function needSmelt()
    for _, s in ipairs(SMELT) do
        if count(s.item) >= 5 then return true end
    end
    return false
end

local function smelt()
    local tbl = findMyTable() or placeTable()
    if not tbl then
        if status == "-" or not status:find("โต๊ะ", 1, true) then status = "รอวางโต๊ะคราฟได้..." end
        return false
    end
    local craftDist = (CraftingConfig.TableCraftDistance or 10) - 3
    if not goNear(tbl:GetPivot().Position, craftDist, not auto.walk) then
        status = "ไปที่โต๊ะคราฟไม่ถึง"
        return false
    end
    -- เปิดโต๊ะเหมือนกด E (เกมส่งค่าโต๊ะมาให้ใช้ตอนคราฟ) ไม่ได้ก็ใช้ตัวโต๊ะแทน
    local prompt = tablePrompt(tbl)
    local askedAt = os.clock()
    if prompt and typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
    local arg = waitFor(2, function() return tableOpenAt >= askedAt end) and tableArg or tbl
    local any = false
    for _, s in ipairs(SMELT) do
        while alive() and auto.on and count(s.item) >= 5 do
            status = "แปรรูป " .. s.item .. "..."
            local before = count(s.item)
            local ok, res = pcall(function()
                return CraftRemotes.Request:InvokeServer("Craft", s.recipe, HttpService:GenerateGUID(false), arg)
            end)
            task.wait((CraftingConfig.CraftCooldown or 0.4) + 0.1)
            if count(s.item) >= before then
                status = "คราฟไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and res.Message or res)
                break
            end
            auto.crafted += 1
            any = true
        end
    end
    -- ปิดหน้าต่างคราฟที่เกมเปิดให้
    pcall(function()
        local gui = LocalPlayer.PlayerGui:FindFirstChild("TableCraftingGUI")
        if gui then gui.Window.Visible = false end
    end)
    return any
end

---------------------------------------------------------------- ขายที่ลุงหมาน
local opened = { shopId = nil, at = 0 }
table.insert(conns, SellRemotes:WaitForChild("Open").OnClientEvent:Connect(function(_, state)
    if type(state) == "table" and state.shopId then opened.shopId, opened.at = state.shopId, os.clock() end
end))
task.spawn(function()
    while alive() do task.wait(1) end
    for _, c in ipairs(conns) do c:Disconnect() end
end)

local function sellable()
    local n = 0
    for _, name in ipairs(OreShop.Order) do n += count(name) end
    return n
end

-- จุดยืนหน้าร้าน: ที่ผู้เล่นบันทึกไว้ หรือหน้าตัวลุงหมาน (ทิศที่ลุงหันอยู่) ห่าง 5 studs บนพื้น
-- ห้ามเดิน/วาร์ปไปข้างร้าน เพราะเข้าไปแล้วติดออกไม่ได้
local function shopFront(part)
    if env.MiningShopSpot then return env.MiningShopSpot end
    local npc = workspace:FindFirstChild(OreShop.Title)
    local root = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
    local base = root or part
    local look = Vector3.new(base.CFrame.LookVector.X, 0, base.CFrame.LookVector.Z)
    look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
    local stand = base.Position + look * 5
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local hit = workspace:Raycast(stand + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
    if hit then stand = Vector3.new(stand.X, hit.Position.Y + 3, stand.Z) end
    return stand
end

local function sellOre()
    if sellable() <= 0 then return true end
    local part = workspace:FindFirstChild(OreShop.PartName, true)
    local prompt = part and part:FindFirstChild(OreShop.PromptName)
    if not prompt then
        status = "หาร้านลุงหมานไม่เจอ"
        return false
    end
    status = auto.walk and "เดินไปขายแร่..." or "วาร์ปไปขายแร่..."
    local front = shopFront(part)
    local ok
    if auto.walk then
        ok = goNear(front, 2, false)
    else
        local hrp = getRoot()
        if hrp then
            local face = Vector3.new(part.Position.X, front.Y, part.Position.Z)
            hrp.CFrame = (face - front).Magnitude > 0.1 and CFrame.lookAt(front, face) or CFrame.new(front)
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.4)
            ok = true
        end
    end
    if not ok then
        status = "ไปหน้าร้านลุงหมานไม่ถึง"
        return false
    end
    local askedAt = os.clock()
    if typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
    if not waitFor(4, function() return opened.at >= askedAt end) then
        status = "กดขายแร่แล้วร้านไม่เปิด"
        return false
    end
    local hum = getHum()
    if hum then hum:UnequipTools() end
    local shopId, guid = opened.shopId, HttpService:GenerateGUID(false)
    local ok, res
    for _ = 1, 3 do
        ok, res = pcall(function()
            return SellRemotes.Request:InvokeServer("SellAll", nil, nil, guid, shopId)
        end)
        if ok then break end
        task.wait(0.3)
    end
    pcall(function() SellRemotes.Request:InvokeServer("Close", nil, nil, nil, shopId) end)
    pcall(function()
        local gui = LocalPlayer.PlayerGui:FindFirstChild("SellHubGui")
        if gui then gui.Enabled = false end
        if LocalPlayer:GetAttribute("UIBusyOwner") == "SellHub" then
            LocalPlayer:SetAttribute("UIBusy", false)
            LocalPlayer:SetAttribute("UIBusyOwner", nil)
        end
    end)
    if ok and type(res) == "table" and res.ok then
        auto.sold += tonumber(res.totalMoney) or 0
        status = ("ขายแร่ %s ชิ้น ได้ %s บาท"):format(tostring(res.soldCount), tostring(res.totalMoney))
        return true
    end
    status = "ขายไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and (res.reason or res.message) or res)
    return false
end

local function wantSell()
    if auto.sellNow then return true end
    if auto.sell == "ไม่ขาย" or sellable() <= 0 then return false end
    if auto.sell == "ทันทีที่มีของขาย" then return true end
    local total, cap = bagState()
    return total >= cap
end

local function bagFull()
    local total, cap = bagState()
    return total >= cap
end

---------------------------------------------------------------- วนอัตโนมัติ
local function autoLoop()
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
        elseif auto.smelt and needSmelt() and (bagFull() or wantSell() or not pickRock(tierOf((pickaxes()[1] or {}).Name or ""))) then
            -- แปรรูปก่อนขาย / ตอนกระเป๋าเต็ม / ตอนไม่มีหินให้ขุด
            if not smelt() then task.wait(2) end
        elseif wantSell() then
            auto.sellNow = false
            if not sellOre() then task.wait(3) end
        else
            local pick = equipPickaxe()
            if not pick then
                status = "ไม่มี Pickaxe"
                task.wait(2)
            else
                local rock = pickRock(tierOf(pick.Name))
                if rock then
                    mineRock(rock, pick)
                elseif auto.smelt and needSmelt() then
                    smelt()
                else
                    status = "ไม่มีแร่ให้ขุด รอเกิดใหม่..."
                    task.wait(2)
                end
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
        warn("[Mining] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.MiningFluent then
        pcall(function() env.MiningFluent:Destroy() end)
    end
    env.MiningFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ขุดเหมือง",
        SubTitle = "Mining",
        TabWidth = 150,
        Size = UDim2.fromOffset(560, 400),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("ขุดเหมือง")
section:AddToggle("MineAuto", {
    Title = "ขุดเหมืองอัตโนมัติ",
    Description = "ขุดแร่ (แพงสุดก่อน) -> วางโต๊ะคราฟแปรรูปแร่ -> ขายลุงหมาน -> วนไปเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) end
end)
section:AddDropdown("MineMove", {
    Title = "วิธีไป",
    Description = "เดิน = ช้ากว่าแต่ปลอดภัย (กันโดนแบน) • วาร์ป = เร็ว",
    Values = { "เดิน", "วาร์ป" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.walk = v ~= "วาร์ป"
end)
section:AddSlider("MineDist", {
    Title = "วาร์ปขุด: ระยะห่างจากหิน",
    Description = "ใช้ตอนเลือกวาร์ป • ห่างจากผิวหิน (ห่างเกินระยะขุด 7 จากหิน หินจะไม่สั่น ให้ลดลง)",
    Default = 2,
    Min = 0,
    Max = 8,
    Rounding = 1,
}):OnChanged(function(v)
    auto.dist = v
end)
section:AddDropdown("MineSide", {
    Title = "วาร์ปขุด: ยืนตรงไหน",
    Description = "ข้าง = ข้างก้อนหิน • บน = ลอยเหนือหิน • ล่าง = มุดใต้หิน",
    Values = { "ข้าง", "บน", "ล่าง" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.side = v
end)
section:AddToggle("MineSmelt", {
    Title = "แปรรูปแร่ที่โต๊ะคราฟ",
    Description = "แร่เงิน/ทอง/เพชร ครบ 5 ก้อน วางโต๊ะแล้วแปรรูปเป็นแท่ง/เม็ด (ร้านรับซื้อแค่ของแปรรูปแล้ว)",
    Default = true,
}):OnChanged(function(v)
    auto.smelt = v
end)
section:AddToggle("MineStone", {
    Title = "ขุดหินธรรมดาด้วย",
    Description = "ได้ Stone ไว้คราฟของ (ขายไม่ได้) ปิดไว้ = ขุดเฉพาะหินแร่",
    Default = false,
}):OnChanged(function(v)
    auto.stone = v
end)
local sellSection = Tabs.main:AddSection("ขายแร่")
sellSection:AddDropdown("MineSell", {
    Title = "ขายแร่เมื่อไหร่",
    Description = "ขาย Coal Nugget / Silver Ingot / Gold Ingot / Diamond Gem ที่ลุงหมาน (ของที่ล็อกขายไว้ไม่ขาย)",
    Values = { "เมื่อกระเป๋าเต็ม", "ทันทีที่มีของขาย", "ไม่ขาย" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.sell = v
end)
sellSection:AddButton({
    Title = "บันทึกจุดยืนหน้าร้าน",
    Description = "ไปยืนหน้าร้านลุงหมานตรงที่กด E ขายแร่ได้ แล้วกดปุ่มนี้ สคริปต์จะไปยืนตรงนี้ทุกครั้งที่ขาย",
    Callback = function()
        local hrp = getRoot()
        if hrp then
            env.MiningShopSpot = hrp.Position
            Fluent:Notify({ Title = "บันทึกแล้ว", Content = "จุดยืนหน้าร้านลุงหมาน", Duration = 4 })
        end
    end,
})
local selling = false
sellSection:AddButton({
    Title = "ขายแร่ตอนนี้",
    Description = "แปรรูปแร่ที่ครบ 5 ก้อนแล้วไปขายเดี๋ยวนี้ (ขุดอัตโนมัติเปิดอยู่ จะขายเสร็จแล้วกลับมาขุดต่อ)",
    Callback = function()
        if auto.on then
            auto.sellNow = true
        elseif not selling then
            selling = true
            task.spawn(function()
                auto.on = true -- ให้เดินไปได้ (goNear หยุดตอน auto.on = false)
                if auto.smelt and needSmelt() then smelt() end
                sellOre()
                auto.on = false
                selling = false
            end)
        end
    end,
})
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local pick = pickaxes()[1]
            local total, cap = bagState()
            statusPara:SetDesc(("%s\nPickaxe: %s  •  กระเป๋า %d/%d\nแร่: ถ่าน %d • เงิน %d • ทอง %d • เพชร %d\nขุด %d ก้อน • แปรรูป %d • ขายได้ %d บาท"):format(
                status, pick and pick.Name or "ไม่มี", total, cap,
                count("Coal Nugget"), count("Silver Nugget"), count("Gold Nugget"), count("Diamond Nugget"),
                auto.mined, auto.crafted, auto.sold))
        end)
        task.wait(0.5)
    end
    if alive() then env.MiningRun += 1 end
end)
