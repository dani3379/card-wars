extends SceneTree
## _probe_golden.gd — PASS 25 of docs/BUG_SWEEP_METHOD_20260829.md (class C25).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_golden.gd
##   ... --script res://tools/_probe_golden.gd -- --bless      (re-record the corpus)
##
## CHARACTERIZATION / GOLDEN MASTER — pin the behaviour, then notice it moving.
##
## Every gate in this suite encodes a property somebody chose. None of them can
## answer the question that actually matters when editing a 20,000-line combat file:
## **did this change alter anything I did not intend?** Approval testing is the
## standard answer for exactly this shape of codebase — no unit tests, one enormous
## module, and a hundred behaviours nobody has written down. Record what the game
## DOES over a fixed set of seeds, commit it, and let any future diff be the alarm.
##
## It does not certify the recorded behaviour is CORRECT. That is the whole trade:
## it costs nothing to record and it catches unintended change anywhere in the
## covered surface, which is more than any hand-written assertion can promise.
##
## Two things it checks TODAY, before any corpus exists:
##
##   · DETERMINISM WITHIN A PROCESS. The same seed run twice must produce the same
##     digest. `CombatOps` owns seeded gameplay randomness precisely so a match is
##     reproducible; nothing has ever tested that a whole MATCH is (C8 covers run
##     GENERATION only). A divergence here is a real bug: it means some gameplay
##     decision is reading unseeded global RNG.
##   · DETERMINISM ACROSS RUNS OF THE HARNESS, which is what makes a committed
##     corpus meaningful at all. A digest that will not reproduce cannot be a
##     baseline, so the corpus is only written once determinism is demonstrated.

const CORPUS := "res://tools/golden/combat_digests.json"

var SS: Node
var NM: Node
var US: Node
var RS: Node
var combat: Node
var CardCls

var _started := false
var _done := false
var _fails := 0
var _bless := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


## `bank` arms the carryover relic on the local slot.
##
## 2026-09-16: Command stopped carrying over by default — it is gated on a relic
## now — and the frugal scenario below exists SPECIFICALLY to keep
## MAX_BANKED_MANA load-bearing (a mutant halving it escaped this corpus once
## already, because nothing in it ever banked). Without the relic that scenario
## would have quietly gone back to proving nothing, and the C12 mutation check
## would have started reporting a gate that cannot fail as a gate that passed.
## The id comes off the instance rather than being spelled here, so a rename
## breaks the probe loudly instead of silently disarming it.
func _boot(seed_val: int, style: int, bank: bool = false) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = seed_val
	SS.vs_bot = true
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.battle_style = style
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	# Before add_child: the relic is read at the first _start_round, which runs
	# off _ready. NET_RELIC_POOL does not carry it — _has_relic reads the drafted
	# SLOT, not the pool, so this grants it the same way a campaign run would.
	if bank and not SS.local_slot().relics.has(combat.BANK_RELIC):
		SS.local_slot().relics.append(combat.BANK_RELIC)
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	var last := -1
	var stable := 0
	for _i in 30:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			return false
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 3:
			break
	return is_instance_valid(combat)


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## A DETERMINISTIC policy. Any randomness in the driver would make the digest
## irreproducible for reasons that have nothing to do with the game — so the
## decisions here are a fixed function of the hand's order.
## `frugal` deliberately spends as little as possible so Command CARRIES OVER.
## Without a scenario that banks, `MAX_BANKED_MANA` is never load-bearing and
## halving it changed no digest at all — a golden master only pins the behaviour
## its scenarios actually exercise, and that is its whole limitation. A corpus with
## narrow scenarios is worse than none, because it reads as coverage.
## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. A driver that starts there is playing a hand the
## game has not finished dealing it: on round 1 that is ONE card of five, and at
## Command 1 a single 2-drop means the whole turn plays nothing.
##
## Rounds 2+ hide it, because the hand is PERSISTENT and carries unplayed stock
## forward — so the fault is worst exactly where round-1 measurements live. It
## cost `_probe_deploy_curve` a published number before it was found; see
## CLAUDE.md's settle-until-stable note.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _play_turn(frugal: bool = false) -> void:
	if frugal:
		# One cheap card at most; the rest of the Command banks into next round.
		if is_instance_valid(combat):
			combat._net_on_done_placing()
			await create_timer(0.35).timeout
		return
	for _pass in 6:
		if not is_instance_valid(combat):
			return
		var played := false
		for card in combat._hand:
			if card == null or not is_instance_valid(card) or not card.is_creature():
				continue
			if combat._effective_cost(card) > combat.player_mana:
				continue
			var slot := _first_empty_slot()
			if slot == null:
				break
			card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
			combat._on_card_played(card)
			await create_timer(0.06).timeout
			played = true
			break
		if not played:
			break
	if is_instance_valid(combat):
		combat._net_on_done_placing()
		await create_timer(0.35).timeout


