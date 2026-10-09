"""Smoke/consistency tests of BattleCityServer.lua on the Roblox stubs (roblox_env.World).

    python -m pytest -q BattleCity/tests/test_server.py

The server Script runs with the real BattleCityCore and a small fixture stage module
(tests/fixtures/stages_small.lua, 3 valid layouts).  To compare the visuals with the core state, most tests load
the core through a thin wrapper ModuleScript that stores the game object created by Core.new() in the server's
_G (_G.BC_TEST.game).  The core file itself is not modified.  All heavy comparisons run in Lua (_G.BC_VERIFY)
right after a world step, when the server has synced the visuals to the core state of that step.
"""
import json
import os
import random
import struct
import sys

import pytest
from lupa import lua51

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402
from roblox_env import World  # noqa: E402

SERVER = luaenv.path("BattleCityServer.lua")
CORE = luaenv.path("BattleCityCore.lua")
FIXTURE_STAGES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "stages_small.lua")

FLOOR_Y = 1

# the real core wrapped so the test can reach the game object the server created
CORE_WRAPPER = """
local Core = (function()
@@CORE@@
end)()
local realNew = Core.new
Core.new = function(opts)
	local g = realNew(opts)
	local rec = { game = g, inputCalls = 0 }
	_G.BC_TEST = rec
	-- นับการเรียก setInput: เทสจะได้รู้ว่า server กรองค่าแปลก ๆ เองก่อนถึง core
	local realSetInput = g.setInput
	g.setInput = function(self, slot, dir, fire)
		rec.inputCalls = rec.inputCalls + 1
		return realSetInput(self, slot, dir, fire)
	end
	return g
end
return Core
"""

