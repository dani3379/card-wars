extends SceneTree
## _probe_card_truth.gd — PASS 8 of docs/BUG_SWEEP_METHOD_20260829.md (class C9).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_card_truth.gd
##
## THE CARD SAYS X, THE DATA SAYS Y. This class hides from every other check
## because BOTH halves are individually well-formed — only their MEANING disagrees.
## It has the worst track record in the repo: the 2026-08-24 hand-audit found six in
## one sitting (Hoarfrost printing "stunned" while the code applies frozen; Camp
## Follower under-printing its own −1; Overrun printing +1 where the keyword grants
## 2/3; `structure` claiming "can't be attacked" beside the attackable Trebuchet).
##
## WHAT IS MECHANISABLE, AND WHAT IS NOT — both were measured before this file
## settled on one check, because two plausible ones turned out to be pure noise:
##
##   TRIED, REJECTED (156/474 hits): "every integer in the desc exists somewhere in
##   the card's data". Custom spells — 78 of them — keep their magnitudes in the
##   RESOLVER, not the data, so "It gets +2 ATK" over a data dict with no 2 in it is
##   completely correct. The direction is backwards.
##
##   TRIED, REJECTED (138/474 hits): "a keyword named in the desc must be in
##   keywords[]". A card that GRANTS a keyword names it without carrying it — "All
##   friendlies gain Swift this round" is a spell, not a Swift spell. Catching the
##   real Hoarfrost shape needs the prose compared against the RESOLVER's behaviour,
##   which is not statically derivable. That half of C9 stays a reading job, and the
##   method doc says so.
##
##   KEPT: the inverse of the first. Where a magnitude DOES live in data, the desc
##   must state it. That is exactly the Camp Follower shape (data said −1, prose did
##   not), it is precise, and it has no noise floor.
##
## Reports rather than fails: the remedy is a copy edit or a data change, both
## judgement calls. The COUNT is the signal.

## data path -> how the number reads in prose. Only fields that ARE magnitudes and
## ARE authored in data; anything a resolver owns is deliberately absent.
const MAGNITUDE_FIELDS: Array = [
	["spell", "value"],
	["on_enter", "value"],
	["on_death", "value"],
	["on_play", "value"],
	["adj_buff", "atk"],
	["adj_buff", "hp"],
	["type_buff", "atk"],
]
const FLAT_FIELDS: Array = ["wither", "extra_damage", "rampage"]

## KEYWORD-TICK FIELDS CARRY THEIR OWN DEFAULT, AND THE GLOSSARY SAYS SO.
## `rampage` reads "Gains +1 ATK this fight each time it kills an enemy creature
## (MORE IF A NUMBER IS SHOWN)" — so a card whose tick equals the default prints no
## number ON PURPOSE, and the resolver agrees (`get("rampage", 1)`). Checking those
## flagged Hydra and Ash Hound for saying exactly what the house rule tells them to.
## A tick ABOVE the default is still checked, which is the case that would lie —
## and is the shape the 2026-08-24 audit caught on Overrun (+1 printed, 2/3 granted).
const KEYWORD_TICK_DEFAULT: Dictionary = {
	"rampage": 1,
}

## card id -> why its magnitude legitimately goes unstated.
const WAIVED: Dictionary = {}

var _started := false
var _done := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _desc_states(desc: String, n: int) -> bool:
	# Word-boundary so 2 does not match inside 12, and so "+2"/"2/1" both count.
	var re := RegEx.create_from_string("(?<![0-9])%d(?![0-9])" % n)
	return re.search(desc) != null


func _run() -> void:
	print("[truth] PASS 8 — card magnitudes vs card text\n")
	var CDB := root.get_node_or_null("CardDB")
	var RS := root.get_node_or_null("RunState")
	if CDB == null or RS == null:
		print("[truth] FATAL: autoloads missing"); _done = true; quit(1); return

	var hits: Array = []
	var checked := 0
	var magnitudes := 0

	for variant in ["base", "plus"]:
		for cid_v in CDB.CARD_POOL:
			var cid := String(cid_v)
			var base: Dictionary = CDB.CARD_POOL[cid_v]
			if String(base.get("rarity", "")) == "enemy":
				continue
			var d: Dictionary = base.duplicate(true)
			if variant == "plus":
				if CDB.get_plus_upgrade(cid).is_empty():
					continue
				d = RS._apply_plus_upgrade(d)
			var desc := String(d.get("desc", "")).strip_edges()
			if desc == "" or WAIVED.has(cid):
				continue
			checked += 1
			var tag := "%s%s" % [cid, "+" if variant == "plus" else ""]
			var unstated: Array = []

			for path in MAGNITUDE_FIELDS:
				var sub = d.get(String(path[0]), null)
				if not (sub is Dictionary):
					continue
				var sd: Dictionary = sub
				if not sd.has(String(path[1])):
					continue
				var n := int(sd[String(path[1])])
				if n == 0:
					continue
				magnitudes += 1
				if not _desc_states(desc, n):
					unstated.append("%s.%s = %d" % [path[0], path[1], n])
			for f in FLAT_FIELDS:
				if not d.has(f):
					continue
				var n2 := int(d[f])
				if n2 == 0:
					continue
				if int(KEYWORD_TICK_DEFAULT.get(f, -1)) == n2:
					continue          # the keyword's own default — printing it is wrong
				magnitudes += 1
				if not _desc_states(desc, n2):
					unstated.append("%s = %d" % [f, n2])

			if not unstated.is_empty():
				hits.append({"tag": tag, "fields": unstated, "desc": desc})

	print("[truth] %d card faces, %d authored magnitudes checked\n" % [checked, magnitudes])
	if hits.is_empty():
		print("  OK    every authored magnitude is stated in its card's text")
	else:
		print("  NOTE  %d face(s) whose data carries a number the text never says:"
			% hits.size())
		for h in hits:
			print("          %-24s %s" % [String(h.tag), str(h.fields)])
			print("                %s" % String(h.desc))
	print("\n[truth] %d note(s) — read each; the fix is prose or data, never bulk"
		% hits.size())
	_done = true
	quit(0)
