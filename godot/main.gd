extends Node3D

const PLAYER_SCENE := preload("res://godot/player.tscn")
const PORT := 7000
var peer := ENetMultiplayerPeer.new()
var spawned := {}
var room_size := 8.0
var floor_height := 3.4

func _ready() -> void:
	$Lobby/Panel/Box/Host.pressed.connect(host_game)
	$Lobby/Panel/Box/Join.pressed.connect(join_game)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	make_level_collision()
	# The procedural runtime mesh mirrors the Blender source (art/netshooter_house.blend).
	# The GLB is retained in godot/assets for editor-side art replacement.
	if "--lobby" in OS.get_cmdline_user_args():
		return
	start_single_player()

func start_single_player() -> void:
	$Lobby.hide()
	spawn_player(1)

func host_game() -> void:
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	$Lobby.hide()
	spawn_player.rpc(1)

func join_game() -> void:
	var address: String = $Lobby/Panel/Box/Address.text.strip_edges()
	peer.create_client(address if address else "127.0.0.1", PORT)
	multiplayer.multiplayer_peer = peer
	$Lobby/Panel/Box/Status.text = "Подключение…"
	multiplayer.connected_to_server.connect(func(): $Lobby.hide())

func _on_peer_connected(id: int) -> void:
	if !multiplayer.is_server(): return
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
