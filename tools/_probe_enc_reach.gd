extends Node
## _probe_enc_reach.gd — can every authored encounter actually be DEALT?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_enc_reach.tscn
##
## `_probe_reachability` (C1) is STATIC: it proves an id is DISPATCHED. This asks
## the empirical question one step out — is the encounter ever SELECTED? An
## encounter can be perfectly authored, perfectly handled, and still never appear
## because no (act, type, faction) query the map generator issues reaches it.
##
## That is not hypothetical here: 11 of grasswake's 12 encounters had never been
## fought once across 236 recorded runs, and the cause was upstream (one lord was
## never rolled). This probe asks the narrower question that does not depend on
## who is playing — CAN the pool produce it at all.
##
## Runs as a SCENE, not `--script`: EncounterDB names CardDB.
##
## FAILS on an unreachable encounter (an unambiguous defect — content that exists
## and cannot be met). Everything below that is REPORTED and never failed, on the
## `_probe_pool_borrow` precedent: pool DEPTH is a function of the authoring
## backlog, so a threshold there fails on content rather than on a bug.
##
## MEASURED 2026-09-29, and three of the four results are corrections or
## confirmations of claims that were being carried on older evidence:
##
##   unreachable                0 of 66   — every authored encounter is deliverable
##   combat pool depth          min 4 / max 8 / mean 5.1 over 15 faction x act slots
##   elite pool depth           min 2 / max 5 / mean 2.6
##   out-of-tier pool entries   0
##
## The combat figure independently CONFIRMS the 2026-09-13 reading that cross-act
## borrowing makes repetition a non-problem there. The out-of-tier figure
## CORRECTS a standing worry: no boss kit can be dealt as a General through
## `get_kingdom_pool` — thin elite pools top up from neighbouring acts within the
## elite tier, not from bosses. And the elite figure LOCATES what is actually
## thin: an act has two General bands, so at a min-depth slot a player meets
## essentially the whole faction's elite pool in one act. That is an authoring
## gap (8 of 15 faction x act elite slots have no authored elite), not a bug.
##
## Its own first run reported all ten lord kits as dead content, because a keep is
## not dealt from a pool at all — see the second-delivery-path note below. A
## reachability answer is only ever as good as its model of how content is chosen.

var _done := false


