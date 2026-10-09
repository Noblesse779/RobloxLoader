"""Tests of the Roblox emulation itself (roblox_stubs.lua + roblox_env.py).

    python -m pytest -q BattleCity/tests/test_stubs.py
"""
import math
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402
from roblox_env import STUBS_PATH, World  # noqa: E402

approx = pytest.approx


@pytest.fixture
def w():
    return World()


def ok_eval(w, code, player=None):
    ok, vals = w.try_eval(code, player)
    assert ok, vals
    return vals


def err_eval(w, code, player=None):
    ok, vals = w.try_eval(code, player)
    assert not ok, "expected an error from: " + code
    return vals[0]


def vec(w, code, player=None):
    return w.value(w.eval(code, player))


# ============================================================================ loading
def test_stubs_load_without_touching_globals():
    lua = luaenv.new_runtime()
    lua.execute(
        """
        setmetatable(_G, {
          __newindex = function(_, k) error("stubs wrote global " .. tostring(k), 2) end,
          __index = function(_, k) error("stubs read undefined global " .. tostring(k), 2) end,
        })"""
    )
    stubs = luaenv.load_file(lua, STUBS_PATH)
    world = stubs.newWorld(None)
    assert world.time == 0


# ============================================================================ datatypes: math conventions
@pytest.mark.parametrize("a", [0.0, 0.3, math.pi / 2, 2.0, -1.2, math.pi])
def test_cframe_angles_y_lookvector(w, a):
    lv = vec(w, "return CFrame.Angles(0, %r, 0).LookVector" % a)
    assert lv == approx((-math.sin(a), 0, -math.cos(a)), abs=1e-12)


def test_cframe_lookat_default_up(w):
    comps = vec(w, "return CFrame.lookAt(Vector3.new(1, 2, 3), Vector3.new(1, 2, -7))")
    assert comps == approx((1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1), abs=1e-12)
    look, up, right = w.eval(
        "local c = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(10, 0, 0)); return c.LookVector, c.UpVector, c.RightVector"
    )
    assert w.value(look) == approx((1, 0, 0), abs=1e-12)
    assert w.value(up) == approx((0, 1, 0), abs=1e-12)
    assert w.value(right) == approx((0, 0, 1), abs=1e-12)
    # CFrame.new(pos, lookAt) == CFrame.lookAt(pos, lookAt)
    assert w.eval(
        "local a, b = Vector3.new(3, 4, 5), Vector3.new(-2, 7, 1); return CFrame.new(a, b):FuzzyEq(CFrame.lookAt(a, b))"
    )


def test_cframe_lookat_straight_down_is_valid(w):
    comps = vec(w, "return CFrame.lookAt(Vector3.new(0, 10, 0), Vector3.new(0, 0, 0))")
    assert comps == approx((0, 10, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0), abs=1e-12)


def test_cframe_composition_and_inverse(w):
    assert w.eval(
        """
        local a = CFrame.new(1, 2, 3) * CFrame.Angles(0.3, -1.1, 0.7)
        local b = CFrame.new(-4, 5, 6) * CFrame.fromEulerAnglesYXZ(0.2, 0.4, -0.9)
        local okInv = (a * a:Inverse()):FuzzyEq(CFrame.identity, 1e-9)
        local okObj = a:ToWorldSpace(a:ToObjectSpace(b)):FuzzyEq(b, 1e-9)
        local p = Vector3.new(7, -3, 2)
        local okPoint = a:PointToWorldSpace(a:PointToObjectSpace(p)):FuzzyEq(p, 1e-9)
        local okMul = (a * p):FuzzyEq(a:PointToWorldSpace(p), 1e-12)
        local okVec = a:VectorToWorldSpace(Vector3.new(0, 0, -1)):FuzzyEq(a.LookVector, 1e-12)
        local okAdd = (a + Vector3.new(1, 0, 0)).Position:FuzzyEq(a.Position + Vector3.new(1, 0, 0), 1e-12)
        return okInv and okObj and okPoint and okMul and okVec and okAdd
        """
    )


def test_cframe_euler_round_trips(w):
    xyz = w.eval("return CFrame.Angles(0.3, -0.5, 1.1):ToEulerAnglesXYZ()")
    assert xyz == approx((0.3, -0.5, 1.1), abs=1e-9)
    yxz = w.eval("return CFrame.fromEulerAnglesYXZ(0.3, -0.5, 1.1):ToEulerAnglesYXZ()")
    assert yxz == approx((0.3, -0.5, 1.1), abs=1e-9)
    assert w.eval("return CFrame.fromOrientation(0.3, -0.5, 1.1):FuzzyEq(CFrame.fromEulerAnglesYXZ(0.3, -0.5, 1.1))")
    # fromAxisAngle around Y == Angles(0, a, 0)
    assert w.eval("return CFrame.fromAxisAngle(Vector3.new(0, 2, 0), 0.8):FuzzyEq(CFrame.Angles(0, 0.8, 0), 1e-12)")
    # 12 component constructor and GetComponents
    comps = w.eval("return CFrame.new(1, 2, 3, 1, 0, 0, 0, 0, -1, 0, 1, 0):GetComponents()")
    assert comps == (1, 2, 3, 1, 0, 0, 0, 0, -1, 0, 1, 0)


def test_cframe_lerp(w):
    mid = w.eval(
        """
        local a = CFrame.new(0, 0, 0)
        local b = CFrame.new(10, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
        local m = a:Lerp(b, 0.5)
        local rx, ry, rz = m:ToEulerAnglesYXZ()
        return m.X, ry
        """
    )
    assert mid == approx((5, math.pi / 4), abs=1e-9)


def test_part_orientation_consistent_with_cframe(w):
    vals = w.eval(
        """
        local p = Instance.new("Part")
        p.CFrame = CFrame.new(1, 2, 3) * CFrame.fromOrientation(math.rad(10), math.rad(20), math.rad(30))
        local o = p.Orientation
        p.Position = Vector3.new(5, 6, 7)
        local keepRot = p.Orientation:FuzzyEq(o, 1e-9)
        p.Orientation = Vector3.new(0, 90, 0)
        return o.X, o.Y, o.Z, keepRot, p.CFrame.LookVector.X, p.Position.Z
        """
    )
    assert vals[:3] == approx((10, 20, 30), abs=1e-9)
    assert vals[3] is True
    assert vals[4] == approx(-1, abs=1e-12)
    assert vals[5] == 7


def test_vector3_math(w):
    assert vec(w, "return Vector3.new(1, 2, 3) + Vector3.new(4, 5, 6)") == (5, 7, 9)
    assert vec(w, "return Vector3.new(1, 2, 3) - Vector3.new(4, 5, 6)") == (-3, -3, -3)
    assert vec(w, "return Vector3.new(1, 2, 3) * 2") == (2, 4, 6)
    assert vec(w, "return 2 * Vector3.new(1, 2, 3)") == (2, 4, 6)
    assert vec(w, "return Vector3.new(1, 2, 3) * Vector3.new(2, 3, 4)") == (2, 6, 12)
    assert vec(w, "return Vector3.new(2, 4, 6) / 2") == (1, 2, 3)
    assert vec(w, "return -Vector3.new(1, -2, 3)") == (-1, 2, -3)
    assert w.eval("return Vector3.new(3, 4, 0).Magnitude") == 5
    assert vec(w, "return Vector3.new(3, 4, 0).Unit") == approx((0.6, 0.8, 0))
    assert w.eval("return Vector3.new(1, 2, 3):Dot(Vector3.new(4, 5, 6))") == 32
    assert vec(w, "return Vector3.xAxis:Cross(Vector3.yAxis)") == (0, 0, 1)
    assert vec(w, "return Vector3.new(0, 0, 0):Lerp(Vector3.new(10, 20, 30), 0.25)") == (2.5, 5, 7.5)
    assert w.eval("return Vector3.new(1, 2, 3):FuzzyEq(Vector3.new(1, 2, 3.000001))") is True
    assert vec(w, "return Vector3.new(1, 5, 3):Min(Vector3.new(2, 1, 9))") == (1, 1, 3)
    assert vec(w, "return Vector3.new(1, 5, 3):Max(Vector3.new(2, 1, 9))") == (2, 5, 9)
    assert vec(w, "return Vector3.new(-1.5, 2.5, -3):Abs()") == (1.5, 2.5, 3)
    assert vec(w, "return Vector3.new(-1.5, 2.5, 3.2):Floor()") == (-2, 2, 3)
    assert w.eval("return Vector3.new(1, 2, 3) == Vector3.new(1, 2, 3), Vector3.new(1, 2, 3) == Vector3.new(1, 2, 4)") == (True, False)
    assert w.eval("return tostring(Vector3.new(1, 2.5, -3))") == "1, 2.5, -3"
    assert w.eval("return Vector3.zero == Vector3.new(), Vector3.one == Vector3.new(1, 1, 1)") == (True, True)
    assert w.eval("local v = Vector3.new(1, 2, 3); return v.X, v.Y, v.Z, v.x") == (1, 2, 3, 1)
    assert "arithmetic" in err_eval(w, "return Vector3.new() + 1")
    assert "cannot be assigned" in err_eval(w, "local v = Vector3.new(); v.X = 1")
    assert "not a valid member" in err_eval(w, "return Vector3.new().Length")


