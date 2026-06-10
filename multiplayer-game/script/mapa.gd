## mapa.gd
## Coordinador de la escena de juego.
extends Node2D

# ---------------------------------------------------------------------------
# Referencias a nodos
# ---------------------------------------------------------------------------
@onready var tile_map:     TileMap  = $TileMap
@onready var camera:       Camera2D = $Camera
@onready var hud:          HUD      = $HUD
@onready var city_menu:    CityMenu = $HUD/CityMenu
@onready var units_layer:  Node2D   = $TileMap/UnitsLayer

@onready var turn_manager:    Node = $TurnManager
@onready var economy_manager: Node = $EconomyManager
@onready var unit_manager:    Node = $UnitManager
@onready var city_manager:    Node = $CityManager
@onready var input_handler:   Node = $InputHandler

# ---------------------------------------------------------------------------
# Estado del mapa
# ---------------------------------------------------------------------------
var map_data:       Array            = []
var city_positions: Array[Vector2i]  = []
var city_count:     int              = 0
var player_ids:     Array[int]       = []

var atlas_source_id: int                = -1
var atlas_source:    TileSetAtlasSource = null

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()

	var ts := tile_map.tile_set
	if ts == null:
		push_error("mapa: TileMap sin TileSet asignado.")
		return

	for i in range(ts.get_source_count()):
		var id  := ts.get_source_id(i)
		var src := ts.get_source(id)
		if src is TileSetAtlasSource:
			atlas_source_id = id
			atlas_source    = src as TileSetAtlasSource
			break

	if atlas_source_id == -1:
		push_error("mapa: no hay TileSetAtlasSource en el TileSet.")
		return

	print("mapa: atlas_source_id =", atlas_source_id)

	player_ids = GameData.get_player_ids()
	print("mapa: player_ids =", player_ids)

	# Inyectar referencia del mapa en todos los sistemas
	turn_manager.map    = self
	economy_manager.map = self
	unit_manager.map    = self
	city_manager.map    = self
	input_handler.map   = self

	_connect_signals()

	if multiplayer.is_server():
		_server_start_game()

# ---------------------------------------------------------------------------
# Arranque servidor
# ---------------------------------------------------------------------------
func _server_start_game() -> void:
	print("mapa SERVER: arrancando partida")
	generate_map()
	city_manager.assign_cities_to_players(city_positions, player_ids)
	turn_manager.start_turns(player_ids)
	economy_manager.init_player_economy(player_ids)

	rpc("sync_map_and_turns",
		map_data,
		city_manager.player_cities,
		turn_manager.turn_order,
		turn_manager.current_turn_index,
		city_manager.city_owner_by_key
	)
	economy_manager.rpc("sync_economy",
		economy_manager.player_resources,
		economy_manager.player_income,
		turn_manager.round_number
	)

	draw_map()
	center_map()
	_debug_print_map()
	_focus_camera_on_my_city()

# ---------------------------------------------------------------------------
# Señales
# ---------------------------------------------------------------------------
func _connect_signals() -> void:
	hud.end_turn_confirmed.connect(turn_manager._on_end_turn_requested)

	turn_manager.turn_changed.connect(_on_turn_changed)
	turn_manager.player_eliminated.connect(_on_player_eliminated)
	turn_manager.game_over.connect(_on_game_over)

	economy_manager.resources_updated.connect(_on_resources_updated)
	city_manager.city_captured.connect(_on_city_captured)
	city_menu.buy_requested.connect(city_manager._on_buy_requested)

func _on_turn_changed(player_id: int) -> void:
	var name_str: String
	if GameData.players.has(player_id):
		name_str = str(GameData.players[player_id])
	else:
		name_str = "Jugador %s" % str(player_id)

	var my_id:    int  = multiplayer.get_unique_id()
	var is_my:    bool = (my_id == player_id)
	var cities:   int  = city_manager.get_city_count_for_player(player_id)
	var res:      Dictionary = economy_manager.get_resources(player_id)

	hud.set_current_player(name_str, is_my)
	hud.set_round(turn_manager.round_number)
	hud.set_player_stats(cities, int(res.get("wood", 0)), int(res.get("stone", 0)))
	_focus_camera_on_my_city()

