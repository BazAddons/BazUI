"""Editable APS scroll arrow, built from the approved Forever color study.

Run with Blender --background --python build_forever_scroll.py.
All parts remain separate meshes with named materials and bevel modifiers.
"""
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parent
SIMPLE = '--simple-pointer' in sys.argv
STYLE = 'forever-pointer' if SIMPLE else 'forever-scroll'
BLEND_NAME = 'BazUI-APS-Forever-Pointer.blend' if SIMPLE else 'BazUI-APS-Forever-Scroll.blend'
OUT = ROOT / 'renders' / STYLE
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metallic, roughness, grain=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    if grain:
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = 48
        noise.inputs['Detail'].default_value = 3
        ramp = nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = 0.16
        ramp.color_ramp.elements[0].color = (*(c * .65 for c in color), 1)
        ramp.color_ramp.elements[1].position = .85
        ramp.color_ramp.elements[1].color = (*(c * 1.18 for c in color), 1)
        links.new(noise.outputs['Fac'], ramp.inputs[0])
        links.new(ramp.outputs[0], shader.inputs['Base Color'])
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .15
        bump.inputs['Distance'].default_value = .009
        links.new(noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs[0], shader.inputs['Normal'])
    return mat

brass = material('Antique brass | raised border and scrolls', (.30, .14, .035), .90, .34, True)
edge = material('Pale brass | fine edge catches', (.53, .30, .095), .88, .29)
bronze = material('Aged bronze | solid sidewalls', (.16, .075, .025), .72, .42, True)
groove = material('Brown patina | recessed border groove', (.039, .017, .007), .5, .52)
brown = material('Warm brown | textured inset face', (.080, .027, .008), .20, .59, True)

pivot = bpy.data.objects.new('Arrow rotation pivot', None)
bpy.context.collection.objects.link(pivot)

def mesh(name, vertices, faces, mat, bevel=.012):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = pivot
    data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new('Soft cast metal edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        normal = obj.modifiers.new('Weighted face normals', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
    return obj

def solid(name, poly, bottom, top, mat, bevel=.012):
    n = len(poly)
    verts = [(x,y,z) for z in (bottom,top) for x,y in poly]
    # Explicit triangulation keeps the deeply concave face and scrolls filled.
    points=[Vector((x,y,0)) for x,y in poly]
    lookup={tuple(v):i for i,v in enumerate(points)}
    triangles=[tuple(v if isinstance(v,int) else lookup[tuple(v)] for v in tri)
               for tri in tessellate_polygon([points])]
    faces = [tuple(reversed(tri)) for tri in triangles]
    faces += [tuple(i+n for i in tri) for tri in triangles]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name, verts, faces, mat, bevel)

def inset(poly, amount):
    result = []
    for i, p in enumerate(poly):
        v = Vector(p)
        a = (v-Vector(poly[i-1])).normalized()
        b = (Vector(poly[(i+1)%len(poly)])-v).normalized()
        c = a.x*b.y-a.y*b.x
        if abs(c) < 1e-6:
            q = v+Vector((-a.y,a.x))*amount
        else:
            p1 = v+Vector((-a.y,a.x))*amount
            p2 = v+Vector((-b.y,b.x))*amount
            d = p2-p1
            q = p1+a*((d.x*b.y-d.y*b.x)/c)
        result.append(tuple(q))
    return result

def ring(name, outer, inner, bottom, top, mat, bevel=.009):
    n = len(outer)
    verts = [(x,y,z) for z in (bottom,top) for poly in (outer,inner) for x,y in poly]
    faces = []
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,j+2*n,i+2*n),(i+n,i+3*n,j+3*n,j+n),
                      (i+2*n,j+2*n,j+3*n,i+3*n),(i,i+n,j+n,j)])
    return mesh(name,verts,faces,mat,bevel)

# Broad spade, curved shoulder cutouts, and the approved central rear V.
outline = [(0,1.65),(-1.12,.24),(-1.35,-.69),
           (-1.00,-.60),(-.83,-.62),(-.68,-.70),
           (-.55,-.84),(-.42,-1.03),(0,-.77),(.42,-1.03),
           (.55,-.84),(.68,-.70),(.83,-.62),(1.00,-.60),
           (1.35,-.69),(1.12,.24)]
