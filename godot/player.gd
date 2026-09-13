extends CharacterBody3D

const SPEED := 5.5
const SPRINT_SPEED := 8.5
const CROUCH_SPEED := 2.8
const GRAVITY := 18.0
const JUMP_VELOCITY := 6.5
const STANDING_HEIGHT := 1.8
const CROUCHING_HEIGHT := 1.25
const THIRD_PERSON_DISTANCE := 3.5
const FX := preload("res://godot/fx.gd")
const CHARACTER := preload("res://godot/character.gd")
const FIRST_PERSON_ARMS := preload("res://godot/first_person_arms.gd")
const FIRST_PERSON_ARMS_MODEL := preload("res://assets/characters/first_person_arms.glb")
const AK47_SCENE := preload("res://assets/guns/ak-47.glb")
const SNIPER_SCENE := preload("res://assets/guns/sniper.glb")
const RIFLE_SHOT_SOUND := preload("res://assets/sfx/rifle_single_shot_#4-1789249322799.mp3")
const SHELL_SOUND_A := preload("res://assets/sfx/gun_shell_fall_on_ti_#1-1789249467987.mp3")
const SHELL_SOUND_B := preload("res://assets/sfx/rifle_shell_fall_on__#3-1789249431048.mp3")
const RELOAD_SOUND := preload("res://assets/sfx/rifle_clip_rearm_#3-1789249495814.mp3")
const KNIFE_HIT_SOUND := preload("res://assets/sfx/knife_hit_stone.mp3")
const FOOTSTEP_SOUND := preload("res://assets/sfx/Heavy_boot_step_on_c_#4-1789290593954.mp3")
const JUMP_SOUND := preload("res://assets/sfx/A_person_in_sneakers_#2-1789290491180.mp3")
const KNIFE_SCENE := preload("res://assets/guns/knife.glb")
const LADDER_POSITIONS := [Vector3(7.15, 0, 8), Vector3(-8.85, -3.4, 8)]
const LADDER_CLIMB_SPEED := 2.7
const LADDER_TOP := 3.42
const LADDER_APPROACH_CLEARANCE := 0.15
const LADDER_APPROACH_REACH := 1.05
const AK47_MAGAZINE_SIZE := 30
const AK47_FIRE_INTERVAL := .095
const AK47_SPREAD_DEGREES := 1.6
const AK47_RELOAD_TIME := 2.35
const SNIPER_MAGAZINE_SIZE := 5
const SNIPER_RELOAD_TIME := 2.3
const KNIFE_SWING_INTERVAL := 1.1
# Grenades: the pin is pulled on the throw, so the fuse burns while the grenade is
# still in the air and a good throw goes off about where it lands.
const GRENADE_CARRIED := 2
const GRENADE_THROW_INTERVAL := .8
const GRENADE_FUSE := 2.2
const GRENADE_THROW_SPEED := 12.0
const GRENADE_THROW_LIFT := 2.6
const GRENADE_BLAST_RADIUS := 5.0
const GRENADE_BLAST_DAMAGE := 95
const AK47_MODEL_SCALE := .58
# Maps rifle axes onto hand-bone axes: the bore runs along the soldier's forward
# and the rifle's up points along the bone's up.
const HOLD_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
const HOLD_PALM := Vector3(0, .012, .02)
# Anchors below are measured on the imported rifle and already multiplied by
# AK47_MODEL_SCALE, so they are plain offsets inside the AK47 weapon root:
# +Y is the rifle's up, -Z is the bore direction.
const AK47_MUZZLE := Vector3(-.001, .148, -.362)
const AK47_MAGAZINE_LUG := Vector3(0, .113, -.084)
const AK47_MAGAZINE_CENTER := Vector3(0, .063, -.015)
const AK47_GRIP := Vector3(0, .073, .126)
# The support hand grips the rear of the handguard in both views: that is as far
# forward as an arm reaches without going ramrod straight, whether the rifle is
# carried at the chest or held out in front of the camera.
const AK47_HANDGUARD_HOLD := Vector3(0, .112, -.11)
# The first-person arms are the soldier's, so they are scaled to the view rifle —
# which is drawn smaller than a real one — and the rig hangs off the camera at
# ARMS_ANCHOR, which puts the shoulders below the frame edge and far enough forward
# for the support hand to reach the handguard.
const ARMS_SCALE := 1.02
const ARMS_ANCHOR := Vector3(0, -1.619, -.14)
# The soldier stands bladed behind the rifle, left shoulder forward, the way anyone
# holding a rifle does: that is what lets the support arm reach the handguard while
# the trigger arm still folds up behind the grip.
const ARMS_BLADE := -35.0
# Where the free hand waits while the other one carries a grenade: down and out to
# the side, just below the frame.
const FREE_HAND_REST := Vector3(-.34, -.46, -.24)
# The rifle arrives as a single mesh, so the detachable magazine is cut out of it
# in mesh space: below the magazine well floor and in front of the trigger guard.
const MAGAZINE_CUT_Y := .072
const MAGAZINE_CUT_Z := -.198
# Reload beats as a fraction of AK47_RELOAD_TIME: magazine falls, support hand
# fetches a fresh one, magazine locks in, rifle returns to the shoulder.
const RELOAD_EJECT_AT := .17
const RELOAD_FETCH_AT := .52
const RELOAD_SEAT_AT := .82
enum Weapon { AK47, SNIPER, KNIFE, FRAG, SMOKE }
static var ak47_body_mesh: ArrayMesh
static var ak47_magazine_mesh: ArrayMesh

class ScopeOverlay extends Control:
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if !active: return
		var center := size * .5
		var radius := minf(size.x, size.y) * .36
		draw_vignette(center, radius)
		draw_arc(center, radius, 0.0, TAU, 96, Color("e7f4f7"), 7.0, true)
		draw_arc(center, radius - 5.0, 0.0, TAU, 96, Color("ffffff"), 1.0, true)
		var reticle := Color(0.9, 1.0, 0.94, .95)
		draw_line(center + Vector2(-radius * .72, 0), center + Vector2(radius * .72, 0), reticle, 1.5)
		draw_line(center + Vector2(0, -radius * .72), center + Vector2(0, radius * .72), reticle, 1.5)
		draw_circle(center, 3.0, Color("d6ffe0"))
		for step in range(1, 6):
			var offset := radius * step / 6.0
			draw_line(center + Vector2(-7, -offset), center + Vector2(7, -offset), reticle, 1.0)
			draw_line(center + Vector2(-7, offset), center + Vector2(7, offset), reticle, 1.0)

	func draw_vignette(center: Vector2, radius: float) -> void:
		# Everything around the eyepiece goes dark while the scope window itself stays
		# untouched: the ring is laid down as a fan of quads rather than a full-screen
		# rectangle, so nothing is ever drawn over the picture the shooter is aiming at.
		var shade := Color(0.0, 0.0, 0.0, .72)
		var outside := size.length()
		# The fan starts a couple of pixels out, so its faceted inner edge hides under
		# the eyepiece ring instead of serrating the rim of the picture.
		radius += 2.0
		var steps := 128
		for step in steps:
			var from := TAU * step / steps
			var to := TAU * (step + 1) / steps
			var edge_from := Vector2(cos(from), sin(from))
			var edge_to := Vector2(cos(to), sin(to))
			draw_colored_polygon(PackedVector2Array([
				center + edge_from * radius, center + edge_from * outside,
				center + edge_to * outside, center + edge_to * radius]), shade)

