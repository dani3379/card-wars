extends SceneTree
## TEMP measurement: does the cartouche's arms row fit its band for EVERY
## hero x rival-kingdom combination?
##   Godot.exe --headless --path . --script res://tools/_tmp_arms_fit.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var gt: Node = root.get_node_or_null("GameTheme")
	var hero_db: Node = root.get_node_or_null("HeroDB")
	if gt == null or hero_db == null:
		print("missing autoload")
		quit(1)
		return true
	var font: Font = gt.get("font_display")
	var sub_sz := 15
	var order_sz := 15
	var worst := 0.0
	var worst_txt := ""
	var order_probe := "Break 2 more holds to open the keep road  ·  0 / 32 provinces"
	var order_w: float = font.get_string_size(order_probe,
		HORIZONTAL_ALIGNMENT_LEFT, -1, order_sz).x
	print("order row width = %.1f" % order_w)
	for hid in hero_db.HERO_ORDER:
		var lord := String(hero_db.get_hero(hid).get("name", "")).to_upper()
		for fid in hero_db.HERO_ORDER:
			if fid == hid:
				continue
			var realm := String(hero_db.faction_info(
				hero_db.get_faction(fid)).get("name", "")).to_upper()
			var full := lord + "  ·  AGAINST " + realm
			var w: float = font.get_string_size(full,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sub_sz).x
			if w > worst:
				worst = w
				worst_txt = full
	print("widest arms row = %.1f px  ->  %s" % [worst, worst_txt])
	print("band inner budget at cap 560 = %.1f" % (560.0 - 32.0))
	print("needed band width = %.1f" % (worst + 32.0))
	quit(0)
	return true