def test_vector2_udim2_color3(w):
    assert vec(w, "return Vector2.new(1, 2) + Vector2.new(3, 4)") == (4, 6)
    assert w.eval("return Vector2.new(3, 4).Magnitude, Vector2.new(1, 0):Cross(Vector2.new(0, 1))") == (5, 1)
    assert vec(w, "return UDim2.fromScale(0.5, 1)") == (0.5, 0, 1, 0)
    assert vec(w, "return UDim2.fromOffset(10, 20)") == (0, 10, 0, 20)
    assert vec(w, "return UDim2.new(0.5, 10, 1, -20) + UDim2.new(0, 5, 0, 5)") == (0.5, 15, 1, -15)
    assert vec(w, "return UDim2.new(0, 0, 0, 0):Lerp(UDim2.new(1, 100, 1, 100), 0.5)") == (0.5, 50, 0.5, 50)
    assert w.eval("local u = UDim2.new(0.5, 10, 1, -20); return u.X.Scale, u.X.Offset, u.Height.Offset") == (0.5, 10, -20)
    assert w.eval("return tostring(UDim2.new(0.5, 10, 1, -20))") == "{0.5, 10}, {1, -20}"
    assert vec(w, "return Color3.fromRGB(255, 0, 51)") == approx((1, 0, 0.2))
    h, s, v = w.eval("return Color3.fromHSV(0.25, 0.5, 0.8):ToHSV()")
    assert (h, s, v) == approx((0.25, 0.5, 0.8))
    assert w.eval("return Color3.fromHex('#FF8000'):ToHex()") == "ff8000"
    assert vec(w, "return Color3.new(0, 0, 0):Lerp(Color3.new(1, 1, 1), 0.5)") == (0.5, 0.5, 0.5)
    assert w.eval("return BrickColor.new('Bright red').Name, BrickColor.new('Bright red').Number") == ("Bright red", 21)


def test_tweeninfo_defaults(w):
    vals = w.eval("local t = TweenInfo.new(); return t.Time, t.EasingStyle, t.EasingDirection, t.RepeatCount, t.Reverses, t.DelayTime")
    assert vals[0] == 1 and w.value(vals[1]) == "Enum.EasingStyle.Quad" and w.value(vals[2]) == "Enum.EasingDirection.Out"
    assert vals[3:] == (0, False, 0)
    assert "EasingStyle" in err_eval(w, "return TweenInfo.new(1, Enum.EasingDirection.In)")


def test_typeof_names(w):
    names = w.eval(
        """
        local rs = game:GetService("RunService")
        local c = rs.Heartbeat:Connect(function() end)
        return typeof(Instance.new("Part")), typeof(Vector3.new()), typeof(Vector2.new()), typeof(CFrame.new()),
            typeof(Color3.new()), typeof(UDim.new()), typeof(UDim2.new()), typeof(Enum.KeyCode.W), typeof(Enum.KeyCode),
            typeof(Enum), typeof(rs.Heartbeat), typeof(c), typeof(TweenInfo.new()), typeof(BrickColor.new("White")),
            typeof(NumberSequence.new(1)), typeof(ColorSequence.new(Color3.new())), typeof(NumberRange.new(1)),
            typeof(Rect.new(0, 0, 1, 1)), typeof(RaycastParams.new()), typeof(nil), typeof({}), typeof(1),
            type(Vector3.new()), type(CFrame.new()), type(Instance.new("Folder"))
        """
    )
    assert names == (
        "Instance", "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "EnumItem", "Enum", "Enums",
        "RBXScriptSignal", "RBXScriptConnection", "TweenInfo", "BrickColor", "NumberSequence", "ColorSequence",
        "NumberRange", "Rect", "RaycastParams", "nil", "table", "number", "vector", "userdata", "userdata",
    )


# ============================================================================ enums
def test_enums(w):
    assert w.eval("return tostring(Enum.KeyCode.W), Enum.KeyCode.W.Name, Enum.KeyCode.W.Value") == ("Enum.KeyCode.W", "W", 119)
    assert w.eval("return Enum.KeyCode.ButtonA.Value, Enum.KeyCode.Space.Value, Enum.KeyCode.Up.Value") == (1002, 32, 273)
    assert w.eval("return Enum.KeyCode.W == Enum.KeyCode.W, Enum.KeyCode.W.EnumType == Enum.KeyCode, Enum.KeyCode.W:IsA('KeyCode')") == (True, True, True)
    prio = w.eval(
        "local r = Enum.RenderPriority; return r.First.Value, r.Input.Value, r.Camera.Value, r.Character.Value, r.Last.Value"
    )
    assert prio == (0, 100, 200, 300, 2000)
    assert w.eval("return Enum.Material.Plastic.Value, Enum.Material.Neon.Name, Enum.Font.Arcade.Name") == (256, "Neon", "Arcade")
    for typo in ["Enum.KeyCode.Spacebar", "Enum.Material.Steel", "Enum.Font.Arcadee", "Enum.EasingStyle.Quadratic"]:
        assert "not a valid member" in err_eval(w, "return " + typo)
    assert "not a valid member" in err_eval(w, "return Enum.KeyCodes.W")
    assert w.eval("return #Enum.NormalId:GetEnumItems(), Enum.CameraType:FromName('Scriptable') == Enum.CameraType.Scriptable") == (6, True)
    for name in ["A", "Z", "Zero", "Nine", "Left", "Right", "Return", "Escape", "Tab", "LeftShift", "ButtonB", "ButtonX",
                 "ButtonY", "ButtonR1", "ButtonR2", "ButtonL1", "ButtonL2", "ButtonStart", "ButtonSelect", "DPadUp",
                 "DPadDown", "DPadLeft", "DPadRight", "Thumbstick1", "Thumbstick2", "Unknown"]:
        ok_eval(w, "return Enum.KeyCode." + name)
    for name in ["SmoothPlastic", "WoodPlanks", "DiamondPlate", "CorrodedMetal", "ForceField", "Glass", "Air", "Water", "Ice"]:
        ok_eval(w, "return Enum.Material." + name)


# ============================================================================ instances
def test_instance_new_errors(w):
    assert 'Unable to create an Instance of type "Partt"' in err_eval(w, "Instance.new('Partt')")
    assert "Unable to create an Instance" in err_eval(w, "Instance.new('BasePart')")
    assert "Unable to create an Instance" in err_eval(w, "Instance.new('Players')")
    assert w.eval("return Instance.new('Part', workspace).Parent == workspace") is True


def test_part_defaults(w):
    vals = w.eval(
        """
        local p = Instance.new("Part")
        return p.Size, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Transparency, p.Material,
            p.Color, p.Name, p.ClassName, p.Parent, p.Shape, p.BrickColor
        """
    )
    v = [w.value(x) for x in vals]
    assert v[0] == approx((4, 1.2, 2))
    assert v[1:7] == [False, True, True, True, True, 0]
    assert v[7] == "Enum.Material.Plastic"
    assert v[8] == approx((163 / 255, 162 / 255, 165 / 255))
    assert v[9:12] == ["Part", "Part", None]
    assert v[12] == "Enum.PartType.Block"
    assert v[13] == "Medium stone grey"


def test_gui_defaults(w):
    v = [w.value(x) for x in w.eval(
        """
        local f = Instance.new("Frame")
        local t = Instance.new("TextLabel")
        local g = Instance.new("ScreenGui")
        return f.Size, f.Position, f.AnchorPoint, f.Visible, f.BackgroundTransparency, f.ZIndex, f.LayoutOrder,
            t.Text, t.TextScaled, t.Font, t.TextSize, t.Size, g.ResetOnSpawn, g.IgnoreGuiInset, g.Enabled, g.DisplayOrder
        """
    )]
    assert v[0] == (0, 100, 0, 100) and v[1] == (0, 0, 0, 0) and v[2] == (0, 0)
    assert v[3:7] == [True, 0, 1, 0]
    assert v[7:11] == ["Label", False, "Enum.Font.Legacy", 14]
    assert v[11] == (0, 200, 0, 50)
    assert v[12:] == [True, False, True, 0]


def test_invalid_members_and_type_checks(w):
    msg = err_eval(w, "local p = Instance.new('Part'); p.Parent = workspace; p.Colour = Color3.new()")
    assert 'Colour is not a valid member of Part "Workspace.Part"' in msg
    assert "eval:1:" in msg  # error points at the user's line, like Roblox
    assert "not a valid member" in err_eval(w, "return Instance.new('Part').Textt")
    assert "not a valid member" in err_eval(w, "local f = Instance.new('Frame'); f.Text = 'x'")
    assert "Vector3 expected, got UDim2" in err_eval(w, "Instance.new('Part').Size = UDim2.new()")
    assert "UDim2 expected, got Vector3" in err_eval(w, "Instance.new('Frame').Size = Vector3.new()")
    assert "Color3 expected" in err_eval(w, "Instance.new('Part').Color = BrickColor.new('White')")
    assert "Instance expected" in err_eval(w, "Instance.new('Part').Parent = 'Workspace'")
    assert "Material" in err_eval(w, "Instance.new('Part').Material = Enum.Font.Arcade")
    assert "Invalid value" in err_eval(w, "Instance.new('Part').Material = 'Steel'")
    assert "boolean expected" in err_eval(w, "Instance.new('Part').Anchored = 1")
    assert "string expected" in err_eval(w, "Instance.new('TextLabel').Text = nil")
    # Roblox coercions that are allowed
    assert w.eval("local p = Instance.new('Part'); p.Material = 'Neon'; return p.Material == Enum.Material.Neon") is True
    assert w.eval("local t = Instance.new('TextLabel'); t.Text = 5; return t.Text") == "5"
    assert w.eval("local f = Instance.new('Frame'); f.ZIndex = 3.7; return f.ZIndex") == 3
    assert "read only" in err_eval(w, "Instance.new('Part').ClassName = 'X'")
    assert "read only" in err_eval(w, "workspace.CurrentCamera.ViewportSize = Vector2.new()")
    assert "Expected ':' not '.'" in err_eval(w, "return workspace.FindFirstChild('Terrain')")
    # children are reachable by name after members
    assert w.eval("local f = Instance.new('Folder'); local c = Instance.new('Part', f); c.Name = 'Size'; return f.Size == c") is True


