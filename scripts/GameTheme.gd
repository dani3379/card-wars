extends Node

# ── Fonts ──
var font_display: Font = null   # Lilita One — card names, type, FLOOP
var font_stat: Font = null      # Lilita One — cost, ATK, HP numerals
var font_body: Font = null      # Nunito Regular + embolden 0.55 — description text (Bold)
var font_body_bold: Font = null # Nunito Regular + embolden 0.85 — keyword [b] tags (ExtraBold)
var font_title: Font = null       # Cinzel SemiBold — combat HUD headers/captions (NOT cards)
var font_title_black: Font = null # Cinzel Black — combat HUD numerals (HP/mana/counts)

# ── Textures ──
var tex_card_frame_ornate: Texture2D = null
var tex_icon_sword: Texture2D = null
var tex_icon_heart: Texture2D = null

# ── Slay-the-Spire-style silhouette map node icons (Kenney CC0 board-game-icons). ──
var tex_node_combat: Texture2D = null
var tex_node_elite: Texture2D = null
var tex_node_rest: Texture2D = null
var tex_node_shop: Texture2D = null
var tex_node_event: Texture2D = null
var tex_node_boss: Texture2D = null
var tex_node_treasure: Texture2D = null
var tex_node_recruit: Texture2D = null

# ── HUD silhouettes (Kenney CC0). ──
var tex_hud_heart: Texture2D = null
var tex_hud_gold: Texture2D = null
var tex_hud_potion: Texture2D = null
var tex_hud_relic: Texture2D = null
var tex_hud_deck: Texture2D = null

# ── Card stat icons (hand-painted, pbmojART CC-BY 3.0 + Kenney CC0). ──
# Used by Card2D v4 in place of the procedurally-drawn GemOrb shapes —
# painted assets read as "real game art" where the polygon orbs always
# read as "programmer placeholder", no matter how many specular layers we
# stack on them.
var tex_stat_cost: Texture2D = null    # blue runestone (cost / mana)
var tex_stat_atk: Texture2D = null     # gold sword (attack)
var tex_stat_hp: Texture2D = null      # painted red heart (health)

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

const USE_NEW_FRAME := true  # flip to false to revert to assets/ui/card_frame_ornate.png
# v4 procedural card frame — drawn entirely in Godot, no PNG dependency.
# Adds Hearthstone-canonical stat colors (blue cost / yellow ATK / red HP), a
# visible rarity gem, and 225x300 card dimensions. Flip false to revert to v3.
# TURNED OFF to test the new painted v5 frames (frame_v5_a/b) via the v3
# PNG-based path. Flip true to revert to procedural.
const USE_PROCEDURAL_FRAME := false
# v5 — "overlap and paint the seams." Single CardCanvas draws the body +
# tapered ribbon banner + scroll divider in one _draw(); stat orbs straddle
# the art/description seam. Replaces v4's stack-of-Panels look. Flip false
# to fall back to v4 (which still works).
const USE_V5_OVERLAP_PAINT := true

# v3 frame variants: 2 types (creature/spell) x 4 rarities + curse.
# Populated by _load_new_frames() when USE_NEW_FRAME is true.
var _new_frames: Dictionary = {}
# Keyword name -> Texture2D for the medallion strip.
var _keyword_icons: Dictionary = {}

func _ready() -> void:
	_load_assets()

