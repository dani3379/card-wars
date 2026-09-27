extends Node

# ── Fonts ──
var font_display: Font = null   # Kreon Bold — card names, type, FLOOP, buttons/titles
var font_stat: Font = null      # Kreon 700 — cost, ATK, HP numerals
var font_body: Font = null      # Inter 850 — UI/menu/HUD/tooltip body
var font_body_bold: Font = null # Inter 900 — keyword [b] tags in UI body
var font_title: Font = null       # Kreon Bold — combat HUD headers/captions (NOT cards)
var font_title_black: Font = null # Kreon 700 — combat HUD numerals (HP/mana/counts)
var font_card_body: Font = null      # Kreon 500 — card rules text (the writ's book hand)
var font_card_body_bold: Font = null # Kreon 700 — keyword [b] tags on the card page

# ── Textures ──
var tex_icon_sword: Texture2D = null
var tex_icon_heart: Texture2D = null
var tex_icon_diamond: Texture2D = null

# ── Slay-the-Spire-style silhouette map node icons (Kenney CC0 board-game-icons). ──
var tex_node_combat: Texture2D = null
var tex_node_elite: Texture2D = null
var tex_node_rest: Texture2D = null
var tex_node_shop: Texture2D = null
var tex_node_event: Texture2D = null
var tex_node_boss: Texture2D = null
var tex_node_treasure: Texture2D = null
var tex_node_recruit: Texture2D = null
var tex_node_wayside: Texture2D = null

# ── HUD silhouettes (Kenney CC0). ──
var tex_hud_heart: Texture2D = null
var tex_hud_gold: Texture2D = null
var tex_hud_potion: Texture2D = null
var tex_hud_relic: Texture2D = null
var tex_hud_deck: Texture2D = null

# ── NinePatch panel textures (Kenney Fantasy UI Borders CC0) ──
var tex_panel_9p: Texture2D = null

# ── Card surface depth textures (built procedurally at load). ──
# Tiled paper grain + vertical light/shadow gradients used by Card2D to give
# the procedural card body real surface depth instead of a flat fill. Without
# these the card reads as a flat-colored rectangle; with them it reads as
# parchment in directional light (Slay-the-Spire surface convention).
# Custom CanvasItem shaders gave better results but the GL Compatibility
# renderer choked on them (see commit be8ef2d) — depth now comes from baked
# NoiseTexture2D + GradientTexture2D overlays which the GL compat path handles
# as plain textures without any shader compilation.
var tex_card_grain: Texture2D = null
var tex_card_wood_grain: Texture2D = null  # anisotropic — horizontal stripes
var tex_card_top_light: Texture2D = null
var tex_card_bottom_shade: Texture2D = null
var tex_card_vignette: Texture2D = null
# Noise-perturbed inner border darkening — breaks the smooth vignette ring
# into brush-stroke-irregular edges so the card reads as ink-wash on
# parchment instead of "rectangle with darkened corners". See section 5 of
# _build_card_surface_textures for the bake.
var tex_card_brush_edge: Texture2D = null

# Keyword name -> Texture2D for the medallion strip.
var _keyword_icons: Dictionary = {}

func _ready() -> void:
	_load_assets()
	_apply_root_theme()
	_install_press_feedback()


func _apply_root_theme() -> void:
	# Native tooltips (every plain `tooltip_text` — relic chips, seals, shop
	# wares) rendered with the engine's stock theme: thin grey default font on
	# a light panel, the smallest and most off-brand text in the game. Restyle
	# them at the window root so they speak the house voice. The theme defines
	# ONLY tooltip entries + a default font — every control with explicit
	# overrides (i.e. all GameTheme-built UI) is untouched.
	var th := Theme.new()
	if font_body != null:
		th.default_font = font_body
		th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 18)
	th.set_color("font_color", "TooltipLabel", IVORY)
	var panel := make_panel_style(Color(0.07, 0.056, 0.046, 0.98),
		Color(0.60, 0.51, 0.34, 0.95), 1, 4, true)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	th.set_stylebox("panel", "TooltipPanel", panel)
	var win := get_window()
	if win != null:
		win.theme = th

func _load_assets() -> void:
	# Font roster (the "Chronicle" pass, 2026-06-29) is loaded below. The eight
	# font_* slots map onto three OFL faces — Marcellus (display), Kreon (cards +
	# numerals), Inter (UI) — see the block comment at the loads for the full mapping
	# and rationale. Two load gotchas worth keeping:
	#   - CACHE_MODE_IGNORE on every ResourceLoader.load: bug godotengine/godot#92778
	#     hands back a stale pre-MSDF FontFile from the resource cache after a reimport.
	#   - If a face ever fails to load from an un-imported .ttf, FontFile.new() +
	#     load_dynamic_font(path) is the runtime fallback (NOT FontFile.data = bytes,
	#     which is .tres-only and silently renders nothing).
	# === FONT ROSTER — "Chronicle" pass (2026-06-29) ===
	# Kreon     → EVERYTHING but UI body: display (titles/banners/card names/buttons),
	#             card rules text, and every stat numeral. Replaced Marcellus as the
	#             display face 2026-06-29 — Marcellus's inscriptional hairlines stayed
	#             thin at any weight; Kreon's low-contrast slab reads reliably fat.
	#             (Marcellus is still loaded below only as a vestigial fallback.)
	# Inter     → UI / menu / HUD / tooltip body.
	# Supersedes Lilita One (cute/rounded, clogged counters at small sizes), Cinzel
	# (thin all-caps, hard small), Nunito (soft/casual) and Alegreya (hairline serifs
	# thinned on the parchment). All three are OFL. MSDF is ON for the Control-scaled
	# card faces (Marcellus/Kreon, msdf_size 64); Inter stays RASTER (UI is drawn at
	# viewport scale, which Godot oversampling already covers) to dodge the
	# see-through-small-text MSDF failure that pushed Nunito back to raster.
	# CACHE_MODE_IGNORE on every load — bug godotengine/godot#92778 hands back stale
	# pre-MSDF FontFiles from the resource cache after a reimport.
	var inter := ResourceLoader.load("res://assets/fonts/Inter-Variable.ttf",
		"FontFile", ResourceLoader.CACHE_MODE_IGNORE) as FontFile
	var marcellus := ResourceLoader.load("res://assets/fonts/Marcellus-Regular.ttf",
		"FontFile", ResourceLoader.CACHE_MODE_IGNORE) as FontFile
	var kreon := ResourceLoader.load("res://assets/fonts/Kreon-Variable.ttf",
		"FontFile", ResourceLoader.CACHE_MODE_IGNORE) as FontFile
	# Nunito stays loaded ONLY as the universal last-resort glyph fallback (arrows,
	# stars, geometric shapes the text faces lack — these tofu'd as boxes before).
	var nunito := ResourceLoader.load("res://assets/fonts/Nunito-Regular.ttf",
		"FontFile", ResourceLoader.CACHE_MODE_IGNORE) as Font
	# Glyph fallback chain: text faces fall through to Inter, then Nunito.
	var _font_fallbacks: Array[Font] = []
	if inter != null:
		_font_fallbacks.append(inter)
	if nunito != null:
		_font_fallbacks.append(nunito)
	if marcellus != null:
		marcellus.fallbacks = _font_fallbacks
	if kreon != null:
		kreon.fallbacks = _font_fallbacks
	if inter != null and nunito != null:
		inter.fallbacks = [nunito]

	# Display = Kreon Bold (replaced Marcellus 2026-06-29). Marcellus is a
	# high-contrast inscriptional face — its hairlines stay thin at ANY weight, and
	# heavy embolden only roughened it on MSDF. Kreon is a low-contrast slab: uniform
	# strokes read reliably FAT at every size, AND it unifies the display with the
	# card rules + numerals (all Kreon now; only the UI body stays Inter). wght 700
	# (axis max) + a little embolden for extra heft (msdf_pixel_range 16 gives room).
	if kreon != null:
		var disp := FontVariation.new()
		disp.base_font = kreon
		disp.variation_opentype = {"wght": 700}
		disp.variation_embolden = 0.25
		font_display = disp
		if OS.is_debug_build():
			print("[GameTheme] font_display set to Kreon Bold")
	else:
		push_warning("[GameTheme] Kreon unavailable — display falls back to Inter")
		font_display = inter
	# Stat numerals = Kreon Bold (lining figures, sturdy slab on the wax seals).
	# NOTE: Card2D's orb numerals carry explicit per-label Y offsets
	# (ORB_NUMERAL_Y_OFFSET) tuned to the old Lilita metrics — re-verify the seal
	# centering after this swap and nudge that constant if numerals sit high/low.
	if kreon != null:
		var statf := FontVariation.new()
		statf.base_font = kreon
		statf.variation_opentype = {"wght": 700}
		statf.variation_embolden = 0.45  # push numerals past Kreon's 700 axis max
		font_stat = statf
	else:
		font_stat = font_display

	# UI / menu / HUD / tooltip body = Inter (modern screen-legibility standard).
	# wght 680 (2026-07-06, down from 850): Black-weight Inter at 16-18px CLOGS —
	# counters and apertures close up and the text reads smaller and muddier than
	# its point size ("feels small, hard to read"). Just-under-Bold keeps couch
	# presence with open letterforms; [b] keyword tags at 900 still read heavier.
	if inter != null:
		var body := FontVariation.new()
		body.base_font = inter
		body.variation_opentype = {"wght": 680}
		font_body = body
		var body_bold := FontVariation.new()
		body_bold.base_font = inter
		body_bold.variation_opentype = {"wght": 900}
		font_body_bold = body_bold
	else:
		font_body = font_display
		font_body_bold = font_display

	# Combat HUD chrome = Marcellus (titles / captions). Titles render large, where
	# Marcellus's engraved Roman caps are elegant and readable — no FontVariation
	# needed. HUD numerals (HP / Command / counts) reuse the Kreon stat font
	# (font_stat): a sturdy slab reads cleaner and crisper at small HUD sizes than a
	# thin serif weight would.
	if kreon != null:
		var titlef := FontVariation.new()
		titlef.base_font = kreon
		titlef.variation_opentype = {"wght": 700}
		titlef.variation_embolden = 0.30  # big HUD headers / banners — extra heft
		font_title = titlef
	else:
		font_title = font_display
	font_title_black = font_stat
	if OS.is_debug_build():
		print("[GameTheme] font_title=Kreon Bold; font_title_black=Kreon stat font")

	# Card rules text = Kreon (Slay the Spire's card hand). A low-contrast slab that
	# stays solid at 10-13px on the parchment where Alegreya's hairlines thinned out;
	# its lining numerals also fix Alegreya's lumpy old-style figures. SCOPED TO CARDS
	# (HUD/menus use Inter). wght 500 body / 700 bold for [b] keyword tags.
	if kreon != null:
		var writ_body := FontVariation.new()
		writ_body.base_font = kreon
		writ_body.variation_opentype = {"wght": 700}  # Kreon Bold (axis max) — real weight
		writ_body.variation_embolden = 0.30  # extra heft now that msdf_pixel_range has room
		font_card_body = writ_body
		var writ_bold := FontVariation.new()
		writ_bold.base_font = kreon
		writ_bold.variation_opentype = {"wght": 700}
		writ_bold.variation_embolden = 0.22  # keyword [b] tags read clearly heavier
		font_card_body_bold = writ_bold
		if OS.is_debug_build():
			print("[GameTheme] font_card_body set to Kreon")
	else:
		font_card_body = font_body
		font_card_body_bold = font_body_bold
	_load_keyword_icons()
	tex_icon_sword = load("res://assets/icons/sword.png")
	tex_icon_heart = load("res://assets/icons/heart.png")
	tex_icon_diamond = load("res://assets/icons/diamond.png")

	# Map node icons — hand-drawn fantasy line-art from game-icons.net
	# (CC-BY 3.0 by lorc & delapouite — credited in CREDITS.md). These look
	# more "drawn into the parchment" than the Kenney silhouettes did and
	# don't all read as the same shape at a glance.
	var gi_dir := "res://assets/icons/game-icons/"
	tex_node_combat = load(gi_dir + "crossed-swords.svg")
	tex_node_elite = load(gi_dir + "horned-skull.svg")
	tex_node_rest = load(gi_dir + "campfire.svg")
	tex_node_shop = load(gi_dir + "shop.svg")
	tex_node_event = load(gi_dir + "scroll-unfurled.svg")
	tex_node_boss = load(gi_dir + "dragon-head.svg")
	tex_node_treasure = load(gi_dir + "coins-pile.svg")
	tex_node_recruit = load(gi_dir + "flying-flag.svg")
	# Wayside halts (drill yard / muster scale / standard-bearer / cache) —
	# the roadside verbs added 2026-06-12. Each verb now draws its OWN ink
	# glyph on the chart (anvil / scales / banner / chest) via
	# MapTerrain._draw_wayside_glyph, so the four stops aren't pixel-identical.
	# This helm-on-a-post texture stays as the fallback for an unknown/blank
	# wayside_id (and the legend reuses the same per-verb glyphs).
	tex_node_wayside = load(gi_dir + "horned-helm.svg")
	# Painted icons (downloaded CC0 from OpenGameArt) prefer over silhouettes
	# where available — they match Slay-the-Spire's painted HUD aesthetic.
	var heart_painted = "res://assets/icons/map/hud_heart_painted.png"
	tex_hud_heart = load(heart_painted) if ResourceLoader.exists(heart_painted) \
		else load("res://assets/icons/map/hud_heart.png")
	# ONE MINT EVERYWHERE. The gold symbol used to be three different coins: the
	# map purse painted CoinProp (the Old King's crowned profile), while the
	# event ledger and every inline outcome glyph used a bought asset-store coin
	# — bright lemon, cartoon bevel, and a CYAN DIAMOND stamped on it, which is
	# the only pure cyan in a sepia-and-ember game. `hud_gold_coin.png` is the
	# CoinProp painter baked to a texture (tools/_bake_coin_icon.gd), so the HUD
	# register and the BBCode glyphs carry the same coinage as the map purse and
	# the event tables' props. Re-run the bake if CoinProp's mint ever changes.
	var gold_mint = "res://assets/icons/map/hud_gold_coin.png"
	tex_hud_gold = load(gold_mint) if ResourceLoader.exists(gold_mint) \
		else load("res://assets/icons/map/hud_gold.png")
	var potion_painted = "res://assets/icons/map/hud_potion_painted.png"
	tex_hud_potion = load(potion_painted) if ResourceLoader.exists(potion_painted) \
		else load("res://assets/icons/map/hud_potion.png")
	tex_hud_relic = load("res://assets/icons/map/hud_relic.png")
	tex_hud_deck = load("res://assets/icons/map/hud_deck.png")

	var np_path = "res://assets/ui/kenney_fantasy-ui-borders/PNG/Double/Panel/panel-009.png"
	if ResourceLoader.exists(np_path):
		tex_panel_9p = load(np_path)

	_build_card_surface_textures()


func _build_card_surface_textures() -> void:
	# Builds the four overlay textures Card2D layers on top of the walnut
	# body to give it real surface depth. All generated procedurally so they
	# stay self-contained and don't add to the asset budget.
	#
	# Order matters: grain goes on first (paper fiber), then top_light
	# (directional sheen), then bottom_shade (gravity shadow), then vignette
	# (corner darkening). Together they fake a card lit from above with
	# parchment in the middle and shadow at the edges — the visual signature
	# of every modern card UI from Hearthstone to STS.

	# 1. Paper grain — tileable Perlin noise. Low frequency + 3 octaves reads
	#    as fiber rather than static. 256x256 is large enough that the seam
	#    isn't visible at card scale (225x300).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.2
	noise.fractal_gain = 0.55
	var grain := NoiseTexture2D.new()
	grain.noise = noise
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	grain.normalize = true
	tex_card_grain = grain

	# Anisotropic wood grain — same Perlin source but baked at 256×32, so
	# when tiled across the 225×300 card it stretches horizontally and
	# repeats vertically ~8 times, giving directional "grain lines" that
	# read as real wood instead of generic digital noise. The fine grain
	# above stays underneath for sub-pixel fiber texture; this layer adds
	# the directional structure that makes the surface stop reading as
	# "Photoshop Add Noise filter" and start reading as a wooden card frame.
	var wood_noise := FastNoiseLite.new()
	wood_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	wood_noise.frequency = 0.07
	wood_noise.fractal_octaves = 2
	wood_noise.fractal_lacunarity = 2.5
	wood_noise.fractal_gain = 0.60
	var wood := NoiseTexture2D.new()
	wood.noise = wood_noise
	wood.width = 256
	wood.height = 32         # 8:1 aspect — horizontal grain when tiled
	wood.seamless = true
	wood.normalize = true
	tex_card_wood_grain = wood

	# 2. Top-light gradient — white at top, fades to transparent by ~55%.
	#    Applied at low alpha (Card2D modulates ~0.10) to suggest a light
	#    source above the card without washing out the bg.
	var top_grad := Gradient.new()
	top_grad.set_color(0, Color(1, 1, 1, 1))
	top_grad.set_color(1, Color(1, 1, 1, 0))
	top_grad.set_offset(0, 0.0)
	top_grad.set_offset(1, 0.55)
	var top_tex := GradientTexture2D.new()
	top_tex.gradient = top_grad
	top_tex.width = 4
	top_tex.height = 256
	top_tex.fill_from = Vector2(0, 0)
	top_tex.fill_to = Vector2(0, 1)
	tex_card_top_light = top_tex

	# 3. Bottom-shade gradient — transparent at top, dark at bottom from ~45% on.
	#    Pairs with the top light to give the body a faux-cylinder shading
	#    cue (lit top, shadowed bottom).
	var bot_grad := Gradient.new()
	bot_grad.set_color(0, Color(0, 0, 0, 0))
	bot_grad.set_color(1, Color(0, 0, 0, 1))
	bot_grad.set_offset(0, 0.45)
	bot_grad.set_offset(1, 1.0)
	var bot_tex := GradientTexture2D.new()
	bot_tex.gradient = bot_grad
	bot_tex.width = 4
	bot_tex.height = 256
	bot_tex.fill_from = Vector2(0, 0)
	bot_tex.fill_to = Vector2(0, 1)
	tex_card_bottom_shade = bot_tex

	# 4. Radial vignette — transparent center, dark corners. GradientTexture2D
	#    with FILL_RADIAL handles the circular falloff; linear gradients can't
	#    fake it. 128x128 is enough for a soft falloff at card scale.
	var vig_grad := Gradient.new()
	vig_grad.set_color(0, Color(0, 0, 0, 0))
	vig_grad.set_color(1, Color(0, 0, 0, 1))
	vig_grad.set_offset(0, 0.55)
	vig_grad.set_offset(1, 1.0)
	var vig_tex := GradientTexture2D.new()
	vig_tex.gradient = vig_grad
	vig_tex.width = 128
	vig_tex.height = 128
	vig_tex.fill = GradientTexture2D.FILL_RADIAL
	vig_tex.fill_from = Vector2(0.5, 0.5)
	vig_tex.fill_to = Vector2(1.0, 0.5)
	tex_card_vignette = vig_tex

	# 5. Painted brush-stroke edge — noise-perturbed inner-vignette that
	#    breaks the smooth ring into brush-irregular ink-wash darkening at
	#    the body edges. GradientTexture2D can only do clean circular
	#    falloffs; brush feel needs real noise sampled per pixel, so this
	#    one's baked into an Image and uploaded as an ImageTexture.
	#
	#    Card aspect (225:300) so the brush detail doesn't get directionally
	#    stretched at apply-time. ~68k pixels generated once at scene start
	#    — sub-frame cost, then reused by every Card2D for the rest of the
	#    session (no per-frame work, GL-compat safe).
	var bw := 225
	var bh := 300
	var bimg := Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	# Low-frequency body noise — varies the ink darkness across the page so
	# some strokes are heavier than others (uneven brush pressure).
	var brush_density := FastNoiseLite.new()
	brush_density.noise_type = FastNoiseLite.TYPE_PERLIN
	brush_density.frequency = 0.04
	brush_density.fractal_octaves = 2
	# High-frequency edge perturbation — pushes the alpha boundary in and
	# out by a few pixels along its length so it stops reading as a smooth
	# inset rectangle and starts reading as a hand-painted edge.
	var brush_edge_perturb := FastNoiseLite.new()
	brush_edge_perturb.noise_type = FastNoiseLite.TYPE_PERLIN
	brush_edge_perturb.frequency = 0.15
	brush_edge_perturb.fractal_octaves = 2
	var edge_zone := 0.20  # darkening starts 20% in from each edge
	for y in bh:
		for x in bw:
			# Distance to nearest edge, normalized 0..0.5 (0 at edge, 0.5 mid).
			# Types are explicit because GDScript's min() returns Variant and
			# arithmetic propagates the Variant — `:=` inference fails.
			var fx: float = float(x) / float(bw - 1)
			var fy: float = float(y) / float(bh - 1)
			var d: float = min(min(fx, 1.0 - fx), min(fy, 1.0 - fy))
			# Perturb d with high-freq noise so the falloff boundary
			# wobbles in and out — turns the clean inset ring into a
			# brush-irregular edge.
			var pert: float = brush_edge_perturb.get_noise_2d(float(x), float(y))
			var dp: float = d + pert * 0.025
			var t: float = clamp(dp / edge_zone, 0.0, 1.0)
			var alpha: float = 1.0 - smoothstep(0.0, 1.0, t)
			# Vary darkness over the body so the wash isn't uniform.
			var dens: float = brush_density.get_noise_2d(float(x), float(y))
			var ink: float = clamp(0.55 + dens * 0.20, 0.30, 0.80)
			bimg.set_pixel(x, y, Color(0.07, 0.05, 0.03, alpha * ink))
	tex_card_brush_edge = ImageTexture.create_from_image(bimg)


# ── Color Palette ──
const PARCHMENT      := Color(0.12, 0.09, 0.07, 0.94)
const PARCHMENT_BORDER := Color(0.60, 0.45, 0.22, 1.0)
const GILT           := Color(0.82, 0.66, 0.30, 1.0)
const GILT_BRIGHT    := Color(1.0, 0.88, 0.35, 1.0)
const IVORY          := Color(0.96, 0.92, 0.78, 1.0)
const BLOOD_RED      := Color(0.85, 0.22, 0.18, 1.0)
const MANA_BLUE      := Color(0.369, 0.525, 0.769, 1.0)  # hex #5E86C4 — dropped the digital-cornflower sat/value (S63→52,V95→77) into the period palette; hue held at 216° so it still reads "Command blue" and stays in the navy COST_BLUE_GEM family
const HEALTH_GREEN   := Color(0.373, 0.659, 0.353, 1.0)  # hex #5FA85A — was electric #40D959 (S71/V85); muted to a herbal sage (S46/V66), hue nudged 130°→116° (warm-leaning) to sit with the parchment family without going muddy; ~6.5:1 on BOARD_BG
const ATK_RED        := Color(0.886, 0.353, 0.235, 1.0)  # hex #E25A3C — pulled the pure #FF593F flame off max value/sat toward the burnished-bronze/oxblood warm family; still a hot orange-red (H11, ~5.2:1 on dark) for the attack/damage signal
const ATK_BUFFED     := Color(1.0, 0.8, 0.2, 1.0)
const HP_DAMAGED     := Color(1.0, 0.3, 0.3, 1.0)
const SPELL_PURPLE   := Color(0.624, 0.525, 0.788, 1.0)  # hex #9F86C9 — desaturated the bright lavender (S42/V95) to a dusty amethyst (S33/V79); hue held at 262° so spells stay distinct, but it no longer reads as glossy digital UI against parchment; ~6:1 on BOARD_BG
const KEYWORD_GOLD   := Color(1.0, 0.85, 0.45, 1.0)
const DESC_DIM       := Color(0.78, 0.74, 0.62, 1.0)
const FLOOP_BLUE     := Color(0.30, 0.70, 0.95, 1.0)
const BOARD_BG       := Color(0.075, 0.065, 0.055, 1.0)
const LANE_BORDER    := Color(0.38, 0.28, 0.15, 0.85)
const DIMMED         := Color(0.50, 0.50, 0.50, 0.70)
const RARITY_COMMON  := Color(0.75, 0.75, 0.75, 1.0)
const RARITY_UNCOMMON := Color(0.435, 0.576, 0.800, 1.0)  # hex #6F93CC — the v4 comment warns off the digital-cornflower; pulled this rarity-text blue (S58/V95) to match the muted MANA_BLUE family (S46/V80), hue held at 217° so it reads identically as "uncommon blue"
const RARITY_RARE    := Color(0.95, 0.78, 0.22, 1.0)
const RARITY_WHITE   := Color(0.92, 0.97, 1.0, 1.0)
const RARITY_STARTER := Color(0.55, 0.55, 0.55, 1.0)

