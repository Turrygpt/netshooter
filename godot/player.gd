extends CharacterBody3D

const SPEED := 5.5
const SPRINT_SPEED := 8.5
const CROUCH_SPEED := 2.8
const GRAVITY := 18.0
const JUMP_VELOCITY := 6.5
const STANDING_HEIGHT := 1.8
const CROUCHING_HEIGHT := 1.25
const THIRD_PERSON_DISTANCE := 3.5
const LADDER_POSITION := Vector3(-1.15, 0, 8)
const LADDER_CLIMB_POSITION_X := -0.75
const LADDER_CLIMB_SPEED := 2.7
const LADDER_TOP := 3.42
const LADDER_APPROACH_CLEARANCE := 0.15
const LADDER_APPROACH_REACH := 1.05
const AK47_MAGAZINE_SIZE := 30
const AK47_FIRE_INTERVAL := .095
const AK47_RELOAD_TIME := 1.7
const SNIPER_MAGAZINE_SIZE := 5
const SNIPER_RELOAD_TIME := 2.3
const CROWBAR_SWING_INTERVAL := 1.1
enum Weapon { AK47, SNIPER, CROWBAR }
var pitch := 0.0
var yaw := 0.0
var fire_cooldown := 0.0
var third_person := false
var climbing := false
var active_weapon := Weapon.AK47
var view_weapon: Node3D
var ak47: Node3D
var sniper: Node3D
var crowbar: Node3D
var recoil_amount := 0.0
var ak47_ammo := AK47_MAGAZINE_SIZE
var reserve_ammo := 90
var sniper_ammo := SNIPER_MAGAZINE_SIZE
var sniper_reserve_ammo := 20
var is_reloading := false
var reload_timer := 0.0
var ammo_label: Label

func _ready() -> void:
	$Collider.shape = CapsuleShape3D.new()
	$Collider.shape.radius = .35
	$Collider.shape.height = STANDING_HEIGHT
	$Body.mesh = CapsuleMesh.new()
	$Body.mesh.radius = .34
	$Body.mesh.height = 1.35
	$Body.material_override = material(Color("36a6ff") if is_multiplayer_authority() else Color("ef6060"))
	if is_multiplayer_authority():
		create_view_weapons()
		create_ammo_hud()
		$CameraBoom/Camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		create_world_weapon()

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

func create_view_weapons() -> void:
	# Each first-person weapon is a child of the camera and cannot drift in world space.
	ak47 = create_weapon_root("AK47")
	var dark := Color("161b20")
	var metal := Color("4d5a66")
	add_weapon_part(ak47, Vector3(.28, .19, .60), Vector3.ZERO, dark) # receiver
	add_weapon_part(ak47, Vector3(.11, .10, .60), Vector3(0, .02, -.58), metal) # barrel
	add_weapon_part(ak47, Vector3(.14, .33, .16), Vector3(0, -.21, .04), Color("29323a")) # magazine
	add_weapon_part(ak47, Vector3(.21, .12, .32), Vector3(0, -.03, .40), dark) # stock
	add_weapon_part(ak47, Vector3(.05, .05, .10), Vector3(0, .12, -.38), Color("d9e4ec")) # sight

	sniper = create_weapon_root("Sniper")
	add_weapon_part(sniper, Vector3(.22, .16, .74), Vector3.ZERO, dark) # body
	add_weapon_part(sniper, Vector3(.12, .12, .45), Vector3(0, -.02, .52), dark) # stock
	add_cylinder_part(sniper, .045, 1.20, Vector3(0, .01, -.82), metal) # long barrel
	add_cylinder_part(sniper, .075, .42, Vector3(0, .17, -.08), Color("111418")) # scope
	add_weapon_part(sniper, Vector3(.10, .28, .10), Vector3(0, -.20, .10), Color("29323a")) # grip

	crowbar = create_weapon_root("Crowbar")
	add_weapon_part(crowbar, Vector3(.07, .07, .82), Vector3(0, 0, -.06), Color("9a2d2d")) # shaft
	add_weapon_part(crowbar, Vector3(.09, .09, .25), Vector3(0, .08, -.50), metal) # hooked tip
	add_weapon_part(crowbar, Vector3(.09, .09, .20), Vector3(0, -.03, .42), metal) # handle
	select_weapon(Weapon.AK47)

