-- มินิเกม: บิงโก / อูโน่ (เล่นกับบอท) / ปาเป้าลูกโป่ง / สาวน้อยตกน้ำ / ตู้คีบ / เซียมซี / Truth or Dare
-- อ่านจากโค้ดเกม:
--   บิงโก (BingoSystem): นั่งที่โต๊ะใน BingoPlaza -> State { open, phase, round, board[4][4], marks[4][4], called, event }
--         กาเลข: Action:FireServer("Mark", round, แถว, คอลัมน์)  ออก: Action:FireServer("Leave")
--         รอบรางวัล (event) 13:00-13:30 / 20:01-20:30 เวลาไทย ผู้ชนะ 5,000 บาท (Config.EventWindows หน่วยนาที)
--   อูโน่ (UNOSystem): นั่งเก้าอี้ (PlayUNO) -> Action("Bot", จำนวน) เล่นกับบอท
--         State { phase, turn, you, winner, drawn, hand[{id,color}], playable[id] }
--         ลงไพ่: Action("Play", id[, สี])  จั่ว: Action("Draw")  ผ่าน: Action("Pass")
--   ปาเป้า/ตกน้ำ (TempleSystems.BalloonDarts / DunkTank): กดปุ่มเล่น -> State "Start" { Token }
--         Action("Charge", token) -> State "Charging" { Started } -> Action("Release", token, จุดเล็ง, เวลา)
--         แรง = ShotMath.Power(เวลาปล่อย - Started) ทิศ = (จุดเล็ง - จุดปา).Unit + ยกขึ้น 0.25
--         Effects "Throw" { Origin, Velocity } บอกจุดปาจริง (จำไว้ใช้ลูกถัดไป) เกมสุ่มเบี้ยวได้ (ตกน้ำ 30%)
--   ตู้คีบ (ClawMachineSystem): กด PlayClaw -> Open(ตู้, gui, ?, id) -> Input(ตู้, ทิศ, กด/ปล่อย, id) / Input(ตู้, "Drop", nil, id)
--         เกมสุ่มหลุดมือ 50% (Config.GripSlipChance)
-- ไม่ทำบอทพูล: พูลเล่นกับผู้เล่นจริง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.MinigameRun = (env.MinigameRun or 0) + 1
local RUN = env.MinigameRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.MinigameRun == RUN
end

