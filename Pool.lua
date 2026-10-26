-- โต๊ะพูล (เล่นกับบอทเท่านั้น): เล็ง + แทงอัตโนมัติ
-- เกมคำนวณลูกที่เซิร์ฟเวอร์ ส่งตำแหน่งลูกมาให้ทาง ReplicatedStorage.PoolSystem.Channel:
--   รับ "state" { tableId, round, revision, botThinking, breakShot, hand, balls = { {id, p = Vector2, down} } }
--   ส่ง "shot"  { tableId, spin = Vector2, power = 0..1, angle = เรเดียน, round }
-- พิกัดโต๊ะเป็น Vector2: ทิศแทง = (cos angle, sin angle), ลูกขาว = id 0
-- ขอบโต๊ะ (จุดที่ลูกแตะขอบ) x = ±7.0455, y = ±3.1555  หลุมมุม (±7.373, ±3.481)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
env.PoolRun = (env.PoolRun or 0) + 1
local RUN = env.PoolRun -- รันใหม่ = ลูปของตัวเก่าหยุดเอง
local function alive()
    return env.PoolRun == RUN
end

local BALL_R = 0.2 -- รัศมีลูก (ประมาณจากจุดชนที่ดักได้)
local RAIL_X, RAIL_Y = 7.0455, 3.1555
local POCKETS = {
    Vector2.new(-7.373, -3.481), Vector2.new(7.373, -3.481),
    Vector2.new(-7.373, 3.481), Vector2.new(7.373, 3.481),
    Vector2.new(0, -3.45), Vector2.new(0, 3.45), -- หลุมกลาง (กะเอา)
}

local settings = {
    auto = false,
    group = "อัตโนมัติ",
    powerScale = 1,
}
local status = "-"
local lastPlan = "-"

local channel = ReplicatedStorage:WaitForChild("PoolSystem"):WaitForChild("Channel")
local state, lastFxAt, shotRevision = nil, 0, nil

local conn = channel.OnClientEvent:Connect(function(kind, data)
    if kind == "state" and typeof(data) == "table" then
        state = data
    elseif kind == "fx" then
        lastFxAt = os.clock()
    end
end)
task.spawn(function()
    while alive() do task.wait(1) end
    conn:Disconnect()
end)

---------------------------------------------------------------- ลูกฝั่งเรา
local function myIndex()
    if typeof(state.names) ~= "table" then return nil end
    for i, n in ipairs(state.names) do
        if n == LocalPlayer.DisplayName or n == LocalPlayer.Name then return i end
    end
end

-- หาฝั่ง (ลูกเต็ม/ลูกลาย) จาก state ถ้าเกมส่งมา (ไม่รู้ชื่อช่องแน่ชัด ลองหลายแบบ)
local function groupFromState()
    local function norm(v)
        if typeof(v) ~= "string" then return nil end
        v = v:lower()
        if v:find("solid") or v:find("low") or v:find("เต็ม") then return "solid" end
        if v:find("stripe") or v:find("high") or v:find("ลาย") then return "stripe" end
    end
    local idx = myIndex()
    for k, v in pairs(state) do
        local key = tostring(k):lower()
        if key:find("group") or key:find("suit") or key:find("assign") then
            if typeof(v) == "table" then
                local g = idx and (norm(v[idx]) or norm(v[LocalPlayer.DisplayName]) or norm(v[LocalPlayer.Name]))
                if g then return g end
            else
                local g = norm(v)
                if g then return g end
            end
        end
    end
end

local function legalIds(balls)
    local group = settings.group == "ลูกเต็ม (1-7)" and "solid"
        or settings.group == "ลูกลาย (9-15)" and "stripe"
        or groupFromState()
    local ids, groupLeft = {}, 0
    for _, b in ipairs(balls) do
        local inGroup = (group == "solid" and b.id >= 1 and b.id <= 7)
            or (group == "stripe" and b.id >= 9)
            or (group == nil and b.id ~= 8)
        if b.id ~= 0 and b.id ~= 8 and inGroup then
            ids[b.id] = true
            groupLeft += 1
        end
    end
    if groupLeft == 0 then ids[8] = true end -- เคลียร์ฝั่งตัวเองหมดแล้ว ตีลูก 8
    return ids
end

---------------------------------------------------------------- คำนวณการแทง
-- ระยะจากจุด p ถึงเส้น a->b
local function segDist(p, a, b)
    local ab = b - a
    local len2 = ab:Dot(ab)
    if len2 < 1e-9 then return (p - a).Magnitude end
    local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
    return (p - (a + ab * t)).Magnitude
