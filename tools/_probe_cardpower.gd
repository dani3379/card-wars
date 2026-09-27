extends SceneTree
## Per-CARD power sweep (2026-07-01). Isolates each draftable card's combat impact
## by STACKING it: deck = COPIES copies of the test card + goblin filler (10 total),
## run through a fixed 3-act gauntlet with the smart auto-pilot. Fights run to an
## ACTUAL death (a hero hits 0); MAX_ROUNDS only catches stalemates. Score per
## fight = HP MARGIN (player_hp - enemy_hp), BUT a finish at or below NEAR_DEATH_HP
## (4) takes a NEAR_DEATH_PENALTY (-15) — in a roguelike, dropping to 4 HP is a
## run-ender, so a crippling "win" scores as a loss, not like a clean one.
##
## Read it as an OUTLIER detector: cards far ABOVE the pack are over-strong; cards
## near or below the 10-goblin BASELINE are under-strong (literally no better than
## filling your deck with 1/2 goblins). Confounds to keep in mind: high-cost cards
## lose a little to curve-clog; pure SYNERGY enablers read low with only goblins to
## work with; cards needing a pick UI can't be auto-played (listed separately).
##
## Run (background — ~350 fights):
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardpower.gd

const HERO := "raider"
# brute = a solid vanilla-ish common (2/3, on-enter 1 to opposing creature, NO face
# damage). Makes the baseline "an average common" so a card's score answers "is this
# better or worse than a fair common body?" — and avoids goblin's face-rush ceiling
# (with goblin filler EVERY card scored below baseline because 10 goblins face-rush).
const FILLER := "brute"
const COPIES := 4
const FILL := 6
# Overridable at runtime: --filler=<id> swaps the shell (brute = neutral FLOOR;
# goblin = aggressive/go-wide/death CEILING for condition-enabling cards).
var _filler: String = FILLER
# --only=<id> sims just that one card (bypasses the draftable/modal filter, so temp
# variant cards marked rarity:"enemy" can still be graded). Repeatable via commas.
var _only: Array = []
# --copies=N : how many copies of the test card to stack. Default 4 amplifies a
# CREATURE's signal, but for non-body cards (buff/utility SPELLS) 4 copies means 4
# fewer creatures than baseline + redundant draws — grade those at --copies=1 ("is
# ONE worth a card slot, given bodies to act on?").
var _copies: int = COPIES
# --wide : grade over the 9-fight act-1 gauntlet instead of the 2-fight default.
# The 2-fight GAUNTLET is fine for a coarse 130-card sweep but far too thin to
# RANK a small slate against itself — one unlucky enemy opening moves a card
# several places. Costs ~4.5x the wall time; use it whenever the question is
# "which of these ~20 is out of line?" rather than "sweep everything".
var _wide: bool = false
# [encounter, rng_seed] — the seed is FIXED per encounter and reused across every
# card (common random numbers), so two cards face identical enemy draws/placement
# and the margin gap is attributable to the CARD, not luck. Combat's 98 global
# randi()/shuffle() calls are otherwise unseeded (baseline swung +8..+15 run-to-run).
const GAUNTLET := [["bandit_camp", 111], ["dragons_lair", 333]]   # act1 + act3 range
# Fights now run to an ACTUAL death (2026-07-13, user-directed): the old 6-round
# margin snapshot rewarded raw tempo and couldn't tell a clean win from barely
# surviving. MAX_ROUNDS is just a stalemate safety net (two walls that can't
# close) — real fights end when a hero hits 0 and the phase flips to GAME_OVER.
const MAX_ROUNDS := 24
# Roguelike scoring: HP is the RUN currency, so ending a fight at or below this
# is a run-ender — scored as a loss even if the enemy died first. A crippling
# "win" must never read like a clean one.
const NEAR_DEATH_HP := 4
const NEAR_DEATH_PENALTY := 15
const TURN_WAIT_TICKS := 70
const TICK := 0.1
# Cards the headless bot can't play (open a pick UI / need special state).
const MODAL := ["familiar", "scholar", "treasure_hunter", "adaptable", "copycat",
	"doppelganger", "lost_tome", "war_council", "chaos_imp", "war_chant",
	"gambit", "recycle", "reanimate", "grave_robbery"]

