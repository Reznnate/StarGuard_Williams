"""The terrain the boss changes, drawn as the original draws it. Used by gen_assets.py.

Main.SetCellRectangle in the original sets its cells and rebuilds the tile corners from one cell up and left of the rect
to the level's ends (Tile.MakeRectangleSeamless), so the platforms around a changed rect get the edges the new cells call
for. Main.SetCellType rebuilds nothing, but on level 9 it only moves cells between types that are not PLATFORM (the
hallway's PlatformDestructibles), and a corner only asks whether a neighbour is PLATFORM. So what the original shows
is always the corners of the cells as they are now. A PLATFORM cell is opaque black with a yellow line along each side
whose neighbour is not PLATFORM (out of the level counts as PLATFORM), and a yellow dot in a corner whose two sides are
PLATFORM and whose diagonal is not. FLOATY_PLATFORM, LAVA and LAVA2 are whole sprites.

The boss changes cells only through the groups of rects below. The cells they can change, and the PLATFORM cells next to
them, are split into rectangular regions. Every layout of the changeable cells that any order of the groups can make is
found, and for each region every look it can have. gen_assets.py cuts the level's own terrain at the regions' edges and
adds each other look as terrain rects of its own, all marked RECT_HIDE, with a table saying which looks each shows in.
The engine (boss_terrain.asm) works out each region's look from the cells as they are, the terrain routines draw only
the rects of the looks the regions have, and when a region's look changes its old rects are erased and its new drawn.
tools/regioncheck.py checks the result against the original for every layout."""

EMPTY, PLATFORM, FLOATY, LAVA, LAVA2 = 0, 1, 3, 4, 5
PLATFORM_DESTRUCTIBLE = 2
IMAGE = (2, 6, 8)           # destructible, exploding, buried: images of their own
TILE = 12
YELLOW = 0x22
FLOATY_SPRITE = 58
SPRITE_ITEM = 0xFF          # an item's solid byte: the floaty platform's sprite at its x, y

# Destructible blocks the boss makes, which the level begins without: Wizard_p2_3.SetupHallway's barrier,
# PlatformDestructible(4 + i + 44, -1 + j + startY / 12) for i < 5, j < 3, with startX 0 and startY / 12 = 32. They go in
# the ROM grid as blocks, drawn and shot like any other, and Level_Load marks them gone (the absent list in the table).
ABSENT = {9: [(x, y) for x in range(48, 53) for y in range(31, 34)]}

# wizard.asm's Main_SetCellRectangle calls, as groups that run together: (type, x, y, w, h), in cells. Wizard.as
# startCell (11, 26); Wizard_p3_3 start cell (81, 32). A run of the fight logs the same rects (tools/cellcheck.lua).
GROUPS = {9: [
    [(PLATFORM, 8, 31, 3, 1)],                                  # SetupBarriers1(true)
    [(EMPTY, 8, 31, 3, 1)],                                     # SetupBarriers1(false): the man died in phase 1
    [(EMPTY, 5, 31, 8, 3)],                                     # SetupHallwayLeft
    [(EMPTY, 22, 31, 4, 3)],                                    # OpenHallwayRight
    [(PLATFORM, 24, 31, 1, 3)],                                 # CloseHallwayRight: the man died in phase 2
    [(PLATFORM, 69, 31, 1, 3), (PLATFORM, 71, 29, 7, 1), (PLATFORM, 71, 35, 7, 1)],   # SetupPlatforms1
    [(PLATFORM, 71, 29, 7, 1), (PLATFORM, 71, 35, 7, 1)],       # p3_switch_state
    [(PLATFORM, 71, 29, 7, 1), (EMPTY, 71, 35, 7, 1), (PLATFORM, 71, 36, 7, 1)],      # p3_switch_phase
    [(PLATFORM, 71, 35, 7, 1)] + [(EMPTY, 72 + 2 * i, y, 1, 1) for i in range(3) for y in (29, 35)],  # FIRE_3, beams
    [(EMPTY, 84, 31, 1, 3), (FLOATY, 79, 34, 5, 1)],           # P3_Die: the way out and the bridge
]}


def changeable(groups):
    return sorted({(i, j) for g in groups for t, x, y, w, h in g for i in range(x, x + w) for j in range(y, y + h)},
                  key=lambda c: (c[1], c[0]))


def reachable(rom, groups, limit=20000):
    """Every layout of the changeable cells that the groups make, in any order, from the level's own."""
    keys = changeable(groups)
    at = {c: k for k, c in enumerate(keys)}
    start = tuple(rom[y][x] for x, y in keys)
    seen, todo = {start}, [start]
    while todo:
        cfg = todo.pop()
        for g in groups:
            new = list(cfg)
            for t, x, y, w, h in g:
                for j in range(y, y + h):
                    for i in range(x, x + w):
                        new[at[(i, j)]] = t
            new = tuple(new)
            if new not in seen:
                seen.add(new)
                todo.append(new)
                if len(seen) > limit:
                    raise SystemExit("the boss's cells have too many layouts")
    return keys, start, sorted(seen)


