extends Node
## _probe_tutorial.gd — the standing gate on the coaching system (2026-09-10).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_tutorial.tscn
##
## RUNS AS A SCENE, not `--script`, because half of what it asserts is about
## UserSettings and an autoload does not exist in a `--script` context. (See
## CLAUDE.md, "parsecheck's ONE blind spot" — the same reason parsecheck is a
## scene.)
##
## FIVE THINGS, and each one is a bug this system has already shipped in some
## form:
##
##   A · REACHABILITY, BOTH DIRECTIONS (the C1 shape). A lesson in the registry
##       that no screen ever teaches is content no player can reach — the exact
##       defect that let six minigames live for months. A lesson id quoted at a
##       call site that is NOT in the registry is worse than dead: `lesson_seen`
##       answers TRUE for an unknown id (deliberately — see there), so a typo in
##       a teaching call does not error, does not warn, and silently means "this
##       player has already been taught it". Forever.
##
##   B · THE COPY CONTRACT. Every lesson needs a title and a body; the title must
##       be a RUN of capped words (`_probe_copy_lint._check_shouting` fails a lone
##       capped word of 3+ chars, and these render straight into the info channel);
##       the body must fit a reading budget and must not use the two words the
##       house has banned from player text.
##
##   C · NO UNRESOLVED TOKENS. `{n}` is substituted by the caller. A lesson that
##       grows a token whose caller does not pass it prints the braces on screen.
##
##   D · THE LEGACY MAPPING IS REAL. `legacy` names a property on UserSettings,
##       and `get()` on a name that does not exist returns null rather than
##       failing — so a typo there would quietly make a lesson permanently unseen
##       AND permanently un-markable.
##
##   E · THE COACHING MODE IS HONOURED. OFF must silence everything, TIPS must
##       drop the walkthrough and keep the rest. This is the whole skip feature;
##       if it regresses, the symptom is a player who turned the tutorial off
##       being taught anyway, which no other gate here would notice.
##
## IT RESTORES THE PROFILE'S FLAGS ON THE WAY OUT. These are once-EVER settings
## and a gate has no business spending the developer's.

const SCAN_ROOT := "res://scripts"
const REGISTRY_PATH := "res://scripts/data/TutorialDB.gd"

## Bodies are read while a fight is waiting. COPY_STYLE §11 puts fast-read text
## at ~40 characters and prose at 50-80 per line; a coach body is prose, but it is
## prose someone reads under pressure, so it gets a word ceiling rather than a
## line one.
const MAX_BODY_WORDS := 32

## Every {token} a lesson body is allowed to use, with a stand-in value. The
## VALUES are irrelevant — this only ever checks that substitution leaves no
## braces behind — but the KEY SET is the contract, so a lesson that invents a
## token fails here until someone also wires it at the `_teach_tip` call site.
##
## Each of these is read LIVE at the call site rather than hardcoded in the copy,
## because a lesson is stamped seen the instant it fires: there is no second
## chance to teach a rule correctly, so a number baked into a sentence is one
## retune away from instructing the player to do something the game refuses. That
## has already happened once — the discard tip taught "any number of cards" after
## MAX_DISCARD_MARKS became 2.
const KNOWN_TOKENS := {
	"n": 2,        # dismiss — Combat._max_discard_marks()
	"cap": 6,      # command_ramp — Combat.COMMAND_RAMP_CAP
	"bank": 2,     # banking — Combat.MAX_BANKED_MANA
}

## The functions that consume a lesson id. Used for the reverse scan — anything
## quoted into one of these must exist in the registry.
const ID_CONSUMERS: Array[String] = [
	"_teach_tip", "should_teach", "lesson_seen", "mark_lesson_seen",
	"replay_lesson", "TutorialDB.title", "TutorialDB.body",
	"TutorialDB.tip_line", "TutorialDB.kind", "TutorialDB.legacy_flag",
]

var _failures: Array[String] = []
var _checks := 0
## Distinct lesson ids found at a call site — reported so the reverse scan's
## reach is visible in the output rather than only asserted.
var _consumed_seen := 0


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fail(msg)


