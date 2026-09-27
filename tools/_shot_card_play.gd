extends Node
## _shot_card_play.gd — EYES ON THE PLAY GESTURE (2026-08-03).
##
## WINDOWED, editor closed:
##   Godot.exe --path "D:\Godot" res://tools/_shot_card_play.tscn
##
## Never `--headless`: a GL screenshot taken without a real display comes back
## white or black, and `_play_landing_pop` bails its arc under headless anyway —
## every flight frame would photograph the same settled board.
##
## ── WHAT THIS IS FOR ──────────────────────────────────────────────────────
## `tools/_probe_card_play.gd` proves the gesture is CORRECT: the card leaves the
## hand, the flight's detach/re-attach round trip cannot strand it, the clock
## reaches the arc. None of that can prove the gesture READS. Eighteen numbered
## frames, one per beat, so a human can flip through the whole motion:
##
##   01 hand_rest      the fan at rest
##   02 hover          one card lifted, gilt-bordered, its detail panel open
##   03 grab           the moment of pickup — DRAG_SCALE, straightened
##   04 drag_lean      dragged across the board, leaning into cursor velocity
##   05 flight_early   a SLOPPY drop, 20% into the arc — the card has left
##   06 flight_apex    50% — the top of the lift, over the board
##   07 flight_land    90% — coming down onto the slot
##   08 press          the wax press: the squash at contact + the ground ring
##   09 seated         settled, compact, on the shared idle clock
##   10 seat_short     a TIGHT drop for contrast — a near-flat seat, not a loop
##   11 long_arc       the same funnel at FULL reach, for judging apex/hang time
##   12 refuse_shake   a rejected drop, mid recoil + head-shake
##   13 refuse_home    the refused card back on its fan slot
##   14 seal_bite      the Command seal STRUCK — the wax dipped, impression born
##   15 seal_ring      80 ms on: the hot core + its band radiating off the rim
##   16 seal_refused   the same press REFUSING — the dip with no ring (✦7b)
##   17 edict_posted   the foe's standing rule, still in force
##   18 edict_struck   ...and struck out by the win (RubricStroke, and it HOLDS)
##
## ── THE SETTLE TRAP ───────────────────────────────────────────────────────
## The failure this file is written against: wait ~1.4 s "for things to settle"
## and every flight frame photographs the same seated card. The player's own
## flight is ~0.12 s for a drop right on the slot and ~0.19 s for a sloppy one,
## so the mid-flight waits are SHORT — and they are FRACTIONS of the arc's
## measured duration rather than wall times, so retuning ARC_MIN_TIME /
## ARC_MAX_TIME moves the frames instead of invalidating them.
##
## Frames 05–08 each get their OWN play rather than being shot in sequence off a
## single flight: `get_image()` stalls the GPU for longer than the beat spacing,
## so a second capture from the same flight would land wherever the readback
## finished, not where it was aimed. Every frame prints IN FLIGHT / landed plus
## the card's live z_index / parent / scale at capture, so the reader can confirm
## which beat was caught instead of taking the filename's word for it.
##
## Outputs tools/screenshot/_cardplay_NN_<tag>.png

const FIXTURE_CARD := "hexwright"   # vanilla 2/4 — nothing fires on arrival

