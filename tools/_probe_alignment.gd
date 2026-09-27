extends SceneTree
## _probe_alignment.gd — CLASS C30: IN ITS BOX, UNCOVERED, AND STILL WRONG.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_alignment.gd
##
## The three layout gates that came before this one all ask a question about ONE
## control against ONE reference:
##
##   * `_probe_textfit` / `_probe_boundary_ui` — does the content fit its own box,
##     and does the box stay on the canvas?
##   * `_probe_occlusion` (C28) — is something painting on top of it?
##   * `_probe_input_reach` (C29) — can the press actually reach it?
##
## A control can pass all three and still be the thing a player points at and
## says "that looks wrong". It fits, nothing covers it, it clicks — and it sits
## four pixels left of the column it belongs to. That is this class, and it is the
## single largest category in the published GUI-defect taxonomies after occlusion
## and truncation: alignment.
##
## THE ORACLE PROBLEM. "Off centre" sounds like a matter of taste, and judged one
## control at a time it is — there is no way to know from a single rect whether
## its author meant it. The judgement only becomes objective when it is made
## RELATIONALLY, against the other controls that were laid out beside it, and
## against what the layout code itself declared. Three shapes of evidence, none
## of which needs an eye:
##
##   A. THE ODD ONE OUT. Five buttons in a column share a centre to the pixel and
##      the sixth does not. Nothing about that requires knowing the design: the
##      column states its own intent five times over, and the sixth member
##      contradicts it. This is the "off centre" report, mechanised.
##
##   B. THE NEAR MISS. Two peers whose edges differ by 1–8 px. Alignment is a
##      binary act — either the author lined them up, or they placed them apart
##      on purpose and the gap reads as a gap. Zero is intent and forty is
##      intent; three is a mistake every time. (The band is why this is safe to
##      run over a whole codebase: a deliberate offset is never three pixels.)
##
##   C. THE CONTRADICTED DECLARATION. `CenterContainer`, and `BoxContainer` with
##      `alignment = ALIGNMENT_CENTER`, are the layout system being told in so
##      many words to centre something. When the rendered result is not centred,
##      the code and the pixels disagree and one of them is a bug — no taste
##      involved. It happens for real: a child with EXPAND size flags eats the
##      whole container and the "centring" silently becomes a no-op.
##
## And the proportion half of the same complaint, which is likewise only
## judgeable in company:
##
##   D. THE MISMATCHED TWIN. Peers in a column whose WIDTHS differ by a near-miss
##      margin (a row's HEIGHTS likewise) — measured on the CROSS axis only,
##      because along the layout axis differing sizes are the normal case and
##      comparing them there is pure noise. Plus the two degenerate shapes that
##      need no company at all: an interactive control below the 24 px minimum
##      target size, and one whose aspect ratio has collapsed.
##
##   E. THE ONE-SIDED GUTTER. An invisible spacer padding one end of a row whose
##      content otherwise spans it — see `_judge_one_sided_gutter`.
##
##   F. INK, NOT RECTS. Worded controls compared across the Button/Label divide
##      by where the WORD lands — see `_judge_ink`.
##
## HOUSE EXCLUSIONS, each for a stated reason:
##   * the INSIDE of a Card2D — the writ is a painting with deliberate corner
##     furniture, not a laid-out column. The card itself IS judged, because cards
##     on a shelf or a slate are peers of each other;
##   * any rotated control and its subtree — its axis-aligned rect is a lie;
##   * any SCALED control — it is mid-animation, and the rect it presents is not
##     the rect the layout produced;
##   * `top_level` controls — they have opted out of the parent's coordinates, so
##     "aligned with its siblings" is not a claim anyone made about them;
##   * a STACK OF LAYERS rather than a row of peers — see `_is_layer_stack`. The
##     one exclusion below that is a group property, not a control property, so
##     it lives in `_judge_group` and is COUNTED and PRINTED with the verdict.

const EXACT := 1.0     # values this close are "the same" — the author lined them up
const SLOP := 2.0      # deviation past this is a real break, not a rounding artifact
const NEAR := 8.0      # 1..NEAR is the near-miss band: neither aligned nor apart
const MIN_TARGET := 24.0   # WCAG 2.2 minimum target size
const ASPECT_MAX := 60.0   # past this a control has collapsed to a line

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const SEED := 606061

## KNOWN AND UNFIXED — visible debt, not absolution (the house convention).
## Keyed "state::needle"; an entry silences one finding.
const WAIVERS := {}

var RS: Node
var US: Node
var EDB: Node
var _started := false
var _done := false
var _hits := 0
var _states := 0
var _groups := 0
var _stacks := 0
var _controls := 0
var _canvas := Vector2(1600, 900)
var _seen := {}


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


# ── identification ───────────────────────────────────────────────────────────

func _label_of(c: Control) -> String:
	if c is Button and (c as Button).text.strip_edges() != "":
		return "\"%s\"" % (c as Button).text.strip_edges().substr(0, 30)
	if c is Label and (c as Label).text.strip_edges() != "":
		return "\"%s\"" % (c as Label).text.strip_edges().substr(0, 30)
	if c is RichTextLabel:
		var t := (c as RichTextLabel).get_parsed_text().strip_edges()
		if t != "":
			return "\"%s\"" % t.substr(0, 30)
	# An unnamed programmatic plate says nothing; borrow the first words inside.
	var stack: Array = [c]
	while not stack.is_empty():
		var x = stack.pop_front()
		if x is Label and (x as Label).text.strip_edges() != "":
			return "%s (\"%s\")" % [c.name, (x as Label).text.strip_edges().substr(0, 24)]
		if x is Button and (x as Button).text.strip_edges() != "":
			return "%s (\"%s\")" % [c.name, (x as Button).text.strip_edges().substr(0, 24)]
		for ch in x.get_children():
			stack.push_back(ch)
	return String(c.name)


## Label and RichTextLabel are the same thing to a player's eye; everything else
## is compared only against its own class, so a TextureButton is never judged
## against a Button (their natural sizes have nothing to do with each other).
func _family(c: Control) -> String:
	if c is Label or c is RichTextLabel:
		return "text"
	return c.get_class()


