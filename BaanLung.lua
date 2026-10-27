-- ตัวรวมแมพบ้านลุง: หน้าต่างเดียว แท็บเรียงตามหมวด
--   งานหาเงิน: ลากซุง / ปลูกข้าว / ตีหมู / เล็งมอน / ขุดเหมือง / ตัดไม้
--   ขาย & อัปเกรด: แอร์ดรอป / ขายของ / เงินฟรี / อัปเกรด / มินิเกม
--   ทั่วไป: กล้อง / ลดแลค / แต่งตัว / กันหลุด & เซิฟ / อ่านระบบ
-- แต่ละงานยังเป็นไฟล์ของมันเอง ตัวนี้สร้างแท็บตามลำดับก่อน แล้วโหลดไฟล์มาใส่
-- ไฟล์ที่มีหลายหมวดได้ตาราง { ชื่อหมวดในไฟล์ = แท็บ } ไป (หลายไฟล์ใช้แท็บเดียวกันได้)
-- แมพตกปลา (มี PlayerGui.FishingHud): เปิด AutoFish.lua แทน
-- แมพอื่น (ไม่ใช่บ้านลุง): โหลดเฉพาะแท็บที่ใช้ได้ทุกแมพ (any = true) งานของบ้านลุงจะรอของในแมพที่ไม่มีวันมา
local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local BAANLUNG_GAME = 10610397754 -- GameId ของบ้านลุง (ทุกเซิฟ/ทุกเพลซในเกมเดียวกัน)
local inBaanLung = game.GameId == BAANLUNG_GAME
local TABS = {
    { key = "elephant", title = "ลากซุง", icon = "truck" },
    { key = "rice", title = "ปลูกข้าว", icon = "leaf" },
    { key = "pig", title = "ตีหมู", icon = "sword" },
    { key = "aim", title = "เล็งมอน", icon = "crosshair" },
    { key = "mine", title = "ขุดเหมือง", icon = "pickaxe" },
    { key = "wood", title = "ตัดไม้", icon = "axe" },
    { key = "airdrop", title = "แอร์ดรอป", icon = "package" },
    { key = "sell", title = "ขายของ", icon = "shopping-cart" },
    { key = "daily", title = "เงินฟรี", icon = "gift" },
    { key = "upgrade", title = "อัปเกรด", icon = "trending-up" },
    { key = "minigame", title = "มินิเกม", icon = "gamepad-2" },
    { key = "cam", title = "กล้อง", icon = "camera", any = true },
    { key = "perf", title = "ลดแลค", icon = "gauge", any = true },
    { key = "outfit", title = "แต่งตัว", icon = "shirt", any = true },
    { key = "guard", title = "กันหลุด & เซิฟ", icon = "shield", any = true },
    { key = "tools", title = "อ่านระบบ", icon = "file-search", any = true },
}
local JOBS = {
    { file = "ElephantJob.lua", tab = "elephant" },
    { file = "RiceJob.lua", tab = "rice" },
    { file = "PigFarm.lua", tabs = { main = "pig", aim = "aim" } },
    { file = "Mining.lua", tab = "mine" },
    { file = "Woodcut.lua", tab = "wood" },
    { file = "Airdrop.lua", tab = "airdrop" },
    { file = "Seller.lua", tab = "sell" },
    { file = "Upgrade.lua", tabs = { daily = "daily", upgrade = "upgrade", server = "guard" } },
    { file = "Minigames.lua", tab = "minigame" },
    { file = "Misc.lua", any = true, tabs = { cam = "cam", perf = "perf", outfit = "outfit", guard = "guard", tools = "tools" } },
}

local env = (typeof(getgenv) == "function" and getgenv()) or _G

-- โหลดไฟล์ในโปรเจกต์: ถ้ารีโปเป็นส่วนตัว ตัวเปิด (bootstrap ที่เก็บไว้ในเครื่อง) จะใส่ env.BaanLungGet
-- ที่ดึงผ่าน GitHub API ด้วย token มาให้ ไม่มี = ดึงจาก raw แบบรีโปสาธารณะ
env.BaanLungGet = env.BaanLungGet or function(file)
    return game:HttpGet(BASE .. file)
end
-- โค้ดที่ใช้เปิดตัวรวมใหม่หลังย้ายเซิฟ/หลุด (bootstrap ใส่ของตัวเองไว้ให้)
env.BaanLungBoot = env.BaanLungBoot or ('loadstring(game:HttpGet("' .. BASE .. 'BaanLung.lua"))()')

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
-- แมพตกปลา (มีหน้าจอ FishingHud): เปิดตัวตกปลา AutoFish.lua ของแมพนั้นแทน (หน้าต่างของมันเอง)
if not inBaanLung then
    local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    if gui:FindFirstChild("FishingHud") or gui:WaitForChild("FishingHud", 3) then
        if env.BaanLungFluent then
            pcall(function() env.BaanLungFluent:Destroy() end)
            env.BaanLungFluent = nil
        end
        loadstring(env.BaanLungGet("AutoFish.lua"))()
        return
    end
end

local ok, Fluent = pcall(loadFluent, true)
if not ok or typeof(Fluent) ~= "table" then
    ok, Fluent = pcall(loadFluent, false)
