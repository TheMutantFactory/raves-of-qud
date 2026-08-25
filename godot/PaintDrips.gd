extends Control
## Magenta paint running out of the sprayed patches on the title wordmark, forever.
##
## GRAVITY DOES NOT CARE ABOUT THE STENCIL. The patch is tilted a few degrees; the drips
## fall straight down from wherever its bottom edge happens to be, so they cut across the
## tilt instead of hanging square off it. That mismatch is most of what makes them read as
## wet paint rather than as part of the graphic.
##
## Each slot RECYCLES: run, sit, fade, re-roll somewhere else along the edge. Left to
## accumulate, continuous drips turn the patch into a curtain within a minute — the fade is
## what keeps the count constant while the motion never stops. Slots are staggered into
## their cycles at birth so they never pulse in unison.
##
## Everything is drawn in BLOCKS, so the drips are pixelated by construction and match the
## stencil they run out of.

## Run lengths are a fraction of the PATCH HEIGHT, not a block count: the authored patch
## pixel lands around 3px on screen, so counting blocks produced a fringe rather than paint
## that ran. What sells it is one or two proper runners against a lot of short ones.
const RUN_MIN := 0.10
const RUN_MAX := 0.55
const RUNNER := 1.35        ## an occasional long runner, as a fraction of the height
const RUNNER_ODDS := 0.16
const BEAD_BULGE := 1.0     ## how many blocks wider the bead is than its run
const HOLD_MIN := 2.5       ## seconds the finished drip sits there before it starts to go
const HOLD_MAX := 6.0
const FADE_MIN := 1.5
const FADE_MAX := 3.0

var _block := 6.0
var _paint := Color(1, 0, 1)
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _span := 100.0
var _rng := RandomNumberGenerator.new()
var _drips: Array = []
var _t := 0.0

## `a`/`b` are the ends of the patch's bottom edge in this node's coordinates, already
## rotated — the caller owns the tilt, we only own the falling.
func setup(block: float, paint: Color, a: Vector2, b: Vector2, span: float, count: int,
		rng_seed: int) -> void:
	_block = maxf(3.0, block)
	_paint = paint
	_a = a
	_b = b
	_span = maxf(1.0, span)
	_rng.seed = rng_seed
	_drips.clear()
	for i in count:
		var d := {}
		_roll(d)
		# born mid-cycle, at a different point each, so the patch is never caught either
		# fully dripping or fully bare
		d["t0"] = -_rng.randf() * _cycle(d)
		_drips.append(d)
	set_process(true)
	queue_redraw()

func _cycle(d: Dictionary) -> float:
	return float(d["delay"]) + float(d["dur"]) + float(d["hold"]) + float(d["fade"])

## Everything random about one drip, re-rolled every time the slot comes around again.
func _roll(d: Dictionary) -> void:
	var at: Vector2 = _a.lerp(_b, _rng.randf_range(0.02, 0.98))
	var run: float = _span * (RUN_MIN + _rng.randf() * (RUN_MAX - RUN_MIN))
	if _rng.randf() < RUNNER_ODDS:
		run = _span * RUNNER * (0.8 + _rng.randf() * 0.4)
	# alpha jitter is PRECOMPUTED per block: rolling it in _draw() would make the drip crawl
	# with static every frame instead of sitting there drying
	var jitter: Array = []
	for k in int(run / _block) + 3:
		jitter.append(0.72 + _rng.randf() * 0.28)
	d["x"] = snappedf(at.x, _block)
	d["y"] = snappedf(at.y, _block) - _block   # start just inside the paint
	d["w"] = 2 if _rng.randf() < 0.30 else 1
	d["run"] = run
	d["jitter"] = jitter
	d["delay"] = _rng.randf() * 0.9
	d["dur"] = 0.9 + _rng.randf() * 1.7 + run / _span * 0.6
	d["hold"] = HOLD_MIN + _rng.randf() * (HOLD_MAX - HOLD_MIN)
	d["fade"] = FADE_MIN + _rng.randf() * (FADE_MAX - FADE_MIN)
	# roughly a quarter shed a droplet that keeps going after the run stalls
	d["drop"] = _rng.randf() < 0.28
	d["drop_gap"] = _span * (0.04 + _rng.randf() * 0.10)
	d["drop_fall"] = _span * (0.10 + _rng.randf() * 0.35)
	d["t0"] = _t

func _process(delta: float) -> void:
	_t += delta
	for d in _drips:
		if _t - float(d["t0"]) >= _cycle(d):
			_roll(d)
	queue_redraw()

func _draw() -> void:
	for d in _drips:
		var age: float = _t - float(d["t0"]) - float(d["delay"])
		if age <= 0.0:
			continue
		var dur: float = float(d["dur"])
		var p: float = clampf(age / dur, 0.0, 1.0)
		# ease-out: paint leaves the edge fast and slows as it runs out of itself
		var eased: float = 1.0 - pow(1.0 - p, 3.0)
		var len: float = float(d["run"]) * eased
		# the slot dries and lets go, so the next drip has somewhere to be
		var dry: float = age - dur - float(d["hold"])
		var alpha: float = 1.0 if dry <= 0.0 else clampf(1.0 - dry / float(d["fade"]), 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var w: float = float(d["w"]) * _block
		var x: float = float(d["x"])
		var y0: float = float(d["y"])
		var jitter: Array = d["jitter"]
		var n := int(len / _block)
		for k in n:
			var a: float = float(jitter[mini(k, jitter.size() - 1)]) * alpha
			draw_rect(Rect2(x, y0 + float(k) * _block, w, _block),
				Color(_paint.r, _paint.g, _paint.b, a), true)
		# the bead: paint pools at the tip, which is why a drip is fatter at the bottom
		if n > 0:
			var bw: float = w + BEAD_BULGE * _block
			draw_rect(Rect2(x - BEAD_BULGE * _block * 0.5, y0 + float(n) * _block, bw, _block * 1.5),
				Color(_paint.r, _paint.g, _paint.b, 0.94 * alpha), true)
		if not bool(d["drop"]):
			continue
		# the shed droplet, falling on its own clock once the run has all but stalled
		var dp: float = clampf((age - dur * 0.75) / 0.9, 0.0, 1.0)
		if dp <= 0.0:
			continue
		var dy: float = y0 + len + float(d["drop_gap"]) + float(d["drop_fall"]) * (dp * dp)
		draw_rect(Rect2(snappedf(x, _block), snappedf(dy, _block), _block, _block),
			Color(_paint.r, _paint.g, _paint.b, 0.90 * alpha), true)
