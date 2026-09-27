extends SceneTree
## Readiness-aware visual QA for the real NetDraft pick screen.

const MATCH_SEED := 20260915
const DEADLINE_MS := 30000
const OUTPUT := "res://_perf_net_draft_atomic_final.png"

var _draft: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ss := root.get_node("SkirmishState")
	var nm := root.get_node("NetMatch")
	var cache := root.get_node("CardTextureCache")
	var settings := root.get_node("UserSettings")
	settings.reduce_motion = false
	settings.particles = false
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	nm.local_hero = "raider"
	nm.start_vs_bot(ss.MatchMode.DRAFT, 1)
	nm.match_seed = MATCH_SEED
	nm.match_mode = ss.MatchMode.DRAFT
	nm.best_of = 1
	ss.reset()
	cache.clear()
	CardArtAliases.clear_runtime_caches()

	_draft = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(_draft)
	await process_frame
	for _pick in 5:
		var deadline := Time.get_ticks_msec() + DEADLINE_MS
		while bool(_draft.call("arsenal_active")) \
				and not bool(_draft.call("arsenal_slate_ready")) \
				and Time.get_ticks_msec() < deadline:
			await process_frame
		if not bool(_draft.call("arsenal_active")):
			break
		if not bool(_draft.call("arsenal_slate_ready")):
			push_error("[draft-atomic-shot] Arsenal readiness timeout")
			quit(1)
			return
		_draft.call("_on_ars_pass")
		await process_frame

	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while not bool(_draft.get("_triplet_ready")) \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(_draft.get("_triplet_ready")):
		push_error("[draft-atomic-shot] triplet readiness timeout")
		quit(1)
		return
	await create_timer(0.45).timeout
	for _i in 3:
		await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT)
	print("[draft-atomic-shot] saved=", OUTPUT, " size=", image.get_size(),
		" error=", error)
	_draft.queue_free()
	for _i in 3:
		await process_frame
	root.get_node("AudioBank").stop_music(0.0)
	quit(0 if error == OK else 1)
