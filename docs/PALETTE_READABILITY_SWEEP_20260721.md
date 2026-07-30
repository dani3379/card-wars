# Palette & readability sweep — 2026-07-21

Follow-on to [`SCREEN_AUDIT_20260721.md`](SCREEN_AUDIT_20260721.md). A static
sweep of `scripts/` for two problem classes the screen audit could only catch
where it happened to look:

- **Class A** — off-palette saturated cool colors in UI chrome.
- **Class B** — reading text in the **14–17px band**, which no probe polices
  (`tools/_probe_text_floor.gd` only fails below 14).

32 genuine hits: 16 in each class.

---

## Class A — off-palette saturated cool colors

| # | file:line | literal | element | recommendation |
|---|---|---|---|---|
| 1 | `Combat.gd:11946` | `Color(0.18, 0.30, 0.14)` | `CONFIRM` on the in-combat card-picker overlay | Same olive-green commit tile the skirmish screens just lost. → ember `Color(0.34, 0.22, 0.08)`. |
| 2 | `Combat.gd:12810` | `Color(0.18, 0.30, 0.14)` | pick button under each card in the choose-a-card overlay | As #1. Fires on every scry / tutor / discover, so it is the most-seen of the three. |
| 3 | `Combat.gd:12373` | `Color(0.18, 0.30, 0.14)` | `Keep on Top` in the top-of-deck overlay | Sibling `Send to Bottom` (12380) is warm. The pair currently reads as a green/red traffic light; make it ember/oxblood. |
| 4 | `NetConstructed.gd:138` | `Color(0.18, 0.30, 0.22)` | `SAVE` deck button | The one surviving green on the skirmish screens — every sibling in its row is warm. |
| 5 | `Combat.gd:12167` | `Color(0.30, 0.85, 0.45, 0.9)` | 4px "move here" slot border | The comment justifies *distinctness* from the red border, not the hue. Verdigris keeps the distinction in-palette. |
| 6 | `Combat.gd:13278` | `Color(0.40, 0.95, 0.45)` | `HEAL` enemy-intent label | `GameTheme.HEALTH_GREEN` carries a comment saying electric `#40D959` was retuned to sage. This literal is the rejected value, reinstated by hand. Route through the constant. |
| 7 | `Combat.gd:4804` | `Color(0.40, 0.95, 0.45)` | `+N` heal floater | Same bypass as #6, on the highest-frequency status text in the game. |
| 8 | `Treasure.gd:53` | `Color(0.20, 0.38, 0.24)` | `Take Provisions` tile | Its two siblings are ember and gilt; the green is the only cool tile on the screen. |
| 9 | `Event.gd:7961` | `Color(0.60, 0.74, 0.82)` | `◄ L` marker in the scales minigame | Its mirror `R ►` (7964) is gilt. A symmetric two-sided device with one side off-palette. |
| 10 | `Rest.gd:1035–1036` | `Color(0.30, 0.95, 0.40, 0.55)` | halo behind the upgraded-card preview | Contradicts the screen's own declared accent — `Rest.gd:123` sets `_accent_upgrade = GameTheme.KEYWORD_GOLD`. The forge is gilt everywhere except its own hero moment. |
| 11 | `Rest.gd:804` | `Color(0.55, 0.95, 0.55, 0.85)` | post-forge particle burst | Same inconsistency, same screen, same beat. |
| 12 | `Event.gd:458` | `Color(0.55, 0.88, 0.55)` | HP-gain flash on the event ledger | Paired against the house oxblood for loss; only the gain side is off-constant. → `HEALTH_GREEN`. |
| 13 | `Combat.gd:22476`, `:22720` | `Color(0.70, 0.78, 0.92)` | `NO FACE DAMAGE` callout / shield-break chip | The only cool entry in an otherwise all-warm forecast ramp. Bone says "nothing happened" without leaving the world. |
| 14 | `MapView.gd:1098–1099` | `Color(0.55, 0.85, 0.55)`, `Color(0.55, 0.70, 0.95)` | `Creatures: N` / `Spells: N` on the deck stats bar | Not a tribe color, not a rarity. An ad-hoc pair beside gilt and ash siblings. |
| 15 | `MapView.gd:1109` | `Color(0.40, 0.75, 0.95)` | `Uncommon: N` count | Rarity IS identity, but the constant `RARITY_UNCOMMON` is deliberately muted away from digital cornflower per its own comment. This literal is brighter. Use the constant. |
| 16 | `GameOver.gd:26` | `Color(0.22, 0.37, 0.16)` | `INK_LAUREL`, the fastest-march line | The only cool ink in an otherwise bronze/gold/rubric/oxblood block. Heraldic laurel is defensible — flagged for a decision, not as a defect. |

## Class B — readability-floor bypasses (14–17px)

