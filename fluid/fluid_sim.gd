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
	var dir: Vector2      ## Outward unit direction of the injected velocity.
	var speed: float      ## Velocity magnitude at the spark's peak.
	var life: float       ## Active duration in seconds.
	var age: float = 0.0
	var delay: float = 0.0  ## Seconds before the spark ignites.

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
## Scratch buffers, rebuilt each active frame and pushed to the sim shader.
var _spark_pos_buf: PackedVector2Array = PackedVector2Array()
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
	_spark_vel_buf.resize(MAX_SPARKS)
	_spark_str_buf.resize(MAX_SPARKS)

	_text_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_text_mask.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_resize_text_mask()
	get_viewport().size_changed.connect(_resize_text_mask)

	SignalBus.fluid_sparks_requested.connect(spark_halo)
	SignalBus.phrase_changed.connect(_on_phrase_changed)


func _process(delta: float) -> void:
	_elapsed += delta
	var dt: float = minf(delta, 1.0 / 30.0) * simulation_speed

	_update_sparks(delta)
	_update_text_ink(delta)

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

	_display_material.set_shader_parameter("u_time", _elapsed)
	_display_material.set_shader_parameter("u_field", _dst.get_texture())

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


## Fire a halo of tiny outward sparks hugging [param normalized_rect] (normalized
## screen coordinates, Y-down / UV space). Replaces any volley still in the air.
## Used to punctuate a text change.
func spark_halo(normalized_rect: Rect2) -> void:
	var center: Vector2 = normalized_rect.get_center()
	var reach: Vector2 = normalized_rect.size * 0.5 + Vector2(spark_margin, spark_margin)
	var count: int = clampi(spark_count, 1, MAX_SPARKS)

	_sparks.clear()
	for i: int in count:
		var angle: float = TAU * float(i) / float(count) + randf_range(-0.25, 0.25)
		var radial: Vector2 = Vector2(cos(angle), sin(angle))
		var spark: Spark = Spark.new()
		spark.pos = center + radial * reach * randf_range(0.95, 1.35)
		spark.dir = radial.rotated(randf_range(-0.35, 0.35))
		spark.speed = spark_speed * randf_range(0.5, 1.4)
		spark.life = maxf(spark_life * randf_range(0.6, 1.3), 0.01)
		spark.delay = randf_range(0.0, spark_stagger)
		_sparks.append(spark)


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
		if i < _sparks.size():
			var spark: Spark = _sparks[i]
			pos = spark.pos
			if spark.delay > 0.0:
				spark.delay -= delta
				all_done = false
			elif spark.age < spark.life:
				spark.age += delta
				# sin envelope: ignite, peak, fade.
				var env: float = sin(clampf(spark.age / spark.life, 0.0, 1.0) * PI)
				env_sum += env
				strength = env * spark_strength
				vel = spark.dir * spark.speed * env
				all_done = false
		_spark_pos_buf[i] = pos
		_spark_vel_buf[i] = vel
		_spark_str_buf[i] = strength

	if env_sum > 0.0:
		_motion_accum += (env_sum / float(_sparks.size())) * spark_stir * delta

	_sim_material.set_shader_parameter("u_spark_count", _sparks.size())
	_sim_material.set_shader_parameter("u_spark_radius", spark_radius)
	_sim_material.set_shader_parameter("u_spark_pos", _spark_pos_buf)
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
