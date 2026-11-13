#!/usr/bin/env python3
"""Spreads a level out so that less of it is on screen at once, keeping every object.

A recipe below stretches an original level from E:/rezguard/data: a column or a row is repeated, without its objects.
Terrain stays in its style, since a long floor is the same floor. The result goes to wms/levels/N.xml, which gen_assets.py uses in place of the original.

usage: relayout.py LEVEL       writes the level, checks it, and prints what any one view holds, before and after
"""
import os
import sys
import xml.etree.ElementTree as ET
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
WMS = os.path.dirname(HERE)
DATA = os.path.join(os.path.dirname(WMS), "data")
OUT = os.path.join(WMS, "levels")
VIEW_W, VIEW_H = 24, 19      # a view, in cells

PLATFORM, FLOATY, LAVA, LAVA2 = 1, 2, 3, 9
TERRAIN = {PLATFORM, FLOATY, LAVA, LAVA2}
TRIGGER = 48
AMBUSH = {36, 38, 40, 41, 42}
TRIGGER_REACH = 10           # an ambush further than this from every trigger never gets up
JUMP_REACH = 6               # cells: raised terrain this close together is a chain of jumps, so it is not moved apart
BANNER, MESSAGE = {62, 72}, 49

KIND = {12: "melee", 14: "melee", 16: "melee", 18: "melee", 19: "melee", 13: "trooper", 61: "trooper", 17: "trooper", 22: "ally", 23: "ally",
        24: "mine", 25: "mine", 36: "ambush", 38: "ambush", 40: "ambush", 41: "ambush", 42: "ambush", 43: "resting", 44: "resting", 45: "resting"}
for s in (28, 57, 58, 59, 26, 27):
    KIND[s] = "turret"
for s in (51, 52, 53, 54, 63, 64, 65, 66):
    KIND[s] = "piglet"
for s in range(30, 36):
    KIND[s] = "beam"

# Original coordinates, in the order of play. ("col", x, n) repeats column x n times; ("row", y, n) repeats row y n times.
RECIPES = {
    1: [
        # The first shaft. The man on the upper floor no longer sees the room he will drop into.
        ("row", 12, 7),
        # One flat stretch of the upper floor splits the crowd of troopers around it. Nothing in jump range is moved apart.
        ("col", 122, 10),
    ],
    5: [
        # The west half of the middle band drops away from the top band, as far as its tunnel, so the two rows of ceiling guns are never in one
        # view, and the top band's guns are out of sight from the tunnel. The stretch where creatures fire down through the floating floor stays.
        ("rows", 8, 7, 0, 44),       # the shaft down into the piglet maze
        ("rows", 7, 7, 45, 71),      # rock over the start, the gun corridor and the tunnel
        # The lower corridor under the lava pit drops away from the top band's hall: a longer drop into it at the west end.
        ("rows", 12, 6, 85, 88),
        ("rows", 8, 6, 89, 110),
        ("rows", 11, 6, 111, 120),
        # The bottom band drops away from the middle band: the shaft to it gets longer. Rows below stay level across the whole map.
        ("rows", 20, 4, 0, 71),
        ("rows", 20, 11, 72, 84),
        ("rows", 20, 5, 85, 120),
        ("rows", 20, 11, 121, 149),
        # Each lowered stretch climbs back up at its east end, by a chimney of floating platforms such as this level already uses.
        ("open", 70, 71, 9, 17),     # from the tunnel to the floor under the floating floor
        ("floaty", 70, 71, 17),
        ("floaty", 70, 71, 15),
        ("floaty", 70, 71, 13),
        ("open", 119, 120, 11, 18),  # from the lower corridor to the room of exploding platforms
        ("floaty", 119, 120, 18),
        ("floaty", 119, 120, 16),
        ("floaty", 119, 120, 14),
        # The crystal's side of the piglet maze is optional. A longer way in, through rock that was already there, keeps its worms out of the
        # view on the main route. The maze and the worms are the same.
        ("cols", 15, 9, 16, 18, 43),
    ],
}


