extends Control
## GameOver.gd — end of run, win or lose.

const MAIN_MENU = "res://scenes/main_menu.tscn"

# Diegetic run-end refrains (Direction C: the player is an effigy the burning
# meadow keeps re-casting). Rotated by total defeat count so the framing shifts
# a little each loop. Hard cap of 3 by design — more reads as content churn, not
# as a refrain the meadow recites.
const DEATH_REFRAINS := [
	"The run ends here. You can begin another.",
	"You stop here, but the war continues.",
	"This run did not reach the final fire. The next one might.",
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

# Only the first exit intent may commit while its claim animation is playing.
var _exit_committing: bool = false


## The parchment sheet the run's chronicle is written on — extracted to
## scripts/ui/painters/ChroniclePage.gd (2026-07-19) so the Credits roll can
## be written on the same paper. Preloaded under its old name (painter
## convention), so ChroniclePage.new() call sites below read unchanged.
const ChroniclePage := preload("res://scripts/ui/painters/ChroniclePage.gd")

## How much canvas the chronicle page leaves below itself, and the least the
## scrolling body may ever be squeezed to. Both are read by the sizing step at
## the end of `_build_run_summary`, which is what keeps the foot buttons on
## screen no matter how heavy the run was.
const PAGE_BOTTOM_GAP: float = 28.0
const PAGE_MIN_SCROLL: float = 160.0

# One authored result-screen timeline. The page used to be faded by both
# `_animate_intro` and `_build_run_summary`, while the seal ran on a third clock.
# Those clocks could overlap differently on a cold card bake. Keep every beat
# relative to the moment the complete page is ready instead.
const SUMMARY_REVEAL_DELAY: float = 0.34
const SUMMARY_INK_DELAY: float = 0.52
const SUMMARY_INK_STAGGER: float = 0.055
const SUMMARY_SEAL_DELAY: float = 1.08


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
		set_anchors_preset(Control.PRESET_TOP_LEFT)
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
	if RunState.last_run_victorious:
		AudioBank.play_music_random(["victory", "victory_boss"])
	else:
		AudioBank.play_music("defeat")
	_spawn_run_end_flourish(RunState.last_run_victorious)

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
	if RunState.last_run_victorious:
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

	# The .tscn's plain BackBtn is superseded: the exit actions (PLAY AGAIN /
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
	# THREE WAVES, NOT ONE BATCH (2026-09-10).
	#
	# This was a single 58-particle burst: everything spawned together and died
	# together, so the screen went from full to empty in one fade and the run's
	# last beat was over before the page had finished being read. It is the fire
	# family's lesson and the lightning's fourth rule in the same sentence — a
	# thing is REBORN in waves; one batch that dims reads as an effect ending
	# rather than a thing happening.
	#
	# AND THE TWO VERDICTS ARE SHAPED DIFFERENTLY IN TIME, which is the part that
	# was only ever colour and direction before. A victory ARRIVES: the first
	# wave is the loudest and it thins to drifting embers. Ash SETTLES: it starts
	# thin and keeps coming, because what is falling is the run, and it should
	# still be falling when the player looks away.
	var waves: Array = [
		{"t": 0.00, "n": 34, "ex": 0.95, "v": 1.25},
		{"t": 0.42, "n": 22, "ex": 0.55, "v": 1.00},
		{"t": 0.96, "n": 15, "ex": 0.30, "v": 0.82},
	] if won else [
		{"t": 0.00, "n": 13, "ex": 0.35, "v": 0.85},
		{"t": 0.70, "n": 20, "ex": 0.20, "v": 1.00},
		{"t": 1.55, "n": 26, "ex": 0.12, "v": 1.10},
	]
	for w in waves:
		var fire := func() -> void:
			if not is_inside_tree():
				return
			Motion.burst(self,
				Vector2(vp.x * 0.5, vp.y * (0.30 if won else 0.18)), "base", {
					"name": "RunEndFlourish", "z_index": 8,
					"explosiveness": float(w.ex),
					"amount": int(w.n),
					"lifetime": 1.7 if won else 2.2,
					"emission_rect": Vector2(vp.x * 0.36, 12.0 if won else 20.0),
					"direction": Vector2(0, -1 if won else 1),
					"spread": 42.0 if won else 24.0,
					"gravity": Vector2(0, 120.0 if won else 38.0),
					"velocity_min": (60.0 if won else 18.0) * float(w.v),
					"velocity_max": (190.0 if won else 54.0) * float(w.v),
					"angular_min": -90.0, "angular_max": 90.0,
					"scale_min": 1.5, "scale_max": 3.6 if won else 4.8,
					"ramp": ramp,
				})
		if float(w.t) <= 0.001:
			fire.call()
		else:
			get_tree().create_timer(float(w.t)).timeout.connect(fire)


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
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")

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
	# ── THE PAGE FOLLOWS THE CANVAS (2026-09-19, CLASS C32) ──
	# Every number below was authored against the 1600x900 design canvas. UI Scale
	# DIVIDES the logical canvas (60% lays out on 2667x1500), so a fixed 1180/±590
	# pair made the chronicle a shrinking island: `_probe_uiscale` measured
	# game_over covering 87% of the canvas in x at 100% and **72% at 60%**. The
	# player who picks 60% is asking to fit MORE on screen, not to get the same
	# page with a wider margin of background around it.
	#
	# READ BEFORE "FIXING" THIS BACK: ProjectSettings is the AUTHORING REFERENCE
	# here — the static canvas these constants were written against — which is its
	# one honest use. The 2026-09-03 decorative-frame bug was the opposite mistake,
	# reading ProjectSettings as if it were the RUNTIME canvas. Static reference,
	# live target; never the other way round. Exactly a no-op at 100%.
	# One definition of this rule lives in GameTheme.canvas_scale — see its header.
	var _k: Vector2 = GameTheme.canvas_scale(self)
	var _kx: float = _k.x
	var _ky: float = _k.y
	panel.custom_minimum_size = Vector2(1180.0 * _kx, 0)
	# The complete page is revealed by its existing ink-dry tween. Keep partial
	# construction hidden while the lower sections are staged across frames.
	var staged_build := DisplayServer.get_name() != "headless"
	panel.modulate.a = 0.0 if staged_build else 1.0
	panel.visible = not staged_build
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
	panel.offset_left = -590.0 * _kx
	panel.offset_right = 590.0 * _kx
	panel.offset_top = 292.0 * _ky
	panel.offset_bottom = 292.0 * _ky  # height auto-expands from content
	add_child(panel)

	# THE PAGE IS BOUNDED TO THE CANVAS, AND THE FOOT IS NOT PART OF WHAT SCROLLS.
	#
	# The contract two comments above ("must ALWAYS fit the 900px canvas with its
	# foot buttons visible") was a HOPE ABOUT CONTENT SIZE, enforced nowhere: the
	# page is top-anchored at 292 with its height auto-expanding, so a heavy run
	# simply grew past the bottom of the screen and took PLAY AGAIN and BACK TO
	# MENU with it. Measured before this fix, at 292 + content: a lean run's foot
	# landed at y=716, a typical one at 795, a heavy one (38 cards, 12 relics, 3
	# veterans, 9 fallen) at 852-906, and a real defeat at 919-973 — i.e. the two
	# ways off this screen were painted entirely below the canvas. Esc still
	# worked, so it was not a softlock; PLAY AGAIN has no key, so the rematch was
	# unreachable exactly on the longest runs. The deck strip's own one-row scroll
	# was an earlier patch for the same overflow, which is the tell that bounding
	# the CONTENT one section at a time does not hold — a new section undoes it.
	#
	# So the structure enforces it instead: everything that varies goes in a
	# ScrollContainer, the foot block sits BELOW that scroll and outside it, and
	# the scroll is capped at whatever height is left over (see the sizing step at
	# the end of this function). A page that fits is sized to its content exactly
	# as before and shows no scrollbar — the common case is visually unchanged.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# The closing marks live here, always on screen, never scrolled away.
	var foot_col := VBoxContainer.new()
	foot_col.name = "PageFoot"
	foot_col.add_theme_constant_override("separation", 6)
	outer.add_child(foot_col)

	var head := _make_summary_label("RUN SUMMARY", 21, INK_BRONZE)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	if staged_build:
		await RenderingServer.frame_post_draw
		if _exit_committing or not is_instance_valid(panel) \
				or not panel.is_inside_tree():
			return

	# What this win CHANGED — the meta bumps used to happen silently (the
	# player only noticed a new ascension tier next time they opened run
	# setup). Announce them here, at the moment they were earned.
	if RunState.last_run_victorious:
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
	# "Provinces", plural — this cell is a COUNT of how far the run got, and the
	# subtitle six lines above it already says "Provinces reached: %d" off the
	# same number. The singular was the odd one out on its own page (COPY_STYLE
	# §12, one term per concept). The main menu's dossier keeps the SINGULAR
	# "PROVINCE" on purpose: there the run is live and the figure is a position.
	stats_row.add_child(_stat_chip("Provinces", str(RunState.current_floor)))
	stats_row.add_child(_stat_chip("Fights Won", str(RunState.fights_won)))
	stats_row.add_child(_stat_chip("Gold", str(RunState.gold), true))
	var total_kills: int = 0
	for uid in RunState.creature_kills:
		total_kills += int(RunState.creature_kills[uid])
	if total_kills > 0:
		stats_row.add_child(_stat_chip("Kills", str(total_kills)))
	if RunState.fallen.size() > 0:
		stats_row.add_child(_stat_chip("Veterans Lost", str(RunState.fallen.size())))
	if staged_build:
		await RenderingServer.frame_post_draw
		if _exit_committing or not is_instance_valid(panel) \
				or not panel.is_inside_tree():
			return

	# Mutators survived — only show the strip if the player actually braved
	# any. Still rendered as text since mutators are conceptual debuffs, not
	# collectible items with art.
	if RunState.mutators_survived.size() > 0:
		_section_head(col, "BATTLE RULES SURVIVED  (%d)" % RunState.mutators_survived.size())

		var mnames: Array = []
		for mid in RunState.mutators_survived:
			var m = MutatorDB.get_mutator(mid)
			if not m.is_empty():
				mnames.append(String(m.get("name", mid)))
			else:
				mnames.append(mid)
		var mlist := _make_summary_label(", ".join(mnames), 14,
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
		_section_head(col, "SPECIAL BATTLES WON  (%d)" % RunState.setpieces_carried.size())
		var spnames: Array = []
		for sp_id in RunState.setpieces_carried:
			var sp: Dictionary = SetPieceDB.get_set_piece(String(sp_id))
			spnames.append(String(sp.get("name", sp_id)) if not sp.is_empty() else String(sp_id))
		var splist := _make_summary_label(", ".join(spnames), 14,
			Color(INK.r, INK.g, INK.b, 0.88))
		splist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		splist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		splist.custom_minimum_size = Vector2(480, 0)
		col.add_child(splist)
	if staged_build:
		await RenderingServer.frame_post_draw
		if _exit_committing or not is_instance_valid(panel) \
				or not panel.is_inside_tree():
			return

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
	if staged_build:
		await RenderingServer.frame_post_draw
		if _exit_committing or not is_instance_valid(panel) \
				or not panel.is_inside_tree():
			return

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
		# Build deferred so the panel skeleton renders immediately. The producer
		# installs every exact-size back before its first await, so the page may
		# reveal while rich faces bake without showing a growing/recentering strip.
		_populate_deck_strip(deck_row)
	if staged_build:
		await RenderingServer.frame_post_draw
		if _exit_committing or not is_instance_valid(panel) \
				or not panel.is_inside_tree():
			return

	# ── The document's closing marks: the exit actions, inked at the foot ──
	# PLAY AGAIN wears the rubric red (the "do it again" line is the page's
	# one imperative); BACK TO MENU signs off in plain ink. Frameless, per
	# the shell-wide button idiom — the label IS the button.
	#
	# The imperative additionally gets boxed (EndorsementBox): rubric red on
	# bare paper with nothing around it reads as an error message rather than
	# the action the page is asking for, and it had exactly the same weight as
	# the sign-off beside it. The box is the clerk's, not the UI's.
	_add_separator(foot_col)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 64)
	foot_col.add_child(foot)
	var rematch := GameTheme.make_back_button("PLAY AGAIN", Vector2(268, 54),
		20, INK_RUBRIC)
	rematch.name = "RematchBtn"
	# PLAY AGAIN names the action; the tooltip names the OUTCOME, because the
	# button alone cannot say WHICH run you get (COPY_STYLE §12). It is not a
	# replay of the run that just ended — _march_again carries the hero and
	# ascension into run setup and the seed is rolled fresh there.
	rematch.tooltip_text = \
		"Start a new run with the same hero and Ascension."
	_ink_button(rematch, Color(0.78, 0.16, 0.07))
	rematch.pressed.connect(_on_march_again_pressed.bind(rematch))
	foot.add_child(rematch)
	rematch.add_child(EndorsementBox.new())
	GameTheme.hover_lift(rematch, 1.03)
	# 240 → 176. The row centres the two RECTS, but only one of them is drawn:
	# PLAY AGAIN's endorsement box fills its 268 box edge to edge, while this
	# label is 123px of ink centred in a 240px box, reserving ~58px of invisible
	# padding on each side. The pair therefore CENTRED correctly and READ 28.5px
	# left of the page — every other row on this document (RUN SUMMARY, the
	# relics, the deck strip, the tally) lands on 799. 176 still leaves the label
	# a comfortable target, and it stops the row paying for space nothing uses.
	var styled := GameTheme.make_back_button("BACK TO MENU", Vector2(176, 46),
		18, INK_DIM)
	styled.name = "BackBtn"
	# States the EFFECT, and states it truthfully: RunState.end_run calls
	# clear_save(), so the slot this run occupied is already gone. A tooltip
	# implying it could be picked up again would be a lie the menu then tells
	# the player off for believing.
	styled.tooltip_text = "Return to the main menu. This run is over and cannot be resumed."
	_ink_button(styled, INK)
	styled.pressed.connect(_on_back_pressed.bind(styled))
	foot.add_child(styled)
	GameTheme.hover_lift(styled, 1.03)

	# The ledger keeps its own count — lifetime tally as the page's footnote.
	var tally := _make_summary_label("Total runs %d  ·  Wins %d" % [
		MetaState.total_runs, MetaState.total_victories], 13,
		Color(INK_DIM.r, INK_DIM.g, INK_DIM.b, 0.85))
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot_col.add_child(tally)

	# ── CAP THE SCROLL (the step that actually enforces the contract) ──────
	# A first estimate now so the page never renders at zero height, then the real
	# one once the layout exists. See _cap_page_scroll for why a mid-build
	# measurement is not good enough.
	scroll.custom_minimum_size.y = _page_budget(panel, foot_col, s)
	_cap_page_scroll(panel, scroll, col, foot_col, s)

	# The chronicle writes itself in: the page settles first, then each
	# section's ink dries top-to-bottom. Without this the run's closing
	# document just popped into existence fully printed.
	if staged_build:
		panel.visible = true
	var snap_intro := not staged_build \
		or (UserSettings != null and UserSettings.reduce_motion)
	var closing_seal_delay := SUMMARY_SEAL_DELAY
	if snap_intro:
		panel.modulate.a = 1.0
	else:
		panel.modulate.a = 0.0
		var ptw := panel.create_tween()
		ptw.tween_interval(SUMMARY_REVEAL_DELAY)
		ptw.tween_property(panel, "modulate:a", 1.0, 0.30).set_ease(Tween.EASE_OUT)
		var line_i := 0
		# The foot block lives outside `col` now (it must not scroll away), so it
		# is dried in explicitly — otherwise the page's closing marks would be the
		# one part that never faded in.
		for child in col.get_children() + foot_col.get_children():
			if not (child is Control):
				continue
			var c := child as Control
			c.modulate.a = 0.0
			var tw := c.create_tween()
			tw.tween_interval(SUMMARY_INK_DELAY + line_i * SUMMARY_INK_STAGGER)
			tw.tween_property(c, "modulate:a", 1.0, 0.24).set_ease(Tween.EASE_OUT)
			line_i += 1
		# Press only after the last authored line has finished drying. Derive this
		# from the actual page: heavy chronicles have more sections than lean ones.
		closing_seal_delay = SUMMARY_INK_DELAY \
			+ maxf(float(line_i - 1), 0.0) * SUMMARY_INK_STAGGER + 0.32

	# ...and once the ink is down, the press comes down on it.
	_stamp_closing_seal(panel, RunState.last_run_victorious, closing_seal_delay)


## What the canvas has left for the scrolling body, once the page's top offset,
## its writing margins, the foot block and a bottom breathing gap are paid for.
## Read from the LIVE viewport, never a 1600x900 constant: UI Scale 60-100% sets
## `content_scale_factor`, which DIVIDES the logical canvas, so a hardcoded 900 is
## wrong at four of the five settings the player is offered (class C32).
func _page_budget(panel: Control, foot_col: Control, s: StyleBox) -> float:
	var canvas_h: float = get_viewport_rect().size.y
	var foot_h: float = foot_col.get_combined_minimum_size().y
	var budget: float = canvas_h - panel.offset_top - PAGE_BOTTOM_GAP \
		- float(s.content_margin_top) - float(s.content_margin_bottom) - foot_h
	# A floor as well as a cap: if a future header block pushes offset_top far
	# enough down that the budget goes negative, an unclamped value would collapse
	# the page to nothing — a worse bug than the one this fixes.
	return maxf(budget, PAGE_MIN_SCROLL)


## Size the scrolling body to its content, capped at what the canvas allows.
##
## THE MEASUREMENT HAS TO HAPPEN AFTER A LAYOUT PASS, and the first cut of this
## did not: a mid-build `get_combined_minimum_size()` under-reported the column by
## ~58px, because an autowrapped Label cannot know its height until it knows its
## wrap WIDTH, and the deck strip is populated deferred so its thumbnails are not
## in the tree yet. Sizing from that number left a scrollbar on EVERY page —
## including the short ones that fit perfectly well — which is a visual regression
## in the common case in exchange for fixing the rare one.
##
## So it settles instead of guessing: re-measure each frame and stop once the
## reading HOLDS, which is the same discipline the pixel gates use and for the
## same reason — a number sampled off a screen that is still assembling is the
## machine's timing, not the layout's.
func _cap_page_scroll(panel: Control, scroll: ScrollContainer, col: Control,
		foot_col: Control, s: StyleBox) -> void:
	var last := -1.0
	for i in 16:
		await get_tree().process_frame
		if not is_instance_valid(scroll) or not is_instance_valid(col) \
				or not is_instance_valid(panel) or not scroll.is_inside_tree():
			return
		var want: float = col.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = minf(want, _page_budget(panel, foot_col, s))
		if absf(want - last) < 0.5:
			return
		last = want


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
func _stamp_closing_seal(panel: Control, won: bool,
		reveal_delay: float = SUMMARY_SEAL_DELAY) -> void:
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

	# HEADLESS LEAVES THE SEAL SETTLED, and this gate is load-bearing rather than
	# tidiness. Returning here is exactly right for a probe: the host is already
	# parked, at scale 1 and full alpha, which is the state a layout gate should
	# measure — the animation is the only thing skipped.
	#
	# Without it, `_probe_alignment` ran the whole press in a headless run and the
	# contact beat built nodes and tweens (the dent, the spatter host, the foil
	# rect) that outlived the probe's teardown of the scene. It crashed with no
	# error and at a DIFFERENT screen each run, which is the signature of a
	# lifetime fault rather than a bad screen, and it is the same class the gate
	# runner's own comment documents. `_spawn_run_end_flourish` already gated
	# headless; this sibling never did, and nothing needed it until the contact
	# beat gave it something to leak.
	if DisplayServer.get_name() == "headless":
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	# THE SEAL IS MOLTEN WAX, NOT A NODE THAT SCALES (2026-09-10).
	#
	# The press was already the right shape — down fast, EASE_IN so it stops dead
	# because a stamp has no follow-through — and it was still a transform tween
	# with nothing happening inside it. Graded against the lightning it had the
	# form and the snap and was missing everything the MATERIAL does, which for
	# wax is very specific and none of it was modelled:
	#
	#   · IT SQUEEZES OUT. Wax under a matrix flows sideways, so the seal is
	#     briefly WIDER than its rest size and settles back as the flow stops.
	#     That overshoot is the material, not a bounce — a bounce would return
	#     symmetrically and this must not, so the settle is slow and one-way.
	#   · THE PAPER TAKES IT. A screen shake says the DESK was hit; it says
	#     nothing about the sheet. The bolt's rule 9 — an effect that arrives
	#     with no mark where it LANDS reads as having passed through.
	#   · IT COOLS. Hot wax is glossy and dulls as it sets, which is the same
	#     "setting" aliveness the road ink got, on a much shorter clock.
	#
	# NO FADE-IN. It used to ramp alpha 0 → 1 over the descent, which is the
	# defect that cost the lightning its first two rebuilds: there was no instant
	# at which the thing was ever at full strength. A stamp is a physical object
	# approaching the page — it is opaque the whole way down.
	host.scale = Vector2(2.4, 2.4)
	host.modulate.a = 0.0
	var wax_col: Color = Color(0.62, 0.14, 0.10) if won else Color(0.26, 0.23, 0.22)
	var tw := host.create_tween()
	tw.tween_interval(reveal_delay)
	tw.tween_property(host, "modulate:a", 1.0, 0.01)
	# The descent. Stops dead.
	tw.tween_property(host, "scale", Vector2(1.06, 1.02), 0.16) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): _seal_contact(host, panel, wax_col, won))
	# The squeeze settling back. Slow and one-way — wax does not spring.
	tw.tween_property(host, "scale", Vector2.ONE, 0.30) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## The moment the matrix meets the page. Everything here is the impact kit the
