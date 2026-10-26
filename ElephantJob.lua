-- แมพงานเลี้ยงช้าง / ลากซุง
-- ขั้นแรก: วาร์ปไปหา NPC "ตาโชคเลี้ยงช้าง" แล้วกดคุย (E) "คุยเรื่องงานลากซุง"
-- รับงาน: กดคุย -> OpenDialogue ส่ง token มา -> Request:InvokeServer("Accept", token)  ขับช้าง: BuffaloRideNetwork.Input

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.ElephantRun = (env.ElephantRun or 0) + 1
local RUN = env.ElephantRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.ElephantRun == RUN
end

local status = "-"

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function waitFor(timeout, check)
    local t = os.clock()
    while alive() and os.clock() - t < timeout do
        if check() then return true end
        task.wait(0.1)
    end
    return false
end

---------------------------------------------------------------- หา NPC
-- ปุ่มคุยของ NPC: ObjectText "ตาโชคเลี้ยงช้าง", ActionText "คุยเรื่องงานลากซุง"
-- เกมอาจเก็บข้อความเป็นอังกฤษแล้วแปลไทยตอนแสดง เลยหาทั้งไทยและอังกฤษ
local NPC_WORDS = { "ลากซุง", "ตาโชค", "เลี้ยงช้าง", "elephant", "log", "lumber", "timber" }

local function isJobPrompt(prompt)
    local text = (prompt.ObjectText .. " " .. prompt.ActionText .. " " .. prompt.Parent.Name):lower()
    for _, w in ipairs(NPC_WORDS) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

local npcPrompt
local function findJobPrompt()
    if npcPrompt and npcPrompt.Parent then return npcPrompt end
    npcPrompt = nil
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and isJobPrompt(d) then
            npcPrompt = d
            break
        end
    end
    return npcPrompt
end

local function promptPosition(prompt)
    local parent = prompt.Parent
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    local part = parent:FindFirstAncestorWhichIsA("BasePart") or parent:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.Position end
    if parent:IsA("Model") then return parent:GetPivot().Position end
end

-- ปุ่มที่ขึ้นบนจอตอนนี้ (ตัวเดียวกับที่ผู้เล่นเห็นแล้วกด E)
local shownPrompt
ProximityPromptService.PromptShown:Connect(function(p) shownPrompt = p end)
ProximityPromptService.PromptHidden:Connect(function(p)
    if shownPrompt == p then shownPrompt = nil end
end)

-- useFire = ใช้ fireproximityprompt  ไม่งั้นกดปุ่มจริง (เหมือนผู้เล่นกด E)
local function pressPrompt(prompt, useFire)
    if useFire and typeof(fireproximityprompt) == "function" then
        if pcall(fireproximityprompt, prompt) then return true end
    end
    local key = prompt.KeyboardKeyCode or Enum.KeyCode.E
    VirtualInputManager:SendKeyEvent(true, key, false, game)
    task.wait((prompt.HoldDuration or 0) + 0.15)
    VirtualInputManager:SendKeyEvent(false, key, false, game)
    return true
end

-- วาร์ปไปหน้า NPC แล้วกดคุย
local function goTalk()
    local hrp = getRoot()
    if not hrp then
        status = "ไม่มีตัวละคร"
        return false
    end
    local prompt = findJobPrompt()
    local target
    if prompt then
        local pos = promptPosition(prompt)
        if pos then
            -- ยืนห่าง NPC 4 studs หันหน้าเข้าหา
            local from = pos + (hrp.Position - pos) * Vector3.new(1, 0, 1)
            local dir = (from - pos).Magnitude > 0.1 and (from - pos).Unit or Vector3.new(0, 0, 1)
            local standAt = pos + dir * 4
            target = CFrame.lookAt(standAt, Vector3.new(pos.X, standAt.Y, pos.Z))
        end
    end
    target = target or env.ElephantNpcSpot
    if not target then
        status = "หา NPC ไม่เจอ: เดินไปหน้า NPC แล้วกด บันทึกจุด NPC"
        return false
    end
    hrp.CFrame = target
    status = "วาร์ปไปหา NPC แล้ว รอปุ่มคุยขึ้น..."
    -- ปุ่มที่ขึ้นอยู่ก่อนแล้ว (เกิดมาข้าง NPC) จะไม่มีสัญญาณ "ขึ้นใหม่" เลยใช้ปุ่ม NPC ที่หาเจอได้เลย
    local function usable()
        if shownPrompt and shownPrompt.Parent then return shownPrompt end
        local pos = prompt and promptPosition(prompt)
        if pos and (pos - hrp.Position).Magnitude <= prompt.MaxActivationDistance + 1 then
            return prompt
        end
    end
    local use
    if not waitFor(3, function() use = usable() return use ~= nil end) then
        status = "วาร์ปไปแล้วแต่ปุ่มคุยไม่ขึ้น"
        return false
    end
    status = ("กดคุยแล้ว (%s)"):format(use.ActionText)
    return true, use
