"""Python wrapper around roblox_stubs.lua: run Roblox Script/LocalScript/ModuleScript code in ONE lupa.lua51 VM.

Quick start (server + one client):

    from roblox_env import World
    import luaenv

    w = World()
    w.add_module("ServerScriptService", "BattleCityCore", luaenv.path("BattleCityCore.lua"))
    w.add_module("ServerScriptService", "BattleCityStages", luaenv.path("BattleCityStages.lua"))
    w.run_script(luaenv.path("BattleCityServer.lua"))            # Script in ServerScriptService
    p1 = w.add_player("Alice", 1)                                # PlayerAdded fires immediately
    w.run_local_script(luaenv.path("BattleCityClient.lua"), p1)  # LocalScript in Alice.PlayerScripts
    w.advance(3.0)                                               # 180 steps of 1/60 s
    w.key_down(p1, "W"); w.advance(0.5); w.key_up(p1, "W")
    w.assert_no_errors()
    folder = w.find("Workspace.BattleCity.Dynamic")
    print(w.attrs(w.find("ReplicatedStorage.BattleCity")))

Notes
* Simulated time only moves with step()/advance(). Remote events fired during step N (or between steps) are
  delivered at the start of the next step. task.wait/task.delay resume right after Heartbeat.
* add_player() fires Players.PlayerAdded immediately (synchronously). Like Roblox, Players.CharacterAutoLoads
  defaults to true, so a Character spawns on the next step unless the server script turns it off.
* Errors inside scripts/handlers do NOT raise in python: they are collected in errors() (with traceback).
  Errors in harness calls (get/set/call/eval) raise (lupa.LuaError / LuaScriptError).
* eval(code, player) runs Lua with Roblox globals as the server (player=None) or as that player's client.
* Instances are Lua userdata; pass them back into the helpers (get/set/call/children/...).
* Instances created by a LocalScript are visible only to that client (like Roblox); helpers here see everything.
* No physics/joints: use Model:PivotTo to move multi-part models. UIListLayout/UIGridLayout do not reposition GUI.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402

STUBS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roblox_stubs.lua")

TICK = 1 / 60


class LuaScriptError(AssertionError):
    """Raised by assert_no_errors / eval_or_raise."""


class World:
    def __init__(self, touch=False, keyboard=None, gamepad=False, studio=False, echo=False, max_players=8,
                 signal_behavior="Immediate"):
        """touch/keyboard/gamepad are the default input devices for players added later.
        echo=True prints script print()/warn() output to stdout (handy while debugging).
        signal_behavior="Deferred" runs signal handlers at the end of the current resumption cycle
        (Roblox Workspace.SignalBehavior = Deferred) instead of immediately; use it to check robustness."""
        self.lua = luaenv.new_runtime()
        self.stubs = luaenv.load_file(self.lua, STUBS_PATH)
        opts = self.lua.table_from({"studio": studio, "echo": echo, "maxPlayers": max_players,
                                    "signalBehavior": signal_behavior})
        self.w = self.stubs.newWorld(opts)
        self.defaults = {"touch": touch, "keyboard": keyboard, "gamepad": gamepad}
        self.game = self.w.game
        self.workspace = self.w.workspace
        self._wcall = self.lua.eval("function(w, name, ...) return w[name](w, ...) end")
        self._get = self.lua.eval("function(o, k) return o[k] end")
        self._set = self.lua.eval("function(o, k, v) o[k] = v end")
        self._method = self.lua.eval("function(o, name, ...) return o[name](o, ...) end")

    # ------------------------------------------------------------------ helpers
    def _call(self, name, *args):
        return self._wcall(self.w, name, *args)

    def _inst(self, x):
        """Accept an Instance or a path string like 'ServerScriptService' / 'Workspace.Map'."""
        if isinstance(x, str):
            inst = self.find(x)
            if inst is None:
                raise KeyError("no instance at path %r" % x)
            return inst
        return x

    def _seq(self, t):
        if t is None:
            return []
        return [t[i] for i in range(1, len(t) + 1)]

    def service(self, name):
        """game:GetService(name) (Workspace, Players, ReplicatedStorage, ...)."""
        s = self.w.serviceByClass[name]
        if s is None:
            raise KeyError("unknown service %r" % name)
        return s

    @property
    def time(self):
        return self.w.time

    # ------------------------------------------------------------------ scripts
    def run_script(self, path, parent="ServerScriptService", name=None):
        """Run a server Script. Returns (ok, error_or_None, script_instance)."""
        opts = {"class": "Script", "parent": self._inst(parent)}
        if name:
            opts["name"] = name
        return self._call("runScript", path, self.lua.table_from(opts))

    def run_local_script(self, path, player, parent=None, name=None):
        """Run a LocalScript as `player`'s client (default parent: player.PlayerScripts)."""
        opts = {"class": "LocalScript", "player": player}
        if parent is not None:
            opts["parent"] = self._inst(parent)
        if name:
            opts["name"] = name
        return self._call("runScript", path, self.lua.table_from(opts))

    def run_source(self, src, cls="Script", player=None, parent=None, name=None):
        """Like run_script but from a source string."""
        opts = {"class": cls}
        if player is not None:
            opts["player"] = player
        if parent is not None:
            opts["parent"] = self._inst(parent)
        if name:
            opts["name"] = name
        return self._call("runSource", src, self.lua.table_from(opts), None)

    def add_module(self, parent, name, path):
        """Create a ModuleScript `name` under parent (Instance or path) whose source is the file at `path`."""
        return self._call("addModule", self._inst(parent), name, path)

    def add_module_source(self, parent, name, src):
        return self._call("addModuleSource", self._inst(parent), name, src, None)

    # ------------------------------------------------------------------ players
    def add_player(self, name="Player1", user_id=None, touch=None, keyboard=None, gamepad=None, viewport=(1280, 720)):
        """Add a player; PlayerAdded fires immediately (synchronously). Returns the Player instance."""
        opts = {}
        for key, val in (("touch", touch), ("keyboard", keyboard), ("gamepad", gamepad)):
            if val is None:
                val = self.defaults[key]
            if val is not None:
                opts[key] = val
        opts["viewportX"], opts["viewportY"] = viewport
        return self._call("addPlayer", name, user_id, self.lua.table_from(opts))

    def remove_player(self, player):
        self._call("removePlayer", player)

    def players(self):
        return self._seq(self._method(self.service("Players"), "GetPlayers"))

    def set_viewport(self, player, x, y):
        self._call("setViewportSize", player, x, y)

    def camera(self, player=None):
        """The client's workspace.CurrentCamera (or the server camera when player is None)."""
        return self._call("camera", player)

    # ------------------------------------------------------------------ time
    def step(self, dt=TICK):
        self._call("step", dt)

    def advance(self, seconds, dt=TICK):
        self._call("advance", seconds, dt)

    # ------------------------------------------------------------------ input (fires in that player's client scripts)
    def key_down(self, player, key, game_processed=False):
        return self._call("keyDown", player, key, game_processed)

    def key_up(self, player, key, game_processed=False):
        return self._call("keyUp", player, key, game_processed)

    def tap_key(self, player, key, hold=TICK * 2):
        self.key_down(player, key)
        self.advance(hold)
        self.key_up(player, key)

    def gamepad_button(self, player, button, down=True, game_processed=False):
        return self._call("gamepadButton", player, button, down, game_processed)

    def thumbstick(self, player, x, y, which=1, game_processed=False):
        return self._call("thumbstick", player, x, y, which, game_processed)

    def touch_begin(self, player, gui, x=None, y=None, game_processed=False):
        """Touch the centre of `gui` (or x, y in GUI coordinates). Returns the touch InputObject."""
        return self._call("touchBegin", player, self._inst(gui) if gui is not None else None, x, y, game_processed)

    def touch_move(self, player, touch, x, y, game_processed=False):
        return self._call("touchMove", player, touch, x, y, game_processed)

    def touch_end(self, player, touch, game_processed=False):
        return self._call("touchEnd", player, touch, game_processed)

    # ------------------------------------------------------------------ instances
    def find(self, path):
        """Find by dotted path, e.g. 'Workspace.BattleCity.Dynamic' or 'Players.Alice.PlayerGui.HUD'. None if missing."""
        return self._call("find", path)

    def get(self, inst, prop):
        """inst[prop] (raises lupa.LuaError on invalid member, like Roblox)."""
        return self._get(self._inst(inst), prop)

    def set(self, inst, prop, value):
        self._set(self._inst(inst), prop, value)

    def call(self, inst, method, *args):
        """inst:method(...) called from the harness (server-like context)."""
        return self._method(self._inst(inst), method, *args)

    def children(self, inst):
        return self._seq(self._call("children", self._inst(inst)))

    def descendants(self, inst):
        return self._seq(self._call("descendants", self._inst(inst)))

    def child(self, inst, name):
        return self._method(self._inst(inst), "FindFirstChild", name)

    def name(self, inst):
        return self._get(inst, "Name")

    def class_name(self, inst):
        return self._get(inst, "ClassName")

    def full_name(self, inst):
        return self._call("fullName", inst)

    def is_a(self, inst, cls):
        return self._method(inst, "IsA", cls)

    def attr(self, inst, name):
        return self.value(self._method(self._inst(inst), "GetAttribute", name))

    def attrs(self, inst):
        """All attributes as a python dict (datatypes converted with value())."""
        t = self._call("attributes", self._inst(inst))
        return {k: self.value(t[k]) for k in t.keys()}

    def typeof(self, v):
        return self.stubs.typeof(v)

    def value(self, v):
        """Convert a Lua value to python: Vector3/Vector2/Color3/CFrame/UDim2... -> tuple of numbers,
        EnumItem -> 'Enum.X.Y', BrickColor -> name, tables -> list/dict, Instance -> unchanged."""
        if v is None or isinstance(v, (bool, int, float, str)):
            return v
        t, comps = self.stubs.describe(v)
        if t in ("Vector3", "Vector2", "Color3", "CFrame", "UDim", "UDim2", "Rect", "NumberRange"):
            return tuple(comps[i] for i in range(1, len(comps) + 1))
        if t == "EnumItem":
            return comps[1]
        if t == "BrickColor":
            return comps[1]
        if t == "table":
            return luaenv.to_py(v)
        return v

    def abs_rect(self, gui):
        """(x, y, w, h) of a GuiObject in GUI coordinates (same space as AbsolutePosition)."""
        return self._call("absRect", self._inst(gui))

    def is_on_screen(self, gui, player):
        res = self._call("isOnScreen", self._inst(gui), player)
        return res[0] if isinstance(res, tuple) else res

    # ------------------------------------------------------------------ ad-hoc Lua
    def try_eval(self, code, player=None):
        """Run Lua code with Roblox globals (server context, or player's client context).
        Returns (ok, [values...]) / (False, [error_message]). Does not touch errors()."""
        res = self._call("eval", code, player)
        if not isinstance(res, tuple):
            res = (res,)
        return res[0], list(res[1:])

    def eval(self, code, player=None):
        """Run Lua code; return its first value (or a tuple if several). Raises LuaScriptError on error."""
        ok, vals = self.try_eval(code, player)
        if not ok:
            raise LuaScriptError(vals[0] if vals else "error")
        if not vals:
            return None
        return vals[0] if len(vals) == 1 else tuple(vals)

    # ------------------------------------------------------------------ diagnostics
    def errors(self):
        return self._seq(self.w.errors)

    def warnings(self):
        return self._seq(self.w.warnings)

    def output(self):
        return self._seq(self.w.output)

    def sounds(self):
        """Sounds played so far: list of dicts {id, name, time}."""
        out = []
        for e in self._seq(self.w.soundLog):
            out.append({"id": e["id"], "name": e["name"], "time": e["time"]})
        return out

    def clear_errors(self):
        self.lua.eval("function(w) w.errors = {} w.warnings = {} end")(self.w)

    def assert_no_errors(self, allow_warnings=True):
        errs = self.errors()
        if not allow_warnings:
            errs = errs + ["WARNING: " + x for x in self.warnings()]
        if errs:
            raise LuaScriptError("Lua errors:\n" + "\n\n".join(errs))