def test_canquery_with_cancollide_warns(w):
    w.eval("local p = Instance.new('Part'); p.Name = 'Bad'; p.CanQuery = false; p.Parent = workspace")
    assert any("CanQuery" in x and "Workspace.Bad" in x for x in w.warnings())
    n = len(w.warnings())
    # setting CanQuery before CanCollide in the same script is fine (checked when the script yields)
    w.eval("local p = Instance.new('Part'); p.CanQuery = false; p.CanCollide = false; p.Parent = workspace")
    assert len(w.warnings()) == n


def test_tree_methods(w):
    vals = w.eval(
        """
        local m = Instance.new("Model"); m.Name = "Tank"; m.Parent = workspace
        local hull = Instance.new("Part"); hull.Name = "Hull"; hull.Parent = m
        local f = Instance.new("Folder"); f.Name = "Parts"; f.Parent = m
        local barrel = Instance.new("WedgePart"); barrel.Name = "Barrel"; barrel.Parent = f
        return barrel:GetFullName(), m:FindFirstChild("Barrel") == nil, m:FindFirstChild("Barrel", true) == barrel,
            m:FindFirstChildOfClass("Folder") == f, m:FindFirstChildWhichIsA("BasePart", true) == hull,
            barrel:FindFirstAncestor("Tank") == m, barrel:FindFirstAncestorOfClass("Model") == m,
            barrel:FindFirstAncestorWhichIsA("PVInstance") == m, #m:GetChildren(), #m:GetDescendants(),
            barrel:IsDescendantOf(workspace), m:IsAncestorOf(barrel), barrel:IsA("BasePart"), barrel:IsA("Part"),
            hull:IsA("PVInstance"), hull:IsA("Instance"), tostring(hull)
        """
    )
    assert vals == ("Workspace.Tank.Parts.Barrel", True, True, True, True, True, True, True, 2, 3, True, True, True, False,
                    True, True, "Hull")


def test_isa_hierarchy(w):
    vals = w.eval(
        """
        local b = Instance.new("TextButton")
        local g = Instance.new("ScreenGui")
        local ls = Instance.new("LocalScript")
        return b:IsA("GuiButton"), b:IsA("GuiObject"), b:IsA("GuiBase2d"), b:IsA("TextLabel"), g:IsA("LayerCollector"),
            g:IsA("GuiObject"), ls:IsA("Script"), ls:IsA("BaseScript"), Instance.new("SpawnLocation"):IsA("Part"),
            Instance.new("MeshPart"):IsA("BasePart"), Instance.new("UICorner"):IsA("UIComponent"),
            Instance.new("RemoteEvent"):IsA("Instance"), Instance.new("Model"):IsA("PVInstance")
        """
    )
    assert vals == (True, True, True, False, True, False, True, True, True, True, True, True, True)


def test_destroy_locks_parent_and_disconnects(w):
    vals = w.eval(
        """
        local log = {}
        local f = Instance.new("Folder"); f.Parent = workspace
        local p = Instance.new("Part"); p.Parent = f
        f.Destroying:Connect(function() table.insert(log, "destroying") end)
        local conn = f.ChildAdded:Connect(function() end)
        f:Destroy()
        local ok, err = pcall(function() f.Parent = workspace end)
        return f.Parent, p.Parent, ok, err, conn.Connected, log[1], #f:GetChildren()
        """
    )
    assert vals[0] is None and vals[1] is None and vals[2] is False
    assert "Parent property of Folder is locked" in vals[3]
    assert vals[4:] == (False, "destroying", 0)


def test_clone_is_deep_and_remaps_references(w):
    vals = w.eval(
        """
        local m = Instance.new("Model"); m.Name = "M"
        local a = Instance.new("Part"); a.Name = "Root"; a.Parent = m
        local b = Instance.new("Part"); b.Name = "B"; b.Parent = a
        m.PrimaryPart = a
        m:SetAttribute("Kind", "armor")
        a:AddTag("Tank")
        local c = m:Clone()
        return c.Parent, c.Name, c:GetAttribute("Kind"), c.PrimaryPart ~= a, c.PrimaryPart == c.Root,
            c.Root.B ~= b, c.Root:HasTag("Tank"), #c:GetDescendants()
        """
    )
    assert vals == (None, "M", "armor", True, True, True, True, 2)
    assert w.eval("local p = Instance.new('Part'); p.Archivable = false; return p:Clone()") is None
    assert w.eval("local f = Instance.new('Folder'); for i = 1, 5 do Instance.new('Part', f) end; f:ClearAllChildren(); return #f:GetChildren()") == 0


def test_attributes(w):
    vals = w.eval(
        """
        local f = Instance.new("Folder")
        local log = {}
        f.AttributeChanged:Connect(function(name) table.insert(log, name) end)
        f:GetAttributeChangedSignal("Phase"):Connect(function() table.insert(log, "phase:" .. tostring(f:GetAttribute("Phase"))) end)
        f:SetAttribute("Phase", "intro")
        f:SetAttribute("Phase", "intro") -- same value: no event
        f:SetAttribute("Score", 100)
        f:SetAttribute("Center", Vector3.new(52, 1, 52))
        f:SetAttribute("Color", Color3.new(1, 0, 0))
        f:SetAttribute("Size", UDim2.new())
        f:SetAttribute("Enum", Enum.Material.Neon)
        f:SetAttribute("Gone", true)
        f:SetAttribute("Gone", nil)
        local n = 0
        for _ in pairs(f:GetAttributes()) do n = n + 1 end
        return table.concat(log, ","), n, f:GetAttribute("Missing")
        """
    )
    assert vals == ("Phase,phase:intro,Score,Center,Color,Size,Enum,Gone,Gone", 6, None)
    for bad in ["{}", "function() end", "Instance.new('Part')", "coroutine.create(function() end)"]:
        assert "not a supported attribute type" in err_eval(w, "workspace:SetAttribute('X', %s)" % bad)
    assert "alphanumeric" in err_eval(w, "workspace:SetAttribute('bad name', 1)")
    assert "reserved" in err_eval(w, "workspace:SetAttribute('RBXFoo', 1)")


def test_property_changed_signals(w):
    vals = w.eval(
        """
        local p = Instance.new("Part")
        local log = {}
        p.Changed:Connect(function(prop) table.insert(log, prop) end)
        p:GetPropertyChangedSignal("Transparency"):Connect(function() table.insert(log, "T=" .. p.Transparency) end)
        p.Transparency = 0.5
        p.Transparency = 0.5 -- unchanged: no event
        p.Name = "X"
        local v = Instance.new("IntValue")
        local got
        v.Changed:Connect(function(val) got = val end)
        v.Value = 7
        return table.concat(log, ","), got
        """
    )
    assert vals == ("Transparency,T=0.5,Name", 7)
    assert "not a valid property name" in err_eval(w, "Instance.new('Part'):GetPropertyChangedSignal('Foo')")


def test_tree_signals(w):
    vals = w.eval(
        """
        local log = {}
        local root = Instance.new("Folder"); root.Parent = workspace
        root.ChildAdded:Connect(function(c) table.insert(log, "add:" .. c.Name) end)
        root.ChildRemoved:Connect(function(c) table.insert(log, "rem:" .. c.Name) end)
        root.DescendantAdded:Connect(function(c) table.insert(log, "desc:" .. c.Name) end)
        root.DescendantRemoving:Connect(function(c) table.insert(log, "desrem:" .. c.Name) end)
        local m = Instance.new("Model"); m.Name = "M"
        local p = Instance.new("Part"); p.Name = "P"; p.Parent = m
        p.AncestryChanged:Connect(function(child, parent) table.insert(log, "anc:" .. child.Name) end)
        m.Parent = root
        m.Parent = nil
        return table.concat(log, ",")
        """
    )
    assert vals == "add:M,desc:M,desc:P,anc:M,desrem:M,desrem:P,rem:M,anc:M"


def test_collection_service(w):
    vals = w.eval(
        """
        local CS = game:GetService("CollectionService")
        local added = {}
        CS:GetInstanceAddedSignal("Enemy"):Connect(function(i) table.insert(added, i.Name) end)
        local a = Instance.new("Part"); a.Name = "A"; a:AddTag("Enemy")
        local b = Instance.new("Part"); b.Name = "B"; CS:AddTag(b, "Enemy"); b.Parent = workspace
        a.Parent = workspace
        local n1 = #CS:GetTagged("Enemy")
        a:RemoveTag("Enemy")
        return table.concat(added, ","), n1, #CS:GetTagged("Enemy"), b:HasTag("Enemy"), CS:GetTags(b)[1]
        """
    )
    assert vals == ("B,A", 2, 1, True, "Enemy")


