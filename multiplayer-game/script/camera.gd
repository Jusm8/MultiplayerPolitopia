extends Camera2D

@export var zoom_min := 0.5
@export var zoom_max := 2.0
@export var zoom_speed := 0.1

@export var drag_sensitivity := 0.5       # qué tanto se mueve por pixel de ratón
@export var pan_lerp_speed := 8.0         # qué tan rápido la cámara alcanza el objetivo
@export var pan_limit_rect := Rect2(-2000, -2000, 4000, 4000)

var dragging := false
var last_mouse_pos: Vector2 = Vector2.ZERO

var target_position: Vector2               # hacia dónde queremos ir

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	target_position = position

func _unhandled_input(event: InputEvent) -> void:
	# Zoom con rueda
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom = Vector2.ONE * clamp(zoom.x + zoom_speed, zoom_min, zoom_max)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom = Vector2.ONE * clamp(zoom.x - zoom_speed, zoom_min, zoom_max)

	# Drag con botón derecho
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		last_mouse_pos = event.position

	if event is InputEventMouseMotion and dragging:
		var delta: Vector2 = (event.position - last_mouse_pos)
		last_mouse_pos = event.position

		# mover la cámara en dirección contraria
		delta *= -drag_sensitivity / zoom.x  

		target_position += delta

		# Limitar la posición objetivo dentro del rectángulo
		target_position.x = clamp(target_position.x, pan_limit_rect.position.x, pan_limit_rect.position.x + pan_limit_rect.size.x)
		target_position.y = clamp(target_position.y, pan_limit_rect.position.y, pan_limit_rect.position.y + pan_limit_rect.size.y)

func _process(delta: float) -> void:
	# Interpolamos suavemente hacia el objetivo
	# 0.0 = no se mueve, 1.0 = llega en un frame
	var t := pan_lerp_speed * delta
	if t > 1.0:
		t = 1.0
	position = position.lerp(target_position, t)
