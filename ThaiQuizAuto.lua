-- ThaiQuizAuto V4 | WindUI by Footagesus (MIT), native UI fallback
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
local legacyRunning=false
local previous = env.__ThaiQuizAutoUI
if previous and type(previous.Destroy) == "function" then
    previous.Destroy()
elseif player:GetAttribute("__ThaiQuizAutoRunning") then
    legacyRunning=true
    warn("[ThaiQuizAuto] Old non-UI script detected; rejoin once to avoid two responders")
end

local R = RS:WaitForChild("Remotes", 15)
if not R then error("Remotes not found") end
local input = R:WaitForChild("MatchInput", 10)
local match = R:WaitForChild("Match", 10)
local solo = R:WaitForChild("Solo", 10)
if not input or not match or not solo then error("Required remotes missing") end

-- Small local fallback if the shared UI library cannot load.
local UserInputService = game:GetService("UserInputService")
local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end
local shell = make("ScreenGui", {
    Name = "ThaiQuizAutoLauncherV3", ResetOnSpawn = false,
    IgnoreGuiInset = true, DisplayOrder = 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))
local launcher = make("TextButton", {
    Size = UDim2.fromOffset(180, 40), Position = UDim2.new(0, 18, 0.18, 0),
    Text = "ก–ฮ V4 • กำลังโหลด UI", TextSize = 15,
    Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(255,255,255),
    BackgroundColor3 = Color3.fromRGB(28, 38, 57), BorderSizePixel = 0,
}, shell)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, launcher)
local hint = make("TextLabel", {
    Position = UDim2.new(0, 18, 0.18, 44), Size = UDim2.fromOffset(340, 44),
    Text = "กำลังโหลดหน้าต่าง...", TextSize = 13, TextWrapped = true,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(255,255,255), BackgroundTransparency = 0.25,
    BackgroundColor3 = Color3.fromRGB(20,24,32), BorderSizePixel = 0,
}, shell)
local function nativeLibrary()
    local library = {}
    function library:CreateWindow(config)
        local W = { dead = false }
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            or Vector2.new(1000, 700)
        local width = math.min(720, viewport.X - 24)
        local height = math.min(490, viewport.Y - 72)
        local frame = make("Frame", {
            Size = UDim2.fromOffset(width,height), AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.fromScale(0.5,0.5), BackgroundColor3 = Color3.fromRGB(22,25,33),
            BackgroundTransparency = 0.12, BorderSizePixel = 0, Active = true,
        }, shell)
        make("UICorner", { CornerRadius=UDim.new(0,14) },frame)
        local title = make("TextLabel", {
            Size=UDim2.new(1,-65,0,44),Position=UDim2.fromOffset(18,0),
            Text=config.Title .. " • สำรอง",TextSize=17,Font=Enum.Font.GothamBold,
            TextColor3=Color3.fromRGB(255,255,255),TextXAlignment=Enum.TextXAlignment.Left,
            BackgroundTransparency=1,Active=true,
        },frame)
        local close = make("TextButton", {
            Position=UDim2.new(1,-45,0,7),Size=UDim2.fromOffset(34,30),Text="−",TextSize=24,
            TextColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,
        },frame)
        close.Activated:Connect(function() frame.Visible=false end)
        local sidebar=make("Frame",{Position=UDim2.fromOffset(10,52),Size=UDim2.new(0,145,1,-62),BackgroundTransparency=1},frame)
        make("UIListLayout",{Padding=UDim.new(0,8)},sidebar)
        local pages={}
        function W:Open() frame.Visible=true end
        function W:Toggle() frame.Visible=not frame.Visible end
        function W:ToggleTransparency(value) frame.BackgroundTransparency=value and 0.12 or 0 end
        function W:OnDestroy(fn) self.callback=fn end
        function W:Destroy()
            if self.dead then return end
            self.dead=true
            frame:Destroy()
            if self.callback then self.callback() end
        end
        function W:Tab(opts)
            local page=make("ScrollingFrame",{
                Position=UDim2.fromOffset(165,52),Size=UDim2.new(1,-177,1,-64),
                BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,
                AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Visible=#pages==0,
            },frame)
            make("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},page)
            pages[#pages+1]=page
            local tabButton=make("TextButton",{
                Size=UDim2.new(1,0,0,42),Text=opts.Title,TextSize=14,Font=Enum.Font.Gotham,
                TextColor3=Color3.fromRGB(240,240,245),BackgroundColor3=Color3.fromRGB(37,42,55),BorderSizePixel=0,
            },sidebar)
            make("UICorner",{CornerRadius=UDim.new(0,8)},tabButton)
            tabButton.Activated:Connect(function()for _,p in ipairs(pages)do p.Visible=p==page end end)
            local T={order=0}
            local function card(text)
                T.order=T.order+1
                local f=make("Frame",{Size=UDim2.new(1,-8,0,0),AutomaticSize=Enum.AutomaticSize.Y,
                    BackgroundColor3=Color3.fromRGB(37,42,55),BackgroundTransparency=0.12,
                    BorderSizePixel=0,LayoutOrder=T.order},page)
                make("UICorner",{CornerRadius=UDim.new(0,8)},f)
                make("UIPadding",{PaddingTop=UDim.new(0,12),PaddingBottom=UDim.new(0,12),PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,12)},f)
                local label=make("TextLabel",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
                    Text=text,TextSize=14,Font=Enum.Font.Gotham,TextWrapped=true,
                    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
                    TextColor3=Color3.fromRGB(235,238,245),BackgroundTransparency=1},f)
                return f,label
            end
            function T:Paragraph(o)
                local _,label=card(o.Title.."\n"..(o.Desc or ""))
                local item={title=o.Title}
                function item:SetDesc(s)label.Text=self.title.."\n"..s end
                return item
            end
            function T:Button(o)
                local f,label=card(o.Title..(o.Desc and "\n"..o.Desc or ""))
                local b=make("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=3},f)
                b.Activated:Connect(o.Callback)
                return {SetTitle=function(_,s)label.Text=s end}
            end
            function T:Toggle(o)
                local value=o.Value==true
                local f,label=card("")
                local function paint()label.Text=(value and "● เปิด  " or "○ ปิด  ")..o.Title..(o.Desc and "\n"..o.Desc or "")end
                paint()
                local b=make("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=3},f)
                local item={}
                function item:Set(v)value=v==true;paint();o.Callback(value)end
                b.Activated:Connect(function()item:Set(not value)end)
                return item
            end
            function T:Slider(o)
                local value=o.Value.Default
                local f,label=card(o.Title.."\n"..tostring(value))
                local item={}
                function item:Set(v)value=math.clamp(v,o.Value.Min,o.Value.Max);label.Text=o.Title.."\n"..string.format("%.2f  (แตะเพื่อปรับ)",value);o.Callback(value)end
                local b=make("TextButton",{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=3},f)
                b.Activated:Connect(function()local n=value+o.Step;if n>o.Value.Max then n=o.Value.Min end;item:Set(n)end)
                return item
            end
            return T
        end
        -- Native drag gesture, including touch.
        local dragging,origin,start
        local movement=UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
                local delta=i.Position-origin
                frame.Position=UDim2.new(start.X.Scale,start.X.Offset+delta.X,start.Y.Scale,start.Y.Offset+delta.Y)
            end
        end)
        title.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
                dragging=true;origin=i.Position;start=frame.Position
            end
        end)
        local ending=UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
        end)
        shell.Destroying:Connect(function()movement:Disconnect();ending:Disconnect()end)
        return W
    end
    return library
