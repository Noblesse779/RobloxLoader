# -*- coding: utf-8 -*-
"""ทดสอบ BattleCityCore.lua แบบ black-box โดยอิงจาก SPEC เท่านั้น (บทบาท core-tests)

รัน:  python -m pytest -q BattleCity/tests/test_core.py

หลักการ: สร้างด่านทดสอบเอง (26x26) + config ย่อเวลา แล้วจิ้มสถานะสาธารณะ (x/y, grid, freezeTimer)
เพื่อจัดฉาก เพราะ SPEC บอกว่าตารางพวกนี้เป็น public  เวลาที่ SPEC ไม่ได้ล็อกลำดับ tick ให้คลาดได้ 1-2 tick
"""
import math
import os
import random
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402

# BC_CORE_PATH ใช้ชี้ไปยังสำเนา core อื่น (เช่นตอนทำ mutation test) ปกติไม่ต้องตั้ง
CORE_PATH = os.environ.get("BC_CORE_PATH") or luaenv.path("BattleCityCore.lua")
TICK = 1.0 / 60
EPS = 1e-6
UP, RIGHT, DOWN, LEFT = 0, 1, 2, 3
EMPTY, BRICK, STEEL, WATER, TREES, ICE, BASE = 0, 1, 2, 3, 4, 5, 6
CHAR_KIND = {".": EMPTY, "B": BRICK, "S": STEEL, "W": WATER, "T": TREES, "I": ICE, "E": BASE}
GN = 52

BASE_CELLS = {(12, 24), (13, 24), (12, 25), (13, 25)}
RING_CELLS = {(11, 23), (12, 23), (13, 23), (14, 23), (11, 24), (11, 25), (14, 24), (14, 25)}
SPAWN_TILES = [(0, 0), (12, 0), (24, 0), (8, 24), (16, 24)]
SPAWN_CELLS = {(cx + dx, cy + dy) for cx, cy in SPAWN_TILES for dx in (0, 1) for dy in (0, 1)}


def micro_of(cells):
    return sorted({(2 * cx + dx, 2 * cy + dy) for cx, cy in cells for dx in (0, 1) for dy in (0, 1)})


RING_MICRO = micro_of(RING_CELLS)
BASE_MICRO = micro_of(BASE_CELLS)
ENEMY_SPAWN_PX = [(96, 0), (192, 0), (0, 0)]
PLAYER_SPAWN_PX = {1: (64, 192), 2: (128, 192)}
PHASES = {"waiting", "intro", "playing", "stageClear", "gameOver", "tally", "final"}
POWERUP_KINDS = {"star", "grenade", "helmet", "shovel", "timer", "tank"}
ENEMY_KINDS = {"basic", "fast", "power", "armor"}
# จุดจอดรถถังศัตรูที่เทสต์ย้ายออกจากจุดเกิด (ไม่ทับผู้เล่น ฐาน หรือจุดเกิด)
PARK = [(x, y) for y in (32, 64, 96, 128) for x in range(0, 193, 24)]

SPEC_DEFAULTS = {
    "TICK": 1.0 / 60, "PLAYER_SPEED": 48,
    "ENEMY_SPEED": {"basic": 32, "fast": 80, "power": 48, "armor": 48},
    "BULLET_SPEED": {"slow": 120, "normal": 180, "fast": 240},
    "ENEMY_BULLET": {"basic": "slow", "fast": "normal", "power": "fast", "armor": "normal"},
    "ENEMY_HP": {"basic": 1, "fast": 1, "power": 1, "armor": 4},
    "ENEMY_POINTS": {"basic": 100, "fast": 200, "power": 300, "armor": 400},
    "POWERUP_POINTS": 500, "START_LIVES": 2, "BONUS_LIFE_SCORE": 20000, "ENEMIES_PER_STAGE": 20,
    "MAX_ENEMIES": [4, 6], "BONUS_ENEMIES": [4, 11, 18], "SPAWN_ANIM_TIME": 1.0, "ENEMY_SPAWN_BASE": 190,
    "RESPAWN_DELAY": 0.5, "SHIELD_SPAWN": 3, "SHIELD_HELMET": 10, "FREEZE_TIME": 10, "SHOVEL_TIME": 20,
    "SHOVEL_FLASH_TIME": 3, "SHOVEL_FLASH_PERIOD": 0.25, "PLAYER_FREEZE_TIME": 3, "ICE_SLIDE_PX": 24,
    "FIRE_COOLDOWN": 0.12, "AI_TURN_CHANCE": 0.125, "AI_FIRE_RATE": 0.8, "AI_BLOCKED_FIRE_CHANCE": 0.3,
    "AI_FIRE_RATE_PER_STAGE": 0.015, "AI_BASE_CHANCE_START": 0.05, "AI_BASE_CHANCE_MAX": 0.25,
    "AI_BASE_RAMP_TIME": 25, "AI_PLAYER_CHANCE": 0.2,
    "INTRO_TIME": 2.5, "STAGE_CLEAR_DELAY": 3, "GAMEOVER_TIME": 4, "TALLY_TIME": 6, "FINAL_TIME": 3,
}

TANK_FIELDS = ["id", "team", "slot", "kind", "x", "y", "dir", "moving", "hp", "maxHp", "bonus", "shield",
               "frozen", "level", "bullets"]
BULLET_FIELDS = ["id", "x", "y", "dir", "speed", "ownerId", "team", "slot", "power"]
SPAWN_FIELDS = ["id", "x", "y", "t", "team", "slot", "kind", "bonus"]
PLAYER_FIELDS = ["slot", "lives", "score", "level", "out", "respawnTimer", "tankId", "bonusLifeGiven"]
EVENT_FIELDS = {
    "phase": ["phase"], "stage": ["stageNumber", "name"], "cell": ["i", "j", "kind"],
    "explosion": ["x", "y", "big"], "score": ["x", "y", "points"], "fire": ["team"], "hit": ["what"],
    "powerupSpawn": ["kind"], "powerupTaken": ["kind", "slot"], "baseDestroyed": [],
    "playerDied": ["slot"], "extraLife": ["slot"],
}

# ตัวช่วยฝั่ง Lua: เรียกเมธอดแบบ obj:name(...), ลบสมาชิกจากอาร์เรย์โดยรักษาลำดับ, แปลง grid เป็นสตริงเร็วๆ
LUA_HELPERS = """
local H = {}
function H.call(obj, name, ...)
  return obj[name](obj, ...)
end
function H.typeOf(obj, name)
  return type(obj[name])
end
function H.removeWhere(arr, field, value)
  local n = #arr
  local k = 1
  for idx = 1, n do
    local v = arr[idx]
    if v[field] ~= value then
      arr[k] = v
      k = k + 1
    end
  end
  for idx = n, k, -1 do
    arr[idx] = nil
  end
end
function H.gridStr(grid, n)
  local parts = {}
  for k = 1, n do
    parts[k] = tostring(grid[k])
  end
  return table.concat(parts, ",")
end
return H
"""


# ---------------------------------------------------------------- helpers

