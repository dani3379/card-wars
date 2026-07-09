extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"

# Diegetic run-end refrains (Direction C: the player is an effigy the burning
# meadow keeps re-casting). Rotated by total defeat count so the framing shifts
# a little each loop. Hard cap of 3 by design — more reads as content churn, not
# as a refrain the meadow recites.
const DEATH_REFRAINS := [
	"The meadow makes another of you. It always has spares.",
	"You stop here. The road doesn't.",
	"That's one more walk that didn't reach the fire. There will be others.",
]

# ── Chronicle ink palette ──────────────────────────────────────────────
# The run summary is written ON parchment (see ChroniclePage below), so all
# its text uses ink-on-paper colors, not the gilt-on-dark HUD palette. The
# gilt values here would wash out on paper exactly like the card faces'
# keyword gold did (CLAUDE.md: re-inked #7a4f10 on the page).
const INK := GameTheme.PARCHMENT_TEXT                   # body ink  #241810
const INK_DIM := Color(0.36, 0.27, 0.18, 1.0)           # captions / the fallen
const INK_BRONZE := Color(0.42, 0.28, 0.10, 1.0)        # section headers
const INK_GOLD := Color(0.478, 0.310, 0.063, 1.0)       # gold values (#7a4f10)
const INK_RUBRIC := Color(0.56, 0.13, 0.07, 1.0)        # red rubric — what the win changed
const INK_LAUREL := Color(0.22, 0.37, 0.16, 1.0)        # fastest-march laurel line


## The parchment sheet the run's chronicle is written on. Replaces the old
## flat dark summary panel — the run ends as a PAGE in the campaign ledger,
## drawn with the same material kit as the cards (deckled edge, edge toast,
## washes, foxing, a double bronze rule). Subclassing PanelContainer keeps
## the auto-height-from-content layout; the stylebox is empty (margins only)
## and the paper is painted in _draw underneath the children.
## A lost run chars the page: blackened deckle, an ember line still eating
## inward, scorch blotches in the corners.
class ChroniclePage extends PanelContainer:
	var charred := false
	var page_seed := 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	## Deckled perimeter path, seeded — same idiom as the cards' WritLeaf.
	func _sheet_path(inset: float, rng: RandomNumberGenerator) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))
		var step := 26.0
		var amp := 5.0
		# Walk the 4 edges; wobble perpendicular to each.
		var edges := [
			[r.position, Vector2(r.end.x, r.position.y), Vector2(0, 1)],
			[Vector2(r.end.x, r.position.y), r.end, Vector2(-1, 0)],
			[r.end, Vector2(r.position.x, r.end.y), Vector2(0, -1)],
			[Vector2(r.position.x, r.end.y), r.position, Vector2(1, 0)],
		]
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var n: Vector2 = e[2]
			var count := maxi(2, int(a.distance_to(b) / step))
			for i in range(count):
				var t := float(i) / float(count)
				# Corners stay pinned (wobble eases to 0 at each end) so the
				# sheet keeps its rectangular stance.
				var ease_w := sin(t * PI)
				pts.append(a.lerp(b, t) + n * rng.randf_range(-amp, amp) * ease_w)
		return pts

	func _draw() -> void:
		if size.x < 120.0 or size.y < 120.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("chronicle_%d" % page_seed)
		var sheet := _sheet_path(8.0, rng)
		# Cast shadow — the page lies ON the scene, so it throws one.
		for sh in [[Vector2(0, 10), 0.30, 26.0], [Vector2(0, 5), 0.22, 10.0]]:
			var off: Vector2 = sh[0]
			var spts := PackedVector2Array()
			for p in sheet:
				spts.append(p + off)
			draw_colored_polygon(spts, Color(0, 0, 0, sh[1]))
		# The paper. A charred page is smoke-dimmed toward ash.
		var paper := Color(0.855, 0.795, 0.665)
		if charred:
			paper = Color(0.760, 0.690, 0.560)
		draw_colored_polygon(sheet, paper)
		# Interior ageing — broad sepia washes, foxing spots, stray fibers.
		var wash := Color(0.42, 0.30, 0.17)
		for i in range(6):
			var c := Vector2(rng.randf_range(size.x * 0.12, size.x * 0.88),
				rng.randf_range(size.y * 0.15, size.y * 0.85))
			draw_circle(c, rng.randf_range(70.0, 180.0),
				Color(wash.r, wash.g, wash.b, rng.randf_range(0.020, 0.040)))
		for i in range(26):
			var c := Vector2(rng.randf_range(size.x * 0.06, size.x * 0.94),
				rng.randf_range(size.y * 0.06, size.y * 0.94))
			draw_circle(c, rng.randf_range(1.5, 5.5),
				Color(0.45, 0.32, 0.16, rng.randf_range(0.045, 0.11)))
		for i in range(34):
			var c := Vector2(rng.randf_range(size.x * 0.08, size.x * 0.92),
				rng.randf_range(size.y * 0.08, size.y * 0.92))
			var d := Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-3.0, 3.0))
			draw_line(c, c + d, Color(0.40, 0.30, 0.18, 0.06), 1.0, true)
		# Edge treatment along the SAME deckled path, so shading never
		# separates from the silhouette (the WritLeaf rule).
		var loop := sheet.duplicate()
		loop.append(sheet[0])
		if charred:
			# Burnt: wide blackened toast, then the ember line still creeping.
			draw_polyline(loop, Color(0.10, 0.07, 0.05, 0.90), 7.0, true)
			draw_polyline(loop, Color(0.62, 0.25, 0.08, 0.28), 2.6, true)
			for i in range(5):
				var t := rng.randf()
				var idx := int(t * (sheet.size() - 1))
				draw_circle(sheet[idx], rng.randf_range(14.0, 34.0),
					Color(0.08, 0.055, 0.04, rng.randf_range(0.10, 0.22)))
		else:
			draw_polyline(loop, Color(0.47, 0.33, 0.18, 0.50), 4.0, true)
			draw_polyline(loop, Color(0.47, 0.33, 0.18, 0.16), 11.0, true)
		draw_polyline(loop, Color(0.16, 0.11, 0.07, 0.80), 1.4, true)
		# Document furniture: the double bronze rule framing the entry.
		var f := Rect2(Vector2(24, 22), size - Vector2(48, 44))
		draw_rect(f, Color(0.55, 0.40, 0.20, 0.50), false, 1.6, true)
		draw_rect(f.grow(-5.0), Color(0.55, 0.40, 0.20, 0.28), false, 1.0, true)