end
if not ok or typeof(Fluent) ~= "table" then
    warn("[BaanLung] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

-- ปิดหน้าต่างเก่าทั้งหมด (ตัวรวมรอบก่อน / ตัวเดี่ยวที่เปิดค้าง)
for _, key in ipairs({ "BaanLungFluent", "ElephantFluent", "RiceFluent", "PigFluent", "AirdropFluent", "MiningFluent", "WoodFluent", "SellerFluent", "UpgradeFluent", "MinigameFluent", "MiscFluent" }) do
    if env[key] then
        pcall(function() env[key]:Destroy() end)
        env[key] = nil
    end
end
env.BaanLungFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "บ้านลุง",
    SubTitle = inBaanLung and "งานหาเงิน • ขาย & อัปเกรด • ทั่วไป" or "ทั่วไป (แมพนี้ไม่ใช่บ้านลุง)",
    TabWidth = 150,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})

---------------------------------------------------------------- หน้าโหลด
-- ซ่อนหน้าต่างไว้จนทุกแท็บโหลดเสร็จ (กดเร็วไปจะเจอแท็บโล่ง) โชว์แถบโหลดแทน
local function setWindowVisible(on)
    pcall(function() Fluent.GUI.Enabled = on end)
end
setWindowVisible(false)

local loader = Instance.new("ScreenGui")
loader.Name = "BaanLungLoading"
loader.IgnoreGuiInset = true
loader.ResetOnSpawn = false
loader.DisplayOrder = 1000
pcall(function() loader.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)
if not loader.Parent then loader.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end
local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.fromScale(0.5, 0.5)
box.Size = UDim2.fromOffset(340, 120)
box.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
box.BorderSizePixel = 0
box.Parent = loader
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
local boxStroke = Instance.new("UIStroke", box)
boxStroke.Color = Color3.fromRGB(70, 76, 92)
local function label(text, y, size, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.fromOffset(16, y)
    l.Size = UDim2.new(1, -32, 0, size + 6)
    l.Font = Enum.Font.GothamBold
    l.TextSize = size
    l.TextColor3 = color
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = box
    return l
end
label("บ้านลุง", 12, 22, Color3.fromRGB(240, 242, 248))
local loadText = label("กำลังโหลด...", 44, 14, Color3.fromRGB(170, 178, 196))
local bar = Instance.new("Frame")
bar.Position = UDim2.fromOffset(16, 84)
bar.Size = UDim2.new(1, -32, 0, 10)
bar.BackgroundColor3 = Color3.fromRGB(44, 48, 60)
bar.BorderSizePixel = 0
bar.Parent = box
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
fill.BorderSizePixel = 0
fill.Parent = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

local tabs, titles = {}, {}
for _, t in ipairs(TABS) do
    if inBaanLung or t.any then
        tabs[t.key] = Window:AddTab({ Title = t.title, Icon = t.icon })
        titles[t.key] = t.title
    end
end

local total, done, failed, pending = 0, 0, {}, {}
for _, job in ipairs(JOBS) do
    if inBaanLung or job.any then total += 1 end
end

for _, job in ipairs(JOBS) do
    if not (inBaanLung or job.any) then continue end
    local tab, title
    if job.tabs then
        tab = {}
        for name, key in pairs(job.tabs) do tab[name] = tabs[key] end
        title = job.file
    else
        tab, title = tabs[job.tab], titles[job.tab]
    end
    -- แต่ละงานรอของในแมพ (WaitForChild) แยกกัน งานหนึ่งช้าไม่ถ่วงอีกงาน
    pending[job.file] = title
    task.spawn(function()
        local loaded, err = pcall(function()
            local chunk = loadstring(env.BaanLungGet(job.file))
            chunk(tab, Fluent)
        end)
        if not loaded then
            warn("[BaanLung] โหลด " .. job.file .. " ไม่ได้: " .. tostring(err))
            failed[#failed + 1] = title .. ": " .. tostring(err)
        end
        pending[job.file] = nil
        done += 1
    end)
end

Window:SelectTab(1)

-- รอทุกไฟล์ (ไม่เกิน 40 วิ: บางงานรอของในแมพนานผิดปกติ ก็เปิดหน้าต่างให้ใช้ส่วนที่พร้อมก่อน)
local startedAt = os.clock()
while done < total and os.clock() - startedAt < 40 do
    local waiting = {}
    for _, name in pairs(pending) do waiting[#waiting + 1] = name end
    loadText.Text = ("กำลังโหลด %d/%d • %s"):format(done, total, table.concat(waiting, ", "))
    fill.Size = UDim2.fromScale(done / math.max(1, total), 1)
    task.wait(0.1)
end
fill.Size = UDim2.fromScale(1, 1)
loadText.Text = done < total and "บางแท็บยังโหลดไม่เสร็จ เปิดส่วนที่พร้อมก่อน" or "พร้อมแล้ว"
task.wait(0.4)
loader:Destroy()
setWindowVisible(true)
for _, msg in ipairs(failed) do
    Fluent:Notify({ Title = "โหลดไม่ได้", Content = msg, Duration = 8 })
end
if done < total then
    local waiting = {}
    for _, name in pairs(pending) do waiting[#waiting + 1] = name end
    Fluent:Notify({ Title = "ยังโหลดไม่เสร็จ", Content = table.concat(waiting, ", "), Duration = 8 })
end
