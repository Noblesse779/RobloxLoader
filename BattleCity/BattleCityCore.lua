--[[
BattleCityCore (ModuleScript ใน ServerScriptService)
ตัวจำลองเกม TANK CITY (กติกาแบบ Battle City บน NES) เขียนเป็น Lua ล้วน
- ไม่แตะ Roblox API เลย จึงเทสต์นอก Roblox ได้ (Lua 5.1 / Luau ใช้ได้ทั้งคู่)
- หน่วยเป็นพิกเซล NES: สนาม 208x208, กริดย่อย 4px = 52x52 ช่อง, รถถัง 16x16
- Server เรียก game:step(1/60) ทุกเฟรม แล้วอ่าน state / popEvents() ไปวาดเอง
- ทุกอย่างที่มีผลต่อเกมวนด้วย array + ipairs และสุ่มผ่าน RNG ของเกมเท่านั้น
  (seed เดียวกัน + input เดียวกัน = ผลลัพธ์เหมือนกันทุกครั้ง)
]]

local Core = {}

local floor, ceil, abs = math.floor, math.ceil, math.abs
local tremove = table.remove

local FIELD = 208
local GRID_N = 52
local MICRO = 4
local TANK = 16
local MAX_POS = FIELD - TANK -- 192: ขอบขวา/ล่างสุดที่มุมซ้ายบนของรถถังไปได้
local EPS = 1e-6 -- กันเศษทศนิยมสะสม (0.8 px ต่อ tick ไม่ลงตัวในเลขฐานสอง)
local RNG_M = 2147483647

local CELL = { EMPTY = 0, BRICK = 1, STEEL = 2, WATER = 3, TREES = 4, ICE = 5, BASE = 6 }
local EMPTY, BRICK, STEEL, WATER, TREES, ICE, BASE = 0, 1, 2, 3, 4, 5, 6
local DIR = { UP = 0, RIGHT = 1, DOWN = 2, LEFT = 3 }
local UP, RIGHT, DOWN, LEFT = 0, 1, 2, 3
local DX = { [0] = 0, 1, 0, -1 }
local DY = { [0] = -1, 0, 1, 0 }

-- ชนิดช่องที่ขวางรถถัง / ขวางกระสุน (กระสุนบินข้ามน้ำ ลอดใต้ป่า ผ่านน้ำแข็ง)
local BLOCKS_TANK = { [BRICK] = true, [STEEL] = true, [WATER] = true, [BASE] = true }
local BLOCKS_BULLET = { [BRICK] = true, [STEEL] = true, [BASE] = true }
local CHAR_KIND = { ["."] = EMPTY, B = BRICK, S = STEEL, W = WATER, T = TREES, I = ICE, E = BASE }
local ENEMY_CHAR = { b = "basic", f = "fast", p = "power", a = "armor" }
local KIND_INDEX = { basic = 1, fast = 2, power = 3, armor = 4 }
local KIND_ORDER = { "basic", "fast", "power", "armor" }
local POWERUP_KINDS = { "star", "grenade", "helmet", "shovel", "timer", "tank" }
local BASE_CX, BASE_CY = 104, 200 -- จุดกึ่งกลางนกอินทรี (AI ใช้เล็งเข้าหา)

local POS = {
	BASE = { x = 96, y = 192 },
	-- ลำดับนี้คือลำดับวนจุดเกิดศัตรู: กลาง, ขวา, ซ้าย (เหมือน NES)
	ENEMY_SPAWNS = { { x = 96, y = 0 }, { x = 192, y = 0 }, { x = 0, y = 0 } },
	PLAYER_SPAWNS = { [1] = { x = 64, y = 192 }, [2] = { x = 128, y = 192 } },
	-- กำแพงอิฐรอบฐาน เป็นช่องขนาด 8px {cx, cy}
	RING_CELLS = {
		{ 11, 23 }, { 12, 23 }, { 13, 23 }, { 14, 23 },
		{ 11, 24 }, { 11, 25 }, { 14, 24 }, { 14, 25 },
	},
}

local DEFAULT_CONFIG = {
	TICK = 1 / 60,
	PLAYER_SPEED = 48,
	ENEMY_SPEED = { basic = 32, fast = 80, power = 48, armor = 48 },
	BULLET_SPEED = { slow = 120, normal = 180, fast = 240 },
	ENEMY_BULLET = { basic = "slow", fast = "normal", power = "fast", armor = "normal" },
	ENEMY_HP = { basic = 1, fast = 1, power = 1, armor = 4 },
	ENEMY_POINTS = { basic = 100, fast = 200, power = 300, armor = 400 },
	POWERUP_POINTS = 500,
	START_LIVES = 2,
	BONUS_LIFE_SCORE = 20000,
	ENEMIES_PER_STAGE = 20,
	MAX_ENEMIES = { 4, 6 },
	BONUS_ENEMIES = { 4, 11, 18 },
	SPAWN_ANIM_TIME = 1.0,
	ENEMY_SPAWN_BASE = 190,
	RESPAWN_DELAY = 0.5,
	SHIELD_SPAWN = 3,
	SHIELD_HELMET = 10,
	FREEZE_TIME = 10,
	SHOVEL_TIME = 20,
	SHOVEL_FLASH_TIME = 3,
	SHOVEL_FLASH_PERIOD = 0.25,
	PLAYER_FREEZE_TIME = 3,
	ICE_SLIDE_PX = 24,
	FIRE_COOLDOWN = 0.12,
	AI_TURN_CHANCE = 0.125,
	AI_FIRE_RATE = 1.2,
	AI_BLOCKED_FIRE_CHANCE = 0.5,
	INTRO_TIME = 2.5,
	STAGE_CLEAR_DELAY = 3,
	GAMEOVER_TIME = 4,
	TALLY_TIME = 6,
	FINAL_TIME = 3,
}

Core.CELL = CELL
Core.DIR = DIR
Core.POS = POS
Core.FIELD = FIELD
Core.GRID_N = GRID_N
Core.MICRO = MICRO
Core.DEFAULT_CONFIG = DEFAULT_CONFIG

