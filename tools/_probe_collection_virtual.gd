extends SceneTree
## Regression probe for Collection's virtualized relic gallery.
## Exercises scrollbar jumps, rehydration, stable geometry/range, and tab races.

const LIVE_NODE_LIMIT := 48
const WAIT_SECONDS := 3.0

var _started := false
var _failures: Array[String] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var scene: Node = load("res://scenes/collection.tscn").instantiate()
	root.add_child(scene)
	scene.call("show_tab", "relics")
	if not await _wait_for_jobs(scene):
		_fail("relic index did not finish")
		await _finish(scene)
		return

	var scroll: ScrollContainer = scene.get("_scroll")
	var bar := scroll.get_v_scroll_bar()
	for _i in 2:
		await process_frame
	var baseline_max := bar.max_value
	var max_scroll := maxf(0.0, bar.max_value - bar.page)
	var stops := [
		{"name": "top", "ratio": 0.0},
		{"name": "middle", "ratio": 0.5},
		{"name": "bottom", "ratio": 1.0},
		{"name": "return_top", "ratio": 0.0},
	]
	for stop in stops:
		scroll.scroll_vertical = int(round(max_scroll * float(stop.ratio)))
		await process_frame
		var hydrated := await _wait_for_visible(scene)
		var stats := _gallery_stats(scene)
		print("[collection-virtual] %s total=%d live=%d placeholders=%d visible_pending=%d bad_size=%d h_overflow=%d v_overflow=%d" % [
			stop.name, stats.total, stats.live, stats.placeholders,
			stats.visible_pending, stats.bad_size, stats.h_overflow,
			stats.v_overflow])
		if not hydrated or stats.visible_pending != 0:
			_fail("%s left visible placeholders" % stop.name)
		if stats.live > LIVE_NODE_LIMIT:
			_fail("%s retained %d live plaques (limit %d)" % [
				stop.name, stats.live, LIVE_NODE_LIMIT])
		if stats.bad_size != 0 or stats.h_overflow != 0 \
				or stats.v_overflow != 0:
			_fail("%s has invalid plaque geometry" % stop.name)
		if absf(bar.max_value - baseline_max) > 1.0:
			_fail("%s changed scroll range %.2f -> %.2f" % [
				stop.name, baseline_max, bar.max_value])

	# Switch away while async work may still be finishing, then return. Cards is
	# event-driven too; no Collection tab should retain an idle process callback.
	scene.call("show_tab", "cards")
	await process_frame
	if scene.is_processing():
		_fail("cards tab left obsolete virtual polling enabled")
	scene.call("show_tab", "relics")
	await process_frame
	scene.call("show_tab", "potions")
	await process_frame
	if scene.is_processing():
		_fail("potions tab left Collection processing")
	scene.call("show_tab", "relics")
	if scene.is_processing():
		_fail("relics tab should be event-driven")
	if not await _wait_for_jobs(scene) or not await _wait_for_visible(scene):
		_fail("rapid tab return did not recover")
	var final_stats := _gallery_stats(scene)
	if final_stats.visible_pending != 0 or final_stats.live > LIVE_NODE_LIMIT:
		_fail("rapid tab return left invalid live window")

	await _finish(scene)


func _wait_for_jobs(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var jobs: Array = scene.get("_relic_jobs")
		if not jobs.is_empty():
			return true
	return false


func _wait_for_visible(scene: Node) -> bool:
	var deadline := Time.get_ticks_msec() + int(WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if int(_gallery_stats(scene).visible_pending) == 0:
			return true
	return false


func _gallery_stats(scene: Node) -> Dictionary:
	var jobs: Array = scene.get("_relic_jobs")
	var scroll: ScrollContainer = scene.get("_scroll")
	var viewport_rect := scroll.get_global_rect()
	var stats := {
		"total": jobs.size(), "live": 0, "placeholders": 0,
		"visible_pending": 0, "bad_size": 0,
		"h_overflow": 0, "v_overflow": 0,
	}
	for job in jobs:
		var node: Control = job.get("node", null)
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			_fail("job has no live node")
			continue
		var state := String(job.get("state", ""))
		if state == "plaque":
			stats.live += 1
			_check_plaque_geometry(node, stats)
		else:
			stats.placeholders += 1
			if node.get_global_rect().intersects(viewport_rect):
				stats.visible_pending += 1
	return stats


func _check_plaque_geometry(tile: Control, stats: Dictionary) -> void:
	if not tile.size.is_equal_approx(Vector2(466, 120)):
		stats.bad_size += 1
	var tile_rect := tile.get_global_rect()
	var labels: Array[Control] = []
	_collect_labels(tile, labels)
	for label in labels:
		var rect := label.get_global_rect()
		if rect.position.x < tile_rect.position.x - 0.5 \
				or rect.end.x > tile_rect.end.x + 0.5:
			stats.h_overflow += 1
		if rect.position.y < tile_rect.position.y - 0.5 \
				or rect.end.y > tile_rect.end.y + 0.5:
			stats.v_overflow += 1


func _collect_labels(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)


func _fail(message: String) -> void:
	if message not in _failures:
		_failures.append(message)
		push_error("[collection-virtual] %s" % message)


func _finish(scene: Node) -> void:
	scene.queue_free()
	for _i in 5:
		await process_frame
	print("[collection-virtual] %s" % (
		"PASS" if _failures.is_empty() else "FAIL (%s)" % ", ".join(_failures)))
	quit(0 if _failures.is_empty() else 1)
