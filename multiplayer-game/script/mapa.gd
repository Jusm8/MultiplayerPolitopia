## mapa.gd — Coordinador + generación de mapa por biomas
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
# Cada celda guarda: {"biome": int, "terrain": int}
# ---------------------------------------------------------------------------
var map_data:       Array            = []   # Array[Array[Dictionary]]
var city_positions: Array[Vector2i]  = []
var city_count:     int              = 0
var player_ids:     Array[int]       = []

var atlas_source_id: int                = -1
var atlas_source:    TileSetAtlasSource = null

# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Inicializar RNG con la semilla recibida del lobby
	# Si map_seed == 0 por algún motivo, usar una aleatoria
	if GameData.map_seed == 0:
		GameData.map_seed = randi_range(10000, 999999)
	seed(GameData.map_seed)
	print("mapa: semilla =", GameData.map_seed)

	var ts := tile_map.tile_set
	if ts == null:
		push_error("mapa: TileMap sin TileSet.")
		return

	for i in range(ts.get_source_count()):
		var id  := ts.get_source_id(i)
		var src := ts.get_source(id)
		if src is TileSetAtlasSource:
			atlas_source_id = id
			atlas_source    = src as TileSetAtlasSource
			break

	if atlas_source_id == -1:
		push_error("mapa: no hay TileSetAtlasSource.")
		return

	player_ids = GameData.get_player_ids()

	turn_manager.map    = self
	economy_manager.map = self
	unit_manager.map    = self
	city_manager.map    = self
	input_handler.map   = self

	_connect_signals()

	if multiplayer.is_server():
		_server_start_game()

# ---------------------------------------------------------------------------
func _server_start_game() -> void:
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
	_focus_camera_on_my_city()

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
	var name_str: String = "Jugador %s" % str(player_id)
	if GameData.players.has(player_id):
		name_str = str(GameData.players[player_id])
	var my_id:  int        = multiplayer.get_unique_id()
	var res:    Dictionary = economy_manager.get_resources(player_id)
	var cities: int        = city_manager.get_city_count_for_player(player_id)
	hud.set_current_player(name_str, my_id == player_id)
	hud.set_round(turn_manager.round_number)
	hud.set_player_stats(cities, int(res.get("wood", 0)), int(res.get("stone", 0)))
	_focus_camera_on_my_city()

func _on_resources_updated(player_id: int) -> void:
	if player_id != multiplayer.get_unique_id():
		return
	var res:    Dictionary = economy_manager.get_resources(player_id)
	var cities: int        = city_manager.get_city_count_for_player(player_id)
	hud.set_player_stats(cities, int(res.get("wood", 0)), int(res.get("stone", 0)))

func _on_player_eliminated(pid: int) -> void:
	if pid == multiplayer.get_unique_id():
		_show_end_screen(false, true)

func _on_game_over(winner: int) -> void:
	_show_end_screen(multiplayer.get_unique_id() == winner, false)

func _on_city_captured(_city_cell: Vector2i, _new_owner: int) -> void:
	pass

# ===========================================================================
# GENERACIÓN DEL MAPA POR BIOMAS
# ===========================================================================
#
# Algoritmo:
#  1. Asignar un bioma base a cada celda mediante Voronoi con N semillas.
#  2. Suavizar bordes con un blur de bioma (mayoría en vecinos).
#  3. Generar ríos como caminos de agua entre zonas.
#  4. Poblar el terreno dentro de cada bioma con pesos aleatorios.
#  5. Colocar ciudades/villas con separación mínima.
#
# ===========================================================================

const N_BIOME_SEEDS  := 9   # cuántos centros de bioma (pradera/desierto/nieve)
const MIN_CITY_DIST  := 4   # distancia mínima entre ciudades
const MAX_CITIES     := 18  # ciudades máximas en el mapa
const N_RIVERS       := 4   # número de ríos

func generate_map() -> void:
	map_data.clear()
	city_positions.clear()
	city_count = 0
	var gs: int = MapData.GRID_SIZE

	# — Inicializar grid vacío —
	for y in range(gs):
		var row: Array = []
		for x in range(gs):
			row.append({"biome": MapData.Biome.PRADERA, "terrain": MapData.Terrain.SUELO})
		map_data.append(row)

	# 1. Voronoi de biomas
	_generate_biomes()

	# 2. Suavizar bordes de bioma
	_smooth_biomes(2)

	# 3. Ríos
	for _i in range(N_RIVERS):
		_carve_river()

	# 4. Poblar terreno
	_populate_terrain()

	# 5. Ciudades con separación mínima
	_place_cities()

	print("mapa: generado. Ciudades=", city_positions.size())

