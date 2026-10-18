# Snapshot and asset provenance

This copy was curated from `BurningMeadow_Clean_VERIFIED-003.rar`. Its transfer notes identify the authoritative working snapshot as 6 October 2026, including uncommitted changes. The archived source and recovery material were left unchanged. This copy is a snapshot, not a reconstruction of the earlier public repository's history.

## Included and excluded material

Runtime scripts, scenes, required assets, selected development documentation/probes, and attribution/license records are retained. The bundled engine, Git history bundle, personal save/settings archive, transfer launchers, reference screenshots from other games, frame-work experiments, and original asset-pack ZIPs are excluded.

The original code did not carry a clearly established project-wide license in the recovered snapshot. No replacement license, author identity, or ownership assertion has been invented. The project owner must resolve the appropriate code publication/license terms and confirm the origin of any borrowed code or commissioned material.

## Third-party and image records

The source's notices are retained in:

- `CREDITS.md`
- `THIRD_PARTY_LICENSES.txt`
- `assets/audio/SFX_CREDITS.md`
- `assets/audio/music/MUSIC_CREDITS.md`

Two additional paths named by the old notice, `assets/spells/painterly-3/README.txt`
and `assets/spells/painterly-4/README.txt`, are absent from both this copy and the
recovered original. The prior source attribution was preserved and the misleading
“bundled notice” statements were corrected. The missing pack records must be
reconciled with the actual included spell images before distribution.

These records identify CC0/CC BY icon, sound, and music sources and font license information. They also describe adaptations of fine-art reproductions. This preparation checked the local presence of notice files; it did not independently establish the provenance or redistribution rights of every image, reproduction, sound, or font.

In particular, the old credits referred to a missing “Bespoke art” section. That dangling reference was replaced with an explicit pointer to this limitation. The origin/author/tool/source and applicable permission for each otherwise-unmapped painted asset still need to be recorded. A generic label such as “bespoke” or “public domain” does not supply that missing per-file record.

Keep all specific credit records and the in-game Credits screen. The engine's notice in `THIRD_PARTY_LICENSES.txt` describes Godot; it is not a license for this game's original code or every included asset.

## Preparation changes

This pass adds a current English README, ignore rules, provenance/validation notes, repairs dangling/missing credit references, and changes the selected PowerShell probe runner to start hidden child processes on Windows. It makes no combat, campaign, balance, networking, or other gameplay changes.