def load(path):
    return [[int((c.text or "0").strip() or 0) - 1 for c in r.findall("tilecol")] for r in ET.parse(path).getroot().findall("tilerow")]


def terrain(v):
    return v if v in TERRAIN else 0


def apply_recipe(rows, recipe):
    """Rows and columns use original coordinates: applied from the bottom right, each step's coordinates still hold.
    "open" and "floaty" carve the finished map, so they use its coordinates, and they apply last."""
    rows = [list(r) for r in rows]
    for op in sorted((o for o in recipe if o[0] == "col"), key=lambda o: -o[1]):
        _, at, n = op
        for r in rows:
            r[at + 1:at + 1] = [terrain(r[at])] * n
    W = len(rows[0])
    # Whole rows, or rows within a span of columns. A column's cells shift down, so every column must end up the same height.
    grow = [[] for _ in range(W)]
    for op in recipe:
        if op[0] == "row":
            for x in range(W):
                grow[x].append((op[1], op[2]))
        elif op[0] == "rows":
            for x in range(op[3], op[4] + 1):
                grow[x].append((op[1], op[2]))
    if any(grow):
        heights = {sum(n for _, n in g) for g in grow}
        if len(heights) != 1:
            raise SystemExit(f"columns would end up different heights: {sorted(heights)}")
        H = len(rows)
        out = []
        for x in range(W):
            col = [rows[y][x] for y in range(H)]
            for y, n in sorted(grow[x], reverse=True):
                col[y + 1:y + 1] = [terrain(col[y])] * n
            out.append(col)
        rows = [[out[x][y] for x in range(W)] for y in range(H + heights.pop())]
    for op in recipe:
        if op[0] == "cols":
            # In the finished map: rows y0..y1 repeat the cells of column at, taking the room from solid rock that ends at x_end.
            _, at, n, y0, y1, x_end = op
            for y in range(y0, y1 + 1):
                r = rows[y]
                if any(v != PLATFORM for v in r[x_end - n + 1:x_end + 1]):
                    raise SystemExit(f"row {y}: columns up to {x_end} are not all rock")
                r[at + 1:at + 1] = [terrain(r[at])] * n
                del r[x_end + 1:x_end + n + 1]
        elif op[0] == "open":
            _, x0, x1, y0, y1 = op
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    if rows[y][x] in TERRAIN:
                        rows[y][x] = 0
        elif op[0] == "floaty":
            _, x0, x1, y = op
            for x in range(x0, x1 + 1):
                if rows[y][x] > 0 and rows[y][x] not in TERRAIN:
                    raise SystemExit(f"a floating platform would cover an object at {x},{y}")
                rows[y][x] = FLOATY
    return rows


def reachable(rows):
    """Where the man can stand, from his start: he walks, falls, and jumps up to 2 cells and across up to 4.
    He jumps up through floating platforms, and lava is never a place to stand. Exploding platforms hold him."""
    H, W = len(rows), len(rows[0])
    EXPLODING = {10, 11}
    def solid(x, y):
        return not (0 <= x < W and 0 <= y < H) or rows[y][x] == PLATFORM
    def stands(x, y):
        return y + 1 < H and (rows[y + 1][x] in (PLATFORM, FLOATY) or rows[y + 1][x] in EXPLODING)
    def land(x, y):
        while y < H and not solid(x, y):
            if rows[y][x] in (LAVA, LAVA2):
                return None
            if stands(x, y):
                return y
            y += 1
        return None
    start = next((x, y) for y in range(H) for x in range(W) if rows[y][x] in (20, 21))
    seen = {(start[0], land(*start))}
    todo = list(seen)
    while todo:
        x, y = todo.pop()
        for rise in (0, 1, 2):
            if rise and solid(x, y - rise):
                break
            for step in (1, -1):
                for dx in range(0, 5):
                    tx = x + step * dx
                    if solid(tx, y - rise):
                        break
                    ty = land(tx, y - rise)
                    if ty is not None and (tx, ty) not in seen:
                        seen.add((tx, ty))
                        todo.append((tx, ty))
    return seen


