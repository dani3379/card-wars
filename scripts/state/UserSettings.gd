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
# Render scale / supersampling (1.0 .. 2.0). 1.0 = native (off). Above 1.0 runs
# the whole game in a SubViewport rendered at render_scale× the window and
# downsampled — true 2D SSAA for crisp procedural draws/fonts. Applied via the
# Supersample autoload. Costs ~scale² the GPU fill, so it's opt-in.
var render_scale: float = 1.0
# Keep the selected supersampling as a quality ceiling, but let sustained combat
# pressure temporarily step it down. The temporary value is never persisted.
var adaptive_render_scale: bool = true
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
# The discrete stops the settings screen offers, slowest → fastest. They live
# HERE rather than in SettingsOverlay so that load-time normalisation and the
# dropdown's selected index read the same table and can never disagree — the
# old split let the row display "Slow" while the stored value was something
# else entirely. Discrete named stops (Celeste's Assist Mode ships six, 50–100%)
# beat a continuous slider: a named state is one a player can describe, return
# to, and reason about.
const ANIM_SPEED_STEPS := [0.34, 0.5, 1.0, 1.5, 3.0]
const ANIM_SPEED_MIN := 0.34
const ANIM_SPEED_MAX := 3.0

# ── Clash dwell ──────────────────────────────────────────────────────────────
# Multiplier on Combat's per-lane clash dwell — how long the clash HOLDS on a
# lane before the spotlight moves to the next one. 0.0 = no dwell at all.
#
# WHY THIS IS A SEPARATE SETTING AND NOT FOLDED INTO anim_speed:
#   * anim_speed scales EVERY tween in the game — menu slides, card deals, map
#     pans, hover lifts, the whole shell. It answers "how fast should this
#     software move".
#   * the clash dwell is dead time ON PURPOSE: the pause that lets the eye land
#     on one lane and read the exchange there (see
#     docs/COMBAT_LEGIBILITY_20260728.md §7 — the serialized clash). It answers
#     "how long do I get to read".
# Those are different questions and players answer them differently. Someone who
# has watched the deal animation a thousand times wants snappy tweens AND a long
# read on the clash; a player who finds the board busy may want the reverse.
# One dial forces a trade neither of them asked for. Speed is also never allowed
# to be an engine-chosen ramp here (the Hearthstone Battlegrounds auto-
# acceleration failure the legibility doc cites) — it is player-owned, always.
var clash_dwell_scale: float = 1.0
const CLASH_DWELL_STEPS := [0.0, 0.6, 1.0, 1.5, 2.0]
const CLASH_DWELL_MIN := 0.0
const CLASH_DWELL_MAX := 2.0
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
# Combat field-ground style: 0 war table / 1 meadow / 2 obsidian / 3 battle-plan.
# Read by Combat._default_field_style at board build; applies from the next fight.
var field_style: int = 0
var resolution: Vector2i = DEFAULT_RES
# Persistent tutorial flags — once dismissed, never shown again.
# DEAD, KEPT FOR SAVE COMPATIBILITY: floop_tutorial_seen and
# sacrifice_tutorial_seen have no _maybe_show_* caller anywhere in the project.
# Floop was folded into on-play battlecries and there is no free sacrifice
# action, so neither tip can ever fire. They stay in the save/load dicts so an
# existing settings file round-trips unchanged — do NOT recycle either name for
# a new tip, or a returning player's stale `true` would suppress it unseen.
var floop_tutorial_seen: bool = false
var sacrifice_tutorial_seen: bool = false
var banking_tutorial_seen: bool = false
var intents_tutorial_seen: bool = false
var pile_tutorial_seen: bool = false
# Taught once on round 1 of the first fight: the MUSTER round. Since TAKE THE
# FIELD (2026-07-27) the hold's line does not appear until the END of round 1,
# and the muster delay means nothing swings on the round it arrives — so the
# player's first turn ends with no clash and no explanation. This is that
# explanation. Distinct from combat_model_tutorial_seen, which teaches how the
# clash resolves once there IS one.
var muster_tutorial_seen: bool = false
# Taught once on the first End Turn: the simultaneous-combat model — the single
# most counter-intuitive rule (both sides strike at once; front rank fights and
# is struck first; the back rank waits in reserve).
var combat_model_tutorial_seen: bool = false
# Taught once on the first turn that holds cards over: right-click dismissal.
var dismiss_tutorial_seen: bool = false
# Completed only after the interactive play / commit / read-the-board lesson.
# Kept separate so resetting tutorials can replay the whole guided first fight.
var first_battle_tutorial_complete: bool = false

