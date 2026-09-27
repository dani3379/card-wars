extends SceneTree
## THE COST RESCALE DERIVATION (2026-09-16) — Phase 3 of
## docs/ECONOMY_REDESIGN_20260916.md §2.2.
##
## The Command ramp (1 on round 1, +1/round, cap 6) shipped against a pool whose
## costs were tuned for a FLAT 3: 47% of entries at <=1, 86% at <=2, one card at
## the top and nothing above 5. So the ramp's own contract — "cost N is first
## affordable on round N" — currently says nothing, because almost the whole pool
## is a round-1-or-2 play and rounds 3..6 buy nothing you could not already have.
##
## THIS TOOL DOES NOT INVENT COSTS. It is a REMAP, and the distinction is the
## whole reason it is trustworthy:
##
##   * A from-scratch re-derivation off a budget formula would fight every
##     hand-tuned decision in the pool and hand back ~254 arbitrary changes, most
##     of them reversing a designer's deliberate call. It would also be circular:
##     the current costs were themselves tuned to `_probe_curve`'s budget line, so
##     re-deriving from that line mostly reproduces them.
##   * What is actually wrong is COMPRESSION, not ordering. 93 cards share cost 1
##     and 99 share cost 2 — the designer's relative judgements are intact, they
##     are just stacked on top of each other with no room to read.
##
## So: costs are remapped BAND BY BAND (old 0 -> new 1, old 1 -> new 1..3, and so
## on), and WITHIN each band the order is decided by POWER. Two cards the designer
## priced apart can never cross; two cards the designer priced the same are
## separated by the same budget model `tools/_probe_curve.gd` already audits
## against. The output is a DRAFT for review, exactly as the design doc requires —
## the derivation is not the answer.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cost_rescale.gd
## Flags (after a bare `--`):
##   --json      emit the proposed table as JSON to tools/_cost_rescale.json
##   --census    print the current cost histogram and stop

# Target share at each new cost, from ECONOMY_REDESIGN §2.2.
#
# THE DENOMINATOR IS DRAFTABLE CARDS, NOT THE WHOLE POOL. §2.2's shape describes
# what a player is OFFERED — and starter-rarity cards are never offered:
# `roll_card_reward` rolls common/uncommon/rare only, and the Recruit slate,
# the shop shelf and every reward pool inherit that. Measuring the shape over a
# denominator that includes 39 cards no player can ever draft is the C26 mistake
# (a coverage number whose denominator does not match what the driver can reach
# is not a measurement), and here it is not academic: starters are the cheapest
# cards in the game, so counting them drags the draftable curve upward and hides
# how expensive the real offers have become.
const TARGET := {1: 0.15, 2: 0.25, 3: 0.25, 4: 0.18, 5: 0.12, 6: 0.05}

# The starter shelf gets its OWN curve, because it is not a sample of anything —
# it is the opening hand, and an opening hand is a designed curve.
#
# Under the ramp, rounds 1 and 2 grant 1 and 2 Command. A ten-card opener must
# therefore be able to act on both, which needs roughly four cost-1 cards and
# three cost-2 (measured below as `dead-open`: the chance a five-card opening
# hand holds no cost-1 card at all). Anything at 4+ in an opener is a card that
# sits in hand for a third of the fight, which is what the retinue rewrite of
# 2026-07-28 was explicitly trying to get away from.
const STARTER_TARGET := {1: 0.48, 2: 0.36, 3: 0.16}

# HOW MUCH THE DESIGNER'S OLD PRICE IS WORTH AS EVIDENCE, in body-points per
# Command. This is the one number that decides the character of the whole remap,
# and getting it wrong is visible immediately in the hero-opener report below.
#
# A STRICT band mapping (old cost as an absolute gate, i.e. this value at
# infinity) was tried first and FAILED, for a reason worth recording: with 41% of
# the pool at old 1 and 42% at old 2, hitting the target shape forces *every*
# old-2 card to cost 3 or more. Hero openers are built from exactly that
# population, so eight of the ten shipped openers came back unable to play a
# single card on round 1 — a dead first turn, which is not a difficulty setting.
#
# The honest reading is that the old price is COMPRESSED evidence: it carries
# only two distinct values across 83% of the pool, so it cannot be the finest
# thing we know about a card. The power model has more resolution. So the old
# price is kept as a strong PRIOR — worth OLD_COST_PRIOR points per Command,
# which is the slope of the budget line `_probe_curve` audits against (2 points
# of body per Command) — and power decides the rest. Cards the designer priced
# apart still separate; a genuinely weak 2-drop may now sit below a strong 1-drop,
# which is the correction the compression was hiding.
const OLD_COST_PRIOR := 2.0


