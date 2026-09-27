extends Node
## Headless gate for THE LANDING — what the very first fight of a run is.
##
##   Godot.exe --headless --path . res://tools/_probe_firstfight.tscn
##   (optional: `-- --seeds=200` after a bare `--`)
##
## Runs as a SCENE so the autoload identifiers (RunState / EncounterDB /
## MetaState / HeroDB) resolve. It drives the REAL path a player walks:
## RunState.start_new_run -> MapTerrain.build_map (which tags terrain and
## then calls RunState.apply_terrain_redeal, the Stage-0 landing re-deal)
## and reads back whatever ends up on Act 1, FIGHT_ROWS[0].
##
## What it proves, and why each check exists:
##   A. THE FIRST-RUN ON-RAMP HOLDS. On a fresh profile (MetaState.total_runs
##      == 0) act 1 row 0 must be the hand-picked opener on EVERY seed and
##      hero. It used to be dealt by _assign_encounters and then silently
##      overwritten by apply_terrain_redeal's Stage 0, which knows nothing
##      about the guard — a brand-new player on an everflame act 1 opened on
##      powderkeg_run's two Doom bombs.
##   B. THE LANDING IS ALWAYS A LANDING KIT. On a veteran profile every row-0
##      hold must come from EncounterDB.LANDING_POOL — the curated easy pool
##      (StS's model: a dedicated easy pool, not one bespoke fight). Without
##      it a lanternhall act 1 borrowed act 2's signal_glass, whose
##      glass_refract passive does NOT act-scale.
##   C. THE LANDING IS VARIED. Across seeds the opener must not collapse to a
##      single id — a fixed first fight is the thing the easy pool replaces.
##   D. THE LEFT LANE IS NOT THE ANSWER. Stage 0 used to assign lightest-first
##      strictly by column, so the leftmost row-0 node was the easiest fight
##      in every act of every run — a learnable non-choice. The landing band
##      is now shuffled on the act's own seeded stream first; this checks the
##      lightest kit does not always land in the lowest column.
##   E. DETERMINISM. The same seed + hero must deal the same landing twice.
##      The Daily March promises one road for everyone.

const FIGHT_ROW_0: int = 0
const DEFAULT_SEEDS: int = 200