## HOW MUCH COACHING THE PLAYER WANTS — TutorialDB.COACH_FULL / _TIPS / _OFF.
##
## THIS IS THE SKIP, and it exists because the old one was not a skip. A player
## who already knows the genre could dismiss the walkthrough once it had already
## interrupted them, and the three tips that had not fired yet still arrived on
## later rounds; the only pre-emptive control was a RESET button that does the
## opposite thing. Set OFF from Settings — or from the walkthrough's own first
## panel — and nothing teaches anything ever again.
var coaching_mode: int = TutorialDB.COACH_FULL

## Per-lesson seen state, keyed by TutorialDB id.
##
## The nine pre-registry lessons keep their own named properties above and are
## reached through TutorialDB's `legacy` key — an existing profile already has
## those `true`, and a lesson that forgot its mapping would re-teach a rule the
## player was taught weeks ago. Everything added since lives in here, so a new
## lesson costs a dictionary key rather than five edits in four places.
var lessons_seen: Dictionary = {}


func set_coaching_mode(v: int) -> void:
	var mode: int = clampi(v, TutorialDB.COACH_FULL, TutorialDB.COACH_OFF)
	if coaching_mode == mode:
		return
	coaching_mode = mode
	save()


## True when this profile has already been taught `id`.
##
## An UNKNOWN id answers TRUE, not false. A caller asking about a lesson that no
## longer exists has nothing to teach, and the failure mode of the other default
## is a rule that fires forever because nothing can mark it seen.
func lesson_seen(id: String) -> bool:
	if not TutorialDB.has(id):
		return true
	var legacy := TutorialDB.legacy_flag(id)
	if legacy != "":
		return bool(get(legacy))
	return bool(lessons_seen.get(id, false))


func mark_lesson_seen(id: String) -> void:
	if not TutorialDB.has(id) or lesson_seen(id):
		return
	var legacy := TutorialDB.legacy_flag(id)
	if legacy != "":
		set(legacy, true)
	else:
		lessons_seen[id] = true
	save()


## Un-spend ONE lesson so it fires again next time the game reaches it. This is
## the retrieval half of the contract: a rule you were told once, at speed,
## during your first fight, has to be gettable back without wiping the profile.
func replay_lesson(id: String) -> void:
	if not TutorialDB.has(id):
		return
	var legacy := TutorialDB.legacy_flag(id)
	if legacy != "":
		set(legacy, false)
	lessons_seen.erase(id)
	save()


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


func mark_dismiss_tutorial_seen() -> void:
	if dismiss_tutorial_seen:
		return
	dismiss_tutorial_seen = true
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


func mark_muster_tutorial_seen() -> void:
	if muster_tutorial_seen:
		return
	muster_tutorial_seen = true
	save()


func mark_combat_model_tutorial_seen() -> void:
	if combat_model_tutorial_seen:
		return
	combat_model_tutorial_seen = true
	save()



func mark_first_battle_tutorial_complete() -> void:
	if first_battle_tutorial_complete:
		return
	first_battle_tutorial_complete = true
	save()


## Un-spend EVERYTHING, including the guided first fight.
##
## It does not touch `coaching_mode`: a player who turned coaching off and then
## pressed this asked for the lessons back, not for the walkthrough to ambush
## them — the mode is a separate control right beside it, and silently flipping
## one from the other is how a settings screen loses a player's trust.
func reset_tutorials() -> void:
	floop_tutorial_seen = false
	sacrifice_tutorial_seen = false
	banking_tutorial_seen = false
	intents_tutorial_seen = false
	pile_tutorial_seen = false
	muster_tutorial_seen = false
	combat_model_tutorial_seen = false
	dismiss_tutorial_seen = false
	first_battle_tutorial_complete = false
	lessons_seen.clear()
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


func _unhandled_key_input(event: InputEvent) -> void:
	# A lightweight global fullscreen shortcut. Using unhandled input keeps the
	# key out of text fields and any screen/modal that deliberately owns it.
	if event is InputEventKey \
			and event.pressed \
			and not event.echo \
			and event.keycode == KEY_F \
			and not event.alt_pressed \
			and not event.ctrl_pressed \
			and not event.meta_pressed \
			and not event.shift_pressed:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


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
	if screen_size.x <= 0 or screen_size.y <= 0:
		return
	var screen_floor := Vector2i(
		mini(MIN_RES.x, screen_size.x),
		mini(MIN_RES.y, screen_size.y))
	var changed := false
	if resolution.x < screen_floor.x or resolution.y < screen_floor.y:
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
		out.append(Vector2i(
			mini(DEFAULT_RES.x, screen_size.x),
			mini(DEFAULT_RES.y, screen_size.y)))
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
	_install_master_limiter()


