extends SceneTree
## ══════════════════════════════════════════════════════════════════════════
##  THE DEPLOYMENT CURVE — how many bodies each side has, round by round.
##  A DELIBERATE FORK of _probe_autorun.gd (2026-09-16). Read this first.
## ══════════════════════════════════════════════════════════════════════════
##
## WHY IT EXISTS. The economy redesign (docs/ECONOMY_REDESIGN_20260916.md §3)
## changed what the player can field per round, and nothing in the harness could
## see whether the ENEMY still matched it. Win rate cannot answer that question:
## _probe_autorun is ~77% deck-insensitive and loses every elite and boss
## regardless of balance, so a two-body tempo swing reads as no change at all —
## measured, the §3a before/after moved overall win rate 33% -> 33% while the
## player's round-2 board went from 0.43 bodies against 2.47 to 0.50 against 1.73.
## A measurement whose instrument cannot resolve the effect is not a measurement.
##
## WHAT IT CHANGES vs its parent, and that is ALL it changes:
##   1. plain combats only (elites/bosses carry authored kits and phase scripts,
##      so pooling them measures the author, not the drip),
##   2. a board census at the TOP of each player turn, before the pilot acts,
##   3. a summary table instead of a win/loss tally.
##
## IT IS A FORK, NOT AN INDEPENDENT PROBE. It shares its parent's boot, teardown,
## polling and auto-pilot verbatim, so it inherits every caveat in that file's
## header — including that the pilot is deliberately dumb. It measures DEPLOYMENT,
## which the pilot's poor play does not bias (both arms play equally badly), and
## it certifies nothing about whether a deck is good. If _probe_autorun changes
## materially, re-fork rather than patch. Folding this into the parent behind a
## `--deploy` flag would be strictly better and is the obvious next step.
##
## Run: <godot> --headless --path "D:\Godot" --script res://tools/_probe_deploy_curve.gd -- --seed=7001
##
## ── the parent's own header follows ───────────────────────────────────────
## Auto-play combat harness — stability hardening (2026-06-17).
##
## ══════════════════════════════════════════════════════════════════════════
##  EVERY PER-HERO WIN RATE THIS HARNESS PRINTED BEFORE 2026-07-28 IS VOID.
## ══════════════════════════════════════════════════════════════════════════
## The encounter list is sorted alphabetically and the hero was picked with
## `HEROES[i % HEROES.size()]`. Each encounter was therefore ALWAYS fought by
## the same hero: hero identity and encounter difficulty were not merely
## correlated, they were literally the same variable, and no sample size could
## separate them. The Kindler's stripe (indices = 4 mod 5) contained ZERO act-1
## plain combats — which is where essentially all bot wins come from — plus two
## fights that switch a Doom deck's win condition off outright (kings_body zeroes
## damage_enemy_hero; rival_stalwart soaks face damage into a siege gate). That
## is the whole of the famous "the Kindler wins 0" finding.
##
## The seed was hardcoded to 4242 as well, and Combat._combat_seed() derives the
## entire combat RNG stream from it, so repeated runs were the SAME run — not
## replicates.
##
## Both are fixed. `--rotate=N` decouples hero from encounter, `--hero=<id>` runs
## one hero against the WHOLE table (the only measurement that can rank heroes),
## and `--seed=N` makes replicates real. The summary now prints a per-hero AND
## per-act breakdown plus the seed, so this class of confound announces itself.
## The default still deals all 56 encounters across all 5 heroes, because the
## probe's primary job is crash/softlock detection, not balance.
##
## To actually compare heroes (5 passes, one per hero, varying the seed):
##   for h in raider stalwart acolyte pyromancer kindler; do
##     Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_autorun.gd \
##       -- --hero=$h --seed=$RANDOM
##   done
##
## Boots the REAL campaign combat scene headless and auto-plays each EncounterDB
## fight to a win/loss, catching runtime crashes and softlocks that the parse-check
## and logic probes can't. Uses a rotating hero per fight so every starter deck is
## exercised. The auto-pilot is deliberately dumb: each turn it plays every
## affordable creature into the first empty slot and every affordable spell — the
## targeted ones onto an auto-picked body (see below) — then ends
## the turn — which hammers on-enter/on-play effects, the clash resolver, keywords,
## passives, deaths/on-death, reinforcements, escalation, and boss/reactive passives
## across the whole encounter table.
##
## Headless notes:
##   - Combat._prebake_hand_textures() now early-returns headless, so _ready runs to
##     _start_round() instead of parking on the texture bake.
##   - anim_speed is forced to max so _short_pause collapses to one frame (fast runs);
##     end-turn warning is disabled so _on_end_turn never opens a modal.
##   - Starter decks contain no Discover/Choose/Copy cards, so no on-play modal can
##     stall the auto-pilot. (Reward-drafted cards are NOT added in this probe.)
##
## TARGETED SPELLS (2026-07-28). The pilot used to play only `targeting: "none"`
## spells, because a targeted one waits for a mouse click that headless can never
## deliver. That made every targeted card a BLANK: drawn, held, never cast. It is
## not a small hole — 33 of the 76 draftable spells are targeted, and all seven of
## the hero-retinue signature spells are, so the harness was measuring five decks
## with their identity cards switched off. The pilot now picks the target itself
## (Combat._auto_target_for, the same helper Chaos Imp / Echo use) and calls the
## same Combat._finish_targeted_spell() the click funnel calls. Rules it obeys:
##   - It asks Combat._target_contract_available() FIRST and skips a spell with no
##     legal target, so a cast is never forced into an empty board.
##   - It re-validates the picked bodies after the cast is armed and CANCELS
##     (the right-click path) rather than resolving onto a stale node.
##   - The cast is fired un-awaited and then POLLED with a tick budget
##     (CAST_WAIT_TICKS). A resolver that parks — an ungated modal, an await that
##     never returns — is reported as a cast stall and fails the probe instead of
##     hanging the run forever. That budget is the only thing standing between
##     this probe and an unkillable CI job, so don't remove it.
## Every modal a spell resolver can reach (_show_discover / _build_discover_overlay
## / _show_discard_picker / _show_recycle_modal / _pick_combat_option /
## _pick_empty_slot_any) self-resolves under headless. The ONE that does not is
## _pick_friendly_creature, and it is unreachable from a spell — Deserter's on-play
## branches around it headless, and _show_copy_friendly_picker is an on_enter whose
## cards (copycat / doppelganger) are on MODAL_BLOCKLIST. If a new card breaks that,
## the right fix is a headless branch in the game or a MODAL_BLOCKLIST entry — never
## a silent re-blocking of a card the game actually ships.
##
## Detection: a per-fight marker is printed before/after each fight. Capture stdout+
## stderr and scan for "SCRIPT ERROR"/"Invalid call" between markers to attribute a
## crash to its fight. The probe itself reports softlocks (a fight that never ends).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_autorun.gd
##
## THIS PROBE WRITES TO THE REAL USER DIR (start_new_run saves run_0.save, and
## MetaState writes meta.save) — an unguarded run overwrites the player's save.
## On Windows, Godot's user dir is derived from %APPDATA%, so the way to isolate a
## run is to override THAT for the process; GODOT_USER_HOME is a Unix-only variable
## and is silently ignored here, which makes it look isolated when it is not:
##   APPDATA=/some/scratch/dir Godot.exe --headless --path "D:\Godot" --script ...
##
## Optional flags (after a BARE `--`, which is what routes them to user args):
##   --pool=N     cards injected from the draftable pool per fight (default 16).
##   --relics=N   rotating relics granted per fight (default 3).
##   --limit=N    smoke run: fight only the first N encounters (never for balance).
##   --trace      print one line per card played, so an engine error with no script
##                backtrace can be attributed to the card that caused it.
##   --hero=<id>  fight EVERY encounter with ONE hero (raider / stalwart /
##                acolyte / pyromancer / kindler). This is the only setting whose
##                per-hero number is comparable to another hero's — see the
##                confound note at the top of this file.
##   --rotate=N   shift the default hero rotation by N. Sweeping N over 0..4
##                gives five runs in which every hero meets every encounter, at
##                one fifth the cost of five --hero passes.
##   --seed=N     run seed (default 4242, the historical value).
##                Combat._combat_seed() derives the whole combat RNG stream from
##                it, so two runs at the same seed are ONE sample, not two.
## `--pool=0 --relics=0` is DECK-COMPARISON mode: the hero's ten cards are the whole
## deck, which is the only way an A/B of HeroDB measures the decks rather than the
## injection. It also suppresses the fights-1-2 board-verb guarantee, which is six
## more pool cards. It is NOT the default and must not become one: the injection is
## how this probe gets a crash-test pass over the whole card pool, which is the job
## it actually exists to do.
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_autorun.gd -- --pool=0 --relics=0

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const MAX_ROUNDS := 40          # a fight that runs past this is treated as a softlock
const TURN_WAIT_TICKS := 80     # ~8s of 0.1s polls waiting for the next player turn
const CAST_WAIT_TICKS := 60     # ~6s budget for ONE targeted cast to finish resolving
const TICK := 0.1
# Hand-settle poll (see _settle_hand). SETTLE_TICK * HAND_STABLE_TICKS must exceed
# Combat._start_round's 0.08s stagger between draws, or "stable" just means "I
# polled inside one gap". 0.15s is a 1.9x margin; the budget is ~1.2s.
const SETTLE_TICK := 0.03
const HAND_STABLE_TICKS := 5
const HAND_SETTLE_TICKS := 40
# Cards whose on-enter/on-play opens a modal picker (Discover / Choose / Copy) or
# casts into one — playing these headless would stall waiting for a click, so the
# auto-pilot draws them (exercising the deck path) but never plays them.
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp"]
# Relics that open a picker/modal the headless auto-pilot can't dismiss (legit in a
# real game — there's a player to click). Mime opens an end-of-turn battlecry picker.
const RELIC_BLOCKLIST := ["mime"]
const POOL_WINDOW := 16         # how many pool cards to inject per fight (rotates)
const RELICS_PER_FIGHT := 3     # how many rotating relics to grant per fight
const DEFAULT_SEED := 4242      # historical value; --seed=N overrides (see header)

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var CDB: Node
var RDB: Node
var combat: Node
var _pool: Array = []
var _relic_ids: Array = []

