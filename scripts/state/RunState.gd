extends Node
## RunState.gd — autoload singleton. Holds the current run's persistent data.
## Owns run persistence/navigation. CampaignMapGenerator builds map topology.

const CampaignMapGenerator = preload("res://scripts/campaign/CampaignMapGenerator.gd")

# ── Hero ──
var hero_max_hp: int = 30
var hero_hp: int = 30
var gold: int = 0
# Id of the hero picked at the start of the run. Used by the rest screen to
# pick the right silhouette / flavor strings; otherwise the run is hero-agnostic
# (deck and signature relic are baked in at start_new_run time). Falls back to
# HeroDB.DEFAULT_HERO if anyone reads this before start_new_run() ran.
var current_hero_id: String = ""
# Rest-screen counters. `rests_visited_in_act` resets when the act advances and
# powers the time-of-day shader tint (first rest = dusk, second = night). Whetstone
# also reads this to determine "first rest of act". Persisted via save_state below.
var rests_visited_in_act: int = 0
var rests_visited_total: int = 0
var whetstone_used_this_act: bool = false
# Array of potion ids the player currently holds (max 3). Each id is a key
# into PotionDB.POTIONS.
var potions: Array[String] = []
const MAX_POTIONS: int = 3

# ── Deck ──
var deck: Array[String] = []
var deck_uids: Array[int] = []
var card_upgrades: Dictionary = {}
var _next_uid: int = 0

# ── Campaign memory (docs/CAMPAIGN_MEMORY.md) ──
# Combat kills per creature, keyed by deck_uid — the service record behind the
# tally scratches on the writ, the epithet at 3 kills, and the +1/+1 at 6.
var creature_kills: Dictionary = {}
# The Roll of the Fallen: one entry per FALL of a real deck creature
# ({name, id, uid, enc, act, round}). Falls, not removals — creatures return
# next fight as always; the Roll is the run's written history of its dead.
var fallen: Array = []

# Kill thresholds for the veterancy milestones.
#
# THE LADDER MOVED FORWARD (2026-07-30). The choosing rung used to sit at 10
# kills, which measured out to "most runs never see it": a card has to survive
# and win ten separate clashes, and the reward for doing so was the first time
# the player got to say anything about it. So the CHOICE moved to the first rung
# and a second, tribe-shaped choice took over the tenth — the front of the ladder
# is where a decision changes how the rest of the run is played.
const VETERAN_EPITHET_KILLS := 3   # earns a name AND the first war school
const VETERAN_RANK_KILLS := 6      # earns +1/+1
const VETERAN_DOCTRINE_KILLS := 10 # earns the tribe's doctrine — a 2nd chosen keyword
# (Combat offers Armored/Swift/Thorns at the first rung and the creature's own
# tribe doctrine at the third; each pick writes a "war_school" / "doctrine" mod
# entry so it folds like any other permanent card change and never re-asks.)
# Epithet table — deterministic per uid (hash pick), so a name never rerolls
# across save/load. Written in the campaign's multi-register voice.
const VETERAN_EPITHETS: Array[String] = [
	"the Blooded", "the Grim", "the Quiet One", "Wall-Breaker",
	"Thrice-Scarred", "the Patient", "Old Salt", "the Hungry",
	"Bridge-Holder", "Lord's-Bane", "Ash-Walker", "the Lucky",
	"First Ashore", "Widow-Maker", "the Meadow-Born", "Oathkeeper",
]

# ── Relics ──
var relics: Array[String] = []
# Run-wide General tally (unlike holds_broken_in_act, this never resets between
# acts). Heads on Pikes reads it, and its offer gate requires at least one.
var generals_broken_run: int = 0
# The Articles of War is chosen after acquisition on the map. Empty means the
# choice is still pending; Combat never applies a discount until it is set.
var articles_of_war_tribe: String = ""
# ── Season winds (2026-07-21) — the run's draft weather. Two tribes roll
# "mustering this season" at run start (seeded off run_seed, so a daily or
# custom-seed march deals every player the same season). Recruit's affinity
# scoring leans slates toward them, so two runs of the same hero walk
# different roads. Announced on the war chest and at each muster. Empty on
# legacy saves — the lean simply doesn't apply.
var season_tribes: Array = []
# The tribe declared at THE MUSTER. Empty only on a legacy v4 save that began
# before banners existed; new runs always normalize to BannerDB.DEFAULT_BANNER.
var current_banner_tribe: String = ""

# Per-act choice stash for "Each act, pick X" relics. The MapView picker writes
# the choice + the act it was made for; a mismatch with get_act() re-prompts at
# the start of the next act. Empty string = no choice made yet this act.
var totem_pole_keyword: String = ""
var totem_pole_act: int = 0
var bone_hourglass_choice: String = ""
var bone_hourglass_act: int = 0
# Bottled Talisman: deck_uid the player bound at acquisition. -1 = unbound (the
# MapView/acquire-screen picker will prompt for a card). Combat pulls this uid
# into the opening hand every fight.
var bottled_talisman_uid: int = -1

# ── Map ──
var map_data: Array = []
var current_act_idx: int = 0
var map_position: Dictionary = {"row": -1, "col": -1}
# Per-act campaign-plate cache (NOT saved): MapTerrain parks its generated
# mesh arrays + baked geography texture here, so re-opening the map after a
# room restores in one frame instead of regenerating ~hundreds of ms of
# terrain. Keyed by act index (1-3). Cleared on new run / load / act change.
var map_plate_cache: Dictionary = {}
var current_encounter_id: String = ""
var current_node_type: String = ""
var current_mutator_id: String = ""
# Phase 2.5 — the visited node's route terrain ("meadow"/"woods"/"pass"/
# "ash"; "" before the plate has tagged the act) and whether the road in
# crosses a river bridge. Event/Recruit read these to lean their offers.
var current_terrain: String = ""
var current_bridge: bool = false
# Which roadside verb a visited wayside halt runs ("drill_yard" /
# "muster_scale" / "standard_bearer" / "supply_cache"). Assigned at map gen
# (node.wayside_id) so the chart can advertise the stop; copied here by
# visit_node so the Wayside scene knows which screen to build.
var current_wayside_id: String = ""
# Which SET-PIECE (named action) a visited hold is, if any — SetPieceDB id,
# "" for an ordinary hold. Assigned at map gen (node.setpiece_id) so the chart
# can advertise the ground before the player commits; copied here by
# visit_node. A set-piece is a `combat` node wearing this field — the same
# precedent as wayside_id / mutator_id — so every routing, save, medallion and
# reward path keeps working untouched. See scripts/data/SetPieceDB.gd.
var current_setpiece_id: String = ""
# Named actions already carried this run, so the GameOver chronicle can list
# them and a re-entered save never re-pays a trophy.
var setpieces_carried: Array[String] = []
# Run statistics — surfaced on the GameOver recap screen. Reset by
# start_new_run, updated by Combat on each victory / death, persisted in
# the save file so a quit-mid-run resume keeps the running counts.
var fights_won: int = 0
var mutators_survived: Array[String] = []
var cause_of_death: String = ""  # encounter name that killed the player
var events_seen: Array[String] = []
# Stable, choice-aware continuity flags. `events_seen` remains the room-level
# anti-repeat/history signal; these flags are only written after a player
# commits the specific action a later callback refers to.
var event_choice_flags: Array[String] = []
# Fight-spoils potion pity ladder: +10% drop chance per dry fight, reset on a
# drop (Combat victory payout). Persisted so save/reload can't reroll it.
var potion_drop_misses: int = 0

# Muster reroll charges (Recruiter's Horn). A run-wide pool granted when the
# relic is acquired; each Muster reroll spends one. Persisted so a reload can't
# refill it. Zero without the relic (and after the pool is spent) — the Muster
# only shows the reroll button while this is > 0. See Recruit.gd.
var muster_rerolls_left: int = 0

# ── Successor Wars: rivals & kingdoms ──
# Three road rivals (index = act_idx) plus the lord who CURRENTLY waits at the
# throne. THE NEXT MARCH may swap that candidate back onto the road; whichever
# lord remains unchosen after the second choice becomes the true finale.
# act_faction always mirrors rival_lords. Empty arrays mean a legacy save
# (pre-conquest), and consumers must fall back gracefully.
var rival_lords: Array[String] = []
var finale_rival: String = ""
var act_faction: Array[String] = []
# Combat/elite victories this act. The rival lord's keep unlocks at
# HOLDS_TO_OPEN_LORD broken holds (incremented by Combat on victory, reset by
# advance_act). Kept in RunState so it saves with the run.
var holds_broken_in_act: int = 0
# Run-wide copy for balance telemetry. Unlike the gate counter above, this does
# not reset between kingdoms.
var holds_broken_run: int = 0
# The boss gate (§15.1 #5): the keep is visible from the first step but
# locked until this many holds have fallen. Map generation guarantees every
# route to the keep carries at least this many fight nodes (no softlock).
const HOLDS_TO_OPEN_LORD: int = 2
# 0 = the three marches; 1 = the throne. After the act-3 rival falls, a
# conquest run routes into one last fight — the spared rival as an amalgam
# (amalgam_<finale_rival>) — before the real victory. Set by enter_finale,
# persisted so a quit at the throne door resumes into the fight (MapView
# redirects stage-1 resumes back into Combat; the throne is not a map node).
var finale_stage: int = 0


## False only while a conquest run still owes holds this act. Legacy runs
## (no rival deal) keep the old always-open keep.
func is_lord_gate_open() -> bool:
	if rival_lords.is_empty():
		return true
	return holds_broken_in_act >= HOLDS_TO_OPEN_LORD


func get_lord_node() -> Dictionary:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return {}
	for row in act_map:
		for n in row:
			if String(n.get("type", "")) == "boss":
				return n
	return {}

# ── Mana ──
var base_max_mana: int = 3

