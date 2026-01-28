extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera
@onready var hud: HUD = $HUD
@onready var city_menu: CityMenu = $HUD/CityMenu
@onready var units_layer: Node2D = $UnitsLayer

const UNIT_SCENE := preload("res://scene/Units.tscn")
const GRID_SIZE := 16

const  TERRAIN_ATLAS := {
	Terrain.CAMPO: [Vector2i(1, 0), Vector2i(6, 0)],
	Terrain.BOSQUE: Vector2i(2, 0),
	Terrain.AGUA: Vector2i(3, 0),
	Terrain.CIUDAD: Vector2i(4, 0),
	Terrain.MONTANIA: Vector2i(5, 0),
}

const ATLAS_SOURCE_ID := 0

# Recursos de los jugadores
const START_WOOD := 10
const START_STONE := 5
const DEFAULT_WOOD_INCOME := 10
const DEFAULT_STONE_INCOME:= 5

enum Terrain {
	CAMPO,
	CIUDAD,
	BOSQUE,
	AGUA,
	MONTANIA,
}

var atlas_source_id: int = -1
var round_number: int = 1
var player_ids: Array[int] = [] # se rellena desde GameData
var player_cities: Dictionary = {}  # player_id -> Vector2i

var atlas_source: TileSetAtlasSource

var map_data: Array = []
var city_positions : Array[Vector2i] = []
var city_count := 0

# Turnos
var turn_order: Array[int] = []
var current_turn_index: int = 0
var current_player_id: int = -1
var is_my_turn: bool = false

# Recursos por jugador
var player_resources := {} # player_id -> "wood: int, "stone": int}

# Produccion por turno (modificable para cada partida)
var player_income := {} # player_id-> {"wood": int, "stone": int}

var unit_db:Array[Dictionary]= [
	{"name":"Soldado", "hp":10, "dmg":5, "desc":"", "wood_cost":10, "stone_cost": 5},
	{"name":"General", "hp":25, "dmg":8, "desc":"", "wood_cost":20, "stone_cost": 10},
	{"name":"Arquero", "hp":10, "dmg":5, "desc":"", "wood_cost":10, "stone_cost": 5},
	{"name":"Tanque", "hp":55, "dmg":10, "desc":"", "wood_cost":50, "stone_cost":40}
]

# city_key -> true (compró ya este turno)
var city_bought_this_turn: Dictionary = {}

var units_by_cell: Dictionary = {}  # x,y -> Unit

func _ready() -> void:
	randomize()

	#  Detectar el AtlasSource del TileSet automáticamente
	var ts := tile_map.tile_set
	if ts == null:
		push_error("TileMap NO tiene TileSet asignado.")
		return

	atlas_source_id = -1
	atlas_source = null

	for i in range(ts.get_source_count()):
		var id := ts.get_source_id(i)
		var src := ts.get_source(id)
		if src is TileSetAtlasSource:
			atlas_source_id = id
			atlas_source = src
			break

	if atlas_source_id == -1 or atlas_source == null:
		push_error("No hay TileSetAtlasSource en el TileSet (no es un atlas).")
		return

	print("Atlas source id detectado: ", atlas_source_id)

	# IDs jugadores
	player_ids = GameData.get_player_ids()
	print("Player IDs en mapa: ", player_ids)

	# CityMenu
	if city_menu == null:
		push_error("CityMenu no esta instanciado en HUD")
		return

	city_menu.buy_requested.connect(_on_city_menu_buy_requested)
	city_menu.closed.connect(_on_city_menu_closed)

	# HUD 
	hud.end_turn_confirmed.connect(_on_hud_end_turn_confirmed)

	# Solo el servidor genera el mapa y sincroniza
	if multiplayer.is_server():
		print("SERVER: player_ids = ", player_ids)

		generate_map()
		assign_cities_to_players()
		start_turns()
		_init_player_economy()

		# Enviar todo a los clientes
		rpc("sync_map_and_turns", map_data, player_cities, turn_order, current_turn_index)
		rpc("sync_economy", player_resources, player_income, round_number)

		print("SERVER: turn_order = ", turn_order)

		draw_map()
		center_map()
		_debug_print_map()
		_focus_camera_on_my_city()

		if turn_order.is_empty():
			push_warning("SERVER: turn_order está vacío, no envío RPC")
			return

