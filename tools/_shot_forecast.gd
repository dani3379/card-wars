extends Node
## _shot_forecast.gd — LOOK AT THE ALWAYS-ON LANE FORECAST.
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_forecast.tscn
##
## The lane forecast is the most-looked-at overlay in the game (it is on screen
## for the whole planning phase, every round, every fight) and it is the one
## combat surface no harness has ever photographed on its own. `_shot_clash_read`
## takes a single `plan_full` frame of it in passing, at 1600x900, as question #6
## of eight — which is how "a dark pill parked on the creature's face" survived
## two polish passes.
##
## THREE THINGS IT DOES THAT A 1600x900 FRAME CANNOT.
##
##  1. NEAREST-NEIGHBOUR ZOOMS, the `_shot_coach_devices` precedent: a chip's
##     corner radius, its plate inset and the weight of its outline are not
##     decidable at 1:1.
##  2. THE PAINTING ORACLE. Card2D's own `_kw_stamp_row` states the house rule
##     for this exact question — keyword devices are "printed ON the paper,
##     never pinned over the painting (the art plate stays clean; that was v7's
##     mistake)". The battlefield token puts its name overlay at anchor_top 0.70,
##     so the top 70% of a token IS the painting. This measures every forecast
##     chip's rect against that band and reports the intersection as a
##     percentage of the chip. A chip sitting on the art is the defect, and it
##     is arithmetic rather than taste.
##  3. A CENSUS BY CLASS. `Panel`/`Label` in the node list means the overlay is
##     still made of UI chrome; the rebuilt kit should be drawn Controls and
##     beam/ring nodes.
##
## It stages the reads that actually differ from each other rather than whatever
## a random board deals: a survivable hit, a LETHAL hit, a HELD refusal (the two
## the owner called out), a face breakthrough, and a two-attacker aggregate.
##
## Headless runs print every measurement and skip the PNGs (get_image is blank
## under the dummy renderer) — so the oracle is CI-able and only the eyes need a
## display.

const SHOT_DIR := "res://tools/screenshot/forecast"
const ENC := "oathbroken_knights"
const STATE_TIMEOUT := 90.0
const POLL := 0.2

## The staged plan. Each column is chosen to produce ONE distinct forecast read.
##   lane 0  enemy 3/3 vs our 7/2      -> our body dies      (LETHAL chip)
##   lane 1  enemy 2/8 vs our 2/9      -> both survive       (survivable chip)
##   lane 2  enemy 2/3 + back 3/2 vs our 6/6 -> two blows    (AGGREGATE chip)
##   lane 3  enemy 4/4 vs nothing      -> face breakthrough  (face marker)
const ENEMY_FRONT := [[3, 3], [2, 8], [2, 3], [4, 4]]
const ENEMY_BACK := {2: [3, 2]}
const PLAYER_FRONT := [[7, 2], [2, 9], [6, 6], null]
const PLAYER_BACK := {1: [3, 5]}
const PLAYER_NAMES := ["Pikeman", "Palisade", "Outrider", ""]

## The painting band of a battlefield token, from Card2D._build_compact_layout:
## the name overlay is anchored at 0.70, so 0..0.70 of the token height is art.
const ART_TOP_FRAC := 0.04
const ART_BOT_FRAC := 0.70

