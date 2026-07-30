extends SceneTree
## Spell SEQUENCE probe (S2/S3 of docs/SPELL_FX_PLAN_20260717.md).
##
## The defect this locks down: `_play_spell_cast_vfx` used to fire ONE burst at
## ONE point, so a `scope: ALL ENEMIES` spell that hits four bodies showed a
## single puff at a hardcoded coordinate where nothing stands. The fix derives
## the impact list from the spell's own `scope`/`targeting` — data that was
## always there and never read.
##
## Checks the DERIVATION (_spell_fx_impact_points), which is the load-bearing
## part and is pure geometry — no rendering, so it runs headless. The look
## itself is a shot-harness job.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_spell_sequence.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

var _ran := false
var _fails := 0


func _all_tagged(c) -> bool:
	# A signature still needs a family — colors and impact composition come
	# from it. (S1's audit gate guarantees pool coverage; this guards the
	# signature list specifically.)
	for sid in c.SPELL_SIGNATURES:
		if not c.SPELL_FAMILIES.has(sid):
			return false
	return true


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[spell_seq] PASS  ", label)
	else:
		_fails += 1
		print("[spell_seq] FAIL  ", label, ("  — " + detail) if detail != "" else "")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var CombatScript = load("res://scripts/scenes/Combat.gd")
	var c = CombatScript.new()
	root.add_child(c)

	# Stand up a board by hand: 4 enemies across the front, 2 friendlies. No
	# scene, no rendering — _spell_fx_impact_points only reads the field arrays
	# and node rects.
	var enemies: Array = []
	for i in 4:
		var n := Control.new()
		n.size = Vector2(100, 100)
		n.position = Vector2(600.0 - float(i) * 120.0, 200.0)  # deliberately RIGHT-to-LEFT
		c.add_child(n)
		c._enemy_field[i] = n
		enemies.append(n)
	var friendlies: Array = []
	for i in 2:
		var n := Control.new()
		n.size = Vector2(100, 100)
		n.position = Vector2(300.0 + float(i) * 120.0, 600.0)
		c.add_child(n)
		c._player_field[i] = n
		friendlies.append(n)

	# ── ALL ENEMIES → one impact per body, swept left-to-right ──────────
	var pts: Array = c._spell_fx_impact_points({"scope": "ALL ENEMIES"}, null)
	_check("ALL ENEMIES lands one impact per body (4)", pts.size() == 4,
		"got %d" % pts.size())
	var sorted_lr := true
	for i in range(1, pts.size()):
		if pts[i].x < pts[i - 1].x:
			sorted_lr = false
	_check("ALL ENEMIES sweeps left-to-right regardless of lane order", sorted_lr,
		str(pts))

	# ── ALL CREATURES → both sides, radiating from the centre ──────────
	var pts_all: Array = c._spell_fx_impact_points({"scope": "ALL CREATURES"}, null)
	_check("ALL CREATURES hits both sides (4 + 2 = 6)", pts_all.size() == 6,
		"got %d" % pts_all.size())
	var mid: Vector2 = c.get_viewport_rect().size * 0.5
	var radiating := true
	for i in range(1, pts_all.size()):
		if pts_all[i].distance_to(mid) < pts_all[i - 1].distance_to(mid) - 0.01:
			radiating = false
	_check("ALL CREATURES radiates outward from the midline (not swept)",
		radiating)

	# ── YOUR ARMY / YOUR FRONT LINE → your side only ────────────────────
	var pts_army: Array = c._spell_fx_impact_points({"scope": "YOUR ARMY"}, null)
	_check("YOUR ARMY hits your side only (2)", pts_army.size() == 2,
		"got %d" % pts_army.size())
	var pts_front: Array = c._spell_fx_impact_points({"scope": "YOUR FRONT LINE"}, null)
	_check("YOUR FRONT LINE hits the front row (2)", pts_front.size() == 2,
		"got %d" % pts_front.size())

	# ── An explicit target always wins over scope ───────────────────────
	var pts_t: Array = c._spell_fx_impact_points({"scope": "ALL ENEMIES"}, enemies[0])
	_check("an explicit target overrides scope (1 impact)", pts_t.size() == 1,
		"got %d" % pts_t.size())
	_check("the explicit target's impact lands ON it",
		pts_t.size() == 1 and pts_t[0].is_equal_approx(
			enemies[0].get_global_rect().get_center()))

	# ── ENEMY BACK ROW → the back row ONLY (S6 fix) ─────────────────────
	# This used to share the ALL ENEMIES branch, so a Crossfire showed impacts
	# on front-row bodies it never touches.
	var backs: Array = []
	for i in 2:
		var n := Control.new()
		n.size = Vector2(100, 100)
		n.position = Vector2(400.0 + float(i) * 120.0, 90.0)
		c.add_child(n)
		c._enemy_back[i] = n
		backs.append(n)
	var pts_back: Array = c._spell_fx_impact_points({"scope": "ENEMY BACK ROW"}, null)
	_check("ENEMY BACK ROW hits the back row only (2, not 6)",
		pts_back.size() == 2, "got %d" % pts_back.size())
	var back_ys_ok := true
	for p in pts_back:
		if p.y > 200.0:
			back_ys_ok = false
	_check("ENEMY BACK ROW impacts land on back-row bodies", back_ys_ok)
	var pts_back_empty_probe: Array = []
	for i in 2:
		c._enemy_back[i] = null
	pts_back_empty_probe = c._spell_fx_impact_points({"scope": "ENEMY BACK ROW"}, null)
	_check("ENEMY BACK ROW with an empty back row derives nothing (fallback puff)",
		pts_back_empty_probe.is_empty())
	# Backs stay nulled — the empty-board check at the end counts on it.

	# ── S6: signature ids must LIVE (the S1 dead-tag lesson) ────────────
	# Every id in SPELL_SIGNATURES / SPELL_LOB must exist in CARD_POOL as a
	# spell, and every lob spell must be a signature — dead ids rot silently.
	var CardDBScript = load("res://scripts/data/CardDB.gd")
	var pool: Dictionary = CardDBScript.CARD_POOL
	var sig_dead: Array = []
	for sid in c.SPELL_SIGNATURES:
		var entry: Dictionary = pool.get(sid, {})
		if entry.is_empty() or String(entry.get("type", "")) != "spell":
			sig_dead.append(sid)
	_check("every SPELL_SIGNATURES id is a live spell in CARD_POOL",
		sig_dead.is_empty(), str(sig_dead))
	var lob_bad: Array = []
	for lid in c.SPELL_LOB:
		if not c.SPELL_SIGNATURES.has(lid):
			lob_bad.append(lid)
	_check("every SPELL_LOB id is also a signature (the lob IS its signature)",
		lob_bad.is_empty(), str(lob_bad))
	_check("signature spells are all family-tagged too",
		_all_tagged(c), "")

	# ── Positional / self-cast spells derive nothing and fall back ──────
	var pts_face: Array = c._spell_fx_impact_points({"scope": "ENEMY FACE"}, null)
	_check("ENEMY FACE derives no body impacts (falls back to the face point)",
		pts_face.is_empty())
	var pts_none: Array = c._spell_fx_impact_points({}, null)
	_check("a scopeless self-cast derives no body impacts", pts_none.is_empty())

	# ── S4: when is a bolt honest? ──────────────────────────────────────
	# A bolt is AIMED. A board-wide wave isn't aimed at anyone (the wave IS the
	# delivery), and past 4 targets bolts stop reading as delivery and start
	# reading as spaghetti.
	_check("single target throws a bolt",
		c._spell_fx_wants_bolt({"targeting": "enemy_creature"}, 1))
	_check("a modest sweep (4) throws bolts",
		c._spell_fx_wants_bolt({"scope": "ALL ENEMIES"}, 4))
	_check("a wide sweep (5+) does NOT throw bolts (spaghetti guard)",
		not c._spell_fx_wants_bolt({"scope": "ALL ENEMIES"}, 5))
	_check("ALL CREATURES never throws bolts (the wave IS the delivery)",
		not c._spell_fx_wants_bolt({"scope": "ALL CREATURES"}, 2))

	# The caster origin must be a real on-screen point, not (0,0) or off-canvas.
	var origin: Vector2 = c._spell_caster_origin()
	var vp_r: Vector2 = c.get_viewport_rect().size
	_check("caster origin is on-screen",
		origin.x > 0.0 and origin.y > 0.0
			and origin.x < vp_r.x and origin.y <= vp_r.y,
		"origin=%s vp=%s" % [origin, vp_r])

	# ── An empty board must not crash or invent impacts ─────────────────
	for i in 4:
		c._enemy_field[i] = null
	var pts_empty: Array = c._spell_fx_impact_points({"scope": "ALL ENEMIES"}, null)
	_check("ALL ENEMIES on an empty board yields nothing (no phantom puff)",
		pts_empty.is_empty(), "got %d" % pts_empty.size())

	print("")
	print("[spell_seq] ALL PASS" if _fails == 0 else "[spell_seq] %d FAIL(S)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
