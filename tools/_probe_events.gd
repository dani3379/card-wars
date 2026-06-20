extends SceneTree
## Auto-exercise EVENT effects — stability hardening (2026-06-18).
##
## Events (~41) are the highest remaining crash surface: every choice carries a
## bespoke effect dict, and many _apply_effect arms read `effect.value` /
## `effect.id` / `effect.outcomes` DIRECTLY — a missing key is a hard runtime
## error the parse-check can't see. This probe walks the whole EVENTS tree
## (choices, follow_ups, blue options, roll_table outcomes, risk_loop steps +
## bust, dice payoff effects) and fires every reachable NON-MODAL effect under
## two RunState fixtures (rich+healthy / poor+hurt) so floor/scaled/cap branches
## both run. Modal pickers (MODAL_EFFECTS) need the live tree + clicks, so they
## are listed-but-skipped (covered by the render probes instead).
##
## It also calls the gate dispatcher on every event-level + blue gate (an unknown
## gate type is meant to fail-closed, not crash).
##
## Detection: a marker prints before each event + each effect type. Capture
## stdout+stderr and scan for SCRIPT ERROR / "Invalid" between markers.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_events.gd

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]

var RS: Node
var CDB: Node
var ev: Object               # non-tree Event instance (for _apply_effect / gates)
var EVENTS: Dictionary = {}
var MODAL: Array = []

var _events := 0
var _effects := 0
var _gates := 0
var _errors := 0             # best-effort: counted from obviously-empty returns is unreliable, so we lean on the stderr scan


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	print("[events] start")
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or CDB == null:
		print("[events] FATAL: autoloads missing")
		quit(1)
		return

	var EvScript = load("res://scripts/scenes/Event.gd")
	EVENTS = EvScript.EVENTS
	MODAL = EvScript.MODAL_EFFECTS
	# A non-tree instance: _ready never fires (no tree entry), so it won't pick a
	# random event or build UI — we just borrow its _apply_effect / gate methods.
	ev = load("res://scenes/event.tscn").instantiate()

	print("[events] %d events, %d modal effect types skipped" % [EVENTS.size(), MODAL.size()])

	var ids: Array = EVENTS.keys()
	ids.sort()
	for id in ids:
		_exercise_event(String(id))

	print("[events] ============ SUMMARY ============")
	print("[events] events walked : %d" % _events)
	print("[events] effects fired : %d  (non-modal _apply_effect calls)" % _effects)
	print("[events] gates checked : %d" % _gates)
	print("[events] (scan the log for SCRIPT ERROR / Invalid to find a crashing effect)")
	print("[events] DONE")
	quit(0)


func _exercise_event(id: String) -> void:
	_events += 1
	var data: Dictionary = EVENTS[id]
	print("[events] >>> %s  (%s)" % [id, String(data.get("name", "?"))])

	# Two fixtures so floor / scaled / cap branches all execute.
	for fixture in ["rich", "poor"]:
		_fixture(fixture, _events)
		# Gate check (event-level) — must not crash even when malformed.
		var gate: Dictionary = data.get("gate", {})
		if not gate.is_empty():
			_check_gate(gate)
		# Walk every effect dict anywhere in the event (any depth).
		var effects: Array = []
		_collect_effects(data, effects)
		for e in effects:
			if e is Dictionary and e.has("type"):
				var t := String(e["type"])
				if t in MODAL:
					continue   # picker — needs live tree + clicks
				print("[events]     fire[%s]: %s" % [fixture, t])
				ev._apply_effect(e)
				_effects += 1
		# Collect + check any nested blue gates too.
		var gates: Array = []
		_collect_gates(data, gates)
		for g in gates:
			_check_gate(g)


func _check_gate(gate: Dictionary) -> void:
	_gates += 1
	# Returns bool; we don't assert the value, only that it doesn't crash.
	ev._event_gate_passes_dict(gate)


## Recursively gather every {"type": ...} effect dict reachable in `node`,
## EXCEPT the "blue" gate dicts (those are gates, not effects) and roll_table /
## risk_loop CONFIG dicts themselves (their type IS modal, so they self-skip;
## their nested step/outcome effects are reached by the walk).
func _collect_effects(node, out: Array) -> void:
	if node is Array:
		for item in node:
			_collect_effects(item, out)
	elif node is Dictionary:
		# A leaf effect dict.
		if node.has("type") and not node.has("choices") and not node.has("outcomes") \
				and not node.has("steps"):
			out.append(node)
		# Recurse into every value EXCEPT a "blue" gate (handled separately).
		for k in node.keys():
			if String(k) == "blue":
				continue
			_collect_effects(node[k], out)


func _collect_gates(node, out: Array) -> void:
	if node is Array:
		for item in node:
			_collect_gates(item, out)
	elif node is Dictionary:
		if node.has("blue") and node["blue"] is Dictionary:
			out.append(node["blue"])
		for k in node.keys():
			_collect_gates(node[k], out)


func _fixture(kind: String, n: int) -> void:
	var hero: String = HEROES[n % HEROES.size()]
	RS.start_new_run(hero, 0, 4242)
	if kind == "rich":
		RS.gold = 500
		RS.hero_hp = RS.hero_max_hp
		# A few potions so sell_potion / potions_full paths run.
		RS.add_potion("healing")
		RS.add_potion("healing")
		# A curse so has_curse / remove-filtered fiction has something to chew.
		RS.add_card(CDB.random_curse_id())
	else:
		RS.gold = 0
		RS.hero_hp = maxi(1, int(RS.hero_max_hp * 0.25))
