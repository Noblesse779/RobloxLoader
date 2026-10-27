-- ทั่วไป: ฟรีแคม (ตั้งปุ่มเปิด/ปิดได้) ใช้ได้ทุกแมพ + สุ่มชุด (เฉพาะแมพที่มีร้านลองชุด OurCatalog)
-- ฟรีแคม: กล้องลอยอิสระ ตัวละครอยู่ที่เดิม งานอื่นทำต่อได้ปกติ
-- สุ่มชุด: ใช้ปุ่ม "ลอง" ของร้านในเกมเอง (AvatarAction "Try") ไม่ได้ซื้อของ
-- กันหลุด: กันโดนเตะตอนยืนนิ่ง 20 นาที + หลุดแล้วเข้าเซิฟใหม่เอง
-- ลดแลค: ปิดเงา/เอฟเฟกต์/พื้นผิว/อนุภาค ลดคุณภาพภาพ จำกัด FPS ปิดภาพ 3D ได้ (ทุกอย่างคืนค่าเดิมได้ตอนปิด)
-- อ่านระบบเซิฟ: รัน Dump.lua เซฟรีโมท/ค่าผู้เล่น/โค้ดฝั่งเรา ลงโฟลเดอร์ GameDump

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.MiscRun = (env.MiscRun or 0) + 1
local RUN = env.MiscRun -- รันใหม่ = ตัวเก่าหยุดเอง
local function alive()
    return env.MiscRun == RUN
end

---------------------------------------------------------------- ฟรีแคม
-- ปุ่มข้างเมาส์ (Mouse4/Mouse5) Roblox ไม่ส่งมาให้สคริปต์ เลยใช้ปุ่มคีย์บอร์ดหรือปุ่มกลางเมาส์แทน
local FREECAM_KEYS = { "P", "V", "C", "X", "Z", "G", "B", "N", "M", "ปุ่มกลางเมาส์" }
local MOVE = {
    W = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1),
    A = Vector3.new(-1, 0, 0), D = Vector3.new(1, 0, 0),
    E = Vector3.new(0, 1, 0), Q = Vector3.new(0, -1, 0),
}
local cam = { on = false, held = {}, pitch = 0, yaw = 0, pos = Vector3.zero, key = "P", speed = 1 }
local onToggleUi = function() end -- ให้สวิตช์ในหน้าต่างตรงกับสถานะ (กำหนดตอนสร้างหน้าต่าง)

-- กินปุ่ม WASDQE ระหว่างฟรีแคม ตัวละครจะไม่เดินตาม
local function sinkMove(_, state, input)
    local name = input.KeyCode.Name
    if MOVE[name] then
        cam.held[name] = state == Enum.UserInputState.Begin
    end
    return Enum.ContextActionResult.Sink
end

local function setFreecam(on)
    if cam.on == on then return end
    cam.on = on
    local camera = workspace.CurrentCamera
    if on then
        local cf = camera.CFrame
        cam.pos = cf.Position
        cam.pitch, cam.yaw = cf:ToEulerAnglesYXZ()
        camera.CameraType = Enum.CameraType.Scriptable
        ContextActionService:BindActionAtPriority("MiscFreecam", sinkMove, false,
            Enum.ContextActionPriority.High.Value + 100,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E)
    else
        ContextActionService:UnbindAction("MiscFreecam")
        table.clear(cam.held)
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        camera.CameraType = Enum.CameraType.Custom
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then camera.CameraSubject = hum end
    end
    onToggleUi(on)
end

local conns = {}
conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
    if not cam.on then return end
    -- คลิกขวาค้าง = หมุนกล้อง
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        local delta = UserInputService:GetMouseDelta()
        cam.yaw -= delta.X * 0.004
        cam.pitch = math.clamp(cam.pitch - delta.Y * 0.004, -1.45, 1.45)
    else
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
    local move = Vector3.zero
    for name, down in pairs(cam.held) do
        if down then move += MOVE[name] end
    end
    local rot = CFrame.fromEulerAnglesYXZ(cam.pitch, cam.yaw, 0)
    local fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
    cam.pos += rot:VectorToWorldSpace(move) * (40 * cam.speed * fast * dt)
    workspace.CurrentCamera.CFrame = CFrame.new(cam.pos) * rot