# ── v4 procedural-frame palette ──
# Wax-seal / struck-coin palette tuned for the painted parchment frame. The
# earlier Hearthstone-bright hues (#3A8BD9 / #F5C842 / #E03C28) read as glossy
# digital-game UI; these are muted, slightly desaturated, and pulled toward
# the brown/tan family of the frame so the discs feel painted on, not pasted on.
# Hue separation still ≥120° on the wheel — readable at a glance.
const COST_BLUE_GEM   := Color(0.149, 0.255, 0.404, 1.0)   # #264167  sealing-wax navy
const ATK_GOLD_SHIELD := Color(0.471, 0.376, 0.157, 1.0)   # #786028  burnished bronze
const HEALTH_RED_DROP := Color(0.510, 0.137, 0.106, 1.0)   # #82231B  oxblood wax
# Enemy COMMAND wax — the foe's resource seal. Vermilion sealing-wax red, the
# warm complement to the player's navy COST_BLUE_GEM, so "blue = your Command /
# red = the foe's Command" reads as a team-colour pair. Pitched brighter & more
# saturated than the oxblood HEALTH drop so an enemy Command seal never reads as
# a health pip. (Palette pass may retune the exact value — keep it a clear red.)
const COMMAND_RED_GEM := Color(0.698, 0.227, 0.157, 1.0)   # #B23A28  vermilion command wax — retuned for the warm/cool team split: hue eased 5°→8° (cleanly off the oxblood) and lifted to V70 vs HEALTH_RED_DROP's V51, so the enemy Command seal stays in one red family with oxblood/BLOOD_RED yet reads a full step brighter than a health pip
# Enemy-side accent (warm team colour) — a slightly desaturated brick of the
# COMMAND_RED_GEM hue for foe-side UI washes / outlines / banners. Sits in the
# same warm red family as the enemy Command seal but muted (V69/S76) so it can
# tint larger areas without shouting; complement to the player's navy.
const ENEMY_TINT      := Color(0.690, 0.224, 0.169, 1.0)   # #B0392B  muted enemy brick
# Parchment well: light tan with near-black body text. Contrast ~11.8:1 → AAA.
const PARCHMENT_LIGHT := Color(0.910, 0.863, 0.753, 1.0)   # #E8DCC0
const PARCHMENT_TEXT  := Color(0.141, 0.094, 0.063, 1.0)   # #241810
# Rarity gem colours (visible at-a-glance per Hearthstone gem-on-art convention).
const GEM_STARTER     := Color(0.627, 0.627, 0.627, 1.0)   # #A0A0A0 muted grey
const GEM_COMMON      := Color(0.95,  0.95,  0.95,  1.0)   # white
const GEM_UNCOMMON    := Color(0.357, 0.525, 0.969, 1.0)   # #5B86F7
const GEM_RARE        := Color(0.961, 0.784, 0.259, 1.0)   # #F5C842 (matches ATK)
const GEM_WHITE       := Color(0.925, 0.980, 1.000, 1.0)   # cold white
# Frame trim colours per rarity — four distinct hues so the frame itself
# carries the rarity signal (Marvel-Snap-style). Combined with the small
# rarity gem at the art/text boundary you get two redundant cues, which is
# the AAA convention for at-a-glance readability.
const FRAME_TRIM_STARTER  := Color(0.706, 0.631, 0.471, 1.0)  # #B4A178 warm brass (was #8A7C5E)
const FRAME_TRIM_COMMON   := Color(0.831, 0.745, 0.541, 1.0)  # #D4BE8A bright gilt (was #B3A077)
const FRAME_TRIM_UNCOMMON := Color(0.529, 0.667, 0.851, 1.0)  # #87AAD9 cool blue gilt (was #6E8AB0)
const FRAME_TRIM_RARE     := Color(0.961, 0.784, 0.259, 1.0)  # #F5C842 bright gold (unchanged — already pops)
const FRAME_TRIM_WHITE    := Color(0.900, 0.970, 1.000, 1.0)  # cold white-blue

# ── Font Sizes ──
# Tuned for the ~1920×1080 logical canvas: body text below ~16px is genuinely
# hard to read from a couch. FONT_BODY is the make_label() default and the most
# leveraged number in the game — a large fraction of every screen's label/desc
# text inherits it. Keep it at the legibility floor, never below.
const FONT_HEADER := 28
const FONT_SUBHEADER := 20
# 18, not 16 (2026-07-06): make_label already clamped 16 up to MIN_LABEL_SIZE,
# so the constant was lying — and every non-clamped path that trusted it
# rendered below the floor. Constant now IS the floor.
const FONT_BODY := 18
const FONT_TITLE := 34
# Hard readability floor: no label/button text renders below this, no matter what
# size a caller asks for. Couch-distance legibility — small 13–15px helper text
# was unreadable. Enforced in make_label / make_themed_button / make_back_button;
# bump this ONE number to make all small UI text bigger.
const MIN_LABEL_SIZE := 18


# ═══════════════════════════════════════════
#  STYLEBOX FACTORIES
# ═══════════════════════════════════════════

func make_panel_textured(tint: Color = Color(0.18, 0.14, 0.10),
		margin: int = 20, content_margin: int = 12) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	if tex_panel_9p:
		s.texture = tex_panel_9p
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.content_margin_left = content_margin
	s.content_margin_right = content_margin
	s.content_margin_top = content_margin
	s.content_margin_bottom = content_margin
	s.modulate_color = tint
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s


## The struck-metal BUTTON plate. Preloaded under its own name like every other
## painter in that directory (no `class_name`, so no `--import` pass is needed
## for it to resolve). Used by `make_plaque_style` above; kept out of
## `ChartPanelStyle`'s path on purpose — see that factory's header.
const PlaqueStyle := preload("res://scripts/ui/painters/PlaqueStyle.gd")
const PageBorder := preload("res://scripts/ui/painters/PageBorder.gd")


# ═══════════════════════════════════════════════════════════════════════════
#  CHART PANEL STYLE — the drawn "document furniture" panel (2026-07-06).
#  Replaces the flat rounded-rectangle StyleBoxFlat every UI panel used to
#  bottom out in. A StyleBox subclass draws the whole assembly per panel:
#    · chamfered corners — the sheet is CUT like a plate mount, not CSS-rounded
#    · a metal rule (caller's border color) over an inner ink keyline (the
#      double-rule convention the card frames and map cartouches already use)
#    · corner tacks on the chamfer diagonals (war-table corner-tack echo);
#      auto-hidden on small chips so chrome never clutters a 30px pill
#    · a lit-from-above field gradient so the panel reads as a physical leaf
#    · a soft layered drop shadow sinking it into the painted scene
#  Extends StyleBox directly, so every add_theme_stylebox_override caller and
#  every content_margin_* mutation keeps working unchanged.
# ═══════════════════════════════════════════════════════════════════════════
class ChartPanelStyle extends StyleBox:
	# bg/border emit `changed` on mutation (StyleBoxFlat parity) — HUD chips
	# recolor their border at runtime and the panel must repaint.
	var bg_color := Color(0.06, 0.05, 0.042, 0.96):
		set(v):
			bg_color = v
			emit_changed()
	var border_color := Color(0.60, 0.51, 0.34, 0.90):
		set(v):
			border_color = v
			emit_changed()
	var rule_width := 1.0
	var chamfer := 12.0
	var shadow := true
	var parchment := false
	var corner_tacks := true
	# StyleBoxFlat-parity shadow knobs (some callers retint the shadow into a
	# hover glow): color tints the layered shadow, size scales its spread
	# (8 = the kit default).
	var shadow_color := Color(0, 0, 0, 1.0):
		set(v):
			shadow_color = v
			emit_changed()
	var shadow_size := 8.0:
		set(v):
			shadow_size = v
			emit_changed()

	func _get_draw_rect(rect: Rect2) -> Rect2:
		# No-shadow plates still grow a touch: the hand-cut wobble breathes
		# up to ~3px outside the box and must not clip.
		return rect.grow(6.0 + shadow_size * 1.2) if shadow else rect.grow(4.0)

	static func _oct(r: Rect2, inset: float, ch: float) -> PackedVector2Array:
		var l := r.position.x + inset
		var t := r.position.y + inset
		var rr := r.position.x + r.size.x - inset
		var b := r.position.y + r.size.y - inset
		var c: float = maxf(ch - inset * 0.5, 2.0)
		return PackedVector2Array([
			Vector2(l + c, t), Vector2(rr - c, t), Vector2(rr, t + c),
			Vector2(rr, b - c), Vector2(rr - c, b), Vector2(l + c, b),
			Vector2(l, b - c), Vector2(l, t + c)])

	## Hand-cut plate silhouette: the chamfered octagon with a seeded organic
	## wobble along each long edge — the WritLeaf rule scaled down to furniture.
	## Corners stay PINNED (wobble eases to zero at both ends of every edge) so
	## the plate keeps its rectangular stance and chamfer cuts read clean; the
	## wobble is two low sines + a per-point hash jitter, so the edge reads as
	## material cut and worn by hand — not a rectangle, not a pure wave.
	## amp <= 0 returns the exact octagon (small chips stay crisp).
	static func _plate(r: Rect2, inset: float, ch: float, seed: int, amp: float) -> PackedVector2Array:
		var oct := _oct(r, inset, ch)
		if amp <= 0.05:
			return oct
		var pts := PackedVector2Array()
		for e in range(8):
			var a := oct[e]
			var b := oct[(e + 1) % 8]
			var seg := a.distance_to(b)
			var count := maxi(1, int(seg / 22.0))
			if count == 1:
				pts.append(a)   # chamfer diagonals and short edges pass through
				continue
			# Outward normal (octagon winds clockwise): wobble breathes both ways.
			var n := Vector2(b.y - a.y, a.x - b.x).normalized() * -1.0
			var ph1 := float(absi((seed ^ (e * 19349663)) % 628)) * 0.01
			var ph2 := float(absi((seed ^ (e * 83492791)) % 628)) * 0.01
			for i in range(count):
				var t := float(i) / float(count)
				var pin := sin(t * PI)
				# Two smooth sines only — a per-point hash jitter was tried for
				# "deckle grain" and read as ALIASING at 1080p ("the game looks
				# pixely"), not as material. Organic must stay smooth.
				var d := sin(t * TAU * 1.5 + ph1) * 0.62 + sin(t * TAU * 3.5 + ph2) * 0.38
				pts.append(a.lerp(b, t) + n * d * amp * pin)
		return pts

	static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
		var out := pts.duplicate()
		out.append(pts[0])
		out.append(pts[1])  # overshoot one segment so the closing joint has no notch
		return out

	func _draw(ci: RID, rect: Rect2) -> void:
		var ch := clampf(chamfer, 4.0, minf(rect.size.x, rect.size.y) * 0.26)
		var small: bool = minf(rect.size.x, rect.size.y) < 70.0
		# Seeded per canvas item: every control gets its own stable hand-cut,
		# and a button's hover/pressed styleboxes (different instances, same
		# ci) keep the SAME silhouette — the plate doesn't re-cut itself on
		# state changes. Amp scales with the plate so chips stay near-crisp.
		var seed := int(ci.get_id() & 0x7FFFFFFF)
		var amp := clampf(minf(rect.size.x, rect.size.y) * 0.032, 0.0, 3.6)
		if small:
			amp = minf(amp, 1.1)

		# 1. Drop shadow — three soft octagon layers, offset down, so the panel
		#    sinks into the painted scene instead of floating as a flat cutout.
		#    shadow_color/shadow_size let hover states retint it into a glow.
		#    (The blur hides straight edges, so the shadow skips the wobble.)
		if shadow:
			var spread := shadow_size / 8.0
			var glow := not shadow_color.is_equal_approx(Color(0, 0, 0, 1.0))
			var sh_a := [0.30, 0.15, 0.07]
			for i in range(3):
				var grow := (1.0 + float(i) * 2.6) * spread
				var pts := _oct(rect.grow(grow), 0.0, ch + grow)
				for j in pts.size():
					pts[j] += Vector2(0.0, 0.0 if glow else 3.0)
				RenderingServer.canvas_item_add_polygon(ci, pts,
					PackedColorArray([Color(shadow_color.r, shadow_color.g,
						shadow_color.b, sh_a[i] * shadow_color.a)]))

		# 2. Field — lit from above, bounded by the hand-cut plate silhouette.
		#    Parchment mode warms the ink toward aged paper before the gradient.
		var base := bg_color
		if parchment:
			base = bg_color.lerp(Color(0.16, 0.12, 0.08, bg_color.a), 0.35)
		var top_c := base.lerp(Color(0.30, 0.24, 0.16, base.a), 0.22)
		var bot_c := base.lerp(Color(0.0, 0.0, 0.0, base.a), 0.30)
		var body := _plate(rect, rule_width * 0.5, ch, seed, amp)
		var cols := PackedColorArray()
		for p in body:
			var f := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
			cols.append(top_c.lerp(bot_c, f))
		RenderingServer.canvas_item_add_polygon(ci, body, cols)

		# 2b. Interior ageing — DOCUMENT tiles only (parchment): sepia washes +
		#     foxing specks. Plain dark plates keep their flat lit gradient —
		#     warm washes on every panel stacked into a global brightness lift
		#     ("the game looks too lit up"), so the material lives on the
		#     tiles that are supposed to read as paper, not on all chrome.
		if parchment and not small:
			for k in range(4):
				var hx := float(absi((seed ^ (k * 40503 + 977)) % 1000)) * 0.001
				var hy := float(absi((seed ^ (k * 65599 + 331)) % 1000)) * 0.001
				var hr := float(absi((seed ^ (k * 97911 + 173)) % 1000)) * 0.001
				var pos := rect.position + Vector2(
					rect.size.x * lerpf(0.16, 0.84, hx),
					rect.size.y * lerpf(0.18, 0.82, hy))
				var rad := minf(rect.size.x, rect.size.y) * lerpf(0.16, 0.34, hr)
				RenderingServer.canvas_item_add_circle(ci, pos, rad,
					Color(0.42, 0.30, 0.17, 0.035), true)
			# (Foxing specks were tried here and cut — 1-3px dark dots on dark
			# fills read as stuck pixels, not age. Real foxing lives on the
			# cards' true-parchment faces, where the paper is light.)

		# 3a. Contour ink seam — thin dark AA line on the path, under
		#     everything, at FIXED alpha. This is the aliasing guard: canvas
		#     polygons can't antialias, and the metal rule inherits the
		#     CALLER'S border alpha — a faint border (disabled chips, dim
		#     accents) would leave the fill's staircase edge uncovered.
		#     Doubles as the cards' contour-ink idiom.
		var loop := _closed(body)
		RenderingServer.canvas_item_add_polyline(ci, loop,
			PackedColorArray([Color(0.04, 0.03, 0.02, 0.85)]),
			maxf(rule_width, 1.4) + 1.4, true)

		# 3b. Edge toast — a scorched dark band straddling the SAME hand-cut
		#    path (the WritLeaf rule: shading never separates from the
		#    silhouette). This is what makes the cut read as seared material
		#    instead of a vector outline.
		if not small:
			RenderingServer.canvas_item_add_polyline(ci, loop,
				PackedColorArray([Color(0.02, 0.012, 0.006, 0.50)]),
				rule_width + 9.0, true)

		# 4. The engraved rule — a faint halo of the metal under a crisp rule
		#    along the same path reads as the old double-rule convention
		#    without needing a parallel inset path. Kept at whisper alpha:
		#    at 0.26 the halo on every panel edge stacked into a global
		#    brightness lift across panel-dense screens.
		if not small:
			RenderingServer.canvas_item_add_polyline(ci, loop,
				PackedColorArray([Color(border_color.r, border_color.g,
					border_color.b, border_color.a * 0.12)]),
				rule_width + 3.0, true)
		# The crisp rule floors at 1.4px: canvas polygons can't antialias in
		# GD4, so this line is what covers the fill's hard staircase edge —
		# a 1px line leaves it peeking through on every wobbled span.
		RenderingServer.canvas_item_add_polyline(ci, loop,
			PackedColorArray([border_color]), maxf(rule_width, 1.4), true)

		# 5. Parchment top sheen — a faint gilt catch-light along the top edge.
		var frame := _oct(rect, rule_width * 0.5, ch)
		if parchment and not small:
			var sheen_c := Color(0.95, 0.82, 0.52, 0.28 * border_color.a)
			RenderingServer.canvas_item_add_polyline(ci,
				PackedVector2Array([frame[0] + Vector2(1, 1.2), frame[1] + Vector2(-1, 1.2)]),
				PackedColorArray([sheen_c]), 1.0, true)

		# 6. Corner tacks — small metal diamonds pinned on the chamfer cuts,
		#    echoing the map plate's corner tacks. Auto-hidden on small chips.
		#    Placed off the un-wobbled octagon: corners are pinned, so the
		#    tacks sit exactly on the drawn chamfers.
		if corner_tacks and not small and ch >= 7.0:
			var s := clampf(ch * 0.30, 2.5, 4.5)
			var fill := Color(border_color.r * 0.55, border_color.g * 0.55,
				border_color.b * 0.55, border_color.a)
			var glint := Color(minf(border_color.r * 1.25, 1.0),
				minf(border_color.g * 1.25, 1.0),
				minf(border_color.b * 1.25, 1.0), border_color.a)
			for pair in [[7, 0], [1, 2], [3, 4], [5, 6]]:
				var m: Vector2 = (frame[pair[0]] + frame[pair[1]]) * 0.5
				var quad := PackedVector2Array([
					m + Vector2(0, -s), m + Vector2(s, 0),
					m + Vector2(0, s), m + Vector2(-s, 0)])
				RenderingServer.canvas_item_add_polygon(ci, quad,
					PackedColorArray([fill]))
				RenderingServer.canvas_item_add_polyline(ci, _closed(quad),
					PackedColorArray([glint]), 1.0, true)


# The praised chart look (see make_choice_banner), now drawn as real document
## THE ONE DEFINITION OF "SCALE AN AUTHORED CONSTANT TO THE LIVE CANVAS"
## (2026-09-19, CLASS C32).
##
## UI Scale sets `Window.content_scale_factor`, and under `canvas_items` stretch
## that DIVIDES the logical canvas — at 60% the UI lays itself out on 2667×1500.
## So any rect placed from a constant authored against 1600×900 becomes a
## shrinking island: the player who picks 60% is asking to fit MORE on screen and
## instead gets the same panel with a wider margin of background around it.
## Multiply authored numbers by this and they keep the FRACTION they were chosen
## for. Exactly (1, 1) at 100%, so every call site is a no-op at design scale.
##
## THIS IS A FUNCTION RATHER THAN FOUR COPIES OF THE ARITHMETIC ON PURPOSE.
## `_probe_uiscale` flagged four screens at once (net_lobby, treasure, recruit,
## game_over) and MainMenu had already solved it inline; five hand-rolled copies
## of one rule is this codebase's documented worst pathology — the same shape as
## `NetPlayerState` restating every relic's magnitude as a literal, equal on the
## day it was written and one retune from diverging silently.
##
## READ BEFORE "FIXING" THIS BACK: ProjectSettings is the AUTHORING REFERENCE —
## the static canvas the callers' numbers were written against — which is its one
## honest use. The 2026-09-03 decorative-frame bug was the opposite mistake,
## reading ProjectSettings as if it were the RUNTIME canvas. Static reference,
## live target; never the other way round.
static func canvas_scale(node: Node) -> Vector2:
	if node == null or not node.is_inside_tree():
		return Vector2.ONE
	var canvas: Vector2 = node.get_viewport_rect().size
	var design := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	if design.x <= 0.0 or design.y <= 0.0 or canvas.x <= 0.0 or canvas.y <= 0.0:
		return Vector2.ONE
	return Vector2(canvas.x / design.x, canvas.y / design.y)


# furniture (ChartPanelStyle above): chamfered corners, metal rule over an ink
# keyline, corner tacks, lit field, layered shadow. Every "UI-kit" panel in the
# game routes through here, so this is THE place the document aesthetic is
# enforced. `parchment = true` warms the field toward aged paper and adds the
# gilt top sheen — for tiles that should read as a torn document, not a button.
static func make_panel_style(bg: Color = Color(0.06, 0.05, 0.042, 0.96),
		border: Color = Color(0.60, 0.51, 0.34, 0.90),
		border_w: int = 1, corner: int = 4, shadow: bool = true,
		parchment: bool = false) -> StyleBox:
	var s := ChartPanelStyle.new()
	s.bg_color = bg
	s.border_color = border
	s.rule_width = float(maxi(border_w, 1))
	s.chamfer = 7.0 + float(corner) * 1.5
	s.shadow = shadow
	s.parchment = parchment
	# StyleBoxFlat used the border width as the implicit content margin —
	# replicate exactly so no layout shifts.
	s.set_content_margin_all(float(maxi(border_w, 1)))
	return s


static func make_btn_style(bg: Color, border: Color = GILT, corner: int = 4) -> StyleBox:
	var s := ChartPanelStyle.new()
	s.bg_color = bg
	s.border_color = border
	s.rule_width = 2.0
	s.chamfer = 5.0 + float(corner)
	s.shadow = false
	s.corner_tacks = false
	s.set_content_margin_all(2.0)  # StyleBoxFlat's implicit border-width margin
	return s


## THE PLATED BUTTON (2026-09-17) — `PlaqueStyle`, the struck-metal plate.
##
## ONE FACTORY, because a button's plate is specified in four places
## (`make_primary_button`, `make_themed_button`, MainMenu's primary action and
## its save slots) and four spellings of one material is how they come to be lit
## by different lamps. See `PlaqueStyle`'s header for the diagnosis: every
## button's edge was FOUR STACKED SYMMETRIC POLYLINES, which is the lightning
## defect, and its face was a vertical ramp lit from a different direction than
## its own edge.
##
## DELIBERATELY NOT ROUTED THROUGH `ChartPanelStyle`. That helper is every panel,
## chip, tile and banner in the game, and its own comments record what happens
## when a warm pass is added to all of them at once — "stacked into a global
## brightness lift", "the game looks too lit up". A molding is a much bigger
## change than a halo, so it goes where it was asked for: the buttons.
##
## `state` is `PlaqueStyle.REST` / `.HOVER` / `.PRESS`. The press state is the
## point — the plate goes FLUSH rather than merely darker.
static func make_plaque_style(metal: Color, fill: Color, state: int,
		opts: Dictionary = {}) -> StyleBox:
	var s = PlaqueStyle.new()
	s.metal = metal
	s.fill = fill
	s.state = state
	for k in opts:
		# AN UNKNOWN KEY IS REPORTED, NOT SWALLOWED. `Object.set()` on a property
		# that does not exist does NOTHING AT ALL — no error, no warning, no
		# return value — so a misspelled option is a style that silently keeps
		# its default and a tuning session spent wondering why a number has no
		# effect. (The sibling spelling is worse in the other direction: a TYPED
		# `s.rule_width = x` against a missing property throws, and a failed
		# assignment ABORTS the function, so the factory returns null and the
		# caller reports "required object is null" from somewhere else entirely.
		# That is exactly how this loop's first version was caught.)
		if not (k in s):
			push_warning("make_plaque_style: unknown option '%s' ignored" % str(k))
			continue
		s.set(k, opts[k])
	return s




