extends SceneTree
## _probe_settings_differential.gd — CLASS C27: CONFIGURATION-DIFFERENTIAL TESTING.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_settings_differential.gd
##
## Every gate in docs/BUG_SWEEP_METHOD_20260829.md tests the game under ONE
## configuration — the default one. But the player can change the configuration,
## and a setting that silently removes CONTENT is a defect the player meets
## immediately and cannot diagnose: they turned on an accessibility option and a
## panel stopped existing.
##
## This is the variability-aware / configuration-differential class from the
## software-product-line testing literature, and its oracle is RELATIONAL like
## C10's — no knowledge of what a screen *should* say is needed, only that two
## configurations must AGREE about it. Settings in this game are declared to be
## presentation-only:
##
##   * `reduce_motion` gates DECORATIVE animation off. The contract in CLAUDE.md is
##     explicit — the kit verbs "gate themselves, incl. snapping to end-state where
##     content must still land". So the end state must be IDENTICAL.
##   * `anim_speed` scales durations. A duration cannot change what is on screen.
##   * `screen_shake` moves the canvas and restores it.
##
## None of them may change WHAT IS LEGIBLE once a screen has settled. So: build
## each screen twice, let both settle by the same wall-clock, and diff the set of
## worded controls the player can actually read.
##
## THE ORACLE IS THE TEXT MULTISET PLUS ITS EFFECTIVE LEGIBILITY, and legibility is
## the half that matters. A node left at `modulate.a = 0` by an entrance that never
## ran is still in the tree, still "visible_in_tree", and still reports its text —
## it is simply invisible. Counting nodes would call that a pass.
##
## AND THE ORACLE CHECKS ITSELF. A differential gate assumes that building the
## same screen twice gives the same screen, and once-per-profile content (the
## coaching panel) breaks that assumption silently — see `_run_state`, where a
## confirming fourth pass now separates "the setting changed this" from "the pass
## order changed this" on any state that reports a divergence.
##
## `visible_ratio` IS PART OF LEGIBILITY, and leaving it out was this probe's own
## first bug. The typewriter (`Motion.write_on`) reveals prose by tweening
## `visible_ratio` 0 → 1 and returns early under Reduce Motion; the whole bug class
## being hunted here is a reveal that returns early WITHOUT restoring its
## pre-state. A label at `visible_ratio = 0` draws not one glyph and still reports
## its full `text` at full alpha — so the first version of this oracle was blind to
## the exact defect it was built for.

const SETTLE_SEC := 1.6      # wall-clock, not frames: tweens and timers are real
## Poll for a STABLE fingerprint after that floor, rather than trusting a clock.
const STABLE_STEP := 0.15
const STABLE_MAX_SEC := 12.0
const HIDDEN := 0.35         # effective alpha below this = the player sees nothing
const SHOWN := 0.90
const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

var RS: Node
var US: Node
var CDB: Node
var EDB: Node
var _started := false
var _done := false
var _hits := 0
var _leaks := 0
var _states := 0
var _unsettled := 0
var _profile := ""
var _only: PackedStringArray = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


# ── The fingerprint ──────────────────────────────────────────────────────────

func _text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


## Alpha as the PLAYER receives it: every ancestor's `modulate` multiplies down the
## tree, `self_modulate` applies only to the node itself, and a CanvasLayer in the
## chain contributes nothing but must not stop the walk.
func _effective_alpha(c: Control) -> float:
	var a: float = c.self_modulate.a
	var walk: Node = c
	while walk != null:
		if walk is CanvasItem:
			a *= (walk as CanvasItem).modulate.a
		walk = walk.get_parent()
	return a


