extends Node
## Game-wide house-style gate for player-facing text.
## Run: Godot.exe --headless --path "D:\Godot" res://tools/_probe_copy_lint.tscn
##
## This intentionally covers every structured copy source, including nested
## event outcomes and upgrade descriptions. UI-only literal strings remain
## protected by the terminology searches and text/layout probes.

const PROBE_NAME := "copy_lint"
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
	"IV", "HP", "ATK", "ALL", "SPELL", "EXHAUST", "RETAIN", "OK",
]
const COPY_KEYS := [
	"name", "desc", "label", "text", "title", "subtitle", "prompt",
	"tooltip", "caption", "flavor", "brief", "tagline", "lore", "blurb",
	"display", "short", "won", "lost", "head", "note", "passive_desc",
	"engine", "engine_line", "lord_title", "season_line",
]

var _fails: Array[String] = []
var _scanned := 0


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
	print("[copy-lint] scanned %d player-facing strings" % _scanned)
	if _scanned < 1500:
		_fails.append("Coverage regression: scanned only %d strings (expected at least 1500)" % _scanned)
	if _fails.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in _fails:
		printerr("[copy-lint] FAIL: " + failure)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1)


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
			if child is String and (key == "text" or key.ends_with("_text")):
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
				_check_card_desc("card+:" + id, upgrade_desc,
					card.get("keywords", []))
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
	# The six banner declarations are choice copy in every sense that matters and
	# were unscanned until the same pass.
	_scan_constant_tree("res://scripts/data/BannerDB.gd", "BANNERS", "banner")


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


func _scan_constant_tree(path: String, constant_name: String, prefix: String) -> void:
	var value: Variant = _script_constant(path, constant_name)
	if not (value is Dictionary):
		_fails.append("%s.%s is not a Dictionary" % [path, constant_name])
		return
	var dict: Dictionary = value
	for id_value in dict.keys():
		_scan_text_tree(dict[id_value], prefix + ":" + String(id_value), "")


func _scan_text_tree(value: Variant, owner: String, path: String) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key_value in dict.keys():
			var key := String(key_value)
			var child: Variant = dict[key_value]
			var child_path := key if path == "" else path + "." + key
			if child is String and _is_copy_key(key):
				_check(owner, child_path, String(child))
			else:
				_scan_text_tree(child, owner, child_path)
	elif value is Array:
		var array: Array = value
		for index in array.size():
			_scan_text_tree(array[index], owner, "%s[%d]" % [path, index])


func _is_copy_key(key: String) -> bool:
	return key in COPY_KEYS or key.ends_with("_text")


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
	if copy.contains("(s)"):
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
		var word := "" if i >= words.size() else _bare(words[i])
		var capped := word.length() >= 2 and word == word.to_upper() 			and word.to_lower() != word.to_upper()
		if capped:
			if run == 0:
				first = word
			run += 1
			continue
		if run == 1 and first.length() >= 3 and not (first in CAPS_OK):
			_fails.append("%s %s shouts a lone word: %s" % [
				owner, field, first])
		run = 0
		first = ""


func _bare(word: String) -> String:
	var out := ""
	for character in word:
		if (character >= "A" and character <= "Z") 				or (character >= "a" and character <= "z"):
			out += character
	return out