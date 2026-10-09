"""Adapter smoke tests for BattleCityClient.lua (LocalScript) on the Roblox stubs.

The test plays the server's role itself: it creates ReplicatedStorage.BattleCity + RemoteEvent "Input",
logs every Input:FireServer(dir, fire) it receives, and drives the attributes of the spec by hand.

Run:  python -m pytest -q BattleCity/tests/test_client.py
"""
import json
import math
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402
from roblox_env import World  # noqa: E402

CLIENT = luaenv.path("BattleCityClient.lua")
GUI_INSET = 58  # roblox_stubs.lua: GUI y = viewport y - 58 (IgnoreGuiInset ScreenGui starts at y = -58)
HUD = "Players.%s.PlayerGui.BattleCityHUD"

# The server's side of the contract, written as a tiny server Script (logs every Input event).
SERVER_ROLE = """
local Players = game:GetService("Players")
Players.CharacterAutoLoads = %s
local RS = game:GetService("ReplicatedStorage")
local f = Instance.new("Folder")
f.Name = "BattleCity"
local ev = Instance.new("RemoteEvent")
ev.Name = "Input"
ev.Parent = f
f.Parent = RS
_G.inputLog = {}
ev.OnServerEvent:Connect(function(plr, dir, fire)
    table.insert(_G.inputLog, { plr.Name, dir, fire, typeof(dir), typeof(fire) })
end)
"""


# --------------------------------------------------------------------------- test-only extensions
# EXTENSION (not in roblox_env.py): fire a UserInputService event (e.g. WindowFocusReleased) for one client.
def fire_uis(w, player, event, *args):
    pc = w.w.clientsByPlayer[player]
    w._call("_fireUIS", pc, event, *args)
    w._call("_settle")


class Harness:
    def __init__(self, touch=False, viewport=(1280, 720), signal_behavior="Immediate", make_folder=True,
                 slot=1, autoload=False, name="Alice", start_client=True, gamepad=False):
        self.w = World(touch=touch, gamepad=gamepad, signal_behavior=signal_behavior)
        self.autoload = autoload
        if make_folder:
            self.make_folder()
        self.name = name
        self.p = self.w.add_player(name, 1, viewport=viewport)
        if slot is not None:
            self.w.call(self.p, "SetAttribute", "BattleCitySlot", slot)
        if start_client:
            self.start()

    def start(self, player=None):
        ok, err, _ = self.w.run_local_script(CLIENT, player or self.p)
        assert ok, err
        self.w.step()

    def make_folder(self):
        ok, err, _ = self.w.run_source(SERVER_ROLE % ("true" if self.autoload else "false"))
        assert ok, err

    # ---------------------------------------------------------------- server role
    @property
    def folder(self):
        return self.w.find("ReplicatedStorage.BattleCity")

    def set(self, name, value):
        self.w.call(self.folder, "SetAttribute", name, value)

    def set_lua(self, name, expr):
        self.w.eval('game:GetService("ReplicatedStorage").BattleCity:SetAttribute("%s", %s)' % (name, expr))

    def now(self):
        return self.w.eval("return workspace:GetServerTimeNow()")

    def phase(self, phase, ago=0.0, start_first=False):
        start = self.now() - ago
        if start_first:
            self.set("PhaseStartedAt", start)
            self.set("Phase", phase)
        else:
            self.set("Phase", phase)
            self.set("PhaseStartedAt", start)

    def basic_state(self):
        self.set_lua("MapCenter", "Vector3.new(52, 1, 52)")
        self.set_lua("MapSize", "Vector3.new(104, 0, 104)")
        self.set("Stage", 1)
        self.set("StageName", "First Strike")
        self.set("EnemiesLeft", 20)
        self.set("P1Present", True)
        self.set("P2Present", False)
        self.set("P1Lives", 2)
        self.set("P2Lives", 0)
        self.set("P1Score", 0)
        self.set("P2Score", 0)
        self.set("P1Name", self.name)
        self.set("HiScore", 20000)
        self.set("GameOver", False)
        self.set("Tally", "")

    def log(self, who=None):
        """All (dir, fire) the server received from `who` (default: this harness' player)."""
        who = who or self.name
        t = luaenv.to_py(self.w.eval("return _G.inputLog")) or []
        out = []
        for e in t:
            assert e[3] == "number" and e[4] == "boolean", e
            assert e[1] == int(e[1]) and -1 <= e[1] <= 3, e
            if e[0] == who:
                out.append((int(e[1]), e[2]))
        return out

    def sent(self):
        """Step once (remote events are delivered at the start of the next step) and return the log."""
        self.w.step()
        return self.log()

    # ---------------------------------------------------------------- GUI helpers
    def gui(self, path, player_name=None):
        g = self.w.find((HUD % (player_name or self.name)) + ("." + path if path else ""))
        assert g is not None, "missing GUI " + path
        return g

    def has_gui(self, path):
        return self.w.find((HUD % self.name) + "." + path) is not None

    def shown(self, path, player=None):
        return bool(self.w.is_on_screen(self.gui(path), player or self.p))

    def text(self, path):
        return self.w.get(self.gui(path), "Text")

    def rect(self, path):
        return self.w.abs_rect(self.gui(path))

    def assert_clean(self):
        self.w.assert_no_errors()
        bad = [x for x in self.w.warnings() if "BattleCityClient" in x]
        assert not bad, bad

    # ---------------------------------------------------------------- camera helpers
    def project(self, x, y, z):
        return self.w.eval(
            "local v, on = workspace.CurrentCamera:WorldToViewportPoint(Vector3.new(%r, %r, %r)) return v.X, v.Y, v.Z, on"
            % (x, y, z), self.p)

    def field_rect_gui(self, top=0.0):
        """Screen rect (GUI coordinates) of the 104x104 field from floor up to `top` studs above it."""
        xs, ys = [], []
        for x in (0.0, 104.0):
            for z in (0.0, 104.0):
                for y in (1.0, 1.0 + top):
                    sx, sy, depth, on = self.project(x, y, z)
                    assert depth > 0
                    xs.append(sx)
                    ys.append(sy - GUI_INSET)
        return min(xs), min(ys), max(xs), max(ys)


