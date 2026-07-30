extends SceneTree
## Honesty probe for The Sentry's Board (morris_game) — proves the game is
## WINNABLE against the exact shipped drill. Drives Event.gd's static
## mor_* functions (the same code the sentry runs in play) with a memoized
## search over the player's choices; the sentry is deterministic, so a
## forced win is a single-agent search. FAILS if no forced player win
## exists, or if the drill crashes mid-line. Also prints the shortest
## forced win so a designer can eyeball how quick the trick is — if it
## ever gets trivially short, tighten the drill and rerun.
## Rules mirrored from the engine: player places first (never the middle
## post as the opening stone), placement alternates P/S ×3, then Tapatan
## marches alternate with `calls` total plies before the watch draws it.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_morris_solve.gd

const CALLS := 18

# Loaded at runtime, one frame in: Event.gd references autoloads at compile
# time, and autoloads only register after the SceneTree initializes — a
# preload here would fail the whole probe's compile.
var EventScript = null
var memo := {}


## Player-to-move node. Returns {rank, plies, line}: rank 2 = forced WIN,
## 1 = draw at best, 0 = loss; among wins, fewest plies preferred.
func solve(board: Array, placed_p: int, placed_s: int, phase_move: bool,
		moves_left: int) -> Dictionary:
	var key := "%s|%d|%d|%s|%d" % [str(board), placed_p, placed_s,
		str(phase_move), moves_left]
	if memo.has(key):
		return memo[key]
	# Zugzwang: the engine has the watch call the game when you cannot march.
	if phase_move and EventScript.mor_moves(board, 1).is_empty():
		var stuck := {"rank": 1, "plies": 0, "line": ["watch calls (you cannot march)"]}
		memo[key] = stuck
		return stuck
	var actions: Array = []
	if not phase_move:
		for p in range(9):
			if int(board[p]) == 0 and not (placed_p == 0 and p == 4):
				actions.append(["P", p])
	else:
		for mv in EventScript.mor_moves(board, 1):
			actions.append(["M", mv])
	var best := {"rank": -1, "plies": 0, "line": []}
	for act in actions:
		var b := board.duplicate()
		var pp := placed_p
		var ml := moves_left
		var desc := ""
		if act[0] == "P":
			b[act[1]] = 1
			pp += 1
			desc = "you place %d" % [act[1]]
		else:
			b[act[1][0]] = 0
			b[act[1][1]] = 1
			desc = "you march %d->%d" % [act[1][0], act[1][1]]
		var out: Dictionary
		if not EventScript.mor_mill(b, 1).is_empty():
			out = {"rank": 2, "plies": 1, "line": [desc + "  ** YOUR MILL **"]}
		else:
			if phase_move:
				ml -= 1
			if phase_move and ml <= 0:
				out = {"rank": 1, "plies": 1, "line": [desc, "watch calls"]}
			else:
				out = sentry_reply(b, pp, placed_s, phase_move, ml, desc)
		if out.rank > best.rank \
				or (out.rank == best.rank and out.rank == 2 and out.plies < best.plies):
			best = out
	memo[key] = best
	return best


func sentry_reply(board: Array, placed_p: int, placed_s: int,
		phase_move: bool, moves_left: int, pdesc: String) -> Dictionary:
	var b := board.duplicate()
	var ps := placed_s
	var pm := phase_move
	var ml := moves_left
	var desc := ""
	if not pm:
		var p: int = EventScript.mor_place_ai(b)
		b[p] = 2
		ps += 1
		desc = "he places %d" % p
		if not EventScript.mor_mill(b, 2).is_empty():
			return {"rank": 0, "plies": 2, "line": [pdesc, desc + "  (his mill)"]}
		if placed_p >= 3 and ps >= 3:
			pm = true
	else:
		var mv: Array = EventScript.mor_move_ai(b)
		if mv.is_empty():
			return {"rank": 1, "plies": 2,
				"line": [pdesc, "watch calls (he cannot march)"]}
		b[mv[0]] = 0
		b[mv[1]] = 2
		desc = "he marches %d->%d" % [mv[0], mv[1]]
		if not EventScript.mor_mill(b, 2).is_empty():
			return {"rank": 0, "plies": 2, "line": [pdesc, desc + "  (his mill)"]}
		ml -= 1
		if ml <= 0:
			return {"rank": 1, "plies": 2, "line": [pdesc, desc, "watch calls"]}
	var sub := solve(b, placed_p, ps, pm, ml)
	return {"rank": sub.rank, "plies": int(sub.plies) + 2,
		"line": [pdesc, desc] + sub.line}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	EventScript = load("res://scripts/scenes/Event.gd")
	if EventScript == null:
		print("[morris_solve] FAIL: could not load Event.gd")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var board: Array = []
	for _i in range(9):
		board.append(0)
	var res := solve(board, 0, 0, false, CALLS)
	var rank := int(res.rank)
	print("[morris_solve] outcome=%s  (searched %d states, %d ms)" % [
		["LOSS", "DRAW", "FORCED WIN"][rank], memo.size(),
		Time.get_ticks_msec() - t0])
	print("[morris_solve] shortest forced line (%d plies):" % [int(res.plies)])
	for step in res.line:
		print("    " + str(step))
	var decisions := int(ceil(float(res.plies) / 2.0))
	if rank == 2 and decisions <= 3:
		print("[morris_solve] WARNING: won in %d player decisions — the drill may be too soft." % decisions)
	print("[morris_solve] " + ("ALL PASS" if rank == 2
		else "FAIL: no forced player win against the shipped drill"))
	quit(0 if rank == 2 else 1)
