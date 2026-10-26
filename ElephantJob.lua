-- แมพงานเลี้ยงช้าง / ลากซุง
-- ขั้นแรก: วาร์ปไปหา NPC "ตาโชคเลี้ยงช้าง" แล้วกดคุย (E) "คุยเรื่องงานลากซุง"
-- รับงานจริงด้วย ReplicatedStorage.ElephantJobSystem.Remotes.Request:InvokeServer("Accept", <รหัสงาน>)

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

---------------------------------------------------------------- เลือก "1.) รับงานลากซุง"
-- คุยแล้วมีตัวเลือก 1.) ["รับงานลากซุง"]  2.) ["ไว้ก่อนครับ"] -> เลือกข้อ 1 แล้วเกมส่ง Accept + รหัสงานเอง
local function isShown(gui)
    while gui do
        if gui:IsA("ScreenGui") then return gui.Enabled end
        if gui:IsA("GuiObject") and not gui.Visible then return false end
        gui = gui.Parent
    end
    return false
end

local ACCEPT_WORDS = { "รับงานลากซุง", "accept", "take the job" }
-- strict = ต้องมี "1." ด้วย (กันไปเจอป้ายชื่องานที่ตั้งอยู่ในแมพตลอด)
local function scanAccept(root, needShown, strict)
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and (not needShown or isShown(d))
            and (not strict or d.Text:find("1.", 1, true)) then
            local t = d.Text:lower()
            for _, w in ipairs(ACCEPT_WORDS) do
                if t:find(w, 1, true) and not t:find("ไว้ก่อน", 1, true) then
                    return d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton") or d
                end
            end
        end
    end
end
-- หน้าต่างตัวเลือกหลังคุย: หาในหน้าจอก่อน ไม่เจอค่อยหาในแมพ/CoreGui (บางเกมทำเป็นป้ายเหนือหัว)
local function findAcceptOption()
    local found = scanAccept(LocalPlayer.PlayerGui, true)
    if found then return found end
    for _, bb in ipairs(workspace:GetDescendants()) do
        if (bb:IsA("BillboardGui") or bb:IsA("SurfaceGui")) and bb.Enabled then
            found = scanAccept(bb, false, true)
            if found then return found end
        end
    end
    pcall(function() found = scanAccept(game:GetService("CoreGui"), false, true) end)
    return found
end

local function clickGui(gui)
    local c = gui.AbsolutePosition + gui.AbsoluteSize / 2
    local sg = gui:FindFirstAncestorWhichIsA("ScreenGui")
    if sg and not sg.IgnoreGuiInset then
        c += game:GetService("GuiService"):GetGuiInset()
    end
    VirtualInputManager:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 1)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 1)
end

local function pressGuiButton(button)
    if button:IsA("GuiButton") then
        for _, signal in ipairs({ "MouseButton1Click", "Activated" }) do
            local fired = pcall(function()
                if typeof(firesignal) == "function" then
                    firesignal(button[signal])
                elseif typeof(getconnections) == "function" then
                    for _, c in ipairs(getconnections(button[signal])) do c:Fire() end
                else
                    error("no")
                end
            end)
            if fired then return end
        end
    end
    clickGui(button)
end

-- ขี่ช้างอยู่ไหม (นั่งบนที่นั่งของช้าง) ใช้ได้เฉพาะถ้าเกมใช้ Seat
local function riding()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and (hum.SeatPart ~= nil or hum.Sit) then return true end
    -- แมพนี้ไม่ได้ใช้ที่นั่ง: ขี่อยู่ = เกมส่ง BuffaloRideNetwork.Input มาเมื่อกี้
    -- หรือตัวผู้เล่นถูกเชื่อมติดกับช้าง (ชิ้นหลักของก้อนไม่ใช่ตัวเราแล้ว)
    if env.ElephantInputAt and os.clock() - env.ElephantInputAt < 1.5 then return true end
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    return hrp ~= nil and hrp.AssemblyRootPart ~= nil and hrp.AssemblyRootPart ~= hrp
end