# ── Compatibility ──
var current_floor: int = 0
var run_active: bool = false
var run_seed: int = 0
var phoenix_heart_consumed: bool = false
# Marked One event delayed-payoff. Set by Event.gd, consumed by Combat.gd at
# the START of the next combat fight and immediately cleared. Both fields
# persist through save/load so closing the game between the event and the
# fight doesn't drop the payoff.
#   next_combat_gift_creature: {name, atk, hp, kw[]} placed in front-left lane
#   next_combat_mana_bonus: int added to max mana for the entire fight
var next_combat_gift_creature: Dictionary = {}
var next_combat_mana_bonus: int = 0
# Cards sold through the Pawnbroker's appraisal counter, oldest first. The
# shelf behind the glass remembers them: a later visit (act 2+) offers the
# FIRST one back, sharpened, at her keeping fee. Persisted with the run.
var pawned_cards: Array = []
# Daily March state: locked to today's seed, carrying today's omen (a run-wide
# mutator that fills every fight without a node mutator of its own). Set by
# MainMenu right after start_new_run; persisted with the run save.
var is_daily_run: bool = false
var daily_mutator_id: String = ""
# Calendar date whose seed opened this Daily March. Persisting the origin lets a
# run finished after midnight update the attempt it actually belongs to.
var daily_date: String = ""
# Ascension level chosen for this run (0..MetaState.unlocked_ascension).
# Set in start_new_run; never modified mid-run.
var current_ascension: int = 0
# ── Ascension = a ladder of RULES, not an HP sponge (redesigned 2026-07-03). ──
# The old ASCENSION_HP_MULT (1.0→2.0 face HP) made every fight the same fight,
# longer — the opposite of the fast-snowball pacing the game is tuned for.
# Each tier now ADDS one rule to all tiers below; consumers ask asc_active(n).
#   A1 Combat._esc_round        — escalation beats land one round earlier
#   A2 Rest._do_heal            — camp rest heals 60% of missing HP, not full
#   A3 here (run/act start)     — begin each act with a War-Debt curse
#   A4 Combat._place_enemy_card — General/lord creatures enter with +1 ATK
#   A5 Combat._scale_enemy_hp   — lords' keep faces +25% HP (bosses ONLY)
const ASCENSION_RULES: Array[String] = [
	"",
	"Enemy reinforcements arrive one round earlier.",
	"Camp Rest heals 60% of missing HP instead of healing to full.",
	"Begin each act with a War-Debt in your deck.",
	"General and lord creatures enter with +1 ATK.",
	"Lord fights have 25% more HP.",
]


func asc_active(tier: int) -> bool:
	return current_ascension >= tier

const ACTS: int = 3

# ── Campaign-map constants ──
# 7 columns wide, 10 rows tall (rows 0..8 are explorable, row 9 = keep).
# History: 15 rows → 8 on 2026-06-10 (at ~38 sites the map read as an
# abstract lattice, not a campaign over the plate) → 10 on 2026-06-12
# (the road-to-the-keep pass: fight count stays constant, the two new
# rows are wayside tissue — the Kaycee's-Mod length lesson: a road grows
# in verbs, not violence) → 12 on 2026-06-12 (slice 2: TWO between-fight
# stops per gap, the Inscryption cadence — every gap between holds is a
# pair of waysides drawn from event/verb/recruit/shop/treasure).
# _generate_act_map enforces a 24–36-site window with an acceptance loop.
const MAP_WIDTH: int = CampaignMapGenerator.MAP_WIDTH
const MAP_HEIGHT: int = CampaignMapGenerator.MAP_HEIGHT
const BOSS_ROW: int = CampaignMapGenerator.BOSS_ROW
const REST_ROW: int = CampaignMapGenerator.REST_ROW
const NUM_PATHS: int = CampaignMapGenerator.NUM_PATHS

# Row skeleton (Kaycee's-Mod model, 2026-06-12; lengthened 2026-07-07): every
# row carries a fixed BEAT — fight rows alternate with wayside PAIRS — so the
# road's rhythm is guaranteed by construction and the within-row choice becomes
# "which flavor of this beat" (fights differ by terrain/kit, waysides by verb).
# This replaced the per-node probability table + sibling/consecutive rules: the
# skeleton can't deal a corridor of straight fights, and fight count per act is
# CONSTANT. Lengthened from 12 rows / 5 combats — the act ended in 3-4 fights,
# too short for the deck, veterancy, and relics to snowball. Now 18 rows /
# 7 combats: 4 plain holds + 2 elite spikes + keep, all extra length being
# between-fights tissue. See _assign_node_types for the band content.
const FIGHT_ROWS: Array[int] = CampaignMapGenerator.FIGHT_ROWS
const ELITE_ROWS: Array[int] = CampaignMapGenerator.ELITE_ROWS

# First-run on-ramp (CLARITY_AUDIT P1#5): on a player's very first campaign
# (MetaState.total_runs == 0 — no run has ever been finished), the Act-1
# row-0 hold is pinned to one hand-picked gentle fight with its mutator
# suppressed, so the first thing a newcomer fights is calm and predictable.
# "goblin_scouts" (The First Cut) is the gentlest authored Act-1 combat:
# the lowest total statline, an EMPTY passive, no thorns/armored walls to
# muddy first trades, no resource/heal/regen trap, and a trivial 1/1 Swift
# reinforcement. The matching "drag a creature onto a lane" coach tip is
# wired separately in Combat (P1#5, other lane).
const FIRST_RUN_OPENER_ENCOUNTER: String = CampaignMapGenerator.FIRST_RUN_OPENER_ENCOUNTER


func get_act() -> int:
	return current_act_idx + 1


# ── Run lifecycle ──

## Compute today's daily-run seed from local-time YYYYMMDD. The same date
## across machines produces the same map, so daily runs are shareable.
func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


## Today's omen — the daily march's run-wide mutator, rotated deterministically
## off the date so every player who marches today faces the same weather.
## Fights that roll their OWN node mutator keep it; the omen fills the rest
## (Combat._init_mutator_state does the fallback).
func daily_mutator_id_for_today() -> String:
	var ids: Array = MutatorDB.MUTATORS.keys()
	ids.sort()
	if ids.is_empty():
		return ""
	return String(ids[daily_seed() % ids.size()])


## Hash an arbitrary string into a deterministic seed. Used by custom-seed
## runs so a player can type "burningmeadow" and get the same map every time.
func seed_from_string(s: String) -> int:
	if s == "":
		return randi()
	# Simple FNV-1a-style hash so identical strings always hash identically
	# across runs (built-in `String.hash()` is also deterministic but the FNV
	# approach is easier to mentally replay if a player is debugging a seed).
	var h: int = 0x811c9dc5
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xffffffff
		h = (h * 0x01000193) & 0xffffffff
	return h


# Cross-run muster options (set by MainMenu's run-setup pane right before
# start_new_run, consumed and cleared inside it). Empty = the hero's defaults.
# pending_signature_relic — a relic id to march with instead of hero.relic
#   (unlocked by the hero's first victory; the alt lives in HeroDB.relic_alt).
# pending_deck_variant — "alt" to build from HeroDB.deck_alt.deck instead of
#   hero.deck (unlocked by a victory at Ascension 4+).
var pending_signature_relic: String = ""
var pending_deck_variant: String = ""
# Declared banner on the still-reversible setup screen. Consumed at commit.
var pending_banner_tribe: String = ""


# What the LIVE run actually mustered with, recorded by start_new_run as the
# pending picks are consumed. The pending fields are cleared at run start, so
# without these the muster choice is unrecoverable — which is what made MARCH
# AGAIN quietly drop unlocked variants.
var current_signature_relic: String = ""
var current_deck_variant: String = ""

## Pure opener composition used by THE ROLL preview and start_new_run alike.
## Keeping one function on both sides of the commit boundary is what makes the
## visible eleven-card roll an honest preview rather than a second deck recipe.
static func opening_deck_for(hero_id: String, use_alt_deck: bool = false,
		banner_tribe: String = BannerDB.DEFAULT_BANNER) -> Array[String]:
	var hero: Dictionary = HeroDB.get_hero(hero_id)
	var source: Array = hero.get("deck", CardDB.STARTER_DECK)
	if use_alt_deck:
		var alt: Dictionary = hero.get("deck_alt", {})
		if not alt.is_empty():
			source = alt.get("deck", source)
	var out: Array[String] = []
	for cid in source:
		out.append(String(cid))
	var banner_card := BannerDB.card_id(BannerDB.normalize(banner_tribe))
	if banner_card != "":
		out.append(banner_card)
	return out



func start_new_run(hero_id: String = "", ascension: int = -1, seed_override: int = 0) -> void:
	hero_max_hp = 30
	hero_hp = 30
	gold = 100
	potions = []
	base_max_mana = 3
	# Per-run trigger flags — must be reset here, not just at declaration,
	# otherwise the value carries over from the previous run when the player
	# starts a new run from MainMenu without restarting the executable. A
	# fresh Phoenix Heart relic wouldn't have fired in that case.
	phoenix_heart_consumed = false
	next_combat_gift_creature = {}
	next_combat_mana_bonus = 0
	pawned_cards = []
	is_daily_run = false
	daily_mutator_id = ""
	daily_date = ""
	map_plate_cache.clear()
	# Campaign memory starts blank — a new march, a fresh ledger.
	creature_kills = {}
	fallen = []
	generals_broken_run = 0
	articles_of_war_tribe = ""
	current_banner_tribe = ""
	season_tribes = []
	# Default to player's highest unlocked tier if caller didn't pick one.
	if ascension < 0:
		current_ascension = MetaState.unlocked_ascension
	else:
		current_ascension = clampi(ascension, 0, MetaState.unlocked_ascension)
	# Resolve hero. "" means "use the default" — keeps any legacy code path
	# that called start_new_run() with no args working (it'll land on Stalwart).
	var hero_key: String = hero_id if hero_id != "" else HeroDB.DEFAULT_HERO
	current_hero_id = hero_key
	rests_visited_in_act = 0
	rests_visited_total = 0
	whetstone_used_this_act = false
	totem_pole_keyword = ""
	totem_pole_act = 0
	bone_hourglass_choice = ""
	bone_hourglass_act = 0
	bottled_talisman_uid = -1
	var hero: Dictionary = HeroDB.get_hero(hero_key)
	deck = []
	deck_uids = []
	card_upgrades = {}
	_next_uid = 0
	# Muster options are consumed here and cleared so an abandoned setup cannot
	# leak into a later rematch or legacy start_new_run call. The first win opens
	# the authored pair; mastery is the later permission to split that pair.
	# Direct callers pass through the same authorization as the setup screen.
	# First-win authorization is a bound doctrine; A4 mastery opens the two axes.
	# Normalize here as well as in MainMenu so direct callers cannot smuggle a
	# pre-mastery mixed loadout into a run.
	var alt_deck: Dictionary = hero.get("deck_alt", {})
	var alt_relic := String(hero.get("relic_alt", ""))
	var doctrine_unlocked := MetaState.hero_wins(hero_key) >= 1 \
		and not alt_deck.is_empty() and alt_relic != ""
	var mastery_unlocked := doctrine_unlocked \
		and MetaState.hero_best_asc(hero_key) >= 4
	var requested_alt_deck := pending_deck_variant == "alt"
	var requested_alt_relic := pending_signature_relic == alt_relic
	var use_alt_deck := false
	var use_alt_relic := false
	if mastery_unlocked:
		use_alt_deck = requested_alt_deck
		use_alt_relic = requested_alt_relic
	elif doctrine_unlocked and requested_alt_deck and requested_alt_relic:
		use_alt_deck = true
		use_alt_relic = true

	var declared_banner := BannerDB.normalize(pending_banner_tribe)
	var deck_list: Array[String] = opening_deck_for(hero_key, use_alt_deck, declared_banner)
	for id in deck_list:
		add_card(id)
	# A3 "The ledger follows" — every act opens with a War-Debt in the deck
	# (act 1's is added here; advance_act adds the later ones).
	if asc_active(3):
		add_card("war_debt")
	relics = []
	var hero_relic := alt_relic if use_alt_relic \
		else String(hero.get("relic", ""))
	if hero_relic != "":
		relics.append(hero_relic)
	# Record the resolved choice before clearing the pending fields. Save/load
	# and MARCH AGAIN use these canonical values rather than trying to infer the
	# doctrine from a deck that may already have transformed during the run.
	current_signature_relic = hero_relic
	current_deck_variant = "alt" if use_alt_deck else ""
	pending_signature_relic = ""
	pending_deck_variant = ""
	current_banner_tribe = declared_banner
	current_floor = 0
	current_act_idx = 0
	pending_banner_tribe = ""
	map_position = {"row": -1, "col": -1}
	current_encounter_id = ""
	current_node_type = ""
	current_mutator_id = ""
	current_terrain = ""
	current_bridge = false
	current_wayside_id = ""
	current_setpiece_id = ""
	setpieces_carried = []
	fights_won = 0
	mutators_survived = []
	cause_of_death = ""
	events_seen = []
	event_choice_flags = []
	potion_drop_misses = 0
	muster_rerolls_left = 0
	holds_broken_in_act = 0
	holds_broken_run = 0
	finale_stage = 0
	run_active = true
	# seed_override of 0 means "roll a fresh random seed". Non-zero values come
	# from daily_seed() / seed_from_string() so the map is reproducible.
	run_seed = seed_override if seed_override != 0 else randi()
	_select_rivals()
	_roll_season()
	CardTextureCache.clear()
	_generate_map()
	# PlayLog: open a per-run telemetry session now that deck + relics are built.
	PlayLog.start_session({
		"hero": current_hero_id, "seed": run_seed, "ascension": current_ascension,
		"deck": deck.duplicate(), "relics": relics.duplicate()})


