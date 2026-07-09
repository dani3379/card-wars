extends SceneTree
## Parse-check the touched scripts + assert the Supersample logical-size math:
## with content_scale_factor=c the SubViewport override must be base/c (so SSAA
## layout + input match the non-SSAA path), and equal base at c=1.0.

func _process(_d: float) -> bool:
	var ok := true
	for path in ["res://scripts/scenes/Event.gd",
			"res://scripts/ui/SettingsOverlay.gd",
			"res://scripts/state/UserSettings.gd",
			"res://scripts/state/Supersample.gd"]:
		var s = load(path)
		if s == null:
			print("[scalecheck] FAILED to load ", path); ok = false
		else:
			print("[scalecheck] parsed ok: ", path)

	# Supersample math: drive apply_scale + content_scale_factor, read override.
	var ss = root.get_node_or_null("Supersample")
	var base := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	if ss != null:
		ss.apply_scale(1.5)             # build the rig
		for c in [1.0, 0.8, 0.7]:
			root.content_scale_factor = c
			ss.refresh()
			var want := Vector2i(int(round(base.x / c)), int(round(base.y / c)))
			var got: Vector2i = ss._svp.size_2d_override
			var pass_ := got == want
			ok = ok and pass_
			print("[scalecheck] factor=%.2f override=%s want=%s %s" %
				[c, str(got), str(want), "OK" if pass_ else "MISMATCH"])
		root.content_scale_factor = 1.0
		ss.apply_scale(1.0)             # tear down
	else:
		print("[scalecheck] (no Supersample autoload in this context)")

	print("[scalecheck] RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return false
