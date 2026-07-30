extends RefCounted
class_name CampaignMapGenerator
## Deterministic campaign topology/content generator.
##
## RunState owns persisted run data and exposes navigation; this object owns the
## pure generation pass and receives the run context explicitly for rival/faction
## selections. A fresh instance is used for every run.

const MAP_WIDTH: int = 7
const MAP_HEIGHT: int = 18
const BOSS_ROW: int = 17
const REST_ROW: int = 16
const NUM_PATHS: int = 3
const FIGHT_ROWS: Array[int] = [0, 3, 9, 15]
const ELITE_ROWS: Array[int] = [6, 12]
const MAX_MUSTERS_PER_ACT: int = 3
const FIRST_RUN_OPENER_ENCOUNTER: String = "goblin_scouts"

var _run_state: Node
var _encounter_db: Node
var _mutator_db: Node
var _hero_db: Node
var _meta_state: Node
var _set_piece_db: Node


func _init(run_state: Node, encounter_db: Node, mutator_db: Node,
		hero_db: Node, meta_state: Node, set_piece_db: Node = null) -> void:
	_run_state = run_state
	_encounter_db = encounter_db
	_mutator_db = mutator_db
	_hero_db = hero_db
	_meta_state = meta_state
	# Optional so the boss-reroll call site (which only needs
	# boss_encounter_for_act) can keep its five-argument construction.
	_set_piece_db = set_piece_db


func generate(seed: int, acts: int) -> Array:
	var result: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for act in range(1, acts + 1):
		result.append(generate_act(act, rng))
	return result


func _find_node_by_col(row_nodes: Array, col: int) -> Dictionary:
	for node in row_nodes:
		if int(node.get("col", -1)) == col:
			return node
	return {}

## Generates a single act map:
##   1. Walk NUM_PATHS paths from row 0 up to REST_ROW, ±1 column per step,
##      with a no-crossing constraint and a 3x merge bias (trunk + branches).
##   2. Stamp the Kaycee's-Mod row skeleton over the lattice — fight rows
##      alternating with wayside bands; guarantees placed, not rolled
##      (see _assign_node_types).
##   3. Add a single boss node at the BOSS_ROW center, with every populated
##      REST_ROW node connecting up to it.
##   4. Walk through and assign encounter IDs to combat/elite/boss nodes.
func generate_act(act: int, rng: RandomNumberGenerator) -> Array:
	# Acceptance loop: only acts with 24–36 sites (incl. boss) read as a
	# campaign over the plate — fewer is degenerate, more re-grows the
	# lattice. (Window scaled with the 2026-07-07 skeleton lengthening: 18 rows
	# walk more stations than the old 12.) One value is drawn from the shared
	# rng per act so later acts stay deterministic regardless of attempts.
	var base_seed: int = rng.randi()
	var flat: Array = []
	for attempt in range(60):
		var arng := RandomNumberGenerator.new()
		arng.seed = base_seed + attempt * 7919
		var grid: Array = []
		for r in range(MAP_HEIGHT):
			var row: Array = []
			for c in range(MAP_WIDTH):
				row.append(null)
			grid.append(row)
		_generate_paths(grid, arng)
		_assign_node_types(grid, arng)
		_add_boss_node(grid)
		_assign_encounters(grid, act, arng)
		flat = _flatten_grid(grid)
		var n: int = 0
		for row_nodes in flat:
			n += (row_nodes as Array).size()
		# Site-count window AND boss-gate guarantee: the worst route a player
		# can walk must still pass _run_state.HOLDS_TO_OPEN_LORD fight nodes, or the
		# locked keep could softlock the act. (The skeleton makes the fight
		# minimum 4 by construction — the DFS check stays as a tripwire.)
		if n >= 24 and n <= 36 and min_fights_to_rest(flat) >= _run_state.HOLDS_TO_OPEN_LORD \
				and _war_road_ok(flat):
			return flat
	return flat


## The route-variance guarantee (2026-07-07): the optional third General
## landed on a wide fight row (the war-road fork), AND at least one elite
## band is ≥2 lanes so the mid-road spike can be dodged too. Lattices where
## every route walks the same fights are rejected — that sameness is exactly
## what this kills. Landing rules in _assign_node_types keep the extra spike
## avoidable by construction (only rows with ≥2 lanes are eligible).
func _war_road_ok(flat: Array) -> bool:
	var extra := false
	for r in FIGHT_ROWS:
		if r >= flat.size():
			continue
		for nd in (flat[r] as Array):
			if String(nd.type) == "elite":
				extra = true
	var wide_band := false
	for r in ELITE_ROWS:
		if r < flat.size() and (flat[r] as Array).size() >= 2:
			wide_band = true
	return extra and wide_band