# ── Power model, lifted from tools/_probe_curve.gd so the two agree ──────────
# That probe asks "is this body over its cost's budget?"; we need the same
# quantity with the cost taken OUT — an absolute power in body-points, which is
# what makes two cards inside one band comparable.
const PREMIUM := {
	"swift": true, "ranged": true, "piercing": true, "poison": true,
	"lifelink": true, "armored": true, "regenerate": true, "last_stand": true,
	"shield": true, "rampage": true, "overrun": true,
}
const MINOR := {"thorns": true, "formation": true, "taunt": true}
# A downside makes a big body CHEAP to print, so it must SUBTRACT from power or
# every Doom body reads as a bomb. Same sign convention as _probe_curve.
const DOWNSIDE := {"doom": true, "wither": true}
const MARKERS := {"on_enter": true, "on_death": true, "on_play": true, "floop": true}

# Spells carry no ATK/HP, so _probe_curve skips them entirely — and they are a
# third of the pool. Their power is denominated in the SAME body-points as a
# creature's so the two can share a band: a point of damage to a creature is
# worth about a point of body, which is the exchange rate the clash already uses.
#
# THE SIGNAL IS THE RULES TEXT, and that is not a shortcut. 78 of 87 spells carry
# `spell: {type: "custom"}` — the effect lives in a resolver in Combat.gd and
# NOTHING in the data says what it does. A first draft that keyed off
# `spell.type` therefore scored every custom spell at one constant, which sorted
# a third of the pool ALPHABETICALLY inside its cost band. The desc is the only
# machine-readable statement of what the card actually does, it is the contract
# COPY_STYLE holds authoritative, and it is what the player prices the card by.
const SPELL_BASE := {
	# type: [points per unit of `value`, flat points]
	"damage": [1.0, 1.0],
	"damage_face": [1.6, 0.0],
	"none": [0.0, 3.0],
}
const SPELL_DEFAULT := [1.0, 2.0]

# Points per unit, read off the printed text. Damage to a creature is the unit
# (1.0) because trading a point of damage for a point of body is what the clash
# does all game; everything else is priced against that.
const TXT_DAMAGE := 1.0
const TXT_FACE := 1.6      # face damage is the only resource that wins
const TXT_ATK := 1.0
const TXT_HP := 0.75
const TXT_HEAL := 0.6      # hero HP, and only when you are behind
const TXT_DRAW := 2.0
const TXT_COMMAND := 2.0
const TXT_DESTROY := 6.0   # unconditional removal of any body
# A "to all" / "each" clause multiplies whatever it governs. 2.6 rather than 4.0
# because the board is rarely full and overkill is wasted.
const TXT_ALL := 2.6
# ...but "every CREATURE" is not "every ENEMY creature". A symmetric sweep takes
# your own line with it, which is why No Quarter can print "destroy every
# creature" at all. Scoring the two the same made it the highest-power card in
# the game while the simulation ranked it near the bottom.
const TXT_ALL_SYMMETRIC := 1.3
# A clause behind "If ..." pays only when its condition holds.
const TXT_CONDITIONAL := 0.55
# Exhaust removes the card from the fight after one use; Retain is the opposite.
# Without this, one-shot bombs (No Quarter, Banish, The Doubled Hour, The Black
# Contract) priced as though they could be cast every round.
const TXT_EXHAUST := 0.75
# Phrases that are a PRICE the card charges its owner, not a promise. A clause
# containing one is negated rather than added: The Black Contract's "Add
# War-Debt" puts a curse in your deck for the rest of the run, and reading it as
# +1.5 of value is how a deliberately-cheap rare with a crippling bill came out
# of the first draft at cost 5.
const TXT_COSTS := ["add war-debt", "add a curse", "add curse", "your hero takes",
	"lose ", "discard your", "sacrifice", "exhaust your", "take 2 damage",
	"add wound", "add a wound"]