# ── Pilot policies mined from real interactive playlogs (2026-07-13, 209
# sessions): creatures land before spells; walls hold the front opposite the
# biggest threat; snipers/siege engines shelter in the back row; sacrifice
# outlets feed the cheapest body, never the best attacker; heals go to the
# wounded veteran; army-wide support waits until there IS an army.
const SAC_FODDER := ["dark_pact", "offering", "last_due"]   # eat the least valuable body
const SAC_CANNON := ["fuel_the_pyre"]           # hurl a heavy hitter that's dying anyway
const HEAL_SPELLS := ["patch_up"]               # mend the wounded veteran
# ── Retinue starters (2026-07-28) need INTENT targeting, not "highest ATK" ──
# Measured: with the generic `friendly_creature -> _best_friendly()` rule these
# four cards were graded while doing the OPPOSITE of their purpose, which is the
# single largest source of a false "the new decks are weak" reading:
#   last_due       sacrificed the deck's BEST attacker every cast (now SAC_FODDER)
#   read_the_will  fired at the highest-ATK body, which almost never carries an
#                  on_death, so the spell resolved as a no-op ~every cast
#   touchpaper     fired at a body with no Doom -> "NO FUSE TO LIGHT", a dead card
#   close_ranks    fired at the biggest attacker rather than the best-connected
#                  body, wasting most of the adjacency payout
# NOTE these bypass Combat._target_contract_available (this probe calls
# _resolve_spell directly), so the pickers below must return null themselves
# when the board cannot honour the card — that is what holds the card instead
# of burning it.
const WILL_SPELLS := ["read_the_will"]          # needs a body that HAS an on_death
const DOOM_SPELLS := ["touchpaper"]             # needs a body that HAS a fuse
const ADJACENCY_SPELLS := ["close_ranks_order"]  # wants the best-connected body
const RETREAT_SPELLS := ["countermarch_levy"]   # pull a hurt body out of the front

# ── DECK MODE (2026-07-28) ──────────────────────────────────────────────────
# `--decks` swaps the per-card sweep for an A/B of whole 10-card OPENING decks
# over a real act-1 gauntlet. Built to answer "did the hero-retinue rewrite make
# the openers weaker?" without the biases baked into _probe_autorun's table
# (which scores on enemy_hp<=0 and so mostly measures how many untargeted burn
# spells a deck holds).
#
# The NEW arm is read LIVE from the HeroDB autoload, so it is always exactly
# what ships. The OLD arm is transcribed from `git show HEAD:scripts/data/HeroDB.gd`.
#
# READ THIS BEFORE QUOTING ANY NUMBER FROM THIS MODE — HEAD is 2026-07-09 for
# HeroDB.gd, i.e. NINETEEN DAYS and several balance passes stale. The old decks
# below are therefore "the last COMMITTED openers", not "the openers as they
# stood the day before the rewrite" (that intermediate state was never committed
# and no longer exists anywhere). They are also being run against TODAY's
# CardDB, in which several of their own cards have since changed
# (goblin 1/2 -> 2/1, levy_rider 1/2 -> 2/1, mourner 1/2 -> 1/3). So this is an
# honest A/B of two card lists under one ruleset; it is NOT a regression test
# against a known-good historical build.
const OLD_DECKS := {
	"raider": {
		"deck": ["goblin", "goblin", "levy_rider", "levy_rider", "ratling", "ratling",
			"brute", "brute", "fireball", "fireball"],
		"relic": "veterans_medal"},
	"stalwart": {
		"deck": ["troll", "troll", "brute", "brute", "naga", "naga",
			"palisade", "palisade", "strike", "strike"],
		"relic": "iron_buckler"},
	"acolyte": {
		"deck": ["ratling", "ratling", "ratling", "brute", "goblin", "goblin",
			"mourner", "mourner", "strike", "strike"],
		"relic": "soul_lantern"},
	"pyromancer": {
		"deck": ["fireball", "fireball", "fireball", "strike", "strike", "strike",
			"spark", "spark", "troll", "troll"],
		"relic": "worn_spellbook"},
	"kindler": {
		"deck": ["cinder_pup", "cinder_pup", "kindling", "kindling", "ash_hound",
			"ash_hound", "burning_martyr", "burning_martyr", "fireball", "strike"],
		"relic": "ember_censer"},
}
# Every act-1 combat encounter, plus six act-2 kits as a STRESS tier.
#
# Act 1 alone does not discriminate: measured 2026-07-28, both the old and the
# new Raider opener won 8 of 9 act-1 fights, so win-rate sat at the ceiling and
# could not have shown a difference of any size. The act-2 half is deliberately
# unfair to a bare 10-card opener (in a real run you would arrive with ~15 cards
# and two more relics) and exists purely to put the measurement back on a part
# of the curve where a deck can actually separate from another one.
# Read act-1 and act-2 win rates separately; do not average them into one number.
const DECK_GAUNTLET := ["goblin_scouts", "wolf_pack", "bandit_camp", "mushroom_grove",
	"stone_sentinels", "harpy_nest", "boar_herd", "scarecrow_field", "powderkeg_run"]