def overlaps(r, field, tol=0.75):
    x, y, w, h = r
    fx0, fy0, fx1, fy1 = field
    if w <= 0 or h <= 0:
        return False
    return x < fx1 - tol and x + w > fx0 + tol and y < fy1 - tol and y + h > fy0 + tol


def no_consecutive_duplicates(seq):
    return all(seq[i] != seq[i + 1] for i in range(len(seq) - 1)) and (not seq or seq[0] != (-1, False))


OVERLAYS = {
    "intro": "IntroOverlay",
    "gameOver": "FieldFrame.GameOverRise",
    "tally": "TallyScreen",
    "final": "FinalScreen",
    "waiting": "WaitingScreen",
}


def assert_only_overlay(h, phase):
    for ph, path in OVERLAYS.items():
        assert h.shown(path) == (ph == phase), "%s visible=%s during phase %s" % (path, h.shown(path), phase)


# =========================================================================== startup / camera
def test_script_is_plain_lua51():
    lua = luaenv.new_runtime()
    with open(CLIENT, encoding="utf-8") as f:
        src = f.read()
    ok, err = lua.eval("function(s) local f, e = loadstring(s, '=client') return f ~= nil, e end")(src)
    assert ok, err
    for bad in ("+=", "-=", "continue", "//", "`", "%d"):
        assert bad not in src.replace("-- ", ""), bad


def test_startup_hud_coregui_and_reset_on_spawn():
    # CharacterAutoLoads stays true here: a spawning character must not wipe the HUD (ResetOnSpawn = false)
    h = Harness(autoload=True)
    h.basic_state()
    h.w.advance(1.0)
    h.assert_clean()
    hud = h.gui("")
    assert h.w.get(hud, "ResetOnSpawn") is False
    assert h.w.get(hud, "IgnoreGuiInset") is True
    for cg in ("Backpack", "Health", "EmotesMenu"):
        assert h.w.eval("return game:GetService('StarterGui'):GetCoreGuiEnabled(Enum.CoreGuiType.%s)" % cg, h.p) is False
    # every TextLabel uses the NES-like Arcade font
    for d in h.w.descendants(hud):
        if h.w.class_name(d) == "TextLabel":
            assert h.w.value(h.w.get(d, "Font")) == "Enum.Font.Arcade", h.w.full_name(d)
    # keyboard player: no touch controls, but the keyboard help is shown in the gutter
    assert not h.has_gui("DPad") and not h.has_gui("FireButton")
    assert h.shown("HelpText")


@pytest.mark.parametrize("viewport", [(1280, 720), (720, 1280), (844, 390), (390, 844), (800, 800), (1024, 768)])
def test_camera_frames_whole_map(viewport):
    h = Harness(viewport=viewport)
    h.basic_state()
    h.w.advance(0.2)
    h.assert_clean()
    ctype, px, py, pz, lx, ly, lz, vx, vy = h.w.eval(
        "local c = workspace.CurrentCamera local cf = c.CFrame local lv = cf.LookVector "
        "return c.CameraType.Name, cf.Position.X, cf.Position.Y, cf.Position.Z, lv.X, lv.Y, lv.Z, "
        "c.ViewportSize.X, c.ViewportSize.Y", h.p)
    assert ctype == "Scriptable"
    assert (vx, vy) == viewport
    # from above, almost straight down, tilted a little toward +Z (screen up = -Z)
    assert py > 40
    assert ly < -0.99 and lz < 0 and abs(lx) < 1e-9
    assert pz > 52 and abs(px - 52) < 1e-9
    assert abs((pz - 52) - 0.03 * (py - 1)) < 1e-6
    # the view ray goes exactly through MapCenter
    dx, dy, dz = 52 - px, 1 - py, 52 - pz
    t = dx * lx + dy * ly + dz * lz
    miss = math.sqrt((px + lx * t - 52) ** 2 + (py + ly * t - 1) ** 2 + (pz + lz * t - 52) ** 2)
    assert miss < 1e-6
    # whole map (plus ~8 stud margin, and walls/trees/power-ups up to 8 studs high) inside the frustum
    points = [(x, y, z) for x in (0, 104) for z in (0, 104) for y in (1, 9)]
    points += [(x, 1, z) for x in (-7.5, 111.5) for z in (-7.5, 111.5)]
    for x, y, z in points:
        sx, sy, depth, on = h.project(x, y, z)
        assert on, (viewport, x, y, z, sx, sy)
    # HUD never covers the field (score/panel/help sit in the gray gutters)
    field = h.field_rect_gui(top=0)
    for path in ("ScoreArea", "SidePanel", "HelpText", "SpectatorLabel"):
        r = h.rect(path)
        assert not overlaps(r, field), (viewport, path, r, field)
    for path in ("ScoreArea", "SidePanel"):
        x, y, w, hh = h.rect(path)
        assert w > 10 and hh > 10, (viewport, path, w, hh)
        assert x >= -0.5 and x + w <= viewport[0] + 0.5 and y >= -GUI_INSET - 0.5 and y + hh <= viewport[1] - GUI_INSET + 0.5
    # gray backdrop leaves a hole that contains the whole field
    hole_l = h.rect("BackdropLeft")
    hole_r = h.rect("BackdropRight")
    hole_t = h.rect("BackdropTop")
    hole_b = h.rect("BackdropBottom")
    full = h.field_rect_gui(top=6.2)
    assert hole_l[0] + hole_l[2] <= full[0] + 0.5
    assert hole_r[0] >= full[2] - 0.5
    assert hole_t[1] + hole_t[3] <= full[1] + 0.5
    assert hole_b[1] >= full[3] - 0.5


