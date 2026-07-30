extends SceneTree
## _probe_dumpcards.gd — dump CardDB to JSON so offline analysis (policy
## hypothesis testing against the playlogs) doesn't need a Godot round-trip
## per idea. Writes user://carddump.json.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_dumpcards.gd

var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	await process_frame
	var cards: Node = root.get_node_or_null("CardDB")
	if cards == null:
		print("[dumpcards] FATAL: CardDB missing")
		quit()
		return
	# CARD_POOL is a script CONST (and a Dictionary keyed by id), so it is not
	# reachable through Object.get() — that returns null and hangs the probe.
	var consts: Dictionary = cards.get_script().get_script_constant_map()
	var pool: Dictionary = consts.get("CARD_POOL", {})
	if pool.is_empty():
		print("[dumpcards] FATAL: CARD_POOL empty/unreadable")
		quit()
		return
	var out: Dictionary = {}
	for key in pool:
		var d: Dictionary = pool[key]
		# Keyed by the pool's own key — entries don't all carry a self "id".
		out[String(key)] = {
			"id": String(key),
			"cost": d.get("cost", 0),
			"atk": d.get("atk", 0),
			"hp": d.get("hp", 0),
			"type": d.get("type", ""),
			"rarity": d.get("rarity", ""),
			"ctype": d.get("ctype", ""),
			"keywords": d.get("keywords", []),
			"passive": d.get("passive", ""),
			"targeting": d.get("targeting", "none"),
			"scope": d.get("scope", ""),
		}
	var f := FileAccess.open("user://carddump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[dumpcards] wrote ", out.size(), " cards to user://carddump.json")
	quit()
