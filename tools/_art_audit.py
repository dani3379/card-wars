#!/usr/bin/env python3
"""Audit which art assets the game references but doesn't have on disk.
Counts both PNG and SVG so the relic list reflects real gaps, not stylistic
mismatches. Adds elite/boss painted-splash check.
"""
import os, re
from pathlib import Path

ROOT = Path(__file__).parent.parent
os.chdir(ROOT)

def read(p): return Path(p).read_text(encoding="utf-8", errors="replace")

def stems(folder, exts):
    p = ROOT / folder
    if not p.exists(): return set()
    return {f.stem for f in p.iterdir() if f.suffix.lower() in exts}

card_db = read("scripts/data/CardDB.gd")

aliases = {}
alias_path = ROOT / "scripts/data/CardArtAliases.gd"
if alias_path.exists():
    aliases = dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"',
        alias_path.read_text(encoding="utf-8", errors="replace")))

creature_ids = set()
spell_ids = set()
enemy_ids = set()
for m in re.finditer(r'"(\w+)"\s*:\s*\{[^{}]*"id":\s*"\1"[^{}]*"type":\s*"(\w+)"', card_db):
    key, ctype = m.group(1), m.group(2)
    if key.startswith("e_"):
        enemy_ids.add(key)
    elif ctype == "creature":
        creature_ids.add(key)
    elif ctype == "spell":
        spell_ids.add(key)
spell_ids |= {"curse", "wound"}

relic_db = read("scripts/data/RelicDB.gd")
relic_ids = set(re.findall(r'"id":\s*"([^"]+)"', relic_db))

enc_db = read("scripts/data/EncounterDB.gd")
# encounter dict keys at top level (1 tab indent + key on its own indent level)
# heuristic: find blocks where a key has "type": "boss"/"elite" within ~30 lines.
enc_blocks = re.split(r'\n(?=\t"[a-z_]+":\s*\{$)', enc_db, flags=re.M)
boss_ids = []
elite_ids = []
for block in enc_blocks:
    m = re.match(r'\t"([a-z_]+)":\s*\{', block)
    if not m: continue
    eid = m.group(1)
    if '"type": "boss"' in block:
        boss_ids.append(eid)
    elif '"type": "elite"' in block:
        elite_ids.append(eid)

# Events
event_text = read("scripts/scenes/Event.gd") if (ROOT/"scripts/scenes/Event.gd").exists() else ""
event_ids = set(re.findall(r'"([a-z_]+)"\s*:\s*\{\s*"name":', event_text))

# Disk inventory
creature_art = stems("assets/creatures", (".png",))
spell_art    = stems("assets/spells",    (".png",))
relic_art    = stems("assets/icons/relics", (".png", ".svg"))
portrait_art = stems("assets/portraits", (".png", ".jpg"))
event_art    = stems("assets/events",    (".png", ".jpg"))

def resolve(id_): return aliases.get(id_, id_)
def chk(ids, art):
    return [(i, resolve(i)) for i in sorted(ids) if resolve(i) not in art]

print("=" * 70)
print(f"  CARD CREATURES — {len(creature_ids)} cards")
print("=" * 70)
m = chk(creature_ids, creature_art)
for i, t in m: print(f"  MISSING  {i}" + (f"  (alias: {t})" if i!=t else ""))
print(f"  >>> {len(m)} missing\n")

print("=" * 70)
print(f"  CARD SPELLS — {len(spell_ids)} cards")
print("=" * 70)
m = chk(spell_ids, spell_art)
for i, t in m: print(f"  MISSING  {i}" + (f"  (alias: {t})" if i!=t else ""))
print(f"  >>> {len(m)} missing\n")

print("=" * 70)
print(f"  ENEMY CREATURES — {len(enemy_ids)} cards")
print("=" * 70)
m = chk(enemy_ids, creature_art)
for i, t in m: print(f"  MISSING  {i}" + (f"  (alias: {t})" if i!=t else ""))
print(f"  >>> {len(m)} missing\n")

print("=" * 70)
print(f"  RELICS — {len(relic_ids)} relics (PNG or SVG counted)")
print("=" * 70)
m = chk(relic_ids, relic_art)
for i, _ in m: print(f"  MISSING  {i}")
print(f"  >>> {len(m)} missing\n")

print("=" * 70)
print(f"  BOSS PAINTED SPLASHES — {len(boss_ids)} bosses (fallback: boss_act<N>.png)")
print("=" * 70)
for b in sorted(boss_ids):
    fn = f"boss_{b}"
    mark = "OK     " if fn in portrait_art else "MISSING"
    print(f"  {mark}  {fn}.png")
print()

print("=" * 70)
print(f"  ELITE PAINTED SPLASHES — {len(elite_ids)} elites (fallback: lead-card art)")
print("=" * 70)
for b in sorted(elite_ids):
    fn = f"boss_{b}"
    mark = "OK     " if fn in portrait_art else "MISSING"
    print(f"  {mark}  {fn}.png")
print()

print("=" * 70)
print(f"  EVENTS — {len(event_ids)} events")
print("=" * 70)
miss = [e for e in event_ids if e not in event_art]
for e in sorted(miss): print(f"  MISSING  {e}")
print(f"  >>> {len(miss)} missing\n")
