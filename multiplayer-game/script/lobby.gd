extends Control

@onready var name_input:   LineEdit      = $VBoxContainer/name_input
@onready var ip_input:     LineEdit      = $VBoxContainer/ip_input
@onready var port_input:   LineEdit      = $VBoxContainer/Port_input
@onready var create_btn:   Button        = $VBoxContainer/HBoxContainer/Create_btn
@onready var join_btn:     Button        = $VBoxContainer/HBoxContainer/Join_btn
@onready var player_list:  VBoxContainer = $VBoxContainer/Player_List
@onready var start_btn:    Button        = $VBoxContainer/Start_btn
@onready var status_lb:    Label         = $VBoxContainer/Status_lb

# Seed UI — añade estos nodos hijos dentro de VBoxContainer, justo encima de Start_btn:
#   HBoxContainer  (nombre: SeedContainer)
#     ├─ Label           texto: "Semilla:"
#     ├─ LineEdit        (nombre: SeedInput)   placeholder: "Aleatoria"
#     ├─ Button          (nombre: RandomBtn)   texto: "🎲"
#     └─ Label           (nombre: SeedDisplay) texto: ""  ← clientes ven la semilla del host aquí
@onready var seed_input:    LineEdit = $VBoxContainer/SeedContainer/SeedInput
@onready var random_btn:    Button   = $VBoxContainer/SeedContainer/RandomBtn
@onready var seed_display:  Label    = $VBoxContainer/SeedContainer/SeedDisplay

# Steam
@onready var createSteam_btn: Button        = $SteamPart/CreateBtn
@onready var refresh_btn:     Button        = $SteamPart/RefreshBtn
@onready var rooms_vbox:      VBoxContainer = $SteamPart/RoomsVbox
@onready var statusSteam_lb:  Label         = $SteamPart/StatusLb

const MAX_MEMBERS := 4
const GAME_KEY    := "JUEGOMULTIPLAYER_V1"

var current_lobby_id: int  = 0
var pending_register:  bool = false
var host_peer_id:      int  = 1
var is_host:           bool = false
var max_player:        int  = 4
var players:           Dictionary = {}

# Semilla actual — 0 significa "aún no asignada"
var current_seed: int = 0

# ---------------------------------------------------------------------------
func _ready() -> void:
	start_btn.disabled = true

	create_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	random_btn.pressed.connect(_on_random_seed_pressed)
	seed_input.text_changed.connect(_on_seed_text_changed)

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

	# Solo el host puede editar la semilla
	_set_seed_ui_editable(false)

# ---------------------------------------------------------------------------
# Semilla
# ---------------------------------------------------------------------------
func _set_seed_ui_editable(editable: bool) -> void:
	seed_input.editable  = editable
	random_btn.disabled  = not editable
	seed_display.visible = not editable

func _on_random_seed_pressed() -> void:
	# Genera un número entre 10000 y 99999 para que sea legible
	var s: int = randi_range(10000, 99999)
	seed_input.text = str(s)
	_apply_seed(s)

func _on_seed_text_changed(new_text: String) -> void:
	if not is_host:
		return
	var s: int = new_text.to_int()
	if s > 0:
		_apply_seed(s)

func _apply_seed(s: int) -> void:
	current_seed       = s
	GameData.map_seed  = s
	# Sincronizar a todos los clientes
	if multiplayer.has_multiplayer_peer():
		rpc("sync_seed", s)

@rpc("any_peer", "call_local")
func sync_seed(s: int) -> void:
	current_seed      = s
	GameData.map_seed = s
	if not is_host:
		seed_display.text = "Semilla: %d" % s

# ---------------------------------------------------------------------------
# Host / Join
# ---------------------------------------------------------------------------
func _on_host_pressed() -> void:
	var player_name: String = name_input.text.strip_edges()
	if player_name == "":
		status_lb.text = "Pon un nombre antes de crear la partida"
		return

	var port: int = port_input.text.to_int()
	if port <= 0:
		status_lb.text = "Puerto inválido"
		return

	var err: int = NetworkManager.host_local(port, max_player)
	if err != OK:
		status_lb.text = "No se pudo crear el servidor"
		return

	host_peer_id = multiplayer.get_unique_id()
	is_host      = true
	status_lb.text = "Servidor (LOCAL) creado en %d. Esperando..." % port

	var my_id: int = multiplayer.get_unique_id()
	players[my_id] = player_name
	_refresh_player_ui()
	_broadcast_players()

	# Habilitar controles de semilla para el host y generar una automáticamente
	_set_seed_ui_editable(true)
	_on_random_seed_pressed()

func _on_join_pressed() -> void:
	var player_name: String = name_input.text.strip_edges()
	if player_name == "":
		status_lb.text = "Pon un nombre antes de unirte"
		return

	var ip:   String = ip_input.text.strip_edges()
	var port: int    = port_input.text.to_int()
	if port <= 0:
		status_lb.text = "Puerto inválido"
		return

	var err: int = NetworkManager.join_local(ip, port)
	if err != OK:
		status_lb.text = "No se pudo conectar"
		return

	is_host        = false
	status_lb.text = "Conectando (LOCAL) a %s:%d..." % [ip, port]
	_set_seed_ui_editable(false)

