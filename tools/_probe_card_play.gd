extends Node
## _probe_card_play.gd — the PLAY GESTURE: hand → flight → slot (2026-08-03).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_card_play.tscn   (CI)
##   Godot.exe            --path "D:\Godot" res://tools/_probe_card_play.tscn   (FULL)
##
## Grep the output for "ALL PASS" — don't trust the exit code alone. Also read
## the SKIP count: `_play_landing_pop` forces `with_arc = false` under headless
## BY DESIGN (the arc is decorative and a third of a second of await per arrival
## would tax every probe in the harness), so a headless run cannot observe the
## detach → HUD-layer → re-attach round trip at all. Those eight checks SKIP
## there rather than passing on an empty board, and the WINDOWED run (editor
## closed) is the one that actually gates the flight.
##
## (The standing failure this header used to record — `_play_armament` carrying
## two refusals on the OLD `_show_info` + `_layout_hand` + `return` shape — was
## FIXED 2026-08-03; both now route through `_refuse_play`. The check that caught
## them stays: it is what makes `_refuse_play` the only way to say no.)
##
## ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
## Playing a card is the single most-repeated gesture in the game and the only
## one that DETACHES a live node from its parent, animates it on a foreign
## canvas layer, and puts it back. `Combat._play_landing_pop`'s arc branch does
## exactly that: remove_child from the slot's CenterContainer → add_child to
## `_hud_layer` → z_index 200 → tween → remove_child → add_child back → z_index
## 0. Every step of that round trip is a place a card can be STRANDED: parented
## to the HUD layer, floating at z=200, still in `_hand`, or seated at a scale
## the flight left behind. Nothing in the harness caught any of that before.
##
## ── HOW IT IS WRITTEN (it was authored against a MOVING target) ───────────
## Card2D.gd and Combat.gd were being rewritten while this file was built, so
## every assertion is a CONTRACT or an INVARIANT, never a number lifted out of
## the source. Durations are compared A/B against THEMSELVES (speed 1 vs speed 3,
## Reduce Motion off vs on) rather than matched to a literal, so retuning the arc
## from 0.34 s to 0.19 s does not turn this file red — while a duration that stops
## asking the animation clock at all still does. The structural checks name
## FUNCTIONS, not line numbers, and exist precisely so that a NEW rotation writer
## or a NEW refusal has to be declared on purpose rather than slipping in.
##
## ── THE CHECKS ────────────────────────────────────────────────────────────
##  A. ROUND TRIP     the flight always puts the card back: real parent, z 0,
##                    rest scale, off the HUD layer — including when a second
##                    landing interrupts a live flight, and when the card is
##                    freed mid-air.
##  B. BOOKKEEPING    a real _on_card_played leaves the card out of _hand, out of
##                    _hand_container, and in _row_array(false, row)[lane] with
##                    matching current_lane / current_row.
##  C. REFUSAL        a rejected drop (occupied slot / closed ground / no
##                    Command) is INFORMATIONAL: the card returns to the hand and
##                    the board is untouched — and it still does so under Reduce
##                    Motion, where only decoration may be gated.
##  D. THE CLOCK      the anim-speed setting must actually reach the flight
##                    (measured: speed 3 must land the card materially sooner
##                    than speed 1), and Reduce Motion must collapse the
##                    decorative entrance while still landing the content.
##  E. ROTATION       `Card2D.rotation` keeps exactly one writer. `_process`
##                    owns it while `_lean_active`; every tween that writes it
##                    lives in a DECLARED function that cannot run during a drag,
##                    the handoff order that makes that true is asserted from
##                    inside the `played` signal, and a pivot swap never moves the
##                    card on screen.
##
## ── TRAPS THIS FILE OBEYS (paid for in earlier rebuilds) ──────────────────
##  · Phase.PLAYER_TURN is enum 0, which is also the uninitialised default, so
##    readiness is polled on `round_number >= 1` + a non-empty hand.
##  · A plain act-1 `combat` encounter is chosen on purpose: THE INITIATIVE only
##    opens at a General or a keep, so no modal can stall the run. (Headless
##    auto-picks the first option anyway — belt and braces.)
##  · Fixtures use `hexwright`: a vanilla 2/4 with no keywords and no on_enter /
##    on_play / on_death, so nothing fires between the play and the assertion.

const COMBAT_SCENE := "res://scenes/combat.tscn"
const FIXTURE_CARD := "hexwright"   # vanilla 2/4, no keywords, no triggers

## Every function in Card2D allowed to tween `self.rotation`, with the reason it
## cannot collide with the lean driver. A rotation tween in ANY OTHER function is
## a second writer and fails the check below — update this list deliberately, the
## same way RIDERS is kept in step in _probe_status_riders.gd.
const ROTATION_TWEEN_OWNERS := {
	"set_hand_target":
		"guarded by `not _is_hovered and not _is_being_dragged`",
	"_on_mouse_entered":
		"returns early while _is_being_dragged; only tweens rotation when the lean cannot arm",
	"_on_mouse_exited":
		"returns early while _is_being_dragged; carries rotation home after _disarm_lean",
	"_die":
		"the card is dead and off the hand — no drag can be live",
	"play_death_flourish":
		"_die's VISUAL half, split out 2026-08-04 so a skirmish client can play the same death without _die's `destroyed` signal (which would run on-death dispatch on a peer that must not resolve it). Same argument as _die: the card is dying on the board, so no drag can be live.",
	"play_attack_lunge":
		"battlefield only; hand cards never lunge",
	"_break_shield_seal":
		"tweens a CHILD ornament's rotation, not the card's",
	"play_return_to_hand":
		"THE REFUSAL head-shake; only reachable after _end_drag has already disarmed the lean",
}

var _fails := 0
var _checks := 0
var _skips := 0
var _combat = null
var _headless := false
## Set once, by watching a real flight: false means `_play_landing_pop` took its
## no-arc branch, so every assertion about the detach/re-attach round trip would
## be VACUOUS. Vacuous green is worse than red — those checks become SKIPs.
var _arc_engages := false


func _check(ok: bool, label: String) -> bool:
	_checks += 1
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok


