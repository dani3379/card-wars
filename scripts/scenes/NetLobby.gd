extends Control
## NetLobby.gd — the online Skirmish lobby (Phase 0). Host or join a 1-v-1 over
## LAN / a Tailscale overlay, then both sides ready up and the host starts the
## match. All transport lives in the NetMatch autoload; this screen is pure UI
## that calls into it and reacts to its signals.
##
## Built programmatically over a GameTheme atmosphere background (same pattern as
## MapView / Shop / Rest / the credits screen).

const MENU_SCENE := "res://scenes/main_menu.tscn"
const DRAFT_SCENE := "res://scenes/net_draft.tscn"   # built in Phase 1

const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
# The lobby's two accents used to be a saturated web-green and web-blue — the
# only cool, fully-saturated inks in a sepia/gilt/ember game, sitting dead
# centre of the screen. They read as unstyled default UI. Both now speak in
# world: VERDIGRIS is the aged-copper "go / open / connected" ink events already
# use for blue options, and JOIN takes the affirmative gilt every other primary
# action in the game wears. The crown/sword tile icons still tell them apart.
## "Go / ready / connected" — a real status channel (10 call sites), distinct
## from ASH (waiting) and the error reds, so it is not decoration and is not
## being deleted. It WAS `Color(0.55, 0.78, 0.70)`: a light, saturated teal, and
## on the lobby render the single cold element on an otherwise all-ember screen
## — the project's #1 recorded art defect, and the exact `b >= r` cyan tell
## MainMenu's own colour notes name. Warmed to a leaf green: `g` stays high (it
## has to, or it stops meaning go) while `b` drops well under `r`, so it reads
## affirmative without reading cyan. Its sibling AZURE was already remapped to
## gilt for the same reason; this one was missed.
const GREEN := Color(0.62, 0.82, 0.44, 1.0)   # leaf — host / ready / connected
const RED := Color(0.90, 0.45, 0.35, 1.0)
const AZURE := Color(0.86, 0.72, 0.34, 1.0)   # join accent — affirmative gilt
const EMBER := Color(0.90, 0.62, 0.30, 1.0)   # practice / drill accent

## NetLobby previously retained 194 ChartPanelStyle drawing commands across
## its plates, tiles, and five hero chips (252 screen draws total). This local
## style keeps the same chamfered, shaded, metal-rimmed language but emits the
## whole face as one triangle array, plus one shadow command when requested.
## It deliberately stays local: document screens that lean on deckled paper
## keep the richer shared painter, while this dense lobby gets the cheap form.
class FastChartPanelStyle extends StyleBox:
	var bg_color := Color(0.06, 0.05, 0.042, 0.96)
	var border_color := Color(0.60, 0.51, 0.34, 0.90)
	var rule_width := 1.0
	var chamfer := 12.0
	var shadow := true
	var parchment := false
	var corner_tacks := true
	var shadow_color := Color(0, 0, 0, 1.0)
	var shadow_size := 8.0

	func _get_draw_rect(rect: Rect2) -> Rect2:
		return rect.grow(3.0 + shadow_size * 0.65) if shadow else rect.grow(2.0)

	static func _oct(rect: Rect2, inset: float, cut: float) -> PackedVector2Array:
		var left := rect.position.x + inset
		var top := rect.position.y + inset
		var right := rect.end.x - inset
		var bottom := rect.end.y - inset
		var corner := clampf(cut - inset * 0.45, 2.0,
			minf(right - left, bottom - top) * 0.26)
		return PackedVector2Array([
			Vector2(left + corner, top), Vector2(right - corner, top),
			Vector2(right, top + corner), Vector2(right, bottom - corner),
			Vector2(right - corner, bottom), Vector2(left + corner, bottom),
			Vector2(left, bottom - corner), Vector2(left, top + corner),
		])

	static func _append_ring(points: Array[Vector2], colors: Array[Color],
			indices: Array[int], outer: PackedVector2Array,
			inner: PackedVector2Array, color: Color) -> void:
		for i in range(outer.size()):
			var j := (i + 1) % outer.size()
			var base := points.size()
			points.append_array([outer[i], outer[j], inner[j], inner[i]])
			colors.append_array([color, color, color, color])
			indices.append_array([base, base + 1, base + 2,
				base, base + 2, base + 3])

	static func _append_fan(points: Array[Vector2], colors: Array[Color],
			indices: Array[int], poly: PackedVector2Array,
			top_color: Color, bottom_color: Color, bounds: Rect2) -> void:
		var center := Vector2.ZERO
		for point in poly:
			center += point
		center /= maxf(float(poly.size()), 1.0)
		var center_index := points.size()
		points.append(center)
		colors.append(top_color.lerp(bottom_color, 0.5))
		var first := points.size()
		for point in poly:
			points.append(point)
			var mix := clampf((point.y - bounds.position.y) /
				maxf(bounds.size.y, 1.0), 0.0, 1.0)
			colors.append(top_color.lerp(bottom_color, mix))
		for i in range(poly.size()):
			indices.append_array([center_index, first + i,
				first + ((i + 1) % poly.size())])

	func _draw(canvas_item: RID, rect: Rect2) -> void:
		if minf(rect.size.x, rect.size.y) < 3.0:
			return
		var cut := clampf(chamfer, 4.0,
			minf(rect.size.x, rect.size.y) * 0.26)
		if shadow:
			var shadow_poly := _oct(rect.grow(shadow_size * 0.32), 0.0,
				cut + shadow_size * 0.32)
			for i in range(shadow_poly.size()):
				shadow_poly[i] += Vector2(0, 3)
			RenderingServer.canvas_item_add_polygon(canvas_item, shadow_poly,
				PackedColorArray([Color(shadow_color.r, shadow_color.g,
					shadow_color.b, shadow_color.a * 0.34)]))

		var seam := 1.4
		var outer := _oct(rect, 0.0, cut)
		var metal := _oct(rect, seam, cut)
		var inner := _oct(rect, seam + maxf(rule_width, 1.4), cut)
		var base := bg_color
		if parchment:
			base = bg_color.lerp(Color(0.16, 0.12, 0.08, bg_color.a), 0.35)
		var top_color := base.lerp(Color(0.30, 0.24, 0.16, base.a), 0.22)
		var bottom_color := base.lerp(Color(0.0, 0.0, 0.0, base.a), 0.30)
		var points: Array[Vector2] = []
		var colors: Array[Color] = []
		var indices: Array[int] = []
		_append_ring(points, colors, indices, outer, metal,
			Color(0.04, 0.03, 0.02, 0.90))
		_append_ring(points, colors, indices, metal, inner, border_color)
		_append_fan(points, colors, indices, inner, top_color, bottom_color, rect)

		if corner_tacks and minf(rect.size.x, rect.size.y) >= 70.0 and cut >= 7.0:
			var tack_size := clampf(cut * 0.27, 2.5, 4.3)
			var tack_color := Color(minf(border_color.r * 1.12, 1.0),
				minf(border_color.g * 1.12, 1.0),
				minf(border_color.b * 1.12, 1.0), border_color.a)
			for pair in [[7, 0], [1, 2], [3, 4], [5, 6]]:
				var at: Vector2 = (outer[pair[0]] + outer[pair[1]]) * 0.5
				var diamond := PackedVector2Array([
					at + Vector2(0, -tack_size), at + Vector2(tack_size, 0),
					at + Vector2(0, tack_size), at + Vector2(-tack_size, 0)])
				_append_fan(points, colors, indices, diamond,
					tack_color, tack_color, rect)

		RenderingServer.canvas_item_add_triangle_array(canvas_item,
			PackedInt32Array(indices), PackedVector2Array(points),
			PackedColorArray(colors))

# ── UI refs ──
var _status_label: Label
var _hint_label: Label
var _code_label: Label              # big shareable room code (host, online)
var _ip_field: LineEdit
var _port_field: LineEdit
var _code_field: LineEdit           # room-code entry (join, online)
var _host_online_btn: Button       # relay host (primary path)
var _join_online_btn: Button       # relay join by code
var _lan_toggle: Button            # expands the direct/LAN fallback section
var _lan_panel: Control            # direct host/join controls (collapsed by default)
var _host_btn: Button              # LAN/direct host
var _join_btn: Button              # LAN/direct join
var _ready_btn: Button
var _start_btn: Button
var _back_btn: Button               # outer "leave to menu" — hidden while the practice sub-panel owns the back
var _connect_panel: VBoxContainer   # host/join controls (hidden once connected)
var _ready_panel: VBoxContainer     # ready/start controls (shown once connected)
var _relay_host: String = ""        # resolved relay address (empty = online disabled)
var _scene_exit_locked: bool = false
var _match_start_requested: bool = false

# ── Mode / format picker (host picks; client sees the choice) ──
var _mode_panel: VBoxContainer       # built on connect (host buttons / client label)
var _mode_buttons: Dictionary = {}   # MatchMode id -> Button (host only)
var _bo_buttons: Dictionary = {}     # best_of value (1/3) -> Button (host only)
var _style_buttons: Dictionary = {}  # NetMatch.STYLE_* -> Button (host only)
var _ars_relic_parts: Array = []     # [HSlider, Label] — the relic scale (host only)
var _ars_potion_parts: Array = []    # [HSlider, Label] — the potion scale (host only)
var _mode_info_label: Label          # client: shows the host's chosen mode/format
var _arsenal_info_label: Label       # host + client: the arsenal terms in words
var _selected_mode: int = 0          # host's current pick (SkirmishState.MatchMode)
var _selected_best_of: int = 1       # host's current pick (1 or 3)
var _selected_style: int = 0         # host's current pick (NetMatch.STYLE_*)
# The arsenal size the host is offering BOTH players. Seeded from the shared
# defaults so an untouched picker commits exactly the stage that shipped.
var _selected_ars_relics: int = SkirmishState.ARSENAL_RELIC_ROUNDS
var _selected_ars_potions: int = SkirmishState.ARSENAL_POTION_ROUNDS

