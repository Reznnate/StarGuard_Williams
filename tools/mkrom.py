#!/usr/bin/env python3
"""Packs an assembled $50000-byte image into a MAME `blaster` romset.

usage: mkrom.py image.bin out_dir [--stock E:/torrent/roms/blaster.zip]

Main ROM files are cut from the image at the offsets MAME's driver loads them. Sound ROMs and the decoder
PROMs come from your own blaster.zip. blaster.col is replaced by an identity table so that the blitter
source remap leaves pixel values alone.
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("out_dir")
    ap.add_argument("--stock", default=r"E:\torrent\roms\blaster.zip")
    ap.add_argument("--robotron-sound", default=r"E:\torrent\roms\robotron.zip",
                    help="zip with Robotron's sound ROM, used in the Blaster sound sockets; empty keeps Blaster's")
    args = ap.parse_args()
    image = open(args.image, "rb").read()
    if len(image) != 0x50000:
        raise SystemExit(f"image is {len(image)} bytes; assemble with --banked")
    os.makedirs(args.out_dir, exist_ok=True)
    path = os.path.join(args.out_dir, "blaster.zip")
    with zipfile.ZipFile(args.stock) as stock, zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as out:
        for name, address, size in MAIN:
            out.writestr(name, image[address:address + size])
        sound = None
        if args.robotron_sound:
            with zipfile.ZipFile(args.robotron_sound) as other:
                sound = other.read("video_sound_rom_3_std_767.ic12")
        for name in COPIED:
            data = sound if sound and "rom_18" in name else stock.read(name)
            out.writestr(name, data)
        out.writestr("blaster.col", bytes(list(range(16)) * 128))
    print("wrote", path)


if __name__ == "__main__":
    main()