var _started := false
var _done := false
var _fights := 0
var _wins := 0
var _losses := 0
var _stuck: Array = []
var _bail := false
var _teardown_failures: Array[String] = []
var _last_post_teardown_memory := -1

# Targeted-cast coverage bookkeeping (printed in the summary so a run can PROVE
# it saw the targeted half of the card pool rather than quietly skipping it).
var _casts_done := 0
var _cast_skipped := 0
var _cast_cancelled := 0
var _cast_stalls: Array[String] = []
var _cast_token := 0
var _cast_done_token := -1

# CLI-overridable injection knobs; defaults are the constants above.
var _pool_window := POOL_WINDOW
var _relics_per_fight := RELICS_PER_FIGHT
var _encounter_limit := 0       # 0 = every encounter (the only honest setting)
var _trace := false             # --trace: log every card the pilot plays
var _hero_filter := ""          # --hero=<id>: one hero fights the whole table
var _hero_rotate := 0           # --rotate=N: shift the default hero rotation
var _run_seed := DEFAULT_SEED   # --seed=N: run seed (see the header)

# Per-hero and per-act tallies. The confound this harness shipped with was
# invisible precisely because the summary reported ONE number, so the breakdown
# is not optional decoration — it is the thing that makes the next confound
# announce itself. Keys: hero id / act int; values {"w": int, "l": int}.
var _by_hero: Dictionary = {}
var _by_act: Dictionary = {}
var _by_hero_act: Dictionary = {}


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _parse_args() -> void:
	## Reads the user args (everything after a bare `--`). Anything unrecognised is
	## ignored on purpose — this probe shares a command line with Godot's own flags.
	for a in OS.get_cmdline_user_args():
		var arg := String(a)
		if arg.begins_with("--pool="):
			_pool_window = maxi(0, int(arg.substr(7)))
		elif arg.begins_with("--relics="):
			_relics_per_fight = maxi(0, int(arg.substr(9)))
		elif arg == "--trace":
			# Prints one line per card the pilot plays. Godot's engine-level
			# errors (a freed lambda capture, an invalid index inside a tween
			# callback) arrive with NO script backtrace, so the only way to
			# attribute one to a card is to have the play printed immediately
			# before it in the same log.
			_trace = true
		elif arg.begins_with("--limit="):
			# Smoke-test escape hatch: fight only the first N encounters. Never
			# use it for a balance number — the table is alphabetical, so a
			# limited run is an act-1-heavy slice, not a sample.
			_encounter_limit = maxi(0, int(arg.substr(8)))
		elif arg.begins_with("--hero="):
			# One hero, the whole encounter table. See the confound note at the
			# top: this is the ONLY mode whose per-hero win rate can be compared
			# with another hero's, because it is the only one in which two heroes
			# are dealt the same fights.
			var want := arg.substr(7).strip_edges().to_lower()
			if want in HEROES:
				_hero_filter = want
			else:
				printerr("[autorun] --hero=%s is not a hero id; ignoring (have: %s)"
					% [want, str(HEROES)])
		elif arg.begins_with("--rotate="):
			_hero_rotate = posmod(int(arg.substr(9)), HEROES.size())
		elif arg.begins_with("--seed="):
			_run_seed = int(arg.substr(7))
	if _hero_filter != "":
		print("[autorun] --hero=%s: ONE hero fights all encounters (comparable mode)"
			% _hero_filter)
	elif _hero_rotate != 0:
		print("[autorun] --rotate=%d: hero rotation shifted" % _hero_rotate)
	if _pool_window != POOL_WINDOW or _relics_per_fight != RELICS_PER_FIGHT:
		print("[autorun] injection overridden: pool=%d relics=%d%s" % [
			_pool_window, _relics_per_fight,
			"  (DECK-COMPARISON MODE: hero deck only)" if _pool_window == 0 else ""])


