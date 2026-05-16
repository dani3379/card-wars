extends Node

# ── Fonts ──
var font_display: Font = null   # Cinzel SemiBold (wght 600) — card names, type, FLOOP
var font_stat: Font = null      # Cinzel Black (wght 800) — cost, ATK, HP numerals
var font_body: Font = null      # Nunito Regular + embolden 0.35 — description text
var font_body_bold: Font = null # Nunito Regular + embolden 0.7 — keyword [b] tags

# ── Textures ──
var tex_card_frame: Texture2D = null
var tex_card_frame_ornate: Texture2D = null
var tex_panel_bg: Texture2D = null
var tex_panel_ornate: Texture2D = null
var tex_icon_sword: Texture2D = null
var tex_icon_heart: Texture2D = null
var tex_icon_shield: Texture2D = null
var tex_icon_diamond: Texture2D = null
var tex_icon_skull: Texture2D = null
var tex_icon_fire: Texture2D = null
var tex_icon_crown: Texture2D = null
var tex_icon_book: Texture2D = null
var tex_icon_campfire: Texture2D = null
var tex_icon_question: Texture2D = null

# ── Slay-the-Spire-style silhouette map node icons (Kenney CC0 board-game-icons). ──
var tex_node_combat: Texture2D = null
var tex_node_elite: Texture2D = null
var tex_node_rest: Texture2D = null
var tex_node_shop: Texture2D = null
var tex_node_event: Texture2D = null
var tex_node_boss: Texture2D = null

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

# ── Map endpoint markers (Kenney CC0). ──
var tex_map_start: Texture2D = null
var tex_map_arrow_right: Texture2D = null

# ── NinePatch panel textures (Kenney Fantasy UI Borders CC0) ──
var tex_panel_9p: Texture2D = null
var tex_panel_9p_alt: Texture2D = null

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

