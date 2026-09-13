extends Node3D

const FX := preload("res://godot/fx.gd")
const PLAYER_SCENE := preload("res://godot/player.tscn")
const WALL_TEXTURE := preload("res://godot/assets/textures/wall_concrete.png")
const FLOOR_TEXTURE := preload("res://godot/assets/textures/floor_tiles.png")
const CEILING_TEXTURE := preload("res://godot/assets/textures/ceiling_panels.png")
const GLASS_TEXTURE := preload("res://godot/assets/textures/window_glass.png")
const LADDER_TEXTURE := preload("res://godot/assets/textures/ladder_metal.png")
const BULLET_HIT_SOUND := preload("res://assets/sfx/rifle_bullet_hit_wall.mp3")
const GLASS_BREAK_SOUNDS := [
	preload("res://assets/sfx/glass_break_1.mp3"),
	preload("res://assets/sfx/glass_break_2.mp3"),
	preload("res://assets/sfx/glass_break_3.mp3"),
	preload("res://assets/sfx/glass_break_4.mp3"),
]
const MAX_BULLET_HOLES := 64
# How long a smoke grenade keeps pumping out its cloud.
const SMOKE_SECONDS := 11.0
const PORT := 7777
const CONNECT_TIMEOUT_SECONDS := 8.0
var peer: ENetMultiplayerPeer
var spawned := {}
var room_size := 8.0
var floor_height := 3.4
var joining := false
var glass_panel_serial := 0
var bullet_holes: Array[MeshInstance3D] = []

class LightFlicker extends Node:
	var lamp: OmniLight3D
	var base_energy := 1.0
	var next_flicker := 0.0
	var blackout_time := 0.0
	func _process(delta: float) -> void:
		if blackout_time > 0.0:
			blackout_time -= delta
			lamp.light_energy = base_energy * .12
			return
		next_flicker -= delta
		lamp.light_energy = base_energy
		if next_flicker <= 0.0:
			blackout_time = randf_range(.08, .22)
			next_flicker = randf_range(8.0, 18.0)

# Lightweight visual physics keeps glass destruction lively without adding dozens
# of collision bodies to the gameplay simulation.
class GlassShard extends MeshInstance3D:
	var velocity := Vector3.ZERO
	var angular_velocity := Vector3.ZERO
	var floor_y := 0.025
	var age := 0.0
	var settled := false
	var settle_age := 0.0

	func _process(delta: float) -> void:
		age += delta
		if age > 5.5:
			queue_free()
			return
		if !settled:
			velocity.y -= 11.5 * delta
			global_position += velocity * delta
			rotation += angular_velocity * delta
			if global_position.y <= floor_y:
				global_position.y = floor_y
				velocity.y = absf(velocity.y) * .28
				velocity.x *= .58
				velocity.z *= .58
				angular_velocity *= .52
				if velocity.y < .7:
					settled = true
					settle_age = age
		else:
			velocity.x = move_toward(velocity.x, 0.0, delta * .9)
			velocity.z = move_toward(velocity.z, 0.0, delta * .9)
			global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
			rotation += angular_velocity * delta
			angular_velocity *= pow(.06, delta)
			var fade := clampf((age - settle_age - 1.4) / 1.15, 0.0, 1.0)
			if fade > 0.0:
				var shard_material := material_override as StandardMaterial3D
				if shard_material:
					var tint := shard_material.albedo_color
					tint.a = .78 * (1.0 - fade)
					shard_material.albedo_color = tint
			if fade >= 1.0:
				queue_free()

# A smoke grenade keeps emitting for a while and then lets the last puffs thin out
# instead of vanishing in one frame.
class SmokeCloud extends CPUParticles3D:
	var seconds_left := SMOKE_SECONDS

	func _process(delta: float) -> void:
		seconds_left -= delta
		if seconds_left > 0.0: return
		emitting = false
		if seconds_left < -lifetime: queue_free()