## The seeded deal fixes Act 1 so the existing run opening needs no extra modal.
## Two provisional road rivals and one provisional finale candidate complete
## the deal. After Act 1, THE NEXT MARCH offers all three living lords; after
## Act 2 it offers both survivors. The last unchosen lord takes the throne.
func _select_rivals() -> void:
	rival_lords = []
	act_faction = []
	finale_rival = ""
	var exclude: String = current_hero_id if HeroDB.has_hero(current_hero_id) \
		else HeroDB.DEFAULT_HERO
	var pool: Array = []
	for hid in HeroDB.HERO_ORDER:
		if hid != exclude:
			pool.append(hid)
	if pool.size() < ACTS + 1:
		# Roster shrank below 5 — leave rivals empty; map gen and boss wiring
		# fall back to the legacy unfiltered pools.
		push_warning("RunState: rival pool too small (%d), running legacy bosses" % pool.size())
		return
	var rng := RandomNumberGenerator.new()
	# Sub-seed (same trick as _generate_act_map) so the rival deal and the map
	# generator draw from independent streams of the same run seed.
	rng.seed = run_seed ^ 0x52495641
	CampaignMapGenerator.shuffle_array(pool, rng)
	for i in range(ACTS):
		rival_lords.append(String(pool[i]))
		act_faction.append(HeroDB.get_faction(String(pool[i])))
	finale_rival = String(pool[ACTS])


## Pure rival deal for THE MUSTER preview. It deliberately mirrors
## _select_rivals' sub-seed and shuffle; the focused probe compares both sides
## so a future drift cannot ship a false preview.
static func preview_rival_deal(hero_id: String, seed_value: int) -> Dictionary:
	var exclude: String = hero_id if HeroDB.has_hero(hero_id) else HeroDB.DEFAULT_HERO
	var pool: Array = []
	for hid in HeroDB.HERO_ORDER:
		if hid != exclude:
			pool.append(hid)
	if pool.size() < ACTS + 1:
		return {"rival_lords": [], "act_faction": [], "finale_rival": ""}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x52495641
	CampaignMapGenerator.shuffle_array(pool, rng)
	var rivals: Array[String] = []
	var factions: Array[String] = []
	for i in range(ACTS):
		var hid := String(pool[i])
		rivals.append(hid)
		factions.append(HeroDB.get_faction(hid))
	return {
		"rival_lords": rivals, "act_faction": factions,
		"finale_rival": String(pool[ACTS]),
	}


# Season winds source data. Pool = the six live tribes; names are the prose
# forms the announce line uses (COPY_STYLE: name things plainly).
const SEASON_TRIBE_POOL: Array = ["soldier", "beast", "dead", "warlock", "bastion", "stray"]
const SEASON_TRIBE_NAMES := {"soldier": "Soldiers", "beast": "Beasts",
	"dead": "the Dead", "warlock": "Warlocks", "bastion": "Bastions", "stray": "Strays"}


## Deal the run's season: two distinct tribes muster strong. Sub-seeded off
## run_seed (same trick as _select_rivals) so seeded/daily runs reproduce it.
func _roll_season() -> void:
	season_tribes = preview_season_tribes(run_seed, current_banner_tribe)


## Pure season deal shared by preview and commit. A valid declaration is fixed
## in slot zero; the war deals a different second tribe from the same sub-seed.
static func preview_season_tribes(seed_value: int, declared_tribe: String = "") -> Array:
	var pool: Array = SEASON_TRIBE_POOL.duplicate()
	var declared := declared_tribe if declared_tribe in SEASON_TRIBE_POOL else ""
	if declared != "":
		pool.erase(declared)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5345534F
	CampaignMapGenerator.shuffle_array(pool, rng)
	if declared != "":
		return [declared, pool[0]]
	return [pool[0], pool[1]]



## The announce sentence for the war chest / muster screens. "" when no
## season is dealt (legacy save) so call sites can simply hide the label.
func season_line() -> String:
	if season_tribes.size() < 2:
		return ""
	var a: String = String(SEASON_TRIBE_NAMES.get(season_tribes[0], season_tribes[0]))
	var b: String = String(SEASON_TRIBE_NAMES.get(season_tribes[1], season_tribes[1]))
	return "This season, %s and %s appear more often at Recruit Camps." % [a, b]


## Format a pending season without mutating the live run.
static func season_line_for(tribes: Array) -> String:
	if tribes.size() < 2:
		return ""
	var a: String = String(SEASON_TRIBE_NAMES.get(tribes[0], tribes[0]))
	var b: String = String(SEASON_TRIBE_NAMES.get(tribes[1], tribes[1]))
	return "This season, %s and %s appear more often at Recruit Camps." % [a, b]


## Faction id of the kingdom the current act takes place in ("" on legacy
## runs with no rival deal — callers treat that as "no faction filter").
func get_act_faction() -> String:
	if current_act_idx < act_faction.size():
		return act_faction[current_act_idx]
	return ""


## The rival lord (hero id) ruling the current act's kingdom, "" on legacy runs.
func get_act_rival() -> String:
	if current_act_idx < rival_lords.size():
		return rival_lords[current_act_idx]
	return ""


## Every still-living rival offered by THE NEXT MARCH. Completed act slots are
## excluded; the provisional finale is included so the player never makes a
## fake two-way choice while a third living kingdom is silently withheld.
func get_next_march_candidates() -> Array[String]:
	var out: Array[String] = []
	var next_idx := current_act_idx + 1
	for i in range(next_idx, rival_lords.size()):
		var lord := String(rival_lords[i])
		if lord != "" and lord != current_hero_id and not out.has(lord):
			out.append(lord)
	if finale_rival != "" and finale_rival != current_hero_id \
			and not out.has(finale_rival):
		out.append(finale_rival)
	return out


## Choose which living rival rules the next act. Choosing the provisional
## finale swaps the displaced next-act lord onto the throne. Then all untouched
## future acts are re-dealt from their now-current factions, not just new bosses.
func choose_next_rival(hero_id: String) -> void:
	var next_idx := current_act_idx + 1
	var candidates := get_next_march_candidates()
	if next_idx < 0 or next_idx >= rival_lords.size() \
			or not candidates.has(hero_id):
		push_warning("RunState: choose_next_rival('%s') not in living deal" % hero_id)
		return

	var displaced := String(rival_lords[next_idx])
	var road_idx := -1
	for i in range(next_idx, rival_lords.size()):
		if rival_lords[i] == hero_id:
			road_idx = i
			break
	if road_idx >= 0:
		rival_lords[next_idx] = hero_id
		rival_lords[road_idx] = displaced
	elif finale_rival == hero_id:
		rival_lords[next_idx] = hero_id
		finale_rival = displaced

	_sync_act_factions()
	_redeal_untouched_future_acts(next_idx)


func _sync_act_factions() -> void:
	act_faction = []
	for lord in rival_lords:
		act_faction.append(HeroDB.get_faction(String(lord)))


## Re-deal only the future maps nobody has entered. The sub-seed depends on
## run seed + act + ruler, so identical choices survive save/resume exactly.
func _redeal_untouched_future_acts(first_idx: int) -> void:
	var last_idx := mini(map_data.size(), rival_lords.size())
	var generator = _make_map_generator()
	for act_idx in range(first_idx, last_idx):
		if not _act_map_is_untouched(act_idx):
			push_warning("RunState: future act %d already touched; encounter deal preserved" \
				% (act_idx + 1))
			continue
		var faction := String(act_faction[act_idx])
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed ^ 0x4D415243 ^ ((act_idx + 1) * 7919) \
			^ seed_from_string("kingdom:" + faction)
		generator.redeal_encounters(map_data[act_idx], act_idx + 1, rng)
		map_plate_cache.erase(act_idx + 1)


func _act_map_is_untouched(act_idx: int) -> bool:
	if act_idx < 0 or act_idx >= map_data.size():
		return false
	for row in map_data[act_idx]:
		for node in row:
			if bool(node.get("visited", false)):
				return false
	return true


## Compatibility helper for diagnostics that only restamp one boss. Normal
## THE NEXT MARCH flow uses _redeal_untouched_future_acts above.
func _rebake_boss_node(act_idx: int) -> void:
	if act_idx < 0 or act_idx >= map_data.size():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ (0x424F5353 + act_idx)
	for row in map_data[act_idx]:
		for node in row:
			if String(node.get("type", "")) == "boss":
				node["encounter_id"] = _make_map_generator().boss_encounter_for_act(
					act_idx + 1, rng)
				return


func end_run(victorious: bool) -> void:
	run_active = false
	_append_run_log(victorious)
	PlayLog.end_session({"result": "victory" if victorious else "defeat",
		"act": get_act(), "floor": current_floor, "fights_won": fights_won})
	clear_save()  # save only persists in-progress runs; ended ones are gone
	if victorious:
		MetaState.record_victory()
	else:
		MetaState.record_defeat()


