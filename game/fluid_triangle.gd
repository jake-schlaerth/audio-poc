class_name FluidTriangle
extends Control

@export var fill: Color = Color.WHITE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var points: PackedVector2Array = [
		Vector2(size.x * 0.5, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	]
	draw_colored_polygon(points, fill)
