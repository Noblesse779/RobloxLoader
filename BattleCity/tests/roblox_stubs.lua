-- roblox_stubs.lua : จำลอง Roblox API สำหรับเทสเท่านั้น (ไม่ต้องเอาไปใส่ใน Studio)
-- รัน Script (server) + LocalScript (client) ใน lupa.lua51 VM เดียว เพื่อจับ error, index nil,
-- ชื่อ API ผิด, ชนิดค่าผิด ก่อนผู้ใช้เอาโค้ดไปวางใน Roblox Studio จริง
--
-- วิธีใช้ (ฝั่ง python ดู roblox_env.py ซึ่งห่อทั้งหมดนี้ไว้แล้ว):
--   local Stubs = <โหลดไฟล์นี้>
--   local world = Stubs.newWorld({ studio = false, echo = false, maxPlayers = 8, signalBehavior = "Immediate" })
--   world:addModule(world.services.ServerScriptService, "BattleCityCore", "BattleCity/BattleCityCore.lua")
--   world:runScript("BattleCity/BattleCityServer.lua", { class = "Script", parent = world.services.ServerScriptService })
--   local p = world:addPlayer("Alice", 1, { keyboard = true })    -- PlayerAdded ยิง "ทันที" (ไม่รอ step)
--   world:runScript("BattleCity/BattleCityClient.lua", { class = "LocalScript", player = p })
--   world:advance(2)          -- เดินเวลาจำลองทีละ 1/60 วินาที
--   world:keyDown(p, "W")
--   assert(#world.errors == 0)
--
-- กติกาที่คนเขียนเทสควรรู้:
-- * เวลาเป็นเวลาจำลอง เดินด้วย world:step(dt) เท่านั้น (tick/time/os.clock ก็ใช้เวลาจำลอง)
-- * ทุก thread รู้ว่าตัวเองเป็น server หรือ client ของใคร (ctx) -> Players.LocalPlayer, RunService:IsClient()
--   และ handler ของ signal รันใน ctx ของสคริปต์ที่ Connect ไว้
-- * signal ยิงแบบ immediate: handler แต่ละตัวรันใน coroutine ของตัวเอง error ตัวหนึ่งไม่ทำให้ตัวอื่นพัง
--   (signalBehavior = "Deferred" ให้ handler รันตอนจบรอบ เหมือน Workspace.SignalBehavior = Deferred)
-- * pcall/xpcall yield ได้แบบ Luau (ทำผ่าน coroutine ลูก) และ coroutine.running() คืน thread ของสคริปต์
-- * ไลบรารีเข้มงวดแบบ Luau: string.format("%d", 1.5) error, table.insert/remove ตำแหน่งเกิน error,
--   ไม่มี loadstring/io/package/math.mod; type(Vector3) = "vector"
-- * Players.CharacterAutoLoads = true เป็นค่าเริ่มต้นเหมือน Roblox (ตัวละครเกิดใน step ถัดไปถ้าไม่ปิด)
-- * instance ที่ client สร้าง มองเห็นเฉพาะ client นั้น (เหมือน Roblox ที่ไม่ replicate ขึ้น server)
--   ส่วน property ของ instance ที่ server สร้าง ถ้า client แก้ ทุกฝั่งจะเห็นค่าเดียวกัน (ไม่ได้แยกสำเนา)
-- * ลำดับใน world:step(dt): ส่ง RemoteEvent ที่ค้างจาก step ก่อน -> client render (BindToRenderStep เรียงตาม
--   priority แล้วตามด้วย RenderStepped) -> Stepped/PreSimulation -> tween -> Heartbeat/PostSimulation ->
--   ปลุก task.wait/task.delay ที่ถึงเวลา -> Debris -> WaitForChild timeout/เตือน -> task.defer
-- * ไม่มีฟิสิกส์ / joint: Weld ไม่ลาก part ตาม ให้ใช้ Model:PivotTo (ซึ่งย้ายทุก BasePart แบบ rigid)
-- * world.errors / world.warnings / world.output เป็น array ของ string

local Stubs = {}

local unpack = unpack or table.unpack
local select, type, tostring, tonumber, pairs, ipairs, next = select, type, tostring, tonumber, pairs, ipairs, next
local rawget, rawset, setmetatable, getmetatable = rawget, rawset, setmetatable, getmetatable
local floor, abs, sqrt, sin, cos, atan2, asin, acos = math.floor, math.abs, math.sqrt, math.sin, math.cos, math.atan2, math.asin, math.acos
local huge, pi = math.huge, math.pi
local fmt, tinsert, tremove, tconcat, tsort = string.format, table.insert, table.remove, table.concat, table.sort
local getmt = debug.getmetatable
local cocreate, coresume, coyield, costatus, corunning = coroutine.create, coroutine.resume, coroutine.yield, coroutine.status, coroutine.running

local STUBS_SRC = debug.getinfo(1, "S").source

local function pack(...)
	return { n = select("#", ...), ... }
end

-- ============================================================================
-- ระบบชนิดข้อมูล: ทุกค่าแบบ Roblox เป็น userdata (newproxy) เหมือนของจริง type() จึงได้ "userdata"
-- ============================================================================
local D = setmetatable({}, { __mode = "k" }) -- proxy -> ข้อมูลภายใน
local TYPE_OF_MT = {} -- metatable -> ชื่อชนิดสำหรับ typeof()
local LOCKED = "The metatable is locked"

local function newType(name)
	local proto = newproxy(true)
	local mt = getmetatable(proto)
	mt.__metatable = LOCKED
	TYPE_OF_MT[mt] = name
	local function make(data)
		local p = newproxy(proto)
		D[p] = data
		return p
	end
	return mt, make
end

local function typeOf(v)
	local t = type(v)
	if t == "userdata" then
		local mt = getmt(v)
		return (mt and TYPE_OF_MT[mt]) or "userdata"
	end
	return t
end

-- หา stack level แรกที่เป็นโค้ดผู้ใช้ เพื่อให้ข้อความ error ขึ้นต้นด้วยบรรทัดของสคริปต์จริง (เหมือน Roblox)
local function throw(msg)
	local lvl = 2
	while true do
		local info = debug.getinfo(lvl, "S")
		if not info then
			-- ไม่เจอเฟรมผู้ใช้ (เช่นถูก tail call แทนที่) -> ไม่ใส่ตำแหน่ง ดู traceback แทน
			error(msg, 0)
		end
		-- ข้ามเฟรมของ stubs, ฟังก์ชัน C และเฟรม tail call (ไม่มีตำแหน่งบรรทัด)
		if info.source ~= STUBS_SRC and info.what ~= "C" and info.what ~= "tail" then
			error(msg, lvl)
		end
		lvl = lvl + 1
	end
end

local function badArg(i, fname, expected, got)
	throw(fmt("invalid argument #%d to '%s' (%s expected, got %s)", i, fname, expected, typeOf(got)))
end

local function optNum(v, i, fname, default)
	if v == nil then
		return default
	end
	if type(v) == "number" then
		return v
	end
	if type(v) == "string" and tonumber(v) then
		return tonumber(v)
	end
	badArg(i, fname, "number", v)
end

local function checkNum(v, i, fname)
	if type(v) == "number" then
		return v
	end
	if type(v) == "string" and tonumber(v) then
		return tonumber(v)
	end
	badArg(i, fname, "number", v)
end

local function arithError(op, a, b)
	throw(fmt("attempt to perform arithmetic (%s) on %s and %s", op, typeOf(a), typeOf(b)))
end

local function readonlyTable(t, name)
	-- ตาราง library ของ Luau แก้ไม่ได้ (เขียนแล้ว error) จึงทำเป็น proxy
	return setmetatable({}, {
		__index = t,
		__newindex = function(_, k)
			throw(fmt("attempt to modify a readonly table (%s.%s)", name or "?", tostring(k)))
		end,
	})
end

local function numStr(n)
	-- แสดงตัวเลขแบบสั้นที่สุดที่ยังอ่านกลับได้ค่าเดิม (คล้าย Luau)
	if n ~= n then
		return "nan"
	end
	if n == huge then
		return "inf"
	end
	if n == -huge then
		return "-inf"
	end
	if n == floor(n) and abs(n) < 1e15 then
		return fmt("%d", n)
	end
	for p = 1, 17 do
		local s = fmt("%." .. p .. "g", n)
		if tonumber(s) == n then
			return s
		end
	end
	return fmt("%.17g", n)
end

local function memberError(k, owner)
	throw(fmt("%s is not a valid member of %s", tostring(k), owner))
end

local function makeAccess(mt, typeName, getters, methods)
	mt.__index = function(self, k)
		local g = getters[k]
		if g then
			return g(D[self])
		end
		local m = methods[k]
		if m then
			return m
		end
		memberError(k, typeName)
	end
	mt.__newindex = function(_, k)
		throw(fmt("%s cannot be assigned to", tostring(k)))
	end
end

local function selfData(mt, v, name)
	if getmt(v) ~= mt then
		throw("Expected ':' not '.' calling member function " .. name)
	end
	return D[v]
end

local R = { clock = function() return 0 end } -- ที่รวมของที่ export จากแต่ละบล็อก (กันชนลิมิต 200 local ของ Lua 5.1)
do
-- ============================================================================
-- Vector3
-- ============================================================================
local V3MT, mkV3 = newType("Vector3")
local function V3(x, y, z)
	return mkV3({ x, y, z })
end
local function isV3(v)
	return getmt(v) == V3MT
end

local V3Get = {
	X = function(d) return d[1] end,
	Y = function(d) return d[2] end,
	Z = function(d) return d[3] end,
	Magnitude = function(d) return sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3]) end,
	Unit = function(d)
		local m = sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
		return V3(d[1] / m, d[2] / m, d[3] / m)
	end,
}
V3Get.x, V3Get.y, V3Get.z, V3Get.magnitude, V3Get.unit = V3Get.X, V3Get.Y, V3Get.Z, V3Get.Magnitude, V3Get.Unit

local V3M = {}
local function v3arg(v, i, fname)
	if not isV3(v) then
		badArg(i, fname, "Vector3", v)
	end
	return D[v]
end
function V3M.Dot(a, b)
	local x = selfData(V3MT, a, "Dot")
	local y = v3arg(b, 1, "Dot")
	return x[1] * y[1] + x[2] * y[2] + x[3] * y[3]
end
function V3M.Cross(a, b)
	local x = selfData(V3MT, a, "Cross")
	local y = v3arg(b, 1, "Cross")
	return V3(x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1])
end
function V3M.Lerp(a, b, t)
	local x = selfData(V3MT, a, "Lerp")
	local y = v3arg(b, 1, "Lerp")
	t = checkNum(t, 2, "Lerp")
	return V3(x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t)
end
function V3M.FuzzyEq(a, b, eps)
	local x = selfData(V3MT, a, "FuzzyEq")
	local y = v3arg(b, 1, "FuzzyEq")
	eps = optNum(eps, 2, "FuzzyEq", 1e-5)
	return abs(x[1] - y[1]) <= eps and abs(x[2] - y[2]) <= eps and abs(x[3] - y[3]) <= eps
end
function V3M.Abs(a)
	local x = selfData(V3MT, a, "Abs")
	return V3(abs(x[1]), abs(x[2]), abs(x[3]))
end
function V3M.Floor(a)
	local x = selfData(V3MT, a, "Floor")
	return V3(floor(x[1]), floor(x[2]), floor(x[3]))
end
function V3M.Ceil(a)
	local x = selfData(V3MT, a, "Ceil")
	return V3(math.ceil(x[1]), math.ceil(x[2]), math.ceil(x[3]))
end
local function sign(n)
	if n > 0 then
		return 1
	elseif n < 0 then
		return -1
	end
	return 0
end
function V3M.Sign(a)
	local x = selfData(V3MT, a, "Sign")
	return V3(sign(x[1]), sign(x[2]), sign(x[3]))
end
function V3M.Min(a, ...)
	local x = selfData(V3MT, a, "Min")
	local r1, r2, r3 = x[1], x[2], x[3]
	for i = 1, select("#", ...) do
		local y = v3arg(select(i, ...), i, "Min")
		r1, r2, r3 = math.min(r1, y[1]), math.min(r2, y[2]), math.min(r3, y[3])
	end
	return V3(r1, r2, r3)
end
function V3M.Max(a, ...)
	local x = selfData(V3MT, a, "Max")
	local r1, r2, r3 = x[1], x[2], x[3]
	for i = 1, select("#", ...) do
		local y = v3arg(select(i, ...), i, "Max")
		r1, r2, r3 = math.max(r1, y[1]), math.max(r2, y[2]), math.max(r3, y[3])
	end
	return V3(r1, r2, r3)
end
function V3M.Angle(a, b, axis)
	local x = selfData(V3MT, a, "Angle")
	local y = v3arg(b, 1, "Angle")
	local cx, cy, cz = x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1]
	local ang = atan2(sqrt(cx * cx + cy * cy + cz * cz), x[1] * y[1] + x[2] * y[2] + x[3] * y[3])
	if axis ~= nil then
		local ax = v3arg(axis, 2, "Angle")
		if cx * ax[1] + cy * ax[2] + cz * ax[3] < 0 then
			ang = -ang
		end
	end
	return ang
end
V3M.lerp = V3M.Lerp
makeAccess(V3MT, "Vector3", V3Get, V3M)

V3MT.__add = function(a, b)
	if isV3(a) and isV3(b) then
		local x, y = D[a], D[b]
		return V3(x[1] + y[1], x[2] + y[2], x[3] + y[3])
	end
	arithError("add", a, b)
end
V3MT.__sub = function(a, b)
	if isV3(a) and isV3(b) then
		local x, y = D[a], D[b]
		return V3(x[1] - y[1], x[2] - y[2], x[3] - y[3])
	end
	arithError("sub", a, b)
end
V3MT.__mul = function(a, b)
	if isV3(a) then
		local x = D[a]
		if isV3(b) then
			local y = D[b]
			return V3(x[1] * y[1], x[2] * y[2], x[3] * y[3])
		elseif type(b) == "number" then
			return V3(x[1] * b, x[2] * b, x[3] * b)
		end
	elseif type(a) == "number" and isV3(b) then
		local y = D[b]
		return V3(a * y[1], a * y[2], a * y[3])
	end
	arithError("mul", a, b)
end
V3MT.__div = function(a, b)
	if isV3(a) then
		local x = D[a]
		if isV3(b) then
			local y = D[b]
			return V3(x[1] / y[1], x[2] / y[2], x[3] / y[3])
		elseif type(b) == "number" then
			return V3(x[1] / b, x[2] / b, x[3] / b)
		end
	elseif type(a) == "number" and isV3(b) then
		local y = D[b]
		return V3(a / y[1], a / y[2], a / y[3])
	end
	arithError("div", a, b)
end
V3MT.__unm = function(a)
	local x = D[a]
	return V3(-x[1], -x[2], -x[3])
end
V3MT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2] and x[3] == y[3]
end
V3MT.__tostring = function(a)
	local x = D[a]
	return numStr(x[1]) .. ", " .. numStr(x[2]) .. ", " .. numStr(x[3])
end

local Vector3 = {}
function Vector3.new(x, y, z)
	return V3(optNum(x, 1, "new", 0), optNum(y, 2, "new", 0), optNum(z, 3, "new", 0))
end
Vector3.zero = V3(0, 0, 0)
Vector3.one = V3(1, 1, 1)
Vector3.xAxis = V3(1, 0, 0)
Vector3.yAxis = V3(0, 1, 0)
Vector3.zAxis = V3(0, 0, 1)

-- ============================================================================
-- Vector2
-- ============================================================================
local V2MT, mkV2 = newType("Vector2")
local function V2(x, y)
	return mkV2({ x, y })
end
local function isV2(v)
	return getmt(v) == V2MT
end
local V2Get = {
	X = function(d) return d[1] end,
	Y = function(d) return d[2] end,
	Magnitude = function(d) return sqrt(d[1] * d[1] + d[2] * d[2]) end,
	Unit = function(d)
		local m = sqrt(d[1] * d[1] + d[2] * d[2])
		return V2(d[1] / m, d[2] / m)
	end,
}
V2Get.x, V2Get.y, V2Get.magnitude, V2Get.unit = V2Get.X, V2Get.Y, V2Get.Magnitude, V2Get.Unit
local V2M = {}
local function v2arg(v, i, fname)
	if not isV2(v) then
		badArg(i, fname, "Vector2", v)
	end
	return D[v]
end
function V2M.Dot(a, b)
	local x = selfData(V2MT, a, "Dot")
	local y = v2arg(b, 1, "Dot")
	return x[1] * y[1] + x[2] * y[2]
end
function V2M.Cross(a, b)
	local x = selfData(V2MT, a, "Cross")
	local y = v2arg(b, 1, "Cross")
	return x[1] * y[2] - x[2] * y[1]
end
function V2M.Lerp(a, b, t)
	local x = selfData(V2MT, a, "Lerp")
	local y = v2arg(b, 1, "Lerp")
	t = checkNum(t, 2, "Lerp")
	return V2(x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t)
end
function V2M.FuzzyEq(a, b, eps)
	local x = selfData(V2MT, a, "FuzzyEq")
	local y = v2arg(b, 1, "FuzzyEq")
	eps = optNum(eps, 2, "FuzzyEq", 1e-5)
	return abs(x[1] - y[1]) <= eps and abs(x[2] - y[2]) <= eps
end
function V2M.Abs(a)
	local x = selfData(V2MT, a, "Abs")
	return V2(abs(x[1]), abs(x[2]))
end
function V2M.Floor(a)
	local x = selfData(V2MT, a, "Floor")
	return V2(floor(x[1]), floor(x[2]))
end
function V2M.Ceil(a)
	local x = selfData(V2MT, a, "Ceil")
	return V2(math.ceil(x[1]), math.ceil(x[2]))
end
function V2M.Sign(a)
	local x = selfData(V2MT, a, "Sign")
	return V2(sign(x[1]), sign(x[2]))
end
function V2M.Min(a, ...)
	local x = selfData(V2MT, a, "Min")
	local r1, r2 = x[1], x[2]
	for i = 1, select("#", ...) do
		local y = v2arg(select(i, ...), i, "Min")
		r1, r2 = math.min(r1, y[1]), math.min(r2, y[2])
	end
	return V2(r1, r2)
end
function V2M.Max(a, ...)
	local x = selfData(V2MT, a, "Max")
	local r1, r2 = x[1], x[2]
	for i = 1, select("#", ...) do
		local y = v2arg(select(i, ...), i, "Max")
		r1, r2 = math.max(r1, y[1]), math.max(r2, y[2])
	end
	return V2(r1, r2)
end
function V2M.Angle(a, b, sgn)
	local x = selfData(V2MT, a, "Angle")
	local y = v2arg(b, 1, "Angle")
	local ang = atan2(x[1] * y[2] - x[2] * y[1], x[1] * y[1] + x[2] * y[2])
	if not sgn then
		ang = abs(ang)
	end
	return ang
end
V2M.lerp = V2M.Lerp
makeAccess(V2MT, "Vector2", V2Get, V2M)
V2MT.__add = function(a, b)
	if isV2(a) and isV2(b) then
		local x, y = D[a], D[b]
		return V2(x[1] + y[1], x[2] + y[2])
	end
	arithError("add", a, b)
end
V2MT.__sub = function(a, b)
	if isV2(a) and isV2(b) then
		local x, y = D[a], D[b]
		return V2(x[1] - y[1], x[2] - y[2])
	end
	arithError("sub", a, b)
end
V2MT.__mul = function(a, b)
	if isV2(a) then
		local x = D[a]
		if isV2(b) then
			local y = D[b]
			return V2(x[1] * y[1], x[2] * y[2])
		elseif type(b) == "number" then
			return V2(x[1] * b, x[2] * b)
		end
	elseif type(a) == "number" and isV2(b) then
		local y = D[b]
		return V2(a * y[1], a * y[2])
	end
	arithError("mul", a, b)
end
V2MT.__div = function(a, b)
	if isV2(a) then
		local x = D[a]
		if isV2(b) then
			local y = D[b]
			return V2(x[1] / y[1], x[2] / y[2])
		elseif type(b) == "number" then
			return V2(x[1] / b, x[2] / b)
		end
	elseif type(a) == "number" and isV2(b) then
		local y = D[b]
		return V2(a / y[1], a / y[2])
	end
	arithError("div", a, b)
end
V2MT.__unm = function(a)
	local x = D[a]
	return V2(-x[1], -x[2])
end
V2MT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2]
end
V2MT.__tostring = function(a)
	local x = D[a]
	return numStr(x[1]) .. ", " .. numStr(x[2])
end
local Vector2 = {}
function Vector2.new(x, y)
	return V2(optNum(x, 1, "new", 0), optNum(y, 2, "new", 0))
end
Vector2.zero = V2(0, 0)
Vector2.one = V2(1, 1)
Vector2.xAxis = V2(1, 0)
Vector2.yAxis = V2(0, 1)

-- ============================================================================
-- CFrame: ตำแหน่ง + เมทริกซ์หมุน 3x3 จริง (แถว r00..r22) แบบเดียวกับ Roblox
-- LookVector = -คอลัมน์ที่ 3, RightVector = คอลัมน์ 1, UpVector = คอลัมน์ 2
-- ============================================================================
local CFMT, mkCF = newType("CFrame")
local function CF(x, y, z, a, b, c, d, e, f, g, h, i)
	return mkCF({ x, y, z, a, b, c, d, e, f, g, h, i })
end
local function isCF(v)
	return getmt(v) == CFMT
end
-- คูณแบบคืนตารางดิบ (ไม่สร้าง userdata) ใช้ในงานภายในที่ทำบ่อย เช่น PivotTo
local function cfMulRaw(A, B)
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = unpack(A, 1, 12)
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = unpack(B, 1, 12)
	return {
		a00 * bx + a01 * by + a02 * bz + ax,
		a10 * bx + a11 * by + a12 * bz + ay,
		a20 * bx + a21 * by + a22 * bz + az,
		a00 * b00 + a01 * b10 + a02 * b20, a00 * b01 + a01 * b11 + a02 * b21, a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20, a10 * b01 + a11 * b11 + a12 * b21, a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20, a20 * b01 + a21 * b11 + a22 * b21, a20 * b02 + a21 * b12 + a22 * b22,
	}
end
local function cfMul(A, B)
	return mkCF(cfMulRaw(A, B))
end
local function cfInvData(A)
	local x, y, z, a, b, c, d, e, f, g, h, i = unpack(A, 1, 12)
	return { -(a * x + d * y + g * z), -(b * x + e * y + h * z), -(c * x + f * y + i * z), a, d, g, b, e, h, c, f, i }
end
local function cfPoint(A, px, py, pz)
	return A[4] * px + A[5] * py + A[6] * pz + A[1], A[7] * px + A[8] * py + A[9] * pz + A[2], A[10] * px + A[11] * py + A[12] * pz + A[3]
end
local function cfVector(A, px, py, pz)
	return A[4] * px + A[5] * py + A[6] * pz, A[7] * px + A[8] * py + A[9] * pz, A[10] * px + A[11] * py + A[12] * pz
end
local function cfVectorInv(A, px, py, pz)
	return A[4] * px + A[7] * py + A[10] * pz, A[5] * px + A[8] * py + A[11] * pz, A[6] * px + A[9] * py + A[12] * pz
end

local function matXYZ(rx, ry, rz)
	local ca, sa, cb, sb, cc, sc = cos(rx), sin(rx), cos(ry), sin(ry), cos(rz), sin(rz)
	return cb * cc, -cb * sc, sb,
		ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb,
		sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb
end
local function matYXZ(rx, ry, rz)
	local ca, sa, cb, sb, cc, sc = cos(rx), sin(rx), cos(ry), sin(ry), cos(rz), sin(rz)
	return cb * cc + sb * sa * sc, -cb * sc + sb * sa * cc, sb * ca,
		ca * sc, ca * cc, -sa,
		-sb * cc + cb * sa * sc, sb * sc + cb * sa * cc, cb * ca
end
local function clamp1(v)
	if v > 1 then
		return 1
	elseif v < -1 then
		return -1
	end
	return v
end
local function eulerXYZ(A)
	return atan2(-A[9], A[12]), asin(clamp1(A[6])), atan2(-A[5], A[4])
end
local function eulerYXZ(A)
	return asin(clamp1(-A[9])), atan2(A[6], A[12]), atan2(A[7], A[8])
end
local function toQuat(a, b, c, d, e, f, g, h, i)
	local tr = a + e + i
	if tr > 0 then
		local s = sqrt(1 + tr) * 2
		return (h - f) / s, (c - g) / s, (d - b) / s, 0.25 * s
	elseif a > e and a > i then
		local s = sqrt(1 + a - e - i) * 2
		return 0.25 * s, (b + d) / s, (c + g) / s, (h - f) / s
	elseif e > i then
		local s = sqrt(1 + e - a - i) * 2
		return (b + d) / s, 0.25 * s, (f + h) / s, (c - g) / s
	else
		local s = sqrt(1 + i - a - e) * 2
		return (c + g) / s, (f + h) / s, 0.25 * s, (d - b) / s
	end
end
local function quatMat(x, y, z, w)
	local n = sqrt(x * x + y * y + z * z + w * w)
	if n == 0 then
		return 1, 0, 0, 0, 1, 0, 0, 0, 1
	end
	x, y, z, w = x / n, y / n, z / n, w / n
	return 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)
end
local function axisAngleMat(ax, ay, az, t)
	local m = sqrt(ax * ax + ay * ay + az * az)
	if m == 0 then
		return 1, 0, 0, 0, 1, 0, 0, 0, 1
	end
	ax, ay, az = ax / m, ay / m, az / m
	local c, s = cos(t), sin(t)
	local k = 1 - c
	return k * ax * ax + c, k * ax * ay - s * az, k * ax * az + s * ay,
		k * ax * ay + s * az, k * ay * ay + c, k * ay * az - s * ax,
		k * ax * az - s * ay, k * ay * az + s * ax, k * az * az + c
end
local function lookAtData(px, py, pz, tx, ty, tz, ux, uy, uz)
	local lx, ly, lz = tx - px, ty - py, tz - pz
	local lm = sqrt(lx * lx + ly * ly + lz * lz)
	if lm < 1e-12 then
		return { px, py, pz, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	lx, ly, lz = lx / lm, ly / lm, lz / lm
	-- right = look x up
	local rx, ry, rz = ly * uz - lz * uy, lz * ux - lx * uz, lx * uy - ly * ux
	local rm = sqrt(rx * rx + ry * ry + rz * rz)
	if rm < 1e-9 then
		-- มองขนานกับ up พอดี: ใช้แกน X เป็น right แบบเดียวกับ Roblox
		rx, ry, rz = 1, 0, 0
		local d = rx * lx
		rx, ry, rz = rx - d * lx, ry - d * ly, rz - d * lz
		rm = sqrt(rx * rx + ry * ry + rz * rz)
		if rm < 1e-9 then
			rx, ry, rz, rm = 0, 0, 1, 1
		end
	end
	rx, ry, rz = rx / rm, ry / rm, rz / rm
	-- up' = right x look
	local vx, vy, vz = ry * lz - rz * ly, rz * lx - rx * lz, rx * ly - ry * lx
	return { px, py, pz, rx, vx, -lx, ry, vy, -ly, rz, vz, -lz }
end

local function cfArg(v, i, fname)
	if not isCF(v) then
		badArg(i, fname, "CFrame", v)
	end
	return D[v]
end

local CFGet = {
	X = function(d) return d[1] end,
	Y = function(d) return d[2] end,
	Z = function(d) return d[3] end,
	Position = function(d) return V3(d[1], d[2], d[3]) end,
	Rotation = function(d) return CF(0, 0, 0, d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12]) end,
	LookVector = function(d) return V3(-d[6], -d[9], -d[12]) end,
	RightVector = function(d) return V3(d[4], d[7], d[10]) end,
	UpVector = function(d) return V3(d[5], d[8], d[11]) end,
	XVector = function(d) return V3(d[4], d[7], d[10]) end,
	YVector = function(d) return V3(d[5], d[8], d[11]) end,
	ZVector = function(d) return V3(d[6], d[9], d[12]) end,
}
CFGet.x, CFGet.y, CFGet.z, CFGet.p = CFGet.X, CFGet.Y, CFGet.Z, CFGet.Position
CFGet.lookVector, CFGet.rightVector, CFGet.upVector = CFGet.LookVector, CFGet.RightVector, CFGet.UpVector

local CFM = {}
function CFM.Inverse(a)
	return mkCF(cfInvData(selfData(CFMT, a, "Inverse")))
end
local function slerp(ax, ay, az, aw, bx, by, bz, bw, t)
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end
	if dot > 0.9995 then
		return ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
	end
	local th = acos(dot)
	local s = sin(th)
	local wa, wb = sin((1 - t) * th) / s, sin(t * th) / s
	return ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
end
function CFM.Lerp(a, b, t)
	local A = selfData(CFMT, a, "Lerp")
	local B = cfArg(b, 1, "Lerp")
	t = checkNum(t, 2, "Lerp")
	local qx, qy, qz, qw = toQuat(unpack(A, 4, 12))
	local rx, ry, rz, rw = toQuat(unpack(B, 4, 12))
	local m = { quatMat(slerp(qx, qy, qz, qw, rx, ry, rz, rw, t)) }
	return CF(A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t, A[3] + (B[3] - A[3]) * t, unpack(m, 1, 9))
end
function CFM.ToWorldSpace(a, ...)
	local A = selfData(CFMT, a, "ToWorldSpace")
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfMul(A, cfArg(select(i, ...), i, "ToWorldSpace"))
	end
	return unpack(out, 1, n)
end
function CFM.ToObjectSpace(a, ...)
	local inv = cfInvData(selfData(CFMT, a, "ToObjectSpace"))
	local out = {}
	local n = select("#", ...)
	for i = 1, n do
		out[i] = cfMul(inv, cfArg(select(i, ...), i, "ToObjectSpace"))
	end
	return unpack(out, 1, n)
end
function CFM.PointToWorldSpace(a, ...)
	local A = selfData(CFMT, a, "PointToWorldSpace")
	local out, n = {}, select("#", ...)
	for i = 1, n do
		local v = v3arg(select(i, ...), i, "PointToWorldSpace")
		out[i] = V3(cfPoint(A, v[1], v[2], v[3]))
	end
	return unpack(out, 1, n)
end
function CFM.PointToObjectSpace(a, ...)
	local inv = cfInvData(selfData(CFMT, a, "PointToObjectSpace"))
	local out, n = {}, select("#", ...)
	for i = 1, n do
		local v = v3arg(select(i, ...), i, "PointToObjectSpace")
		out[i] = V3(cfPoint(inv, v[1], v[2], v[3]))
	end
	return unpack(out, 1, n)
end
function CFM.VectorToWorldSpace(a, ...)
	local A = selfData(CFMT, a, "VectorToWorldSpace")
	local out, n = {}, select("#", ...)
	for i = 1, n do
		local v = v3arg(select(i, ...), i, "VectorToWorldSpace")
		out[i] = V3(cfVector(A, v[1], v[2], v[3]))
	end
	return unpack(out, 1, n)
end
function CFM.VectorToObjectSpace(a, ...)
	local A = selfData(CFMT, a, "VectorToObjectSpace")
	local out, n = {}, select("#", ...)
	for i = 1, n do
		local v = v3arg(select(i, ...), i, "VectorToObjectSpace")
		out[i] = V3(cfVectorInv(A, v[1], v[2], v[3]))
	end
	return unpack(out, 1, n)
end
function CFM.GetComponents(a)
	return unpack(selfData(CFMT, a, "GetComponents"), 1, 12)
end
function CFM.ToEulerAnglesXYZ(a)
	return eulerXYZ(selfData(CFMT, a, "ToEulerAnglesXYZ"))
end
function CFM.ToEulerAnglesYXZ(a)
	return eulerYXZ(selfData(CFMT, a, "ToEulerAnglesYXZ"))
end
function CFM.ToOrientation(a)
	return eulerYXZ(selfData(CFMT, a, "ToOrientation"))
end
function CFM.ToAxisAngle(a)
	local A = selfData(CFMT, a, "ToAxisAngle")
	local x, y, z, w = toQuat(unpack(A, 4, 12))
	if w < 0 then
		x, y, z, w = -x, -y, -z, -w
	end
	local ang = 2 * acos(clamp1(w))
	local s = sqrt(1 - w * w)
	if s < 1e-9 then
		return V3(1, 0, 0), 0
	end
	return V3(x / s, y / s, z / s), ang
end
function CFM.FuzzyEq(a, b, eps)
	local A = selfData(CFMT, a, "FuzzyEq")
	local B = cfArg(b, 1, "FuzzyEq")
	eps = optNum(eps, 2, "FuzzyEq", 1e-5)
	for i = 1, 12 do
		if abs(A[i] - B[i]) > eps then
			return false
		end
	end
	return true
end
function CFM.Orthonormalize(a)
	local A = selfData(CFMT, a, "Orthonormalize")
	local x, y, z, w = toQuat(unpack(A, 4, 12))
	return CF(A[1], A[2], A[3], quatMat(x, y, z, w))
end
CFM.inverse, CFM.lerp, CFM.toWorldSpace, CFM.toObjectSpace = CFM.Inverse, CFM.Lerp, CFM.ToWorldSpace, CFM.ToObjectSpace
CFM.pointToWorldSpace, CFM.pointToObjectSpace = CFM.PointToWorldSpace, CFM.PointToObjectSpace
CFM.vectorToWorldSpace, CFM.vectorToObjectSpace = CFM.VectorToWorldSpace, CFM.VectorToObjectSpace
CFM.components, CFM.toEulerAnglesXYZ, CFM.toEulerAnglesYXZ, CFM.toAxisAngle = CFM.GetComponents, CFM.ToEulerAnglesXYZ, CFM.ToEulerAnglesYXZ, CFM.ToAxisAngle
makeAccess(CFMT, "CFrame", CFGet, CFM)

CFMT.__mul = function(a, b)
	if isCF(a) then
		if isCF(b) then
			return cfMul(D[a], D[b])
		elseif isV3(b) then
			local v = D[b]
			return V3(cfPoint(D[a], v[1], v[2], v[3]))
		end
	end
	arithError("mul", a, b)
end
CFMT.__add = function(a, b)
	if isCF(a) and isV3(b) then
		local A, v = D[a], D[b]
		return CF(A[1] + v[1], A[2] + v[2], A[3] + v[3], unpack(A, 4, 12))
	end
	arithError("add", a, b)
end
CFMT.__sub = function(a, b)
	if isCF(a) and isV3(b) then
		local A, v = D[a], D[b]
		return CF(A[1] - v[1], A[2] - v[2], A[3] - v[3], unpack(A, 4, 12))
	end
	arithError("sub", a, b)
end
CFMT.__eq = function(a, b)
	local A, B = D[a], D[b]
	for i = 1, 12 do
		if A[i] ~= B[i] then
			return false
		end
	end
	return true
end
CFMT.__tostring = function(a)
	local A, parts = D[a], {}
	for i = 1, 12 do
		parts[i] = numStr(A[i])
	end
	return tconcat(parts, ", ")
end

local CFrame = {}
function CFrame.new(...)
	local n = select("#", ...)
	local a1, a2 = ...
	if n == 0 then
		return CF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if isV3(a1) then
		local p = D[a1]
		if n >= 2 and a2 ~= nil then
			local t = v3arg(a2, 2, "new")
			return mkCF(lookAtData(p[1], p[2], p[3], t[1], t[2], t[3], 0, 1, 0))
		end
		return CF(p[1], p[2], p[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local args = { ... }
	for i = 1, n do
		args[i] = checkNum(args[i], i, "new")
	end
	if n == 3 then
		return CF(args[1], args[2], args[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 7 then
		return CF(args[1], args[2], args[3], quatMat(args[4], args[5], args[6], args[7]))
	elseif n == 12 then
		return CF(unpack(args, 1, 12))
	end
	throw(fmt("Invalid number of arguments: %d", n))
end
function CFrame.lookAt(at, target, up)
	local p = v3arg(at, 1, "lookAt")
	local t = v3arg(target, 2, "lookAt")
	local u = up ~= nil and v3arg(up, 3, "lookAt") or { 0, 1, 0 }
	return mkCF(lookAtData(p[1], p[2], p[3], t[1], t[2], t[3], u[1], u[2], u[3]))
end
function CFrame.Angles(rx, ry, rz)
	return CF(0, 0, 0, matXYZ(optNum(rx, 1, "Angles", 0), optNum(ry, 2, "Angles", 0), optNum(rz, 3, "Angles", 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return CF(0, 0, 0, matYXZ(optNum(rx, 1, "fromEulerAnglesYXZ", 0), optNum(ry, 2, "fromEulerAnglesYXZ", 0), optNum(rz, 3, "fromEulerAnglesYXZ", 0)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz, order)
	if order ~= nil and order ~= "XYZ" and typeOf(order) ~= "EnumItem" then
		badArg(4, "fromEulerAngles", "EnumItem", order)
	end
	return CFrame.Angles(rx, ry, rz)
end
function CFrame.fromAxisAngle(axis, angle)
	local v = v3arg(axis, 1, "fromAxisAngle")
	return CF(0, 0, 0, axisAngleMat(v[1], v[2], v[3], checkNum(angle, 2, "fromAxisAngle")))
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	local p = v3arg(pos, 1, "fromMatrix")
	local x = v3arg(vx, 2, "fromMatrix")
	local y = v3arg(vy, 3, "fromMatrix")
	local z
	if vz ~= nil then
		z = v3arg(vz, 4, "fromMatrix")
	else
		local cx, cy, cz = x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1]
		local m = sqrt(cx * cx + cy * cy + cz * cz)
		z = { cx / m, cy / m, cz / m }
	end
	return CF(p[1], p[2], p[3], x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3])
end
CFrame.identity = CF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

	R.cfMulRaw = cfMulRaw
	R.V3MT = V3MT
	R.V3 = V3
	R.isV3 = isV3
	R.v3arg = v3arg
	R.Vector3 = Vector3
	R.V2MT = V2MT
	R.V2 = V2
	R.isV2 = isV2
	R.v2arg = v2arg
	R.Vector2 = Vector2
	R.CFMT = CFMT
	R.CF = CF
	R.mkCF = mkCF
	R.isCF = isCF
	R.cfArg = cfArg
	R.cfMul = cfMul
	R.cfInvData = cfInvData
	R.cfPoint = cfPoint
	R.cfVector = cfVector
	R.cfVectorInv = cfVectorInv
	R.CFrame = CFrame
	R.sign = sign
	R.matYXZ = matYXZ
	R.matXYZ = matXYZ
	R.eulerYXZ = eulerYXZ
	R.eulerXYZ = eulerXYZ
	R.lookAtData = lookAtData
	R.toQuat = toQuat
	R.quatMat = quatMat
	R.slerp = slerp
	R.clamp1 = clamp1
end

do
	local V2, isV2, v2arg = R.V2, R.isV2, R.v2arg
-- ============================================================================
-- Color3 / BrickColor
-- ============================================================================
local C3MT, mkC3 = newType("Color3")
local function C3(r, g, b)
	return mkC3({ r, g, b })
end
local function RGB(r, g, b)
	return C3(r / 255, g / 255, b / 255)
end
local function isC3(v)
	return getmt(v) == C3MT
end
local function toHSV(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local dl = mx - mn
	local h = 0
	if dl > 0 then
		if mx == r then
			h = ((g - b) / dl) % 6
		elseif mx == g then
			h = (b - r) / dl + 2
		else
			h = (r - g) / dl + 4
		end
		h = h / 6
	end
	local s = 0
	if mx > 0 then
		s = dl / mx
	end
	return h, s, mx
end
local C3Get = {
	R = function(d) return d[1] end,
	G = function(d) return d[2] end,
	B = function(d) return d[3] end,
}
C3Get.r, C3Get.g, C3Get.b = C3Get.R, C3Get.G, C3Get.B
local C3M = {}
function C3M.Lerp(a, b, t)
	local x = selfData(C3MT, a, "Lerp")
	if not isC3(b) then
		badArg(1, "Lerp", "Color3", b)
	end
	local y = D[b]
	t = checkNum(t, 2, "Lerp")
	return C3(x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t)
end
function C3M.ToHSV(a)
	local x = selfData(C3MT, a, "ToHSV")
	return toHSV(x[1], x[2], x[3])
end
local function to255(v)
	local n = floor(v * 255 + 0.5)
	if n < 0 then
		n = 0
	elseif n > 255 then
		n = 255
	end
	return n
end
function C3M.ToHex(a)
	local x = selfData(C3MT, a, "ToHex")
	return fmt("%02x%02x%02x", to255(x[1]), to255(x[2]), to255(x[3]))
end
C3M.lerp = C3M.Lerp
makeAccess(C3MT, "Color3", C3Get, C3M)
C3MT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2] and x[3] == y[3]
end
C3MT.__tostring = function(a)
	local x = D[a]
	return numStr(x[1]) .. ", " .. numStr(x[2]) .. ", " .. numStr(x[3])
end
local function hsv(h, s, v)
	h = (h % 1) * 6
	local i = floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end
local Color3 = {}
function Color3.new(r, g, b)
	return C3(optNum(r, 1, "new", 0), optNum(g, 2, "new", 0), optNum(b, 3, "new", 0))
end
function Color3.fromRGB(r, g, b)
	return RGB(optNum(r, 1, "fromRGB", 0), optNum(g, 2, "fromRGB", 0), optNum(b, 3, "fromRGB", 0))
end
function Color3.fromHSV(h, s, v)
	return C3(hsv(checkNum(h, 1, "fromHSV"), checkNum(s, 2, "fromHSV"), checkNum(v, 3, "fromHSV")))
end
function Color3.toHSV(c)
	if not isC3(c) then
		badArg(1, "toHSV", "Color3", c)
	end
	local x = D[c]
	return toHSV(x[1], x[2], x[3])
end
function Color3.fromHex(hex)
	if type(hex) ~= "string" then
		badArg(1, "fromHex", "string", hex)
	end
	local h = hex:gsub("^#", "")
	if #h == 3 then
		h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
	end
	if #h ~= 6 or h:find("[^%x]") then
		throw("Unable to convert characters to hex value")
	end
	return RGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

local BCMT, mkBC = newType("BrickColor")
-- จานสีบางส่วนของ BrickColor จริง (number, name, r, g, b)
local BRICK_PALETTE = {
	{ 1, "White", 242, 243, 243 }, { 2, "Grey", 161, 165, 162 }, { 5, "Brick yellow", 215, 197, 154 },
	{ 18, "Nougat", 204, 142, 105 }, { 21, "Bright red", 196, 40, 28 }, { 23, "Bright blue", 13, 105, 172 },
	{ 24, "Bright yellow", 245, 205, 48 }, { 26, "Black", 27, 42, 53 }, { 28, "Dark green", 40, 127, 71 },
	{ 37, "Bright green", 75, 151, 75 }, { 38, "Dark orange", 160, 95, 53 }, { 102, "Medium blue", 110, 153, 202 },
	{ 106, "Bright orange", 218, 133, 65 }, { 119, "Br. yellowish green", 164, 189, 71 }, { 141, "Earth green", 39, 70, 45 },
	{ 192, "Reddish brown", 105, 64, 40 }, { 194, "Medium stone grey", 163, 162, 165 }, { 199, "Dark stone grey", 99, 95, 98 },
	{ 1001, "Institutional white", 248, 248, 248 }, { 1002, "Mid gray", 205, 205, 205 }, { 1003, "Really black", 17, 17, 17 },
	{ 1004, "Really red", 255, 0, 0 }, { 1005, "Deep orange", 255, 176, 0 }, { 1009, "New Yeller", 255, 255, 0 },
	{ 1010, "Really blue", 0, 0, 255 }, { 1011, "Navy blue", 0, 32, 96 }, { 1013, "Cyan", 4, 175, 236 },
	{ 1015, "Magenta", 170, 0, 170 }, { 1016, "Pink", 255, 102, 204 }, { 1019, "Toothpaste", 0, 255, 255 },
	{ 1020, "Lime green", 0, 255, 0 }, { 1032, "Hot pink", 255, 0, 191 },
}
local BC_BY_NUM, BC_BY_NAME = {}, {}
for _, e in ipairs(BRICK_PALETTE) do
	BC_BY_NUM[e[1]] = e
	BC_BY_NAME[e[2]] = e
end
local BC_CACHE = {}
local function BC(entry)
	local p = BC_CACHE[entry[1]]
	if not p then
		p = mkBC({ entry = entry, color = RGB(entry[3], entry[4], entry[5]) })
		BC_CACHE[entry[1]] = p
	end
	return p
end
local function nearestBrick(r, g, b)
	local best, bd = BC_BY_NUM[194], huge
	for _, e in ipairs(BRICK_PALETTE) do
		local dr, dg, db = e[3] - r * 255, e[4] - g * 255, e[5] - b * 255
		local dist = dr * dr + dg * dg + db * db
		if dist < bd then
			best, bd = e, dist
		end
	end
	return BC(best)
end
local BCGet = {
	Name = function(d) return d.entry[2] end,
	Number = function(d) return d.entry[1] end,
	Color = function(d) return d.color end,
	r = function(d) return d.entry[3] / 255 end,
	g = function(d) return d.entry[4] / 255 end,
	b = function(d) return d.entry[5] / 255 end,
}
makeAccess(BCMT, "BrickColor", BCGet, {})
BCMT.__tostring = function(a)
	return D[a].entry[2]
end
BCMT.__eq = function(a, b)
	return D[a].entry == D[b].entry
end
local BrickColor = {}
function BrickColor.new(a, b, c)
	if type(a) == "string" then
		local e = BC_BY_NAME[a]
		if not e then
			-- Roblox จริงไม่ error แต่คืน Medium stone grey -> บันทึกคำเตือนไว้ให้เทสเห็น
			if R.warnHook then
				R.warnHook(fmt("BrickColor.new(%q): unknown BrickColor name, using Medium stone grey", a))
			end
			e = BC_BY_NUM[194]
		end
		return BC(e)
	elseif type(a) == "number" and b == nil then
		return BC(BC_BY_NUM[a] or BC_BY_NUM[194])
	elseif type(a) == "number" then
		return nearestBrick(a, checkNum(b, 2, "new"), checkNum(c, 3, "new"))
	elseif isC3(a) then
		local x = D[a]
		return nearestBrick(x[1], x[2], x[3])
	end
	badArg(1, "new", "string", a)
end
function BrickColor.palette(i)
	return BC(BRICK_PALETTE[(checkNum(i, 1, "palette") % #BRICK_PALETTE) + 1])
end
function BrickColor.random()
	return BC(BRICK_PALETTE[math.random(1, #BRICK_PALETTE)])
end
BrickColor.White = function() return BC(BC_BY_NUM[1]) end
BrickColor.Gray = function() return BC(BC_BY_NUM[194]) end
BrickColor.DarkGray = function() return BC(BC_BY_NUM[199]) end
BrickColor.Black = function() return BC(BC_BY_NUM[26]) end
BrickColor.Red = function() return BC(BC_BY_NUM[21]) end
BrickColor.Yellow = function() return BC(BC_BY_NUM[24]) end
BrickColor.Green = function() return BC(BC_BY_NUM[28]) end
BrickColor.Blue = function() return BC(BC_BY_NUM[23]) end

-- ============================================================================
-- UDim / UDim2 / Rect / NumberRange / Sequences
-- ============================================================================
local UDMT, mkUD = newType("UDim")
local function UD(s, o)
	return mkUD({ s, o })
end
local function isUD(v)
	return getmt(v) == UDMT
end
makeAccess(UDMT, "UDim", { Scale = function(d) return d[1] end, Offset = function(d) return d[2] end }, {})
UDMT.__add = function(a, b)
	if isUD(a) and isUD(b) then
		return UD(D[a][1] + D[b][1], D[a][2] + D[b][2])
	end
	arithError("add", a, b)
end
UDMT.__sub = function(a, b)
	if isUD(a) and isUD(b) then
		return UD(D[a][1] - D[b][1], D[a][2] - D[b][2])
	end
	arithError("sub", a, b)
end
UDMT.__unm = function(a)
	return UD(-D[a][1], -D[a][2])
end
UDMT.__eq = function(a, b)
	return D[a][1] == D[b][1] and D[a][2] == D[b][2]
end
UDMT.__tostring = function(a)
	return numStr(D[a][1]) .. ", " .. numStr(D[a][2])
end
local UDim = {}
function UDim.new(s, o)
	return UD(optNum(s, 1, "new", 0), optNum(o, 2, "new", 0))
end

local U2MT, mkU2 = newType("UDim2")
local function U2(xs, xo, ys, yo)
	return mkU2({ xs, xo, ys, yo })
end
local function isU2(v)
	return getmt(v) == U2MT
end
local U2Get = {
	X = function(d) return UD(d[1], d[2]) end,
	Y = function(d) return UD(d[3], d[4]) end,
}
U2Get.Width, U2Get.Height = U2Get.X, U2Get.Y
local U2M = {}
function U2M.Lerp(a, b, t)
	local x = selfData(U2MT, a, "Lerp")
	if not isU2(b) then
		badArg(1, "Lerp", "UDim2", b)
	end
	local y = D[b]
	t = checkNum(t, 2, "Lerp")
	return U2(x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t, x[4] + (y[4] - x[4]) * t)
end
makeAccess(U2MT, "UDim2", U2Get, U2M)
U2MT.__add = function(a, b)
	if isU2(a) and isU2(b) then
		local x, y = D[a], D[b]
		return U2(x[1] + y[1], x[2] + y[2], x[3] + y[3], x[4] + y[4])
	end
	arithError("add", a, b)
end
U2MT.__sub = function(a, b)
	if isU2(a) and isU2(b) then
		local x, y = D[a], D[b]
		return U2(x[1] - y[1], x[2] - y[2], x[3] - y[3], x[4] - y[4])
	end
	arithError("sub", a, b)
end
U2MT.__unm = function(a)
	local x = D[a]
	return U2(-x[1], -x[2], -x[3], -x[4])
end
U2MT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2] and x[3] == y[3] and x[4] == y[4]
end
U2MT.__tostring = function(a)
	local x = D[a]
	return fmt("{%s, %s}, {%s, %s}", numStr(x[1]), numStr(x[2]), numStr(x[3]), numStr(x[4]))
end
local UDim2 = {}
function UDim2.new(a, b, c, d)
	if isUD(a) or isUD(b) then
		local x = isUD(a) and D[a] or { 0, 0 }
		local y = isUD(b) and D[b] or { 0, 0 }
		if a ~= nil and not isUD(a) then
			badArg(1, "new", "UDim", a)
		end
		if b ~= nil and not isUD(b) then
			badArg(2, "new", "UDim", b)
		end
		return U2(x[1], x[2], y[1], y[2])
	end
	return U2(optNum(a, 1, "new", 0), optNum(b, 2, "new", 0), optNum(c, 3, "new", 0), optNum(d, 4, "new", 0))
end
function UDim2.fromScale(x, y)
	return U2(optNum(x, 1, "fromScale", 0), 0, optNum(y, 2, "fromScale", 0), 0)
end
function UDim2.fromOffset(x, y)
	return U2(0, optNum(x, 1, "fromOffset", 0), 0, optNum(y, 2, "fromOffset", 0))
end

local RectMT, mkRect = newType("Rect")
makeAccess(RectMT, "Rect", {
	Min = function(d) return V2(d[1], d[2]) end,
	Max = function(d) return V2(d[3], d[4]) end,
	Width = function(d) return d[3] - d[1] end,
	Height = function(d) return d[4] - d[2] end,
}, {})
RectMT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2] and x[3] == y[3] and x[4] == y[4]
end
RectMT.__tostring = function(a)
	local x = D[a]
	return fmt("%s, %s, %s, %s", numStr(x[1]), numStr(x[2]), numStr(x[3]), numStr(x[4]))
end
local Rect = {}
function Rect.new(a, b, c, d)
	if isV2(a) then
		local p, q = D[a], v2arg(b, 2, "new")
		return mkRect({ p[1], p[2], q[1], q[2] })
	end
	return mkRect({ optNum(a, 1, "new", 0), optNum(b, 2, "new", 0), optNum(c, 3, "new", 0), optNum(d, 4, "new", 0) })
end

local NRMT, mkNR = newType("NumberRange")
makeAccess(NRMT, "NumberRange", { Min = function(d) return d[1] end, Max = function(d) return d[2] end }, {})
NRMT.__eq = function(a, b)
	return D[a][1] == D[b][1] and D[a][2] == D[b][2]
end
NRMT.__tostring = function(a)
	return numStr(D[a][1]) .. " " .. numStr(D[a][2])
end
local NumberRange = {}
function NumberRange.new(mn, mx)
	mn = checkNum(mn, 1, "new")
	mx = optNum(mx, 2, "new", mn)
	if mx < mn then
		throw("NumberRange: invalid range")
	end
	return mkNR({ mn, mx })
end

local NSKMT, mkNSK = newType("NumberSequenceKeypoint")
makeAccess(NSKMT, "NumberSequenceKeypoint", {
	Time = function(d) return d[1] end,
	Value = function(d) return d[2] end,
	Envelope = function(d) return d[3] end,
}, {})
NSKMT.__eq = function(a, b)
	return D[a][1] == D[b][1] and D[a][2] == D[b][2] and D[a][3] == D[b][3]
end
NSKMT.__tostring = function(a)
	return numStr(D[a][1]) .. " " .. numStr(D[a][2]) .. " " .. numStr(D[a][3])
end
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v, e)
	return mkNSK({ checkNum(t, 1, "new"), checkNum(v, 2, "new"), optNum(e, 3, "new", 0) })
end

local CSKMT, mkCSK = newType("ColorSequenceKeypoint")
makeAccess(CSKMT, "ColorSequenceKeypoint", {
	Time = function(d) return d[1] end,
	Value = function(d) return d[2] end,
}, {})
CSKMT.__eq = function(a, b)
	return D[a][1] == D[b][1] and D[a][2] == D[b][2]
end
CSKMT.__tostring = function(a)
	return numStr(D[a][1]) .. " " .. tostring(D[a][2])
end
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, c)
	if not isC3(c) then
		badArg(2, "new", "Color3", c)
	end
	return mkCSK({ checkNum(t, 1, "new"), c })
end

local function checkKeypoints(kps, kmt, tname)
	if type(kps) ~= "table" or #kps < 2 then
		throw(tname .. ": requires at least 2 keypoints")
	end
	local out = {}
	for i, k in ipairs(kps) do
		if getmt(k) ~= kmt then
			throw(tname .. ": all keypoints must be " .. tname .. "Keypoint")
		end
		if i > 1 and D[k][1] < D[kps[i - 1]][1] then
			throw(tname .. ": all keypoints must be ordered by time")
		end
		out[i] = k
	end
	if abs(D[out[1]][1]) > 1e-4 then
		throw(tname .. " must start at time=0.0")
	end
	if abs(D[out[#out]][1] - 1) > 1e-4 then
		throw(tname .. " must end at time=1.0")
	end
	return out
end
local NSMT, mkNS = newType("NumberSequence")
makeAccess(NSMT, "NumberSequence", {
	Keypoints = function(d)
		local c = {}
		for i, k in ipairs(d) do
			c[i] = k
		end
		return c
	end,
}, {})
NSMT.__eq = function(a, b)
	local x, y = D[a], D[b]
	if #x ~= #y then
		return false
	end
	for i = 1, #x do
		if x[i] ~= y[i] then
			return false
		end
	end
	return true
end
NSMT.__tostring = function(a)
	local parts = {}
	for i, k in ipairs(D[a]) do
		parts[i] = tostring(k)
	end
	return tconcat(parts, " ")
end
local NumberSequence = {}
function NumberSequence.new(a, b)
	if type(a) == "number" then
		local v1 = optNum(b, 2, "new", a)
		return mkNS({ mkNSK({ 0, a, 0 }), mkNSK({ 1, v1, 0 }) })
	end
	return mkNS(checkKeypoints(a, NSKMT, "NumberSequence"))
end

local CSMT, mkCS = newType("ColorSequence")
makeAccess(CSMT, "ColorSequence", {
	Keypoints = function(d)
		local c = {}
		for i, k in ipairs(d) do
			c[i] = k
		end
		return c
	end,
}, {})
CSMT.__eq = NSMT.__eq
CSMT.__tostring = NSMT.__tostring
local ColorSequence = {}
function ColorSequence.new(a, b)
	if isC3(a) then
		local c1 = a
		if b ~= nil then
			if not isC3(b) then
				badArg(2, "new", "Color3", b)
			end
			c1 = b
		end
		return mkCS({ mkCSK({ 0, a }), mkCSK({ 1, c1 }) })
	end
	return mkCS(checkKeypoints(a, CSKMT, "ColorSequence"))
end

	R.C3MT = C3MT
	R.C3 = C3
	R.RGB = RGB
	R.isC3 = isC3
	R.Color3 = Color3
	R.toHSV = toHSV
	R.BCMT = BCMT
	R.BC = BC
	R.BC_BY_NUM = BC_BY_NUM
	R.nearestBrick = nearestBrick
	R.BrickColor = BrickColor
	R.UDMT = UDMT
	R.UD = UD
	R.isUD = isUD
	R.UDim = UDim
	R.U2MT = U2MT
	R.U2 = U2
	R.isU2 = isU2
	R.UDim2 = UDim2
	R.RectMT = RectMT
	R.mkRect = mkRect
	R.Rect = Rect
	R.NRMT = NRMT
	R.mkNR = mkNR
	R.NumberRange = NumberRange
	R.NSKMT = NSKMT
	R.mkNSK = mkNSK
	R.NumberSequenceKeypoint = NumberSequenceKeypoint
	R.CSKMT = CSKMT
	R.mkCSK = mkCSK
	R.ColorSequenceKeypoint = ColorSequenceKeypoint
	R.NSMT = NSMT
	R.mkNS = mkNS
	R.NumberSequence = NumberSequence
	R.CSMT = CSMT
	R.mkCS = mkCS
	R.ColorSequence = ColorSequence
end

do
-- ============================================================================
-- Enum: รายการค่าจริงของ Roblox (เฉพาะชนิดที่เกมน่าจะใช้) เข้าถึงชื่อผิด -> error ทันที
-- ============================================================================
local ENUM_SRC = {
	UserInputType = "MouseButton1=0 MouseButton2=1 MouseButton3=2 MouseWheel=3 MouseMovement=4 Touch=7 Keyboard=8 Focus=9 Accelerometer=10 Gyro=11 Gamepad1=12 Gamepad2=13 Gamepad3=14 Gamepad4=15 Gamepad5=16 Gamepad6=17 Gamepad7=18 Gamepad8=19 TextInput=20 InputMethod=21 None=22",
	UserInputState = "Begin=0 Change=1 End=2 Cancel=3 None=4",
	Material = "Plastic=256 SmoothPlastic=272 Neon=288 Wood=512 WoodPlanks=528 Marble=784 Basalt=788 Slate=800 CrackedLava=804 Concrete=816 Limestone=820 Granite=832 Pavement=836 Brick=848 Pebble=864 Cobblestone=880 Rock=896 Sandstone=912 CorrodedMetal=1040 DiamondPlate=1056 Foil=1072 Metal=1088 Grass=1280 LeafyGrass=1284 Sand=1296 Fabric=1312 Snow=1328 Mud=1344 Ground=1360 Asphalt=1376 Salt=1392 Cardboard=1424 Carpet=1425 CeramicTiles=1426 ClayRoofTiles=1427 RoofShingles=1428 Leather=1429 Plaster=1430 Rubber=1431 Ice=1536 Glacier=1552 Glass=1568 ForceField=1584 Air=1792 Water=2048",
	Font = "Legacy=0 Arial=1 ArialBold=2 SourceSans=3 SourceSansBold=4 SourceSansLight=5 SourceSansItalic=6 Bodoni=7 Garamond=8 Cartoon=9 Code=10 Highway=11 SciFi=12 Arcade=13 Fantasy=14 Antique=15 SourceSansSemibold=16 Gotham=17 GothamMedium=18 GothamBold=19 GothamBlack=20 AmaticSC=21 Bangers=22 Creepster=23 DenkOne=24 Fondamento=25 FredokaOne=26 GrenzeGotisch=27 IndieFlower=28 JosefinSans=29 Jura=30 Kalam=31 LuckiestGuy=32 Merriweather=33 Michroma=34 Nunito=35 Oswald=36 PatrickHand=37 PermanentMarker=38 Roboto=39 RobotoCondensed=40 RobotoMono=41 Sarpanch=42 SpecialElite=43 TitilliumWeb=44 Ubuntu=45 BuilderSans=46 BuilderSansMedium=47 BuilderSansBold=48 BuilderSansExtraBold=49 Unknown=100",
	FontWeight = "Thin=100 ExtraLight=200 Light=300 Regular=400 Medium=500 SemiBold=600 Bold=700 ExtraBold=800 Heavy=900",
	FontStyle = "Normal=0 Italic=1",
	PartType = "Ball=0 Block=1 Cylinder=2 Wedge=3 CornerWedge=4",
	NormalId = "Right=0 Top=1 Back=2 Left=3 Bottom=4 Front=5",
	SurfaceType = "Smooth=0 Glue=1 Weld=2 Studs=3 Inlet=4 Universal=5 Hinge=6 Motor=7 SteppingMotor=8 SmoothNoOutlines=10",
	EasingStyle = "Linear=0 Sine=1 Back=2 Quad=3 Quart=4 Quint=5 Bounce=6 Elastic=7 Exponential=8 Circular=9 Cubic=10",
	EasingDirection = "In=0 Out=1 InOut=2",
	CameraType = "Fixed=0 Attach=1 Watch=2 Track=3 Follow=4 Custom=5 Scriptable=6 Orbital=7",
	RenderPriority = "First=0 Input=100 Camera=200 Character=300 Last=2000",
	CoreGuiType = "PlayerList=0 Health=1 Backpack=2 Chat=3 All=4 EmotesMenu=5 SelfView=6 Captures=7",
	ZIndexBehavior = "Global=0 Sibling=1",
	TextXAlignment = "Left=0 Right=1 Center=2",
	TextYAlignment = "Top=0 Center=1 Bottom=2",
	FillDirection = "Horizontal=0 Vertical=1",
	HorizontalAlignment = "Center=0 Left=1 Right=2",
	VerticalAlignment = "Center=0 Top=1 Bottom=2",
	SortOrder = "Name=0 Custom=1 LayoutOrder=2",
	AutomaticSize = "None=0 X=1 Y=2 XY=3",
	ScaleType = "Stretch=0 Slice=1 Tile=2 Fit=3 Crop=4",
	SurfaceGuiSizingMode = "FixedSize=0 PixelsPerStud=1",
	ApplyStrokeMode = "Contextual=0 Border=1",
	LineJoinMode = "Round=0 Bevel=1 Miter=2",
	SizeConstraint = "RelativeXY=0 RelativeXX=1 RelativeYY=2",
	AspectType = "FitWithinMaxSize=0 ScaleWithParentSize=1",
	DominantAxis = "Width=0 Height=1",
	PlaybackState = "Begin=0 Delayed=1 Playing=2 Paused=3 Completed=4 Cancelled=5",
	HumanoidStateType = "FallingDown=0 Ragdoll=1 GettingUp=2 Jumping=3 Swimming=4 Freefall=5 Flying=6 Landed=7 Running=8 RunningNoPhysics=10 StrafingNoPhysics=11 Climbing=12 Seated=13 PlatformStanding=14 Dead=15 Physics=16 None=18",
	ThumbnailType = "HeadShot=0 AvatarBust=1 AvatarThumbnail=2",
	ThumbnailSize = "Size48x48=0 Size180x180=1 Size420x420=2 Size60x60=3 Size100x100=4 Size150x150=5 Size352x352=6",
	TextTruncate = "None=0 AtEnd=1 SplitWord=2",
	BorderMode = "Outline=0 Middle=1 Inset=2",
	StartCorner = "TopLeft=0 TopRight=1 BottomLeft=2 BottomRight=3",
	HighlightDepthMode = "AlwaysOnTop=0 Occluded=1",
	MeshType = "Head=0 Torso=1 Wedge=2 Sphere=3 Cylinder=4 FileMesh=5 Brick=6 Prism=7 Pyramid=8 ParallelRamp=9 RightAngleRamp=10 CornerWedge=11",
	ContextActionResult = "Sink=0 Pass=1",
	ContextActionPriority = "Low=1000 Medium=2000 Default=2000 High=3000",
	ResamplerMode = "Default=0 Pixelated=1",
	Axis = "X=0 Y=1 Z=2",
	ScreenOrientation = "LandscapeLeft=0 LandscapeRight=1 LandscapeSensor=2 Portrait=3 Sensor=4",
	ScreenInsets = "None=0 DeviceSafeInsets=1 CoreUISafeInsets=2 TopbarSafeInsets=3",
	SafeAreaCompatibility = "None=0 FullscreenExtension=1",
	RollOffMode = "Inverse=0 Linear=1 LinearSquare=2 InverseTapered=3",
	ScrollingDirection = "X=1 Y=2 XY=4",
	ElasticBehavior = "WhenScrollable=0 Always=1 Never=2",
	ScrollBarInset = "None=0 ScrollBar=1 Always=2",
	VerticalScrollBarPosition = "Right=0 Left=1",
	RaycastFilterType = "Blacklist=0 Exclude=0 Whitelist=1 Include=1",
	HumanoidDisplayDistanceType = "Viewer=0 Subject=1 None=2",
	HumanoidHealthDisplayType = "DisplayWhenDamaged=0 AlwaysOn=1 AlwaysOff=2",
	HumanoidRigType = "R6=0 R15=1",
	RunContext = "Legacy=0 Server=1 Client=2 Plugin=3",
	CameraMode = "Classic=0 LockFirstPerson=1",
	MouseBehavior = "Default=0 LockCenter=1 LockCurrentPosition=2",
	ParticleOrientation = "FacingCamera=0 FacingCameraWorldUp=1 VelocityParallel=2 VelocityPerpendicular=3",
	ParticleEmitterShape = "Box=0 Sphere=1 Cylinder=2 Disc=3",
	ParticleEmitterShapeStyle = "Volume=0 Surface=1",
	ParticleEmitterShapeInOut = "Outward=0 Inward=1 InAndOut=2",
	SelectionBehavior = "Escape=0 Stop=1",
	TextDirection = "Auto=0 LeftToRight=1 RightToLeft=2",
	ButtonStyle = "Custom=0 RobloxButtonDefault=1 RobloxButton=2 RobloxRoundButton=3 RobloxRoundDefaultButton=4 RobloxRoundDropdownButton=5",
	AlphaMode = "Overlay=0 Transparency=1",
	CollisionFidelity = "Default=0 Hull=1 Box=2 PreciseConvexDecomposition=3",
	RenderFidelity = "Automatic=0 Precise=1 Performance=2",
	ExplosionType = "NoCraters=0 Craters=1",
	FieldOfViewMode = "Vertical=0 Diagonal=1 MaxAxis=2",
	ModelStreamingMode = "Default=0 Atomic=1 Persistent=2 PersistentPerPlayer=3 Nonatomic=4",
	ModelLevelOfDetail = "Automatic=0 StreamingMesh=1 Disabled=2",
	AnimationPriority = "Idle=0 Movement=1 Action=2 Action2=3 Action3=4 Action4=5 Core=1000",
	Technology = "Legacy=0 Voxel=1 Compatibility=2 ShadowMap=3 Future=4 Unified=5",
	PlayerActions = "CharacterForward=0 CharacterBackward=1 CharacterLeft=2 CharacterRight=3 CharacterJump=4",
	ProductPurchaseDecision = "NotProcessedYet=0 PurchaseGranted=1",
	MessageType = "MessageOutput=0 MessageInfo=1 MessageWarning=2 MessageError=3",
	TweenStatus = "Canceled=0 Completed=1",
	FontSize = "Size8=0 Size9=1 Size10=2 Size11=3 Size12=4 Size14=5 Size18=6 Size24=7 Size36=8 Size48=9 Size28=10 Size32=11 Size42=12 Size60=13 Size96=14",
	DevTouchMovementMode = "UserChoice=0 Thumbstick=1 DPad=2 Thumbpad=3 ClickToMove=4 Scriptable=5 DynamicThumbstick=6",
	DevComputerMovementMode = "UserChoice=0 KeyboardMouse=1 ClickToMove=2 Scriptable=3",
	DevTouchCameraMovementMode = "UserChoice=0 Classic=1 Follow=2 Orbital=3",
	DevComputerCameraMovementMode = "UserChoice=0 Classic=1 Follow=2 Orbital=3 CameraToggle=4",
	KeyCode = "Unknown=0 Backspace=8 Tab=9 Clear=12 Return=13 Pause=19 Escape=27 Space=32 QuotedDouble=34 Hash=35 Dollar=36 Percent=37 Ampersand=38 Quote=39 LeftParenthesis=40 RightParenthesis=41 Asterisk=42 Plus=43 Comma=44 Minus=45 Period=46 Slash=47 Zero=48 One=49 Two=50 Three=51 Four=52 Five=53 Six=54 Seven=55 Eight=56 Nine=57 Colon=58 Semicolon=59 LessThan=60 Equals=61 GreaterThan=62 Question=63 At=64 LeftBracket=91 BackSlash=92 RightBracket=93 Caret=94 Underscore=95 Backquote=96 LeftCurly=123 Pipe=124 RightCurly=125 Tilde=126 Delete=127 KeypadPeriod=266 KeypadDivide=267 KeypadMultiply=268 KeypadMinus=269 KeypadPlus=270 KeypadEnter=271 KeypadEquals=272 Up=273 Down=274 Right=275 Left=276 Insert=277 Home=278 End=279 PageUp=280 PageDown=281 NumLock=300 CapsLock=301 ScrollLock=302 RightShift=303 LeftShift=304 RightControl=305 LeftControl=306 RightAlt=307 LeftAlt=308 RightMeta=309 LeftMeta=310 LeftSuper=311 RightSuper=312 Mode=313 Compose=314 Help=315 Print=316 SysReq=317 Break=318 Menu=319 Power=320 Euro=321 Undo=322 ButtonX=1000 ButtonY=1001 ButtonA=1002 ButtonB=1003 ButtonR1=1004 ButtonL1=1005 ButtonR2=1006 ButtonL2=1007 ButtonR3=1008 ButtonL3=1009 ButtonStart=1010 ButtonSelect=1011 DPadLeft=1012 DPadRight=1013 DPadUp=1014 DPadDown=1015 Thumbstick1=1016 Thumbstick2=1017",
}
do
	-- ตัวอักษร A-Z, F1-F15, Keypad0-9 สร้างด้วยลูป (ค่าตรงกับ Roblox)
	local extra = {}
	for i = 0, 25 do
		extra[#extra + 1] = string.char(65 + i) .. "=" .. (97 + i)
	end
	for i = 1, 15 do
		extra[#extra + 1] = "F" .. i .. "=" .. (281 + i)
	end
	local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	for i = 0, 9 do
		extra[#extra + 1] = "Keypad" .. digits[i + 1] .. "=" .. (256 + i)
	end
	ENUM_SRC.KeyCode = ENUM_SRC.KeyCode .. " " .. tconcat(extra, " ")
end

local EIMT, mkEI = newType("EnumItem")
local ETMT, mkET = newType("Enum")
local ENMT, mkEN = newType("Enums")
local function isEnumItem(v)
	return getmt(v) == EIMT
end
local EnumTypes = {}
local EnumTypeList = {}
for tname, src in pairs(ENUM_SRC) do
	local et = { name = tname, items = {}, list = {}, byValue = {} }
	local proxy = mkET(et)
	et.proxy = proxy
	for iname, val in src:gmatch("([%w_]+)=(%-?%d+)") do
		local item = mkEI({ Name = iname, Value = tonumber(val), EnumType = proxy, typeName = tname })
		et.items[iname] = item
		et.list[#et.list + 1] = item
		if et.byValue[tonumber(val)] == nil then
			et.byValue[tonumber(val)] = item
		end
	end
	tsort(et.list, function(a, b)
		if D[a].Value ~= D[b].Value then
			return D[a].Value < D[b].Value
		end
		return D[a].Name < D[b].Name
	end)
	EnumTypes[tname] = et
	EnumTypeList[#EnumTypeList + 1] = proxy
end
tsort(EnumTypeList, function(a, b)
	return D[a].name < D[b].name
end)

local EIMethods = {
	IsA = function(self, name)
		local d = selfData(EIMT, self, "IsA")
		return d.typeName == name
	end,
}
EIMT.__index = function(self, k)
	local d = D[self]
	if k == "Name" or k == "Value" or k == "EnumType" then
		return d[k]
	end
	local m = EIMethods[k]
	if m then
		return m
	end
	memberError(k, '"Enum.' .. d.typeName .. "." .. d.Name .. '"')
end
EIMT.__newindex = function(_, k)
	throw(fmt("%s cannot be assigned to", tostring(k)))
end
EIMT.__tostring = function(self)
	local d = D[self]
	return "Enum." .. d.typeName .. "." .. d.Name
end

local ETMethods = {
	GetEnumItems = function(self)
		local et = selfData(ETMT, self, "GetEnumItems")
		local out = {}
		for i, it in ipairs(et.list) do
			out[i] = it
		end
		return out
	end,
	FromName = function(self, name)
		return selfData(ETMT, self, "FromName").items[name]
	end,
	FromValue = function(self, v)
		return selfData(ETMT, self, "FromValue").byValue[v]
	end,
}
ETMT.__index = function(self, k)
	local et = D[self]
	local it = et.items[k]
	if it then
		return it
	end
	local m = ETMethods[k]
	if m then
		return m
	end
	throw(fmt('%s is not a valid member of "Enum.%s"', tostring(k), et.name))
end
ETMT.__newindex = function(_, k)
	throw(fmt("%s cannot be assigned to", tostring(k)))
end
ETMT.__tostring = function(self)
	return D[self].name
end

local EnumRoot = mkEN({})
ENMT.__index = function(_, k)
	local et = EnumTypes[k]
	if et then
		return et.proxy
	end
	if k == "GetEnums" then
		return function()
			local out = {}
			for i, p in ipairs(EnumTypeList) do
				out[i] = p
			end
			return out
		end
	end
	throw(fmt('%s is not a valid member of "Enum"', tostring(k)))
end
ENMT.__newindex = function(_, k)
	throw(fmt("%s cannot be assigned to", tostring(k)))
end
ENMT.__tostring = function()
	return "Enums"
end

local function E(tname, iname)
	return EnumTypes[tname].items[iname]
end
local function enumArg(v, tname, i, fname)
	if v == nil then
		return nil
	end
	if isEnumItem(v) and D[v].typeName == tname then
		return v
	end
	badArg(i, fname, "Enum." .. tname, v)
end

	R.EIMT = EIMT
	R.ETMT = ETMT
	R.ENMT = ENMT
	R.isEnumItem = isEnumItem
	R.EnumTypes = EnumTypes
	R.EnumTypeList = EnumTypeList
	R.EnumRoot = EnumRoot
	R.E = E
	R.enumArg = enumArg
end

do
	local V3, v3arg, E, enumArg, isEnumItem = R.V3, R.v3arg, R.E, R.enumArg, R.isEnumItem
-- ============================================================================
-- TweenInfo / PhysicalProperties / Ray / RaycastParams / OverlapParams / Random / Font / DateTime
-- ============================================================================
local TIMT, mkTI = newType("TweenInfo")
makeAccess(TIMT, "TweenInfo", {
	Time = function(d) return d.Time end,
	EasingStyle = function(d) return d.EasingStyle end,
	EasingDirection = function(d) return d.EasingDirection end,
	RepeatCount = function(d) return d.RepeatCount end,
	Reverses = function(d) return d.Reverses end,
	DelayTime = function(d) return d.DelayTime end,
}, {})
TIMT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x.Time == y.Time and x.EasingStyle == y.EasingStyle and x.EasingDirection == y.EasingDirection
		and x.RepeatCount == y.RepeatCount and x.Reverses == y.Reverses and x.DelayTime == y.DelayTime
end
TIMT.__tostring = function(a)
	local x = D[a]
	return fmt("Time:%s DelayTime:%s RepeatCount:%s Reverses:%s EasingDirection:%s EasingStyle:%s", numStr(x.Time), numStr(x.DelayTime),
		numStr(x.RepeatCount), tostring(x.Reverses), D[x.EasingDirection].Name, D[x.EasingStyle].Name)
end
local TweenInfo = {}
function TweenInfo.new(t, style, dir, rep, rev, delay)
	if rev ~= nil and type(rev) ~= "boolean" then
		badArg(5, "new", "boolean", rev)
	end
	return mkTI({
		Time = optNum(t, 1, "new", 1),
		EasingStyle = enumArg(style, "EasingStyle", 2, "new") or E("EasingStyle", "Quad"),
		EasingDirection = enumArg(dir, "EasingDirection", 3, "new") or E("EasingDirection", "Out"),
		RepeatCount = optNum(rep, 4, "new", 0),
		Reverses = rev or false,
		DelayTime = optNum(delay, 6, "new", 0),
	})
end

local PPMT, mkPP = newType("PhysicalProperties")
makeAccess(PPMT, "PhysicalProperties", {
	Density = function(d) return d[1] end,
	Friction = function(d) return d[2] end,
	Elasticity = function(d) return d[3] end,
	FrictionWeight = function(d) return d[4] end,
	ElasticityWeight = function(d) return d[5] end,
}, {})
PPMT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x[1] == y[1] and x[2] == y[2] and x[3] == y[3] and x[4] == y[4] and x[5] == y[5]
end
PPMT.__tostring = function(a)
	local x = D[a]
	return fmt("%s, %s, %s, %s, %s", numStr(x[1]), numStr(x[2]), numStr(x[3]), numStr(x[4]), numStr(x[5]))
end
local PhysicalProperties = {}
function PhysicalProperties.new(a, b, c, d, e)
	if isEnumItem(a) then
		return mkPP({ 0.7, 0.3, 0.5, 1, 1 })
	end
	return mkPP({ checkNum(a, 1, "new"), checkNum(b, 2, "new"), checkNum(c, 3, "new"), optNum(d, 4, "new", 1), optNum(e, 5, "new", 1) })
end

local RayMT, mkRay = newType("Ray")
local RayM = {}
function RayM.ClosestPoint(self, p)
	local r = selfData(RayMT, self, "ClosestPoint")
	local v = v3arg(p, 1, "ClosestPoint")
	local o, dd = r[1], r[2]
	local dm = dd[1] * dd[1] + dd[2] * dd[2] + dd[3] * dd[3]
	local t = 0
	if dm > 0 then
		t = ((v[1] - o[1]) * dd[1] + (v[2] - o[2]) * dd[2] + (v[3] - o[3]) * dd[3]) / dm
		if t < 0 then
			t = 0
		end
	end
	return V3(o[1] + dd[1] * t, o[2] + dd[2] * t, o[3] + dd[3] * t)
end
function RayM.Distance(self, p)
	local c = RayM.ClosestPoint(self, p)
	return (c - p).Magnitude
end
makeAccess(RayMT, "Ray", {
	Origin = function(d) return V3(d[1][1], d[1][2], d[1][3]) end,
	Direction = function(d) return V3(d[2][1], d[2][2], d[2][3]) end,
	Unit = function(d)
		local dd = d[2]
		local m = sqrt(dd[1] * dd[1] + dd[2] * dd[2] + dd[3] * dd[3])
		return mkRay({ d[1], { dd[1] / m, dd[2] / m, dd[3] / m } })
	end,
}, RayM)
RayMT.__tostring = function(a)
	local d = D[a]
	return fmt("{%s, %s, %s}, {%s, %s, %s}", numStr(d[1][1]), numStr(d[1][2]), numStr(d[1][3]), numStr(d[2][1]), numStr(d[2][2]), numStr(d[2][3]))
end
local Ray = {}
function Ray.new(o, d)
	local a = v3arg(o, 1, "new")
	local b = v3arg(d, 2, "new")
	return mkRay({ { a[1], a[2], a[3] }, { b[1], b[2], b[3] } })
end

-- RaycastParams/OverlapParams เป็น userdata ที่แก้ฟิลด์ได้ (ตรวจชื่อฟิลด์และชนิด)
local function makeParamsType(tname, fields)
	local mt, mk = newType(tname)
	local methods = {
		AddToFilter = function(self, x)
			local d = selfData(mt, self, "AddToFilter")
			local list = d.FilterDescendantsInstances
			if type(x) == "table" then
				for _, v in ipairs(x) do
					list[#list + 1] = v
				end
			else
				list[#list + 1] = x
			end
		end,
	}
	mt.__index = function(self, k)
		local d = D[self]
		if fields[k] ~= nil then
			if k == "FilterDescendantsInstances" then
				local c = {}
				for i, v in ipairs(d[k]) do
					c[i] = v
				end
				return c
			end
			return d[k]
		end
		if methods[k] then
			return methods[k]
		end
		memberError(k, tname)
	end
	mt.__newindex = function(self, k, v)
		local spec = fields[k]
		if spec == nil then
			memberError(k, tname)
		end
		local d = D[self]
		if k == "FilterDescendantsInstances" then
			if type(v) ~= "table" then
				throw(fmt("Unable to assign property %s. Array expected, got %s", k, typeOf(v)))
			end
			local c = {}
			for i, x in ipairs(v) do
				if typeOf(x) ~= "Instance" then
					throw("Unable to assign property FilterDescendantsInstances. Instance expected in array")
				end
				c[i] = x
			end
			d[k] = c
		elseif spec == "enum" then
			d[k] = enumArg(v, "RaycastFilterType", 3, k) or d[k]
		elseif type(spec) ~= typeOf(v) then
			throw(fmt("Unable to assign property %s. %s expected, got %s", k, type(spec), typeOf(v)))
		else
			d[k] = v
		end
	end
	mt.__tostring = function()
		return tname
	end
	return function()
		local d = {}
		for k, v in pairs(fields) do
			if v == "enum" then
				d[k] = E("RaycastFilterType", "Exclude")
			elseif k == "FilterDescendantsInstances" then
				d[k] = {}
			else
				d[k] = v
			end
		end
		return mk(d)
	end, mt
end
local RaycastParams, OverlapParams = {}, {}
local RAYPARAMS_MT, OVERLAP_MT
RaycastParams.new, RAYPARAMS_MT = makeParamsType("RaycastParams", {
	FilterDescendantsInstances = "list", FilterType = "enum", IgnoreWater = false, CollisionGroup = "Default",
	RespectCanCollide = false, BruteForceAllSlow = false,
})
OverlapParams.new, OVERLAP_MT = makeParamsType("OverlapParams", {
	FilterDescendantsInstances = "list", FilterType = "enum", MaxParts = 0, CollisionGroup = "Default",
	RespectCanCollide = false, BruteForceAllSlow = false,
})

local RRMT, mkRR = newType("RaycastResult")
makeAccess(RRMT, "RaycastResult", {
	Instance = function(d) return d.Instance end,
	Position = function(d) return d.Position end,
	Normal = function(d) return d.Normal end,
	Material = function(d) return d.Material end,
	Distance = function(d) return d.Distance end,
}, {})
RRMT.__tostring = function()
	return "RaycastResult"
end

local RandMT, mkRand = newType("Random")
local RANDOM_MOD = 2147483647
local function randNext(d)
	d.s = (16807 * d.s) % RANDOM_MOD
	return d.s / RANDOM_MOD
end
local RandM = {}
function RandM.NextNumber(self, mn, mx)
	local d = selfData(RandMT, self, "NextNumber")
	mn = optNum(mn, 1, "NextNumber", 0)
	mx = optNum(mx, 2, "NextNumber", 1)
	return mn + (mx - mn) * randNext(d)
end
function RandM.NextInteger(self, mn, mx)
	local d = selfData(RandMT, self, "NextInteger")
	mn = floor(checkNum(mn, 1, "NextInteger"))
	mx = floor(checkNum(mx, 2, "NextInteger"))
	if mx < mn then
		throw("invalid argument #2 to 'NextInteger' (interval is empty)")
	end
	local r = mn + floor(randNext(d) * (mx - mn + 1))
	if r > mx then
		r = mx
	end
	return r
end
function RandM.NextUnitVector(self)
	local d = selfData(RandMT, self, "NextUnitVector")
	local z = randNext(d) * 2 - 1
	local a = randNext(d) * 2 * pi
	local r = sqrt(1 - z * z)
	return V3(r * cos(a), r * sin(a), z)
end
function RandM.Shuffle(self, t)
	local d = selfData(RandMT, self, "Shuffle")
	for i = #t, 2, -1 do
		local j = 1 + floor(randNext(d) * i)
		if j > i then
			j = i
		end
		t[i], t[j] = t[j], t[i]
	end
end
function RandM.Clone(self)
	local d = selfData(RandMT, self, "Clone")
	return mkRand({ s = d.s })
end
makeAccess(RandMT, "Random", {}, RandM)
RandMT.__tostring = function()
	return "Random"
end
local Random = {}
local randomSeedCounter = 12345
function Random.new(seed)
	local s
	if seed == nil then
		randomSeedCounter = (randomSeedCounter * 48271) % RANDOM_MOD
		s = randomSeedCounter
	else
		s = floor(abs(checkNum(seed, 1, "new"))) % (RANDOM_MOD - 1) + 1
	end
	return mkRand({ s = s })
end

local FontMT, mkFont = newType("Font")
makeAccess(FontMT, "Font", {
	Family = function(d) return d.Family end,
	Weight = function(d) return d.Weight end,
	Style = function(d) return d.Style end,
	Bold = function(d) return D[d.Weight].Value >= 600 end,
}, {})
FontMT.__eq = function(a, b)
	local x, y = D[a], D[b]
	return x.Family == y.Family and x.Weight == y.Weight and x.Style == y.Style
end
FontMT.__tostring = function(a)
	local x = D[a]
	return fmt("Font { Family = %s, Weight = %s, Style = %s }", x.Family, D[x.Weight].Name, D[x.Style].Name)
end
local Font = {}
function Font.new(family, weight, style)
	if type(family) ~= "string" then
		badArg(1, "new", "string", family)
	end
	return mkFont({
		Family = family,
		Weight = enumArg(weight, "FontWeight", 2, "new") or E("FontWeight", "Regular"),
		Style = enumArg(style, "FontStyle", 3, "new") or E("FontStyle", "Normal"),
	})
end
function Font.fromName(name, weight, style)
	if type(name) ~= "string" then
		badArg(1, "fromName", "string", name)
	end
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function Font.fromEnum(f)
	enumArg(f, "Font", 1, "fromEnum")
	if f == nil then
		badArg(1, "fromEnum", "Enum.Font", f)
	end
	local bold = D[f].Name:find("Bold") ~= nil
	return Font.new("rbxasset://fonts/families/" .. D[f].Name .. ".json", bold and E("FontWeight", "Bold") or nil)
end
function Font.fromId(id, weight, style)
	return Font.new("rbxassetid://" .. tostring(checkNum(id, 1, "fromId")), weight, style)
end

local EPOCH = 1700000000
local DTMT, mkDT = newType("DateTime")
makeAccess(DTMT, "DateTime", {
	UnixTimestamp = function(d) return floor(d.ms / 1000) end,
	UnixTimestampMillis = function(d) return d.ms end,
}, {
	ToIsoDate = function(self)
		local d = selfData(DTMT, self, "ToIsoDate")
		return os.date("!%Y-%m-%dT%H:%M:%SZ", floor(d.ms / 1000))
	end,
})
DTMT.__tostring = function(a)
	return tostring(D[a].ms)
end
local DateTime = {}
function DateTime.now()
	return mkDT({ ms = floor((EPOCH + R.clock()) * 1000) })
end
function DateTime.fromUnixTimestamp(s)
	return mkDT({ ms = floor(checkNum(s, 1, "fromUnixTimestamp") * 1000) })
end
function DateTime.fromUnixTimestampMillis(ms)
	return mkDT({ ms = floor(checkNum(ms, 1, "fromUnixTimestampMillis")) })
end

	R.TIMT = TIMT
	R.mkTI = mkTI
	R.TweenInfo = TweenInfo
	R.PPMT = PPMT
	R.mkPP = mkPP
	R.PhysicalProperties = PhysicalProperties
	R.RayMT = RayMT
	R.mkRay = mkRay
	R.Ray = Ray
	R.RaycastParams = RaycastParams
	R.OverlapParams = OverlapParams
	R.RAYPARAMS_MT = RAYPARAMS_MT
	R.OVERLAP_MT = OVERLAP_MT
	R.RRMT = RRMT
	R.mkRR = mkRR
	R.RandMT = RandMT
	R.mkRand = mkRand
	R.Random = Random
	R.FontMT = FontMT
	R.mkFont = mkFont
	R.Font = Font
	R.DTMT = DTMT
	R.mkDT = mkDT
	R.DateTime = DateTime
	R.EPOCH = EPOCH
end

do
-- ============================================================================
-- JSON (HttpService) : array = คีย์ 1..n ต่อเนื่อง, object = คีย์ string ล้วน, ผสม -> error แบบ Roblox
-- ============================================================================
local function jsonQuote(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
		return map[c] or fmt("\\u%04x", c:byte())
	end) .. '"'
end
local function tableKind(t)
	-- คืน "array", "object" หรือ nil (ผสม/แปลงไม่ได้)
	local n, count, strKeys, other = #t, 0, 0, 0
	for k in pairs(t) do
		count = count + 1
		if type(k) == "string" then
			strKeys = strKeys + 1
		elseif type(k) ~= "number" or k ~= floor(k) or k < 1 or k > n then
			other = other + 1
		end
	end
	if count == 0 then
		return "array", 0
	end
	if strKeys == count then
		return "object", count
	end
	if strKeys == 0 and other == 0 and count == n then
		return "array", n
	end
	return nil
end
local function jsonEncode(v, seen)
	local t = type(v)
	if v == nil then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == huge or v == -huge then
			throw("Can't convert to JSON")
		end
		return numStr(v)
	elseif t == "string" then
		return jsonQuote(v)
	elseif t == "table" then
		if seen[v] then
			throw("Can't convert to JSON")
		end
		seen[v] = true
		local kind, n = tableKind(v)
		local out = {}
		if kind == "array" then
			for i = 1, n do
				out[i] = jsonEncode(v[i], seen)
			end
			seen[v] = nil
			return "[" .. tconcat(out, ",") .. "]"
		elseif kind == "object" then
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = k
			end
			tsort(keys)
			for i, k in ipairs(keys) do
				out[i] = jsonQuote(k) .. ":" .. jsonEncode(v[k], seen)
			end
			seen[v] = nil
			return "{" .. tconcat(out, ",") .. "}"
		end
		throw("Can't convert to JSON")
	end
	throw("Can't convert to JSON")
end
local function jsonDecode(s)
	if type(s) ~= "string" then
		badArg(1, "JSONDecode", "string", s)
	end
	local pos = 1
	local function fail()
		throw("Can't parse JSON")
	end
	local function ws()
		pos = s:find("[^ \t\r\n]", pos) or (#s + 1)
	end
	local value
	local function str()
		pos = pos + 1
		local buf = {}
		while true do
			local c = s:sub(pos, pos)
			if c == "" then
				fail()
			elseif c == '"' then
				pos = pos + 1
				return tconcat(buf)
			elseif c == "\\" then
				local e = s:sub(pos + 1, pos + 1)
				local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if map[e] then
					buf[#buf + 1] = map[e]
					pos = pos + 2
				elseif e == "u" then
					local hex = s:sub(pos + 2, pos + 5)
					if not hex:match("^%x%x%x%x$") then
						fail()
					end
					local cp = tonumber(hex, 16)
					if cp < 0x80 then
						buf[#buf + 1] = string.char(cp)
					elseif cp < 0x800 then
						buf[#buf + 1] = string.char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
					else
						buf[#buf + 1] = string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
					end
					pos = pos + 6
				else
					fail()
				end
			else
				buf[#buf + 1] = c
				pos = pos + 1
			end
		end
	end
	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			ws()
			if s:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				ws()
				if s:sub(pos, pos) ~= '"' then
					fail()
				end
				local k = str()
				ws()
				if s:sub(pos, pos) ~= ":" then
					fail()
				end
				pos = pos + 1
				obj[k] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					fail()
				end
			end
		elseif c == "[" then
			pos = pos + 1
			local arr, n = {}, 0
			ws()
			if s:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				n = n + 1
				arr[n] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					fail()
				end
			end
		elseif c == '"' then
			return str()
		elseif s:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif s:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif s:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not num or num == "" or not tonumber(num) then
				fail()
			end
			pos = pos + #num
			return tonumber(num)
		end
	end
	local v = value()
	ws()
	if pos <= #s then
		fail()
	end
	return v
end

	R.jsonEncode = jsonEncode
	R.jsonDecode = jsonDecode
	R.tableKind = tableKind
	R.jsonQuote = jsonQuote
end

-- ============================================================================
-- Scheduler / Signal / Instance (แกนกลาง)
-- ============================================================================
local V3, isV3, v3arg, V2, isV2 = R.V3, R.isV3, R.v3arg, R.V2, R.isV2
local CF, mkCF, isCF, cfMul, cfInvData = R.CF, R.mkCF, R.isCF, R.cfMul, R.cfInvData
local C3, RGB, isC3, U2, UD = R.C3, R.RGB, R.isC3, R.U2, R.UD
local E, isEnumItem, EnumTypes = R.E, R.isEnumItem, R.EnumTypes
local S, Sig, I = {}, {}, {}
local Classes = {}
local InstMT, mkInst = newType("Instance")
local SigMT, mkSig = newType("RBXScriptSignal")
local ConnMT, mkConn = newType("RBXScriptConnection")
local function isInst(v)
	return getmt(v) == InstMT
end
-- ข้อมูลภายในอ้างถึง proxy แบบ weak (ไม่งั้นเกิด cycle ใน D ที่ GC ของ Lua 5.1 เก็บไม่ได้ -> หน่วยความจำรั่ว)
-- ถ้า proxy ถูกเก็บไปแล้ว (ไม่มีใครถืออยู่) สร้างใหม่ได้อย่างปลอดภัยเพราะไม่มีใครเทียบตัวตนกับของเก่าได้แล้ว
local WEAKV = { __mode = "v" }
local function PX(t)
	local ref = t._ref
	local p = ref[1]
	if p == nil then
		p = t._mk(t)
		ref[1] = p
	end
	return p
end
local GUI_INSET = 58 -- ความสูงแถบ topbar ของ Roblox (GuiService:GetGuiInset)

-- ---------------------------------------------------------------- scheduler
-- ctx = { kind = "server"|"client"|"harness", peer = "server"|"client:<UserId>"|"harness",
--         player = Player|nil, script = Instance|nil, label = string, alive = bool }
function S.ctx(W)
	local co = corunning()
	if co then
		local c = W.ctxOf[co]
		if c then
			return c
		end
	end
	return W.harness
end

-- thread ที่ scheduler ต้องปลุก (ถ้ากำลังอยู่ใน pcall ที่ yield ได้ ต้องปลุกตัวนอกสุด)
function S.root(W, co)
	local p = W.parentOf[co]
	while p do
		co = p
		p = W.parentOf[co]
	end
	return co
end

function S.luaFn(fn)
	-- coroutine.create ของ Lua 5.1 รับเฉพาะฟังก์ชัน Lua จึงห่อฟังก์ชัน C ไว้
	if type(fn) == "function" and debug.getinfo(fn, "S").what ~= "C" then
		return fn
	end
	return function(...)
		return fn(...)
	end
end

function S.report(W, co, err)
	local ctx = (co and W.ctxOf[co]) or W.harness
	local msg = tostring(err)
	local tb = co and debug.traceback(co, msg) or msg
	W.errors[#W.errors + 1] = ctx.label .. ": " .. tb
end

function S.resume(W, co, ...)
	if W.dead[co] or costatus(co) ~= "suspended" then
		return false
	end
	local ctx = W.ctxOf[co]
	if ctx and not ctx.alive then
		return false
	end
	local ok, err = coresume(co, ...)
	if not ok then
		S.report(W, co, err)
	end
	return ok
end

function S.thread(W, fn, ctx)
	local co = cocreate(S.luaFn(fn))
	W.ctxOf[co] = ctx
	return co
end

function S.spawn(W, fn, ctx, ...)
	local co = S.thread(W, fn, ctx)
	S.resume(W, co, ...)
	return co
end

function S.currentThread(W)
	local co = corunning()
	if not co then
		throw("attempt to yield from outside a coroutine")
	end
	return co, S.root(W, co)
end

-- task.wait: พักจนกว่าเวลาจำลองถึง (อย่างน้อย 1 step) แล้วคืนเวลาที่ผ่านไปจริง
function S.waitFor(W, seconds)
	local _, root = S.currentThread(W)
	W.seq = W.seq + 1
	W.waits[#W.waits + 1] = { co = root, at = W.time + seconds, minStep = W.stepCount + 1, start = W.time, seq = W.seq }
	return coyield()
end

function S.schedule(W, at, fnOrThread, ctx, args)
	W.seq = W.seq + 1
	local e = { at = at, minStep = W.stepCount + 1, start = W.time, seq = W.seq, args = args, ctx = ctx }
	if type(fnOrThread) == "thread" then
		e.co = fnOrThread
	else
		e.fn = fnOrThread
	end
	W.waits[#W.waits + 1] = e
	return e
end

function S.defer(W, fnOrThread, ctx, args)
	W.deferred[#W.deferred + 1] = { target = fnOrThread, ctx = ctx, args = args or { n = 0 } }
end

function S.runEntry(W, e, ...)
	if e.fn then
		local co = S.thread(W, e.fn, e.ctx)
		if e.args then
			S.resume(W, co, unpack(e.args, 1, e.args.n))
		else
			S.resume(W, co, ...)
		end
	elseif e.args then
		S.resume(W, e.co, unpack(e.args, 1, e.args.n))
	else
		S.resume(W, e.co, ...)
	end
end

function S.flush(W)
	local rounds = 0
	while #W.deferred > 0 do
		rounds = rounds + 1
		if rounds > 200 then
			W.errors[#W.errors + 1] = "scheduler: task.defer re-entrancy limit reached (deferred threads keep deferring)"
			W.deferred = {}
			break
		end
		local q = W.deferred
		W.deferred = {}
		for _, e in ipairs(q) do
			local t = e.target
			if type(t) == "thread" then
				S.resume(W, t, unpack(e.args, 1, e.args.n))
			else
				S.spawn(W, t, e.ctx, unpack(e.args, 1, e.args.n))
			end
		end
	end
end

function S.resumeDue(W)
	local due, keep = {}, {}
	for _, e in ipairs(W.waits) do
		local dead = e.co and W.dead[e.co]
		if not dead and not e.cancelled then
			if W.time + 1e-9 >= e.at and W.stepCount >= e.minStep then
				due[#due + 1] = e
			else
				keep[#keep + 1] = e
			end
		end
	end
	W.waits = keep
	tsort(due, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.seq < b.seq
	end)
	for _, e in ipairs(due) do
		if e.fn or e.args then
			S.runEntry(W, e)
		else
			-- เวลาเป็นผลรวม dt จึงคลาดได้นิดหน่อย: ไม่คืนค่าน้อยกว่าที่ขอรอ
			S.resume(W, e.co, math.max(W.time - e.start, e.at - e.start))
		end
	end
end

-- pcall/xpcall ที่ yield ได้ (Luau yield ข้าม pcall ได้ แต่ Lua 5.1 ทำไม่ได้) -> รันใน coroutine ลูก
function S.ypcall(W, handler, f, ...)
	local parent = corunning()
	if not parent then
		if handler then
			local args = pack(...)
			return xpcall(function()
				return f(unpack(args, 1, args.n))
			end, handler)
		end
		return pcall(f, ...)
	end
	local co = cocreate(S.luaFn(f))
	W.ctxOf[co] = S.ctx(W)
	W.parentOf[co] = parent
	local res = pack(coresume(co, ...))
	while true do
		if costatus(co) == "dead" then
			if res[1] then
				return true, unpack(res, 2, res.n)
			end
			if handler then
				local prev = W.xpcallThread
				W.xpcallThread = co
				local hres = pack(pcall(handler, res[2]))
				W.xpcallThread = prev
				if hres[1] then
					return false, unpack(hres, 2, hres.n)
				end
				return false, hres[2]
			end
			return false, res[2]
		end
		-- ลูก yield (เช่น task.wait) -> yield ต่อขึ้นไป แล้วส่งค่าที่ถูกปลุกกลับลงมา
		local back = pack(coyield(unpack(res, 2, res.n)))
		res = pack(coresume(co, unpack(back, 1, back.n)))
	end
end

-- ---------------------------------------------------------------- signals
function Sig.new(W, name, opts)
	local s = { W = W, name = name, conns = {}, waiters = nil }
	if opts then
		s.check = opts.check
		s.onConnect = opts.onConnect
	end
	s._ref, s._mk = setmetatable({ mkSig(s) }, WEAKV), mkSig
	return s
end

function Sig.disconnect(c)
	if not c.connected then
		return
	end
	c.connected = false
	local list = c.sig.conns
	for i = #list, 1, -1 do
		if list[i] == c then
			tremove(list, i)
			break
		end
	end
end

function Sig.connect(s, fn, once, fname)
	if type(fn) ~= "function" then
		throw("Attempt to connect failed: Passed value is not a function")
	end
	local W = s.W
	local ctx = S.ctx(W)
	if s.check then
		s.check(ctx, fname or "Connect")
	end
	local c = { sig = s, fn = fn, ctx = ctx, connected = true, once = once }
	c._ref, c._mk = setmetatable({ mkConn(c) }, WEAKV), mkConn
	s.conns[#s.conns + 1] = c
	if s.onConnect then
		s.onConnect(c)
	end
	return PX(c)
end

-- ยิง signal: handler ทุกตัวรันใน coroutine ใหม่ตาม ctx ของคนที่ Connect, filter(ctx) ใช้เลือกผู้รับ
function Sig.fire(s, filter, ...)
	if not s then
		return
	end
	local W = s.W
	local conns = s.conns
	local n = #conns
	if n > 0 then
		local snap = {}
		for i = 1, n do
			snap[i] = conns[i]
		end
		for i = 1, n do
			local c = snap[i]
			if c.connected then
				local ctx = c.ctx
				if not ctx.alive then
					Sig.disconnect(c)
				elseif not filter or filter(ctx) then
					if c.once then
						Sig.disconnect(c)
					end
					if W.deferredEvents then
						-- SignalBehavior.Deferred: handler รันตอนจบรอบปัจจุบัน (ถ้ายังไม่ถูก Disconnect)
						local conn, once = c, c.once
						S.defer(W, function(...)
							if conn.connected or once then
								return conn.fn(...)
							end
						end, ctx, pack(...))
					else
						S.spawn(W, c.fn, ctx, ...)
					end
				end
			end
		end
	end
	local ws = s.waiters
	if ws and #ws > 0 then
		s.waiters = {}
		for _, w in ipairs(ws) do
			if not w.ctx.alive then
				-- ทิ้ง
			elseif not filter or filter(w.ctx) then
				if W.deferredEvents then
					S.defer(W, w.co, nil, pack(...))
				else
					S.resume(W, w.co, ...)
				end
			else
				s.waiters[#s.waiters + 1] = w
			end
		end
	end
end

function Sig.hasListeners(s, filter)
	if not s then
		return false
	end
	for _, c in ipairs(s.conns) do
		if c.connected and c.ctx.alive and (not filter or filter(c.ctx)) then
			return true
		end
	end
	if s.waiters then
		for _, w in ipairs(s.waiters) do
			if w.ctx.alive and (not filter or filter(w.ctx)) then
				return true
			end
		end
	end
	return false
end

function Sig.disconnectAll(s)
	for _, c in ipairs(s.conns) do
		c.connected = false
	end
	s.conns = {}
	s.waiters = nil
end

local SigMethods = {}
function SigMethods.Connect(self, fn)
	return Sig.connect(selfData(SigMT, self, "Connect"), fn, false, "Connect")
end
function SigMethods.Once(self, fn)
	return Sig.connect(selfData(SigMT, self, "Once"), fn, true, "Once")
end
function SigMethods.ConnectParallel(self, fn)
	return Sig.connect(selfData(SigMT, self, "ConnectParallel"), fn, false, "ConnectParallel")
end
function SigMethods.Wait(self)
	local s = selfData(SigMT, self, "Wait")
	local W = s.W
	local ctx = S.ctx(W)
	if s.check then
		s.check(ctx, "Wait")
	end
	local _, root = S.currentThread(W)
	s.waiters = s.waiters or {}
	s.waiters[#s.waiters + 1] = { co = root, ctx = ctx }
	return coyield()
end
SigMethods.connect = SigMethods.Connect
SigMethods.wait = SigMethods.Wait
SigMT.__index = function(_, k)
	local m = SigMethods[k]
	if m then
		return m
	end
	memberError(k, "RBXScriptSignal")
end
SigMT.__newindex = function(_, k)
	throw(fmt("%s cannot be assigned to", tostring(k)))
end
SigMT.__tostring = function(self)
	return "Signal " .. D[self].name
end

local function connDisconnect(self)
	Sig.disconnect(selfData(ConnMT, self, "Disconnect"))
end
ConnMT.__index = function(self, k)
	if k == "Connected" then
		return D[self].connected
	elseif k == "Disconnect" or k == "disconnect" then
		return connDisconnect
	end
	memberError(k, "RBXScriptConnection")
end
ConnMT.__newindex = function(_, k)
	throw(fmt("%s cannot be assigned to", tostring(k)))
end
ConnMT.__tostring = function()
	return "Connection"
end

-- ---------------------------------------------------------------- classes
local function P(t, default, extra)
	local p = { type = t, default = default }
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	return p
end
local function EP(enumName, item, extra)
	local p = P("Enum", E(enumName, item), extra)
	p.enum = enumName
	return p
end
local function IP(cls, extra)
	local p = P("Instance", nil, extra)
	p.cls = cls
	return p
end
local function RO(t, getter)
	return { type = t, ro = true, get = getter }
end

local function defClass(name, superName, def)
	def = def or {}
	def.name = name
	if superName then
		def.super = Classes[superName]
		if not def.super then
			error("stubs bug: unknown super class " .. superName)
		end
	end
	Classes[name] = def
	return def
end

function I.classIsA(cls, target)
	while cls do
		if cls == target then
			return true
		end
		cls = cls.super
	end
	return false
end
function I.classIsAName(cls, name)
	while cls do
		if cls.name == name then
			return true
		end
		cls = cls.super
	end
	return false
end

function I.members(cls)
	if cls.members then
		return cls.members
	end
	local m, inits = {}, {}
	if cls.super then
		for k, v in pairs(I.members(cls.super)) do
			m[k] = v
		end
		-- flag แบบ isPart/isGuiObject สืบทอดจากคลาสแม่
		for k, v in pairs(cls.super) do
			if type(k) == "string" and k:sub(1, 2) == "is" and v == true and cls[k] == nil then
				cls[k] = true
			end
		end
		for _, f in ipairs(cls.super.inits) do
			inits[#inits + 1] = f
		end
	end
	if cls.init then
		inits[#inits + 1] = cls.init
	end
	if cls.props then
		for k, spec in pairs(cls.props) do
			local c = {}
			for a, b in pairs(spec) do
				c[a] = b
			end
			c.kind, c.name = "prop", k
			m[k] = c
		end
	end
	if cls.defaults then
		for k, v in pairs(cls.defaults) do
			local base = m[k]
			if not base or base.kind ~= "prop" then
				error("stubs bug: default for unknown prop " .. k .. " in " .. cls.name)
			end
			local c = {}
			for a, b in pairs(base) do
				c[a] = b
			end
			c.default = v
			m[k] = c
		end
	end
	if cls.methods then
		for k, fn in pairs(cls.methods) do
			local owner, mname = cls, k
			m[k] = {
				kind = "method",
				fn = function(self, ...)
					local d = D[self]
					if d == nil or not d.isInstance or not I.classIsA(d.class, owner) then
						throw("Expected ':' not '.' calling member function " .. mname)
					end
					return fn(d, ...)
				end,
			}
		end
	end
	if cls.events then
		for _, k in ipairs(cls.events) do
			m[k] = { kind = "event", name = k, opts = cls.eventOpts and cls.eventOpts[k] }
		end
	end
	if cls.callbacks then
		for k, opts in pairs(cls.callbacks) do
			m[k] = { kind = "callback", name = k, opts = opts }
		end
	end
	cls.members, cls.inits = m, inits
	return m
end

-- ---------------------------------------------------------------- instance core
function I.peer(W)
	return S.ctx(W).peer
end

function I.visibleTo(cd, peer)
	local o = cd.owner
	return o == nil or peer == "harness" or o == peer
end

-- มองเห็นได้จริงไหม (รวมกรณีอยู่ใน ServerScriptService/ServerStorage ที่ client มองไม่เห็นทั้งก้อน)
function I.visibleDeep(cd, peer)
	if not I.visibleTo(cd, peer) then
		return false
	end
	if peer == "server" or peer == "harness" then
		return true
	end
	local cur = cd.parent and D[cd.parent]
	while cur do
		if cur.serverOnly or not I.visibleTo(cur, peer) then
			return false
		end
		cur = cur.parent and D[cur.parent]
	end
	return true
end

function I.visFilter(cd)
	local o = cd.owner
	if o == nil then
		return nil
	end
	return function(ctx)
		return ctx.peer == "harness" or ctx.peer == o
	end
end

function I.new(W, cname, owner)
	local cls = Classes[cname]
	if not cls then
		error("stubs bug: unknown class " .. tostring(cname))
	end
	I.members(cls)
	local d = { W = W, class = cls, name = cls.defaultName or cname, props = {}, children = {}, isInstance = true, owner = owner }
	W.nextId = W.nextId + 1
	d.id = W.nextId
	local p = mkInst(d)
	d._ref, d._mk = setmetatable({ p }, WEAKV), mkInst
	for _, f in ipairs(cls.inits) do
		f(d)
	end
	return p, d
end

function I.get(d, k)
	local m = d.class.members[k]
	if m.get then
		return m.get(d, k)
	end
	local v = d.props[k]
	if v == nil then
		return m.default
	end
	return v
end

local TYPE_LABEL = { bool = "boolean", int = "number", number = "number", string = "string", Content = "string" }

function I.coerce(m, v)
	local t = m.type
	if t == "string" or t == "Content" then
		if type(v) == "string" then
			return true, v
		elseif type(v) == "number" then
			return true, numStr(v)
		end
	elseif t == "number" or t == "int" then
		local n = v
		if type(n) == "string" then
			n = tonumber(n)
		end
		if type(n) == "number" then
			if t == "int" then
				if n >= 0 then
					n = floor(n)
				else
					n = -floor(-n)
				end
			end
			return true, n
		end
	elseif t == "bool" then
		if type(v) == "boolean" then
			return true, v
		end
	elseif t == "Instance" then
		if v == nil then
			return true, nil
		end
		if isInst(v) then
			if m.cls and not I.classIsAName(D[v].class, m.cls) then
				return false, fmt("Unable to assign property %s. %s expected, got %s", m.name, m.cls, D[v].class.name)
			end
			return true, v
		end
		return false, fmt("Unable to assign property %s. Instance expected, got %s", m.name, typeOf(v))
	elseif t == "Enum" then
		local et = EnumTypes[m.enum]
		if isEnumItem(v) then
			if D[v].typeName == m.enum then
				return true, v
			end
			return false, fmt("Unable to assign property %s. EnumItem of type %s expected, got %s", m.name, m.enum, tostring(v))
		elseif type(v) == "string" then
			if et.items[v] then
				return true, et.items[v]
			end
			return false, fmt('Unable to assign property %s. Invalid value "%s" for enum %s', m.name, v, m.enum)
		elseif type(v) == "number" then
			if et.byValue[v] then
				return true, et.byValue[v]
			end
			return false, fmt("Unable to assign property %s. Invalid value %s for enum %s", m.name, numStr(v), m.enum)
		end
		return false, fmt("Unable to assign property %s. EnumItem of type %s expected, got %s", m.name, m.enum, typeOf(v))
	elseif t == "PhysicalProperties?" then
		if v == nil or typeOf(v) == "PhysicalProperties" then
			return true, v
		end
		return false, fmt("Unable to assign property %s. PhysicalProperties expected, got %s", m.name, typeOf(v))
	elseif t == "any" then
		return true, v
	else
		if typeOf(v) == t then
			return true, v
		end
	end
	return false, fmt("Unable to assign property %s. %s expected, got %s", m.name, TYPE_LABEL[t] or t, typeOf(v))
end

function I.changed(d, k)
	local ev = d.events
	if ev then
		local s = ev.Changed
		if s then
			if d.class.isValue then
				if k == "Value" then
					Sig.fire(s, nil, I.get(d, "Value"))
				end
			else
				Sig.fire(s, nil, k)
			end
		end
	end
	local ps = d.propSignals
	if ps and ps[k] then
		Sig.fire(ps[k], nil)
	end
end

function I.rawSet(d, k, v)
	local m = d.class.members[k]
	local old = d.props[k]
	if old == nil then
		old = m.default
	end
	d.props[k] = v
	if old ~= v then
		I.changed(d, k)
	end
end

-- ตั้ง property แบบเดียวกับสคริปต์ (ผ่านการตรวจชนิด) ใช้ภายใน stubs และจาก tween
function I.set(d, k, v)
	local m = d.class.members[k]
	if not m or m.kind ~= "prop" then
		throw(fmt('%s is not a valid member of %s "%s"', tostring(k), d.class.name, I.fullName(d)))
	end
	if m.ro then
		throw(type(m.ro) == "string" and m.ro or fmt("Unable to assign property %s. Property is read only", k))
	end
	local ok, val = I.coerce(m, v)
	if not ok then
		throw(val)
	end
	if m.set then
		m.set(d, val, k)
	else
		I.rawSet(d, k, val)
	end
end

function I.event(d, k, m)
	local ev = d.events
	if not ev then
		ev = {}
		d.events = ev
	end
	local s = ev[k]
	if not s then
		local opts = m and m.opts
		s = Sig.new(d.W, k, opts)
		s.owner = d
		ev[k] = s
	end
	return s
end

-- คืน signal ถ้ามีคนเคยเข้าถึงแล้ว (ไม่สร้างใหม่ เพื่อความเร็ว)
function I.sig(d, k)
	local ev = d.events
	return ev and ev[k]
end

InstMT.__index = function(p, k)
	local d = D[p]
	local m = d.class.members[k]
	if m then
		local kind = m.kind
		if kind == "prop" then
			if m.get then
				return m.get(d, k)
			end
			local v = d.props[k]
			if v == nil then
				return m.default
			end
			return v
		elseif kind == "method" then
			return m.fn
		elseif kind == "event" then
			return PX(I.event(d, k, m))
		elseif kind == "callback" then
			throw(fmt("%s is a callback member of %s; you can only set the callback value, get is not available", k, d.class.name))
		end
	end
	if type(k) == "string" then
		local c = I.findChild(d, k, I.peer(d.W))
		if c then
			return c
		end
	end
	throw(fmt('%s is not a valid member of %s "%s"', tostring(k), d.class.name, I.fullName(d)))
end

InstMT.__newindex = function(p, k, v)
	local d = D[p]
	local m = d.class.members[k]
	if not m then
		throw(fmt('%s is not a valid member of %s "%s"', tostring(k), d.class.name, I.fullName(d)))
	end
	if m.kind == "callback" then
		if v ~= nil and type(v) ~= "function" then
			throw(fmt("Unable to assign property %s. function expected, got %s", k, typeOf(v)))
		end
		if m.opts and m.opts.check then
			m.opts.check(S.ctx(d.W), k)
		end
		d.callbacks = d.callbacks or {}
		d.callbacks[k] = v and { fn = v, ctx = S.ctx(d.W) } or nil
		if m.opts and m.opts.onSet then
			m.opts.onSet(d)
		end
		return
	end
	if m.kind ~= "prop" then
		throw(fmt("Unable to assign property %s. Property is read only", tostring(k)))
	end
	I.set(d, k, v)
end

InstMT.__tostring = function(p)
	return D[p].name
end

function I.fullName(d)
	local parts = {}
	local cur = d
	while cur do
		if cur.class.name == "DataModel" then
			break
		end
		tinsert(parts, 1, cur.name)
		cur = cur.parent and D[cur.parent]
	end
	if #parts == 0 then
		return d.name
	end
	return tconcat(parts, ".")
end

function I.children(d, peer)
	if d.serverOnly and peer ~= "server" and peer ~= "harness" then
		return {}
	end
	local out = {}
	for _, c in ipairs(d.children) do
		local cd = D[c]
		if cd.owner == nil or peer == "harness" or cd.owner == peer then
			out[#out + 1] = c
		end
	end
	return out
end

function I.findChild(d, name, peer)
	if d.serverOnly and peer ~= "server" and peer ~= "harness" then
		return nil
	end
	for _, c in ipairs(d.children) do
		local cd = D[c]
		if cd.name == name and (cd.owner == nil or peer == "harness" or cd.owner == peer) then
			return c
		end
	end
	return nil
end

function I.descendants(d, peer, out)
	out = out or {}
	for _, c in ipairs(I.children(d, peer)) do
		out[#out + 1] = c
		I.descendants(D[c], peer, out)
	end
	return out
end

-- descendant ทั้งหมดแบบไม่สนการมองเห็น (ใช้ภายใน)
function I.allDescendants(d, out)
	out = out or {}
	for _, c in ipairs(d.children) do
		out[#out + 1] = c
		I.allDescendants(D[c], out)
	end
	return out
end

function I.isDescendantOf(d, ancestorD)
	local cur = d.parent
	while cur do
		if cur == PX(ancestorD) then
			return true
		end
		cur = D[cur].parent
	end
	return false
end

function I.inDataModel(d)
	local cur = d
	while cur.parent do
		cur = D[cur.parent]
	end
	return cur.class.name == "DataModel"
end

function I.removeChild(pd, p)
	local list = pd.children
	for i = #list, 1, -1 do
		if list[i] == p then
			tremove(list, i)
			return
		end
	end
end

function I.argName(v, i, fname)
	if type(v) == "string" then
		return v
	elseif type(v) == "number" then
		return numStr(v)
	elseif v == nil then
		throw(fmt("Argument %d missing or nil", i))
	end
	badArg(i, fname, "string", v)
end

function I.setParent(d, np)
	local W = d.W
	if d.parentLocked then
		throw(fmt("The Parent property of %s is locked, current parent: %s, new parent %s", d.name,
			d.parent and D[d.parent].name or "NULL", np and D[np].name or "NULL"))
	end
	local op = d.parent
	if np == op then
		return
	end
	local nd = np and D[np]
	if nd then
		local cur = nd
		while cur do
			if cur == d then
				throw(fmt("Attempt to set parent of %s to %s would result in circular reference", I.fullName(d), I.fullName(nd)))
			end
			cur = cur.parent and D[cur.parent]
		end
	end
	local vf = I.visFilter(d)
	if op then
		local od = D[op]
		I.fireDescendantRemoving(od, d, vf)
		I.removeChild(od, PX(d))
		d.parent = nil
		local s = I.sig(od, "ChildRemoved")
		if s then
			Sig.fire(s, vf, PX(d))
		end
	end
	d.parent = np
	if nd then
		nd.children[#nd.children + 1] = PX(d)
		local s = I.sig(nd, "ChildAdded")
		if s then
			Sig.fire(s, vf, PX(d))
		end
		I.fireDescendantAdded(nd, d, vf)
		if #W.childWaits > 0 then
			I.checkChildWaits(W, nd, d)
		end
	end
	I.fireAncestry(d, PX(d), np, vf)
	I.changed(d, "Parent")
	if W.tagCount > 0 then
		I.updateTagMembership(d)
	end
end

function I.ancestorsWith(pd, ev)
	local list
	local cur = pd
	while cur do
		local s = I.sig(cur, ev)
		if s then
			list = list or {}
			list[#list + 1] = s
		end
		cur = cur.parent and D[cur.parent]
	end
	return list
end

function I.fireDescendantAdded(pd, d, vf)
	local sigs = I.ancestorsWith(pd, "DescendantAdded")
	if not sigs then
		return
	end
	local subtree = { PX(d) }
	I.allDescendants(d, subtree)
	for _, s in ipairs(sigs) do
		for _, x in ipairs(subtree) do
			Sig.fire(s, I.visFilter(D[x]) or vf, x)
		end
	end
end

function I.fireDescendantRemoving(pd, d, vf)
	local sigs = I.ancestorsWith(pd, "DescendantRemoving")
	if not sigs then
		return
	end
	local subtree = { PX(d) }
	I.allDescendants(d, subtree)
	for _, s in ipairs(sigs) do
		for _, x in ipairs(subtree) do
			Sig.fire(s, I.visFilter(D[x]) or vf, x)
		end
	end
end

function I.fireAncestry(d, child, parent, vf)
	local s = I.sig(d, "AncestryChanged")
	if s then
		Sig.fire(s, vf, child, parent)
	end
	for _, c in ipairs(d.children) do
		I.fireAncestry(D[c], child, parent, vf)
	end
end

function I.setName(d, v)
	if d.name == v then
		return
	end
	d.name = v
	I.changed(d, "Name")
	if d.parent and #d.W.childWaits > 0 then
		I.checkChildWaits(d.W, D[d.parent], d)
	end
end

-- WaitForChild ที่รออยู่: ปลุกเมื่อมีลูกชื่อตรง (ผ่าน task.defer เหมือน Roblox ปลุกในรอบถัดไป)
function I.checkChildWaits(W, pd, cd)
	local keep = {}
	for _, w in ipairs(W.childWaits) do
		if w.parent == pd and w.name == cd.name and I.visibleTo(cd, w.peer) and not (pd.serverOnly and w.peer ~= "server" and w.peer ~= "harness") then
			S.defer(W, w.co, nil, pack(PX(cd)))
		else
			keep[#keep + 1] = w
		end
	end
	W.childWaits = keep
end

function I.destroy(d)
	if d.destroyed or d.destroying then
		return
	end
	d.destroying = true
	local s = I.sig(d, "Destroying")
	if s then
		Sig.fire(s, nil)
	end
	if d.parent then
		I.setParent(d, nil)
	end
	d.parentLocked = true
	local ch = d.children
	for i = #ch, 1, -1 do
		local c = ch[i]
		if c then
			I.destroy(D[c])
		end
	end
	d.destroyed = true
	if d.events then
		for _, sg in pairs(d.events) do
			Sig.disconnectAll(sg)
		end
	end
	if d.propSignals then
		for _, sg in pairs(d.propSignals) do
			Sig.disconnectAll(sg)
		end
	end
	if d.attrSignals then
		for _, sg in pairs(d.attrSignals) do
			Sig.disconnectAll(sg)
		end
	end
	local cls = d.class
	while cls do
		if cls.onDestroy then
			cls.onDestroy(d)
		end
		cls = cls.super
	end
end

function I.clone(d, owner, map)
	if not I.get(d, "Archivable") or d.class.notClonable then
		return nil
	end
	local p2, d2 = I.new(d.W, d.class.name, owner)
	map[PX(d)] = p2
	d2.name = d.name
	for k, v in pairs(d.props) do
		d2.props[k] = v
	end
	if d.attrs then
		d2.attrs = {}
		for k, v in pairs(d.attrs) do
			d2.attrs[k] = v
		end
	end
	d2.source, d2.sourcePath, d2.worldPivotSet, d2.scale = d.source, d.sourcePath, d.worldPivotSet, d.scale
	for _, c in ipairs(d.children) do
		local c2 = I.clone(D[c], owner, map)
		if c2 then
			local cd2 = D[c2]
			cd2.parent = p2
			d2.children[#d2.children + 1] = c2
		end
	end
	if d.tags then
		for _, t in ipairs(d.tags.list) do
			I.addTag(d2, t)
		end
	end
	return p2
end

function I.remapRefs(map)
	for _, p2 in pairs(map) do
		local props = D[p2].props
		for k, v in pairs(props) do
			if isInst(v) and map[v] then
				props[k] = map[v]
			end
		end
	end
end

-- ---------------------------------------------------------------- attributes & tags
local ATTR_TYPES = {
	string = true, boolean = true, number = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, EnumItem = true, Font = true,
}
function I.setAttribute(d, name, value)
	if type(name) ~= "string" then
		badArg(1, "SetAttribute", "string", name)
	end
	if #name > 100 then
		throw(fmt("Attribute name '%s' is too long (max 100 characters)", name))
	end
	if not name:match("^[%w_]+$") then
		throw(fmt("Attribute name '%s' can only contain alphanumeric characters and underscores", name))
	end
	if name:sub(1, 3) == "RBX" then
		throw(fmt("Attribute name '%s' is reserved (names starting with RBX are reserved by Roblox)", name))
	end
	local t = typeOf(value)
	if value ~= nil and not ATTR_TYPES[t] then
		throw(fmt("%s is not a supported attribute type", t))
	end
	d.attrs = d.attrs or {}
	local old = d.attrs[name]
	d.attrs[name] = value
	if old ~= value or (value ~= value) then
		local s = I.sig(d, "AttributeChanged")
		if s then
			Sig.fire(s, nil, name)
		end
		local as = d.attrSignals and d.attrSignals[name]
		if as then
			Sig.fire(as, nil)
		end
	end
end

function I.tagRegistry(W, tag)
	local r = W.tagged[tag]
	if not r then
		r = { list = {}, set = {} }
		W.tagged[tag] = r
	end
	return r
end

function I.addTag(d, tag)
	if type(tag) ~= "string" then
		badArg(1, "AddTag", "string", tag)
	end
	d.tags = d.tags or { list = {}, set = {} }
	if d.tags.set[tag] then
		return
	end
	d.tags.set[tag] = true
	d.tags.list[#d.tags.list + 1] = tag
	local W = d.W
	local r = I.tagRegistry(W, tag)
	r.set[PX(d)] = true
	r.list[#r.list + 1] = PX(d)
	W.tagCount = W.tagCount + 1
	d.tagInDM = d.tagInDM or {}
	if I.inDataModel(d) then
		d.tagInDM[tag] = true
		local s = W.tagAdded[tag]
		if s then
			Sig.fire(s, I.visFilter(d), PX(d))
		end
	end
end

function I.removeTag(d, tag)
	if not (d.tags and d.tags.set[tag]) then
		return
	end
	d.tags.set[tag] = nil
	for i, t in ipairs(d.tags.list) do
		if t == tag then
			tremove(d.tags.list, i)
			break
		end
	end
	local W = d.W
	local r = I.tagRegistry(W, tag)
	r.set[PX(d)] = nil
	for i, x in ipairs(r.list) do
		if x == PX(d) then
			tremove(r.list, i)
			break
		end
	end
	if d.tagInDM and d.tagInDM[tag] then
		d.tagInDM[tag] = nil
		local s = W.tagRemoved[tag]
		if s then
			Sig.fire(s, I.visFilter(d), PX(d))
		end
	end
end

-- ยิง GetInstanceAdded/RemovedSignal เมื่อ instance ที่มี tag เข้า/ออกจาก DataModel
function I.updateTagMembership(d)
	local W = d.W
	local list = { PX(d) }
	I.allDescendants(d, list)
	for _, p in ipairs(list) do
		local x = D[p]
		if x.tags and #x.tags.list > 0 then
			local inDM = I.inDataModel(x)
			x.tagInDM = x.tagInDM or {}
			for _, tag in ipairs(x.tags.list) do
				if inDM and not x.tagInDM[tag] then
					x.tagInDM[tag] = true
					if W.tagAdded[tag] then
						Sig.fire(W.tagAdded[tag], I.visFilter(x), p)
					end
				elseif not inDM and x.tagInDM[tag] then
					x.tagInDM[tag] = nil
					if W.tagRemoved[tag] then
						Sig.fire(W.tagRemoved[tag], I.visFilter(x), p)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- geometry helpers
local IDENT = R.CFrame.identity
local Vector3, Vector2 = R.Vector3, R.Vector2
local cfPoint, cfVector, cfVectorInv, eulerYXZ, eulerXYZ, matYXZ, matXYZ = R.cfPoint, R.cfVector, R.cfVectorInv, R.eulerYXZ, R.eulerXYZ, R.matYXZ, R.matXYZ
function I.partCF(d)
	return d.props.CFrame or IDENT
end

function I.setPartCF(d, cf)
	local old = d.props.CFrame or IDENT
	d.props.CFrame = cf
	if old ~= cf then
		I.changed(d, "CFrame")
		I.changed(d, "Position")
		I.changed(d, "Orientation")
	end
end

function I.descParts(d, out)
	out = out or {}
	for _, c in ipairs(d.children) do
		local cd = D[c]
		if cd.class.isPart then
			out[#out + 1] = cd
		end
		I.descParts(cd, out)
	end
	return out
end

function I.primaryPart(d)
	local pp = d.props.PrimaryPart
	if pp then
		local pd = D[pp]
		if pd.destroyed or not I.isDescendantOf(pd, d) then
			return nil
		end
	end
	return pp
end

-- กล่องล้อมรอบ (ในทิศของ rot) ของ BasePart ลูกหลานทั้งหมด
function I.bbox(d, rot, includeSelf)
	local parts = I.descParts(d)
	if includeSelf then
		tinsert(parts, 1, d)
	end
	if #parts == 0 then
		return nil
	end
	local minx, miny, minz, maxx, maxy, maxz = huge, huge, huge, -huge, -huge, -huge
	for _, pd in ipairs(parts) do
		local c = D[I.partCF(pd)]
		local s = D[I.get(pd, "Size")]
		local hx, hy, hz = s[1] / 2, s[2] / 2, s[3] / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local wx, wy, wz = cfPoint(c, sx * hx, sy * hy, sz * hz)
					local lx, ly, lz = cfVectorInv(rot, wx, wy, wz)
					if lx < minx then minx = lx end
					if ly < miny then miny = ly end
					if lz < minz then minz = lz end
					if lx > maxx then maxx = lx end
					if ly > maxy then maxy = ly end
					if lz > maxz then maxz = lz end
				end
			end
		end
	end
	local wx, wy, wz = cfVector(rot, (minx + maxx) / 2, (miny + maxy) / 2, (minz + maxz) / 2)
	return CF(wx, wy, wz, unpack(rot, 4, 12)), V3(maxx - minx, maxy - miny, maxz - minz)
end

function I.partPivot(pd)
	local off = pd.props.PivotOffset
	if off == nil then
		return I.partCF(pd) -- PivotOffset ปกติเป็น identity: ไม่ต้องคูณ
	end
	return cfMul(D[I.partCF(pd)], D[off])
end

function I.modelPivot(d)
	local pp = I.primaryPart(d)
	if pp then
		return I.partPivot(D[pp])
	end
	if d.worldPivotSet then
		return d.props.WorldPivot
	end
	-- Roblox: Model ที่ยังไม่เคยตั้ง WorldPivot ใช้จุดกึ่งกลางกล่องล้อมรอบ
	return (I.bbox(d, D[IDENT])) or IDENT
end

function I.getPivot(d)
	if d.class.isCamera then
		return I.get(d, "CFrame")
	end
	if d.class.isPart then
		return I.partPivot(d)
	end
	return I.modelPivot(d)
end

function I.pivotTo(d, target)
	if not isCF(target) then
		badArg(1, "PivotTo", "CFrame", target)
	end
	if d.class.isCamera then
		I.set(d, "CFrame", target)
		return
	end
	local cur = I.getPivot(d)
	local delta = R.cfMulRaw(D[target], cfInvData(D[cur]))
	if d.class.isPart then
		I.setPartCF(d, cfMul(delta, D[I.partCF(d)]))
	end
	for _, pd in ipairs(I.descParts(d)) do
		I.setPartCF(pd, cfMul(delta, D[I.partCF(pd)]))
	end
	if not d.class.isPart and not I.primaryPart(d) then
		d.worldPivotSet = true
		d.props.WorldPivot = target
		I.changed(d, "WorldPivot")
	end
end

function I.viewportOf(d)
	-- หา viewport ของผู้เล่นเจ้าของ GUI (ScreenGui ใต้ PlayerGui ของใคร)
	local cur = d
	while cur do
		if cur.class.name == "Player" then
			local pc = d.W.clientsByPlayer[PX(cur)]
			if pc then
				return D[pc.viewport]
			end
			break
		end
		cur = cur.parent and D[cur.parent]
	end
	return { 1280, 720 }
end

-- ตำแหน่ง/ขนาดบนจอ (pixel) ของ GuiObject/LayerCollector: x, y, w, h (ไม่คำนวณ UIListLayout/UIGridLayout)
function I.absRect(d)
	local cls = d.class
	if cls.name == "ScreenGui" then
		-- พิกัด GUI ของ Roblox: (0,0) อยู่ใต้แถบ topbar; ScreenGui ที่ IgnoreGuiInset ขยายขึ้นไปทับ topbar
		local vp = I.viewportOf(d)
		if I.get(d, "IgnoreGuiInset") then
			return 0, -GUI_INSET, vp[1], vp[2]
		end
		return 0, 0, vp[1], vp[2] - GUI_INSET
	elseif cls.name == "SurfaceGui" then
		local c = D[I.get(d, "CanvasSize")]
		return 0, 0, c[1], c[2]
	elseif cls.name == "BillboardGui" then
		local s = D[I.get(d, "Size")]
		return 0, 0, s[2], s[4]
	elseif cls.isGuiObject then
		local px, py, pw, ph = 0, 0, 0, 0
		local pd = d.parent and D[d.parent]
		if pd and pd.class.isGuiBase2d then
			px, py, pw, ph = I.absRect(pd)
		end
		local sz = D[I.get(d, "Size")]
		local pos = D[I.get(d, "Position")]
		local ap = D[I.get(d, "AnchorPoint")]
		local sc = D[I.get(d, "SizeConstraint")].Name
		local w = sz[1] * pw + sz[2]
		local h = sz[3] * ph + sz[4]
		if sc == "RelativeXX" then
			h = sz[3] * pw + sz[4]
		elseif sc == "RelativeYY" then
			w = sz[1] * ph + sz[2]
		end
		for _, c in ipairs(d.children) do
			local cd = D[c]
			if cd.class.name == "UIAspectRatioConstraint" and h > 0 and w > 0 then
				local ratio = I.get(cd, "AspectRatio")
				if D[I.get(cd, "AspectType")].Name == "FitWithinMaxSize" then
					if w / h > ratio then
						w = h * ratio
					else
						h = w / ratio
					end
				elseif D[I.get(cd, "DominantAxis")].Name == "Width" then
					h = w / ratio
				else
					w = h * ratio
				end
			elseif cd.class.name == "UIScale" then
				local s = I.get(cd, "Scale")
				w, h = w * s, h * s
			end
		end
		return px + pos[1] * pw + pos[2] - ap[1] * w, py + pos[3] * ph + pos[4] - ap[2] * h, w, h
	end
	return 0, 0, 0, 0
end

-- GUI นี้แสดงบนจอของผู้เล่น player จริงไหม (Visible ทุกชั้น, ScreenGui Enabled, อยู่ใต้ PlayerGui ของคนนั้น)
function I.guiOnScreen(d, player)
	local cur = d
	while cur do
		local cls = cur.class
		if cls.isGuiObject and not I.get(cur, "Visible") then
			return false, cur.name .. " is not Visible"
		end
		if cls.isLayerCollector and not I.get(cur, "Enabled") then
			return false, cur.name .. " is not Enabled"
		end
		if cls.name == "PlayerGui" then
			if cur.parent == player then
				return true
			end
			return false, "under another player's PlayerGui"
		end
		cur = cur.parent and D[cur.parent]
	end
	return false, "not under the player's PlayerGui"
end

function I.textBounds(d)
	local text = I.get(d, "Text")
	local size = I.get(d, "TextSize")
	local lines, longest = 1, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local n = 0
		for _ in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			n = n + 1
		end
		if n > longest then
			longest = n
		end
	end
	local _, nl = text:gsub("\n", "")
	lines = lines + nl
	return V2(longest * size * 0.5, lines * size)
end

-- ---------------------------------------------------------------- ค่าที่ส่งผ่าน Remote/Bindable
local tableKind = R.tableKind
function I.copyValue(v, mode, toPeer, seen)
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "number" or t == "string" then
		return v
	elseif t == "table" then
		if seen[v] then
			throw("Cannot send tables with cyclic references")
		end
		local kind = tableKind(v)
		if not kind then
			throw("Cannot convert mixed or non-array tables: keys must be strings")
		end
		seen[v] = true
		local c = {}
		for k, x in pairs(v) do
			c[k] = I.copyValue(x, mode, toPeer, seen)
		end
		seen[v] = nil
		return c
	elseif t == "userdata" then
		local tn = typeOf(v)
		if tn == "Instance" then
			if toPeer and not I.visibleDeep(D[v], toPeer) then
				return nil -- instance ที่ฝั่งรับมองไม่เห็นจะกลายเป็น nil เหมือน Roblox
			end
			return v
		elseif tn == "RBXScriptSignal" or tn == "RBXScriptConnection" or tn == "userdata" or tn == "RaycastParams" or tn == "OverlapParams" or tn == "Random" then
			throw(fmt("%s cannot be sent through a %s", tn, mode))
		end
		return v
	elseif t == "function" and mode == "BindableEvent" then
		return v
	end
	throw(fmt("%s values cannot be sent through a %s", t, mode))
end

function I.copyArgs(args, mode, toPeer)
	local out = { n = args.n }
	for i = 1, args.n do
		out[i] = I.copyValue(args[i], mode, toPeer, {})
	end
	return out
end

local function peerGroup(ctx)
	if ctx.kind == "client" then
		return ctx.peer
	end
	return "server"
end
I.peerGroup = peerGroup

local function requireServer(what)
	return function(ctx)
		if ctx.kind == "client" then
			throw(what .. " can only be used on the server")
		end
	end
end
local function requireClient(what)
	return function(ctx)
		if ctx.kind ~= "client" then
			throw(what .. " can only be used on the client")
		end
	end
end

-- ---------------------------------------------------------------- tween easing
local EASE = {}
EASE.Linear = function(t) return t end
EASE.Sine = function(t) return 1 - cos(t * pi / 2) end
EASE.Quad = function(t) return t * t end
EASE.Cubic = function(t) return t * t * t end
EASE.Quart = function(t) return t * t * t * t end
EASE.Quint = function(t) return t * t * t * t * t end
EASE.Exponential = function(t)
	if t == 0 then
		return 0
	end
	return 2 ^ (10 * (t - 1))
end
EASE.Circular = function(t) return 1 - sqrt(math.max(0, 1 - t * t)) end
EASE.Back = function(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
local function bounceOut(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	end
	t = t - 2.625 / 2.75
	return 7.5625 * t * t + 0.984375
end
EASE.Bounce = function(t) return 1 - bounceOut(1 - t) end
EASE.Elastic = function(t)
	if t == 0 or t == 1 then
		return t
	end
	local p = 0.3
	return -(2 ^ (10 * (t - 1))) * sin((t - 1 - p / 4) * (2 * pi) / p)
end
function I.ease(alpha, style, dir)
	local f = EASE[D[style].Name] or EASE.Linear
	local dn = D[dir].Name
	if alpha <= 0 then
		return 0
	elseif alpha >= 1 then
		return 1
	end
	if dn == "In" then
		return f(alpha)
	elseif dn == "Out" then
		return 1 - f(1 - alpha)
	end
	if alpha < 0.5 then
		return f(alpha * 2) / 2
	end
	return 1 - f((1 - alpha) * 2) / 2
end

local TWEENABLE = { number = true, int = true, bool = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, Rect = true, Enum = true }
function I.lerpValue(t, a, b, alpha)
	if t == "number" or t == "int" then
		return a + (b - a) * alpha
	elseif t == "bool" or t == "Enum" then
		if alpha >= 1 then
			return b
		end
		return a
	elseif t == "UDim" then
		local x, y = D[a], D[b]
		return UD(x[1] + (y[1] - x[1]) * alpha, x[2] + (y[2] - x[2]) * alpha)
	elseif t == "Rect" then
		local x, y = D[a], D[b]
		return R.mkRect({ x[1] + (y[1] - x[1]) * alpha, x[2] + (y[2] - x[2]) * alpha, x[3] + (y[3] - x[3]) * alpha, x[4] + (y[4] - x[4]) * alpha })
	end
	return a:Lerp(b, alpha)
end

-- ============================================================================
-- คลาส Instance (รายชื่อ property เป็นชื่อจริงของ Roblox; ตั้ง property ที่ไม่มี -> error)
-- ============================================================================
local M = {} -- methods ของ Instance
function M.FindFirstChild(d, name, recursive)
	name = I.argName(name, 1, "FindFirstChild")
	local peer = I.peer(d.W)
	if recursive then
		for _, c in ipairs(I.descendants(d, peer)) do
			if D[c].name == name then
				return c
			end
		end
		return nil
	end
	return I.findChild(d, name, peer)
end
function M.FindFirstChildOfClass(d, cname)
	cname = I.argName(cname, 1, "FindFirstChildOfClass")
	for _, c in ipairs(I.children(d, I.peer(d.W))) do
		if D[c].class.name == cname then
			return c
		end
	end
	return nil
end
function M.FindFirstChildWhichIsA(d, cname, recursive)
	cname = I.argName(cname, 1, "FindFirstChildWhichIsA")
	local peer = I.peer(d.W)
	local list = recursive and I.descendants(d, peer) or I.children(d, peer)
	for _, c in ipairs(list) do
		if I.classIsAName(D[c].class, cname) then
			return c
		end
	end
	return nil
end
function M.FindFirstDescendant(d, name)
	name = I.argName(name, 1, "FindFirstDescendant")
	for _, c in ipairs(I.descendants(d, I.peer(d.W))) do
		if D[c].name == name then
			return c
		end
	end
	return nil
end
function M.FindFirstAncestor(d, name)
	name = I.argName(name, 1, "FindFirstAncestor")
	local cur = d.parent
	while cur do
		if D[cur].name == name then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
function M.FindFirstAncestorOfClass(d, cname)
	cname = I.argName(cname, 1, "FindFirstAncestorOfClass")
	local cur = d.parent
	while cur do
		if D[cur].class.name == cname then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
function M.FindFirstAncestorWhichIsA(d, cname)
	cname = I.argName(cname, 1, "FindFirstAncestorWhichIsA")
	local cur = d.parent
	while cur do
		if I.classIsAName(D[cur].class, cname) then
			return cur
		end
		cur = D[cur].parent
	end
	return nil
end
function M.GetChildren(d)
	return I.children(d, I.peer(d.W))
end
function M.GetDescendants(d)
	return I.descendants(d, I.peer(d.W))
end
function M.IsA(d, cname)
	if type(cname) ~= "string" then
		badArg(1, "IsA", "string", cname)
	end
	return I.classIsAName(d.class, cname)
end
function M.IsDescendantOf(d, anc)
	if not isInst(anc) then
		badArg(1, "IsDescendantOf", "Instance", anc)
	end
	return I.isDescendantOf(d, D[anc])
end
function M.IsAncestorOf(d, desc)
	if not isInst(desc) then
		badArg(1, "IsAncestorOf", "Instance", desc)
	end
	return I.isDescendantOf(D[desc], d)
end
function M.Destroy(d)
	if d.isService then
		throw(fmt("The Parent property of %s is locked, current parent: %s, new parent NULL", d.name, d.parent and D[d.parent].name or "NULL"))
	end
	I.destroy(d)
end
function M.Remove(d)
	I.setParent(d, nil)
end
function M.Clone(d)
	local ctx = S.ctx(d.W)
	local map = {}
	local p = I.clone(d, ctx.kind == "client" and ctx.peer or nil, map)
	I.remapRefs(map)
	return p
end
function M.ClearAllChildren(d)
	local peer = I.peer(d.W)
	local ch = d.children
	for i = #ch, 1, -1 do
		local c = ch[i]
		if c and I.visibleTo(D[c], peer) and not D[c].isService then
			I.destroy(D[c])
		end
	end
end
function M.GetFullName(d)
	return I.fullName(d)
end
function M.GetDebugId(d)
	return "stub_" .. d.id
end
function M.SetAttribute(d, name, value)
	I.setAttribute(d, name, value)
end
function M.GetAttribute(d, name)
	if type(name) ~= "string" then
		badArg(1, "GetAttribute", "string", name)
	end
	return d.attrs and d.attrs[name]
end
function M.GetAttributes(d)
	local out = {}
	if d.attrs then
		for k, v in pairs(d.attrs) do
			out[k] = v
		end
	end
	return out
end
function M.GetAttributeChangedSignal(d, name)
	if type(name) ~= "string" then
		badArg(1, "GetAttributeChangedSignal", "string", name)
	end
	d.attrSignals = d.attrSignals or {}
	local s = d.attrSignals[name]
	if not s then
		s = Sig.new(d.W, "AttributeChanged:" .. name)
		d.attrSignals[name] = s
	end
	return PX(s)
end
function M.GetPropertyChangedSignal(d, name)
	if type(name) ~= "string" then
		badArg(1, "GetPropertyChangedSignal", "string", name)
	end
	local m = d.class.members[name]
	if not m or m.kind ~= "prop" then
		throw(fmt("%s is not a valid property name.", name))
	end
	d.propSignals = d.propSignals or {}
	local s = d.propSignals[name]
	if not s then
		s = Sig.new(d.W, "PropertyChanged:" .. name)
		d.propSignals[name] = s
	end
	return PX(s)
end
function M.AddTag(d, tag)
	I.addTag(d, tag)
end
function M.RemoveTag(d, tag)
	I.removeTag(d, tag)
end
function M.HasTag(d, tag)
	return (d.tags and d.tags.set[tag]) or false
end
function M.GetTags(d)
	local out = {}
	if d.tags then
		for i, t in ipairs(d.tags.list) do
			out[i] = t
		end
	end
	return out
end
function M.WaitForChild(d, name, timeout)
	name = I.argName(name, 1, "WaitForChild")
	local W = d.W
	local peer = I.peer(W)
	local c = I.findChild(d, name, peer)
	if c then
		return c
	end
	if timeout ~= nil then
		timeout = checkNum(timeout, 2, "WaitForChild")
	end
	local _, root = S.currentThread(W)
	W.childWaits[#W.childWaits + 1] = { parent = d, name = name, co = root, peer = peer, start = W.time, timeout = timeout }
	return coyield()
end
function M.GetActor()
	return nil
end
function M.IsPropertyModified(d, name)
	return d.props[name] ~= nil
end
function M.ResetPropertyToDefault(d, name)
	if d.props[name] ~= nil then
		d.props[name] = nil
		I.changed(d, name)
	end
end

defClass("Instance", nil, {
	abstract = true,
	props = {
		Name = P("string", nil, { get = function(d) return d.name end, set = function(d, v) I.setName(d, v) end }),
		ClassName = RO("string", function(d) return d.class.name end),
		Parent = P("Instance", nil, { get = function(d) return d.parent end, set = function(d, v) I.setParent(d, v) end }),
		Archivable = P("bool", true),
		RobloxLocked = RO("bool", function() return false end),
	},
	methods = M,
	events = { "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "AttributeChanged" },
})

-- ---------------------------------------------------------------- 3D
defClass("PVInstance", "Instance", {
	abstract = true,
	methods = {
		GetPivot = function(d) return I.getPivot(d) end,
		PivotTo = function(d, cf) I.pivotTo(d, cf) end,
	},
})

local function partSize(d, v)
	local x = D[v]
	local function cl(n)
		if n < 0.001 then
			return 0.001
		elseif n > 2048 then
			return 2048
		end
		return n
	end
	I.rawSet(d, "Size", V3(cl(x[1]), cl(x[2]), cl(x[3])))
end
local function canQueryWatch(d, v, k)
	I.rawSet(d, k, v)
	d.W.canQueryCheck[d] = true
end
defClass("BasePart", "PVInstance", {
	abstract = true,
	isPart = true,
	props = {
		Anchored = P("bool", false),
		CanCollide = P("bool", true, { set = canQueryWatch }),
		CanQuery = P("bool", true, { set = canQueryWatch }),
		CanTouch = P("bool", true),
		CastShadow = P("bool", true),
		Transparency = P("number", 0),
		Reflectance = P("number", 0),
		LocalTransparencyModifier = P("number", 0),
		Locked = P("bool", false),
		Massless = P("bool", false),
		Material = EP("Material", "Plastic", {
			set = function(d, v)
				I.rawSet(d, "Material", v)
				local n = D[v].Name
				if (n == "Water" or n == "Air") and not d.W.warnedOnce[d] then
					-- Water/Air เป็นวัสดุของ Terrain เท่านั้น ใช้กับ Part ไม่ได้ผลตามที่คิด
					d.W.warnedOnce[d] = true
					d.W:warn(I.fullName(d) .. ": Enum.Material." .. n .. " is a Terrain-only material; use Glass/SmoothPlastic/Neon for parts")
				end
			end,
		}),
		MaterialVariant = P("string", ""),
		Color = P("Color3", RGB(163, 162, 165), {
			set = function(d, v)
				I.rawSet(d, "Color", v)
				I.changed(d, "BrickColor")
			end,
		}),
		BrickColor = P("BrickColor", nil, {
			get = function(d)
				local c = D[I.get(d, "Color")]
				return R.nearestBrick(c[1], c[2], c[3])
			end,
			set = function(d, v)
				I.rawSet(d, "Color", D[v].color)
				I.changed(d, "BrickColor")
			end,
		}),
		Size = P("Vector3", V3(4, 1.2, 2), { set = partSize }),
		CFrame = P("CFrame", IDENT, { set = function(d, v) I.setPartCF(d, v) end }),
		Position = P("Vector3", nil, {
			get = function(d)
				local c = D[I.partCF(d)]
				return V3(c[1], c[2], c[3])
			end,
			set = function(d, v)
				local c, p = D[I.partCF(d)], D[v]
				I.setPartCF(d, CF(p[1], p[2], p[3], unpack(c, 4, 12)))
			end,
		}),
		Orientation = P("Vector3", nil, {
			get = function(d)
				local rx, ry, rz = eulerYXZ(D[I.partCF(d)])
				return V3(math.deg(rx), math.deg(ry), math.deg(rz))
			end,
			set = function(d, v)
				local c, o = D[I.partCF(d)], D[v]
				I.setPartCF(d, CF(c[1], c[2], c[3], matYXZ(math.rad(o[1]), math.rad(o[2]), math.rad(o[3]))))
			end,
		}),
		Rotation = P("Vector3", nil, {
			get = function(d)
				local rx, ry, rz = eulerXYZ(D[I.partCF(d)])
				return V3(math.deg(rx), math.deg(ry), math.deg(rz))
			end,
			set = function(d, v)
				local c, o = D[I.partCF(d)], D[v]
				I.setPartCF(d, CF(c[1], c[2], c[3], matXYZ(math.rad(o[1]), math.rad(o[2]), math.rad(o[3]))))
			end,
		}),
		PivotOffset = P("CFrame", IDENT),
		CollisionGroup = P("string", "Default"),
		CollisionGroupId = P("int", 0),
		CustomPhysicalProperties = P("PhysicalProperties?", nil),
		AssemblyLinearVelocity = P("Vector3", Vector3.zero),
		AssemblyAngularVelocity = P("Vector3", Vector3.zero),
		Velocity = P("Vector3", Vector3.zero),
		RotVelocity = P("Vector3", Vector3.zero),
		AssemblyMass = RO("number", function(d)
			local s = D[I.get(d, "Size")]
			return s[1] * s[2] * s[3] * 0.7
		end),
		Mass = RO("number", function(d)
			local s = D[I.get(d, "Size")]
			return s[1] * s[2] * s[3] * 0.7
		end),
		AssemblyRootPart = RO("Instance", function(d) return PX(d) end),
		AssemblyCenterOfMass = RO("Vector3", function(d)
			local c = D[I.partCF(d)]
			return V3(c[1], c[2], c[3])
		end),
		ExtentsCFrame = RO("CFrame", function(d) return I.partCF(d) end),
		ExtentsSize = RO("Vector3", function(d) return I.get(d, "Size") end),
		ResizeIncrement = RO("int", function() return 1 end),
		RootPriority = P("int", 0),
		EnableFluidForces = P("bool", true),
		AudioCanCollide = P("bool", true),
		TopSurface = EP("SurfaceType", "Smooth"),
		BottomSurface = EP("SurfaceType", "Smooth"),
		FrontSurface = EP("SurfaceType", "Smooth"),
		BackSurface = EP("SurfaceType", "Smooth"),
		LeftSurface = EP("SurfaceType", "Smooth"),
		RightSurface = EP("SurfaceType", "Smooth"),
		ReceiveAge = RO("number", function() return 0 end),
	},
	methods = {
		GetMass = function(d) return I.get(d, "Mass") end,
		GetConnectedParts = function() return {} end,
		GetTouchingParts = function() return {} end,
		GetJoints = function() return {} end,
		GetNoCollisionConstraints = function() return {} end,
		GetRootPart = function(d) return PX(d) end,
		IsGrounded = function(d) return I.get(d, "Anchored") end,
		ApplyImpulse = function() end,
		ApplyAngularImpulse = function() end,
		ApplyImpulseAtPosition = function() end,
		GetVelocityAtPosition = function() return Vector3.zero end,
		BreakJoints = function() end,
		Resize = function() return true end,
		SetNetworkOwner = function(d, player)
			if S.ctx(d.W).kind == "client" then
				throw("SetNetworkOwner can only be called from the server")
			end
			if I.get(d, "Anchored") then
				throw("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.")
			end
			d.networkOwner = player
		end,
		SetNetworkOwnershipAuto = function() end,
		GetNetworkOwner = function(d) return d.networkOwner end,
		GetNetworkOwnershipAuto = function() return true end,
		CanSetNetworkOwnership = function(d)
			if I.get(d, "Anchored") then
				return false, "Cannot change network ownership of Anchored parts"
			end
			return true
		end,
	},
	events = { "Touched", "TouchEnded" },
})
defClass("Part", "BasePart", { props = { Shape = EP("PartType", "Block") } })
defClass("SpawnLocation", "Part", {
	props = {
		AllowTeamChangeOnTouch = P("bool", false),
		Duration = P("int", 10),
		Enabled = P("bool", true),
		Neutral = P("bool", true),
		TeamColor = P("BrickColor", R.BC(R.BC_BY_NUM[194])),
	},
})
defClass("WedgePart", "BasePart")
defClass("CornerWedgePart", "BasePart")
defClass("TrussPart", "BasePart")
defClass("MeshPart", "BasePart", {
	props = {
		MeshId = P("Content", "", { ro = "Unable to assign property MeshId. Script write access is restricted (MeshId of a MeshPart can only be set in Studio)" }),
		TextureID = P("Content", ""),
		DoubleSided = RO("bool", function() return false end),
		MeshSize = RO("Vector3", function(d) return I.get(d, "Size") end),
		RenderFidelity = EP("RenderFidelity", "Automatic", { ro = "Unable to assign property RenderFidelity. Script write access is restricted" }),
		CollisionFidelity = EP("CollisionFidelity", "Default", { ro = "Unable to assign property CollisionFidelity. Script write access is restricted" }),
	},
})
defClass("Terrain", "BasePart", {
	notCreatable = true,
	notClonable = true,
	defaultName = "Terrain",
	props = {
		WaterColor = P("Color3", RGB(12, 84, 92)),
		WaterReflectance = P("number", 1),
		WaterTransparency = P("number", 0.3),
		WaterWaveSize = P("number", 0.15),
		WaterWaveSpeed = P("number", 10),
		Decoration = P("bool", false),
	},
	methods = {
		Clear = function() end,
		FillBlock = function() end,
		FillBall = function() end,
		FillCylinder = function() end,
		FillWedge = function() end,
	},
})

local MODEL_METHODS = {
	GetBoundingBox = function(d)
		local pp = I.primaryPart(d)
		local rot
		if pp then
			rot = D[I.partCF(D[pp])]
		elseif d.worldPivotSet then
			rot = D[d.props.WorldPivot]
		else
			rot = D[IDENT]
		end
		local cf, size = I.bbox(d, rot)
		if not cf then
			return I.modelPivot(d), Vector3.zero
		end
		return cf, size
	end,
	GetExtentsSize = function(d)
		local _, size = I.bbox(d, D[IDENT])
		return size or Vector3.zero
	end,
	MoveTo = function(d, pos)
		local p = v3arg(pos, 1, "MoveTo")
		local cur = D[I.modelPivot(d)]
		I.pivotTo(d, CF(p[1], p[2], p[3], unpack(cur, 4, 12)))
	end,
	TranslateBy = function(d, v)
		local p = v3arg(v, 1, "TranslateBy")
		local cur = D[I.modelPivot(d)]
		I.pivotTo(d, CF(cur[1] + p[1], cur[2] + p[2], cur[3] + p[3], unpack(cur, 4, 12)))
	end,
	SetPrimaryPartCFrame = function(d, cf)
		local pp = I.primaryPart(d)
		if not pp then
			throw("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.")
		end
		I.pivotTo(d, cfMul(D[R.cfArg(cf, 1, "SetPrimaryPartCFrame")], D[I.get(D[pp], "PivotOffset")]))
	end,
	GetPrimaryPartCFrame = function(d)
		local pp = I.primaryPart(d)
		if not pp then
			return nil
		end
		return I.partCF(D[pp])
	end,
	GetModelCFrame = function(d)
		return I.modelPivot(d)
	end,
	GetScale = function(d)
		return d.scale or 1
	end,
	ScaleTo = function(d, s)
		s = checkNum(s, 1, "ScaleTo")
		if s <= 0 then
			throw("Model:ScaleTo() scale factor must be positive")
		end
		local f = s / (d.scale or 1)
		local pivot = D[I.modelPivot(d)]
		local inv = cfInvData(pivot)
		for _, pd in ipairs(I.descParts(d)) do
			local rel = D[cfMul(inv, D[I.partCF(pd)])]
			local sz = D[I.get(pd, "Size")]
			I.rawSet(pd, "Size", V3(sz[1] * f, sz[2] * f, sz[3] * f))
			I.setPartCF(pd, cfMul(pivot, D[CF(rel[1] * f, rel[2] * f, rel[3] * f, unpack(rel, 4, 12))]))
		end
		d.scale = s
	end,
	BreakJoints = function() end,
	MakeJoints = function() end,
}
local MODEL_PROPS = {
	PrimaryPart = IP("BasePart", {
		get = function(d) return I.primaryPart(d) end,
		set = function(d, v)
			if v and not I.isDescendantOf(D[v], d) then
				-- Roblox ต้องการให้ PrimaryPart เป็นลูกหลานของ Model -> เตือนให้ใส่ part เข้า Model ก่อน
				d.W:warn(fmt("%s.PrimaryPart was set to %s which is not a descendant of the Model (parent the part into the Model first)", I.fullName(d), I.fullName(D[v])))
			end
			I.rawSet(d, "PrimaryPart", v)
		end,
	}),
	WorldPivot = P("CFrame", nil, {
		get = function(d)
			if d.worldPivotSet then
				return d.props.WorldPivot
			end
			return (I.bbox(d, D[IDENT])) or IDENT
		end,
		set = function(d, v)
			d.worldPivotSet = true
			I.rawSet(d, "WorldPivot", v)
		end,
	}),
	LevelOfDetail = EP("ModelLevelOfDetail", "Automatic"),
	ModelStreamingMode = EP("ModelStreamingMode", "Default"),
}
defClass("Model", "PVInstance", { props = MODEL_PROPS, methods = MODEL_METHODS })
defClass("Actor", "Model")
defClass("Folder", "Instance")
defClass("Configuration", "Instance")

defClass("Attachment", "Instance", {
	props = {
		CFrame = P("CFrame", IDENT),
		Position = P("Vector3", nil, {
			get = function(d)
				local c = D[I.get(d, "CFrame")]
				return V3(c[1], c[2], c[3])
			end,
			set = function(d, v)
				local c, p = D[I.get(d, "CFrame")], D[v]
				I.rawSet(d, "CFrame", CF(p[1], p[2], p[3], unpack(c, 4, 12)))
			end,
		}),
		Orientation = P("Vector3", nil, {
			get = function(d)
				local rx, ry, rz = eulerYXZ(D[I.get(d, "CFrame")])
				return V3(math.deg(rx), math.deg(ry), math.deg(rz))
			end,
			set = function(d, v)
				local c, o = D[I.get(d, "CFrame")], D[v]
				I.rawSet(d, "CFrame", CF(c[1], c[2], c[3], matYXZ(math.rad(o[1]), math.rad(o[2]), math.rad(o[3]))))
			end,
		}),
		WorldCFrame = P("CFrame", nil, {
			get = function(d)
				local pd = d.parent and D[d.parent]
				if pd and pd.class.isPart then
					return cfMul(D[I.partCF(pd)], D[I.get(d, "CFrame")])
				end
				return I.get(d, "CFrame")
			end,
			set = function(d, v)
				local pd = d.parent and D[d.parent]
				if pd and pd.class.isPart then
					I.rawSet(d, "CFrame", cfMul(cfInvData(D[I.partCF(pd)]), D[v]))
				else
					I.rawSet(d, "CFrame", v)
				end
			end,
		}),
		WorldPosition = RO("Vector3", function(d)
			local pd = d.parent and D[d.parent]
			local c = D[I.get(d, "CFrame")]
			if pd and pd.class.isPart then
				return V3(cfPoint(D[I.partCF(pd)], c[1], c[2], c[3]))
			end
			return V3(c[1], c[2], c[3])
		end),
		Axis = RO("Vector3", function(d) return V3(D[I.get(d, "CFrame")][4], D[I.get(d, "CFrame")][7], D[I.get(d, "CFrame")][10]) end),
		SecondaryAxis = RO("Vector3", function(d) return V3(D[I.get(d, "CFrame")][5], D[I.get(d, "CFrame")][8], D[I.get(d, "CFrame")][11]) end),
		Visible = P("bool", false),
	},
	methods = { GetConstraints = function() return {} end },
})

local JOINT_PROPS = {
	Part0 = IP("BasePart"),
	Part1 = IP("BasePart"),
	Enabled = P("bool", true),
	Active = RO("bool", function(d) return I.get(d, "Enabled") and d.props.Part0 ~= nil and d.props.Part1 ~= nil end),
}
defClass("JointInstance", "Instance", { abstract = true, props = { C0 = P("CFrame", IDENT), C1 = P("CFrame", IDENT) } })
for k, v in pairs(JOINT_PROPS) do
	Classes.JointInstance.props[k] = v
end
defClass("Weld", "JointInstance")
defClass("Motor6D", "JointInstance", {
	props = {
		Transform = P("CFrame", IDENT),
		CurrentAngle = P("number", 0),
		DesiredAngle = P("number", 0),
		MaxVelocity = P("number", 0),
	},
})
defClass("WeldConstraint", "Instance", { props = JOINT_PROPS })
defClass("NoCollisionConstraint", "Instance", { props = { Part0 = IP("BasePart"), Part1 = IP("BasePart"), Enabled = P("bool", true) } })

defClass("Decal", "Instance", {
	props = {
		Texture = P("Content", ""),
		Color3 = P("Color3", RGB(255, 255, 255)),
		Transparency = P("number", 0),
		Face = EP("NormalId", "Front"),
		ZIndex = P("int", 1),
	},
})
defClass("Texture", "Decal", {
	props = {
		StudsPerTileU = P("number", 2),
		StudsPerTileV = P("number", 2),
		OffsetStudsU = P("number", 0),
		OffsetStudsV = P("number", 0),
	},
})
local SA_RO = "Unable to assign property %s. SurfaceAppearance properties can only be set in Studio"
defClass("SurfaceAppearance", "Instance", {
	props = {
		ColorMap = P("Content", "", { ro = fmt(SA_RO, "ColorMap") }),
		NormalMap = P("Content", "", { ro = fmt(SA_RO, "NormalMap") }),
		MetalnessMap = P("Content", "", { ro = fmt(SA_RO, "MetalnessMap") }),
		RoughnessMap = P("Content", "", { ro = fmt(SA_RO, "RoughnessMap") }),
		AlphaMode = EP("AlphaMode", "Overlay", { ro = fmt(SA_RO, "AlphaMode") }),
		Color = P("Color3", RGB(255, 255, 255)),
	},
})
defClass("SpecialMesh", "Instance", {
	props = {
		MeshType = EP("MeshType", "Head"),
		MeshId = P("Content", ""),
		TextureId = P("Content", ""),
		Scale = P("Vector3", V3(1, 1, 1)),
		Offset = P("Vector3", Vector3.zero),
		VertexColor = P("Vector3", V3(1, 1, 1)),
	},
})
defClass("BlockMesh", "Instance", { props = { Scale = P("Vector3", V3(1, 1, 1)), Offset = P("Vector3", Vector3.zero) } })
defClass("CylinderMesh", "Instance", { props = { Scale = P("Vector3", V3(1, 1, 1)), Offset = P("Vector3", Vector3.zero) } })
defClass("SelectionBox", "Instance", {
	props = {
		Adornee = IP("PVInstance"),
		Color3 = P("Color3", RGB(13, 105, 172)),
		LineThickness = P("number", 0.15),
		SurfaceColor3 = P("Color3", RGB(13, 105, 172)),
		SurfaceTransparency = P("number", 1),
		Transparency = P("number", 0),
		Visible = P("bool", true),
	},
})

defClass("ParticleEmitter", "Instance", {
	props = {
		Enabled = P("bool", true),
		Rate = P("number", 20),
		Lifetime = P("NumberRange", R.NumberRange.new(5, 10)),
		Speed = P("NumberRange", R.NumberRange.new(5)),
		SpreadAngle = P("Vector2", Vector2.zero),
		Color = P("ColorSequence", R.ColorSequence.new(RGB(255, 255, 255))),
		Size = P("NumberSequence", R.NumberSequence.new(1)),
		Transparency = P("NumberSequence", R.NumberSequence.new(0)),
		Squash = P("NumberSequence", R.NumberSequence.new(0)),
		LightEmission = P("number", 0),
		LightInfluence = P("number", 1),
		Brightness = P("number", 1),
		Texture = P("Content", "rbxasset://textures/particles/sparkles_main.dds"),
		Rotation = P("NumberRange", R.NumberRange.new(0)),
		RotSpeed = P("NumberRange", R.NumberRange.new(0)),
		Acceleration = P("Vector3", Vector3.zero),
		Drag = P("number", 0),
		EmissionDirection = EP("NormalId", "Top"),
		LockedToPart = P("bool", false),
		ZOffset = P("number", 0),
		TimeScale = P("number", 1),
		VelocityInheritance = P("number", 0),
		Orientation = EP("ParticleOrientation", "FacingCamera"),
		Shape = EP("ParticleEmitterShape", "Box"),
		ShapeStyle = EP("ParticleEmitterShapeStyle", "Volume"),
		ShapeInOut = EP("ParticleEmitterShapeInOut", "Outward"),
		ShapePartial = P("number", 1),
	},
	methods = {
		Emit = function(d, n)
			d.W.particlesEmitted[#d.W.particlesEmitted + 1] = { emitter = PX(d), count = optNum(n, 1, "Emit", 16) }
		end,
		Clear = function() end,
	},
})
local function lightProps(extra)
	local p = {
		Brightness = P("number", 1),
		Color = P("Color3", RGB(255, 255, 255)),
		Enabled = P("bool", true),
		Shadows = P("bool", false),
		Range = P("number", 8),
	}
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end
defClass("Light", "Instance", { abstract = true })
defClass("PointLight", "Light", { props = lightProps() })
defClass("SpotLight", "Light", { props = lightProps({ Angle = P("number", 90), Face = EP("NormalId", "Front"), Range = P("number", 16) }) })
defClass("SurfaceLight", "Light", { props = lightProps({ Angle = P("number", 90), Face = EP("NormalId", "Front"), Range = P("number", 16) }) })
defClass("Highlight", "Instance", {
	props = {
		Adornee = IP(nil),
		DepthMode = EP("HighlightDepthMode", "AlwaysOnTop"),
		Enabled = P("bool", true),
		FillColor = P("Color3", RGB(255, 0, 0)),
		FillTransparency = P("number", 0.5),
		OutlineColor = P("Color3", RGB(255, 255, 255)),
		OutlineTransparency = P("number", 0),
	},
})
defClass("Fire", "Instance", {
	props = {
		Color = P("Color3", RGB(236, 139, 70)),
		SecondaryColor = P("Color3", RGB(139, 80, 55)),
		Enabled = P("bool", true),
		Heat = P("number", 9),
		Size = P("number", 5),
		TimeScale = P("number", 1),
	},
})
defClass("Smoke", "Instance", {
	props = {
		Color = P("Color3", RGB(255, 255, 255)),
		Enabled = P("bool", true),
		Opacity = P("number", 0.5),
		RiseVelocity = P("number", 1),
		Size = P("number", 1),
		TimeScale = P("number", 1),
	},
})
defClass("Sparkles", "Instance", { props = { SparkleColor = P("Color3", RGB(144, 25, 255)), Enabled = P("bool", true), TimeScale = P("number", 1) } })
defClass("Explosion", "Instance", {
	props = {
		BlastPressure = P("number", 500000),
		BlastRadius = P("number", 4),
		DestroyJointRadiusPercent = P("number", 1),
		ExplosionType = EP("ExplosionType", "Craters"),
		Position = P("Vector3", Vector3.zero),
		TimeScale = P("number", 1),
		Visible = P("bool", true),
	},
	events = { "Hit" },
})
defClass("Trail", "Instance", {
	props = {
		Attachment0 = IP("Attachment"),
		Attachment1 = IP("Attachment"),
		Color = P("ColorSequence", R.ColorSequence.new(RGB(255, 255, 255))),
		Transparency = P("NumberSequence", R.NumberSequence.new(0.5)),
		WidthScale = P("NumberSequence", R.NumberSequence.new(1)),
		Enabled = P("bool", true),
		FaceCamera = P("bool", false),
		Lifetime = P("number", 2),
		LightEmission = P("number", 0),
		LightInfluence = P("number", 0),
		MinLength = P("number", 0.1),
		MaxLength = P("number", 0),
		Texture = P("Content", ""),
	},
	methods = { Clear = function() end },
})
defClass("Beam", "Instance", {
	props = {
		Attachment0 = IP("Attachment"),
		Attachment1 = IP("Attachment"),
		Color = P("ColorSequence", R.ColorSequence.new(RGB(255, 255, 255))),
		Transparency = P("NumberSequence", R.NumberSequence.new(0.5)),
		Width0 = P("number", 1),
		Width1 = P("number", 1),
		CurveSize0 = P("number", 0),
		CurveSize1 = P("number", 0),
		Enabled = P("bool", true),
		FaceCamera = P("bool", false),
		LightEmission = P("number", 0),
		LightInfluence = P("number", 0),
		Segments = P("int", 10),
		Texture = P("Content", ""),
		TextureLength = P("number", 1),
		TextureSpeed = P("number", 1),
		ZOffset = P("number", 0),
	},
})
defClass("ForceField", "Instance", { props = { Visible = P("bool", true) } })
defClass("PVAdornment", "Instance", {
	abstract = true,
	props = {
		Adornee = IP("PVInstance"),
		Color3 = P("Color3", RGB(13, 105, 172)),
		Transparency = P("number", 0),
		Visible = P("bool", true),
	},
})
defClass("SelectionSphere", "PVAdornment", { props = { SurfaceColor3 = P("Color3", RGB(13, 105, 172)), SurfaceTransparency = P("number", 1) } })
defClass("HandleAdornment", "PVAdornment", {
	abstract = true,
	props = {
		AlwaysOnTop = P("bool", false),
		CFrame = P("CFrame", IDENT),
		SizeRelativeOffset = P("Vector3", Vector3.zero),
		ZIndex = P("int", -1),
	},
	events = { "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave" },
})
defClass("BoxHandleAdornment", "HandleAdornment", { props = { Size = P("Vector3", V3(1, 1, 1)) } })
defClass("SphereHandleAdornment", "HandleAdornment", { props = { Radius = P("number", 1) } })
defClass("CylinderHandleAdornment", "HandleAdornment", { props = { Height = P("number", 1), Radius = P("number", 1), InnerRadius = P("number", 0), Angle = P("number", 360) } })
defClass("ClickDetector", "Instance", {
	props = { MaxActivationDistance = P("number", 32), CursorIcon = P("Content", "") },
	events = { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" },
})

-- ---------------------------------------------------------------- Lighting effects
defClass("PostEffect", "Instance", { abstract = true, props = { Enabled = P("bool", true) } })
defClass("BloomEffect", "PostEffect", { props = { Intensity = P("number", 1), Size = P("number", 24), Threshold = P("number", 2) } })
defClass("BlurEffect", "PostEffect", { props = { Size = P("number", 24) } })
defClass("ColorCorrectionEffect", "PostEffect", {
	props = { Brightness = P("number", 0), Contrast = P("number", 0), Saturation = P("number", 0), TintColor = P("Color3", RGB(255, 255, 255)) },
})
defClass("SunRaysEffect", "PostEffect", { props = { Intensity = P("number", 0.25), Spread = P("number", 1) } })
defClass("DepthOfFieldEffect", "PostEffect", {
	props = { FarIntensity = P("number", 0.75), FocusDistance = P("number", 0.05), InFocusRadius = P("number", 10), NearIntensity = P("number", 0.75) },
})
defClass("Sky", "Instance", {
	props = {
		SkyboxBk = P("Content", ""), SkyboxDn = P("Content", ""), SkyboxFt = P("Content", ""),
		SkyboxLf = P("Content", ""), SkyboxRt = P("Content", ""), SkyboxUp = P("Content", ""),
		CelestialBodiesShown = P("bool", true), StarCount = P("int", 3000), SunAngularSize = P("number", 21),
		MoonAngularSize = P("number", 11), SunTextureId = P("Content", ""), MoonTextureId = P("Content", ""),
	},
})
defClass("Atmosphere", "Instance", {
	props = {
		Color = P("Color3", RGB(199, 199, 199)), Decay = P("Color3", RGB(106, 112, 125)), Density = P("number", 0.3),
		Glare = P("number", 0), Haze = P("number", 0), Offset = P("number", 0),
	},
})

-- ---------------------------------------------------------------- GUI
local Font = R.Font
defClass("GuiBase", "Instance", { abstract = true })
defClass("GuiBase2d", "GuiBase", {
	abstract = true,
	isGuiBase2d = true,
	props = {
		AbsolutePosition = RO("Vector2", function(d)
			local x, y = I.absRect(d)
			return V2(x, y)
		end),
		AbsoluteSize = RO("Vector2", function(d)
			local _, _, w, h = I.absRect(d)
			return V2(w, h)
		end),
		AbsoluteRotation = RO("number", function(d)
			if d.class.members.Rotation then
				return I.get(d, "Rotation")
			end
			return 0
		end),
		AutoLocalize = P("bool", true),
		RootLocalizationTable = IP("LocalizationTable"),
		SelectionGroup = P("bool", false),
		SelectionBehaviorUp = EP("SelectionBehavior", "Escape"),
		SelectionBehaviorDown = EP("SelectionBehavior", "Escape"),
		SelectionBehaviorLeft = EP("SelectionBehavior", "Escape"),
		SelectionBehaviorRight = EP("SelectionBehavior", "Escape"),
	},
})
defClass("LayerCollector", "GuiBase2d", {
	abstract = true,
	isLayerCollector = true,
	props = {
		Enabled = P("bool", true),
		ResetOnSpawn = P("bool", true),
		ZIndexBehavior = EP("ZIndexBehavior", "Sibling"),
	},
})
defClass("ScreenGui", "LayerCollector", {
	props = {
		DisplayOrder = P("int", 0),
		IgnoreGuiInset = P("bool", false),
		ScreenInsets = EP("ScreenInsets", "CoreUISafeInsets"),
		SafeAreaCompatibility = EP("SafeAreaCompatibility", "FullscreenExtension"),
		ClipToDeviceSafeArea = P("bool", true),
		OnTopOfCoreBlur = P("bool", false),
	},
})
defClass("BillboardGui", "LayerCollector", {
	props = {
		Active = P("bool", false),
		Adornee = IP(nil),
		AlwaysOnTop = P("bool", false),
		Brightness = P("number", 1),
		ClipsDescendants = P("bool", false),
		CurrentDistance = RO("number", function() return 0 end),
		DistanceLowerLimit = P("number", 0),
		DistanceStep = P("number", 0),
		DistanceUpperLimit = P("number", -1),
		ExtentsOffset = P("Vector3", Vector3.zero),
		ExtentsOffsetWorldSpace = P("Vector3", Vector3.zero),
		LightInfluence = P("number", 0),
		MaxDistance = P("number", huge),
		PlayerToHideFrom = IP("Player"),
		Size = P("UDim2", U2(0, 0, 0, 0)),
		SizeOffset = P("Vector2", Vector2.zero),
		StudsOffset = P("Vector3", Vector3.zero),
		StudsOffsetWorldSpace = P("Vector3", Vector3.zero),
	},
})
defClass("SurfaceGui", "LayerCollector", {
	props = {
		Active = P("bool", true),
		Adornee = IP(nil),
		AlwaysOnTop = P("bool", false),
		Brightness = P("number", 1),
		CanvasSize = P("Vector2", V2(800, 600)),
		ClipsDescendants = P("bool", true),
		Face = EP("NormalId", "Front"),
		LightInfluence = P("number", 0),
		MaxDistance = P("number", 0),
		PixelsPerStud = P("number", 50),
		SizingMode = EP("SurfaceGuiSizingMode", "FixedSize"),
		ToolPunchThroughDistance = P("number", 0),
		ZOffset = P("number", 0),
	},
})

local function guiTween(d, props, easingDir, easingStyle, t, override, callback)
	local W = d.W
	local dir = easingDir or E("EasingDirection", "Out")
	if type(dir) == "string" then
		dir = EnumTypes.EasingDirection.items[dir] or throw("Invalid EasingDirection " .. dir)
	end
	local style = easingStyle or E("EasingStyle", "Quad")
	if type(style) == "string" then
		style = EnumTypes.EasingStyle.items[style] or throw("Invalid EasingStyle " .. style)
	end
	for k in pairs(props) do
		if W.guiTweens[d] and W.guiTweens[d][k] and not override then
			return false
		end
	end
	local tw = I.createTween(W, d, R.TweenInfo.new(optNum(t, 4, "TweenPosition", 1), style, dir), props)
	W.guiTweens[d] = W.guiTweens[d] or {}
	for k in pairs(props) do
		W.guiTweens[d][k] = tw
	end
	D[tw].onComplete = function(state)
		for k in pairs(props) do
			if W.guiTweens[d] and W.guiTweens[d][k] == tw then
				W.guiTweens[d][k] = nil
			end
		end
		if type(callback) == "function" then
			local status = E("TweenStatus", D[state].Name == "Completed" and "Completed" or "Canceled")
			S.spawn(W, callback, S.ctx(W), status)
		end
	end
	tw.Play(tw)
	return true
end

defClass("GuiObject", "GuiBase2d", {
	abstract = true,
	isGuiObject = true,
	props = {
		Active = P("bool", false),
		AnchorPoint = P("Vector2", Vector2.zero),
		AutomaticSize = EP("AutomaticSize", "None"),
		BackgroundColor3 = P("Color3", RGB(163, 162, 165)),
		BackgroundTransparency = P("number", 0),
		BorderColor3 = P("Color3", RGB(27, 42, 53)),
		BorderMode = EP("BorderMode", "Outline"),
		BorderSizePixel = P("int", 1),
		ClipsDescendants = P("bool", false),
		Interactable = P("bool", true),
		LayoutOrder = P("int", 0),
		NextSelectionDown = IP("GuiObject"),
		NextSelectionLeft = IP("GuiObject"),
		NextSelectionRight = IP("GuiObject"),
		NextSelectionUp = IP("GuiObject"),
		Position = P("UDim2", U2(0, 0, 0, 0)),
		Rotation = P("number", 0),
		Selectable = P("bool", false),
		SelectionImageObject = IP("GuiObject"),
		SelectionOrder = P("int", 0),
		Size = P("UDim2", U2(0, 100, 0, 100)),
		SizeConstraint = EP("SizeConstraint", "RelativeXY"),
		Transparency = P("number", nil, {
			get = function(d) return I.get(d, "BackgroundTransparency") end,
			set = function(d, v) I.rawSet(d, "BackgroundTransparency", v) end,
		}),
		Visible = P("bool", true),
		ZIndex = P("int", 1),
	},
	methods = {
		TweenPosition = function(d, pos, dir, style, t, override, cb)
			if typeOf(pos) ~= "UDim2" then
				badArg(1, "TweenPosition", "UDim2", pos)
			end
			return guiTween(d, { Position = pos }, dir, style, t, override, cb)
		end,
		TweenSize = function(d, size, dir, style, t, override, cb)
			if typeOf(size) ~= "UDim2" then
				badArg(1, "TweenSize", "UDim2", size)
			end
			return guiTween(d, { Size = size }, dir, style, t, override, cb)
		end,
		TweenSizeAndPosition = function(d, size, pos, dir, style, t, override, cb)
			if typeOf(size) ~= "UDim2" then
				badArg(1, "TweenSizeAndPosition", "UDim2", size)
			end
			if typeOf(pos) ~= "UDim2" then
				badArg(2, "TweenSizeAndPosition", "UDim2", pos)
			end
			return guiTween(d, { Size = size, Position = pos }, dir, style, t, override, cb)
		end,
	},
	events = {
		"InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelBackward",
		"MouseWheelForward", "SelectionGained", "SelectionLost", "TouchLongPress", "TouchPan", "TouchPinch", "TouchRotate",
		"TouchSwipe", "TouchTap",
	},
})

local function textProps(defaultText)
	return {
		Text = P("string", defaultText),
		TextColor3 = P("Color3", RGB(27, 42, 53)),
		TextSize = P("number", 14),
		TextScaled = P("bool", false),
		TextWrapped = P("bool", false),
		TextWrap = P("bool", nil, {
			get = function(d) return I.get(d, "TextWrapped") end,
			set = function(d, v) I.rawSet(d, "TextWrapped", v) end,
		}),
		Font = EP("Font", "Legacy", {
			set = function(d, v)
				I.rawSet(d, "Font", v)
				I.rawSet(d, "FontFace", Font.fromEnum(v))
			end,
		}),
		FontFace = P("Font", Font.fromEnum(E("Font", "Legacy"))),
		TextXAlignment = EP("TextXAlignment", "Center"),
		TextYAlignment = EP("TextYAlignment", "Center"),
		TextTransparency = P("number", 0),
		TextStrokeColor3 = P("Color3", RGB(0, 0, 0)),
		TextStrokeTransparency = P("number", 1),
		RichText = P("bool", false),
		LineHeight = P("number", 1),
		MaxVisibleGraphemes = P("int", -1),
		FontSize = EP("FontSize", "Size14"),
		TextTruncate = EP("TextTruncate", "None"),
		TextDirection = EP("TextDirection", "Auto"),
		TextBounds = RO("Vector2", function(d) return I.textBounds(d) end),
		TextFits = RO("bool", function() return true end),
		ContentText = RO("string", function(d) return I.get(d, "Text") end),
		LocalizedText = RO("string", function(d) return I.get(d, "Text") end),
	}
end
local function imageProps()
	return {
		Image = P("Content", ""),
		ImageColor3 = P("Color3", RGB(255, 255, 255)),
		ImageTransparency = P("number", 0),
		ImageRectOffset = P("Vector2", Vector2.zero),
		ImageRectSize = P("Vector2", Vector2.zero),
		ScaleType = EP("ScaleType", "Stretch"),
		SliceCenter = P("Rect", R.Rect.new(0, 0, 0, 0)),
		SliceScale = P("number", 1),
		TileSize = P("UDim2", U2(1, 0, 1, 0)),
		ResampleMode = EP("ResamplerMode", "Default"),
		IsLoaded = RO("bool", function() return true end),
	}
end
defClass("Frame", "GuiObject")
defClass("ScrollingFrame", "GuiObject", {
	props = {
		AbsoluteCanvasSize = RO("Vector2", function(d)
			local _, _, w, h = I.absRect(d)
			local c = D[I.get(d, "CanvasSize")]
			return V2(c[1] * w + c[2], c[3] * h + c[4])
		end),
		AbsoluteWindowSize = RO("Vector2", function(d)
			local _, _, w, h = I.absRect(d)
			return V2(w, h)
		end),
		AutomaticCanvasSize = EP("AutomaticSize", "None"),
		BottomImage = P("Content", "rbxasset://textures/ui/Scroll/scroll-bottom.png"),
		MidImage = P("Content", "rbxasset://textures/ui/Scroll/scroll-middle.png"),
		TopImage = P("Content", "rbxasset://textures/ui/Scroll/scroll-top.png"),
		CanvasPosition = P("Vector2", Vector2.zero),
		CanvasSize = P("UDim2", U2(0, 0, 2, 0)),
		ElasticBehavior = EP("ElasticBehavior", "WhenScrollable"),
		HorizontalScrollBarInset = EP("ScrollBarInset", "None"),
		VerticalScrollBarInset = EP("ScrollBarInset", "None"),
		ScrollBarImageColor3 = P("Color3", RGB(255, 255, 255)),
		ScrollBarImageTransparency = P("number", 0),
		ScrollBarThickness = P("int", 12),
		ScrollingDirection = EP("ScrollingDirection", "XY"),
		ScrollingEnabled = P("bool", true),
		VerticalScrollBarPosition = EP("VerticalScrollBarPosition", "Right"),
	},
	defaults = { ClipsDescendants = true, Selectable = true, Active = true },
})
defClass("CanvasGroup", "GuiObject", { props = { GroupColor3 = P("Color3", RGB(255, 255, 255)), GroupTransparency = P("number", 0) } })
defClass("ViewportFrame", "GuiObject", {
	props = {
		Ambient = P("Color3", RGB(200, 200, 200)),
		CurrentCamera = IP("Camera"),
		ImageColor3 = P("Color3", RGB(255, 255, 255)),
		ImageTransparency = P("number", 0),
		LightColor = P("Color3", RGB(140, 140, 140)),
		LightDirection = P("Vector3", V3(-1, -1, -1)),
	},
})
defClass("GuiLabel", "GuiObject", { abstract = true })
defClass("TextLabel", "GuiLabel", { props = textProps("Label"), defaults = { Size = U2(0, 200, 0, 50) } })
defClass("ImageLabel", "GuiLabel", { props = imageProps() })
defClass("GuiButton", "GuiObject", {
	abstract = true,
	isGuiButton = true,
	props = {
		AutoButtonColor = P("bool", true),
		Modal = P("bool", false),
		Selected = P("bool", false),
		Style = EP("ButtonStyle", "Custom"),
	},
	defaults = { Active = true, Selectable = true },
	events = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" },
})
defClass("TextButton", "GuiButton", { props = textProps("Button"), defaults = { Size = U2(0, 200, 0, 50) } })
do
	local ip = imageProps()
	ip.HoverImage = P("Content", "")
	ip.PressedImage = P("Content", "")
	defClass("ImageButton", "GuiButton", { props = ip })
end
do
	local tp = textProps("")
	tp.PlaceholderText = P("string", "")
	tp.PlaceholderColor3 = P("Color3", RGB(178, 178, 178))
	tp.ClearTextOnFocus = P("bool", true)
	tp.MultiLine = P("bool", false)
	tp.TextEditable = P("bool", true)
	tp.CursorPosition = P("int", 1)
	tp.SelectionStart = P("int", -1)
	tp.ShowNativeInput = P("bool", true)
	defClass("TextBox", "GuiObject", {
		props = tp,
		defaults = { Size = U2(0, 200, 0, 50), Active = true, Selectable = true },
		methods = {
			CaptureFocus = function(d) d.focused = true end,
			ReleaseFocus = function(d) d.focused = false end,
			IsFocused = function(d) return d.focused == true end,
		},
		events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
	})
end

defClass("UIBase", "Instance", { abstract = true })
defClass("UIComponent", "UIBase", { abstract = true })
defClass("UICorner", "UIComponent", { props = { CornerRadius = P("UDim", UD(0, 8)) } })
defClass("UIStroke", "UIComponent", {
	props = {
		ApplyStrokeMode = EP("ApplyStrokeMode", "Contextual"),
		Color = P("Color3", RGB(0, 0, 0)),
		Enabled = P("bool", true),
		LineJoinMode = EP("LineJoinMode", "Round"),
		Thickness = P("number", 1),
		Transparency = P("number", 0),
	},
})
defClass("UIGradient", "UIComponent", {
	props = {
		Color = P("ColorSequence", R.ColorSequence.new(RGB(255, 255, 255))),
		Enabled = P("bool", true),
		Offset = P("Vector2", Vector2.zero),
		Rotation = P("number", 0),
		Transparency = P("NumberSequence", R.NumberSequence.new(0)),
	},
})
defClass("UIPadding", "UIComponent", {
	props = {
		PaddingBottom = P("UDim", UD(0, 0)),
		PaddingLeft = P("UDim", UD(0, 0)),
		PaddingRight = P("UDim", UD(0, 0)),
		PaddingTop = P("UDim", UD(0, 0)),
	},
})
defClass("UIScale", "UIComponent", { props = { Scale = P("number", 1) } })
defClass("UIConstraint", "UIComponent", { abstract = true })
defClass("UIAspectRatioConstraint", "UIConstraint", {
	props = {
		AspectRatio = P("number", 1),
		AspectType = EP("AspectType", "FitWithinMaxSize"),
		DominantAxis = EP("DominantAxis", "Width"),
	},
})
defClass("UISizeConstraint", "UIConstraint", { props = { MaxSize = P("Vector2", V2(huge, huge)), MinSize = P("Vector2", Vector2.zero) } })
defClass("UITextSizeConstraint", "UIConstraint", { props = { MaxTextSize = P("int", 100), MinTextSize = P("int", 1) } })
defClass("UILayout", "UIComponent", { abstract = true })
defClass("UIGridStyleLayout", "UILayout", {
	abstract = true,
	props = {
		AbsoluteContentSize = RO("Vector2", function() return Vector2.zero end),
		FillDirection = EP("FillDirection", "Horizontal"),
		HorizontalAlignment = EP("HorizontalAlignment", "Left"),
		VerticalAlignment = EP("VerticalAlignment", "Top"),
		SortOrder = EP("SortOrder", "LayoutOrder"),
	},
	methods = { ApplyLayout = function() end },
})
defClass("UIListLayout", "UIGridStyleLayout", {
	props = { Padding = P("UDim", UD(0, 0)), Wraps = P("bool", false) },
	defaults = { FillDirection = E("FillDirection", "Vertical") },
})
defClass("UIGridLayout", "UIGridStyleLayout", {
	props = {
		AbsoluteCellCount = RO("Vector2", function() return Vector2.zero end),
		AbsoluteCellSize = RO("Vector2", function(d)
			local c = D[I.get(d, "CellSize")]
			return V2(c[2], c[4])
		end),
		CellPadding = P("UDim2", U2(0, 5, 0, 5)),
		CellSize = P("UDim2", U2(0, 100, 0, 100)),
		FillDirectionMaxCells = P("int", 0),
		StartCorner = EP("StartCorner", "TopLeft"),
	},
})

-- ---------------------------------------------------------------- Sound
function I.soundPlay(d)
	local W = d.W
	local id = I.get(d, "SoundId")
	W.soundLog[#W.soundLog + 1] = { sound = PX(d), id = id, name = d.name, time = W.time, peer = I.peer(W) }
	I.rawSet(d, "Playing", true)
	d.soundStart = W.time
	if id ~= "" and not I.get(d, "Looped") then
		W.playingSounds[d] = W.time + 1 / math.max(0.01, I.get(d, "PlaybackSpeed"))
	end
	local s = I.sig(d, "Played")
	if s then
		Sig.fire(s, nil, id)
	end
end
defClass("Sound", "Instance", {
	props = {
		SoundId = P("Content", ""),
		Volume = P("number", 0.5),
		Looped = P("bool", false),
		Playing = P("bool", false, {
			set = function(d, v)
				if v then
					I.soundPlay(d)
				else
					d.W.playingSounds[d] = nil
					I.rawSet(d, "Playing", false)
				end
			end,
		}),
		PlaybackSpeed = P("number", 1),
		TimePosition = P("number", 0),
		TimeLength = RO("number", function(d)
			if I.get(d, "SoundId") == "" then
				return 0
			end
			return 1
		end),
		IsPlaying = RO("bool", function(d) return d.props.Playing == true end),
		IsPaused = RO("bool", function(d) return d.props.Playing ~= true end),
		IsLoaded = RO("bool", function(d) return I.get(d, "SoundId") ~= "" end),
		PlaybackLoudness = RO("number", function() return 0 end),
		RollOffMaxDistance = P("number", 10000),
		RollOffMinDistance = P("number", 10),
		RollOffMode = EP("RollOffMode", "Inverse"),
		PlayOnRemove = P("bool", false),
		SoundGroup = IP("SoundGroup"),
	},
	methods = {
		Play = function(d)
			I.rawSet(d, "TimePosition", 0)
			I.soundPlay(d)
		end,
		Stop = function(d)
			d.W.playingSounds[d] = nil
			I.rawSet(d, "Playing", false)
			I.rawSet(d, "TimePosition", 0)
			Sig.fire(I.sig(d, "Stopped"), nil, I.get(d, "SoundId"))
		end,
		Pause = function(d)
			d.W.playingSounds[d] = nil
			I.rawSet(d, "Playing", false)
			Sig.fire(I.sig(d, "Paused"), nil, I.get(d, "SoundId"))
		end,
		Resume = function(d)
			I.soundPlay(d)
			Sig.fire(I.sig(d, "Resumed"), nil, I.get(d, "SoundId"))
		end,
	},
	events = { "Ended", "Played", "Paused", "Resumed", "Stopped", "Loaded", "DidLoop" },
	onDestroy = function(d)
		d.W.playingSounds[d] = nil
		if I.get(d, "PlayOnRemove") then
			I.soundPlay(d)
		end
	end,
})
defClass("SoundGroup", "Instance", { props = { Volume = P("number", 0.5) } })

-- ---------------------------------------------------------------- Camera
function I.worldToViewport(d, v, screen)
	local p = v3arg(v, 1, screen and "WorldToScreenPoint" or "WorldToViewportPoint")
	local inv = cfInvData(D[I.get(d, "CFrame")])
	local x, y, z = cfPoint(inv, p[1], p[2], p[3])
	local vp = D[I.get(d, "ViewportSize")]
	local tanV = math.tan(math.rad(I.get(d, "FieldOfView")) / 2)
	local aspect = vp[1] / vp[2]
	local depth = -z
	local sx = (x / (depth * tanV * aspect) + 1) / 2 * vp[1]
	local sy = (1 - y / (depth * tanV)) / 2 * vp[2]
	local onScreen = depth > 0 and sx >= 0 and sx <= vp[1] and sy >= 0 and sy <= vp[2]
	if screen then
		sy = sy - GUI_INSET
	end
	return V3(sx, sy, depth), onScreen
end
function I.viewportRay(d, x, y, depth)
	local vp = D[I.get(d, "ViewportSize")]
	local tanV = math.tan(math.rad(I.get(d, "FieldOfView")) / 2)
	local aspect = vp[1] / vp[2]
	local nx = (x / vp[1]) * 2 - 1
	local ny = 1 - (y / vp[2]) * 2
	local cf = D[I.get(d, "CFrame")]
	local dx, dy, dz = cfVector(cf, nx * tanV * aspect, ny * tanV, -1)
	local m = sqrt(dx * dx + dy * dy + dz * dz)
	depth = depth or 0
	return R.Ray.new(V3(cf[1] + dx / m * depth, cf[2] + dy / m * depth, cf[3] + dz / m * depth), V3(dx / m, dy / m, dz / m))
end
defClass("Camera", "PVInstance", {
	isCamera = true,
	props = {
		CFrame = P("CFrame", R.CFrame.lookAt(V3(0, 20, 20), V3(0, 0, 0))),
		Focus = P("CFrame", IDENT),
		FieldOfView = P("number", 70, {
			set = function(d, v)
				if v < 1 then
					v = 1
				elseif v > 120 then
					v = 120
				end
				I.rawSet(d, "FieldOfView", v)
			end,
		}),
		ViewportSize = RO("Vector2", function(d) return d.viewport or V2(1280, 720) end),
		CameraType = EP("CameraType", "Custom"),
		CameraSubject = IP(nil),
		NearPlaneZ = RO("number", function() return -0.1 end),
		HeadLocked = P("bool", true),
		HeadScale = P("number", 1),
		FieldOfViewMode = EP("FieldOfViewMode", "Vertical"),
		DiagonalFieldOfView = RO("number", function(d)
			local vp = D[I.get(d, "ViewportSize")]
			local tv = math.tan(math.rad(I.get(d, "FieldOfView")) / 2)
			return math.deg(2 * math.atan(tv * sqrt(1 + (vp[1] / vp[2]) ^ 2)))
		end),
		MaxAxisFieldOfView = RO("number", function(d)
			local vp = D[I.get(d, "ViewportSize")]
			local tv = math.tan(math.rad(I.get(d, "FieldOfView")) / 2)
			return math.deg(2 * math.atan(tv * math.max(1, vp[1] / vp[2])))
		end),
		VRTiltAndRollEnabled = P("bool", false),
	},
	methods = {
		WorldToViewportPoint = function(d, v) return I.worldToViewport(d, v, false) end,
		WorldToScreenPoint = function(d, v) return I.worldToViewport(d, v, true) end,
		ViewportPointToRay = function(d, x, y, depth)
			return I.viewportRay(d, checkNum(x, 1, "ViewportPointToRay"), checkNum(y, 2, "ViewportPointToRay"), optNum(depth, 3, "ViewportPointToRay", 0))
		end,
		ScreenPointToRay = function(d, x, y, depth)
			return I.viewportRay(d, checkNum(x, 1, "ScreenPointToRay"), checkNum(y, 2, "ScreenPointToRay") + GUI_INSET, optNum(depth, 3, "ScreenPointToRay", 0))
		end,
		GetPartsObscuringTarget = function() return {} end,
		GetRenderCFrame = function(d) return I.get(d, "CFrame") end,
		GetRoll = function() return 0 end,
		SetRoll = function() end,
		ZoomToExtents = function() end,
		GetLargestCutoffDistance = function() return 0 end,
	},
	events = { "InterpolationFinished" },
})

-- ---------------------------------------------------------------- values & scripts
defClass("ValueBase", "Instance", { abstract = true, isValue = true })
defClass("StringValue", "ValueBase", { props = { Value = P("string", "") } })
defClass("IntValue", "ValueBase", { props = { Value = P("int", 0) } })
defClass("NumberValue", "ValueBase", { props = { Value = P("number", 0) } })
defClass("BoolValue", "ValueBase", { props = { Value = P("bool", false) } })
defClass("ObjectValue", "ValueBase", { props = { Value = IP(nil) } })
defClass("Vector3Value", "ValueBase", { props = { Value = P("Vector3", Vector3.zero) } })
defClass("CFrameValue", "ValueBase", { props = { Value = P("CFrame", IDENT) } })
defClass("Color3Value", "ValueBase", { props = { Value = P("Color3", C3(0, 0, 0)) } })
defClass("BrickColorValue", "ValueBase", { props = { Value = P("BrickColor", R.BC(R.BC_BY_NUM[194])) } })

defClass("LuaSourceContainer", "Instance", {
	abstract = true,
	props = {
		Source = P("string", nil, {
			get = function() throw("The current thread cannot read 'Source' (lacking capability Plugin)") end,
			ro = "The current thread cannot write 'Source' (lacking capability Plugin)",
		}),
	},
})
defClass("BaseScript", "LuaSourceContainer", {
	abstract = true,
	props = {
		Enabled = P("bool", true, {
			set = function(d, v)
				I.rawSet(d, "Enabled", v)
				if not v then
					I.killScript(d)
				end
			end,
		}),
		Disabled = P("bool", nil, {
			get = function(d) return not I.get(d, "Enabled") end,
			set = function(d, v) I.set(d, "Enabled", not v) end,
		}),
		RunContext = EP("RunContext", "Legacy"),
		LinkedSource = P("Content", ""),
	},
	onDestroy = function(d) I.killScript(d) end,
})
defClass("Script", "BaseScript")
defClass("LocalScript", "Script")
defClass("ModuleScript", "LuaSourceContainer", { props = { LinkedSource = P("Content", "") } })
function I.killScript(d)
	local list = d.W.scriptCtx[PX(d)]
	if list then
		for _, ctx in ipairs(list) do
			ctx.alive = false
		end
	end
end

-- ---------------------------------------------------------------- remotes & bindables
local function playerArg(v, fname)
	if not isInst(v) or D[v].class.name ~= "Player" then
		throw(fname .. ": player argument must be a Player object")
	end
	return v
end
local REMOTE_METHODS = {
	FireServer = function(d, ...)
		local W = d.W
		local ctx = S.ctx(W)
		if ctx.kind ~= "client" then
			throw("FireServer can only be called from the client")
		end
		local args = I.copyArgs(pack(...), d.class.name, "server")
		W.remoteQueue[#W.remoteQueue + 1] = { kind = "server", remote = d, player = ctx.player, args = args }
	end,
	FireClient = function(d, player, ...)
		local W = d.W
		if S.ctx(W).kind == "client" then
			throw("FireClient can only be called from the server")
		end
		playerArg(player, "FireClient")
		local pc = W.clientsByPlayer[player]
		local args = I.copyArgs(pack(...), d.class.name, pc and pc.peer)
		if pc then
			W.remoteQueue[#W.remoteQueue + 1] = { kind = "client", remote = d, player = player, args = args }
		end
	end,
	FireAllClients = function(d, ...)
		local W = d.W
		if S.ctx(W).kind == "client" then
			throw("FireAllClients can only be called from the server")
		end
		local raw = pack(...)
		I.copyArgs(raw, d.class.name, nil) -- ตรวจชนิดก่อน (error ที่บรรทัดของผู้เรียก)
		for _, pp in ipairs(W.playerList) do
			local pc = W.clientsByPlayer[pp]
			W.remoteQueue[#W.remoteQueue + 1] = { kind = "client", remote = d, player = pp, args = I.copyArgs(raw, d.class.name, pc.peer) }
		end
	end,
}
local REMOTE_EVENT_OPTS = {
	OnServerEvent = { check = requireServer("OnServerEvent") },
	OnClientEvent = { check = requireClient("OnClientEvent") },
}
defClass("BaseRemoteEvent", "Instance", { abstract = true, methods = REMOTE_METHODS, events = { "OnServerEvent", "OnClientEvent" }, eventOpts = REMOTE_EVENT_OPTS })
defClass("RemoteEvent", "BaseRemoteEvent")
defClass("UnreliableRemoteEvent", "BaseRemoteEvent")

function I.callbackFor(d, name, group)
	local cbs = d.callbacks
	if not cbs then
		return nil
	end
	local cb = cbs[name]
	if cb and cb.ctx.alive and (group == nil or peerGroup(cb.ctx) == group) then
		return cb
	end
	return nil
end
defClass("RemoteFunction", "Instance", {
	methods = {
		InvokeServer = function(d, ...)
			local W = d.W
			local ctx = S.ctx(W)
			if ctx.kind ~= "client" then
				throw("InvokeServer can only be called from the client")
			end
			local args = I.copyArgs(pack(...), "RemoteFunction", "server")
			local _, root = S.currentThread(W)
			W.remoteQueue[#W.remoteQueue + 1] = { kind = "invokeServer", remote = d, player = ctx.player, args = args, co = root, peer = ctx.peer }
			local res = pack(coyield())
			if not res[1] then
				throw(res[2])
			end
			return unpack(res, 2, res.n)
		end,
		InvokeClient = function(d, player, ...)
			local W = d.W
			if S.ctx(W).kind == "client" then
				throw("InvokeClient can only be called from the server")
			end
			playerArg(player, "InvokeClient")
			local pc = W.clientsByPlayer[player]
			if not pc then
				throw("InvokeClient: player is not in the game")
			end
			local args = I.copyArgs(pack(...), "RemoteFunction", pc.peer)
			local _, root = S.currentThread(W)
			W.remoteQueue[#W.remoteQueue + 1] = { kind = "invokeClient", remote = d, player = player, args = args, co = root, peer = pc.peer }
			local res = pack(coyield())
			if not res[1] then
				throw(res[2])
			end
			return unpack(res, 2, res.n)
		end,
	},
	callbacks = {
		OnServerInvoke = {
			check = function(ctx)
				if ctx.kind == "client" then
					throw("OnServerInvoke can only be set on the server")
				end
			end,
		},
		OnClientInvoke = {
			check = function(ctx)
				if ctx.kind ~= "client" then
					throw("OnClientInvoke can only be set on the client")
				end
			end,
		},
	},
})
defClass("BindableEvent", "Instance", {
	methods = {
		Fire = function(d, ...)
			local W = d.W
			local group = peerGroup(S.ctx(W))
			local args = I.copyArgs(pack(...), "BindableEvent", nil)
			Sig.fire(I.event(d, "Event", d.class.members.Event), function(ctx) return peerGroup(ctx) == group end, unpack(args, 1, args.n))
		end,
	},
	events = { "Event" },
})
defClass("BindableFunction", "Instance", {
	methods = {
		Invoke = function(d, ...)
			local W = d.W
			local group = peerGroup(S.ctx(W))
			local cb = I.callbackFor(d, "OnInvoke", group)
			if not cb then
				throw("BindableFunction:Invoke failed because OnInvoke is not set")
			end
			local args = I.copyArgs(pack(...), "BindableEvent", nil)
			return cb.fn(unpack(args, 1, args.n))
		end,
	},
	callbacks = { OnInvoke = {} },
})

-- ---------------------------------------------------------------- tween instance
function I.createTween(W, target, info, goals)
	local list = {}
	for k, v in pairs(goals) do
		if type(k) ~= "string" then
			throw("TweenService:Create property names must be strings")
		end
		local m = target.class.members[k]
		if not m or m.kind ~= "prop" then
			throw(fmt("TweenService:Create no property named '%s' for object '%s'", k, target.name))
		end
		if m.ro then
			throw(fmt("TweenService:Create property named '%s' on object '%s' is not tweenable (read only)", k, target.name))
		end
		local ok = I.coerce(m, v)
		local vt = typeOf(v)
		if not TWEENABLE[m.type] or not ok or (m.type == "Enum" and not isEnumItem(v)) then
			throw(fmt("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')",
				k, TYPE_LABEL[m.type] or m.type, vt))
		end
		local _, cv = I.coerce(m, v)
		list[#list + 1] = { key = k, m = m, goal = cv }
	end
	tsort(list, function(a, b) return a.key < b.key end)
	local p, d = I.new(W, "Tween", S.ctx(W).kind == "client" and S.ctx(W).peer or nil)
	d.tween = { target = target, info = D[info], infoProxy = info, goals = list, state = E("PlaybackState", "Begin"), elapsed = 0 }
	return p
end
function I.tweenFinish(d, stateName)
	local tw = d.tween
	tw.state = E("PlaybackState", stateName)
	d.W.tweens[d] = nil
	I.changed(d, "PlaybackState")
	if d.onComplete then
		d.onComplete(tw.state)
	end
	Sig.fire(I.sig(d, "Completed"), nil, tw.state)
end
function I.tweenStep(d, dt)
	local tw = d.tween
	local target = tw.target
	if target.destroyed then
		d.W.tweens[d] = nil
		tw.state = E("PlaybackState", "Cancelled")
		return
	end
	tw.elapsed = tw.elapsed + dt
	local info = tw.info
	local t = tw.elapsed - info.DelayTime
	if t < 0 then
		tw.state = E("PlaybackState", "Delayed")
		return
	end
	tw.state = E("PlaybackState", "Playing")
	local T = info.Time
	local cycle = info.Reverses and 2 * T or T
	local finished, alpha = false, 1
	if cycle <= 0 then
		finished = true
		alpha = info.Reverses and 0 or 1
	else
		local k = floor(t / cycle)
		if info.RepeatCount >= 0 and k > info.RepeatCount then
			finished = true
			alpha = info.Reverses and 0 or 1
		else
			local u = t - k * cycle
			if info.Reverses and u > T then
				u = 2 * T - u
			end
			alpha = I.ease(u / T, info.EasingStyle, info.EasingDirection)
		end
	end
	for _, g in ipairs(tw.goals) do
		local v
		if finished then
			v = alpha >= 1 and g.goal or g.from
		else
			v = I.lerpValue(g.m.type, g.from, g.goal, alpha)
		end
		if g.m.set then
			g.m.set(target, v, g.key)
		else
			I.rawSet(target, g.key, v)
		end
	end
	if finished then
		I.tweenFinish(d, "Completed")
	end
end
defClass("TweenBase", "Instance", {
	abstract = true,
	notClonable = true,
	props = {
		PlaybackState = RO("Enum", function(d) return d.tween.state end),
	},
	methods = {
		Play = function(d)
			local W = d.W
			local tw = d.tween
			local sn = D[tw.state].Name
			if sn == "Playing" or sn == "Delayed" then
				return
			end
			if sn ~= "Paused" then
				tw.elapsed = 0
				for _, g in ipairs(tw.goals) do
					g.from = I.get(tw.target, g.key)
				end
			end
			-- tween ใหม่ที่แตะ property เดียวกันจะแทนที่ tween เก่า (เหมือน Roblox)
			for other in pairs(W.tweens) do
				if other ~= d and other.tween.target == tw.target then
					for _, g in ipairs(other.tween.goals) do
						for _, g2 in ipairs(tw.goals) do
							if g.key == g2.key then
								W.tweens[other] = nil
								other.tween.state = E("PlaybackState", "Cancelled")
							end
						end
					end
				end
			end
			tw.state = E("PlaybackState", tw.info.DelayTime > 0 and "Delayed" or "Playing")
			W.tweens[d] = true
		end,
		Pause = function(d)
			if d.W.tweens[d] then
				d.W.tweens[d] = nil
				d.tween.state = E("PlaybackState", "Paused")
			end
		end,
		Cancel = function(d)
			local sn = D[d.tween.state].Name
			d.W.tweens[d] = nil
			d.tween.elapsed = 0
			if sn ~= "Completed" and sn ~= "Cancelled" then
				I.tweenFinish(d, "Cancelled")
			end
		end,
	},
	events = { "Completed" },
})
defClass("Tween", "TweenBase", {
	notCreatable = true,
	props = {
		Instance = RO("Instance", function(d) return PX(d.tween.target) end),
		TweenInfo = RO("TweenInfo", function(d) return d.tween.infoProxy end),
	},
})

-- ---------------------------------------------------------------- players & characters
function I.pcOf(W)
	local ctx = S.ctx(W)
	if ctx.kind == "client" then
		return W.clients[ctx.peer]
	end
	return nil
end
local function asyncYield(W)
	-- ฟังก์ชัน *Async ของ Roblox yield เสมอ (เรียกผ่าน HTTP) -> พัก 1 step
	S.waitFor(W, 0)
end

function I.loadCharacter(pd)
	local W = pd.W
	local old = I.get(pd, "Character")
	if old then
		Sig.fire(I.sig(pd, "CharacterRemoving"), nil, old)
		I.destroy(D[old])
	end
	local model, md = I.new(W, "Model")
	md.name = pd.name
	local hrp, hd = I.new(W, "Part")
	hd.name = "HumanoidRootPart"
	hd.props.Size = V3(2, 2, 1)
	hd.props.Transparency = 1
	hd.props.CFrame = CF(0, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	I.setParent(hd, model)
	local head, headD = I.new(W, "Part")
	headD.name = "Head"
	headD.props.Size = V3(2, 1, 1)
	headD.props.CFrame = CF(0, 4.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	I.setParent(headD, model)
	local _, humD = I.new(W, "Humanoid")
	I.setParent(humD, model)
	md.props.PrimaryPart = hrp
	I.setParent(md, W.workspace)
	I.rawSet(pd, "Character", model)
	-- StarterGui ถูกคัดลอกเข้า PlayerGui ตอนตัวละครเกิด (ถ้า CharacterAutoLoads = false จะไม่เกิดเอง)
	local pg = I.findChild(pd, "PlayerGui", "harness")
	if pg then
		local pgd = D[pg]
		for _, c in ipairs(I.children(pgd, "harness")) do
			local cd = D[c]
			if cd.class.isLayerCollector and I.get(cd, "ResetOnSpawn") then
				I.destroy(cd)
			end
		end
		for _, c in ipairs(I.children(D[W.services.StarterGui], "server")) do
			local map = {}
			local c2 = I.clone(D[c], nil, map)
			if c2 then
				I.remapRefs(map)
				I.setParent(D[c2], pg)
			end
		end
	end
	Sig.fire(I.sig(pd, "CharacterAdded"), nil, model)
	return model
end

defClass("Player", "Instance", {
	notCreatable = true,
	notClonable = true,
	props = {
		Name = P("string", nil, { get = function(d) return d.name end, ro = "Unable to assign property Name. Property is read only" }),
		DisplayName = P("string", nil, {
			get = function(d) return d.displayName or d.name end,
			set = function(d, v)
				d.displayName = v
				I.changed(d, "DisplayName")
			end,
		}),
		UserId = RO("number", function(d) return d.userId end),
		AccountAge = RO("number", function() return 365 end),
		Character = IP("Model"),
		CameraMode = EP("CameraMode", "Classic"),
		CameraMaxZoomDistance = P("number", 128),
		CameraMinZoomDistance = P("number", 0.5),
		AutoJumpEnabled = P("bool", true),
		CanLoadCharacterAppearance = P("bool", true),
		CharacterAppearanceId = P("int", 0),
		HealthDisplayDistance = P("number", 100),
		NameDisplayDistance = P("number", 100),
		Neutral = P("bool", true),
		Team = IP("Team"),
		TeamColor = P("BrickColor", R.BC(R.BC_BY_NUM[1])),
		RespawnLocation = IP("SpawnLocation"),
		LocaleId = RO("string", function() return "en-us" end),
		FollowUserId = RO("number", function() return 0 end),
		GameplayPaused = RO("bool", function() return false end),
		ReplicationFocus = IP(nil),
		DevTouchMovementMode = EP("DevTouchMovementMode", "UserChoice"),
		DevComputerMovementMode = EP("DevComputerMovementMode", "UserChoice"),
		DevTouchCameraMode = EP("DevTouchCameraMovementMode", "UserChoice"),
		DevComputerCameraMode = EP("DevComputerCameraMovementMode", "UserChoice"),
		DevEnableMouseLock = P("bool", true),
	},
	methods = {
		Kick = function(d, msg)
			local W = d.W
			local ctx = S.ctx(W)
			if ctx.kind == "client" and ctx.player ~= PX(d) then
				throw("Cannot kick a non-local Player from a LocalScript")
			end
			W.kicks[#W.kicks + 1] = { player = PX(d), name = d.name, message = msg }
			S.defer(W, function() W:removePlayer(PX(d)) end, W.harness)
		end,
		LoadCharacter = function(d)
			if S.ctx(d.W).kind == "client" then
				throw("LoadCharacter can only be called by the backend server")
			end
			I.loadCharacter(d)
		end,
		LoadCharacterAsync = function(d)
			if S.ctx(d.W).kind == "client" then
				throw("LoadCharacter can only be called by the backend server")
			end
			I.loadCharacter(d)
		end,
		GetMouse = function(d)
			if not d.mouse then
				local p = I.new(d.W, "PlayerMouse", d.W.clientsByPlayer[PX(d)] and d.W.clientsByPlayer[PX(d)].peer)
				d.mouse = p
			end
			return d.mouse
		end,
		GetNetworkPing = function() return 0.05 end,
		IsFriendsWith = function() return false end,
		GetRankInGroup = function() return 0 end,
		GetRoleInGroup = function() return "Guest" end,
		IsInGroup = function() return false end,
		HasAppearanceLoaded = function() return true end,
		GetJoinData = function() return {} end,
		DistanceFromCharacter = function() return 0 end,
		ClearCharacterAppearance = function() end,
		RequestStreamAroundAsync = function() end,
		GetFriendsOnline = function() return {} end,
	},
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" },
})
defClass("PlayerGui", "Instance", {
	notCreatable = true,
	props = {
		ScreenOrientation = EP("ScreenOrientation", "LandscapeSensor"),
		CurrentScreenOrientation = RO("Enum", function() return E("ScreenOrientation", "LandscapeLeft") end),
		SelectionImageObject = IP("GuiObject"),
	},
	methods = {
		GetTopbarTransparency = function() return 0.5 end,
		SetTopbarTransparency = function() end,
		GetGuiObjectsAtPosition = function(d, x, y)
			x = checkNum(x, 1, "GetGuiObjectsAtPosition")
			y = checkNum(y, 2, "GetGuiObjectsAtPosition")
			local out = {}
			local player = d.parent
			for _, c in ipairs(I.descendants(d, I.peer(d.W))) do
				local cd = D[c]
				if cd.class.isGuiObject and I.guiOnScreen(cd, player) then
					local ax, ay, w, h = I.absRect(cd)
					if x >= ax and x <= ax + w and y >= ay and y <= ay + h then
						tinsert(out, 1, c)
					end
				end
			end
			return out
		end,
	},
	events = { "TopbarTransparencyChangedSignal" },
})
defClass("PlayerScripts", "Instance", { notCreatable = true })
defClass("Backpack", "Instance")
defClass("StarterGear", "Instance", { notCreatable = true })
defClass("PlayerMouse", "Instance", {
	notCreatable = true,
	props = {
		Hit = RO("CFrame", function() return IDENT end),
		Origin = RO("CFrame", function() return IDENT end),
		Target = RO("Instance", function() return nil end),
		TargetFilter = IP(nil),
		TargetSurface = RO("Enum", function() return E("NormalId", "Top") end),
		UnitRay = RO("Ray", function() return R.Ray.new(Vector3.zero, V3(0, 0, -1)) end),
		X = RO("number", function() return 640 end),
		Y = RO("number", function() return 360 end),
		ViewSizeX = RO("number", function() return 1280 end),
		ViewSizeY = RO("number", function() return 720 end),
		Icon = P("Content", ""),
	},
	events = { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Idle", "Move", "WheelBackward", "WheelForward", "KeyDown", "KeyUp" },
})
defClass("InputObject", "Instance", {
	notCreatable = true,
	notClonable = true,
	props = {
		KeyCode = EP("KeyCode", "Unknown"),
		UserInputType = EP("UserInputType", "None"),
		UserInputState = EP("UserInputState", "None"),
		Position = P("Vector3", Vector3.zero),
		Delta = P("Vector3", Vector3.zero),
	},
	methods = { IsModifierKeyDown = function() return false end },
})
defClass("Humanoid", "Instance", {
	props = {
		Health = P("number", 100, {
			set = function(d, v)
				local mx = I.get(d, "MaxHealth")
				if v > mx then
					v = mx
				elseif v < 0 then
					v = 0
				end
				local old = I.get(d, "Health")
				I.rawSet(d, "Health", v)
				if v ~= old then
					Sig.fire(I.sig(d, "HealthChanged"), nil, v)
				end
				if v <= 0 and old > 0 then
					Sig.fire(I.sig(d, "Died"), nil)
				end
			end,
		}),
		MaxHealth = P("number", 100),
		WalkSpeed = P("number", 16),
		JumpPower = P("number", 50),
		JumpHeight = P("number", 7.2),
		UseJumpPower = P("bool", false),
		HipHeight = P("number", 2),
		AutoRotate = P("bool", true),
		AutoJumpEnabled = P("bool", true),
		BreakJointsOnDeath = P("bool", true),
		RequiresNeck = P("bool", true),
		DisplayName = P("string", ""),
		DisplayDistanceType = EP("HumanoidDisplayDistanceType", "Viewer"),
		HealthDisplayType = EP("HumanoidHealthDisplayType", "DisplayWhenDamaged"),
		HealthDisplayDistance = P("number", 100),
		NameDisplayDistance = P("number", 100),
		PlatformStand = P("bool", false),
		Sit = P("bool", false),
		Jump = P("bool", false),
		MoveDirection = RO("Vector3", function() return Vector3.zero end),
		RigType = EP("HumanoidRigType", "R15"),
		RootPart = RO("Instance", function(d)
			local m = d.parent and D[d.parent]
			return m and I.findChild(m, "HumanoidRootPart", "harness")
		end),
		FloorMaterial = RO("Enum", function() return E("Material", "Air") end),
		WalkToPoint = P("Vector3", Vector3.zero),
		WalkToPart = IP("BasePart"),
		MaxSlopeAngle = P("number", 89),
		EvaluateStateMachine = P("bool", true),
		CameraOffset = P("Vector3", Vector3.zero),
	},
	methods = {
		TakeDamage = function(d, n)
			I.set(d, "Health", I.get(d, "Health") - checkNum(n, 1, "TakeDamage"))
		end,
		Move = function() end,
		MoveTo = function() end,
		ChangeState = function(d, st)
			d.humState = st
		end,
		GetState = function(d) return d.humState or E("HumanoidStateType", "Running") end,
		SetStateEnabled = function() end,
		GetStateEnabled = function() return true end,
		EquipTool = function() end,
		UnequipTools = function() end,
		ApplyDescription = function() end,
		GetAppliedDescription = function() return nil end,
	},
	events = { "Died", "HealthChanged", "StateChanged", "Running", "Jumping", "MoveToFinished", "Touched", "Seated", "FreeFalling", "GettingUp", "Climbing" },
})
defClass("Team", "Instance", {
	props = { TeamColor = P("BrickColor", R.BC(R.BC_BY_NUM[1])), AutoAssignable = P("bool", true) },
	methods = {
		GetPlayers = function(d)
			local out = {}
			for _, p in ipairs(d.W.playerList) do
				if D[p].props.Team == PX(d) then
					out[#out + 1] = p
				end
			end
			return out
		end,
	},
	events = { "PlayerAdded", "PlayerRemoved" },
})
defClass("DataStore", "Instance", {
	notCreatable = true,
	methods = {
		GetAsync = function(d, key)
			local W = d.W
			if type(key) ~= "string" then
				badArg(1, "GetAsync", "string", key)
			end
			asyncYield(W)
			local s = d.store[key]
			if s == nil then
				return nil
			end
			return R.jsonDecode(s)
		end,
		SetAsync = function(d, key, value)
			if type(key) ~= "string" then
				badArg(1, "SetAsync", "string", key)
			end
			local ok, s = pcall(R.jsonEncode, value, {})
			if not ok then
				throw("Cannot store " .. typeOf(value) .. " in data store. Data stores can only accept valid UTF-8 characters and JSON-compatible values.")
			end
			asyncYield(d.W)
			d.store[key] = s
		end,
		UpdateAsync = function(d, key, fn)
			if type(key) ~= "string" then
				badArg(1, "UpdateAsync", "string", key)
			end
			asyncYield(d.W)
			local old = d.store[key] and R.jsonDecode(d.store[key])
			local new = fn(old)
			if new ~= nil then
				d.store[key] = R.jsonEncode(new, {})
			end
			return new
		end,
		RemoveAsync = function(d, key)
			asyncYield(d.W)
			local old = d.store[key] and R.jsonDecode(d.store[key])
			d.store[key] = nil
			return old
		end,
		IncrementAsync = function(d, key, delta)
			asyncYield(d.W)
			local v = (d.store[key] and R.jsonDecode(d.store[key]) or 0) + optNum(delta, 2, "IncrementAsync", 1)
			d.store[key] = R.jsonEncode(v, {})
			return v
		end,
	},
})

-- ---------------------------------------------------------------- services
local function svc(name, super, def)
	def = def or {}
	def.notCreatable = true
	def.notClonable = true
	def.isServiceClass = true
	return defClass(name, super or "Instance", def)
end

defClass("ServiceProvider", "Instance", {
	abstract = true,
	methods = {
		GetService = function(d, name)
			if type(name) ~= "string" then
				badArg(1, "GetService", "string", name)
			end
			local s = d.W.serviceByClass[name]
			if not s then
				throw(fmt("'%s' is not a valid Service name", name))
			end
			return s
		end,
		FindService = function(d, name)
			if type(name) ~= "string" then
				badArg(1, "FindService", "string", name)
			end
			return d.W.serviceByClass[name]
		end,
	},
})
svc("DataModel", "ServiceProvider", {
	defaultName = "Game",
	props = {
		PlaceId = RO("number", function() return 0 end),
		GameId = RO("number", function() return 0 end),
		JobId = RO("string", function() return "" end),
		CreatorId = RO("number", function() return 0 end),
		PlaceVersion = RO("number", function() return 0 end),
		PrivateServerId = RO("string", function() return "" end),
		PrivateServerOwnerId = RO("number", function() return 0 end),
		Workspace = RO("Instance", function(d) return d.W.workspace end),
	},
	methods = {
		IsLoaded = function() return true end,
		BindToClose = function(d, fn)
			if type(fn) ~= "function" then
				badArg(1, "BindToClose", "function", fn)
			end
			if S.ctx(d.W).kind == "client" then
				throw("BindToClose can only be called on the server")
			end
			d.W.closeCallbacks[#d.W.closeCallbacks + 1] = { fn = fn, ctx = S.ctx(d.W) }
		end,
	},
	events = { "Loaded", "Close" },
})

local function regionParts(W, ctx, params, test)
	local filterList, include, maxParts
	if params ~= nil then
		local mt = getmt(params)
		if mt ~= R.OVERLAP_MT and mt ~= R.RAYPARAMS_MT then
			badArg(2, "GetPartBounds", "OverlapParams", params)
		end
		local pd = D[params]
		filterList = pd.FilterDescendantsInstances
		include = D[pd.FilterType].Value == 1
		maxParts = pd.MaxParts
	end
	local out = {}
	for _, p in ipairs(I.descendants(D[W.workspace], ctx.peer)) do
		local pd = D[p]
		if pd.class.isPart and pd.class.name ~= "Terrain" and not (I.get(pd, "CanQuery") == false and I.get(pd, "CanCollide") == false) then
			local ok = true
			if filterList then
				local inList = false
				for _, f in ipairs(filterList) do
					if f == p or I.isDescendantOf(pd, D[f]) then
						inList = true
						break
					end
				end
				if include then
					ok = inList
				else
					ok = not inList
				end
			end
			if ok and test(pd) then
				out[#out + 1] = p
				if maxParts and maxParts > 0 and #out >= maxParts then
					break
				end
			end
		end
	end
	return out
end
local function partAABB(pd)
	-- กล่องแนวแกนโลกที่ครอบ part เดียว
	local c = D[I.partCF(pd)]
	local s = D[I.get(pd, "Size")]
	local hx, hy, hz = s[1] / 2, s[2] / 2, s[3] / 2
	local ex = abs(c[4]) * hx + abs(c[5]) * hy + abs(c[6]) * hz
	local ey = abs(c[7]) * hx + abs(c[8]) * hy + abs(c[9]) * hz
	local ez = abs(c[10]) * hx + abs(c[11]) * hy + abs(c[12]) * hz
	return c[1] - ex, c[2] - ey, c[3] - ez, c[1] + ex, c[2] + ey, c[3] + ez
end
-- ray กับกล่อง (ทุก shape คิดเป็นกล่อง) คืน t (0..1 ตามเวกเตอร์ทิศ) และ normal ในโลก
function I.rayBox(pd, o, dv)
	local c = D[I.partCF(pd)]
	local s = D[I.get(pd, "Size")]
	local lo = { cfVectorInv(c, o[1] - c[1], o[2] - c[2], o[3] - c[3]) }
	local ld = { cfVectorInv(c, dv[1], dv[2], dv[3]) }
	local tmin, tmax, axis, sgn = 0, 1, nil, 0
	for i = 1, 3 do
		local h = s[i] / 2
		if abs(ld[i]) < 1e-12 then
			if lo[i] < -h or lo[i] > h then
				return nil
			end
		else
			local t1 = (-h - lo[i]) / ld[i]
			local t2 = (h - lo[i]) / ld[i]
			local face = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				face = 1
			end
			if t1 > tmin then
				tmin, axis, sgn = t1, i, face
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	if not axis then
		return nil -- จุดเริ่มอยู่ในกล่อง: Roblox ไม่นับ part ที่ ray เริ่มข้างใน
	end
	local n = { 0, 0, 0 }
	n[axis] = sgn
	return tmin, cfVector(c, n[1], n[2], n[3])
end
defClass("WorldRoot", "Model", {
	abstract = true,
	methods = {
		Raycast = function(d, origin, dir, params)
			local o = v3arg(origin, 1, "Raycast")
			local dv = v3arg(dir, 2, "Raycast")
			if params ~= nil and getmt(params) ~= R.RAYPARAMS_MT then
				badArg(3, "Raycast", "RaycastParams", params)
			end
			local W = d.W
			local best, bt, bn
			local respect = params ~= nil and D[params].RespectCanCollide
			regionParts(W, S.ctx(W), params, function(pd)
				if respect and not I.get(pd, "CanCollide") then
					return false
				end
				local t, nx, ny, nz = I.rayBox(pd, o, dv)
				if t and (not bt or t < bt) then
					best, bt, bn = pd, t, { nx, ny, nz }
				end
				return false
			end)
			if not best then
				return nil
			end
			local len = sqrt(dv[1] * dv[1] + dv[2] * dv[2] + dv[3] * dv[3])
			return R.mkRR({
				Instance = PX(best),
				Position = V3(o[1] + dv[1] * bt, o[2] + dv[2] * bt, o[3] + dv[3] * bt),
				Normal = V3(bn[1], bn[2], bn[3]),
				Material = I.get(best, "Material"),
				Distance = bt * len,
			})
		end,
		GetPartBoundsInBox = function(d, cf, size, params)
			local c = R.cfArg(cf, 1, "GetPartBoundsInBox")
			local s = v3arg(size, 2, "GetPartBoundsInBox")
			local W = d.W
			local qx0, qx1 = c[1] - s[1] / 2, c[1] + s[1] / 2
			local qy0, qy1 = c[2] - s[2] / 2, c[2] + s[2] / 2
			local qz0, qz1 = c[3] - s[3] / 2, c[3] + s[3] / 2
			return regionParts(W, S.ctx(W), params, function(pd)
				local x0, y0, z0, x1, y1, z1 = partAABB(pd)
				return x0 <= qx1 and x1 >= qx0 and y0 <= qy1 and y1 >= qy0 and z0 <= qz1 and z1 >= qz0
			end)
		end,
		GetPartBoundsInRadius = function(d, pos, radius, params)
			local p = v3arg(pos, 1, "GetPartBoundsInRadius")
			radius = checkNum(radius, 2, "GetPartBoundsInRadius")
			local W = d.W
			return regionParts(W, S.ctx(W), params, function(pd)
				local x0, y0, z0, x1, y1, z1 = partAABB(pd)
				local dx = math.max(x0 - p[1], 0, p[1] - x1)
				local dy = math.max(y0 - p[2], 0, p[2] - y1)
				local dz = math.max(z0 - p[3], 0, p[3] - z1)
				return dx * dx + dy * dy + dz * dz <= radius * radius
			end)
		end,
		GetPartsInPart = function(d, part, params)
			if not isInst(part) or not D[part].class.isPart then
				badArg(1, "GetPartsInPart", "BasePart", part)
			end
			local W = d.W
			local qx0, qy0, qz0, qx1, qy1, qz1 = partAABB(D[part])
			return regionParts(W, S.ctx(W), params, function(pd)
				if PX(pd) == part then
					return false
				end
				local x0, y0, z0, x1, y1, z1 = partAABB(pd)
				return x0 < qx1 and x1 > qx0 and y0 < qy1 and y1 > qy0 and z0 < qz1 and z1 > qz0
			end)
		end,
		BulkMoveTo = function(d, parts, cfs)
			if type(parts) ~= "table" then
				badArg(1, "BulkMoveTo", "table", parts)
			end
			if type(cfs) ~= "table" then
				badArg(2, "BulkMoveTo", "table", cfs)
			end
			if #parts ~= #cfs then
				throw("BulkMoveTo: partList and cframeList must be the same length")
			end
			for i, p in ipairs(parts) do
				if not isInst(p) or not D[p].class.isPart then
					throw("BulkMoveTo: partList must only contain BaseParts")
				end
				if not isCF(cfs[i]) then
					throw("BulkMoveTo: cframeList must only contain CFrames")
				end
				I.setPartCF(D[p], cfs[i])
			end
		end,
		ArePartsTouchingOthers = function() return false end,
		Blockcast = function() return nil end,
		Spherecast = function() return nil end,
		Shapecast = function() return nil end,
	},
})
svc("Workspace", "WorldRoot", {
	props = {
		CurrentCamera = IP("Camera", {
			get = function(d)
				local W = d.W
				local ctx = S.ctx(W)
				if ctx.kind == "client" then
					local pc = W.clients[ctx.peer]
					return pc and pc.camera
				end
				return W.serverCamera
			end,
			set = function(d, v)
				local W = d.W
				local ctx = S.ctx(W)
				if ctx.kind == "client" then
					W.clients[ctx.peer].camera = v
				else
					W.serverCamera = v
				end
				I.changed(d, "CurrentCamera")
			end,
		}),
		Gravity = P("number", 196.2),
		DistributedGameTime = RO("number", function(d) return d.W.time end),
		FallenPartsDestroyHeight = P("number", -500),
		StreamingEnabled = RO("bool", function() return false end),
		FilteringEnabled = RO("bool", function() return true end),
		Terrain = RO("Instance", function(d) return d.W.terrain end),
		AllowThirdPartySales = P("bool", false),
		GlobalWind = P("Vector3", Vector3.zero),
		TouchesUseCollisionGroups = P("bool", false),
		AirDensity = P("number", 0.0012),
	},
	methods = {
		GetServerTimeNow = function(d) return R.EPOCH + d.W.time end,
		GetRealPhysicsFPS = function() return 60 end,
		GetNumAwakeParts = function() return 0 end,
		PGSIsEnabled = function() return true end,
	},
})

local function playersMethods()
	return {
		GetPlayers = function(d)
			local out = {}
			for i, p in ipairs(d.W.playerList) do
				out[i] = p
			end
			return out
		end,
		GetPlayerByUserId = function(d, id)
			id = checkNum(id, 1, "GetPlayerByUserId")
			for _, p in ipairs(d.W.playerList) do
				if D[p].userId == id then
					return p
				end
			end
			return nil
		end,
		GetPlayerFromCharacter = function(d, model)
			if model == nil then
				return nil
			end
			for _, p in ipairs(d.W.playerList) do
				if D[p].props.Character == model then
					return p
				end
			end
			return nil
		end,
		GetUserIdFromNameAsync = function(d, name)
			asyncYield(d.W)
			for _, p in ipairs(d.W.playerList) do
				if D[p].name == name then
					return D[p].userId
				end
			end
			throw("Players:GetUserIdFromNameAsync() failed: Unknown user")
		end,
		GetNameFromUserIdAsync = function(d, id)
			asyncYield(d.W)
			for _, p in ipairs(d.W.playerList) do
				if D[p].userId == id then
					return D[p].name
				end
			end
			throw("Players:GetNameFromUserIdAsync() failed: Unknown user")
		end,
		GetUserThumbnailAsync = function(d, id, ttype, tsize)
			checkNum(id, 1, "GetUserThumbnailAsync")
			R.enumArg(ttype, "ThumbnailType", 2, "GetUserThumbnailAsync")
			R.enumArg(tsize, "ThumbnailSize", 3, "GetUserThumbnailAsync")
			asyncYield(d.W)
			return "rbxthumb://type=AvatarHeadShot&id=" .. numStr(id) .. "&w=150&h=150", true
		end,
	}
end
svc("Players", "Instance", {
	props = {
		LocalPlayer = RO("Instance", function(d)
			local ctx = S.ctx(d.W)
			if ctx.kind == "client" then
				return ctx.player
			end
			return nil
		end),
		CharacterAutoLoads = P("bool", true),
		MaxPlayers = RO("int", function(d) return d.W.maxPlayers end),
		PreferredPlayers = RO("int", function(d) return d.W.maxPlayers end),
		RespawnTime = P("number", 5),
		BubbleChat = RO("bool", function() return true end),
		ClassicChat = RO("bool", function() return false end),
	},
	methods = playersMethods(),
	events = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
})
svc("Lighting", "Instance", {
	props = {
		Ambient = P("Color3", RGB(70, 70, 70)),
		Brightness = P("number", 2),
		ClockTime = P("number", 14),
		TimeOfDay = P("string", nil, {
			get = function(d)
				local t = I.get(d, "ClockTime") % 24
				local h = floor(t)
				local m = floor((t - h) * 60)
				local s = floor(((t - h) * 60 - m) * 60 + 0.5)
				return fmt("%02d:%02d:%02d", h, m, s)
			end,
			set = function(d, v)
				local h, m, s = v:match("^(%d+):?(%d*):?(%d*)$")
				if not h then
					throw("Unable to assign property TimeOfDay. Invalid time string")
				end
				I.rawSet(d, "ClockTime", (tonumber(h) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600) % 24)
				I.changed(d, "TimeOfDay")
			end,
		}),
		ColorShift_Bottom = P("Color3", C3(0, 0, 0)),
		ColorShift_Top = P("Color3", C3(0, 0, 0)),
		EnvironmentDiffuseScale = P("number", 0),
		EnvironmentSpecularScale = P("number", 0),
		ExposureCompensation = P("number", 0),
		FogColor = P("Color3", RGB(192, 192, 192)),
		FogEnd = P("number", 100000),
		FogStart = P("number", 0),
		GeographicLatitude = P("number", 41.733),
		GlobalShadows = P("bool", true),
		OutdoorAmbient = P("Color3", RGB(128, 128, 128)),
		ShadowSoftness = P("number", 0.2),
		Technology = EP("Technology", "ShadowMap", { ro = "Unable to assign property Technology. Technology can only be changed in Studio" }),
	},
	methods = {
		GetMinutesAfterMidnight = function(d) return I.get(d, "ClockTime") * 60 end,
		SetMinutesAfterMidnight = function(d, m) I.set(d, "ClockTime", (checkNum(m, 1, "SetMinutesAfterMidnight") / 60) % 24) end,
		GetSunDirection = function() return V3(0, 1, 0) end,
		GetMoonDirection = function() return V3(0, -1, 0) end,
	},
	events = { "LightingChanged" },
})
svc("ReplicatedStorage")
svc("ReplicatedFirst", "Instance", {
	methods = {
		RemoveDefaultLoadingScreen = function() end,
		IsFinishedReplicating = function() return true end,
		SetDefaultLoadingGuiEnabled = function() end,
	},
	events = { "FinishedReplicating", "RemoveDefaultLoadingGuiSignal" },
})
svc("ServerScriptService", "Instance", {
	props = { LoadStringEnabled = RO("bool", function() return false end) },
	init = function(d) d.serverOnly = true end,
})
svc("ServerStorage", "Instance", { init = function(d) d.serverOnly = true end })
svc("StarterPack")
svc("StarterPlayer", "Instance", {
	props = {
		CharacterWalkSpeed = P("number", 16),
		CharacterJumpPower = P("number", 50),
		CharacterJumpHeight = P("number", 7.2),
		CharacterUseJumpPower = P("bool", false),
		CharacterMaxSlopeAngle = P("number", 89),
		CameraMaxZoomDistance = P("number", 128),
		CameraMinZoomDistance = P("number", 0.5),
		CameraMode = EP("CameraMode", "Classic"),
		AutoJumpEnabled = P("bool", true),
		EnableMouseLockOption = P("bool", true),
		HealthDisplayDistance = P("number", 100),
		NameDisplayDistance = P("number", 100),
		LoadCharacterAppearance = P("bool", true),
		UserEmotesEnabled = P("bool", true),
		DevTouchMovementMode = EP("DevTouchMovementMode", "UserChoice"),
		DevComputerMovementMode = EP("DevComputerMovementMode", "UserChoice"),
		DevTouchCameraMovementMode = EP("DevTouchCameraMovementMode", "UserChoice"),
		DevComputerCameraMovementMode = EP("DevComputerCameraMovementMode", "UserChoice"),
	},
})
defClass("StarterPlayerScripts", "Instance", { notCreatable = true })
defClass("StarterCharacterScripts", "StarterPlayerScripts", { notCreatable = true })

local CORE_SET = {
	ResetButtonCallback = true, TopbarEnabled = true, ChatActive = true, SendNotification = true, ChatMakeSystemMessage = true,
	PointsNotificationsActive = true, BadgesNotificationsActive = true, AvatarContextMenuEnabled = true, DevConsoleVisible = true,
	ChatWindowPosition = true, ChatWindowSize = true, ChatBarDisabled = true, CoreGuiChatConnections = true, PlayerBlockedEvent = true,
	PlayerUnblockedEvent = true, PlayerMutedEvent = true, PlayerUnmutedEvent = true, PromptSendFriendRequest = true,
	PromptUnfriend = true, PromptBlockPlayer = true, PromptUnblockPlayer = true, SetAvatarContextMenuTarget = true,
	EnableMouseLockOption = true, AddAvatarContextMenuOption = true, RemoveAvatarContextMenuOption = true,
}
local function needClient(W, fname)
	local pc = I.pcOf(W)
	if not pc then
		throw(fname .. " can only be called from a LocalScript (client)")
	end
	return pc
end
svc("StarterGui", "Instance", {
	props = {
		ScreenOrientation = EP("ScreenOrientation", "LandscapeSensor"),
		ShowDevelopmentGui = P("bool", true),
		ResetPlayerGuiOnSpawn = P("bool", true),
	},
	methods = {
		SetCoreGuiEnabled = function(d, ctype, enabled)
			local pc = needClient(d.W, "SetCoreGuiEnabled")
			R.enumArg(ctype, "CoreGuiType", 1, "SetCoreGuiEnabled")
			if ctype == nil then
				throw("Argument 1 missing or nil")
			end
			if type(enabled) ~= "boolean" then
				badArg(2, "SetCoreGuiEnabled", "boolean", enabled)
			end
			local name = D[ctype].Name
			if name == "All" then
				for _, it in ipairs(EnumTypes.CoreGuiType.list) do
					pc.coreGui[D[it].Name] = enabled
				end
			else
				pc.coreGui[name] = enabled
			end
		end,
		GetCoreGuiEnabled = function(d, ctype)
			local pc = needClient(d.W, "GetCoreGuiEnabled")
			R.enumArg(ctype, "CoreGuiType", 1, "GetCoreGuiEnabled")
			if ctype == nil then
				throw("Argument 1 missing or nil")
			end
			local v = pc.coreGui[D[ctype].Name]
			return v ~= false
		end,
		SetCore = function(d, name, value)
			local pc = needClient(d.W, "SetCore")
			if type(name) ~= "string" then
				badArg(1, "SetCore", "string", name)
			end
			if not CORE_SET[name] then
				throw(fmt("SetCore: %s has not been registered by the CoreScripts", name))
			end
			pc.setCore[name] = value
		end,
		GetCore = function(d, name)
			local pc = needClient(d.W, "GetCore")
			if type(name) ~= "string" or not CORE_SET[name] then
				throw(fmt("GetCore: %s has not been registered by the CoreScripts", tostring(name)))
			end
			return pc.setCore[name]
		end,
	},
})
svc("SoundService", "Instance", {
	props = {
		DistanceFactor = P("number", 3.33),
		DopplerScale = P("number", 1),
		RolloffScale = P("number", 1),
		RespectFilteringEnabled = P("bool", true),
	},
	methods = {
		PlayLocalSound = function(d, sound)
			if not isInst(sound) or D[sound].class.name ~= "Sound" then
				badArg(1, "PlayLocalSound", "Sound", sound)
			end
			local sd = D[sound]
			d.W.soundLog[#d.W.soundLog + 1] = { sound = sound, id = I.get(sd, "SoundId"), name = sd.name, time = d.W.time, peer = I.peer(d.W), localSound = true }
		end,
	},
})
svc("Chat", "Instance", {
	props = { BubbleChatEnabled = P("bool", false), LoadDefaultChat = P("bool", true) },
	methods = {
		Chat = function() end,
		FilterStringForBroadcast = function(_, s) return s end,
	},
})
svc("TextChatService", "Instance", {
	props = { CreateDefaultTextChannels = P("bool", true), CreateDefaultCommands = P("bool", true) },
})
svc("Teams", "Instance", {
	methods = {
		GetTeams = function(d)
			local out = {}
			for _, c in ipairs(I.children(d, I.peer(d.W))) do
				if D[c].class.name == "Team" then
					out[#out + 1] = c
				end
			end
			return out
		end,
	},
})

svc("RunService", "Instance", {
	defaultName = "Run Service",
	methods = {
		IsServer = function(d) return S.ctx(d.W).kind ~= "client" end,
		IsClient = function(d) return S.ctx(d.W).kind == "client" end,
		IsStudio = function(d) return d.W.studio end,
		IsRunning = function() return true end,
		IsRunMode = function() return false end,
		IsEdit = function() return false end,
		BindToRenderStep = function(d, name, priority, fn)
			local pc = needClient(d.W, "BindToRenderStep")
			if type(name) ~= "string" then
				badArg(1, "BindToRenderStep", "string", name)
			end
			if type(priority) ~= "number" then
				badArg(2, "BindToRenderStep", "number", priority)
			end
			if type(fn) ~= "function" then
				badArg(3, "BindToRenderStep", "function", fn)
			end
			d.W.seq = d.W.seq + 1
			pc.renderBinds[#pc.renderBinds + 1] = { name = name, priority = priority, fn = fn, ctx = S.ctx(d.W), seq = d.W.seq }
		end,
		UnbindFromRenderStep = function(d, name)
			local pc = needClient(d.W, "UnbindFromRenderStep")
			if type(name) ~= "string" then
				badArg(1, "UnbindFromRenderStep", "string", name)
			end
			for i, b in ipairs(pc.renderBinds) do
				if b.name == name then
					tremove(pc.renderBinds, i)
					return
				end
			end
		end,
		Set3dRenderingEnabled = function(d)
			needClient(d.W, "Set3dRenderingEnabled")
		end,
		Pause = function() throw("RunService:Pause can only be called by a plugin") end,
		Run = function() throw("RunService:Run can only be called by a plugin") end,
		Stop = function() throw("RunService:Stop can only be called by a plugin") end,
	},
	events = { "Heartbeat", "Stepped", "RenderStepped", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	eventOpts = {
		RenderStepped = { check = function(ctx)
			if ctx.kind ~= "client" then
				throw("RenderStepped event can only be used from local scripts")
			end
		end },
		PreRender = { check = function(ctx)
			if ctx.kind ~= "client" then
				throw("PreRender event can only be used from local scripts")
			end
		end },
	},
})
svc("TweenService", "Instance", {
	methods = {
		Create = function(d, inst, info, goals)
			if inst == nil then
				throw("Argument 1 missing or nil")
			end
			if not isInst(inst) then
				throw("Unable to cast value to Object")
			end
			if info == nil then
				throw("Argument 2 missing or nil")
			end
			if typeOf(info) ~= "TweenInfo" then
				throw("Unable to cast value to TweenInfo")
			end
			if type(goals) ~= "table" then
				throw("Unable to cast to Dictionary")
			end
			return I.createTween(d.W, D[inst], info, goals)
		end,
		GetValue = function(_, alpha, style, dir)
			alpha = checkNum(alpha, 1, "GetValue")
			R.enumArg(style, "EasingStyle", 2, "GetValue")
			R.enumArg(dir, "EasingDirection", 3, "GetValue")
			return I.ease(alpha, style, dir)
		end,
	},
})
svc("Debris", "Instance", {
	props = { MaxItems = P("int", 1000) },
	methods = {
		AddItem = function(d, item, lifetime)
			if not isInst(item) then
				badArg(1, "AddItem", "Instance", item)
			end
			lifetime = optNum(lifetime, 2, "AddItem", 10)
			d.W.debris[#d.W.debris + 1] = { d = D[item], at = d.W.time + lifetime }
		end,
	},
})
Classes.Debris.methods.addItem = Classes.Debris.methods.AddItem

local function uisGetter(field)
	return RO("bool", function(d)
		local pc = I.pcOf(d.W)
		return pc ~= nil and pc[field] == true
	end)
end
local GAMEPAD_KEYS = {
	"ButtonX", "ButtonY", "ButtonA", "ButtonB", "ButtonR1", "ButtonL1", "ButtonR2", "ButtonL2", "ButtonR3", "ButtonL3",
	"ButtonStart", "ButtonSelect", "DPadLeft", "DPadRight", "DPadUp", "DPadDown", "Thumbstick1", "Thumbstick2",
}
svc("UserInputService", "Instance", {
	props = {
		KeyboardEnabled = uisGetter("keyboard"),
		TouchEnabled = uisGetter("touch"),
		GamepadEnabled = uisGetter("gamepad"),
		MouseEnabled = uisGetter("mouse"),
		AccelerometerEnabled = RO("bool", function() return false end),
		GyroscopeEnabled = RO("bool", function() return false end),
		VREnabled = RO("bool", function() return false end),
		OnScreenKeyboardVisible = RO("bool", function() return false end),
		MouseIconEnabled = P("bool", true),
		MouseBehavior = EP("MouseBehavior", "Default"),
		MouseDeltaSensitivity = P("number", 1),
		ModalEnabled = P("bool", false),
	},
	methods = {
		IsKeyDown = function(d, kc)
			R.enumArg(kc, "KeyCode", 1, "IsKeyDown")
			local pc = I.pcOf(d.W)
			return pc ~= nil and pc.keys[kc] ~= nil
		end,
		GetKeysPressed = function(d)
			local pc = I.pcOf(d.W)
			local out = {}
			if pc then
				for _, inp in pairs(pc.keys) do
					out[#out + 1] = inp
				end
				tsort(out, function(a, b) return D[a].pressSeq < D[b].pressSeq end)
			end
			return out
		end,
		IsGamepadButtonDown = function(d, gp, kc)
			R.enumArg(gp, "UserInputType", 1, "IsGamepadButtonDown")
			R.enumArg(kc, "KeyCode", 2, "IsGamepadButtonDown")
			local pc = I.pcOf(d.W)
			return pc ~= nil and gp == E("UserInputType", "Gamepad1") and pc.buttons[kc] ~= nil
		end,
		GetGamepadConnected = function(d, gp)
			R.enumArg(gp, "UserInputType", 1, "GetGamepadConnected")
			local pc = I.pcOf(d.W)
			return pc ~= nil and pc.gamepad == true and gp == E("UserInputType", "Gamepad1")
		end,
		GetConnectedGamepads = function(d)
			local pc = I.pcOf(d.W)
			if pc and pc.gamepad then
				return { E("UserInputType", "Gamepad1") }
			end
			return {}
		end,
		GetNavigationGamepads = function(d)
			local pc = I.pcOf(d.W)
			if pc and pc.gamepad then
				return { E("UserInputType", "Gamepad1") }
			end
			return {}
		end,
		GetGamepadState = function(d, gp)
			R.enumArg(gp, "UserInputType", 1, "GetGamepadState")
			local pc = I.pcOf(d.W)
			local out = {}
			if pc and pc.gamepad and gp == E("UserInputType", "Gamepad1") then
				for _, name in ipairs(GAMEPAD_KEYS) do
					out[#out + 1] = pc.buttons[E("KeyCode", name)] or I.gamepadStateObject(d.W, pc, name)
				end
			end
			return out
		end,
		GetSupportedGamepadKeyCodes = function(d, gp)
			R.enumArg(gp, "UserInputType", 1, "GetSupportedGamepadKeyCodes")
			local out = {}
			for _, name in ipairs(GAMEPAD_KEYS) do
				out[#out + 1] = E("KeyCode", name)
			end
			return out
		end,
		GamepadSupports = function(d, gp, kc)
			R.enumArg(kc, "KeyCode", 2, "GamepadSupports")
			for _, name in ipairs(GAMEPAD_KEYS) do
				if E("KeyCode", name) == kc then
					return true
				end
			end
			return false
		end,
		GetLastInputType = function(d)
			local pc = I.pcOf(d.W)
			return pc and pc.lastInputType or E("UserInputType", "None")
		end,
		GetMouseLocation = function(d)
			local pc = I.pcOf(d.W)
			if pc then
				local vp = D[pc.viewport]
				return V2(vp[1] / 2, vp[2] / 2)
			end
			return Vector2.zero
		end,
		GetMouseDelta = function() return Vector2.zero end,
		GetMouseButtonsPressed = function() return {} end,
		IsMouseButtonPressed = function() return false end,
		GetFocusedTextBox = function() return nil end,
		GetStringForKeyCode = function(_, kc)
			R.enumArg(kc, "KeyCode", 1, "GetStringForKeyCode")
			local n = D[kc].Name
			if #n == 1 then
				return n
			end
			return ""
		end,
		GetImageForKeyCode = function() return "" end,
	},
	events = {
		"InputBegan", "InputEnded", "InputChanged", "TouchStarted", "TouchEnded", "TouchMoved", "TouchTap", "TouchTapInWorld",
		"TouchLongPress", "TouchSwipe", "TouchPinch", "TouchPan", "TouchRotate", "GamepadConnected", "GamepadDisconnected",
		"LastInputTypeChanged", "WindowFocused", "WindowFocusReleased", "JumpRequest", "TextBoxFocused", "TextBoxFocusReleased",
		"DeviceAccelerationChanged", "DeviceGravityChanged", "DeviceRotationChanged",
	},
})
svc("ContextActionService", "Instance", {
	methods = {
		BindAction = function(d, name, fn, touchButton, ...)
			local pc = needClient(d.W, "BindAction")
			I.casBind(d.W, pc, name, fn, touchButton, 2000, pack(...))
		end,
		BindActionAtPriority = function(d, name, fn, touchButton, priority, ...)
			local pc = needClient(d.W, "BindActionAtPriority")
			I.casBind(d.W, pc, name, fn, touchButton, checkNum(priority, 4, "BindActionAtPriority"), pack(...))
		end,
		UnbindAction = function(d, name)
			local pc = I.pcOf(d.W)
			if not pc then
				return
			end
			for i = #pc.actions, 1, -1 do
				if pc.actions[i].name == name then
					tremove(pc.actions, i)
				end
			end
		end,
		UnbindAllActions = function(d)
			local pc = I.pcOf(d.W)
			if pc then
				pc.actions = {}
			end
		end,
		GetBoundActionInfo = function(d, name)
			local pc = I.pcOf(d.W)
			if pc then
				for _, a in ipairs(pc.actions) do
					if a.name == name then
						return { inputTypes = a.inputs, priorityLevel = a.priority, createTouchButton = a.touchButton, stackOrder = a.seq }
					end
				end
			end
			return {}
		end,
		GetAllBoundActionInfo = function(d)
			local out = {}
			local pc = I.pcOf(d.W)
			if pc then
				for _, a in ipairs(pc.actions) do
					out[a.name] = { inputTypes = a.inputs, priorityLevel = a.priority, createTouchButton = a.touchButton, stackOrder = a.seq }
				end
			end
			return out
		end,
		SetTitle = function() end,
		SetDescription = function() end,
		SetImage = function() end,
		SetPosition = function() end,
		GetButton = function() return nil end,
		GetCurrentLocalToolIcon = function() return "" end,
	},
	events = { "LocalToolEquipped", "LocalToolUnequipped" },
})
function I.casBind(W, pc, name, fn, touchButton, priority, inputs)
	if type(name) ~= "string" then
		badArg(1, "BindAction", "string", name)
	end
	if type(fn) ~= "function" then
		badArg(2, "BindAction", "function", fn)
	end
	if type(touchButton) ~= "boolean" then
		badArg(3, "BindAction", "boolean", touchButton)
	end
	local list = {}
	for i = 1, inputs.n do
		local v = inputs[i]
		if not isEnumItem(v) or not (D[v].typeName == "KeyCode" or D[v].typeName == "UserInputType" or D[v].typeName == "PlayerActions") then
			throw("BindAction: input types must be Enum.KeyCode, Enum.UserInputType or Enum.PlayerActions")
		end
		list[#list + 1] = v
	end
	for i = #pc.actions, 1, -1 do
		if pc.actions[i].name == name then
			tremove(pc.actions, i)
		end
	end
	W.seq = W.seq + 1
	pc.actions[#pc.actions + 1] = { name = name, fn = fn, touchButton = touchButton, priority = priority, inputs = list, ctx = S.ctx(W), seq = W.seq }
end

svc("HttpService", "Instance", {
	props = { HttpEnabled = P("bool", false) },
	methods = {
		JSONEncode = function(_, v)
			return R.jsonEncode(v, {})
		end,
		JSONDecode = function(_, s)
			return R.jsonDecode(s)
		end,
		GenerateGUID = function(d, wrap)
			local W = d.W
			W.guidCounter = W.guidCounter + 1
			local h = {}
			local x = W.guidCounter * 2654435761 % 4294967296
			for i = 1, 32 do
				x = (x * 1103515245 + 12345) % 2147483648
				h[i] = fmt("%X", floor(x / 65536) % 16)
			end
			local s = tconcat(h)
			s = s:sub(1, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16) .. "-" .. s:sub(17, 20) .. "-" .. s:sub(21, 32)
			if wrap == false then
				return s
			end
			return "{" .. s .. "}"
		end,
		UrlEncode = function(_, s)
			if type(s) ~= "string" then
				badArg(1, "UrlEncode", "string", s)
			end
			return (s:gsub("[^%w%-_%.~]", function(c) return fmt("%%%02X", c:byte()) end))
		end,
		GetAsync = function(d)
			if not I.get(d, "HttpEnabled") then
				throw("Http requests are not enabled. Enable via game settings")
			end
			throw("HttpService: network access is not available in tests")
		end,
		PostAsync = function(d)
			if not I.get(d, "HttpEnabled") then
				throw("Http requests are not enabled. Enable via game settings")
			end
			throw("HttpService: network access is not available in tests")
		end,
		RequestAsync = function(d)
			if not I.get(d, "HttpEnabled") then
				throw("Http requests are not enabled. Enable via game settings")
			end
			throw("HttpService: network access is not available in tests")
		end,
	},
})
svc("CollectionService", "Instance", {
	methods = {
		GetTagged = function(d, tag)
			if type(tag) ~= "string" then
				badArg(1, "GetTagged", "string", tag)
			end
			local peer = I.peer(d.W)
			local out = {}
			local r = d.W.tagged[tag]
			if r then
				for _, p in ipairs(r.list) do
					local x = D[p]
					if I.inDataModel(x) and I.visibleTo(x, peer) then
						out[#out + 1] = p
					end
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(d, tag)
			if type(tag) ~= "string" then
				badArg(1, "GetInstanceAddedSignal", "string", tag)
			end
			local W = d.W
			W.tagAdded[tag] = W.tagAdded[tag] or Sig.new(W, "InstanceAdded:" .. tag)
			return PX(W.tagAdded[tag])
		end,
		GetInstanceRemovedSignal = function(d, tag)
			if type(tag) ~= "string" then
				badArg(1, "GetInstanceRemovedSignal", "string", tag)
			end
			local W = d.W
			W.tagRemoved[tag] = W.tagRemoved[tag] or Sig.new(W, "InstanceRemoved:" .. tag)
			return PX(W.tagRemoved[tag])
		end,
		AddTag = function(_, inst, tag)
			if not isInst(inst) then
				badArg(1, "AddTag", "Instance", inst)
			end
			I.addTag(D[inst], tag)
		end,
		RemoveTag = function(_, inst, tag)
			if not isInst(inst) then
				badArg(1, "RemoveTag", "Instance", inst)
			end
			I.removeTag(D[inst], tag)
		end,
		HasTag = function(_, inst, tag)
			if not isInst(inst) then
				badArg(1, "HasTag", "Instance", inst)
			end
			local x = D[inst]
			return (x.tags and x.tags.set[tag]) or false
		end,
		GetTags = function(_, inst)
			if not isInst(inst) then
				badArg(1, "GetTags", "Instance", inst)
			end
			local out = {}
			local x = D[inst]
			if x.tags then
				for i, t in ipairs(x.tags.list) do
					out[i] = t
				end
			end
			return out
		end,
		GetAllTags = function(d)
			local out = {}
			for tag, r in pairs(d.W.tagged) do
				if #r.list > 0 then
					out[#out + 1] = tag
				end
			end
			tsort(out)
			return out
		end,
	},
	events = { "TagAdded", "TagRemoved" },
})
svc("PhysicsService", "Instance", {
	methods = {
		RegisterCollisionGroup = function(d, name)
			if type(name) ~= "string" then
				badArg(1, "RegisterCollisionGroup", "string", name)
			end
			if S.ctx(d.W).kind == "client" then
				throw("RegisterCollisionGroup can only be called on the server")
			end
			local g = d.W.collisionGroups
			if not g.set[name] then
				if #g.list >= 32 then
					throw("Could not create collision group, the maximum of 32 groups has been reached")
				end
				g.set[name] = {}
				g.list[#g.list + 1] = name
			end
		end,
		CollisionGroupSetCollidable = function(d, a, b, on)
			local g = d.W.collisionGroups
			if not g.set[a] or not g.set[b] then
				throw("Collision group does not exist.")
			end
			if type(on) ~= "boolean" then
				badArg(3, "CollisionGroupSetCollidable", "boolean", on)
			end
			g.set[a][b] = on
			g.set[b][a] = on
		end,
		CollisionGroupsAreCollidable = function(d, a, b)
			local g = d.W.collisionGroups
			if not g.set[a] or not g.set[b] then
				throw("Collision group does not exist.")
			end
			return g.set[a][b] ~= false
		end,
		IsCollisionGroupRegistered = function(d, name)
			return d.W.collisionGroups.set[name] ~= nil
		end,
		GetRegisteredCollisionGroups = function(d)
			local out = {}
			for i, n in ipairs(d.W.collisionGroups.list) do
				out[i] = { id = i - 1, mask = 0, name = n }
			end
			return out
		end,
		UnregisterCollisionGroup = function(d, name)
			local g = d.W.collisionGroups
			g.set[name] = nil
			for i, n in ipairs(g.list) do
				if n == name then
					tremove(g.list, i)
					break
				end
			end
		end,
		GetMaxCollisionGroups = function() return 32 end,
	},
})
Classes.PhysicsService.methods.CreateCollisionGroup = Classes.PhysicsService.methods.RegisterCollisionGroup
svc("GuiService", "Instance", {
	props = {
		SelectedObject = IP("GuiObject"),
		AutoSelectGuiEnabled = P("bool", true),
		GuiNavigationEnabled = P("bool", true),
		TouchControlsEnabled = P("bool", true),
		MenuIsOpen = RO("bool", function() return false end),
		PreferredTransparency = RO("number", function() return 1 end),
		ReducedMotionEnabled = RO("bool", function() return false end),
		TopbarInset = RO("Rect", function(d)
			local pc = I.pcOf(d.W)
			local w = pc and D[pc.viewport][1] or 1280
			return R.Rect.new(0, 0, w, GUI_INSET)
		end),
	},
	methods = {
		GetGuiInset = function() return V2(0, GUI_INSET), V2(0, 0) end,
		IsTenFootInterface = function() return false end,
		GetEmotesMenuOpen = function() return false end,
		SetEmotesMenuOpen = function() end,
		AddSelectionParent = function() end,
		RemoveSelectionGroup = function() end,
		CloseInspectMenu = function() end,
		GetInspectMenuEnabled = function() return false end,
		SetInspectMenuEnabled = function() end,
	},
	events = { "MenuOpened", "MenuClosed" },
})
svc("TextService", "Instance", {
	methods = {
		GetTextSize = function(_, text, size, font, frame)
			if type(text) ~= "string" then
				badArg(1, "GetTextSize", "string", text)
			end
			size = checkNum(size, 2, "GetTextSize")
			R.enumArg(font, "Font", 3, "GetTextSize")
			if not isV2(frame) then
				badArg(4, "GetTextSize", "Vector2", frame)
			end
			local fr = D[frame]
			local n = 0
			for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
				n = n + 1
			end
			return V2(math.min(n * size * 0.5, fr[1]), size)
		end,
	},
})
svc("MarketplaceService", "Instance", {
	methods = {
		PromptProductPurchase = function() end,
		PromptGamePassPurchase = function() end,
		PromptPurchase = function() end,
		UserOwnsGamePassAsync = function(d)
			asyncYield(d.W)
			return false
		end,
		PlayerOwnsAsset = function(d)
			asyncYield(d.W)
			return false
		end,
		GetProductInfo = function(d, id)
			asyncYield(d.W)
			return { Name = "Product " .. tostring(id), PriceInRobux = 0, Description = "" }
		end,
	},
	callbacks = {
		ProcessReceipt = {
			check = function(ctx)
				if ctx.kind == "client" then
					throw("ProcessReceipt can only be set on the server")
				end
			end,
		},
	},
	events = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished" },
})
svc("DataStoreService", "Instance", {
	methods = {
		GetDataStore = function(d, name, scope)
			local W = d.W
			if S.ctx(W).kind == "client" then
				throw("DataStore can't be accessed from client")
			end
			if type(name) ~= "string" then
				badArg(1, "GetDataStore", "string", name)
			end
			local key = name .. "/" .. tostring(scope or "global")
			local ds = W.datastores[key]
			if not ds then
				local p, dd = I.new(W, "DataStore")
				dd.name = name
				dd.store = {}
				ds = p
				W.datastores[key] = p
			end
			return ds
		end,
		GetRequestBudgetForRequestType = function() return 100 end,
	},
})
Classes.DataStoreService.methods.GetGlobalDataStore = function(d)
	return Classes.DataStoreService.methods.GetDataStore(d, "global")
end
svc("BadgeService", "Instance", {
	methods = {
		AwardBadge = function(d)
			asyncYield(d.W)
			return true
		end,
		UserHasBadgeAsync = function(d)
			asyncYield(d.W)
			return false
		end,
		GetBadgeInfoAsync = function(d)
			asyncYield(d.W)
			return { Name = "Badge", IsEnabled = true }
		end,
	},
})
svc("TeleportService", "Instance", {
	methods = {
		Teleport = function() throw("Teleport is not available in tests (and does not work in Studio)") end,
		TeleportAsync = function() throw("Teleport is not available in tests (and does not work in Studio)") end,
		TeleportToPlaceInstance = function() throw("Teleport is not available in tests (and does not work in Studio)") end,
	},
})
svc("VRService", "Instance", {
	props = { VREnabled = RO("bool", function() return false end) },
})
svc("LogService", "Instance", {
	methods = { GetLogHistory = function() return {} end },
	events = { "MessageOut" },
})
svc("HapticService", "Instance", {
	methods = {
		IsVibrationSupported = function() return false end,
		IsMotorSupported = function() return false end,
		SetMotor = function() end,
		GetMotor = function() return 0 end,
	},
})

-- ============================================================================
-- ไลบรารีมาตรฐานแบบ Luau (string/table/math/utf8/bit32) ใช้ร่วมกันทั้ง VM
-- ============================================================================
local LIB = {}
do
	-- string: เพิ่ม split และ format ที่เข้มงวดแบบ Luau (%d กับเลขไม่เต็มจะ error)
	local LuauString = {}
	for k, v in pairs(string) do
		LuauString[k] = v
	end
	LuauString.gfind, LuauString.dump = nil, nil -- ไม่มีใน Luau
	function LuauString.split(s, sep)
		if type(s) ~= "string" then
			badArg(1, "split", "string", s)
		end
		sep = sep or ","
		local out = {}
		if sep == "" then
			for i = 1, #s do
				out[i] = s:sub(i, i)
			end
			if #s == 0 then
				out[1] = ""
			end
			return out
		end
		local start = 1
		while true do
			local i, j = s:find(sep, start, true)
			if not i then
				out[#out + 1] = s:sub(start)
				break
			end
			out[#out + 1] = s:sub(start, i - 1)
			start = j + 1
		end
		return out
	end
	function LuauString.format(f, ...)
		if type(f) ~= "string" and type(f) ~= "number" then
			badArg(1, "format", "string", f)
		end
		f = tostring(f)
		local args = pack(...)
		local idx = 0
		local out = f:gsub("%%([%-+ #0]*%d*%.?%d*)([%a%%%*])", function(flags, conv)
			if conv == "%" then
				return "%%"
			end
			idx = idx + 1
			local v = args[idx]
			if conv == "*" then
				args[idx] = tostring(v)
				return "%" .. flags .. "s"
			end
			if idx > args.n then
				throw(fmt("invalid argument #%d to 'format' (no value)", idx + 1))
			end
			if conv == "d" or conv == "i" or conv == "x" or conv == "X" or conv == "o" or conv == "c" or conv == "u" then
				if type(v) == "string" and tonumber(v) then
					v = tonumber(v)
					args[idx] = v
				end
				if type(v) ~= "number" then
					throw(fmt("invalid argument #%d to 'format' (number expected, got %s)", idx + 1, typeOf(v)))
				end
				if v ~= floor(v) then
					throw(fmt("invalid argument #%d to 'format' (number has no integer representation)", idx + 1))
				end
			elseif conv == "s" then
				if type(v) ~= "string" and type(v) ~= "number" then
					args[idx] = tostring(v)
				end
			elseif conv == "f" or conv == "g" or conv == "e" or conv == "G" or conv == "E" or conv == "a" or conv == "A" then
				if type(v) == "string" and tonumber(v) then
					args[idx] = tonumber(v)
				elseif type(v) ~= "number" then
					throw(fmt("invalid argument #%d to 'format' (number expected, got %s)", idx + 1, typeOf(v)))
				end
			end
			return "%" .. flags .. conv
		end)
		return fmt(out, unpack(args, 1, args.n))
	end
	getmetatable("").__index = LuauString
	LIB.string = LuauString

	local T = {}
	for k, v in pairs(table) do
		T[k] = v
	end
	T.setn = nil -- ไม่มีใน Luau
	local frozen = setmetatable({}, { __mode = "k" })
	-- Luau ตรวจตำแหน่งของ insert/remove (Lua 5.1 ไม่ตรวจ) -> ทำให้เข้มงวดแบบ Luau เพื่อจับบั๊ก
	function T.insert(t, ...)
		if type(t) ~= "table" then
			badArg(1, "insert", "table", t)
		end
		local nargs = select("#", ...)
		if nargs == 1 then
			t[#t + 1] = (...)
			return
		elseif nargs == 2 then
			local pos, v = ...
			pos = checkNum(pos, 2, "insert")
			if pos ~= floor(pos) or pos < 1 or pos > #t + 1 then
				throw("invalid argument #2 to 'insert' (position out of bounds)")
			end
			tinsert(t, pos, v)
			return
		end
		throw("wrong number of arguments to 'insert'")
	end
	function T.remove(t, pos)
		if type(t) ~= "table" then
			badArg(1, "remove", "table", t)
		end
		local n = #t
		if pos == nil then
			return tremove(t)
		end
		pos = checkNum(pos, 2, "remove")
		if pos ~= n and (pos ~= floor(pos) or pos < 1 or pos > n + 1) then
			throw("invalid argument #2 to 'remove' (position out of bounds)")
		end
		if pos == n + 1 or n == 0 then
			local v = t[pos]
			t[pos] = nil
			return v
		end
		return tremove(t, pos)
	end
	function T.find(t, v, init)
		if type(t) ~= "table" then
			badArg(1, "find", "table", t)
		end
		for i = init or 1, #t do
			if t[i] == v then
				return i
			end
		end
		return nil
	end
	function T.clear(t)
		if type(t) ~= "table" then
			badArg(1, "clear", "table", t)
		end
		if frozen[t] then
			throw("attempt to modify a readonly table")
		end
		for k in pairs(t) do
			t[k] = nil
		end
	end
	function T.create(n, v)
		local t = {}
		for i = 1, checkNum(n, 1, "create") do
			t[i] = v
		end
		return t
	end
	function T.freeze(t)
		if type(t) ~= "table" then
			badArg(1, "freeze", "table", t)
		end
		frozen[t] = true
		return t
	end
	function T.isfrozen(t)
		if type(t) ~= "table" then
			badArg(1, "isfrozen", "table", t)
		end
		return frozen[t] == true
	end
	function T.clone(t)
		if type(t) ~= "table" then
			badArg(1, "clone", "table", t)
		end
		local c = {}
		for k, v in pairs(t) do
			c[k] = v
		end
		return setmetatable(c, getmetatable(t))
	end
	function T.move(a1, f, e, t, a2)
		a2 = a2 or a1
		if e >= f then
			if t > f or t > e or a1 ~= a2 then
				for i = 0, e - f do
					a2[t + i] = a1[f + i]
				end
			else
				for i = e - f, 0, -1 do
					a2[t + i] = a1[f + i]
				end
			end
		end
		return a2
	end
	function T.pack(...)
		return pack(...)
	end
	T.unpack = unpack
	LIB.table = T

	local Mth = {}
	for k, v in pairs(math) do
		Mth[k] = v
	end
	Mth.mod = nil -- Luau ไม่มี math.mod
	function Mth.clamp(x, mn, mx)
		x = checkNum(x, 1, "clamp")
		mn = checkNum(mn, 2, "clamp")
		mx = checkNum(mx, 3, "clamp")
		if mx < mn then
			throw("invalid argument #3 to 'clamp' (max must be greater than or equal to min)")
		end
		if x < mn then
			return mn
		elseif x > mx then
			return mx
		end
		return x
	end
	function Mth.sign(x)
		return R.sign(checkNum(x, 1, "sign"))
	end
	function Mth.round(x)
		x = checkNum(x, 1, "round")
		if x >= 0 then
			return floor(x + 0.5)
		end
		return math.ceil(x - 0.5)
	end
	function Mth.log(x, base)
		if base == nil then
			return math.log(x)
		end
		return math.log(x) / math.log(base)
	end
	local PERM = {
		151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
		247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
		74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
		65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
		52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
		119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
		218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
		184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
	}
	local function perm(i)
		return PERM[(i % 256) + 1]
	end
	local function fade(t)
		return t * t * t * (t * (t * 6 - 15) + 10)
	end
	local function grad(h, x, y, z)
		h = h % 16
		local u = h < 8 and x or y
		local v
		if h < 4 then
			v = y
		elseif h == 12 or h == 14 then
			v = x
		else
			v = z
		end
		if h % 2 == 1 then
			u = -u
		end
		if floor(h / 2) % 2 == 1 then
			v = -v
		end
		return u + v
	end
	local function lerp(t, a, b)
		return a + t * (b - a)
	end
	function Mth.noise(x, y, z)
		x = checkNum(x, 1, "noise")
		y = optNum(y, 2, "noise", 0)
		z = optNum(z, 3, "noise", 0)
		local X, Y, Z = floor(x), floor(y), floor(z)
		x, y, z = x - X, y - Y, z - Z
		local u, v, w = fade(x), fade(y), fade(z)
		local A = perm(X) + Y
		local AA, AB = perm(A) + Z, perm(A + 1) + Z
		local B = perm(X + 1) + Y
		local BA, BB = perm(B) + Z, perm(B + 1) + Z
		return lerp(w,
			lerp(v, lerp(u, grad(perm(AA), x, y, z), grad(perm(BA), x - 1, y, z)), lerp(u, grad(perm(AB), x, y - 1, z), grad(perm(BB), x - 1, y - 1, z))),
			lerp(v, lerp(u, grad(perm(AA + 1), x, y, z - 1), grad(perm(BA + 1), x - 1, y, z - 1)), lerp(u, grad(perm(AB + 1), x, y - 1, z - 1), grad(perm(BB + 1), x - 1, y - 1, z - 1))))
	end
	LIB.math = Mth

	local U8 = { charpattern = "[%z\1-\127\194-\244][\128-\191]*" }
	local function enc(cp)
		if cp < 0x80 then
			return string.char(cp)
		elseif cp < 0x800 then
			return string.char(0xC0 + floor(cp / 64), 0x80 + cp % 64)
		elseif cp < 0x10000 then
			return string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
		end
		return string.char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64, 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
	end
	function U8.char(...)
		local out = {}
		for i = 1, select("#", ...) do
			out[i] = enc(checkNum(select(i, ...), i, "char"))
		end
		return tconcat(out)
	end
	local function dec(s, i)
		local c = s:byte(i)
		if not c then
			return nil
		end
		if c < 0x80 then
			return c, 1
		elseif c >= 0xF0 then
			local b, cc, d = s:byte(i + 1, i + 3)
			return ((c - 0xF0) * 262144) + ((b - 0x80) * 4096) + ((cc - 0x80) * 64) + (d - 0x80), 4
		elseif c >= 0xE0 then
			local b, cc = s:byte(i + 1, i + 2)
			return ((c - 0xE0) * 4096) + ((b - 0x80) * 64) + (cc - 0x80), 3
		elseif c >= 0xC0 then
			local b = s:byte(i + 1)
			return ((c - 0xC0) * 64) + (b - 0x80), 2
		end
		return nil
	end
	function U8.codes(s)
		local i = 1
		return function()
			if i > #s then
				return nil
			end
			local cp, n = dec(s, i)
			if not cp then
				throw("invalid UTF-8 code")
			end
			local pos = i
			i = i + n
			return pos, cp
		end
	end
	function U8.codepoint(s, i, j)
		i = i or 1
		j = j or i
		local out = {}
		local p = i
		while p <= j do
			local cp, n = dec(s, p)
			if not cp then
				throw("invalid UTF-8 code")
			end
			out[#out + 1] = cp
			p = p + n
		end
		return unpack(out)
	end
	function U8.len(s, i, j)
		i = i or 1
		j = j or #s
		local n, p = 0, i
		while p <= j do
			local cp, k = dec(s, p)
			if not cp then
				return nil, p
			end
			n = n + 1
			p = p + k
		end
		return n
	end
	function U8.offset(s, n, i)
		i = i or 1
		local p = i
		for _ = 1, n - 1 do
			local _, k = dec(s, p)
			if not k then
				return nil
			end
			p = p + k
		end
		return p
	end
	LIB.utf8 = U8

	local B = {}
	local function u32(x)
		return floor(x) % 4294967296
	end
	local function bitop(a, b, f)
		a, b = u32(a), u32(b)
		local r, bit = 0, 1
		for _ = 1, 32 do
			local x, y = a % 2, b % 2
			if f(x, y) then
				r = r + bit
			end
			a, b, bit = floor(a / 2), floor(b / 2), bit * 2
		end
		return r
	end
	local function fold(f, init)
		return function(...)
			local r = init
			for i = 1, select("#", ...) do
				r = bitop(r, checkNum(select(i, ...), i, "bit32"), f)
			end
			return r
		end
	end
	B.band = fold(function(x, y) return x == 1 and y == 1 end, 4294967295)
	B.bor = fold(function(x, y) return x == 1 or y == 1 end, 0)
	B.bxor = fold(function(x, y) return x ~= y end, 0)
	function B.bnot(x)
		return 4294967295 - u32(x)
	end
	function B.btest(...)
		return B.band(...) ~= 0
	end
	function B.lshift(x, n)
		if n >= 32 then
			return 0
		end
		return u32(u32(x) * 2 ^ n)
	end
	function B.rshift(x, n)
		if n >= 32 then
			return 0
		end
		return floor(u32(x) / 2 ^ n)
	end
	function B.arshift(x, n)
		x = u32(x)
		local r = floor(x / 2 ^ n)
		if x >= 2147483648 then
			r = r + u32(4294967295 * 2 ^ (32 - math.min(n, 32)))
		end
		return u32(r)
	end
	function B.extract(x, f, w)
		w = w or 1
		return floor(u32(x) / 2 ^ f) % 2 ^ w
	end
	function B.replace(x, v, f, w)
		w = w or 1
		local mask = 2 ^ w - 1
		x = u32(x)
		local cleared = x - (floor(x / 2 ^ f) % 2 ^ w) * 2 ^ f
		return u32(cleared + (u32(v) % (mask + 1)) * 2 ^ f)
	end
	function B.lrotate(x, n)
		n = n % 32
		x = u32(x)
		return u32((x * 2 ^ n) % 4294967296 + floor(x / 2 ^ (32 - n)))
	end
	function B.rrotate(x, n)
		return B.lrotate(x, 32 - (n % 32))
	end
	function B.countlz(x)
		x = u32(x)
		local n = 0
		for i = 31, 0, -1 do
			if floor(x / 2 ^ i) % 2 == 1 then
				return n
			end
			n = n + 1
		end
		return 32
	end
	function B.countrz(x)
		x = u32(x)
		if x == 0 then
			return 32
		end
		local n = 0
		while x % 2 == 0 do
			x = x / 2
			n = n + 1
		end
		return n
	end
	LIB.bit32 = B
end

-- ============================================================================
-- World
-- ============================================================================
local World = {}
World.__index = World

local function clientFilter(pc)
	local peer = pc.peer
	return function(ctx)
		return ctx.kind == "client" and ctx.peer == peer
	end
end
local function serverFilter(ctx)
	return ctx.kind ~= "client"
end

function Stubs.newWorld(opts)
	opts = opts or {}
	local W = setmetatable({}, World)
	W.time, W.stepCount, W.seq, W.nextId, W.guidCounter = 0, 0, 0, 0, 0
	W.errors, W.warnings, W.output = {}, {}, {}
	W.ctxOf = setmetatable({}, { __mode = "k" })
	W.parentOf = setmetatable({}, { __mode = "k" })
	W.dead = setmetatable({}, { __mode = "k" })
	W.waits, W.deferred, W.childWaits, W.remoteQueue = {}, {}, {}, {}
	W.tweens, W.debris, W.playingSounds, W.soundLog, W.particlesEmitted = {}, {}, {}, {}, {}
	W.guiTweens = setmetatable({}, { __mode = "k" })
	W.tagged, W.tagAdded, W.tagRemoved, W.tagCount = {}, {}, {}, 0
	W.canQueryCheck, W.backlogWarned = {}, {}
	W.cqWarned = setmetatable({}, { __mode = "k" })
	W.warnedOnce = setmetatable({}, { __mode = "k" })
	W.clients, W.clientsByPlayer, W.playerList = {}, {}, {}
	W.scriptCtx, W.moduleCache, W.sharedG, W.sharedShared = {}, {}, {}, {}
	W.kicks, W.closeCallbacks, W.datastores = {}, {}, {}
	W.collisionGroups = { set = { Default = {} }, list = { "Default" } }
	W.studio = opts.studio == true
	W.maxPlayers = opts.maxPlayers or 8
	W.echo = opts.echo == true
	-- "Immediate" (ค่าเริ่มต้น) หรือ "Deferred" (เหมือน Workspace.SignalBehavior = Deferred ของ Roblox)
	W.deferredEvents = opts.signalBehavior == "Deferred"
	W.harness = { kind = "harness", peer = "harness", label = "harness", alive = true }
	W.serverCtx = { kind = "server", peer = "server", label = "server (runAs)", alive = true }
	R.warnHook = function(msg)
		W:warn(msg)
	end
	R.clock = function()
		return W.time
	end

	local game, gd = I.new(W, "DataModel")
	gd.isService, gd.parentLocked = true, true
	W.game = game
	W.services, W.serviceByClass = {}, {}
	local order = {
		"Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage",
		"StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Chat", "Teams", "TextChatService", "RunService",
		"TweenService", "Debris", "UserInputService", "ContextActionService", "HttpService", "CollectionService",
		"PhysicsService", "GuiService", "TextService", "MarketplaceService", "DataStoreService", "BadgeService",
		"TeleportService", "HapticService", "VRService", "LogService",
	}
	for _, cname in ipairs(order) do
		local p, d = I.new(W, cname)
		d.isService = true
		I.setParent(d, game)
		d.parentLocked = true
		W.services[cname] = p
		W.serviceByClass[cname] = p
	end
	W.workspace = W.services.Workspace
	local _, spsd = I.new(W, "StarterPlayerScripts")
	I.setParent(spsd, W.services.StarterPlayer)
	local _, scsd = I.new(W, "StarterCharacterScripts")
	I.setParent(scsd, W.services.StarterPlayer)
	local terrain, td = I.new(W, "Terrain")
	td.props.Anchored = true
	I.setParent(td, W.workspace)
	td.parentLocked, td.isService = true, true
	W.terrain = terrain
	local cam, camd = I.new(W, "Camera", "server")
	I.setParent(camd, W.workspace)
	W.serverCamera = cam
	W.base = W:_buildBase()
	return W
end

function World:warn(msg)
	self.warnings[#self.warnings + 1] = msg
	self.output[#self.output + 1] = "WARNING: " .. msg
	if self.echo then
		io.write("[warn] ", msg, "\n")
	end
end

function World:_print(isWarn, ...)
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	local msg = tconcat(parts, " ")
	if isWarn then
		self:warn(msg)
	else
		self.output[#self.output + 1] = msg
		if self.echo then
			io.write(msg, "\n")
		end
	end
end

-- สร้างตาราง global ที่ทุกสคริปต์ใน world นี้เห็น (แต่ละสคริปต์มี env ของตัวเองที่ __index มาที่นี่)
function World:_buildBase()
	local W = self
	local base = {}
	for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "rawequal", "rawget", "rawset", "select", "tonumber", "tostring", "unpack", "getmetatable", "setmetatable", "newproxy", "gcinfo", "getfenv", "setfenv" }) do
		base[k] = _G[k]
	end
	base.type = function(v)
		local t = type(v)
		if t == "userdata" and getmt(v) == R.V3MT then
			return "vector" -- Vector3 ใน Luau เป็นชนิด native "vector"
		end
		return t
	end
	base.typeof = typeOf
	base.rawlen = function(t)
		if type(t) ~= "table" and type(t) ~= "string" then
			badArg(1, "rawlen", "table or string", t)
		end
		return #t
	end
	base.pcall = function(f, ...)
		return S.ypcall(W, nil, f, ...)
	end
	base.ypcall = base.pcall
	base.xpcall = function(f, handler, ...)
		return S.ypcall(W, handler, f, ...)
	end
	base.print = function(...)
		W:_print(false, ...)
	end
	base.warn = function(...)
		W:_print(true, ...)
	end
	base.require = function(m)
		return W:_require(m)
	end
	base.loadstring = function()
		throw("loadstring() is not available")
	end
	base.collectgarbage = function(opt)
		if opt == "count" then
			return collectgarbage("count")
		end
		throw("collectgarbage must be called with 'count'; use gcinfo() instead")
	end
	base.tick = function()
		return R.EPOCH + W.time
	end
	base.time = function()
		return W.time
	end
	base.elapsedTime = base.time
	base.version = function()
		return "0.650.0.6500000"
	end
	base.printidentity = function(s)
		W:_print(false, (s or "Current identity is") .. " 2")
	end
	local task = {}
	function task.wait(t)
		return S.waitFor(W, optNum(t, 1, "wait", 0))
	end
	function task.spawn(f, ...)
		if type(f) == "thread" then
			S.resume(W, f, ...)
			return f
		end
		if type(f) ~= "function" then
			badArg(1, "spawn", "function or thread", f)
		end
		return S.spawn(W, f, S.ctx(W), ...)
	end
	function task.defer(f, ...)
		if type(f) == "thread" then
			S.defer(W, f, nil, pack(...))
			return f
		end
		if type(f) ~= "function" then
			badArg(1, "defer", "function or thread", f)
		end
		local co = S.thread(W, f, S.ctx(W))
		S.defer(W, co, nil, pack(...))
		return co
	end
	function task.delay(t, f, ...)
		t = optNum(t, 1, "delay", 0)
		local target = f
		if type(f) == "function" then
			target = S.thread(W, f, S.ctx(W))
		elseif type(f) ~= "thread" then
			badArg(2, "delay", "function or thread", f)
		end
		S.schedule(W, W.time + t, target, nil, pack(...))
		return target
	end
	function task.cancel(th)
		if type(th) ~= "thread" then
			badArg(1, "cancel", "thread", th)
		end
		W.dead[th] = true
	end
	function task.synchronize() end
	function task.desynchronize() end
	base.task = readonlyTable(task, "task")
	base.wait = function(t)
		t = optNum(t, 1, "wait", 0)
		if t < 0.03 then
			t = 0.03
		end
		local el = S.waitFor(W, t)
		return el, W.time
	end
	base.delay = function(t, f)
		t = optNum(t, 1, "delay", 0)
		if type(f) ~= "function" then
			badArg(2, "delay", "function", f)
		end
		S.schedule(W, W.time + math.max(t, 0.03), S.thread(W, f, S.ctx(W)), nil, pack(t, W.time))
	end
	base.spawn = function(f)
		if type(f) ~= "function" then
			badArg(1, "spawn", "function", f)
		end
		S.schedule(W, W.time + 0.03, S.thread(W, f, S.ctx(W)), nil, pack(0.03, W.time))
	end

	local co = {}
	function co.create(f)
		if type(f) ~= "function" then
			badArg(1, "create", "function", f)
		end
		local th = cocreate(S.luaFn(f))
		W.ctxOf[th] = S.ctx(W)
		return th
	end
	function co.resume(th, ...)
		if W.dead[th] then
			return false, "cannot resume dead coroutine"
		end
		return coresume(th, ...)
	end
	co.yield = coyield
	function co.status(th)
		if W.dead[th] then
			return "dead"
		end
		local cur = corunning()
		if cur and S.root(W, cur) == th then
			return "running"
		end
		return costatus(th)
	end
	function co.running()
		local cur = corunning()
		if not cur then
			return nil
		end
		return S.root(W, cur)
	end
	function co.wrap(f)
		local th = co.create(f)
		return function(...)
			local r = pack(co.resume(th, ...))
			if not r[1] then
				error(r[2], 2)
			end
			return unpack(r, 2, r.n)
		end
	end
	function co.isyieldable()
		return corunning() ~= nil
	end
	function co.close(th)
		W.dead[th] = true
		return true
	end
	base.coroutine = readonlyTable(co, "coroutine")

	base.math = readonlyTable(LIB.math, "math")
	base.string = readonlyTable(LIB.string, "string")
	base.table = readonlyTable(LIB.table, "table")
	base.utf8 = readonlyTable(LIB.utf8, "utf8")
	base.bit32 = readonlyTable(LIB.bit32, "bit32")
	base.os = readonlyTable({
		time = function(t)
			if t ~= nil then
				return os.time(t)
			end
			return floor(R.EPOCH + W.time)
		end,
		clock = function()
			return W.time
		end,
		date = function(f, t)
			return os.date(f, t or floor(R.EPOCH + W.time))
		end,
		difftime = os.difftime,
	}, "os")
	base.debug = readonlyTable({
		traceback = function(a, b, c)
			if type(a) == "thread" then
				return debug.traceback(a, b, c)
			end
			if W.xpcallThread then
				return debug.traceback(W.xpcallThread, a)
			end
			return debug.traceback(a, (b or 1) + 1)
		end,
		info = function(a, b)
			local lvl = a
			if type(a) == "number" then
				lvl = a + 1
			end
			local info = debug.getinfo(lvl, "Slnf")
			if not info then
				return nil
			end
			local out = {}
			for ch in tostring(b or ""):gmatch(".") do
				if ch == "s" then
					out[#out + 1] = info.short_src
				elseif ch == "l" then
					out[#out + 1] = info.currentline
				elseif ch == "n" then
					out[#out + 1] = info.name
				elseif ch == "f" then
					out[#out + 1] = info.func
				elseif ch == "a" then
					out[#out + 1] = 0
					out[#out + 1] = false
				end
			end
			return unpack(out)
		end,
		profilebegin = function() end,
		profileend = function() end,
		setmemorycategory = function() end,
		resetmemorycategory = function() end,
	}, "debug")

	base.game, base.Game = W.game, W.game
	base.workspace, base.Workspace = W.workspace, W.workspace
	base.Instance = readonlyTable({
		new = function(cname, parent)
			if type(cname) ~= "string" then
				badArg(1, "new", "string", cname)
			end
			local cls = Classes[cname]
			if not cls or cls.abstract or cls.notCreatable then
				throw(fmt('Unable to create an Instance of type "%s"', cname))
			end
			if parent ~= nil and not isInst(parent) then
				badArg(2, "new", "Instance", parent)
			end
			local ctx = S.ctx(W)
			local p, d = I.new(W, cname, ctx.kind == "client" and ctx.peer or nil)
			if parent then
				I.setParent(d, parent)
			end
			return p
		end,
	}, "Instance")
	for _, k in ipairs({ "Vector3", "Vector2", "CFrame", "Color3", "BrickColor", "UDim", "UDim2", "Rect", "NumberRange",
		"NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "TweenInfo", "PhysicalProperties",
		"Ray", "RaycastParams", "OverlapParams", "Random", "Font", "DateTime" }) do
		base[k] = readonlyTable(R[k], k)
	end
	base.Enum = R.EnumRoot
	return base
end

function World:_makeEnv(ctx, scriptProxy)
	local g = peerGroup(ctx)
	self.sharedG[g] = self.sharedG[g] or {}
	self.sharedShared[g] = self.sharedShared[g] or {}
	local env = setmetatable({}, { __index = self.base })
	env.script = scriptProxy
	env._G = self.sharedG[g]
	env.shared = self.sharedShared[g]
	return env
end

function World:_pc(player, fname)
	local pc = player and self.clientsByPlayer[player]
	if not pc then
		error((fname or "world") .. ": expected a Player that is in the game (from addPlayer)", 3)
	end
	return pc
end

function World:_newCtx(kind, player, scriptProxy, label)
	local ctx = { kind = kind, alive = true, script = scriptProxy, label = label }
	if kind == "client" then
		local pc = self:_pc(player, "runScript")
		ctx.peer, ctx.player = pc.peer, player
		pc.ctxs = pc.ctxs or {}
		pc.ctxs[#pc.ctxs + 1] = ctx
	else
		ctx.peer = "server"
	end
	return ctx
end

local function readFile(path)
	local f, err = io.open(path, "rb")
	if not f then
		error("cannot open " .. tostring(path) .. ": " .. tostring(err), 3)
	end
	local src = f:read("*a")
	f:close()
	return src
end

-- รันสคริปต์: opts = { class = "Script"|"LocalScript", parent = Instance, name = string, player = Player }
-- คืน ok, err, scriptInstance (syntax error / runtime error ช่วงแรกถูกบันทึกใน world.errors ด้วย)
function World:runScript(path, opts)
	return self:runSource(readFile(path), opts, path)
end

function World:runSource(src, opts, path)
	opts = opts or {}
	local W = self
	local class = opts.class or "Script"
	if class ~= "Script" and class ~= "LocalScript" then
		error("runScript: class must be 'Script' or 'LocalScript'", 2)
	end
	local name = opts.name or (path and path:match("([^/\\]+)%.lua$")) or class
	local parent, owner, player = opts.parent, nil, opts.player
	if class == "LocalScript" then
		local pc = W:_pc(player, "runScript(LocalScript)")
		owner = pc.peer
		parent = parent or I.findChild(D[player], "PlayerScripts", "harness")
	else
		parent = parent or W.services.ServerScriptService
	end
	local sp, sd = I.new(W, class, owner)
	sd.name, sd.source, sd.sourcePath = name, src, path
	if parent then
		I.setParent(sd, parent)
	end
	local label = I.fullName(sd) .. (class == "LocalScript" and (" [client " .. D[player].name .. "]") or " [server]")
	local ctx = W:_newCtx(class == "LocalScript" and "client" or "server", player, sp, label)
	W.scriptCtx[sp] = { ctx }
	local fn, err = loadstring(src, "=" .. I.fullName(sd))
	if not fn then
		local msg = "SyntaxError: " .. tostring(err)
		W.errors[#W.errors + 1] = label .. ": " .. msg
		return false, msg, sp
	end
	setfenv(fn, W:_makeEnv(ctx, sp))
	local co = cocreate(fn)
	W.ctxOf[co] = ctx
	local nerr = #W.errors
	S.resume(W, co)
	W:_settle()
	if #W.errors > nerr and costatus(co) == "dead" then
		return false, W.errors[nerr + 1], sp
	end
	return true, nil, sp
end

function World:addModule(parent, name, path)
	return self:addModuleSource(parent, name, readFile(path), path)
end

function World:addModuleSource(parent, name, src, path)
	local mp, md = I.new(self, "ModuleScript")
	md.name, md.source, md.sourcePath = name, src, path
	if parent then
		I.setParent(md, parent)
	end
	return mp
end

function World:_require(m)
	local W = self
	if not isInst(m) or D[m].class.name ~= "ModuleScript" then
		if type(m) == "number" then
			throw("require(assetId) is not supported in tests")
		end
		throw("Attempted to call require with invalid argument(s).")
	end
	local md = D[m]
	local ctx = S.ctx(W)
	local g = peerGroup(ctx)
	W.moduleCache[g] = W.moduleCache[g] or {}
	local cache = W.moduleCache[g]
	local cur = corunning()
	local root = cur and S.root(W, cur)
	local e = cache[m]
	if e then
		if not e.done then
			if root == nil or root == e.root then
				throw("Requested module was required recursively")
			end
			e.waiters[#e.waiters + 1] = root
			coyield()
		end
		if e.failed then
			throw("Requested module experienced an error while loading")
		end
		return e.value
	end
	e = { done = false, waiters = {}, root = root }
	cache[m] = e
	local function finish(failed, value)
		e.done, e.failed, e.value = true, failed, value
		for _, w in ipairs(e.waiters) do
			S.defer(W, w, nil, pack())
		end
	end
	if not md.source then
		finish(true)
		throw("Requested module has no source")
	end
	local fn, err = loadstring(md.source, "=" .. I.fullName(md))
	if not fn then
		W.errors[#W.errors + 1] = ctx.label .. ": SyntaxError in module " .. I.fullName(md) .. ": " .. tostring(err)
		finish(true)
		throw("Requested module experienced an error while loading")
	end
	setfenv(fn, W:_makeEnv(ctx, m))
	local res = pack(S.ypcall(W, function(e2)
		if W.xpcallThread then
			return debug.traceback(W.xpcallThread, tostring(e2))
		end
		return debug.traceback(tostring(e2), 2)
	end, fn))
	if not res[1] then
		W.errors[#W.errors + 1] = ctx.label .. ": error while loading module " .. I.fullName(md) .. ": " .. tostring(res[2])
		finish(true)
		throw("Requested module experienced an error while loading")
	end
	if res.n ~= 2 then
		finish(true)
		throw("Module code did not return exactly one value")
	end
	finish(false, res[2])
	return res[2]
end

-- ---------------------------------------------------------------- players
function World:addPlayer(name, userId, opts)
	opts = opts or {}
	local W = self
	userId = userId or (#W.playerList + 1)
	local peer = "client:" .. tostring(userId)
	if W.clients[peer] then
		error("addPlayer: a player with UserId " .. tostring(userId) .. " is already in the game", 2)
	end
	local p, pd = I.new(W, "Player")
	pd.name = name or ("Player" .. tostring(userId))
	pd.userId = userId
	local touch = opts.touch == true
	local keyboard = opts.keyboard
	if keyboard == nil then
		keyboard = not touch
	end
	local mouse = opts.mouse
	if mouse == nil then
		mouse = keyboard
	end
	local pc = {
		player = p, peer = peer, touch = touch, keyboard = keyboard, gamepad = opts.gamepad == true, mouse = mouse,
		keys = {}, buttons = {}, sticks = {}, touches = {}, padState = {}, coreGui = {}, setCore = {}, renderBinds = {}, actions = {}, ctxs = {},
		viewport = V2(opts.viewportX or 1280, opts.viewportY or 720),
	}
	if touch then
		pc.lastInputType = E("UserInputType", "Touch")
	elseif keyboard then
		pc.lastInputType = E("UserInputType", "Keyboard")
	elseif pc.gamepad then
		pc.lastInputType = E("UserInputType", "Gamepad1")
	else
		pc.lastInputType = E("UserInputType", "None")
	end
	W.clients[peer], W.clientsByPlayer[p] = pc, pc
	for _, cname in ipairs({ "Backpack", "StarterGear", "PlayerGui", "PlayerScripts" }) do
		local _, cd = I.new(W, cname, cname == "PlayerScripts" and peer or nil)
		I.setParent(cd, p)
	end
	local cam, camd = I.new(W, "Camera", peer)
	camd.viewport = pc.viewport
	I.setParent(camd, W.workspace)
	pc.camera = cam
	W.playerList[#W.playerList + 1] = p
	I.setParent(pd, W.services.Players)
	-- PlayerAdded ยิงทันที (synchronous) ใน ctx ของสคริปต์ที่ Connect ไว้
	Sig.fire(I.sig(D[W.services.Players], "PlayerAdded"), nil, p)
	if I.get(D[W.services.Players], "CharacterAutoLoads") then
		-- Roblox โหลดตัวละครให้เองถ้า CharacterAutoLoads = true (เช็กอีกครั้งตอนถึงเวลา)
		S.schedule(W, W.time, function()
			if pd.parent and I.get(D[W.services.Players], "CharacterAutoLoads") and not pd.props.Character then
				I.loadCharacter(pd)
			end
		end, W.harness)
	end
	W:_settle()
	return p
end

function World:removePlayer(p)
	local W = self
	local pc = W.clientsByPlayer[p]
	if not pc then
		return
	end
	local pd = D[p]
	Sig.fire(I.sig(D[W.services.Players], "PlayerRemoving"), nil, p)
	for _, ctx in ipairs(pc.ctxs) do
		ctx.alive = false
	end
	pc.renderBinds, pc.actions = {}, {}
	local ch = pd.props.Character
	if ch and not D[ch].destroyed then
		I.destroy(D[ch])
	end
	if not D[pc.camera].destroyed then
		I.destroy(D[pc.camera])
	end
	for i, x in ipairs(W.playerList) do
		if x == p then
			tremove(W.playerList, i)
			break
		end
	end
	W.clients[pc.peer], W.clientsByPlayer[p] = nil, nil
	I.setParent(pd, nil)
	W:_settle()
end

function World:setViewportSize(player, x, y)
	local pc = self:_pc(player, "setViewportSize")
	pc.viewport = V2(x, y)
	local camd = D[pc.camera]
	camd.viewport = pc.viewport
	I.changed(camd, "ViewportSize")
	self:_settle()
end

function World:camera(player)
	if player == nil then
		return self.serverCamera
	end
	return self:_pc(player, "camera").camera
end

-- ---------------------------------------------------------------- input simulation
local function newInput(W, pc, kc, uit, state, pos)
	local p, d = I.new(W, "InputObject", pc.peer)
	d.props.KeyCode, d.props.UserInputType, d.props.UserInputState = kc, uit, state
	d.props.Position = pos or Vector3.zero
	W.seq = W.seq + 1
	d.pressSeq = W.seq
	return p, d
end

function I.gamepadStateObject(W, pc, name)
	local kc = E("KeyCode", name)
	if pc.sticks[kc] then
		return pc.sticks[kc]
	end
	local o = pc.padState[name]
	if not o then
		o = newInput(W, pc, kc, E("UserInputType", "Gamepad1"), E("UserInputState", "End"))
		pc.padState[name] = o
	end
	return o
end

local function keyArg(key, fname)
	if isEnumItem(key) and D[key].typeName == "KeyCode" then
		return key
	end
	local kc = type(key) == "string" and EnumTypes.KeyCode.items[key]
	if not kc then
		error(fname .. ": unknown KeyCode " .. tostring(key), 3)
	end
	return kc
end

function World:_fireUIS(pc, ev, ...)
	Sig.fire(I.sig(D[self.services.UserInputService], ev), clientFilter(pc), ...)
end

function World:_setLastInput(pc, uit)
	if pc.lastInputType ~= uit then
		pc.lastInputType = uit
		self:_fireUIS(pc, "LastInputTypeChanged", uit)
	end
end

-- ContextActionService: เรียก action ที่ผูกกับปุ่มนี้ (priority สูงก่อน, ผูกทีหลังก่อน) คืน true ถ้าถูก Sink
function World:_cas(pc, input, state)
	local d = D[input]
	local kc, uit = d.props.KeyCode, d.props.UserInputType
	local list = {}
	for _, a in ipairs(pc.actions) do
		for _, inp in ipairs(a.inputs) do
			if inp == kc or inp == uit then
				list[#list + 1] = a
				break
			end
		end
	end
	tsort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.seq > b.seq
	end)
	for _, a in ipairs(list) do
		local result
		local th = S.thread(self, function(...)
			result = a.fn(...)
		end, a.ctx)
		S.resume(self, th, a.name, state, input)
		if result ~= E("ContextActionResult", "Pass") then
			return true
		end
	end
	return false
end

function World:keyDown(player, key, gameProcessed)
	local pc = self:_pc(player, "keyDown")
	local kc = keyArg(key, "keyDown")
	if pc.keys[kc] then
		return pc.keys[kc]
	end
	local input = newInput(self, pc, kc, E("UserInputType", "Keyboard"), E("UserInputState", "Begin"))
	pc.keys[kc] = input
	self:_setLastInput(pc, E("UserInputType", "Keyboard"))
	self:_cas(pc, input, E("UserInputState", "Begin"))
	self:_fireUIS(pc, "InputBegan", input, gameProcessed == true)
	self:_settle()
	return input
end

function World:keyUp(player, key, gameProcessed)
	local pc = self:_pc(player, "keyUp")
	local kc = keyArg(key, "keyUp")
	local input = pc.keys[kc]
	if not input then
		return nil
	end
	pc.keys[kc] = nil
	local d = D[input]
	d.props.UserInputState = E("UserInputState", "End")
	self:_cas(pc, input, E("UserInputState", "End"))
	self:_fireUIS(pc, "InputEnded", input, gameProcessed == true)
	self:_settle()
	return input
end

function World:_gamepadOn(pc)
	if not pc.gamepad then
		pc.gamepad = true
		self:_fireUIS(pc, "GamepadConnected", E("UserInputType", "Gamepad1"))
	end
end

function World:gamepadButton(player, key, down, gameProcessed)
	local pc = self:_pc(player, "gamepadButton")
	local kc = keyArg(key, "gamepadButton")
	self:_gamepadOn(pc)
	self:_setLastInput(pc, E("UserInputType", "Gamepad1"))
	if down then
		if pc.buttons[kc] then
			return pc.buttons[kc]
		end
		local input = newInput(self, pc, kc, E("UserInputType", "Gamepad1"), E("UserInputState", "Begin"))
		pc.buttons[kc] = input
		self:_cas(pc, input, E("UserInputState", "Begin"))
		self:_fireUIS(pc, "InputBegan", input, gameProcessed == true)
		self:_settle()
		return input
	end
	local input = pc.buttons[kc]
	if not input then
		return nil
	end
	pc.buttons[kc] = nil
	D[input].props.UserInputState = E("UserInputState", "End")
	self:_cas(pc, input, E("UserInputState", "End"))
	self:_fireUIS(pc, "InputEnded", input, gameProcessed == true)
	self:_settle()
	return input
end

-- คันโยก: x ขวา = +, y ขึ้น = + (แบบ Roblox) ยิง InputChanged เท่านั้น
function World:thumbstick(player, x, y, which, gameProcessed)
	local pc = self:_pc(player, "thumbstick")
	local kc = E("KeyCode", which == 2 and "Thumbstick2" or "Thumbstick1")
	self:_gamepadOn(pc)
	self:_setLastInput(pc, E("UserInputType", "Gamepad1"))
	local input = pc.sticks[kc]
	if not input then
		input = newInput(self, pc, kc, E("UserInputType", "Gamepad1"), E("UserInputState", "Change"))
		pc.sticks[kc] = input
	end
	local d = D[input]
	local old = D[d.props.Position]
	d.props.Delta = V3(x - old[1], y - old[2], 0)
	d.props.Position = V3(x, y, 0)
	d.props.UserInputState = E("UserInputState", "Change")
	self:_cas(pc, input, E("UserInputState", "Change"))
	self:_fireUIS(pc, "InputChanged", input, gameProcessed == true)
	self:_settle()
	return input
end

-- แตะจอที่ GuiObject (ตำแหน่งกลางปุ่ม หรือ x,y ในพิกัด GUI แบบ AbsolutePosition)
function World:touchBegin(player, gui, x, y, gameProcessed)
	local pc = self:_pc(player, "touchBegin")
	local gd = gui and D[gui]
	local px, py = x, y
	if gd then
		local ax, ay, w, h = I.absRect(gd)
		px = px or (ax + w / 2)
		py = py or (ay + h / 2)
		local ok, why = I.guiOnScreen(gd, player)
		if not ok then
			self:warn("touchBegin: " .. I.fullName(gd) .. " cannot be touched (" .. tostring(why) .. ")")
			gd = nil
		end
	end
	local input, d = newInput(self, pc, E("KeyCode", "Unknown"), E("UserInputType", "Touch"), E("UserInputState", "Begin"), V3(px or 0, py or 0, 0))
	d.touchGui = gd
	pc.touches[input] = true
	self:_setLastInput(pc, E("UserInputType", "Touch"))
	local f = clientFilter(pc)
	if gd then
		Sig.fire(I.sig(gd, "InputBegan"), f, input)
		if gd.class.isGuiButton then
			Sig.fire(I.sig(gd, "MouseButton1Down"), f, px, py)
		end
	end
	self:_cas(pc, input, E("UserInputState", "Begin"))
	self:_fireUIS(pc, "TouchStarted", input, gameProcessed == true)
	self:_fireUIS(pc, "InputBegan", input, gameProcessed == true)
	self:_settle()
	return input
end

function World:touchMove(player, input, x, y, gameProcessed)
	local pc = self:_pc(player, "touchMove")
	local d = D[input]
	local old = D[d.props.Position]
	d.props.Delta = V3(x - old[1], y - old[2], 0)
	d.props.Position = V3(x, y, 0)
	d.props.UserInputState = E("UserInputState", "Change")
	local f = clientFilter(pc)
	if d.touchGui then
		Sig.fire(I.sig(d.touchGui, "InputChanged"), f, input)
	end
	self:_fireUIS(pc, "TouchMoved", input, gameProcessed == true)
	self:_fireUIS(pc, "InputChanged", input, gameProcessed == true)
	self:_settle()
	return input
end

function World:touchEnd(player, input, gameProcessed)
	local pc = self:_pc(player, "touchEnd")
	local d = D[input]
	if not pc.touches[input] then
		return input
	end
	pc.touches[input] = nil
	d.props.UserInputState = E("UserInputState", "End")
	local f = clientFilter(pc)
	local gd = d.touchGui
	if gd then
		Sig.fire(I.sig(gd, "InputEnded"), f, input)
		if gd.class.isGuiButton then
			local pos = D[d.props.Position]
			Sig.fire(I.sig(gd, "MouseButton1Up"), f, pos[1], pos[2])
			Sig.fire(I.sig(gd, "MouseButton1Click"), f)
			Sig.fire(I.sig(gd, "Activated"), f, input, 1)
		end
	end
	self:_cas(pc, input, E("UserInputState", "End"))
	self:_fireUIS(pc, "TouchEnded", input, gameProcessed == true)
	self:_fireUIS(pc, "InputEnded", input, gameProcessed == true)
	self:_settle()
	return input
end

-- ---------------------------------------------------------------- step
function World:_deliver(e)
	local W = self
	if e.kind == "server" then
		if not W.clientsByPlayer[e.player] then
			return true -- ผู้ส่งออกจากเกมไปแล้ว
		end
		local s = I.sig(e.remote, "OnServerEvent")
		if not Sig.hasListeners(s, serverFilter) then
			return false
		end
		Sig.fire(s, serverFilter, e.player, unpack(e.args, 1, e.args.n))
		return true
	elseif e.kind == "client" then
		local pc = W.clientsByPlayer[e.player]
		if not pc then
			return true
		end
		local f = clientFilter(pc)
		local s = I.sig(e.remote, "OnClientEvent")
		if not Sig.hasListeners(s, f) then
			return false
		end
		Sig.fire(s, f, unpack(e.args, 1, e.args.n))
		return true
	elseif e.kind == "invokeServer" or e.kind == "invokeClient" then
		local pc = W.clientsByPlayer[e.player]
		if not pc then
			W.remoteQueue[#W.remoteQueue + 1] = { kind = "return", co = e.co, ok = false, args = pack("player left the game") }
			return true
		end
		local toServer = e.kind == "invokeServer"
		local cb = I.callbackFor(e.remote, toServer and "OnServerInvoke" or "OnClientInvoke", toServer and "server" or pc.peer)
		if not cb then
			return false
		end
		local backPeer = toServer and pc.peer or "server"
		local function run(...)
			local res = pack(S.ypcall(W, nil, cb.fn, ...))
			local ret
			if res[1] then
				local ok, copied = pcall(I.copyArgs, pack(unpack(res, 2, res.n)), "RemoteFunction", backPeer)
				if ok then
					ret = { kind = "return", co = e.co, ok = true, args = copied }
				else
					ret = { kind = "return", co = e.co, ok = false, args = pack(tostring(copied)) }
				end
			else
				ret = { kind = "return", co = e.co, ok = false, args = pack(tostring(res[2])) }
			end
			W.remoteQueue[#W.remoteQueue + 1] = ret
		end
		if toServer then
			S.spawn(W, run, cb.ctx, e.player, unpack(e.args, 1, e.args.n))
		else
			S.spawn(W, run, cb.ctx, unpack(e.args, 1, e.args.n))
		end
		return true
	elseif e.kind == "return" then
		S.resume(W, e.co, e.ok, unpack(e.args, 1, e.args.n))
		return true
	end
	return true
end

function World:_deliverRemotes()
	local W = self
	local q = W.remoteQueue
	if #q == 0 then
		return
	end
	W.remoteQueue = {}
	local keep, count = {}, {}
	for _, e in ipairs(q) do
		if not W:_deliver(e) then
			local key = tostring(e.remote.id) .. "|" .. e.kind .. "|" .. tostring(e.player and D[e.player].userId)
			count[key] = (count[key] or 0) + 1
			if count[key] <= 256 then
				keep[#keep + 1] = e
			elseif not W.backlogWarned[key] then
				W.backlogWarned[key] = true
				W:warn("Remote event invocation queue exhausted for " .. I.fullName(e.remote) .. "; did you forget to implement "
					.. (e.kind == "server" and "OnServerEvent" or e.kind == "client" and "OnClientEvent" or "the invoke callback") .. "?")
			end
		end
	end
	for _, e in ipairs(W.remoteQueue) do
		keep[#keep + 1] = e
	end
	W.remoteQueue = keep
end

function World:_checkCanQuery()
	local list = {}
	for d in pairs(self.canQueryCheck) do
		list[#list + 1] = d
	end
	self.canQueryCheck = {}
	tsort(list, function(a, b) return a.id < b.id end)
	for _, d in ipairs(list) do
		if not d.destroyed and I.get(d, "CanQuery") == false and I.get(d, "CanCollide") == true and not self.cqWarned[d] then
			self.cqWarned[d] = true
			self:warn(I.fullName(d) .. ": CanQuery = false is ignored by Roblox while CanCollide = true (set CanCollide = false too)")
		end
	end
end

-- เรียกทุกครั้งหลังงานจากฝั่งเทส: เคลียร์ task.defer และเช็กคำเตือน CanQuery
function World:_settle()
	S.flush(self)
	self:_checkCanQuery()
end

function World:step(dt)
	local W = self
	dt = dt or 1 / 60
	W.stepCount = W.stepCount + 1
	W.time = W.time + dt
	local rs = D[W.services.RunService]

	W:_deliverRemotes()
	S.flush(W)

	for _, p in ipairs(W.playerList) do
		local pc = W.clientsByPlayer[p]
		if pc then
			local binds = {}
			for i, b in ipairs(pc.renderBinds) do
				binds[i] = b
			end
			tsort(binds, function(a, b)
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.seq < b.seq
			end)
			for _, b in ipairs(binds) do
				if b.ctx.alive then
					S.spawn(W, b.fn, b.ctx, dt)
				end
			end
			local f = clientFilter(pc)
			Sig.fire(I.sig(rs, "PreRender"), f, dt)
			Sig.fire(I.sig(rs, "RenderStepped"), f, dt)
		end
	end
	S.flush(W)

	Sig.fire(I.sig(rs, "PreAnimation"), nil, dt)
	Sig.fire(I.sig(rs, "Stepped"), nil, W.time, dt)
	Sig.fire(I.sig(rs, "PreSimulation"), nil, dt)
	S.flush(W)

	local tl = {}
	for d in pairs(W.tweens) do
		tl[#tl + 1] = d
	end
	tsort(tl, function(a, b) return a.id < b.id end)
	for _, d in ipairs(tl) do
		if W.tweens[d] then
			I.tweenStep(d, dt)
		end
	end
	S.flush(W)

	Sig.fire(I.sig(rs, "PostSimulation"), nil, dt)
	Sig.fire(I.sig(rs, "Heartbeat"), nil, dt)
	S.flush(W)

	S.resumeDue(W)
	S.flush(W)

	if #W.debris > 0 then
		local keep = {}
		for _, e in ipairs(W.debris) do
			if W.time + 1e-9 >= e.at then
				if not e.d.destroyed then
					local ok, err = pcall(I.destroy, e.d)
					if not ok then
						W:warn("Debris could not destroy " .. I.fullName(e.d) .. ": " .. tostring(err))
					end
				end
			else
				keep[#keep + 1] = e
			end
		end
		W.debris = keep
	end

	local ended = {}
	for d, at in pairs(W.playingSounds) do
		if W.time + 1e-9 >= at then
			ended[#ended + 1] = d
		end
	end
	tsort(ended, function(a, b) return a.id < b.id end)
	for _, d in ipairs(ended) do
		W.playingSounds[d] = nil
		I.rawSet(d, "Playing", false)
		Sig.fire(I.sig(d, "Ended"), nil, I.get(d, "SoundId"))
	end

	if #W.childWaits > 0 then
		local keep = {}
		for _, w in ipairs(W.childWaits) do
			local ctx = W.ctxOf[w.co]
			if ctx and not ctx.alive then
				-- สคริปต์ตายแล้ว ทิ้ง
			elseif w.timeout and W.time - w.start + 1e-9 >= w.timeout then
				S.defer(W, w.co, nil, pack(nil))
			else
				if not w.timeout and not w.warned and W.time - w.start >= 5 then
					w.warned = true
					W:warn(fmt("Infinite yield possible on '%s:WaitForChild(\"%s\")'", I.fullName(w.parent), w.name))
				end
				keep[#keep + 1] = w
			end
		end
		W.childWaits = keep
	end
	W:_settle()
end

function World:advance(seconds, dt)
	dt = dt or 1 / 60
	local n = floor(seconds / dt + 0.5)
	for _ = 1, n do
		self:step(dt)
	end
end

-- ---------------------------------------------------------------- helpers สำหรับเทส
-- รันฟังก์ชันใน ctx ของ client (player) หรือ server (player = nil) คืนค่าที่ฟังก์ชันคืน (ถ้าจบในรอบเดียว)
function World:runAs(player, fn, ...)
	local ctx
	if player then
		ctx = self:_newCtx("client", player, nil, "runAs [client " .. D[player].name .. "]")
	else
		ctx = self.serverCtx
	end
	local res
	local th = S.thread(self, function(...)
		res = pack(fn(...))
	end, ctx)
	S.resume(self, th, ...)
	self:_settle()
	if res then
		return unpack(res, 1, res.n)
	end
end

-- รันโค้ด Lua สั้นๆ ด้วย global แบบ Roblox; คืน ok, ...ค่า (ไม่บันทึก error ลง world.errors)
function World:eval(code, player)
	local fn, err = loadstring(code, "=eval")
	if not fn then
		return false, tostring(err)
	end
	local ctx
	if player then
		ctx = self:_newCtx("client", player, nil, "eval [client " .. D[player].name .. "]")
	else
		ctx = self.serverCtx
	end
	setfenv(fn, self:_makeEnv(ctx, nil))
	local res
	local th = S.thread(self, function()
		res = pack(fn())
	end, ctx)
	local ok, e = coresume(th)
	self:_settle()
	if not ok then
		return false, tostring(e)
	end
	if res then
		return true, unpack(res, 1, res.n)
	end
	return true
end

-- หา instance จาก path เช่น "Workspace.BattleCity.Dynamic" หรือ "Players.Alice.PlayerGui" (มองเห็นทุกอย่าง)
function World:find(path)
	local cur = D[self.game]
	local first = true
	for seg in tostring(path):gmatch("[^%.]+") do
		if first and (seg == "game" or seg == "Game") then
			-- อยู่ที่ราก
		else
			local c = I.findChild(cur, seg, "harness")
			if not c and first then
				c = self.serviceByClass[seg]
			end
			if not c then
				return nil
			end
			cur = D[c]
		end
		first = false
	end
	return PX(cur)
end

function World:children(inst)
	return I.children(D[inst], "harness")
end

function World:descendants(inst)
	return I.descendants(D[inst], "harness")
end

function World:attributes(inst)
	local out = {}
	local d = D[inst]
	if d.attrs then
		for k, v in pairs(d.attrs) do
			out[k] = v
		end
	end
	return out
end

function World:fullName(inst)
	return I.fullName(D[inst])
end

function World:absRect(gui)
	return I.absRect(D[gui])
end

function World:isOnScreen(gui, player)
	return I.guiOnScreen(D[gui], player)
end

-- แตกค่าชนิด Roblox ให้ python อ่านง่าย: คืน typeof และตาราง components
function Stubs.describe(v)
	local t = typeOf(v)
	local d = D[v]
	if t == "Vector3" or t == "Vector2" or t == "Color3" or t == "CFrame" or t == "UDim" or t == "UDim2" or t == "Rect" or t == "NumberRange" then
		local c = {}
		for i, x in ipairs(d) do
			c[i] = x
		end
		return t, c
	elseif t == "EnumItem" then
		return t, { tostring(v), d.Name, d.Value }
	elseif t == "BrickColor" then
		return t, { d.entry[2], d.entry[1] }
	elseif t == "Instance" then
		return t, { I.fullName(d), d.class.name }
	end
	return t, { v }
end

Stubs.typeof = typeOf
Stubs.Enum = R.EnumRoot
Stubs.Classes = Classes
Stubs.version = "1"

return Stubs