const NINEPATCH_MARGIN := 18
const USE_NEW_FRAME := true  # flip to false to revert to assets/ui/card_frame_ornate.png
# v4 procedural card frame — drawn entirely in Godot, no PNG dependency.
# Adds Hearthstone-canonical stat colors (blue cost / yellow ATK / red HP), a
# visible rarity gem, and 180x252 card dimensions. Flip false to revert to v3.
const USE_PROCEDURAL_FRAME := true

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
	var cinzel := load("res://assets/fonts/Cinzel-Variable.ttf") as Font

	var cinzel_display := FontVariation.new()
	cinzel_display.base_font = cinzel
	cinzel_display.variation_opentype = {&"wght": 600}
	# spacing_bottom = -3 gives a ~1.5px optical-center nudge (caps-only text
	# sits above geometric center because the line box reserves descender
	# room the glyphs don't use). Was -6 earlier; that was over-correcting
	# for a separate bug where POINT_NAME's y was 20px wrong — fixed now via
	# pixel-measured POINT_* constants from tools/measure_frame.py.
	cinzel_display.spacing_bottom = -3
	font_display = cinzel_display

	var cinzel_stat := FontVariation.new()
	cinzel_stat.base_font = cinzel
	cinzel_stat.variation_opentype = {&"wght": 800}
	cinzel_stat.spacing_bottom = -3
	font_stat = cinzel_stat

	# Body text: Nunito Regular wrapped in a FontVariation with variation_embolden
	# so the rendered strokes thicken without needing a separate SemiBold .ttf.
	# At 9–11 pt, anti-aliasing eats Nunito Regular's strokes and the text reads
	# as grey smudge even when the color-contrast math is fine; embolden 0.35
	# restores stroke weight close to a true SemiBold (~600 wt) and defeats the
	# AA-thinning effect AAA card games address with bold body fonts.
	var nunito := load("res://assets/fonts/Nunito-Regular.ttf") as Font
	var nunito_body := FontVariation.new()
	nunito_body.base_font = nunito
	nunito_body.variation_embolden = 0.35
	font_body = nunito_body
	# Heavier embolden for [b] tags so keyword highlighting actually changes
	# weight, not just colour. 0.7 reads as a true Bold against the 0.35
	# SemiBold body — the weight jump is the AAA convention (MtG uses bold
	# alone for keywords; StS and Hearthstone pair bold with a colour shift).
	var nunito_bold := FontVariation.new()
	nunito_bold.base_font = nunito
	nunito_bold.variation_embolden = 0.7
	font_body_bold = nunito_bold
	tex_card_frame = load("res://assets/ui/card_frame.png")
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
	tex_panel_bg = load("res://assets/ui/panel_bg.png")
	tex_panel_ornate = load("res://assets/ui/panel_ornate.png")
	tex_icon_sword = load("res://assets/icons/sword.png")
	tex_icon_heart = load("res://assets/icons/heart.png")
	tex_icon_shield = load("res://assets/icons/shield.png")
	tex_icon_diamond = load("res://assets/icons/diamond.png")
	tex_icon_skull = load("res://assets/icons/skull.png")
	tex_icon_fire = load("res://assets/icons/fire.png")
	tex_icon_crown = load("res://assets/icons/crown.png")
	tex_icon_book = load("res://assets/icons/book.png")
	tex_icon_campfire = load("res://assets/icons/campfire.png")
	var qpath = "res://assets/icons/kenney_game-icons/PNG/White/1x/question.png"
	if ResourceLoader.exists(qpath):
		tex_icon_question = load(qpath)

	# Map node icons — hand-drawn fantasy line-art from game-icons.net
	# (CC-BY 3.0 by lorc & delapouite — credited in CREDITS.md). These look
	# more "drawn into the parchment" than the Kenney silhouettes did and
	# don't all read as the same shape at a glance.
	var gi_dir := "res://assets/icons/game-icons/"
	tex_node_combat = load(gi_dir + "crossed-swords.svg")
	tex_node_elite = load(gi_dir + "horned-skull.svg")
	tex_node_rest = load(gi_dir + "campfire.svg")
	tex_node_shop = load(gi_dir + "shop.svg")
	tex_node_event = load(gi_dir + "perspective-dice-six-faces-random.svg")
	tex_node_boss = load(gi_dir + "dragon-head.svg")
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
	# Map endpoint markers. tex_map_start is now an unfurled scroll (Lorc,
	# game-icons.net) used as a decoration on the START banner.
	var scroll_path := "res://assets/icons/game-icons/scroll-unfurled.svg"
	if ResourceLoader.exists(scroll_path):
		tex_map_start = load(scroll_path)
	var arrow_path := "res://assets/icons/kenney_game-icons/PNG/Black/2x/arrowRight.png"
	if ResourceLoader.exists(arrow_path):
		tex_map_arrow_right = load(arrow_path)
	var np_path = "res://assets/ui/kenney_fantasy-ui-borders/PNG/Double/Panel/panel-009.png"
	if ResourceLoader.exists(np_path):
		tex_panel_9p = load(np_path)
	var np_alt = "res://assets/ui/kenney_fantasy-ui-borders/PNG/Double/Panel/panel-005.png"
	if ResourceLoader.exists(np_alt):
		tex_panel_9p_alt = load(np_alt)

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
	#    isn't visible at card scale (180x252).
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
	# when tiled across the 180×252 card it stretches horizontally and
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


# ── Color Palette ──
const PARCHMENT      := Color(0.12, 0.09, 0.07, 0.94)
const PARCHMENT_LITE := Color(0.16, 0.13, 0.10, 0.92)
const PARCHMENT_BORDER := Color(0.60, 0.45, 0.22, 1.0)
const GILT           := Color(0.82, 0.66, 0.30, 1.0)
const GILT_BRIGHT    := Color(1.0, 0.88, 0.35, 1.0)
const IVORY          := Color(0.96, 0.92, 0.78, 1.0)
const BLOOD_RED      := Color(0.85, 0.22, 0.18, 1.0)
const MANA_BLUE      := Color(0.35, 0.58, 0.95, 1.0)
const MANA_BLUE_DIM  := Color(0.12, 0.16, 0.30, 1.0)
const HEALTH_GREEN   := Color(0.25, 0.85, 0.35, 1.0)
const HEALTH_BAR_BG  := Color(0.12, 0.07, 0.05, 0.95)
const ATK_RED        := Color(1.0, 0.35, 0.25, 1.0)
const ATK_BUFFED     := Color(1.0, 0.8, 0.2, 1.0)
const HP_DAMAGED     := Color(1.0, 0.3, 0.3, 1.0)
const SPELL_PURPLE   := Color(0.70, 0.55, 0.95, 1.0)
const KEYWORD_GOLD   := Color(1.0, 0.85, 0.45, 1.0)
const DESC_DIM       := Color(0.78, 0.74, 0.62, 1.0)
const FLOOP_BLUE     := Color(0.30, 0.70, 0.95, 1.0)
const BOARD_BG       := Color(0.075, 0.065, 0.055, 1.0)
const BOARD_TOP      := Color(0.10, 0.055, 0.045, 1.0)
const BOARD_BOT      := Color(0.06, 0.075, 0.055, 1.0)
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
const FONT_SMALL := 12
const FONT_STAT := 22
const FONT_COST := 17
const FONT_TITLE := 34
const FONT_CARD_NAME := 14

