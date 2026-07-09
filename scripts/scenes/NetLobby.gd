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
const GREEN := Color(0.55, 0.85, 0.45, 1.0)
const RED := Color(0.90, 0.45, 0.35, 1.0)
const AZURE := Color(0.52, 0.68, 0.95, 1.0)   # join accent (answer-the-call blue)
const EMBER := Color(0.90, 0.62, 0.30, 1.0)   # practice / drill accent

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
var _you_ready_label: Label
var _opp_ready_label: Label
var _relay_host: String = ""        # resolved relay address (empty = online disabled)

# ── Mode / format picker (host picks; client sees the choice) ──
var _mode_panel: VBoxContainer       # built on connect (host buttons / client label)
var _mode_buttons: Dictionary = {}   # MatchMode id -> Button (host only)
var _bo_buttons: Dictionary = {}     # best_of value (1/3) -> Button (host only)
var _style_buttons: Dictionary = {}  # NetMatch.STYLE_* -> Button (host only)
var _mode_info_label: Label          # client: shows the host's chosen mode/format
var _selected_mode: int = 0          # host's current pick (SkirmishState.MatchMode)
var _selected_best_of: int = 1       # host's current pick (1 or 3)
var _selected_style: int = 0         # host's current pick (NetMatch.STYLE_*)

