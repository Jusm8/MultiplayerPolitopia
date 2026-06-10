class_name MapData
extends Node

enum Biome {
	PRADERA,
	NIEVE,
	DESIERTO,
}

enum Terrain {
	SUELO,
	BOSQUE,
	VILLA,
	MONTANIA,
	AGUA,
}

# ---------------------------------------------------------------------------
# Tileset real (imagen segunda foto):
#
# FILA 0 — PRADERA
#   col 0: pradera suelo variante 1 (flores rojas)
#   col 1: pradera suelo variante 2 (flores blancas)
#   col 2: pradera bosque
#   col 3: pradera villa (cabaña)
#   col 4: montaña gris
#   col 5: agua (único, compartido)
#
# FILA 1 — NIEVE
#   col 0: nieve suelo variante 1 (flores moradas)
#   col 1: nieve suelo variante 2 (estanque)
#   col 2: nieve bosque (árbol seco)
#   col 3: nieve villa (cabaña nevada)
#   col 4: montaña nevada
#   (sin agua propia → usa col 5 fila 0)
#
# FILA 2 — DESIERTO
#   col 0: desierto suelo variante 1 (cactus)
#   col 1: desierto suelo variante 2 (piedras)
#   col 2: desierto bosque (oasis)
#   col 3: desierto villa (edificio adobe)
#   col 4: desierto montaña (roca naranja)
#   (sin agua propia → usa col 5 fila 0)
# ---------------------------------------------------------------------------
const ATLAS: Dictionary = {
	Biome.PRADERA: {
		Terrain.SUELO:    [Vector2i(0, 0), Vector2i(1, 0)],
		Terrain.BOSQUE:   Vector2i(2, 0),
		Terrain.VILLA:    Vector2i(3, 0),
		Terrain.MONTANIA: Vector2i(4, 0),
		Terrain.AGUA:     Vector2i(5, 0),
	},
	Biome.NIEVE: {
		Terrain.SUELO:    [Vector2i(0, 1), Vector2i(1, 1)],
		Terrain.BOSQUE:   Vector2i(2, 1),
		Terrain.VILLA:    Vector2i(3, 1),
		Terrain.MONTANIA: Vector2i(4, 1),
		Terrain.AGUA:     Vector2i(5, 0),
	},
	Biome.DESIERTO: {
		Terrain.SUELO:    [Vector2i(0, 2), Vector2i(1, 2)],
		Terrain.BOSQUE:   Vector2i(2, 2),
		Terrain.VILLA:    Vector2i(3, 2),
		Terrain.MONTANIA: Vector2i(4, 2),
		Terrain.AGUA:     Vector2i(5, 0),
	},
}

const AGUA_COORDS:     Vector2i = Vector2i(5, 0)
const GRID_SIZE:       int      = 30
const ATLAS_SOURCE_ID: int      = 0

# ---------------------------------------------------------------------------
static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

static func get_atlas_coords(biome: int, terrain: int, cell: Vector2i) -> Vector2i:
	if terrain == Terrain.AGUA:
		return AGUA_COORDS

	var biome_dict: Dictionary = ATLAS.get(biome, {})
	if not biome_dict.has(terrain):
		return Vector2i(0, 0)

	var entry = biome_dict[terrain]
	if entry is Array:
		return entry[int(abs(hash(cell))) % entry.size()]
	return entry as Vector2i
