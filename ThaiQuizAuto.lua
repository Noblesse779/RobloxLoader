-- ThaiQuizAuto UI | UI: WindUI by Footagesus (MIT)
-- https://github.com/Footagesus/WindUI
-- Dictionary-based answers; server decides validity. No Time Attack support.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
if game.PlaceId ~= 121878558222387 then
    warn("[ThaiQuizAuto] This script is for Place 121878558222387")
    return
end
local player = Players.LocalPlayer
if not player then error("Run on the client") end
local env = type(getgenv) == "function" and getgenv() or _G
local previous = env.__ThaiQuizAutoUI
if previous and type(previous.Destroy) == "function" then
    previous.Destroy()
elseif player:GetAttribute("__ThaiQuizAutoRunning") then
    warn("[ThaiQuizAuto] Rejoin once to stop the old non-UI script, then run this version")
    return
end

local R = RS:WaitForChild("Remotes", 15)
if not R then error("Remotes not found") end
local input = R:WaitForChild("MatchInput", 10)
local match = R:WaitForChild("Match", 10)
local solo = R:WaitForChild("Solo", 10)
if not input or not match or not solo then error("Required remotes missing") end

local okLibrary, WindUI = pcall(function()
    local code = game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua")
    local chunk, compileError = loadstring(code)
    if not chunk then error(compileError) end
    return chunk()
end)
if not okLibrary then
    error("[ThaiQuizAuto] Cannot load WindUI: " .. tostring(WindUI))
end

local words = {
    fruit = "กล้วย ขนุน เงาะ ชมพู่ แตงโม ทุเรียน น้อยหน่า มะม่วง ลำไย ส้ม องุ่น",
    vegetable = "กะหล่ำปลี ขิง คะน้า ตำลึง ถั่วฝักยาว บวบ ผักบุ้ง พริก มะเขือ หอม",
    thaifood = "แกงเขียวหวาน ข้าวผัด คอหมูย่าง ต้มยำกุ้ง น้ำพริก ปูผัดผงกะหรี่ ผัดไทย ส้มตำ",
    drink = "กาแฟ โกโก้ ชาแดง ชานม น้ำเปล่า นม โอเลี้ยง",
    thaidessert = "กล้วยบวชชี ขนมชั้น ทองหยิบ บัวลอย ฝอยทอง ลอดช่อง สังขยา",
    snack = "เกี๊ยวทอด ข้าวเกรียบ คุกกี้ ป๊อปคอร์น มันฝรั่งทอด ลูกชิ้น",
    landanimal = "กระต่าย ควาย งู ช้าง ตุ๊กแก ม้า ยีราฟ ลิง วัว เสือ หมา อูฐ",
    wateranimal = "กุ้ง ฉลาม เต่า ปู แมงกะพรุน โลมา วาฬ หมึก",
    bird = "กา ไก่ กระจอก เขา เป็ด พิราบ แร้ง หงส์",
    insect = "จิ้งหรีด ตั๊กแตน ด้วง ผีเสื้อ ผึ้ง มด แมลงวัน ยุง",
    flower = "กุหลาบ กล้วยไม้ จำปี ชบา ดาวเรือง ทานตะวัน บัว มะลิ",
    tree = "กระถิน ขนุน จามจุรี ตาล ไทร ประดู่ มะขาม ยาง สัก",
    province = "กระบี่ ขอนแก่น ชลบุรี เชียงใหม่ ตรัง ตาก น่าน บุรีรัมย์ ปัตตานี พังงา ยะลา ระนอง ลำปาง เลย สตูล",
    country = "กัมพูชา จีน ญี่ปุ่น ชิลี เดนมาร์ก ไทย เนปาล บราซิล เปรู พม่า มาเลเซีย รัสเซีย ลาว เวียดนาม สิงคโปร์ อินเดีย",
    cityplace = "คาเฟ่ ตลาด ธนาคาร โรงเรียน โรงพยาบาล วัด สนามบิน ห้าง",
    worldcity = "กรุงเทพมหานคร โตเกียว ปารีส มาดริด โรม ลอนดอน เวนิส โซล",
    thaitravel = "เกาะช้าง เขาใหญ่ ดอยสุเทพ ภูกระดึง วัดอรุณ อัมพวา",
    job = "ครู จิตรกร ชาวนา ตำรวจ ทหาร นักบิน พยาบาล แพทย์ วิศวกร",
    body = "กระดูก ขา คอ จมูก ตา นิ้ว ปาก ผม ฟัน มือ ลิ้น สมอง หู",
    family = "ตา ยาย ปู่ ย่า พ่อ แม่ พี่ น้อง ลุง ป้า น้า อา ลูก หลาน",
    folktale = "ไกรทอง ขุนแผน ซินเดอเรลลา พินอคคิโอ ราพันเซล สโนว์ไวท์ หนูน้อยหมวกแดง",
    sport = "กอล์ฟ คาราเต้ เทนนิส บาสเกตบอล แบดมินตัน ฟุตบอล มวย ว่ายน้ำ",
    house = "กระจก เก้าอี้ จาน ช้อน โต๊ะ ถ้วย ผ้าห่ม หมอน",
    school = "กระดาน กรรไกร ชอล์ก ดินสอ โต๊ะเรียน ปากกา ไม้บรรทัด ยางลบ สมุด หนังสือ",
    clothes = "กางเกง กระโปรง ถุงเท้า ผ้าพันคอ รองเท้า เสื้อ หมวก",
    vehicle = "จักรยาน ตุ๊กตุ๊ก เครื่องบิน รถยนต์ เรือ",
    appliance = "กาต้มน้ำ เครื่องซักผ้า ตู้เย็น เตารีด โทรทัศน์ พัดลม หม้อหุงข้าว",
    instrument = "กีตาร์ ขลุ่ย ฆ้อง ฉิ่ง ซอ ดับเบิลเบส เปียโน ระนาด ไวโอลิน",
    color = "ขาว เขียว คราม ชมพู ดำ แดง เทา น้ำเงิน ฟ้า ม่วง ส้ม เหลือง",
    verb = "กิน เขียน คิด จำ เดิน ตี ถาม ทำ นอน บิน ไป พูด มา ยืน ร้อง ล้าง วิ่ง สอน หัวเราะ อ่าน",
    adjective = "กลม ขาว คม งาม ดี เตี้ย นุ่ม บาง เปรี้ยว ผอม แพง มืด ยาว ร้อน เล็ก สูง หอม อ้วน",
    subject = "คณิตศาสตร์ เคมี ชีววิทยา ดนตรี ประวัติศาสตร์ ภาษาไทย ฟิสิกส์ ศิลปะ สังคมศึกษา",
    festival = "คริสต์มาส ตรุษจีน ปีใหม่ ลอยกระทง สงกรานต์ ฮาโลวีน",
}