## A hand-ruled ledger separator: heavier line over a hairline, in bronze
## ink — the same double-rule furniture the cards print between regions.
class RuleSep extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(540, 7)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		draw_line(Vector2(0, 2), Vector2(w, 2), Color(0.45, 0.31, 0.14, 0.55), 1.6, true)
		draw_line(Vector2(w * 0.06, 5), Vector2(w * 0.94, 5),
			Color(0.45, 0.31, 0.14, 0.28), 1.0, true)


func _ready() -> void:
	# Lift the crushed background. Two crushers were stacking: the .tscn's
	# Background.self_modulate (≈0.2 brightness) and the "game_over" mood's
	# heavy vignette. Raise the modulate and soften the vignette/gradient so the
	# painted end-of-run art actually reads behind the summary panel.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.46, 0.42, 0.46, 1.0)
	GameTheme.add_atmosphere(self, "game_over", true, {
		"vignette": 0.40,
		"grad_outer": Color(0.02, 0.01, 0.03, 0.50),
	})
	AudioBank.play_music("victory" if RunState.hero_hp > 0 else "defeat")

	# Apply display font to title
	if GameTheme.font_display:
		$Title.add_theme_font_override("font", GameTheme.font_display)
	if GameTheme.font_body:
		$Subtitle.add_theme_font_override("font", GameTheme.font_body)
		$Stats.add_theme_font_override("font", GameTheme.font_body)

	# Ascension suffix is only meaningful if the player actually ran one.
	var asc_suffix: String = ""
	if RunState.current_ascension > 0:
		asc_suffix = "\nAscension %d" % RunState.current_ascension
	if RunState.hero_hp > 0:
		$Title.text = "VICTORY"
		var vcol := Color(1.0, 0.84, 0.38)
		$Title.add_theme_color_override("font_color", vcol)
		$Title.add_theme_color_override("font_outline_color", Color(vcol.r, vcol.g, vcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		# A conquest run ends on the throne — and the throne is the eternal
		# cycle (§15.1 #1): winning makes you the next thing worth marching on.
		if RunState.finale_stage == 1:
			$Subtitle.text = "The throne is yours, and everything it owes.\nProvinces claimed: %d%s" % [
				RunState.current_floor, asc_suffix]
		else:
			$Subtitle.text = "The first flame is extinguished.\nProvinces claimed: %d%s" % [
				RunState.current_floor, asc_suffix]
	else:
		$Title.text = "DEFEAT"
		var dcol := Color(1.0, 0.3, 0.3)
		$Title.add_theme_color_override("font_color", dcol)
		$Title.add_theme_color_override("font_outline_color", Color(dcol.r, dcol.g, dcol.b, 0.25))
		$Title.add_theme_constant_override("outline_size", 8)
		# "Killed by X" line surfaces the cause-of-death captured by Combat
		# when the player went to 0 HP. Mid-run quits (no death) leave the
		# string empty, so we only append it when it's actually meaningful.
		var death_line: String = ""
		if RunState.cause_of_death != "":
			death_line = "\nFelled by %s" % RunState.cause_of_death
		# Rotate the loop refrain by defeat count. Modulo keeps the index valid
		# even on a mid-run quit (total_defeats may be 0 → index 0).
		var refrain: String = DEATH_REFRAINS[MetaState.total_defeats % DEATH_REFRAINS.size()]
		$Subtitle.text = "%s\nProvinces reached: %d%s%s" % [
			refrain, RunState.current_floor, asc_suffix, death_line]

	# The lifetime tally used to float here between the subtitle and the
	# summary panel, where the defeat subtitle's third line ("Felled by…")
	# collided with it. It now closes the chronicle page instead — the ledger
	# keeps its own count (see the footnote in _build_run_summary).
	$Stats.visible = false

	_build_run_summary()

	# The .tscn's plain BackBtn is superseded: the exit actions (MARCH AGAIN /
	# BACK TO MENU) are now written at the FOOT of the chronicle page itself —
	# see the foot row in _build_run_summary. Living inside the page means
	# they can never collide with it however tall the deck strip grows, and
	# they read as the document's own closing marks.
	var old_btn: Node = $BackBtn
	old_btn.name = "BackBtn_old"
	old_btn.queue_free()
	GameTheme.make_settings_gear(self)

	_add_seed_chip()
	_animate_intro()


func _add_seed_chip() -> void:
	# The run seed, bottom-left, click-to-copy. Daily marchers and seed-sharers
	# need this number — it existed nowhere in the game until now. Frameless
	# and dim so it reads as a footnote, not a button.
	var chip := Button.new()
	chip.name = "SeedChip"
	chip.text = "Seed %d  ·  click to copy" % RunState.run_seed
	chip.flat = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_theme_font_size_override("font_size", 16)
	chip.add_theme_color_override("font_color", Color(0.62, 0.56, 0.46, 0.85))
	chip.add_theme_color_override("font_hover_color", Color(0.90, 0.82, 0.60))
	if GameTheme.font_body:
		chip.add_theme_font_override("font", GameTheme.font_body)
	chip.anchor_left = 0.0
	chip.anchor_right = 0.0
	chip.anchor_top = 1.0
	chip.anchor_bottom = 1.0
	chip.offset_left = 18
	chip.offset_right = 320
	chip.offset_top = -42
	chip.offset_bottom = -12
	chip.pressed.connect(func():
		DisplayServer.clipboard_set(str(RunState.run_seed))
		chip.text = "Seed %d  ·  copied" % RunState.run_seed)
	add_child(chip)


const CARD_SCENE = preload("res://scenes/card_2d.tscn")

# Thumbnail size for deck cards in the summary. Card2D's intrinsic size is
# 225×300; we display at scale = THUMB_W / 225 ≈ 0.4 to fit a deck of 15-25
# cards in 2 rows without colliding with the BackBtn at y≈800. The slot
# Control claims THUMB_SIZE so HFlowContainer lays them out compactly while
# the Card2D child shrinks via `scale`.
const THUMB_W: float = 82.0
const THUMB_H: float = 109.0
const THUMB_SIZE := Vector2(THUMB_W, THUMB_H)
const THUMB_SCALE: float = THUMB_W / 225.0


func _build_run_summary() -> void:
	# Detailed recap of the run that just ended — stats, mutators, relics,
	# and a thumbnail strip of the final deck. Replaces an earlier text-only
	# summary so the post-mortem matches the AAA polish of the in-combat HUD:
	# gilded relic chips instead of a comma list, deduplicated deck thumbnails
	# (with ×N stack badges) instead of "Deck: 12 cards".
	# The chronicle page — the run written into the campaign ledger. The
	# parchment (and its charred defeat dress) is painted by ChroniclePage;
	# an empty stylebox carries only the writing margins, kept generous so
	# the text never rides the deckled edge.
	var panel := ChroniclePage.new()
	panel.name = "RunSummaryPanel"
	panel.charred = RunState.hero_hp <= 0
	panel.page_seed = RunState.run_seed
	panel.custom_minimum_size = Vector2(1180, 0)
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 60
	s.content_margin_right = 60
	s.content_margin_top = 30
	s.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", s)
	# Top-anchored under the title block. The page must ALWAYS fit the 900px
	# canvas with its foot buttons visible: the deck is a one-row scroll strip
	# and veterans/fallen share a row, so worst-case height stays bounded.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -590
	panel.offset_right = 590
	panel.offset_top = 292
	panel.offset_bottom = 292  # height auto-expands from content
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var head := _make_summary_label("THE CHRONICLE OF THE MARCH", 21, INK_BRONZE)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	# What this win CHANGED — the meta bumps used to happen silently (the
	# player only noticed a new ascension tier next time they opened run
	# setup). Announce them here, at the moment they were earned.
	if RunState.hero_hp > 0:
		if MetaState.last_victory_unlocked_tier > 0:
			var tier: int = MetaState.last_victory_unlocked_tier
			var rule: String = ""
			if tier < RunState.ASCENSION_RULES.size():
				rule = "\n" + RunState.ASCENSION_RULES[tier]
			var unlock := _make_summary_label(
				"ASCENSION %d UNLOCKED%s" % [tier, rule],
				16, INK_RUBRIC)
			unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			unlock.custom_minimum_size = Vector2(560, 0)
			col.add_child(unlock)
		if MetaState.last_victory_was_fastest:
			var fastest := _make_summary_label(
				"Your fastest march yet — %d provinces." % RunState.current_floor,
				14, INK_LAUREL)
			fastest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(fastest)

	# Stats row: floor / fights won / gold, plus the campaign-memory honors
	# (total kills, veterans lost) when the run produced any.
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 28)
	col.add_child(stats_row)
	stats_row.add_child(_stat_chip("Province", str(RunState.current_floor)))
	stats_row.add_child(_stat_chip("Fights Won", str(RunState.fights_won)))
	stats_row.add_child(_stat_chip("Gold", str(RunState.gold), true))
	var total_kills: int = 0
	for uid in RunState.creature_kills:
		total_kills += int(RunState.creature_kills[uid])
	if total_kills > 0:
		stats_row.add_child(_stat_chip("Kills", str(total_kills)))
	if RunState.fallen.size() > 0:
		stats_row.add_child(_stat_chip("Veterans Lost", str(RunState.fallen.size())))

	# Mutators survived — only show the strip if the player actually braved
	# any. Still rendered as text since mutators are conceptual debuffs, not
	# collectible items with art.
	if RunState.mutators_survived.size() > 0:
		_add_separator(col)
		var mhead := _make_summary_label(
			"MUTATORS SURVIVED  (%d)" % RunState.mutators_survived.size(),
			16, INK_BRONZE)
		mhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(mhead)

		var mnames: Array = []
		for mid in RunState.mutators_survived:
			var m = MutatorDB.get_mutator(mid)
			if not m.is_empty():
				mnames.append(String(m.get("name", mid)))
			else:
				mnames.append(mid)
		var mlist := _make_summary_label(", ".join(mnames), 13,
			Color(INK.r, INK.g, INK.b, 0.88))
		mlist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mlist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mlist.custom_minimum_size = Vector2(480, 0)
		col.add_child(mlist)

	# Relics — gilded chips with hover tooltips (name + desc), matching the
	# combat HUD strip. make_relic_chip handles tier-glow + icon/letter
	# fallback for icon-less relics, so this Just Works for every relic.
	if RunState.relics.size() > 0:
		_add_separator(col)
		var rel_head := _make_summary_label("RELICS  (%d)" % RunState.relics.size(),
			16, INK_BRONZE)
		rel_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rel_head)

		var rel_flow := HFlowContainer.new()
		rel_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		rel_flow.add_theme_constant_override("h_separation", 8)
		rel_flow.add_theme_constant_override("v_separation", 8)
		rel_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(rel_flow)
		for rid in RunState.relics:
			rel_flow.add_child(GameTheme.make_relic_chip(rid, 46))

	# Campaign memory (docs/CAMPAIGN_MEMORY.md) — the run closes as history:
	# the named veterans who carried the march, then the Roll of the Fallen.
	_add_campaign_memory_section(col)

	# Deck — deduplicated Card2D thumbnails with ×N stack badges. Uses
	# CardTextureCache to cache the heavy v4 layout into a single TextureRect
	# per card; the panel still shows the live numerals + frame instead of a
	# count text. Async (await) because each uncached card needs ~2 frames to
	# bake; cached cards (typical mid-run case) return instantly.
	if RunState.deck.size() > 0:
		_add_separator(col)
		var deck_head := _make_summary_label(
			"DECK  (%d cards)" % RunState.deck.size(),
			16, INK_BRONZE)
		deck_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(deck_head)

		# One scrolling row, however big the deck — the Reward screen's forge
		# strip idiom. A multi-row flow made a memory-heavy defeat page taller
		# than the canvas, drowning the foot buttons.
		var deck_scroll := ScrollContainer.new()
		deck_scroll.custom_minimum_size = Vector2(0, THUMB_H + 16)
		deck_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		col.add_child(deck_scroll)
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 10)
		deck_row.alignment = BoxContainer.ALIGNMENT_CENTER
		deck_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		deck_scroll.add_child(deck_row)
		# Build deferred so the panel skeleton renders immediately and the
		# fade-in animation can start while bakes are still in flight.
		_populate_deck_strip(deck_row)

	# ── The document's closing marks: the exit actions, inked at the foot ──
	# MARCH AGAIN wears the rubric red (the "do it again" line is the page's
	# one imperative); BACK TO MENU signs off in plain ink. Frameless, per
	# the shell-wide button idiom — the label IS the button.
	_add_separator(col)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 64)
	col.add_child(foot)
	var rematch := GameTheme.make_back_button("MARCH AGAIN", Vector2(240, 46),
		18, INK_RUBRIC)
	rematch.name = "RematchBtn"
	_ink_button(rematch, Color(0.78, 0.16, 0.07))
	rematch.pressed.connect(_march_again)
	foot.add_child(rematch)
	var styled := GameTheme.make_back_button("BACK TO MENU", Vector2(240, 46),
		18, INK_DIM)
	styled.name = "BackBtn"
	_ink_button(styled, INK)
	styled.pressed.connect(_back)
	foot.add_child(styled)

	# The ledger keeps its own count — lifetime tally as the page's footnote.
	var tally := _make_summary_label("Total runs %d  ·  victories %d" % [
		MetaState.total_runs, MetaState.total_victories], 13,
		Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, 0.85))
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tally)


