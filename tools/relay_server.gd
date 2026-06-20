extends SceneTree
## relay_server.gd — the public Skirmish RELAY, run headless on a VPS.
##
## This is the SAME Godot project as the game (so the @rpc node paths match), run
## with NetMatch driven into relay mode. Both players connect OUT to this process;
## it pairs them by room code and forwards each envelope to the room partner only.
## Outbound connections traverse any NAT/CGNAT, so neither player needs Tailscale,
## port-forwarding, or a public IP — only this relay needs a reachable address.
##
## Run (port optional; defaults to NetMatch.RELAY_PORT_DEFAULT):
##   Godot.exe --headless --path "D:\Godot" --script res://tools/relay_server.gd -- --port 7717
## or set the port via the RELAY_PORT environment variable. Keep it running (e.g.
## under systemd / nohup / a Windows service). It prints a heartbeat with the live
## room/peer count so you can confirm it's healthy.
##
## SHIPPING: bake the relay's address into NetMatch.RELAY_HOST_DEFAULT so players
## never type an IP — they just share a 4-character room code.

const HEARTBEAT_SEC := 30.0

var NM: Node
var _started := false
var _heartbeat := 0.0


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_boot()
	_heartbeat += delta
	if _heartbeat >= HEARTBEAT_SEC:
		_heartbeat = 0.0
		_log_status()
	return false   # never quit — the relay is a long-running service


func _boot() -> void:
	NM = root.get_node_or_null("NetMatch")
	if NM == null:
		push_error("[relay] FATAL: NetMatch autoload missing — run with --path to the project.")
		quit(1)
		return
	var port := _resolve_port()
	var err: int = NM.run_as_relay(port)
	if err != OK:
		push_error("[relay] FATAL: could not open relay on port %d (error %d)." % [port, err])
		quit(1)
		return
	print("[relay] Skirmish relay listening on UDP :%d — share room codes; no port-forwarding needed." % port)
	print("[relay] heartbeat every %ds; Ctrl-C to stop." % int(HEARTBEAT_SEC))


## Port precedence: a `-- --port N` cmdline arg, else the RELAY_PORT env var, else
## NetMatch's default.
func _resolve_port() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			var p := int(args[i + 1])
			if p > 0 and p < 65536:
				return p
	var env := OS.get_environment("RELAY_PORT")
	if env != "" and int(env) > 0 and int(env) < 65536:
		return int(env)
	return NM.RELAY_PORT_DEFAULT


func _log_status() -> void:
	var rooms := 0
	var peers := 0
	if NM != null:
		rooms = NM._relay_rooms.size()
		peers = NM._relay_peer_room.size()
	print("[relay] alive — %d room(s), %d connected peer(s)." % [rooms, peers])