def lua_src(v):
    """แปลงค่าจาก python เป็นซอร์ส Lua (ใช้สร้าง opts/ตารางที่จิ้มใส่ core)"""
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_src(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join("[%s] = %s" % (lua_src(k), lua_src(x)) for k, x in v.items()) + "}"
    raise TypeError(v)


def make_layout(fill=".", rows=None, cells=None, fixed=True):
    g = [[fill] * 26 for _ in range(26)]
    for cy, ch in (rows or {}).items():
        for cx in range(26):
            g[cy][cx] = ch
    for (cx, cy), ch in (cells or {}).items():
        g[cy][cx] = ch
    if fixed:
        for cx, cy in SPAWN_CELLS:
            g[cy][cx] = "."
        for cx, cy in RING_CELLS:
            g[cy][cx] = "B"
        for cx, cy in BASE_CELLS:
            g[cy][cx] = "E"
    return ["".join(r) for r in g]


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        if not v:
            return []
        return [v[k] for k in sorted(v)]
    raise AssertionError("expected array, got %r" % (v,))


def kills_list(v):
    """kills ตาม SPEC คือ {b,f,p,a} (อาร์เรย์ 4 ช่อง) — รับรูป dict ด้วยเผื่อ core ใช้ key"""
    if isinstance(v, list):
        assert len(v) == 4, v
        return [int(x) for x in v]
    if isinstance(v, dict):
        for keys in (("b", "f", "p", "a"), ("basic", "fast", "power", "armor"), (1, 2, 3, 4)):
            if any(k in v for k in keys):
                return [int(v.get(k, 0)) for k in keys]
    raise AssertionError("bad kills table %r" % (v,))


def close(a, b, tol=EPS):
    return abs(a - b) <= tol


def assert_struct_close(actual, expected, label):
    if isinstance(expected, dict):
        assert isinstance(actual, dict), label
        for k, v in expected.items():
            assert k in actual, "%s.%s missing" % (label, k)
            assert_struct_close(actual[k], v, "%s.%s" % (label, k))
    elif isinstance(expected, list):
        assert isinstance(actual, list) and len(actual) == len(expected), "%s: %r" % (label, actual)
        for k, (a, e) in enumerate(zip(actual, expected)):
            assert_struct_close(a, e, "%s[%d]" % (label, k))
    elif isinstance(expected, str):
        assert actual == expected, "%s: %r != %r" % (label, actual, expected)
    else:
        assert isinstance(actual, (int, float)) and close(actual, expected, 1e-9), "%s: %r != %r" % (label, actual, expected)


def boxes_overlap(ax, ay, aw, bx, by, bw):
    return ax < bx + bw and bx < ax + aw and ay < by + bw and by < ay + aw


def pick(tbl, fields):
    if tbl is None:
        return None
    out = {}
    for f in fields:
        v = tbl[f]
        out[f] = v
    return out


QUIET = {"INTRO_TIME": 0.05, "MAX_ENEMIES": [0, 0]}


def quiet(**kw):
    """ไม่มีศัตรูเลย (MAX_ENEMIES = 0) — ใช้ทดสอบกลไกผู้เล่นล้วนๆ"""
    c = dict(QUIET)
    c.update(kw)
    return c


def arena(**kw):
    """มีศัตรูแต่ AI ไม่ยิง/ไม่เลี้ยวเอง และเกิดทุก 1 วินาที — จัดฉากได้แน่นอน"""
    c = {"INTRO_TIME": 0.05, "ENEMY_SPAWN_BASE": 30, "AI_FIRE_RATE": 0, "AI_TURN_CHANCE": 0,
         "AI_BLOCKED_FIRE_CHANCE": 0, "BONUS_ENEMIES": []}
    c.update(kw)
    return c


class Sim:
    def __init__(self, layout=None, enemies="b" * 20, seed=1, config=None, stages=None, name="Test Field",
                 math_seed=None, pass_seed=True):
        self.lua = luaenv.new_runtime()
        if math_seed is not None:
            self.lua.execute("math.randomseed(%d)" % math_seed)
        self.Core = luaenv.load_file(self.lua, CORE_PATH)
        self.H = self.lua.execute(LUA_HELPERS)
        if stages is None:
            stages = [{"name": name, "map": layout if layout is not None else make_layout(), "enemies": enemies}]
        opts = {"stages": stages}
        if pass_seed:
            opts["seed"] = seed
        if config:
            opts["config"] = config
        self.g = self.Core.new(self.lua_value(opts))
        self.tick = 0
        self.log = []
        self.shadow = None
        self.hooks = []
        self.parked = set()
        self.park_slots = list(PARK)
        self.seen_spawns = []

    # --- พื้นฐาน
    def lua_value(self, v):
        return self.lua.eval(lua_src(v))

    def call(self, name, *args):
        return self.H.call(self.g, name, *args)

    def add(self, slot):
        self.call("addPlayer", slot)

    def remove(self, slot):
        self.call("removePlayer", slot)

    def set_input(self, slot, d, fire=False):
        self.call("setInput", slot, d, fire)

    def pop(self):
        return as_list(luaenv.to_py(self.call("popEvents")))

    def step(self, dt=TICK, n=1):
        for _ in range(n):
            self.call("step", dt)
            self.tick += 1
            for e in self.pop():
                self.log.append((self.tick, e))
                typ = e.get("type")
                if typ == "stage":
                    self.shadow = self.grid()
                elif typ == "cell" and self.shadow is not None:
                    self.shadow[int(e["j"]) * GN + int(e["i"])] = e["kind"]
            for h in self.hooks:
                h()

    def run(self, seconds, dt=TICK):
        self.step(dt, int(round(seconds / dt)))

    def run_until(self, pred, max_seconds, what="condition"):
        limit = int(round(max_seconds * 60))
        for k in range(limit + 1):
            if pred():
                return k
            if k < limit:
                self.step()
        raise AssertionError("timeout waiting for %s (phase=%s tick=%d)" % (what, self.phase, self.tick))

    # --- อ่านสถานะ
    @property
    def phase(self):
        return self.g.phase

    @staticmethod
    def arr(t):
        if t is None:
            return []
        return [t[k] for k in range(1, len(t) + 1)]

    def tanks(self):
        return self.arr(self.g.tanks)

    def enemies(self):
        return [t for t in self.tanks() if t.team == "enemy"]

    def ptank(self, slot):
        for t in self.tanks():
            if t.team == "player" and t.slot == slot:
                return t
        return None

    def bullets(self):
        return self.arr(self.g.bullets)

    def player_bullets(self, slot):
        return [b for b in self.bullets() if b.team == "player" and b.slot == slot]

    def spawns(self):
        return self.arr(self.g.spawns)

    def enemy_spawns(self):
        return [s for s in self.spawns() if s.team == "enemy"]

    def player_spawn(self, slot):
        for s in self.spawns():
            if s.team == "player" and s.slot == slot:
                return s
        return None

    def player(self, slot):
        return self.g.players[slot]

    def kills(self, slot):
        return kills_list(luaenv.to_py(self.player(slot).kills))

    def set_kills(self, slot, values):
        cur = luaenv.to_py(self.player(slot).kills)
        if isinstance(cur, dict) and "b" in cur:
            self.player(slot).kills = self.lua_value(dict(zip("bfpa", values)))
        else:
            self.player(slot).kills = self.lua_value(list(values))

    def cell(self, i, j):
        return self.g.grid[j * GN + i + 1]

    def set_cell(self, i, j, kind):
        self.g.grid[j * GN + i + 1] = kind

    def get_cell(self, i, j):
        return self.call("getCell", i, j)

    def grid(self):
        s = self.H.gridStr(self.g.grid, GN * GN)
        return [int(float(x)) for x in s.split(",")]

    def resync_shadow(self):
        self.shadow = self.grid()

    def events(self, typ=None, since=0):
        return [e for (t, e) in self.log if t > since and (typ is None or e.get("type") == typ)]

    # --- จัดฉาก
    def freeze_enemies(self):
        self.g.freezeTimer = 1e6

    def unfreeze_enemies(self):
        self.g.freezeTimer = 0

    def enable_parking(self):
        def hook():
            for t in self.enemies():
                if t.id not in self.parked and t.y < 16:
                    x, y = self.park_slots.pop(0)
                    t.x, t.y = x, y
                    self.parked.add(t.id)
        self.hooks.append(hook)
        hook()

    def track_spawns(self):
        ids = set()

        def hook():
            for s in self.enemy_spawns():
                if s.id not in ids:
                    ids.add(s.id)
                    self.seen_spawns.append({"tick": self.tick, "x": s.x, "y": s.y, "kind": s.kind,
                                             "bonus": s.bonus, "t": s.t})
        self.hooks.append(hook)
        hook()

    def start(self, slots=(1,), freeze=False, park=False, track=False, wait_tanks=True):
        for s in slots:
            self.add(s)
        self.run_until(lambda: self.phase == "playing", 10, "playing")
        if freeze:
            self.freeze_enemies()
        if track:
            self.track_spawns()
        if park:
            self.enable_parking()
        if wait_tanks:
            self.run_until(lambda: all(self.ptank(s) is not None for s in slots), 3, "player tanks")

    def clear_stage(self):
        """จิ้มให้ด่านเคลียร์: ไม่มีศัตรูสำรอง ไม่มีศัตรูบนสนาม/กำลังเกิด"""
        self.g.enemiesInReserve = 0
        self.H.removeWhere(self.g.tanks, "team", "enemy")
        self.H.removeWhere(self.g.spawns, "team", "enemy")

    def remove_tank(self, tank_id):
        self.H.removeWhere(self.g.tanks, "id", tank_id)

    def fire_once(self, slot=1, max_ticks=120):
        self.set_input(slot, -1, True)
        t0 = self.tick
        for _ in range(max_ticks):
            self.step()
            if any(e.get("slot") == slot for e in self.events("fire", t0)):
                break
        else:
            raise AssertionError("player %d did not fire" % slot)
        self.set_input(slot, -1, False)

    def wait_player_bullets_gone(self, slot=1, max_s=3):
        self.run_until(lambda: not self.player_bullets(slot), max_s, "bullets of P%d gone" % slot)

    def give_powerup(self, kind, slot=1):
        """วางพาวเวอร์อัปทับรถถังผู้เล่นแล้วเดินจนเก็บได้ คืน tick ก่อนเก็บ"""
        t = self.ptank(slot)
        self.g.powerup = self.lua_value({"id": 90000 + self.tick, "kind": kind, "x": t.x, "y": t.y})
        t0 = self.tick
        self.run_until(lambda: self.events("powerupTaken", t0), 3 * TICK, "pickup " + kind)
        return t0

    def enemy_kills_player(self, slot, max_s=3):
        """ศัตรูตัวแรกยิงลงใส่ผู้เล่นจากด้านบน (ต้องใช้ AI_FIRE_RATE สูงและ AI_TURN_CHANCE 0)"""
        e = self.enemies()[0]
        p = self.ptank(slot)
        e.x, e.y, e.dir = p.x, p.y - 90, DOWN
        p.shield = 0
        t0 = self.tick
        self.unfreeze_enemies()
        self.run_until(lambda: self.events("playerDied", t0), max_s, "player death")
        self.freeze_enemies()
        return t0


def ring_state(sim):
    kinds = {sim.cell(i, j) for (i, j) in RING_MICRO}
    if kinds == {STEEL}:
        return "S"
    if kinds == {BRICK}:
        return "B"
    return "X" + repr(sorted(kinds))


# ---------------------------------------------------------------- API & stage load

def test_api_surface_and_constants():
    lua = luaenv.new_runtime()
    Core = luaenv.load_file(lua, CORE_PATH)
    to = luaenv.to_py
    assert to(Core.CELL) == {"EMPTY": 0, "BRICK": 1, "STEEL": 2, "WATER": 3, "TREES": 4, "ICE": 5, "BASE": 6}
    assert to(Core.DIR) == {"UP": 0, "RIGHT": 1, "DOWN": 2, "LEFT": 3}
    assert Core.FIELD == 208 and Core.GRID_N == 52 and Core.MICRO == 4
    assert Core.POS is not None and isinstance(to(Core.POS), dict)
    cfg = to(Core.DEFAULT_CONFIG)
    for k, v in SPEC_DEFAULTS.items():
        assert k in cfg, "DEFAULT_CONFIG.%s missing" % k
        assert_struct_close(cfg[k], v, k)

    sim = Sim()
    for m in ("addPlayer", "removePlayer", "setInput", "step", "popEvents", "getCell"):
        assert sim.H.typeOf(sim.g, m) == "function", m
    assert sim.phase == "waiting"
    sim.step()
    assert sim.phase == "waiting"
    assert sim.pop() == []
    # popEvents ล้างคิว
    sim.add(1)
    sim.step()
    assert sim.phase == "intro"
    assert sim.pop() == []
    for (i, j) in [(-1, 0), (0, -1), (52, 0), (0, 52), (100, -100)]:
        assert sim.get_cell(i, j) == STEEL, (i, j)
    assert sim.get_cell(0, 0) == EMPTY and sim.get_cell(24, 48) == BASE


def test_config_override_does_not_leak_between_games():
    a = Sim(config=quiet(PLAYER_SPEED=24))
    assert a.Core.DEFAULT_CONFIG.PLAYER_SPEED == 48
    assert luaenv.load_file(a.lua, CORE_PATH).DEFAULT_CONFIG.PLAYER_SPEED == 48
    a.start()
    a.set_input(1, UP)
    a.run(1.0)
    assert abs((192 - a.ptank(1).y) - 24) <= 0.4 + EPS
    # เกมที่สองใน runtime เดียวกัน ไม่ได้รับผลจาก override ของเกมแรก
    g2 = a.Core.new(a.lua_value({"stages": [{"name": "X", "map": make_layout(), "enemies": "b" * 20}],
                                 "config": {"INTRO_TIME": 0.05, "MAX_ENEMIES": [0, 0]}}))
    a.H.call(g2, "addPlayer", 1)
    for _ in range(70):
        a.H.call(g2, "step", TICK)
    tank = None
    for k in range(1, len(g2.tanks) + 1):
        if g2.tanks[k].team == "player":
            tank = g2.tanks[k]
    assert tank is not None
    a.H.call(g2, "setInput", 1, UP, False)
    for _ in range(60):
        a.H.call(g2, "step", TICK)
    assert abs((192 - tank.y) - 48) <= 0.8 + EPS


def test_stage_load_layout_mapping_and_forced_cells():
    cells = {}
    for cx in range(26):
        cells[(cx, 5)] = ".BSWTI"[cx % 6]
        cells[(cx, 6)] = "IWTBS."[cx % 6]
        cells[(cx, 20)] = "TTII.."[cx % 6]
    # ช่องตายตัวใส่ของผิดไว้ก่อน — core ต้องบังคับทับเอง
    lay = make_layout(fill="S", cells=cells, fixed=False)
    sim = Sim(layout=lay, name="Mapping", config=quiet())
    sim.add(1)
    sim.step()
    assert sim.phase == "intro"
    grid = sim.grid()
    assert len(grid) == GN * GN
    for j in range(GN):
        for i in range(GN):
            c = (i // 2, j // 2)
            if c in BASE_CELLS:
                exp = BASE
            elif c in RING_CELLS:
                exp = BRICK
            elif c in SPAWN_CELLS:
                exp = EMPTY
            else:
                exp = CHAR_KIND[lay[c[1]][c[0]]]
            assert grid[j * GN + i] == exp, "micro (%d,%d) cell %s" % (i, j, c)
    for (i, j) in [(0, 0), (10, 10), (24, 48), (23, 47), (16, 48), (51, 51), (5, 40)]:
        assert sim.get_cell(i, j) == grid[j * GN + i]
    st = sim.events("stage")
    assert len(st) == 1 and st[0]["stageNumber"] == 1 and st[0]["name"] == "Mapping"
    assert sim.g.stageName == "Mapping" and sim.g.stageNumber == 1
    assert [e["phase"] for e in sim.events("phase")] == ["intro"]
    assert sim.g.enemiesInReserve == 20 and sim.g.enemiesSpawned == 0
    p = sim.player(1)
    assert p.slot == 1 and p.lives == 2 and p.score == 0 and p.level == 0
    assert p.out is False and p.bonusLifeGiven is False and p.tankId is None
    assert sim.kills(1) == [0, 0, 0, 0]
    assert sim.tanks() == [] and sim.bullets() == [] and sim.spawns() == []
    assert sim.g.powerup is None
    assert sim.g.baseDestroyed is False and sim.g.isGameOver is False


def test_stages_wrap_and_level_score_kept_kills_reset():
    stages = [
        {"name": "Alpha", "map": make_layout(cells={(0, 10): "B"}), "enemies": "b" * 20},
        {"name": "Beta", "map": make_layout(cells={(0, 10): "S"}), "enemies": "f" * 20},
    ]
    sim = Sim(stages=stages, config=quiet(STAGE_CLEAR_DELAY=0.05, TALLY_TIME=0.05))
    sim.start()
    assert sim.g.stageName == "Alpha" and sim.cell(0, 20) == BRICK
    sim.set_cell(0, 20, EMPTY)  # ยิงอิฐหายไปแล้ว ต้องกลับมาตอนโหลดด่านใหม่
    sim.player(1).level = 2
    sim.ptank(1).level = 2
    sim.player(1).score = 1200
    sim.set_kills(1, [1, 0, 0, 0])
    for number, name, kind in [(2, "Beta", STEEL), (3, "Alpha", BRICK)]:
        sim.clear_stage()
        sim.run_until(lambda: sim.phase == "intro" and sim.g.stageNumber == number, 2, "stage %d" % number)
        assert sim.g.stageName == name
        assert sim.cell(0, 20) == kind
        assert sim.kills(1) == [0, 0, 0, 0]
        assert sim.ptank(1) is None
        sim.run_until(lambda: sim.ptank(1) is not None, 3, "respawn")
        assert sim.ptank(1).level == 2 and sim.player(1).level == 2
        assert sim.player(1).score == 1200 and sim.player(1).lives == 2
    st = [(e["stageNumber"], e["name"]) for e in sim.events("stage")]
    assert st == [(1, "Alpha"), (2, "Beta"), (3, "Alpha")]


# ---------------------------------------------------------------- phases

def test_phase_flow_stage_clear_with_default_timings():
    sim = Sim(config={"MAX_ENEMIES": [0, 0]})
    assert sim.phase == "waiting"
    sim.add(1)
    t_add = sim.tick
    sim.step()
    assert sim.phase == "intro" and sim.g.stageNumber == 1
    sim.run_until(lambda: sim.phase == "playing", 4)
    assert abs((sim.tick - t_add) - 150) <= 2  # INTRO_TIME 2.5 s
    assert sim.g.phaseTime < 3 * TICK
    sp = sim.player_spawn(1)
    assert sp is not None and (sp.x, sp.y) == (64, 192)
    assert sp.kind == "player" and 1.0 - 3 * TICK <= sp.t <= 1.0 + EPS
    assert sim.ptank(1) is None
    t_play = sim.tick
    sim.run_until(lambda: sim.ptank(1) is not None, 2)
    assert abs((sim.tick - t_play) - 60) <= 2  # SPAWN_ANIM_TIME
    t = sim.ptank(1)
    assert t.dir == UP and t.kind == "player" and t.team == "player" and t.slot == 1
    assert (t.x, t.y) == (64, 192)
    assert 3 - 3 * TICK <= t.shield <= 3 + EPS
    assert t.level == 0 and t.bullets == 0 and t.frozen == 0 and t.moving is False
    assert sim.player(1).tankId == t.id
    assert sim.player_spawn(1) is None
    s0 = t.shield
    sim.run(1.5)
    assert abs(t.shield - (s0 - 1.5)) <= 2 * TICK
    sim.run(1.6)
    assert 0 <= t.shield < EPS
    assert close(sim.g.time, sim.tick * TICK, 1e-6)

    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "stageClear", 3 * TICK)
    t_sc = sim.tick
    # stageClear: ผู้เล่นยังขยับได้
    y0 = t.y
    sim.set_input(1, UP)
    sim.run(0.5)
    assert t.y < y0 - 20
    sim.set_input(1, -1)
    sim.run_until(lambda: sim.phase == "tally", 4)
    assert abs((sim.tick - t_sc) - 180) <= 2
    t_t = sim.tick
    T = sim.g.tally
    assert T.stageNumber == 1 and T.gameOver is False
    assert kills_list(luaenv.to_py(T.players[1].kills)) == [0, 0, 0, 0]
    # tally: อินพุตถูกเมิน
    if sim.ptank(1) is not None:
        y1 = sim.ptank(1).y
        sim.set_input(1, UP, True)
        sim.run(0.5)
        assert sim.ptank(1) is None or sim.ptank(1).y == y1
        sim.set_input(1, -1, False)
    sim.run_until(lambda: sim.phase == "intro", 7)
    assert abs((sim.tick - t_t) - 360) <= 2
    assert sim.g.stageNumber == 2
    assert [e["phase"] for e in sim.events("phase")] == ["intro", "playing", "stageClear", "tally", "intro"]
    assert [e["stageNumber"] for e in sim.events("stage")] == [1, 2]


def test_base_destroyed_gameover_tally_final_new_game_default_timings():
    sim = Sim(config={"MAX_ENEMIES": [0, 0]})
    sim.start()
    sim.set_input(1, RIGHT, True)
    t0 = sim.tick
    sim.run_until(lambda: sim.g.baseDestroyed, 10, "base destroyed")
    t_go = sim.tick
    sim.run_until(lambda: sim.phase == "gameOver", 2 * TICK)
    assert sim.g.isGameOver is True
    assert len(sim.events("baseDestroyed", t0)) == 1
    big = [e for e in sim.events("explosion", t0) if e["big"]]
    assert len(big) == 1 and close(big[0]["x"], 104, 0.5) and close(big[0]["y"], 200, 0.5)
    for (i, j) in BASE_MICRO:
        assert sim.cell(i, j) == BASE
    # กระสุน 2 นัดแรกเจาะแหวนอิฐทีละ 1 micro (แถบ 4 ช่อง), นัดที่สามโดนฐาน
    for i in (22, 23):
        for j in range(48, 52):
            assert sim.cell(i, j) == EMPTY
        for j in (46, 47):
            assert sim.cell(i, j) == BRICK
    assert [h["what"] for h in sim.events("hit", t0)][:2] == ["brick", "brick"]
    assert sim.player(1).score == 0
    # gameOver: อินพุตผู้เล่นถูกเมิน
    p = sim.ptank(1)
    pos = (p.x, p.y)
    t1 = sim.tick
    sim.set_input(1, UP, True)
    sim.run(0.5)
    assert (p.x, p.y) == pos
    assert not [e for e in sim.events("fire", t1) if e.get("slot") == 1]
    sim.set_input(1, -1, False)
    sim.player(1).score = 123400
    sim.run_until(lambda: sim.phase == "tally", 5)
    assert abs((sim.tick - t_go) - 240) <= 2
    T = sim.g.tally
    assert T.gameOver is True and T.stageNumber == 1
    assert (T.players[1].bonus or 0) == 0
    assert sim.g.hiScore == 123400
    assert sim.g.isGameOver is True
    t_t = sim.tick
    sim.run_until(lambda: sim.phase == "final", 7)
    assert abs((sim.tick - t_t) - 360) <= 2
    assert sim.g.isGameOver is True
    t_f = sim.tick
    sim.run_until(lambda: sim.phase == "intro", 4)
    assert abs((sim.tick - t_f) - 180) <= 2
    assert [e["phase"] for e in sim.events("phase")] == ["intro", "playing", "gameOver", "tally", "final", "intro"]
    # เกมใหม่
    p = sim.player(1)
    assert sim.g.stageNumber == 1 and p.lives == 2 and p.score == 0 and p.level == 0
    assert p.out is False and p.bonusLifeGiven is False
    assert sim.g.isGameOver is False and sim.g.baseDestroyed is False
    assert sim.g.hiScore == 123400
    for (i, j) in RING_MICRO:
        assert sim.cell(i, j) == BRICK
    assert sim.g.enemiesInReserve == 20


def test_player_death_respawn_level_reset_and_out_gameover():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    sim.player(1).level = 2
    sim.ptank(1).level = 2
    t0 = sim.enemy_kills_player(1)
    died = sim.events("playerDied", t0)
    assert len(died) == 1 and died[0]["slot"] == 1
    big = [e for e in sim.events("explosion", t0) if e["big"]]
    assert len(big) == 1 and close(big[0]["x"], 72, 4) and close(big[0]["y"], 200, 4)
    p = sim.player(1)
    assert sim.ptank(1) is None and p.tankId is None
    assert p.lives == 1 and p.level == 0 and p.out is False
    assert 0 < p.respawnTimer <= 0.5 + EPS
    t_d = sim.tick
    sim.run_until(lambda: sim.player_spawn(1) is not None, 1)
    assert abs((sim.tick - t_d) - 30) <= 2  # RESPAWN_DELAY
    sp = sim.player_spawn(1)
    assert (sp.x, sp.y) == (64, 192)
    sim.run_until(lambda: sim.ptank(1) is not None, 2)
    assert abs((sim.tick - t_d) - 90) <= 3
    t = sim.ptank(1)
    assert t.level == 0 and 3 - 3 * TICK <= t.shield <= 3 + EPS and t.dir == UP
    # ชีวิตหมด -> out -> ผู้เล่นคนเดียว = gameOver
    p.lives = 0
    t1 = sim.enemy_kills_player(1)
    assert p.out is True and p.lives == 0
    sim.run_until(lambda: sim.phase == "gameOver", 3 * TICK)
    assert sim.g.isGameOver is True and sim.g.baseDestroyed is False
    assert sim.player_spawn(1) is None
    # gameOver: ศัตรูยังทำงานต่อ
    e = sim.enemies()[0]
    y_e = e.y
    sim.unfreeze_enemies()
    sim.run(1.0)
    assert e.y != y_e
    assert sim.ptank(1) is None and sim.player_spawn(1) is None
    assert len(sim.events("playerDied", t1)) == 1


def test_one_player_out_game_continues_in_2p():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(slots=(1, 2), freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    sim.player(1).lives = 0
    sim.enemy_kills_player(1)
    assert sim.player(1).out is True
    sim.run(1.0)
    assert sim.phase == "playing"
    assert sim.ptank(2) is not None and sim.ptank(1) is None and sim.player_spawn(1) is None
    sim.player(2).lives = 0
    sim.enemy_kills_player(2)
    sim.run_until(lambda: sim.phase == "gameOver", 3 * TICK)


def test_stage_clear_waits_for_pending_enemy_spawn_animation():
    sim = Sim(config=arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000))
    sim.add(1)
    sim.run_until(lambda: sim.enemy_spawns(), 2)
    sim.g.enemiesInReserve = 0
    sim.run(0.5)
    assert sim.phase == "playing"  # ยังมีศัตรูกำลังเกิด
    sim.run_until(lambda: sim.enemies(), 1)
    sim.run(0.2)
    assert sim.phase == "playing"
    sim.remove_tank(sim.enemies()[0].id)
    sim.run_until(lambda: sim.phase == "stageClear", 3 * TICK)


def test_enemies_keep_spawning_during_game_over():
    sim = Sim(config=arena(MAX_ENEMIES=[4, 4], GAMEOVER_TIME=5))
    sim.start()
    sim.set_input(1, RIGHT, True)
    sim.run_until(lambda: sim.phase == "gameOver", 10)
    sim.set_input(1, -1, False)
    sim.clear_stage()
    sim.g.enemiesInReserve = 10
    n0 = sim.g.enemiesSpawned
    sim.run(2.5)
    assert sim.phase == "gameOver"
    assert sim.g.enemiesSpawned >= n0 + 2


def test_moving_flag_false_in_phases_without_simulation():
    sim = Sim(config=quiet(STAGE_CLEAR_DELAY=0.5, TALLY_TIME=2))
    sim.start()
    sim.set_input(1, UP)
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "stageClear", 3 * TICK)
    sim.run(0.2)
    assert sim.ptank(1).moving is True
    sim.run_until(lambda: sim.phase == "tally", 1)
    sim.step(n=2)
    t = sim.ptank(1)
    assert t is None or t.moving is False  # tick นี้ไม่ได้ขยับ


