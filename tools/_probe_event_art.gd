extends Node
## Verifies that every live event resolves to one real image, and that the set
## of events SHARING a painting is exactly the debt we have already signed off.
## Run: Godot.exe --headless --path "D:\\Godot" res://tools/_probe_event_art.tscn
##
## ══════════════════════ WHY AN ALLOW-LIST EXISTS ══════════════════════
## The house rule (CLAUDE.md, event authoring) is: "art from cut events stays
## on disk for exactly this; don't point two live events at the same stand-in."
##
## As written that rule is UNSATISFIABLE BY ARITHMETIC today. There are 46 live
## events and 33 assignable paintings in `assets/events/` (35 files, minus
## `the_siege_kitchen-finished-example.png`, a dev-only reference wired to
## `tools/_shot_event_hybrid_preview.gd`, minus `butcher.png`, which has no
## fitting home in the current pool). Producing the missing plates is a
## Midjourney job — see `docs/MIDJOURNEY_EVENT_PROMPTS.md` — not a coding job,
## so ~13 events must keep sharing until that art lands.
##
## A gate that can never go green is a gate everyone learns to ignore, and this
## probe was ignored for exactly that reason. So the known shares are written
## down in SHARED_ART_DEBT below as an explicit, temporary LEDGER. The probe
## goes green on today's state and still fails on:
##   * an event with no art, or an art key that resolves to nothing;
##   * a NEW shared pair that is not in the ledger;
##   * a shared GROUP of three or more (the ledger only sanctions pairs);
##   * a STALE ledger entry — a pair listed here that no longer shares.
##
## That last case is the important half. Without it the ledger silently rots
## and the debt never shrinks, which is just the old red gate wearing a
## disguise. Entries here are DELETED, never added.
##
## ── Clearing an entry (the only sanctioned direction) ──
##   1. Generate the plate from `docs/MIDJOURNEY_EVENT_PROMPTS.md`.
##   2. Save it as `assets/events/<event_id>.png`, run a headless `--import`.
##   3. Drop that event's `"art"` override in `scripts/data/EventDB.gd` so it
##      resolves by its own id.
##   4. Delete the entry below. The probe will fail as STALE until you do.
##
## ── If you are about to ADD an entry ──
## Don't. Adding a line here means shipping a new event with no art of its own
## and charging the debt to someone else. Point the new event at its own
## painting, or get the owner's sign-off before growing this list.

const PROBE_NAME := "event_art"

