extends Node

const COUNTER_FONT: Font = preload("res://assets/fonts/joystix monospace.otf")
const COUNTER_FONT_SIZE: int = 44
const BLOB_RADIUS: float = 130.0
const AUTO_BLOB_RADIUS: float = 176.0
const MENU_SIZE: Vector2 = Vector2(74.0, 62.0)
const MENU_MARGIN: float = 24.0
const SKILL_TREE_SCENE: String = "res://skilltree/skill_tree.tscn"

@onready var _fluid: FluidSim = %FluidBackground
@onready var _button: CircleButton = %CircleButton
@onready var _menu_hit: TapTarget = %MenuHit

var _counter: Label
var _auto_timer: float = 0.0


func _ready() -> void:
	_counter = Label.new()
	_counter.add_theme_font_override(&"font", COUNTER_FONT)
	_counter.add_theme_font_size_override(&"font_size", COUNTER_FONT_SIZE)
	_counter.position = Vector2(36.0, 24.0)
	_fluid.add_mask_content(_counter)
	_refresh_counter()

	var triangle: FluidTriangle = FluidTriangle.new()
	triangle.anchor_left = 1.0
	triangle.anchor_right = 1.0
	triangle.offset_left = -MENU_MARGIN - MENU_SIZE.x
	triangle.offset_top = MENU_MARGIN
	triangle.offset_right = -MENU_MARGIN
	triangle.offset_bottom = MENU_MARGIN + MENU_SIZE.y
	_fluid.add_mask_content(triangle)

	_fluid.set_excited_blob(Vector2(0.5, 0.5), BLOB_RADIUS)
	_fluid.set_palette_tier(_palette_tier(), true)
	_button.radius = BLOB_RADIUS
	_button.pressed.connect(_on_blob_pressed)
	_menu_hit.tapped.connect(_open_skill_tree)

	if GameState.auto_unlocked():
		_fluid.set_excited_blob_2(Vector2(0.5, 0.5), AUTO_BLOB_RADIUS)


func _process(delta: float) -> void:
	if not GameState.auto_unlocked():
		return
	_auto_timer += delta
	var interval: float = GameState.auto_interval()
	if _auto_timer < interval:
		return
	_auto_timer -= interval
	_gain(GameState.auto_value())
	_fluid.pulse_excited_blob_2(1.0)


func _on_blob_pressed() -> void:
	_gain(GameState.click_value())
	_fluid.pulse_excited_blob()
	var view: Vector2 = get_viewport().get_visible_rect().size
	SignalBus.fluid_lightning_requested.emit(Vector2(0.5, 0.5), BLOB_RADIUS / view.x)


func _gain(amount: int) -> void:
	var tier_before: int = _palette_tier()
	GameState.points += amount
	var tier_after: int = _palette_tier()
	_refresh_counter()
	_fluid.set_palette_tier(tier_after)
	if tier_after > tier_before:
		_fluid.bloom_palette(tier_after)


func _open_skill_tree() -> void:
	get_tree().change_scene_to_file(SKILL_TREE_SCENE)


func _refresh_counter() -> void:
	_counter.text = GameState.format_number(GameState.points)


func _palette_tier() -> int:
	var tier: int = 1
	var threshold: int = 10
	while GameState.points >= threshold and tier < 7:
		tier += 1
		threshold *= 10
	return tier
