extends Node3D
## Atmosphere.gd — particles whose color, direction, density, and emission
## crossfade with mood. Reads mood every frame from MoodDirector.
##
## Three layers: Petals (pink → ash), Sparkles (gold motes → red embers),
## Bugs (drifting pollen → rising embers).

@onready var petal_particles: GPUParticles3D = $Petals
@onready var sparkle_particles: GPUParticles3D = $Sparkles
@onready var bug_particles: GPUParticles3D = $Bugs

@export_node_path("Node3D") var mood_director: NodePath
var _director: Node

var _petal_mat: ParticleProcessMaterial
var _sparkle_mat: ParticleProcessMaterial
var _bug_mat: ParticleProcessMaterial
var _petal_draw: StandardMaterial3D
var _sparkle_draw: StandardMaterial3D
var _bug_draw: StandardMaterial3D


func _ready() -> void:
	_configure_petals()
	_configure_sparkles()
	_configure_bugs()
	if mood_director:
		_director = get_node(mood_director)


func _process(_delta: float) -> void:
	if _director:
		_apply_mood(_director.mood)


# ── One-time setup ──
# CRITICAL: All three particle materials use BILLBOARD_PARTICLES, NOT
# BILLBOARD_ENABLED. The latter ignores particle scale and renders the
# raw QuadMesh size — which is why the petals were 1m wide before.
func _configure_petals() -> void:
	_petal_mat = ParticleProcessMaterial.new()
	_petal_mat.spread = 30.0
	_petal_mat.gravity = Vector3(0, -0.05, 0)
	_petal_mat.angular_velocity_min = -180.0
	_petal_mat.angular_velocity_max = 180.0
	_petal_mat.scale_min = 0.020
	_petal_mat.scale_max = 0.040
	_petal_mat.scale_curve = _make_fade_curve()
	_petal_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_petal_mat.emission_box_extents = Vector3(2.5, 0.5, 1.5)
	_petal_mat.turbulence_enabled = true
	_petal_mat.turbulence_noise_strength = 0.5
	_petal_mat.turbulence_noise_scale = 1.8
	petal_particles.process_material = _petal_mat
	petal_particles.amount = 35
	petal_particles.lifetime = 8.0
	petal_particles.preprocess = 4.0

	_petal_draw = StandardMaterial3D.new()
	_petal_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_petal_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_petal_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_petal_draw.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _petal_draw
	petal_particles.draw_pass_1 = quad


func _configure_sparkles() -> void:
	_sparkle_mat = ParticleProcessMaterial.new()
	_sparkle_mat.direction = Vector3(0, 1, 0)
	_sparkle_mat.spread = 90.0
	_sparkle_mat.gravity = Vector3.ZERO
	_sparkle_mat.scale_min = 0.008
	_sparkle_mat.scale_max = 0.015
	_sparkle_mat.scale_curve = _make_pulse_curve()
	_sparkle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_sparkle_mat.emission_box_extents = Vector3(2.0, 0.8, 1.2)
	_sparkle_mat.turbulence_enabled = true
	_sparkle_mat.turbulence_noise_strength = 0.15
	_sparkle_mat.turbulence_noise_scale = 4.0
	sparkle_particles.process_material = _sparkle_mat
	sparkle_particles.amount = 40
	sparkle_particles.lifetime = 3.5
	sparkle_particles.preprocess = 2.0

	_sparkle_draw = StandardMaterial3D.new()
	_sparkle_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sparkle_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sparkle_draw.emission_enabled = true
	_sparkle_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_sparkle_draw.billboard_keep_scale = true
	# Mix blend instead of Add so they don't accumulate to white blowout
	_sparkle_draw.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _sparkle_draw
	sparkle_particles.draw_pass_1 = quad


func _configure_bugs() -> void:
	_bug_mat = ParticleProcessMaterial.new()
	_bug_mat.spread = 180.0
	_bug_mat.scale_min = 0.012
	_bug_mat.scale_max = 0.020
	_bug_mat.scale_curve = _make_fade_curve()
	_bug_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_bug_mat.emission_box_extents = Vector3(2.0, 0.6, 1.2)
	_bug_mat.turbulence_enabled = true
	_bug_mat.turbulence_noise_strength = 0.6
	_bug_mat.turbulence_noise_scale = 0.8
	bug_particles.process_material = _bug_mat
	bug_particles.amount = 18
	bug_particles.lifetime = 6.0
	bug_particles.preprocess = 3.0

	_bug_draw = StandardMaterial3D.new()
	_bug_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bug_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bug_draw.emission_enabled = true
	_bug_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_bug_draw.billboard_keep_scale = true
	_bug_draw.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _bug_draw
	bug_particles.draw_pass_1 = quad


# ── Per-frame application. Emission energy multipliers are dialed way down
# from earlier — additive emissive particles plus glow blow out the screen
# in a hurry. We trade pop for legibility.
func _apply_mood(m: float) -> void:
	# PETALS: pink → ash, breeze → fall
	var petal_color := Color(1.0, 0.78, 0.88).lerp(Color(0.45, 0.40, 0.36), m)
	_petal_draw.albedo_color = Color(petal_color.r, petal_color.g, petal_color.b, lerpf(0.95, 0.65, m))
	_petal_mat.direction = Vector3(0.6, -0.2, 0.1).lerp(Vector3(0.05, -0.7, 0.0), m)
	_petal_mat.initial_velocity_min = lerpf(0.10, 0.04, m)
	_petal_mat.initial_velocity_max = lerpf(0.25, 0.12, m)
	petal_particles.amount_ratio = lerpf(1.0, 0.30, smoothstep(0.4, 0.85, m))

	# SPARKLES: gold sun-motes → red embers
	var spark_albedo := Color(1.0, 1.0, 0.85).lerp(Color(1.0, 0.55, 0.20), m)
	_sparkle_draw.albedo_color = Color(spark_albedo.r, spark_albedo.g, spark_albedo.b, 1.0)
	_sparkle_draw.emission = Color(0.9, 0.85, 0.5).lerp(Color(1.0, 0.45, 0.10), m)
	_sparkle_draw.emission_energy_multiplier = lerpf(0.15, 0.8, m)
	_sparkle_mat.initial_velocity_min = lerpf(0.02, 0.10, m)
	_sparkle_mat.initial_velocity_max = lerpf(0.08, 0.30, m)
	_sparkle_mat.turbulence_noise_strength = lerpf(0.15, 0.45, m)

	# BUGS: drifting pollen → rising embers
	var bug_albedo := Color(1.0, 0.95, 0.55).lerp(Color(1.0, 0.5, 0.15), m)
	_bug_draw.albedo_color = Color(bug_albedo.r, bug_albedo.g, bug_albedo.b, 1.0)
	_bug_draw.emission = Color(0.9, 0.85, 0.4).lerp(Color(1.0, 0.4, 0.08), m)
	_bug_draw.emission_energy_multiplier = lerpf(0.05, 0.7, m)
	_bug_mat.direction = Vector3(0.3, 0.1, 0.0).lerp(Vector3(0.0, 1.0, 0.0), m)
	_bug_mat.gravity = Vector3.ZERO.lerp(Vector3(0.0, 0.10, 0.0), m)
	_bug_mat.initial_velocity_min = lerpf(0.04, 0.12, m)
	_bug_mat.initial_velocity_max = lerpf(0.10, 0.30, m)
	bug_particles.amount_ratio = lerpf(0.7, 1.5, m)


func _make_fade_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


func _make_pulse_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.4, 0.4))
	curve.add_point(Vector2(0.6, 1.0))
	curve.add_point(Vector2(0.8, 0.4))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