# --------------------------------------------------------------------------- Lua-side consistency check
VERIFY_LUA = r"""
local KIND_MAT = {
	[1] = Enum.Material.Brick, [2] = Enum.Material.DiamondPlate, [3] = Enum.Material.Glass,
	[4] = Enum.Material.Grass, [5] = Enum.Material.Ice,
}
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local KIND_PART = { player = "Hatch", basic = "Turret", fast = "Nose", power = "Muzzle", armor = "PlateF" }
local function rgb(c)
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end
local function sameColor(c, r, g, b)
	local cr, cg, cb = rgb(c)
	return cr == r and cg == g and cb == b
end
local BASE_COLOR = {
	p1 = { 236, 200, 48 }, p2 = { 56, 176, 72 }, enemy = { 188, 188, 188 }, red = { 216, 40, 16 },
	[4] = { 40, 160, 128 }, [3] = { 224, 192, 64 }, [2] = { 188, 188, 188 }, [1] = { 120, 120, 120 },
}

_G.BC_VERIFY = function()
	local g = _G.BC_TEST.game
	local errs = {}
	local function err(s)
		if #errs < 25 then
			errs[#errs + 1] = s
		end
	end
	local root = workspace:FindFirstChild("BattleCity")
	if not root then
		return "workspace.BattleCity missing", 0
	end
	local field, dyn = root:FindFirstChild("Field"), root:FindFirstChild("Dynamic")
	if not field or not dyn then
		return "Field/Dynamic missing", 0
	end

	-- map: one part per non-empty, non-BASE micro cell, right material and place
	local parts, nParts = {}, 0
	for _, c in ipairs(field:GetChildren()) do
		if c:IsA("BasePart") then
			nParts = nParts + 1
			parts[c.Name] = c
		end
	end
	local expected = 0
	for j = 0, 51 do
		for i = 0, 51 do
			local kind = g.grid[j * 52 + i + 1]
			local part = parts["C" .. i .. "_" .. j]
			if kind ~= 0 and kind ~= 6 then
				expected = expected + 1
				if not part then
					err("missing cell part " .. i .. "," .. j .. " kind " .. kind)
				else
					if part.Material ~= KIND_MAT[kind] then
						err("cell " .. i .. "," .. j .. " kind " .. kind .. " has material " .. tostring(part.Material))
					end
					local p = part.Position
					if math.abs(p.X - (i * 2 + 1)) > 0.2 or math.abs(p.Z - (j * 2 + 1)) > 0.2 then
						err("cell " .. i .. "," .. j .. " misplaced")
					end
					if kind == 4 and p.Y < FLOOR_Y + 6 then
						err("trees below tank height at " .. i .. "," .. j)
					end
					if (kind == 1 or kind == 2) and math.abs(part.Size.Y - 6) > 1e-6 then
						err("wall height wrong at " .. i .. "," .. j)
					end
				end
			elseif part then
				err("stale cell part " .. i .. "," .. j .. " (grid kind " .. kind .. ")")
			end
		end
	end
	if nParts ~= expected then
		err("field part count " .. nParts .. " ~= " .. expected)
	end

	-- dynamic children
	local tanks, bullets, spawns, pu = {}, {}, {}, {}
	for _, c in ipairs(dyn:GetChildren()) do
		local n = c.Name
		local id = string.match(n, "^Tank(%d+)$")
		if id then
			tanks[tonumber(id)] = c
		else
			id = string.match(n, "^Bullet(%d+)$")
			if id then
				bullets[tonumber(id)] = c
			else
				id = string.match(n, "^Spawn(%d+)$")
				if id then
					spawns[tonumber(id)] = c
				elseif n == "Powerup" then
					pu[#pu + 1] = c
				elseif n ~= "Explosion" and n ~= "Score" then
					err("unexpected Dynamic child " .. n)
				end
			end
		end
	end

	for _, t in ipairs(g.tanks) do
		local m = tanks[t.id]
		if not m then
			err("missing model for tank " .. t.id)
		else
			tanks[t.id] = nil
			local r = m.PrimaryPart
			if not r or r.Name ~= "Root" then
				err("tank " .. t.id .. " PrimaryPart is not Root")
			else
				local p = r.Position
				local ex, ez = (t.x + 8) * 0.5, (t.y + 8) * 0.5
				if math.abs(p.X - ex) > 0.01 or math.abs(p.Z - ez) > 0.01 or math.abs(p.Y - FLOOR_Y) > 0.01 then
					err(string.format("tank %d at (%.3f, %.3f, %.3f) expected (%.3f, 1, %.3f)", t.id, p.X, p.Y, p.Z, ex, ez))
				end
				local lv = r.CFrame.LookVector
				if math.abs(lv.X - DX[t.dir]) > 1e-3 or math.abs(lv.Z - DZ[t.dir]) > 1e-3 or math.abs(lv.Y) > 1e-3 then
					err("tank " .. t.id .. " faces wrong way for dir " .. t.dir)
				end
				local pv = m:GetPivot().Position
				if (pv - p).Magnitude > 1e-6 then
					err("tank " .. t.id .. " pivot is not its Root")
				end
				-- every visible part stays inside the 8x8 stud tile (barrel may poke out a little)
				for _, part in ipairs(m:GetChildren()) do
					if part:IsA("BasePart") and part.Name ~= "Shield" then
						local rel = r.CFrame:PointToObjectSpace(part.Position)
						if math.abs(rel.X) > 4 or math.abs(rel.Z) > 4.5 or rel.Y < -0.01 or rel.Y > 4 then
							err("tank " .. t.id .. " part " .. part.Name .. " out of the tank box")
						end
					end
				end
			end
			local kindKey = t.team == "player" and "player" or t.kind
			if not m:FindFirstChild(KIND_PART[kindKey] or "Turret") then
				err("tank " .. t.id .. " (" .. kindKey .. ") lacks its distinctive part")
			end
			local hull = m:FindFirstChild("Hull")
			if hull then
				local want
				if t.team == "player" then
					want = BASE_COLOR[t.slot == 2 and "p2" or "p1"]
				elseif t.kind == "armor" then
					want = BASE_COLOR[math.max(1, math.min(4, t.hp))]
				else
					want = BASE_COLOR.enemy
				end
				local red = BASE_COLOR.red
				local okColor = sameColor(hull.Color, want[1], want[2], want[3])
					or (t.bonus and sameColor(hull.Color, red[1], red[2], red[3]))
				if not okColor then
					local r1, g1, b1 = rgb(hull.Color)
					err(string.format("tank %d (%s hp %d bonus %s) hull color %d,%d,%d", t.id, t.kind, t.hp, tostring(t.bonus), r1, g1, b1))
				end
			else
				err("tank " .. t.id .. " has no Hull")
			end
			local shield = m:FindFirstChild("Shield")
			if (t.shield > 0) ~= (shield ~= nil) then
				err("tank " .. t.id .. " shield visual mismatch (shield " .. t.shield .. ")")
			end
		end
	end
	for id in pairs(tanks) do
		err("stale tank model " .. id)
	end

	for _, b in ipairs(g.bullets) do
		local part = bullets[b.id]
		if not part then
			err("missing bullet part " .. b.id)
		else
			bullets[b.id] = nil
			local p = part.Position
			if math.abs(p.X - b.x * 0.5) > 0.01 or math.abs(p.Z - b.y * 0.5) > 0.01 or math.abs(p.Y - (FLOOR_Y + 2)) > 0.01 then
				err("bullet " .. b.id .. " misplaced")
			end
		end
	end
	for id in pairs(bullets) do
		err("stale bullet part " .. id)
	end

	for _, s in ipairs(g.spawns) do
		local m = spawns[s.id]
		if not m then
			err("missing spawn star " .. s.id)
		else
			spawns[s.id] = nil
			local p = m.PrimaryPart.Position
			if math.abs(p.X - (s.x + 8) * 0.5) > 0.01 or math.abs(p.Z - (s.y + 8) * 0.5) > 0.01 then
				err("spawn star " .. s.id .. " misplaced")
			end
		end
	end
	for id in pairs(spawns) do
		err("stale spawn star " .. id)
	end

	if g.powerup then
		if #pu ~= 1 then
			err("expected 1 power-up part, found " .. #pu)
		else
			local p = pu[1].Position
			if math.abs(p.X - (g.powerup.x + 8) * 0.5) > 0.01 or math.abs(p.Z - (g.powerup.y + 8) * 0.5) > 0.01
				or math.abs(p.Y - (FLOOR_Y + 7.5)) > 0.01 then
				err("power-up misplaced")
			end
			if pu[1]:GetAttribute("Kind") ~= g.powerup.kind then
				err("power-up kind mismatch")
			end
		end
	elseif #pu > 0 then
		err("stale power-up part")
	end

	-- eagle
	local body = field.Eagle.Body
	local label = body.Icon.Label
	if g.baseDestroyed then
		if label.Text ~= "🏳️" then
			err("eagle should look wrecked")
		end
	elseif label.Text ~= "🦅" then
		err("eagle should look alive")
	end

	-- attributes
	local rs = game:GetService("ReplicatedStorage").BattleCity
	local function attr(name, want)
		local v = rs:GetAttribute(name)
		if v ~= want then
			err("attribute " .. name .. " = " .. tostring(v) .. " expected " .. tostring(want))
		end
	end
	attr("Phase", g.phase)
	attr("Stage", g.stageNumber)
	attr("StageName", g.stageName)
	attr("EnemiesLeft", g.enemiesInReserve)
	attr("HiScore", g.hiScore)
	attr("GameOver", g.isGameOver)
	for slot = 1, 2 do
		local p = g.players[slot]
		attr("P" .. slot .. "Present", p ~= nil)
		attr("P" .. slot .. "Lives", p and p.lives or 0)
		attr("P" .. slot .. "Score", p and p.score or 0)
	end
	local tallyStr = rs:GetAttribute("Tally")
	if g.tally == nil then
		if tallyStr ~= "" then
			err("Tally should be empty")
		end
	else
		local ok, t = pcall(function()
			return game:GetService("HttpService"):JSONDecode(tallyStr)
		end)
		if not ok or type(t) ~= "table" then
			err("Tally is not valid JSON: " .. tostring(tallyStr))
		else
			if t.stageNumber ~= g.tally.stageNumber or t.gameOver ~= g.tally.gameOver then
				err("Tally header mismatch")
			end
			for slot = 1, 2 do
				local a, b = g.tally.players[slot], t.players[slot]
				if a then
					if type(b) ~= "table" then
						err("Tally lacks slot " .. slot)
					else
						for k = 1, 4 do
							if a.kills[k] ~= b.kills[k] or a.points[k] ~= b.points[k] then
								err("Tally kills/points mismatch slot " .. slot)
							end
						end
						if a.totalKills ~= b.totalKills or a.score ~= b.score or a.bonus ~= b.bonus then
							err("Tally totals mismatch slot " .. slot)
						end
					end
				elseif b then
					err("Tally has data for absent slot " .. slot)
				end
			end
		end
	end
	return table.concat(errs, "\n"), #dyn:GetChildren()
end

-- every part under workspace.BattleCity must be purely decorative
_G.BC_FLAGS = function()
	local bad, n = {}, 0
	for _, d in ipairs(workspace.BattleCity:GetDescendants()) do
		if d:IsA("BasePart") then
			n = n + 1
			if not d.Anchored or d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow then
				if #bad < 10 then
					bad[#bad + 1] = d:GetFullName()
				end
			end
		end
	end
	return table.concat(bad, "\n"), n
end
""".replace("FLOOR_Y", str(FLOOR_Y))

