#!/bin/sh
# Builds the vertical romset, for a monitor turned as Sinistar's: romset/blaster.zip here. Run ../tools/gen_assets.py --vertical
# first if art or levels changed. How the view scrolls sideways (2 pixels a step, 1 pixel, or 2 with no wait for the beam on
# steps along the lines only) is the SCROLL line of the advanced settings, not a build option. Any arguments are passed to the
# assembler. Play it in MAME with -rol.
cd "$(dirname "$0")"
mkdir -p build
python -I ../tools/as6809.py src/main.asm --banked --stub-undefined -D VERT=1 -o build/game.bin -l build/game.lst -s build/game.sym "$@" || exit 1
python -I ../tools/mkrom.py build/game.bin romset || exit 1