end)

-- ปุ่มลัดเปิด/ปิด
conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local hit
    if cam.key == "ปุ่มกลางเมาส์" then
        hit = input.UserInputType == Enum.UserInputType.MouseButton3
    else
        hit = input.KeyCode.Name == cam.key
    end
    if hit then setFreecam(not cam.on) end
end)

-- รันใหม่/ปิดหน้าต่าง = คืนกล้องปกติ
task.spawn(function()
    while alive() do task.wait(1) end
    setFreecam(false)
    for _, c in ipairs(conns) do c:Disconnect() end
end)

---------------------------------------------------------------- สุ่มชุด
-- ช่องที่สุ่ม: ชื่อ, ประเภทของ (ตามหมวดในร้าน), Asset/Bundle
local SLOTS = {
    { name = "ผม", assets = { "HairAccessory" } },
    { name = "หมวก", assets = { "Hat" } },
    { name = "หน้า", assets = { "FaceAccessory" } },
    { name = "คอ", assets = { "NeckAccessory" } },
    { name = "หลัง", assets = { "BackAccessory" } },
    { name = "ไหล่", assets = { "ShoulderAccessory" } },
    { name = "เอว", assets = { "WaistAccessory" } },
    { name = "เสื้อ", assets = { "Shirt" } },
    { name = "กางเกง", assets = { "Pants" } },
    { name = "รองเท้า", bundles = { "Shoes" } },
}
local SORTS = {
    Enum.CatalogSortType.Relevance, Enum.CatalogSortType.Bestselling,
    Enum.CatalogSortType.MostFavorited, Enum.CatalogSortType.RecentlyCreated,
}
local outfit = { clear = true, skin = true, auto = false, every = 30, busy = false }
local pools = {} -- ของที่ค้นมาแล้วต่อช่อง ใช้หมดค่อยค้นใหม่

local function avatarAction()
    local cat = ReplicatedStorage:FindFirstChild("OurCatalog")
    return cat and cat:FindFirstChild("AvatarAction")
end

