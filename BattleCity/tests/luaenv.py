"""Helpers for running the BattleCity Lua files under PUC Lua 5.1 (closest to Roblox Luau).

Install once:  pip install lupa pytest
Run:           python -m pytest BattleCity/tests
"""
import os

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # BattleCity/


def path(*parts):
    return os.path.join(ROOT, *parts)


def new_runtime():
    return lua51.LuaRuntime(unpack_returned_tuples=True)


def load_file(lua, file_path):
    """Run a Lua file that `return`s a value (ModuleScript style) and give back that value."""
    with open(file_path, encoding="utf-8") as f:
        src = f.read()
    loader = lua.eval("function(src, name) local fn, err = loadstring(src, '@' .. name); if not fn then error(err, 0) end; return fn() end")
    return loader(src, os.path.basename(file_path))


def to_py(value):
    """Recursively convert Lua tables to python dict/list (1-based sequential tables become lists)."""
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    try:
        keys = list(value.keys())
    except AttributeError:
        return value
    if keys and all(isinstance(k, (int, float)) and k == int(k) for k in keys):
        ints = sorted(int(k) for k in keys)
        if ints == list(range(1, len(ints) + 1)):
            return [to_py(value[i]) for i in ints]
    return {k: to_py(value[k]) for k in keys}