## forge and the writ already speak, so the run's closing beat is in the same
## grammar as every other permanent mark the game makes on a card.
func _seal_contact(host: Control, panel: Control, wax_col: Color,
		won: bool) -> void:
	if not is_instance_valid(self) or not is_instance_valid(host):
		return
	GameTheme.shake_impulse(self, 0.26 if won else 0.14)
	AudioBank.play_sfx("upgrade_confirm", 0.02, -2.0, 0.78 if won else 0.62)
	# WARM AND LOW, not the kit's white-hot default. A forge strike is metal being
	# hit and wants the over-exposure; wax is warm, dull and soft, and at 0.55
	# white the seal photographed pale pink at the one instant it should read as
	# a deep red mass landing.
	Motion.impact_frame(self, host, Vector2(1.06, 1.02),
		Color(1.0, 0.88, 0.74, 0.30))
	var centre: Vector2 = host.global_position + host.size * host.scale * 0.5
	# THE BEAD OF WAX PUSHED OUT PAST THE MATRIX. Rings in the wax's own colour
	# rather than the kit's white, because this is displaced material and not a
	# flash — it should look like it came OUT of the seal.
	Motion.shock_rings(self, centre, wax_col, 1.35)
	# Spatter: a few droplets thrown clear. Wax, so they are heavy and they fall.
	Motion.burst(self, centre, "base", {
		"texture": "ink", "z_index": 9,
		"explosiveness": 1.0, "amount": 9, "lifetime": 0.5,
		"direction": Vector2(0, 0), "spread": 180.0,
		"gravity": Vector2(0, 340.0),
		"velocity_min": 40.0, "velocity_max": 170.0,
		"scale_min": 1.0, "scale_max": 2.6,
		"color": Color(wax_col.r, wax_col.g, wax_col.b, 0.90),
	})
	# IT COOLS. The specular crosses the wax once and is gone — the whole read is
	# that it was liquid a moment ago and is not any more.
	Motion.foil_sweep(self, host, Color(1.0, 0.90, 0.72), 0.46)
	_dent_the_page(host, panel, centre)