## Minimum number of combat/elite nodes along ANY root→rest-row route — the
## fewest fights a player can reach the keep with. Memoized DFS over the DAG.
func min_fights_to_rest(flat: Array) -> int:
	if flat.is_empty() or (flat[0] as Array).is_empty():
		return 0
	var memo: Dictionary = {}
	var best: int = 999
	for start in flat[0]:
		best = mini(best, _min_fights_from(flat, 0, int(start.col), memo))
	return best


func _min_fights_from(flat: Array, row: int, col: int, memo: Dictionary) -> int:
	var node: Dictionary = _find_node_by_col(flat[row], col)
	if node.is_empty():
		return 999
	var key: int = row * 100 + col
	if memo.has(key):
		return memo[key]
	var self_cost: int = 1 if String(node.type) in ["combat", "elite"] else 0
	if row >= REST_ROW:
		memo[key] = self_cost
		return self_cost
	var best: int = 999
	for nc in node.connections:
		best = mini(best, _min_fights_from(flat, row + 1, int(nc), memo))
	var total: int = self_cost + (best if best < 999 else 0)
	memo[key] = total
	return total


func _generate_paths(grid: Array, rng: RandomNumberGenerator) -> void:
	var starts: Array[int] = []
	for p in range(NUM_PATHS):
		var start_col: int = _pick_start_col(rng, starts, p)
		starts.append(start_col)
		_walk_path(grid, start_col, rng)


func _pick_start_col(rng: RandomNumberGenerator, prev_starts: Array,
		path_idx: int) -> int:
	# STS rule: the first two paths must originate from different columns so
	# the player always has a meaningful first choice.
	var avail: Array[int] = []
	for c in range(MAP_WIDTH):
		if path_idx == 1 and prev_starts.size() > 0 and c == prev_starts[0]:
			continue
		avail.append(c)
	return avail[rng.randi() % avail.size()]


func _walk_path(grid: Array, start_col: int,
		rng: RandomNumberGenerator) -> void:
	var cur_col: int = start_col
	if grid[0][cur_col] == null:
		grid[0][cur_col] = _make_node(cur_col, 0)
	for r in range(REST_ROW):
		var next_col: int = _pick_next_col(grid, r, cur_col, rng)
		if grid[r + 1][next_col] == null:
			grid[r + 1][next_col] = _make_node(next_col, r + 1)
		var conns: Array = grid[r][cur_col]["connections"]
		if not conns.has(next_col):
			conns.append(next_col)
		cur_col = next_col


func _make_node(col: int, row: int) -> Dictionary:
	return {
		"type": "",
		"encounter_id": "",
		"mutator_id": "",
		"setpiece_id": "",
		"visited": false,
		"connections": [],
		"row": row,
		"col": col,
	}


func _pick_next_col(grid: Array, r: int, cur_col: int,
		rng: RandomNumberGenerator) -> int:
	# Step diagonally to ±1 or stay in the same column. Never produce an edge
	# that crosses an existing one (no X-shaped intersections). Candidates
	# whose destination cell is already populated get double weight, so paths
	# prefer to merge into existing nodes — this reduces total node count and
	# gives the map a more organic feel (STS2-style convergent landmarks).
	var candidates: Array[int] = []
	for d in [-1, 0, 1]:
		var nc: int = cur_col + d
		if nc < 0 or nc >= MAP_WIDTH:
			continue
		if _would_cross(grid, r, cur_col, nc):
			continue
		candidates.append(nc)
		if grid[r + 1][nc] != null:
			# Strong merge bias (3×): paths converge into a trunk road with
			# branches — the validated campaign-map look.
			candidates.append(nc)
			candidates.append(nc)
	if candidates.is_empty():
		return cur_col
	return candidates[rng.randi() % candidates.size()]


func _would_cross(grid: Array, r: int, from_col: int, to_col: int) -> bool:
	# Two diagonals form an X when the cell at the destination column already
	# has an edge pointing to our source column. Straight-up steps never cross.
	if to_col == from_col:
		return false
	var partner = grid[r][to_col]
	if partner == null:
		return false
	return partner["connections"].has(from_col)