def objects(rows):
    return [(v, x, y) for y, r in enumerate(rows) for x, v in enumerate(r) if v > 0 and v not in TERRAIN]


def in_jump_chain(rows, at):
    """True if the nearest terrain each way along this column's floor stands above that floor, close enough to jump between."""
    H, W = len(rows), len(rows[0])
    col = [terrain(rows[y][at]) for y in range(H)]
    # The open run the man would stand in: the lowest one, as a floor is what he runs on.
    floor = max(y for y in range(1, H) if rows[y][at] == PLATFORM and rows[y - 1][at] not in TERRAIN)
    top = floor - 1
    while top > 0 and rows[top - 1][at] not in TERRAIN:
        top -= 1
    def raised(step):
        x, gap = at + step, 0
        while 0 <= x < W and [terrain(rows[y][x]) for y in range(H)] == col:
            x += step
            gap += 1
        if not 0 <= x < W:
            return None
        return gap if any(rows[y][x] in TERRAIN for y in range(top, floor)) else None
    a, b = raised(-1), raised(1)
    return a is not None and b is not None and a + b + 1 <= JUMP_REACH


def check_recipe(rows, recipe):
    """Stretching must only lengthen what is already even: a repeated column must match a neighbor, or a gap or an obstacle would change."""
    bad = []
    H = len(rows)
    for step in recipe:
        if step[0] in ("open", "floaty", "cols"):
            continue
        op, at, n = step[:3]
        if op == "rows":
            for x in range(step[3], step[4] + 1):
                if rows[at][x] > 0 and rows[at][x] not in TERRAIN:
                    bad.append(f"row {at} holds an object at {x}")
                if rows[at][x] == FLOATY:
                    bad.append(f"row {at} would stack a floating platform at {x}")
            continue
        if op == "col":
            col = lambda x: [terrain(rows[y][x]) for y in range(H)]
            if col(at) != col(at - 1) and col(at) != col(at + 1):
                bad.append(f"column {at} is unlike both neighbors")
            floors = [y for y in range(1, H) if not rows[y - 1][at] in TERRAIN and rows[y][at] == PLATFORM]
            if not floors:
                bad.append(f"column {at} has no floor")
            elif in_jump_chain(rows, at):
                bad.append(f"column {at} lies between raised terrain in jump range")
        elif op == "row":
            for x, v in enumerate(rows[at]):
                if v > 0 and v not in TERRAIN:
                    bad.append(f"row {at} holds an object at {x}")
    return bad


def spread_of(objs, a, b):
    return [(abs(p[1] - q[1]), abs(p[2] - q[2])) for p in objs if p[0] in a for q in objs if q[0] in b]


