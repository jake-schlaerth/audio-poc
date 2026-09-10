class_name FluidSim
extends Node
## GPU fluid simulation.
##
## The state (velocity, dye, pressure) lives in a single RGBA texture that is
## ping-ponged between two SubViewports: each frame one viewport reads the other
## and renders one simulation step via [code]fluid_sim.gdshader[/code]. A
## screen-filling ColorRect then draws the current state with
## [code]fluid_display.gdshader[/code].
##
## Left-click and drag to inject force and dye.

const SIM_SHADER: Shader = preload("res://fluid/fluid_sim.gdshader")
const DISPLAY_SHADER: Shader = preload("res://fluid/fluid_display.gdshader")

## Must match [code]MAX_SPARKS[/code] in [code]fluid_sim.gdshader[/code].
const MAX_SPARKS: int = 24


## One ember in a text-spark halo. Injects a fixed-point outward pulse of dye and
## velocity that ramps up then fades over [member life].
class Spark extends RefCounted:
	var pos: Vector2      ## Fixed injection point, normalized screen / UV space.
	var end_pos: Vector2  ## Other end of the injection segment; equal to pos for a point.
	var dir: Vector2      ## Outward unit direction of the injected velocity.
	var speed: float      ## Velocity magnitude at the spark's peak.
	var life: float       ## Active duration in seconds.
	var strength: float = 1.0  ## Per-spark scale on the volley strength.
	var age: float = 0.0
	var delay: float = 0.0  ## Seconds before the spark ignites.


## One line in a lightning strike: a run of straight segments, possibly a fork.
class Branch extends RefCounted:
	var point: Vector2
	var axis: Vector2
	var side: float = 1.0
	var length: int = 5
	var gen: int = 0
	var delay: float = 0.0

## Internal simulation grid size. Independent of the window resolution.
@export var sim_resolution: Vector2i = Vector2i(512, 512)
## Multiplier applied to frame delta before it reaches the shader.
@export var simulation_speed: float = 60.0
@export_range(0.0001, 4.0) var viscosity: float = 1.2
@export_range(0.0, 5.0) var vorticity: float = 0.5
## Dye retention per step (1.0 = never fades).
@export_range(0.9, 1.0, 0.0005) var dissipation: float = 0.989
@export_range(0.0, 0.25) var dye_diffuse: float = 0.0025
@export_range(0.0, 1.0) var ambient_flow: float = 0.0
@export_range(0.5, 12.0) var ambient_scale: float = 3.0
## Radius of the mouse force splat, in normalized screen units.
@export_range(0.01, 0.3) var force_radius: float = 0.08
## Scales pointer motion into injected velocity.
@export var force_strength: float = 0.05

@export_group("Adaptive music")
## Drag speed, in screen widths per second, that maps to full boss intensity.
@export var activity_full_speed: float = 2.5
## Seconds for tracked activity to rise toward the current stirring level.
@export_range(0.01, 3.0) var activity_attack: float = 0.25
## Seconds for tracked activity to fall back toward zero once stirring stops.
@export_range(0.05, 10.0) var activity_release: float = 2.0

@export_group("Text sparks")
## Number of sparks in one halo (capped at the shader's slot count).
@export_range(1, 24) var spark_count: int = 16
## Gap between the text edge and the spark ring, in normalized screen units.
@export var spark_margin: float = 0.02
## Outward speed injected by each spark.
@export var spark_speed: float = 0.3
## Dye/velocity radius of a single spark — small; these are embers, not splats.
@export_range(0.002, 0.05) var spark_radius: float = 0.012
## Seconds a spark stays alight.
@export var spark_life: float = 0.35
## Spread of spark ignition times so the halo crackles instead of firing at once.
@export var spark_stagger: float = 0.18
## Peak velocity/dye magnitude per spark.
@export var spark_strength: float = 1.0
## How hard a halo stirs the field for the music, in [member activity_full_speed]
## units; it then eases back via [member activity_release].
@export var spark_stir: float = 2.2