var CDB: Node
var HDB: Node
var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	CDB = root.get_node_or_null("CardDB")
	HDB = root.get_node_or_null("HeroDB")
	if CDB == null:
		print("[rescale] FATAL no CardDB"); quit(1); return

	var want_json := false
	var census_only := false
	var verify := false
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "--json": want_json = true
		elif s == "--census": census_only = true
		elif s == "--verify": verify = true
	if verify:
		_verify(); return

	# ── Collect the entries a rescale is allowed to touch ────────────────────
	# Enemy-only cards carry cost 0 and are never paid for; curses are priced by
	# their own rules (Cowardice's 2 is a deliberate tax, not a power reading).
	# Tokens are summoned, never bought. All three are left exactly as they are.
	var rows: Array = []
	var skipped := {"enemy": 0, "curse": 0, "token": 0}
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	for id in ids:
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		var rarity := String(d.get("rarity", ""))
		var t := String(d.get("type", ""))
		if rarity == "enemy":
			skipped["enemy"] += 1; continue
		if CDB.is_curse(sid):
			skipped["curse"] += 1; continue
		if t not in ["creature", "spell", "armament"]:
			skipped["token"] += 1; continue
		rows.append({
			"id": sid, "cost": int(d.get("cost", 0)), "rarity": rarity, "type": t,
			"power": _power(d), "name": String(d.get("name", sid)),
		})

	# ── Census ───────────────────────────────────────────────────────────────
	var hist := {}
	for r in rows:
		hist[r["cost"]] = int(hist.get(r["cost"], 0)) + 1
	var keys: Array = hist.keys(); keys.sort()
	print("[rescale] %d rescalable entries (skipped %s)" % [rows.size(), str(skipped)])
	var line := "[rescale] CURRENT  "
	for k in keys:
		line += "%d:%d (%.0f%%)  " % [k, hist[k], 100.0 * float(hist[k]) / float(rows.size())]
	print(line)
	if census_only:
		quit(0); return

	# ── Assign ───────────────────────────────────────────────────────────────
	# Two shelves, two curves, one method. Each is ranked weakest-first and cut at
	# its own quota boundaries; neither borrows from the other, because they
	# answer different questions ("what am I offered?" vs "what do I open on?").
	var draft_rows: Array = []
	var starter_rows: Array = []
	for r in rows:
		if String(r["rarity"]) == "starter": starter_rows.append(r)
		else: draft_rows.append(r)

	var proposal := {}
	_assign(draft_rows, TARGET, proposal)
	_assign(starter_rows, STARTER_TARGET, proposal)
	# A quota is a SHAPE, and a shape does not know which ten cards a hero opens
	# on. Enforce the one thing that is not negotiable — every opener can act on
	# round 1 — instead of hoping the distribution happens to deliver it. Left to
	# chance it did not: the starved opener moved between `raider (alt)` and
	# `stalwart (alt)` on every tweak to the power model, which is the signal that
	# a constraint was being treated as an outcome.
	_relieve_starved_openers(rows, proposal)

	# Regroup for the transition matrix.
	var by_band := {}
	for r in rows:
		var b: int = clampi(int(r["cost"]), 0, 5)
		if not by_band.has(b): by_band[b] = []
		by_band[b].append(r)
	var band_keys: Array = by_band.keys(); band_keys.sort()
	var quota := {}
	for c in TARGET.keys():
		quota[c] = int(round(float(TARGET[c]) * float(draft_rows.size())))

	# ── Report ───────────────────────────────────────────────────────────────
	var nhist := {}
	for r in draft_rows:
		nhist[r["new"]] = int(nhist.get(r["new"], 0)) + 1
	var nkeys: Array = nhist.keys(); nkeys.sort()
	var nline := "[rescale] DRAFTABLE PROPOSED "
	for k in nkeys:
		nline += "%d:%d (%.0f%%)  " % [k, nhist[k], 100.0 * float(nhist[k]) / float(draft_rows.size())]
	print(nline)
	var tline := "[rescale] DRAFTABLE TARGET   "
	for k in [1, 2, 3, 4, 5, 6]:
		tline += "%d:%d (%.0f%%)  " % [k, quota[k], 100.0 * float(TARGET[k])]
	print(tline)

	# The transition matrix is the review surface: it says how each old price
	# splits, which is the only way to see at a glance whether a band was torn.
	print("\n[rescale] ===== OLD -> NEW =====")
	for b in band_keys:
		var counts := {}
		for r in by_band[b]:
			counts[r["new"]] = int(counts.get(r["new"], 0)) + 1
		var ck: Array = counts.keys(); ck.sort()
		var s := "[rescale]   old %d (n=%d) -> " % [b, (by_band[b] as Array).size()]
		for k in ck:
			s += "%d:%d  " % [k, counts[k]]
		print(s)

	# The starter shelf on its own — it is what every run opens on, so its curve
	# matters more than the pool's and is invisible inside the pool histogram.
	var shist := {}
	var sn := 0
	for r in rows:
		if String(r["rarity"]) != "starter": continue
		sn += 1
		shist[r["new"]] = int(shist.get(r["new"], 0)) + 1
	var sk: Array = shist.keys(); sk.sort()
	var sline := "[rescale] STARTERS (n=%d)  " % sn
	for k in sk:
		sline += "%d:%d  " % [k, shist[k]]
	print(sline)

	# ── The one hard constraint: a hero must have a round-1 play ─────────────
	# Round 1 grants exactly 1 Command. An opening deck with no cost-1 card deals
	# a five-card hand that cannot be played at all, which is not a difficulty
	# setting, it is a dead turn. This is the check that decides whether the
	# derivation is shippable.
	print("\n[rescale] ===== HERO OPENERS (round 1 = 1 Command) =====")
	var starve: Array = []
	if HDB != null:
		for hid0 in ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]:
			var hid := String(hid0)
			var h: Dictionary = HDB.get_hero(hid)
			for variant in ["deck", "alt"]:
				var deck: Array = []
				var label: String = hid
				if variant == "deck":
					deck = h.get("deck", [])
				else:
					var da: Dictionary = h.get("deck_alt", {})
					if da.is_empty(): continue
					deck = da.get("deck", [])
					label = hid + " (alt)"
				var ones := 0
				var breakdown := {}
				for cid in deck:
					var nc: int = int(proposal.get(String(cid), -1))
					if nc == 1: ones += 1
					breakdown[nc] = int(breakdown.get(nc, 0)) + 1
				# P(no cost-1 card in a 5-card opening hand from 10).
				var dead := _p_no_one(deck.size(), ones)
				var bk: Array = breakdown.keys(); bk.sort()
				var bs := ""
				for k in bk: bs += "%d:%d " % [k, breakdown[k]]
				print("[rescale]   %-16s cost-1 x%d  dead-open %.1f%%   [%s]"
					% [label, ones, dead * 100.0, bs.strip_edges()])
				if dead > 0.10:
					starve.append(label)
	if starve.is_empty():
		print("[rescale]   OK — every opener plays on round 1 at least 90%% of the time.")
	else:
		print("[rescale]   *** STARVED OPENERS: %s" % str(starve))

	# ── Independent cross-check: the simulation ranking ──────────────────────
	# `tools/_cardpower_ranking.txt` is a MEASURED lift (HP margin over a fixed
	# gauntlet, common random numbers) for 123 cards, produced by
	# `_probe_cardpower.gd`. It knows nothing about stat lines — it played the
	# games — so where it and this static model disagree, one of them is wrong,
	# and that disagreement list IS the review queue the design doc asks for.
	#
	# It is a CHECK, never an input: it covers half the pool, is two months old,
	# and a synergy card reads low in it by construction (the shell is filler).
	_cross_check(rows)

	# ── Per-card table, grouped by new cost for review ───────────────────────
	print("\n[rescale] ===== PROPOSAL (grouped by new cost) =====")
	rows.sort_custom(func(x, y):
		if int(x["new"]) != int(y["new"]): return int(x["new"]) < int(y["new"])
		if int(x["cost"]) != int(y["cost"]): return int(x["cost"]) < int(y["cost"])
		return float(x["power"]) < float(y["power"]))
	var cur := -1
	for r in rows:
		if int(r["new"]) != cur:
			cur = int(r["new"])
			print("[rescale] --- new cost %d ---" % cur)
		var moved := "" if int(r["new"]) == int(r["cost"]) else ("  (%d->%d)" % [r["cost"], r["new"]])
		print("[rescale]   %-24s %-9s %-8s pow %5.1f  old %d%s"
			% [r["id"], r["type"], r["rarity"], r["power"], r["cost"], moved])

	if want_json:
		var f := FileAccess.open("res://tools/_cost_rescale.json", FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(proposal, "  ", true))
			f.close()
			print("\n[rescale] wrote tools/_cost_rescale.json (%d entries)" % proposal.size())
	print("[rescale] DONE")
	quit(0)


