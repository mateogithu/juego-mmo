extends Node

## Procedural sound effect synthesizer using AudioStreamGenerator.
## Zero external audio file dependencies; silently bypassed in headless dedicated server mode.

const MIX_RATE: float = 22050.0
const POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _enabled: bool = true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_enabled = false
		return
	for i: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SynthVoice_%d" % i
		player.bus = "Master"
		add_child(player)
		_players.append(player)


func _play_samples(samples: PackedVector2Array, volume_db: float = -6.0) -> void:
	if not _enabled or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_pool_index]
	_pool_index = (_pool_index + 1) % _players.size()

	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = maxf(float(samples.size()) / MIX_RATE + 0.05, 0.15)
	player.stream = gen
	player.volume_db = volume_db
	player.play()

	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames_avail: int = playback.get_frames_available()
	var count: int = mini(samples.size(), frames_avail)
	for i: int in range(count):
		playback.push_frame(samples[i])


func play_sword_hit() -> void:
	if not _enabled:
		return
	var duration: float = 0.22
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-t * 22.0)
		var metallic: float = sin(TAU * (820.0 - t * 1800.0) * t) * 0.45 + sin(TAU * 1640.0 * t) * 0.2
		var impact_noise: float = rng.randf_range(-1.0, 1.0) * exp(-t * 36.0) * 0.65
		var s: float = clampf((metallic + impact_noise) * env, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -5.0)


func play_fireball() -> void:
	if not _enabled:
		return
	var duration: float = 0.42
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var lp: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = sin(minf(t / 0.05, 1.0) * PI * 0.5) * exp(-t * 5.2)
		var noise: float = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.14)
		var whoosh: float = sin(TAU * (240.0 - t * 280.0) * t) * 0.35
		var s: float = clampf((lp * 1.4 + whoosh) * env, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -4.0)


func play_dragon_roar() -> void:
	if not _enabled:
		return
	var duration: float = 0.85
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var lp: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var attack: float = clampf(t / 0.12, 0.0, 1.0)
		var decay: float = clampf(1.0 - (t - 0.35) / 0.5, 0.0, 1.0) if t > 0.35 else 1.0
		var env: float = attack * decay
		var base_freq: float = lerpf(118.0, 58.0, t / duration) + sin(TAU * 14.0 * t) * 9.0
		var growl: float = sin(TAU * base_freq * t) * 0.55 + sin(TAU * base_freq * 2.02 * t) * 0.25
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
		var s: float = clampf(tanh((growl + lp * 0.9) * 1.8) * env * 0.75, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -3.0)


func play_dodge() -> void:
	if not _enabled:
		return
	var duration: float = 0.18
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var lp: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = sin((t / duration) * PI)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.25)
		var s: float = clampf(lp * env * 0.9, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -7.0)


func play_combat_grace_fanfare() -> void:
	if not _enabled:
		return
	var duration: float = 1.25
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var notes: Array[float] = [261.63, 329.63, 392.0, 523.25]
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var chord: float = 0.0
		for n_idx: int in range(notes.size()):
			var onset: float = float(n_idx) * 0.12
			if t >= onset:
				var nt: float = t - onset
				var n_env: float = clampf(nt / 0.04, 0.0, 1.0) * exp(-nt * 1.9)
				var f: float = notes[n_idx]
				chord += (sin(TAU * f * nt) * 0.6 + sin(TAU * f * 2.0 * nt) * 0.25 + sin(TAU * f * 3.0 * nt) * 0.1) * n_env
		var s: float = clampf(chord * 0.35, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -4.0)


func play_heal() -> void:
	if not _enabled:
		return
	var duration: float = 0.45
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = sin(minf(t / 0.08, 1.0) * PI * 0.5) * exp(-t * 4.5)
		var f1: float = lerpf(440.0, 880.0, t / duration)
		var f2: float = lerpf(554.37, 1108.73, t / duration)
		var s: float = clampf((sin(TAU * f1 * t) * 0.45 + sin(TAU * f2 * t) * 0.35) * env, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -6.0)


func play_build_place() -> void:
	if not _enabled:
		return
	var duration: float = 0.20
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-t * 24.0)
		var thud: float = sin(TAU * (120.0 - t * 200.0) * t) * 0.7
		var grit: float = rng.randf_range(-0.35, 0.35) * exp(-t * 40.0)
		var s: float = clampf((thud + grit) * env, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -5.0)


func play_ui_click() -> void:
	if not _enabled:
		return
	var duration: float = 0.06
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-t * 55.0)
		var s: float = clampf(sin(TAU * 660.0 * t) * env * 0.5, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -10.0)


func play_wing_flap() -> void:
	if not _enabled:
		return
	var duration: float = 0.28
	var total: int = int(duration * MIX_RATE)
	var samples: PackedVector2Array = PackedVector2Array()
	samples.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var lp: float = 0.0
	for i: int in range(total):
		var t: float = float(i) / MIX_RATE
		var env: float = sin((t / duration) * PI)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.09)
		var bass: float = sin(TAU * 62.0 * t) * 0.25
		var s: float = clampf((lp * 1.1 + bass) * env * 0.65, -1.0, 1.0)
		samples[i] = Vector2(s, s)
	_play_samples(samples, -8.0)
