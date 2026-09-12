extends Node3D

const PLAYER_SCENE := preload("res://godot/player.tscn")
const PORT := 7000
const CONNECT_TIMEOUT_SECONDS := 8.0
var peer: ENetMultiplayerPeer
var spawned := {}
var room_size := 8.0
var floor_height := 3.4
var joining := false

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
	var result := peer.create_server(PORT)
	if result != OK:
		$Lobby/Panel/Box/Status.text = "Не удалось открыть порт %s: %s" % [PORT, error_string(result)]
		return
	multiplayer.multiplayer_peer = peer
	$Lobby.hide()
	spawn_player.rpc(1)

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
	$Lobby/Panel/Box/Status.text = "Таймаут. Разрешите Godot UDP %s в Windows Firewall." % PORT
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

func make_box(position: Vector3, size: Vector3, rotate_x := 0.0) -> void:
	var wall := StaticBody3D.new()
	wall.position = position
	wall.rotation.x = rotate_x
	var visible := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = size
	var paint := StandardMaterial3D.new(); paint.albedo_color = Color("303946"); paint.roughness = .8
	visible.mesh = mesh; visible.material_override = paint; wall.add_child(visible)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size
	collider.shape = shape; wall.add_child(collider); add_child(wall)

func make_level_collision() -> void:
	for floor in 1:
		var y := floor * floor_height
		make_box(Vector3(0, y - .15, 0), Vector3(24, .3, 24))
		for x in [-12.0, 12.0]: make_box(Vector3(x, y + 1.7, 0), Vector3(.35, 3.4, 24))
		for z in [-12.0, 12.0]: make_box(Vector3(0, y + 1.7, z), Vector3(24, 3.4, .35))
		# Divider panels are placed on the actual bay edges (±4), leaving a 2.5m aperture in every bay.
		for z in [-4.0, 4.0]:
			for x in [-8.0, 0.0, 8.0]:
				make_box(Vector3(x - 2.625, y + 1.7, z), Vector3(2.75, 3.4, .28))
				make_box(Vector3(x + 2.625, y + 1.7, z), Vector3(2.75, 3.4, .28))
		for x in [-4.0, 4.0]:
			for z in [-8.0, 0.0, 8.0]:
				make_box(Vector3(x, y + 1.7, z - 2.625), Vector3(.28, 3.4, 2.75))
				make_box(Vector3(x, y + 1.7, z + 2.625), Vector3(.28, 3.4, 2.75))
