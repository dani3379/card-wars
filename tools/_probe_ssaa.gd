extends SceneTree
## Drives the REAL Supersample autoload through a menu->map scene change with
## SSAA forced to 2x — the user's actual config (render_scale=2.0). Exercises the
## reparent/free logic in Supersample._process that headless --script never hits.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_ssaa.gd

var _step := 0
var _ss: Node
var _frames := 0


func _process(_d: float) -> bool:
	_frames += 1
	match _step:
		0:
			_ss = root.get_node_or_null("Supersample")
			if _ss == null:
				print("[ssaa] FATAL: no Supersample autoload"); quit(1); return true
			var scale := 2.0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--scale="):
					scale = float(a.trim_prefix("--scale="))
			print("[ssaa] forcing render_scale=%.1f and building rig ..." % scale)
			_ss.apply_scale(scale)
			print("[ssaa]   is_active=%s svp.size=%s 2d_override=%s" % [
				str(_ss.is_active()),
				str(_ss._svp.size) if _ss.is_active() else "-",
				str(_ss._svp.size_2d_override) if _ss.is_active() else "-"])
			print("[ssaa] loading main_menu as current_scene ...")
			var mm = load("res://scenes/main_menu.tscn").instantiate()
			root.add_child(mm)
			current_scene = mm
			_step = 1
		1:
			# Let _build_rig/_pull_scene_in + _process pull the menu into the svp.
			if _frames > 4:
				print("[ssaa] menu pulled into svp? svp children=%d current_scene=%s" % [
					_svp_children(), str(current_scene)])
				print("[ssaa] change_scene_to_file -> map.tscn (the new-run transition) ...")
				var err = change_scene_to_file("res://scenes/map.tscn")
				print("[ssaa]   change_scene err=%d" % err)
				_step = 2
				_frames = 0
		2:
			# Pump frames so the deferred scene swap + Supersample reparent/free run.
			if _frames > 10:
				print("[ssaa] after transition: svp children=%d current_scene=%s" % [
					_svp_children(), str(current_scene)])
				print("[ssaa] changing scene AGAIN -> combat.tscn (stress the stale-free loop) ...")
				change_scene_to_file("res://scenes/combat.tscn")
				_step = 3
				_frames = 0
		3:
			if _frames > 12:
				print("[ssaa] after 2nd transition: svp children=%d" % _svp_children())
				print("[ssaa] DONE — no crash in SSAA reparent logic")
				quit(0)
				return true
	return false


func _svp_children() -> int:
	if _ss != null and _ss.is_active():
		return _ss._svp.get_child_count()
	return -1
