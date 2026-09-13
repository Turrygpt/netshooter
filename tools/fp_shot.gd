extends Node3D
# Screenshot harness for the first-person view. It drops a single player on a bare
# lit floor, lets the pose settle and writes the camera image to a PNG, so the
# weapon and the hands can be checked without playing the game:
#
#     Godot_v4.7.1-stable_win64.exe --path . --windowed --resolution 1280x720 tools/fp_shot.tscn
#
# Arguments go after a bare `--`:
#
#   --out <path>        where to write the PNG (default res://tools/fp_shot.png)
#   --frames <n>        how long to wait; reloads and shots start 15 frames in, so a
#                       larger number captures a later point in the animation
#   --reload  --fire    play a reload or a shot before the capture
#   --fire-count <n>    fire n times back to back, ignoring the cooldown
#   --slot <n>          0 AK, 1 sniper, 2 knife, 3 frag, 4 smoke
#   --third             third-person camera        --scope   sniper scope overlay
#   --level             play in the real house instead of the bare test floor
#   --marks             draw dots on the rifle anchors and the hand bones
#   --weapon (x,y,z)  --weapon-rot (x,y,z)  --weapon-scale <f>
#   --anchor (x,y,z)  --arms-yaw <deg>      --arms-scale <f>
#                       try a different stance without editing player.gd
#   --set field=value   write a tunable on the arms rig, e.g. --set support_roll=300
#   --sweep <field> --sweep-values a,b,c
#                       one PNG per value, named <out>_<value>.png
#   --model <path> [--raw] [--angle <deg>] [--model-scale <f>] [--camera (x,y,z)]
#                       forget the player and just look at a character mesh

const PLAYER_SCENE := preload("res://godot/player.tscn")
const LEVEL_SCENE := preload("res://godot/Main.tscn")
const CHARACTER := preload("res://godot/character.gd")

var frames_left := 40
var action_frame := 25
var output := "res://tools/fp_shot.png"
var player: CharacterBody3D
var do_reload := false
var do_fire := false
var fire_count := 1
# `--model <path>` skips the player and just puts a rigged mesh in front of the
# camera, which is how the arms asset itself gets inspected.
var model_path := ""
var model_angle := 0.0
var model_scale := 1.0
var raw_model := false
var camera_position := Vector3(0, .8, 2.0)
var weapon_position := Vector3.INF
var weapon_rotation := Vector3.INF
var anchor := Vector3.INF
var arms_scale := 0.0
var weapon_scale := 0.0
var marks := false
# `--slot 1` shows the sniper instead of the AK, `--third` the third-person view.
var weapon_slot := -1
var third_person := false
var scope := false
# `--level` swaps the bare test floor for the real house, which is the only way to
# see grenades bounce off real walls and blow up through the level's own code.
var use_level := false
# `--pitch <deg>` aims the camera up or down before the action, e.g. to lob a
# grenade straight up and stand under it.
var aim_pitch := 999.0
var arms_yaw := 999.0
# `--sweep <field> <a,b,c>` writes one PNG per value of a tunable on the arms rig.
var sweep_field := ""
var sweep_values: PackedStringArray = []
# `--set field=value` writes any tunable on the arms rig before the shot, e.g.
# `--set support_reach=(0.8,0.4,-0.4)`.
var overrides: PackedStringArray = []

func _ready() -> void:
	read_arguments()
	# Actions fire 15 frames in, so `--frames` decides how far into a reload or a
	# recoil the picture is taken.
	action_frame = maxi(frames_left - 15, 1)
	if use_level:
		build_level()
		return
	build_stage()
	if model_path != "":
		show_model()
		return
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0, .1, 0)
	add_child(player)

func build_level() -> void:
	# The house itself becomes the running scene, so the player code finds the real
	# level under get_tree().current_scene and every effect goes through main.gd.
	var level := LEVEL_SCENE.instantiate()
	# The root is still building its own children at this point, so the house joins
	# the tree on the next idle frame and the game starts once it is ready.
	get_tree().root.add_child.call_deferred(level)
	level.ready.connect(start_level.bind(level))

func start_level(level: Node) -> void:
	get_tree().current_scene = level
	level.start_single_player()
	player = level.spawned[1]

