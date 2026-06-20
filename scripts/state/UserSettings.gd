extends Node
## UserSettings.gd — autoload. Persists player preferences to user://settings.save.
## Also creates audio buses (Master/Music/SFX) on startup.

# Emitted when brightness/colorblind change so any active scene can refresh
# its overlay/theme without rebuilding from scratch.
signal brightness_changed(value: float)
signal colorblind_changed(mode: String)

const SAVE_PATH := "user://settings.save"

# Minimum sane window size — guards against a corrupt save file (e.g. stored
# 0×0) shrinking the window to a few pixels. Anything smaller than this and we
# replace it with a safe default that fits the user's screen.
const MIN_RES := Vector2i(1024, 576)
const DEFAULT_RES := Vector2i(1600, 900)

var master_volume: float = 1.0
# Music sits ~30% below master by default — full-volume music drowns out SFX
# and the player's own attention. Players can still push it back up in the
# settings overlay if they want.
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var fullscreen: bool = false
var screen_shake: bool = true
var particles: bool = true
var vsync: bool = true
# Display mode: "windowed", "borderless", "fullscreen". Supersedes the older
# `fullscreen` bool — kept around for backward compat with old saves.
var display_mode: String = "windowed"
# Cap engine framerate. 0 = unlimited (V-Sync still applies if enabled).
var fps_cap: int = 0
# UI scale (0.8 .. 1.5). Multiplies window content_scale_factor — independent
# of the project-level stretch settings, so it scales all canvas_items together.
var ui_scale: float = 1.0
# Brightness offset in [-0.4, +0.4]. Applied via a fullscreen ColorRect overlay
# (additive black or white at low alpha), not a gamma shader — keeps the GL
# Compatibility renderer fast.
var brightness: float = 0.0
# Animation speed multiplier. 0.5 = slow, 1.0 = normal, 1.5 = fast, 3.0 = instant.
# Combat pause helpers and tween durations divide their base time by this.
var anim_speed: float = 1.0
# Tooltip / hover-popup delay in seconds. 0 = instant.
var tooltip_delay: float = 0.0
# Color blind palette mode: "off" (default red/green), "deuteranopia" (red→orange,
# green→blue), "protanopia" (similar), "tritanopia" (blue/yellow swap).
var colorblind_mode: String = "off"
# Reduce motion: master kill-switch for non-essential animations (card sway,
# pulses, screen shake, particles, intro flourishes). When ON, also forces
# screen_shake and particles off regardless of their individual settings.
var reduce_motion: bool = false
# Show a "you still have mana / cards" modal before ending turn.
var end_turn_warning: bool = true
# Combat telegraph: when hovering a battlefield creature, draw an arrow to the
# creature it will strike plus a DIES/-N/SURVIVES outcome chip. Per-frame work
# while a creature is hovered, so it's a toggle for players who want it off.
var combat_telegraph: bool = true
# Mute audio when the window loses focus.
var mute_on_focus_loss: bool = true
var resolution: Vector2i = DEFAULT_RES
# Persistent tutorial flags — once dismissed, never shown again.
var floop_tutorial_seen: bool = false
var sacrifice_tutorial_seen: bool = false
var banking_tutorial_seen: bool = false
var intents_tutorial_seen: bool = false
var pile_tutorial_seen: bool = false
# Taught once on the first End Turn: the simultaneous-combat model — the single
# most counter-intuitive rule (both sides strike at once; front rank fights and
# is struck first; the back rank waits in reserve).
var combat_model_tutorial_seen: bool = false


func mark_floop_tutorial_seen() -> void:
	if floop_tutorial_seen:
		return
	floop_tutorial_seen = true
	save()


func mark_sacrifice_tutorial_seen() -> void:
	if sacrifice_tutorial_seen:
		return
	sacrifice_tutorial_seen = true
	save()


func mark_banking_tutorial_seen() -> void:
	if banking_tutorial_seen:
		return
	banking_tutorial_seen = true
	save()


func mark_intents_tutorial_seen() -> void:
	if intents_tutorial_seen:
		return
	intents_tutorial_seen = true
	save()


func mark_pile_tutorial_seen() -> void:
	if pile_tutorial_seen:
		return
	pile_tutorial_seen = true
	save()


func mark_combat_model_tutorial_seen() -> void:
	if combat_model_tutorial_seen:
		return
	combat_model_tutorial_seen = true
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
	# Hook into window focus for mute-on-focus-loss.
	if get_window() != null:
		get_window().focus_entered.connect(func(): _on_main_window_focus_changed(true))
		get_window().focus_exited.connect(func(): _on_main_window_focus_changed(false))


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
	_apply_vsync()
	_apply_fps_cap()
	call_deferred("_apply_ui_scale")
	_apply_display_mode()


func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_fps_cap() -> void:
	# 0 = unlimited (Engine.max_fps convention).
	Engine.max_fps = max(0, fps_cap)


func _apply_ui_scale() -> void:
	# content_scale_factor scales all canvas_items uniformly. We deferred so it
	# runs after the initial scene tree builds — applying too early during
	# _ready can race the autoload setup.
	if get_window() != null:
		get_window().content_scale_factor = clampf(ui_scale, 0.6, 1.8)


func _apply_display_mode() -> void:
	# Three-way mode: windowed / borderless / fullscreen. Borderless is
	# windowed mode with the decoration flag cleared, sized to the monitor.
	match display_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_window().borderless = false
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			await get_tree().process_frame
			var screen := DisplayServer.window_get_current_screen()
			var screen_size := DisplayServer.screen_get_size(screen)
			get_window().borderless = true
			get_window().size = screen_size
			DisplayServer.window_set_position(Vector2i.ZERO)
		_:  # "windowed"
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().borderless = false
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