-- มีงานลากซุงอยู่ไหม: เพิ่งรับงาน (ดัก Request "Accept" ได้) / ป้ายบนจอ "ลากซุงไปจุด"
-- / ป้าย "จุดส่งซุง" ในแมพ  ถ้ามีงานอยู่ห้ามรับงานซ้ำ และห้ามวาร์ป (วาร์ปตอนขี่ = ช้างจมดิน)
local findTarget -- ประกาศไว้ก่อน ตัวจริงอยู่ข้างล่าง
local function hudActive()
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and d.Text:find("ลากซุงไปจุด", 1, true) then
            return true
        end
    end
    return false
end
local function jobActive()
    -- รับงานแล้วถือว่ามีงานไปยาวๆ (กันรับซ้ำ) จนกว่าจะกด ลงจากช้าง หรือผ่านไป 10 นาทีไม่เห็นป้ายงาน
    if env.ElephantAcceptAt and os.clock() - env.ElephantAcceptAt < 600 then return true end
    -- ไม่นับป้าย "จุดส่งซุง" ในแมพ (บางป้ายตั้งอยู่ตลอด ทำให้คิดว่ามีงานทั้งที่ไม่มี)
    return riding() or hudActive()
end

-- รหัสงาน (uuid) ที่ต้องส่งไปกับ Accept: เซิร์ฟเวอร์ส่งมาตอนกดคุย (ดักรีโมทฝั่งเราไม่เจอ)
-- เลยฟังทุก RemoteEvent ใน ElephantJobSystem + หาในหน้าต่างคุย แล้วจำ uuid ล่าสุดไว้
local UUID = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local function findUuid(v, depth)
    depth = depth or 0
    if typeof(v) == "string" then
        return v:match(UUID)
    elseif typeof(v) == "table" and depth < 4 then
        for k, x in pairs(v) do
            local id = findUuid(k, depth + 1) or findUuid(x, depth + 1)
            if id then return id end
        end
    elseif typeof(v) == "Instance" and depth < 4 then
        for _, x in pairs(v:GetAttributes()) do
            local id = findUuid(x, depth + 1)
            if id then return id end
        end
        if v:IsA("StringValue") then return findUuid(v.Value, depth + 1) end
    end
end
local offer = { id = nil, at = 0, from = "-" }
local function setOffer(id, from)
    offer.id, offer.at, offer.from = id, os.clock(), from
end
local function watchRemote(r)
    if r:IsA("RemoteEvent") then
        r.OnClientEvent:Connect(function(...)
            local id = findUuid({ ... })
            if id then setOffer(id, r.Name) end
        end)
    end
end
task.spawn(function()
    local sys = game:GetService("ReplicatedStorage"):WaitForChild("ElephantJobSystem", 30)
    if not sys then return end
    for _, r in ipairs(sys:GetDescendants()) do watchRemote(r) end
    sys.DescendantAdded:Connect(watchRemote)
end)
local function sendAccept(id)
    local sys = game:GetService("ReplicatedStorage"):FindFirstChild("ElephantJobSystem")
    local remotes = sys and sys:FindFirstChild("Remotes")
    local request = remotes and remotes:FindFirstChild("Request")
    if not request then return false end
    local ok, res = pcall(function() return request:InvokeServer("Accept", id) end)
    return ok, res
end