# ============================================================================ pivots
def test_model_pivot_to_moves_all_parts_rigidly(w):
    w.eval(
        """
        local m = Instance.new("Model"); m.Name = "Tank"
        local root = Instance.new("Part"); root.Name = "Root"; root.Size = Vector3.new(1, 1, 1); root.Parent = m
        local hull = Instance.new("Part"); hull.Name = "Hull"; hull.Position = Vector3.new(0, 1, 0); hull.Parent = m
        local f = Instance.new("Folder"); f.Parent = m
        local barrel = Instance.new("Part"); barrel.Name = "Barrel"; barrel.Position = Vector3.new(0, 2, -3); barrel.Parent = f
        m.PrimaryPart = root
        m.Parent = workspace
        m:PivotTo(CFrame.new(10, 1, 20) * CFrame.Angles(0, -math.pi / 2, 0))
        """
    )
    root = w.find("Workspace.Tank.Root")
    barrel = w.find("Workspace.Tank.Folder.Barrel")
    hull = w.find("Workspace.Tank.Hull")
    assert w.value(w.get(root, "Position")) == approx((10, 1, 20), abs=1e-9)
    assert w.value(w.get(hull, "Position")) == approx((10, 2, 20), abs=1e-9)
    # rotating -90 deg around Y maps local -Z (forward) to world +X (screen right)
    assert w.value(w.get(barrel, "Position")) == approx((13, 3, 20), abs=1e-9)
    look = w.value(w.eval("return workspace.Tank.Folder.Barrel.CFrame.LookVector"))
    assert look == approx((1, 0, 0), abs=1e-9)
    assert w.value(w.call("Workspace.Tank", "GetPivot")) == approx(w.value(w.get(root, "CFrame")), abs=1e-12)
    # pivot again (root was at the origin when the offsets were made): offsets are kept exactly
    w.eval("workspace.Tank:PivotTo(CFrame.new(0, 1, 0))")
    assert w.value(w.get(barrel, "Position")) == approx((0, 3, -3), abs=1e-9)
    assert w.value(w.get(hull, "Position")) == approx((0, 2, 0), abs=1e-9)


def test_model_without_primary_part_pivots_around_bbox_center(w):
    vals = w.eval(
        """
        local m = Instance.new("Model")
        local a = Instance.new("Part"); a.Size = Vector3.new(2, 2, 2); a.Position = Vector3.new(0, 0, 0); a.Parent = m
        local b = Instance.new("Part"); b.Size = Vector3.new(2, 2, 2); b.Position = Vector3.new(4, 0, 0); b.Parent = m
        local before = m:GetPivot().Position
        m:PivotTo(CFrame.new(0, 5, 0))
        local cf, size = m:GetBoundingBox()
        return before, a.Position, b.Position, m.WorldPivot.Position, size
        """
    )
    v = [w.value(x) for x in vals]
    assert v[0] == approx((2, 0, 0))
    assert v[1] == approx((-2, 5, 0)) and v[2] == approx((2, 5, 0))
    assert v[3] == approx((0, 5, 0)) and v[4] == approx((6, 2, 2))


def test_basepart_pivot_moves_descendant_parts(w):
    vals = w.eval(
        """
        local p = Instance.new("Part"); p.Position = Vector3.new(1, 0, 0)
        local c = Instance.new("Part"); c.Position = Vector3.new(1, 3, 0); c.Parent = p
        p:PivotTo(CFrame.new(0, 10, 0))
        return p.Position, c.Position
        """
    )
    assert w.value(vals[0]) == approx((0, 10, 0)) and w.value(vals[1]) == approx((0, 13, 0))


# ============================================================================ scheduler
def test_wait_for_child_yields_until_child_exists(w):
    w.run_source(
        """
        local f = workspace:WaitForChild("Later")
        print("got", f.Name, time())
        local missing = workspace:WaitForChild("Never", 1)
        print("timeout", missing)
        """
    )
    assert w.output() == []
    w.advance(0.5)
    w.eval("local f = Instance.new('Folder'); f.Name = 'Later'; f.Parent = workspace")
    assert w.output() == ["got Later 0.5"]
    w.advance(1.1)
    assert w.output()[-1] == "timeout nil"
    assert w.warnings() == []
    w.assert_no_errors()


def test_wait_for_child_infinite_yield_warning_once(w):
    w.run_source("game.ReplicatedStorage:WaitForChild('BattleCity')")
    w.advance(4.9)
    assert w.warnings() == []
    w.advance(0.2)
    assert w.warnings() == ["Infinite yield possible on 'ReplicatedStorage:WaitForChild(\"BattleCity\")'"]
    w.advance(6)
    assert len(w.warnings()) == 1


def test_task_wait_timing(w):
    w.run_source(
        """
        local start = time()
        local dt = task.wait(0.5)
        print(string.format("woke %.4f %.4f", time() - start, dt))
        local d2 = task.wait()
        print(string.format("frame %.4f", d2))
        """
    )
    w.advance(29 / 60)
    assert w.output() == []
    w.step()
    assert w.output() == ["woke 0.5000 0.5000"]
    w.step()
    assert w.output()[-1] == "frame 0.0167"


def test_task_library(w):
    w.run_source(
        """
        local log = {}
        task.spawn(function(x) table.insert(log, "spawn" .. x) end, 1)
        task.defer(function() table.insert(log, "defer") end)
        table.insert(log, "main")
        task.delay(0.25, function(a) table.insert(log, "delay" .. a) end, 7)
        local t = task.delay(0.1, function() table.insert(log, "cancelled!") end)
        task.cancel(t)
        _G.log = log
        """
    )
    assert w.eval("return table.concat(_G.log, ',')") == "spawn1,main,defer"
    w.advance(0.3)
    assert w.eval("return table.concat(_G.log, ',')") == "spawn1,main,defer,delay7"
    w.run_source("local e, t = wait(0.1); print('wait', e >= 0.1, t > 0)")
    w.advance(0.2)
    assert "wait true true" in w.output()
    w.assert_no_errors()


def test_pcall_can_yield_like_luau(w):
    w.run_source(
        """
        local ok, v = pcall(function()
            task.wait(0.1)
            return workspace:WaitForChild("Thing").Name
        end)
        print("pcall", ok, v)
        local ok2, err = pcall(function() error("bad") end)
        print("pcall2", ok2, err)
        local ok3, tb = xpcall(function() local x = nil; return x.y end, debug.traceback)
        print("xpcall", ok3, string.find(tb, "attempt to index") ~= nil)
        """
    )
    w.advance(0.2)
    w.eval("Instance.new('Folder', workspace).Name = 'Thing'")
    out = w.output()
    assert out[0] == "pcall true Thing"
    assert out[1].startswith("pcall2 false ") and "bad" in out[1]
    assert out[2] == "xpcall false true"
    w.assert_no_errors()


def test_coroutine_running_inside_pcall_is_the_script_thread(w):
    w.run_source(
        """
        local th
        pcall(function() th = coroutine.running() end)
        print(th == coroutine.running(), coroutine.status(th))
        """
    )
    assert w.output() == ["true running"]


# ============================================================================ signals
def test_signal_connect_once_wait_disconnect(w):
    w.run_source(
        """
        local be = Instance.new("BindableEvent")
        local count, once = 0, 0
        local c = be.Event:Connect(function(n) count = count + n end)
        be.Event:Once(function() once = once + 1 end)
        task.spawn(function()
            local a, b = be.Event:Wait()
            print("waited", a, b)
        end)
        be:Fire(1, "x")
        be:Fire(2)
        c:Disconnect()
        be:Fire(100)
        print(count, once, c.Connected)
        """
    )
    assert w.output() == ["waited 1 x", "3 1 false"]


def test_handler_errors_are_isolated_and_reported(w):
    w.run_source(
        """
        local be = Instance.new("BindableEvent")
        be.Event:Connect(function() local t = nil; print(t.field) end)
        be.Event:Connect(function() print("second handler ran") end)
        be:Fire()
        print("script continues")
        """,
        name="Handlers",
    )
    assert w.output() == ["second handler ran", "script continues"]
    errs = w.errors()
    assert len(errs) == 1
    assert "ServerScriptService.Handlers" in errs[0] and "attempt to index" in errs[0] and "stack traceback" in errs[0]


def test_connect_requires_function(w):
    assert "Attempt to connect failed" in err_eval(w, "workspace.ChildAdded:Connect(nil)")


# ============================================================================ errors in scripts
def test_syntax_error_is_reported(w, tmp_path):
    bad = tmp_path / "Broken.lua"
    bad.write_text("local x = = 1\n", encoding="utf-8")
    ok, err, inst = w.run_script(str(bad))
    assert ok is False and "SyntaxError" in err and "ServerScriptService.Broken:1" in err
    assert len(w.errors()) == 1 and "SyntaxError" in w.errors()[0]


def test_luau_only_syntax_is_rejected(w):
    for src in ["local x = 1\nx += 1", "for i = 1, 3 do if i == 2 then continue end end", "local s = `hi`", "local function f(x: number) end"]:
        ok, err, _ = w.run_source(src)
        assert ok is False and "SyntaxError" in err


def test_runtime_error_reported_with_script_line(w, tmp_path):
    f = tmp_path / "Crash.lua"
    f.write_text("print('a')\nlocal p = workspace.DoesNotExist\n", encoding="utf-8")
    ok, err, _ = w.run_script(str(f))
    assert ok is False
    assert "ServerScriptService.Crash:2: DoesNotExist is not a valid member of Workspace \"Workspace\"" in err
    with pytest.raises(AssertionError):
        w.assert_no_errors()