end

---------------------------------------------------------------- ข้อมูลงานจากเกม
-- อ่านจากโค้ดเกม (PlayerGui.ElephantJobUI.Client, PlayerScripts.BuffaloRideClient):
--   Remotes.State        เซิร์ฟเวอร์ -> เรา { status = "None" / "Active" / ส่งแล้ว, index, cframe, size, road }
--                        status ไม่ใช่ "Active" = ส่งแล้ว ต้องขี่กลับไปหาตาโชค (cframe = จุดที่ต้องไป)
--   Remotes.OpenDialogue เซิร์ฟเวอร์ -> เรา ตอนกดคุย { kind = "Question", token, message }
--   Remotes.Request:InvokeServer("Accept", token) = รับงาน / ("State") = ขอสถานะงาน
--   LocalPlayer.BuffaloRideMount (ObjectValue) = ช้างที่ขี่อยู่ (ข้างในมี MountRoot)
--   BuffaloRideNetwork.Input:FireServer(ช้าง, คันเร่ง, ทิศ) คันเร่ง 1 = เดินหน้า 0 = หยุด -1 = ถอย
--     ทิศ = ทิศที่กล้องหัน (แนวราบ) เซิร์ฟเวอร์เป็นคนเดินช้าง
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local JobSystem = ReplicatedStorage:WaitForChild("ElephantJobSystem")
local JobRemotes = JobSystem:WaitForChild("Remotes")
local RideNet = ReplicatedStorage:WaitForChild("BuffaloRideNetwork")
local InputRemote = RideNet:WaitForChild("Input")
local okNav, RoadNavigation = pcall(function() return require(JobSystem:WaitForChild("RoadNavigation")) end)
if not okNav then RoadNavigation = nil end

local jobState = { status = "None" }
local offer = { token = nil, at = 0 }
local conns = {}
table.insert(conns, JobRemotes:WaitForChild("State").OnClientEvent:Connect(function(s)
    if type(s) == "table" then jobState = s end
end))
table.insert(conns, JobRemotes:WaitForChild("OpenDialogue").OnClientEvent:Connect(function(d)
    if type(d) == "table" and d.kind == "Question" and d.token then
        offer.token, offer.at = d.token, os.clock()
    end
end))
task.spawn(function()
    while alive() do task.wait(1) end
    for _, c in ipairs(conns) do c:Disconnect() end
end)

local function request(action, arg)
    local ok, res = pcall(function() return JobRemotes.Request:InvokeServer(action, arg) end)
    if ok and type(res) == "table" then return res end
    return { ok = false, message = ok and "-" or tostring(res) }
end
task.spawn(function()
    local res = request("State")
    if res.ok and type(res.state) == "table" then jobState = res.state end
end)

-- ช้างที่ขี่อยู่ + ชิ้นหลัก (MountRoot)
local function myMount()
    local ref = LocalPlayer:FindFirstChild("BuffaloRideMount")
    local m = ref and ref.Value
    if m and m:IsDescendantOf(workspace) then
        local root = m:FindFirstChild("MountRoot")
        if root then return m, root end
    end
end
local function riding()
    return myMount() ~= nil
end
local function jobActive()
    return jobState.status ~= nil and jobState.status ~= "None"
