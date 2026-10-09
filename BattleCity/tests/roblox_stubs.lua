-- roblox_stubs.lua : จำลอง Roblox API สำหรับเทสเท่านั้น (ไม่ต้องเอาไปใส่ใน Studio)
-- รัน Script (server) + LocalScript (client) ใน lupa.lua51 VM เดียว เพื่อจับ error, index nil,
-- ชื่อ API ผิด, ชนิดค่าผิด ก่อนผู้ใช้เอาโค้ดไปวางใน Roblox Studio จริง
--
-- วิธีใช้ (ฝั่ง python ดู roblox_env.py ซึ่งห่อทั้งหมดนี้ไว้แล้ว):
--   local Stubs = <โหลดไฟล์นี้>
--   local world = Stubs.newWorld({ studio = false })
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
			error(msg, 2)
		end
		if info.source ~= STUBS_SRC and info.what ~= "C" then
			error(msg, lvl - 1)
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
local function cfMul(A, B)
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = unpack(A, 1, 12)
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = unpack(B, 1, 12)
	return CF(
		a00 * bx + a01 * by + a02 * bz + ax,
		a10 * bx + a11 * by + a12 * bz + ay,
		a20 * bx + a21 * by + a22 * bz + az,
		a00 * b00 + a01 * b10 + a02 * b20, a00 * b01 + a01 * b11 + a02 * b21, a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20, a10 * b01 + a11 * b11 + a12 * b21, a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20, a20 * b01 + a21 * b11 + a22 * b21, a20 * b02 + a21 * b12 + a22 * b22
	)
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
			S.resume(W, e.co, W.time - e.start)
		end
	end
end

-- pcall/xpcall ที่ yield ได้ (Luau yield ข้าม pcall ได้ แต่ Lua 5.1 ทำไม่ได้) -> รันใน coroutine ลูก
function S.ypcall(W, handler, f, ...)
	local parent = corunning()
	if not parent then
		if handler then
			return xpcall(function() return f() end, handler)
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
	s.proxy = mkSig(s)
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
	c.proxy = mkConn(c)
	s.conns[#s.conns + 1] = c
	if s.onConnect then
		s.onConnect(c)
	end
	return c.proxy
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
					S.spawn(W, c.fn, ctx, ...)
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
				S.resume(W, w.co, ...)
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
	d.proxy = p
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
			return I.event(d, k, m).proxy
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
		if cur == ancestorD.proxy then
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
		I.removeChild(od, d.proxy)
		d.parent = nil
		local s = I.sig(od, "ChildRemoved")
		if s then
			Sig.fire(s, vf, d.proxy)
		end
	end
	d.parent = np
	if nd then
		nd.children[#nd.children + 1] = d.proxy
		local s = I.sig(nd, "ChildAdded")
		if s then
			Sig.fire(s, vf, d.proxy)
		end
		I.fireDescendantAdded(nd, d, vf)
		if #W.childWaits > 0 then
			I.checkChildWaits(W, nd, d)
		end
	end
	I.fireAncestry(d, d.proxy, np, vf)
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
	local subtree = { d.proxy }
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
	local subtree = { d.proxy }
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
			S.defer(W, w.co, nil, pack(cd.proxy))
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
	map[d.proxy] = p2
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
	r.set[d.proxy] = true
	r.list[#r.list + 1] = d.proxy
	W.tagCount = W.tagCount + 1
	d.tagInDM = d.tagInDM or {}
	if I.inDataModel(d) then
		d.tagInDM[tag] = true
		local s = W.tagAdded[tag]
		if s then
			Sig.fire(s, I.visFilter(d), d.proxy)
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
	r.set[d.proxy] = nil
	for i, x in ipairs(r.list) do
		if x == d.proxy then
			tremove(r.list, i)
			break
		end
	end
	if d.tagInDM and d.tagInDM[tag] then
		d.tagInDM[tag] = nil
		local s = W.tagRemoved[tag]
		if s then
			Sig.fire(s, I.visFilter(d), d.proxy)
		end
	end
end

-- ยิง GetInstanceAdded/RemovedSignal เมื่อ instance ที่มี tag เข้า/ออกจาก DataModel
function I.updateTagMembership(d)
	local W = d.W
	local list = { d.proxy }
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
function I.partCF(d)
	return d.props.CFrame or CFrame_identity
end

-- @@PART3B@@