func _ready() -> void:
	$Lobby/Panel/Box/Single.pressed.connect(start_single_player)
	$Lobby/Panel/Box/Host.pressed.connect(host_game)
	$Lobby/Panel/Box/Join.pressed.connect(join_game)
	$PauseMenu/Panel/Box/Resume.pressed.connect(resume_game)
	$PauseMenu/Panel/Box/Exit.pressed.connect(exit_game)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	make_atmosphere()
	make_level_collision()
	# The procedural runtime mesh mirrors the Blender source (art/netshooter_house.blend).
	# The GLB is retained in godot/assets for editor-side art replacement.
	if "--single" in OS.get_cmdline_user_args(): start_single_player()
	if "--host" in OS.get_cmdline_user_args(): host_game()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--join="):
			$Lobby/Panel/Box/Address.text = argument.trim_prefix("--join=")
			call_deferred("join_game")

func start_single_player() -> void:
	$Lobby.hide()
	spawn_player(1)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and !$Lobby.visible:
		if $PauseMenu.visible: resume_game()
		else: pause_game()
		get_viewport().set_input_as_handled()

func pause_game() -> void:
	$PauseMenu.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume_game() -> void:
	$PauseMenu.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func exit_game() -> void:
	get_tree().quit()

func host_game() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("*")
	var result := peer.create_server(PORT)
	if result != OK:
		$Lobby/Panel/Box/Status.text = "Не удалось открыть порт %s: %s" % [PORT, error_string(result)]
		return
	multiplayer.multiplayer_peer = peer
	$Lobby.hide()
	show_host_address()
	spawn_player.rpc(1)

func show_host_address() -> void:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(".") and !address.begins_with("127.") and !address.begins_with("169.254."):
			addresses.append(address)
	var hud := CanvasLayer.new()
	hud.name = "HostAddressHUD"
	var label := Label.new()
	label.position = Vector2(18, 18)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("b9ddff"))
	label.text = "LAN-сервер UDP %s | IP: %s" % [PORT, ", ".join(addresses) if !addresses.is_empty() else "не найден"]
	hud.add_child(label)
	add_child(hud)

func join_game() -> void:
	if joining: return
	var address: String = $Lobby/Panel/Box/Address.text.strip_edges()
	peer = ENetMultiplayerPeer.new()
	var result := peer.create_client(address if address else "127.0.0.1", PORT)
	if result != OK:
		$Lobby/Panel/Box/Status.text = "Неверный адрес: %s" % error_string(result)
		return
	multiplayer.multiplayer_peer = peer
	joining = true
	$Lobby/Panel/Box/Status.text = "Подключение…"
	get_tree().create_timer(CONNECT_TIMEOUT_SECONDS).timeout.connect(_on_connection_timeout)

func _on_connected_to_server() -> void:
	joining = false
	$Lobby.hide()
	print("Connected to Netshooter server")

func _on_connection_failed() -> void:
	joining = false
	$Lobby/Panel/Box/Status.text = "Подключение не удалось. Проверьте IP и UDP-порт %s." % PORT
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _on_connection_timeout() -> void:
	if !joining: return
	joining = false
	$Lobby/Panel/Box/Status.text = "Хост недоступен. Проверьте IP и разрешите входящий UDP %s в Firewall на компьютере хоста." % PORT
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _on_server_disconnected() -> void:
	joining = false
	$Lobby.show()
	$Lobby/Panel/Box/Status.text = "Сервер отключился."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _on_peer_connected(id: int) -> void:
	if !multiplayer.is_server(): return
	print("Player connected: %s" % id)
	for existing in spawned.keys(): spawn_player.rpc_id(id, existing)
	spawn_player.rpc(id)

func _on_peer_disconnected(id: int) -> void:
	if spawned.has(id):
		spawned[id].queue_free()
		spawned.erase(id)

@rpc("authority", "call_local", "reliable")
func spawn_player(id: int) -> void:
	if spawned.has(id): return
	var player = PLAYER_SCENE.instantiate()
	player.name = "Player_%s" % id
	player.position = Vector3((id % 3 - 1) * 2.0, 0.1, (id % 2) * 2.0)
	player.set_multiplayer_authority(id)
	add_child(player)
	spawned[id] = player

