-- ตัวรวมแมพบ้านลุง: หน้าต่างเดียว แท็บละงาน (ลากซุง / ปลูกข้าว / ตีหมู / แอร์ดรอป / ขุดเหมือง / ตัดไม้ / ขายของ / ทั่วไป)
-- แต่ละงานยังเป็นไฟล์ของมันเอง (ElephantJob.lua / RiceJob.lua) ตัวนี้แค่โหลดมาใส่แท็บ
local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local JOBS = {
    { file = "ElephantJob.lua", title = "ลากซุง", icon = "truck" },
    { file = "RiceJob.lua", title = "ปลูกข้าว", icon = "leaf" },
    { file = "PigFarm.lua", title = "ตีหมู", icon = "sword" },
    { file = "Airdrop.lua", title = "แอร์ดรอป", icon = "package" },
    { file = "Mining.lua", title = "ขุดเหมือง", icon = "pickaxe" },
    { file = "Woodcut.lua", title = "ตัดไม้", icon = "axe" },
    { file = "Seller.lua", title = "ขายของ", icon = "shopping-cart" },
    { file = "Misc.lua", title = "ทั่วไป", icon = "settings" },
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
    SubTitle = "ลากซุง • ปลูกข้าว • ตีหมู",
    TabWidth = 150,
    Size = UDim2.fromOffset(560, 400),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})

for _, job in ipairs(JOBS) do
    local tab = Window:AddTab({ Title = job.title, Icon = job.icon })
    -- แต่ละงานรอของในแมพ (WaitForChild) แยกกัน งานหนึ่งช้าไม่ถ่วงอีกงาน
    task.spawn(function()
        local loaded, err = pcall(function()
            local chunk = loadstring(game:HttpGet(BASE .. job.file))
            chunk(tab, Fluent)
        end)
        if not loaded then
            warn("[BaanLung] โหลด " .. job.file .. " ไม่ได้: " .. tostring(err))
            Fluent:Notify({ Title = "โหลดไม่ได้", Content = job.title .. ": " .. tostring(err), Duration = 8 })
        end
    end)
end

Window:SelectTab(1)
