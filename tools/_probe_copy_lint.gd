extends Node
## Game-wide house-style gate for player-facing text.
## Run: Godot.exe --headless --path "D:\Godot" res://tools/_probe_copy_lint.tscn
##
## This intentionally covers every structured copy source, including nested
## event outcomes and upgrade descriptions, plus the terminology rules over
## literals authored directly in scene scripts (see _scan_ui_literals).
##
## ── A BROKEN PROBE IS INVISIBLE, AND IT LOOKS LIKE A HANG (2026-09-15) ──
##
## `_probe_parsecheck` compiles everything under `scripts/` — it does NOT read
## `tools/`. So a parse error in THIS file is caught by nothing: the scene loads
## with no script attached, `_ready` never runs, the probe never calls quit, and
## the process sits there printing absolutely nothing until the runner's timeout
## kills it. That reads exactly like an infinite loop in whatever you last
## touched, and it is not.
##
## The tell is ZERO OUTPUT. A probe that hangs mid-scan still prints whatever it
## printed before the stall; a probe that prints nothing at all never started.
## When that happens, compile the probe itself before debugging its logic:
##
##     Godot.exe --headless --path "D:\Godot" --check-only --script res://tools/<probe>.gd
##
## (What it caught here: a helper added to the bottom of this file duplicated a
## function name already defined further up.)

const PROBE_NAME := "copy_lint"
const COVERAGE_FLOOR := 5150
const EVENT_DESC_WORD_LIMIT := 40
const EVENT_RESULT_WORD_LIMIT := 60
const CARD_DESC_CHAR_LIMIT := 90
const RELIC_DESC_CHAR_LIMIT := 120
const ENCOUNTER_PASSIVE_WORD_LIMIT := 32
const KEYWORD_DESC_WORD_LIMIT := 24

const MOUTH := [
	"you feel", "you realise", "you realize", "you think", "you remember",
	"you decide", "you wonder", "your heart", "you shudder", "you hope",
]
const CLICHE := [
	"too quiet", "black as pitch", "diaphanous", "a chill runs",
	"blood runs cold", "deafening silence", "nameless dread", "ancient evil",
	"little did", "sends shivers",
]
# Terms that previously made ordinary rules or choices needlessly opaque.
# Internal ids are not scanned; this applies only to fields players can read.
const OPAQUE_TERMS := [
	"chit", "chits", "quoits", "sutler", "reliquary", "provost",
	"chirurgeon", "vivandiere", "vivandière", "remount", "watchword",
	"mangonel", "pavise", "serjeant", "tally-stick", "writ",
	"cornicen", "optio", "muster", "mustering", "levy", "levies", "tithe",
	"seated",
	# "loose" REMOVED 2026-07-29. It was presumably added for the archery
	# imperative ("loose!") or the Strongbox game's SEATED/LOOSE ward feedback —
	# but that wording lives in Event.gd, which this lint does not scan (it reads
	# DB dictionaries only). So the term caught nothing it was aimed at and
	# false-positived on the card "Loose Horse", where "loose" is the ordinary
	# English adjective for a runaway animal, not jargon.
	#
	# NOTE: "seated" above has the same blind spot — it is only meaningful in the
	# Strongbox feedback this lint cannot see. It is currently harmless (nothing in
	# a DB dict uses the word), so it is left in place rather than churned, but it
	# is not doing the job it looks like it is doing.
]
const CAPS_OK := [
	# Only entries of 3+ characters can ever be consulted — _check_shouting
	# gates on first.length() >= 3 first. "IV"/"HP"/"OK" lived here as dead
	# code; Roman numerals are handled by _is_roman_numeral instead.
	"ATK", "ALL", "SPELL", "EXHAUST", "RETAIN",
]
const COPY_KEYS := [
	"name", "desc", "label", "text", "title", "subtitle", "prompt",
	"tooltip", "caption", "flavor", "brief", "tagline", "lore", "blurb",
	"display", "short", "won", "lost", "head", "note", "passive_desc",
	"engine", "engine_line", "lord_title", "season_line",
	# Added 2026-07-31. All of these hold prose that RENDERS, and all were
	# invisible because the key was not on this list. The sharpest case is
	# `rule`: Combat assigns `siege.rule` into the very same standing-rule
	# plaque that `passive_desc` fills, so one slot was wording-gated and
	# word-budgeted while the other was not gated at all.
	"preamble", "scope", "tell", "rule", "order", "break_noun",
	"breach_log", "after_breach", "sub", "action", "speaker",
	"msg", "transition_msg",
]

var _fails: Array[String] = []
var _scanned := 0
var _read_constants: Dictionary = {}


