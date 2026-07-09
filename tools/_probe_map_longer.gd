extends SceneTree
## Longer-act map probe (2026-07-07). Verifies the 18-row / 7-combat skeleton
## generates cleanly across many seeds: the acceptance loop converges into the
## 24-36 site window, fights land at rows [0,3,9,15], BOTH elite bands (R6,R12)
## yield exactly one General each, the two guaranteed treasures + two musters
## are placed, a shop always exists, rest=R16 / boss=R17, and every route still
## clears the lord gate.
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
	_ck("FIGHT_ROWS == [0,3,9,15]", RS.FIGHT_ROWS == [0, 3, 9, 15], str(RS.FIGHT_ROWS))
	_ck("ELITE_ROWS == [6,12]", RS.ELITE_ROWS == [6, 12], str(RS.ELITE_ROWS))

	var seeds := 60
	var out_of_window := 0
	var min_sites := 999
	var max_sites := 0
	var elite_bad := 0
	var warroad_bad := 0
	var treasure_bad := 0
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
			var fight_row_hits := {0: false, 3: false, 9: false, 15: false}
			for row_nodes in flat:
				for nd in (row_nodes as Array):
					n += 1
					var t := String(nd.type)
					by_type[t] = int(by_type.get(t, 0)) + 1
					max_row = maxi(max_row, int(nd.row))
					if t == "rest":
						rest_rows.append(int(nd.row))
					if t in ["combat", "elite"] and int(nd.row) in [0, 3, 9, 15]:
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
			# row (dodgeable by routing), and at least one elite band is ≥2
			# lanes wide so the mid-road spike can be dodged too.
			var wr_ok := false
			for fr2 in [3, 9, 15]:
				for nd2 in (flat[fr2] as Array):
					if String(nd2.type) == "elite" \
							and (flat[fr2] as Array).size() >= 2:
						wr_ok = true
			var band_wide: bool = (flat[6] as Array).size() >= 2 \
				or (flat[12] as Array).size() >= 2
			if not (wr_ok and band_wide):
				warroad_bad += 1
			# Two guaranteed treasures, two musters, at least one shop
			if int(by_type.get("treasure", 0)) < 2:
				treasure_bad += 1
			if int(by_type.get("recruit", 0)) < 2:
				recruit_bad += 1
			if int(by_type.get("shop", 0)) < 1:
				shop_bad += 1
			# Boss sits at row 17; rest at row 16
			if int(by_type.get("boss", 0)) != 1 or max_row != 17:
				bossrow_bad += 1
			for rr in rest_rows:
				if rr != 16:
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
	_ck("war-road General avoidable + a dodgeable band", warroad_bad == 0,
		"%d bad" % warroad_bad)
	_ck("every act has >=2 treasures", treasure_bad == 0, "%d bad" % treasure_bad)
	_ck("every act has >=2 musters", recruit_bad == 0, "%d bad" % recruit_bad)
	_ck("every act has >=1 shop", shop_bad == 0, "%d bad" % shop_bad)
	_ck("boss at R17 + rest at R16", bossrow_bad == 0, "%d bad" % bossrow_bad)
	_ck("all four fight rows populated", fightrow_bad == 0, "%d bad" % fightrow_bad)
	_ck("every route clears the lord gate", gate_bad == 0, "%d bad" % gate_bad)

	print("[map_longer] site window observed: min=%d max=%d over %d acts"
		% [min_sites, max_sites, total])
	print("[map_longer] done: %d passed, %d failed" % [_pass, _fail])
	_done = true
	quit(0 if _fail == 0 else 1)