var _combat: Node = null
var _shot_n := 0
var _old_speed := 1.0
var _old_rm := false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	if DisplayServer.get_name() == "headless":
		print("CARD_PLAY_SHOTS ABORT — run WINDOWED; headless bails the arc and shoots blank frames.")
		get_tree().quit(1)
		return

	await _boot_combat(_find_plain_act1_combat())
	# A FRAME SERIES MUST OWN ITS CLOCK. The machine that shot this had
	# anim_speed 3.0 (Instant) saved, which collapses the whole arc to ~0.07 s —
	# every mid-flight wait below sailed past a gesture that was already over, and
	# the first run of this file produced four identical seated boards. Reduce
	# Motion would be worse still: it bails the arc outright. Pin both, restore at
	# the end, never save.
	_old_speed = UserSettings.anim_speed
	_old_rm = UserSettings.reduce_motion
	UserSettings.anim_speed = 1.0
	UserSettings.reduce_motion = false
	print("ready: round=%d hand=%d · clock pinned (was anim_speed=%.1f reduce_motion=%s)"
		% [_combat.round_number, _combat._hand.size(), _old_speed, _old_rm])

	await _shoot("hand_rest", null)

	await _shoot_hover()
	await _shoot_grab_and_drag()

	# ── THE FLIGHT ───────────────────────────────────────────────────────────
	# A SLOPPY drop — released ~105 px off the slot's centre. That is genuinely
	# how big "sloppy" gets: `_nearest_player_slot` snaps to the closest slot, so
	# a larger miss lands in a DIFFERENT lane rather than making a longer arc. The
	# player's own flight is short by design (see the with_arc=TRUE note at
	# Combat._play_creature), which is exactly why these waits are fractions of
	# the measured duration and not round numbers.
	var sloppy := Vector2(-80.0, 70.0)
	await _fly_and_shoot(1, _combat.ROW_FRONT, sloppy, 0.20, "flight_early")
	await _fly_and_shoot(1, _combat.ROW_FRONT, sloppy, 0.50, "flight_apex")
	await _fly_and_shoot(1, _combat.ROW_FRONT, sloppy, 0.90, "flight_land")
	# The press: the arc is over, the card is back in its cell, and the wax press
	# is at its squash (PRESS_CONTACT in) with the ground ring going out.
	# 1.37 = the landing plus PRESS_CONTACT: the squash is at its deepest exactly
	# one contact-beat after the arc ends, and it is only 70 ms wide.
	await _fly_and_shoot(1, _combat.ROW_FRONT, sloppy, 1.37, "press")
	# Fully settled — the whole board, no single card: compact, at rest scale,
	# on the shared idle clock.
	await get_tree().create_timer(1.0).timeout
	await _shoot("seated", null)
	# The contrast frame: a drop right on the slot is a near-flat SEAT, not a loop
	# back over the player's own gesture. Same beat fraction as flight_apex, so
	# the two frames are directly comparable.
	await _fly_and_shoot(2, _combat.ROW_FRONT, Vector2.ZERO, 0.50, "seat_short")
	# ...and the arc at FULL size, which the player's own play can never show:
	# this is the shape a long deal takes, driven straight through the landing
	# funnel from off the board.
	await _shoot_long_arc()

	await _shoot_refusal()

	await _shoot_command_seal()
	await _shoot_struck_edict()

	UserSettings.anim_speed = _old_speed        # direct restore, never saved
	UserSettings.reduce_motion = _old_rm
	print("CARD_PLAY_SHOTS_DONE — %d frames in tools/screenshot/_cardplay_*.png" % _shot_n)
	get_tree().quit()


# ═══════════════════════════════════════════════════════════════════════════
#  THE BEATS
# ═══════════════════════════════════════════════════════════════════════════

## 02 — hover. The lift is 0.11 s, so this waits just long enough for the rise
## AND for the detail panel (tooltip_delay) to open, and no longer.
func _shoot_hover() -> void:
	var card: Control = _hand_card(0)
	if card == null:
		return
	_warp_to(card)
	card._on_mouse_entered()
	await get_tree().create_timer(0.45).timeout
	await _shoot("hover", card)
	card._on_mouse_exited()
	await get_tree().create_timer(0.3).timeout


