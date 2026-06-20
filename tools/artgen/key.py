#!/usr/bin/env python3
"""Key + install a chosen building render into the game (iter203).

Takes a raw render from Sprites/Buildings/raw/<btype>_<i>.png, floods the solid-black
background to transparent (edge flood-fill so the building's own dark areas stay opaque),
trims to the subject bounding box, downsizes to ~1400px max, and writes the game sprite to
view/micro/sprites/<btype>.png.

Usage:
  key.py <btype> <cand_index>      key+install one chosen candidate
  key.py --all selections.json     batch: {"btype": index, ...}
"""
import json, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW  = os.path.join(ROOT, "Sprites", "Buildings", "raw")
DEST = os.path.join(ROOT, "view", "micro", "sprites")
os.makedirs(DEST, exist_ok=True)
MAXDIM = 1400   # match the village_hall reference scale

def key_one(btype, idx):
    src = os.path.join(RAW, f"{btype}_{idx}.png")
    if not os.path.exists(src):
        print(f"  MISSING {src}"); return False
    dst = os.path.join(DEST, f"{btype}.png")
    # Keying the AI candidates is tricky: their "black" background is NOISY near-black
    # (lum up to ~0.10), and the building's own shadows are also near-black — so a plain
    # luminance floodfill can't cleanly separate them. Low fuzz leaves background islands
    # (opaque black boxes); high fuzz removes the bg but LEAKS through dark channels and
    # punches thin transparent slivers into the building.
    #   Fix: flood at 12% (clears the noisy bg) with `-fill none` (keeps RGB under the new
    #   alpha), then morphologically CLOSE the alpha — this re-fills the thin leak-slivers
    #   and any enclosed holes (which then show the real building RGB kept underneath) while
    #   leaving the large exterior transparent. Result: clean cutout, no holes, no black box.
    cmd = [
        "magick", src, "-alpha", "set", "-bordercolor", "black", "-border", "1",
        "-fill", "none", "-fuzz", "12%",
        "-draw", "alpha 0,0 floodfill",
        "-channel", "A", "-morphology", "Close", "Disk:4", "+channel",
        "-shave", "1x1",
        "-trim", "+repage",
        "-resize", f"{MAXDIM}x{MAXDIM}>",
        dst,
    ]
    subprocess.run(cmd, check=True)
    # report resulting geometry
    geo = subprocess.run(["magick", "identify", "-format", "%wx%h", dst],
                         capture_output=True, text=True).stdout
    print(f"  {btype}: {dst}  ({geo})")
    return True

if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--all":
        sel = json.load(open(a[1]))
        ok = sum(key_one(bt, i) for bt, i in sel.items())
        print(f"keyed {ok}/{len(sel)}")
    elif len(a) == 2:
        key_one(a[0], int(a[1]))
    else:
        print(__doc__)
