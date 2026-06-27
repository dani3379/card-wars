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
## Resolution-agnostic: the SubViewport's logical size is pinned to the live
## window size via size_2d_override (so every scene lays out identically to the
## non-SSAA path at ANY resolution), while its render size is window × scale.
## Re-derives on every window resize.

const MAX_SCALE := 2.0

var render_scale: float = 1.0

var _holder: CanvasLayer = null
var _display: TextureRect = null
var _svp: SubViewport = null
var _scene_in_vp: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Settings load slightly after autoload _ready; apply once the tree settles.
	call_deferred("_boot")


func _boot() -> void:
	if render_scale > 1.001:
		_build_rig()


## Public API — called by UserSettings.set_render_scale().
func apply_scale(s: float) -> void:
	s = clampf(s, 1.0, MAX_SCALE)
	render_scale = s
	if render_scale <= 1.001:
		_teardown()
	else:
		_build_rig()
		_resize()


func is_active() -> bool:
	return _svp != null and is_instance_valid(_svp)


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
	if not root.size_changed.is_connected(_resize):
		root.size_changed.connect(_resize)
	_pull_scene_in()


func _teardown() -> void:
	# Hand the scene back to the window root, then drop the rig.
	if _scene_in_vp != null and is_instance_valid(_scene_in_vp) and _scene_in_vp.get_parent() == _svp:
		_scene_in_vp.reparent(get_tree().root)
	_scene_in_vp = null
	var root := get_tree().root
	if root.size_changed.is_connected(_resize):
		root.size_changed.disconnect(_resize)
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_svp = null
	_display = null


func _resize() -> void:
	if not is_active():
		return
	var win: Vector2i = get_tree().root.size
	if win.x <= 0 or win.y <= 0:
		return
	# Logical size = window (layout matches the non-SSAA path exactly).
	_svp.size_2d_override = win
	# Render size = window × scale (the supersampling).
	_svp.size = Vector2i(int(round(win.x * render_scale)), int(round(win.y * render_scale)))
	if _display != null:
		_display.size = win


func _process(_dt: float) -> void:
	# change_scene_to_file() drops the new scene under the window root; pull it
	# into the SubViewport so it renders supersampled. Cheap identity check.
	if not is_active():
		return
	var cur := get_tree().current_scene
	if cur != null and is_instance_valid(cur) and cur != _scene_in_vp and cur.get_parent() == get_tree().root:
		_scene_in_vp = cur
		cur.reparent.call_deferred(_svp)


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
	# Coords need a remap: the SubViewport RENDERS at window×render_scale, and
	# push_input() applies that stretch (override→render = ×render_scale) to the
	# event. The event arrives in window space, so we must pre-divide by
	# render_scale or the two multiply out — clicks then drift further off the
	# further the cursor is from the top-left (error grows with distance). The
	# transform is identity at scale 1, but the rig is only active above 1 anyway.
	if not is_active():
		return
	var inv := 1.0 / render_scale
	var xform := Transform2D(0.0, Vector2(inv, inv), 0.0, Vector2.ZERO)
	_svp.push_input(event.xformed_by(xform))