## The impression. A wax seal pressed at the foot of a sheet leaves the paper
## dished around it, and that mark does not fade — it is the last permanent thing
## the run does. Drawn UNDER the seal and left there.
func _dent_the_page(host: Control, panel: Control, centre: Vector2) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(host):
		return
	var dent := TextureRect.new()
	dent.name = "SealDent"
	dent.texture = Motion.particle_tex("ink")
	dent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dent.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var d: float = host.size.x * 1.55
	dent.size = Vector2(d, d * 0.88)
	dent.global_position = centre - dent.size * 0.5
	# Behind the seal but above the page. `show_behind_parent` is the same tool
	# the map's ink layer uses to sit under its parent's own drawing.
	dent.z_index = -1
	dent.modulate = Color(0.10, 0.06, 0.04, 0.0)
	add_child(dent)
	move_child(dent, maxi(host.get_index() - 1, 0))
	# It arrives WITH the blow, not after it: the paper is dished at the instant
	# of contact, so this is a fast fade-up to a held value and then nothing.
	var dt := dent.create_tween()
	dt.tween_property(dent, "modulate:a", 0.30, 0.09) \
		.set_ease(Tween.EASE_OUT)


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
		var vlist := _make_summary_label("\n".join(vlines), 14,
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
		var flist := _make_summary_label("\n".join(flines), 14, INK_DIM)
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

	# The complete strip exists before the first asynchronous bake. Small face-down
	# writs are honest loading content for a deckbuilder and, more importantly,
	# reserve every final pixel so no completed card can shove an earlier one.
	var slots: Array[Control] = []
	var backs: Array[Control] = []
	for _key in order:
		var stage := _make_deck_thumb_stage(thumb_w, parent)
		var slot: Control = stage["slot"]
		var back: Control = stage["back"]
		parent.add_child(slot)
		slots.append(slot)
		backs.append(back)
	# Let the HBox sort its final footprint once. Everything after this point is
	# mounted inside those fixed Controls and cannot alter the row's geometry.
	await get_tree().process_frame

	# Batch cold identities before constructing any visible Card2D. A late-run
	# upgrade or never-drawn card must not leave its full ornate fallback alive
	# on the post-mortem after the cache finishes behind it.
	var unique_datas: Array = []
	for key in order:
		unique_datas.append(groups[key]["data"])
	var still_here := func() -> bool:
		return is_inside_tree() and is_instance_valid(parent) \
			and parent.is_inside_tree()
	await CardTextureCache.bake_many(unique_datas, still_here)
	if not still_here.call():
		return

	var faces: Array[Control] = []
	for i in order.size():
		var key: String = order[i]
		var entry: Dictionary = groups[key]
		var face := _hydrate_deck_thumb(slots[i], entry["data"],
			int(entry["count"]), thumb_w)
		faces.append(face)
		# Keep the old one-tree-per-frame construction budget, but hide the order
		# behind the already-complete set of backs.
		await get_tree().process_frame
		if not still_here.call():
			return

	# One final deck, one turn. Every back closes in the same frame and every full
	# ornate face opens from that shared edge. Reduced motion snaps the same set.
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	for face in faces:
		if is_instance_valid(face):
			face.modulate.a = 1.0
	if snap:
		for back in backs:
			if is_instance_valid(back):
				back.queue_free()
	else:
		for i in faces.size():
			if is_instance_valid(backs[i]) and is_instance_valid(faces[i]):
				Motion.flip_out(backs[i], 0.13)
				Motion.flip_in(faces[i], Motion.time(0.13), 0.17)


func _make_deck_thumb_stage(thumb_w: float = THUMB_W,
		group: CanvasItem = null) -> Dictionary:
	var thumb_h: float = thumb_w * (THUMB_H / THUMB_W)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(thumb_w, thumb_h)
	slot.size = Vector2(thumb_w, thumb_h)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.clip_contents = false  # tooltip popup needs to extend past the slot
	var back := TextureRect.new()
	back.texture = CARD_BACK_TEXTURE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, group)
	slot.add_child(back)
	return {"slot": slot, "back": back}


