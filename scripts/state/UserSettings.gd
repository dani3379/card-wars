extends Node
## UserSettings.gd — autoload. Persists player preferences to user://settings.save.
## Also creates audio buses (Master/Music/SFX) on startup.

const SAVE_PATH := "user://settings.save"

# Minimum sane window size — guards against a corrupt save file (e.g. stored
# 0×0) shrinking the window to a few pixels. Anything smaller than this and we
# replace it with a safe default that fits the user's screen.
const MIN_RES := Vector2i(1024, 576)
const DEFAULT_RES := Vector2i(1600, 900)

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false
var screen_shake: bool = true
var particles: bool = true
var resolution: Vector2i = DEFAULT_RES
# Persistent tutorial flags — once dismissed, never shown again.
var floop_tutorial_seen: bool = false


func mark_floop_tutorial_seen() -> void:
	if floop_tutorial_seen:
		return
	floop_tutorial_seen = true
	save()

var _bus_music: int = -1
var _bus_sfx: int = -1


const SettingsOverlay = preload("res://scripts/ui/SettingsOverlay.gd")

func _ready() -> void:
	_setup_audio_buses()
	load_settings()
	_clamp_resolution_to_screen()
	_apply_all()
	call_deferred("_spawn_overlay")


func _get_usable_rect() -> Rect2i:
	var screen := DisplayServer.window_get_current_screen()
	return DisplayServer.screen_get_usable_rect(screen)


func _clamp_resolution_to_screen() -> void:
	# Guard against (a) a corrupt save file with 0×0 or otherwise tiny
	# values, and (b) a saved resolution larger than the current monitor
	# (e.g. the user moved to a smaller screen). Both would leave the window
	# unusable. Snap to DEFAULT_RES clamped to screen size in that case.
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var changed := false
	if resolution.x < MIN_RES.x or resolution.y < MIN_RES.y:
		resolution = Vector2i(
			min(DEFAULT_RES.x, screen_size.x),
			min(DEFAULT_RES.y, screen_size.y))
		changed = true
	elif resolution.x > screen_size.x or resolution.y > screen_size.y:
		resolution = Vector2i(
			min(resolution.x, screen_size.x),
			min(resolution.y, screen_size.y))
		changed = true
	if changed:
		save()


func get_available_resolutions(candidates: Array) -> Array:
	# Use full screen size (not usable rect) — users expect to see their
	# monitor's native resolution even though the taskbar eats some height.
	# The apply step clamps to usable area if needed.
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var out: Array = []
	for r in candidates:
		if r.x <= screen_size.x and r.y <= screen_size.y:
			out.append(r)
	if out.is_empty() and candidates.size() > 0:
		out.append(candidates[0])
	return out


func _spawn_overlay() -> void:
	var overlay := SettingsOverlay.new()
	add_child(overlay)


func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_bus_music = AudioServer.get_bus_index("Music")
	_bus_sfx = AudioServer.get_bus_index("SFX")


func _apply_all() -> void:
	_apply_volume(0, master_volume)
	_apply_volume(_bus_music, music_volume)
	_apply_volume(_bus_sfx, sfx_volume)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		call_deferred("_apply_resolution")


func _apply_volume(bus: int, linear: float) -> void:
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear))
	AudioServer.set_bus_mute(bus, linear <= 0.0)


func set_master_volume(val: float) -> void:
	master_volume = val
	_apply_volume(0, val)
	save()

func set_music_volume(val: float) -> void:
	music_volume = val
	_apply_volume(_bus_music, val)
	save()

func set_sfx_volume(val: float) -> void:
	sfx_volume = val
	_apply_volume(_bus_sfx, val)
	save()

func set_fullscreen(val: bool) -> void:
	fullscreen = val
	if val:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		call_deferred("_apply_resolution")
	save()

func set_resolution(val: Vector2i) -> void:
	resolution = val
	if not fullscreen:
		_apply_resolution()
	save()

func _apply_resolution() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await get_tree().process_frame
	# Clamp to the monitor's usable area (excludes Windows taskbar) and to a
	# floor of MIN_RES so a corrupt value can never produce a tiny window.
	var usable := _get_usable_rect()
	var clamped := Vector2i(
		clampi(resolution.x, MIN_RES.x, usable.size.x),
		clampi(resolution.y, MIN_RES.y, usable.size.y))
	get_window().size = clamped
	# Center within the current monitor's usable rect — `usable.position` is
	# non-zero on a secondary monitor, so the naive (screen - window)/2 formula
	# would place the window on the wrong screen.
	var pos := usable.position + (usable.size - clamped) / 2
	DisplayServer.window_set_position(pos)

func set_screen_shake(val: bool) -> void:
	screen_shake = val
	save()

func set_particles(val: bool) -> void:
	particles = val
	save()
	var scene = get_tree().current_scene
	if scene:
		var motes = scene.find_child("AmbientMotes", true, false)
		if motes:
			motes.emitting = val
			motes.visible = val


func save() -> void:
	var data := {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"screen_shake": screen_shake,
		"particles": particles,
		"resolution_x": resolution.x,
		"resolution_y": resolution.y,
		"floop_tutorial_seen": floop_tutorial_seen,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		master_volume = parsed.get("master_volume", 1.0)
		music_volume = parsed.get("music_volume", 0.8)
		sfx_volume = parsed.get("sfx_volume", 1.0)
		fullscreen = parsed.get("fullscreen", false)
		screen_shake = parsed.get("screen_shake", true)
		particles = parsed.get("particles", true)
		var rx: int = int(parsed.get("resolution_x", 1600))
		var ry: int = int(parsed.get("resolution_y", 900))
		resolution = Vector2i(rx, ry)
		floop_tutorial_seen = parsed.get("floop_tutorial_seen", false)