func _excluded(c: Control) -> bool:
	var walk: Node = c
	while walk != null:
		if walk is Control:
			var w: Control = walk
			if w.top_level:
				return true
			if absf(w.rotation) > 0.001:
				return true
			# A SCALED CONTROL IS MID-ANIMATION, and its axis-aligned rect is not
			# the rect the layout produced. The menu title breathes on a looping
			# 1.0->1.025 scale tween, and photographing it at 1.014 read as the
			# game's own name sitting 4.2px left of everything beneath it.
			if not w.scale.is_equal_approx(Vector2.ONE):
				return true
			# A CARD'S INSIDE IS A PAINTING, NOT A LAYOUT. The v9 writ puts its
			# cost seal in the top-left corner while the name and rules centre, so
			# judging a card's own furniture reported that seal as 93.5px off the
			# centre its five neighbours share — on every card, in every grid.
			# The card ITSELF is still judged: cards on a shop shelf or a draft
			# slate are peers of each other and must line up.
			if walk != c:
				var sc: Script = w.get_script()
				if sc != null and String(sc.resource_path).ends_with("Card2D.gd"):
					return true
		walk = walk.get_parent()
	return false


func _report(state: String, kind: String, headline: String, lines: Array) -> void:
	var key := "%s::%s" % [state, headline]
	if _seen.has(key):
		return
	_seen[key] = true
	for w in WAIVERS.keys():
		if key.findn(String(w)) >= 0:
			return
	_hits += 1
	print("  HIT   %-24s %-14s %s" % [state, kind, headline])
	for l in lines:
		print("        %s" % String(l))


# ── oracle A/B/D: judge one group of laid-out peers ──────────────────────────

## The largest set of values that agree to within EXACT, returned as indices.
func _cluster(vals: Array) -> Array:
	var best: Array = []
	for i in vals.size():
		var here: Array = []
		for j in vals.size():
			if absf(float(vals[j]) - float(vals[i])) <= EXACT:
				here.append(j)
		if here.size() > best.size():
			best = here
	return best


func _mean(vals: Array, idx: Array) -> float:
	var s := 0.0
	for i in idx:
		s += float(vals[int(i)])
	return s / maxf(1.0, float(idx.size()))


## ── A STACK OF LAYERS IS NOT A ROW OF PEERS ─────────────────────────────────
##
## Every oracle in `_judge_group` asks a question about controls placed BESIDE
## one another — the odd one out of a column, the near miss, the mismatched twin.
## Siblings that all fill the SAME box and differ only by a small uniform nudge
## were never placed beside anything. They are stacked in Z, and the nudge is not
## a position that could be wrong; it IS the drawing.
##
## Combat's pile panels are the case in hand. A deck of orders is drawn as
## full-rect leaves nudged 3px and 6px up-left behind the front sheet — what a
## stack of paper looks like from the front — and `_refresh_pile_stack` decides
## live how many draw: both back leaves at 10+ cards, one at 4+, a flat sheet
## below. At exactly ONE visible leaf the Panel family under `Art` is
## {leaf(-3), shadow(0), front(0)}: three members, two agreeing on a left edge,
## and the leaf reported 3.0px off it. Eight times over, once per combat state,
## and the count moves with the deck size — the 2026-09-16 economy pass dropped
## the draw to 2 and rescaled costs, which is what walked the deck into the 4..9
## band where exactly one leaf shows.
##
## This is the one case the near-miss band's premise does not cover. That band is
## safe over a whole codebase because "a deliberate offset is never three pixels"
## — true of anything POSITIONED, and false by construction of a stacked leaf,
## for which three pixels is the only offset there has ever been.
##
## The test is STRUCTURAL: it reads what the layout code declared, not what this
## particular art happens to be, and both halves must hold.
##
##   * Every member anchored to its parent's full rect with `offset_left ==
##     offset_right` and `offset_top == offset_bottom` — a control saying "I am
##     my parent's box, moved". That is an opt-out from being positioned as plain
##     as `top_level`, and it is a declaration in the code, not a look.
##   * And the group is genuinely STACKED rather than spread: the union of its
##     members is no more than a near-miss bigger than one member. Two full-rect
##     layers driven 300px apart are not a stack, and are still judged.
##
## It is worth being clear about how little this can hide, because an exclusion
## that quietly widens is how a gate dies. The size oracle below cannot fire on
## such a group anyway — a full-rect layer with symmetric offsets is EXACTLY its
## parent's size, so all members match by construction — and `_judge_shape`,
## `_judge_declared_centre`, `_judge_one_sided_gutter` and `_judge_ink` all run
## outside this function and are untouched. The only verdict this can change is
## an alignment one between overlapping layers.
##
## Deliberately NOT a WAIVERS entry. Those record known debt keyed on a state and
## a needle, and the needle here would have to be an engine-assigned node name
## (`@Panel@11998`) that is different on every run — a waiver that silences
## nothing, filed against a layout that is correct.
func _is_box_layer(c: Control) -> bool:
	if not is_equal_approx(c.anchor_left, 0.0) or not is_equal_approx(c.anchor_top, 0.0):
		return false
	if not is_equal_approx(c.anchor_right, 1.0) or not is_equal_approx(c.anchor_bottom, 1.0):
		return false
	return absf(c.offset_left - c.offset_right) <= EXACT \
		and absf(c.offset_top - c.offset_bottom) <= EXACT


func _is_layer_stack(members: Array) -> bool:
	var union: Rect2 = members[0]["r"]
	var widest := 0.0
	var tallest := 0.0
	for m in members:
		if not _is_box_layer(m["n"] as Control):
			return false
		var r: Rect2 = m["r"]
		union = union.merge(r)
		widest = maxf(widest, r.size.x)
		tallest = maxf(tallest, r.size.y)
	return union.size.x - widest <= NEAR and union.size.y - tallest <= NEAR


