"""Cut the first-person arms out of the rigged soldier and write them as their own GLB.

The first-person view must show the same soldier the other players see, so the arms
are not modelled separately: they are the soldier's own arm geometry, carried over
with the skin weights tools/rig_character.py painted on it. Everything from the
shoulder down is kept — the upper arm sits behind the camera in game and hides the
cut — and the 24-bone skeleton is copied across unchanged, so godot/character.gd
poses this file exactly like the full body.

    python tools/make_fp_arms.py [assets/characters/soldier.glb]
        [assets/characters/first_person_arms.glb]

Run it again after re-rigging the soldier; the output is rebuilt from scratch.
"""

import json
import struct
import sys

import numpy as np

# Bones whose flesh belongs to the first-person arms. The shoulder is deliberately
# left out: its weights reach onto the vest and the shoulder pad, which would drag
# torso geometry into the view model.
ARM_BONES = [
    "upperarm.L", "forearm.L", "hand.L", "hand_tip.L",
    "upperarm.R", "forearm.R", "hand.R", "hand_tip.R",
]
# A triangle is kept when its vertices are mostly arm. Keeping the threshold below
# 1.0 preserves the blended band around the shoulder instead of tearing a ring of
# half-weighted triangles out of the mesh.
ARM_WEIGHT = 0.55
# Weight gates also catch a few scraps of webbing and knee pad that happen to lie
# beside the hands in the A-pose. They come out as their own little islands, so the
# mesh is split into connected pieces and only the two big ones — the arms — survive.
ISLAND_SHARE = 0.05


def read_glb(path):
    with open(path, "rb") as handle:
        magic, _, _ = struct.unpack("<III", handle.read(12))
        if magic != 0x46546C67:
            raise SystemExit("%s is not a GLB file" % path)
        json_length, _ = struct.unpack("<II", handle.read(8))
        gltf = json.loads(handle.read(json_length))
        binary_length, _ = struct.unpack("<II", handle.read(8))
        return gltf, handle.read(binary_length)


def accessor_array(gltf, blob, index, dtype, components):
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor["count"] * components
    return np.frombuffer(blob, dtype=dtype, count=count, offset=offset).reshape(-1, components)


def keep_largest_islands(triangles, positions):
    # Union-find over the triangle edges: an island is one connected piece of surface.
    # UV seams split a vertex into several copies in the file, so the pieces are found
    # on welded positions — otherwise every seam would read as its own island.
    _, welded = np.unique(np.round(positions, 5), axis=0, return_inverse=True)
    triangles = welded[triangles]
    parent = np.arange(len(positions))

    def find(item):
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    for triangle in triangles:
        root = find(triangle[0])
        for vertex in triangle[1:]:
            other = find(vertex)
            if other != root:
                parent[other] = root

    roots = np.array([find(triangle[0]) for triangle in triangles])
    keep = np.zeros(len(triangles), dtype=bool)
    for root in np.unique(roots):
        island = roots == root
        if island.sum() >= ISLAND_SHARE * len(triangles):
            keep |= island
    return keep


