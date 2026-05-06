extends Node
## KeywordEffects.gd — central registry for keyword behaviour.
## Combat.gd calls dispatch_* which iterates a card's keywords and
## runs the matching hook. To add a keyword: add entry to KEYWORDS,
## implement the hook, update Card2D._format_keywords() for display.

const KEYWORDS: Dictionary = {
	"charge":            { "display": "Charge",        "hooks": [] },
	"taunt":             { "display": "Taunt",         "hooks": [] },
	"lifesteal":         { "display": "Lifesteal",     "hooks": [] },
	"frenzy":            { "display": "Frenzy",        "hooks": [] },
	"deathrattle_smite": { "display": "Death: smite",  "hooks": ["on_death"] },
	"deathrattle_burn":  { "display": "Death: burn",   "hooks": ["on_death"] },
	"onplay_draw":       { "display": "Play: draw",    "hooks": ["on_play"] },
	"onplay_smite":      { "display": "Play: smite",   "hooks": ["on_play"] },
}


static func display_text_for(keywords: Array) -> String:
	var out: Array[String] = []
	for k in keywords:
		if KEYWORDS.has(k):
			out.append(KEYWORDS[k].display)
	return "  ".join(out)


static func dispatch_on_play(card_id: String, lane_idx: int, is_enemy: bool, ctx) -> void:
	var data = CardDB.get_card_data(card_id)
	if data.is_empty() or not data.has("keywords"):
		return
	for kw in data.keywords:
		_run_on_play(kw, lane_idx, is_enemy, ctx)


static func dispatch_on_death(card, lane_idx: int, was_enemy: bool, ctx) -> void:
	if card == null or not card.card_data.has("keywords"):
		return
	for kw in card.card_data.keywords:
		_run_on_death(kw, lane_idx, was_enemy, ctx)


static func _run_on_play(kw: String, lane_idx: int, is_enemy: bool, ctx) -> void:
	match kw:
		"onplay_draw":
			if not is_enemy:
				ctx.draw_one()
		"onplay_smite":
			if is_enemy:
				ctx.damage_player_hero(2)
			else:
				ctx.damage_enemy_hero(2)


static func _run_on_death(kw: String, lane_idx: int, was_enemy: bool, ctx) -> void:
	match kw:
		"deathrattle_smite":
			var target = ctx.get_opposing_card(lane_idx, was_enemy)
			if target != null:
				target.take_damage(2)
		"deathrattle_burn":
			if was_enemy:
				ctx.damage_player_hero(1)
			else:
				ctx.damage_enemy_hero(1)