func _ready() -> void:
	_scan_events()
	_scan_cards()
	_scan_relics()
	_scan_potions()
	_scan_encounters()
	_scan_heroes_and_factions()
	_scan_keywords()
	_scan_mutators()
	_scan_set_pieces()
	_scan_writs()
	_scan_modes()
	_scan_ascension_rules()
	_scan_tutorial()
	_scan_lessons()
	# The Field Manual's group headings, and the three Coaching settings the
	# player picks between. Both are copy by construction — id keys, player text
	# for values — which is exactly what _scan_copy_map exists for.
	_scan_copy_map("res://scripts/data/TutorialDB.gd", "GROUP_TITLES", "lessongroup")
	_scan_copy_map("res://scripts/data/TutorialDB.gd", "COACH_MODE_LABELS", "coachmode")
	_scan_ui_literals()
	_assert_constants_covered()
	print("[copy-lint] scanned %d player-facing strings" % _scanned)
	# Coverage RATCHET. The old floor of 1500 sat ~1200 strings below the real
	# count, so not one of the scanned constants could vanish individually and
	# trip it — the flat-dict bug that hid MUSTER_COPY cost 16 strings, roughly
	# two orders of magnitude under the guard. Raise this when coverage grows;
	# a drop means a source stopped being read, which is the whole point.
	if _scanned < COVERAGE_FLOOR:
		_fails.append("Coverage regression: scanned only %d strings (expected at least %d)"
			% [_scanned, COVERAGE_FLOOR])
	if _fails.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in _fails:
		printerr("[copy-lint] FAIL: " + failure)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1)


## ── THE SCENE-SCRIPT BLIND SPOT (2026-09-15) ──
##
## Everything above reads DB DICTIONARIES, and that is deliberate: a structured
## dict lets this lint read only name/desc fields, so it never trips over a code
## identifier — every Command identifier in the engine still says `mana`.
##
## The cost was that copy authored INSIDE a scene script was size-gated by
## _probe_text_floor and never wording-gated by anything. This file already
## carries two scars from it: "loose" was removed from OPAQUE_TERMS because the
## Strongbox wording it targeted lives in Event.gd, and the note above "seated"
## says outright that it "is not doing the job it looks like it is doing".
## Measured at the time of writing: 2,482 prose-like literals across
## scripts/scenes and scripts/ui, none of them checked by anything.
##
## SCOPE IS NARROW ON PURPOSE. Only the three TERMINOLOGY rules run here —
## "mana", "elite", and the "(s)" plural — because those are decidable on a bare
## string with no false positives (measured: zero hits across all 2,482 today,
## so this ships GREEN and exists to stop drift, not to fix a backlog). The
## wordier rules — MOUTH, CLICHE, word budgets — stay DB-only, where the probe
## knows a field is prose rather than guessing. A lint that guesses is a lint
## people learn to ignore.
##
## A literal counts as prose if it holds a SPACE and is not a res:// path or a
## bare snake_case identifier. Comment lines are skipped — a comment is not
## shipped copy, and this file's own header would otherwise fail the gate by
## quoting the very words it bans.
const UI_LITERAL_DIRS := [
	"res://scripts/scenes", "res://scripts/ui",
]
## Keyed "basename.gd::needle". An entry here is visible debt, not absolution.
const UI_LITERAL_WAIVERS := {}


func _scan_ui_literals() -> void:
	for dir_path in UI_LITERAL_DIRS:
		var dir := DirAccess.open(String(dir_path))
		if dir == null:
			_fails.append("Cannot open UI source dir: %s" % dir_path)
			continue
		for file_name in dir.get_files():
			if not String(file_name).ends_with(".gd"):
				continue
			_scan_ui_literal_file("%s/%s" % [dir_path, file_name])


func _scan_ui_literal_file(path: String) -> void:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		_fails.append("Cannot read UI source: %s" % path)
		return
	var owner := path.get_file()
	var line_no := 0
	while not handle.eof_reached():
		var line := handle.get_line()
		line_no += 1
		# CHEAPEST TEST FIRST, and it is load-bearing rather than tidy. The scan
		# covers ~50,000 lines (Combat.gd alone is 20,400) and the first cut
		# split every one of them on the quote character, which pushed this probe
		# past a five-minute budget it used to clear comfortably. The large
		# majority of lines carry no quote at all, so one `in` test retires them
		# before any allocation happens.
		if not ("\"" in line):
			continue
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		for literal in _extract_literals(line):
			if not _is_prose_literal(literal):
				continue
			_scanned += 1
			_check_ui_terminology(owner, line_no, literal)
	handle.close()


## Every double-quoted run on the line. Deliberately simple: a GDScript escape
## inside player copy is vanishingly rare, and the failure mode of getting one
## wrong is a slightly short literal, not a wrong verdict.
func _extract_literals(line: String) -> Array[String]:
	var out: Array[String] = []
	var parts := line.split("\"")
	# Quoted runs are the ODD indices of a split on the quote character.
	var i := 1
	while i < parts.size():
		out.append(String(parts[i]))
		i += 2
	return out


func _is_prose_literal(text: String) -> bool:
	# Space first: it rejects most literals (ids, keys, paths, node names) in one
	# test, before anything walks the string.
	if not (" " in text):
		return false
	if text.begins_with("res://") or text.begins_with("user://"):
		return false
	# A format-only fragment ("%d / %d") carries no words to police.
	var wordy := false
	for c in text:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z"):
			wordy = true
			break
	return wordy


