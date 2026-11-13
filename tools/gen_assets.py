#!/usr/bin/env python3
"""Bakes the game's art and levels into ROM data for the Blaster board. Needs Pillow.

Writes to src/gen/:
  sprtable.bin  fixed ROM: one 8-byte entry per sprite id
  sprites.bin   bank 0: pixel data
  levelN.bin    banks 1-9: header, terrain grid, terrain rectangles with an x index, object list
  messages.bin  bank 10: strings as glyph indices
  assets.inc    equates shared with the assembly source

Sprite ids are the original sheet indices 0-347. Font 2 glyph g is id FONT2_BASE + g, font 1 is FONT1_BASE + g.

Sprite entry: src(2) w(1) h(1) ox(1) oy(1) spare(2). Source data is row-major, w bytes per row (2 pixels per
byte) and includes one trailing zero byte per row so that the blitter's shift (odd x) never carries a stray
nibble between rows. ox/oy are the pixel offset of the trimmed box inside the 12x12 cell; ox is even.
Palette index 0 is transparent. Opaque black pixels in the art use index PAL_BLACK.

Level header (big-endian words):
  +0 width +2 height +4 grid +6 rect_index +8 rects +10 objects +12 object_count +14 kill_total
  +16 man_x_cell +18 man_y_cell +20 man_heading (0 right, 1 left)
  +22 boss regions (0 if none) +24 far turret rows (see far_rows)
Grid: 4-bit cell types (the C port's EMPTY..GOAL), row-major, two cells per byte, high nibble first.
Rect: col(2) row(2) w(1) h(1) solid(1) ctrl(1), all byte-aligned; `ctrl` holds the blitter NO_EVEN/NO_ODD bits for
one-pixel-wide edges. Rects are sorted by column and may be long. rect_index has two words per RECT_BUCKET columns:
the offset of the first rect that reaches this bucket, and the offset of the first rect that starts in it.
Object: symbol(1) cell_x(2) cell_y(1), sorted by x.
"""
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))     # run as python -I too
import boss_terrain  # noqa: E402

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
WMS = os.path.dirname(HERE)
ROOT = os.path.dirname(WMS)
ASSETS = os.path.join(ROOT, "scripts", "_assets")
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(WMS, "src", "gen")

# Index 0 is transparent; the rest come from the game's eight named colors, then opaque black.
COLORS = {(255, 0, 0): 1, (255, 255, 0): 2, (0, 255, 0): 3, (0, 255, 255): 4, (0, 0, 255): 5, (255, 0, 255): 6,
          (255, 255, 255): 7, (0, 0, 0): 8,
          (255, 3, 3): 1}  # one stray pixel in the sheet
PAL_BLACK = 8
# Hardware palette, BBGGGRRR, for those indices.
PALETTE = [0x00, 0x07, 0x3F, 0x38, 0xF8, 0xC0, 0xC7, 0xFF, 0x00, 0, 0, 0, 0, 0, 0, 0]

SPRITE_COUNT = 348
FONT2_BASE = 348
FONT2_COUNT = 44
FONT1_BASE = 392
BLOCK_SPRITE = 131
PGL_SPRITE, PGL_ENGINE = 228, 132
TRAIL_SPRITES = (132, 133, 134)     # what trailed lasers draw: lz_trail_draw counts on them being in a row
SPRFIX_ORG, SPRFIX_SIZE = 0x8800, 0x800
# A second room in fixed ROM, ending where the vectors start: main.asm puts gen/sprfix2.bin there.
SPRFIX2_END, SPRFIX2_MAX = 0xFFF0, 160
# Sheet cells the port never draws: the color swatches the original's ColoredSprite painted from (the port fills with
# draw_color), and the phase 2 worm's parts, which are baked into WORM_* images instead.
UNDRAWN = set(range(240, 248)) | set(range(288, 293))
WORM_BASE = 288
BLOCK_COLS, BLOCK_LINES = 6, 12
BLOCK_WIDE, BLOCK_TALL = 6, 6   # the largest group of blocks one image can draw, in blocks
BLOCK_PAGES = BLOCK_WIDE * BLOCK_COLS
BLOCK_BASE_PAGE = 64 - BLOCK_PAGES
RECT_IMAGE = 0x01         # a rect's control byte: this rect is a block's image
RECT_HIDE = 0x04          # a rect's control byte: this rect lies in a region of terrain the boss changes, and the hide
                          # table says when it shows (boss_terrain.py). It is BC_SLOW to the blitter, which only makes
                          # these few short lines a little slower to draw.
LINE_SOLID = 0x22         # the color of the lines that scroll fast
VIEW_COLS = 146
EP_SPRITE = 53
EP_CORE_COLORS = (1, 7)     # red, white
FONT1_COUNT = 50
TABLE_ENTRIES = FONT1_BASE + FONT1_COUNT
ENTRY_SIZE = 8
RECT_BUCKET = 16      # columns per index bucket; one column is 2 pixels

SYM_PLATFORM, SYM_FLOATY, SYM_LAVA, SYM_GOAL, SYM_LAVA2 = 1, 2, 3, 4, 9
SYM_DESTRUCTIBLE, SYM_BURIED, SYM_EXPLODE_ONCE, SYM_EXPLODE_RESPAWN = 5, 6, 10, 11
SYM_MAN_RIGHT, SYM_MAN_LEFT = 20, 21
EMPTY, PLATFORM, PLATFORM_DESTRUCTIBLE, FLOATY, LAVA, LAVA2, EXPLODING, GOAL, BURIED_BLOCK = 0, 1, 2, 3, 4, 5, 6, 7, 8


def palette_index(rgba):
    r, g, b, a = rgba
    if a < 128:
        return 0
    if (r, g, b) not in COLORS:
        raise SystemExit(f"color {rgba} is not in the palette")
    return COLORS[(r, g, b)]


def cell_pixels(im, ox, oy, w, h):
    px = im.load()
    W, H = im.size
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            sx, sy = ox + x, oy + y
            row.append(palette_index(px[sx, sy]) if sx < W and sy < H else 0)
        rows.append(row)
    return rows