# ── Practice vs Bot (offline; no peer) ──
var _vs_bot_btn: Button
var _vsbot_begin_btn: Button
var _vs_bot_panel: VBoxContainer
var _vsbot_mode: int = 0
var _vsbot_bo: int = 1
var _vsbot_style: int = 0
var _vsbot_ars_relics: int = SkirmishState.ARSENAL_RELIC_ROUNDS
var _vsbot_ars_potions: int = SkirmishState.ARSENAL_POTION_ROUNDS
var _vsbot_mode_buttons: Dictionary = {}
var _vsbot_bo_buttons: Dictionary = {}
var _vsbot_style_buttons: Dictionary = {}
var _vsbot_ars_relic_parts: Array = []
var _vsbot_ars_potion_parts: Array = []
## The drill's own copy of the terms line. Kept separate from _arsenal_info_label
## rather than shared: both panels can exist at once (the mode panel is built on
## connect, this one on the practice press), so one field would let whichever was
## built last silently steal the other's label.
var _vsbot_arsenal_info: Label = null

# ── Lord pick + the two banner plates (your standard vs the challenger's).
# The pick is cosmetic identity (portrait + emote voice, both players see it);
# the flanking plates are the lobby's stage and refresh from the same signals
# (hero_state_changed → _refresh_hero_ui, ready_state_changed → seals).
var _hero_buttons: Dictionary = {}        # hero id -> Button (left plate chips)
var _selected_hero: String = ""
var _your_portrait: TextureRect = null
var _your_name_label: Label = null
var _your_tagline: Label = null
var _your_seal: Label = null              # your ready state, stamped on your plate
var _your_glow: TextureRect = null        # breathing lamplight over your portrait
var _opp_portrait: TextureRect = null
var _opp_empty_box: Control = null        # engraved mark while the seat is empty
var _opp_name_label: Label = null
var _opp_tagline: Label = null
var _opp_seal: Label = null               # opponent ready state, on their plate
var _opp_glow: TextureRect = null
var _opp_shown: bool = false              # is the challenger portrait currently up
var _challenger_is_bot: bool = false      # practice panel open → plate shows the bot
var _code_plate: Control = null           # the watchword docket (shareable room code)
var _code_caption: Label = null           # docket caption — flips to COPIED feedback
var _room_code_raw := ""                  # unspaced code, for the clipboard
var _code_copy_gen := 0                   # stale-restore guard on the caption flip
var _opp_portrait_life: Tween = null       # active only while opponent art is visible
var _opp_glow_life: Tween = null           # ditto: no hidden infinite tweens
var _lamp_glow_tex: Texture2D = null      # shared radial lamplight texture
var _lan_default_open: bool = false       # direct-IP panel starts open (no-relay build)


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	# The muster pool: quiet war-council medieval, shared by every skirmish
	# prep screen (lobby, quick-match, draft, sealed, constructed).
	AudioBank.play_music_random(["net_lobby", "net_lobby_b", "rest_c"])
	_relay_host = NetMatch.get_relay_host()
	# Fresh lobby: drop any stale connection from a previous visit. The lord pick
	# survives leave() (sticky), so a rematch lobby reopens on your last lord.
	NetMatch.leave()
	_selected_hero = NetMatch.local_hero if NetMatch.local_hero != "" \
		else HeroDB.DEFAULT_HERO
	_build_ui()
	_flatten_chart_styles(self)
	_wire_net_signals()
	_refresh_state()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc = the BACK button: drop any connection and return to the main menu.
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────────────────────────────────
#  UI
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# The stage: two banner plates flank a central war-table column — your
	# standard on the left, the challenger's seat on the right. The center
	# column carries the state panels (connect / practice / ready) unchanged.
	_build_banner_plates()

	var col := VBoxContainer.new()
	col.name = "Lobby"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 11)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	# THE COLUMN FOLLOWS THE CANVAS (2026-09-19, CLASS C32). These are authored
	# against 1600×900; UI Scale divides the logical canvas, so pinned offsets made
	# this the worst-hit shell screen — `_probe_uiscale` measured net_lobby falling
	# 95%→77% in x and 81%→68% in y at 60%. See GameTheme.canvas_scale's header;
	# a no-op at 100%, so every number below keeps the meaning it was chosen for.
	var _k: Vector2 = GameTheme.canvas_scale(self)
	col.offset_left = -430.0 * _k.x
	col.offset_right = 430.0 * _k.x
	# ±390, not ±330 (2026-09-14). A VBox whose content exceeds its rect does not
	# centre the overflow — it lays out from the TOP and spills off the bottom, so
	# the rect's top edge is the only thing that decides where a too-tall state
	# starts. The connected-host column is the tallest state in this scene and it
	# was already within 20px of the canvas floor; the arsenal picker put BACK 73px
	# under it. Growing the rect SYMMETRICALLY costs the shorter states nothing —
	# they centre on 450 either way — and buys the tall one 60px of headroom.
	col.offset_top = -390.0 * _k.y
	col.offset_bottom = 390.0 * _k.y
	add_child(col)

	col.add_child(GameTheme.make_screen_title("SKIRMISH", GILT_BRIGHT))

	var blurb := GameTheme.make_label(
		"Play against a friend or practice against a bot.", 16, ASH)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)

	# ── Connect panel (host / join / practice) ──
	_connect_panel = VBoxContainer.new()
	_connect_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_panel.add_theme_constant_override("separation", 11)
	col.add_child(_connect_panel)

	# Composition follows whether the relay is wired into THIS build. When it is,
	# the online duel headlines. When it isn't, we don't parade two dead grey
	# blocks in the centre — the paths that actually work (a practice drill, and a
	# direct connection to a friend) lead instead.
	var online_ok := _relay_host != ""

	if online_ok:
		# ── Relay wired: the online duel is the headline ──
		_connect_panel.add_child(GameTheme.make_section_divider(
			"PLAY A FRIEND", GameTheme.GILT, 17, 130.0))
		var duel_row := HBoxContainer.new()
		duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
		duel_row.add_theme_constant_override("separation", 18)
		_connect_panel.add_child(duel_row)
		var host_tile := _build_host_tile(true, "")
		_host_online_btn = host_tile.get_node("ClickButton")
		_host_online_btn.pressed.connect(_on_host_online_pressed)
		GameTheme.arm_ui_press(_host_online_btn, "commit")
		duel_row.add_child(host_tile)
		duel_row.add_child(_build_join_tile(true, ""))

		_connect_panel.add_child(GameTheme.make_section_divider(
			"OR PRACTICE SOLO", GameTheme.GILT, 17, 130.0))
		_connect_panel.add_child(_build_practice_banner(Vector2(802, 90)))

		# Advanced: the direct-IP fallback stays folded behind a quiet toggle.
		_lan_toggle = GameTheme.make_back_button("Same network / direct IP  ▾",
			Vector2(300, 32), 14, ASH)
		_lan_toggle.tooltip_text = "Play over a LAN or a Tailscale address with no relay — best on the same WiFi."
		_lan_toggle.pressed.connect(_on_lan_toggle_pressed)
		GameTheme.arm_ui_press(_lan_toggle, "select")
		_connect_panel.add_child(_lan_toggle)
		_lan_panel = _build_lan_panel()
		_connect_panel.add_child(_lan_panel)
	else:
		# ── No relay in this build: lead with what works. ──
		_connect_panel.add_child(GameTheme.make_section_divider(
			"START A MATCH", GameTheme.GILT, 17, 130.0))
		# Practice is the hero here — a taller, warmer banner that deals in.
		var hero := _build_practice_banner(Vector2(760, 110))
		_connect_panel.add_child(hero)
		GameTheme.deal_in(hero, 0.22)

		# A direct connection is the real "face a friend" path with no relay, so
		# it sits open — not buried under a toggle a player has to discover.
		_connect_panel.add_child(GameTheme.make_section_divider(
			"OR PLAY A FRIEND — SAME NETWORK", GameTheme.GILT, 14, 96.0))
		_lan_default_open = true
		_lan_panel = _build_lan_panel()
		_lan_panel.visible = true
		_connect_panel.add_child(_lan_panel)

	# ── Practice-vs-bot sub-panel (offline mode/format pick, shown on demand) ──
	_vs_bot_panel = VBoxContainer.new()
	_vs_bot_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_bot_panel.add_theme_constant_override("separation", 8)
	_vs_bot_panel.visible = false
	col.add_child(_vs_bot_panel)

	# ── Ready panel (after connect) ──
	# The lord pick and both ready seals live on the flanking banner plates, so
	# the column carries only the terms of the duel and the two big actions.
	_ready_panel = VBoxContainer.new()
	_ready_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_ready_panel.add_theme_constant_override("separation", 10)
	_ready_panel.visible = false
	col.add_child(_ready_panel)

	_ready_panel.add_child(GameTheme.make_section_divider(
		"MATCH SETTINGS", GameTheme.GILT, 17, 130.0))

	# Mode / format picker — populated on connect (host gets buttons, client a
	# read-only label) since is_host isn't known until host/join completes.
	_mode_panel = VBoxContainer.new()
	_mode_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_panel.add_theme_constant_override("separation", 6)
	_ready_panel.add_child(_mode_panel)
	_ready_panel.add_child(GameTheme.make_separator(GILT_BRIGHT, 300.0))

	# GILT, NOT GREEN — the same affirmative ink every other primary action wears
	# (see the AZURE note at the top of this file). GREEN is this screen's STATUS
	# channel, and the opponent plate three hundred pixels to the right prints the
	# literal word "READY" in it to mean *they have readied up*. This button, while
	# you have NOT readied, printed the same word in the same colour to mean
	# *press me* — and did it directly under your own plate reading "not ready".
	# One word, one colour, two opposite meanings, all on screen at once.
	_ready_btn = GameTheme.make_back_button("READY", Vector2(300, 46), 20, GILT_BRIGHT)
	_ready_btn.pressed.connect(_on_ready_pressed)
	GameTheme.arm_ui_press(_ready_btn, "commit")
	_ready_panel.add_child(_ready_btn)

	_start_btn = GameTheme.make_back_button("START MATCH", Vector2(300, 46), 20, GILT_BRIGHT)
	_start_btn.tooltip_text = "Host only — enabled once both players are ready."
	_start_btn.pressed.connect(_on_start_pressed)
	GameTheme.arm_ui_press(_start_btn, "commit")
	_start_btn.disabled = true
	_ready_panel.add_child(_start_btn)

	col.add_child(GameTheme.make_separator(GILT_BRIGHT, 360.0))

	# ── Status + shareable code + hint ──
	_status_label = GameTheme.make_label("", 16, IVORY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status_label)

	# The watchword docket — the shareable room code staged as a parchment chit
	# (host, online). Hidden until the relay assigns one.
	_code_plate = _build_code_plate()
	_code_plate.visible = false
	col.add_child(_code_plate)

	_hint_label = GameTheme.make_label("", 13, ASH)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(620, 0)
	col.add_child(_hint_label)

	# ── Back ──
	_back_btn = GameTheme.make_back_button("BACK", Vector2(160, 42), 16)
	_back_btn.pressed.connect(_on_back_pressed)
	GameTheme.arm_ui_press(_back_btn, "back")
	col.add_child(_back_btn)