func _assign_node_types(grid: Array, rng: RandomNumberGenerator) -> void:
	# The row skeleton. Fight rows and the rest row are uniform; the elite
	# band gets exactly one elite (the act's stronghold spike — forced onto
	# every route when the band is a single merge point, avoidable when the
	# row is wider); wayside rows deal their band's flavors round-robin so
	# siblings differ wherever the row has width. Every between-fight gap is
	# a PAIR of wayside rows — the Inscryption cadence: two stops of
	# different kinds between every hold.
	#   R0 fight (the landing — lightest deal, see apply_terrain_redeal)
	#   R1 wayside: the landing tissue — events, a verb, maybe a muster
	#   R2 wayside: roadside verbs and omens
	#   R3 fight
	#   R4 wayside: the muster band — recruit guaranteed, shop beside it
	#   R5 wayside: events, sometimes a second muster
	#   R6 fight: the FIRST elite band (mid-road spike)
	#   R7 wayside: the spoils band — treasure guaranteed after the spike
	#   R8 wayside: outfitting — shop leads the pool
	#   R9 fight (the mid hold)
	#   R10 wayside: the second muster band — recruit guaranteed
	#   R11 wayside: events and verbs
	#   R12 fight: the SECOND elite band (the escalation before the keep)
	#   R13 wayside: the Arsenal — non-relic forge / potion / gold spoils
	#   R14 wayside: last outfitting — shop in the pool
	#   R15 fight (the approach hold)
	#   R16 rest (the war-council breather)   R17 keep
	for c in range(MAP_WIDTH):
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["type"] = "rest"
	for r in FIGHT_ROWS:
		for node in _row_nodes(grid, r):
			node["type"] = "combat"
	# Each elite band is a fight row where exactly one node becomes the General;
	# the rest of the band stays a plain hold (avoidable when the row is wider
	# than the single spike).
	for elite_row in ELITE_ROWS:
		var band: Array = _row_nodes(grid, elite_row)
		for node in band:
			node["type"] = "combat"
		if not band.is_empty():
			band[rng.randi() % band.size()]["type"] = "elite"
	# THE WAR ROAD (2026-07-07): one plain fight row per act hides a THIRD,
	# optional General — the StS elite-hunt trade the flat skeleton lacked
	# (every route used to walk the same fights, so the fork never mattered).
	# A greedy road can now break 3 Generals for 3 relic drops; a quiet road
	# dodges down to whatever the merges force. Only rows wide enough to
	# route around (≥2 lanes) are eligible, and never the landing row — the
	# extra spike must always be a CHOICE read off the chart, not an ambush.
	# The acceptance loop re-rolls lattices where it couldn't land (see
	# _war_road_ok), so the fork is a guarantee, not a prayer.
	var war_rows: Array = [3, 9, 15]
	shuffle_array(war_rows, rng)
	for wr in war_rows:
		var wband: Array = _row_nodes(grid, wr)
		if wband.size() >= 2:
			var war_node: Dictionary = wband[rng.randi() % wband.size()]
			war_node["type"] = "elite"
			# Tag the row so the set-piece placer (which runs later, in
			# _assign_encounters, where the act number is known) can keep the
			# two optional spikes on SEPARATE rows — two forks, two decisions.
			war_node["war_road"] = true
			break
	var wayside_rows: Array[int] = [1, 2, 4, 5, 7, 8, 10, 11, 13, 14]
	_fill_wayside_row(grid, 1, ["event", "wayside", "recruit"], rng)
	_fill_wayside_row(grid, 2, ["wayside", "event"], rng)
	_fill_wayside_row(grid, 4, ["shop", "event"], rng)
	_fill_wayside_row(grid, 5, ["event", "wayside", "recruit"], rng)
	_fill_wayside_row(grid, 7, ["event", "wayside"], rng)
	_fill_wayside_row(grid, 8, ["shop", "event", "wayside"], rng)
	_fill_wayside_row(grid, 10, ["event", "wayside", "recruit"], rng)
	_fill_wayside_row(grid, 11, ["wayside", "event"], rng)
	_fill_wayside_row(grid, 13, ["event", "wayside"], rng)
	_fill_wayside_row(grid, 14, ["shop", "event", "wayside"], rng)
	# Placed guarantees: two musters, one relic-bearing Reliquary, one non-relic
	# Arsenal, and at least one shop. This bounds relic volume while preserving
	# the second post-General spoils beat. R1/R5/R11 can add further musters;
	# deck growth lives at camps in the conquest economy (fights pay gold, not
	# cards), capped at three across the act's two halves.
	_force_one(grid, 4, "recruit", rng)
	_force_one(grid, 10, "recruit", rng)
	# Normalize AFTER the guarantees. The old order deduplicated first, then a
	# forced R10 recruit could create a second Muster on that same row; optional
	# R1/R5/R11 deals could also lift the act to five Musters.
	_normalize_musters(grid, wayside_rows, rng)
	# Wayside halts get their verb only after normalization so demoted recruits
	# never retain stale per-verb metadata.
	var verbs: Array = ["drill_yard", "standard_bearer", "supply_cache"]
	shuffle_array(verbs, rng)
	var vi: int = 0
	for r in wayside_rows:
		for node in _row_nodes(grid, r):
			if String(node["type"]) == "wayside":
				node["wayside_id"] = verbs[vi % verbs.size()]
				vi += 1
	_force_one(grid, 7, "treasure", rng)
	_force_one(grid, 13, "arsenal", rng)
	if _count_type(grid, "shop") == 0:
		for r in [8, 14, 4, 5]:
			if _force_one(grid, r, "shop", rng):
				break