func _check_ui_terminology(owner: String, line_no: int, text: String) -> void:
	var low := text.to_lower()
	var where := "%s:%d" % [owner, line_no]
	for needle in ["mana", "elite"]:
		# The house _has_word treats a trailing 's' as part of the word, so the
		# plural is asked for by name rather than by loosening the shared test.
		if not (_has_word(low, needle) or _has_word(low, needle + "s")):
			continue
		if UI_LITERAL_WAIVERS.has("%s::%s" % [owner, needle]):
			continue
		var house := "Command" if needle == "mana" else "General"
		_fails.append("%s says \"%s\" in player text (house word: %s): \"%s\""
			% [where, needle, house, text])
	if "(s)" in low and not UI_LITERAL_WAIVERS.has("%s::(s)" % owner):
		_fails.append("%s uses the \"(s)\" plural: \"%s\"" % [where, text])


func _script_constant(path: String, constant_name: String) -> Variant:
	var resource := ResourceLoader.load(path, "GDScript")
	if resource == null or not (resource is GDScript):
		_fails.append("Cannot load data script: %s" % path)
		return null
	var script := resource as GDScript
	var err := script.reload(true)
	if err != OK:
		_fails.append("Cannot compile %s: %s" % [path, error_string(err)])
		return null
	var constants := script.get_script_constant_map()
	if not _read_constants.has(path):
		_read_constants[path] = []
	if not (_read_constants[path] as Array).has(constant_name):
		(_read_constants[path] as Array).append(constant_name)
	if not constants.has(constant_name):
		_fails.append("%s has no %s constant" % [path, constant_name])
		return null
	return constants[constant_name]


func _scan_events() -> void:
	var value: Variant = _script_constant("res://scripts/data/EventDB.gd", "EVENTS")
	if not (value is Dictionary):
		_fails.append("EventDB.EVENTS is not a Dictionary")
		return
	var events: Dictionary = value
	for id_value in events.keys():
		var id := String(id_value)
		var event_value: Variant = events[id_value]
		if not (event_value is Dictionary):
			_fails.append("EventDB.EVENTS[%s] is not a Dictionary" % id)
			continue
		var event: Dictionary = event_value
		_scan_text_tree(event, "event:" + id, "")
		var desc := String(event.get("desc", ""))
		var words := _word_count(desc)
		if words > EVENT_DESC_WORD_LIMIT:
			_fails.append("event:%s desc is %d words (budget %d)" % [
				id, words, EVENT_DESC_WORD_LIMIT])
		_scan_event_result_budgets(event, "event:" + id, "")


func _scan_event_result_budgets(value: Variant, owner: String, path: String) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key_value in dict.keys():
			var key := String(key_value)
			var child: Variant = dict[key_value]
			var child_path := key if path == "" else path + "." + key
			if child is String and _is_copy_key(key):
				var words := _word_count(String(child))
				if words > EVENT_RESULT_WORD_LIMIT:
					_fails.append("%s %s is %d words (result budget %d)" % [
						owner, child_path, words, EVENT_RESULT_WORD_LIMIT])
			else:
				_scan_event_result_budgets(child, owner, child_path)
	elif value is Array:
		var array: Array = value
		for index in array.size():
			_scan_event_result_budgets(array[index], owner,
				"%s[%d]" % [path, index])


func _scan_cards() -> void:
	var cards_value: Variant = _script_constant(
		"res://scripts/data/CardDB.gd", "CARD_POOL")
	var upgrades_value: Variant = _script_constant(
		"res://scripts/data/CardDB.gd", "UPGRADES")
	if not (cards_value is Dictionary):
		_fails.append("CardDB.CARD_POOL is not a Dictionary")
		return
	if not (upgrades_value is Dictionary):
		_fails.append("CardDB.UPGRADES is not a Dictionary")
		return
	var cards: Dictionary = cards_value
	var upgrades: Dictionary = upgrades_value
	for key_value in cards.keys():
		var card_value: Variant = cards[key_value]
		if not (card_value is Dictionary):
			_fails.append("CardDB.CARD_POOL[%s] is not a Dictionary" % key_value)
			continue
		var card: Dictionary = card_value
		var id := String(card.get("id", key_value))
		var desc := String(card.get("desc", ""))
		_check("card:" + id, "name", String(card.get("name", "")))
		_check("card:" + id, "desc", desc)
		_check_card_desc("card:" + id, desc, card.get("keywords", []))
		if upgrades.has(key_value):
			var upgrade_value: Variant = upgrades[key_value]
			if upgrade_value is Dictionary:
				var upgrade_desc := String((upgrade_value as Dictionary).get("desc", ""))
				_check("card+:" + id, "desc", upgrade_desc)
				# Validate the "+" text against the UPGRADED keywords: passing the
				# base list means an upgrade that ADDS on_enter/on_death
				# false-positives the "says On-Enter but has no on_enter" rule.
				var up_kw: Variant = (upgrade_value as Dictionary).get(
					"keywords", card.get("keywords", []))
				_check_card_desc("card+:" + id, upgrade_desc, up_kw)
	for upgrade_key in upgrades.keys():
		if not cards.has(upgrade_key):
			_fails.append("CardDB.UPGRADES[%s] has no base card" % upgrade_key)


