"""Validate and package the Blender PNGs; requires Pillow."""

import hashlib
import json
from pathlib import Path
import zipfile
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parent
POINTER = '--forever-pointer' in sys.argv
MAP_GOLD = '--map-gold' in sys.argv
OUTPUT = ROOT / ('export-forever-pointer-map-gold' if MAP_GOLD else ('export-forever-pointer' if POINTER else 'export-rich'))
metadata = json.loads((OUTPUT / "directions.json").read_text(encoding="utf-8"))
paths = [OUTPUT / entry["file"] for entry in metadata["frames"]]
assert len(paths) == 108
assert len(list((OUTPUT / "directions").glob("*.png"))) == 108
images = []
hashes = set()
for path in paths:
    with Image.open(path) as source:
        assert source.mode == "RGBA" and source.size == (256, 256), path
        image = source.copy()
    alpha = image.getchannel("A")
    assert alpha.getextrema() == (0, 255), path
    left, top, right, bottom = alpha.getbbox()
    assert left > 1 and top > 1 and right < 255 and bottom < 255, (path, alpha.getbbox())
    hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
    images.append(image)
assert len(hashes) == 108, "Duplicate direction frames"

atlas = Image.new("RGBA", (2304, 3072), (0, 0, 0, 0))
for index, image in enumerate(images):
    atlas.paste(image, ((index % 9) * 256, (index // 9) * 256))
atlas.save(OUTPUT / "arrow-directions-9x12.png")

# A viewing copy only; exported PNGs and atlas retain their true alpha.
preview = []
for image in images:
    background = Image.new("RGBA", image.size, (28, 33, 40, 255))
    background.alpha_composite(image)
    preview.append(background.convert("RGB"))
preview[0].save(OUTPUT / "rotation-preview.gif", save_all=True,
                append_images=preview[1:], duration=40, loop=0)

stem = 'BazUI-AGN-Forever-Pointer-MapGold-108' if MAP_GOLD else ('BazUI-AGN-Forever-Pointer-108' if POINTER else 'BazUI-Alliance-Arrow-Rich-108')
archive = OUTPUT / (stem + '.zip')
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
    for path in paths:
        bundle.write(path, path.relative_to(OUTPUT))
    for name in ("directions.json", "arrow-directions-9x12.png"):
        bundle.write(OUTPUT / name, name)
    bundle.write(ROOT / (stem + '.blend'), stem + '.blend')
    for name in ("build_preview.py", "build_forever_scroll.py", "build_map_gold.py", "render_directions.py", "pack_directions.py"):
        bundle.write(ROOT / name, "source/" + name)

print("Validated 108 distinct RGBA frames with transparent margins and no clipping.")
print("Atlas:", OUTPUT / "arrow-directions-9x12.png")
print("Archive:", archive, archive.stat().st_size, "bytes")