var _combat: Node = null
var _shots := 0
var _headless := false
var _problems: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[fc] WATCHDOG — never finished")
		get_tree().quit(1))

	_headless = DisplayServer.get_name() == "headless"
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	if not _headless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# Ship settings, not this machine's — Reduce Motion on the dev profile would
	# photograph the accessibility fallback and answer a different question.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	UserSettings.combat_telegraph = true
	UserSettings.end_turn_warning = false
	for m in ["mark_combat_model_tutorial_seen", "mark_intents_tutorial_seen",
			"mark_pile_tutorial_seen", "mark_dismiss_tutorial_seen",
			"mark_banking_tutorial_seen", "mark_floop_tutorial_seen",
			"mark_sacrifice_tutorial_seen"]:
		if UserSettings.has_method(m):
			UserSettings.call(m)

	# SEEDED, OR THE ORACLE CANNOT GATE ANYTHING (2026-09-24). Without a seed
	# `start_new_run` mints a random one, so every run of this harness booted a
	# different encounter and muster: the staged board came out with 8 bodies or
	# 7, and the same lane read `2/8` one run and `3/8` the next (an encounter
	# passive the stage does not override). The seal oracle duly flickered
	# between 0 and 2 collisions ON IDENTICAL CODE, which made it impossible to
	# tell a geometry fix from a lucky draw — I chased my own tail on it for
	# three sweeps. A fixture that varies is not a fixture.
	RunState.start_new_run("stalwart", -1, 20260924)
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	if not await _await_state(1, false, "round 1 player turn"):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return
	await get_tree().create_timer(2.2).timeout

	_stage_board()
	await get_tree().create_timer(1.4).timeout

	# Force a rebuild through the REAL entry point — the signature cache would
	# otherwise skip it, and a harness that draws the overlay itself is testing
	# the harness.
	_combat.set("_lane_forecast_signature", "")
	_combat.call("_refresh_lane_forecast")
	await get_tree().create_timer(0.6).timeout

	_census()
	_painting_oracle()
	_geometry()

	await _shoot("board")
	# Zooms: one per staged read, cropped around the target token so the chip,
	# the ring and the token's own stat seals are all in frame together.
	await _zoom_on_lane(0, "lane0_lethal")
	await _zoom_on_lane(1, "lane1_survives")
	await _zoom_on_lane(2, "lane2_aggregate")
	await _zoom_on_lane(3, "lane3_face")
	await _shoot_refusal_states()

	print("[fc] frames written: %d -> %s" % [_shots, SHOT_DIR])
	if _problems.is_empty():
		print("[fc] FORECAST_SHOT_DONE")
		get_tree().quit()
	else:
		for p in _problems:
			print("[fc] PROBLEM: ", p)
		print("[fc] FORECAST_SHOT_DONE_WITH_FINDINGS")
		get_tree().quit()


# ── the measurements ───────────────────────────────────────────────────────

## THE TWO STATES THE STAGED BOARD CANNOT DEAL, and one of them is the state the
## owner named. A refusal ("HELD — NO FACE THIS ROUND", the Rush rule) needs a
## Swift body in its arrival round facing an empty column, and a face KILL needs
## the hero low enough to die — neither survives the fixed plan this harness
## exists to keep stable.
##
## So they are pushed through the REAL mark layer (`_add_lane_forecast`) with the
## dict shape the predictor emits, exactly as `_shot_clash_read` drives its
## enemy-only A/B. This photographs the MARKS; `_probe_combat_telegraph` is what
## proves the predictor produces these dicts.
func _shoot_refusal_states() -> void:
	var host = _card(true, 0, 1)
	if host == null:
		print("[fc] no host for the refusal frame — skipped")
		return
	_combat.call("_clear_lane_forecast")
	_combat.call("_add_lane_forecast", host, {
		"point": _combat.call("_card_center", host),
		"text": "HELD - NO FACE THIS ROUND", "quiet_text": "HELD",
		"color": Color(0.72, 0.76, 0.82), "face": false, "damage": 0,
		"refusal": true,
	})
	var blocked = _card(true, 0, 2)
	if blocked != null:
		_combat.call("_add_lane_forecast", blocked, {
			"point": _combat.call("_card_center", blocked),
			"text": "BLOCKED - NO STRIKE", "quiet_text": "BLOCKED",
			"color": Color(0.72, 0.76, 0.82), "face": false, "damage": 0,
			"refusal": true,
		})
	await get_tree().process_frame
	await get_tree().process_frame
	_census()
	await _zoom_on_lane(1, "refusal_held")
	# Put the real read back — the signature cache would otherwise decide
	# nothing had changed and leave the staged fakes on screen.
	_combat.set("_lane_forecast_signature", "")
	_combat.call("_refresh_lane_forecast")
	await get_tree().process_frame


