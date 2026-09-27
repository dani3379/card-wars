extends Node
## _probe_tutorial_live.gd — do the combat lessons actually REACH a board?
## (2026-09-10)
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_tutorial_live.tscn
##
## `_probe_tutorial` is STATIC: it proves every lesson id is quoted at a call
## site. That is necessary and it is not sufficient, and the difference is the
## whole lesson of the C20 content census — content can be perfectly wired and
## still never appear, because some gate in front of it never opens.
##
## Every lesson added by the coverage pass is gated on its SUBJECT BEING ON
## SCREEN, which is the right design and also six new ways to never fire:
##   · `relics` wants a visible chip in `_relic_chip_by_id`
##   · `potions` wants `_potion_bar_root` visible AND a potion in the belt
##   · `keywords` wants a hand card carrying a keyword
##   · `spells` wants a spell in hand
##   · `overkill` / `hero_hp` want a latch armed from inside the clash
## A typo in any of those member names, or a HUD rebuild that leaves one hidden,
## produces a lesson that is fully wired, passes the static gate, and no player
## ever sees. Nothing else here would notice.
##
## So this boots the REAL combat scene on a real encounter and asks each lesson
## to fire, one at a time, against the real board.
##
## THE HAND IS STACKED ON PURPOSE for the two card-shaped lessons. `keywords` and
## `spells` depend on what the opening five happened to be, and a probe whose
## answer depends on a shuffle is a probe that goes red for the wrong reason on
## some future seed. The gate being tested is "does the scan find it and does the
## tip land", not "did the deck deal one".
##
## THREE PHASES, and the later two boot whole scenes rather than poking Combat:
##   1. `_ready` — the seven combat lessons, offered one at a time on a real board
##   2. `_probe_road_screens` — Rest and Event, whose lessons find their targets
##      by NAME and go silently unreachable on a rename
##   3. `_probe_stop_screens` — Recruit, Shop and MapView (both of its lessons),
##      whose targets are live arrays the screen has to have filled first
##
## PHASES 2 AND 3 SHARE ONE ORACLE (`_teach_on_screen`), and that is a fix rather
## than a tidy-up. Phase 2 used to accept `lesson_seen` as its whole answer, which
## is the precise thing phase 3's header argues is not an answer: `teach()` stamps
## a lesson seen even when every target it was handed resolved to nothing. Rest is
## the screen where that matters most and had the least cover — `Event` refuses to
## teach on an empty target list, but `_maybe_coach_the_camp` does NOT, so a stale
## "CampChoices" lookup there produces a panel over an unlit screen that spends the
## lesson forever and passed the old check green. Every screen now has to say what
## it lit, and each oracle is written to survive the failure it hunts (the camp's
## banners are found by SHAPE, never by the name the lesson looks them up under).

## ── THE MUTATION HARNESS (C12: test the tests) ─────────────────────────
##
## Every check in phases 2 and 3 is a claim about a screen the probe cannot see,
## and a green oracle is worth nothing until it has been made to go red on the
## defect it was written for. Set `_MUTANT` to one lesson id, run, and that one
## screen is sabotaged in the exact way the case exists to catch.
##
## SCORE ON THE PASS THAT ADDED THEM: 5 of 5, each naming the right thing —
##   camp_choice  rename "CampChoices" → "camp_choice: the coach opened NO
##                spotlight" (and the lesson was STILL stamped seen, which is the
##                whole finding: see the Rest note in `_probe_road_screens`)
##   recruit_card empty `_card_nodes`  → subject guard + no spotlight
##   shop_trade   hide `_gold_label`   → subject guard + no spotlight
##   map_road     disable every chip   → subject guard + no spotlight
##   map_gate     zero the Hold tally  → subject guard + lesson never fired +
##                no coach, i.e. the case really is on the KEEP branch
##
## TWO MUTANTS ESCAPED ON THEIR FIRST RUN and the reason is the standing trap on
## this file: Recruit and MapView both build ASYNCHRONOUSLY, so a mutation applied
## at `add_child` time is simply overwritten by the build that follows it — the
## harness had proved nothing while reporting a clean pass. It is therefore
## re-applied on EVERY POLL FRAME, so whatever the screen holds when `teach` is
## finally reached is the sabotaged state. A mutant that does not mutate is the
## same false green as a probe that does not probe.
const _MUTANT := ""


