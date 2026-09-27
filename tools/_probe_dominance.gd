extends SceneTree
## _probe_dominance.gd — PASS 23 of docs/BUG_SWEEP_METHOD_20260829.md (class C23).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_dominance.gd
##
## RELATIONAL DESIGN ANALYSIS — every other pass reads one thing at a time.
##
## Twenty-two classes and not one of them ever compares two pieces of content TO
## EACH OTHER. Every gate so far asks "is this card well-formed / reachable /
## correctly merged"; none asks "is this card worth playing GIVEN the one next to
## it". That is a real hole, because a strictly dominated card is dead content by a
## route no reachability census can see: it rolls, it appears in the slate, the
## player looks at it and correctly never picks it. C20 would count it as reachable.
##
## THE ORACLE IS THE RARITY CURVE, which makes this mechanical rather than a matter
## of taste. Card A dominates card B when A costs no more, has no worse stats, has
## every keyword B has, carries every triggered ability B carries, and B brings
## nothing of its own. Then:
##   · a RARER card dominating a commoner one is the curve working as intended and
##     is not reported;
##   · SAME-RARITY dominance is a dead pick — two cards compete for one slot and one
##     of them is never the answer;
##   · a COMMONER card dominating a rarer one is the curve INVERTED, which is the
##     sharpest finding here: the rare is a downgrade the game presents as a prize.
##
## The second half needs no design judgement at all. Every "+" forge must be
## STRICTLY BETTER than the card it upgrades — an upgrade that is equal or worse is
## unambiguously a bug, and `_probe_upgrade_merge` (C2/C9) cannot see it: that pass
## proves the delta keys are CONSUMED, never that the result is an improvement.
##
## Report, not hard failure, for dominance (an ability this reads as "nothing" may
## carry real text) — but the "+" checks are hard, because there is no defensible
## reading of a downgrade sold as an upgrade.

## Rarity order for the curve comparison.
const RARITY_RANK := {"starter": 0, "common": 1, "uncommon": 2, "rare": 3}

## Fields that mean "this card does something the stat line does not say".
## `armament` belongs here: omitting it made two armaments with completely
## different payloads ({atk, keywords} vs {effect: adjacent_strikes}) compare as
## though neither had an ability at all, so the cheaper one "dominated" the other.
const ABILITY_KEYS := ["on_enter", "on_death", "on_play", "floop", "adj_buff",
	"passive", "spell", "armament", "wither", "extra_damage", "type_buff",
	"per_gold", "buff_ctype_keyword", "buff_per_ctype", "per_ctype",
	"buff_ctype_hp", "dismiss_muster", "doom", "curse_on_draw", "sniper"]

## KEYWORDS THAT ARE A COST, NOT A BONUS. Treating every extra keyword as strictly
## better made Live Coal (4/3 Swift + DOOM 2) "dominate" Hired Blade (3/3 Swift) —
## but Doom is a death timer, so the bigger body is paying for its size and the two
## cards are a real choice. A card carrying one of these is never dominating on
## account of it.
const DOWNSIDE_KEYWORDS := ["doom", "wither", "exhaust", "fragile", "curse"]

var CardDB: Node
var _started := false
var _done := false
var _fails := 0
var _reports := 0


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


func _abilities(cd: Dictionary) -> Array:
	var out: Array = []
	for k in ABILITY_KEYS:
		if cd.has(k):
			out.append(k)
	out.sort()
	return out


func _kw(cd: Dictionary) -> Array:
	var out: Array = []
	for k in cd.get("keywords", []):
		out.append(String(k))
	out.sort()
	return out


