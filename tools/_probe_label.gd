extends SceneTree
## Confirm GameTheme.make_label now gives body-sized text a default outline and
## leaves titles + explicit-outline callers as intended.

func _process(_d: float) -> bool:
	var gt = root.get_node_or_null("GameTheme")
	if gt == null:
		print("[label] no GameTheme autoload"); quit(1); return false
	for case in [[13, false], [16, false], [22, false], [16, true]]:
		var sz: int = case[0]
		var outl: bool = case[1]
		var lbl: Label = gt.make_label("Ag", sz, gt.IVORY, outl)
		var osize = lbl.get_theme_constant("outline_size")
		var fsize = lbl.get_theme_font_size("font_size")
		print("[label] asked=%d outline_arg=%s -> rendered_size=%d outline=%s (floor=%d)" %
			[sz, str(outl), fsize, str(osize), gt.MIN_LABEL_SIZE])
		lbl.free()
	print("[label] DONE")
	quit(0)
	return false
