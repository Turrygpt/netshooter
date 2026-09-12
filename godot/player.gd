extends CharacterBody3D

const SPEED := 5.5
const GRAVITY := 18.0
var pitch := 0.0
var yaw := 0.0
var fire_cooldown := 0.0

func _ready() -> void:
	$Collider.shape = CapsuleShape3D.new()
	$Collider.shape.radius = .35
	$Collider.shape.height = 1.8
	$Body.mesh = CapsuleMesh.new()
	$Body.mesh.radius = .34
	$Body.mesh.height = 1.35
	$Body.material_override = material(Color("36a6ff") if is_multiplayer_authority() else Color("ef6060"))
	var gun := MeshInstance3D.new(); gun.mesh = BoxMesh.new(); gun.mesh.size = Vector3(.6, .17, .22); gun.position = Vector3(.48, .8, -.12); gun.material_override = material(Color("161b20")); $Body.add_child(gun)
	if is_multiplayer_authority():
		$Camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.metallic = .2; return m

func _unhandled_input(event: InputEvent) -> void:
	if !is_multiplayer_authority(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * .0025; pitch = clamp(pitch - event.relative.y * .0025, -1.2, 1.2)
		rotation.y = yaw; $Camera.rotation.x = pitch
	if event.is_action_pressed("fire"): fire.rpc(global_position, -$Camera.global_transform.basis.z)

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority(): return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * SPEED; velocity.z = direction.z * SPEED
	if !is_on_floor(): velocity.y -= GRAVITY * delta
	else: velocity.y = -0.1
	move_and_slide()
	sync_state.rpc(global_position, rotation.y, $Camera.rotation.x)

@rpc("any_peer", "call_remote", "unreliable")
func sync_state(new_position: Vector3, new_yaw: float, new_pitch: float) -> void:
	global_position = new_position; rotation.y = new_yaw; $Camera.rotation.x = new_pitch

@rpc("any_peer", "call_local", "unreliable")
func fire(origin: Vector3, direction: Vector3) -> void:
	# Visual-only projectile: deliberately no raycast, health, hit registration, or damage.
	var tracer := MeshInstance3D.new(); tracer.mesh = SphereMesh.new(); tracer.mesh.radius = .05; tracer.mesh.height = .1; tracer.material_override = material(Color("f5a623")); tracer.global_position = origin + Vector3.UP * .8; get_tree().current_scene.add_child(tracer)
	var tween := create_tween(); tween.tween_property(tracer, "global_position", tracer.global_position + direction * 12.0, .18); tween.tween_callback(tracer.queue_free)
