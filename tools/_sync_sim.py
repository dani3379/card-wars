#!/usr/bin/env python3
"""One-shot script to regenerate the CARDS dict in burning_meadow_sim.jsx
   from scripts/data/CardDB.gd. Doesn't try to perfectly map every effect —
   captures id/name/type/cost/atk/hp/rarity/keywords/floop type+value/
   on_enter type+value/on_death type+value/spell type+value/targeting/desc.
   New cards (not previously in sim) get bare entries with minimal effect."""
import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
CARDDB = ROOT / "scripts" / "data" / "CardDB.gd"
RELICDB = ROOT / "scripts" / "data" / "RelicDB.gd"
SIM = ROOT / "tools" / "burning_meadow_sim.jsx"

txt = CARDDB.read_text(encoding="utf-8")

# Find each card entry. Each entry starts on a line beginning with
# `\t"<id>": {"id": "<id>", "name": "...",` and ends with `}},` at indent depth 1.
# We rely on the fact that nested `{` blocks are single-line (e.g. `"floop": {...}`)
# so we can match by greedy regex up to the next top-level `},\n\t"` or `}\n\n`.

card_pat = re.compile(
    r'\t"([a-z_]+)":\s*\{"id":\s*"(?P=name1)"(?P<body>.*?)\}\},'.replace(
        "(?P=name1)", r"\1"),
    re.DOTALL,
)
# Above is fragile — let me use a simpler line-based parser instead.

def parse_cards(text):
    cards = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'\t"([a-z_]+)":\s*\{"id":\s*"\1"', line)
        if not m:
            i += 1
            continue
        # Found start of a card. Concatenate lines until we hit a line ending in }}, or }} (end of dict)
        cid = m.group(1)
        buf = [line]
        # The entry may span 1..5 lines. Scan until brace depth returns to 0.
        depth = 0
        j = i
        while j < len(lines):
            for ch in lines[j]:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
            if j > i and depth == 0:
                break
            j += 1
            if j < len(lines) and j > i:
                buf.append(lines[j])
        joined = "\n".join(buf)
        cards[cid] = joined
        i = j + 1
    return cards

cards = parse_cards(txt)

def field(body, key, kind="str"):
    """Extract a JSON-ish field from the card body. kind: str | int | list | dict | dict_inline"""
    if kind == "int":
        m = re.search(r'"%s":\s*(-?\d+)' % key, body)
        return int(m.group(1)) if m else None
    if kind == "str":
        m = re.search(r'"%s":\s*"([^"]*)"' % key, body)
        return m.group(1) if m else None
    if kind == "list":
        m = re.search(r'"%s":\s*\[([^\]]*)\]' % key, body)
        if not m:
            return []
        items = re.findall(r'"([^"]+)"', m.group(1))
        return items
    if kind == "dict_inline":
        # Find {...} after "key":
        m = re.search(r'"%s":\s*\{([^{}]*)\}' % key, body)
        if not m:
            return None
        return m.group(1)
    return None

def js_str(s):
    if s is None:
        return "null"
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def js_keywords(kws):
    return "[" + ",".join('"%s"' % k for k in kws) + "]"

def js_floop(body):
    inner = field(body, "floop", "dict_inline")
    if inner is None:
        return "null"
    # parse "type": "X", "value": N
    t = re.search(r'"type":\s*"([^"]+)"', inner)
    v = re.search(r'"value":\s*(-?\d+)', inner)
    parts = []
    if t:
        parts.append('type:"%s"' % t.group(1))
    if v:
        parts.append('value:%d' % int(v.group(1)))
    return "{" + ",".join(parts) + "}" if parts else "null"

# Enemy cards (id starts with e_) are placed via encounter decks, not drafted —
# skip them from the sim's CARDS dict (the sim builds enemies from ENCOUNTERS).
SKIP = lambda cid: cid.startswith("e_") or cid in {"curse", "wound"}