# test-side helpers that change the core state directly (the adapter must follow whatever the core does)
CLEAR_STAGE_LUA = """
local g = _G.BC_TEST.game
g.enemiesInReserve = 0
for k = #g.spawns, 1, -1 do
	if g.spawns[k].team == "enemy" then table.remove(g.spawns, k) end
end
for k = #g.tanks, 1, -1 do
	local t = g.tanks[k]
	if t.team == "enemy" then
		g._tankById[t.id] = nil
		table.remove(g.tanks, k)
	end
end
"""

FREEZE_ENEMIES_LUA = "_G.BC_TEST.game.freezeTimer = 1000"


# --------------------------------------------------------------------------- harness
def make_world(signal_behavior="Immediate", wrap_core=True, stages=FIXTURE_STAGES, before=None, server_src=None):
    w = World(signal_behavior=signal_behavior)
    if before:
        before(w)
    if wrap_core:
        with open(CORE, encoding="utf-8") as f:
            core_src = f.read()
        w.add_module_source("ServerScriptService", "BattleCityCore", CORE_WRAPPER.replace("@@CORE@@", core_src))
    else:
        w.add_module("ServerScriptService", "BattleCityCore", CORE)
    w.add_module("ServerScriptService", "BattleCityStages", stages)
    if server_src is None:
        ok, err, _ = w.run_script(SERVER)
    else:
        ok, err, _ = w.run_source(server_src, name="BattleCityServer")
    assert ok, err
    w.eval(VERIFY_LUA)  # only defines functions; BC_VERIFY needs the wrapped core
    return w


def g(w, expr):
    """Evaluate a Lua expression on the core game object (server context)."""
    return w.eval("local g = _G.BC_TEST.game; return " + expr)


def verify(w, max_dynamic=150):
    res = w.eval("return _G.BC_VERIFY()")
    msg, ndyn = res
    assert msg == "", msg
    assert ndyn <= max_dynamic, "Dynamic has %d children" % ndyn
    return ndyn


def check_flags(w):
    bad, n = w.eval("return _G.BC_FLAGS()")
    assert bad == "", "parts with physics enabled:\n" + bad
    return n


def clean(w):
    w.assert_no_errors(allow_warnings=False)


def send(w, player, d, fire):
    w.eval("game:GetService('ReplicatedStorage').BattleCity.Input:FireServer(%s, %s)" % (d, "true" if fire else "false"), player)


def rs_attrs(w):
    return w.attrs(w.find("ReplicatedStorage.BattleCity"))


def step_until(w, cond, timeout, check_every=1):
    """Step one frame at a time (verifying every `check_every` frames) until cond() is true."""
    n = int(timeout * 60)
    for k in range(n):
        w.step()
        if k % check_every == 0:
            verify(w)
        if cond():
            return True
    return False


