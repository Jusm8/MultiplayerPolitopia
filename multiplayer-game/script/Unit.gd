extends Node2D
class_name Unit

@export var atlas_texture: Texture2D # asigna SoldadosMultiplayer.png desde el inspector
@export var frame_size: Vector2i = Vector2i(64, 64)
@export var base_offset: Vector2 = Vector2(0, -18) 
# ajusta este offset para que "pise" bien la loseta (depende de tu arte)

var owner_id: int = -1
var unit_id: int = -1
var cell: Vector2i

@onready var sprite: Sprite2D = $Sprite2D

# unit_id -> coordenadas (col, fila) en el spritesheet
const UNIT_ATLAS := {
	0: Vector2i(0, 0), # Soldado
	1: Vector2i(1, 0), # General
	2: Vector2i(2, 0), # Arquero
	3: Vector2i(3, 0), # Tanque
}

func setup(_owner_id: int, _unit_id: int, _cell: Vector2i) -> void:
	owner_id = _owner_id
	unit_id = _unit_id
	cell = _cell

	_apply_sprite()

func _apply_sprite() -> void:
	if atlas_texture == null:
		push_warning("Unit: atlas_texture no asignado en el inspector.")
		return

	if not UNIT_ATLAS.has(unit_id):
		push_warning("Unit: unit_id %s no existe en UNIT_ATLAS" % str(unit_id))
		return

	var coord: Vector2i = UNIT_ATLAS[unit_id]

	sprite.texture = atlas_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(coord.x * frame_size.x, coord.y * frame_size.y, frame_size.x, frame_size.y)

	# opcional: centrar el sprite para que el offset sea más intuitivo
	sprite.centered = true