func _apply_mutant(id: String, screen) -> void:
	match id:
		"camp_choice":
			var row = screen.get_node_or_null("CampChoices")
			if row != null:
				row.name = "CampChoicesRENAMED"
		"recruit_card":
			screen.set("_card_nodes", [])
		"shop_trade":
			var purse = screen.get("_gold_label")
			if purse != null:
				(purse as Control).visible = false
		"map_road":
			for b in screen.get("_site_buttons"):
				if b != null and is_instance_valid(b):
					b.disabled = true
		"map_gate":
			RunState.holds_broken_in_act = 0


var _combat: Node = null
var _failures: Array[String] = []
var _checks := 0
var _saved := {}
var _headless := DisplayServer.get_name() == "headless"


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(msg)


func _ready() -> void:
	for k in ["muster_tutorial_seen", "intents_tutorial_seen", "pile_tutorial_seen",
			"banking_tutorial_seen", "combat_model_tutorial_seen",
			"dismiss_tutorial_seen", "first_battle_tutorial_complete"]:
		_saved[k] = UserSettings.get(k)
	_saved["lessons_seen"] = UserSettings.lessons_seen.duplicate(true)
	_saved["coaching_mode"] = UserSettings.coaching_mode

	UserSettings.reset_tutorials()
	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)

	RunState.start_new_run("raider", 0, 90210)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	await _wait_for_hand()

	# The guided walkthrough owns the teaching surface while it runs, and every
	# `_maybe_show_*` correctly refuses under it. Retire it first — this probe is
	# about the tips that come AFTER the walkthrough, which is the state a real
	# player is in for every fight but their first.
	UserSettings.mark_first_battle_tutorial_complete()
	_combat.set("_first_battle_tutorial_stage", 0)

	_check(_combat.get("_info_label") != null,
		"no _info_label — the tip channel does not exist, every tip would refuse")

	_probe_lesson("relics", "_maybe_show_relic_tutorial")
	_probe_lesson("keywords", "_maybe_show_keyword_tutorial", _stack_keyword_card)
	_probe_lesson("spells", "_maybe_show_spell_tutorial", _stack_spell_card)
	_probe_lesson("potions", "_maybe_show_potion_tutorial", _stock_a_potion)
	_probe_lesson("overkill", "_maybe_show_overkill_tutorial",
		func(): _combat.set("_overkill_lesson_armed", true))
	_probe_lesson("hero_hp", "_maybe_show_hero_hp_tutorial",
		func(): _combat.set("_hero_hit_lesson_armed", true))
	# LAST, because it is the only setup that changes the BOARD. It summons a
	# real body into the back row through the real primitive rather than poking
	# `_player_back` — the lesson's gate reads live occupancy, and a hand-stuffed
	# array would prove the probe can write to an array, not that the gate opens.
	_probe_lesson("back_row", "_maybe_show_back_row_tutorial", _summon_a_back_body)
	_check(_combat.get("_player_back")[0] != null,
		"back_row: the summon did not land, so its check proved nothing")

	# The two clash latches must be reachable from the code that arms them —
	# a latch nothing sets is a lesson nothing teaches.
	_check(_combat.has_method("_arm_overkill_lesson"),
		"_arm_overkill_lesson is missing; the clash cannot arm the lesson")
	_check(_combat.has_method("_arm_hero_hit_lesson"),
		"_arm_hero_hit_lesson is missing; the clash cannot arm the lesson")

	# And OFF must still be honoured on a live board, not only in the unit-shaped
	# check — this is the setting a player actually set.
	UserSettings.reset_tutorials()
	UserSettings.set_coaching_mode(TutorialDB.COACH_OFF)
	_combat.set("_tutorial_tip_live", "")
	_combat.call("_maybe_show_relic_tutorial")
	_check(not UserSettings.lesson_seen("relics"),
		"a lesson fired on a live board with coaching OFF")

	_combat.queue_free()
	_combat = null
	await get_tree().process_frame
	await _probe_road_screens()
	await _probe_stop_screens()

	for k in _saved:
		UserSettings.set(k, _saved[k])
	UserSettings.save()

	print("[tutorial_live] %d checks" % _checks)
	# A sabotaged run must never be mistakable for a real one — it is SUPPOSED to
	# be red, and a left-behind `_MUTANT` would otherwise read as a regression.
	if _MUTANT != "":
		print("[tutorial_live] !! MUTATION HARNESS ARMED (_MUTANT = '%s') — this "
			% _MUTANT + "run is deliberately sabotaged and its verdict means "
			+ "nothing until _MUTANT is set back to \"\"")
	if _failures.is_empty():
		print("PROBE PASS: tutorial_live")
	else:
		for f in _failures:
			print("  FAIL  ", f)
		print("PROBE FAIL: tutorial_live (%d failures)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


## Offer one lesson against the live board and require it to LAND.
##
## The channel is released by hand first: a tip holds `_info_label` for 7 seconds
## and refuses everything else meanwhile (first-claim-wins), so without this the
## probe would measure the hold rather than the gate — every lesson after the
## first would report as unreachable.
func _probe_lesson(id: String, method: String, setup: Callable = Callable()) -> void:
	if setup.is_valid():
		setup.call()
	UserSettings.replay_lesson(id)
	_combat.set("_tutorial_tip_live", "")
	_check(_combat.has_method(method), "%s: %s does not exist" % [id, method])
	if not _combat.has_method(method):
		return
	_combat.call(method)
	_check(UserSettings.lesson_seen(id),
		"%s: offered on a real board and did not land — its gate never opens"
		% id)
	var lbl = _combat.get("_info_label")
	if lbl != null and is_instance_valid(lbl):
		_check(String(lbl.text).contains(TutorialDB.title(id)),
			"%s: marked seen but the channel does not carry its text (got '%s')"
			% [id, String(lbl.text)])


## THE ROAD SCREENS, END TO END. Each of these boots the real scene and requires
## the lesson to have marked itself seen by the time the screen settles.
##
## THE RISK THIS EXISTS FOR IS NAME LOOKUP. Almost every control on these screens
## is a LOCAL discarded at the end of the build, so two of the lessons find their
## spotlight targets by NAME — `Rest` looks up "CampChoices", `Event` walks four
## possible choice containers because it has five presentation layouts. A rename
## anywhere in those builders makes the lookup return null.
##
## AND THE TWO SCREENS FAIL THAT DIFFERENTLY, which is why "seen" cannot be the
## oracle here either. `Event` checks its target list and returns WITHOUT teaching
## when it is empty — a silently unreachable lesson, caught by a `lesson_seen`
## check. `Rest` has no such guard: a stale name there calls `teach` with an EMPTY
## array, which lights nothing, panels anyway, and stamps the lesson spent for
## good — and `lesson_seen` answers true for it. So both run through
## `_teach_on_screen` with the same spotlight oracle the stop screens use.
func _probe_road_screens() -> void:
	# COACHING BACK ON. The phase before this one deliberately leaves it OFF (that
	# is what it was testing), and inheriting that made both screens fail
	# identically — which is the tell: a uniform failure across every case is
	# almost always the oracle, not the code. Same lesson as the chaos-save pass,
	# where three separate harness bugs each produced "14 of 14 unusable".
	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)

	await _teach_on_screen({
		"id": "camp_choice", "scene": "res://scenes/rest.tscn", "seconds": 12.0,
		"setup": func(): RunState.current_node_type = "rest",
		"subject": _camp_subject, "spotlight": _camp_spotlight})

	await _teach_on_screen({
		"id": "event_choice", "scene": "res://scenes/event.tscn", "seconds": 15.0,
		"setup": _pin_the_crossing, "audit": _event_audit,
		"subject": _event_subject, "spotlight": _event_spotlight})


