extends Node
## _probe_trigger_text.gd — does a foe's rules text name the right army?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_trigger_text.tscn
##
## `Card2D._synthesized_rules_text` is the ONLY rules text 105 authored enemy
## bodies ever get: EncounterDB decks are terse ({name, atk, hp, kw}) and carry no
## `desc`, so the battle-log hover preview composes one from their triggers.
##
## Until 2026-09-29 it was worded from the CARD OWNER's point of view while being
## shown exclusively on ENEMY cards, so four lines named the wrong army — a foe's
## on-death read "deal N damage to all ENEMY creatures" when the handler walks the
## PLAYER's line. Missing rules text is a gap; text asserting the opposite of what
## the code does is worse, because the player prices a decision against it.
##
## This gate is a DIFFERENTIAL, which is what makes it need no taste: the same
## effect dict is rendered on a player card and on an enemy card, and the two must
## name DIFFERENT armies. A table that has drifted back to one perspective returns
## the same string for both and fails, whatever the wording happens to be.
##
## Runs as a SCENE: Card2D names KeywordEffects, and CLAUDE.md's C14 lesson is
## that naming Card2D at parse time in a `--script` probe drags it into the
## pre-autoload compile and the card silently instantiates scriptless.

const CARD_SCENE := "res://scenes/card_2d.tscn"

# One authored dict per effect type whose target depends on side, taken from real
# EncounterDB bodies. `summon` and `draw` are deliberately absent: they act on the
# card's OWN side, so they SHOULD read the same either way.
const SIDED: Array = [
	{"type": "damage_face", "value": 3},
	{"type": "damage_all_enemies", "value": 2},
	{"type": "damage_random_player", "value": 2},
	{"type": "debuff_all_player_atk", "value": 1},
	{"type": "damage_opposing_lane", "value": 2},
]
const SIDE_NEUTRAL: Array = [
	{"type": "summon", "atk": 2, "hp": 2},
	{"type": "draw", "value": 1},
	# ENEMY-ONLY BY CONSTRUCTION, and it belongs here rather than above. Its
	# handler is `if is_enemy` guarded and reads `ctx._hand`, so it can only ever
	# exist on a foe's card and always empties the PLAYER's hand -- there is no
	# player-side reading for it to differ FROM. The first draft of this gate
	# demanded it flip, which is a test asserting a property nothing promises.
	{"type": "discard_random", "value": 1},
]

var _fails := 0
var _checks := 0


func _ready() -> void:
	var scene: PackedScene = load(CARD_SCENE)
	if scene == null:
		print("[trigtext] FATAL: card scene missing")
		get_tree().quit(1)
		return

	print("[trigtext] does a foe's synthesised rules text name the right army?\n")

	# ── A. every side-dependent effect must read differently on the two sides ──
	print("[trigtext] --- A. side-dependent effects ---")
	for eff in SIDED:
		var mine := _render(scene, eff, false)
		var theirs := _render(scene, eff, true)
		_check("%s differs by side" % String(eff["type"]), mine != theirs,
			"both sides render \"%s\"" % mine)
		# The foe's copy must speak to the player about the player.
		_check("%s names YOU on a foe card" % String(eff["type"]),
			theirs.to_lower().contains("you"),
			"foe copy is \"%s\"" % theirs)
		# And a player card must never tell the player its own effects hit them.
		_check("%s does not accuse the player on their own card" % String(eff["type"]),
			not mine.to_lower().contains("your creature")
				and not mine.to_lower().contains("you discard"),
			"own copy is \"%s\"" % mine)
		print("      %-24s mine: %s" % [String(eff["type"]), mine])
		print("      %-24s foe : %s" % ["", theirs])

	# ── B. effects on the card's OWN side must NOT flip ────────────────────────
	# The vacuity guard for A: if the renderer flipped everything blindly, A would
	# pass for the wrong reason.
	print("\n[trigtext] --- B. own-side effects must read the same ---")
	for eff in SIDE_NEUTRAL:
		var mine := _render(scene, eff, false)
		var theirs := _render(scene, eff, true)
		_check("%s is side-neutral" % String(eff["type"]), mine == theirs,
			"mine \"%s\" vs foe \"%s\"" % [mine, theirs])
		print("      %-24s both: %s" % [String(eff["type"]), mine])

	# ── C. no effect type may fall through to a raw identifier ────────────────
	# `copy_opposing_keywords` and `cast_random_spell` did, on 9 authored bodies,
	# printing "Copy opposing keywords" — an id with the underscores taken out.
	print("\n[trigtext] --- C. no raw identifiers reach the player ---")
	var enc = get_node_or_null("/root/EncounterDB")
	var seen := {}
	if enc != null:
		for eid in enc.ENCOUNTERS:
			for body in _bodies_in(enc.ENCOUNTERS[eid]):
				for ch in ["on_enter", "on_death"]:
					var sub = body.get(ch, null)
					if sub is Dictionary and (sub as Dictionary).has("type"):
						seen[String((sub as Dictionary)["type"])] = sub
	for t in seen.keys():
		var line := _render(scene, seen[t], true)
		# A fall-through is the id with underscores replaced and capitalised.
		var raw := String(t).replace("_", " ").capitalize()
		_check("%s has authored copy" % String(t), line != raw,
			"falls through to the raw id \"%s\"" % raw)
	print("      %d distinct authored enemy trigger types checked" % seen.size())

	print("\n[trigtext] %d checks, %d failed" % [_checks, _fails])
	print("[trigtext] %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(1 if _fails > 0 else 0)


## Build a real Card2D, hand it one trigger, and read back the composed line.
## The card is added to the tree so _ready runs and the autoloads resolve.
func _render(scene: PackedScene, eff: Dictionary, is_foe: bool) -> String:
	var card: Control = scene.instantiate()
	card.card_data = {
		"id": "probe_body", "name": "Probe Body", "type": "creature",
		"atk": 2, "hp": 2, "keywords": [], "desc": "",
		"on_death": eff.duplicate(true),
	}
	card.is_opponent = is_foe
	card.synth_desc_if_empty = true
	add_child(card)
	var text := String(card.call("_synthesized_rules_text"))
	card.queue_free()
	return text.strip_edges()


func _bodies_in(v: Variant) -> Array:
	var out: Array = []
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("atk") and d.has("hp"):
			out.append(d)
		for k in d.keys():
			out.append_array(_bodies_in(d[k]))
	elif v is Array:
		for e in (v as Array):
			out.append_array(_bodies_in(e))
	return out


func _check(label: String, ok: bool, why: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL  %s — %s" % [label, why])
