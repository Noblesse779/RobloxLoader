-- อัปเกรด & เงินฟรี: รับเช็คอินรายวัน / ซื้อกระเป๋าใหญ่ขึ้น / ซื้ออาวุธที่ดีกว่า / ย้ายไปเซิฟคนน้อย
-- อ่านจากโค้ดเกม:
--   เช็คอิน: DailyLoginSystem.Remotes.GetState() -> { ok, CanClaim, Day, NextAt, ServerNow, Days[i].Available }
--            Claim(i) รับวันที่ i (ได้เงิน 30k-50k / กระเป๋า +1 / Diamond Gem x30 / Gold Pickaxe / Sushi Rod)
--   กระเป๋า: กดปุ่ม BagShopPrompt (sellbagpart) -> BagShopSystem.Remotes.OpenShop { ok, bagsize, money }
--            Purchase:InvokeServer(ความจุระดับถัดไป) ต้องซื้อทีละระดับ แล้ว CloseShop:FireServer()
--   อาวุธ: กดปุ่ม WeaponShopPrompt (ลุงน้อยขายอาวุธ) -> WeaponShopSystem.Remotes.OpenShop { ok, money, owned }
--          Purchase:InvokeServer(ชื่ออาวุธ)  ของที่มีแล้ว = LocalPlayer.CollectionState BoolValue
--   คราฟพลั่ว: Survival System.CraftingRemotes.Request:InvokeServer("Craft", รหัสสูตร, GUID, nil) คราฟมือ ไม่ต้องมีโต๊ะ
--            gold_pickaxe = 50k + ไม้ 30 + Gold Ingot 30 (ขุด 4 ที/ก้อน ขุดเพชรได้)
--            diamond_pickaxe = 75k + ไม้ 30 + Diamond Gem 30 (ขุด 3 ที/ก้อน)
--            ล็อกขาย: InventorySystem.Remotes.SetSaleLock:InvokeServer(ชื่อของ, true/false) ร้านจะไม่รับของที่ล็อก
--   เซิฟ: GetServerList() -> { jobId, players, maxPlayers, isCurrent, hostName }  ย้าย: ServerBrowserJoin(jobId)
-- ระหว่างไปร้าน งานอื่นในตัวรวมพักรอ (env.AirdropBusy ตัวเดียวกับแอร์ดรอป/ขายของ)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.UpgradeRun = (env.UpgradeRun or 0) + 1
local RUN = env.UpgradeRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.UpgradeRun == RUN
end

local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local status = "-"
local opt = {
    daily = false, bag = false, weapon = false, pickaxe = false, keep = false,
    reserve = 0,   -- เก็บเงินไว้อย่างน้อยเท่านี้ ไม่เอาไปซื้อ
    busy = false,
}

local function money()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local m = ls and ls:FindFirstChild("Money")
    return m and m.Value or 0
end

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

local function fmt(n)
    local s = tostring(math.floor(n or 0))
    local k
    repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end

---------------------------------------------------------------- เช็คอินรายวัน
local Daily = ReplicatedStorage:WaitForChild("DailyLoginSystem"):WaitForChild("Remotes")
local dailyInfo = "-"

local function dailyClaim()
    local ok, st = pcall(function() return Daily.GetState:InvokeServer() end)
    if not ok or type(st) ~= "table" or not st.ok then
        dailyInfo = "ดูสถานะเช็คอินไม่ได้"
        return false
    end
    if st.CanClaim then
        for i, d in ipairs(st.Days or {}) do
            if d.Available then
                local ok2, res = pcall(function() return Daily.Claim:InvokeServer(i) end)
                local msg = ok2 and type(res) == "table" and res.message
                dailyInfo = "รับวันที่ " .. i .. " (" .. tostring(d.Label or ""):gsub("\n", " ") .. ")"
                    .. (msg and (" • " .. msg) or "")
                return true
            end
        end
    end
    local left = math.max(0, (st.NextAt or 0) - (st.ServerNow or 0))
    dailyInfo = ("รับแล้ว รอบถัดไปอีก %02d:%02d ชม."):format(math.floor(left / 3600), math.floor(left / 60) % 60)
    return false
end