## Temporary art debt. Each entry is EXACTLY two live event ids that currently
## resolve to the same file, in alphabetical order. The comment above each
## entry names why the share is tolerable and what painting would clear it.
## Verified 2026-07-28 against 46 events / 33 assignable paintings.
const SHARED_ART_DEBT: Array = [
	# old_army_game (the dead paymaster's shell game) rides the_bone_pit.png.
	# Both are the Fourth's unburied ground, so the plate is not a lie.
	# Clears with: three helmets over a drumhead.
	["old_army_game", "the_bone_pit"],

	# the_beetle_derby (renamed "The Wheel of the Fourth") rides
	# coin_on_edge.png — a coin standing upright in the road. Roadside game of
	# chance either way. Clears with: a three-section betting wheel.
	["coin_on_edge", "the_beetle_derby"],

	# the_fourths_strongbox (crack the legion pay chest) rides
	# fattened_sin_eater.png. Shared read: a fat man grown rich on other
	# people's debts. Clears with: a locked, banded legion pay chest.
	["fattened_sin_eater", "the_fourths_strongbox"],

	# the_provost_marshal ("The Dead Marshal", a dice game) rides
	# gravesong_choir.png. Shared read: a dead formation facing you across the
	# dark. Clears with: a dead marshal over a dice cup.
	["gravesong_choir", "the_provost_marshal"],

	# BORROWER-BORROWER: neither event owns hollow_lantern.png, so either one
	# may be given bespoke art to clear this. A lantern over black water reads
	# for the ferry; a lit cresset reads for the beacon line.
	["the_drowned_ferry", "the_signal_line"],

	# BORROWER-BORROWER on old_forge.png. The forge cart was chosen for
	# the_ladder_merchant's arms-dealer rig (see its inline note) and still
	# fits. the_powder_move only inherited it from the retired powder-keg
	# game — it is now "The Dead Man's Deal", a card game, so it holds the
	# WEAKER claim and should get the bespoke plate first.
	["the_ladder_merchant", "the_powder_move"],

	# widows_tray (renamed "The Widow's Cut") rides pawnbrokers_window.png.
	# Shared read: a woman trading across a counter after dark. Clears with:
	# a widow's card table.
	["pawnbrokers_window", "widows_tray"],

	# BORROWER-BORROWER on plague_bell.png. Both are the dead still standing
	# their post; the_short_straw was re-pointed here in a past pass precisely
	# because it is the_last_garrison's fiction. Either may be cleared first.
	["the_last_garrison", "the_short_straw"],

	# the_proving_ground (a sapper's hidden-charge sand table) rides
	# rotting_carnival.png. Shared read: a fairground game with lethal stakes.
	# Clears with: a sand table strung with marked paths.
	["rotting_carnival", "the_proving_ground"],

	# the_gibbet_green (renamed "Gallows Green", a ring toss) rides
	# sin_eater.png. Shared read: a keeper making a living off the hanged.
	# Clears with: a gibbet, a peg and a hanging chain reading the wind.
	["sin_eater", "the_gibbet_green"],

	# the_old_game (morra — a HAND game) rides strangers_hand.png.
	# docs/MIDJOURNEY_EVENT_PROMPTS.md already flags this plate as showing the
	# CUT "hand at a red door" concept, so it currently fits the borrower
	# better than its owner (The Wet Cards). Clears with: bespoke art for
	# strangers_hand, not for the_old_game.
	["strangers_hand", "the_old_game"],

	# WEAKEST PAIRING IN THE LEDGER — prioritise. the_quartermasters_scale
	# (find the underweight coin on a balance) rides the_chrysalis.png, a row
	# of hanging cocoons. Nothing connects them but the hanging silhouette.
	# Clears with: a balance scale and a row of worn pay-tokens.
	["the_chrysalis", "the_quartermasters_scale"],

	# the_couriers_satchel (a drowned courier hunting pay tokens) rides
	# the_crossing.png. Both are literally the same ford, so this is the most
	# defensible share in the list. Clears with: a satchel spilling tokens.
	["the_couriers_satchel", "the_crossing"],
]