## The PRACTICE vs BOT banner (built at two sizes: a secondary strip when online
## leads, or a taller hero when the relay is unavailable). Wires _vs_bot_btn.
func _build_practice_banner(min_size: Vector2) -> Control:
	var banner := GameTheme.make_choice_banner(
		"PRACTICE VS BOT",
		"Play any mode against a local AI opponent — no connection needed.",
		EMBER, "res://assets/icons/game-icons/crossed-swords.svg", min_size)
	_vs_bot_btn = banner.get_node("ClickButton")
	_vs_bot_btn.pressed.connect(_on_vs_bot_pressed)
	GameTheme.arm_ui_press(_vs_bot_btn, "commit")
	return banner


# ─────────────────────────────────────────────────────────────────────────
#  BANNER PLATES — the two standards flanking the war table. Left = your
#  lord (portrait + the pick chips); right = the challenger's seat (empty
#  mark → their portrait + ready seal once someone answers).
# ─────────────────────────────────────────────────────────────────────────

func _build_banner_plates() -> void:
	var left := _make_banner_plate("YOU", -745.0, -465.0)
	var lrefs: Dictionary = left.get_meta("refs")
	_your_portrait = lrefs.portrait
	_your_name_label = lrefs.name_label
	_your_tagline = lrefs.tagline
	_your_seal = lrefs.seal
	_your_glow = lrefs.glow
	(lrefs.body as VBoxContainer).add_child(_build_hero_chips())

	var right := _make_banner_plate("OPPONENT", 465.0, 745.0)
	var rrefs: Dictionary = right.get_meta("refs")
	_opp_portrait = rrefs.portrait
	_opp_empty_box = rrefs.empty_box
	_opp_name_label = rrefs.name_label
	_opp_tagline = rrefs.tagline
	_opp_seal = rrefs.seal
	_opp_glow = rrefs.glow

	# The chips row refreshed before the right plate existed — run the full
	# repaint now that both plates hold their refs.
	_refresh_hero_ui()

	GameTheme.deal_in(left, 0.08)
	GameTheme.deal_in(right, 0.16)
	# Breathe once layout has a real portrait size to pivot the Ken-Burns on.
	call_deferred("_start_plate_life")


## One flanking plate: header word, framed portrait well, name, tagline, seal.
## Returns the PanelContainer with a "refs" meta dict for the refreshers.
func _make_banner_plate(header_text: String, off_l: float, off_r: float) -> PanelContainer:
	var plate := PanelContainer.new()
	var style := GameTheme.make_panel_style(
		Color(0.055, 0.048, 0.040, 0.94), Color(0.60, 0.51, 0.34, 0.80), 1, 6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", style)
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	# THE PLATES FOLLOW THE CANVAS (2026-09-19, CLASS C32). These flanking plates
	# span x -745..+745 — 93% of the design canvas — so they, not the centre
	# column, are what the coverage oracle measures on this screen. Fixing the
	# column alone moved nothing, which is the ink-bounding-box limit the gate's
	# own header warns about: it sees the layout pinned WHOLESALE, so every piece
	# at the extremes has to follow. See GameTheme.canvas_scale; no-op at 100%.
	var _k: Vector2 = GameTheme.canvas_scale(self)
	plate.offset_left = off_l * _k.x
	plate.offset_right = off_r * _k.x
	plate.offset_top = -285.0 * _k.y
	plate.offset_bottom = 285.0 * _k.y
	add_child(plate)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	plate.add_child(vb)

	var head := GameTheme.make_label(header_text, 16, GameTheme.GILT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	vb.add_child(GameTheme.make_separator(Color(GILT_BRIGHT.r, GILT_BRIGHT.g,
		GILT_BRIGHT.b, 0.30), 180.0))

	# Portrait well: dark recess with a gilt hairline; the painting sits inset,
	# and an engraved-mark box (hidden by default) covers the empty-seat state.
	# clip_contents so the portrait's slow Ken-Burns zoom is masked to the well.
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(236, 296)
	well.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	well.clip_contents = true
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Color(0.03, 0.025, 0.02, 0.92)
	well_style.border_color = Color(0.60, 0.51, 0.34, 0.65)
	well_style.set_border_width_all(1)
	well.add_theme_stylebox_override("panel", well_style)
	vb.add_child(well)

	var port := TextureRect.new()
	port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	port.clip_contents = true
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(port)

	# Breathing lamplight: a warm radial glow, additive over the portrait, biased
	# to the top like a hanging lamp. Held steady under Reduce Motion; pulses
	# otherwise (see _start_plate_life).
	var glow := TextureRect.new()
	glow.texture = _lamp_glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1.0, 0.74, 0.36, 0.13)
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	well.add_child(glow)

	var empty_box := Control.new()
	empty_box.custom_minimum_size = Vector2(96, 96)
	empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# AN EMPTY HELM ON THE TABLE, not a grey sword. This slot is a large black
	# well beside a fully painted hero portrait, so whatever sits in it is read
	# as "the art did not load" unless it is unmistakably heraldry. sword.png is
	# a flat primitive from the pre-art icon set; the horned helm is from the
	# engraved game-icons kit and says the seat is waiting for someone.
	_add_engraved_icon(empty_box,
		"res://assets/icons/game-icons/horned-helm.svg", true)
	var empty_center := CenterContainer.new()
	empty_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_center.visible = false     # the refresher toggles this wrapper
	empty_center.add_child(empty_box)
	well.add_child(empty_center)

	var name_lbl := GameTheme.make_label("", 22, GILT_BRIGHT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	vb.add_child(name_lbl)

	var tagline := GameTheme.make_label("", 13, ASH)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(230, 0)
	vb.add_child(tagline)

	var seal := GameTheme.make_label("", 15, ASH)
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(seal)

	plate.set_meta("refs", {"body": vb, "portrait": port, "empty_box": empty_center,
		"name_label": name_lbl, "tagline": tagline, "seal": seal, "glow": glow})
	return plate


## Shared radial lamplight texture — a soft warm disc biased to the upper third,
## so an additive copy over a portrait reads as a lamp hung above it.
func _lamp_glow_texture() -> Texture2D:
	if _lamp_glow_tex != null:
		return _lamp_glow_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.32)
	t.fill_to = Vector2(1.18, 1.12)
	t.width = 128
	t.height = 160
	_lamp_glow_tex = t
	return _lamp_glow_tex


## Kick the plates to life once layout has settled: a slow Ken-Burns breath on
## each portrait and a gentle lamplight pulse over each well. Deferred so the
## portraits have a real size to pivot on. Reduce Motion holds it all steady.
func _start_plate_life() -> void:
	# Let layout settle so the portraits have a real size to pivot the zoom on.
	await get_tree().process_frame
	await get_tree().process_frame
	if _your_portrait != null and is_instance_valid(_your_portrait) \
			and _your_portrait.size.x > 1.0:
		GameTheme.ken_burns(_your_portrait, _your_portrait.size * 0.5, 1.05, 15.0)
	_pulse_glow(_your_glow)
	# The empty seat breathes: a slow dim/lift on the engraved sword, so an
	# unclaimed seat reads as waiting rather than dead. Runs on the hidden
	# wrapper harmlessly once a challenger fills the seat.
	if _opp_empty_box != null and is_instance_valid(_opp_empty_box) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		var tw := _opp_empty_box.create_tween().set_loops()
		tw.tween_property(_opp_empty_box, "modulate:a", 0.45, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_opp_empty_box, "modulate:a", 1.0, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Loop a warm lamp pulse on a glow overlay (decorative — held steady otherwise).
func _pulse_glow(glow: TextureRect) -> void:
	if glow == null or not is_instance_valid(glow):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "modulate:a", 0.21, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(glow, "modulate:a", 0.09, 2.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Start or stop the opponent's two decorative loops with the portrait itself.
## A fresh lobby spends nearly all its time on the empty-seat state; previously
## its hidden portrait and hidden glow still owned two infinite SceneTreeTweens.
func _set_opponent_plate_life(on: bool) -> void:
	# A deferred start can become stale if the peer leaves in the same frame.
	if on != _opp_shown:
		return
	if not on:
		if _opp_portrait_life != null and _opp_portrait_life.is_valid():
			_opp_portrait_life.kill()
		if _opp_glow_life != null and _opp_glow_life.is_valid():
			_opp_glow_life.kill()
		_opp_portrait_life = null
		_opp_glow_life = null
		if _opp_portrait != null and is_instance_valid(_opp_portrait):
			_opp_portrait.scale = Vector2.ONE
		if _opp_glow != null and is_instance_valid(_opp_glow):
			_opp_glow.modulate.a = 0.13
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if _opp_portrait != null and is_instance_valid(_opp_portrait) \
			and _opp_portrait.size.x > 1.0:
		_opp_portrait.pivot_offset = _opp_portrait.size * 0.5
		_opp_portrait_life = _opp_portrait.create_tween().set_loops()
		_opp_portrait_life.tween_property(
			_opp_portrait, "scale", Vector2(1.05, 1.05), 15.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_opp_portrait_life.tween_property(
			_opp_portrait, "scale", Vector2.ONE, 15.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _opp_glow != null and is_instance_valid(_opp_glow):
		_opp_glow_life = _opp_glow.create_tween().set_loops()
		_opp_glow_life.tween_property(_opp_glow, "modulate:a", 0.21, 2.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_opp_glow_life.tween_property(_opp_glow, "modulate:a", 0.09, 2.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)



## The watchword docket: caption + the big spaced room code on a parchment chit.
func _build_code_plate() -> Control:
	var wrap := CenterContainer.new()
	var chit := PanelContainer.new()
	var style := GameTheme.make_panel_style(GameTheme.PARCHMENT,
		Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.70), 1, 5)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	chit.add_theme_stylebox_override("panel", style)
	# The docket is the thing you hand to your friend — clicking it copies the
	# code so "share this" is one gesture, not six keystrokes read aloud.
	chit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chit.tooltip_text = "Copy the room code."
	chit.gui_input.connect(_on_code_chit_input.bind(chit))
	wrap.add_child(chit)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	chit.add_child(vb)

	var cap := GameTheme.make_label("ROOM CODE", 12, GameTheme.GILT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	_code_caption = cap

	_code_label = GameTheme.make_label("", 40, GILT_BRIGHT)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameTheme.font_display:
		_code_label.add_theme_font_override("font", GameTheme.font_display)
	vb.add_child(_code_label)
	return wrap


func _on_code_chit_input(ev: InputEvent, chit: Control) -> void:
	if not (ev is InputEventMouseButton and ev.pressed
			and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if _room_code_raw == "":
		return
	DisplayServer.clipboard_set(_room_code_raw)
	AudioBank.play_ui("select")
	GameTheme.punch(chit, 1.05)
	if _code_caption == null or not is_instance_valid(_code_caption):
		return
	# The caption flip is the confirmation (informational — survives Reduce
	# Motion); the pulse is just the flash on top.
	_code_caption.text = "COPIED — SEND IT TO YOUR FRIEND"
	GameTheme.pulse_label(_code_caption)
	_code_copy_gen += 1
	var gen := _code_copy_gen
	await get_tree().create_timer(1.8).timeout
	if is_instance_valid(_code_caption) and gen == _code_copy_gen:
		_code_caption.text = "ROOM CODE"


## Shared skeleton for the two FACE-A-FRIEND tiles (HOST and JOIN) so they read
## as identical siblings: chart panel, engraved sigil, display title, accent rule.
## Returns {"root": PanelContainer, "vbox": VBoxContainer} — the caller fills the
## vbox with its body text + controls (and, for HOST, a whole-tile click overlay).
func _duel_tile_base(title_text: String, accent: Color, icon_path: String,
		online_ok: bool) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(392, 152)
	root.add_theme_stylebox_override("panel", _chart_panel_style(not online_ok))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hbox)

	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_engraved_icon(icon_box, icon_path, not online_ok)
	hbox.add_child(icon_box)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 7)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vb)

	var title := GameTheme.make_label(title_text, 24,
		Color(0.90, 0.78, 0.52) if online_ok else Color(0.6, 0.6, 0.55, 0.7))
	if GameTheme.font_display:
		title.add_theme_font_override("font", GameTheme.font_display)
	vb.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.80 if online_ok else 0.30)
	rule.custom_minimum_size = Vector2(38, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(rule)

	return {"root": root, "vbox": vb}


## HOST tile — a whole-tile click target (mirrors make_choice_banner's hover lift).
func _build_host_tile(online_ok: bool, reason: String) -> Control:
	var base := _duel_tile_base("HOST", GREEN,
		"res://assets/icons/game-icons/flying-flag.svg", online_ok)
	var root: PanelContainer = base.root
	var vb: VBoxContainer = base.vbox

	var body := GameTheme.make_label(
		"Open a room and get a code to share. Works anywhere — no IP, no port forwarding." \
			if online_ok else reason,
		15, Color(0.88, 0.84, 0.72) if online_ok else Color(0.82, 0.72, 0.60))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(300, 0)
	vb.add_child(body)

	var click := Button.new()
	click.name = "ClickButton"
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.disabled = not online_ok
	click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	for st in ["normal", "hover", "pressed", "disabled"]:
		click.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	root.add_child(click)
	if online_ok:
		click.mouse_entered.connect(func(): root.modulate = Color(1.10, 1.08, 1.02))
		click.mouse_exited.connect(func(): root.modulate = Color.WHITE)
	else:
		root.modulate = Color(0.85, 0.82, 0.78, 0.95)
	return root


## JOIN tile — sibling to HOST, but it carries the room-code field + CONNECT
## instead of a single click target.
func _build_join_tile(online_ok: bool, reason: String) -> Control:
	var base := _duel_tile_base("JOIN", AZURE,
		"res://assets/icons/game-icons/crossed-swords.svg", online_ok)
	var vb: VBoxContainer = base.vbox

	var hint := GameTheme.make_label(
		"Enter your friend's room code." if online_ok else reason, 15,
		Color(0.88, 0.84, 0.72) if online_ok else Color(0.82, 0.72, 0.60))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	vb.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)

	_code_field = _make_field("", 176, "ROOM CODE")
	_code_field.max_length = NetMatch.ROOM_CODE_LEN
	_code_field.editable = online_ok
	_code_field.text_changed.connect(_on_code_typed)
	_code_field.text_submitted.connect(func(_t): _on_join_online_pressed())
	row.add_child(_code_field)

	_join_online_btn = GameTheme.make_back_button("CONNECT", Vector2(118, 40), 17, GILT_BRIGHT)
	_join_online_btn.tooltip_text = "Enter your friend's room code to connect."
	_join_online_btn.disabled = not online_ok
	_join_online_btn.pressed.connect(_on_join_online_pressed)
	GameTheme.arm_ui_press(_join_online_btn, "commit")
	row.add_child(_join_online_btn)

	return base.root


## The collapsible direct-IP fallback, wrapped in a chart panel so the advanced
## section reads as one grouped card rather than loose controls.
func _build_lan_panel() -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _chart_panel_style(false))

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var note := GameTheme.make_label(
		"No relay needed — connect straight over a LAN or a Tailscale address.", 14, ASH)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)

	# HOST and JOIN are the same KIND of thing — two halves of one decision — so
	# they take the same ink AND the same plate. Frameless gilt at size 17,
	# centred on its own line, is the screen's SECTION-HEADING costume: this sat
	# directly under "OR PLAY A FRIEND — SAME NETWORK" and above the address row
	# wearing exactly that, so the one control that starts a LAN game read as a
	# caption for the fields below it. Its sibling JOIN was replated for this
	# same reason a few lines down and this one was left behind — which made the
	# mismatch worse, because now the row had a real button in it and the header
	# above it did not. GREEN stays reserved for genuine status (ready /
	# connected); it was the only green on a gilt-and-ember screen.
	_host_btn = GameTheme.make_themed_button("HOST (LAN)",
		Color(0.78, 0.58, 0.22), Vector2(320, 40), 17)
	_host_btn.tooltip_text = "Start a server on this machine; share your LAN / Tailscale IP."
	_host_btn.pressed.connect(_on_host_pressed)
	GameTheme.arm_ui_press(_host_btn, "commit")
	vb.add_child(_host_btn)

	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 8)
	vb.add_child(addr_row)

	_ip_field = _make_field("127.0.0.1", 220, "Host's LAN / Tailscale IP")
	addr_row.add_child(_ip_field)
	_port_field = _make_field(str(NetMatch.DEFAULT_PORT), 80, "Port")
	addr_row.add_child(_port_field)

	# PLATED, not frameless. `make_back_button` is the house idiom for a retreat
	# and for light confirms, and it is right in most places — but this one sits
	# in a row between two filled LineEdits, so it was the only element in the
	# row without a box and read as a caption printed after the port number
	# rather than as the button that connects you. Same fault as the settings
	# overlay's RESUME: frameless is fine until it stands beside a plate.
	_join_btn = GameTheme.make_themed_button("JOIN", Color(0.78, 0.58, 0.22),
		Vector2(112, 40), 17)
	_join_btn.pressed.connect(_on_join_pressed)
	GameTheme.arm_ui_press(_join_btn, "commit")
	addr_row.add_child(_join_btn)

	return panel