func _run() -> void:
	print("[autorun] start")
	_parse_args()
	_log_memory("start")
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	SS  = root.get_node_or_null("SkirmishState")
	NM  = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null:
		print("[autorun] FATAL: autoloads missing (RunState/EncounterDB)")
		await _finish(1)
		return
	# Speed pauses to ~0 and never pop the end-turn warning modal.
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	# Make sure no stale skirmish state routes combat into a net path.
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()
	# Build the full draftable card pool + relic id list for stress coverage.
	CDB = root.get_node_or_null("CardDB")
	RDB = root.get_node_or_null("RelicDB")
	if CDB != null:
		for id in CDB.CARD_POOL.keys():
			var d: Dictionary = CDB.CARD_POOL[id]
			if String(d.get("type", "")) in ["creature", "spell"] \
					and String(d.get("rarity", "")) != "enemy" and not CDB.is_curse(String(id)):
				_pool.append(String(id))
		_pool.sort()
	if RDB != null:
		for rid in RDB.RELICS.keys():
			_relic_ids.append(String(rid))
		_relic_ids.sort()
	print("[autorun] pool=%d draftable cards, %d relics" % [_pool.size(), _relic_ids.size()])

	var enc_ids: Array = []
	for id in EDB.ENCOUNTERS.keys():
		# Deployment curve: ordinary holds only. Elites/bosses carry authored
		# kits, phase scripts and reactive passives, so including them measures
		# the author rather than the drip this change touches — and every one of
		# them loses in this harness regardless of balance anyway.
		if String(EDB.ENCOUNTERS[id].get("type", "combat")) != "combat":
			continue
		if String(id).begins_with("rival_") or String(id).begins_with("amalgam_"):
			continue
		enc_ids.append(String(id))
	enc_ids.sort()
	if _encounter_limit > 0 and _encounter_limit < enc_ids.size():
		enc_ids = enc_ids.slice(0, _encounter_limit)
		print("[autorun] --limit: SMOKE RUN, first %d encounters only" % enc_ids.size())
	print("[autorun] %d encounters to fight" % enc_ids.size())

	for i in enc_ids.size():
		if _bail:
			break
		# Hero assignment. `HEROES[i % HEROES.size()]` over an ALPHABETICALLY
		# SORTED encounter list is what pinned each encounter to exactly one hero
		# forever — hero and encounter difficulty were the same variable. --hero
		# runs one hero against all of them (comparable); --rotate shifts the
		# stripe so a sweep of 0..4 covers every hero x encounter pair.
		var hero: String = _hero_filter if _hero_filter != "" \
			else HEROES[(i + _hero_rotate) % HEROES.size()]
		await _fight(i + 1, enc_ids.size(), hero, enc_ids[i])

	print("[autorun] ============ SUMMARY ============")
	print("[autorun] seed       : %d   heroes: %s" % [
		_run_seed, _hero_filter if _hero_filter != "" \
			else "rotating(+%d)" % _hero_rotate])
	print("[autorun] fights run : %d" % _fights)
	print("[autorun] wins/losses: %d / %d" % [_wins, _losses])
	_print_breakdown()
	print("[autorun] softlocks  : %d %s" % [_stuck.size(), str(_stuck)])
	print("[autorun] teardown   : %d %s" % [_teardown_failures.size(), str(_teardown_failures)])
	print("[autorun] targeted   : %d cast / %d skipped (no legal target) / %d cancelled" % [
		_casts_done, _cast_skipped, _cast_cancelled])
	print("[autorun] caststalls : %d %s" % [_cast_stalls.size(), str(_cast_stalls)])
	print("[autorun] (scan the log above for SCRIPT ERROR / Invalid call to attribute crashes)")
	print("[autorun] DONE")
	await _finish(1 if not _stuck.is_empty() or not _teardown_failures.is_empty() \
		or not _cast_stalls.is_empty() else 0)