## 03 + 04 — the pickup and the drag. Two frames off one gesture because they are
## 400 ms apart, not 40: the grab settle (GRAB_SETTLE) is done long before the
## lean has built any velocity.
func _shoot_grab_and_drag() -> void:
	var card: Control = _hand_card(0)
	if card == null:
		return
	var start: Vector2 = card.global_position + card.size * 0.5
	_warp_to(card)
	await get_tree().process_frame
	card._start_drag(start)
	# GRAB_SETTLE is 0.09 s — shoot just past it so the card is at DRAG_SCALE and
	# straightened, which is what the pickup POSE is. Any earlier and this frame
	# is a hand card that happens to be under the cursor.
	await get_tree().create_timer(0.13).timeout
	await _shoot("grab", card)

	# Now sweep it across the board. The lean damps toward cursor VELOCITY, so it
	# needs several frames of real movement to build — a single warp would shoot a
	# rigid card and the frame would be a lie about the driver.
	var target: Vector2 = _combat._slot_global_center(false, _combat.ROW_FRONT, 2)
	for i in range(18):
		var t: float = float(i + 1) / 18.0
		var p: Vector2 = start.lerp(target + Vector2(0, 120), t)
		Input.warp_mouse(p)
		card._update_drag(p)
		await get_tree().process_frame
	await _shoot("drag_lean", card)
	# Put it back rather than playing it — frame 05 wants a clean hand.
	card.global_position = Vector2(card.global_position.x, 10_000)
	card._end_drag()
	_combat._clear_slot_highlights()
	await get_tree().create_timer(0.5).timeout


## One play, one frame, aimed at `beat` — a FRACTION of the flight, not a wall
## time. 0.5 is the apex; anything over 1.0 is that far past the landing, into
## the wax press. Fractions rather than seconds because the arc's duration is
## derived from how far the card actually travels, so a fixed 0.16 s wait means a
## different beat for every drop and a completely different one the moment
## ARC_MAX_TIME is retuned.
##
## Each flight frame gets its OWN play: a `get_image()` readback costs more than
## the spacing between these beats, so a second capture off the same flight would
## land wherever the stall ended, not where it was aimed.
func _fly_and_shoot(lane: int, row: int, drop_offset: Vector2, beat: float,
		tag: String) -> void:
	await _clear_board()
	var card: Control = await _deal_fixture()
	if card == null:
		print("  (no fixture for %s — hand full?)" % tag)
		return
	var centre: Vector2 = _combat._slot_global_center(false, row, lane)
	# `_play_creature` reads `global_position + size * 0.5` (NOT size*scale*0.5 —
	# the drag pivot is centred), so the release point has to aim the same spot a
	# real drop does or the card lands in a different lane than intended.
	card.global_position = centre - card.size * 0.5 + drop_offset
	var dur: float = _arc_duration(drop_offset.length())
	_combat._on_card_played(card)
	# The wait is the RAW fraction, with no frame added at either end, because two
	# one-frame errors cancel: `_play_landing_pop` yields once before the tween
	# starts (to let the CenterContainer place the card so it knows where it is
	# flying TO), and `_shoot`'s `frame_post_draw` costs one more on the way out.
	# The first version of this file added the leading frame and forgot the
	# trailing one, and the 90% frame came back landed.
	await get_tree().create_timer(dur * beat).timeout
	await _shoot("%s [%d%% of a %.0fms arc]" % [tag, int(beat * 100.0), dur * 1000.0],
		card, tag)
	# Let the press finish before the next fixture is dealt, so a stray tween from
	# this card is never in the next frame.
	await get_tree().create_timer(0.7).timeout


## How long THIS flight will take, from the same three constants the arc reads.
## Travel is origin-to-origin, which is the drop offset: the aim is otherwise
## exact. Read out of the constant map with fallbacks so retuning them moves the
## frames automatically and renaming them degrades to sane defaults instead of
## crashing the series.
func _arc_duration(travel: float) -> float:
	var c: Dictionary = _combat.get_script().get_script_constant_map()
	var reach: float = clampf(travel / float(c.get("ARC_FULL_TRAVEL", 420.0)), 0.0, 1.0)
	# anim_speed is pinned to 1.0 for the series, so Motion.time() is identity.
	return lerpf(float(c.get("ARC_MIN_TIME", 0.12)),
		float(c.get("ARC_MAX_TIME", 0.38)), reach)