func make_themed_button(text: String, bg: Color, min_size: Vector2 = Vector2(160, 44),
		font_size: int = FONT_BODY, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE  # drop the default Godot focus rectangle
	btn.add_theme_font_size_override("font_size", maxi(font_size, MIN_LABEL_SIZE))
	# Apply the display font so buttons inherit the game's typography instead
	# of falling back to Godot's default sans-serif. Guarded for the case where
	# font_display hasn't loaded yet (very early scene init).
	if font_display:
		btn.add_theme_font_override("font", font_display)
	# Gilt-ivory letters. The outline is back to 3 now the plaque is gone — the
	# label sits on whatever painted scene is behind it, which is what the heavy
	# outline is for.
	btn.add_theme_color_override("font_color", Color(0.95, 0.88, 0.68))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.80))
	btn.add_theme_color_override("font_disabled_color", Color(0.62, 0.57, 0.47, 0.6))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	btn.add_theme_constant_override("outline_size", 3)

	## ── FRAMELESS (2026-09-18, owner's call). NO PLAQUE, NO FILL, NO KEYLINE.
	##
	## These 44 call sites are the last of the boxed buttons: the primaries went
	## frameless first, and leaving the shop shelf and the lobby rows plated
	## would have been the same mixed grammar from the other side. See
	## [[feedback_ui_aesthetic]] — the text IS the button.
	##
	## THE ACCENT IS PRESERVED, AND THAT IS THE ONLY DELICATE PART. `bg` has
	## carried price / affordability / rarity coding across every one of those
	## sites, first as a flat fill and then as the plaque's keyline. Dropping it
	## would silently delete meaning from a shop shelf, so it MOVES to the
	## igniting underline via the exact expression the plaque used
	## (`GILT.lerp(accent, 0.55 * strength)`) — the same colour, relocated from a
	## box's edge to a rule under the word.
	##
	## AT REST THE ACCENT IS NOT DRAWN, deliberately. Measured across the call
	## sites, most accents are near-identical dark browns (0.34/0.22/0.08 and
	## friends) inherited from the flat-fill era and carrying no information at
	## all; only a handful — the reds and the gilts — mean anything. A rest-state
	## rule per button would therefore print 44 near-identical lines to
	## distinguish about four cases, which is the flat-rectangle problem wearing
	## a thinner hat.
	var key := GILT.lerp(bg.lightened(0.10), 0.55)
	var rest := StyleBoxEmpty.new()
	rest.content_margin_left = 14
	rest.content_margin_right = 14
	rest.content_margin_top = 7
	rest.content_margin_bottom = 7
	btn.add_theme_stylebox_override("normal", rest)
	btn.add_theme_stylebox_override("disabled", rest)
	var lit_style := StyleBoxFlat.new()
	lit_style.bg_color = Color(0.85, 0.62, 0.25, 0.09)
	lit_style.border_color = Color(key.r, key.g, key.b, 0.95)
	lit_style.border_width_bottom = 2
	lit_style.content_margin_left = 14
	lit_style.content_margin_right = 14
	lit_style.content_margin_top = 7
	lit_style.content_margin_bottom = 7
	btn.add_theme_stylebox_override("hover", lit_style)
	btn.add_theme_stylebox_override("focus", lit_style)
	var down := lit_style.duplicate() as StyleBoxFlat
	down.bg_color = Color(0.85, 0.62, 0.25, 0.03)
	down.border_color = Color(key.r * 0.85, key.g * 0.85, key.b * 0.85, 0.95)
	btn.add_theme_stylebox_override("pressed", down)
	arm_ui_hover(btn)
	return btn


# ===========================================================================
#  THE UI VOICE (2026-08-05)
#
#  Before this pass NOTHING in this game made a sound when you touched it:
#  40 `mouse_entered` handlers across scripts/ and not one played a cue, and
#  the whole shell (MainMenu, SettingsOverlay, Collection, Credits) held zero
#  play_sfx call sites. Meanwhile the clash has hitstop and a shuffle bag.
#
#  HOVER is armed HERE, inside the game-wide button funnels, because it is
#  collision-free by construction: no call site in the repo plays anything on
#  hover, so nothing can double up.
#
#  PRESS is NOT armed here, deliberately. Roughly twenty call sites already
#  play their own cue on a button press (Reward's forge pick, MapView's march,
#  Combat's initiative, the event minigame props), and arming the funnel would
#  layer a second sound under every one of them. Screens that have no cue of
#  their own call `arm_ui_press()` explicitly — see SettingsOverlay, Collection
#  and NetLobby. When adding a press cue to a screen, GREP IT FOR play_sfx
#  FIRST.
# ===========================================================================

func arm_ui_hover(btn: Button) -> void:
	## The dry paper tick under the cursor. Skips disabled buttons — a control
	## that refuses the click must not answer the hover.
	if btn == null:
		return
	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(btn) and not btn.disabled:
			AudioBank.play_ui("hover"))


func arm_ui_press(btn: Button, cue: String = "select") -> void:
	## cue: "select" (an ordinary pick) · "back" (any retreat, pitched down so
	## advance and retreat are distinguishable with the screen unread) ·
	## "commit" (a wax seal — reserved for the buttons that spend a run).
	##
	## Since the 2026-09-17 press pass this is no longer how a button GETS a
	## voice — every button has one. It is how a button gets a DIFFERENT one:
	## calling it declares the cue explicitly and the funnel's default "select"
	## stands down (see `_install_press_feedback`).
	if btn == null:
		return
	btn.set_meta("ui_cue", cue)
	if cue == "commit":
		btn.set_meta("press_weight", true)
	btn.pressed.connect(func() -> void: AudioBank.play_ui(cue))


# ═══════════════════════════════════════════════════════════════════════════
#  THE PRESS FUNNEL (2026-09-17)
#
#  MEASURED BEFORE THE PASS: 214 `pressed.connect` sites, 2 `button_down`
#  connections in the entire repo, 24 buttons with a press cue, and
#  `Motion.press` called exactly ONCE (on a HUD instrument, not a button). So
#  pressing almost anything in this game changed a StyleBox and nothing else —
#  no motion, no sound, and the StyleBox swap itself is a state the player only
#  sees while the mouse is down and looking at the thing it is covering.
#
#  WHY THIS IS A TREE HOOK AND NOT FOUR FACTORY CALLS. The obvious
#  implementation arms it inside `make_themed_button` / `make_back_button` /
#  `make_primary_button` / `make_choice_banner`, where `arm_ui_hover` already
#  lives. Counted: those four cover ~87 call sites — against 92 bare
#  `Button.new()`s built by hand across the scenes. Half the game's buttons are
#  not made by the factories, so a factory-side arm would deliver exactly the
#  half-covered surface this pass exists to end, and the gap would be invisible
#  (a button that does not react looks like a button, not like a bug). Hooking
#  `node_added` is the only spelling that cannot drift from the population.
#
#  HOVER'S RULE, APPLIED AGAIN. The block above this one arms hover in the
#  funnels because hover was collision-free, and deliberately leaves PRESS out
#  because ~two dozen call sites already play their own cue. Press MOTION is
#  collision-free in exactly the way hover audio was — nothing but MainMenu
#  animated a press — so it is armed unconditionally. Press AUDIO is not, and is
#  handled by the two devices below.
#
#  DEVICE 1 — THE CUE IS CONNECTED DEFERRED. A screen's own cue is connected
#  later than the funnel's and would therefore run second; deferring the
#  funnel's lets the explicit one claim the frame first.
#  DEVICE 2 — `AudioBank.play_ui` COLLAPSES A REPEAT IN THE SAME FRAME, so the
#  loser is dropped rather than layered. One press is one sound.
#
#  Both are needed: the ordering decides WHICH cue survives, the dedupe decides
#  that only one does.
# ═══════════════════════════════════════════════════════════════════════════

func _install_press_feedback() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.node_added.connect(_on_node_added_press)
	# Autoloads are readied before the main scene, so in practice the tree holds
	# nothing yet — but a probe that boots a scene itself can beat us here, and
	# a funnel that silently covers "everything added after I woke up" is the
	# kind of partial coverage this pass is about.
	for n in tree.root.find_children("*", "BaseButton", true, false):
		_arm_press_default(n as BaseButton)


func _on_node_added_press(node: Node) -> void:
	# Runs for EVERY node added to the tree, combat's thousands included, so it
	# stays a single type test and nothing else.
	if node is BaseButton:
		_arm_press_default(node)


func press_cue_for(btn: BaseButton) -> String:
	## "back" for any retreat, "commit" for a button that spends a run, else
	## "select". Read off the button rather than guessed from its label: the
	## words move with the copy pass and the meaning does not.
	if btn == null or not is_instance_valid(btn):
		return "select"
	if btn.has_meta("ui_cue"):
		return String(btn.get_meta("ui_cue"))
	if btn.has_meta("shell_cue"):
		return String(btn.get_meta("shell_cue"))
	return "select"


func _arm_press_default(btn: BaseButton) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	# `no_press_feel` is the opt-out for a control that owns its own press
	# behaviour (a drag handle, a slider grabber, an invisible catcher whose
	# wrapper is animated by its screen).
	if btn.has_meta("no_press_feel"):
		return
	# `press_weight` asks for the at-cursor mark on top of the dip — set by
	# `make_primary_button` and by any button declaring the "commit" cue, i.e.
	# the actions that spend something. See Motion.press_mark for why it is not
	# simply given to everything.
	Motion.arm_press(btn, {"mark": btn.has_meta("press_weight")})
	btn.pressed.connect(func() -> void:
		if is_instance_valid(btn):
			AudioBank.play_ui(press_cue_for(btn)), CONNECT_DEFERRED)


# ═══════════════════════════════════════════════════════════════════════════
#  CHOICE BANNER — parchment panel + icon + title + desc, used by the rest
#  screen (and any other "pick one of several" UI) as a lighter alternative
#  to make_themed_button's flat colored rectangle. Reads as a torn parchment
#  card pinned over the painted background, not a button. Critic review fed
#  this design choice — Card2D's full frame was wrong here (cost orb +
#  ATK/HP would invite drag attempts), and the old flat buttons were
#  hiding the painted scene underneath.
# ═══════════════════════════════════════════════════════════════════════════

## Returns a Control containing a parchment panel + invisible overlay Button.
## Connect to `banner.click_button.pressed` (the meta-field on the returned
## Control), or just iterate the children to find the Button if you prefer.
## `icon_path` may be "" — falls back to drawing a glyph from the title's
## first character. `disabled_reason` non-empty greys the banner and shows
## that text in the body.
func make_choice_banner(title: String, desc: String, accent: Color,
		icon_path: String = "", min_size: Vector2 = Vector2(340, 150),
		disabled_reason: String = "") -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = min_size
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var disabled: bool = (disabled_reason != "")

	# Chart-language panel: the drawn document-furniture kit (ChartPanelStyle).
	# The accent survives as a small rule under the title and the hotspot glow
	# behind the banner, so choices still read related-but-distinct without
	# becoming colored rectangles.
	var s := make_panel_style(
		Color(0.055, 0.048, 0.040, 0.96 if not disabled else 0.60),
		Color(0.60, 0.51, 0.34, 0.90 if not disabled else 0.35),
		1, 4, true, true)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	root.add_theme_stylebox_override("panel", s)

	# Body: HBox = [icon column | text column]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hbox)

	# Icon column — a FIXED-size sigil that anchors the banner without dominating
	# it. Hard-pinned: SHRINK_CENTER stops the HBox stretching the column, and
	# clip_contents guarantees the glyph can never bleed under the body text (an
	# earlier FIT_WIDTH_PROPORTIONAL + FULL_RECT setup ballooned to ~130px and
	# the copy rendered on top of it — the "gold blob behind the words" bug).
	const ICON_PX := 46.0
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.clip_contents = true
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_box)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		# Engraved-sigil treatment: drop shadow + parchment tint, like the map
		# legend icons. Flooding the white glyph with the accent color turns
		# it into a flat toy — the accent belongs on the rule, not the icon.
		var icon_tex: Texture2D = load(icon_path)
		for layer in range(2):
			var tex := TextureRect.new()
			tex.texture = icon_tex
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			if layer == 0:
				for prop in ["offset_left", "offset_top",
						"offset_right", "offset_bottom"]:
					tex.set(prop, 2.0)
				tex.modulate = Color(0, 0, 0, 0.55 if not disabled else 0.30)
			else:
				# Quieter parchment tint — the icon is a supporting sigil, not
				# a bright gold focal point competing with the title.
				tex.modulate = Color(0.74, 0.67, 0.52) if not disabled \
					else Color(0.50, 0.48, 0.44, 0.55)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(tex)
	else:
		var glyph := Label.new()
		glyph.text = title.left(1)
		glyph.add_theme_font_size_override("font_size", 40)
		glyph.add_theme_color_override("font_color",
			Color(0.82, 0.74, 0.56) if not disabled else Color(0.5, 0.5, 0.5, 0.5))
		glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		glyph.add_theme_constant_override("outline_size", 3)
		if font_display:
			glyph.add_theme_font_override("font", font_display)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(glyph)

	# Text column — title (display font) + desc (body font). Both ignore mouse
	# so the overlay Button below catches every click cleanly.
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color",
		Color(0.90, 0.78, 0.52) if not disabled else Color(0.6, 0.6, 0.55, 0.7))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title_lbl.add_theme_constant_override("outline_size", 3)
	if font_display:
		title_lbl.add_theme_font_override("font", font_display)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title_lbl)

	# The accent's home: a short rule under the title, echoing the chart's
	# ruled furniture while keeping the choice's identity color.
	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b,
		0.80 if not disabled else 0.30)
	rule.custom_minimum_size = Vector2(38, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(rule)

	var body_text: String = disabled_reason if disabled else desc
	var body_lbl := Label.new()
	body_lbl.text = body_text
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 18)
	body_lbl.add_theme_color_override("font_color",
		Color(0.88, 0.84, 0.72, 0.95) if not disabled else Color(0.82, 0.72, 0.60, 0.92))
	body_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	body_lbl.add_theme_constant_override("outline_size", 2)
	if font_body:
		body_lbl.add_theme_font_override("font", font_body)
	body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(body_lbl)

	# Click overlay — sits over the whole panel, transparent stylebox so the
	# painted parchment shows through. Disabled when disabled_reason is set,
	# Godot then greys input automatically and skips the pressed signal.
	var click_btn := Button.new()
	click_btn.name = "ClickButton"
	click_btn.flat = true
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.disabled = disabled
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	root.add_child(click_btn)

	# Hover lift: subtle modulate brighten on enter, restore on exit. Skipped
	# when disabled so dead options don't pretend to be live.
	if not disabled:
		click_btn.mouse_entered.connect(func():
			root.modulate = Color(1.10, 1.08, 1.02, 1.0)
		)
		click_btn.mouse_exited.connect(func():
			root.modulate = Color.WHITE
		)
	else:
		# Permanent "torn / faded" look — slight desaturation + slight rotation
		# kept off so it doesn't look misaligned next to live banners.
		root.modulate = Color(0.85, 0.82, 0.78, 0.95)

	# Expose the click button as a child by name so callers can connect:
	#   var b = GameTheme.make_choice_banner(...)
	#   b.get_node("ClickButton").pressed.connect(_on_my_choice)
	return root


# ═══════════════════════════════════════════
#  CARD TRIBES — name accent color by faction
# ═══════════════════════════════════════════
# Like Monster Train's clan accents and Legends of Runeterra's region tint,
# but applied only to the card's name text. Lookup is name-key first (so
# enemy-only inline creatures defined in EncounterDB by name pick up the right
# color without needing an id), with id as a fallback for cards where the id
# differs from the name (e.g. wolf_c, smite_spell, echo_spell).
const CARD_TRIBES := {
	# SOLDIER — knights, militia, paladins, disciplined fighters
	"shieldbearer": "soldier", "pikeman": "soldier",
	"squire_captain": "soldier", "torchbearer": "soldier",
	"crystal_sentry": "soldier", "glass_knight": "soldier",
	"battle_drummer": "soldier", "duelist": "soldier",
	"adaptable": "soldier", "royal_guard": "soldier",
	"ironclad_veteran": "soldier", "paladin": "soldier", "assassin": "soldier", "warchief": "soldier",
	"lookout": "soldier",
	"scout": "soldier", "archer": "soldier", "enforcer": "soldier",
	"headsman": "soldier", "iron_champion": "soldier",
	"fallen_knight": "soldier", "disgraced_squire": "soldier",
	"demon_soldier": "soldier",

	# WRETCH — goblins, savages, low humanoids
	"goblin": "wretch", "brute": "wretch", "troll": "wretch",
	"ratling": "wretch", "scavenger": "wretch", "goblin_scout": "wretch",
	"plague_rat": "wretch",

	# BEAST — animals, monsters, dragons, harpies
	"wolf": "beast", "hound": "beast", "harpy": "beast",
	"raven": "beast", "bloodhound": "beast", "mule": "beast",
	"griffin": "beast",
	"dragon_hatchling": "beast", "hydra": "beast",
	"wind_harpy": "beast", "bog_lurker": "beast",
	"drake": "beast", "elder_dragon": "beast",
	"spore_beast": "beast", "mire_beast": "beast",
	"basilisk": "beast", "cleave_hound": "beast",

	# FAE — sprites, witches, mages, magical creatures, shapeshifters
	"sprite": "fae", "naga": "fae", "mana_sprite": "fae",
	"witch": "fae", "crow_witch": "fae", "summoner": "fae",
	"leyline_conduit": "fae", "thornguard": "fae", "hexblade": "fae",
	"familiar": "fae",
	"dark_priest": "fae", "cultist": "fae",
	"doppelganger": "fae", "copycat": "fae",

	# UNDEAD/BLOOD — necromancy, vampires, demons, spirits, fire-revenants
	"gravedigger": "undead", "necromancer": "undead", "revenant": "undead",
	"blood_pyre": "undead", "vengeance": "undead", "corpse_eater": "undead",
	"vampire_lord": "undead", "warden_of_graves": "undead",
	"chaos_imp": "undead", "doom_knight": "undead", "husk": "undead",
	"bone_knight": "undead", "fire_elemental": "undead",
	"devils_champion": "undead", "collectors_champion": "undead",

	# CONSTRUCT — stone, walls, golems, siege engines, titans
	"iron_bastion": "construct", "warding_stone": "construct",
	"siege_golem": "construct", "riteforge": "construct",
	"golem": "construct", "stone_sentinel": "construct",

	# SUCCESSOR WARS — rival-kit bodies (renamed per kingdom's island age)
	"centurion": "soldier", "eagle-bearer": "soldier", "first_spear": "soldier",
	"first_ashore": "wretch",
	"salt_harpy": "beast", "pennon_griffin": "beast", "wake_hound": "beast",
	"debtor": "undead", "collateral": "undead", "vault_warden": "undead",
	"repossessed": "undead", "paid_in_full": "undead", "siphon_imp": "undead",
	"furnace_priest": "fae", "claw_adept": "fae", "burning_glass": "fae",
	"cold_lector": "fae", "ink_beast": "fae",
	"pitch_hulk": "construct", "furnace_altar": "construct",
}

# DARK tribe colors — Card2D v3 (the active render path) paints the name on a
# CREAM banner, so the tribe color must be dark/saturated to read. Each value
# clears 4.5:1 contrast against the cream banner and stays visually distinct
# from its neighbors. Bright variants (for dark banners, e.g. v5 if re-
# enabled) are kept below as TRIBE_COLORS_BRIGHT.
const TRIBE_COLORS := {
	"soldier":   Color(0.55, 0.35, 0.08, 1.0),  # dark amber / gold-bronze
	"wretch":    Color(0.62, 0.30, 0.12, 1.0),  # rust brown
	"beast":     Color(0.18, 0.40, 0.15, 1.0),  # forest green
	"fae":       Color(0.10, 0.35, 0.55, 1.0),  # deep teal
	"undead":    Color(0.55, 0.10, 0.10, 1.0),  # crimson
	"construct": Color(0.25, 0.35, 0.45, 1.0),  # slate blue-grey
	"spell":     Color(0.38, 0.18, 0.55, 1.0),  # dark violet
	"neutral":   Color(0.165, 0.122, 0.071, 1.0),  # warm dark brown (v3 default)
}

# Bright variants — used by render paths that paint the name on a DARK banner.
# Same tribes, hand-tuned for
# 4.5:1 contrast on near-black instead of cream.
const TRIBE_COLORS_BRIGHT := {
	"soldier":   Color(0.96, 0.80, 0.34, 1.0),  # warm gold
	"wretch":    Color(0.92, 0.58, 0.26, 1.0),  # burnt orange
	"beast":     Color(0.72, 0.88, 0.34, 1.0),  # lime green
	"fae":       Color(0.46, 0.81, 0.95, 1.0),  # sky cyan
	"undead":    Color(0.94, 0.36, 0.36, 1.0),  # blood red
	"construct": Color(0.74, 0.82, 0.90, 1.0),  # slate blue
	"spell":     Color(0.82, 0.66, 0.96, 1.0),  # lavender
	"neutral":   Color(0.985, 0.965, 0.890, 1.0),  # warm cream
}


func get_card_tribe(card_data: Dictionary) -> String:
	# Returns the tribe key for a card by id first, then name-key fallback so
	# enemy-only creatures defined inline in EncounterDB still get colored
	# even though they have no id field.
	var id: String = card_data.get("id", "")
	if id != "" and CARD_TRIBES.has(id):
		return CARD_TRIBES[id]
	var nm: String = card_data.get("name", "")
	if nm != "":
		var key := nm.to_lower().replace(" ", "_").replace("'", "")
		if CARD_TRIBES.has(key):
			return CARD_TRIBES[key]
	if card_data.get("type", "") == "spell":
		return "spell"
	return "neutral"


func get_name_color(card_data: Dictionary) -> Color:
	# Convenience: tribe → name color, with neutral cream as fallback.
	var tribe: String = get_card_tribe(card_data)
	return TRIBE_COLORS.get(tribe, TRIBE_COLORS["neutral"])


# ═══════════════════════════════════════════
#  SETTINGS GEAR
# ═══════════════════════════════════════════

const GEAR_ICON_PATH := "res://assets/icons/kenney_game-icons/PNG/White/2x/gear.png"

func make_settings_gear(host: Node, size: int = 48,
		offset: Vector2 = Vector2(14, 14)) -> TextureButton:
	# Settings gear — canonical top-LEFT position in card-game UIs (Hearthstone,
	# Cross Blitz, Marvel Snap). Adds itself as a child of `host` so any scene
	# can just call `GameTheme.make_settings_gear(self)` from _ready() and get
	# the same look + behavior everywhere. `host` is typed as Node (not Control)
	# because Combat parents to a CanvasLayer — TextureButton anchors against
	# the viewport in that case, which is exactly what we want for a HUD overlay.
	# Opens the persistent SettingsOverlay attached to UserSettings.
	#
	# Uses the Kenney gear PNG (not a font glyph) so the icon renders identically
	# on every machine regardless of which fonts have U+2699. A prior version
	# used `Button.text = "⚙"` but Lilita One doesn't include the gear codepoint,
	# so the button rendered as empty space on most machines.
	# Ink roundel under the glyph — the same dark-disc + gilt-hairline orb the
	# combat "?" / emote buttons wear, so the gear stops being the one naked
	# icon on every screen and reads as part of the instrument family.
	var orb := Panel.new()
	orb.anchor_left = 0.0
	orb.anchor_right = 0.0
	orb.anchor_top = 0.0
	orb.anchor_bottom = 0.0
	orb.offset_left = offset.x
	orb.offset_right = offset.x + size
	orb.offset_top = offset.y
	orb.offset_bottom = offset.y + size
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var orb_st := StyleBoxFlat.new()
	orb_st.bg_color = Color(0.10, 0.075, 0.060, 0.92)
	orb_st.border_color = Color(0.62, 0.48, 0.26, 0.75)
	orb_st.set_border_width_all(2)
	orb_st.set_corner_radius_all(size / 2)
	orb_st.shadow_color = Color(0, 0, 0, 0.6)
	orb_st.shadow_size = 6
	orb.add_theme_stylebox_override("panel", orb_st)
	host.add_child(orb)
	var btn := TextureButton.new()
	var tex: Texture2D = load(GEAR_ICON_PATH) as Texture2D
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.anchor_left = 0.0
	btn.anchor_right = 0.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	# Glyph inset inside the roundel so the disc stays a disc, not a tight crop.
	var inset := int(size * 0.17)
	btn.offset_left = offset.x + inset
	btn.offset_right = offset.x + size - inset
	btn.offset_top = offset.y + inset
	btn.offset_bottom = offset.y + size - inset
	btn.custom_minimum_size = Vector2(size - inset * 2, size - inset * 2)
	btn.tooltip_text = "Settings"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Gilt tint at rest, bright gold on hover — matches the rest of the HUD's
	# parchment palette. Modulate (not theme color) since this is a TextureButton.
	# The roundel rim brightens in step (direct stylebox write; it's per-orb).
	btn.modulate = Color(0.82, 0.66, 0.30, 0.85)
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.0, 0.88, 0.35, 1.0), 0.12)
		orb_st.border_color = GILT_BRIGHT)
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate", Color(0.82, 0.66, 0.30, 0.85), 0.12)
		orb_st.border_color = Color(0.62, 0.48, 0.26, 0.75))
	btn.pressed.connect(_open_settings_overlay_from_anywhere)
	host.add_child(btn)
	return btn


func _open_settings_overlay_from_anywhere() -> void:
	# Finds the SettingsOverlay attached to the UserSettings autoload and opens
	# it. Same lookup used by Combat / MainMenu — centralized so adding the
	# gear button to a new scene doesn't require duplicating this snippet.
	for child in UserSettings.get_children():
		if child.has_method("_open"):
			child._open()
			return
		elif child.has_method("open"):
			child.open()
			return


