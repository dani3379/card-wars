"""Map staging/ Midjourney spell art to assets/spells/<id>.png.

Each MJ filename starts with the prompt text. We match the unique prefix
of each MJ filename to the spell ID, then copy the file into place with
the canonical name. Existing .import files are deleted so Godot re-imports
the new file cleanly on next editor launch.
"""

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / "staging"
TARGET = ROOT / "assets" / "spells"

# Map: (unique prefix from MJ filename) -> spell ID
MAPPING = {
	"A_curved_arc_of_pure_red_kinetic_force":              "strike",
	"A_floating_orb_of_churning_flame_and_crackling":      "fireball",
	"A_withered_black_hex-sigil_floating":                 "curse",
	"A_clean_precise_arc_of_silver-white":                 "slash",
	"A_translucent_hexagonal_barrier-dome":                "shield_wall",
	"Concentric_red_shockwave_rings":                      "war_cry",
	"An_unfurled_glowing_scroll":                          "provision",
	"A_glowing_golden_orb_of_healing":                     "patch_up",
	"A_focused_dart_of_fire_shaped":                       "flame_bolt",
	"A_radial_pushback_force_ripple":                      "shove",
	"Three_glowing_playing_cards":                         "gambit",
	"A_single_crimson_blood_droplet":                      "blood_tithe",
	"A_forward-rushing_streak_of_red":                     "reckless_charge",
	"A_streak_of_green-yellow_energy":                     "quick_shot",
	"A_burst_of_bright_orange_sparks":                     "scrap",
	"A_horizontal_wall_of_stacked_translucent":            "barricade",
	"A_pulsing_red_heart-shaped_aura":                     "adrenaline",
	"A_swirling_deep-blue_arcane_mandala":                 "concentrate",
	"A_massive_vertical_pillar_of_blinding":               "smite_spell",
	"A_radiant_golden_sunburst_aura":                      "inspire",
	"Multiple_sharp_dagger-shaped_shadow-spikes":          "ambush",
	"An_upward_spiral_of_emerald":                         "second_wind",
	"Two_glowing_orbs_of_blue_and_amber":                  "reposition",
	"A_jagged_white-blue_bolt_of_lightning":               "lightning",
	"A_hovering_mana_crystal_at_the_top":                  "offering",
	"A_floating_sigil_of_glowing_bone-white":              "grave_pact",
	"A_towering_spectral_column_of_green-tinged":          "fuel_the_pyre",
	"Concentric_golden_soundwave_rings":                   "battle_hymn",
	"A_burst_of_gold_coins":                               "pillage",
	"Three_concentric_ring-ripples":                       "echo_spell",
	"A_floating_chalice_of_swirling_crimson":              "bloodletting",
	"A_cracked_floating_red_mana_crystal":                 "turbo",
	"A_burning_glowing_card_dissolving":                   "recycle",
	"Radial_jagged_cracks_of_glowing_orange":              "earthquake",
	"A_regal_golden_command-sigil":                        "kings_command",
	"A_floating_black_contract_scroll":                    "unholy_bargain",
	"Multiple_withered_skeletal_hands":                    "mass_grave",
	"A_glowing_pentagram_sigil":                           "dark_pact",
	"Radiating_golden_soundwave_rings":                    "war_chant",
	"A_single_skeletal_hand_reaching":                     "grave_robbery",
	"A_colossal_jagged_rift":                              "cataclysm",
	"Two_glowing_orbs_of_light_suspended":                 "soul_swap",
	"A_panoramic_sky_filled_with_falling":                 "apocalypse",
	"A_brilliant_gold-white_starburst":                    "lay_on_hands",
	"Soft_warm_golden_sunrays":                            "mending_light",
	"A_swirling_vortex_of_pure_white-blue":                "banish",
	"An_immense_ornate_floating_pocket-watch":             "time_snare",
	"A_descending_blade-shape_of_pure_gold-white":         "holy_smite",
	"A_towering_wall_of_churning_hellfire":                "inferno",
	"A_colossal_descending_shockwave":                     "overwhelming_force",
}


def main() -> None:
	mj_files = sorted(STAGING.glob("dani3379_*.png"))
	# Skip the Game_relic icons — those belong to a different pipeline.
	mj_files = [f for f in mj_files if "Game_relic" not in f.name]

	resolved: dict[str, Path] = {}
	unmatched_files: list[Path] = []

	for f in mj_files:
		# MJ filename: dani3379_<prompt_prefix>_<uuid>_<variant>.png
		# We strip the dani3379_ prefix and match the first part against keys.
		stem = f.stem.removeprefix("dani3379_")
		hit = None
		for prefix, spell_id in MAPPING.items():
			if stem.startswith(prefix):
				hit = spell_id
				break
		if hit is None:
			unmatched_files.append(f)
		elif hit in resolved:
			print(f"[DUPLICATE] {hit} already mapped to {resolved[hit].name},"
				  f" skipping {f.name}")
		else:
			resolved[hit] = f

	missing_spells = sorted(set(MAPPING.values()) - set(resolved.keys()))

	print(f"Matched: {len(resolved)} / {len(MAPPING)}")
	if missing_spells:
		print("Missing spells (no MJ file matched):")
		for s in missing_spells:
			print(f"  - {s}")
	if unmatched_files:
		print("Unmatched MJ files (no spell prefix matched):")
		for f in unmatched_files:
			print(f"  - {f.name}")

	if missing_spells or unmatched_files:
		print("\nABORTING — fix the mapping or staging first.")
		return

	# Copy each MJ file into place, and delete old .import so Godot re-imports.
	for spell_id, src in resolved.items():
		dst = TARGET / f"{spell_id}.png"
		dst_import = TARGET / f"{spell_id}.png.import"
		shutil.copyfile(src, dst)
		if dst_import.exists():
			dst_import.unlink()
		print(f"  {spell_id:24s} <- {src.name}")

	print(f"\nWrote {len(resolved)} spell PNGs to {TARGET}.")
	print("Deleted .import files — Godot will re-import on next editor launch.")


if __name__ == "__main__":
	main()