## THE STANDING GATE (`--verify`). Reads the LIVE costs and asserts the two
## properties the rescale exists to create. Everything above is a one-shot
## derivation; this is the part that keeps being true.
##
## It gates the CONTRACT, never the exact numbers — a rebalance is allowed to
## move any card, and a gate that pins the table would simply be re-blessed every
## time and stop meaning anything.
##   A. Every hero opener can act on round 1 (Command 1). This is the property
##      the derivation could not reach on its own and had to be told, so it is
##      exactly the one that will rot.
##   B. The draftable curve still spans 1..6 with no tier empty and no tier
##      swallowing the pool — the compression this whole pass was fixing.
func _verify() -> void:
	var fails: Array = []
	var draft := {}       # new cost -> count, draftable only
	var live := {}        # id -> cost
	for id in CDB.CARD_POOL.keys():
		var sid := String(id)
		var d: Dictionary = CDB.CARD_POOL[sid]
		if CDB.is_curse(sid): continue
		if String(d.get("type", "")) not in ["creature", "spell", "armament"]: continue
		var c := int(d.get("cost", 0))
		live[sid] = c
		if String(d.get("rarity", "")) != "starter":
			draft[c] = int(draft.get(c, 0)) + 1

	# A — openers.
	if HDB == null:
		fails.append("HeroDB missing — cannot check openers")
	else:
		for hid0 in ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]:
			var hid := String(hid0)
			var h: Dictionary = HDB.get_hero(hid)
			for variant in ["deck", "alt"]:
				var deck: Array = []
				if variant == "deck":
					deck = h.get("deck", [])
				else:
					var da: Dictionary = h.get("deck_alt", {})
					if da.is_empty(): continue
					deck = da.get("deck", [])
				var ones := 0
				for cid in deck:
					if int(live.get(String(cid), 99)) <= 1: ones += 1
				var dead := _p_no_one(deck.size(), ones)
				var tag := "%s/%s" % [hid, variant]
				print("[verify] opener %-18s cost-1 x%d  dead-open %.1f%%" % [tag, ones, dead * 100.0])
				if dead > DEAD_OPEN_MAX:
					fails.append("%s opens dead %.0f%% of the time (only %d cost-1 cards). Round 1 grants 1 Command." % [tag, dead * 100.0, ones])

	# B — the curve still spans the ramp.
	var total := 0
	for c in draft.keys(): total += int(draft[c])
	var line := "[verify] draftable curve  "
	for c in [1, 2, 3, 4, 5, 6]:
		line += "%d:%d  " % [c, int(draft.get(c, 0))]
	print(line)
	for c in [1, 2, 3, 4, 5, 6]:
		if int(draft.get(c, 0)) <= 0:
			fails.append("no draftable card costs %d — the ramp buys nothing on round %d" % [c, c])
	for c in draft.keys():
		var share := float(draft[c]) / float(maxi(1, total))
		if share > 0.40:
			fails.append("cost %d holds %.0f%% of the draftable pool — the curve is compressed again" % [c, share * 100.0])
	if int(draft.get(0, 0)) > 0:
		fails.append("%d draftable cards still cost 0 — nothing should be free under a ramp" % int(draft[0]))

	if fails.is_empty():
		print("[verify] PROBE PASS: cost_rescale")
		quit(0)
	else:
		for f in fails:
			print("[verify] FAIL: %s" % f)
		print("[verify] PROBE FAIL: cost_rescale (%d)" % fails.size())
		quit(1)


