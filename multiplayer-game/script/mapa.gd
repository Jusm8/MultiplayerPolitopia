extends Node2D

@onready var tile_map: TileMap = $TileMap

const GRID_SIZE := 16

enum Terrain {
	CAMPO,
	CIUDAD,
	BOSQUE,
	AGUA,
	MONTANIA,
}

var map_data: Array = []
var city_count := 0

func _ready() -> void:
	randomize()
	generate_map()
	draw_map()
	center_map()
	_debug_print_map()

func generate_map() -> void:
	map_data.clear()
	city_count = 0
	for y in range(GRID_SIZE):
		map_data.append([])
		for x in range(GRID_SIZE):
			var terrain := _random_terrain()
			map_data[y].append(terrain)
			
func _random_terrain() -> int:
	var r := randf()
	
	if city_count < 8:
		# CAMPO  50%
		# BOSQUE 20%
		# MONTAÑA 15%
		# AGUA   10%
		# CIUDAD  5% (hasta un máximo de 8)
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
		# Sin ciudades: repartimos su probabilidad al campo
		# CAMPO  55%
		# BOSQUE 20%
		# MONTAÑA 15%
		# AGUA   10%
		if r < 0.55:
			return Terrain.CAMPO
		elif r < 0.75:
			return Terrain.BOSQUE
		elif r < 0.90:
			return Terrain.MONTANIA
		else:
			return Terrain.AGUA

func _debug_print_map() -> void:
	for y in range(GRID_SIZE):
		var line := ""
		for x in range(GRID_SIZE):
			match map_data[y][x]:
				Terrain.CAMPO:   line += "C "
				Terrain.CIUDAD:  line += "X "
				Terrain.BOSQUE:  line += "B "
				Terrain.AGUA:    line += "A "
				Terrain.MONTANIA: line += "M "
		print(line)

func draw_map() -> void:
	tile_map.clear()

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var terrain: int = map_data[y][x]
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
	# Rectángulo de celdas que estamos usando
	var used: Rect2i = tile_map.get_used_rect()

	# Convertimos las esquinas del rectángulo de celdas a píxeles (coordenadas locales del TileMap)
	var top_left: Vector2 = tile_map.map_to_local(used.position)
	var bottom_right: Vector2 = tile_map.map_to_local(used.position + used.size)

	var map_size: Vector2 = bottom_right - top_left
	var viewport_size: Vector2 = get_viewport_rect().size

	# Colocamos el TileMap para que el mapa quede centrado
	tile_map.position = viewport_size * 0.5 - map_size * 0.5 - top_left