var _ran := false
var _fails := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if _ran:
		return
	_ran = true
	var n_seeds := DEFAULT_SEEDS
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--seeds="):
			n_seeds = maxi(1, int(String(arg).split("=")[1]))
	var heroes: Array = []
	for hid in HeroDB.HERO_ORDER:
		heroes.append(String(hid))

	var saved_total_runs: int = MetaState.total_runs

	print("[firstfight] %d seeds x %d heroes = %d runs per profile"
		% [n_seeds, heroes.size(), n_seeds * heroes.size()])

	# ---- Fresh profile (the on-ramp) -------------------------------------
	MetaState.total_runs = 0
	var fresh := _sweep(heroes, n_seeds)
	_report("FRESH PROFILE (total_runs == 0)", fresh)

	# ---- Veteran profile (the ordinary deal) -----------------------------
	MetaState.total_runs = 12
	var vet := _sweep(heroes, n_seeds)
	_report("VETERAN PROFILE (total_runs == 12)", vet)

	MetaState.total_runs = saved_total_runs

	_check_a(fresh)
	_check_b(vet)
	_check_c(vet)
	_check_d(vet)
	_check_e(heroes)

	print("[firstfight-probe] %s" % ("ALL PASS" if _fails == 0
		else "%d FAILURES" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


## One full sweep. Returns a bag of tallies plus the raw per-run rows so the
## checks below can slice it any way they need.
func _sweep(heroes: Array, n_seeds: int) -> Dictionary:
	var rows: Array = []
	for hero in heroes:
		for s in range(n_seeds):
			var seed_v: int = 1000 + s * 37
			rows.append_array(_landing_for(String(hero), seed_v))
	var by_enc: Dictionary = {}
	var by_faction: Dictionary = {}
	var by_hero: Dictionary = {}
	var lightest_col: Dictionary = {}
	for r in rows:
		var eid := String(r.encounter_id)
		by_enc[eid] = int(by_enc.get(eid, 0)) + 1
		var fk := String(r.faction)
		if not by_faction.has(fk):
			by_faction[fk] = {}
		by_faction[fk][eid] = int((by_faction[fk] as Dictionary).get(eid, 0)) + 1
		var hk := String(r.hero)
		if not by_hero.has(hk):
			by_hero[hk] = {}
		by_hero[hk][eid] = int((by_hero[hk] as Dictionary).get(eid, 0)) + 1
		if int(r.band_rank) == 0 and int(r.band_size) > 1 \
				and bool(r.band_has_distinct_weights):
			var k := "sorted" if bool(r.band_sorted_light_to_heavy) else "not_sorted"
			lightest_col[k] = int(lightest_col.get(k, 0)) + 1
	return {
		"rows": rows, "by_enc": by_enc, "by_faction": by_faction,
		"by_hero": by_hero, "lightest_col": lightest_col,
	}


## Start one run, drive the REAL terrain pass, and read back every act-1
## row-0 hold. Returns one record per row-0 node (a band can be 1-3 wide).
func _landing_for(hero: String, seed_v: int) -> Array:
	RunState.start_new_run(hero, 0, seed_v)
	# NOT added to the tree: _ready would schedule a second build_map.
	var map: Control = (load("res://scripts/scenes/MapTerrain.gd") as GDScript).new()
	map.set("bake_mode", "probe")   # build only, never start the bake chain
	map.size = Vector2(1600, 900)
	map.call("build_map")
	var faction: String = String(RunState.act_faction[0]) \
		if RunState.act_faction.size() > 0 else ""
	var band: Array = []
	for row in RunState.get_current_act_map():
		for nd in row:
			if int(nd.get("row", -1)) == FIGHT_ROW_0 \
					and String(nd.get("type", "")) == "combat" \
					and String(nd.get("encounter_id", "")) != "":
				band.append(nd)
	band.sort_custom(func(a, b): return int(a.col) < int(b.col))
	var out: Array = []
	# The old Stage 0 laid the band down lightest-first strictly by column, so
	# the weights read non-decreasing left->right in EVERY act of EVERY run.
	# Weight TIES are common (a thin pool cycles duplicates), so only bands
	# carrying two distinct weights say anything — those are the ones scored.
	var weights: Array = []
	for nd in band:
		weights.append(EncounterDB.kit_weight(String(nd.encounter_id)))
	var sorted_lh := true
	for i in range(1, weights.size()):
		if int(weights[i]) < int(weights[i - 1]):
			sorted_lh = false
	var distinct := {}
	for w in weights:
		distinct[w] = true
	for i in range(band.size()):
		var nd: Dictionary = band[i]
		var eid := String(nd.encounter_id)
		out.append({
			"hero": hero, "seed": seed_v, "faction": faction,
			"encounter_id": eid, "col": int(nd.col),
			"band_rank": i, "band_size": band.size(),
			"weight": int(weights[i]),
			"band_sorted_light_to_heavy": sorted_lh,
			"band_has_distinct_weights": distinct.size() > 1,
			"act": int(EncounterDB.get_encounter(eid).get("act", 0)),
		})
	map.free()
	RunState.map_plate_cache.clear()
	return out


func _report(title: String, bag: Dictionary) -> void:
	print("\n[firstfight] ===== %s =====" % title)
	var rows: Array = bag.rows
	print("[firstfight] %d row-0 holds observed" % rows.size())
	print("[firstfight] by encounter:")
	for pair in _sorted_pairs(bag.by_enc):
		var eid := String(pair[0])
		var enc: Dictionary = EncounterDB.get_encounter(eid)
		print("    %-22s %5d (%5.1f%%)  act%d w=%d passive=%s" % [
			eid, pair[1], 100.0 * float(pair[1]) / float(maxi(1, rows.size())),
			int(enc.get("act", 0)), EncounterDB.kit_weight(eid),
			String(enc.get("passive_id", "")) if String(enc.get("passive_id", "")) != "" else "-"])
	print("[firstfight] by act-1 rival faction:")
	for fk in bag.by_faction:
		var line := ""
		for pair in _sorted_pairs(bag.by_faction[fk]):
			line += "%s=%d " % [pair[0], pair[1]]
		print("    %-12s %s" % [fk, line])
	print("[firstfight] by hero:")
	for hk in bag.by_hero:
		var line2 := ""
		for pair in _sorted_pairs(bag.by_hero[hk]):
			line2 += "%s=%d " % [pair[0], pair[1]]
		print("    %-12s %s" % [hk, line2])
	print("[firstfight] multi-weight bands, weights read light->heavy by column: %s"
		% str(bag.lightest_col))


func _sorted_pairs(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([String(k), int(d[k])])
	out.sort_custom(func(a, b):
		return a[1] > b[1] if a[1] != b[1] else String(a[0]) < String(b[0]))
	return out


# ── A. the on-ramp holds on a fresh profile ───────────────────────────────
func _check_a(bag: Dictionary) -> void:
	var want := String(CampaignMapGenerator.FIRST_RUN_OPENER_ENCOUNTER)
	var bad := 0
	for r in bag.rows:
		if String(r.encounter_id) != want:
			bad += 1
	if bad > 0:
		print("  FAIL  A: %d/%d fresh-profile row-0 holds are not '%s'"
			% [bad, (bag.rows as Array).size(), want])
		_fails += 1
	else:
		print("  pass  A: fresh profile always opens on '%s' (%d holds)"
			% [want, (bag.rows as Array).size()])


# ── B. every landing is a curated landing kit ─────────────────────────────
func _check_b(bag: Dictionary) -> void:
	var bad: Dictionary = {}
	for r in bag.rows:
		if not EncounterDB.is_landing_kit(String(r.encounter_id)):
			bad[String(r.encounter_id)] = int(bad.get(String(r.encounter_id), 0)) + 1
	if not bad.is_empty():
		print("  FAIL  B: row-0 holds outside the landing pool: %s" % str(bad))
		_fails += 1
	else:
		print("  pass  B: every row-0 hold is in EncounterDB.LANDING_POOL")
	# Structural: the pool itself must be act-1 only and passive-free, or a
	# borrowed/unsclaed passive can ride in the way glass_refract did.
	for eid in EncounterDB.LANDING_POOL:
		var enc: Dictionary = EncounterDB.get_encounter(String(eid))
		if enc.is_empty():
			print("  FAIL  B: LANDING_POOL names unknown encounter '%s'" % eid)
			_fails += 1
			continue
		if int(enc.get("act", 0)) != 1 or String(enc.get("type", "")) != "combat":
			print("  FAIL  B: landing kit '%s' is not an act-1 combat" % eid)
			_fails += 1
		if String(enc.get("passive_id", "")) != "":
			print("  FAIL  B: landing kit '%s' carries passive '%s'"
				% [eid, enc.get("passive_id", "")])
			_fails += 1


# ── C. the landing is varied ──────────────────────────────────────────────
func _check_c(bag: Dictionary) -> void:
	var n: int = (bag.by_enc as Dictionary).size()
	if n < 3:
		print("  FAIL  C: only %d distinct openers over the whole sweep" % n)
		_fails += 1
	else:
		print("  pass  C: %d distinct openers across the sweep" % n)


# ── D. the left lane is not the answer ────────────────────────────────────
func _check_d(bag: Dictionary) -> void:
	var lc: Dictionary = bag.lightest_col
	var sorted_n: int = int(lc.get("sorted", 0))
	var total: int = sorted_n + int(lc.get("not_sorted", 0))
	if total < 10:
		print("  skip  D: only %d scoreable row-0 bands (need 10)" % total)
		return
	var frac := float(sorted_n) / float(total)
	if frac > 0.90:
		print("  FAIL  D: row-0 band reads light->heavy left-to-right in "
			+ "%.1f%% of bands (%d/%d) — the left lane is a learnable non-choice"
			% [frac * 100.0, sorted_n, total])
		_fails += 1
	else:
		print("  pass  D: row-0 band reads light->heavy left-to-right in "
			+ "%.1f%% of bands (%d/%d)" % [frac * 100.0, sorted_n, total])


# ── E. determinism ────────────────────────────────────────────────────────
func _check_e(heroes: Array) -> void:
	var bad := 0
	for hero in heroes:
		for seed_v in [4242, 77, 900001]:
			var a := _ids(_landing_for(String(hero), seed_v))
			var b := _ids(_landing_for(String(hero), seed_v))
			if a != b:
				print("  FAIL  E: %s seed %d dealt %s then %s"
					% [hero, seed_v, str(a), str(b)])
				bad += 1
	if bad == 0:
		print("  pass  E: landing is a pure function of (hero, seed)")
	else:
		_fails += 1


func _ids(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append("%d:%s" % [int(r.col), String(r.encounter_id)])
	return out