## Every hero opener must be able to act on round 1, where Command is 1.
##
## Walks each shipped deck (and each unlockable variant); where a five-card
## opening hand would hold no cost-1 card more than DEAD_OPEN_MAX of the time,
## marks that deck's WEAKEST remaining starter down to cost 1 and re-checks.
## Weakest-first because the opener's cheap slot is what a weak body is for, and
## because it is the change least likely to matter anywhere else.
##
## Every override is printed. A silent repair here would hide exactly the thing a
## reviewer needs to see — that the derivation did not reach this on its own.
const DEAD_OPEN_MAX := 0.10

func _relieve_starved_openers(rows: Array, proposal: Dictionary) -> void:
	if HDB == null: return
	var by_id := {}
	for r in rows: by_id[String(r["id"])] = r
	for hid0 in ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]:
		var h: Dictionary = HDB.get_hero(String(hid0))
		for variant in ["deck", "alt"]:
			var deck: Array = []
			if variant == "deck":
				deck = h.get("deck", [])
			else:
				var da: Dictionary = h.get("deck_alt", {})
				if da.is_empty(): continue
				deck = da.get("deck", [])
			# Bounded: at most one markdown per distinct card in the deck, so a
			# deck the tool cannot satisfy ends the loop instead of spinning.
			for _guard in range(deck.size()):
				var ones := 0
				for cid in deck:
					if int(proposal.get(String(cid), 99)) == 1: ones += 1
				if _p_no_one(deck.size(), ones) <= DEAD_OPEN_MAX: break
				# Cheapest-to-print card in the deck that is not already at 1.
				var pick: Dictionary = {}
				var pick_pow := 99999.0
				for cid in deck:
					var r: Dictionary = by_id.get(String(cid), {})
					if r.is_empty(): continue
					if int(proposal.get(String(cid), 99)) <= 1: continue
					if float(r["power"]) < pick_pow:
						pick_pow = float(r["power"]); pick = r
				if pick.is_empty(): break
				proposal[String(pick["id"])] = 1
				pick["new"] = 1
				print("[rescale]   OPENER RELIEF: %s -> cost 1 (weakest in %s's %s, pow %.1f)"
					% [pick["id"], hid0, variant, pick_pow])