| # | file:line | size | element | recommendation |
|---|---|---|---|---|
| 1 | `GameTheme.gd:3509` | 14 | description under every option in `show_option_picker` | **Worst hit in either class.** Autowrapped prose that is the whole basis for a modal decision, at 14px, while its own button label above is 18 — the hierarchy is inverted. Used by Totem Pole, Bone Hourglass, Treasure and the combat pay-choices. |
| 2 | `SettingsOverlay.gd:1280` | 15 | `_make_row_label` — the name of **every** settings row | 14 call sites incl. `Color Blind Mode`. Interactive labels → ≥18. The accessibility rows are themselves sub-floor. |
| 3 | `Event.gd:9318` | 14 | the posted drill in the morris minigame | Two lines of rules needed to beat the opponent, in dim ink. §11 names minigame aids explicitly: the honesty promise dies if the honest text can't be read. |
| 4 | `Event.gd:5484` | 14 | race-name chips on the lane pick buttons | These *are* the interactive labels — the only thing telling one clickable lane from another. |
| 5 | `Event.gd:6585` | 14 | `VENUS PAYS DOUBLE` payout rule on the tali slate | Rules text at 14/α0.75, while its own slate header is 15 — one device disagreeing with itself. |
| 6 | `Event.gd:6577` | 14 | tali rank names (payout rows) | The rows the player reads to evaluate a throw. |
| 7 | `Rest.gd:539` | 15 | `Fell at %s — Act %d, round %d` in the Hold a Wake picker | Prose, in the dimmest ink, in the picker where you choose which of the fallen to raise. |
| 8 | `Rest.gd:543` | 15 | `Rises at %d/%d` | The stat line the choice actually turns on. |
| 9 | `EventChoiceDevice.gd:200` | 15 | lock-reason note under a locked choice | Autowrapped prose explaining why an option is unavailable. |
| 10 | `Event.gd:9308` | 14 | live clock/state readout in morris | A caption stating live state: 15–16, never below. |
| 11 | `SettingsOverlay.gd:583`, `:1189` | 14 | `%d%%` slider readouts | Numerals, but bare labels in a row — not fitted inside a drawn object, so the fitted exemption does not apply. |
| 12 | `NetLobby.gd:1187, 1207, 1221, 1299, 1316, 1329` | 14 | `MODE` / `FORMAT` / `BATTLE STYLE` headers | Genuine caption chips, but a full step below the band floor. |
| 13 | `NetLobby.gd:339` | 14 | panel section header | As #12. |
| 14 | `NetDeckBuilder.gd:573` | 14 | `— TAKE IT —` under a card tile | An action prompt, not a marker. |
| 15 | `NetDeckBuilder.gd:276` | 15 | saved-deck `OptionButton` | Interactive control text at the caption floor. |
| 16 | `NetDeckBuilder.gd:251` | 15 | deck-name `LineEdit` | Text the player types and re-reads. |

---

## False positives considered and rejected

Recorded so the next reader knows what was deliberately *not* flagged.

**The big one — `MainMenu.gd:241, 247, 255, 261`.** These pass elaborate greens
and blues to `NEW RUN` / `LOAD GAME` / `SKIRMISH` / `COLLECTION` and look like
the worst hits in the codebase. They are not: `_make_menu_button(text, _bg:
Color, ...)` at `MainMenu.gd:390` prefixes the parameter with an underscore —
**the color is a dead argument and never reaches a pixel.** That is why the main
menu scored 9 on palette. Not a defect, but a live trap: eight call sites pass a
meaningful-looking color that does nothing, and anyone retheming that screen
will change them and see no result.

**Identity systems (all deliberate, all documented at their definition):**
Command/mana navy (`NetDraft.gd:469`, `NetDeckBuilder.gd:161–167`,
`Collection.gd:471`, `Combat.gd:18342`); `TRIBE_COLORS` and `CTYPE_COLORS`;
rarity metals (`GameTheme.gd:2088–2115`, `Motion.gd:843`); keyword-device tints
(`Combat.gd:12613–12618`, `:12440`, `:20624–20632`); potion colors
(`Shop.gd:260` ← `PotionDB`); map medallion enamels (`MapTerrain.gd:3064–3097`,
whose comment documents shop-green as deliberate wayfinding away from treasure
gold); spell purple/blue (`Combat.gd:14168`, `Wayside.gd:387`, `Event.gd:2830`);
the palette constants themselves, each carrying its own retune rationale.

**Painters coloring physical props** — `CandleStub` flame core, `MerelsBoard`
felt, `StationMark` wash. Stated exception.

**Verdigris** (`Event.gd:333`, `:7468`, `EventChoiceDevice.gd:6–7`,
`NetLobby.gd:22`, `NetDeckBuilder.gd:37`, `CombatNet.gd:4819`) — in-palette.

**Deliberate semantic pairs** — `MainMenu.gd:2495`, the blessing screen's
"honest" tile paired against wine for "priced", with a comment saying so.
`Rest.gd:125`, "spectral bone-blue" for Hold a Wake — a deliberate ghost tint,
pale enough not to read as web-blue.

**Class B legal-band leaves** — `Event.gd:6980, 7272, 7587, 7893, 8321, 8737`
(minigame ledgers/log rows at 15) and `Event.gd:6492, 6528, 6558` (one-breath
captions riding a bigger device) sit legally at 15, though with no headroom.
Fitted numerals inside drawn seals and gems (`NetDraft.gd:466`,
`Combat.gd:15483`, `NetLobby.gd:404`) are the free-sized register.
`SettingsOverlay.gd:965`, the GPU info line, is correctly subordinate.

---

## Why the 14–17 band needs its own gate

`SettingsOverlay.gd:1280` is the instructive case. The screen audit scored
Settings **9/9 on legibility** from a rendered frame — and every row name on it
is 15px, including `Color Blind Mode`. It looks fine at 1080p on a desk monitor
and is sub-floor at the 1600×900 canvas §11 says to size for. A screenshot
cannot catch this class; only a source gate can. `_probe_text_floor` should
grow a second, warning-level band for worded text at 14–17 outside the caption
register.