@export_group("Text ink")
@export_range(0.0, 1.0) var text_ink_strength: float = 0.25
@export_range(0.0, 1.0) var text_ink_maintain: float = 0.12
@export_range(0.0, 4.0) var text_ink_fade_in: float = 0.5
@export_range(0.0, 2.0) var text_ink_settle: float = 0.6
@export_range(0.0, 1.0) var text_ink_calm: float = 0.95
@export_range(0.0, 0.3) var text_ink_stir: float = 0.02
@export_range(0.5, 16.0) var text_ink_stir_scale: float = 6.0
@export_range(0.0, 2.0) var text_ink_stir_speed: float = 0.35
@export_range(0.0, 3.0) var text_ink_stir_music: float = 0.4
@export var persistent_ink: bool = false

@export_group("Click lightning")
@export_range(1, 6) var lightning_bolts: int = 3
@export_range(2, 12) var lightning_segments: int = 5
@export var lightning_segment_length: float = 0.06
@export_range(0.0, 1.5) var lightning_jitter: float = 0.7
@export_range(0.0, 0.6) var lightning_spread: float = 0.22
@export var lightning_speed: float = 0.75
@export_range(0.001, 0.03) var lightning_radius: float = 0.005
@export var lightning_life: float = 0.1
@export var lightning_travel: float = 0.018
@export var lightning_strength: float = 1.3
@export var lightning_stir: float = 2.8
@export_range(0.0, 1.0) var lightning_fork_chance: float = 0.22
@export_range(0, 3) var lightning_fork_depth: int = 2
@export_range(0.0, 1.0) var lightning_branch_strength: float = 0.55

@export_group("Excited blob")
@export_range(0.0, 1.0) var blob_dye: float = 0.45
@export_range(0.0, 1.0) var blob_ceil: float = 0.6
@export_range(0.0, 1.0) var blob_swirl: float = 0.26
@export_range(0.5, 24.0) var blob_swirl_scale: float = 12.0
@export_range(0.0, 2.0) var blob_swirl_speed: float = 0.7
@export_range(0.0, 0.1) var blob_edge: float = 0.014
@export var blob_pulse_decay: float = 3.5

@export_group("Palette")
@export_range(0, 7) var palette_start_tier: int = 7
@export var palette_transition_speed: float = 1.4
@export var palette_bloom_decay: float = 1.2
@export_range(0.0, 1.5) var palette_bloom_strength: float = 0.9

@onready var _a: SubViewport = %SimA
@onready var _b: SubViewport = %SimB
@onready var _display: ColorRect = %Display
@onready var _text_mask: SubViewport = %TextMask
@onready var _ink_label: Label = %InkLabel

var _sim_material: ShaderMaterial
var _display_material: ShaderMaterial
var _src: SubViewport
var _dst: SubViewport
var _reset_frames: int = 3
var _elapsed: float = 0.0

var _force_pos: Vector2 = Vector2(-1.0, -1.0)
var _force_dir: Vector2 = Vector2.ZERO
var _mouse_down: bool = false

## Smoothed 0..1 stir level driving the adaptive music crossfade.
var _activity: float = 0.0
## Normalized pointer distance travelled since the last frame.
var _motion_accum: float = 0.0

var _ink_age: float = -1.0
var _settle_age: float = -1.0

## Sparks currently in the air. Empty between text changes.
var _sparks: Array[Spark] = []
var _volley_stir: float = 0.0
var _volley_radius: float = 0.0
var _volley_strength: float = 1.0

var _blob_pos: Vector2 = Vector2(-1.0, -1.0)
var _blob_radius_px: float = 0.0
var _blob_pulse: float = 0.0
var _blob2_pos: Vector2 = Vector2(-1.0, -1.0)
var _blob2_radius_px: float = 0.0
var _blob2_pulse: float = 0.0

