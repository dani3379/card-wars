# MIDJOURNEY BATCH 4 — THE MISSING ART (2026-09-08)

Companion to [`ART_REPLACEMENT_SWEEP_20260908.md`](ART_REPLACEMENT_SWEEP_20260908.md).
**This doc only covers what has no prompt anywhere yet.** The sweep found 39 R1 replacements
and **33 of them are already prompted** in `MIDJOURNEY_ART_OVERHAUL_20260722.md` /
`MIDJOURNEY_ICON_REPLACEMENTS.md` — those are a *generate* job, not a *write* job. What was
genuinely missing:

- **§2 — the 25 relics with no icon file at all** (the highest-value art job in the project)
- **§3 — the 6 R1s with no prompt**
- **§4 — where Midjourney is the WRONG tool**, and why

## 1. Workflow — do this or the batch drifts

Generate **one** image you love, grab its `--sref` code, then append `--sref <code> --sw 100`
to every other prompt in the batch. `--sref` pins palette, light and finish — not subject.
Two or three references held together are more stable than one, because a pair averages toward
a house look instead of one image's quirks. **This is the whole fix for the cyan problem**: the
103 cool-cast assets in the set each drifted because each was generated alone.

`--oref` is **V7-only and did not carry into V8.1** — do not build on it. V8's character-lock
is `--cref`, which matters only for §3's portraits.

**Best anchor candidates already in the repo** (strongest, most on-style relic icons — use one
of these as the `--sref` image rather than inventing a new look):
`icons/relics/bone_hourglass.png` · `icons/relics/ember_crown.png` ·
`icons/relics/stalwarts_anvil.png` · `icons/relics/the_family.png`

**THE RELIC TAIL** — paste after every subject line in §2. Unchanged from the 2026-07-22 doc so
this batch matches the 129 icons already shipped:

```
stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

Note the tail already excludes `flat black background, empty void` — that is the fix for the
six shipped relics whose grounds are flat black while the family paints its grounds.

Save each as `assets/icons/relics/<id>.png`. **The id is the filename** — `RelicDB.get_icon`
resolves `res://assets/icons/relics/<id>.png` and nothing else. One id below does **not** match
its display name: `paymasters_tally` is shown to the player as *Paymaster's Coin*. File it under
the **id**.

---

## 2. The 25 relics with no icon

Each subject line is written from the relic's own rules text, so the picture teaches the
mechanic. Ordered by tier, because the `starting` set are hero doctrine relics — the player
sees those every single run.

### Doctrine relics (`tier: "starting"` — seen every run, do these first)

**`centurions_rule`** — *Centurion's Rule*
> The first friendly to survive a hit each round gains +1 HP this fight. One adjacent friendly does too.
```
a centurion's knotted vine-staff of office laid across a battered file-leader's shoulder-plate, the vine wood polished dark by decades of use, one fresh dent in the plate beside it, [RELIC TAIL]
```

**`chain_censer`** — *Chain Censer*
> Your first Doom detonation each round reduces adjacent friendly Doom timers by 1.
```
a heavy iron thurible swinging on three long chains, its pierced lid venting thick ember-lit funerary smoke that gutters sideways, chain links catching firelight, [RELIC TAIL]
```

**`cinder_crown`** — *Cinder Crown*
> The first damage spell you cast each round deals +1 damage.
```
a blackened iron circlet of burnt laurel leaves, each leaf-tip still holding a live orange coal, faint heat-shimmer rising from the band, [RELIC TAIL]
```

**`funeral_lantern`** — *Funeral Lantern*
> When the first friendly dies each round: its On-Death effect fires a second time.
```
a pierced-tin grave lantern with a guttering candle inside, casting a second lantern's worth of shadow-shapes on the wall behind it, black crepe knotted to the handle, [RELIC TAIL]
```

**`ledger_seal`** — *Ledger Seal*
> When the first friendly dies each round: a surviving friendly in its column gains +1/+1 this fight.
```
a brass seal-matrix pressed into a fat blob of blood-red wax on a muster roll, one name on the roll struck through in ink and the name below it circled, [RELIC TAIL]
```

**`marching_spurs`** — *Marching Spurs*
> The first friendly you relocate each round gets +1 ATK and Swift this round.
```
a pair of worn iron prick-spurs with cracked leather straps, road dust and dried mud still on the rowels, one strap trailing, [RELIC TAIL]
```

**`mirror_primer`** — *Mirror Primer*
> The first time you cast two differently named spells each round: draw 1.
```
a small brass-cornered spellbook lying open with a polished silver mirror-plate set into one page, the facing page's script reflected and doubled in it, warm candlelight, [RELIC TAIL]
```

**`rearward_horn`** — *Rearward Horn*
> The first creature you play in your back row each round gets +1 ATK and Swift this round.
```
a short curved signal-horn of blackened ox-horn with a battered bronze bell and a rear-guard's green cord, hung on a tent pole, [RELIC TAIL]
```

**`reserve_standard`** — *Reserve Standard*
> The first creature you play directly behind a friendly each round gains Shield.
```
a furled reserve banner still in its leather case, planted butt-first in trampled earth behind the line, one edge of dark cloth escaping the case, [RELIC TAIL]
```