if SIMPLE:
    # Four clean corners: long tip, two rear wings, and the deep central notch.
    outline = [(0,1.65),(-1.20,-1.00),(0,-.43),(1.20,-1.00)]
solid('01 | solid aged bronze body',outline,-.13,.10,bronze,.025)
ring('02 | outer brass bevel',outline,inset(outline,.09),.085,.205,brass,.016)
ring('03 | narrow pale highlight rail',inset(outline,.022),inset(outline,.046),.20,.223,edge,.006)
ring('04 | dark inset reveal',inset(outline,.09),inset(outline,.14),.09,.17,groove,.006)
ring('05 | fine inner brass lip',inset(outline,.14),inset(outline,.165),.10,.178,brass,.005)
solid('06 | recessed brown face',inset(outline,.163),.08,.149,brown,.01)

def smooth_path(points, steps=10):
    pts=[Vector(p) for p in points]
    samples=[]
    for i in range(len(pts)-1):
        a,b,c,d=pts[max(i-1,0)],pts[i],pts[i+1],pts[min(i+2,len(pts)-1)]
        for j in range(steps):
            t=j/steps
            v=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            samples.append(v)
    samples.append(pts[-1])
    return samples

scroll_points=[(1.23,-.59),(1.12,-.39),(.94,-.21),(.73,-.13),
               (.52,-.02),(.46,.17),(.55,.34),(.74,.37),(.88,.25),
               (.87,.10),(.76,.025),(.65,.085),(.67,.18)]

def scroll(side):
    path=smooth_path([(side*x,y) for x,y in scroll_points])
    left=[];right=[]
    for i,p in enumerate(path):
        tangent=(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
        normal=Vector((-tangent.y,tangent.x))
        # Ribbon tapers gently into the center of the curled terminal.
        width=.17*(1-.65*(i/(len(path)-1))**2)
        left.append(tuple(p+normal*width/2))
        right.append(tuple(p-normal*width/2))
    poly=left+list(reversed(right))
    # Orient both mirrored closed ribbons counter-clockwise for correct normals.
    area=sum(poly[i][0]*poly[(i+1)%len(poly)][1]-poly[(i+1)%len(poly)][0]*poly[i][1] for i in range(len(poly)))
    if area<0: poly.reverse()
    return solid(('07 | left' if side<0 else '08 | right')+' sculpted brass scroll',poly,.145,.255,brass,.012)

if not SIMPLE:
    scroll(-1);scroll(1)
# Rear nested chevron relief remains bronze rather than blue.
chevron=[(-.53,-.66),(0,-.31),(.53,-.66),(.48,-.73),(0,-.415),(-.48,-.73)]
if not SIMPLE:
    solid('09 | rear brass chevron',list(reversed(chevron)),.148,.207,brass,.012)

def light(name,pos,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    obj.location=pos;obj.rotation_euler=(-obj.location).to_track_quat('-Z','Y').to_euler()

light('Soft neutral key',(-3,-4,6),430,4,(1,.94,.85))
light('Neutral fill',(4,-1,4),300,5,(.86,.91,1))
light('Warm edge',(1,4,5),480,3,(1,.95,.86))
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.film_transparent=True
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.65,.69,.75,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.28
scene.view_settings.view_transform='AgX';scene.view_settings.exposure=-.45
data=bpy.data.cameras.new('Fixed orthographic camera')
camera=bpy.data.objects.new('Fixed orthographic camera',data)
bpy.context.collection.objects.link(camera);data.type='ORTHO';data.ortho_scale=3.65;scene.camera=camera

def camera_angle(degrees):
    a=math.radians(degrees)
    target=Vector((0,.15,.045))
    camera.location=target+Vector((0,-7*math.cos(a),7*math.sin(a)))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()

for angle,filename in [(60,'detail-60.png'),(30,'game-angle-30.png')]:
    camera_angle(angle)
    pivot.rotation_euler.z=0
    scene.render.filepath=str(OUT/filename)
    bpy.ops.render.render(write_still=True)

for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/BLEND_NAME))
print('FOREVER_ARROW_COMPLETE',OUT,flush=True)
