## unit_manager.gd
## Sistema de unidades: spawn, movimiento, combate y marcadores visuales.
extends Node

signal unit_moved(from_cell: Vector2i, to_cell: Vector2i)
signal unit_attacked(attacker_cell: Vector2i, defender_cell: Vector2i)
signal unit_died(cell: Vector2i)

var map: Node = null

const UNIT_SCENE:            PackedScene = preload("res://scene/Units.tscn")
const MOVE_MARKER_TEXTURE:   Texture2D   = preload("res://assets/iconos/MovementMarker.png")
const ATTACK_MARKER_TEXTURE: Texture2D   = preload("res://assets/iconos/AttackMarker.png")
const BUSSY_MARKER_TEXTURE:  Texture2D   = preload("res://assets/iconos/BussyMarker.png")

var units_by_cell:  Dictionary      = {}
var selected_unit:  Unit            = null
var move_mode:      bool            = false
var move_targets:   Array[Vector2i] = []
var attack_targets: Array[Vector2i] = []
var move_markers:   Array[Node2D]   = []

# ---------------------------------------------------------------------------
# Selección
# ---------------------------------------------------------------------------
func try_select_unit(cell: Vector2i) -> bool:
	var key: String = MapData.cell_key(cell)
	if not units_by_cell.has(key):
		return false
	var u: Unit = units_by_cell[key]
	if u == null or u.owner_id != multiplayer.get_unique_id():
		return false
	_enter_move_mode(u)
	return true

func try_move_or_attack(cell: Vector2i) -> bool:
	if not move_mode:
		return false
	if cell in move_targets:
		_request_move_unit(selected_unit.cell, cell)
		_exit_move_mode()
		return true
	if cell in attack_targets:
		_request_attack_unit(selected_unit.cell, cell)
		_exit_move_mode()
		return true
	_exit_move_mode()
	return false

func is_in_move_mode() -> bool:
	return move_mode

func _enter_move_mode(u: Unit) -> void:
	selected_unit = u
	move_mode     = true
	_show_move_markers(u.cell)

func _exit_move_mode() -> void:
	move_mode     = false
	selected_unit = null
	_clear_move_markers()

# ---------------------------------------------------------------------------
# Marcadores
# ---------------------------------------------------------------------------
func _show_move_markers(from_cell: Vector2i) -> void:
	_clear_move_markers()
	var adj: Array[Vector2i] = map.get_adjacent_cells(from_cell)
	for c: Vector2i in adj:
		var key:    String   = MapData.cell_key(c)
		var marker: Sprite2D = Sprite2D.new()
		marker.position   = map.cell_center_local(c)
		marker.modulate.a = 0.9
		marker.z_index    = c.y * 100 + c.x - 1
		marker.centered   = true

		if units_by_cell.has(key):
			var other: Unit = units_by_cell[key]
			if other != null and selected_unit != null and other.owner_id != selected_unit.owner_id:
				marker.texture = ATTACK_MARKER_TEXTURE
				attack_targets.append(c)
			else:
				marker.texture = BUSSY_MARKER_TEXTURE
		else:
			marker.texture = MOVE_MARKER_TEXTURE
			move_targets.append(c)

		map.units_layer.add_child(marker)
		move_markers.append(marker)

func _clear_move_markers() -> void:
	for m: Node2D in move_markers:
		if is_instance_valid(m):
			m.queue_free()
	move_markers.clear()
	move_targets.clear()
	attack_targets.clear()