## Chart-language panel stylebox — the house hand-cut plate (ChartPanelStyle:
## deckled edges, corner tacks, drop shadow) so the lobby's tiles sit in the
## same material world as every other screen's document furniture.
func _chart_panel_style(dim: bool) -> StyleBox:
	var s := GameTheme.make_panel_style(
		Color(0.055, 0.048, 0.040, 0.96 if not dim else 0.60),
		Color(0.60, 0.51, 0.34, 0.90 if not dim else 0.35), 1, 3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

## Convert only this screen's explicit ChartPanelStyle overrides. Colors,
## margins, button states, shadow tint, chamfers, and tacks survive; the costly
## deckle/age micro-detail is the part intentionally traded for a batched face.
func _flatten_chart_styles(host: Node) -> void:
	var converted: Dictionary = {}
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			var control := node as Control
			var slots: Array[StringName] = []
			if control is PanelContainer:
				slots.append(&"panel")
			if control is Button:
				slots.append_array([&"normal", &"focus", &"hover", &"pressed", &"disabled"])
			for slot in slots:
				if not control.has_theme_stylebox_override(slot):
					continue
				var source := control.get_theme_stylebox(slot)
				if source is GameTheme.ChartPanelStyle:
					control.add_theme_stylebox_override(slot,
						_fast_chart_style(source, converted))
			for meta_key in [&"style_rest", &"style_sel"]:
				if not control.has_meta(meta_key):
					continue
				var meta_style = control.get_meta(meta_key)
				if meta_style is GameTheme.ChartPanelStyle:
					control.set_meta(meta_key,
						_fast_chart_style(meta_style, converted))
		for child in node.get_children():
			stack.append(child)


func _fast_chart_style(source: GameTheme.ChartPanelStyle,
		converted: Dictionary) -> StyleBox:
	var source_id := source.get_instance_id()
	if converted.has(source_id):
		return converted[source_id]
	var fast := FastChartPanelStyle.new()
	fast.bg_color = source.bg_color
	fast.border_color = source.border_color
	fast.rule_width = source.rule_width
	fast.chamfer = source.chamfer
	fast.shadow = source.shadow
	fast.parchment = source.parchment
	fast.corner_tacks = source.corner_tacks
	fast.shadow_color = source.shadow_color
	fast.shadow_size = source.shadow_size
	fast.content_margin_left = source.get_content_margin(SIDE_LEFT)
	fast.content_margin_top = source.get_content_margin(SIDE_TOP)
	fast.content_margin_right = source.get_content_margin(SIDE_RIGHT)
	fast.content_margin_bottom = source.get_content_margin(SIDE_BOTTOM)
	converted[source_id] = fast
	return fast


## Two-layer engraved sigil (shadow + parchment tint) — the same treatment
## make_choice_banner gives its icons, so the JOIN tile's sword matches.
func _add_engraved_icon(host: Control, path: String, dim: bool) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	for layer in range(2):
		var t := TextureRect.new()
		t.texture = tex
		# IGNORE_SIZE (not FIT_WIDTH_PROPORTIONAL): the icon fills its 56×56 host
		# box and never propagates the texture's native size up the layout, so a
		# big source PNG can't blow the tile out of shape.
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if layer == 0:
			for p in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
				t.set(p, 2.0)
			t.modulate = Color(0, 0, 0, 0.55 if not dim else 0.30)
		else:
			t.modulate = Color(0.82, 0.74, 0.56) if not dim \
				else Color(0.50, 0.48, 0.44, 0.55)
		host.add_child(t)


func _make_field(default_text: String, width: int, placeholder: String) -> LineEdit:
	# Ink-well field: dark parchment recess with a tan hairline (gilt on focus),
	# so text entry sits in the chart language instead of a raw OS rectangle.
	var f := LineEdit.new()
	f.text = default_text
	f.placeholder_text = placeholder
	f.custom_minimum_size = Vector2(width, 40)
	f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameTheme.font_body:
		f.add_theme_font_override("font", GameTheme.font_body)
	f.add_theme_font_size_override("font_size", 18)
	f.add_theme_color_override("font_color", IVORY)
	f.add_theme_color_override("font_placeholder_color", Color(0.60, 0.55, 0.45, 0.65))
	f.add_theme_color_override("caret_color", GILT_BRIGHT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.015, 0.01, 0.85)
	box.border_color = Color(0.60, 0.51, 0.34, 0.75)
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	f.add_theme_stylebox_override("normal", box)
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = GILT_BRIGHT
	f.add_theme_stylebox_override("focus", focus)
	return f


## Selectable mode/format chip — a subtle chart-chip with a tan hairline that
## brightens to gilt on hover. The picker's highlight logic modulates the whole
## chip white (selected) / grey (unselected), so this only defines the rest look.
func _make_pick_chip(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tooltip != "":
		b.tooltip_text = tooltip
	if GameTheme.font_display:
		b.add_theme_font_override("font", GameTheme.font_display)
	b.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	b.add_theme_color_override("font_color", IVORY)
	b.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	var normal := GameTheme.make_panel_style(
		Color(0.055, 0.048, 0.040, 0.92), Color(0.60, 0.51, 0.34, 0.55), 1, 3, false)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("focus", normal)
	var hover := normal.duplicate() as GameTheme.ChartPanelStyle
	hover.border_color = GILT_BRIGHT
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	# Selected face: gilt rule + a lit ground, swapped in by _set_chip_selected —
	# the chosen term reads as chosen, not as the only enabled button.
	var sel := normal.duplicate() as GameTheme.ChartPanelStyle
	sel.border_color = GILT_BRIGHT
	sel.bg_color = Color(0.115, 0.095, 0.062, 0.96)
	b.set_meta("style_rest", normal)
	b.set_meta("style_sel", sel)
	return b


## One labelled scale: LABEL [====o====] N. Returns [slider, numeral] so the
## caller can drive both. A SCALE rather than a chip per value (2026-09-14):
## relics run 0..14, and fifteen 44px chips are 700px of lobby column for what
## is one number — the control has to stay the same size as its ceiling moves.
func _build_count_scale(row: HBoxContainer, label_text: String, max_value: int,
		value: int, on_change: Callable, width: float) -> Array:
	row.add_child(GameTheme.make_label(label_text, 15, IVORY))
	var slider := GameTheme.make_count_slider(0, max_value, value, width)
	slider.value_changed.connect(func(v: float) -> void: on_change.call(int(v)))
	row.add_child(slider)
	# The numeral is the readout the slider cannot give: a grabber position is
	# not a number, and this one has to be exact before START is pressed.
	var num := GameTheme.make_label(str(value), 18, GILT_BRIGHT)
	num.custom_minimum_size = Vector2(26, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(num)
	return [slider, num]


## Build the ARSENAL size row into `host_panel`: RELICS and POTIONS scales on ONE
## line. Both runs are laid out here rather than as two labelled sections because
## the lobby column is already near its budget with MODE / FORMAT / BATTLE STYLE
## — a fourth full section would push READY and START off the plate.
## `relic_parts` / `potion_parts` are filled with [slider, numeral].
func _build_arsenal_picker(host_panel: VBoxContainer, relics_value: int,
		potions_value: int, on_relic: Callable, on_potion: Callable,
		relic_parts: Array, potion_parts: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	host_panel.add_child(row)

	# ARSENAL rides the row as its leading section label rather than taking the
	# centred header line MODE / FORMAT / BATTLE STYLE each get. Measured: the
	# connected-host column already stood at 853px of an 853px budget, so a
	# fourth full section ran READY, the hint and BACK off the bottom of the
	# canvas — and this row already carries two labels of its own, so a third
	# reads as the same kind of thing rather than as a missing heading.
	row.add_child(GameTheme.make_label("ARSENAL", 16, GILT_BRIGHT))
	var head_gap := Control.new()
	head_gap.custom_minimum_size = Vector2(12, 0)
	head_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head_gap)

	relic_parts.clear()
	relic_parts.append_array(_build_count_scale(row, "RELICS",
		SkirmishState.arsenal_relic_max(), relics_value, on_relic, 196.0))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(20, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	potion_parts.clear()
	# The potion scale is narrower because its ceiling is: a 0..4 run given the
	# same 196px would put five stops 49px apart against the relic scale's 14px,
	# and two scales at different densities in one row read as different units.
	potion_parts.append_array(_build_count_scale(row, "POTIONS",
		SkirmishState.arsenal_potion_max(), potions_value, on_potion, 76.0))


## Push a value back onto a scale and its numeral. The slider write is GUARDED:
## setting `value` emits value_changed, which re-enters the handler that called
## this — an unguarded write would loop, and `set_value_no_signal` is the whole
## reason this is a function rather than two lines at each call site.
func _refresh_count_scale(parts: Array, value: int) -> void:
	if parts.size() < 2:
		return
	var slider := parts[0] as HSlider
	var num := parts[1] as Label
	if slider != null and is_instance_valid(slider) \
			and int(slider.value) != value:
		slider.set_value_no_signal(float(value))
	if num != null and is_instance_valid(num):
		num.text = str(value)


## The arsenal terms as a sentence — the numerals alone don't say the thing that
## matters, which is that BOTH sides draft the same count.
func _arsenal_terms_text(relics: int, potions: int) -> String:
	if relics <= 0 and potions <= 0:
		return "No arsenal — both sides fight on their decks alone."
	var parts: Array[String] = []
	if relics > 0:
		parts.append("%d relic%s" % [relics, "" if relics == 1 else "s"])
	if potions > 0:
		parts.append("%d potion%s" % [potions, "" if potions == 1 else "s"])
	return "Each player drafts %s before the deck." % " and ".join(parts)


## Selected-state swap for a pick chip (mode / format / battle style).
func _set_chip_selected(b: Button, on: bool) -> void:
	if b == null or not is_instance_valid(b) or not b.has_meta("style_rest"):
		return
	var style: StyleBox = b.get_meta("style_sel") if on else b.get_meta("style_rest")
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("focus", style)
	b.modulate = Color.WHITE if on else Color(0.62, 0.62, 0.62)


# ─────────────────────────────────────────────────────────────────────────
#  LORD PICKER — pick the character you march as. Cosmetic identity (your
#  portrait on both screens + your emote voice); decks come from the mode.
#  Lives on YOU plate as a row of small chips under the big portrait.
# ─────────────────────────────────────────────────────────────────────────

## The row of five lord chips (left plate). Clicking one repaints the plate's
## big portrait and ships the pick to the opponent.
func _build_hero_chips() -> Control:
	_hero_buttons.clear()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)

	for hid in HeroDB.HERO_ORDER:
		var hero := HeroDB.get_hero(hid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s — %s" % [String(hero.get("name", hid)),
			String(hero.get("tagline", ""))]
		var normal := GameTheme.make_panel_style(
			Color(0.055, 0.048, 0.040, 0.92), Color(0.60, 0.51, 0.34, 0.55), 1, 3, false)
		var hover := normal.duplicate() as GameTheme.ChartPanelStyle
		hover.border_color = GILT_BRIGHT
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("focus", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		var port_path := "res://assets/portraits/hero_portrait_%s.png" % hid
		if ResourceLoader.exists(port_path):
			var tex := TextureRect.new()
			tex.texture = load(port_path)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tex.clip_contents = true
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex.offset_left = 3
			tex.offset_top = 3
			tex.offset_right = -3
			tex.offset_bottom = -3
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(tex)
		else:
			# No painted portrait — a monogram keeps the chip legible (MainMenu's
			# graceful-degrade convention).
			b.text = String(hero.get("name", hid)).strip_edges().left(1).to_upper()
			if GameTheme.font_display:
				b.add_theme_font_override("font", GameTheme.font_display)
			b.add_theme_font_size_override("font_size", 24)
			b.add_theme_color_override("font_color", GILT_BRIGHT)
		b.pressed.connect(_on_hero_chosen.bind(hid))
		row.add_child(b)
		_hero_buttons[hid] = b

	_refresh_hero_ui()
	return row


func _on_hero_chosen(hid: String) -> void:
	_selected_hero = hid
	NetMatch.set_local_hero(hid)   # stores locally + ships to the opponent
	_refresh_hero_ui()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# A small pop on the banner sells the swap — the standard reacts to the pick.
	if _your_portrait != null and is_instance_valid(_your_portrait):
		_flash_pick(_your_portrait.get_parent() as Control)


## Quick scale pop (decorative — held still under Reduce Motion). Scale is a
## render transform, so it never reflows the plate.
func _flash_pick(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.04, 1.04), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)


## Repaint both banner plates: your portrait/name/tagline + chip highlight on
## the left, the challenger's seat (empty mark / bot / their lord) on the right.
func _refresh_hero_ui() -> void:
	for hid in _hero_buttons:
		var b: Button = _hero_buttons[hid]
		if is_instance_valid(b):
			b.modulate = Color.WHITE if hid == _selected_hero \
				else Color(0.45, 0.45, 0.45)

	if _your_portrait != null and is_instance_valid(_your_portrait):
		var mine := HeroDB.get_hero(_selected_hero)
		_set_plate_portrait(_your_portrait, _selected_hero)
		_your_name_label.text = String(mine.get("name", _selected_hero)).to_upper()
		_your_tagline.text = String(mine.get("tagline", ""))

	_refresh_challenger_plate()


## The right plate's three states: empty seat / practice bot / a live opponent.
func _refresh_challenger_plate() -> void:
	if _opp_portrait == null or not is_instance_valid(_opp_portrait):
		return
	# Only a live opponent with a chosen lord fills the seat with a portrait; the
	# bot and the empty/awaiting states keep the engraved sword.
	var shown := false
	var was_shown := _opp_shown
	if _challenger_is_bot:
		_opp_name_label.text = "THE PRACTICE BOT"
		_opp_tagline.text = "A local AI opponent."
	elif not NetMatch.remote_present:
		_opp_name_label.text = "—"
		_opp_tagline.text = "Waiting for an opponent…"
	elif NetMatch.remote_hero == "":
		_opp_name_label.text = "…"
		_opp_tagline.text = "Choosing a hero…"
	else:
		var theirs := HeroDB.get_hero(NetMatch.remote_hero)
		_set_plate_portrait(_opp_portrait, NetMatch.remote_hero)
		_opp_name_label.text = String(theirs.get("name", NetMatch.remote_hero)).to_upper()
		_opp_tagline.text = String(theirs.get("tagline", ""))
		shown = true

	_opp_portrait.visible = shown
	_opp_empty_box.visible = not shown
	if _opp_glow != null and is_instance_valid(_opp_glow):
		_opp_glow.visible = shown

	# When a challenger's portrait first rises into the empty seat, fade it in.
	if shown and not was_shown \
			and not (UserSettings != null and UserSettings.reduce_motion):
		_opp_portrait.modulate.a = 0.0
		_opp_portrait.create_tween().tween_property(
			_opp_portrait, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	_opp_shown = shown
	if shown != was_shown:
		if shown:
			# Defer once so the newly visible well has its final layout size.
			call_deferred("_set_opponent_plate_life", true)
		else:
			_set_opponent_plate_life(false)


func _set_plate_portrait(port: TextureRect, hid: String) -> void:
	var path := "res://assets/portraits/hero_portrait_%s.png" % hid
	port.texture = load(path) if ResourceLoader.exists(path) else null


# ─────────────────────────────────────────────────────────────────────────
#  NET SIGNAL WIRING
# ─────────────────────────────────────────────────────────────────────────

func _wire_net_signals() -> void:
	NetMatch.peer_joined.connect(_on_peer_joined)
	NetMatch.connected_to_host.connect(_on_connected_to_host)
	NetMatch.connection_failed.connect(_on_connection_failed)
	NetMatch.host_closed.connect(_on_host_closed)
	NetMatch.peer_left.connect(_on_peer_left)
	NetMatch.ready_state_changed.connect(_refresh_ready_labels)
	NetMatch.hero_state_changed.connect(_refresh_hero_ui)
	NetMatch.match_starting.connect(_on_match_starting)
	NetMatch.match_config_changed.connect(_on_match_config_changed)
	NetMatch.room_created.connect(_on_room_created)
	NetMatch.room_error.connect(_on_room_error)
	NetMatch.protocol_rejected.connect(_on_protocol_rejected)


# ── Button handlers ──

## Online HOST: open a room on the relay; the code arrives via `room_created`.
func _on_host_online_pressed() -> void:
	if _relay_host == "":
		_set_status("Online play isn't available — use Same network / direct IP instead.", RED)
		return
	var err := NetMatch.host_via_relay(_relay_host, NetMatch.RELAY_PORT_DEFAULT)
	if err != OK:
		_set_status("Couldn't reach the relay (error %d) — check your connection, or use direct IP." % err, RED)
		return
	_set_status("Opening a room on the relay…", GILT_BRIGHT)
	_set_connect_buttons_enabled(false)


## Online JOIN: connect to the relay and claim the friend's room by its code.
func _on_join_online_pressed() -> void:
	if _relay_host == "":
		_set_status("Online play isn't available — use Same network / direct IP instead.", RED)
		return
	var code := _code_field.text.strip_edges().to_upper()
	if code.length() != NetMatch.ROOM_CODE_LEN:
		_set_status("Enter the %d-character room code your friend shared." % NetMatch.ROOM_CODE_LEN, RED)
		return
	var err := NetMatch.join_via_relay(_relay_host, NetMatch.RELAY_PORT_DEFAULT, code)
	if err != OK:
		_set_status("Couldn't reach the relay (error %d) — check your connection, or use direct IP." % err, RED)
		return
	_set_status("Joining room %s…" % code, GILT_BRIGHT)
	_set_connect_buttons_enabled(false)


## Keep the room-code field uppercase as the player types (caret-safe).
func _on_code_typed(new_text: String) -> void:
	var up := new_text.to_upper()
	if up != new_text:
		var caret := _code_field.caret_column
		_code_field.text = up
		_code_field.caret_column = caret


func _on_lan_toggle_pressed() -> void:
	_lan_panel.visible = not _lan_panel.visible
	_lan_toggle.text = "Same network / direct IP  " + ("▴" if _lan_panel.visible else "▾")


func _on_host_pressed() -> void:
	var port := _read_port()
	var err := NetMatch.host(port)
	if err != OK:
		_set_status("Port %d wouldn't open (error %d) — another program may be using it." % [port, err], RED)
		return
	_set_status("Hosting on port %d — waiting for a friend…" % port, GILT_BRIGHT)
	_hint_label.text = _host_address_hint(port)
	_connect_panel.visible = false
	_show_ready_panel()


## Build the host's "tell your friend this address" hint. Reads the machine's own
## IPv4 addresses and labels them: a Tailscale overlay IP (100.64.0.0/10 — works
## across different WiFi over the internet) is shown FIRST and is the one to send a
## remote friend; private LAN IPs (same WiFi only) and any other routable address
## follow. Loopback / link-local / IPv6 are skipped.
func _host_address_hint(port: int) -> String:
	var tailscale: Array[String] = []
	var lan: Array[String] = []
	var other: Array[String] = []
	for addr in IP.get_local_addresses():
		if ":" in addr:                                   # IPv6 — skip
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue                                      # loopback / link-local
		var parts := addr.split(".")
		if parts.size() != 4:
			continue
		var o0 := int(parts[0])
		var o1 := int(parts[1])
		if o0 == 100 and o1 >= 64 and o1 <= 127:          # Tailscale CGNAT range
			tailscale.append(addr)
		elif o0 == 10 or (o0 == 192 and o1 == 168) or (o0 == 172 and o1 >= 16 and o1 <= 31):
			lan.append(addr)
		else:
			other.append(addr)
	var lines: Array[String] = []
	if not tailscale.is_empty():
		lines.append("Over the internet (Tailscale) — send your friend:  %s : %d"
			% [", ".join(tailscale), port])
	if not lan.is_empty():
		lines.append("Same WiFi/LAN:  %s : %d" % [", ".join(lan), port])
	if not other.is_empty():
		lines.append("Other:  %s : %d" % [", ".join(other), port])
	if tailscale.is_empty():
		lines.append("No Tailscale address found — to play across different WiFi, "
			+ "install Tailscale on both PCs and this line will show the address to send.")
	lines.append("Your friend picks Join and enters the matching address + port.")
	return "\n".join(lines)


func _on_join_pressed() -> void:
	var ip := _ip_field.text.strip_edges()
	if ip == "":
		_set_status("Enter the host's address first.", RED)
		return
	var port := _read_port()
	var err := NetMatch.join(ip, port)
	if err != OK:
		_set_status("Couldn't start the connection (error %d) — check the address and port." % err, RED)
		return
	_set_status("Connecting to %s:%d…" % [ip, port], GILT_BRIGHT)
	_host_btn.disabled = true
	_join_btn.disabled = true


func _on_ready_pressed() -> void:
	if not _scene_exit_locked and not _match_start_requested:
		NetMatch.set_local_ready(not NetMatch.local_ready)


func _on_start_pressed() -> void:
	if _scene_exit_locked or _match_start_requested \
			or not NetMatch.is_host or not NetMatch.both_ready():
		return
	_match_start_requested = true
	if _start_btn != null:
		_start_btn.disabled = true
	NetMatch.start_match()


func _on_back_pressed() -> void:
	# START emits locally and ships remotely in the same commit. Once pressed,
	# Back must not tear down the peer before the match-start signal is handled.
	if _match_start_requested or not _claim_lobby_exit(_back_btn):
		return
	NetMatch.leave()
	_change_scene_with_ink(MENU_SCENE, _back_btn, Vector2(0.08, 0.10))


func _go_to_deck_scene(target: String, source: Control = null) -> void:
	if not _claim_lobby_exit(source):
		return
	_change_scene_with_ink(target, source, Vector2(0.50, 0.54))


func _claim_lobby_exit(source: Control = null) -> bool:
	if _scene_exit_locked:
		return false
	_scene_exit_locked = true
	for button in [_ready_btn, _start_btn, _vsbot_begin_btn, _back_btn, source]:
		if button != null and is_instance_valid(button) and button is BaseButton:
			(button as BaseButton).disabled = true
	return true


func _change_scene_with_ink(target: String, source: Control,
		fallback_origin: Vector2) -> void:
	var can_animate := DisplayServer.get_name() != "headless" \
		and (UserSettings == null or not UserSettings.reduce_motion)
	if can_animate:
		GameTheme.fade_out_then_change_scene(self, target, 0.30,
			_lobby_transition_origin(source, fallback_origin))
	else:
		get_tree().change_scene_to_file(target)


func _lobby_transition_origin(source: Control, fallback: Vector2) -> Vector2:
	if source == null or not is_instance_valid(source) \
			or not source.is_visible_in_tree():
		return fallback
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return fallback
	var center := source.global_position + source.size * 0.5
	return Vector2(center.x / viewport_size.x, center.y / viewport_size.y)


# ── Net event handlers ──

## Relay assigned our shareable room code (host, online). Show it large and move on
## to the ready panel — the host reads the code to their friend while waiting.
func _on_room_created(code: String) -> void:
	_room_code_raw = code
	var spaced := ""
	for ch in code:
		spaced += String(ch) + "  "
	_code_label.text = spaced.strip_edges()
	_code_plate.visible = true
	GameTheme.deal_in(_code_plate)
	_set_status("Room open — share this code with your friend:", GREEN)
	_hint_label.text = "Your friend picks Join, enters this code, and presses Connect. Then both press Ready and you press Start Match."
	_connect_panel.visible = false
	_show_ready_panel()


## Relay rejected our code (bad / full / closed). `_rpc_room_error` already called
## leave(), so we're cleanly disconnected — let the player try another code.
func _on_room_error(reason: String) -> void:
	_set_status(reason if reason != "" else "That room code didn't work.", RED)
	_set_connect_buttons_enabled(true)


## A version-mismatch handshake tears the link down silently (NetMatch calls
## leave(), which emits no failure signal), so the lobby used to sit on
## "Connecting…" forever with nothing to act on. Surface that one case — the rest
## of the protocol_rejected reasons are per-message diagnostics, not lobby states.
func _on_protocol_rejected(reason: String) -> void:
	if reason != "protocol_handshake":
		return
	var why := NetMatch.last_error
	_set_status(why if why != "" else "The other player is running a different version of the game.", RED)
	_reset_to_connect_panel()


func _on_peer_joined(_id: int) -> void:
	_set_status("An opponent joined your room.", GREEN)
	_hint_label.text = "Both players press Ready, then you (the host) press Start Match."
	_show_ready_panel()


func _on_connected_to_host() -> void:
	_set_status("Connected — you're in the host's room.", GREEN)
	_hint_label.text = "Press Ready — the host starts the match."
	_connect_panel.visible = false
	_show_ready_panel()


func _on_connection_failed() -> void:
	_set_status("No answer — check the address, and that your friend is still hosting.", RED)
	_reset_to_connect_panel()


func _on_host_closed() -> void:
	_set_status("The host closed the room. Join another, or open your own.", RED)
	_reset_to_connect_panel()


func _on_peer_left(_id: int) -> void:
	_set_status("Your opponent disconnected — host or join again to play on.", RED)
	_reset_to_connect_panel()


func _on_match_starting(_seed: int) -> void:
	# Route to the chosen mode's deck-acquisition scene (host's pick, synced via
	# NetMatch.match_mode). Falls back to the draft if that scene isn't in the build.
	var scene := SkirmishState.mode_scene(NetMatch.match_mode)
	if not ResourceLoader.exists(scene) and ResourceLoader.exists(DRAFT_SCENE):
		_set_status("That mode is unavailable — starting a Draft instead.", GREEN)
		scene = DRAFT_SCENE
	if not ResourceLoader.exists(scene):
		_match_start_requested = false
		_set_status("Ready — but no deck screen could be opened. Press Back.", RED)
		_refresh_ready_labels()
		return
	_match_start_requested = true
	var source: Control = null
	if _start_btn != null and _start_btn.is_visible_in_tree():
		source = _start_btn
	_go_to_deck_scene(scene, source)


# ─────────────────────────────────────────────────────────────────────────
#  STATE / DISPLAY
# ─────────────────────────────────────────────────────────────────────────

func _show_ready_panel() -> void:
	_ready_panel.visible = true
	# START is host-only; the client never sees an enabled start button.
	_start_btn.visible = NetMatch.is_host
	# Make sure a lord is always on the wire — an untouched picker still commits
	# the highlighted default (late-join catch-up re-sends it if the peer arrives
	# after this).
	if NetMatch.local_hero == "":
		NetMatch.set_local_hero(_selected_hero)
	_populate_mode_panel()
	_refresh_ready_labels()
	_refresh_hero_ui()


# ─────────────────────────────────────────────────────────────────────────
#  MODE / FORMAT PICKER  (host picks; client sees the choice)
# ─────────────────────────────────────────────────────────────────────────

func _populate_mode_panel() -> void:
	if _mode_panel == null:
		return
	for c in _mode_panel.get_children():
		c.queue_free()
	_mode_buttons.clear()
	_bo_buttons.clear()
	_ars_relic_parts.clear()
	_ars_potion_parts.clear()
	_mode_info_label = null
	_arsenal_info_label = null
	if NetMatch.is_host:
		_build_host_mode_picker()
		# Broadcast the current selection so a connected client shows it at once.
		NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style,
			_selected_ars_relics, _selected_ars_potions)
	else:
		_build_client_mode_display()


func _build_host_mode_picker() -> void:
	var ml := GameTheme.make_label("MODE", 16, GILT_BRIGHT)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(ml)

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	_mode_panel.add_child(mode_row)
	# Only offer modes whose scene exists in this build. If the host's last pick is
	# no longer available, fall back to the first offered mode.
	var modes := SkirmishState.available_modes()
	if not modes.has(_selected_mode):
		_selected_mode = int(modes[0])
	for mode in modes:
		var b := _make_pick_chip(SkirmishState.mode_name(mode).to_upper(),
			SkirmishState.mode_blurb(mode))
		b.pressed.connect(_on_mode_chosen.bind(mode))
		mode_row.add_child(b)
		_mode_buttons[mode] = b

	var fl := GameTheme.make_label("FORMAT", 16, GILT_BRIGHT)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(fl)

	var bo_row := HBoxContainer.new()
	bo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bo_row.add_theme_constant_override("separation", 8)
	_mode_panel.add_child(bo_row)
	for bo in [1, 3]:
		var b2 := _make_pick_chip("SINGLE GAME" if bo == 1 else "BEST OF 3")
		b2.pressed.connect(_on_best_of_chosen.bind(bo))
		bo_row.add_child(b2)
		_bo_buttons[bo] = b2

	var sl := GameTheme.make_label("BATTLE STYLE", 16, GILT_BRIGHT)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(sl)

	var style_row := HBoxContainer.new()
	style_row.alignment = BoxContainer.ALIGNMENT_CENTER
	style_row.add_theme_constant_override("separation", 8)
	_mode_panel.add_child(style_row)
	for st in [NetMatch.STYLE_ALTERNATING, NetMatch.STYLE_SEALED]:
		var b3 := _make_pick_chip(
			"ALTERNATING" if st == NetMatch.STYLE_ALTERNATING else "SEALED ORDERS",
			"Take turns — your line strikes when your turn ends"
				if st == NetMatch.STYLE_ALTERNATING
				else "Both place in secret, reveal together, one clash per round")
		b3.pressed.connect(_on_style_chosen.bind(st))
		style_row.add_child(b3)
		_style_buttons[st] = b3

	# ARSENAL — how many relic and potion picks the opening stage offers. The host
	# sets it for BOTH sides; there is deliberately no per-player number, or the
	# player who happened to host would be choosing their own item advantage.
	_build_arsenal_picker(_mode_panel, _selected_ars_relics, _selected_ars_potions,
		_on_ars_relics_chosen, _on_ars_potions_chosen,
		_ars_relic_parts, _ars_potion_parts)
	_arsenal_info_label = GameTheme.make_label("", 14, ASH)
	_arsenal_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_arsenal_info_label)

	_refresh_host_picker_highlight()
	_flatten_chart_styles(_mode_panel)


func _on_mode_chosen(mode: int) -> void:
	_selected_mode = mode
	_push_match_config()


func _on_best_of_chosen(bo: int) -> void:
	_selected_best_of = bo
	_push_match_config()


func _on_style_chosen(st: int) -> void:
	_selected_style = st
	_push_match_config()


func _on_ars_relics_chosen(n: int) -> void:
	_selected_ars_relics = n
	_push_match_config()


func _on_ars_potions_chosen(n: int) -> void:
	_selected_ars_potions = n
	_push_match_config()


## One funnel for every host pick: commit the whole config (it crosses the wire
## as one message, so a partial send could leave the client showing terms the
## host has already changed) and relight the chips.
func _push_match_config() -> void:
	NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style,
		_selected_ars_relics, _selected_ars_potions)
	_refresh_host_picker_highlight()


func _refresh_host_picker_highlight() -> void:
	for mode in _mode_buttons:
		_set_chip_selected(_mode_buttons[mode], mode == _selected_mode)
	for bo in _bo_buttons:
		_set_chip_selected(_bo_buttons[bo], bo == _selected_best_of)
	for st in _style_buttons:
		_set_chip_selected(_style_buttons[st], st == _selected_style)
	_refresh_count_scale(_ars_relic_parts, _selected_ars_relics)
	_refresh_count_scale(_ars_potion_parts, _selected_ars_potions)
	if _arsenal_info_label != null and is_instance_valid(_arsenal_info_label):
		_arsenal_info_label.text = _arsenal_terms_text(
			_selected_ars_relics, _selected_ars_potions)


# ─────────────────────────────────────────────────────────────────────────
#  PRACTICE vs BOT (offline) — pick a mode/format, then run the normal deck
#  scene + combat with NetMatch.vs_bot set (no peer; SkirmishBot drives slot 1).
# ─────────────────────────────────────────────────────────────────────────

func _on_vs_bot_pressed() -> void:
	_connect_panel.visible = false
	if _lan_panel != null:
		_lan_panel.visible = false
	_vs_bot_panel.visible = true
	# The challenger plate takes the bot's seat while the drill is being set up.
	_challenger_is_bot = true
	_refresh_challenger_plate()
	# The sub-panel carries its own BACK (returns to the lobby choices), so hide
	# the outer leave-to-menu BACK — one back button, one meaning.
	if _back_btn != null:
		_back_btn.visible = false
	_populate_vs_bot_panel()
	_set_status("Practice match — pick a mode, then Begin.", GILT_BRIGHT)


func _populate_vs_bot_panel() -> void:
	for c in _vs_bot_panel.get_children():
		c.queue_free()
	_vsbot_mode_buttons.clear()
	_vsbot_bo_buttons.clear()
	_vsbot_arsenal_info = null   # the panel's children were just queue_freed
	_vsbot_ars_relic_parts.clear()
	_vsbot_ars_potion_parts.clear()

	_vs_bot_panel.add_child(GameTheme.make_section_divider(
		"THE DRILL", GameTheme.GILT, 17, 130.0))

	var ml := GameTheme.make_label("MODE", 16, GILT_BRIGHT)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_bot_panel.add_child(ml)
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 8)
	_vs_bot_panel.add_child(mode_row)
	var modes := SkirmishState.available_modes()
	if not modes.has(_vsbot_mode):
		_vsbot_mode = int(modes[0])
	for mode in modes:
		var b := _make_pick_chip(SkirmishState.mode_name(mode).to_upper(),
			SkirmishState.mode_blurb(mode))
		b.pressed.connect(_on_vsbot_mode_chosen.bind(mode))
		mode_row.add_child(b)
		_vsbot_mode_buttons[mode] = b

	var fl := GameTheme.make_label("FORMAT", 16, GILT_BRIGHT)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_bot_panel.add_child(fl)
	var bo_row := HBoxContainer.new()
	bo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bo_row.add_theme_constant_override("separation", 8)
	_vs_bot_panel.add_child(bo_row)
	for bo in [1, 3]:
		var b2 := _make_pick_chip("SINGLE GAME" if bo == 1 else "BEST OF 3")
		b2.pressed.connect(_on_vsbot_bo_chosen.bind(bo))
		bo_row.add_child(b2)
		_vsbot_bo_buttons[bo] = b2

	var sl := GameTheme.make_label("BATTLE STYLE", 16, GILT_BRIGHT)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_bot_panel.add_child(sl)
	var style_row := HBoxContainer.new()
	style_row.alignment = BoxContainer.ALIGNMENT_CENTER
	style_row.add_theme_constant_override("separation", 8)
	_vs_bot_panel.add_child(style_row)
	for st in [NetMatch.STYLE_ALTERNATING, NetMatch.STYLE_SEALED]:
		var b3 := _make_pick_chip(
			"ALTERNATING" if st == NetMatch.STYLE_ALTERNATING else "SEALED ORDERS")
		b3.pressed.connect(_on_vsbot_style_chosen.bind(st))
		style_row.add_child(b3)
		_vsbot_style_buttons[st] = b3

	# The drill runs the same arsenal stage as a real match — you are the host of
	# a one-player room, so the terms are yours to set here too. (The bot drafts
	# the same number of relics from its own board-only pool and no potions.)
	_build_arsenal_picker(_vs_bot_panel, _vsbot_ars_relics, _vsbot_ars_potions,
		_on_vsbot_ars_relics_chosen, _on_vsbot_ars_potions_chosen,
		_vsbot_ars_relic_parts, _vsbot_ars_potion_parts)
	_vsbot_arsenal_info = GameTheme.make_label("", 14, ASH)
	_vsbot_arsenal_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_bot_panel.add_child(_vsbot_arsenal_info)

	_vs_bot_panel.add_child(GameTheme.make_separator(GILT_BRIGHT, 300.0))

	_vsbot_begin_btn = GameTheme.make_back_button("BEGIN", Vector2(220, 46), 18, GILT_BRIGHT)
	_vsbot_begin_btn.pressed.connect(_on_vs_bot_begin)
	_vs_bot_panel.add_child(_vsbot_begin_btn)

	var back := GameTheme.make_back_button("BACK", Vector2(160, 38), 15)
	back.pressed.connect(_on_vs_bot_back)
	_vs_bot_panel.add_child(back)

	_refresh_vsbot_highlight()
	_flatten_chart_styles(_vs_bot_panel)