# A thrown grenade. Every peer runs this simulation from the same launch numbers, so
# the flight and the bounces match everywhere without any per-frame network traffic.
class GrenadeProjectile extends Node3D:
	var velocity := Vector3.ZERO
	var grenade_type := 3
	var owner_player: Node
	var fuse := 2.2

	func _process(delta: float) -> void:
		fuse -= delta
		var from := global_position
		velocity.y -= 18.0 * delta
		var to := from + velocity * delta
		var query := PhysicsRayQueryParameters3D.new()
		query.from = from
		query.to = to
		query.collision_mask = 1
		if is_instance_valid(owner_player): query.exclude = [owner_player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = to
		else:
			global_position = hit.position + hit.normal * .025
			velocity = velocity.bounce(hit.normal) * .42
			if velocity.length() < 1.0: velocity = Vector3.ZERO
		rotation += Vector3(4.0, 7.0, 5.0) * delta
		if fuse <= 0.0:
			if is_instance_valid(owner_player) and owner_player.has_method("detonate_grenade"):
				owner_player.detonate_grenade(global_position, grenade_type)
			queue_free()
var pitch := 0.0
var yaw := 0.0
var fire_cooldown := 0.0
var third_person := false
var climbing := false
var active_weapon := Weapon.AK47
var view_weapon: Node3D
var ak47: Node3D
var sniper: Node3D
var knife: Node3D
var frag_grenade: Node3D
var smoke_grenade: Node3D
var recoil_amount := 0.0
var ak47_ammo := AK47_MAGAZINE_SIZE
var reserve_ammo := 90
var sniper_ammo := SNIPER_MAGAZINE_SIZE
var sniper_reserve_ammo := 20
var frag_ammo := GRENADE_CARRIED
var smoke_ammo := GRENADE_CARRIED
var is_reloading := false
var reload_timer := 0.0
var ammo_label: Label
var health := 100
var health_label: Label
var shot_player: AudioStreamPlayer3D
var shell_player_a: AudioStreamPlayer3D
var shell_player_b: AudioStreamPlayer3D
var reload_player: AudioStreamPlayer3D
var knife_hit_player: AudioStreamPlayer3D
var footstep_player: AudioStreamPlayer3D
var jump_player: AudioStreamPlayer3D
var muzzle: Marker3D
var magazine_pivot: Node3D
var character: Node3D
var first_person_arms
var scope_overlay: ScopeOverlay
var aiming := false
var fp_muzzle: Marker3D
var fp_magazine_pivot: Node3D
var world_muzzle: Marker3D
var world_magazine_pivot: Node3D
var is_crouching := false
var reload_show_timer := 0.0
var melee_timer := 0.0
var previous_position := Vector3.ZERO
var active_ladder := Vector3.ZERO
var camera_kick := Vector2.ZERO
var step_distance := 0.0
# Where the left hand holds the rifle, in AK47 weapon space. It rides the handguard
# and travels down to the magazine pouch during a reload.
var support_hold := AK47_HANDGUARD_HOLD

# Shells and spent magazines only need to look right, so they bounce on a single
# ground plane instead of adding rigid bodies to the gameplay simulation.
class FallingDebris extends Node3D:
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var floor_y := 0.0
	var bounce := .32
	var life := 5.0
	var age := 0.0

	func _process(delta: float) -> void:
		age += delta
		if age > life:
			queue_free()
			return
		velocity.y -= 16.0 * delta
		global_position += velocity * delta
		rotation += spin * delta
		if global_position.y > floor_y: return
		global_position.y = floor_y
		velocity.y = absf(velocity.y) * bounce
		velocity.x *= .62
		velocity.z *= .62
		spin *= .45
		if velocity.y < .4:
			velocity.y = 0.0
			spin = spin.limit_length(1.2)

func _ready() -> void:
	add_to_group("players")
	$Collider.shape = CapsuleShape3D.new()
	$Collider.shape.radius = .35
	$Collider.shape.height = STANDING_HEIGHT
	$Body.visible = false
	previous_position = global_position
	create_character()
	create_audio_players()
	if is_multiplayer_authority():
		create_view_weapons()
		create_first_person_arms()
		create_ammo_hud()
		create_scope_overlay()
		$CameraBoom/Camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh_weapon_view()

func add_weapon_part(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = position
	part.material_override = material(color)
	parent.add_child(part)

func add_cylinder_part(parent: Node3D, radius: float, height: float, position: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	part.mesh = cylinder
	part.position = position
	part.rotation.x = deg_to_rad(90.0)
	part.material_override = material(color)
	parent.add_child(part)

func create_weapon_root(weapon_name: String) -> Node3D:
	var weapon := Node3D.new()
	weapon.name = weapon_name
	$CameraBoom/Camera.add_child(weapon)
	return weapon

static func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var found := find_mesh_instance(child)
		if found: return found
	return null

static func prepare_ak47_parts(source: MeshInstance3D) -> void:
	# Split the imported rifle into a body and a magazine once per process: both parts
	# reuse the original vertex data and only own a slice of the index buffer.
	if ak47_body_mesh: return
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var in_magazine := PackedByteArray()
	in_magazine.resize(vertices.size())
	for index in vertices.size():
		var vertex := vertices[index]
		in_magazine[index] = 1 if vertex.z > MAGAZINE_CUT_Z and vertex.y < MAGAZINE_CUT_Y else 0
	var body_indices := PackedInt32Array()
	var magazine_indices := PackedInt32Array()
	for triangle in indices.size() / 3:
		var a := indices[triangle * 3]
		var b := indices[triangle * 3 + 1]
		var c := indices[triangle * 3 + 2]
		if in_magazine[a] + in_magazine[b] + in_magazine[c] >= 2:
			magazine_indices.push_back(a); magazine_indices.push_back(b); magazine_indices.push_back(c)
		else:
			body_indices.push_back(a); body_indices.push_back(b); body_indices.push_back(c)
	var rifle_material := source.mesh.surface_get_material(0)
	ak47_body_mesh = mesh_from_indices(arrays, body_indices, rifle_material)
	ak47_magazine_mesh = mesh_from_indices(arrays, magazine_indices, rifle_material)

static func mesh_from_indices(arrays: Array, indices: PackedInt32Array, part_material: Material) -> ArrayMesh:
	var part_arrays := arrays.duplicate()
	part_arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part_arrays)
	mesh.surface_set_material(0, part_material)
	return mesh

static func magazine_mesh_instance(offset: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "Magazine"
	part.mesh = ak47_magazine_mesh
	# The glTF mesh is stored Z-up, so it carries the same +90° roll as the rifle body.
	part.transform = Transform3D(Basis.from_euler(Vector3(PI * .5, 0, 0)).scaled(Vector3.ONE * AK47_MODEL_SCALE), offset)
	return part

func create_ak47_model(parent: Node3D, model_scale: float) -> Node3D:
	var model := AK47_SCENE.instantiate() as Node3D
	model.name = "AK47Model"
	model.scale = Vector3.ONE * model_scale
	var rifle_mesh := find_mesh_instance(model)
	prepare_ak47_parts(rifle_mesh)
	rifle_mesh.mesh = ak47_body_mesh
	parent.add_child(model)
	return model

func create_magazine_pivot(parent: Node3D, model_scale: float) -> Node3D:
	# The pivot sits on the magazine's front lug, so a fresh magazine can be rocked
	# into the well the way it is on a real AK.
	var ratio := model_scale / AK47_MODEL_SCALE
	var pivot := Node3D.new()
	pivot.name = "MagazinePivot"
	pivot.position = AK47_MAGAZINE_LUG * ratio
	pivot.scale = Vector3.ONE * ratio
	pivot.add_child(magazine_mesh_instance(-AK47_MAGAZINE_LUG))
	parent.add_child(pivot)
	return pivot

func create_view_weapons() -> void:
	# Each first-person weapon is a child of the camera and cannot drift in world space.
	ak47 = create_weapon_root("AK47")
	# Keep the rifle close to the body so the stock/barrel are clipped by the camera.
	create_ak47_model(ak47, AK47_MODEL_SCALE)
	fp_magazine_pivot = create_magazine_pivot(ak47, AK47_MODEL_SCALE)
	fp_muzzle = Marker3D.new()
	fp_muzzle.name = "Muzzle"
	fp_muzzle.position = AK47_MUZZLE
	ak47.add_child(fp_muzzle)

	sniper = create_weapon_root("Sniper")
	var sniper_model := SNIPER_SCENE.instantiate() as Node3D
	sniper_model.name = "SniperModel"
	sniper_model.scale = Vector3.ONE * .86
	# The imported mesh faces away from the first-person weapon convention, so turn
	# it around: the stock stays by the shooter and the folded bipod remains intact.
	sniper_model.rotation_degrees = Vector3(0, 180, 0)
	sniper.add_child(sniper_model)

	knife = create_weapon_root("Knife")
	var knife_model := KNIFE_SCENE.instantiate() as Node3D
	knife_model.name = "KnifeModel"
	knife_model.scale = Vector3.ONE * .85
	knife_model.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	knife.add_child(knife_model)
	frag_grenade = create_weapon_root("FragGrenade")
	frag_grenade.add_child(create_grenade_model(Weapon.FRAG))
	smoke_grenade = create_weapon_root("SmokeGrenade")
	smoke_grenade.add_child(create_grenade_model(Weapon.SMOKE))
	select_weapon(Weapon.AK47)

func create_grenade_model(grenade_type: Weapon) -> Node3D:
	# Sized like the real thing — a hand-sized can about 11 cm tall — so it reads the
	# same in the hand and in flight.
	var model := Node3D.new()
	model.name = "FragModel" if grenade_type == Weapon.FRAG else "SmokeModel"
	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .028
	cylinder.bottom_radius = .032
	cylinder.height = .088
	cylinder.radial_segments = 12
	body.mesh = cylinder
	body.material_override = material(Color("3d4a2b") if grenade_type == Weapon.FRAG else Color("26313a"))
	model.add_child(body)
	var cap := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = .032
	dome.height = .044
	dome.radial_segments = 12
	dome.rings = 6
	cap.mesh = dome
	cap.position.y = .044
	cap.material_override = material(Color("53613a") if grenade_type == Weapon.FRAG else Color("3b4852"))
	model.add_child(cap)
	var ring := MeshInstance3D.new()
	var pin := TorusMesh.new()
	pin.inner_radius = .011
	pin.outer_radius = .016
	pin.rings = 8
	pin.ring_segments = 6
	ring.mesh = pin
	ring.position = Vector3(.026, .052, 0)
	ring.rotation_degrees = Vector3(0, 0, 90)
	ring.material_override = material(Color("b7a05d"))
	model.add_child(ring)
	return model

func create_first_person_arms() -> void:
	# The rig hangs off the camera, so the shoulders keep a fixed place under the eyes
	# and only the arms move; ARMS_ANCHOR puts them roughly where a shouldered rifle
	# stance holds them.
	var arms := FIRST_PERSON_ARMS.new()
	arms.name = "FirstPersonArms"
	arms.model_scene = FIRST_PERSON_ARMS_MODEL
	arms.position = ARMS_ANCHOR
	arms.scale = Vector3.ONE * ARMS_SCALE
	arms.rotation_degrees = Vector3(0, ARMS_BLADE, 0)
	$CameraBoom/Camera.add_child(arms)
	first_person_arms = arms

func create_scope_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ScopeLayer"
	layer.layer = 20
	add_child(layer)
	scope_overlay = ScopeOverlay.new()
	scope_overlay.name = "ScopeOverlay"
	scope_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(scope_overlay)

func create_audio_players() -> void:
	shot_player = AudioStreamPlayer3D.new()
	shot_player.name = "RifleShotAudio"
	shot_player.stream = RIFLE_SHOT_SOUND
	shot_player.volume_db = -2.0
	shot_player.max_distance = 32.0
	add_child(shot_player)
	shell_player_a = AudioStreamPlayer3D.new()
	shell_player_a.name = "ShellAudioA"
	shell_player_a.stream = SHELL_SOUND_A
	shell_player_a.volume_db = -5.0
	shell_player_a.max_distance = 16.0
	add_child(shell_player_a)
	shell_player_b = AudioStreamPlayer3D.new()
	shell_player_b.name = "ShellAudioB"
	shell_player_b.stream = SHELL_SOUND_B
	shell_player_b.volume_db = -5.0
	shell_player_b.max_distance = 16.0
	add_child(shell_player_b)
	reload_player = AudioStreamPlayer3D.new()
	reload_player.name = "ReloadAudio"
	reload_player.stream = RELOAD_SOUND
	reload_player.volume_db = -2.0
	reload_player.max_distance = 24.0
	add_child(reload_player)
	knife_hit_player = AudioStreamPlayer3D.new()
	knife_hit_player.name = "KnifeHitAudio"
	knife_hit_player.stream = KNIFE_HIT_SOUND
	knife_hit_player.volume_db = -1.0
	knife_hit_player.max_distance = 20.0
	add_child(knife_hit_player)
	footstep_player = AudioStreamPlayer3D.new()
	footstep_player.name = "FootstepAudio"
	footstep_player.stream = FOOTSTEP_SOUND
	footstep_player.volume_db = -6.0
	footstep_player.max_distance = 24.0
	add_child(footstep_player)
	jump_player = AudioStreamPlayer3D.new()
	jump_player.name = "JumpAudio"
	jump_player.stream = JUMP_SOUND
	jump_player.volume_db = -2.0
	jump_player.max_distance = 24.0
	add_child(jump_player)

func set_weapon_visible(weapon: Node3D, should_show: bool) -> void:
	weapon.visible = should_show

func weapon_rest_position() -> Vector3:
	match active_weapon:
		Weapon.AK47: return Vector3(.103, -.273, -.465)
		Weapon.SNIPER: return Vector3(.20, -.32, -.62)
		Weapon.KNIFE: return Vector3(.52, -.22, -.75)
		Weapon.FRAG: return Vector3(.26, -.22, -.40)
		Weapon.SMOKE: return Vector3(.26, -.22, -.40)
	return Vector3.ZERO

func weapon_rest_rotation() -> Vector3:
	match active_weapon:
		Weapon.AK47: return Vector3(deg_to_rad(-2.0), deg_to_rad(8.0), 0.0)
		Weapon.SNIPER: return Vector3(deg_to_rad(-3.0), deg_to_rad(-2.0), 0.0)
		Weapon.KNIFE: return Vector3(deg_to_rad(-6.0), deg_to_rad(0.0), deg_to_rad(-12.0))
		Weapon.FRAG: return Vector3(deg_to_rad(-10.0), deg_to_rad(12.0), deg_to_rad(-8.0))
		Weapon.SMOKE: return Vector3(deg_to_rad(-10.0), deg_to_rad(12.0), deg_to_rad(-8.0))
	return Vector3.ZERO

func select_weapon(new_weapon: Weapon) -> void:
	active_weapon = new_weapon
	view_weapon = [ak47, sniper, knife, frag_grenade, smoke_grenade][active_weapon]
	refresh_weapon_view()
	view_weapon.position = weapon_rest_position()
	view_weapon.rotation = weapon_rest_rotation()
	recoil_amount = 0.0
	is_reloading = false
	reset_ak47_pose()
	update_ammo_hud()

func reset_ak47_pose() -> void:
	# Put the magazine and the support hand back where they belong after a reload is
	# finished or interrupted by a weapon switch.
	if magazine_pivot:
		magazine_pivot.position = AK47_MAGAZINE_LUG
		magazine_pivot.rotation = Vector3.ZERO
		magazine_pivot.visible = true
	support_hold = AK47_HANDGUARD_HOLD

func create_ammo_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	ammo_label = Label.new()
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -680.0
	ammo_label.offset_top = -108.0
	ammo_label.offset_right = -36.0
	ammo_label.offset_bottom = -62.0
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.add_theme_font_size_override("font_size", 22)
	ammo_label.add_theme_color_override("font_color", Color("f5a623"))
	hud.add_child(ammo_label)
	health_label = Label.new()
	health_label.position = Vector2(24, 24)
	health_label.add_theme_font_size_override("font_size", 24)
	health_label.add_theme_color_override("font_color", Color("8ee6a0"))
	hud.add_child(health_label)
	update_health_hud()
	update_ammo_hud()

func update_health_hud() -> void:
	if health_label: health_label.text = "HP %d" % health

@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int) -> void:
	if !is_multiplayer_authority(): return
	health = maxi(0, health - amount)
	update_health_hud()
	if health == 0:
		health = 100
		global_position = Vector3(0, .1, 0)
		velocity = Vector3.ZERO
		update_health_hud()

func update_ammo_hud() -> void:
	if !ammo_label: return
	if active_weapon == Weapon.KNIFE:
		ammo_label.hide()
		return
	ammo_label.show()
	if active_weapon == Weapon.FRAG:
		ammo_label.text = "ГРАНАТА  %d    ЛКМ — бросок" % frag_ammo
	elif active_weapon == Weapon.SMOKE:
		ammo_label.text = "ДЫМОВАЯ  %d    ЛКМ — бросок" % smoke_ammo
	elif is_reloading:
		ammo_label.text = ("АК-47" if active_weapon == Weapon.AK47 else "СНАЙПЕРКА") + "  ПЕРЕЗАРЯДКА…"
	elif active_weapon == Weapon.SNIPER:
		ammo_label.text = "СНАЙПЕРКА  %02d / %02d    R — перезарядка" % [sniper_ammo, sniper_reserve_ammo]
	else:
		ammo_label.text = "АК-47  %02d / %02d    R — перезарядка" % [ak47_ammo, reserve_ammo]

func start_reload() -> void:
	if is_reloading or active_weapon == Weapon.KNIFE or is_grenade(active_weapon):
		return
	if active_weapon == Weapon.AK47 and (ak47_ammo == AK47_MAGAZINE_SIZE or reserve_ammo == 0): return
	if active_weapon == Weapon.SNIPER and (sniper_ammo == SNIPER_MAGAZINE_SIZE or sniper_reserve_ammo == 0): return
	is_reloading = true
	reload_timer = AK47_RELOAD_TIME if active_weapon == Weapon.AK47 else SNIPER_RELOAD_TIME
	if multiplayer.has_multiplayer_peer(): play_reload.rpc()
	else: play_reload()
	update_ammo_hud()

func try_fire() -> void:
	if fire_cooldown > 0.0 or is_reloading: return
	if active_weapon == Weapon.AK47:
		if ak47_ammo == 0:
			start_reload()
			return
		ak47_ammo -= 1
		fire_cooldown = AK47_FIRE_INTERVAL
	elif is_grenade(active_weapon):
		throw_grenade()
		return
	elif active_weapon == Weapon.SNIPER:
		if sniper_ammo == 0:
			start_reload()
			return
		sniper_ammo -= 1
		fire_cooldown = 1.15
	else:
		play_recoil()
		fire_cooldown = KNIFE_SWING_INTERVAL
		if multiplayer.has_multiplayer_peer(): play_knife_hit.rpc()
		else: play_knife_hit()
		return
	play_recoil()
	var camera := $CameraBoom/Camera
	var direction: Vector3 = -camera.global_transform.basis.z
	if active_weapon == Weapon.AK47:
		# Apply spread around the reticle before sending the shot so the server and
		# every peer resolve and display the same bullet trajectory.
		var spread := deg_to_rad(AK47_SPREAD_DEGREES)
		direction = (direction
			+ camera.global_transform.basis.x * randf_range(-spread, spread)
			+ camera.global_transform.basis.y * randf_range(-spread, spread)).normalized()
	# The muzzle effect stays on the barrel mouth while the projectile direction may
	# deviate slightly from the reticle when using the automatic rifle.
	var origin: Vector3 = camera.global_position + direction * .25
	var flash_origin: Vector3 = origin + camera.global_transform.basis.x * .26 - camera.global_transform.basis.y * .12
	if active_weapon == Weapon.AK47 and muzzle: flash_origin = muzzle.global_position
	var shooter_id := multiplayer.get_unique_id()
	if multiplayer.has_multiplayer_peer(): fire.rpc(origin, direction, flash_origin, active_weapon, shooter_id)
	else: fire(origin, direction, flash_origin, active_weapon, shooter_id)
	update_ammo_hud()

func is_grenade(weapon: Weapon) -> bool:
	return weapon == Weapon.FRAG or weapon == Weapon.SMOKE

func grenades_left(weapon: Weapon) -> int:
	return frag_ammo if weapon == Weapon.FRAG else smoke_ammo

func throw_grenade() -> void:
	if grenades_left(active_weapon) == 0: return
	if active_weapon == Weapon.FRAG: frag_ammo -= 1
	else: smoke_ammo -= 1
	# The hand is empty from this moment on, whatever the belt still carries.
	refresh_weapon_view()
	fire_cooldown = GRENADE_THROW_INTERVAL
	# The view model swings through the throw on the same counter the recoil uses.
	recoil_amount = 1.0
	var camera := $CameraBoom/Camera
	# It leaves the hand just in front of the face and carries the player's own run
	# with it, so a grenade thrown on the move does not drop straight down.
	var origin: Vector3 = camera.global_position - camera.global_transform.basis.z * .45
	var launch: Vector3 = (-camera.global_transform.basis.z * GRENADE_THROW_SPEED
		+ Vector3.UP * GRENADE_THROW_LIFT + Vector3(velocity.x, 0, velocity.z))
	if multiplayer.has_multiplayer_peer(): launch_grenade.rpc(origin, launch, active_weapon)
	else: launch_grenade(origin, launch, active_weapon)
	update_ammo_hud()

@rpc("any_peer", "call_local", "reliable")
func launch_grenade(origin: Vector3, launch: Vector3, grenade_type: Weapon) -> void:
	# The throw travels over the network once; from there every peer simulates the
	# same flight, so the grenade lies in the same place on every screen.
	var grenade := GrenadeProjectile.new()
	grenade.name = "Grenade"
	grenade.velocity = launch
	grenade.grenade_type = grenade_type
	grenade.fuse = GRENADE_FUSE
	grenade.owner_player = self
	grenade.add_child(create_grenade_model(grenade_type))
	var level := get_tree().current_scene
	level.add_child(grenade)
	grenade.global_position = origin

func detonate_grenade(at: Vector3, grenade_type: int) -> void:
	# Called by each peer's own copy of the grenade, so the blast is seen everywhere;
	# only the server turns it into damage.
	var level := get_tree().current_scene
	if level.has_method("show_explosion"): level.show_explosion(at, grenade_type == Weapon.SMOKE)
	if grenade_type == Weapon.SMOKE: return
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server(): return
	if level.has_method("resolve_explosion"):
		level.resolve_explosion(at, GRENADE_BLAST_RADIUS, GRENADE_BLAST_DAMAGE)

func play_recoil() -> void:
	# The knife attacks with a swing; firearms recoil only backwards in camera space.
	recoil_amount = 1.0
	if active_weapon == Weapon.KNIFE: return
	# Firearms also punch the view: the muzzle climbs and drifts a little sideways.
	var climb := .75 if active_weapon == Weapon.AK47 else 1.9
	camera_kick.x = minf(camera_kick.x + climb, 2.8)
	camera_kick.y = clampf(camera_kick.y + randf_range(-.42, .42), -1.3, 1.3)

func update_camera_kick(delta: float) -> void:
	camera_kick = camera_kick.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	# The punch rides on the camera itself, so the reticle and the hitscan stay aligned.
	$CameraBoom/Camera.rotation = Vector3(deg_to_rad(camera_kick.x), deg_to_rad(camera_kick.y), 0.0)

func create_character() -> void:
	# Everyone gets the rigged soldier: remote players always see it, the owner sees
	# it in third person.
	character = CHARACTER.new()
	character.name = "Soldier"
	add_child(character)
	create_world_weapon()

func create_world_weapon() -> void:
	# The soldier carries the same rifle model, bolted to its right hand bone.
	if character == null or character.rifle_mount == null: return
	var weapon := Node3D.new()
	weapon.name = "WorldWeapon"
	var mount_scale: float = character.rifle_local_scale() / AK47_MODEL_SCALE
	# The mount inherits the posed hand, so undo that rotation before aiming the bore
	# down the soldier's line of sight.
	# character.gd aims the wrist so the hand bone already carries the rifle's own
	# orientation; the weapon only has to hang its grip in the palm.
	weapon.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * mount_scale),
		HOLD_PALM - AK47_GRIP * mount_scale)
	character.support_offset = (AK47_HANDGUARD_HOLD - AK47_GRIP) * mount_scale
	character.rifle_mount.add_child(weapon)
	create_ak47_model(weapon, AK47_MODEL_SCALE).name = "AK47WorldModel"
	world_magazine_pivot = create_magazine_pivot(weapon, AK47_MODEL_SCALE)
	# The world rifle carries its own barrel marker so muzzle effects hang off the
	# weapon the viewer is actually looking at.
	world_muzzle = Marker3D.new()
	world_muzzle.name = "Muzzle"
	world_muzzle.position = AK47_MUZZLE
	weapon.add_child(world_muzzle)