## Re-ink a shell button for parchment: the heavy dark outline that keeps
## labels legible over painted scenes just looks like smudge on paper, and
## the gilt hover washes out — hover instead deepens toward the given ink.
func _ink_button(btn: Button, hover: Color) -> void:
	btn.add_theme_color_override("font_hover_color", hover)
	btn.add_theme_color_override("font_pressed_color", hover)
	btn.add_theme_color_override("font_outline_color", Color(0.90, 0.85, 0.72, 0.55))
	btn.add_theme_constant_override("outline_size", 3)


## Campaign memory: the named veterans (3+ kills) and the last entries of the
## Roll of the Fallen. A veteran's display name is resolved from the live deck
## when it still marches, else from its last recorded fall — a veteran sold or
## transformed away simply drops off the honors list.
func _add_campaign_memory_section(col: VBoxContainer) -> void:
	# ── Named veterans (top 3 by kills, named ones only) ──
	var vets: Array = []
	for uid in RunState.creature_kills:
		var kills: int = int(RunState.creature_kills[uid])
		if kills < RunState.VETERAN_EPITHET_KILLS:
			continue
		var vname := ""
		var di: int = RunState.deck_uids.find(int(uid))
		if di >= 0:
			vname = String(RunState.get_upgraded_card_data(di).get("name", ""))
		else:
			for f in RunState.fallen:
				if int(f.get("uid", -1)) == int(uid):
					vname = String(f.get("name", ""))
		if vname != "":
			vets.append({"name": vname, "kills": kills})
	# Veterans and the fallen share one ledger row — honors on the left page
	# margin, losses on the right — so a memory-heavy defeat can't push the
	# page's foot off the canvas. Either alone takes the full width.
	var vets_box: VBoxContainer = null
	if not vets.is_empty():
		vets.sort_custom(func(a, b): return int(a["kills"]) > int(b["kills"]))
		vets_box = VBoxContainer.new()
		vets_box.add_theme_constant_override("separation", 4)
		var vhead := _make_summary_label("NAMED VETERANS", 16, INK_BRONZE)
		vhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vets_box.add_child(vhead)
		var vlines: Array = []
		for v in vets.slice(0, 3):
			vlines.append("%s — %d kills" % [v["name"], v["kills"]])
		var vlist := _make_summary_label("\n".join(vlines), 13,
			Color(INK.r, INK.g, INK.b, 0.92))
		vlist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vets_box.add_child(vlist)

	var fallen_box: VBoxContainer = null
	if not RunState.fallen.is_empty():
		fallen_box = VBoxContainer.new()
		fallen_box.add_theme_constant_override("separation", 4)
		var fhead := _make_summary_label(
			"THE ROLL OF THE FALLEN  (%d)" % RunState.fallen.size(),
			16, INK_BRONZE)
		fhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallen_box.add_child(fhead)
		var acts := ["I", "II", "III"]
		var flines: Array = []
		var recent: Array = RunState.fallen.slice(maxi(0, RunState.fallen.size() - 4))
		for f in recent:
			var act_n: String = acts[clampi(int(f.get("act", 1)) - 1, 0, 2)]
			flines.append("%s — fell at %s (Act %s)"
				% [String(f.get("name", "?")), String(f.get("enc", "the road")), act_n])
		if RunState.fallen.size() > 4:
			flines.append("…and %d earlier falls" % (RunState.fallen.size() - 4))
		var flist := _make_summary_label("\n".join(flines), 13, INK_DIM)
		flist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		flist.custom_minimum_size = Vector2(430, 0)
		fallen_box.add_child(flist)

	if vets_box != null and fallen_box != null:
		_add_separator(col)
		var mem_row := HBoxContainer.new()
		mem_row.alignment = BoxContainer.ALIGNMENT_CENTER
		mem_row.add_theme_constant_override("separation", 70)
		mem_row.add_child(vets_box)
		mem_row.add_child(fallen_box)
		col.add_child(mem_row)
	elif vets_box != null or fallen_box != null:
		_add_separator(col)
		col.add_child(vets_box if vets_box != null else fallen_box)


