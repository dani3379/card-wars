extends Control
## Credits.gd — the chronicle of the making. Attribution written in ink on a
## tall chronicle-paper roll (the same ChroniclePage the run summary is
## written on) that drifts slowly up over the night camp, embers rising.
## Replaces the old ivory-text-on-black scroll list. Programmatic so the
## .tscn file stays a one-line stub.

const MENU_SCENE = "res://scenes/main_menu.tscn"
const ChroniclePage := preload("res://scripts/ui/painters/ChroniclePage.gd")
const WaxSeal := preload("res://scripts/ui/painters/WaxSeal.gd")

# Ink-on-paper palette — the page is parchment, so all text uses the
# GameOver chronicle inks, not the gilt-on-dark HUD palette (gilt washes
# out on paper; same lesson as the card faces' keyword gold).
const INK := GameTheme.PARCHMENT_TEXT
const INK_DIM := Color(0.38, 0.29, 0.20, 1.0)
const INK_BRONZE := Color(0.42, 0.28, 0.10, 1.0)

const PAGE_W := 820.0
const ROLL_SPEED := 34.0          # px/s auto-drift
const ROLL_RESUME_DELAY := 3.5    # s of stillness after the player wheels
const ROLL_BUILD_LINES_PER_FRAME := 5

const SECTIONS: Array = [
	{
		"heading": "GAME DESIGN",
		"lines": [
			"Burning Meadow — a lane combat roguelike deckbuilder",
			"Inspired by Card Wars and Slay the Spire",
		],
	},
	{
		"heading": "ENGINE",
		"lines": [
			"Godot Engine 4.6 — godotengine.org",
		],
	},
	{
		"heading": "FONTS",
		"lines": [
			"Kreon — Julia Petretta — SIL Open Font License",
			"Inter — Rasmus Andersson — SIL Open Font License",
			"Marcellus — Astigmatic — SIL Open Font License",
			"Nunito — Vernon Adams — SIL Open Font License",
		],
	},
	{
		"heading": "ART — UI & ICONS",
		"lines": [
			"Kenney Fantasy UI Borders — CC0",
			"Kenney Board Game Icons — CC0",
			"Kenney Game Icons — CC0",
			"game-icons.net — Lorc, Delapouite, willdabeast, sbed",
			"     & contributors — CC-BY 3.0",
			"Fantasy RPG Icons — Lucas (pbmojART) — CC-BY 3.0",
			"Painterly Spell Icons — J. W. Bjerk (eleazzaar) — CC-BY 3.0",
		],
	},
	{
		"heading": "ART — CARDS & PORTRAITS",
		"lines": [
			"Public-domain masters: Gustave Doré, Mikhail Vrubel,",
			"Henry Fuseli, Goya, Bruegel, Bosch, and others",
		],
	},
	{
		"heading": "MUSIC",
		"lines": [
			"Scott Buckley — CC-BY 4.0 — scottbuckley.com.au",
			"     Song of the Forge · Simulacra · Eyes in the Void",
			"     Penumbra · Memories of Stone · Balefire",
			"     Legionnaire · Uprising · Goliath",
			"     March of Midnight · Juggernaut · Terminus",
			"     Echoes of Home · The Old Ones · Born of the Sky",
			"     The Endurance · The Fury · Unraveling · Vanguard",
			"     The Encounter · Hour of the Witch · The Summoning",
			"     Jade · Pathfinder · With These Hands · Incantation",
			"     A Dragon's Lullaby · Hyperion · Amberlight",
			"Alexander Nakarada (CreatorChords) — CC-BY 4.0 — creatorchords.com",
			"     Battle of the Creek · Valhalla · Medieval Metal",
			"     Prepare for War · The Great Battle · The Vikings",
			"     Medieval Loop One · Medieval Chateau · Tavern Tales",
			"     Sunguard · Magic Tavern · Adventure",
			"Matthew Pablo — CC-BY 3.0 — matthewpablo.com",
			"     Heroic Demise · The Dark Amulet",
			"RandomMind — CC0 — the Medieval series:",
			"     Market Day · Battle · Exploration · The Old Tower Inn",
			"     The Bard's Tale · Minstrel Dance",
		],
	},
]