func _load_assets() -> void:
	# Display fonts: Cinzel Variable (Google Fonts, OFL). Classical Roman-engraved
	# capitals — pairs with the ornate frame's gold scrollwork. Replaces Pirata
	# One, which is more cartoony and fights with the painterly art.
	#
	# Two variants, both wrapped in FontVariations:
	#   - font_display: Cinzel SemiBold (wght 600) for card names, type, FLOOP.
	#     Slightly heavier than default 400 so caps read clearly at 9-10pt.
	#   - font_stat: Cinzel Black (wght 800) for cost/ATK/HP numerals. AAA card
	#     games (Hearthstone, MtG Arena, Playfair Display per typography guides)
	#     use heavy bold serif numerals for stat orbs — visual weight matches
	#     the gravity of those numbers. Cinzel at 400 weight rendered the orbs
	#     "thin and sus"; 800 gives the chunky stat-orb look players expect.
	#
	# Each variation also sets spacing_bottom < 0 to fix Godot's known
	# vertical_alignment=CENTER bug: Godot centers on font ascent+descent, but
	# all-caps / numeric text doesn't use the descender region, so glyphs appear
	# in the upper half. Negative spacing_bottom shrinks the line box's bottom,
	# pulling centered glyphs to their optical center.
	# Ref: https://forum.godotengine.org/t/correcting-vertical-alignment-center-for-a-label/2992
	# Display font: Lilita One (Google Fonts, OFL). Rounded heavy display
	# typeface — Wildfrost-adjacent, fits the storybook fantasy multi-register
	# tone better than Cinzel's formal Roman inscriptions.
	#
	# CRITICAL: setting `FontFile.data = bytes` directly is BROKEN — that path
	# is for `.tres` serialization, NOT runtime font initialization. The font
	# silently fails to render through that route. The correct runtime API is
	# `FontFile.load_dynamic_font(path)` which sets up the glyph cache atlas.
	# Alternative: `load("res://...")` works if Godot has imported the .ttf
	# (an .import file exists), but on first scan that .import won't exist
	# yet — load_dynamic_font sidesteps that entirely.
	var lilita: FontFile = null
	var lilita_path = "res://assets/fonts/LilitaOne-Regular.ttf"
	# Use CACHE_MODE_IGNORE to skip Godot's Resource cache — there's a known
	# bug (godotengine/godot#92778) where the cache returns stale fonts after
	# a .ttf is re-imported. Without this, "Lilita One loaded" prints success
	# but the rendered glyphs are from the previous import.
	lilita = ResourceLoader.load(lilita_path, "FontFile",
		ResourceLoader.CACHE_MODE_IGNORE) as FontFile
	if lilita != null:
		print("[GameTheme] Lilita One loaded via ResourceLoader (cache ignored)")
	else:
		# Fallback: load_dynamic_font (the runtime API for un-imported files).
		var ff := FontFile.new()
		var err := ff.load_dynamic_font(lilita_path)
		if err == OK:
			ff.resource_path = lilita_path  # theme cache key
			lilita = ff
			print("[GameTheme] Lilita One loaded via load_dynamic_font()")
		else:
			push_warning("[GameTheme] Lilita One failed both load paths, err=", err)

	# Body font loads first so we can use it as the fallback for the display
	# font's missing glyphs (Lilita One's character set is narrow — no arrow,
	# star, geometric-shape codepoints — so symbol characters tofu'd as boxes
	# until we wired this fallback up).
	var nunito := load("res://assets/fonts/Nunito-Regular.ttf") as Font

	if lilita != null:
		# Lilita One is the display weight we want; attach Nunito as a glyph
		# fallback so anything Lilita doesn't have falls through to Nunito
		# instead of rendering as a tofu rectangle.
		if nunito != null:
			lilita.fallbacks = [nunito]
		font_display = lilita
		# Stat numerals use the raw Lilita font — font-level spacing_bottom
		# wasn't reliable for centering caps across orb sizes (the natural
		# Lilita line metrics put caps in the upper portion of the line box,
		# AND the SphereOrb's drop shadow shifts the painted "visual center"
		# below the container's geometric center, so any single spacing
		# value either over- or under-corrects). Instead, the orb labels in
		# Card2D (_build_full_layout_v3 / _build_orb_number_label) apply an
		# explicit Y offset on the label rect — pixel-deterministic, per
		# call site. See ORB_NUMERAL_Y_OFFSET in Card2D.gd.
		font_stat = lilita
		print("[GameTheme] font_display and font_stat set to Lilita One")
	else:
		# Final fallback to Cinzel.
		push_warning("[GameTheme] Lilita One unavailable — using Cinzel fallback")
		var cinzel_fallback := load("res://assets/fonts/Cinzel-Variable.ttf") as Font
		if cinzel_fallback is FontFile and nunito != null:
			(cinzel_fallback as FontFile).fallbacks = [nunito]
		font_display = cinzel_fallback
		# Same approach as the Lilita branch — explicit per-label Y offset
		# in Card2D handles centering; the font itself stays unmodified.
		font_stat = cinzel_fallback

	# Body text: Nunito Regular with HEAVIER embolden to pair with Lilita One's
	# weight. Was 0.35 (SemiBold) when paired with Cinzel; Lilita's chunky
	# display weight wants a true Bold body to balance — bumped to 0.55.
	# At 11pt this reads firmly against the dark text well and survives anti-
	# aliasing, while still being a CLEAN body font (not a display font used
	# as body text, which would be illegible).
	var nunito_body := FontVariation.new()
	nunito_body.base_font = nunito
	nunito_body.variation_embolden = 0.55
	font_body = nunito_body
	# Heavier embolden for [b] tags so keyword highlighting actually changes
	# weight, not just colour. 0.85 reads as a true ExtraBold against the 0.55
	# Bold body — the weight jump is the AAA convention (MtG uses bold alone
	# for keywords; StS and Hearthstone pair bold with a colour shift).
	var nunito_bold := FontVariation.new()
	nunito_bold.base_font = nunito
	nunito_bold.variation_embolden = 0.85
	font_body_bold = nunito_bold

	# Combat HUD chrome uses Cinzel (engraved Roman serif) for AAA dark-fantasy
	# gravitas. Kept SEPARATE from font_display/font_stat (Lilita One) on purpose:
	# Card2D's orb numerals carry per-label pixel Y-offsets tuned to Lilita's
	# metrics, so swapping the global card font would misalign every card face.
	# The HUD has no such tuning, so it can carry the serif freely. Two weights:
	# SemiBold (640) for header/caption text, Black (860) for big stat numerals —
	# the chunky-numeral convention shared by Hearthstone / MtG Arena stat orbs.
	var cinzel := load("res://assets/fonts/Cinzel-Variable.ttf") as FontFile
	if cinzel != null:
		if nunito != null:
			cinzel.fallbacks = [nunito]
		var title := FontVariation.new()
		title.base_font = cinzel
		title.variation_opentype = {"wght": 640}
		font_title = title
		var title_black := FontVariation.new()
		title_black.base_font = cinzel
		title_black.variation_opentype = {"wght": 860}
		font_title_black = title_black
		print("[GameTheme] font_title/font_title_black set to Cinzel")
	else:
		push_warning("[GameTheme] Cinzel unavailable — HUD falls back to display/stat font")
		font_title = font_display
		font_title_black = font_stat
	# Flip USE_NEW_FRAME below to false to revert to the old card_frame_ornate.png.
	var ornate_path = "res://assets/ui/card_frame_ornate.png"
	if USE_NEW_FRAME:
		_load_new_frames()
		var new_path = "res://assets/frames/frame_creature_common.png"
		if ResourceLoader.exists(new_path):
			ornate_path = new_path
	if ResourceLoader.exists(ornate_path):
		tex_card_frame_ornate = load(ornate_path)
	print("[GameTheme] tex_card_frame_ornate (default) loaded from: ", ornate_path,
		"  USE_NEW_FRAME=", USE_NEW_FRAME)
	tex_icon_sword = load("res://assets/icons/sword.png")
	tex_icon_heart = load("res://assets/icons/heart.png")

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
	# Painted icons (downloaded CC0 from OpenGameArt) prefer over silhouettes
	# where available — they match Slay-the-Spire's painted HUD aesthetic.
	var heart_painted = "res://assets/icons/map/hud_heart_painted.png"
	tex_hud_heart = load(heart_painted) if ResourceLoader.exists(heart_painted) \
		else load("res://assets/icons/map/hud_heart.png")
	var gold_painted = "res://assets/icons/map/hud_gold_painted.png"
	tex_hud_gold = load(gold_painted) if ResourceLoader.exists(gold_painted) \
		else load("res://assets/icons/map/hud_gold.png")
	var potion_painted = "res://assets/icons/map/hud_potion_painted.png"
	tex_hud_potion = load(potion_painted) if ResourceLoader.exists(potion_painted) \
		else load("res://assets/icons/map/hud_potion.png")
	tex_hud_relic = load("res://assets/icons/map/hud_relic.png")
	tex_hud_deck = load("res://assets/icons/map/hud_deck.png")

	# Card stat icons — hand-painted assets that replace the procedural
	# GemOrb cost/ATK/HP shapes. Heart reuses the existing painted HUD
	# texture (Kenney pack) so all three stat icons share the same painted
	# vocabulary. Cost+sword from pbmojART's Fantasy RPG Icons (CC-BY 3.0,
	# credited in CREDITS.md).
	var cost_path := "res://assets/icons/stats/cost_runestone.png"
	if ResourceLoader.exists(cost_path):
		tex_stat_cost = load(cost_path)
	var atk_path := "res://assets/icons/stats/atk_sword.png"
	if ResourceLoader.exists(atk_path):
		tex_stat_atk = load(atk_path)
	tex_stat_hp = tex_hud_heart  # reuse painted heart from HUD set
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
const MANA_BLUE      := Color(0.35, 0.58, 0.95, 1.0)
const HEALTH_GREEN   := Color(0.25, 0.85, 0.35, 1.0)
const ATK_RED        := Color(1.0, 0.35, 0.25, 1.0)
const ATK_BUFFED     := Color(1.0, 0.8, 0.2, 1.0)
const HP_DAMAGED     := Color(1.0, 0.3, 0.3, 1.0)
const SPELL_PURPLE   := Color(0.70, 0.55, 0.95, 1.0)
const KEYWORD_GOLD   := Color(1.0, 0.85, 0.45, 1.0)
const DESC_DIM       := Color(0.78, 0.74, 0.62, 1.0)
const FLOOP_BLUE     := Color(0.30, 0.70, 0.95, 1.0)
const BOARD_BG       := Color(0.075, 0.065, 0.055, 1.0)
const LANE_BORDER    := Color(0.38, 0.28, 0.15, 0.85)
const DIMMED         := Color(0.50, 0.50, 0.50, 0.70)
const RARITY_COMMON  := Color(0.75, 0.75, 0.75, 1.0)
const RARITY_UNCOMMON := Color(0.40, 0.60, 0.95, 1.0)
const RARITY_RARE    := Color(0.95, 0.78, 0.22, 1.0)
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
# Parchment well: light tan with near-black body text. Contrast ~11.8:1 → AAA.
const PARCHMENT_LIGHT := Color(0.910, 0.863, 0.753, 1.0)   # #E8DCC0
const PARCHMENT_TEXT  := Color(0.141, 0.094, 0.063, 1.0)   # #241810
# Rarity gem colours (visible at-a-glance per Hearthstone gem-on-art convention).
const GEM_STARTER     := Color(0.627, 0.627, 0.627, 1.0)   # #A0A0A0 muted grey
const GEM_COMMON      := Color(0.95,  0.95,  0.95,  1.0)   # white
const GEM_UNCOMMON    := Color(0.357, 0.525, 0.969, 1.0)   # #5B86F7
const GEM_RARE        := Color(0.961, 0.784, 0.259, 1.0)   # #F5C842 (matches ATK)
# Frame trim colours per rarity — four distinct hues so the frame itself
# carries the rarity signal (Marvel-Snap-style). Combined with the small
# rarity gem at the art/text boundary you get two redundant cues, which is
# the AAA convention for at-a-glance readability.
const FRAME_TRIM_STARTER  := Color(0.706, 0.631, 0.471, 1.0)  # #B4A178 warm brass (was #8A7C5E)
const FRAME_TRIM_COMMON   := Color(0.831, 0.745, 0.541, 1.0)  # #D4BE8A bright gilt (was #B3A077)
const FRAME_TRIM_UNCOMMON := Color(0.529, 0.667, 0.851, 1.0)  # #87AAD9 cool blue gilt (was #6E8AB0)
const FRAME_TRIM_RARE     := Color(0.961, 0.784, 0.259, 1.0)  # #F5C842 bright gold (unchanged — already pops)

