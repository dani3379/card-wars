extends SceneTree
## Icon audit contact sheet: renders every LIVE icon surface at real usage
## sizes so they can be judged visually. Run WINDOWED (editor closed):
##   Godot.exe --path . --script res://tools/_shot_icon_audit.gd
## Saves tools/screenshot/_icon_audit.png

const SHEET_W := 1560
const SHEET_H := 2340

var _frames := 0
var _sheet: Control
var _pending: Array[String] = []
var _keep: Array = []          # hold refs so nothing unloads pre-draw
var _shot_frame := 0


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 1:
		# Collect every texture path the sheet draws. Loading them all in ONE
		# frame poisons the GL upload queue in --script context (they sample
		# white forever) — so queue the paths and load a few per frame.
		for d in ["res://assets/icons/keywords", "res://assets/icons/game-icons",
				"res://assets/icons/map", "res://assets/icons/stats",
				"res://assets/icons/downloaded", "res://assets/icons/potions",
				"res://assets/icons"]:
			var da := DirAccess.open(d)
			if da == null:
				continue
			for fn in da.get_files():
				if fn.ends_with(".png") or fn.ends_with(".svg"):
					_pending.append(d + "/" + fn)
		for rid in IconSheet.RELIC_SAMPLE:
			_pending.append("res://assets/icons/relics/%s.png" % rid)
			_pending.append("res://assets/icons/relics/%s.svg" % rid)
		_pending.append("res://assets/icons/kenney_game-icons/PNG/White/2x/gear.png")
		_pending.append("res://assets/icons/kenney_game-icons/PNG/White/2x/audioOn.png")
		return false
	if not _pending.is_empty():
		for _i in 4:
			if _pending.is_empty():
				break
			var p: String = _pending.pop_back()
			if ResourceLoader.exists(p):
				_keep.append(load(p))
		return false
	if _sheet == null:
		# Main window, not a SubViewport: post-startup loads render white there.
		_sheet = IconSheet.new()
		_sheet.gt = root.get_node("/root/GameTheme")
		_sheet.pdb = root.get_node("/root/PotionDB")
		_sheet.size = Vector2(SHEET_W, SHEET_H)
		root.add_child(_sheet)
		_shot_frame = _frames + 20
		return false
	# Capture in 3 scrolled pages (window is only ~900px tall).
	if _frames == _shot_frame or _frames == _shot_frame + 10 or _frames == _shot_frame + 20:
		var page := (_frames - _shot_frame) / 10 + 1
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://tools/screenshot/_icon_audit_p%d.png" % page)
		print("[shot] saved tools/screenshot/_icon_audit_p%d.png" % page)
		_sheet.position.y -= 780.0
		return false
	if _shot_frame > 0 and _frames >= _shot_frame + 25:
		quit(0)
	return false


