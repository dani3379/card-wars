extends SceneTree
## New-run crash finder. Calls RunState.start_new_run for each hero and the
## no-arg legacy path, printing where it dies.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_newrun.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var RS: Node = root.get_node_or_null("RunState")
	var HDB: Node = root.get_node_or_null("HeroDB")
	if RS == null or HDB == null:
		print("[newrun] FATAL: autoloads missing"); quit(1); return

	print("[newrun] no-arg start_new_run() ...")
	RS.start_new_run()
	print("[newrun]   OK  deck=%d relics=%d acts_map=%s" % [
		RS.deck.size(), RS.relics.size(), str(RS.act_maps.size()) if "act_maps" in RS else "?"])

	for hid in HDB.HERO_ORDER:
		print("[newrun] hero '%s' ..." % hid)
		RS.start_new_run(String(hid), 0, 4242)
		print("[newrun]   OK  deck=%d relics=%d" % [RS.deck.size(), RS.relics.size()])

	print("[newrun] DONE — no crash")
	quit(0)
