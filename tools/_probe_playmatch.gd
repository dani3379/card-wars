extends SceneTree
## _probe_playmatch.gd — does the bot play like a human?
##
## Replays every combat decision recorded from a REAL player (PlayLog sessions
## with mode=="interactive") and asks HumanPilot what it would do from that
## exact state, then scores agreement. This is the missing instrument: the
## 2026-07-13 pilot was written FROM the playlogs by reading them, but its
## agreement with them was never measured, so "plays like a human" was an
## assertion rather than a number.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_playmatch.gd
##
## Flags:
##   --order=hand_order|curve   creature-selection rule
##   --spells-first             cast before committing bodies
##   --bank=N                   hold N Command back
##   --limit=N                  only read the first N interactive sessions
##   --errors=N                 print N sample disagreements (default 8)
##   --min-plays=N              session quality floor (default 3)
##
## CORPUS QUALITY — read this before trusting any number here. Of 376
## "interactive" sessions, 44 contain a combat_start followed immediately by
## end_turn with a full hand and an empty board: those are the dev opening a
## fight to look at something and leaving, not play. They contributed ~46 fake
## "the human banked a whole turn" decisions and made the stop-rule look
## completely broken. `--min-plays` drops sessions with fewer than N real card
## plays; at the default the corpus is ~11 sessions / ~137 plays / ~52 end
## turns, ALL FROM ONE PLAYER. That is enough to catch gross policy errors and
## to rank heuristics coarsely. It is NOT enough to certify "plays like a
## human" — treat sub-10-point differences as noise and check the ± bands.
##
## Metrics. Every logged play_creature / play_spell / end_turn is one decision;
## the pilot sees the same snapshot the player saw.
##   ACTION   — did it choose the same KIND of action (creature/spell/end turn)?
##   CARD     — of the creature plays both agree on, same card out of hand?
##   LANE/ROW — same placement, scored only where the card matched (a lane
##              comparison across two different cards is meaningless)
##   EXACT    — card + lane + row all agree
## Card/lane/row are conditional on the prior step agreeing, so read them as a
## funnel, not as four independent scores.

const Pilot := preload("res://scripts/sim/HumanPilot.gd")