# ---------------------------------------------------------------------------
# 1. Biomas por Voronoi
# ---------------------------------------------------------------------------
func _generate_biomes() -> void:
	var gs: int = MapData.GRID_SIZE
	var seeds: Array[Dictionary] = []
	var biomes: Array[int] = [MapData.Biome.PRADERA, MapData.Biome.DESIERTO, MapData.Biome.NIEVE]

	# Distribuir semillas en una cuadrícula irregular para cubrir bien el mapa
	var grid_n: int = 3  # 3x3 = 9 semillas
	for gy in range(grid_n):
		for gx in range(grid_n):
			var cx: float = (float(gx) + 0.2 + randf() * 0.6) / float(grid_n) * gs
			var cy: float = (float(gy) + 0.2 + randf() * 0.6) / float(grid_n) * gs
			seeds.append({
				"pos":   Vector2(cx, cy),
				"biome": biomes[randi() % biomes.size()]
			})

	# Asignar a cada celda el bioma de la semilla más cercana
	for y in range(gs):
		for x in range(gs):
			var best_dist: float = INF
			var best_biome: int  = MapData.Biome.PRADERA
			for s in seeds:
				var d: float = Vector2(x, y).distance_to(s["pos"])
				if d < best_dist:
					best_dist  = d
					best_biome = s["biome"]
			map_data[y][x]["biome"] = best_biome

# ---------------------------------------------------------------------------
# 2. Suavizar bordes de bioma (N pasadas de moda entre vecinos)
# ---------------------------------------------------------------------------
func _smooth_biomes(passes: int) -> void:
	var gs: int = MapData.GRID_SIZE
	for _p in range(passes):
		var new_biomes: Array = []
		for y in range(gs):
			var row: Array = []
			for x in range(gs):
				var counts: Dictionary = {}
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var ny: int = y + dy
						var nx: int = x + dx
						if ny < 0 or ny >= gs or nx < 0 or nx >= gs:
							continue
						var b: int = map_data[ny][nx]["biome"]
						counts[b] = counts.get(b, 0) + 1
				# Moda
				var best_b: int   = map_data[y][x]["biome"]
				var best_c: int   = 0
				for b in counts:
					if counts[b] > best_c:
						best_c = counts[b]
						best_b = b
				row.append(best_b)
			new_biomes.append(row)
		for y in range(gs):
			for x in range(gs):
				map_data[y][x]["biome"] = new_biomes[y][x]

# ---------------------------------------------------------------------------
# 3. Ríos — camino aleatorio de borde a borde
# ---------------------------------------------------------------------------
func _carve_river() -> void:
	var gs: int = MapData.GRID_SIZE

	# Empezar desde un borde, apuntar al borde opuesto
	var side: int = randi() % 4
	var x: int; var y: int
	var tx: int; var ty: int

	match side:
		0: x = randi_range(2, gs-3); y = 0;      tx = randi_range(2, gs-3); ty = gs-1
		1: x = randi_range(2, gs-3); y = gs-1;   tx = randi_range(2, gs-3); ty = 0
		2: x = 0;      y = randi_range(2, gs-3); tx = gs-1; ty = randi_range(2, gs-3)
		_: x = gs-1;   y = randi_range(2, gs-3); tx = 0;    ty = randi_range(2, gs-3)

	for _step in range(gs * 4):
		if x < 0 or x >= gs or y < 0 or y >= gs:
			break
		map_data[y][x]["terrain"] = MapData.Terrain.AGUA

		# Comprobar si llegamos al borde destino
		if (side == 0 and y >= gs-1) or (side == 1 and y <= 0) \
		or (side == 2 and x >= gs-1) or (side == 3 and x <= 0):
			break

		var want_dx: int = sign(tx - x)
		var want_dy: int = sign(ty - y)
		var r: float = randf()
		var main_axis_x: bool = abs(tx - x) >= abs(ty - y)

		if r < 0.70:
			# Avanzar hacia el destino por el eje con mayor diferencia
			if main_axis_x:
				x += want_dx if want_dx != 0 else (1 if randf()>0.5 else -1)
			else:
				y += want_dy if want_dy != 0 else (1 if randf()>0.5 else -1)
		elif r < 0.88:
			# Meandro perpendicular
			if main_axis_x:
				y += (1 if randf() > 0.5 else -1)
			else:
				x += (1 if randf() > 0.5 else -1)
		else:
			# Diagonal suave hacia destino
			if want_dx != 0: x += want_dx
			if want_dy != 0: y += want_dy