def pack_sprite(rows):
    """Trim to the bounding box. Returns (bytes, w_bytes, h, ox, oy), or None for a blank cell."""
    lit = [(x, y) for y, r in enumerate(rows) for x, v in enumerate(r) if v]
    if not lit:
        return None
    x0 = min(p[0] for p in lit) & ~1
    x1 = max(p[0] for p in lit)
    y0 = min(p[1] for p in lit)
    y1 = max(p[1] for p in lit)
    w_bytes = (x1 - x0) // 2 + 1 + 1  # one trailing zero byte for the shifter
    out = bytearray()
    for y in range(y0, y1 + 1):
        row = rows[y]
        for b in range(w_bytes):
            hi = row[x0 + b * 2] if x0 + b * 2 < len(row) else 0
            lo = row[x0 + b * 2 + 1] if x0 + b * 2 + 1 < len(row) else 0
            out.append(hi << 4 | lo)
    return bytes(out), w_bytes, y1 - y0 + 1, x0, y0


def worm_segment_shape(phase):
    """Width and stretch of a worm segment at one of the 90 steps of the 3-second wave (Wizard_p2_3.GetSegmentPosition)."""
    t = phase / 90 * 4 - 2
    t = min(1, max(0, abs(t) - 0.25))
    return int(6 + 3 * (1 - t)), int(4 * t)


# Per width, the stretch of its tallest segment; and other whole segments worth an image of their own.
WORM_TALL = {6: 4, 7: 2, 8: 1, 9: 0}
WORM_WHOLE = []


def worm_pieces(cells):
    """The phase 2 worm as images that draw exactly what Wizard_p2_3.DrawSegment and DrawMouth draw, in one color.
    S<w>: a segment of width w at its tallest. A shorter segment of that width is its first h-9 lines, then its last 9
    lines 9 further down. S<w><v>: a whole segment where one image is worth it. HT, HB: the head's top and bottom 9
    lines. HC: its middle, 18 lines from h/2-9: the spine, sprite 292 and the two 4x4 squares."""
    def canvas(w, h):
        return [[0] * w for _ in range(h)]

    def spr(c, n, x, y):
        for j, r in enumerate(cells[WORM_BASE + n]):
            for i, v in enumerate(r):
                if v and 0 <= y + j < len(c) and 0 <= x + i < len(c[0]):
                    c[y + j][x + i] = 1

    def rect(c, x, y, w, h):
        for j in range(y, y + h):
            for i in range(x, x + w):
                if 0 <= j < len(c) and 0 <= i < len(c[0]):
                    c[j][i] = 1

    def segment(w, v):
        h = 28 + 2 * v
        c = canvas(w, h)
        spr(c, 2, 0, 0); spr(c, 2, w - 6, 0); rect(c, 0, 9, w, h - 18)
        spr(c, 3, 0, h - 12); spr(c, 3, w - 6, h - 12)
        return c

    out = {f"S{w}": segment(w, v) for w, v in WORM_TALL.items()}
    for w, v in WORM_WHOLE:
        out[f"S{w}{v}"] = segment(w, v)
    c = canvas(18, 9)
    spr(c, 2, 0, 0); spr(c, 0, 6, 0); rect(c, 5, 1, 1, 1)
    out["HT"] = c
    c = canvas(18, 9)
    spr(c, 3, 0, -3); spr(c, 1, 6, -3); rect(c, 5, 7, 1, 1)
    out["HB"] = c
    c = canvas(8, 18)
    rect(c, 0, 0, 2, 18); spr(c, 4, 1, 3); rect(c, 2, 0, 4, 4); rect(c, 2, 14, 4, 4)
    out["HC"] = c
    return out