func _ready() -> void:
	var saved := _snapshot_settings()
	_check_registry_copy()
	_check_reachability()
	_check_legacy_mapping()
	_check_seen_roundtrip()
	_check_coaching_modes()
	_restore_settings(saved)

	print("[tutorial] %d lessons, %d checks, %d call sites" % [
		TutorialDB.LESSONS.size(), _checks, _consumed_seen])
	if _failures.is_empty():
		print("PROBE PASS: tutorial")
	else:
		for f in _failures:
			print("  FAIL  ", f)
		print("PROBE FAIL: tutorial (%d failures)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


# ── B / C · the copy contract ──────────────────────────────────────────

func _check_registry_copy() -> void:
	for id in TutorialDB.ids():
		var title := TutorialDB.title(id)
		var body := TutorialDB.body(id)
		_check(title != "", "%s: empty title" % id)
		_check(body != "", "%s: empty body" % id)

		# A RUN of capped words is signage and is allowed; a lone one shouts.
		var words := title.split(" ", false)
		var capped := 0
		for w in words:
			if w.length() >= 3 and w == w.to_upper() and w != w.to_lower():
				capped += 1
		_check(capped >= 2 or words.size() >= 2,
			"%s: title '%s' is a lone capped word — copy_lint's _check_shouting "
			% [id, title] + "will fail it")

		var n := body.split(" ", false).size()
		_check(n <= MAX_BODY_WORDS,
			"%s: body is %d words (budget %d)" % [id, n, MAX_BODY_WORDS])

		var low := body.to_lower()
		# The two words the house has banned from player text. Every code
		# identifier still says `mana`; nothing a player reads may.
		_check(not low.contains("mana"),
			"%s: body says 'mana' — the player-facing word is Command" % id)
		_check(not low.contains("elite"),
			"%s: body says 'elite' — the player-facing word is General" % id)
		_check(not body.contains("(s)"),
			"%s: body uses '(s)' pluralisation" % id)

		# C · a token nobody fills prints its own braces.
		#
		# KNOWN_TOKENS is the registry of every {token} a lesson body may use,
		# and it is deliberately a hand-maintained list rather than "whatever
		# this body happens to contain": the failure being guarded is a call
		# site that forgets an argument, so the probe has to know the intended
		# argument set independently of the copy. Adding a token to a lesson
		# therefore means adding it here too — and that is the gate working,
		# because the same edit is the reminder to pass it at the call site.
		var filled := TutorialDB.body(id, KNOWN_TOKENS)
		_check(not filled.contains("{"),
			("%s: body has an unresolved token after substitution: %s"
			+ "\n        (if this is a NEW token, add it to KNOWN_TOKENS in this"
			+ " probe AND pass it from the _teach_tip call site)")
			% [id, filled])

		_check(TutorialDB.GROUP_TITLES.has(
			String(TutorialDB.LESSONS[id].get("group", ""))),
			"%s: unknown group" % id)
		_check(TutorialDB.kind(id) in [TutorialDB.KIND_STEP, TutorialDB.KIND_TIP,
			TutorialDB.KIND_CARD], "%s: unknown kind" % id)

	# Every group must contain something, or the manual prints a bare heading.
	for group in TutorialDB.GROUP_ORDER:
		_check(not TutorialDB.ids_in_group(group).is_empty(),
			"group '%s' has no lessons — the Field Manual would print an empty "
			% group + "heading")

	# `order` decides the manual's reading order AND the curriculum. Two lessons
	# sharing one is not an error, but it makes the order arbitrary, so it is
	# reported: the ladder is a sequence someone chose.
	var seen_orders: Dictionary = {}
	for id in TutorialDB.ids():
		var o := int(TutorialDB.LESSONS[id].get("order", 0))
		_check(not seen_orders.has(o),
			"%s: duplicate order %d (also %s)" % [id, o, seen_orders.get(o, "")])
		seen_orders[o] = id


# ── A · reachability, both directions ──────────────────────────────────

func _check_reachability() -> void:
	var sources := _gather_sources(SCAN_ROOT)
	_check(sources.size() > 50,
		"only %d scripts scanned — the walk is broken, not the code"
		% sources.size())

	var blob := ""
	var quoted_ids: Dictionary = {}
	for path in sources:
		if path == REGISTRY_PATH:
			continue        # the registry defining an id is not a call site
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		blob += text
		for id in _extract_consumed_ids(text):
			if not quoted_ids.has(id):
				quoted_ids[id] = path

	# FORWARD — a lesson nothing teaches.
	for id in TutorialDB.ids():
		_check(blob.contains('"%s"' % id),
			"%s: in the registry but quoted at no call site in scripts/ — "
			% id + "no screen can ever teach it")

	# VACUITY GUARD. The reverse check below passes trivially if the extractor
	# matched nothing — and a regex that has quietly stopped matching looks
	# exactly like a codebase with no mistakes in it. The house rule from the
	# metamorphic pass applies: a test that can pass without observing anything
	# must first prove it observed something.
	_consumed_seen = quoted_ids.size()
	_check(quoted_ids.size() >= 10,
		"the id extractor found only %d consumed ids — the regexes have stopped "
		% quoted_ids.size() + "matching and the reverse check is vacuous")

	# REVERSE — an id taught that the registry does not define. This is the one
	# that fails silently in production: `lesson_seen` answers TRUE for an
	# unknown id, so a typo reads as "already taught" and the lesson never fires.
	for id in quoted_ids:
		_check(TutorialDB.has(id),
			"'%s' is passed to a lesson function in %s but is not in TutorialDB "
			% [id, quoted_ids[id]] + "— it will silently never fire")


## Pull every string literal handed to one of the id-consuming functions.
func _extract_consumed_ids(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	for fn in ID_CONSUMERS:
		# `teach(self, "id")` puts the id second, so allow one leading argument.
		re.compile("%s\\s*\\(\\s*(?:[A-Za-z_][A-Za-z0-9_.]*\\s*,\\s*)?\"([a-z0-9_]+)\""
			% fn.replace(".", "\\."))
		for m in re.search_all(text):
			out.append(m.get_string(1))
	# `TutorialCoach.teach(host, "id", ...)` — its own shape, host first.
	re.compile("teach\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_.]*\\s*,\\s*\"([a-z0-9_]+)\"")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


func _gather_sources(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gather_sources(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


# ── D · the legacy mapping ─────────────────────────────────────────────

func _check_legacy_mapping() -> void:
	var props: Dictionary = {}
	for p in UserSettings.get_property_list():
		props[String(p.get("name", ""))] = true
	for id in TutorialDB.ids():
		var flag := TutorialDB.legacy_flag(id)
		if flag == "":
			continue
		# A name that does not exist makes `get()` return null, which reads as
		# false forever and can never be set — the lesson would be permanently
		# unseen and permanently un-markable, with no error anywhere.
		_check(props.has(flag),
			"%s: legacy flag '%s' is not a property on UserSettings" % [id, flag])


# ── The persistence round trip ─────────────────────────────────────────

func _check_seen_roundtrip() -> void:
	UserSettings.reset_tutorials()
	for id in TutorialDB.ids():
		_check(not UserSettings.lesson_seen(id),
			"%s: still seen after reset_tutorials()" % id)

	for id in TutorialDB.ids():
		UserSettings.mark_lesson_seen(id)
		_check(UserSettings.lesson_seen(id),
			"%s: mark_lesson_seen did not stick" % id)

	# Per-lesson replay — the retrieval half of the contract. Lessons sharing a
	# legacy flag come back together by design (the guided fight is one thing),
	# so the assertion is "this one is back", not "only this one".
	for id in TutorialDB.ids():
		UserSettings.replay_lesson(id)
		_check(not UserSettings.lesson_seen(id),
			"%s: replay_lesson left it seen" % id)
		UserSettings.mark_lesson_seen(id)

	# An unknown id answers SEEN so nothing can loop forever on it.
	_check(UserSettings.lesson_seen("no_such_lesson_id_xyz"),
		"an unknown lesson id must answer seen=true")


# ── E · the coaching mode ──────────────────────────────────────────────

func _check_coaching_modes() -> void:
	UserSettings.reset_tutorials()

	UserSettings.set_coaching_mode(TutorialDB.COACH_OFF)
	for id in TutorialDB.ids():
		_check(not TutorialCoach.should_teach(id),
			"%s: still offered with coaching OFF" % id)

	UserSettings.set_coaching_mode(TutorialDB.COACH_TIPS)
	var steps := 0
	for id in TutorialDB.ids():
		if TutorialDB.kind(id) == TutorialDB.KIND_STEP:
			steps += 1
			_check(not TutorialCoach.should_teach(id),
				"%s: a guided STEP fired under TIPS ONLY" % id)
		else:
			_check(TutorialCoach.should_teach(id),
				"%s: a tip was suppressed under TIPS ONLY" % id)
	_check(steps > 0, "no KIND_STEP lessons exist — the TIPS mode test is vacuous")

	UserSettings.set_coaching_mode(TutorialDB.COACH_FULL)
	for id in TutorialDB.ids():
		_check(TutorialCoach.should_teach(id),
			"%s: not offered on a fresh profile at COACH_FULL" % id)


# ── Profile hygiene ────────────────────────────────────────────────────

func _snapshot_settings() -> Dictionary:
	var out := {"lessons_seen": UserSettings.lessons_seen.duplicate(true),
		"coaching_mode": UserSettings.coaching_mode}
	for id in TutorialDB.ids():
		var flag := TutorialDB.legacy_flag(id)
		if flag != "":
			out[flag] = UserSettings.get(flag)
	return out


func _restore_settings(saved: Dictionary) -> void:
	for k in saved:
		UserSettings.set(k, saved[k])
	UserSettings.save()