# ---------------------------------------------------------------------------
# 4. Poblar terreno (sin sobreescribir agua)
# ---------------------------------------------------------------------------
func _populate_terrain() -> void:
	var gs: int = MapData.GRID_SIZE
	for y in range(gs):
		for x in range(gs):
			if map_data[y][x]["terrain"] == MapData.Terrain.AGUA:
				continue
			map_data[y][x]["terrain"] = _random_terrain_for_biome(map_data[y][x]["biome"])

func _random_terrain_for_biome(biome: int) -> int:
	var r: float = randf()
	match biome:
		MapData.Biome.PRADERA:
			if   r < 0.55: return MapData.Terrain.SUELO
			elif r < 0.78: return MapData.Terrain.BOSQUE
			elif r < 0.93: return MapData.Terrain.MONTANIA
			else:          return MapData.Terrain.SUELO
		MapData.Biome.DESIERTO:
			if   r < 0.65: return MapData.Terrain.SUELO
			elif r < 0.78: return MapData.Terrain.BOSQUE   # oasis/palmeras
			elif r < 0.92: return MapData.Terrain.MONTANIA
			else:          return MapData.Terrain.SUELO
		MapData.Biome.NIEVE:
			if   r < 0.50: return MapData.Terrain.SUELO
			elif r < 0.68: return MapData.Terrain.BOSQUE
			elif r < 0.88: return MapData.Terrain.MONTANIA
			else:          return MapData.Terrain.SUELO
	return MapData.Terrain.SUELO

# ---------------------------------------------------------------------------
# 5. Ciudades con separación mínima
# ---------------------------------------------------------------------------
func _place_cities() -> void:
	var gs: int = MapData.GRID_SIZE
	var candidates: Array[Vector2i] = []

	# Recoger todas las celdas que no sean agua ni montaña
	for y in range(gs):
		for x in range(gs):
			var t: int = map_data[y][x]["terrain"]
			if t != MapData.Terrain.AGUA and t != MapData.Terrain.MONTANIA:
				candidates.append(Vector2i(x, y))

	candidates.shuffle()

	for cell in candidates:
		if city_count >= MAX_CITIES:
			break
		# Comprobar distancia mínima con ciudades ya colocadas
		var too_close: bool = false
		for existing in city_positions:
			if cell.distance_to(existing) < MIN_CITY_DIST:
				too_close = true
				break
		if too_close:
			continue

		map_data[cell.y][cell.x]["terrain"] = MapData.Terrain.VILLA
		city_positions.append(cell)
		city_count += 1

# ===========================================================================
# DIBUJO
# ===========================================================================

func draw_map() -> void:
	tile_map.clear()
	if map_data.is_empty():
		return

	# Contar tiles faltantes para debug
	var missing: Dictionary = {}

	for y in range(map_data.size()):
		var row: Array = map_data[y]
		for x in range(row.size()):
			var cell:    Vector2i = Vector2i(x, y)
			var biome:   int      = int(row[x]["biome"])
			var terrain: int      = int(row[x]["terrain"])
			var coords:  Vector2i = MapData.get_atlas_coords(biome, terrain, cell)

			if not atlas_source.has_tile(coords):
				var key: String = "b%d_t%d -> %s" % [biome, terrain, str(coords)]
				missing[key] = missing.get(key, 0) + 1
				# Fallback: usar suelo de pradera para no dejar hueco
				var fallback: Vector2i = Vector2i(0, 0)
				if atlas_source.has_tile(fallback):
					tile_map.set_cell(0, cell, atlas_source_id, fallback, 0)
				continue

			tile_map.set_cell(0, cell, atlas_source_id, coords, 0)

	if not missing.is_empty():
		print("=== TILES FALTANTES EN ATLAS ===")
		for k in missing:
			print("  ", k, " x", missing[k])
		print("================================")

