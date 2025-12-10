extends Node2D

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
		# CIUDAD  5%
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