func refresh_weapon_view() -> void:
	# Only one rifle is on screen at a time: the view model in first person, the one
	# in the soldier's hands otherwise.
	var world_view := third_person or !is_multiplayer_authority()
	if character: character.visible = world_view
	# The arms are posed onto the AK and onto a carried grenade; the sniper and the
	# knife are still held by an empty screen, so those keep showing no hands.
	if first_person_arms:
		first_person_arms.visible = !world_view and (active_weapon == Weapon.AK47
			or (is_grenade(active_weapon) and grenades_left(active_weapon) > 0))
	if ak47: set_weapon_visible(ak47, !world_view and active_weapon == Weapon.AK47)
	if sniper: set_weapon_visible(sniper, !world_view and active_weapon == Weapon.SNIPER)
	if knife: set_weapon_visible(knife, !world_view and active_weapon == Weapon.KNIFE)
	# An empty hand holds nothing: the grenade only shows while one is left on the belt.
	if frag_grenade: set_weapon_visible(frag_grenade, !world_view and active_weapon == Weapon.FRAG and frag_ammo > 0)
	if smoke_grenade: set_weapon_visible(smoke_grenade, !world_view and active_weapon == Weapon.SMOKE and smoke_ammo > 0)
	muzzle = world_muzzle if world_view else fp_muzzle
	magazine_pivot = world_magazine_pivot if world_view else fp_magazine_pivot

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.metallic = .2; return m