func _on_hud_end_turn_confirmed() -> void:
	end_turn()

func generate_map() -> void:
	map_data.clear()
	city_positions.clear()
	city_count = 0

	for y in range(GRID_SIZE):
		map_data.append([])
		for x in range(GRID_SIZE):
			var terrain := _random_terrain()
			map_data[y].append(terrain)

			if terrain == Terrain.CIUDAD:
				city_positions.append(Vector2i(x, y))

	print("Ciudades generadas: ", city_count, " / posiciones: ", city_positions.size())

func _random_terrain() -> int:
	var r := randf()

	if city_count < 8:
		if r < 0.50:
			return Terrain.CAMPO
		elif r < 0.70:
			return Terrain.BOSQUE
		elif r < 0.85:
			return Terrain.MONTANIA
		elif r < 0.95:
			return Terrain.AGUA
		else:
			city_count += 1
			return Terrain.CIUDAD
	else:
		if r < 0.55:
			return Terrain.CAMPO
		elif r < 0.75:
			return Terrain.BOSQUE
		elif r < 0.90:
			return Terrain.MONTANIA
		else:
			return Terrain.AGUA

func _debug_print_map() -> void:
	if map_data.is_empty():
		print("debug_print_map: map_data vacío, no imprimo nada.")
		return

	for y in range(map_data.size()):
		var row = map_data[y]
		var line := ""
		for x in range(row.size()):
			match row[x]:
				Terrain.CAMPO:
					line += "C "
				Terrain.CIUDAD:
					line += "X "
				Terrain.BOSQUE:
					line += "B "
				Terrain.AGUA:
					line += "A "
				Terrain.MONTANIA:
					line += "M "
		print(line)

func draw_map() -> void:
	tile_map.clear()

	if map_data.is_empty():
		push_warning("draw_map: map_data esta vacio, no dibujo nada")
		return

	if atlas_source_id == -1 or atlas_source == null:
		push_error("draw_map: atlas_source no inicializado.")
		return

	for y in range(map_data.size()):
		var row = map_data[y]
		for x in range(row.size()):
			var terrain: int = int(row[x])
			if not TERRAIN_ATLAS.has(terrain):
				continue
	
			var atlas_coords: Vector2i
	
			if terrain == Terrain.CAMPO:
				var options: Array = TERRAIN_ATLAS[terrain] # [Vector2i(1,0), Vector2i(6,0)]
				var pick := int(abs(hash(Vector2i(x, y))) % options.size()) # estable
				atlas_coords = options[pick]
			else:
				atlas_coords = TERRAIN_ATLAS[terrain]
	
			if not atlas_source.has_tile(atlas_coords):
				push_warning("No existe tile en atlas_coords=%s para terrain=%s" % [str(atlas_coords), str(terrain)])
				continue
	
			tile_map.set_cell(0, Vector2i(x, y), atlas_source_id, atlas_coords, 0)

func center_map() -> void:
	var used: Rect2i = tile_map.get_used_rect()

	var top_left: Vector2 = tile_map.map_to_local(used.position)
	var bottom_right: Vector2 = tile_map.map_to_local(used.position + used.size)

	var map_size: Vector2 = bottom_right - top_left
	var viewport_size: Vector2 = get_viewport_rect().size

	tile_map.position = viewport_size * 0.5 - map_size * 0.5 - top_left

func assign_cities_to_players() -> void:
	if city_positions.size() < player_ids.size():
		push_warning("No hay suficientes ciudades para todos los jugadores.")
		return

	var shuffled := city_positions.duplicate()
	shuffled.shuffle()

	player_cities.clear()
	for i in range(player_ids.size()):
		var pid := player_ids[i]
		var cell : Vector2i = shuffled[i]
		player_cities[pid] = cell

	print("Ciudades por jugador: ", player_cities)

func _get_city_count_for_player(player_id: int) -> int:
	var count := 0

	for owner_id in player_cities.keys():
		if owner_id == player_id:
			count += 1

	return count

