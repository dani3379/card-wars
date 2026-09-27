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
const FADE_QUIET_DB := -40.0  # "silent" level for ambience fade ends
const MAX_MUSIC_STREAM_ENTRIES := 6
# Floor for the music crossfade. Deeper than FADE_QUIET_DB because the
# equal-power law (see _crossfade_step) only reaches the floor at the very ends
# of the fade, where the other track is at full level and masks it completely —
# so there is no reason to stop 40 dB short of silence and hear the tail.
const FADE_FLOOR_DB := -60.0

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
	"relic_trigger": "coin",
	"potion_use": "heal",
	"upgrade_confirm": "coin",
	"doom_tick": "button_click",
	"boss_intro": "turn_start",
	# Event gamble stage (2026-07-18): knucklebone cast/settle, coin pours
	# into the pot, the spinner finally falling flat. Real clips auto-win
	# once assets/audio/sfx/<name>/ lands.
	"bone_cast": "card_play",
	"bone_settle": "button_click",
	"coin_pour": "coin",
	"coin_fall": "hit",
	# The 2026-07-18 second wave: shell-game passes, the drawn lot, the
	# candle guttering out.
	"helm_slide": "card_play",
	"paper_draw": "card_draw",
	"candle_out": "button_click",
	# Take Aim (2026-07-21 sniper rework): the marksman accepting a standing
	# order. A real bolt-nock / bowstring-creak clip auto-wins once
	# assets/audio/sfx/sniper_aim/ lands.
	"sniper_aim": "button_click",
	# THE REFUSAL CUE (2026-07-28). "error" was the ONLY sound any refusal in the
	# game played, and it had neither a clip dir nor an alias — so the one refusal
	# that bothered to make a noise made none, and tools/_probe_audio_cues.gd was
	# failing on it. A dry click stands in until a real short scrape lands; it must
	# never be a sting, because a refusal is not an impact.
	"refused": "button_click",
	# THE SHELL'S FOUR CUES (2026-08-05). Until this pass the entire shell —
	# title screen, THE MUSTER, settings, collection, credits — played NOTHING on
	# interaction: MainMenu/SettingsOverlay/Collection/Credits held zero play_sfx
	# call sites between them, and not one of the 40 `mouse_entered` handlers in
	# scripts/ made a sound. Meanwhile the clash has hitstop and a shuffle bag.
	#
	# Four cues cover every shell button, voiced as the game's own materials
	# rather than as UI beeps:
	#   ui_hover  — a dry paper tick under the cursor. The one cue that must
	#               never fatigue: it fires hundreds of times a session, so it
	#               plays quiet and wide-jittered (see UI_CUE_MIX).
	#   ui_select — a card set down on wood. A pick that does NOT advance.
	#   ui_back   — the same paper drawn back, pitched DOWN, so retreat and
	#               advance are distinguishable with the screen unread.
	#   ui_commit — a wax seal pressed. NEW MARCH and TAKE THE FIELD are the two
	#               moments a player commits 40 minutes; they sounded like
	#               nothing at all.
	# Real clips auto-win the moment assets/audio/sfx/<name>/ lands.
	"ui_hover": "card_draw",
	"ui_select": "card_play",
	"ui_back": "card_discard",
	"ui_commit": "upgrade_confirm",
}

## THE SHELL AUDIO FUNNEL (2026-08-05).
##
## Every shell interaction goes through play_ui() rather than calling play_sfx
## with hand-picked numbers, so the four cues keep ONE voice across MainMenu, the
## muster, SettingsOverlay, Collection, NetLobby and Credits. Levels and jitter
## are set once, here. The hover cue's level is load-bearing: it is the only
## sound in the game that fires on mouse MOVEMENT, so it sits far enough down
## that sweeping a column reads as texture rather than as a stutter of clicks.
const UI_CUE_MIX := {
	"hover": {"db": -17.0, "jitter": 0.10, "pitch": 1.20},
	"select": {"db": -7.0, "jitter": 0.07, "pitch": 1.06},
	"back": {"db": -9.0, "jitter": 0.07, "pitch": 0.88},
	"commit": {"db": -3.0, "jitter": 0.05, "pitch": 1.0},
}