def dyn_names(w):
    return [w.name(c) for c in w.children("Workspace.BattleCity.Dynamic")]


def field_cell(w, i, j):
    return w.find("Workspace.BattleCity.Field.C%d_%d" % (i, j))


# --------------------------------------------------------------------------- static check
def _lua51_global_access(src):
    """(op, name) for every GETGLOBAL/SETGLOBAL in the compiled chunk (Lua 5.1 bytecode)."""
    lua = lua51.LuaRuntime(encoding=None)
    dump = lua.eval(b"function(src) local f = assert(loadstring(src, '=BattleCityServer')); return string.dump(f) end")
    data = dump(src.encode("utf-8"))
    assert data[:5] == b"\x1bLua\x51"
    endian = "<" if data[6] == 1 else ">"
    int_size, size_t_size, num_size = data[7], data[8], data[10]
    pos = [12]

    def take(fmt, size):
        v = struct.unpack_from(endian + fmt, data, pos[0])[0]
        pos[0] += size
        return v

    def rint():
        return take("i" if int_size == 4 else "q", int_size)

    def rsize():
        return take("I" if size_t_size == 4 else "Q", size_t_size)

    def rbyte():
        v = data[pos[0]]
        pos[0] += 1
        return v

    def rstring():
        n = rsize()
        s = data[pos[0]:pos[0] + n]
        pos[0] += n
        return s[:-1] if n else None

    found = set()

    def function():
        rstring()
        rint()
        rint()
        for _ in range(4):
            rbyte()
        code = [take("I", 4) for _ in range(rint())]
        consts = []
        for _ in range(rint()):
            t = rbyte()
            if t == 0:
                consts.append(None)
            elif t == 1:
                consts.append(bool(rbyte()))
            elif t == 3:
                consts.append(take("d", num_size))
            elif t == 4:
                consts.append(rstring())
            else:
                raise AssertionError("unknown constant type %d" % t)
        for _ in range(rint()):
            function()
        for _ in range(rint()):
            rint()
        for _ in range(rint()):
            rstring()
            rint()
            rint()
        for _ in range(rint()):
            rstring()
        for ins in code:
            op = ins & 0x3F
            if op in (5, 7):  # OP_GETGLOBAL, OP_SETGLOBAL
                found.add(("set" if op == 7 else "get", consts[(ins >> 14) & 0x3FFFF].decode()))

    function()
    return found


def test_server_uses_only_known_globals():
    """A misspelled local silently becomes a nil global in Lua; catch it before the user does."""
    with open(SERVER, encoding="utf-8") as f:
        src = f.read()
    allowed = {
        "game", "workspace", "script", "Instance", "Enum", "Vector3", "CFrame", "Color3", "UDim2", "TweenInfo",
        "math", "string", "table", "os", "task", "tostring", "tonumber", "type", "pairs", "ipairs", "pcall",
        "require", "warn",
    }
    access = _lua51_global_access(src)
    sets = sorted(n for op, n in access if op == "set")
    unknown = sorted(n for op, n in access if op == "get" and n not in allowed)
    assert not sets, "assigns globals: %s" % sets
    assert not unknown, "reads unexpected globals: %s" % unknown


# --------------------------------------------------------------------------- tests
def test_boot_with_real_core_and_no_players():
    w = make_world(wrap_core=False)
    w.advance(0.5)
    a = rs_attrs(w)
    assert a["Phase"] == "waiting"
    assert a["MapCenter"] == (52, 1, 52)
    assert a["MapSize"] == (104, 0, 104)
    assert a["P1Present"] is False and a["P2Present"] is False
    assert a["Tally"] == "" and a["GameOver"] is False
    assert isinstance(a["PhaseStartedAt"], (int, float))
    assert w.class_name(w.find("ReplicatedStorage.BattleCity")) == "Folder"
    assert w.class_name(w.find("ReplicatedStorage.BattleCity.Input")) == "RemoteEvent"
    assert w.get("Players", "CharacterAutoLoads") is False
    field = w.find("Workspace.BattleCity.Field")
    kids = w.children(field)
    assert sorted(w.name(k) for k in kids) == ["Eagle", "Frame"]  # empty map while waiting
    assert all(w.class_name(k) == "Model" for k in kids)
    assert w.children("Workspace.BattleCity.Dynamic") == []
    # eagle: gold body with a top SurfaceGui
    gui = w.find("Workspace.BattleCity.Field.Eagle.Body.Icon")
    assert w.value(w.get(gui, "Face")) == "Enum.NormalId.Top"
    assert w.value(w.get(gui, "SizingMode")) == "Enum.SurfaceGuiSizingMode.PixelsPerStud"
    assert w.get("Workspace.BattleCity.Field.Eagle.Body.Icon.Label", "Text") == "🦅"
    assert w.eval("local e = workspace.BattleCity.Field.Eagle; return e.PrimaryPart == e.Body") is True
    floor = w.value(w.get("Workspace.BattleCity.Field.Frame.Floor", "Position"))
    size = w.value(w.get("Workspace.BattleCity.Field.Frame.Floor", "Size"))
    assert floor[1] + size[1] / 2 == pytest.approx(FLOOR_Y)
    assert w.value(w.get("Workspace.BattleCity.Field.Frame.Floor", "Color")) == (0, 0, 0)
    check_flags(w)
    # a player joins with the real (unwrapped) core: the game starts
    p = w.add_player("Solo", 1)
    w.advance(4)
    a = rs_attrs(w)
    assert a["Phase"] == "playing" and a["Stage"] == 1 and a["StageName"] == "Fixture Bricks"
    assert w.attr(p, "BattleCitySlot") == 1
    assert any(n.startswith("Tank") for n in dyn_names(w))
    assert w.sounds() == []  # all SOUNDS ids are empty
    clean(w)