## PIN THE EVENT ROLL. `_pick_event` shuffles with the GLOBAL rng — no run seed
## reaches it — and one of the outcomes correctly teaches nothing: an event whose
## node carries an `auto_effect` builds no choices at all (it is its own picker),
## so `_maybe_coach_the_page` returns without teaching, by design. This case
## therefore went red about one run in five for a reason that was not the thing it
## tests, which is worse than not testing it.
##
## A run standing on a bridge takes `_pick_event`'s FIRST branch outright — no
## gate test, no shuffle, no RNG of any kind — and The Crossing is a three-choice
## page on the `location` dress, so the pin also moves this off the `folio`
## fallback and onto a real presented layout. That branch also APPENDS the id to
## `events_seen`, and its own condition is `not events_seen.has(...)`: the erase is
## half the pin, not tidying, and without it a second run in one process falls
## straight back into the shuffle.
func _pin_the_crossing() -> void:
	RunState.current_node_type = "event"
	RunState.current_bridge = true
	RunState.events_seen.erase("the_crossing")


## The pin, asserted rather than assumed — and kept apart from the vacuity guard
## below it, because "the roll escaped the pin" and "the page offered no choices"
## are different findings and must not share a check.
func _event_audit(screen) -> void:
	RunState.current_bridge = false
	_check(String(screen.get("_event_id")) == "the_crossing",
		"event_choice: the roll escaped the pin (dealt '%s') — this case is back to measuring whatever the shuffle handed it"
		% String(screen.get("_event_id")))