func _ready() -> void:
	var enc = get_node_or_null("/root/EncounterDB")
	if enc == null:
		print("[encreach] FATAL: EncounterDB missing")
		get_tree().quit(1)
		return

	# Every faction the conquest deal can march on, read off the DB rather than
	# restated here — a hardcoded list would go stale the moment one is added and
	# would report its encounters as unreachable.
	var factions := {}
	for eid in enc.ENCOUNTERS:
		var f := String((enc.ENCOUNTERS[eid] as Dictionary).get("faction", ""))
		if f != "":
			factions[f] = true

	var reachable := {}
	var queries := 0
	for act in [1, 2, 3]:
		for kind in ["combat", "elite", "boss"]:
			for fac in factions.keys():
				queries += 1
				for id in enc.get_kingdom_pool(act, kind, String(fac)):
					reachable[String(id)] = true
			# the faction-blind form the generator also uses
			queries += 1
			for id in enc.get_ids_for(act, kind):
				reachable[String(id)] = true

	# THE SECOND DELIVERY PATH, and forgetting it made this probe's first run
	# report all ten lord kits as dead content. A keep is NOT dealt from a pool:
	# `CampaignMapGenerator.boss_encounter_for_act` returns "rival_<lord>"
	# directly for whichever lord holds that act, and `RunState.enter_finale`
	# builds "amalgam_<finale_rival>". Both are correctly absent from
	# `get_ids_for(act, "boss")` — an ordinary boss roll must not be able to deal
	# a lord kit out of tier — which is exactly why a pool-only model cannot see
	# them. Same lesson as C26's denominator: a reachability answer is only as
	# good as its model of how the content is selected.
	var hero_db = get_node_or_null("/root/HeroDB")
	if hero_db != null:
		for lord in hero_db.HERO_ORDER:
			# _select_rivals excludes the lord being PLAYED, and every lord is
			# playable, so across runs every kit can be met.
			for prefix in ["rival_", "amalgam_"]:
				# `prefix` is Variant here (untyped array literal), so `:=` cannot
				# infer and the script fails to COMPILE — which in a scene probe
				# means _ready never runs, nothing calls quit(), and the harness
				# hangs with no diagnostic. Annotate explicitly.
				var kit: String = String(prefix) + String(lord)
				if enc.ENCOUNTERS.has(kit):
					reachable[kit] = true

	print("[encreach] factions=%d queries=%d reachable=%d authored=%d"
		% [factions.size(), queries, reachable.size(), enc.ENCOUNTERS.size()])

	var dead: Array = []
	for eid in enc.ENCOUNTERS:
		if not reachable.has(String(eid)):
			var e: Dictionary = enc.ENCOUNTERS[eid]
			dead.append("%-26s act%s %-6s faction=%-11s %s"
				% [String(eid), str(e.get("act", "?")), String(e.get("type", "?")),
					String(e.get("faction", "(none)")), String(e.get("name", ""))])

	print("\n[encreach] AUTHORED ENCOUNTERS NO POOL QUERY CAN REACH\n")
	if dead.is_empty():
		print("  none — every authored encounter is deliverable by some query")
	else:
		for line in dead:
			print("  " + line)
	print("\n[encreach] unreachable: %d of %d" % [dead.size(), enc.ENCOUNTERS.size()])

	# The other direction: a pool that is THIN enough to substitute out of tier.
	# Reported, never failed — pool depth is a function of the authoring backlog.
	print("\n[encreach] POOL DEPTH per (act, kind, faction) — 1 entry means every")
	print("[encreach] march through that slot fights the same thing\n")
	var thin := 0
	var depths := {"combat": [], "elite": []}
	for act in [1, 2, 3]:
		for kind in ["combat", "elite"]:
			for fac in factions.keys():
				var pool: Array = enc.get_kingdom_pool(act, kind, String(fac))
				(depths[kind] as Array).append(pool.size())
				if pool.size() <= 1:
					thin += 1
					print("  act%d %-6s %-11s -> %d  %s"
						% [act, kind, String(fac), pool.size(), str(pool)])
	for kind in ["combat", "elite"]:
		var d: Array = depths[kind]
		d.sort()
		var tot := 0
		for v in d:
			tot += int(v)
		print("  %-6s over %d slots: min=%d max=%d mean=%.1f"
			% [kind, d.size(), int(d[0]), int(d[d.size() - 1]), float(tot) / d.size()])
	print("\n[encreach] slots with <=1 distinct fight: %d" % thin)

	# OUT-OF-TIER SUBSTITUTION. `get_kingdom_pool` tops a thin faction pool up
	# from neighbours, and CLAUDE.md records the cost: "a short elite pool pulls
	# the faction's BOSSES as stand-ins, which is a boss kit turning up as a road
	# fight." A boss kit is authored to be met ONCE, chosen, at the end of an act
	# — met as a General it is the same unfair-vs-hard confusion, and the player
	# cannot tell it apart from intended content. Reported per tier, because the
	# fix is authoring an elite, not clamping the pool.
	print("\n[encreach] POOL ENTRIES WHOSE AUTHORED TIER IS NOT THE SLOT'S\n")
	var subs := 0
	for act in [1, 2, 3]:
		for kind in ["combat", "elite"]:
			for fac in factions.keys():
				for id in enc.get_kingdom_pool(act, kind, String(fac)):
					var e: Dictionary = enc.ENCOUNTERS.get(String(id), {})
					var authored := String(e.get("type", ""))
					if authored != "" and authored != kind:
						subs += 1
						print("  act%d %-6s %-11s <- %-24s authored as %s"
							% [act, kind, String(fac), String(id), authored])
	print("\n[encreach] out-of-tier pool entries: %d" % subs)
	# Only unreachable content fails the gate; depth and substitution are data.
	var failed: bool = not dead.is_empty()
	print("\n[encreach] %s" % ("PASS" if not failed
		else "FAIL — %d authored encounter(s) no path can deliver" % dead.size()))
	print("[encreach] DONE")
	_done = true
	get_tree().quit(1 if failed else 0)
