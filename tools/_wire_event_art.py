"""Map staging/ Midjourney event art to assets/events/<event_key>.png.

Same approach as _wire_spell_art.py — match the MJ filename prefix to the
event key, then copy into place with the canonical name. Event.gd's
_load_event_image() auto-discovers <key>.png at runtime, no wiring needed.
"""

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / "staging"
TARGET = ROOT / "assets" / "events"

# Map: (unique prefix from MJ filename) -> event key
MAPPING = {
	"A_weathered_medieval_blacksmiths_forge":             "blacksmith_offer",
	"An_ancient_stone_fountain_in_moonlight":             "blood_fountain",
	"A_hooded_cloaked_figure_seen_from_behind":           "collector_event",
	"A_massive_black_stone_altar":                        "dark_altar",
	"A_worn_wooden_gambling_table":                       "gambler",
	"A_solitary_hermits_wagon":                           "hermit",
	"A_grim_medieval_butchers_shop":                      "butcher",
	"An_ancient_stone_shrine_half-overgrown":             "mysterious_shrine",
	"A_bubbling_natural_spring_rising":                   "thrice_blessed_spring",
	"A_pawnbrokers_shop_window":                          "pawnbrokers_window",
	"An_overgrown_apiary_at_twilight":                    "beekeeper",
	"An_empty_wicker_cradle":                             "burning_cradle",
	"A_small_forest_clearing_at_dawn":                    "woodcutter",
	"A_small_bonfire_pyre":                               "char_widow",
	"An_open_empty_grave_dug":                            "gravesong_choir",
	"A_small_delicate_cat_figurine":                      "glass_familiar",
	"A_worn_wooden_scribes_desk":                         "spellwrights_pact",
}


def main() -> None:
	mj_files = sorted(STAGING.glob("dani3379_*.png"))

	resolved: dict[str, Path] = {}
	for f in mj_files:
		stem = f.stem.removeprefix("dani3379_")
		for prefix, event_key in MAPPING.items():
			if stem.startswith(prefix):
				if event_key not in resolved:
					resolved[event_key] = f
				break

	missing = sorted(set(MAPPING.values()) - set(resolved.keys()))
	print(f"Matched: {len(resolved)} / {len(MAPPING)}")
	if missing:
		print("Missing event art (no MJ file matched):")
		for e in missing:
			print(f"  - {e}")
		print("\nABORTING.")
		return

	for event_key, src in resolved.items():
		dst = TARGET / f"{event_key}.png"
		dst_import = TARGET / f"{event_key}.png.import"
		shutil.copyfile(src, dst)
		if dst_import.exists():
			dst_import.unlink()
		print(f"  {event_key:24s} <- {src.name}")

	print(f"\nWrote {len(resolved)} event PNGs to {TARGET}.")
	print("Deleted .import files — Godot will re-import on next editor launch.")


if __name__ == "__main__":
	main()
