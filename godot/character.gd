extends Node3D
# Third-person soldier. The downloaded model is a static A-pose mesh, so
# tools/rig_character.py fits a 24-bone skeleton onto it and everything below poses
# those bones from code — there is no imported animation to play back.
#
# Bone space of this rig: +X is the soldier's own left, +Y is the direction it
# faces and +Z points down. So a rotation around X swings a limb forwards or
# backwards, around Y swings it out to the side, and around Z twists it.

const MODEL := preload("res://assets/characters/soldier.glb")
const MODEL_HEIGHT := 1.1393
const TARGET_HEIGHT := 1.78
const RIFLE_LENGTH_SCALE := .74
const WALK_CYCLE := 1.45
const RUN_CYCLE := 2.35
# Rifle axes expressed in skeleton space: the bore runs along the soldier's forward
# (+Y) and the rifle's up points at the soldier's up (-Z).
const RIFLE_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
# Where the pistol grip sits relative to the chest bone, in skeleton space. Raised
# above and pushed forward of the chest so the rifle sits at chest-to-shoulder
# height with both arms extended, the way a soldier actually carries one, instead
# of hanging low across the stomach.
const GRIP_FROM_CHEST := Vector3(-.045, .055, -.075)
const MAGAZINE_POUCH := Vector3(.15, .04, -.36)

var skeleton: Skeleton3D
var bones := {}
var rifle_mount: BoneAttachment3D
var pose_cache := {}
var stride := 0.0
var breath := 0.0
# Written by player.gd every frame; remote players derive speed from their synced
# position, so the animation never needs its own network traffic.
var ground_speed := 0.0
var sprinting := false
var crouching := false
var airborne := false
var aim_pitch := 0.0
var reload_progress := -1.0
var fire_kick := 0.0
var melee_swing := 0.0
# Handguard position relative to the pistol grip, in rifle space; player.gd fills it
# in from the rifle it mounts on the hand.
var support_offset := Vector3(0, .03, -.19)
var rifle_pose := Transform3D.IDENTITY

func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	model.name = "SoldierModel"
	# The mesh faces +Z, the player's forward is -Z.
	model.rotation.y = PI
	model.scale = Vector3.ONE * (TARGET_HEIGHT / MODEL_HEIGHT)
	add_child(model)
	skeleton = find_skeleton(model)
	if skeleton == null: return
	for index in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(index)] = index
	rifle_mount = BoneAttachment3D.new()
	rifle_mount.name = "RifleMount"
	rifle_mount.bone_name = "hand.R"
	skeleton.add_child(rifle_mount)
	# Snap straight into the carry pose so the rifle starts in the hand, not the
	# A-pose the mesh was generated in.
	pose_arms(1.0)

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found: return found
	return null

func model_scale() -> float:
	return TARGET_HEIGHT / MODEL_HEIGHT

func rifle_local_scale() -> float:
	# The rifle hangs under the skeleton, which is scaled up to human height, so it
	# has to be scaled back down to end up the right size in the world.
	return RIFLE_LENGTH_SCALE / model_scale()

func set_bone(bone: String, euler: Vector3, delta: float, speed := 14.0) -> void:
	apply_bone(bone, Quaternion.from_euler(euler), delta, speed)

func apply_bone(bone: String, target: Quaternion, delta: float, speed := 14.0) -> void:
	var index: int = bones.get(bone, -1)
	if index < 0: return
	var current: Quaternion = pose_cache.get(bone, target)
	current = current.slerp(target, clampf(delta * speed, 0.0, 1.0))
	pose_cache[bone] = current
	skeleton.set_bone_pose_rotation(index, current)

func bone_base(index: int) -> Transform3D:
	# Where a bone sits before its own pose is applied.
	var parent := skeleton.get_bone_parent(index)
	var parent_pose := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	return parent_pose * skeleton.get_bone_rest(index)

