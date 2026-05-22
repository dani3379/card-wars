extends RefCounted
class_name CreatureInstance
## Gameplay state for a creature on the board. Separated from Card2D so future
## work (unit tests, AI simulator, save/load reliability, replays, undo) can
## reason about combat without instantiating UI nodes.
##
## Migration is incremental. Each flag moves from Card2D's `set_meta(...)` bag
## to a typed field here. While migration is in progress, both forms may exist
## side-by-side — callsites are migrated one at a time.
##
## ── MIGRATED ─────────────────────────────────────────────────────────────
##   stunned
##
## ── STILL ON Card2D via set_meta() — TO MIGRATE ─────────────────────────
##   temp_armored        bool   — Combat.gd:791,796,803,2796 (set); 3088 (check)
##   bonus_thorns        int    — Combat.gd:805 (set); 805 (read)
##   temp_thorns         int    — Combat.gd:812 (set); 3091 (check)
##   redirecting         bool   — Combat.gd:814 (set); 1230 (check)
##   challenge_any_lane  bool   — Combat.gd:900 (set); spot-checks
##   swap_atk_original   int    — Combat.gd:961-962 (set); 3103 (read)
##   is_copy             bool   — Combat.gd:969 (set)
##   marked              bool   — Combat.gd:2896 (set); 1141 (check)
##   enrage_vulnerable   bool   — Combat.gd:2808 (set); 1143 (check)
##   will_retreat        bool   — Combat.gd:2811 (set); 3112 (check)
##   floop_discount      int    — Combat.gd:873 (set)
##   current_intent      String — Combat.gd:2654,2670 (set); 2693 (check)
##   last_intent         String — Combat.gd:2671 (set); 2662 (read)
##   intent_consecutive  int    — Combat.gd:2672 (set); 2661 (read)
##   intent_cycle_pos    int    — Combat.gd:2673,2942 (set); 2658 (read)
##
## ── Combat-level flags (on `self`, not on a card) ─────────────────────
##   phantom_veil_used   bool   — Combat.gd:543,1357 — once-per-round relic gate
##
## ── HOW TO MIGRATE A FLAG ─────────────────────────────────────────────
## 1. Add a typed field here.
## 2. In Card2D.gd, expose a getter that mirrors `set_meta`/`get_meta` to the
##    typed field if Card2D holds an instance.
## 3. Replace each `set_meta("X", v)` / `get_meta("X", ...)` callsite in
##    Combat.gd with `card.state.X = v` / `card.state.X`.
## 4. Remove the entry from the table above.


# === Per-round flags (cleared by tick_end_of_round) =====================
var stunned: bool = false             # Spell/floop set; skips combat this round


# === Combat lifecycle ===================================================

func tick_end_of_round() -> void:
	# Reset every per-round flag in one place so we never forget one. As fields
	# migrate here from set_meta, add their reset to this method.
	stunned = false


func reset_temp_state() -> void:
	# Clear ALL temporary effects — used when a creature is copied or transformed
	# (e.g. become_copy floop). Per-round tick is a subset of this.
	tick_end_of_round()