func _on_connected_to_server() -> void:
	status_lb.text = "Conectado. Registrando jugador..."
	var player_name: String = name_input.text.strip_edges()
	rpc_id(1, "register_player", player_name)

func _on_connection_failed() -> void:
	status_lb.text = "Falló la conexión al servidor"

func _on_server_disconected() -> void:
	status_lb.text = "Desconectado del servidor"
	players.clear()
	_refresh_player_ui()
	start_btn.disabled = true

func _on_peer_connected(id: int) -> void:
	if is_host:
		print("Peer conectado: ", id)
		# Enviar semilla actual al nuevo cliente
		if current_seed > 0:
			rpc_id(id, "sync_seed", current_seed)

	if pending_register and id == 1:
		pending_register = false
		var player_name: String = name_input.text.strip_edges()
		rpc_id(1, "register_player", player_name)

func _on_peer_disconnected(id: int) -> void:
	var pname: String = ""
	if players.has(id):
		pname = str(players[id])
		players.erase(id)
		_refresh_player_ui()
		_broadcast_players()

	if is_host:
		status_lb.text = "Jugador %s se ha desconectado" % (pname if pname != "" else str(id))

# ---------------------------------------------------------------------------
# Registro y sincronización de jugadores
# ---------------------------------------------------------------------------
@rpc("any_peer")
func register_player(player_name: String) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if players.size() >= max_player:
		return
	players[id]    = player_name
	status_lb.text = "Jugador %s se ha conectado" % player_name
	_broadcast_players()

func _broadcast_players() -> void:
	GameData.players = players.duplicate()
	rpc("sync_players", players)

@rpc("any_peer", "call_local")
func sync_players(p: Dictionary) -> void:
	players          = p.duplicate()
	GameData.players = players.duplicate()

	for child in player_list.get_children():
		child.queue_free()
	for id in players.keys():
		var label: Label = Label.new()
		label.text       = str(players[id])
		player_list.add_child(label)

	var count: int = players.size()
	start_btn.disabled = not (is_host and count >= 2 and count <= max_player)

func _refresh_player_ui() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for id in players.keys():
		var label: Label = Label.new()
		label.text       = str(players[id])
		player_list.add_child(label)

	var count: int = players.size()
	start_btn.disabled = not (is_host and count >= 2 and count <= max_player)

# ---------------------------------------------------------------------------
# Inicio de partida
# ---------------------------------------------------------------------------
func _on_start_pressed() -> void:
	if not is_host:
		return
	# Si no se eligió semilla, generar una ahora
	if current_seed == 0:
		_on_random_seed_pressed()
	# Sincronizar semilla final y arrancar
	rpc("start_game", current_seed)

@rpc("any_peer", "call_local")
func start_game(seed: int) -> void:
	GameData.map_seed = seed
	get_tree().change_scene_to_file("res://scene/mapa.tscn")

# ---------------------------------------------------------------------------
# Steam
# ---------------------------------------------------------------------------
func _on_create_steam_pressed() -> void:
	var player_name: String = name_input.text.strip_edges()
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
		statusSteam_lb.text = "No pude iniciar red Steam."
		return

	host_peer_id   = 1
	is_host        = true
	statusSteam_lb.text = "Sala Steam creada. Esperando..."

	var my_id: int = multiplayer.get_unique_id()
	players[my_id] = name_input.text.strip_edges()
	_refresh_player_ui()
	_broadcast_players()

	_set_seed_ui_editable(true)
	_on_random_seed_pressed()

func _on_refresh_pressed() -> void:
	_clear_rooms()
	statusSteam_lb.text = "Buscando salas Steam..."
	Steam.addRequestLobbyListStringFilter("game", GAME_KEY, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListResultCountFilter(50)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	statusSteam_lb.text = "Salas encontradas: %d" % lobbies.size()
	for lobby_id in lobbies:
		var lname: String = Steam.getLobbyData(lobby_id, "name")
		if lname == "":
			lname = "Lobby " + str(lobby_id)
		_add_room_row(lobby_id, lname, Steam.getNumLobbyMembers(lobby_id))

func _add_room_row(lobby_id: int, lobby_name: String, members: int) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var lbl: Label         = Label.new()
	lbl.text = "%s (%d/%d)" % [lobby_name, members, MAX_MEMBERS]
	var btn: Button = Button.new()
	btn.text = "Entrar"
	btn.pressed.connect(func():
		statusSteam_lb.text = "Entrando a %s..." % lobby_name
		Steam.joinLobby(lobby_id)
	)
	row.add_child(lbl)
	row.add_child(btn)
	rooms_vbox.add_child(row)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int) -> void:
	current_lobby_id    = lobby_id
	statusSteam_lb.text = "Dentro del lobby. Conectando a host..."
	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	if not NetworkManager.join_steam(host_steam_id):
		statusSteam_lb.text = "No pude unirme por Steam."
		return
	is_host          = false
	pending_register = true
	statusSteam_lb.text = "Conectado por Steam. Esperando al host..."
	_set_seed_ui_editable(false)

func _clear_rooms() -> void:
	for c in rooms_vbox.get_children():
		c.queue_free()