# ---------------------------------------------------------------- movement

def test_player_movement_speed_and_bounds():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    sim.set_input(1, UP)
    sim.run(1.0)
    assert close(p.x, 64)
    assert abs(p.y - 144) <= 0.8 + EPS
    assert p.moving is True and p.dir == UP
    sim.set_input(1, -1)
    sim.step()
    y = p.y
    sim.run(0.5)
    assert p.y == y and p.moving is False
    # ขอบสนาม 0..192
    sim.set_input(1, UP)
    sim.run(4)
    assert close(p.y, 0)
    assert p.moving is False
    sim.set_input(1, LEFT)
    sim.run(2)
    assert close(p.x, 0) and close(p.y, 0)
    sim.set_input(1, RIGHT)
    sim.run(5)
    assert close(p.x, 192)
    sim.set_input(1, DOWN)
    sim.run(5)
    assert close(p.x, 192) and close(p.y, 192)
    assert p.dir == DOWN


def test_large_dt_matches_fixed_ticks():
    a = Sim(config=quiet())
    a.start()
    b = Sim(config=quiet())
    b.start()
    a.set_input(1, UP)
    b.set_input(1, UP)
    a.run(1.0)
    for _ in range(30):
        b.step(1.0 / 30)
    assert close(a.ptank(1).y, b.ptank(1).y, 1e-6)
    assert abs(b.ptank(1).y - 144) <= 0.8 + EPS


def test_enemy_speeds_and_enemy_bullet_speeds():
    cfg = arena(MAX_ENEMIES=[4, 4], AI_FIRE_RATE=1000)
    sim = Sim(config=cfg, enemies="bfpa" * 5)
    sim.start(freeze=True, park=True)
    sim.run_until(lambda: len(sim.enemies()) == 4, 6)
    p = sim.ptank(1)
    p.x, p.y = 96, 96  # ให้พ้นแนวยิงของศัตรูทุกตัว
    exp_speed = {"basic": 32, "fast": 80, "power": 48, "armor": 48}
    exp_bullet = {"basic": 120, "fast": 180, "power": 240, "armor": 180}
    xs = [0, 32, 136, 176]
    by_kind = {}
    for e, x in zip(sim.enemies(), xs):
        e.x, e.y, e.dir = x, 16, DOWN
        by_kind[e.kind] = e
    assert set(by_kind) == set(exp_speed)
    sim.unfreeze_enemies()
    sim.run(0.5)
    for kind, e in by_kind.items():
        assert abs((e.y - 16) - exp_speed[kind] * 0.5) <= exp_speed[kind] * TICK + EPS, kind
        assert e.dir == DOWN
    for kind, e in by_kind.items():
        mine = [b for b in sim.bullets() if b.ownerId == e.id]
        assert len(mine) == 1, kind
        b = mine[0]
        assert b.speed == exp_bullet[kind] and b.team == "enemy" and b.dir == DOWN and b.power is False
        assert b.slot is None
        y0 = b.y
        bid = b.id
        sim.step()
        b2 = [x for x in sim.bullets() if x.id == bid]
        if b2:
            assert close(b2[0].y - y0, exp_bullet[kind] * TICK, 1e-6), kind


