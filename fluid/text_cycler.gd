class_name TextCycler
extends Label
## Title label that cycles through [member phrases].
##
## Press Space to advance to the next phrase: the current one fades out, the text
## swaps, and the new one fades and pops back in via a [Tween]. Each change also
## fires [signal SignalBus.fluid_sparks_requested] so a halo of sparks flies off
## the edges of the text.

## Phrases shown in order; wraps back to the first after the last.
@export var phrases: PackedStringArray = [
	"mother wants you to call home",
	"",
	"it is 105 degrees and rising",
	"",
	"white christmas indeed!",
	"",
]
## Seconds for the outgoing phrase to fade away.
@export_range(0.01, 1.0) var fade_out_time: float = 0.10
## Seconds for the incoming phrase to fade and pop in.
@export_range(0.01, 1.0) var fade_in_time: float = 0.22
## Scale the incoming phrase grows from (1.0 = no pop).
@export_range(0.1, 1.0) var pop_from_scale: float = 0.7

@export_range(0, 16) var text_outline_size: int = 8
@export var show_overlay: bool = false
@export var emit_sparks: bool = false

var _index: int = 0
var _tween: Tween


func _ready() -> void:
	add_theme_color_override(&"font_outline_color", Color.BLACK)
	add_theme_constant_override(&"outline_size", text_outline_size)
	visible = show_overlay
	if not phrases.is_empty():
		text = phrases[0]
		SignalBus.phrase_changed.emit.call_deferred(phrases[0], 0)
	resized.connect(_recenter_pivot)
	_recenter_pivot()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_SPACE:
		return
	accept_event()
	cycle()


## Advance to the next phrase with a transition and a spark halo off the text.
func cycle() -> void:
	if phrases.size() < 2:
		return
	_index = (_index + 1) % phrases.size()
	var next_text: String = phrases[_index]

	if emit_sparks:
		SignalBus.fluid_sparks_requested.emit(_normalized_rect())
	SignalBus.phrase_changed.emit(next_text, _index)

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_time).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: text = next_text)
	_tween.tween_property(self, "scale", Vector2.ONE, fade_in_time) \
		.from(Vector2(pop_from_scale, pop_from_scale)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, fade_in_time)


## Keep the scale pivot at the label's centre so the pop grows symmetrically.
func _recenter_pivot() -> void:
	pivot_offset = size * 0.5


## The label's on-screen box in normalized viewport coordinates (Y-down), which
## is also the fluid shader's UV space.
func _normalized_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var box: Rect2 = get_global_rect()
	return Rect2(box.position / viewport_size, box.size / viewport_size)
