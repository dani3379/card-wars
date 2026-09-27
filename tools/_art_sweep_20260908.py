"""Merge machine metrics (art_lint) + hand verdicts (this session's viewing pass)
+ liveness into ONE row per shipped image, so the sweep is complete by
construction rather than by claim.

Output: verdicts.csv + a markdown table per family.
"""
import os, re, csv, json, subprocess, collections

ROOT = "D:/Godot"
SP = r"C:/Users/danie/AppData/Local/Temp/claude/D--Godot/2fc2ded0-a6f4-42ff-bd6b-09cde20fbc2d/scratchpad"

FAMILIES = [
    "assets/creatures", "assets/spells", "assets/events", "assets/portraits",
    "assets/backgrounds", "assets/icons/relics", "assets/icons/potions",
    "assets/icons/keywords", "assets/icons/map", "assets/icons/stats",
    "assets/icons/game-icons", "assets/icons", "assets/frames", "assets/ui",
    "assets/icons/downloaded",
]

# ---------------------------------------------------------------- lint metrics
lint = collections.defaultdict(dict)
txt = open(os.path.join(SP, "lint_full.txt"), encoding="utf-8", errors="replace").read()
sec = None
for line in txt.splitlines():
    if line.startswith("== "):
        sec = line
        continue
    m = re.match(r"\s*([\d.]+)%\s+(\S+)$", line)
    if m and sec and "CYAN" in sec:
        lint[m.group(2)]["cyan"] = float(m.group(1))
    m = re.match(r"\s*z=\s*([\d.]+) on (\S+)\s+(\S+)$", line)
    if m:
        lint[m.group(3)]["outlier"] = f"z{m.group(1)} {m.group(2)}"
    m = re.match(r"\s*blocky=\s*([\d.]+)%\s+colors=\s*(\d+)\s+(\S+)$", line)
    if m:
        lint[m.group(3)]["blocky"] = m.group(1)
    m = re.match(r"\s*tones=\s*(\d+)\s+texture=\s*([\d.]+)\s+(\S+)$", line)
    if m:
        lint[m.group(3)]["tones"] = m.group(1)
    m = re.match(r"\s*EXACT\s+(\S+)\s+==\s+(\S+)$", line)
    if m:
        lint[m.group(1)]["dup"] = "EXACT==" + os.path.basename(m.group(2))
        lint[m.group(2)]["dup"] = "EXACT==" + os.path.basename(m.group(1))
    m = re.match(r"\s*NEAR\((\d+)\)\s+(\S+)\s+~\s+(\S+)$", line)
    if m:
        lint[m.group(2)]["dup"] = "NEAR==" + os.path.basename(m.group(3))
        lint[m.group(3)]["dup"] = "NEAR==" + os.path.basename(m.group(2))

# ------------------------------------------------- hand verdicts from viewing
# grade: R1 = replace, high priority (wrong subject / breaks the set on sight)
#        R2 = replace / regrade (palette or register break, subject is fine)
#        D  = delete (dead file, duplicate, or dev leftover)
#        K  = keep
V = {}


def put(grade, reason, *names):
    for n in names:
        V[n] = (grade, reason)


# --- creatures
put("R1", "no creature in frame - a teal seascape", "assets/creatures/the_black_tide.png")
put("R1", "burning cart, not a stalker", "assets/creatures/ember_stalker.png")
# --- corrected after full-res re-check; the thumbnail misread each of these ---
put("K", "FULL-RES RECHECK: a mounted lancer at the couch - strong and on style",
    "assets/creatures/lancer.png")
put("R2", "witch + crows are legible at full res; the defect is 75% cyan and low contrast",
    "assets/creatures/crow_witch.png")
put("R2", "FULL-RES RECHECK: a rock colossus IS there; the defect is the pastel lavender",
    "assets/creatures/stone_sentinel.png")