# ── Practice vs Bot (offline; no peer) ──
var _vs_bot_btn: Button
var _vs_bot_panel: VBoxContainer
var _vsbot_mode: int = 0
var _vsbot_bo: int = 1
var _vsbot_style: int = 0
var _vsbot_mode_buttons: Dictionary = {}
var _vsbot_bo_buttons: Dictionary = {}
var _vsbot_style_buttons: Dictionary = {}


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	# The muster pool: quiet war-council medieval, shared by every skirmish
	# prep screen (lobby, quick-match, draft, sealed, constructed).
	AudioBank.play_music_random(["map_c", "map_d", "rest_c"])
	_relay_host = NetMatch.get_relay_host()
	# Fresh lobby: drop any stale connection from a previous visit.
	NetMatch.leave()
	_build_ui()
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
	var col := VBoxContainer.new()
	col.name = "Lobby"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 13)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -430
	col.offset_right = 430
	col.offset_top = -330
	col.offset_bottom = 330
	add_child(col)

	col.add_child(GameTheme.make_screen_title("SKIRMISH", GILT_BRIGHT))

	var blurb := GameTheme.make_label(
		"Duel a friend anywhere — or drill against a bot.", 16, ASH)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(blurb)

	# ── Connect panel (host / join / practice) ──
	_connect_panel = VBoxContainer.new()
	_connect_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_panel.add_theme_constant_override("separation", 11)
	col.add_child(_connect_panel)

	# Whether the relay is wired into this build. When it isn't, the two online
	# tiles render greyed with the reason printed on them (honest dead-state)
	# rather than as live-looking buttons that only flash a red error on click.
	var online_ok := _relay_host != ""
	var online_reason := "" if online_ok else \
		"Online isn't wired into this build yet — use the direct-IP option below."

	# ── Face a friend: HOST and JOIN as two matched chart panels, side by side ──
	_connect_panel.add_child(GameTheme.make_section_divider("FACE A FRIEND", GameTheme.GILT, 17, 130.0))

	var duel_row := HBoxContainer.new()
	duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	duel_row.add_theme_constant_override("separation", 18)
	_connect_panel.add_child(duel_row)

	var host_tile := _build_host_tile(online_ok, online_reason)
	_host_online_btn = host_tile.get_node("ClickButton")
	_host_online_btn.pressed.connect(_on_host_online_pressed)
	duel_row.add_child(host_tile)

	duel_row.add_child(_build_join_tile(online_ok, online_reason))

	# ── Or drill solo: one wide practice banner ──
	_connect_panel.add_child(GameTheme.make_section_divider("OR DRILL SOLO", GameTheme.GILT, 17, 130.0))
	var bot_banner := GameTheme.make_choice_banner(
		"PRACTICE vs BOT",
		"Play any mode against a local AI opponent — no connection needed.",
		EMBER, "res://assets/icons/shield.png", Vector2(802, 90))
	_vs_bot_btn = bot_banner.get_node("ClickButton")
	_vs_bot_btn.pressed.connect(_on_vs_bot_pressed)
	_connect_panel.add_child(bot_banner)

	# ── Advanced: quiet frameless toggle that unfolds the direct-IP controls ──
	_lan_toggle = GameTheme.make_back_button("Same network / direct IP  ▾",
		Vector2(300, 32), 14, ASH)
	_lan_toggle.tooltip_text = "Play over a LAN or a Tailscale address with no relay — best on the same WiFi."
	_lan_toggle.pressed.connect(_on_lan_toggle_pressed)
	_connect_panel.add_child(_lan_toggle)

	_lan_panel = _build_lan_panel()
	_connect_panel.add_child(_lan_panel)

	# ── Practice-vs-bot sub-panel (offline mode/format pick, shown on demand) ──
	_vs_bot_panel = VBoxContainer.new()
	_vs_bot_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_vs_bot_panel.add_theme_constant_override("separation", 8)
	_vs_bot_panel.visible = false
	col.add_child(_vs_bot_panel)

	# ── Ready panel (after connect) ──
	_ready_panel = VBoxContainer.new()
	_ready_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_ready_panel.add_theme_constant_override("separation", 10)
	_ready_panel.visible = false
	col.add_child(_ready_panel)

	# Mode / format picker — populated on connect (host gets buttons, client a
	# read-only label) since is_host isn't known until host/join completes.
	_mode_panel = VBoxContainer.new()
	_mode_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_panel.add_theme_constant_override("separation", 6)
	_ready_panel.add_child(_mode_panel)
	_ready_panel.add_child(GameTheme.make_separator(GILT_BRIGHT, 300.0))

	var ready_row := HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_row.add_theme_constant_override("separation", 40)
	_ready_panel.add_child(ready_row)
	_you_ready_label = GameTheme.make_label("You: not ready", 16, ASH)
	ready_row.add_child(_you_ready_label)
	_opp_ready_label = GameTheme.make_label("Opponent: —", 16, ASH)
	ready_row.add_child(_opp_ready_label)

	_ready_btn = GameTheme.make_back_button("READY", Vector2(300, 46), 20, GREEN)
	_ready_btn.pressed.connect(_on_ready_pressed)
	_ready_panel.add_child(_ready_btn)

	_start_btn = GameTheme.make_back_button("START MATCH", Vector2(300, 46), 20, GILT_BRIGHT)
	_start_btn.tooltip_text = "Host only — enabled once both players are ready."
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.disabled = true
	_ready_panel.add_child(_start_btn)

	col.add_child(GameTheme.make_separator(GILT_BRIGHT, 360.0))

	# ── Status + shareable code + hint ──
	_status_label = GameTheme.make_label("", 16, IVORY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status_label)

	# Big shareable room code (host, online). Hidden until the relay assigns one.
	_code_label = GameTheme.make_label("", 40, GILT_BRIGHT)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.visible = false
	col.add_child(_code_label)

	_hint_label = GameTheme.make_label("", 13, ASH)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(620, 0)
	col.add_child(_hint_label)

	# ── Back ──
	_back_btn = GameTheme.make_back_button("BACK", Vector2(160, 42), 16)
	_back_btn.pressed.connect(_on_back_pressed)
	col.add_child(_back_btn)


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
	var base := _duel_tile_base("HOST", GREEN, "res://assets/icons/crown.png", online_ok)
	var root: PanelContainer = base.root
	var vb: VBoxContainer = base.vbox

	var body := GameTheme.make_label(
		"Open a war-room and get a code to share. Plays anywhere — no IP, no port forwarding." \
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
	var base := _duel_tile_base("JOIN", AZURE, "res://assets/icons/sword.png", online_ok)
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

	_host_btn = GameTheme.make_back_button("HOST (LAN)", Vector2(320, 40), 17, GREEN)
	_host_btn.tooltip_text = "Start a server on this machine; share your LAN / Tailscale IP."
	_host_btn.pressed.connect(_on_host_pressed)
	vb.add_child(_host_btn)

	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 8)
	vb.add_child(addr_row)

	_ip_field = _make_field("127.0.0.1", 220, "Host's LAN / Tailscale IP")
	addr_row.add_child(_ip_field)
	_port_field = _make_field(str(NetMatch.DEFAULT_PORT), 80, "Port")
	addr_row.add_child(_port_field)

	_join_btn = GameTheme.make_back_button("JOIN", Vector2(100, 40), 17, AZURE)
	_join_btn.pressed.connect(_on_join_pressed)
	addr_row.add_child(_join_btn)

	return panel


## Chart-language panel stylebox — the dark-ink body + tan rule + drop shadow
## used across the map tooltips and choice banners, so the lobby's custom tiles
## sit in the same material world as make_choice_banner.
func _chart_panel_style(dim: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.048, 0.040, 0.96 if not dim else 0.60)
	s.border_color = Color(0.60, 0.51, 0.34, 0.90 if not dim else 0.35)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.65)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


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
	return b


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
	NetMatch.match_starting.connect(_on_match_starting)
	NetMatch.match_config_changed.connect(_on_match_config_changed)
	NetMatch.room_created.connect(_on_room_created)
	NetMatch.room_error.connect(_on_room_error)