var _palette_count: float = 7.0
var _palette_target: float = 7.0
var _bloom: float = 0.0
var _bloom_index: int = 0
## Scratch buffers, rebuilt each active frame and pushed to the sim shader.
var _spark_pos_buf: PackedVector2Array = PackedVector2Array()
var _spark_end_buf: PackedVector2Array = PackedVector2Array()
var _spark_vel_buf: PackedVector2Array = PackedVector2Array()
var _spark_str_buf: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_sim_material = ShaderMaterial.new()
	_sim_material.shader = SIM_SHADER
	_sim_material.set_shader_parameter("u_resolution", Vector2(sim_resolution))

	_display_material = ShaderMaterial.new()
	_display_material.shader = DISPLAY_SHADER
	_display.material = _display_material
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_palette_target = float(palette_start_tier)
	_palette_count = _palette_target

	var viewports: Array[SubViewport] = [_a, _b]
	for viewport: SubViewport in viewports:
		viewport.size = sim_resolution
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		viewport.disable_3d = true
		viewport.use_hdr_2d = true
		# The ColorRect uses full-rect anchors (set in the scene) so it always
		# covers the whole SubViewport.
		var field: ColorRect = viewport.get_child(0) as ColorRect
		field.material = _sim_material

	_src = _a
	_dst = _b

	_spark_pos_buf.resize(MAX_SPARKS)
	_spark_end_buf.resize(MAX_SPARKS)
	_spark_vel_buf.resize(MAX_SPARKS)
	_spark_str_buf.resize(MAX_SPARKS)

	_text_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_text_mask.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_resize_text_mask()
	get_viewport().size_changed.connect(_resize_text_mask)

	SignalBus.fluid_sparks_requested.connect(spark_halo)
	SignalBus.fluid_lightning_requested.connect(strike_lightning)
	SignalBus.phrase_changed.connect(_on_phrase_changed)

	if persistent_ink:
		_ink_age = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	var dt: float = minf(delta, 1.0 / 30.0) * simulation_speed

	_update_sparks(delta)
	_update_text_ink(delta)
	_update_blob(delta)

	_sim_material.set_shader_parameter("u_time", _elapsed)
	_sim_material.set_shader_parameter("u_dt", dt)
	_sim_material.set_shader_parameter("u_prev", _src.get_texture())
	_sim_material.set_shader_parameter("u_viscosity", maxf(viscosity, 0.0001))
	_sim_material.set_shader_parameter("u_vorticity", vorticity)
	_sim_material.set_shader_parameter("u_dissipation", dissipation)
	_sim_material.set_shader_parameter("u_dye_diffuse", dye_diffuse)
	_sim_material.set_shader_parameter("u_ambient_flow", ambient_flow)
	_sim_material.set_shader_parameter("u_ambient_scale", ambient_scale)
	_sim_material.set_shader_parameter("u_force_radius", force_radius)
	_sim_material.set_shader_parameter("u_force_pos", _force_pos)
	_sim_material.set_shader_parameter("u_force_dir", _force_dir)
	_sim_material.set_shader_parameter("u_reset", _reset_frames > 0)

	# Render exactly one step into the write target this frame.
	_dst.render_target_update_mode = SubViewport.UPDATE_ONCE

	_palette_count = move_toward(_palette_count, _palette_target, palette_transition_speed * delta)
	_bloom = maxf(_bloom - palette_bloom_decay * delta, 0.0)
	_display_material.set_shader_parameter("u_time", _elapsed)
	_display_material.set_shader_parameter("u_field", _dst.get_texture())
	_display_material.set_shader_parameter("u_palette_count", _palette_count)
	_display_material.set_shader_parameter("u_bloom", _bloom * palette_bloom_strength)
	_display_material.set_shader_parameter("u_bloom_index", _bloom_index)

	var previous_src: SubViewport = _src
	_src = _dst
	_dst = previous_src

	_force_dir = _force_dir.lerp(Vector2.ZERO, 0.25)
	if _reset_frames > 0:
		_reset_frames -= 1

	_update_activity(delta)


