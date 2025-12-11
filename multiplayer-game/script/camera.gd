extends Camera2D

@export var zoom_min := 0.5
@export var zoom_max := 2.0
@export var zoom_speed := 0.1
@export var pan_speed := 10.0
@export var pan_limit_rect := Rect2(-2000, -2000, 4000, 4000)

var dragging := false
var last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	# Zoom con rueda
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom = Vector2.ONE * clamp(zoom.x - zoom_speed, zoom_min, zoom_max)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom = Vector2.ONE * clamp(zoom.x + zoom_speed, zoom_min, zoom_max)

	# Drag con botón derecho
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		dragging = event.pressed
		last_mouse_pos = event.position

	if event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = (motion.position - last_mouse_pos) * -1.0
		last_mouse_pos = motion.position
		position += delta * pan_speed
		# Limitar movimiento de la cámara
		position.x = clamp(position.x, pan_limit_rect.position.x, pan_limit_rect.position.x + pan_limit_rect.size.x)
		position.y = clamp(position.y, pan_limit_rect.position.y, pan_limit_rect.position.y + pan_limit_rect.size.y)
