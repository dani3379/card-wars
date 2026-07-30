extends SceneTree
## Dumps every event choice's outcome string through Event._ink_outcome so the
## term/prose comma split can be read as text instead of squinted at in 51
## thumbnails. Flags any line where a middot landed next to lowercase prose,
## which is the failure mode of the heuristic.

const EVENT_SCENE := "res://scenes/event.tscn"


func _initialize() -> void:
	var ev = load(EVENT_SCENE).instantiate()
	root.add_child(ev)
	var suspicious := 0
	var total := 0
	for eid in EventDB.EVENTS:
		var data: Dictionary = EventDB.EVENTS[eid]
		for choice in data.get("choices", []):
			var raw := String(choice.get("desc", ""))
			if raw.is_empty():
				continue
			total += 1
			var inked: String = ev._ink_outcome(raw)
			# Strip bbcode for reading.
			var plain := ""
			var depth := 0
			for c in inked:
				if c == "[":
					depth += 1
				elif c == "]":
					depth = maxi(0, depth - 1)
				elif depth == 0:
					plain += c
			if raw.find(",") < 0 and raw.find("·") < 0:
				continue
			var flag := ""
			# A middot should never precede a lowercase connective word.
			for bad in [" · then", " · kept", " · is ", " · permanently", " · honestly",
					" · Last Stand", " · Thorns", " · Armored", " · Swift"]:
				if plain.find(bad) >= 0:
					flag = "  <<< SUSPICIOUS"
					suspicious += 1
					break
			print("  %s%s" % [plain.strip_edges(), flag])
	print("[outcome-ink] %d outcome strings, %d suspicious" % [total, suspicious])
	quit(suspicious)