func set_weapon_visible(weapon: Node3D, should_show: bool) -> void:
	for part in weapon.get_children():
		if part is MeshInstance3D:
			part.visible = should_show

func weapon_rest_position() -> Vector3:
	match active_weapon:
		Weapon.AK47: return Vector3(.38, -.30, -.72)
		Weapon.SNIPER: return Vector3(.34, -.26, -.92)
		Weapon.CROWBAR: return Vector3(.54, -.25, -.78)
	return Vector3.ZERO

func weapon_rest_rotation() -> Vector3:
	match active_weapon:
		Weapon.AK47: return Vector3(deg_to_rad(-4.0), deg_to_rad(-3.0), 0.0)
		Weapon.SNIPER: return Vector3(deg_to_rad(-3.0), deg_to_rad(-2.0), 0.0)
		Weapon.CROWBAR: return Vector3(deg_to_rad(82.0), deg_to_rad(0.0), deg_to_rad(-12.0))
	return Vector3.ZERO

func select_weapon(new_weapon: Weapon) -> void:
	active_weapon = new_weapon
	set_weapon_visible(ak47, active_weapon == Weapon.AK47)
	set_weapon_visible(sniper, active_weapon == Weapon.SNIPER)
	set_weapon_visible(crowbar, active_weapon == Weapon.CROWBAR)
	view_weapon = [ak47, sniper, crowbar][active_weapon]
	view_weapon.position = weapon_rest_position()
	view_weapon.rotation = weapon_rest_rotation()
	recoil_amount = 0.0
	is_reloading = false
	update_ammo_hud()

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
	update_ammo_hud()

func update_ammo_hud() -> void:
	if !ammo_label: return
	if active_weapon == Weapon.CROWBAR:
		ammo_label.hide()
		return
	ammo_label.show()
	if is_reloading:
		ammo_label.text = ("АК-47" if active_weapon == Weapon.AK47 else "СНАЙПЕРКА") + "  ПЕРЕЗАРЯДКА…"
	elif active_weapon == Weapon.SNIPER:
		ammo_label.text = "СНАЙПЕРКА  %02d / %02d    R — перезарядка" % [sniper_ammo, sniper_reserve_ammo]
	else:
		ammo_label.text = "АК-47  %02d / %02d    R — перезарядка" % [ak47_ammo, reserve_ammo]

func start_reload() -> void:
	if is_reloading or active_weapon == Weapon.CROWBAR:
		return
	if active_weapon == Weapon.AK47 and (ak47_ammo == AK47_MAGAZINE_SIZE or reserve_ammo == 0): return
	if active_weapon == Weapon.SNIPER and (sniper_ammo == SNIPER_MAGAZINE_SIZE or sniper_reserve_ammo == 0): return
	is_reloading = true
	reload_timer = AK47_RELOAD_TIME if active_weapon == Weapon.AK47 else SNIPER_RELOAD_TIME
	update_ammo_hud()

func try_fire() -> void:
	if fire_cooldown > 0.0 or is_reloading: return
	if active_weapon == Weapon.AK47:
		if ak47_ammo == 0:
			start_reload()
			return
		ak47_ammo -= 1
		fire_cooldown = AK47_FIRE_INTERVAL
	elif active_weapon == Weapon.SNIPER:
		if sniper_ammo == 0:
			start_reload()
			return
		sniper_ammo -= 1
		fire_cooldown = 1.15
	else:
		play_recoil()
		fire_cooldown = CROWBAR_SWING_INTERVAL
		return
	play_recoil()
	var direction: Vector3 = -$CameraBoom/Camera.global_transform.basis.z
	var origin: Vector3 = $CameraBoom/Camera.global_position + direction * .8
	if multiplayer.has_multiplayer_peer(): fire.rpc(origin, direction, active_weapon)
	else: fire(origin, direction, active_weapon)
	update_ammo_hud()