## How much of this node's text is actually drawn. A typewriter parks its label at
## `visible_ratio = 0` and reveals it over time; a Label does the same through
## `visible_characters`. Both report their FULL `text` the whole way.
func _revealed(c: Control) -> float:
	if c is RichTextLabel:
		return clampf((c as RichTextLabel).visible_ratio, 0.0, 1.0)
	if c is Label:
		var l: Label = c
		if l.visible_characters < 0:
			return 1.0
		var total := l.text.length()
		return 1.0 if total <= 0 else clampf(float(l.visible_characters) / float(total), 0.0, 1.0)
	return 1.0


func _norm(s: String) -> String:
	var t := s.strip_edges()
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	return t.replace("\n", " ").replace("\t", " ")


## text -> { "n": count, "alpha": the BEST alpha any instance of that string got }
## Best, not worst: a screen legitimately holds a hidden duplicate (a measuring
## ghost, a pre-built next page). What is a defect is a string the player could
## read in one configuration and can read in NO instance in the other.
func _fingerprint(node: Node) -> Dictionary:
	var out := {}
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if not (n is Control):
			continue
		var c: Control = n
		if not c.is_visible_in_tree():
			continue
		var txt := _norm(_text_of(c))
		if txt == "" or txt.length() < 2:
			continue
		var a: float = _effective_alpha(c) * _revealed(c)
		var r := c.get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		if out.has(txt):
			out[txt]["n"] += 1
			out[txt]["alpha"] = maxf(out[txt]["alpha"], a)
		else:
			out[txt] = {"n": 1, "alpha": a}
	return out


## The findings between two fingerprints, as printable lines. It RETURNS them
## rather than printing, because `_run_state` has to decide whether they are
## about the configuration or about this probe before it can label them.
func _findings(base: Dictionary, other: Dictionary) -> Array:
	var out: Array = []
	for k in base:
		var b: Dictionary = base[k]
		if float(b["alpha"]) < SHOWN:
			continue                      # not legible in the baseline either
		if not other.has(k):
			out.append("CONTENT LOST: \"%s\"" % k.substr(0, 60))
		elif float(other[k]["alpha"]) < HIDDEN:
			out.append("INVISIBLE: \"%s\"  (alpha %.2f)"
				% [k.substr(0, 60), float(other[k]["alpha"])])
	for k in other:
		if float(other[k]["alpha"]) >= SHOWN and not base.has(k):
			out.append("ONLY HERE: \"%s\"" % k.substr(0, 60))
	return out


# ── Driving one screen state under one profile ───────────────────────────────

## `-- --only=map,shop` runs just the states whose label starts with one of those
## prefixes. A full run is ~66 states x 3 builds and minutes long, which is the
## right shape for the gate and the wrong shape for iterating on one screen — or
## for mutation-testing this file's own LEAK guard, which needs the defect it
## detects put back on purpose. A filtered run reports what it ran, never ALL
## AGREE, so a narrowed run can't be mistaken for a clean one.
func _wanted(label: String) -> bool:
	if _only.is_empty():
		return true
	for pre in _only:
		if label.begins_with(pre):
			return true
	return false

## THE COACH IS ONCE-PER-PROFILE, AND THAT IS A STATE LEAK ACROSS PASSES
## (2026-09-15). A lesson fires the first time its subject is on screen and
## `mark_lesson_seen` then spends it FOR THE WHOLE PROCESS — so the `base` pass
## met a screen with a coaching panel on it and the two that follow met the same
## screen with no panel at all. That reported 30 divergences ("GOT IT", "CHOOSE
## THE ROAD", "BUY AND SELL" CONTENT LOST on map/shop/recruit) against a product
## where nothing had gone wrong: the variable was the pass ORDER, not the
## setting. The tell is that every one of them was reported under BOTH profiles
## — a real reduce_motion defect has no reason to also be a screen_shake defect.
##
## Un-spending the lessons before every pass is the fix rather than switching
## coaching OFF, and the distinction matters: the coach carries its own
## reduce_motion contract (hold, never remove — `_probe_coach_a11y` gates the
## layer, this gates the WORDS), so a configuration diff that never renders a
## panel would be agreeing about nothing on the one surface built to be gated.
##
## The reset belongs here, beside the settings, because this function is where a
## pass's world is made identical to its siblings'. `reset_tutorials` saves, and
## `run_ui_gates.ps1` redirects APPDATA — a bare run writes the real profile.
func _apply_profile(prof: String) -> void:
	_profile = prof
	US.reset_tutorials()
	US.anim_speed = 3.0          # both profiles run fast; speed is not the variable
	US.end_turn_warning = false
	match prof:
		"base":
			US.reduce_motion = false
			US.screen_shake = true
		"reduce_motion":
			US.reduce_motion = true
			US.screen_shake = true
		"no_shake":
			US.reduce_motion = false
			US.screen_shake = false


