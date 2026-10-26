-- ขายของ: ดูในกระเป๋าว่ามีอะไรขายได้ร้านไหนบ้าง แล้ววาร์ปไปขายทีละร้านจนหมด แล้ววาร์ปกลับที่เดิม
-- อ่านจากโค้ดเกม (PlayerGui.SellHubGui.SellHubClient + SellHubSystem.SellHubConfig):
--   ร้าน (SellHubConfig.Shops): ปลา (sellfishpart) / เนื้อหมู (sellmeatpart) / แร่ ลุงหมาน (sellorepart)
--     แต่ละร้านรับของตาม Order ของร้าน  ของในกระเป๋า = LocalPlayer.InventoryState IntValue ชื่อของ
--     ของที่กดล็อกขายไว้ (Attribute SaleLocked) ร้านไม่รับ
--   กดปุ่มร้าน -> SellHubSystem.Remotes.Open(ส่วนร้าน, { shopId }) ต้องอยู่ห่างไม่เกิน 15
--   ขาย: Request:InvokeServer("SellAll", nil, nil, GUID, shopId)  ปิด: Request:InvokeServer("Close", nil, nil, nil, shopId)
-- ระหว่างขาย งานอื่นในตัวรวมพักรอ (ใช้ env.AirdropBusy ตัวเดียวกับแอร์ดรอป)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.SellerRun = (env.SellerRun or 0) + 1
local RUN = env.SellerRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.SellerRun == RUN
end

local SellHub = ReplicatedStorage:WaitForChild("SellHubSystem")
local SellRemotes = SellHub:WaitForChild("Remotes")
local SellConfig = require(SellHub:WaitForChild("SellHubConfig"))
local SHOP_ORDER = { "Ore", "Meat", "Fish" }

local status = "-"
local auto = { whenFull = false, back = true, sold = 0, busy = false }

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

local opened = { shopId = nil, at = 0 }
local openConn = SellRemotes:WaitForChild("Open").OnClientEvent:Connect(function(_, state)
    if type(state) == "table" and state.shopId then opened.shopId, opened.at = state.shopId, os.clock() end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    openConn:Disconnect()
end)

---------------------------------------------------------------- กระเป๋า
-- ของที่ร้านนี้รับ และมีในกระเป๋า (ไม่นับที่ล็อกขาย): { [ชื่อ] = จำนวน }, รวม
local function sellableFor(shop)
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    local list, total = {}, 0
    if not inv then return list, 0 end
    for _, name in ipairs(shop.Order or {}) do
        local v = inv:FindFirstChild(name)
        if v and v:IsA("IntValue") and v.Value > 0 and not v:GetAttribute("SaleLocked") then
            list[name] = v.Value
            total += v.Value
        end
    end
    return list, total
end

local function bagFull()
    local inv = LocalPlayer:FindFirstChild("InventoryState")
    return inv ~= nil and (inv:GetAttribute("Total") or 0) >= (inv:GetAttribute("Capacity") or 100)
end

---------------------------------------------------------------- จุดร้าน
-- ปุ่มร้าน (อาจมีหลายจุด เช่นร้านปลา) เอาอันที่ใกล้สุด
local function shopPrompt(shop)
    local hrp = getRoot()
    local best, bestDist
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Name == shop.PromptName and d.Parent and d.Parent:IsA("BasePart") then
            local dist = hrp and (d.Parent.Position - hrp.Position).Magnitude or 0
            if not bestDist or dist < bestDist then best, bestDist = d, dist end
        end
    end
    return best
end