put("R2", "FULL-RES RECHECK: egg + brood are there but muddy and low contrast",
    "assets/creatures/hatchling_brood.png")
put("R2", "FULL-RES RECHECK: pale twin with lit eyes IS there; the defect is cyan",
    "assets/creatures/doppelganger.png")
put("R1", "82% cyan; aliased by revenant/vengeance/the_undying so it is high-traffic",
    "assets/creatures/vengeful_spirit.png")
put("R1", "cute cartoon housecat - breaks tone hardest of any card",
    "assets/creatures/stray_cat.png")
put("R1", "Ghibli-cute fairy child in flowers", "assets/creatures/sprite.png")
put("R1", "big-eyed cute child", "assets/creatures/torchbearer.png")
put("R1", "cute grinning imp, pink", "assets/creatures/hellfire_imp.png")
put("R1", "cute cartoon gnome", "assets/creatures/gravedigger.png")
put("R1", "pink many-eyed fluffball on cream - cutest thing in the pool",
    "assets/creatures/chaos_imp.png")
put("R1", "cyan cute fairy blob", "assets/creatures/mana_sprite.png")
put("R2", "smiling fire sprite reads cute; also an exact pair",
    "assets/creatures/kindling.png", "assets/creatures/kindling_alt.png")
put("R2", "64% cyan", "assets/creatures/glass_knight.png")
put("R2", "60% cyan", "assets/creatures/chorus_of_echoes.png")
put("R2", "75% cyan", "assets/creatures/crow_witch.png")
put("R2", "pastel lavender owl - softest thing on the board",
    "assets/creatures/e_wind_harpy.png")
put("R2", "neon acid green", "assets/creatures/plague_rat.png")
put("R2", "green outlier", "assets/creatures/risen_lich.png", "assets/creatures/e_bone_knight.png",
    "assets/creatures/necromancer.png", "assets/creatures/harpy.png")
put("R2", "cyan glow", "assets/creatures/e_golem.png", "assets/creatures/assassin.png",
    "assets/creatures/copycat.png", "assets/creatures/archmage.png")
put("R2", "neon cyan crystals", "assets/creatures/leyline_conduit.png")
put("R2", "purple/lavender outlier", "assets/creatures/summoner.png", "assets/creatures/raven.png",
    "assets/creatures/cauldron.png", "assets/creatures/doom_knight.png",
    "assets/creatures/the_leveler.png")
put("R2", "smiling jack-o-lantern cloud, weak subject", "assets/creatures/cinder_whelp.png")
put("R2", "a toad for a corpse-eater", "assets/creatures/corpse_eater.png",
    "assets/creatures/basilisk.png")
put("R2", "a chest, no hunter", "assets/creatures/treasure_hunter.png")
put("R2", "subject illegible inside its own explosion", "assets/creatures/ember_mystic.png")
put("R2", "gold border baked into the bitmap", "assets/creatures/e_bog_lurker.png",
    "assets/creatures/mule.png")
put("D", "fine-art nude, off-style; dead file beside the live .png",
    "assets/creatures/e_devil_champ.jpg")

# --- spells
put("R1", "95% cyan - the single worst offender in the game; neon green crystal spikes",
    "assets/spells/ambush.png")
put("R1", "86% cyan whirlpool", "assets/spells/banish.png")
put("R1", "a GREEN pyre - the colour contradicts the card's own name",
    "assets/spells/fuel_the_pyre.png")
put("R2", "FULL-RES RECHECK: a frost-caked soldier - the concept EARNS its cool cast; "
          "the only cool-palette asset in the game that should stay cool",
    "assets/spells/hoarfrost.png")
put("R1", "purple; exact duplicate of mass_grave and no bell in frame",
    "assets/spells/plague_bell.png")
