extends Node
## AudioBank.gd — autoload. Plays SFX + music with graceful no-ops when audio
## assets are missing, so the game runs identically whether you have files or
## not. Drop CC0 audio into the structure documented in assets/audio/README.md.
##
## SFX directory layout: assets/audio/sfx/<event_name>/*.ogg|wav|mp3
##   - Multiple files in the same event dir become random variants per play.
##   - Example: assets/audio/sfx/hit/hit_01.ogg, hit_02.ogg, hit_03.ogg
##
## Music directory layout: assets/audio/music/<track_name>.ogg|wav
##   - Single file per track. play_music(name) crossfades between tracks.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const SFX_POOL_SIZE := 12  # how many overlapping SFX can play at once
const FADE_QUIET_DB := -40.0  # "silent" level for crossfade ends

# event_name -> Array[AudioStream]
var _sfx_streams: Dictionary = {}
# Pool of AudioStreamPlayer nodes cycled round-robin so a new sound never
# cuts off a still-playing one (until the pool wraps).
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_idx: int = 0
# Two music players for A/B crossfade.
var _music_a: AudioStreamPlayer = null
var _music_b: AudioStreamPlayer = null
var _music_active: AudioStreamPlayer = null
var _current_music_track: String = ""


func _ready() -> void:
	_load_sfx()
	_build_sfx_pool()
	_build_music_players()


# ---------------------------------------------------------------------------
# LOADERS
# ---------------------------------------------------------------------------

func _load_sfx() -> void:
	if not DirAccess.dir_exists_absolute(SFX_DIR):
		return
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			_load_sfx_event(entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _load_sfx_event(event_name: String) -> void:
	var event_dir := SFX_DIR + event_name + "/"
	var dir := DirAccess.open(event_dir)
	if dir == null:
		return
	var streams: Array[AudioStream] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and _is_audio_file(entry):
			var path := event_dir + entry
			if ResourceLoader.exists(path):
				var res = load(path)
				if res is AudioStream:
					streams.append(res)
		entry = dir.get_next()
	dir.list_dir_end()
	if not streams.is_empty():
		_sfx_streams[event_name] = streams


func _is_audio_file(name: String) -> bool:
	var lower := name.to_lower()
	return lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3")


func _build_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)


func _build_music_players() -> void:
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	_music_a.volume_db = FADE_QUIET_DB
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	_music_b.volume_db = FADE_QUIET_DB
	add_child(_music_b)


# ---------------------------------------------------------------------------
# SFX PLAY
# ---------------------------------------------------------------------------

func play_sfx(event_name: String, pitch_jitter: float = 0.06, volume_db: float = 0.0) -> void:
	## Plays a random variant of the given event. Pitch is jittered by ±pitch_jitter
	## so rapid-fire plays (e.g. multiple hits in a turn) don't sound mechanical.
	if not _sfx_streams.has(event_name):
		return
	var streams: Array = _sfx_streams[event_name]
	if streams.is_empty():
		return
	var stream: AudioStream = streams[randi() % streams.size()]
	var player := _sfx_pool[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % _sfx_pool.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()


func has_sfx(event_name: String) -> bool:
	return _sfx_streams.has(event_name)


# ---------------------------------------------------------------------------
# MUSIC PLAY
# ---------------------------------------------------------------------------

func play_music(track_name: String, fade_seconds: float = 1.0) -> void:
	## Crossfades into the named music track. If the same track is already
	## playing, this is a no-op. Looks for assets/audio/music/<name>.ogg or .wav.
	if _current_music_track == track_name:
		return
	var path := _resolve_music_path(track_name)
	if path == "":
		return
	var stream = load(path)
	if not (stream is AudioStream):
		return
	# AudioStreamOggVorbis / WAV both support loop, but defaults vary. Force it
	# on so menu music doesn't silently end after one play.
	if "loop" in stream:
		stream.loop = true
	var incoming := _music_b if _music_active == _music_a else _music_a
	var outgoing := _music_active
	incoming.stream = stream
	incoming.volume_db = FADE_QUIET_DB
	incoming.play()
	_music_active = incoming
	_current_music_track = track_name
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, fade_seconds)
	if outgoing != null and outgoing.playing:
		tw.tween_property(outgoing, "volume_db", FADE_QUIET_DB, fade_seconds)
		tw.chain().tween_callback(outgoing.stop)


func stop_music(fade_seconds: float = 0.6) -> void:
	_current_music_track = ""
	for p in [_music_a, _music_b]:
		if p != null and p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", FADE_QUIET_DB, fade_seconds)
			tw.tween_callback(p.stop)


func _resolve_music_path(track_name: String) -> String:
	for ext in [".ogg", ".wav", ".mp3"]:
		# Explicit String type — the loop variable `ext` is Variant (untyped
		# array elements), so the `+` expression's type can't be inferred.
		var p: String = MUSIC_DIR + track_name + ext
		if ResourceLoader.exists(p):
			return p
	return ""
