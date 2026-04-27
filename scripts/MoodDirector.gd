extends Node3D
## MoodDirector.gd — single source of truth for atmospheric mood (0..1).
##
##   0.0 = late afternoon meadow. Golden sun, pink petals, blue sky, light haze.
##   1.0 = burning grimoire night. Blood-red horizon, ash, embers, dense smoke,
##         volumetric god-rays from brazier flames.

signal mood_changed(new_mood: float)

@export_node_path("Node3D") var play_area: NodePath
@export_range(0.05, 4.0) var lerp_speed: float = 0.6
@export_range(0.05, 4.0) var stress_decay_speed: float = 0.5

# Resolved references
var _play_area: Node
var _world_env: WorldEnvironment
var _env: Environment
var _sun: DirectionalLight3D
var _sun_origin: Vector3

# Mood state
var mood: float = 0.0
var target_mood: float = 0.0
var stress: float = 0.0

# ── Sun: arcs from "late afternoon" to "near horizon" using Euler angles.
# Euler-built bases are guaranteed orthonormal — no slerp / quaternion errors.
const SUN_PITCH_AFTERNOON := -50.0  # 50° above horizon
const SUN_PITCH_HORIZON   := -8.0   # near horizon
const SUN_YAW_AFTERNOON   := 30.0
const SUN_YAW_HORIZON     := 65.0

# ── Color stops (mood 0 → 1) ──
const SUN_COLOR_DAY     := Color(1.00, 0.96, 0.88)
const SUN_COLOR_GOLDEN  := Color(1.00, 0.62, 0.30)
const SUN_COLOR_BLOODY  := Color(0.85, 0.18, 0.12)
const SUN_ENERGY_DAY    := 1.20
const SUN_ENERGY_NIGHT  := 0.20

const SKY_TOP_DAY       := Color(0.32, 0.55, 0.85)
const SKY_TOP_NIGHT     := Color(0.04, 0.02, 0.06)
const SKY_HORIZON_DAY   := Color(0.85, 0.78, 0.65)
const SKY_HORIZON_NIGHT := Color(0.55, 0.10, 0.05)

const FOG_COLOR_DAY     := Color(0.78, 0.82, 0.88)
const FOG_COLOR_NIGHT   := Color(0.42, 0.10, 0.06)
const FOG_DENSITY_DAY   := 0.008
const FOG_DENSITY_NIGHT := 0.060

const VOL_DENSITY_DAY   := 0.0
const VOL_DENSITY_NIGHT := 0.030
const VOL_ALBEDO_DAY    := Color(1.0, 1.0, 1.0)
const VOL_ALBEDO_NIGHT  := Color(1.0, 0.55, 0.35)

const SAT_DAY        := 1.05
const SAT_NIGHT      := 0.82
const CONTRAST_DAY   := 1.00
const CONTRAST_NIGHT := 1.20
# Glow intensity — kept low even at night. Glow stacks fast with emissive
# surfaces, so we err on the gentle side.
const GLOW_DAY       := 0.15
const GLOW_NIGHT     := 0.55


func _ready() -> void:
	_play_area = get_node(play_area) if play_area else get_parent()
	_sun = _play_area.get_node_or_null("Sun") as DirectionalLight3D
	_world_env = _play_area.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env:
		_env = _world_env.environment
	if _sun:
		_sun_origin = _sun.transform.origin
	_ensure_environment()
	RenderingServer.global_shader_parameter_set("mood", 0.0)
	_apply_mood(0.0)


func _process(delta: float) -> void:
	stress = lerp(stress, 0.0, clampf(delta * stress_decay_speed, 0.0, 1.0))
	var combined := clampf(target_mood + stress, 0.0, 1.0)
	var prev := mood
	mood = lerp(mood, combined, clampf(delta * lerp_speed, 0.0, 1.0))
	if absf(mood - prev) > 0.0005:
		_apply_mood(mood)
		mood_changed.emit(mood)


func set_target_mood(m: float) -> void:
	target_mood = clampf(m, 0.0, 1.0)


func add_stress(amount: float) -> void:
	stress = minf(stress + amount, 0.5)


