extends Node
## _probe_hero_pitch.gd — the day-one truth gate on HeroDB's `desc` (the pitch)
## and `tagline`.
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_hero_pitch.tscn
##
## WHY THIS EXISTS. The pitch is printed IN FULL in THE COLUMN pane of the run
## opening — one of the first sentences a new player ever reads, and the only
## place the game says what a hero DOES. Three pitches were found false in the
## Phase 0 pass (docs/RUN_OPENING_REDESIGN_20260728.md §5), rewritten, and three
## had drifted false again by 2026-08-01. The failure is always the same shape:
## the pitch describes a mechanic the reader does not have — a `relic_alt` (gated
## on winning with the hero), a `deck_alt` (gated on a win at Ascension 4+), a
## pool card, or a relic that was later reshaped out from under the sentence.
##
## THE BAR: every clause must map to the DEFAULT `deck` or the DEFAULT `relic`.
##
## WHAT THIS PROBE CAN CATCH (mechanically, with no per-hero table):
##   1. A keyword named in a pitch or tagline that NO card in the default opener
##      carries. Catches "let Formation ..." the day Rank Spearman leaves the
##      deck, and any pitch that reaches for Piercing/Poison/Charge on spec.
##   2. A relic named by name that is not the hero's default relic — including,
##      by an explicit assertion with its own message, `relic_alt` and the
##      `deck_alt` name.
##   3. Any Capitalized word used MID-SENTENCE that is not part of the hero's
##      day-one vocabulary (the capitalized words on its default opener cards,
##      on its default relic, and the keyword names those cards carry). This is
##      the broad one: COPY_STYLE §4 and §8 both make a mid-sentence capital a
##      NAMED THING, so a named thing the player does not own is a lie by
##      construction. It is what catches the Acolyte's Shade — no opener card
##      summons one, and the two that do (Apocalypse, Raise the Fallen) are rare
##      pool spells. It also catches a card name from the wrong deck.
##   4. The shape rules the two fields are rendered under: the pitch is ONE
##      sentence, the tagline fits the 430px roster box (~42 chars), and the
##      loadout each pitch is written against actually exists and is well-formed
##      (10 cards, all real; a `starting`-tier relic restricted to this hero).
##
## WHAT IT CANNOT CATCH — and this is the honest limit, so do not read a PASS as
## "the pitch is true":
##   * A PARAPHRASE. The Kindler's "the first detonation pulls the next one
##     forward" was Chain Censer's rule with every word changed; no string test
##     reaches it. Only reading the relic beside the deck does.
##   * A lowercase mechanic reference. Checks 1 and 3 are case-SENSITIVE on
##     purpose (the style guide capitalizes every named mechanic), so a pitch
##     that says "formation" in lowercase reads as ordinary English and passes.
##   * Scope and emphasis. "let Formation grow a soldier" and "let Formation
##     grow every rank" are equally legal here; only one is honest about a deck
##     carrying a single Formation body.
##   * Whether the clause describes the mechanic CORRECTLY. Formation was named
##     by a deck that carries it, in a sentence that described a different
##     keyword's behaviour, and check 1 passed the whole time.
## When you edit a pitch, re-read the ten cards and the signature relic. This
## probe only guarantees you did not name something that isn't there.

const PROBE_NAME := "hero_pitch"
const PITCH_MAX_CHARS := 120
## The roster row box is 400px wide (the section is 430) and the taglines
## ellipsised twice at narrower widths — see MainMenu._make_muster_host_row.
const TAGLINE_MAX_CHARS := 42
const HERO_DECK_SIZE := 10

## Words a pitch may capitalize mid-sentence without owning a card for them:
## house vocabulary that is capitalized everywhere in the game by policy.
const HOUSE_WORDS := [
	"Command", "General", "Generals", "Curse", "HP", "ATK", "Swift",
]

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	var heroes: Dictionary = HeroDB.HEROES
	var order: Array = HeroDB.HERO_ORDER
	_check(order.size() == 5, "HERO_ORDER lists five heroes (%d)" % order.size())
	for hid_value in order:
		var hid := String(hid_value)
		_check(heroes.has(hid), "HERO_ORDER id '%s' exists in HEROES" % hid)
		if not heroes.has(hid):
			continue
		var hero: Dictionary = heroes[hid]
		var deck := _default_deck(hid, hero)
		var relic: Dictionary = RelicDB.get_relic(String(hero.get("relic", "")))
		_check_loadout(hid, hero, deck, relic)
		var vocab := _day_one_vocabulary(deck, relic, hero)
		var carried := _carried_keywords(deck)
		for field in ["desc", "tagline"]:
			var copy := String(hero.get(field, ""))
			_check(copy != "", "%s: %s is authored" % [hid, field])
			if copy == "":
				continue
			_check_shape(hid, field, copy)
			_check_named_keywords(hid, field, copy, carried)
			_check_named_relics(hid, field, copy, hero)
			_check_capitalized_words(hid, field, copy, vocab)

	print("[hero-pitch] %d checks" % _checks)
	if _fails.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in _fails:
		printerr("[hero-pitch] FAIL: " + failure)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(label)