func _add_separator(col: VBoxContainer) -> void:
	col.add_child(RuleSep.new())


func _populate_deck_strip(parent: Container) -> void:
	# Aggregate deck entries by visual identity (id + cost + atk + hp + sorted
	# keywords). Two upgraded Goblins stack; an upgraded + un-upgraded Goblin
	# do not. Order by cost ascending so the strip reads left-to-right cheap
	# to expensive — matches Collection's section ordering.
	var groups: Dictionary = {}   # key → {"data": Dictionary, "count": int}
	var order: Array[String] = []
	for i in RunState.deck.size():
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		if data.is_empty():
			continue
		var key: String = CardTextureCache.cache_key(data)
		if not groups.has(key):
			groups[key] = {"data": data, "count": 0}
			order.append(key)
		groups[key]["count"] += 1
	order.sort_custom(func(a, b):
		return int(groups[a]["data"].get("cost", 0)) < int(groups[b]["data"].get("cost", 0)))

	for key in order:
		var entry: Dictionary = groups[key]
		var slot := _make_deck_thumb(entry["data"], int(entry["count"]))
		if not is_inside_tree():
			return  # scene exited mid-bake
		parent.add_child(slot)
		await get_tree().process_frame


func _make_deck_thumb(card_data: Dictionary, count: int) -> Control:
	# Slot Control claims THUMB_SIZE so HFlowContainer reserves the right
	# footprint; the Card2D child renders at full 225×300 logical size but
	# `scale = THUMB_SCALE` shrinks it visually to fit. clip_contents = true
	# prevents the card's drop shadow from bleeding past the slot rect.
	var slot := Control.new()
	slot.custom_minimum_size = THUMB_SIZE
	slot.size = THUMB_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.clip_contents = false  # tooltip popup needs to extend past the slot

	var card = CARD_SCENE.instantiate()
	card.card_data = card_data.duplicate(true)
	card.card_id = card_data.get("id", "")
	# is_on_battlefield → no drag system, no hover lift. live_baked_mode →
	# uses CardTextureCache's baked texture once warm (cheap), falls back to
	# full layout on cold cache. Pre-baked just below.
	card.is_on_battlefield = true
	card.live_baked_mode = true
	card.scale = Vector2(THUMB_SCALE, THUMB_SCALE)
	card.position = Vector2.ZERO
	slot.add_child(card)
	# Bake in background so the first frame the slot exists, the cache is
	# already warm and Card2D's _build_layout picks the fast path. No await
	# here — the live overlay numerals stay correct even on cache miss.
	CardTextureCache.bake(card_data)

	if count > 1:
		slot.add_child(_make_count_badge(count))
	return slot