# Group cards by type for ordered output
sections = []
for cid, body in cards.items():
    if SKIP(cid):
        continue
    name = field(body, "name", "str") or cid
    ctype = field(body, "type", "str") or "creature"
    cost = field(body, "cost", "int") or 0
    rarity = field(body, "rarity", "str") or "common"
    keywords = field(body, "keywords", "list")
    desc = field(body, "desc", "str") or ""
    entry = {"id": cid, "name": name, "type": ctype, "cost": cost, "rarity": rarity, "keywords": keywords, "desc": desc}
    if ctype == "creature":
        entry["atk"] = field(body, "atk", "int") or 0
        entry["hp"] = field(body, "hp", "int") or 1
        entry["floop"] = js_floop(body)
    else:
        # Spell — most are type:"custom" in CardDB with values baked in
        # Combat._resolve_custom_spell. Mirror the effective behavior here so
        # the sim can score them. Keep custom_* for genuinely complex spells
        # (sacrifice + reward, discard chains, etc.) that the sim engine
        # has explicit handlers for.
        spell = field(body, "spell", "dict_inline")
        effect = "damage"; value = 0
        target = field(body, "targeting", "str") or "none"
        custom_id = None
        if spell:
            tm = re.search(r'"type":\s*"([^"]+)"', spell)
            vm = re.search(r'"value":\s*(-?\d+)', spell)
            im = re.search(r'"id":\s*"([^"]+)"', spell)
            if tm: effect = tm.group(1)
            if vm: value = int(vm.group(1))
            if im: custom_id = im.group(1)
        if effect == "custom" and custom_id:
            # Override map — flatten the custom handler's behavior to a sim
            # effect+value pair where possible. Format: (effect, value[, target])
            # When (effect, value) is None, leave as custom_<id> for the sim
            # engine's explicit handler.
            OVERRIDES = {
                "slash": ("damage", 3),
                "shield_wall": ("buff_hp", 4),
                "war_cry": ("buff_all_atk", 1),
                "patch_up": ("heal", 4),
                "flame_bolt": ("damage_face", 3),
                "shove": ("damage", 2),
                "reckless_charge": ("damage", 3),
                "quick_shot": ("damage", 1),
                "frost_bolt": ("damage", 2),
                "ricochet": ("damage", 2),
                "hex": ("damage", 2),
                "hoarfrost": ("damage_all_enemies", 1),
                "holy_smite": ("damage", 3),
                "lay_on_hands": ("heal", 99),
                "lost_tome": ("draw", 1),
                "mass_grave": ("damage_all_enemies", 3),
                "pillage": ("damage", 3),
                "reanimate": ("draw", 1),
                "smite_spell": ("damage", 6),
                "venom_tip": ("buff_hp", 0),
                "ambush": ("damage_all_enemies", 1),
                "dark_pact": ("buff_all_atk", 1),
                "earthquake": ("damage_all", 3),
                "inspire": ("buff_all_atk", 2),
                "war_council": ("draw", 1),
                "apocalypse": ("damage_all", 99),
                "inferno": ("damage_all_enemies", 4),
                "kings_command": ("buff_all_atk", 3),
                "overwhelming_force": ("buff_all_atk", 3),
                "unholy_bargain": ("draw", 3),
                "charge_spell": ("damage", 1),
            }
            if custom_id in OVERRIDES:
                effect, value = OVERRIDES[custom_id]
            else:
                effect = "custom_" + custom_id
        entry["effect"] = effect
        entry["value"] = value
        entry["target"] = target
        if "exhaust" in keywords:
            entry["exhaust"] = True
    sections.append(entry)

# Order: starters, then commons (creatures then spells), uncommons, rares.
def sortkey(e):
    rarity_order = {"starter": 0, "common": 1, "uncommon": 2, "rare": 3}
    type_order = {"creature": 0, "spell": 1}
    return (rarity_order.get(e["rarity"], 99), type_order.get(e["type"], 99), e["cost"], e["id"])

sections.sort(key=sortkey)

# Emit JS
lines = ["// ── CARD DATABASE (regenerated from CardDB.gd by tools/_sync_sim.py) ──"]
lines.append("const CARDS = {")
last_section = None
for e in sections:
    section_tag = (e["rarity"], e["type"])
    if section_tag != last_section:
        last_section = section_tag
        label = {
            ("starter", "creature"): "Starters",
            ("starter", "spell"): "Starter Spells",
            ("common", "creature"): "Common Creatures",
            ("common", "spell"): "Common Spells",
            ("uncommon", "creature"): "Uncommon Creatures",
            ("uncommon", "spell"): "Uncommon Spells",
            ("rare", "creature"): "Rare Creatures",
            ("rare", "spell"): "Rare Spells",
        }.get(section_tag, "%s %ss" % section_tag)
        lines.append("  // %s" % label)
    if e["type"] == "creature":
        kws = js_keywords(e["keywords"])
        lines.append('  %s: { name:%s, type:"creature", rarity:"%s", cost:%d, atk:%d, hp:%d, keywords:%s, floop:%s },' % (
            e["id"], js_str(e["name"]), e["rarity"], e["cost"], e["atk"], e["hp"], kws, e["floop"]
        ))
    else:
        extra = ""
        if e.get("exhaust"):
            extra = ", exhaust:true"
        lines.append('  %s: { name:%s, type:"spell", rarity:"%s", cost:%d, effect:"%s", value:%d, target:"%s"%s },' % (
            e["id"], js_str(e["name"]), e["rarity"], e["cost"], e["effect"], e["value"], e.get("target", "none"), extra
        ))