put("R1", "letterboxed - black bars baked top and bottom", "assets/spells/echo_spell.png")
put("R2", "77% cyan neon lightning", "assets/spells/lightning.png")
put("R2", "77% cyan", "assets/spells/recycle.png")
put("R2", "64% cyan pocket watch", "assets/spells/time_snare.png")
put("R2", "54% cyan", "assets/spells/shield_wall.png")
put("R2", "56% cyan", "assets/spells/hex.png", "assets/spells/lost_tome.png")
put("R2", "neon magenta pentagram", "assets/spells/dark_pact.png")
put("R2", "acid green", "assets/spells/quick_shot.png", "assets/spells/craven.png",
    "assets/spells/curse.png", "assets/spells/second_wind.png",
    "assets/spells/venom_tip.png", "assets/spells/reanimate.png")
put("R2", "purple outlier", "assets/spells/mass_grave.png", "assets/spells/grave_robbery.png",
    "assets/spells/earthquake.png")
put("R2", "cyan half of a two-colour composition", "assets/spells/reposition.png",
    "assets/spells/soul_swap.png")
put("R2", "vague smear, low legibility", "assets/spells/concentrate.png",
    "assets/spells/turbo.png", "assets/spells/ricochet.png")
put("R2", "pastel sky + a rock; weak read", "assets/spells/frost_bolt.png")
put("R2", "flat, near pixel-art", "assets/spells/grave_debt.png")

# --- events
put("R1", "86% cyan - the #2 offender", "assets/events/hollow_lantern.png")
put("R1", "photoreal stock coin on gravel", "assets/events/coin_on_edge.png")
put("R1", "washed-out photoreal road; no ink left in it",
    "assets/events/fork_in_the_long_road.png")
put("R2", "61% cyan", "assets/events/gravesong_choir.png")
put("R2", "67% cyan", "assets/events/sin_eater.png")
put("R2", "54-56% cyan", "assets/events/blood_fountain.png", "assets/events/hermit.png",
    "assets/events/dark_altar.png", "assets/events/glass_familiar.png",
    "assets/events/the_answering_well.png", "assets/events/thrice_blessed_spring.png",
    "assets/events/the_weeping_orchard.png")
put("R2", "photoreal register", "assets/events/butcher.png")
put("R2", "letterboxed - black bars baked top and bottom", "assets/events/the_chrysalis.png")
put("R2", "misty pond; nothing of the twin in it", "assets/events/mirror_twin.png")
put("R2", "a lit cave, nothing of a beekeeper", "assets/events/beekeeper.png")
put("R2", "generator filename shipped as the art id; rename to the event id",
    "assets/events/the_siege_kitchen-character-stage-v2.png")
put("D", "unreferenced second dev export of the same event",
    "assets/events/the_siege_kitchen-finished-events-v1.png")

# --- portraits
put("R1", "black+magenta, reads like a different game", "assets/portraits/enemy_commander.png")
put("R1", "anime face - the only one in the game", "assets/portraits/hero_portrait_pyromancer.png")
put("R1", "MISSING FILE - 4 of 5 heroes have a silhouette, Kindler has none",
    "assets/portraits/hero_silhouette_kindler.png")
put("R2", "fine-oil family while its 4 siblings are flat-ink",
    "assets/portraits/hero_portrait_kindler.png")
put("R2", "teal outlier", "assets/portraits/hero_portrait_acolyte.png",
    "assets/portraits/boss_collector.png", "assets/portraits/boss_hollow_king.png",
    "assets/portraits/hero_silhouette_raider.png", "assets/portraits/boss_iron_warden.png")
put("R2", "green outlier", "assets/portraits/hero_portrait_stalwart.png",
    "assets/portraits/hero_silhouette_stalwart.png")
put("R2", "pink/lavender outlier", "assets/portraits/boss_act2.png",
    "assets/portraits/boss_demon_vanguard.png")
put("R2", "no figure carries the frame", "assets/portraits/boss_rival_pyromancer.png")
put("D", "Duerer engraving - public-domain woodcut, zero references",
    "assets/portraits/player_knight.jpg")