func _row_nodes(grid: Array, r: int) -> Array:
	var out: Array = []
	for c in range(MAP_WIDTH):
		if grid[r][c] != null:
			out.append(grid[r][c])
	return out


## Deal a wayside band's flavors across the row, round-robin from a random
## offset — siblings differ whenever the row is wider than one site.
func _fill_wayside_row(grid: Array, r: int, pool: Array,
		rng: RandomNumberGenerator) -> void:
	var i: int = rng.randi() % pool.size()
	for node in _row_nodes(grid, r):
		node["type"] = pool[i % pool.size()]
		i += 1


## Keep one Muster per row and at most three per act. R4/R10 are structural
## guarantees; one seeded optional survives from the other bands when offered.
func _normalize_musters(grid: Array, wayside_rows: Array[int],
		rng: RandomNumberGenerator) -> void:
	var optional: Array = []
	var guaranteed_count := 0
	for r in wayside_rows:
		var kept_on_row := false
		for node in _row_nodes(grid, r):
			if String(node["type"]) != "recruit":
				continue
			if kept_on_row:
				node["type"] = "event"
				node.erase("wayside_id")
				continue
			kept_on_row = true
			if r in [4, 10]:
				guaranteed_count += 1
			else:
				optional.append(node)
	shuffle_array(optional, rng)
	var optional_to_keep := maxi(0, MAX_MUSTERS_PER_ACT - guaranteed_count)
	for i in range(optional_to_keep, optional.size()):
		optional[i]["type"] = "event"
		optional[i].erase("wayside_id")


## Stamp `t` onto one PLAIN node (event/shop) of row `r` — never onto an
## already-placed guarantee (a single-site muster row must not lose its
## recruit to the shop fallback). Falls back to eating a wayside halt when
## the row dealt no plain slot (a 1-wide spoils row that rolled "wayside"
## must still yield its treasure). Returns false if the row has neither.
func _force_one(grid: Array, r: int, t: String,
		rng: RandomNumberGenerator) -> bool:
	# A naturally dealt guarantee already satisfies the row. Returning here is
	# what prevents forcing a second recruit beside it.
	for node in _row_nodes(grid, r):
		if String(node["type"]) == t:
			return true
	for pool in [["event", "shop"], ["wayside"]]:
		var plain: Array = []
		for node in _row_nodes(grid, r):
			if String(node["type"]) in pool:
				plain.append(node)
		if not plain.is_empty():
			var picked: Dictionary = plain[rng.randi() % plain.size()]
			picked["type"] = t
			picked.erase("wayside_id")
			return true
	return false


func _count_type(grid: Array, t: String) -> int:
	var n: int = 0
	for r in range(MAP_HEIGHT):
		for c in range(MAP_WIDTH):
			if grid[r][c] != null and String(grid[r][c]["type"]) == t:
				n += 1
	return n


func _add_boss_node(grid: Array) -> void:
	var boss_col: int = MAP_WIDTH / 2
	grid[BOSS_ROW][boss_col] = _make_node(boss_col, BOSS_ROW)
	grid[BOSS_ROW][boss_col]["type"] = "boss"
	for c in range(MAP_WIDTH):
		if grid[REST_ROW][c] != null:
			grid[REST_ROW][c]["connections"] = [boss_col]


