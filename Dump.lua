-- อ่านทั้งระบบของเซิฟ (ฝั่งที่เครื่องเราเห็นได้) แล้วเซฟเป็นไฟล์ไว้ส่งให้ดู
-- ได้: รีโมททั้งหมด, ค่าในตัวผู้เล่น (ของ/เงิน/สถานะ), ปุ่ม E (ProximityPrompt) ในแมพ,
--      โครงสร้างแมพ, โค้ดสคริปต์ฝั่งเครื่องเรา (decompile) ทั้งหมด
-- ไฟล์อยู่ที่โฟลเดอร์ workspace ของตัวรัน: GameDump/<PlaceId>/
--   00_index.txt  = สรุป (ส่งอันนี้ก่อน)
--   scripts_N.txt = โค้ด แบ่งไฟล์ละ ~1MB

local CONFIG = {
    chunkSize = 1000000,   -- ขนาดต่อไฟล์โค้ด
    skipRoblox = true,     -- ข้ามสคริปต์มาตรฐานของ Roblox (กล้อง/ควบคุม/แชท) ไฟล์จะเล็กลงมาก
    workspaceDepth = 3,    -- ความลึกของต้นไม้แมพในไฟล์สรุป
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function notify(text)
    print("[Dump] " .. text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Dump", Text = text, Duration = 5 })
    end)
end

if typeof(writefile) ~= "function" then
    notify("ตัวรันนี้ไม่มี writefile เซฟไฟล์ไม่ได้")
    return
end
local canDecompile = typeof(decompile) == "function"

local ROOT = "GameDump/" .. game.PlaceId
pcall(function()
    if typeof(makefolder) == "function" then
        if not (typeof(isfolder) == "function" and isfolder("GameDump")) then makefolder("GameDump") end
        if not (typeof(isfolder) == "function" and isfolder(ROOT)) then makefolder(ROOT) end
    end
end)

local function path(inst)
    local ok, full = pcall(function() return inst:GetFullName() end)
    return ok and full or tostring(inst)
end

local function fmt(v)
    local t = typeof(v)
    if t == "string" then return string.format("%q", v) end
    if t == "Instance" then return path(v) end
    return tostring(v)
end

local function attrs(inst)
    local ok, a = pcall(function() return inst:GetAttributes() end)
    if not ok or not next(a) then return "" end
    local parts = {}
    for k, v in pairs(a) do parts[#parts + 1] = k .. "=" .. fmt(v) end
    table.sort(parts)
    return "  {" .. table.concat(parts, ", ") .. "}"
end

local index = {}
local function out(line) index[#index + 1] = line end

---------------------------------------------------------------- ข้อมูลเกม
local placeName = "?"
pcall(function()
    placeName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
end)
out("==== เกม")
out("ชื่อ: " .. placeName)
out("PlaceId: " .. game.PlaceId .. "  GameId: " .. game.GameId .. "  JobId: " .. game.JobId)
out("ผู้เล่นในเซิฟ: " .. #Players:GetPlayers())
out("")

---------------------------------------------------------------- รีโมท
local REMOTE_CLASSES = {
    RemoteEvent = "RE", RemoteFunction = "RF", UnreliableRemoteEvent = "URE",
    BindableEvent = "BE", BindableFunction = "BF",
}
local remotes = {}
local okAll, everything = pcall(function() return game:GetDescendants() end)
if not okAll then
    everything = {}
    for _, service in ipairs(game:GetChildren()) do
        pcall(function()
            for _, inst in ipairs(service:GetDescendants()) do everything[#everything + 1] = inst end
        end)
    end
end
for _, inst in ipairs(everything) do
    local tag = REMOTE_CLASSES[inst.ClassName]
    if tag then
        local ok = pcall(function() return inst.Parent end)
        if ok then remotes[#remotes + 1] = string.format("[%s] %s", tag, path(inst)) end
    end
end
table.sort(remotes)
out("==== รีโมท (" .. #remotes .. ")")
for _, r in ipairs(remotes) do out(r) end
out("")

---------------------------------------------------------------- ค่าในตัวผู้เล่น
local function dumpValues(root, depth, prefix)
    for _, child in ipairs(root:GetChildren()) do
        local line = prefix .. child.Name .. " (" .. child.ClassName .. ")"
        if child:IsA("ValueBase") then
            local ok, v = pcall(function() return child.Value end)
            if ok then line = line .. " = " .. fmt(v) end
        end
        out(line .. attrs(child))
        if depth > 1 and not child:IsA("PlayerGui") and not child:IsA("PlayerScripts")
            and not child:IsA("Model") then
            dumpValues(child, depth - 1, prefix .. "  ")
        end
    end
end
out("==== ผู้เล่น: " .. LocalPlayer.Name .. attrs(LocalPlayer))
dumpValues(LocalPlayer, 4, "")
out("")
if LocalPlayer.Character then
    out("==== ตัวละคร" .. attrs(LocalPlayer.Character))
    for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
        if not child:IsA("BasePart") and not child:IsA("Accessory") then
            out(child.Name .. " (" .. child.ClassName .. ")" .. attrs(child))
        end
    end
    out("")
end
out("==== กระเป๋า (Backpack)")
for _, tool in ipairs(LocalPlayer:WaitForChild("Backpack"):GetChildren()) do
    out(tool.Name .. " (" .. tool.ClassName .. ")" .. attrs(tool))
end
out("")

---------------------------------------------------------------- ปุ่ม E ในแมพ
local prompts = {}
for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("ProximityPrompt") then
        prompts[#prompts + 1] = string.format("%s | Action=%q Object=%q Hold=%s Dist=%s%s",
            path(inst), inst.ActionText, inst.ObjectText, inst.HoldDuration, inst.MaxActivationDistance, attrs(inst))
    end
end
table.sort(prompts)
out("==== ปุ่ม E / ProximityPrompt (" .. #prompts .. ")")
for _, p in ipairs(prompts) do out(p) end
out("")

---------------------------------------------------------------- โครงสร้างแมพ
local function tree(root, depth, prefix)
    local counts, order = {}, {}
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("BasePart") or child:IsA("Terrain") then
            counts[child.ClassName] = (counts[child.ClassName] or 0) + 1
        else
            local key = child.Name .. " (" .. child.ClassName .. ")"
            if not counts[key] then order[#order + 1] = { key = key, inst = child } end
            counts[key] = (counts[key] or 0) + 1
        end
    end
    for _, e in ipairs(order) do
        local n = counts[e.key]
        out(prefix .. e.key .. (n > 1 and (" x" .. n) or "") .. attrs(e.inst))
        if depth > 1 and n == 1 then tree(e.inst, depth - 1, prefix .. "  ") end
    end
    local parts = 0
    for k, n in pairs(counts) do
        if k == "Part" or k == "MeshPart" or k == "UnionOperation" or k == "WedgePart" then parts += n end
    end
    if parts > 0 then out(prefix .. "(ชิ้นส่วน " .. parts .. ")") end
end
out("==== แมพ (workspace)")
tree(workspace, CONFIG.workspaceDepth, "")
out("")

---------------------------------------------------------------- สคริปต์
local ROBLOX_SKIP = {
    "PlayerModule", "RbxCharacterSounds", "ChatScript", "BubbleChat", "PlayerScriptsLoader",
    "ChatServiceRunner", "ClientChatModules", "ChatModules", "CoreGui", "CorePackages",
    "TextChatService", "Animate",
}
local function skip(full)
    if not CONFIG.skipRoblox then return false end
    for _, word in ipairs(ROBLOX_SKIP) do
        if string.find(full, word, 1, true) then return true end
    end
    return false
end

local scripts, seen = {}, {}
local function add(s)
    if typeof(s) ~= "Instance" or seen[s] then return end
    if not (s:IsA("LocalScript") or s:IsA("ModuleScript")
        or (s:IsA("Script") and s.RunContext == Enum.RunContext.Client)) then return end
    seen[s] = true
    local full = path(s)
    if not skip(full) then scripts[#scripts + 1] = { inst = s, path = full } end
end
for _, root in ipairs({
    game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst"),
    game:GetService("StarterPlayer"), game:GetService("StarterGui"), game:GetService("StarterPack"),
    LocalPlayer, workspace,
}) do
    for _, inst in ipairs(root:GetDescendants()) do add(inst) end
end
-- สคริปต์ที่ซ่อนอยู่ (ไม่มีพ่อ/โหลดอยู่ในหน่วยความจำ)
if typeof(getloadedmodules) == "function" then
    pcall(function() for _, m in ipairs(getloadedmodules()) do add(m) end end)
end
if typeof(getscripts) == "function" then
    pcall(function() for _, s in ipairs(getscripts()) do add(s) end end)
end
if typeof(getnilinstances) == "function" then
    pcall(function() for _, s in ipairs(getnilinstances()) do add(s) end end)
end
table.sort(scripts, function(a, b) return a.path < b.path end)

out("==== สคริปต์ (" .. #scripts .. ")" .. (canDecompile and "" or "  * ตัวรันนี้ decompile ไม่ได้ มีแค่รายชื่อ"))
for _, s in ipairs(scripts) do out(s.inst.ClassName .. "  " .. s.path) end

local indexText = table.concat(index, "\n")
writefile(ROOT .. "/00_index.txt", indexText)
notify("เซฟสรุปแล้ว กำลัง decompile " .. #scripts .. " สคริปต์...")

if not canDecompile then
    notify("เสร็จ (ไม่มี decompile) ไฟล์: " .. ROOT .. "/00_index.txt")
    return
end

local fileNo, buf, size, failed = 1, {}, 0, 0
local function flush()
    if #buf == 0 then return end
    writefile(ROOT .. "/scripts_" .. fileNo .. ".txt", table.concat(buf))
    fileNo += 1
    buf, size = {}, 0
end
local hashes = {}
for i, s in ipairs(scripts) do
    local hash
    if typeof(getscripthash) == "function" then
        pcall(function() hash = getscripthash(s.inst) end)
    end
    local body
    if hash and hashes[hash] then
        body = "-- (โค้ดเหมือนกับ " .. hashes[hash] .. ")\n"
    else
        local ok, src = pcall(decompile, s.inst)
        if ok and typeof(src) == "string" then
            body = src
        else
            failed += 1
            body = "-- decompile ไม่ได้: " .. tostring(src) .. "\n"
        end
        if hash then hashes[hash] = s.path end
    end
    local block = "\n-- ==== " .. s.path .. " (" .. s.inst.ClassName .. ")\n" .. body .. "\n"
    if size + #block > CONFIG.chunkSize then flush() end
    buf[#buf + 1] = block
    size += #block
    if i % 10 == 0 then task.wait() end
    if i % 100 == 0 then notify("decompile " .. i .. "/" .. #scripts) end
end
flush()

notify(string.format("เสร็จ! %d สคริปต์ (พลาด %d) %d ไฟล์โค้ด อยู่ใน %s", #scripts, failed, fileNo - 1, ROOT))
pcall(function()
    if typeof(setclipboard) == "function" then setclipboard(indexText) end
end)
