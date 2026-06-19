#!/usr/bin/env python3
"""ComfyUI building-sprite generator for Sovereign's Reach (iter203).

Generates isometric building art matching the village_hall reference: warm painterly
3D-render look, red clay-tile roofs, stone+timber, grass plot, on SOLID BLACK background
(keyed to transparent later). SDXL @1024 -> 4x Remacri upscale -> save.

Usage:
  gen.py <btype> [n]          generate n candidates (default 4) for one building
  gen.py --batch              generate the whole SUBJECTS set (default candidates each)
  gen.py --list               list building keys
Outputs raw PNGs to Sprites/Buildings/raw/<btype>_<i>.png
"""
import json, sys, time, urllib.request, urllib.error, os, random

COMFY = "http://127.0.0.1:8188"
CKPT  = "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"
UPSCALER = "4x_foolhardy_Remacri.pth"
RAW_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "Sprites", "Buildings", "raw")
RAW_DIR = os.path.abspath(RAW_DIR)
os.makedirs(RAW_DIR, exist_ok=True)

# Shared style — the cohesive look of the whole set. {subj} is the per-building phrase.
# Tuned (iter203b): more "spritey" hand-painted game-asset look (Forge of Empires / Travian /
# Settlers), less photoreal CG; and FRAMED with a generous black margin so the whole plot sits
# inside the canvas (edges fade into black, never hard-cut at the image border).
STYLE = (
    "ONE single isolated {subj}, exactly one building and nothing else, "
    "hand-painted 2D isometric game building sprite, browser strategy game art, "
    "Forge of Empires and Travian and Anno art style, stylized painterly illustration, "
    "visible brush texture, warm storybook concept art, subtle clean dark outline, "
    "medieval fantasy European architecture, weathered red clay terracotta tile roof, "
    "stone masonry and timber framing, sitting on one small square grass base plot "
    "with cobblestones, "
    "the building and its large distinctive equipment are fully visible and centered, "
    "generous empty space around, wide black margin on all sides, not touching the edges, zoomed out, "
    "3/4 top-down isometric view, isolated on a solid pure black background"
)
NEG = (
    "village, multiple buildings, two buildings, neighboring buildings, surrounding houses, "
    "background buildings, rows of houses, town, city, street, multiple structures, cluster, "
    "photorealistic, photograph, 3d render, octane, cgi, realistic, hyperrealistic, "
    "blurry, out of focus, soft, low resolution, lowres, jpeg artifacts, noise, grain, "
    "text, words, letters, signage, watermark, signature, logo, "
    "crowd, people, person, character, animal, "
    "cropped, cut off, touching frame edge, filling the frame, zoomed in, close-up, "
    "deformed, distorted, melted, warped, asymmetrical mess, "
    "ugly, oversaturated, neon, blurry background, "
    "white background, gray background, sky, clouds, gradient background"
)