func open_settings_overlay() -> void:
	# Public entry point so any screen can open the shared pause/settings overlay
	# from an Esc handler (or a button) — mirrors the top-left gear. The overlay
	# owns its own Esc-to-close, so a second Esc closes it again.
	_open_settings_overlay_from_anywhere()


# ═══════════════════════════════════════════
#  RICH HOVER (StS-style pop-out + anchored tooltip)
# ═══════════════════════════════════════════
# Replaces the engine tooltip on treasure chips (relics, potions): hovering
# pops the chip out (scale-up around its center, raised above its neighbors)
# and shows an ink-board tooltip with the item's name + rules text INSTANTLY
# beside it — no native-tooltip delay, no mouse-chasing. One system so every
# chip in the game (combat HUD, shop, menu relic list) behaves identically.

# Player-facing tier line on relic tooltips. "Elite" stays code-only; these
# words already appear in shop/reward copy.
const RELIC_TIER_TAGS := {
	"starting": "Signature Relic",
	"combat":   "Combat Relic",
	"utility":  "Utility Relic",
	"boss":     "Boss Relic",
	"event":    "Event Relic",
}


func attach_rich_hover(chip: Control, title: String, body: String,
		tag: String = "", accent: Color = GILT, pop_scale: float = 1.3) -> void:
	# The chip must not be MOUSE_FILTER_IGNORE or it will never see the hover.
	chip.mouse_entered.connect(_rich_hover_enter.bind(chip, title, body, tag, accent, pop_scale))
	chip.mouse_exited.connect(_rich_hover_exit.bind(chip))
	# Chips are rebuilt wholesale (relic strip / potion bar refreshes) — never
	# leave an orphaned tooltip behind when the hovered chip is freed.
	chip.tree_exiting.connect(_rich_hover_clear_tip.bind(chip))


func _rich_hover_enter(chip: Control, title: String, body: String, tag: String,
		accent: Color, pop_scale: float) -> void:
	if not chip.has_meta("_rh_base_z"):
		chip.set_meta("_rh_base_z", chip.z_index)
	chip.pivot_offset = chip.size * 0.5
	chip.z_index = 100
	_rich_hover_scale(chip, Vector2(pop_scale, pop_scale), 0.14, Tween.TRANS_BACK)
	_rich_hover_clear_tip(chip)
	var tip := _build_rich_tip(title, body, tag, accent)
	# Host the tip in the chip's own canvas so coordinates line up 1:1: the
	# nearest CanvasLayer ancestor (combat HUD rides layer 12 — a viewport-root
	# tip would render UNDER it), else the chip's viewport root. Never a child
	# of the chip itself: ancestor clip_contents (scroll lists) would crop it.
	var host: Node = null
	var walk: Node = chip.get_parent()
	while walk != null:
		if walk is CanvasLayer:
			host = walk
			break
		walk = walk.get_parent()
	if host == null:
		host = chip.get_viewport()
	if host == null:
		tip.free()
		return
	host.add_child(tip)
	# Beside the chip's popped silhouette, right by default, flipped left when
	# the right edge can't fit it (enemy-rail side), clamped on screen.
	var r := chip.get_global_rect()
	var vp := chip.get_viewport_rect().size
	var grow_x := r.size.x * 0.5 * maxf(pop_scale - 1.0, 0.0)
	var tx := r.position.x + r.size.x + grow_x + 12.0
	if tx + tip.size.x > vp.x - 8.0:
		tx = r.position.x - grow_x - 12.0 - tip.size.x
	var ty := clampf(r.position.y + r.size.y * 0.5 - tip.size.y * 0.5,
		8.0, maxf(8.0, vp.y - tip.size.y - 8.0))
	tip.position = Vector2(maxf(8.0, tx), ty)
	chip.set_meta("_rh_tip", tip)
	tip.modulate.a = 0.0
	var tw := tip.create_tween()
	tw.tween_property(tip, "modulate:a", 1.0, 0.10)


func _rich_hover_exit(chip: Control) -> void:
	chip.z_index = int(chip.get_meta("_rh_base_z", 0))
	_rich_hover_scale(chip, Vector2.ONE, 0.10, Tween.TRANS_QUAD)
	_rich_hover_clear_tip(chip)


func _rich_hover_scale(chip: Control, target: Vector2, dur: float,
		trans: Tween.TransitionType) -> void:
	# has_meta guard: get_meta with a null default still raises an error.
	var old = chip.get_meta("_rh_tween") if chip.has_meta("_rh_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := chip.create_tween()
	tw.tween_property(chip, "scale", target, dur) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	chip.set_meta("_rh_tween", tw)


func _rich_hover_clear_tip(chip: Control) -> void:
	if not chip.has_meta("_rh_tip"):
		return
	var tip = chip.get_meta("_rh_tip")
	if tip != null and is_instance_valid(tip):
		(tip as Node).queue_free()
	chip.remove_meta("_rh_tip")


func _build_rich_tip(title: String, body: String, tag: String, accent: Color) -> Control:
	# Fixed-width ink-board plaque, sized by FONT METRICS up front — autowrap
	# Labels report garbage minimum heights until layout settles (same trap
	# fit_tile_height documents), and a hover tip can't wait a frame to size.
	const TIP_W := 320.0
	const PAD := 14.0
	var wrap_w := TIP_W - PAD * 2.0
	var tip := Panel.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 101
	tip.add_theme_stylebox_override("panel", make_panel_style(
		Color(0.088, 0.064, 0.048, 0.97), Color(0.55, 0.44, 0.24, 1.0), 1, 5, true))
	var f_title: Font = font_title if font_title != null else ThemeDB.fallback_font
	var f_body: Font = font_body if font_body != null else ThemeDB.fallback_font
	var y := PAD - 2.0
	y += _tip_add_line(tip, title, f_title, 21, accent, PAD, y, wrap_w)
	if tag != "":
		y += 1.0
		# Caption register (16px, deliberate): a type tag, not reading text.
		y += _tip_add_line(tip, tag, f_body, 16, Color(0.62, 0.55, 0.42, 1.0), PAD, y, wrap_w)
	y += 7.0
	var rule := ColorRect.new()
	rule.color = Color(GILT.r, GILT.g, GILT.b, 0.30)
	rule.position = Vector2(PAD, y)
	rule.size = Vector2(wrap_w, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.add_child(rule)
	y += 8.0
	y += _tip_add_line(tip, body, f_body, 18, IVORY, PAD, y, wrap_w)
	tip.size = Vector2(TIP_W, y + PAD - 2.0)
	return tip


func _tip_add_line(tip: Control, text: String, f: Font, fs: int, color: Color,
		x: float, y: float, wrap_w: float) -> float:
	# One manually-placed wrapped label; returns its measured height. Wrap flags
	# must match the label's AUTOWRAP_WORD or the measurement undershoots.
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	var ms := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs, -1, brk)
	var lines := maxi(1, int(round(ms.y / f.get_height(fs))))
	var h := ms.y + float(lines) * 3.0
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(wrap_w, h)
	tip.add_child(lbl)
	return h


func make_relic_chip(rid: String, size: int = 40) -> Panel:
	# Ornate framed chip for a relic icon — used by the HUD strip, shop cards,
	# the starting-relic-pick tiles, and the main-menu relic list. The frame is
	# a dark backing + gilt rim + tier-tinted shadow halo (boss=purple,
	# combat=warm bronze, utility=green, starting=gold) for at-a-glance rarity
	# the way WoW item borders cue quality. SVG silhouettes get the gilt tint
	# they were designed for; painted PNGs render at full color.
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(size, size)
	# PASS, not STOP: the chip still sees hover (rich tip below) but no longer
	# eats clicks meant for a parent tile (shop relic cards had a dead click
	# zone exactly over the icon).
	chip.mouse_filter = Control.MOUSE_FILTER_PASS

	var r := RelicDB.get_relic(rid)
	# StS-style hover: pop the chip out + show name/tier/rules beside it.
	attach_rich_hover(chip, r.get("name", rid), r.get("desc", ""),
		RELIC_TIER_TAGS.get(str(r.get("tier", "")), ""), RelicDB.get_tier_color(rid))

	var tier_color: Color = RelicDB.get_tier_color(rid)
	var radius: int = max(4, int(round(size * 0.14)))
	var rim: int = 2 if size < 56 else 3

	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	frame.border_color = GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		frame.set(k, rim)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		frame.set(k, radius)
	# Tier-tinted glow halo — the WoW-quality cue. Stronger on bigger chips.
	# Kept subtle: at 0.55 alpha the gold starting-tier halo was the single
	# brightest element on the combat screen (verified on a 1080p capture),
	# outshining the board it sits beside. A quality cue should murmur.
	frame.shadow_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.30)
	frame.shadow_size = max(3, int(round(size * 0.12)))
	chip.add_theme_stylebox_override("panel", frame)

	# Inner highlight ring — a second stylebox layered on a transparent Panel
	# child gives the frame a "two-tone metal" look (bright gilt outside, dim
	# inner shadow) without baking the icon's edges into the rim.
	var inner_ring := Panel.new()
	inner_ring.anchor_left = 0.0
	inner_ring.anchor_right = 1.0
	inner_ring.anchor_top = 0.0
	inner_ring.anchor_bottom = 1.0
	inner_ring.offset_left = rim
	inner_ring.offset_right = -rim
	inner_ring.offset_top = rim
	inner_ring.offset_bottom = -rim
	inner_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0, 0, 0, 0)
	inner_style.border_color = Color(0.0, 0.0, 0.0, 0.55)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		inner_style.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		inner_style.set(k, max(2, radius - 1))
	inner_ring.add_theme_stylebox_override("panel", inner_style)
	chip.add_child(inner_ring)

	var icon: Texture2D = RelicDB.get_relic_icon(rid)
	if icon != null:
		var inset: int = rim + 2
		var icon_clip := Control.new()
		icon_clip.clip_contents = true
		icon_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_clip.offset_left = inset
		icon_clip.offset_right = -inset
		icon_clip.offset_top = inset
		icon_clip.offset_bottom = -inset
		icon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon_clip)
		var tex := TextureRect.new()
		tex.texture = icon
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Painted icons are full-scene squares with a baked-in outer glow and
		# scenery behind the subject; rendered 1:1 at chip size the glow reads
		# as a UI highlight ring and the scenery turns to mud. Overscan past
		# the canvas edge so the subject fills the chip and the baked frame
		# stays outside the clip. SVG silhouettes render 1:1 with gilt tint.
		if RelicDB.is_painted_icon(rid):
			var over: float = float(size) * 0.16
			tex.offset_left = -over
			tex.offset_right = over
			tex.offset_top = -over
			tex.offset_bottom = over
		else:
			tex.modulate = GILT
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_clip.add_child(tex)
	else:
		var letter := Label.new()
		letter.text = r.get("name", "?").substr(0, 1).to_upper()
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", max(14, int(size * 0.45)))
		letter.add_theme_color_override("font_color", GILT)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font_display:
			letter.add_theme_font_override("font", font_display)
		chip.add_child(letter)
	return chip


func make_potion_chip(pid: String, size: int = 40) -> Panel:
	# Potion sibling of make_relic_chip. The painted potion art is a full-bleed
	# square painting, so it MUST sit behind the gilt frame — otherwise the
	# painting's own warm background swallows the rim and the picture reads as
	# sitting on top of the frame (reported 2026-07-08). Layering back → front:
	#   1. dark well + accent glow halo (base panel)
	#   2. the clipped art (no overscan — the old 16% zoom is what spilled it out)
	#   3. the metal frame + inner keyline, drawn LAST so the border mats the art.
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(size, size)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS

	var p := PotionDB.get_potion(pid)
	var accent: Color = p.get("color", GILT)
	attach_rich_hover(chip, p.get("name", pid), p.get("desc", ""), "POTION", accent)

	var radius: int = max(4, int(round(size * 0.14)))
	# A frame you can actually see: scale the gilt band with the chip instead of a
	# fixed hairline (a 3px rim on a 96px tile vanishes under a full-bleed
	# painting). Small chips still floor at 3px.
	var rim: int = max(3, int(round(size * 0.055)))

	# 1. Back — dark well + accent halo. No border here; the frame overlay owns
	# the metal edge so it can be drawn on TOP of the art.
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		base.set(k, radius)
	base.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
	base.shadow_size = max(3, int(round(size * 0.12)))
	chip.add_theme_stylebox_override("panel", base)

	# 2. Middle — the painted art, clipped inside the frame footprint (inset by
	# the rim so its edge tucks under the metal). Square art in a square clip
	# fills exactly under STRETCH_KEEP_ASPECT_COVERED, no overscan needed.
	var icon: Texture2D = PotionDB.icon_for(pid)
	if icon != null:
		var icon_clip := Control.new()
		icon_clip.clip_contents = true
		icon_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_clip.offset_left = rim
		icon_clip.offset_right = -rim
		icon_clip.offset_top = rim
		icon_clip.offset_bottom = -rim
		icon_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon_clip)
		var tex := TextureRect.new()
		tex.texture = icon
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		if not PotionDB.is_painted_icon(pid):
			tex.modulate = accent          # tint the white game-icons silhouette
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_clip.add_child(tex)

	# 3. Front — the metal frame, drawn last so the gilt band sits over the
	# picture's edge, plus the dark inner keyline (two-tone metal look).
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0, 0, 0, 0)
	fstyle.border_color = GILT
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		fstyle.set(k, rim)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		fstyle.set(k, radius)
	frame.add_theme_stylebox_override("panel", fstyle)
	chip.add_child(frame)

	var inner_ring := Panel.new()
	inner_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner_ring.offset_left = rim
	inner_ring.offset_right = -rim
	inner_ring.offset_top = rim
	inner_ring.offset_bottom = -rim
	inner_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0, 0, 0, 0)
	inner_style.border_color = Color(0.0, 0.0, 0.0, 0.55)
	for k in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		inner_style.set(k, 1)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		inner_style.set(k, max(2, radius - 1))
	inner_ring.add_theme_stylebox_override("panel", inner_style)
	chip.add_child(inner_ring)
	return chip


# ── Shared stacked-tile skeleton ─────────────────────────────────────────────
# Both relic cards (make_relic_card, used on Shop/Reward/Treasure) and Shop's
# service slots (potion/removal) are the same shape: an empty Button so the whole
# tile is one hit target, with a centered, mouse-ignoring VBox inset from the
# edges that callers stack icon + text into. This builds that skeleton so the two
# tile builders can't drift in layout. Callers add their own styleboxes + content.
# Returns {"button": Button, "col": VBoxContainer}.
func make_tile_skeleton(min_size: Vector2, separation: int = 4) -> Dictionary:
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 8
	col.offset_bottom = -8
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", separation)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)
	return {"button": btn, "col": col}


## LEVEL A ROW OF TILES, so peers can be compared rather than merely read.
##
## `fit_tile_height` closes each box onto ITS OWN content, which is right for a
## lone tile and wrong for a row: two relic offers whose rules text differs by a
## line get different heights, and an HBox child set SHRINK_CENTER then centres
## each one separately — so the icons sit at different heights, the names sit at
## different heights, and nothing in the row shares a baseline. (Measured on the
## General's reward: Quartermaster's Chest against Pen Nib put 23px between two
## titles that are the same kind of thing.) It is the C30 class exactly — every
## tile passes every test applied to it alone, and the row still looks wrong.
##
## Raise them all to the tallest instead. No await: `fit_tile_height` computes
## from font metrics synchronously, so the heights are final the moment the
## tiles are built.
##
## EQUAL BOXES ARE ONLY HALF OF IT. `make_tile_skeleton` centres its inner column
## (right for a lone tile, where the content should sit in the middle of its
## plate), so levelling the boxes alone still centres a two-line tile's whole
## stack against a four-line one and leaves the icons exactly as far apart as
## they started. The levelled row top-aligns as well, which is what puts the
## icons and the names on a shared baseline and lets only the rules text — the
## one thing that genuinely differs — run longer on one side.
func level_tile_row(tiles: Array) -> void:
	var tallest := 0.0
	for t in tiles:
		if t is Control:
			tallest = maxf(tallest, (t as Control).custom_minimum_size.y)
	if tallest <= 0.0:
		return
	for t in tiles:
		if not (t is Control):
			continue
		var c := t as Control
		c.custom_minimum_size = Vector2(c.custom_minimum_size.x, tallest)
		for ch in c.get_children():
			if ch is VBoxContainer:
				(ch as VBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
				break


func fit_tile_height(btn: Button, col: VBoxContainer) -> void:
	# The tile skeleton's inner VBox is anchored FULL_RECT, so the Button's min
	# size never grows with content — a long autowrapped body printed straight
	# through the bottom border (the shop's potion tile clipped its price line).
	# Measure the stacked content at the tile's known wrap width and grow the
	# button min-height to fit. Synchronous + explicit (font metrics, not
	# container minimums): autowrap Labels report garbage minimum heights until
	# layout settles their width, so signal-driven growth mis-fires.
	var wrap_w: float = btn.custom_minimum_size.x - 20.0  # col side insets
	var sep: float = col.get_theme_constant("separation")
	var need := 16.0  # col top+bottom insets
	var first := true
	for ch in col.get_children():
		if not (ch is Control) or not (ch as Control).visible:
			continue
		var h: float
		if ch is Label and (ch as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			var l := ch as Label
			var f: Font = l.get_theme_font("font")
			var fs: int = l.get_theme_font_size("font_size")
			# Mirror the label's own break flags: WORD_SMART balances lines
			# (BREAK_ADAPTIVE), which wraps EARLIER than plain word-bound —
			# measuring without it undershoots by a whole line on long bodies.
			var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			if l.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
				brk |= TextServer.BREAK_ADAPTIVE
			var ms := f.get_multiline_string_size(l.text,
				HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs, -1, brk)
			var lines := maxi(1, int(round(ms.y / f.get_height(fs))))
			# Per-line slack: the Label's real line boxes run a few px taller
			# than raw font metrics (spacing + fractional rounding). Slight
			# overshoot is invisible on a centered tile; undershoot clips.
			h = ms.y + float(lines) * (float(l.get_theme_constant("line_spacing")) + 3.0) + 6.0
		else:
			h = (ch as Control).get_combined_minimum_size().y
		if not first:
			need += sep
		first = false
		need += h
	if need > btn.custom_minimum_size.y:
		btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, need)
	# NOTE: do NOT try to refine this with a col.resized/get_combined_minimum_size
	# hook — autowrapped Labels report garbage minimum heights until their own
	# width settles (a frame after the col's), and a grow-only hook that reads
	# one bogus pass balloons the tile permanently (seen: 2000px-tall tiles).


## `hover_desc` = the shelf mode (Shop). The description leaves the tile and
## moves to the shared rich-hover tip, so every tile on the row keeps EXACTLY
## the height it was asked for and the price sits on one shared baseline. A
## shelf of wares whose prices float to four different heights because one relic
## has a six-line rule is the thing this fixes; pick-one-of-three screens
## (Reward/Treasure) still want the text inline and leave this false.
## NOTE: hover_desc owns `scale` (it pops the tile itself) — do NOT also call
## hover_lift on the returned button, they would fight over the same property.
func make_relic_card(rid: String, bg: Color, min_size: Vector2 = Vector2(220, 172),
		price: int = -1, hover_desc: bool = false) -> Button:
	# A relic "card" button: gilt-trimmed panel with the relic's icon stacked
	# above its name + description (and an optional price line for the shop).
	# Built on the shared make_tile_skeleton (empty Button + centered VBox) so the
	# whole tile is one hit target and the icon gets a controlled size — the source
	# SVGs are 512px, so they can't be dropped into Button.icon directly. The
	# icon comes from RelicDB.get_relic_icon by convention; if it isn't imported
	# yet the card just renders text-only instead of breaking.
	var r := RelicDB.get_relic(rid)
	var skel := make_tile_skeleton(min_size, 3)
	var btn: Button = skel.button
	btn.tooltip_text = "%s — %s" % [r.get("name", rid), r.get("desc", "")]
	var normal := make_btn_style(bg, GILT, 10)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as ChartPanelStyle
	hover.bg_color = bg.lightened(0.15)
	hover.border_color = GILT_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as ChartPanelStyle
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as ChartPanelStyle
	disabled.bg_color = bg.darkened(0.40)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)

	var col: VBoxContainer = skel.col

	# The relic is the hero of its tile: the icon scales with the tile
	# instead of sitting at a fixed 56px — on the Reward screen's 340×300
	# choice tiles that's ~114px of painted relic, on the Shop's shorter
	# tiles proportionally less. Growing the BOX without growing the object
	# just made the tiles emptier (the 220×172 → 340×300 bump proved it).
	var icon_px := clampi(int(min_size.y * 0.38), 56, 128)
	var chip := make_relic_chip(rid, icon_px)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var name_lbl := make_label(r.get("name", rid), 18, KEYWORD_GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)
	if not hover_desc:
		var desc_lbl := make_label(r.get("desc", ""), 16, IVORY)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(desc_lbl)
	if price >= 0:
		var price_lbl := make_label("— %dg —" % price, FONT_BODY, GILT)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(price_lbl)
	if hover_desc:
		# Fixed height by construction: never measure content, never grow.
		attach_rich_hover(btn, String(r.get("name", rid)), String(r.get("desc", "")),
			"RELIC", GILT, 1.03)
		return btn
	fit_tile_height(btn, col)
	return btn


