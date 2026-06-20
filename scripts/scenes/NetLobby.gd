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
var _ip_field: LineEdit
var _port_field: LineEdit
var _host_btn: Button
var _join_btn: Button
var _ready_btn: Button
var _start_btn: Button
var _connect_panel: VBoxContainer   # host/join controls (hidden once connected)
var _ready_panel: VBoxContainer     # ready/start controls (shown once connected)
var _you_ready_label: Label
var _opp_ready_label: Label


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
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
		"Draft a 20-card deck, then fight a friend.\n"
		+ "Connect over a Tailscale / LAN address — no port forwarding needed.",
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

	_host_btn = GameTheme.make_themed_button("HOST A MATCH",
		Color(0.18, 0.36, 0.18), Vector2(360, 48), 20,
		"Start a server and wait for a friend to join.")
	_host_btn.pressed.connect(_on_host_pressed)
	_connect_panel.add_child(_host_btn)

	var or_lbl := GameTheme.make_label("— or join —", 14, ASH)
	or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connect_panel.add_child(or_lbl)

	# Address row: IP + port fields.
	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 8)
	_connect_panel.add_child(addr_row)

	_ip_field = _make_field("127.0.0.1", 240, "Host's Tailscale / LAN IP")
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


# ── Button handlers ──

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
	if ResourceLoader.exists(DRAFT_SCENE):
		get_tree().change_scene_to_file(DRAFT_SCENE)
	else:
		# Phase 0 standalone: the draft scene arrives in Phase 1.
		_set_status("Connected & ready — draft screen lands in Phase 1.", GREEN)


# ─────────────────────────────────────────────────────────────────────────
#  STATE / DISPLAY
# ─────────────────────────────────────────────────────────────────────────

func _show_ready_panel() -> void:
	_ready_panel.visible = true
	# START is host-only; the client never sees an enabled start button.
	_start_btn.visible = NetMatch.is_host
	_refresh_ready_labels()


func _reset_to_connect_panel() -> void:
	_connect_panel.visible = true
	_ready_panel.visible = false
	_host_btn.disabled = false
	_join_btn.disabled = false
	_start_btn.disabled = true


func _refresh_state() -> void:
	_set_status("Host a match, or join a friend's address.", IVORY)
	_hint_label.text = ""


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
