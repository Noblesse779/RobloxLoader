-- ตัวรวมแมพบ้านลุง: หน้าต่างเดียว แท็บเรียงตามหมวด
--   งานหาเงิน: ลากซุง / ปลูกข้าว / ตีหมู / ขุดเหมือง / ตัดไม้
--   ขาย & อัปเกรด: แอร์ดรอป / ขายของ / เงินฟรี / อัปเกรด
--   ทั่วไป: กล้อง / ลดแลค / แต่งตัว / กันหลุด & เซิฟ / อ่านระบบ
-- แต่ละงานยังเป็นไฟล์ของมันเอง ตัวนี้สร้างแท็บตามลำดับก่อน แล้วโหลดไฟล์มาใส่
-- ไฟล์ที่มีหลายหมวดได้ตาราง { ชื่อหมวดในไฟล์ = แท็บ } ไป (หลายไฟล์ใช้แท็บเดียวกันได้)
local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local TABS = {
    { key = "elephant", title = "ลากซุง", icon = "truck" },
    { key = "rice", title = "ปลูกข้าว", icon = "leaf" },
    { key = "pig", title = "ตีหมู", icon = "sword" },
    { key = "mine", title = "ขุดเหมือง", icon = "pickaxe" },
    { key = "wood", title = "ตัดไม้", icon = "axe" },
    { key = "airdrop", title = "แอร์ดรอป", icon = "package" },
    { key = "sell", title = "ขายของ", icon = "shopping-cart" },
    { key = "daily", title = "เงินฟรี", icon = "gift" },
    { key = "upgrade", title = "อัปเกรด", icon = "trending-up" },
    { key = "cam", title = "กล้อง", icon = "camera" },
    { key = "perf", title = "ลดแลค", icon = "gauge" },
    { key = "outfit", title = "แต่งตัว", icon = "shirt" },
    { key = "guard", title = "กันหลุด & เซิฟ", icon = "shield" },
    { key = "tools", title = "อ่านระบบ", icon = "file-search" },
}
local JOBS = {
    { file = "ElephantJob.lua", tab = "elephant" },
    { file = "RiceJob.lua", tab = "rice" },
    { file = "PigFarm.lua", tab = "pig" },
    { file = "Mining.lua", tab = "mine" },
    { file = "Woodcut.lua", tab = "wood" },
    { file = "Airdrop.lua", tab = "airdrop" },
    { file = "Seller.lua", tab = "sell" },
    { file = "Upgrade.lua", tabs = { daily = "daily", upgrade = "upgrade", server = "guard" } },
    { file = "Misc.lua", tabs = { cam = "cam", perf = "perf", outfit = "outfit", guard = "guard", tools = "tools" } },
}

local env = (typeof(getgenv) == "function" and getgenv()) or _G

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
    warn("[BaanLung] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

-- ปิดหน้าต่างเก่าทั้งหมด (ตัวรวมรอบก่อน / ตัวเดี่ยวที่เปิดค้าง)
for _, key in ipairs({ "BaanLungFluent", "ElephantFluent", "RiceFluent", "PigFluent", "AirdropFluent", "MiningFluent", "WoodFluent", "SellerFluent", "UpgradeFluent", "MiscFluent" }) do
    if env[key] then
        pcall(function() env[key]:Destroy() end)
        env[key] = nil
    end
end
env.BaanLungFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "บ้านลุง",
    SubTitle = "งานหาเงิน • ขาย & อัปเกรด • ทั่วไป",
    TabWidth = 150,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})

local tabs, titles = {}, {}
for _, t in ipairs(TABS) do
    tabs[t.key] = Window:AddTab({ Title = t.title, Icon = t.icon })
    titles[t.key] = t.title
end

for _, job in ipairs(JOBS) do
    local tab, title
    if job.tabs then
        tab = {}
        for name, key in pairs(job.tabs) do tab[name] = tabs[key] end
        title = job.file
    else
        tab, title = tabs[job.tab], titles[job.tab]
    end
    -- แต่ละงานรอของในแมพ (WaitForChild) แยกกัน งานหนึ่งช้าไม่ถ่วงอีกงาน
    task.spawn(function()
        local loaded, err = pcall(function()
            local chunk = loadstring(game:HttpGet(BASE .. job.file))
            chunk(tab, Fluent)
        end)
        if not loaded then
            warn("[BaanLung] โหลด " .. job.file .. " ไม่ได้: " .. tostring(err))
            Fluent:Notify({ Title = "โหลดไม่ได้", Content = title .. ": " .. tostring(err), Duration = 8 })
        end
    end)
end

Window:SelectTab(1)