## A GROUP DECLARES ITS OWN ALIGNMENT, AND ONLY THAT DECLARATION IS JUDGED.
##
## This is the whole correctness argument of the pass, and the first version got
## it wrong in both directions:
##
##   * it judged CENTRE in a LEFT-FLUSH column, and reported a deliberately short
##     chip row — perfectly left-aligned with its siblings — as "102px off
##     centre". In a left-flush column the centres differ precisely BECAUSE the
##     widths do, which is not a defect, it is what left-flush means.
##   * it judged EDGES in a CENTRED row, and reported the map HUD's purse coin —
##     a 50px coin deliberately sharing the 40px row's mid-line — as a 5px
##     near-miss on both top and bottom. Those two deviations are equal and
##     opposite, which is the signature of a correctly centred object.
##
## Both mistakes are the same mistake: asking a question the layout never
## claimed an answer to. So the metric with the STRONGEST agreement wins and is
## the only one judged. Everyone agreeing is a pass; exactly one member breaking
## the agreement is the finding; anything less is a scatter with no declared
## alignment, and a pass by default (this pass never guesses at intent).
func _judge_group(state: String, members: Array) -> void:
	if members.size() < 2:
		return
	# Layers in Z, not peers in a row — and never counted as a group judged.
	if _is_layer_stack(members):
		_stacks += 1
		return
	_groups += 1
	# Which way was this group laid out? The axis the centres are SPREAD along is
	# the layout axis; the other one is the axis alignment is a claim about.
	var xs: Array = []
	var ys: Array = []
	for m in members:
		var r: Rect2 = m["r"]
		xs.append(r.get_center().x)
		ys.append(r.get_center().y)
	var spread_x: float = float(xs.max()) - float(xs.min())
	var spread_y: float = float(ys.max()) - float(ys.min())
	var column := spread_y >= spread_x
	var axis := "column" if column else "row"

	var metrics: Array = []
	if column:
		metrics = [
			["left", false, func(r: Rect2) -> float: return r.position.x],
			["centre-x", true, func(r: Rect2) -> float: return r.get_center().x],
			["right", false, func(r: Rect2) -> float: return r.end.x]]
	else:
		metrics = [
			["top", false, func(r: Rect2) -> float: return r.position.y],
			["centre-y", true, func(r: Rect2) -> float: return r.get_center().y],
			["bottom", false, func(r: Rect2) -> float: return r.end.y]]

	# Score every candidate alignment, keep the best-supported one.
	var best_metric := ""
	var best_centre := false
	var best_cluster: Array = []
	var best_vals: Array = []
	for spec in metrics:
		var vals: Array = []
		for m in members:
			vals.append((spec[2] as Callable).call(m["r"] as Rect2))
		var cl := _cluster(vals)
		if cl.size() > best_cluster.size():
			best_cluster = cl
			best_vals = vals
			best_metric = String(spec[0])
			best_centre = bool(spec[1])

	if best_cluster.size() == members.size():
		pass                        # the group agrees with itself: aligned
	elif members.size() >= 3 and best_cluster.size() == members.size() - 1:
		var base := _mean(best_vals, best_cluster)
		for i in members.size():
			if best_cluster.has(i):
				continue
			var dev: float = absf(float(best_vals[i]) - base)
			if dev <= SLOP:
				continue
			# An EDGE broken by a lot is an indent, which is ordinary design; a
			# CENTRE broken at all is the "off centre" report, at any distance.
			if not best_centre and dev > NEAR:
				continue
			_flag(state, members, i, best_metric, best_centre, dev, base,
				best_cluster, best_vals, axis)
	elif members.size() == 2:
		# A PAIR HAS NO MAJORITY, so the near-miss band does the work alone:
		# they share no edge and no centre, yet come within 8px of sharing one.
		# Alignment is a binary act — zero is intent and forty is intent, three
		# is a slip — so this is safe without knowing which was meant.
		var closest := INF
		var which := ""
		for spec in metrics:
			var vals: Array = []
			for m in members:
				vals.append((spec[2] as Callable).call(m["r"] as Rect2))
			var dev: float = absf(float(vals[0]) - float(vals[1]))
			if dev > SLOP and dev <= NEAR and dev < closest:
				closest = dev
				which = String(spec[0])
		if which != "":
			_report(state, "NEAR-MISS", "%s and %s miss sharing a %s by %.1fpx" % [
					_label_of(members[0]["n"]), _label_of(members[1]["n"]),
					which, closest],
				["neither aligned nor deliberately apart (axis %s)" % axis,
					"path=%s" % str((members[0]["n"] as Control).get_path())])

	# SIZE is judged on the CROSS axis only. Along the layout axis differing
	# sizes are the normal case and comparing them there is pure noise.
	if members.size() >= 3:
		var sz: Array = []
		for m in members:
			sz.append((m["r"] as Rect2).size.x if column else (m["r"] as Rect2).size.y)
		var scl := _cluster(sz)
		if scl.size() == members.size() - 1:
			var sbase := _mean(sz, scl)
			for i in members.size():
				if scl.has(i):
					continue
				var dev: float = absf(float(sz[i]) - sbase)
				if dev <= SLOP or dev > NEAR:
					continue        # a deliberately larger peer, or no difference
				var c: Control = members[i]["n"]
				_report(state, "MISMATCH", "%s is %.1fpx %s than the %d peer(s) it matches otherwise"
						% [_label_of(c), dev, "wider" if column else "taller",
							scl.size()],
					["%s %.1f vs %.1f" % ["width" if column else "height",
							float(sz[i]), sbase],
						"path=%s" % str(c.get_path())])


