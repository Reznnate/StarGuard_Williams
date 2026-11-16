#!/usr/bin/env python3
"""Packs an assembled $50000-byte image into a MAME `blaster` romset.

usage: mkrom.py image.bin out_dir [--stock blaster.zip] [--robotron-sound robotron.zip]
       mkrom.py image.bin out_dir --game-only
       mkrom.py starguard_game_roms.zip out_dir [--stock ...] [--robotron-sound ...]

Main ROM files are cut from the image at the offsets MAME's driver loads them. The sound ROM and the decoder PROMs are
Williams' and are not part of this project: they come from your own romsets. The game's sounds are Robotron's, so its
sound ROM goes in the Blaster sound sockets; without --robotron-sound, Blaster's own sound ROM stays and the sounds are
wrong. blaster.col is replaced by an identity table so that the blitter source remap leaves pixel values alone.
Beside blaster.zip goes blaster_jrok.zip: the same files under the short names a JROK Williams FPGA board looks for.

Where your romsets are: the options, else the environment variables STARGUARD_BLASTER_ZIP and STARGUARD_ROBOTRON_ZIP,
else tools/roms.cfg beside this script (not checked in), with lines such as
    blaster=C:/mame/roms/blaster.zip
    robotron=C:/mame/roms/robotron.zip

--game-only writes out_dir/starguard_game_roms.zip instead: only the game's own files, which may be passed around. Give
that zip in place of the image to make a playable blaster.zip from it and your own romsets.
"""
import argparse
import os
import zipfile

MAIN = [
    ("proto6_blaster_3021_rom_11.ic25", 0x04000, 0x2000), ("proto6_blaster_3021_rom_12.ic26", 0x06000, 0x2000),
    ("proto6_blaster_3021_rom_17.ic41", 0x08000, 0x1000), ("proto6_blaster_3021_rom_16.ic39", 0x0D000, 0x1000),
    ("proto6_blaster_3021_rom_13.ic27", 0x0E000, 0x2000), ("proto5_blaster_3021_rom_15.ic38", 0x10000, 0x4000),
    ("proto5_blaster_3021_rom_8.ic20", 0x14000, 0x4000), ("proto5_blaster_3021_rom_9.ic22", 0x18000, 0x4000),
    ("proto5_blaster_3021_rom_10.ic24", 0x1C000, 0x4000), ("proto5_blaster_3021_rom_6.ic13", 0x20000, 0x4000),
    ("proto5_blaster_3021_rom_5.ic11", 0x24000, 0x4000), ("proto5_blaster_3021_rom_14.ic35", 0x28000, 0x4000),
    ("proto6_blaster_3021_rom_7.ic15", 0x2C000, 0x4000), ("proto5_blaster_3021_rom_1.ic1", 0x30000, 0x4000),
    ("proto5_blaster_3021_rom_2.ic3", 0x34000, 0x4000), ("proto6_blaster_3021_rom_4.ic7", 0x38000, 0x4000),
    ("proto6_blaster_3021_rom_3.ic6", 0x3C000, 0x4000),
]
COPIED = ["proto5_blaster_3021_rom_18.sb10", "proto5_blaster_3021_rom_18.sb13", "decoder_rom_4.ic42", "video_decoder_rom_6.ic23"]
COL = "blaster.col"
GAME_ZIP = "starguard_game_roms.zip"
JROK_ZIP = "blaster_jrok.zip"


def configured(key, env):
    """A romset's path from the environment or tools/roms.cfg; None if neither names one."""
    if os.environ.get(env):
        return os.environ[env]
    cfg = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roms.cfg")
    if os.path.exists(cfg):
        for line in open(cfg):
            name, _, value = line.partition("=")
            if name.strip() == key and value.strip():
                return value.strip()
    return None


def game_files(source):
    """The game's own files, name -> bytes, from an assembled image or from a zip made with --game-only."""
    if source.lower().endswith(".zip"):
        with zipfile.ZipFile(source) as z:
            return {name: z.read(name) for name in [m[0] for m in MAIN] + [COL]}
    image = open(source, "rb").read()
    if len(image) != 0x50000:
        raise SystemExit(f"image is {len(image)} bytes; assemble with --banked")
    files = {name: image[address:address + size] for name, address, size in MAIN}
    files[COL] = bytes(list(range(16)) * 128)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", help="the assembled image, or a zip made with --game-only")
    ap.add_argument("out_dir")
    ap.add_argument("--stock", help="your own blaster.zip: the decoder PROMs, and the sound ROM without --robotron-sound")
    ap.add_argument("--robotron-sound", help="your own robotron.zip: its sound ROM goes in the Blaster sound sockets")
    ap.add_argument("--game-only", action="store_true", help="write only the game's own files, to " + GAME_ZIP)
    args = ap.parse_args()
    files = game_files(args.image)
    os.makedirs(args.out_dir, exist_ok=True)
    if args.game_only:
        path = os.path.join(args.out_dir, GAME_ZIP)
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as out:
            for name, data in files.items():
                out.writestr(name, data)
        print("wrote", path)
        return
    stock_path = args.stock or configured("blaster", "STARGUARD_BLASTER_ZIP")
    if not stock_path:
        raise SystemExit("no blaster.zip named: give --stock, set STARGUARD_BLASTER_ZIP, or write tools/roms.cfg "
                         "(see the top of mkrom.py). Or use --game-only.")
    sound_path = args.robotron_sound or configured("robotron", "STARGUARD_ROBOTRON_ZIP")
    path = os.path.join(args.out_dir, "blaster.zip")
    with zipfile.ZipFile(stock_path) as stock, zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as out:
        for name, data in files.items():
            if name != COL:
                out.writestr(name, data)
        sound = None
        if sound_path:
            with zipfile.ZipFile(sound_path) as other:
                sound = other.read("video_sound_rom_3_std_767.ic12")
        else:
            print("no robotron.zip named: Blaster's own sound ROM is kept, and the game's sounds will be wrong")
        for name in COPIED:
            data = sound if sound and "rom_18" in name else stock.read(name)
            out.writestr(name, data)
        out.writestr(COL, files[COL])
    print("wrote", path)
    # The same files under the names a JROK Williams FPGA board looks for: each name from after its last underscore,
    # as 11.ic25 for proto6_blaster_3021_rom_11.ic25.
    jrok_path = os.path.join(args.out_dir, JROK_ZIP)
    with zipfile.ZipFile(path) as full, zipfile.ZipFile(jrok_path, "w", zipfile.ZIP_DEFLATED) as out:
        short = [name.rpartition("_")[2] for name in full.namelist()]
        if len(set(short)) != len(short):
            raise SystemExit("two files share a JROK name: " + " ".join(sorted(short)))
        for name, to in zip(full.namelist(), short):
            out.writestr(to, full.read(name))
    print("wrote", jrok_path)


if __name__ == "__main__":
    main()