func solve_arm_ik(side: String, target: Vector3, pole: Vector3, delta: float, speed := 16.0) -> void:
	# Analytic two-bone IK. The limb bones have no rest rotation and each points at
	# its child, so aiming a bone is just the shortest rotation from the rest offset
	# onto the direction we want.
	var upper_index: int = bones.get("upperarm.%s" % side, -1)
	var fore_index: int = bones.get("forearm.%s" % side, -1)
	var hand_index: int = bones.get("hand.%s" % side, -1)
	if upper_index < 0 or fore_index < 0 or hand_index < 0: return
	var upper_offset := skeleton.get_bone_rest(fore_index).origin
	var fore_offset := skeleton.get_bone_rest(hand_index).origin
	var upper_length := upper_offset.length()
	var fore_length := fore_offset.length()
	var upper_base := bone_base(upper_index)
	var to_target := target - upper_base.origin
	var distance := clampf(to_target.length(), .02, (upper_length + fore_length) * .995)
	var direction := to_target.normalized()
	var swing := acos(clampf((upper_length * upper_length + distance * distance - fore_length * fore_length)
		/ (2.0 * upper_length * distance), -1.0, 1.0))
	var hinge := direction.cross(pole)
	if hinge.length_squared() < .0001: hinge = direction.cross(Vector3.RIGHT)
	var upper_direction := direction.rotated(hinge.normalized(), swing)
	apply_bone("upperarm.%s" % side,
		Quaternion(upper_offset.normalized(), (upper_base.basis.inverse() * upper_direction).normalized()),
		delta, speed)
	var fore_base := bone_base(fore_index)
	var elbow_to_target := target - fore_base.origin
	if elbow_to_target.length_squared() < .0001: return
	apply_bone("forearm.%s" % side,
		Quaternion(fore_offset.normalized(), (fore_base.basis.inverse() * elbow_to_target.normalized()).normalized()),
		delta, speed)

func offset_bone(bone: String, offset: Vector3, delta: float, speed := 12.0) -> void:
	var index: int = bones.get(bone, -1)
	if index < 0: return
	var rest := skeleton.get_bone_rest(index).origin
	var key := bone + ":pos"
	var current: Vector3 = pose_cache.get(key, rest + offset)
	current = current.lerp(rest + offset, clampf(delta * speed, 0.0, 1.0))
	pose_cache[key] = current
	skeleton.set_bone_pose_position(index, current)