## ── A GUTTER RESERVED ON ONE SIDE ONLY ──────────────────────────────────────
##
## The LOAD GAME screen shipped 26px off centre and every oracle above passed it,
## for a reason worth recording: the three slot plates agreed with EACH OTHER
## perfectly, so there was no odd one out, and the thing they disagreed with —
## the centred title above them — is in another container entirely.
##
## The cause was structural and is checkable. Each row reserved a 44px column for
## a "delete" button that only filled on occupied slots, on the RIGHT only, so
## the plate occupied 568 of the row's 620 and sat flush left inside a column
## that was itself centred on the screen. On a fresh profile — the first time
## anybody sees that screen — nothing ever filled the gutter.
##
## The pattern: an invisible spacer padding ONE end of a row whose content
## otherwise spans it. The span test is what keeps this honest — content filling
## most of its row is content meant to be the row, so a one-sided pad shifts the
## whole thing; content occupying a quarter of its row is being POSITIONED, and a
## lead gutter there is how you align a short label to a list's rail.
func _inkless(c: Control) -> bool:
	return c.get_class() == "Control" and c.get_script() == null \
		and c.get_child_count() == 0


## The union of everything under `c` that actually paints. Containers are skipped
## — they draw nothing, and an HBox's own rect is exactly the full-width box this
## check exists to see past.
func _ink_bounds(c: Control) -> Rect2:
	var out := Rect2()
	var any := false
	var stack: Array = [c]
	while not stack.is_empty():
		var x = stack.pop_front()
		for ch in x.get_children():
			stack.push_back(ch)
		if not (x is Control):
			continue
		var k: Control = x
		if not k.is_visible_in_tree() or k is Container or _inkless(k):
			continue
		# A BARE `Control` NEVER DRAWS. Only childless ones were skipped, so a
		# full-rect Control used as a wrapper contributed its own screen-sized
		# rect to the union and made its subtree's ink look 1600px wide — which
		# then failed the block-size filter and left its children looking like
		# top-level blocks. That is what made Event's two choice seals, a
		# perfectly mirrored pair, read as two independent off-axis blocks.
		if k.get_class() == "Control" and k.get_script() == null:
			continue
		var r := k.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		out = r if not any else out.merge(r)
		any = true
	return out if any else Rect2()


func _judge_one_sided_gutter(state: String, p: Control) -> void:
	if not (p is HBoxContainer):
		return
	var pr := p.get_global_rect()
	if pr.size.x <= 1.0:
		return
	var has_spacer := false
	var painters := 0
	for ch in p.get_children():
		if not (ch is Control) or not (ch as Control).is_visible_in_tree():
			continue
		if _inkless(ch as Control):
			has_spacer = true
		elif _ink_bounds(ch as Control).size.x > 0.0:
			painters += 1
	if not has_spacer:
		return
	# ONE BLOCK, OR THIS IS NOT THE QUESTION. The check asks whether a single
	# piece of content that spans its row got shoved off centre by a spacer. A
	# row holding TWO or more real controls is a layout with ENDS — a centred
	# screen title beside a corner BACK button is the common one — and its ink is
	# asymmetric on purpose. Judging those reported the Collection header, whose
	# title this pass had just centred correctly, as 70px off.
	if painters != 1:
		return
	var ink := _ink_bounds(p)
	if ink.size.x < pr.size.x * 0.70:
		return                      # content is positioned, not spanning
	var dev: float = absf(ink.get_center().x - pr.get_center().x)
	if dev <= SLOP:
		return
	_report(state, "GUTTER", "row content sits %.1fpx off its own centre — a spacer pads one side"
			% dev,
		["content %.0f..%.0f inside a row %.0f..%.0f" % [
				ink.position.x, ink.end.x, pr.position.x, pr.end.x],
			"reserve the same gutter on BOTH sides, or the block reads off-centre",
			"path=%s" % str(p.get_path())])


## ── THE PLAYER READS INK, NOT RECTS ─────────────────────────────────────────
##
## Everything above compares control RECTS, and a rect is not what anybody sees.
## A frameless button's word sits wherever its stylebox margins and its inner
## row put it, which can be tens of pixels inside a rect that lines up perfectly
## — so a column can be flawless by rect and visibly ragged on screen.
##
## It shipped exactly that way: the title screen's `credits` link is a `Button`
## with `flat = true`, which stops the box being DRAWN but still spends its
## content margins on placement, so the word stood 4px right of the rail every
## other line in the column shares. The rect oracle could not see it twice over
## — the offset lives inside the rect, and a Button is never compared against a
## Label anyway.
##
## So worded controls are also compared BY THEIR INK, across class boundaries,
## on the left edge only (the one edge whose ink position is exactly derivable
## for left-aligned text without re-implementing the font stack).
func _ink_left(c: Control) -> float:
	var r := c.get_global_rect()
	if c is Label:
		if (c as Label).horizontal_alignment != HORIZONTAL_ALIGNMENT_LEFT:
			return INF
		return r.position.x
	if c is RichTextLabel:
		return r.position.x
	if c is Button:
		var b: Button = c
		# This codebase's frameless buttons put their word in a child Label
		# inside a left-packed HBox; that Label IS the ink.
		var stack: Array = [b]
		while not stack.is_empty():
			var x = stack.pop_front()
			if x != b and x is Label and (x as Label).text.strip_edges() != "":
				return (x as Label).get_global_rect().position.x
			for ch in x.get_children():
				stack.push_back(ch)
		if b.text.strip_edges() == "":
			return INF
		if b.alignment != HORIZONTAL_ALIGNMENT_LEFT:
			return INF
		var sb := b.get_theme_stylebox("normal")
		var pad := 0.0 if sb == null else sb.get_margin(SIDE_LEFT)
		return r.position.x + pad
	return INF