func _nodes() -> Array:
	var raw = _combat.get("_lane_forecast_nodes")
	var out: Array = []
	for n in (raw as Array):
		if n != null and is_instance_valid(n):
			out.append(n)
	return out


func _census() -> void:
	var by_class: Dictionary = {}
	for n in _nodes():
		var k: String = n.get_class()
		by_class[k] = int(by_class.get(k, 0)) + 1
	var parts: Array[String] = []
	for k in by_class:
		parts.append("%s=%d" % [k, int(by_class[k])])
	parts.sort()
	print("[fc] forecast nodes: %d  (%s)" % [_nodes().size(), ", ".join(parts)])
	for n in _nodes():
		if n is Label:
			print("[fc]   label %-34s at %s size %s" % [
				'"%s"' % String(n.text).replace("\n", " / "),
				str(Vector2i((n as Label).global_position)),
				str(Vector2i((n as Label).size))])


## Every chip rect against every token's painting band.
func _painting_oracle() -> void:
	var cards: Array = _combat.call("_all_creatures_both_sides")
	var worst := 0.0
	var hits := 0
	# THE FILTER BELOW USED TO BE `if not (c is Label): continue`, AND IT HAD
	# GONE VACUOUS (found 2026-09-20 from a player report that "the circle clips
	# through the card edge").
	#
	# When this oracle was written every chip was a plate with a Label on it, so
	# measuring the ink was measuring the chip. The 2026-09-16 redesign then
	# deleted the words — "an ordinary read prints NO WORDS AT ALL" — and
	# replaced them with `WoundSeal` and `StruckBracket` painters. The filter was
	# never updated, so from that day the oracle measured only the EXCEPTIONAL
	# word chips: on the staged board, **2 Labels out of 20 forecast nodes.** It
	# then reported "0 collisions" and was read as proof the redesign had cleared
	# the painting, when in fact it had stopped looking at the redesign.
	#
	# Now every forecast node is measured. Children are skipped so a plate and
	# its label are not counted twice — the outermost node is the chip.
	var measured: Array = _nodes()
	for n in measured:
		if not (n is Control):
			continue
		var c := n as Control
		var nested := false
		for other in measured:
			if other != c and other is Node and (other as Node).is_ancestor_of(c):
				nested = true
				break
		if nested:
			continue
		var inks: Array = _ink_rects_of(c)
		var area := 0.0
		for ir in inks:
			area += (ir as Rect2).size.x * (ir as Rect2).size.y
		if area <= 0.0:
			continue
		for card in cards:
			if card == null or not is_instance_valid(card):
				continue
			var art := _art_rect(card)
			var cov := 0.0
			for ir in inks:
				var ov := (ir as Rect2).intersection(art)
				if ov.size.x > 0.0 and ov.size.y > 0.0:
					cov += ov.size.x * ov.size.y
			if cov <= 0.0:
				continue
			var frac: float = cov / area
			if frac < 0.02:
				continue
			hits += 1
			worst = maxf(worst, frac)
			print("[fc]   ON THE PAINTING: %-30s %.0f%% of the chip is over %s's art" % [
				_chip_name(c), frac * 100.0,
				String(card.card_data.get("name", "?"))])
	print("[fc] painting oracle: %d chip/art collisions, worst %.0f%% covered" % [
		hits, worst * 100.0])
	_seal_oracle(cards, measured)
	if hits > 0:
		_problems.append(
			"%d forecast chips sit on a creature's painting (worst %.0f%%)"
			% [hits, worst * 100.0])