## Rank the cards this model and the SIMULATION both have an opinion about, and
## print the worst disagreements. Both are converted to a percentile inside the
## shared set so a body-point score and an HP margin can be compared at all.
func _cross_check(rows: Array) -> void:
	var f := FileAccess.open("res://tools/_cardpower_ranking.txt", FileAccess.READ)
	if f == null:
		print("\n[rescale] (no _cardpower_ranking.txt — cross-check skipped)")
		return
	var sim := {}
	while not f.eof_reached():
		var parts := f.get_line().strip_edges().split("\t", false)
		if parts.size() >= 2:
			sim[String(parts[1]).strip_edges()] = float(parts[0])
	f.close()

	var both: Array = []
	for r in rows:
		if sim.has(String(r["id"])):
			both.append({"id": r["id"], "new": r["new"], "cost": r["cost"],
				"model": float(r["power"]), "sim": float(sim[String(r["id"])])})
	if both.size() < 10:
		print("\n[rescale] (only %d cards in both — cross-check too thin)" % both.size())
		return

	var by_model: Array = both.duplicate()
	by_model.sort_custom(func(x, y): return float(x["model"]) < float(y["model"]))
	for i in range(by_model.size()):
		by_model[i]["pm"] = float(i) / float(maxi(1, by_model.size() - 1))
	var by_sim: Array = both.duplicate()
	by_sim.sort_custom(func(x, y): return float(x["sim"]) < float(y["sim"]))
	for i in range(by_sim.size()):
		by_sim[i]["ps"] = float(i) / float(maxi(1, by_sim.size() - 1))

	var agree := 0
	for r in both:
		r["gap"] = float(r["pm"]) - float(r["ps"])
		if absf(float(r["gap"])) <= 0.33: agree += 1
	print("\n[rescale] ===== CROSS-CHECK vs SIMULATED LIFT (%d cards both rate) =====" % both.size())
	print("[rescale] Raw agreement within a third of the range: %d of %d (%.0f%%)."
		% [agree, both.size(), 100.0 * float(agree) / float(both.size())])

	# READ THE CONFOUND BEFORE READING THE NUMBER ABOVE. `_probe_cardpower` stacks
	# FOUR COPIES of the test card into a TEN-card deck and plays it under the old
	# FLAT-3 economy, so a cheap card gets a consistent engine and an expensive one
	# clogs the draw — its own header calls this out ("high-cost cards lose a
	# little to curve-clog"). That bias runs along COST, which is the exact axis a
	# rescale moves, so the raw agreement figure cannot validate this work in
	# either direction. The line below measures how big the confound is; when it
	# is large, the raw number is about the instrument, not the proposal.
	var cost_corr := _rank_corr(both, "cost", "ps")
	print("[rescale] sim-lift vs OLD COST correlation: %+.2f  (a large negative value"
		% cost_corr)
	print("[rescale]   means the sim is substantially ranking cards BY PRICE — the")
	print("[rescale]   curve-clog confound — and the raw figure above is not evidence.)")

	# The honest comparison holds cost STILL: inside one old-cost band every card
	# paid the same clog, so a disagreement there is about the CARD. Same move as
	# the duplicate-pairing in `reference_ai_variant_measurement` — cancel the
	# nuisance variable rather than average over it.
	var bands := {}
	for r in both:
		var c: int = int(r["cost"])
		if not bands.has(c): bands[c] = []
		bands[c].append(r)
	var within: Array = []
	for c in bands.keys():
		var b: Array = bands[c]
		if b.size() < 6: continue
		var bm: Array = b.duplicate()
		bm.sort_custom(func(x, y): return float(x["model"]) < float(y["model"]))
		for i in range(bm.size()): bm[i]["bm"] = float(i) / float(maxi(1, bm.size() - 1))
		var bs: Array = b.duplicate()
		bs.sort_custom(func(x, y): return float(x["sim"]) < float(y["sim"]))
		for i in range(bs.size()): bs[i]["bs"] = float(i) / float(maxi(1, bs.size() - 1))
		for r in b:
			r["bgap"] = float(r["bm"]) - float(r["bs"])
			within.append(r)
	var wagree := 0
	for r in within:
		if absf(float(r["bgap"])) <= 0.33: wagree += 1
	if within.is_empty():
		print("[rescale] (no old-cost band large enough for a within-band check)")
		return
	print("[rescale] WITHIN-BAND agreement (cost held still): %d of %d (%.0f%%)."
		% [wagree, within.size(), 100.0 * float(wagree) / float(within.size())])
	within.sort_custom(func(x, y): return absf(float(x["bgap"])) > absf(float(y["bgap"])))
	print("[rescale] Worst WITHIN-BAND disagreements — REVIEW THESE:")
	for i in range(mini(10, within.size())):
		var r = within[i]
		var dir := "model says STRONGER than it plays" if float(r["bgap"]) > 0.0 \
			else "model says WEAKER than it plays"
		print("[rescale]   %-22s old %d -> new %d   model %.2f vs sim %.2f   %s"
			% [r["id"], r["cost"], r["new"], r["bm"], r["bs"], dir])


## Spearman-ish rank correlation between two keys over `rows`, in [-1, +1].
func _rank_corr(rows: Array, key_a: String, key_b: String) -> float:
	var n := rows.size()
	if n < 3: return 0.0
	var a: Array = rows.duplicate()
	a.sort_custom(func(x, y): return float(x[key_a]) < float(y[key_a]))
	for i in range(n): a[i]["_ra"] = float(i)
	var b: Array = rows.duplicate()
	b.sort_custom(func(x, y): return float(x[key_b]) < float(y[key_b]))
	for i in range(n): b[i]["_rb"] = float(i)
	var d2 := 0.0
	for r in rows:
		var d: float = float(r["_ra"]) - float(r["_rb"])
		d2 += d * d
	return 1.0 - (6.0 * d2) / (float(n) * (float(n) * float(n) - 1.0))