func play_recoil() -> void:
	# The crowbar attacks with a swing; firearms recoil only backwards in camera space.
	recoil_amount = 1.0

func create_world_weapon() -> void:
	# Other players still need a compact visible weapon in the shared world.
	var weapon := Node3D.new()
	weapon.name = "WorldWeapon"
	weapon.position = Vector3(.38, .72, -.18)
	weapon.rotation = Vector3(0.0, deg_to_rad(-8.0), 0.0)
	$Body.add_child(weapon)
	add_weapon_part(weapon, Vector3(.16, .12, .45), Vector3.ZERO, Color("161b20"))
	add_weapon_part(weapon, Vector3(.06, .06, .30), Vector3(0, .01, -.34), Color("4d5a66"))

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.metallic = .2; return m

func _unhandled_input(event: InputEvent) -> void:
	if !is_multiplayer_authority(): return
	if event is InputEventKey and event.pressed and !event.echo:
		if event.keycode == KEY_1: select_weapon(Weapon.AK47)
		if event.keycode == KEY_2: select_weapon(Weapon.SNIPER)
		if event.keycode == KEY_3: select_weapon(Weapon.CROWBAR)
		if event.keycode == KEY_R: start_reload()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * .0025; pitch = clamp(pitch - event.relative.y * .0025, -1.2, 1.2)
		rotation.y = yaw; $CameraBoom.rotation.x = pitch
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_V:
		third_person = !third_person
		$CameraBoom.spring_length = THIRD_PERSON_DISTANCE if third_person else 0.0
	if event.is_action_pressed("fire"):
		try_fire()

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority(): return
	var climb_axis := Input.get_axis("move_back", "move_forward")
	if is_near_ladder() and abs(climb_axis) > 0.01: climbing = true
	if climbing:
		climb_ladder(climb_axis, delta)
		if multiplayer.has_multiplayer_peer(): sync_state.rpc(global_position, rotation.y, $CameraBoom.rotation.x)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var crouching := Input.is_key_pressed(KEY_CTRL) and is_on_floor()
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED)
	velocity.x = direction.x * speed; velocity.z = direction.z * speed
	if !is_on_floor(): velocity.y -= GRAVITY * delta
	elif Input.is_key_pressed(KEY_SPACE): velocity.y = JUMP_VELOCITY
	else: velocity.y = -0.1
	update_stance(crouching, delta)
	move_and_slide()
	if multiplayer.has_multiplayer_peer(): sync_state.rpc(global_position, rotation.y, $CameraBoom.rotation.x)

func is_near_ladder() -> bool:
	if abs(global_position.z - LADDER_POSITION.z) >= .8 or global_position.y < -.1 or global_position.y > LADDER_TOP + .2:
		return false
	# Mount from the east side, facing the open part of the hatch. At roof level
	# the west landing remains available so the player can start descending.
	if global_position.y > 3.0:
		return abs(global_position.x + 1.7) < .9
	var approach_offset := global_position.x - LADDER_POSITION.x
	return approach_offset > LADDER_APPROACH_CLEARANCE and approach_offset < LADDER_APPROACH_REACH