# The frame the last UI cue sounded on, and which cue won it — see play_ui's
# one-press-one-sound note. The kind is recorded so the collapse is OBSERVABLE:
# without it a gate can tell that only one cue played but not that the right one
# survived, which is the half that actually breaks (a screen's "commit" losing
# to the funnel's default "select" is silent and sounds almost correct).
var _ui_cue_frame: int = -1
var _ui_cue_kind: String = ""

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
	_music_a.volume_db = FADE_FLOOR_DB
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	_music_b.volume_db = FADE_FLOOR_DB
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
	var stream: AudioStream = _draw_variant(key, streams)
	var player := _sfx_pool[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % _sfx_pool.size()
	player.stream = stream
	player.pitch_scale = pitch_base * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	player.volume_db = volume_db
	player.play()


func play_ui(kind: String) -> void:
	## The shell's interaction voice. kind: "hover" | "select" | "back" | "commit".
	##
	## ONE PRESS IS ONE SOUND (2026-09-17). Since the press funnel gives every
	## button a default cue, a screen that already plays its own would layer two
	## clicks a few milliseconds apart — the stutter UI_CUE_MIX's hover level
	## exists to avoid, arriving by a different route. A cue is therefore dropped
	## if one already sounded THIS FRAME.
	##
	## The frame, not a time window. A window has to be guessed against how long
	## a player holds a button, which is unbounded; every pair this needs to
	## collapse is emitted from one `pressed` signal and is exact on the frame
	## counter. Deliberately across KINDS as well as within one: the pair being
	## collapsed is usually a screen's "commit" against the funnel's "select",
	## and dropping the quieter default is the entire intent. First one wins,
	## which is why the funnel connects deferred — see GameTheme's press funnel.
	##
	## Written as four LITERAL play_sfx calls rather than the obvious
	## `play_sfx("ui_" + kind, ...)`. The one-liner is prettier and it is wrong
	## here for two reasons: `tools/_probe_audio_cues.gd` scans for
	## `play_sfx("<literal>")` and reported the whole funnel as one silent cue
	## named `ui_` (caught on the first run of this gate), and a grep for
	## "ui_commit" would have found no call site at all. Same house lesson as the
	## relic `effect` strings — a name assembled at runtime is a name nothing can
	## verify. The numbers come from UI_CUE_MIX so the levels stay in one place.
	var frame: int = Engine.get_process_frames()
	if frame == _ui_cue_frame:
		return
	_ui_cue_frame = frame
	_ui_cue_kind = kind
	match kind:
		"hover":
			play_sfx("ui_hover", UI_CUE_MIX.hover.jitter,
				UI_CUE_MIX.hover.db, UI_CUE_MIX.hover.pitch)
		"select":
			play_sfx("ui_select", UI_CUE_MIX.select.jitter,
				UI_CUE_MIX.select.db, UI_CUE_MIX.select.pitch)
		"back":
			play_sfx("ui_back", UI_CUE_MIX.back.jitter,
				UI_CUE_MIX.back.db, UI_CUE_MIX.back.pitch)
		"commit":
			play_sfx("ui_commit", UI_CUE_MIX.commit.jitter,
				UI_CUE_MIX.commit.db, UI_CUE_MIX.commit.pitch)


## Shuffle-bag variant selection (2026-07-30) — the cheapest audio win in the repo.
##
## This was `streams[randi() % streams.size()]`. Most cues ship TWO clips, so
## that is a 50% chance of playing the same clip twice in a row — the single most
## fatiguing arrangement possible, and it fires 8-13 times a round in a clash. It
## is a large part of why combat reads as "samey but wobbly": the variation was
## random pitch on a repeating sample rather than an actually different sample.
##
## A bag holds one of each variant, draws without replacement, and refills when
## empty — so with 2 clips you get strict alternation, with 4 you get all four
## before any repeat. On refill the last-played clip is excluded from the first
## draw, which is the one seam where a bag can still stutter.
##
## The precedent is already in this file: play_music_random excludes the current
## track for exactly this reason. The idea simply never reached play_sfx.
var _sfx_bag: Dictionary = {}
var _sfx_last: Dictionary = {}

func _draw_variant(key: String, streams: Array) -> AudioStream:
	if streams.size() <= 1:
		return streams[0]
	var bag: Array = _sfx_bag.get(key, [])
	if bag.is_empty():
		for i in streams.size():
			bag.append(i)
		bag.shuffle()
		# Don't let a refill hand back the clip we just played.
		if bag.size() > 1 and _sfx_last.has(key) and bag[0] == _sfx_last[key]:
			var swap: int = bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = swap
	var idx: int = int(bag.pop_front())
	_sfx_bag[key] = bag
	_sfx_last[key] = idx
	return streams[clampi(idx, 0, streams.size() - 1)]


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
# Load on ResourceLoader's worker threads and retain a six-track working set;
# older tracks can leave memory and reload asynchronously if revisited later.
var _music_streams: Dictionary = {}
var _music_stream_lru: Array[String] = []
# The track the game currently WANTS playing. play_music sets it immediately;
# the async loader only starts a track if it still matches when the load lands
# (a rapid scene skip or stop_music may have superseded the request).
var _pending_music_track: String = ""
var _pending_music_fade: float = 1.0
# Paths with an in-flight threaded request, so overlapping play_music calls
# for the same track don't double-request (load_threaded_get consumes the
# request — a second getter would read an invalid handle).
var _music_inflight: Dictionary = {}
# The in-flight crossfade. One at a time, always — see _start_music_stream.
var _music_tween: Tween = null


func _touch_music_stream(track_name: String) -> void:
	_music_stream_lru.erase(track_name)
	_music_stream_lru.append(track_name)


func _remember_music_stream(track_name: String, stream: AudioStream) -> void:
	_music_streams[track_name] = stream
	_touch_music_stream(track_name)
	_trim_music_stream_cache()


func _music_stream_is_protected(track_name: String) -> bool:
	# Pending/current names protect the hand-off around an async load. Values in
	# _music_inflight are track names (keys remain ResourceLoader paths).
	if track_name == _current_music_track or track_name == _pending_music_track:
		return true
	for loading_track in _music_inflight.values():
		if String(loading_track) == track_name:
			return true
	var stream := _music_streams.get(track_name) as AudioStream
	if stream == null:
		return false
	# Both players matter during a crossfade. Dropping our dictionary reference
	# would already be safe (the player owns one), but retaining it avoids a
	# needless reload if the outgoing track is requested before the fade ends.
	return (_music_a != null and _music_a.stream == stream) \
		or (_music_b != null and _music_b.stream == stream)


func _trim_music_stream_cache() -> void:
	var remaining := _music_stream_lru.size()
	while _music_streams.size() > MAX_MUSIC_STREAM_ENTRIES \
			and remaining > 0 and not _music_stream_lru.is_empty():
		var oldest: String = _music_stream_lru.pop_front()
		if _music_stream_is_protected(oldest):
			_music_stream_lru.append(oldest)
			remaining -= 1
			continue
		_music_streams.erase(oldest)
		remaining = _music_stream_lru.size()

func play_music(track_name: String, fade_seconds: float = 1.0) -> void:
	## Crossfades into the named music track. If the same track is already
	## playing, this is a no-op. Looks for assets/audio/music/<name>.ogg or .wav.
	## First play of a track loads it on a background thread — the crossfade
	## starts a few frames later instead of freezing the scene transition.
	if _current_music_track == track_name:
		if _music_streams.has(track_name):
			_touch_music_stream(track_name)
		return
	var path := _resolve_music_path(track_name)
	if path == "":
		return
	_pending_music_track = track_name
	_pending_music_fade = fade_seconds
	if _music_streams.has(track_name):
		_touch_music_stream(track_name)
		_start_music_stream(_music_streams[track_name] as AudioStream,
			track_name, fade_seconds)
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
			_remember_music_stream(track_name, res)
			if _pending_music_track == track_name:
				_start_music_stream(res, track_name, _pending_music_fade)
		return
	_music_inflight[path] = track_name
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
	_remember_music_stream(track_name, stream)
	if _pending_music_track == track_name and _current_music_track != track_name:
		_start_music_stream(stream, track_name, _pending_music_fade)


func _start_music_stream(stream: AudioStream, track_name: String,
		fade_seconds: float) -> void:
	# AudioStreamOggVorbis / WAV both support loop, but defaults vary. Force it
	# on so menu music doesn't silently end after one play.
	#
	# AudioStreamSynchronized has NO `loop` property of its own — read the engine
	# source, not the class docs, for why this matters: its mix() ends with
	# `if (!any_active) active = false;`, so the moment every sub-stream runs out
	# the whole layered cue stops dead. Looping has to be set on each LAYER.
	if stream is AudioStreamSynchronized:
		# Explicit local: an `is` check does not narrow the type for `:=`
		# inference, so `var sub := stream.get_sync_stream(i)` is a hard parse
		# error ("cannot infer the type") rather than a warning.
		var sync_stream: AudioStreamSynchronized = stream
		for i in sync_stream.stream_count:
			var sub: AudioStream = sync_stream.get_sync_stream(i)
			if sub != null and "loop" in sub:
				sub.loop = true
	elif "loop" in stream:
		stream.loop = true
		# Leaving a layered cue: drop its tweens, or they go on writing volumes
		# into a cached resource that is no longer the thing playing.
		if not _layer_targets.is_empty():
			_kill_layer_tweens()
			_layer_targets.clear()
	var incoming := _music_b if _music_active == _music_a else _music_a
	var outgoing := _music_active
	if _current_music_track != "" and outgoing != null and outgoing.playing:
		_music_positions[_current_music_track] = outgoing.get_playback_position()
	incoming.stream = stream
	# Silent for the one frame between play() and the tween's first step.
	incoming.volume_db = FADE_FLOOR_DB
	var resume_at: float = float(_music_positions.get(track_name, 0.0))
	var track_len: float = stream.get_length()
	if track_len > 0.0:
		resume_at = fmod(resume_at, track_len)
	incoming.play(resume_at)
	_music_active = incoming
	_current_music_track = track_name
	# A second crossfade arriving mid-fade must not leave two tweens writing the
	# same two volume_db properties — the loser would go on driving a player the
	# winner had just started, and the old tween's trailing stop() callback would
	# kill it outright. Only two players exist, so killing the previous fade and
	# re-deriving both roles from _music_active is the whole fix.
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_method(_crossfade_step.bind(incoming, outgoing),
		0.0, 1.0, maxf(fade_seconds, 0.01))
	_music_tween.tween_callback(_end_crossfade.bind(incoming, outgoing))


## THE CROSSFADE HAS TO BE EQUAL-POWER (2026-09-14).
##
## This used to be two parallel `tween_property(player, "volume_db", ...)` calls
## — incoming −40→0, outgoing 0→−40. That interpolates LINEARLY IN DECIBELS,
## which is exponential in amplitude, so at the midpoint both tracks sit at
## −20 dB, i.e. a tenth of their amplitude EACH. Two tenths do not make a whole:
## the sum lands ~17 dB below either endpoint, and the music audibly drops out
## in the middle of the transition and climbs back.
##
## MEASURED on the real assets (map.mp3 crossfading to combat.mp3 over the
## shipped 1.0 s, rendered and RMS-metered per 100 ms): steady state −13 dBFS,
## and the old law fell to −34 dBFS mid-fade. A 21 dB hole, on every transition,
## roughly a hundred times a run. It is most of why the score "sounds weird" —
## the tracks are fine, the seam between them was a dropout.
##
## The fix is the standard constant-power law: amplitude in = sin(t·π/2),
## out = cos(t·π/2), so in² + out² = 1 at every t and two uncorrelated sources
## sum to a flat level. Same measurement with this law: −19.6 dBFS at its
## deepest, and that residue is the material (combat.mp3 is genuinely 3 dB
## quieter than map.mp3 here), not the fade.
##
## NOTE the conversion order. The law is defined on AMPLITUDE and the player
## takes DECIBELS, so the sin/cos must be computed first and converted after —
## running the curve on volume_db directly is the bug this replaces.
func _crossfade_step(t: float, incoming: AudioStreamPlayer,
		outgoing: AudioStreamPlayer) -> void:
	if incoming != null:
		incoming.volume_db = _fade_gain_db(sin(t * PI * 0.5))
	if outgoing != null and outgoing != incoming and outgoing.playing:
		outgoing.volume_db = _fade_gain_db(cos(t * PI * 0.5))


func _end_crossfade(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer) -> void:
	if incoming != null:
		incoming.volume_db = 0.0
	if outgoing != null and outgoing != incoming and outgoing.playing:
		outgoing.stop()
		outgoing.volume_db = FADE_FLOOR_DB


func _fade_gain_db(amp: float) -> float:
	# linear_to_db(0.0) is -inf, which a volume_db write will not accept.
	return FADE_FLOOR_DB if amp <= 0.001 else maxf(linear_to_db(amp), FADE_FLOOR_DB)


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


## THEMES — THE ANTI-REPETITION FEATURE WAS CAUSING THE REPETITION (2026-09-14).
##
## play_music_random EXCLUDES the currently-playing track, so any screen that
## re-rolls its pool on entry is GUARANTEED to change track every single time.
## MapView did exactly that, and the act skeleton returns the player to the chart
## after every one of its ~18 stops — so no road theme was ever heard twice
## running, in any run, ever. Nobody could hum a tune from this game because no
## tune was ever established, and every forced change also paid a crossfade.
##
## The fix is the opposite of the instinct that produced the bug: a THEME is
## chosen ONCE and then HELD. Recognition is what repetition buys; fatigue comes
## from literal UNVARIED repetition, which is a different thing (Margulis, *On
## Repeat* — the exposure effect raises liking and then reverses, and it is the
## literal repeat that reverses it, not the familiarity).
##
## Variety is kept on the axis where it costs nothing: the pick is re-rolled per
## RUN, never per visit. Inside a run the act's road theme is the thing you march
## to; across runs — and a roguelike is played fifty times — you get another one.
##
## KEY NAMESPACES ARE LOAD-BEARING. Only "run:*" keys are dropped by
## clear_music_themes() (called from RunState.start_new_run). Anything else
## survives, which is how the menu keeps one voice for a whole session while the
## road re-rolls every march.
var _themes: Dictionary = {}


func play_music_theme(key: String, candidates: Array, fade_seconds: float = 1.0) -> void:
	if candidates.is_empty():
		return
	var pick: String = String(_themes.get(key, ""))
	# Re-roll when unset, or when the remembered pick is no longer IN the pool —
	# a book edited between sessions must not strand a theme on a dead name,
	# which would silently no-op play_music and leave the screen quiet.
	if pick == "" or not candidates.has(pick):
		pick = String(candidates[randi() % candidates.size()])
		_themes[key] = pick
	play_music(pick, fade_seconds)


func clear_music_themes() -> void:
	## Drops run-scoped themes so the next march draws fresh ones. keys() returns
	## a copy, so erasing while walking it is safe.
	for k in _themes.keys():
		if String(k).begins_with("run:"):
			_themes.erase(k)


func current_music_theme(key: String) -> String:
	## For probes and for any caller that needs to know what a theme resolved to
	## without starting it. "" means the theme has not been drawn yet.
	return String(_themes.get(key, ""))


## THE ROAD'S BOOKS, keyed by act.
##
## Every other music pool in this game lives at its call site, and that is still
## the convention. This one is here because TWO screens must reach the SAME
## answer: MapView paints the chart, and Wayside is a stop ON that chart which
## deliberately does NOT change the music. Two copies of this table would drift,
## and the symptom of drift is subtle — a crossfade appearing on the one screen
## whose whole point is that it doesn't get one.
const ROAD_BOOKS := {
	1: ["map", "map_b", "map_e"],
	2: ["map_act2", "map_c", "map_d"],
	3: ["map_act3", "map", "map_d"],
}


func play_road_theme(act: int, fade_seconds: float = 1.0) -> void:
	## The march's own voice for this act, held for the whole run. Calling it
	## when it is already playing is a no-op by way of play_music, which is what
	## lets a wayside sit inside the road music instead of interrupting it.
	var a: int = clampi(act, 1, 3)
	play_music_theme("run:road:%d" % a, ROAD_BOOKS[a], fade_seconds)


# ---------------------------------------------------------------------------
# VERTICAL LAYERING (2026-09-14)
# ---------------------------------------------------------------------------
##
## A LAYERED CUE is one piece of music whose ARRANGEMENT responds to the game:
## the same bars throughout, with instrument layers faded in and out. Because
## every layer is the same bar of the same recording there is no transition to
## get wrong — which is the whole reason this is the technique that beats
## fatigue. A theme heard fifty times but never twice in the same clothes does
## not wear out the way a literal repeat does.
##
## Built on AudioStreamSynchronized. THE CONTRACT, READ OUT OF THE ENGINE SOURCE
## (modules/interactive_music/audio_stream_synchronized.cpp) because the class
## docs do not state it:
##
##   * mix() re-reads `stream->audio_stream_volume_db[i]` on EVERY mix call, so
##     set_sync_stream_volume DOES take effect live. This is the load-bearing
##     fact for the whole feature and it is not documented anywhere.
##   * …but it applies per MIX_BUFFER_SIZE (128 frames, ~2.7 ms) as a STEP. A
##     snapped volume change is a discontinuity, i.e. a click. Layers must be
##     TWEENED, never assigned. set_music_layer is the only writer, and it
##     tweens.
##   * start(pos) starts every sub-playback at the same position, which is what
##     keeps the layers sample-locked. Never drive layers with N separate
##     AudioStreamPlayers — they drift.
##   * MAX_STREAMS is 32.
##
## The layered stream is just an AudioStream, so it rides the ordinary
## play_music path and inherits the equal-power crossfade, the resume position
## and the async load for free.
const MAX_MUSIC_LAYERS := 8
## Silence for a layer that is off. Low enough to be inaudible under the bed,
## high enough that db_to_linear stays well away from denormals.
const LAYER_OFF_DB := -60.0
## A layer move is a mix decision, not an effect — it should be felt and not
## noticed. Fast enough to answer the board, slow enough to hide the 2.7 ms
## stepping described above.
const LAYER_FADE_SECS := 1.2

var _layer_tweens: Array[Tween] = []
var _layer_targets: Array[float] = []


## THE LAYERED CUE REGISTRY.
##
## Layer ORDER is the contract every caller depends on — index 0 is the bed and
## must be the layer that can stand alone. The stems were separated from the
## original master with Demucs (see docs/MUSIC_SYSTEM_AUDIT_20260914.md §Step 6);
## the pop-trained model's four stems do NOT map cleanly onto orchestral music,
## so what ships is a three-layer arrangement rather than the textbook
## drums/bass/other: on this track the bass stem measured -49 LUFS, 31 dB under
## the mix, because there is no bass-guitar-shaped source for it to find. It is
## folded into the bed rather than wasted on a layer that does nothing.
## KEYS ARE THE ACT'S ANCHOR TRACK NAME — Combat derives the key from pool[0],
## so the layered cue and the flat fallback are always the same piece of music
## and a missing stem set is inaudible as a change of plan.
const LAYERED_CUES := {
	# act 1 — Nakarada, "The Great Battle"
	"combat": [
		"res://assets/audio/music/layers/combat_bed.ogg",    # 0 strings/brass — stands alone
		"res://assets/audio/music/layers/combat_perc.ogg",   # 1 percussion — the drive
		"res://assets/audio/music/layers/combat_choir.ogg",  # 2 voices — the stakes
	],
	# act 2 — Buckley, "Monomyth: The Endurance"
	"combat_act2": [
		"res://assets/audio/music/layers/combat_act2_bed.ogg",
		"res://assets/audio/music/layers/combat_act2_perc.ogg",
		"res://assets/audio/music/layers/combat_act2_choir.ogg",
	],
	# act 3 — Buckley, "Monomyth: The Fury"
	"combat_act3": [
		"res://assets/audio/music/layers/combat_act3_bed.ogg",
		"res://assets/audio/music/layers/combat_act3_perc.ogg",
		"res://assets/audio/music/layers/combat_act3_choir.ogg",
	],
	# Generals — Buckley, "March of Midnight"
	"combat_elite": [
		"res://assets/audio/music/layers/combat_elite_bed.ogg",
		"res://assets/audio/music/layers/combat_elite_perc.ogg",
		"res://assets/audio/music/layers/combat_elite_choir.ogg",
	],
	# THE KEEPS. One leitmotif per rival lord, so each gets its own arrangement.
	"combat_boss": [        # the Everflame (Kindler) — "Juggernaut"
		"res://assets/audio/music/layers/combat_boss_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_choir.ogg",
	],
	"combat_boss_b": [      # the Last Wall (Stalwart) — "Song of the Forge"
		"res://assets/audio/music/layers/combat_boss_b_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_b_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_b_choir.ogg",
	],
	"combat_boss_c": [      # the Grasswake (Raider) — "Vanguard"
		"res://assets/audio/music/layers/combat_boss_c_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_c_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_c_choir.ogg",
	],
	"combat_boss_d": [      # the Lanternhall (Pyromancer) — "Hour of the Witch"
		"res://assets/audio/music/layers/combat_boss_d_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_d_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_d_choir.ogg",
	],
	"combat_boss_e": [      # the Owed (Acolyte) — "The Summoning"
		"res://assets/audio/music/layers/combat_boss_e_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_e_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_e_choir.ogg",
	],
	"combat_boss_act3": [   # the act 3 heavyweight — "Terminus"
		"res://assets/audio/music/layers/combat_boss_act3_bed.ogg",
		"res://assets/audio/music/layers/combat_boss_act3_perc.ogg",
		"res://assets/audio/music/layers/combat_boss_act3_choir.ogg",
	],
}


func layered_cue_available(key: String) -> bool:
	## A PARTIAL ARRANGEMENT IS WORSE THAN THE FLAT TRACK — a missing percussion
	## stem would not error, it would just quietly play a battle theme with no
	## drums. Callers use this to fall back to the ordinary cue, which is what
	## keeps the prototype safe to ship before every track has stems.
	if not LAYERED_CUES.has(key):
		return false
	for p in LAYERED_CUES[key]:
		if not ResourceLoader.exists(String(p)):
			return false
	return true


func play_layered_cue(key: String, fade_seconds: float = 1.0) -> void:
	if not layered_cue_available(key):
		return
	play_music_layered("layered:" + key, LAYERED_CUES[key], fade_seconds)


func play_music_layered(track_name: String, stem_paths: Array,
		fade_seconds: float = 1.0) -> void:
	## stem_paths[0] is the BED and comes up with the cue; every other layer
	## starts silent and is raised by set_music_layer.
	if stem_paths.is_empty():
		return
	if _current_music_track == track_name:
		return
	var sync := AudioStreamSynchronized.new()
	var streams: Array[AudioStream] = []
	for p in stem_paths:
		var path := String(p)
		if not ResourceLoader.exists(path):
			push_warning("[AudioBank] layered cue '%s' missing stem %s" % [track_name, path])
			return  # a partial arrangement is worse than the flat track
		var st = load(path)
		if not (st is AudioStream):
			return
		streams.append(st)
	sync.stream_count = mini(streams.size(), MAX_MUSIC_LAYERS)
	for i in sync.stream_count:
		sync.set_sync_stream(i, streams[i])
		sync.set_sync_stream_volume(i, 0.0 if i == 0 else LAYER_OFF_DB)
	_layer_targets.clear()
	for i in sync.stream_count:
		_layer_targets.append(0.0 if i == 0 else LAYER_OFF_DB)
	_kill_layer_tweens()
	_pending_music_track = track_name
	_pending_music_fade = fade_seconds
	_remember_music_stream(track_name, sync)
	_start_music_stream(sync, track_name, fade_seconds)


func set_music_layer(index: int, on: bool, fade_seconds: float = -1.0) -> void:
	## Raise or drop one layer. Safe to call every round — a call that asks for
	## the level a layer is already heading to is dropped, so a per-round
	## re-assertion does not restart the fade and stutter it.
	var target: float = 0.0 if on else LAYER_OFF_DB
	if index < 0 or index >= _layer_targets.size():
		return
	if is_equal_approx(_layer_targets[index], target):
		return
	var sync := _active_layered_stream()
	if sync == null:
		return
	_layer_targets[index] = target
	var secs: float = LAYER_FADE_SECS if fade_seconds < 0.0 else fade_seconds
	while _layer_tweens.size() <= index:
		_layer_tweens.append(null)
	if _layer_tweens[index] != null and _layer_tweens[index].is_valid():
		_layer_tweens[index].kill()
	var from_db: float = sync.get_sync_stream_volume(index)
	var tw := create_tween()
	# tween_method, not tween_property: the value lives on a RESOURCE behind a
	# setter, and the step has to go through set_sync_stream_volume.
	tw.tween_method(_layer_step.bind(index), from_db, target, maxf(secs, 0.01))
	_layer_tweens[index] = tw


func music_layer_is_on(index: int) -> bool:
	return index >= 0 and index < _layer_targets.size() \
		and not is_equal_approx(_layer_targets[index], LAYER_OFF_DB)


func music_layer_count() -> int:
	var sync := _active_layered_stream()
	return 0 if sync == null else sync.stream_count


func _layer_step(db: float, index: int) -> void:
	var sync := _active_layered_stream()
	if sync == null:
		return
	sync.set_sync_stream_volume(index, db)


func _active_layered_stream() -> AudioStreamSynchronized:
	# _layer_targets is the authority on whether layering is LIVE, not the
	# player's stream: AudioStreamPlayer.stop() does not clear `stream`, so after
	# stop_music the player still holds the synchronized resource and a
	# stream-based check would go on reporting three drivable layers over silence.
	# Combat guards on music_layer_count(), so that lie would have it driving a
	# cue that is not playing.
	if _music_active == null or _layer_targets.is_empty():
		return null
	return _music_active.stream as AudioStreamSynchronized


func _kill_layer_tweens() -> void:
	for tw in _layer_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_layer_tweens.clear()


func stop_music(fade_seconds: float = 0.6) -> void:
	_pending_music_track = ""  # cancel any in-flight async play
	_current_music_track = ""
	# Layer tweens write into a RESOURCE that outlives this playback (streams are
	# cached in _music_streams), so one left running would keep mutating the next
	# cue's arrangement after the music it belonged to had stopped.
	_kill_layer_tweens()
	_layer_targets.clear()
	# Kill any crossfade first: it owns both players' volume_db, and left running
	# it would fade one of them back UP underneath this fade-out.
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if not (_music_a != null and _music_a.playing) \
			and not (_music_b != null and _music_b.playing):
		return
	_music_tween = create_tween()
	_music_tween.tween_method(_fadeout_step, 0.0, 1.0, maxf(fade_seconds, 0.01))
	_music_tween.tween_callback(_end_fadeout)


func _fadeout_step(t: float) -> void:
	# Same cosine leg as the crossfade, so a stop sounds like the back half of a
	# transition rather than a different gesture.
	var db := _fade_gain_db(cos(t * PI * 0.5))
	for p in [_music_a, _music_b]:
		if p != null and p.playing:
			p.volume_db = db


func _end_fadeout() -> void:
	for p in [_music_a, _music_b]:
		if p != null and p.playing:
			p.stop()
			p.volume_db = FADE_FLOOR_DB


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