def test_camera_follows_viewport_change_and_map_center():
    h = Harness(viewport=(1280, 720))
    h.basic_state()
    h.w.advance(0.1)
    panel_landscape = h.rect("SidePanel")
    h.w.set_viewport(h.p, 720, 1280)  # rotate the phone
    h.w.advance(0.1)
    for x in (0, 104):
        for z in (0, 104):
            assert h.project(x, 1, z)[3]
    panel_portrait = h.rect("SidePanel")
    assert panel_portrait != panel_landscape
    assert panel_portrait[2] > panel_portrait[3]  # portrait: panel turns into a horizontal strip
    assert panel_landscape[3] > panel_landscape[2]
    # a different map center is followed too
    h.set_lua("MapCenter", "Vector3.new(152, 1, 52)")
    h.w.advance(0.1)
    px = h.w.eval("return workspace.CurrentCamera.CFrame.Position.X", h.p)
    assert abs(px - 152) < 1e-9
    h.assert_clean()


# =========================================================================== keyboard / gamepad input
@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
def test_keyboard_priority_stack_and_fire(behavior):
    h = Harness(signal_behavior=behavior)
    w, p = h.w, h.p
    w.key_down(p, "W")
    assert h.sent() == [(0, False)]
    w.key_down(p, "D")
    assert h.sent()[-1] == (1, False)
    w.key_up(p, "D")
    assert h.sent()[-1] == (0, False)
    w.key_up(p, "W")
    assert h.sent()[-1] == (-1, False)
    assert h.log() == [(0, False), (1, False), (0, False), (-1, False)]

    # arrow keys map like WASD; releasing an older key does not change the newest one
    w.key_down(p, "Left")
    w.key_down(p, "Down")
    w.key_up(p, "Left")
    w.key_up(p, "Down")
    w.key_down(p, "Right")
    w.key_up(p, "Right")
    w.key_down(p, "Up")
    w.key_up(p, "Up")
    w.key_down(p, "S")
    w.key_down(p, "A")
    w.key_up(p, "A")
    w.key_up(p, "S")
    assert h.sent()[4:] == [(3, False), (2, False), (-1, False), (1, False), (-1, False), (0, False), (-1, False),
                            (2, False), (3, False), (2, False), (-1, False)]

    # fire = Space, J, Z ; holding two fire keys and releasing one keeps firing ; no duplicates
    n = len(h.log())
    w.key_down(p, "Space")
    w.key_down(p, "J")
    w.key_up(p, "Space")
    w.key_down(p, "W")
    w.key_up(p, "J")
    w.key_up(p, "W")
    w.key_down(p, "Z")
    w.key_up(p, "Z")
    w.key_down(p, "E")  # not a game key
    w.key_up(p, "E")
    assert h.sent()[n:] == [(-1, True), (0, True), (0, False), (-1, False), (-1, True), (-1, False)]
    assert no_consecutive_duplicates(h.log())
    h.assert_clean()


@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
def test_game_processed_and_focus_loss_release_everything(behavior):
    h = Harness(signal_behavior=behavior)
    w, p = h.w, h.p
    # typing in chat: processed key presses are ignored
    w.key_down(p, "W", game_processed=True)
    w.key_down(p, "Space", game_processed=True)
    assert h.sent() == []
    w.key_up(p, "W", game_processed=True)
    w.key_up(p, "Space", game_processed=True)
    assert h.sent() == []

    # holding D + Space; a game key already taken by Roblox (e.g. sunk by ContextActionService) is just skipped
    w.key_down(p, "D")
    w.key_down(p, "Space")
    assert h.sent() == [(1, False), (1, True)]
    w.key_down(p, "Left", game_processed=True)
    w.key_up(p, "Left", game_processed=True)
    assert h.sent() == [(1, False), (1, True)]
    # chat starts (processed non-game key like "/") -> release everything
    w.key_down(p, "Slash", game_processed=True)
    assert h.sent()[-1] == (-1, False)
    w.key_down(p, "H", game_processed=True)  # typing...
    w.key_down(p, "W", game_processed=True)  # ...a word containing W must not move the tank
    w.key_up(p, "D", game_processed=True)
    w.key_up(p, "Space", game_processed=True)
    w.key_up(p, "Slash", game_processed=True)
    w.key_up(p, "H", game_processed=True)
    w.key_up(p, "W", game_processed=True)
    assert h.sent() == [(1, False), (1, True), (-1, False)]

    # window loses focus while holding keys -> release; the late key-ups send nothing new
    w.key_down(p, "W")
    w.key_down(p, "J")
    assert h.sent()[-1] == (0, True)
    fire_uis(w, p, "WindowFocusReleased")
    assert h.sent()[-1] == (-1, False)
    w.key_up(p, "W")
    w.key_up(p, "J")
    assert h.sent()[-3:] == [(0, False), (0, True), (-1, False)]
    assert no_consecutive_duplicates(h.log())
    h.assert_clean()


def test_gamepad_dpad_thumbstick_and_buttons():
    h = Harness(gamepad=True)
    w, p = h.w, h.p
    w.gamepad_button(p, "DPadUp", True)
    w.gamepad_button(p, "DPadRight", True)
    w.gamepad_button(p, "DPadRight", False)
    w.gamepad_button(p, "DPadUp", False)
    assert h.sent() == [(0, False), (1, False), (0, False), (-1, False)]
    n = len(h.log())
    w.thumbstick(p, 0.2, 0.3)  # inside the 0.5 dead zone
    w.thumbstick(p, 0.9, 0.4)  # right
    w.thumbstick(p, 0.3, -0.8)  # down (stick y up = +)
    w.thumbstick(p, -0.6, 0.55)  # left (dominant axis)
    w.thumbstick(p, 0.1, 0.95)  # up
    w.thumbstick(p, 0.0, 0.0)
    assert h.sent()[n:] == [(1, False), (2, False), (3, False), (0, False), (-1, False)]
    n = len(h.log())
    for b in ("ButtonA", "ButtonX", "ButtonR2"):
        w.gamepad_button(p, b, True)
        w.gamepad_button(p, b, False)
    assert h.sent()[n:] == [(-1, True), (-1, False)] * 3
    assert no_consecutive_duplicates(h.log())
    h.assert_clean()