## Does A dominate B — same role, never worse, and B offers nothing back?
func _dominates(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("type", "")) != String(b.get("type", "")):
		return false
	if int(a.get("cost", 99)) > int(b.get("cost", 0)):
		return false
	if String(a.get("type", "")) == "creature":
		if int(a.get("atk", 0)) < int(b.get("atk", 0)):
			return false
		if int(a.get("hp", 0)) < int(b.get("hp", 0)):
			return false
		# TRIBE IS NOT COSMETIC. Six tribes each have payoff keystones, so a Dead
		# 2/2 and a Beast 4/2 at the same cost are not substitutes — the smaller
		# one feeds Gravepact and the reap spine. Comparing across tribes made War
		# Boar "dominate" Grave Soldier, which is only true in a deck that cares
		# about neither.
		if String(a.get("ctype", "")) != String(b.get("ctype", "")):
			return false
	# B's keywords must all be present on A; B may not have one A lacks.
	for k in _kw(b):
		if not (k in _kw(a)):
			return false
	# A keyword A has that B lacks only counts as an advantage if it IS one.
	for k in _kw(a):
		if k in DOWNSIDE_KEYWORDS and not (k in _kw(b)):
			return false
	# ABILITIES MUST MATCH BY PAYLOAD, NOT BY KEY. Comparing only the presence of a
	# key made every spell "comparable" to every other spell — they all carry a
	# `spell` key and 0/0 stats, so the cheapest one appeared to dominate the
	# entire spell pool, and the pass produced 1,077 findings that were all noise.
	# Sling Stone does not dominate Hex; they do different things. Two cards are
	# only comparable when they do the SAME thing to a different degree.
	if _abilities(a) != _abilities(b):
		return false
	for k in _abilities(b):
		var va = a.get(k)
		var vb = b.get(k)
		if typeof(va) != typeof(vb):
			return false
		if typeof(vb) == TYPE_DICTIONARY:
			# Same effect KIND, and A's magnitudes never worse. A differing type is
			# a different card, not a worse one.
			if String((va as Dictionary).get("type", "")) \
					!= String((vb as Dictionary).get("type", "")):
				return false
			for f in (vb as Dictionary):
				if f == "type":
					continue
				var fa = (va as Dictionary).get(f)
				var fb = (vb as Dictionary).get(f)
				if typeof(fa) != typeof(fb):
					return false
				if typeof(fb) in [TYPE_INT, TYPE_FLOAT]:
					if float(fa) < float(fb):
						return false
				elif fa != fb:
					return false
		elif va != vb and typeof(vb) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		elif typeof(vb) in [TYPE_INT, TYPE_FLOAT] and float(va) < float(vb):
			return false
	# Targeting is part of what a spell IS: a spell that hits one enemy is not a
	# worse version of one that hits anything.
	if String(a.get("targeting", "")) != String(b.get("targeting", "")):
		return false
	# Strictly better somewhere, or they are simply two printings of one card.
	var strictly := int(a.get("cost", 0)) < int(b.get("cost", 0)) \
		or int(a.get("atk", 0)) > int(b.get("atk", 0)) \
		or int(a.get("hp", 0)) > int(b.get("hp", 0)) \
		or _kw(a).size() > _kw(b).size() \
		or _abilities(a).size() > _abilities(b).size()
	return strictly


func _playable() -> Array:
	var out: Array = []
	for cid in CardDB.CARD_POOL:
		var cd: Dictionary = CardDB.CARD_POOL[cid]
		var r := String(cd.get("rarity", ""))
		if r == "enemy" or bool(cd.get("token", false)) or CardDB.is_curse(cid):
			continue
		if cd.has("draftable") and not bool(cd.get("draftable", true)):
			continue
		out.append(cid)
	return out


func _scan_dominance() -> void:
	print("\n[dom] --- strict dominance between playable cards ---")
	var ids := _playable()
	var same_rarity: Array = []
	var inverted: Array = []
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var ca: Dictionary = CardDB.CARD_POOL[a]
			var cb: Dictionary = CardDB.CARD_POOL[b]
			if not _dominates(ca, cb):
				continue
			var ra: int = int(RARITY_RANK.get(String(ca.get("rarity", "")), 9))
			var rb: int = int(RARITY_RANK.get(String(cb.get("rarity", "")), 9))
			var line := "%s (%s %s, %d/%d for %d) dominates %s (%s %s, %d/%d for %d)" % [
				String(ca.get("name", a)), a, String(ca.get("rarity", "")),
				int(ca.get("atk", 0)), int(ca.get("hp", 0)), int(ca.get("cost", 0)),
				String(cb.get("name", b)), b, String(cb.get("rarity", "")),
				int(cb.get("atk", 0)), int(cb.get("hp", 0)), int(cb.get("cost", 0))]
			if ra < rb:
				inverted.append(line)      # a commoner card beating a rarer one
			elif ra == rb:
				same_rarity.append(line)
			# ra > rb (rarer beats commoner) is the curve working; not reported.
	print("        %d same-rarity, %d curve-inverting" % [
		same_rarity.size(), inverted.size()])
	# THE SHARPEST FINDING: the game rolls a rarer card, presents it as the better
	# prize, and it is a strict downgrade on something the player can get commonly.
	if not inverted.is_empty():
		print("  HIT   THE RARITY CURVE IS INVERTED here — a commoner card is")
		print("        strictly better than a rarer one it competes with:")
		for l in inverted:
			print("           %s" % l)
		_reports += inverted.size()
	else:
		print("  PASS  no commoner card strictly dominates a rarer one")
	if not same_rarity.is_empty():
		print("  HIT   %d same-rarity dead pick(s) — two cards at one rarity where"
			% same_rarity.size())
		print("        one is never the answer:")
		for l in same_rarity:
			print("           %s" % l)
		_reports += same_rarity.size()
	else:
		print("  PASS  no same-rarity card is strictly dominated")