---------------------------------------------------------------- ไปร้าน
-- จุดยืน: หน้า NPC ห่าง 5 (มีพื้น) ไม่มี NPC = ข้างปุ่มห่าง 4
local function standAt(npc, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local function ground(p)
        local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
        return hit and Vector3.new(p.X, hit.Position.Y + 3, p.Z)
    end
    local root = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
    if root then
        local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if look.Magnitude > 0.1 then
            local g = ground(root.Position + look.Unit * 5)
            if g then return g, root.Position end
        end
    end
    local look = Vector3.new(part.CFrame.LookVector.X, 0, part.CFrame.LookVector.Z)
    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
    return ground(part.Position + look.Unit * 4) or part.Position + Vector3.new(0, 3, 0), part.Position
end

local function findPrompt(name)
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Name == name then return d end
    end
end

-- วาร์ปไปร้าน กดปุ่ม รอร้านเปิด แล้วให้ fn ซื้อ ปิดร้าน วาร์ปกลับ
local function visitShop(promptName, npcName, openRemote, closeRemote, guiName, fn)
    if opt.busy then return end
    local prompt = findPrompt(promptName)
    local hrp = getRoot()
    if not prompt or not hrp then
        status = "หาร้านไม่เจอ"
        return
    end
    opt.busy = true
    env.AirdropBusy = true -- งานอื่นพักรอ
    local home = hrp.CFrame
    local part = prompt.Parent:IsA("Attachment") and prompt.Parent.Parent or prompt.Parent
    local stand, face = standAt(workspace:FindFirstChild(npcName), part)
    hrp.CFrame = CFrame.lookAt(stand, Vector3.new(face.X, stand.Y, face.Z))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.4)
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:UnequipTools() end

    local state
    local conn = openRemote.OnClientEvent:Connect(function(s)
        if type(s) == "table" and s.ok and not s.close then state = s end
    end)
    if typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
    if waitFor(4, function() return state ~= nil end) then
        pcall(fn, state)
    else
        status = "กดปุ่มร้านแล้วร้านไม่เปิด"
    end
    conn:Disconnect()
    pcall(function() closeRemote:FireServer() end)
    pcall(function()
        local gui = LocalPlayer.PlayerGui:FindFirstChild(guiName)
        if gui then gui.Enabled = false end
    end)
    task.wait(0.3)
    hrp = getRoot()
    if hrp then
        hrp.CFrame = home
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
    env.AirdropBusy = false
    opt.busy = false
end

---------------------------------------------------------------- กระเป๋า
local BagShop = ReplicatedStorage:WaitForChild("BagShopSystem")
local BagConfig = require(BagShop:WaitForChild("BagShopConfig"))
local BagRemotes = BagShop:WaitForChild("Remotes")

local function bagCapacity()
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    return inv and inv:GetAttribute("Capacity") or BagConfig.DefaultCapacity or 100
end

local function nextBag()
    return BagConfig.GetNextTier(bagCapacity())
end

local function buyBag()
    local tier = nextBag()
    if not tier then status = "กระเป๋าเต็มระดับสูงสุดแล้ว" return end
    if money() - tier.Price < opt.reserve then
        status = "เงินไม่พอซื้อกระเป๋า " .. fmt(tier.Capacity) .. " ช่อง (" .. fmt(tier.Price) .. ")"
        return
    end
    status = "ไปซื้อกระเป๋า " .. fmt(tier.Capacity) .. " ช่อง..."
    visitShop(BagConfig.PromptName, "ลุงหมายขายกระเป๋า", BagRemotes.OpenShop, BagRemotes.CloseShop, "Bagshop", function()
        -- ซื้อต่อทีละระดับจนเงินไม่พอ
        for _ = 1, #BagConfig.Tiers do
            local t = nextBag()
            if not t or money() - t.Price < opt.reserve then break end
            local ok, res = pcall(function() return BagRemotes.Purchase:InvokeServer(t.Capacity) end)
            if not (ok and type(res) == "table" and res.ok) then
                status = "ซื้อกระเป๋าไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and res.message or res)
                return
            end
            status = "ซื้อกระเป๋า " .. fmt(t.Capacity) .. " ช่องแล้ว"
            waitFor(2, function() return bagCapacity() >= t.Capacity end)
            task.wait((BagConfig.PurchaseCooldown or 0.5) + 0.2)
        end
    end)
end

