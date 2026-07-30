extends SceneTree
## Headless gate for SET-PIECE HOLDS — the named actions of the war
## (scripts/data/SetPieceDB.gd, engine in Combat.gd's set-piece section).
##
##   Godot.exe --headless --path . --script res://tools/_probe_setpiece.gd
##
## What it proves, and why each check exists:
##   A. DATA INTEGRITY — every authored set-piece has the fields the engine
##      dereferences without guards, its objective kind is one the engine
##      actually implements, and its trophy names a real relic. A typo'd
##      objective kind would silently make a scenario unwinnable.
##   B. AUTHORED-BOARD SANITY — no opening body sits in a lane the same
##      scenario CLOSES (that body could never have been placed), no two
##      bodies share a slot, and every objective that needs a flagged body
##      (slay_marked → "mark", protect → "ward") actually has one.
##   C. TROPHIES ARE UNROLLABLE — every trophy is tier "event", so a set-piece
##      prize can never leak into a shop, reward or treasure roll. If one did,
##      the named action would stop being the reason to take the hard road.
##   D. MAP PLACEMENT — across many seeds: at most one named action per act,
##      always on a plain fight row, never on the war road's row, always on a
##      row wide enough to route AROUND (the whole design rests on it being a
##      choice), and never carrying a mutator on top of its own ground.
##   E. WITHDRAWAL IS SURVIVABLE — every toll is smaller than the HP a player
##      could plausibly arrive with, and the engine clamps it below lethal
##      regardless. Failing a puzzle must never end a run.

const FIGHT_ROWS := [0, 3, 9, 15]
const ELITE_ROWS := [6, 12]
const OBJECTIVE_KINDS := ["hold_rounds", "slay_marked", "protect",
	"break_face", "clear_board"]
const LANES := 4
const REQUIRED_VARIETY := {
	"the_relief_fort": "break_face",
	"the_last_muster": "clear_board",
}