# ── Button handlers ──

## Online HOST: open a room on the relay; the code arrives via `room_created`.
func _on_host_online_pressed() -> void:
	if _relay_host == "":
		_set_status("Online play isn't set up in this build yet — use Same network / direct IP below.", RED)
		return
	var err := NetMatch.host_via_relay(_relay_host, NetMatch.RELAY_PORT_DEFAULT)
	if err != OK:
		_set_status("Couldn't reach the relay (error %d). Try again, or use direct IP." % err, RED)
		return
	_set_status("Opening a room on the relay…", GILT_BRIGHT)
	_set_connect_buttons_enabled(false)


## Online JOIN: connect to the relay and claim the friend's room by its code.
func _on_join_online_pressed() -> void:
	if _relay_host == "":
		_set_status("Online play isn't set up in this build yet — use Same network / direct IP below.", RED)
		return
	var code := _code_field.text.strip_edges().to_upper()
	if code.length() != NetMatch.ROOM_CODE_LEN:
		_set_status("Enter the %d-character room code your friend shared." % NetMatch.ROOM_CODE_LEN, RED)
		return
	var err := NetMatch.join_via_relay(_relay_host, NetMatch.RELAY_PORT_DEFAULT, code)
	if err != OK:
		_set_status("Couldn't reach the relay (error %d). Try again, or use direct IP." % err, RED)
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
		_set_status("Could not host on port %d (error %d)." % [port, err], RED)
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
		lines.append("No Tailscale address found — for play across different WiFi, "
			+ "install Tailscale on both PCs, then this line will show your 100.x address.")
	lines.append("Your friend picks JOIN and enters the matching address + port.")
	return "\n".join(lines)


func _on_join_pressed() -> void:
	var ip := _ip_field.text.strip_edges()
	if ip == "":
		_set_status("Enter the host's address first.", RED)
		return
	var port := _read_port()
	var err := NetMatch.join(ip, port)
	if err != OK:
		_set_status("Could not start connection (error %d)." % err, RED)
		return
	_set_status("Connecting to %s:%d…" % [ip, port], GILT_BRIGHT)
	_host_btn.disabled = true
	_join_btn.disabled = true


func _on_ready_pressed() -> void:
	NetMatch.set_local_ready(not NetMatch.local_ready)


func _on_start_pressed() -> void:
	NetMatch.start_match()


func _on_back_pressed() -> void:
	NetMatch.leave()
	get_tree().change_scene_to_file(MENU_SCENE)


# ── Net event handlers ──

## Relay assigned our shareable room code (host, online). Show it large and move on
## to the ready panel — the host reads the code to their friend while waiting.
func _on_room_created(code: String) -> void:
	var spaced := ""
	for ch in code:
		spaced += String(ch) + "  "
	_code_label.text = spaced.strip_edges()
	_code_label.visible = true
	_set_status("Room open — share this code with your friend:", GREEN)
	_hint_label.text = "Your friend picks JOIN ONLINE and types this code. Then both ready up and you press START MATCH."
	_connect_panel.visible = false
	_show_ready_panel()


## Relay rejected our code (bad / full / closed). `_rpc_room_error` already called
## leave(), so we're cleanly disconnected — let the player try another code.
func _on_room_error(reason: String) -> void:
	_set_status(reason if reason != "" else "That room code didn't work.", RED)
	_set_connect_buttons_enabled(true)


func _on_peer_joined(_id: int) -> void:
	_set_status("A friend connected!", GREEN)
	_hint_label.text = "Both ready up, then you (host) press START MATCH."
	_show_ready_panel()


func _on_connected_to_host() -> void:
	_set_status("Connected to host!", GREEN)
	_hint_label.text = "Ready up — the host starts the match."
	_connect_panel.visible = false
	_show_ready_panel()


func _on_connection_failed() -> void:
	_set_status("Connection failed — check the address and that the host is up.", RED)
	_reset_to_connect_panel()


func _on_host_closed() -> void:
	_set_status("Host closed the match.", RED)
	_reset_to_connect_panel()


func _on_peer_left(_id: int) -> void:
	_set_status("Your opponent disconnected.", RED)
	_reset_to_connect_panel()


