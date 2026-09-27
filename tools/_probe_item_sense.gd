extends Node
## _probe_item_sense.gd — do the relics and potions still MEAN what they say?
##
## The economy redesign (Command ramp + fixed draw + cost rescale) moved the
## ground under every item that grants Command, draw, or a cost discount, and
## item TEXT is a promise the player prices decisions by. This reads the shipped
## dictionaries and reports items whose text or effect no longer lines up:
##
##   A. retired relics that skirmish still deals (NET_RELIC_POOL is an explicit
##      allow-list and does NOT consult `retired`, so a relic the campaign pulled
##      is still offered — and its copy still read — by a skirmish player).
##   B. text that names a number the data no longer carries.
##   C. text that still describes the refill-to-N hand the game no longer has.
##   D. potions whose belt slot would be a DEAD BUTTON in combat (`usable_in`
##      map-only), which is the standing trap in _probe_silent_refusal's waivers.
##   E. Command grants measured as a FRACTION of the round they land on — a flat
##      +1 was +33% against a flat 3 forever; under the ramp it is +100% on round
##      1 and +17% at the cap, so "how big is this relic" is now a question with a
##      different answer every round.
##
## REPORT, not a gate: every line wants a human ruling. The COUNT is the signal.
##
## RUNS AS A SCENE, deliberately. As a `--script` probe this file could not work:
## reading `Combat.command_for_round` means load()ing Combat.gd, which drags it
## into the PRE-AUTOLOAD compile where its bare `RunState` / `CardDB` identifiers
## are hard errors — the blind spot parsecheck's own header warns about. A scene
## has the autoloads registered before _ready, so both the singletons and the
## ramp function resolve normally.

var _rows: Array[String] = []


func _ready() -> void:
	var root := get_tree().get_root()
	var RDB = root.get_node_or_null("RelicDB")
	var PDB = root.get_node_or_null("PotionDB")
	var SS = root.get_node_or_null("SkirmishState")
	var CB = load("res://scripts/scenes/Combat.gd")
	if RDB == null or PDB == null:
		printerr("[items] autoloads missing"); get_tree().quit(1); return

	print("[items] === A. retired relics that skirmish still deals ===")
	var net_pool: Array = []
	if SS != null:
		net_pool = SS.NET_RELIC_POOL
	var a := 0
	for rid in net_pool:
		var r: Dictionary = RDB.get_relic(String(rid))
		if bool(r.get("retired", false)):
			a += 1
			print("  RETIRED-IN-POOL  %-22s %s" % [rid, r.get("name", "")])
			print("      desc: %s" % r.get("desc", ""))
	print("  %d found" % a)

	print("\n[items] === B/C. item text vs the economy it describes ===")
	var stale := 0
	for rid in RDB.RELICS:
		var r: Dictionary = RDB.RELICS[rid]
		var d := String(r.get("desc", ""))
		var low := d.to_lower()
		# C: refill language the fixed draw retired.
		if low.contains("refill") or low.contains("up to 5 cards") \
				or low.contains("hand to 5") or low.contains("back up to"):
			stale += 1
			print("  REFILL-LANG      %-22s %s" % [rid, d])
		# B: a desc naming a magnitude the data does not carry.
		var val := int(r.get("value", -999))
		if val > 0:
			var has_val := d.contains(str(val))
			var nums := 0
			for ch in d:
				if ch.is_valid_int():
					nums += 1
			if nums > 0 and not has_val:
				stale += 1
				print("  NUMBER-MISMATCH  %-22s value=%d | %s" % [rid, val, d])
	print("  %d found" % stale)

	print("\n[items] === D. potions that would be a dead button in combat ===")
	var dead := 0
	for pid in PDB.POTIONS:
		var p: Dictionary = PDB.POTIONS[pid]
		var usable := String(p.get("usable_in", "both"))
		if usable == "map":
			dead += 1
			print("  MAP-ONLY         %-22s %s" % [pid, p.get("name", "")])
	print("  %d found (the combat belt does not filter usable_in)" % dead)

	print("\n[items] === E. a Command grant is a different relic every round ===")
	print("  round  base  +1 reads as   +2 reads as")
	for r_i in range(1, 7):
		var base: int = CB.command_for_round(r_i)
		print("  %-6d %-5d %-13s %s" % [
			r_i, base,
			"+%d%%" % int(round(100.0 / float(base))),
			"+%d%%" % int(round(200.0 / float(base)))])
	print("  (a flat 3 made +1 a constant +33%; it is now +100% .. +17%)")

	print("\n[items] DONE — report only; each line wants a ruling")
	get_tree().quit(0)