def pad(blob):
    while len(blob) % 4:
        blob += b"\0"
    return blob


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "assets/characters/soldier.glb"
    target = sys.argv[2] if len(sys.argv) > 2 else "assets/characters/first_person_arms.glb"
    gltf, blob = read_glb(source)
    if not gltf.get("skins"):
        raise SystemExit("%s has no skin; run tools/rig_character.py on it first" % source)

    primitive = gltf["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    positions = accessor_array(gltf, blob, attributes["POSITION"], np.float32, 3)
    normals = accessor_array(gltf, blob, attributes["NORMAL"], np.float32, 3)
    uvs = accessor_array(gltf, blob, attributes["TEXCOORD_0"], np.float32, 2)
    joints = accessor_array(gltf, blob, attributes["JOINTS_0"], np.uint8, 4)
    weights = accessor_array(gltf, blob, attributes["WEIGHTS_0"], np.float32, 4)
    indices = accessor_array(gltf, blob, primitive["indices"], np.uint16, 1).reshape(-1, 3)

    skin = gltf["skins"][0]
    bone_names = [gltf["nodes"][node]["name"] for node in skin["joints"]]
    arm_slots = {bone_names.index(name) for name in ARM_BONES if name in bone_names}
    if len(arm_slots) != len(ARM_BONES):
        raise SystemExit("%s is missing arm bones; expected %s" % (source, ARM_BONES))

    # How much of each vertex is driven by an arm bone.
    is_arm_slot = np.isin(joints, sorted(arm_slots))
    arm_share = (weights * is_arm_slot).sum(axis=1)
    keep_triangle = (arm_share[indices] >= ARM_WEIGHT).all(axis=1)
    kept_indices = indices[keep_triangle]
    if not len(kept_indices):
        raise SystemExit("no arm triangles found in %s" % source)
    kept_indices = kept_indices[keep_largest_islands(kept_indices, positions)]

    used = np.unique(kept_indices)
    remap = np.full(len(positions), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    positions = positions[used]
    normals = normals[used]
    uvs = uvs[used]
    joints = joints[used]
    weights = weights[used]
    triangles = remap[kept_indices].astype(np.uint16).reshape(-1)

    inverse_binds = accessor_array(gltf, blob, skin["inverseBindMatrices"], np.float32, 16)

    chunks = []
    views = []
    offset = 0

    def add_view(data, target_hint=None):
        nonlocal offset
        data = pad(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target_hint:
            view["target"] = target_hint
        views.append(view)
        chunks.append(data)
        offset += len(data)
        return len(views) - 1

    position_view = add_view(positions.tobytes(), 34962)
    normal_view = add_view(normals.tobytes(), 34962)
    uv_view = add_view(uvs.tobytes(), 34962)
    index_view = add_view(triangles.tobytes(), 34963)
    joint_view = add_view(joints.tobytes(), 34962)
    weight_view = add_view(weights.tobytes(), 34962)
    bind_view = add_view(inverse_binds.tobytes())

    image_views = []
    for image in gltf.get("images", []):
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        image_views.append(add_view(blob[start:start + view["byteLength"]]))

    count = len(positions)
    gltf["accessors"] = [
        {"bufferView": position_view, "componentType": 5126, "count": count, "type": "VEC3",
         "min": positions.min(axis=0).tolist(), "max": positions.max(axis=0).tolist()},
        {"bufferView": normal_view, "componentType": 5126, "count": count, "type": "VEC3"},
        {"bufferView": uv_view, "componentType": 5126, "count": count, "type": "VEC2"},
        {"bufferView": index_view, "componentType": 5123, "count": len(triangles), "type": "SCALAR"},
        {"bufferView": joint_view, "componentType": 5121, "count": count, "type": "VEC4"},
        {"bufferView": weight_view, "componentType": 5126, "count": count, "type": "VEC4"},
        {"bufferView": bind_view, "componentType": 5126, "count": len(inverse_binds), "type": "MAT4"},
    ]
    gltf["bufferViews"] = views
    primitive["attributes"] = {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "JOINTS_0": 4, "WEIGHTS_0": 5}
    primitive["indices"] = 3
    skin["inverseBindMatrices"] = 6
    skin["name"] = "FirstPersonArmsSkin"
    gltf["meshes"][0]["name"] = "FirstPersonArms"
    for node in gltf["nodes"]:
        if node.get("mesh") == 0:
            node["name"] = "FirstPersonArms"
    for slot, image in enumerate(gltf.get("images", [])):
        image["bufferView"] = image_views[slot]

    binary = b"".join(chunks)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_blob) % 4:
        json_blob += b" "

    with open(target, "wb") as handle:
        total = 12 + 8 + len(json_blob) + 8 + len(binary)
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_blob), 0x4E4F534A))
        handle.write(json_blob)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)

    print("wrote %s: %d vertices, %d triangles from %d" % (
        target, count, len(triangles) // 3, len(indices)))


if __name__ == "__main__":
    main()