## Not a pass and not a failure — a check that could not be OBSERVED in this run.
## Counted and printed separately so a headless CI run can never be mistaken for
## full coverage of the flight.
func _skip(label: String, reason: String) -> void:
	_skips += 1
	print("  SKIP  %s  — %s" % [label, reason])


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	print("[card_play] === THE PLAY GESTURE === (display: %s)"
		% DisplayServer.get_name())
	if _headless:
		# `_play_landing_pop` forces `with_arc = false` under headless BY DESIGN —
		# the arc is decorative and a third of a second of await per arrival would
		# tax every probe in the harness. That is correct, and it also means the
		# detach → HUD-layer → re-attach round trip DOES NOT HAPPEN here. Run this
		# file windowed (editor closed) for the full battery:
		#   Godot.exe --path "D:\Godot" res://tools/_probe_card_play.tscn
		print("[card_play] headless: the arc is bailed by design — flight checks will SKIP.")

	# ── E runs first: it needs no combat scene, so a broken board still leaves
	# the rotation-ownership contract gated. ──────────────────────────────────
	_check_rotation_ownership()

	if not await _boot_combat():
		_finish()
		return

	await _check_bookkeeping()
	await _check_refusals()
	await _check_round_trip()
	await _check_clock()

	_finish()


func _finish() -> void:
	print("[card_play] %d checks, %d failures, %d skipped" % [_checks, _fails, _skips])
	if _skips > 0:
		print("[card_play] %d check(s) could not be OBSERVED in this run — see the SKIP lines." % _skips)
	print("[card_play] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


# ═══════════════════════════════════════════════════════════════════════════
#  BOOT
# ═══════════════════════════════════════════════════════════════════════════

func _boot_combat() -> bool:
	RunState.start_new_run("stalwart", 0, 90210)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_plain_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	_combat = load(COMBAT_SCENE).instantiate()
	add_child(_combat)
	# READINESS TRAP: never poll `phase == Phase.PLAYER_TURN` — PLAYER_TURN is
	# enum 0, which is also the uninitialised default, so it reads true against a
	# half-built board. Round number plus a dealt hand is the honest gate.
	#
	# SECOND READINESS TRAP, measured 2026-08-03: "a dealt hand" is NOT
	# `not _hand.is_empty()`. The opening deal is STAGGERED (deal_in delays), so
	# that test releases the instant the FIRST card lands, with five more still
	# in flight — the hand was observed going 1 → 3 → 5 → 6 over ~300 ms after
	# the old gate returned. Everything downstream then raced the deal: a draw
	# that should have grown the hand by 1 grew it by 2, and `_hand.back()`
	# handed back a card the DEAL had just appended instead of the one we drew,
	# so the probe aimed at a slot and played the wrong card while its fixture
	# sat in hand. That reads as eight play-path failures and is none — it cost a
	# real investigation, so the gate now waits for the hand to STOP GROWING.
	var waited := 0
	var stable := 0
	var last_hand := -1
	while waited < 400:
		if is_instance_valid(_combat) and _combat.round_number >= 1 \
				and not _combat._hand.is_empty():
			var n: int = _combat._hand.size()
			if n == last_hand:
				stable += 1
				if stable >= 6:   # ~0.3 s of no growth — longer than the deal's stagger
					break
			else:
				stable = 0
				last_hand = n
		await get_tree().create_timer(0.05).timeout
		waited += 1
	if not _check(is_instance_valid(_combat) and _combat.round_number >= 1
			and not _combat._hand.is_empty(), "combat reached round 1 with a dealt hand"):
		return false
	_check(_combat._initiative == "",
		"a plain hold opens with no INITIATIVE modal to stall on")
	# Command is not what this file is about — take it out of the equation so a
	# cost check can never masquerade as a play-path failure. (No round is
	# advanced below, so _start_round never reassigns this.)
	_combat.player_mana = 20
	return true


func _find_plain_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat" \
				and String(e.get("passive_id", "")) == "":
			return String(id)
	for id in EncounterDB.ENCOUNTERS:
		var e2: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e2.get("act", 1)) == 1 and String(e2.get("type", "")) == "combat":
			return String(id)
	return ""


# ═══════════════════════════════════════════════════════════════════════════
#  FIXTURES
# ═══════════════════════════════════════════════════════════════════════════

## A real hand card, drawn through Combat's own `_draw_card` so every signal the
## play path relies on (`played`, `dragging`, `drag_ended`, `dismiss_requested`)
## is wired exactly as it is in a fight. Never hand-instantiate a Card2D here —
## a hand card that Combat did not wire cannot be played at all.
## IDENTIFY THE CARD, NEVER ASSUME ITS POSITION. `_hand.back()` is only the card
## we just drew if nothing else appended in the same window — and something can:
## a staggered opening deal, a relic's bonus draw, a reactive. When it lied, the
## probe played an unrelated card and reported eight failures against a fixture
## that had never left the hand. Diff the hand and match on identity instead.
func _deal_fixture() -> Control:
	var before: Array = _combat._hand.duplicate()
	_combat._draw_card(FIXTURE_CARD)
	await get_tree().process_frame
	if _combat._hand.size() <= before.size():
		return null
	# Newest first: if the deal raced us and drew a second copy, we want ours.
	var fresh: Array = _combat._hand.filter(func(c): return not before.has(c))
	for i in range(fresh.size() - 1, -1, -1):
		var c = fresh[i]
		if c != null and is_instance_valid(c) and String(c.card_id) == FIXTURE_CARD:
			return c
	return null


## Park the card so its CENTRE sits on a given slot. `_play_creature` reads
## `global_position + size * 0.5` (NOT size*scale*0.5 — the drag pivot is
## centred), so the fixture must aim the same point the real drop does.
func _aim_at_slot(card: Control, row: int, lane: int) -> void:
	var centre: Vector2 = _combat._slot_global_center(false, row, lane)
	card.global_position = centre - card.size * 0.5