class IconSheet extends Control:
	const RELIC_SAMPLE := ["veterans_medal", "iron_buckler", "soul_lantern",
		"worn_spellbook", "ember_censer", "couriers_bag", "coin_purse",
		"scouts_emblem", "ember_crown", "whetstone", "war_horn", "lantern",
		"ice_cream", "sozu", "coffee_dripper", "phoenix_heart",
		"vanguard_banner", "rear_guard_charm", "skull_throne", "snecko_eye",
		"du_vu_doll", "pandoras_box", "mimic_ring", "glass_cannon",
		"bone_pile", "butchers_cleaver", "reapers_scythe", "mana_pearl",
		"frozen_eye", "pen_nib", "champions_belt", "centaur_heart",
		"calling_bell", "happy_flower", "cursed_key", "merchants_license",
		"philosophers_stone", "velvet_choker", "sundial", "ectoplasm",
		"iron_legion", "phalanx_stone", "linked_banner", "diagonal_crest",
		"catapult_crew", "bridge_watcher", "inkpot_of_many", "junk_slot"]
	var gt: Node
	var pdb: Node
	const PARCH := Color(0.85, 0.78, 0.62)
	const DARK := Color(0.105, 0.088, 0.066)
	const GILT := Color(0.91, 0.71, 0.28)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.11, 0.09))
		var f: Font = gt.font_body
		var fd: Font = gt.font_display
		var y := 16.0

		# ── A. Keyword devices ──────────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "A. KEYWORD DEVICES (dark-on-cream 18px / gilt orb 30px / 52px)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var kws := ["armored", "swift", "thorns", "regenerate", "summon",
			"last_stand", "piercing", "sacrifice", "exhaust", "retain",
			"wither", "on_enter", "on_death", "adj_buff",
			"shield", "poison", "guardian", "doom", "rampage", "lifelink",
			"overrun", "formation", "structure", "floop", "ranged"]
		var col_w := 118.0
		var per_row := 13
		for i in kws.size():
			var kw: String = kws[i]
			var cx := 20.0 + float(i % per_row) * col_w
			var cy := y + float(i / per_row) * 158.0
			var tex: Texture2D = load("res://assets/icons/keywords/%s.svg" % kw)
			var wired: bool = gt.get_keyword_icon(kw) != null
			var name_col := Color(0.9, 0.85, 0.75) if wired else Color(0.95, 0.4, 0.3)
			draw_string(f, Vector2(cx, cy + 12), kw + ("" if wired else " (off)"),
				HORIZONTAL_ALIGNMENT_LEFT, col_w - 8, 12, name_col)
			if tex == null:
				continue
			# 18px near-black on cream medallion (hand-card strip)
			draw_circle(Vector2(cx + 14, cy + 34), 13.0, Color(0.96, 0.88, 0.65))
			draw_texture_rect(tex, Rect2(cx + 5, cy + 25, 18, 18), false,
				Color(0.10, 0.05, 0.02))
			# 30px gilt on dark roundel (battlefield token orb)
			draw_circle(Vector2(cx + 52, cy + 34), 17.0, DARK)
			draw_arc(Vector2(cx + 52, cy + 34), 17.0, 0, TAU, 24,
				Color(0.62, 0.50, 0.26), 1.0, true)
			draw_texture_rect(tex, Rect2(cx + 52 - 11, cy + 34 - 11, 22, 22),
				false, GILT)
			# 52px white on dark (tooltip / large read)
			draw_rect(Rect2(cx + 2, cy + 58, 56, 56), Color(0.16, 0.13, 0.10))
			draw_texture_rect(tex, Rect2(cx + 4, cy + 60, 52, 52), false,
				Color(0.94, 0.90, 0.82))
		y += 2.0 * 158.0 + 12.0

		# ── B. Map node medallions ──────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "B. MAP SITE GLYPHS on enamel (30px chip / 56px)  [event/recruit/wayside use procedural glyphs in-game]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var nodes := [
			["combat", "crossed-swords", Color(0.46, 0.16, 0.12)],
			["elite", "horned-skull", Color(0.34, 0.10, 0.10)],
			["rest", "campfire", Color(0.60, 0.31, 0.12)],
			["shop", "shop", Color(0.16, 0.42, 0.27)],
			["event*", "scroll-unfurled", Color(0.42, 0.24, 0.60)],
			["treasure", "coins-pile", Color(0.50, 0.38, 0.11)],
			["recruit*", "flying-flag", Color(0.17, 0.33, 0.50)],
			["wayside*", "horned-helm", Color(0.34, 0.30, 0.22)],
			["boss", "dragon-head", Color(0.35, 0.09, 0.08)],
		]
		for i in nodes.size():
			var cx := 20.0 + float(i) * 168.0
			var tex: Texture2D = load("res://assets/icons/game-icons/%s.svg" % nodes[i][1])
			draw_string(f, Vector2(cx, y + 12), String(nodes[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color(0.9, 0.85, 0.75))
			var face: Color = nodes[i][2]
			# small: real chip scale (r=19 → icon ~30px)
			draw_circle(Vector2(cx + 20, y + 44), 19.0, face)
			if tex:
				var ink := Color(0.97, 0.93, 0.85)
				draw_texture_rect(tex, Rect2(cx + 20 - 15, y + 44 - 15, 30, 30), false, ink)
			# large
			draw_circle(Vector2(cx + 90, y + 44), 30.0, face)
			if tex:
				draw_texture_rect(tex, Rect2(cx + 90 - 28, y + 44 - 28, 56, 56), false,
					Color(0.97, 0.93, 0.85))
		y += 96.0

		# ── C. HUD resource icons ───────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "C. HUD RESOURCE ICONS (40px HUD / 16px inline event-text size)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var huds := [
			["heart_painted", "res://assets/icons/map/hud_heart_painted.png"],
			["gold_painted", "res://assets/icons/map/hud_gold_painted.png"],
			["potion_painted", "res://assets/icons/map/hud_potion_painted.png"],
			["hud_relic", "res://assets/icons/map/hud_relic.png"],
			["hud_deck", "res://assets/icons/map/hud_deck.png"],
			["skull (curse glyph)", "res://assets/icons/skull.png"],
			["heart (legacy)", "res://assets/icons/map/hud_heart.png"],
			["gold (legacy)", "res://assets/icons/map/hud_gold.png"],
			["potion (legacy)", "res://assets/icons/map/hud_potion.png"],
		]
		for i in huds.size():
			var cx := 20.0 + float(i) * 168.0
			var tex: Texture2D = load(String(huds[i][1]))
			draw_string(f, Vector2(cx, y + 12), String(huds[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, 164, 12, Color(0.9, 0.85, 0.75))
			if tex == null:
				continue
			draw_texture_rect(tex, Rect2(cx, y + 20, 40, 40), false)
			# inline-16 on parchment (event rich text)
			draw_rect(Rect2(cx + 52, y + 32, 26, 26), PARCH)
			draw_texture_rect(tex, Rect2(cx + 57, y + 37, 16, 16), false)
		y += 86.0

		# ── D. Card stat icons ──────────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "D. STAT + MISC UI ICONS",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var stats := [
			["cost_runestone", "res://assets/icons/stats/cost_runestone.png"],
			["hp_heart", "res://assets/icons/stats/hp_heart.png"],
			["sword.png (token ATK)", "res://assets/icons/sword.png"],
			["heart.png (token HP)", "res://assets/icons/heart.png"],
			["diamond (bullets)", "res://assets/icons/diamond.png"],
			["fire (menu)", "res://assets/icons/fire.png"],
			["gear (settings)", "res://assets/icons/kenney_game-icons/PNG/White/2x/gear.png"],
			["audioOn (settings)", "res://assets/icons/kenney_game-icons/PNG/White/2x/audioOn.png"],
			["cards1 (shop sell)", "res://assets/icons/downloaded/cards1.png"],
			["potion1 (shop)", "res://assets/icons/downloaded/potion1.png"],
		]
		for i in stats.size():
			var cx := 20.0 + float(i) * 138.0
			var tex: Texture2D = load(String(stats[i][1]))
			draw_string(f, Vector2(cx, y + 12), String(stats[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, 134, 11, Color(0.9, 0.85, 0.75))
			if tex == null:
				continue
			draw_texture_rect(tex, Rect2(cx, y + 20, 44, 44), false)
		y += 86.0

		# ── E. Potion identity (the real combat bar look) ───────────────
		draw_string(fd, Vector2(20, y + 18), "E. POTIONS AS RENDERED (PotionDB.icon_for silhouettes x potion colour, 52px combat slots)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var pids: Array = pdb.all_ids()
		for i in pids.size():
			var pid: String = pids[i]
			var data: Dictionary = pdb.get_potion(pid)
			var cx := 20.0 + float(i % 13) * 118.0
			var cyp := y + float(i / 13) * 92.0
			draw_string(f, Vector2(cx, cyp + 12), String(data.get("name", pid)).left(14),
				HORIZONTAL_ALIGNMENT_LEFT, 114, 11, Color(0.9, 0.85, 0.75))
			draw_rect(Rect2(cx, cyp + 18, 52, 52), Color(0.06, 0.04, 0.03, 0.85))
			var icon: Texture2D = pdb.icon_for(pid)
			if icon:
				draw_texture_rect(icon, Rect2(cx + 6, cyp + 24, 40, 40), false,
					data.get("color", Color.WHITE))
		y += 92.0 * ceilf(float(pids.size()) / 13.0)

		# ── F. Relic icon sample ────────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "F. RELIC ICONS sample (44px on dark, as in HUD relic strip)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var relics := RELIC_SAMPLE
		per_row = 20
		for i in relics.size():
			var rid: String = relics[i]
			var cx := 20.0 + float(i % per_row) * 76.0
			var cy := y + float(i / per_row) * 92.0
			draw_string(f, Vector2(cx - 2, cy + 10), rid.left(10),
				HORIZONTAL_ALIGNMENT_LEFT, 76, 9, Color(0.8, 0.75, 0.65))
			draw_rect(Rect2(cx, cy + 14, 52, 52), Color(0.08, 0.06, 0.05))
			# Mirror RelicDB.get_relic_icon resolution: painted PNG wins, else the
			# SVG silhouette (drawn gilt-tinted here, as make_relic_chip renders it).
			var p := "res://assets/icons/relics/%s.png" % rid
			if ResourceLoader.exists(p):
				var tex: Texture2D = load(p)
				draw_texture_rect(tex, Rect2(cx + 4, cy + 18, 44, 44), false)
			elif ResourceLoader.exists("res://assets/icons/relics/%s.svg" % rid):
				var tex2: Texture2D = load("res://assets/icons/relics/%s.svg" % rid)
				draw_texture_rect(tex2, Rect2(cx + 4, cy + 18, 44, 44), false, GILT)
		y += 92.0 * ceilf(float(relics.size()) / float(per_row)) + 12.0

		# ── G. Combat intent icons ──────────────────────────────────────
		draw_string(fd, Vector2(20, y + 18), "G. COMBAT INTENT / TELEGRAPH ICONS",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GILT)
		y += 34.0
		var intents := [
			["crossed-swords (attack)", "res://assets/icons/game-icons/crossed-swords.svg"],
			["horned-skull (lethal)", "res://assets/icons/game-icons/horned-skull.svg"],
			["flying-flag (reinforce)", "res://assets/icons/game-icons/flying-flag.svg"],
			["scroll-quill", "res://assets/icons/game-icons/scroll-quill.svg"],
			["sands-of-time", "res://assets/icons/game-icons/sands-of-time.svg"],
			["skull-bolt", "res://assets/icons/game-icons/skull-bolt.svg"],
			["cash", "res://assets/icons/game-icons/cash.svg"],
			["coins", "res://assets/icons/game-icons/coins.svg"],
			["rolling-dices", "res://assets/icons/game-icons/rolling-dices.svg"],
			["d20", "res://assets/icons/game-icons/dice-twenty-faces-twenty.svg"],
		]
		for i in intents.size():
			var cx := 20.0 + float(i) * 148.0
			var tex: Texture2D = load(String(intents[i][1]))
			draw_string(f, Vector2(cx, y + 12), String(intents[i][0]),
				HORIZONTAL_ALIGNMENT_LEFT, 144, 11, Color(0.9, 0.85, 0.75))
			if tex == null:
				continue
			draw_rect(Rect2(cx, y + 18, 52, 52), Color(0.16, 0.13, 0.10))
			draw_texture_rect(tex, Rect2(cx + 4, y + 22, 44, 44), false,
				Color(0.94, 0.90, 0.82))
		y += 92.0