def test_require_modules(w):
    w.add_module_source("ServerScriptService", "Mod", "print('loading Mod') return { value = 42, ctx = game:GetService('RunService'):IsClient() }")
    w.add_module_source("ReplicatedStorage", "Shared", "return { n = 1 }")
    w.add_module_source("ServerScriptService", "Broken", "local x = nil; return x.y")
    w.add_module_source("ServerScriptService", "NoReturn", "local x = 1")
    w.add_module_source("ServerScriptService", "Waits", "local f = workspace:WaitForChild('Ready'); return f.Name")
    w.run_source(
        """
        local a = require(script.Parent.Mod)
        local b = require(script.Parent:WaitForChild("Mod"))
        print(a == b, a.value, a.ctx)
        print(pcall(require, script.Parent.Broken))
        print(pcall(require, script.Parent.NoReturn))
        print(require(script.Parent.Waits))
        """
    )
    assert w.output()[:2] == ["loading Mod", "true 42 false"]
    assert "Requested module experienced an error while loading" in w.output()[2]
    assert "Module code did not return exactly one value" in w.output()[3]
    w.eval("Instance.new('Folder', workspace).Name = 'Ready'")
    assert w.output()[-1] == "Ready"
    assert any("Broken" in e and "attempt to index" in e for e in w.errors())
    # client and server get separate module instances (separate Lua VMs in Roblox)
    p = w.add_player("A", 1)
    w.run_source("local s = require(game.ReplicatedStorage.Shared); s.n = s.n + 1; print('client', s.n)", cls="LocalScript", player=p)
    w.run_source("local s = require(game.ReplicatedStorage.Shared); print('server', s.n)")
    assert w.output()[-2:] == ["client 2", "server 1"]
    assert "invalid argument" in err_eval(w, "require(5)") or "not supported" in err_eval(w, "require(5)")


# ============================================================================ context: server / client
def test_local_player_and_run_service_follow_context(w):
    a = w.add_player("Alice", 1)
    b = w.add_player("Bob", 2)
    assert w.eval("return game.Players.LocalPlayer") is None
    assert w.eval("return game:GetService('RunService'):IsServer(), game:GetService('RunService'):IsClient()") == (True, False)
    assert w.eval("return game.Players.LocalPlayer.Name", a) == "Alice"
    assert w.eval("return game.Players.LocalPlayer.Name", b) == "Bob"
    assert w.eval("return game:GetService('RunService'):IsClient()", b) is True
    # a client's signal handler runs as that client even when fired by the server
    w.run_source("game.ReplicatedStorage.ChildAdded:Connect(function() print('seen by', game.Players.LocalPlayer.Name) end)", cls="LocalScript", player=a)
    w.eval("Instance.new('Folder', game.ReplicatedStorage)")
    assert w.output() == ["seen by Alice"]
    assert [w.name(x) for x in w.players()] == ["Alice", "Bob"]


def test_client_created_instances_are_local(w):
    a = w.add_player("Alice", 1)
    b = w.add_player("Bob", 2)
    w.run_source("local f = Instance.new('Folder'); f.Name = 'LocalOnly'; f.Parent = workspace", cls="LocalScript", player=a)
    assert w.eval("return workspace:FindFirstChild('LocalOnly') ~= nil", a) is True
    assert w.eval("return workspace:FindFirstChild('LocalOnly')") is None
    assert w.eval("return workspace:FindFirstChild('LocalOnly')", b) is None
    assert w.find("Workspace.LocalOnly") is not None  # the harness sees everything
    # server-only containers are invisible to clients
    w.add_module_source("ServerScriptService", "Secret", "return 1")
    assert w.eval("return #game.ServerScriptService:GetChildren()", a) == 0
    # each client has its own camera
    assert w.eval("return workspace.CurrentCamera", a) != w.eval("return workspace.CurrentCamera", b)


def test_player_added_fires_immediately_and_removal(w):
    w.run_source(
        """
        local Players = game:GetService("Players")
        Players.CharacterAutoLoads = false
        Players.PlayerAdded:Connect(function(p) print("added", p.Name, p.UserId, p:FindFirstChild("PlayerGui") ~= nil) end)
        Players.PlayerRemoving:Connect(function(p) print("removing", p.Name) end)
        """
    )
    p = w.add_player("Zed", 77)
    assert w.output() == ["added Zed 77 true"]
    w.advance(0.1)
    assert w.get(p, "Character") is None  # CharacterAutoLoads = false
    w.remove_player(p)
    assert w.output()[-1] == "removing Zed"
    assert w.players() == []


def test_character_autoloads_by_default(w):
    p = w.add_player("Ann", 1)
    w.step()
    ch = w.get(p, "Character")
    assert ch is not None and w.class_name(ch) == "Model"


# ============================================================================ remotes
def test_remote_event_round_trip(w):
    w.run_source(
        """
        local f = Instance.new("Folder"); f.Name = "BattleCity"; f.Parent = game.ReplicatedStorage
        local re = Instance.new("RemoteEvent"); re.Name = "Input"; re.Parent = f
        re.OnServerEvent:Connect(function(player, dir, fire, t)
            print("server got", player.Name, dir, fire, type(t), t and t.k)
            re:FireClient(player, "ack", dir)
        end)
        """
    )
    a = w.add_player("Alice", 1)
    b = w.add_player("Bob", 2)
    for p in (a, b):
        w.run_source(
            """
            local re = game.ReplicatedStorage:WaitForChild("BattleCity"):WaitForChild("Input")
            re.OnClientEvent:Connect(function(msg, v) print(game.Players.LocalPlayer.Name, "got", msg, v) end)
            """,
            cls="LocalScript",
            player=p,
        )
    w.eval("game.ReplicatedStorage.BattleCity.Input:FireServer(2, true, {k = 'v'})", b)
    assert w.output() == []  # delivered on the next step, not immediately
    w.step()
    assert w.output() == ["server got Bob 2 true table v"]
    w.step()
    assert w.output()[-1] == "Bob got ack 2"
    assert not any(x.startswith("Alice") for x in w.output())
    w.eval("game.ReplicatedStorage.BattleCity.Input:FireAllClients('all', 0)")
    w.step()
    assert w.output()[-2:] == ["Alice got all 0", "Bob got all 0"]
    w.assert_no_errors()


def test_remote_argument_validation(w):
    w.eval("local re = Instance.new('RemoteEvent'); re.Name = 'R'; re.Parent = game.ReplicatedStorage")
    p = w.add_player("A", 1)
    assert "FireServer can only be called from the client" in err_eval(w, "game.ReplicatedStorage.R:FireServer(1)")
    assert "FireClient can only be called from the server" in err_eval(w, "game.ReplicatedStorage.R:FireClient(game.Players.A)", p)
    assert "function" in err_eval(w, "game.ReplicatedStorage.R:FireServer(print)", p)
    assert "thread" in err_eval(w, "game.ReplicatedStorage.R:FireServer(coroutine.create(print))", p)
    assert "Cannot convert mixed" in err_eval(w, "game.ReplicatedStorage.R:FireServer({1, 2, x = 3})", p)
    assert "Cannot convert mixed" in err_eval(w, "game.ReplicatedStorage.R:FireClient(game.Players.A, {[1] = 1, [3] = 3})")
    assert "player argument" in err_eval(w, "game.ReplicatedStorage.R:FireClient('A', 1)")
    assert "OnServerEvent can only be used on the server" in err_eval(w, "game.ReplicatedStorage.R.OnServerEvent:Connect(print)", p)
    assert "OnClientEvent can only be used on the client" in err_eval(w, "game.ReplicatedStorage.R.OnClientEvent:Connect(print)")


def test_remote_tables_are_copied_and_local_instances_become_nil(w):
    w.run_source(
        """
        local re = Instance.new("RemoteEvent"); re.Name = "R"; re.Parent = game.ReplicatedStorage
        re.OnServerEvent:Connect(function(p, t, inst, shared)
            print(t == _G.sent, t[1], inst, shared == workspace)
        end)
        """
    )
    p = w.add_player("A", 1)
    w.eval("local t = {5}; local f = Instance.new('Folder', workspace); game.ReplicatedStorage.R:FireServer(t, f, workspace)", p)
    w.step()
    assert w.output() == ["false 5 nil true"]
    # server-only instances arrive as nil on the client
    w.run_source("game.ReplicatedStorage.R.OnClientEvent:Connect(function(a, b) print('client', a, b) end)", cls="LocalScript", player=p)
    w.eval("local s = Instance.new('Folder', game.ServerStorage); s.Name = 'S'; game.ReplicatedStorage.R:FireClient(game.Players.A, s, workspace)")
    w.step()
    assert w.output()[-1] == "client nil Workspace"


def test_remote_events_queue_until_a_handler_connects(w):
    w.eval("local re = Instance.new('RemoteEvent'); re.Name = 'R'; re.Parent = game.ReplicatedStorage")
    p = w.add_player("A", 1)
    w.eval("game.ReplicatedStorage.R:FireServer('early')", p)
    w.advance(0.1)
    w.run_source("game.ReplicatedStorage.R.OnServerEvent:Connect(function(p, x) print('late handler', x) end)")
    w.step()
    assert w.output() == ["late handler early"]