end

---------------------------------------------------------------- รับงาน
-- กดคุย -> เซิร์ฟเวอร์ส่ง token มาทาง OpenDialogue -> ส่ง Accept + token เอง (ไม่ต้องกดตัวเลือก)
-- ขี่ช้างอยู่ห้ามวาร์ป (ช้างจม) ต้องขี่ไปใกล้ NPC ก่อน
local function acceptJob()
    if jobState.status == "Active" then
        status = "มีงานอยู่แล้ว"
        return true
    end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:UnequipTools() end
    local prompt
    if riding() then
        prompt = findJobPrompt()
        if not prompt then
            status = "หา NPC ไม่เจอ"
            return false
        end
    else
        local talked
        talked, prompt = goTalk()
        if not talked then return false end
    end
    local askedAt = os.clock()
    local function asked() return offer.at >= askedAt and offer.token ~= nil end
    pressPrompt(prompt, true)
    if not waitFor(3, asked) then
        pressPrompt(prompt, false)
        if not waitFor(3, asked) then
            status = "กดคุยแล้วแต่ NPC ไม่ถามรับงาน"
            return false
        end
    end
    local res = request("Accept", offer.token)
    offer.token = nil
    if waitFor(6, function() return jobState.status == "Active" end) then
        status = "รับงานแล้ว"
        return true
    end
    status = "รับงานไม่สำเร็จ: " .. tostring(res.message or "-")
    return false
end

-- ลงจากช้าง = เลิกงาน (เหมือนกด Spacebar): BuffaloRideNetwork.Dismount:FireServer()
local function dismount()
    env.ElephantDrive = nil
    RideNet.Dismount:FireServer()
    status = "ลงจากช้างแล้ว (เลิกงาน)"
    return true
end

---------------------------------------------------------------- ลากซุงอัตโนมัติ
local auto = { on = false, delivered = 0 }

-- เกมส่ง Input เองทุก 0.05-0.1 วิ (คันเร่งจากปุ่ม W/S) ถ้าไม่ดักไว้ มันจะส่ง "หยุด" ทับของเรา
-- ตอนขับเอง: เปลี่ยนเป็น คันเร่ง/ทิศ ของสคริปต์ (env.ElephantDrive) ไม่ดัก = ส่งตามปกติ
if not env.ElephantHook5 and typeof(hookmetamethod) == "function"
    and typeof(getnamecallmethod) == "function" then
    env.ElephantHook5 = true
    local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
    local old
    old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local drive = env.ElephantDrive
        if drive and self == drive.remote and getnamecallmethod() == "FireServer" then
            local mount = ...
            return old(self, mount, drive.throttle, drive.dir)
        end
        return old(self, ...)
    end))
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function deliveryCount()
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if d:IsA("TextLabel") then
            local a, b = d.Text:match("ส่งซุงสำเร็จ%s*(%d+)%s*/%s*(%d+)")
            if a then return tonumber(a), tonumber(b) end
        end
    end
end

-- เส้นทางตามถนนแบบเดียวกับลูกศรในเกม (RoadNavigation.Build) หาไม่ได้ = เดินตรง
local function buildPath(from, to)
    if RoadNavigation and jobState.road then
        local ok, path = pcall(RoadNavigation.Build, jobState.road, from, to)
        if ok and type(path) == "table" and #path > 0 then return path end
    end
    return { from, to }
end

