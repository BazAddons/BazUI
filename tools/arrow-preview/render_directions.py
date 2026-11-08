"""Render the approved 30-degree camera through 108 arrow headings."""

import json
import math
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parent
POINTER = '--forever-pointer' in sys.argv
MAP_GOLD = '--map-gold' in sys.argv
STEM = 'BazUI-APS-Forever-Pointer-MapGold' if MAP_GOLD else ('BazUI-APS-Forever-Pointer' if POINTER else 'BazUI-Alliance-Arrow-Rich')
OUTPUT = ROOT / ('export-forever-pointer-map-gold' if MAP_GOLD else ('export-forever-pointer' if POINTER else 'export-rich'))
FRAMES = OUTPUT / "directions"
FRAMES.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT / (STEM + '.blend')))
scene = bpy.context.scene
arrow = bpy.data.objects["Arrow rotation pivot"]
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.resolution_percentage = 100
scene.cycles.samples = 64
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.frame_start = 0
scene.frame_end = 107

# The model turns; camera, lighting, scale and image center stay fixed.
for index in range(109):
    arrow.rotation_euler.z = math.tau * index / 108
    arrow.keyframe_insert(data_path="rotation_euler", index=2, frame=index)

metadata = {
    "frame_count": 108,
    "frame_size": [256, 256],
    "camera_elevation_degrees": 30,
    "angle_step_degrees": 360 / 108,
    "zero_direction": "Arrow points away from the camera, toward the top of the image.",
    "positive_rotation": "Counterclockwise about Blender's +Z axis; frame 27 points left.",
    "atlas": {"file": "arrow-directions-9x12.png", "columns": 9, "rows": 12,
              "width": 2304, "height": 3072, "order": "row-major, starting at top-left"},
    "frames": [],
}

for index in range(108):
    scene.frame_set(index)
    filename = f"arrow_{index:03d}.png"
    scene.render.filepath = str(FRAMES / filename)
    bpy.ops.render.render(write_still=True)
    metadata["frames"].append({"index": index, "angle_degrees": index * 360 / 108,
                               "file": "directions/" + filename})
    if index % 18 == 17:
        print(f"ARROW_PROGRESS {index + 1}/108", flush=True)

scene.frame_set(0)
scene.render.filepath = str(FRAMES / "arrow_")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / (STEM + '-108.blend')))
(OUTPUT / "directions.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
print("ARROW_DIRECTIONS_COMPLETE", OUTPUT, flush=True)