func _fight(n: int, total: int, hero: String, enc_id: String) -> void:
	var enc: Dictionary = EDB.get_encounter(enc_id)
	var etype: String = String(enc.get("type", "combat"))
	print("[autorun] >>> FIGHT %d/%d hero=%s enc=%s type=%s act=%d" % [
		n, total, hero, enc_id, etype, int(enc.get("act", 1))])
	_log_memory("pre-fight", enc_id)
	RS.start_new_run(hero, 0, _run_seed)
	RS.current_encounter_id = enc_id
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"
	# Stage the ACT the encounter was authored for. start_new_run leaves
	# current_act_idx at 0, so get_act() answers 1 for every fight and
	# EncounterDB._act_scale_creature rescales act-2/act-3 kits DOWN to act-1
	# strength (delta = 1 - enc.act, i.e. -2/-2 on every act-3 body) plus a
	# rescaled face. Without this line the harness measures a fight that the
	# game never actually deals.
	RS.current_act_idx = clampi(int(enc.get("act", 1)), 1, 3) - 1

	# Stress coverage on top of the hero's starter deck: guarantee the board-verb
	# cards in the first couple of fights, then a rotating window of the whole
	# draftable pool so every card gets drawn/played across the run; plus a few
	# rotating relics each fight to exercise relic hooks (reset per start_new_run).
	# --pool=0 is deck-comparison mode: the hero's ten cards ARE the deck, so the
	# board-verb guarantee (six more pool cards) goes with the injection.
	if n <= 2 and _pool_window > 0:
		for cid in ["pikeman", "pikeman", "harpy", "harpy", "lookout", "raven"]:
			RS.add_card(cid)
	for k in _pool_window:
		if _pool.size() > 0:
			RS.add_card(_pool[((n - 1) * _pool_window + k) % _pool.size()])
	for r in _relics_per_fight:
		if _relic_ids.size() > 0:
			var rid: String = _relic_ids[((n - 1) * _relics_per_fight + r) % _relic_ids.size()]
			if not (rid in RELIC_BLOCKLIST):
				RS.add_relic(rid)

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	_fights += 1

	# Wait for _ready to reach the first player turn (or an instant game-over).
	if not await _wait_for_player_turn():
		# never reached a player turn and not over -> stuck during boot/round 1
		_record_stuck(enc_id, "boot")
		await _teardown(enc_id)
		return

	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		# DEPLOYMENT SAMPLE — taken at the TOP of the player's turn, before the
		# pilot plays anything, so it reads the board each side actually brought
		# into this round. This is the measurement the win rate cannot make:
		# _probe_autorun is ~77% deck-insensitive and loses every elite and boss
		# regardless of balance, so it can show a tempo change as nothing at all.
		# The hand is staggered in; play only once it has all arrived (_settle_hand).
		await _settle_hand()
		if not is_instance_valid(combat):
			break
		_sample_board(int(combat.round_number), etype)
		var _r_now: int = int(combat.round_number)
		await _auto_play_turn()
		# UNSPENT COMMAND is the oracle for the pilot itself, not for the game.
		# Body count cannot tell a hold that out-deploys the player from a
		# PILOT that could not spend its turn — both read as a deficit. Sampled
		# after the turn is played and before it is ended, so it is exactly what
		# the player left on the table.
		if etype == "combat" and is_instance_valid(combat):
			_record_unspent(_r_now, int(combat.player_mana))
		if not is_instance_valid(combat):
			break
		# End the turn (bypass the warning; it's disabled anyway).
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		# Wait for the resolve/enemy/next-round chain to hand control back.
		if not await _wait_for_player_turn():
			break  # either game-over (loop cond catches it) or stuck (handled below)

	var act: int = clampi(int(enc.get("act", 1)), 1, 3)
	if is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER:
		if int(combat.enemy_hp) <= 0:
			_wins += 1
			_tally(hero, act, true)
			print("[autorun] <<< result=WIN  rounds=%d" % rounds)
		else:
			_losses += 1
			_tally(hero, act, false)
			print("[autorun] <<< result=LOSS rounds=%d" % rounds)
	elif rounds >= MAX_ROUNDS:
		_record_stuck(enc_id, "max_rounds")
	elif is_instance_valid(combat):
		_record_stuck(enc_id, "no_player_turn")
	await _teardown(enc_id)