func _make_count_badge(n: int) -> Label:
	# Gilt-on-dark numeral chip in the bottom-right corner of a deck thumb,
	# inventory-game style. ×4 sticks ~20px in from the slot edges so the
	# badge sits on the card's parchment, not its frame.
	var badge := Label.new()
	badge.text = "×%d" % n
	badge.add_theme_font_size_override("font_size", 16)
	if GameTheme.font_stat:
		badge.add_theme_font_override("font", GameTheme.font_stat)
	badge.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.04, 0.92)
	bg.border_color = GameTheme.GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		bg.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		bg.set(k, 4)
	badge.add_theme_stylebox_override("normal", bg)
	# Anchor a small chip to the bottom-right of THUMB_SIZE.
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -34
	badge.offset_right = -4
	badge.offset_top = -22
	badge.offset_bottom = -4
	return badge


func _stat_chip(label: String, value: String, is_gold: bool = false) -> VBoxContainer:
	# Pair of stacked labels: small dim caption over a large inked value —
	# ledger entries on the chronicle page. Only the Gold tally wears the
	# paper-gold ink, so gold on this page still means currency rather than
	# "every number."
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	var lbl := _make_summary_label(label, 15, INK_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var val_col: Color = INK_GOLD if is_gold else INK
	var val := _make_summary_label(value, 26, val_col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(val)
	return box


func _make_summary_label(text: String, size: int, color: Color) -> Label:
	# On the chronicle page: headers (16+) are set in the display caps, body
	# lines in the cards' book hand (font_card_body) — the same "written on
	# the page" register the card rules text uses.
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if size >= 16 and GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	elif GameTheme.font_card_body:
		lbl.add_theme_font_override("font", GameTheme.font_card_body)
	elif GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _animate_intro() -> void:
	# Title slams in with a back-eased overshoot; subtitle and stats follow.
	# Victory feels celebratory, defeat feels heavy — same beat, different colors
	# (color is already set above).
	# The exit buttons live INSIDE the chronicle page now, so the summary
	# fade carries them — no separate button tweens.
	$Title.pivot_offset = $Title.size * 0.5
	$Title.scale = Vector2(0.7, 0.7)
	$Title.modulate.a = 0.0
	$Subtitle.modulate.a = 0.0
	var summary := get_node_or_null("RunSummaryPanel")
	if summary != null:
		summary.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property($Title, "modulate:a", 1.0, 0.50).set_ease(Tween.EASE_OUT)
	tw.tween_property($Title, "scale", Vector2.ONE, 0.65) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property($Subtitle, "modulate:a", 1.0, 0.40).set_delay(0.45)
	if summary != null:
		tw.tween_property(summary, "modulate:a", 1.0, 0.50).set_delay(0.80)


func _march_again() -> void:
	# Same hero, same ascension, fresh seed. The main menu consumes the
	# request in _ready and restarts straight into the war chest.
	RunState.rematch_request = {
		"hero": RunState.current_hero_id,
		"ascension": RunState.current_ascension,
	}
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	# Esc returns to the main menu (the run is already over).
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)