## Rank one shelf weakest-first and cut it at `target`'s quota boundaries,
## writing the result into `out`.
##
## The rank key fuses the two things we know about a card: the designer's old
## price (worth OLD_COST_PRIOR points per Command) and the measured power. Ties
## break on id so the derivation is REPRODUCIBLE — an unstable sort here means
## two runs disagree and neither is reviewable.
func _assign(shelf: Array, target: Dictionary, out: Dictionary) -> void:
	if shelf.is_empty(): return
	for r in shelf:
		r["rank"] = float(r["power"]) + OLD_COST_PRIOR * float(int(r["cost"]))
	shelf.sort_custom(func(x, y):
		if absf(float(x["rank"]) - float(y["rank"])) > 0.001:
			return float(x["rank"]) < float(y["rank"])
		return String(x["id"]) < String(y["id"]))
	var order: Array = target.keys()
	order.sort()
	var quota := {}
	for c in order:
		quota[c] = int(round(float(target[c]) * float(shelf.size())))
	var ci := 0
	var left: int = int(quota[order[0]])
	for r in shelf:
		# The last cost absorbs any rounding remainder, so every card is assigned
		# even when the quotas do not sum to the shelf size exactly.
		while left <= 0 and ci < order.size() - 1:
			ci += 1
			left = int(quota[order[ci]])
		var nc: int = int(order[ci])
		left -= 1
		out[r["id"]] = nc
		r["new"] = nc


## Absolute power in body-points. Denominated so a creature and a spell can be
## ranked against each other inside one band.
func _power(d: Dictionary) -> float:
	var t := String(d.get("type", ""))
	var p := 0.0
	var atk := int(d.get("atk", 0))
	if t == "creature":
		# HP defends only, so it is worth less than ATK per point — the same
		# ratio BoardEval uses (0.75) rather than _probe_curve's flat ATK+HP,
		# because here we are RANKING cards, not auditing a budget.
		#
		# A 0-1 ATK body is a WALL, and `_probe_curve` already buckets those
		# apart on the grounds that "high HP isn't a value engine". Same rule
		# here, or a support piece prices like a bomb: Battle Drummer (1/5
		# Armored, grants adjacent Swift) landed at cost 5 in the first draft
		# purely on hit points, which is a utility card sold as a finisher.
		var hp_worth := 0.5 if atk <= 1 else 0.75
		p = float(atk) + hp_worth * float(int(d.get("hp", 0)))
	else:
		p = _spell_power(d)
	# Keywords and effect dicts, same taxonomy as _probe_curve — but a keyword's
	# worth RIDES THE BODY it is printed on, and that is not a refinement, it is
	# the difference between a sensible curve and a broken one.
	#
	# Flat +2 per premium keyword made a 3/2 Swift with a small rider out-price a
	# 6/6: three cheap keywords beat any statline, so Headhunter (3/2 Swift),
	# The Bravo (4/1 Shield Swift) and Berserker all came out of the first draft
	# at cost 5, where the player would be paying a bomb's price for a body that
	# dies to anything. Swift doubles what a creature's ATK does; Shield buys one
	# hit. Both are worth more the more there is to double or protect.
	var kw_scale := 1.0
	if t == "creature":
		kw_scale = clampf(p / 7.0, 0.45, 1.15)
	for kw in d.get("keywords", []):
		var k := String(kw)
		if MARKERS.has(k): continue
		if DOWNSIDE.has(k): p -= 2.0
		elif PREMIUM.has(k): p += 2.0 * kw_scale
		else: p += 1.0 * kw_scale
	for ek in ["on_enter", "on_death", "floop", "adj_buff", "passive", "wither", "extra_damage"]:
		if d.has(ek): p += 1.0
	# ...but an effect dict is not automatically VALUE. `hero_pay` bills the
	# player's own hero, which is why Bloodsworn can print a 4/4 Lifesteal at
	# common. Counting its drawback as a bonus is a double error — it pushed the
	# card up the ranking on the strength of its own downside.
	if String((d.get("on_enter", {}) as Dictionary).get("type", "")) == "hero_pay":
		p -= 2.0
	if d.has("adj_buff"):
		var ab: Dictionary = d.get("adj_buff", {})
		if int(ab.get("atk", 0)) + int(ab.get("hp", 0)) >= 2:
			p += 1.0
	# Rarity is a GATE, not a stat — but a rare is drafted far less often, so it
	# is allowed to be stronger at the same price. Pull it down slightly here so
	# rarity alone does not push every rare to the top of its band.
	var rar := String(d.get("rarity", ""))
	if rar == "rare": p -= 1.0
	elif rar == "uncommon": p -= 0.5
	return p


func _spell_power(d: Dictionary) -> float:
	var sp: Dictionary = d.get("spell", {})
	var st := String(sp.get("type", ""))
	var p := 0.0
	if SPELL_BASE.has(st):
		var m: Array = SPELL_BASE[st]
		p = float(int(sp.get("value", 1))) * float(m[0]) + float(m[1])
	else:
		p = _desc_power(String(d.get("desc", "")))
	# How many times the card gets to do that, over one fight.
	var kws: Array = d.get("keywords", [])
	if "retain" in kws:
		p *= 1.4
	elif "exhaust" in kws:
		p *= TXT_EXHAUST
	return p