## Poll until the scene is in PLAYER_TURN (ready for input) or GAME_OVER.
## Returns false only if it timed out in some other phase (potential softlock).
##
## `round_number >= 1` is NOT decoration, and dropping it costs the whole run:
## `Phase.PLAYER_TURN` is enum 0, which is also `phase`'s DEFAULT, so a freshly
## instantiated Combat reports "ready for input" on the very first poll — before
## _ready has built anything. That was survivable while the opening was one
## synchronous block. It stopped being survivable when the 2026-07-26 cold-open
## pass made the build INTERLEAVED (_build_hud is now a coroutine that hands the
## frame back): the probe began playing into a half-built scene, `_on_end_turn`
## hit a null `_end_turn_btn`, and every single encounter was reported as a
## max_rounds SOFTLOCK — 56 false failures that said nothing about the game.
## round_number is stamped by _start_round, so it is the first honest signal
## that the scene is actually live.
func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN and int(combat.round_number) >= 1:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round staggers the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` (Combat.gd ~4374).
## That stagger has no headless branch, no reduce_motion branch, and is NOT
## scaled by anim_speed — so `phase == PLAYER_TURN` is true while the hand is
## still one card, and a driver that starts there is playing a hand the game
## never dealt it.
##
## On ROUND 1 that was the entire measurement. draw_count is 5 and Command is 1,
## so if the one card that arrived in time cost 2+, the pass played nothing and
## returned — and the probe reported a dead opening turn (0.00 bodies, 0.90 of
## 1.0 Command unspent) that no human player has ever had. Later rounds hid it:
## the hand is PERSISTENT, so from round 2 on it carries unplayed stock forward
## and is never down to the single synchronous draw.
##
## Stability polling, not a computed deal window: draw_count is decided by the
## ramp plus four relics plus two mutators, and restating that arithmetic here
## is the duplicate-rule pathology this codebase has already paid for twice.
## Bounded on purpose — an unbounded `while await` that never settles spins to
## the harness timeout and reports NOTHING, which is worse than a wrong number
## because it deletes the evidence.
func _settle_hand() -> void:
	var last := -1
	var stable := 0
	var waited := 0
	while waited < HAND_SETTLE_TICKS:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= HAND_STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _auto_play_turn() -> void:
	# Several passes, since playing a card can grant Command (ramp) and open more plays.
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var played_any := false
		# DESCENDING COST, not deal order (2026-09-16). Under the old curve, where
		# 86% of the pool cost <= 2, scan order barely mattered — almost everything
		# in hand was affordable. Under the rescaled 1-6 curve it decides the turn:
		# a deal-order scan spends 2 Command on the first card it meets and then
		# cannot afford the 4-drop behind it, so the pilot STRANDS Command and the
		# probe reports a tempo deficit it manufactured itself.
		#
		# Biggest-affordable-first, then top up with whatever still fits, is the
		# greedy that maximises Command SPENT. That target is chosen deliberately:
		# this probe measures BODY COUNT, and cheapest-first would maximise exactly
		# that — a thumb on the scale of its own metric. Spending well is neutral
		# between one 4-drop and two 2-drops; deploying many bodies is not.
		#
		# The outer 4-pass loop already re-scans, so this needs no second pass.
		var by_cost: Array = combat._hand.duplicate()
		var cost_desc := func(a, b) -> bool:
			var ca := -1
			var cb := -1
			if is_instance_valid(a): ca = int(a.card_data.get("cost", 0))
			if is_instance_valid(b): cb = int(b.card_data.get("cost", 0))
			return ca > cb
		by_cost.sort_custom(cost_desc)
		for card in by_cost:
			if not is_instance_valid(card) or not (card in combat._hand):
				continue
			var cd: Dictionary = card.card_data
			# (Curses are harmless to "play" — a none-spell that wastes itself — so
			# we don't special-case them; playing one just exercises that path.)
			if String(cd.get("id", "")) in MODAL_BLOCKLIST:
				continue   # would open a picker and stall headless
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost:
				continue
			var ctype: String = String(cd.get("type", ""))
			if ctype == "creature":
				var slot = _find_empty_player_slot()
				if slot == null:
					continue
				card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
				_trace_play(cd, "creature")
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
			elif ctype == "spell":
				var targeting: String = String(cd.get("targeting", "none"))
				if targeting == "none":
					_trace_play(cd, "spell/none")
					combat._on_card_played(card)
					played_any = true
					await create_timer(0.03).timeout
				elif await _cast_targeted(card, targeting):
					played_any = true
					await create_timer(0.03).timeout
					if not is_instance_valid(combat) \
							or combat.phase != combat.Phase.PLAYER_TURN:
						return   # the cast finished the fight
		if not played_any:
			return


func _trace_play(cd: Dictionary, kind: String) -> void:
	if not _trace:
		return
	print("[autorun][play] r=%d cmd=%d %s id=%s" % [
		int(combat.round_number), int(combat.player_mana), kind,
		String(cd.get("id", "?"))])


## True if `c` is a body the real click funnel would accept as a spell target.
## Mirrors Combat._clicked_target_from's filter exactly — a dying body, an inert
## structure and an effect-immune body (the Old King's Body) all decline the click.
func _is_targetable(c) -> bool:
	return c != null and is_instance_valid(c) and int(c.current_hp) > 0 \
		and not c.is_inert_structure() and not combat._is_effect_immune(c)


func _legal(pool: Array) -> Array:
	return pool.filter(func(c): return _is_targetable(c))


## One body for a single-target mode. Combat._auto_target_for is the game's own
## picker and is tried first; it excludes every `structure`-keyworded body (even
## the `attackable` ones the click funnel accepts) and does not filter dying or
## effect-immune bodies, so its answer is validated and a plain scan backs it up.
func _pick_one(targeting: String):
	var t = combat._auto_target_for(targeting)
	if _is_targetable(t):
		return t
	var pool: Array = []
	match targeting:
		"enemy_creature":
			pool = combat._all_enemy_creatures()
		"friendly_creature":
			pool = combat._all_player_creatures()
		"any_creature", "any":
			pool = combat._all_enemy_creatures() + combat._all_player_creatures()
	for c in pool:
		if _is_targetable(c):
			return c
	return null


## Decides what this cast would click on, WITHOUT touching the board. Returns
## {} when there is nothing legal — the caller then skips the card entirely,
## so no Command is ever spent on a cast that has to be cancelled.
## Keys mirror Combat._finish_targeted_spell's parameters: target / lane / primary.
func _plan_target(targeting: String) -> Dictionary:
	match targeting:
		"enemy_creature", "friendly_creature", "any_creature":
			var t = _pick_one(targeting)
			if t == null:
				return {}
			return {"target": t, "lane": int(t.current_lane), "primary": null}
		"any":
			# Both outcomes the click funnel offers: a body if one stands,
			# otherwise the enemy face (the top-strip click, target = null).
			var t_any = _pick_one("any")
			if t_any != null:
				return {"target": t_any, "lane": int(t_any.current_lane), "primary": null}
			return {"target": null, "lane": -1, "primary": null}
		"lane":
			# Gallows Writ / Salted Ground mark a COLUMN. Prefer one an enemy is
			# standing in so the cast is doing something measurable.
			for row in [combat.ROW_FRONT, combat.ROW_BACK]:
				for lane in range(combat.LANES_PER_ROW):
					if combat._sp_lane_closed(lane):
						continue
					if _is_targetable(combat._row_array(true, row)[lane]):
						return {"target": null, "lane": lane, "primary": null}
			for open_lane in range(combat.LANES_PER_ROW):
				if not combat._sp_lane_closed(open_lane):
					return {"target": null, "lane": open_lane, "primary": null}
			return {}
		"friendly_then_enemy":
			var ally = _pick_one("friendly_creature")
			var foe = _pick_one("enemy_creature")
			if ally == null or foe == null:
				return {}
			return {"target": foe, "lane": int(foe.current_lane), "primary": ally}
		"two_enemies":
			var foes: Array = _legal(combat._all_enemy_creatures())
			if foes.size() < 2:
				return {}
			return {"target": foes[1], "lane": int(foes[1].current_lane),
				"primary": foes[0]}
		"friendly_lane":
			# A mover plus an EMPTY adjacent lane in its own row — the same
			# legality Combat._try_resolve_target enforces on the second click.
			for mover in _legal(combat._all_player_creatures()):
				for dest in [int(mover.current_lane) - 1, int(mover.current_lane) + 1]:
					if dest < 0 or dest >= combat.LANES_PER_ROW:
						continue
					if combat._sp_lane_closed(dest):
						continue
					if combat._row_array(false, int(mover.current_row))[dest] == null:
						return {"target": null, "lane": dest, "primary": mover}
			return {}
	return {}


## Casts one targeted spell. Returns true only if it actually resolved.
func _cast_targeted(card, targeting: String) -> bool:
	var cd: Dictionary = card.card_data
	# The game's own gate, asked BEFORE anything is spent. _on_card_played runs
	# the identical check and bounces the card back into the fan, but asking here
	# keeps "no legal target -> SKIP" an explicit promise rather than a side
	# effect, and it is what counts the skip.
	if not combat._target_contract_available(cd):
		_cast_skipped += 1
		return false
	var plan: Dictionary = _plan_target(targeting)
	if plan.is_empty():
		_cast_skipped += 1
		return false

	_trace_play(cd, "spell/" + targeting)
	combat._on_card_played(card)
	# The play can still be refused after the gate (Command, Velvet Choker, a
	# curse). Only a real arm parks THIS card in _targeting_spell.
	if not is_instance_valid(combat) or combat._targeting_spell != card:
		return false

	var tgt: Control = plan.get("target")
	var primary: Control = plan.get("primary")
	if (tgt != null and not _is_targetable(tgt)) \
			or (primary != null and not _is_targetable(primary)):
		combat._cancel_targeting()   # the right-click path: card back, Command back
		_cast_cancelled += 1
		return false

	# Fire un-awaited and poll with a budget. Awaiting directly would mean a
	# resolver that parks on an unclickable modal hangs the WHOLE run with no
	# diagnostic — MAX_ROUNDS / TURN_WAIT_TICKS only guard the turn loop, not
	# a coroutine stalled inside a cast.
	_cast_token += 1
	var token := _cast_token
	_run_cast(token, tgt, int(plan.get("lane", -1)), primary)
	var waited := 0
	while _cast_done_token != token and waited < CAST_WAIT_TICKS:
		if not is_instance_valid(combat):
			break
		await create_timer(TICK).timeout
		waited += 1
	if _cast_done_token != token and is_instance_valid(combat):
		var label := "%s(%s)" % [String(cd.get("id", "?")), targeting]
		printerr("[autorun] CAST-STALL %s: resolution did not finish in %.1fs" % [
			label, CAST_WAIT_TICKS * TICK])
		_cast_stalls.append(label)
		return false
	_casts_done += 1
	return true


## Wrapper so the cast can be fired without awaiting it and still be observed.
## _finish_targeted_spell is the same call Combat._try_resolve_target makes once
## the player has clicked, so this is the shipped resolution path, not a shortcut.
func _run_cast(token: int, tgt: Control, lane: int, primary: Control) -> void:
	await combat._finish_targeted_spell(tgt, lane, primary)
	_cast_done_token = token


func _find_empty_player_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## Book one decided fight against hero, act, and the pair.
func _tally(hero: String, act: int, won: bool) -> void:
	for bucket in [[_by_hero, hero], [_by_act, act], [_by_hero_act, "%s/a%d" % [hero, act]]]:
		var d: Dictionary = bucket[0]
		var k = bucket[1]
		if not d.has(k):
			d[k] = {"w": 0, "l": 0}
		d[k]["w" if won else "l"] += 1


func _rate_line(label: String, rec: Dictionary) -> String:
	var w: int = int(rec.get("w", 0))
	var l: int = int(rec.get("l", 0))
	var n: int = w + l
	return "%-16s %3d W / %3d L   %5.1f%%  (n=%d)" % [
		label, w, l, (100.0 * float(w) / float(n)) if n > 0 else 0.0, n]


## THE BREAKDOWN IS THE POINT. A single aggregate number is what let the
## hero/encounter confound live in this file undetected: any per-hero spread it
## produced was really a per-ENCOUNTER spread wearing a hero's name. Printing the
## per-act split beside it makes that visible — in a rotating or --hero run the
## act columns should be comparable across heroes; if they are not, the slate is
## still doing the talking.
func _print_breakdown() -> void:
	if _by_hero.is_empty():
		return
	print("[autorun] ---- per hero ----")
	for h in HEROES:
		if _by_hero.has(h):
			print("[autorun]   " + _rate_line(h, _by_hero[h]))
	print("[autorun] ---- per act ----")
	for a in [1, 2, 3]:
		if _by_act.has(a):
			print("[autorun]   " + _rate_line("act %d" % a, _by_act[a]))
	print("[autorun] ---- hero x act ----")
	for h in HEROES:
		for a in [1, 2, 3]:
			var k := "%s/a%d" % [h, a]
			if _by_hero_act.has(k):
				print("[autorun]   " + _rate_line(k, _by_hero_act[k]))
	if _hero_filter == "":
		print("[autorun] NOTE: heroes rotate over an ALPHABETICAL encounter list, so a")
		print("[autorun]       single run still deals each hero a DIFFERENT slate. Per-hero")
		print("[autorun]       rates below are NOT comparable across heroes unless you")
		print("[autorun]       sweep --rotate=0..4 or run --hero=<id> five times.")


func _record_stuck(enc_id: String, why: String) -> void:
	print("[autorun] <<< result=STUCK (%s) enc=%s" % [why, enc_id])
	_stuck.append("%s:%s" % [enc_id, why])


func _memory_mib(bytes: int) -> float:
	return float(bytes) / (1024.0 * 1024.0)


func _log_memory(stage: String, enc_id: String = "") -> void:
	var current := OS.get_static_memory_usage()
	var peak := OS.get_static_memory_peak_usage()
	var delta := 0 if _last_post_teardown_memory < 0 else current - _last_post_teardown_memory
	print("[autorun][memory] stage=%s enc=%s static=%.1fMiB peak=%.1fMiB delta_from_last_post=%.1fMiB" % [
		stage,
		enc_id if not enc_id.is_empty() else "-",
		_memory_mib(current),
		_memory_mib(peak),
		_memory_mib(delta),
	])
	if stage == "post-teardown":
		_last_post_teardown_memory = current


## round -> {"p": total player bodies, "e": total enemy bodies,
##           "cmd": player max Command, "n": samples}
var _dep: Dictionary = {}


func _count_side(is_enemy: bool) -> int:
	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(is_enemy, row):
			if c != null and is_instance_valid(c):
				n += 1
	return n


## Unspent Command at the end of a player turn, per round. See the call site.
var _unspent: Dictionary = {}


func _record_unspent(r: int, left: int) -> void:
	if r < 1 or r > 8:
		return
	var row: Dictionary = _unspent.get(r, {"left": 0, "n": 0})
	row["left"] = int(row["left"]) + maxi(0, left)
	row["n"] = int(row["n"]) + 1
	_unspent[r] = row


func _sample_board(r: int, etype: String) -> void:
	if r < 1 or r > 8:
		return
	# Plain combats only. Elites and bosses carry authored kits and phase
	# scripts, so pooling them with ordinary holds measures the author, not the
	# deployment curve this change touches.
	if etype != "combat":
		return
	var row: Dictionary = _dep.get(r, {"p": 0, "e": 0, "cmd": 0, "n": 0})
	row["p"] = int(row["p"]) + _count_side(false)
	row["e"] = int(row["e"]) + _count_side(true)
	row["cmd"] = int(row["cmd"]) + int(combat.player_max_mana)
	row["n"] = int(row["n"]) + 1
	_dep[r] = row


func _print_deploy_curve() -> void:
	print("")
	print("[deploy] ── BODIES ON BOARD at the top of each player turn ──")
	print("[deploy] plain combats only; p=player bodies e=enemy bodies (means)")
	print("[deploy]  round   cmd     player    enemy     enemy-player   unspent  n")
	var rounds: Array = _dep.keys()
	rounds.sort()
	for r in rounds:
		var d: Dictionary = _dep[r]
		var n: float = float(d["n"])
		if n <= 0:
			continue
		var p: float = float(d["p"]) / n
		var e: float = float(d["e"]) / n
		var u: Dictionary = _unspent.get(r, {"left": 0, "n": 0})
		var un: float = -1.0
		if int(u["n"]) > 0:
			un = float(u["left"]) / float(u["n"])
		print("[deploy]   %-6d %-7.1f %-9.2f %-9.2f %+-14.2f %-8.2f %d" % [
			r, float(d["cmd"]) / n, p, e, e - p, un, int(d["n"])])
	print("")


func _teardown(enc_id: String = "") -> void:
	var doomed: WeakRef = null
	if is_instance_valid(combat):
		doomed = weakref(combat)
		combat.queue_free()
	combat = null
	# queue_free() is serviced at a frame boundary. Wait for two boundaries so a
	# stale combat root cannot silently accumulate across the encounter sweep.
	await process_frame
	await process_frame
	if doomed != null and doomed.get_ref() != null:
		var label := enc_id if not enc_id.is_empty() else "<unknown>"
		printerr("[autorun] TEARDOWN-FAIL enc=%s: combat root survived two frames" % label)
		_teardown_failures.append(label)
	_log_memory("post-teardown", enc_id)


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		await _teardown("<finish>")
	else:
		await process_frame
	_log_memory("finish")
	_print_deploy_curve()
	if code == 0:
		print("PROBE PASS: autorun")
	else:
		printerr("PROBE FAIL: autorun")
	_done = true
	quit(code)