func _ready() -> void:
	var failures: Array[String] = []
	# Explicit `: Variant` rather than `:=` — this project treats
	# INFERRED_DECLARATION as an error, and both of these call sites return
	# Variant, which made the probe itself unloadable (found 2026-07-28).
	var events_value: Variant = _script_constant(
		"res://scripts/data/EventDB.gd", "EVENTS", failures)
	var event_resource := ResourceLoader.load(
		"res://scripts/scenes/Event.gd", "GDScript")
	if event_resource == null or not (event_resource is GDScript):
		failures.append("Cannot load Event.gd")
		_finish(0, 0, failures)
		return
	var event_script := event_resource as GDScript
	var compile_err := event_script.reload(true)
	if compile_err != OK:
		failures.append("Cannot compile Event.gd: %s" % error_string(compile_err))
		_finish(0, 0, failures)
		return
	if not (events_value is Dictionary):
		failures.append("EventDB.EVENTS is not a Dictionary")
		_finish(0, 0, failures)
		return

	var event: Variant = event_script.new()
	if event == null or not (event is Control):
		failures.append("Cannot instantiate Event.gd outside the scene tree")
		_finish(0, 0, failures)
		return
	var events: Dictionary = events_value
	var ids: Array = events.keys()
	ids.sort()
	var resolved: Dictionary = {}
	for id_value in ids:
		var id := String(id_value)
		event.set("_event_id", id)
		event.set("_event_data", events[id_value])
		var path := String(event.call("_resolve_event_image_path"))
		if path == "":
			failures.append("NO ART: %s (art field: %s)" % [
				id, events[id_value].get("art", "-")])
			continue
		if not ResourceLoader.exists(path):
			failures.append("MISSING RESOURCE: %s -> %s" % [id, path])
			continue
		var owners: Array = resolved.get(path, [])
		owners.append(id)
		resolved[path] = owners
	event.free()

	# The ledger is keyed by "a|b" with the ids alphabetised, so an entry
	# written in either order still matches the observed pair.
	var ledger: Dictionary = {}
	for entry_value in SHARED_ART_DEBT:
		if not (entry_value is Array) or (entry_value as Array).size() != 2:
			failures.append(
				"MALFORMED LEDGER ENTRY (want exactly 2 event ids): %s"
				% str(entry_value))
			continue
		var entry: Array = entry_value
		var key := _pair_key(String(entry[0]), String(entry[1]))
		if ledger.has(key):
			failures.append("DUPLICATE LEDGER ENTRY: %s" % key.replace("|", " + "))
			continue
		ledger[key] = false

	var shared_groups := 0
	var paths: Array = resolved.keys()
	paths.sort()
	for path_value in paths:
		var owners: Array = resolved[path_value]
		if owners.size() < 2:
			continue
		shared_groups += 1
		owners.sort()
		var file_name := String(path_value).get_file()
		if owners.size() > 2:
			# The ledger sanctions PAIRS only. Three events on one plate is a
			# different (worse) problem and always needs a human decision.
			failures.append("SHARED ART (%d events on one plate): %s <- %s" % [
				owners.size(), file_name, ", ".join(owners)])
			continue
		var key := _pair_key(String(owners[0]), String(owners[1]))
		if ledger.has(key):
			ledger[key] = true
			continue
		# Printed output stays pure ASCII: run_safe_probes.ps1 reads these logs
		# back with Get-Content under the system ANSI codepage, which mojibakes
		# anything non-ASCII (an em-dash here rendered as garbage in CI).
		failures.append(
			"SHARED ART (not in the debt ledger): %s <- %s"
			% [file_name, ", ".join(owners)]
			+ " -- give one of them its own assets/events/<event_id>.png"
			+ " (see docs/MIDJOURNEY_EVENT_PROMPTS.md) rather than adding a"
			+ " SHARED_ART_DEBT entry.")

	# Stale ledger entries are a failure ON PURPOSE: it is the only pressure
	# that makes this list shrink as art lands.
	var ledger_keys: Array = ledger.keys()
	ledger_keys.sort()
	for key_value in ledger_keys:
		if bool(ledger[key_value]):
			continue
		failures.append(
			"STALE LEDGER ENTRY: %s no longer share a plate"
			% String(key_value).replace("|", " + ")
			+ " (art landed, an event was renamed, or an event was cut)"
			+ " -- delete this line from SHARED_ART_DEBT in this file.")

	_finish(events.size(), shared_groups, failures)


func _pair_key(a: String, b: String) -> String:
	if a <= b:
		return a + "|" + b
	return b + "|" + a


func _script_constant(path: String, constant_name: String,
		failures: Array[String]) -> Variant:
	var resource := ResourceLoader.load(path, "GDScript")
	if resource == null or not (resource is GDScript):
		failures.append("Cannot load data script: %s" % path)
		return null
	var script := resource as GDScript
	var err := script.reload(true)
	if err != OK:
		failures.append("Cannot compile %s: %s" % [path, error_string(err)])
		return null
	var constants := script.get_script_constant_map()
	if not constants.has(constant_name):
		failures.append("%s has no %s constant" % [path, constant_name])
		return null
	return constants[constant_name]


func _finish(event_count: int, shared_groups: int,
		failures: Array[String]) -> void:
	print("[event-art] checked %d live events" % event_count)
	if event_count == 0:
		failures.append("No live events were checked")
	# Debt stays visible on every run, pass or fail. One shared plate = one
	# bespoke painting still owed (the other event keeps the plate it has).
	if event_count > 0:
		print("[event-art] ART DEBT: %d shared plate(s), %d bespoke painting(s)"
			% [shared_groups, shared_groups]
			+ " still owed (%d of %d live events await their own art)."
				% [shared_groups, event_count]
			+ " See docs/MIDJOURNEY_EVENT_PROMPTS.md.")
		if shared_groups == 0:
			print("[event-art] Debt clear — every live event owns its plate."
				+ " SHARED_ART_DEBT should now be empty.")
	if failures.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in failures:
		printerr("[event-art] " + failure)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, failures.size()])
	get_tree().quit(1)