## Every profile must meet the SAME screen, so the run is rebuilt from the same
## seed and the global RNG is re-seeded before the scene is instantiated —
## otherwise a shop that rolled different stock reads as content loss.
func _stage(kind: String, hero_i: int) -> void:
	seed(SEED)
	RS.start_new_run(HEROES[hero_i % HEROES.size()], 0, SEED)
	RS.gold = 800 if kind == "rich" else 150
	RS.hero_hp = RS.hero_max_hp


## WALL-CLOCK, which is what SETTLE_SEC has always claimed to be.
##
## The previous version credited `t += 1.0 / 60.0` per `process_frame` — a 60fps
## assumption headless never meets — ON TOP OF the real 0.02 timer. So `t` ran up
## to ~1.8x faster than the clock and a nominal 1.6s settle could return after
## roughly 1.0s of real time, with the exact figure depending on how fast frames
## happened to run.
##
## That made this gate NON-DETERMINISTIC, and it failed in the direction that
## costs the most: a screen still mid-animation fingerprints as CONTENT LOST. The
## stranger's hand deals its three cards face-down and flips them one at a time,
## the third landing at 0.95s (Event._play_wet_deal: 0.35 + 2 x 0.22 + 0.16) —
## just inside that ~1.0s window. It reported a phantom 3-string divergence on
## roughly one run in three while the two configurations were in fact identical.
## Every other screen settles well inside 1.0s, which is why only this one showed
## it. Same shape as `_probe_input_reach._settle`, which had it right.
func _settle() -> void:
	var t := 0.0
	while t < SETTLE_SEC:
		await process_frame
		await create_timer(0.02).timeout
		t += 0.02


## ── AND THEN SETTLE UNTIL THE SCREEN STOPS CHANGING (2026-09-03) ────────────
##
## Raising SETTLE_SEC fixed the Event deal and left the same bug in place for
## COMBAT, whose opening is deliberately interleaved across several seconds
## (`Combat._ready` hands the frame back between build stages, then deals a hand
## one card at a time). 1.6s fingerprints it mid-build, so `combat:bandit_camp`
## reported a phantom divergence — "Trail Scout" present in one profile and not
## another — on roughly one run in three. It failed a full gate suite that way,
## and re-running with identical code gave ALL AGREE.
##
## A bigger constant would only move the boundary. This polls instead: sample the
## fingerprint, and accept it once two consecutive samples AGREE. That is
## deterministic whatever a screen's build takes, and it is the same lesson
## CLAUDE.md records for `_layout_hand` — poll until the count HOLDS.
func _settle_stable(node: Node) -> Dictionary:
	var t := 0.0
	var prev := ""
	var fp := {}
	var agreed := 0
	while t < STABLE_MAX_SEC:
		await process_frame
		await create_timer(STABLE_STEP).timeout
		t += STABLE_STEP
		if t < SETTLE_SEC:
			continue                      # never sample before the old floor
		if not is_instance_valid(node):
			return fp
		fp = _fingerprint(node)
		var key := "|".join(PackedStringArray(fp.keys()))
		if key == prev:
			agreed += 1
			if agreed >= 2:
				return fp
		else:
			agreed = 0
		prev = key
	_unsettled += 1
	return fp