## Read a spell's power out of its printed rules text, in body-points.
##
## Deliberately a SHALLOW reader: it scores the numbers a card promises and the
## scope words that multiply them. It cannot understand a combo and does not try
## — the cross-check against the simulated ranking is what catches the cards it
## misreads, and those are reviewed by hand. Sentences are scored separately so
## a conditional second clause ("If it dies, ...") is discounted without
## discounting the whole card.
func _desc_power(desc_in: String) -> float:
	var desc := desc_in.to_lower()
	if desc.is_empty(): return SPELL_DEFAULT[1]
	var total := 0.0
	for raw in desc.split(".", false):
		var s := String(raw).strip_edges()
		if s.is_empty(): continue
		var w := 1.0
		if s.begins_with("if ") or s.contains(", if ") or s.contains(" if you") \
				or s.contains(" if it") or s.contains(" if none"):
			w = TXT_CONDITIONAL
		# "all"/"each"/"every" multiplies the clause it governs — by how much
		# depends on whether it spares your own line.
		var scope := 1.0
		if s.contains("all ") or s.contains("each ") or s.contains("every "):
			var one_sided: bool = s.contains("enemy") or s.contains("enemies") \
				or s.contains("opposing") or s.contains("foe") \
				or s.contains("your ") or s.contains("friendly")
			scope = TXT_ALL if one_sided else TXT_ALL_SYMMETRIC
		var clause := 0.0
		# Damage — face damage is worth more than creature damage.
		for n in _numbers_after(s, "damage"):
			clause += n * (TXT_FACE if s.contains("face") else TXT_DAMAGE)
		# ("deal N damage" is already counted by the `damage` needle above.)
		# Stat grants: "+2 ATK", "+1/+1", "+3 HP".
		clause += _plus_stats(s)
		for n in _numbers_after(s, "draw"):
			clause += n * TXT_DRAW
		if s.contains("draw a card") or s.contains("draw 1"):
			clause += TXT_DRAW
		for n in _numbers_after(s, "heal"):
			clause += n * TXT_HEAL
		for n in _numbers_after(s, "command"):
			clause += n * TXT_COMMAND
		if s.contains("destroy") or s.contains("banish") or s.contains("exile"):
			clause += TXT_DESTROY
		if s.contains("summon"):
			clause += 3.0
		# A clause that promised something the reader could not parse still did
		# SOMETHING — a floor keeps an unparseable effect from reading as blank.
		if clause <= 0.0:
			clause = 1.5
		# A clause that CHARGES the owner is subtracted, not added.
		var is_cost := false
		for needle in TXT_COSTS:
			if s.contains(String(needle)): is_cost = true; break
		if is_cost:
			clause = -clause
		total += clause * scope * w
	return total


## Every number appearing within a short window before or after `needle`.
## "Deal 3 damage" and "damage 3" both resolve; a number belonging to a different
## clause does not, because the window is tight.
func _numbers_after(s: String, needle: String) -> Array:
	var out: Array = []
	var at := s.find(needle)
	while at != -1:
		var lo: int = maxi(0, at - 12)
		var hi: int = mini(s.length(), at + needle.length() + 12)
		var win := s.substr(lo, hi - lo)
		var cur := ""
		for i in range(win.length()):
			var ch := win[i]
			if ch >= "0" and ch <= "9":
				cur += ch
			else:
				if cur != "": out.append(float(cur.to_int())); cur = ""
		if cur != "": out.append(float(cur.to_int()))
		at = s.find(needle, at + 1)
		# One window per needle occurrence is enough; a runaway loop here would
		# hang the probe silently.
		if out.size() > 8: break
	return out


## "+2 ATK" / "+1/+1" / "+3 HP" -> body-points.
func _plus_stats(s: String) -> float:
	var p := 0.0
	var at := s.find("+")
	while at != -1 and at < s.length() - 1:
		var i := at + 1
		var num := ""
		while i < s.length() and s[i] >= "0" and s[i] <= "9":
			num += s[i]; i += 1
		if num != "":
			var v := float(num.to_int())
			var rest := s.substr(i, 10)
			if rest.begins_with("/+"):
				# "+N/+M" — read both halves.
				var j := i + 2
				var num2 := ""
				while j < s.length() and s[j] >= "0" and s[j] <= "9":
					num2 += s[j]; j += 1
				p += v * TXT_ATK + float(num2.to_int()) * TXT_HP
			elif rest.contains("hp"):
				p += v * TXT_HP
			else:
				p += v * TXT_ATK
		at = s.find("+", at + 1)
	return p


## Probability that a 5-card opening hand off an `n`-card deck holding `ones`
## cost-1 cards contains none of them. Hypergeometric, computed as a product so
## it needs no factorials.
func _p_no_one(n: int, ones: int) -> float:
	var draw := 5
	if ones <= 0: return 1.0
	if n - ones < draw: return 0.0
	var p := 1.0
	for i in range(draw):
		p *= float(n - ones - i) / float(n - i)
	return p