local function acceptJob()
    if jobActive() then
        status = "มีงานลากซุงอยู่แล้ว"
        return true
    end
    -- รับงานสำเร็จ = ป้าย "ลากซุงไปจุด" ขึ้น หรือได้ขี่ช้าง
    local function accepted()
        if hudActive() or riding() then
            env.ElephantAcceptAt = os.clock()
            return true
        end
        return false
    end
    local function pressOne()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
    end
    -- เก็บของที่ถืออยู่ก่อน (ถือของอยู่จะคุยกับ NPC ไม่ได้ / กด 1 ไปหยิบของ)
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:UnequipTools() end
    local talked, prompt = goTalk()
    if not talked then return false end
    -- ทางลัด: กดคุยแล้วได้รหัสงาน -> ส่ง Accept เองเลย ไม่ต้องพึ่งหน้าต่างตัวเลือก
    local askedAt = os.clock()
    pressPrompt(prompt, true)
    -- (ไม่เอา uuid จากหน้าจอ: เจอรหัสอื่นที่ไม่ใช่งาน แล้วสคริปต์นึกว่ารับงานแล้ว)
    local id
    if waitFor(2, function()
        id = offer.at >= askedAt and offer.id
        return id ~= nil and id ~= false
    end) then
        status = "ได้รหัสงานแล้ว ส่งรับงาน..."
        sendAccept(id)
        -- นับว่าสำเร็จต่อเมื่อขึ้นช้าง/ป้ายงานขึ้นจริง
        if waitFor(6, accepted) then
            status = "รับงานแล้ว"
            return true
        end
    end
    -- กด E จริงก่อน (เหมือนผู้เล่น) ถ้าหน้าต่างตัวเลือกไม่ขึ้นค่อยลอง fireproximityprompt
    local option
    local function dialog()
        option = findAcceptOption()
        return option ~= nil or accepted()
    end
    -- กดคุยไปแล้วข้างบน หน้าต่างอาจขึ้นอยู่แล้ว (กด E ซ้ำจะปิดมัน)
    if not waitFor(1, dialog) then
        pressPrompt(prompt, false)
        if not waitFor(3, dialog) then
            -- ห้ามกด 1 ตอนหน้าต่างไม่ขึ้น (จะไปเปิดกระเป๋า/ช่องของแทน)
            status = "กดคุยแล้วแต่หน้าต่างตัวเลือกไม่ขึ้น"
            return false
        end
    end
    if accepted() then
        status = "รับงานแล้ว"
        return true
    end
    status = "เจอตัวเลือก รับงานลากซุง กำลังเลือก..."
    -- หน้าต่างขึ้นแล้ว: กดเลข 1 (ผู้เล่นกดเองก็รับงานได้) ไม่ติดค่อยกดที่ตัวเลือก
    pressOne()
    if waitFor(6, accepted) then
        status = "รับงานแล้ว"
        return true
    end
    if option then pressGuiButton(option) end
    if waitFor(6, accepted) then
        status = "รับงานแล้ว"
        return true
    end
    status = "เจอตัวเลือกแล้วแต่กดไม่ติด"
    return false
end

-- ลงจากช้าง = เลิกงาน (เหมือนกด Spacebar): BuffaloRideNetwork.Dismount:FireServer()
local function dismount()
    local net = game:GetService("ReplicatedStorage"):FindFirstChild("BuffaloRideNetwork")
    local remote = net and net:FindFirstChild("Dismount")
    if not remote then
        status = "หา BuffaloRideNetwork.Dismount ไม่เจอ"
        return false
    end
    remote:FireServer()
    env.ElephantAcceptAt = nil
    env.ElephantMount = nil
    status = "ลงจากช้างแล้ว (เลิกงาน)"
    return true
end

---------------------------------------------------------------- ลากซุงอัตโนมัติ
-- ขี่ช้างอยู่ซุงติดมาแล้ว เดินไปจุดส่ง ("จุดส่งซุง 2") ตามลูกศร ส่งแล้วได้งานต่อทันที
-- บังคับช้าง: เกมส่ง BuffaloRideNetwork.Input:FireServer(ช้าง, 0, ทิศทาง) ทุกเฟรม
-- สคริปต์ดักการส่งนั้นแล้ว "เปลี่ยนทิศทาง" เป็นทิศไปจุดส่ง (เหมือนกดเดินไปทางนั้นเอง)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local auto = { on = false, delivered = 0, dir = nil }

local function inputRemote()
    local net = ReplicatedStorage:FindFirstChild("BuffaloRideNetwork")
    return net and net:FindFirstChild("Input")
end

-- ช้างของเรา: จากที่นั่ง หรือจากตัวแรกที่เกมส่งไปกับ Input (ดักได้ใน hook)
local function myMount()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if seat then return seat:FindFirstAncestorWhichIsA("Model") or seat end
    -- ช้างที่เกมส่งไปกับ Input (Remote Spy เห็นเป็น Model ไม่มี Parent ฝั่งเรา ก็ใช้ได้)
    local m = env.ElephantMount
    if typeof(m) == "Instance" then return m end
    -- ยังไม่เคยดักได้: ใช้โมเดลที่ตัวเราติดอยู่ด้วย (ขี่ = ตัวเชื่อมกับช้าง)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local rootPart = hrp and hrp.AssemblyRootPart
    if rootPart and rootPart ~= hrp and not rootPart:IsDescendantOf(char) then
        return rootPart:FindFirstAncestorWhichIsA("Model") or rootPart
    end