## Local balance telemetry: one CSV row per finished run (user://runs.csv).
## Turns playtests into data — where runs die, on what, with which hero —
## instead of vibes. Local file only; never leaves the machine.
## The rival columns feed the Successor Wars matchup matrix (the project's
## dominant balancing cost): every dev run records who was marched on, in
## what order, who was spared, and how many holds the act had fallen.
const _RUN_LOG_HEADER: String = ("ended_at,result,hero,ascension,seed,act," +
	"floor,hp,max_hp,gold,fights_won,deck_size,relics,cause_of_death," +
	"rival_act1,rival_act2,rival_act3,finale_rival,holds_broken_run")


func _append_run_log(victorious: bool) -> void:
	var path := "user://runs.csv"
	# Schema change (rival columns): a file written with the old header can't
	# take the new rows — shelve it under a timestamped name and start fresh
	# rather than mixing two schemas in one CSV.
	if FileAccess.file_exists(path):
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe != null:
			var first_line := probe.get_line()
			probe.close()
			if first_line != _RUN_LOG_HEADER:
				DirAccess.rename_absolute(ProjectSettings.globalize_path(path),
					ProjectSettings.globalize_path("user://runs_legacy_%d.csv"
						% int(Time.get_unix_time_from_system())))
	var exists := FileAccess.file_exists(path)
	var f := FileAccess.open(path,
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		return
	if exists:
		f.seek_end()
	else:
		f.store_line(_RUN_LOG_HEADER)
	var r1: String = rival_lords[0] if rival_lords.size() > 0 else ""
	var r2: String = rival_lords[1] if rival_lords.size() > 1 else ""
	var r3: String = rival_lords[2] if rival_lords.size() > 2 else ""
	f.store_line("%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%d" % [
		Time.get_datetime_string_from_system(),
		"victory" if victorious else "defeat",
		current_hero_id, current_ascension, run_seed,
		get_act(), current_floor, hero_hp, hero_max_hp, gold,
		fights_won, deck.size(), relics.size(),
		cause_of_death.replace(",", ";"),
		r1, r2, r3, finale_rival, holds_broken_run])
	f.close()


# ── Deck manipulation ──

func add_card(id: String) -> int:
	deck.append(id)
	var uid = _next_uid
	deck_uids.append(uid)
	_next_uid += 1
	PlayLog.log_event("deck_add", {"id": id, "uid": uid})
	return uid


func remove_card_at(index: int) -> bool:
	if index < 0 or index >= deck.size():
		return false
	var uid = deck_uids[index]
	PlayLog.log_event("deck_remove", {"id": deck[index], "uid": uid})
	deck.remove_at(index)
	deck_uids.remove_at(index)
	card_upgrades.erase(uid)
	# The Sin-Eater's Crust (event relic): every card that leaves the deck
	# feeds you. All removal paths — events, shop service, wayside scales,
	# curse-eating — funnel through here, so this is the one hook site.
	if has_relic("sin_eaters_crust"):
		heal_hero(int(RelicDB.get_relic("sin_eaters_crust").get("value", 3)))
	return true


# ── Card upgrades (Inscryption model: mods STACK) ──
# card_upgrades[uid] is an ordered Array of mod entries ({path, keyword, ...}).
# A card can be drilled, carry a transferred keyword, AND be forged — every
# entry folds into the card data in the order it was earned. The only
# per-path cap is "plus" (a card has exactly one hand-crafted + version) and
# the drill's own DRILL_MAX_STACKS; callers gate those via has_upgrade_path /
# get_upgrade_entry, not via "is the card touched at all".

func upgrade_card(deck_index: int, path: String, keyword: String = "") -> void:
	if deck_index < 0 or deck_index >= deck_uids.size():
		return
	PlayLog.log_event("card_upgrade", {
		"id": deck[deck_index] if deck_index < deck.size() else "",
		"path": path, "keyword": keyword})
	_append_upgrade(deck_uids[deck_index], {"path": path, "keyword": keyword})


func get_card_upgrades(deck_index: int) -> Array:
	if deck_index < 0 or deck_index >= deck_uids.size():
		return []
	return card_upgrades.get(deck_uids[deck_index], [])


## True if any entry in the card's mod stack uses `path`.
func has_upgrade_path(deck_index: int, path: String) -> bool:
	for entry in get_card_upgrades(deck_index):
		if String(entry.get("path", "")) == path:
			return true
	return false


## First entry with the given path ({} if none) — the drill reads its banked
## stacks back through this.
func get_upgrade_entry(deck_index: int, path: String) -> Dictionary:
	for entry in get_card_upgrades(deck_index):
		if String(entry.get("path", "")) == path:
			return entry
	return {}


## Wayside verbs write richer upgrade entries than upgrade_card's
## path+keyword pair. Entries append to the card's mod stack; the drill is
## the one exception — it carries a TOTAL stacks counter, so a new drill
## entry replaces the previous drill entry instead of stacking beside it.
func apply_wayside_upgrade(deck_index: int, entry: Dictionary) -> void:
	if deck_index < 0 or deck_index >= deck_uids.size():
		return
	PlayLog.log_event("card_upgrade", {
		"id": deck[deck_index] if deck_index < deck.size() else "", "wayside": entry})
	var uid = deck_uids[deck_index]
	if String(entry.get("path", "")) == "drill":
		var stack: Array = card_upgrades.get(uid, [])
		for i in range(stack.size()):
			if String(stack[i].get("path", "")) == "drill":
				stack[i] = entry
				return
	_append_upgrade(uid, entry)


func _append_upgrade(uid: int, entry: Dictionary) -> void:
	if not card_upgrades.has(uid):
		card_upgrades[uid] = []
	card_upgrades[uid].append(entry)


## The Undying: every death writes a permanent +1/+1 against the card's uid.
## Same replace-in-place shape as the drill entry — one "undying" entry whose
## stacks counter grows, so the mod stack never floods with duplicates.
func grow_undying(uid: int) -> void:
	if uid < 0:
		return
	var stack: Array = card_upgrades.get(uid, [])
	for i in range(stack.size()):
		if String(stack[i].get("path", "")) == "undying":
			stack[i]["stacks"] = int(stack[i].get("stacks", 1)) + 1
			return
	_append_upgrade(uid, {"path": "undying", "stacks": 1})


## True if the card carries ANY mod. Callers that used this to mean
## "already forged" now ask has_upgrade_path(i, "plus") instead.
func is_card_upgraded(deck_index: int) -> bool:
	return not get_card_upgrades(deck_index).is_empty()


# ── Campaign memory (docs/CAMPAIGN_MEMORY.md) ────────────────────────────────

## Tally a combat kill against a creature's service record. Returns the new
## total so the caller can fire milestone moments (BLOODED / VETERAN).
func record_kill(uid: int) -> int:
	if uid < 0:
		return 0
	creature_kills[uid] = int(creature_kills.get(uid, 0)) + 1
	return creature_kills[uid]


func get_kills(uid: int) -> int:
	return int(creature_kills.get(uid, 0))


func veteran_epithet_kills() -> int:
	return 2 if has_relic("drill_book") else VETERAN_EPITHET_KILLS


## The war school now rides the epithet rung — deliberately the SAME accessor, so
## every existing call site (the tally line, the catch-up sweep, the kill handler)
## moved with the ladder in one edit instead of thirteen.
func veteran_school_kills() -> int:
	return veteran_epithet_kills()


## The tribe doctrine takes over the threshold the school vacated, drill_book
## shave included, so the relic still shortens the whole ladder rather than only
## its front half.
func veteran_doctrine_kills() -> int:
	return 7 if has_relic("drill_book") else VETERAN_DOCTRINE_KILLS


## The creature's earned name at VETERAN_EPITHET_KILLS — deterministic per uid
## so it never rerolls across save/load or re-draws.
func veteran_epithet(uid: int) -> String:
	return VETERAN_EPITHETS[absi(hash(uid)) % VETERAN_EPITHETS.size()]


## Write one fall into the Roll of the Fallen. `name` is the name as worn at
## death (epithet included); `enc` is the encounter's display name.
func record_fall(uid: int, card_id: String, name: String, enc: String, round_no: int) -> void:
	fallen.append({
		"uid": uid, "id": card_id, "name": name,
		"enc": enc, "act": get_act(), "round": round_no,
	})
	PlayLog.log_event("creature_fall", {"id": card_id, "uid": uid, "enc": enc})


func get_upgraded_card_data(deck_index: int) -> Dictionary:
	if deck_index < 0 or deck_index >= deck.size():
		return {}
	var base = CardDB.get_card_data(deck[deck_index])
	var stack := get_card_upgrades(deck_index)
	var uid: int = deck_uids[deck_index] if deck_index < deck_uids.size() else -1
	var kills: int = get_kills(uid)
	if stack.is_empty() and kills <= 0:
		return base
	var d = base.duplicate(true)
	var forged := false
	for entry in stack:
		d = _apply_upgrade(d, entry)
		if String(entry.get("path", "")) == "plus":
			forged = true
	# Campaign memory: the service record rides the card data so every consumer
	# (Combat draw, deck viewers, Rest, events) shows it for free. Tally
	# scratches from kill 1 (Card2D reads veteran_kills), the earned name at 3,
	# the veteran's +1/+1 at 6 — folded BEFORE the " +" suffix so a forged
	# veteran reads "Pikeman the Grim +". The 10-kill war school is NOT here:
	# it's a chosen keyword, so it lives as a "war_school" entry in the mod
	# stack (folded above with the other upgrades).
	if kills > 0 and d.get("type", "") == "creature":
		d["veteran_kills"] = kills
		if kills >= veteran_epithet_kills():
			d.name = String(d.name) + " " + veteran_epithet(uid)
			# Letters Patent relic: the epithet comes with a grant of arms —
			# +1/+1, folded here so every future draw wears the knighthood.
			if has_relic("letters_patent"):
				d.atk = int(d.get("atk", 0)) + 1
				d.hp = int(d.get("hp", 1)) + 1
		if kills >= VETERAN_RANK_KILLS:
			d.atk = int(d.get("atk", 0)) + 1
			d.hp = int(d.get("hp", 1)) + 1
	# The " +" suffix marks the FORGED state specifically — wayside drills and
	# transferred banners show in the stats/keywords, not the name.
	if forged:
		d.name = d.name + " +"
	return d


# Folds ONE mod entry into card data. Called per stack entry by
# get_upgraded_card_data, which owns the duplicate() and the " +" suffix —
# this function mutates and returns the dict it's given.
func _apply_upgrade(d: Dictionary, upgrade: Dictionary) -> Dictionary:
	var bonus = 3 if has_relic("blacksmiths_hammer") else 2
	match upgrade.path:
		"plus":
			# Per-card "+" upgrade. Reads CardDB.UPGRADES and merges every
			# defined delta into the card data. Blacksmith's Hammer bumps
			# stat-style deltas by +1 (so a Brute+ goes from +1/+1 to +2/+2),
			# matching the way the relic boosted the legacy Sharpen/Fortify
			# paths. The is_upgraded flag is read by Combat.gd custom-spell
			# resolvers (dmg_bonus, slay_draw, etc.) and by Card2D to pick
			# the upgraded rarity tint.
			d = _apply_plus_upgrade(d)
		"sharpen":
			if d.type == "creature":
				d.atk += bonus
			else:
				if d.has("spell") and d.spell.has("value"):
					d.spell.value += bonus
		"fortify":
			if d.type == "creature":
				d.hp += bonus
			else:
				d.cost = maxi(0, d.cost - 1)
		"fortify_neg":
			# Event-only "negative fortify" — used by the debuff_starters event
			# (Event.gd:420) to drop a starter creature's max HP by 1 permanently.
			# Floored at 1 so we never store a non-positive HP that would crash
			# combat (a 0-hp card would die instantly on placement).
			if d.type == "creature":
				d.hp = maxi(1, d.hp - 1)
		"drill":
			# Drill Yard wayside: +1/+1 per completed drill pass (stacks live
			# in the upgrade entry — push-your-luck writes the same slot).
			if d.type == "creature":
				var st: int = int(upgrade.get("stacks", 1))
				d.atk += st
				d.hp += st
		"undying":
			# The Undying: +1/+1 per recorded death (grow_undying writes the
			# stacks; combat's on-death dispatch is the only author).
			if d.type == "creature":
				var ust: int = int(upgrade.get("stacks", 1))
				d.atk += ust
				d.hp += ust
		"grant_kw":
			# Standard-Bearer wayside, receiving end: the banner passes on.
			if d.type == "creature" and String(upgrade.get("keyword", "")) != "" \
					and not d.keywords.has(upgrade.keyword):
				d.keywords.append(upgrade.keyword)
		"war_school":
			# Veterancy rung 1 (3 kills, was 10): the keyword the player CHOSE for
			# this soldier. Same fold as grant_kw; a separate path so "already
			# schooled" is unambiguous (a transferred banner must not eat the
			# rung). An empty keyword is the honorary rank — the veteran already
			# carried all three schools when the choice came up.
			if d.type == "creature" and String(upgrade.get("keyword", "")) != "" \
					and not d.keywords.has(upgrade.keyword):
				d.keywords.append(upgrade.keyword)
		"doctrine":
			# Veterancy rung 3 (10 kills): the second chosen keyword, drawn from
			# this creature's OWN tribe's doctrine rather than from the universal
			# three. Folded identically and kept on its own path for the same
			# reason war_school is — so "already has a doctrine" is a question with
			# an unambiguous answer, and a school pick can never satisfy it.
			if d.type == "creature" and String(upgrade.get("keyword", "")) != "" \
					and not d.keywords.has(upgrade.keyword):
				d.keywords.append(upgrade.keyword)
		"strip_kw":
			# Standard-Bearer wayside, giving end: the bearer marches plainer.
			if d.type == "creature":
				var stripped_kw := String(upgrade.get("keyword", ""))
				d.keywords.erase(stripped_kw)
				if stripped_kw == "sniper":
					d.erase("sniper")
		"butcher":
			# Butcher event payoff: +2 ATK and Wither 1 on a creature. The Event
			# screen advertises both halves — previously we only applied the ATK
			# half via the "sharpen" path so the downside was free-skipped.
			if d.type == "creature":
				d.atk += 2
				if not d.keywords.has("wither"):
					d.keywords.append("wither")
				d.wither = maxi(1, int(d.get("wither", 0)))
		"mirror_twin":
			# Mirror-Twin event payoff: a glass-cannon trade — HP drops to 1, ATK
			# gains a flat +4. Capped (not "ATK += old HP") so a 2/10 wall can't
			# become a 12/1 freight train; this stays a calculated risk, not an
			# auto-pick on tank cards.
			if d.type == "creature":
				d.atk += 4
				d.hp = 1
		"imbue":
			if d.type == "creature":
				var kw = upgrade.get("keyword", "")
				if kw != "" and not d.keywords.has(kw):
					d.keywords.append(kw)
			else:
				var kw = upgrade.get("keyword", "")
				if kw == "retain":
					if not d.keywords.has("retain"):
						d.keywords.append("retain")
				else:
					# "Double effect + Exhaust" — only apply the Exhaust downside
					# when the doubling actually landed. Custom spells (Echo,
					# War Chant, Reanimate, etc.) don't read spell.value, so they
					# can't be doubled — and giving them Exhaust without the
					# upside was strictly worse than skipping the upgrade.
					var doubled := false
					if d.has("spell") and d.spell.has("value"):
						d.spell.value *= 2
						doubled = true
					if doubled and not d.keywords.has("exhaust"):
						d.keywords.append("exhaust")
	return d


# Applies a CardDB.UPGRADES delta to a card's data dict. Every field is
# optional; missing fields silently no-op. Stat deltas (atk/hp) get +1 from
# Blacksmith's Hammer; numeric sub-effect bumps and dmg_bonus do not — those
# are tuned per-card and should stay at their authored value.
# Public preview of the "+" upgrade for a given card data dict, used by the
# Rest screen to render the comparison without mutating deck state. Pure
# function — caller passes a copy or accepts that the return shares no refs
# with the input (we deep-duplicate before merging). Mirrors the " +" name
# suffix that _apply_upgrade tacks on for live cards so the preview matches.
func preview_plus_upgrade(data: Dictionary) -> Dictionary:
	var out: Dictionary = _apply_plus_upgrade(data.duplicate(true))
	out.name = String(out.get("name", "")) + " +"
	return out


func _apply_plus_upgrade(d: Dictionary) -> Dictionary:
	var card_id: String = String(d.get("id", ""))
	var u: Dictionary = CardDB.get_plus_upgrade(card_id)
	if u.is_empty():
		return d
	var stat_bonus: int = 1 if has_relic("blacksmiths_hammer") else 0
	# Creature stats
	if d.get("type", "") == "creature":
		if u.has("atk"):
			d.atk = maxi(0, int(d.get("atk", 0)) + int(u.atk) + (stat_bonus if int(u.atk) > 0 else 0))
		if u.has("hp"):
			d.hp = maxi(1, int(d.get("hp", 1)) + int(u.hp) + (stat_bonus if int(u.hp) > 0 else 0))
		if u.has("adj_buff_atk") and d.has("adj_buff"):
			d.adj_buff.atk = int(d.adj_buff.get("atk", 0)) + int(u.adj_buff_atk)
		if u.has("adj_buff_hp") and d.has("adj_buff"):
			d.adj_buff.hp = int(d.adj_buff.get("hp", 0)) + int(u.adj_buff_hp)
		if u.has("wither"):
			d.wither = maxi(0, int(d.get("wither", 0)) + int(u.wither))
		if u.has("extra_damage"):
			d.extra_damage = int(d.get("extra_damage", 0)) + int(u.extra_damage)
		if u.has("on_enter_value") and d.has("on_enter") and d.on_enter.has("value"):
			d.on_enter.value = int(d.on_enter.value) + int(u.on_enter_value)
		if u.has("on_death_value") and d.has("on_death") and d.on_death.has("value"):
			d.on_death.value = int(d.on_death.value) + int(u.on_death_value)
		if u.has("on_death_atk") and d.has("on_death") and d.on_death.has("atk"):
			d.on_death.atk = int(d.on_death.atk) + int(u.on_death_atk)
		if u.has("on_death_hp") and d.has("on_death") and d.on_death.has("hp"):
			d.on_death.hp = int(d.on_death.hp) + int(u.on_death_hp)
		if u.has("on_play_value") and d.has("on_play") and d.on_play.has("value"):
			d.on_play.value = int(d.on_play.value) + int(u.on_play_value)
		if u.has("on_play_atk_gain") and d.has("on_play") and d.on_play.has("atk_gain"):
			d.on_play.atk_gain = int(d.on_play.atk_gain) + int(u.on_play_atk_gain)
		if u.has("on_play_atk") and d.has("on_play") and d.on_play.has("atk"):
			d.on_play.atk = int(d.on_play.atk) + int(u.on_play_atk)
		if u.has("on_play_hp") and d.has("on_play") and d.on_play.has("hp"):
			d.on_play.hp = int(d.on_play.hp) + int(u.on_play_hp)
		if u.has("on_play_heal") and d.has("on_play") and d.on_play.has("heal"):
			d.on_play.heal = int(d.on_play.heal) + int(u.on_play_heal)
	# Cost (any card)
	if u.has("cost"):
		d.cost = maxi(0, int(d.get("cost", 0)) + int(u.cost))
	# Spell value (non-custom spells with a value field)
	if u.has("value") and d.has("spell") and d.spell.has("value"):
		d.spell.value = int(d.spell.value) + int(u.value)
	# Keywords add/remove
	if u.has("add_keywords"):
		var kw_list: Array = d.get("keywords", [])
		for kw in u.add_keywords:
			if not kw_list.has(kw):
				kw_list.append(kw)
		d.keywords = kw_list
	if u.has("remove_keywords"):
		var kw_list2: Array = d.get("keywords", [])
		for kw in u.remove_keywords:
			kw_list2.erase(kw)
			if String(kw) == "sniper":
				d.erase("sniper")
		d.keywords = kw_list2
	# Keyword tick value (e.g. Rampage N) — additive, consulted by the rider that
	# reads card_data.rampage directly (it doesn't check is_upgraded).
	if u.has("rampage"):
		d.rampage = maxi(1, int(d.get("rampage", 1)) + int(u.rampage))
	# Tail-effect bonus fields that custom resolvers consult by name. These
	# only matter if the card's resolver reads them — declaring them here is
	# free for cards that don't (it's just a no-op merge).
	for k in ["dmg_bonus", "slay_draw", "slay_gold", "slay_mana", "atk_bonus",
			"hp_bonus", "spell_ping_bonus", "extra_reveal", "doom_atk_bonus", "doom_tick",
			"extra_draw", "extra_mana", "ricochet_hits"]:
		if u.has(k):
			d[k] = int(u[k])
	# Description override — applied last so it wins over any auto-generated
	# desc. Card2D reads card_data.desc verbatim.
	if u.has("desc"):
		d.desc = String(u.desc)
	# Flag for Card2D / Combat to detect the upgrade visually + behaviorally.
	d.is_upgraded = true
	return d


# ── Relic manipulation ──

func add_relic(id: String) -> void:
	if relics.has(id):
		return
	relics.append(id)
	PlayLog.log_event("relic_add", {"id": id})
	# Central pickup cue — every grant path (treasure, shop, reward, events)
	# funnels through here. No-ops until assets/audio/sfx/relic_get/ has files.
	if AudioBank != null:
		AudioBank.play_sfx("relic_get")
	_apply_relic_on_acquire(id)


# Side effects that fire the moment a relic enters the player's collection.
# Lives here (not in Combat.gd) so Reward / Shop / Treasure / Event all share
# the same logic. Keep this branch SMALL — most relics react to combat hooks,
# not acquisition, and belong in Combat.gd instead.
func _apply_relic_on_acquire(id: String) -> void:
	match id:
		"pandoras_box":
			_pandoras_box_transform()
		"calling_bell":
			_calling_bell_grant()
		"recruiters_horn":
			# Fill the Muster reroll pool. The relic's `value` is the single
			# source of truth for "how many" — desc and grant stay in sync.
			muster_rerolls_left = int(RelicDB.get_relic(id).get("value", 3))
		# totem_pole / bone_hourglass deliberately do NOTHING on acquire: their
		# "each act, pick" choice is prompted by the MapView picker at the start of
		# every act (see MapView._resolve_meta_pickers). bottled_talisman likewise
		# binds via a picker (acquire screen or MapView catch-all), not here.


func _pandoras_box_transform() -> void:
	# Replace every starter-rarity CREATURE in the deck with a random rare
	# creature id. Spells and any later additions (commons/uncommons/rares,
	# curses, tokens) are untouched so the deck stops looking like "hero starter".
	# card_upgrades is keyed by deck_uid: erase the entry for each replaced
	# slot so prior upgrade payloads don't carry onto the new card identity.
	var rare_creatures: Array[String] = []
	for cid in CardDB.get_pool_by_rarity("rare"):
		if CardDB.get_card_data(cid).get("type", "") == "creature":
			rare_creatures.append(cid)
	if rare_creatures.is_empty():
		return
	var transformed := 0
	for i in deck.size():
		var entry: String = deck[i]
		var data: Dictionary = CardDB.get_card_data(entry)
		if data.get("type", "") == "creature" and data.get("rarity", "") == "starter":
			deck[i] = rare_creatures[randi() % rare_creatures.size()]
			card_upgrades.erase(deck_uids[i])
			transformed += 1
	# Selling every starter before finding the Coffer should not turn a boss
	# reward into blank cardboard. Its floor is one new rare body.
	if transformed == 0:
		add_card(rare_creatures[randi() % rare_creatures.size()])


func _calling_bell_grant() -> void:
	# Roll up to 3 boss relics the player doesn't already own and add them
	# directly (no UI pick — this IS the payoff). Recurses through add_relic
	# so each rolled relic gets its OWN acquire-side-effect chance. Then
	# pad the deck with 3 random curses as the cost.
	var picks: Array[String] = RelicDB.roll_boss_relics(relics, current_hero_id)
	for new_id in picks:
		add_relic(new_id)
	for _i in 3:
		add_card(CardDB.random_curse_id())


func has_relic(id: String) -> bool:
	return relics.has(id)


## Spend one Muster reroll charge (Recruiter's Horn). Returns true if a charge
## was available and consumed, false if the pool is empty. The Muster gates the
## reroll button on `muster_rerolls_left > 0`, so this only fails on a race.
func use_muster_reroll() -> bool:
	if muster_rerolls_left <= 0:
		return false
	muster_rerolls_left -= 1
	return true


# ── Hero HP ──

func damage_hero(amount: int) -> void:
	hero_hp = maxi(0, hero_hp - amount)


func heal_hero(amount: int) -> void:
	hero_hp = mini(hero_max_hp, hero_hp + amount)


func gain_gold(amount: int) -> void:
	if has_downside("no_gold"):
		return
	gold += amount


func record_event_choice(flag: String) -> void:
	var clean := flag.strip_edges()
	if clean.is_empty() or event_choice_flags.has(clean):
		return
	event_choice_flags.append(clean)


func has_event_choice(flag: String) -> bool:
	var clean := flag.strip_edges()
	return not clean.is_empty() and event_choice_flags.has(clean)


## Jittered fight reward (±25% around `base`) so payouts land on odd numbers, not fixed amounts.
func roll_gold_reward(base: int) -> int:
	var spread: int = int(round(base * 0.25))
	return base + randi_range(-spread, spread)


func get_max_mana() -> int:
	return base_max_mana + RelicDB.get_boss_mana_bonus(relics)


func has_downside(downside: String) -> bool:
	return RelicDB.has_downside(relics, downside)


# ── Potions ──

func can_add_potion() -> bool:
	return potions.size() < MAX_POTIONS and not has_downside("no_potions")


func add_potion(id: String) -> bool:
	if not can_add_potion():
		return false
	if not PotionDB.POTIONS.has(id):
		push_warning("RunState.add_potion: unknown id '%s'" % id)
		return false
	potions.append(id)
	PlayLog.log_event("potion_add", {"id": id})
	return true


func consume_potion(index: int) -> String:
	## Removes and returns the potion id at `index`. Used by callers that
	## resolve the effect themselves (Combat has gameplay context; MapView
	## handles map-applicable effects). Returns "" if index is invalid.
	if index < 0 or index >= potions.size():
		return ""
	var id: String = potions[index]
	potions.remove_at(index)
	# Central drink cue — Combat and MapView both consume through here.
	# No-ops until assets/audio/sfx/potion_use/ has files.
	if AudioBank != null:
		AudioBank.play_sfx("potion_use")
	return id


func first_potion_index(id: String) -> int:
	return potions.find(id)


# ── Map navigation ──

func get_current_act_map() -> Array:
	if current_act_idx < map_data.size():
		return map_data[current_act_idx]
	return []


func get_available_nodes() -> Array:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return []
	if map_position.row == -1:
		return act_map[0].duplicate()
	var row: int = map_position.row
	var col: int = map_position.col
	if row >= act_map.size():
		return []
	var current_node: Dictionary = _find_node_by_col(act_map[row], col)
	if current_node.is_empty():
		return []
	var next_row: int = row + 1
	if next_row >= act_map.size():
		return []
	var available: Array = []
	for target_col in current_node.connections:
		var n = _find_node_by_col(act_map[next_row], target_col)
		if not n.is_empty():
			# The boss gate: the keep stays painted on the plate but its road
			# doesn't open until enough holds have fallen. Filtering here is
			# the single source of truth — buttons, road tint, and the pulse
			# overlay all read availability from this list. No softlock:
			# _generate_act_map guarantees every route carries enough fights.
			if String(n.type) == "boss" and not is_lord_gate_open():
				continue
			available.append(n)
	var boss_node := get_lord_node()
	if is_lord_gate_open() and not boss_node.is_empty() \
			and not bool(boss_node.get("visited", false)) \
			and int(boss_node.get("row", BOSS_ROW)) > row:
		var already := false
		for n in available:
			if int(n.get("row", -99)) == int(boss_node.get("row", -1)) \
					and int(n.get("col", -99)) == int(boss_node.get("col", -1)):
				already = true
				break
		if not already:
			available.append(boss_node)
	return available


func visit_node(row: int, col: int) -> void:
	var act_map = get_current_act_map()
	if act_map.is_empty():
		return
	map_position = {"row": row, "col": col}
	for n in act_map[row]:
		if n.col == col:
			n.visited = true
			current_node_type = n.type
			current_encounter_id = n.get("encounter_id", "")
			PlayLog.log_event("map_visit", {"row": row, "col": col,
				"node_type": current_node_type, "encounter": current_encounter_id})
			current_mutator_id = n.get("mutator_id", "")
			current_terrain = String(n.get("terrain", ""))
			current_bridge = bool(n.get("bridge", false))
			current_wayside_id = String(n.get("wayside_id", ""))
			current_setpiece_id = String(n.get("setpiece_id", ""))
			current_floor += 1
			save_run()  # checkpoint: player is committing to enter a room
			return


func _find_node_by_col(row_nodes: Array, col: int) -> Dictionary:
	for n in row_nodes:
		if n.col == col:
			return n
	return {}


## Phase 2.5 — once the plate has tagged this act's holds with terrain
## (MapTerrain._derive_terrain_tags, first open of the act), re-DEAL the
## already-dealt encounters onto terrain-matching nodes. The multiset of
## fights never changes — the player meets the same kits either way — they
## just land on coherent ground: ambush kits in the woods, armor on the
## pass, doom in the ash, the lightest deal on the meadow road. Pure
## function of (dealt multiset, tags): greedy over a total order, no RNG,
## so re-running it is idempotent. Gated to untouched acts so a mid-act
## save from before tagging never shuffles fights the player has already
## scouted via tooltips.
func apply_terrain_redeal() -> void:
	var act_map := get_current_act_map()
	if act_map.is_empty():
		return
	for row in act_map:
		for n in row:
			if bool(n.get("visited", false)):
				return
	var order := {"ash": 0, "woods": 1, "pass": 2, "meadow": 3}
	for node_type in ["combat", "elite"]:
		var nodes: Array = []
		for row in act_map:
			for n in row:
				if String(n.get("type", "")) == node_type \
						and String(n.get("terrain", "")) != "" \
						and String(n.get("encounter_id", "")) != "":
					nodes.append(n)
		if nodes.size() < 2:
			continue
		var pool: Array = []
		for n in nodes:
			pool.append(String(n.encounter_id))
		# Stage 0 (combat only) — the landing is always light: row-0 holds
		# take the lightest kits in the deal outright, terrain be damned.
		# The act opens like an invasion (skirmishes at the beachhead) and
		# the heavy deals are pushed up-road by construction.
		var rest_nodes: Array = []
		if node_type == "combat":
			var landing: Array = []
			for n in nodes:
				if int(n.row) == 0:
					landing.append(n)
				else:
					rest_nodes.append(n)
			landing.sort_custom(func(a, b): return int(a.col) < int(b.col))
			for n in landing:
				var li := 0
				for i in range(pool.size()):
					var wi: int = EncounterDB.kit_weight(pool[i])
					var wl: int = EncounterDB.kit_weight(pool[li])
					if wi < wl or (wi == wl and pool[i] < pool[li]):
						li = i
				n["encounter_id"] = pool[li]
				pool.remove_at(li)
		else:
			rest_nodes = nodes
		# Stage 1 — terrain claims the rest: ash holds pick first (rarest
		# ground, loudest theme), then woods, pass, meadow; (row, col)
		# breaks ties so the order is total.
		rest_nodes.sort_custom(func(a, b):
			var ta: int = order.get(String(a.terrain), 3)
			var tb: int = order.get(String(b.terrain), 3)
			if ta != tb:
				return ta < tb
			if int(a.row) != int(b.row):
				return int(a.row) < int(b.row)
			return int(a.col) < int(b.col))
		for n in rest_nodes:
			var best_i := 0
			var best_s: int = -(1 << 30)
			for i in range(pool.size()):
				var s: int = EncounterDB.terrain_affinity(pool[i], String(n.terrain))
				# Tie-break on the id itself, NOT pool position — the pool is
				# rebuilt in row-major node order on every call, so a position
				# tie-break made equal-scoring kits swap on a second pass
				# (idempotence is the whole determinism guarantee here).
				if s > best_s or (s == best_s and pool[i] < pool[best_i]):
					best_s = s
					best_i = i
			n["encounter_id"] = pool[best_i]
			pool.remove_at(best_i)
		# Stage 2 — escalation within terrain: every node in a terrain group
		# scores identically wherever its kit lands (affinity is a function
		# of kit x terrain alone), so permuting INSIDE a group is free.
		# Sort each group's kits light→heavy and lay them down the road in
		# row order: the deal sharpens as the keep nears.
		var groups: Dictionary = {}
		for n in rest_nodes:
			var t: String = String(n.terrain)
			if not groups.has(t):
				groups[t] = []
			groups[t].append(n)
		for t in groups:
			var grp: Array = groups[t]
			if grp.size() < 2:
				continue
			var kits: Array = []
			for n in grp:
				kits.append(String(n.encounter_id))
			kits.sort_custom(func(a, b):
				var wa: int = EncounterDB.kit_weight(a)
				var wb: int = EncounterDB.kit_weight(b)
				return wa < wb if wa != wb else a < b)
			grp.sort_custom(func(a, b):
				if int(a.row) != int(b.row):
					return int(a.row) < int(b.row)
				return int(a.col) < int(b.col))
			for i in range(grp.size()):
				grp[i]["encounter_id"] = kits[i]


func advance_act() -> void:
	current_act_idx += 1
	map_position = {"row": -1, "col": -1}
	# Last act's plate (mesh + ~23MB geo texture) can't be revisited — drop it.
	map_plate_cache.clear()
	current_encounter_id = ""
	current_node_type = ""
	current_mutator_id = ""
	current_terrain = ""
	current_bridge = false
	current_wayside_id = ""
	current_setpiece_id = ""
	# Per-act rest counters reset so the time-of-day shader tint (dusk → night)
	# restarts each act, and Whetstone's "first rest of act" payoff re-arms.
	rests_visited_in_act = 0
	whetstone_used_this_act = false
	# Fresh kingdom, fresh siege: the next rival's keep starts locked.
	holds_broken_in_act = 0
	# Centaur Heart: reaching Act 2 (current_act_idx now == 1) grants +5 max HP
	# and heals to full. Fires once per relic — guard via meta flag held on
	# the relic id so a re-entry doesn't keep re-applying.
	if has_relic("centaur_heart") and current_act_idx == 1:
		hero_max_hp += 5
		hero_hp = hero_max_hp
	# A3 "The ledger follows" — the new act opens with a fresh War-Debt.
	if asc_active(3):
		add_card("war_debt")


## Called by Rest.gd when the player commits to staying at a rest node (any
## option — Heal/Upgrade/Remove/Reforge). Increments both counters so the next
## rest screen knows it's not the first of the act. Saves immediately because
## the scene transition that follows can drop these values otherwise (the next
## save normally fires on the *next* map-node visit_node, which is too late if
## the player force-quits between rest and the map screen — Whetstone could
## otherwise be re-spent because whetstone_used_this_act never persisted).
func register_rest_visit() -> void:
	rests_visited_in_act += 1
	rests_visited_total += 1
	save_run()


## True when the act-3 rival just fell and the throne still waits: the run
## should route into the amalgam finale instead of ending. False on legacy
## runs and when the spared rival's amalgam kit isn't authored yet — those
## runs end at the act-3 boss exactly as before.
func should_enter_finale() -> bool:
	return finale_stage == 0 and current_act_idx >= ACTS - 1 \
		and current_node_type == "boss" and finale_rival != "" \
		and EncounterDB.ENCOUNTERS.has("amalgam_" + finale_rival)


## Routes the run into the throne fight. Saves immediately — the checkpoint
## at the throne door survives a quit.
func enter_finale() -> void:
	finale_stage = 1
	current_encounter_id = "amalgam_" + finale_rival
	current_mutator_id = ""
	current_setpiece_id = ""
	save_run()


func is_final_boss() -> bool:
	if finale_stage == 1:
		return true
	return current_act_idx >= ACTS - 1 and current_node_type == "boss" \
		and not should_enter_finale()


# ── Map generation ──

func _generate_map() -> void:
	map_data = _make_map_generator().generate(run_seed, ACTS)


func _make_map_generator():
	return CampaignMapGenerator.new(self, EncounterDB, MutatorDB, HeroDB, MetaState, SetPieceDB)


# Diagnostic compatibility facades. Generation logic stays in the dedicated
# object, while existing invariant probes can continue exercising one act.
func _generate_act_map(act: int, rng: RandomNumberGenerator) -> Array:
	return _make_map_generator().generate_act(act, rng)


func _min_fights_to_rest(flat: Array) -> int:
	return _make_map_generator().min_fights_to_rest(flat)

#  SAVE / RESUME
# ════════════════════════════════════════════════════════════════════
# Persists the in-progress run as JSON across SAVE_SLOTS slots. The save is
# written every time the player commits to a map node (`visit_node`), so
# quitting and relaunching restores them on the map at the room they were
# about to enter. The save is cleared on death or victory (end_run).

# v2: campaign-map act shrink (15→8 rows, 11–15 sites). v1 saves carry
# 15-row map_data the Sicily plate was never sized for; the strict version
# check below retires them as empty slots rather than migrating.
# v3: Successor Wars — rival_lords / finale_rival / act_faction /
# holds_broken_in_act enter the schema. A v2 save has no rival deal, so its
# kingdoms and boss would silently fall back to legacy pools mid-run; retire.
# v4: the 2026-07-07 act lengthening (map 8→18 rows) plus set-piece holds
# (current_setpiece_id / setpieces_carried) and the muster field. A v3 save
# written before those carries an 8/10/12-row map_data that self-navigates but
# resumes a short, wrong-cadence act with no setpieces and mis-tuned hold gates;
# the strict check below never fired because the schema grew without this bump.
const SAVE_VERSION: int = 4
const SAVE_SLOTS: int = 3
const LEGACY_SAVE_PATH: String = "user://run.save"

# Which slot the current in-memory run reads from / writes to. -1 means
# "no slot picked yet" (e.g. the player is in the main menu before starting).
var active_slot: int = -1

# MARCH AGAIN (game-over rematch): GameOver stashes {hero, ascension} here and
# routes to the main menu, which consumes it and restarts immediately — same
# hero, same ascension, fresh seed, straight into the war chest. Transient by
# design: never saved, cleared on consume.
var rematch_request: Dictionary = {}


func _save_path_for_slot(slot: int) -> String:
	return "user://run_%d.save" % slot


# Migrates a pre-multislot save (user://run.save) into the first physically
# empty slot. The source is deleted only after a validated, byte-identical
# SaveIO round trip; occupied or incompatible data is left recoverable.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var src := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != SAVE_VERSION:
		push_warning("RunState: legacy run.save is incompatible; left untouched")
		return
	var target := ""
	for slot in range(SAVE_SLOTS):
		var candidate := _save_path_for_slot(slot)
		if not FileAccess.file_exists(candidate) \
				and not FileAccess.file_exists(candidate + ".bak") \
				and not FileAccess.file_exists(candidate + ".tmp"):
			target = candidate
			break
	if target == "":
		push_warning("RunState: no empty slot for legacy run.save; left untouched")
		return
	if not SaveIO.write_text(target, text) or SaveIO.read_text(target) != text:
		push_warning("RunState: legacy run.save copy did not verify; source kept")
		return
	var remove_err := DirAccess.remove_absolute(
		ProjectSettings.globalize_path(LEGACY_SAVE_PATH))
	if remove_err != OK:
		push_warning("RunState: migrated legacy save but could not remove source (err=%d)" % remove_err)


func _ready() -> void:
	_migrate_legacy_save()


func save_run() -> void:
	if not run_active:
		return
	if active_slot < 0 or active_slot >= SAVE_SLOTS:
		# No real slot has been claimed (e.g. a headless probe that called
		# start_new_run without going through the menu's slot picker). Skip the
		# write rather than silently clobbering slot 0's save.
		push_warning("RunState.save_run: no active_slot claimed (%d), skipping save" % active_slot)
		return
	# JSON converts integer dict keys to strings, so card_upgrades keys come
	# back as Strings on load — we convert back in load_run().
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"hero_max_hp": hero_max_hp,
		"hero_hp": hero_hp,
		"gold": gold,
		"potions": potions,
		"deck": deck,
		"deck_uids": deck_uids,
		"card_upgrades": card_upgrades,
		"next_uid": _next_uid,
		"creature_kills": creature_kills,
		"fallen": fallen,
		"relics": relics,
		"generals_broken_run": generals_broken_run,
		"articles_of_war_tribe": articles_of_war_tribe,
		"season_tribes": season_tribes,
		"map_data": map_data,
		"current_act_idx": current_act_idx,
		"map_position": map_position,
		"current_encounter_id": current_encounter_id,
		"current_node_type": current_node_type,
		"current_mutator_id": current_mutator_id,
		"current_terrain": current_terrain,
		"current_bridge": current_bridge,
		"current_wayside_id": current_wayside_id,
		"current_setpiece_id": current_setpiece_id,
		"setpieces_carried": setpieces_carried,
		"fights_won": fights_won,
		"mutators_survived": mutators_survived,
		"cause_of_death": cause_of_death,
		"events_seen": events_seen,
		"event_choice_flags": event_choice_flags,
		"potion_drop_misses": potion_drop_misses,
		"muster_rerolls_left": muster_rerolls_left,
		"base_max_mana": base_max_mana,
		"current_floor": current_floor,
		"run_seed": run_seed,
		"phoenix_heart_consumed": phoenix_heart_consumed,
		"next_combat_gift_creature": next_combat_gift_creature,
		"next_combat_mana_bonus": next_combat_mana_bonus,
		"pawned_cards": pawned_cards,
		"current_ascension": current_ascension,
		"current_hero_id": current_hero_id,
		"current_signature_relic": current_signature_relic,
		"current_banner_tribe": current_banner_tribe,
		"current_deck_variant": current_deck_variant,
		"rival_lords": rival_lords,
		"finale_rival": finale_rival,
		"act_faction": act_faction,
		"holds_broken_in_act": holds_broken_in_act,
		"holds_broken_run": holds_broken_run,
		"finale_stage": finale_stage,
		"rests_visited_in_act": rests_visited_in_act,
		"rests_visited_total": rests_visited_total,
		"whetstone_used_this_act": whetstone_used_this_act,
		"totem_pole_keyword": totem_pole_keyword,
		"totem_pole_act": totem_pole_act,
		"bone_hourglass_choice": bone_hourglass_choice,
		"bone_hourglass_act": bone_hourglass_act,
		"bottled_talisman_uid": bottled_talisman_uid,
		"is_daily_run": is_daily_run,
		"daily_mutator_id": daily_mutator_id,
		"daily_date": daily_date,
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	var path := _save_path_for_slot(active_slot)
	if not SaveIO.write_text(path, JSON.stringify(payload)):
		push_warning("RunState.save_run: could not open %s for write" % path)


# All three slot accessors take an optional slot. -1 means "use the active
# slot" so existing call sites that don't know about slots keep working.
func has_save(slot: int = -1) -> bool:
	var s: int = slot if slot >= 0 else active_slot
	if s < 0 or s >= SAVE_SLOTS:
		return false
	var path := _save_path_for_slot(s)
	# The .bak generation counts: if a crash landed between SaveIO's two
	# renames the main file is briefly absent but the run is still recoverable.
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") \
		or FileAccess.file_exists(path + ".tmp")


func clear_save(slot: int = -1) -> void:
	var s: int = slot if slot >= 0 else active_slot
	if s < 0 or s >= SAVE_SLOTS:
		return
	var path := _save_path_for_slot(s)
	# Clear every generation — leaving a .bak behind would let a deliberately
	# abandoned run resurrect through the corruption fallback.
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# Loads and parses a save file, returning the raw Dictionary or {} on failure.
# Shared by load_run() and get_slot_summary() so summary headers don't have
# to duplicate the parse/version-check logic.
func _read_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= SAVE_SLOTS:
		return {}
	var path := _save_path_for_slot(slot)
	var text := SaveIO.read_text(path)
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# Corrupt main file (crash mid-write): the .bak generation is the last
		# checkpoint that parsed — a fight behind beats a dead slot.
		parsed = JSON.parse_string(SaveIO.read_backup_text(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		return {}
	return data


# Returns a small summary of a slot for the menu's slot picker:
#   {has_save: bool, act: int, floor: int, hp: int, max_hp: int,
#    gold: int, ascension: int, saved_at: int}
# If the slot is empty or corrupt, has_save is false and other fields are 0.
func get_slot_summary(slot: int) -> Dictionary:
	var data := _read_slot(slot)
	if data.is_empty():
		# Preserve the distinction between an empty slot and physical data that is
		# incompatible, corrupt, or temporarily unreadable. The menu must never
		# turn a failed parse into an automatic delete.
		return {"has_save": false, "unreadable": has_save(slot)}
	return {
		"has_save": true,
		"unreadable": false,
		"act": int(data.get("current_act_idx", 0)) + 1,
		"floor": int(data.get("current_floor", 0)),
		"hp": int(data.get("hero_hp", 0)),
		"max_hp": int(data.get("hero_max_hp", 25)),
		"gold": int(data.get("gold", 0)),
		"ascension": int(data.get("current_ascension", 0)),
		"hero": String(data.get("current_hero_id", "")),
		"is_daily_run": bool(data.get("is_daily_run", false)),
		"daily_date": String(data.get("daily_date", "")),
		"saved_at": int(data.get("saved_at", 0)),
	}


func load_run(slot: int = -1) -> bool:
	var s: int = slot if slot >= 0 else active_slot
	var data := _read_slot(s)
	if data.is_empty():
		return false

	pending_banner_tribe = ""
	hero_max_hp = int(data.get("hero_max_hp", 25))
	hero_hp = int(data.get("hero_hp", 25))
	gold = int(data.get("gold", 0))
	# potions was an int (count of generic heal potions) in older saves; new
	# saves store an Array[String] of potion ids. Migrate legacy saves by
	# expanding the int into N healing potions so existing runs don't lose them.
	var raw_potions = data.get("potions", [])
	potions = []
	if typeof(raw_potions) == TYPE_ARRAY:
		for pid in raw_potions:
			potions.append(String(pid))
	else:
		var n: int = int(raw_potions)
		for _i in range(n):
			potions.append("healing")
	# Rebuild typed arrays from the plain JSON arrays.
	deck = []
	deck_uids = []
	var valid_deck_uids: Dictionary = {}
	var max_uid: int = -1
	var raw_deck: Array = data.get("deck", [])
	var raw_deck_uids: Array = data.get("deck_uids", [])
	for i in range(raw_deck.size()):
		var cid: String = String(raw_deck[i])
		if not CardDB.CARD_POOL.has(cid):
			continue
		var uid: int = int(raw_deck_uids[i]) if i < raw_deck_uids.size() else i
		deck.append(cid)
		deck_uids.append(uid)
		valid_deck_uids[uid] = true
		max_uid = maxi(max_uid, uid)
	# JSON int-keyed dicts come back as String keys — convert.
	card_upgrades = {}
	var raw_upgrades: Dictionary = data.get("card_upgrades", {})
	# Shape migration: saves from the single-slot era store one Dictionary per
	# uid; the stacking model stores an Array of entries. Wrap legacy values.
	for k in raw_upgrades:
		var upgrade_uid: int = int(k)
		if not valid_deck_uids.has(upgrade_uid):
			continue
		var v = raw_upgrades[k]
		card_upgrades[upgrade_uid] = v if v is Array else [v]
	_next_uid = maxi(int(data.get("next_uid", max_uid + 1)), max_uid + 1)
	# Campaign memory — JSON stringifies dict keys; restore int uids the same
	# way card_upgrades does. Legacy saves without the keys load blank ledgers.
	creature_kills = {}
	var raw_kills: Dictionary = data.get("creature_kills", {})
	for k in raw_kills:
		var kill_uid: int = int(k)
		if valid_deck_uids.has(kill_uid):
			creature_kills[kill_uid] = int(raw_kills[k])
	fallen = data.get("fallen", [])
	relics = []
	for id in data.get("relics", []):
		# Drop retired ids (2026-07-07 pool cut) so an old save can't carry a
		# ghost relic into the HUD strip / reward filters / effect checks.
		var relic_id := String(id)
		if RelicDB.RELICS.has(relic_id) \
				and not bool(RelicDB.RELICS[relic_id].get("retired", false)):
			relics.append(relic_id)
	generals_broken_run = int(data.get("generals_broken_run", 0))
	articles_of_war_tribe = String(data.get("articles_of_war_tribe", ""))
	var saved_banner := String(data.get("current_banner_tribe", ""))
	current_banner_tribe = saved_banner if BannerDB.has_banner(saved_banner) else ""

	season_tribes = Array(data.get("season_tribes", []))
	map_data = data.get("map_data", [])
	map_plate_cache.clear()
	current_act_idx = int(data.get("current_act_idx", 0))
	map_position = data.get("map_position", {"row": -1, "col": -1})
	current_encounter_id = String(data.get("current_encounter_id", ""))
	current_node_type = String(data.get("current_node_type", ""))
	current_mutator_id = String(data.get("current_mutator_id", ""))
	current_terrain = String(data.get("current_terrain", ""))
	current_bridge = bool(data.get("current_bridge", false))
	current_wayside_id = String(data.get("current_wayside_id", ""))
	current_setpiece_id = String(data.get("current_setpiece_id", ""))
	# Named actions already carried — a resumed save must never re-pay
	# a trophy for ground it already holds.
	setpieces_carried = []
	for sp_id in data.get("setpieces_carried", []):
		setpieces_carried.append(String(sp_id))
	fights_won = int(data.get("fights_won", 0))
	potion_drop_misses = int(data.get("potion_drop_misses", 0))
	muster_rerolls_left = int(data.get("muster_rerolls_left", 0))
	mutators_survived = []
	for m in data.get("mutators_survived", []):
		mutators_survived.append(String(m))
	cause_of_death = String(data.get("cause_of_death", ""))
	events_seen = []
	for id in data.get("events_seen", []):
		events_seen.append(String(id))
	event_choice_flags = []
	for flag in data.get("event_choice_flags", []):
		record_event_choice(String(flag))
	base_max_mana = int(data.get("base_max_mana", 3))
	current_floor = int(data.get("current_floor", 0))
	run_seed = int(data.get("run_seed", 0))
	phoenix_heart_consumed = bool(data.get("phoenix_heart_consumed", false))
	next_combat_gift_creature = data.get("next_combat_gift_creature", {})
	next_combat_mana_bonus = int(data.get("next_combat_mana_bonus", 0))
	pawned_cards = []
	for pid in data.get("pawned_cards", []):
		pawned_cards.append(String(pid))
	current_ascension = int(data.get("current_ascension", 0))
	current_hero_id = String(data.get("current_hero_id", HeroDB.DEFAULT_HERO))
	# Optional v4 doctrine fields. Old saves recover the signature from the
	# starting-tier relic they already hold and treat the deck as Standard.
	var saved_signature := String(data.get("current_signature_relic", ""))
	if saved_signature == "" or not relics.has(saved_signature):
		saved_signature = ""
		for rid in relics:
			var rd: Dictionary = RelicDB.get_relic(String(rid))
			if String(rd.get("tier", "")) == "starting":
				saved_signature = String(rid)
				break
	if saved_signature == "":
		saved_signature = String(HeroDB.get_hero(current_hero_id).get("relic", ""))
	current_signature_relic = saved_signature
	current_deck_variant = "alt" \
		if String(data.get("current_deck_variant", "")) == "alt" else ""
	rival_lords = []
	for hid in data.get("rival_lords", []):
		rival_lords.append(String(hid))
	finale_rival = String(data.get("finale_rival", ""))
	act_faction = []
	for fid in data.get("act_faction", []):
		act_faction.append(String(fid))
	holds_broken_in_act = int(data.get("holds_broken_in_act", 0))
	holds_broken_run = int(data.get("holds_broken_run", holds_broken_in_act))
	finale_stage = int(data.get("finale_stage", 0))
	rests_visited_in_act = int(data.get("rests_visited_in_act", 0))
	rests_visited_total = int(data.get("rests_visited_total", 0))
	whetstone_used_this_act = bool(data.get("whetstone_used_this_act", false))
	totem_pole_keyword = String(data.get("totem_pole_keyword", ""))
	totem_pole_act = int(data.get("totem_pole_act", 0))
	bone_hourglass_choice = String(data.get("bone_hourglass_choice", ""))
	bone_hourglass_act = int(data.get("bone_hourglass_act", 0))
	bottled_talisman_uid = int(data.get("bottled_talisman_uid", -1))
	is_daily_run = bool(data.get("is_daily_run", false))
	daily_mutator_id = String(data.get("daily_mutator_id", ""))
	daily_date = String(data.get("daily_date", ""))
	# v4 daily saves predate daily_date. Recover their origin from the matching
	# marching ledger when possible; otherwise leave it blank and MetaState uses
	# today's date as the compatibility fallback.
	if is_daily_run and daily_date == "":
		daily_date = MetaState.daily_date_for_run(current_hero_id, s)
	run_active = true
	active_slot = s
	CardTextureCache.clear()
	return true
