extends SceneTree
## Card-furniture honesty probe (2026-07-10 surgical pass).
## The inline keyword stamps (KeywordEffects.decorate_keywords) only mark a
## keyword where its display name appears in the rules text — a keyword whose
## word never shows up gets NO device anywhere on the hand card now that the
## bottom-margin roundel row is retired. This probe enforces that contract:
##   1. every keywords[] entry's display name appears in the card's desc,
##      base AND "+"-upgraded (UPGRADES desc overrides checked) — except the
##      entries in ACCEPTED, each a deliberate prose-explains-it decision;
##   2. every spell's one-line footer ("SPELL — {contract} · {economy}") fits
##      the 230px box (≤ 31 chars);
##   3. `scope` only appears on targeting:"none" spells.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_card_furniture.gd

# "card_id:keyword" -> why the missing word is fine. Every entry here means
# "this keyword has no stamp and no icon on the hand card" — keep it short.
const ACCEPTED: Dictionary = {
	"torchbearer:adj_buff": "prose 'Adjacent friendlies +1 ATK'; the Adjacent word gilds+hints",
	# Same card shape and the same prose pattern as Torchbearer above — it is a
	# HERO-RETINUE starter (2026-07-28) and simply never got the waiver its twin
	# already had, so this gate had been red on it since. Forcing the literal
	# "Adj. Buff" into the desc instead would be the wrong fix twice over: it is
	# a UI word, not a road word, and COPY_STYLE's whole point is that the
	# sentence explains the rule. Both descs gild "Adjacent", which carries the
	# hover glossary.
	"standard_page:adj_buff": "prose 'Adjacent friendlies have +N HP'; the Adjacent word gilds+hints",
	"ironclad_veteran:on_enter": "prose 'Enters with...' carries the timing",
	"gallows_writ:exhaust": "the authored EXHAUST footer carries the keyword; exact rules prose stays uncluttered",
	# Same shape as gallows_writ above, and here the two gates are in DIRECT
	# CONFLICT: The Black Contract's desc is EXACTLY 90 characters, which is
	# copy_lint's per-card budget, so appending " Exhaust." (+9) turns copy_lint
	# red on both the base and the "+" desc. Tried it, measured it, reverted it.
	# Every shorter phrasing costs a real rule — "non-token" is what stops tokens
	# triggering it, and "2nd copy" is what says a SECOND copy draws. The footer
	# (Card2D._spell_footer_text) prints the EXHAUST contract on the card face, so
	# the keyword is on screen; only the prose repetition is missing.
	"unholy_bargain:exhaust": "desc is at copy_lint's 90-char budget; the EXHAUST footer carries the keyword",
}

var _fails: Array = []
var _accepted_hits: Array = []
var _started := false
# Autoload globals aren't compiled into --script SceneTree contexts; fetch the
# singleton instances off the root like the other probes do.
var DB: Node
var KW: Node


func _process(_d: float) -> bool:
	if _started:
		return false
	_started = true
	DB = root.get_node("CardDB")
	KW = root.get_node("KeywordEffects")
	_run()
	return false


func _kw_display(kw: String) -> String:
	if not KW.KEYWORDS.has(kw):
		return ""
	return String(KW.KEYWORDS[kw].display).trim_suffix(" N")


func _desc_names_kw(desc: String, kw: String) -> bool:
	var disp := _kw_display(kw)
	if disp == "":
		return false
	return desc.to_lower().contains(disp.to_lower())


func _footer_for(data: Dictionary) -> String:
	var contract := ""
	match String(data.get("targeting", "none")):
		"enemy_creature":    contract = "TARGET ENEMY"
		"friendly_creature": contract = "TARGET ALLY"
		"any_creature":      contract = "ANY CREATURE"
		"any":               contract = "ANY TARGET"
		"lane":              contract = "TARGET LANE"
		"friendly_then_enemy": contract = "ALLY · ENEMY"
		"two_enemies":       contract = "TWO ENEMIES"
		"friendly_lane":     contract = "ALLY · LANE"
		_:                   contract = String(data.get("scope", ""))
	var parts: Array[String] = []
	if contract != "":
		parts.append(contract)
	var kws: Array = data.get("keywords", [])
	if "exhaust" in kws:
		parts.append("EXHAUST")
	elif "retain" in kws:
		parts.append("RETAIN")
	if parts.is_empty():
		return "SPELL"
	return " · ".join(parts)


func _run() -> void:
	var unknown_kws: Array = []
	for id in DB.CARD_POOL.keys():
		var data: Dictionary = DB.CARD_POOL[id]
		var cid := String(id)
		if DB.is_curse(cid):
			continue
		# ── 1. keyword word present in base + upgraded desc ──
		var base_desc := String(data.get("desc", ""))
		var up: Dictionary = DB.get_plus_upgrade(cid)
		var up_desc := String(up.get("desc", base_desc))
		var up_kws: Array = data.get("keywords", []).duplicate()
		for ak in up.get("add_keywords", []):
			if not up_kws.has(ak):
				up_kws.append(ak)
		for rk in up.get("remove_keywords", []):
			up_kws.erase(rk)
		for kw_v in data.get("keywords", []):
			var kw := String(kw_v)
			if not KW.KEYWORDS.has(kw):
				unknown_kws.append("%s:%s" % [cid, kw])
				continue
			_check_named(cid, kw, base_desc, "base")
		for kw_v in up_kws:
			var kw := String(kw_v)
			if not KW.KEYWORDS.has(kw):
				continue
			_check_named(cid, kw, up_desc, "plus")
		# ── 2 + 3. footer fits; scope only on untargeted spells ──
		if String(data.get("type", "")) == "spell":
			var foot := _footer_for(data)
			if foot.length() > 31:
				_fails.append("FOOTER_LONG %s: \"%s\" (%d chars)" % [cid, foot, foot.length()])
			if data.has("scope") and String(data.get("targeting", "none")) != "none":
				_fails.append("SCOPE_ON_TARGETED %s" % cid)
		elif String(data.get("type", "")) == "armament":
			var arm_foot := "ARMAMENT · ALLY · EXHAUST"
			if arm_foot.length() > 31:
				_fails.append("FOOTER_LONG %s: \"%s\" (%d chars)" % [cid, arm_foot, arm_foot.length()])
			if String(data.get("targeting", "")) != "friendly_creature" \
					or data.get("armament", {}).is_empty():
				_fails.append("BAD_ARMAMENT_CONTRACT %s" % cid)
		elif data.has("scope"):
			_fails.append("SCOPE_ON_CREATURE %s" % cid)

	if not unknown_kws.is_empty():
		print("UNKNOWN_KEYWORDS (no KEYWORDS entry, informational): ", ", ".join(unknown_kws))
	for a in _accepted_hits:
		print("ACCEPTED: ", a)
	if _fails.is_empty():
		print("PROBE_CARD_FURNITURE_OK")
		quit(0)
	else:
		for f in _fails:
			print("FAIL ", f)
		print("PROBE_CARD_FURNITURE_FAILED (%d)" % _fails.size())
		quit(1)


func _check_named(cid: String, kw: String, desc: String, which: String) -> void:
	if _desc_names_kw(desc, kw):
		return
	var key := "%s:%s" % [cid, kw]
	if ACCEPTED.has(key):
		_accepted_hits.append("%s (%s)" % [key, ACCEPTED[key]])
		return
	_fails.append("KW_UNNAMED %s (%s desc misses \"%s\")" % [key, which, _kw_display(kw)])