func _event_subject(screen) -> String:
	if screen.call("_visible_event_choices").is_empty():
		return "the page built no visible choices, so there was nothing to spotlight"
	return ""


## Every choice the page decided to offer must be lit. The count comes from the
## page's own DATA (`_visible_event_choices` reads the node's choice list and its
## blue gates), never from the container walk under test — an oracle that repeats
## the lookup it is checking only ever agrees with itself.
func _event_spotlight(screen, coach) -> String:
	var want: int = screen.call("_visible_event_choices").size()
	var lit := _focused_nodes(coach)
	for n in lit:
		if not (n is Control) or not screen.is_ancestor_of(n):
			return "a lit target is not a control on the event page"
	if lit.size() != want:
		return "%d control(s) lit, %d choice(s) are on offer" % [lit.size(), want]
	return ""


## The camp's banner column, found by SHAPE — the one direct child VBox holding
## PanelContainers — and deliberately NOT by the name `_maybe_coach_the_camp` uses.
##
## THIS IS THE WHOLE POINT OF THE CASE. The failure being hunted is that lookup
## going stale, and an oracle that repeated it would go blind at exactly that
## moment: it would report "the camp built no banners" (false, and reads as a
## broken probe) instead of "the coach lit nothing" (true, and names the bug).
func _camp_banners(screen) -> Array:
	for child in screen.get_children():
		if not (child is VBoxContainer):
			continue
		var banners: Array = []
		for b in (child as VBoxContainer).get_children():
			if b is PanelContainer:
				banners.append(b)
		if not banners.is_empty():
			return banners
	return []


func _camp_subject(screen) -> String:
	if _camp_banners(screen).is_empty():
		return "the camp built no choice banners"
	return ""


func _camp_spotlight(screen, coach) -> String:
	var want := _camp_banners(screen)
	var lit := _focused_nodes(coach)
	for n in lit:
		if not want.has(n):
			return "a spotlight opened over something that is not a camp banner"
	if lit.size() != want.size():
		return "%d of the %d camp banners are lit" % [lit.size(), want.size()]
	return ""