func _check_card_desc(owner: String, desc: String, keywords_value: Variant) -> void:
	if desc.length() > CARD_DESC_CHAR_LIMIT:
		_fails.append("%s desc is %d characters (budget %d)" % [
			owner, desc.length(), CARD_DESC_CHAR_LIMIT])
	var keywords: Array = keywords_value if keywords_value is Array else []
	if desc.contains("On-Enter:") and not keywords.has("on_enter"):
		_fails.append("%s says On-Enter but has no on_enter keyword" % owner)
	if desc.contains("On-Death:") and not keywords.has("on_death"):
		_fails.append("%s says On-Death but has no on_death keyword" % owner)
	var low := desc.to_lower()
	for old_form in ["on play:", "on-play:", "on enter:", "on death:"]:
		if low.contains(old_form):
			_fails.append("%s uses inconsistent trigger wording: %s" % [
				owner, old_form])


func _scan_relics() -> void:
	var value: Variant = _script_constant("res://scripts/data/RelicDB.gd", "RELICS")
	if not (value is Dictionary):
		_fails.append("RelicDB.RELICS is not a Dictionary")
		return
	var relics: Dictionary = value
	for id_value in relics.keys():
		var relic_value: Variant = relics[id_value]
		if not (relic_value is Dictionary):
			continue
		var relic: Dictionary = relic_value
		var owner := "relic:" + String(id_value)
		var desc := String(relic.get("desc", ""))
		_check(owner, "name", String(relic.get("name", "")))
		_check(owner, "desc", desc)
		if desc.length() > RELIC_DESC_CHAR_LIMIT:
			_fails.append("%s desc is %d characters (budget %d)" % [
				owner, desc.length(), RELIC_DESC_CHAR_LIMIT])


func _scan_potions() -> void:
	var value: Variant = _script_constant("res://scripts/data/PotionDB.gd", "POTIONS")
	if not (value is Dictionary):
		_fails.append("PotionDB.POTIONS is not a Dictionary")
		return
	var potions: Dictionary = value
	for id_value in potions.keys():
		var potion_value: Variant = potions[id_value]
		if potion_value is Dictionary:
			_scan_text_tree(potion_value, "potion:" + String(id_value), "")


func _scan_encounters() -> void:
	var value: Variant = _script_constant(
		"res://scripts/data/EncounterDB.gd", "ENCOUNTERS")
	if not (value is Dictionary):
		_fails.append("EncounterDB.ENCOUNTERS is not a Dictionary")
		return
	var encounters: Dictionary = value
	for id_value in encounters.keys():
		var encounter_value: Variant = encounters[id_value]
		if not (encounter_value is Dictionary):
			continue
		var owner := "encounter:" + String(id_value)
		var encounter: Dictionary = encounter_value
		_scan_text_tree(encounter, owner, "")
		var passive := String(encounter.get("passive_desc", ""))
		var words := _word_count(passive)
		if words > ENCOUNTER_PASSIVE_WORD_LIMIT:
			_fails.append("%s passive is %d words (budget %d)" % [
				owner, words, ENCOUNTER_PASSIVE_WORD_LIMIT])
	_scan_passive_rungs()


## PASSIVE_RUNG_DESC is the canonical text for a passive that has an ACT LADDER
## (`EncounterDB.get_passive_for` steps a borrowed lineup down a rung rather than
## dropping its rule). That text reaches the player through the edict banner and
## the route tooltip exactly as an authored `passive_desc` does, so it gets the
## same register rules and the same word budget — a rung sentence that is exempt
## from the budget is how the banner grows a paragraph nobody reads.
func _scan_passive_rungs() -> void:
	var value: Variant = _script_constant(
		"res://scripts/data/EncounterDB.gd", "PASSIVE_RUNG_DESC")
	if not (value is Dictionary):
		_fails.append("EncounterDB.PASSIVE_RUNG_DESC is not a Dictionary")
		return
	var rungs: Dictionary = value
	for id_value in rungs.keys():
		var owner := "passive-rung:" + String(id_value)
		var text := String(rungs[id_value])
		_check(owner, "desc", text)
		var words := _word_count(text)
		if words > ENCOUNTER_PASSIVE_WORD_LIMIT:
			_fails.append("%s is %d words (budget %d)" % [
				owner, words, ENCOUNTER_PASSIVE_WORD_LIMIT])


func _scan_heroes_and_factions() -> void:
	_scan_constant_tree("res://scripts/data/HeroDB.gd", "HEROES", "hero")
	_scan_constant_tree("res://scripts/data/HeroDB.gd", "FACTIONS", "faction")


func _scan_keywords() -> void:
	var value: Variant = _script_constant(
		"res://scripts/data/KeywordEffects.gd", "KEYWORDS")
	if not (value is Dictionary):
		_fails.append("KeywordEffects.KEYWORDS is not a Dictionary")
		return
	var keywords: Dictionary = value
	for id_value in keywords.keys():
		var keyword_value: Variant = keywords[id_value]
		if not (keyword_value is Dictionary):
			continue
		var owner := "keyword:" + String(id_value)
		var keyword: Dictionary = keyword_value
		_scan_text_tree(keyword, owner, "")
		var desc := String(keyword.get("desc", ""))
		var words := _word_count(desc)
		if words > KEYWORD_DESC_WORD_LIMIT:
			_fails.append("%s desc is %d words (budget %d)" % [
				owner, words, KEYWORD_DESC_WORD_LIMIT])