var _scroll: ScrollContainer = null
var _scroll_pos := 0.0
var _firelight: ShaderMaterial = null
var _fire_t := 0.0
var _rolled_out := false
var _roll_hold := 1.2   # settle beat before the drift starts
var _rolling := true
## One-way latch on the way out. fade_out_then_change_scene parents its ink
## overlay to the TREE ROOT and only changes the scene when its 0.30s tween
## lands, so the exit stays clickable for the whole wipe: a second Esc (or Esc
## while BACK is already fading) queued a SECOND transition, and the menu it had
## just loaded was torn down and rebuilt 0.3s later — music restarting, intro
## replaying. Every other screen in the shell already carries this latch.
var _exit_committing := false


func _ready() -> void:
	_build_backdrop()
	GameTheme.add_atmosphere(self, "rest", true, {
		"vignette": 0.45,
		"grad_outer": Color(0.02, 0.01, 0.01, 0.55),
	})
	AudioBank.play_music("credits")
	_build_roll()
	_build_firelight()
	_build_chrome()
	GameTheme.fade_in(self, 0.30)
	# Reduce Motion: the roll holds still — the wheel is the only mover.
	if UserSettings != null and UserSettings.reduce_motion:
		_rolling = false
	# ALWAYS PROCESS NOW. This used to be `set_process(_rolling)` and to switch
	# itself off at the foot of the roll, on the reasoning that there was then
	# "no animation left to drive". The fire is animation left to drive, and it
	# burns whether or not the page is moving — a hearth that goes out the moment
	# the credits finish scrolling is worse than never lighting it.
	set_process(true)


func _unhandled_input(event: InputEvent) -> void:
	# Esc = the BACK button: return to the main menu.
	if event.is_action_pressed("ui_cancel"):
		if not _exit_committing:
			_exit_committing = true
			GameTheme.fade_out_then_change_scene(self, MENU_SCENE, 0.30)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_drive_firelight(delta)
	# The slow drift up the page. Player wheel input holds it for a beat
	# (see _on_scroll_input); reaching the foot of the roll parks it.
	if _scroll == null or _rolled_out or not _rolling:
		return
	if _roll_hold > 0.0:
		_roll_hold -= delta
		return
	var limit := maxf(0.0,
		_scroll.get_v_scroll_bar().max_value - _scroll.size.y)
	_scroll_pos = minf(_scroll_pos + ROLL_SPEED * delta, limit)
	# ROLL_SPEED advances by less than one pixel on many rendered frames. Avoid
	# dirtying the ScrollContainer (and its descendants' transforms) when the
	# integer scroll position has not actually changed.
	var next_pixel := int(_scroll_pos)
	if _scroll.scroll_vertical != next_pixel:
		_scroll.scroll_vertical = next_pixel
	# Once the chronicle reaches its foot the DRIFT is done — but the fire is
	# not, so this parks the scroll with a flag instead of killing `_process`.
	# Input below clears it if the player wheels back up.
	if _scroll_pos >= limit:
		_rolled_out = true


## The guttering. Three harmonics at incommensurate rates never line up, which is
## what separates a fire from a pulsing UI element — the same reasoning, and the
## same shape, as the war table's standard lamp.
func _drive_firelight(delta: float) -> void:
	if _firelight == null:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	_fire_t += delta
	var f: float = 1.0 \
		+ 0.17 * sin(_fire_t * 2.1) \
		+ 0.08 * sin(_fire_t * 5.3 + 1.1) \
		+ 0.05 * sin(_fire_t * 11.7 + 2.6)
	_firelight.set_shader_parameter("flicker", f)


func _on_scroll_input(event: InputEvent) -> void:
	# Any wheel/drag takes the reins: sync our accumulator to wherever the
	# player scrolled and hold the auto-drift for a few quiet seconds.
	if event is InputEventMouseButton or event is InputEventScreenDrag:
		_scroll_pos = float(_scroll.scroll_vertical)
		_roll_hold = ROLL_RESUME_DELAY
		# `_process` is always on now (the fire), so wheeling back up only has to
		# clear the parked flag.
		_rolled_out = false