-- จุดยืนหน้าร้าน: ถ้ามี NPC ชื่อเดียวกับร้าน ยืนหน้า NPC ห่าง 5
-- ไม่มี: ลองรอบตัวกล่องขาย 8 ทิศ เอาจุดที่โล่ง (มองเห็นกล่องตรงๆ ไม่มีอะไรบัง) และมีพื้น
local function standPoint(shop, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local function ground(p)
        local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
        return hit and Vector3.new(p.X, hit.Position.Y + 3, p.Z)
    end
    local npc = workspace:FindFirstChild(shop.Title)
    local root = npc and npc:FindFirstChildOfClass("Humanoid") and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
    if root then
        local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        if look.Magnitude > 0.1 then
            local g = ground(root.Position + look.Unit * 5)
            if g then return g end
        end
    end
    for i = 0, 7 do
        local a = math.rad(i * 45)
        local dir = (part.CFrame * CFrame.Angles(0, a, 0)).LookVector
        dir = Vector3.new(dir.X, 0, dir.Z)
        if dir.Magnitude > 0.1 then
            local spot = part.Position + dir.Unit * 6
            local blocked = workspace:Raycast(part.Position, spot - part.Position, params)
            local g = not (blocked and blocked.Instance ~= part) and ground(spot)
            if g then return g end
        end
    end
    return part.Position + Vector3.new(0, 3, 0)
end

local function closeShopUi()
    pcall(function()
        local gui = LocalPlayer.PlayerGui:FindFirstChild("SellHubGui")
        if gui then gui.Enabled = false end
        if LocalPlayer:GetAttribute("UIBusyOwner") == "SellHub" then
            LocalPlayer:SetAttribute("UIBusy", false)
            LocalPlayer:SetAttribute("UIBusyOwner", nil)
        end
    end)
end

---------------------------------------------------------------- ขาย 1 ร้าน
local function sellAt(id, shop)
    local _, have = sellableFor(shop)
    if have <= 0 then return 0 end
    local prompt = shopPrompt(shop)
    if not prompt then
        status = "หา" .. shop.Title .. "ไม่เจอ"
        return 0
    end
    local part = prompt.Parent
    local hrp = getRoot()
    if not hrp then return 0 end
    status = "วาร์ปไป" .. shop.Title .. "..."
    local stand = standPoint(shop, part)
    hrp.CFrame = CFrame.lookAt(stand, Vector3.new(part.Position.X, stand.Y, part.Position.Z))
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.4)
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:UnequipTools() end
    local money = 0
    -- ขายจนของหมด (บางทีร้านขายให้ทีละส่วน) ไม่เกิน 3 รอบ
    for _ = 1, 3 do
        local _, left = sellableFor(shop)
        if left <= 0 then break end
        local askedAt = os.clock()
        if typeof(fireproximityprompt) == "function" then pcall(fireproximityprompt, prompt) end
        if not waitFor(4, function() return opened.at >= askedAt end) then
            status = "กดปุ่ม" .. shop.Title .. "แล้วร้านไม่เปิด"
            break
        end
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
        closeShopUi()
        if ok and type(res) == "table" and res.ok then
            money += tonumber(res.totalMoney) or 0
            status = ("ขายที่%s %s ชิ้น ได้ %s บาท"):format(shop.Title, tostring(res.soldCount), tostring(res.totalMoney))
        else
            status = "ขายที่" .. shop.Title .. "ไม่สำเร็จ: " .. tostring(ok and type(res) == "table" and (res.reason or res.message) or res)
            break
        end
        task.wait((SellConfig.SaleCooldown or 0.5) + 0.2)
    end
    return money
end

---------------------------------------------------------------- ขายทุกร้าน
local function sellEverything()
    if auto.busy then return end
    local any = false
    for _, id in ipairs(SHOP_ORDER) do
        local shop = SellConfig.Shops[id]
        if shop and select(2, sellableFor(shop)) > 0 then any = true end
    end
    if not any then
        status = "ไม่มีของที่ขายได้ในกระเป๋า"
        return
    end
    auto.busy = true
    env.AirdropBusy = true -- งานอื่นในตัวรวมพักรอ
    local hrp = getRoot()
    local home = hrp and hrp.CFrame
    local total = 0
    for _, id in ipairs(SHOP_ORDER) do
        local shop = SellConfig.Shops[id]
        if shop and alive() then
            total += sellAt(id, shop)
        end
    end
    auto.sold += total
    if auto.back and home then
        hrp = getRoot()
        if hrp then
            hrp.CFrame = home
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end
    status = ("ขายเสร็จ ได้ทั้งหมด %d บาท"):format(total)
    env.AirdropBusy = false
    auto.busy = false
end

-- ขายเองเมื่อกระเป๋าเต็ม (เช็คทุก 2 วิ)
task.spawn(function()
    while alive() do
        if auto.whenFull and not auto.busy and bagFull() then sellEverything() end
        task.wait(2)
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
        warn("[Seller] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.SellerFluent then
        pcall(function() env.SellerFluent:Destroy() end)
    end
    env.SellerFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ขายของ",
        SubTitle = "Sell",
        TabWidth = 150,
        Size = UDim2.fromOffset(540, 340),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("ขายของ")
section:AddButton({
    Title = "ขายของทั้งหมดตอนนี้",
    Description = "ดูกระเป๋า -> วาร์ปไปขายทุกร้านที่รับของที่มี (แร่ / เนื้อหมู / ปลา) จนหมด -> วาร์ปกลับที่เดิม",
    Callback = function()
        task.spawn(sellEverything)
    end,
})
section:AddToggle("SellWhenFull", {
    Title = "ขายเองเมื่อกระเป๋าเต็ม",
    Description = "กระเป๋าเต็มเมื่อไหร่ พักงานอื่น วาร์ปไปขายทุกร้าน แล้วกลับมาทำต่อ",
    Default = false,
}):OnChanged(function(v)
    auto.whenFull = v
end)
section:AddToggle("SellBack", {
    Title = "ขายเสร็จวาร์ปกลับที่เดิม",
    Default = true,
}):OnChanged(function(v)
    auto.back = v
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local lines = {}
            for _, id in ipairs(SHOP_ORDER) do
                local shop = SellConfig.Shops[id]
                if shop then
                    local list, n = sellableFor(shop)
                    if n > 0 then
                        local parts = {}
                        for name, c in pairs(list) do table.insert(parts, name .. " x" .. c) end
                        table.insert(lines, shop.Title .. ": " .. table.concat(parts, ", "))
                    end
                end
            end
            statusPara:SetDesc(("%s\n%s\nขายไปแล้ว %d บาท"):format(status,
                #lines > 0 and table.concat(lines, "\n") or "ไม่มีของที่ขายได้", auto.sold))
        end)
        task.wait(1)
    end
    if alive() then env.SellerRun += 1 end
end)