## The DEFAULT opener only — never deck_alt, and never the banner card, which the
## player picks on step II and which no pitch may assume.
func _default_deck(hid: String, hero: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cid_value in Array(hero.get("deck", [])):
		var cd: Dictionary = CardDB.get_card_data(String(cid_value))
		_check(not cd.is_empty(), "%s: opener card '%s' exists" % [hid, cid_value])
		if not cd.is_empty():
			out.append(cd)
	return out


## The pitch is written against this loadout, so assert the loadout is the thing
## it says it is before asserting anything about the sentence.
func _check_loadout(hid: String, hero: Dictionary, deck: Array[Dictionary],
		relic: Dictionary) -> void:
	_check(Array(hero.get("deck", [])).size() == HERO_DECK_SIZE,
		"%s: default deck is %d cards" % [hid, HERO_DECK_SIZE])
	_check(deck.size() == Array(hero.get("deck", [])).size(),
		"%s: every default opener card resolves" % hid)
	var rid := String(hero.get("relic", ""))
	var alt := String(hero.get("relic_alt", ""))
	_check(rid != "", "%s: names a signature relic" % hid)
	_check(not relic.is_empty(), "%s: signature relic '%s' exists" % [hid, rid])
	if not relic.is_empty():
		_check(String(relic.get("tier", "")) == "starting",
			"%s: signature relic '%s' is tier starting" % [hid, rid])
		var restricted := String(relic.get("restricted_to", hid))
		_check(restricted == hid,
			"%s: signature relic '%s' is restricted to this hero (got '%s')"
				% [hid, rid, restricted])
	# The whole defect class starts here: if these two are ever the same id, the
	# "never describe relic_alt" rule below stops meaning anything.
	_check(alt != "" and alt != rid,
		"%s: relic_alt is a distinct second doctrine" % hid)
	_check(not RelicDB.get_relic(alt).is_empty(),
		"%s: relic_alt '%s' exists" % [hid, alt])


## COPY_STYLE §7 plus the two boxes these render in.
func _check_shape(hid: String, field: String, copy: String) -> void:
	_check(copy.ends_with("."), "%s: %s ends with a period" % [hid, field])
	if field == "desc":
		_check(copy.length() <= PITCH_MAX_CHARS,
			"%s: pitch is %d characters (budget %d)"
				% [hid, copy.length(), PITCH_MAX_CHARS])
		# One sentence. A second one does not fit THE COLUMN pane's two lines and
		# turns the pitch into the tagline's job.
		_check(not copy.substr(0, copy.length() - 1).contains(". "),
			"%s: pitch is one sentence" % hid)
	else:
		_check(copy.length() <= TAGLINE_MAX_CHARS,
			"%s: tagline is %d characters (roster box holds %d)"
				% [hid, copy.length(), TAGLINE_MAX_CHARS])


## CHECK 1 — a keyword named in the copy must be carried by a default opener card.
## Multi-word displays ("Last Stand", "Adj. Buff") match as whole phrases: split
## into words, "Stand together." would read as a Last Stand claim.
func _check_named_keywords(hid: String, field: String, copy: String,
		carried: Dictionary) -> void:
	for kw_value in KeywordEffects.KEYWORDS.keys():
		var kw := String(kw_value)
		var phrase := _keyword_phrase(kw)
		if phrase == "" or not _has_phrase(copy, phrase):
			continue
		_check(carried.has(kw),
			"%s: %s names the keyword '%s', which NO card in the default opener carries"
				% [hid, field, phrase])


## CHECK 2 — no relic but your own. relic_alt and deck_alt get their own message
## because they are the specific trap: both are unlock-gated, so naming one sells
## the reader a doctrine a first run cannot hold.
func _check_named_relics(hid: String, field: String, copy: String,
		hero: Dictionary) -> void:
	var own := String(RelicDB.get_relic(String(hero.get("relic", ""))).get("name", ""))
	var alt_name := String(RelicDB.get_relic(String(hero.get("relic_alt", ""))).get("name", ""))
	if alt_name != "":
		_check(not _has_phrase(copy, alt_name),
			"%s: %s names '%s' — that is relic_alt, gated on a win with this hero"
				% [hid, field, alt_name])
	var deck_alt: Dictionary = hero.get("deck_alt", {})
	var alt_deck_name := String(deck_alt.get("name", ""))
	if alt_deck_name != "":
		_check(not _has_phrase(copy, alt_deck_name),
			"%s: %s names '%s' — that is deck_alt, gated on a win at Ascension 4+"
				% [hid, field, alt_deck_name])
	for rid_value in RelicDB.RELICS.keys():
		var name := String(RelicDB.RELICS[rid_value].get("name", ""))
		if name == "" or name == own or not _has_phrase(copy, name):
			continue
		_check(false,
			"%s: %s names the relic '%s', which is not this hero's signature relic"
				% [hid, field, name])


## CHECK 3 — a mid-sentence capital is a NAMED THING (COPY_STYLE §4, §8). Every
## one must be day-one vocabulary. Sentence-initial words are exempt: they are
## capitalized by grammar, not by naming ("Strike where they are not").
func _check_capitalized_words(hid: String, field: String, copy: String,
		vocab: Dictionary) -> void:
	var words := copy.split(" ", false)
	var starts_sentence := true
	for raw_value in words:
		var raw := String(raw_value)
		var word := _bare_word(raw)
		var was_initial := starts_sentence
		starts_sentence = raw.ends_with(".") or raw.ends_with("!") \
			or raw.ends_with("?") or raw.ends_with(":")
		if word.length() < 2 or was_initial:
			continue
		if word.substr(0, 1) != word.substr(0, 1).to_upper() \
				or word.substr(0, 1).to_lower() == word.substr(0, 1).to_upper():
			continue
		_check(vocab.has(word),
			"%s: %s capitalizes '%s' mid-sentence, but nothing in the default opener"
				% [hid, field, word]
				+ " or the signature relic names it")


## Every capitalized word a day-one player can actually read on their own cards
## and their own relic, plus the keyword names those cards carry. Built from the
## data rather than a curated list, so a new retinue card widens it for free.
func _day_one_vocabulary(deck: Array[Dictionary], relic: Dictionary,
		hero: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for w in HOUSE_WORDS:
		out[String(w)] = true
	for w in _capitals_in(String(hero.get("name", ""))):
		out[w] = true
	var faction: Dictionary = HeroDB.faction_info(String(hero.get("faction", "")))
	for key in ["name", "element", "engine"]:
		for w in _capitals_in(String(faction.get(key, ""))):
			out[w] = true
	for cd in deck:
		for key in ["name", "desc"]:
			for w in _capitals_in(String(cd.get(key, ""))):
				out[w] = true
		for kw_value in Array(cd.get("keywords", [])):
			for w in _capitals_in(_keyword_phrase(String(kw_value))):
				out[w] = true
	for key in ["name", "desc"]:
		for w in _capitals_in(String(relic.get(key, ""))):
			out[w] = true
	return out


func _carried_keywords(deck: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for cd in deck:
		for kw_value in Array(cd.get("keywords", [])):
			out[String(kw_value)] = true
	return out


## The display name a player actually reads, minus the "N" placeholder that
## "Doom N" / "Wither N" carry (the card prints a digit there).
func _keyword_phrase(kw: String) -> String:
	var entry: Dictionary = KeywordEffects.KEYWORDS.get(kw, {})
	var display := String(entry.get("display", ""))
	if display.ends_with(" N"):
		display = display.substr(0, display.length() - 2)
	return display.strip_edges()


func _capitals_in(text: String) -> Array[String]:
	var out: Array[String] = []
	for raw_value in text.split(" ", false):
		var word := _bare_word(String(raw_value))
		if word.length() < 2:
			continue
		var head := word.substr(0, 1)
		if head == head.to_upper() and head.to_lower() != head.to_upper():
			out.append(word)
	return out


## Strips surrounding punctuation but keeps the internal hyphen and apostrophe,
## so "On-Death:" -> "On-Death" and "creature's" -> "creature's".
func _bare_word(raw: String) -> String:
	var out := raw
	while out.length() > 0 and not _is_word_char(out.substr(0, 1)):
		out = out.substr(1)
	while out.length() > 0 and not _is_word_char(out.substr(out.length() - 1, 1)):
		out = out.substr(0, out.length() - 1)
	return out


func _is_word_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
		or (c >= "0" and c <= "9")


## Whole-phrase, case-SENSITIVE match with word boundaries on both ends, so
## "Command" does not fire on "commanded" and "Slay" does not fire inside a name.
func _has_phrase(copy: String, phrase: String) -> bool:
	if phrase == "":
		return false
	var from := 0
	while true:
		var at := copy.find(phrase, from)
		if at < 0:
			return false
		var before := "" if at == 0 else copy.substr(at - 1, 1)
		var after_at := at + phrase.length()
		var after := "" if after_at >= copy.length() else copy.substr(after_at, 1)
		if not _is_word_char(before) and not _is_word_char(after):
			return true
		from = at + 1
	return false