def port_reads_platform(t, rom_t):
    """What Main_GetCell answers, as PLATFORM or not, for a cell the original holds as t over the ROM grid's rom_t. The RAM
    map only says whether a cell differs from the grid: EMPTY asked for gives EMPTY, PLATFORM or FLOATY_PLATFORM over an
    EMPTY grid cell gives PLATFORM, and anything else leaves the grid's type."""
    if t == EMPTY:
        return False
    if t in (PLATFORM, FLOATY) and rom_t == EMPTY:
        return True
    return rom_t == PLATFORM


def lines(get, cells):
    """The look of the given cells: items (x, y, w, h, solid) in world pixels, solid YELLOW, $20 for the left pixel of
    a byte column or $02 for the right, or SPRITE_ITEM for a sprite. Vertical lines and dots first, then horizontal
    lines: a one pixel item writes black to the other pixel of its column, which is never lit except by those."""
    def plat(x, y):
        return get(x, y) == PLATFORM

    vert, dots, horiz, sprites = [], [], [], []
    for x, y in cells:
        c, X, Y = get(x, y), x * TILE, y * TILE
        if c == FLOATY:
            sprites.append((X, Y, 0, 0, SPRITE_ITEM))
        elif c in (LAVA, LAVA2):
            raise SystemExit(f"lava at {x}, {y} in a region the boss changes")
        elif c == PLATFORM:
            up, down, left, right = plat(x, y - 1), plat(x, y + 1), plat(x - 1, y), plat(x + 1, y)
            if not up:
                horiz.append((Y, X, X + TILE))
            if not down:
                horiz.append((Y + TILE - 1, X, X + TILE))
            if not left:
                vert.append((X, Y, Y + TILE))
            if not right:
                vert.append((X + TILE - 1, Y, Y + TILE))
            for dx, dy, px, py in ((-1, -1, X, Y), (1, -1, X + TILE - 1, Y), (-1, 1, X, Y + TILE - 1),
                                   (1, 1, X + TILE - 1, Y + TILE - 1)):
                if plat(x + dx, y) and plat(x, y + dy) and not plat(x + dx, y + dy):
                    dots.append((px, py))
    out = []
    # Merge touching runs: verticals by column, horizontals by line.
    for px, a, b in merge(vert):
        out.append((px, a, 1, b - a, 0x20 if px % 2 == 0 else 0x02))
    for px, py in sorted(dots):
        out.append((px, py, 1, 1, 0x20 if px % 2 == 0 else 0x02))
    for py, a, b in merge(horiz):
        out.append((a, py, b - a, 1, YELLOW))
    return out + sprites


def merge(runs):
    out = []
    for key, a, b in sorted(runs):
        if out and out[-1][0] == key and out[-1][2] == a:
            out[-1] = (key, out[-1][1], b)
        else:
            out.append((key, a, b))
    return out


def pixels(items):
    """The yellow pixels of a look (sprites left out), for checking it."""
    lit = set()
    for x, y, w, h, s in items:
        if s == SPRITE_ITEM:
            continue
        for j in range(y, y + h):
            for i in range(x, x + w):
                lit.add((i, j))
    return lit


def rectangles(cells):
    """Cells as rectangles (x0, y0, x1, y1), exclusive ends: runs along each line, merged with the same run below."""
    rows = {}
    for x, y in cells:
        rows.setdefault(y, set()).add(x)
    runs = []
    for y in sorted(rows):
        xs = sorted(rows[y])
        a = xs[0]
        for p, q in zip(xs, xs[1:] + [None]):
            if q != p + 1:
                runs.append((a, p + 1, y))
                a = q
    out = []
    for a, b, y in runs:
        for k, (x0, y0, x1, y1) in enumerate(out):
            if (x0, x1) == (a, b) and y1 == y:
                out[k] = (x0, y0, x1, y1 + 1)
                break
        else:
            out.append((a, y, b, y + 1))
    return out