## Where a mark is ALLOWED to go. Prints the token rect, its painting band, its
## two stat seals and the clear gutter around it, so placement is measured
## instead of guessed — the reason the old chip landed on a creature's face is
## that `_card_center` was the only anchor anyone ever computed.
func _geometry() -> void:
	print("[fc] --- board geometry ---")
	for is_enemy in [true, false]:
		for row in [0, 1]:
			for lane in range(4):
				var c = _card(is_enemy, row, lane)
				if c == null:
					continue
				var r := Rect2(c.global_position, c.size * c.scale)
				var hp := _hp_seal_rect(c)
				print("[fc]   %s r%d l%d  token %s  art %s  hpseal %s" % [
					"foe " if is_enemy else "ours", row, lane,
					_r(r), _r(_art_rect(c)), _r(hp)])
	# The clear space between columns and between rows — the only ground a mark
	# can occupy without covering either the painting or a stat seal.
	var a = _card(true, 0, 0)
	var b = _card(true, 0, 1)
	if a != null and b != null:
		var ga: Rect2 = Rect2(a.global_position, a.size * a.scale)
		var gb: Rect2 = Rect2(b.global_position, b.size * b.scale)
		print("[fc]   column gutter: %.0fpx" % (gb.position.x - ga.end.x))
	var f = _card(true, 0, 0)
	var g = _card(false, 0, 0)
	if f != null and g != null:
		var gf: Rect2 = Rect2(f.global_position, f.size * f.scale)
		var gg: Rect2 = Rect2(g.global_position, g.size * g.scale)
		print("[fc]   front-line gap: %.0fpx" % (gg.position.y - gf.end.y))


func _r(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [int(r.position.x), int(r.position.y),
		int(r.size.x), int(r.size.y)]


func _art_rect(card: Control) -> Rect2:
	var sz: Vector2 = card.size * card.scale
	return Rect2(
		card.global_position + Vector2(0.0, sz.y * ART_TOP_FRAC),
		Vector2(sz.x, sz.y * (ART_BOT_FRAC - ART_TOP_FRAC)))


## The HP seal's live screen rect — where a wound read would have to land if it
## wanted to speak in the card's own numbers rather than beside them.
func _hp_seal_rect(card: Control) -> Rect2:
	var lbl = card.get("_hp_label")
	if lbl == null or not is_instance_valid(lbl):
		return Rect2()
	var parent := (lbl as Control).get_parent()
	if parent is Control:
		return (parent as Control).get_global_rect()
	return (lbl as Control).get_global_rect()


# ── shooting ───────────────────────────────────────────────────────────────

func _shoot(tag: String) -> void:
	if _headless:
		return
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[fc] SAVED %s.png %s" % [tag, str(img.get_size())])


## A 3x nearest-neighbour crop centred on a lane's contested column. Nearest so
## the zoom shows the pixels that exist rather than a resampler's opinion of
## them — the same reason _shot_coach_devices zooms its 2px rims.
func _zoom_on_lane(lane: int, tag: String) -> void:
	if _headless:
		return
	var focus := _lane_focus_point(lane)
	if focus == Vector2.ZERO:
		print("[fc] no focus for lane %d — skipped" % lane)
		return
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var box := Vector2i(330, 250)
	var org := Vector2i(focus) - box / 2
	org.x = clampi(org.x, 0, img.get_width() - box.x)
	org.y = clampi(org.y, 0, img.get_height() - box.y)
	var crop := img.get_region(Rect2i(org, box))
	crop.resize(box.x * 3, box.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOT_DIR, tag])
	_shots += 1
	print("[fc] SAVED %s.png (3x zoom at %s)" % [tag, str(Vector2i(focus))])


## Centre the crop on whatever the read is ABOUT: the struck body if there is
## one, else the attacker.
func _lane_focus_point(lane: int) -> Vector2:
	for row in [0, 1]:
		var c = _card(false, row, lane)
		if c != null:
			return _combat.call("_card_center", c)
	var e = _card(true, 0, lane)
	if e != null:
		return _combat.call("_card_center", e)
	return Vector2.ZERO


# ── staging ────────────────────────────────────────────────────────────────