def test_single_player_flow_tanks_spawns_and_input():
    w = make_world()
    p1 = w.add_player("Alice", 1)
    assert w.attr(p1, "BattleCitySlot") == 1
    w.step()
    verify(w)
    a = rs_attrs(w)
    assert a["Phase"] == "intro" and a["Stage"] == 1 and a["P1Present"] is True and a["P1Name"] == "Alice"
    assert a["P1Lives"] == 2 and a["EnemiesLeft"] == 20
    assert w.get(p1, "Character") is None
    started = a["PhaseStartedAt"]
    # intro -> playing: spawn stars first, then tanks
    assert step_until(w, lambda: g(w, "g.phase") == "playing", 3)
    assert rs_attrs(w)["PhaseStartedAt"] > started
    w.step()
    verify(w)
    assert any(n.startswith("Spawn") for n in dyn_names(w))
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 1.5)
    tank_id = g(w, "g.players[1].tankId")
    model = "Workspace.BattleCity.Dynamic.Tank%d" % tank_id
    assert w.find(model) is not None
    assert w.find(model + ".Shield") is not None  # spawn shield bubble
    w.eval(FREEZE_ENEMIES_LUA)
    # drive input through the remote from the client
    z0 = w.value(w.get(model + ".Root", "Position"))[2]
    send(w, p1, 0, False)
    for _ in range(30):
        w.step()
        verify(w)
    z1 = w.value(w.get(model + ".Root", "Position"))[2]
    assert z1 < z0 - 5  # moved up the screen (-Z)
    assert g(w, "g._inputs[1].dir") == 0
    send(w, p1, 3, False)
    for _ in range(10):
        w.step()
        verify(w)
    assert g(w, "g._tankById[g.players[1].tankId].dir") == 3
    lv =w.eval("return workspace.BattleCity.Dynamic.Tank%d.Root.CFrame.LookVector" % tank_id)
    assert w.value(lv) == pytest.approx((-1, 0, 0), abs=1e-6)
    # shield bubble disappears after SHIELD_SPAWN seconds
    assert step_until(w, lambda: w.find(model + ".Shield") is None, 4)
    # fire: a bullet part appears and later disappears with the core bullet
    send(w, p1, -1, True)
    assert step_until(w, lambda: any(n.startswith("Bullet") for n in dyn_names(w)), 1)
    send(w, p1, -1, False)
    assert step_until(w, lambda: g(w, "#g.bullets") == 0, 3)
    w.step()
    assert not any(n.startswith("Bullet") for n in dyn_names(w))
    check_flags(w)
    clean(w)


def test_shooting_wall_removes_bricks_then_base_and_game_restarts():
    w = make_world()
    p1 = w.add_player("Alice", 1)
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    w.eval(FREEZE_ENEMIES_LUA)
    # the base ring brick right of P1's spawn (micro col 22, rows 48..51)
    for j in range(48, 52):
        assert field_cell(w, 22, j) is not None
        assert w.value(w.get(field_cell(w, 22, j), "Material")) == "Enum.Material.Brick"
    cells_before = len(w.children("Workspace.BattleCity.Field"))
    send(w, p1, 1, True)  # drive right into the ring and keep shooting
    saw_explosion = [False]

    def bricks_gone():
        if "Explosion" in dyn_names(w):
            saw_explosion[0] = True
        return all(field_cell(w, 22, j) is None for j in range(48, 52))

    assert step_until(w, bricks_gone, 3)
    assert all(g(w, "g.grid[%d]" % (j * 52 + 22 + 1)) == 0 for j in range(48, 52))
    assert len(w.children("Workspace.BattleCity.Field")) == cells_before - 4
    assert step_until(w, lambda: g(w, "g.baseDestroyed"), 5)
    if "Explosion" in dyn_names(w):
        saw_explosion[0] = True
    assert saw_explosion[0]
    assert w.get("Workspace.BattleCity.Field.Eagle.Body.Icon.Label", "Text") == "🏳️"
    assert step_until(w, lambda: rs_attrs(w)["Phase"] == "gameOver", 1)
    assert rs_attrs(w)["GameOver"] is True
    send(w, p1, -1, False)
    assert step_until(w, lambda: g(w, "g.phase") == "tally", 6, check_every=10)
    tally = json.loads(rs_attrs(w)["Tally"])
    assert tally["gameOver"] is True and tally["stageNumber"] == 1
    assert tally["players"][0]["totalKills"] == 0
    assert step_until(w, lambda: g(w, "g.phase") == "final", 8, check_every=10)
    assert step_until(w, lambda: g(w, "g.phase") == "intro", 5, check_every=10)
    # new game: stage 1 again, ring rebuilt, eagle alive, tally cleared
    w.step()
    verify(w)
    a = rs_attrs(w)
    assert a["Stage"] == 1 and a["GameOver"] is False and a["Tally"] == ""
    assert all(field_cell(w, 22, j) is not None for j in range(48, 52))
    assert w.get("Workspace.BattleCity.Field.Eagle.Body.Icon.Label", "Text") == "🦅"
    check_flags(w)
    clean(w)