local function enumList(enum, names)
    local out = {}
    for _, n in ipairs(names or {}) do
        local ok, v = pcall(function() return enum[n] end)
        if ok and v then out[#out + 1] = v end
    end
    return out
end

-- ค้นแคตตาล็อกแบบเดียวกับร้าน (เรียง/หน้าแบบสุ่ม) แล้วเก็บไอดีไว้ในกอง
local function refill(slot)
    local params = CatalogSearchParams.new()
    params.SearchKeyword = ""
    params.Limit = 30
    params.IncludeOffSale = false
    params.AssetTypes = enumList(Enum.AvatarAssetType, slot.assets)
    params.BundleTypes = enumList(Enum.BundleType, slot.bundles)
    params.CategoryFilter = Enum.CatalogCategoryFilter.None
    params.SortType = SORTS[math.random(#SORTS)]
    local ok, pages = pcall(function() return AvatarEditorService:SearchCatalogAsync(params) end)
    if not ok or not pages then return end
    for _ = 1, math.random(0, 2) do -- ข้ามไปหน้าถัดๆ ไปบ้างให้ไม่ซ้ำ
        if pages.IsFinished or not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
    end
    local list = {}
    for _, item in ipairs(pages:GetCurrentPage()) do
        local id = tonumber(item.Id or item.AssetId)
        if id then
            list[#list + 1] = { id = id, kind = item.ItemType == "Bundle" and "Bundle" or "Asset" }
        end
    end
    pools[slot.name] = list
end

local function pick(slot)
    local list = pools[slot.name]
    if not list or #list == 0 then
        refill(slot)
        list = pools[slot.name]
    end
    if not list or #list == 0 then return end
    return table.remove(list, math.random(#list))
end

local function randomOutfit()
    if outfit.busy then return false, "กำลังสุ่มอยู่" end
    local remote = avatarAction()
    if not remote then return false, "แมพนี้ไม่มีร้านลองชุด" end
    outfit.busy = true
    local worn = 0
    local function call(...)
        local args = table.pack(...)
        local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
        task.wait(0.3) -- เว้นจังหวะเหมือนกดเอง
        return ok and res
    end
    -- ต้องเปิดเมนูแต่งตัวก่อนเหมือนกดปุ่มเสื้อ (เก็บเครื่องมือ/ลุกจากที่นั่งก่อน) แต่งเสร็จค่อยปิด
    local prepare = remote.Parent:FindFirstChild("PrepareAvatarMenu")
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:UnequipTools()
        if hum.Sit or hum.SeatPart then
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
    if prepare then
        local ok, res = pcall(function() return prepare:InvokeServer(true) end)
        if not (ok and res) then
            outfit.busy = false
            return false, "เปิดเมนูแต่งตัวไม่ได้ (ลุกจากที่นั่ง/เก็บของในมือแล้วลองใหม่)"
        end
    end
    if outfit.clear then call("Clear") end
    if outfit.skin then
        call("Skin", Color3.fromHSV(math.random(), math.random(10, 60) / 100, math.random(35, 100) / 100))
    end
    for _, slot in ipairs(SLOTS) do
        if not alive() then break end
        local item = pick(slot)
        if item and call("Try", item.id, item.kind) then worn += 1 end
    end
    if prepare then pcall(function() prepare:InvokeServer(false) end) end
    outfit.busy = false
    return true, "ใส่ได้ " .. worn .. "/" .. #SLOTS .. " ชิ้น"
end

task.spawn(function()
    local last = 0
    while alive() do
        task.wait(1)
        if outfit.auto and not outfit.busy and os.clock() - last >= outfit.every then
            last = os.clock()
            randomOutfit()
        end
    end
end)

---------------------------------------------------------------- กันหลุด
local BASE = "https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/"
local guard = { afk = true, rejoin = false, reload = true, rejoining = false }

-- เกมเตะคนที่ไม่ขยับ 20 นาที: พอ Roblox ส่งสัญญาณว่านิ่งนาน ให้กดเมาส์ปลอมหนึ่งที
conns[#conns + 1] = LocalPlayer.Idled:Connect(function()
    if not guard.afk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local function queueReload()
    local queue = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or (typeof(syn) == "table" and syn.queue_on_teleport)
    if guard.reload and queue then
        pcall(queue, 'loadstring(game:HttpGet("' .. BASE .. 'BaanLung.lua"))()')
    end
end

-- หลุด/โดนเตะ (ขึ้นกล่องแจ้ง error) = เข้าเซิฟเดิมก่อน ไม่ได้ค่อยหาเซิฟใหม่
conns[#conns + 1] = GuiService.ErrorMessageChanged:Connect(function(msg)
    if not guard.rejoin or guard.rejoining or msg == "" then return end
    guard.rejoining = true
    task.spawn(function()
        queueReload()
        task.wait(2)
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
        for _ = 1, 30 do
            task.wait(10)
            queueReload()
            pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        end
        guard.rejoining = false
    end)
end)

---------------------------------------------------------------- ลดแลค
local Lighting = game:GetService("Lighting")
local perf = { low = false, hide = false, cap = 0, no3d = false }
local saved = setmetatable({}, { __mode = "k" }) -- ค่าเดิม { [ของ] = { prop = ค่า } } ไว้คืนตอนปิด
local savedLighting, savedQuality

local function remember(inst, props)
    local t = saved[inst]
    if not t then t = {}; saved[inst] = t end
    for prop, value in pairs(props) do
        if t[prop] == nil then
            local ok, old = pcall(function() return inst[prop] end)
            if ok then t[prop] = old end
        end
        pcall(function() inst[prop] = value end)
    end
end

-- ลดภาระของแต่ละชิ้น: พื้นผิวเรียบ ไม่มีเงา ปิดรูปแปะ/อนุภาค
local function lighten(inst)
    -- ไม่เปลี่ยน Material เพราะมีผลกับแรงเสียดทาน/น้ำหนัก (ตัวละคร ช้าง รถ) คุณภาพภาพระดับ 1 ลดพื้นผิวให้อยู่แล้ว
    if inst:IsA("BasePart") then
        remember(inst, { CastShadow = false, Reflectance = 0 })
    elseif inst:IsA("Decal") or inst:IsA("Texture") then
        remember(inst, { Transparency = 1 })
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Smoke")
        or inst:IsA("Fire") or inst:IsA("Sparkles") then
        remember(inst, { Enabled = false })
    elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
        remember(inst, { Shadows = false })
    end
end

local function restoreAll()
    for inst, props in pairs(saved) do
        for prop, value in pairs(props) do
            pcall(function() inst[prop] = value end)
        end
    end
    table.clear(saved)
end

local function setLow(on)
    if on then
        savedLighting = savedLighting or {
            GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd,
            Brightness = Lighting.Brightness, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        }
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e9
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        for _, e in ipairs(Lighting:GetDescendants()) do
            if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Clouds") then
                if e:IsA("Atmosphere") then
                    remember(e, { Density = 0, Haze = 0, Glare = 0 })
                else
                    remember(e, { Enabled = false })
                end
            end
        end
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            remember(terrain, { WaterWaveSize = 0, WaterWaveSpeed = 0, WaterReflectance = 0, WaterTransparency = 0.9, Decoration = false })
        end
        pcall(function()
            savedQuality = savedQuality or settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        -- ของในแมพเยอะ ทำทีละชุดไม่ให้ค้าง
        task.spawn(function()
            for i, inst in ipairs(workspace:GetDescendants()) do
                if not perf.low or not alive() then return end
                lighten(inst)
                if i % 400 == 0 then task.wait() end
            end
        end)
    else
        if savedLighting then
            for k, v in pairs(savedLighting) do pcall(function() Lighting[k] = v end) end
            savedLighting = nil
        end
        if savedQuality then
            pcall(function() settings().Rendering.QualityLevel = savedQuality end)
            savedQuality = nil
        end
        restoreAll()
    end
end

conns[#conns + 1] = workspace.DescendantAdded:Connect(function(inst)
    if perf.low then lighten(inst) end
end)

-- ซ่อนผู้เล่นอื่น (เฉพาะจอเรา) ไม่ต้องวาดตัวละคร/ชุด/เอฟเฟกต์ของคนอื่น
local function hideCharacter(char, on)
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            d.LocalTransparencyModifier = on and 1 or 0
        end
    end
end
-- เช็คทุก 1 วิ พอ (ทุกเฟรมจะกินเครื่องเอง) จับคนเกิดใหม่/ใส่ของใหม่ด้วย
task.spawn(function()
    while alive() do
        if perf.hide then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then hideCharacter(plr.Character, true) end
            end
        end
        task.wait(1)
    end
end)
local function setHide(on)
    perf.hide = on
    if not on then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then hideCharacter(plr.Character, false) end
        end
    end
end

local function setCap(n)
    perf.cap = n
    if typeof(setfpscap) == "function" then pcall(setfpscap, n > 0 and n or 0) end
end

local function set3d(off)
    perf.no3d = off
    pcall(function() RunService:Set3dRenderingEnabled(not off) end)
end

-- รันใหม่/ปิด = คืนทุกอย่าง
task.spawn(function()
    while alive() do task.wait(1) end
    if perf.low then perf.low = false; setLow(false) end
    setHide(false)
    if perf.cap > 0 then setCap(0) end
    if perf.no3d then set3d(false) end
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
-- ตัวรวมส่งมาได้ 2 แบบ: แท็บเดียว (ใส่ทุกหมวดในแท็บนั้น) หรือตาราง { cam, outfit, guard, tools } แยกแท็บละหมวด
local TAB_KEYS = {
    { key = "cam", title = "กล้อง", icon = "camera" },
    { key = "perf", title = "ลดแลค", icon = "gauge" },
    { key = "outfit", title = "แต่งตัว", icon = "shirt" },
    { key = "guard", title = "กันหลุด", icon = "shield" },
    { key = "tools", title = "อ่านระบบ", icon = "file-search" },
}
local HUB_TAB, HUB_FLUENT = ...
local Fluent, Window, Tabs
if HUB_TAB then
    Fluent = HUB_FLUENT
    if typeof(HUB_TAB) == "table" and HUB_TAB.cam then
        Tabs = HUB_TAB
    else
        Tabs = {}
        for _, t in ipairs(TAB_KEYS) do Tabs[t.key] = HUB_TAB end
    end
else
    local ok
    ok, Fluent = pcall(loadFluent, true)
    if not ok or typeof(Fluent) ~= "table" then
        ok, Fluent = pcall(loadFluent, false)
    end
    if not ok or typeof(Fluent) ~= "table" then
        warn("[Misc] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.MiscFluent then
        pcall(function() env.MiscFluent:Destroy() end)
    end
    env.MiscFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ทั่วไป",
        SubTitle = "Misc",
        TabWidth = 150,
        Size = UDim2.fromOffset(560, 360),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {}
    for _, t in ipairs(TAB_KEYS) do
        Tabs[t.key] = Window:AddTab({ Title = t.title, Icon = t.icon })
    end
end

local section = Tabs.cam:AddSection("ฟรีแคม")
local freecamToggle = section:AddToggle("MiscFreecam", {
    Title = "ฟรีแคม",
    Description = "WASD เลื่อนกล้อง • Q/E ลง/ขึ้น • คลิกขวาค้างหมุนกล้อง • Shift เร็วขึ้น (ตัวละครอยู่ที่เดิม งานอื่นทำต่อได้)",
    Default = false,
})
freecamToggle:OnChanged(function(v)
    setFreecam(v)
end)
onToggleUi = function(on)
    if freecamToggle.Value ~= on then
        pcall(function() freecamToggle:SetValue(on) end)
    end
end
section:AddDropdown("MiscFreecamKey", {
    Title = "ปุ่มเปิด/ปิดฟรีแคม",
    Values = FREECAM_KEYS,
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    cam.key = v
end)
section:AddSlider("MiscFreecamSpeed", {
    Title = "ความเร็วกล้อง",
    Default = 1,
    Min = 0.2,
    Max = 5,
    Rounding = 1,
}):OnChanged(function(v)
    cam.speed = v
end)

local perfSection = (Tabs.perf or Tabs.cam):AddSection("บูท FPS / ลดแลค (เห็นแค่จอเรา ปิดแล้วกลับเหมือนเดิม)")
perfSection:AddToggle("MiscLowGfx", {
    Title = "กราฟิกต่ำสุด",
    Description = "ปิดเงา หมอก เอฟเฟกต์แสง น้ำกระเพื่อม หญ้า พื้นผิว รูปแปะ อนุภาค ควัน ไฟ + คุณภาพภาพระดับ 1",
    Default = false,
}):OnChanged(function(v)
    if perf.low == v then return end
    perf.low = v
    setLow(v)
end)
perfSection:AddToggle("MiscHidePlayers", {
    Title = "ซ่อนผู้เล่นอื่น",
    Description = "ไม่วาดตัวละคร ชุด และเอฟเฟกต์ของคนอื่น (คนเยอะเซิฟจะลื่นขึ้นมาก)",
    Default = false,
}):OnChanged(setHide)
perfSection:AddDropdown("MiscFpsCap", {
    Title = "จำกัด FPS",
    Description = "ยิ่งต่ำยิ่งกินเครื่องน้อย เครื่องไม่ร้อน (ต้องใช้ตัวรันที่มี setfpscap)",
    Values = { "ไม่จำกัด", "60", "30", "15" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    setCap(tonumber(v) or 0)
end)
perfSection:AddToggle("MiscNo3D", {
    Title = "ปิดภาพ 3D (จอดำ) สำหรับฟาร์ม AFK",
    Description = "ไม่วาดแมพเลย กินเครื่องน้อยที่สุด สคริปต์ฟาร์มยังทำงานปกติ เมนูยังกดได้",
    Default = false,
}):OnChanged(set3d)

local outfitSection = Tabs.outfit:AddSection("สุ่มชุด")
outfitSection:AddButton({
    Title = "สุ่มชุดเลย",
    Description = "ลองชุดสุ่มจากร้านในเกม (ผม หมวก เครื่องประดับ เสื้อ กางเกง รองเท้า สีผิว) คนอื่นเห็นด้วย",
    Callback = function()
        task.spawn(function()
            local ok, msg = randomOutfit()
            Fluent:Notify({ Title = "สุ่มชุด", Content = msg, Duration = 4 })
        end)
    end,
})
outfitSection:AddToggle("MiscOutfitClear", {
    Title = "ถอดของเดิมก่อนสุ่ม",
    Default = true,
}):OnChanged(function(v)
    outfit.clear = v
end)
outfitSection:AddToggle("MiscOutfitSkin", {
    Title = "สุ่มสีผิวด้วย",
    Default = true,
}):OnChanged(function(v)
    outfit.skin = v
end)
outfitSection:AddToggle("MiscOutfitAuto", {
    Title = "สุ่มเองเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    outfit.auto = v
end)
outfitSection:AddSlider("MiscOutfitEvery", {
    Title = "สุ่มทุกกี่วินาที",
    Default = 30,
    Min = 10,
    Max = 300,
    Rounding = 0,
}):OnChanged(function(v)
    outfit.every = v
end)

local guardSection = Tabs.guard:AddSection("กันหลุด")
guardSection:AddToggle("MiscAntiAfk", {
    Title = "กันโดนเตะตอนยืนนิ่ง (AFK)",
    Description = "ยืนนิ่งเกิน 20 นาทีเกมจะเตะ เปิดไว้จะไม่โดน",
    Default = true,
}):OnChanged(function(v)
    guard.afk = v
end)
guardSection:AddToggle("MiscRejoin", {
    Title = "หลุดแล้วเข้าเซิฟใหม่เอง",
    Description = "ขึ้นกล่องหลุด/โดนเตะ = เข้าเซิฟเดิม ถ้าเต็มหรือปิดไปแล้วจะหาเซิฟใหม่",
    Default = false,
}):OnChanged(function(v)
    guard.rejoin = v
end)
guardSection:AddToggle("MiscRejoinReload", {
    Title = "เข้าใหม่แล้วเปิดสคริปต์ให้เอง",
    Description = "ต้องกดเปิดงานเองอีกรอบ (ทุกอย่างเริ่มปิด)",
    Default = true,
}):OnChanged(function(v)
    guard.reload = v
end)

local dumpSection = Tabs.tools:AddSection("อ่านระบบเซิฟ")
local dumping = false
dumpSection:AddButton({
    Title = "อ่านระบบเซิฟนี้",
    Description = "เซฟรีโมท ค่าในตัวเรา ปุ่ม E ในแมพ และโค้ดฝั่งเรา ไว้ที่โฟลเดอร์ GameDump/<PlaceId> (ใช้เวลาเป็นนาที)",
    Callback = function()
        if dumping then return end
        dumping = true
        task.spawn(function()
            local ok, err = pcall(function()
                loadstring(game:HttpGet(BASE .. "Dump.lua"))()
            end)
            if not ok then
                Fluent:Notify({ Title = "อ่านระบบเซิฟ", Content = "ไม่สำเร็จ: " .. tostring(err), Duration = 6 })
            end
            dumping = false
        end)
    end,
})

-- ค้นโค้ดตามชื่อระบบ: decompile เฉพาะสคริปต์ที่ชื่อ/ที่อยู่มีคำที่พิมพ์ แล้วก๊อปลงคลิปบอร์ด + เซฟไฟล์
local findWords = "BagShop, DailyLogin, Halloween, WeaponShop, ServerBrowser"
local function findCode(words)
    if typeof(decompile) ~= "function" then return false, "ตัวรันนี้ decompile ไม่ได้" end
    local keys = {}
    for w in string.gmatch(words, "[^,]+") do
        w = string.lower((w:gsub("^%s+", ""):gsub("%s+$", "")))
        if w ~= "" then keys[#keys + 1] = w end
    end
    if #keys == 0 then return false, "พิมพ์ชื่อระบบก่อน" end
    local found, seen = {}, {}
    local function check(inst)
        if seen[inst] or not (inst:IsA("LocalScript") or inst:IsA("ModuleScript")) then return end
        seen[inst] = true
        local full = inst:GetFullName()
        -- สำเนาใน StarterGui/StarterPlayer ซ้ำกับของที่อยู่ในตัวเรา ข้ามไป
        if full:find("^StarterGui%.") or full:find("^StarterPlayer%.") then return end
        local low = string.lower(full)
        for _, k in ipairs(keys) do
            if string.find(low, k, 1, true) then
                found[#found + 1] = { inst = inst, path = full }
                return
            end
        end
    end
    for _, root in ipairs({ ReplicatedStorage, game:GetService("ReplicatedFirst"), LocalPlayer, workspace }) do
        for _, inst in ipairs(root:GetDescendants()) do check(inst) end
    end
    if #found == 0 then return false, "ไม่เจอสคริปต์ที่มีคำนี้" end
    table.sort(found, function(a, b) return a.path < b.path end)
    local parts = {}
    for i, f in ipairs(found) do
        local ok, src = pcall(decompile, f.inst)
        parts[#parts + 1] = "-- ==== " .. f.path .. "\n" .. (ok and tostring(src) or ("-- decompile ไม่ได้: " .. tostring(src))) .. "\n"
        if i % 5 == 0 then task.wait() end
    end
    local text = table.concat(parts, "\n")
    local file = "GameDump/" .. game.PlaceId .. "/find.txt"
    pcall(function()
        if typeof(makefolder) == "function" then
            if not (typeof(isfolder) == "function" and isfolder("GameDump")) then makefolder("GameDump") end
            if not (typeof(isfolder) == "function" and isfolder("GameDump/" .. game.PlaceId)) then
                makefolder("GameDump/" .. game.PlaceId)
            end
        end
        writefile(file, text)
    end)
    pcall(function() setclipboard(text) end)
    return true, string.format("เจอ %d สคริปต์ ก๊อปลงคลิปบอร์ดแล้ว (เซฟที่ %s ด้วย)", #found, file)
end

local findSection = Tabs.tools:AddSection("ค้นโค้ดตามชื่อระบบ")
findSection:AddInput("MiscFindWords", {
    Title = "ชื่อระบบ (คั่นด้วย ,)",
    Default = findWords,
    Placeholder = "เช่น BagShop, DailyLogin",
    Finished = false,
}):OnChanged(function(v)
    findWords = v
end)
local finding = false
findSection:AddButton({
    Title = "ค้นแล้วก๊อปโค้ด",
    Description = "ก๊อปโค้ดของระบบที่พิมพ์ลงคลิปบอร์ด วางส่งได้เลย ไม่ต้องไปหาไฟล์",
    Callback = function()
        if finding then return end
        finding = true
        task.spawn(function()
            local ok, _, msg = pcall(findCode, findWords)
            if not ok then msg = _ end
            Fluent:Notify({ Title = "ค้นโค้ด", Content = tostring(msg), Duration = 6 })
            finding = false
        end)
    end,
})

if Window then Window:SelectTab(1) end

-- ปิดหน้าต่าง = หยุดตัวนี้ (คืนกล้อง)
task.spawn(function()
    while alive() and not Fluent.Unloaded do task.wait(1) end
    if alive() then env.MiscRun += 1 end
end)