# ── Font Sizes ──
const FONT_HEADER := 26
const FONT_SUBHEADER := 19
const FONT_BODY := 15
const FONT_TITLE := 34


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


static func make_panel_style(bg: Color = PARCHMENT, border: Color = PARCHMENT_BORDER,
		border_w: int = 2, corner: int = 16, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = border_w
	s.border_width_bottom = border_w
	s.border_width_left = border_w
	s.border_width_right = border_w
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	return s


static func make_btn_style(bg: Color, border: Color = GILT, corner: int = 20) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_width_left = 2
	s.border_width_right = 2
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	return s


# ═══════════════════════════════════════════
#  BUTTON FACTORY
# ═══════════════════════════════════════════

func make_themed_button(text: String, bg: Color, min_size: Vector2 = Vector2(160, 44),
		font_size: int = FONT_BODY, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE  # drop the default Godot focus rectangle
	btn.add_theme_font_size_override("font_size", font_size)
	# Apply the display font so buttons inherit the game's typography instead
	# of falling back to Godot's default sans-serif. Guarded for the case where
	# font_display hasn't loaded yet (very early scene init).
	if font_display:
		btn.add_theme_font_override("font", font_display)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.65, 0.55, 0.6))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	btn.add_theme_constant_override("outline_size", 2)
	var normal = make_btn_style(bg, GILT, int(min_size.y / 2.0))
	btn.add_theme_stylebox_override("normal", normal)
	var hover = normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = bg.darkened(0.40)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)
	return btn


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

	# Chart-language panel: dark ink body with a tan rule (the map screen's
	# tooltip/cartouche kit). The accent survives as a small rule under the
	# title and the hotspot glow behind the banner, so choices still read
	# related-but-distinct without becoming colored rectangles.
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.048, 0.040, 0.96 if not disabled else 0.60)
	s.border_color = Color(0.60, 0.51, 0.34,
		0.90 if not disabled else 0.35)
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.shadow_color = Color(0, 0, 0, 0.65)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)
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

	# Icon column — TextureRect if a path was provided, else a big colored
	# glyph from the title's first character. Sized so it visually anchors
	# the banner without dominating it.
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
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
			tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			if layer == 0:
				for prop in ["offset_left", "offset_top",
						"offset_right", "offset_bottom"]:
					tex.set(prop, 2.0)
				tex.modulate = Color(0, 0, 0, 0.55 if not disabled else 0.30)
			else:
				tex.modulate = Color(0.82, 0.74, 0.56) if not disabled \
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
	title_lbl.add_theme_font_size_override("font_size", 22)
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
	body_lbl.add_theme_font_size_override("font_size", 13)
	body_lbl.add_theme_color_override("font_color",
		Color(0.86, 0.82, 0.70, 0.92) if not disabled else Color(0.65, 0.55, 0.45, 0.75))
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
	"stone_wall": "construct", "iron_bastion": "construct", "warding_stone": "construct",
	"siege_golem": "construct", "riteforge": "construct",
	"golem": "construct", "stone_sentinel": "construct",
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

