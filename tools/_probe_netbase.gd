extends SceneTree
## Verifies the NetDeckBuilder base-class extraction wired up at runtime:
## each of the 4 deck-builder scripts must (a) instantiate, (b) read the inherited
## constants + state vars, and (c) carry the inherited _build_pool_thumb method.
## Does NOT run _ready (no peer needed) — purely an inheritance-resolution check.

func _process(_delta: float) -> bool:
	var subs := {
		"NetConstructed": "res://scripts/scenes/NetConstructed.gd",
		"NetSealed": "res://scripts/scenes/NetSealed.gd",
		"NetQuick": "res://scripts/scenes/NetQuick.gd",
		"NetDraft": "res://scripts/scenes/NetDraft.gd",
	}
	var fails := 0
	for name in subs:
		var S = load(subs[name])
		var o = S.new()
		var checks := {
			"MENU_SCENE inherited": o.MENU_SCENE == "res://scenes/main_menu.tscn",
			"GILT_BRIGHT inherited": o.GILT_BRIGHT == Color(1.0, 0.85, 0.45, 1.0),
			"_target inherited (=20)": o._target == 20,
			"_local_finished inherited (=false)": o._local_finished == false,
			"_remote_finished inherited (=false)": o._remote_finished == false,
			"_pool_rows inherited (Dictionary)": o._pool_rows is Dictionary,
			"_build_pool_thumb inherited": o.has_method("_build_pool_thumb"),
			"_rng inherited (RNG)": o._rng is RandomNumberGenerator,
		}
		for label in checks:
			if not checks[label]:
				print("  FAIL  ", name, " :: ", label)
				fails += 1
		print("ok  ", name, " — all inherited members resolve")
		o.free()
	print("[netbase] RESULT: ", ("PASS" if fails == 0 else "FAIL"), " — fails=", fails)
	return true  # quit after one tick