# =========================================================================== touch input
@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
def test_touch_dpad_and_fire_multitouch(behavior):
    h = Harness(touch=True, viewport=(844, 390), signal_behavior=behavior)
    h.basic_state()
    h.w.advance(0.1)
    w, p = h.w, h.p
    assert h.shown("DPad") and h.shown("FireButton")
    assert not h.shown("HelpText")
    dx, dy, dw, dh = h.rect("DPad")
    fx, fy, fw, fh = h.rect("FireButton")
    # controls are on screen, D-pad bottom-left and FIRE bottom-right, not on top of each other
    assert dx >= 0 and dy + dh <= 390 - GUI_INSET + 0.5 and dw > 60
    assert fx + fw <= 844 + 0.5 and fx > dx + dw
    # field gets covered by nothing but the touch controls
    field = h.field_rect_gui()
    for path in ("ScoreArea", "SidePanel"):
        assert not overlaps(h.rect(path), field)
        assert not overlaps(h.rect(path), (dx, dy, dx + dw, dy + dh))
        assert not overlaps(h.rect(path), (fx, fy, fx + fw, fy + fh))

    t1 = w.touch_begin(p, h.gui("DPad"), dx + dw / 2, dy + dh * 0.1)  # top arm
    assert h.sent() == [(0, False)]
    t2 = w.touch_begin(p, h.gui("FireButton"))  # second finger
    assert h.sent()[-1] == (0, True)
    w.touch_move(p, t1, dx + dw * 0.95, dy + dh * 0.55)  # slide to the right arm
    assert h.sent()[-1] == (1, True)
    w.touch_move(p, t1, dx + dw * 2.0, dy + dh * 0.5)  # slid off the pad: still steering right
    w.touch_move(p, t1, dx + dw * 0.5, dy + dh * 0.95)  # down
    assert h.sent()[-1] == (2, True)
    w.touch_end(p, t2)
    assert h.sent()[-1] == (2, False)
    w.touch_move(p, t1, dx + dw * 0.05, dy + dh * 0.5)  # left
    w.touch_move(p, t1, dx + dw * 0.5, dy + dh * 0.5)  # centre = dead zone
    w.touch_end(p, t1)
    assert h.sent() == [(0, False), (0, True), (1, True), (2, True), (2, False), (3, False), (-1, False)]

    # a touch on the field (not on a control) does nothing; fallback hit-test via UserInputService works
    n = len(h.log())
    t3 = w.touch_begin(p, None, 422, 150)
    w.touch_end(p, t3)
    assert h.sent()[n:] == []
    t4 = w.touch_begin(p, None, fx + fw / 2, fy + fh / 2)
    assert h.sent()[n:] == [(-1, True)]
    w.touch_end(p, t4)
    assert h.sent()[n:] == [(-1, True), (-1, False)]

    # focus loss releases held touches too
    t5 = w.touch_begin(p, h.gui("DPad"), dx + dw * 0.5, dy + dh * 0.05)
    assert h.sent()[-1] == (0, False)
    fire_uis(w, p, "WindowFocusReleased")
    assert h.sent()[-1] == (-1, False)
    w.touch_end(p, t5)
    assert h.sent()[-1] == (-1, False) and h.log()[-2] == (0, False)
    assert no_consecutive_duplicates(h.log())
    h.assert_clean()


def test_touch_portrait_layout():
    h = Harness(touch=True, viewport=(390, 844))
    h.basic_state()
    h.w.advance(0.1)
    field = h.field_rect_gui()
    for path in ("ScoreArea", "SidePanel"):
        assert not overlaps(h.rect(path), field), path
    dx, dy, dw, dh = h.rect("DPad")
    assert dy >= field[3] - 0.5  # portrait: the D-pad sits below the field
    t1 = h.w.touch_begin(h.p, h.gui("DPad"), dx + dw * 0.1, dy + dh * 0.5)
    assert h.sent() == [(3, False)]
    h.w.touch_end(h.p, t1)
    assert h.sent() == [(3, False), (-1, False)]
    h.assert_clean()


# =========================================================================== HUD
def test_reserve_icons_lives_stage_scores():
    h = Harness()
    h.basic_state()
    h.phase("playing", ago=5)
    h.w.advance(0.1)

    def visible_icons():
        return sum(1 for k in range(1, 21) if h.shown("SidePanel.ReserveIcons.Reserve%d" % k))

    for left, expect in ((20, 20), (13, 13), (1, 1), (0, 0), (25, 20), (-3, 0), (7.6, 7)):
        h.set("EnemiesLeft", left)
        h.w.step()
        assert visible_icons() == expect, (left, visible_icons())
    h.set("EnemiesLeft", 13)
    h.w.step()
    # NES order: the last icons disappear first
    assert h.shown("SidePanel.ReserveIcons.Reserve13") and not h.shown("SidePanel.ReserveIcons.Reserve14")

    assert h.text("SidePanel.IPGroup.Lives") == "2"
    assert h.shown("SidePanel.IPGroup") and not h.shown("SidePanel.IIPGroup")
    assert not h.shown("ScoreArea.Score2P")
    h.set("P1Lives", 5)
    h.set("P2Present", True)
    h.set("P2Lives", 1)
    h.set("Stage", 12)
    h.set("P1Score", 1500)
    h.set("P2Score", 300)
    h.set("HiScore", 31000)
    h.w.step()
    assert h.text("SidePanel.IPGroup.Lives") == "5"
    assert h.shown("SidePanel.IIPGroup") and h.text("SidePanel.IIPGroup.Lives") == "1"
    assert h.text("SidePanel.StageGroup.StageNum") == "12"
    assert h.text("IntroOverlay.StageTextBox.StageText") == "STAGE 12"
    assert h.text("ScoreArea.Score1P") == "1500"
    assert h.text("ScoreArea.Score2P") == "300" and h.shown("ScoreArea.Score2P")
    assert h.text("ScoreArea.ScoreHI") == "31000"
    # only P2 left in the game -> IP block hides, IIP stays
    h.set("P1Present", False)
    h.w.step()
    assert not h.shown("SidePanel.IPGroup") and h.shown("SidePanel.IIPGroup")
    h.assert_clean()


