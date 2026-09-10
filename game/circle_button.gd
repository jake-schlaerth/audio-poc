class_name CircleButton
extends Control

signal pressed

@export var radius: float = 110.0
@export var center_ratio: Vector2 = Vector2(0.5, 0.5)


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * center_ratio) <= radius


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
