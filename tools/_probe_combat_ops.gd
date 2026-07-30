extends SceneTree
## Determinism and side-routing contract for CombatOps.

const Ops = preload("res://scripts/combat/CombatOps.gd")
var _failed := false


class FakeCombat extends RefCounted:
	var player_hp: int = 20
	var enemy_hp: int = 20
	var player_units: Array = ["p"]
	var enemy_units: Array = ["e"]

	func damage_player_hero(amount: int) -> void:
		player_hp -= amount

	func damage_enemy_hero(amount: int) -> void:
		enemy_hp -= amount

	func _all_player_creatures() -> Array:
		return player_units

	func _all_enemy_creatures() -> Array:
		return enemy_units


func _initialize() -> void:
	var a = Ops.new(77331)
	var b = Ops.new(77331)
	var seq_a: Array = []
	var seq_b: Array = []
	for _i in range(12):
		seq_a.append(a.rangei(-4, 9))
		seq_b.append(b.rangei(-4, 9))
	_check(seq_a == seq_b, "equal seeds produce equal gameplay choices")

	a.reseed(55)
	b.reseed(55)
	var pool := ["a", "b", "c", "d"]
	_check(a.pick(pool) == b.pick(pool) and a.chance(0.37) == b.chance(0.37),
		"pick and chance share the deterministic stream")
	a.reseed(991)
	b.reseed(991)
	var shuffled_a := pool.duplicate()
	var shuffled_b := pool.duplicate()
	a.shuffle(shuffled_a)
	b.shuffle(shuffled_b)
	_check(shuffled_a == shuffled_b, "shuffle uses the deterministic gameplay stream")
	_check(a.next_id("token") == "token_1" and a.next_id("token") == "token_2",
		"synthetic gameplay ids are deterministic and monotonic")

	var fake := FakeCombat.new()
	a.damage_hero(fake, false, 3)
	a.damage_hero(fake, true, 5)
	_check(fake.player_hp == 17 and fake.enemy_hp == 15,
		"side damage reaches the requested hero")
	_check(a.heal_hero(fake, false, 20, 22) == 5 and fake.player_hp == 22,
		"side healing caps and reports the actual amount")
	a.damage_opposing_hero(fake, false, 4)
	_check(fake.enemy_hp == 11, "owner-relative damage reaches the opposing hero")
	_check(a.creatures(fake, false) == ["p"] and a.creatures(fake, true) == ["e"],
		"side creature lookup is explicit")

	print("[combat-ops] %s" % ("FAILED" if _failed else "all checks passed"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
	else:
		_failed = true
		push_error("[combat-ops] FAIL: %s" % label)
