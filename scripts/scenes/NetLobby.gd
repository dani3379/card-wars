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
var _lan_panel: VBoxContainer      # direct host/join controls (collapsed by default)
var _host_btn: Button              # LAN/direct host
var _join_btn: Button              # LAN/direct join
var _ready_btn: Button
var _start_btn: Button
var _connect_panel: VBoxContainer   # host/join controls (hidden once connected)
var _ready_panel: VBoxContainer     # ready/start controls (shown once connected)
var _you_ready_label: Label
var _opp_ready_label: Label
var _relay_host: String = ""        # resolved relay address (empty = online disabled)

# ── Mode / format picker (host picks; client sees the choice) ──
var _mode_panel: VBoxContainer       # built on connect (host buttons / client label)
var _mode_buttons: Dictionary = {}   # MatchMode id -> Button (host only)
var _bo_buttons: Dictionary = {}     # best_of value (1/3) -> Button (host only)
var _mode_info_label: Label          # client: shows the host's chosen mode/format
var _selected_mode: int = 0          # host's current pick (SkirmishState.MatchMode)
var _selected_best_of: int = 1       # host's current pick (1 or 3)


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	_relay_host = NetMatch.get_relay_host()
	# Fresh lobby: drop any stale connection from a previous visit.
	NetMatch.leave()
	_build_ui()
	_wire_net_signals()
	_refresh_state()


# ─────────────────────────────────────────────────────────────────────────
#  UI
# ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var col := VBoxContainer.new()
	col.name = "Lobby"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -300
	col.offset_right = 300
	col.offset_top = -260
	col.offset_bottom = 260
	add_child(col)

	col.add_child(GameTheme.make_screen_title("SKIRMISH — ONLINE", GILT_BRIGHT))

	var blurb := GameTheme.make_label(
		"Pick a mode, then fight a friend anywhere.\n"
		+ "Host gets a room code — share it, your friend types it in. No IP, no setup.",
		15, ASH)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(560, 0)
	col.add_child(blurb)

	col.add_child(GameTheme.make_separator(GILT_BRIGHT, 360.0))

	# ── Connect panel (host / join) ──
	_connect_panel = VBoxContainer.new()
	_connect_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_panel.add_theme_constant_override("separation", 12)
	col.add_child(_connect_panel)

	# ── Online (relay / room code) — the primary, NAT-free path ──
	_host_online_btn = GameTheme.make_themed_button("HOST ONLINE",
		Color(0.18, 0.36, 0.18), Vector2(360, 48), 20,
		"Open a room on the relay and get a code to share. Plays across the internet — no port forwarding, no VPN.")
	_host_online_btn.pressed.connect(_on_host_online_pressed)
	_connect_panel.add_child(_host_online_btn)

	var or_lbl := GameTheme.make_label("— or join with a code —", 14, ASH)
	or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connect_panel.add_child(or_lbl)

	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 8)
	_connect_panel.add_child(code_row)

	_code_field = _make_field("", 200, "ROOM CODE")
	_code_field.max_length = NetMatch.ROOM_CODE_LEN
	_code_field.text_changed.connect(_on_code_typed)
	_code_field.text_submitted.connect(func(_t): _on_join_online_pressed())
	code_row.add_child(_code_field)

	_join_online_btn = GameTheme.make_themed_button("JOIN ONLINE",
		Color(0.20, 0.28, 0.42), Vector2(150, 44), 18,
		"Enter your friend's room code to connect.")
	_join_online_btn.pressed.connect(_on_join_online_pressed)
	code_row.add_child(_join_online_btn)

	# ── Same-network / direct fallback (LAN or a Tailscale IP) — collapsed ──
	_lan_toggle = GameTheme.make_themed_button("Same network / direct IP  ▾",
		Color(0.16, 0.16, 0.20), Vector2(360, 32), 13,
		"Play over a LAN or a Tailscale address with no relay — best when you're on the same WiFi.")
	_lan_toggle.pressed.connect(_on_lan_toggle_pressed)
	_connect_panel.add_child(_lan_toggle)

	_lan_panel = VBoxContainer.new()
	_lan_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_lan_panel.add_theme_constant_override("separation", 10)
	_lan_panel.visible = false
	_connect_panel.add_child(_lan_panel)

	_host_btn = GameTheme.make_themed_button("HOST (LAN)",
		Color(0.18, 0.32, 0.22), Vector2(360, 42), 17,
		"Start a server on this machine; share your LAN / Tailscale IP.")
	_host_btn.pressed.connect(_on_host_pressed)
	_lan_panel.add_child(_host_btn)

	# Address row: IP + port fields.
	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 8)
	_lan_panel.add_child(addr_row)

	_ip_field = _make_field("127.0.0.1", 240, "Host's LAN / Tailscale IP")
	addr_row.add_child(_ip_field)
	_port_field = _make_field(str(NetMatch.DEFAULT_PORT), 90, "Port")
	addr_row.add_child(_port_field)

	_join_btn = GameTheme.make_themed_button("JOIN",
		Color(0.20, 0.28, 0.42), Vector2(110, 44), 18)
	_join_btn.pressed.connect(_on_join_pressed)
	addr_row.add_child(_join_btn)

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

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.18, 0.36, 0.18), Vector2(360, 48), 20)
	_ready_btn.pressed.connect(_on_ready_pressed)
	_ready_panel.add_child(_ready_btn)

	_start_btn = GameTheme.make_themed_button("START MATCH",
		Color(0.40, 0.30, 0.12), Vector2(360, 48), 20,
		"Host only — enabled once both players are ready.")
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.disabled = true
	_ready_panel.add_child(_start_btn)

	col.add_child(GameTheme.make_separator(GILT_BRIGHT, 360.0))

	# ── Status + hint ──
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
	_hint_label.custom_minimum_size = Vector2(560, 0)
	col.add_child(_hint_label)

	# ── Back ──
	var back_btn := GameTheme.make_themed_button("BACK",
		Color(0.26, 0.16, 0.14), Vector2(160, 42), 16)
	back_btn.pressed.connect(_on_back_pressed)
	col.add_child(back_btn)