## Track how hard the field is being stirred — by the pointer or by a spark halo
## — and broadcast the smoothed 0..1 level on [signal SignalBus.fluid_activity_changed].
## Rises quickly, decays slowly afterwards so the music tails out instead of
## cutting.
func _update_activity(delta: float) -> void:
	var drag_speed: float = _motion_accum / maxf(delta, 0.0001)
	_motion_accum = 0.0
	var target: float = clampf(drag_speed / maxf(activity_full_speed, 0.0001), 0.0, 1.0)
	var tau: float = activity_attack if target > _activity else activity_release
	_activity = lerpf(_activity, target, 1.0 - exp(-delta / maxf(tau, 0.0001)))
	# The music layer (and anything else) reacts to this, not to the raw input.
	SignalBus.fluid_activity_changed.emit(_activity)


## Inject velocity and dye at [param normalized_pos] (0..1 screen space, Y-down).
## [param direction] is added to the velocity field; its magnitude controls
## strength. Lasts one frame, so call every frame for a sustained stream.
func splat(normalized_pos: Vector2, direction: Vector2) -> void:
	_force_pos = normalized_pos
	_force_dir = direction


func add_mask_content(content: CanvasItem) -> void:
	_text_mask.add_child(content)


## Fire a halo of tiny outward sparks hugging [param normalized_rect] (normalized
## screen coordinates, Y-down / UV space). Replaces any volley still in the air.
## Used to punctuate a text change.
func spark_halo(normalized_rect: Rect2) -> void:
	var center: Vector2 = normalized_rect.get_center()
	var reach: Vector2 = normalized_rect.size * 0.5 + Vector2(spark_margin, spark_margin)
	var count: int = clampi(spark_count, 1, MAX_SPARKS)

	_volley_stir = spark_stir
	_volley_radius = spark_radius
	_volley_strength = spark_strength

	_sparks.clear()
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.25, 0.25)
		var radial: Vector2 = Vector2(cos(angle), sin(angle))
		var spark: Spark = Spark.new()
		spark.pos = center + radial * reach * randf_range(0.95, 1.35)
		spark.end_pos = spark.pos
		spark.dir = radial.rotated(randf_range(-0.35, 0.35))
		spark.speed = spark_speed * randf_range(0.5, 1.4)
		spark.life = maxf(spark_life * randf_range(0.6, 1.3), 0.01)
		spark.delay = randf_range(0.0, spark_stagger)
		_sparks.append(spark)


func strike_lightning(center: Vector2, radius: float) -> void:
	var bolts: int = clampi(lightning_bolts, 1, MAX_SPARKS)

	_volley_stir = lightning_stir
	_volley_radius = lightning_radius
	_volley_strength = lightning_strength

	_sparks.clear()

	var pending: Array[Branch] = []
	for b: int in bolts:
		var root_angle: float = TAU * (float(b) + randf_range(-0.4, 0.4)) / float(bolts)
		var branch: Branch = Branch.new()
		branch.axis = Vector2(cos(root_angle), sin(root_angle)).rotated(randf_range(-lightning_spread, lightning_spread))
		branch.point = center + branch.axis * radius
		branch.side = 1.0 if randf() < 0.5 else -1.0
		branch.length = clampi(lightning_segments, 2, 12)
		pending.append(branch)

	while not pending.is_empty() and _sparks.size() < MAX_SPARKS:
		var branch: Branch = pending.pop_front()
		var point: Vector2 = branch.point
		var side: float = branch.side
		var is_fork: bool = branch.gen > 0
		var len_scale: float = 0.7 if is_fork else 1.0
		var strength_scale: float = lightning_branch_strength if is_fork else 1.0

		for s: int in branch.length:
			if _sparks.size() >= MAX_SPARKS:
				break
			var seg_frac: float = float(s) / float(maxi(branch.length - 1, 1))
			side = -side if randf() < 0.8 else side
			var straighten: float = 0.4 if s == 0 and not is_fork else 1.0
			var heading: Vector2 = branch.axis.rotated(side * lightning_jitter * randf_range(0.4, 1.0) * straighten)
			var next_point: Vector2 = point + heading * lightning_segment_length * randf_range(0.8, 1.35) * len_scale
			var delay: float = branch.delay + seg_frac * lightning_travel

			var spark: Spark = Spark.new()
			spark.pos = point
			spark.end_pos = next_point
			spark.dir = heading
			spark.strength = strength_scale
			spark.speed = lightning_speed * randf_range(0.85, 1.15)
			spark.life = maxf(lightning_life * randf_range(0.85, 1.15), 0.01)
			spark.delay = delay
			_sparks.append(spark)

			if branch.gen < lightning_fork_depth and s >= 1 and s < branch.length - 1 \
					and _sparks.size() < MAX_SPARKS - 1 and randf() < lightning_fork_chance:
				var fork: Branch = Branch.new()
				fork.point = next_point
				fork.axis = heading.rotated(-side * randf_range(0.45, 1.0))
				fork.side = 1.0 if randf() < 0.5 else -1.0
				fork.length = randi_range(2, 4)
				fork.gen = branch.gen + 1
				fork.delay = delay
				pending.append(fork)

			point = next_point


