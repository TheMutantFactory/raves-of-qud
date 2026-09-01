extends Node

## THE THREE PIECES OF A FIRE, each on its own switch — headless.
##
##   Godot --headless --path godot/ --quit-after 120 res://tests/fire_flags.tscn
##
## Daniel asked whether anything could turn the torch/campfire floor lighting off. Nothing could:
## _place_light was gated on 1:1 and the world map and on nothing else, so a Raves fire was three
## objects over one Qud-lit cell — a pool, a flame, a plume — with a lever on only the plume, and
## that lever (`particles`) deliberately exempted fires.
##
## WHAT IS ACTUALLY EASY TO GET WRONG HERE is not the gate, it is everything that runs AFTER it.
## The flicker driver rewrites transparency and `emitting` on every fixture every frame, and a
## GPUParticles3D goes on emitting while invisible — so a flag that is only read at build time is
## undone one frame later, and one that only sets `visible` leaves a hidden emitter smoking.

var _failed: Array[String] = []


func _ready() -> void:
	# USER MODE, PINNED — before the renderer is built, since its _ready re-reads these gates.
	# They go through Settings.qud_shape(), which returns true UNCONDITIONALLY in 1:1, so on a
	# machine whose settings.json says `"mode": "1to1"` no fixture is ever built and twelve of
	# the checks below fail reporting `pools=0 flames=0 plumes=0` — a red SPOT run caused by the
	# developer's own config rather than by the code. set_value is in-memory only (save() is what
	# writes to disk), so pinning it here cannot disturb the real settings file.
	Settings.one_to_one_only = false
	Settings.set_value("mode", "user")

	var r = load("res://ZoneRenderer.gd").new()
	add_child(r)
	r._light_root = Node3D.new()
	add_child(r._light_root)
	r._live_build = true

	# ── all three on: a whole fire ────────────────────────────────────────────
	_set_flags(true, true, true)
	r._refresh_fx_flags()
	_light(r, 4, 4, true)
	_check("a fire has a floor pool", _vis(r, r.FX_POOL_GROUP) == 1, _tally(r))
	_check("...a flame", _vis(r, r.FX_FLAME_GROUP) == 1, _tally(r))
	_check("...and a plume", _emitting(r) == 1, _tally(r))

	# ── each flag off in turn, applied to fixtures that ALREADY EXIST ─────────
	# The toggle has to reach what is already built. A user flips this in the options overlay while
	# standing in a lit zone; "takes effect when you walk somewhere else" is the failure being
	# ruled out.
	_set_flags(false, true, true)
	_check("the flags notice the change", r._refresh_fx_flags())
	r._apply_fx_flags()
	_check("floorglow off clears the pool", _vis(r, r.FX_POOL_GROUP) == 0, _tally(r))
	_check("...and leaves the flame", _vis(r, r.FX_FLAME_GROUP) == 1, _tally(r))
	_check("...and the plume", _emitting(r) == 1, _tally(r))

	_set_flags(true, false, true)
	r._refresh_fx_flags()
	r._apply_fx_flags()
	_check("flames off clears the flame", _vis(r, r.FX_FLAME_GROUP) == 0, _tally(r))
	_check("...and leaves the pool", _vis(r, r.FX_POOL_GROUP) == 1, _tally(r))

	_set_flags(true, true, false)
	r._refresh_fx_flags()
	r._apply_fx_flags()
	_check("firesmoke off stops the plume", _emitting(r) == 0, _tally(r))
	_check("...and leaves the pool and flame",
		_vis(r, r.FX_POOL_GROUP) == 1 and _vis(r, r.FX_FLAME_GROUP) == 1, _tally(r))

	# ── the flags survive the frame that follows ─────────────────────────────
	# THE DRIVER IS THE THREAT. It writes amount_ratio/emitting/transparency over every fixture in
	# _lights every frame, from the daylight multipliers alone — a build-time-only gate is undone
	# by the very next frame and the fire comes back.
	_set_flags(false, false, false)
	r._refresh_fx_flags()
	r._apply_fx_flags()
	r.set_daylight(0.0)          # deep night: every multiplier at full, maximum pressure to relight
	r._process(0.016)
	_check("a frame of the flicker driver does not relight the pool",
		_vis(r, r.FX_POOL_GROUP) == 0, _tally(r))
	_check("...nor the flame", _vis(r, r.FX_FLAME_GROUP) == 0, _tally(r))
	# A HIDDEN EMITTER STILL EMITS. Godot keeps simulating a GPUParticles3D whose visible is false,
	# so `emitting` is the only honest question to ask of smoke — and of the flame, which is a
	# particle system too on the live path. Switching it off invisibly would leave the whole rig
	# simulating behind a hidden node, paying for a fire nobody asked to see.
	_check("...nor the plume", _emitting(r) == 0, _tally(r))
	_check("...and the switched-off flame is not still simulating", _flame_emitting(r) == 0,
		"%d emitting" % _flame_emitting(r))

	# ── SOMETHING ELSE TURNS THEM BACK ON ────────────────────────────────────
	# The bug that survived five rounds of looking. The pool over an arc sconce was visible with
	# `floorglow` off while sitting IN the fx_pool group — so it had been gated at birth, and
	# something re-showed it afterwards (the floor pool recycles MeshInstance3Ds and writes
	# visible=true on them, which is the shape of it). Gating at birth and on change is not enough
	# against a writer that runs every frame; the driver has to re-assert it every frame too.
	_set_flags(false, false, true)
	r._refresh_fx_flags()
	r._apply_fx_flags()
	_check("the pool starts hidden", _vis(r, r.FX_POOL_GROUP) == 0, _tally(r))
	for n in r.get_tree().get_nodes_in_group(r.FX_POOL_GROUP):
		(n as Node3D).visible = true        # an outside writer, exactly as the recycler does
	for n in r.get_tree().get_nodes_in_group(r.FX_FLAME_GROUP):
		(n as Node3D).visible = true
	_check("...and an outside writer can turn it back on", _vis(r, r.FX_POOL_GROUP) > 0, _tally(r))
	r.set_daylight(0.0)
	r._process(0.016)
	_check("one frame of the driver takes it back off", _vis(r, r.FX_POOL_GROUP) == 0, _tally(r))
	_check("...and the flame with it", _vis(r, r.FX_FLAME_GROUP) == 0, _tally(r))
	# THE OTHER FLAME IN THE LIVE ZONE. A live fixture gets a particle fire only when it smokes or
	# is on fire; a glow-critter gets the DRAWN sprite instead, and that branch of the driver is
	# the one no fixture in this file was building — its re-assertion could be deleted with every
	# check still green.
	var critter_before := _vis(r, r.FX_FLAME_GROUP)
	r._place_light(40, 40, 3.0, false, false)      # smokes=false, on_fire=false: a glow critter
	_check("a glow-critter builds the drawn flame", _vis(r, r.FX_FLAME_GROUP) == critter_before,
		"born hidden with the flag off: %s" % _tally(r))
	for n in r.get_tree().get_nodes_in_group(r.FX_FLAME_GROUP):
		(n as Node3D).visible = true
	r._process(0.016)
	_check("...and the driver takes the drawn flame back off too",
		_vis(r, r.FX_FLAME_GROUP) == 0, _tally(r))

	# ...and it does not fight a flag that is ON: a re-assertion that always hid them would pass
	# every check above and delete the fires outright.
	_set_flags(true, true, true)
	r._refresh_fx_flags()
	r._process(0.016)
	_check("with the flags on, the driver leaves them lit",
		_vis(r, r.FX_POOL_GROUP) > 0 and _vis(r, r.FX_FLAME_GROUP) > 0, _tally(r))
	_set_flags(false, false, false)
	r._refresh_fx_flags()
	r._apply_fx_flags()

	# ── born with the flags already on them ──────────────────────────────────
	# A fixture built while a flag is off must come out switched off, not switched off a frame
	# later: a zone build hitch holds that first frame on screen, which is how the pools came to
	# flash full-bright at noon on every zone crossing once already.
	_light(r, 9, 9, true)
	_check("a fire built with the flags off is born dark",
		_vis(r, r.FX_POOL_GROUP) == 0 and _vis(r, r.FX_FLAME_GROUP) == 0 and _emitting(r) == 0,
		_tally(r))

	# ── the OTHER flame, the one banked zones get ────────────────────────────
	# A live zone's flame is a particle system; a remembered or neighbour zone's is a drawn sprite,
	# because emitters are live-zone-only under the bounded-particle rule. That is a whole second
	# construction path, and with _live_build left true above it had never been built here at all —
	# deleting its gate outright changed nothing and every check still passed.
	_set_flags(false, false, false)
	r._refresh_fx_flags()
	r._live_build = false
	var banked_before := _count(r)
	_light(r, 19, 19, true)
	_check("a banked zone builds its own kind of flame", _count(r) > banked_before,
		"%d -> %d" % [banked_before, _count(r)])
	_check("...and it is born switched off too",
		_vis(r, r.FX_POOL_GROUP) == 0 and _vis(r, r.FX_FLAME_GROUP) == 0, _tally(r))
	_set_flags(true, true, true)
	r._refresh_fx_flags()
	_light(r, 24, 24, true)
	_check("...and born lit when the flags are on",
		_vis(r, r.FX_POOL_GROUP) == 1 and _vis(r, r.FX_FLAME_GROUP) == 1, _tally(r))
	r._live_build = true

	# ── a torch is not a fire ────────────────────────────────────────────────
	# `firesmoke` covers what is ON FIRE. A sconce's night plume stays under `particles`, which is
	# off by default — folding the two together would have deleted campfire smoke for everyone who
	# never opted into ambience.
	_set_flags(true, true, false)
	Settings.set_value("qol_particles", true)
	r._refresh_fx_flags()
	_check("a sconce plume answers to `particles`, not `firesmoke`", r._smoke_wanted(false))
	_check("...and a fire's plume answers to `firesmoke`", not r._smoke_wanted(true))
	Settings.set_value("qol_particles", false)
	_check("with `particles` off the sconce plume stops", not r._smoke_wanted(false))

	# ── 1:1 is untouched ─────────────────────────────────────────────────────
	# Parity mode has no fixture to switch: _place_light returns before it builds anything.
	_set_flags(true, true, true)
	r._refresh_fx_flags()
	var before := _count(r)
	r._one_to_one = true
	_light(r, 14, 14, true)
	_check("1:1 builds no fixture at all, flags or no flags", _count(r) == before,
		"%d -> %d" % [before, _count(r)])
	r._one_to_one = false

	# ── a renderer that has never been told ──────────────────────────────────
	# Every check above hand-calls _refresh_fx_flags() first, so none of them can tell whether the
	# app ever makes that call itself — deleting it from _ready broke nothing. This builds a fresh
	# renderer with a flag already off and asks it for a fire without a word of setup, which is
	# what entering the first zone of a session actually does.
	_set_flags(false, false, false)
	var r2 = load("res://ZoneRenderer.gd").new()
	add_child(r2)                       # _ready runs here, and must read the flags
	r2._light_root = Node3D.new()
	add_child(r2._light_root)
	r2._live_build = true
	r2._place_light(4, 4, 3.0, true, true)
	_check("the first fire of a session is born switched off",
		_vis_under(r2._light_root, r2.FX_POOL_GROUP) == 0
		and _vis_under(r2._light_root, r2.FX_FLAME_GROUP) == 0,
		"pools=%d flames=%d" % [_vis_under(r2._light_root, r2.FX_POOL_GROUP),
			_vis_under(r2._light_root, r2.FX_FLAME_GROUP)])
	# ...and the same renderer with the flags ON, so the check above is not passing because this
	# path builds nothing at all.
	_set_flags(true, true, true)
	var r3 = load("res://ZoneRenderer.gd").new()
	add_child(r3)
	r3._light_root = Node3D.new()
	add_child(r3._light_root)
	r3._live_build = true
	r3._place_light(4, 4, 3.0, true, true)
	_check("...and born lit when nothing is switched off",
		_vis_under(r3._light_root, r3.FX_POOL_GROUP) == 1
		and _vis_under(r3._light_root, r3.FX_FLAME_GROUP) == 1,
		"pools=%d flames=%d" % [_vis_under(r3._light_root, r3.FX_POOL_GROUP),
			_vis_under(r3._light_root, r3.FX_FLAME_GROUP)])

	_report()