local conns = {}
local function on(signal, fn)
    conns[#conns + 1] = signal:Connect(fn)
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function waitFor(timeout, check)
    local t = os.clock() + timeout
    while os.clock() < t do
        if check() then return true end
        task.wait(0.1)
    end
    return check()
end

local function human(a, b) -- หน่วงเหมือนคนกด
    task.wait(a + math.random() * (b - a))
end

-- วาร์ปไปใกล้ปุ่ม E แล้วกด
local function usePrompt(prompt)
    local hrp = getRoot()
    if not (prompt and hrp) then return false end
    local part = prompt.Parent
    if part and part:IsA("Attachment") then part = part.Parent end
    local pos = part and part:IsA("BasePart") and part.Position
    if not pos then return false end
    if (pos - hrp.Position).Magnitude > prompt.MaxActivationDistance - 1 then
        hrp.CFrame = CFrame.new(pos + Vector3.new(2, 3, 0), pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.4)
    end
    if typeof(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, prompt)
    end
    return false
end

local function findPrompts(root, name)
    local list = {}
    if not root then return list end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Name == name then list[#list + 1] = d end
    end
    return list
end

local function nearestPrompt(list)
    local hrp = getRoot()
    local best, bestD
    for _, p in ipairs(list) do
        local part = p.Parent
        if part and part:IsA("Attachment") then part = part.Parent end
        if part and part:IsA("BasePart") and p.Enabled then
            local d = hrp and (part.Position - hrp.Position).Magnitude or 0
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return best
end

---------------------------------------------------------------- บิงโก
local Bingo = ReplicatedStorage:FindFirstChild("BingoSystem")
local BingoConfig = Bingo and Bingo:FindFirstChild("Config") and require(Bingo.Config)
local bingo = { auto = false, always = false, state = nil, marked = {}, seated = false, info = "-" }

-- ตอนนี้อยู่ในรอบรางวัลไหม (เวลาไทย = UTC+7)
local function bingoWindow()
    local t = os.time() + 7 * 3600
    local minutes = math.floor(t / 60) % 1440
    for _, w in ipairs(BingoConfig and BingoConfig.EventWindows or {}) do
        if minutes >= w.Start and minutes < w.Finish then return true end
    end
    return false
end

local function bingoSeat()
    local plaza = workspace:FindFirstChild("BingoPlaza")
    local area = plaza and (plaza:FindFirstChild("03_TablesAndSeats") or plaza)
    local hrp = getRoot()
    local best, bestD
    for _, s in ipairs(area and area:GetDescendants() or {}) do
        if s:IsA("Seat") and not s.Occupant and not s.Disabled then
            local d = hrp and (s.Position - hrp.Position).Magnitude or 0
            if not bestD or d < bestD then best, bestD = s, d end
        end
    end
    return best
end

local function bingoMarkAll(st)
    if not (bingo.auto and st and st.open and st.phase == "RUNNING" and st.board and st.marks) then return end
    local called = {}
    for _, n in ipairs(st.called or {}) do called[n] = true end
    for r = 1, 4 do
        for c = 1, 4 do
            local n = st.board[r] and st.board[r][c]
            local key = tostring(st.round) .. ":" .. r .. ":" .. c
            if n and called[n] and not st.marks[r][c] and not bingo.marked[key] then
                bingo.marked[key] = true
                task.spawn(function()
                    human(0.15, 0.35) -- ใครกาครบแถวก่อนชนะ: กาเร็วเท่าคนกดไว
                    if bingo.state and bingo.state.round == st.round then
                        Bingo.Action:FireServer("Mark", st.round, r, c)
                    end
                end)
            end
        end
    end
end

if Bingo then
    on(Bingo:WaitForChild("State").OnClientEvent, function(st)
        if typeof(st) ~= "table" then return end
        bingo.state = st
        bingo.seated = st.open == true
        bingoMarkAll(st)
    end)
end

local function bingoLeave()
    if not Bingo then return end
    pcall(function() Bingo.Action:FireServer("Leave") end)
    local hum = getHum()
    if hum then hum.Sit = false; hum.Jump = true end
    bingo.seated = false
end

task.spawn(function()
    local busyMine = false
    while alive() do
        local want = Bingo and bingo.auto and (bingo.always or bingoWindow())
        -- รอบรางวัลบิงโก (5,000) คุ้มกว่าแอร์ดรอป: บอกแอร์ดรอปไม่ต้องลุกไป
        env.BingoActive = want and bingo.state ~= nil and bingo.state.event == true or nil
        if want then
            if not bingo.seated then
                local seat = bingoSeat()
                local hrp, hum = getRoot(), getHum()
                if seat and hrp and hum and hum.Health > 0 then
                    bingo.info = "ไปนั่งโต๊ะบิงโก..."
                    env.AirdropBusy = true -- งานอื่นพักระหว่างเล่น
                    busyMine = true
                    hrp.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.3)
                    pcall(function() seat:Sit(hum) end)
                    waitFor(5, function() return bingo.seated end)
                    if not bingo.seated then pcall(function() Bingo.Action:FireServer("Sync") end) end
                else
                    bingo.info = "ไม่มีที่นั่งว่างที่โต๊ะบิงโก"
                end
            else
                env.AirdropBusy = true
                busyMine = true
                local st = bingo.state or {}
                bingo.info = ("นั่งเล่นอยู่ • %s • รอบ %s • %s"):format(tostring(st.phase), tostring(st.round),
                    st.event and "รอบรางวัล 5,000" or "รอบเล่นฟรี")
                bingoMarkAll(st)
            end
        else
            if bingo.seated then bingoLeave() end
            if busyMine then
                env.AirdropBusy = false
                busyMine = false
            end
            bingo.info = bingo.auto and "รอรอบรางวัล 13:00-13:30 / 20:01-20:30" or "-"
        end
        task.wait(1)
    end
    if busyMine then env.AirdropBusy = false end
    env.BingoActive = nil
end)

---------------------------------------------------------------- อูโน่ (เล่นกับบอท)
local UNO = ReplicatedStorage:FindFirstChild("UNOSystem")
local uno = { auto = false, again = false, bots = 3, state = nil, acted = nil, info = "-" }

-- เลือกไพ่ให้มีโอกาสชนะมากสุด:
--   ไพ่โจมตี (+2 / ข้าม / กลับทาง) ก่อน แล้วเลขมาก (ทิ้งแต้มสูงก่อน) ชอบสีที่มีในมือเยอะ (ตาต่อไปลงต่อได้)
--   ไพ่เปลี่ยนสีเก็บไว้ใช้ตอนไม่มีอย่างอื่นให้ลง (เปลี่ยนสีธรรมดาก่อน +4) เลือกสีที่เหลือในมือมากสุด
local ACTION_SCORE = { draw2 = 30, skip = 25, reverse = 20 }
local function unoPick(st)
    local playable = {}
    for _, id in ipairs(st.playable or {}) do playable[id] = true end
    local colorCount = { red = 0, yellow = 0, green = 0, blue = 0 }
    for _, c in ipairs(st.hand or {}) do
        if colorCount[c.color] then colorCount[c.color] += 1 end
    end
    local best, bestScore
    for _, c in ipairs(st.hand or {}) do
        if playable[c.id] then
            local score
            if c.value == "wild4" then
                score = -20
            elseif c.color == "wild" then
                score = -10
            else
                score = (ACTION_SCORE[c.value] or tonumber(c.value) or 0) + (colorCount[c.color] or 0) * 3
            end
            -- เหลือไพ่ใบเดียวหลังลง: ลงอะไรก็ได้ที่ลงได้ ไม่ต้องเก็บไพ่เปลี่ยนสี
            if #st.hand <= 2 and c.color == "wild" then score = 100 end
            if not bestScore or score > bestScore then best, bestScore = c, score end
        end
    end
    if not best then return nil end
    local pickColor
    if best.color == "wild" then
        local top = -1
        for color, n in pairs(colorCount) do
            if n > top then pickColor, top = color, n end
        end
    end
    return best.id, pickColor
end

local function unoTurn(st)
    if not (uno.auto and UNO and st and st.phase == "playing" and st.turn == st.you and not st.winner) then return end
    local sig = tostring(st.roundId) .. ":" .. #(st.hand or {}) .. ":" .. tostring(st.drawn) .. ":" .. tostring(st.top and st.top.id)
    if uno.acted == sig then return end
    uno.acted = sig
    task.spawn(function()
        human(0.5, 1)
        local cur = uno.state
        if not (cur and cur.turn == cur.you and not cur.winner) then return end
        local id, color = unoPick(cur)
        if id then
            uno.info = "ลงไพ่"
            UNO.Action:FireServer("Play", id, color)
        elseif not cur.drawn then
            uno.info = "จั่ว"
            UNO.Action:FireServer("Draw")
        else
            uno.info = "ผ่านตา"
            UNO.Action:FireServer("Pass")
        end
    end)
end

if UNO then
    on(UNO:WaitForChild("State").OnClientEvent, function(st)
        if typeof(st) ~= "table" then return end
        uno.state = st
        unoTurn(st)
        if st.winner and uno.auto and uno.again then
            task.delay(6, function()
                if alive() and uno.auto and uno.again and uno.state == st then
                    UNO.Action:FireServer("Bot", uno.bots)
                end
            end)
        end
    end)
end

local function unoStart()
    if not UNO then return "แมพนี้ไม่มีอูโน่" end
    local free = {}
    for _, p in ipairs(findPrompts(workspace:FindFirstChild("UNOZone"), "PlayUNO")) do
        local seat = p.Parent
        if seat and seat:IsA("Seat") and not seat.Occupant then free[#free + 1] = p end
    end
    local prompt = nearestPrompt(free)
    if not prompt then return "ไม่มีเก้าอี้อูโน่ว่าง" end
    usePrompt(prompt)
    task.wait(1.5)
    UNO.Action:FireServer("Bot", uno.bots)
    return "นั่งแล้ว เล่นกับบอท " .. uno.bots .. " ตัว"
end

---------------------------------------------------------------- ปาเป้า / ตกน้ำ (คำนวณวิถี)
local Temple = ReplicatedStorage:FindFirstChild("TempleSystems")
local GRAVITY = 38

-- หามุมยิงให้ถึงเป้า: ลองแรงจากน้อยไปมาก เอาวิถีต่ำที่บินถึงทันเวลา
local function solveShot(math_, origin, target)
    local d = target - origin
    local flat = Vector3.new(d.X, 0, d.Z)
    local dx, dy = flat.Magnitude, d.Y
    if dx < 0.5 then return nil end
    for p = 0.3, 1.001, 0.02 do
        local s = math_.Speed(p)
        local disc = s ^ 4 - GRAVITY * (GRAVITY * dx * dx + 2 * dy * s * s)
        if disc >= 0 then
            local theta = math.atan((s * s - math.sqrt(disc)) / (GRAVITY * dx))
            local flight = dx / (s * math.cos(theta))
            if flight <= math_.MaxFlight then
                local u = flat.Unit * math.cos(theta) + Vector3.new(0, math.sin(theta), 0)
                -- เกมยกทิศขึ้น 0.25 ก่อนคูณแรง: หาทิศเล็ง a ที่ (a + 0.25y).Unit = u
                local lambda = 0.25 * u.Y + math.sqrt(0.0625 * u.Y * u.Y + 0.9375)
                local aimDir = (u * lambda - Vector3.new(0, 0.25, 0)).Unit
                return p, origin + aimDir * 20
            end
        end
    end
    return nil
end

local function makeThrower(name, folderName, speed, maxFlight, targetsOf)
    local sys = Temple and Temple:FindFirstChild(name)
    local t = { auto = false, token = nil, started = nil, origin = nil, waitingThrow = 0, info = "-", busy = false }
    if not sys then return t end
    local math_ = { Speed = speed, MaxFlight = maxFlight }

    local function throw()
        if t.busy or not t.token then return end
        t.busy = true
        local hrp = getRoot()
        local targets = targetsOf()
        local origin = t.origin or (hrp and hrp.Position + Vector3.new(0, 1.5, 0))
        local best, bestD
        for _, part in ipairs(targets) do
            local d = (part.Position - origin).Magnitude
            if not bestD or d < bestD then best, bestD = part, d end
        end
        if not (best and origin) then
            t.info = "หาเป้าไม่เจอ"
            t.busy = false
            return
        end
        local p, aimPos = solveShot(math_, origin, best.Position)
        if not p then
            t.info = "เป้าไกลเกินแรงสูงสุด"
            t.busy = false
            return
        end
        human(0.4, 0.9)
        t.started = nil
        sys.Action:FireServer("Charge", t.token)
        if not waitFor(3, function() return t.started ~= nil end) then
            t.info = "ชาร์จไม่ขึ้น"
            t.busy = false
            return
        end
        -- แรงขึ้นเป็นสามเหลี่ยม 0 -> 1 ใน 0.9 วิ: ปล่อยตอนแรงถึงที่คำนวณ
        local at = t.started + p * 0.9
        while workspace:GetServerTimeNow() < at do task.wait() end
        t.waitingThrow = os.clock()
        sys.Action:FireServer("Release", t.token, aimPos, workspace:GetServerTimeNow())
        t.info = ("ปาแรง %d%%"):format(math.floor(p * 100 + 0.5))
        task.wait(1)
        t.busy = false
    end

    on(sys:WaitForChild("State").OnClientEvent, function(kind, data)
        if kind == "Start" and typeof(data) == "table" then
            t.token, t.origin = data.Token, nil
        elseif kind == "Status" and typeof(data) == "table" and data.Token == t.token then
            if data.CanThrow and t.auto then task.spawn(throw) end
        elseif kind == "Charging" and typeof(data) == "table" and data.Token == t.token then
            t.started = data.Started
        elseif kind == "End" then
            t.token = nil
            t.info = typeof(data) == "table" and (tostring(data.Reason) .. " • ได้ " .. tostring(data.Score)) or "จบ"
        end
    end)
    on(sys:WaitForChild("Effects").OnClientEvent, function(kind, data)
        -- ลูกที่เพิ่งปา (ภายใน 1 วิ) = จุดปาจริงของเรา จำไว้ใช้ลูกถัดไป
        if kind == "Throw" and typeof(data) == "table" and os.clock() - t.waitingThrow < 1 and data.Origin then
            t.origin = data.Origin
            t.waitingThrow = 0
        end
    end)
    return t
end

local function partsNamed(root, words)
    local list = {}
    for _, d in ipairs(root and root:GetDescendants() or {}) do
        if d:IsA("BasePart") and d.Transparency < 1 then
            local n = string.lower(d.Name)
            for _, w in ipairs(words) do
                if n:find(w, 1, true) then list[#list + 1] = d break end
            end
        end
    end
    return list
end

local function nearestModel(list)
    local hrp = getRoot()
    local best, bestD
    for _, m in ipairs(list) do
        local d = hrp and (m:GetPivot().Position - hrp.Position).Magnitude or 0
        if not bestD or d < bestD then best, bestD = m, d end
    end
    return best
end

local templeWs = workspace:FindFirstChild("TempleSystems")
local darts = makeThrower("BalloonDarts", "BalloonDarts",
    function(p) return 16 + 25 * p ^ 1.35 end, 2.2,
    function()
        local folder = templeWs and templeWs:FindFirstChild("BalloonDarts")
        local booth = folder and nearestModel(folder:GetChildren())
        return partsNamed(booth, { "balloon" })
    end)
local dunk = makeThrower("DunkTank", "DunkTank",
    function(p) return 22 + 34 * p ^ 1.2 end, 3,
    function()
        local booth = templeWs and templeWs:FindFirstChild("สาวน้อยตกน้ำ_DunkTankBooth")
        local tanks = {}
        for _, c in ipairs(booth and booth:GetChildren() or {}) do
            if c.Name:find("Tank") then tanks[#tanks + 1] = c end
        end
        return partsNamed(nearestModel(tanks), { "target", "bullseye", "button", "trigger", "plate" })
    end)

---------------------------------------------------------------- ตู้คีบ
local Claw = ReplicatedStorage:FindFirstChild("ClawMachineSystem")
local claw = { auto = false, machine = nil, id = nil, info = "-", busy = false }

if Claw then
    on(Claw:WaitForChild("Open").OnClientEvent, function(machine, _, _, id)
        claw.machine, claw.id = machine, id
    end)
    on(Claw:WaitForChild("Close").OnClientEvent, function()
        claw.machine, claw.id = nil, nil
    end)
end

local function clawHead(machine)
    local housing = machine and machine:FindFirstChild("ClawHousing")
    return housing and housing:GetPivot().Position
end

local function clawPlay()
    if not Claw or claw.busy then return end
    local machine, id = claw.machine, claw.id
    if not machine then claw.info = "ยังไม่ได้เปิดตู้ (กดเล่นตู้คีบก่อน)" return end
    claw.busy = true
    local prizes = machine:FindFirstChild("Prizes")
    -- เรียนทิศ: กดขวา/ขึ้นสั้นๆ ดูว่าหัวคีบขยับไปทางไหน
    local function press(dir, secs)
        Claw.Input:FireServer(machine, dir, true, id)
        task.wait(secs)
        Claw.Input:FireServer(machine, dir, false, id)
        task.wait(0.15)
    end
    local a = clawHead(machine)
    press("Right", 0.25)
    local b = clawHead(machine)
    press("Up", 0.25)
    local c = clawHead(machine)
    if not (a and b and c) then claw.info = "หาหัวคีบไม่เจอ" claw.busy = false return end
    local right, up = (b - a) / 0.25, (c - b) / 0.25 -- ระยะต่อวิ
    local target, bestD
    for _, prize in ipairs(prizes and prizes:GetChildren() or {}) do
        local pos = prize:IsA("Model") and prize:GetPivot().Position or (prize:IsA("BasePart") and prize.Position)
        if pos then
            local d = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude
            if not bestD or d < bestD then target, bestD = pos, d end
        end
    end
    if not target or right.Magnitude < 0.01 or up.Magnitude < 0.01 then
        claw.info = "หาตุ๊กตาไม่เจอ / หัวคีบไม่ขยับ"
        claw.busy = false
        return
    end
    -- เลื่อนทีละแกนตามระยะที่ต้องไป (สองรอบให้แม่นขึ้น)
    for _ = 1, 2 do
        local head = clawHead(machine)
        local off = Vector3.new(target.X - head.X, 0, target.Z - head.Z)
        local rFlat = Vector3.new(right.X, 0, right.Z)
        local uFlat = Vector3.new(up.X, 0, up.Z)
        local sr = off:Dot(rFlat.Unit) / rFlat.Magnitude
        local su = off:Dot(uFlat.Unit) / uFlat.Magnitude
        if math.abs(sr) > 0.03 then press(sr > 0 and "Right" or "Left", math.min(math.abs(sr), 4)) end
        if math.abs(su) > 0.03 then press(su > 0 and "Up" or "Down", math.min(math.abs(su), 4)) end
    end
    human(0.2, 0.5)
    Claw.Input:FireServer(machine, "Drop", nil, id)
    claw.info = "ปล่อยคีบแล้ว (เกมสุ่มหลุดมือ 50%)"
    claw.busy = false
end

task.spawn(function()
    while alive() do
        if claw.auto and claw.machine and not claw.busy then
            task.wait(0.5)
            pcall(clawPlay)
            waitFor(15, function() return claw.machine == nil or not alive() end)
        end
        task.wait(0.5)
    end
end)

local function clawStart()
    local list = findPrompts(workspace:FindFirstChild("ClawMachineSystem"), "PlayClaw")
    local prompt = nearestPrompt(list)
    if not prompt then return "หาตู้คีบไม่เจอ" end
    usePrompt(prompt)
    return "กดเล่นตู้คีบแล้ว (500 บาท)"
end

---------------------------------------------------------------- เซียมซี / Truth or Dare
local function siamsi()
    local root = templeWs and templeWs:FindFirstChild("SiamSi")
    local shake = nearestPrompt(findPrompts(root, "ShakePrompt"))
    if not shake then return "หาเซียมซีไม่เจอ" end
    usePrompt(shake)
    task.wait(5)
    local read = nearestPrompt(findPrompts(root, "ReadPrompt"))
    if read then usePrompt(read) end
    return "เขย่าแล้วอ่านคำทำนายแล้ว"
end

local function truthOrDare()
    local prompt = nearestPrompt(findPrompts(workspace:FindFirstChild("TruthOrDareRig"), "TOD_Prompt"))
    if not prompt then return "หา Truth or Dare ไม่เจอ" end
    usePrompt(prompt)
    return "กดสุ่มแล้ว"
end

local function startBooth(rootName, promptName, label)
    local root = templeWs and templeWs:FindFirstChild(rootName)
    local prompt = nearestPrompt(findPrompts(root, promptName))
    if not prompt then return "หา" .. label .. "ไม่เจอ" end
    usePrompt(prompt)
    return "กดเล่น" .. label .. "แล้ว (100 บาท)"
end

task.spawn(function()
    while alive() do task.wait(1) end
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
        warn("[Minigames] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
        return
    end

    if env.MinigameFluent then
        pcall(function() env.MinigameFluent:Destroy() end)
    end
    env.MinigameFluent = Fluent

    Window = Fluent:CreateWindow({
        Title = "มินิเกม",
        SubTitle = "Minigames",
        TabWidth = 150,
        Size = UDim2.fromOffset(560, 420),
        Acrylic = false,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.H,
    })
    Tabs = {
        main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
    }
end

local function notify(msg)
    Fluent:Notify({ Title = "มินิเกม", Content = tostring(msg), Duration = 5 })
end

local bingoSection = Tabs.main:AddSection("บิงโก (รอบรางวัล ผู้ชนะ 5,000 บาท)")
bingoSection:AddToggle("MgBingo", {
    Title = "เล่นบิงโกเอง",
    Description = "ถึงรอบรางวัล 13:00-13:30 / 20:01-20:30 ไปนั่งโต๊ะ กาเลขที่ออกทันที (เร็วเท่าคนกดไว) หมดรอบแล้วลุกกลับไปทำงานต่อ",
    Default = false,
}):OnChanged(function(v)
    bingo.auto = v
end)
bingoSection:AddToggle("MgBingoAlways", {
    Title = "เล่นทุกรอบ (รวมรอบไม่มีรางวัล)",
    Default = false,
}):OnChanged(function(v)
    bingo.always = v
end)

local unoSection = Tabs.main:AddSection("อูโน่ (เล่นกับบอทของเกม)")
unoSection:AddToggle("MgUno", {
    Title = "เล่นอูโน่เอง",
    Description = "ลงไพ่โจมตีก่อน ทิ้งเลขมาก ชอบสีที่มีเยอะ เก็บไพ่เปลี่ยนสีไว้ท้าย ไม่มีให้ลง จั่ว/ผ่าน",
    Default = false,
}):OnChanged(function(v)
    uno.auto = v
    if v and uno.state then unoTurn(uno.state) end
end)
unoSection:AddToggle("MgUnoAgain", {
    Title = "จบเกมแล้วเล่นต่อกับบอท",
    Default = false,
}):OnChanged(function(v)
    uno.again = v
end)
unoSection:AddDropdown("MgUnoBots", {
    Title = "จำนวนบอท",
    Values = { "1", "2", "3" },
    Multi = false,
    Default = 3,
}):OnChanged(function(v)
    uno.bots = tonumber(v) or 3
end)
unoSection:AddButton({
    Title = "ไปนั่งโต๊ะว่างแล้วเริ่มกับบอท",
    Callback = function() task.spawn(function() notify(unoStart()) end) end,
})

local throwSection = Tabs.main:AddSection("ปาเป้าลูกโป่ง / สาวน้อยตกน้ำ (ตาละ 100 บาท)")
throwSection:AddToggle("MgDarts", {
    Title = "ปาเป้าลูกโป่งเอง",
    Description = "คำนวณวิถีลูกดอกเล็งลูกโป่งที่ใกล้สุด ลูกแรกกะจุดปาเอง ลูกต่อไปแม่นขึ้น",
    Default = false,
}):OnChanged(function(v)
    darts.auto = v
end)
throwSection:AddButton({
    Title = "กดเล่นปาเป้าลูกโป่ง",
    Callback = function() task.spawn(function() notify(startBooth("BalloonDarts", "PlayPrompt", "ปาเป้า")) end) end,
})
throwSection:AddToggle("MgDunk", {
    Title = "ปาสาวน้อยตกน้ำเอง",
    Description = "คำนวณวิถีลูกเทนนิสเล็งเป้าของถัง (เกมสุ่มเบี้ยว 30%)",
    Default = false,
}):OnChanged(function(v)
    dunk.auto = v
end)
throwSection:AddButton({
    Title = "กดเล่นสาวน้อยตกน้ำ",
    Callback = function() task.spawn(function() notify(startBooth("สาวน้อยตกน้ำ_DunkTankBooth", "PlayPrompt", "สาวน้อยตกน้ำ")) end) end,
})

local clawSection = Tabs.main:AddSection("ตู้คีบ (ตาละ 500 บาท)")
clawSection:AddToggle("MgClaw", {
    Title = "คีบเอง",
    Description = "เปิดตู้แล้ว เลื่อนหัวคีบไปเหนือตุ๊กตาที่ใกล้สุดแล้วปล่อย (เกมสุ่มหลุดมือ 50%)",
    Default = false,
}):OnChanged(function(v)
    claw.auto = v
end)
clawSection:AddButton({
    Title = "กดเล่นตู้คีบ",
    Callback = function() task.spawn(function() notify(clawStart()) end) end,
})

local freeSection = Tabs.main:AddSection("ฟรี")
freeSection:AddButton({
    Title = "เซียมซี (เขย่า + อ่านคำทำนาย)",
    Callback = function() task.spawn(function() notify(siamsi()) end) end,
})
freeSection:AddButton({
    Title = "Truth or Dare (สุ่ม)",
    Callback = function() task.spawn(function() notify(truthOrDare()) end) end,
})

local statusPara = Tabs.main:AddSection("สถานะ"):AddParagraph({ Title = "สถานะ", Content = "-" })

if Window then Window:SelectTab(1) end

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            statusPara:SetDesc(table.concat({
                "บิงโก: " .. bingo.info .. (bingoWindow() and " (ตอนนี้รอบรางวัล)" or ""),
                "อูโน่: " .. uno.info,
                "ปาเป้า: " .. darts.info,
                "ตกน้ำ: " .. dunk.info,
                "ตู้คีบ: " .. claw.info,
            }, "\n"))
        end)
        task.wait(1)
    end
    if alive() then env.MinigameRun += 1 end
end)