-- รายชื่อช่องย่อย (i, j) ที่ "บังคับ" ตอนโหลดด่าน เก็บแบบแบน {i1, j1, i2, j2, ...} จะได้ไม่สร้างตารางย่อยเยอะ
local RING_MICRO = {}
for _, c in ipairs(POS.RING_CELLS) do
	for dj = 0, 1 do
		for di = 0, 1 do
			RING_MICRO[#RING_MICRO + 1] = c[1] * 2 + di
			RING_MICRO[#RING_MICRO + 1] = c[2] * 2 + dj
		end
	end
end

local function boxMicro(list, x, y)
	-- ช่องย่อยทั้ง 16 ช่องใต้กล่อง 16x16 ที่มุม (x, y)
	for dj = 0, 3 do
		for di = 0, 3 do
			list[#list + 1] = floor(x / MICRO) + di
			list[#list + 1] = floor(y / MICRO) + dj
		end
	end
end

local BASE_MICRO = {}
boxMicro(BASE_MICRO, POS.BASE.x, POS.BASE.y)
local SPAWN_MICRO = {}
for _, p in ipairs(POS.ENEMY_SPAWNS) do
	boxMicro(SPAWN_MICRO, p.x, p.y)
end
for slot = 1, 2 do
	boxMicro(SPAWN_MICRO, POS.PLAYER_SPAWNS[slot].x, POS.PLAYER_SPAWNS[slot].y)
end

---------------------------------------------------------------------------
-- เครื่องมือเล็ก ๆ
---------------------------------------------------------------------------

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x)
	end
	return t
end

-- รวม config: ตารางแบบมี key (ENEMY_SPEED ฯลฯ) รวมทีละ key, ตารางแบบ array (MAX_ENEMIES) แทนทั้งก้อน
local function mergeConfig(over)
	local cfg = deepCopy(DEFAULT_CONFIG)
	if type(over) ~= "table" then
		return cfg
	end
	for k, v in pairs(over) do
		local cur = cfg[k]
		if type(v) == "table" and type(cur) == "table" and cur[1] == nil then
			for k2, v2 in pairs(v) do
				cur[k2] = deepCopy(v2)
			end
		else
			cfg[k] = deepCopy(v)
		end
	end
	return cfg
end

-- ช่องย่อยแรก/สุดท้ายที่ช่วง [a, b) ทับอยู่ (เผื่อ EPS กันเศษทศนิยมแตะช่องข้าง ๆ)
local function firstIdx(a)
	return floor((a + EPS) / MICRO)
end
local function lastIdx(b)
	return ceil((b - EPS) / MICRO) - 1
end

-- กล่องสี่เหลี่ยมจัตุรัสสองกล่องทับกันไหม (ขอบชนกันพอดีไม่นับว่าทับ)
local function overlap(ax, ay, as, bx, by, bs)
	return ax < bx + bs - EPS and bx < ax + as - EPS and ay < by + bs - EPS and by < ay + as - EPS
end

-- RNG แบบ Park–Miller: ใช้เลขจำนวนเต็มล้วน ผลตรงกันทุกเครื่อง/ทุกเวอร์ชัน Lua
local function rand(g)
	g._rng = (16807 * g._rng) % RNG_M
	return g._rng / RNG_M
end

local function randInt(g, n)
	local k = floor(rand(g) * n) + 1
	if k > n then
		k = n
	end
	return k
end

local function nextId(g)
	g._nextId = g._nextId + 1
	return g._nextId
end

local function emit(g, ev)
	local q = g._events
	q[#q + 1] = ev
end

-- เปลี่ยนช่องย่อยหลังโหลดด่าน: ส่งอีเวนต์ "cell" เฉพาะช่องที่ชนิดเปลี่ยนจริง
local function setCell(g, i, j, kind)
	local idx = j * GRID_N + i + 1
	if g.grid[idx] ~= kind then
		g.grid[idx] = kind
		emit(g, { type = "cell", i = i, j = j, kind = kind })
	end
end

local function setRing(g, kind)
	for k = 1, #RING_MICRO, 2 do
		setCell(g, RING_MICRO[k], RING_MICRO[k + 1], kind)
	end
end

local function clearArray(t)
	for k = #t, 1, -1 do
		t[k] = nil
	end
end

local function countPlayers(g)
	local n = 0
	for slot = 1, 2 do
		if g.players[slot] then
			n = n + 1
		end
	end
	return n
end

local function updateMaxEnemies(g)
	local list = g.config.MAX_ENEMIES
	local n = countPlayers(g)
	if n < 1 then
		n = 1
	end
	if n > #list then
		n = #list
	end
	g.maxEnemiesOnField = list[n] or 4
end

local function spawnInterval(g)
	local cfg = g.config
	local players = countPlayers(g)
	if players < 1 then
		players = 1
	end
	local stage = g.stageNumber
	if stage > 35 then
		stage = 35
	end
	local v = (cfg.ENEMY_SPAWN_BASE - 4 * stage - 20 * (players - 1)) / 60
	if v < 1.0 then
		v = 1.0
	end
	return v
end

local function enemyCounts(g)
	local tanks, anims = 0, 0
	for _, t in ipairs(g.tanks) do
		if t.team == "enemy" then
			tanks = tanks + 1
		end
	end
	for _, s in ipairs(g.spawns) do
		if s.team == "enemy" then
			anims = anims + 1
		end
	end
	return tanks, anims
end

local function removeTankAt(g, k)
	local t = tremove(g.tanks, k)
	if t then
		g._tankById[t.id] = nil
	end
	return t
end

local function removeTankById(g, id)
	local tanks = g.tanks
	for k = 1, #tanks do
		if tanks[k].id == id then
			return removeTankAt(g, k)
		end
	end
	return nil
end

local function addScore(g, p, points)
	p.score = p.score + points
	if not p.bonusLifeGiven and p.score >= g.config.BONUS_LIFE_SCORE then
		p.bonusLifeGiven = true
		p.lives = p.lives + 1
		emit(g, { type = "extraLife", slot = p.slot })
	end
end

---------------------------------------------------------------------------
-- การเคลื่อนที่ของรถถัง
---------------------------------------------------------------------------

local function cellsBlockTank(grid, i0, i1, j0, j1)
	for j = j0, j1 do
		local row = j * GRID_N + 1
		for i = i0, i1 do
			if BLOCKS_TANK[grid[row + i]] then
				return true
			end
		end
	end
	return false
end

-- รถถังคันอื่นที่ "เพิ่งจะ" ทับ: ถ้าเดิมทับกันอยู่แล้วให้แยกออกจากกันได้
local function blockedByTank(g, tank, nx, ny)
	local ox, oy = tank.x, tank.y
	local tanks = g.tanks
	for k = 1, #tanks do
		local o = tanks[k]
		if o ~= tank and overlap(nx, ny, TANK, o.x, o.y, TANK) and not overlap(ox, oy, TANK, o.x, o.y, TANK) then
			return true
		end
	end
	return false
end

-- เดินไปตาม dir ระยะ dist; เช็คเฉพาะช่องที่เพิ่งเข้าใหม่ ถ้าติดก็ไปได้ถึงขอบช่อง 4px ก่อนสิ่งกีดขวาง
local function moveTank(g, tank, dist)
	if not (dist > 0) then
		return false
	end
	local dir = tank.dir
	local ox, oy = tank.x, tank.y
	local nx, ny = ox, oy
	local grid = g.grid
	if dir == RIGHT then
		nx = ox + dist
		if nx > MAX_POS then
			nx = MAX_POS
		end
		local j0, j1 = firstIdx(oy), lastIdx(oy + TANK)
		for i = lastIdx(ox + TANK) + 1, lastIdx(nx + TANK) do
			if cellsBlockTank(grid, i, i, j0, j1) then
				nx = i * MICRO - TANK
				break
			end
		end
		if nx < ox then
			nx = ox
		end
	elseif dir == LEFT then
		nx = ox - dist
		if nx < 0 then
			nx = 0
		end
		local j0, j1 = firstIdx(oy), lastIdx(oy + TANK)
		for i = firstIdx(ox) - 1, firstIdx(nx), -1 do
			if cellsBlockTank(grid, i, i, j0, j1) then
				nx = (i + 1) * MICRO
				break
			end
		end
		if nx > ox then
			nx = ox
		end
	elseif dir == DOWN then
		ny = oy + dist
		if ny > MAX_POS then
			ny = MAX_POS
		end
		local i0, i1 = firstIdx(ox), lastIdx(ox + TANK)
		for j = lastIdx(oy + TANK) + 1, lastIdx(ny + TANK) do
			if cellsBlockTank(grid, i0, i1, j, j) then
				ny = j * MICRO - TANK
				break
			end
		end
		if ny < oy then
			ny = oy
		end
	else
		ny = oy - dist
		if ny < 0 then
			ny = 0
		end
		local i0, i1 = firstIdx(ox), lastIdx(ox + TANK)
		for j = firstIdx(oy) - 1, firstIdx(ny), -1 do
			if cellsBlockTank(grid, i0, i1, j, j) then
				ny = (j + 1) * MICRO
				break
			end
		end
		if ny > oy then
			ny = oy
		end
	end
	if nx == ox and ny == oy then
		return false
	end
	if blockedByTank(g, tank, nx, ny) then
		return false
	end
	tank.x, tank.y = nx, ny
	return true
end

-- ตำแหน่งหลังจัดแนว (snap) ใช้ได้ไหม: อยู่ในสนาม, ช่องที่เพิ่งเข้าไม่ขวาง, ไม่ทับรถถังคันใหม่
local function canSnap(g, tank, nx, ny)
	if nx < 0 or nx > MAX_POS or ny < 0 or ny > MAX_POS then
		return false
	end
	local ox, oy = tank.x, tank.y
	local oi0, oi1, oj0, oj1 = firstIdx(ox), lastIdx(ox + TANK), firstIdx(oy), lastIdx(oy + TANK)
	local grid = g.grid
	for j = firstIdx(ny), lastIdx(ny + TANK) do
		for i = firstIdx(nx), lastIdx(nx + TANK) do
			local inOld = i >= oi0 and i <= oi1 and j >= oj0 and j <= oj1
			if not inOld and BLOCKS_TANK[grid[j * GRID_N + i + 1]] then
				return false
			end
		end
	end
	return not blockedByTank(g, tank, nx, ny)
end

-- เลี้ยวตั้งฉาก = จัดแกนเดิมให้ลงช่อง 8px ใกล้สุด (ช่วยให้มุดช่องแคบได้แบบ NES), กลับหลังหันไม่จัด
local function turnTank(g, tank, newDir)
	local old = tank.dir
	if newDir == old then
		return
	end
	if (old + 2) % 4 ~= newDir then
		if old == UP or old == DOWN then
			local y = tank.y
			local n1 = floor(y / 8 + 0.5) * 8
			if n1 ~= y then
				local n2 = n1 + 8
				if n1 > y then
					n2 = n1 - 8
				end
				if canSnap(g, tank, tank.x, n1) then
					tank.y = n1
				elseif canSnap(g, tank, tank.x, n2) then
					tank.y = n2
				end
			end
		else
			local x = tank.x
			local n1 = floor(x / 8 + 0.5) * 8
			if n1 ~= x then
				local n2 = n1 + 8
				if n1 > x then
					n2 = n1 - 8
				end
				if canSnap(g, tank, n1, tank.y) then
					tank.x = n1
				elseif canSnap(g, tank, n2, tank.y) then
					tank.x = n2
				end
			end
		end
	end
	tank.dir = newDir
end

local function onIce(g, tank)
	local i = floor((tank.x + 8) / MICRO)
	local j = floor((tank.y + 8) / MICRO)
	return g.grid[j * GRID_N + i + 1] == ICE
end

---------------------------------------------------------------------------
-- กระสุน
---------------------------------------------------------------------------

local function tryFire(g, tank)
	local cfg = g.config
	local maxB, speed, power
	if tank.team == "player" then
		local lv = tank.level
		maxB = 1
		if lv >= 2 then
			maxB = 2
		end
		if lv >= 1 then
			speed = cfg.BULLET_SPEED.fast
		else
			speed = cfg.BULLET_SPEED.normal
		end
		power = lv >= 3
	else
		maxB = 1
		speed = cfg.BULLET_SPEED[cfg.ENEMY_BULLET[tank.kind] or "slow"]
		power = false
	end
	speed = tonumber(speed) or 180
	if tank.bullets >= maxB or tank.cooldown > 0 then
		return false
	end
	local dir = tank.dir
	local b = {
		id = nextId(g),
		x = tank.x + 8 + DX[dir] * 6,
		y = tank.y + 8 + DY[dir] * 6,
		dir = dir,
		speed = speed,
		ownerId = tank.id,
		team = tank.team,
		slot = tank.slot,
		power = power,
	}
	g.bullets[#g.bullets + 1] = b
	tank.bullets = tank.bullets + 1
	tank.cooldown = cfg.FIRE_COOLDOWN
	emit(g, { type = "fire", team = tank.team, slot = tank.slot })
	return true
end

-- เอากระสุนออก + คืนโควตาให้เจ้าของ (กันติดลบ/ลดซ้ำ ถ้าเจ้าของตายไปแล้วก็ข้าม)
local function killBullet(g, b)
	if b.dead then
		return
	end
	b.dead = true
	local owner = g._tankById[b.ownerId]
	if owner and owner.bullets > 0 then
		owner.bullets = owner.bullets - 1
	end
end

local function destroyBase(g)
	g.baseDestroyed = true
	emit(g, { type = "explosion", x = BASE_CX, y = BASE_CY, big = true })
	emit(g, { type = "baseDestroyed" })
end

-- กระสุนชนกำแพง: หาแถวหน้าสุดที่ขวาง แล้วกระทบแถบกว้าง 16px ตั้งฉากกับทางวิ่ง
local function bulletHitsGrid(g, b)
	local grid = g.grid
	local i0, i1 = firstIdx(b.x - 2), lastIdx(b.x + 2)
	local j0, j1 = firstIdx(b.y - 2), lastIdx(b.y + 2)
	if i0 < 0 then i0 = 0 end
	if j0 < 0 then j0 = 0 end
	if i1 > GRID_N - 1 then i1 = GRID_N - 1 end
	if j1 > GRID_N - 1 then j1 = GRID_N - 1 end
	local dir = b.dir
	local vertical = dir == UP or dir == DOWN
	local line -- แถว (วิ่งแนวตั้ง) หรือคอลัมน์ (วิ่งแนวนอน) ที่โดน
	if vertical then
		local js, je, st = j0, j1, 1
		if dir == UP then
			js, je, st = j1, j0, -1
		end
		for j = js, je, st do
			for i = i0, i1 do
				if BLOCKS_BULLET[grid[j * GRID_N + i + 1]] then
					line = j
					break
				end
			end
			if line then
				break
			end
		end
	else
		local is, ie, st = i0, i1, 1
		if dir == LEFT then
			is, ie, st = i1, i0, -1
		end
		for i = is, ie, st do
			for j = j0, j1 do
				if BLOCKS_BULLET[grid[j * GRID_N + i + 1]] then
					line = i
					break
				end
			end
			if line then
				break
			end
		end
	end
	if not line then
		return false
	end
	local c = vertical and b.x or b.y
	local k0, k1 = firstIdx(c - 8), lastIdx(c + 8)
	if k0 < 0 then k0 = 0 end
	if k1 > GRID_N - 1 then k1 = GRID_N - 1 end
	local brick, baseHit = false, false
	for k = k0, k1 do
		local i, j = k, line
		if not vertical then
			i, j = line, k
		end
		local kind = grid[j * GRID_N + i + 1]
		if kind == BRICK then
			setCell(g, i, j, EMPTY)
			brick = true
		elseif kind == STEEL then
			if b.power then
				-- กระสุนดาว 3: เหล็กหายทั้งบล็อก 8px
				local bi, bj = i - i % 2, j - j % 2
				for dj = 0, 1 do
					for di = 0, 1 do
						if grid[(bj + dj) * GRID_N + bi + di + 1] == STEEL then
							setCell(g, bi + di, bj + dj, EMPTY)
						end
					end
				end
			end
		elseif kind == BASE then
			baseHit = true
		end
	end
	killBullet(g, b)
	emit(g, { type = "explosion", x = b.x, y = b.y, big = false })
	if brick then
		emit(g, { type = "hit", what = "brick" })
	else
		emit(g, { type = "hit", what = "steel" })
	end
	if baseHit and not g.baseDestroyed then
		destroyBase(g)
	end
	return true
end

local function spawnPowerup(g)
	local kind = POWERUP_KINDS[randInt(g, #POWERUP_KINDS)]
	local x, y = 0, 0
	for _ = 1, 20 do
		x = (randInt(g, 25) - 1) * 8
		y = (randInt(g, 25) - 1) * 8
		local bad = overlap(x, y, TANK, POS.BASE.x, POS.BASE.y, TANK)
		if not bad then
			for _, t in ipairs(g.tanks) do
				if t.team == "player" and overlap(x, y, TANK, t.x, t.y, TANK) then
					bad = true
					break
				end
			end
		end
		if not bad then
			break
		end
	end
	g.powerup = { id = nextId(g), kind = kind, x = x, y = y }
	emit(g, { type = "powerupSpawn", kind = kind })
end

local function killPlayerTank(g, k)
	local t = removeTankAt(g, k)
	emit(g, { type = "explosion", x = t.x + 8, y = t.y + 8, big = true })
	local p = g.players[t.slot]
	if p then
		p.tankId = nil
		p.level = 0
		emit(g, { type = "playerDied", slot = p.slot })
		if p.lives > 0 then
			p.lives = p.lives - 1
			p.respawnPending = true
			p.respawnTimer = g.config.RESPAWN_DELAY
		else
			p.out = true
		end
	end
end

local function hitEnemy(g, k, t, b)
	if t.bonus then
		t.bonus = false
		spawnPowerup(g)
	end
	t.hp = t.hp - 1
	if t.hp > 0 then
		emit(g, { type = "hit", what = "armor" })
		return
	end
	removeTankAt(g, k)
	local cx, cy = t.x + 8, t.y + 8
	emit(g, { type = "explosion", x = cx, y = cy, big = true })
	local p = b.slot and g.players[b.slot]
	if p then
		local points = g.config.ENEMY_POINTS[t.kind] or 0
		emit(g, { type = "score", x = cx, y = cy, points = points })
		addScore(g, p, points)
		local ki = KIND_INDEX[t.kind]
		if ki then
			p.kills[ki] = (p.kills[ki] or 0) + 1
		end
	end
end

local function bulletHitsTank(g, b)
	local tanks = g.tanks
	local bx, by = b.x - 2, b.y - 2
	for k = 1, #tanks do
		local t = tanks[k]
		if t.id ~= b.ownerId and overlap(bx, by, 4, t.x, t.y, TANK) then
			if b.team == "enemy" then
				-- กระสุนศัตรูทะลุรถถังศัตรูด้วยกัน
				if t.team == "player" then
					killBullet(g, b)
					if t.shield > 0 then
						emit(g, { type = "hit", what = "shield" })
					else
						killPlayerTank(g, k)
					end
					return true
				end
			elseif t.team == "enemy" then
				killBullet(g, b)
				hitEnemy(g, k, t, b)
				return true
			elseif t.slot ~= b.slot then
				-- ยิงโดนเพื่อน: เพื่อนแข็งค้างชั่วคราว (โล่กันได้)
				killBullet(g, b)
				if t.shield > 0 then
					emit(g, { type = "hit", what = "shield" })
				else
					t.frozen = g.config.PLAYER_FREEZE_TIME
				end
				return true
			end
		end
	end
	return false
end

local function bulletsCancel(a, b)
	if a.team ~= b.team then
		return true
	end
	return a.team == "player" and a.slot ~= b.slot
end

local function compactBullets(list)
	local n = 0
	for k = 1, #list do
		local b = list[k]
		if not b.dead then
			n = n + 1
			list[n] = b
		end
	end
	for k = #list, n + 1, -1 do
		list[k] = nil
	end
end

-- เดินกระสุนทีละก้าวย่อย (ไม่เกิน 2px) กันกระสุนทะลุกำแพง 4px / ทะลุกระสุนสวน
local function updateBullets(g, h)
	local list = g.bullets
	if #list == 0 then
		return
	end
	local maxMove = 0
	for k = 1, #list do
		local d = list[k].speed * h
		if d > maxMove then
			maxMove = d
		end
	end
	local n = ceil(maxMove / 2 - EPS)
	if n < 1 then
		n = 1
	end
	for _ = 1, n do
		for k = 1, #list do
			local b = list[k]
			local d = b.speed * h / n
			b.x = b.x + DX[b.dir] * d
			b.y = b.y + DY[b.dir] * d
		end
		for k = 1, #list do
			local b = list[k]
			if not b.dead then
				local x, y = b.x, b.y
				if x - 2 < 0 or x + 2 > FIELD or y - 2 < 0 or y + 2 > FIELD then
					killBullet(g, b)
					if x < 0 then x = 0 elseif x > FIELD then x = FIELD end
					if y < 0 then y = 0 elseif y > FIELD then y = FIELD end
					emit(g, { type = "explosion", x = x, y = y, big = false })
					emit(g, { type = "hit", what = "border" })
				elseif not bulletHitsGrid(g, b) then
					bulletHitsTank(g, b)
				end
			end
		end
		-- กระสุนสวนกันหักล้าง (ศัตรูกับศัตรูผ่านกันได้, กระสุนคนเดียวกันไม่ชนกันเอง)
		for a = 1, #list do
			local A = list[a]
			if not A.dead then
				for c = a + 1, #list do
					local B = list[c]
					if not B.dead and bulletsCancel(A, B) and abs(A.x - B.x) < 4 - EPS and abs(A.y - B.y) < 4 - EPS then
						killBullet(g, A)
						killBullet(g, B)
						break
					end
				end
			end
		end
		compactBullets(list)
		if #list == 0 then
			break
		end
	end
end

---------------------------------------------------------------------------
-- ผู้เล่น / AI ศัตรู
---------------------------------------------------------------------------

local function updatePlayerTank(g, tank, h, active)
	local inp = g._inputs[tank.slot]
	if not active or tank.frozen > 0 or not inp then
		tank.slide = 0
		tank.lastInput = -1
		return
	end
	local cfg = g.config
	local dir = inp.dir
	local movedLast = tank.moving
	if dir >= 0 then
		tank.slide = 0
		if dir ~= tank.dir then
			turnTank(g, tank, dir)
		end
		moveTank(g, tank, cfg.PLAYER_SPEED * h)
	else
		-- ปล่อยปุ่มบนน้ำแข็งตอนกำลังวิ่ง -> ไถลต่ออีก ICE_SLIDE_PX
		if tank.lastInput >= 0 and movedLast and onIce(g, tank) then
			tank.slide = cfg.ICE_SLIDE_PX
		end
		if tank.slide > 0 then
			local want = cfg.PLAYER_SPEED * h
			if want > tank.slide then
				want = tank.slide
			end
			local ox, oy = tank.x, tank.y
			moveTank(g, tank, want)
			local got = abs(tank.x - ox) + abs(tank.y - oy)
			if got < want - EPS then
				tank.slide = 0
			else
				tank.slide = tank.slide - got
				if tank.slide < EPS then
					tank.slide = 0
				end
			end
		end
	end
	tank.lastInput = dir
	if inp.fire then
		tryFire(g, tank)
	end
end

-- "มุ่งไปหา" เป้า: แกนที่ห่างกว่า (สุ่ม 30% ใช้อีกแกนถ้าไม่ใช่ศูนย์)
local function towardDir(g, tank, tx, ty)
	local ddx = tx - (tank.x + 8)
	local ddy = ty - (tank.y + 8)
	local useX = abs(ddx) > abs(ddy)
	if rand(g) < 0.3 then
		if useX and ddy ~= 0 then
			useX = false
		elseif not useX and ddx ~= 0 then
			useX = true
		end
	end
	if useX then
		if ddx > 0 then
			return RIGHT
		end
		return LEFT
	end
	if ddy > 0 then
		return DOWN
	elseif ddy < 0 then
		return UP
	end
	return randInt(g, 4) - 1
end

local function chooseDir(g, tank)
	local r = rand(g)
	if r < 0.5 then
		return randInt(g, 4) - 1
	end
	local tx, ty = BASE_CX, BASE_CY
	if r >= 0.75 then
		local best
		local cx, cy = tank.x + 8, tank.y + 8
		for _, t in ipairs(g.tanks) do
			if t.team == "player" then
				local d = (t.x + 8 - cx) * (t.x + 8 - cx) + (t.y + 8 - cy) * (t.y + 8 - cy)
				if not best or d < best then
					best = d
					tx, ty = t.x + 8, t.y + 8
				end
			end
		end
	end
	return towardDir(g, tank, tx, ty)
end

local function updateEnemy(g, tank, h)
	if g.freezeTimer > 0 then
		return
	end
	local cfg = g.config
	local dir = tank.dir
	local vertical = dir == UP or dir == DOWN
	local before = vertical and tank.y or tank.x
	local speed = tonumber(cfg.ENEMY_SPEED[tank.kind]) or 32
	if not moveTank(g, tank, speed * h) then
		-- ติด: บางทียิงใส่สิ่งที่ขวาง (ทำให้ศัตรูเจาะกำแพงอิฐได้แบบ NES) แล้วเปลี่ยนทิศ
		if rand(g) < cfg.AI_BLOCKED_FIRE_CHANCE then
			tryFire(g, tank)
		end
		turnTank(g, tank, chooseDir(g, tank))
	else
		local after = vertical and tank.y or tank.x
		local crossed
		if DX[dir] + DY[dir] > 0 then
			crossed = floor((after + EPS) / 8) > floor((before + EPS) / 8)
		else
			crossed = ceil((after - EPS) / 8) < ceil((before - EPS) / 8)
		end
		if crossed and rand(g) < cfg.AI_TURN_CHANCE then
			turnTank(g, tank, chooseDir(g, tank))
		end
	end
	if tank.bullets == 0 and rand(g) < cfg.AI_FIRE_RATE * h then
		tryFire(g, tank)
	end
end

---------------------------------------------------------------------------
-- จุดเกิด / พาวเวอร์อัป
---------------------------------------------------------------------------

local function newTank(g, team, slot, kind, x, y, dir, hp)
	local t = {
		id = nextId(g),
		team = team,
		slot = slot,
		kind = kind,
		x = x,
		y = y,
		dir = dir,
		moving = false,
		hp = hp,
		maxHp = hp,
		bonus = false,
		shield = 0,
		frozen = 0,
		level = 0,
		bullets = 0,
		cooldown = 0, -- ภายใน: เวลาที่เหลือก่อนยิงนัดถัดไปได้
		slide = 0, -- ภายใน: ระยะไถลบนน้ำแข็งที่เหลือ
		lastInput = -1, -- ภายใน: ทิศที่กดเมื่อ tick ก่อน
	}
	g.tanks[#g.tanks + 1] = t
	g._tankById[t.id] = t
	return t
end

local function hasPlayerAnim(g, slot)
	for _, s in ipairs(g.spawns) do
		if s.team == "player" and s.slot == slot then
			return true
		end
	end
	return false
end

local function queuePlayerSpawn(g, p)
	p.respawnPending = false
	p.respawnTimer = 0
	if p.tankId and g._tankById[p.tankId] then
		return
	end
	if hasPlayerAnim(g, p.slot) then
		return
	end
	local sp = POS.PLAYER_SPAWNS[p.slot]
	g.spawns[#g.spawns + 1] = {
		id = nextId(g),
		x = sp.x,
		y = sp.y,
		t = g.config.SPAWN_ANIM_TIME,
		team = "player",
		slot = p.slot,
		kind = "player",
		bonus = false,
		born = g._ticks, -- ภายใน: tick ที่สร้าง (เริ่มนับถอยหลัง tick ถัดไป ให้ยาวเท่ากันทุกกรณี)
	}
end

local function finishSpawn(g, s)
	local cfg = g.config
	if s.team == "player" then
		local p = g.players[s.slot]
		if p and not (p.tankId and g._tankById[p.tankId]) then
			local t = newTank(g, "player", s.slot, "player", s.x, s.y, UP, 1)
			t.shield = cfg.SHIELD_SPAWN
			t.level = p.level
			p.tankId = t.id
		end
	else
		local hp = tonumber(cfg.ENEMY_HP[s.kind]) or 1
		if hp < 1 then
			hp = 1
		end
		local t = newTank(g, "enemy", nil, s.kind, s.x, s.y, DOWN, hp)
		if s.bonus then
			-- รถถังกะพริบเกิดใหม่ = พาวเวอร์อัปเก่าหายไป (เหมือน NES)
			t.bonus = true
			g.powerup = nil
		end
	end
end

local function updateSpawnAnims(g, h)
	local list = g.spawns
	local k = 1
	while k <= #list do
		local s = list[k]
		if s.born ~= g._ticks then
			s.t = s.t - h
		end
		if s.t <= EPS then
			s.t = 0
			tremove(list, k)
			finishSpawn(g, s)
		else
			k = k + 1
		end
	end
end

local function spawnPointFree(g, x, y)
	for _, t in ipairs(g.tanks) do
		if overlap(x, y, TANK, t.x, t.y, TANK) then
			return false
		end
	end
	-- กันแอนิเมชันเกิดซ้อนจุดเดียวกัน (กรณีตั้ง config ให้เกิดถี่มาก)
	for _, s in ipairs(g.spawns) do
		if overlap(x, y, TANK, s.x, s.y, TANK) then
			return false
		end
	end
	return true
end

local function updateEnemySpawning(g, h)
	g._spawnTimer = g._spawnTimer + h
	if g.enemiesInReserve <= 0 then
		return
	end
	local tanks, anims = enemyCounts(g)
	if tanks + anims >= g.maxEnemiesOnField then
		return
	end
	if g._spawnTimer < spawnInterval(g) - EPS then
		return
	end
	local points = POS.ENEMY_SPAWNS
	for _ = 1, #points do
		local p = points[g._spawnCycle]
		g._spawnCycle = g._spawnCycle % #points + 1
		if spawnPointFree(g, p.x, p.y) then
			g._spawnTimer = 0
			g.enemiesInReserve = g.enemiesInReserve - 1
			g.enemiesSpawned = g.enemiesSpawned + 1
			local order = g.enemiesSpawned
			g.spawns[#g.spawns + 1] = {
				id = nextId(g),
				x = p.x,
				y = p.y,
				t = g.config.SPAWN_ANIM_TIME,
				team = "enemy",
				slot = nil,
				kind = g._stageEnemies[order] or "basic",
				bonus = g._bonusOrder[order] == true,
				born = g._ticks,
			}
			return
		end
	end
end

local function applyPowerup(g, pu, tank, p)
	local cfg = g.config
	local kind = pu.kind
	emit(g, { type = "score", x = pu.x + 8, y = pu.y + 8, points = cfg.POWERUP_POINTS })
	emit(g, { type = "powerupTaken", kind = kind, slot = tank.slot })
	if p then
		addScore(g, p, cfg.POWERUP_POINTS)
	end
	if kind == "star" then
		local lv = tank.level + 1
		if lv > 3 then
			lv = 3
		end
		tank.level = lv
		if p then
			p.level = lv
		end
	elseif kind == "grenade" then
		-- ระเบิดศัตรูทุกคันบนสนาม: ไม่ได้แต้ม ไม่นับในตารางคะแนน
		local tanks = g.tanks
		local k = 1
		while k <= #tanks do
			local t = tanks[k]
			if t.team == "enemy" then
				removeTankAt(g, k)
				emit(g, { type = "explosion", x = t.x + 8, y = t.y + 8, big = true })
			else
				k = k + 1
			end
		end
	elseif kind == "helmet" then
		if tank.shield < cfg.SHIELD_HELMET then
			tank.shield = cfg.SHIELD_HELMET
		end
	elseif kind == "shovel" then
		g.shovelTimer = cfg.SHOVEL_TIME
		setRing(g, STEEL)
	elseif kind == "timer" then
		g.freezeTimer = cfg.FREEZE_TIME
	elseif kind == "tank" then
		if p then
			p.lives = p.lives + 1
			emit(g, { type = "extraLife", slot = p.slot })
		end
	end
end

local function updatePowerupPickup(g)
	local pu = g.powerup
	if not pu then
		return
	end
	local tanks = g.tanks
	for k = 1, #tanks do
		local t = tanks[k]
		if t.team == "player" and overlap(t.x, t.y, TANK, pu.x, pu.y, TANK) then
			g.powerup = nil
			applyPowerup(g, pu, t, g.players[t.slot])
			return
		end
	end
end

---------------------------------------------------------------------------
-- ตัวจับเวลา
---------------------------------------------------------------------------

local function updateShovel(g, h)
	if g.shovelTimer <= 0 then
		return
	end
	local cfg = g.config
	g.shovelTimer = g.shovelTimer - h
	if g.shovelTimer <= EPS then
		g.shovelTimer = 0
		setRing(g, BRICK)
	elseif g.shovelTimer <= cfg.SHOVEL_FLASH_TIME + EPS then
		-- ช่วงท้าย: สลับอิฐ/เหล็กจริง ๆ (ชนได้จริงแบบ NES) เริ่มจากอิฐ
		local period = cfg.SHOVEL_FLASH_PERIOD
		local kind = BRICK
		if period > 0 then
			local idx = floor((cfg.SHOVEL_FLASH_TIME - g.shovelTimer) / period + EPS)
			if idx % 2 == 1 then
				kind = STEEL
			end
		end
		setRing(g, kind)
	end
end

local function updateTimers(g, h, respawnActive)
	if g.freezeTimer > 0 then
		g.freezeTimer = g.freezeTimer - h
		if g.freezeTimer < EPS then
			g.freezeTimer = 0
		end
	end
	updateShovel(g, h)
	for _, t in ipairs(g.tanks) do
		if t.shield > 0 then
			t.shield = t.shield - h
			if t.shield < EPS then
				t.shield = 0
			end
		end
		if t.frozen > 0 then
			t.frozen = t.frozen - h
			if t.frozen < EPS then
				t.frozen = 0
			end
		end
		if t.cooldown > 0 then
			t.cooldown = t.cooldown - h
			if t.cooldown < EPS then
				t.cooldown = 0
			end
		end
	end
	if respawnActive then
		for slot = 1, 2 do
			local p = g.players[slot]
			if p and p.respawnPending then
				p.respawnTimer = p.respawnTimer - h
				if p.respawnTimer <= EPS then
					queuePlayerSpawn(g, p)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- เฟส / ด่าน
---------------------------------------------------------------------------

local function setPhase(g, phase)
	g.phase = phase
	g.phaseTime = 0
	emit(g, { type = "phase", phase = phase })
end

local function clearField(g)
	clearArray(g.tanks)
	clearArray(g.bullets)
	clearArray(g.spawns)
	g._tankById = {}
	g.powerup = nil
	for slot = 1, 2 do
		local p = g.players[slot]
		if p then
			p.tankId = nil
			p.respawnPending = false
			p.respawnTimer = 0
		end
	end
end

local function loadStage(g)
	local cfg = g.config
	local stages = g.stages
	local idx = ((g.stageNumber - 1) % #stages) + 1
	local st = stages[idx]
	if type(st) ~= "table" then
		st = {}
	end
	if st.name ~= nil then
		g.stageName = tostring(st.name)
	else
		g.stageName = ""
	end
	local map = st.map
	if type(map) ~= "table" then
		map = {}
	end
	local grid = g.grid
	for cy = 0, 25 do
		local row = map[cy + 1]
		if type(row) ~= "string" then
			row = ""
		end
		for cx = 0, 25 do
			local kind = CHAR_KIND[string.sub(row, cx + 1, cx + 1)] or EMPTY
			local base = (cy * 2) * GRID_N + cx * 2 + 1
			grid[base] = kind
			grid[base + 1] = kind
			grid[base + GRID_N] = kind
			grid[base + GRID_N + 1] = kind
		end
	end
	-- บังคับตำแหน่งตายตัว ไม่ว่าด่านจะเขียนมาอย่างไร
	for k = 1, #SPAWN_MICRO, 2 do
		grid[SPAWN_MICRO[k + 1] * GRID_N + SPAWN_MICRO[k] + 1] = EMPTY
	end
	for k = 1, #RING_MICRO, 2 do
		grid[RING_MICRO[k + 1] * GRID_N + RING_MICRO[k] + 1] = BRICK
	end
	for k = 1, #BASE_MICRO, 2 do
		grid[BASE_MICRO[k + 1] * GRID_N + BASE_MICRO[k] + 1] = BASE
	end
	-- ลำดับชนิดศัตรูของด่าน (ตัวอักษรไม่รู้จัก/ขาด -> basic)
	local s = st.enemies
	if type(s) ~= "string" then
		s = ""
	end
	local kinds = {}
	for k = 1, cfg.ENEMIES_PER_STAGE do
		kinds[k] = ENEMY_CHAR[string.sub(s, k, k)] or "basic"
	end
	g._stageEnemies = kinds
	emit(g, { type = "stage", stageNumber = g.stageNumber, name = g.stageName })
end

local function enterIntro(g)
	setPhase(g, "intro")
	clearField(g)
	g.tally = nil
	g.enemiesInReserve = g.config.ENEMIES_PER_STAGE
	g.enemiesSpawned = 0
	g.freezeTimer = 0
	g.shovelTimer = 0
	g.baseDestroyed = false
	g._spawnTimer = 0
	g._spawnCycle = 1
	for slot = 1, 2 do
		local p = g.players[slot]
		if p then
			p.kills = { 0, 0, 0, 0 }
		end
	end
	loadStage(g)
end

local function newGame(g)
	local cfg = g.config
	g.stageNumber = 1
	g.isGameOver = false
	g.baseDestroyed = false
	for slot = 1, 2 do
		local p = g.players[slot]
		if p then
			p.lives = cfg.START_LIVES
			p.score = 0
			p.level = 0
			p.out = false
			p.bonusLifeGiven = false
			p.respawnPending = false
			p.respawnTimer = 0
		end
	end
	enterIntro(g)
end

local function enterPlaying(g)
	setPhase(g, "playing")
	-- ศัตรูตัวแรกของด่านออกทันที
	g._spawnTimer = spawnInterval(g)
	for slot = 1, 2 do
		local p = g.players[slot]
		if p and not p.out then
			queuePlayerSpawn(g, p)
		end
	end
end

local function enterGameOver(g)
	g.isGameOver = true
	setPhase(g, "gameOver")
end

local function enterTally(g)
	local cfg = g.config
	local tally = { stageNumber = g.stageNumber, gameOver = g.isGameOver == true, players = {} }
	local present = 0
	for slot = 1, 2 do
		local p = g.players[slot]
		if p then
			present = present + 1
			local kills, points, total = {}, {}, 0
			for k = 1, 4 do
				local n = p.kills[k] or 0
				kills[k] = n
				points[k] = n * (cfg.ENEMY_POINTS[KIND_ORDER[k]] or 0)
				total = total + n
			end
			tally.players[slot] = { kills = kills, points = points, totalKills = total, score = p.score, bonus = 0 }
		end
	end
	-- โบนัส 1000 ให้คนที่ฆ่าได้มากกว่า (เฉพาะเล่น 2 คนและด่านผ่าน)
	if present == 2 and not g.isGameOver then
		local a, b = tally.players[1], tally.players[2]
		local winner
		if a.totalKills > b.totalKills then
			winner = 1
		elseif b.totalKills > a.totalKills then
			winner = 2
		end
		if winner then
			local p = g.players[winner]
			addScore(g, p, 1000)
			tally.players[winner].bonus = 1000
			tally.players[winner].score = p.score
		end
	end
	for slot = 1, 2 do
		local p = g.players[slot]
		if p and p.score > g.hiScore then
			g.hiScore = p.score
		end
	end
	g.tally = tally
	setPhase(g, "tally")
end

local function goWaiting(g)
	clearField(g)
	setPhase(g, "waiting")
end

local function updatePhase(g)
	local cfg = g.config
	local ph = g.phase
	local t = g.phaseTime + EPS
	if ph == "intro" then
		if t >= cfg.INTRO_TIME then
			enterPlaying(g)
		end
	elseif ph == "stageClear" then
		if t >= cfg.STAGE_CLEAR_DELAY then
			enterTally(g)
		end
	elseif ph == "gameOver" then
		if t >= cfg.GAMEOVER_TIME then
			enterTally(g)
		end
	elseif ph == "tally" then
		if t >= cfg.TALLY_TIME then
			if g.isGameOver then
				setPhase(g, "final")
			else
				g.stageNumber = g.stageNumber + 1
				enterIntro(g)
			end
		end
	elseif ph == "final" then
		if t >= cfg.FINAL_TIME then
			if countPlayers(g) > 0 then
				newGame(g)
			else
				goWaiting(g)
			end
		end
	end
end

local function allPlayersOut(g)
	local any = false
	for slot = 1, 2 do
		local p = g.players[slot]
		if p then
			any = true
			if not p.out or p.respawnPending or (p.tankId and g._tankById[p.tankId]) or hasPlayerAnim(g, slot) then
				return false
			end
		end
	end
	return any
end

local function checkEnd(g)
	local ph = g.phase
	if ph ~= "playing" and ph ~= "stageClear" then
		return
	end
	if g.baseDestroyed or allPlayersOut(g) then
		enterGameOver(g)
		return
	end
	if ph == "playing" and g.enemiesInReserve <= 0 then
		local tanks, anims = enemyCounts(g)
		if tanks == 0 and anims == 0 then
			setPhase(g, "stageClear")
		end
	end
end

-- 1 ก้าวย่อย (ไม่เกิน TICK) ตามลำดับในสเปก
local function subStep(g, h)
	g._ticks = g._ticks + 1
	g.time = g.time + h
	g.phaseTime = g.phaseTime + h
	updatePhase(g) -- 1
	local ph = g.phase
	if ph ~= "playing" and ph ~= "stageClear" and ph ~= "gameOver" then
		-- เฟสที่ไม่จำลอง (เช่น tally): รถถังที่ค้างอยู่ไม่ได้ขยับใน tick นี้ ไม่งั้นตีนตะขาบยังหมุนค้าง
		for _, t in ipairs(g.tanks) do
			t.moving = false
		end
		return
	end
	local active = ph ~= "gameOver" -- ตอน game over ผู้เล่นขยับไม่ได้ แต่ศัตรูยังเดินต่อ
	updateTimers(g, h, active) -- 2
	updateSpawnAnims(g, h) -- 3
	if ph ~= "stageClear" then
		updateEnemySpawning(g, h) -- 4
	end
	for slot = 1, 2 do -- 5
		local p = g.players[slot]
		local t = p and p.tankId and g._tankById[p.tankId]
		if t then
			local ox, oy = t.x, t.y
			updatePlayerTank(g, t, h, active)
			t.moving = t.x ~= ox or t.y ~= oy
		end
	end
	local tanks = g.tanks
	for k = 1, #tanks do -- 6
		local t = tanks[k]
		if t.team == "enemy" then
			local ox, oy = t.x, t.y
			updateEnemy(g, t, h)
			t.moving = t.x ~= ox or t.y ~= oy
		end
	end
	updateBullets(g, h) -- 7
	if active then
		updatePowerupPickup(g) -- 8
	end
	checkEnd(g) -- 9
end

---------------------------------------------------------------------------
-- API สาธารณะ
---------------------------------------------------------------------------

local Game = {}
Game.__index = Game

function Core.new(opts)
	if type(opts) ~= "table" then
		opts = {}
	end
	local stages = opts.stages
	if type(stages) ~= "table" or #stages == 0 then
		-- ไม่มีข้อมูลด่าน: ใช้สนามว่าง (มีแค่ฐาน) เพื่อไม่ให้เกมพัง
		stages = { { name = "", map = {}, enemies = "" } }
	end
	local cfg = mergeConfig(opts.config)
	local seed = tonumber(opts.seed) or 1
	if seed ~= seed then
		seed = 1
	end
	seed = floor(seed)
	if seed < 1 then
		seed = 1
	elseif seed > RNG_M - 1 then
		seed = RNG_M - 1
	end
	local g = setmetatable({}, Game)
	g.config = cfg
	g.stages = stages
	g.phase = "waiting"
	g.phaseTime = 0
	g.time = 0
	g.stageNumber = 1
	g.stageName = ""
	g.grid = {}
	for k = 1, GRID_N * GRID_N do
		g.grid[k] = EMPTY
	end
	g.tanks = {}
	g.bullets = {}
	g.spawns = {}
	g.powerup = nil
	g.players = {}
	g.enemiesInReserve = 0
	g.enemiesSpawned = 0
	g.freezeTimer = 0
	g.shovelTimer = 0
	g.baseDestroyed = false
	g.hiScore = 20000 -- ค่าเริ่มต้นแบบ NES
	g.isGameOver = false
	g.tally = nil
	g.maxEnemiesOnField = 4
	-- ภายใน
	g._rng = seed
	g._nextId = 0
	g._ticks = 0
	g._events = {}
	g._inputs = { { dir = -1, fire = false }, { dir = -1, fire = false } }
	g._tankById = {}
	g._spawnTimer = 0
	g._spawnCycle = 1
	g._stageEnemies = {}
	g._bonusOrder = {}
	if type(cfg.BONUS_ENEMIES) == "table" then
		for _, n in ipairs(cfg.BONUS_ENEMIES) do
			g._bonusOrder[n] = true
		end
	end
	if type(cfg.MAX_ENEMIES) ~= "table" then
		cfg.MAX_ENEMIES = { tonumber(cfg.MAX_ENEMIES) or 4 }
	end
	updateMaxEnemies(g)
	return g
end

local function validSlot(slot)
	if slot == 1 or slot == 2 then
		return floor(slot)
	end
	return nil
end

function Game:addPlayer(slot)
	slot = validSlot(slot)
	if not slot or self.players[slot] then
		return
	end
	local cfg = self.config
	local p = {
		slot = slot,
		lives = cfg.START_LIVES,
		score = 0,
		level = 0,
		kills = { 0, 0, 0, 0 },
		out = false,
		respawnTimer = 0,
		respawnPending = false,
		tankId = nil,
		bonusLifeGiven = false,
	}
	self.players[slot] = p
	updateMaxEnemies(self)
	local ph = self.phase
	if ph == "waiting" then
		newGame(self)
	elseif ph == "playing" or ph == "stageClear" then
		queuePlayerSpawn(self, p)
	end
	-- intro: เกิดตอนเริ่ม playing / gameOver, tally, final: รอเกมหรือด่านถัดไป
end

function Game:removePlayer(slot)
	slot = validSlot(slot)
	if not slot then
		return
	end
	local p = self.players[slot]
	if not p then
		return
	end
	if p.tankId then
		removeTankById(self, p.tankId)
	end
	local list = self.spawns
	for k = #list, 1, -1 do
		if list[k].team == "player" and list[k].slot == slot then
			tremove(list, k)
		end
	end
	self.players[slot] = nil
	self._inputs[slot].dir = -1
	self._inputs[slot].fire = false
	if countPlayers(self) == 0 then
		goWaiting(self)
	else
		updateMaxEnemies(self)
	end
end

function Game:setInput(slot, dir, fire)
	slot = validSlot(slot)
	if not slot then
		return
	end
	if type(dir) ~= "number" or dir ~= floor(dir) or dir < -1 or dir > 3 then
		return
	end
	if type(fire) ~= "boolean" then
		return
	end
	local inp = self._inputs[slot]
	inp.dir = floor(dir)
	inp.fire = fire
end

function Game:step(dt)
	dt = tonumber(dt)
	if not dt or dt ~= dt or dt <= 0 then
		return
	end
	if dt > 0.25 then
		dt = 0.25 -- กันเฟรมกระตุกนาน ๆ ทำให้เกมกระโดด
	end
	local tick = tonumber(self.config.TICK) or 1 / 60
	if not (tick > 0) then
		tick = 1 / 60
	end
	local n = ceil(dt / tick - 1e-9)
	if n < 1 then
		n = 1
	end
	local h = dt / n
	for _ = 1, n do
		subStep(self, h)
	end
end

function Game:popEvents()
	local q = self._events
	self._events = {}
	return q
end

function Game:getCell(i, j)
	if type(i) ~= "number" or type(j) ~= "number" then
		return STEEL
	end
	i, j = floor(i), floor(j)
	if i < 0 or j < 0 or i >= GRID_N or j >= GRID_N then
		return STEEL
	end
	return self.grid[j * GRID_N + i + 1] or EMPTY
end

return Core