var _fails := 0
var _ran := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	var spdb: Node = root.get_node_or_null("SetPieceDB")
	var rdb: Node = root.get_node_or_null("RelicDB")
	if rs == null or spdb == null or rdb == null:
		print("[setpiece-probe] autoloads missing (RunState / SetPieceDB / RelicDB)")
		quit(1)
		return true

	# ── A. DATA INTEGRITY ────────────────────────────────────────────────
	print("— A. data integrity (%d authored set-pieces)" % spdb.SET_PIECES.size())
	_check(spdb.SET_PIECES.size() >= 1, "at least one set-piece is authored")
	var acts_seen: Dictionary = {}
	for sp_id in spdb.SET_PIECES:
		var sp: Dictionary = spdb.SET_PIECES[sp_id]
		var tag: String = String(sp_id)
		for field in ["name", "act", "brief", "ground", "objective", "deck",
				"reinforcement", "hp", "toll"]:
			_check(sp.has(field), "%s has `%s`" % [tag, field])
		var act: int = int(sp.get("act", 0))
		_check(act >= 1 and act <= 3, "%s act %d is in range" % [tag, act])
		acts_seen[act] = int(acts_seen.get(act, 0)) + 1
		var obj: Dictionary = sp.get("objective", {})
		var kind: String = String(obj.get("kind", ""))
		_check(OBJECTIVE_KINDS.has(kind),
			"%s objective kind `%s` is implemented" % [tag, kind])
		_check(String(obj.get("label", "")) != "", "%s objective has a label" % tag)
		_check(String(obj.get("short", "")) != "", "%s objective has a short form" % tag)
		# Every kind except clear_board is meaningless without a deadline.
		if kind != "clear_board":
			_check(int(obj.get("rounds", 0)) >= 1,
				"%s objective has a deadline" % tag)
		# `break_face` is the one kind that needs a magnitude as well as a clock.
		if kind == "break_face":
			_check(int(obj.get("value", 0)) >= 1, "%s break_face has a value" % tag)
		# Copy budgets — COPY_STYLE §10 road register. The brief is read mid-run
		# by a tired player; a wall of text is the failure mode.
		var words: int = String(sp.get("brief", "")).split(" ", false).size()
		_check(words <= 55, "%s brief is %d words (<= 55)" % [tag, words])
		_check(String(sp.get("won", "")) != "" and String(sp.get("lost", "")) != "",
			"%s has both verdict lines" % tag)
		# The ground is the ONE twisted rule and it must be printed.
		_check(String(sp.get("ground", {}).get("text", "")) != "",
			"%s prints its ground rule" % tag)
		_check(String(sp.get("ground", {}).get("name", "")) != "",
			"%s names its ground rule" % tag)

	# Focused variety slice: these two IDs turn the final unused objective kinds
	# into map-live scenarios. Keep their clocks generous enough for a plain,
	# slow deck rather than balancing around reach, burst or rare cards.
	print("-- A2. break-face / clear-board variety rails")
	for required_id in REQUIRED_VARIETY:
		_check(spdb.exists(required_id), "%s is live in SetPieceDB" % required_id)
		if spdb.exists(required_id):
			_check(String(spdb.get_set_piece(required_id).get("objective", {}).get(
				"kind", "")) == String(REQUIRED_VARIETY[required_id]),
				"%s keeps its promised objective kind" % required_id)

	if spdb.exists("the_relief_fort"):
		var relief: Dictionary = spdb.get_set_piece("the_relief_fort")
		var relief_obj: Dictionary = relief.get("objective", {})
		var relief_rounds: int = int(relief_obj.get("rounds", 0))
		var occupied_lanes: Dictionary = {}
		for entry in relief.get("opening", {}).get("enemy", []):
			occupied_lanes[int(entry.get("lane", -1))] = true
		_check(bool(relief.get("rules", {}).get("no_reinforce", false)),
			"the_relief_fort is a finite board with no reserve drip")
		_check(relief_rounds >= 6,
			"the_relief_fort gives a slow deck at least six rounds")
		# A 2-ATK creature played into the empty lane on round 1 pays muster
		# delay, then has enough clashes left to meet this printed threshold.
		_check(int(relief_obj.get("value", 0)) <= maxi(1, relief_rounds - 1) * 2,
			"the_relief_fort threshold fits one plain 2-ATK lane clock")
		_check(occupied_lanes.size() < LANES,
			"the_relief_fort opens at least one direct lane")

	if spdb.exists("the_last_muster"):
		var muster: Dictionary = spdb.get_set_piece("the_last_muster")
		var muster_obj: Dictionary = muster.get("objective", {})
		var muster_bodies: Array = muster.get("opening", {}).get("enemy", [])
		# Combat thickens ordinary enemy bodies by +0/+1/+2 HP across the acts.
		# Budget the board the player actually sees, not its pre-scale payload.
		var act_thickening := clampi(int(muster.get("act", 1)) - 1, 0, 2)
		var live_hp := 0
		for entry in muster_bodies:
			live_hp += int(entry.get("hp", 0)) + act_thickening
		_check(bool(muster.get("rules", {}).get("no_reinforce", false)),
			"the_last_muster cannot refill the board after it is cleared")
		_check(int(muster_obj.get("rounds", 0)) >= 6,
			"the_last_muster gives a slow deck at least six rounds")
		_check(muster_bodies.size() <= 4,
			"the_last_muster asks for at most one opening body per lane")
		_check(live_hp <= 20,
			"the_last_muster live HP stays inside the slow-deck budget (%d)" % live_hp)

	# ── B. AUTHORED-BOARD SANITY ─────────────────────────────────────────
	print("— B. authored opening boards")
	for sp_id in spdb.SET_PIECES:
		var sp: Dictionary = spdb.SET_PIECES[sp_id]
		var tag: String = String(sp_id)
		var closed: Array = spdb.closed_lanes(sp_id)
		for lane in closed:
			_check(int(lane) >= 0 and int(lane) < LANES,
				"%s closed lane %s is on the board" % [tag, str(lane)])
		_check(closed.size() < LANES, "%s does not close every lane" % tag)
		var seen: Dictionary = {}
		var has_mark := false
		var has_ward := false
		for side in ["enemy", "player"]:
			for entry in spdb.build_opening(sp_id, side):
				var row: int = int(entry.row)
				var lane: int = int(entry.lane)
				var key: String = "%s:%d:%d" % [side, row, lane]
				_check(not seen.has(key),
					"%s %s opening slot r%d l%d is unique" % [tag, side, row, lane])
				seen[key] = true
				_check(row == 0 or row == 1, "%s opening row %d is valid" % [tag, row])
				_check(lane >= 0 and lane < LANES,
					"%s opening lane %d is valid" % [tag, lane])
				# The rule must not contradict the board it ships with.
				_check(not closed.has(lane),
					"%s opening body at lane %d is not on closed ground" % [tag, lane])
				if bool(entry.data.get("sp_mark", false)):
					has_mark = true
				if bool(entry.data.get("sp_ward", false)):
					has_ward = true
		var kind: String = String(sp.get("objective", {}).get("kind", ""))
		if kind == "slay_marked":
			_check(has_mark, "%s slay_marked ships a marked body" % tag)
		if kind == "protect":
			_check(has_ward, "%s protect ships a warded body" % tag)
		# A reinforcement deck the engine can actually deal.
		_check(spdb.build_deck(sp_id).size() >= 1, "%s has a reinforcement deck" % tag)
		_check(not spdb.get_reinforcement(sp_id).is_empty(),
			"%s has a backup body" % tag)

	# ── C. TROPHIES ARE UNROLLABLE ───────────────────────────────────────
	print("— C. trophies never enter a roll pool")
	for sp_id in spdb.SET_PIECES:
		var trophy: String = String(spdb.SET_PIECES[sp_id].get("trophy", {}).get("relic", ""))
		if trophy == "":
			continue
		var relic: Dictionary = rdb.get_relic(trophy)
		_check(not relic.is_empty(), "%s trophy `%s` is a real relic" % [sp_id, trophy])
		_check(String(relic.get("tier", "")) == "event",
			"%s trophy `%s` is tier event (unrollable)" % [sp_id, trophy])
		_check(String(relic.get("desc", "")) != "",
			"%s trophy `%s` has player-facing text" % [sp_id, trophy])

	# ── D. MAP PLACEMENT ─────────────────────────────────────────────────
	print("— D. map placement (8 seeds × 3 acts)")
	var total_placed := 0
	for seed_val in [3, 11, 777, 4242, 90210, 20260720, 8675309, 31337]:
		rs.start_new_run("raider", -1, seed_val)
		for act_idx in range(3):
			var placed: Array = []
			var war_rows: Array = []
			var rows_by_index: Dictionary = {}
			for row in rs.map_data[act_idx]:
				for n in row:
					var r: int = int(n.row)
					rows_by_index[r] = int(rows_by_index.get(r, 0)) + 1
					if bool(n.get("war_road", false)):
						war_rows.append(r)
					if String(n.get("setpiece_id", "")) != "":
						placed.append(n)
			var where: String = "seed %d act %d" % [seed_val, act_idx + 1]
			_check(placed.size() <= 1, "%s: at most one named action" % where)
			for n in placed:
				total_placed += 1
				var r: int = int(n.row)
				_check(String(n.type) == "combat",
					"%s: named action is a combat node" % where)
				_check(r in [3, 9, 15],
					"%s: named action on a plain fight row (row %d)" % [where, r])
				_check(not ELITE_ROWS.has(r),
					"%s: named action is not on an elite band" % where)
				_check(r != 0, "%s: named action is not the landing row" % where)
				_check(not war_rows.has(r),
					"%s: named action is not on the war road's row" % where)
				# The routing promise: a row of 2+ can always be walked around.
				_check(int(rows_by_index.get(r, 0)) >= 2,
					"%s: named action row is routable (width %d)" \
						% [where, int(rows_by_index.get(r, 0))])
				_check(String(n.get("mutator_id", "")) == "",
					"%s: named action carries no mutator over its own ground" % where)
				_check(spdb.exists(String(n.setpiece_id)),
					"%s: setpiece_id `%s` resolves" % [where, String(n.setpiece_id)])
				_check(int(spdb.get_set_piece(String(n.setpiece_id)).get("act", 0)) == act_idx + 1,
					"%s: named action belongs to this act" % where)
	_check(total_placed > 0, "named actions actually reach the chart (%d placed)" % total_placed)

	# ── E. WITHDRAWAL IS SURVIVABLE ──────────────────────────────────────
	print("— E. failing a named action never ends a run")
	for sp_id in spdb.SET_PIECES:
		var toll: int = int(spdb.SET_PIECES[sp_id].get("toll", 0))
		_check(toll >= 0, "%s toll is not negative" % sp_id)
		# 30 is the starting hero HP; a toll at or above it would read as a
		# death sentence on the tooltip even though the engine clamps it.
		_check(toll < 30, "%s toll %d is survivable from full HP" % [sp_id, toll])

	print("")
	if _fails == 0:
		print("[setpiece-probe] ALL PASS")
		quit(0)
	else:
		print("[setpiece-probe] %d FAIL" % _fails)
		quit(1)
	return true
