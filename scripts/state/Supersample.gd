extends Node
## Supersample.gd — autoload. Optional 2D SSAA for the whole game.
##
## When render_scale > 1, the active scene is reparented into a SubViewport that
## RENDERS at render_scale× the window resolution, then is blitted down to the
## window with a linear filter. Downsampling a 2×-resolution frame is true
## supersampling: every procedural draw_*, font glyph, gem, seal and sprite gets
## averaged from 4 samples → smooth, crisp edges that Godot's native 2D AA can't
## reach (there is no built-in 2D render-scale in the engine).
##
## render_scale == 1.0 is a FULL BYPASS: no SubViewport, no reparenting, the game
## renders exactly as it does today. So the default path is untouched and the
## feature is risk-free to ship; SSAA only engages when the player opts in.
##
## Resolution-agnostic: the SubViewport's logical size is pinned to the project
## BASE canvas (display/window/size/viewport_*) via size_2d_override — the same
## size the root lays out at under `canvas_items` stretch — so a scene lays out
## identically whether SSAA is on or off, at ANY window size/DPI. Its render size
## is base × scale. Re-derives on every window resize.

const MAX_SCALE := 2.0
const ADAPTIVE_WARMUP := 4.0
const ADAPTIVE_WINDOW := 1.0
const ADAPTIVE_RESIZE_COOLDOWN := 3.0
const ADAPTIVE_MAX_FRAME := 0.100
const ADAPTIVE_SLOW_WINDOWS := 2

signal effective_scale_changed(effective: float, requested: float)

# Effective runtime scale. requested_scale is the player's saved quality ceiling.
var render_scale: float = 1.0
var requested_scale: float = 1.0
var adaptive_enabled := true

var _holder: CanvasLayer = null
var _display: TextureRect = null
var _svp: SubViewport = null
var _scene_in_vp: Node = null
var _adaptive_owner: WeakRef = null
var _adaptive_warmup_left := 0.0
var _adaptive_window_time := 0.0
var _adaptive_frame_sum := 0.0
var _adaptive_frame_count := 0
var _adaptive_slow_count := 0
var _adaptive_slow_windows := 0
var _adaptive_change_cooldown := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Settings load slightly after autoload _ready; apply once the tree settles.
	call_deferred("_boot")


func _boot() -> void:
	if render_scale > 1.001:
		_build_rig()


## Public API — called by UserSettings.set_render_scale().
func apply_scale(s: float) -> void:
	# Fixed-scale compatibility path used by the existing SSAA probes.
	requested_scale = clampf(s, 1.0, MAX_SCALE)
	adaptive_enabled = false
	_adaptive_owner = null
	_set_effective_scale(requested_scale)


func configure_scale(requested: float, adaptive: bool) -> void:
	requested_scale = clampf(requested, 1.0, MAX_SCALE)
	adaptive_enabled = adaptive
	_set_effective_scale(requested_scale)
	_reset_adaptive_sampling(2.0)


func _set_effective_scale(s: float) -> void:
	s = clampf(s, 1.0, requested_scale)
	if is_equal_approx(render_scale, s) and (s <= 1.001) == (not is_active()):
		return
	render_scale = s
	if render_scale <= 1.001:
		_teardown()
	else:
		_build_rig()
		_resize()
	effective_scale_changed.emit(render_scale, requested_scale)


func begin_adaptive_scope(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	_adaptive_owner = weakref(owner)
	_set_effective_scale(requested_scale)
	_reset_adaptive_sampling(ADAPTIVE_WARMUP)


func end_adaptive_scope(owner: Node) -> void:
	if _adaptive_owner == null:
		return
	var current = _adaptive_owner.get_ref()
	if current != owner:
		return
	_adaptive_owner = null
	_set_effective_scale(requested_scale)
	_reset_adaptive_sampling(0.0)


func get_effective_scale() -> float:
	return render_scale


func get_requested_scale() -> float:
	return requested_scale


func is_adaptively_reduced() -> bool:
	return render_scale + 0.01 < requested_scale


func get_active_scene() -> Node:
	if _scene_in_vp != null and is_instance_valid(_scene_in_vp):
		return _scene_in_vp
	return get_tree().current_scene


func is_active() -> bool:
	return _svp != null and is_instance_valid(_svp)


## Re-derive the rig from current settings (UI Scale changed, etc.). No-op when
## SSAA is off. UserSettings calls this after content_scale_factor changes so the
## SubViewport's logical size tracks UI Scale.
func refresh() -> void:
	if is_active():
		_resize()
		_reset_adaptive_sampling(2.0)


func _build_rig() -> void:
	if is_active():
		return
	var root := get_tree().root

	# Display layer sits BELOW autoload overlays (settings/brightness live on the
	# window at layer 0+) so those stay crisp on top; the game itself is the
	# texture underneath.
	_holder = CanvasLayer.new()
	_holder.name = "SupersampleLayer"
	_holder.layer = -128
	root.add_child(_holder)

	_display = TextureRect.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_SCALE
	# Linear so the 2× frame averages down smoothly (the whole point).
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_display)

	_svp = SubViewport.new()
	_svp.name = "SupersampleVP"
	_svp.size_2d_override_stretch = true
	_svp.transparent_bg = false
	_svp.handle_input_locally = true
	_svp.gui_disable_input = false
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Match the project's 2D MSAA inside the SS viewport too, so edges are both
	# multisampled AND supersampled.
	_svp.msaa_2d = root.msaa_2d
	_holder.add_child(_svp)
	_display.texture = _svp.get_texture()

	_resize()
	if not root.size_changed.is_connected(_on_root_size_changed):
		root.size_changed.connect(_on_root_size_changed)
	_pull_scene_in()


