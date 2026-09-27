extends Node
## _probe_pool_borrow.gd — WHAT ACT IS THIS FIGHT AUTHORED FOR? (2026-09-26)
##
## `EncounterDB.get_kingdom_pool(act, type, faction)` tops a thin faction pool up
## from NEIGHBOURING ACTS, `dist` 1 then 2 — so an act-1 road fight can be an
## act-3 authored lineup. Face HP and per-body stats DO rescale to the target act
## (Combat feeds it as the target to `get_face_hp` / `build_enemy_deck`), but the
## DECK COMPOSITION and the PASSIVE do not.
##
## `get_kingdom_pool`'s own landing-pool header already names this defect — it
## opened runs "on a borrowed act-2 lineup whose passive does not act-scale" — and
## the landing pool fixed it for FIGHT ONE ONLY. Stops 2-7 of an act were never
## covered.
##
## Measured in the pilot corpus: `Where the Old Drake Sleeps` is authored act 3,
## was dealt on ACT 1, and went 0 of 2 at a cost of 30.5 hero HP — against an
## act-1 plain-combat average of 95% and 3.6 HP. See
## docs/PLAYTEST_MEASUREMENT_20260919.md §17.
##
## This is a MEASUREMENT that reports, not a gate that fails: how much a pool
## borrows is a content-coverage fact (8 of 15 faction/act elite slots are empty
## by CLAUDE.md's own count), so a threshold here would fail on the authoring
## backlog rather than on a defect. It calls the REAL function — a reimplementation
## of those thirty lines would be the duplicate-rule pathology this codebase has
## paid for three times.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_pool_borrow.tscn

const TYPES := ["combat", "elite", "boss"]


func _ready() -> void:
	print("=== _probe_pool_borrow ===")
	var factions := _factions()
	print("factions: %s" % str(factions))

	var authored_act: Dictionary = {}
	var authored_pass: Dictionary = {}
	for id in EncounterDB.ENCOUNTERS.keys():
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		authored_act[id] = int(e.get("act", 0))
		authored_pass[id] = String(e.get("passive_id", ""))

	var tot := {"n": 0, "borrowed": 0, "far": 0, "with_passive": 0, "far_passive": 0}
	for type in TYPES:
		print("\n--- %s" % type.to_upper())
		print("  %-14s %-5s %4s %4s %5s   %s" % ["faction", "act", "pool", "brwd", "dist2", "borrowed (authored act / passive)"])
		for faction in factions:
			for act in [1, 2, 3]:
				var pool: Array = EncounterDB.get_kingdom_pool(act, type, faction)
				if pool.is_empty():
					continue
				var borrowed: Array = []
				var far := 0
				for id in pool:
					var aa: int = int(authored_act.get(id, act))
					if aa == act:
						continue
					borrowed.append("%s[a%d%s]" % [
						String(EncounterDB.ENCOUNTERS[id].get("name", id)).substr(0, 20),
						aa,
						(" *" + String(authored_pass[id])) if String(authored_pass[id]) != "" else ""])
					if absi(aa - act) >= 2:
						far += 1
						if String(authored_pass[id]) != "":
							tot["far_passive"] = int(tot["far_passive"]) + 1
					if String(authored_pass[id]) != "":
						tot["with_passive"] = int(tot["with_passive"]) + 1
				tot["n"] = int(tot["n"]) + pool.size()
				tot["borrowed"] = int(tot["borrowed"]) + borrowed.size()
				tot["far"] = int(tot["far"]) + far
				print("  %-14s a%-4d %4d %4d %5d   %s" % [
					faction, act, pool.size(), borrowed.size(), far,
					", ".join(borrowed) if not borrowed.is_empty() else "-"])

	print("\n=== TOTALS over every faction x act x type pool")
	print("  pool entries offered          %d" % int(tot["n"]))
	print("  BORROWED from another act     %d  (%.0f%%)" % [
		int(tot["borrowed"]), 100.0 * float(tot["borrowed"]) / maxf(1.0, float(tot["n"]))])
	print("  ...from TWO acts away         %d" % int(tot["far"]))
	print("  borrowed AND carrying a passive   %d" % int(tot["with_passive"]))
	print("  two acts away AND a passive       %d   <- the shape that cost 30 HP" % int(tot["far_passive"]))
	print("")
	print("  A borrowed lineup rescales its FACE HP and its per-body stats to the")
	print("  target act. Its DECK SHAPE and its PASSIVE do not. So the number above")
	print("  counts fights whose standing rule was written for a different deck")
	print("  than the one that will meet it.")
	_report_travel_limit(authored_act, authored_pass, factions)
	get_tree().quit(0)