def test_tank_stops_flush_at_4px_brick_boundary():
    sim = Sim(config=quiet(PLAYER_SPEED=50))  # 0.8333 px/tick ไม่ลงตัวกับ 4 px
    sim.start()
    p = sim.ptank(1)

    def drive_up(cols):
        sim.set_input(1, -1)
        for i in range(14, 22):
            sim.set_cell(i, 20, EMPTY)
        for i in cols:
            sim.set_cell(i, 20, BRICK)  # แถว micro 20 = px 80..84
        p.x, p.y, p.dir = 64, 120, UP
        sim.set_input(1, UP)
        sim.run(1.5)
        sim.set_input(1, -1)
        return p.y

    assert close(drive_up(range(16, 20)), 84)
    assert p.moving is False or close(p.y, 84)
    assert close(drive_up([19]), 84)   # ทับแค่ขอบขวา 4px ก็ชน
    assert close(drive_up([16]), 84)
    assert drive_up([20]) < 60          # px 80..84 ไม่ทับรถถัง x 64..80
    assert drive_up([15]) < 60
    # แนวนอน: อิฐคอลัมน์ micro 30 = px 120..124
    for j in range(22, 30):
        sim.set_cell(30, j, BRICK)
    p.x, p.y, p.dir = 40, 96, RIGHT
    sim.set_input(1, RIGHT)
    sim.run(2)
    assert close(p.x, 104)
    # ถอยหลังห่างออกมาได้ปกติ
    sim.set_input(1, LEFT)
    sim.run(0.5)
    assert abs(p.x - (104 - 25)) <= 0.9


def test_tank_overlapping_steel_can_drive_out():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    for i in range(16, 20):
        for j in range(24, 28):
            sim.set_cell(i, j, STEEL)
    cases = [(UP, UP, (64, 72)), (UP, DOWN, (64, 120)), (UP, LEFT, (40, 96)), (LEFT, RIGHT, (88, 96))]
    for start_dir, d, (ex, ey) in cases:
        sim.set_input(1, -1)
        p.x, p.y, p.dir = 64, 96, start_dir
        sim.set_input(1, d)
        sim.run(0.5)
        assert abs(p.x - ex) <= 0.8 + EPS and abs(p.y - ey) <= 0.8 + EPS, (start_dir, d, p.x, p.y)
    # ถ้าข้างหน้ายังเป็นเหล็ก (ช่องที่เพิ่งเข้าใหม่) ต้องขยับไม่ได้
    sim.set_input(1, -1)
    for i in range(16, 20):
        for j in range(20, 24):
            sim.set_cell(i, j, STEEL)
    p.x, p.y, p.dir = 64, 96, UP
    sim.set_input(1, UP)
    sim.run(0.5)
    assert close(p.y, 96) and close(p.x, 64)