# ── How-To-Play overlay (shared by MapView + MainMenu) ───────────────────────
# Single source of truth for the campaign primer + keyword glossary. The two
# screens used to build their own near-identical copies, which drifted ("Play"
# vs "Place creatures", different combat wording). Now both call this.
const HOW_TO_PLAY_PRIMER := [
	["The goal", "Cross three acts and defeat each rival lord. If your hero reaches 0 HP, the run ends and you start a new one."],
	["Each round", "Refill your hand and Command, then play cards. End your turn to resolve both sides' attacks and begin the next round."],
	["Command", "Command pays for creatures and spells. You start each turn with 3. Up to 2 unspent Command carries into your next turn."],
	["Your hand", "Cards stay in your hand between turns. Each turn refills it to 5. Right-click up to 2 cards to mark them for discard when the turn ends."],
	# THE BACK ROW IS NOT A BENCH. "Front guards back" is the model this line has
	# to kill: both rows attack every round, so a player who reads the front row
	# as the fighting one and the back row as a reserve throws away four of their
	# eight slots. Stated as a count first (all 8 fight), because that is the fact
	# a player can act on; the strike order is the qualifier, not the rule.
	["The board", "Each side has 4 lanes with a front and a back slot. All 8 slots fight: both rows attack every round. The front row attacks first and is attacked first — the back row is not a reserve."],
	# "Swift creatures can attack immediately" was false in the way that costs a
	# game: _can_reach_face returns `ready_to_swing or has_keyword("charge")`, so a
	# Swift body on its arrival round breaks BODIES and cannot touch the enemy
	# face. Charge is the one keyword that buys that. The strike-back clause is the
	# other half nothing had stated — _defender_is_mustering arms the counter in
	# solo, so a creature still forming up is not a free kill.
	["New creatures", "A creature played this round is Forming Up: it cannot start an attack until next round, though it still strikes back if hit. Swift lets it hit a creature at once, but not the enemy face — only Charge reaches the face on its arrival round."],
	["Forecast and combat", "Incoming shows the face damage headed your way. End your turn to start the clash: Swift strikes first, then both front rows, then both back rows. Round 1 has no clash — both sides are still forming up."],
	# OVERKILL IS UNIVERSAL AND WAS STATED NOWHERE ON THIS SCREEN. Piercing's
	# glossary entry names the spill, which reads as though the keyword owns it —
	# so a player learns that chump-blocking negates a whole attack, which stopped
	# being true in the 2026-07-28 blocker-economy pass. Both halves of
	# _apply_piercing_overflow are here: the spill stops at the body behind, and
	# only Piercing reads on, and only into an empty slot.
	["Killing blows", "A killing blow spills its extra damage into the creature standing behind the one it felled, then stops. Piercing carries that spill on to the enemy face when the slot behind is empty."],
	["Map sites", "Holds are normal fights; Generals are harder fights with relic rewards. Recruit Camps add cards. The Trader's Wagon buys and sells. Relic Caches show one relic: take it or take gold instead. Supply Caches offer a Forge, potions, or gold."],
	["Keywords and the Forge", "Hover keywords for their rules. At camp, Forge gives one card its permanent + version. The preview shows the exact change before you confirm."],
	["The boss gate", "A lord's keep starts locked. Win enough Holds to open the road. The map always shows how many Holds remain."],
	["Ascension and Daily Run", "Ascension adds the listed difficulty rules. Daily Run uses today's fixed hero, seed, and Battle Rule so everyone faces the same run."],
	["Skirmish modes", "Draft: pick 1 of 3 cards twenty times. Constructed: choose any 20 cards. Quick Battle: use random decks. Sealed: build 20 cards from a fixed pool."],
]
## Builds the full-screen "How to Play" overlay. Add the returned Control as a
## child; CLOSE or a click on the dim scrim dismisses it.
## `open_tab` — 0 opens on the campaign primer, 1 on the COACHING lesson list.
## Combat's `?` panel opens straight to 1: mid-fight is the moment of maximum
## confusion, and making someone land on the primer and find a tab first is the
## menu dive this screen exists to remove.
func make_how_to_play_overlay(open_tab: int = 0) -> Control:
	var gilt_b := Color(1.0, 0.88, 0.35, 1.0)
	var ivory_c := Color(0.96, 0.92, 0.78, 1.0)
	var ash_c := Color(0.62, 0.58, 0.52, 1.0)

	var scrim := ColorRect.new()
	scrim.name = "HowToPlayOverlay"
	scrim.color = Color(0.02, 0.015, 0.03, 0.90)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.z_index = 50
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			# Clicking out of a modal IS a retreat, so it gets the retreat's
			# voice. It used to close in silence while the CLOSE button beside
			# it spoke — the same act, two different answers.
			AudioBank.play_ui("back")
			scrim.queue_free())

	var panel := PanelContainer.new()
	# Manual anchors+offsets center a 1180×740 rect. set_anchors_preset(PRESET_CENTER)
	# leaves the offsets at 0, so the min-size panel grew down-and-right off the
	# bottom-right corner ("mostly off screen") — the same trap documented in
	# GameOver.gd. Half-extents: 1180/2 = 590, 740/2 = 370.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -590
	panel.offset_right = 590
	panel.offset_top = -370
	panel.offset_bottom = 370
	# Grow from the center so if content min-size exceeds the offset rect the
	# panel stays centered instead of drifting toward the bottom-right.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1180, 740)
	panel.add_theme_stylebox_override("panel", make_panel_style(
		Color(0.06, 0.05, 0.045, 0.99),
		Color(0.60, 0.51, 0.34, 0.95), 2, 6, true))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.add_child(panel)

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 28)
	panel.add_child(pad)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	pad.add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	outer.add_child(head)
	var title := make_label("HOW TO PLAY", FONT_HEADER, gilt_b)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := make_back_button("CLOSE", Vector2(120, 36), 16)
	close.pressed.connect(func(): scrim.queue_free())
	head.add_child(close)

	var rule := ColorRect.new()
	rule.color = Color(0.60, 0.51, 0.34, 0.55)
	rule.custom_minimum_size = Vector2(0, 2)
	outer.add_child(rule)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)

	# The field the columns are cut out of — the fade at each cut edge dissolves
	# into exactly this, so the text reads as running under the panel rather than
	# stopping at a hard line.
	var field := Color(0.06, 0.05, 0.045, 0.99)

	# LEFT — two pages behind one pair of tabs: the campaign primer, and the
	# COACHING page, which is the tutorial itself made readable and replayable.
	#
	# WHY THE MANUAL IS WHERE THE TUTORIAL GOES TO BE FOUND AGAIN. A lesson is
	# spent the instant it fires — one line, seven seconds, during your first
	# fight — and until now the only way back was a Settings button that wiped
	# every flag on the profile. That is not retrieval, it is a reset. NN/g's rule
	# for dismissible help is that dismissal and RECALL matter equally, and the
	# Game Accessibility Guidelines list replayable instructions as a standing
	# requirement rather than a nicety. So every lesson is printed here in full,
	# ticked if the player has met it, with its own button to have it back in
	# context — and this screen is already on the menu column and behind the map's
	# "?", so the path to it is one a player has walked before.
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.custom_minimum_size = Vector2(500, 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left_col)

	var left_wrap: Control = _htp_scroll_column(500.0, false, field)
	var basics := VBoxContainer.new()
	basics.add_theme_constant_override("separation", 10)
	basics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(left_wrap.get_node("Scroll") as ScrollContainer).add_child(basics)
	for entry in HOW_TO_PLAY_PRIMER:
		basics.add_child(_htp_primer_block(entry[0], entry[1], ivory_c))

	var coaching_wrap: Control = _htp_scroll_column(500.0, false, field)
	var coaching := VBoxContainer.new()
	coaching.add_theme_constant_override("separation", 10)
	coaching.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(coaching_wrap.get_node("Scroll") as ScrollContainer).add_child(coaching)
	_htp_fill_coaching_page(coaching, ivory_c, ash_c, gilt_b)

	var tabs := _htp_tab_row(
		["HOW THE CAMPAIGN WORKS", "COACHING"], [left_wrap, coaching_wrap],
		clampi(open_tab, 0, 1))
	left_col.add_child(tabs)
	left_col.add_child(left_wrap)
	left_col.add_child(coaching_wrap)
	left_wrap.visible = open_tab != 1
	coaching_wrap.visible = open_tab == 1

	var vrule := ColorRect.new()
	vrule.color = Color(0.50, 0.42, 0.28, 0.40)
	vrule.custom_minimum_size = Vector2(2, 0)
	vrule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(vrule)

	# RIGHT — keyword glossary, sourced live from KeywordEffects.
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right_col)
	right_col.add_child(make_label("KEYWORD GLOSSARY", FONT_SUBHEADER, gilt_b))
	right_col.add_child(make_label(
		"Keywords and combat status terms.", 15, ash_c))

	var gloss_wrap: Control = _htp_scroll_column(0.0, true, field)
	right_col.add_child(gloss_wrap)
	var gloss_scroll: ScrollContainer = gloss_wrap.get_node("Scroll")
	var gloss := VBoxContainer.new()
	gloss.add_theme_constant_override("separation", 9)
	gloss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gloss_scroll.add_child(gloss)
	# Not a real KeywordEffects entry — the muster delay has no keyword, so the
	# glossary has to state it by hand or the commonest "why did nothing happen"
	# in the game has no entry at all. It stops a body INITIATING, never
	# defending (Combat._defender_is_mustering), and that clause is the whole
	# difference between "wait a round" and "you just gave away a free kill".
	gloss.add_child(_htp_keyword_row("mustering", "Forming Up",
		"Cannot start an attack this round, but still strikes back if hit. Attacks normally from next round.",
		ivory_c))
	for key in KeywordEffects.KEYWORDS.keys():
		var kw: Dictionary = KeywordEffects.KEYWORDS[key]
		gloss.add_child(_htp_keyword_row(String(key),
			String(kw.get("display", key)), String(kw.get("desc", "")), ivory_c))

	return scrim


func _htp_scroll_column(min_w: float, expand_h: bool, field: Color) -> Control:
	# Both manual columns are longer than the panel, and the left one cuts
	# mid-sentence ("Marked cards are"). A hard edge under a hairline rail reads
	# as BROKEN TEXT, not as more text — the player has no reason to suspect a
	# scroll. Two cues fix it together: the present rail says the column moves,
	# and the fade at the cut says the sentence continues under the panel.
	#
	# A plain Control wraps the scroll rather than a container, because the fade
	# must sit OVER the scroll's clipped viewport — a container would lay both
	# children out as siblings in the same flow instead of stacking them.
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(min_w, 0)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if expand_h:
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	style_rail_scrollbar(scroll)
	wrap.add_child(scroll)

	var grad := Gradient.new()
	grad.set_color(0, Color(field.r, field.g, field.b, 0.0))
	grad.set_color(1, Color(field.r, field.g, field.b, 1.0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 4
	tex.height = 64
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)

	var fade := TextureRect.new()
	fade.texture = tex
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.visible = false
	fade.anchor_left = 0.0
	fade.anchor_right = 1.0
	fade.anchor_top = 1.0
	fade.anchor_bottom = 1.0
	fade.offset_top = -52
	# Stop short of the rail: veiling the slider would undo the other half of the
	# cue at exactly the moment the fade is telling the player to use it.
	fade.offset_right = -15
	wrap.add_child(fade)

	# The fade is a PROMISE of more text, so it must be honest: hidden at the
	# bottom of the travel and hidden when the column doesn't overflow at all.
	var bar := scroll.get_v_scroll_bar()
	var sync := func() -> void:
		if not is_instance_valid(fade) or not is_instance_valid(bar):
			return
		var span: float = bar.max_value - bar.page
		fade.visible = span > 2.0 and bar.value < span - 2.0
	bar.value_changed.connect(func(_v: float): sync.call())
	bar.changed.connect(func(): sync.call())
	wrap.resized.connect(func(): sync.call())
	return wrap


## A pair of page tabs over a shared column. Exactly one page is visible; the
## chosen tab loses its underline-and-dim so the state reads without colour
## alone (GAG: no essential information by a fixed colour).
func _htp_tab_row(labels: Array, pages: Array, active: int = 0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var buttons: Array[Button] = []
	var repaint := func(active: int) -> void:
		for i in buttons.size():
			var b: Button = buttons[i]
			if not is_instance_valid(b):
				continue
			b.add_theme_color_override("font_color",
				Color(1.0, 0.88, 0.40) if i == active else Color(0.60, 0.55, 0.46))
			# The chosen tab is the one carrying the rule beneath it. A tab strip
			# distinguished only by a brighter gold fails for a player who cannot
			# separate the two golds.
			var rule: Control = b.get_node_or_null("TabRule")
			if rule != null:
				rule.visible = i == active
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", FONT_SUBHEADER)
		if font_display:
			b.add_theme_font_override("font", font_display)
		var rule := ColorRect.new()
		rule.name = "TabRule"
		rule.color = Color(0.95, 0.78, 0.34, 0.85)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.anchor_left = 0.0
		rule.anchor_right = 1.0
		rule.anchor_top = 1.0
		rule.anchor_bottom = 1.0
		rule.offset_top = -2
		b.add_child(rule)
		var idx := i
		b.pressed.connect(func() -> void:
			for j in pages.size():
				if is_instance_valid(pages[j]):
					pages[j].visible = j == idx
			repaint.call(idx))
		buttons.append(b)
		row.add_child(b)
	repaint.call(clampi(active, 0, maxi(buttons.size() - 1, 0)))
	return row


## THE COACHING PAGE — every lesson in the game, printed in full, ticked if met,
## and replayable one at a time.
##
## THE DEDUPE RULE IS LOAD-BEARING. Several lessons share one underlying flag —
## the three steps of the guided fight are one walkthrough and cannot be replayed
## apart — so a replay button is offered ONCE per distinct flag. Keyed off the
## flag rather than off a hand-listed set of ids, so a future lesson that joins an
## existing group inherits the behaviour instead of shipping a second button that
## silently does the same thing as the first.
func _htp_fill_coaching_page(box: VBoxContainer, ivory: Color, ash: Color,
		gilt: Color) -> void:
	var intro := make_label(
		"Every lesson the game will teach you. Replay one to have it offered "
		+ "again the next time it is relevant.", 16, ash)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(460, 0)
	box.add_child(intro)

	var all_btn := make_themed_button("REPLAY ALL", Color(0.34, 0.22, 0.10),
		Vector2(170, 32), 14, "Offer every lesson again, from the first fight.")
	# SHRINK_BEGIN or the ScrollContainer stretches it to the full column and its
	# right end goes under the scroll rail — shot-caught, and the same fault the
	# state chips below had.
	all_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(all_btn)

	var rows: Array[Dictionary] = []
	var claimed: Dictionary = {}
	for group in TutorialDB.GROUP_ORDER:
		var ids := TutorialDB.ids_in_group(group)
		if ids.is_empty():
			continue
		box.add_child(make_label(
			String(TutorialDB.GROUP_TITLES.get(group, group)), 18, gilt))
		for id in ids:
			# The replay control goes to the first lesson standing on a given flag.
			var flag := TutorialDB.legacy_flag(id)
			var owns_button: bool = flag == "" or not claimed.has(flag)
			if flag != "":
				claimed[flag] = true
			rows.append(_htp_coaching_row(box, id, owns_button, ivory, ash))

	var refresh := func() -> void:
		for r in rows:
			var state: Label = r.get("state")
			var btn: Button = r.get("button")
			var seen: bool = UserSettings != null \
				and UserSettings.lesson_seen(String(r.get("id", "")))
			if is_instance_valid(state):
				# A word, not a tick alone — a glyph in one colour is exactly the
				# signal GAG says may not stand by itself.
				state.text = "SEEN  ✓" if seen else "NOT YET SEEN"
				state.modulate = Color(0.66, 0.78, 0.56) if seen \
					else Color(0.80, 0.72, 0.52)
			if btn != null and is_instance_valid(btn):
				btn.disabled = not seen
	refresh.call()

	all_btn.pressed.connect(func() -> void:
		if UserSettings != null:
			UserSettings.reset_tutorials()
		claim_pop(all_btn)
		refresh.call())
	for r in rows:
		var btn: Button = r.get("button")
		if btn == null or not is_instance_valid(btn):
			continue
		var lesson_id := String(r.get("id", ""))
		btn.pressed.connect(func() -> void:
			if UserSettings != null:
				UserSettings.replay_lesson(lesson_id)
			claim_pop(btn)
			refresh.call())


func _htp_coaching_row(box: VBoxContainer, id: String, with_button: bool,
		ivory: Color, ash: Color) -> Dictionary:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(entry)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(head)
	var title := make_label(TutorialDB.title(id), 18, Color(0.92, 0.80, 0.50, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	# 15px: a caption chip riding a bigger element — COPY_STYLE §11's middle
	# register and its floor. It states live state, so it may not go lower.
	var state := make_label("", 15, ash)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(state)
	# THE RAIL GUTTER. The column's ScrollContainer stretches this row to the FULL
	# wrap width, but `_htp_scroll_column` floats the scrollbar over the last ~15px
	# of it — so a right-aligned chip lands underneath the rail and loses its last
	# letter ("NOT YET SEE"). The body text below never hits this because it is
	# capped at 460; the head is not, so it needs the gutter spelled out.
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(22, 0)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gutter)

	# THE BODY IS THE LESSON'S OWN TEXT, not a paraphrase — the whole point of the
	# registry is that there is one copy of each sentence. `{n}` is filled with the
	# printed default here: this page is read outside a fight, where there is no
	# live cap to read, and a raw token on the page would be a bug on screen.
	var body := make_label(TutorialDB.body(id, {"n": 2}), 16, ivory)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(460, 0)
	entry.add_child(body)

	var btn: Button = null
	if with_button:
		btn = make_themed_button("SHOW AGAIN", Color(0.26, 0.20, 0.12),
			Vector2(150, 28), 14, "Offer this lesson again when it next applies.")
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		entry.add_child(btn)
	return {"id": id, "state": state, "button": btn}


func _htp_primer_block(heading: String, body: String, ivory: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(make_label(heading, 18, Color(0.92, 0.80, 0.50, 1.0)))
	var b := make_label(body, 16, ivory)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(460, 0)
	box.add_child(b)
	return box


func _htp_keyword_row(key: String, name: String, desc: String, ivory: Color) -> Control:
	# Frameless glossary entry: the keyword's white-silhouette device in gilt,
	# name + body beside it, a hairline rule below. Replaced the boxed chip
	# rows — a column of outlined rectangles read as a settings form, not a
	# war manual (feedback: no flat rectangles).
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(row)

	# Device column — fixed box so text always aligns whether or not a
	# keyword ships a device; icon-less keywords take the house diamond.
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(34, 34)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_box)
	var device: Texture2D = get_keyword_icon(key)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if device != null:
		icon.texture = device
		icon.modulate = Color(0.95, 0.82, 0.48, 0.95)
	else:
		icon.texture = tex_icon_diamond
		icon.offset_left = 9
		icon.offset_right = -9
		icon.offset_top = 9
		icon.offset_bottom = -9
		icon.modulate = Color(0.80, 0.68, 0.42, 0.70)
	icon_box.add_child(icon)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(make_label(name, 17, Color(0.95, 0.82, 0.48, 1.0)))
	var d := make_label(desc, 16, ivory)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.custom_minimum_size = Vector2(510, 0)
	v.add_child(d)

	# Hairline rule closes the entry — indented past the device column so
	# the rules read as ledger lines under the text.
	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.38, 0.26, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(rule)
	return entry


func style_thin_scrollbar(scroll: ScrollContainer) -> void:
	# Slim gilt grabber on an invisible track. The stock chunky grey
	# VScrollBar reads as engine chrome on every themed screen; this turns
	# it into a hairline that only asserts itself under the cursor.
	var bar := scroll.get_v_scroll_bar()
	var track := StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.72, 0.61, 0.38, 0.45)
	grab.set_corner_radius_all(2)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	bar.add_theme_stylebox_override("grabber", grab)
	var grab_hl: StyleBoxFlat = grab.duplicate()
	grab_hl.bg_color = Color(0.95, 0.82, 0.48, 0.75)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hl)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hl)
	bar.custom_minimum_size = Vector2(6, 0)


func style_rail_scrollbar(scroll: ScrollContainer, width: int = 11) -> void:
	# The hairline above is right for a side list you glance at and wrong for a
	# screen whose whole PURPOSE is scrolling (the compendium, the manual). There
	# the rail is the primary navigation, and a 6px grabber at 45% alpha on an
	# invisible track tells the player neither that the screen scrolls nor how
	# much of it is left. This is the same gilt-on-ink material, drawn as a real
	# fitting: a sunk groove with a solid gilt slider riding in it.
	var bar := scroll.get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.065, 0.052, 0.70)
	track.set_corner_radius_all(4)
	track.border_width_left = 1
	track.border_width_right = 1
	track.border_color = Color(0.62, 0.50, 0.34, 0.26)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.72, 0.61, 0.38, 0.82)
	grab.set_corner_radius_all(4)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	# Vertical margins set the grabber's MINIMUM height. Without them a
	# hundred-plus-tile gallery shrinks the slider to a few pixels of nub, which
	# is unclickable and reads as a speck of dirt on the groove.
	grab.content_margin_top = 11
	grab.content_margin_bottom = 11
	bar.add_theme_stylebox_override("grabber", grab)
	var grab_hl: StyleBoxFlat = grab.duplicate()
	grab_hl.bg_color = Color(0.96, 0.84, 0.50, 0.95)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hl)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hl)
	bar.custom_minimum_size = Vector2(width, 0)


# ═══════════════════════════════════════════
#  CARD DATA FORMATTERS
# ═══════════════════════════════════════════

static func format_keywords(data: Dictionary) -> String:
	if not data.has("keywords") or data.keywords.is_empty():
		return ""
	return ", ".join(data.keywords)


# ═══════════════════════════════════════════
#  LABEL FACTORY
# ═══════════════════════════════════════════

func make_label(text: String, font_size: int = FONT_BODY, color: Color = IVORY,
		outline: bool = false) -> Label:
	# Enforce the readability floor — callers asking for 13–15px get bumped to it.
	font_size = maxi(font_size, MIN_LABEL_SIZE)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	# Apply the body font so descriptions / labels use the game's typography
	# rather than Godot's default sans-serif. Headers (large sizes) get the
	# display font; small/medium sizes get body Nunito for readability.
	if font_size >= 22 and font_display:
		lbl.add_theme_font_override("font", font_display)
	elif font_body:
		lbl.add_theme_font_override("font", font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline:
		# Explicit, stronger outline for text over busy art / photo backgrounds.
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("outline_size", 3)
	elif font_size < 22:
		# Default legibility for body-sized text: at 13–18px a thin stroke is mostly
		# partial-alpha anti-alias pixels, so with NO edge it dissolves into a dark
		# panel and reads as semi-transparent (the "see-through small text" bug, e.g.
		# the net-lobby hint). A tight near-black outline wraps each glyph in opaque
		# pixels. 2px stays under the size where an MSDF outline floods letter
		# counters. Display-size text (≥22, thick Lilita) is already solid, so it's
		# left clean to preserve the title look. Callers that truly want no edge can
		# override outline_size back to 0.
		lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.85))
		lbl.add_theme_constant_override("outline_size", 2)
	return lbl


# ═══════════════════════════════════════════
#  RARITY HELPERS
# ═══════════════════════════════════════════

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"white": return RARITY_WHITE
		"common": return RARITY_COMMON
		"uncommon": return RARITY_UNCOMMON
		"rare": return RARITY_RARE
		"starter": return RARITY_STARTER
		_: return RARITY_COMMON


static func rarity_frame_trim(rarity: String) -> Color:
	# Marvel-Snap-style: each rarity has its own distinct frame hue, so the
	# frame itself is the rarity signal. Starter is muted, common warm, uncommon
	# cool blue, rare bright gold — readable at hand-thumbnail scale even
	# without looking at the gem.
	match rarity:
		"starter":  return FRAME_TRIM_STARTER
		"white":    return FRAME_TRIM_WHITE
		"common":   return FRAME_TRIM_COMMON
		"uncommon": return FRAME_TRIM_UNCOMMON
		"rare":     return FRAME_TRIM_RARE
		_:          return FRAME_TRIM_COMMON


# ─────────────────────────────────────────────────────────────────────────
#  Rarity name-plate palette — STS / Marvel Snap convention.
#  Replaces the old diamond rarity gem with a tint shift on the title plate
#  itself. Players read rarity from the banner's hue + the outer frame trim,
#  both of which scan instantly at thumbnail size. The previous gem competed
#  with the cost orb for the eye's attention; dropping it cleans the layout
#  and matches every modern card UI from STS to Hearthstone Battlegrounds.
# ─────────────────────────────────────────────────────────────────────────

static func rarity_plate_bg(rarity: String) -> Color:
	# Banner background — dark warmth shifted per rarity. All four kept near
	# the same luminance (~0.10) so the IVORY name text holds ~14:1 contrast
	# (AAA WCAG) across every rarity, with the hue being the only variable.
	match rarity:
		"starter":  return Color(0.182, 0.135, 0.082, 0.97)  # brass-shadow
		"white":    return Color(0.105, 0.132, 0.150, 0.97)  # cool blackened silver
		"common":   return Color(0.165, 0.118, 0.075, 0.97)  # neutral walnut
		"uncommon": return Color(0.082, 0.122, 0.220, 0.97)  # deep teal-blue
		"rare":     return Color(0.235, 0.165, 0.057, 0.97)  # warm dark gold
		_:          return Color(0.165, 0.118, 0.075, 0.97)


static func rarity_plate_border(rarity: String) -> Color:
	# Banner border — the saturated rarity hue. Stronger than rarity_plate_bg
	# so the 1-2 px outline pops as the actual rarity cue; the bg is the
	# supporting wash that ties the border to the rest of the card body.
	match rarity:
		"starter":  return Color(0.706, 0.631, 0.471, 0.95)  # brass
		"white":    return Color(0.920, 0.980, 1.000, 1.00)  # cold white
		"common":   return Color(0.831, 0.745, 0.541, 0.95)  # gilt
		"uncommon": return Color(0.450, 0.700, 1.000, 1.00)  # bright sky
		"rare":     return Color(1.000, 0.850, 0.260, 1.00)  # vivid gold
		_:          return Color(0.831, 0.745, 0.541, 0.95)


static func rarity_card_tint(rarity: String) -> Color:
	# Whole-card wash overlay. Kept very low alpha (<= 0.07) so the walnut
	# and parchment underneath stay the dominant surface — this just adds a
	# faint cool wash to uncommons and a faint warm wash to rares so the
	# card has a temperature signal alongside the banner colour.
	match rarity:
		"starter":  return Color(0.706, 0.631, 0.471, 0.04)
		"white":    return Color(0.720, 0.920, 1.000, 0.08)
		"common":   return Color(1.000, 1.000, 1.000, 0.00)  # no wash
		"uncommon": return Color(0.300, 0.500, 0.950, 0.07)
		"rare":     return Color(1.000, 0.780, 0.220, 0.07)
		_:          return Color(1.000, 1.000, 1.000, 0.00)


func _load_keyword_icons() -> void:
	# Game-icons.net SVGs, CC-BY 3.0 (credited in CREDITS.md), plus the
	# hand-authored redesign-keyword devices in the same white-silhouette kit.
	var keywords = [
		"armored", "swift", "thorns", "regenerate", "summon",
		"last_stand", "piercing", "sacrifice", "exhaust", "retain",
		"wither", "on_enter", "on_death", "adj_buff",
		# Redesign keywords — were silently icon-less (no bottom-margin device).
		"shield", "poison", "guardian", "doom", "rampage", "lifelink",
		"overrun", "formation", "structure", "sniper", "charge",
		# Transient statuses (not card keywords) — the battlefield tokens' live
		# status rail renders these while the effect holds.
		"frozen", "stunned", "mustering",
	]
	for k in keywords:
		var p = "res://assets/icons/keywords/%s.svg" % k
		if ResourceLoader.exists(p):
			_keyword_icons[k] = load(p)