## The arc at FULL reach. The player's own play can never show this — a drop more
## than half a slot off snaps to a different lane — but it is the same funnel, and
## it is the shape worth looking at when judging the apex and the hang time.
func _shoot_long_arc() -> void:
	await _clear_board()
	var card: Control = await _deal_fixture()
	if card == null:
		return
	var centre: Vector2 = _combat._slot_global_center(false, _combat.ROW_FRONT, 2)
	card.global_position = centre - card.size * 0.5
	_combat._on_card_played(card)
	await get_tree().create_timer(1.0).timeout   # let it seat and settle first
	var seated = _combat._row_array(false, _combat.ROW_FRONT)[2]
	if seated == null or not is_instance_valid(seated):
		return
	var far: Vector2 = _combat._slot_global_center(false, _combat.ROW_BACK, 0) \
		+ Vector2(-260.0, 320.0)
	var dur: float = _arc_duration(500.0)   # clamps to full reach
	_combat._play_landing_pop(seated, far, true)
	await get_tree().create_timer(dur * 0.5).timeout
	await _shoot("long_arc [50%% of a %.0fms full-reach arc]" % (dur * 1000.0),
		seated, "long_arc")
	await get_tree().create_timer(0.8).timeout


## Sweep the board between flight frames. Without this, cards accumulate and the
## next drop lands on an OCCUPIED slot — which is a refusal, so the frame comes
## back showing a card in the hand instead of a card in the air. (That is exactly
## what the first run of this file produced.)
func _clear_board() -> void:
	for row in [_combat.ROW_FRONT, _combat.ROW_BACK]:
		var arr: Array = _combat._row_array(false, row)
		for i in range(_combat.LANES_PER_ROW):
			if arr[i] != null and is_instance_valid(arr[i]):
				var slot = _combat._slot_array(false, row)[i]
				if slot != null and is_instance_valid(slot):
					_combat._slot_take_card(slot, arr[i])
				arr[i].queue_free()
			arr[i] = null
	await get_tree().process_frame


## 14 + 15 + 16 — THE COMMAND SEAL IS STRUCK (✦1 of
## docs/CARD_PLAY_COOL_HUNT_20260803.md), and the same instrument REFUSING (✦7b).
##
## Paying Command squashes the seal+numeral wrapper and rings an impression off
## the wax's rim; a play that cannot be paid for takes the same dip with NO ring
## and no re-stamp. The two are only worth anything side by side, which is why
## they are shot consecutively.
##
## THE TIMING IS DERIVED, NOT GUESSED. The strike rides `MANA_SPEND_BEAT` (the
## resource is deliberately half a beat behind the card), then `Motion.press`
## bites over `time(PUNCH * 0.7)`. So the deepest point — the frame the
## impression is born on — is MANA_SPEND_BEAT + PUNCH*0.7 after the drop. Read
## out of the constant maps so retuning either one moves these frames instead of
## invalidating them. The REFUSAL has no spend beat: `_refuse_play` strikes on
## the frame it says no.
func _shoot_command_seal() -> void:
	var c: Dictionary = _combat.get_script().get_script_constant_map()
	var mc: Dictionary = load("res://scripts/ui/Motion.gd").get_script_constant_map()
	var bite: float = float(c.get("MANA_SPEND_BEAT", 0.09)) \
		+ float(mc.get("PUNCH", 0.10)) * 0.7
	for beat in [[bite, "seal_bite"], [bite + 0.08, "seal_ring"]]:
		await _clear_board()
		var card: Control = await _deal_fixture()
		if card == null:
			continue
		_combat.player_mana = 20
		var centre: Vector2 = _combat._slot_global_center(false, _combat.ROW_FRONT, 1)
		card.global_position = centre - card.size * 0.5
		_combat._on_card_played(card)
		await get_tree().create_timer(float(beat[0])).timeout
		await _shoot("%s [%.0fms after the drop]" % [beat[1], float(beat[0]) * 1000.0],
			null, String(beat[1]))
		await get_tree().create_timer(0.9).timeout
	# The FAILED press, for contrast: same dip, no impression, no re-stamp. Shot at
	# the bare bite — this one does not wait on MANA_SPEND_BEAT.
	await _clear_board()
	var poor: Control = await _deal_fixture()
	if poor == null:
		return
	var saved: int = int(_combat.player_mana)
	_combat.player_mana = 0
	var slot: Vector2 = _combat._slot_global_center(false, _combat.ROW_FRONT, 1)
	poor.global_position = slot - poor.size * 0.5
	_combat._on_card_played(poor)
	await get_tree().create_timer(float(mc.get("PUNCH", 0.10)) * 0.7).timeout
	await _shoot("seal_refused (the press that doesn't take)", null, "seal_refused")
	_combat.player_mana = saved
	await get_tree().create_timer(0.9).timeout