**`war_bellows`** — *War Bellows*
> The first Doom creature you play each round gains +2/+2.
```
a great iron-bound forge bellows, its leather lungs half-compressed, blowing a gout of sparks and white heat out of the nozzle, [RELIC TAIL]
```

### Uncommon

**`familiars_quill`** — *The Familiar's Quill*
> When you play a Warlock: your next spell this turn costs 1 less.
```
a black crow-feather quill standing upright in a squat inkwell, the feather's barbs smoking faintly, a spilled ink-drop on the desk shaped like a small watching bird, [RELIC TAIL]
```

**`forlorn_hope`** — *Forlorn Hope*
> Your first creature each fight gains +1 ATK. Against a General or lord, it gains +2 ATK and Swift this round.
```
a single scaling ladder propped against a breached wall at dawn, one dropped helmet at its foot, the top rungs shot away, nobody on it yet, [RELIC TAIL]
```

**`head_money`** — *Head-Money*
> When a Stray kills an enemy creature: gain gold equal to its printed Command cost (max 10 gold per fight).
```
a bounty purse spilling coin onto a nailed-up warrant, a notched tally-stick across it counting the paid, [RELIC TAIL]
```

**`heads_on_pikes`** — *Heads on Pikes*
> Start of each fight: the highest-ATK enemy gets -1 ATK this fight for each General defeated this run.
```
three captured enemy helms jammed onto pike-points in a row against a smoky dusk sky, crests broken off, crows circling small and distant, [RELIC TAIL]
```

**`portcullis`** — *The Portcullis*
> Once per round, while a friendly Bastion is in play, prevent the first 2 face damage you would take.
```
a massive iron portcullis dropped and seated in its stone groove, spear-points of the grille bitten into the flagstones, torchlight raking the bars from behind, [RELIC TAIL]
```

**`powder_horn`** — *Powder Horn*
> Banking Command adds 1 powder charge (max 3). Your next damage spell spends all charges for +2 damage each.
```
a scrimshawed ox-horn powder flask with a brass measure-spout, three measured charges poured out in a neat row beside it, one loose grain catching a spark, [RELIC TAIL]
```

**`second_rank`** — *The Second Rank*
> When you play a Soldier directly behind another Soldier: both gain +1/+1 this fight.
```
two spear-butts planted in the earth one directly behind the other, the rear spear's shaft crossed and lashed to the front one with cord, greaves and mud below, [RELIC TAIL]
```

### Rare

**`cerecloth`** — *The Cerecloth*
> Your first creature each fight copies the newest fallen creature's printed keywords. If none, it gains +1/+1.
```
a waxed linen burial shroud drawn back from an empty bier, the cloth still holding the hollow impression of the body that was wrapped in it, [RELIC TAIL]
```

**`drill_book`** — *The Drill Book*
> Your creatures earn their name and war school at 2 kills instead of 3, and their tribe doctrine at 7 instead of 10.
```
a small thumb-worn drill manual open on a camp drum, its diagrams of footwork and pike-angles inked in the margins, a stub of chalk resting on the page, [RELIC TAIL]
```

**`old_meg`** — *Old Meg*
> Once per round, a targeted damage spell also deals 2 to the other enemy in that column, or face if empty.
```
a huge stubby siege bombard on a timber bed, hoop-and-stave iron barrel bound with heavy rings, muzzle blackened, a stone shot at its wheel, named in the soldiers' way, [RELIC TAIL]
```

**`sextons_spade`** — *The Sexton's Spade*
> The first friendly Doom creature to detonate each fight detonates twice.
```
a sexton's iron-shod grave spade driven upright into fresh turned earth, two open graves behind it instead of one, lantern light low across the soil, [RELIC TAIL]
```

### Boss

**`articles_of_war`** — *The Articles of War*
> Choose a tribe. Its creatures cost 1 less (minimum 1).
```
a nailed-up broadsheet of army regulations on a post, wax seals and ribbons hanging heavy from its foot, one clause slashed through with a knife, torchlight, [RELIC TAIL]
```

### Event relics (`tier: "event"` — granted by name, never rolled)

**`eagle_of_the_fourth`** — *The Eagle of the Fourth*
> The first friendly creature that dies each fight returns as a 1/1.
```
a battered bronze legionary eagle standard, one wing bent, lifted out of the mud by an unseen hand, the numeral IV worn almost smooth on its plinth, [RELIC TAIL]
```
*Canon note: the Fourth Legion is the shared-world anchor the Old King never paid — see the
Bone Pit and the clerk's strongbox IV. Keep the eagle poor, old and never-relieved, not gilded.*

**`paymasters_tally`** — *Paymaster's Coin* — **file as `paymasters_tally.png`**
> At the start of every fight: gain 12 gold.
```
a single worn pay-token coin rubbed smooth of its device, held on a paymaster's split tally-stick over an open strongbox of coin, [RELIC TAIL]
```
*Use the Old King's coinage the props already establish: heads a crowned profile, tails crossed
pikes, this one worn smooth. Matches `CoinProp`'s `worn` face.*