## A COLUMN MAY HAVE MORE THAN ONE RAIL, and requiring one majority is how the
## first version of this managed to be completely inert.
##
## The title screen's column has two legitimate rails: the six action buttons
## stand 40px in, leaving a gutter for the hover flame to ignite in, while the
## tagline, the epigraph and the record line share the outer rail. With ten
## worded controls split 6/3, no "all but one agree" majority can ever form — so
## the `credits` link, sitting 4px off the outer rail, was invisible to a gate
## written to catch exactly it. (Verified by mutation: the fix was reverted and
## the gate stayed green.)
##
## Stated properly, the rule does not need a majority at all. Ink positions
## cluster into RAILS; a rail with two or more members is an established
## alignment. The defect is a rail that comes within the near-miss band of
## ANOTHER rail without joining it — almost lined up, which is the one thing
## alignment is never allowed to be.
func _judge_ink(state: String, worded: Array) -> void:
	if worded.size() < 3:
		return
	var order: Array = range(worded.size())
	order.sort_custom(func(a, b): return float(worded[a]["ink"]) < float(worded[b]["ink"]))
	# Greedy single-linkage into rails: a gap wider than EXACT starts a new one.
	var rails: Array = []
	var cur: Array = []
	for i in order:
		if cur.is_empty() or absf(float(worded[i]["ink"])
				- float(worded[int(cur[-1])]["ink"])) <= EXACT:
			cur.append(i)
		else:
			rails.append(cur)
			cur = [i]
	if not cur.is_empty():
		rails.append(cur)
	if rails.size() < 2:
		return
	for a in rails.size():
		var ra: Array = rails[a]
		var va: float = _mean_ink(worded, ra)
		for b in rails.size():
			if a == b:
				continue
			var rb: Array = rails[b]
			if rb.size() < 2 or rb.size() <= ra.size():
				continue          # only a WEAKER rail is judged against a stronger
			var dev: float = absf(va - _mean_ink(worded, rb))
			if dev <= SLOP or dev > NEAR:
				continue          # aligned, or deliberately indented
			var names: Array = []
			for i in ra:
				names.append(_label_of(worded[int(i)]["n"]))
			_report(state, "INK", "%s prints %.1fpx off the rail %d other line(s) share"
					% [", ".join(PackedStringArray(names)).substr(0, 44), dev,
						rb.size()],
				["ink starts at x=%.1f, the rail at x=%.1f" % [
						va, _mean_ink(worded, rb)],
					"the RECTS can line up perfectly — this is where the WORD lands",
					"path=%s" % str((worded[int(ra[0])]["n"] as Control).get_path())])
			break


func _mean_ink(worded: Array, idx: Array) -> float:
	var s := 0.0
	for i in idx:
		s += float(worded[int(i)]["ink"])
	return s / maxf(1.0, float(idx.size()))


func _flag(state: String, members: Array, i: int, metric: String, is_centre: bool,
		dev: float, base: float, cl: Array, vals: Array, axis: String) -> void:
	var c: Control = members[i]["n"]
	var agree: Array = []
	for j in cl:
		agree.append(_label_of(members[int(j)]["n"]))
	var kind := "OFF-CENTRE" if is_centre else "OFF-" + metric.to_upper()
	_report(state, kind, "%s is %.1fpx off the %s its %d peer(s) share" % [
			_label_of(c), dev, metric, cl.size()],
		["%s: %.1f, the other %d at %.1f (axis %s)" % [
				metric, float(vals[i]), cl.size(), base, axis],
			"peers: %s" % ", ".join(PackedStringArray(agree)).substr(0, 88),
			"path=%s" % str(c.get_path())])


# ── oracle C: the layout system was told to centre and did not ───────────────

func _judge_declared_centre(state: String, p: Control, kids: Array,
		partial: bool) -> void:
	if kids.is_empty():
		return
	# A BLOCK MEASURED WITH A MEMBER MISSING IS NOT THE BLOCK. This check unions
	# the container's children and compares that union's centre with the
	# container's — so it is only valid when every child is in the union. The
	# menu column's title is excluded (it breathes on a scale tween), and
	# unioning the remaining four reported the column as 40px low when it is
	# centred to the pixel.
	if partial:
		return
	var pr := p.get_global_rect()
	if pr.size.x <= 0.0 or pr.size.y <= 0.0:
		return
	var union: Rect2 = kids[0]["r"]
	for k in kids:
		union = union.merge(k["r"])

	if p is CenterContainer:
		for ax in ["x", "y"]:
			var kid_c: float = union.get_center().x if ax == "x" else union.get_center().y
			var par_c: float = pr.get_center().x if ax == "x" else pr.get_center().y
			var span: float = union.size.x if ax == "x" else union.size.y
			var room: float = pr.size.x if ax == "x" else pr.size.y
			if span >= room - SLOP:
				continue          # fills the axis: there is nothing to centre
			if absf(kid_c - par_c) <= SLOP:
				continue
			_report(state, "DECLARED", "CenterContainer content sits %.1fpx off its own centre (%s)"
					% [absf(kid_c - par_c), ax],
				["%s says centre; content centre %.1f vs container centre %.1f"
						% [p.get_class(), kid_c, par_c],
					"contents: %s" % _label_of(kids[0]["n"]),
					"path=%s" % str(p.get_path())])
	elif p is BoxContainer and (p as BoxContainer).alignment == BoxContainer.ALIGNMENT_CENTER:
		var vertical := p is VBoxContainer
		var kid_c: float = union.get_center().y if vertical else union.get_center().x
		var par_c: float = pr.get_center().y if vertical else pr.get_center().x
		var span: float = union.size.y if vertical else union.size.x
		var room: float = pr.size.y if vertical else pr.size.x
		if span >= room - SLOP:
			return
		if absf(kid_c - par_c) <= SLOP:
			return
		_report(state, "DECLARED", "%s alignment=CENTER but its block sits %.1fpx off centre"
				% [p.get_class(), absf(kid_c - par_c)],
			["block centre %.1f vs container centre %.1f (span %.1f in %.1f)"
					% [kid_c, par_c, span, room],
				"first child: %s" % _label_of(kids[0]["n"]),
				"path=%s" % str(p.get_path())])


# ── oracle D2/D3: shapes that need no company ────────────────────────────────

