extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D

const GRID_SIZE := 16

var player_ids: Array[int] = [] # se rellena desde GameData
var player_cities: Dictionary = {}  # player_id -> Vector2i


enum Terrain {
	CAMPO,
	CIUDAD,
	BOSQUE,
	AGUA,
	MONTANIA,
}

var map_data: Array = []
var city_positions : Array[Vector2i] = []
var city_count := 0

# Turnos
var turn_order: Array[int] = []
var current_turn_index: int = 0
var current_player_id: int = -1
var is_my_turn: bool = false


func _ready() -> void:
	randomize()

	player_ids = GameData.get_player_ids()
	print("Player IDs en mapa: ", player_ids)

	if multiplayer.is_server():
		print("SERVER: player_ids = ", player_ids)
		generate_map()
		assign_cities_to_players()
		start_turns()
		print("SERVER: turn_order = ", turn_order)

		if turn_order.is_empty():
			push_warning("SERVER: turn_order está vacío, no envío RPC")
			return

		rpc("sync_map_and_turns", map_data, player_cities, turn_order, current_turn_index)

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

	for y in range(map_data.size()):
		var row = map_data[y]
		for x in range(row.size()):
			var terrain: int = row[x]
			var source_id: int = -1

			match terrain:
				Terrain.CAMPO:
					source_id = 0  # Campo.png (ID 0)
				Terrain.BOSQUE:
					source_id = 1  # Bosque.png
				Terrain.MONTANIA:
					source_id = 2  # Montania.png
				Terrain.AGUA:
					source_id = 3  # Agua.png
				Terrain.CIUDAD:
					source_id = 4  # Ciudad.png

			if source_id != -1:
				tile_map.set_cell(0, Vector2i(x, y), source_id, Vector2i.ZERO)

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

func start_turns() -> void:
	if player_ids.is_empty():
		push_warning("No hay jugadores para los turnos.")
		return

	turn_order = player_ids.duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	_set_active_player(turn_order[current_turn_index])


func _set_active_player(player_id: int) -> void:
	current_player_id = player_id
	# en multijugador real el host haría rpc("sync_turn", current_player_id)
	_update_local_turn()


func _update_local_turn() -> void:
	var my_id := multiplayer.get_unique_id()
	is_my_turn = (my_id == current_player_id)
	print("Jugador ", my_id, " → es mi turno? ", is_my_turn)

func end_turn() -> void:
	if not multiplayer.is_server():
		# En clientes, pedimos al servidor que pase turno
		rpc_id(1, "request_end_turn")
		return

	# SOLO servidor llega aquí
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	_set_active_player(turn_order[current_turn_index])

	# Avisamos a todos del nuevo jugador activo
	rpc("sync_turn", current_player_id, current_turn_index)

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

	end_turn()  # Llama a la versión "server" de arriba


@rpc("any_peer", "call_local")
func sync_turn(new_player_id: int, new_turn_index: int) -> void:
	current_player_id = new_player_id
	current_turn_index = new_turn_index
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
