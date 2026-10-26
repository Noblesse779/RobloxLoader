-- เควสปลูกข้าว (ลุงหมา) อัตโนมัติ
-- อ่านจากโค้ดเกม (PlayerScripts.RiceQuestSystem.RiceQuestClient + RiceQuestConfig):
--   คุย: ProximityPrompt workspace["ลุงหมา"].Head.RiceQuestPrompt -> Remotes.OpenDialogue { kind, token }
--        kind = "Question" -> Request("Accept", token) -> { ok, token } -> Request("FinishIntro", token) = ได้ข้าว 10 ต้น
--        kind = "Reward" (ได้เงิน) / อื่นๆ = ยังมีข้าวเหลือ (remaining)
--   ปลูก: ถือ Tool ข้าว (Attribute RiceQuestTool + InventoryOwner) ยืนในแปลง workspace.RiceZone -> Request("UseRice")
--         ห่างต้นอื่น >= 3 studs, ระหว่างปลูกห้ามขยับเกิน 4 studs, LocalPlayer.RiceActionBusy = กำลังทำท่า
--   เก็บ: ต้นใน workspace.RiceCrops ที่ OwnerUserId = เรา และ ReadyAt <= เวลาเซิร์ฟเวอร์ -> Request("UseRice", ต้น) ในระยะ 7

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.RiceRun = (env.RiceRun or 0) + 1
local RUN = env.RiceRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.RiceRun == RUN
end

local System = ReplicatedStorage:WaitForChild("RiceQuestSystem")
local Config = require(System:WaitForChild("RiceQuestConfig"))
local Remotes = System:WaitForChild("Remotes")
local RiceCrops = workspace:WaitForChild("RiceCrops")

local status = "-"
local auto = { on = false, planted = 0, harvested = 0, walk = true } -- walk = เดินเอง (กันโดนแบน) / false = วาร์ป

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

local function request(action, arg)
    local ok, res = pcall(function() return Remotes.Request:InvokeServer(action, arg) end)
    if ok and type(res) == "table" then return res end
    return { ok = false, message = ok and "-" or tostring(res) }
end

-- เซิร์ฟเวอร์ส่งมาตอนกดคุยกับลุงหมา
local dialogue = { data = nil, at = 0 }
-- แจ้งเตือนจากเกม เช่น "เก็บข้าวสำเร็จ! ได้รับเงิน 59 บาท" = เก็บเสร็จแล้ว ไปต้นต่อไปได้เลย
local notify = { text = "", at = 0 }
local conns = {
    Remotes.OpenDialogue.OnClientEvent:Connect(function(d)
        if type(d) == "table" then dialogue.data, dialogue.at = d, os.clock() end
    end),
    Remotes.Notify.OnClientEvent:Connect(function(text)
        if type(text) == "string" then notify.text, notify.at = text, os.clock() end
    end),
}
task.spawn(function()
    while alive() do task.wait(1) end
    for _, c in ipairs(conns) do c:Disconnect() end
end)

