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
# Floor for the window size. Raised from 1024×576 → 1366×768: the combat board
# lays out 4 fixed-width lanes (4×204px + gaps ≈ 876px) inside a zone that is
# `window_width − 544`, so a canvas narrower than ~1360px overflows the play area
# and the lanes collide with the side UI. Gating the minimum is the chosen
# stopgap; the proper fix is a fixed design canvas (stretch=canvas_items).
const MIN_RES := Vector2i(1366, 768)
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
# Render scale / supersampling (1.0 .. 2.0). 1.0 = native (off). Above 1.0 runs
# the whole game in a SubViewport rendered at render_scale× the window and
# downsampled — true 2D SSAA for crisp procedural draws/fonts. Applied via the
# Supersample autoload. Costs ~scale² the GPU fill, so it's opt-in.
var render_scale: float = 1.0
# Graphics quality preset. "auto" resolves to a concrete tier from the detected
# GPU/CPU/RAM each launch (so it adapts if the hardware changes); "low"/"medium"/
# "high"/"ultra" are fixed tiers that drive the heavy perf levers together;
# "custom" means the player hand-tuned an individual graphics control. Fresh
# installs start on "auto" so the game self-configures to the machine on run 1.
var graphics_preset: String = "auto"
var _detected_preset_cache: String = ""

# Each tier sets the two levers that actually move the framerate: whole-screen
# supersampling (the dominant GPU cost) and ambient particles. MSAA is
# deliberately NOT a lever — 2D MSAA is a no-op in the gl_compatibility renderer
# (engine issue #69462), so exposing it would be a lie.
const GRAPHICS_PRESETS := {
	"low":    {"render_scale": 1.0, "particles": false},
	"medium": {"render_scale": 1.0, "particles": true},
	"high":   {"render_scale": 1.5, "particles": true},
	"ultra":  {"render_scale": 2.0, "particles": true},
}
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
	# Fresh install (no save file → preset stays "auto"): read the machine and
	# apply the matching tier a frame after boot, once the tree has settled.
	if graphics_preset == "auto":
		call_deferred("apply_graphics_preset", "auto", false)
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
	call_deferred("_apply_render_scale")
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
	graphics_preset = "custom"  # hand-tuned → no longer a named preset
	_apply_particles_live()
	save()


func _apply_particles_live() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var motes = scene.find_child("AmbientMotes", true, false)
	if motes:
		motes.emitting = particles
		motes.visible = particles


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


func set_render_scale(val: float) -> void:
	render_scale = clampf(val, 1.0, 2.0)
	graphics_preset = "custom"  # hand-tuned → no longer a named preset
	_apply_render_scale()
	save()


func _apply_render_scale() -> void:
	# Supersample is an autoload; guard in case of early call ordering.
	var ss = get_node_or_null("/root/Supersample")
	if ss != null:
		ss.apply_scale(render_scale)


# ── Graphics quality presets ─────────────────────────────────────────────────

## Apply a named preset. "auto" resolves to a hardware-matched tier; "custom"
## leaves the current values alone (the player is hand-tuning). Anything else
## sets render_scale + particles from GRAPHICS_PRESETS and applies them live.
func apply_graphics_preset(name: String, persist: bool = true) -> void:
	graphics_preset = name
	if name != "custom":
		var tier := resolve_preset(name)
		var p: Dictionary = GRAPHICS_PRESETS.get(tier, GRAPHICS_PRESETS["medium"])
		render_scale = clampf(float(p["render_scale"]), 1.0, 2.0)
		particles = bool(p["particles"])
		_apply_render_scale()
		_apply_particles_live()
	if persist:
		save()


## "auto" → a concrete tier chosen from the machine; every other name maps to
## itself (callers guard "custom" separately).
func resolve_preset(name: String) -> String:
	if name == "auto":
		return detect_recommended_preset()
	return name


## Best-effort hardware match, cached for the session. Reads GPU name/type, CPU
## cores, total RAM and monitor size, then returns the heaviest tier the machine
## should run comfortably. Caps at "high": Ultra (2× supersample = 4× fill) stays
## a deliberate opt-in so Auto can never tank someone's framerate.
func detect_recommended_preset() -> String:
	if _detected_preset_cache == "":
		_detected_preset_cache = _compute_recommended_preset()
	return _detected_preset_cache


## Human-readable adapter name for the settings read-out ("NVIDIA GeForce ...").
func get_gpu_name() -> String:
	var n := str(RenderingServer.get_video_adapter_name())
	return n if n != "" else "Unknown GPU"


func _compute_recommended_preset() -> String:
	var gpu := str(RenderingServer.get_video_adapter_name()).to_lower()
	# Device type is the cleanest signal WHEN reported — but the compatibility
	# backend often returns OTHER, so it's only a tie-breaker, not the basis.
	# RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU=1, DISCRETE=2, CPU=4.
	var adapter_type := int(RenderingServer.get_video_adapter_type())

	var cores := OS.get_processor_count()
	var ram_gb := 0.0
	var mem = OS.get_memory_info()
	if mem is Dictionary and int(mem.get("physical", -1)) > 0:
		ram_gb = float(mem["physical"]) / 1073741824.0  # bytes → GiB
	var native: Vector2i = DisplayServer.screen_get_size()
	var is_4k := native.x >= 3840 or native.y >= 2160

	# GPU class: 3 = high-end discrete, 2 = solid discrete, 1 = integrated/entry.
	var gpu_class := 1
	var high_end := ["rtx 20", "rtx 30", "rtx 40", "rtx 50",
		"radeon rx 6", "radeon rx 7", "radeon rx 9", "arc a7", "arc b"]
	var mid_disc := ["geforce", "gtx 10", "gtx 16", "radeon rx", "quadro", "arc a"]
	# Integrated markers. Bare "intel" is omitted on purpose — Intel Arc is a
	# discrete line, so we key off the integrated family names instead.
	var integrated := ["uhd", "hd graphics", "iris", "vega",
		"radeon(tm) graphics", "radeon graphics", "apple m"]
	for k in high_end:
		if gpu.find(k) != -1:
			gpu_class = 3
			break
	if gpu_class < 3:
		for k in mid_disc:
			if gpu.find(k) != -1:
				gpu_class = 2
				break
	var looks_integrated := false
	for k in integrated:
		if gpu.find(k) != -1:
			looks_integrated = true
			break
	if adapter_type == 1:
		looks_integrated = true
	elif adapter_type == 2 and gpu_class < 2:
		gpu_class = 2
	elif adapter_type == 4:
		gpu_class = 0
	if looks_integrated and gpu_class > 1:
		gpu_class = 1

	var tier := "medium"
	match gpu_class:
		3, 2: tier = "high"
		1: tier = "medium"
		_: tier = "low"
	# Hard floors — a dual-core or low-RAM box shouldn't run SSAA + particles.
	if cores <= 2 or (ram_gb > 0.0 and ram_gb < 6.0):
		tier = "low"
	# A 4K monitor makes whole-screen SSAA brutal (render_scale multiplies an
	# already-huge framebuffer), so 4K users default to native unless they opt up.
	if is_4k and tier == "high":
		tier = "medium"
	return tier


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
		"render_scale": render_scale,
		"graphics_preset": graphics_preset,
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
		render_scale = float(parsed.get("render_scale", 1.0))
		# Saves that predate presets had hand-set graphics values, so default them
		# to "custom" — never silently override a returning player's choices. Only
		# a fresh install (no file at all → this block is skipped) keeps "auto".
		graphics_preset = str(parsed.get("graphics_preset", "custom"))
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