func _on_match_starting(_seed: int) -> void:
	# Route to the chosen mode's deck-acquisition scene (host's pick, synced via
	# NetMatch.match_mode). Falls back to the draft if that scene isn't in the build.
	var scene := SkirmishState.mode_scene(NetMatch.match_mode)
	if ResourceLoader.exists(scene):
		get_tree().change_scene_to_file(scene)
	elif ResourceLoader.exists(DRAFT_SCENE):
		_set_status("That mode isn't in this build — starting a draft.", GREEN)
		get_tree().change_scene_to_file(DRAFT_SCENE)
	else:
		_set_status("Connected & ready — deck screens land with the mode build.", GREEN)


# ─────────────────────────────────────────────────────────────────────────
#  STATE / DISPLAY
# ─────────────────────────────────────────────────────────────────────────

func _show_ready_panel() -> void:
	_ready_panel.visible = true
	# START is host-only; the client never sees an enabled start button.
	_start_btn.visible = NetMatch.is_host
	_populate_mode_panel()
	_refresh_ready_labels()


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
	_mode_info_label = null
	if NetMatch.is_host:
		_build_host_mode_picker()
		# Broadcast the current selection so a connected client shows it at once.
		NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style)
	else:
		_build_client_mode_display()


func _build_host_mode_picker() -> void:
	var ml := GameTheme.make_label("MODE", 14, GILT_BRIGHT)
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

	var fl := GameTheme.make_label("FORMAT", 14, GILT_BRIGHT)
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

	var sl := GameTheme.make_label("BATTLE STYLE", 14, GILT_BRIGHT)
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

	_refresh_host_picker_highlight()


func _on_mode_chosen(mode: int) -> void:
	_selected_mode = mode
	NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style)
	_refresh_host_picker_highlight()


func _on_best_of_chosen(bo: int) -> void:
	_selected_best_of = bo
	NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style)
	_refresh_host_picker_highlight()


func _on_style_chosen(st: int) -> void:
	_selected_style = st
	NetMatch.set_match_config(_selected_mode, _selected_best_of, _selected_style)
	_refresh_host_picker_highlight()


func _refresh_host_picker_highlight() -> void:
	for mode in _mode_buttons:
		(_mode_buttons[mode] as Button).modulate = \
			Color.WHITE if mode == _selected_mode else Color(0.5, 0.5, 0.5)
	for bo in _bo_buttons:
		(_bo_buttons[bo] as Button).modulate = \
			Color.WHITE if bo == _selected_best_of else Color(0.5, 0.5, 0.5)
	for st in _style_buttons:
		(_style_buttons[st] as Button).modulate = \
			Color.WHITE if st == _selected_style else Color(0.5, 0.5, 0.5)


# ─────────────────────────────────────────────────────────────────────────
#  PRACTICE vs BOT (offline) — pick a mode/format, then run the normal deck
#  scene + combat with NetMatch.vs_bot set (no peer; SkirmishBot drives slot 1).
# ─────────────────────────────────────────────────────────────────────────

func _on_vs_bot_pressed() -> void:
	_connect_panel.visible = false
	if _lan_panel != null:
		_lan_panel.visible = false
	_vs_bot_panel.visible = true
	# The sub-panel carries its own BACK (returns to the lobby choices), so hide
	# the outer leave-to-menu BACK — one back button, one meaning.
	if _back_btn != null:
		_back_btn.visible = false
	_populate_vs_bot_panel()
	_set_status("Practice match — pick a mode, then BEGIN.", GILT_BRIGHT)