def test_turn_snapping_fallback_and_reverse():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000)
    sim = Sim(config=cfg)
    sim.start(slots=(1, 2), freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    p1, p2, e = sim.ptank(1), sim.ptank(2), sim.enemies()[0]
    e.x, e.y = 176, 40
    v = 48 * TICK

    def turn(x, y, d0, d):
        sim.set_input(1, -1)
        p1.x, p1.y, p1.dir = x, y, d0
        sim.set_input(1, d)
        sim.step()
        sim.set_input(1, -1)
        return p1.x, p1.y, p1.dir

    # ตั้งฉาก: snap แกนเดิมไปพหุคูณ 8 ที่ใกล้สุด แล้วเดินในติ๊กเดียวกัน
    x, y, d = turn(64, 181, UP, LEFT)
    assert close(y, 184) and close(x, 64 - v) and d == LEFT
    x, y, d = turn(67, 100, RIGHT, UP)
    assert close(x, 64) and close(y, 100 - v) and d == UP
    x, y, d = turn(69, 100, RIGHT, DOWN)
    assert close(x, 72) and close(y, 100 + v) and d == DOWN
    # กลับหลัง 180 องศา ไม่ snap
    x, y, d = turn(64, 181, UP, DOWN)
    assert close(y, 181 + v) and close(x, 64) and d == DOWN
    x, y, d = turn(67, 100, RIGHT, LEFT)
    assert close(x, 67 - v) and close(y, 100) and d == LEFT
    # ค่าที่ใกล้สุดชนรถถังคันอื่น (ชนใหม่) -> ใช้พหุคูณอีกข้าง
    p2.x, p2.y = 40, 118
    x, y, d = turn(40, 101, UP, LEFT)
    assert close(y, 96) and close(x, 40 - v) and d == LEFT
    # ชนทั้งสองข้าง -> คงค่าเดิม
    e.x, e.y = 40, 84
    x, y, d = turn(40, 101, UP, LEFT)
    assert close(y, 101) and close(x, 40 - v) and d == LEFT


def test_tank_tank_blocking_and_separation():
    sim = Sim(config=quiet())
    sim.start(slots=(1, 2))
    p1, p2 = sim.ptank(1), sim.ptank(2)
    p1.x, p1.y, p1.dir = 16, 96, RIGHT
    p2.x, p2.y, p2.dir = 64, 96, UP
    sim.set_input(1, RIGHT)
    sim.run(1.5)
    assert 47.2 - EPS <= p1.x <= 48 + EPS and close(p1.y, 96)
    assert (p2.x, p2.y) == (64, 96)
    assert p1.moving is False
    # ผู้เล่น 2 ขับชนจากอีกด้าน ก็ถูกบล็อกเหมือนกัน
    sim.set_input(1, -1)
    p2.dir = LEFT
    sim.set_input(2, LEFT)
    sim.run(0.5)
    assert p2.x >= p1.x + 16 - EPS
    sim.set_input(2, -1)
    # รถถังที่ทับกันอยู่แล้วแยกออกจากกันได้
    p1.x, p1.y, p1.dir = 40, 96, LEFT
    p2.x, p2.y, p2.dir = 48, 96, RIGHT
    sim.set_input(1, LEFT)
    sim.set_input(2, RIGHT)
    sim.run(0.5)
    assert abs(p1.x - 16) <= 0.8 + EPS and abs(p2.x - 72) <= 0.8 + EPS


def test_trees_and_ice_do_not_block_tanks_water_does():
    sim = Sim(layout=make_layout(rows={20: "T", 18: "I", 14: "W"}), config=quiet())
    sim.start()
    p = sim.ptank(1)
    sim.set_input(1, UP)
    sim.run(3)
    assert close(p.y, 120)  # ผ่านป่า + น้ำแข็ง แล้วหยุดชิดน้ำ (ขอบล่างน้ำ = 120)


@pytest.mark.parametrize("ice_col,slides", [(8, False), (9, True)])
def test_on_ice_is_judged_at_tank_center(ice_col, slides):
    # รถถัง x=64..80: ช่อง 8px คอลัมน์ 8 อยู่ใต้มุมซ้าย, คอลัมน์ 9 อยู่ใต้จุดกึ่งกลาง (72)
    lay = make_layout(cells={(ice_col, cy): "I" for cy in range(2, 23)})
    sim = Sim(layout=lay, config=quiet())
    sim.start()
    p = sim.ptank(1)
    sim.set_input(1, UP)
    sim.run(1.0)
    y_rel = p.y
    sim.set_input(1, -1)
    sim.run(1.0)
    if slides:
        assert abs((y_rel - p.y) - 24) <= 0.8 + EPS
    else:
        assert p.y == y_rel


def test_ice_slide_distance_block_and_cancel():
    sim = Sim(layout=make_layout(fill="I"), config=quiet())
    sim.start()
    p = sim.ptank(1)
    sim.set_input(1, UP)
    sim.run(1.0)
    y_rel = p.y
    assert abs(y_rel - 144) <= 0.8 + EPS
    sim.set_input(1, -1)
    sim.run(0.1)
    assert p.moving is True and p.y < y_rel
    sim.run(0.9)
    assert abs((y_rel - p.y) - 24) <= 0.8 + EPS
    assert p.moving is False
    # ไถลแล้วชนอิฐ -> หยุดก่อน
    sim2 = Sim(layout=make_layout(fill="I", cells={(8, 15): "B", (9, 15): "B"}), config=quiet())
    sim2.start()
    q = sim2.ptank(1)
    sim2.set_input(1, UP)
    sim2.run(1.0)
    assert q.y > 128
    sim2.set_input(1, -1)
    sim2.run(1.0)
    assert close(q.y, 128)
    # ไถลอยู่แล้วกดทิศใหม่ = ยกเลิกการไถล
    sim3 = Sim(layout=make_layout(fill="I"), config=quiet())
    sim3.start()
    r = sim3.ptank(1)
    sim3.set_input(1, UP)
    sim3.run(1.0)
    y_rel = r.y
    sim3.set_input(1, -1)
    sim3.step(n=3)
    y_mid = r.y
    assert y_mid < y_rel
    sim3.set_input(1, DOWN)
    sim3.run(0.5)
    assert r.y > y_mid + 20 and r.dir == DOWN
    # ไม่ได้อยู่บนน้ำแข็ง -> หยุดทันที
    sim4 = Sim(config=quiet())
    sim4.start()
    s = sim4.ptank(1)
    sim4.set_input(1, UP)
    sim4.run(1.0)
    y_rel = s.y
    sim4.set_input(1, -1)
    sim4.run(1.0)
    assert s.y == y_rel


# ---------------------------------------------------------------- firing & bullets

def test_player_fire_limits_speeds_power_and_cooldown():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    expected = {0: (1, 180, False), 1: (1, 240, False), 2: (2, 240, False), 3: (2, 240, True)}
    ids = set()
    for lvl, (maxb, speed, power) in expected.items():
        sim.set_input(1, -1, False)
        sim.wait_player_bullets_gone(1)
        sim.player(1).level = lvl
        p.level = lvl
        t0 = sim.tick
        sim.set_input(1, -1, True)
        max_seen = 0
        first = None
        for _ in range(30):
            sim.step()
            mine = [b for b in sim.bullets() if b.ownerId == p.id]
            max_seen = max(max_seen, len(mine))
            assert p.bullets == len(mine)
            if first is None and mine:
                first = mine[0]
                assert first.x == 72 and first.dir == UP and first.team == "player" and first.slot == 1
                assert first.speed == speed and first.power is power
                assert 194 - speed * TICK - EPS <= first.y <= 194 + EPS
                ids.add(first.id)
        assert max_seen == maxb, lvl
        fires = [(t, e) for (t, e) in sim.log if t > t0 and e.get("type") == "fire"]
        assert len(fires) == maxb, lvl
        assert all(e["team"] == "player" and e["slot"] == 1 for _, e in fires)
        if maxb == 2:
            gap = fires[1][0] - fires[0][0]
            assert 7 <= gap <= 9, gap  # FIRE_COOLDOWN 0.12 s
        live = [b for b in sim.bullets() if b.id == first.id]
        if live:
            y1 = live[0].y
            sim.step()
            live = [b for b in sim.bullets() if b.id == first.id]
            if live:
                assert close(y1 - live[0].y, speed * TICK, 1e-6)
    # ถือปุ่มค้าง = ยิงอัตโนมัติเมื่อกระสุนเก่าหายไป
    sim.set_input(1, -1, False)
    sim.wait_player_bullets_gone(1)
    sim.player(1).level = 0
    p.level = 0
    t0 = sim.tick
    sim.set_input(1, -1, True)
    sim.run(2.5)
    assert len(sim.events("fire", t0)) >= 2
    sim.set_input(1, -1, False)
    sim.wait_player_bullets_gone(1)
    assert p.bullets == 0


def test_bullet_vs_brick_strip_vertical():
    sim = Sim(layout=make_layout(rows={10: "B"}), config=quiet())
    sim.start()
    p = sim.ptank(1)
    p.x, p.y, p.dir = 64, 120, UP
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    for i in range(GN):
        assert sim.cell(i, 21) == (EMPTY if 16 <= i <= 19 else BRICK), i
        assert sim.cell(i, 20) == BRICK, i
    cells = sorted((e["i"], e["j"], e["kind"]) for e in sim.events("cell", t0))
    assert cells == [(i, 21, EMPTY) for i in range(16, 20)]
    assert [h["what"] for h in sim.events("hit", t0)] == ["brick"]
    ex = sim.events("explosion", t0)
    assert len(ex) == 1 and ex[0]["big"] is False
    assert close(ex[0]["x"], 72, 2.01) and 80 <= ex[0]["y"] <= 92
    assert sim.shadow == sim.grid()
    # นัดสอง: แถวถัดไป
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    for i in range(GN):
        assert sim.cell(i, 20) == (EMPTY if 16 <= i <= 19 else BRICK), i
    assert [h["what"] for h in sim.events("hit", t1)] == ["brick"]
    # นัดสาม: ทะลุช่องว่างไปชนขอบ
    t2 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert [h["what"] for h in sim.events("hit", t2)] == ["border"]
    assert sim.shadow == sim.grid()


def test_frontmost_row_is_first_met_when_two_rows_overlap():
    # รถถังทับอิฐอยู่ (เช่นแหวนพลั่วกะพริบกลับเป็นอิฐใต้รถ) กล่องกระสุนจะทับอิฐสองแถวพร้อมกัน
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    for j in (20, 21, 22):
        for i in range(16, 20):
            sim.set_cell(i, j, BRICK)
    sim.resync_shadow()
    p.x, p.y, p.dir = 64, 88, UP
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    got = sorted((e["i"], e["j"], e["kind"]) for e in sim.events("cell", t0))
    assert got == [(i, 22, EMPTY) for i in range(16, 20)]  # แถวที่กระสุนเจอก่อน (ใกล้คนยิง)
    for i in range(16, 20):
        assert sim.cell(i, 21) == BRICK and sim.cell(i, 20) == BRICK


def test_bullet_vs_brick_strip_horizontal():
    sim = Sim(layout=make_layout(cells={(20, cy): "B" for cy in range(2, 23)}), config=quiet())
    sim.start()
    p = sim.ptank(1)
    p.x, p.y, p.dir = 64, 96, RIGHT
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    for j in range(4, 46):
        assert sim.cell(40, j) == (EMPTY if 24 <= j <= 27 else BRICK), j
        assert sim.cell(41, j) == BRICK, j
    cells = sorted((e["i"], e["j"], e["kind"]) for e in sim.events("cell", t0))
    assert cells == [(40, j, EMPTY) for j in range(24, 28)]


def test_brick_strip_with_gap_and_mixed_steel_power():
    lay = make_layout(rows={10: "B"}, cells={(9, 10): "S"})
    sim = Sim(layout=lay, config=quiet())
    sim.start()
    p = sim.ptank(1)
    p.x, p.y, p.dir = 64, 120, UP
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    # ไม่มีพลัง: อิฐในแถบหาย เหล็กอยู่, hit = brick
    assert sorted((e["i"], e["j"], e["kind"]) for e in sim.events("cell", t0)) == [(16, 21, EMPTY), (17, 21, EMPTY)]
    assert [h["what"] for h in sim.events("hit", t0)] == ["brick"]
    for i in (18, 19):
        for j in (20, 21):
            assert sim.cell(i, j) == STEEL
    # ระดับ 3 (power): เหล็กหายทั้งบล็อก 8px, อิฐแถวหลังยังอยู่, hit = steel
    sim.player(1).level = 3
    p.level = 3
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    got = sorted((e["i"], e["j"], e["kind"]) for e in sim.events("cell", t1))
    assert got == sorted((i, j, EMPTY) for i in (18, 19) for j in (20, 21))
    assert [h["what"] for h in sim.events("hit", t1)] == ["steel"]
    assert sim.cell(16, 20) == BRICK and sim.cell(17, 20) == BRICK
    assert sim.cell(20, 21) == BRICK and sim.cell(15, 21) == BRICK


def test_steel_blocks_without_power_and_breaks_whole_cell_with_power():
    sim = Sim(layout=make_layout(rows={10: "S"}), config=quiet())
    sim.start()
    p = sim.ptank(1)
    p.x, p.y, p.dir = 64, 120, UP
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert sim.events("cell", t0) == []
    assert [h["what"] for h in sim.events("hit", t0)] == ["steel"]
    ex = sim.events("explosion", t0)
    assert len(ex) == 1 and ex[0]["big"] is False
    for i in range(GN):
        assert sim.cell(i, 20) == STEEL and sim.cell(i, 21) == STEEL
    sim.player(1).level = 3
    p.level = 3
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    for i in range(GN):
        for j in (20, 21):
            assert sim.cell(i, j) == (EMPTY if 16 <= i <= 19 else STEEL), (i, j)
    assert len(sim.events("cell", t1)) == 8
    assert [h["what"] for h in sim.events("hit", t1)] == ["steel"]
    assert sim.shadow == sim.grid()


def test_bullets_fly_over_water_ice_and_under_trees():
    lay = make_layout(rows={14: "W", 13: "T", 12: "I", 8: "B"})
    sim = Sim(layout=lay, config=quiet())
    sim.start()
    p = sim.ptank(1)
    p.x, p.y, p.dir = 64, 128, UP
    before = sim.grid()
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    after = sim.grid()
    changed = sorted((k % GN, k // GN) for k in range(GN * GN) if before[k] != after[k])
    assert changed == [(i, 17) for i in range(16, 20)]
    assert [h["what"] for h in sim.events("hit", t0)] == ["brick"]


def test_bullet_border_hits():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert [h["what"] for h in sim.events("hit", t0)] == ["border"]
    ex = sim.events("explosion", t0)
    assert len(ex) == 1 and ex[0]["big"] is False
    assert close(ex[0]["x"], 72, 0.01) and 0 <= ex[0]["y"] <= 4
    assert p.bullets == 0
    p.x, p.y, p.dir = 176, 96, RIGHT
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    ex = sim.events("explosion", t1)
    assert [h["what"] for h in sim.events("hit", t1)] == ["border"]
    assert len(ex) == 1 and 204 <= ex[0]["x"] <= 208 and close(ex[0]["y"], 104, 0.01)


def test_fast_bullet_with_large_dt_does_not_tunnel():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    for i in range(16, 20):
        sim.set_cell(i, 20, BRICK)
    sim.resync_shadow()
    sim.player(1).level = 1
    p.level = 1
    p.x, p.y, p.dir = 64, 120, UP
    t0 = sim.tick
    sim.set_input(1, -1, True)
    sim.step(1.0 / 30)
    sim.set_input(1, -1, False)
    for _ in range(60):
        sim.step(1.0 / 30)
    assert [h["what"] for h in sim.events("hit", t0)] == ["brick"]
    for i in range(16, 20):
        assert sim.cell(i, 20) == EMPTY


# ---------------------------------------------------------------- enemies

def test_enemy_spawn_cycle_first_immediate_blocked_points_and_max():
    cfg = {"INTRO_TIME": 0.05, "AI_FIRE_RATE": 0, "AI_TURN_CHANCE": 0, "AI_BLOCKED_FIRE_CHANCE": 0}
    sim = Sim(config=cfg, enemies="bfpa" * 5)
    sim.add(1)
    sim.run_until(lambda: sim.phase == "playing", 2)
    t_play = sim.tick
    sim.freeze_enemies()
    sim.track_spawns()
    sim.run_until(lambda: len(sim.seen_spawns) >= 1, TICK)
    s = sim.seen_spawns
    assert (s[0]["x"], s[0]["y"]) == (96, 0) and s[0]["tick"] - t_play <= 1
    assert s[0]["kind"] == "basic" and s[0]["bonus"] is False
    assert sim.g.enemiesInReserve == 19 and sim.g.enemiesSpawned == 1
    assert sim.g.maxEnemiesOnField == 4
    sim.run(7)
    assert [(x["x"], x["y"]) for x in s[:3]] == ENEMY_SPAWN_PX
    assert [x["kind"] for x in s[:3]] == ["basic", "fast", "power"]
    assert abs((s[1]["tick"] - s[0]["tick"]) - 186) <= 2  # (190-4)/60 s
    assert abs((s[2]["tick"] - s[1]["tick"]) - 186) <= 2
    # จุดเกิดทั้ง 3 มีรถถังแช่แข็งทับอยู่ -> รอ
    sim.run(5)
    assert len(s) == 3 and sim.g.enemiesInReserve == 17
    # ย้ายคันที่ (192,0) ออก -> ข้าม (96,0) ที่ยังถูกบัง ไปเกิดที่ (192,0)
    blocker = [e for e in sim.enemies() if (e.x, e.y) == (192, 0)][0]
    blocker.y = 100
    sim.run_until(lambda: len(s) == 4, 3 * TICK)
    assert (s[3]["x"], s[3]["y"]) == (192, 0) and s[3]["kind"] == "armor" and s[3]["bonus"] is True
    # ครบ 4 คันบนสนามแล้ว (1P) -> ย้ายทุกคันออกก็ไม่เกิดเพิ่ม
    sim.enable_parking()
    sim.run(8)
    assert len(s) == 4 and sim.g.enemiesInReserve == 16 and sim.g.enemiesSpawned == 4
    assert len(sim.enemies()) + len(sim.enemy_spawns()) == 4
    # ลบหนึ่งคัน -> เกิดใหม่ทันที ที่จุดถัดไปในรอบ (0,0)
    sim.remove_tank(sim.enemies()[0].id)
    sim.run_until(lambda: len(s) == 5, 3 * TICK)
    assert (s[4]["x"], s[4]["y"]) == (0, 0) and s[4]["kind"] == "basic"


def test_blocked_spawn_point_is_skipped_in_the_same_tick():
    def second_spawn(block):
        cfg = {"INTRO_TIME": 0.05, "ENEMY_SPAWN_BASE": 150, "AI_FIRE_RATE": 0, "AI_TURN_CHANCE": 0,
               "AI_BLOCKED_FIRE_CHANCE": 0}
        sim = Sim(config=cfg)
        sim.add(1)
        sim.run_until(lambda: sim.phase == "playing", 1)
        sim.freeze_enemies()
        sim.track_spawns()
        sim.enable_parking()
        sim.run_until(lambda: sim.ptank(1) is not None, 2)
        if block:
            p = sim.ptank(1)
            p.x, p.y = 190, 4  # ทับจุดเกิดขวาบน (192,0)
        sim.run_until(lambda: len(sim.seen_spawns) >= 2, 4)
        s = sim.seen_spawns
        return s[1]["tick"] - s[0]["tick"], (s[1]["x"], s[1]["y"])
    gap_free, pos_free = second_spawn(False)
    gap_blocked, pos_blocked = second_spawn(True)
    assert pos_free == (192, 0) and pos_blocked == (0, 0)
    assert gap_blocked == gap_free


@pytest.mark.parametrize("slots,stage,base,expected", [
    ((1,), 1, 190, 186), ((1, 2), 1, 190, 166), ((1,), 1, 30, 60), ((1,), 1, 50, 60), ((1,), 2, 190, 182)])
def test_enemy_spawn_interval_formula(slots, stage, base, expected):
    cfg = {"INTRO_TIME": 0.05, "STAGE_CLEAR_DELAY": 0.05, "TALLY_TIME": 0.05, "ENEMY_SPAWN_BASE": base,
           "AI_FIRE_RATE": 0, "AI_TURN_CHANCE": 0, "AI_BLOCKED_FIRE_CHANCE": 0}
    sim = Sim(config=cfg)
    for sl in slots:
        sim.add(sl)
    sim.run_until(lambda: sim.phase == "playing", 2)
    if stage == 2:
        sim.clear_stage()
        sim.run_until(lambda: sim.phase == "intro" and sim.g.stageNumber == 2, 2)
        sim.run_until(lambda: sim.phase == "playing", 2)
    sim.freeze_enemies()
    sim.track_spawns()
    sim.enable_parking()
    sim.run_until(lambda: len(sim.seen_spawns) >= 2, 5)
    gap = sim.seen_spawns[1]["tick"] - sim.seen_spawns[0]["tick"]
    assert abs(gap - expected) <= 2, gap


@pytest.mark.parametrize("slots,maxe", [((1,), 4), ((1, 2), 6)])
def test_max_enemies_on_field(slots, maxe):
    sim = Sim(config={"INTRO_TIME": 0.05, "ENEMY_SPAWN_BASE": 30, "AI_FIRE_RATE": 0, "AI_TURN_CHANCE": 0,
                      "AI_BLOCKED_FIRE_CHANCE": 0, "SPAWN_ANIM_TIME": 3})
    seen_max = [0]

    def hook():
        seen_max[0] = max(seen_max[0], len(sim.enemies()) + len(sim.enemy_spawns()))
    sim.hooks.append(hook)
    sim.start(slots=slots, freeze=True, park=True, wait_tanks=False)
    sim.run(12)
    assert sim.g.maxEnemiesOnField == maxe
    assert len(sim.enemies()) + len(sim.enemy_spawns()) == maxe
    assert seen_max[0] == maxe
    assert sim.g.enemiesInReserve == 20 - maxe and sim.g.enemiesSpawned == maxe


def test_spawn_kinds_and_bonus_carriers_4_11_18():
    cfg = {"INTRO_TIME": 0.05, "ENEMY_SPAWN_BASE": 30, "MAX_ENEMIES": [20, 20], "AI_FIRE_RATE": 0,
           "AI_TURN_CHANCE": 0, "AI_BLOCKED_FIRE_CHANCE": 0}
    sim = Sim(config=cfg, enemies="bfpa" * 5)
    sim.start(freeze=True, park=True, track=True, wait_tanks=False)
    sim.run_until(lambda: sim.g.enemiesInReserve == 0 and len(sim.enemies()) == 20, 25)
    s = sim.seen_spawns
    names = {"b": "basic", "f": "fast", "p": "power", "a": "armor"}
    assert [x["kind"] for x in s] == [names[c] for c in "bfpa" * 5]
    assert [k + 1 for k, x in enumerate(s) if x["bonus"]] == [4, 11, 18]
    assert [(x["x"], x["y"]) for x in s] == (ENEMY_SPAWN_PX * 7)[:20]
    for k in range(1, 20):
        assert abs((s[k]["tick"] - s[k - 1]["tick"]) - 60) <= 2
    en = sim.enemies()
    assert [k + 1 for k, t in enumerate(en) if t.bonus] == [4, 11, 18]
    for t in en:
        hp = 4 if t.kind == "armor" else 1
        assert t.hp == hp and t.maxHp == hp and t.dir == DOWN and t.team == "enemy" and t.slot is None
    assert sim.g.enemiesSpawned == 20


def test_timer_freezes_enemies_including_new_ones():
    cfg = arena(MAX_ENEMIES=[3, 3], AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) >= 2, 3)
    e1, e2 = sim.enemies()[:2]
    e1.x, e1.y, e1.dir = 0, 40, DOWN
    e2.x, e2.y, e2.dir = 176, 40, DOWN
    sim.unfreeze_enemies()
    sim.give_powerup("timer")
    assert 10 - 2 * TICK <= sim.g.freezeTimer <= 10 + EPS
    t1 = sim.tick
    pos = {}
    for _ in range(int(9.5 * 60)):
        for e in sim.enemies():
            if e.id not in pos:
                pos[e.id] = (e.x, e.y)
            assert (e.x, e.y) == pos[e.id], "enemy moved during freeze"
        sim.step()
    assert len(pos) == 3  # ตัวที่สามเกิดระหว่างหยุดเวลา ก็ต้องนิ่ง
    assert not [e for e in sim.events("fire", t1) if e["team"] == "enemy"]
    t2 = sim.tick
    sim.run(1.0)
    assert any((e.x, e.y) != pos[e.id] for e in sim.enemies() if e.id in pos)
    assert [e for e in sim.events("fire", t2) if e["team"] == "enemy"]


@pytest.mark.parametrize("blocked_fire", [1, 0])
def test_ai_blocked_enemy_turns_and_may_fire(blocked_fire):
    lay = make_layout(rows={5: "S"})  # แถวเหล็ก px y 40..48 ขวางเต็มกว้าง
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_BLOCKED_FIRE_CHANCE=blocked_fire)
    sim = Sim(layout=lay, config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: sim.enemies(), 2)
    e = sim.enemies()[0]
    e.x, e.y, e.dir = 64, 48, UP
    t0 = sim.tick
    sim.unfreeze_enemies()
    sim.step()
    fired = [x for x in sim.events("fire", t0) if x["team"] == "enemy"]
    assert len(fired) == blocked_fire
    sim.run(3)
    assert e.dir != UP or (e.x, e.y) != (64, 48)
    assert (e.x, e.y) != (64, 48)  # เลี้ยวแล้วเดินต่อได้
    if not blocked_fire:
        assert not [x for x in sim.events("fire", t0) if x["team"] == "enemy"]


def test_enemy_bullets_pass_enemy_tanks_and_each_other():
    cfg = arena(MAX_ENEMIES=[2, 2], AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 2, 3)
    p = sim.ptank(1)
    p.x, p.y = 176, 96
    a, b = sim.enemies()
    a.x, a.y, a.dir = 64, 8, DOWN
    b.x, b.y, b.dir = 64, 48, DOWN
    t0 = sim.tick
    sim.unfreeze_enemies()
    sim.step()
    first = [x for x in sim.bullets() if x.ownerId == a.id]
    assert len(first) == 1
    bid = first[0].id
    passed = False
    for _ in range(50):
        sim.step()
        cur = [x for x in sim.bullets() if x.id == bid]
        assert cur, "enemy bullet was stopped by an enemy tank"
        if cur[0].y - 2 > b.y + 16:
            passed = True
            break
    assert passed
    assert b.id in [t.id for t in sim.enemies()] and b.hp == 1
    assert not sim.events("hit", t0) or all(h["what"] == "border" for h in sim.events("hit", t0))
    assert not [e for e in sim.events("explosion", t0) if e["big"]]
    # กระสุนศัตรูสวนกันเอง: ผ่านกันไปได้
    sim.freeze_enemies()
    sim.run_until(lambda: not sim.bullets(), 3)
    a.x, a.y, a.dir = 64, 8, DOWN
    b.x, b.y, b.dir = 64, 150, UP
    sim.unfreeze_enemies()
    sim.step()
    ba = [x for x in sim.bullets() if x.ownerId == a.id]
    bb = [x for x in sim.bullets() if x.ownerId == b.id]
    assert len(ba) == 1 and len(bb) == 1
    ida, idb = ba[0].id, bb[0].id
    crossed = False
    for _ in range(60):
        sim.step()
        cur = {x.id: x for x in sim.bullets()}
        assert ida in cur and idb in cur, "enemy bullets cancelled each other"
        if cur[ida].y > cur[idb].y + 6:
            crossed = True
            break
    assert crossed


# ---------------------------------------------------------------- hits, scores, power-ups

def test_kill_scores_kills_popups_and_armor_hits():
    cfg = arena(MAX_ENEMIES=[1, 1])
    sim = Sim(config=cfg, enemies="bfpa" + "b" * 16)
    sim.start(freeze=True)
    points = {"basic": 100, "fast": 200, "power": 300, "armor": 400}
    total = 0
    for kind in ["basic", "fast", "power", "armor"]:
        sim.run_until(lambda: len(sim.enemies()) == 1, 3)
        e = sim.enemies()[0]
        assert e.kind == kind
        hp = 4 if kind == "armor" else 1
        assert e.hp == hp and e.maxHp == hp and e.dir == DOWN
        eid = e.id
        e.x, e.y = 64, 100
        for shot in range(hp):
            t0 = sim.tick
            sim.fire_once(1)
            sim.wait_player_bullets_gone(1)
            if shot < hp - 1:
                assert e.hp == hp - shot - 1
                assert [h["what"] for h in sim.events("hit", t0)] == ["armor"]
                assert not sim.events("score", t0)
                assert eid in [t.id for t in sim.enemies()]
            else:
                assert eid not in [t.id for t in sim.enemies()]
                sc = sim.events("score", t0)
                assert len(sc) == 1 and sc[0]["points"] == points[kind]
                assert close(sc[0]["x"], 72, 0.01) and close(sc[0]["y"], 108, 0.01)
                big = [x for x in sim.events("explosion", t0) if x["big"]]
                assert len(big) == 1 and close(big[0]["x"], 72, 0.01) and close(big[0]["y"], 108, 0.01)
        total += points[kind]
        assert sim.player(1).score == total
    assert sim.kills(1) == [1, 1, 1, 1]
    assert sim.ptank(1) is not None


@pytest.mark.parametrize("seed", [1, 2, 3, 4, 5])
def test_bonus_carrier_spawns_powerup_and_next_carrier_removes_it(seed):
    cfg = arena(MAX_ENEMIES=[1, 1], BONUS_ENEMIES=[1, 2, 3])
    sim = Sim(config=cfg, seed=seed)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 3)
    e = sim.enemies()[0]
    assert e.bonus is True
    e.x, e.y = 64, 100
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    ps = sim.events("powerupSpawn", t0)
    assert len(ps) == 1 and ps[0]["kind"] in POWERUP_KINDS
    pu = sim.g.powerup
    assert pu is not None and pu.kind == ps[0]["kind"]
    assert pu.x % 8 == 0 and pu.y % 8 == 0 and 0 <= pu.x <= 192 and 0 <= pu.y <= 192
    assert not boxes_overlap(pu.x, pu.y, 16, 96, 192, 16)
    p = sim.ptank(1)
    assert not boxes_overlap(pu.x, pu.y, 16, p.x, p.y, 16)
    assert [x["points"] for x in sim.events("score", t0)] == [100]
    # คันพาหะถัดไปถูกสร้าง -> พาวเวอร์อัปเดิมหายไป
    sim.run_until(lambda: sim.enemy_spawns() or sim.enemies(), 0.2)
    while not sim.enemies():
        assert sim.g.powerup is not None
        sim.step()
        assert sim.tick - t0 < 300
    assert sim.g.powerup is None
    assert sim.enemies()[0].bonus is True
    # มีพาวเวอร์อัปค้างอยู่แล้วยิงพาหะ -> ของใหม่แทนที่ของเดิม
    sim.g.powerup = sim.lua_value({"id": 777777, "kind": "timer", "x": 0, "y": 96})
    e2 = sim.enemies()[0]
    e2.x, e2.y = 64, 100
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert len(sim.events("powerupSpawn", t1)) == 1
    assert sim.g.powerup is not None and sim.g.powerup.id != 777777