# ── Card Dimensions ──
# Authoritative card size lives in Card2D.gd (CARD_W/CARD_H). This constant
# stays for any legacy reader; bump in lockstep if Card2D.CARD_SIZE changes.
const CARD_SIZE := Vector2(180, 252)
const CARD_BORDER := 2
const CARD_CORNER := 8

# ── Node map icons ──
const MAP_ICONS: Dictionary = {
	"combat": "⚔", "elite": "★", "boss": "☠",
	"rest": "♨", "shop": "🪙", "event": "?",
}


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


static func make_card_style(bg: Color, border: Color = GILT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = CARD_BORDER
	s.border_width_bottom = CARD_BORDER
	s.border_width_left = CARD_BORDER
	s.border_width_right = CARD_BORDER
	s.corner_radius_top_left = CARD_CORNER
	s.corner_radius_top_right = CARD_CORNER
	s.corner_radius_bottom_left = CARD_CORNER
	s.corner_radius_bottom_right = CARD_CORNER
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
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


static func make_slot_style(is_enemy: bool, lane_idx: int) -> StyleBoxFlat:
	# Slots must be clearly visible — alternating brightness per lane
	var base_alpha = 0.10 if lane_idx % 2 == 0 else 0.15
	var tint: Color
	if is_enemy:
		tint = Color(0.22, 0.08, 0.06, base_alpha)
	else:
		tint = Color(0.06, 0.14, 0.08, base_alpha)
	var s := StyleBoxFlat.new()
	s.bg_color = tint
	s.border_color = LANE_BORDER
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	# Inner padding so cards don't press against slot edges
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


# ═══════════════════════════════════════════
#  BUTTON FACTORY
# ═══════════════════════════════════════════

static func make_themed_button(text: String, bg: Color, min_size: Vector2 = Vector2(160, 44),
		font_size: int = FONT_BODY, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.65, 0.55, 0.6))
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


# ═══════════════════════════════════════════
#  LABEL FACTORY
# ═══════════════════════════════════════════

