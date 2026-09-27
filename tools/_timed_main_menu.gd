extends "res://scripts/scenes/MainMenu.gd"
## QA-only subclass that accumulates inclusive construction time by helper.

var _perf_totals: Dictionary = {}
var _perf_calls: Dictionary = {}


func _add_sample(label: String, started: int) -> void:
	_perf_totals[label] = float(_perf_totals.get(label, 0.0)) \
		+ float(Time.get_ticks_usec() - started) / 1000.0
	_perf_calls[label] = int(_perf_calls.get(label, 0)) + 1


func perf_reset() -> void:
	_perf_totals.clear()
	_perf_calls.clear()


func perf_report() -> void:
	var rows: Array[Dictionary] = []
	for label in _perf_totals:
		rows.append({
			"label": String(label),
			"ms": float(_perf_totals[label]),
			"calls": int(_perf_calls[label]),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.ms) > float(b.ms))
	for row in rows:
		print("[menu-helper] %-24s total=%7.2fms calls=%d avg=%6.3fms" % [
			row.label, row.ms, row.calls, row.ms / maxf(float(row.calls), 1.0)])


func _make_menu_button(text: String, bg: Color, font_size: int, height: int,
		with_flame: bool = true) -> Button:
	var started := Time.get_ticks_usec()
	var result := super._make_menu_button(text, bg, font_size, height, with_flame)
	_add_sample("make_menu_button", started)
	return result


func _make_display_label(text: String, size: int, color: Color) -> Label:
	var started := Time.get_ticks_usec()
	var result := super._make_display_label(text, size, color)
	_add_sample("make_display_label", started)
	return result


func _make_caption_label(text: String, size: int, color: Color) -> Label:
	var started := Time.get_ticks_usec()
	var result := super._make_caption_label(text, size, color)
	_add_sample("make_caption_label", started)
	return result


func _make_ornament_row(width: float, left_aligned: bool = false,
		glyph: bool = false, stretch: bool = false) -> Control:
	var started := Time.get_ticks_usec()
	var result := super._make_ornament_row(width, left_aligned, glyph, stretch)
	_add_sample("make_ornament_row", started)
	return result


func _make_flame_accent() -> TextureRect:
	var started := Time.get_ticks_usec()
	var result := super._make_flame_accent()
	_add_sample("make_flame_accent", started)
	return result


func _build_campaign_record() -> Control:
	var started := Time.get_ticks_usec()
	var result := super._build_campaign_record()
	_add_sample("build_campaign_record", started)
	return result


func _build_command_dossier(has_any_save: bool) -> void:
	var started := Time.get_ticks_usec()
	super._build_command_dossier(has_any_save)
	_add_sample("build_command_dossier", started)


func _any_save_exists() -> bool:
	var started := Time.get_ticks_usec()
	var result := super._any_save_exists()
	_add_sample("any_save_exists", started)
	return result


func _filled_slot_count() -> int:
	var started := Time.get_ticks_usec()
	var result := super._filled_slot_count()
	_add_sample("filled_slot_count", started)
	return result


func _most_recent_slot() -> int:
	var started := Time.get_ticks_usec()
	var result := super._most_recent_slot()
	_add_sample("most_recent_slot", started)
	return result


func _continue_preview_line(slot: int, verbose: bool = false) -> String:
	var started := Time.get_ticks_usec()
	var result := super._continue_preview_line(slot, verbose)
	_add_sample("continue_preview_line", started)
	return result


func _dossier_icon(path: String, sz: float, tint: Color) -> TextureRect:
	var started := Time.get_ticks_usec()
	var result := super._dossier_icon(path, sz, tint)
	_add_sample("dossier_icon", started)
	return result


## Was `_dossier_row` until the 2026-09-18 dossier rebuild replaced the
## dotted-leader rows with drawn figures; same job, one more parameter.
func _dossier_figure(parent: VBoxContainer, caption: String, value: String,
		accent: Color, track: Control) -> void:
	var started := Time.get_ticks_usec()
	super._dossier_figure(parent, caption, value, accent, track)
	_add_sample("dossier_figure", started)