func _scan_mutators() -> void:
	_scan_constant_tree("res://scripts/data/MutatorDB.gd", "MUTATORS", "mutator")


func _scan_set_pieces() -> void:
	_scan_constant_tree("res://scripts/data/SetPieceDB.gd", "SET_PIECES", "setpiece")
	# Constants living INSIDE files the probe already loads, never wired up. The
	# same failure class as an unscanned file, and larger: BOSS_PHASES carries
	# `passive_desc`, the exact field this probe budgets at 32 words when it
	# arrives via ENCOUNTERS.
	_scan_constant_tree("res://scripts/data/CardDB.gd", "ENEMY_POOL", "enemy")
	_scan_constant_tree("res://scripts/data/EncounterDB.gd", "BOSS_PHASES", "phase")
	_scan_constant_tree("res://scripts/data/EncounterDB.gd",
		"ENCOUNTER_SCRIPTS", "script")
	_scan_constant_tree("res://scripts/data/EncounterDB.gd",
		"AMALGAM_HISTORY_PHASES", "amalgam")
	_scan_copy_map("res://scripts/GameTheme.gd", "RELIC_TIER_TAGS", "relic-tier")
	# Prose that renders: the veterancy epithet stamped on a card's name, and the
	# tribe forms the season announce line is assembled from.
	_scan_copy_list("res://scripts/state/RunState.gd", "VETERAN_EPITHETS", "epithet")
	_scan_copy_map("res://scripts/state/RunState.gd", "SEASON_TRIBE_NAMES", "season-tribe")


func _scan_writs() -> void:
	# THE WAR CHEST's four commissions. These MUST be scanned from the DB rather
	# than authored inline in MainMenu: this lint only reads DB dictionaries, so
	# option copy written in a scene script is size-gated by _probe_text_floor
	# but escapes the wording rules entirely.
	_scan_constant_tree("res://scripts/data/WritDB.gd", "WRITS", "writ")
	_scan_constant_tree("res://scripts/data/WritDB.gd", "PACTS", "pact")
	# The opening screen's own chrome, moved out of MainMenu 2026-07-30 for
	# exactly this reason — it said "sign one Writ" and the lint could not see it.
	_scan_constant_tree("res://scripts/data/WritDB.gd", "MUSTER_COPY", "opening")
	# The house-word glossary (2026-07-31). Definitions of the vocabulary the
	# opening prices its decisions in are the MOST wording-sensitive copy on the
	# screen — if a definition is wrong or opaque, every term quoting that word
	# inherits the error.
	_scan_constant_tree("res://scripts/data/WritDB.gd", "GLOSSARY", "gloss")
	# The slot furniture printed BESIDE the terms on the same screen. Keyed by
	# slot id, so it needs the copy-map entry point, not the tree walker.
	_scan_copy_map("res://scripts/data/WritDB.gd", "SLOT_LABELS", "slot-label")
	_scan_copy_map("res://scripts/data/WritDB.gd", "SLOT_HINTS", "slot-hint")


func _scan_modes() -> void:
	var value: Variant = _script_constant(
		"res://scripts/net/SkirmishState.gd", "MODE_DEFS")
	if not (value is Array):
		_fails.append("SkirmishState.MODE_DEFS is not an Array")
		return
	var modes: Array = value
	for index in modes.size():
		_scan_text_tree(modes[index], "mode:%d" % index, "")


func _scan_ascension_rules() -> void:
	var value: Variant = _script_constant(
		"res://scripts/state/RunState.gd", "ASCENSION_RULES")
	if not (value is Array):
		_fails.append("RunState.ASCENSION_RULES is not an Array")
		return
	var rules: Array = value
	for index in rules.size():
		_check("ascension:%d" % index, "rule", String(rules[index]))


## THE HOW-TO-PLAY PRIMER. Note the name: this scans `HOW_TO_PLAY_PRIMER`, which
## is the manual's campaign page — NOT the coaching registry. `_scan_lessons`
## below is the one that covers the tutorial proper.
func _scan_tutorial() -> void:
	var value: Variant = _script_constant(
		"res://scripts/GameTheme.gd", "HOW_TO_PLAY_PRIMER")
	if not (value is Array):
		_fails.append("GameTheme.HOW_TO_PLAY_PRIMER is not an Array")
		return
	var entries: Array = value
	for index in entries.size():
		var entry_value: Variant = entries[index]
		if not (entry_value is Array):
			_fails.append("HOW_TO_PLAY_PRIMER[%d] is not an Array" % index)
			continue
		var entry: Array = entry_value
		if entry.size() < 2:
			_fails.append("HOW_TO_PLAY_PRIMER[%d] has no body" % index)
			continue
		_check("tutorial:%d" % index, "title", String(entry[0]))
		_check("tutorial:%d" % index, "body", String(entry[1]))


