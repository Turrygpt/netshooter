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
const LADDER_CLIMB_SPEED := 2.7
const LADDER_TOP := 3.42
const LADDER_APPROACH_CLEARANCE := 0.15
var pitch := 0.0
var yaw := 0.0
var fire_cooldown := 0.0
var third_person := false
var climbing := false

func _ready() -> void:
	$Collider.shape = CapsuleShape3D.new()
	$Collider.shape.radius = .35
	$Collider.shape.height = STANDING_HEIGHT
	$Body.mesh = CapsuleMesh.new()
	$Body.mesh.radius = .34
	$Body.mesh.height = 1.35
	$Body.material_override = material(Color("36a6ff") if is_multiplayer_authority() else Color("ef6060"))
	var gun := MeshInstance3D.new(); gun.mesh = BoxMesh.new(); gun.mesh.size = Vector3(.6, .17, .22); gun.position = Vector3(.48, .8, -.12); gun.material_override = material(Color("161b20")); $Body.add_child(gun)
	if is_multiplayer_authority():
		$CameraBoom/Camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.metallic = .2; return m

func _unhandled_input(event: InputEvent) -> void:
	if !is_multiplayer_authority(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * .0025; pitch = clamp(pitch - event.relative.y * .0025, -1.2, 1.2)
		rotation.y = yaw; $CameraBoom.rotation.x = pitch
	if event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_V:
		third_person = !third_person
		$CameraBoom.spring_length = THIRD_PERSON_DISTANCE if third_person else 0.0
	if event.is_action_pressed("fire"):
		if multiplayer.has_multiplayer_peer(): fire.rpc(global_position, -$CameraBoom/Camera.global_transform.basis.z)
		else: fire(global_position, -$CameraBoom/Camera.global_transform.basis.z)

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
	# The ladder can only be mounted from its west/opposite side. The current
	# room-side approach (x greater than the ladder) is deliberately rejected.
	return global_position.x < LADDER_POSITION.x - LADDER_APPROACH_CLEARANCE and abs(global_position.z - LADDER_POSITION.z) < .8 and global_position.y >= -.1 and global_position.y <= LADDER_TOP + .2

func climb_ladder(axis: float, delta: float) -> void:
	# Snap gently onto the rails, then W climbs upward and S descends.
	global_position.x = move_toward(global_position.x, LADDER_POSITION.x, delta * 4.0)
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

@rpc("any_peer", "call_remote", "unreliable")
func sync_state(new_position: Vector3, new_yaw: float, new_pitch: float) -> void:
	global_position = new_position; rotation.y = new_yaw; $CameraBoom.rotation.x = new_pitch

@rpc("any_peer", "call_local", "unreliable")
func fire(origin: Vector3, direction: Vector3) -> void:
	# Visual-only projectile: deliberately no raycast, health, hit registration, or damage.
	var tracer := MeshInstance3D.new(); tracer.mesh = SphereMesh.new(); tracer.mesh.radius = .05; tracer.mesh.height = .1; tracer.material_override = material(Color("f5a623")); tracer.global_position = origin + Vector3.UP * .8; get_tree().current_scene.add_child(tracer)
	var tween := create_tween(); tween.tween_property(tracer, "global_position", tracer.global_position + direction * 12.0, .18); tween.tween_callback(tracer.queue_free)