func compute_target(turn_number: int, player_hp: int, enemy_hp: int, max_hp: int) -> float:
	var hp_pressure := 1.0 - float(mini(player_hp, enemy_hp)) / float(max_hp)
	var turn_pressure := clampf(float(turn_number - 1) / 9.0, 0.0, 1.0)
	return clampf(0.65 * hp_pressure + 0.45 * turn_pressure, 0.0, 1.0)


func _apply_mood(m: float) -> void:
	RenderingServer.global_shader_parameter_set("mood", m)

	if _sun:
		var pitch_deg = lerpf(SUN_PITCH_AFTERNOON, SUN_PITCH_HORIZON, m)
		var yaw_deg = lerpf(SUN_YAW_AFTERNOON, SUN_YAW_HORIZON, m)
		var basis := Basis.from_euler(Vector3(
			deg_to_rad(pitch_deg),
			deg_to_rad(yaw_deg),
			0.0
		))
		_sun.transform = Transform3D(basis, _sun_origin)

		var c := SUN_COLOR_DAY.lerp(SUN_COLOR_GOLDEN, smoothstep(0.0, 0.6, m))
		c = c.lerp(SUN_COLOR_BLOODY, smoothstep(0.5, 1.0, m))
		_sun.light_color = c
		_sun.light_energy = lerpf(SUN_ENERGY_DAY, SUN_ENERGY_NIGHT, m)
		_sun.shadow_bias = 0.02

	if not _env:
		return

	var sky_mat: ProceduralSkyMaterial = null
	if _env.sky:
		sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat:
		sky_mat.sky_top_color = SKY_TOP_DAY.lerp(SKY_TOP_NIGHT, m)
		sky_mat.sky_horizon_color = SKY_HORIZON_DAY.lerp(SKY_HORIZON_NIGHT, m)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.4)
		sky_mat.ground_bottom_color = SKY_TOP_NIGHT.darkened(0.5)
		sky_mat.sky_energy_multiplier = lerpf(1.0, 0.30, m)
		sky_mat.sun_angle_max = lerpf(30.0, 90.0, m)
		sky_mat.sun_curve = lerpf(0.15, 0.05, m)

	_env.fog_light_color = FOG_COLOR_DAY.lerp(FOG_COLOR_NIGHT, m)
	_env.fog_density = lerpf(FOG_DENSITY_DAY, FOG_DENSITY_NIGHT, m)
	_env.fog_aerial_perspective = 1.0
	_env.fog_sky_affect = lerpf(0.2, 0.5, m)

	_env.volumetric_fog_density = lerpf(VOL_DENSITY_DAY, VOL_DENSITY_NIGHT, m)
	_env.volumetric_fog_albedo = VOL_ALBEDO_DAY.lerp(VOL_ALBEDO_NIGHT, m)
	_env.volumetric_fog_anisotropy = lerpf(0.3, 0.6, m)

	_env.adjustment_saturation = lerpf(SAT_DAY, SAT_NIGHT, m)
	_env.adjustment_contrast = lerpf(CONTRAST_DAY, CONTRAST_NIGHT, m)
	_env.glow_intensity = lerpf(GLOW_DAY, GLOW_NIGHT, m)
	_env.ambient_light_energy = lerpf(1.0, 0.5, m)


func _ensure_environment() -> void:
	if not _env:
		push_warning("MoodDirector: no WorldEnvironment found; skipping setup.")
		return

	if not _env.sky:
		var sky := Sky.new()
		sky.sky_material = ProceduralSkyMaterial.new()
		_env.sky = sky
	elif not (_env.sky.sky_material is ProceduralSkyMaterial):
		_env.sky.sky_material = ProceduralSkyMaterial.new()

	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX

	# Glow — dialed back. HDR threshold at 1.0 means only true HDR pixels
	# bloom. Strength 0.7 keeps the bloom from spreading too far.
	_env.glow_enabled = true
	_env.glow_bloom = 0.0
	_env.glow_hdr_threshold = 1.0
	_env.glow_hdr_scale = 1.5
	_env.glow_strength = 0.7
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	_env.fog_enabled = true
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_length = 8.0
	_env.volumetric_fog_emission_energy = 0.0

	_env.adjustment_enabled = true