def test_powerup_positions_avoid_base_and_player_over_many_rolls():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000)
    sim = Sim(config=cfg, enemies="a" * 20, seed=4321)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    e = sim.enemies()[0]
    e.x, e.y = 64, 100
    p = sim.ptank(1)
    kinds = set()
    for _ in range(400):
        e.hp = 4
        e.bonus = True  # จิ้มให้เป็นพาหะใหม่ทุกนัด เพื่อสุ่มตำแหน่งซ้ำหลายครั้ง
        t0 = sim.tick
        sim.fire_once(1)
        sim.wait_player_bullets_gone(1)
        assert len(sim.events("powerupSpawn", t0)) == 1
        pu = sim.g.powerup
        kinds.add(pu.kind)
        assert pu.x % 8 == 0 and pu.y % 8 == 0 and 0 <= pu.x <= 192 and 0 <= pu.y <= 192
        assert not boxes_overlap(pu.x, pu.y, 16, 96, 192, 16), (pu.x, pu.y)
        assert not boxes_overlap(pu.x, pu.y, 16, p.x, p.y, 16), (pu.x, pu.y)
    assert kinds == POWERUP_KINDS


def test_ai_turns_at_8px_crossings_when_turn_chance_is_one():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_TURN_CHANCE=1)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    e = sim.enemies()[0]
    e.x, e.y, e.dir = 96, 40, DOWN
    sim.unfreeze_enemies()
    dirs = set()
    for _ in range(180):
        sim.step()
        dirs.add(e.dir)
    assert len(dirs) >= 2


def _trapped_enemy_dir_freq(seed, n, skip=0, **overrides):
    """ด่านเหล็กทั้งแผ่น: ศัตรูที่จุดเกิด (96,0) ถูกขังทุกทิศ จึงสุ่มทิศใหม่ทุก tick ให้นับสัดส่วนได้ตรงๆ"""
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, **overrides)
    sim = Sim(layout=make_layout(fill="S"), config=cfg, seed=seed)
    sim.start()
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    e = sim.enemies()[0]
    for _ in range(skip):
        sim.step()
    counts = [0, 0, 0, 0]
    for _ in range(n):
        sim.step()
        counts[int(e.dir)] += 1
    assert (e.x, e.y) == (96, 0)
    return [c / float(n) for c in counts]


def test_ai_base_chance_ramps_with_tank_age():
    # ไม่มีผู้เล่นให้ไล่ (AI_PLAYER_CHANCE=0): ทิศ DOWN = สุ่มได้ DOWN (1/4 ของส่วนสุ่ม) + ไปฐาน
    # คันที่เพิ่งเกิด: ไปฐาน ~0.05 -> DOWN ~ 0.05 + 0.95/4; อายุเกิน AI_BASE_RAMP_TIME: ~0.25 + 0.75/4
    young = _trapped_enemy_dir_freq(5, 240, AI_PLAYER_CHANCE=0, AI_BASE_RAMP_TIME=1000)
    old = _trapped_enemy_dir_freq(5, 3000, skip=int(26 * 60), AI_PLAYER_CHANCE=0)
    assert abs(young[DOWN] - (0.05 + 0.95 / 4)) <= 0.07, young
    assert abs(old[DOWN] - (0.25 + 0.75 / 4)) <= 0.04, old


def test_ai_direction_choice_weights():
    # ตรึงน้ำหนักไว้ที่ 0.5 สุ่ม 4 ทิศ, 0.25 ไปฐาน (dx=0 -> DOWN เสมอ), 0.25 ไปผู้เล่น (DOWN, สุ่ม 30% ใช้แกน x -> LEFT)
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_BASE_CHANCE_START=0.25,
                AI_BASE_CHANCE_MAX=0.25, AI_PLAYER_CHANCE=0.25)
    sim = Sim(layout=make_layout(fill="S"), config=cfg, seed=99)
    sim.start()
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    e = sim.enemies()[0]
    assert (e.x, e.y) == (96, 0)
    counts = [0, 0, 0, 0]
    n = 4000
    for _ in range(n):
        sim.step()
        counts[int(e.dir)] += 1
    assert (e.x, e.y) == (96, 0)
    freq = [c / float(n) for c in counts]
    expect = {DOWN: 0.55, LEFT: 0.20, UP: 0.125, RIGHT: 0.125}
    for d, f in expect.items():
        assert abs(freq[d] - f) <= 0.04, (d, freq)


def test_armor_bonus_carrier_hit_spawns_powerup_and_survives():
    cfg = arena(MAX_ENEMIES=[1, 1], BONUS_ENEMIES=[1])
    sim = Sim(config=cfg, enemies="a" * 20)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 3)
    e = sim.enemies()[0]
    e.x, e.y = 64, 100
    t0 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert len(sim.events("powerupSpawn", t0)) == 1
    assert e.bonus is False and e.hp == 3
    assert [h["what"] for h in sim.events("hit", t0)] == ["armor"]
    t1 = sim.tick
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert sim.events("powerupSpawn", t1) == [] and e.hp == 2


