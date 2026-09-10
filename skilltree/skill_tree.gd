extends Node

const LABEL_FONT: Font = preload("res://assets/fonts/joystix monospace.otf")
const NODE_RADIUS: float = 104.0
const LEFT_X: float = 0.32
const RIGHT_X: float = 0.68
const MENU_SIZE: Vector2 = Vector2(74.0, 62.0)
const MENU_MARGIN: float = 24.0
const GAME_SCENE: String = "res://game/game.tscn"

@onready var _fluid: FluidSim = %FluidBackground
@onready var _skill_hit: CircleButton = %SkillHit
@onready var _auto_hit: CircleButton = %AutoHit
@onready var _back_hit: TapTarget = %BackHit

var _counter: Label
var _skill_label: Label
var _auto_label: Label
var _auto_timer: float = 0.0


func _ready() -> void:
	_counter = _make_label(44)
	_counter.position = Vector2(36.0, 24.0)
	_fluid.add_mask_content(_counter)

	_skill_label = _make_node_label(LEFT_X)
	_auto_label = _make_node_label(RIGHT_X)

	var triangle: FluidTriangle = FluidTriangle.new()
	triangle.anchor_left = 1.0
	triangle.anchor_right = 1.0
	triangle.offset_left = -MENU_MARGIN - MENU_SIZE.x
	triangle.offset_top = MENU_MARGIN
	triangle.offset_right = -MENU_MARGIN
	triangle.offset_bottom = MENU_MARGIN + MENU_SIZE.y
	_fluid.add_mask_content(triangle)

	_fluid.set_palette_tier(GameState.skill_tier, true)
	_fluid.set_excited_blob(Vector2(LEFT_X, 0.5), NODE_RADIUS)
	_fluid.set_excited_blob_2(Vector2(RIGHT_X, 0.5), NODE_RADIUS)

	_skill_hit.radius = NODE_RADIUS
	_skill_hit.center_ratio = Vector2(LEFT_X, 0.5)
	_skill_hit.pressed.connect(_on_skill_pressed)

	_auto_hit.radius = NODE_RADIUS
	_auto_hit.center_ratio = Vector2(RIGHT_X, 0.5)
	_auto_hit.pressed.connect(_on_auto_pressed)

	_back_hit.tapped.connect(_go_back)

	_refresh()


func _process(delta: float) -> void:
	if not GameState.auto_unlocked():
		return
	_auto_timer += delta
	var interval: float = GameState.auto_interval()
	if _auto_timer < interval:
		return
	_auto_timer -= interval
	GameState.points += GameState.auto_value()
	_fluid.pulse_excited_blob_2(1.0)
	_refresh()


func _on_skill_pressed() -> void:
	if GameState.buy_skill():
		_fluid.set_palette_tier(GameState.skill_tier)
		_fluid.bloom_palette(GameState.skill_tier)
		_fluid.pulse_excited_blob(1.4)
		_refresh()


func _on_auto_pressed() -> void:
	if GameState.buy_auto():
		_fluid.pulse_excited_blob_2(1.5)
		_auto_timer = 0.0
		_refresh()


func _go_back() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _refresh() -> void:
	_counter.text = GameState.format_number(GameState.points)

	if GameState.skill_tier >= GameState.MAX_SKILL_TIER:
		_skill_label.text = "CLICK  x%s  MAX" % GameState.format_number(GameState.click_value())
	else:
		_skill_label.text = "CLICK  x%s\ncost %s" % [
			GameState.format_number(GameState.next_skill_multiplier()),
			GameState.format_number(GameState.next_skill_cost()),
		]

	if not GameState.auto_unlocked():
		_auto_label.text = "AUTO-PULSE\ncost %s" % GameState.format_number(GameState.next_auto_cost())
	elif GameState.auto_tier >= GameState.MAX_AUTO_TIER:
		_auto_label.text = "AUTO  +%s / %.1fs  MAX" % [
			GameState.format_number(GameState.auto_value()),
			GameState.auto_interval(),
		]
	else:
		_auto_label.text = "AUTO  +%s / %.1fs\nnext cost %s" % [
			GameState.format_number(GameState.auto_value()),
			GameState.auto_interval(),
			GameState.format_number(GameState.next_auto_cost()),
		]


func _make_node_label(x_ratio: float) -> Label:
	var label: Label = _make_label(24)
	label.anchor_left = x_ratio
	label.anchor_right = x_ratio
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -230.0
	label.offset_right = 230.0
	label.offset_top = NODE_RADIUS + 26.0
	label.offset_bottom = NODE_RADIUS + 100.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fluid.add_mask_content(label)
	return label


func _make_label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override(&"font", LABEL_FONT)
	label.add_theme_font_size_override(&"font_size", font_size)
	return label