## What `EncounterDB.PASSIVE_TRAVEL_LIMIT` actually stops, enumerated through the
## real funnel. Printed rather than asserted: which entries are affected is a
## function of the authoring backlog, so a pinned list would be re-blessed on
## every new encounter and stop meaning anything. The COUNT is the signal.
func _report_travel_limit(authored_act: Dictionary, authored_pass: Dictionary,
		factions: Array[String]) -> void:
	print("\n=== THE TRAVEL LIMIT — which rules do not come along")
	print("  PASSIVE_TRAVEL_LIMIT = %d act(s)" % EncounterDB.PASSIVE_TRAVEL_LIMIT)
	var stopped: Dictionary = {}
	var kept_far := 0
	for type in TYPES:
		for faction in factions:
			for act in [1, 2, 3]:
				for id in EncounterDB.get_kingdom_pool(act, type, faction):
					if String(authored_pass.get(id, "")) == "":
						continue
					var aa: int = int(authored_act.get(id, act))
					if absi(aa - act) < EncounterDB.PASSIVE_TRAVEL_LIMIT:
						continue
					var got := String(EncounterDB.get_passive_for(id, act).get("passive_id", ""))
					if got == "":
						stopped["%s|a%d" % [id, act]] = [
							String(EncounterDB.ENCOUNTERS[id].get("name", id)),
							aa, act, String(authored_pass[id])]
					else:
						# Two acts away and the rule still travels: that is the
						# DOWNWARD direction, which is deliberate — an easy rule on
						# a strong deck harms nothing, and dropping it there would
						# only make a soft fight softer.
						kept_far += 1
	var keys: Array = stopped.keys()
	keys.sort()
	for k in keys:
		var r: Array = stopped[k]
		print("  STOPPED  %-24s authored a%d -> dealt a%d   *%s" % [
			String(r[0]).substr(0, 24), int(r[1]), int(r[2]), String(r[3])])
	# The LADDER families never reach the drop: they step to the rung the target
	# act was written for, so the fight keeps its identity. Enumerated separately
	# because a "stopped" count alone would report this family as untouched.
	var stepped: Dictionary = {}
	for type in TYPES:
		for faction in factions:
			for act in [1, 2, 3]:
				for id in EncounterDB.get_kingdom_pool(act, type, faction):
					var was := String(authored_pass.get(id, ""))
					if was == "":
						continue
					var now := String(EncounterDB.get_passive_for(id, act).get("passive_id", ""))
					if now == "" or now == was:
						continue
					stepped["%s|a%d" % [id, act]] = [
						String(EncounterDB.ENCOUNTERS[id].get("name", id)),
						int(authored_act.get(id, act)), act, was, now]
	var skeys: Array = stepped.keys()
	skeys.sort()
	for k in skeys:
		var r: Array = stepped[k]
		print("  STEPPED  %-24s authored a%d -> dealt a%d   *%s -> *%s" % [
			String(r[0]).substr(0, 24), int(r[1]), int(r[2]), String(r[3]), String(r[4])])
	print("  stepped down a LADDER                %d pool entries" % skeys.size())
	print("  stopped (borrowed UP >= %d acts)      %d pool entries" % [
		EncounterDB.PASSIVE_TRAVEL_LIMIT, keys.size()])
	print("  kept    (borrowed DOWN >= %d acts)    %d  — deliberate, see the funnel" % [
		EncounterDB.PASSIVE_TRAVEL_LIMIT, kept_far])
	if keys.is_empty():
		print("  NOTE: nothing was stopped. Either the limit is wide enough that no")
		print("  authored fight reaches it, or the funnel is not wired — check that")
		print("  Combat reads get_passive_for and not enc.passive_id.")


func _factions() -> Array[String]:
	var seen: Dictionary = {}
	for id in EncounterDB.ENCOUNTERS.keys():
		var f := String((EncounterDB.ENCOUNTERS[id] as Dictionary).get("faction", ""))
		if f != "":
			seen[f] = true
	var out: Array[String] = []
	for f in seen.keys():
		out.append(String(f))
	out.sort()
	return out
