extends SceneTree
## _probe_map_plaque.gd — the order plaque may never cover the army standard.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_map_plaque.gd
##
## THE DEFECT (found by QA crop, fixed 2026-07-30): MapPulseOverlay draws its
## "MARCH TO ..." plaque at the march DESTINATION, 62px above it and centred, up to
## 250px wide — while the army standard stands at the ORIGIN, one lane away. On any
## leg that climbs or drops a lane the plaque landed on the standard and hid the one
## object on the chart that answers "where is my army".
##
## Geometry, not pixels, is the right gate here: the failure is a rect overlap that
## a shot can only catch on the one seed that happens to reproduce it, whereas
## _plaque_rect can be swept over every relative position in a fraction of a second.

var _fails: Array[String] = []
var _ran := false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails.append(label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var MV := load("res://scripts/scenes/MapView.gd")
	var overlay = MV.MapPulseOverlay.new()
	# A stand-in "map" the overlay only reads size / player position off. Using the
	# real MapTerrain would drag in a generated act for a pure geometry question.
	var fake := FakeMap.new()
	fake.size = Vector2(1600, 900)
	overlay.map = fake
	overlay.size = fake.size

	print("— the plaque clears the standard from every relative direction")
	# The standard sits mid-chart; sweep the destination all around it at the real
	# lane pitch (~0.100 * h = 90px) and column spacing the war table uses.
	fake._player_pos = Vector2(700.0, 480.0)
	var widths: Array[float] = [116.0, 180.0, 250.0]
	var tested := 0
	for dx in [-260, -180, -100, -40, 0, 40, 100, 180, 260]:
		for dy in [-180, -90, -45, 0, 45, 90, 180]:
			var dest := fake._player_pos + Vector2(float(dx), float(dy))
			for w in widths:
				var r: Rect2 = overlay._plaque_rect(dest, w, 27.0)
				var keep: Rect2 = overlay._standard_keepout()
				tested += 1
				_check(not r.intersects(keep),
					"dest %+d,%+d w%d: plaque clears the standard" % [dx, dy, int(w)])
				# It must also stay on the sheet — the old code clamped x for this
				# reason and the slide path must not undo it.
				_check(r.position.x >= 35.0
						and r.position.x + r.size.x <= fake.size.x - 35.0,
					"dest %+d,%+d w%d: plaque stays on the sheet" % [dx, dy, int(w)])
				# And it must stay near its own pin, or it stops labelling it.
				_check(absf(r.get_center().y - dest.y) < 260.0,
					"dest %+d,%+d w%d: plaque stays near its pin" % [dx, dy, int(w)])
	print("  swept %d placements" % tested)

	print("— a destination near the top edge still hangs BELOW")
	# The original rule exists because a plaque above a top-row pin leaves the
	# sheet. Verify the avoidance did not eat it.
	fake._player_pos = Vector2(200.0, 700.0)   # standard far away, no interference
	var top: Rect2 = overlay._plaque_rect(Vector2(800.0, 120.0), 180.0, 27.0)
	_check(top.position.y > 120.0, "a top-edge pin labels below itself")
	_check(top.position.y + top.size.y <= 900.0, "and stays on the sheet")

	print("— the camp gate is the standard's home before the first claim")
	fake._has_player = false
	var camp: Vector2 = overlay._standard_point()
	_check(camp.is_equal_approx(fake._camp_pos + Vector2(30, -4)),
		"with no claimed stop the standard stands at the camp gate")

	overlay.free()
	fake.free()
	if _fails.is_empty():
		print("[map-plaque] ALL PASS")
		quit(0)
	else:
		print("[map-plaque] FAIL — %d problem(s):" % _fails.size())
		for f in _fails.slice(0, 12):
			print("  x ", f)
		quit(1)
	return true


## The two fields _standard_point reads, and the size _plaque_rect clamps against.
class FakeMap extends Control:
	var _has_player: bool = true
	var _player_pos: Vector2 = Vector2(700, 480)
	var _camp_pos: Vector2 = Vector2(120, 480)
