"""Fit a humanoid skeleton onto the downloaded soldier mesh and write it back as a
skinned GLB.

The model arrives from the asset generator as a single static mesh in an A-pose, so
there is nothing to animate. This script measures the mesh, places bones along the
measured limb centrelines, paints smooth skin weights and rewrites the GLB with a
glTF skin. Godot then imports it as a Skeleton3D and the game animates the bones in
code (see godot/character.gd).

    python tools/rig_character.py [assets/characters/soldier.glb]

Re-running is safe: the buffer is rebuilt from the mesh data every time, so old rig
data never piles up inside the file.
"""

import json
import struct
import sys

import numpy as np

# Bones are laid out in character space: +X is the character's left, +Y is up and
# +Z is the direction the model faces. Values come from the measurements printed by
# `measure()` below and match this particular soldier, not a generic humanoid.
BONES = [
    # name, parent, head position
    ("hips", None, (0.000, 0.440, 0.010)),
    ("spine", "hips", (0.000, 0.580, 0.010)),
    ("chest", "spine", (0.000, 0.740, 0.020)),
    ("neck", "chest", (0.000, 0.900, -0.010)),
    ("head", "neck", (0.000, 0.965, 0.000)),
    ("head_tip", "head", (0.000, 1.130, 0.010)),
    ("shoulder.L", "chest", (0.070, 0.850, -0.020)),
    ("upperarm.L", "shoulder.L", (0.155, 0.840, -0.030)),
    ("forearm.L", "upperarm.L", (0.208, 0.620, -0.030)),
    ("hand.L", "forearm.L", (0.205, 0.500, 0.000)),
    ("hand_tip.L", "hand.L", (0.200, 0.440, 0.010)),
    ("shoulder.R", "chest", (-0.070, 0.850, -0.020)),
    ("upperarm.R", "shoulder.R", (-0.155, 0.840, -0.030)),
    ("forearm.R", "upperarm.R", (-0.208, 0.620, -0.030)),
    ("hand.R", "forearm.R", (-0.205, 0.500, 0.000)),
    ("hand_tip.R", "hand.R", (-0.200, 0.440, 0.010)),
    ("thigh.L", "hips", (0.085, 0.420, 0.010)),
    ("shin.L", "thigh.L", (0.092, 0.290, 0.000)),
    ("foot.L", "shin.L", (0.115, 0.075, -0.010)),
    ("toe.L", "foot.L", (0.120, 0.015, 0.080)),
    ("thigh.R", "hips", (-0.085, 0.420, 0.010)),
    ("shin.R", "thigh.R", (-0.092, 0.290, 0.000)),
    ("foot.R", "shin.R", (-0.115, 0.075, -0.010)),
    ("toe.R", "foot.R", (-0.120, 0.015, 0.080)),
]

# A bone may only take real ownership of the body part it belongs to. Pure distance
# weighting would let the thighs grab the hands and the upper arms grab the ribs,
# because in an A-pose those surfaces are only centimetres apart. Bones from another
# region keep a small influence so the seams between regions still blend.
REGIONS = {
    "hips": "torso", "spine": "torso", "chest": "torso", "neck": "torso",
    "head": "torso", "head_tip": "torso",
    "shoulder.L": "arm.L", "upperarm.L": "arm.L", "forearm.L": "arm.L",
    "hand.L": "arm.L", "hand_tip.L": "arm.L",
    "shoulder.R": "arm.R", "upperarm.R": "arm.R", "forearm.R": "arm.R",
    "hand.R": "arm.R", "hand_tip.R": "arm.R",
    "thigh.L": "leg.L", "shin.L": "leg.L", "foot.L": "leg.L", "toe.L": "leg.L",
    "thigh.R": "leg.R", "shin.R": "leg.R", "foot.R": "leg.R", "toe.R": "leg.R",
}

CROSS = 0.05       # how much a bone from a neighbouring region may still pull
FALLOFF = 3.0      # weight = 1 / (distance + eps) ** FALLOFF
SMOOTH_PASSES = 4


def read_glb(path):
    with open(path, "rb") as handle:
        magic, version, _ = struct.unpack("<III", handle.read(12))
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


