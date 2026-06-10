## turn_manager.gd
## Sistema de turnos: orden, rondas, jugadores eliminados y fin de partida.
## Nodo hijo de la escena mapa. Se comunica hacia afuera solo con señales.
extends Node

# ---------------------------------------------------------------------------
# Señales
# ---------------------------------------------------------------------------
signal turn_changed(player_id: int)       ## El turno pasó a este jugador
signal player_eliminated(pid: int)        ## Este jugador fue eliminado
signal game_over(winner_id: int)          ## Partida terminada

# ---------------------------------------------------------------------------
# Referencia al coordinador (inyectada por mapa.gd en _ready)
# ---------------------------------------------------------------------------
var map: Node = null

# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------
var turn_order:          Array[int] = []
var current_turn_index:  int        = 0
var current_player_id:   int        = -1
var round_number:        int        = 1
var eliminated_players:  Dictionary = {}
var game_over_flag:      bool       = false
var winner_id:           int        = -1

# ---------------------------------------------------------------------------
# Arranque (llamado por mapa.gd solo en el servidor)
# ---------------------------------------------------------------------------
func start_turns(player_ids: Array[int]) -> void:
	if player_ids.is_empty():
		push_warning("TurnManager: no hay jugadores.")
		return

	turn_order           = player_ids.duplicate()
	turn_order.shuffle()
	current_turn_index   = 0
	round_number         = 1
	_set_active_player(turn_order[0])

# ---------------------------------------------------------------------------
# Estado inicial recibido por clientes via RPC de mapa.gd
# ---------------------------------------------------------------------------
func receive_initial_state(remote_turn_order: Array, remote_turn_index: int) -> void:
	turn_order          = remote_turn_order.duplicate()
	current_turn_index  = remote_turn_index
	if turn_order.is_empty():
		push_warning("TurnManager: turn_order vacío en receive_initial_state.")
		return
	current_player_id = turn_order[current_turn_index]
	_emit_turn_changed()

# ---------------------------------------------------------------------------
# Fin de turno — entrada desde el HUD (solo el jugador activo puede llamarlo)
# ---------------------------------------------------------------------------
func _on_end_turn_requested() -> void:
	if not multiplayer.is_server():
		rpc_id(1, "request_end_turn")
		return
	_server_advance_turn(multiplayer.get_unique_id())

@rpc("any_peer")
func request_end_turn() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != current_player_id:
		return
	_server_advance_turn(sender)

# ---------------------------------------------------------------------------
# Lógica de avance de turno (solo servidor)
# ---------------------------------------------------------------------------
func _server_advance_turn(_sender: int) -> void:
	# Economía del jugador que acaba
	map.economy_manager.apply_end_turn_income(current_player_id)

	# Capturas de ciudad
	map.city_manager.server_process_city_captures()

	# Eliminar jugadores sin ciudades
	_server_prune_eliminated_players()

	if game_over_flag:
		return

	# Avanzar índice
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	if current_turn_index == 0:
		round_number += 1

	_set_active_player(turn_order[current_turn_index])

	# Limpiar compras de ciudad del turno anterior
	map.city_manager.on_new_turn_started()

	# Sincronizar a todos
	rpc("sync_turn", current_player_id, current_turn_index, round_number)
	rpc("economy_manager/sync_economy",
		map.economy_manager.player_resources,
		map.economy_manager.player_income,
		round_number
	)

func _set_active_player(player_id: int) -> void:
	current_player_id = player_id
	_emit_turn_changed()

func _emit_turn_changed() -> void:
	turn_changed.emit(current_player_id)

# ---------------------------------------------------------------------------
# Eliminación de jugadores sin ciudades (solo servidor)
# ---------------------------------------------------------------------------
func _server_prune_eliminated_players() -> void:
	var alive: Array[int] = []
	for pid in turn_order:
		if map.city_manager.get_city_count_for_player(pid) > 0:
			alive.append(pid)
		else:
			if not eliminated_players.has(pid):
				eliminated_players[pid] = true
				print("TurnManager: ELIMINADO =", pid)
				rpc("sync_player_eliminated", pid)

	turn_order = alive

	if turn_order.is_empty():
		return

	if turn_order.size() == 1 and not game_over_flag:
		game_over_flag = true
		winner_id      = int(turn_order[0])
		rpc("sync_game_over", winner_id)
		return

	# Reajustar índice si el jugador actual fue eliminado
	if not (current_player_id in turn_order):
		current_turn_index = current_turn_index % turn_order.size()
		current_player_id  = turn_order[current_turn_index]
	else:
		current_turn_index = turn_order.find(current_player_id)

	rpc("sync_turn_order", turn_order)

# ---------------------------------------------------------------------------
# RPCs de sincronización
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_local")
func sync_turn(new_player_id: int, new_turn_index: int, new_round: int) -> void:
	current_player_id  = new_player_id
	current_turn_index = new_turn_index
	round_number       = new_round
	_emit_turn_changed()

@rpc("any_peer", "call_local")
func sync_turn_order(remote_order: Array) -> void:
	turn_order = remote_order.duplicate()

@rpc("any_peer", "call_local")
func sync_player_eliminated(pid: int) -> void:
	eliminated_players[pid] = true
	player_eliminated.emit(pid)

@rpc("any_peer", "call_local")
func sync_game_over(winner: int) -> void:
	game_over_flag = true
	winner_id      = winner
	game_over.emit(winner_id)

# ---------------------------------------------------------------------------
# Helpers públicos
# ---------------------------------------------------------------------------
func is_my_turn() -> bool:
	return multiplayer.get_unique_id() == current_player_id

func is_eliminated(player_id: int) -> bool:
	return eliminated_players.has(player_id)