## THE COACHING REGISTRY — `TutorialDB.LESSONS`, 22 lessons of `title` + `body`.
##
## THIS WAS A REAL HOLE, and it had already cost something. Despite the name,
## `_scan_tutorial` above covers the MANUAL's primer page; nothing scanned the
## lessons themselves. `tools/_probe_tutorial.gd` checks them for "mana", "elite"
## and `(s)`, but not for this file's OPAQUE_TERMS, its cliché list, or the
## shouting rule — so the primer was linted for words the tutorial was not, and
## a lesson shipped saying "the front **rank**" when COPY_STYLE §12 settles
## combat rows as *rows*, never ranks. The registry is the most-read copy in the
## game for a new player; it gets the same lint as everything else.
##
## `{n}` is substituted the way the Field Manual substitutes it — a raw token
## would trip the lint on a brace the player never sees.
func _scan_lessons() -> void:
	var value: Variant = _script_constant(
		"res://scripts/data/TutorialDB.gd", "LESSONS")
	if not (value is Dictionary):
		_fails.append("TutorialDB.LESSONS is not a Dictionary")
		return
	var lessons: Dictionary = value
	if lessons.is_empty():
		_fails.append("TutorialDB.LESSONS is empty — the scan would be vacuous")
		return
	for id in lessons:
		var entry_value: Variant = lessons[id]
		if not (entry_value is Dictionary):
			_fails.append("LESSONS[%s] is not a Dictionary" % id)
			continue
		var entry: Dictionary = entry_value
		var owner := "lesson:%s" % id
		_check(owner, "title", String(entry.get("title", "")))
		_check(owner, "body", String(entry.get("body", "")).replace("{n}", "2"))


## For dictionaries that are copy BY CONSTRUCTION — every value is player text,
## and the KEY is a domain id (`roll`, `arsenal`) rather than a copy-key name.
## _scan_constant_tree cannot serve these: it key-gates through _is_copy_key, so
## wiring WritDB.SLOT_LABELS there would have scanned zero strings and reported
## success. Using this instead also retires the fragile `_text`-suffix naming
## convention for any new copy map.
func _scan_copy_map(path: String, constant_name: String, prefix: String) -> void:
	var value: Variant = _script_constant(path, constant_name)
	if not (value is Dictionary):
		_fails.append("%s.%s is not a Dictionary" % [path, constant_name])
		return
	var dict: Dictionary = value
	if dict.is_empty():
		_fails.append("%s.%s is an empty copy map" % [path, constant_name])
		return
	# `str()`, NOT `String()` — and this was a live hole, not a style nit.
	# Godot 4's String has constructors for String / StringName / NodePath and
	# NOTHING ELSE, so `String(0)` raises "Nonexistent 'String' constructor" and
	# ABORTS the function where it stands. `COACH_MODE_LABELS` is keyed by the
	# COACH_* ints, so this threw on its very first key and that map has never
	# been linted at all — while the probe went on to print PROBE PASS, because
	# the abort kills the scan and not the verdict. A gate that reports success
	# on a scan it never performed is the exact failure the method doc calls a
	# FAKE GATE. Whether the runner NOTICED depended on stdout/stderr buffering
	# order, which is why it surfaced intermittently.
	for key_value in dict.keys():
		_check(prefix, str(key_value), str(dict[key_value]))


## Array[String] counterpart to _scan_copy_map — every element is player text.
func _scan_copy_list(path: String, constant_name: String, prefix: String) -> void:
	var value: Variant = _script_constant(path, constant_name)
	if not (value is Array):
		_fails.append("%s.%s is not an Array" % [path, constant_name])
		return
	var list: Array = value
	if list.is_empty():
		_fails.append("%s.%s is an empty copy list" % [path, constant_name])
		return
	for i in list.size():
		# `str()` for the same reason as its sibling above.
		_check(prefix, "[%d]" % i, str(list[i]))


func _scan_constant_tree(path: String, constant_name: String, prefix: String) -> void:
	var value: Variant = _script_constant(path, constant_name)
	if not (value is Dictionary):
		_fails.append("%s.%s is not a Dictionary" % [path, constant_name])
		return
	var dict: Dictionary = value
	for id_value in dict.keys():
		# Every entry must yield at least one player-facing string. This asserts a
		# STRUCTURAL invariant rather than a count, so it never churns on a copy
		# edit — and it is the assertion that would have caught MUSTER_COPY's 16
		# entries silently producing 0, which the global 1500 floor cannot see
		# (the slack above that floor is ~1200 strings).
		var produced_before := _scanned
		var entry: Variant = dict[id_value]
		# FLAT dictionaries (key → copy) such as WritDB.MUSTER_COPY and
		# WritDB.GLOSSARY. _scan_text_tree only descends Dictionaries and Arrays,
		# so a top-level String hit neither branch and was dropped in silence —
		# every one of the opening screen's chrome strings was passing this gate
		# by never reaching it, which is the same class of hole as authoring the
		# copy inline. Caught 2026-07-31 when adding three glossary entries did
		# not move the scanned-string count.
		if entry is String:
			if _is_copy_key(String(id_value)):
				_check(prefix, String(id_value), String(entry))
		else:
			_scan_text_tree(entry, prefix + ":" + String(id_value), "")
		if _scanned == produced_before:
			_fails.append("%s.%s[%s] produced no player-facing text" % [
				path, constant_name, String(id_value)])