func make_atmosphere() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8db8d5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("162233")
	environment.ambient_light_energy = .18
	environment.glow_enabled = true
	var world := WorldEnvironment.new(); world.environment = environment; add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "DaylightSun"
	sun.light_color = Color("fff0d0")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	add_child(sun)

func add_ceiling_lamp(position: Vector3, flicker := false) -> void:
	var fixture := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = Vector3(1.5, .10, .35)
	var material := StandardMaterial3D.new(); material.albedo_color = Color("d7ecff"); material.emission_enabled = true; material.emission = Color("8bc8ff"); material.emission_energy_multiplier = 3.2
	fixture.mesh = mesh; fixture.material_override = material; fixture.position = position; add_child(fixture)
	var light := OmniLight3D.new(); light.position = position - Vector3(0,.15,0); light.light_color = Color("9ccfff"); light.light_energy = 3.1; light.omni_range = 6.8; light.omni_attenuation = 1.35; add_child(light)
	if flicker:
		var controller := LightFlicker.new()
		controller.lamp = light
		controller.base_energy = light.light_energy
		controller.next_flicker = randf_range(6.0, 14.0)
		add_child(controller)

func add_emergency_lamp(position: Vector3) -> void:
	var fixture := MeshInstance3D.new()
	var mesh := SphereMesh.new(); mesh.radius = .12; mesh.height = .24
	var material := StandardMaterial3D.new(); material.albedo_color = Color("ff3b30"); material.emission_enabled = true; material.emission = Color("ff1208"); material.emission_energy_multiplier = 4.0
	fixture.mesh = mesh; fixture.material_override = material; fixture.position = position; add_child(fixture)
	var light := OmniLight3D.new(); light.position = position; light.light_color = Color("ff3c2b"); light.light_energy = 1.8; light.omni_range = 4.2; light.omni_attenuation = 1.6; add_child(light)
	var controller := LightFlicker.new(); controller.lamp = light; controller.base_energy = light.light_energy; controller.next_flicker = randf_range(6.0, 14.0); add_child(controller)

func make_box(position: Vector3, size: Vector3, rotate_x := 0.0, color := Color("303946"), collidable := true, texture: Texture2D = WALL_TEXTURE, surface_type: String = "solid") -> void:
	var wall := StaticBody3D.new()
	wall.position = position
	wall.rotation.x = rotate_x
	wall.set_meta("surface_type", surface_type)
	if surface_type == "glass":
		glass_panel_serial += 1
		wall.name = "GlassPanel_%d" % glass_panel_serial
		wall.add_to_group("glass_panels")
	var visible := MeshInstance3D.new()
	visible.name = "Surface"
	var mesh := BoxMesh.new(); mesh.size = size
	var paint := StandardMaterial3D.new(); paint.albedo_color = Color.WHITE if texture else color; paint.roughness = .35 if color == Color("4b9bd0") else .8
	paint.albedo_texture = texture
	paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	visible.mesh = mesh; visible.material_override = paint; wall.add_child(visible)
	if collidable:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new(); shape.size = size
		collider.shape = shape; wall.add_child(collider)
	add_child(wall)

