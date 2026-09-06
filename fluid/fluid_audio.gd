class_name FluidAudio
extends Node
## Adaptive music layer for the fluid simulation.
##
## Runs [member low_loop] (calm, sparse) and [member high_loop] (busy, intense)
## as two looping players started on the same frame. Both clips are the same
## length and share the audio output clock, so once started they stay aligned
## for the session.
##
## The crossfade follows the fluid: it listens to
## [signal SignalBus.fluid_activity_changed] (0.0 = calm ... 1.0 = full boss) and
## equal-power blends the two loops. Anything that stirs the field — pointer drag
## or a [method FluidSim.spark_halo] — moves the music. [method set_intensity] is
## also callable directly for tests.

## Calm, sparse loop heard while the fluid is idle.
@export var low_loop: AudioStream = preload("res://assets/music/low-loop.ogg")
@export var high_loop: AudioStream = preload("res://assets/music/high-loop.ogg")
@export var bus: StringName = &"Master"
@export_range(0.01, 5.0) var fade_in_time: float = 0.01
@export_range(0.01, 10.0) var fade_out_time: float = 0.01
@export_range(0.0001, 0.1) var silence_threshold: float = 0.001

const MUTE_DB: float = -80.0
const SHUTDOWN_DRAIN_TIME: float = 0.1

var _low_player: AudioStreamPlayer
var _high_player: AudioStreamPlayer
var _target: float = 0.0
var _mix: float = 0.0


func _ready() -> void:
	_low_player = _make_player(&"LowMusic", low_loop)
	_high_player = _make_player(&"HighMusic", high_loop)
	_apply_mix()
	# Same frame, same audio clock -> the two loops start sample-aligned.
	_low_player.play()
	_high_player.play()

	SignalBus.fluid_activity_changed.connect(set_intensity)

	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


func _shutdown() -> void:
	_low_player.stop()
	_high_player.stop()
	await get_tree().create_timer(SHUTDOWN_DRAIN_TIME).timeout
	get_tree().quit()


func _process(delta: float) -> void:
	var tau: float = fade_in_time if _target > _mix else fade_out_time
	# Frame-rate independent exponential approach toward the target mix.
	_mix = lerpf(_mix, _target, 1.0 - exp(-delta / maxf(tau, 0.0001)))
	_apply_mix()


## Set the desired boss weight for this frame: 0.0 calm ... 1.0 full boss.
## Values are clamped; call every frame for a continuous crossfade.
func set_intensity(value: float) -> void:
	_target = clampf(value, 0.0, 1.0)


func _make_player(node_name: StringName, stream: AudioStream) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = bus
	add_child(player)
	return player


func _apply_mix() -> void:
	# Equal-power crossfade: the two gains sum in quadrature to 1.0, so the
	# combined loudness stays flat through the blend instead of dipping.
	_low_player.volume_db = _gain_to_db(sqrt(1.0 - _mix))
	_high_player.volume_db = _gain_to_db(sqrt(_mix))


func _gain_to_db(gain: float) -> float:
	if gain <= silence_threshold:
		return MUTE_DB
	return linear_to_db(gain)
