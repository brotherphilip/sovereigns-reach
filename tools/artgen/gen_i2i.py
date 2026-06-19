#!/usr/bin/env python3
"""img2img building refiner (iter203c).

Takes each cleaned source reference (input/srref/<name>.png, building on black) and runs a
moderate-denoise SDXL pass to add resolution + crisp painterly detail WHILE the reference pins
the isometric angle, composition and light direction. Then 4x Remacri upscale -> save.
This is what keeps the set internally consistent (plain t2i could not hold the angle).

Usage:
  gen_i2i.py <name> <denoise> [n]      test one building at a denoise level
  gen_i2i.py --batch <denoise>         refine all staged refs
Outputs to Sprites/Buildings/raw_i2i/<name>_d<denoise>_<i>.png
"""
import json, sys, time, os, random, urllib.request, urllib.parse
sys.path.insert(0, os.path.dirname(__file__))
from gen import SUBJECTS, COMFY, UPSCALER, post, get

# Illustration/2D-leaning SDXL — matches the source sheet's flat bright illustrated sprite
# style far better than the photoreal Juggernaut (which rendered everything dark/3D).
CKPT = "Illustrious-XL-v2.0.safetensors"

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "Sprites", "Buildings", "raw_i2i"))
os.makedirs(OUT, exist_ok=True)
STAGED = "/home/philip/Applications/AI/ComfyUI/input/srref"

# Refine-focused prompt: emphasize FINISH/QUALITY, not composition (that comes from the ref).
REFINE = (
    "{subj}, hand-painted 2D isometric game building sprite, "
    "Forge of Empires and Settlers and Anno art style, stylized painterly illustration, "
    "bright clean warm even daylight, soft readable lighting, rich crisp detail, sharp focus, "
    "vibrant but natural colors, high quality game asset, isolated on a solid pure black background"
)
NEG = (
    "dark, gloomy, heavy shadows, low key, muddy, desaturated, "
    "blurry, soft, lowres, jpeg artifacts, noise, grain, text, watermark, signature, "
    "multiple buildings, people, deformed, melted, warped, ugly, "
    "white background, gray background, sky, gradient background"
)

def graph(name, subj, seed, denoise, steps=30, cfg=5.0):
    return {
        "4":  {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "10": {"class_type": "LoadImage", "inputs": {"image": f"srref/{name}.png"}},
        "12": {"class_type": "VAEEncode", "inputs": {"pixels": ["10", 0], "vae": ["4", 2]}},
        "6":  {"class_type": "CLIPTextEncode", "inputs": {"text": REFINE.format(subj=subj), "clip": ["4", 1]}},
        "7":  {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "3":  {"class_type": "KSampler", "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg, "sampler_name": "dpmpp_2m_sde_gpu",
                "scheduler": "karras", "denoise": denoise,
                "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["12", 0]}},
        # Native 1024 decode — crisp and plenty for the ~256px in-game footprint. (A 4x ESRGAN
        # pass was tried and only over-magnified softness; native output is sharper.)
        "8":  {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9":  {"class_type": "SaveImage", "inputs": {"filename_prefix": "sri2i/r", "images": ["8", 0]}},
    }

def run_one(name, subj, seed, denoise):
    pid = post("/prompt", {"prompt": graph(name, subj, seed, denoise)})["prompt_id"]
    for _ in range(300):
        time.sleep(2)
        h = get(f"/history/{pid}")
        if pid in h:
            for nid, o in h[pid]["outputs"].items():
                for im in o.get("images", []):
                    return urllib.request.urlopen(
                        f"{COMFY}/view?filename={urllib.parse.quote(im['filename'])}"
                        f"&subfolder={urllib.parse.quote(im['subfolder'])}&type={im['type']}", timeout=60).read()
            return None
    return None

def generate(name, denoise, n):
    subj = SUBJECTS.get(name, name.replace("_", " "))
    print(f"[{name}] d={denoise}  {subj[:60]}")
    for i in range(n):
        seed = random.randint(1, 2**31)
        t0 = time.time()
        data = run_one(name, subj, seed, denoise)
        if not data:
            print(f"  cand {i}: FAILED"); continue
        out = os.path.join(OUT, f"{name}_d{denoise}_{i}.png")
        open(out, "wb").write(data)
        print(f"  cand {i}: {os.path.basename(out)} ({time.time()-t0:.0f}s)")

if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--batch":
        d = float(a[1]) if len(a) > 1 else 0.52
        n = int(a[2]) if len(a) > 2 else 2
        for nm in sorted(os.listdir(STAGED)):
            if nm.endswith(".png"):
                generate(nm[:-4], d, n)
    else:
        nm = a[0]; d = float(a[1]); n = int(a[2]) if len(a) > 2 else 1
        generate(nm, d, n)