func set_excited_blob(normalized_pos: Vector2, radius_px: float) -> void:
	_blob_pos = normalized_pos
	_blob_radius_px = radius_px


func set_excited_blob_2(normalized_pos: Vector2, radius_px: float) -> void:
	_blob2_pos = normalized_pos
	_blob2_radius_px = radius_px


func pulse_excited_blob_2(amount: float = 1.0) -> void:
	_blob2_pulse = minf(_blob2_pulse + amount, 1.5)


func set_palette_tier(tier: int, snap: bool = false) -> void:
	_palette_target = float(clampi(tier, 0, 7))
	if snap:
		_palette_count = _palette_target


func bloom_palette(tier: int) -> void:
	_bloom_index = clampi(tier - 1, 0, 6)
	_bloom = 1.0


func pulse_excited_blob(amount: float = 1.0) -> void:
	_blob_pulse = minf(_blob_pulse + amount, 1.5)


func _update_blob(delta: float) -> void:
	_blob_pulse = maxf(_blob_pulse - blob_pulse_decay * delta, 0.0)
	_blob2_pulse = maxf(_blob2_pulse - blob_pulse_decay * delta, 0.0)

	var view: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = view.x / maxf(view.y, 1.0)

	_sim_material.set_shader_parameter("u_blob_pos", _blob_pos)
	_sim_material.set_shader_parameter("u_blob_radius", _blob_radius_px / maxf(view.x, 1.0))
	_sim_material.set_shader_parameter("u_blob_aspect", aspect)
	_sim_material.set_shader_parameter("u_blob_dye", blob_dye)
	_sim_material.set_shader_parameter("u_blob_ceil", blob_ceil)
	_sim_material.set_shader_parameter("u_blob_swirl", blob_swirl)
	_sim_material.set_shader_parameter("u_blob_swirl_scale", blob_swirl_scale)
	_sim_material.set_shader_parameter("u_blob_swirl_speed", blob_swirl_speed)
	_sim_material.set_shader_parameter("u_blob_edge", blob_edge)
	_sim_material.set_shader_parameter("u_blob_pulse", _blob_pulse)

	_sim_material.set_shader_parameter("u_blob2_pos", _blob2_pos)
	_sim_material.set_shader_parameter("u_blob2_radius", _blob2_radius_px / maxf(view.x, 1.0))
	_sim_material.set_shader_parameter("u_blob2_pulse", _blob2_pulse)

	_motion_accum += (_blob_pulse + _blob2_pulse) * 0.4 * delta


