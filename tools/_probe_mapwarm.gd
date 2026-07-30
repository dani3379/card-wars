extends SceneTree
## MAP IDLE-WARM probe (2026-07-25). The companion to _probe_coldentry.gd.
##
## A fight only opens "cold" when the player commits to a map node faster than
## MapView's idle warm can finish. This probe boots the REAL map scene with a
## realistic deck and measures the actual warm curve:
##
##   * when the map becomes interactive (plate baked, node buttons up)
##   * when warm_run_deck actually STARTS baking (it opens with a fixed delay)
##   * how much of the deck is baked at each moment a player might click
##   * how long begin_warm_encounter_art takes for a real encounter
##
## The output is a "click at T ms -> X% warm" table, which is the only honest
## way to decide whether the warm needs changing.
##
## Run WINDOWED:
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       --script res://tools/_probe_mapwarm.gd -- --deck=30
##
## NOTE: probe scripts compile BEFORE autoloads register — never name Card2D /
## CardDB / MapView at compile time here.

const HERO := "pyromancer"
const RUN_SEED := 4242
const SAMPLE_SEC := 14.0
const PROBE_POINTS := [250, 500, 750, 1000, 1500, 2000, 2500, 3000,
	4000, 5000, 6000, 8000, 10000, 12000]

var RS: Node
var CTC: Node
var SP: Node
var EDB: Node
var US: Node
var mapv: Node
var _started := false
var _done := false
var _lines: Array[String] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _arg(name: String, def: int) -> int:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with(name):
			return int(String(a).substr(name.length()))
	return def


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	CTC = root.get_node_or_null("CardTextureCache")
	SP = root.get_node_or_null("ScenePreload")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	if RS == null or CTC == null or SP == null:
		_log("[mapwarm] FATAL autoloads missing")
		_finish()
		return
	if US != null:
		US.anim_speed = 1.0

	# Same premise as the cold-entry probe: the player has crossed the menu, so
	# ScenePreload's boot queue and card-pipeline prewarm are already retired.
	var waited := 0.0
	while waited < 20.0:
		if bool(SP.is_warmup_complete()) and bool(SP.get("_prewarmed")):
			break
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(1.0).timeout

	var want := _arg("--deck=", 30)
	RS.start_new_run(HERO, 0, RUN_SEED)
	_pad_deck(want)
	var uniq := _unique_deck_keys()
	_log("[mapwarm] deck=%d cards, %d unique bake keys" % [RS.deck.size(), uniq])

	CTC.clear()
	var CAA = load("res://scripts/data/CardArtAliases.gd")
	if CAA != null and CAA.has_method("clear_runtime_caches"):
		CAA.clear_runtime_caches()
	SP.invalidate_encounter_art_warm_state()
	# _deck_warm_busy latches for the life of a warm; make sure we start clean.
	SP.set("_deck_warm_busy", false)

	var scene = load("res://scenes/map.tscn")
	await process_frame
	var t0 := Time.get_ticks_usec()
	mapv = scene.instantiate()
	root.add_child(mapv)
	_log("[mapwarm] map add_child(_ready sync) = %.1f ms" % _ms(Time.get_ticks_usec() - t0))

	# Sample the warm curve every frame.
	var t_interactive := -1
	var t_first_bake := -1
	var t_hand_done := -1
	var t_all_done := -1
	var curve: Array = []   # [ms, hand_cache, battlefield_cache]
	# HARD CONSTRAINT guard: the warm must never be bought with map smoothness.
	# Sample every frame gap while the chart is opening (fade-in + focus glide)
	# and across the whole warm, so any regression shows up as a number.
	var gaps_open: Array[float] = []   # first 1.5 s — the entrance
	var gaps_all: Array[float] = []
	var prev := t0
	var deadline := t0 + int(SAMPLE_SEC * 1_000_000.0)
	while Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		var gap := _ms(now - prev)
		prev = now
		gaps_all.append(gap)
		if float(now - t0) / 1000.0 <= 1500.0:
			gaps_open.append(gap)
		var hand: int = CTC._cache.size()
		var bf: int = CTC._battlefield_cache.size()
		curve.append([_ms(now - t0), hand, bf])
		if t_interactive < 0 and _map_interactive():
			t_interactive = now
		if t_first_bake < 0 and hand > 0:
			t_first_bake = now
		if t_hand_done < 0 and hand >= uniq:
			t_hand_done = now
		if t_all_done < 0 and hand >= uniq and not bool(SP.get("_deck_warm_busy")):
			t_all_done = now
			break

	_log("[mapwarm] MAP SMOOTHNESS  entrance(0-1.5s): max gap %.1f ms, >50ms x%d | whole warm: max gap %.1f ms, >50ms x%d, >100ms x%d" % [
		_max(gaps_open), _over(gaps_open, 50.0),
		_max(gaps_all), _over(gaps_all, 50.0), _over(gaps_all, 100.0)])
	_log("[mapwarm] map interactive (buttons up)   = %.1f ms" % _rel(t_interactive, t0))
	_log("[mapwarm] FIRST deck bake lands          = %.1f ms" % _rel(t_first_bake, t0))
	_log("[mapwarm] hand bakes complete (%d/%d)    = %.1f ms" % [
		uniq, uniq, _rel(t_hand_done, t0)])
	_log("[mapwarm] WHOLE deck warm complete       = %.1f ms" % _rel(t_all_done, t0))
	_log("[mapwarm] --- if the player commits at T, this much of the deck is baked ---")
	_log("[mapwarm]    T(ms)   hand   bfield   hand%%")
	for p in PROBE_POINTS:
		var row := _curve_at(curve, p)
		if row.is_empty():
			continue
		_log("[mapwarm]   %6d   %4d   %4d   %5.0f%%" % [
			p, row[1], row[2], 100.0 * float(row[1]) / maxf(1.0, float(uniq))])

	# --- encounter-art side -------------------------------------------------
	var enc_id := ""
	for id in EDB.ENCOUNTERS.keys():
		var d: Dictionary = EDB.ENCOUNTERS[id]
		if int(d.get("act", 1)) == 1 and String(d.get("type", "combat")) == "combat":
			enc_id = String(id)
			break
	if enc_id != "":
		if CAA != null:
			CAA.clear_runtime_caches()
		SP.invalidate_encounter_art_warm_state()
		var te := Time.get_ticks_usec()
		SP.begin_warm_encounter_art(enc_id)
		var frames := 0
		while frames < 900:
			await process_frame
			frames += 1
			if not (SP._encounter_art_busy.has(enc_id) \
					or String(SP.get("_encounter_art_active")) == enc_id \
					or String(SP.get("_encounter_art_queued")) == enc_id):
				break
		_log("[mapwarm] encounter art warm (%s, COLD art cache) = %.1f ms  (the commit waits at most 150 ms for this)" % [
			enc_id, _ms(Time.get_ticks_usec() - te)])

	if is_instance_valid(mapv):
		mapv.queue_free()
	_log("[mapwarm] DONE")
	_finish()