# --- backgrounds
put("R2", "heavy teal/green", "assets/backgrounds/combat_arena_act2.png",
    "assets/backgrounds/rest_campfire_act2.png", "assets/backgrounds/rest_campfire_act3.png")
put("D", "photoreal forest photo, 0 references", "assets/backgrounds/event_forest.jpg")
put("D", "0 references", "assets/backgrounds/main_menu.jpg")
put("D", "photoreal night-forest photo, 0 references", "assets/backgrounds/rest_campfire.jpg")
put("D", "near-black corridor, 0 references", "assets/backgrounds/shop_tavern.jpg")
put("K", "paper fibre texture - the val outlier is correct for it",
    "assets/backgrounds/map_parchment.jpg")

# --- relics
put("R1", "a folding fan, not gloves; pastel pink", "assets/icons/relics/thiefs_gloves.png")
put("R1", "no boots in frame; 55% cyan", "assets/icons/relics/swift_boots.png")
put("R1", "a gold/teal cube, not a hammer", "assets/icons/relics/fusion_hammer.png")
put("R2", "FULL-RES RECHECK: a raised fist IS there; the defect is the magenta cast",
    "assets/icons/relics/glowing_hand.png")
put("R1", "an empty orange field with a post - reads unfinished",
    "assets/icons/relics/junk_slot.png")
put("R1", "80% cyan - worst in the family", "assets/icons/relics/mana_tide.png")
put("R1", "exact duplicate of war_horn.png", "assets/icons/relics/recruiters_horn.png")
put("R1", "photoreal product shot on black", "assets/icons/relics/coin_landed.png",
    "assets/icons/relics/war_drum.png", "assets/icons/relics/warlords_standard.png",
    "assets/icons/relics/warm_knucklebone.png")
put("R2", "cyan/blue outlier", "assets/icons/relics/acolytes_tome.png",
    "assets/icons/relics/lantern.png", "assets/icons/relics/mana_drunkard.png",
    "assets/icons/relics/mana_pearl.png", "assets/icons/relics/echo_staff.png",
    "assets/icons/relics/last_breath.png", "assets/icons/relics/phantom_veil.png",
    "assets/icons/relics/mark_of_pain.png", "assets/icons/relics/bone_ring.png",
    "assets/icons/relics/mimic_ring.png", "assets/icons/relics/soul_lantern.png",
    "assets/icons/relics/vanguards_cry.png")
put("R2", "magenta/purple outlier", "assets/icons/relics/conscription_relic.png",
    "assets/icons/relics/resonance_crystal.png", "assets/icons/relics/runic_pyramid.png",
    "assets/icons/relics/lichs_bargain.png", "assets/icons/relics/stygian_soul.png",
    "assets/icons/relics/steady_banner.png", "assets/icons/relics/lean_mean.png",
    "assets/icons/relics/calling_bell.png", "assets/icons/relics/snecko_eye.png",
    "assets/icons/relics/blacksmiths_hammer.png")
put("R2", "flat black ground while the family paints its grounds",
    "assets/icons/relics/hexagonal_shield.png", "assets/icons/relics/runebound_idol.png",
    "assets/icons/relics/scavengers_pouch.png", "assets/icons/relics/gravewardens_pact.png",
    "assets/icons/relics/banner_of_unity.png", "assets/icons/relics/doom_herald.png")
put("R2", "subject does not match the name", "assets/icons/relics/gamblers_coin.png",
    "assets/icons/relics/piercing_crown.png", "assets/icons/relics/ectoplasm.png",
    "assets/icons/relics/drovers_whip.png", "assets/icons/relics/busted_crown.png",
    "assets/icons/relics/briar_amulet.png", "assets/icons/relics/sozu.png")