func set_vsync(val: bool) -> void:
	vsync = val
	_apply_vsync()
	save()


func set_fps_cap(val: int) -> void:
	fps_cap = max(0, val)
	_apply_fps_cap()
	save()


func set_ui_scale(val: float) -> void:
	ui_scale = clampf(val, 0.6, 1.8)
	_apply_ui_scale()
	save()


func set_brightness(val: float) -> void:
	brightness = clampf(val, -0.4, 0.4)
	save()
	# Brightness applies via a per-scene fullscreen overlay; GameTheme rebuilds it
	# on scene change. Existing overlay (if any) refreshes via a signal.
	brightness_changed.emit(brightness)


func set_anim_speed(val: float) -> void:
	anim_speed = clampf(val, 0.5, 3.0)
	save()


func set_tooltip_delay(val: float) -> void:
	tooltip_delay = clampf(val, 0.0, 0.5)
	save()


func set_colorblind_mode(val: String) -> void:
	colorblind_mode = val
	save()
	colorblind_changed.emit(val)


func set_reduce_motion(val: bool) -> void:
	reduce_motion = val
	save()
	# When ON, force screen_shake and particles off live — the player chose
	# accessibility over flair, so respect that everywhere.
	if val:
		set_screen_shake(false)
		set_particles(false)


func set_end_turn_warning(val: bool) -> void:
	end_turn_warning = val
	save()


func set_combat_telegraph(val: bool) -> void:
	combat_telegraph = val
	save()


func set_mute_on_focus_loss(val: bool) -> void:
	mute_on_focus_loss = val
	save()


func set_display_mode(val: String) -> void:
	display_mode = val
	fullscreen = (val == "fullscreen")  # backward compat
	_apply_display_mode()
	save()


# Returns a scaled animation duration. Callers use:
#   var t := UserSettings.anim_time(0.5)
#   create_tween().tween_property(...).set_duration(t)
# Or short-pause callers (Combat._short_pause) multiply by anim_speed.
func anim_time(base_seconds: float) -> float:
	if anim_speed <= 0.001:
		return 0.001
	return base_seconds / anim_speed


# Window focus → mute / unmute audio. Wired up in _ready().
func _on_main_window_focus_changed(focused: bool) -> void:
	if not mute_on_focus_loss:
		return
	# Set bus volume to silent when unfocused, restore when refocused.
	if focused:
		_apply_volume(0, master_volume)
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(0.0))
		AudioServer.set_bus_mute(0, true)


func save() -> void:
	var data := {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"screen_shake": screen_shake,
		"particles": particles,
		"vsync": vsync,
		"display_mode": display_mode,
		"fps_cap": fps_cap,
		"ui_scale": ui_scale,
		"brightness": brightness,
		"anim_speed": anim_speed,
		"tooltip_delay": tooltip_delay,
		"colorblind_mode": colorblind_mode,
		"reduce_motion": reduce_motion,
		"end_turn_warning": end_turn_warning,
		"combat_telegraph": combat_telegraph,
		"mute_on_focus_loss": mute_on_focus_loss,
		"resolution_x": resolution.x,
		"resolution_y": resolution.y,
		"floop_tutorial_seen": floop_tutorial_seen,
		"sacrifice_tutorial_seen": sacrifice_tutorial_seen,
		"banking_tutorial_seen": banking_tutorial_seen,
		"intents_tutorial_seen": intents_tutorial_seen,
		"pile_tutorial_seen": pile_tutorial_seen,
		"combat_model_tutorial_seen": combat_model_tutorial_seen,
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
		music_volume = parsed.get("music_volume", 0.7)
		sfx_volume = parsed.get("sfx_volume", 1.0)
		fullscreen = parsed.get("fullscreen", false)
		screen_shake = parsed.get("screen_shake", true)
		particles = parsed.get("particles", true)
		vsync = parsed.get("vsync", true)
		display_mode = parsed.get("display_mode", "fullscreen" if fullscreen else "windowed")
		fps_cap = int(parsed.get("fps_cap", 0))
		ui_scale = float(parsed.get("ui_scale", 1.0))
		brightness = float(parsed.get("brightness", 0.0))
		anim_speed = float(parsed.get("anim_speed", 1.0))
		tooltip_delay = float(parsed.get("tooltip_delay", 0.0))
		colorblind_mode = parsed.get("colorblind_mode", "off")
		reduce_motion = parsed.get("reduce_motion", false)
		end_turn_warning = parsed.get("end_turn_warning", true)
		combat_telegraph = parsed.get("combat_telegraph", true)
		mute_on_focus_loss = parsed.get("mute_on_focus_loss", true)
		var rx: int = int(parsed.get("resolution_x", 1600))
		var ry: int = int(parsed.get("resolution_y", 900))
		resolution = Vector2i(rx, ry)
		floop_tutorial_seen = parsed.get("floop_tutorial_seen", false)
		sacrifice_tutorial_seen = parsed.get("sacrifice_tutorial_seen", false)
		banking_tutorial_seen = parsed.get("banking_tutorial_seen", false)
		intents_tutorial_seen = parsed.get("intents_tutorial_seen", false)
		pile_tutorial_seen = parsed.get("pile_tutorial_seen", false)
		combat_model_tutorial_seen = parsed.get("combat_model_tutorial_seen", false)