func _hydrate_deck_thumb(slot: Control, card_data: Dictionary, count: int,
		thumb_w: float = THUMB_W) -> Control:
	# Card and count badge share one face layer so they turn over as a single writ.
	# The layer fills the already-reserved slot and never participates in HBox size.
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_PASS
	face.modulate.a = 0.0
	slot.add_child(face)
	var card = CARD_SCENE.instantiate()
	card.card_data = card_data.duplicate(true)
	card.card_id = card_data.get("id", "")
	# is_on_battlefield → no drag system, no hover lift. live_baked_mode →
	# uses the texture pre-baked by _populate_deck_strip above, so the card
	# always takes the compact path when it enters the live tree.
	card.is_on_battlefield = true
	card.live_baked_mode = true
	var sc: float = thumb_w / 225.0
	# A THUMB IS A PICTURE, AND THE RULES LIVE ON THE HOVER.
	#
	# This used to claim the muster strip proved ~0.36 scale stayed legible and
	# that "hovering a thumb still floats the full card". Both halves were false.
	# The muster strip was REPLACED on 2026-09-14 precisely because scaling a
	# Card2D node renders its rules text below the floor — Card2D holds rules at
	# an ABSOLUTE 18px (`_fit_desc_to_box` would rather clip the card than shrink
	# a glyph), so 0.62 drew 11.2px there and was ruled unreadable. This strip is
	# 82/225 = 0.36, i.e. **6.5px** — less than half the 14px hard floor that
	# `_probe_text_floor` fails the build on, and invisible to that probe because
	# it reads font-size OVERRIDES and a `Control.scale` is not one.
	#
	# And the float was never wired: the only trace of it was a `clip_contents`
	# comment on the slot. So the post-mortem showed a player their final deck
	# with the rules rendered as grey mush and no gesture that could read them.
	# The scale stays — at 25 cards nothing bigger fits above the foot buttons —
	# and the readable face is now one hover away, which is the house rule.
	card.scale = Vector2(sc, sc)
	card.position = Vector2.ZERO
	face.add_child(card)

	if count > 1:
		face.add_child(_make_count_badge(count))
	_add_thumb_hover(slot, card_data)
	return face