func get_keyword_icon(keyword: String) -> Texture2D:
	return _keyword_icons.get(keyword, null)


## Colour-blind remap. Critical red/green (and blue/yellow) signals route through
## this so the `colorblind_mode` setting (UserSettings) actually changes what's on
## screen — it had ZERO consumers before. "off" returns the colour unchanged, so
## default players pay only one string compare. Strategy: shift the CONFUSABLE hue
## family to a distinguishable one (cheap + predictable; enough for stat/float
## legibility) rather than a full per-pixel daltonisation.
func cb_color(c: Color) -> Color:
	var mode: String = UserSettings.colorblind_mode
	if mode == "off":
		return c
	var h := c.h
	match mode:
		"deuteranopia", "protanopia":
			# Red↔green confusable. Keep red/orange; rotate the GREEN family
			# (hue ~75°..165°) toward blue so heal/buff greens read distinct
			# from damage reds.
			if h >= 0.21 and h <= 0.46:
				return Color.from_hsv(0.56, clampf(c.s, 0.4, 1.0),
					clampf(c.v * 1.04, 0.0, 1.0), c.a)
			return c
		"tritanopia":
			# Blue↔yellow confusable. Push the BLUE family (hue ~190°..260°)
			# toward teal/cyan so navy/cost blues don't collapse into greens.
			if h >= 0.52 and h <= 0.72:
				return Color.from_hsv(0.47, c.s, c.v, c.a)
			return c
	return c


# ═══════════════════════════════════════════
#  ATMOSPHERE SYSTEM
# ═══════════════════════════════════════════
# Layered mood lighting: vignette + gradient shader, ambient particles,
# decorative corner frame.  Each screen type gets its own palette.

const SCREEN_MOODS: Dictionary = {
	"main_menu": {
		"grad_inner": Color(0.10, 0.06, 0.08, 0.30),
		"grad_outer": Color(0.02, 0.01, 0.03, 0.65),
		"vignette": 0.55,
		"particle_color": Color(1.0, 0.82, 0.35, 0.45),
		"particle_alt": Color(1.0, 0.60, 0.20, 0.25),
		"particle_count": 35,
		"particle_speed": 12.0,
		"frame_color": Color(0.65, 0.50, 0.25, 0.28),
	},
	"map": {
		"grad_inner": Color(0.05, 0.04, 0.06, 0.20),
		"grad_outer": Color(0.01, 0.01, 0.02, 0.70),
		"vignette": 0.62,
		"particle_color": Color(0.78, 0.62, 0.30, 0.30),
		"particle_alt": Color(0.55, 0.42, 0.20, 0.15),
		"particle_count": 18,
		"particle_speed": 8.0,
		"frame_color": Color(0.35, 0.28, 0.15, 0.12),
	},
	"combat": {
		"grad_inner": Color(0.10, 0.06, 0.04, 0.25),
		"grad_outer": Color(0.02, 0.01, 0.01, 0.55),
		"vignette": 0.40,
		"particle_color": Color(1.0, 0.50, 0.18, 0.35),
		"particle_alt": Color(1.0, 0.28, 0.08, 0.20),
		"particle_count": 20,
		"particle_speed": 18.0,
		"frame_color": Color(0.50, 0.30, 0.15, 0.20),
	},
	"shop": {
		"grad_inner": Color(0.12, 0.09, 0.05, 0.30),
		"grad_outer": Color(0.03, 0.02, 0.01, 0.60),
		"vignette": 0.45,
		"particle_color": Color(1.0, 0.85, 0.40, 0.35),
		"particle_alt": Color(0.90, 0.70, 0.25, 0.20),
		"particle_count": 25,
		"particle_speed": 10.0,
		"frame_color": Color(0.65, 0.50, 0.22, 0.28),
	},
	"rest": {
		# Warmer, deeper inner — pulls eye toward the painted fire. Outer alpha
		# bumped 0.60 → 0.78 so we can drop the rest.tscn self_modulate dimmer
		# and let the painted background breathe; the vignette + alpha do the
		# darkening that the self_modulate used to do (badly).
		"grad_inner": Color(0.10, 0.06, 0.03, 0.10),
		"grad_outer": Color(0.02, 0.01, 0.01, 0.78),
		"vignette": 0.55,
		# Glowing embers rising from the fire — orange→red fade. Old palette
		# was green/teal "firefly" — wrong color for a campfire scene.
		"particle_color": Color(1.0, 0.55, 0.15, 0.55),
		"particle_alt": Color(1.0, 0.30, 0.05, 0.0),
		"particle_count": 32,
		"particle_speed": 28.0,
		"frame_color": Color(0.65, 0.45, 0.22, 0.30),
		# Ember anchor (Vector2 in 1600×900 space, or null for fullscreen).
		# Tuned to roughly where the campfire flame sits in rest_campfire.png.
		"particle_anchor": Vector2(820, 720),
		"particle_anchor_extents": Vector2(110, 30),
		# Slight upward bias + small spread so embers wobble up like real sparks.
		"particle_spread": 30.0,
		"particle_scale_min": 1.2,
		"particle_scale_max": 2.6,
	},
	"event": {
		"grad_inner": Color(0.08, 0.05, 0.12, 0.30),
		"grad_outer": Color(0.02, 0.01, 0.05, 0.65),
		"vignette": 0.50,
		"particle_color": Color(0.70, 0.50, 0.95, 0.35),
		"particle_alt": Color(0.55, 0.35, 0.80, 0.20),
		"particle_count": 22,
		"particle_speed": 10.0,
		"frame_color": Color(0.50, 0.35, 0.60, 0.25),
	},
	"reward": {
		"grad_inner": Color(0.12, 0.10, 0.06, 0.30),
		"grad_outer": Color(0.03, 0.02, 0.02, 0.60),
		"vignette": 0.45,
		"particle_color": Color(1.0, 0.90, 0.45, 0.45),
		"particle_alt": Color(1.0, 0.75, 0.25, 0.30),
		"particle_count": 30,
		"particle_speed": 14.0,
		"frame_color": Color(0.65, 0.55, 0.25, 0.30),
	},
	"game_over": {
		"grad_inner": Color(0.06, 0.03, 0.05, 0.25),
		"grad_outer": Color(0.01, 0.00, 0.02, 0.70),
		"vignette": 0.60,
		"particle_color": Color(0.60, 0.40, 0.40, 0.25),
		"particle_alt": Color(0.40, 0.25, 0.30, 0.15),
		"particle_count": 15,
		"particle_speed": 5.0,
		"frame_color": Color(0.40, 0.30, 0.25, 0.20),
	},
}


static var _atmosphere_shader: Shader = null


static func _get_atmosphere_shader() -> Shader:
	if _atmosphere_shader == null:
		_atmosphere_shader = Shader.new()
		_atmosphere_shader.code = ("shader_type canvas_item;\n"
			+ "uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;\n"
			+ "uniform vec4 grad_inner : source_color;\n"
			+ "uniform vec4 grad_outer : source_color;\n"
			+ "void fragment() {\n"
			+ "  vec2 uv = UV - 0.5;\n"
			+ "  float dist = length(uv) * 2.0;\n"
			+ "  float t = smoothstep(0.0, 1.3, dist);\n"
			+ "  vec4 grad = mix(grad_inner, grad_outer, t);\n"
			+ "  float vig = smoothstep(0.4, 1.4, dist) * vignette_strength;\n"
			+ "  float grain = fract(sin(dot(UV * 500.0, vec2(12.9898, 78.233))) * 43758.5453) * 0.015 - 0.0075;\n"
			+ "  vec3 col = grad.rgb * (1.0 - vig * 0.5) + grain;\n"
			+ "  float a = grad.a + vig * (1.0 - grad.a);\n"
			+ "  COLOR = vec4(col, a);\n"
			+ "}\n")
	return _atmosphere_shader


## Adds vignette + gradient overlay, ambient particles, and decorative frame.
## Call once in _ready() — survives _build_ui() if cleanup preserves "Atmosphere".
## `mood_override` keys merge over the screen_type's base mood — used by Rest.gd
## to tint the screen warmer (dusk) on first visit or cooler (night) on second.
static func add_atmosphere(parent: Control, screen_type: String,
		include_frame: bool = true, mood_override: Dictionary = {}) -> void:
	if parent.has_node("Atmosphere"):
		return
	var base: Dictionary = SCREEN_MOODS.get(screen_type, SCREEN_MOODS["main_menu"])
	var mood: Dictionary = base.duplicate()
	for k in mood_override:
		mood[k] = mood_override[k]

	var atm := Control.new()
	atm.name = "Atmosphere"
	atm.set_anchors_preset(Control.PRESET_FULL_RECT)
	atm.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# — Vignette + radial gradient (single shader ColorRect) —
	var vig_rect := ColorRect.new()
	vig_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_rect.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _get_atmosphere_shader()
	mat.set_shader_parameter("vignette_strength", mood.vignette)
	mat.set_shader_parameter("grad_inner", mood.grad_inner)
	mat.set_shader_parameter("grad_outer", mood.grad_outer)
	vig_rect.material = mat
	atm.add_child(vig_rect)

	# — Ambient floating particles —
	var particles := _make_ambient_particles(mood)
	var particles_on: bool = parent.get_node_or_null("/root/UserSettings").particles \
		if parent.is_inside_tree() else true
	particles.emitting = particles_on
	particles.visible = particles_on
	atm.add_child(particles)

	# — Decorative corner frame —
	if include_frame:
		var frame := _make_decorative_frame(mood.frame_color)
		atm.add_child(frame)

	# — Brightness overlay —
	# Fullscreen ColorRect that darkens (black @ low alpha) or lightens
	# (white @ low alpha) the rendered scene. Updates live via the
	# UserSettings.brightness_changed signal.
	var bright_rect := ColorRect.new()
	bright_rect.name = "BrightnessOverlay"
	bright_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bright_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bright_rect.z_as_relative = false
	bright_rect.z_index = 50  # above gameplay, below modal popups (z_index ~100+)
	_apply_brightness_to_rect(bright_rect)
	atm.add_child(bright_rect)
	if parent.is_inside_tree() and parent.get_node_or_null("/root/UserSettings") != null:
		var us = parent.get_node("/root/UserSettings")
		# The old guard tested the UNBOUND callable against a connection made with
		# `.bind(bright_rect)` — two different Callables, so `is_connected` was
		# always false and every screen entered stacked one more permanent
		# connection on the autoload's signal. Bind once, and drop the connection
		# with the rect it feeds (a static func's Callable outlives the ColorRect,
		# so nothing else ever cleans it up).
		var bright_cb: Callable = _on_brightness_changed_static.bind(bright_rect)
		if not us.brightness_changed.is_connected(bright_cb):
			us.brightness_changed.connect(bright_cb)
		bright_rect.tree_exiting.connect(func() -> void:
			if is_instance_valid(us) and us.brightness_changed.is_connected(bright_cb):
				us.brightness_changed.disconnect(bright_cb))

	parent.add_child(atm)
	# Slot right after Background (index 0) so UI builds on top
	parent.move_child(atm, 1)


static func _apply_brightness_to_rect(rect: ColorRect) -> void:
	if rect == null:
		return
	var b := 0.0
	var us = Engine.get_main_loop().root.get_node_or_null("UserSettings") if Engine.get_main_loop() != null else null
	if us != null:
		b = float(us.brightness)
	if b >= 0.0:
		# Brighter: white at low alpha
		rect.color = Color(1, 1, 1, clampf(b, 0.0, 0.4))
	else:
		# Darker: black at low alpha
		rect.color = Color(0, 0, 0, clampf(-b, 0.0, 0.4))


static func _on_brightness_changed_static(_value: float, rect: ColorRect) -> void:
	if rect != null and is_instance_valid(rect):
		_apply_brightness_to_rect(rect)


static func _make_ambient_particles(mood: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "AmbientMotes"
	p.emitting = true
	p.amount = mood.particle_count
	p.lifetime = 6.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	# Emit across the full viewport by default, but mood entries can pin the
	# emitter to a point (e.g. campfire) by setting `particle_anchor`. When set,
	# embers/sparks rise from that location instead of from the whole screen,
	# which is what sells "fire" vs "fireflies."
	var anchor = mood.get("particle_anchor", null)
	if anchor != null and anchor is Vector2:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		var ext: Vector2 = mood.get("particle_anchor_extents", Vector2(80, 24))
		p.emission_rect_extents = ext
		p.position = anchor
	else:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(800, 450)
		p.position = Vector2(800, 450)
	# Slow upward drift with lateral wobble. Spread tunable per mood — embers
	# want a tight cone (~30°), ambient motes a wide one (~60°).
	p.direction = Vector2(0, -1)
	p.spread = mood.get("particle_spread", 60.0)
	p.initial_velocity_min = mood.particle_speed * 0.5
	p.initial_velocity_max = mood.particle_speed
	p.gravity = Vector2(0, 0)
	p.linear_accel_min = -2.0
	p.linear_accel_max = 2.0
	# Size — embers are smaller than ambient motes; mood overrides the defaults.
	p.scale_amount_min = mood.get("particle_scale_min", 1.5)
	p.scale_amount_max = mood.get("particle_scale_max", 3.5)
	# Color ramp: transparent → glow → color-shift → transparent
	var c1: Color = mood.particle_color
	var c2: Color = mood.get("particle_alt", c1)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(c1.r, c1.g, c1.b, 0.0))
	gradient.set_color(1, Color(c2.r, c2.g, c2.b, 0.0))
	gradient.add_point(0.15, c1)
	gradient.add_point(0.7, c2)
	p.color_ramp = gradient
	return p


## ── ONE RULE PER EDGE, AND IT IS DRAWN (2026-09-18) ──
##
## This built the border out of TWELVE `ColorRect`s at TWO alphas — eight corner
## arms at `frame_color`, four connecting rules at half that, four corner dots —
## so every edge carried a HARD -46% value step where the arm met the rule.
## Measured on RUN SETUP: 0.151 for 48px, then 0.084, mid-run, on a straight
## line, EIGHT times round the page. Its cross-section was two rows at one value,
## and the "corner diamond dot" was an axis-aligned SQUARE, because a `ColorRect`
## in a static layout has no rotation available to it.
##
## It is now one drawn Control: `PageBorder` ramps the corner emphasis into the
## run instead of stepping it, gives the rule the house cross-section so the page
## edge and the frames on the page sit under one lamp, and draws the pips as real
## lit diamonds. The C32 anchoring lesson SURVIVES the rebuild and got shorter —
## it moved from anchors on twelve rects into `_draw` reading `size`, which IS
## the live canvas, so the border is right at any resolution and at every UI
## Scale with no resize handler and no `ProjectSettings` read. (`ProjectSettings`
## is static and the runtime canvas is not: at the 60% the settings screen
## offers, the canvas is 2667x1500 while it still reports 1600x900.)
static func _make_decorative_frame(frame_color: Color) -> Control:
	return PageBorder.make(frame_color)


# ═══════════════════════════════════════════
#  SCREEN TITLE  (label + decorative separator)
# ═══════════════════════════════════════════

func make_screen_title(text: String, color: Color = GILT_BRIGHT,
		font_size: int = FONT_TITLE) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", font_size)
	title.add_theme_color_override("font_color", color)
	title.add_theme_color_override("font_outline_color",
		Color(color.r, color.g, color.b, 0.25))
	title.add_theme_constant_override("outline_size", 6)
	if font_display:
		title.add_theme_font_override("font", font_display)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	# Every screen headline takes the letterpress strike from one place rather
	# than eight call sites. The screens still deal_in the whole title unit
	# (title + rule); this presses the WORD onto the page inside it.
	Motion.stamp_in(title, 0.06, Color(color.r * 1.20, color.g * 1.14, color.b * 0.92))

	# ── THE HEADLINE RULE (2026-07-30 — was line · diamond · line).
	#
	# This one function underlines EVERY screen title in the game, so the diamond
	# it used to set was the single most-repeated glyph in the build — the same
	# shape the settings panel spent on section breaks, dropdown markers, slider
	# thumbs and toggle knobs. Repeated that widely it stopped reading as an
	# ornament and started reading as furniture.
	#
	# What replaces it is not a deletion but a better device: a hairline that
	# FADES OUT at both ends instead of stopping dead. A hard-ended bar declares
	# two arbitrary endpoints and fights the centred title above it; a rule that
	# dissolves into the page has no endpoints to argue with, which is exactly why
	# engraved frontispieces have used it for centuries. It also costs one texture
	# instead of three nodes, and it suits a game whose whole visual fiction is a
	# document.
	var line_col := Color(color.r, color.g, color.b, 0.52)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_offset(1, 1.0)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	grad.add_point(0.5, line_col)

	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 190
	gtex.height = 1
	gtex.fill_from = Vector2(0.0, 0.0)
	gtex.fill_to = Vector2(1.0, 0.0)

	var rule := TextureRect.new()
	rule.texture = gtex
	rule.custom_minimum_size = Vector2(190, 1)
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE

	vbox.add_child(rule)
	return vbox


## Thin horizontal rule for section breaks.
static func make_separator(color: Color = GILT, width: float = 200.0) -> CenterContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(width, 1)
	line.color = Color(color.r, color.g, color.b, 0.20)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(line)
	return center