func show_model() -> void:
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(0, model_angle, 0)
	add_child(pivot)
	if raw_model:
		# The imported scene without the game rig on top: the mesh exactly as authored.
		var model := (load(model_path) as PackedScene).instantiate() as Node3D
		model.scale = Vector3.ONE * model_scale
		pivot.add_child(model)
	else:
		var rig := CHARACTER.new()
		rig.model_scene = load(model_path)
		pivot.add_child(rig)
	var camera := Camera3D.new()
	camera.position = camera_position
	camera.look_at_from_position(camera_position, Vector3(0, camera_position.y, 0))
	camera.current = true
	add_child(camera)

func read_arguments() -> void:
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		match arguments[index]:
			"--out": output = arguments[index + 1] if index + 1 < arguments.size() else output
			"--frames": frames_left = int(arguments[index + 1]) if index + 1 < arguments.size() else frames_left
			"--reload": do_reload = true
			"--fire": do_fire = true
			"--fire-count": fire_count = int(arguments[index + 1]) if index + 1 < arguments.size() else fire_count
			"--model": model_path = arguments[index + 1] if index + 1 < arguments.size() else model_path
			"--angle": model_angle = float(arguments[index + 1]) if index + 1 < arguments.size() else model_angle
			"--model-scale": model_scale = float(arguments[index + 1]) if index + 1 < arguments.size() else model_scale
			"--raw": raw_model = true
			"--marks": marks = true
			"--slot": weapon_slot = int(arguments[index + 1]) if index + 1 < arguments.size() else weapon_slot
			"--third": third_person = true
			"--scope": scope = true
			"--level": use_level = true
			"--pitch": aim_pitch = float(arguments[index + 1]) if index + 1 < arguments.size() else aim_pitch
			"--arms-yaw": arms_yaw = float(arguments[index + 1]) if index + 1 < arguments.size() else arms_yaw
			"--camera": camera_position = str_to_var("Vector3" + arguments[index + 1]) if index + 1 < arguments.size() else camera_position
			"--weapon": weapon_position = str_to_var("Vector3" + arguments[index + 1]) if index + 1 < arguments.size() else weapon_position
			"--weapon-rot": weapon_rotation = str_to_var("Vector3" + arguments[index + 1]) if index + 1 < arguments.size() else weapon_rotation
			"--weapon-scale": weapon_scale = float(arguments[index + 1]) if index + 1 < arguments.size() else weapon_scale
			"--arms-scale": arms_scale = float(arguments[index + 1]) if index + 1 < arguments.size() else arms_scale
			"--set": overrides.append(arguments[index + 1] if index + 1 < arguments.size() else "")
			"--sweep": sweep_field = arguments[index + 1] if index + 1 < arguments.size() else sweep_field
			"--sweep-values": sweep_values = arguments[index + 1].split(",") if index + 1 < arguments.size() else sweep_values
			"--anchor": anchor = str_to_var("Vector3" + arguments[index + 1]) if index + 1 < arguments.size() else anchor

func build_stage() -> void:
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("2a3038")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("8fa0b4")
	world.ambient_light_energy = .9
	environment.environment = world
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)

	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, .4, 40)
	collider.shape = box
	collider.position = Vector3(0, -.2, 0)
	ground.add_child(collider)
	var surface := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = box.size
	surface.mesh = plane
	surface.position = collider.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a5158")
	surface.material_override = material
	ground.add_child(surface)
	add_child(ground)

	# A wall gives the hands something to read against instead of empty sky.
	var wall := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(20, 6, .4)
	wall.mesh = slab
	wall.position = Vector3(0, 3, -6)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color("6c7480")
	wall.material_override = wall_material
	add_child(wall)

