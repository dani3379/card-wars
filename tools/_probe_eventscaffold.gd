extends SceneTree
## Smoke-tests Event._build_event_screen (the shared dice/risk/appraisal scaffold
## extracted in the 2026-06-28 safe-dedup). Builds an Event node WITHOUT running
## _ready (no run needed), calls the helper with both the default and the
## appraisal-widened choices column, and asserts it produces the expected tree:
## a title + desc parented to the Event, and a returned bottom-left VBox.

func _process(_delta: float) -> bool:
	var fails := 0
	var E = load("res://scripts/scenes/Event.gd")
	var e = E.new()  # Event node, NOT in tree -> _ready does not fire

	# Default column (dice / risk use 80–700).
	var vb = e._build_event_screen("A Title", "A beat of description.", 2)
	if not (vb is VBoxContainer):
		print("  FAIL  default: returned node is not a VBoxContainer"); fails += 1
	elif not (vb.offset_left == 80 and vb.offset_right == 700):
		print("  FAIL  default: choices column not at 80–700"); fails += 1
	elif vb.get_theme_constant("separation") != 12:
		print("  FAIL  default: separation != 12"); fails += 1
	else:
		print("ok  default column scaffold (80–700, sep 12)")

	# Appraisal column (widened to 360–980).
	var vb2 = e._build_event_screen("Appraise", "She names a figure.", 3, 360, 980)
	if not (vb2 is VBoxContainer and vb2.offset_left == 360 and vb2.offset_right == 980):
		print("  FAIL  appraisal: choices column not at 360–980"); fails += 1
	else:
		print("ok  appraisal column scaffold (360–980)")

	# After a build the Event should hold: title + desc + the choices VBox.
	# (_clear_ui ran first each call, so exactly the last build's nodes remain.)
	var kids: Array = e.get_children()
	if kids.size() < 3:
		print("  FAIL  expected >=3 children (title, desc, vbox); got ", kids.size()); fails += 1
	else:
		print("ok  Event holds title+desc+vbox (", kids.size(), " children)")

	print("[eventscaffold] RESULT: ", ("PASS" if fails == 0 else "FAIL"), " — fails=", fails)
	e.free()
	return true