func _scan_text_tree(value: Variant, owner: String, path: String) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key_value in dict.keys():
			var key := String(key_value)
			var child: Variant = dict[key_value]
			var child_path := key if path == "" else path + "." + key
			if child is String and _is_copy_key(key):
				_check(owner, child_path, String(child))
			elif child is Array and _is_copy_key(key):
				# The Array branch below only RECURSES, and a bare String element
				# then matches neither branch and is dropped in silence, so copy
				# held as ["line", "line"] was unreachable under any key. Scoped
				# to copy keys because the other 814 dropped strings are ids.
				var lines: Array = child
				for li in lines.size():
					var el_path := "%s[%d]" % [child_path, li]
					if lines[li] is String:
						_check(owner, el_path, String(lines[li]))
					else:
						_scan_text_tree(lines[li], owner, el_path)
			else:
				_scan_text_tree(child, owner, child_path)
	elif value is Array:
		var array: Array = value
		for index in array.size():
			_scan_text_tree(array[index], owner, "%s[%d]" % [path, index])


func _is_copy_key(key: String) -> bool:
	# SEGMENT test, not a suffix test. `leave_text_early` (EventDB) is prose that
	# renders on a gamble result screen, and it escaped every wording rule for the
	# life of this probe purely because the key ends `_early` rather than `_text`
	# — its sibling `leave_text`, one line above in the same dict, was gated.
	# Verified across every scanned constant: this matches exactly one new key.
	return key in COPY_KEYS or "text" in key.split("_") 		or key.ends_with("_label") or key.ends_with("_sub") 		or key.ends_with("_body") or key.ends_with("_title")


func _check(owner: String, field: String, copy: String) -> void:
	if copy.strip_edges() == "":
		return
	_scanned += 1
	var low := copy.to_lower()
	if _has_word(low, "mana"):
		_fails.append("%s %s says mana; player-facing word is Command" % [
			owner, field])
	if _has_word(low, "elite"):
		_fails.append("%s %s says elite; player-facing word is General" % [
			owner, field])
	if low.contains("(s)"):
		_fails.append("%s %s leaks an (s) pluralisation artifact" % [
			owner, field])
	for phrase in MOUTH:
		if low.contains(phrase):
			_fails.append("%s %s puts words in the player's mouth: %s" % [
				owner, field, phrase])
	for phrase in CLICHE:
		if low.contains(phrase):
			_fails.append("%s %s uses the cliche: %s" % [
				owner, field, phrase])
	for term in OPAQUE_TERMS:
		if _has_word(low, term):
			_fails.append("%s %s uses unexplained term: %s" % [
				owner, field, term])
	_check_shouting(owner, field, copy)


func _has_word(low: String, term: String) -> bool:
	var regex := RegEx.new()
	var err := regex.compile("(^|[^a-z])" + term + "([^a-z]|$)")
	return err == OK and regex.search(low) != null