func _on_vsbot_mode_chosen(mode: int) -> void:
	_vsbot_mode = mode
	_refresh_vsbot_highlight()


func _on_vsbot_bo_chosen(bo: int) -> void:
	_vsbot_bo = bo
	_refresh_vsbot_highlight()


func _on_vsbot_style_chosen(st: int) -> void:
	_vsbot_style = st
	_refresh_vsbot_highlight()


func _on_vsbot_ars_relics_chosen(n: int) -> void:
	_vsbot_ars_relics = n
	_refresh_vsbot_highlight()


func _on_vsbot_ars_potions_chosen(n: int) -> void:
	_vsbot_ars_potions = n
	_refresh_vsbot_highlight()


func _refresh_vsbot_highlight() -> void:
	for mode in _vsbot_mode_buttons:
		_set_chip_selected(_vsbot_mode_buttons[mode], mode == _vsbot_mode)
	for bo in _vsbot_bo_buttons:
		_set_chip_selected(_vsbot_bo_buttons[bo], bo == _vsbot_bo)
	for st in _vsbot_style_buttons:
		_set_chip_selected(_vsbot_style_buttons[st], st == _vsbot_style)
	_refresh_count_scale(_vsbot_ars_relic_parts, _vsbot_ars_relics)
	_refresh_count_scale(_vsbot_ars_potion_parts, _vsbot_ars_potions)
	if _vsbot_arsenal_info != null and is_instance_valid(_vsbot_arsenal_info):
		# "Each player" is literally true in a drill: the bot's own arsenal now
		# follows the same setting (it drafts from BOT_RELIC_POOL and never drinks,
		# so its potion count is always zero).
		_vsbot_arsenal_info.text = _arsenal_terms_text(
			_vsbot_ars_relics, _vsbot_ars_potions)