func start_turns() -> void:
	if player_ids.is_empty():
		push_warning("No hay jugadores para los turnos.")
		return

	turn_order = player_ids.duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	round_number = 1
	_set_active_player(turn_order[current_turn_index])

func _set_active_player(player_id: int) -> void:
	current_player_id = player_id
	# en multijugador real el host haría rpc("sync_turn", current_player_id)
	_update_local_turn()

func _update_local_turn() -> void:
	var my_id := multiplayer.get_unique_id()
	is_my_turn = (my_id == current_player_id)
	print("Jugador ", my_id, " → es mi turno? ", is_my_turn)

	# Nombre del jugador actual (desde GameData)
	var current_name := ""
	if GameData.players.has(current_player_id):
		current_name = str(GameData.players[current_player_id])
	else:
		current_name = "Jugador %s" % str(current_player_id)

	var cities : int = _get_city_count_for_player(current_player_id)
	var wood: int = 0
	var stone: int = 0
	if player_resources.has(current_player_id):
		wood = int(player_resources[current_player_id]["wood"])
		stone = int(player_resources[current_player_id]["stone"])

	hud.set_current_player(current_name, is_my_turn)
	hud.set_round(round_number)
	hud.set_player_stats(cities, wood, stone)
@rpc("any_peer", "call_local")
func sync_economy(remote_resources: Dictionary, remote_income: Dictionary, remote_round: int) -> void:
	player_resources = remote_resources.duplicate(true)
	player_income = remote_income.duplicate(true)
	round_number = remote_round
	_update_local_turn()

	# Si el menú está abierto, refrescarlo con recursos nuevos
	if city_menu.visible:
		var my_id := multiplayer.get_unique_id()
		var wood := int(player_resources.get(my_id, {"wood": 0})["wood"])
		var stone := int(player_resources.get(my_id, {"stone": 0})["stone"])

		var cell := city_menu.get_city_cell()
		var key := _city_key(cell) 
		var can_buy_here := not city_bought_this_turn.has(key)

		city_menu.open_for_city(cell, unit_db, wood, stone, can_buy_here)

func end_turn() -> void:
	if not multiplayer.is_server():
		rpc_id(1, "request_end_turn")
		return

	# Solo puede pasar turno el jugador al que le toca
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != current_player_id:
		return

	_apply_end_turn_income(current_player_id)

	current_turn_index = (current_turn_index + 1) % turn_order.size()
	if current_turn_index == 0:
		round_number += 1

	_set_active_player(turn_order[current_turn_index])
	if multiplayer.is_server():
		_on_new_turn_started()

	rpc("sync_turn", current_player_id, current_turn_index, round_number)
	rpc("sync_economy", player_resources, player_income, round_number)

@rpc("any_peer", "call_local")
func sync_map_and_turns(
		remote_map_data: Array,
		remote_player_cities: Dictionary,
		remote_turn_order: Array,
		remote_current_turn_index: int
	) -> void:

	# Si viene vacío, no hacemos nada para evitar crasheos
	if remote_map_data.is_empty():
		push_warning("sync_map_and_turns: remote_map_data está vacío, no sincronizo.")
		return

	# Copiamos datos del mapa (¡sin usar clear!, creamos un array nuevo)
	map_data = []
	for row in remote_map_data:
		map_data.append(row.duplicate())

	# Reconstruimos posiciones de ciudades
	city_positions.clear()
	city_count = 0
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			if map_data[y][x] == Terrain.CIUDAD:
				city_positions.append(Vector2i(x, y))
				city_count += 1

	# Ciudades por jugador
	player_cities = remote_player_cities.duplicate()

	# Turnos
	turn_order = remote_turn_order.duplicate()
	current_turn_index = remote_current_turn_index

	if turn_order.is_empty():
		push_warning("sync_map_and_turns: turn_order vacío, no puedo establecer jugador actual.")
	else:
		current_player_id = turn_order[current_turn_index]
		_update_local_turn()

	draw_map()
	center_map()
	_debug_print_map()

	print("Mapa y turnos sincronizados. Turn order: ", turn_order)

@rpc("any_peer")
func request_end_turn() -> void:
	# Solo el host hace caso
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != current_player_id:
		return # si no es su turno fuera
	end_turn()  # Llama a la versión "server" de arriba