def test_spectator_label():
    h = Harness(slot=None)
    h.basic_state()
    h.phase("playing", ago=3)
    h.w.advance(0.1)
    assert not h.shown("SpectatorLabel")  # slot not assigned yet
    h.w.call(h.p, "SetAttribute", "BattleCitySlot", 0)
    h.w.step()
    assert h.shown("SpectatorLabel")
    assert h.text("SpectatorLabel") == "SPECTATING (2 players max)"
    # promoted to a slot while holding a key -> label hides and the held input is re-sent for the new slot
    h.w.key_down(h.p, "W")
    assert h.sent() == [(0, False)]
    h.w.call(h.p, "SetAttribute", "BattleCitySlot", 2)
    assert h.sent() == [(0, False), (0, False)]
    assert not h.shown("SpectatorLabel")
    h.assert_clean()


TALLY_1P = {
    "stageNumber": 3, "gameOver": False,
    "players": [{"kills": [3, 1, 0, 2], "points": [300, 200, 0, 800], "totalKills": 6, "score": 4300, "bonus": 0}],
}
TALLY_2P = {
    "stageNumber": 4, "gameOver": False,
    "players": {
        "1": {"kills": [5, 2, 1, 0], "points": [500, 400, 300, 0], "totalKills": 8, "score": 12000, "bonus": 1000},
        "2": {"kills": [1, 0, 0, 4], "points": [100, 0, 0, 1600], "totalKills": 5, "score": 9100, "bonus": 0},
    },
}


@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
@pytest.mark.parametrize("start_first", [False, True])
def test_phase_overlays_through_every_phase(behavior, start_first):
    h = Harness(signal_behavior=behavior)
    h.w.step()
    # folder exists but nothing set yet -> waiting screen
    assert h.shown("WaitingScreen")
    assert h.text("WaitingScreen.Content.WaitingText") == "WAITING FOR PLAYERS"
    h.basic_state()
    h.phase("waiting", start_first=start_first)
    h.w.advance(0.05)
    assert_only_overlay(h, "waiting")

    # intro: curtain closes, then "STAGE 1"
    h.phase("intro", start_first=start_first)
    h.w.advance(0.1)
    assert_only_overlay(h, "intro")
    assert not h.shown("IntroOverlay.StageTextBox")
    top_y = h.w.value(h.w.get(h.gui("IntroOverlay.CurtainTop"), "Position"))[2]
    assert -0.51 < top_y < 0  # half-way closing
    h.w.advance(0.6)
    assert h.shown("IntroOverlay.StageTextBox")
    assert h.text("IntroOverlay.StageTextBox.StageText") == "STAGE 1"
    assert abs(h.w.value(h.w.get(h.gui("IntroOverlay.CurtainTop"), "Position"))[2]) < 1e-6
    assert abs(h.w.value(h.w.get(h.gui("IntroOverlay.CurtainBottom"), "Position"))[2] - 0.49) < 1e-6
    h.w.advance(1.7)

    # playing: the curtain opens (0.5 s) and then nothing covers the field
    h.phase("playing", start_first=start_first)
    h.w.advance(0.1)
    assert h.shown("IntroOverlay") and not h.shown("IntroOverlay.StageTextBox")
    h.w.advance(0.5)
    assert_only_overlay(h, None)
    assert h.w.value(h.w.get(h.gui("IntroOverlay.CurtainTop"), "Position"))[2] <= -0.51 + 1e-6

    h.phase("stageClear", start_first=start_first)
    h.w.advance(0.2)
    assert_only_overlay(h, None)

    # gameOver: red GAME OVER rises from the bottom of the field to its centre
    h.phase("gameOver", start_first=start_first)
    h.set("GameOver", True)
    h.w.advance(0.1)
    assert_only_overlay(h, "gameOver")
    y1 = h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2]
    h.w.advance(1.0)
    y2 = h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2]
    assert 1.2 > y1 > y2 > 0.5
    h.w.advance(2.0)
    assert abs(h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2] - 0.5) < 1e-6

    # tally: black score screen with count-up
    h.set("Tally", json.dumps(TALLY_1P))
    h.phase("tally", start_first=start_first)
    h.w.advance(0.1)
    assert_only_overlay(h, "tally")
    assert not h.shown("TallyScreen.Content.Row1")  # rows appear one after another
    assert not h.shown("TallyScreen.Content.TotalP1")
    h.w.advance(0.55)
    assert h.shown("TallyScreen.Content.Row1")
    assert int(h.text("TallyScreen.Content.Row1.P1Kills")) < 3  # still counting
    h.w.advance(4.5)
    assert_tally_1p(h)

    h.phase("final", start_first=start_first)
    h.w.advance(0.1)
    assert_only_overlay(h, "final")
    h.phase("intro", start_first=start_first)
    h.w.advance(0.1)
    assert_only_overlay(h, "intro")
    h.assert_clean()


