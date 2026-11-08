"""Build the BazUI arrow concept and render camera-angle comparisons.

Run with Blender in background mode. All output stays beside this script,
inside tools/, which BazUI's release package excludes.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parent
RENDERS = ROOT / "renders"
RENDERS.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, metallic, roughness, brushed=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if brushed:
        texture = nodes.new("ShaderNodeTexNoise")
        texture.inputs["Scale"].default_value = 145
        texture.inputs["Detail"].default_value = 2
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.12
        bump.inputs["Distance"].default_value = 0.008
        mat.node_tree.links.new(texture.outputs["Fac"], bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


gold = material("Warm brushed gold", (0.60, 0.225, 0.012), 1.0, 0.38, True)
edge_gold = material("Polished gold edge", (0.78, 0.32, 0.025), 1.0, 0.30)
steel = material("Dark steel sidewalls", (0.045, 0.055, 0.07), 0.72, 0.36, True)
blue = material("Alliance blue enamel", (0.002, 0.008, 0.20), 0.8, 0.42)

arrow = bpy.data.objects.new("Arrow rotation pivot", None)
bpy.context.collection.objects.link(arrow)
arrow.rotation_euler.z = math.radians(-25)

# Counter-clockwise outline; the tail's shallow V echoes the concept.
outline = [
    (0, 1.55), (-1.18, 0.08), (-0.43, 0.19),
    (-0.43, -1.12), (0, -0.91), (0.43, -1.12),
    (0.43, 0.19), (1.18, 0.08),
]


def inset(poly, distance):
    """Intersect parallel, inward-offset edges of this simple outline."""
    result = []
    for i, point in enumerate(poly):
        previous = Vector(poly[i - 1])
        current = Vector(point)
        following = Vector(poly[(i + 1) % len(poly)])
        a = (current - previous).normalized()
        b = (following - current).normalized()
        p = current + Vector((-a.y, a.x)) * distance
        q = current + Vector((-b.y, b.x)) * distance
        cross = a.x * b.y - a.y * b.x
        delta = q - p
        t = (delta.x * b.y - delta.y * b.x) / cross
        v = p + a * t
        result.append((v.x, v.y))
    return result


def mesh_object(name, vertices, faces, mat, bevel):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = arrow
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Soft machined bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.affect = "EDGES"
        mod = obj.modifiers.new("Weighted face normals", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    return obj


def solid(name, poly, bottom, top, mat, bevel=0.02):
    n = len(poly)
    vertices = [(x, y, z) for z in (bottom, top) for x, y in poly]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh_object(name, vertices, faces, mat, bevel)


def ring(name, outer, inner, bottom, top, mat, bevel=0.012):
    n = len(outer)
    vertices = [(x, y, z) for z in (bottom, top) for loop in (outer, inner) for x, y in loop]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [
            (i, j, j + 2 * n, i + 2 * n),
            (i + n, i + 3 * n, j + 3 * n, j + n),
            (i + 2 * n, j + 2 * n, j + 3 * n, i + 3 * n),
            (i, i + n, j + n, j),
        ]
    return mesh_object(name, vertices, faces, mat, bevel)


solid("Thick dark-metal body", outline, -0.14, 0.12, steel, 0.045)
inner_rim = inset(outline, 0.095)
inner_blue = inset(outline, 0.165)
ring("Raised gold perimeter", outline, inner_rim, 0.095, 0.21, edge_gold)
ring("Recessed blue enamel channel", inner_rim, inner_blue, 0.105, 0.172, blue, 0.008)
face = solid("Brushed gold central face", inner_blue, 0.10, 0.205, gold, 0.018)

def area_light(name, position, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()


area_light("Large soft key", (-3, -4, 6), 180, 4, (1, 0.90, 0.75))
area_light("Cool fill", (4, -1, 3), 110, 4, (0.72, 0.83, 1))
area_light("Back edge light", (1, 4, 4), 220, 3, (1, 0.94, 0.82))

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -0.65
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.65, 0.72, 0.85, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.10

camera_data = bpy.data.cameras.new("Fixed orthographic preview camera")
camera = bpy.data.objects.new("Fixed orthographic preview camera", camera_data)
bpy.context.collection.objects.link(camera)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 3.3
scene.camera = camera


def camera_angle(degrees):
    angle = math.radians(degrees)
    camera.location = (0, -7 * math.cos(angle), 7 * math.sin(angle))
    camera.rotation_euler = (Vector((0, 0, 0.06)) - camera.location).to_track_quat("-Z", "Y").to_euler()


camera_angle(30)
scene.render.filepath = str(RENDERS / "arrow-camera-30-rich.png")
bpy.ops.render.render(write_still=True)

# Save an editable scene opening directly onto the model through its camera.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_perspective = "CAMERA"
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "BazUI-Alliance-Arrow-Rich.blend"))
print("ARROW_PREVIEW_COMPLETE", ROOT)