func center_map() -> void:
	var used:         Rect2i  = tile_map.get_used_rect()
	var top_left:     Vector2 = tile_map.map_to_local(used.position)
	var bottom_right: Vector2 = tile_map.map_to_local(used.position + used.size)
	var map_size:     Vector2 = bottom_right - top_left
	var vp_size:      Vector2 = get_viewport_rect().size
	tile_map.position = vp_size * 0.5 - map_size * 0.5 - top_left

# ===========================================================================
# RPC sincronización inicial
# ===========================================================================

@rpc("any_peer", "call_local")
func sync_map_and_turns(
		remote_map_data:      Array,
		remote_player_cities: Dictionary,
		remote_turn_order:    Array,
		remote_turn_index:    int,
		remote_city_owners:   Dictionary
	) -> void:

	if remote_map_data.is_empty():
		return

	map_data = []
	city_positions.clear()
	city_count = 0

	for y in range(remote_map_data.size()):
		var row: Array = []
		for x in range(remote_map_data[y].size()):
			var cell_data: Dictionary = remote_map_data[y][x].duplicate()
			row.append(cell_data)
			if int(cell_data.get("terrain", -1)) == MapData.Terrain.VILLA:
				city_positions.append(Vector2i(x, y))
				city_count += 1
		map_data.append(row)

	city_manager.receive_initial_state(remote_player_cities, remote_city_owners)
	turn_manager.receive_initial_state(remote_turn_order, remote_turn_index)

	draw_map()
	center_map()
	print("mapa: cliente sincronizado. Ciudades=", city_count)

# ===========================================================================
# Utilidades de posición
# ===========================================================================

func cell_center_local(cell: Vector2i) -> Vector2:
	return tile_map.map_to_local(cell)

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
	var cell_local: Vector2  = tile_map.map_to_local(cell)
	var d:          Vector2  = local_pos - cell_local
	var ts:         Vector2i = tile_map.tile_set.tile_size
	var hw:         float    = float(ts.x) * 0.5
	var hh:         float    = float(ts.y) * 0.5
	return (abs(d.x) / hw + abs(d.y) / hh) <= 1.0

func get_terrain_at(cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= map_data.size():         return -1
	if cell.x < 0 or cell.x >= map_data[cell.y].size(): return -1
	return int(map_data[cell.y][cell.x].get("terrain", -1))

func get_biome_at(cell: Vector2i) -> int:
	if cell.y < 0 or cell.y >= map_data.size():         return -1
	if cell.x < 0 or cell.x >= map_data[cell.y].size(): return -1
	return int(map_data[cell.y][cell.x].get("biome", -1))

# ===========================================================================
# Cámara
# ===========================================================================

func _focus_camera_on_my_city() -> void:
	var my_id: int = multiplayer.get_unique_id()
	if not city_manager.player_cities.has(my_id):
		return
	var cell:      Vector2i = city_manager.player_cities[my_id]
	var world_pos: Vector2  = tile_map.map_to_local(cell)
	camera.position        = world_pos
	camera.target_position = world_pos

# ===========================================================================
# Pantalla de fin
# ===========================================================================

var _end_screen: CanvasLayer = null

func _show_end_screen(victory: bool, eliminated: bool) -> void:
	if _end_screen != null and is_instance_valid(_end_screen):
		return
	_end_screen       = CanvasLayer.new()
	_end_screen.layer = 100
	add_child(_end_screen)

	var panel: ColorRect = ColorRect.new()
	panel.color          = Color(0, 0, 0, 0.75)
	panel.anchor_right   = 1
	panel.anchor_bottom  = 1
	_end_screen.add_child(panel)

	var label: Label = Label.new()
	label.anchor_left   = 0.5; label.anchor_top    = 0.5
	label.anchor_right  = 0.5; label.anchor_bottom = 0.5
	label.offset_left   = -250; label.offset_top    = -60
	label.offset_right  = 250;  label.offset_bottom = 60
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	if eliminated:   label.text = "ELIMINADO\nEstás observando la partida"
	elif victory:    label.text = "VICTORIA"
	else:            label.text = "DERROTA"

	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	panel.add_child(label)