## Topmost catcher on a deck thumb: names the card for a screen reader and a
## tooltip, and floats the full-size face while the pointer is on it.
func _add_thumb_hover(slot: Control, card_data: Dictionary) -> void:
	var catcher := Control.new()
	catcher.name = "ThumbHover"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	catcher.tooltip_text = String(card_data.get("name", ""))
	slot.add_child(catcher)
	var data := card_data.duplicate(true)
	catcher.mouse_entered.connect(func() -> void:
		_show_thumb_preview(data, catcher))
	catcher.mouse_exited.connect(_hide_thumb_preview)


var _thumb_preview: Node = null


func _show_thumb_preview(card_data: Dictionary, anchor: Control) -> void:
	_hide_thumb_preview()
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var card = CARD_SCENE.instantiate()
	card.card_data = card_data
	card.card_id = String(card_data.get("id", ""))
	card.is_on_battlefield = true
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above the parchment page and its closing seal, both of which the strip sits
	# on top of — a preview half-behind the document reads as a rendering fault.
	card.z_index = 220
	add_child(card)
	var r := anchor.get_global_rect()
	var vp := get_viewport_rect().size
	# Standing ABOVE the thumb, because the strip is the last block on the page:
	# below it there is only the foot row, and 300px of card would leave the
	# canvas entirely.
	var pos := Vector2(r.get_center().x - 112.5, r.position.y - 312.0)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - 233.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - 308.0))
	card.global_position = pos
	_thumb_preview = card