## THE FIRE THE SCREEN ALREADY CLAIMED (2026-09-11).
##
## `_build_backdrop`'s own comment has always said "the chronicler writes these
## names by its light" — and there was no light on the roll. The whole screen was
## a list of labels drifting over a painted camp at one flat exposure, with no
## focal point anywhere and nothing alive on it. Same shape as
## `_play_face_damage_flash`, which described blood at the edges of vision and
## shipped a uniform wash: the intent was documented and unbuilt.
##
## FORM: a pool of firelight across the reading line, falling off above and
## below, so a name is brightest exactly where the eye already is.
##
## ALIVENESS: **guttering**, matched to the matter. A campfire does not breathe
## on a clean sine, so this is the three-harmonic flicker the map's standard lamp
## uses — incommensurate rates, never repeating. It is the one moving thing on a
## screen whose only other motion is a constant scroll.
##
## ADDITIVE, AND HERE THAT IS CORRECT. The ring engine measured additive and
## rejected it, but that was for a mark that FADES — folding alpha into the
## colour means a fading additive ring stops adding anything. This pool never
## fades; it is light falling on a page, which is the one thing `blend_add`
## actually models. It also means the effect can only ever ADD contrast, so it
## cannot push any name below the §11 readability floor — which a darkening
## vignette could, and `add_atmosphere` is already spending one of those.
func _build_firelight() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var lamp := ColorRect.new()
	lamp.name = "Firelight"
	lamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.color = Color.WHITE
	lamp.z_index = 6
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode blend_add;

uniform vec4 warm : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float line = 0.46;     // where the reading band sits, in UV
uniform float spread = 0.26;   // how far the pool reaches up and down
uniform float gain = 0.20;
uniform float flicker = 1.0;

