extends "res://scripts/scenes/GameOver.gd"
## QA-only subclass that accumulates inclusive Game Over startup helper costs.

var _perf_totals: Dictionary = {}
var _perf_calls: Dictionary = {}


func _sample(label: String, started: int) -> void:
	_perf_totals[label] = float(_perf_totals.get(label, 0.0)) \
		+ float(Time.get_ticks_usec() - started) / 1000.0
	_perf_calls[label] = int(_perf_calls.get(label, 0)) + 1


func perf_report() -> void:
	var rows: Array[Dictionary] = []
	for label in _perf_totals:
		rows.append({"label": String(label), "ms": float(_perf_totals[label]),
			"calls": int(_perf_calls[label])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.ms) > float(b.ms))
	for row in rows:
		print("[game-over-helper] %-25s total=%7.2fms calls=%d avg=%6.3fms" % [
			row.label, row.ms, row.calls,
			row.ms / maxf(float(row.calls), 1.0)])


func _build_run_summary() -> void:
	var started := Time.get_ticks_usec()
	super._build_run_summary()
	_sample("build_run_summary", started)


func _spawn_run_end_flourish(won: bool) -> void:
	var started := Time.get_ticks_usec()
	super._spawn_run_end_flourish(won)
	_sample("spawn_end_flourish", started)


func _add_seed_chip() -> void:
	var started := Time.get_ticks_usec()
	super._add_seed_chip()
	_sample("add_seed_chip", started)


func _animate_intro() -> void:
	var started := Time.get_ticks_usec()
	super._animate_intro()
	_sample("animate_intro", started)


func _add_campaign_memory_section(col: VBoxContainer) -> void:
	var started := Time.get_ticks_usec()
	super._add_campaign_memory_section(col)
	_sample("campaign_memory", started)


func _add_separator(col: VBoxContainer) -> void:
	var started := Time.get_ticks_usec()
	super._add_separator(col)
	_sample("add_separator", started)


func _section_head(col: VBoxContainer, text: String) -> void:
	var started := Time.get_ticks_usec()
	super._section_head(col, text)
	_sample("section_head", started)


func _stat_chip(label: String, value: String,
		is_gold: bool = false) -> VBoxContainer:
	var started := Time.get_ticks_usec()
	var result := super._stat_chip(label, value, is_gold)
	_sample("stat_chip", started)
	return result


func _make_summary_label(text: String, size: int, color: Color) -> Label:
	var started := Time.get_ticks_usec()
	var result := super._make_summary_label(text, size, color)
	_sample("summary_label", started)
	return result


func _ink_button(btn: Button, hover: Color) -> void:
	var started := Time.get_ticks_usec()
	super._ink_button(btn, hover)
	_sample("ink_button", started)