def test_stage_progression_rebuilds_field_from_grid():
    w = make_world()
    w.add_player("Alice", 1)
    w.add_player("Bob", 2)
    names = ["Fixture Bricks", "Fixture Waters", "Fixture Forest", "Fixture Bricks"]
    for stage in range(1, 5):
        assert step_until(w, lambda: g(w, "g.phase") == "playing", 4, check_every=5)
        a = rs_attrs(w)
        assert a["Stage"] == stage and a["StageName"] == names[stage - 1]
        verify(w)
        materials = {w.value(w.get(c, "Material")) for c in w.children("Workspace.BattleCity.Field")
                     if w.is_a(c, "BasePart")}
        if stage == 2:
            assert "Enum.Material.Glass" in materials and "Enum.Material.Grass" in materials
            assert "Enum.Material.Ice" in materials and "Enum.Material.DiamondPlate" in materials
        if stage == 3:
            assert "Enum.Material.Ice" in materials and "Enum.Material.Grass" in materials
        # let enemies appear for a moment, then finish the stage
        w.advance(1.5)
        verify(w)
        w.eval(CLEAR_STAGE_LUA)
        assert step_until(w, lambda: g(w, "g.phase") == "stageClear", 0.5)
        assert step_until(w, lambda: g(w, "g.phase") == "tally", 4, check_every=10)
        tally = json.loads(rs_attrs(w)["Tally"])
        assert tally["gameOver"] is False and tally["stageNumber"] == stage
        assert len(tally["players"]) == 2
        assert step_until(w, lambda: g(w, "g.phase") == "intro", 7, check_every=10)
        w.step()
        verify(w)  # field part count == non-empty non-BASE cells right after the stage event
        assert rs_attrs(w)["Tally"] == ""
    check_flags(w)
    clean(w)


def test_two_players_spectator_promotion_and_everyone_leaving():
    w = make_world()
    a = w.add_player("Ann", 1)
    b = w.add_player("Ben", 2)
    c = w.add_player("Cid", 3)
    assert [w.attr(p, "BattleCitySlot") for p in (a, b, c)] == [1, 2, 0]
    assert step_until(w, lambda: g(w, "#g.tanks") >= 2, 5)
    attrs = rs_attrs(w)
    assert attrs["P1Name"] == "Ann" and attrs["P2Name"] == "Ben"
    # spectator input is ignored
    send(w, c, 2, True)
    w.step()
    assert g(w, "g._inputs[1].dir") == -1 and g(w, "g._inputs[2].dir") == -1
    assert g(w, "g._inputs[1].fire") is False and g(w, "g._inputs[2].fire") is False
    # P1 leaves while moving/shooting: the spectator takes slot 1
    send(w, a, 0, True)
    w.advance(0.3)
    w.remove_player(a)
    assert w.attr(c, "BattleCitySlot") == 1
    w.step()
    verify(w)
    attrs = rs_attrs(w)
    assert attrs["P1Present"] is True and attrs["P1Name"] == "Cid" and attrs["P2Name"] == "Ben"
    send(w, c, 1, False)
    w.step()
    assert g(w, "g._inputs[1].dir") == 1
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 3)
    # P2 leaves in the middle of things
    send(w, b, 3, True)
    w.advance(0.5)
    w.remove_player(b)
    w.step()
    verify(w)
    assert rs_attrs(w)["P2Present"] is False and rs_attrs(w)["P2Name"] == ""
    # last player leaves: back to waiting, all tanks/bullets/stars gone
    w.advance(0.2)
    w.remove_player(c)
    w.step()
    verify(w)
    assert rs_attrs(w)["Phase"] == "waiting"
    assert not any(n.startswith(("Tank", "Bullet", "Spawn", "Powerup")) for n in dyn_names(w))
    w.advance(2)
    assert all(n in ("Explosion", "Score") for n in dyn_names(w))
    # a new player can start again
    d = w.add_player("Dee", 4)
    assert w.attr(d, "BattleCitySlot") == 1
    assert step_until(w, lambda: g(w, "g.phase") == "playing", 4)
    clean(w)


def test_invalid_remote_arguments_are_ignored():
    w = make_world()
    p1 = w.add_player("Alice", 1)
    w.advance(0.1)
    bad = ["'0', true", "1.5, false", "4, true", "-2, true", "0/0, true", "math.huge, true", "-math.huge, false",
           "1, 'yes'", "1, nil", "nil, true", "{}, true", "1, {}", "true, true", "1, 1", "", "Vector3.new(1, 0, 0), true",
           "game.Players.LocalPlayer, true"]
    for args in bad:
        w.eval("game:GetService('ReplicatedStorage').BattleCity.Input:FireServer(%s)" % args, p1)
        w.step()
        assert g(w, "g._inputs[1].dir") == -1, args
        assert g(w, "g._inputs[1].fire") is False, args
    # the server filtered every one of them itself (never forwarded to the core)
    assert w.eval("return _G.BC_TEST.inputCalls") == 0
    send(w, p1, 2, True)
    w.step()
    assert w.eval("return _G.BC_TEST.inputCalls") == 1
    assert g(w, "g._inputs[1].dir") == 2 and g(w, "g._inputs[1].fire") is True
    send(w, p1, -1, False)
    w.step()
    assert g(w, "g._inputs[1].dir") == -1 and g(w, "g._inputs[1].fire") is False
    clean(w)