## Build one fixture at a cell. `fire` picks a campfire (a plume that burns day and night) over a
## sconce, because a fire's smoke is the piece `firesmoke` governs.
func _light(r, cx: int, cy: int, fire: bool) -> void:
	r._place_light(cx, cy, 3.0, true, fire)


func _set_flags(pool: bool, flame: bool, smoke: bool) -> void:
	Settings.set_value("qol_floorglow", pool)
	Settings.set_value("qol_flames", flame)
	Settings.set_value("qol_firesmoke", smoke)


## Visible nodes in a fixture group. Counts LIVE ones, so a freed node cannot pad the tally.
func _vis(r, group: String) -> int:
	var n := 0
	for c in r.get_tree().get_nodes_in_group(group):
		if is_instance_valid(c) and (c as Node3D).visible:
			n += 1
	return n


## Flame emitters still simulating. Separate from _vis on purpose: `visible` and `emitting` are
## different questions and only one of them costs anything when the answer is wrong.
func _flame_emitting(r) -> int:
	var n := 0
	for c in r.get_tree().get_nodes_in_group(r.FX_FLAME_GROUP):
		if is_instance_valid(c) and c is GPUParticles3D and (c as GPUParticles3D).emitting:
			n += 1
	return n


## Visible fixtures UNDER one renderer's light root. The groups are tree-wide, so counting them
## globally would tally every fixture built earlier in this file against a fresh renderer.
func _vis_under(root: Node3D, group: String) -> int:
	var n := 0
	for c in root.get_tree().get_nodes_in_group(group):
		if is_instance_valid(c) and root.is_ancestor_of(c) and (c as Node3D).visible:
			n += 1
	return n


func _count(r) -> int:
	return r.get_tree().get_nodes_in_group(r.FX_POOL_GROUP).size() \
		+ r.get_tree().get_nodes_in_group(r.FX_FLAME_GROUP).size()


func _emitting(r) -> int:
	var n := 0
	for L in r._lights:
		if L.has("smoke") and is_instance_valid(L["smoke"]) and (L["smoke"] as GPUParticles3D).emitting:
			n += 1
	return n


func _tally(r) -> String:
	return "pools=%d flames=%d plumes=%d" % [_vis(r, r.FX_POOL_GROUP),
		_vis(r, r.FX_FLAME_GROUP), _emitting(r)]


func _check(what: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % what)
	else:
		_failed.append(what)
		print("  FAIL %s%s" % [what, ("  (%s)" % detail) if detail != "" else ""])


func _report() -> void:
	if _failed.is_empty():
		print("all good (0 checks failed)")
	else:
		print("%d checks failed:" % _failed.size())
		for f in _failed:
			print("  - %s" % f)
	get_tree().quit(0 if _failed.is_empty() else 1)
