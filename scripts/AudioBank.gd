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

# Interim cue aliases: when a cue's own event dir is missing or empty, play_sfx
# falls back to the mapped event so the moment is never silent (five wired cues
# shipped as no-ops in 2026-07 because only their call sites existed). The
# primary dir auto-wins the moment real clips land there — the alias is only
# consulted when the primary has no loaded streams. play_ambience deliberately
# does NOT alias (missing ambience no-oping is a design contract, see Event.gd).
# tools/_probe_audio_cues.gd enforces that every play_sfx cue resolves here.
const SFX_FALLBACKS := {
	"creature_death": "death",
	"hit_creature": "hit",
	"relic_get": "coin",
	"potion_use": "heal",
	"upgrade_confirm": "coin",
	"doom_tick": "button_click",
	"boss_intro": "turn_start",
}

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
# Looping-ambience player, separate from one-shot SFX and music. Used for the
# campfire crackle on the rest screen (and similar long looping textures).
# Always exactly one ambience may play at a time; calling play_ambience("x")
# stops the previous loop and crossfades in the new one, mirroring play_music.
var _ambience_player: AudioStreamPlayer = null
var _current_ambience: String = ""


func _ready() -> void:
	_load_sfx()
	_build_sfx_pool()
	_build_music_players()
	_build_ambience_player()


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


func _build_ambience_player() -> void:
	_ambience_player = AudioStreamPlayer.new()
	# Routed through the SFX bus so the player's SFX volume slider also
	# attenuates ambience — most players treat fire-crackle / wind as "sound
	# effects," not music, and reach for the SFX knob when they want it down.
	_ambience_player.bus = "SFX"
	_ambience_player.volume_db = FADE_QUIET_DB
	add_child(_ambience_player)


# ---------------------------------------------------------------------------
# SFX PLAY
# ---------------------------------------------------------------------------

func play_sfx(event_name: String, pitch_jitter: float = 0.06, volume_db: float = 0.0,
		pitch_base: float = 1.0) -> void:
	## Plays a random variant of the given event. Pitch is jittered by ±pitch_jitter
	## around pitch_base so rapid-fire plays (e.g. multiple hits in a turn) don't
	## sound mechanical. pitch_base below 1.0 deepens a cue — how one clip serves
	## as both a strike and a muffled heartbeat, or a turn horn and a boss horn.
	var key := event_name
	if not _sfx_streams.has(key):
		key = String(SFX_FALLBACKS.get(key, key))
	if not _sfx_streams.has(key):
		return
	var streams: Array = _sfx_streams[key]
	if streams.is_empty():
		return
	var stream: AudioStream = streams[randi() % streams.size()]
	var player := _sfx_pool[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % _sfx_pool.size()
	player.stream = stream
	player.pitch_scale = pitch_base * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	player.volume_db = volume_db
	player.play()


func has_sfx(event_name: String) -> bool:
	# Mirrors play_sfx's fallback resolution: "true" means a call will make sound.
	return _sfx_streams.has(event_name) \
		or _sfx_streams.has(String(SFX_FALLBACKS.get(event_name, "")))


func has_own_sfx(event_name: String) -> bool:
	# True only when the cue's OWN dir has clips — fallback NOT considered.
	# Call sites use this to apply stand-in-specific pitching (a UI click posing
	# as a doom tick wants to be pitched down; the real clip, once it lands,
	# should play straight).
	return _sfx_streams.has(event_name)


# ---------------------------------------------------------------------------
# MUSIC DUCKING
# ---------------------------------------------------------------------------

var _duck_tween: Tween = null
var _duck_db: float = 0.0  # currently-applied duck offset (≤ 0)

func duck_music(depth_db: float = -6.0, hold: float = 0.9, attack: float = 0.08,
		release: float = 0.7) -> void:
	## Momentarily dips the Music bus so a stinger (victory, defeat, boss horn)
	## reads over the track instead of fighting it. Applied as a RELATIVE offset
	## on top of whatever level the user's Music slider set — UserSettings owns
	## the base; every step removes the previous offset before applying the new
	## one, so overlapping ducks never stack or drift.
	if AudioServer.get_bus_index("Music") == -1:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_apply_music_duck, _duck_db, depth_db, attack)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(_apply_music_duck, depth_db, 0.0, release)
	_duck_tween.tween_callback(_end_music_duck)