# Per-building subject phrases. Materials nudged to match the building's role while keeping
# the cohesive set look (military = darker timber/slate, etc.).
# Each phrase leads with a LARGE, SILHOUETTE-DEFINING identifying feature so the type reads
# even when rendered small in-game (props are oversized / foregrounded, not tiny clutter).
SUBJECTS = {
    "village_hall":    "grand village hall, a tall central bell-tower spire rising high above the roof, big red flag, large heraldic lion crest over wide arched double doors, broad stone entrance steps",
    "keep":            "tall fortified square stone keep tower, heavy crenellated battlements, narrow arrow slits, a big red banner down the front, far taller than wide",
    "guildhall":       "stately civic guildhall with a large columned stone portico across the whole front, ornate pediment, gold guild emblem, copper-green accents",
    "church":          "stone church dominated by one very tall pointed steeple with a cross on top, big arched stained-glass windows, far taller than wide",
    "cathedral":       "huge gothic cathedral with two tall twin spires, an enormous round rose window, rows of pointed arches, monumental and grand",
    "market":          "open-air marketplace, NO main house, several big striped cloth awning stalls heaped with produce crates and barrels around a tall stone market cross",
    "trading_post":    "merchant trading post, a big hanging golden-coin sign on a beam out front, stacks of trade crates and barrels and bundles piled high by the door",
    "inn":             "lively tavern inn, a large hanging painted tavern sign on an iron bracket, glowing lantern, big chimney with smoke, benches and barrels outside",
    "apothecary":      "village apothecary herbalist's shop, an open timber storefront hung with bunches of drying herbs and rows of glass remedy bottles and ceramic jars on shelves, a mortar and pestle, a green cross sign, climbing medicinal vines",
    "well":            "just a stone village well in the center, a tall timber A-frame with a roof and a bucket on a rope winch, NO house, mostly open grass",
    "hovel":           "tiny humble peasant cottage, low thatched roof, one crooked mud chimney with smoke, very small and simple",
    "granary":         "tall round thatched granary silo raised on stone staddle stones, a big conical thatch cap, sacks of grain stacked at the base",
    "bakery":          "village bakery, a huge domed stone bread oven with a tall smoking chimney built onto the front, trays of loaves, warm orange glow",
    "brewery":         "brewery, several oversized wooden ale barrels and a big copper brewing kettle dominating the front, hop vines, steam",
    "mill":            "windmill, four huge wooden sail blades on the roof dominating the silhouette, round stone tower base, sacks of flour",
    "dairy_farm":      "big red gambrel-roofed dairy barn with a tall silo beside it, fenced pasture, cows, hay bales, NOT a house",
    "apple_orchard":   "orchard, mostly many rows of large fruiting apple trees filling the plot, a small timber shed and apple crates in one corner, rail fence",
    "wheat_farm":      "wheat farm, mostly a big field of tall golden ripe wheat with a small timber barn and stacked hay bales at the edge",
    "hops_farm":       "hops farm, tall trellises covered in climbing green hop vines filling most of the plot, a small shed",
    "pig_farm":        "pig farm, a large fenced muddy pen full of pigs in the foreground with a small timber sty and feeding trough",
    "blacksmith":      "blacksmith, a huge stone forge furnace glowing bright orange with a tall smoking chimney and a big iron anvil out front under an open timber awning, hammers and tongs",
    "armorer":         "armorer workshop, large open front displaying big racks of shining plate armor breastplates helmets and shields, a forge chimney",
    "armory":          "stone armory storehouse, iron-banded doors, big wall racks of spears and swords, hanging shields and war banners on the front",
    "fletcher":        "fletcher's workshop, huge bundles of arrows and tall stacks of bow staves out front, hanging longbows, feathers, drying rack",
    "crossbow_workshop":"crossbow workshop, big display racks of crossbows on the open front, a heavy workbench with a winch and bolts",
    "poleturner":      "poleturner workshop, a big pole-lathe and tall stacks of long wooden spear and pike shafts leaning out front, wood shavings",
    "tannery":         "tannery, tall wooden frames with big stretched animal hides drying across the whole front, open vats of dye, leather-brown tones",
    "siege_workshop":  "siege workshop, a giant wooden trebuchet and a catapult dominating the foreground, towering over a small open timber work-shed, stacked boulders",
    "barracks":        "military barracks, a long fortified timber longhouse behind a spiked palisade, many tall red war banners on poles, weapon racks and training dummies",
    "watchtower":      "very tall slender wooden watchtower on four stilt legs with a roofed lookout platform at the top and a long ladder, a flag, far taller than wide",
    "lookout_tower":   "tall thin wooden lookout post tower, a small open roofed platform high on top, ladder, much taller than wide",
    "great_tower":     "enormous massive round stone fortress tower, heavy battlements, several banners, a fire beacon brazier on top, towering and imposing",
    "gatehouse":       "stone castle gatehouse, a big central arched gateway with a raised iron portcullis flanked by two battlemented towers, heraldic banners",
    "stone_wall":      "a straight section of tall crenellated grey stone castle curtain wall with battlements, NO building, NO roof",
    "wooden_palisade": "a straight section of tall sharpened vertical timber log palisade wall with a defensive walkway, NO building, NO roof",
    "woodcutter_camp": "woodcutter's logging camp, big stacks of cut logs and a large chopping block with an embedded axe dominating the yard, a small open timber lean-to, sawdust",
    "stone_quarry":    "stone quarry, a big open dug pit with terraced grey rock walls, large cut stone blocks and a tall timber lifting crane, NOT a house",
    "iron_mine":       "iron mine, a big rocky hill mound with a timber-framed mine tunnel entrance, ore carts on rails and heaps of dark ore, NOT a house",
    "pitch_rig":       "pitch tar works, a tall wooden derrick frame standing over a dark bubbling tar pit, rows of tar barrels, NOT a house",
    "stockpile":       "open storage depot, NO house, just big heaps of stacked crates sacks and barrels on a low timber platform",
}