## THE MASTER HAD NO CEILING (2026-09-14).
##
## The buses are built here at runtime and carried NO effects at all, while the
## mix routinely asks for more than full scale from two directions:
##
##   1. Six library tracks are mastered ABOVE 0 dBTP and clip on decode by
##      themselves — event_b +0.84, combat_act2_c +0.80, shop_c +0.59,
##      combat_act2_d +0.23, combat_act3_c +0.15, shop +0.14 dBTP (measured with
##      ffmpeg loudnorm over all 49 tracks, 2026-09-14).
##   2. Music plus up to SFX_POOL_SIZE (12) concurrent SFX voices sum with
##      nothing watching the total, and a clash fires 8-13 cues a round.
##
## Without a ceiling that overflow hard-clips at the driver, which is audible as
## a crackle or a brief tearing on exactly the loudest, busiest moments — the
## ones that are supposed to feel best.
##
## AudioEffectHardLimiter (Godot 4.3+) is the right tool rather than a
## compressor: it is transparent until the signal actually reaches the ceiling,
## so it changes nothing about the mix on any ordinary frame. This is a safety
## net, NOT a loudness stage — pre_gain_db stays 0 and the fix for a track that
## rides it constantly is to re-master that track, not to lean on this.
func _install_master_limiter() -> void:
	var master := 0
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return  # already installed (this can be re-entered on a settings reload)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5  # leaves room for inter-sample peaks the meter misses
	lim.pre_gain_db = 0.0
	lim.release = 0.15
	AudioServer.add_bus_effect(master, lim)


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
	var effective: int = maxi(0, fps_cap)
	# Do not run Godot's sleep-based limiter on top of V-Sync when V-Sync is
	# already the tighter/equal cap; two pacers at 60 Hz produce uneven waits.
	if vsync and effective > 0:
		var screen: int = DisplayServer.window_get_current_screen()
		var refresh: float = DisplayServer.screen_get_refresh_rate(screen)
		if refresh > 1.0 and effective >= int(round(refresh)):
			effective = 0
	Engine.max_fps = effective


func _apply_ui_scale() -> void:
	# content_scale_factor scales all canvas_items uniformly. We deferred so it
	# runs after the initial scene tree builds — applying too early during
	# _ready can race the autoload setup.
	if get_window() != null:
		get_window().content_scale_factor = clampf(ui_scale, 0.6, 1.8)
	# When supersampling is active its SubViewport must re-derive from the new
	# content_scale_factor — otherwise UI Scale is ignored under SSAA and clicks
	# land offset. Harmless no-op when SSAA is off.
	var ss = get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("refresh"):
		ss.refresh()


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
	var min_width := mini(MIN_RES.x, usable.size.x)
	var min_height := mini(MIN_RES.y, usable.size.y)
	var clamped := Vector2i(
		clampi(resolution.x, min_width, usable.size.x),
		clampi(resolution.y, min_height, usable.size.y))
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
	for emitter in get_tree().get_nodes_in_group("ambient_particles"):
		if emitter is CPUParticles2D or emitter is GPUParticles2D:
			emitter.emitting = particles
			emitter.visible = particles


func set_vsync(val: bool) -> void:
	vsync = val
	_apply_vsync()
	_apply_fps_cap()
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


func set_adaptive_render_scale(val: bool) -> void:
	adaptive_render_scale = val
	_apply_render_scale()
	save()


func _apply_render_scale() -> void:
	# Supersample is an autoload; guard in case of early call ordering.
	var ss = get_node_or_null("/root/Supersample")
	if ss != null:
		ss.configure_scale(render_scale, adaptive_render_scale)


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


## Concrete quality tier for secondary render/cache budgets. Named presets and
## Auto map directly; Custom is inferred from the two controls it can tune so
## hand-card and map snapshots track the player's actual graphics cost.
func effective_graphics_tier() -> String:
	var tier := resolve_preset(graphics_preset)
	if tier in GRAPHICS_PRESETS:
		return tier
	if render_scale >= 1.75:
		return "ultra"
	if render_scale > 1.0:
		return "high"
	return "medium" if particles else "low"


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
	# Slow end widened 0.5 -> 0.34 on 2026-07-28. The old floor meant the
	# player-facing "slower" slider topped out at exactly 2x, which is not enough
	# for someone learning the clash or reading a busy board — combat is eight
	# duels resolving in sequence, and some players want to watch each one.
	anim_speed = clampf(val, ANIM_SPEED_MIN, ANIM_SPEED_MAX)
	save()