func _teardown() -> void:
	# Hand the scene back to the window root, then drop the rig.
	var restored_scene := _scene_in_vp
	if restored_scene != null and is_instance_valid(restored_scene) \
			and restored_scene.get_parent() == _svp:
		restored_scene.reparent(get_tree().root)
		# Reparenting the current scene into a SubViewport clears SceneTree's
		# pointer. Restore it when SSAA is disabled live so the next scene change
		# can free this outgoing screen normally.
		if get_tree().current_scene == null:
			get_tree().current_scene = restored_scene
	_scene_in_vp = null
	var root := get_tree().root
	if root.size_changed.is_connected(_on_root_size_changed):
		root.size_changed.disconnect(_on_root_size_changed)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_svp = null
	_display = null


func _base_size() -> Vector2i:
	# The project's logical design canvas. Under `canvas_items` stretch the root
	# lays out at this size and the engine scales it to fill the window, so the
	# SubViewport must use the SAME logical size to match the non-SSAA path 1:1
	# (and to keep _unhandled_input coords — already delivered in this space —
	# valid when pushed in_local_coords).
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))


func _on_root_size_changed() -> void:
	_resize()
	_reset_adaptive_sampling(2.0)


func _resize() -> void:
	if not is_active():
		return
	var base: Vector2i = _base_size()
	if base.x <= 0 or base.y <= 0:
		return
	# Honor UI Scale. content_scale_factor enlarges drawn content (factor 0.8 →
	# 1/0.8 = 1.25× as many logical units), and under canvas_items the engine both
	# lays the non-SSAA scene out AND delivers input in that base/factor space. The
	# SubViewport must use the SAME logical size, or UI Scale is silently ignored
	# in SSAA mode AND pushed-in clicks land offset. At factor 1.0 this is exactly
	# `base`, so the verified default path is unchanged.
	var factor := 1.0
	var win := get_window()
	if win != null and win.content_scale_factor > 0.001:
		factor = win.content_scale_factor
	var logical := Vector2i(int(round(base.x / factor)), int(round(base.y / factor)))
	# Logical size matches the canvas_items non-SSAA path (incl. UI Scale).
	_svp.size_2d_override = logical
	# Render size = logical × scale (the supersampling).
	_svp.size = Vector2i(int(round(logical.x * render_scale)), int(round(logical.y * render_scale)))
	# _display is a PRESET_FULL_RECT child of a CanvasLayer, so its anchors already
	# stretch it across the base logical rect (which canvas_items scales to fill the
	# window). No explicit size needed — setting it fights the anchors and warns.


func _process(delta: float) -> void:
	# change_scene_to_file() drops the new scene under the window root; pull it
	# into the SubViewport so it renders supersampled. Cheap identity check.
	if not is_active():
		return
	var cur := get_tree().current_scene
	if cur != null and is_instance_valid(cur) and cur != _scene_in_vp and cur.get_parent() == get_tree().root:
		# Reparenting our previous scene INTO _svp moved it off the window root,
		# which nulls get_tree().current_scene. So change_scene_to_file's own
		# "free the outgoing scene" step ran against a null current_scene and did
		# nothing — the screen we just left is still alive (and visible) inside
		# _svp. Godot can't free it for us anymore, so free the straggler(s) here
		# before adopting the new scene; otherwise every screen stacks up. (cur is
		# still under root at this point, so it's never among _svp's children yet.)
		for stale in _svp.get_children():
			if is_instance_valid(stale):
				stale.queue_free()
		_scene_in_vp = cur
		cur.reparent.call_deferred(_svp)
	_adaptive_process(delta)