---------------------------------------------------------------- ข้าวในกระเป๋า / ต้นข้าวของเรา
local function riceTools()
    local list = {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("RiceQuestTool") == true
                    and t:GetAttribute("InventoryOwner") == LocalPlayer.UserId then
                    table.insert(list, t)
                end
            end
        end
    end
    return list
end

-- ข้าวอยู่ในกระเป๋าของเกม (ไม่ใช่ Backpack) ต้องเอาออกมาไว้ช่องลัดก่อนถึงจะกลายเป็น Tool
-- เกมส่ง InventorySystem.Remotes.SetHotbar:FireServer({ ชื่อของในช่องลัดทั้งหมด })
-- ส่งรายการเดิมที่อยู่ในช่องลัด (Tool ที่มีอยู่) + "Rice" จะได้ไม่ไปลบของอื่นออกจากช่องลัด
-- ลองเอาออกมาไม่เกินทุก 4 วิ (ไม่มีข้าวในกระเป๋าแล้วจะได้ไม่ยิงรีโมทรัวๆ) force = เพิ่งได้ข้าวมา
local lastEnsure = 0
local function ensureRiceTool(force)
    if #riceTools() > 0 then return true end
    if not force and os.clock() - lastEnsure < 4 then return false end
    lastEnsure = os.clock()
    local inv = ReplicatedStorage:FindFirstChild("InventorySystem")
    local remote = inv and inv:FindFirstChild("Remotes") and inv.Remotes:FindFirstChild("SetHotbar")
    if not remote then return false end
    local names, seen = {}, {}
    for _, holder in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }) do
        if holder then
            for _, t in ipairs(holder:GetChildren()) do
                if t:IsA("Tool") and not seen[t.Name] then
                    seen[t.Name] = true
                    table.insert(names, t.Name)
                end
            end
        end
    end
    if not seen[Config.ToolName] then table.insert(names, Config.ToolName) end
    status = "เอาข้าวออกมาไว้ช่องลัด..."
    remote:FireServer(names)
    return waitFor(3, function() return #riceTools() > 0 end)
end

local function cropPart(model)
    local p = model:FindFirstChild("Handle") or model:FindFirstChildWhichIsA("BasePart", true)
    return p and p:IsA("BasePart") and p or nil
end

-- ต้นของเรา: { model, part, ready, left }
local function myCrops()
    local now = workspace:GetServerTimeNow()
    local list = {}
    for _, m in ipairs(RiceCrops:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            local part = cropPart(m)
            local readyAt = m:GetAttribute("ReadyAt") or math.huge
            if part then
                table.insert(list, {
                    model = m,
                    part = part,
                    ready = readyAt <= now and not m:GetAttribute("Harvesting"),
                    left = math.max(0, readyAt - now),
                })
            end
        end
    end
    return list
end

local function busy()
    return LocalPlayer:GetAttribute("RiceActionBusy") == true
end

---------------------------------------------------------------- ย้ายตัว (เดินเท้าเท่านั้น)
local function groundAt(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, RiceCrops }
    params.IgnoreWater = true -- นาข้าวมีน้ำ ยืนบนดินใต้น้ำ
    local hit = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
    return hit and hit.Position
end

-- เดินไปเอง (หาทางอ้อมรั้ว/สิ่งกีดขวาง) ใช้เวลานานกว่าแต่ปลอดภัยกว่าวาร์ป
local PathfindingService = game:GetService("PathfindingService")
local function walkTo(pos, arrive)
    local hrp = getRoot()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return false end
    local function close()
        local d = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        return d.Magnitude <= arrive
    end
    if close() then return true end
    local points = { pos }
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
    if pcall(function() path:ComputeAsync(hrp.Position, pos) end) and path.Status == Enum.PathStatus.Success then
        points = {}
        for _, wp in ipairs(path:GetWaypoints()) do
            table.insert(points, { pos = wp.Position, jump = wp.Action == Enum.PathWaypointAction.Jump })
        end
    else
        points = { { pos = pos } }
    end
    for _, wp in ipairs(points) do
        if not (alive() and auto.on) then return false end
        if close() then break end
        if wp.jump then hum.Jump = true end
        hum:MoveTo(wp.pos)
        local t, last, lastMove = os.clock(), hrp.Position, os.clock()
        while alive() and auto.on and os.clock() - t < 6 do
            local d = Vector3.new(wp.pos.X - hrp.Position.X, 0, wp.pos.Z - hrp.Position.Z)
            if d.Magnitude < 2 or close() then break end
            if (hrp.Position - last).Magnitude > 0.5 then
                last, lastMove = hrp.Position, os.clock()
            elseif os.clock() - lastMove > 1 then
                hum.Jump = true -- ติดขอบ/รั้วเตี้ย กระโดดข้าม
                lastMove = os.clock()
            end
            task.wait(0.1)
        end
    end
    hum:MoveTo(hrp.Position) -- หยุด
    return close()
end

local function moveTo(pos, arrive)
    local hrp = getRoot()
    if not hrp then return false end
    if LocalPlayer:FindFirstChild("BuffaloRideMount") and LocalPlayer.BuffaloRideMount.Value then
        status = "ลงจากช้างก่อน (กด Spacebar)"
        return false
    end
    if auto.walk then
        local ok = walkTo(pos, arrive or 1.5)
        task.wait(0.2)
        return ok
    end
    local ground = groundAt(pos) or pos
    hrp.CFrame = CFrame.new(ground + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.Position)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.35)
    return true
end

---------------------------------------------------------------- คุยกับลุงหมา (รับข้าว / รับเงิน)
local function npc()
    return workspace:FindFirstChild(Config.NpcName)
end

local function talk()
    local model = npc()
    local head = model and model:FindFirstChild("Head")
    local prompt = head and head:FindFirstChild("RiceQuestPrompt")
    if not prompt then
        status = "หาลุงหมาไม่เจอ"
        return false
    end
    -- ยืนตรงหน้าลุงหมา 4 studs ความสูงเท่าตัวลุง หันหน้าเข้าหา
    -- (ไม่ยิงหาพื้นจากข้างบน เพราะไปโดนหลังคาแล้ววาร์ปขึ้นไปอยู่บนหลังคา)
    local hrp = getRoot()
    if not hrp then return false end
    if LocalPlayer:FindFirstChild("BuffaloRideMount") and LocalPlayer.BuffaloRideMount.Value then
        status = "ลงจากช้างก่อน (กด Spacebar)"
        return false
    end
    if (hrp.Position - head.Position).Magnitude > 8 then
        local body = model:FindFirstChild("HumanoidRootPart") or head
        local look = Vector3.new(body.CFrame.LookVector.X, 0, body.CFrame.LookVector.Z)
        look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
        local stand = body.Position + look * 4
        if auto.walk then
            status = "เดินไปหาลุงหมา..."
            if not walkTo(stand, 3) then
                status = "เดินไปหาลุงหมาไม่ถึง"
                return false
            end
        else
            hrp.CFrame = CFrame.lookAt(stand, Vector3.new(body.Position.X, stand.Y, body.Position.Z))
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.35)
        end
    end
    local askedAt = os.clock()
    status = "คุยกับลุงหมา..."
    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
    end
    if not waitFor(4, function() return dialogue.at >= askedAt end) then
        status = "กดคุยแล้วลุงหมาไม่ตอบ"
        return false
    end
    local d = dialogue.data
    if d.kind ~= "Question" then
        status = d.kind == "Reward" and ("ได้เงินจากลุงหมา " .. tostring(d.amount) .. " บาท")
            or ("ลุงหมา: ยังมีข้าวเหลือ " .. tostring(d.remaining or "?") .. " ต้น")
        return d.kind == "Reward"
    end
    local res = request("Accept", d.token)
    if not res.ok then
        status = "รับข้าวไม่สำเร็จ: " .. tostring(res.message)
        return false
    end
    -- เกมรอลุงพูดจบ 2 ประโยคก่อนส่ง FinishIntro: ลองส่งเลย ไม่ได้ค่อยรอแล้วส่งใหม่
    local fin = request("FinishIntro", res.token)
    if not fin.ok then
        task.wait(Config.IntroLineSeconds * 2 + 0.5)
        fin = request("FinishIntro", res.token)
    end
    -- ข้าวที่ได้เข้ากระเป๋าของเกม ต้องเอาออกมาช่องลัดก่อนถึงจะถือได้
    if not (waitFor(2, function() return #riceTools() > 0 end) or ensureRiceTool(true)
        or (task.wait(1) and ensureRiceTool(true))) then
        status = "รับงานแล้วแต่ข้าวไม่เข้ากระเป๋า: " .. tostring(fin.message)
        return false
    end
    status = "ได้ข้าว " .. #riceTools() .. " ต้นแล้ว"
    return true
end

---------------------------------------------------------------- ปลูก
local function zone()
    local z = workspace:FindFirstChild(Config.ZoneName)
    return z and z:IsA("BasePart") and z or nil
end

-- จุดนั้นเป็นนา (มีน้ำอยู่เหนือพื้นแปลง) ไหม: เกมให้ปลูกเฉพาะตรงที่มีน้ำ ทางเดินดินที่ผ่ากลางแปลงไม่ได้
local function isPaddy(spot, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = false
    local hit = workspace:Raycast(Vector3.new(spot.X, z.Position.Y + 30, spot.Z), Vector3.new(0, -60, 0), params)
    return hit ~= nil and hit.Material == Enum.Material.Water
end

-- จุดปลูก: ตารางในแปลง ห่างกันพอดีระยะขั้นต่ำ เลือกจุดว่างที่เป็นนาและใกล้ตัวเราที่สุด = ปลูกติดๆ กันเป็นกลุ่ม
local function plantSpot()
    local z = zone()
    if not z then return nil end
    -- เผื่อระยะ: ต้นข้าวขึ้นตรงที่ตัวเรายืน ซึ่งคลาดจากจุดที่เล็งได้นิดหน่อย
    local spacing = (Config.MinimumPlantSpacing or 3) + 1.5
    local others = {}
    for _, m in ipairs(RiceCrops:GetChildren()) do
        local p = m:IsA("Model") and cropPart(m)
        if p then table.insert(others, Vector3.new(p.Position.X, 0, p.Position.Z)) end
    end
    local hrp = getRoot()
    local me = hrp and hrp.Position or z.Position
    me = Vector3.new(me.X, 0, me.Z)
    local hx, hz = z.Size.X / 2 - 2.5, z.Size.Z / 2 - 2.5
    local free = {}
    for x = -hx, hx, spacing do
        for zz = -hz, hz, spacing do
            local spot = (z.CFrame * CFrame.new(x, 0, zz)).Position
            local flatSpot = Vector3.new(spot.X, 0, spot.Z)
            local ok = true
            for _, o in ipairs(others) do
                if (o - flatSpot).Magnitude < spacing then ok = false break end
            end
            if ok then table.insert(free, { spot = spot, d = (me - flatSpot).Magnitude }) end
        end
    end
    table.sort(free, function(a, b) return a.d < b.d end)
    for _, c in ipairs(free) do
        if isPaddy(c.spot, z) then return c.spot end
    end
end

-- เกมล็อกตัวไว้ระหว่างท่า (RiceActionBusy) ทั้งที่ได้ผลแล้ว: ปลดล็อกฝั่งเราแล้วไปต่อเลย
local actionDone = false -- ทำต้นล่าสุดเสร็จแล้ว (ได้ต้น/ได้เงิน) ไม่ต้องรอท่าจบ
local function unfreeze()
    local hrp = getRoot()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hrp then hrp.Anchored = false end
    if hum then
        hum.PlatformStand = false
        if hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end
        if hum.UseJumpPower and hum.JumpPower <= 0 then hum.JumpPower = 50 end
    end
end

-- ส่งคำสั่งแบบไม่รอคำตอบ (คำตอบกลับมาตอนท่าจบ) แล้วดูผลจากของในแมพแทน
local function fire(action, arg)
    local box = { done = false, res = nil }
    task.spawn(function()
        box.res = request(action, arg)
        box.done = true
    end)
    return box
end

local function plantOne()
    local tool = riceTools()[1]
    if not tool then return false end
    -- ถือข้าวให้ได้ก่อน แล้วค่อยทำอย่างอื่น
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if tool.Parent ~= LocalPlayer.Character then
        status = "หยิบข้าวขึ้นมาถือ..."
        hum:EquipTool(tool)
        if not waitFor(2, function() return tool.Parent == LocalPlayer.Character end) then
            status = "หยิบข้าวขึ้นมาถือไม่ได้"
            return false
        end
    end
    local spot = plantSpot()
    if not spot then
        status = "หาที่ว่างในแปลงไม่เจอ"
        return false
    end
    if not moveTo(spot) then return false end
    if tool.Parent ~= LocalPlayer.Character then -- เผื่อหลุดมือระหว่างทาง
        hum:EquipTool(tool)
        task.wait(0.3)
    end
    local before = #myCrops()
    status = "ปลูกข้าว..."
    actionDone = false
    local box = fire("UseRice")
    -- ต้นใหม่โผล่ในแปลง = ปลูกสำเร็จ ไปต่อเลยไม่ต้องรอท่าจบ
    waitFor(Config.AnimationTimeout or 12, function()
        return #myCrops() > before or (box.done and (not box.res.ok or not busy()))
    end)
    if #myCrops() <= before then
        status = "ปลูกไม่สำเร็จ: " .. tostring(box.res and box.res.message or "หมดเวลา")
        return false
    end
    actionDone = true
    unfreeze()
    auto.planted += 1
    status = "ปลูกแล้ว เหลือข้าว " .. #riceTools() .. " ต้น"
    return true
end

---------------------------------------------------------------- เก็บ
local function harvest(crop)
    local hrp = getRoot()
    if not hrp then return false end
    if (hrp.Position - crop.part.Position).Magnitude > (Config.HarvestDistance or 7) - 2 then
        if not moveTo(crop.part.Position, 3) then return false end
    end
    status = "เก็บข้าว..."
    local startedAt = os.clock()
    actionDone = false
    local box = fire("UseRice", crop.model)
    -- ได้เงินแล้ว (แจ้งเตือน "เก็บข้าวสำเร็จ") หรือต้นหายไป = เสร็จ ไปต้นต่อไปเลย
    local function got()
        return not crop.model.Parent
            or (notify.at >= startedAt and notify.text:find("สำเร็จ", 1, true) ~= nil)
    end
    waitFor(Config.AnimationTimeout or 12, function()
        return got() or (box.done and (not box.res.ok or not busy()))
    end)
    if not got() then
        status = "เก็บไม่สำเร็จ: " .. tostring(box.res and box.res.message or "หมดเวลา")
        return false
    end
    actionDone = true
    unfreeze()
    auto.harvested += 1
    status = "เก็บแล้ว"
    return true
end

---------------------------------------------------------------- เร่งท่าปลูก/ก้มเก็บ
-- ท่าก้ม (Config.AnimationId) เล่นบนตัวเรา: ตอนเปิดออโต้ให้เล่นเร็ว 5 เท่า
-- ถ้าเซิร์ฟเวอร์จับเวลาเอง (RiceActionBusy ยังค้าง) ก็จะไม่เร็วขึ้น แค่ท่าดูเร็ว
local ANIM_ID = tostring(Config.AnimationId):match("%d+")
local ANIM_SPEED = 5
local animConn
local function hookAnimator(char)
    if animConn then animConn:Disconnect() animConn = nil end
    local hum = char and char:WaitForChild("Humanoid", 10)
    local animator = hum and hum:WaitForChild("Animator", 10)
    if not animator then return end
    animConn = animator.AnimationPlayed:Connect(function(track)
        local id = track.Animation and track.Animation.AnimationId:match("%d+")
        if auto.on and id == ANIM_ID then
            track:AdjustSpeed(ANIM_SPEED)
        end
    end)
end
task.spawn(hookAnimator, LocalPlayer.Character)
local charConn = LocalPlayer.CharacterAdded:Connect(hookAnimator)
task.spawn(function()
    while alive() do task.wait(1) end
    charConn:Disconnect()
    if animConn then animConn:Disconnect() end
end)

---------------------------------------------------------------- วนอัตโนมัติ
local function autoLoop()
    while alive() and auto.on do
        if busy() and not actionDone then
            task.wait(0.2)
        else
            local crops = myCrops()
            local ready
            for _, c in ipairs(crops) do
                if c.ready then ready = c break end
            end
            -- ปลูกให้หมดก่อน แล้วค่อยไล่เก็บ
            -- มีข้าว (ในมือ/ช่องลัด หรือยังค้างในกระเป๋าเกม) ปลูกก่อนเสมอ ไม่ยืนรอข้าวโตทั้งที่มีข้าว
            if #riceTools() > 0 or ensureRiceTool() then
                if not plantOne() then task.wait(busy() and 0.2 or 1) end
            elseif ready then
                if not harvest(ready) then task.wait(busy() and 0.2 or 1) end
            elseif #crops == 0 then
                -- ปลูก/เก็บหมดแล้ว: ไปหาลุงหมา รับเงิน/รับข้าวรอบใหม่
                if not talk() then task.wait(3) end
                task.wait(1)
            else
                local soon = math.huge
                for _, c in ipairs(crops) do soon = math.min(soon, c.left) end
                status = ("รอข้าวโต %d ต้น (ต้นแรกอีก %d วิ)"):format(#crops, math.ceil(soon))
                task.wait(1)
            end
        end
        task.wait(0.2)
    end
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
        warn("[RiceJob] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.RiceFluent then
        pcall(function() env.RiceFluent:Destroy() end)
    end
    env.RiceFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "ปลูกข้าว",
        SubTitle = "ลุงหมา",
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

local section = Tabs.main:AddSection("ปลูกข้าว")
section:AddToggle("RiceAuto", {
    Title = "ปลูกข้าวอัตโนมัติ",
    Description = "รับข้าวจากลุงหมา -> ปลูกในแปลงจนหมด -> รอโตแล้วเก็บ -> รับรอบใหม่ วนไปเรื่อยๆ",
    Default = false,
}):OnChanged(function(v)
    auto.on = v
    if v then task.spawn(autoLoop) end
end)
section:AddDropdown("RiceMove", {
    Title = "วิธีไป",
    Description = "เดิน = ช้ากว่าแต่ปลอดภัย (กันโดนแบน) • วาร์ป = เร็ว",
    Values = { "เดิน", "วาร์ป" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    auto.walk = v ~= "วาร์ป"
end)
local statusPara = section:AddParagraph({ Title = "สถานะ", Content = status })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            local crops = myCrops()
            local ready = 0
            for _, c in ipairs(crops) do
                if c.ready then ready += 1 end
            end
            statusPara:SetDesc(("%s\nข้าวในกระเป๋า: %d  •  ต้นในแปลง: %d (พร้อมเก็บ %d)\nปลูกไปแล้ว %d  •  เก็บไปแล้ว %d"):format(
                status, #riceTools(), #crops, ready, auto.planted, auto.harvested))
        end)
        task.wait(0.5)
    end
    if alive() then env.RiceRun += 1 end
end)