**`sunken_road_stone`** — *The Sunken Road Stone*
> The first creature you play each round gains Armored.
```
a squat lichen-crusted boundary stone half-sunk into a rutted hollow way, cart-ruts worn deep on both sides of it, mist pooling in the cut, [RELIC TAIL]
```

---

## 3. The 6 R1 replacements with no prompt yet

**`creatures/stray_cat.png`** — currently a smiling cartoon kitten; the loudest tone break in
the pool. The card is a Stray (the masterless — rogues, mercs, larceny), so lean thief, not pet.
```
a lean scarred camp cat crouched on a broken wall with a stolen strip of meat in its jaws, one ear torn, eyes catching torchlight from below, a soldier's abandoned kit behind it, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, cute, kitten, chibi, big eyes, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`portraits/enemy_commander.png`** — currently black + neon magenta, reads like another game.
```
a grim enemy field commander seen close and frontal, dented dark plate over a red-brown campaign cloak, visor raised on a hard weathered face, a marshal's baton held across the chest, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, magenta, pink, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**`portraits/hero_portrait_pyromancer.png`** — currently the only anime face in the game.
**Generate this one twice**, once per house look, and let it settle §8 of the sweep — this is
the cheapest possible way to decide the portrait question with real images instead of argument.
```
a hooded pyromancer hero, hood back and face lit hard from below by the fire cupped in one bare hand, soot-marked cheekbones, a burn-scarred jaw, weathered adult features, dark-fantasy character portrait, single figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, anime, manga, big eyes, chibi, cute, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**`icons/map/hud_potion.png`** — currently a modern chemistry flask. Renders at 20px in event
text, and its sibling `hud_gold_coin.png` proves a painted object survives that size **if it is
one bold silhouette**. Keep it a single stubby bottle, no props.
```
a single stubby corked campaign flask of thick green-brown glass, one bold clear silhouette, a leather cord at the neck, warm firelit sheen on the shoulder of the bottle, stylized fantasy game icon, Darkest Dungeon and Slay the Spire style, bold brushstrokes, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, laboratory, science, erlenmeyer, photograph, 3d render, cgi, realistic, flat black background, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`icons/keywords/mustering.svg` and `icons/keywords/overrun.svg`** — see §4. **Do not generate
these.** They are 18px single-path silhouettes and Midjourney is the wrong tool.

---

## 4. Where Midjourney is the WRONG tool — and why

Using MJ "as much as it makes sense" has one hard boundary in this codebase, and it is already
written down in CLAUDE.md: **painted icons mush below ~20px.** That is why
`KeywordEffects.INLINE_KEYWORD_STAMPS` is switched OFF to this day — it is waiting for "flat
bold silhouettes", not paintings.

**Keep as flat single-path SVG silhouettes (game-icons.net, CC BY 3.0, already credited):**

- **All 28 `assets/icons/keywords/*.svg`.** They draw at ~18px on the card rail and the rail
  **tints them** — transient statuses render tinted ahead of the gilt printed keywords. A tint
  needs a single flat `fill="#fff"` path; a painting cannot be recoloured that way. `GameTheme.
  _load_keyword_icons()` is an explicit allow-list of exactly this format.
  The three R1 fixes here are **downloads, not generations**:
  - `mustering.svg` — currently the same hourglass as `exhaust.svg`, inverted. Two rules, one
    glyph. Take something that reads *forming up*, not *time passing*.
  - `charge.svg` (a bare `→`) and `overrun.svg` (a bare `»`) — UI arrows, and twins of each
    other. Both want a weapon/impact silhouette instead.
  - Lower priority, same route: `sniper` (a modern optics reticle), `thorns` (barbed wire —
    19th century), `regenerate` (a medical cross), `poison` (an emoji sad face), `retain` (a
    question mark), `adj_buff` + `on_enter` (infographic figures and arrows).
- **`assets/icons/game-icons/shop.svg`** — a modern awninged shopfront; the sutler is a tent.
  And **`dice-twenty-faces-twenty.svg`** — a d20 is tabletop-RPG register.
- **`assets/icons/map/node_*.png`** — the war-table map draws its own medallions procedurally
  (`_draw_medallion`), so these are chrome, not art.

**Painted (MJ) is right for everything else**, because everything else renders at 46px or
larger: relic icons at `ICON_PX := 46` and up to `SPOIL_ICON_PX := 160`, potions, the 20px
event-text glyphs that are single bold objects, and every card, portrait, event and background.

---

## 5. Checklist after the files land

1. Drop each PNG at the exact path given. Run a headless `--import`.
2. `Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" res://tools/_probe_parsecheck.tscn`
   (only if any `.gd` changed — pure art drops do not need it).
3. `python tools/art_lint.py --baseline` — new offenders fail; a fix that lands cleanly should
   leave the baseline green. Re-`--bless` deliberately.
4. `python tools/_art_sweep_20260908.py` — rebuilds the verdict table so the 25 absences drop
   out of the count.
5. Consider a `_probe_relic_art` on the model of `_probe_card_art.tscn`, so relic id → icon is
   gated and the next missing 25 fails a probe instead of needing a human to look.
