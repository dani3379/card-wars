extends SceneTree
## _probe_persistence.gd — PASS 7 of docs/BUG_SWEEP_METHOD_20260829.md (class C8).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_persistence.gd
##
## A save that does not restore what it saved, or a seed that does not reproduce.
## This class hides because the WRITE side always looks complete — you only find a
## missing field when the value it carried mattered, which may be one board
## reconcile in a hundred.
##
## Precedent, and the reason this is mechanical rather than a reading pass:
## `CreatureInstance.effect_immune` was "the ONE field of 60 missing from
## to_snapshot / apply_snapshot", so a board reconcile silently cleared it. It was
## found by hand, once. There are 56 fields on that class today and nothing checks
## the other 55.
##
## The method is exhaustive by construction: enumerate the script's OWN properties
## via `get_property_list()`, give every one a value distinguishable from its
## default, round-trip it, and diff. A field added tomorrow is covered the moment
## it is declared — no list to maintain, which is the whole point.

## Fields whose DOMAIN is narrower than their type, so the probe must pick a legal
## value or it measures a clamp rather than a loss. `row` is clamped to [0,1] in
## `apply_snapshot` (front/back), and a naive "default + 17" reported it as lost.
const BOUNDED_FIELDS: Dictionary = {
	"row": 1,          # ROW_BACK — the only other legal row
	"lane": 3,         # LANES_PER_ROW - 1
}

## field -> why it legitimately does not survive a round trip.
const WAIVED_SNAPSHOT: Dictionary = {}
## Fields the REPLICATION snapshot deliberately omits. That snapshot is the wire
## format: it carries what the watching peer must render, not the host's private
## bookkeeping, so a smaller set is correct here.
const WAIVED_REPLICATION: Dictionary = {
	"lane": "position rides the board sync's own lane/row fields",
	"row": "position rides the board sync's own lane/row fields",
	"is_opponent": "ownership is viewer-relative; the sync sends `owner` instead",
	"is_on_battlefield": "implied — only board creatures are replicated",
	"is_token": "carried as the sync's own `token` field",
	"current_hp": "carried as the sync's own `hp` field",
	"current_atk": "carried as the sync's own `atk` field (folded effective_atk)",
	"will_floop": "carried as the sync's own `floop` field",
	"doom_counter": "carried as the sync's own `doom` field, host-authoritative",
	"sealed_pending": "a private commitment — replicating it would leak the order",
	# THE ATK COMPONENTS ARE FOLDED, NOT DROPPED. `_net_sync_board` ships
	# `int(c.effective_atk())` as the snapshot's `atk`, so the watcher receives the
	# TOTAL and holds it in `current_atk` with every component at zero — and its own
	# `effective_atk()` then returns that same total. Replicating the parts as well
	# would double-count them. The client renders; it never recomputes.
	"temp_atk_buff": "folded into the sync's `atk` (effective_atk)",
	"persistent_atk_buff": "folded into the sync's `atk` (effective_atk)",
	"persistent_atk_buff_rounds": "a host-side expiry clock; the client sees only the total",
	"adjacency_atk_buff": "folded into the sync's `atk`; the host refreshes adjacency per sync",
	"relic_atk_buff": "folded into the sync's `atk` (effective_atk)",
}

var _started := false
var _done := false
var _fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Every property declared by the SCRIPT itself (not inherited engine members).
func _script_vars(obj: Object) -> Array:
	var out: Array = []
	for p in obj.get_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p)
	return out


## A value that is definitely not the current one, so "did it survive" is decidable.
func _distinct_value(cur, type_id: int):
	match type_id:
		TYPE_BOOL:
			return not bool(cur)
		TYPE_INT:
			return int(cur) + 17
		TYPE_FLOAT:
			return float(cur) + 3.5
		TYPE_STRING:
			return String(cur) + "_rt"
	return null