def to_character_space(positions):
    # The mesh is authored Z-up and stood upright by a node rotation; undo that so
    # the bone maths can be written in plain character coordinates.
    return np.stack([positions[:, 0], -positions[:, 2], positions[:, 1]], axis=1)


def segment_distance(points, start, end):
    axis = end - start
    length2 = float(axis @ axis)
    if length2 < 1e-9:
        return np.linalg.norm(points - start, axis=1)
    t = np.clip((points - start) @ axis / length2, 0.0, 1.0)
    return np.linalg.norm(points - (start + t[:, None] * axis), axis=1)


def build_weights(points, bone_index, heads, parents):
    # A bone owns the flesh between its own head and the head of its first child —
    # the upper arm is the segment from shoulder to elbow, not from neck to shoulder.
    # Getting this backwards makes the elbow deform the bicep and folds the mesh.
    first_child = {}
    for name, parent, _ in BONES:
        if parent and parent not in first_child:
            first_child[parent] = name

    order = [name for name, _, _ in BONES]
    distances = np.empty((len(points), len(order)))
    for column, name in enumerate(order):
        tail = first_child.get(name)
        distances[:, column] = segment_distance(points, heads[name], heads[tail] if tail else heads[name])
    # A vertex belongs to the body part of the bone it actually sits on. A plane
    # through the shoulder would cut the armpit in half and leave the inner sleeve
    # behind when the arm swings.
    nearest = distances.argmin(axis=1)
    region = np.array([REGIONS[order[column]] for column in nearest], dtype=object)

    weights = np.zeros((len(points), len(bone_index)), dtype=np.float64)
    for column, name in enumerate(order):
        own = region == REGIONS[name]
        weights[:, bone_index[name]] = 1.0 / (distances[:, column] + 0.012) ** FALLOFF * np.where(own, 1.0, CROSS)
    return weights
def smooth_weights(weights, indices, passes):
    # Averaging along mesh edges removes the hard seam where two regions meet, which
    # is what makes an automatic rig look like a paper doll when it bends.
    triangles = indices.reshape(-1, 3)
    edges = np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])
    edges = np.concatenate([edges, edges[:, ::-1]])
    counts = np.bincount(edges[:, 0], minlength=len(weights)).astype(np.float64)
    counts[counts == 0] = 1.0
    for _ in range(passes):
        summed = np.zeros_like(weights)
        np.add.at(summed, edges[:, 0], weights[edges[:, 1]])
        weights = 0.35 * weights + 0.65 * (summed / counts[:, None])
        weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    return weights


def top_four(weights):
    order = np.argsort(-weights, axis=1)[:, :4]
    picked = np.take_along_axis(weights, order, axis=1)
    picked /= np.maximum(picked.sum(axis=1, keepdims=True), 1e-12)
    return order.astype(np.uint8), picked.astype(np.float32)