func _unhandled_input(event: InputEvent) -> void:
	if !is_multiplayer_authority(): return
	if event is InputEventKey and event.pressed and !event.echo:
		if event.keycode == KEY_1: select_weapon(Weapon.AK47)
		if event.keycode == KEY_2: select_weapon(Weapon.SNIPER)
		if event.keycode == KEY_3: select_weapon(Weapon.KNIFE)
		if event.keycode == KEY_4: select_weapon(Weapon.FRAG)
		if event.keycode == KEY_5: select_weapon(Weapon.SMOKE)
		if event.keycode == KEY_R: start_reload()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * .0025; pitch = clamp(pitch - event.relative.y * .0025, -1.2, 1.2)
		rotation.y = yaw; $CameraBoom.rotation.x = pitch
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_V:
		third_person = !third_person
		$CameraBoom.spring_length = THIRD_PERSON_DISTANCE if third_person else 0.0
		refresh_weapon_view()
	if event.is_action_pressed("fire"):
		try_fire()

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority(): return
	var climb_axis := Input.get_axis("move_back", "move_forward")
	# Climbing is deliberate: E prevents the player from being pulled onto a ladder while walking past it.
	if is_near_ladder() and Input.is_key_pressed(KEY_E) and abs(climb_axis) > 0.01: climbing = true
	if climbing:
		climb_ladder(climb_axis, delta)
		if multiplayer.has_multiplayer_peer(): sync_state.rpc(global_position, rotation.y, $CameraBoom.rotation.x, is_crouching)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var airborne_before_move := !is_on_floor()
	var crouching := Input.is_key_pressed(KEY_CTRL) and is_on_floor()
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED)
	velocity.x = direction.x * speed; velocity.z = direction.z * speed
	if !is_on_floor(): velocity.y -= GRAVITY * delta
	elif Input.is_key_pressed(KEY_SPACE): velocity.y = JUMP_VELOCITY
	else: velocity.y = -0.1
	update_stance(crouching, delta)
	move_and_slide()
	if airborne_before_move and is_on_floor():
		if multiplayer.has_multiplayer_peer(): play_jump.rpc()
		else: play_jump()
	if multiplayer.has_multiplayer_peer(): sync_state.rpc(global_position, rotation.y, $CameraBoom.rotation.x, is_crouching)

