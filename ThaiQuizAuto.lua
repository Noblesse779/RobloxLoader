-- Thai Quiz Auto Answer: Place 121878558222387
-- Dictionary-based; server validation remains authoritative.
-- Start before a new round. Time Attack is not supported.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
if game.PlaceId ~= 121878558222387 then
    warn("[ThaiQuizAuto] Wrong place")
    return
end

local player = Players.LocalPlayer
if not player then error("Run on the client") end
local key = "__ThaiQuizAutoRunning"
if player:GetAttribute(key) then
    warn("[ThaiQuizAuto] Already running; rejoin to restart")
    return
end

local R = RS:WaitForChild("Remotes", 15)
if not R then error("Remotes not found") end
local input = R:WaitForChild("MatchInput", 10)
local match = R:WaitForChild("Match", 10)
local solo = R:WaitForChild("Solo", 10)
if not input or not match or not solo then error("Required remotes missing") end

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

-- Keep the original client's answer cache consistent with its later flush.
-- Optional executor APIs vary; report if they are unavailable.
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

local letter
local categories = {}
local generation = 0
local connections = {}
local warnedCache = false

local function cancel()
    generation = generation + 1
end

local function answer()
    cancel()
    local token = generation
    local roundLetter = letter
    local roundCategories = categories
    task.spawn(function()
        task.wait(0.4)
        if generation ~= token then return end
        local state = discoverState()
        if not state and not warnedCache then
            warnedCache = true
            warn("[ThaiQuizAuto] Client answer cache unavailable; the game may overwrite submitted answers")
        end

        for index, category in ipairs(roundCategories) do
            if generation ~= token then return end
            local id = type(category) == "table" and category.id or category
            local text = bank[id] and bank[id][roundLetter]
            if text then
                if state and state.letter == roundLetter and state.canType then
                    state.answers[index] = text
                end
                input:FireServer({
                    type = "answer",
                    cat = index,
                    text = text,
                })
                print("[ThaiQuizAuto]", id, text)
            else
                warn("[ThaiQuizAuto] No dictionary entry:", id, roundLetter)
            end
            task.wait(0.15)
        end
    end)
end

connections[#connections + 1] = match.OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    if data.type == "spin" then
        cancel()
        letter = data.letter
        categories = data.categories or {}
    elseif data.type == "answering" then
        answer()
    elseif data.type == "start" or data.type == "locked"
        or data.type == "pranked" or data.type == "podium" then
        cancel()
    end
end)

connections[#connections + 1] = solo.OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    cancel()
    if data.type == "roundStart" then
        letter = data.letter
        categories = data.categories or {}
        answer()
    end
end)

player:SetAttribute(key, true)
print("[ThaiQuizAuto] Ready. Start a new round. Manual Stop/Submit; no Time Attack.")