end

local WindUI
local nativeInUse=false
local completed=false
local libraryTask=task.spawn(function()
    local ok,result=pcall(function()
        local source=game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua")
        local chunk,err=loadstring(source)
        if not chunk then error(err) end
        return chunk()
    end)
    if ok and type(result)=="table" then WindUI=result end
    completed=true
end)
local deadline=os.clock()+8
while not completed and os.clock()<deadline do task.wait(0.1) end
if not completed then pcall(task.cancel,libraryTask) end
if not WindUI then
    nativeInUse=true
    WindUI=nativeLibrary()
    hint.Text="ใช้หน้าต่างสำรอง • โหลด WindUI ไม่สำเร็จ"
else
    -- Use PlayerGui so the window is not hidden in a protected UI container.
    pcall(function()WindUI:SetParent(player.PlayerGui)end)
    hint.Text="พร้อมใช้งาน • แตะปุ่มเพื่อเปิดเมนู"
end
launcher.Text="ก–ฮ V4 • เปิดเมนู"


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
            bank[category][letter] = {word}
        elseif letter then
            table.insert(bank[category][letter],word)
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

local function createWindow(ui)
return ui:CreateWindow({
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
end
local windowOK,Window,windowDone=false,nil,false
local windowTask=task.spawn(function()
    windowOK,Window=pcall(createWindow,WindUI)
    windowDone=true
end)
local windowDeadline=os.clock()+8
while not windowDone and os.clock()<windowDeadline do task.wait(0.1)end
if not windowDone then pcall(task.cancel,windowTask)end
if not windowOK then
    nativeInUse=true
    WindUI=nativeLibrary()
    Window=createWindow(WindUI)
    hint.Text="ใช้หน้าต่างสำรอง • WindUI สร้างหน้าต่างไม่สำเร็จ"
end
launcher.Activated:Connect(function()pcall(function()Window:Open()end)end)
pcall(function()Window:Open()end)
task.delay(7,function()if shell.Parent then hint.Visible=false end end)
connections[#connections+1]=UserInputService.InputBegan:Connect(function(i,processed)
    if nativeInUse and not processed and i.KeyCode==Enum.KeyCode.RightShift then pcall(function()Window:Toggle()end)end
end)
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

local answer
-- Derived data: VOLUBILIS by Belisan, CC BY-SA 4.0. See ThaiQuizData/v3/README.md.
local HttpService = game:GetService("HttpService")
local dataBase="https://raw.githubusercontent.com/Noblesse779/RobloxLoader/main/ThaiQuizData/v3/"
local vocabularyTotal=0
local vocabularyState="กำลังโหลดคลังคำ..."
local vocabularyCard
local sentByCategory={}
local validationCache={}
local requestRemote=R:FindFirstChild("Request")

local extra={
    country="เยเมน ยูกันดา เยอรมนี ยูเครน เยอรมัน สหรัฐอเมริกา สหราชอาณาจักร ออสเตรเลีย ออสเตรีย อาร์เจนตินา อิตาลี อิหร่าน อิรัก อิสราเอล อินโดนีเซีย ไอซ์แลนด์ ไอร์แลนด์ แคนาดา เกาหลีใต้ เกาหลีเหนือ กรีซ กานา กาตาร์ กินี คิวบา เคนยา โครเอเชีย จอร์แดน จาเมกา เช็ก ชาด ซาอุดีอาระเบีย ซีเรีย ซูดาน ซูรินาม เซเนกัล เซอร์เบีย แซมเบีย ตุรกี ตูนิเซีย ตองกา ทาจิกิสถาน แทนซาเนีย นอร์เวย์ นิวซีแลนด์ นามิเบีย ไนจีเรีย เนเธอร์แลนด์ บังกลาเทศ บาห์เรน เบลเยียม เบลารุส ปากีสถาน ปานามา โปรตุเกส โปแลนด์ ฝรั่งเศส ฟินแลนด์ ฟิลิปปินส์ เม็กซิโก โมร็อกโก มองโกเลีย มัลดีฟส์ รวันดา โรมาเนีย ลัตเวีย ลิทัวเนีย เลบานอน เวเนซุเอลา สเปน สวีเดน สวิตเซอร์แลนด์ สโลวาเกีย สโลวีเนีย หวานูอาตู ฮังการี เฮติ ฮอนดูรัส",
    worldcity="ย่างกุ้ง ยอกยาการ์ตา ยะโฮร์บาห์รู เยรูซาเลม เยเรวาน ยอนโกปิง กรุงเทพ กัวลาลัมเปอร์ กาฐมาณฑุ กวางโจว ขอนแก่น คุนหมิง โคเปนเฮเกน เคปทาวน์ แคนเบอร์รา ไคโร จาร์กาตา จาการ์ตา เจนีวา ชิคาโก เชียงใหม่ ซัปโปโร ซิดนีย์ ซูริก ดับลิน ดูไบ ดานัง เดลี โดฮา ตรัง ตูลูส เตหะราน ไทเป เทียนจิน เทลอาวีฟ นครปฐม นครราชสีมา นางาซากิ นาโกยา นิวยอร์ก นิวเดลี นีซ บางกอก บาร์เซโลนา บรัสเซลส์ บอสตัน บูดาเปสต์ เบอร์ลิน ปักกิ่ง ปราก ปารีส ปูซาน ปีนัง พนมเปญ พัทยา พอร์ตแลนด์ ฟลอเรนซ์ มอสโก มิลาน มุมไบ มะนิลา เมลเบิร์น มิวนิก รอตเทอร์ดาม ริโอเดจาเนโร ริยาด ลิสบอน ลียง ลิมา ลอสแอนเจลิส วอร์ซอ วอชิงตัน เวียนนา เวียงจันทน์ สตอกโฮล์ม สิงคโปร์ เสิ่นเจิ้น โซล หางโจว หาดใหญ่ ฮานอย ฮ่องกง ฮัมบูร์ก เฮลซิงกิ ออสโล อัมสเตอร์ดัม อังการา โอซากา",
    sport="ยิมนาสติก ยิงปืน ยิงธนู ยกน้ำหนัก ยูโด โยคะ โยธวาทิต กระโดดน้ำ กรีฑา กาบัดดี กังฟู ขี่ม้า ขว้างจักร คริกเก็ต เคนโด จานร่อน ชักเย่อ ซอฟต์บอล เซปักตะกร้อ ดำน้ำ ดาบสากล ตะกร้อ เทควันโด เทเบิลเทนนิส ทุ่มน้ำหนัก บิลเลียด เปตอง ปิงปอง โปโล พายเรือ ฟันดาบ มวยปล้ำ มาราธอน รักบี้ เรือใบ ลีลาศ วิ่ง วอลเลย์บอล วอลเลย์บอลชายหาด สเกตบอร์ด สกี สนุกเกอร์ หมากรุก หมากล้อม ฮอกกี้ แฮนด์บอล อเมริกันฟุตบอล",
    vehicle="บอลลูน บัลลูน บีทีเอส บิ๊กไบค์ บัส บั๊กกี้ รถบัส รถไฟ รถราง รถตู้ รถถัง รถเก๋ง รถกระบะ รถจักรยานยนต์ รถสามล้อ รถเมล์ รถไฟฟ้า เรือใบ เรือยนต์ เรือแจว เรือพาย เรือดำน้ำ เรือสำเภา เรือยอชต์ ยานยนต์ ยานอวกาศ ยานพาหนะ ยานบิน เครื่องร่อน เกวียน กระเช้า จรวด เจ็ตสกี แท็กซี่ มอเตอร์ไซค์ สกู๊ตเตอร์ สามล้อ สเกตบอร์ด เฮลิคอปเตอร์ โฮเวอร์คราฟต์ อากาศยาน",
    cityplace="บริษัท บ้านพัก บาร์ บ่อน บ่อน้ำพุ บึง บูธ บางลำพู กรมการขนส่ง กองบัญชาการ กระทรวง กองไปรษณีย์ เขต คลังสินค้า คุก คาเฟ่ คอนโด คลินิก โบสถ์ จวนผู้ว่าราชการจังหวัด จุดจอดรถ ชุมชน ซอย ซูเปอร์มาร์เก็ต ซูเปอร์เซ็นเตอร์ ด่านตรวจ ตลาดนัด ตึก ตู้ไปรษณีย์ ถนน ท่าเรือ ที่ว่าการอำเภอ ธนาคาร นิคมอุตสาหกรรม น้ำพุ ประตูเมือง ป้อมตำรวจ ปั๊มน้ำมัน ผับ แผงลอย พิพิธภัณฑ์ พาณิชย์จังหวัด มหาวิทยาลัย มัสยิด มูลนิธิ แยก ย่านการค้า โรงแรม โรงเรียน โรงหนัง โรงพยาบาล ร้านอาหาร ร้านกาแฟ ลานจอดรถ วัด วงเวียน ศาล ศาลากลางจังหวัด ศูนย์การค้า สถานีตำรวจ สถานีรถไฟ สวนสาธารณะ สนามบิน ห้างสรรพสินค้า ห้องสมุด หอพัก อนุสาวรีย์ อู่ซ่อมรถ ฮอลล์",
    family="ญาติ ยาย ย่า ยายทวด ย่าทวด ปู่ทวด ตาทวด บิดา บุตร บุตรสาว บุตรชาย สามี ภรรยา สะใภ้ เขย คู่สมรส พ่อเลี้ยง แม่เลี้ยง พี่สะใภ้ น้องเขย",
    vegetable="บวบ บรอกโคลี บีตรูต ใบย่านาง ย่านาง ยอดมะพร้าว ยอดฟักแม้ว ยอดกระถิน กะเพรา โหระพา กระชาย กระเทียม ข่า ขมิ้น ข้าวโพด คื่นฉ่าย คะน้า แครอต ชะอม ชะพลู ต้นหอม แตงกวา ถั่วงอก ถั่วพู ถั่วลันเตา น้ำเต้า ปวยเล้ง ผักกาด ผักชี ผักคะน้า เผือก พริกไทย ฟักทอง ฟักเขียว มะระ มะนาว มะกรูด มะรุม มันเทศ มันฝรั่ง สะตอ หน่อไม้ หัวไชเท้า หอมแดง อัญชัน",
    instrument="ขิม แคน จ้องหน่อง ฉาบ ซอด้วง ซออู้ ซอสามสาย ฆ้องวง กลอง กลองยาว กลองชุด กลองแขก ฆ้อง ระนาดเอก ระนาดทุ้ม จะเข้ ปี่ ปี่ชวา ปี่สก็อต เปียโน พิณ พิณน้ำเต้า กีตาร์ไฟฟ้า กีตาร์โปร่ง ทรัมเป็ต ทรอมโบน ทูบา โทน โทมบา บองโก เบส แมนโดลิน เมโลเดียน เมาท์ออร์แกน ยูโฟเนียม รีคอร์เดอร์ ลูท วิโอลา ไวโอลิน ไวโอลอนเชลโล ฮาร์ป ฮาร์โมนิกา ออร์แกน อูคูเลเล",
}
local seenCandidates={}
for cat,letters in pairs(bank)do
    seenCandidates[cat]={}
    for l,values in pairs(letters)do for _,word in ipairs(values)do seenCandidates[cat][word]=true end end
end
local function addCandidate(cat,word)
    word=word:gsub("%s+","")
    if utf8.len(word)>30 then return end
    for _,cp in utf8.codes(word)do if cp<0x0E01 or cp>0x0E5B then return end end
    local l=firstConsonant(word)
    if not l then return end
    bank[cat]=bank[cat] or {}
    seenCandidates[cat]=seenCandidates[cat] or {}
    if seenCandidates[cat][word] then return end
    seenCandidates[cat][word]=true
    bank[cat][l]=bank[cat][l] or {}
    table.insert(bank[cat][l],word)
end
for cat,list in pairs(extra)do
    for word in list:gmatch("%S+")do addCandidate(cat,word)end
end

-- Additional real-word candidates. Every candidate still requires game validation.
local curated={
    fruit="จัน จันทน์ ซาลัก เดื่อ ดิวเบอร์รี ยอ ยอบ้าน ยอป่า",
    thaidessert="จ่ามงกุฎ จาวตาลเชื่อม นางเล็ด นิ่มนวล พระพาย พุทราเชื่อม ยิ้มเสน่ห์",
    snack="ช็อกโกแลต ชีสบอล ชูโรส ซาลาเปา ซูชิ โดนัท ดองผลไม้ เต้าหู้ทอด ตือฮวน ถั่วทอด ถั่วลิสงอบ ถั่วลิสงต้ม ทอดมัน ทาโกะยากิ โรตี โรตีกรอบ วาฟเฟิล หอยทอด หมูปิ้ง หมูสะเต๊ะ ไส้กรอก อัลมอนด์อบ",
    landanimal="ดอร์เมาส์ เดกู ไดโนเสาร์",
    bird="ยูง ยูงไทย ยูงเขียว ยูงอินเดีย",
    flower="ถั่วผี เถาวัลย์หลง ถั่วพู ถั่วแปบ",
    job="ซินแส ซีอีโอ เซลส์ ซอมเมอลิเยร์ ดารา ดีเจ เด็กเสิร์ฟ เถ้าแก่",
    body="ชายโครง ซี่โครง ดวงตา ดั้ง ถุงน้ำดี ถุงอัณฑะ ทวารหนัก ท่อปัสสาวะ ท่อน้ำดี บ่า เบ้าตา พุง พังผืด เยื่อหุ้มสมอง เยื่อแก้วหู รังไข่ รูจมูก ริมฝีปาก วัลวา อก อัณฑะ",
    family="ซ้อ ทวด ทายาท ราชบุตร ราชธิดา วงศ์ญาติ วงศาคณาญาติ วงศ์วาน",
    folktale="ก้านกล้วย กระต่ายกับเต่า กบเจ้าชาย ขุนช้าง ขุนแผน ขวานฟ้าหน้าดำ คาวี ไกรทอง จันทโครพ จันทกุมาร จาฟาร์ จัสมิน ฉางเอ๋อ ชาละวัน ชูชก ซินเดอเรลลา ซินเดอเรลล่า ซุนหงอคง ซินแบด ดัมโบ ตะเภาแก้ว ตะเภาทอง ติ๊งเกอร์เบลล์ ถังซำจั๋ง ทศกัณฐ์ ท้าวแสนปม ท้าวสามล ท้าวยศวิมล นางเงือก นางสิบสอง นางรจนา นางสีดา นางวันทอง นางแก้วหน้าม้า บัวแก้ว บัวทอง บาลี ปลาบู่ทอง ปีเตอร์แพน ปิน็อกคิโอ ผีเสื้อสมุทร พินอคคิโอ พระอภัยมณี พระสังข์ พระลอ พระสุธน พลายแก้ว พลายงาม ภูริทัต มณโฑ มโนราห์ มู่หลาน เมาคลี ไมยราพ ยักษ์ ยักษ์วัดแจ้ง รจนา ราพันเซล รามสูร ลักษณวงศ์ ลิตเติลเมอร์เมด ลูกหมูสามตัว วันทอง วานร ศรีธนญชัย สโนว์ไวท์ สังข์ทอง สินสมุทร สุดสาคร สุพรรณมัจฉา หนูน้อยหมวกแดง หนุมาน หมีพูห์ อาละดิน อาลีบาบา อุสา ฮันเซล เกรเทล เงาะป่า เจ้าชายน้อย เจ้าหญิงนิทรา เจ้าหญิงถั่วลันเตา",
    house="ถังขยะ ถังน้ำ ถุงขยะ ถาด ถุงพลาสติก ถ้วยชาม ถ้วย ขัน ขวด ขวดน้ำ เขียง ค้อน ครก คีม ด้าย ดอกกุญแจ ด้ามไม้กวาด ทัพพี ทิชชู่ ที่นอน ที่เปิดขวด น้ำยาล้างจาน น้ำยาถูพื้น บันได บัวรดน้ำ ปลอกหมอน ปลั๊กไฟ ปฏิทิน แปรง แปรงสีฟัน ผ้าขนหนู ฝาชี ฝาหม้อ พรม มุ้ง ม่าน ยาสีฟัน ยาฆ่าแมลง ราวตากผ้า รองเท้าแตะ รีโมต ลิ้นชัก ลูกบิดประตู ลวด วอลเปเปอร์ วงกบ อ่างล้างจาน อ่างอาบน้ำ อ่างล้างหน้า โอ่ง",
    school="เข็มทิศ ขาตั้งกระดาน เครื่องคิดเลข คอมพิวเตอร์ จานสี จิ๊กซอว์ ซองเอกสาร ซองดินสอ ถุงดินสอ ถาดสี น้ำหมึก น้ำยาลบคำผิด บอร์ด บัตรนักเรียน ผ้าลบกระดาน แผนที่ พู่กัน แฟ้ม พจนานุกรม รองเท้านักเรียน ลูกโลก ลวดเสียบกระดาษ อุปกรณ์เรขาคณิต อุปกรณ์ทดลอง",
    vehicle="ขบวนรถไฟ ชอปเปอร์ ซาเล้ง ไซด์คาร์ ซูเปอร์คาร์ โดรน นาวา ปิกอัพ ปิคอัพ ลีมูซีน ล้อเลื่อน เวสป้า หัวรถจักร หัวลาก",
    appliance="ชาร์จเจอร์ ไดร์เป่าผม โน้ตบุ๊ก แบตเตอรี่ เบรกเกอร์ ปลั๊กพ่วง ปั๊มน้ำ แผงโซลาร์เซลล์ ยูพีเอส รีโมต ลำโพง สแกนเนอร์ สเตอริโอ สว่านไฟฟ้า อะแดปเตอร์ อ่างน้ำวน",
    instrument="เถิดเทิง โทน โปงลาง แคน ซอด้วง ซออู้ ซอสามสาย สะล้อ สังข์ หีบเพลง หีบเพลงปาก หีบเพลงชัก",
    color="จำปา ซีเปีย ตองอ่อน ตะกั่ว ตับม้า เถ้า บานเย็น บรอนซ์ เบจ เปลือกไข่ พีช เลือดหมู ลาเวนเดอร์ ไวน์แดง อิฐ อำพัน อินดิโก โอลด์โรส",
    subject="ขับร้อง ขับร้องประสานเสียง จริยศึกษา จิตวิทยา จุลชีววิทยา โซลเฟจ ตรีโกณมิติ ตรรกศาสตร์ ถ่ายภาพ ทัศนศิลป์ เทคโนโลยี ทักษะชีวิต ทฤษฎีดนตรี ธรรมศึกษา ธรณีวิทยา บัลเลต์ บัญชี บรรณารักษศาสตร์ บริหารธุรกิจ ผดุงครรภ์ พลศึกษา พฤกษศาสตร์ พีชคณิต แพทยศาสตร์ มานุษยวิทยา ยุทธศาสตร์ ละคร ลีลาศ ลอจิก หัตถศึกษา หัตถกรรม อังกฤษ อาชีวอนามัย อิเล็กทรอนิกส์ อุตสาหกรรมศึกษา",
    festival="เทศกาลไหว้พระจันทร์ วันเด็ก วันครู วันพ่อ วันแม่ วันสงกรานต์ วันลอยกระทง วันขึ้นปีใหม่ วันมาฆบูชา วันวิสาขบูชา วันอาสาฬหบูชา วันเข้าพรรษา วันออกพรรษา วันจักรี วันแรงงาน วันรัฐธรรมนูญ วันปิยมหาราช วันภาษาไทย วันสุนทรภู่ วันอนามัยโลก วันสิ่งแวดล้อมโลก วันฮาโลวีน หยวนเซียว เช็งเม้ง ฮาโลวีน คริสต์มาส ตรุษจีน อีสเตอร์ อีดิ้ลฟิตรี",
}
for cat,list in pairs(curated)do
    local preferred={}
    for word in list:gmatch("%S+")do
        addCandidate(cat,word)
        local l=firstConsonant(word)
        preferred[l]=preferred[l] or {}
        if seenCandidates[cat] and seenCandidates[cat][word] then table.insert(preferred[l],word)end
    end
    for l,wordsForLetter in pairs(preferred)do
        local unique,ordered={},{}
        for _,word in ipairs(wordsForLetter)do if not unique[word]then unique[word]=true;table.insert(ordered,word)end end
        for _,word in ipairs(bank[cat][l] or {})do if not unique[word]then unique[word]=true;table.insert(ordered,word)end end
        bank[cat][l]=ordered
    end
end

local checksThisRound=0
local function checked(cat,l,word,token,fresh)
    local key=cat.."/"..l.."/"..word
    if not fresh and validationCache[key] then return validationCache[key] end
    if checksThisRound>=80 then return "rate_limited" end
    checksThisRound=checksThisRound+1
    if not requestRemote then return "unavailable" end
    local done=false
    local status="unavailable"
    local call=task.spawn(function()
        local ok,result=pcall(function()
            return requestRemote:InvokeServer("checkAnswer",{category=cat,letter=l,text=word})
        end)
        if ok and type(result)=="table" and type(result.status)=="string" then status=result.status end
        done=true
    end)
    local limit=os.clock()+1.5
    while not done and alive and generation==token and os.clock()<limit do task.wait(0.05)end
    if not done then pcall(task.cancel,call)end
    if done and (status=="valid" or status=="unknown_word" or status=="wrong_letter" or status=="nonsense") then
        validationCache[key]=status
    end
    return status
end

local function startVocabulary()
    task.spawn(function()
        local ok,manifest=pcall(function()
            return HttpService:JSONDecode(game:HttpGet(dataBase.."manifest.json"))
        end)
        if not alive then return end
        if not ok or type(manifest)~="table" then
            vocabularyState="โหลดคลังใหญ่ไม่สำเร็จ — ยังใช้คลังคำเริ่มต้นได้"
            setDesc(vocabularyCard,vocabularyState)
            return
        end
        local nextPart,finished,failed=1,0,0
        local allSeen={}
        local function worker()
            while alive do
                local index=nextPart
                nextPart=nextPart+1
                local name=manifest.parts[index]
                if not name then return end
                local got,text=pcall(function()return game:HttpGet(dataBase..name)end)
                if not alive then return end
                if got and type(text)=="string" then
                    local n=0
                    for line in text:gmatch("[^\r\n]+")do
                        local word,cats=line:match("^(.-)\t(.*)$")
                        if word and not allSeen[word] then
                            allSeen[word]=true
                            vocabularyTotal=vocabularyTotal+1
                            for cat in cats:gmatch("[^,]+")do addCandidate(cat,word)end
                        end
                        n=n+1
                        if n%250==0 then task.wait();if not alive then return end end
                    end
                else failed=failed+1 end
                finished=finished+1
                vocabularyState=string.format("โหลดแล้ว %s / %s คำและวลี • %d/%d ส่วน",tostring(vocabularyTotal),tostring(manifest.total),finished,#manifest.parts)
                setDesc(vocabularyCard,vocabularyState)
            end
        end
        for _=1,3 do task.spawn(worker)end
        while alive and finished<#manifest.parts do task.wait(0.2)end
        if not alive then return end
        vocabularyState=string.format("โหลด %d คำและวลี • แบ่งหมวดอัตโนมัติ %d รายการ • ส่วนที่โหลดไม่สำเร็จ %d",vocabularyTotal,manifest.classified or 0,failed)
        setDesc(vocabularyCard,vocabularyState)
        log("คลังคำ: "..vocabularyState)
        if enabled and isOpen() then answer()end
    end)
end


answer=function()
    cancel()
    if legacyRunning then setStatus("มีสคริปต์รุ่นเก่าทำงานอยู่ — เข้าเกมใหม่ก่อนใช้ V4");return end
    if not isOpen()then setStatus("รอช่วงตอบคำถามของรอบใหม่");return end
    local token=generation
    local roundLetter,roundCategories=letter,categories
    task.spawn(function()
        task.wait(0.1)
        if not alive or generation~=token or not isOpen()then return end
        local state=discoverState()
        cacheText=state and "เชื่อมข้อมูลคำตอบในเกมแล้ว" or "เชื่อมข้อมูลไม่ได้ — เกมอาจเขียนทับคำตอบตอนจบรอบ"
        setDesc(cacheCard,cacheText)
        local cursor={}
        local function active()return alive and generation==token and isOpen()end
        local function key(id,word)return id.."/"..roundLetter.."/"..word end
        local function renderResults()
            local lines,n={},0
            for i,cat in ipairs(roundCategories)do
                local name=type(cat)=="table" and (cat.name or cat.id) or cat
                if sentByCategory[i]then n=n+1 end
                lines[#lines+1]=tostring(name)..": "..(sentByCategory[i] or "กำลังหาคำที่ผ่านตรวจ")
            end
            resultText=table.concat(lines,"\n");setDesc(resultCard,resultText)
            return n
        end
        -- Recheck our earlier answers; a prior successful check is not permanent.
        for index,cat in ipairs(roundCategories)do
            if not active()then return end
            local old=sentByCategory[index]
            if old then
                local id=type(cat)=="table" and cat.id or cat
                local status=checked(id,roundLetter,old,token,true)
                if not active()then return end
                if status~="valid" and status~="unavailable" then
                    sentByCategory[index]=nil
                    validationCache[key(id,old)]=status
                    if state and state.answers[index]==old then state.answers[index]="" end
                    input:FireServer({type="answer",cat=index,text=""})
                    log("ถอนคำที่ไม่ผ่าน: "..old)
                end
                task.wait(delaySeconds)
            end
        end
        -- Give every category a candidate before trying a second candidate.
        for pass=1,16 do
            if not active()then return end
            local pending=false
            for index,cat in ipairs(roundCategories)do
                if not active()then return end
                if not sentByCategory[index]then
                    local id=type(cat)=="table" and cat.id or cat
                    local name=type(cat)=="table" and (cat.name or id) or id
                    local list=bank[id] and bank[id][roundLetter] or {}
                    cursor[index]=cursor[index] or 1
                    local word=list[cursor[index]]
                    cursor[index]=cursor[index]+1
                    if word then
                        pending=true
                        setStatus("ตรวจ "..tostring(name)..": "..word)
                        local status=checked(id,roundLetter,word,token)
                        if not active()then return end
                        if status=="valid" then
                            if state and state.letter==roundLetter and state.canType then state.answers[index]=word end
                            local sentOK,err=pcall(function()input:FireServer({type="answer",cat=index,text=word})end)
                            if sentOK then
                                task.wait(0.3)
                                if not active()then return end
                                local final=checked(id,roundLetter,word,token,true)
                                if not active()then return end
                                if final=="valid" or final=="unavailable" then
                                    sentByCategory[index]=word
                                    log(tostring(name).." → "..word..(final=="valid" and " ✓" or " • ส่งแล้ว รอตรวจซ้ำ"))
                                else
                                    validationCache[key(id,word)]=final
                                    if state and state.answers[index]==word then state.answers[index]="" end
                                    input:FireServer({type="answer",cat=index,text=""})
                                    log("เกมไม่รับ "..word.." — จะลองคำถัดไป")
                                end
                            else log("ส่งไม่สำเร็จ: "..tostring(err))end
                        elseif status=="rate_limited" or status=="unavailable" then
                            log("ตรวจคำยังไม่สำเร็จ: "..tostring(name).." / "..status)
                            cursor[index]=cursor[index]-1
                            task.wait(0.6)
                        end
                        renderResults()
                        task.wait(delaySeconds)
                    end
                end
            end
            if renderResults()==#roundCategories or not pending then break end
        end
        if active()then
            local n=renderResults()
            setStatus(string.format("ส่งแล้ว %d/%d หมวด • %s",n,#roundCategories,
                n==#roundCategories and "กดหยุด/ส่งในเกมเมื่อพร้อม" or "ยังมีหมวดที่ไม่พบคำผ่านตรวจ"))
        end
    end)
end

statusCard = Main:Paragraph({ Title = "สถานะ • V4", Desc = statusText })
roundCard = Main:Paragraph({ Title = "รอบปัจจุบัน", Desc = "รอเริ่มรอบ" })
Main:Toggle({
    Title = "ตอบคำถามอัตโนมัติ",
    Desc = "ตรวจคำก่อนและหลังส่ง ถ้าเกมไม่รับจะลองคำถัดไป",
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
vocabularyCard=Settings:Paragraph({Title="คลังคำและวลีไทย",Desc=vocabularyState})
Settings:Paragraph({Title="เครดิตข้อมูล",Desc="VOLUBILIS Mundo by Belisan • CC BY-SA 4.0\n102,783 รายการหลังกรอง • ไม่ใช่เฉลยที่เกมรับรอง"})
Settings:Paragraph({
    Title = "เครดิตหน้าต่าง",
    Desc = "WindUI by Footagesus • MIT • github.com/Footagesus/WindUI",
})

function controller.Destroy()
    if not alive then return end
    alive = false
    shell:Destroy()
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
    sentByCategory={}
    validationCache={}
    checksThisRound=0
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
log("เปิดหน้าต่าง V4 แล้ว — เปิดสวิตช์เพื่อใช้งาน")
if legacyRunning then setStatus("มีสคริปต์รุ่นเก่าทำงานอยู่ — เข้าเกมใหม่ก่อนใช้ V4")end
startVocabulary()
return controller