static func make_label(text: String, font_size: int = FONT_BODY, color: Color = IVORY,
		outline: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline:
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("outline_size", 3)
	return lbl


# ═══════════════════════════════════════════
#  HP BAR FACTORY
# ═══════════════════════════════════════════

static func make_hp_bar(current: int, max_hp: int, width: float = 150.0, height: float = 24.0,
		fill_color: Color = BLOOD_RED) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(width, height)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Outer frame — rounded border
	var frame := Panel.new()
	frame.size = Vector2(width, height)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = HEALTH_BAR_BG
	frame_style.border_color = Color(0.35, 0.25, 0.15, 0.8)
	frame_style.border_width_top = 1
	frame_style.border_width_bottom = 1
	frame_style.border_width_left = 1
	frame_style.border_width_right = 1
	frame_style.corner_radius_top_left = 4
	frame_style.corner_radius_top_right = 4
	frame_style.corner_radius_bottom_left = 4
	frame_style.corner_radius_bottom_right = 4
	frame.add_theme_stylebox_override("panel", frame_style)
	container.add_child(frame)
	# Fill — inset 1px so it doesn't cover the border
	var fill := Panel.new()
	fill.name = "Fill"
	var ratio = clampf(float(current) / float(max_hp), 0.0, 1.0)
	fill.position = Vector2(1, 1)
	fill.size = Vector2((width - 2) * ratio, height - 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	fill.add_theme_stylebox_override("panel", fill_style)
	container.add_child(fill)
	# Highlight strip at top of fill — gives a gloss/depth feel
	var gloss := ColorRect.new()
	gloss.position = Vector2(1, 1)
	gloss.size = Vector2((width - 2) * ratio, maxf(3.0, height * 0.2))
	gloss.color = Color(1, 1, 1, 0.12)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(gloss)
	# Text overlay
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = "%d / %d" % [current, max_hp]
	lbl.size = Vector2(width, height)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", IVORY)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(lbl)
	return container


# ═══════════════════════════════════════════
#  MANA PIP FACTORY
# ═══════════════════════════════════════════

static func make_mana_pips(current: int, max_mana: int, pip_size: float = 20.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(max_mana):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pip_style := StyleBoxFlat.new()
		var r := int(pip_size * 0.5)
		pip_style.corner_radius_top_left = r
		pip_style.corner_radius_top_right = r
		pip_style.corner_radius_bottom_left = r
		pip_style.corner_radius_bottom_right = r
		if i < current:
			pip_style.bg_color = MANA_BLUE
			pip_style.border_color = Color(0.55, 0.75, 1.0, 0.6)
			# Inner glow — brighter top half via shadow trick
			pip_style.shadow_color = Color(0.5, 0.7, 1.0, 0.25)
			pip_style.shadow_size = 3
		else:
			pip_style.bg_color = MANA_BLUE_DIM
			pip_style.border_color = Color(0.25, 0.30, 0.45, 0.5)
		pip_style.border_width_top = 1
		pip_style.border_width_bottom = 1
		pip_style.border_width_left = 1
		pip_style.border_width_right = 1
		pip.add_theme_stylebox_override("panel", pip_style)
		row.add_child(pip)
	return row


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


static func rarity_gem_color(rarity: String) -> Color:
	# v4 — Hearthstone-canonical rarity gem (visible at the bottom of art).
	match rarity:
		"starter":  return GEM_STARTER
		"common":   return GEM_COMMON
		"uncommon": return GEM_UNCOMMON
		"rare":     return GEM_RARE
		_:          return GEM_COMMON


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
	if String(card_data.get("type", "")) == "curse" or String(card_data.get("id", "")) == "curse":
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
		"grad_inner": Color(0.05, 0.10, 0.07, 0.25),
		"grad_outer": Color(0.01, 0.03, 0.02, 0.60),
		"vignette": 0.45,
		"particle_color": Color(0.40, 0.85, 0.55, 0.30),
		"particle_alt": Color(0.30, 0.65, 0.80, 0.20),
		"particle_count": 18,
		"particle_speed": 6.0,
		"frame_color": Color(0.30, 0.55, 0.35, 0.25),
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
static func add_atmosphere(parent: Control, screen_type: String,
		include_frame: bool = true) -> void:
	if parent.has_node("Atmosphere"):
		return
	var mood = SCREEN_MOODS.get(screen_type, SCREEN_MOODS["main_menu"])

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

	parent.add_child(atm)
	# Slot right after Background (index 0) so UI builds on top
	parent.move_child(atm, 1)


static func _make_ambient_particles(mood: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "AmbientMotes"
	p.emitting = true
	p.amount = mood.particle_count
	p.lifetime = 6.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	# Emit across the full viewport
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(800, 450)
	p.position = Vector2(800, 450)
	# Slow upward drift with lateral wobble
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = mood.particle_speed * 0.5
	p.initial_velocity_max = mood.particle_speed
	p.gravity = Vector2(0, 0)
	p.linear_accel_min = -2.0
	p.linear_accel_max = 2.0
	# Size
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
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

static func make_screen_title(text: String, color: Color = GILT_BRIGHT,
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# ── ◆ ── separator
	var sep := HBoxContainer.new()
	sep.alignment = BoxContainer.ALIGNMENT_CENTER
	sep.add_theme_constant_override("separation", 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line_col := Color(color.r, color.g, color.b, 0.30)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(50, 1)
	left.color = line_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(left)

	var diamond := Label.new()
	diamond.text = " ◆ "
	diamond.add_theme_font_size_override("font_size", 8)
	diamond.add_theme_color_override("font_color",
		Color(color.r, color.g, color.b, 0.45))
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(diamond)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(50, 1)
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
#  NINEPATCH CARD FRAME
# ═══════════════════════════════════════════

func make_card_frame(tint: Color = GILT) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex_card_frame
	np.patch_margin_left = NINEPATCH_MARGIN
	np.patch_margin_right = NINEPATCH_MARGIN
	np.patch_margin_top = NINEPATCH_MARGIN
	np.patch_margin_bottom = NINEPATCH_MARGIN
	np.modulate = tint
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


func make_panel_frame(tint: Color = Color(0.45, 0.35, 0.20, 0.85)) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex_panel_bg
	np.patch_margin_left = NINEPATCH_MARGIN
	np.patch_margin_right = NINEPATCH_MARGIN
	np.patch_margin_top = NINEPATCH_MARGIN
	np.patch_margin_bottom = NINEPATCH_MARGIN
	np.modulate = tint
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


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


## Creature art aliases — map a card-name slug to an existing creature art file
## (.png or .jpg, extension auto-resolved). Used for two cases:
##   1. Genuine near-duplicates (Bloodhound → hound, Mana Sprite → sprite).
##   2. Encounter-only enemy creatures (Goblin Scout, Wolf, Drake, etc.) that
##      don't have dedicated art but share an archetype with a creature that
##      does. Without these, enemy battlefield cards fall back to the blank
##      hash-tinted placeholder, which looks empty next to the player's
##      illustrated hand. EncounterDB creature names are slugged the same way
##      Card2D._find_card_art slugs them (lower, spaces→_, apostrophes stripped).
const CREATURE_ART_ALIASES: Dictionary = {
	# ── Player-side near-duplicates ──────────────────────────────────────
	"bloodhound":           "hound",
	"war_hound":            "hound",
	"mana_sprite":          "sprite",
	"stone_wall":           "iron_bastion",
	"ironclad_veteran":     "iron_bastion",

	# ── Wolves / hounds ──────────────────────────────────────────────────
	"wolf":                 "wolf_c",
	"dire_wolf":            "wolf_c",
	"alpha":                "wolf_c",
	"pup":                  "wolf_c",
	"hellhound":            "hound",

	# ── Bandits / scouts / rogues ────────────────────────────────────────
	"goblin_scout":         "e_scout",
	"runt":                 "e_goblin",
	"bandit":               "assassin",
	"thug":                 "assassin",
	"archer":               "ranger",
	"sharpshooter":         "ranger",
	"captain":              "royal_guard",
	"sellsword":            "berserker",
	"recruit":              "berserker",
	"shadow_blade":         "assassin",

	# ── Plants / fungi / swamp ───────────────────────────────────────────
	"sprout":               "thornguard",
	"spore_beast":          "thornguard",
	"spore":                "thornguard",
	"mycelium":             "hydra",
	"mire_beast":           "e_bog_lurker",
	"leech":                "e_bog_lurker",
	"swamp_hag":            "witch",
	"hydra_spawn":          "hydra",

	# ── Stone / iron / siege constructs ──────────────────────────────────
	"rock_hurler":          "e_golem",
	"granite_guard":        "e_golem",
	"fragment":             "e_golem",
	"flame_golem":          "e_golem",
	"forge_guardian":       "iron_bastion",
	"slag_heap":            "e_golem",
	"ice_elemental":        "e_golem",
	"earth_elemental":      "e_golem",
	"nexus_core":           "siege_golem",
	"iron_sentinel":        "iron_bastion",
	"iron_guard":           "iron_bastion",
	"iron_vanguard":        "iron_bastion",
	"iron_recruit":         "iron_bastion",
	"siege_engine":         "siege_golem",
	"wardens_champion":     "doom_knight",
	"display_case":         "iron_bastion",
	"trinket":              "iron_bastion",
	"temple_guardian":      "iron_bastion",
	"shard":                "iron_bastion",
	"collector_golem":      "iron_bastion",

	# ── Harpies / flyers ─────────────────────────────────────────────────
	"matron":               "harpy",
	"chick":                "harpy",

	# ── Orcs / warriors ──────────────────────────────────────────────────
	"warrior":              "berserker",
	"drummer":              "ratling",
	"chieftain":            "orc",
	"grunt":                "orc",

	# ── Skeletons / liches / undead ──────────────────────────────────────
	"skeleton":             "vengeful_spirit",
	"bone_knight":          "doom_knight",
	"bone_dragon":          "e_elder_dragon",
	"skeleton_knight":      "doom_knight",
	"lich":                 "necromancer",
	"lich_acolyte":         "necromancer",
	"dark_acolyte":         "e_cultist",
	"risen_bones":          "vengeful_spirit",
	"risen":                "vengeful_spirit",
	"phylactery":           "warden_of_graves",

	# ── Cultists ─────────────────────────────────────────────────────────
	"zealot":               "e_cultist",
	"fanatic":              "e_cultist",
	"initiate":             "e_cultist",

	# ── Dragons ──────────────────────────────────────────────────────────
	"wyrm":                 "dragon_hatchling",
	"whelp":                "dragon_hatchling",
	"elder_drake":          "e_elder_dragon",

	# ── Ghosts / spirits / hollow ────────────────────────────────────────
	"wraith":               "vengeful_spirit",
	"banshee":              "vengeful_spirit",
	"specter":              "vengeful_spirit",
	"shade":                "vengeful_spirit",
	"gravewarden":          "warden_of_graves",
	"hollow_knight":        "doom_knight",
	"void_guard":           "doom_knight",
	"hollow_champion":      "doom_knight",
	"shade_knight":         "doom_knight",

	# ── Demons / hellfire ────────────────────────────────────────────────
	"demon_soldier":        "doom_knight",
	"pit_fiend":            "e_devil_champ",
	"infernal":             "e_devil_champ",
	"imp":                  "chaos_imp",
	"hellfire_imp":         "chaos_imp",
	"devils_champion":      "e_devil_champ",
	"lesser_demon":         "chaos_imp",
	"soul_reaper":          "vengeful_spirit",
	"cinder":               "chaos_imp",
	"ember_elemental":      "chaos_imp",
	"fire_elemental":       "chaos_imp",
	"storm_elemental":      "chaos_imp",
	"spark":                "chaos_imp",

	# ── Executioners ─────────────────────────────────────────────────────
	"torturer":             "e_headsman",
	"executioner":          "e_headsman",
	"jailer":               "e_headsman",
	"condemned":            "corpse_eater",

	# ── Puppets / mirrors / doubles ──────────────────────────────────────
	"marionette":           "doppelganger",
	"puppet_knight":        "doom_knight",
	"shadow_double":        "doppelganger",
	"puppeteers_guard":     "doom_knight",
	"string":               "doppelganger",
	"mirror_knight":        "doppelganger",
	"reflection":           "doppelganger",
	"doppel":               "doppelganger",

	# ── Void / collector ─────────────────────────────────────────────────
	"void_spawn":           "chaos_imp",
	"rift_stalker":         "vengeful_spirit",
	"null_beast":           "corpse_eater",
	"void_maw":             "hydra",
	"soul_cage":            "warden_of_graves",
	"collectors_pride":     "war_titan",
	"collectors_champion":  "doom_knight",
}


func try_load_creature_art(card_id: String) -> Texture2D:
	# Direct match wins — a card with a real dedicated PNG keeps it.
	var path = "res://assets/creatures/%s.png" % card_id
	if ResourceLoader.exists(path):
		return load(path)
	# Alias fallback — share art with a thematically similar creature.
	# Try .png first, then .jpg (chaos_imp, doppelganger, warden_of_graves,
	# corpse_eater, e_devil_champ are all .jpg).
	if CREATURE_ART_ALIASES.has(card_id):
		var alias_target: String = CREATURE_ART_ALIASES[card_id]
		var alias_png := "res://assets/creatures/%s.png" % alias_target
		if ResourceLoader.exists(alias_png):
			return load(alias_png)
		var alias_jpg := "res://assets/creatures/%s.jpg" % alias_target
		if ResourceLoader.exists(alias_jpg):
			return load(alias_jpg)
	var jpg_path = "res://assets/creatures/%s.jpg" % card_id
	if ResourceLoader.exists(jpg_path):
		return load(jpg_path)
	return null


# Tried a semantic-icon placeholder system (chess pieces, skulls, etc. picked
# by card name keywords). It looked terrible — flat board-game icons clashed
# hard with the painterly style of cards that DO have illustrations. Removed.
# Cards without dedicated art now show a quiet hash-tinted gradient via
# Card2D._build_placeholder_art, which doesn't pretend to be art.


## Per-spell art overrides. The original `assets/spells/<id>.png` set had
## clusters of look-alike fire art and a few mismatches (e.g. `slash` was
## actually a fireball image). This map points each spell at a hand-picked
## painterly variant from `painterly-1`/`painterly-2` so every spell reads
## distinctly. Falls back to the loose per-id PNG if the override is missing.
const SPELL_ART_OVERRIDES: Dictionary = {
	# Damage spells
	"strike":              "res://assets/spells/painterly-1/enchant-red-1.png",
	"slash":               "res://assets/spells/painterly-1/enchant-orange-1.png",
	"smite_spell":         "res://assets/spells/painterly-2/beam-sky-1.png",
	"flame_bolt":          "res://assets/spells/painterly-1/fireball-red-1.png",
	"inferno":             "res://assets/spells/painterly-1/fireball-eerie-1.png",
	"earthquake":          "res://assets/spells/painterly-2/rock-orange-1.png",
	"ambush":              "res://assets/spells/painterly-1/enchant-eerie-1.png",
	"lightning":           "res://assets/spells/painterly-2/lightning-blue-1.png",
	"quick_shot":          "res://assets/spells/painterly-2/beam-orange-1.png",
	"cataclysm":           "res://assets/spells/painterly-2/rock-royal-1.png",
	"apocalypse":          "res://assets/spells/painterly-2/beam-eerie-1.png",
	"mass_grave":          "res://assets/spells/painterly-1/evil-eye-eerie-1.png",
	"pillage":             "res://assets/spells/painterly-1/enchant-orange-2.png",
	# Buff / heal / defensive
	"war_cry":             "res://assets/spells/painterly-2/haste-fire-1.png",
	"inspire":             "res://assets/spells/painterly-2/haste-royal-1.png",
	"battle_hymn":         "res://assets/spells/painterly-2/haste-sky-1.png",
	"kings_command":       "res://assets/spells/painterly-1/protect-royal-1.png",
	"shield_wall":         "res://assets/spells/painterly-1/protect-blue-1.png",
	"barricade":           "res://assets/spells/painterly-1/protect-acid-1.png",
	"patch_up":            "res://assets/spells/painterly-1/heal-jade-1.png",
	"second_wind":         "res://assets/spells/painterly-1/heal-sky-1.png",
	"dark_pact":           "res://assets/spells/painterly-1/enchant-magenta-1.png",
	"overwhelming_force":  "res://assets/spells/painterly-2/beam-red-1.png",
	# Utility / combo
	"provision":           "res://assets/spells/painterly-1/enchant-jade-1.png",
	"gambit":              "res://assets/spells/painterly-1/enchant-sky-1.png",
	"shove":               "res://assets/spells/painterly-2/rock-plain-1.png",
	"adrenaline":          "res://assets/spells/painterly-2/haste-fire-2.png",
	"concentrate":         "res://assets/spells/painterly-1/enchant-royal-1.png",
	"scrap":               "res://assets/spells/painterly-2/vines-acid-1.png",
	"reposition":          "res://assets/spells/painterly-2/vines-plain-1.png",
	"offering":            "res://assets/spells/painterly-2/vines-eerie-1.png",
	"grave_pact":          "res://assets/spells/painterly-1/evil-eye-eerie-2.png",
	"fuel_the_pyre":       "res://assets/spells/painterly-1/fireball-acid-1.png",
	"bloodletting":        "res://assets/spells/painterly-1/enchant-red-2.png",
	"echo_spell":          "res://assets/spells/painterly-2/beam-magenta-1.png",
	"turbo":               "res://assets/spells/painterly-2/haste-sky-2.png",
	"recycle":             "res://assets/spells/painterly-2/vines-jade-1.png",
	"soul_swap":           "res://assets/spells/painterly-1/enchant-eerie-2.png",
	"war_chant":           "res://assets/spells/painterly-2/haste-royal-2.png",
	"grave_robbery":       "res://assets/spells/painterly-1/evil-eye-red-1.png",
	"blood_tithe":         "res://assets/spells/painterly-1/enchant-red-3.png",
	"reckless_charge":     "res://assets/spells/painterly-2/haste-fire-3.png",
	"unholy_bargain":      "res://assets/spells/painterly-1/evil-eye-eerie-3.png",
}


func try_load_spell_art(card_id: String) -> Texture2D:
	# Override map first — each spell gets a hand-picked painterly variant.
	if SPELL_ART_OVERRIDES.has(card_id):
		var override_path: String = SPELL_ART_OVERRIDES[card_id]
		if ResourceLoader.exists(override_path):
			return load(override_path)
	# Fallback to the legacy per-spell PNG (covers spells not in the map).
	var path = "res://assets/spells/%s.png" % card_id
	if ResourceLoader.exists(path):
		return load(path)
	return null