def test_player_already_in_game_with_character_when_script_starts():
    def before(w):
        early = w.add_player("Early", 1)
        w.step()  # CharacterAutoLoads is still true: the avatar spawns
        assert w.get(early, "Character") is not None

    w = make_world(before=before)
    early = w.players()[0]
    w.step()
    ch = w.get(early, "Character")
    assert ch is None or w.get(ch, "Parent") is None  # avatar destroyed
    assert w.attr(early, "BattleCitySlot") == 1
    assert rs_attrs(w)["Phase"] == "intro" and rs_attrs(w)["P1Name"] == "Early"
    # someone loading a character later gets it removed too
    w.call(early, "LoadCharacter")
    w.step()
    ch = w.get(early, "Character")
    assert ch is None or w.get(ch, "Parent") is None
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    clean(w)


def test_powerup_visual_follows_core_state_and_blinks():
    w = make_world()
    w.add_player("Alice", 1)
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    w.eval(FREEZE_ENEMIES_LUA)
    icons = {"star": "⭐", "grenade": "💣", "helmet": "🛡️", "shovel": "🧱", "timer": "⏰", "tank": "1UP"}
    for k, (kind, icon) in enumerate(icons.items()):
        w.eval("_G.BC_TEST.game.powerup = { id = %d, kind = '%s', x = 0, y = 96 }" % (900000 + k, kind))
        w.step()
        verify(w)
        part = "Workspace.BattleCity.Dynamic.Powerup"
        assert w.get(part + ".Icon.Label", "Text") == icon
        assert w.value(w.get(part + ".Icon", "Face")) == "Enum.NormalId.Top"
        seen = set()
        for _ in range(30):
            w.step()
            seen.add(w.get(part, "Transparency"))
        assert seen == {0, 1}  # blinking
    w.eval("_G.BC_TEST.game.powerup = nil")
    w.step()
    verify(w)
    assert "Powerup" not in dyn_names(w)
    # picking one up for real: a star changes the player's tank shape (longer barrel)
    tank_id = g(w, "g.players[1].tankId")
    barrel = "Workspace.BattleCity.Dynamic.Tank%d.Barrel" % tank_id
    len0 = w.value(w.get(barrel, "Size"))[2]
    w.eval("local g = _G.BC_TEST.game; local t = g._tankById[g.players[1].tankId]; "
           "g.powerup = { id = 990001, kind = 'star', x = t.x, y = t.y }")
    w.step()
    verify(w)
    assert g(w, "g.players[1].level") == 1
    assert "Powerup" not in dyn_names(w)
    assert w.value(w.get(barrel, "Size"))[2] > len0
    assert "Score" in dyn_names(w)  # 500 points popup
    w.advance(1.2)
    assert "Score" not in dyn_names(w)
    clean(w)


def test_frozen_player_blinks_and_bonus_enemy_flashes():
    w = make_world()
    w.add_player("Alice", 1)
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    tank_id = g(w, "g.players[1].tankId")
    w.eval("local g = _G.BC_TEST.game; g._tankById[g.players[1].tankId].frozen = 1")
    hull = "Workspace.BattleCity.Dynamic.Tank%d.Hull" % tank_id
    seen = set()
    for _ in range(30):
        w.step()
        verify(w)
        seen.add(w.get(hull, "Transparency"))
    assert seen == {0, 1}
    w.advance(1)
    assert w.get(hull, "Transparency") == 0
    # a bonus carrier flashes red (~6 Hz)
    first_enemy = "(function() for _, t in ipairs(g.tanks) do if t.team == 'enemy' then return t.id end end return nil end)()"
    assert step_until(w, lambda: g(w, first_enemy) is not None, 5)
    eid = g(w, first_enemy)
    w.eval(FREEZE_ENEMIES_LUA)
    w.eval("_G.BC_TEST.game._tankById[%d].bonus = true" % eid)
    colors = set()
    for _ in range(20):
        w.step()
        verify(w)
        colors.add(w.value(w.get("Workspace.BattleCity.Dynamic.Tank%d.Hull" % eid, "Color")))
    assert len(colors) == 2
    clean(w)


def test_p2_only_tally_is_valid_json():
    w = make_world()
    a = w.add_player("Ann", 1)
    w.add_player("Ben", 2)
    assert step_until(w, lambda: g(w, "g.phase") == "playing", 4)
    w.remove_player(a)
    w.step()
    w.eval(CLEAR_STAGE_LUA)
    assert step_until(w, lambda: g(w, "g.phase") == "tally", 5, check_every=5)
    tally = json.loads(rs_attrs(w)["Tally"])
    assert tally["players"][0] is False  # no hole in a JSON array: absent slot 1 is false
    assert tally["players"][1]["score"] == g(w, "g.players[2].score")
    clean(w)


def test_sound_ids_are_played_only_when_set():
    with open(SERVER, encoding="utf-8") as f:
        src = f.read()
    assert '\tfire = "", ' in src
    src = src.replace('\tfire = "", ', '\tfire = "12345", ', 1)
    w = make_world(server_src=src)
    p1 = w.add_player("Alice", 1)
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    w.eval(FREEZE_ENEMIES_LUA)
    send(w, p1, -1, True)
    w.advance(1)
    played = w.sounds()
    assert played and all(s["id"] == "rbxassetid://12345" for s in played)
    clean(w)