# Bright variants — used by render paths that paint the name on a DARK banner
# (v5 engraved path, legacy _build_full_layout). Same tribes, hand-tuned for
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
	var btn := TextureButton.new()
	var tex: Texture2D = load(GEAR_ICON_PATH) as Texture2D
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.anchor_left = 0.0
	btn.anchor_right = 0.0
	btn.anchor_top = 0.0
	btn.anchor_bottom = 0.0
	btn.offset_left = offset.x
	btn.offset_right = offset.x + size
	btn.offset_top = offset.y
	btn.offset_bottom = offset.y + size
	btn.custom_minimum_size = Vector2(size, size)
	btn.tooltip_text = "Settings"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Gilt tint at rest, bright gold on hover — matches the rest of the HUD's
	# parchment palette. Modulate (not theme color) since this is a TextureButton.
	btn.modulate = Color(0.82, 0.66, 0.30, 0.85)
	btn.mouse_entered.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate", Color(1.0, 0.88, 0.35, 1.0), 0.12))
	btn.mouse_exited.connect(func():
		var tw := btn.create_tween()
		tw.tween_property(btn, "modulate", Color(0.82, 0.66, 0.30, 0.85), 0.12))
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


func make_relic_chip(rid: String, size: int = 40) -> Panel:
	# Ornate framed chip for a relic icon — used by the HUD strip, shop cards,
	# the starting-relic-pick tiles, and the main-menu relic list. The frame is
	# a dark backing + gilt rim + tier-tinted shadow halo (boss=purple,
	# combat=warm bronze, utility=green, starting=gold) for at-a-glance rarity
	# the way WoW item borders cue quality. SVG silhouettes get the gilt tint
	# they were designed for; painted PNGs render at full color.
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(size, size)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP

	var r := RelicDB.get_relic(rid)
	chip.tooltip_text = "%s — %s" % [r.get("name", rid), r.get("desc", "")]

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