put("R2", "white border baked into the bitmap", "assets/icons/relics/reapers_scythe.png")
put("R2", "photoreal register", "assets/icons/relics/pen_nib.png")
put("R2", "cosmic/sci-fi register in a medieval war", "assets/icons/relics/stardust_vial.png")
put("R2", "cheerful/soft tone break", "assets/icons/relics/happy_flower.png",
    "assets/icons/relics/sentinel_pact.png", "assets/icons/relics/mime.png",
    "assets/icons/relics/velvet_choker.png", "assets/icons/relics/coffee_dripper.png")
put("R2", "washed out, low ink", "assets/icons/relics/linked_banner.png")

# --- potions
put("R1", "neon-blue glow, z=25 - the biggest single-family outlier in the game",
    "assets/icons/potions/mana_surge.png")
put("R2", "cyan outlier", "assets/icons/potions/aegis_brew.png",
    "assets/icons/potions/chain_flask.png")
put("R2", "cosmic/galaxy register", "assets/icons/potions/insight_tonic.png")

# --- stat glyphs
put("R1", "a glowing CYAN runestone printed on every card AND in event body text - "
          "the most-repeated cyan intrusion in the game",
    "assets/icons/stats/cost_runestone.png")
put("R2", "pale cyan blade, asset-store gloss", "assets/icons/stats/atk_sword.png")
put("K", "gilt/crimson painted heart - on style", "assets/icons/stats/hp_heart.png")

# --- map / HUD icons
put("R1", "a literal emoji heart", "assets/icons/map/hud_heart_painted.png")
put("R1", "a modern chemistry flask", "assets/icons/map/hud_potion.png")
put("R1", "a DOLLAR SIGN in a medieval war game", "assets/icons/map/hud_gold.png")
put("R2", "cartoon bevel on a navy disc", "assets/icons/map/hud_potion_painted.png")
put("R2", "generic modern jewellery", "assets/icons/map/hud_relic.png")
put("R2", "a '?' in a hexagon - UI register, not a war device",
    "assets/icons/map/node_event.png")
put("D", "cartoon lemon coin with a cyan diamond; 0 references",
    "assets/icons/map/hud_gold_painted.png")

# --- keyword devices
put("R1", "same hourglass as exhaust.svg - two rules, one glyph at 18px",
    "assets/icons/keywords/mustering.svg")
put("R1", "a bare UI arrow", "assets/icons/keywords/charge.svg")
put("R1", "a bare UI chevron; also reads as charge's twin",
    "assets/icons/keywords/overrun.svg")
put("R2", "infographic register (figures + arrows)", "assets/icons/keywords/adj_buff.svg",
    "assets/icons/keywords/on_enter.svg")
put("R2", "modern optics reticle", "assets/icons/keywords/sniper.svg")
put("R2", "barbed wire - 19th century in a medieval war",
    "assets/icons/keywords/thorns.svg")
put("R2", "modern medical cross", "assets/icons/keywords/regenerate.svg")
put("R2", "emoji-register sad face", "assets/icons/keywords/poison.svg")
put("R2", "a question mark - UI, not a device", "assets/icons/keywords/retain.svg")
put("R2", "sparkles read as 'clean', not 'stunned'", "assets/icons/keywords/stunned.svg")

# --- game-icons
put("R2", "a modern shopfront with an awning", "assets/icons/game-icons/shop.svg")
put("R2", "a d20 - tabletop-RPG register", "assets/icons/game-icons/dice-twenty-faces-twenty.svg")

# --- generic pre-art root icons
put("R2", "flat white silhouette from the pre-art set, still loaded by GameTheme",
    "assets/icons/sword.png", "assets/icons/heart.png", "assets/icons/diamond.png",
    "assets/icons/fire.png")
put("D", "pre-art generic set, no live reference", "assets/icons/book.png",
    "assets/icons/campfire.png", "assets/icons/crown.png", "assets/icons/shield.png",
    "assets/icons/skull.png")

