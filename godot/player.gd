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
	if is_multiplayer_authority():
		create_view_weapon()
		$Camera.current = true
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

func create_view_weapon() -> void:
	# First-person weapon: a child of the camera, so it cannot drift in world space.
	var weapon := Node3D.new()
	weapon.name = "ViewWeapon"
	weapon.position = Vector3(.38, -.30, -.72)
	weapon.rotation = Vector3(deg_to_rad(-4.0), deg_to_rad(-3.0), 0.0)
	$Camera.add_child(weapon)
	var dark := Color("161b20")
	var metal := Color("4d5a66")
	add_weapon_part(weapon, Vector3(.26, .18, .58), Vector3(0, 0, 0), dark) # receiver
	add_weapon_part(weapon, Vector3(.10, .10, .52), Vector3(0, .02, -.53), metal) # barrel
	add_weapon_part(weapon, Vector3(.04, .04, .10), Vector3(0, .10, -.27), Color("d9e4ec")) # front sight
	add_weapon_part(weapon, Vector3(.17, .25, .12), Vector3(0, -.18, .12), Color("29323a")) # grip
	add_weapon_part(weapon, Vector3(.20, .12, .30), Vector3(0, -.03, .38), dark) # stock
	add_weapon_part(weapon, Vector3(.12, .07, .13), Vector3(0, .13, .12), metal) # rear sight

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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * .0025; pitch = clamp(pitch - event.relative.y * .0025, -1.2, 1.2)
		rotation.y = yaw; $Camera.rotation.x = pitch
	if event.is_action_pressed("fire"):
		if multiplayer.has_multiplayer_peer(): fire.rpc(global_position, -$Camera.global_transform.basis.z)
		else: fire(global_position, -$Camera.global_transform.basis.z)

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority(): return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = direction.x * SPEED; velocity.z = direction.z * SPEED
	if !is_on_floor(): velocity.y -= GRAVITY * delta
	else: velocity.y = -0.1
	move_and_slide()
	if multiplayer.has_multiplayer_peer(): sync_state.rpc(global_position, rotation.y, $Camera.rotation.x)

@rpc("any_peer", "call_remote", "unreliable")
func sync_state(new_position: Vector3, new_yaw: float, new_pitch: float) -> void:
	global_position = new_position; rotation.y = new_yaw; $Camera.rotation.x = new_pitch

@rpc("any_peer", "call_local", "unreliable")
func fire(origin: Vector3, direction: Vector3) -> void:
	# Visual-only projectile: deliberately no raycast, health, hit registration, or damage.
	var tracer := MeshInstance3D.new(); tracer.mesh = SphereMesh.new(); tracer.mesh.radius = .05; tracer.mesh.height = .1; tracer.material_override = material(Color("f5a623")); tracer.global_position = origin + Vector3.UP * .8; get_tree().current_scene.add_child(tracer)
	var tween := create_tween(); tween.tween_property(tracer, "global_position", tracer.global_position + direction * 12.0, .18); tween.tween_callback(tracer.queue_free)