func make_relic_card(rid: String, bg: Color, min_size: Vector2 = Vector2(220, 120),
		price: int = -1) -> Button:
	# A relic "card" button: gilt-trimmed panel with the relic's icon stacked
	# above its name + description (and an optional price line for the shop).
	# Built as an empty Button + child VBox (mouse_filter IGNORE) so the whole
	# tile is one hit target and the icon gets a controlled size — the source
	# SVGs are 512px, so they can't be dropped into Button.icon directly. The
	# icon comes from RelicDB.get_relic_icon by convention; if it isn't imported
	# yet the card just renders text-only instead of breaking.
	var r := RelicDB.get_relic(rid)
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "%s — %s" % [r.get("name", rid), r.get("desc", "")]
	var normal := make_btn_style(bg, GILT, 10)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	hover.border_color = GILT_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = bg.darkened(0.40)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 8
	col.offset_bottom = -8
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var chip := make_relic_chip(rid, 56)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var name_lbl := make_label(r.get("name", rid), FONT_BODY, KEYWORD_GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)
	var desc_lbl := make_label(r.get("desc", ""), 12, IVORY)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)
	if price >= 0:
		var price_lbl := make_label("— %dg —" % price, FONT_BODY, GILT)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(price_lbl)
	return btn


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
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("outline_size", 3)
	return lbl


