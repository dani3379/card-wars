extends RefCounted
class_name CombatOps
## Deterministic gameplay operations shared by solo and host-authoritative net.
##
## Presentation is free to use cosmetic randomness. Any random choice that can
## alter combat state routes through this explicitly seeded stream instead.

var _rng := RandomNumberGenerator.new()
var _serial: int = 0


func _init(seed: int = 1) -> void:
	reseed(seed)


func reseed(seed: int) -> void:
	_rng.seed = seed
	_serial = 0


func pick(items: Array):
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


func index(size: int) -> int:
	return _rng.randi_range(0, size - 1) if size > 0 else -1


func shuffle(items: Array) -> void:
	# Array.shuffle() consumes Godot's global RNG, which makes gameplay order
	# depend on unrelated presentation calls. Keep all combat order here.
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var item = items[i]
		items[i] = items[j]
		items[j] = item


func rangei(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < clampf(probability, 0.0, 1.0)


func chance_percent(percent: int) -> bool:
	return _rng.randi_range(0, 99) < clampi(percent, 0, 100)


func next_id(prefix: String) -> String:
	_serial += 1
	return "%s_%d" % [prefix, _serial]


func creatures(ctx, is_enemy_side: bool) -> Array:
	return ctx._all_enemy_creatures() if is_enemy_side else ctx._all_player_creatures()


## Damage the hero physically represented by `is_enemy_side` on the authority.
func damage_hero(ctx, is_enemy_side: bool, amount: int) -> void:
	if amount <= 0:
		return
	if is_enemy_side:
		ctx.damage_enemy_hero(amount)
	else:
		ctx.damage_player_hero(amount)


## Heal one side and return the amount actually restored.
func heal_hero(ctx, is_enemy_side: bool, amount: int, cap: int) -> int:
	if amount <= 0:
		return 0
	var before: int = ctx.enemy_hp if is_enemy_side else ctx.player_hp
	var after: int = mini(before + amount, cap)
	if is_enemy_side:
		ctx.enemy_hp = after
	else:
		ctx.player_hp = after
	return after - before


func damage_opposing_hero(ctx, owner_is_enemy: bool, amount: int) -> void:
	damage_hero(ctx, not owner_is_enemy, amount)
