extends SceneTree
## Longer-act map probe (2026-07-07; re-pinned 2026-09-19). Verifies the 18-row
## skeleton generates cleanly across many seeds: the acceptance loop converges
## into the 24-36 site window, the MANDATORY fights land at rows [0,3,15], BOTH
## elite bands (R6,R12) yield exactly one General each AND fill every other lane
## with road so the fight is declinable, one Reliquary + one Arsenal + two
## musters are placed, a shop always exists, rests sit at R9+R16, boss at R17,
## and every route still clears the lord gate.
##
## The row literals it used to carry are now read off RunState's constants. It
## pinned [0,3,9,15] in three separate places, and the 2026-09-19 spine change
## failed all three — correctly, but it is the same duplicate-rule drift this
## codebase keeps paying for, so the spine is named ONCE here now.
## The COUNT and its span are `tools/_probe_fight_count.tscn`, not this file.
##
## Run: Godot_console.exe --headless --path "D:\Godot" --script res://tools/_probe_map_longer.gd

var _started := false
var _done := false
var _pass := 0
var _fail := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("[map_longer]   FAIL  %s   %s" % [label, detail])


func _run() -> void:
	print("[map_longer] start")
	var RS = root.get_node_or_null("RunState")
	if RS == null:
		print("[map_longer] FATAL: RunState missing"); _done = true; quit(1); return

	_ck("MAP_HEIGHT == 18", RS.MAP_HEIGHT == 18, str(RS.MAP_HEIGHT))
	_ck("BOSS_ROW == 17", RS.BOSS_ROW == 17, str(RS.BOSS_ROW))
	_ck("REST_ROW == 16", RS.REST_ROW == 16, str(RS.REST_ROW))
	# 2026-09-19: the mandatory spine dropped row 9, which became MID_REST_ROW.
	_ck("FIGHT_ROWS == [0,3,15]", RS.FIGHT_ROWS == [0, 3, 15], str(RS.FIGHT_ROWS))
	_ck("ELITE_ROWS == [6,12]", RS.ELITE_ROWS == [6, 12], str(RS.ELITE_ROWS))
	_ck("MID_REST_ROW == 9", RS.MID_REST_ROW == 9, str(RS.MID_REST_ROW))
	_ck("the mid camp is not also a fight row",
		not RS.FIGHT_ROWS.has(RS.MID_REST_ROW) and not RS.ELITE_ROWS.has(RS.MID_REST_ROW),
		"row %d" % RS.MID_REST_ROW)

	var seeds := 60
	var out_of_window := 0
	var min_sites := 999
	var max_sites := 0
	var elite_bad := 0
	var band_shape_bad := 0
	var warroad_bad := 0
	var treasure_bad := 0
	var arsenal_bad := 0
	var recruit_bad := 0
	var shop_bad := 0
	var gate_bad := 0
	var fightrow_bad := 0
	var bossrow_bad := 0

	for s in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + s * 31
		for act in [1, 2, 3]:
			var flat: Array = RS._generate_act_map(act, rng)
			# Site count
			var n := 0
			var by_type := {}
			var max_row := 0
			var rest_rows := []
			# Derived from the constant, never restated — a second spelling of
			# the spine is exactly how a probe goes on testing last month's map.
			var fight_row_hits := {}
			for _fr in RS.FIGHT_ROWS:
				fight_row_hits[int(_fr)] = false
			for row_nodes in flat:
				for nd in (row_nodes as Array):
					n += 1
					var t := String(nd.type)
					by_type[t] = int(by_type.get(t, 0)) + 1
					max_row = maxi(max_row, int(nd.row))
					if t == "rest":
						rest_rows.append(int(nd.row))
					if t in ["combat", "elite"] and fight_row_hits.has(int(nd.row)):
						fight_row_hits[int(nd.row)] = true
			min_sites = mini(min_sites, n)
			max_sites = maxi(max_sites, n)
			if n < 24 or n > 36:
				out_of_window += 1
			# Exactly 3 Generals: one per band + the optional war-road spike
			# on a wide plain fight row (2026-07-07 route-variance pass).
			if int(by_type.get("elite", 0)) != 3:
				elite_bad += 1
			# War-road avoidability: the fight-row General sits on a ≥2-lane
			# row (dodgeable by routing), and — tightened 2026-09-19 — EVERY
			# elite band is ≥2 lanes. Was `or`, which was sufficient while a
			# band's non-spike lanes were plain holds (dodging changed WHICH
			# fight, not whether one happened). Now those lanes are road, so a
			# width-1 band is a General that cannot be declined at all.
			var wr_ok := false
			for fr2 in RS.FIGHT_ROWS:
				if int(fr2) == 0:
					continue  # never the landing row
				for nd2 in (flat[int(fr2)] as Array):
					if String(nd2.type) == "elite" \
							and (flat[int(fr2)] as Array).size() >= 2:
						wr_ok = true
			var band_wide: bool = true
			for er in RS.ELITE_ROWS:
				if (flat[int(er)] as Array).size() < 2:
					band_wide = false
			if not (wr_ok and band_wide):
				warroad_bad += 1
			# THE BAND CARRIES EXACTLY ONE SPIKE AND THE REST IS ROAD. This is
			# the property that makes the fight count a decision; without it the
			# span collapses to zero and nothing else here would notice.
			for er2 in RS.ELITE_ROWS:
				var band2: Array = flat[int(er2)] as Array
				var spikes := 0
				var holds := 0
				for nd3 in band2:
					var t3 := String(nd3.type)
					if t3 == "elite":
						spikes += 1
					elif t3 == "combat":
						holds += 1
				if spikes != 1 or holds != 0:
					band_shape_bad += 1
					break
			# Current reward structure: one Reliquary, one Arsenal, two musters.
			if int(by_type.get("treasure", 0)) < 1:
				treasure_bad += 1
			if int(by_type.get("arsenal", 0)) < 1:
				arsenal_bad += 1
			if int(by_type.get("recruit", 0)) < 2:
				recruit_bad += 1
			if int(by_type.get("shop", 0)) < 1:
				shop_bad += 1
			# Boss sits at row 17; rests at row 16 and the mid-act camp.
			if int(by_type.get("boss", 0)) != 1 or max_row != 17:
				bossrow_bad += 1
			for rr in rest_rows:
				if rr != RS.REST_ROW and rr != RS.MID_REST_ROW:
					bossrow_bad += 1
					break
			# All four fight rows populated with a combat/elite
			for fr in fight_row_hits:
				if not fight_row_hits[fr]:
					fightrow_bad += 1
					break
			# Every route clears the gate
			if RS._min_fights_to_rest(flat) < RS.HOLDS_TO_OPEN_LORD:
				gate_bad += 1

	var total := seeds * 3
	_ck("all %d acts land in 24-36 sites" % total, out_of_window == 0,
		"%d out of window (min=%d max=%d)" % [out_of_window, min_sites, max_sites])
	_ck("every act has 3 Generals (2 bands + war road)", elite_bad == 0,
		"%d bad" % elite_bad)
	_ck("war-road General avoidable + EVERY band dodgeable", warroad_bad == 0,
		"%d bad" % warroad_bad)
	_ck("each elite band is one spike + road (no plain holds)", band_shape_bad == 0,
		"%d bad" % band_shape_bad)
	_ck("every act has a Reliquary", treasure_bad == 0, "%d bad" % treasure_bad)
	_ck("every act has an Arsenal", arsenal_bad == 0, "%d bad" % arsenal_bad)
	_ck("every act has >=2 musters", recruit_bad == 0, "%d bad" % recruit_bad)
	_ck("every act has >=1 shop", shop_bad == 0, "%d bad" % shop_bad)
	_ck("boss at R17; rests only at R16+R9", bossrow_bad == 0, "%d bad" % bossrow_bad)
	_ck("every mandatory fight row populated", fightrow_bad == 0, "%d bad" % fightrow_bad)
	_ck("every route clears the lord gate", gate_bad == 0, "%d bad" % gate_bad)

	print("[map_longer] site window observed: min=%d max=%d over %d acts"
		% [min_sites, max_sites, total])
	print("[map_longer] done: %d passed, %d failed" % [_pass, _fail])
	_done = true
	quit(0 if _fail == 0 else 1)