def assert_tally_1p(h):
    c = "TallyScreen.Content."
    assert h.text(c + "StageLabel") == "STAGE 3"
    assert h.text(c + "HiValue") == "20000"
    assert h.text(c + "P1Score") == "4300" and h.shown(c + "P1Name")
    assert not h.shown(c + "P2Name") and not h.shown(c + "P2Score")
    for r, (k, pts) in enumerate(((3, 300), (1, 200), (0, 0), (2, 800)), start=1):
        assert h.shown(c + "Row%d" % r)
        assert h.text(c + "Row%d.P1Kills" % r) == str(k)
        assert h.text(c + "Row%d.P1Pts" % r) == str(pts)
        assert not h.shown(c + "Row%d.P2Kills" % r)
        assert h.shown(c + "Row%d.Icon" % r) and h.shown(c + "Row%d.ArrowLeft" % r)
    assert h.shown(c + "TotalP1") and h.text(c + "TotalP1") == "6"
    assert not h.shown(c + "TotalP2")
    assert not h.shown(c + "BonusP1") and not h.shown(c + "BonusP2")


def test_tally_two_players_bonus_and_mid_phase_join():
    # the client joins 5 s into the tally: it must show the finished count immediately
    h = Harness(start_client=False)
    h.basic_state()
    h.set("HiScore", 12000)
    h.set("Tally", json.dumps(TALLY_2P))
    h.phase("tally", ago=5.0)
    h.start()
    h.w.advance(0.05)
    assert_only_overlay(h, "tally")
    c = "TallyScreen.Content."
    assert h.text(c + "StageLabel") == "STAGE 4"
    assert h.text(c + "HiValue") == "12000"
    assert h.text(c + "P1Score") == "12000" and h.text(c + "P2Score") == "9100"
    expect = {1: ((5, 500), (1, 100)), 2: ((2, 400), (0, 0)), 3: ((1, 300), (0, 0)), 4: ((0, 0), (4, 1600))}
    for r, ((k1, p1), (k2, p2)) in expect.items():
        assert (h.text(c + "Row%d.P1Kills" % r), h.text(c + "Row%d.P1Pts" % r)) == (str(k1), str(p1))
        assert (h.text(c + "Row%d.P2Kills" % r), h.text(c + "Row%d.P2Pts" % r)) == (str(k2), str(p2))
        assert h.shown(c + "Row%d.ArrowRight" % r)
    assert h.text(c + "TotalP1") == "8" and h.text(c + "TotalP2") == "5"
    assert h.shown(c + "BonusP1") and h.text(c + "BonusP1.Value") == "1000 PTS"
    assert not h.shown(c + "BonusP2")
    # tally arrives AFTER the phase (any order) and then gets replaced by garbage: never errors
    h.set("Tally", "{not json")
    h.w.step()
    assert not h.shown(c + "P1Name")
    h.set("Tally", "")
    h.w.step()
    h.set("Tally", json.dumps({"players": [{"kills": "x", "points": None, "score": "big"}], "stageNumber": "?"}))
    h.w.step()
    assert h.text(c + "Row1.P1Kills") == "0"
    h.set("Tally", json.dumps([1, 2, 3]))
    h.w.step()
    h.assert_clean()


@pytest.mark.parametrize("phase,ago", [("intro", 1.0), ("gameOver", 3.0), ("playing", 0.25), ("final", 1.0)])
def test_mid_phase_join_shows_right_moment(phase, ago):
    h = Harness(start_client=False)
    h.basic_state()
    h.phase(phase, ago=ago)
    h.start()
    h.w.step()
    if phase == "intro":
        assert_only_overlay(h, "intro")
        assert h.shown("IntroOverlay.StageTextBox")
        assert abs(h.w.value(h.w.get(h.gui("IntroOverlay.CurtainTop"), "Position"))[2]) < 1e-6
    elif phase == "gameOver":
        assert_only_overlay(h, "gameOver")
        assert abs(h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2] - 0.5) < 1e-6
    elif phase == "playing":
        # half-way through opening the curtain
        y = h.w.value(h.w.get(h.gui("IntroOverlay.CurtainTop"), "Position"))[2]
        assert h.shown("IntroOverlay") and -0.4 < y < -0.1
        h.w.advance(0.3)
        assert_only_overlay(h, None)
    else:
        assert_only_overlay(h, "final")
    h.assert_clean()


def test_robust_to_missing_folder_bad_attributes_and_order():
    # client starts before the server made the folder
    h = Harness(make_folder=False, slot=None)
    h.w.key_down(h.p, "W")  # pressed while there is no remote yet
    h.w.advance(1.0)
    assert h.shown("WaitingScreen")
    assert h.text("WaitingScreen.Content.WaitingText") == "LOADING..."
    assert h.w.eval("return workspace.CurrentCamera.CameraType.Name", h.p) == "Scriptable"
    h.make_folder()
    h.w.advance(0.1)
    # the key held before the remote existed is delivered once the remote is there
    assert h.log() == [(0, False)]
    h.w.key_up(h.p, "W")
    assert h.sent() == [(0, False), (-1, False)]
    # attributes with wrong types / missing values / any order
    h.set("PhaseStartedAt", "soon")
    h.set("EnemiesLeft", "many")
    h.set("P1Lives", True)
    h.set("Stage", float("nan"))
    h.set_lua("MapCenter", '"center"')
    h.set_lua("MapSize", "Vector3.new(0, 0, 0)")
    h.set("Tally", "[")
    h.set("Phase", "tally")
    h.w.advance(0.5)
    h.set("Phase", "somethingNew")
    h.w.advance(0.1)
    assert_only_overlay(h, None)
    h.set("Phase", "gameOver")
    h.w.advance(0.1)
    h.set("PhaseStartedAt", None)
    h.set("Phase", None)
    h.w.advance(0.1)
    assert h.shown("WaitingScreen")
    # camera falls back to the spec's map when MapCenter/MapSize are unusable
    px, pz = h.w.eval("local p = workspace.CurrentCamera.CFrame.Position return p.X, p.Z", h.p)
    assert abs(px - 52) < 1e-9 and pz > 52
    h.assert_clean()