## Build one screen under one profile and fingerprint it.
func _pass(label: String, prof: String, builder: Callable) -> Variant:
	_apply_profile(prof)
	var node = await builder.call()
	if node == null:
		print("  skip  %s (%s): builder returned null" % [label, prof])
		return null
	var fp = await _settle_stable(node)
	node.queue_free()
	await process_frame
	return fp


## THE CONFIRMING FOURTH PASS, and why a differential oracle needs one.
##
## This gate's whole claim is that a difference between pass 1 and pass 2 was
## caused by the SETTING, and that claim rests on an assumption it never checked:
## that building the same screen twice gives the same screen. Once-per-profile
## content breaks that assumption — the coaching panel fires on first sight of
## its subject and is spent for the rest of the process, so `base` met a panel
## and the two profiles after it met a screen where that panel no longer exists.
## Thirty divergences, every one of them reported under BOTH profiles, and every
## one of them the pass ORDER rather than the setting.
##
## So on a hit — and only on a hit, because this costs a whole extra build of the
## screen — `base` is run AGAIN, last instead of first. If the two `base` passes
## disagree, the screen is order-dependent and this gate cannot measure it: say
## THAT, in those words, instead of accusing reduce_motion of losing content.
## Both outcomes fail the run; they just fail it with the right diagnosis, which
## is the entire difference between a ten-minute fix and an afternoon.
func _run_state(label: String, builder: Callable) -> void:
	if not _wanted(label):
		return
	_states += 1
	var prints := {}
	for prof in ["base", "reduce_motion", "no_shake"]:
		var fp = await _pass(label, prof, builder)
		if fp == null:
			return
		prints[prof] = fp

	var found := {
		"reduce_motion": _findings(prints["base"], prints["reduce_motion"]),
		"no_shake": _findings(prints["base"], prints["no_shake"]),
	}
	if found["reduce_motion"].is_empty() and found["no_shake"].is_empty():
		print("  ok    %-34s agrees" % label)
		return

	var again = await _pass(label, "base", builder)
	if again != null:
		var drift := _findings(prints["base"], again)
		if not drift.is_empty():
			_leaks += 1
			print("  LEAK  %-34s base != base: this screen is ORDER-DEPENDENT, so the"
				% label)
			print("        %-34s configuration diff below cannot be trusted." % "")
			for d in drift:
				print("        %-34s %s" % ["", d])
			return

	for prof in ["reduce_motion", "no_shake"]:
		for f in found[prof]:
			_hits += 1
			print("  HIT   %-34s %-13s | %s" % [label, prof, f])


func _simple(path: String, kind: String, hero_i: int) -> Callable:
	return func():
		_stage(kind, hero_i)
		var n = load(path).instantiate()
		root.add_child(n)
		return n


## HOW TO ACTUALLY SEAT AN EVENT, because the obvious way does not work.
##
## `Event._ready` calls `_pick_event()`, which ROLLS. Setting `_event_id` after
## `add_child` and calling `_show_event()` / `_build_event()` — the recipe in
## `_probe_textfit._audit_event` — seats nothing at all: neither method exists on
## Event.gd, so the `has_method` chain falls through silently and the screen keeps
## whatever the roll produced. Verified by asking for 14 distinct events and
## getting 9 distinct screens, none of them the one requested.
##
## The working recipe is `_probe_boundary_ui`'s: tear the rolled screen down with
## `_clear_ui()`, seat the fields, and rebuild with `_build_ui()`.
func _event(ev_id: String) -> Callable:
	return func():
		_stage("rich", 1)
		var EvScript = load("res://scripts/scenes/Event.gd")
		var ev = load("res://scenes/event.tscn").instantiate()
		root.add_child(ev)
		await process_frame
		ev._clear_ui()
		ev._event_id = ev_id
		ev._event_data = EvScript.EVENTS[ev_id].duplicate(true)
		ev._current_node = ev._event_data
		ev._build_ui()
		return ev