@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
def test_long_run_two_players_no_leaks(behavior):
    rng = random.Random(7)
    w = make_world(signal_behavior=behavior)
    pa = w.add_player("Ann", 1)
    pb = w.add_player("Ben", 2)
    spec = w.add_player("Cid", 3)
    players = [pa, pb]
    max_dyn = 0
    stage_events = 0
    last_stage = None
    total_seconds = 150
    for half in range(total_seconds * 2):
        # new random input for each active player twice a second (often holding fire)
        for p in list(players):
            send(w, p, rng.choice([-1, 0, 1, 2, 3, 0, 2]), rng.random() < 0.7)
        if half % 60 == 59:
            w.eval(CLEAR_STAGE_LUA)  # force a stage change every 30 s
        if half % 37 == 20:
            w.eval("local g = _G.BC_TEST.game; g.powerup = { id = %d, kind = 'timer', x = %d, y = %d }"
                   % (800000 + half, rng.randrange(0, 25) * 8, rng.randrange(0, 12) * 8))
        if half == 140:
            # P2 leaves mid-game: the spectator is promoted
            w.remove_player(pb)
            players = [pa, spec]
            assert w.attr(spec, "BattleCitySlot") == 2
        for _ in range(30):
            w.step()
        ndyn = verify(w)
        max_dyn = max(max_dyn, ndyn)
        st = g(w, "g.stageNumber")
        if st != last_stage:
            stage_events += 1
            last_stage = st
    assert stage_events >= 3
    assert max_dyn < 150
    # Dynamic shrinks back to the live objects once effects expire
    w.eval(FREEZE_ENEMIES_LUA)
    for p in players:
        send(w, p, -1, False)
    w.advance(2)
    verify(w)
    live = g(w, "#g.tanks + #g.bullets + #g.spawns + (g.powerup and 1 or 0)")
    extra = [n for n in dyn_names(w) if n in ("Explosion", "Score")]
    assert len(dyn_names(w)) - len(extra) == live
    n_parts = check_flags(w)
    assert n_parts < 3000
    for p in players:
        w.remove_player(p)
    w.step()
    verify(w)
    assert rs_attrs(w)["Phase"] == "waiting"
    clean(w)


def test_shovel_ring_toggles_reuse_parts_and_grenade_clears_enemies():
    w = make_world()
    w.add_player("Alice", 1)
    assert step_until(w, lambda: g(w, "g.players[1].tankId ~= nil"), 5)
    # wait for some enemies to be on the field
    assert step_until(w, lambda: g(w, "(function() local n = 0 for _, t in ipairs(g.tanks) do if t.team == 'enemy' then n = n + 1 end end return n end)()") >= 2, 10, check_every=10)
    w.eval(FREEZE_ENEMIES_LUA)
    ring = (22, 48)  # a micro cell of the base ring
    w.eval("_G.BC_RING_PART = workspace.BattleCity.Field.C%d_%d" % ring)
    pickup = ("local g = _G.BC_TEST.game; local t = g._tankById[g.players[1].tankId]; "
              "g.powerup = { id = %d, kind = '%s', x = t.x, y = t.y }")
    w.eval(pickup % (700001, "shovel"))
    w.step()
    verify(w)
    part = "Workspace.BattleCity.Field.C%d_%d" % ring
    assert w.value(w.get(part, "Material")) == "Enum.Material.DiamondPlate"
    assert w.eval("return workspace.BattleCity.Field.C%d_%d == _G.BC_RING_PART" % ring) is True  # same part, restyled
    # flashing in the last seconds: the part toggles between brick and steel, always matching the grid
    seen = set()
    for k in range(int(21 * 60)):
        w.step()
        if k % 3 == 0:
            verify(w)
        if g(w, "g.shovelTimer") > 0:
            seen.add(w.value(w.get(part, "Material")))
    verify(w)
    assert seen == {"Enum.Material.DiamondPlate", "Enum.Material.Brick"}
    assert w.value(w.get(part, "Material")) == "Enum.Material.Brick"
    assert w.eval("return workspace.BattleCity.Field.C%d_%d == _G.BC_RING_PART" % ring) is True
    # grenade: every enemy tank explodes at once
    n_enemies = g(w, "(function() local n = 0 for _, t in ipairs(g.tanks) do if t.team == 'enemy' then n = n + 1 end end return n end)()")
    assert n_enemies >= 1
    w.eval(pickup % (700002, "grenade"))
    w.step()
    verify(w)
    assert g(w, "(function() for _, t in ipairs(g.tanks) do if t.team == 'enemy' then return false end end return true end)()")
    names = dyn_names(w)
    assert names.count("Explosion") >= 2 * n_enemies  # big explosions use two balls
    w.advance(1.5)
    verify(w)
    assert "Explosion" not in dyn_names(w)
    clean(w)


def test_deferred_signals_quick_join_and_leave():
    """SignalBehavior = Deferred: a player who joins and leaves at once must not keep a slot."""
    w = make_world(signal_behavior="Deferred")
    a = w.add_player("Ann", 1)
    w.remove_player(a)
    b = w.add_player("Ben", 2)
    w.advance(0.5)
    verify(w)
    assert w.attr(b, "BattleCitySlot") == 1
    attrs = rs_attrs(w)
    assert attrs["P1Name"] == "Ben" and attrs["P2Present"] is False
    assert g(w, "g.players[2] == nil")
    clean(w)