func is_near_ladder() -> bool:
	for ladder in LADDER_POSITIONS:
		if global_position.y < ladder.y - .1 or global_position.y > ladder.y + LADDER_TOP + .2: continue
		if abs(global_position.z - ladder.z) >= .8: continue
		# Mount from the east side; each staircase has its own upper landing.
		if global_position.y > ladder.y + 3.0:
			if abs(global_position.x - (ladder.x + 1.7)) < .9:
				active_ladder = ladder
				return true
		else:
			var approach_offset: float = global_position.x - ladder.x
			if approach_offset > LADDER_APPROACH_CLEARANCE and approach_offset < LADDER_APPROACH_REACH:
				active_ladder = ladder
				return true
	return false

func climb_ladder(axis: float, delta: float) -> void:
	# Snap gently onto the rails, then W climbs upward and S descends.
	# Keep the capsule inside the hatch opening instead of directly under its rim.
	global_position.x = move_toward(global_position.x, active_ladder.x + .4, delta * 4.0)
	global_position.z = move_toward(global_position.z, active_ladder.z, delta * 4.0)
	velocity = Vector3(0, axis * LADDER_CLIMB_SPEED, 0)
	move_and_slide()
	if axis > 0.0 and global_position.y >= active_ladder.y + LADDER_TOP:
		# Step out onto the solid east roof panel, away from the hatch rim.
		global_position = Vector3(active_ladder.x + 1.7, active_ladder.y + 3.58, active_ladder.z)
		velocity = Vector3.ZERO
		climbing = false
	elif global_position.y <= active_ladder.y + .05 and axis < 0.0:
		global_position.y = active_ladder.y + .05
		climbing = false

