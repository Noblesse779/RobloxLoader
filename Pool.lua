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
    Vector2.new(0, -3.481), Vector2.new(0, 3.481), -- หลุมกลาง
}
-- ปากหลุม: ปลายขอบยางสองข้างของแต่ละหลุม (วัดจากภาพโต๊ะ) ลูกต้องผ่านระหว่างสองจุดนี้
-- ไม่งั้นชนปากหลุมเด้งออก (ลูกที่อยู่ใกล้หลุมแต่มุมเฉียง)
local CORNER_JAW, SIDE_JAW = 0.58, 0.55
local JAWS = {}
for i, p in ipairs(POCKETS) do
    local sx, sy = math.sign(p.X), math.sign(p.Y)
    if i <= 4 then
        JAWS[i] = { Vector2.new(sx * (RAIL_X - CORNER_JAW), sy * RAIL_Y), Vector2.new(sx * RAIL_X, sy * (RAIL_Y - CORNER_JAW)) }
    else
        JAWS[i] = { Vector2.new(-SIDE_JAW, sy * RAIL_Y), Vector2.new(SIDE_JAW, sy * RAIL_Y) }
    end
end
-- จุดเล็งในหลุม: กลางหลุม หรือเยื้องไปทางปากข้างใดข้างหนึ่ง (ให้เลี่ยงปากหลุมได้)
local function pocketTargets(i)
    local c, j = POCKETS[i], JAWS[i]
    return { c, c + (j[1] - c) * 0.3, c + (j[2] - c) * 0.3 }
end