## 17 — THE EDICT STRUCK OUT (2026-08-04). Winning voids the foe's standing rule:
## `_dim_war_furniture(true)` draws a RubricStroke through every line of the
## plaque and LEAVES IT THERE, so the verdict plays over a cancelled law instead
## of over a law still in force.
##
## Driven at `_strike_the_edict` rather than by killing the enemy, on purpose: the
## real victory path fires the ★8 killing-blow moment (a colour drain, a duck, a
## push-in) and then changes scene on a 1.5 s timer, so a frame shot through it
## photographs the ceremony rather than the mark. This frame is about the mark.
func _shoot_struck_edict() -> void:
	var enc: String = _find_act1_combat_with_rule()
	if enc == "":
		print("  (no act-1 combat carries a standing rule — edict frames skipped)")
		return
	# A SECOND FIGHT, on purpose. Every frame above is shot on a deliberately
	# PLAIN encounter (passive_id empty) so nothing fires during the gesture —
	# which is exactly why that fight has no standing-rule plaque to strike.
	# Giving all thirteen play frames a live fight passive to win one frame here
	# is the wrong trade, so the edict gets its own boot, LAST, where a messy
	# teardown costs nothing. Still a `combat` type, so THE INITIATIVE (Generals
	# and keeps only) still cannot open a modal over the frame.
	if is_instance_valid(_combat):
		_combat.queue_free()
		await get_tree().process_frame
	await _boot_combat(enc)
	if _combat._passive_banner == null \
			or not is_instance_valid(_combat._passive_banner) \
			or not _combat._passive_banner.visible:
		print("  (plaque not posted in %s — edict frames skipped)" % enc)
		return
	await _shoot("edict_posted [%s — the rule in force]" % enc, null, "edict_posted")
	_combat._strike_the_edict()
	# Past the last line's stagger and its progress tween, and into the dry: the
	# mark is fully laid down and has darkened, which is the state it HOLDS. It
	# must NOT fade — if a later frame ever comes back empty, that is the bug.
	await get_tree().create_timer(0.75).timeout
	await _shoot("edict_struck (the law is void)", null, "edict_struck")


## 11 + 12 — THE REFUSAL. A drop on an occupied slot: `_refuse_play` shows the
## reason, relays the hand, then `play_return_to_hand` throws the card back at
## the fan with a BACK-out overshoot and a damped head-shake (REFUSAL_BEAT).
func _shoot_refusal() -> void:
	# Something to refuse against: a body already standing in the lane.
	var lane := 3
	if _combat._row_array(false, _combat.ROW_BACK)[lane] == null:
		_combat.summon_token(1, 1, lane, false, _combat.ROW_BACK, {}, "Probe Wall")
		await get_tree().create_timer(0.8).timeout
	var card: Control = await _deal_fixture()
	if card == null:
		return
	var centre: Vector2 = _combat._slot_global_center(false, _combat.ROW_BACK, lane)
	card.global_position = centre - card.size * 0.5
	_combat._on_card_played(card)
	# ~a third of REFUSAL_BEAT: the recoil is under way and the head-shake is at
	# its first swing. Late enough to be motion, early enough not to be the fan.
	await get_tree().create_timer(0.10).timeout
	await _shoot("refuse_shake", card)
	await get_tree().create_timer(0.9).timeout
	await _shoot("refuse_home", card)


