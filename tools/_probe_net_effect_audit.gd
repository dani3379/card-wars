extends SceneTree
## Audit: which DRAFTABLE skirmish cards carry an effect that resolves WRONG (or not
## at all) when the CLIENT owns the creature — i.e. the host runs it with is_enemy=true
## and the effect is gated `if not is_enemy` / uses a host-only picker or pile.
##
## Pure data scan (no scene). Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_effect_audit.gd

# Effect-type → why it's client-broken. Keep in sync with KeywordEffects._run_on_enter /
# _run_on_death and Combat._resolve_on_play_ability.
#
# FIXED 2026-06-29 (now net-handled for the client, so NOT listed here — re-adding any
# of these would be a regression): copy_last_dead, cast_random_spell, choose_keyword,
# copy_friendly (all on_enter) and return_to_hand_once (on_death). See Combat's
# "CLIENT-OWNED CREATURE EFFECTS" block + the EV_CHOICE/IN_CHOICE picker.
# FIXED 2026-07-06: bonus_mana (on_death, Mourner) — routes through
# Combat._battlecry_bonus_mana_next_turn (EV_MANA next=true for the client).
const BROKEN_ON_ENTER := {
	"look_top": "host-only (client no-op): scry the caster's pile",
	"discover": "host-only picker (client no-op) — needs Discover net infra",
	"discover_link": "host-only picker (client no-op) — needs Discover net infra",
	"discard_random": "is_enemy-gated: only disrupts when ENEMY plays it",
}
const BROKEN_ON_DEATH := {
	"debuff_all_player_atk": "was_enemy-gated: only fires for an enemy death",
}
const BROKEN_ON_PLAY := {
	"scry": "host-only picker (client no-op)",
	"reorder_deck": "host-only picker (client no-op)",
	"filter_draw": "host-only picker (client no-op)",
	"raise_dead": "host-only pile read (client no-op)",
	"graveyard_damage": "reads the HOST discard pile regardless of owner",
	"discard_top_damage": "reads the HOST draw pile regardless of owner",
}


func _process(_delta: float) -> bool:
	_run()
	return true   # quit after one frame


func _run() -> void:
	var CDB = root.get_node_or_null("CardDB")
	var SS = root.get_node_or_null("SkirmishState")
	if CDB == null or SS == null:
		print("FATAL: autoloads missing")
		quit(1)
		return

	var pool: Array = SS.skirmish_legal_pool()
	print("[net-effect-audit] skirmish legal pool = %d cards\n" % pool.size())

	var hits := {"on_enter": [], "on_death": [], "on_play": []}
	for id in pool:
		var d: Dictionary = CDB.get_card_data(id)
		_scan(d, "on_enter", BROKEN_ON_ENTER, id, hits)
		_scan(d, "on_death", BROKEN_ON_DEATH, id, hits)
		_scan(d, "on_play", BROKEN_ON_PLAY, id, hits)

	var total := 0
	for slot in ["on_enter", "on_death", "on_play"]:
		var rows: Array = hits[slot]
		print("── %s: %d draftable cards ──" % [slot.to_upper(), rows.size()])
		for r in rows:
			print("   %-18s %-22s  %s  [%s]" % [r.id, r.type, r.why, r.rarity])
		total += rows.size()
		print("")
	print("[net-effect-audit] %d client-broken draftable card-effects total" % total)

	# ── FULL CENSUS: every distinct effect type / passive / floop in the legal pool,
	# with the cards using it — so a host-only path can't hide in a type I didn't
	# anticipate. Cross-check each against the resolvers' is_enemy handling.
	print("\n==================== FULL TYPE CENSUS ====================")
	for slot in ["on_enter", "on_death", "on_play", "floop"]:
		var census := {}
		for id in pool:
			var d: Dictionary = CDB.get_card_data(id)
			if d.has(slot):
				var t := String((d[slot] as Dictionary).get("type", "?"))
				if not census.has(t):
					census[t] = []
				census[t].append(id)
		var keys := census.keys()
		keys.sort()
		print("\n── %s types (%d distinct) ──" % [slot, keys.size()])
		for t in keys:
			print("   %-24s ×%d  %s" % [t, census[t].size(), str(census[t])])
	# Passives are a bare string field, not a {type:} dict.
	var pcensus := {}
	for id in pool:
		var d: Dictionary = CDB.get_card_data(id)
		var p := String(d.get("passive", ""))
		if p != "":
			if not pcensus.has(p):
				pcensus[p] = []
			pcensus[p].append(id)
	var pkeys := pcensus.keys()
	pkeys.sort()
	print("\n── passive values (%d distinct) ──" % pkeys.size())
	for p in pkeys:
		print("   %-24s ×%d  %s" % [p, pcensus[p].size(), str(pcensus[p])])
	quit(0)


func _scan(d: Dictionary, slot: String, broken: Dictionary, id: String, hits: Dictionary) -> void:
	if not d.has(slot):
		return
	var t := String((d[slot] as Dictionary).get("type", ""))
	if broken.has(t):
		hits[slot].append({"id": id, "type": t, "why": broken[t],
			"rarity": String(d.get("rarity", "?"))})
