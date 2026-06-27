extends Node
# Diagnostic: report what Godot sees about the display + DPI so we can tell
# whether a 125%-scaled Windows desktop is making the game render sub-native.
# Run WINDOWED (NOT --headless):
#   Godot.exe --path "D:\Godot" res://tools/_probe_dpi.tscn

func _ready() -> void:
	await get_tree().process_frame
	var scr := DisplayServer.window_get_current_screen()
	print("=== DPI PROBE ===")
	print("screen_get_size       = ", DisplayServer.screen_get_size(scr))
	print("screen_get_scale      = ", DisplayServer.screen_get_scale(scr))
	print("screen_get_dpi        = ", DisplayServer.screen_get_dpi(scr))
	print("window_get_size       = ", DisplayServer.window_get_size())
	print("window_get_size_with_decorations = ", DisplayServer.window_get_size_with_decorations())
	print("viewport visible rect = ", get_viewport().get_visible_rect().size)
	print("content_scale_factor  = ", get_window().content_scale_factor)
	print("content_scale_size    = ", get_window().content_scale_size)
	print("=== END ===")
	get_tree().quit()
