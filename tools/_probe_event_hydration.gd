extends SceneTree
## Focused contract probe for Event's placeholder-first painting hydration.

var _fails := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/scenes/Event.gd")
	var build_pos: int = source.find("\t_build_ui()")
	var hydrate_pos: int = source.find("\t_begin_event_art_hydration()")
	_check(build_pos >= 0 and hydrate_pos > build_pos,
		"Event builds its interactive UI before requesting the painting")
	_check(source.find("return load(") < 0 and source.find("_load_event_image()") < 0,
		"Event first-use path has no synchronous painting fallback")

	var rs: Node = root.get_node_or_null("RunState")
	_check(rs != null, "event hydration dependencies are present")
	if rs == null:
		quit(1)
		return
	var event_script: GDScript = load("res://scripts/scenes/Event.gd")
	var resolver: Control = event_script.new()
	resolver._event_id = "the_reliquary_cart"
	resolver._event_data = event_script.EVENTS["the_reliquary_cart"]
	_check(resolver._resolve_event_image_path() \
			== "res://assets/events/the_answering_well.png",
		"missing bespoke art still resolves its declared stand-in")
	resolver.free()

	rs.start_new_run("raider", 0, 82031)
	# The first bridge deterministically selects The Crossing, whose bespoke
	# 1.4 MB painting makes this exercise the real first-use path.
	rs.current_bridge = true
	rs.events_seen.erase("the_crossing")
	var ev: Node = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)

	var choices: Node = _choice_root(ev)
	var fallback: CanvasItem = ev.get_node_or_null("Background") as CanvasItem
	var overlay: CanvasItem = ev.get_node_or_null("EventOverlayLeft") as CanvasItem
	_check(choices != null and _wired_button_count(choices) > 0,
		"title/description/choices are interactive on the ready frame")
	_check(fallback != null and fallback.visible and not ev.has_node("EventArt"),
		"fallback painting remains visible for the first interactive frame")
	# THE LEFT WASH IS A FOLIO DEVICE (2026-08-05). `_ensure_event_overlay`'s own
	# header: the wash "pools ink down the LEFT ... a shape cut for the folio
	# ladder, whose title and choices live exactly there. A presented layout
	# draws its own ink where ITS copy sits" — and `_build_presented_event`
	# duly sets `EventOverlayLeft.visible = false`. Asserting that node is
	# visible therefore fails by design on every presented event, which is what
	# The Crossing became.
	#
	# What this check is FOR is the hydration contract: the copy must be
	# readable while the painting streams in. So assert hydration is genuinely
	# running, and that a readability treatment is in force — the left wash on
	# folio, or the layout's own ink otherwise. Deliberately NOT re-deriving
	# `_wants_left_scrim()`, which would make the check a tautology.
	var presented: bool = ev._event_presentation_layout() != "folio"
	_check(ev._event_art_loading and (presented or (overlay != null and overlay.visible)),
		"a readability treatment is live while painting hydration runs")

	# Model a modal picker hiding art during the request. The late texture must
	# honor that state instead of flashing itself over the picker.
	ev._set_event_art_visible(false)
	var landed: bool = false
	for _i in range(300):
		await process_frame
		if ev._event_image != null and ev.has_node("EventArt"):
			landed = true
			break
	_check(landed and not ev._event_art_loading,
		"worker-loaded event painting hot-swaps when ready")
	var art: TextureRect = ev.get_node_or_null("EventArt") as TextureRect
	overlay = ev.get_node_or_null("EventOverlayLeft") as CanvasItem
	_check(art != null and art.texture != null and not art.visible \
			and ((presented and overlay == null) \
			or (not presented and overlay != null and not overlay.visible)),
		"late hydration preserves a modal picker's hidden-art state")
	_check(is_instance_valid(choices) and choices == _choice_root(ev) \
			and _wired_button_count(choices) > 0,
		"painting swap leaves the live choice subtree untouched")

	ev._set_event_art_visible(true)
	_check(art.visible and (presented or (overlay != null and overlay.visible)) \
			and fallback != null and not fallback.visible,
		"revealing hydrated art replaces the fallback without rebuilding UI")

	var request_serial: int = ev._event_art_request_serial
	var event_path: String = ev._event_image_path
	root.remove_child(ev)
	_check(ev._event_art_request_serial > request_serial and not ev._event_art_loading \
			and ev._event_image == null,
		"scene exit cancels ownership and releases its painting reference")
	_check(not CardArtAliases._threaded_path_cache.has(event_path),
		"scene exit leaves no shared strong pin for the event painting")
	ev.free()

	# Cancellation before the first hydration frame must not install a late art
	# node into a detached Event or retain the request through the shared cache.
	# Attach Event.gd after a bare Control is already in-tree so this focused
	# cancellation check does not also launch the choice-layout coroutines.
	var cancelled := Control.new()
	root.add_child(cancelled)
	cancelled.set_script(event_script)
	cancelled._event_id = "the_crossing"
	cancelled._event_data = event_script.EVENTS["the_crossing"]
	cancelled._begin_event_art_hydration()
	var cancel_path: String = cancelled._event_image_path
	var cancel_serial: int = cancelled._event_art_request_serial
	root.remove_child(cancelled)
	await process_frame
	await process_frame
	_check(cancelled._event_art_request_serial > cancel_serial \
			and cancelled._event_image == null and not cancelled.has_node("EventArt"),
		"exit before first hydration frame cancels the late install")
	_check(not CardArtAliases._threaded_path_cache.has(cancel_path),
		"cancelled first-use request leaves no shared strong pin")
	cancelled.free()

	print("[event-hydration] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## THE CHOICE COLUMN IS NOT ALWAYS CALLED "ChoicesBox" (2026-08-05).
##
## `_build_ui` only builds that node on the FOLIO fallback path: an event with a
## `presentation.layout` returns through `_build_presented_event` first, and The
## Crossing — the event this probe deliberately selects, because its 1.4 MB
## bespoke painting exercises the real first-use path — is `layout: "location"`.
## So `get_node_or_null("ChoicesBox")` had been returning null, and THREE checks
## were failing on it: the interactive-frame check, the scrim check, and the
## "swap leaves the live choice subtree untouched" check. Nothing was wrong with
## hydration; the probe was pinned to one layout's node name.
##
## The contract here is "the player's choices exist and are wired before the
## painting is requested" — which is about STRUCTURE, not naming. Find the
## direct child of the scene whose subtree owns the wired buttons: stable
## identity across the art swap (which is what the third check needs) without
## caring how the event chose to lay itself out.
func _choice_root(ev: Node) -> Node:
	var named := ev.get_node_or_null("ChoicesBox")
	if named != null and _wired_button_count(named) > 0:
		return named
	for child in ev.get_children():
		if _wired_button_count(child) > 0:
			return child
	return null


func _wired_button_count(node: Node) -> int:
	var count := 0
	if node is Button and not (node as Button).disabled \
			and not (node as Button).pressed.get_connections().is_empty():
		count += 1
	for child in node.get_children():
		count += _wired_button_count(child)
	return count