---------------------------------------------------------------- อาวุธ
local WeaponShop = ReplicatedStorage:WaitForChild("WeaponShopSystem")
local WeaponShopConfig = require(WeaponShop:WaitForChild("WeaponShopConfig"))
local WeaponRemotes = WeaponShop:WaitForChild("Remotes")

local function owns(name)
    local col = LocalPlayer:FindFirstChild("CollectionState")
    local v = col and col:FindFirstChild(name)
    return v ~= nil and v:IsA("BoolValue") and v.Value
end

-- อาวุธที่ซื้อด้วยเงินในเกมได้ เรียงถูกไปแพง (ข้ามของยศ/ของ Robux)
local function weaponList()
    local list = {}
    for _, w in ipairs(WeaponShopConfig.Weapons) do
        if w.Price and not w.RankOnly and not w.RobuxOnly and not w.EventOnly then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.Price < b.Price end)
    return list
end

-- อาวุธที่ยังไม่มี ตัวถัดไป (ซื้อไล่ขึ้นทีละตัว)
local function nextWeapon()
    for _, w in ipairs(weaponList()) do
        if not owns(w.ToolName) then return w end
    end
end

local function buyWeapon()
    local w = nextWeapon()
    if not w then status = "มีอาวุธที่ซื้อได้ครบแล้ว" return end
    if money() - w.Price < opt.reserve then
        status = "เงินไม่พอซื้อ " .. w.ToolName .. " (" .. fmt(w.Price) .. ")"
        return
    end
    status = "ไปซื้อ " .. w.ToolName .. "..."
    visitShop(WeaponShopConfig.PromptName, WeaponShopConfig.PromptNpcName, WeaponRemotes.OpenShop,
        WeaponRemotes.CloseShop, "Weaponshop", function()
        local ok, res = pcall(function() return WeaponRemotes.Purchase:InvokeServer(w.ToolName) end)
        if ok and type(res) == "table" and res.ok then
            status = "ซื้อ " .. w.ToolName .. " แล้ว (ตีหมูจะหยิบอันที่ดีสุดเอง)"
        else
            status = "ซื้อ " .. w.ToolName .. " ไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and res.message or res)
        end
    end)
end

---------------------------------------------------------------- คราฟพลั่ว
local Survival = ReplicatedStorage:WaitForChild("Survival System")
local CraftRemotes = Survival:WaitForChild("CraftingRemotes")
local HttpService = game:GetService("HttpService")
local SetSaleLock = ReplicatedStorage:WaitForChild("InventorySystem"):WaitForChild("Remotes"):WaitForChild("SetSaleLock")

-- ไล่ขึ้น: ทอง -> เพชร (มีอันดีกว่าแล้วไม่ต้องทำอันต่ำ)
local PICKAXES = {
    { id = "gold_pickaxe", name = "Gold Pickaxe", money = 50000, wood = 30, item = "Gold Ingot", need = 30 },
    { id = "diamond_pickaxe", name = "Diamond Pickaxe", money = 75000, wood = 30, item = "Diamond Gem", need = 30 },
}

local function count(name)
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    local v = inv and inv:FindFirstChild(name)
    return v and v.Value or 0
end

local function nextPickaxe()
    if owns("Diamond Pickaxe") then return nil end
    if owns("Gold Pickaxe") then return PICKAXES[2] end
    return PICKAXES[1]
end