func _make_field(default_text: String, width: int, placeholder: String) -> LineEdit:
	var f := LineEdit.new()
	f.text = default_text
	f.placeholder_text = placeholder
	f.custom_minimum_size = Vector2(width, 44)
	f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if GameTheme.font_body:
		f.add_theme_font_override("font", GameTheme.font_body)
	f.add_theme_font_size_override("font_size", 16)
	return f


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
		NetMatch.set_match_config(_selected_mode, _selected_best_of)
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
		var b := GameTheme.make_themed_button(SkirmishState.mode_name(mode).to_upper(),
			Color(0.20, 0.24, 0.34), Vector2(150, 40), 14, SkirmishState.mode_blurb(mode))
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
		var b2 := GameTheme.make_themed_button(
			"SINGLE GAME" if bo == 1 else "BEST OF 3",
			Color(0.20, 0.24, 0.34), Vector2(150, 36), 13)
		b2.pressed.connect(_on_best_of_chosen.bind(bo))
		bo_row.add_child(b2)
		_bo_buttons[bo] = b2

	_refresh_host_picker_highlight()


func _on_mode_chosen(mode: int) -> void:
	_selected_mode = mode
	NetMatch.set_match_config(_selected_mode, _selected_best_of)
	_refresh_host_picker_highlight()


func _on_best_of_chosen(bo: int) -> void:
	_selected_best_of = bo
	NetMatch.set_match_config(_selected_mode, _selected_best_of)
	_refresh_host_picker_highlight()


func _refresh_host_picker_highlight() -> void:
	for mode in _mode_buttons:
		(_mode_buttons[mode] as Button).modulate = \
			Color.WHITE if mode == _selected_mode else Color(0.5, 0.5, 0.5)
	for bo in _bo_buttons:
		(_bo_buttons[bo] as Button).modulate = \
			Color.WHITE if bo == _selected_best_of else Color(0.5, 0.5, 0.5)


func _build_client_mode_display() -> void:
	_mode_info_label = GameTheme.make_label("", 16, IVORY)
	_mode_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_mode_info_label)
	_refresh_client_mode_display()


func _refresh_client_mode_display() -> void:
	if _mode_info_label == null:
		return
	_mode_info_label.text = "Host chose:  %s  ·  %s" % [
		SkirmishState.mode_name(NetMatch.match_mode),
		"Best of 3" if NetMatch.best_of == 3 else "Single game"]


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
	_set_status("Host a match, or join a friend's room code.", IVORY)
	_hint_label.text = ""
	_set_connect_buttons_enabled(true)
	if _relay_host == "":
		_hint_label.text = "Online play isn't set up in this build yet — open “Same network / direct IP” to play over LAN or Tailscale."


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