# ═══════════════════════════════════════════
#  RARITY HELPERS
# ═══════════════════════════════════════════

static func rarity_color(rarity: String) -> Color:
	match rarity:
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
		"common":   return Color(1.000, 1.000, 1.000, 0.00)  # no wash
		"uncommon": return Color(0.300, 0.500, 0.950, 0.07)
		"rare":     return Color(1.000, 0.780, 0.220, 0.07)
		_:          return Color(1.000, 1.000, 1.000, 0.00)


# ═══════════════════════════════════════════
#  V3 FRAME VARIANT LOADER + LOOKUP
# ═══════════════════════════════════════════

func _load_new_frames() -> void:
	# Loads all 9 baked v3 variants into _new_frames. Missing files fall back
	# to creature_common at lookup time.
	var keys = [
		"creature_starter", "creature_common", "creature_uncommon", "creature_rare",
		"spell_starter",    "spell_common",    "spell_uncommon",    "spell_rare",
		"curse",
	]
	for k in keys:
		var p = "res://assets/frames/frame_%s.png" % k
		if ResourceLoader.exists(p):
			_new_frames[k] = load(p)
	_load_keyword_icons()


func _load_keyword_icons() -> void:
	# Game-icons.net SVGs, CC-BY 3.0 (credited in CREDITS.md).
	var keywords = [
		"armored", "swift", "ranged", "thorns", "regenerate", "summon",
		"last_stand", "piercing", "sacrifice", "exhaust", "retain",
		"wither", "on_enter", "on_death", "floop", "adj_buff",
	]
	for k in keywords:
		var p = "res://assets/icons/keywords/%s.svg" % k
		if ResourceLoader.exists(p):
			_keyword_icons[k] = load(p)


