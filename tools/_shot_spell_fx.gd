extends Node
## _shot_spell_fx.gd — the spell SEQUENCE, photographed (S2/S3 of
## docs/SPELL_FX_PLAN_20260717.md).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_spell_fx.tscn
##
## `_probe_spell_sequence` proves the DERIVATION (counts, ordering, geometry).
## It cannot prove the sweep LOOKS like anything — and in this layer the shot is
## the only thing that has ever caught a defect (every failure in the cool pitch
## was invisible to parse checks and code review). So:
##
##   sweep_mid   a `scope: ALL ENEMIES` cast caught MID-SWEEP — the frame that
##               used to be one puff at a dead point, and must now show impacts
##               landing ON bodies, left-to-right, some already fading
##   sweep_late  the same cast near the end of its sweep
##   radiate     a `scope: ALL CREATURES` cast — must radiate from the midline
##               (both sides lit), not sweep
##   single      a single-target bolt — must land on the target, no scheduling
##
## Outputs _shot_spell_*.png at the project root.

var _combat: Node = null


func _ready() -> void:
	# Watchdog — a windowed harness whose _ready throws never reaches quit() and
	# the process lives forever (cost three orphans on 07-16).
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[spellfx] WATCHDOG fired — _ready never completed")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# This machine's saved settings have Reduce Motion ON — force it off or the
	# harness photographs the static fallback (known trap).
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0
		UserSettings.particles = true

	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	await get_tree().create_timer(6.0).timeout   # fight intro + round-1 banner

	var enemies: Array = _combat.call("_all_enemy_creatures")
	print("[spellfx] enemy bodies on board: %d" % enemies.size())
	if enemies.size() < 2:
		print("[spellfx] FAIL — need >=2 bodies to photograph a sweep")
		get_tree().quit(1)
		return

	var pts: Array = _combat.call("_spell_fx_impact_points",
		{"scope": "ALL ENEMIES"}, null)
	print("[spellfx] ALL ENEMIES derives %d impact points (bodies: %d)"
		% [pts.size(), enemies.size()])
	if pts.size() != enemies.size():
		print("[spellfx] FAIL — impact count != body count")

	# ── 1. ALL ENEMIES, caught mid-sweep ────────────────────────────────
	# Inferno: fire family, scope ALL ENEMIES. The stagger is ~0.06/body, so
	# grab it a beat in — the whole point is the frame where some have landed
	# and some haven't.
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("inferno"), null)
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_spell_sweep_mid.png", "sweep_mid (Inferno, ALL ENEMIES)")
	await get_tree().create_timer(0.16).timeout
	await _shoot("res://_shot_spell_sweep_late.png", "sweep_late (same cast, later)")
	await get_tree().create_timer(1.2).timeout

	# ── 2. ALL CREATURES — must RADIATE, not sweep ──────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("apocalypse"), null)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_spell_radiate.png", "radiate (Apocalypse, ALL CREATURES)")
	await get_tree().create_timer(1.2).timeout

	# ── 3. Single target — lands on the body, no scheduling ─────────────
	var t = enemies[0]
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("frost_bolt"), t)
	await get_tree().create_timer(0.06).timeout
	await _shoot("res://_shot_spell_single.png", "single (Frost Bolt on a body)")
	await get_tree().create_timer(1.2).timeout

	# ══ S6 signatures ════════════════════════════════════════════════════
	# ── 4. The Petard — mortar arc, then the blast ──────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("petard"), t)
	await get_tree().create_timer(0.17).timeout
	await _shoot("res://_shot_sig_lob_air.png", "petard lob — shell mid-air")
	await get_tree().create_timer(0.19).timeout
	await _shoot("res://_shot_sig_lob_blast.png", "petard lob — the blast")
	await get_tree().create_timer(1.2).timeout

	# ── 5. Strike — steel, not weather ──────────────────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("strike"), t)
	await get_tree().create_timer(0.18).timeout
	await _shoot("res://_shot_sig_strike.png", "strike — crossed blade streaks")
	await get_tree().create_timer(1.2).timeout

	# ── 6. Earthquake — the fissure ─────────────────────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("earthquake"), null)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_sig_fissure.png", "earthquake — fissure + radiate")
	await get_tree().create_timer(1.6).timeout

	# ── 7. Lane bars — Salted Ground / The Gallows Writ ─────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("salted_ground"),
		null, 1)
	await get_tree().create_timer(0.14).timeout
	await _shoot("res://_shot_sig_salt.png", "salted ground — bone bar + salt fall, lane 2")
	await get_tree().create_timer(1.2).timeout
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("gallows_writ"),
		null, 2)
	await get_tree().create_timer(0.12).timeout
	await _shoot("res://_shot_sig_gallows.png", "gallows writ — crimson stroke, lane 3")
	await get_tree().create_timer(1.2).timeout

	# ── 8. King's Command — the banner sweep ────────────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("kings_command"), null)
	await get_tree().create_timer(0.16).timeout
	await _shoot("res://_shot_sig_banner.png", "king's command — gilt standard mid-sweep")
	await get_tree().create_timer(1.2).timeout

	# ── 9. The Doubled Hour — the bell strikes twice ────────────────────
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("time_snare"), null)
	await get_tree().create_timer(0.10).timeout
	await _shoot("res://_shot_sig_hour1.png", "doubled hour — first ring")
	await get_tree().create_timer(0.24).timeout
	await _shoot("res://_shot_sig_hour2.png", "doubled hour — second ring")
	await get_tree().create_timer(1.2).timeout

	# ── 10. Soul Swap — glints cross between the stat seals ─────────────
	var t2 = enemies[mini(1, enemies.size() - 1)]
	_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("soul_swap"), t2)
	await get_tree().create_timer(0.08).timeout
	await _shoot("res://_shot_sig_soulswap.png", "soul swap — crossing stat glints")
	await get_tree().create_timer(1.0).timeout

	# ── 11. Crossfire — both wings converge (needs back-row bodies) ─────
	var backs: Array = []
	for c in _combat.get("_enemy_back"):
		if c != null:
			backs.append(c)
	if backs.size() > 0:
		_combat.call("_play_spell_cast_vfx", CardDB.get_card_data("ricochet"), null)
		await get_tree().create_timer(0.08).timeout
		await _shoot("res://_shot_sig_crossfire.png", "crossfire — converging wings")
	else:
		print("[spellfx] crossfire skipped — no back-row bodies this encounter")

	# ── 12. Turncoat — the deserter WALKS across the table ──────────────
	var live: Array = _combat.call("_all_enemy_creatures")
	if live.size() >= 2:
		_combat.call("_resolve_spell", CardDB.get_card_data("inspire"),
			live[0], -1)
		await get_tree().create_timer(0.22).timeout
		await _shoot("res://_shot_sig_desert.png", "turncoat — deserter mid-walk")
		await get_tree().create_timer(1.0).timeout
		# ── 13. Banish — torn from the fight (spiral + contracting ring) ─
		var live2: Array = _combat.call("_all_enemy_creatures")
		if live2.size() > 0:
			_combat.call("_resolve_spell", CardDB.get_card_data("banish"),
				live2[0], -1)
			await get_tree().create_timer(0.14).timeout
			await _shoot("res://_shot_sig_banish.png", "banish — mid-spiral exit")
	else:
		print("[spellfx] desert/banish skipped — not enough bodies")

	print("[spellfx] DONE")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0)


func _shoot(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[spellfx] wrote %s — %s" % [path.get_file(), label])