def check_level(old, new):
    bad = []
    if Counter(o[0] for o in objects(old)) != Counter(o[0] for o in objects(new)):
        bad.append("objects were lost or added")
    o, n = objects(old), objects(new)
    # The man can still stand next to everything he could before: above all, the goal and the respawn points.
    def near(rows, syms):
        here = reachable(rows)
        cells = [(x, y) for y, r in enumerate(rows) for x, v in enumerate(r) if v in syms]
        return len(here), sum(any(abs(c[0] - p[0]) <= 1 and abs(c[1] - p[1]) <= 2 for p in here) for c in cells), len(cells)
    for name, syms in (("goal cells", {4}), ("respawn points", {50})):
        a, b = near(old, syms), near(new, syms)
        print(f"the man can reach {b[1]} of {b[2]} {name}, and {a[1]} of {a[2]} before (he can stand in {a[0]} places before, {b[0]} after)")
        if b[1] != a[1]:
            bad.append(f"{name} in reach changed")
    # Every ambush that a trigger woke still has one in reach.
    def woken(objs):
        ts = [p for p in objs if p[0] == TRIGGER]
        return [p for p in objs if p[0] in AMBUSH and any(abs(p[1] - t[1]) <= TRIGGER_REACH and abs(p[2] - t[2]) <= TRIGGER_REACH for t in ts)]
    if len(woken(o)) != len(woken(n)):
        bad.append(f"ambushes in a trigger's reach: {len(woken(o))} before, {len(woken(n))} after")
    # A message is shown where its banner can be seen when it trips.
    def seen(objs):
        ms, bs = [p for p in objs if p[0] == MESSAGE], [p for p in objs if p[0] in BANNER]
        return sum(any(abs(m[1] - b[1]) <= VIEW_W // 2 and abs(m[2] - b[2]) <= VIEW_H // 2 for b in bs) for m in ms)
    if seen(o) != seen(n):
        bad.append(f"messages near their banner: {seen(o)} before, {seen(n)} after")
    return bad


def crowding(rows):
    """For every view: how many of each kind, and how much terrain edge. Worst and average over views the man can stand in."""
    H, W = len(rows), len(rows[0])
    objs = [(KIND[o[0]], o[1], o[2]) for o in objects(rows) if o[0] in KIND]
    is_solid = [[v in TERRAIN for v in r] for r in rows]
    worst, total, views = Counter(), Counter(), 0
    busy = []
    for wx in range(0, max(W - VIEW_W, 0) + 1):
        for wy in range(0, max(H - VIEW_H, 0) + 1):
            cx, cy = wx + VIEW_W // 2, wy + VIEW_H // 2
            if is_solid[cy][cx]:
                continue         # nobody stands here
            c = Counter(k for k, x, y in objs if wx <= x < wx + VIEW_W and wy <= y < wy + VIEW_H)
            c["all"] = sum(v for k, v in c.items() if k != "resting")
            views += 1
            for k, v in c.items():
                worst[k] = max(worst[k], v)
                total[k] += v
            busy.append((c["all"], wx, wy))
    return worst, {k: v / max(views, 1) for k, v in total.items()}, busy


def write(rows, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("<map>\n")
        for r in rows:
            f.write("<tilerow>\n" + "".join(f"<tilecol>{v + 1}</tilecol>" for v in r) + "\n</tilerow>\n")
        f.write("</map>\n")


def main():
    n = int(sys.argv[1])
    old = load(os.path.join(DATA, f"{n}.xml"))
    recipe = RECIPES[n]
    bad = check_recipe(old, recipe)
    new = apply_recipe(old, recipe)
    bad += check_level(old, new)
    print(f"level {n}: {len(old[0])}x{len(old)} becomes {len(new[0])}x{len(new)}, objects {len(objects(old))} and {len(objects(new))}")
    a, am, _ = crowding(old)
    b, bm, busy = crowding(new)
    print(f"{'in one view':12}{'worst before':>14}{'after':>7}{'mean before':>13}{'after':>7}")
    for k in sorted(set(a) | set(b)):
        print(f"{k:12}{a[k]:>14}{b[k]:>7}{am.get(k, 0):>13.1f}{bm.get(k, 0):>7.1f}")
    print("busiest views after (count, cell):", sorted(busy, reverse=True)[:1])
    gaps = lambda rows: [q - p for p, q in zip(*(lambda xs: (xs, xs[1:]))(sorted(o[1] for o in objects(rows) if o[0] == 50)))]
    print("cells between respawn points, by x: before", gaps(old), "after", gaps(new))
    for line in bad:
        print("PROBLEM:", line)
    if bad:
        raise SystemExit(1)
    write(new, os.path.join(OUT, f"{n}.xml"))
    print("wrote", os.path.join(OUT, f"{n}.xml"))


main()
