-- ทั่วไป: ฟรีแคม (ตั้งปุ่มเปิด/ปิดได้) ใช้ได้ทุกแมพ
-- ฟรีแคม: กล้องลอยอิสระ ตัวละครอยู่ที่เดิม งานอื่นทำต่อได้ปกติ

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
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
        Size = UDim2.fromOffset(540, 320),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local section = Tabs.main:AddSection("ฟรีแคม")
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

if Window then Window:SelectTab(1) end

-- ปิดหน้าต่าง = หยุดตัวนี้ (คืนกล้อง)
task.spawn(function()
    while alive() and not Fluent.Unloaded do task.wait(1) end
    if alive() then env.MiscRun += 1 end
end)
