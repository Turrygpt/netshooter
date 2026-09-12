"""Build the Netshooter prototype house in Blender and export its visual level."""
import bpy
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "netshooter_house.blend"
GLB = ROOT / "godot" / "assets" / "netshooter_house.glb"
TEXTURES = ROOT / "godot" / "assets" / "textures"

for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)

def mat(name, color, metallic=0.0, roughness=0.6, texture_name=None):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1)
    m.metallic = metallic; m.roughness = roughness
    if texture_name:
        texture_path = TEXTURES / texture_name
        if texture_path.exists():
            m.use_nodes = True
            nodes = m.node_tree.nodes
            image = bpy.data.images.load(str(texture_path), check_existing=True)
            texture = nodes.new("ShaderNodeTexImage"); texture.image = image
            shader = nodes.get("Principled BSDF")
            m.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
            shader.inputs["Roughness"].default_value = roughness
            shader.inputs["Metallic"].default_value = metallic
    return m

CONCRETE = mat("Concrete", (0.24, 0.27, 0.32), 0, .82, "wall_concrete.png")
FLOOR = mat("Floor", (0.11, 0.13, 0.16), .05, .7, "floor_tiles.png")
CEILING = mat("Acoustic ceiling", (.28, .3, .34), 0, .9, "ceiling_panels.png")
TRIM = mat("Safety yellow", (.95, .54, .05), .15, .4)
GUN = mat("Gun metal", (.04, .05, .06), .8, .26)
PLAYER = mat("Player mannequin", (.12, .55, .95), .1, .45)
WINDOW = mat("Window glow", (.14, .55, .9), .1, .25, "window_glass.png")
LADDER = mat("Ladder metal", (.08, .09, .1), .8, .4, "ladder_metal.png")
LAMP = mat("Cold fluorescent lamp", (.55, .8, 1.0), .0, .2)