lines.append("};")
new_cards_block = "\n".join(lines) + "\n"

# Now replace the CARDS block in sim.jsx.
sim_txt = SIM.read_text(encoding="utf-8")
m = re.search(r'^// ── CARD DATABASE.*?^const CARDS = \{.*?^\};\n', sim_txt, re.DOTALL | re.MULTILINE)
if not m:
    raise SystemExit("Could not locate CARDS block in sim.jsx")

new_sim = sim_txt[:m.start()] + new_cards_block + sim_txt[m.end():]
SIM.write_text(new_sim, encoding="utf-8")

print(f"Regenerated CARDS block with {len(sections)} cards")
print(f"  Starters: {sum(1 for e in sections if e['rarity']=='starter')}")
print(f"  Commons:  {sum(1 for e in sections if e['rarity']=='common')}")
print(f"  Uncommon: {sum(1 for e in sections if e['rarity']=='uncommon')}")
print(f"  Rare:     {sum(1 for e in sections if e['rarity']=='rare')}")


# ─────────────────────────────────────────────────────────────
# RELICS — regen all four arrays from RelicDB.gd
# ─────────────────────────────────────────────────────────────

rtxt = RELICDB.read_text(encoding="utf-8")

# Each relic is one entry: \t"id": {"id": "id", "name": "Name", "tier": "..", "desc": "..", ...}
relic_pat = re.compile(
    r'\t"(?P<id>[a-z_]+)":\s*\{[^}]*"id":\s*"(?P=id)"[^}]*?"tier":\s*"(?P<tier>[a-z]+)"[^}]*?"desc":\s*"(?P<desc>[^"]+)"[^}]*?\}',
    re.DOTALL,
)
relics_by_tier = {"starting": [], "combat": [], "utility": [], "boss": []}
for m in relic_pat.finditer(rtxt):
    rid = m.group("id")
    tier = m.group("tier")
    desc = m.group("desc")
    # Pull name from a separate search since the inline regex's name capture got eaten
    nm = re.search(r'"%s":\s*\{[^}]*"name":\s*"([^"]+)"' % re.escape(rid), rtxt)
    name = nm.group(1) if nm else rid
    if tier in relics_by_tier:
        relics_by_tier[tier].append({"id": rid, "name": name, "desc": desc})
    else:
        # Treat any unknown tier as combat (4x4-specific, mana relics also use "combat")
        relics_by_tier["combat"].append({"id": rid, "name": name, "desc": desc})

def emit_relic_array(var_name, items):
    out = [f"const {var_name} = ["]
    for r in items:
        out.append(f'  {{ id:"{r["id"]}", name:"{r["name"]}", desc:"{r["desc"]}" }},')
    out.append("];")
    return "\n".join(out)

new_relics_block = "\n// ── RELICS (regenerated from RelicDB.gd by tools/_sync_sim.py) ──\n"
new_relics_block += emit_relic_array("STARTING_RELICS", relics_by_tier["starting"]) + "\n\n"
new_relics_block += emit_relic_array("COMBAT_RELICS", relics_by_tier["combat"]) + "\n\n"
new_relics_block += emit_relic_array("UTILITY_RELICS", relics_by_tier["utility"]) + "\n\n"
new_relics_block += emit_relic_array("BOSS_RELICS", relics_by_tier["boss"]) + "\n"

# Replace the old relics block in sim.jsx. It runs from "// ── RELICS ──" to
# the end of BOSS_RELICS array (then the next comment is "// ── ENCOUNTERS").
sim_txt2 = SIM.read_text(encoding="utf-8")
m = re.search(r'^// ── RELICS.*?^const BOSS_RELICS = \[.*?^\];\n', sim_txt2, re.DOTALL | re.MULTILINE)
if not m:
    raise SystemExit("Could not locate RELICS block in sim.jsx")

new_sim2 = sim_txt2[:m.start()] + new_relics_block + sim_txt2[m.end():]
SIM.write_text(new_sim2, encoding="utf-8")

print(f"\nRegenerated RELICS block:")
print(f"  Starting: {len(relics_by_tier['starting'])}")
print(f"  Combat:   {len(relics_by_tier['combat'])}")
print(f"  Utility:  {len(relics_by_tier['utility'])}")
print(f"  Boss:     {len(relics_by_tier['boss'])}")