void fragment() {
	// Vertical pool: a soft band centred on the reading line.
	float dy = (UV.y - line) / spread;
	float band = exp(-dy * dy * 2.2);
	// ...and a gentle horizontal falloff, so it is a POOL of light and not a
	// stripe running off both edges of the screen.
	float dx = (UV.x - 0.5) / 0.62;
	float across = exp(-dx * dx * 1.4);
	COLOR = vec4(warm.rgb * band * across * gain * flicker, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	lamp.material = mat
	add_child(lamp)
	_firelight = mat
	# Reduce Motion holds the fire steady rather than switching it off: the pool
	# is what gives the page a focal point, and that is information about where
	# to read, not decoration. Only the guttering is decorative.
	if UserSettings != null and UserSettings.reduce_motion:
		mat.set_shader_parameter("flicker", 1.0)


func _build_backdrop() -> void:
	# The night camp — the same fire the army rests by. The chronicler
	# writes these names by its light.
	var bg := TextureRect.new()
	bg.name = "CampBackdrop"
	bg.texture = load("res://assets/backgrounds/rest_campfire.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.self_modulate = Color(0.94, 0.90, 0.88, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_roll() -> void:
	var vp := get_viewport_rect().size
	_scroll = ScrollContainer.new()
	_scroll.name = "Roll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.gui_input.connect(_on_scroll_input)
	add_child(_scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(col)

	# The page opens partway up the screen and drifts from there; the tail
	# spacer lets the closing seal ride up clear of the back button.
	col.add_child(_make_spacer(vp.y * 0.30))

	var page := ChroniclePage.new()
	page.name = "CreditsPage"
	page.page_seed = 20260719
	# Keep the lower deckle beyond the viewport while offscreen entries hydrate.
	# Finished copy is taller than this, so final scroll distance is unchanged.
	page.custom_minimum_size = Vector2(PAGE_W, vp.y)
	page.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 66
	s.content_margin_right = 66
	s.content_margin_top = 48
	s.content_margin_bottom = 56
	page.add_theme_stylebox_override("panel", s)
	col.add_child(page)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	page.add_child(list)

	# ── The page heading — same document family as the run chronicle ──
	var name_lbl := _make_display_label("BURNING MEADOW", 46, INK)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(name_lbl)
	var sub := _make_display_label("CREDITS", 21, INK_BRONZE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(sub)
	list.add_child(_make_spacer(6))
	list.add_child(_make_ink_ornament(360.0))
	list.add_child(_make_spacer(18))

	for section in SECTIONS:
		await _add_section(list, section)
		if _exit_committing or not is_instance_valid(list) \
				or not list.is_inside_tree():
			return

	# ── Close of the roll: thanks + the chronicler's seal ──
	list.add_child(_make_spacer(20))
	list.add_child(_make_ink_ornament(300.0))
	list.add_child(_make_spacer(14))
	var thanks := _make_display_label("Thank you for playing.", 24, INK)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(thanks)
	list.add_child(_make_spacer(16))
	list.add_child(_make_seal())

	col.add_child(_make_spacer(vp.y * 0.42))


## Build only the currently-near portion of the long attribution roll per frame.
## The unseen lower copy completes beneath the 0.30 s scene fade; headless probes
## retain the complete synchronous tree they use for structural assertions.
func _add_section(list: VBoxContainer, section: Dictionary) -> void:
	var windowed := DisplayServer.get_name() != "headless"
	var lines_this_frame := 0
	list.add_child(_make_spacer(14))
	var heading := _make_display_label(section.get("heading", ""), 22, INK_BRONZE)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(heading)
	list.add_child(_make_rule(400.0))
	list.add_child(_make_spacer(2))
	for line_text in section.get("lines", []):
		# Indented lines are detail entries (track lists, contributor tails):
		# smaller, dimmer ink under their parent line.
		var is_detail: bool = String(line_text).begins_with(" ")
		var line := _make_body_label(String(line_text).strip_edges(),
			14 if is_detail else 16, INK_DIM if is_detail else INK)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(line)
		lines_this_frame += 1
		if windowed and lines_this_frame >= ROLL_BUILD_LINES_PER_FRAME:
			lines_this_frame = 0
			await RenderingServer.frame_post_draw
			if _exit_committing or not is_instance_valid(list) \
					or not list.is_inside_tree():
				return
	if windowed:
		await RenderingServer.frame_post_draw


func _build_chrome() -> void:
	# Fixed screen furniture that does NOT ride the roll.
	# Top-right, off the paper and over dark canopy — the Collection's BACK
	# placement, so it never collides with the rolling text.
	var back_btn := GameTheme.make_back_button("BACK TO MENU", Vector2(220, 48))
	back_btn.anchor_left = 1.0
	back_btn.anchor_right = 1.0
	back_btn.anchor_top = 0.0
	back_btn.anchor_bottom = 0.0
	back_btn.offset_left = -260
	back_btn.offset_right = -40
	back_btn.offset_top = 34
	back_btn.offset_bottom = 82
	back_btn.pressed.connect(func():
		if _exit_committing:
			return
		_exit_committing = true
		GameTheme.fade_out_then_change_scene(self, MENU_SCENE, 0.30))
	GameTheme.arm_ui_press(back_btn, "back")
	add_child(back_btn)
	GameTheme.make_settings_gear(self)


func _make_seal() -> Control:
	# The chronicler's wax seal closes the roll — pressed ember-red wax with
	# the army's diamond sunk into it.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(78, 78)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seal := WaxSeal.new()
	seal.seed_text = "the_chroniclers_seal"
	seal.wax = Color(0.46, 0.13, 0.09)
	seal.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(seal)
	if GameTheme.tex_icon_diamond != null:
		var mark := TextureRect.new()
		mark.texture = GameTheme.tex_icon_diamond
		mark.custom_minimum_size = Vector2(26, 26)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.anchor_left = 0.5
		mark.anchor_right = 0.5
		mark.anchor_top = 0.5
		mark.anchor_bottom = 0.5
		mark.offset_left = -13
		mark.offset_right = 13
		mark.offset_top = -13
		mark.offset_bottom = 13
		# Sunk into the wax, not gilded onto it.
		mark.modulate = Color(0.24, 0.06, 0.05, 0.85)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(mark)
	return slot


func _make_spacer(h: float) -> Control:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, h)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sp


func _make_display_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_body_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_rule(width: float) -> Control:
	# Hand-ruled ledger separator — heavier line over a hairline, bronze ink
	# (the GameOver RuleSep furniture).
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(width, 7)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func():
		var w: float = rule.size.x
		rule.draw_line(Vector2(0, 2), Vector2(w, 2), Color(0.45, 0.31, 0.14, 0.55), 1.6, true)
		rule.draw_line(Vector2(w * 0.06, 5), Vector2(w * 0.94, 5),
			Color(0.45, 0.31, 0.14, 0.28), 1.0, true))
	return rule


func _make_ink_ornament(width: float) -> Control:
	# The line·diamond·line ornament, re-inked for paper.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for side in range(2):
		if side == 1 and GameTheme.tex_icon_diamond != null:
			var diamond := TextureRect.new()
			diamond.texture = GameTheme.tex_icon_diamond
			diamond.custom_minimum_size = Vector2(13, 13)
			diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			diamond.modulate = INK_BRONZE
			diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(diamond)
		var line := ColorRect.new()
		line.custom_minimum_size = Vector2(width * 0.42, 2)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.color = Color(0.45, 0.31, 0.14, 0.50)
		row.add_child(line)
	return row