def test_powerup_pickup_star_helmet_tank():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    for expect in (1, 2, 3, 3):
        t0 = sim.give_powerup("star")
        taken = sim.events("powerupTaken", t0)
        assert [(x["kind"], x["slot"]) for x in taken] == [("star", 1)]
        assert [x["points"] for x in sim.events("score", t0)] == [500]
        assert sim.player(1).level == expect and p.level == expect
        assert sim.g.powerup is None
    assert sim.player(1).score == 2000
    # หมวก: shield = max(shield, 10)
    sim.give_powerup("helmet")
    assert 10 - 2 * TICK <= p.shield <= 10 + EPS
    p.shield = 15
    sim.give_powerup("helmet")
    assert 15 - 2 * TICK <= p.shield <= 15 + EPS
    # รถถัง: +1 ชีวิต + extraLife
    lives = sim.player(1).lives
    t0 = sim.give_powerup("tank")
    assert sim.player(1).lives == lives + 1
    assert [x["slot"] for x in sim.events("extraLife", t0)] == [1]
    assert sim.player(1).score == 3500


def test_grenade_kills_enemy_tanks_without_points_and_clears_stage():
    cfg = arena(ENEMIES_PER_STAGE=3, MAX_ENEMIES=[4, 4])
    sim = Sim(config=cfg)
    sim.add(1)
    sim.step()
    assert sim.g.enemiesInReserve == 3
    sim.start(freeze=True, park=True)
    sim.run_until(lambda: len(sim.enemies()) == 3, 5)
    assert sim.g.enemiesInReserve == 0 and sim.g.enemiesSpawned == 3
    t0 = sim.give_powerup("grenade")
    assert sim.enemies() == []
    assert len([e for e in sim.events("explosion", t0) if e["big"]]) == 3
    assert [x["points"] for x in sim.events("score", t0)] == [500]
    assert sim.player(1).score == 500 and sim.kills(1) == [0, 0, 0, 0]
    assert sim.ptank(1) is not None
    sim.run_until(lambda: sim.phase == "stageClear", 3 * TICK)


def test_shovel_timeline_steel_flash_and_restore():
    sim = Sim(config=quiet())
    sim.start()
    sim.set_cell(22, 46, EMPTY)  # แหวนแหว่งไปหนึ่ง micro ก่อนเก็บพลั่ว
    sim.resync_shadow()
    t0 = sim.give_powerup("shovel")
    t_pick = sim.tick
    assert ring_state(sim) == "S"
    assert 20 - 2 * TICK <= sim.g.shovelTimer <= 20 + EPS
    ev = sim.events("cell", t0)
    assert sorted((e["i"], e["j"]) for e in ev) == RING_MICRO and all(e["kind"] == STEEL for e in ev)
    states = []
    for _ in range(int(21 * 60)):
        sim.step()
        st = ring_state(sim)
        assert st in ("S", "B"), st
        for (i, j) in RING_MICRO[:4]:
            assert sim.get_cell(i, j) == sim.cell(i, j)
        states.append((sim.tick - t_pick, st))
        if (sim.tick - t_pick) % 30 == 0:
            assert sim.shadow == sim.grid()
    trans = [states[k][0] for k in range(1, len(states)) if states[k][1] != states[k - 1][1]]
    assert all(st == "S" for (dt, st) in states if dt < 17 * 60 - 2)
    assert all(st == "B" for (dt, st) in states if dt > 20 * 60 + 2)
    assert trans, "ring never flashed"
    assert 17 * 60 - 3 <= trans[0] <= 17.25 * 60 + 3, trans
    assert abs(trans[-1] - 20 * 60) <= 3, trans
    assert 10 <= len(trans) <= 13, trans
    for a, b in zip(trans, trans[1:-1]):
        assert abs((b - a) - 15) <= 1, trans
    assert sim.g.shovelTimer <= EPS
    assert sim.shadow == sim.grid()


def test_tank_on_ring_drives_out_when_shovel_makes_it_steel():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    # เจาะแหวนซ้ายออก แล้วจอดรถทับแนวแหวนก่อนเก็บพลั่ว
    for (i, j) in RING_MICRO:
        if i in (22, 23):
            sim.set_cell(i, j, EMPTY)
    sim.resync_shadow()
    p.x, p.y, p.dir = 80, 184, RIGHT
    sim.give_powerup("shovel")
    assert sim.cell(22, 48) == STEEL
    sim.set_input(1, LEFT)
    sim.run(0.5)
    assert p.x < 72


def test_extra_life_once_at_20000():
    sim = Sim(config=quiet())
    sim.start()
    assert sim.player(1).bonusLifeGiven is False
    sim.player(1).score = 19000
    t0 = sim.give_powerup("helmet")
    sim.step()
    assert sim.player(1).score == 19500 and sim.player(1).lives == 2 and not sim.events("extraLife", t0)
    t1 = sim.give_powerup("helmet")
    sim.step()
    assert sim.player(1).score == 20000
    assert sim.player(1).lives == 3 and sim.player(1).bonusLifeGiven is True
    assert [x["slot"] for x in sim.events("extraLife", t1)] == [1]
    t2 = sim.give_powerup("helmet")
    sim.step()
    assert sim.player(1).lives == 3 and sim.events("extraLife", t2) == []


def test_helmet_or_spawn_shield_blocks_enemy_bullet():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    p = sim.ptank(1)
    e = sim.enemies()[0]
    e.x, e.y, e.dir = 64, 102, DOWN
    p.shield = 5
    t0 = sim.tick
    sim.unfreeze_enemies()
    sim.run_until(lambda: sim.events("hit", t0), 2)
    sim.freeze_enemies()
    assert [h["what"] for h in sim.events("hit", t0)] == ["shield"]
    assert sim.ptank(1) is not None and sim.ptank(1).id == p.id
    assert sim.player(1).lives == 2 and not sim.events("playerDied", t0)
    assert [b for b in sim.bullets() if b.ownerId == e.id] == []


def test_friendly_fire_freezes_teammate_unless_shielded():
    sim = Sim(config=quiet())
    sim.start(slots=(1, 2))
    p1, p2 = sim.ptank(1), sim.ptank(2)
    p1.x, p1.y, p1.dir = 64, 120, UP
    p2.x, p2.y, p2.dir = 64, 40, UP
    p2.shield = 0
    t0 = sim.tick
    sim.fire_once(1)
    sim.run_until(lambda: p2.frozen > 0, 1)
    assert 3 - 2 * TICK <= p2.frozen <= 3 + EPS
    assert sim.ptank(2) is not None and sim.ptank(2).id == p2.id
    assert sim.player(2).lives == 2 and not sim.events("playerDied", t0)
    assert sim.player_bullets(1) == []
    # ระหว่างถูกแช่แข็ง: เดิน/ยิงไม่ได้
    y0 = p2.y
    t1 = sim.tick
    sim.set_input(2, UP, True)
    sim.run(2.5)
    assert p2.y == y0 and sim.player_bullets(2) == []
    assert not [e for e in sim.events("fire", t1) if e.get("slot") == 2]
    sim.run(0.7)
    assert p2.frozen <= EPS and p2.y < y0
    sim.set_input(2, -1, False)
    sim.wait_player_bullets_gone(2)
    # มีโล่ -> ไม่ถูกแช่แข็ง
    p2.x, p2.y, p2.dir = 64, 40, UP
    p2.shield = 5
    sim.fire_once(1)
    sim.wait_player_bullets_gone(1)
    assert p2.frozen == 0


def test_bullet_vs_bullet_player_and_enemy_cancel():
    cfg = arena(MAX_ENEMIES=[1, 1], ENEMY_SPAWN_BASE=100000, AI_FIRE_RATE=1000)
    sim = Sim(config=cfg)
    sim.start(freeze=True)
    sim.run_until(lambda: len(sim.enemies()) == 1, 2)
    p = sim.ptank(1)
    e = sim.enemies()[0]
    p.x, p.y, p.dir = 64, 150, UP
    p.shield = 0
    e.x, e.y, e.dir = 64, 20, DOWN
    t0 = sim.tick
    sim.unfreeze_enemies()
    sim.set_input(1, -1, True)
    sim.step()
    sim.set_input(1, -1, False)
    assert {x["team"] for x in sim.events("fire", t0)} == {"player", "enemy"}
    sim.run_until(lambda: not sim.bullets(), 1)
    sim.freeze_enemies()
    assert sim.events("explosion", t0) == [] and sim.events("hit", t0) == []
    assert sim.events("cell", t0) == []
    assert e.id in [t.id for t in sim.enemies()] and e.hp == 1
    assert sim.ptank(1) is not None and sim.ptank(1).id == p.id and sim.player(1).lives == 2


@pytest.mark.parametrize("level,p2y", [(0, 20), (1, 22)])
def test_bullet_vs_bullet_two_players_cancel(level, p2y):
    # level 1 + p2y 22: ระยะห่างลด 8px/tick และไม่ลงช่อง |dy|<4 ถ้าไม่แบ่งก้าวย่อย 2px
    sim = Sim(config=quiet())
    sim.start(slots=(1, 2))
    p1, p2 = sim.ptank(1), sim.ptank(2)
    for s_, t_ in ((1, p1), (2, p2)):
        sim.player(s_).level = level
        t_.level = level
    p1.x, p1.y, p1.dir = 64, 150, UP
    p2.x, p2.y, p2.dir = 64, p2y, DOWN
    p1.shield = 0
    p2.shield = 0
    t0 = sim.tick
    sim.set_input(1, -1, True)
    sim.set_input(2, -1, True)
    sim.step()
    sim.set_input(1, -1, False)
    sim.set_input(2, -1, False)
    assert sorted(x["slot"] for x in sim.events("fire", t0)) == [1, 2]
    sim.run_until(lambda: not sim.bullets(), 1)
    assert sim.events("explosion", t0) == []
    assert p1.frozen == 0 and p2.frozen == 0


# ---------------------------------------------------------------- tally / players

def test_tally_contents_and_two_player_bonus():
    cfg = quiet(STAGE_CLEAR_DELAY=0.1, TALLY_TIME=0.5)
    sim = Sim(config=cfg)
    sim.start(slots=(1, 2))
    sim.set_kills(1, [3, 1, 0, 2])
    sim.set_kills(2, [1, 0, 0, 1])
    sim.player(1).score = 5000
    sim.player(2).score = 3000
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "tally", 1)
    T = sim.g.tally
    assert T.stageNumber == 1 and T.gameOver is False
    a, b = T.players[1], T.players[2]
    to = luaenv.to_py
    assert kills_list(to(a.kills)) == [3, 1, 0, 2] and to(a.points) == [300, 200, 0, 800]
    assert a.totalKills == 6 and a.bonus == 1000 and a.score in (5000, 6000)
    assert kills_list(to(b.kills)) == [1, 0, 0, 1] and to(b.points) == [100, 0, 0, 400]
    assert b.totalKills == 2 and (b.bonus or 0) == 0 and b.score == 3000
    assert sim.player(1).score == 6000 and sim.player(2).score == 3000
    assert sim.g.hiScore >= 5000
    # ด่านต่อไป: เสมอกัน -> ไม่มีโบนัส
    sim.run_until(lambda: sim.phase == "playing", 2)
    sim.set_kills(1, [1, 1, 0, 0])
    sim.set_kills(2, [0, 0, 2, 0])
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "tally", 1)
    T = sim.g.tally
    assert T.stageNumber == 2
    assert (T.players[1].bonus or 0) == 0 and (T.players[2].bonus or 0) == 0
    assert sim.player(1).score == 6000 and sim.player(2).score == 3000


def test_tally_single_player_has_no_bonus():
    sim = Sim(config=quiet(STAGE_CLEAR_DELAY=0.1, TALLY_TIME=0.5))
    sim.start()
    sim.set_kills(1, [5, 0, 0, 0])
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "tally", 1)
    T = sim.g.tally
    assert (T.players[1].bonus or 0) == 0 and T.players[1].totalKills == 5
    assert T.players[2] is None
    assert sim.player(1).score == 0


def test_remove_player_back_to_waiting_and_readd():
    sim = Sim(config={"INTRO_TIME": 0.05, "AI_FIRE_RATE": 0})
    sim.start(slots=(1, 2))
    sim.run(1.0)
    sim.set_input(1, -1, True)
    sim.step()
    sim.remove(2)
    sim.step()
    assert sim.player(2) is None and sim.ptank(2) is None and sim.player_spawn(2) is None
    assert sim.phase == "playing" and sim.ptank(1) is not None
    assert sim.g.maxEnemiesOnField == 4
    sim.remove(2)  # ไม่มีอยู่แล้ว: ต้องไม่ error
    sim.remove(1)
    sim.step()
    assert sim.phase == "waiting"
    assert sim.tanks() == [] and sim.bullets() == [] and sim.spawns() == []
    assert sim.player(1) is None
    assert sim.events("phase")[-1]["phase"] == "waiting"
    sim.run(1.0)
    assert sim.phase == "waiting"
    sim.add(1)
    sim.step()
    assert sim.phase == "intro" and sim.g.stageNumber == 1


def test_remove_player_during_spawn_animation():
    sim = Sim(config=quiet())
    sim.add(1)
    sim.add(2)
    sim.run_until(lambda: sim.phase == "playing", 1)
    assert sim.player_spawn(2) is not None
    sim.remove(2)
    sim.step()
    assert sim.player_spawn(2) is None
    sim.run(1.5)
    assert sim.ptank(2) is None and sim.ptank(1) is not None


