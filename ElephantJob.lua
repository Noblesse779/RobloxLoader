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

local function pressPrompt(prompt)
    if typeof(fireproximityprompt) == "function" then
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
    shownPrompt = nil
    hrp.CFrame = target
    status = "วาร์ปไปหา NPC แล้ว รอปุ่มคุยขึ้น..."
    if not waitFor(3, function() return shownPrompt ~= nil end) then
        status = "วาร์ปไปแล้วแต่ปุ่มคุยไม่ขึ้น"
        return false
    end
    pressPrompt(shownPrompt)
    status = ("กดคุยแล้ว (%s)"):format(shownPrompt and shownPrompt.ActionText or "?")
    return true
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

local ACCEPT_WORDS = { "รับงาน", "accept", "take the job" }
local function findAcceptOption()
    for _, d in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and isShown(d) then
            local t = d.Text:lower()
            for _, w in ipairs(ACCEPT_WORDS) do
                if t:find(w, 1, true) and not t:find("ไว้ก่อน", 1, true) then
                    return d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton") or d
                end
            end
        end
    end
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

-- ขี่ช้างอยู่ไหม (นั่งบนที่นั่งของช้าง)
local function riding()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.SeatPart ~= nil
end

local function acceptJob()
    if riding() then
        status = "ขี่ช้างอยู่แล้ว (รับงานอยู่)"
        return true
    end
    if not goTalk() then return false end
    local option
    if not waitFor(3, function()
        option = findAcceptOption()
        return option ~= nil
    end) then
        -- หาตัวเลือกบนจอไม่เจอ: กดเลข 1 แทน (ผู้เล่นกด 1 เองก็รับงานได้)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
        task.wait(0.1)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
    else
        pressGuiButton(option)
    end
    if waitFor(4, riding) then
        status = "รับงานแล้ว ขี่ช้างอยู่"
        return true
    end
    -- กดที่ตัวเลือกไม่ติด ลองกดเลข 1 อีกที
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
    if waitFor(3, riding) then
        status = "รับงานแล้ว ขี่ช้างอยู่"
        return true
    end
    status = option and "กดรับงานแล้วแต่ไม่ได้ขี่ช้าง" or "ไม่เจอตัวเลือก รับงานลากซุง"
    return false
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
local statusPara = jobSection:AddParagraph({ Title = "สถานะ", Content = status })

Window:SelectTab(1)

task.spawn(function()
    while alive() and not Fluent.Unloaded do
        local prompt = findJobPrompt()
        pcall(function()
            statusPara:SetDesc(("%s\nNPC: %s  •  ขี่ช้าง: %s"):format(status,
                prompt and ("เจอ (" .. prompt.ActionText .. ")") or "ยังหาไม่เจอ",
                riding() and "ใช่" or "ไม่"))
        end)
        task.wait(1)
    end
    if alive() then env.ElephantRun += 1 end
end)
