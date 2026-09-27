extends SceneTree
## _probe_upgrade_merge.gd — PASS 4/5 of docs/BUG_SWEEP_METHOD_20260829.md (C2+C9).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_upgrade_merge.gd
##
## THE "+" ALLOW-LIST TRAP, made mechanical.
##
## `RunState._apply_plus_upgrade` folds a `CardDB.UPGRADES` delta onto a card. It
## consumes a FIXED set of keys — explicit `u.has("x")` arms plus one tail
## allow-list — and **anything not in that set is silently dropped**. The resolver
## then falls back to its own default, the forge does nothing, and the "+" card's
## text promises a number the card cannot produce.
##
## This has already shipped once: Counterorders declared `order_bonus` in UPGRADES,
## nothing merged it, and the forged card advertised 9 damage while dealing 6. The
## fix added the key to the list; nothing stops the next one. A card that lies
## about its own numbers is worse than a weak card, and it is invisible to every
## other gate — both halves are individually well-formed, only the WIRING is absent.
##
## So: extract the consumed key set from the merge's own source, and diff every key
## every UPGRADES entry actually declares against it.

const RUNSTATE := "res://scripts/state/RunState.gd"

## Keys that are structural rather than merged values — they steer other arms or
## are consumed by name elsewhere, so their absence from the merge is correct.
const STRUCTURAL_KEYS: Dictionary = {
	"desc": "the description override, applied last by its own arm",
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


## Every key `_apply_plus_upgrade` can actually consume: the `u.has("x")` arms and
## the string literals of the tail allow-list, read from the function's own source
## so the gate cannot drift from the code it guards.
func _consumed_keys() -> Dictionary:
	var f := FileAccess.open(RUNSTATE, FileAccess.READ)
	if f == null:
		return {}
	var lines := f.get_as_text().split("\n")
	f.close()
	var start := -1
	var stop := -1
	for i in lines.size():
		var l: String = lines[i]
		if l.begins_with("func _apply_plus_upgrade"):
			start = i
		elif start >= 0 and l.begins_with("func ") and i > start:
			stop = i
			break
	if start < 0:
		return {}
	if stop < 0:
		stop = lines.size()
	var out := {}
	var has_re := RegEx.create_from_string('u\\.has\\("([a-z_]+)"\\)')
	var lit_re := RegEx.create_from_string('"([a-z_]+)"')
	var in_tail := false
	for i in range(start, stop):
		var l: String = lines[i]
		for m in has_re.search_all(l):
			out[m.get_string(1)] = true
		# The tail allow-list: `for k in [ "a", "b", ... ]:` possibly wrapped.
		if l.contains("for k in ["):
			in_tail = true
		if in_tail:
			for m in lit_re.search_all(l):
				out[m.get_string(1)] = true
			if l.contains("]:"):
				in_tail = false
	return out


func _run() -> void:
	print("[upgrade] PASS 4/5 — the \"+\" merge allow-list\n")
	var CDB := root.get_node_or_null("CardDB")
	if CDB == null:
		print("[upgrade] FATAL: CardDB missing"); _done = true; quit(1); return

	var consumed := _consumed_keys()
	print("[upgrade] merge consumes %d distinct keys" % consumed.size())
	_check(consumed.size() > 20, "the consumed-key set was extracted from the merge")

	# ── Every key any UPGRADES entry declares must be consumable ──────────
	var declared := {}
	var offenders: Array = []
	var entries := 0
	for cid_v in CDB.UPGRADES:
		var cid := String(cid_v)
		var u = CDB.UPGRADES[cid_v]
		if not (u is Dictionary):
			continue
		entries += 1
		for k_v in (u as Dictionary):
			var k := String(k_v)
			declared[k] = true
			if consumed.has(k) or STRUCTURAL_KEYS.has(k):
				continue
			offenders.append("%s declares '%s' — the merge drops it" % [cid, k])
	print("[upgrade] %d UPGRADES entries declaring %d distinct keys"
		% [entries, declared.size()])
	_check(entries > 50, "the probe read a real UPGRADES table")
	_check(offenders.is_empty(),
		"every key declared by an UPGRADES entry is one the merge consumes")
	for o in offenders:
		print("          FAIL %s" % o)

	# ── The reverse: a consumable key no entry uses is dead allow-list ────
	# Not a failure — the list is deliberately permissive ("declaring them here is
	# free for cards that don't") — but a key nothing declares is either a typo or
	# a resolver field whose card was cut, and both are worth seeing.
	var unused: Array = []
	for k in consumed:
		if not declared.has(k):
			unused.append(k)
	unused.sort()
	if unused.is_empty():
		print("  OK    every consumable key is used by at least one entry")
	else:
		print("  NOTE  %d consumable key(s) no UPGRADES entry declares:" % unused.size())
		print("          %s" % str(unused))

	# ── A forged card must actually differ from its base ──────────────────
	# The end-to-end version of the same question: fold the delta for real and
	# check something changed. Catches an entry whose keys are all consumable but
	# whose values are no-ops.
	print("\n[upgrade] --- forged cards must differ from their base ---")
	var RS := root.get_node_or_null("RunState")
	var inert: Array = []
	var folded := 0
	if RS != null:
		for cid_v in CDB.UPGRADES:
			var cid := String(cid_v)
			var base = CDB.get_card_data(cid)
			if base.is_empty():
				continue
			var forged: Dictionary = RS._apply_plus_upgrade(base.duplicate(true))
			folded += 1
			var differs := false
			for k in forged:
				if k == "is_upgraded":
					continue
				if not base.has(k) or base[k] != forged[k]:
					differs = true
					break
			if not differs:
				inert.append(cid)
	print("        folded %d cards" % folded)
	_check(folded > 50, "the fold ran over the table")
	_check(inert.is_empty(), "no forged card is identical to its base %s" % str(inert))

	print("\n[upgrade] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