local function firstConsonant(text)
    for _, cp in utf8.codes(text) do
        if cp >= 0x0E01 and cp <= 0x0E2E then
            return utf8.char(cp)
        end
    end
end

local bank = {}
for category, list in pairs(words) do
    bank[category] = {}
    for word in list:gmatch("%S+") do
        local letter = firstConsonant(word)
        if letter and not bank[category][letter] then
            bank[category][letter] = word
        end
    end
end

local clientState
local function discoverState()
    if clientState then return clientState end
    if type(getconnections) ~= "function"
        or not debug or type(debug.getupvalues) ~= "function" then
        return nil
    end
    local ok, connections = pcall(getconnections, match.OnClientEvent)
    if not ok then return nil end
    for _, connection in pairs(connections) do
        local found, values = pcall(function()
            return debug.getupvalues(connection.Function)
        end)
        if found and type(values) == "table" then
            for _, value in pairs(values) do
                if type(value) == "table"
                    and type(value.answers) == "table"
                    and type(value.categories) == "table"
                    and type(value.active) == "number"
                    and type(value.canType) == "boolean" then
                    clientState = value
                    return value
                end
            end
        end
    end
    return nil
end

local enabled = false
local delaySeconds = 0.2
local generation = 0
local alive = true
local canAnswer = false
local letter
local categories = {}
local endsAt = 0
local mode = ""
local connections = {}
local entries = {}
local statusText = "พร้อมใช้งาน — เปิดตอบออโต้ก่อนเริ่มรอบ"
local resultText = "ยังไม่มีคำตอบ"
local cacheText = "รอตรวจเมื่อเริ่มรอบ"
local statusCard, roundCard, resultCard, logCard, cacheCard
local controller = {}
env.__ThaiQuizAutoUI = controller

local Window = WindUI:CreateWindow({
    Title = "ก–ฮ | ตอบอัตโนมัติ",
    Author = "Noblesse779 • WindUI",
    Folder = "ThaiQuizAutoUI",
    Size = UDim2.fromOffset(720, 490),
    MinSize = Vector2.new(560, 360),
    MaxSize = Vector2.new(1000, 760),
    Theme = "Dark",
    Transparent = true,
    Resizable = true,
    SideBarWidth = 185,
    HideSearchBar = true,
    ToggleKey = Enum.KeyCode.RightShift,
    OpenButton = {
        Title = "ก–ฮ เมนู",
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
    },
})
local Main = Window:Tab({ Title = "ตอบอัตโนมัติ", Icon = "bot" })
local Logs = Window:Tab({ Title = "คำตอบล่าสุด", Icon = "list" })
local Settings = Window:Tab({ Title = "ตั้งค่า", Icon = "settings" })