func get_keyword_icon(keyword: String) -> Texture2D:
	return _keyword_icons.get(keyword, null)


func get_card_frame(card_data: Dictionary) -> Texture2D:
	# Returns the appropriate v3 frame for a card. Falls back to the legacy
	# tex_card_frame_ornate if USE_NEW_FRAME is off or the file is missing.
	if not USE_NEW_FRAME or _new_frames.is_empty():
		return tex_card_frame_ornate
	var ct: String = "spell" if String(card_data.get("type", "creature")) == "spell" else "creature"
	if CardDB.is_curse(String(card_data.get("id", ""))) or String(card_data.get("type", "")) == "curse":
		return _new_frames.get("curse", tex_card_frame_ornate)
	var rarity: String = String(card_data.get("rarity", "common"))
	if rarity not in ["starter", "common", "uncommon", "rare"]:
		rarity = "common"
	var key = "%s_%s" % [ct, rarity]
	return _new_frames.get(key, _new_frames.get("creature_common", tex_card_frame_ornate))


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
		if not us.brightness_changed.is_connected(_on_brightness_changed_static):
			us.brightness_changed.connect(_on_brightness_changed_static.bind(bright_rect))

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


static func _make_decorative_frame(frame_color: Color) -> Control:
	var frame := Control.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Render above all sibling UI regardless of add-order
	frame.z_as_relative = false
	frame.z_index = 10

	var inset := 14.0
	var clen := 40.0    # corner piece length
	var w := 1.5

	var dim := Color(frame_color.r, frame_color.g, frame_color.b,
		frame_color.a * 0.5)

	# Corner L-shapes (8 rects: 2 per corner)
	_add_frame_rect(frame, Vector2(inset, inset), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(inset, inset), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - clen, inset), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - w, inset), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(inset, 900 - inset - w), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(inset, 900 - inset - clen), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - clen, 900 - inset - w), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - w, 900 - inset - clen), Vector2(w, clen), frame_color)

	# Thin connecting lines between corners
	_add_frame_rect(frame, Vector2(inset + clen, inset),
		Vector2(1600 - 2 * (inset + clen), w), dim)
	_add_frame_rect(frame, Vector2(inset + clen, 900 - inset - w),
		Vector2(1600 - 2 * (inset + clen), w), dim)
	_add_frame_rect(frame, Vector2(inset, inset + clen),
		Vector2(w, 900 - 2 * (inset + clen)), dim)
	_add_frame_rect(frame, Vector2(1600 - inset - w, inset + clen),
		Vector2(w, 900 - 2 * (inset + clen)), dim)

	# Small diamond dots at the four corners
	var ds := 5.0
	var bright := Color(frame_color.r * 1.4, frame_color.g * 1.4,
		frame_color.b * 1.4, minf(frame_color.a * 1.5, 1.0))
	_add_frame_rect(frame, Vector2(inset - ds / 2, inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(1600 - inset - ds / 2, inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(inset - ds / 2, 900 - inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(1600 - inset - ds / 2, 900 - inset - ds / 2),
		Vector2(ds, ds), bright)

	return frame


static func _add_frame_rect(parent: Control, pos: Vector2, sz: Vector2,
		col: Color) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


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

	# ── diamond separator — texture-based so it renders even if the display
	# font is missing the U+25C6 glyph.
	var sep := HBoxContainer.new()
	sep.alignment = BoxContainer.ALIGNMENT_CENTER
	sep.add_theme_constant_override("separation", 6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line_col := Color(color.r, color.g, color.b, 0.30)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(50, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = line_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(left)

	var diamond_tex := load("res://assets/icons/diamond.png") as Texture2D
	if diamond_tex != null:
		var diamond := TextureRect.new()
		diamond.texture = diamond_tex
		diamond.custom_minimum_size = Vector2(10, 10)
		diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		diamond.modulate = Color(color.r, color.g, color.b, 0.55)
		diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sep.add_child(diamond)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(50, 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.color = line_col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(right)

	vbox.add_child(sep)
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


func pulse_label(lbl: Label, flash_color: Color = Color(1.0, 0.85, 0.30)) -> void:
	# One-shot color-flash + scale punch on a label. Used by Shop / Rest / Reward
	# to give gold and HP labels feedback when they change.
	if lbl == null or not is_instance_valid(lbl):
		return
	var rest_color: Color = lbl.get_theme_color("font_color")
	var rest_scale := lbl.scale
	lbl.pivot_offset = lbl.size * 0.5
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", rest_scale * 1.20, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color):
			lbl.add_theme_color_override("font_color", c),
		flash_color, rest_color, 0.32)
	tw.chain().tween_property(lbl, "scale", rest_scale, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Fade-to-black scene transition. Returns the overlay so the caller can chain
# additional setup; the overlay auto-frees once the fade-in completes. Calling
# fade_in() at scene _ready time is the matched bookend.
func fade_out_then_change_scene(host: Node, target_scene: String,
		duration: float = 0.28) -> void:
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 1000
	host.get_tree().root.add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "color:a", 1.0, duration).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if host.get_tree() != null:
			host.get_tree().change_scene_to_file(target_scene)
		if is_instance_valid(overlay):
			overlay.queue_free()
	)


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
	btn.add_theme_font_size_override("font_size", font_size)
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
	return btn


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
		on_confirm: Callable = Callable()) -> void:
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
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	s.border_color = GILT_BRIGHT
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 24
	s.content_margin_bottom = 24
	s.shadow_size = 22
	s.shadow_color = Color(0, 0, 0, 0.6)
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
	msg_lbl.add_theme_font_size_override("font_size", 16)
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
		layer.queue_free())
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

func show_deck_picker(host: Node, title: String, type_filter: String = "",
		allow_cancel: bool = false) -> int:
	## Modal grid of the run deck; the player clicks a card. Returns the chosen
	## RunState.deck INDEX, or -1 if dismissed / nothing eligible.
	##   type_filter: "" (any) | "creature" | "spell"
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return -1
	# Resolve eligible deck indices first — bail before building UI if empty.
	var eligible: Array[int] = []
	for i in RunState.deck.size():
		var d: Dictionary = RunState.get_upgraded_card_data(i)
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

	var title_lbl := make_label(title, FONT_TITLE, GILT_BRIGHT, true)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	# -2 = still open, -1 = cancelled, >=0 = picked deck index.
	var result := {"index": -2}
	var batch := 6
	for bstart in range(0, eligible.size(), batch):
		for k in range(batch):
			var ei := bstart + k
			if ei >= eligible.size():
				break
			var di: int = eligible[ei]
			var data: Dictionary = RunState.get_upgraded_card_data(di)
			var slot := Control.new()
			slot.custom_minimum_size = Vector2(220, 300)
			grid.add_child(slot)
			var card = card_scene.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = data.get("id", "")
			card.is_on_battlefield = true
			card.static_display = true
			slot.add_child(card)
			var btn := Button.new()
			btn.flat = true
			btn.focus_mode = Control.FOCUS_NONE
			btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			var captured: int = di
			btn.pressed.connect(func():
				result["index"] = captured
				layer.queue_free())
			slot.add_child(btn)
		if not is_instance_valid(layer):
			return -1
		await host.get_tree().process_frame

	if allow_cancel:
		var cancel := make_back_button("CANCEL", Vector2(170, 44))
		cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cancel.pressed.connect(func():
			result["index"] = -1
			layer.queue_free())
		root.add_child(cancel)

	while result["index"] == -2 and is_instance_valid(layer):
		await host.get_tree().process_frame
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
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	s.border_color = GILT_BRIGHT
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 24
	s.content_margin_bottom = 24
	s.shadow_size = 22
	s.shadow_color = Color(0, 0, 0, 0.6)
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
		await host.get_tree().process_frame
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
	if host == null or not is_instance_valid(host) or host.get_tree() == null:
		return
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 1000
	host.get_tree().root.add_child(overlay)
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	tw.tween_callback(overlay.queue_free)