var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	await process_frame
	var cards: Node = root.get_node_or_null("CardDB")
	if cards == null:
		print("[playmatch] FATAL: CardDB autoload missing")
		quit()
		return

	var params := Pilot.default_params()
	var limit := 0
	var err_budget := 8
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--order="):
			params.creature_order = arg.substr(8)
		elif arg == "--spells-first":
			params.spells_first = true
		elif arg.begins_with("--bank="):
			params.bank_below = int(arg.substr(7))
		elif arg.begins_with("--limit="):
			limit = int(arg.substr(8))
		elif arg.begins_with("--errors="):
			err_budget = int(arg.substr(9))
		elif arg.begins_with("--open="):
			params.open_lane_score = int(arg.substr(7))
		elif arg.begins_with("--block="):
			params.block_score = int(arg.substr(8))

	var min_plays := 3
	for a in OS.get_cmdline_user_args():
		var s2 := String(a)
		if s2.begins_with("--min-plays="):
			min_plays = int(s2.substr(12))

	var all_files := _interactive_sessions(limit)
	var files: Array = []
	for f in all_files:
		if _play_count(f) >= min_plays:
			files.append(f)
	print("[playmatch] interactive sessions: %d, kept %d (>= %d real plays)"
		% [all_files.size(), files.size(), min_plays])

	# Tallies
	var n_dec := 0
	var act_hit := 0
	var n_creature := 0        # human played a creature AND pilot agreed on kind
	var card_hit := 0
	var lane_hit := 0
	var row_hit := 0
	var exact := 0
	var n_human_creature := 0
	var n_human_spell := 0
	var n_human_end := 0
	var pilot_kind_on_end := {}   # what the pilot wanted when the human stopped
	var errors: Array = []

	for f in files:
		for rec in _read_jsonl(f):
			var htype := String(rec.get("type", ""))
			if not (htype in ["play_creature", "play_spell", "end_turn"]):
				continue
			var state: Dictionary = rec.get("state", {})
			if state.is_empty():
				continue
			n_dec += 1
			match htype:
				"play_creature": n_human_creature += 1
				"play_spell": n_human_spell += 1
				_: n_human_end += 1

			var act: Dictionary = Pilot.decide(state, cards, params)
			var pk := String(act.get("kind", "end_turn"))
			var hk := "end_turn"
			if htype == "play_creature":
				hk = "creature"
			elif htype == "play_spell":
				hk = "spell"

			if pk == hk:
				act_hit += 1
			elif htype == "end_turn":
				pilot_kind_on_end[pk] = int(pilot_kind_on_end.get(pk, 0)) + 1

			if hk == "creature" and pk == "creature":
				n_creature += 1
				var same_card: bool = String(act.get("id", "")) == String(rec.get("card", ""))
				if same_card:
					card_hit += 1
					var l_ok: bool = int(act.get("lane", -1)) == int(rec.get("lane", -9))
					var r_ok: bool = int(act.get("row", -1)) == int(rec.get("row", -9))
					if l_ok:
						lane_hit += 1
					if r_ok:
						row_hit += 1
					if l_ok and r_ok:
						exact += 1
					elif errors.size() < err_budget:
						errors.append(_describe(rec, act, state))
				elif errors.size() < err_budget:
					errors.append(_describe(rec, act, state))

	print("")
	print("=== DECISION AGREEMENT (n=%d) ===" % n_dec)
	print("  human plays: %d creature, %d spell, %d end-turn"
		% [n_human_creature, n_human_spell, n_human_end])
	_pct("ACTION KIND", act_hit, n_dec)
	_pct("  CARD  (of agreed creature plays)", card_hit, n_creature)
	_pct("  LANE  (of matched cards)", lane_hit, card_hit)
	_pct("  ROW   (of matched cards)", row_hit, card_hit)
	_pct("  EXACT (card+lane+row)", exact, n_creature)
	if not pilot_kind_on_end.is_empty():
		print("  when the human ENDED TURN, pilot wanted: ", pilot_kind_on_end)
	print("  params: order=%s spells_first=%s bank=%d"
		% [params.creature_order, str(params.spells_first), params.bank_below])

	_score_turns(files, cards, params)
	_score_nuance(files, cards, params)

	if errors.size() > 0:
		print("")
		print("=== SAMPLE DISAGREEMENTS (per-decision) ===")
		for e in errors:
			print(e)
	quit()


## TURN-LEVEL agreement — the headline measure. Groups each session's creature
## plays into player turns, hands the pilot the turn-START snapshot, lets it
## play the whole turn, and compares outcomes as MULTISETS so a different but
## equivalent play order isn't scored as a miss.
func _score_turns(files: Array, cards: Node, params) -> void:
	var turns: Dictionary = {}        # key -> Array of play records (ordered)
	for f in files:
		var combat_i := 0
		for rec in _read_jsonl(f):
			var t := String(rec.get("type", ""))
			if t == "combat_start":
				combat_i += 1
				continue
			if t != "play_creature":
				continue
			var st: Dictionary = rec.get("state", {})
			var key := "%s|%d|%d" % [f, combat_i, int(st.get("round", -1))]
			if not turns.has(key):
				turns[key] = []
			(turns[key] as Array).append(rec)

	var n := 0
	var set_hit := 0
	var order_hit := 0
	var card_overlap := 0
	var card_total := 0
	var place_overlap := 0
	for key in turns:
		var rs: Array = turns[key]
		rs.sort_custom(func(a, b): return int(a.get("seq", 0)) < int(b.get("seq", 0)))
		var human_cards: Array = []
		var human_places: Array = []
		for r in rs:
			human_cards.append(String(r.get("card", "")))
			human_places.append("%s@%d/%d" % [String(r.get("card", "")),
				int(r.get("lane", -1)), int(r.get("row", -1))])
		var acts: Array = Pilot.simulate_turn((rs[0] as Dictionary).get("state", {}),
			cards, params)
		var bot_cards: Array = []
		var bot_places: Array = []
		for a in acts:
			if String((a as Dictionary).get("kind", "")) != "creature":
				continue
			bot_cards.append(String((a as Dictionary).get("id", "")))
			bot_places.append("%s@%d/%d" % [String((a as Dictionary).get("id", "")),
				int((a as Dictionary).get("lane", -1)),
				int((a as Dictionary).get("row", -1))])
		n += 1
		card_total += human_cards.size()
		card_overlap += _multiset_overlap(human_cards, bot_cards)
		place_overlap += _multiset_overlap(human_places, bot_places)
		if _same_multiset(human_cards, bot_cards):
			set_hit += 1
			if human_cards == bot_cards:
				order_hit += 1

	print("")
	print("=== TURN AGREEMENT (n=%d player turns) ===" % n)
	_pct("CARD overlap (order-free)", card_overlap, card_total)
	_pct("PLACEMENT overlap (card+lane+row)", place_overlap, card_total)
	_pct("  whole turn, same card set", set_hit, n)
	_pct("  whole turn, same order too", order_hit, n)