func _reset_adaptive_sampling(warmup: float) -> void:
	_adaptive_warmup_left = maxf(0.0, warmup)
	_adaptive_change_cooldown = 0.0
	_adaptive_window_time = 0.0
	_adaptive_frame_sum = 0.0
	_adaptive_frame_count = 0
	_adaptive_slow_count = 0
	_adaptive_slow_windows = 0


func _adaptive_process(delta: float) -> void:
	if not adaptive_enabled or requested_scale <= 1.251 \
			or DisplayServer.get_name() == "headless":
		return
	if _adaptive_owner == null:
		return
	var owner = _adaptive_owner.get_ref()
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		_adaptive_owner = null
		_set_effective_scale(requested_scale)
		return
	var win := get_window()
	if get_tree().paused or (win != null and not win.has_focus()):
		_reset_adaptive_sampling(1.0)
		return
	if _adaptive_change_cooldown > 0.0:
		_adaptive_change_cooldown = maxf(0.0, _adaptive_change_cooldown - delta)
	if _adaptive_warmup_left > 0.0:
		_adaptive_warmup_left = maxf(0.0, _adaptive_warmup_left - delta)
		return
	if delta <= 0.0 or delta > ADAPTIVE_MAX_FRAME:
		return
	var target_fps := _adaptive_target_fps()
	if target_fps < 50.0:
		return
	var budget := 1.0 / target_fps
	_adaptive_window_time += delta
	_adaptive_frame_sum += delta
	_adaptive_frame_count += 1
	if delta > budget * 1.08:
		_adaptive_slow_count += 1
	if _adaptive_window_time < ADAPTIVE_WINDOW:
		return
	var avg := _adaptive_frame_sum / float(maxi(_adaptive_frame_count, 1))
	var slow_ratio := float(_adaptive_slow_count) \
		/ float(maxi(_adaptive_frame_count, 1))
	var slow := avg > budget * 1.07 and slow_ratio >= 0.35
	_adaptive_slow_windows = _adaptive_slow_windows + 1 if slow else 0
	_adaptive_window_time = 0.0
	_adaptive_frame_sum = 0.0
	_adaptive_frame_count = 0
	_adaptive_slow_count = 0
	if _adaptive_slow_windows < ADAPTIVE_SLOW_WINDOWS \
			or _adaptive_change_cooldown > 0.0:
		return
	var lower := _next_adaptive_scale()
	if lower + 0.01 < render_scale:
		_set_effective_scale(lower)
		_adaptive_change_cooldown = ADAPTIVE_RESIZE_COOLDOWN
	_adaptive_slow_windows = 0


func _adaptive_target_fps() -> float:
	var target := 60.0
	if UserSettings.fps_cap > 0:
		target = minf(target, float(UserSettings.fps_cap))
	elif UserSettings.vsync:
		var screen := DisplayServer.window_get_current_screen()
		var refresh := DisplayServer.screen_get_refresh_rate(screen)
		if refresh > 1.0:
			target = minf(target, refresh)
	return target


func _next_adaptive_scale() -> float:
	if render_scale > 1.75:
		return 1.5
	if render_scale > 1.26:
		return 1.25
	return render_scale


func _pull_scene_in() -> void:
	var cur := get_tree().current_scene
	if cur != null and is_instance_valid(cur) and cur.get_parent() == get_tree().root:
		_scene_in_vp = cur
		cur.reparent(_svp)


func _unhandled_input(event: InputEvent) -> void:
	# Window-level GUI (settings/brightness overlays) gets first crack; whatever
	# they don't consume is forwarded into the SubViewport so the game — buttons,
	# card drags, spell-target _input, hover — receives it.
	#
	# Push in LOCAL coords. With `canvas_items` stretch the engine already delivers
	# input in the logical (base) coordinate system, and size_2d_override pins the
	# SubViewport's 2D space to that SAME base — so the event is already in the
	# viewport's local space. in_local_coords=true tells push_input NOT to apply
	# its own stretch transform; applying it (the default, and the cause of the
	# earlier bugs) mis-scales the position so clicks miss every control. This also
	# leaves InputEvent.global_position as true screen coords, which the card-drag
	# system depends on. Verified against a headless hit-test rig.
	if not is_active():
		return
	_svp.push_input(event, true)