## Section heading in the chart's vocabulary: a centered caption flanked by two
## tan rules with a small diamond accent — the same furniture as make_screen_title
## but lighter, for sub-sections within a screen (e.g. the Shop's "Cards for Sale"
## / "Relics & Services" shelf labels). Reads as a ruled heading on the page
## instead of a stray floating Label. Returns an HBoxContainer; anchor/position it
## like any Control.
func make_section_divider(text: String, color: Color = GILT,
		font_size: int = FONT_SUBHEADER, rule_width: float = 90.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line_col := Color(color.r, color.g, color.b, 0.42)

	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(rule_width, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = line_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	# The two flanking diamonds are retired (2026-07-30). This device already
	# says "section" three times over — a rule on the left, a rule on the right,
	# and a centred caps label between them. The glyphs were a fourth statement
	# of the same thing, in the same shape the settings panel, every screen
	# title and every card corner was already printing. rule - LABEL - rule is
	# the clean form and reads as deliberate rather than decorated.

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("outline_size", 3)
	if font_display:
		lbl.add_theme_font_override("font", font_display)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(rule_width, 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.color = line_col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	return row


# ═══════════════════════════════════════════
#  ICON + LABEL STAT BADGE
# ═══════════════════════════════════════════

func make_icon_stat(icon: Texture2D, value: String, icon_tint: Color,
		font_size: int = 18) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.texture = icon
	tex.custom_minimum_size = Vector2(18, 18)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.modulate = icon_tint
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(tex)
	var lbl := Label.new()
	lbl.text = value
	# Heavy stat font (Cinzel Black via FontVariation) so battlefield numerals
	# match the hand-card stat orb numerals.
	if font_stat:
		lbl.add_theme_font_override("font", font_stat)
	elif font_body:
		lbl.add_theme_font_override("font", font_body)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox


## Creature art aliases and loaders moved to scripts/data/CardArtAliases.gd.
## Call CardArtAliases.try_load_creature_art() / try_load_spell_art() directly.


# ---------------------------------------------------------------------------
# Shared floating-text VFX
# ---------------------------------------------------------------------------
# Non-Combat scenes (Shop, Rest, Reward, Event) need the same "+N" / "-Ng"
# floating-number feedback Combat has, but Combat's spawn_floating_number is
# scene-local. Hosting one here means any scene can ask for a floating number
# at a screen position, parented to its own viewport so the label lifetime
# matches the scene.

func spawn_floating_text(host: Node, global_pos: Vector2, text: String,
		color: Color = Color(1, 1, 1), big: bool = false) -> void:
	if host == null or not is_instance_valid(host):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 34 if big else 22)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 200
	lbl.scale = Vector2(0.55, 0.55)
	lbl.position = global_pos + Vector2(-14, -8)
	lbl.pivot_offset = Vector2(14, 14)
	# Parent to a top-level CanvasLayer if the host has one named HUDLayer,
	# else parent directly to the host so it inherits its transform.
	var parent: Node = host
	if host.has_node("HUDLayer"):
		parent = host.get_node("HUDLayer")
	parent.add_child(lbl)
	var rise: float = -56.0 if not big else -78.0
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", lbl.position.y + rise, 0.78) \
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.78) \
		.set_ease(Tween.EASE_IN).set_delay(0.22)
	tw.chain().tween_callback(lbl.queue_free)


# ── Shared motion kit — the verbs live in scripts/ui/Motion.gd (R6) ───────
# Extracted 2026-07-16 (the painters/CombatNet precedent): every verb below
# is a same-name delegator so the shell screens' ~140 GameTheme.* call sites
# keep working unchanged. New motion verbs belong in Motion.gd; add a
# delegator here only when shell code will call it as GameTheme.<verb>.
# The stateful motion pieces — the trauma screen shake and the ink-wipe
# scene transition — genuinely live on this autoload (they need _process /
# a cached shader), further down this file.

func pulse_label(lbl: Label, flash_color: Color = Color(1.0, 0.85, 0.30)) -> void:
	Motion.pulse_label(lbl, flash_color)


func deal_in(ctrl: Control, delay: float = 0.0) -> void:
	Motion.deal_in(ctrl, delay)


func stamp_in(lbl: Control, delay: float = 0.0,
		bloom: Color = Color(1.0, 0.90, 0.52), shake: bool = false) -> void:
	Motion.stamp_in(lbl, delay, bloom, shake)


func hover_lift(btn: Control, lift: float = 1.03, target: Control = null,
		raise_z: bool = false) -> void:
	Motion.hover_lift(btn, lift, target, raise_z)


func punch(ctrl: Control, amount: float = 1.08) -> void:
	Motion.punch(ctrl, amount)


func fade_exit(ctrl: Control, dur: float = Motion.EXIT) -> void:
	Motion.fade_exit(ctrl, dur)


func claim_pop(ctrl: Control) -> void:
	Motion.claim_pop(ctrl)


func pocket_away(ctrl: Control, to_global: Vector2, dur: float = 0.32) -> void:
	# Await-forwarding: callers rebuild their UI after the tile lands.
	await Motion.pocket_away(ctrl, to_global, dur)


func tick_number(lbl: Label, from_val: int, to_val: int,
		template: String = "%d", dur: float = 0.5) -> void:
	Motion.tick_number(lbl, from_val, to_val, template, dur)


func write_on(rich_label, delay: float = 0.10) -> void:
	Motion.write_on(rich_label, delay)


func ken_burns(art: Control, pivot: Vector2, amount: float = 1.035,
		period: float = 16.0) -> void:
	Motion.ken_burns(art, pivot, amount, period)


func card_reveal(card: Control, delay: float, rarity: String = "",
		companion: Control = null) -> void:
	Motion.card_reveal(card, delay, rarity, companion)


func forge_strike(host: Control, target: Control) -> void:
	# Await-forwarding: the forge set-piece is a ~0.6s beat callers wait on.
	await Motion.forge_strike(host, target)


func writ_amend(host: Control, card: Control, stamp_text: String,
		accent: Color = Color(1.0, 0.84, 0.40), opts: Dictionary = {}) -> void:
	# Await-forwarding: the permanent-change stamp is a ~0.9s beat callers wait
	# on before rebuilding their screen. forge_strike's quieter sibling.
	await Motion.writ_amend(host, card, stamp_text, accent, opts)


func rarity_reveal(ctrl: Control, rarity: String, delay: float = 0.0) -> void:
	Motion.rarity_reveal(ctrl, rarity, delay)


func ring_pulse(overlay: Control, center: Vector2, color: Color,
		start_d: float, end_d: float, dur: float, delay: float = 0.0) -> void:
	Motion.ring_pulse(overlay, center, color, start_d, end_d, dur, delay)


func reroll_sweep(host: Control, cards: Array,
		accent: Color = Color(1.0, 0.82, 0.36)) -> float:
	# Returns the seconds the caller should wait before dealing the new slate.
	return Motion.reroll_sweep(host, cards, accent)


# ── Trauma screen shake (R2 of docs/ANIMATION_AUDIT_20260716.md) ──────────
# One shake service for every screen (Eiserloh's GDC trauma model): impulses
# ADD energy to a 0–1 trauma reservoir, amplitude = trauma² × SHAKE_MAX_OFFSET,
# offsets come from smooth noise, and trauma decays linearly. Compared to the
# old per-call jitter tween this composes (a kill during a shake makes it
# BIGGER, not a restart) and gives the shaken property a single writer.
#
# Usage: `set_shake_target(node)` once per screen (idempotent — safe to call
# per impulse), then `add_trauma(x)` with x in 0–1 (0.2 = a tap, 0.5 = a heavy
# blow, 1.0 = the world ends). Combat.screen_shake delegates here and maps its
# legacy pixel amounts; shell set-pieces call it directly with small values.
# CanvasLayers shake via "offset", Controls/Node2Ds via "position"; the rest
# value is captured at registration and restored exactly when trauma runs out.
# Gates on the dedicated Screen Shake setting, NOT reduce_motion (shake has
# its own toggle in Settings).

const SHAKE_MAX_OFFSET: float = 18.0  # px at full trauma (amplitude = trauma² × this)
const SHAKE_DECAY: float = 2.4        # trauma lost per second (full shake fades in ~0.4s)
const SHAKE_FREQ: float = 190.0       # noise sample speed — higher = more violent rattle

var _shake_trauma: float = 0.0
var _shake_target: Node = null
var _shake_prop: String = "position"
var _shake_rest: Vector2 = Vector2.ZERO
# Co-targets shaken off the same trauma, in lockstep with _shake_target.
# Entries: {node, prop, rest}. See set_shake_targets.
var _shake_extra: Array = []
var _shake_clock: float = 0.0
var _shake_noise_x: FastNoiseLite = null
var _shake_noise_y: FastNoiseLite = null


func set_shake_target(node: Node) -> void:
	# Idempotent: re-registering the current target keeps its trauma (so
	# per-impulse callers don't reset a shake in flight). A NEW target releases
	# the old one back to its rest value first.
	if node == _shake_target:
		return
	_release_shake_target()
	if node == null or not is_instance_valid(node):
		return
	_shake_target = node
	_shake_prop = "offset" if node is CanvasLayer else "position"
	_shake_rest = node.get(_shake_prop)


func set_shake_targets(nodes: Array) -> void:
	# Shake several nodes IN LOCKSTEP off one trauma reservoir. Combat needs
	# this because the board and the HUD are different layers: the cards live in
	# _board_container (a Control) while the floating numbers, rings and impact
	# bursts live in _hud_layer (a CanvasLayer). Shaking only one of them either
	# leaves the battlefield perfectly still while the numbers jitter (what the
	# game did before 2026-07-17) or tears the VFX off the cards they were
	# spawned on. One offset, applied to every target, keeps them welded.
	#
	# Idempotent on the same set, for the same reason as set_shake_target: an
	# impulse arriving mid-shake must ADD energy, not restart the shake.
	var live: Array = []
	for n in nodes:
		if n != null and is_instance_valid(n):
			live.append(n)
	if live.is_empty():
		return
	if _shake_extra_match(live):
		return
	_release_shake_target()
	_shake_target = live[0]
	_shake_prop = "offset" if live[0] is CanvasLayer else "position"
	_shake_rest = live[0].get(_shake_prop)
	for i in range(1, live.size()):
		var n: Node = live[i]
		var prop: String = "offset" if n is CanvasLayer else "position"
		_shake_extra.append({"node": n, "prop": prop, "rest": n.get(prop)})


func _shake_extra_match(live: Array) -> bool:
	if _shake_target != live[0] or _shake_extra.size() != live.size() - 1:
		return false
	for i in range(1, live.size()):
		if _shake_extra[i - 1]["node"] != live[i]:
			return false
	return true


func add_trauma(amount: float) -> void:
	if UserSettings != null and not UserSettings.screen_shake:
		return
	if _shake_target == null or not is_instance_valid(_shake_target):
		return
	if _shake_noise_x == null:
		_shake_noise_x = FastNoiseLite.new()
		_shake_noise_x.seed = 1013
		_shake_noise_y = FastNoiseLite.new()
		_shake_noise_y.seed = 4021
	_shake_trauma = clampf(_shake_trauma + clampf(amount, 0.0, 1.0), 0.0, 1.0)
	set_process(true)


func shake_impulse(node: Node, amount: float) -> void:
	# Convenience for shell one-shots (forge strike, treasure burst): target +
	# impulse in one call.
	set_shake_target(node)
	add_trauma(amount)


func _process(delta: float) -> void:
	# Only runs while a shake is live — add_trauma() arms it, and it disarms
	# itself (restoring the target's rest value exactly) when trauma hits zero
	# or the target is freed under it.
	if _shake_trauma <= 0.0 or _shake_target == null \
			or not is_instance_valid(_shake_target):
		_release_shake_target()
		set_process(false)
		return
	_shake_trauma = maxf(_shake_trauma - SHAKE_DECAY * delta, 0.0)
	_shake_clock += delta
	var amp: float = _shake_trauma * _shake_trauma * SHAKE_MAX_OFFSET
	var off := Vector2(
		_shake_noise_x.get_noise_1d(_shake_clock * SHAKE_FREQ),
		_shake_noise_y.get_noise_1d(_shake_clock * SHAKE_FREQ)) * amp
	_shake_target.set(_shake_prop, _shake_rest + off)
	# Same offset on every co-target, so the board and the effects drawn over it
	# move as one object.
	for e in _shake_extra:
		if is_instance_valid(e["node"]):
			e["node"].set(e["prop"], e["rest"] + off)
	if _shake_trauma <= 0.0:
		_release_shake_target()
		set_process(false)


func _release_shake_target() -> void:
	if _shake_target != null and is_instance_valid(_shake_target):
		_shake_target.set(_shake_prop, _shake_rest)
	for e in _shake_extra:
		if is_instance_valid(e["node"]):
			e["node"].set(e["prop"], e["rest"])
	_shake_extra.clear()
	_shake_target = null
	_shake_trauma = 0.0


# ── The signature transition: an ink-bleed wipe ────────────────────────
# Every scene change routes through here, so this one function is where the
# game's whole shell gets its "campaign ledger" hand: instead of a flat
# alpha fade, dark ink pours in from the page's top-left corner, its
# frontier roughened by paper-grain noise and rimmed with a faint ember —
# the world chars away, then the next page opens. Degrades safely: if the
# shader ever fails to compile the overlay is simply invisible and the
# change still happens on schedule.
const _INK_WIPE_CODE := "
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ember : source_color = vec3(0.95, 0.45, 0.14);
uniform vec2 origin = vec2(0.08, 0.10);
// 0 = the ink FLOODS IN toward the origin (leaving a screen).
// 1 = the ink LIFTS AWAY from the origin (arriving on one), so the new screen
//     appears first at the point the player was already looking at.
uniform float invert = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	float n = vnoise(UV * 7.0) * 0.55 + vnoise(UV * 19.0) * 0.30
		+ vnoise(UV * 43.0) * 0.15;
	float field = distance(UV, origin) / 1.35;
	float f = field * 0.72 + n * 0.28;
	f = mix(f, 1.0 - f, invert);
	float t = progress * 1.12;
	float a = 1.0 - smoothstep(t - 0.035, t, f);
	// A THIN charring line at the very frontier — an accent, not a fire wall.
	float rim = smoothstep(t - 0.030, t - 0.014, f)
		* (1.0 - smoothstep(t - 0.014, t, f));
	COLOR = vec4(COLOR.rgb + ember * rim * 0.30, a);
}
"
var _ink_wipe_shader: Shader = null

## Where the last transition's ink closed, in UV. Read by `fade_in` so the next
## screen opens at the same point. Defaults to the page-turn corner for a cold
## boot or any scene reached without a wipe.
var transition_origin := Vector2(0.08, 0.10)

## How long the outgoing ink is held after the scene swap, covering the incoming
## screen while its `_ready` builds. Long enough to span instantiation plus a
## build frame or two; short enough that a warm scene is not made to wait.
## The cover is held until the incoming screen is settled, bounded at both ends.
## MIN keeps an instant swap from flickering; MAX is the ceiling for a scene that
## never calms down, so a bad frame budget degrades to the old fixed behaviour
## rather than to a screen that stays covered. CALM_FRAME is ~1.5x a 60Hz frame:
## a build hitch is a long frame by definition, so short frames mean it is over.
const TRANSITION_COVER_MIN := 0.10
const TRANSITION_COVER_MAX := 1.10
const TRANSITION_CALM_FRAME := 0.024

## True while a wipe still owns the screen and is going to reveal it itself.
## `fade_in` stands down for that window — otherwise the incoming scene stacks a
## second cover on top of the one already mid-reveal.
var _transition_reveal_pending := false


func _get_ink_wipe_shader() -> Shader:
	if _ink_wipe_shader == null:
		_ink_wipe_shader = Shader.new()
		_ink_wipe_shader.code = _INK_WIPE_CODE
	return _ink_wipe_shader


# Ink-wipe scene transition (see the shader block above). The overlay covers
# input immediately and auto-frees right after the scene switch. Calling
# fade_in() at scene _ready time is the matched bookend.
func fade_out_then_change_scene(host: Node, target_scene: String,
		duration: float = 0.34,
		origin_uv: Vector2 = Vector2(0.08, 0.10)) -> void:
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Near-black sepia ink, not pure black — matches the shell's murk.
	overlay.color = Color(0.043, 0.031, 0.024, 1.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 1000
	var mat := ShaderMaterial.new()
	mat.shader = _get_ink_wipe_shader()
	mat.set_shader_parameter("progress", 0.0)
	# MapView passes the committed site's screen position so the ink starts at
	# the place the army just entered. Other scenes keep the page-turn origin.
	var ink_origin := Vector2(
		clampf(origin_uv.x, 0.0, 1.0), clampf(origin_uv.y, 0.0, 1.0))
	mat.set_shader_parameter("origin", ink_origin)
	# CARRIED ACROSS THE CUT. The incoming scene has no way to know where the
	# outgoing one closed, so it is remembered here and `fade_in` opens from the
	# same point — see the note there on why that is the whole idea.
	transition_origin = ink_origin
	overlay.material = mat
	host.get_tree().root.add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_method(func(p: float):
		mat.set_shader_parameter("progress", p),
		0.0, 1.0, duration).set_ease(Tween.EASE_IN)
	# HOLD THE TREE, NOT THE HOST. This callback used to close over `host` and
	# reach the tree through it. The outgoing scene root can be freed inside the
	# 0.34s wipe (a second transition racing this one, quit-to-menu, a scene that
	# frees itself on the way out) — and a freed capture makes Godot abort the
	# callable while it MARSHALS captures ("Lambda capture at index 0 was freed"),
	# so NEITHER statement below ran. That lost both halves at once: the scene
	# change was silently dropped, and this full-rect MOUSE_FILTER_STOP overlay at
	# z_index 1000 was never freed — a black screen that ate every click, with no
	# way out. The SceneTree outlives every scene, so it is the safe thing to
	# hold; the overlay rides a weakref for the same reason.
	var tree := host.get_tree()
	# Explicit type: weakref() is declared Variant, and this project compiles with
	# Variant-inference warnings treated as errors, so `:=` here fails the gate.
	var overlay_ref: WeakRef = weakref(overlay)
	tw.tween_callback(func():
		if tree != null and is_instance_valid(tree):
			# Measure the actual scene load/settle, not this fixed ink-wipe tween.
			PerformanceOverlay.begin_transition(target_scene)
			tree.change_scene_to_file(target_scene)
		# ONE OVERLAY DOES BOTH HALVES (2026-09-11).
		#
		# This used to free the overlay in the same breath as the scene change,
		# and that leaves a real uncovered window: `change_scene_to_file` swaps
		# on the next idle frame, the incoming scene then runs `_ready` — which
		# is where every screen in this game assembles its entire UI in code —
		# and only AFTER that does its `fade_in` get to spawn a cover, because
		# `fade_in` is itself deferred. The half-built screen was therefore on
		# display for the whole of its own construction, which on a cold scene is
		# the most expensive frame it will ever have.
		#
		# HOLDING THE OLD COVER AND LETTING THE NEW ONE REVEAL UNDER IT WAS THE
		# FIRST FIX AND IT IS WRONG: two stacked overlays means the incoming one
		# is already part-revealed when the outgoing one frees, so the screen
		# jumps from fully covered to half-revealed in a single frame. Worse, the
		# obvious patch — fading the old one out — cannot work here, because this
		# shader writes COLOR outright and `modulate` never reaches it.
		#
		# So the same overlay covers, waits out the build, and then reveals: flip
		# `invert`, run `progress` back down. At the moment of the flip it is
		# opaque either way (every f lies below the threshold at progress 1), so
		# the hand-off has no seam by construction rather than by timing.
		_transition_reveal_pending = true
		if tree == null or not is_instance_valid(tree):
			var ov = overlay_ref.get_ref()
			if ov != null and is_instance_valid(ov):
				ov.queue_free()
			_transition_reveal_pending = false
			return
		# THE BACKSTOP IS NOT OPTIONAL. The failure recorded above was this exact
		# overlay never being freed — a black screen that ate every click with no
		# way out — so there is a tree-owned timer that frees it and clears the
		# flag whatever happens to the reveal, including a scene that never
		# loads. The tree outlives every scene, so this fires regardless.
		var bail := tree.create_timer(TRANSITION_COVER_MAX + duration + 1.5)
		bail.timeout.connect(func():
			var ob = overlay_ref.get_ref()
			if ob != null and is_instance_valid(ob):
				ob.queue_free()
			_transition_reveal_pending = false)
		_hold_cover_until_settled(overlay_ref, duration)
	)


## Hold the cover until the incoming screen is genuinely ON ITS FEET, then reveal.
##
## A FIXED HOLD WAS THE FIRST VERSION AND IT IS A GUESS DRESSED AS A NUMBER: a
## warm scene is ready in a frame or two and is made to wait out the rest, while
## a cold one is still building when the ink starts lifting — which is the exact
## defect the hold was added to fix, just narrower.
##
## So it waits for the thing that actually matters: the scene has SWAPPED (a
## different instance from the one we left, since `change_scene_to_file` is
## deferred and `current_scene` still points at the old one for a frame), and
## then two consecutive CALM frames. A build hitch is a long frame by definition,
## so "frames are short again" IS "the build is done" — no per-scene cooperation
## needed, which matters because every screen here builds differently.
##
## Wall-clock between resumes, not `delta`: under a stalled frame the reported
## delta can be clamped, and the whole point is to notice the stall.
func _hold_cover_until_settled(overlay_ref: WeakRef, duration: float) -> void:
	var tree := get_tree()
	if tree == null:
		_transition_reveal_pending = false
		return
	var left_behind: int = 0
	if tree.current_scene != null:
		left_behind = tree.current_scene.get_instance_id()
	var elapsed := 0.0
	var calm := 0
	var last := Time.get_ticks_usec()
	while elapsed < TRANSITION_COVER_MAX:
		await tree.process_frame
		if not is_instance_valid(tree):
			break
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		elapsed += dt
		var cur := tree.current_scene
		var swapped: bool = cur != null and cur.get_instance_id() != left_behind
		if swapped and dt <= TRANSITION_CALM_FRAME:
			calm += 1
			if calm >= 2:
				break
		else:
			calm = 0
	# A FLOOR, even on an instant swap. Headless and on a fast machine the two
	# calm frames land almost immediately, and a reveal that begins before the
	# eye has registered the cut reads as a flicker rather than a transition.
	if elapsed < TRANSITION_COVER_MIN:
		await tree.create_timer(TRANSITION_COVER_MIN - elapsed).timeout
	_reveal_cover(overlay_ref, duration)


## The second half: flip the wipe and run it back out from the origin. Opaque on
## either side of the flip (at progress 1 every `f` sits below the threshold), so
## there is no seam to time.
func _reveal_cover(overlay_ref: WeakRef, duration: float) -> void:
	var o2 = overlay_ref.get_ref()
	if o2 == null or not is_instance_valid(o2):
		_transition_reveal_pending = false
		return
	var m2 := (o2 as ColorRect).material as ShaderMaterial
	if m2 == null:
		o2.queue_free()
		_transition_reveal_pending = false
		return
	m2.set_shader_parameter("invert", 1.0)
	m2.set_shader_parameter("progress", 1.0)
	# Explicit type: `o2` came out of a WeakRef and is therefore Variant, so `:=`
	# cannot infer the return and the Variant-inference warning is an error in
	# this project — the same trap the weakref in the wipe already documents.
	var rt: Tween = o2.create_tween()
	rt.tween_method(func(p: float):
		if is_instance_valid(m2):
			m2.set_shader_parameter("progress", p),
		1.0, 0.0, duration).set_ease(Tween.EASE_OUT)
	rt.tween_callback(func():
		_transition_reveal_pending = false
		var o3 = overlay_ref.get_ref()
		if o3 != null and is_instance_valid(o3):
			o3.queue_free())


## ── The slider kit ───────────────────────────────────────────────────────────
## Lives here rather than in SettingsOverlay (which owned it privately until
## 2026-09-14) because the skirmish lobby's arsenal scale needs the same face,
## and a second copy of a look is how two controls drift apart. SettingsOverlay
## calls through to these.

## A filled diamond with a 1px dark keyline, so a grabber reads as a set stone
## rather than a floating blob. Antialiased by manhattan-distance falloff.
func make_diamond_texture(radius: int, color: Color) -> ImageTexture:
	var size := radius * 2 + 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	var edge := Color(0.10, 0.07, 0.03, color.a)
	for x in range(size):
		for y in range(size):
			var d := absf(x - c) + absf(y - c)
			if d <= radius - 1.6:
				img.set_pixel(x, y, color)
			elif d <= radius - 0.6:
				img.set_pixel(x, y, edge.lerp(color, clampf(radius - 0.6 - d, 0.0, 1.0)))
			elif d <= radius + 0.4:
				var a := clampf(radius + 0.4 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(edge.r, edge.g, edge.b, edge.a * a))
	return ImageTexture.create_from_image(img)


## The house slider face: sunken track, gilt fill, diamond grabber.
func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.05, 0.9)
	track.border_color = Color(0.3, 0.22, 0.12, 0.5)
	for prop in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		track.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		track.set(prop, 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)

	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.65, 0.50, 0.18, 0.9)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		filled.set(prop, 4)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", filled)

	var filled_hl := filled.duplicate() as StyleBoxFlat
	filled_hl.bg_color = Color(0.82, 0.66, 0.30, 1.0)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_hl)

	slider.add_theme_icon_override("grabber", make_diamond_texture(9, GILT_BRIGHT))
	slider.add_theme_icon_override("grabber_highlight",
		make_diamond_texture(11, Color(1.0, 0.92, 0.55)))
	slider.add_theme_icon_override("grabber_disabled", make_diamond_texture(9, DIMMED))


## A whole-number scale: a styled HSlider stepping by 1 over [min_value, max].
## Snapping is not decoration — the arsenal size is a COUNT, and a slider that
## can rest between two rounds is a control that lies about what it sets.
func make_count_slider(min_value: int, max_value: int, value: int,
		width: float = 190.0) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = float(min_value)
	slider.max_value = float(maxi(max_value, min_value))
	slider.step = 1.0
	slider.value = float(clampi(value, min_value, max_value))
	slider.rounded = true
	slider.scrollable = true
	slider.custom_minimum_size = Vector2(width, 24)
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	style_slider(slider)
	return slider


func make_back_button(label: String = "BACK", min_size: Vector2 = Vector2(140, 42),
		font_size: int = 16, rest_color: Color = IVORY) -> Button:
	# Unified frameless text button used by every scene — "go back / leave /
	# close / cancel" and also light primary confirms (Pick). Slay-the-Spire /
	# Hades idiom: no filled pill at rest, the label *is* the button. On hover a
	# gilt underline ignites beneath it and the text brightens to gilt. A heavy
	# dark text outline keeps the label legible over busy painted backgrounds.
	# `rest_color` defaults to IVORY (secondary); pass GILT/KEYWORD_GOLD for a
	# primary-feeling action that should read warmer at rest.
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_display:
		btn.add_theme_font_override("font", font_display)
	btn.add_theme_font_size_override("font_size", maxi(font_size, MIN_LABEL_SIZE))
	btn.add_theme_color_override("font_color", rest_color)
	btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.85, 0.65))
	btn.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	btn.add_theme_constant_override("outline_size", 5)

	# Rest state: truly frameless (no box), with content margins so the click
	# target and text padding match the hover state — nothing reflows on hover.
	var rest := StyleBoxEmpty.new()
	rest.content_margin_left = 18
	rest.content_margin_right = 18
	rest.content_margin_top = 6
	rest.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", rest)
	btn.add_theme_stylebox_override("focus", rest)
	btn.add_theme_stylebox_override("disabled", rest)

	# Hover: a gilt underline (bottom border only, near-transparent fill) fades
	# in beneath the label — the frameless hover signal, no pill.
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.85, 0.62, 0.25, 0.10)
	hover.border_color = GILT_BRIGHT
	hover.border_width_bottom = 2
	hover.content_margin_left = 18
	hover.content_margin_right = 18
	hover.content_margin_top = 6
	hover.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.85, 0.62, 0.25, 0.04)
	pressed.border_color = GILT
	btn.add_theme_stylebox_override("pressed", pressed)
	# THE RETREAT KEEPS ITS OWN VOICE. Once the press funnel gives every button a
	# default cue, a back button that declares nothing says "select" — and the
	# whole reason `ui_back` exists is to be pitched DOWN so advance and retreat
	# are distinguishable with the screen unread. 32 call sites would have
	# quietly lost that. Keyed off `rest_color`, which is this helper's own
	# existing declaration of intent (its header: pass GILT for "a primary-feeling
	# action that should read warmer at rest"), so the two uses stay separable
	# without a new argument.
	btn.set_meta("ui_cue", "back" if rest_color == IVORY else "select")
	arm_ui_hover(btn)
	return btn


func make_primary_button(text: String, min_size: Vector2 = Vector2(220, 52),
		font_size: int = 20) -> Button:
	## THE WAY ON (2026-08-05) — the counterpart `make_back_button` never had.
	##
	## That helper is the house frameless idiom for "go back / leave / close /
	## cancel", and its own header notes it also serves "light primary confirms".
	## In practice the in-run shell used it for the FORWARD move on screens the
	## player passes through many times a run — Reward's "Continue" (pressed
	## after every fight, the most-repeated press in the game outside combat),
	## the Shop's "Leave the Wagon", a Wayside's "Continue" — so the action that
	## advances the run rendered as a caption floating under the content it was
	## meant to conclude.
	##
	## Warm parchment tab with a gilt keyline: the same weight as MainMenu's
	## `_make_primary_action`, deliberately WITHOUT its flame. The igniting flame
	## is the title screen's own motif for a menu column; in the run the plate is
	## the signal and a flame here would read as a second, unrelated grammar.
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if font_display:
		btn.add_theme_font_override("font", font_display)
	btn.add_theme_font_size_override("font_size", maxi(font_size, MIN_LABEL_SIZE))
	btn.add_theme_color_override("font_color", Color(0.99, 0.92, 0.74))
	btn.add_theme_color_override("font_hover_color", GILT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(0.94, 0.86, 0.62))
	btn.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	# BACK TO 4 (2026-09-18). It was cut to 2 when this button had a plate, on the
	# reasoning that a plated button controls its own background. It does not have
	# one any more — the label now floats over whatever painted scene is behind
	# it, which is the exact case the heavy outline exists for. Dropping the plate
	# without restoring this would have left the word to fend for itself over the
	# meadow fire.
	btn.add_theme_constant_override("outline_size", 4)

	## THE PLATE IS A SOLID NOW (2026-09-17). These three states used to be three
	## `make_panel_style` calls, i.e. the same flat-rule assembly in three
	## colours: the press differed from the rest state by a darker fill and a
	## slightly different keyline, which is the only thing a rectangle can do.
	## `PlaqueStyle` makes it an object with a molded edge, so the press can
	## drive it FLUSH instead — see that file's fact 5.
	## ── NO PLATE. THE WORD IS THE BUTTON (2026-09-18, owner's call).
	##
	## This helper carried a filled tab since 2026-08-05, and the 2026-09-17 pass
	## rebuilt that tab as a struck metal plaque. The owner's verdict on the
	## result was blunt and it was right: hide the background, like the start
	## menu. The standing preference is on record and predates all of it —
	## *"frameless text buttons over boxed ones: no panel/fill; the text IS the
	## button; hover = brighten to gilt + a flame igniting"*, chosen explicitly
	## when offered the alternative, alongside *"don't force things cuz they are
	## there"* about exactly this kind of inherited chrome. A gilt frame added to
	## the board was pushed back on the same way once before. I built a better
	## rectangle when the note in the file said not to build a rectangle.
	##
	## So the plate is gone and the AFFORDANCE MOVES TO THE INK: the label is the
	## object, and hover ignites a gilt underline beneath it — `make_back_button`'s
	## idiom, which is already what most of this game's buttons do. The plaque
	## kit stays in the tree for the surfaces that genuinely are objects (the
	## save-slot rows), not for anything that is really a word.
	var rest := StyleBoxEmpty.new()
	rest.content_margin_left = 18
	rest.content_margin_right = 18
	rest.content_margin_top = 6
	rest.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", rest)
	btn.add_theme_stylebox_override("disabled", rest)
	# Hover / focus: the underline ignites. Bottom border only, near-transparent
	# fill — no pill, nothing that reads as a box.
	var lit_style := StyleBoxFlat.new()
	lit_style.bg_color = Color(0.85, 0.62, 0.25, 0.10)
	lit_style.border_color = GILT_BRIGHT
	lit_style.border_width_bottom = 2
	lit_style.content_margin_left = 18
	lit_style.content_margin_right = 18
	lit_style.content_margin_top = 6
	lit_style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", lit_style)
	btn.add_theme_stylebox_override("focus", lit_style)
	var down := lit_style.duplicate() as StyleBoxFlat
	down.bg_color = Color(0.85, 0.62, 0.25, 0.04)
	down.border_color = GILT
	btn.add_theme_stylebox_override("pressed", down)
	# THE WAY ON earns the at-cursor mark: this helper exists for the action that
	# advances the run, which is the most-repeated weighted press outside combat.
	btn.set_meta("press_weight", true)
	arm_ui_hover(btn)
	# The glint is FOLDED INTO `arm_transitions` now (the lamp crossing the brass
	# is part of the hover movement, not a separate effect) — and it had to be:
	# with ONE plate instead of three, a swept `sweep_phase` would persist into
	# the rest pose instead of disappearing with the hover stylebox.
	# NO ENGRAVE HERE ANY MORE: a struck word needs metal to be struck INTO, and
	# there is no plate now. `arm_plaque_label` is a no-op on a non-plaque
	# stylebox anyway, but leaving the call would read as an intention.
	return btn