@rpc("any_peer", "call_local")
func sync_turn(new_player_id: int, new_turn_index: int, new_round: int) -> void:
	current_player_id = new_player_id
	current_turn_index = new_turn_index
	round_number = new_round
	_update_local_turn()
	_focus_camera_on_my_city()

func _focus_camera_on_my_city() -> void:
	var my_id := multiplayer.get_unique_id()
	if not player_cities.has(my_id):
		return

	var cell: Vector2i = player_cities[my_id]
	# Convertimos celda → posición local del TileMap
	var world_pos: Vector2 = tile_map.map_to_local(cell)
	# Como la cámara es hija de mapa, están en el mismo espacio
	camera.position = world_pos

func _unhandled_input(event: InputEvent) -> void:
	if not is_my_turn:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 1) mundo (con cámara ya aplicada)
		var world_pos: Vector2 = get_global_mouse_position()

		# 2) mundo -> local del tilemap
		var local_pos: Vector2 = tile_map.to_local(world_pos)

		# 3) local -> celda del tilemap
		var cell: Vector2i = tile_map.local_to_map(local_pos)

		# 4) validar dentro del array
		if cell.y < 0 or cell.y >= map_data.size():
			return
		if cell.x < 0 or cell.x >= map_data[cell.y].size():
			return

		var terrain: int = int(map_data[cell.y][cell.x])

		# filtro rombo iso
		if not _is_point_inside_iso_cell(local_pos, cell):
			return

		hud.set_selected_tile(cell, terrain)

		if terrain == Terrain.CIUDAD:
			_open_city_menu(cell)


func _is_point_inside_iso_cell(local_pos: Vector2, cell: Vector2i) -> bool:
	# Posición local del centro de la celda
	var cell_local: Vector2 = tile_map.map_to_local(cell)

	# Offset del punto respecto al centro de la celda
	var d: Vector2 = local_pos - cell_local

	# Tamaño del tile (en píxeles) -> saca el tile_size del TileSet del TileMap
	var ts: Vector2i = tile_map.tile_set.tile_size
	var hw := float(ts.x) * 0.5
	var hh := float(ts.y) * 0.5

	# Ecuación del rombo isométrico: |x/hw| + |y/hh| <= 1
	return (abs(d.x) / hw + abs(d.y) / hh) <= 1.0

func _init_player_economy() -> void:
	player_resources.clear()
	player_income.clear()
	
	for pid in player_ids:
		player_resources[pid] = { "wood": START_WOOD, "stone": START_STONE}
		player_income[pid] = {"wood": DEFAULT_WOOD_INCOME, "stone": DEFAULT_STONE_INCOME}

func _apply_end_turn_income(player_id: int) -> void:
	if not player_resources.has(player_id) or not player_income.has(player_id):
		return

	player_resources[player_id]["wood"] += int(player_income[player_id]["wood"])
	player_resources[player_id]["stone"] += int(player_income[player_id]["stone"])

func _city_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _on_new_turn_started() -> void:
	if multiplayer.is_server():
		city_bought_this_turn.clear()
		rpc("sync_city_bought", city_bought_this_turn)

func _open_city_menu(cell: Vector2i) -> void:
	var my_id := multiplayer.get_unique_id()

	# Solo tu ciudad 
	if not player_cities.has(my_id) or player_cities[my_id] != cell:
		return

	var wood := int(player_resources.get(my_id, {"wood": 0})["wood"])
	var stone := int(player_resources.get(my_id, {"stone": 0})["stone"])

	var key := _city_key(cell)
	var can_buy_here := not city_bought_this_turn.has(key)

	city_menu.open_for_city(cell, unit_db, wood, stone, can_buy_here)