func _judge_shape(state: String, c: Control, r: Rect2) -> void:
	if c is BaseButton and not (c as BaseButton).disabled \
			and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		var small: float = minf(r.size.x, r.size.y)
		if small < MIN_TARGET:
			_report(state, "TARGET", "%s is %.0f×%.0f — under the %.0fpx minimum target"
					% [_label_of(c), r.size.x, r.size.y, MIN_TARGET],
				["a press this small is a miss for most players",
					"path=%s" % str(c.get_path())])
	# A COLLAPSED SHAPE IS ONLY A DEFECT IF SOMETHING WAS SUPPOSED TO FIT IN IT.
	# This judged Panels too, and reported Combat's divider bars — a 1036x14 band
	# and a 1072x4 hairline rule — as "collapsed". A long thin Panel is what a
	# rule IS; it is the house's most-used piece of furniture. Only an
	# interactive control flattened to a line is the bug this is looking for.
	if r.size.x > 0.0 and r.size.y > 0.0 and c is BaseButton:
		var aspect: float = maxf(r.size.x / r.size.y, r.size.y / r.size.x)
		if aspect > ASPECT_MAX:
			_report(state, "PROPORTION", "%s has collapsed to %.0f×%.0f (aspect %.0f:1)"
					% [_label_of(c), r.size.x, r.size.y, aspect],
				["path=%s" % str(c.get_path())])


# ── the scan ─────────────────────────────────────────────────────────────────

func _scan(node: Node, state: String) -> void:
	_states += 1
	var before := _hits
	var stack: Array = [node]
	var parents: Array = []
	while not stack.is_empty():
		var n = stack.pop_front()
		for ch in n.get_children():
			stack.push_back(ch)
		if not (n is Control):
			continue
		var p: Control = n
		if not p.is_visible_in_tree():
			continue
		parents.append(p)


	for p in parents:
		# Gather this parent's own laid-out children.
		var kids: Array = []
		var partial := false
		for ch in (p as Control).get_children():
			if not (ch is Control):
				continue
			var c: Control = ch
			if not c.is_visible_in_tree():
				continue
			if _excluded(c):
				partial = true
				continue
			var r := c.get_global_rect()
			# BOTH OF THESE DROPS MAKE THE UNION INCOMPLETE, so both must raise
			# `partial` — the flag means "this is not the whole block", and
			# `_judge_declared_centre` is the one oracle that cannot survive a
			# missing member. Only `_excluded` used to set it, which left two
			# silent holes and produced a real false positive: `net_lobby:ready`
			# was reported 27.5px off centre, and 27.5 is EXACTLY half the 55px
			# the report itself printed as the gap between the span and the
			# container. Measured directly, that column is centred to the pixel —
			# a child at one end had been dropped, so the union lost its height
			# and the centre moved by half of it. That arithmetic (deviation ==
			# half the missing extent) is the signature of this bug, not of a
			# layout one.
			if r.size.x <= 1.0 or r.size.y <= 1.0:
				partial = true
				continue
			if not Rect2(Vector2.ZERO, _canvas).intersects(r):
				partial = true
				continue          # off-canvas is _probe_boundary_ui's beat
			kids.append({"n": c, "r": r})
		if kids.is_empty():
			continue
		_controls += kids.size()
		for k in kids:
			_judge_shape(state, k["n"], k["r"])
		_judge_declared_centre(state, p, kids, partial)
		_judge_one_sided_gutter(state, p)
		# Peers are judged only against their own kind.
		var fams := {}
		for k in kids:
			var f := _family(k["n"])
			if not fams.has(f):
				fams[f] = []
			fams[f].append(k)
		for f in fams.keys():
			_judge_group(state, fams[f])
		# Worded peers are ALSO compared by ink, across the Button/Label divide.
		var worded: Array = []
		for k in kids:
			var ink := _ink_left(k["n"])
			if ink < INF:
				worded.append({"n": k["n"], "ink": ink})
		_judge_ink(state, worded)

	if _hits == before:
		print("  ok    %s" % state)


# ── staging (shared with _probe_input_reach) ─────────────────────────────────

func _stage(kind: String, hero_i: int) -> void:
	seed(SEED)
	RS.start_new_run(HEROES[hero_i % HEROES.size()], 0, SEED)
	RS.gold = 800 if kind == "rich" else 150
	RS.hero_hp = RS.hero_max_hp


func _settle(sec: float = 1.4) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		await create_timer(0.02).timeout
		t += 0.02


func _simple(label: String, path: String, kind: String, hero_i: int) -> void:
	_stage(kind, hero_i)
	var n = load(path).instantiate()
	root.add_child(n)
	await _settle()
	if is_instance_valid(n):
		_scan(n, label)
		n.queue_free()
	await process_frame


## ── HELPER CONTRACT: A SHARED BUILDER MUST PRODUCE WHAT IT WAS ASKED FOR ─────
##
## The geometry oracles above are relational, and a shared helper that is wrong
## the SAME way at every call site is invisible to them — every rule it draws is
## consistently, identically short, so nothing is the odd one out.
##
## `_make_ornament_row(width, ...)` is the shell's divider: six call sites across
## the title screen, the menu column, the dossier and the muster panels. It took
## a `width` and sized each half at `width * 0.45` with the separations and the
## diamond added ON TOP, so the number a caller passed was not the width it got.
## The dossier asked for 340 and drew 183 — a rule stopping barely past half the
## panel it divides. The contract is now literal, and this is what holds it.
func _check_helper_contracts(m: Node) -> void:
	if not m.has_method("_make_ornament_row"):
		return
	var host := VBoxContainer.new()
	host.custom_minimum_size = Vector2(1200, 500)
	root.add_child(host)
	var rows: Array = []
	for spec in [[260.0, true, true], [200.0, true, false], [340.0, true, false],
			[220.0, false, false], [340.0, false, true], [120.0, false, false]]:
		var r = m.call("_make_ornament_row", float(spec[0]), bool(spec[1]),
			bool(spec[2]))
		host.add_child(r)
		rows.append({"r": r, "w": float(spec[0]), "l": bool(spec[1]),
			"g": bool(spec[2])})
	await _settle(0.4)
	for e in rows:
		var c: Control = e["r"]
		if not is_instance_valid(c):
			continue
		var got: float = c.size.x
		if absf(got - float(e["w"])) <= SLOP:
			continue
		_report("helper", "CONTRACT",
			"_make_ornament_row(%.0f, left=%s, glyph=%s) draws %.0fpx" % [
				float(e["w"]), str(e["l"]), str(e["g"]), got],
			["a caller's width must be the width it gets — this one is %.0fpx %s"
				% [absf(got - float(e["w"])),
					"short" if got < float(e["w"]) else "over"]])
	host.queue_free()
	await process_frame