## Push a word into every plaque state a button wears, so the plate can strike it
## (see `PlaqueStyle.label`).
##
## ONE FUNNEL, because the failure mode is a DOUBLE PRINT rather than a miss. The
## engrave is drawn by the stylebox and the glyph by the Button, from two
## different copies of the string — so a caller that assigns `btn.text` after
## construction leaves the OLD word ghosted under the new one, at full shadow
## strength, forever. Re-calling this is the fix, and having exactly one place to
## call is what makes that instruction meaningful.
##
## Non-plaque styleboxes are skipped silently: this is safe to call on any button,
## which is what lets a screen that retitles a control just call it unconditionally.
## Strike a word that lives in its own `Label` rather than in `Button.text`.
##
## TWO MECHANISMS FOR ONE EFFECT, BECAUSE THE ENGINE OFFERS DIFFERENT THINGS TO
## THE TWO CONTROLS, and this is worth knowing before anyone tries to unify them.
## Measured off `ThemeDB` rather than recalled: a `Button`'s theme carries
## `font_outline_color` and no shadow item at all — its colour list is
## font/font_pressed/font_hover/font_focus/font_hover_pressed/font_disabled/
## font_outline plus the icon set, and nothing else — so a Button's engrave has
## to be drawn underneath it by the stylebox (`PlaqueStyle.label`). A `Label`
## DOES carry `font_shadow_color` with `shadow_offset_x/y`, which the engine
## positions itself.
##
## Where a Label is available it is strictly better, and the reason is exactness:
## the stylebox route re-derives where the glyph will land, and a cast shadow one
## pixel off its caster is not a softer shadow, it is a double print. The engine
## cannot be off by a pixel. That is why the flame buttons — whose word sits in a
## child Label inside an HBox, where the stylebox genuinely cannot know the
## position — get this instead of an engrave, and end up with the more reliable
## half of the pair.
##
## Down-light (down-right, for the kit's up-left lamp), matching the plate's own
## drop so the letter and the plate it stands on are lit by one sun.
static func engrave_label(lbl: Label, shadow_a: float = 0.62) -> void:
	if lbl == null:
		return
	lbl.add_theme_color_override("font_shadow_color",
		Color(0.02, 0.012, 0.008, shadow_a))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)






func make_close_button(min_size: Vector2 = Vector2(44, 44)) -> Button:
	# Compact circular X used by modal overlays (deck viewer, settings, etc.).
	# Plain ASCII X — the U+2715 multiplication-x glyph isn't in every display
	# font and tofu'd on a few screens.
	var btn := Button.new()
	btn.text = "X"
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	if font_display:
		btn.add_theme_font_override("font", font_display)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.45))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	btn.add_theme_constant_override("outline_size", 3)
	# Closing a modal is a retreat, so it takes the retreat's cue — same rule as
	# the click-outside-to-dismiss scrim.
	btn.set_meta("ui_cue", "back")
	var bg := Color(0.18, 0.14, 0.10, 0.92)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = GILT
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	var corner: int = int(min_size.x * 0.5)
	normal.corner_radius_top_left = corner
	normal.corner_radius_top_right = corner
	normal.corner_radius_bottom_left = corner
	normal.corner_radius_bottom_right = corner
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.40, 0.14, 0.10, 0.95)
	hover.border_color = Color(1.0, 0.55, 0.30)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn


func show_confirm_dialog(host: Node, title: String, message: String,
		confirm_label: String = "CONFIRM", cancel_label: String = "CANCEL",
		on_confirm: Callable = Callable(), on_cancel: Callable = Callable()) -> void:
	# Modal yes/no dialog. Centered panel with title + body text + two pill
	# buttons. Backdrop dims the screen and absorbs clicks so the player can't
	# act on what's behind. Calls on_confirm only if the player picks confirm.
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	# Wrap the dialog in a CanvasLayer at very high `layer` so it renders on
	# top of SettingsOverlay (layer=100) and any other HUD CanvasLayer. Pure
	# z_index doesn't help here — CanvasLayer order beats z_index across the
	# tree, which is why the previous z_index=999 approach left the dialog
	# hidden behind the settings panel.
	# Parented to current_scene (not root) so when the player confirms an
	# action that changes the scene, the dialog dies with the old scene
	# instead of surviving into the next one ("stuck on main menu" bug).
	var layer := CanvasLayer.new()
	layer.layer = 1000
	var current_scene: Node = host.get_tree().current_scene
	var dialog_parent: Node = current_scene if current_scene != null else host.get_tree().root
	dialog_parent.add_child(layer)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	# House document kit (chamfer + metal rule + corner tacks) — the old
	# 16px-radius rounded bubble was the last non-kit panel in the pause flow.
	var s := make_panel_style(
		Color(0.105, 0.082, 0.062, 0.98), Color(0.70, 0.58, 0.35, 0.95),
		2, 6, true, true)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 24
	s.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", GILT_BRIGHT)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.45, 0.12, 0.05, 0.85))
	title_lbl.add_theme_constant_override("outline_size", 5)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_display:
		title_lbl.add_theme_font_override("font", font_display)
	vbox.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = message
	msg_lbl.add_theme_font_size_override("font_size", 18)
	msg_lbl.add_theme_color_override("font_color", IVORY)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.custom_minimum_size = Vector2(380, 0)
	if font_body:
		msg_lbl.add_theme_font_override("font", font_body)
	vbox.add_child(msg_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var cancel_btn := make_back_button(cancel_label, Vector2(150, 44))
	cancel_btn.pressed.connect(func():
		layer.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	btn_row.add_child(cancel_btn)

	var confirm_btn := make_themed_button(confirm_label,
		Color(0.40, 0.12, 0.10), Vector2(180, 44), 17)
	confirm_btn.pressed.connect(func():
		layer.queue_free()
		if on_confirm.is_valid():
			on_confirm.call())
	btn_row.add_child(confirm_btn)

	# Backdrop click does NOT dismiss — destructive actions deserve an explicit
	# Cancel. Only the Cancel button or Esc closes without action.

	# Animate the panel in: backdrop fades from 0 → 0.55, panel from scale 0.9 → 1.0
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(230, 80)
	var tw := overlay.create_tween()
	tw.set_parallel(true)
	tw.tween_property(backdrop, "color:a", 0.55, 0.18)
	tw.tween_property(panel, "modulate:a", 1.0, 0.22)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ── Reusable acquire / per-act pickers ──────────────────────────────────────
# Shared by Combat (pen_nib), MapView (per-act totem/hourglass + Bottled
# Talisman catch-all), and the acquire screens (Reward/Shop/Treasure). All use
# the same CanvasLayer(1000) modal idiom as show_confirm_dialog so they render
# above the settings overlay and die with the scene on a mid-modal transition.

## Interactive deck-builder card thumbnail: a scaled, cache-baked Card2D in a
## clickable slot with a mutable ×N badge and a gilt hover outline. Returns
## {root, card, badge, button} — the caller wires `button.pressed` and updates
## `badge.text` / `badge.visible` / `button.disabled` / `card.modulate` as the
## deck changes. Lets deck screens show real card art instead of a name list.
## The card keeps its crisp vector rules text at any thumbnail scale — small but
## legible, and honest about what each card does (see the rules-text note in
## Card2D._build_baked_overlay_layout).
func make_card_thumb(card_data: Dictionary, card_scale: float = 0.46) -> Dictionary:
	var w: float = 225.0 * card_scale
	var h: float = 300.0 * card_scale
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(w, h)
	slot.size = Vector2(w, h)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.card_data = card_data.duplicate(true)
	card.card_id = card_data.get("id", "")
	card.is_on_battlefield = true       # no drag / hover-lift
	card.static_display = true
	card.live_baked_mode = true         # cheap once the cache is warm
	# Pool screens may prepare the native 1x gallery class while combat-facing
	# paths prepare the larger mipmapped class. Pick the class that actually
	# exists before Card2D._ready chooses its layout.
	var use_gallery := not CardTextureCache.has(card_data) \
		and CardTextureCache.has_gallery(card_data)
	card.gallery_baked_mode = use_gallery
	card.scale = Vector2(card_scale, card_scale)
	card.position = Vector2.ZERO
	slot.add_child(card)
	if not CardTextureCache.has(card_data) and not use_gallery:
		CardTextureCache.bake(card_data)

	# Full-rect transparent click catcher with a gilt hover outline (the "add /
	# remove" affordance). Sits above the card, below the badge.
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(1, 1, 1, 0.0)
	hov.border_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.85)
	hov.set_border_width_all(2)
	hov.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	slot.add_child(btn)

	# ×N count chip, bottom-right (gilt-on-dark). Hidden until the caller sets it.
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 16)
	if font_stat != null:
		badge.add_theme_font_override("font", font_stat)
	badge.add_theme_color_override("font_color", GILT_BRIGHT)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(0.06, 0.05, 0.04, 0.92)
	bbg.border_color = GILT
	bbg.set_border_width_all(1)
	bbg.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("normal", bbg)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -36.0
	badge.offset_right = -5.0
	badge.offset_top = -27.0
	badge.offset_bottom = -5.0
	badge.visible = false
	slot.add_child(badge)

	return {"root": slot, "card": card, "badge": badge, "button": btn}


## THE PICKER RANK — one wrap rule for every screen that asks for a card.
##
## Every card picker in the game used to be a `GridContainer` with `columns = 6`,
## and a GridContainer fills left to right: eleven cards seated as six over five
## LEFT-FLUSH, with a card-shaped hole in the bottom right. Nine cards (the drill
## yard) read worse still — six over three, and half the rank empty. It is the
## commonest short-row defect there is, and it was on every choosing screen at
## once: the muster forge, Rest's forge, every Event picker, the drill yard and
## `show_deck_picker`.
##
## A FlowContainer centres each line it wraps, which is the whole fix — but its
## wrap point is decided by the width it is GIVEN, and that made the naive
## version fragile in two directions measured before this shipped:
##
##   * a ScrollContainer hands its child the child's MINIMUM width, and a flow
##     container's minimum width is ONE item — so without an expand/shrink flag
##     every picker collapsed to a single column;
##   * sized to the viewport instead, the wrap moves when a vertical scrollbar
##     appears. Rest's grid clears six 225px cards by 10px; lose 8 to a scrollbar
##     and the rank silently becomes five, which is a bigger regression than the
##     hole it was meant to fix.
##
## So the width is PINNED to exactly `cols` items and the flow is SHRINK_CENTER
## inside its viewport. The wrap point is then arithmetic rather than a
## measurement, and the centring happens twice: the block inside the screen, and
## the short last rank inside the block.
func make_picker_rank(cols: int, item_w: float, h_sep: int,
		v_sep: int) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", h_sep)
	flow.add_theme_constant_override("v_separation", v_sep)
	flow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var c: float = float(maxi(cols, 1))
	flow.custom_minimum_size.x = item_w * c + float(h_sep) * (c - 1.0)
	return flow


func show_deck_picker(host: Node, title: String, type_filter: String = "",
		allow_cancel: bool = false) -> int:
	## Modal grid of the run deck; the player clicks a card. Returns the chosen
	## RunState.deck INDEX, or -1 if dismissed / nothing eligible.
	##   type_filter: "" (any) | "creature" | "spell" | "upgradeable"
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return -1
	# Resolve eligible deck indices first — bail before building UI if empty.
	var eligible: Array[int] = []
	for i in RunState.deck.size():
		var d: Dictionary = RunState.get_upgraded_card_data(i)
		if type_filter == "upgradeable":
			if RunState.has_upgrade_path(i, "plus") \
					or not CardDB.is_upgradeable(RunState.deck[i]):
				continue
			eligible.append(i)
			continue
		if type_filter != "" and d.get("type", "") != type_filter:
			continue
		eligible.append(i)
	if eligible.is_empty():
		return -1

	var card_scene: PackedScene = load("res://scenes/card_2d.tscn")
	var layer := CanvasLayer.new()
	layer.layer = 1000
	var current_scene: Node = host.get_tree().current_scene
	var modal_parent: Node = current_scene if current_scene != null else host.get_tree().root
	modal_parent.add_child(layer)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.03, 0.02, 0.05, 0.93)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 16)
	overlay.add_child(root)
	# Give the first render something honest to present while the shared bake
	# viewport prepares a cold late-run deck. Removed before cards are staged.
	var title_lbl := make_label(title, FONT_TITLE, GILT_BRIGHT, true)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_lbl)
	var preparing := make_label("PREPARING THE DECK...", FONT_SUBHEADER,
		Color(IVORY.r, IVORY.g, IVORY.b, 0.72))
	preparing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preparing.custom_minimum_size = Vector2(0, 28)
	preparing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(preparing)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	# Tiles are 220 wide here (see the reserved slot below), so the rank is pinned
	# to six of them and the short last row centres itself.
	var grid := make_picker_rank(6, 220.0, 18, 20)
	scroll.add_child(grid)

	# -2 = still open, -1 = cancelled, >=0 = picked deck index.
	var result := {"index": -2}

	# Cancellation is live during cache preparation as well as card selection.
	if allow_cancel:
		var cancel := make_back_button("CANCEL", Vector2(170, 44))
		cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cancel.pressed.connect(func():
			result["index"] = -1
			layer.queue_free())
		root.add_child(cancel)

	var card_datas: Array[Dictionary] = []
	for di in eligible:
		card_datas.append(RunState.get_upgraded_card_data(di))
	# Reserve the complete grid before the first asynchronous bake. Adding cards
	# directly to a centred/container-managed row made every completed card resize
	# the layout and shove the cards already on screen. The backs are the content
	# while the faces hydrate; the final geometry exists from frame one.
	var picker_slots: Array[Control] = []
	var picker_backs: Array[Control] = []
	var card_back_tex := load("res://assets/ui/card_back.png") as Texture2D
	for _ei in range(eligible.size()):
		var reserved := Control.new()
		reserved.custom_minimum_size = Vector2(220, 300)
		reserved.size = Vector2(220, 300)
		reserved.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(reserved)
		var back: Control
		if card_back_tex != null:
			var back_pic := TextureRect.new()
			back_pic.texture = card_back_tex
			back_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			back_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			back = back_pic
		else:
			var back_plate := ColorRect.new()
			back_plate.color = Color(0.075, 0.055, 0.045, 1.0)
			back = back_plate
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Motion.arm_loading_writ(back, grid)
		reserved.add_child(back)
		picker_slots.append(reserved)
		picker_backs.append(back)
	var picker_alive := func() -> bool:
		return is_instance_valid(layer)
	# Picker cards never exceed their native 225x300 face, so use the 1x gallery
	# cache instead of allocating 3x mipmapped combat textures for the whole deck.
	# Sequential bakes naturally cap construction/readback at one card per beat.
	for data in card_datas:
		if not CardTextureCache.has_gallery(data):
			await CardTextureCache.bake_gallery(data, picker_alive)
		if not is_instance_valid(layer):
			return int(result["index"]) if int(result["index"]) != -2 \
				else -1

	# Hydrate one face per presented frame BEHIND the complete set of backs. The
	# work stays bounded without exposing build order to the player.
	var picker_cards: Array[Control] = []
	var picker_buttons: Array[Button] = []
	for ei in range(eligible.size()):
		var di: int = eligible[ei]
		var data: Dictionary = card_datas[ei]
		var slot: Control = picker_slots[ei]
		var card = card_scene.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = data.get("id", "")
		card.is_on_battlefield = true
		card.gallery_baked_mode = true
		card.static_display = true
		card.live_baked_mode = true
		card.modulate.a = 0.0
		slot.add_child(card)
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.disabled = true
		var captured: int = di
		btn.pressed.connect(func():
			result["index"] = captured
			layer.queue_free())
		slot.add_child(btn)
		picker_cards.append(card)
		picker_buttons.append(btn)
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		if not is_instance_valid(layer):
			return int(result["index"]) if int(result["index"]) != -2 \
				else -1

	# One reveal for one set. All backs close together and all faces open together;
	# no card advertises which bake happened to finish first. Flip scale belongs to
	# the children, so the GridContainer never receives a geometry change.
	var snap_reveal := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	if snap_reveal:
		for i in range(picker_cards.size()):
			picker_backs[i].queue_free()
			picker_cards[i].modulate.a = 1.0
			picker_buttons[i].disabled = false
		preparing.text = ""
	else:
		preparing.text = "UNSEALING THE DECK..."
		await RenderingServer.frame_post_draw
		if not is_instance_valid(layer):
			return -1
		for i in range(picker_cards.size()):
			picker_cards[i].modulate.a = 1.0
			Motion.flip_out(picker_backs[i], 0.13)
			Motion.flip_in(picker_cards[i], Motion.time(0.13), 0.17)
		await get_tree().create_timer(maxf(Motion.time(0.34), 0.01)).timeout
		if not is_instance_valid(layer):
			return -1
		for btn in picker_buttons:
			btn.disabled = false
		preparing.text = ""

	while result["index"] == -2 and is_instance_valid(layer):
		await get_tree().process_frame
	# Layer freed by a scene change rather than a pick → treat as dismissed.
	if result["index"] == -2:
		return -1
	return result["index"]


func show_option_picker(host: Node, title: String, options: Array) -> int:
	## Modal list of labeled choices. `options` is an Array of Dictionaries:
	##   {"label": String, "desc": String, "color": Color (optional)}
	## Returns the chosen index, or -1 only if dismissed by a scene change.
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return -1
	if options.is_empty():
		return -1

	var layer := CanvasLayer.new()
	layer.layer = 1000
	var current_scene: Node = host.get_tree().current_scene
	var modal_parent: Node = current_scene if current_scene != null else host.get_tree().root
	modal_parent.add_child(layer)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	# The chart kit, not a CSS-rounded rect — same conversion the confirm
	# dialog got (2026-07-18); this was the last rounded-rect modal.
	var s := make_panel_style(Color(0.12, 0.09, 0.07, 0.97), GILT_BRIGHT, 2, 6, true)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 24
	s.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", GILT_BRIGHT)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.45, 0.12, 0.05, 0.85))
	title_lbl.add_theme_constant_override("outline_size", 5)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_display:
		title_lbl.add_theme_font_override("font", font_display)
	vbox.add_child(title_lbl)

	var result := {"index": -2}
	for oi in options.size():
		var opt: Dictionary = options[oi]
		var bg: Color = opt.get("color", Color(0.22, 0.16, 0.11))
		var label_text: String = String(opt.get("label", "?"))
		var desc_text: String = String(opt.get("desc", ""))
		var btn := make_themed_button(label_text, bg, Vector2(480, 50), 18, desc_text)
		var captured: int = oi
		btn.pressed.connect(func():
			result["index"] = captured
			layer.queue_free())
		vbox.add_child(btn)
		if desc_text != "":
			var dl := make_label(desc_text, 14, IVORY)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size = Vector2(480, 0)
			vbox.add_child(dl)

	while result["index"] == -2 and is_instance_valid(layer):
		await get_tree().process_frame
	if result["index"] == -2:
		return -1
	return result["index"]


func bind_bottled_talisman(host: Node) -> void:
	## Prompt the player to bind a deck card to Bottled Talisman, unless a valid
	## binding already exists. Safe to call from any acquire screen or MapView —
	## the guard makes repeat calls (e.g. MapView catch-all after an inline bind)
	## no-ops. Re-prompts if the bound card was later removed from the deck.
	if RunState.bottled_talisman_uid >= 0 \
			and RunState.bottled_talisman_uid in RunState.deck_uids:
		return
	var idx: int = await show_deck_picker(host,
		"Bottled Talisman — bind a card to your opening hand", "", false)
	if idx >= 0 and idx < RunState.deck_uids.size():
		RunState.bottled_talisman_uid = RunState.deck_uids[idx]


func fade_in(host: Node, duration: float = 0.32) -> void:
	# Quick black->transparent overlay so the new scene fades in. Call from _ready.
	# A scene root may still be assembling its children at that point; defer the
	# root-level insertion so transitions never lose their fade or emit an error.
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	# A wipe that is still covering will reveal this screen itself — see
	# `_transition_reveal_pending`. Standing down here is what keeps the
	# transition ONE movement instead of two overlays taking turns.
	if _transition_reveal_pending:
		return
	call_deferred("_spawn_fade_in", host, duration)


## `host` is deliberately UNTYPED. See the house gotcha recorded on 2026-07-07
## for Card2D._fit_desc_to_box: a call_deferred target with a TYPED Object param
## errors at DISPATCH ("Cannot convert argument 1 from Object to Object") when
## the argument is freed between the deferred call and the next idle frame — the
## is_instance_valid guard below never gets to run, because marshalling fails
## first. A scene that changes scene in the same frame it calls fade_in (every
## fast transition: map -> fight -> reward) hits exactly that window, and it was
## spamming the error on nearly every transition. Untyped param, guard, then use.
func _spawn_fade_in(host, duration: float) -> void:
	if host == null or not is_instance_valid(host) or not (host is Node) \
			or host.get_tree() == null:
		return
	# THE TRANSITION WAS ONE-SIDED (2026-09-11).
	#
	# The exit is authored: a noise-perturbed ink front blooming from a chosen
	# origin with a charring ember rim, and MapView even hands it the screen
	# position of the site the army just entered. The entrance was
	# `color:a 1 -> 0` on a PURE BLACK rect — so every screen change in the game
	# read as "a page burns away, and then a brightness happens".
	#
	# Two separate faults in that, and the second is the interesting one:
	#
	#   · A HUE POP AT THE CUT. The exit settles on sepia ink (0.043, 0.031,
	#     0.024) and the entrance started from pure black, so the switch flicked
	#     colder for a frame before brightening. Same overlay colour now.
	#
	#   · NO CONTINUITY OF ATTENTION. The exit converges on the thing the player
	#     clicked; the entrance began nowhere in particular. Running the SAME
	#     shader inverted means the ink now LIFTS from that same point — the new
	#     screen appears first exactly where the eye already is, and the two
	#     halves become one movement instead of two effects that happen to be
	#     adjacent. That is the whole reason the origin is carried on GameTheme
	#     rather than recomputed.
	#
	# It is the screen-level form of the rule the card pass already settled:
	# things arrive as THEMSELVES, not by becoming less transparent.
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.043, 0.031, 0.024, 1.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 1000
	var mat := ShaderMaterial.new()
	mat.shader = _get_ink_wipe_shader()
	mat.set_shader_parameter("origin", transition_origin)
	mat.set_shader_parameter("invert", 1.0)
	# Opaque on the spawn frame: the scene behind is still assembling and must
	# not be seen doing it.
	mat.set_shader_parameter("progress", 1.0)
	overlay.material = mat
	host.get_tree().root.add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_method(func(p: float):
		if is_instance_valid(mat):
			mat.set_shader_parameter("progress", p),
		1.0, 0.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_callback(overlay.queue_free)
