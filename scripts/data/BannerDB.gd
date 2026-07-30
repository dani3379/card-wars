extends Node
## BannerDB.gd — the six declarations on THE MUSTER.
##
## A banner is direction, not a second hero power: it declares the first
## seasonal tribe, adds exactly one authored levy card, and leaves the war to
## deal the second tribe from the run seed. Player-facing choice copy stays in
## this DB so the copy lint sees it.

const DEFAULT_BANNER: String = "soldier"
const BANNER_ORDER: Array[String] = [
	"soldier", "beast", "dead", "warlock", "bastion", "stray",
]

const BANNERS: Dictionary = {
	"soldier": {
		"id": "soldier", "name": "The Colours", "tribe": "Soldier",
		"line_text": "Soldiers answer first.", "card_id": "line_marker",
		"color": Color(0.66, 0.53, 0.30),
	},
	"beast": {
		"id": "beast", "name": "The Hunt", "tribe": "Beast",
		"line_text": "Beasts answer first.", "card_id": "loose_horse",
		"color": Color(0.52, 0.40, 0.24),
	},
	"dead": {
		"id": "dead", "name": "The Roll", "tribe": "Dead",
		"line_text": "The Dead answer first.", "card_id": "ash_marker",
		"color": Color(0.47, 0.50, 0.38),
	},
	"warlock": {
		"id": "warlock", "name": "The Coven", "tribe": "Warlock",
		"line_text": "Warlocks answer first.", "card_id": "hedge_caster",
		"color": Color(0.48, 0.34, 0.54),
	},
	"bastion": {
		"id": "bastion", "name": "The Works", "tribe": "Bastion",
		"line_text": "Bastions answer first.", "card_id": "marker_stone",
		"color": Color(0.48, 0.49, 0.48),
	},
	"stray": {
		"id": "stray", "name": "The Contract", "tribe": "Stray",
		"line_text": "Strays answer first.", "card_id": "free_lance",
		"color": Color(0.48, 0.55, 0.49),
	},
}


static func has_banner(id: String) -> bool:
	return BANNERS.has(id)


static func normalize(id: String) -> String:
	return id if has_banner(id) else DEFAULT_BANNER


static func get_banner(id: String) -> Dictionary:
	return BANNERS.get(normalize(id), BANNERS[DEFAULT_BANNER])


static func card_id(id: String) -> String:
	return String(get_banner(id).get("card_id", ""))


static func display_name(id: String) -> String:
	return String(get_banner(id).get("name", id))


static func choice_line(id: String) -> String:
	return String(get_banner(id).get("line_text", ""))