func _on_resources_updated(player_id: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	if player_id != my_id:
		return
	var res:    Dictionary = economy_manager.get_resources(my_id)
	var cities: int        = city_manager.get_city_count_for_player(my_id)
	hud.set_player_stats(cities, int(res.get("wood", 0)), int(res.get("stone", 0)))

func _on_player_eliminated(pid: int) -> void:
	if pid == multiplayer.get_unique_id():
		_show_end_screen(false, true)

func _on_game_over(winner: int) -> void:
	_show_end_screen(multiplayer.get_unique_id() == winner, false)

func _on_city_captured(_city_cell: Vector2i, _new_owner: int) -> void:
	pass

# ---------------------------------------------------------------------------
# Generación del mapa
# ---------------------------------------------------------------------------
func generate_map() -> void:
	map_data.clear()
	city_positions.clear()
	city_count = 0

	for y in range(MapData.GRID_SIZE):
		map_data.append([])
		for x in range(MapData.GRID_SIZE):
			var terrain := _random_terrain()
			map_data[y].append(terrain)
			if terrain == MapData.Terrain.CIUDAD:
				city_positions.append(Vector2i(x, y))

	print("mapa: ciudades =", city_positions.size())

func _random_terrain() -> int:
	var r := randf()
	if city_count < 8:
		if   r < 0.50: return MapData.Terrain.CAMPO
		elif r < 0.70: return MapData.Terrain.BOSQUE
		elif r < 0.85: return MapData.Terrain.MONTANIA
		elif r < 0.95: return MapData.Terrain.AGUA
		else:
			city_count += 1
			return MapData.Terrain.CIUDAD
	else:
		if   r < 0.55: return MapData.Terrain.CAMPO
		elif r < 0.75: return MapData.Terrain.BOSQUE
		elif r < 0.90: return MapData.Terrain.MONTANIA
		else:          return MapData.Terrain.AGUA

# ---------------------------------------------------------------------------
# Dibujo
# ---------------------------------------------------------------------------
func draw_map() -> void:
	tile_map.clear()
	if map_data.is_empty():
		push_warning("mapa: map_data vacío.")
		return

	for y in range(map_data.size()):
		var row = map_data[y]
		for x in range(row.size()):
			var terrain: int = int(row[x])
			if not MapData.TERRAIN_ATLAS.has(terrain):
				continue
			var atlas_coords: Vector2i
			if terrain == MapData.Terrain.CAMPO:
				var options: Array = MapData.TERRAIN_ATLAS[terrain]
				atlas_coords = options[int(abs(hash(Vector2i(x, y)))) % options.size()]
			else:
				atlas_coords = MapData.TERRAIN_ATLAS[terrain]
			if not atlas_source.has_tile(atlas_coords):
				push_warning("mapa: tile inexistente %s terrain=%s" % [str(atlas_coords), str(terrain)])
				continue
			tile_map.set_cell(0, Vector2i(x, y), atlas_source_id, atlas_coords, 0)

func center_map() -> void:
	var used:         Rect2i = tile_map.get_used_rect()
	var top_left:     Vector2 = tile_map.map_to_local(used.position)
	var bottom_right: Vector2 = tile_map.map_to_local(used.position + used.size)
	var map_size:     Vector2 = bottom_right - top_left
	var vp_size:      Vector2 = get_viewport_rect().size
	tile_map.position = vp_size * 0.5 - map_size * 0.5 - top_left

# ---------------------------------------------------------------------------
# RPC: sincronización inicial (clientes)
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_local")
func sync_map_and_turns(
		remote_map_data:      Array,
		remote_player_cities: Dictionary,
		remote_turn_order:    Array,
		remote_turn_index:    int,
		remote_city_owners:   Dictionary
	) -> void:

	if remote_map_data.is_empty():
		push_warning("mapa: sync_map_and_turns con map_data vacío.")
		return

	map_data = []
	for row in remote_map_data:
		map_data.append(row.duplicate())

	city_positions.clear()
	city_count = 0
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			if map_data[y][x] == MapData.Terrain.CIUDAD:
				city_positions.append(Vector2i(x, y))
				city_count += 1

	city_manager.receive_initial_state(remote_player_cities, remote_city_owners)
	turn_manager.receive_initial_state(remote_turn_order, remote_turn_index)

	draw_map()
	center_map()
	_debug_print_map()
	print("mapa: sincronizado. turn_order =", turn_manager.turn_order)

# ---------------------------------------------------------------------------
# Utilidades de posición
# ---------------------------------------------------------------------------
func cell_center_local(cell: Vector2i) -> Vector2:
	return tile_map.map_to_local(cell)

func cell_to_global(cell: Vector2i) -> Vector2:
	return tile_map.to_global(tile_map.map_to_local(cell))

func local_to_cell(local_pos: Vector2) -> Vector2i:
	return tile_map.local_to_map(local_pos)

func global_to_local(world_pos: Vector2) -> Vector2:
	return tile_map.to_local(world_pos)

func get_adjacent_cells(cell: Vector2i) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var out:  Array[Vector2i] = []
	for d in dirs:
		var c: Vector2i = cell + d
		if c.y < 0 or c.y >= map_data.size():         continue
		if c.x < 0 or c.x >= map_data[c.y].size():    continue
		out.append(c)
	return out

func is_point_inside_iso_cell(local_pos: Vector2, cell: Vector2i) -> bool:
	var cell_local: Vector2 = tile_map.map_to_local(cell)
	var d:          Vector2 = local_pos - cell_local
	var ts:         Vector2i = tile_map.tile_set.tile_size
	var hw:         float = float(ts.x) * 0.5
	var hh:         float = float(ts.y) * 0.5
	return (abs(d.x) / hw + abs(d.y) / hh) <= 1.0

func get_terrain_at(cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= map_data.size():          return -1
	if cell.x < 0 or cell.x >= map_data[cell.y].size():  return -1
	return int(map_data[cell.y][cell.x])

# ---------------------------------------------------------------------------
# Cámara
# ---------------------------------------------------------------------------
func _focus_camera_on_my_city() -> void:
	var my_id: int = multiplayer.get_unique_id()
	if not city_manager.player_cities.has(my_id):
		return
	var cell:      Vector2i = city_manager.player_cities[my_id]
	var world_pos: Vector2  = tile_map.map_to_local(cell)
	camera.position        = world_pos
	camera.target_position = world_pos

# ---------------------------------------------------------------------------
# Pantalla de fin
# ---------------------------------------------------------------------------
var _end_screen: CanvasLayer = null

func _show_end_screen(victory: bool, eliminated: bool) -> void:
	if _end_screen != null and is_instance_valid(_end_screen):
		return

	_end_screen       = CanvasLayer.new()
	_end_screen.layer = 100
	add_child(_end_screen)

	var panel: ColorRect  = ColorRect.new()
	panel.color           = Color(0, 0, 0, 0.75)
	panel.anchor_right    = 1
	panel.anchor_bottom   = 1
	_end_screen.add_child(panel)

	var label: Label = Label.new()
	label.anchor_left   = 0.5
	label.anchor_top    = 0.5
	label.anchor_right  = 0.5
	label.anchor_bottom = 0.5
	label.offset_left   = -250
	label.offset_top    = -60
	label.offset_right  = 250
	label.offset_bottom = 60
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	if eliminated:
		label.text = "ELIMINADO\nEstás observando la partida"
	elif victory:
		label.text = "VICTORIA"
	else:
		label.text = "DERROTA"

	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	panel.add_child(label)

# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------
func _debug_print_map() -> void:
	if map_data.is_empty():
		return
	for y in range(map_data.size()):
		var row  = map_data[y]
		var line: String = ""
		for x in range(row.size()):
			match row[x]:
				MapData.Terrain.CAMPO:    line += "C "
				MapData.Terrain.CIUDAD:   line += "X "
				MapData.Terrain.BOSQUE:   line += "B "
				MapData.Terrain.AGUA:     line += "A "
				MapData.Terrain.MONTANIA: line += "M "
		print(line)
