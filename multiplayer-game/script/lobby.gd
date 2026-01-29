extends Control

@onready var name_input: LineEdit = $VBoxContainer/name_input
@onready var ip_input: LineEdit = $VBoxContainer/ip_input
@onready var port_input: LineEdit = $VBoxContainer/Port_input
@onready var create_btn: Button = $VBoxContainer/HBoxContainer/Create_btn
@onready var join_btn: Button = $VBoxContainer/HBoxContainer/Join_btn
@onready var player_list: VBoxContainer = $VBoxContainer/Player_List
@onready var start_btn: Button = $VBoxContainer/Start_btn
@onready var status_lb: Label = $VBoxContainer/Status_lb

# Steam
@onready var createSteam_btn: Button = $SteamPart/CreateBtn
@onready var refresh_btn: Button = $SteamPart/RefreshBtn
@onready var rooms_vbox: VBoxContainer = $SteamPart/RoomsVbox
@onready var statusSteam_lb: Label = $SteamPart/StatusLb

const MAX_MEMBERS := 4
const GAME_KEY := "JUEGOMULTIPLAYER_V1" # clave test

var current_lobby_id: int = 0

var host_peer_id: int = 1

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
	
	createSteam_btn.pressed.connect(_on_create_steam_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)

func _on_host_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name == "":
		status_lb.text = "Pon un nombre antes de crear la partida"
		return

	var port := port_input.text.to_int()
	if port <= 0:
		status_lb.text = "Puerto inválido"
		return

	var err: int = NetworkManager.host_local(port, max_player)
	if err != OK:
		status_lb.text = "No se pudo crear el servidor"
		return

	host_peer_id = multiplayer.get_unique_id()

	is_host = true
	status_lb.text = "Servidor (LOCAL) creado en %d. Esperando..." % port

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
	var port := port_input.text.to_int()
	if port <= 0:
		status_lb.text = "Puerto inválido"
		return

	var err := NetworkManager.join_local(ip, port)
	if err != OK:
		status_lb.text = "No se pudo conectar"
		return

	is_host = false
	status_lb.text = "Conectando (LOCAL) a %s:%d..." % [ip, port]

func _on_connected_to_server() -> void:
	status_lb.text = "Conectado. Registrando jugador..."
	var player_name := name_input.text.strip_edges()
	rpc_id(host_peer_id, "register_player", player_name)

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

func _on_create_steam_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name == "":
		statusSteam_lb.text = "Pon un nombre antes de crear sala Steam"
		return

	statusSteam_lb.text = "Creando sala Steam..."
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_MEMBERS)

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		statusSteam_lb.text = "Error creando lobby (result=%s)" % result
		return

	current_lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "game", GAME_KEY)
	Steam.setLobbyData(lobby_id, "name", "Sala de " + Steam.getPersonaName())

	if not NetworkManager.host_steam():
		statusSteam_lb.text = "No pude iniciar red Steam (SteamMultiplayerPeer faltante)."
		return

	host_peer_id = multiplayer.get_unique_id()

	is_host = true
	statusSteam_lb.text = "Sala Steam creada. Esperando..."

	var my_id := multiplayer.get_unique_id()
	players[my_id] = name_input.text.strip_edges()
	_refresh_player_ui()
	_broadcast_playes()

func _on_refresh_pressed() -> void:
	_clear_rooms()
	statusSteam_lb.text = "Buscando salas Steam..."

	Steam.addRequestLobbyListStringFilter("game", GAME_KEY, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListResultCountFilter(50)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	statusSteam_lb.text = "Salas encontradas: %d" % lobbies.size()

	for lobby_id in lobbies:
		var name := Steam.getLobbyData(lobby_id, "name")
		if name == "": name = "Lobby " + str(lobby_id)
		_add_room_row(lobby_id, name, Steam.getNumLobbyMembers(lobby_id))

func _add_room_row(lobby_id: int, lobby_name: String, members: int) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s (%d/%d)" % [lobby_name, members, MAX_MEMBERS]

	var btn := Button.new()
	btn.text = "Entrar"
	btn.pressed.connect(func():
		statusSteam_lb.text = "Entrando a %s..." % lobby_name
		Steam.joinLobby(lobby_id)
	)

	row.add_child(lbl)
	row.add_child(btn)
	rooms_vbox.add_child(row)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int) -> void:
	current_lobby_id = lobby_id
	statusSteam_lb.text = "Dentro del lobby. Conectando a host..."

	var host_steam_id := Steam.getLobbyOwner(lobby_id)

	if not NetworkManager.join_steam(host_steam_id):
		statusSteam_lb.text = "No pude unirme por Steam (SteamMultiplayerPeer faltante)."
		return

	is_host = false

	# Espera a que se cree la sesión P2P y aparezcan peers
	await get_tree().create_timer(0.3).timeout
	var peers := multiplayer.get_peers()

	# Heurística: el host suele ser el primer peer que ves
	if peers.size() > 0:
		host_peer_id = int(peers[0])
	else:
		host_peer_id = 1

func _clear_rooms() -> void:
	for c in rooms_vbox.get_children():
		c.queue_free()
