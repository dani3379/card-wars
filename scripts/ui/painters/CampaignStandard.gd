extends Control
## Small reusable company standard used by the Spoils ceremony. Its physical
## additions are run history: wax seals for completed marches, ribbons for
## broken Generals, and mourning cloth when the Roll of the Fallen is nonempty.

var accent := Color(0.82, 0.60, 0.24)
var acts_won := 0
var generals_broken := 0
var fallen_count := 0


func configure(completed_acts: int, generals: int, fallen: int,
		banner_color: Color) -> void:
	acts_won = clampi(completed_acts, 0, 3)
	generals_broken = maxi(generals, 0)
	fallen_count = maxi(fallen, 0)
	accent = banner_color
	custom_minimum_size = Vector2(142, 104)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var pole_x := 38.0
	var top_y := 12.0
	var foot_y := 91.0
	# Contact shadow + iron pole.
	draw_line(Vector2(pole_x + 3.0, top_y + 3.0),
		Vector2(pole_x + 3.0, foot_y + 3.0), Color(0, 0, 0, 0.34), 4.0, true)
	draw_line(Vector2(pole_x, top_y), Vector2(pole_x, foot_y),
		Color(0.13, 0.09, 0.055), 3.0, true)
	draw_circle(Vector2(pole_x, top_y), 3.2, Color(0.90, 0.73, 0.30), true, -1.0, true)
	# Swallow-tail banner.
	var flag := PackedVector2Array([
		Vector2(pole_x, 18), Vector2(119, 22), Vector2(98, 38),
		Vector2(119, 54), Vector2(pole_x, 49)])
	draw_colored_polygon(flag, accent)
	var closed := flag.duplicate()
	closed.append(flag[0])
	draw_polyline(closed, Color(0.12, 0.075, 0.04, 0.88), 1.5, true)
	draw_line(Vector2(pole_x + 7, 25), Vector2(102, 28),
		Color(1.0, 0.91, 0.62, 0.24), 1.5, true)
	# A small black streamer is readable even at one fallen soldier; length
	# grows only slightly so a large roll never turns into visual clutter.
	if fallen_count > 0:
		var mourning_len := minf(34.0 + float(fallen_count - 1) * 2.0, 48.0)
		var mourning := PackedVector2Array([
			Vector2(46, 49), Vector2(56, 50), Vector2(52, 50 + mourning_len),
			Vector2(47, 43 + mourning_len)])
		draw_colored_polygon(mourning, Color(0.055, 0.045, 0.042, 0.96))
	# General ribbons hang from the spear crossbar. Cap the visible count; the
	# shape communicates honors, while the reward copy carries exact numbers.
	for i in range(mini(generals_broken, 5)):
		var rx := 66.0 + float(i) * 9.0
		var ribbon_col := Color(0.74, 0.18, 0.11).lerp(
			Color(0.92, 0.66, 0.24), float(i % 2) * 0.35)
		draw_colored_polygon(PackedVector2Array([
			Vector2(rx, 51), Vector2(rx + 6, 51), Vector2(rx + 5, 68),
			Vector2(rx + 3, 65), Vector2(rx + 1, 68)]), ribbon_col)
	# Completed marches become wax seals at the foot of the standard.
	for i in range(acts_won):
		var p := Vector2(62.0 + float(i) * 23.0, 86.0)
		draw_circle(p + Vector2(2, 2), 9.0, Color(0, 0, 0, 0.24), true, -1.0, true)
		draw_circle(p, 9.0, Color(0.54, 0.10, 0.075), true, -1.0, true)
		draw_arc(p, 6.0, 0, TAU, 18, Color(0.88, 0.45, 0.24, 0.65), 1.2, true)
	# The planted foot.
	draw_line(Vector2(23, foot_y), Vector2(54, foot_y),
		Color(0.18, 0.11, 0.055, 0.82), 3.0, true)