const DECK_GAUNTLET_A2 := ["cultist_enclave", "mercenary_company", "haunted_crypt",
	"oathbroken_knights", "carrion_choir", "grass_that_hunts"]

var RS: Node
var EDB: Node
var HDB: Node
var US: Node
var SS: Node
var CDB: Node
var combat: Node
var _started := false
var _scores: Array = []   # [{id, cost, rarity, type, score}]
var _baseline := 0.0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[cardpow] start")
	RS = root.get_node_or_null("RunState"); EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings"); SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB"); HDB = root.get_node_or_null("HeroDB")
	if RS == null or EDB == null or CDB == null:
		print("[cardpow] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	for arg0 in OS.get_cmdline_user_args():
		if String(arg0) == "--decks":
			await _run_decks()
			return

	# Build the testable card list: draftable creatures + spells, minus curses,
	# enemy-only, the filler itself, and modal (un-auto-playable) cards.
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	var test_ids: Array = []
	var skipped_modal: Array = []
	for id in ids:
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		var t := String(d.get("type", ""))
		var r := String(d.get("rarity", ""))
		if t not in ["creature", "spell"]: continue
		if r == "enemy": continue
		if CDB.is_curse(sid): continue
		if sid == FILLER: continue
		if sid in MODAL:
			skipped_modal.append(sid); continue
		test_ids.append(sid)
	# --from=N --to=M slices the test list so a foreground run fits under 10 min
	# (background runs get killed at session teardown). Chunks are combined at the end.
	var from_i := 0
	var to_i := test_ids.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--from="): from_i = int(arg.substr(7))
		elif arg.begins_with("--to="): to_i = int(arg.substr(5))
		elif arg.begins_with("--filler="): _filler = arg.substr(9)
		elif arg.begins_with("--only="): _only = arg.substr(7).split(",", false)
		elif arg.begins_with("--copies="): _copies = maxi(1, int(arg.substr(9)))
		elif arg == "--wide": _wide = true
	from_i = clampi(from_i, 0, test_ids.size())
	to_i = clampi(to_i, from_i, test_ids.size())
	# --only wins: grade exactly the listed ids (any rarity), skipping the sweep.
	var chunk: Array = _only if _only.size() > 0 else test_ids.slice(from_i, to_i)
	var gaunt_desc: String = ("WIDE: %d act-1 fights" % DECK_GAUNTLET.size()) if _wide else str(GAUNTLET)
	print("[cardpow] shell=%s | testing %s over gauntlet %s (%d copies + %d filler, cap %d rounds)"
		% [_filler, ("only " + str(_only) if _only.size() > 0 else "[%d..%d) of %d" % [from_i, to_i, test_ids.size()]), gaunt_desc, _copies, 10 - _copies, MAX_ROUNDS])

	# Baseline: a pure 10-filler deck — the reference line for THIS shell.
	_baseline = await _score_deck([])
	print("[cardpow] BASELINE (10x %s) margin = %+.1f" % [_filler, _baseline])

	var n := 0
	for sid in chunk:
		var score: float = await _score_deck([sid])
		var d: Dictionary = CDB.CARD_POOL[sid]
		_scores.append({"id": sid, "cost": int(d.get("cost", 0)),
			"rarity": String(d.get("rarity", "")), "type": String(d.get("type", "")),
			"score": score})
		n += 1
		print("[cardpow] %3d/%d  %-20s %+6.1f (base %+.1f, lift %+.1f)"
			% [n, chunk.size(), sid, score, _baseline, score - _baseline])

	# ── Report ──
	_scores.sort_custom(func(a, b): return a["score"] > b["score"])
	print("\n[cardpow] ===================== RANKING (strongest first) =====================")
	print("[cardpow] baseline (10x goblin) = %+.1f  | lift = card_score - baseline" % _baseline)
	for row in _scores:
		print("[cardpow] %+6.1f  lift %+6.1f  %-20s [%s %dcc %s]" % [
			row["score"], row["score"] - _baseline, row["id"], row["type"], row["cost"], row["rarity"]])
	# Outlier flags: top/bottom deciles + anything at or below baseline.
	var k: int = maxi(3, _scores.size() / 10)
	print("\n[cardpow] ===== TOO GOOD? (top %d) =====" % k)
	for i in range(mini(k, _scores.size())):
		print("[cardpow]   %-20s %+6.1f (lift %+.1f)" % [_scores[i]["id"], _scores[i]["score"], _scores[i]["score"] - _baseline])
	print("[cardpow] ===== TOO BAD? (bottom %d — at/under a goblin) =====" % k)
	for i in range(maxi(0, _scores.size() - k), _scores.size()):
		print("[cardpow]   %-20s %+6.1f (lift %+.1f)" % [_scores[i]["id"], _scores[i]["score"], _scores[i]["score"] - _baseline])
	print("[cardpow] not simulatable (needs a pick UI): %s" % str(skipped_modal))
	print("[cardpow] DONE")
	quit(0)


# ── Deck A/B mode ───────────────────────────────────────────────────────────

## Run every hero's OLD and NEW opener over the act-1 gauntlet and report both
## the result AND the run-to-run spread, because a single pass proves nothing.
##
## Flags (all after a bare `--`):
##   --decks              enter this mode
##   --seeds=N            seed blocks per deck (default 3). Each block replays
##                        the WHOLE gauntlet under a different RNG seed, and the
##                        block-to-block spread IS the noise estimate.
##   --heroes=a,b         restrict to these heroes
##   --no-relic           run the deck WITHOUT its signature relic, isolating
##                        the card list from the doctrine relic
func _run_decks() -> void:
	var seeds := 3
	var only_heroes: Array = []
	var use_relic := true
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--seeds="): seeds = maxi(1, int(s.substr(8)))
		elif s.begins_with("--heroes="): only_heroes = s.substr(9).split(",", false)
		elif s == "--no-relic": use_relic = false
	var heroes: Array = ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
	if only_heroes.size() > 0: heroes = only_heroes
	print("[decks] gauntlet=%d act-1 fights x %d seed blocks | relic=%s"
		% [DECK_GAUNTLET.size(), seeds, str(use_relic)])

	var rows: Array = []
	for hero in heroes:
		for arm in ["old", "new"]:
			var deck: Array = []
			var relic := ""
			if arm == "old":
				deck = (OLD_DECKS[hero]["deck"] as Array).duplicate()
				relic = String(OLD_DECKS[hero]["relic"])
			else:
				var h: Dictionary = HDB.get_hero(String(hero))
				deck = (h.get("deck", []) as Array).duplicate()
				relic = String(h.get("relic", ""))
			if not use_relic: relic = ""
			var blocks: Array = []
			for b in range(seeds):
				var w1 := 0; var n1 := 0; var m1 := 0.0
				var w2 := 0; var n2 := 0; var m2 := 0.0
				for tier in [1, 2]:
					var list: Array = DECK_GAUNTLET if tier == 1 else DECK_GAUNTLET_A2
					for enc in list:
						# Seed is a pure function of (encounter, block) and NOT of
						# the deck, so both arms meet identical enemy draws —
						# common random numbers, the same trick the card sweep uses.
						var sd: int = hash(String(enc)) + b * 7919
						var r = await _fight_deck(String(enc), sd, String(hero), deck, relic)
						if r == null: continue
						if tier == 1:
							n1 += 1; m1 += float(r["margin"])
							if bool(r["win"]): w1 += 1
						else:
							n2 += 1; m2 += float(r["margin"])
							if bool(r["win"]): w2 += 1
				blocks.append({"w1": w1, "n1": n1, "m1": m1 / float(maxi(1, n1)),
					"w2": w2, "n2": n2, "m2": m2 / float(maxi(1, n2))})
				print("[decks]   %-11s %-3s block %d: act1 %d/%d (%+.1f) | act2 %d/%d (%+.1f)"
					% [hero, arm, b, w1, n1, m1 / float(maxi(1, n1)),
						w2, n2, m2 / float(maxi(1, n2))])
			rows.append({"hero": hero, "arm": arm, "blocks": blocks})

	# ── Report ──
	print("\n[decks] ================= RESULT =================")
	print("[decks] hero        arm   act1 W/N   margin |  act2 W/N   margin | act1 blocks / act2 blocks")
	var noise1: Array = []
	var noise2: Array = []
	var mnoise: Array = []
	for r in rows:
		var w1 := 0; var n1 := 0; var s1 := 0.0
		var w2 := 0; var n2 := 0; var s2 := 0.0
		var p1: Array = []; var p2: Array = []
		var lo1 := 999; var hi1 := -999; var lo2 := 999; var hi2 := -999
		var mlo := 9999.0; var mhi := -9999.0
		for b in r["blocks"]:
			w1 += int(b["w1"]); n1 += int(b["n1"]); s1 += float(b["m1"])
			w2 += int(b["w2"]); n2 += int(b["n2"]); s2 += float(b["m2"])
			p1.append(int(b["w1"])); p2.append(int(b["w2"]))
			lo1 = mini(lo1, int(b["w1"])); hi1 = maxi(hi1, int(b["w1"]))
			lo2 = mini(lo2, int(b["w2"])); hi2 = maxi(hi2, int(b["w2"]))
			var bm: float = (float(b["m1"]) + float(b["m2"])) * 0.5
			mlo = minf(mlo, bm); mhi = maxf(mhi, bm)
		noise1.append(hi1 - lo1); noise2.append(hi2 - lo2); mnoise.append(mhi - mlo)
		var nb: float = float(maxi(1, r["blocks"].size()))
		print("[decks] %-11s %-3s   %2d/%-3d  %+7.1f | %2d/%-3d  %+7.1f | %s / %s"
			% [r["hero"], r["arm"], w1, n1, s1 / nb, w2, n2, s2 / nb, str(p1), str(p2)])
	# The honest headline: how far the SAME deck moves between identical-quality
	# seed blocks. Any old-vs-new gap smaller than this is not a result.
	var worst1 := 0; var worst2 := 0; var worstm := 0.0
	for x in noise1: worst1 = maxi(worst1, int(x))
	for x in noise2: worst2 = maxi(worst2, int(x))
	for x in mnoise: worstm = maxf(worstm, float(x))
	print("[decks] NOISE (widest swing for a FIXED deck across seed blocks):")
	print("[decks]   act1 wins +-%d of %d | act2 wins +-%d of %d | mean margin +-%.1f HP"
		% [worst1, DECK_GAUNTLET.size(), worst2, DECK_GAUNTLET_A2.size(), worstm])
	print("[decks] Any old-vs-new gap below those figures is NOT a result.")
	print("[decks] DONE")
	quit(0)


## One fight with an explicitly installed deck + relic. Mirrors _fight but does
## not stack copies of a test card and does not blanket-clear the relic list.
func _fight_deck(enc_id: String, rng_seed: int, hero: String, deck: Array, relic: String):
	RS.start_new_run(hero, 0, 4242)
	RS.current_encounter_id = enc_id
	var enc: Dictionary = EDB.get_encounter(enc_id)
	RS.current_node_type = String(enc.get("type", "combat"))
	RS.current_act_idx = clampi(int(enc.get("act", 1)), 1, 3) - 1
	RS.relics.clear()
	if relic != "": RS.relics.append(relic)
	RS.deck.clear(); RS.deck_uids.clear()
	for id in deck:
		RS.add_card(String(id))
	seed(rng_seed)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		await _teardown(); return null
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _settle_hand()
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn(): break
	var out = null
	if is_instance_valid(combat):
		var php := int(combat.player_hp)
		var ehp := int(combat.enemy_hp)
		var margin: int = maxi(0, php) - maxi(0, ehp)
		if php <= NEAR_DEATH_HP: margin -= NEAR_DEATH_PENALTY
		# A WIN is the enemy dead with the player still standing. Reported
		# alongside margin on purpose: margin alone hides whether a deck is
		# winning cleanly or losing narrowly, and win-rate alone hides how far
		# from the line a losing deck actually is.
		out = {"win": ehp <= 0 and php > 0, "margin": margin, "rounds": rounds}
	await _teardown()
	return out


## Mean HP margin for a deck = COPIES×extra_ids + goblins to 10, across the gauntlet.
func _score_deck(extra_ids: Array) -> float:
	var lineup: Array = GAUNTLET
	if _wide:
		lineup = []
		for enc in DECK_GAUNTLET:
			# Seed derived from the encounter name, so it is fixed per encounter
			# and shared by every card — common random numbers, as above.
			lineup.append([enc, hash(String(enc))])
	var total := 0.0
	var fights := 0
	for pair in lineup:
		var m = await _fight(String(pair[0]), int(pair[1]), extra_ids)
		if m != null:
			total += float(m)
			fights += 1
	return total / float(maxi(1, fights))


func _fight(enc_id: String, rng_seed: int, extra_ids: Array):
	RS.start_new_run(HERO, 0, 4242)
	RS.current_encounter_id = enc_id
	var enc: Dictionary = EDB.get_encounter(enc_id)
	RS.current_node_type = String(enc.get("type", "combat"))
	# See _probe_autorun: without the act flag, get_act() answers 1 and
	# act-2/act-3 kits are scaled down to act-1 strength before the fight.
	RS.current_act_idx = clampi(int(enc.get("act", 1)), 1, 3) - 1
	RS.relics.clear()   # neutralize the hero's signature relic — isolate the card
	# Install the controlled 10-card deck.
	RS.deck.clear(); RS.deck_uids.clear()
	for id in extra_ids:
		for _c in _copies:
			RS.add_card(String(id))
	while RS.deck.size() < 10:
		RS.add_card(_filler)

	# Common random numbers: pin combat's global RNG so this (card, encounter) is
	# reproducible and every card meets the same enemy line. Set right before the
	# scene consumes any randi() (enemy build / opening shuffle happen in _ready).
	seed(rng_seed)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		await _teardown(); return null
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		await _settle_hand()
		await _auto_play_turn()
		if not is_instance_valid(combat): break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn(): break
	var margin = null
	if is_instance_valid(combat):
		var php := int(combat.player_hp)
		var ehp := int(combat.enemy_hp)
		margin = maxi(0, php) - maxi(0, ehp)
		# Death (php <= 0) is already a negative margin; the <= NEAR_DEATH_HP band
		# also catches a "won but crippled" finish and drags it firmly into
		# loss territory, so surviving at 3 HP never outscores a clean 20-HP win.
		if php <= NEAR_DEATH_HP:
			margin -= NEAR_DEATH_PENALTY
	await _teardown()
	return margin


## Poll until the scene is really ready for input, or the fight is over.
##
## `round_number >= 1` is NOT decoration — dropping it silently voids every
## number this probe prints. `Phase.PLAYER_TURN` is enum 0, which is also
## `phase`'s DEFAULT, so a freshly instantiated Combat answers "ready for input"
## on the very first poll, before `_ready` has built anything. That was
## survivable while the opening was one synchronous block; it stopped being
## survivable when the 2026-07-26 cold-open pass made the build INTERLEAVED
## (`_build_hud` is now a coroutine that hands the frame back).
##
## MEASURED FAILURE (2026-07-28): without this guard the probe played into a
## half-built scene, `_on_end_turn` died on a null `_end_turn_btn` at
## Combat.gd:3774 before it ever reached `_do_combat()`, and EVERY fight ran to
## the MAX_ROUNDS cap having resolved no clash at all. The reported margin was
## then just `player_hp(30) - encounter_hp` — a constant. The whole sweep came
## back at exactly +9.0 for every card ((30-20 + 30-22)/2 over the gauntlet),
## which reads as "saturated / no signal" but was actually "no game was played".
## `_probe_autorun._wait_for_player_turn` carries the same guard for the same
## reason; keep them in step.
func _wait_turn() -> bool:
	var w := 0
	while w < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN and int(combat.round_number) >= 1:
			return true
		await create_timer(TICK).timeout
		w += 1
	return false


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


func _auto_play_turn() -> void:
	# Human turn shape from the playlogs: creatures first, spells after (so
	# removal/buffs see the real board), then one more creature pass in case the
	# skirmish-only Coin opened up another body.
	await _play_creatures()
	await _play_spells()
	await _play_creatures()


func _play_creatures() -> void:
	for _pass in 4:
		if not _turn_live(): return
		var played := false
		for card in combat._hand.duplicate():
			if not _card_live(card): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL: continue
			if String(cd.get("type", "")) != "creature": continue
			if int(combat.player_mana) < int(cd.get("cost", 0)): continue
			var slot = _pick_slot(cd)
			if slot == null: continue
			card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
			combat._on_card_played(card)
			played = true
			await create_timer(0.02).timeout
		if not played: return


func _play_spells() -> void:
	for _pass in 4:
		if not _turn_live(): return
		var played := false
		for card in combat._hand.duplicate():
			if not _card_live(card): continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL: continue
			if String(cd.get("type", "")) != "spell": continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost: continue
			var targeting := String(cd.get("targeting", "none"))
			if targeting == "none":
				# Army-wide support with no army = a wasted card; humans bank instead.
				if String(cd.get("scope", "")) == "YOUR ARMY" \
						and combat._all_player_creatures().is_empty():
					continue
				combat._on_card_played(card)
				played = true
				await create_timer(0.02).timeout
			else:
				var target = _smart_target(cd)
				if target == null or not is_instance_valid(target): continue
				var lane: int = maxi(0, int(target.current_lane))
				combat.player_mana -= cost
				combat._first_spell_this_turn = true
				combat._cards_played_this_turn += 1
				combat._hand.erase(card)
				if card.get_parent() != null: card.get_parent().remove_child(card)
				await combat._resolve_spell(card.card_data, target, lane)
				if is_instance_valid(card): combat._after_spell(card)
				played = true
				await create_timer(0.02).timeout
		if not played: return


func _turn_live() -> bool:
	return is_instance_valid(combat) and combat.phase == combat.Phase.PLAYER_TURN


func _card_live(card) -> bool:
	return is_instance_valid(card) and (card in combat._hand)


func _smart_target(cd: Dictionary) -> Object:
	var id := String(cd.get("id", ""))
	var targeting := String(cd.get("targeting", "none"))
	var spell: Dictionary = cd.get("spell", {})
	# Intent beats targeting string: a sacrifice outlet wants the WORST body,
	# a heal wants the wounded one — the old "highest ATK friendly" pick was
	# the single biggest source of bogus low scores for these cards.
	if id in SAC_FODDER: return _sac_fodder()
	if id in SAC_CANNON: return _sac_cannon()
	if id in HEAL_SPELLS: return _wounded_veteran()
	if id in WILL_SPELLS: return _bequest_body()
	if id in DOOM_SPELLS: return _shortest_fuse()
	if id in ADJACENCY_SPELLS: return _best_connected()
	if id in RETREAT_SPELLS: return _wounded_front()
	var stype := String(spell.get("type", ""))
	var supportive: bool = stype in ["buff_atk", "buff_hp", "heal", "shield", "regen", "buff_all_atk"] \
		or targeting == "friendly_creature"
	if targeting == "friendly_creature": return _best_friendly()
	if targeting == "enemy_creature": return _best_enemy(int(spell.get("value", 3)))
	if supportive:
		var f = _best_friendly()
		if f != null: return f
	var e = _best_enemy(int(spell.get("value", 3)))
	if e != null: return e
	return combat._auto_target_for(targeting)


func _sac_fodder() -> Object:
	# Feed the knife the least valuable body — and never our only one.
	var mine: Array = combat._all_player_creatures()
	if mine.size() < 2: return null
	var best: Object = null
	var best_v := 9999
	for c in mine:
		if not is_instance_valid(c): continue
		var v: int = c.effective_atk() * 2 + int(c.current_hp)
		if v < best_v: best_v = v; best = c
	return best


func _sac_cannon() -> Object:
	# Hurl the hardest hitter that is already dying; else fall back to fodder.
	var mine: Array = combat._all_player_creatures()
	if mine.size() < 2: return null
	var best: Object = null
	var best_a := -1
	for c in mine:
		if not is_instance_valid(c): continue
		if int(c.current_hp) <= 2 and c.effective_atk() > best_a:
			best_a = c.effective_atk(); best = c
	return best if best != null else _sac_fodder()


func _wounded_veteran() -> Object:
	# Mend the damaged body with the most ATK still in it; nobody hurt = hold.
	var best: Object = null
	var best_s := 0
	for c in combat._all_player_creatures():
		if not is_instance_valid(c): continue
		var missing: int = int(c.card_data.get("hp", c.current_hp)) - int(c.current_hp)
		var s: int = missing * 2 + c.effective_atk()
		if missing > 0 and s > best_s: best_s = s; best = c
	return best


func _bequest_body() -> Object:
	# Read the Will: the only sane target is a body that actually HAS a will to
	# read. Prefer the fattest bequest we can measure cheaply (a summon or an
	# area effect beats a 1-damage ping), then the sturdiest carrier so the
	# creature survives to die properly later.
	var deny: Array = []
	if "READ_THE_WILL_DENY" in combat:
		deny = combat.READ_THE_WILL_DENY.keys()
	var best: Object = null
	var best_s := -1
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.current_hp <= 0: continue
		var will: Dictionary = c.card_data.get("on_death", {})
		if will.is_empty(): continue
		if String(will.get("type", "")) in deny: continue
		var s: int = int(will.get("value", 1)) * 3 + int(c.current_hp)
		if String(will.get("type", "")) == "summon": s += 10
		if s > best_s: best_s = s; best = c
	return best


func _shortest_fuse() -> Object:
	# Touchpaper: only a Doom body has a fuse at all. Pull the SHORTEST one, so
	# the tick is most likely to convert into an actual detonation this round
	# rather than being spent on a timer that had rounds left to run anyway.
	var best: Object = null
	var best_d := 99999
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.current_hp <= 0: continue
		if not c.has_keyword("doom"): continue
		var d: int = int(c.card_data.get("doom", 99))
		if "doom_counter" in c and int(c.doom_counter) != -999:
			d = int(c.doom_counter)
		if d < best_d: best_d = d; best = c
	return best


func _best_connected() -> Object:
	# Dress the Line pays per BODY it touches (the named one plus its adjacent
	# allies), so the target is the best-connected creature, not the biggest.
	var best: Object = null
	var best_s := -1
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.current_hp <= 0: continue
		var pos: Dictionary = combat._find_creature_position(c)
		if pos.is_empty(): continue
		var n := 0
		for a in combat._adjacent_creatures(false, int(pos.row), int(pos.lane)):
			if a != null and is_instance_valid(a) and a.current_hp > 0: n += 1
		# Ties to the body with the most ATK riding on the extra HP.
		var s: int = n * 100 + c.effective_atk()
		if s > best_s: best_s = s; best = c
	return best


func _wounded_front() -> Object:
	# Change Step is a retreat: pull the most badly hurt FRONT body out of the
	# line (it also gains +1 HP). Nobody hurt in front = hold the card.
	var best: Object = null
	var best_missing := 0
	for lane in range(combat.LANES_PER_ROW):
		var c = combat._row_array(false, combat.ROW_FRONT)[lane]
		if c == null or not is_instance_valid(c) or c.current_hp <= 0: continue
		var missing: int = int(c.card_data.get("hp", c.current_hp)) - int(c.current_hp)
		if missing > best_missing: best_missing = missing; best = c
	return best


func _best_enemy(dmg: int) -> Object:
	var best: Object = null; var best_atk := -1
	var bk: Object = null; var bk_atk := -1
	for c in combat._all_enemy_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk: best_atk = atk; best = c
		if dmg > 0 and int(c.current_hp) <= dmg and atk > bk_atk: bk_atk = atk; bk = c
	return bk if bk != null else best


func _best_friendly() -> Object:
	var best: Object = null; var best_atk := -1
	for c in combat._all_player_creatures():
		if not is_instance_valid(c) or c.has_keyword("structure"): continue
		var atk: int = c.effective_atk()
		if atk > best_atk: best_atk = atk; best = c
	return best


func _pick_slot(cd: Dictionary):
	# Placement policy from the human playlogs: walls hold the front opposite
	# the biggest attacker; snipers/siege pieces shelter in back (front is
	# struck first); attackers hunt a kill-trade, then an open road to the
	# face, then block; everything overflows to back as queue when front fills.
	var kws: Array = cd.get("keywords", [])
	var atk := int(cd.get("atk", 0))
	var hp := int(cd.get("hp", 1))
	var is_wall: bool = ("guardian" in kws) or (atk <= 1 and hp >= 4)
	var wants_back: bool = ("sniper" in kws) \
		or String(cd.get("passive", "")) == "trebuchet_volley" \
		or (atk == 0 and not ("guardian" in kws))
	var front_free: Array = []
	var back_free: Array = []
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_FRONT)[lane] == null: front_free.append(lane)
		if combat._row_array(false, combat.ROW_BACK)[lane] == null: back_free.append(lane)
	if wants_back and back_free.size() > 0:
		var pick_b: int = back_free[0]
		for l in back_free:   # prefer sheltering behind a held front lane
			if combat._row_array(false, combat.ROW_FRONT)[l] != null:
				pick_b = l
				break
		return combat._slot_array(false, combat.ROW_BACK)[pick_b]
	if front_free.size() > 0:
		var pick: int = front_free[0]
		if is_wall:
			var best_t := -1
			for l in front_free:
				var t := _lane_threat(l)
				if t > best_t: best_t = t; pick = l
		else:
			var best_s := -999
			for l in front_free:
				var e = combat._row_array(true, combat.ROW_FRONT)[l]
				var s := 0
				if e != null and is_instance_valid(e):
					if int(e.current_hp) <= atk: s = 100 + e.effective_atk()   # trade up
					else: s = _lane_threat(l) - int(e.current_hp)              # block value
				else:
					s = 50   # open road to the face
				if s > best_s: best_s = s; pick = l
		return combat._slot_array(false, combat.ROW_FRONT)[pick]
	if back_free.size() > 0:
		return combat._slot_array(false, combat.ROW_BACK)[back_free[0]]
	return null


func _lane_threat(lane: int) -> int:
	var t := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var e = combat._row_array(true, row)[lane]
		if e != null and is_instance_valid(e):
			t += e.effective_atk()
	return t


func _teardown() -> void:
	if is_instance_valid(combat): combat.queue_free()
	combat = null
	await create_timer(0.04).timeout