func _run() -> void:
	print("[persist] PASS 7 — persistence & determinism\n")

	# ── A. CreatureInstance.to_snapshot / apply_snapshot ──────────────────
	print("[persist] --- A: CreatureInstance save round-trip ---")
	var CI = load("res://scripts/state/CreatureInstance.gd")
	var a = CI.new()
	var props := _script_vars(a)
	var touched: Array = []
	for p in props:
		var nm := String(p.name)
		var v = BOUNDED_FIELDS.get(nm, _distinct_value(a.get(nm), int(p.type)))
		if v == null or v == a.get(nm):
			continue
		a.set(nm, v)
		touched.append(nm)
	print("        %d script fields, %d given a distinct value" % [props.size(), touched.size()])
	var snap: Dictionary = a.to_snapshot()
	var b = CI.new()
	b.apply_snapshot(snap)
	var lost: Array = []
	for nm in touched:
		if b.get(nm) != a.get(nm):
			lost.append("%s (%s -> %s)" % [nm, str(a.get(nm)), str(b.get(nm))])
	var lost_live: Array = []
	for l in lost:
		var f := String(l).split(" ")[0]
		if not WAIVED_SNAPSHOT.has(f):
			lost_live.append(l)
	_check(touched.size() > 30, "the probe actually exercised the field set")
	_check(lost_live.is_empty(),
		"every CreatureInstance field survives to_snapshot → apply_snapshot")
	for l in lost_live:
		print("          LOST %s" % l)

	# ── B. the REPLICATION snapshot (the wire format) ─────────────────────
	print("\n[persist] --- B: CreatureInstance replication round-trip ---")
	var rep: Dictionary = a.to_replication_snapshot()
	var c = CI.new()
	c.apply_snapshot(rep)
	var rlost: Array = []
	for nm in touched:
		if WAIVED_REPLICATION.has(nm):
			continue
		if c.get(nm) != a.get(nm):
			rlost.append("%s (%s -> %s)" % [nm, str(a.get(nm)), str(c.get(nm))])
	print("        %d field(s) waived as deliberately off-wire" % WAIVED_REPLICATION.size())
	_check(rlost.is_empty(),
		"every non-waived field survives to_replication_snapshot → apply_snapshot")
	for l in rlost:
		print("          NOT REPLICATED %s" % l)

	# ── C. determinism: the same seed must build the same run ─────────────
	print("\n[persist] --- C: seed reproduction ---")
	var RS := root.get_node_or_null("RunState")
	if RS == null:
		_check(false, "RunState present")
	else:
		var sig_a := _run_signature(RS, 777001)
		var sig_b := _run_signature(RS, 777001)
		var sig_c := _run_signature(RS, 777002)
		_check(sig_a == sig_b,
			"the same seed reproduces the same run (map + rivals + rewards)")
		if sig_a != sig_b:
			print("          A: %s" % sig_a.substr(0, 160))
			print("          B: %s" % sig_b.substr(0, 160))
		_check(sig_a != sig_c, "a different seed produces a different run")

	print("\n[persist] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)


## A compact fingerprint of everything a seed is supposed to decide.
func _run_signature(RS: Node, seed_val: int) -> String:
	RS.start_new_run("stalwart", 0, seed_val)
	var parts: Array = []
	for act in 3:
		if act > 0:
			RS.advance_act()
		for row in RS.get_current_act_map():
			for nd in row:
				if nd is Dictionary:
					var d: Dictionary = nd
					parts.append("%s/%s/%s" % [
						String(d.get("type", "")), str(d.get("col", -1)),
						String(d.get("encounter_id", ""))])
	parts.append("rivals:" + str(RS.rival_lords))
	# Gold rolls are seeded off run_seed ^ floor, so sample a few deterministically.
	if RS.has_method("roll_gold_reward"):
		for f in 5:
			RS.current_floor = f
			parts.append("gold%d:%d" % [f, int(RS.roll_gold_reward(20))])
	return "|".join(PackedStringArray(parts))