func apply_overrides() -> void:
	# Trying a different weapon or shoulder placement without editing the game: the
	# player stops driving its own pose and the view is rebuilt from these values.
	if (weapon_position == Vector3.INF and weapon_rotation == Vector3.INF
			and anchor == Vector3.INF and arms_scale <= 0.0 and weapon_scale <= 0.0 and arms_yaw == 999.0
			and sweep_field == "" and overrides.is_empty()):
		return
	player.set_process(false)
	if weapon_position != Vector3.INF: player.view_weapon.position = weapon_position
	if weapon_rotation != Vector3.INF: player.view_weapon.rotation_degrees = weapon_rotation
	if anchor != Vector3.INF: player.first_person_arms.position = anchor
	if arms_yaw != 999.0: player.first_person_arms.rotation_degrees = Vector3(0, arms_yaw, 0)
	if weapon_scale > 0.0: player.view_weapon.scale = Vector3.ONE * weapon_scale
	if arms_scale > 0.0: player.first_person_arms.scale = Vector3.ONE * arms_scale
	for entry in overrides:
		var parts := entry.split("=")
		if parts.size() != 2: continue
		var value: Variant = str_to_var("Vector3" + parts[1]) if parts[1].begins_with("(") else float(parts[1])
		player.first_person_arms.set(parts[0], value)
	# A full-length step lands the arms on the weapon in one go.
	player.animate_first_person_arms(1.0)

func add_marks() -> void:
	# Little spheres on the rifle anchors, to see where the code thinks the grip and
	# the handguard are.
	for entry in [[player.ak47.to_global(player.AK47_GRIP), Color("ff4040")],
			[player.ak47.to_global(player.support_hold), Color("40ff60")],
			[bone_world("hand.L"), Color("4080ff")], [bone_world("hand_tip.L"), Color("ffe040")],
			[bone_world("hand.R"), Color("ff40ff")]]:
		var mark := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = .012
		ball.height = .024
		mark.mesh = ball
		var paint := StandardMaterial3D.new()
		paint.albedo_color = entry[1]
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark.material_override = paint
		add_child(mark)
		mark.global_position = entry[0]

func bone_world(bone: String) -> Vector3:
	var arms = player.first_person_arms
	var skeleton: Skeleton3D = arms.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(arms.bones.get(bone, 0)).origin

func report() -> void:
	# Numbers behind the picture: where the hands were asked to go and where the rig
	# actually put them.
	var arms = player.first_person_arms
	var skeleton: Skeleton3D = arms.skeleton
	for entry in [["hand.R", player.ak47.to_global(player.AK47_GRIP)],
			["hand.L", player.ak47.to_global(player.support_hold)]]:
		var index: int = arms.bones.get(entry[0], -1)
		var root: int = arms.bones.get("upperarm.%s" % String(entry[0]).right(1), -1)
		var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		var shoulder: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(root).origin
		print("%s target %v at %v shoulder %v miss %.3f reach %.3f" % [entry[0], entry[1], at,
			shoulder, at.distance_to(entry[1]), shoulder.distance_to(entry[1])])
		var tip: int = arms.bones.get("hand_tip.%s" % String(entry[0]).right(1), -1)
		var tip_at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(tip).origin
		var pose := skeleton.global_transform.basis * skeleton.get_bone_global_pose(index).basis
		print("   fingers %v boneZ %v boneX %v rifleX %v" % [(tip_at - at).normalized(),
			pose.z.normalized(), pose.x.normalized(), player.ak47.global_transform.basis.x.normalized()])

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)

func run_sweep() -> void:
	for value in sweep_values:
		player.first_person_arms.set(sweep_field, float(value))
		player.animate_first_person_arms(1.0)
		await capture(output.replace(".png", "_%s.png" % value))

func _process(_delta: float) -> void:
	# The player grabs the mouse on start; give it straight back so the harness never
	# takes over the desktop.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	frames_left -= 1
	if frames_left == action_frame and player:
		if aim_pitch != 999.0: player.get_node("CameraBoom").rotation.x = deg_to_rad(aim_pitch)
		if weapon_slot >= 0: player.select_weapon(weapon_slot)
		if scope:
			# The player resets the overlay every frame from its own aim state, so it has
			# to stop driving the view before the scope can be forced on.
			player.set_process(false)
			player.scope_overlay.active = true
			player.scope_overlay.queue_redraw()
		if third_person:
			player.third_person = true
			player.get_node("CameraBoom").spring_length = player.THIRD_PERSON_DISTANCE
			player.refresh_weapon_view()
		if do_reload:
			player.ak47_ammo = 8
			player.start_reload()
		if do_fire:
			for shot in fire_count:
				player.try_fire()
				player.fire_cooldown = 0.0
		apply_overrides()
	if frames_left > 0: return
	set_process(false)
	if player:
		report()
		if marks: add_marks()
	if sweep_field != "" and player:
		await run_sweep()
	else:
		await capture(output)
	get_tree().quit()
