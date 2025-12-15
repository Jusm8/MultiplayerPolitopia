extends Control

@onready var name_input: LineEdit = $VBoxContainer/name_input
@onready var ip_input: LineEdit = $VBoxContainer/ip_input
@onready var port_input: LineEdit = $VBoxContainer/Port_input
@onready var create_btn: Button = $VBoxContainer/HBoxContainer/Create_btn
@onready var join_btn: Button = $VBoxContainer/HBoxContainer/Join_btn
@onready var player_list: VBoxContainer = $VBoxContainer/Player_List
@onready var start_btn: Button = $VBoxContainer/Start_btn
@onready var status_lb: Label = $VBoxContainer/Status_lb

var is_host: bool = false
var max_player: int = 4
var players:= {} #peer_id nombre

func _ready() -> void:
	start_btn.disabled = true
	
	create_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_btn.pressed.connect(_on_start_pressed)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconected)
	
func _on_host_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name == "":
		status_lb.text = "Pon un nombre antes de crear la partida"
		return
	
	var port:= port_input.text.to_int()
	if port <= 0:
		status_lb.text = "No se pudo crear el servidor"
		return
	
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_player)
	if error != OK:
		status_lb.text = "No se puedo crear el servidor"
		return
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	status_lb.text = "Servidor creado en el puerto %d. Esperando jugadores..." % port 
	
	var my_id := multiplayer.get_unique_id()
	players[my_id] = player_name
	
	_refresh_player_ui()
	_broadcast_playes()  

func _on_join_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name == "":
		status_lb.text = "Pon un nombre antes de unirte"
		return
	
	var ip := ip_input.text.strip_edges()
	var port:= port_input.text.to_int()
	if port <= 0:
		status_lb.text = "Puerto invalido"
		return
	
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		status_lb.text = "No se pudo encontrar el servidor"
		return
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	status_lb.text = "Conectando a %s:%d..." % [ip, port]

func _on_connected_to_server() -> void:
	status_lb.text = "Conectando al servidor. Registrando jugador..."
	var player_name := name_input.text.strip_edges()
	# El server siempre es el peer 1
	rpc_id(1, "register_player", player_name)

func _on_connection_failed() -> void:
	status_lb.text = "Fallo la conexion al servidor"

func _on_server_disconected() -> void:
	status_lb.text = "Desconectado del servidor"
	players.clear()
	_refresh_player_ui()
	start_btn.disabled = true
	
func _on_peer_connected(id: int) -> void:
	if is_host:
		print("Peer conectado con id: ", id)

func _on_peer_disconnected(id: int) -> void:
	var name := ""
	if players.has(id):
		name = str(players[id])
		players.erase(id)
		_refresh_player_ui()
		_broadcast_playes()

	if is_host:
		if name == "":
			status_lb.text = "Un jugador se ha desconectado"
		else:
			status_lb.text = "Jugador %s se ha desconectado" % name

@rpc("any_peer")
func register_player(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()

	if players.size() >= max_player:
		return

	players[id] = player_name
	status_lb.text = "Jugador %s se ha conectado" % player_name

	_broadcast_playes()

func _broadcast_playes() -> void:
	var names := []
	GameData.players = players.duplicate()

	for id in players.keys():
		names.append(players[id])
	rpc("sync_players", players)

@rpc("any_peer", "call_local")
func sync_players(p: Dictionary) -> void:
	# Actualizamos diccionario local en TODOS los peers
	players = p.duplicate()
	GameData.players = players.duplicate()

	# Reconstruimos la lista visual con los nombres
	for child in player_list.get_children():
		child.queue_free()

	for id in players.keys():
		var label := Label.new()
		label.text = str(players[id])
		player_list.add_child(label)

	var count := players.size()
	start_btn.disabled = not (is_host and count >= 2 and count <= max_player)

func _refresh_player_ui() -> void:
	# Reconstruye la lista a partir del diccionario players
	for child in player_list.get_children():
		child.queue_free()

	for id in players.keys():
		var label := Label.new()
		label.text = str(players[id])
		player_list.add_child(label)

	var count := players.size()
	start_btn.disabled = not (is_host and count >= 2 and count <= max_player)

func _on_start_pressed() -> void:
	if not is_host:
		return
	status_lb.text = "Empezando partida..."
	rpc("start_game")  # avisa a todos


@rpc("any_peer", "call_local")
func start_game() -> void:
	# Cambiar a la escena del mapa en todos los peers
	get_tree().change_scene_to_file("res://scene/mapa.tscn")