func animate(delta: float) -> void:
	if skeleton == null: return
	breath += delta
	var moving := ground_speed > .35
	var cycle := RUN_CYCLE if sprinting else WALK_CYCLE
	if moving:
		# Driving the cycle with distance travelled keeps the feet from skating.
		stride += delta * ground_speed * cycle
	else:
		stride = lerp_angle(stride, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	pose_legs(delta, moving)
	pose_torso(delta, moving)
	pose_arms(delta)

func pose_legs(delta: float, moving: bool) -> void:
	var swing := 0.0
	var lift := 0.0
	if moving:
		swing = deg_to_rad(28.0 if sprinting else 20.0) * minf(ground_speed / 5.5, 1.4)
		lift = deg_to_rad(46.0 if sprinting else 30.0) * minf(ground_speed / 5.5, 1.4)
	var left := sin(stride)
	var right := sin(stride + PI)
	var crouch := deg_to_rad(42.0) if crouching else 0.0
	var brace := deg_to_rad(18.0) if airborne else 0.0
	for side in ["L", "R"]:
		var phase: float = left if side == "L" else right
		var forward := -swing * phase
		var knee: float = maxf(0.0, -phase) * lift
		if airborne:
			forward = -brace
			knee = deg_to_rad(38.0)
		set_bone("thigh.%s" % side, Vector3(forward - crouch * .85, 0, 0), delta, 16.0)
		set_bone("shin.%s" % side, Vector3(knee + crouch * 1.5, 0, 0), delta, 16.0)
		set_bone("foot.%s" % side, Vector3(-knee * .5 - crouch * .6, 0, 0), delta, 16.0)
	# Hips drop and rock with the stride; crouching pulls the whole body down.
	var bob := sin(stride * 2.0) * (.012 if moving else 0.0)
	var drop := (-.26 if crouching else 0.0) + (-.02 if airborne else 0.0)
	offset_bone("hips", Vector3(0, -bob * .5, -drop / model_scale() * -1.0), delta, 10.0)

func pose_torso(delta: float, moving: bool) -> void:
	# +Z is down in bone space, so a forward lean is a negative rotation about X.
	var lean := deg_to_rad(-6.0) if moving else deg_to_rad(-2.0)
	if sprinting and moving: lean = deg_to_rad(-12.0)
	if crouching: lean += deg_to_rad(-10.0)
	var sway := sin(stride) * deg_to_rad(3.0) if moving else sin(breath * 1.6) * deg_to_rad(1.2)
	var recoil := fire_kick * deg_to_rad(5.0)
	set_bone("spine", Vector3(lean * .45 + recoil * .4, 0, sway * .5), delta, 12.0)
	# The chest carries the aim: the soldier points the rifle where the player looks.
	set_bone("chest", Vector3(lean * .55 - aim_pitch * .55 + recoil * .6, 0, -sway), delta, 14.0)
	set_bone("neck", Vector3(-lean * .6 + aim_pitch * .25, 0, 0), delta, 12.0)
	set_bone("head", Vector3(-lean * .5 - aim_pitch * .2, 0, sin(breath * .9) * deg_to_rad(1.5)), delta, 10.0)

func pose_arms(delta: float) -> void:
	# The rifle is placed first, then both arms are solved onto it. That way the hands
	# always sit on the weapon instead of the weapon chasing a hand-tuned arm pose.
	var chest_index: int = bones.get("chest", -1)
	if chest_index < 0: return
	var chest := skeleton.get_bone_global_pose(chest_index)
	var aim := Basis(Vector3(1, 0, 0), -aim_pitch)
	var grip := chest.origin + aim * GRIP_FROM_CHEST
	var basis := aim * RIFLE_BASIS
	var speed := 14.0
	if melee_swing > 0.0:
		# Knife: the rifle is swept aside and the right arm punches across the body.
		grip += basis * Vector3(.10, -.04, .12) * melee_swing
		basis = basis.rotated(basis.z, deg_to_rad(-55.0) * melee_swing)
		speed = 22.0
	elif reload_progress >= 0.0:
		var tilt := reload_tilt()
		# Rock the rifle inboard and down so the magazine well faces the free hand.
		grip += basis * Vector3(-.03, -.05, .05) * tilt
		basis = basis.rotated(basis.x, deg_to_rad(26.0) * tilt).rotated(basis.y, deg_to_rad(-18.0) * tilt)
		speed = 16.0
	else:
		grip += basis * Vector3(0, 0, .035) * fire_kick
		basis = basis.rotated(basis.x, deg_to_rad(-7.0) * fire_kick)
	rifle_pose = Transform3D(basis, grip)
	solve_arm_ik("R", grip, Vector3(-.45, -.35, 1.0).normalized(), delta, speed)
	# Point the wrist so the rifle it carries ends up aimed where the soldier looks.
	var hand_index: int = bones.get("hand.R", -1)
	if hand_index >= 0:
		var hand_base := bone_base(hand_index)
		apply_bone("hand.R", (hand_base.basis.inverse() * basis).get_rotation_quaternion(), delta, speed)
	pose_support_arm(delta, speed)

func pose_support_arm(delta: float, speed: float) -> void:
	# The left hand rides the handguard and lets go to fetch a magazine on a reload.
	var target := rifle_pose * support_offset
	var reach := reload_reach()
	if reach > 0.0:
		target = target.lerp(MAGAZINE_POUCH, reach)
	solve_arm_ik("L", target, Vector3(.45, -.30, 1.0).normalized(), delta, speed)
	set_bone("hand.L", Vector3(0, deg_to_rad(18.0), 0), delta, speed)

func reload_reach() -> float:
	# 0 on the handguard, 1 down at the magazine pouch.
	if reload_progress < 0.0: return 0.0
	return smoothstep(.06, .30, reload_progress) - smoothstep(.62, .86, reload_progress)

func reload_tilt() -> float:
	if reload_progress < 0.0: return 0.0
	return smoothstep(0.0, .18, reload_progress) - smoothstep(.80, 1.0, reload_progress)