# ═══════════════════════════════════════════════════════════════════════════
#  PLUMBING
# ═══════════════════════════════════════════════════════════════════════════

func _hand_card(idx: int) -> Control:
	if _combat._hand.size() <= idx:
		return null
	return _combat._hand[idx]


func _warp_to(card: Control) -> void:
	Input.warp_mouse(card.global_position + card.size * 0.5)


func _deal_fixture() -> Control:
	var before: int = _combat._hand.size()
	_combat._draw_card(FIXTURE_CARD)
	await get_tree().create_timer(0.35).timeout   # let the deal-in reflow land
	if _combat._hand.size() <= before:
		return null
	return _combat._hand.back()


## Stand a fight up and wait until it is genuinely playable. Extracted 2026-08-04
## because the edict frames need a SECOND fight (see _shoot_struck_edict) and a
## duplicated boot is exactly where a readiness trap gets re-introduced.
func _boot_combat(enc_id: String) -> void:
	RunState.start_new_run("stalwart", 0, 90210)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = enc_id
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host through
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so the press ring, the
	# slot-claim wash and every callout silently no-op — the landing frames would
	# come back with the card in the right place and none of the impact.
	get_tree().current_scene = _combat

	# READINESS TRAP: never poll `phase == Phase.PLAYER_TURN` (enum 0 is also the
	# uninitialised default). Round number plus a dealt hand is the honest gate.
	var waited := 0
	while waited < 400:
		if is_instance_valid(_combat) and _combat.round_number >= 1 \
				and not _combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	# One extra beat for the encounter intro banner to clear the board.
	await get_tree().create_timer(2.5).timeout
	_combat.player_mana = 20


func _find_plain_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat" \
				and String(e.get("passive_id", "")) == "":
			return String(id)
	return ""


## The opposite pick, for the edict frames: an ordinary act-1 fight that DOES
## post a standing rule. 98 of EncounterDB's 105 entries carry one, so this is
## the normal case and the passive-free fixture above is the rare one.
func _find_act1_combat_with_rule() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat" \
				and String(e.get("passive_desc", "")) != "":
			return String(id)
	return ""


## SHOOT AFTER THE DRAW, NEVER BEFORE. `get_viewport().get_texture().get_image()`
## reads whatever the GPU last finished; without `await RenderingServer.
## frame_post_draw` in front of it that is the PREVIOUS frame, so every capture
## in the series would be one beat stale — which on a 0.3 s arc is a different
## picture entirely.
func _shoot(label: String, card: Control, file_tag: String = "") -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	_shot_n += 1
	var tag: String = file_tag if file_tag != "" else label
	img.save_png("res://tools/screenshot/_cardplay_%02d_%s.png" % [_shot_n, tag])
	# The state at capture, so a reader can tell WHICH beat this frame caught
	# rather than trusting the filename. `IN FLIGHT` means the card was detached
	# onto the HUD layer at z 200; `landed` means the round trip was already done.
	var state := "(whole board)"
	if card != null and is_instance_valid(card):
		var parent: Node = card.get_parent()
		var flying: bool = int(card.z_index) >= 200
		state = "%s  z=%d parent=%s scale=%.3f rot=%+.3f" % [
			"IN FLIGHT" if flying else "landed  ", int(card.z_index),
			parent.name if parent != null else "<none>", card.scale.x, card.rotation]
	print("SHOT %02d  %-46s %s  %s" % [_shot_n, label, img.get_size(), state])