local settings = {
    auto = false,
    group = "อัตโนมัติ",
    powerScale = 1,
    banks = true, -- ให้ลูกเป้าเด้งขอบลงหลุม
    kicks = true, -- ให้ลูกขาวเด้งขอบไปชน
    bounce = 0.85, -- ขอบเด้งกลับกี่ส่วน (แรงตั้งฉากกับขอบ)
    spinX = 0, -- สปินซ้าย/ขวา
    spinY = 0, -- สปินบน (ตาม) / ล่าง (ดึงกลับ)
    breakSpin = 0.7, -- สปินบนตอนเปิดเกม
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

-- เส้นทางจาก s ไป q: ตรง หรือเด้งขอบ 1 ครั้ง (ขอบ 4 ด้าน)
-- ขอบไม่เด้งเต็มที่: แรงตั้งฉากกับขอบเหลือ e เท่า -> จุดเป้า "ในกระจก" อยู่ลึก c/e
local CX, CY = RAIL_X - BALL_R, RAIL_Y - BALL_R -- เส้นที่จุดศูนย์กลางลูกแตะขอบ
local RAILS = {
    { axis = "Y", at = CY }, { axis = "Y", at = -CY },
    { axis = "X", at = CX }, { axis = "X", at = -CX },
}
local function routes(s, q, allowBank)
    local list = { { first = q - s, last = q - s, len = (q - s).Magnitude, banks = 0, segs = { { s, q } } } }
    if not allowBank then return list end
    local e = settings.bounce
    for _, r in ipairs(RAILS) do
        local sv = r.axis == "Y" and s.Y or s.X
        local qv = r.axis == "Y" and q.Y or q.X
        local a, c = math.abs(r.at - sv), math.abs(r.at - qv)
        -- q ต้องอยู่ฝั่งในโต๊ะเหมือน s (หลุมที่อยู่บนขอบนี้เด้งเข้าไม่ได้)
        if a > 0.05 and c > 0.2 and (r.at - sv) * (r.at - qv) > 0 then
            local t = a / (a + c / e)
            local bounce
            if r.axis == "Y" then
                bounce = Vector2.new(s.X + (q.X - s.X) * t, r.at)
            else
                bounce = Vector2.new(r.at, s.Y + (q.Y - s.Y) * t)
            end
            -- จุดเด้งต้องอยู่บนขอบ ไม่ใช่ปากหลุม
            local okBounce
            if r.axis == "Y" then
                okBounce = math.abs(bounce.X) < CX - 0.5 and math.abs(bounce.X) > 0.6
            else
                okBounce = math.abs(bounce.Y) < CY - 0.5
            end
            if okBounce then
                table.insert(list, {
                    first = bounce - s, last = q - bounce,
                    len = (bounce - s).Magnitude + (q - bounce).Magnitude / e,
                    banks = 1, segs = { { s, bounce }, { bounce, q } },
                })
            end
        end
    end
    return list
end

local function routeClear(route, balls, skip)
    for _, seg in ipairs(route.segs) do
        if not pathClear(seg[1], seg[2], balls, skip) then return false end
    end
    return true
end

-- ลูกขาวหลังชน (ไม่มีสปิน) วิ่งตามเส้นสัมผัส ถ้าเส้นนั้นพุ่งเข้าหลุม = เสี่ยงลูกขาวลง
local function scratchRisk(ghost, arrive, objDir)
    local d = arrive.Unit
    local tangent = d - objDir * d:Dot(objDir)
    local dir, reach
    if tangent.Magnitude < 0.15 then
        dir, reach = objDir, 1.5 -- ตรงๆ ลูกขาวไหลตามไปนิดหน่อย
    else
        dir, reach = tangent.Unit, 5
    end
    for _, pocket in ipairs(POCKETS) do
        local rel = pocket - ghost
        local along = rel:Dot(dir)
        if along > 0 and along < reach and (rel - dir * along).Magnitude < 0.45 then
            return true
        end
    end
    return false
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
            -- สูตรเปิด: ชนลูกหัวกองเต็มๆ แรงสุด + สปินบน (ลูกขาวตามเข้ากองต่อ กระจายดี ลูกลงบ่อย)
            return { angle = math.atan2(d.Y, d.X), power = 1, spin = Vector2.new(0, settings.breakSpin) },
                "เปิดเกม (ชนหัวกอง สปินบน)"
        end
    end

    local legal = legalIds(balls)
    local best, bestScore, bestText
    for _, b in ipairs(balls) do
        if legal[b.id] then
            local skip = { [0] = true, [b.id] = true }
            for pi = 1, #POCKETS do
              for _, pocket in ipairs(pocketTargets(pi)) do
                for _, ballRoute in ipairs(routes(b.p, pocket, settings.banks)) do
                    local dir = ballRoute.first.Unit
                    -- เส้นสุดท้ายเข้าหลุมต้องไม่เฉียดปากหลุม
                    local lastSeg = ballRoute.segs[#ballRoute.segs]
                    -- ลูกจ่อปากหลุมอยู่แล้ว ไม่ต้องเช็ค
                    local okSide = true
                    if (b.p - POCKETS[pi]).Magnitude > 0.7 then
                    for _, jaw in ipairs(JAWS[pi]) do
                        if segDist(jaw, lastSeg[1], lastSeg[2]) < BALL_R + 0.04 then okSide = false end
                    end
                    end
                    local ghost = b.p - dir * (BALL_R * 2)
                    if okSide and insideTable(ghost) and routeClear(ballRoute, balls, skip) then
                        for _, cueRoute in ipairs(routes(cue.p, ghost, settings.kicks)) do
                            if cueRoute.len > 0.01 then
                                local arrive = cueRoute.last.Unit
                                local cut = arrive:Dot(dir) -- 1 = ตรง, 0 = เฉียด 90 องศา
                                if cut > 0.26 and routeClear(cueRoute, balls, skip) then
                                    local banks = ballRoute.banks + cueRoute.banks
                                    local scratch = scratchRisk(ghost, cueRoute.last, dir)
                                    local score = cueRoute.len + ballRoute.len + (1 - cut) * 12
                                        + banks * 4 + (scratch and 8 or 0)
                                    if not bestScore or score < bestScore then
                                        bestScore = score
                                        best = {
                                            angle = math.atan2(cueRoute.first.Y, cueRoute.first.X),
                                            power = powerFor(cueRoute.len + ballRoute.len / math.max(cut, 0.4)),
                                        }
                                        local kind = (ballRoute.banks > 0 and "เด้งขอบลงหลุม" or "")
                                            .. (cueRoute.banks > 0 and " ลูกขาวเด้งขอบ" or "")
                                        bestText = ("ลูก %d -> หลุม %d (เฉียง %d°)%s%s"):format(b.id, pi,
                                            math.deg(math.acos(math.clamp(cut, -1, 1))),
                                            kind ~= "" and " " .. kind or "",
                                            scratch and " เสี่ยงลูกขาวลง" or "")
                                    end
                                end
                            end
                        end
                    end
                end
              end
            end
        end
    end
    if best then return best, bestText end

    -- ไม่มีทางลงหลุม: ตีให้โดนลูกฝั่งเรา (ตรง หรือเด้งขอบ) กันฟาวล์
    local near, nearScore
    for _, b in ipairs(balls) do
        if legal[b.id] then
            for _, r in ipairs(routes(cue.p, b.p, true)) do
                if routeClear(r, balls, { [0] = true, [b.id] = true }) then
                    local score = r.len + r.banks * 3
                    if not nearScore or score < nearScore then
                        near, nearScore = { route = r, id = b.id }, score
                    end
                end
            end
        end
    end
    if near then
        local r = near.route
        return { angle = math.atan2(r.first.Y, r.first.X), power = powerFor(r.len + 3) },
            ("ไม่มีทางลง: ตีโดนลูก %d%s"):format(near.id, r.banks > 0 and " (เด้งขอบ)" or "")
    end
    return nil, "ไม่มีทางตีโดนลูกฝั่งเรา"
end

local function shoot()
    if not state then
        status = "ยังไม่ได้รับข้อมูลโต๊ะ (นั่งโต๊ะแล้วรอตาเรา)"
        return false
    end
    if state.hand and not state.breakShot then
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
        spin = shot.spin or Vector2.new(settings.spinX, settings.spinY),
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

-- ปุ่มเดียว: เปิดแล้วแทงเองทุกตาเรา (เปิดเกม/ตรง/เด้งขอบ/กันลูกขาวลง ใช้ค่าตั้งใน settings ข้างบน)
local shotSection = Tabs.main:AddSection("แทง")
shotSection:AddToggle("PoolAuto", {
    Title = "แทงอัตโนมัติ",
    Description = "ถึงตาเราแทงเองจนจบเกม",
    Default = false,
}):OnChanged(function(v)
    settings.auto = v
end)
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
