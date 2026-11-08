"""Recolor the approved pointer to match Forever's warm gold minimap rim."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'renders' / 'forever-pointer-map-gold'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'BazUI-APS-Forever-Pointer.blend'))

palette = {
    'Antique brass | raised border and scrolls': (.58, .255, .055),
    'Pale brass | fine edge catches': (.85, .48, .15),
    'Aged bronze | solid sidewalls': (.20, .065, .012),
    'Brown patina | recessed border groove': (.045, .014, .003),
    'Warm brown | textured inset face': (.12, .043, .009),
}
for name, color in palette.items():
    material = bpy.data.materials[name]
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color, 1)
    for node in material.node_tree.nodes:
        if node.type == 'VALTORGB':
            node.color_ramp.elements[0].color = (*(c * .65 for c in color), 1)
            node.color_ramp.elements[1].color = (*(c * 1.18 for c in color), 1)

scene = bpy.context.scene
scene.render.filepath = str(OUT / 'game-angle-30.png')
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'BazUI-APS-Forever-Pointer-MapGold.blend'))
print('MAP_GOLD_COMPLETE', OUT, flush=True)