def test_two_players_each_send_their_own_input():
    h = Harness(name="Alice")
    bob = h.w.add_player("Bob", 2)
    h.w.call(bob, "SetAttribute", "BattleCitySlot", 2)
    h.start(bob)
    h.basic_state()
    h.set("P2Present", True)
    h.set("P2Lives", 2)
    h.phase("playing", ago=2)
    h.w.advance(0.1)
    h.w.key_down(h.p, "W")
    h.w.key_down(bob, "Left")
    h.w.key_down(bob, "Space")
    h.w.step()
    assert h.log("Alice") == [(0, False)]
    assert h.log("Bob") == [(3, False), (3, True)]
    assert h.w.is_on_screen(h.gui("SidePanel.IIPGroup", "Bob"), bob)
    # each client colours its own label
    yellow = h.w.value(h.w.get(h.gui("ScoreArea.Label1P", "Alice"), "TextColor3"))
    green = h.w.value(h.w.get(h.gui("ScoreArea.Label2P", "Bob"), "TextColor3"))
    assert yellow != green
    h.assert_clean()


@pytest.mark.parametrize("players_json", [
    '{"2": %s}', '{"P2": %s}', '[null, %s]', '[false, %s]',
])
def test_tally_only_second_player(players_json):
    p2 = json.dumps({"kills": [2, 0, 1, 0], "points": [200, 0, 300, 0], "totalKills": 3, "score": 700, "bonus": 0})
    tally = '{"stageNumber": 2, "gameOver": true, "players": %s}' % (players_json % p2)
    h = Harness(slot=2)
    h.basic_state()
    h.set("Tally", tally)
    h.phase("tally", ago=5.5)
    h.w.advance(0.05)
    c = "TallyScreen.Content."
    assert not h.shown(c + "P1Name") and h.shown(c + "P2Name")
    assert h.text(c + "P2Score") == "700"
    assert [h.text(c + "Row%d.P2Kills" % r) for r in range(1, 5)] == ["2", "0", "1", "0"]
    assert [h.text(c + "Row%d.P2Pts" % r) for r in range(1, 5)] == ["200", "0", "300", "0"]
    assert h.text(c + "TotalP2") == "3" and not h.shown(c + "TotalP1")
    h.assert_clean()


# =========================================================================== end-to-end with the real core
# Test-only mini server: plays the server's role with the REAL BattleCityCore (not the real server adapter),
# publishing the spec's attributes, so the client is checked against real core data shapes.
MINI_SERVER = r"""
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
Players.CharacterAutoLoads = false
local Core = require(game:GetService("ServerScriptService"):WaitForChild("BattleCityCore"))
local map = {}
for i = 1, 26 do map[i] = string.rep(".", 26) end
local g = Core.new({ stages = { { name = "Test", map = map, enemies = "bbbbbbbbbbbbbbbbbbbb" } }, seed = 3,
    config = { INTRO_TIME = 0.5, GAMEOVER_TIME = 1.5, TALLY_TIME = 6, FINAL_TIME = 1, ENEMIES_PER_STAGE = 1 } })
local folder = Instance.new("Folder")
folder.Name = "BattleCity"
local input = Instance.new("RemoteEvent")
input.Name = "Input"
input.Parent = folder
folder:SetAttribute("MapCenter", Vector3.new(52, 1, 52))
folder:SetAttribute("MapSize", Vector3.new(104, 0, 104))
folder.Parent = RS
local slots = {}
local function set(name, v)
    if folder:GetAttribute(name) ~= v then folder:SetAttribute(name, v) end
end
Players.PlayerAdded:Connect(function(p)
    local slot = 0
    if slots[1] == nil then slot = 1 elseif slots[2] == nil then slot = 2 end
    if slot > 0 then slots[slot] = p; g:addPlayer(slot) end
    p:SetAttribute("BattleCitySlot", slot)
end)
input.OnServerEvent:Connect(function(p, dir, fire)
    for s = 1, 2 do if slots[s] == p then g:setInput(s, dir, fire) end end
end)
local acc, lastPhase = 0, nil
RunService.Heartbeat:Connect(function(dt)
    acc = math.min(acc + dt, 0.25)
    while acc >= 1 / 60 - 1e-9 do g:step(1 / 60); acc = acc - 1 / 60 end
    g:popEvents()
    if g.phase ~= lastPhase then
        lastPhase = g.phase
        set("PhaseStartedAt", workspace:GetServerTimeNow())
        set("Phase", g.phase)
    end
    set("Stage", g.stageNumber)
    set("EnemiesLeft", g.enemiesInReserve)
    set("HiScore", g.hiScore)
    set("GameOver", g.isGameOver == true)
    for s = 1, 2 do
        local p = g.players[s]
        set("P" .. s .. "Present", p ~= nil)
        set("P" .. s .. "Lives", p and p.lives or 0)
        set("P" .. s .. "Score", p and p.score or 0)
    end
    set("Tally", g.tally and HttpService:JSONEncode(g.tally) or "")
end)
"""