func _apply_music_duck(db: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus == -1:
		return
	var base := AudioServer.get_bus_volume_db(bus) - _duck_db
	_duck_db = db
	AudioServer.set_bus_volume_db(bus, base + db)


func _end_music_duck() -> void:
	# Re-assert the slider level so a mid-duck settings change can't leave a
	# stale offset baked into the bus.
	_duck_db = 0.0
	var us := get_node_or_null("/root/UserSettings")
	if us != null and us.has_method("_apply_volume") and "music_volume" in us:
		us._apply_volume(AudioServer.get_bus_index("Music"), us.music_volume)


# ---------------------------------------------------------------------------
# MUSIC PLAY
# ---------------------------------------------------------------------------

# Per-track resume positions, saved whenever a track is crossfaded out. A
# track that re-enters rotation continues where it left off instead of
# replaying its intro — hearing the same 8-second opening fifteen times a run
# is half of what makes a small library feel repetitive.
var _music_positions: Dictionary = {}
# Session cache: track_name -> AudioStream. The library's files run up to
# ~18 MB; a synchronous load() at scene entry was a visible main-thread hitch
# (every screen rotates music, so it fired on transition after transition).
# Each track now loads ONCE per session, on ResourceLoader's worker threads.
var _music_streams: Dictionary = {}
# The track the game currently WANTS playing. play_music sets it immediately;
# the async loader only starts a track if it still matches when the load lands
# (a rapid scene skip or stop_music may have superseded the request).
var _pending_music_track: String = ""
var _pending_music_fade: float = 1.0
# Paths with an in-flight threaded request, so overlapping play_music calls
# for the same track don't double-request (load_threaded_get consumes the
# request — a second getter would read an invalid handle).
var _music_inflight: Dictionary = {}

func play_music(track_name: String, fade_seconds: float = 1.0) -> void:
	## Crossfades into the named music track. If the same track is already
	## playing, this is a no-op. Looks for assets/audio/music/<name>.ogg or .wav.
	## First play of a track loads it on a background thread — the crossfade
	## starts a few frames later instead of freezing the scene transition.
	if _current_music_track == track_name:
		return
	var path := _resolve_music_path(track_name)
	if path == "":
		return
	_pending_music_track = track_name
	_pending_music_fade = fade_seconds
	if _music_streams.has(track_name):
		_start_music_stream(_music_streams[track_name], track_name, fade_seconds)
		return
	if _music_inflight.has(path):
		return  # already loading — the in-flight coroutine will honor _pending
	_load_music_async(track_name, path)


func _load_music_async(track_name: String, path: String) -> void:
	# Fire-and-forget coroutine: threaded file read + decode, then start the
	# crossfade if this track is still the one the game wants.
	if ResourceLoader.load_threaded_request(path) != OK:
		var res = load(path)  # fallback: the old synchronous path
		if res is AudioStream:
			_music_streams[track_name] = res
			if _pending_music_track == track_name:
				_start_music_stream(res, track_name, _pending_music_fade)
		return
	_music_inflight[path] = true
	while true:
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			if not is_inside_tree():
				_music_inflight.erase(path)
				return
			continue
		break
	_music_inflight.erase(path)
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var stream = ResourceLoader.load_threaded_get(path)
	if not (stream is AudioStream):
		return
	_music_streams[track_name] = stream
	if _pending_music_track == track_name and _current_music_track != track_name:
		_start_music_stream(stream, track_name, _pending_music_fade)


func _start_music_stream(stream: AudioStream, track_name: String,
		fade_seconds: float) -> void:
	# AudioStreamOggVorbis / WAV both support loop, but defaults vary. Force it
	# on so menu music doesn't silently end after one play.
	if "loop" in stream:
		stream.loop = true
	var incoming := _music_b if _music_active == _music_a else _music_a
	var outgoing := _music_active
	if _current_music_track != "" and outgoing != null and outgoing.playing:
		_music_positions[_current_music_track] = outgoing.get_playback_position()
	incoming.stream = stream
	incoming.volume_db = FADE_QUIET_DB
	var resume_at: float = float(_music_positions.get(track_name, 0.0))
	var track_len: float = stream.get_length()
	if track_len > 0.0:
		resume_at = fmod(resume_at, track_len)
	incoming.play(resume_at)
	_music_active = incoming
	_current_music_track = track_name
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, fade_seconds)
	if outgoing != null and outgoing.playing:
		tw.tween_property(outgoing, "volume_db", FADE_QUIET_DB, fade_seconds)
		tw.chain().tween_callback(outgoing.stop)


