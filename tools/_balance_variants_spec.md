# Balance variant grading task — spec for the grader agent

## Goal
Three cards were broken by the simultaneity fix (they're flat/dead now). Rework each into a card that is **situational but exciting** — NOT a number-shave. Each variant below is built on a real, named genre mechanic (Morbid, go-wide, Overload, strike-first, rage-on-hit). Your job: implement each variant, **objectively sim-grade** it, keep the best per card, revert the rest.

The user's rule (obey it): do NOT make cards boring. Power is fine if it's **conditional**. A good rework has a *fair floor* (not a dead card, not an auto-include) and a *high ceiling* when its condition is met.

## Grading method (objective, two-shell sim)
Harness: `tools/_probe_cardpower.gd`. Stacks 4 copies of the card + 6 filler, runs an act1+act3 gauntlet, prints `lift` (HP-margin vs that shell's baseline). Higher lift = stronger. Run each variant in BOTH shells:

- **FLOOR** (neutral): `Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_cardpower.gd -- --only=<id> --filler=brute`
- **CEILING** (enabling: goblins are wide + die a lot + hit face, so they turn on go-wide / Morbid / Spectacle conditions): `... --only=<id> --filler=goblin`

Binary: `D:/games/Godot_v4.6.2-stable_win64.exe`. Each run ≈ 30–60s. Read the `lift` line.

### Rubric (pick the winner per card)
1. **FLOOR lift must be fair:** roughly `-3 .. +5`. Below −3 = still a dead card (reject). Above +6 = an unconditional auto-include (reject — that's the boring-strong we're avoiding).
2. **CEILING should beat FLOOR** (compare the variant's goblin-shell result to its brute-shell result, and to the OTHER variants in the goblin shell). A bigger floor→ceiling gap = more situational = better.
3. **Design check:** it must use a real condition/hook (situational), not a flat stat line. Prefer the one that's most *exciting* if two grade similarly.
4. Keep the winner implemented; revert the card to its ORIGINAL for any losing variant (work from the original each time — do NOT stack edits).

Report a table: card | variant | floor lift | ceiling lift | verdict, and which you applied + why.

---

## CARD 1 — kings_command  (2cc RARE spell)
CardDB.gd: `"desc"` currently `"All friendlies get +3 ATK this round and a permanent +1 HP. Exhaust."`
Resolver: Combat.gd `_resolve_custom_spell`, arm `"kings_command":` (~line 5103). ORIGINAL resolver:
```
"kings_command":
    var atk_gain2: int = 3 + plus_dmg
    var hp_gain2: int = 1 + plus_dmg
    for c in _all_player_creatures():
        c.temp_atk_buff += atk_gain2
        c.current_hp += hp_gain2
        c.card_data.hp += hp_gain2
        c.update_stat_display()
```
- **V1 "Fight anthem" (survival that sticks):** desc "All friendlies get +2/+2 this fight. Exhaust." Resolver: for each: `c.current_atk += 2; c.card_data.hp += 2; c.current_hp += 2`. (Permanent-for-fight so the buff survives a trade — copy the +HP pattern from the `battle_hymn` arm.)
- **V2 "Go-wide payoff" (scales with board):** desc "All friendlies get +1/+1 this fight, plus +1/+1 more for each friendly beyond the first. Exhaust." Resolver: `var n = _all_player_creatures().size(); var g = 1 + maxi(0, n-1)` then each `+= g` atk and hp (perm-for-fight). Situational: dead on an empty board, a bomb when wide.
- **V3 "Morbid" (feeds on death):** desc "All friendlies get +2/+1 this fight; +4/+2 instead if a friendly died this round. Exhaust." Resolver: `var big = _friendly_deaths_this_round > 0; var a = 4 if big else 2; var h = 2 if big else 1` then perm-for-fight. (`_friendly_deaths_this_round` already exists.)

## CARD 2 — inspire  (2cc uncommon spell)
CardDB desc currently `"All friendlies get +2 ATK and Piercing this round. Exhaust."`
Resolver arm `"inspire":` (~line 5282). ORIGINAL:
```
"inspire":
    var inspire_atk: int = 2 + plus_dmg
    for c in _all_player_creatures():
        c.temp_atk_buff += inspire_atk
        c.set_meta("inspire_piercing", true)
        c.update_stat_display()
```
- **V1 "Morbid":** desc "All friendlies get +2 ATK and Piercing this round; +4 instead if a friendly died this round." Resolver: `var a = 4 if _friendly_deaths_this_round > 0 else 2`, keep the `inspire_piercing` meta.
- **V2 "Strike-first" (alpha strike):** desc "All friendlies gain Piercing and Swift this round." Resolver: for each: `c.set_meta("inspire_piercing", true); c.set_meta("war_cry_swift", true); c.update_stat_display()`. (Reuse the `war_cry_swift` meta — see the `war_cry` arm; Swift-this-round lets your team strike first in the simultaneous clash. Drop the raw +ATK — the tempo IS the payoff.)
- **V3 "Kicker floor" (never dead):** desc "All friendlies get +2 ATK and Piercing this round. Draw a card. Exhaust." Resolver: original + `draw_one()`. (Gives it a floor so it's never a dead card — cantrip.)

## CARD 3 — berserker  (2cc creature)
CardDB.gd (~line 175): `"atk": 3, "hp": 3, ... "passive": "grow_on_attack", "extra_damage": 1`, desc "Gains +1 ATK each round this attacks. Takes +1 damage from all sources."
Note: `grow_on_attack` adds +1 in Combat.gd `_do_combat` (~line 2329: `c.current_atk += 1`). `extra_damage` is read in Card2D.take_damage. This card is DATA-driven except V3.
- **V1 "Bulk to snowball":** `atk 3, hp 5`, keep grow_on_attack + extra_damage 1. desc unchanged wording but 3/5. (Survives to grow — the simplest fix.)
- **V2 "Glass cannon" (risk/reward):** `atk 4, hp 4`, extra_damage **2**, and make grow +2/attack (edit the `grow_on_attack` line in `_do_combat` to `+= 2` — or add a check; keep it simple). desc "Gains +2 ATK each round it attacks. Takes +2 damage from all sources." Bigger swings both ways.
- **V3 "Rage-on-hit" (fragility IS the engine):** `atk 3, hp 4`, keep extra_damage 1, REMOVE grow_on_attack, add a new passive `rage_on_hit`: whenever it is hit and survives, +2 ATK. Implement by copying the royal_guard "+ATK when hit" block in `_creature_attacks_creature` (~line 2717) — add a parallel `if defender.card_data.get("passive","")=="rage_on_hit" and defender.current_hp>0 and atk>0: defender.current_atk += 2; defender.update_stat_display()`. desc "Whenever it is hit and survives, +2 ATK. Takes +1 damage from all sources." (The reckless fragility now fuels the rage.)

After all edits, parse-check headless (`--editor --quit-after 5 res://scenes/combat.tscn`) and make sure the winners are the only changes left in CardDB.gd / Combat.gd.