func update_stance(crouching: bool, delta: float) -> void:
	var target_height := CROUCHING_HEIGHT if crouching else STANDING_HEIGHT
	var height := move_toward($Collider.shape.height, target_height, delta * 6.0)
	$Collider.shape.height = height
	$Collider.position.y = height * .5
	is_crouching = crouching
	$CameraBoom.position.y = lerp(1.5, 1.0, (STANDING_HEIGHT - height) / (STANDING_HEIGHT - CROUCHING_HEIGHT))

func finish_reload() -> void:
	if active_weapon == Weapon.AK47:
		var loaded := mini(AK47_MAGAZINE_SIZE - ak47_ammo, reserve_ammo)
		ak47_ammo += loaded
		reserve_ammo -= loaded
	else:
		var loaded := mini(SNIPER_MAGAZINE_SIZE - sniper_ammo, sniper_reserve_ammo)
		sniper_ammo += loaded
		sniper_reserve_ammo -= loaded
	is_reloading = false
	reset_ak47_pose()
	update_ammo_hud()

func pose_ak47_reload(progress: float) -> void:
	# Rock the rifle out of the shoulder, drop the spent magazine, let the support hand
	# fetch a fresh one from the belt, rock it into the well and come back on target.
	var settle := smoothstep(0.0, RELOAD_EJECT_AT, progress) - smoothstep(RELOAD_SEAT_AT, 1.0, progress)
	var lift := smoothstep(RELOAD_FETCH_AT, RELOAD_SEAT_AT - .09, progress)
	var lock := smoothstep(RELOAD_SEAT_AT - .09, RELOAD_SEAT_AT, progress)
	view_weapon.position = weapon_rest_position() + Vector3(-.10, .09, .04) * settle
	view_weapon.rotation = weapon_rest_rotation() + Vector3(deg_to_rad(7.0), deg_to_rad(13.0), deg_to_rad(-26.0)) * settle
	var fetch_offset := Vector3(-.05, -.30, .11)
	var magazine_grip := AK47_MAGAZINE_LUG + Vector3(-.035, -.105, .015)
	if progress < RELOAD_EJECT_AT:
		support_hold = AK47_HANDGUARD_HOLD.lerp(AK47_HANDGUARD_HOLD + fetch_offset, smoothstep(.05, RELOAD_EJECT_AT, progress))
	elif progress < RELOAD_FETCH_AT:
		support_hold = AK47_HANDGUARD_HOLD + fetch_offset
	elif progress < RELOAD_SEAT_AT:
		support_hold = (magazine_grip + fetch_offset).lerp(magazine_grip, lift)
	else:
		support_hold = magazine_grip.lerp(AK47_HANDGUARD_HOLD, smoothstep(RELOAD_SEAT_AT, 1.0, progress))
	magazine_pivot.visible = progress < RELOAD_EJECT_AT or progress >= RELOAD_FETCH_AT
	if progress < RELOAD_EJECT_AT:
		# The spent magazine stays locked in until the release is pressed.
		magazine_pivot.position = AK47_MAGAZINE_LUG
		magazine_pivot.rotation.x = 0.0
		return
	magazine_pivot.position = AK47_MAGAZINE_LUG + Vector3(-.015, -.24, -.03) * (1.0 - lift)
	magazine_pivot.rotation.x = deg_to_rad(-24.0) * (1.0 - lock)

func update_character(delta: float) -> void:
	if character == null: return
	var travelled := global_position - previous_position
	previous_position = global_position
	var speed := Vector2(travelled.x, travelled.z).length() / maxf(delta, .0001)
	# Respawns and network corrections teleport the body; they are not a sprint.
	if speed > SPRINT_SPEED * 2.0: speed = 0.0
	var grounded := is_on_floor() if is_multiplayer_authority() else absf(travelled.y) < .03
	if grounded and !climbing and speed > 0.5:
		step_distance += Vector2(travelled.x, travelled.z).length()
		var stride := 1.45 if is_crouching else (1.9 if speed > 6.2 else 2.1)
		if step_distance >= stride:
			step_distance = fmod(step_distance, stride)
			play_footstep()
	else:
		step_distance = 0.0
	character.ground_speed = lerpf(character.ground_speed, speed, clampf(delta * 9.0, 0.0, 1.0))
	character.sprinting = character.ground_speed > 6.2
	character.crouching = is_crouching
	character.airborne = !is_on_floor() if is_multiplayer_authority() else absf(travelled.y) > .03
	character.aim_pitch = $CameraBoom.rotation.x
	if reload_show_timer > 0.0:
		reload_show_timer = maxf(0.0, reload_show_timer - delta)
		character.reload_progress = 1.0 - reload_show_timer / AK47_RELOAD_TIME
	else:
		character.reload_progress = -1.0
	if melee_timer > 0.0:
		melee_timer = maxf(0.0, melee_timer - delta)
		character.melee_swing = sin(clampf(1.0 - melee_timer / (KNIFE_SWING_INTERVAL * .55), 0.0, 1.0) * PI)
	else:
		character.melee_swing = 0.0
	character.fire_kick = move_toward(character.fire_kick, 0.0, delta * 5.0)
	character.animate(delta)
	if first_person_arms and first_person_arms.visible:
		animate_first_person_arms(delta)

func animate_first_person_arms(delta: float) -> void:
	# Whatever is in the hands leads and the arms follow it: the rig is handed the
	# world positions its two hands have to end up at.
	first_person_arms.ground_speed = character.ground_speed
	first_person_arms.sprinting = character.sprinting
	first_person_arms.fire_kick = character.fire_kick
	first_person_arms.carrying = is_grenade(active_weapon)
	if first_person_arms.carrying:
		# One hand holds the grenade, the other hangs at the side out of frame.
		first_person_arms.grip_point = view_weapon.global_position
		first_person_arms.weapon_basis = view_weapon.global_transform.basis
		first_person_arms.support_point = $CameraBoom/Camera.to_global(FREE_HAND_REST)
	else:
		first_person_arms.grip_point = ak47.to_global(AK47_GRIP)
		first_person_arms.support_point = ak47.to_global(support_hold)
		first_person_arms.weapon_basis = ak47.global_transform.basis
	first_person_arms.animate(delta)

func _process(delta: float) -> void:
	update_character(delta)
	if is_multiplayer_authority(): update_scope(delta)
	if !is_multiplayer_authority() or !view_weapon: return
	if fire_cooldown > 0.0:
		fire_cooldown = maxf(0.0, fire_cooldown - delta)
	update_camera_kick(delta)
	if is_reloading:
		var previous_timer := reload_timer
		reload_timer -= delta
		if active_weapon == Weapon.AK47:
			var previous_progress := 1.0 - previous_timer / AK47_RELOAD_TIME
			var progress := minf(1.0 - reload_timer / AK47_RELOAD_TIME, 1.0)
			if previous_progress < RELOAD_EJECT_AT and progress >= RELOAD_EJECT_AT:
				if multiplayer.has_multiplayer_peer(): eject_magazine.rpc()
				else: eject_magazine()
			pose_ak47_reload(progress)
		if reload_timer <= 0.0:
			finish_reload()
	elif active_weapon == Weapon.AK47 and Input.is_action_pressed("fire"):
		try_fire()
	# A frame-driven recoil works even when the player fires again mid-animation.
	recoil_amount = move_toward(recoil_amount, 0.0, delta * 4.0)
	if is_reloading and active_weapon == Weapon.AK47: return
	var rest_position := weapon_rest_position()
	var rest_rotation := weapon_rest_rotation()
	if active_weapon == Weapon.KNIFE:
		view_weapon.position = rest_position + Vector3(0, -.12, -.36) * recoil_amount
		view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(-96.0), deg_to_rad(8.0), deg_to_rad(18.0)) * recoil_amount
		return
	if is_grenade(active_weapon):
		# The arm winds up over the shoulder and comes back empty; once the last one is
		# gone the rifle comes back up on its own.
		view_weapon.position = rest_position + Vector3(-.10, .16, .26) * recoil_amount
		view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(-70.0), 0.0, deg_to_rad(18.0)) * recoil_amount
		if fire_cooldown == 0.0 and grenades_left(active_weapon) == 0: select_weapon(Weapon.AK47)
		return
	var kick := .28 if active_weapon == Weapon.AK47 else .48
	view_weapon.position = rest_position + Vector3(0, 0, kick) * recoil_amount
	view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(8.0), 0, 0) * recoil_amount