## The recorded behaviour of one match, as a stable string.
##
## DELIBERATELY EXCLUDES anything wall-clock or frame-count dependent. A digest that
## records timing is a digest that fails on a busy machine, and a flaky baseline
## gets deleted rather than investigated.
func _digest(seed_val: int, style: int) -> String:
	if not is_instance_valid(combat):
		return "<no combat>"
	var board: Array = []
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				board.append("%s:%s:%d/%d:r%dl%d" % [
					"foe" if is_enemy else "me",
					String(c.card_data.get("id", "?")),
					int(c.effective_atk()), int(c.current_hp), row, lane])
	board.sort()
	var hand: Array = []
	for c in combat._hand:
		if c != null and is_instance_valid(c):
			hand.append(String(c.card_data.get("id", "?")))
	hand.sort()
	return "seed=%d style=%d round=%d hp=%d/%d mana=%d/%d hand=[%s] board=[%s]" % [
		seed_val, style, int(combat.round_number),
		int(combat.player_hp), int(combat.enemy_hp),
		int(combat.player_mana), int(combat.player_max_mana),
		",".join(hand), ",".join(board)]


func _run_match(seed_val: int, style: int, turns: int, frugal: bool = false) -> String:
	# The frugal scenario is the ONLY one that banks, so it is the only one that
	# needs the relic that allows banking at all — see _boot.
	if not await _boot(seed_val, style, frugal):
		return "<boot failed>"
	var played := 0
	var stalls := 0
	while played < turns and is_instance_valid(combat) and not combat._net_match_over:
		var mine: bool
		if style == NM.STYLE_SEALED:
			mine = combat._sorcery_active == NM.local_player_index \
				or (combat._sorcery_active < 0 and not combat._sealed_await_foe \
					and combat.phase == combat.Phase.PLAYER_TURN)
		else:
			mine = combat._net_active_index == NM.local_player_index \
				and combat.phase == combat.Phase.PLAYER_TURN
		if not mine:
			stalls += 1
			if stalls > 400:
				break
			await create_timer(0.05).timeout
			continue
		stalls = 0
		played += 1
		await _settle_hand()
		await _play_turn(frugal)
	var d := _digest(seed_val, style)
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.3).timeout
	return d


func _load_corpus() -> Dictionary:
	if not FileAccess.file_exists(CORPUS):
		return {}
	var f := FileAccess.open(CORPUS, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _save_corpus(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://tools/golden"))
	var f := FileAccess.open(CORPUS, FileAccess.WRITE)
	if f == null:
		print("[golden] could not write %s" % CORPUS)
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	print("[golden] corpus written: %s (%d entries)" % [CORPUS, d.size()])


func _run() -> void:
	print("[golden] PASS 25 — pin the behaviour, then notice it moving\n")
	for a in OS.get_cmdline_user_args():
		if String(a) == "--bless":
			_bless = true
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	RS = root.get_node_or_null("RunState")
	if SS == null or NM == null:
		print("[golden] FATAL: autoloads missing"); _done = true; quit(1); return
	CardCls = load("res://scripts/Card2D.gd")
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	# ── 1. DETERMINISM: the same seed twice, in this process. ───────────────
	print("[golden] --- determinism: same seed, twice ---")
	var scenarios := [{"seed": 24601, "style": 0, "frugal": false},
		{"seed": 13579, "style": 1, "frugal": false},
		{"seed": 24601, "style": 0, "frugal": true}]
	var digests := {}
	for sc in scenarios:
		var key := "seed%d_style%d%s" % [int(sc["seed"]), int(sc["style"]),
			"_frugal" if bool(sc["frugal"]) else ""]
		var a := await _run_match(int(sc["seed"]), int(sc["style"]), 4,
			bool(sc["frugal"]))
		var b := await _run_match(int(sc["seed"]), int(sc["style"]), 4,
			bool(sc["frugal"]))
		digests[key] = a
		if a != b:
			print("        A: %s" % a)
			print("        B: %s" % b)
		_check(a == b, "%s reproduces exactly on a second run" % key)
		# VACUITY: two identical "<boot failed>" strings would satisfy the check
		# above while proving nothing at all.
		_check(a.find("<") < 0 and (bool(sc["frugal"]) or a.find("board=[]") < 0),
			"%s produced a real match to compare" % key)

	# ── 2. THE CORPUS. ──────────────────────────────────────────────────────
	var corpus := _load_corpus()
	if _bless or corpus.is_empty():
		if corpus.is_empty() and not _bless:
			print("\n[golden] no corpus yet — recording the current behaviour as the")
			print("[golden] baseline. It certifies nothing about correctness; from")
			print("[golden] here on, any DIFFERENCE is the signal.")
		_save_corpus(digests)
		for k in digests:
			print("        %s" % k)
			print("          %s" % digests[k])
	else:
		print("\n[golden] --- diffing against the committed corpus ---")
		var moved := 0
		for k in digests:
			if not corpus.has(k):
				print("  NOTE  %s is new (not in the corpus)" % k)
				continue
			if String(corpus[k]) == String(digests[k]):
				print("  PASS  %s unchanged" % k)
			else:
				moved += 1
				_fails += 1
				print("  FAIL  %s CHANGED" % k)
				print("        was: %s" % String(corpus[k]))
				print("        now: %s" % String(digests[k]))
		if moved > 0:
			print("\n[golden] A diff is not automatically a bug — it is an "
				+ "UNANNOUNCED CHANGE.\n[golden] If you meant it, re-record with "
				+ "`-- --bless`. If you did not, you have\n[golden] just found "
				+ "something no hand-written assertion was watching for.")

	print("\n[golden] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