## How long the clash holds on each lane, as a multiplier on Combat's base
## per-lane dwell. 0.0 means "no dwell" — see the CLASH_DWELL_STEPS block above
## for why this is deliberately not the same dial as anim_speed.
func set_clash_dwell_scale(val: float) -> void:
	clash_dwell_scale = clampf(val, CLASH_DWELL_MIN, CLASH_DWELL_MAX)
	save()


## Scaled per-lane clash dwell, in seconds. Same arithmetic Combat would write
## inline, behind a name so the intent reads at the call site.
##
## Deliberately does NOT divide by anim_speed: the caller decides whether the
## two compose (a dwell already routed through Motion.time()/anim_time() must
## not be scaled twice). Callers must treat a 0.0 result as "skip the pause
## entirely" and never await a zero-length timer for it.
func clash_dwell_time(base_seconds: float) -> float:
	return maxf(0.0, base_seconds * clash_dwell_scale)


## Index into ANIM_SPEED_STEPS of the stop nearest the live value. Always a
## valid index, so a settings row built from it can never show a word that
## disagrees with the stored state.
func anim_speed_step_index() -> int:
	return maxi(0, _nearest_step_index(ANIM_SPEED_STEPS, anim_speed))


## Index into CLASH_DWELL_STEPS of the stop nearest the live value.
func clash_dwell_step_index() -> int:
	return maxi(0, _nearest_step_index(CLASH_DWELL_STEPS, clash_dwell_scale))


## Nearest offered stop by absolute distance. Ties go to the EARLIER (slower,
## longer-dwell) entry — if we have to guess, guess toward legibility.
## Returns -1 only for an empty table.
func _nearest_step_index(steps: Array, val: float) -> int:
	var best := -1
	var best_d := INF
	for i in steps.size():
		var d: float = absf(float(steps[i]) - val)
		if d < best_d:
			best_d = d
			best = i
	return best


## Read a persisted float, then clamp and snap it onto the offered stops.
##
## This exists because the SETTER is the only guarded door and a save file walks
## straight past it: a value written by an older build, a hand edit, or a
## corrupt/half-written file arrives raw. An out-of-range anim_speed is not
## cosmetic — a negative one makes anim_time() return a NEGATIVE duration, which
## breaks every tween in the game at once, and any unrecognised value used to
## leave the settings row displaying a stop the player had not chosen.
## `steps` must be sorted ascending; its ends are the legal range.
func _load_step(parsed: Dictionary, key: String, steps: Array, def: float) -> float:
	if steps.is_empty():
		return def
	var raw: Variant = parsed.get(key, def)
	var val := def
	if raw is float or raw is int:
		val = float(raw)
	var lo := float(steps[0])
	var hi := float(steps[steps.size() - 1])
	var idx := _nearest_step_index(steps, clampf(val, lo, hi))
	return float(steps[idx]) if idx >= 0 else def


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


func set_field_style(val: int) -> void:
	field_style = clampi(val, 0, 3)
	save()


func set_display_mode(val: String) -> void:
	display_mode = val
	fullscreen = (val == "fullscreen")  # backward compat
	_apply_display_mode()
	save()


func toggle_fullscreen() -> void:
	set_display_mode("windowed" if display_mode == "fullscreen" else "fullscreen")