## THE THREE SCREENS NOBODY HAD EVER BOOTED — MapView, Recruit and Shop.
##
## `_probe_tutorial` proves each of these lesson ids is QUOTED at a call site.
## That is a spelling check. Every one of them is then gated on a live subject
## that the screen has to have built by the time the call is reached:
##   · MapView filters `_site_buttons` to `not disabled`, and `map_gate` hunts
##     `_nodes` for an entry of `type == "boss"`
##   · Recruit hands over `_card_nodes`
##   · Shop hands over `[_gold_label]`
## Shift a build order, rename a member, move a `teach` above the builder that
## fills its array, and the lesson is gone with every existing gate still green.
##
## AND "SEEN" IS NOT THE ORACLE. `TutorialCoach.teach` stamps the lesson seen
## even when every target it was handed resolved to nothing — the empty-list
## refusal lives in Event's own builder, not in the helper, so these three have
## no such protection. An emptied `_card_nodes` therefore produces a lesson that
## dims the whole screen, rings nothing, spends itself permanently on this
## profile, and passes a `lesson_seen` check forever. So each case additionally
## requires the coach to be HOLDING LIVE TARGETS, and requires them to be the
## RIGHT ones — recomputed here from the screen's own board data rather than by
## calling the helper under test, which would only prove it agrees with itself
## (the C20 census shipped exactly that bug and PASSED 18-of-18 on it).
func _probe_stop_screens() -> void:
	# Coaching stays ON for the whole phase — see _probe_road_screens' note; the
	# uniform failure that comment records was this setting, inherited.
	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)
	_check(RunState.run_active,
		"the run went inactive — every screen below bails to the main menu in "
		+ "_ready and would report as an unreachable lesson")

	await _teach_on_screen({
		"id": "recruit_card", "scene": "res://scenes/recruit.tscn",
		"seconds": 12.0, "pump": true,
		"setup": func(): RunState.current_node_type = "recruit",
		"subject": _recruit_subject, "spotlight": _recruit_spotlight})

	await _teach_on_screen({
		"id": "shop_trade", "scene": "res://scenes/shop.tscn",
		"seconds": 12.0,
		"setup": func(): RunState.current_node_type = "shop",
		"subject": _shop_subject, "spotlight": _shop_spotlight})

	# THE CHART, TWICE, IN THE ORDER A PLAYER MEETS IT. `_maybe_coach_the_road`
	# teaches whichever of its two lessons is true right now, so the only honest
	# way to reach the second is to have really been taught the first: the gate
	# branch requires `not should_teach("map_road")`, i.e. map_road already spent.
	# Both opens also get a fat budget — MapView generates and lays out a whole
	# act before the coach's own 0.62s settle even starts.
	await _teach_on_screen({
		"id": "map_road", "scene": "res://scenes/map.tscn", "seconds": 40.0,
		"setup": func(): RunState.holds_broken_in_act = 0,
		"subject": _map_road_subject, "spotlight": _map_road_spotlight})

	# The precondition for the gate branch, asserted rather than assumed. If
	# map_road did not land above, MapView takes the road branch again and the
	# map_gate case below would be measuring the road lesson a second time.
	_check(not TutorialCoach.should_teach("map_road"),
		"map_gate: map_road is still unseen, so MapView takes the road branch "
		+ "again — the keep branch would never be exercised")
	await _teach_on_screen({
		"id": "map_gate", "scene": "res://scenes/map.tscn", "seconds": 40.0,
		# The gate lesson is deliberately withheld until the tally has moved off
		# zero (see _maybe_coach_the_road) — so break a Hold first, or the branch
		# is unreachable by construction.
		"setup": func(): RunState.holds_broken_in_act = 1,
		"subject": _map_gate_subject, "spotlight": _map_gate_spotlight})


## Boot one screen for real and require its lesson to teach itself against
## whatever that screen actually built.
##
## `spec` — `id`, `scene`, `seconds` (wall-clock budget), `pump`, plus four
## optional Callables: `setup()` runs before the boot, `subject(screen)` is this
## case's vacuity guard, `spotlight(screen, coach)` says whether the right thing
## got lit, and `audit(screen)` is free to raise checks of its own (it is how the
## event pin asserts itself without folding two findings into one check). The two
## oracles return "" for OK and a reason otherwise.
func _teach_on_screen(spec: Dictionary) -> void:
	var id := String(spec["id"])
	var path := String(spec["scene"])
	var setup: Callable = spec.get("setup", Callable())
	if setup.is_valid():
		setup.call()
	UserSettings.replay_lesson(id)
	# VACUITY GUARD ONE, and it is the cheapest one in the file: `should_teach`
	# is the exact gate every teaching site asks first, so this single line
	# states the whole precondition — coaching is on, the id is real, and no
	# earlier phase has already spent it. Without it a case can go green against
	# a screen that was never permitted to teach anything.
	_check(TutorialCoach.should_teach(id),
		"%s: not eligible to teach BEFORE %s was booted (coaching mode %d, already seen %s) — every check below would be vacuous"
		% [id, path, UserSettings.coaching_mode, UserSettings.lesson_seen(id)])

	var packed = ResourceLoader.load(path)
	if packed == null:
		_check(false, "%s: could not load %s" % [id, path])
		return
	var screen = packed.instantiate()
	get_tree().root.add_child(screen)
	get_tree().current_scene = screen

	if _MUTANT == id:
		_apply_mutant(id, screen)

	# Polled on the WALL CLOCK, not on a frame count. Headless frames are
	# unbounded and MapView's coach parks on a real 0.62s timer behind several
	# seconds of act generation, so "120 frames" is a budget that means one thing
	# on this machine and something else on the next.
	var deadline := Time.get_ticks_msec() \
		+ int(float(spec.get("seconds", 8.0)) * 1000.0)
	var pump := bool(spec.get("pump", false))
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _MUTANT == id:
			_apply_mutant(id, screen)
		if pump:
			_pump_a_frame()
		if UserSettings.lesson_seen(id):
			break

	# VACUITY GUARD TWO. "The lesson never fired" and "there was nothing on the
	# screen to teach" are different findings and must never share a check — a
	# screen that built no cards would otherwise read as a coaching regression.
	var subject: Callable = spec.get("subject", Callable())
	if subject.is_valid():
		var missing := String(subject.call(screen))
		_check(missing == "", "%s: %s — the lesson's own check proves nothing"
			% [id, missing])

	var audit: Callable = spec.get("audit", Callable())
	if audit.is_valid():
		audit.call(screen)

	_check(UserSettings.lesson_seen(id),
		"%s: %s built and the lesson never fired — either its gate never opened or the teach call is unreachable on this path"
		% [id, path])

	var coach = screen.get_node_or_null("TutorialCoach")
	_check(coach != null and is_instance_valid(coach),
		"%s: no TutorialCoach stands on the screen after the lesson" % id)
	if coach == null or not is_instance_valid(coach):
		screen.queue_free()
		await get_tree().process_frame
		return
	# THE PANEL MUST BE THIS LESSON'S. `lesson_seen` says a lesson got stamped; it
	# cannot say which panel is standing on the screen, and MapView's two lessons
	# share one entry point, one screen and one coach — so without this, a
	# map_gate case could be reading a coach that map_road built.
	var titled = coach.get("_title")
	var shown := "" if titled == null or not is_instance_valid(titled) \
		else String(titled.text)
	_check(shown == TutorialDB.title(id),
		"%s: the coach's panel is headed '%s', not this lesson's title '%s'"
		% [id, shown, TutorialDB.title(id)])

	var lit := _focused_nodes(coach)
	_check(not lit.is_empty(),
		"%s: the coach opened NO spotlight. teach() stamps a lesson seen even when every target resolved to nothing, so this is the exact silent failure the phase exists to catch"
		% id)
	var spotlight: Callable = spec.get("spotlight", Callable())
	if spotlight.is_valid() and not lit.is_empty():
		var wrong := String(spotlight.call(screen, coach))
		_check(wrong == "", "%s: %s" % [id, wrong])

	screen.queue_free()
	await get_tree().process_frame


