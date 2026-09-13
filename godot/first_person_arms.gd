extends "res://godot/character.gd"
# The player's own arms in first person. They are the soldier's arms — the mesh is
# cut straight out of the rigged body by tools/make_fp_arms.py — so what the player
# sees on the rifle is what everyone else sees him holding.
#
# The third-person rig builds a carry pose and hangs the rifle off the hand it ends
# up with. Here it works the other way round: the view weapon is drawn wherever the
# camera puts it and both arms are solved onto that rifle every frame, so the hands
# stay on the grip and the handguard whatever the weapon does. player.gd fills in
# the three fields below in world space.

# Pistol grip, forward hold and the rifle's own orientation, all in world space.
var grip_point := Vector3.ZERO
var support_point := Vector3.ZERO
var weapon_basis := Basis.IDENTITY

# How each hand sits on the rifle. `reach` is where the hand's long axis — wrist to
# fingertips — points in the rifle's own axes (+X right, +Y up, -Z down the bore),
# and `roll` turns the hand around that axis until the palm lands on the weapon.
# `palm` is where the gripped point sits inside the hand, in bone units: the bones
# carry no rest rotation, so there the fingers run along +Z and the hand bone itself
# sits in the middle of the palm.
var trigger_reach := Vector3(0, -.62, -.78)
var trigger_roll := 300.0
var trigger_palm := Vector3(0, 0, .012)
var support_reach := Vector3(.55, .55, -.63)
var support_roll := 300.0
var support_palm := Vector3(-.012, 0, .012)
# Carrying a grenade instead of the rifle: the throwing hand cups it from below and
# the other arm is simply sent to wherever `support_point` hangs, out of the frame.
var carrying := false
var carry_reach := Vector3(-.30, -.30, -.90)
var carry_roll := 240.0
var carry_palm := Vector3(0, 0, .010)
# Elbows: down and slightly outboard, the way they hang on a shouldered rifle.
const TRIGGER_POLE := Vector3(-.55, -.30, 1.0)
const SUPPORT_POLE := Vector3(.55, -.30, 1.0)
const POSE_SPEED := 18.0
# Breathing keeps the shoulders alive; without it the arms look welded to the screen.
const BREATH_SWAY := 1.1

var snap := true

func animate(delta: float) -> void:
	if skeleton == null: return
	breath += delta
	# A fresh rig starts in the A-pose of the mesh, so the first frame lands straight
	# on the weapon instead of swinging up to it in full view of the player.
	var blend := 1.0 if snap else delta
	snap = false
	pose_shoulders(blend)
	pose_hands(blend)

func pose_shoulders(delta: float) -> void:
	# Only the chest matters here: it carries the arm roots. It breathes, leans into a
	# sprint and takes the recoil the camera is already showing.
	var sway := sin(breath * BREATH_SWAY) * deg_to_rad(.9)
	var lean := deg_to_rad(-5.0) if sprinting and ground_speed > .35 else 0.0
	set_bone("spine", Vector3(lean * .4, 0, sway * .5), delta, 8.0)
	set_bone("chest", Vector3(lean * .6 + fire_kick * deg_to_rad(4.0), 0, -sway), delta, 10.0)

func pose_hands(delta: float) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	# The rifle's axes inside the skeleton, which is where the IK works.
	var rifle := skeleton.global_transform.basis.orthonormalized().inverse() * weapon_basis.orthonormalized()

	var trigger := rifle * hand_basis(carry_reach if carrying else trigger_reach,
		carry_roll if carrying else trigger_roll)
	solve_arm_ik("R", to_skeleton * grip_point - trigger * (carry_palm if carrying else trigger_palm),
		TRIGGER_POLE.normalized(), delta, POSE_SPEED)
	aim_hand("R", trigger, delta)

	var support := rifle * hand_basis(support_reach, support_roll)
	solve_arm_ik("L", to_skeleton * support_point - support * support_palm,
		SUPPORT_POLE.normalized(), delta, POSE_SPEED)
	aim_hand("L", support, delta)

func hand_basis(reach: Vector3, roll: float) -> Basis:
	# A hand frame in rifle space: the long axis is given, the rifle's own up decides
	# where the frame starts, and the roll turns the palm onto the weapon from there.
	var along := reach.normalized()
	var across := Vector3.UP - along * Vector3.UP.dot(along)
	if across.length_squared() < .0001: across = Vector3.RIGHT
	across = across.normalized().rotated(along, deg_to_rad(roll))
	return Basis(across, along.cross(across), along)

func aim_hand(side: String, target: Basis, delta: float) -> void:
	var index: int = bones.get("hand.%s" % side, -1)
	if index < 0: return
	var base := bone_base(index)
	apply_bone("hand.%s" % side, (base.basis.inverse() * target).get_rotation_quaternion(),
		delta, POSE_SPEED)