# Returns a scaled animation duration. Callers use:
#   var t := UserSettings.anim_time(0.5)
#   create_tween().tween_property(...).set_duration(t)
# Or short-pause callers (Combat._short_pause) multiply by anim_speed.
# Unchanged contract: divides by anim_speed only. The clash dwell is NOT routed
# through here — it is a reading pause, not an animation, and rides
# clash_dwell_scale instead. The near-zero guard below stays as the last line of
# defence, but both write paths (set_anim_speed, load_settings) now clamp into
# [ANIM_SPEED_MIN, ANIM_SPEED_MAX], so it can no longer be reached from a save.
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
		"adaptive_render_scale": adaptive_render_scale,
		"graphics_preset": graphics_preset,
		"brightness": brightness,
		"anim_speed": anim_speed,
		"clash_dwell_scale": clash_dwell_scale,
		"tooltip_delay": tooltip_delay,
		"colorblind_mode": colorblind_mode,
		"reduce_motion": reduce_motion,
		"end_turn_warning": end_turn_warning,
		"combat_telegraph": combat_telegraph,
		"mute_on_focus_loss": mute_on_focus_loss,
		"field_style": field_style,
		"resolution_x": resolution.x,
		"resolution_y": resolution.y,
		"floop_tutorial_seen": floop_tutorial_seen,
		"sacrifice_tutorial_seen": sacrifice_tutorial_seen,
		"banking_tutorial_seen": banking_tutorial_seen,
		"intents_tutorial_seen": intents_tutorial_seen,
		"pile_tutorial_seen": pile_tutorial_seen,
		"muster_tutorial_seen": muster_tutorial_seen,
		"combat_model_tutorial_seen": combat_model_tutorial_seen,
		"dismiss_tutorial_seen": dismiss_tutorial_seen,
		"first_battle_tutorial_complete": first_battle_tutorial_complete,
		"coaching_mode": coaching_mode,
		"lessons_seen": lessons_seen,
	}
	SaveIO.write_text(SAVE_PATH, JSON.stringify(data))


func load_settings() -> void:
	var raw := SaveIO.read_text(SAVE_PATH)
	if raw == "":
		return
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		parsed = JSON.parse_string(SaveIO.read_backup_text(SAVE_PATH))
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
		adaptive_render_scale = bool(parsed.get("adaptive_render_scale", true))
		# Saves that predate presets had hand-set graphics values, so default them
		# to "custom" — never silently override a returning player's choices. Only
		# a fresh install (no file at all → this block is skipped) keeps "auto".
		graphics_preset = str(parsed.get("graphics_preset", "custom"))
		brightness = float(parsed.get("brightness", 0.0))
		# Both speed dials go through _load_step: clamped into range and snapped
		# onto an offered stop, so a stale/corrupt value can neither poison
		# anim_time() nor leave a settings row naming a state that isn't the one
		# in force. Saves predating clash_dwell_scale get the 1.0 default.
		anim_speed = _load_step(parsed, "anim_speed", ANIM_SPEED_STEPS, 1.0)
		clash_dwell_scale = _load_step(
			parsed, "clash_dwell_scale", CLASH_DWELL_STEPS, 1.0)
		tooltip_delay = float(parsed.get("tooltip_delay", 0.0))
		colorblind_mode = parsed.get("colorblind_mode", "off")
		reduce_motion = parsed.get("reduce_motion", false)
		end_turn_warning = parsed.get("end_turn_warning", true)
		combat_telegraph = parsed.get("combat_telegraph", true)
		mute_on_focus_loss = parsed.get("mute_on_focus_loss", true)
		field_style = clampi(int(parsed.get("field_style", 0)), 0, 3)
		var rx: int = int(parsed.get("resolution_x", 1600))
		var ry: int = int(parsed.get("resolution_y", 900))
		resolution = Vector2i(rx, ry)
		floop_tutorial_seen = parsed.get("floop_tutorial_seen", false)
		sacrifice_tutorial_seen = parsed.get("sacrifice_tutorial_seen", false)
		banking_tutorial_seen = parsed.get("banking_tutorial_seen", false)
		intents_tutorial_seen = parsed.get("intents_tutorial_seen", false)
		pile_tutorial_seen = parsed.get("pile_tutorial_seen", false)
		muster_tutorial_seen = parsed.get("muster_tutorial_seen", false)
		combat_model_tutorial_seen = parsed.get("combat_model_tutorial_seen", false)
		dismiss_tutorial_seen = parsed.get("dismiss_tutorial_seen", false)
		first_battle_tutorial_complete = bool(parsed.get(
			"first_battle_tutorial_complete", false))
		coaching_mode = clampi(int(parsed.get("coaching_mode", TutorialDB.COACH_FULL)),
			TutorialDB.COACH_FULL, TutorialDB.COACH_OFF)
		# TYPE-CHECKED, NOT ASSUMED. `user://settings.save` is a plain JSON file on
		# a disk the player owns, and C21's chaos pass is the standing reminder
		# that a save can come back the wrong SHAPE — a String here would abort
		# every `lessons_seen.get()` call site rather than fail one lookup.
		var seen = parsed.get("lessons_seen", {})
		lessons_seen = seen if seen is Dictionary else {}