## Hand the renderer a frame it would never take by itself.
##
## `await RenderingServer.frame_post_draw` NEVER RETURNS under `--headless`: the
## main loop only calls `RenderingServer::draw()` while `can_any_window_draw()`
## is true, and the headless DisplayServer answers false for the life of the
## process. MapTerrain._bake_via_clone and CardTextureCache both carry an
## explicit guard for that fact and take another path; `Recruit._build_ui` does
## NOT (its per-card stagger awaits the signal raw), so Recruit's `_ready`
## suspends on its FIRST card and never reaches its `TutorialCoach.teach` call.
## That is not the game being broken — a player is windowed and posts a frame
## every 16ms — it is the harness being blind to a screen the player sees, which
## is the thing this probe exists to stop happening.
##
## `force_draw` calls draw() directly and emits the signal, so the probe posts
## the frame itself and measures the screen a player gets. Reported, not fixed:
## the missing guard belongs in Recruit.gd beside Shop's, which has it.
func _pump_a_frame() -> void:
	if _headless:
		RenderingServer.force_draw(false)


## The coach's live spotlight targets, as nodes.
func _focused_nodes(coach) -> Array:
	var out: Array = []
	for ref in coach.get("_focus_targets"):
		if not (ref is WeakRef):
			continue
		var t = (ref as WeakRef).get_ref()
		if t != null and is_instance_valid(t):
			out.append(t)
	return out


func _recruit_subject(screen) -> String:
	var cards: Array = screen.get("_card_nodes")
	if cards.is_empty():
		return "Recruit built no card nodes"
	return ""


func _recruit_spotlight(screen, coach) -> String:
	var cards: Array = screen.get("_card_nodes")
	var lit := _focused_nodes(coach)
	for n in lit:
		if not cards.has(n):
			return "a spotlight opened over something that is not a recruit card"
	if lit.size() != cards.size():
		return "%d of the %d recruits on offer are lit" % [lit.size(), cards.size()]
	return ""


func _shop_subject(screen) -> String:
	var purse = screen.get("_gold_label")
	if purse == null or not is_instance_valid(purse):
		return "the Shop built no purse label"
	if not (purse as Control).is_visible_in_tree():
		return "the purse label is hidden, so teach() would drop it as a target"
	return ""


