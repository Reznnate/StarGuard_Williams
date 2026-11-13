#!/bin/sh
# Builds the vertical romset, for a monitor turned as Sinistar's: romset/blaster.zip here. Run ../tools/gen_assets.py --vertical
# first if art or levels changed. The sideways scroll moves 2 pixels a step; "sh build.sh 1px" builds it in 1-pixel steps
# (smoother, slower), and "sh build.sh nowait" without the wait for the beam on steps along the lines only (faster; a sprite
# may show erased for a frame). Anything else is passed to the assembler. Play it in MAME with -rol.
cd "$(dirname "$0")"
OPT=""
case "$1" in
    1px) OPT="-D VERT_STEP1=1"; shift ;;
    nowait) OPT="-D VERT_NOWAIT=1"; shift ;;
esac
mkdir -p build
python -I ../tools/as6809.py src/main.asm --banked --stub-undefined -D VERT=1 $OPT -o build/game.bin -l build/game.lst -s build/game.sym "$@" || exit 1
python -I ../tools/mkrom.py build/game.bin romset || exit 1
