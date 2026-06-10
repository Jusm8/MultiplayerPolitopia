extends Node2D
class_name Unit

@export var atlas_texture: Texture2D
@export var frame_size: Vector2i = Vector2i(32, 32)
@export var base_offset: Vector2 = Vector2(0, 0) 

var owner_id: int = -1
var unit_id: int = -1
var cell: Vector2i

var hp: int = 10
var dmg: int = 1

@onready var sprite: Sprite2D = $Sprite2D
var hp_label: Label

const UNIT_ATLAS := {
	0: Vector2i(0, 0), # Soldado
	1: Vector2i(1, 0), # General
	2: Vector2i(2, 0), # Arquero
	3: Vector2i(3, 0), # Tanque
}

func _ready() -> void:
	hp_label = Label.new()
	add_child(hp_label)
	hp_label.z_index = 9999
	hp_label.position = Vector2(5, -15)
	
	var font : FontFile = load("res://assets/fonts/Minecraft.ttf")
	hp_label.add_theme_font_override("font", font)
	hp_label.add_theme_font_size_override("font_size", 7)
	
	hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hp_label.add_theme_constant_override("outline_size", 4)
	_update_hp_label()

func setup(_owner_id: int, _unit_id: int, _cell: Vector2i) -> void:
	owner_id = _owner_id
	unit_id = _unit_id
	cell = _cell
	_apply_sprite()
	_update_hp_label()

func set_stats(_hp: int, _dmg:int) -> void:
	hp = _hp
	dmg = _dmg
	_update_hp_label()

func set_hp(new_hp: int) -> void:
	hp = new_hp
	_update_hp_label()

func _update_hp_label() -> void:
	if hp_label:
		hp_label.text = str(hp)

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
	sprite.centered = true