# ---------------------------------------------------------------- liveness
def live_map():
    """grep the shipped code once for every basename."""
    hay = ""
    for d in ("scripts", "scenes"):
        for r, _, fs in os.walk(os.path.join(ROOT, d)):
            for f in fs:
                if f.endswith((".gd", ".tscn")):
                    hay += open(os.path.join(r, f), encoding="utf-8", errors="replace").read()
    return hay


HAY = live_map()
CARD_IDS = set()
for db in ("CardDB", "RelicDB", "PotionDB", "EventDB", "EncounterDB", "HeroDB", "CardArtAliases"):
    p = os.path.join(ROOT, "scripts/data", db + ".gd")
    if os.path.exists(p):
        CARD_IDS |= set(re.findall(r'"([a-z0-9_\-]+)"', open(p, encoding="utf-8", errors="replace").read()))


def is_live(rel):
    base = os.path.basename(rel)
    stem = os.path.splitext(base)[0]
    if base in HAY or rel in HAY:
        return "live"
    # content families load by id, so the id appearing in a DB is the reference
    if rel.split("/")[1] in ("creatures", "spells", "events", "portraits") or "relics" in rel \
            or "potions" in rel or "keywords" in rel:
        if stem in CARD_IDS:
            return "live"
    if "%s" in HAY or "%d" in HAY:
        fam = os.path.dirname(rel).split("/")[-1]
        if fam in ("creatures", "spells", "relics", "potions", "keywords", "portraits", "events"):
            return "live?"
    return "DEAD"


# ---------------------------------------------------------------- assemble
rows = []
seen = set()
for fam in FAMILIES:
    d = os.path.join(ROOT, fam)
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        if not f.lower().endswith((".png", ".jpg", ".jpeg", ".svg", ".webp")):
            continue
        rel = f"{fam}/{f}"
        if rel in seen:
            continue
        seen.add(rel)
        g, why = V.get(rel, ("K", ""))
        # rule-based deletions: whole trees the shipped code never names
        if fam == "assets/frames":
            g, why = "D", "superseded v3 frame set - the live card is drawn by painters"
        elif fam == "assets/icons/downloaded":
            g, why = "D", "raw download dump (clip-art coins, emoji hearts, a (C) symbol)"
        elif fam == "assets/ui" and f != "card_back.png":
            g, why = "D", "superseded UI kit / AI test exports, 0 references"
        elif fam == "assets/icons/relics" and f.endswith(".svg"):
            g, why = "D", "redundant fallback - the painted .png always wins the loader"
        L = lint.get(rel, {})
        rows.append({
            "file": rel, "family": fam, "verdict": g, "reason": why,
            "live": is_live(rel),
            "cyan%": L.get("cyan", ""), "outlier": L.get("outlier", ""),
            "dup": L.get("dup", ""), "blocky%": L.get("blocky", ""),
            "tones": L.get("tones", ""),
        })

# the one file that must exist and does not
rows.append({"file": "assets/portraits/hero_silhouette_kindler.png", "family": "assets/portraits",
             "verdict": "R1", "reason": V["assets/portraits/hero_silhouette_kindler.png"][1],
             "live": "MISSING", "cyan%": "", "outlier": "", "dup": "", "blocky%": "", "tones": ""})

with open(os.path.join(SP, "verdicts.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

c = collections.Counter(r["verdict"] for r in rows)
print("TOTAL ROWS:", len(rows))
print("verdicts:", dict(c))
for fam in FAMILIES:
    fr = [r for r in rows if r["family"] == fam]
    if not fr:
        continue
    cc = collections.Counter(r["verdict"] for r in fr)
    print(f"  {fam:28s} n={len(fr):4d}  R1={cc['R1']:3d} R2={cc['R2']:3d} D={cc['D']:3d} K={cc['K']:3d}")
json.dump(rows, open(os.path.join(SP, "verdicts.json"), "w"), indent=1)
