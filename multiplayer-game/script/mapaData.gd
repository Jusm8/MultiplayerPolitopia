class_name MapData
extends Node

enum Terrain {
	CAMPO,
	CIUDAD,
	BOSQUE,
	AGUA,
	MONTANIA,
}

const GRID_SIZE       := 30
const ATLAS_SOURCE_ID := 0

const TERRAIN_ATLAS: Dictionary = {
	Terrain.CAMPO:    [Vector2i(1, 0), Vector2i(6, 0)],
	Terrain.BOSQUE:   Vector2i(2, 0),
	Terrain.AGUA:     Vector2i(3, 0),
	Terrain.CIUDAD:   Vector2i(4, 0),
	Terrain.MONTANIA: Vector2i(5, 0),
}

static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