def test_remote_function_invoke(w):
    w.run_source(
        """
        local rf = Instance.new("RemoteFunction"); rf.Name = "Ask"; rf.Parent = game.ReplicatedStorage
        rf.OnServerInvoke = function(player, a, b) return player.Name .. ":" .. (a + b) end
        """
    )
    p = w.add_player("Q", 1)
    w.run_source("print('answer', game.ReplicatedStorage.Ask:InvokeServer(2, 3))", cls="LocalScript", player=p)
    w.advance(3 / 60)
    assert w.output() == ["answer Q:5"]
    assert "callback member" in err_eval(w, "return game.ReplicatedStorage.Ask.OnServerInvoke")


# ============================================================================ tweens / debris / sounds
def test_tween_interpolates_and_completes(w):
    w.run_source(
        """
        local TweenService = game:GetService("TweenService")
        local p = Instance.new("Part"); p.Name = "T"; p.Transparency = 0; p.Parent = workspace
        local f = Instance.new("Frame"); f.Name = "F"; f.Parent = workspace
        local t = TweenService:Create(p, TweenInfo.new(1, Enum.EasingStyle.Linear), {Transparency = 1, Position = Vector3.new(10, 0, 0), Color = Color3.new(1, 0, 0)})
        local t2 = TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)})
        t.Completed:Connect(function(state) print("completed", state, t.PlaybackState) end)
        t:Play(); t2:Play()
        """
    )
    w.advance(0.25)
    part = w.find("Workspace.T")
    assert w.get(part, "Transparency") == approx(0.25)
    assert w.value(w.get(part, "Position")) == approx((2.5, 0, 0))
    assert w.value(w.get("Workspace.F", "Size")) == approx((0.5, 50, 0.5, 50))
    w.advance(0.8)
    assert w.get(part, "Transparency") == 1
    assert w.output() == ["completed Enum.PlaybackState.Completed Enum.PlaybackState.Completed"]
    w.assert_no_errors()


def test_tween_goal_validation(w):
    assert "no property named 'Foo'" in err_eval(w, "game:GetService('TweenService'):Create(Instance.new('Part'), TweenInfo.new(), {Foo = 1})")
    assert "type mismatch" in err_eval(w, "game:GetService('TweenService'):Create(Instance.new('Part'), TweenInfo.new(), {Size = 2})")
    assert "TweenInfo" in err_eval(w, "game:GetService('TweenService'):Create(Instance.new('Part'), {Time = 1}, {Transparency = 1})")
    assert w.eval("return game:GetService('TweenService'):GetValue(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In)") == 0.5


def test_debris_destroys_after_lifetime(w):
    w.eval("local p = Instance.new('Part', workspace); p.Name = 'Boom'; game:GetService('Debris'):AddItem(p, 0.5)")
    w.advance(0.45)
    assert w.find("Workspace.Boom") is not None
    w.advance(0.1)
    assert w.find("Workspace.Boom") is None


def test_sounds_are_logged(w):
    w.eval("local s = Instance.new('Sound', workspace); s.Name = 'Fire'; s.SoundId = 'rbxassetid://1'; s:Play()")
    assert w.sounds()[0]["id"] == "rbxassetid://1"


# ============================================================================ services
def test_services(w):
    assert w.eval("return game:GetService('Workspace') == workspace, game.Workspace == workspace, game:GetService('Players') == game.Players") == (True, True, True)
    assert "is not a valid Service name" in err_eval(w, "game:GetService('Playerz')")
    # RunService's Name is "Run Service" in Roblox, so game.RunService does not exist
    assert "not a valid member" in err_eval(w, "return game.RunService")
    assert w.eval("return workspace.CurrentCamera.FieldOfView, workspace.CurrentCamera.ViewportSize") is not None
    assert w.eval("return workspace:GetServerTimeNow() > 0, workspace.DistributedGameTime") == (True, 0)
    for name in ["ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui", "RunService",
                 "TweenService", "Debris", "UserInputService", "ContextActionService", "HttpService", "SoundService",
                 "Lighting", "CollectionService", "PhysicsService", "GuiService", "TextService", "Teams", "Chat",
                 "MarketplaceService"]:
        ok_eval(w, "return game:GetService('%s')" % name)
    assert w.eval("return game.StarterPlayer:FindFirstChild('StarterPlayerScripts') ~= nil") is True


def test_http_json_round_trip(w):
    enc = w.eval(
        """
        local H = game:GetService("HttpService")
        return H:JSONEncode({phase = "tally", stage = 3, players = {{kills = {1, 2, 0, 4}, bonus = 1000}}, empty = {}, ok = true, s = 'a"b'})
        """
    )
    assert enc == '{"empty":[],"ok":true,"phase":"tally","players":[{"bonus":1000,"kills":[1,2,0,4]}],"s":"a\\"b","stage":3}'
    vals = w.eval(
        """
        local H = game:GetService("HttpService")
        local t = H:JSONDecode(H:JSONEncode({a = {1, 2.5, "x"}, b = {c = false}}))
        return #t.a, t.a[2], t.a[3], t.b.c
        """
    )
    assert vals == (3, 2.5, "x", False)
    assert "Can't convert to JSON" in err_eval(w, "return game:GetService('HttpService'):JSONEncode({1, x = 2})")
    assert "Can't convert to JSON" in err_eval(w, "return game:GetService('HttpService'):JSONEncode({[2] = 'sparse'})")
    assert "Can't parse JSON" in err_eval(w, "return game:GetService('HttpService'):JSONDecode('{bad')")
    guid = w.eval("return game:GetService('HttpService'):GenerateGUID(false)")
    assert len(guid) == 36 and guid.count("-") == 4


def test_starter_gui_core_gui_is_client_only(w):
    p = w.add_player("A", 1)
    assert "client" in err_eval(w, "game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)")
    assert w.eval("local sg = game:GetService('StarterGui'); sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false); return sg:GetCoreGuiEnabled(Enum.CoreGuiType.Health)", p) is False
    assert "has not been registered" in err_eval(w, "game.StarterGui:SetCore('NotAThing', 1)", p)


def test_render_step_binding_order_and_client_only(w):
    p = w.add_player("A", 1)
    w.run_source(
        """
        local RunService = game:GetService("RunService")
        RunService:BindToRenderStep("late", Enum.RenderPriority.Camera.Value + 1, function() print("camera+1") end)
        RunService:BindToRenderStep("early", Enum.RenderPriority.Input.Value, function() print("input") end)
        RunService.RenderStepped:Connect(function() print("renderstepped") end)
        RunService.Heartbeat:Connect(function() print("heartbeat client") end)
        """,
        cls="LocalScript",
        player=p,
    )
    w.run_source("game:GetService('RunService').Heartbeat:Connect(function() print('heartbeat server') end)")
    w.step()
    assert w.output() == ["input", "camera+1", "renderstepped", "heartbeat client", "heartbeat server"]
    assert "can only be called from a LocalScript" in err_eval(w, "game:GetService('RunService'):BindToRenderStep('x', 1, print)")
    assert "RenderStepped" in err_eval(w, "game:GetService('RunService').RenderStepped:Connect(print)")
    assert "number expected, got EnumItem" in err_eval(w, "game:GetService('RunService'):BindToRenderStep('x', Enum.RenderPriority.Camera, print)", p)


# ============================================================================ input simulation
def test_keyboard_input_goes_to_that_players_client_only(w):
    a = w.add_player("A", 1)
    b = w.add_player("B", 2)
    for p in (a, b):
        w.run_source(
            """
            local UIS = game:GetService("UserInputService")
            UIS.InputBegan:Connect(function(input, gp) print(game.Players.LocalPlayer.Name, "began", input.KeyCode.Name, input.UserInputType.Name, input.UserInputState.Name, gp) end)
            UIS.InputEnded:Connect(function(input, gp) print(game.Players.LocalPlayer.Name, "ended", input.KeyCode.Name, UIS:IsKeyDown(input.KeyCode)) end)
            """,
            cls="LocalScript",
            player=p,
        )
    w.key_down(b, "W")
    assert w.output() == ["B began W Keyboard Begin false"]
    assert w.eval("return game:GetService('UserInputService'):IsKeyDown(Enum.KeyCode.W)", b) is True
    assert w.eval("return game:GetService('UserInputService'):IsKeyDown(Enum.KeyCode.W)", a) is False
    assert w.eval("return #game:GetService('UserInputService'):GetKeysPressed()", b) == 1
    w.key_up(b, "W")
    assert w.output()[-1] == "B ended W false"


def test_gamepad_and_thumbstick(w):
    p = w.add_player("G", 1, gamepad=True, keyboard=False)
    w.run_source(
        """
        local UIS = game:GetService("UserInputService")
        print("pads", UIS.GamepadEnabled, UIS.KeyboardEnabled, UIS:GetGamepadConnected(Enum.UserInputType.Gamepad1))
        UIS.InputBegan:Connect(function(i) print("began", i.KeyCode.Name, i.UserInputType.Name) end)
        UIS.InputChanged:Connect(function(i) print("changed", i.KeyCode.Name, i.Position.X, i.Position.Y) end)
        """,
        cls="LocalScript",
        player=p,
    )
    w.gamepad_button(p, "ButtonA", True)
    w.gamepad_button(p, "DPadUp", True)
    w.thumbstick(p, 0.25, -0.75)
    assert w.output() == ["pads true false true", "began ButtonA Gamepad1", "began DPadUp Gamepad1", "changed Thumbstick1 0.25 -0.75"]
    assert w.eval("return game:GetService('UserInputService'):IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)", p) is True


