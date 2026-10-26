-- PoolSpy: เก็บข้อมูลโต๊ะพูล (ใช้ครั้งเดียวเพื่อทำสคริปต์แทงอัตโนมัติ เล่นกับบอท)
-- - ดัก PoolSystem.Channel ทุกอันที่ไม่ใช่ "aim" (เช่นตอนปล่อยแทง)
-- - ดักสิ่งที่เซิร์ฟเวอร์ส่งกลับมาทาง Channel (ไม่เอาที่ซ้ำ)
-- - กดปุ่ม P = เขียนโครงสร้างโต๊ะ + ลูกทั้งหมด แล้วคัดลอกทั้งหมดใส่คลิปบอร์ด
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local channel = ReplicatedStorage:WaitForChild("PoolSystem"):WaitForChild("Channel")
local log = {}

local function ser(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "table" then
        if depth > 3 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. ser(x, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        return v:GetFullName()
    elseif t == "string" then
        return ("%q"):format(v)
    end
    return t .. "(" .. tostring(v) .. ")"
end

local function add(line)
    table.insert(log, line)
    print("[PoolSpy] " .. line)
end

local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
local old
old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
    if self == channel and getnamecallmethod() == "FireServer" then
        local action = ...
        if action ~= "aim" then
            add("ส่ง: " .. ser({ ... }))
        end
    end
    return old(self, ...)
end))

local seen = {}
channel.OnClientEvent:Connect(function(...)
    local s = ser({ ... })
    local key = s:sub(1, 60)
    if not seen[key] then
        seen[key] = true
        add("รับ: " .. s:sub(1, 1500))
    end
end)

local function dumpTable()
    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name:match("^Table%d+$") then
            table.insert(out, "== " .. d:GetFullName() .. " (" .. d.ClassName .. ")")
            for _, c in ipairs(d:GetDescendants()) do
                local line = c:GetFullName():sub(#d:GetFullName() + 2) .. " [" .. c.ClassName .. "]"
                if c:IsA("BasePart") then
                    line ..= (" pos=%.2f,%.2f,%.2f size=%.2f,%.2f,%.2f"):format(
                        c.Position.X, c.Position.Y, c.Position.Z, c.Size.X, c.Size.Y, c.Size.Z)
                    if c:IsA("Part") then line ..= " shape=" .. c.Shape.Name end
                end
                table.insert(out, line)
                if #out > 400 then break end
            end
        end
    end
    return table.concat(out, "\n")
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.P then return end
    local text = table.concat(log, "\n") .. "\n\n" .. dumpTable()
    if typeof(setclipboard) == "function" then
        setclipboard(text)
        print("[PoolSpy] คัดลอกใส่คลิปบอร์ดแล้ว (" .. #text .. " ตัวอักษร)")
    else
        print(text)
    end
end)

print("[PoolSpy] พร้อม: แทงลูก 1-2 ครั้ง แล้วกด P")