def test_add_player_during_intro_playing_and_stage_clear():
    sim = Sim(config=quiet(INTRO_TIME=0.5, STAGE_CLEAR_DELAY=2))
    sim.add(1)
    sim.step()
    assert sim.phase == "intro"
    sim.add(2)
    sim.run_until(lambda: sim.phase == "playing", 1)
    s1, s2 = sim.player_spawn(1), sim.player_spawn(2)
    assert s1 is not None and s2 is not None
    assert (s1.x, s1.y) == PLAYER_SPAWN_PX[1] and (s2.x, s2.y) == PLAYER_SPAWN_PX[2]
    assert sim.player(2).lives == 2
    sim.run(1.2)
    assert sim.ptank(2) is not None
    # playing: เข้ามาแล้วเกิดทันที (ชีวิตเริ่มต้น)
    sim.remove(2)
    sim.player(1).lives = 1
    sim.step()
    sim.add(2)
    sim.step()
    sp = sim.player_spawn(2)
    assert sp is not None and 1 - 3 * TICK <= sp.t <= 1 + EPS
    assert sim.player(2).lives == 2 and sim.player(2).score == 0 and sim.player(1).lives == 1
    sim.run(1.1)
    t2 = sim.ptank(2)
    assert t2 is not None and (t2.x, t2.y) == (128, 192) and t2.dir == UP and t2.shield > 2.5
    # addPlayer ซ้ำ -> ไม่สนใจ
    sim.player(2).score = 700
    sim.add(2)
    sim.step()
    assert sim.player(2).score == 700 and sim.ptank(2).id == t2.id
    # stageClear
    sim.remove(2)
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "stageClear", 3 * TICK)
    sim.add(2)
    sim.step()
    assert sim.player_spawn(2) is not None and sim.phase == "stageClear"


@pytest.mark.parametrize("join_phase", ["gameOver", "tally", "final"])
def test_add_player_after_game_over_joins_next_game(join_phase):
    sim = Sim(config=quiet(GAMEOVER_TIME=0.3, TALLY_TIME=0.3, FINAL_TIME=0.3))
    sim.start()
    sim.set_input(1, RIGHT, True)
    sim.run_until(lambda: sim.phase == "gameOver", 10)
    sim.set_input(1, -1, False)
    sim.run_until(lambda: sim.phase == join_phase, 2)
    sim.add(2)
    sim.step()
    assert sim.player_spawn(2) is None and sim.ptank(2) is None
    sim.run_until(lambda: sim.phase == "intro", 2)
    assert sim.g.stageNumber == 1 and sim.g.isGameOver is False
    sim.run_until(lambda: sim.phase == "playing", 1)
    assert sim.player_spawn(1) is not None and sim.player_spawn(2) is not None
    assert sim.player(2).lives == 2 and sim.player(1).lives == 2


def test_add_player_during_stage_tally_joins_next_stage():
    sim = Sim(config=quiet(STAGE_CLEAR_DELAY=0.05, TALLY_TIME=0.5))
    sim.start()
    sim.clear_stage()
    sim.run_until(lambda: sim.phase == "tally", 1)
    sim.add(2)
    sim.step()
    assert sim.player_spawn(2) is None and sim.ptank(2) is None
    sim.run_until(lambda: sim.phase == "playing" and sim.g.stageNumber == 2, 2)
    assert sim.player_spawn(1) is not None and sim.player_spawn(2) is not None


def test_set_input_invalid_args_are_ignored():
    sim = Sim(config=quiet())
    sim.start()
    p = sim.ptank(1)
    sim.set_input(1, UP, False)
    for args in [(1, 4, False), (1, -2, True), (1, 1.5, False), (1, None, True), (1, 0, "yes"),
                 (3, 0, True), (0, 0, True), (None, 0, True), ("1", 0, True)]:
        sim.call("setInput", *args)
    sim.call("setInput", 2, RIGHT, True)  # ผู้เล่น 2 ยังไม่อยู่
    y0 = p.y
    sim.run(0.5)
    assert abs((y0 - p.y) - 24) <= 0.8 + EPS and close(p.x, 64)
    assert sim.player_bullets(1) == []


# ---------------------------------------------------------------- determinism & soak

def snapshot(sim):
    g = sim.g
    players = {}
    for s in (1, 2):
        pl = g.players[s]
        if pl is not None:
            d = pick(pl, PLAYER_FIELDS)
            d["kills"] = luaenv.to_py(pl.kills)
            players[s] = d
    return {
        "phase": g.phase, "time": g.time, "stage": g.stageNumber,
        "tanks": [pick(t, TANK_FIELDS) for t in sim.tanks()],
        "bullets": [pick(b, BULLET_FIELDS) for b in sim.bullets()],
        "spawns": [pick(s, SPAWN_FIELDS) for s in sim.spawns()],
        "powerup": pick(g.powerup, ["id", "kind", "x", "y"]), "players": players, "grid": sim.grid(),
        "reserve": g.enemiesInReserve, "events": [e for _, e in sim.log],
    }


def scripted_run(seed, math_seed, seconds=40, input_seed=99):
    sim = Sim(seed=seed, math_seed=math_seed, enemies="bfpabfpabfpabfpabfpa",
              layout=make_layout(rows={6: "B", 12: "B", 16: "T", 18: "I"}, cells={(5, 9): "S", (20, 9): "W"}))
    sim.add(1)
    sim.add(2)
    rng = random.Random(input_seed)
    for k in range(int(seconds * 60)):
        if k % 20 == 0:
            for s in (1, 2):
                sim.set_input(s, rng.choice([-1, 0, 1, 2, 3]), rng.random() < 0.5)
        sim.step()
    return snapshot(sim)


def test_determinism_same_seed_same_state_different_seed_differs():
    a = scripted_run(seed=7, math_seed=1)
    b = scripted_run(seed=7, math_seed=4242)  # core ห้ามใช้ math.random
    assert a == b
    c = scripted_run(seed=8, math_seed=1)
    assert a["tanks"] != c["tanks"] or a["events"] != c["events"]


def test_seed_default_and_clamping():
    def run(**kw):
        sim = Sim(enemies="bfpa" * 5, **kw)
        sim.add(1)
        sim.run(15)
        return snapshot(sim)
    base = run(seed=1)
    assert run(pass_seed=False) == base       # ค่าเริ่มต้น seed = 1
    assert run(seed=0) == base                # clamp เข้า 1..2147483646
    assert run(seed=-50) == base
    assert run(seed=2 ** 40) == run(seed=2147483646)


def random_layout(rng):
    chars = "." * 12 + "B" * 6 + "S" + "W" + "T" * 2 + "I"
    cells = {(cx, cy): rng.choice(chars) for cx in range(26) for cy in range(26)}
    return make_layout(cells=cells)


def check_invariants(sim, stats):
    g = sim.g
    phase = g.phase
    assert phase in PHASES, phase
    tanks, bullets, spawns = sim.tanks(), sim.bullets(), sim.spawns()
    ids = [t.id for t in tanks]
    assert len(set(ids)) == len(ids), "duplicate tank ids"
    grid = sim.grid()
    for t in tanks:
        assert -EPS <= t.x <= 192 + EPS and -EPS <= t.y <= 192 + EPS, (t.x, t.y)
        assert t.dir in (0, 1, 2, 3) and isinstance(t.moving, bool)
        assert t.hp >= 1 and t.shield >= -EPS and t.frozen >= -EPS
        own = sum(1 for b in bullets if b.ownerId == t.id)
        assert t.bullets == own, "tank.bullets out of sync"
        if t.team == "player":
            assert t.kind == "player" and t.slot in (1, 2)
            assert own <= (2 if t.level >= 2 else 1)
            pl = g.players[t.slot]
            assert pl is not None and pl.tankId == t.id and not pl.out
        else:
            assert t.team == "enemy" and t.kind in ENEMY_KINDS and t.hp <= t.maxHp
        # รถถังไม่ควรทับน้ำหรือฐาน
        # เผื่อเศษทศนิยม (เช่น y = 183.9999999999999 ไม่นับว่าแตะแถวบน)
        i0, i1 = int((t.x + EPS) // 4), int(math.ceil((t.x + 16 - EPS) / 4)) - 1
        j0, j1 = int((t.y + EPS) // 4), int(math.ceil((t.y + 16 - EPS) / 4)) - 1
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                assert grid[j * GN + i] not in (WATER, BASE), ("tank in water/base", t.x, t.y)
    for s in (1, 2):
        pt = [t for t in tanks if t.team == "player" and t.slot == s]
        ps = [x for x in spawns if x.team == "player" and x.slot == s]
        assert len(pt) + len(ps) <= 1, "player %d has tank and spawn" % s
        pl = g.players[s]
        if pl is None:
            assert not pt and not ps
        else:
            assert pl.lives >= 0 and pl.score >= 0 and pl.score % 100 == 0
            assert pl.level in (0, 1, 2, 3)
            assert sum(kills_list(luaenv.to_py(pl.kills))) <= 20
    n_enemy = len([t for t in tanks if t.team == "enemy"]) + len([x for x in spawns if x.team == "enemy"])
    assert n_enemy <= 6
    if phase != "waiting":
        assert g.enemiesInReserve + g.enemiesSpawned == 20
        assert g.enemiesInReserve >= 0
        for (i, j) in BASE_MICRO:
            assert grid[j * GN + i] == BASE
    for b in bullets:
        assert -EPS <= b.x <= 208 + EPS and -EPS <= b.y <= 208 + EPS, (b.x, b.y)
        assert b.dir in (0, 1, 2, 3) and b.speed in (120, 180, 240) and b.team in ("player", "enemy")
    pu = g.powerup
    if pu is not None:
        assert pu.kind in POWERUP_KINDS and pu.x % 8 == 0 and pu.y % 8 == 0
        assert 0 <= pu.x <= 192 and 0 <= pu.y <= 192
    assert all(v in (0, 1, 2, 3, 4, 5, 6) for v in grid)
    stats["phases"].add(phase)


def check_events(evs, prev_phase):
    allowed = {
        "waiting": {"intro"}, "intro": {"playing", "waiting"}, "playing": {"stageClear", "gameOver", "waiting"},
        "stageClear": {"tally", "gameOver", "waiting"}, "gameOver": {"tally", "waiting"},
        "tally": {"intro", "final", "waiting"}, "final": {"intro", "waiting"},
    }
    for e in evs:
        typ = e.get("type")
        assert typ in EVENT_FIELDS, "unknown event %r" % (e,)
        for f in EVENT_FIELDS[typ]:
            assert e.get(f) is not None, "event %s missing %s" % (typ, f)
        if typ == "phase":
            assert e["phase"] in allowed[prev_phase], (prev_phase, e["phase"])
            prev_phase = e["phase"]
        elif typ == "cell":
            assert 0 <= e["i"] < GN and 0 <= e["j"] < GN and e["kind"] in range(7)
        elif typ == "explosion":
            assert -EPS <= e["x"] <= 208 + EPS and -EPS <= e["y"] <= 208 + EPS
        elif typ == "score":
            assert e["points"] in (100, 200, 300, 400, 500)
        elif typ == "hit":
            assert e["what"] in ("brick", "steel", "border", "armor", "shield")
        elif typ in ("powerupSpawn", "powerupTaken"):
            assert e["kind"] in POWERUP_KINDS
    return prev_phase


@pytest.mark.parametrize("seed,minutes", [(12345, 5), (777, 2)])
def test_soak_random_two_player_inputs(seed, minutes):
    rng = random.Random(seed)
    stages = [{"name": "Soak %d" % k, "map": random_layout(rng),
               "enemies": "".join(rng.choice("bbbfpa") for _ in range(20))} for k in range(3)]
    sim = Sim(stages=stages, seed=seed)
    sim.add(1)
    sim.add(2)
    stats = {"phases": set()}
    prev_phase = "waiting"
    next_change = {1: 0, 2: 0}
    total = minutes * 60 * 60
    logged = 0
    for k in range(total):
        for s in (1, 2):
            if k >= next_change[s]:
                d = rng.choice([-1, 0, 1, 2, 3, 0, 1, 2, 3])
                sim.set_input(s, d, rng.random() < 0.6)
                next_change[s] = k + rng.randint(3, 90)
        if k == total // 3:
            sim.remove(2)
        if k == total // 3 + 400:
            sim.add(2)
        if k == (2 * total) // 3:
            sim.remove(1)
            sim.remove(2)
        if k == (2 * total) // 3 + 60:
            sim.add(2)
            sim.add(1)
        r = rng.random()
        dt = TICK if r < 0.85 else (1.0 / 30 if r < 0.95 else 0.5 / 60)
        sim.step(dt)
        prev_phase = check_events([e for _, e in sim.log[logged:]], prev_phase)
        logged = len(sim.log)
        if k % 10 == 0:
            check_invariants(sim, stats)
        if k % 120 == 0 and sim.shadow is not None and sim.phase != "waiting":
            assert sim.shadow == sim.grid(), "grid changed without a cell event"
    assert "playing" in stats["phases"]
    assert sim.events("fire")
    assert sim.events("explosion")