local function setDesc(card, text)
    if card and alive then
        pcall(function() card:SetDesc(text) end)
    end
end

local function setStatus(text)
    statusText = text
    setDesc(statusCard, text)
end

local function log(text)
    entries[#entries + 1] = text
    if #entries > 16 then table.remove(entries, 1) end
    setDesc(logCard, table.concat(entries, "\n"))
    print("[ThaiQuizAuto]", text)
end

local function updateRound()
    local names = {}
    for _, cat in ipairs(categories) do
        names[#names + 1] = type(cat) == "table"
            and (cat.name or cat.id or "?") or tostring(cat)
    end
    setDesc(roundCard, "ตัวอักษร: " .. tostring(letter or "—")
        .. "\nหมวด: " .. (#names > 0 and table.concat(names, " / ") or "รอเริ่มรอบ"))
end

local function cancel()
    generation = generation + 1
end

local function isOpen()
    return alive and canAnswer
        and (endsAt <= 0 or workspace:GetServerTimeNow() < endsAt)
end

local function answer()
    cancel()
    if not isOpen() then
        setStatus("รอช่วงตอบคำถามของรอบใหม่")
        return
    end
    local token = generation
    local roundLetter = letter
    local roundCategories = categories
    task.spawn(function()
        task.wait(0.4)
        if not alive or generation ~= token or not isOpen() then return end
        local state = discoverState()
        cacheText = state and "เชื่อมข้อมูลคำตอบในเกมแล้ว"
            or "เชื่อมข้อมูลในเกมไม่ได้ — เกมอาจเขียนทับคำตอบตอนจบรอบ"
        setDesc(cacheCard, cacheText)
        local lines = {}
        local sent = 0
        setStatus("กำลังส่งคำตอบ...")
        for index, cat in ipairs(roundCategories) do
            if not alive or generation ~= token or not isOpen() then return end
            local id = type(cat) == "table" and cat.id or cat
            local name = type(cat) == "table" and (cat.name or id) or id
            local text = bank[id] and bank[id][roundLetter]
            if text then
                if state and state.letter == roundLetter and state.canType then
                    state.answers[index] = text
                end
                local sentOK, sendError = pcall(function()
                    input:FireServer({ type = "answer", cat = index, text = text })
                end)
                if sentOK then
                    sent = sent + 1
                    lines[#lines + 1] = tostring(name) .. ": " .. text
                    log(tostring(name) .. " → " .. text)
                else
                    lines[#lines + 1] = tostring(name) .. ": ส่งไม่สำเร็จ"
                    log("ส่งไม่สำเร็จ: " .. tostring(sendError))
                end
            else
                lines[#lines + 1] = tostring(name) .. ": ไม่มีคำในคลัง"
                log("ไม่มีคำ: " .. tostring(name) .. " / " .. tostring(roundLetter))
            end
            resultText = table.concat(lines, "\n")
            setDesc(resultCard, resultText)
            task.wait(delaySeconds)
        end
        if alive and generation == token then
            setStatus(string.format("ส่งแล้ว %d/%d หมวด • กดหยุด/ส่งในเกมเมื่อพร้อม",
                sent, #roundCategories))
        end
    end)
end

statusCard = Main:Paragraph({ Title = "สถานะ", Desc = statusText })
roundCard = Main:Paragraph({ Title = "รอบปัจจุบัน", Desc = "รอเริ่มรอบ" })
Main:Toggle({
    Title = "ตอบคำถามอัตโนมัติ",
    Desc = "เลือกคำตามหมวดและตัวอักษรเมื่อเริ่มรอบ",
    Value = false,
    Callback = function(value)
        enabled = value == true
        cancel()
        if enabled then
            if isOpen() then answer()
            else setStatus("เปิดแล้ว — รอเริ่มรอบใหม่") end
        else
            setStatus("ปิดตอบอัตโนมัติแล้ว")
        end
    end,
})
Main:Button({
    Title = "ตอบรอบนี้หนึ่งครั้ง",
    Desc = "ใช้ได้เฉพาะช่วงที่กำลังตอบคำถาม",
    Icon = "send",
    Callback = answer,
})
cacheCard = Main:Paragraph({ Title = "การเชื่อมกับเกม", Desc = cacheText })
Main:Paragraph({
    Title = "วิธีใช้",
    Desc = "เปิดสวิตช์แล้วเข้าเล่น คำที่ไม่มีในคลังจะเว้นไว้ กดหยุด/ส่งเอง คำตอบยังต้องผ่านการตรวจของเกม ไม่รองรับ Time Attack",
})
resultCard = Logs:Paragraph({ Title = "คำตอบรอบล่าสุด", Desc = resultText })
logCard = Logs:Paragraph({ Title = "บันทึกการทำงาน", Desc = "ยังไม่มีรายการ" })
Logs:Button({
    Title = "ล้างบันทึก",
    Icon = "trash-2",
    Callback = function()
        entries = {}
        setDesc(logCard, "ล้างบันทึกแล้ว")
    end,
})
Settings:Slider({
    Title = "เว้นช่วงส่งคำตอบ (วินาที)",
    Step = 0.05,
    Value = { Min = 0.15, Max = 1.5, Default = 0.2 },
    Callback = function(value)
        delaySeconds = math.clamp(tonumber(value) or 0.2, 0.15, 1.5)
    end,
})
Settings:Toggle({
    Title = "พื้นหลังโปร่งแสง",
    Value = true,
    Callback = function(value)
        Window:ToggleTransparency(value)
    end,
})
Settings:Paragraph({
    Title = "ซ่อนและเปิดหน้าต่าง",
    Desc = "กด Right Shift หรือใช้ปุ่ม ก–ฮ เมนู เพื่อเปิดหน้าต่างอีกครั้ง",
})
Settings:Paragraph({
    Title = "เครดิตหน้าต่าง",
    Desc = "WindUI by Footagesus • MIT • github.com/Footagesus/WindUI",
})

function controller.Destroy()
    if not alive then return end
    alive = false
    enabled = false
    canAnswer = false
    cancel()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    player:SetAttribute("__ThaiQuizAutoRunning", nil)
    if env.__ThaiQuizAutoUI == controller then env.__ThaiQuizAutoUI = nil end
    pcall(function() Window:Destroy() end)
end
Settings:Button({
    Title = "หยุดสคริปต์และปิดหน้าต่าง",
    Icon = "power",
    Callback = controller.Destroy,
})
-- Minimizing only hides the UI. Destroying it stops all callbacks.
Window:OnDestroy(controller.Destroy)

local function readRound(data, roundMode)
    letter = data.letter
    categories = type(data.categories) == "table" and data.categories or {}
    endsAt = tonumber(data.endsAt) or 0
    mode = roundMode or mode
    resultText = "ยังไม่ได้ส่งคำตอบในรอบนี้"
    setDesc(resultCard, resultText)
    updateRound()
end

connections[#connections + 1] = match.OnClientEvent:Connect(function(data)
    if not alive or type(data) ~= "table" then return end
    if data.type == "spin" then
        cancel()
        canAnswer = false
        readRound(data, "table")
        setStatus("กำลังสุ่มตัวอักษร...")
    elseif data.type == "answering" then
        canAnswer = true
        endsAt = tonumber(data.endsAt) or endsAt
        setStatus("เริ่มช่วงตอบคำถาม")
        if enabled then answer() end
    elseif data.type == "stopped" then
        endsAt = tonumber(data.endsAt) or endsAt
    elseif data.type == "start" or data.type == "locked"
        or data.type == "pranked" or data.type == "podium" then
        cancel()
        canAnswer = false
        setStatus(data.type == "locked" and "จบรอบ — รอผลตรวจ"
            or "รอรอบถัดไป")
    end
end)

connections[#connections + 1] = solo.OnClientEvent:Connect(function(data)
    if not alive or type(data) ~= "table" then return end
    if data.type == "roundStart" then
        cancel()
        readRound(data, data.mode)
        canAnswer = true
        setStatus("เริ่มรอบเล่นคนเดียว")
        if enabled then answer() end
    elseif data.type == "roundEnd" or data.type == "roundResult" or data.type == "results"
        or data.type == "end" or data.type == "locked" then
        cancel()
        canAnswer = false
        setStatus("จบรอบ — รอรอบใหม่")
    end
end)

-- If loaded mid-round, recover only the local client's current round.
local current = discoverState()
if current and current.canType and type(current.categories) == "table"
    and #current.categories > 0 then
    letter = current.letter
    categories = current.categories
    endsAt = tonumber(current.endsAt) or 0
    mode = current.mode or ""
    canAnswer = true
    updateRound()
    setStatus("พบรอบที่กำลังเล่น — เปิดสวิตช์เพื่อเริ่มตอบ")
end
player:SetAttribute("__ThaiQuizAutoRunning", true)
log("เปิดหน้าต่างแล้ว — เปิดสวิตช์เพื่อใช้งาน")
return controller