## THE NAMED ACTION (2026-07-20) — place this act's SET-PIECE hold.
##
## A set-piece is an authored scenario (scripts/data/SetPieceDB.gd): its own
## opening board, ONE twisted rule, and an objective on a clock. It is placed
## by exactly the same trade as the war road, because that trade is proven:
##   · a PLAIN fight row only (3 / 9 / 15) — never the landing row 0, whose
##     job is the on-ramp, and never an elite band, which already spends the
##     player's route budget on a General;
##   · a row at least 2 lanes wide, so the named action can always be routed
##     AROUND. It must be a choice read off the chart, never an ambush;
##   · never the war road's own row, so the act's two optional spikes are two
##     separate decisions rather than one loaded corner of the map.
##
## If no row qualifies (a narrow lattice), the act simply gets no named action.
## That is deliberate: these are named GROUND, and named ground does not move
## somewhere else to make itself convenient. The acceptance loop is NOT gated
## on placement succeeding — a set-piece is content, not a structural promise,
## and rejecting lattices over it would fight the site-count window.
func _place_set_piece(grid: Array, act: int, rng: RandomNumberGenerator,
		first_run_opener: bool) -> void:
	# The very first campaign walks a clean on-ramp: no named action in act 1
	# until the player has finished one march. A scenario with a closed board
	# and a deadline is a bad first impression of "what a fight is."
	if first_run_opener or _set_piece_db == null:
		return
	var pool: Array = _set_piece_db.ids_for_act(act)
	if pool.is_empty():
		return
	var war_row: int = -1
	for r in range(MAP_HEIGHT):
		for c in range(MAP_WIDTH):
			if grid[r][c] != null and bool(grid[r][c].get("war_road", false)):
				war_row = r
	var rows: Array = [3, 9, 15]
	shuffle_array(rows, rng)
	for sr in rows:
		if sr == war_row:
			continue
		var band: Array = _row_nodes(grid, sr)
		if band.size() < 2:
			continue
		var open_band: Array = []
		for node in band:
			if String(node["type"]) == "combat":
				open_band.append(node)
		if open_band.is_empty():
			continue
		open_band[rng.randi() % open_band.size()]["setpiece_id"] = \
			String(pool[rng.randi() % pool.size()])
		return


func _assign_encounters(grid: Array, act: int,
		rng: RandomNumberGenerator) -> void:
	# Successor Wars: every hold in the kingdom belongs to the act's faction
	# (the rival being marched on). Thin factions borrow their own fights
	# from other acts — Combat rescales them via the target_act rails. On a
	# legacy run with no rival deal, faction is "" and the pools fall back
	# to the unfiltered act lists (get_kingdom_pool passes through).
	var faction: String = _run_state.act_faction[act - 1] if act - 1 < _run_state.act_faction.size() else ""
	var combat_ids: Array = _encounter_db.get_kingdom_pool(act, "combat", faction)
	shuffle_array(combat_ids, rng)
	var elite_ids: Array = _encounter_db.get_kingdom_pool(act, "elite", faction)
	shuffle_array(elite_ids, rng)
	# First-run on-ramp (P1#5): only the very first campaign's opening hold —
	# Act 1, row 0 (FIGHT_ROWS[0]) — gets the hand-picked gentle fight with no
	# mutator. Every later act, later row, and every subsequent run keeps the
	# shuffled pool + 35% mutator roll untouched. Identity-only: this never
	# touches the skeleton/site counts the acceptance loop guards.
	var first_run_opener: bool = act == 1 and _meta_state.total_runs == 0
	# The act's named action goes down BEFORE the encounter walk, so the walk
	# can see the setpiece_id and skip dealing that node a pool fight / mutator.
	_place_set_piece(grid, act, rng, first_run_opener)
	var combat_idx: int = 0
	var elite_idx: int = 0
	for r in range(MAP_HEIGHT):
		for c in range(MAP_WIDTH):
			var node = grid[r][c]
			if node == null:
				continue
			match node["type"]:
				"combat":
					# A named action brings its own board, deck and rule — it
					# neither draws from the encounter pool nor wears a mutator
					# (its GROUND is the one twisted rule; stacking a second
					# parallel rule on top is the thing the boss branch below
					# already refuses to do).
					if String(node.get("setpiece_id", "")) != "":
						node["encounter_id"] = ""
						node["mutator_id"] = ""
						continue
					if first_run_opener and r == FIGHT_ROWS[0]:
						node["encounter_id"] = FIRST_RUN_OPENER_ENCOUNTER
						node["mutator_id"] = ""
						continue
					if combat_ids.size() > 0:
						node["encounter_id"] = combat_ids[combat_idx % combat_ids.size()]
						combat_idx += 1
					node["mutator_id"] = _mutator_db.roll(0.35, rng)
				"elite":
					if elite_ids.size() > 0:
						node["encounter_id"] = elite_ids[elite_idx % elite_ids.size()]
						elite_idx += 1
					node["mutator_id"] = _mutator_db.roll(0.65, rng)
				"boss":
					node["encounter_id"] = boss_encounter_for_act(act, rng)
					# Bosses keep their own complex passives — no mutator on boss
					# fights to avoid stacking too many parallel rule changes.