func _menu_states() -> void:
	_stage("default", 0)
	var m = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(m)
	await _settle(1.8)
	await _check_helper_contracts(m)
	_scan(m, "main_menu")

	# THE MUSTER — four screens, each built programmatically over the menu.
	if m.has_method("_show_hero_select"):
		for step in [1, 2, 3, 4]:
			m.call("_show_hero_select", step)
			await _settle(1.2)
			_scan(m, "muster:%d" % step)

	# THE STARTING BONUS is a SEPARATE screen from the muster (it has been since
	# 2026-09-16) and this pass walked straight past it for as long as it has
	# existed: `_show_hero_select` rebuilds run setup and never reaches it, so the
	# four writ tiles — a peer group of four laid-out sheets, each with its own
	# internal rows — were judged by nothing. Exactly the coverage question C20
	# exists to ask: a gate is only correct if it can open.
	if m.has_method("_show_starting_bonus"):
		m.call("_show_starting_bonus")
		await _settle(1.4)
		_scan(m, "starting_bonus")
		# Back to run setup, so the states after this one start where they used
		# to — the bonus screen owns a sibling backdrop that its own exit path is
		# what removes.
		if m.has_method("_leave_starting_bonus"):
			m.call("_leave_starting_bonus")
			await _settle(1.0)

	for pair in [["_show_load_screen", "load_game"], ["_show_how_to_play", "how_to_play"],
			["_show_quick_march", "skirmish_setup"]]:
		if not m.has_method(String(pair[0])):
			continue
		if String(pair[0]) == "_show_load_screen":
			m.call(String(pair[0]), false)
		else:
			m.call(String(pair[0]))
		await _settle(1.2)
		_scan(m, String(pair[1]))

	# The settings overlay, in both contexts. It hangs off the UserSettings
	# autoload as a CanvasLayer — NOT a Control — which is how the first version
	# of this scanned nothing at all and said so by printing no line whatsoever.
	# A state that silently fails to stage is worse than one that fails loudly.
	var GT = root.get_node_or_null("GameTheme")
	for ctx in ["settings", "settings_paused"]:
		if GT == null or not GT.has_method("open_settings_overlay"):
			break
		if ctx == "settings_paused":
			RS.run_active = true
		GT.call("open_settings_overlay")
		await _settle(1.2)
		var found := false
		for ch in US.get_children():
			if ch is CanvasLayer or ch is Control:
				found = true
				_scan(ch, ctx)
		if not found:
			print("  FAIL  %s never staged — nothing hangs off UserSettings" % ctx)
			_hits += 1
		for ch in US.get_children():
			if ch.has_method("_close"):
				ch.call("_close")
		await _settle(0.5)
	RS.run_active = false

	if is_instance_valid(m):
		m.queue_free()
	await process_frame


## Drive a settled combat scene into a state worth measuring. Each arm is
## defensive about method names — Combat is 20k lines and a renamed internal
## should skip a state, not take the whole gate down with it.
func _combat_load(cb: Node, what: String) -> void:
	match what:
		"played":
			# A BOARD WITH BODIES ON IT is a different layout from an empty one:
			# the lane slots fill, the hand shrinks, the status rails appear.
			if cb.has_method("_place_enemy_card") and EDB != null:
				var deck: Array = EDB.build_enemy_deck(
					String(RS.current_encounter_id))
				for i in mini(3, deck.size()):
					cb.call("_place_enemy_card", deck[i], i)
					await _settle(0.25)
			await _settle(1.0)
		"pile":
			if cb.has_method("_show_pile_viewer"):
				if cb.get("_player_discard_pile") != null \
						and (cb.get("_player_discard_pile") as Array).is_empty():
					for i in mini(8, RS.deck.size()):
						(cb.get("_player_discard_pile") as Array).append(RS.deck[i])
				cb.call("_show_pile_viewer", 1)
				await _settle(1.4)
		"glossary":
			if cb.has_method("_reset_glossary_layer"):
				cb.call("_reset_glossary_layer", 0.56)
				await _settle(1.4)


func _arm_offline_peer() -> void:
	if ClassDB.class_exists("OfflineMultiplayerPeer"):
		get_multiplayer().multiplayer_peer = ClassDB.instantiate("OfflineMultiplayerPeer")