func _hide_thumb_preview() -> void:
	if _thumb_preview != null and is_instance_valid(_thumb_preview):
		_thumb_preview.queue_free()
	_thumb_preview = null


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
	# The chronicle owns its own reveal timeline once its complete layout is
	# ready. Do not tween it here too: two opacity writers made the page timing
	# depend on whether its final card faces were warm or cold.
	$Title.pivot_offset = $Title.size * 0.5
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		$Title.scale = Vector2.ONE
		$Title.modulate.a = 1.0
		$Subtitle.modulate.a = 1.0
		return
	$Title.scale = Vector2(0.7, 0.7)
	$Title.modulate.a = 0.0
	$Subtitle.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property($Title, "modulate:a", 1.0, 0.50).set_ease(Tween.EASE_OUT)
	tw.tween_property($Title, "scale", Vector2.ONE, 0.65) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property($Subtitle, "modulate:a", 1.0, 0.40).set_delay(0.45)

func _on_march_again_pressed(btn: Button) -> void:
	if _exit_committing:
		return
	_exit_committing = true
	if btn != null and is_instance_valid(btn) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(btn)
		await get_tree().create_timer(0.14).timeout
	if not is_inside_tree():
		return
	_march_again()


func _on_back_pressed(btn: Button) -> void:
	if _exit_committing:
		return
	_exit_committing = true
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
	}
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	# Esc returns to the main menu (the run is already over).
	if event.is_action_pressed("ui_cancel"):
		if not _exit_committing:
			_exit_committing = true
			_back()
		get_viewport().set_input_as_handled()


func _back() -> void:
	GameTheme.fade_out_then_change_scene(self, MAIN_MENU)