func _on_city_menu_buy_requested(city_cell: Vector2i, unit_id: int) -> void:
	if not is_my_turn:
		return
	
	var my_id := multiplayer.get_unique_id()
	var wood := int(player_resources.get(my_id, {"wood": 0})["wood"])
	var stone := int(player_resources.get(my_id, {"stone": 0})["stone"])
	var u: Dictionary = unit_db[unit_id]
	if wood < int(u.get("wood_cost", 0)) or stone < int(u.get("stone_cost", 0)):
		hud.show_error("Recursos insuficientes")
		return
	
	# Pedimos al servidor que haga la compra dependiendo de si es el host o cliente
	if multiplayer.is_server():
		request_buy_unit(city_cell, unit_id)
	else:
		rpc_id(1, "request_buy_unit", city_cell, unit_id)

func _on_city_menu_closed() -> void:
	pass

@rpc("any_peer")
func request_buy_unit(city_cell: Vector2i, unit_id: int) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()

	# Detectamos cuando el host llama 
	if sender == 0:
		sender = multiplayer.get_unique_id()
	
	# Solo el jugador del turno puede comprar
	if sender != current_player_id:
		rpc_id(sender, "client_show_error", "No es tu turno")
		return

	# Solo si es ciudad
	if city_cell.y < 0 or city_cell.y >= map_data.size():
		return
	if city_cell.x < 0 or city_cell.x >= map_data[city_cell.y].size():
		return
	if int(map_data[city_cell.y][city_cell.x]) != Terrain.CIUDAD:
		return

	# Una compra por ciudad y por turno
	var key := _city_key(city_cell)
	if city_bought_this_turn.has(key):
		rpc_id(sender, "client_show_error", "Ya compraste en esta ciudad este turno")
		return

	# Unit id válido
	if unit_id < 0 or unit_id >= unit_db.size():
		return
	var u: Dictionary = unit_db[unit_id]

	var wood_cost := int(u.get("wood_cost", 0))
	var stone_cost := int(u.get("stone_cost", 0))

	# Recursos suficientes
	if not player_resources.has(sender):
		return

	var wood := int(player_resources[sender]["wood"])
	var stone := int(player_resources[sender]["stone"])

	if wood < wood_cost or stone < stone_cost:
		rpc_id(sender, "client_show_error", "Recursos insuficientes")
		return

	# Descontar recursos
	player_resources[sender]["wood"] = wood - wood_cost
	player_resources[sender]["stone"] = stone - stone_cost

	# Marcar ciudad como comprada este turno
	city_bought_this_turn[key] = true
	rpc("spawn_unit", sender, unit_id, city_cell)

	# Sincronizar
	rpc("sync_economy", player_resources, player_income, round_number)
	rpc("sync_city_bought", city_bought_this_turn)
	
@rpc("any_peer", "call_local")
func spawn_unit(owner_id: int, unit_id: int, cell: Vector2i) -> void:
	_spawn_unit_local(owner_id, unit_id, cell)

@rpc("any_peer", "call_local")
func sync_city_bought(remote_dict: Dictionary) -> void:
	city_bought_this_turn = remote_dict.duplicate(true)
	if city_menu.visible:
		var my_id := multiplayer.get_unique_id()
		var wood := int(player_resources.get(my_id, {"wood": 0})["wood"])
		var stone := int(player_resources.get(my_id, {"stone": 0})["stone"])
		var cell := city_menu.get_city_cell()
		var key := _city_key(cell)
		var can_buy_here := not city_bought_this_turn.has(key)
		city_menu.open_for_city(cell, unit_db, wood, stone, can_buy_here)

@rpc("authority", "call_local")
func client_show_error(msg: String) -> void:
	hud.show_error(msg)

func _cell_to_world(cell: Vector2i) -> Vector2:
	var local_pos := tile_map.map_to_local(cell)
	return tile_map.to_global(local_pos)

func _spawn_unit_local(owner_id: int, unit_id: int, cell: Vector2i) -> void:
	var key := _city_key(cell)
	
	# Si hay una unidad en esa casilla evitamos duplicados
	if units_by_cell.has(key):
		return
	
	var u: Unit = UNIT_SCENE.instantiate()
	units_layer.add_child(u)
	
	u.atlas_texture = preload("res://assets/SoldadosMultiplayer.png")
	
	u.setup(owner_id, unit_id, cell)
	# Poscicionar encima de la tile
	u.global_position = _cell_to_world(cell) + u.base_offset
	u.z_index = cell.y * 100 + cell.x
	units_by_cell[key] = u
