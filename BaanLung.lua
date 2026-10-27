-- ตัวรวมแมพบ้านลุง: หน้าต่างเดียว แบ่งหมวด
--   งานหาเงิน: ลากซุง / ปลูกข้าว / ตีหมู / ขุดเหมือง / ตัดไม้
--   เก็บของ & ขาย: แอร์ดรอป / ขายของ
--   ทั่วไป: กล้อง / แต่งตัว / กันหลุด / อ่านระบบ (ไฟล์ Misc.lua ไฟล์เดียว แยกแท็บ)
-- แต่ละงานยังเป็นไฟล์ของมันเอง ตัวนี้แค่โหลดมาใส่แท็บ
local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local JOBS = {
    { file = "ElephantJob.lua", title = "ลากซุง", icon = "truck" },
    { file = "RiceJob.lua", title = "ปลูกข้าว", icon = "leaf" },
    { file = "PigFarm.lua", title = "ตีหมู", icon = "sword" },
    { file = "Mining.lua", title = "ขุดเหมือง", icon = "pickaxe" },
    { file = "Woodcut.lua", title = "ตัดไม้", icon = "axe" },
    { file = "Airdrop.lua", title = "แอร์ดรอป", icon = "package" },
    { file = "Seller.lua", title = "ขายของ", icon = "shopping-cart" },
    { file = "Misc.lua", tabs = {
        { key = "cam", title = "กล้อง", icon = "camera" },
        { key = "outfit", title = "แต่งตัว", icon = "shirt" },
        { key = "guard", title = "กันหลุด", icon = "shield" },
        { key = "tools", title = "อ่านระบบ", icon = "file-search" },
    } },
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
for _, key in ipairs({ "BaanLungFluent", "ElephantFluent", "RiceFluent", "PigFluent", "AirdropFluent", "MiningFluent", "WoodFluent", "SellerFluent", "MiscFluent" }) do
    if env[key] then
        pcall(function() env[key]:Destroy() end)
        env[key] = nil
    end
end
env.BaanLungFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "บ้านลุง",
    SubTitle = "งานหาเงิน • ขายของ • ทั่วไป",
    TabWidth = 150,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})

for _, job in ipairs(JOBS) do
    -- ไฟล์ที่มีหลายหมวด (tabs) ได้ตารางแท็บ { key = tab } ไป ที่เหลือได้แท็บเดียว
    local tab
    if job.tabs then
        tab = {}
        for _, t in ipairs(job.tabs) do
            tab[t.key] = Window:AddTab({ Title = t.title, Icon = t.icon })
        end
    else
        tab = Window:AddTab({ Title = job.title, Icon = job.icon })
    end
    local title = job.title or job.file
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
