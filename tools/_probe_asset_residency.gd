extends SceneTree
## Focused headless probe for bounded card-art and decoded-music residency.
## Run: Godot --headless --path . --script res://tools/_probe_asset_residency.gd

var _fails: int = 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_probe_card_art_lrus()
	_probe_music_lru()
	print("RESULT: %s (%d fails)" % [
		"ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _probe_card_art_lrus() -> void:
	CardArtAliases.clear_runtime_caches()
	var held_creature: Texture2D = GradientTexture1D.new()
	CardArtAliases._remember_creature_art("held_creature", held_creature)
	for i in range(CardArtAliases.MAX_CREATURE_ART_ENTRIES + 2):
		CardArtAliases._remember_creature_art(
			"creature_%d" % i, GradientTexture1D.new())
	_check(CardArtAliases._creature_art_cache.size() \
		== CardArtAliases.MAX_CREATURE_ART_ENTRIES,
		"creature-art LRU remains at its cap")
	_check(not CardArtAliases._creature_art_cache.has("held_creature"),
		"least-recent creature-art reference is evicted")
	_check(is_instance_valid(held_creature),
		"eviction does not invalidate a texture held by a live consumer")
	_check(CardArtAliases._creature_art_cache.has(
		"creature_%d" % (CardArtAliases.MAX_CREATURE_ART_ENTRIES + 1)),
		"most-recent creature art remains resident")

	var held_spell: Texture2D = GradientTexture1D.new()
	CardArtAliases._remember_spell_art("held_spell", held_spell)
	for i in range(CardArtAliases.MAX_SPELL_ART_ENTRIES + 2):
		CardArtAliases._remember_spell_art(
			"spell_%d" % i, GradientTexture1D.new())
	_check(CardArtAliases._spell_art_cache.size() \
		== CardArtAliases.MAX_SPELL_ART_ENTRIES,
		"spell-art LRU remains at its cap")
	_check(not CardArtAliases._spell_art_cache.has("held_spell"),
		"least-recent spell-art reference is evicted")
	_check(is_instance_valid(held_spell),
		"spell texture survives removal of the cache reference")

	CardArtAliases._threaded_path_cache.clear()
	CardArtAliases._threaded_path_lru.clear()
	CardArtAliases._threaded_path_busy.clear()
	var busy_tex: Texture2D = GradientTexture1D.new()
	CardArtAliases._remember_texture_path("busy_path", busy_tex)
	CardArtAliases._threaded_path_busy["busy_path"] = true
	for i in range(CardArtAliases.MAX_THREADED_PATH_ENTRIES + 2):
		CardArtAliases._remember_texture_path(
			"path_%d" % i, GradientTexture1D.new())
	_check(CardArtAliases._threaded_path_cache.size() \
		== CardArtAliases.MAX_THREADED_PATH_ENTRIES,
		"threaded-path LRU remains at its cap")
	_check(CardArtAliases._threaded_path_cache.has("busy_path"),
		"threaded-path LRU protects a joined in-flight request")
	CardArtAliases._threaded_path_busy.erase("busy_path")
	CardArtAliases.release_texture_path("busy_path")
	_check(not CardArtAliases._threaded_path_cache.has("busy_path") \
		and not CardArtAliases._threaded_path_lru.has("busy_path"),
		"explicit path release removes both cache and recency entry")
	CardArtAliases.clear_runtime_caches()
	CardArtAliases._threaded_path_busy.clear()


func _probe_music_lru() -> void:
	var audio: Node = root.get_node_or_null("AudioBank")
	_check(audio != null, "AudioBank autoload present")
	if audio == null:
		return
	audio._music_streams.clear()
	audio._music_stream_lru.clear()
	audio._music_inflight.clear()
	audio._current_music_track = ""
	audio._pending_music_track = ""
	audio._music_a.stop()
	audio._music_b.stop()
	audio._music_a.stream = null
	audio._music_b.stream = null

	var held_music: AudioStream = AudioStreamWAV.new()
	audio._music_positions["held_music"] = 12.5
	audio._remember_music_stream("held_music", held_music)
	for i in range(audio.MAX_MUSIC_STREAM_ENTRIES + 2):
		audio._remember_music_stream("music_%d" % i, AudioStreamWAV.new())
	_check(audio._music_streams.size() == audio.MAX_MUSIC_STREAM_ENTRIES,
		"decoded-music LRU remains at six tracks")
	_check(not audio._music_streams.has("held_music"),
		"least-recent decoded music is evicted")
	_check(is_instance_valid(held_music),
		"music eviction only removes the cache reference")
	_check(is_equal_approx(float(audio._music_positions.get("held_music", 0.0)), 12.5),
		"resume positions survive decoded-stream eviction")

	audio._music_streams.clear()
	audio._music_stream_lru.clear()
	var current_stream: AudioStream = AudioStreamWAV.new()
	var pending_stream: AudioStream = AudioStreamWAV.new()
	var loading_stream: AudioStream = AudioStreamWAV.new()
	var player_a_stream: AudioStream = AudioStreamWAV.new()
	var player_b_stream: AudioStream = AudioStreamWAV.new()
	audio._remember_music_stream("current", current_stream)
	audio._remember_music_stream("pending", pending_stream)
	audio._remember_music_stream("loading", loading_stream)
	audio._remember_music_stream("player_a", player_a_stream)
	audio._remember_music_stream("player_b", player_b_stream)
	audio._current_music_track = "current"
	audio._pending_music_track = "pending"
	audio._music_inflight["res://probe_loading.ogg"] = "loading"
	audio._music_a.stream = player_a_stream
	audio._music_b.stream = player_b_stream
	for i in 4:
		audio._remember_music_stream("disposable_%d" % i, AudioStreamWAV.new())
	_check(audio._music_streams.size() == audio.MAX_MUSIC_STREAM_ENTRIES,
		"protected music entries do not make the LRU exceed its cap")
	for key in ["current", "pending", "loading", "player_a", "player_b"]:
		_check(audio._music_streams.has(key),
			"music LRU protects %s stream" % key)
	audio._current_music_track = ""
	audio._pending_music_track = ""
	audio._music_inflight.clear()
	audio._music_streams.clear()
	audio._music_stream_lru.clear()
	audio._music_a.stream = null
	audio._music_b.stream = null