## Every "+" must be strictly better than its base. This one is a HARD check: an
## upgrade that is equal or worse has no defensible reading, and C2/C9 cannot see it
## because that pass proves the delta KEYS are consumed, never that the RESULT
## improves. The Counterorders bug was a key that never merged; this is the other
## half — a key that merges into no improvement at all.
func _scan_upgrades() -> void:
	print("\n[dom] --- every \"+\" forge must be strictly better than its base ---")
	var worse: Array = []
	var equal: Array = []
	var checked := 0
	for cid in _playable():
		if not CardDB.is_upgradeable(cid):
			continue
		var delta: Dictionary = CardDB.get_plus_upgrade(cid)
		if delta.is_empty():
			continue
		checked += 1
		# Read the DELTA the game will merge, not a re-derived guess at it.
		var d_cost := int(delta.get("cost", 0))
		var d_atk := int(delta.get("atk", 0))
		var d_hp := int(delta.get("hp", 0))
		var gained_kw: int = (delta.get("keywords", []) as Array).size()
		# Any non-stat key (value bumps, extra draws, sub-effect deepening, a
		# rewritten desc that names a bigger number) counts as an improvement.
		var other := 0
		for k in delta:
			if k in ["cost", "atk", "hp", "keywords", "desc"]:
				continue
			other += 1
		var better := d_atk > 0 or d_hp > 0 or d_cost < 0 or gained_kw > 0 or other > 0
		# A DESC-ONLY DELTA IS NOT AUTOMATICALLY A LIE. Some upgrades are driven at
		# the RESOLVER by an `is_upgraded` read rather than by a merged field —
		# `Combat._apply_armament` has an explicit per-id match block granting the
		# forged bonus, and CLAUDE.md documents the same pattern for several
		# creature passives. The first version of this check did not know that and
		# accused all six armaments of advertising stats they do not deliver, which
		# was simply false: they deliver exactly what their "+" text promises.
		if not better and _resolver_reads_upgraded(cid):
			better = true
		var regressed := d_atk < 0 or d_hp < 0 or d_cost > 0
		var name := String(CardDB.CARD_POOL[cid].get("name", cid))
		if regressed and not better:
			worse.append("%s (%s): %s" % [name, cid, str(delta)])
		elif not better:
			equal.append("%s (%s): %s  (no merged delta and no is_upgraded resolver)"
				% [name, cid, str(delta)])
	print("        %d upgradeable cards checked" % checked)
	_check(checked > 0, "the upgrade table was actually read (vacuity guard)")
	_check(worse.is_empty(), "no \"+\" forge is strictly WORSE than its base")
	for w in worse:
		print("           %s" % w)
	_check(equal.is_empty(), "no \"+\" forge leaves the card unchanged")
	for e in equal:
		print("           %s" % e)


## Is this card's forged bonus granted in CODE rather than by the merged delta?
## Looks for the card id within a dozen lines of an `is_upgraded` / `upgraded` read
## in any gameplay script — the shape `Combat._apply_armament` uses.
func _resolver_reads_upgraded(cid: String) -> bool:
	# SEARCH THE RESOLVER'S OWN KEY, NOT JUST THE CARD ID. Custom spells are
	# dispatched on `spell.id`, which is frequently NOT the card id — Lock Shields
	# resolves under "testudo", Countermarch under "baggage_train", Turncoat under
	# "turncoat". Looking only for the card id found nothing and accused all three
	# of shipping an inert "+", when every one of them honours the forge.
	var needles: Array = [cid]
	var cd: Dictionary = CardDB.CARD_POOL.get(cid, {})
	var sp = cd.get("spell", null)
	if typeof(sp) == TYPE_DICTIONARY:
		var sid := String((sp as Dictionary).get("id", ""))
		if sid != "" and sid != cid:
			needles.append(sid)
	for path in ["res://scripts/scenes/Combat.gd", "res://scripts/data/KeywordEffects.gd",
			"res://scripts/net/CombatNet.gd", "res://scripts/Card2D.gd"]:
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		var lines := fa.get_as_text().split("\n")
		fa.close()
		for i in lines.size():
			var hit := false
			for n in needles:
				if String(lines[i]).find('"%s"' % String(n)) >= 0:
					hit = true
					break
			if not hit:
				continue
			var lo: int = maxi(0, i - 12)
			var hi: int = mini(lines.size() - 1, i + 12)
			for j in range(lo, hi + 1):
				# THREE different mechanisms drive a forged bonus in this codebase,
				# and a check that knows only one accuses the other two. Merged
				# deltas are handled by the caller; `is_upgraded` is read directly
				# by `_apply_armament` and several creature passives; and the
				# custom-spell resolvers use a local `is_plus` computed from it
				# (`long_roll` pays 7/16 forged against 5/12 base entirely that
				# way). Missing `is_plus` is what made this pass accuse eight
				# perfectly correct spells.
				var t := String(lines[j])
				if t.findn("upgraded") >= 0 or t.findn("is_plus") >= 0 \
						or t.findn("plus_dmg") >= 0:
					return true
	return false


func _run() -> void:
	print("[dom] PASS 23 — content compared against its neighbours, not itself")
	CardDB = root.get_node_or_null("CardDB")
	if CardDB == null:
		print("[dom] FATAL: CardDB missing"); _done = true; quit(1); return
	print("[dom] %d playable cards" % _playable().size())
	_scan_dominance()
	_scan_upgrades()
	print("\n[dom] %d design report(s); %s" % [_reports,
		"gates OK" if _fails == 0 else "%d HARD FAIL" % _fails])
	print("[dom] Dominance is a REPORT — an ability this reads as \"nothing\" may")
	print("[dom] carry real text, so each wants a human. The \"+\" checks are hard:")
	print("[dom] a downgrade sold as an upgrade has no defensible reading.")
	_done = true
	quit(1 if _fails > 0 else 0)