func make_level_collision() -> void:
	var room_centers := [-16.0, -8.0, 0.0, 8.0, 16.0]
	var divider_positions := [-12.0, -4.0, 4.0, 12.0]
	for floor in [-1, 0, 1]:
		var y: float = floor * floor_height
		if floor == -1:
			make_box(Vector3(0, y - .15, 0), Vector3(40, .3, 40), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
		elif floor == 0:
			for tile_x in room_centers:
				for tile_z in room_centers:
					if tile_x == -8.0 and tile_z == 8.0:
						make_box(Vector3(tile_x - 2.6, y - .15, tile_z), Vector3(2.8, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x + 2.6, y - .15, tile_z), Vector3(2.8, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x, y - .15, tile_z - 2.6), Vector3(2.4, .3, 2.8), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x, y - .15, tile_z + 2.6), Vector3(2.4, .3, 2.8), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						continue
					make_box(Vector3(tile_x, y - .15, tile_z), Vector3(8.0, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
		else:
			for tile_x in room_centers:
				for tile_z in room_centers:
					if tile_x == 8.0 and tile_z == 8.0:
						make_box(Vector3(tile_x - 2.6, y - .15, tile_z), Vector3(2.8, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x + 2.6, y - .15, tile_z), Vector3(2.8, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x, y - .15, tile_z - 2.6), Vector3(2.4, .3, 2.8), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						make_box(Vector3(tile_x, y - .15, tile_z + 2.6), Vector3(2.4, .3, 2.8), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
						continue
					make_box(Vector3(tile_x, y - .15, tile_z), Vector3(8.0, .3, 8.0), 0.0, Color.WHITE, true, FLOOR_TEXTURE)
		for x in room_centers:
			for z in room_centers:
				var is_hatch: bool = (floor == -1 and x == -8.0 and z == 8.0) or (floor == 0 and x == 8.0 and z == 8.0)
				if is_hatch:
					make_box(Vector3(x - 2.6, y + 3.4, z), Vector3(2.8, .18, 8.0), 0.0, Color.WHITE, true, CEILING_TEXTURE)
					make_box(Vector3(x + 2.6, y + 3.4, z), Vector3(2.8, .18, 8.0), 0.0, Color.WHITE, true, CEILING_TEXTURE)
					make_box(Vector3(x, y + 3.4, z - 2.6), Vector3(2.4, .18, 2.8), 0.0, Color.WHITE, true, CEILING_TEXTURE)
					make_box(Vector3(x, y + 3.4, z + 2.6), Vector3(2.4, .18, 2.8), 0.0, Color.WHITE, true, CEILING_TEXTURE)
				else:
					make_box(Vector3(x, y + 3.4, z), Vector3(8.0, .18, 8.0), 0.0, Color.WHITE, true, CEILING_TEXTURE)
		# Reinforced perimeter of the base.
		make_box(Vector3(-20, y + 1.7, 0), Vector3(.45, 3.4, 40))
		make_box(Vector3(20, y + 1.7, 0), Vector3(.45, 3.4, 40))
		make_box(Vector3(0, y + 1.7, -20), Vector3(40, 3.4, .45))
		make_box(Vector3(0, y + 1.7, 20), Vector3(40, 3.4, .45))
		# Every inner wall has a door-width aperture, creating a connected 5 × 5 compound.
		for divider in divider_positions:
			for center in room_centers:
				make_box(Vector3(divider, y + 1.7, center - 2.65), Vector3(.28, 3.4, 2.7))
				make_box(Vector3(divider, y + 1.7, center + 2.65), Vector3(.28, 3.4, 2.7))
				make_box(Vector3(center - 2.65, y + 1.7, divider), Vector3(2.7, 3.4, .28))
				make_box(Vector3(center + 2.65, y + 1.7, divider), Vector3(2.7, 3.4, .28))
		if floor == 0 or floor == -1:
			# Ladders sit against the hatch side instead of floating in its center.
			var ladder_x := 7.15 if floor == 0 else -8.85
			for z_rail in [7.35, 8.65]: make_box(Vector3(ladder_x, y + 1.7, z_rail), Vector3(.11, 3.15, .11), 0.0, Color.WHITE, false, LADDER_TEXTURE)
			for rung in 7: make_box(Vector3(ladder_x, y + .35 + rung * .42, 8), Vector3(.11, .09, 1.4), 0.0, Color.WHITE, false, LADDER_TEXTURE)
		# Every room gets a ceiling fixture; stairwell hatches stay clear for traversal.
		for x in room_centers:
			for z in room_centers:
				var is_stairwell: bool = (floor == -1 and x == -8.0 and z == 8.0) or (floor == 0 and x == 8.0 and z == 8.0)
				if is_stairwell: continue
				var flicker: bool = (floor == -1 and (x == -8.0 or z == 16.0)) or (floor == 0 and x == 16.0 and z == -8.0)
				add_ceiling_lamp(Vector3(x, y + 3.18, z), flicker)
		if floor == -1 or floor == 0:
			# Same ceiling fixtures light the stairwells from the side without blocking the shafts.
			add_ceiling_lamp(Vector3(-5.8, y + 3.18, 5.6), true)
			add_ceiling_lamp(Vector3(5.8, y + 3.18, 5.6), true)
		if floor == 0:
			# Supply crates sit against perimeter walls, keeping the corridors clear.
			add_base_cover(Vector3(-19.2, .375, -14), 2)
			add_base_cover(Vector3(19.2, .375, 6), 1)
			add_base_cover(Vector3(0, .375, -19.2), 2)

func add_base_cover(position: Vector3, crates: int) -> void:
	for index in crates:
		# Stack crates directly above one another so every box has physical support.
		make_box(position + Vector3(0, index * .75, 0), Vector3(.85, .75, .85), 0.0, Color("4f563c"), true, null)

func add_maze_bulkheads(y: float, floor: int) -> void:
	# X barriers close doorways on vertical walls; Z barriers close the perpendicular ones.
	var x_barriers := [Vector2(-4, -8), Vector2(4, 0), Vector2(12, 8), Vector2(-12, 16), Vector2(4, -16)]
	var z_barriers := [Vector2(-4, -8), Vector2(4, 8), Vector2(12, 0), Vector2(-12, 8), Vector2(4, 16)]
	if floor == 1:
		x_barriers = [Vector2(-12, -8), Vector2(-4, 8), Vector2(4, -16), Vector2(12, 0)]
		z_barriers = [Vector2(-12, 0), Vector2(-4, 16), Vector2(4, -8), Vector2(12, 8)]
	for barrier in x_barriers:
		make_box(Vector3(barrier.x, y + 1.7, barrier.y), Vector3(.34, 3.4, 2.7))
	for barrier in z_barriers:
		make_box(Vector3(barrier.y, y + 1.7, barrier.x), Vector3(2.7, 3.4, .34))

func resolve_projectile_hit(origin: Vector3, direction: Vector3, shooter_id: int, weapon: int) -> void:
	var shooter := spawned.get(shooter_id) as Node3D
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + direction * 80.0
	query.collision_mask = 1
	if shooter: query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return
	var collider := hit.collider as Node
	if collider and collider.is_in_group("players"):
		var damage := 25 if weapon == 0 else 70
		if collider.has_method("receive_damage"):
			collider.receive_damage.rpc_id(collider.get_multiplayer_authority(), damage)
		show_impact.rpc(hit.position, hit.normal, false)
		return
	if collider and collider.get_meta("surface_type", "solid") == "glass":
		break_glass_at.rpc(hit.position, hit.normal)
	else:
		show_impact.rpc(hit.position, hit.normal)

func resolve_explosion(point: Vector3, radius: float, damage: int) -> void:
	# Server side, the way bullet hits are resolved: everyone inside the blast is hurt,
	# the further out the less, and a wall between them and the grenade stops it. The
	# thrower is not excluded — standing next to your own grenade hurts.
	for node in get_tree().get_nodes_in_group("players"):
		var target := node as Node3D
		if target == null or !target.has_method("receive_damage"): continue
		var chest := target.global_position + Vector3(0, .9, 0)
		var distance := chest.distance_to(point)
		if distance > radius: continue
		var query := PhysicsRayQueryParameters3D.new()
		query.from = point
		query.to = chest
		query.collision_mask = 1
		query.exclude = [target.get_rid()]
		if !get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		var hurt := int(round(damage * (1.0 - distance / radius)))
		if hurt <= 0: continue
		if multiplayer.has_multiplayer_peer():
			target.receive_damage.rpc_id(target.get_multiplayer_authority(), hurt)
		else:
			target.receive_damage(hurt)

func show_explosion(point: Vector3, smoke: bool) -> void:
	# Every peer detonates its own copy of the grenade, so this is a plain local call
	# rather than an RPC.
	play_blast_sound(point, smoke)
	if smoke:
		spawn_smoke_cloud(point)
		return
	spawn_blast_fire(point)
	spawn_blast_sparks(point)
	spawn_blast_smoke(point)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb05a")
	light.light_energy = 7.0
	light.omni_range = 9.0
	add_child(light)
	light.global_position = point + Vector3(0, .3, 0)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, .32)
	tween.tween_callback(light.queue_free)

func play_blast_sound(point: Vector3, smoke: bool) -> void:
	# There is no dedicated explosion sample in the project, so the bullet impact is
	# dropped a couple of octaves: a short, heavy thud instead of a sharp crack.
	var audio := AudioStreamPlayer3D.new()
	audio.name = "GrenadeAudio"
	audio.stream = BULLET_HIT_SOUND
	audio.pitch_scale = .82 if smoke else .42
	audio.volume_db = -6.0 if smoke else 6.0
	audio.max_distance = 30.0 if smoke else 70.0
	add_child(audio)
	audio.global_position = point
	audio.play()
	audio.finished.connect(audio.queue_free)

func spawn_blast_fire(point: Vector3) -> void:
	var fire := CPUParticles3D.new()
	fire.name = "GrenadeFire"
	fire.amount = 24
	fire.lifetime = .42
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.spread = 180.0
	fire.initial_velocity_min = 2.5
	fire.initial_velocity_max = 8.5
	fire.damping_min = 6.0
	fire.damping_max = 12.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.particle_flag_align_y = true
	fire.scale_amount_min = 1.2
	fire.scale_amount_max = 2.6
	fire.scale_amount_curve = FX.fade_curve(1.0, .3)
	fire.color_ramp = FX.alpha_ramp(Color(1, .96, .82), Color(1, .42, .08, 0))
	fire.mesh = FX.flame_mesh(.34, .62)
	add_child(fire)
	fire.global_position = point + Vector3(0, .15, 0)
	fire.emitting = true
	fire.finished.connect(fire.queue_free)

func spawn_blast_sparks(point: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "GrenadeSparks"
	sparks.amount = 34
	sparks.lifetime = .6
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 6.0
	sparks.initial_velocity_max = 17.0
	sparks.damping_min = 1.0
	sparks.damping_max = 3.5
	sparks.gravity = Vector3(0, -11.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = .5
	sparks.scale_amount_max = 1.3
	sparks.scale_amount_curve = FX.fade_curve(1.0, .2)
	sparks.color_ramp = FX.alpha_ramp(Color("fff4d2"), Color(1, .35, .05, 0))
	sparks.mesh = FX.streak_mesh(.012, .26)
	add_child(sparks)
	sparks.global_position = point + Vector3(0, .1, 0)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)

func spawn_blast_smoke(point: Vector3) -> void:
	var smoke := CPUParticles3D.new()
	smoke.name = "GrenadeSmoke"
	smoke.amount = 18
	smoke.lifetime = 1.9
	smoke.one_shot = true
	smoke.explosiveness = .85
	smoke.spread = 180.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 4.5
	smoke.damping_min = 2.0
	smoke.damping_max = 4.0
	smoke.gravity = Vector3(0, .5, 0)
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.angular_velocity_min = -25.0
	smoke.angular_velocity_max = 25.0
	smoke.scale_amount_min = .7
	smoke.scale_amount_max = 1.5
	smoke.scale_amount_curve = FX.fade_curve(1.0, 3.2)
	smoke.color_ramp = FX.alpha_ramp(Color(.22, .21, .20, .75), Color(.42, .41, .40, 0))
	smoke.mesh = FX.smoke_mesh(1.0)
	add_child(smoke)
	smoke.global_position = point + Vector3(0, .2, 0)
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)

func spawn_smoke_cloud(point: Vector3) -> void:
	# A screening cloud: it keeps feeding itself for SMOKE_SECONDS and fills a ball a
	# couple of metres across, enough to break a line of sight through a doorway.
	var cloud := SmokeCloud.new()
	cloud.name = "SmokeCloud"
	cloud.amount = 90
	cloud.lifetime = 3.4
	cloud.preprocess = 1.2
	cloud.spread = 180.0
	cloud.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cloud.emission_sphere_radius = 1.5
	cloud.initial_velocity_min = .15
	cloud.initial_velocity_max = .9
	cloud.damping_min = .5
	cloud.damping_max = 1.4
	cloud.gravity = Vector3(0, .25, 0)
	cloud.angle_min = -180.0
	cloud.angle_max = 180.0
	cloud.angular_velocity_min = -12.0
	cloud.angular_velocity_max = 12.0
	cloud.scale_amount_min = 1.6
	cloud.scale_amount_max = 3.2
	cloud.scale_amount_curve = FX.fade_curve(.6, 1.4)
	# Each puff blooms in, hangs there opaque and thins out again.
	var ramp := FX.alpha_ramp(Color(.88, .90, .92, 0), Color(.80, .82, .84, 0))
	ramp.add_point(.22, Color(.86, .88, .90, .85))
	ramp.add_point(.72, Color(.83, .85, .87, .78))
	cloud.color_ramp = ramp
	cloud.mesh = FX.smoke_mesh(1.0)
	add_child(cloud)
	cloud.global_position = point + Vector3(0, .8, 0)
	cloud.emitting = true

@rpc("authority", "call_local", "unreliable")
func show_impact(point: Vector3, normal: Vector3, solid := true) -> void:
	var impact_audio := AudioStreamPlayer3D.new()
	impact_audio.name = "BulletImpactAudio"
	impact_audio.stream = BULLET_HIT_SOUND
	impact_audio.volume_db = -3.0
	impact_audio.max_distance = 24.0
	add_child(impact_audio)
	impact_audio.global_position = point
	impact_audio.play()
	impact_audio.finished.connect(impact_audio.queue_free)
	# Sparks are stretched along their own flight, so they read as ricocheting
	# splinters rather than a puff of round blobs.
	var sparks := CPUParticles3D.new()
	sparks.name = "WallImpactSparks"
	sparks.amount = 9
	sparks.lifetime = .19
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = normal
	sparks.spread = 52.0
	sparks.initial_velocity_min = 2.4
	sparks.initial_velocity_max = 6.5
	sparks.damping_min = 1.5
	sparks.damping_max = 4.0
	sparks.gravity = Vector3(0, -9.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = .4
	sparks.scale_amount_max = .9
	sparks.scale_amount_curve = FX.fade_curve(1.0, .25)
	sparks.color_ramp = FX.alpha_ramp(Color("fff2cd"), Color(1, .38, .05, 0))
	sparks.mesh = FX.streak_mesh(.008, .13)
	add_child(sparks)
	sparks.global_position = point + normal * .015
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)
	# A single short flame lick where the round bites into the surface.
	var flash := CPUParticles3D.new()
	flash.name = "WallImpactFlash"
	flash.amount = 2
	flash.lifetime = .09
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.direction = normal
	flash.spread = 24.0
	flash.initial_velocity_min = 1.2
	flash.initial_velocity_max = 2.4
	flash.damping_min = 12.0
	flash.damping_max = 18.0
	flash.gravity = Vector3.ZERO
	flash.particle_flag_align_y = true
	flash.scale_amount_min = .55
	flash.scale_amount_max = 1.0
	flash.scale_amount_curve = FX.fade_curve(1.0, .2)
	flash.color_ramp = FX.alpha_ramp(Color(1, 1, 1, 1), Color(1, .7, .35, 0))
	flash.mesh = FX.flame_mesh(.10, .22)
	add_child(flash)
	flash.global_position = point + normal * .01
	flash.emitting = true
	flash.finished.connect(flash.queue_free)
	var light := OmniLight3D.new(); light.light_color = Color("ff9b38"); light.light_energy = .9; light.omni_range = 1.4; add_child(light); light.global_position = point + normal * .1
	var tween := create_tween(); tween.tween_property(light, "light_energy", 0.0, .14); tween.tween_callback(light.queue_free)
	if !solid: return
	spawn_impact_dust(point, normal)
	spawn_bullet_hole(point, normal)

func spawn_impact_dust(point: Vector3, normal: Vector3) -> void:
	# Concrete gives off a short cone of dust that hangs in front of the hole.
	var dust := CPUParticles3D.new()
	dust.name = "WallImpactDust"
	dust.amount = 6
	dust.lifetime = .9
	dust.one_shot = true
	dust.explosiveness = .8
	dust.direction = normal
	dust.spread = 62.0
	dust.initial_velocity_min = .5
	dust.initial_velocity_max = 1.8
	dust.damping_min = 1.8
	dust.damping_max = 3.2
	dust.gravity = Vector3(0, -.6, 0)
	dust.angle_min = -180.0
	dust.angle_max = 180.0
	dust.angular_velocity_min = -30.0
	dust.angular_velocity_max = 30.0
	dust.scale_amount_min = .06
	dust.scale_amount_max = .13
	dust.scale_amount_curve = FX.fade_curve(1.0, 3.0)
	dust.color_ramp = FX.alpha_ramp(Color(.78, .75, .70, .40), Color(.55, .53, .50, 0))
	dust.mesh = FX.smoke_mesh(1.0)
	add_child(dust)
	dust.global_position = point + normal * .05
	dust.emitting = true
	dust.finished.connect(dust.queue_free)

func spawn_bullet_hole(point: Vector3, normal: Vector3) -> void:
	# The Compatibility renderer has no decal projector, so a hit leaves a small quad
	# lying on the surface. Older holes are recycled to keep the count bounded.
	var hole := MeshInstance3D.new()
	hole.name = "BulletHole"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * randf_range(.11, .16)
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = FX.bullet_hole_texture()
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.roughness = .95
	paint.render_priority = 1
	quad.material = paint
	hole.mesh = quad
	add_child(hole)
	# A centimetre of lift keeps the quad off the wall it is painted on.
	hole.global_transform = Transform3D(FX.surface_basis(normal).rotated(normal, randf_range(0.0, TAU)), point + normal * .012)
	bullet_holes.append(hole)
	if bullet_holes.size() > MAX_BULLET_HOLES:
		var oldest: MeshInstance3D = bullet_holes.pop_front()
		if is_instance_valid(oldest): oldest.queue_free()

@rpc("authority", "call_local", "reliable")
func break_glass_at(point: Vector3, impact_normal: Vector3) -> void:
	var nearest: Node3D
	var nearest_distance := 2.5
	for panel in get_tree().get_nodes_in_group("glass_panels"):
		if panel.get_meta("broken", false): continue
		var candidate := panel as Node3D
		var distance := candidate.global_position.distance_to(point)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	if nearest == null: return
	nearest.set_meta("broken", true)
	var surface := nearest.get_node_or_null("Surface") as MeshInstance3D
	if surface: surface.visible = false
	nearest.collision_layer = 0
	nearest.collision_mask = 0
	play_glass_break_sound(point)
	spawn_glass_shards(point, impact_normal)

func play_glass_break_sound(point: Vector3) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.name = "GlassBreakAudio"
	audio.stream = GLASS_BREAK_SOUNDS[randi() % GLASS_BREAK_SOUNDS.size()]
	audio.volume_db = -1.0
	audio.max_distance = 28.0
	audio.global_position = point
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func spawn_glass_shards(point: Vector3, impact_normal: Vector3) -> void:
	var shard_material := StandardMaterial3D.new()
	shard_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shard_material.albedo_color = Color(0.12, 0.52, 0.86, .78)
	shard_material.emission_enabled = true
	shard_material.emission = Color(0.025, 0.18, 0.42)
	var outward := impact_normal.normalized()
	for index in 26:
		var shard := GlassShard.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(randf_range(.045, .16), randf_range(.055, .22))
		shard.mesh = mesh
		shard.material_override = shard_material.duplicate()
		shard.global_position = point + outward * .035 + Vector3(randf_range(-.14, .14), randf_range(-.14, .14), randf_range(-.14, .14))
		shard.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))
		var spray := (outward + Vector3(randf_range(-.75, .75), randf_range(-.22, .85), randf_range(-.75, .75))).normalized()
		shard.velocity = spray * randf_range(2.6, 5.6) + Vector3(0.0, randf_range(.8, 2.5), 0.0)
		shard.angular_velocity = Vector3(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
		add_child(shard)