func _word_count(copy: String) -> int:
	return copy.replace("
", " ").split(" ", false).size()


func _check_shouting(owner: String, field: String, copy: String) -> void:
	var words := copy.replace("
", " ").split(" ", false)
	var run := 0
	var first := ""
	for i in words.size() + 1:
		var at_end := i >= words.size()
		var word := "" if at_end else _bare(words[i])
		# A token carrying fewer than two LETTERS is run-NEUTRAL: it neither joins
		# a run of signage nor breaks one. Separators and numbers are not words,
		# but `_bare` reduces them to "" or a stray letter ("%d" -> "d"), which
		# used to reset the run and strand the capped word beside them as a "lone
		# shout". That is why "III · THE TERMS" flagged, and it is a whole family:
		# "+%d GOLD", "-%d COMMAND", "TAKES %d WOUNDS", "WIN - BLOCK - CENTER".
		# Patching those one at a time is how CAPS_OK ended up carrying "IV".
		# Cost: a genuine one-letter word ("a") also stops breaking a run, which
		# no real copy in this project depends on.
		if not at_end and word.length() < 2:
			continue
		var capped := word.length() >= 2 and word == word.to_upper() 			and word.to_lower() != word.to_upper()
		if capped:
			if run == 0:
				first = word
			run += 1
			continue
		if run == 1 and first.length() >= 3 and not (first in CAPS_OK) \
				and not _is_roman_numeral(first):
			_fails.append("%s %s shouts a lone word: %s" % [
				owner, field, first])
		run = 0
		first = ""


## A Roman numeral is a NUMBER, not a shouted word. The game sets its slots and
## steps in them ("III · THE TERMS", "I · THE ROLL"), and the separator breaks
## the capped run the shout rule uses to recognise signage, so "III" read as a
## lone shout while "I" and "II" slipped under the 3-character threshold —
## inconsistent treatment of one series.
##
## Matched strictly (1-39) rather than by character set: "CIVIL" is composed
## entirely of numeral letters and must still be able to trip the shout rule.
func _is_roman_numeral(word: String) -> bool:
	var re := RegEx.new()
	if re.compile("^(X{0,3})(IX|IV|V?I{0,3})$") != OK:
		return false
	var m := re.search(word)
	return m != null and m.get_string(0) == word and word != ""


func _bare(word: String) -> String:
	var out := ""
	for character in word:
		if (character >= "A" and character <= "Z") 				or (character >= "a" and character <= "z"):
			out += character
	return out

## Every container constant in a file this probe already opens must be either
## SCANNED or explicitly WAIVED. Nothing else closes the failure that has now
## happened three times in this repo: a new copy dictionary is authored, nobody
## wires it into a _scan_* function, and it stays invisible forever while the
## probe reports PASS (MUSTER_COPY, SLOT_LABELS, SLOT_HINTS).
##
## The cost is honest: one waiver line per new NON-copy constant. That is a
## deliberate trade — the friction is a single line carrying a message that
## names the exact fix, versus the status quo where the omission is silent.
const CONTAINER_WAIVERS: Dictionary = {	"res://scripts/data/CardDB.gd": [
		"STARTER_DECK", "CURSE_IDS", "_CURSE_WEIGHTS", "RARITY_WEIGHT",
		"ACT_REWARD_WEIGHTS", "SKIRMISH_DENYLIST", "CARD_RARITY",
	],
	"res://scripts/data/RelicDB.gd": [
		"RELIC_RARITY", "TIER_COLORS", "FOUNDATION_RELICS", "BOSS_RELICS",
		"RARITY_WEIGHT",
		# relic id -> stand-in ICON id. Both halves are asset/entry identifiers
		# that never reach the player; the relic's own player-facing name and desc
		# are scanned where they are authored, in RELICS.
		"ICON_FALLBACKS",
	],
	"res://scripts/data/EncounterDB.gd": [
		"ACT_FACE_HP_NORM", "REACTIVE_PASSIVES", "TERRAIN_KW",
		# Passive IDs in act order — code identifiers, never shown. The player-
		# facing sentence for each rung lives in PASSIVE_RUNG_DESC, which IS
		# scanned (see _scan_passive_rungs) and budgeted like any passive_desc.
		"PASSIVE_ACT_LADDERS",
		# Encounter ids, not prose — the lineups they name are scanned where they
		# are authored, in ENCOUNTERS.
		"LANDING_POOL",
	],
	"res://scripts/data/HeroDB.gd": ["HERO_ORDER"],
	"res://scripts/data/TutorialDB.gd": [
		# Group ids in reading order — the group's player-facing heading lives in
		# GROUP_TITLES, which IS scanned (see _scan_lessons' siblings below).
		"GROUP_ORDER",
	],
	"res://scripts/data/WritDB.gd": ["GLOSSARY_ORDER"],
	"res://scripts/GameTheme.gd": [
		"CARD_TRIBES", "TRIBE_COLORS", "TRIBE_COLORS_BRIGHT", "SCREEN_MOODS",
	],
	"res://scripts/data/KeywordEffects.gd": ["COMBAT_KEYWORDS"],
	"res://scripts/state/RunState.gd": [
		"FIGHT_ROWS", "ELITE_ROWS", "SEASON_TRIBE_POOL",
		# The run-history CSV's known-result VOCABULARY, not prose. It exists to
		# tell a real record from a garbled line: a row is accepted if it carries
		# a plausible ISO stamp OR a result word from this list, so noise produces
		# neither and is dropped rather than rendered as an invented run. The
		# player never meets these strings — Collection's HISTORY_OUTCOMES maps
		# each to its own label, and that map is where the read words are authored.
		# (Combat writes "withdraw" at a set-piece withdrawal, which is NOT here —
		# but that is a PlayLog telemetry event, a different log, so this
		# vocabulary is complete for the file it guards.)
		"RUN_RESULTS",
	],
	"res://scripts/net/SkirmishState.gd": [
		"CombatMode", "MatchMode", "SKIRMISH_RARITY_TIERS",
		"SKIRMISH_DRAFT_WEIGHTS", "SKIRMISH_RARITY_OVERRIDES",
		"SKIRMISH_DENYLIST", "DRAFTABLE_RARITIES", "NET_RELIC_POOL",
		"NET_POTION_POOL", "BOT_RELIC_POOL", "NET_SPELL_TYPES",
		"NET_SPELL_CUSTOMS",
	],
}


func _assert_constants_covered() -> void:
	for path_value in _read_constants.keys():
		var path := String(path_value)
		var resource := ResourceLoader.load(path, "GDScript")
		if resource == null or not (resource is GDScript):
			continue
		var scanned: Array = _read_constants[path_value]
		var waived: Array = CONTAINER_WAIVERS.get(path, [])
		for cname_value in (resource as GDScript).get_script_constant_map().keys():
			var cname := String(cname_value)
			if scanned.has(cname) or waived.has(cname):
				continue
			var v: Variant = (resource as GDScript).get_script_constant_map()[cname_value]
			if not (v is Dictionary or v is Array):
				continue
			_fails.append(("%s.%s is a container constant this probe never reads"
				+ " — scan it in a _scan_* function, or add it to CONTAINER_WAIVERS")
				% [path, cname])