-- ขับช้างไป pos จนกว่า done() จริง (เกมนับแล้ว) หรือถึงระยะ arrive (ถ้า done = nil)
local function driveTo(pos, arrive, done)
    local path, pathAt = nil, 0
    local lastPos, lastMove, started, lastSend = nil, os.clock(), os.clock(), 0
    local reverseUntil = 0
    local result = false
    while alive() and auto.on do
        if done and done() then result = true break end
        local mount, root = myMount()
        if not root then break end
        local ground = root.Position - Vector3.new(0, (mount:GetAttribute("GroundOffset") or 6.91) - 0.2, 0)
        local dist = flat(pos - ground).Magnitude
        if not done and dist <= arrive then result = true break end
        if os.clock() - pathAt > 0.5 or not path then
            pathAt = os.clock()
            path = buildPath(ground, pos)
        end
        -- จุดถัดไปบนเส้นทางที่ห่างเกิน 6 studs (ใกล้เป้าแล้วเล็งเป้าตรงๆ)
        local wp = pos
        if dist > 8 then
            for i = 2, #path do
                if flat(path[i] - ground).Magnitude > 6 then wp = path[i] break end
            end
        end
        local d = flat(wp - ground)
        local dir = d.Magnitude > 0.05 and d.Unit or flat(root.CFrame.LookVector).Unit
        local throttle = 1
        if os.clock() < reverseUntil then throttle = -1 end
        -- ถึงกลางจุดส่งแล้วแต่เกมยังไม่นับ: ค่อยๆ เดินหน้าช้าๆ ผ่านจุด
        env.ElephantDrive = { remote = InputRemote, throttle = throttle, dir = dir }
        if os.clock() - lastSend > 0.1 then
            lastSend = os.clock()
            pcall(function() InputRemote:FireServer(mount, throttle, dir) end)
        end
        -- ติด 3 วิ: ถอยหลัง 1 วิแล้วไปต่อ
        if not lastPos or (root.Position - lastPos).Magnitude > 1.5 then
            lastPos, lastMove = root.Position, os.clock()
        elseif os.clock() - lastMove > 3 then
            lastMove = os.clock()
            reverseUntil = os.clock() + 1
            status = "ช้างติด ถอยแล้วไปใหม่"
        end
        if os.clock() - started > 300 then break end -- กันวนไม่จบ
        RunService.Heartbeat:Wait()
    end
    env.ElephantDrive = nil
    local mount = myMount()
    if mount then
        pcall(function() InputRemote:FireServer(mount, 0, flat(workspace.CurrentCamera.CFrame.LookVector).Unit) end)
    end
    return result
end

-- รับงานแล้วแต่ยังไม่ได้ขึ้นช้าง: หาปุ่มขี่ช้าง (ProximityPrompt บนช้าง) ใกล้ๆ แล้วกด
local CollectionService = game:GetService("CollectionService")
local MOUNT_WORDS = { "ขี่", "ride", "mount", "ขึ้นช้าง" }
local function findMountPrompt()
    local hrp = getRoot()
    local best, bestDist
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") and p.Enabled then
            local text = (p.ActionText .. " " .. p.ObjectText):lower()
            local match = false
            for _, w in ipairs(MOUNT_WORDS) do
                if text:find(w, 1, true) then match = true break end
            end
            local model = p:FindFirstAncestorWhichIsA("Model")
            if model and CollectionService:HasTag(model, "RideableBuffalo") then match = true end
            local pos = match and promptPosition(p)
            if pos and hrp then
                local d = (pos - hrp.Position).Magnitude
                if d < 150 and (not bestDist or d < bestDist) then best, bestDist = p, d end
            end
        end
    end
    return best
end

local lastMountTry = 0
local function tryMount()
    if riding() or os.clock() - lastMountTry < 5 then return end
    lastMountTry = os.clock()
    local prompt = findMountPrompt()
    if not prompt then
        status = "มีงานแต่ไม่ได้ขี่ช้าง (ไม่เจอปุ่มขี่ช้าง)"
        return
    end
    local hrp, pos = getRoot(), promptPosition(prompt)
    if hrp and pos and (pos - hrp.Position).Magnitude > prompt.MaxActivationDistance - 2 then
        hrp.CFrame = CFrame.new(pos + Vector3.new(3, 2, 0), pos) -- ยังไม่ได้ขี่ วาร์ปได้
        task.wait(0.4)
    end
    status = "กดขึ้นช้าง (" .. prompt.ActionText .. ")"
    pressPrompt(prompt, true)
end

