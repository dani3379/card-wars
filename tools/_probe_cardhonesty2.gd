extends SceneTree
## Card-honesty AUDIT v2 (2026-07-01). Beyond the numeric probe: cross-checks the
## DESC against the card's actual mechanics, and dumps a compact per-card mechanic
## line so type-vs-desc mismatches can be eyeballed.
##
## Auto-flags:
##  (A) a KEYWORD named in the desc (by its display name) that the card neither
##      carries in keywords[] nor plausibly GRANTS (desc has give/grant/gains).
##  (B) a keyword CARRIED in keywords[] that the desc never mentions (softer — the
##      icon shows it, but a rules-text card should usually say it).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardhonesty2.gd

const GRANT_WORDS := ["give", "grant", "gain", "gains", "gets", "becomes", "gain a", "turn "]

func _eff_str(eff: Dictionary) -> String:
	# type + the numeric knobs that a desc would name, so value lies are visible.
	var s := String(eff.get("type", "?"))
	for k in ["value", "threshold", "heal", "atk_gain", "self_damage", "count", "amount", "name"]:
		if eff.has(k):
			s += " %s=%s" % [k, str(eff[k])]
	return s

func _has_grant_language(desc: String) -> bool:
	var d := desc.to_lower()
	for w in GRANT_WORDS:
		if d.find(w) != -1:
			return true
	return false

func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	var KE = root.get_node_or_null("KeywordEffects")
	if CDB == null or KE == null:
		print("[honesty2] autoloads missing"); return true

	# display-name -> keyword id (for scanning descs). Multi-word displays first.
	var kw_display := {}
	for kid in KE.KEYWORDS.keys():
		var disp := String(KE.KEYWORDS[kid].get("display", "")).to_lower()
		# strip the trailing " n" placeholder on Wither/Doom displays
		disp = disp.replace(" n", "").strip_edges()
		if disp != "":
			kw_display[disp] = kid

	var flags_a: Array = []   # desc names a keyword the card doesn't have/grant
	var flags_b: Array = []   # card has a keyword the desc never names
	var dump: Array = []

	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = CDB.CARD_POOL[id]
		var ctype := String(c.get("type", ""))
		var desc := String(c.get("desc", ""))
		var dlow := desc.to_lower()
		var kws: Array = c.get("keywords", [])

		# ── (A) keyword named in desc but not carried / granted ──
		for disp in kw_display.keys():
			# Skip the generic structural labels that appear in prose, not as grants.
			if disp in ["on-enter", "on-death", "adj. buff", "adjacent", "slay", "summon"]:
				continue
			if dlow.find(disp) != -1:
				var kid: String = kw_display[disp]
				if not kws.has(kid) and not _has_grant_language(desc):
					flags_a.append("  %-20s names '%s' but keywords=%s  | %s" % [id, disp, str(kws), desc])

		# ── (B) carried keyword the desc never names (creatures only; skip structural) ──
		if ctype == "creature":
			for kid in kws:
				var disp2 := String(KE.KEYWORDS.get(kid, {}).get("display", "")).to_lower().replace(" n", "").strip_edges()
				if disp2 == "" or disp2 in ["on-enter", "on-death", "adj. buff", "structure"]:
					continue
				if disp2 != "" and dlow.find(disp2) == -1:
					flags_b.append("  %-20s carries '%s' but desc silent  | %s" % [id, kid, desc])

		# ── compact mechanic dump for eyeballing ──
		var mech := []
		if kws.size() > 0: mech.append("kw=" + str(kws))
		if c.has("on_enter"): mech.append("onEnter=" + _eff_str(c["on_enter"]))
		if c.has("on_play"): mech.append("onPlay=" + _eff_str(c["on_play"]))
		if c.has("on_death"): mech.append("onDeath=" + _eff_str(c["on_death"]))
		if c.has("floop"): mech.append("floop=" + String(c["floop"].get("type","?")))
		if c.has("passive"): mech.append("passive=" + String(c["passive"]))
		if c.has("adj_buff"): mech.append("adjBuff=" + str(c["adj_buff"]))
		if c.has("wither"): mech.append("wither=" + str(c["wither"]))
		if c.has("spell"):
			var sp: Dictionary = c["spell"]
			mech.append("spell=" + String(sp.get("type","?")) + ("/" + String(sp.get("id","")) if sp.get("type","")=="custom" else ""))
		if c.has("targeting"): mech.append("target=" + String(c["targeting"]))
		dump.append("%-20s [%s] {%s}\n      desc: %s" % [id, ctype, ", ".join(mech), desc])

	print("[honesty2] ===== (A) DESC names a keyword the card lacks & doesn't grant =====")
	if flags_a.is_empty(): print("  (none)")
	for f in flags_a: print(f)
	print("\n[honesty2] ===== (B) card CARRIES a keyword its desc never names =====")
	if flags_b.is_empty(): print("  (none)")
	for f in flags_b: print(f)
	print("\n[honesty2] mechanic dump follows (%d cards)" % dump.size())
	for line in dump:
		print(line)
	print("[honesty2] DONE")
	return true