func _on_vs_bot_back() -> void:
	_vs_bot_panel.visible = false
	_connect_panel.visible = true
	_challenger_is_bot = false
	_refresh_challenger_plate()
	# Restore the direct-IP panel to its default open/closed state (open in the
	# no-relay build, where it's the friend path; collapsed behind the toggle otherwise).
	if _lan_panel != null:
		_lan_panel.visible = _lan_default_open
	if _back_btn != null:
		_back_btn.visible = true
	_refresh_state()


func _on_vs_bot_begin() -> void:
	if _scene_exit_locked:
		return
	var scene := SkirmishState.mode_scene(_vsbot_mode)
	if not ResourceLoader.exists(scene):
		scene = DRAFT_SCENE
	if not ResourceLoader.exists(scene):
		_set_status("No deck screen could be opened.", RED)
		return
	# No peer to sync with — set the style + lord directly before the local start
	# (start_vs_bot reads local_hero to roll a non-mirror bot lord).
	NetMatch.battle_style = _vsbot_style
	NetMatch.local_hero = _selected_hero
	# The arsenal size goes THROUGH start_vs_bot: it calls leave() first, which
	# restores the defaults, so writing the fields beside battle_style above would
	# be erased before the drill ever read them.
	NetMatch.start_vs_bot(_vsbot_mode, _vsbot_bo,
		_vsbot_ars_relics, _vsbot_ars_potions)
	_go_to_deck_scene(scene, _vsbot_begin_btn)


