extends Node
## SavedDecks — named skirmish warbands persisted to user://decks.json so a drafted
## or hand-built deck can be reused without drafting again. A saved deck is just a
## name + an ordered list of CardDB ids (exactly SkirmishState.DECK_TARGET of them).
## Used by the Constructed / Draft / Sealed deck-acquisition scenes (save + load)
## and by the bot when "use a saved deck" is wired. Local-only JSON, mirrors the
## MetaState / UserSettings save pattern.

const PATH := "user://decks.json"
const MAX_DECKS := 30

## Array of { "name": String, "cards": Array[String], "saved_at": String }.
var decks: Array = []


func _ready() -> void:
	_load()


func _load() -> void:
	decks = []
	var txt := SaveIO.read_text(PATH)
	if txt == "":
		return
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		parsed = JSON.parse_string(SaveIO.read_backup_text(PATH))
	if not (parsed is Dictionary):
		return
	for d in parsed.get("decks", []):
		if not (d is Dictionary):
			continue
		var cards: Array = []
		for c in d.get("cards", []):
			cards.append(String(c))
		if cards.is_empty():
			continue
		decks.append({
			"name": String(d.get("name", "Warband")),
			"cards": cards,
			"saved_at": String(d.get("saved_at", "")),
		})


func _save_file() -> void:
	if not SaveIO.write_text(PATH, JSON.stringify({"decks": decks}, "\t")):
		push_warning("SavedDecks: could not write %s" % PATH)


## All saved decks (newest first as stored). Each entry: {name, cards, saved_at}.
func list_decks() -> Array:
	return decks


func count() -> int:
	return decks.size()


## Save (or replace by name) a deck. `cards` is copied. Returns the stored name.
## A blank name auto-numbers ("Warband N"). Replacing a same-name deck keeps the
## list tidy instead of piling up near-duplicates.
func save_deck(deck_name: String, cards: Array) -> String:
	var nm := deck_name.strip_edges()
	if nm == "":
		nm = "Warband %d" % (decks.size() + 1)
	var copy: Array = []
	for c in cards:
		copy.append(String(c))
	var entry := {
		"name": nm,
		"cards": copy,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	# Replace an existing deck with the same name (case-insensitive) in place.
	for i in decks.size():
		if String(decks[i].get("name", "")).to_lower() == nm.to_lower():
			decks[i] = entry
			_save_file()
			return nm
	decks.push_front(entry)
	while decks.size() > MAX_DECKS:
		decks.pop_back()
	_save_file()
	return nm


func delete_deck(index: int) -> void:
	if index < 0 or index >= decks.size():
		return
	decks.remove_at(index)
	_save_file()


## The card-id list of a saved deck (a copy), or [] for a bad index.
func get_cards(index: int) -> Array:
	if index < 0 or index >= decks.size():
		return []
	var out: Array = []
	for c in decks[index].get("cards", []):
		out.append(String(c))
	return out


func deck_name(index: int) -> String:
	if index < 0 or index >= decks.size():
		return ""
	return String(decks[index].get("name", ""))