func _shop_spotlight(screen, coach) -> String:
	var lit := _focused_nodes(coach)
	if lit.size() != 1 or lit[0] != screen.get("_gold_label"):
		return "the spotlight is not the purse (%d target(s) lit)" % lit.size()
	return ""


## The walkable stops, recomputed here rather than asked of `_open_site_targets`
## — an oracle that calls the function under test only ever agrees with itself.
func _open_site_buttons(screen) -> Array:
	var out: Array = []
	var btns: Array = screen.get("_site_buttons")
	var nodes: Array = screen.get("_nodes")
	for i in mini(btns.size(), nodes.size()):
		var b = btns[i]
		if b != null and is_instance_valid(b) and not b.disabled:
			out.append(b)
	return out


func _map_road_subject(screen) -> String:
	if screen.get("_site_buttons").is_empty():
		return "the chart drew no site chips"
	if _open_site_buttons(screen).is_empty():
		return "every site chip is disabled, so there is no road to point at"
	return ""


func _map_road_spotlight(screen, coach) -> String:
	var want := _open_site_buttons(screen)
	var lit := _focused_nodes(coach)
	for n in lit:
		if not want.has(n):
			return "a lit chip is not a site the army may actually walk to"
	if lit.size() != want.size():
		return "%d chips lit, %d stops are open" % [lit.size(), want.size()]
	return ""


## The keep's own button, found by walking `_nodes` for the boss entry and taking
## the button built at the same index — `_build_node_buttons` appends one per
## node in order, which is the contract `_keep_site_targets` leans on too.
func _keep_button(screen):
	var nodes: Array = screen.get("_nodes")
	var btns: Array = screen.get("_site_buttons")
	for i in mini(btns.size(), nodes.size()):
		if String((nodes[i] as Dictionary).get("type", "")) == "boss":
			var b = btns[i]
			if b != null and is_instance_valid(b):
				return b
	return null


func _map_gate_subject(screen) -> String:
	if screen.get("_nodes").is_empty():
		return "the act generated no map nodes"
	if _keep_button(screen) == null:
		return "the act has no boss stop wearing a button"
	if RunState.holds_broken_in_act <= 0:
		return "no Hold is broken, so the gate lesson is withheld by design"
	return ""


func _map_gate_spotlight(screen, coach) -> String:
	var keep = _keep_button(screen)
	var lit := _focused_nodes(coach)
	if lit.size() != 1 or lit[0] != keep:
		return "the spotlight is not the keep (%d target(s) lit)" % lit.size()
	return ""


func _stack_keyword_card() -> void:
	# Guarantee a keyworded card in hand rather than trusting the shuffle.
	for card in _combat.get("_hand"):
		if is_instance_valid(card):
			var kws = card.card_data.get("keywords", [])
			if kws is Array and not kws.is_empty():
				return
	var hand: Array = _combat.get("_hand")
	if hand.is_empty():
		return
	var data: Dictionary = hand[0].card_data.duplicate(true)
	data["keywords"] = ["armored"]
	hand[0].card_data = data


func _stack_spell_card() -> void:
	for card in _combat.get("_hand"):
		if is_instance_valid(card) and card.is_spell():
			return
	var hand: Array = _combat.get("_hand")
	if hand.is_empty():
		return
	var data: Dictionary = hand[0].card_data.duplicate(true)
	data["type"] = "spell"
	hand[0].card_data = data


func _summon_a_back_body() -> void:
	if _combat.get("_player_back")[0] == null:
		_combat.call("summon_token", 1, 1, 0, false, 1, {}, "Drill Dummy", [])


func _stock_a_potion() -> void:
	# "healing", not "healing_potion" — the belt takes PotionDB ids, and the wrong
	# one is a silent miss here (the lesson only counts the slot) that surfaces two
	# phases later as a PotionDB warning when MapView draws the same belt.
	if RunState.potions.is_empty():
		RunState.potions.append("healing")
	_combat.call("_update_hud")


func _wait_for_hand() -> void:
	for _i in 600:
		if is_instance_valid(_combat) and _combat.round_number >= 1 \
				and not _combat.get("_hand").is_empty():
			# The deal lands one card at a time; let the fan settle so the HUD
			# (relic chips, potion belt) is fully built before anything is asked
			# whether it is visible.
			await get_tree().create_timer(0.5).timeout
			return
		await get_tree().create_timer(0.05).timeout