func _build_client_mode_display() -> void:
	_mode_info_label = GameTheme.make_label("", 16, IVORY)
	_mode_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_mode_info_label)
	# The arsenal terms get their own line: they are the one setting that decides
	# what the client's NEXT screen asks it to do, so it must not be a fourth
	# clause running off the end of a sentence.
	_arsenal_info_label = GameTheme.make_label("", 15, ASH)
	_arsenal_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_arsenal_info_label)
	_refresh_client_mode_display()


func _refresh_client_mode_display() -> void:
	if _mode_info_label == null:
		return
	_mode_info_label.text = "Host chose:  %s  ·  %s  ·  %s" % [
		SkirmishState.mode_name(NetMatch.match_mode),
		"Best of 3" if NetMatch.best_of == 3 else "Single game",
		"Sealed Orders" if NetMatch.battle_style == NetMatch.STYLE_SEALED else "Alternating"]
	if _arsenal_info_label != null and is_instance_valid(_arsenal_info_label):
		_arsenal_info_label.text = _arsenal_terms_text(
			NetMatch.arsenal_relics, NetMatch.arsenal_potions)


func _on_match_config_changed() -> void:
	# Client side only: the host changed the mode/format — refresh the display.
	if not NetMatch.is_host:
		_refresh_client_mode_display()


