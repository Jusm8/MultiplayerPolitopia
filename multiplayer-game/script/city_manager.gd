## city_manager.gd
## Sistema de ciudades: asignación, captura y compra de unidades.
extends Node

signal city_captured(city_cell: Vector2i, new_owner: int)
signal unit_bought(city_cell: Vector2i, unit_id: int, buyer_id: int)

var map: Node = null

var unit_db: Array[Dictionary] = [
	{"name": "Soldado", "hp": 10, "dmg": 5,  "desc": "", "wood_cost": 10, "stone_cost": 5},
	{"name": "General", "hp": 25, "dmg": 8,  "desc": "", "wood_cost": 20, "stone_cost": 10},
	{"name": "Arquero", "hp": 10, "dmg": 5,  "desc": "", "wood_cost": 10, "stone_cost": 5},
	{"name": "Tanque",  "hp": 55, "dmg": 10, "desc": "", "wood_cost": 50, "stone_cost": 40},
]

var player_cities:         Dictionary = {}
var city_owner_by_key:     Dictionary = {}
var city_capture_pending:  Dictionary = {}
var city_bought_this_turn: Dictionary = {}

# ---------------------------------------------------------------------------
func assign_cities_to_players(city_positions: Array[Vector2i], player_ids: Array[int]) -> void:
	if city_positions.size() < player_ids.size():
		push_warning("CityManager: no hay suficientes ciudades.")
		return

	var shuffled: Array = city_positions.duplicate()
	shuffled.shuffle()

	player_cities.clear()
	city_owner_by_key.clear()
	city_capture_pending.clear()

	for i in range(player_ids.size()):
		var pid:  int      = player_ids[i]
		var cell: Vector2i = shuffled[i]
		player_cities[pid]                   = cell
		city_owner_by_key[MapData.cell_key(cell)] = pid

	print("CityManager: ciudades =", player_cities)

func receive_initial_state(remote_player_cities: Dictionary, remote_city_owners: Dictionary) -> void:
	player_cities     = remote_player_cities.duplicate()
	city_owner_by_key = remote_city_owners.duplicate(true)

# ---------------------------------------------------------------------------
func get_city_count_for_player(player_id: int) -> int:
	var count: int = 0
	for key in city_owner_by_key.keys():
		if int(city_owner_by_key[key]) == player_id:
			count += 1
	return count

func get_city_owner(cell: Vector2i) -> int:
	var key: String = MapData.cell_key(cell)
	if not city_owner_by_key.has(key):
		return -1
	return int(city_owner_by_key[key])

func try_open_city_menu(cell: Vector2i) -> void:
	var my_id: int    = multiplayer.get_unique_id()
	var key:   String = MapData.cell_key(cell)

	if not city_owner_by_key.has(key) or int(city_owner_by_key[key]) != my_id:
		return

	var r:       Dictionary = map.economy_manager.get_resources(my_id)
	var can_buy: bool       = not city_bought_this_turn.has(key)
	map.city_menu.open_for_city(cell, unit_db, int(r["wood"]), int(r["stone"]), can_buy)

# ---------------------------------------------------------------------------
func _on_buy_requested(city_cell: Vector2i, unit_id: int) -> void:
	if not map.turn_manager.is_my_turn():
		return
	if multiplayer.is_server():
		request_buy_unit(city_cell, unit_id)
	else:
		rpc_id(1, "request_buy_unit", city_cell, unit_id)

@rpc("any_peer")
func request_buy_unit(city_cell: Vector2i, unit_id: int) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()

	if sender != map.turn_manager.current_player_id:
		rpc_id(sender, "_client_show_error", "No es tu turno")
		return

	if map.get_terrain_at(city_cell) != MapData.Terrain.VILLA:
		return

	var key: String = MapData.cell_key(city_cell)
	if city_bought_this_turn.has(key):
		rpc_id(sender, "_client_show_error", "Ya compraste en esta ciudad este turno")
		return

	if unit_id < 0 or unit_id >= unit_db.size():
		return

	var u:          Dictionary = unit_db[unit_id]
	var wood_cost:  int        = int(u.get("wood_cost", 0))
	var stone_cost: int        = int(u.get("stone_cost", 0))

	if not map.economy_manager.spend(sender, wood_cost, stone_cost):
		rpc_id(sender, "_client_show_error", "Recursos insuficientes")
		return

	city_bought_this_turn[key] = true

	map.unit_manager.rpc("spawn_unit", sender, unit_id, city_cell)
	rpc("sync_city_bought", city_bought_this_turn)
	map.economy_manager.rpc("sync_economy",
		map.economy_manager.player_resources,
		map.economy_manager.player_income,
		map.turn_manager.round_number
	)
	unit_bought.emit(city_cell, unit_id, sender)

@rpc("authority", "call_local")
func _client_show_error(msg: String) -> void:
	map.hud.show_error(msg)

# ---------------------------------------------------------------------------
@rpc("any_peer", "call_local")
func sync_city_bought(remote_dict: Dictionary) -> void:
	city_bought_this_turn = remote_dict.duplicate(true)

	if map.city_menu.visible:
		var my_id:   int        = multiplayer.get_unique_id()
		var r:       Dictionary = map.economy_manager.get_resources(my_id)
		var cell:    Vector2i   = map.city_menu.get_city_cell()
		var key:     String     = MapData.cell_key(cell)
		var can_buy: bool       = not city_bought_this_turn.has(key)
		map.city_menu.open_for_city(cell, unit_db, int(r["wood"]), int(r["stone"]), can_buy)

# ---------------------------------------------------------------------------
func server_process_city_captures() -> void:
	if not multiplayer.is_server():
		return

	for city_cell: Vector2i in map.city_positions:
		var key: String = MapData.cell_key(city_cell)
		if not city_owner_by_key.has(key):
			continue

		var owner:    int        = int(city_owner_by_key[key])
		var units_by: Dictionary = map.unit_manager.units_by_cell

		if units_by.has(key):
			var u: Unit = units_by[key]
			if u == null:
				city_capture_pending.erase(key)
				continue

			var occupier: int = int(u.owner_id)

			if occupier != owner:
				if city_capture_pending.has(key) and int(city_capture_pending[key]) == occupier:
					city_owner_by_key[key] = occupier
					city_capture_pending.erase(key)
					if not player_cities.has(occupier):
						player_cities[occupier] = city_cell
					print("CityManager: CAPTURA", key, "→", occupier)
					city_captured.emit(city_cell, occupier)
				else:
					city_capture_pending[key] = occupier
			else:
				city_capture_pending.erase(key)
		else:
			city_capture_pending.erase(key)

	rpc("sync_city_owners", city_owner_by_key)

@rpc("any_peer", "call_local")
func sync_city_owners(remote: Dictionary) -> void:
	city_owner_by_key = remote.duplicate(true)

# ---------------------------------------------------------------------------
func on_new_turn_started() -> void:
	if not multiplayer.is_server():
		return
	city_bought_this_turn.clear()
	rpc("sync_city_bought", city_bought_this_turn)