func _map_interactive() -> bool:
	# MapView lays invisible hover/click Buttons over the painted site chips;
	# their existence is the honest "the player can commit now" signal.
	if not is_instance_valid(mapv):
		return false
	return _count_buttons(mapv) > 0


func _count_buttons(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		if c is Button:
			total += 1
		total += _count_buttons(c)
	return total


func _curve_at(curve: Array, ms: int) -> Array:
	var best: Array = []
	for row in curve:
		if float(row[0]) <= float(ms):
			best = row
		else:
			break
	return best


func _pad_deck(want: int) -> void:
	var CDB := root.get_node_or_null("CardDB")
	if CDB == null:
		return
	for id_v in CDB.CARD_POOL.keys():
		if RS.deck.size() >= want:
			break
		var id := String(id_v)
		if RS.deck.has(id):
			continue
		var rar := String(CDB.CARD_POOL[id].get("rarity", ""))
		if rar == "enemy" or rar == "":
			continue
		RS.add_card(id)


func _unique_deck_keys() -> int:
	var seen := {}
	for i in range(RS.deck.size()):
		var cd: Dictionary = RS.get_upgraded_card_data(i)
		if cd.is_empty():
			continue
		seen[CTC.cache_key(cd)] = true
	return seen.size()


func _max(a: Array[float]) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


func _over(a: Array[float], thresh: float) -> int:
	var n := 0
	for v in a:
		if v > thresh:
			n += 1
	return n


func _ms(usec: int) -> float:
	return snappedf(float(usec) / 1000.0, 0.1)


func _rel(t: int, t0: int) -> float:
	return _ms(t - t0) if t > 0 else -1.0


func _finish() -> void:
	var f := FileAccess.open("user://_probe_mapwarm.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	_done = true
	quit()
