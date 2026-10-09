"""Validates stage layouts in BattleCityStages.lua (or any stage file given on the command line).

    python BattleCity/tests/test_stages.py path/to/stages.lua   # report for one file
    python -m pytest BattleCity/tests/test_stages.py             # checks the real module
"""
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv  # noqa: E402

N = 26
VALID = set(".BSWTIE")
BASE_CELLS = {(12, 24), (13, 24), (12, 25), (13, 25)}
RING_CELLS = {(11, 23), (12, 23), (13, 23), (14, 23), (11, 24), (11, 25), (14, 24), (14, 25)}
ENEMY_SPAWNS = [(0, 0), (12, 0), (24, 0)]          # top-left cell of each 2x2 tank tile
PLAYER_SPAWNS = [(8, 24), (16, 24)]
SPAWN_CELLS = {(cx + dx, cy + dy) for cx, cy in ENEMY_SPAWNS + PLAYER_SPAWNS for dx in (0, 1) for dy in (0, 1)}
# places from which an enemy can shoot straight into the base (bricks on the way are fine)
ATTACK_POSITIONS = [(12, 21), (9, 24), (15, 24)]
# recommended share of the 676 cells (soft limits -> warnings)
SOFT_LIMITS = {"B": (0.12, 0.55), "S": (0.0, 0.14), "W": (0.0, 0.18), "T": (0.0, 0.28), "I": (0.0, 0.32)}
ENEMY_CHARS = set("bfpa")


def tank_can_stand(rows, cx, cy):
    """A 16px tank (2x2 cells) can occupy (cx, cy) if no steel/water/base is under it (bricks can be shot away)."""
    if not (0 <= cx <= N - 2 and 0 <= cy <= N - 2):
        return False
    for dx in (0, 1):
        for dy in (0, 1):
            if rows[cy + dy][cx + dx] in "SWE":
                return False
    return True


def reachable(rows, start):
    seen = {start}
    queue = deque([start])
    while queue:
        cx, cy = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (cx + dx, cy + dy)
            if nxt not in seen and tank_can_stand(rows, *nxt):
                seen.add(nxt)
                queue.append(nxt)
    return seen


def validate_stage(stage, label):
    errors, warnings = [], []
    name = stage.get("name") if isinstance(stage, dict) else None
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{label}: missing name")
    rows = stage.get("map") if isinstance(stage, dict) else None
    if not isinstance(rows, list) or len(rows) != N:
        errors.append(f"{label}: map must have {N} rows (has {len(rows) if isinstance(rows, list) else 'none'})")
        return errors, warnings
    for r, row in enumerate(rows):
        if not isinstance(row, str) or len(row) != N:
            errors.append(f"{label}: row {r + 1} must be {N} chars (has {len(row) if isinstance(row, str) else 'n/a'})")
        elif set(row) - VALID:
            errors.append(f"{label}: row {r + 1} has invalid chars {sorted(set(row) - VALID)}")
    if errors:
        return errors, warnings

    for (cx, cy) in BASE_CELLS:
        if rows[cy][cx] != "E":
            errors.append(f"{label}: base cell (col {cx}, row {cy}) must be 'E'")
    for (cx, cy) in RING_CELLS:
        if rows[cy][cx] != "B":
            errors.append(f"{label}: base ring cell (col {cx}, row {cy}) must be 'B'")
    for (cx, cy) in SPAWN_CELLS:
        if rows[cy][cx] != ".":
            errors.append(f"{label}: spawn cell (col {cx}, row {cy}) must be '.'")
    extra_e = [(c, r) for r in range(N) for c in range(N) if rows[r][c] == "E" and (c, r) not in BASE_CELLS]
    if extra_e:
        errors.append(f"{label}: 'E' only allowed on the base cells, found at {extra_e[:5]}")

    for spawn in ENEMY_SPAWNS:
        seen = reachable(rows, spawn)
        if not any(p in seen for p in ATTACK_POSITIONS):
            errors.append(f"{label}: enemy spawn {spawn} cannot reach the base (steel/water blocks every route)")
    for spawn in PLAYER_SPAWNS:
        seen = reachable(rows, spawn)
        for target in ENEMY_SPAWNS:
            if target not in seen:
                errors.append(f"{label}: player spawn {spawn} cannot reach enemy spawn {target}")

    enemies = stage.get("enemies")
    if not isinstance(enemies, str) or len(enemies) != 20 or set(enemies) - ENEMY_CHARS:
        errors.append(f"{label}: enemies must be 20 chars of b/f/p/a (got {enemies!r})")

    counts = {ch: sum(row.count(ch) for row in rows) for ch in "BSWTI"}
    for ch, (lo, hi) in SOFT_LIMITS.items():
        share = counts[ch] / (N * N)
        if share < lo or share > hi:
            warnings.append(f"{label}: '{ch}' covers {share:.0%} of the map (recommended {lo:.0%}-{hi:.0%})")
    return errors, warnings


def validate_file(file_path, first_number=1):
    lua = luaenv.new_runtime()
    stages = luaenv.to_py(luaenv.load_file(lua, file_path))
    errors, warnings = [], []
    if not isinstance(stages, list) or not stages:
        return [f"{file_path}: must return a non-empty array of stages"], [], []
    names = {}
    layouts = {}
    for k, stage in enumerate(stages):
        label = f"stage {first_number + k}"
        e, w = validate_stage(stage, label)
        errors += e
        warnings += w
        if isinstance(stage, dict):
            nm = stage.get("name")
            if nm in names:
                errors.append(f"{label}: duplicate name {nm!r} (also {names[nm]})")
            names[nm] = label
            key = "\n".join(stage.get("map") or [])
            if key in layouts:
                errors.append(f"{label}: identical layout to {layouts[key]}")
            layouts[key] = label
    return errors, warnings, stages


def test_stage_module():
    errors, warnings, stages = validate_file(luaenv.path("BattleCityStages.lua"))
    assert not errors, "\n".join(errors)
    assert len(stages) == 35, f"expected 35 stages, got {len(stages)}"


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else luaenv.path("BattleCityStages.lua")
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    result = validate_file(target, first)
    errs, warns = result[0], result[1]
    for w in warns:
        print("WARN ", w)
    for e in errs:
        print("ERROR", e)
    print(f"{len(errs)} error(s), {len(warns)} warning(s)")
    sys.exit(1 if errs else 0)