def build(n, rom, W, H, rom_canvas_yellow):
    """Returns the regions, each (x0, y0, x1, y1, keys, looks, patterns) in cells, ends exclusive: keys the changeable
    cells near it whose PLATFORM-ness (as the engine reads it) tells its looks apart, looks the items of each look, the
    level's own first, and patterns (key bits, look) for every reading of the keys that is not the first look. Only regions that can look more than one way. rom_canvas_yellow is the set of yellow pixels
    of the level's own terrain, to check that each region's first look is it."""
    groups = GROUPS.get(n)
    if not groups:
        return []
    keys, start, configs = reachable(rom, groups)
    changing = set(keys)

    def get_in(cfg):
        vals = dict(zip(keys, cfg))

        def get(x, y):
            if not (0 <= x < W and 0 <= y < H):
                return PLATFORM
            v = vals.get((x, y), rom[y][x])
            return EMPTY if v in IMAGE else v
        return get
    # A cell's look can change if it can change, or if it is a platform next to one that can.
    near = {(x + dx, y + dy) for x, y in keys for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    cells = {c for c in near if 0 <= c[0] < W and 0 <= c[1] < H and (c in changing or rom[c[1]][c[0]] == PLATFORM)}
    for x, y in cells:
        if rom[y][x] in IMAGE:
            raise SystemExit(f"level {n}: a block at {x}, {y} next to cells the boss changes")
    regions = []
    for x0, y0, x1, y1 in rectangles(cells):
        inside = [(x, y) for y in range(y0, y1) for x in range(x0, x1)]
        around = {(x + dx, y + dy) for x, y in inside for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
        rkeys = [k for k in keys if k in around]
        looks = {}
        for cfg in configs:
            vals = dict(zip(keys, cfg))
            bits = tuple(port_reads_platform(vals[k], rom[k[1]][k[0]]) for k in rkeys)
            items = lines(get_in(cfg), inside)
            if bits in looks and looks[bits] != items:
                raise SystemExit(f"level {n}: region {x0},{y0} looks two ways for one reading of its cells")
            looks[bits] = items
        first_bits = tuple(port_reads_platform(rom[k[1]][k[0]], rom[k[1]][k[0]]) for k in rkeys)
        first = looks[first_bits]
        own = {p for p in rom_canvas_yellow if x0 * TILE <= p[0] < x1 * TILE and y0 * TILE <= p[1] < y1 * TILE}
        if pixels(first) != own:
            raise SystemExit(f"level {n}: region {x0},{y0}: its first look is not the level's own terrain")
        # Each look but the first once, and each reading of the keys that calls for one of those. Any other reading
        # (the engine finds no match) is the first look.
        distinct = [first]
        patterns = []
        for b, it in sorted(looks.items()):
            if it == first:
                continue
            if it not in distinct:
                distinct.append(it)
            patterns.append((b, distinct.index(it)))
        if not patterns:
            continue
        if len(distinct) > 8:
            raise SystemExit(f"level {n}: region {x0},{y0} has more than 8 looks")
        regions.append((x0, y0, x1, y1, rkeys, distinct, patterns))
    return regions


def table(n, regions, at, rect_count, rects_at, hide, rom, W):
    """The region table for the level's bank, at address at. hide: {rect address: (region, looks mask)}.
    A count of regions, the address of the look table (2), the address of the absent list (2), then per region: first and end byte column (2 each), first
    and end line (2 each), the address of its keys, of its readings and of its rects. Keys: a count, then per key its byte
    in the engine's map of changed cells (2), its bit there, and 1 if its grid cell is a platform. Readings: a count, then per reading its key bits, a byte per 8 keys from bit 7 down, and the look it calls for; a
    reading not listed is look 0, the level's own. Rects: a count, then the address of each rect marked RECT_HIDE in the
    region. The look table: 2 bytes for each of the level's rects, in order: for a rect marked RECT_HIDE its region and
    the looks it shows in (bit n for look n). The absent list: a count, then per block the level begins without its
    byte in the map of changed cells (2) and its bit there."""
    def word(v):
        return bytes([v >> 8 & 255, v & 255])

    rsize = 14
    body = bytearray()
    base = at + 5 + rsize * len(regions)
    recs = bytearray()
    stride = (W + 7) // 8       # the engine's map of changed cells
    for r, (x0, y0, x1, y1, keys, _, patterns) in enumerate(regions):
        nk = (len(keys) + 7) // 8
        keys_at = base + len(body)
        body += bytes([len(keys)])
        for x, y in keys:
            # The engine's map of changed cells (one bit per cell, stride bytes a line): a key reads PLATFORM if its grid
            # cell is a platform and not changed, or empty and changed.
            if rom[y][x] not in (EMPTY, PLATFORM):
                raise SystemExit(f"a key cell at {x}, {y} that is neither empty nor a platform")
            body += word(y * stride + x // 8) + bytes([1 << (x & 7), 1 if rom[y][x] == PLATFORM else 0])
        looks_at = base + len(body)
        body += bytes([len(patterns)])
        for bits, look in patterns:
            kb = bytearray(nk)
            for i, b in enumerate(bits):
                if b:
                    kb[i // 8] |= 0x80 >> (i % 8)
            body += kb + bytes([look])
        mine = sorted(a for a, (reg, _) in hide.items() if reg == r)
        list_at = base + len(body)
        if len(mine) > 255:
            raise SystemExit("a region with too many rects")
        body += bytes([len(mine)])
        for a in mine:
            body += word(a)
        recs += word(x0 * TILE // 2) + word(x1 * TILE // 2) + word(y0 * TILE) + word(y1 * TILE) + word(keys_at)             + word(looks_at) + word(list_at)
    vis_at = base + len(body)
    for i in range(rect_count):
        reg, mask = hide.get(rects_at + 8 * i, (0, 0))
        body += bytes([reg, mask])
    absent_at = base + len(body)
    gone = ABSENT.get(n, [])
    body += bytes([len(gone)])
    for x, y in gone:
        if rom[y][x] != PLATFORM_DESTRUCTIBLE:
            raise SystemExit(f"an absent block at {x}, {y} that is not a block in the grid")
        body += word(y * stride + x // 8) + bytes([1 << (x & 7)])
    return bytes(bytes([len(regions)]) + word(vis_at) + word(absent_at) + recs + body)