func _stage_board() -> void:
	var placed := 0
	for lane in range(4):
		var want = ENEMY_FRONT[lane]
		if want == null:
			continue
		var c = _card(true, 0, lane)
		if c == null:
			_combat.call("_place_enemy_card", _mk("Footman", want[0], want[1]),
				lane, 0, false)
			c = _card(true, 0, lane)
			placed += 1
		_force(c, want[0], want[1])
	for lane in ENEMY_BACK.keys():
		var want2 = ENEMY_BACK[lane]
		var c2 = _card(true, 1, int(lane))
		if c2 == null:
			_combat.call("_place_enemy_card", _mk("Squire", want2[0], want2[1]),
				int(lane), 1, false)
			c2 = _card(true, 1, int(lane))
			placed += 1
		_force(c2, want2[0], want2[1])
	# Anything the muster put outside the plan is left standing but made inert,
	# so the four staged columns still read the way they were designed to.
	for c3 in (_combat.call("_all_enemy_creatures") as Array):
		if _planned(int(c3.current_row), int(c3.current_lane)):
			continue
		_force(c3, 1, 6)

	for lane in range(4):
		var pw = PLAYER_FRONT[lane]
		if pw == null:
			continue
		var p = _card(false, 0, lane)
		if p == null:
			_combat.call("summon_token", pw[0], pw[1], lane, false, 0, {},
				PLAYER_NAMES[lane], [])
			p = _card(false, 0, lane)
			placed += 1
		_force(p, pw[0], pw[1])
	for lane in PLAYER_BACK.keys():
		var pw2 = PLAYER_BACK[lane]
		var p2 = _card(false, 1, int(lane))
		if p2 == null:
			_combat.call("summon_token", pw2[0], pw2[1], int(lane), false, 1, {},
				"Bowman", [])
			p2 = _card(false, 1, int(lane))
			placed += 1
		_force(p2, pw2[0], pw2[1])

	# The muster delay's state. `_start_round` is what normally sweeps it, so
	# doing it here is the round-open's own act, not a cheat around the rule.
	for c4 in (_combat.call("_all_creatures_both_sides") as Array):
		c4.state.ready_to_swing = true
		c4.has_attacked_this_turn = false
		if c4.is_opponent:
			c4.state.current_intent = "ATK"
			_combat.call("_update_intent_display", c4, "ATK")
	_combat.call("_refresh_adjacency_buffs")
	_combat.set("_friendly_deaths_this_round", 0)
	_combat.set("_enemy_deaths_this_round", 0)
	_combat.call("_update_hud")
	print("[fc] staged: %d bodies added" % placed)
	_report_board()


func _planned(row: int, lane: int) -> bool:
	if row == 0:
		return lane >= 0 and lane < 4 and ENEMY_FRONT[lane] != null
	return ENEMY_BACK.has(lane)


func _report_board() -> void:
	for is_enemy in [true, false]:
		for row in [0, 1]:
			var cells: Array[String] = []
			for lane in range(4):
				var c = _card(is_enemy, row, lane)
				cells.append("----" if c == null
					else "%d/%d" % [int(c.effective_atk()), int(c.current_hp)])
			print("[fc]   %s %s  %s" % [
				"foe " if is_enemy else "ours",
				"front" if row == 0 else "back ", " ".join(cells)])


func _card(is_enemy: bool, row: int, lane: int):
	var arr = _combat.call("_row_array", is_enemy, row)
	var c = arr[lane]
	return c if (c != null and is_instance_valid(c)) else null


func _mk(nm: String, atk: int, hp: int) -> Dictionary:
	return EncounterDB.make_card_data({"name": nm, "atk": atk, "hp": hp, "kw": []})


func _force(card, atk: int, hp: int) -> void:
	if card == null or not is_instance_valid(card):
		return
	# last_stand / regenerate would silently turn a staged lethal column into one
	# that is not, and the capture would disagree with its own plan.
	for kw in ["last_stand", "regenerate"]:
		if card.has_method("has_keyword") and card.has_keyword(kw):
			var kws: Array = Array(card.card_data.get("keywords", []))
			kws.erase(kw)
			card.card_data["keywords"] = kws
	card.current_atk = atk
	card.current_hp = hp
	card.state.temp_atk_buff = 0
	card.state.persistent_atk_buff = 0
	if card.has_method("update_stat_display"):
		card.update_stat_display()


func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[fc] ABORT — combat scene gone waiting for ", what)
			get_tree().quit(1)
			return false
		if int(_combat.get("round_number")) >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[fc] ABORT — timed out waiting for ", what)
	get_tree().quit(1)
	return false