func climb_ladder(axis: float, delta: float) -> void:
	# Snap gently onto the rails, then W climbs upward and S descends.
	# Keep the capsule inside the hatch opening instead of directly under its rim.
	global_position.x = move_toward(global_position.x, LADDER_CLIMB_POSITION_X, delta * 4.0)
	global_position.z = move_toward(global_position.z, LADDER_POSITION.z, delta * 4.0)
	velocity = Vector3(0, axis * LADDER_CLIMB_SPEED, 0)
	move_and_slide()
	if global_position.y >= LADDER_TOP:
		# Step out onto the solid roof panel beside the hatch.
		global_position = Vector3(-1.7, 3.55, LADDER_POSITION.z)
		velocity = Vector3.ZERO
		climbing = false
	elif global_position.y <= .05 and axis < 0.0:
		global_position.y = .05
		climbing = false

func update_stance(crouching: bool, delta: float) -> void:
	var target_height := CROUCHING_HEIGHT if crouching else STANDING_HEIGHT
	var height := move_toward($Collider.shape.height, target_height, delta * 6.0)
	$Collider.shape.height = height
	$Collider.position.y = height * .5
	$Body.position.y = height * .5
	$Body.scale.y = height / STANDING_HEIGHT
	$CameraBoom.position.y = lerp(1.5, 1.0, (STANDING_HEIGHT - height) / (STANDING_HEIGHT - CROUCHING_HEIGHT))

func _process(delta: float) -> void:
	if !is_multiplayer_authority() or !view_weapon: return
	if fire_cooldown > 0.0:
		fire_cooldown = maxf(0.0, fire_cooldown - delta)
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			if active_weapon == Weapon.AK47:
				var loaded := mini(AK47_MAGAZINE_SIZE - ak47_ammo, reserve_ammo)
				ak47_ammo += loaded
				reserve_ammo -= loaded
			else:
				var loaded := mini(SNIPER_MAGAZINE_SIZE - sniper_ammo, sniper_reserve_ammo)
				sniper_ammo += loaded
				sniper_reserve_ammo -= loaded
			is_reloading = false
			update_ammo_hud()
	elif active_weapon == Weapon.AK47 and Input.is_action_pressed("fire"):
		try_fire()
	# A frame-driven recoil works even when the player fires again mid-animation.
	recoil_amount = move_toward(recoil_amount, 0.0, delta * 4.0)
	var rest_position := weapon_rest_position()
	var rest_rotation := weapon_rest_rotation()
	if is_reloading and active_weapon == Weapon.AK47:
		view_weapon.position = rest_position + Vector3(.10, -.34, .10)
		view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(18.0), 0, deg_to_rad(-18.0))
		return
	if active_weapon == Weapon.CROWBAR:
		view_weapon.position = rest_position + Vector3(0, -.12, -.36) * recoil_amount
		view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(-96.0), deg_to_rad(8.0), deg_to_rad(18.0)) * recoil_amount
		return
	var kick := .28 if active_weapon == Weapon.AK47 else .48
	view_weapon.position = rest_position + Vector3(0, 0, kick) * recoil_amount
	view_weapon.rotation = rest_rotation + Vector3(deg_to_rad(8.0), 0, 0) * recoil_amount

@rpc("any_peer", "call_remote", "unreliable")
func sync_state(new_position: Vector3, new_yaw: float, new_pitch: float) -> void:
	global_position = new_position; rotation.y = new_yaw; $CameraBoom.rotation.x = new_pitch

@rpc("any_peer", "call_local", "unreliable")
func fire(origin: Vector3, direction: Vector3, weapon: Weapon) -> void:
	# Visual-only projectile: deliberately no raycast, health, hit registration, or damage.
	var tracer := MeshInstance3D.new(); tracer.mesh = SphereMesh.new(); tracer.mesh.radius = .05 if weapon == Weapon.AK47 else .075; tracer.mesh.height = .1; tracer.material_override = material(Color("f5a623")); tracer.global_position = origin; get_tree().current_scene.add_child(tracer)
	var distance := 12.0 if weapon == Weapon.AK47 else 32.0
	var duration := .18 if weapon == Weapon.AK47 else .28
	var tween := create_tween(); tween.tween_property(tracer, "global_position", tracer.global_position + direction * distance, duration); tween.tween_callback(tracer.queue_free)