## The three measures the human-move-prediction literature actually leans on,
## none of which top-1 exact-match captures:
##
##  TOP-K       — several lanes are usually near-equivalent, so top-1 alone is
##                a harsh target; Maia-2 reports top-3 for exactly this reason.
##  DIFFICULTY  — accuracy rises with the quality gap between the best and
##                second-best option ("in many positions with only one good
##                move, the good move is an obvious one"). A single blended
##                number hides whether the pilot is nailing the forced plays
##                and coin-flipping the real decisions, or the reverse.
##  DISTRIBUTION— exact-match has a hard ceiling (this game's own logs put the
##                player's self-agreement on lane choice near 57%), so the
##                honest target for "plays the same way" is that the pilot's
##                aggregate behaviour matches the population's. Reported as
##                total variation distance: 0 = identical, 1 = disjoint.
func _score_nuance(files: Array, cards: Node, params) -> void:
	var top1 := 0
	var top2 := 0
	var ranked_n := 0
	var obv_hit := 0
	var obv_n := 0
	var con_hit := 0
	var con_n := 0
	var h_lane := [0, 0, 0, 0]
	var b_lane := [0, 0, 0, 0]
	var h_row := [0, 0]
	var b_row := [0, 0]

	for f in files:
		for rec in _read_jsonl(f):
			if String(rec.get("type", "")) != "play_creature":
				continue
			var state: Dictionary = rec.get("state", {})
			if state.is_empty():
				continue
			var hl: int = int(rec.get("lane", -1))
			var hr: int = int(rec.get("row", -1))
			if hl >= 0 and hl < 4:
				h_lane[hl] += 1
			if hr >= 0 and hr < 2:
				h_row[hr] += 1
			var act: Dictionary = Pilot.decide(state, cards, params)
			if String(act.get("kind", "")) == "creature":
				var bl: int = int(act.get("lane", -1))
				var br: int = int(act.get("row", -1))
				if bl >= 0 and bl < 4:
					b_lane[bl] += 1
				if br >= 0 and br < 2:
					b_row[br] += 1

			# Lane top-k + difficulty, on front-row plays of the card the human
			# actually chose (so this measures PLACEMENT, not selection).
			if hr != 0:
				continue
			var cd: Dictionary = cards.call("get_card_data", String(rec.get("card", "")))
			if cd.is_empty():
				continue
			var ranked: Array = Pilot.rank_front_lanes(state, cd, params)
			if ranked.size() < 2:
				continue
			ranked_n += 1
			if int((ranked[0] as Dictionary)["lane"]) == hl:
				top1 += 1
			if int((ranked[0] as Dictionary)["lane"]) == hl \
					or int((ranked[1] as Dictionary)["lane"]) == hl:
				top2 += 1
			# "Obvious" = a decisive gap between the best and second-best lane.
			var gap: float = float((ranked[0] as Dictionary)["score"]) \
				- float((ranked[1] as Dictionary)["score"])
			if gap >= 40.0:
				obv_n += 1
				if int((ranked[0] as Dictionary)["lane"]) == hl:
					obv_hit += 1
			else:
				con_n += 1
				if int((ranked[0] as Dictionary)["lane"]) == hl:
					con_hit += 1

	print("")
	print("=== PLACEMENT NUANCE (n=%d front plays with a real lane choice) ===" % ranked_n)
	_pct("lane TOP-1", top1, ranked_n)
	_pct("lane TOP-2", top2, ranked_n)
	_pct("  obvious lanes (decisive gap)", obv_hit, obv_n)
	_pct("  contested lanes (near-tie)", con_hit, con_n)
	print("")
	print("=== DISTRIBUTION MATCH (aggregate behaviour, not per-decision) ===")
	print("  lane  human %s  vs  pilot %s   TVD %.3f"
		% [str(h_lane), str(b_lane), _tvd(h_lane, b_lane)])
	print("  row   human %s  vs  pilot %s   TVD %.3f"
		% [str(h_row), str(b_row), _tvd(h_row, b_row)])
	print("  (reference: SOTA human move prediction in chess peaks ~53%% top-1;")
	print("   this player's own lane self-agreement measured ~57%%.)")