end

-- ติดตั้งตัวดักครั้งเดียว (รันสคริปต์ใหม่ใช้ตัวเดิม อ่านค่าจาก env)
-- Input:FireServer(ช้าง, flag, ทิศ) = จำช้างไว้ และเปลี่ยนทิศเป็นทิศไปจุดส่ง
-- ห้ามดัก InvokeServer: executor บางตัวรอผลใน hook ไม่ได้ ทำให้ Accept ของเกมพัง (ช้างไม่ขึ้น)
if not env.ElephantHook4 and typeof(hookmetamethod) == "function"
    and typeof(getnamecallmethod) == "function" then
    env.ElephantHook4 = true
    local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
    local old
    old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        if getnamecallmethod() == "FireServer" and self == inputRemote() then
            local mount, flag = ...
            if typeof(mount) == "Instance" then env.ElephantMount = mount end
            if not env.ElephantSelfInput then env.ElephantInputAt = os.clock() end
            local dir = env.ElephantAutopilotDir
            if dir then return old(self, mount, flag, dir) end
        end
        return old(self, ...)
    end))
end
-- บางเกมเรียก FireServer แบบไม่ผ่าน namecall (remote.FireServer(remote, ...)) ดักทางนี้ด้วย
if not env.ElephantHookFn and typeof(hookfunction) == "function" and inputRemote() then
    env.ElephantHookFn = true
    local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
    local oldFire
    oldFire = hookfunction(inputRemote().FireServer, wrap(function(self, ...)
        if self == inputRemote() then
            local mount, flag = ...
            if typeof(mount) == "Instance" then env.ElephantMount = mount end
            if not env.ElephantSelfInput then env.ElephantInputAt = os.clock() end
            local dir = env.ElephantAutopilotDir
            if dir then return oldFire(self, mount, flag, dir) end
        end
        return oldFire(self, ...)
    end))
end

-- ทางที่ 2: ป้อนทิศเข้าระบบควบคุมของ Roblox (เหมือนดันจอยเอง)
-- ช้างอาจเดินตามปุ่มเดิน/จอยฝั่งเรา ไม่ใช่ตามค่าใน Input -> แก้ ControlModule ให้คืนทิศเรา
task.spawn(function()
    local ok, controls = pcall(function()
        local pm = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
        return require(pm):GetControls()
    end)
    if not ok or typeof(controls) ~= "table" or controls.ElephantPatched then return end
    controls.ElephantPatched = true
    local function camRelative(dir)
        local cam = workspace.CurrentCamera
        local _, yaw = cam.CFrame:ToEulerAnglesYXZ()
        local rel = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(dir)
        return Vector3.new(rel.X, 0, rel.Z)
    end
    local origGet = controls.GetMoveVector
    if typeof(origGet) == "function" then
        controls.GetMoveVector = function(self, ...)
            local dir = env.ElephantAutopilotDir
            if dir and dir.Magnitude > 0 then return camRelative(dir) end
            return origGet(self, ...)
        end
    end
    local origMove = controls.moveFunction
    if typeof(origMove) == "function" then
        controls.moveFunction = function(player, vec, cameraRelative, ...)
            local dir = env.ElephantAutopilotDir
            if dir and dir.Magnitude > 0 then return origMove(player, dir, false) end
            return origMove(player, vec, cameraRelative, ...)
        end
    end
end)

-- เป้าหมาย: ป้าย "จุดส่งซุง" ที่ขึ้นอยู่ในแมพ
local TARGET_WORDS = { "จุดส่ง", "deliver", "drop off", "dropoff" }
function findTarget()
    local hrp = getRoot()
    local best, bestDist
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = d.Text:lower()
            local match = false
            for _, w in ipairs(TARGET_WORDS) do
                if t:find(w, 1, true) then match = true break end
            end
            if match then
                local bb = d:FindFirstAncestorWhichIsA("BillboardGui")
                if not bb or bb.Enabled then
                    local part = (bb and bb.Adornee) or d:FindFirstAncestorWhichIsA("BasePart")
                    if part and part:IsA("BasePart") then
                        local dist = hrp and (part.Position - hrp.Position).Magnitude or 0
                        if not bestDist or dist < bestDist then
                            best, bestDist = part, dist
                        end
                    end
                end
            end
        end
    end
    return best
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