func _combat(enc_id: String) -> Callable:
	return func():
		_stage("default", 0)
		RS.current_encounter_id = enc_id
		RS.current_node_type = String(EDB.ENCOUNTERS[enc_id].get("type", "combat"))
		var n = load("res://scenes/combat.tscn").instantiate()
		root.add_child(n)
		return n


func _wayside(verb: String) -> Callable:
	return func():
		_stage("rich", 2)
		RS.current_wayside_id = verb
		var n = load("res://scenes/wayside.tscn").instantiate()
		root.add_child(n)
		return n


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	CDB = root.get_node_or_null("CardDB")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or US == null or EDB == null:
		print("[cfgdiff] FATAL: autoloads missing"); _done = true; quit(1); return

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",", false)

	print("[cfgdiff] CLASS C27 — the same screen under three configurations")
	if not _only.is_empty():
		print("[cfgdiff] FILTERED to: %s" % ", ".join(_only))
	print("")

	await _run_state("main_menu", _simple("res://scenes/main_menu.tscn", "default", 0))
	await _run_state("collection", _simple("res://scenes/collection.tscn", "default", 0))
	await _run_state("credits", _simple("res://scenes/credits.tscn", "default", 0))
	await _run_state("net_lobby", _simple("res://scenes/net_lobby.tscn", "default", 0))
	await _run_state("map", _simple("res://scenes/map.tscn", "default", 1))
	await _run_state("reward", _simple("res://scenes/reward.tscn", "rich", 1))
	await _run_state("shop", _simple("res://scenes/shop.tscn", "rich", 2))
	await _run_state("rest", _simple("res://scenes/rest.tscn", "default", 3))
	await _run_state("treasure", _simple("res://scenes/treasure.tscn", "rich", 3))
	await _run_state("recruit", _simple("res://scenes/recruit.tscn", "default", 4))
	await _run_state("game_over", _simple("res://scenes/game_over.tscn", "default", 4))
	for verb in ["drill_yard", "standard_bearer", "supply_cache"]:
		await _run_state("wayside:%s" % verb, _wayside(verb))
	# Events are the largest worded surface in the game (46 rooms) and hold 41 of
	# the 160 hand-written reduce_motion branches — the densest concentration
	# anywhere. Every one of them gets driven.
	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev_ids: Array = EvScript.EVENTS.keys()
	ev_ids.sort()
	for ev_id in ev_ids:
		await _run_state("event:%s" % ev_id, _event(String(ev_id)))
	for enc in ["goblin_scouts", "bandit_camp", "rival_stalwart"]:
		if EDB.ENCOUNTERS.has(enc):
			await _run_state("combat:%s" % enc, _combat(enc))

	print("\n[cfgdiff] %d screen state(s) x 3 configurations" % _states)
	# A state that never stopped changing was fingerprinted on a guess, which is
	# how this gate used to flake. Say so rather than letting it pass silently.
	if _unsettled > 0:
		print("[cfgdiff] %d state(s) never reached a stable fingerprint within %.0fs"
			% [_unsettled, STABLE_MAX_SEC])
	# An order-dependent screen is NOT a configuration divergence and must never
	# be counted as one — it is this gate reporting that it could not measure.
	if _leaks > 0:
		print("[cfgdiff] %d screen(s) ORDER-DEPENDENT — once-per-profile content is "
			% _leaks + "leaking across passes; fix the probe, not the product")
	# A filtered run must never print the runner's sentinel: it did not look at
	# most of the game, and "ALL AGREE" would say that it had.
	if _hits > 0 or _leaks > 0:
		print("[cfgdiff] %d DIVERGENCE(S), %d LEAK(S)" % [_hits, _leaks])
	elif _only.is_empty():
		print("[cfgdiff] ALL AGREE")
	else:
		print("[cfgdiff] filtered run clean — NOT a full pass, %d state(s) only" % _states)
	_done = true
	quit(1 if (_hits > 0 or _leaks > 0) else 0)