local function autoLoop()
    while alive() and auto.on do
        local st = jobState.status
        if not jobActive() and not riding() then
            status = "ยังไม่มีงาน: ไปรับงาน"
            if not acceptJob() then task.wait(3) end
        elseif not riding() then
            tryMount()
            task.wait(1)
        elseif st == "Active" and jobState.cframe then
            local idx = jobState.index
            status = "ขับช้างไปจุดส่ง " .. tostring(idx)
            if driveTo(jobState.cframe.Position, 0, function()
                return jobState.status ~= "Active" or jobState.index ~= idx
            end) then
                auto.delivered += 1
                status = "ส่งจุด " .. tostring(idx) .. " แล้ว"
            end
        else
            -- ส่งแล้ว (หรือไม่มีงานแต่ขี่อยู่): ขี่กลับไปหาตาโชคแล้วรับงานต่อ
            local npc = findJobPrompt()
            local back = (jobState.cframe and jobState.cframe.Position) or (npc and promptPosition(npc))
            if back then
                status = "ส่งซุงแล้ว ขี่กลับไปหาตาโชค"
                driveTo(back, 10, nil)
            end
            if auto.on and alive() and jobState.status ~= "Active" then
                if not acceptJob() then task.wait(2) end
            end
        end
        task.wait(0.2)
    end
    env.ElephantDrive = nil
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
local ok, Fluent = pcall(loadFluent, true)
if not ok or typeof(Fluent) ~= "table" then
    ok, Fluent = pcall(loadFluent, false)
end
if not ok or typeof(Fluent) ~= "table" then
    warn("[ElephantJob] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

if env.ElephantFluent then
    pcall(function() env.ElephantFluent:Destroy() end)
end
env.ElephantFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "งานเลี้ยงช้าง",
    SubTitle = "Elephant Job",
    TabWidth = 150,
    Size = UDim2.fromOffset(540, 380),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})
local Tabs = {
    main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
}

local jobSection = Tabs.main:AddSection("รับงานลากซุง")
jobSection:AddButton({
    Title = "วาร์ปไปรับงานลากซุง",
    Description = "วาร์ปไปหา ตาโชคเลี้ยงช้าง -> กด E คุย -> เลือก 1.) รับงานลากซุง -> ขึ้นขี่ช้าง",
    Callback = function()
        task.spawn(acceptJob)
    end,
})
jobSection:AddButton({
    Title = "ลงจากช้าง (เลิกงาน)",
    Description = "เหมือนกด Spacebar ตอนขี่ช้าง",
    Callback = function()
        dismount()
    end,
})
jobSection:AddButton({
    Title = "บันทึกจุด NPC",
    Description = "ใช้ตอนสคริปต์หา NPC เองไม่เจอ: ยืนหน้า NPC แล้วกด",
    Callback = function()
        local hrp = getRoot()
        if hrp then
            env.ElephantNpcSpot = hrp.CFrame
            Fluent:Notify({ Title = "บันทึกแล้ว", Content = "จุด NPC", Duration = 4 })
        end
    end,
})
local autoSection = Tabs.main:AddSection("ลากซุงอัตโนมัติ")
autoSection:AddToggle("EJAuto", {
    Title = "ลากซุงอัตโนมัติ",
    Description = "รับงาน -> ขับช้างตามถนนไปจุดส่ง -> ขี่กลับไปหาตาโชค -> รับงานต่อ วนไปเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then
        task.spawn(autoLoop)
    else
        env.ElephantDrive = nil
    end
end)
local statusPara = jobSection:AddParagraph({ Title = "สถานะ", Content = status })

Window:SelectTab(1)

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        local prompt = findJobPrompt()
        pcall(function()
            local done, total = deliveryCount()
            statusPara:SetDesc(("%s\nNPC: %s  •  งาน: %s  •  ขี่ช้าง: %s\nส่งไปแล้ว %d จุด%s"):format(status,
                prompt and ("เจอ (" .. prompt.ActionText .. ")") or "ยังหาไม่เจอ",
                tostring(jobState.status) .. (jobState.index and (" จุด " .. tostring(jobState.index)) or ""),
                riding() and "ใช่" or "ไม่", auto.delivered,
                done and ("  •  ในเกม %d/%d"):format(done, total) or ""))
        end)
        task.wait(1)
    end
    if alive() then env.ElephantRun += 1 end
end)