func _reset_to_connect_panel() -> void:
	if not _scene_exit_locked:
		_match_start_requested = false
	_connect_panel.visible = true
	_ready_panel.visible = false
	_code_plate.visible = false
	_room_code_raw = ""
	_set_connect_buttons_enabled(true)
	_start_btn.disabled = true
	_refresh_ready_labels()
	_refresh_challenger_plate()


## Enable/disable the connect buttons together. Online tiles are only built when
## a relay is configured, so their refs may be null (guarded); the direct-IP
## HOST/JOIN in the LAN panel are always present.
func _set_connect_buttons_enabled(on: bool) -> void:
	var online_ok := on and _relay_host != ""

	if _host_online_btn != null:
		_host_online_btn.disabled = not online_ok
	if _join_online_btn != null:
		_join_online_btn.disabled = not online_ok
	if _host_btn != null:
		_host_btn.disabled = not on
	if _join_btn != null:
		_join_btn.disabled = not on


func _refresh_state() -> void:
	# The status line stays quiet at rest — it fills with the host address / room
	# code once a match is actually being set up.
	if _relay_host == "":
		_set_status("Drill against the bot, or connect directly to a friend on your network.", IVORY)
	else:
		_set_status("Host a room and share the code, or join a friend's.", IVORY)
	_hint_label.text = ""
	_set_connect_buttons_enabled(true)


## The ready states are stamped as seals on the two banner plates (the column
## keeps only the READY / START actions).
func _refresh_ready_labels() -> void:
	var in_lobby := _ready_panel != null and _ready_panel.visible
	if _your_seal != null and is_instance_valid(_your_seal):
		_your_seal.text = ("READY" if NetMatch.local_ready else "not ready") \
			if in_lobby else ""
		_your_seal.add_theme_color_override("font_color",
			GREEN if NetMatch.local_ready else ASH)
	if _opp_seal != null and is_instance_valid(_opp_seal):
		var opp_txt := ""
		var opp_col := ASH
		if in_lobby:
			if not NetMatch.remote_present:
				opp_txt = "—"
			elif NetMatch.remote_ready:
				opp_txt = "READY"
				opp_col = GREEN
			else:
				opp_txt = "not ready"
		_opp_seal.text = opp_txt
		_opp_seal.add_theme_color_override("font_color", opp_col)

	if _ready_btn != null:
		_ready_btn.text = "UNREADY" if NetMatch.local_ready else "READY"

	# Host can start once both sides are ready.
	if NetMatch.is_host and _start_btn != null:
		_start_btn.disabled = not NetMatch.both_ready() \
			or _match_start_requested or _scene_exit_locked


func _set_status(msg: String, color: Color) -> void:
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", color)


func _read_port() -> int:
	var p := int(_port_field.text.strip_edges())
	return p if p > 0 and p < 65536 else NetMatch.DEFAULT_PORT