def test_end_to_end_with_real_core():
    w = World()
    w.add_module("ServerScriptService", "BattleCityCore", luaenv.path("BattleCityCore.lua"))
    ok, err, _ = w.run_source(MINI_SERVER)
    assert ok, err
    p = w.add_player("Alice", 1)
    ok, err, _ = w.run_local_script(CLIENT, p)
    assert ok, err
    h = Harness.__new__(Harness)  # reuse the GUI helpers on this world
    h.w, h.p, h.name = w, p, "Alice"

    def wait_phase(name, limit):
        for _ in range(int(limit * 60)):
            if w.attr("ReplicatedStorage.BattleCity", "Phase") == name:
                return
            w.step()
        raise AssertionError("phase %s not reached (now %s)" % (name, w.attr("ReplicatedStorage.BattleCity", "Phase")))

    wait_phase("intro", 1)
    w.advance(0.1)
    assert_only_overlay(h, "intro")
    wait_phase("playing", 2)
    w.advance(0.7)
    assert_only_overlay(h, None)
    assert h.text("SidePanel.IPGroup.Lives") == "2"
    assert h.text("SidePanel.StageGroup.StageNum") == "1"
    # drive the tank with the client: face right toward the eagle and keep firing -> base destroyed
    w.key_down(p, "D")
    w.key_down(p, "Space")
    wait_phase("gameOver", 8)
    w.advance(0.1)
    assert_only_overlay(h, "gameOver")
    wait_phase("tally", 4)
    w.advance(5.5)
    assert_only_overlay(h, "tally")
    tally = json.loads(w.attr("ReplicatedStorage.BattleCity", "Tally"))
    me = tally["players"][0]
    c = "TallyScreen.Content."
    assert h.text(c + "P1Score") == str(me["score"])
    for r in range(1, 5):
        assert h.text(c + "Row%d.P1Kills" % r) == str(me["kills"][r - 1])
        assert h.text(c + "Row%d.P1Pts" % r) == str(me["points"][r - 1])
    assert h.text(c + "TotalP1") == str(me["totalKills"])
    wait_phase("final", 2)
    w.advance(0.1)
    assert_only_overlay(h, "final")
    wait_phase("intro", 3)  # a player is present -> new game
    w.advance(0.1)
    assert_only_overlay(h, "intro")
    assert w.attr("ReplicatedStorage.BattleCity", "Stage") == 1 and w.attr("ReplicatedStorage.BattleCity", "GameOver") is False
    h.assert_clean()


def test_phase_start_time_arriving_late():
    # Phase changes first; PhaseStartedAt of the new phase arrives a few frames later (attributes in any order)
    h = Harness()
    h.basic_state()
    h.phase("playing", ago=30)
    h.w.advance(0.1)
    h.set("Phase", "gameOver")  # PhaseStartedAt still holds the old phase's value (30 s ago)
    h.w.advance(0.25)
    y = h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2]
    assert y > 1.0, y  # just started rising, not jumped to the end because of the stale start time
    h.set("PhaseStartedAt", h.now() - 0.25)
    h.w.advance(0.05)
    y2 = h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2]
    assert 0.5 < y2 < 1.2 and abs(y2 - (1.2 - 0.7 * 0.3 / 2.5)) < 0.03, y2
    h.w.advance(3.0)
    assert abs(h.w.value(h.w.get(h.gui("FieldFrame.GameOverRise"), "Position"))[2] - 0.5) < 1e-6
    h.assert_clean()


# =========================================================================== integration with the real server script
TINY_STAGES = """
local map = {}
for i = 1, 26 do map[i] = string.rep(".", 26) end
return { { name = "Test", map = map, enemies = "bbbbbbbbbbbbbbbbbbbb" } }
"""


@pytest.mark.skipif(not os.path.exists(luaenv.path("BattleCityServer.lua")), reason="server script not written yet")
def test_with_real_server_script():
    w = World()
    w.add_module("ServerScriptService", "BattleCityCore", luaenv.path("BattleCityCore.lua"))
    w.add_module_source("ServerScriptService", "BattleCityStages", TINY_STAGES)
    # ตัวจริงของผู้ใช้อยู่ใน StarterPlayerScripts (ไม่งั้น server จะเตือนว่าวางผิดที่)
    w.eval("local s = Instance.new('LocalScript'); s.Name = 'BattleCityClient'; "
           "s.Parent = game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')")
    ok, err, _ = w.run_script(luaenv.path("BattleCityServer.lua"))
    assert ok, err
    p = w.add_player("Alice", 1)
    ok, err, _ = w.run_local_script(CLIENT, p)
    assert ok, err
    h = Harness.__new__(Harness)
    h.w, h.p, h.name = w, p, "Alice"

    def wait_phase(name, limit):
        for _ in range(int(limit * 60)):
            if w.attr("ReplicatedStorage.BattleCity", "Phase") == name:
                return
            w.step()
        raise AssertionError("phase %s not reached (now %s)" % (name, w.attr("ReplicatedStorage.BattleCity", "Phase")))

    wait_phase("intro", 2)
    w.advance(0.1)
    assert_only_overlay(h, "intro")
    wait_phase("playing", 10)
    w.advance(1.5)
    assert_only_overlay(h, None)
    assert w.attr(p, "BattleCitySlot") == 1
    assert w.eval("return workspace.CurrentCamera.CameraType.Name", p) == "Scriptable"
    visible = sum(1 for k in range(1, 21) if h.shown("SidePanel.ReserveIcons.Reserve%d" % k))
    assert visible == w.attr("ReplicatedStorage.BattleCity", "EnemiesLeft")
    w.key_down(p, "D")  # the client steers the real server's tank into its own eagle
    w.key_down(p, "Space")
    wait_phase("gameOver", 15)
    w.advance(0.1)
    assert_only_overlay(h, "gameOver")
    wait_phase("tally", 10)
    w.advance(5.6)
    assert_only_overlay(h, "tally")
    me = json.loads(w.attr("ReplicatedStorage.BattleCity", "Tally"))["players"][0]
    assert h.text("TallyScreen.Content.P1Score") == str(int(me["score"]))
    assert h.text("TallyScreen.Content.TotalP1") == str(int(me["totalKills"]))
    w.assert_no_errors()
    assert not [x for x in w.warnings() if "BattleCityClient" in x]