def test_touch_on_gui_button(w):
    p = w.add_player("T", 1, touch=True, viewport=(800, 400))
    w.run_source(
        """
        local UIS = game:GetService("UserInputService")
        print("touch", UIS.TouchEnabled, UIS.KeyboardEnabled)
        local gui = Instance.new("ScreenGui"); gui.Name = "HUD"; gui.IgnoreGuiInset = true
        gui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
        local fire = Instance.new("TextButton"); fire.Name = "Fire"; fire.Size = UDim2.fromOffset(100, 100)
        fire.AnchorPoint = Vector2.new(1, 1); fire.Position = UDim2.new(1, -10, 1, -10); fire.Parent = gui
        fire.InputBegan:Connect(function(i) print("fire began", i.UserInputType.Name) end)
        fire.InputEnded:Connect(function(i) print("fire ended") end)
        fire.Activated:Connect(function() print("activated") end)
        UIS.TouchStarted:Connect(function(i, gp) print("touch started", i.Position.X, i.Position.Y, gp) end)
        UIS.TouchEnded:Connect(function(i) print("touch ended") end)
        local hidden = Instance.new("TextButton"); hidden.Name = "Hidden"; hidden.Visible = false; hidden.Parent = gui
        hidden.InputBegan:Connect(function() print("hidden touched!") end)
        """,
        cls="LocalScript",
        player=p,
    )
    fire = w.find("Players.T.PlayerGui.HUD.Fire")
    assert w.abs_rect(fire) == (690, 232, 100, 100)
    assert w.value(w.get(fire, "AbsolutePosition")) == (690, 232)
    t = w.touch_begin(p, fire)
    w.touch_end(p, t)
    assert w.output() == ["touch true false", "fire began Touch", "touch started 740 282 false", "fire ended", "activated", "touch ended"]
    w.touch_begin(p, "Players.T.PlayerGui.HUD.Hidden")
    assert "hidden touched!" not in w.output()
    assert any("cannot be touched" in x for x in w.warnings())


def test_camera_viewport_and_projection(w):
    p = w.add_player("C", 1)
    assert w.value(w.eval("return workspace.CurrentCamera.ViewportSize", p)) == (1280, 720)
    w.set_viewport(p, 1000, 500)
    assert w.value(w.eval("return workspace.CurrentCamera.ViewportSize", p)) == (1000, 500)
    vals = w.eval(
        """
        local cam = workspace.CurrentCamera
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(Vector3.new(0, 100, 0.001), Vector3.new(0, 0, 0))
        local v, on = cam:WorldToViewportPoint(Vector3.new(0, 0, 0))
        return v.X, v.Y, on, cam.FieldOfView
        """,
        p,
    )
    assert vals[0] == approx(500, abs=1e-3) and vals[1] == approx(250, abs=0.1) and vals[2] is True and vals[3] == 70
    assert w.value(w.get(w.camera(p), "CFrame"))[:3] == approx((0, 100, 0.001))


# ============================================================================ Luau standard library
def test_luau_library_extras(w):
    assert w.eval("return math.clamp(5, 0, 3), math.clamp(-1, 0, 3), math.sign(-2), math.sign(0), math.round(2.5), math.round(-2.5)") == (3, 0, -1, 0, 3, -3)
    assert w.eval("return math.noise(1, 2, 3), math.noise(1.5, 2.3, 0.7) ~= 0, math.abs(math.noise(0.1, 0.2, 0.3)) <= 1") == (0, True, True)
    assert "max must be greater" in err_eval(w, "return math.clamp(1, 3, 0)")
    assert w.eval("return table.find({'a', 'b', 'c'}, 'b'), table.find({}, 1)") == (2, None)
    assert w.eval("local t = {1, 2, x = 3}; table.clear(t); return next(t)") is None
    assert w.eval("local t = table.create(3, 0); return #t, t[3]") == (3, 0)
    assert w.eval("local t = table.freeze({}); return table.isfrozen(t)") is True
    assert w.eval("local p = string.split('a,b,,c', ','); return #p, p[3], ('x y'):split(' ')[2]") == (4, "", "y")
    assert w.eval("return string.format('%d|%5.1f|%s|%s', 3, 2.25, nil, true)") == "3|  2.2|nil|true"
    assert "no integer representation" in err_eval(w, "return string.format('%d', 1.5)")
    assert "no integer representation" in err_eval(w, "return ('%d'):format(2.5)")
    assert w.eval("return utf8.char(3607, 65), utf8.len('ก')") == ("ทA", 1)
    assert w.eval("return bit32.band(12, 10), bit32.bor(12, 10), bit32.bxor(12, 10), bit32.lshift(1, 4), bit32.rshift(256, 4)") == (8, 14, 6, 16, 16)
    assert "readonly" in err_eval(w, "math.clamp = nil")
    assert "loadstring() is not available" in err_eval(w, "loadstring('return 1')")
    assert w.eval("return os.time() > 0, os.clock(), tick() > 0") == (True, 0, True)


def test_globals_are_per_script_but_G_is_shared(w):
    w.run_source("myGlobal = 1; _G.shared1 = 'yes'")
    w.run_source("print(myGlobal, _G.shared1)")
    assert w.output() == ["nil yes"]


def test_table_insert_remove_are_strict_like_luau(w):
    assert w.eval("local t = {1, 2}; table.insert(t, 3); table.insert(t, 1, 0); return table.concat(t, ',')") == "0,1,2,3"
    assert "position out of bounds" in err_eval(w, "local t = {}; table.insert(t, 5, 'x')")
    assert "position out of bounds" in err_eval(w, "local t = {1}; table.remove(t, 7)")
    assert w.eval("local t = {}; return table.remove(t), #t") == (None, 0)
    assert w.eval("local t = {1, 2, 3}; return table.remove(t, 1), table.remove(t), #t") == (1, 3, 1)


def test_pcall_from_harness_passes_arguments(w):
    assert w.lua.eval("function(w) return w.base.xpcall(function(a, b) return a + b end, print, 2, 3) end")(w.w) == (True, 5)


def test_every_creatable_class_round_trips_its_properties(w):
    """Read every property of every creatable class and write it back (catches broken defaults/getters)."""
    problems = w.lua.eval(
        """function(w, Stubs)
          local out = {}
          local Instance = w.base.Instance
          local names = {}
          for name in pairs(Stubs.Classes) do names[#names + 1] = name end
          table.sort(names)
          for _, name in ipairs(names) do
            local cls = Stubs.Classes[name]
            local ok, inst = pcall(Instance.new, name)
            if ok then
              for k, m in pairs(cls.members) do
                if m.kind == "prop" and k ~= "Source" and k ~= "Parent" then
                  local ok2, v = pcall(function() return inst[k] end)
                  if not ok2 then
                    out[#out + 1] = name .. "." .. k .. " read: " .. tostring(v)
                  elseif not m.ro then
                    local ok3, e = pcall(function() inst[k] = v end)
                    if not ok3 then out[#out + 1] = name .. "." .. k .. " write: " .. tostring(e) end
                  end
                end
              end
              local ok4, e4 = pcall(function() local c = inst:Clone(); if c then c.Parent = w.workspace; c:Destroy() end end)
              if not ok4 then out[#out + 1] = name .. " clone/destroy: " .. tostring(e4) end
            end
          end
          for cname, svc in pairs(w.serviceByClass) do
            for k, m in pairs(Stubs.Classes[cname].members) do
              if m.kind == "prop" and k ~= "Source" then
                local ok2, v = pcall(function() return svc[k] end)
                if not ok2 then out[#out + 1] = cname .. "." .. k .. " read: " .. tostring(v) end
              end
            end
          end
          return out
        end"""
    )(w.w, w.stubs)
    assert list(problems.values()) == []
    w.assert_no_errors()


