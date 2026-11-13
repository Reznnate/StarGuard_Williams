#!/bin/sh
# Builds the romset: romset/blaster.zip. Run tools/gen_assets.py first if art or levels changed.
cd "$(dirname "$0")"
mkdir -p build
python -I tools/as6809.py src/main.asm --banked --stub-undefined -o build/game.bin -l build/game.lst -s build/game.sym "$@" || exit 1
python -I tools/mkrom.py build/game.bin romset || exit 1