## Late-bind the fight identities on an already-generated, still-unvisited act.
## THE NEXT MARCH can change which lord rules a future map after all topology
## has been generated. Only encounter_id is touched here: roads, site types,
## named-action placement, terrain tags and the originally-dealt mutators remain
## stable. RunState supplies a deterministic act/faction sub-stream.
func redeal_encounters(flat: Array, act: int,
		rng: RandomNumberGenerator) -> void:
	var faction: String = _run_state.act_faction[act - 1] \
		if act - 1 < _run_state.act_faction.size() else ""
	var combat_ids: Array = _encounter_db.get_kingdom_pool(
		act, "combat", faction)
	shuffle_array(combat_ids, rng)
	var elite_ids: Array = _encounter_db.get_kingdom_pool(
		act, "elite", faction)
	shuffle_array(elite_ids, rng)
	var combat_idx := 0
	var elite_idx := 0
	for row in flat:
		for raw_node in row:
			var node: Dictionary = raw_node
			# Named actions own their encounter setup. Keep their slot and rule
			# intact, and never accidentally dress one as an ordinary hold.
			if String(node.get("setpiece_id", "")) != "":
				node["encounter_id"] = ""
				continue
			match String(node.get("type", "")):
				"combat":
					node["encounter_id"] = ""
					if not combat_ids.is_empty():
						node["encounter_id"] = \
							combat_ids[combat_idx % combat_ids.size()]
						combat_idx += 1
				"elite":
					node["encounter_id"] = ""
					if not elite_ids.is_empty():
						node["encounter_id"] = \
							elite_ids[elite_idx % elite_ids.size()]
						elite_idx += 1
				"boss":
					node["encounter_id"] = boss_encounter_for_act(act, rng)


## The act's boss fight: the rival lord's kit if authored (rival_<hero>),
## else a stand-in boss from his own faction (nearest act first, rescaled by
## the cross-act rails), else the legacy unfiltered act roll. Stand-ins keep
## runs completable while the five lord kits are authored one at a time.
func boss_encounter_for_act(act: int, rng: RandomNumberGenerator) -> String:
	var rival: String = _run_state.rival_lords[act - 1] if act - 1 < _run_state.rival_lords.size() else ""
	if rival != "":
		var kit_id := "rival_%s" % rival
		if _encounter_db.ENCOUNTERS.has(kit_id):
			return kit_id
		var stand_ins: Array = _encounter_db.get_kingdom_pool(
			act, "boss", _hero_db.get_faction(rival))
		# get_kingdom_pool can top up from the unfiltered act pool when a
		# faction has no boss anywhere (grasswake) — that's fine here too:
		# better an off-banner boss than no keep to take.
		if not stand_ins.is_empty():
			return stand_ins[rng.randi() % stand_ins.size()]
	var boss_ids: Array = _encounter_db.get_ids_for(act, "boss")
	if boss_ids.is_empty():
		# Last resort so the keep never stamps an empty encounter id (which would
		# softlock the act): pull a boss from any act, else any non-special fight.
		for other_act in [1, 2, 3]:
			var any_boss: Array = _encounter_db.get_ids_for(other_act, "boss")
			if not any_boss.is_empty():
				boss_ids = any_boss
				break
		if boss_ids.is_empty():
			for id in _encounter_db.ENCOUNTERS:
				var sid := String(id)
				if not sid.begins_with("rival_") and not sid.begins_with("amalgam_"):
					boss_ids = [id]
					break
		if boss_ids.is_empty():
			return ""
	shuffle_array(boss_ids, rng)
	return boss_ids[0]


func _flatten_grid(grid: Array) -> Array:
	# Compact the sparse grid into per-row arrays of only the populated nodes.
	# Each node keeps its grid `col` for visuals and for connection lookups.
	var rows: Array = []
	for r in range(MAP_HEIGHT):
		var row_nodes: Array = []
		for c in range(MAP_WIDTH):
			if grid[r][c] != null:
				row_nodes.append(grid[r][c])
		rows.append(row_nodes)
	return rows


static func shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp


# ════════════════════════════════════════════════════════════════════