## The multiplayer shell — the lobby in its three states, then each mode's own
## deck screen behind the shared arsenal overlay.
func _net_states() -> void:
	var NM = root.get_node_or_null("NetMatch")
	var SS = root.get_node_or_null("SkirmishState")
	if NM == null or SS == null:
		return
	var lobby = load("res://scenes/net_lobby.tscn").instantiate()
	root.add_child(lobby)
	await _settle(2.6)
	_scan(lobby, "net_lobby")
	if lobby.has_method("_on_vs_bot_pressed"):
		lobby.call("_on_vs_bot_pressed")
		await _settle(1.0)
		_scan(lobby, "net_lobby:bot")
		if lobby.has_method("_on_vs_bot_back"):
			lobby.call("_on_vs_bot_back")
			await process_frame
	if lobby.has_method("_on_room_created"):
		# The connected-lobby state broadcasts the picked lord and the match
		# config, and `rpc()` with no peer assigned prints an engine ERROR — this
		# harness pretending a peer exists, not a defect, but an ERROR line
		# before the verdict is exactly what a gate runner must fail on. Armed
		# HERE rather than once at the top because the practice-bot panel above
		# routes through `NetMatch.leave()`, which nulls whatever was set.
		_arm_offline_peer()
		NM.is_host = true
		lobby.call("_on_room_created", "KM7Q2R")
		await process_frame
		NM.remote_present = true
		NM.remote_hero = "stalwart"
		NM.remote_ready = true
		if lobby.has_method("_on_peer_joined"):
			lobby.call("_on_peer_joined", 2)
		await _settle(1.2)
		_scan(lobby, "net_lobby:ready")
	lobby.queue_free()
	await process_frame

	for row in [["draft", "res://scenes/net_draft.tscn", SS.MatchMode.DRAFT],
			["quick", "res://scenes/net_quick.tscn", SS.MatchMode.QUICK],
			["constructed", "res://scenes/net_constructed.tscn", SS.MatchMode.CONSTRUCTED],
			["sealed", "res://scenes/net_sealed.tscn", SS.MatchMode.SEALED]]:
		NM.start_vs_bot(row[2], 1)
		var n = load(String(row[1])).instantiate()
		root.add_child(n)
		await _settle(2.8)
		if not is_instance_valid(n):
			continue
		_scan(n, "net:%s/arsenal" % String(row[0]))
		# Clear the arsenal overlay so the mode's OWN screen is measured too.
		# PASS rather than pick: it is allowed once per slate and needs no
		# knowledge of what was dealt (the deal is seeded per session, so a
		# hardcoded id would only match the slate by luck).
		for _i in range(8):
			if not n.has_method("_on_ars_pass") or n.get("_ars_layer") == null:
				break
			n.call("_on_ars_pass")
			await _settle(0.45)
		await _settle(1.4)
		if is_instance_valid(n):
			_scan(n, "net:%s" % String(row[0]))
			n.queue_free()
		await process_frame
	NM.vs_bot = false
	SS.vs_bot = false
	NM.is_host = false
	NM.remote_present = false
	get_multiplayer().multiplayer_peer = null


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or US == null:
		print("[align] FATAL: autoloads missing"); _done = true; quit(1); return
	US.anim_speed = 3.0
	US.end_turn_warning = false
	_canvas = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	print("[align] CLASS C30 — the odd one out, the near miss, the broken claim\n")

	await _menu_states()

	for row in [
		["collection", "res://scenes/collection.tscn", "default", 0],
		["credits", "res://scenes/credits.tscn", "default", 0],
		["map", "res://scenes/map.tscn", "default", 1],
		["reward", "res://scenes/reward.tscn", "rich", 1],
		["shop", "res://scenes/shop.tscn", "rich", 2],
		["rest", "res://scenes/rest.tscn", "default", 3],
		["treasure", "res://scenes/treasure.tscn", "rich", 3],
		["recruit", "res://scenes/recruit.tscn", "default", 4],
		["game_over", "res://scenes/game_over.tscn", "default", 4],
	]:
		await _simple(String(row[0]), String(row[1]), String(row[2]), int(row[3]))

	for verb in ["drill_yard", "standard_bearer", "supply_cache"]:
		_stage("rich", 2)
		RS.current_wayside_id = verb
		var n = load("res://scenes/wayside.tscn").instantiate()
		root.add_child(n)
		await _settle()
		if is_instance_valid(n):
			_scan(n, "wayside:%s" % verb)
			n.queue_free()
		await process_frame

	await _net_states()

	# Events — every authored screen, since the choice count and the prose length
	# are what move this layout around.
	var EvScript = load("res://scripts/scenes/Event.gd")
	var ev_ids: Array = EvScript.EVENTS.keys()
	ev_ids.sort()
	for ev_id in ev_ids:
		_stage("rich", 1)
		var ev = load("res://scenes/event.tscn").instantiate()
		root.add_child(ev)
		await process_frame
		ev._clear_ui()
		ev._event_id = String(ev_id)
		ev._event_data = EvScript.EVENTS[ev_id].duplicate(true)
		ev._current_node = ev._event_data
		ev._build_ui()
		await _settle(1.6)
		if is_instance_valid(ev):
			_scan(ev, "event:%s" % String(ev_id))
			ev.queue_free()
		await process_frame

	# ── COMBAT, AND COMBAT UNDER LOAD ────────────────────────────────────────
	# The densest laid-out surface in the game, and for a long time the only one
	# this pass saw AT REST. A board with cards on it, a modal over the top and a
	# hand at full width are all different layouts, and they are the ones a
	# player looks at for the whole game.
	if EDB != null:
		for enc in ["goblin_scouts", "iron_warden"]:
			if not EDB.ENCOUNTERS.has(enc):
				# A MISSPELLED ID IS SILENT COVERAGE LOSS. This list said
				# `the_iron_warden`, which is not an encounter (the id is
				# `iron_warden`), so the loop measured ONE encounter for weeks
				# while reporting nothing wrong. A skip that nobody is told
				# about is indistinguishable from a pass.
				print("  FAIL  combat:%s — no such encounter id" % enc)
				_hits += 1
				continue
			for what in ["rest", "played", "pile", "glossary"]:
				_stage("default", 0)
				RS.current_encounter_id = enc
				RS.current_node_type = String(
					EDB.ENCOUNTERS[enc].get("type", "combat"))
				var cb = load("res://scenes/combat.tscn").instantiate()
				root.add_child(cb)
				await _settle(7.0)
				if is_instance_valid(cb):
					await _combat_load(cb, what)
				if is_instance_valid(cb):
					_scan(cb, "combat:%s/%s" % [enc, what])
					cb.queue_free()
				await _settle(0.4)

	print("\n[align] %d screen state(s), %d control(s) in %d peer group(s)"
		% [_states, _controls, _groups])
	# AN EXCLUSION NOBODY IS TOLD ABOUT IS INDISTINGUISHABLE FROM A PASS — the
	# same rule the misspelled-encounter check above is written to. Printed with
	# the verdict so a stack exclusion that starts swallowing hundreds of groups
	# is visible in the log instead of quietly hollowing the gate out.
	print("[align] %d layer stack(s) skipped — full-rect siblings nudged, not laid out"
		% _stacks)
	print("[align] %s" % ("EVERYTHING LINES UP" if _hits == 0
		else "%d ALIGNMENT DEFECT(S)" % _hits))
	_done = true
	quit(1 if _hits > 0 else 0)