end

local function pathClear(a, b, balls, skip)
    for _, o in ipairs(balls) do
        if not skip[o.id] and segDist(o.p, a, b) < BALL_R * 2 - 0.01 then
            return false
        end
    end
    return true
end

local function insideTable(p)
    return math.abs(p.X) <= RAIL_X - BALL_R + 0.02 and math.abs(p.Y) <= RAIL_Y - BALL_R + 0.02
end

local function powerFor(dist)
    return math.clamp((0.3 + 0.045 * dist) * settings.powerScale, 0.2, 1)
end

local function planShot()
    local balls, cue = {}, nil
    for _, b in ipairs(state.balls or {}) do
        if not b.down and typeof(b.p) == "Vector2" then
            table.insert(balls, b)
            if b.id == 0 then cue = b end
        end
    end
    if not cue then return nil, "ไม่เจอลูกขาว" end

    -- เปิดเกม: ตีไปที่กองลูกแรงสุด
    if state.breakShot then
        local nearest, nd
        for _, b in ipairs(balls) do
            if b.id ~= 0 then
                local d = (b.p - cue.p).Magnitude
                if not nd or d < nd then nearest, nd = b, d end
            end
        end
        if nearest then
            local d = nearest.p - cue.p
            return { angle = math.atan2(d.Y, d.X), power = 1 }, "เปิดเกม"
        end
    end

    local legal = legalIds(balls)
    local best, bestScore, bestText
    for _, b in ipairs(balls) do
        if legal[b.id] then
            for pi, pocket in ipairs(POCKETS) do
                local toPocket = pocket - b.p
                local dir = toPocket.Unit
                -- หลุมกลางเข้าได้แค่มุมไม่เฉียงเกิน
                local okSide = pi <= 4 or math.abs(dir.Y) > 0.6
                local ghost = b.p - dir * (BALL_R * 2)
                local aim = ghost - cue.p
                if okSide and aim.Magnitude > 0.01 and insideTable(ghost) then
                    local cut = aim.Unit:Dot(dir) -- 1 = ตรง, 0 = เฉียด 90 องศา
                    if cut > 0.26 -- เฉียงไม่เกิน ~75 องศา
                        and pathClear(cue.p, ghost, balls, { [0] = true, [b.id] = true })
                        and pathClear(b.p, pocket, balls, { [0] = true, [b.id] = true }) then
                        local score = aim.Magnitude + toPocket.Magnitude + (1 - cut) * 12
                        if not bestScore or score < bestScore then
                            bestScore = score
                            best = {
                                angle = math.atan2(aim.Y, aim.X),
                                power = powerFor(aim.Magnitude + toPocket.Magnitude / math.max(cut, 0.4)),
                            }
                            bestText = ("ลูก %d -> หลุม %d (เฉียง %d°)"):format(b.id, pi, math.deg(math.acos(math.clamp(cut, -1, 1))))
                        end
                    end
                end
            end
        end
    end
    if best then return best, bestText end

    -- ไม่มีทางลงหลุม: ตีโดนลูกฝั่งเราลูกที่ใกล้สุดที่ทางโล่ง (กันฟาวล์)
    local near, nd
    for _, b in ipairs(balls) do
        if legal[b.id] then
            local d = (b.p - cue.p).Magnitude
            if pathClear(cue.p, b.p, balls, { [0] = true, [b.id] = true }) and (not nd or d < nd) then
                near, nd = b, d
            end
        end
    end
    if near then
        local d = near.p - cue.p
        return { angle = math.atan2(d.Y, d.X), power = powerFor(d.Magnitude + 3) }, ("ไม่มีทางลง: ตีโดนลูก %d"):format(near.id)
    end
    return nil, "ไม่มีทางตีโดนลูกฝั่งเรา"
end

local function shoot()
    if not state then
        status = "ยังไม่ได้รับข้อมูลโต๊ะ (นั่งโต๊ะแล้วรอตาเรา)"
        return false
    end
    if state.hand then
        status = "ลูกขาวอยู่ในมือ: วางลูกขาวเองก่อน"
        return false
    end
    local shot, text = planShot()
    lastPlan = text or "-"
    if not shot then
        status = text
        return false
    end
    channel:FireServer("shot", {
        tableId = state.tableId,
        spin = Vector2.new(0, 0),
        power = shot.power,
        angle = shot.angle,
        round = state.round,
    })
    shotRevision = state.revision
    status = ("แทงแล้ว: %s แรง %.2f"):format(text, shot.power)
    return true