func _populate_vs_bot_panel() -> void:
	for c in _vs_bot_panel.get_children():
		c.queue_free()
	_vsbot_mode_buttons.clear()
	_vsbot_bo_buttons.clear()

	var title := GameTheme.make_label("PRACTICE vs BOT", 20, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_bot_panel.add_child(title)

	var ml := GameTheme.make_label("MODE", 14, GILT_BRIGHT)
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

	var fl := GameTheme.make_label("FORMAT", 14, GILT_BRIGHT)
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

	var sl := GameTheme.make_label("BATTLE STYLE", 14, GILT_BRIGHT)
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

	_vs_bot_panel.add_child(GameTheme.make_separator(GILT_BRIGHT, 300.0))

	var begin := GameTheme.make_back_button("BEGIN", Vector2(220, 46), 18, GILT_BRIGHT)
	begin.pressed.connect(_on_vs_bot_begin)
	_vs_bot_panel.add_child(begin)

	var back := GameTheme.make_back_button("BACK", Vector2(160, 38), 15)
	back.pressed.connect(_on_vs_bot_back)
	_vs_bot_panel.add_child(back)

	_refresh_vsbot_highlight()


func _on_vsbot_mode_chosen(mode: int) -> void:
	_vsbot_mode = mode
	_refresh_vsbot_highlight()


func _on_vsbot_bo_chosen(bo: int) -> void:
	_vsbot_bo = bo
	_refresh_vsbot_highlight()


func _on_vsbot_style_chosen(st: int) -> void:
	_vsbot_style = st
	_refresh_vsbot_highlight()


func _refresh_vsbot_highlight() -> void:
	for mode in _vsbot_mode_buttons:
		(_vsbot_mode_buttons[mode] as Button).modulate = \
			Color.WHITE if mode == _vsbot_mode else Color(0.5, 0.5, 0.5)
	for bo in _vsbot_bo_buttons:
		(_vsbot_bo_buttons[bo] as Button).modulate = \
			Color.WHITE if bo == _vsbot_bo else Color(0.5, 0.5, 0.5)
	for st in _vsbot_style_buttons:
		(_vsbot_style_buttons[st] as Button).modulate = \
			Color.WHITE if st == _vsbot_style else Color(0.5, 0.5, 0.5)


func _on_vs_bot_back() -> void:
	_vs_bot_panel.visible = false
	_connect_panel.visible = true
	if _back_btn != null:
		_back_btn.visible = true
	_refresh_state()


func _on_vs_bot_begin() -> void:
	# No peer to sync with — set the style directly before the local start.
	NetMatch.battle_style = _vsbot_style
	NetMatch.start_vs_bot(_vsbot_mode, _vsbot_bo)
	var scene := SkirmishState.mode_scene(_vsbot_mode)
	if not ResourceLoader.exists(scene):
		scene = DRAFT_SCENE
	get_tree().change_scene_to_file(scene)


func _build_client_mode_display() -> void:
	_mode_info_label = GameTheme.make_label("", 16, IVORY)
	_mode_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_mode_info_label)
	_refresh_client_mode_display()


func _refresh_client_mode_display() -> void:
	if _mode_info_label == null:
		return
	_mode_info_label.text = "Host chose:  %s  ·  %s  ·  %s" % [
		SkirmishState.mode_name(NetMatch.match_mode),
		"Best of 3" if NetMatch.best_of == 3 else "Single game",
		"Sealed Orders" if NetMatch.battle_style == NetMatch.STYLE_SEALED else "Alternating"]


func _on_match_config_changed() -> void:
	# Client side only: the host changed the mode/format — refresh the display.
	if not NetMatch.is_host:
		_refresh_client_mode_display()


func _reset_to_connect_panel() -> void:
	_connect_panel.visible = true
	_ready_panel.visible = false
	_code_label.visible = false
	_set_connect_buttons_enabled(true)
	_start_btn.disabled = true


## Enable/disable all four connect buttons together. Online buttons stay disabled
## when no relay address is configured in this build.
func _set_connect_buttons_enabled(on: bool) -> void:
	var online_ok := on and _relay_host != ""
	_host_online_btn.disabled = not online_ok
	_join_online_btn.disabled = not online_ok
	_host_btn.disabled = not on
	_join_btn.disabled = not on


func _refresh_state() -> void:
	# The HOST/JOIN tiles already print the online-unavailable reason on themselves
	# (greyed), so the bottom hint stays quiet here — it fills with the host address
	# / room code once a match is actually being set up.
	if _relay_host == "":
		_set_status("Drill against the bot, or open the direct-IP option to play a friend.", IVORY)
	else:
		_set_status("Host a room and share the code, or join a friend's.", IVORY)
	_hint_label.text = ""
	_set_connect_buttons_enabled(true)


func _refresh_ready_labels() -> void:
	_you_ready_label.text = "You: " + ("READY" if NetMatch.local_ready else "not ready")
	_you_ready_label.add_theme_color_override("font_color",
		GREEN if NetMatch.local_ready else ASH)

	var opp_txt: String
	var opp_col: Color
	if not NetMatch.remote_present:
		opp_txt = "Opponent: —"
		opp_col = ASH
	elif NetMatch.remote_ready:
		opp_txt = "Opponent: READY"
		opp_col = GREEN
	else:
		opp_txt = "Opponent: not ready"
		opp_col = ASH
	_opp_ready_label.text = opp_txt
	_opp_ready_label.add_theme_color_override("font_color", opp_col)

	if _ready_btn != null:
		_ready_btn.text = "UNREADY" if NetMatch.local_ready else "READY"

	# Host can start once both sides are ready.
	if NetMatch.is_host and _start_btn != null:
		_start_btn.disabled = not NetMatch.both_ready()


func _set_status(msg: String, color: Color) -> void:
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", color)


func _read_port() -> int:
	var p := int(_port_field.text.strip_edges())
	return p if p > 0 and p < 65536 else NetMatch.DEFAULT_PORT
