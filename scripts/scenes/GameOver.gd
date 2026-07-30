extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"

# Diegetic run-end refrains (Direction C: the player is an effigy the burning
# meadow keeps re-casting). Rotated by total defeat count so the framing shifts
# a little each loop. Hard cap of 3 by design — more reads as content churn, not
# as a refrain the meadow recites.
const DEATH_REFRAINS := [
	"The march ends here. You can begin another.",
	"You stop here, but the war continues.",
	"This march did not reach the final fire. The next one might.",
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


## The parchment sheet the run's chronicle is written on — extracted to
## scripts/ui/painters/ChroniclePage.gd (2026-07-19) so the Credits roll can
## be written on the same paper. Preloaded under its old name (painter
## convention), so ChroniclePage.new() call sites below read unchanged.
const ChroniclePage := preload("res://scripts/ui/painters/ChroniclePage.gd")


## A hand-ruled ledger separator: heavier line over a hairline, in bronze
## ink — the same double-rule furniture the cards print between regions.
## Rules out to the page's full writing width. It used to be pinned to a
## 540px minimum and SHRINK_CENTER'd, which is what made an 1180px sheet
## read as a narrow column with ~380px of blank paper down each side — the
## furniture, not the text, was setting the page's rhythm.
class RuleSep extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(0, 7)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		if w <= 2.0:
			return
		draw_line(Vector2(0, 2), Vector2(w, 2), Color(0.45, 0.31, 0.14, 0.55), 1.6, true)
		draw_line(Vector2(w * 0.06, 5), Vector2(w * 0.94, 5),
			Color(0.45, 0.31, 0.14, 0.28), 1.0, true)


## The box a clerk rules around the action line on a writ: a hairline
## rectangle with heavier brackets at the corners, in rubric ink. Corner
## brackets rather than a solid border on purpose — a filled or fully-ruled
## rectangle is the flat-UI look this shell doesn't use anywhere else.
## Drawn UNDER its parent button's label (added as a child Control, so the
## button's own text still renders on top).
class EndorsementBox extends Control:
	var ink := Color(0.56, 0.13, 0.07, 1.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A Button is not a Container, so it never lays its children out. The
		# anchors below resolve ONCE, against a parent that is still 0×0 when
		# the box is added — which left this drawing nothing at all. Track the
		# button's rect explicitly instead of trusting anchor propagation.
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var p := get_parent() as Control
		if p != null:
			p.resized.connect(_follow_parent)
			_follow_parent.call_deferred()

	func _follow_parent() -> void:
		var p := get_parent() as Control
		if p == null:
			return
		position = Vector2.ZERO
		size = p.size
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		if r.size.x <= 8.0 or r.size.y <= 8.0:
			return
		draw_rect(r, Color(ink.r, ink.g, ink.b, 0.30), false, 1.0, true)
		var arm := minf(r.size.x * 0.18, 22.0)
		var heavy := Color(ink.r, ink.g, ink.b, 0.85)
		for corner in [
			[r.position, Vector2(1, 0), Vector2(0, 1)],
			[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
			[r.end, Vector2(-1, 0), Vector2(0, -1)],
		]:
			var o: Vector2 = corner[0]
			draw_line(o, o + (corner[1] as Vector2) * arm, heavy, 1.8, true)
			draw_line(o, o + (corner[2] as Vector2) * arm, heavy, 1.8, true)


## The tally band — the run's headline numbers ruled into the page as proper
## ledger cells, each claiming an equal share of the writing width with a
## hairline gutter between. (They used to sit in a 28px-separated huddle in
## the middle of the sheet, so the eye read three small numbers floating in
## paper rather than an account.) The gutters are drawn here rather than
## added as child nodes so cell count stays free — kills, veterans lost and
## the ascension cell only appear on some runs.
class TallyBand extends HBoxContainer:
	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN or what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var kids: Array = []
		for c in get_children():
			if c is Control and (c as Control).visible:
				kids.append(c)
		if kids.size() < 2:
			return
		var gap := float(get_theme_constant("separation"))
		for i in range(1, kids.size()):
			var x: float = (kids[i] as Control).position.x - gap * 0.5
			draw_line(Vector2(x, size.y * 0.16), Vector2(x, size.y * 0.84),
				Color(0.45, 0.31, 0.14, 0.32), 1.0, true)


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
	GameTheme.fade_in(self, 0.26)
	if RunState.hero_hp > 0:
		AudioBank.play_music_random(["victory", "victory_boss"])
	else:
		AudioBank.play_music("defeat")
	_spawn_run_end_flourish(RunState.hero_hp > 0)

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
			$Subtitle.text = "You claimed the throne.\nProvinces claimed: %d%s" % [
				RunState.current_floor, asc_suffix]
		else:
			$Subtitle.text = "You extinguished the first flame.\nProvinces claimed: %d%s" % [
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


func _spawn_run_end_flourish(won: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	# A verdict curtain across the page: victory rains gilt embers upward off
	# a wide band; defeat lets grey ash sink. Fully bespoke, so it rides the
	# factory's "base" preset with everything overridden.
	var vp := get_viewport_rect().size
	var ramp: Array = [
		[0.0, Color(1.0, 0.92, 0.52, 0.0)], [0.15, Color(1.0, 0.84, 0.34, 0.88)],
		[0.65, Color(0.95, 0.58, 0.18, 0.42)], [1.0, Color(0.90, 0.38, 0.12, 0.0)],
	] if won else [
		[0.0, Color(0.60, 0.52, 0.48, 0.0)], [0.18, Color(0.42, 0.36, 0.34, 0.46)],
		[0.72, Color(0.20, 0.16, 0.15, 0.26)], [1.0, Color(0.08, 0.06, 0.055, 0.0)],
	]
	Motion.burst(self, Vector2(vp.x * 0.5, vp.y * (0.30 if won else 0.18)), "base", {
		"name": "RunEndFlourish", "z_index": 8,
		"explosiveness": 0.55 if won else 0.28,
		"amount": 58 if won else 36,
		"lifetime": 1.7 if won else 2.2,
		"emission_rect": Vector2(vp.x * 0.36, 12.0 if won else 20.0),
		"direction": Vector2(0, -1 if won else 1),
		"spread": 42.0 if won else 24.0,
		"gravity": Vector2(0, 120.0 if won else 38.0),
		"velocity_min": 60.0 if won else 18.0,
		"velocity_max": 190.0 if won else 54.0,
		"angular_min": -90.0, "angular_max": 90.0,
		"scale_min": 1.5, "scale_max": 3.6 if won else 4.8,
		"ramp": ramp,
	})


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
		GameTheme.claim_pop(chip)
		DisplayServer.clipboard_set(str(RunState.run_seed))
		chip.text = "Seed %d  ·  copied" % RunState.run_seed)
	add_child(chip)
	GameTheme.deal_in(chip, 1.02)
	GameTheme.hover_lift(chip, 1.02)


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

	var head := _make_summary_label("RUN SUMMARY", 21, INK_BRONZE)
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
				"Your fastest run yet — %d provinces." % RunState.current_floor,
				14, INK_LAUREL)
			fastest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(fastest)

	# Stats row: floor / fights won / gold, plus the campaign-memory honors
	# (total kills, veterans lost) when the run produced any.
	var stats_row := TallyBand.new()
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
		_section_head(col, "MUTATORS SURVIVED  (%d)" % RunState.mutators_survived.size())

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

	# Named actions carried — the run's set-piece holds, by name. These are the
	# ground the march CHOSE to take when it could have walked around, so the
	# chronicle names them rather than counting them: "The Sunken Road" is a
	# thing the player remembers doing, in a way that "1 named action" is not.
	if RunState.setpieces_carried.size() > 0:
		_section_head(col, "GROUND CARRIED  (%d)" % RunState.setpieces_carried.size())
		var spnames: Array = []
		for sp_id in RunState.setpieces_carried:
			var sp: Dictionary = SetPieceDB.get_set_piece(String(sp_id))
			spnames.append(String(sp.get("name", sp_id)) if not sp.is_empty() else String(sp_id))
		var splist := _make_summary_label(", ".join(spnames), 13,
			Color(INK.r, INK.g, INK.b, 0.88))
		splist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		splist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		splist.custom_minimum_size = Vector2(480, 0)
		col.add_child(splist)

	# Relics — gilded chips with hover tooltips (name + desc), matching the
	# combat HUD strip. make_relic_chip handles tier-glow + icon/letter
	# fallback for icon-less relics, so this Just Works for every relic.
	if RunState.relics.size() > 0:
		_section_head(col, "RELICS  (%d)" % RunState.relics.size())

		var rel_flow := HFlowContainer.new()
		rel_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		rel_flow.add_theme_constant_override("h_separation", 8)
		rel_flow.add_theme_constant_override("v_separation", 8)
		rel_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(rel_flow)
		# Chip size scales down only as the hoard grows. A 3-relic win used to
		# show three 46px chips adrift under a full-width rule; the trophies of
		# a whole run deserve to be read, and there is paper for it.
		var chip_px: int = 46
		var rc: int = RunState.relics.size()
		if rc <= 6:
			chip_px = 58
		elif rc <= 10:
			chip_px = 52
		for rid in RunState.relics:
			rel_flow.add_child(GameTheme.make_relic_chip(rid, chip_px))

	# Campaign memory (docs/CAMPAIGN_MEMORY.md) — the run closes as history:
	# the named veterans who carried the march, then the Roll of the Fallen.
	_add_campaign_memory_section(col)

	# Deck — deduplicated Card2D thumbnails with ×N stack badges. Uses
	# CardTextureCache to flatten the full writ layout into one TextureRect
	# per card; the panel still shows the live numerals + frame instead of a
	# count text. Async (await) because each uncached card needs ~2 frames to
	# bake; cached cards (typical mid-run case) return instantly.
	if RunState.deck.size() > 0:
		_section_head(col, "THE DECK  (%d cards)" % RunState.deck.size())

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
	#
	# The imperative additionally gets boxed (EndorsementBox): rubric red on
	# bare paper with nothing around it reads as an error message rather than
	# the action the page is asking for, and it had exactly the same weight as
	# the sign-off beside it. The box is the clerk's, not the UI's.
	_add_separator(col)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 64)
	col.add_child(foot)
	var rematch := GameTheme.make_back_button("MARCH AGAIN", Vector2(268, 54),
		20, INK_RUBRIC)
	rematch.name = "RematchBtn"
	_ink_button(rematch, Color(0.78, 0.16, 0.07))
	rematch.pressed.connect(_on_march_again_pressed.bind(rematch))
	foot.add_child(rematch)
	rematch.add_child(EndorsementBox.new())
	GameTheme.hover_lift(rematch, 1.03)
	var styled := GameTheme.make_back_button("BACK TO MENU", Vector2(240, 46),
		18, INK_DIM)
	styled.name = "BackBtn"
	_ink_button(styled, INK)
	styled.pressed.connect(_on_back_pressed.bind(styled))
	foot.add_child(styled)
	GameTheme.hover_lift(styled, 1.03)

	# The ledger keeps its own count — lifetime tally as the page's footnote.
	var tally := _make_summary_label("Total runs %d  ·  victories %d" % [
		MetaState.total_runs, MetaState.total_victories], 13,
		Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, 0.85))
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tally)

	# The chronicle writes itself in: the page settles first, then each
	# section's ink dries top-to-bottom. Without this the run's closing
	# document just popped into existence fully printed.
	if not (UserSettings != null and UserSettings.reduce_motion):
		panel.modulate.a = 0.0
		var ptw := panel.create_tween()
		ptw.tween_property(panel, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
		var line_i := 0
		for child in col.get_children():
			if not (child is Control):
				continue
			var c := child as Control
			c.modulate.a = 0.0
			var tw := c.create_tween()
			tw.tween_interval(0.18 + line_i * 0.07)
			tw.tween_property(c, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
			line_i += 1

	# ...and once the ink is down, the press comes down on it.
	_stamp_closing_seal(panel, RunState.hero_hp > 0)


## Roman numeral, for the seal's march number. Small by construction — the
## campaign ledger counts in the Old King's hand, and "MARCH XXII" reads as a
## record where "March 22" reads as a stat.
func _roman(n: int) -> String:
	if n <= 0:
		return "—"
	if n > 3999:
		return str(n)
	const VALS := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	const SYMS := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX",
		"V", "IV", "I"]
	var out := ""
	var left := n
	for i in VALS.size():
		while left >= VALS[i]:
			out += SYMS[i]
			left -= VALS[i]
	return out


## The seal that closes the dispatch — the chronicle's last mark, and the
## page's one moment of ceremony. The run summary is a document; a document
## ends by being SEALED, so the beat is a stamp coming down on it: the wax
## drops in fast, stops dead, and knocks the page.
##
## Victory seals in crimson wax. A lost march gets cold, near-black wax —
## the same press, no ceremony in it. The seal bears this march's number in
## the ledger, so a run reads as an entry in a campaign rather than a score.
##
## Lives on the SCENE, not the page: PanelContainer stretches every child to
## its content rect, so a seal parented to the page would fight the VBox.
## Positioned against the page's real rect once layout has settled.
func _stamp_closing_seal(panel: Control, won: bool) -> void:
	const SEAL_D := 168.0
	var host := Control.new()
	host.name = "ClosingSeal"
	host.custom_minimum_size = Vector2(SEAL_D, SEAL_D)
	host.size = Vector2(SEAL_D, SEAL_D)
	host.pivot_offset = Vector2(SEAL_D, SEAL_D) * 0.5
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.rotation = -0.085 if won else 0.06   # pressed by hand, never square
	add_child(host)

	var wax = preload("res://scripts/ui/painters/WaxSeal.gd").new()
	wax.wax = Color(0.52, 0.11, 0.09) if won else Color(0.16, 0.14, 0.14)
	wax.seed_text = "chronicle_%d" % RunState.run_seed
	wax.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(wax)

	# Stamped legend, sunk into the wax: the light is top-left everywhere in
	# this kit, so a recess shows its lit wall on the FAR side — a pale ghost
	# offset down-right behind dark glyphs. (A drop shadow on the near side
	# would emboss it instead, and the seal would read as a sticker.)
	var legend := "SEALED" if won else "CLOSED"
	var face := Color(0.90, 0.78, 0.52, 0.92) if won else Color(0.62, 0.58, 0.54, 0.80)
	for pass_i in 2:
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", -2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if pass_i == 0:
			box.position = Vector2(1.5, 1.5)
			box.modulate = Color(1, 1, 1, 0.34)
		var top := _make_summary_label(legend, 19,
			Color(0.05, 0.02, 0.02, 0.85) if pass_i == 0 else face)
		top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(top)
		var num := _make_summary_label(_roman(maxi(MetaState.total_runs, 1)), 30,
			Color(0.05, 0.02, 0.02, 0.85) if pass_i == 0 else face)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(num)
		host.add_child(box)

	# Park it against the page's bottom-right corner, half-overhanging the
	# deckle the way a real seal is pressed at the foot of a sheet. The page
	# auto-heights from content, so wait for a settled rect before measuring.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(host) or not is_instance_valid(panel):
		return
	# Mostly ON the paper, with just enough overhang past the deckle to read as
	# pressed at the corner. It used to hang 81px below the sheet, which walked
	# off the bottom of the screen entirely on the taller defeat page.
	var anchor := panel.position + panel.size - Vector2(SEAL_D * 0.95, SEAL_D * 0.80)
	# ...but never off the screen. Page height varies with what the run
	# produced (the defeat page carries veterans + the Roll of the Fallen on
	# top of everything the victory page shows), so clamp rather than trust
	# any one measured layout.
	var vp := get_viewport_rect().size
	anchor.x = minf(anchor.x, vp.x - SEAL_D - 10.0)
	anchor.y = minf(anchor.y, vp.y - SEAL_D - 10.0)
	host.position = anchor

	if UserSettings != null and UserSettings.reduce_motion:
		return
	# The press: down fast from above the page, stopping dead on contact
	# (EASE_IN — a stamp has no follow-through), then the page takes the knock.
	host.scale = Vector2(2.4, 2.4)
	host.modulate.a = 0.0
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(host, "modulate:a", 1.0, 0.10).set_delay(0.55)
	tw.tween_property(host, "scale", Vector2.ONE, 0.16) \
		.set_delay(0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(func():
		if not is_instance_valid(self):
			return
		GameTheme.shake_impulse(self, 0.26 if won else 0.14)
		AudioBank.play_sfx("upgrade_confirm", 0.02, -2.0, 0.78 if won else 0.62))


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
		if kills < RunState.veteran_epithet_kills():
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


## A section heading ruled INTO the page: the bronze rule runs out to both
## writing margins and breaks around the head, the way a ledger's own hand
## rules a new account. Replaces the old separator-then-centered-label
## stack, which stated the page's width twice and used none of it.
func _section_head(col: VBoxContainer, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := RuleSep.new()
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	var lbl := _make_summary_label(text, 16, INK_BRONZE)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var right := RuleSep.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	col.add_child(row)


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

	# Size the thumbs to the muster: a 5-card starter deck rendered at the
	# many-cards size left a lonely huddle of stamps under a full-width rule,
	# while a 25-card deck still has to fit one scrolling row. Fill the strip's
	# ~1000px of paper when the deck is small, fall back to 82px when it isn't.
	# HARD CEILING, not a preference: the page must fit the 900px canvas with
	# its foot buttons and closing seal visible, and the DEFEAT page is the
	# worst case (it also carries the veterans + Roll of the Fallen block).
	# 150px thumbs pushed both run-end pages clean off the bottom of the
	# screen. 104 is the most the strip can spend and still leave the document
	# closable.
	var span: float = 1000.0
	var thumb_w: float = clampf(span / maxf(float(order.size()), 1.0) - 10.0,
		THUMB_W, 104.0)
	# The scroll viewport was pinned to the 82px thumb's height; a bigger thumb
	# would be clipped by its own container. Grow the row's viewport to match.
	var scroll := parent.get_parent()
	if scroll is Control:
		(scroll as Control).custom_minimum_size = Vector2(0,
			thumb_w * (THUMB_H / THUMB_W) + 16.0)

	for key in order:
		var entry: Dictionary = groups[key]
		var slot := _make_deck_thumb(entry["data"], int(entry["count"]), thumb_w)
		if not is_inside_tree():
			return  # scene exited mid-bake
		parent.add_child(slot)
		await get_tree().process_frame


func _make_deck_thumb(card_data: Dictionary, count: int,
		thumb_w: float = THUMB_W) -> Control:
	# Slot Control claims the thumb footprint so the row reserves the right
	# space; the Card2D child renders at full 225×300 logical size but `scale`
	# shrinks it visually to fit. Width is passed in by the caller, which sizes
	# the whole strip to the deck (see _populate_deck_strip).
	var thumb_h: float = thumb_w * (THUMB_H / THUMB_W)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(thumb_w, thumb_h)
	slot.size = Vector2(thumb_w, thumb_h)
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
	var sc: float = thumb_w / 225.0
	# The muster strip keeps its crisp vector rules text even at ~0.36 scale —
	# small but legible, and hovering a thumb still floats the full card.
	card.scale = Vector2(sc, sc)
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
	# One ledger cell: small dim caption over a big inked figure. Only the Gold
	# tally wears the paper-gold ink, so gold on this page still means currency
	# rather than "every number."
	#
	# The cell EXPANDs so TallyBand can spread the account across the full
	# writing width — and the figure is set at 40pt in the display caps, which
	# is the point of a tally: the numbers are the headline of the page, not a
	# caption under it. (At the old 26pt they were smaller than the section
	# heads announcing them.)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var lbl := _make_summary_label(label.to_upper(), 14, INK_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	var val_col: Color = INK_GOLD if is_gold else INK
	var val := _make_summary_label(value, 40, val_col)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameTheme.font_title_black:
		val.add_theme_font_override("font", GameTheme.font_title_black)
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


func _on_march_again_pressed(btn: Button) -> void:
	if btn != null and is_instance_valid(btn) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(btn)
		await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	_march_again()


func _on_back_pressed(btn: Button) -> void:
	if btn != null and is_instance_valid(btn) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(btn)
		await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	_back()


func _march_again() -> void:
	# Same hero, same ascension, fresh seed. The main menu consumes the
	# request in _ready and restarts straight into the war chest.
	# Carry the muster picks too — a rematch that silently reverted an unlocked
	# alternate relic or deck to the hero's defaults was the old behaviour.
	RunState.rematch_request = {
		"hero": RunState.current_hero_id,
		"ascension": RunState.current_ascension,
		"signature_relic": RunState.current_signature_relic,
		"deck_variant": RunState.current_deck_variant,
		# The banner rides along for the same reason the doctrine does: a rematch
		# never runs THE MUSTER, so without this the declaration silently reverts
		# to the default and the rematch marches under someone else's colours.
		"banner_tribe": RunState.current_banner_tribe,
	}
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	# Esc returns to the main menu (the run is already over).
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)