# ---------------------------------------------------------------------------
# Peticiones
# ---------------------------------------------------------------------------
func _request_move_unit(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if multiplayer.is_server():
		request_move_unit(from_cell, to_cell)
	else:
		rpc_id(1, "request_move_unit", from_cell, to_cell)

func _request_attack_unit(attacker_cell: Vector2i, defender_cell: Vector2i) -> void:
	if multiplayer.is_server():
		request_attack_unit(attacker_cell, defender_cell)
	else:
		rpc_id(1, "request_attack_unit", attacker_cell, defender_cell)

# ---------------------------------------------------------------------------
# RPCs servidor
# ---------------------------------------------------------------------------
@rpc("any_peer")
func request_move_unit(from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = _get_sender()
	if sender != map.turn_manager.current_player_id:
		return

	var from_key: String = MapData.cell_key(from_cell)
	if not units_by_cell.has(from_key):
		return

	var u: Unit = units_by_cell[from_key]
	if u.owner_id != sender:
		return
	if not (to_cell in map.get_adjacent_cells(from_cell)):
		return
	if units_by_cell.has(MapData.cell_key(to_cell)):
		return

	rpc("sync_move_unit", from_cell, to_cell)

@rpc("any_peer")
func request_attack_unit(attacker_cell: Vector2i, defender_cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return

	var sender:  int    = _get_sender()
	if sender != map.turn_manager.current_player_id:
		return

	var atk_key: String = MapData.cell_key(attacker_cell)
	var def_key: String = MapData.cell_key(defender_cell)

	if not units_by_cell.has(atk_key) or not units_by_cell.has(def_key):
		return

	var attacker: Unit = units_by_cell[atk_key]
	var defender: Unit = units_by_cell[def_key]

	if attacker == null or defender == null:
		return
	if attacker.owner_id != sender:
		return
	if defender.owner_id == sender:
		return
	if not (defender_cell in map.get_adjacent_cells(attacker_cell)):
		return

	var new_hp: int = defender.hp - attacker.dmg
	if new_hp <= 0:
		rpc("sync_unit_dead", defender_cell)
	else:
		rpc("sync_unit_hp", defender_cell, new_hp)

# ---------------------------------------------------------------------------
# RPCs sincronización
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_local")
func spawn_unit(owner_id: int, unit_id: int, cell: Vector2i) -> void:
	print("UnitManager: spawn owner=%s unit_id=%s cell=%s" % [owner_id, unit_id, str(cell)])
	_spawn_unit_local(owner_id, unit_id, cell)

@rpc("any_peer", "call_local")
func sync_move_unit(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var from_key: String = MapData.cell_key(from_cell)
	if not units_by_cell.has(from_key):
		return
	var u: Unit = units_by_cell[from_key]
	_move_unit_to_cell(u, to_cell)
	unit_moved.emit(from_cell, to_cell)

@rpc("any_peer", "call_local")
func sync_unit_hp(cell: Vector2i, new_hp: int) -> void:
	var key: String = MapData.cell_key(cell)
	if not units_by_cell.has(key):
		return
	var u: Unit = units_by_cell[key]
	if u == null:
		return
	u.set_hp(new_hp)

@rpc("any_peer", "call_local")
func sync_unit_dead(cell: Vector2i) -> void:
	var key: String = MapData.cell_key(cell)
	if not units_by_cell.has(key):
		return
	var u: Unit = units_by_cell[key]
	units_by_cell.erase(key)
	if u != null and is_instance_valid(u):
		u.queue_free()
	unit_died.emit(cell)

# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------
func _spawn_unit_local(owner_id: int, unit_id: int, cell: Vector2i) -> void:
	var key: String = MapData.cell_key(cell)
	if units_by_cell.has(key):
		return

	var u: Unit = UNIT_SCENE.instantiate()
	map.units_layer.add_child(u)
	u.atlas_texture = preload("res://assets/SoldadosMultiplayer.png")
	u.setup(owner_id, unit_id, cell)

	var stats: Dictionary = map.city_manager.unit_db[unit_id]
	u.set_stats(int(stats["hp"]), int(stats["dmg"]))
	u.position = map.cell_center_local(cell) + u.base_offset
	u.z_index  = cell.y * 100 + cell.x
	units_by_cell[key] = u

func _move_unit_to_cell(u: Unit, target: Vector2i) -> void:
	var old_key: String = MapData.cell_key(u.cell)
	if units_by_cell.has(old_key):
		units_by_cell.erase(old_key)
	u.cell     = target
	u.position = map.cell_center_local(target) + u.base_offset
	u.z_index  = target.y * 100 + target.x
	units_by_cell[MapData.cell_key(target)] = u

func _get_sender() -> int:
	var s: int = multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()
