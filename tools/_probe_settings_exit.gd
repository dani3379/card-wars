extends SceneTree
## Verify the settings system-row exits per context: a live match must offer
## "LEAVE MATCH" (the screenshot bug was QUIT-only), and reset state must not.

func _process(_d: float) -> bool:
	var nm = root.get_node_or_null("NetMatch")
	var ov = root.get_node_or_null("UserSettings")
	# Find the SettingsOverlay (child of UserSettings autoload).
	var so = null
	if ov != null:
		for c in ov.get_children():
			if c.has_method("_rebuild_system_row"):
				so = c; break
	if so == null:
		print("[setexit] no SettingsOverlay found"); quit(1); return false

	# Case A: simulate an active Skirmish (vs_bot makes is_connected_to_peer true).
	nm.vs_bot = true
	so._rebuild_system_row()
	print("[setexit] in-match row: ", _labels(so._system_row))

	# Case B: not in a match (and no run) — should offer MAIN MENU, never only QUIT.
	nm.vs_bot = false
	nm._connected = false
	so._rebuild_system_row()
	print("[setexit] idle row:     ", _labels(so._system_row))

	print("[setexit] DONE")
	quit(0)
	return false


func _labels(row) -> Array:
	var out: Array = []
	if row == null:
		return out
	for b in row.get_children():
		if b is Button:
			out.append(String(b.text))
	return out