local function pickaxeNeeds(p)
    local miss = {}
    if count("Wood") < p.wood then miss[#miss + 1] = ("ไม้ %d/%d"):format(count("Wood"), p.wood) end
    if count(p.item) < p.need then miss[#miss + 1] = ("%s %d/%d"):format(p.item, count(p.item), p.need) end
    if money() - p.money < opt.reserve then miss[#miss + 1] = ("เงิน %s/%s"):format(fmt(money()), fmt(p.money + opt.reserve)) end
    return miss
end

local function setLock(name, on)
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    local v = inv and inv:FindFirstChild(name)
    if not v or (v:GetAttribute("SaleLocked") == true) == on then return end
    pcall(function() SetSaleLock:InvokeServer(name, on) end)
end

-- ล็อกของที่ต้องใช้คราฟพลั่วตัวถัดไปไว้ไม่ให้ขาย คราฟเสร็จ/ปิดสวิตช์ = ปลดล็อก
local function syncLocks()
    local p = nextPickaxe()
    for _, q in ipairs(PICKAXES) do
        setLock(q.item, opt.keep and p ~= nil and q == p)
    end
end

local function craftPickaxe()
    local p = nextPickaxe()
    if not p then status = "มี Diamond Pickaxe แล้ว" return end
    local miss = pickaxeNeeds(p)
    if #miss > 0 then
        status = p.name .. " ยังขาด: " .. table.concat(miss, ", ")
        return
    end
    local ok, res = pcall(function()
        return CraftRemotes.Request:InvokeServer("Craft", p.id, HttpService:GenerateGUID(false), nil)
    end)
    task.wait(0.5)
    if owns(p.name) then
        status = "คราฟ " .. p.name .. " แล้ว (ขุดเหมืองจะหยิบอันดีสุดเอง)"
        syncLocks()
    else
        status = "คราฟ " .. p.name .. " ไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and res.Message or res)
    end
end

---------------------------------------------------------------- ย้ายเซิฟ
local serverInfo = "-"

local function queueReload()
    local queue = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or (typeof(syn) == "table" and syn.queue_on_teleport)
    if queue then pcall(queue, 'loadstring(game:HttpGet("' .. BASE .. 'BaanLung.lua"))()') end
end

local function hopLowest()
    local ok, list = pcall(function() return ReplicatedStorage.GetServerList:InvokeServer() end)
    if not ok or type(list) ~= "table" then
        serverInfo = "โหลดรายชื่อเซิฟไม่ได้"
        return
    end
    local best, mine
    for _, s in ipairs(list) do
        if s.isCurrent then
            mine = s
        elseif (s.players or 0) < (s.maxPlayers or 0)
            and (not best or s.players < best.players) then
            best = s
        end
    end
    if not best then
        serverInfo = "ไม่มีเซิฟอื่นที่ว่าง"
        return
    end
    if mine and best.players >= mine.players then
        serverInfo = ("เซิฟนี้คนน้อยสุดแล้ว (%d คน)"):format(mine.players)
        return
    end
    serverInfo = ("ย้ายไป %s (%d/%d คน)..."):format(tostring(best.hostName), best.players, best.maxPlayers)
    queueReload()
    local ok2, res = pcall(function() return ReplicatedStorage.ServerBrowserJoin:InvokeServer(best.jobId) end)
    if not (ok2 and type(res) == "table" and res.ok) then
        serverInfo = "ย้ายไม่สำเร็จ: " .. tostring(ok2 and type(res) == "table" and res.message or res)
    end
end

---------------------------------------------------------------- ลูปอัตโนมัติ
task.spawn(function()
    local lastDaily = -math.huge
    while alive() do
        if opt.daily and os.clock() - lastDaily >= 60 then
            lastDaily = os.clock()
            pcall(dailyClaim)
        end
        pcall(syncLocks)
        if opt.pickaxe then
            local p = nextPickaxe()
            if p and #pickaxeNeeds(p) == 0 then pcall(craftPickaxe) end
        end
        if not opt.busy and not env.AirdropBusy then
            local tier = opt.bag and nextBag()
            if tier and money() - tier.Price >= opt.reserve then
                buyBag()
            else
                local w = opt.weapon and nextWeapon()
                if w and money() - w.Price >= opt.reserve then buyWeapon() end
            end
        end
        task.wait(5)
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
        warn("[Upgrade] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.UpgradeFluent then
        pcall(function() env.UpgradeFluent:Destroy() end)
    end
    env.UpgradeFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "อัปเกรด",
        SubTitle = "Upgrade",
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

local daily = Tabs.main:AddSection("เงินฟรี")
daily:AddToggle("UpgDaily", {
    Title = "รับเช็คอินรายวันเอง",
    Description = "เงิน 30k-50k / กระเป๋า +1 / Diamond Gem x30 / Gold Pickaxe / Sushi Rod (รีเที่ยงคืนไทย)",
    Default = false,
}):OnChanged(function(v)
    opt.daily = v
end)
daily:AddButton({
    Title = "รับเช็คอินตอนนี้",
    Callback = function() task.spawn(dailyClaim) end,
})

local shop = Tabs.main:AddSection("อัปเกรด (วาร์ปไปซื้อแล้ววาร์ปกลับ)")
shop:AddToggle("UpgBag", {
    Title = "ซื้อกระเป๋าใหญ่ขึ้นเองเมื่อเงินพอ",
    Description = "ซื้อไล่ทีละระดับ 250 -> 3000 ช่อง กระเป๋าใหญ่ = ไปขายน้อยรอบ",
    Default = false,
}):OnChanged(function(v)
    opt.bag = v
end)
shop:AddToggle("UpgWeapon", {
    Title = "ซื้ออาวุธที่ดีกว่าเองเมื่อเงินพอ",
    Description = "Thermal Katana 150k -> Dark Surge 650k -> Ice Axe 1.2M -> Sniper 1.8M (ตีหมูหยิบอันดีสุดเอง)",
    Default = false,
}):OnChanged(function(v)
    opt.weapon = v
end)
shop:AddSlider("UpgReserve", {
    Title = "เก็บเงินไว้อย่างน้อย (บาท)",
    Description = "ซื้อเฉพาะตอนที่ซื้อแล้วยังเหลือเงินเท่านี้",
    Default = 0,
    Min = 0,
    Max = 500000,
    Rounding = 0,
}):OnChanged(function(v)
    opt.reserve = v
end)
shop:AddButton({
    Title = "ซื้อกระเป๋าระดับถัดไปตอนนี้",
    Callback = function() task.spawn(buyBag) end,
})
shop:AddButton({
    Title = "ซื้ออาวุธตัวถัดไปตอนนี้",
    Callback = function() task.spawn(buyWeapon) end,
})

local craft = Tabs.main:AddSection("พลั่วดีขึ้น = ขุดไวขึ้น + ขุดเพชรได้ (เพชร 400/เม็ด)")
craft:AddToggle("UpgKeep", {
    Title = "เก็บแท่งทอง/เพชรไว้คราฟพลั่ว",
    Description = "ล็อกขาย Gold Ingot (ยังไม่มีพลั่วทอง) หรือ Diamond Gem (ยังไม่มีพลั่วเพชร) ร้านจะไม่รับ ได้พลั่วแล้วปลดล็อกเอง",
    Default = false,
}):OnChanged(function(v)
    opt.keep = v
    task.spawn(syncLocks)
end)
craft:AddToggle("UpgPickaxe", {
    Title = "คราฟพลั่วเองเมื่อของครบ",
    Description = "Gold Pickaxe: 50k + ไม้ 30 + Gold Ingot 30  |  Diamond Pickaxe: 75k + ไม้ 30 + Diamond Gem 30",
    Default = false,
}):OnChanged(function(v)
    opt.pickaxe = v
end)
craft:AddButton({
    Title = "คราฟพลั่วตัวถัดไปตอนนี้",
    Callback = function() task.spawn(craftPickaxe) end,
})

local server = Tabs.main:AddSection("เซิฟ")
server:AddButton({
    Title = "ย้ายไปเซิฟที่คนน้อยสุด",
    Description = "คนน้อย = แย่งหิน/ต้นไม้/แอร์ดรอปน้อย  ย้ายแล้วเปิดสคริปต์ให้เอง (ต้องกดเปิดงานใหม่)",
    Callback = function() task.spawn(hopLowest) end,
})

local statusPara = Tabs.main:AddSection("สถานะ"):AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local tier, w = nextBag(), nextWeapon()
            statusPara:SetDesc(table.concat({
                "เงิน: " .. fmt(money()) .. " บาท",
                "กระเป๋า: " .. fmt(bagCapacity()) .. " ช่อง" .. (tier and (" • ถัดไป " .. fmt(tier.Capacity) .. " ช่อง " .. fmt(tier.Price) .. " บาท") or " • สูงสุดแล้ว"),
                "อาวุธถัดไป: " .. (w and (w.ToolName .. " " .. fmt(w.Price) .. " บาท") or "ครบแล้ว"),
                "พลั่วถัดไป: " .. (function()
                    local p = nextPickaxe()
                    if not p then return "มีพลั่วเพชรแล้ว" end
                    local miss = pickaxeNeeds(p)
                    return p.name .. (#miss > 0 and (" • ขาด " .. table.concat(miss, ", ")) or " • ของครบ คราฟได้")
                end)(),
                "เช็คอิน: " .. dailyInfo,
                "เซิฟ: " .. serverInfo,
                status,
            }, "\n"))
        end)
        task.wait(1)
    end
    if alive() then env.UpgradeRun += 1 end
end)