def build_sprites(plan_from=None):
    sheet = Image.open(os.path.join(ASSETS, "34_Draw_sprites_sprite.png")).convert("RGBA")
    font2 = Image.open(os.path.join(ASSETS, "35_Draw_font2_sprite.png")).convert("RGBA")
    font1 = Image.open(os.path.join(ASSETS, "33_Draw_font1_sprite.png")).convert("RGBA")
    cells = []
    for i in range(SPRITE_COUNT):
        cells.append(cell_pixels(sheet, i % 12 * 12, i // 12 * 12, 12, 12))
    worm = worm_pieces(cells)
    for i in UNDRAWN:
        cells[i] = [[0] * 12 for _ in range(12)]
    for g in range(FONT2_COUNT):
        cells.append(cell_pixels(font2, g * 5, 0, 5, 6))
    for g in range(FONT1_COUNT):
        cells.append(cell_pixels(font1, g * 4, 0, 4, 6))
    # An exploding platform at rest, with its core in place: one image rather than a sprite and a rectangle.
    for color in EP_CORE_COLORS:
        rows = [list(r) for r in cells[EP_SPRITE]]
        for y in range(2, 10):
            for x in range(2, 10):
                rows[y][x] = color
        cells.append(rows)

    table = bytearray()
    bank = Bank0(sheet)
    if plan_from is not None:
        bank.make_plan(plan_from)
    seen = {}
    worm_at = {}
    # The worm's images, before the small ones fill the gaps they need. Not in the table: wizard.asm writes their display
    # list entries itself.
    for name, rows in worm.items():
        packed, w, h, ox, oy = pack_sprite(rows)
        assert ox == 0 and oy == 0, name
        if max(x for r in rows for x, v in enumerate(r) if v) % 2 == 0:
            # An odd number of pixels: the last byte's low pixel is empty, so a shifted blit loses nothing without
            # the spare byte, and carries nothing into the next line.
            packed = b"".join(packed[y * w:y * w + w - 1] for y in range(h))
            w -= 1
        worm_at[name] = (bank.put(packed), w, h)
    for rows in cells:
        packed = pack_sprite(rows)
        if packed is None:
            table += bytes(ENTRY_SIZE)
            continue
        pixels, w, h, ox, oy = packed
        if pixels in seen:
            addr = seen[pixels]
        else:
            addr = bank.put(pixels)
            seen[pixels] = addr
        table += bytes([addr >> 8, addr & 255, w, h, ox, oy, 0, 0])
    tables = dict(BLOCK_PAGE=BLOCK_BASE_PAGE, TAB_FLAT=bank.flat)
    for name, (addr, w, h) in worm_at.items():
        tables[f"WORM_{name}"] = addr
        tables[f"WORM_{name}_W"] = w
        tables[f"WORM_{name}_H"] = h
    # Each piglet with its flame behind it, in every position the flame has. Most of the flame is hidden, and a piglet is one
    # sprite rather than two.
    tables["PGL_COMP"] = len(table) // ENTRY_SIZE
    for rows in piglet_composites(cells):
        packed, w, h, ox, oy = pack_sprite(rows)
        if packed in seen:
            addr = seen[packed]
        else:
            addr = bank.put(packed)
            seen[packed] = addr
        table += bytes([addr >> 8, addr & 255, w, h, ox, oy, 0, 0])
    # A trailed laser's three copies, one step apart along its heading, as one image. Only so many shapes come of rounding the steps.
    # On a canvas starting 3 pixels up and left of the laser's cell, since an image's trim cannot be negative.
    shapes = trail_shapes()
    tables["TRAIL_COMP"] = len(table) // ENTRY_SIZE
    tables["TRAIL_N"] = len(shapes)
    for spr in TRAIL_SPRITES:
        for s1x, s1y, s2x, s2y in shapes:
            can = [[0] * 18 for _ in range(18)]
            for dx, dy in ((0, 0), (s1x, s1y), (s2x, s2y)):
                for y, r in enumerate(cells[spr]):
                    for x, v in enumerate(r):
                        if v:
                            can[y + 3 + dy][x + 3 + dx] = v
            packed, w, h, ox, oy = pack_sprite(can)
            if packed in seen:
                addr = seen[packed]
            else:
                addr = bank.put(packed)
                seen[packed] = addr
            table += bytes([addr >> 8, addr & 255, w, h, ox, oy, 0, 0])
    with open(os.path.join(OUT, "trailshapes.bin"), "wb") as f:
        for sh in shapes:
            f.write(bytes(v & 255 for v in sh))
    with open(os.path.join(OUT, "sprfix.bin"), "wb") as f:
        f.write(bytes(bank.fixed))
    with open(os.path.join(OUT, "sprfix2.bin"), "wb") as f:
        f.write(bytes(bank.fixed2))
    tables["SPRFIX2_ORG"] = bank.fixed2_org
    global SPACE
    SPACE = bytearray(0x10000)
    SPACE[SPRFIX_ORG:SPRFIX_ORG + len(bank.fixed)] = bank.fixed
    SPACE[bank.fixed2_org:SPRFIX2_END] = bank.fixed2
    if plan_from is None:
        # A first pass only finds what is to be stored: now store it, packed tightly.
        return build_sprites(bank.wanted)
    data = bank.finish()
    SPACE[0:len(data)] = data
    with open(os.path.join(OUT, "tabalt.bin"), "wb") as f:
        # Color and black in turn: from here for a line moving left, from one on for a line moving right.
        f.write(bytes([LINE_SOLID, 0]) * 129)
    return bytes(table), bytes(data), sheet, tables


def trail_shapes():
    """Every set of steps a laser's heading can give, by lz_trail_off's rounding, for a heading whose length is within lz_aim's error."""
    def off(c, t):
        v = (c * abs(t) + 64) >> 7
        return v if t >= 0 else -v
    shapes = set()
    for tx in range(-160, 161):
        for ty in range(-160, 161):
            if 0.95 <= (tx * tx + ty * ty) ** 0.5 / 128 <= 1.05:
                shapes.add((off(1, tx), off(1, ty), off(2, tx), off(2, ty)))
    return sorted(shapes)


def piglet_composites(cells):
    """By k = direction + 4 * animation + 8 * segment, then flame offset 2, 3, 4. On a canvas starting 4 pixels up and left of the
    piglet's cell, since an image's trim cannot be negative. The flame is behind the body, and away from the heading."""
    heading = ((1, 0), (0, -1), (-1, 0), (0, 1))
    out = []
    for seg in (0, 24):
        for anim in (0, 4):
            for d in range(4):
                body = cells[PGL_SPRITE + d + seg + anim]
                for f in (2, 3, 4):
                    can = [[0] * 20 for _ in range(20)]
                    dx, dy = -heading[d][0] * f, -heading[d][1] * f
                    for y, r in enumerate(cells[PGL_ENGINE]):
                        for x, v in enumerate(r):
                            if v:
                                can[y + 4 + dy][x + 4 + dx] = v
                    for y, r in enumerate(body):
                        for x, v in enumerate(r):
                            if v:
                                can[y + 4][x + 4] = v
                    out.append(can)
    return out


class Bank0:
    """What the blitter reads in bank 0. A group of blocks is drawn from one image, with one 256-byte page per column, so the
    blitter can start it at any column and line. Those pages hold only the first few bytes of each: everything else in the bank
    is packed around them. Blocks repeat every 6 columns and 12 lines. Groups a column of blocks wide can be tall, the rest are one
    block high. A sprite must not cross the image, so it cannot cross a page up there, and a table that must stay in a page starts one."""

    def __init__(self, sheet):
        self.data = bytearray(0x4000)
        self.fixed = bytearray()
        self.used = 0
        self.free = [(0, BLOCK_BASE_PAGE << 8)]
        self.plan = None
        self.wanted = []
        self.fixed2 = bytearray()
        self.fixed2_org = SPRFIX2_END
        px = sheet.load()
        sx, sy = BLOCK_SPRITE % 12 * 12, BLOCK_SPRITE // 12 * 12
        for page in range(BLOCK_PAGES):
            col = page % BLOCK_COLS
            lines = BLOCK_LINES * BLOCK_TALL if page < BLOCK_COLS else BLOCK_LINES
            for line in range(lines):
                a, b = (palette_index(px[sx + col * 2 + i, sy + line % BLOCK_LINES]) for i in (0, 1))
                a, b = (0 if v == PAL_BLACK else v for v in (a, b))
                self.data[((BLOCK_BASE_PAGE + page) << 8) + line] = a << 4 | b
            self.free.append((((BLOCK_BASE_PAGE + page) << 8) + lines, (BLOCK_BASE_PAGE + page + 1) << 8))
        # A row of color between two blacks, for floors.
        row = bytes([0]) + bytes([LINE_SOLID]) * VIEW_COLS + bytes([0])
        i = next(k for k in range(1, len(self.free)) if self.free[k][1] - self.free[k][0] >= len(row))
        self.flat = self.free[i][0]
        self.data[self.flat:self.flat + len(row)] = row
        self.free[i] = (self.flat + len(row), self.free[i][1])

    def put(self, pixels):
        if self.plan is not None:
            addr = self.plan[pixels]
            if addr >= self.fixed2_org:
                o = addr - self.fixed2_org
                self.fixed2[o:o + len(pixels)] = pixels
            elif addr >= SPRFIX_ORG:
                o = addr - SPRFIX_ORG
                self.fixed[len(self.fixed):o + len(pixels)] = bytes(max(0, o + len(pixels) - len(self.fixed)))
                self.fixed[o:o + len(pixels)] = pixels
            else:
                self.data[addr:addr + len(pixels)] = pixels
            return addr
        self.wanted.append(pixels)
        for i, (lo, hi) in enumerate(self.free):
            if hi - lo >= len(pixels):
                self.data[lo:lo + len(pixels)] = pixels
                self.free[i] = (lo + len(pixels), hi)
                return lo
        # Fixed ROM can be read by the blitter too, whatever the bank.
        addr = SPRFIX_ORG + len(self.fixed)
        self.fixed += pixels
        return addr

    def make_plan(self, wanted):
        """Largest first, each into the smallest room it fits: the gaps between the block pages are many and small."""
        self.plan = {}
        free = list(self.free) + [(SPRFIX2_END - SPRFIX2_MAX, SPRFIX2_END)]
        fixed = 0
        for px in sorted(set(wanted), key=lambda p: (-len(p), p)):  # not set order, which changes from run to run
            fits = [i for i, (lo, hi) in enumerate(free) if hi - lo >= len(px)]
            if fits:
                i = min(fits, key=lambda k: free[k][1] - free[k][0])
                lo, hi = free[i]
                self.plan[px] = lo
                free[i] = (lo + len(px), hi)
            else:
                self.plan[px] = SPRFIX_ORG + fixed
                fixed += len(px)
        if fixed > SPRFIX_SIZE:
            raise SystemExit(f"no room for sprites: {fixed} bytes in fixed ROM")
        self.planned_free = sum(hi - lo for lo, hi in free[:-1])
        used2 = [a for a in self.plan.values() if a >= SPRFIX2_END - SPRFIX2_MAX]
        self.fixed2_org = min(used2) if used2 else SPRFIX2_END
        self.fixed2 = bytearray(SPRFIX2_END - self.fixed2_org)

    def finish(self):
        free = self.planned_free if self.plan is not None else sum(hi - lo for lo, hi in self.free)
        print("bank 0 free:", free, " in fixed ROM:", len(self.fixed), "+", len(self.fixed2) if self.plan is not None else 0)
        return bytes(self.data)


def block_groups(blocks):
    """Rectangles of blocks: first long rows, then columns of what is left, then whatever remains."""
    left = set(blocks)
    out = []

    def take(x, y, w, h):
        for i in range(w):
            for j in range(h):
                left.discard((x + i, y + j))
        out.append((x, y, w, h))

    def rows(least):
        for x, y in sorted(left, key=lambda c: (c[1], c[0])):
            if (x, y) not in left or (x - 1, y) in left:
                continue
            n = 0
            while (x + n, y) in left and n < BLOCK_WIDE:
                n += 1
            if n >= least:
                take(x, y, n, 1)

    rows(3)
    for x, y in sorted(left):
        if (x, y) not in left or (x, y - 1) in left:
            continue
        n = 0
        while (x, y + n) in left and n < BLOCK_TALL:
            n += 1
        if n >= 2:
            take(x, y, 1, n)
    rows(2)
    rows(1)
    return out


def corner_id(cells, W, H, x, y, dx, dy, base):
    """Tile.GetCorner: which half-tile art a corner of a platform uses."""
    def at(cx, cy):
        return cells[cy][cx] if 0 <= cx < W and 0 <= cy < H else PLATFORM
    self_ = cells[y][x]
    side = at(x + dx, y) == self_
    vert = at(x, y + dy) == self_
    diag = at(x + dx, y + dy) == self_
    if not side and not vert:
        kind = 0
    elif side and vert and not diag:
        kind = 1
    elif side and not vert:
        kind = 2
    elif not side and vert:
        kind = 3
    else:
        kind = 4
    return base + 2 * kind


def render_terrain(cells, W, H, sheet):
    """Render static terrain as the game's draw_tiles does. Returns {(x, y): palette index}."""
    px = sheet.load()
    canvas = {}

    def stamp(sx, sy, w, h, dx, dy):
        for j in range(h):
            for i in range(w):
                v = palette_index(px[sx + i, sy + j])
                if v:
                    canvas[(dx + i, dy + j)] = v

    for y in range(H):
        for x in range(W):
            c = cells[y][x]
            X, Y = x * 12, y * 12
            if c == PLATFORM:
                for dx, dy, base, ox, oy in ((1, -1, 203, 6, 0), (-1, -1, 202, 0, 0), (-1, 1, 226, 0, 6), (1, 1, 227, 6, 6)):
                    cid = corner_id(cells, W, H, x, y, dx, dy, base)
                    stamp((cid % 24) * 6, (cid // 24) * 6, 6, 6, X + ox, Y + oy)
            elif c == FLOATY:
                stamp(58 % 12 * 12, 58 // 12 * 12, 12, 12, X, Y)
            elif c == LAVA:
                stamp(120 % 12 * 12, 120 // 12 * 12, 12, 12, X, Y)
            elif c == LAVA2:
                stamp(144 % 12 * 12, 144 // 12 * 12, 12, 12, X, Y)
    return canvas


def vectorize(canvas):
    """Cover the lit pixels with solid byte-aligned rectangles. Opaque black needs no drawing: the
    background is black. Returns rects as (col, row, w_bytes, h, solid, ctrl), plus a check image."""
    pixels = {p: v for p, v in canvas.items() if v != PAL_BLACK}
    # Work in byte columns: each column holds a left and a right pixel.
    columns = {}
    for (x, y), v in pixels.items():
        columns[(x >> 1, y)] = columns.get((x >> 1, y), [0, 0])
        columns[(x >> 1, y)][x & 1] = v
    cells = {k: (v[0] << 4 | v[1]) for k, v in columns.items()}
    rects = []
    done = set()
    for (col, row) in sorted(cells, key=lambda k: (k[1], k[0])):
        if (col, row) in done:
            continue
        value = cells[(col, row)]
        # Option A: grow right, then down. Option B: grow down, then right. Keep the larger.
        def grow(first_horizontal):
            w, h = 1, 1
            if first_horizontal:
                while w < 255 and cells.get((col + w, row)) == value and (col + w, row) not in done:
                    w += 1
                while h < 255 and all(cells.get((col + i, row + h)) == value and (col + i, row + h) not in done for i in range(w)):
                    h += 1
            else:
                while h < 255 and cells.get((col, row + h)) == value and (col, row + h) not in done:
                    h += 1
                while w < 255 and all(cells.get((col + w, row + j)) == value and (col + w, row + j) not in done for j in range(h)):
                    w += 1
            return w, h
        wa, ha = grow(True)
        wb, hb = grow(False)
        w, h = (wa, ha) if wa * ha >= wb * hb else (wb, hb)
        for i in range(w):
            for j in range(h):
                done.add((col + i, row + j))
        hi, lo = value >> 4, value & 15
        ctrl = 0
        if hi == 0:
            ctrl = 0x80  # NO_EVEN: leave the left pixel alone
        elif lo == 0:
            ctrl = 0x40  # NO_ODD: leave the right pixel alone
        rects.append((col, row, w, h, value, ctrl))
    return rects, pixels


def check_rects(rects, pixels):
    """Rebuild the terrain from the rectangles and compare it with the original pixels."""
    got = {}
    for col, row, w, h, solid, ctrl in rects:
        for i in range(w):
            for j in range(h):
                if not ctrl & 0x80:
                    got[(col + i) * 2, row + j] = solid >> 4
                if not ctrl & 0x40:
                    got[(col + i) * 2 + 1, row + j] = solid & 15
    got = {k: v for k, v in got.items() if v}
    if got != pixels:
        raise SystemExit("terrain rectangles do not reproduce the terrain")


def cut_opened(rects, regions):
    """Cuts each rect at the edges of the cells in regions (x, y, w, h), and marks the pieces inside one RECT_HIDE."""
    for x, y, w, h in regions:
        c0, c1, r0, r1 = x * BLOCK_COLS, (x + w) * BLOCK_COLS, y * BLOCK_LINES, (y + h) * BLOCK_LINES
        out = []
        for col, row, rw, rh, solid, ctrl in rects:
            if not (col < c1 and c0 < col + rw and row < r1 and r0 < row + rh):
                out.append((col, row, rw, rh, solid, ctrl))
                continue
            cs = [col] + [c for c in (c0, c1) if col < c < col + rw] + [col + rw]
            rs = [row] + [r for r in (r0, r1) if row < r < row + rh] + [row + rh]
            for a, b in zip(cs, cs[1:]):
                for t, u in zip(rs, rs[1:]):
                    inside = c0 <= a and b <= c1 and r0 <= t and u <= r1
                    out.append((a, t, b - a, u - t, solid, ctrl | (RECT_HIDE if inside else 0)))
        rects = out
    return rects


PIGLET_HEADS = {51: 0, 52: 1, 53: 2, 54: 3, 63: 0, 64: 1, 65: 2, 66: 3}   # symbol: heading, 0 east, 1 north, 2 west, 3 south


def piglet_routes(cells, W, H, objects):
    """Piglet.as: each piglet is made when the level loads and steps a cell every 250 ms, by GetNewDestination (ahead,
    right, left, back, into an EMPTY or FLOATY_PLATFORM cell). On the level's own grid that is a loop. Returns
    (object index, the loop's moves) for each piglet: the heading of each step from its constructor's on, 0 east,
    1 north, 2 west, 3 south. The engine puts a piglet it makes or wakes where the original's would be by now."""
    dxs, dys = (1, 0, -1, 0), (0, -1, 0, 1)

    def clear(x, y):
        return (cells[y][x] if 0 <= x < W and 0 <= y < H else PLATFORM) in (EMPTY, FLOATY)

    routes = []
    for i, (s, x, y) in enumerate(objects):
        if s not in PIGLET_HEADS:
            continue
        heading, seen, moves = PIGLET_HEADS[s], {}, []
        while True:
            for turn in (0, -1, 2, 1):
                heading = (heading + turn) % 4
                if clear(x + dxs[heading], y + dys[heading]):
                    break
            else:
                raise SystemExit(f"a piglet at {x}, {y} cannot move")
            x, y = x + dxs[heading], y + dys[heading]
            if (x, y, heading) in seen:
                break
            seen[(x, y, heading)] = len(moves)
            moves.append(heading)
        if seen[(x, y, heading)] != 0 or not 0 < len(moves) < 256:
            raise SystemExit(f"piglet {i}: its route does not loop from its first step")
        routes.append((i, moves))
    return routes


def thin_objects(n, objects):
    """Leaves out what src/level_cuts.txt lists: the original levels stay as they are, and the cuts stay reviewable."""
    cuts = set()
    with open(os.path.join(WMS, "src", "level_cuts.txt")) as f:
        for line in f:
            line = line.split("#")[0].split()
            if line and int(line[0]) == n:
                cuts.add(tuple(int(v) for v in line[1:4]))
    missing = cuts - set(objects)
    if missing:
        raise SystemExit(f"level {n}: cuts match no object: {sorted(missing)}")
    return [o for o in objects if o not in cuts]


TERRAIN_SYMS = {1, 2, 3, 4, 5, 6, 9, 10, 11}    # symbols whose cell is not EMPTY when the level is made


def sideways_turrets(rows, objects):
    """Alien turrets that add to Main.killCount: BoltTurret.as and GroupedBurstTurret.as count themselves only when
    they face sideways (a PLATFORM cell left or right of them), though shooting any of them is a kill.
    GroupedTurretController.as lines turrets up from its cell while the wall behind goes on and the cell is EMPTY."""
    H, W = len(rows), len(rows[0])

    def platform(x, y):
        return 0 <= x < W and 0 <= y < H and rows[y][x] == SYM_PLATFORM

    def empty(x, y):
        return 0 <= x < W and 0 <= y < H and rows[y][x] not in TERRAIN_SYMS

    count = 0
    for s, x, y in objects:
        if s not in (56, 57, 58, 59):
            continue
        hx = 1 if platform(x - 1, y) else -1 if platform(x + 1, y) else 0
        if not hx:
            continue
        if s != 56:
            count += 1
            continue
        k = 0
        while platform(x - hx, y + k) and empty(x, y + k):
            count += 1
            k += 1
    return count


FAR_NEAR_X = 156     # pools.asm's SPAWN_NEAR_X
FAR_REACH = 254      # entities.asm's prefill places shots up to GTC_AGE_MAX ticks old: 254 px


def far_rows(cells, W, H, objects):
    """GroupedTurretController rows that fire sideways (a PLATFORM left or right of the first cell, as nt_heading
    finds it), as (object index, lowest camera x, highest camera x). The range covers the row and its shots' path
    to the first PLATFORM or block, up to FAR_REACH, with the spawner's margin either side."""
    def cell(x, y):
        return cells[y][x] if 0 <= x < W and 0 <= y < H else PLATFORM

    out = []
    for i, (s, x, y) in enumerate(objects):
        if s != 56:
            continue
        hx = 1 if cell(x - 1, y) == PLATFORM else -1 if cell(x + 1, y) == PLATFORM else 0
        if not hx:
            continue
        reach, k = 0, 0
        while cell(x - hx, y + k) == PLATFORM and cell(x, y + k) == EMPTY:
            c = x + hx
            while cell(c, y + k) not in (PLATFORM, PLATFORM_DESTRUCTIBLE) and abs(c - x) * 12 < FAR_REACH + 12:
                c += hx
            reach = max(reach, min(FAR_REACH, (abs(c - x) - 1) * 12))
            k += 1
        if reach < 24:
            continue
        lo, hi = (x * 12, x * 12 + 12 + reach) if hx > 0 else (x * 12 - reach, x * 12 + 12)
        out.append((i, max(0, lo - FAR_NEAR_X), hi + FAR_NEAR_X))
    return out


def build_level(n, sheet, stats):
    # wms/levels holds levels laid out again for this hardware. See tools/relayout.py.
    laid_out = os.path.join(WMS, "levels", f"{n}.xml")
    path = laid_out if os.path.exists(laid_out) else os.path.join(DATA, f"{n}.xml")
    rows = [[int((c.text or "0").strip() or 0) - 1 for c in r.findall("tilecol")]
            for r in ET.parse(path).getroot().findall("tilerow")]
    W, H = len(rows[0]), len(rows)
    cells = [[EMPTY] * W for _ in range(H)]
    objects = []
    man = None
    for y in range(H):
        for x in range(W):
            s = rows[y][x]
            if s == SYM_PLATFORM:
                cells[y][x] = PLATFORM
            elif s == SYM_FLOATY:
                cells[y][x] = FLOATY
            elif s in (SYM_LAVA, SYM_LAVA2):
                cells[y][x] = LAVA
            elif s == SYM_GOAL:
                cells[y][x] = GOAL
            if s in (SYM_MAN_RIGHT, SYM_MAN_LEFT):
                # The last one wins, as Main.AddMan keeps the last made: level 3 has a second marker left in it.
                man = (x, y, 0 if s == SYM_MAN_RIGHT else 1)
            elif s > 0 and s not in (SYM_PLATFORM, SYM_FLOATY, SYM_LAVA, SYM_LAVA2):
                objects.append((s, x, y))
    if man is None:
        raise SystemExit(f"level {n} has no man")
    objects = thin_objects(n, objects)
    # Blocks the boss makes later are blocks in the grid from the start, which Level_Load marks gone: see boss_terrain.
    for x, y in boss_terrain.ABSENT.get(n, []):
        if cells[y][x] != EMPTY or any(o[1:] == (x, y) for o in objects):
            raise SystemExit(f"level {n}: an absent block at {x}, {y} on something else")
        objects.append((SYM_DESTRUCTIBLE, x, y))
    blocks = [(x, y) for s, x, y in objects if s in (SYM_DESTRUCTIBLE, SYM_BURIED)]
    canvas = render_terrain(cells, W, H, sheet)
    rects, pixels = vectorize(canvas)
    # The terrain the boss changes (tools/boss_terrain.py): its regions' own terrain is cut at their edges and marked
    # RECT_HIDE, and each other look of a region is terrain rects of its own, marked the same. The hide table says, for
    # each such rect, its region and the looks it shows in.
    rom = [row[:] for row in cells]
    for s, x, y in objects:
        if s in (SYM_DESTRUCTIBLE, SYM_BURIED):
            rom[y][x] = PLATFORM_DESTRUCTIBLE
        elif s in (SYM_EXPLODE_ONCE, SYM_EXPLODE_RESPAWN):
            rom[y][x] = EXPLODING
    regions = boss_terrain.build(n, rom, W, H, {p for p, v in canvas.items() if v == 2})
    rects = cut_opened(rects, [(r[0], r[1], r[2] - r[0], r[3] - r[1]) for r in regions])
    check_rects(rects, pixels)

    def region_of(col, row, w, h):
        for i, (x0, y0, x1, y1) in enumerate(r[:4] for r in regions):
            if x0 * BLOCK_COLS <= col and col + w <= x1 * BLOCK_COLS and y0 * BLOCK_LINES <= row and row + h <= y1 * BLOCK_LINES:
                return i
        raise SystemExit(f"level {n}: a hidden rect at {col}, {row} is in no region")
    hide = {r: (region_of(*r[:4]), 1) for r in rects if r[5] & RECT_HIDE}
    for i, region in enumerate(regions):
        for k, items in enumerate(region[5][1:], 1):
            look = {}
            for x, y, w, h, sol in items:
                if sol == boss_terrain.SPRITE_ITEM:
                    px = sheet.load()
                    sid = boss_terrain.FLOATY_SPRITE
                    for j in range(12):
                        for q in range(12):
                            v = palette_index(px[sid % 12 * 12 + q, sid // 12 * 12 + j])
                            if v:
                                look[(x + q, y + j)] = v
                    continue
                for j in range(y, y + h):
                    for q in range(x, x + w):
                        look[(q, j)] = 2
            look_rects, look_pixels = vectorize(look)
            check_rects(look_rects, look_pixels)
            for col, row, w, h, sol, ctrl in look_rects:
                key = (col, row, w, h, sol, ctrl | RECT_HIDE)
                if region_of(col, row, w, h) != i:
                    raise SystemExit(f"level {n}: a look of region {i} reaches out of it")
                hide[key] = (i, hide.get(key, (i, 0))[1] | 1 << k)
    rects += [r for r in hide if not r in set(rects)]
    # Destructible blocks are terrain until a laser hits one. Groups of them are one image, not the 16 rectangles an outline makes.
    groups = block_groups(blocks)
    rects += [(x * BLOCK_COLS, y * BLOCK_LINES, w * BLOCK_COLS, h * BLOCK_LINES, 0, RECT_IMAGE) for x, y, w, h in groups]
    rects.sort(key=lambda r: (r[0], r[1]))

    # Destructible and exploding cells are written into the ROM grid; their objects own them at run time.
    for s, x, y in objects:
        if s == SYM_DESTRUCTIBLE:
            cells[y][x] = PLATFORM_DESTRUCTIBLE
        elif s == SYM_BURIED:
            cells[y][x] = BURIED_BLOCK
        elif s in (SYM_EXPLODE_ONCE, SYM_EXPLODE_RESPAWN):
            cells[y][x] = EXPLODING
    # Blocks are not objects: the engine makes an entity only when one is hit.
    objects = [o for o in objects if o[0] not in (SYM_DESTRUCTIBLE, SYM_BURIED)]
    objects.sort(key=lambda o: (o[1], o[2]))

    grid = bytearray()
    for row in cells:
        for x in range(0, W, 2):
            hi = row[x]
            lo = row[x + 1] if x + 1 < W else 0
            grid.append(hi << 4 | lo)
    buckets = (W * 12 // 2) // RECT_BUCKET + 2
    rect_blob = bytearray()
    for col, row, w, h, solid, ctrl in rects:
        rect_blob += bytes([col >> 8, col & 255, row >> 8, row & 255, w, h, solid, ctrl])
    table = []
    for b in range(buckets + 1):
        low = b * RECT_BUCKET
        reach = next((i for i, r in enumerate(rects) if r[0] + r[2] > low), len(rects))
        start = next((i for i, r in enumerate(rects) if r[0] >= low), len(rects))
        table += [reach * 8, start * 8]
    obj_blob = bytearray()
    for s, x, y in objects:
        obj_blob += bytes([s, x >> 8, x & 255, y])
    # After the objects: the piglets' routes. A count, then for each its object index (2), the loop's length, the
    # address of its moves (2), and then the moves, four to a byte from the top bits down.
    routes = piglet_routes(cells, W, H, objects)

    header_size = 26
    grid_at = header_size
    index_at = grid_at + len(grid)
    rects_at = index_at + len(table) * 2
    objects_at = rects_at + len(rect_blob)
    # What Main.killCount ends up as: every enemy and alien turret the level can produce.
    kill_value = {12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 61: 1, 27: 1,
                  36: 1, 37: 6, 38: 5, 39: 1, 40: 1, 41: 1, 42: 1, 60: 3}
    kill_total = sum(kill_value.get(o[0], 0) for o in objects) + sideways_turrets(rows, objects)
    regions_at = 0               # filled in below
    head = [W, H, grid_at, index_at, rects_at, objects_at, len(objects), kill_total, man[0], man[1], man[2], regions_at,
            0]
    blob = bytearray()
    for v in head:
        blob += bytes([v >> 8, v & 255])
    blob += grid
    for v in table:
        blob += bytes([v >> 8, v & 255])
    blob += rect_blob
    blob += obj_blob
    blob.append(len(routes))
    moves_at = len(blob) + 5 * len(routes)
    packed = bytearray()
    for i, moves in routes:
        blob += bytes([i >> 8, i & 255, len(moves), (moves_at + len(packed)) >> 8, (moves_at + len(packed)) & 255])
        for k in range(0, len(moves), 4):
            four = moves[k:k + 4] + [0] * (4 - len(moves[k:k + 4]))
            packed.append(four[0] << 6 | four[1] << 4 | four[2] << 2 | four[3])
    blob += packed
    # After the routes: the turret rows that fire sideways, found through the header's word at +24. For each its object
    # index (2) and the lowest and highest camera x (2 each) at which it should exist: anywhere its shots can be seen,
    # not only near the row (far_rows.asm). $FFFF ends the list.
    far = far_rows(cells, W, H, objects)
    far_at = len(blob)
    blob[24:26] = bytes([far_at >> 8, far_at & 255])
    for v in far:
        blob += bytes([v[0] >> 8, v[0] & 255, v[1] >> 8, v[1] & 255, v[2] >> 8, v[2] & 255])
    blob += bytes([0xFF, 0xFF])
    if regions:
        # After the routes: the boss's regions (boss_terrain.table), found through the header's last word.
        at = {r: rects_at + 8 * i for i, r in enumerate(rects)}
        regions_at = len(blob)
        blob[22:24] = bytes([regions_at >> 8, regions_at & 255])
        blob += boss_terrain.table(n, regions, regions_at, len(rects), rects_at, {at[r]: v for r, v in hide.items()},
                                     rom, W)
    if len(blob) > 0x4000:
        raise SystemExit(f"level {n} overflows its bank: {len(blob)}")
    stats.append((n, W, H, len(rects), len(objects), len(blob)))
    return bytes(blob)


GLYPHS = {" ": 43, "\n": 44, ".": 36, ",": 37, "'": 38, "?": 39, "!": 40, "/": 41, "-": 42}


def to_glyphs(text):
    out = bytearray()
    for c in text:
        if "A" <= c <= "Z":
            out.append(ord(c) - 65)
        elif "0" <= c <= "9":
            out.append(26 + ord(c) - 48)
        elif c in GLYPHS:
            out.append(GLYPHS[c])
    return bytes(out)


WORD_ADVANCE = 5
SPACE_GLYPH = 43
NEWLINE_GLYPH = 44
# Word images sit above a level's own data in these banks. Levels 7 and 9 have the most text. A list's index is its level.
ATLAS_GROUPS = (
    (1, (9,)),
    (3, (7,)),
    (2, (0, 1, 2, 3, 4, 5, 6, 8)),
)


def split_words(glyphs):
    words = []
    word = bytearray()
    for g in glyphs:
        if g in (SPACE_GLYPH, NEWLINE_GLYPH):
            if word:
                words.append(bytes(word))
            word = bytearray()
        else:
            word.append(g)
    if word:
        words.append(bytes(word))
    return words


def word_image(word, table, sprites):
    """A whole word as one image, each letter where it would be if drawn alone, at the font's advance. Returns (w, h, bytes)."""
    pixels = {}
    for i, g in enumerate(word):
        e = table[(FONT2_BASE + g) * ENTRY_SIZE:(FONT2_BASE + g + 1) * ENTRY_SIZE]
        src, w, h, tx, ty = e[0] << 8 | e[1], e[2], e[3], e[4], e[5]
        for y in range(h):
            for b in range(w):
                v = sprites[src + y * w + b]
                for n, nib in ((0, v >> 4), (1, v & 15)):
                    if nib:
                        pixels[(WORD_ADVANCE * i + tx + b * 2 + n, ty + y)] = nib
    width = (max(x for x, _ in pixels) + 2) // 2 + 1    # one spare byte: the blitter's half-pixel shift needs it
    height = max(y for _, y in pixels) + 1
    data = bytearray(width * height)
    for (x, y), nib in pixels.items():
        data[y * width + x // 2] |= nib << 4 if x % 2 == 0 else nib
    return width, height, bytes(data)


def build_atlas(words, org_end, table, sprites):
    """Lays out unique words so that the last byte is just below org_end. Returns (org, bytes, word -> (src, w, h))."""
    images = {w: word_image(w, table, sprites) for w in sorted(set(words))}
    size = sum(len(v[2]) for v in images.values())
    org = org_end - size
    blob = bytearray()
    index = {}
    for w, (iw, ih, data) in images.items():
        index[w] = (org + len(blob), iw, ih)
        blob += data
    return org, bytes(blob), index


def build_messages(table, sprites):
    """Bank 10: one word per level pointing at a list of (count, then word offsets to strings with a 2-byte length). After
    each string, 3 bytes for each of its words: the image's address, with its top bit set for 6 lines rather than 5, and
    its width. Returns the messages, the atlases as (bank, org, bytes), and the bank for each level."""
    root = ET.parse(os.path.join(DATA, "messages.xml")).getroot()
    levels = [[(m.text or "").strip() for m in lv.findall("message")] for lv in root.findall("level")]
    atlases = []
    index = {}
    level_bank = [0] * len(levels)
    for bank, group in ATLAS_GROUPS:
        words = [w for i in group for m in levels[i] for w in split_words(to_glyphs(m))]
        org, blob, images = build_atlas(words, 0x4000, table, sprites)
        atlases.append((bank, org, blob))
        for i in group:
            index[i] = images
            level_bank[i] = bank
    table_size = len(levels) * 2
    body = bytearray()
    offsets_table = []
    for i, msgs in enumerate(levels):
        offsets_table.append(table_size + len(body))
        body += bytes([len(msgs)])
        strings = bytearray()
        offsets = []
        base = table_size + len(body) + len(msgs) * 2
        for m in msgs:
            g = to_glyphs(m)
            offsets.append(base + len(strings))
            strings += bytes([len(g) >> 8, len(g) & 255]) + g
            if i in index:
                for w in split_words(g):
                    src, iw, ih = index[i][w]
                    assert ih in (5, 6) and src < 0x4000, (ih, src)
                    strings += bytes([src >> 8 | (0x80 if ih == 6 else 0), src & 255, iw])
        for o in offsets:
            body += bytes([o >> 8, o & 255])
        body += strings
    blob = bytearray()
    for t in offsets_table:
        blob += bytes([t >> 8, t & 255])
    return bytes(blob + body), atlases, level_bank


def main():
    os.makedirs(OUT, exist_ok=True)
    table, sprites, sheet, terrain = build_sprites()
    with open(os.path.join(OUT, "sprtable.bin"), "wb") as f:
        f.write(table)
    with open(os.path.join(OUT, "sprites.bin"), "wb") as f:
        f.write(sprites)
    stats = []
    for n in range(1, 10):
        with open(os.path.join(OUT, f"level{n}.bin"), "wb") as f:
            f.write(build_level(n, sheet, stats))
    messages, atlases, level_bank = build_messages(table, SPACE)    # fonts may be in either bank 0 or fixed ROM
    with open(os.path.join(OUT, "messages.bin"), "wb") as f:
        f.write(messages)
    for bank, org, blob in atlases:
        with open(os.path.join(OUT, f"atlas{bank}.bin"), "wb") as f:
            f.write(blob)
        level_size = next(b for n, _, _, _, _, b in stats if n == bank)
        if level_size > org:
            raise SystemExit(f"level {bank} runs into its bank's word images: {level_size} > {org}")
    with open(os.path.join(OUT, "assets.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gen_assets.py. Do not edit.\n")
        f.write(f"FONT2_BASE equ {FONT2_BASE}\nFONT1_BASE equ {FONT1_BASE}\nPAL_BLACK equ {PAL_BLACK}\n")
        f.write(f"SPRITE_ENTRY equ {ENTRY_SIZE}\nRECT_BUCKET equ {RECT_BUCKET}\n")
        f.write(f"BLOCK_COLS equ {BLOCK_COLS}\nBLOCK_LINES equ {BLOCK_LINES}\nRECT_IMAGE equ {RECT_IMAGE}\nRECT_HIDE equ {RECT_HIDE}\nLINE_SOLID equ {LINE_SOLID}\n")
        for k, v in terrain.items():
            f.write(f"{k} equ {v}\n")
        f.write(f"SPR_EP_RED equ {FONT1_BASE + FONT1_COUNT}\nSPR_EP_WHITE equ {FONT1_BASE + FONT1_COUNT + 1}\n")
        for bank, org, blob in atlases:
            f.write(f"ATLAS{bank}_ORG equ {org}\n")
        f.write("ATLAS_BANKS macro\n fcb " + ",".join(str(b) for b in level_bank[:10]) + "\n endm\n")
        f.write("HW_PALETTE macro\n fcb " + ",".join(f"${v:02X}" for v in PALETTE) + "\n endm\n")
    print(f"sprite table: {len(table)} bytes, pixels: {len(sprites)} bytes")
    for n, W, H, r, o, b in stats:
        print(f"level {n}: {W}x{H}  rects {r}  objects {o}  rom {b}")
    print(f"messages: {len(messages)} bytes")
    print("word images, bank and bytes: " + ", ".join(f"{b} {len(d)}" for b, _, d in atlases))


if __name__ == "__main__":
    main()