end

-- แทงอัตโนมัติ: รอลูกหยุด (ไม่มี fx 1.5 วิ) + บอทไม่ได้คิดอยู่ + ยังไม่ได้แทงใน state นี้
task.spawn(function()
    while alive() do
        if settings.auto and state and not state.botThinking
            and state.revision ~= shotRevision and os.clock() - lastFxAt > 1.5 then
            task.wait(0.4)
            if settings.auto and state and not state.botThinking then
                shoot()
                shotRevision = state.revision -- ไม่สำเร็จก็ไม่ลองซ้ำใน state เดิม
            end
        end
        task.wait(0.3)
    end
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
local ok, Fluent = pcall(loadFluent, true)
if not ok or typeof(Fluent) ~= "table" then
    ok, Fluent = pcall(loadFluent, false)
end
if not ok or typeof(Fluent) ~= "table" then
    warn("[Pool] โหลดหน้าต่างไม่ได้: " .. tostring(Fluent))
    return
end

if env.PoolFluent then
    pcall(function() env.PoolFluent:Destroy() end)
end
env.PoolFluent = Fluent

local Window = Fluent:CreateWindow({
    Title = "โต๊ะพูล",
    SubTitle = "เล่นกับบอท",
    TabWidth = 150,
    Size = UDim2.fromOffset(540, 380),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.H,
})
local Tabs = {
    main = Window:AddTab({ Title = "หลัก", Icon = "home" }),
}

local shotSection = Tabs.main:AddSection("แทง")
shotSection:AddToggle("PoolAuto", {
    Title = "แทงอัตโนมัติ",
    Description = "ถึงตาเรา (ลูกหยุดแล้ว) จะเลือกลูกที่ลงง่ายสุดแล้วแทงเอง",
    Default = false,
}):OnChanged(function(v)
    settings.auto = v
end)
shotSection:AddButton({
    Title = "แทง 1 ครั้ง",
    Description = "คำนวณแล้วแทงตอนนี้เลย (กดตอนถึงตาเรา)",
    Callback = function()
        shoot()
    end,
})
shotSection:AddDropdown("PoolGroup", {
    Title = "ลูกฝั่งเรา",
    Values = { "อัตโนมัติ", "ลูกเต็ม (1-7)", "ลูกลาย (9-15)" },
    Multi = false,
    Default = 1,
}):OnChanged(function(v)
    settings.group = v
end)
shotSection:AddSlider("PoolPower", {
    Title = "คูณแรงแทง",
    Description = "ลูกไม่ถึงหลุม = เพิ่ม, แรงเกินจนลูกเด้งออก = ลด",
    Default = 1,
    Min = 0.5,
    Max = 1.8,
    Rounding = 2,
}):OnChanged(function(v)
    settings.powerScale = v
end)
shotSection:AddButton({
    Title = "คัดลอกข้อมูลโต๊ะล่าสุด",
    Description = "ส่งให้คนทำสคริปต์ดูตอนเลือกฝั่ง/ตาเล่นผิด",
    Callback = function()
        if not state then return end
        local parts = {}
        for k, v in pairs(state) do
            if k ~= "balls" then
                local s = typeof(v) == "table" and "{table}" or tostring(v)
                if typeof(v) == "table" then
                    local inner = {}
                    for k2, v2 in pairs(v) do table.insert(inner, tostring(k2) .. "=" .. tostring(v2)) end
                    s = "{" .. table.concat(inner, ", ") .. "}"
                end
                table.insert(parts, tostring(k) .. " = " .. s)
            end
        end
        local text = table.concat(parts, "\n")
        if typeof(setclipboard) == "function" then setclipboard(text) end
        print(text)
        Fluent:Notify({ Title = "คัดลอกแล้ว", Content = "ข้อมูลโต๊ะ", Duration = 4 })
    end,
})
local statusPara = shotSection:AddParagraph({ Title = "สถานะ", Content = status })

Window:SelectTab(1)

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        pcall(function()
            statusPara:SetDesc(("%s\nแผนล่าสุด: %s\nโต๊ะ: %s  •  บอทคิดอยู่: %s"):format(status, lastPlan,
                state and tostring(state.tableId) or "-",
                state and (state.botThinking and "ใช่" or "ไม่") or "-"))
        end)
        task.wait(0.5)
    end
    if alive() then env.PoolRun += 1 end
end)