## Sweep BOTH the board and the hand between sections. The hand half matters:
## every refused fixture stays in hand by design, and `_draw_card` silently
## returns once `_hand.size() >= MAX_HAND_SIZE` — so without this, a later
## section's fixture comes back null and reads as a play-path failure when it is
## really a full hand.
func _clear_board() -> void:
	for card in _combat._hand.duplicate():
		if card != null and is_instance_valid(card):
			if _combat._hand_container != null \
					and _combat._hand_container.is_ancestor_of(card):
				_combat._hand_container.remove_child(card)
			card.queue_free()
	_combat._hand.clear()
	for is_enemy in [false, true]:
		for row in [_combat.ROW_FRONT, _combat.ROW_BACK]:
			var arr: Array = _combat._row_array(is_enemy, row)
			for i in range(_combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					var slot = _combat._slot_array(is_enemy, row)[i]
					if slot != null and is_instance_valid(slot):
						_combat._slot_take_card(slot, arr[i])
					arr[i].queue_free()
				arr[i] = null
	await get_tree().process_frame


## True while the card is anywhere under the HUD canvas layer — the borrowed
## canvas the flight animates on. A card that is still here after the gesture
## settles is a STRANDED card: it renders above the whole board, ignores the
## slot's layout, and no board query will ever find it.
func _on_hud_layer(card: Control) -> bool:
	var hud: CanvasLayer = _combat._hud_layer
	return hud != null and is_instance_valid(hud) and hud.is_ancestor_of(card)


## Is this card on the shared battlefield visual clock? `enable_idle_bob` calls
## `_register_battlefield_visuals` FIRST, before the Reduce Motion exit, because
## a player card is compacted while detached from the hand tree and the landing
## callback is its only in-tree opportunity to join. The bob is decorative; the
## registration drives the LIVE status rail and is not.
func _registered_on_battlefield_clock(card: Control) -> bool:
	for ref_variant in Card2D._battlefield_visual_refs:
		var ref := ref_variant as WeakRef
		if ref != null and ref.get_ref() == card:
			return true
	return false


func _seated_in(card: Control, row: int, lane: int) -> bool:
	var slot: Control = _combat._slot_array(false, row)[lane]
	if slot == null or not is_instance_valid(slot):
		return false
	return slot.is_ancestor_of(card)


# ═══════════════════════════════════════════════════════════════════════════
#  B. BOOKKEEPING — the card leaves the hand and arrives in the slot
# ═══════════════════════════════════════════════════════════════════════════

func _check_bookkeeping() -> void:
	print("[card_play] -- B. hand -> slot bookkeeping --")
	await _clear_board()
	var card: Control = await _deal_fixture()
	if not _check(card != null, "fixture: a %s dealt into the hand" % FIXTURE_CARD):
		return
	_check(_combat._hand.has(card), "the fixture starts in _hand")
	_check(_combat._hand_container.is_ancestor_of(card),
		"the fixture starts parented to the hand container")

	var lane := 2
	var row: int = _combat.ROW_FRONT
	_aim_at_slot(card, row, lane)
	_combat._on_card_played(card)
	# The landing is a coroutine fired and forgotten by _place_card_in_slot;
	# give it real frames to complete rather than guessing a duration.
	await _settle(card)

	if not _check(is_instance_valid(card), "the played card survived the gesture"):
		return
	_check(not _combat._hand.has(card), "the played card is GONE from _hand")
	_check(not _combat._hand_container.is_ancestor_of(card),
		"the played card is no longer parented to the hand container")
	_check(_combat._row_array(false, row)[lane] == card,
		"the played card is in _row_array(false, %d)[%d]" % [row, lane])
	_check(int(card.current_row) == row and int(card.current_lane) == lane,
		"current_row/current_lane agree with the slot it landed in (got %d/%d)"
			% [int(card.current_row), int(card.current_lane)])
	_check(_seated_in(card, row, lane),
		"the played card is parented INSIDE its lane slot (not floating)")
	_check(not _on_hud_layer(card),
		"the played card is NOT stranded on the HUD layer")
	_check(int(card.z_index) == 0,
		"z_index returned to 0 (flight lifts it to 200; a card left there covers the board) — got %d"
			% int(card.z_index))
	_check(bool(card.is_on_battlefield),
		"the played card is flagged is_on_battlefield")
	# The landing callback is the ONLY in-tree chance a player card gets to join
	# the shared battlefield visual clock: it was compacted while detached from
	# the hand, so its layout-time registration could not take. Miss it and the
	# card renders fine and its status rail never polls again — a silent failure
	# that no visual check would catch.
	#
	# ── WAIT FOR THE LANDING TO FINISH LANDING (headless, 2026-08-04) ─────────
	# This check went red headless while passing windowed, and it was THIS FILE's
	# bug, not the game's. `_settle` polls "off the HUD layer and z_index 0" —
	# which on the NON-ARC path (the only path headless takes, by design) is true
	# on the very first frame, so it returns after its 8 quiet frames with the wax
	# press still running. The registration rides that press's FINAL
	# `tween_callback`, ~0.25 s of tween time later. Windowed, 8 vsynced frames
	# are ~133 ms and the race was being won by luck; headless the frames are
	# sub-millisecond, 8 of them pass in ~2 ms, and the check read the state
	# before the card had finished arriving. The card was never unregistered — it
	# was not registered YET.
	#
	# `_quiesce` is this file's own published answer to exactly this mistake
	# ("wait until the card has stopped MOVING, not merely stopped flying") and it
	# carries a 320 ms floor, so it cannot be fooled by a tween that has not
	# started. NOTE WHAT THIS IS NOT: it does not poll for the registration and
	# give up quietly. It waits for the GESTURE to be over and then asserts, so a
	# landing that genuinely never registers still fails — which is the point,
	# because that failure is invisible on screen.
	var reg_at_settle: bool = _registered_on_battlefield_clock(card)
	await _quiesce(card)
	print("  [diag] battlefield-clock registration: at _settle=%s, after _quiesce=%s"
		% [reg_at_settle, _registered_on_battlefield_clock(card)])
	_check(_registered_on_battlefield_clock(card),
		"the played card joined the shared battlefield visual clock (else its status rail goes dead)")

	# ── The same landing, under Reduce Motion ────────────────────────────────
	# The press is decorative and snaps; the REGISTRATION on that path is not,
	# and it is exactly the kind of thing an early `return` in the Reduce Motion
	# branch would drop.
	var old_rm_seat: bool = UserSettings.reduce_motion
	UserSettings.reduce_motion = true
	var rm_card: Control = await _deal_fixture()
	if rm_card != null:
		_aim_at_slot(rm_card, _combat.ROW_BACK, 0)
		_combat._on_card_played(rm_card)
		await _quiesce(rm_card)
		_check(is_instance_valid(rm_card)
				and _combat._row_array(false, _combat.ROW_BACK)[0] == rm_card,
			"Reduce Motion: the card still seats in its slot")
		_check(is_instance_valid(rm_card) and _registered_on_battlefield_clock(rm_card),
			"Reduce Motion: the card STILL joins the battlefield visual clock (registration is not decorative)")
		_check(is_instance_valid(rm_card) and int(rm_card.z_index) == 0,
			"Reduce Motion: z_index is back to 0")
		_check(is_instance_valid(rm_card) and not _on_hud_layer(rm_card),
			"Reduce Motion: the card is not left on the HUD layer")
	UserSettings.reduce_motion = old_rm_seat   # direct restore, never saved

	# Two cards must not collapse onto one slot: the second drop on an occupied
	# lane is a refusal, tested in C. Here, a SECOND lane must seat independently.
	var card2: Control = await _deal_fixture()
	if _check(card2 != null, "fixture: a second %s dealt" % FIXTURE_CARD):
		_aim_at_slot(card2, _combat.ROW_BACK, 1)
		_combat._on_card_played(card2)
		await _settle(card2)
		_check(_combat._row_array(false, _combat.ROW_BACK)[1] == card2,
			"a second play seats in its own row/lane without disturbing the first")
		_check(_combat._row_array(false, row)[lane] == card,
			"...and the first card is still in its slot")


# ═══════════════════════════════════════════════════════════════════════════
#  C. REFUSAL — a rejected drop is informational and must always land
# ═══════════════════════════════════════════════════════════════════════════

func _check_refusals() -> void:
	print("[card_play] -- C. rejected drops --")
	await _clear_board()
	# Occupy one lane with a token so the refusal has something to refuse.
	_combat.summon_token(1, 1, 0, false, _combat.ROW_FRONT, {}, "Probe Wall")
	await get_tree().process_frame
	var blocker: Control = _combat._row_array(false, _combat.ROW_FRONT)[0]
	if not _check(blocker != null, "fixture: a body standing in lane 0"):
		return

	for rm in [false, true]:
		var old_rm: bool = UserSettings.reduce_motion
		UserSettings.reduce_motion = rm
		var tag := "Reduce Motion ON" if rm else "Reduce Motion off"
		var card: Control = await _deal_fixture()
		if card != null:
			var hand_before: int = _combat._hand.size()
			_aim_at_slot(card, _combat.ROW_FRONT, 0)
			_combat._on_card_played(card)
			await _settle(card)
			_check(is_instance_valid(card) and _combat._hand.has(card),
				"%s: a drop on an OCCUPIED slot leaves the card in the hand" % tag)
			_check(is_instance_valid(card)
					and _combat._hand_container.is_ancestor_of(card),
				"%s: the refused card is still parented to the hand" % tag)
			_check(is_instance_valid(card) and not _on_hud_layer(card),
				"%s: a refusal never detaches the card onto the HUD layer" % tag)
			_check(_combat._row_array(false, _combat.ROW_FRONT)[0] == blocker,
				"%s: the occupied slot still holds its original body" % tag)
			_check(_combat._hand.size() == hand_before,
				"%s: the hand size is unchanged by a refusal" % tag)
			_check(is_instance_valid(card) and not bool(card.is_on_battlefield),
				"%s: the refused card is not flagged onto the battlefield" % tag)
		UserSettings.reduce_motion = old_rm   # direct restore, never saved

	# ── THE REFUSAL BEAT IS WIRED ────────────────────────────────────────────
	# Card2D ships `play_return_to_hand` with a published contract in its header:
	# "call `_layout_hand()` FIRST, then `card.play_return_to_hand()`". A refusal
	# that only calls `_layout_hand()` returns the card on the PLAIN reflow tween
	# — the exact motion a card makes when a NEIGHBOUR is drawn — so the game
	# saying no is indistinguishable from a shuffle. The beat is informational,
	# so it is not enough for it to exist in Card2D; Combat has to call it.
	var card2d_src: String = load("res://scripts/Card2D.gd").source_code
	var combat_src: String = load("res://scripts/scenes/Combat.gd").source_code
	var has_beat: bool = card2d_src.contains("func play_return_to_hand")
	print("  [diag] Card2D declares play_return_to_hand: %s · Combat call sites: %d"
		% [has_beat, combat_src.count("play_return_to_hand(")])
	if has_beat:
		_check(combat_src.count("play_return_to_hand(") > 0,
			"Combat routes its refusals through Card2D.play_return_to_hand (declared in Card2D but never called = a dead refusal beat)")
	# ...and ONE funnel, not seventeen hand-written bounces. The old refusal shape
	# was `_show_info(...)` + `_layout_hand()` + `return`, which returns the card
	# on the PLAIN reflow tween — the same motion a card makes when a NEIGHBOUR is
	# drawn. Any survivor of that shape inside the play gesture is a refusal the
	# player cannot feel, and it will not be caught by looking at the screen
	# because the card DOES go home; it just says nothing on the way.
	var unfunnelled: Array[String] = _unfunnelled_refusals(combat_src)
	_check(unfunnelled.is_empty(),
		"every refusal in the play gesture routes through the _refuse_play funnel%s"
			% ("" if unfunnelled.is_empty() else "; bare _show_info+_layout_hand+return at "
				+ ", ".join(unfunnelled)))

	# The card must come HOME whatever beat carries it: a refused card left short
	# of its fan slot sits over the board and reads as still in play.
	var homed: Control = await _deal_fixture()
	if homed != null:
		_aim_at_slot(homed, _combat.ROW_FRONT, 0)
		_combat._on_card_played(homed)
		await _settle_hand(homed)
		_check(is_instance_valid(homed)
				and homed.position.distance_to(homed._hand_target_position) < 2.0,
			"a refused card settles back onto its fan slot (%s vs %s)"
				% [homed.position if is_instance_valid(homed) else "freed",
					homed._hand_target_position if is_instance_valid(homed) else "-"])
		_check(is_instance_valid(homed)
				and is_equal_approx(homed.rotation, homed._hand_target_rotation),
			"a refused card ends on its fan ANGLE (the head-shake must land exactly, not park off-angle)")
		_check(is_instance_valid(homed)
				and homed.scale.is_equal_approx(homed._hand_target_scale),
			"a refused card ends at its fan scale")

	# A refusal must also not spend Command. This is the half a silent animation
	# regression would hide: the card bounces back but the turn already paid.
	var card3: Control = await _deal_fixture()
	if card3 != null:
		var mana_before: int = int(_combat.player_mana)
		_aim_at_slot(card3, _combat.ROW_FRONT, 0)
		_combat._on_card_played(card3)
		await _settle(card3)
		_check(int(_combat.player_mana) == mana_before,
			"a refused play spends no Command (%d -> %d)"
				% [mana_before, int(_combat.player_mana)])

	# Not enough Command is the other refusal shape, and it must behave the same.
	var card4: Control = await _deal_fixture()
	if card4 != null:
		var saved: int = int(_combat.player_mana)
		_combat.player_mana = 0
		_aim_at_slot(card4, _combat.ROW_BACK, 3)
		_combat._on_card_played(card4)
		await _settle(card4)
		_check(is_instance_valid(card4) and _combat._hand.has(card4),
			"a play with no Command leaves the card in the hand")
		_check(_combat._row_array(false, _combat.ROW_BACK)[3] == null,
			"...and seats nothing on the board")
		_combat.player_mana = saved


## Find the OLD refusal shape surviving inside the play-gesture functions:
## `_show_info(...)` … `_layout_hand()` … `return`, with no `play_return_to_hand`
## between them. Scoped to the four functions the drag actually reaches, because
## `_layout_hand()` is a perfectly ordinary call everywhere else (and on the
## SUCCESS path of a play, where the hand closes the gap the card left).
func _unfunnelled_refusals(src: String) -> Array[String]:
	const GESTURE := ["_on_card_played", "_play_creature", "_play_spell", "_play_armament"]
	var lines: PackedStringArray = src.split("\n")
	var fn := ""
	var said_no_at := -1     # line index of the most recent _show_info in this function
	var out: Array[String] = []
	for i in range(lines.size()):
		var raw: String = lines[i]
		if raw.begins_with("func "):
			fn = raw.substr(5).split("(")[0].strip_edges()
			said_no_at = -1
			continue
		if not (fn in GESTURE):
			continue
		var t: String = raw.strip_edges()
		if t.begins_with("#"):
			continue
		if t.contains("_show_info("):
			said_no_at = i
		elif t.contains("play_return_to_hand(") or t.contains("_refuse_play("):
			said_no_at = -1
		elif t.contains("_layout_hand()") and said_no_at >= 0 and (i - said_no_at) <= 3:
			out.append("%s:%d" % [fn, i + 1])
			said_no_at = -1
	return out


# ═══════════════════════════════════════════════════════════════════════════
#  A. ROUND TRIP — the flight's detach/re-attach can never strand a card
# ═══════════════════════════════════════════════════════════════════════════

func _check_round_trip() -> void:
	print("[card_play] -- A. the flight's detach -> re-attach round trip --")
	await _clear_board()
	var lane := 1
	var row: int = _combat.ROW_FRONT
	var card: Control = await _seat_one(row, lane)
	if not _check(card != null, "fixture: a body seated in lane %d" % lane):
		return
	# Capture "rest" only once the seat is FULLY quiet — the wax press is still
	# tweening scale for a fifth of a second after the card lands, and a rest
	# value read mid-press turns every later scale assertion into noise.
	await _quiesce(card)
	var rest_scale: Vector2 = card.scale
	var from: Vector2 = _combat._slot_global_center(false, _combat.ROW_BACK, 3)
	from += Vector2(0, 260)

	# ── The plain arc ────────────────────────────────────────────────────────
	_combat._play_landing_pop(card, from, true)
	_arc_engages = await _watch_for_lift(card)
	print("  [diag] the flight detached the card onto the HUD layer: %s" % _arc_engages)
	await _quiesce(card, 4.0)
	if not _arc_engages:
		# `_play_landing_pop` forces `with_arc = false` under headless (and under
		# Reduce Motion). No detach happened, so asserting the round trip here
		# would be green with ZERO coverage — the one outcome a gate must never
		# produce. Say so instead.
		var why := "the arc is bailed under headless by design — run this probe windowed" \
			if _headless else "the arc did not engage on a real display (with_arc bailed?)"
		if not _headless:
			_check(false, "the flight ENGAGES its arc on a real display — %s" % why)
		for label in ["after the arc the card is back inside its lane slot",
				"after the arc the card is off the HUD layer (the strand case)",
				"after the arc z_index is back to 0",
				"after the arc the card is at its resting scale",
				"a landing that INTERRUPTS a live flight does not strand the card",
				"a card freed MID-AIR does not crash the fight"]:
			_skip(label, why)
		return
	_check(is_instance_valid(card), "the card survived a full arc flight")
	if is_instance_valid(card):
		_check(_seated_in(card, row, lane),
			"after the arc the card is back INSIDE its lane slot")
		_check(not _on_hud_layer(card),
			"after the arc the card is off the HUD layer (the strand case)")
		_check(int(card.z_index) == 0,
			"after the arc z_index is back to 0 (got %d)" % int(card.z_index))
		_check(card.scale.is_equal_approx(rest_scale),
			"after the arc the card is at its resting scale (%s vs %s) — the flight shrinks it to 0.92 and punches to 1.05 on the way"
				% [card.scale, rest_scale])
		_check(_combat._row_array(false, row)[lane] == card,
			"the row array still points at the card after the flight")

	# ── An INTERRUPTED flight ────────────────────────────────────────────────
	# The realistic shape: a landing arc is live when something else moves the
	# same card — an on-enter that redeploys, a swap, a reposition. All of those
	# call _place_card_in_slot / _play_landing_pop again, and every one of them
	# reads the card's CURRENT parent as the parent to restore. Mid-flight that
	# parent is the HUD layer, so a naive second landing re-attaches the card to
	# the HUD layer FOREVER. This is the highest-value assertion in the file.
	if is_instance_valid(card):
		_combat._play_landing_pop(card, from, true)
		await _watch_for_lift(card)
		_combat._play_landing_pop(card, from + Vector2(120, 0), true)
		await _quiesce(card, 5.0)
		_check(is_instance_valid(card), "the card survived an interrupted flight")
		if is_instance_valid(card):
			_check(not _on_hud_layer(card),
				"a landing that interrupts a live flight does NOT strand the card on the HUD layer")
			_check(_seated_in(card, row, lane),
				"an interrupted flight still ends inside the lane slot")
			_check(int(card.z_index) == 0,
				"an interrupted flight still returns z_index to 0 (got %d)"
					% int(card.z_index))

	# ── A card freed MID-AIR must not take the scene with it ─────────────────
	var doomed: Control = await _seat_one(_combat.ROW_BACK, 2)
	if _check(doomed != null, "fixture: a body seated for the mid-air free"):
		_combat._play_landing_pop(doomed, from, true)
		await _watch_for_lift(doomed)
		doomed.queue_free()
		await get_tree().create_timer(0.8).timeout
		_check(is_instance_valid(_combat) and _combat.is_inside_tree(),
			"freeing a card mid-flight does not crash the fight")
		_check(_combat._hud_layer == null or not is_instance_valid(_combat._hud_layer)
				or _hud_layer_card_count() == 0,
			"no card node is left behind on the HUD layer after a mid-air free")


func _hud_layer_card_count() -> int:
	var hud: CanvasLayer = _combat._hud_layer
	if hud == null or not is_instance_valid(hud):
		return 0
	var n := 0
	for c in hud.get_children():
		if c is Control and c.has_method("is_creature"):
			n += 1
	return n


## Seat a real fixture card in a slot by playing it, so the state under test is
## the state a fight actually produces.
func _seat_one(row: int, lane: int) -> Control:
	var card: Control = await _deal_fixture()
	if card == null:
		return null
	_aim_at_slot(card, row, lane)
	_combat._on_card_played(card)
	await _settle(card)
	if not is_instance_valid(card) or _combat._row_array(false, row)[lane] != card:
		return null
	return card


# ═══════════════════════════════════════════════════════════════════════════
#  D. THE CLOCK — anim speed and Reduce Motion must both reach the flight
# ═══════════════════════════════════════════════════════════════════════════

func _check_clock() -> void:
	print("[card_play] -- D. the animation clock reaches the play flight --")
	await _clear_board()
	var card: Control = await _seat_one(_combat.ROW_FRONT, 3)
	if not _check(card != null, "fixture: a body to fly repeatedly"):
		return
	var from: Vector2 = _combat._slot_global_center(false, _combat.ROW_BACK, 0) \
		+ Vector2(0, 240)

	var old_speed: float = UserSettings.anim_speed
	var old_rm: bool = UserSettings.reduce_motion
	UserSettings.reduce_motion = false

	UserSettings.anim_speed = 1.0
	var t_normal: float = await _timed_flight(card, from)
	UserSettings.anim_speed = 3.0
	var t_fast: float = await _timed_flight(card, from)
	UserSettings.anim_speed = 1.0
	UserSettings.reduce_motion = true
	var t_rm: float = await _timed_flight(card, from)

	UserSettings.anim_speed = old_speed     # direct restore, never saved
	UserSettings.reduce_motion = old_rm

	print("  [diag] flight wall time — speed 1.0: %.3fs · speed 3.0 (Instant): %.3fs · Reduce Motion: %.3fs"
		% [t_normal, t_fast, t_rm])
	print("  [diag] the flight's duration asks the animation clock (Motion.time / anim_time): %s"
		% _flight_body_scales_its_clock())

	if not _arc_engages:
		# No arc ran, so all three numbers are the same near-zero no-arc path and
		# the comparison would be meaningless in both directions.
		_skip("Animation Speed reaches the play flight",
			"no arc engaged in this run — timing is unobservable")
		_skip("Reduce Motion collapses the decorative flight",
			"no arc engaged in this run — timing is unobservable")
	else:
		# A/B against ITSELF, never against a literal: the pass is free to retune
		# the arc, but the Animation Speed setting must demonstrably move it.
		# Anything at or above 75% of the speed-1 time means the duration is a
		# bare float that the setting never reaches.
		_check(t_normal > 0.0 and t_fast <= t_normal * 0.75,
			"Animation Speed reaches the play flight (Instant must land the card materially sooner: %.3fs vs %.3fs)"
				% [t_fast, t_normal])
		# The flight is an ENTRANCE, and entrances are decorative by the house
		# contract — Reduce Motion gates them off and snaps to the end state. The
		# CONTENT (the card in its slot) must still land, which the checks below
		# assert independently of how the motion was gated.
		_check(t_normal > 0.0 and t_rm <= t_normal * 0.6,
			"Reduce Motion collapses the decorative flight (%.3fs vs %.3fs)"
				% [t_rm, t_normal])
	_check(is_instance_valid(card) and _seated_in(card, _combat.ROW_FRONT, 3),
		"Reduce Motion still LANDS the content — the card is seated in its slot")
	if is_instance_valid(card):
		_check(int(card.z_index) == 0,
			"Reduce Motion still returns z_index to 0 (got %d)" % int(card.z_index))
		_check(not _on_hud_layer(card),
			"Reduce Motion never leaves the card on the HUD layer")


## Wall-clock the whole gesture: from the call until the card is back under a
## real parent at z 0. Deliberately measures the OBSERVABLE round trip rather
## than reading a duration out of the source, so it survives a rewrite.
func _timed_flight(card: Control, from: Vector2) -> float:
	if not is_instance_valid(card):
		return 0.0
	var parent_before: Node = card.get_parent()
	var t0: int = Time.get_ticks_usec()
	_combat._play_landing_pop(card, from, true)
	var frames := 0
	while frames < 3000:
		await get_tree().process_frame
		frames += 1
		if not is_instance_valid(card):
			break
		# `_play_landing_pop` yields one frame before it does anything, so give it
		# two before believing "already finished".
		if frames >= 2 and card.get_parent() == parent_before and int(card.z_index) == 0:
			break
	return float(Time.get_ticks_usec() - t0) / 1_000_000.0


## Diagnostic only — points the fixing agent straight at the line. The CHECK is
## the measured A/B above; this just says whether the body ever asks the clock.
func _flight_body_scales_its_clock() -> bool:
	var src: String = load("res://scripts/scenes/Combat.gd").source_code
	var start: int = src.find("func _play_landing_pop")
	if start < 0:
		return false
	var stop: int = src.find("\nfunc ", start + 1)
	if stop < 0:
		stop = src.length()
	var body: String = src.substr(start, stop - start)
	return body.contains("Motion.time(") or body.contains("anim_time(")


# ═══════════════════════════════════════════════════════════════════════════
#  E. ROTATION — exactly one writer
# ═══════════════════════════════════════════════════════════════════════════

func _check_rotation_ownership() -> void:
	print("[card_play] -- E. Card2D.rotation keeps exactly one writer --")

	# ── E1: no UNDECLARED tween may write `self.rotation` ────────────────────
	# The lean driver owns rotation every frame while a hand card is dragged or
	# hovered. A tween started in that window is a second writer and the two
	# fight visibly (the card judders, or snaps back mid-drag). Rather than try
	# to catch that race at runtime, pin the SET of functions allowed to tween
	# rotation at all: each one below is either drag-guarded or unreachable from
	# a hand card. A new one has to be added here on purpose.
	var src: String = load("res://scripts/Card2D.gd").source_code
	var lines: PackedStringArray = src.split("\n")
	var current_fn := "<file scope>"
	var offenders: Array[String] = []
	var seen: Dictionary = {}
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.begins_with("func "):
			current_fn = line.substr(5).split("(")[0].strip_edges()
		if not line.contains("\"rotation\""):
			continue
		if not (line.contains("tween_property") or line.contains("tween_method")):
			continue
		seen[current_fn] = true
		if not ROTATION_TWEEN_OWNERS.has(current_fn):
			offenders.append("%s (line %d)" % [current_fn, i + 1])
	print("  [diag] functions tweening rotation in Card2D: %s" % str(seen.keys()))
	_check(offenders.is_empty(),
		"no UNDECLARED rotation tween in Card2D — a second writer would fight the lean driver%s"
			% ("" if offenders.is_empty() else "; found " + ", ".join(offenders)))

	# ── E2: the runtime handoff ──────────────────────────────────────────────
	var card: Control = _bare_card()
	if card == null:
		_check(false, "fixture: a bare Card2D for the rotation checks")
		return
	var old_rm: bool = UserSettings.reduce_motion
	UserSettings.reduce_motion = false

	card.set_hand_target(Vector2(400, 700), 0.22, Vector2(0.8, 0.8))
	_check(card._hand_tween != null and card._hand_tween.is_valid(),
		"at rest the hand tween owns rotation")
	# `is_processing()` STOPPED BEING A PROXY FOR THE LEAN (▲3, 2026-09-02).
	# `_process` now carries two drivers on two channels — the lean owns
	# `rotation`, the reflow spring owns `position` — so the node legitimately
	# processes for ~0.17 s after any relayout. The contract these three checks
	# actually protect is "the LEAN is off, so the tweens own rotation", and that
	# is `_lean_active`. The frame-cost half is not dropped: it is asserted below
	# as "stands down once settled", which is the thing that was ever at risk.
	_check(not card._lean_active,
		"at rest the lean driver is OFF (the tweens own rotation)")

	card._start_drag(Vector2(400, 700))
	_check(card._hand_tween == null or not card._hand_tween.is_valid(),
		"the grab KILLS the hand tween — rotation has no tween writer during a drag")
	_check(card._hover_tween == null or not card._hover_tween.is_valid(),
		"the grab kills the hover tween too")
	_check(card._lean_active and card.is_processing(),
		"the grab arms the lean driver, which now owns rotation")

	# The two re-entry points that could arm a rotation tween mid-drag. A hand
	# relayout happens on every draw and every play, so this fires constantly in
	# a real fight; `_on_mouse_entered` fires whenever the cursor crosses another
	# card while a drag is live.
	card.set_hand_target(Vector2(500, 690), -0.18, Vector2(0.8, 0.8))
	_check(card._hand_tween == null or not card._hand_tween.is_valid(),
		"a hand relayout DURING a drag arms no rotation tween (set_hand_target is drag-guarded)")
	card._on_mouse_entered()
	_check(card._hover_tween == null or not card._hover_tween.is_valid(),
		"a hover DURING a drag arms no rotation tween (_on_mouse_entered is drag-guarded)")
	_check(card._lean_active,
		"...and the lean driver still holds the rotation baton")

	# ── E3: the HANDOFF ORDER that makes the refusal beat legal ──────────────
	# `play_return_to_hand` tweens rotation, and it is only safe because a refusal
	# can never reach a card whose lean is still armed: `_end_drag` disarms the
	# driver BEFORE it emits `played`, so the baton has changed hands by the time
	# Combat can say no. Asserted from inside the signal, which is the only place
	# that ordering is observable.
	var committed := _bare_card()
	if committed != null:
		committed.set_hand_target(Vector2(400, 700), 0.22, Vector2(0.8, 0.8))
		var lean_at_emit := [true, true]
		committed.played.connect(func():
			lean_at_emit[0] = bool(committed._lean_active)
			lean_at_emit[1] = bool(committed._is_being_dragged))
		committed._start_drag(Vector2(400, 700))
		committed.global_position = Vector2(400, 40)   # well above the play threshold
		committed._end_drag()
		_check(not lean_at_emit[0],
			"the lean driver is ALREADY disarmed when `played` fires (this is what makes the refusal beat's rotation tween legal)")
		_check(not lean_at_emit[1],
			"_is_being_dragged is already false when `played` fires")
		committed.queue_free()

	# Releasing over the hand cancels the play: the driver must let go and the
	# card must be restored to its fan pose, with rotation handed back cleanly.
	card.global_position = Vector2(400, 10_000)   # far below the play threshold
	card._end_drag()
	_check(not card._lean_active,
		"the release DISARMS the lean driver — the tweens own rotation again")
	_check(is_equal_approx(card.rotation, card._hand_target_rotation),
		"a cancelled drag restores the fan rotation exactly (%.4f vs %.4f)"
			% [card.rotation, card._hand_target_rotation])

	# ── E4: swapping the pivot must not MOVE the card ────────────────────────
	# The gesture changes pivot twice — the grab centres it, the return-to-hand
	# puts it back at bottom-centre — and a Control's `position` is measured from
	# its origin while its transform is built around the pivot. Change one without
	# compensating the other and the card TELEPORTS by up to half its size in a
	# single frame, which is what a rejected drop and a discard flight both used
	# to do. Asserted on a card wearing a real scale AND rotation, because at
	# scale 1 / rotation 0 the compensation term is zero and the bug hides.
	var pivoted := _bare_card()
	if pivoted != null:
		pivoted.position = Vector2(300, 500)
		pivoted.scale = Vector2(0.85, 0.85)
		pivoted.rotation = 0.21
		pivoted.pivot_offset = pivoted.size * 0.5
		var probe_pt := Vector2(17.0, 43.0)   # any point that is not the pivot
		var before: Vector2 = pivoted.get_global_transform() * probe_pt
		pivoted._repivot_preserving_pose(Vector2(pivoted.size.x * 0.5, pivoted.size.y))
		var after: Vector2 = pivoted.get_global_transform() * probe_pt
		_check(before.distance_to(after) < 0.5,
			"_repivot_preserving_pose moves the pivot WITHOUT moving the card on screen (drift %.2f px)"
				% before.distance_to(after))
		pivoted.queue_free()

	# Reduce Motion: the lean is decorative and must never arm, but rotation must
	# still have an owner — the card may not be left mid-lean with no driver.
	UserSettings.reduce_motion = true
	var rigid: Control = _bare_card()
	if rigid != null:
		rigid.set_hand_target(Vector2(400, 700), 0.22, Vector2(0.8, 0.8))
		rigid._start_drag(Vector2(400, 700))
		_check(not rigid._lean_active,
			"Reduce Motion never arms the lean driver")
		# The frame-cost guarantee, kept honest: whatever drivers ran, the card
		# must go quiet on its own rather than processing for the rest of the run.
		await _settle(rigid, 0.6)
		_check(not rigid.is_processing(),
			"and every driver stands down once settled (no permanent frame cost)")
		_check(is_equal_approx(rigid.rotation, 0.0),
			"Reduce Motion leaves the grabbed card straight (rotation %.4f)" % rigid.rotation)
		rigid.queue_free()
	UserSettings.reduce_motion = old_rm   # direct restore, never saved
	card.queue_free()


func _bare_card() -> Control:
	var scene: PackedScene = load("res://scenes/card_2d.tscn")
	if scene == null:
		return null
	var c = scene.instantiate()
	c.card_id = FIXTURE_CARD
	c.card_data = CardDB.get_card_data(FIXTURE_CARD)
	add_child(c)
	return c


# ═══════════════════════════════════════════════════════════════════════════
#  SHARED
# ═══════════════════════════════════════════════════════════════════════════

## Watch the first frames of a flight for the LIFT — the moment the card is
## detached onto the HUD layer at z 200. Returns true if it was seen. Used to
## time the interruption test, and reported as a diagnostic so a run where the
## arc never engaged is legible rather than a mystery pass.
##
## SHORT and deliberate: the lift happens one frame after the call, so a long
## wait here would sail past it into the settled end state (the settle trap).
func _watch_for_lift(card: Control) -> bool:
	for _i in range(12):
		await get_tree().process_frame
		if not is_instance_valid(card):
			return false
		if _on_hud_layer(card) or int(card.z_index) > 0:
			return true
	return false


## Wait out whatever tween is carrying a REFUSED card back into the fan. Polls
## `_hand_tween` rather than sleeping a fixed amount, so retuning REFUSAL_BEAT
## (or replacing the beat entirely) does not touch this file.
func _settle_hand(card: Control, seconds: float = 2.5) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	# Give the refusal a frame to arm its tween before believing "already done".
	await get_tree().process_frame
	await get_tree().process_frame
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(card):
			return
		var tw = card._hand_tween
		if tw == null or not tw.is_valid() or not tw.is_running():
			return
		await get_tree().process_frame


## Let the gesture finish on REAL frames. Never a fixed sleep sized to today's
## duration — poll the end state, with a hard ceiling so no path can hang.
func _settle(card: Control, seconds: float = 2.0) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var quiet := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_instance_valid(card):
			return
		if int(card.z_index) == 0 and not _on_hud_layer(card):
			quiet += 1
			if quiet >= 8:
				return
		else:
			quiet = 0


## Wait until the card has stopped MOVING, not merely stopped flying.
##
## THE SETTLE TRAP, inverted. The shot scripts get burned by waiting too long and
## photographing the settled state; a probe gets burned the other way — the wax
## press is still tweening `scale` for ~0.24s after the card is back in its cell,
## so a rest value read at `_settle` time is a mid-tween number and every later
## scale comparison is noise. Detection is EXACT equality across consecutive
## frames (a live tween writes a different float every frame), plus a floor on
## elapsed time so a tween that has not started yet cannot read as "finished".
func _quiesce(card: Control, seconds: float = 3.0) -> void:
	await _settle(card, seconds)
	if not is_instance_valid(card):
		return
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var floor_ms: int = Time.get_ticks_msec() + 320
	var last_scale: Vector2 = card.scale
	var last_pos: Vector2 = card.global_position
	var still := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_instance_valid(card):
			return
		if card.scale == last_scale and card.global_position == last_pos:
			still += 1
			if still >= 10 and Time.get_ticks_msec() >= floor_ms:
				return
		else:
			still = 0
		last_scale = card.scale
		last_pos = card.global_position