## Total variation distance between two count histograms.
func _tvd(a: Array, b: Array) -> float:
	var sa := 0.0
	var sb := 0.0
	for x in a:
		sa += float(x)
	for x in b:
		sb += float(x)
	if sa <= 0.0 or sb <= 0.0:
		return 1.0
	var d := 0.0
	for i in a.size():
		d += absf(float(a[i]) / sa - float(b[i]) / sb)
	return d * 0.5


func _multiset_overlap(a: Array, b: Array) -> int:
	var pool: Array = b.duplicate()
	var hit := 0
	for x in a:
		var i: int = pool.find(x)
		if i >= 0:
			pool.remove_at(i)
			hit += 1
	return hit


func _same_multiset(a: Array, b: Array) -> bool:
	return a.size() == b.size() and _multiset_overlap(a, b) == a.size()


func _pct(label: String, hit: int, total: int) -> void:
	if total <= 0:
		print("  %-34s   n/a (0)" % label)
		return
	var p := 100.0 * float(hit) / float(total)
	# Wald 95% band — with a few hundred decisions the noise floor is several
	# points wide, so a bare percentage invites reading nonexistent progress.
	var se := sqrt(p * (100.0 - p) / float(total))
	print("  %-34s %5.1f%%  ±%.1f   (%d/%d)" % [label, p, 1.96 * se, hit, total])


func _describe(rec: Dictionary, act: Dictionary, state: Dictionary) -> String:
	var hand_ids: Array = []
	for h in state.get("hand", []):
		hand_ids.append("%s(%d)" % [String(h.get("id", "?")), int(h.get("cost", 0))])
	return "  r%d mana %d | human: %s @L%d/R%d | pilot: %s @L%d/R%d | hand: %s" % [
		int(state.get("round", 0)), int(state.get("mana", 0)),
		String(rec.get("card", "?")), int(rec.get("lane", -1)), int(rec.get("row", -1)),
		String(act.get("id", act.get("kind", "?"))),
		int(act.get("lane", -1)), int(act.get("row", -1)),
		", ".join(hand_ids)]


func _interactive_sessions(limit: int) -> Array:
	var out: Array = []
	var dir := DirAccess.open("user://playlogs")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".jsonl"):
			var path := "user://playlogs/" + name
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				var first := f.get_line()
				f.close()
				var j = JSON.parse_string(first)
				if j is Dictionary and String(j.get("mode", "")) == "interactive":
					out.append(path)
					if limit > 0 and out.size() >= limit:
						break
		name = dir.get_next()
	dir.list_dir_end()
	return out


## How many real card plays a session contains — the session-quality signal.
## A file full of end_turns and nothing else is someone leaving a fight, and
## its "decisions" are noise that swamps the stop-rule metric.
func _play_count(path: String) -> int:
	var n := 0
	for rec in _read_jsonl(path):
		if String(rec.get("type", "")) in ["play_creature", "play_spell"]:
			n += 1
	return n


func _read_jsonl(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var j = JSON.parse_string(line)
		if j is Dictionary:
			out.append(j)
	f.close()
	return out