func update_scope(delta: float) -> void:
	var should_aim := active_weapon == Weapon.SNIPER and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and !third_person and !is_reloading
	aiming = should_aim
	var target_fov := 37.5 if aiming else 75.0
	$CameraBoom/Camera.fov = lerpf($CameraBoom/Camera.fov, target_fov, clampf(delta * 12.0, 0.0, 1.0))
	if scope_overlay:
		scope_overlay.active = aiming
		scope_overlay.queue_redraw()

@rpc("any_peer", "call_local", "unreliable")
func play_jump() -> void:
	if jump_player: jump_player.play()

func play_footstep() -> void:
	if footstep_player: footstep_player.play()

@rpc("any_peer", "call_remote", "unreliable")
func sync_state(new_position: Vector3, new_yaw: float, new_pitch: float, crouched: bool) -> void:
	global_position = new_position; rotation.y = new_yaw; $CameraBoom.rotation.x = new_pitch
	is_crouching = crouched

@rpc("any_peer", "call_local", "unreliable")
func fire(origin: Vector3, direction: Vector3, flash_origin: Vector3, weapon: Weapon, shooter_id: int) -> void:
	# The server resolves the raycast and damage; every peer renders the same shot FX.
	if character: character.fire_kick = 1.0
	if weapon == Weapon.AK47 or weapon == Weapon.SNIPER:
		var shot_power := 1.5 if weapon == Weapon.SNIPER else 1.0
		play_rifle_shot_effect(Transform3D(Basis.looking_at(direction), flash_origin), shot_power)
	var main := get_tree().current_scene
	if main.has_method("resolve_projectile_hit") and (!multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		main.resolve_projectile_hit(origin, direction, shooter_id, weapon)
	var tracer_origin := muzzle.global_position if muzzle and weapon == Weapon.AK47 else flash_origin
	spawn_tracer(tracer_origin, visual_impact_point(origin, direction), weapon)

func visual_impact_point(origin: Vector3, direction: Vector3) -> Vector3:
	# Every peer traces the shot once on its own side purely to know where the tracer
	# has to stop, so rounds no longer fly on through the wall they just hit.
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + direction * 80.0
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit.has("position") else origin + direction * 80.0

func spawn_tracer(from: Vector3, to: Vector3, weapon: Weapon) -> void:
	# A bullet in flight is a velocity-stretched billboard: a quad kept aligned with
	# its own travel direction that only spins around that axis to face the camera.
	# Like real belts, only part of the rounds are bright tracers.
	var travel := to - from
	var distance := travel.length()
	if distance < .25: return
	var direction := travel / distance
	var tracer_round := weapon == Weapon.SNIPER or randf() < .34
	var length: float = (2.6 if weapon == Weapon.SNIPER else 1.7) * (1.0 if tracer_round else .45)
	var width: float = (.07 if weapon == Weapon.SNIPER else .05) * (1.0 if tracer_round else .55)
	var speed: float = 180.0 if weapon == Weapon.SNIPER else 90.0
	var tracer := MeshInstance3D.new()
	tracer.name = "Tracer"
	tracer.mesh = FX.streak_mesh(width, length)
	tracer.transparency = 0.0 if tracer_round else .45
	get_tree().current_scene.add_child(tracer)
	tracer.global_transform = Transform3D(FX.aim_basis(direction), from)
	var flight := maxf(distance / speed, .03)
	var tween := create_tween()
	tween.tween_property(tracer, "global_position", to - direction * length * .5, flight)
	tween.parallel().tween_property(tracer, "transparency", 1.0, flight).set_delay(flight * .55)
	tween.tween_callback(tracer.queue_free)

@rpc("any_peer", "call_local", "unreliable")
func play_reload() -> void:
	if reload_player: reload_player.play()
	reload_show_timer = AK47_RELOAD_TIME

@rpc("any_peer", "call_local", "unreliable")
func eject_magazine() -> void:
	# Every peer throws the spent magazine away from its own view of this rifle: the
	# owner from the first-person weapon, everyone else from the world weapon.
	if magazine_pivot == null: return
	var rifle_basis := magazine_pivot.global_transform.basis.orthonormalized()
	var magazine := FallingDebris.new()
	magazine.name = "DroppedMagazine"
	magazine.add_child(magazine_mesh_instance(-AK47_MAGAZINE_CENTER))
	get_tree().current_scene.add_child(magazine)
	magazine.global_transform = Transform3D(rifle_basis, magazine_pivot.global_position + rifle_basis * Vector3(0, -.06, .05))
	magazine.velocity = rifle_basis * Vector3(randf_range(-.5, -.1), -1.1, randf_range(.1, .5))
	magazine.spin = Vector3(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	magazine.floor_y = global_position.y + .03
	magazine.bounce = .22
	magazine.life = 7.0
	magazine_pivot.visible = false
	if is_multiplayer_authority(): return
	# Remote rifles have no reload animation, so give their magazine back on a timer.
	get_tree().create_timer(AK47_RELOAD_TIME * RELOAD_FETCH_AT).timeout.connect(restore_magazine)

func restore_magazine() -> void:
	if magazine_pivot: magazine_pivot.visible = true

@rpc("any_peer", "call_local", "unreliable")
func play_knife_hit() -> void:
	if knife_hit_player: knife_hit_player.play()
	melee_timer = KNIFE_SWING_INTERVAL * .55

func play_rifle_shot_effect(flash_transform: Transform3D, power := 1.0) -> void:
	if shot_player:
		shot_player.volume_db = -2.0 + (20.0 * log(power) / log(10.0))
		shot_player.play()
	spawn_muzzle_flash(flash_transform, power)
	spawn_muzzle_smoke(flash_transform)
	spawn_muzzle_sparks(flash_transform, power)
	spawn_shell_casing()

func attach_muzzle_effect(effect: Node3D, fallback: Transform3D, offset: Vector3) -> void:
	# Muzzle effects hang off the barrel itself. Spawned in world space they stayed
	# where the shot was fired, so strafing tore the flash away from the weapon.
	# `offset` is given in muzzle space, where -Z points down the bore.
	if muzzle:
		muzzle.add_child(effect)
		effect.position = offset
		return
	get_tree().current_scene.add_child(effect)
	effect.global_transform = Transform3D(fallback.basis, fallback.origin + fallback.basis * offset)

func spawn_muzzle_flash(flash_transform: Transform3D, power := 1.0) -> void:
	# Head-on pop: a two-particle star burst, each with its own roll and size.
	var star := CPUParticles3D.new()
	star.name = "MuzzleFlash"
	star.amount = 2
	star.lifetime = .075
	star.one_shot = true
	star.explosiveness = 1.0
	star.local_coords = true
	star.gravity = Vector3.ZERO
	star.initial_velocity_min = 0.0
	star.initial_velocity_max = 0.0
	star.angle_min = -180.0
	star.angle_max = 180.0
	star.scale_amount_min = .26 * power
	star.scale_amount_max = .46 * power
	star.scale_amount_curve = FX.fade_curve(1.0, .25)
	star.color_ramp = FX.alpha_ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	star.mesh = FX.star_mesh(1.0)
	attach_muzzle_effect(star, flash_transform, Vector3.ZERO)
	star.emitting = true
	star.finished.connect(star.queue_free)
	# Burning powder: tongues of flame that are stretched along their own travel,
	# so the muzzle throws real fire instead of a round glowing blob.
	var flame := CPUParticles3D.new()
	flame.name = "MuzzleFlame"
	flame.amount = maxi(4, roundi(4.0 * power))
	flame.lifetime = .09
	flame.one_shot = true
	flame.explosiveness = 1.0
	flame.local_coords = true
	flame.direction = Vector3.FORWARD
	flame.spread = 30.0
	flame.initial_velocity_min = 2.2
	flame.initial_velocity_max = 4.6
	flame.damping_min = 10.0
	flame.damping_max = 18.0
	flame.gravity = Vector3.ZERO
	flame.particle_flag_align_y = true
	flame.scale_amount_min = .7 * power
	flame.scale_amount_max = 1.35 * power
	flame.scale_amount_curve = FX.fade_curve(1.0, .3)
	flame.color_ramp = FX.alpha_ramp(Color(1, 1, 1, 1), Color(1, .78, .5, 0))
	flame.mesh = FX.flame_mesh(.09 * power, .20 * power)
	attach_muzzle_effect(flame, flash_transform, Vector3(0, 0, -.04))
	flame.emitting = true
	flame.finished.connect(flame.queue_free)
	# Two lights: a hot one that washes nearby geometry and a wider one down the barrel,
	# so the flash visibly bounces off the walls of the room.
	var light := OmniLight3D.new()
	light.name = "MuzzleLight"
	light.light_color = Color("ffc275")
	light.light_energy = 0.0
	light.light_specular = 1.6
	light.omni_range = 5.6
	light.omni_attenuation = 1.1
	attach_muzzle_effect(light, flash_transform, Vector3(0, 0, -.1))
	var bounce := OmniLight3D.new()
	bounce.name = "MuzzleBounceLight"
	bounce.light_color = Color("ffd9a8")
	bounce.light_energy = 0.0
	bounce.omni_range = 10.0
	bounce.omni_attenuation = .85
	attach_muzzle_effect(bounce, flash_transform, Vector3(0, 0, -2.4))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(light, "light_energy", 5.5, .012)
	tween.tween_property(bounce, "light_energy", 2.4, .012)
	tween.chain().tween_property(light, "light_energy", 0.0, .085).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.parallel().tween_property(bounce, "light_energy", 0.0, .085).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween.chain().tween_callback(light.queue_free)
	tween.parallel().tween_callback(bounce.queue_free)

func spawn_muzzle_smoke(flash_transform: Transform3D) -> void:
	# Hot gas first: a thin jet that shoots out of the barrel and stalls immediately.
	var jet := CPUParticles3D.new()
	jet.name = "RifleSmokeJet"
	jet.amount = 9
	jet.lifetime = .8
	jet.one_shot = true
	jet.explosiveness = .85
	jet.direction = Vector3.FORWARD
	jet.spread = 16.0
	jet.initial_velocity_min = 1.1
	jet.initial_velocity_max = 2.6
	jet.damping_min = 3.0
	jet.damping_max = 4.5
	jet.gravity = Vector3(0, .35, 0)
	jet.angle_min = -180.0
	jet.angle_max = 180.0
	jet.angular_velocity_min = -25.0
	jet.angular_velocity_max = 25.0
	jet.scale_amount_min = .05
	jet.scale_amount_max = .10
	jet.scale_amount_curve = FX.fade_curve(1.0, 3.4)
	jet.color_ramp = FX.alpha_ramp(Color(.72, .74, .78, .30), Color(.46, .48, .52, 0))
	jet.mesh = FX.smoke_mesh(1.0)
	attach_muzzle_effect(jet, flash_transform, Vector3(0, 0, -.06))
	jet.emitting = true
	jet.finished.connect(jet.queue_free)
	# Then the slow cloud that hangs in front of the shooter and drifts upwards.
	var cloud := CPUParticles3D.new()
	cloud.name = "RifleSmokeCloud"
	cloud.amount = 5
	cloud.lifetime = 1.8
	cloud.one_shot = true
	cloud.explosiveness = .6
	cloud.direction = Vector3.FORWARD
	cloud.spread = 55.0
	cloud.initial_velocity_min = .1
	cloud.initial_velocity_max = .45
	cloud.damping_min = .4
	cloud.damping_max = .9
	cloud.gravity = Vector3(0, .30, 0)
	cloud.angle_min = -180.0
	cloud.angle_max = 180.0
	cloud.angular_velocity_min = -14.0
	cloud.angular_velocity_max = 14.0
	cloud.scale_amount_min = .12
	cloud.scale_amount_max = .22
	cloud.scale_amount_curve = FX.fade_curve(.7, 2.6)
	cloud.color_ramp = FX.alpha_ramp(Color(.60, .62, .66, .18), Color(.40, .42, .46, 0))
	cloud.mesh = FX.smoke_mesh(1.0)
	attach_muzzle_effect(cloud, flash_transform, Vector3(0, 0, -.18))
	cloud.emitting = true
	cloud.finished.connect(cloud.queue_free)

func spawn_muzzle_sparks(flash_transform: Transform3D, power := 1.0) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "MuzzleSparks"
	sparks.amount = maxi(7, roundi(7.0 * power))
	sparks.lifetime = .26
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.FORWARD
	sparks.spread = 22.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 7.5
	sparks.damping_min = 2.0
	sparks.damping_max = 5.0
	sparks.gravity = Vector3(0, -9.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = .5 * power
	sparks.scale_amount_max = 1.1 * power
	sparks.scale_amount_curve = FX.fade_curve(1.0, .2)
	sparks.color_ramp = FX.alpha_ramp(Color("fff0c2"), Color(1, .42, .06, 0))
	sparks.mesh = FX.streak_mesh(.009, .12)
	attach_muzzle_effect(sparks, flash_transform, Vector3.ZERO)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)

func spawn_shell_casing() -> void:
	var shell := FallingDebris.new()
	shell.name = "ShellCasing"
	var casing := MeshInstance3D.new()
	var mesh := CylinderMesh.new(); mesh.top_radius = .0105; mesh.bottom_radius = .012; mesh.height = .048; mesh.radial_segments = 10; mesh.rings = 1
	casing.mesh = mesh; casing.material_override = material(Color("d49a38"))
	casing.rotation_degrees = Vector3(0, 0, 78.0)
	shell.add_child(casing)
	var ejection_side := global_transform.basis.x
	var forward := -global_transform.basis.z
	get_tree().current_scene.add_child(shell)
	shell.global_position = global_position + ejection_side * .26 + Vector3.UP * 1.2 + forward * .22
	shell.velocity = ejection_side * randf_range(1.7, 2.5) + Vector3.UP * randf_range(1.3, 2.0) + forward * randf_range(-.4, .1)
	shell.spin = Vector3(randf_range(-18.0, 18.0), randf_range(-12.0, 12.0), randf_range(-18.0, 18.0))
	shell.floor_y = global_position.y + .012
	shell.bounce = .38
	shell.life = 3.2
	if randi() % 2 == 0:
		shell_player_a.play()
	else:
		shell_player_b.play()