def box(name, loc, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o=bpy.context.object; o.name=name; o.scale=[v/2 for v in scale]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=o.modifiers.new("Edge softening", "BEVEL"); mod.width=bevel; mod.segments=2
    o.data.materials.append(material)
    return o

def cylinder(name, loc, radius, depth, material, rotation=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth, location=loc, rotation=rotation or (0,0,0))
    o=bpy.context.object; o.name=name; o.data.materials.append(material); return o

ROOM=8.0; H=3.4; FLOORS=1
def wall_with_door(name, axis, coord, z, span_min, span_max, door_center, material=CONCRETE):
    # Wall split into two pieces around a 2.5 m traversable opening.
    gap=2.5; low=door_center-gap/2; high=door_center+gap/2
    for a,b in ((span_min,low),(high,span_max)):
        if b-a <= .01: continue
        mid=(a+b)/2
        if axis == 'x': box(name, (mid,coord,z+H/2), (b-a,.28,H), material, .04)
        else: box(name, (coord,mid,z+H/2), (.28,b-a,H), material, .04)
    # lintel makes the opening read as a door, not a missing wall
    if axis=='x': box(name+"_lintel", (door_center,coord,z+2.85), (gap,.28,1.1), material,.04)
    else: box(name+"_lintel", (coord,door_center,z+2.85), (.28,gap,1.1),material,.04)

for floor in range(FLOORS):
    z=floor*H
    # nine repeating 8x8 room slabs
    for gx in (-1,0,1):
        for gy in (-1,0,1):
            box(f"F{floor+1}_Room_{gx+2}{gy+2}_floor", (gx*ROOM,gy*ROOM,z-.15), (ROOM-.08,ROOM-.08,.3), FLOOR)
            if gx == 0 and gy == 1:
                # North room: a 2.4m square ceiling hatch, framed by four structural slabs.
                for side in (-1, 1):
                    box(f"F{floor+1}_north_hatch_side", (side*2.6,gy*ROOM,z+H), (2.8,ROOM-.08,.18), CEILING)
                    box(f"F{floor+1}_north_hatch_end", (0,gy*ROOM + side*2.6,z+H), (2.4,2.8,.18), CEILING)
            else:
                box(f"F{floor+1}_Room_{gx+2}{gy+2}_ceiling", (gx*ROOM,gy*ROOM,z+H), (ROOM-.08,ROOM-.08,.18), CEILING)
    # Exterior office facade: each outer room bay gets a framed 4.2m × 1.4m glazed window.
    for x in (-12,12):
        for y in (-8,0,8):
            box(f"F{floor+1}_facade_lower", (x,y,z+.7), (.35,8,1.4), CONCRETE,.04)
            box(f"F{floor+1}_facade_upper", (x,y,z+2.9), (.35,8,1.0), CONCRETE,.04)
            for side in (-1,1): box(f"F{floor+1}_facade_pier", (x,y+side*3.05,z+H/2), (.35,1.9,H), CONCRETE,.04)
            box(f"F{floor+1}_office_window", (x,y,z+2.0), (.09,4.2,1.4), WINDOW,.01)
    for y in (-12,12):
        for x in (-8,0,8):
            box(f"F{floor+1}_facade_lower", (x,y,z+.7), (8,.35,1.4), CONCRETE,.04)
            box(f"F{floor+1}_facade_upper", (x,y,z+2.9), (8,.35,1.0), CONCRETE,.04)
            for side in (-1,1): box(f"F{floor+1}_facade_pier", (x+side*3.05,y,z+H/2), (1.9,.35,H), CONCRETE,.04)
            box(f"F{floor+1}_office_window", (x,y,z+2.0), (4.2,.09,1.4), WINDOW,.01)
    # Two structural dividers per axis, split per room bay. Each bay has a real 2.5 m aperture.
    # This yields center→side and side→corner routes, without walls running through room centers.
    for y in (-4,4):
        for x in (-8,0,8):
            wall_with_door(f"F{floor+1}_north_south_passage", 'x', y, z, x-4, x+4, x)
    for x in (-4,4):
        for y in (-8,0,8):
            wall_with_door(f"F{floor+1}_east_west_passage", 'y', x, z, y-4, y+4, y)
    # yellow guides distinguish the central-room circulation routes.
    box(f"F{floor+1}_guide_x", (0,0,z+.02), (21,.12,.04), TRIM)
    box(f"F{floor+1}_guide_y", (0,0,z+.02), (.12,21,.04), TRIM)

# Ladder is turned 90 degrees and hugs the left (west) edge of the north-room hatch.
LADDER_X = -1.15
for z in (7.35, 8.65):
    cylinder("North_room_ladder_rail", (LADDER_X,z,H/2), .055, H-.25, LADDER)
for rung in range(7):
    cylinder("North_room_ladder_rung", (LADDER_X,8,.35 + rung*.42), .045, 1.4, LADDER)

# Sparse cold ceiling fixtures create pools of light, leaving unlit side rooms deliberately dark.
for x, y in ((0,0), (-8,-8), (8,-8), (-8,8), (8,8)):
    box("Ceiling_fluorescent_fixture", (x,y,H-.14), (1.5,.35,.10), LAMP,.02)
    bpy.ops.object.light_add(type='AREA', location=(x,y,H-.22))
    fixture_light=bpy.context.object; fixture_light.name="Cold_ceiling_light"; fixture_light.data.energy=450; fixture_light.data.shape='RECTANGLE'; fixture_light.data.size=3.0; fixture_light.data.color=(.55,.75,1.0)

# simple player doll in central ground room
base=Vector((0,0,.2))
cylinder("Player_body", base+Vector((0,0,1.05)), .34, 1.35, PLAYER)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=.38, location=base+Vector((0,0,2.0))); bpy.context.object.name="Player_head"; bpy.context.object.data.materials.append(PLAYER)
for x in (-.22,.22): cylinder("Player_leg", base+Vector((x,0,.38)), .13,.75,PLAYER)
for x in (-.42,.42):
    arm=cylinder("Player_arm", base+Vector((x,0,1.2)), .11,.85,PLAYER, (0, math.radians(18 if x>0 else -18),0))
# pistol aligned to right hand, visible in export
gun=box("Working_pistol_visual", (.72,-.02,1.2), (.65,.18,.24), GUN,.025)
box("Pistol_grip", (.56,-.02,1.02), (.16,.16,.42), GUN,.02)
cylinder("Pistol_barrel", (1.05,-.02,1.2), .06,.24,GUN,(0,math.pi/2,0))

# Dark ambient baseline; only the selected ceiling fixtures light the floor.
bpy.context.scene.world.color=(.005,.008,.015)
# review camera
bpy.ops.object.camera_add(location=(18,-22,16)); cam=bpy.context.object; cam.name='Production_Camera'; bpy.context.scene.camera=cam
def look(obj, target): obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
look(cam,(0,0,5)); cam.data.lens=28

scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=1280; scene.render.resolution_y=720; scene.render.resolution_percentage=50
scene['design_contract']='5 floors x 9 rooms; central-to-side and side-to-corner door openings; ramp in north room each floor; non-damaging LAN prototype uses web/ server.'
OUT.parent.mkdir(parents=True,exist_ok=True); GLB.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', export_apply=True, use_visible=True)
print(f'BUILT {OUT} and {GLB}')