# ============================================================================ integration: adapter-like scripts
MINI_SERVER = r"""
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Core = require(script.Parent:WaitForChild("MiniCore"))
Players.CharacterAutoLoads = false
local folder = ReplicatedStorage:FindFirstChild("BattleCity") or Instance.new("Folder")
folder.Name = "BattleCity"
folder.Parent = ReplicatedStorage
local input = folder:FindFirstChild("Input") or Instance.new("RemoteEvent")
input.Name = "Input"
input.Parent = folder
folder:SetAttribute("MapCenter", Vector3.new(52, 1, 52))
folder:SetAttribute("MapSize", Vector3.new(104, 0, 104))
local world = Instance.new("Folder")
world.Name = "BattleCity"
world.Parent = workspace
local field = Instance.new("Folder")
field.Name = "Field"
field.Parent = world
local dyn = Instance.new("Folder")
dyn.Name = "Dynamic"
dyn.Parent = world
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end
for i = 0, 25 do
	part({ Name = "Brick" .. i, Size = Vector3.new(2, 6, 2), Position = Vector3.new(i * 4 + 1, 4, 9), Material = Enum.Material.Brick, Color = Color3.fromRGB(160, 80, 40), Parent = field })
end
local eagle = part({ Name = "Eagle", Size = Vector3.new(8, 1, 8), Position = Vector3.new(52, 1.5, 100), Material = Enum.Material.Neon, Parent = field })
local sg = Instance.new("SurfaceGui")
sg.Face = Enum.NormalId.Top
sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
sg.PixelsPerStud = 20
sg.Parent = eagle
local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromScale(1, 1)
lbl.BackgroundTransparency = 1
lbl.Text = "🦅"
lbl.TextScaled = true
lbl.Font = Enum.Font.Arcade
lbl.Parent = sg
local tank = Instance.new("Model")
tank.Name = "Tank1"
local root = part({ Name = "Root", Size = Vector3.new(1, 1, 1), Transparency = 1, Parent = tank })
part({ Name = "Hull", Size = Vector3.new(7, 2, 7), Position = Vector3.new(0, 1, 0), Color = Color3.fromRGB(230, 200, 40), Parent = tank })
part({ Name = "Barrel", Size = Vector3.new(1, 1, 4), Position = Vector3.new(0, 2.5, -3), Parent = tank })
tank.PrimaryPart = root
tank.Parent = dyn
local slots = {}
local state = { dir = -1, fire = false }
input.OnServerEvent:Connect(function(player, dir, fire)
	if type(dir) ~= "number" or dir ~= math.floor(dir) or dir < -1 or dir > 3 then
		return
	end
	if type(fire) ~= "boolean" then
		return
	end
	state.dir, state.fire = dir, fire
end)
local function onPlayer(p)
	local slot = 0
	if not slots[1] then
		slot = 1
	elseif not slots[2] then
		slot = 2
	end
	if slot > 0 then
		slots[slot] = p
	end
	p:SetAttribute("BattleCitySlot", slot)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
local x, z = 52, 90
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc = math.min(acc + dt, 0.25)
	while acc >= Core.TICK - 1e-9 do
		acc = acc - Core.TICK
		if state.dir == 0 then
			z = z - 0.4
		elseif state.dir == 1 then
			x = x + 0.4
		elseif state.dir == 2 then
			z = z + 0.4
		elseif state.dir == 3 then
			x = x - 0.4
		end
	end
	local d = state.dir < 0 and 0 or state.dir
	tank:PivotTo(CFrame.new(x, 1, z) * CFrame.Angles(0, -d * math.pi / 2, 0))
	if state.fire then
		state.fire = false
		local boom = part({ Name = "Explosion", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Material = Enum.Material.Neon, Position = Vector3.new(x, 2, z), Parent = dyn })
		TweenService:Create(boom, TweenInfo.new(0.3), { Size = Vector3.new(6, 6, 6), Transparency = 1 }):Play()
		Debris:AddItem(boom, 0.35)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(80, 30)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.AlwaysOnTop = true
		bb.Adornee = boom
		bb.Parent = boom
	end
	if folder:GetAttribute("Phase") ~= "playing" then
		folder:SetAttribute("Phase", "playing")
		folder:SetAttribute("PhaseStartedAt", workspace:GetServerTimeNow())
	end
	folder:SetAttribute("Tally", HttpService:JSONEncode({ stageNumber = 1, players = { { kills = { 1, 0, 0, 0 } } } }))
end)
"""

MINI_CLIENT = r"""
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local folder = game:GetService("ReplicatedStorage"):WaitForChild("BattleCity")
local input = folder:WaitForChild("Input")
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
local camera = workspace.CurrentCamera
local center = folder:GetAttribute("MapCenter")
RunService:BindToRenderStep("BattleCityCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local vp = camera.ViewportSize
	local tanV = math.tan(math.rad(camera.FieldOfView / 2))
	local h = math.max((52 + 8) / tanV, (52 + 8) / (tanV * vp.X / vp.Y))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, h, h * 0.03), center)
end)
local gui = Instance.new("ScreenGui")
gui.Name = "BattleCityHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local phase = Instance.new("TextLabel")
phase.Name = "Phase"
phase.Font = Enum.Font.Arcade
phase.Parent = gui
folder:GetAttributeChangedSignal("Phase"):Connect(function()
	phase.Text = string.upper(folder:GetAttribute("Phase"))
end)
local held, order, fire, last = {}, {}, false, nil
local KEYS = { [Enum.KeyCode.W] = 0, [Enum.KeyCode.Up] = 0, [Enum.KeyCode.D] = 1, [Enum.KeyCode.S] = 2, [Enum.KeyCode.A] = 3 }
local function send()
	local dir = -1
	for i = #order, 1, -1 do
		if held[order[i]] then
			dir = KEYS[order[i]]
			break
		end
	end
	local key = dir .. tostring(fire)
	if key ~= last then
		last = key
		input:FireServer(dir, fire)
	end
end
UIS.InputBegan:Connect(function(io, gp)
	if gp then
		return
	end
	if KEYS[io.KeyCode] then
		held[io.KeyCode] = true
		table.insert(order, io.KeyCode)
		send()
	elseif io.KeyCode == Enum.KeyCode.Space then
		fire = true
		send()
	end
end)
UIS.InputEnded:Connect(function(io)
	if KEYS[io.KeyCode] then
		held[io.KeyCode] = nil
		for i = #order, 1, -1 do
			if order[i] == io.KeyCode then
				table.remove(order, i)
			end
		end
		send()
	elseif io.KeyCode == Enum.KeyCode.Space then
		fire = false
		send()
	end
end)
"""


@pytest.mark.parametrize("behavior", ["Immediate", "Deferred"])
def test_typical_server_and_client_scripts_run_cleanly(behavior, tmp_path):
    w = World(signal_behavior=behavior)
    (tmp_path / "MiniServer.lua").write_text(MINI_SERVER, encoding="utf-8")
    (tmp_path / "MiniClient.lua").write_text(MINI_CLIENT, encoding="utf-8")
    (tmp_path / "MiniCore.lua").write_text("local Core = {}\nCore.TICK = 1 / 60\nreturn Core\n", encoding="utf-8")
    early = w.add_player("Early", 1)  # joined before the server script starts
    w.add_module("ServerScriptService", "MiniCore", str(tmp_path / "MiniCore.lua"))
    ok, err, _ = w.run_script(str(tmp_path / "MiniServer.lua"))
    assert ok, err
    late = w.add_player("Late", 2)
    third = w.add_player("Third", 3)
    for p in (early, late):
        ok, err, _ = w.run_local_script(str(tmp_path / "MiniClient.lua"), p)
        assert ok, err
    w.advance(0.5)
    assert [w.attr(p, "BattleCitySlot") for p in (early, late, third)] == [1, 2, 0]
    assert w.get(early, "Character") is None
    rs = w.find("ReplicatedStorage.BattleCity")
    assert w.attr(rs, "MapCenter") == (52, 1, 52)
    assert w.attr(rs, "Phase") == "playing"
    assert w.get("Players.Early.PlayerGui.BattleCityHUD.Phase", "Text") == "PLAYING"
    cam = w.value(w.get(w.camera(early), "CFrame"))
    assert cam[0] == approx(52) and cam[1] > 50
    root = w.find("Workspace.BattleCity.Dynamic.Tank1.Root")
    z0 = w.value(w.get(root, "Position"))[2]
    w.key_down(early, "W")
    w.advance(0.5)
    z1 = w.value(w.get(root, "Position"))[2]
    assert z1 < z0 - 5
    w.key_down(early, "D")  # most recent key wins
    w.advance(0.25)
    assert w.value(w.get("Workspace.BattleCity.Dynamic.Tank1.Barrel", "CFrame"))[0] > w.value(w.get(root, "Position"))[0]
    w.key_up(early, "D")
    w.key_up(early, "W")
    w.key_down(early, "Space")
    w.advance(3 / 60)
    assert w.find("Workspace.BattleCity.Dynamic.Explosion") is not None
    w.advance(0.5)
    assert w.find("Workspace.BattleCity.Dynamic.Explosion") is None
    w.remove_player(early)
    w.advance(0.2)
    w.assert_no_errors(allow_warnings=False)


def test_suspicious_but_legal_usage_warns(w):
    w.eval("local p = Instance.new('Part', workspace); p.Name = 'Pool'; p.Material = Enum.Material.Water")
    assert any("Terrain-only" in x for x in w.warnings())
    w.eval("local m = Instance.new('Model', workspace); m.Name = 'M'; local p = Instance.new('Part'); m.PrimaryPart = p")
    assert any("not a descendant of the Model" in x for x in w.warnings())
    n = len(w.warnings())
    w.eval("local m = Instance.new('Model', workspace); local p = Instance.new('Part', m); m.PrimaryPart = p")
    assert len(w.warnings()) == n


def test_deferred_signal_behavior_option():
    w = World(signal_behavior="Deferred")
    w.run_source(
        """
        local be = Instance.new("BindableEvent")
        local got = 0
        local c = be.Event:Connect(function(n) got = got + n end)
        be:Fire(1)
        print("right after Fire", got)   -- deferred: handler has not run yet
        task.wait()
        print("after yield", got)
        be:Fire(5)
        c:Disconnect()                   -- disconnected before the deferred handler runs
        task.wait()
        print("after disconnect", got)
        """
    )
    w.advance(3 / 60)
    assert w.output() == ["right after Fire 0", "after yield 1", "after disconnect 1"]
    # the mini adapter scripts also work in deferred mode
    w.assert_no_errors()


def test_more_classes_and_enums_exist(w):
    ok_eval(w, "local f = Instance.new('ForceField'); local b = Instance.new('BoxHandleAdornment'); b.Size = Vector3.new(1, 2, 3); b.AlwaysOnTop = true")
    ok_eval(w, "local t = Instance.new('TextLabel'); t.FontSize = Enum.FontSize.Size24")
    ok_eval(w, "game.StarterPlayer.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable")
    assert w.eval("return game:GetService('VRService').VREnabled") is False