func play_music_random(candidates: Array, fade_seconds: float = 1.0) -> void:
	## Picks one track at random from the candidates and crossfades to it. If the
	## currently-playing track is in the pool, it is excluded so two consecutive
	## fights never start on the same song (assuming the pool has 2+ entries).
	if candidates.is_empty():
		return
	if candidates.size() == 1:
		play_music(String(candidates[0]), fade_seconds)
		return
	var pool: Array = candidates.duplicate()
	if _current_music_track != "" and pool.has(_current_music_track):
		pool.erase(_current_music_track)
	var pick: String = String(pool[randi() % pool.size()])
	play_music(pick, fade_seconds)


func stop_music(fade_seconds: float = 0.6) -> void:
	_pending_music_track = ""  # cancel any in-flight async play
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


# ---------------------------------------------------------------------------
# AMBIENCE (looping background SFX like campfire crackle, wind, rain)
# ---------------------------------------------------------------------------

func play_ambience(event_name: String, fade_seconds: float = 0.8,
		volume_db: float = -6.0) -> void:
	## Crossfades into a looping ambient sound. Looks up the first audio file
	## under assets/audio/sfx/<event_name>/. No-op if the directory is empty so
	## the game runs identically whether ambience assets exist or not.
	if _current_ambience == event_name:
		return
	if not _sfx_streams.has(event_name):
		# Ambience asset missing — silently stop any current loop so we don't
		# leave the previous screen's crackle bleeding into this one.
		stop_ambience(fade_seconds)
		return
	var streams: Array = _sfx_streams[event_name]
	if streams.is_empty():
		stop_ambience(fade_seconds)
		return
	var stream: AudioStream = streams[0]
	# Force loop so a 4-second crackle loops indefinitely instead of playing once.
	# Some Godot AudioStream variants (Ogg, WAV) expose `loop`; MP3 does not.
	if "loop" in stream:
		stream.loop = true
	_ambience_player.stop()
	_ambience_player.stream = stream
	_ambience_player.volume_db = FADE_QUIET_DB
	# Random start offset: a looping texture that always opens on the same
	# phrase reads as "that sound again" — starting mid-loop hides the seam.
	var loop_len: float = stream.get_length()
	_ambience_player.play(randf() * maxf(loop_len - 0.5, 0.0) if loop_len > 2.0 else 0.0)
	_current_ambience = event_name
	var tw := create_tween()
	tw.tween_property(_ambience_player, "volume_db", volume_db, fade_seconds)


func stop_ambience(fade_seconds: float = 0.6) -> void:
	if _ambience_player == null or _current_ambience == "":
		return
	_current_ambience = ""
	if _ambience_player.playing:
		var tw := create_tween()
		tw.tween_property(_ambience_player, "volume_db", FADE_QUIET_DB, fade_seconds)
		tw.tween_callback(_ambience_player.stop)