## A chip's name for the report. Not every chip is a Label any more — since the
## 2026-09-16 redesign most of them are painters that print nothing at all — so
## the class name is the only universally available identity.
func _chip_name(c: Control) -> String:
	if c is Label:
		return '"%s"' % String((c as Label).text).replace("
", " / ")
	return "<%s>" % c.get_class() if c.get_script() == null 		else "<%s>" % String(c.get_script().resource_path).get_file().get_basename()


## THE SECOND KEEP-OUT, AND THE ONE THE PAINTING BAND CANNOT SEE.
##
## `_painting_oracle` measures against the art band, 0.04..0.70 of token height.
## The card's own ATK and HP wax seals sit at **0.845** — BELOW that band — so a
## forecast mark landing on a seal is invisible to it by construction. That is
## exactly what a player reported on 2026-09-20: the bracket's bottom corner
## ticks are drawn across the seals, which reads as the card's edge cutting
## through the circle.
##
## The seals are the card speaking its own numbers. A mark laid over them is
## worse than a mark on the painting: it does not merely cover art, it covers
## the two figures the player reads the board by.
func _seal_oracle(cards: Array, measured: Array) -> void:
	var hits := 0
	var worst := 0.0
	for n in measured:
		if not (n is Control):
			continue
		var c := n as Control
		var nested := false
		for other in measured:
			if other != c and other is Node and (other as Node).is_ancestor_of(c):
				nested = true
				break
		if nested:
			continue
		var inks: Array = _ink_rects_of(c)
		for card in cards:
			if card == null or not is_instance_valid(card):
				continue
			for sr in _stat_seal_rects(card):
				var cov := 0.0
				for ir in inks:
					var ov := (ir as Rect2).intersection(sr as Rect2)
					if ov.size.x > 0.0 and ov.size.y > 0.0:
						cov += ov.size.x * ov.size.y
				if cov <= 0.0:
					continue
				var frac: float = cov / ((sr as Rect2).size.x * (sr as Rect2).size.y)
				if frac < 0.02:
					continue
				hits += 1
				worst = maxf(worst, frac)
				print("[fc]   ON A STAT SEAL: %-24s covers %.0f%% of a seal on %s" % [
					_chip_name(c), frac * 100.0,
					String(card.card_data.get("name", "?"))])
	print("[fc] seal oracle: %d chip/seal collisions, worst %.0f%% of a seal covered" % [
		hits, worst * 100.0])
	if hits > 0:
		_problems.append(
			"%d forecast marks sit on a card's own stat seal (worst %.0f%%)"
			% [hits, worst * 100.0])


## Both wax seals, in screen space. Built from `Card2D._build_compact_layout`'s
## own anchors (38px boxes, inset 3px from each bottom corner) rather than
## measured off a label, so an empty or baked token still reports them.
func _stat_seal_rects(card: Control) -> Array:
	var sz: Vector2 = card.size * card.scale
	var k: float = sz.x / 200.0        # the layout is authored against a 200px token
	var box: float = 38.0 * k
	var inset: float = 3.0 * k
	var y: float = card.global_position.y + sz.y - inset - box
	return [
		Rect2(Vector2(card.global_position.x + inset, y), Vector2(box, box)),
		Rect2(Vector2(card.global_position.x + sz.x - inset - box, y),
			Vector2(box, box)),
	]


## A chip's INK, not its box. A `StruckBracket`'s Control is the whole token and
## it paints four short corner ticks, so measuring the rect reports a bracket as
## covering 100% of a stat seal the ink misses entirely — "fit the INK, not the
## boxes", the same rule the relic rail's fit already runs on. Painters that know
## their own ink expose `ink_rects()`; everything else is its own rect.
func _ink_rects_of(c: Control) -> Array:
	if c.has_method("ink_rects"):
		var ink: Array = c.call("ink_rects")
		if not ink.is_empty():
			return ink
	return [Rect2(c.global_position, c.size * c.scale)]