-- จุดทางเดิน (หลบสิ่งกีดขวาง) ถ้าหาทางไม่ได้ เดินตรงไปเลย
local function computePath(from, to)
    local path = PathfindingService:CreatePath({ AgentRadius = 5, AgentHeight = 10, AgentCanJump = false })
    local ok = pcall(function() path:ComputeAsync(from, to) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local pts = {}
        for _, wp in ipairs(path:GetWaypoints()) do table.insert(pts, wp.Position) end
        return pts
    end
    return { to }
end

local function deliveryCount()
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if d:IsA("TextLabel") then
            local a, b = d.Text:match("ส่งซุงสำเร็จ%s*(%d+)%s*/%s*(%d+)")
            if a then return tonumber(a), tonumber(b) end
        end
    end
end

-- บังคับช้างผ่าน BuffaloRideNetwork.Input (เซิร์ฟเวอร์เป็นคนเดินช้าง)
-- เลื่อนช้างฝั่งเราเอง (ลอย/วาร์ป) เซิร์ฟเวอร์ไม่เห็น ถึงจุดแล้วก็ไม่นับ
local function driveTo(target)
    if not myMount() then
        status = "ขยับช้างเองนิดนึงก่อน (กด W) ให้สคริปต์จำช้างได้"
        return false
    end
    -- ตำแหน่งใช้ตัวผู้เล่น (ขี่อยู่บนช้าง ไปด้วยกัน) ไม่ต้องรู้ว่าช้างคือชิ้นไหน
    local root = getRoot()
    if not root then return false end
    local points = computePath(root.Position, target.Position)
    local i = 1
    local lastPos, lastMove, started = root.Position, os.clock(), os.clock()
    local lastCheck = 0
    -- กด W ค้างไว้ด้วย: ถ้าเกมส่ง Input เฉพาะตอนกดเดิน จะได้ส่ง (แล้ว hook เปลี่ยนทิศให้)
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
    local function releaseW()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    end
    while alive() and auto.on and root.Parent do
        local pos = root.Position
        -- เหยียบจุดแล้วป้ายจะย้ายไปจุดถัดไปเอง (ไม่มี remote) = ถึงแล้ว
        if os.clock() - lastCheck > 0.5 then
            lastCheck = os.clock()
            local now = findTarget()
            if now ~= target then
                env.ElephantAutopilotDir = nil
                releaseW()
                return true
            end
        end
        -- ถึงจุดทางเดินนี้แล้ว ไปจุดถัดไป
        while points[i] and flat(points[i] - pos).Magnitude < 6 and i < #points do
            i += 1
        end
        local dir = flat((points[i] or target.Position) - pos)
        dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero
        env.ElephantAutopilotDir = dir
        -- เกมส่ง Input เองรัวๆ อยู่แล้ว (hook เปลี่ยนทิศให้) ส่งเพิ่มเองด้วยถ้ารู้ว่าช้างตัวไหน
        local mount, remote = myMount(), inputRemote()
        if mount and remote then
            env.ElephantSelfInput = true
            pcall(function() remote:FireServer(mount, 0, dir) end)
            env.ElephantSelfInput = false
        end
        -- ติด 4 วิ: คำนวณทางใหม่
        if (pos - lastPos).Magnitude > 2 then
            lastPos, lastMove = pos, os.clock()
        elseif os.clock() - lastMove > 4 then
            points, i = computePath(pos, target.Position), 1
            lastMove = os.clock()
            status = ("ช้างไม่ขยับ หาทางใหม่ (ช้าง: %s, เกมส่ง Input ล่าสุด %s)"):format(
                tostring(mount and mount.Name),
                env.ElephantInputAt and ("%.0f วิที่แล้ว"):format(os.clock() - env.ElephantInputAt) or "ไม่เคย")
        end
        if os.clock() - started > 180 then break end -- กันวนไม่จบ
        RunService.Heartbeat:Wait() -- ส่งทุกเฟรมเหมือนเกม
    end
    env.ElephantAutopilotDir = nil
    releaseW()
    return false
end

-- รับงานแล้วแต่ยังไม่ได้ขึ้นช้าง: หาปุ่มขี่ช้าง (ProximityPrompt) ใกล้ๆ แล้วกด
local MOUNT_WORDS = { "ขี่", "ride", "mount", "ขึ้นช้าง" }
local function findMountPrompt()
    local hrp = getRoot()
    local best, bestDist
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") and p.Enabled then
            local text = (p.ActionText .. " " .. p.ObjectText .. " " .. (p.Parent and p.Parent.Name or "")):lower()
            local match = false
            for _, w in ipairs(MOUNT_WORDS) do
                if text:find(w, 1, true) then match = true break end
            end
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
    if hudActive() or riding() or os.clock() - lastMountTry < 5 then return end
    lastMountTry = os.clock()
    local prompt = findMountPrompt()
    if not prompt then
        status = "รับงานแล้ว รอขึ้นช้าง (ไม่เจอปุ่มขี่ช้าง)"
        return
    end
    local hrp, pos = getRoot(), promptPosition(prompt)
    if hrp and pos and (pos - hrp.Position).Magnitude > prompt.MaxActivationDistance - 2 then
        -- ยังไม่ได้ขี่ วาร์ปตัวไปข้างช้างได้ (ไม่จม)
        hrp.CFrame = CFrame.new(pos + Vector3.new(3, 2, 0), pos)
        task.wait(0.4)
    end
    status = "กดขึ้นช้าง (" .. prompt.ActionText .. ")"
    pressPrompt(prompt, true)
    task.wait(1)
    if not hudActive() and not riding() then pressPrompt(prompt, false) end
end

local function autoLoop()
    while alive() and auto.on do
        if not jobActive() then
            status = "ยังไม่มีงาน: ไปรับงาน"
            if not acceptJob() then task.wait(3) end
        else
            local target = findTarget()
            if not (hudActive() or riding()) then
                -- ยังไม่ได้ขึ้นช้าง (ป้าย "ลากซุงไปจุด" ยังไม่ขึ้น) ห้ามวาร์ปไปจุดส่งตัวเปล่า
                tryMount()
                task.wait(1)
            elseif not target then
                status = "ไม่เจอป้ายจุดส่งซุง รอ..."
                task.wait(1)
            else
                -- วาร์ปไปเกมไม่นับ (ทดสอบแล้ว) ต้องเดินช้างไปเอง
                status = "เดินช้างไป " .. target.Name
                if driveTo(target) then
                    auto.delivered += 1 -- ผ่านจุด (เหยียบแล้วป้ายย้ายไปจุดถัดไป)
                    status = "ผ่าน " .. target.Name .. " ไปจุดถัดไป"
                end
            end
        end
        task.wait(0.2)
    end
    env.ElephantAutopilotDir = nil
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
    Description = "รับงาน -> บังคับช้างเดินไปจุดส่งซุงทีละจุด (เหยียบแล้วไปจุดต่อ) -> งานต่อ วนไปเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then
        task.spawn(autoLoop)
    else
        env.ElephantAutopilotDir = nil
    end
end)
local statusPara = jobSection:AddParagraph({ Title = "สถานะ", Content = status })

Window:SelectTab(1)

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        local prompt = findJobPrompt()
        pcall(function()
            local done, total = deliveryCount()
            statusPara:SetDesc(("%s\nNPC: %s  •  มีงาน: %s\nผ่านจุดส่งไปแล้ว %d จุด%s"):format(status,
                prompt and ("เจอ (" .. prompt.ActionText .. ")") or "ยังหาไม่เจอ",
                jobActive() and "ใช่" or "ไม่", auto.delivered,
                done and ("  •  ในเกม %d/%d"):format(done, total) or ""))
        end)
        task.wait(1)
    end
    if alive() then env.ElephantRun += 1 end
end)