def pad(blob):
    while len(blob) % 4:
        blob += b"\0"
    return blob


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/characters/soldier.glb"
    gltf, blob = read_glb(path)
    primitive = gltf["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    positions = accessor_array(gltf, blob, attributes["POSITION"], np.float32, 3)
    normals = accessor_array(gltf, blob, attributes["NORMAL"], np.float32, 3)
    uvs = accessor_array(gltf, blob, attributes["TEXCOORD_0"], np.float32, 2)
    indices = accessor_array(gltf, blob, primitive["indices"], np.uint16, 1).reshape(-1)

    bone_index = {name: i for i, (name, _, _) in enumerate(BONES)}
    heads = {name: np.array(head, dtype=np.float64) for name, _, head in BONES}
    parents = {name: parent for name, parent, _ in BONES}

    points = to_character_space(positions.astype(np.float64))
    weights = build_weights(points, bone_index, heads, parents)
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    weights = smooth_weights(weights, indices.astype(np.int64), SMOOTH_PASSES)
    joints, skin_weights = top_four(weights)

    # Bone heads back into glTF space (X right, Y forward, Z up in the mesh file).
    def to_gltf(position):
        return np.array([position[0], position[2], -position[1]], dtype=np.float64)

    rest = {name: to_gltf(heads[name]) for name in bone_index}
    inverse_binds = []
    for name, _, _ in BONES:
        matrix = np.eye(4)
        matrix[:3, 3] = -rest[name]
        inverse_binds.append(matrix.T.reshape(-1))  # glTF matrices are column-major
    inverse_binds = np.array(inverse_binds, dtype=np.float32)

    # Rebuild the binary chunk: mesh data, the three embedded textures, then the rig.
    chunks = []
    views = []
    offset = 0

    def add_view(data, target=None):
        nonlocal offset
        data = pad(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        chunks.append(data)
        offset += len(data)
        return len(views) - 1

    position_view = add_view(positions.tobytes(), 34962)
    normal_view = add_view(normals.tobytes(), 34962)
    uv_view = add_view(uvs.tobytes(), 34962)
    index_view = add_view(indices.tobytes(), 34963)
    joint_view = add_view(joints.tobytes(), 34962)
    weight_view = add_view(skin_weights.tobytes(), 34962)
    bind_view = add_view(inverse_binds.tobytes())

    image_views = []
    for image in gltf.get("images", []):
        source = gltf["bufferViews"][image["bufferView"]]
        start = source.get("byteOffset", 0)
        image_views.append(add_view(blob[start:start + source["byteLength"]]))

    count = len(positions)
    accessors = [
        {"bufferView": position_view, "componentType": 5126, "count": count, "type": "VEC3",
         "min": positions.min(axis=0).tolist(), "max": positions.max(axis=0).tolist()},
        {"bufferView": normal_view, "componentType": 5126, "count": count, "type": "VEC3"},
        {"bufferView": uv_view, "componentType": 5126, "count": count, "type": "VEC2"},
        {"bufferView": index_view, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        {"bufferView": joint_view, "componentType": 5121, "count": count, "type": "VEC4"},
        {"bufferView": weight_view, "componentType": 5126, "count": count, "type": "VEC4"},
        {"bufferView": bind_view, "componentType": 5126, "count": len(BONES), "type": "MAT4"},
    ]

    nodes = [{"name": "Soldier", "mesh": 0, "skin": 0}]
    joint_nodes = {}
    for name, parent, _ in BONES:
        local = rest[name] - (rest[parent] if parent else np.zeros(3))
        joint_nodes[name] = len(nodes)
        nodes.append({"name": name, "translation": [float(v) for v in local]})
    for name, parent, _ in BONES:
        if parent:
            nodes[joint_nodes[parent]].setdefault("children", []).append(joint_nodes[name])
    armature = len(nodes)
    nodes.append({
        "name": "Armature",
        # Same quarter turn the static model used to stand upright.
        "rotation": [0.7071068286895752, 0.0, 0.0, 0.7071068286895752],
        "children": [0, joint_nodes["hips"]],
    })

    primitive["attributes"] = {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "JOINTS_0": 4, "WEIGHTS_0": 5}
    primitive["indices"] = 3
    gltf["accessors"] = accessors
    gltf["bufferViews"] = views
    gltf["nodes"] = nodes
    gltf["scenes"] = [{"nodes": [armature]}]
    gltf["scene"] = 0
    gltf["skins"] = [{
        "name": "SoldierSkin",
        "inverseBindMatrices": 6,
        "skeleton": joint_nodes["hips"],
        "joints": [joint_nodes[name] for name, _, _ in BONES],
    }]
    for slot, image in enumerate(gltf.get("images", [])):
        image["bufferView"] = image_views[slot]

    binary = b"".join(chunks)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    # The JSON chunk is padded with spaces, not zeroes, so other glTF readers can
    # still parse the file.
    json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_blob) % 4:
        json_blob += b" "

    with open(path, "wb") as handle:
        total = 12 + 8 + len(json_blob) + 8 + len(binary)
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_blob), 0x4E4F534A))
        handle.write(json_blob)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)

    influences = (skin_weights > 0.02).sum(axis=1)
    print("rigged %s: %d vertices, %d bones, %.2f influences per vertex" % (
        path, count, len(BONES), influences.mean()))


if __name__ == "__main__":
    main()