## Advance every live spark, push the halo to the sim shader, and feed the music
## stir accumulator. Runs before the shader parameters so the injection lands
## this frame. Retires the whole volley once the last spark burns out.
func _update_sparks(delta: float) -> void:
	if _sparks.is_empty():
		return

	var env_sum: float = 0.0
	var all_done: bool = true
	for i: int in MAX_SPARKS:
		var strength: float = 0.0
		var vel: Vector2 = Vector2.ZERO
		var pos: Vector2 = Vector2.ZERO
		var end_pos: Vector2 = Vector2.ZERO
		if i < _sparks.size():
			var spark: Spark = _sparks[i]
			pos = spark.pos
			end_pos = spark.end_pos
			if spark.delay > 0.0:
				spark.delay -= delta
				all_done = false
			elif spark.age < spark.life:
				spark.age += delta
				# sin envelope: ignite, peak, fade.
				var env: float = sin(clampf(spark.age / spark.life, 0.0, 1.0) * PI)
				env_sum += env
				strength = env * _volley_strength * spark.strength
				vel = spark.dir * spark.speed * env
				all_done = false
		_spark_pos_buf[i] = pos
		_spark_end_buf[i] = end_pos
		_spark_vel_buf[i] = vel
		_spark_str_buf[i] = strength

	if env_sum > 0.0:
		_motion_accum += (env_sum / float(_sparks.size())) * _volley_stir * delta

	_sim_material.set_shader_parameter("u_spark_count", _sparks.size())
	_sim_material.set_shader_parameter("u_spark_radius", _volley_radius)
	_sim_material.set_shader_parameter("u_spark_pos", _spark_pos_buf)
	_sim_material.set_shader_parameter("u_spark_end", _spark_end_buf)
	_sim_material.set_shader_parameter("u_spark_vel", _spark_vel_buf)
	_sim_material.set_shader_parameter("u_spark_strength", _spark_str_buf)

	if all_done:
		_sparks.clear()
		_sim_material.set_shader_parameter("u_spark_count", 0)


func _on_phrase_changed(phrase: String, _index: int) -> void:
	if _ink_age >= 0.0:
		_settle_age = 0.0
	_ink_label.text = phrase
	_ink_age = 0.0 if not phrase.strip_edges().is_empty() else -1.0


func _resize_text_mask() -> void:
	_text_mask.size = Vector2i(get_viewport().get_visible_rect().size)


func _update_text_ink(delta: float) -> void:
	var inject: float = 0.0
	var calm: float = 0.0
	if _ink_age >= 0.0:
		_ink_age += delta
		var fade_in: float = maxf(text_ink_fade_in, 0.0001)
		var maintain: float = text_ink_maintain / maxf(text_ink_strength, 0.0001)
		if _ink_age < fade_in:
			inject = _ink_age / fade_in
			calm = clampf(_ink_age / (fade_in * 0.3), 0.0, 1.0)
		else:
			inject = maintain
			calm = 1.0

	var settle: float = 0.0
	if _settle_age >= 0.0:
		_settle_age += delta
		var settle_time: float = maxf(text_ink_settle, 0.0001)
		if _settle_age >= settle_time:
			_settle_age = -1.0
		else:
			settle = 1.0 - _settle_age / settle_time

	var presence: float = clampf(calm, 0.0, 1.0)
	_sim_material.set_shader_parameter("u_text_mask", _text_mask.get_texture())
	_sim_material.set_shader_parameter("u_text_amount", clampf(inject, 0.0, 1.0) * text_ink_strength)
	_sim_material.set_shader_parameter("u_text_calm", presence * text_ink_calm)
	_sim_material.set_shader_parameter("u_text_stir", presence * text_ink_stir)
	_sim_material.set_shader_parameter("u_text_stir_scale", text_ink_stir_scale)
	_sim_material.set_shader_parameter("u_text_stir_speed", text_ink_stir_speed)
	_sim_material.set_shader_parameter("u_text_settle", settle)
	_motion_accum += presence * text_ink_stir_music * delta


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = button.pressed
			if not _mouse_down:
				_force_pos = Vector2(-1.0, -1.0)
	elif event is InputEventMouseMotion and _mouse_down:
		var motion: InputEventMouseMotion = event
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		_force_pos = motion.position / view_size
		_force_dir = motion.relative * force_strength
		_motion_accum += (motion.relative / view_size).length()