def post(path, data):
    req = urllib.request.Request(COMFY + path, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read())

def get(path):
    return json.loads(urllib.request.urlopen(COMFY + path, timeout=30).read())

def graph(subj, seed, w=1024, h=1024, steps=34, cfg=6.0):
    """SDXL t2i -> VAEdecode -> 4x upscale -> save (API/prompt format)."""
    pos = STYLE.format(subj=subj)
    return {
        "4":  {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "6":  {"class_type": "CLIPTextEncode", "inputs": {"text": pos, "clip": ["4", 1]}},
        "7":  {"class_type": "CLIPTextEncode", "inputs": {"text": NEG, "clip": ["4", 1]}},
        "5":  {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "3":  {"class_type": "KSampler", "inputs": {
                "seed": seed, "steps": steps, "cfg": cfg, "sampler_name": "dpmpp_2m_sde_gpu",
                "scheduler": "karras", "denoise": 1.0,
                "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]}},
        "8":  {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "10": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": UPSCALER}},
        "11": {"class_type": "ImageUpscaleWithModel", "inputs": {"upscale_model": ["10", 0], "image": ["8", 0]}},
        "9":  {"class_type": "SaveImage", "inputs": {"filename_prefix": "srbuild/gen", "images": ["11", 0]}},
    }

def run_one(subj, seed):
    pid = post("/prompt", {"prompt": graph(subj, seed)})["prompt_id"]
    # poll history
    for _ in range(300):
        time.sleep(2)
        h = get(f"/history/{pid}")
        if pid in h:
            outs = h[pid]["outputs"]
            for nid, o in outs.items():
                for im in o.get("images", []):
                    data = urllib.request.urlopen(
                        f"{COMFY}/view?filename={urllib.parse.quote(im['filename'])}"
                        f"&subfolder={urllib.parse.quote(im['subfolder'])}&type={im['type']}",
                        timeout=60).read()
                    return data
            return None
    return None

def generate(btype, n):
    subj = SUBJECTS[btype]
    print(f"[{btype}] {subj}")
    for i in range(n):
        seed = random.randint(1, 2**31)
        t0 = time.time()
        data = run_one(subj, seed)
        if data is None:
            print(f"  cand {i}: FAILED")
            continue
        out = os.path.join(RAW_DIR, f"{btype}_{i}.png")
        with open(out, "wb") as f:
            f.write(data)
        _pad_black(out, frac=0.10)   # guarantee black margin on every side for clean keying
        print(f"  cand {i}: {out} (seed {seed}, {time.time()-t0:.0f}s, {len(data)//1024}KB)")

def _pad_black(path, frac=0.10):
    """Add a solid-black border (frac of the short side) so the subject never touches the edge."""
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB")
        m = int(min(im.size) * frac)
        canvas = Image.new("RGB", (im.width + 2 * m, im.height + 2 * m), (0, 0, 0))
        canvas.paste(im, (m, m))
        canvas.save(path)
    except Exception as e:
        print(f"    (pad skipped: {e})")

if __name__ == "__main__":
    import urllib.parse
    a = sys.argv[1:]
    if not a or a[0] == "--list":
        print("\n".join(sorted(SUBJECTS)))
    elif a[0] == "--batch":
        n = int(a[1]) if len(a) > 1 else 3
        for bt in SUBJECTS:
            generate(bt, n)
    else:
        bt = a[0]; n = int(a[1]) if len(a) > 1 else 4
        generate(bt, n)
