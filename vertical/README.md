# Star Guard, vertical

The game drawn turned a quarter, for a vertical monitor such as a Sinistar cabinet's, on the same Blaster hardware as the
horizontal build in the folder above. It has its own source, src/, and shares ../tools.

- Build: `sh build.sh` (2-pixel sideways scroll steps), `sh build.sh 1px`, or `sh build.sh nowait`. The romset is
  romset/blaster.zip here.
- Assets: `python ../tools/gen_assets.py --vertical` writes src/gen here.
- Play in MAME with `-rol`, as the turned monitor shows it.

With VERT=0 and the horizontal build's assets, src/ assembles to the same ROM as ../src: the two share all but the
drawing.
