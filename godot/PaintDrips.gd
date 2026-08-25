extends Control
## Magenta paint running out of the sprayed patches on the title wordmark.
##
## GRAVITY DOES NOT CARE ABOUT THE STENCIL. The patch is tilted a few degrees; the drips
## fall straight down from wherever its bottom edge happens to be, so they cut across the
## tilt instead of hanging square off it. That mismatch is most of what makes them read as
## wet paint rather than as part of the graphic.
##
## Everything is drawn in BLOCKS the size of one authored patch pixel, so the drips are
## pixelated by construction and match the stencil they run out of.

## Run lengths are a fraction of the PATCH HEIGHT, not a block count: the authored patch
## pixel lands around 3px on screen, so counting blocks produced a fringe rather than paint
## that ran. What sells it is one or two proper runners against a lot of short ones.
const RUN_MIN := 0.10
const RUN_MAX := 0.55
const RUNNER := 1.35        ## the one long runner per patch, as a fraction of the height
const BEAD_BULGE := 1.0     ## how many blocks wider the bead is than its run

var _block := 6.0
var _paint := Color(1, 0, 1)
var _drips: Array = []
var _t := 0.0

## `a`/`b` are the ends of the patch's bottom edge in this node's coordinates, already
## rotated — the caller owns the tilt, we only own the falling.
func setup(block: float, paint: Color, a: Vector2, b: Vector2, span: float, count: int,
		rng_seed: int) -> void:
	_block = maxf(3.0, block)
	_paint = paint
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	_drips.clear()
	for i in count:
		var t: float = (float(i) + rng.randf() * 0.8) / float(count)
		var at: Vector2 = a.lerp(b, clampf(t, 0.02, 0.98))
		var wide: int = 2 if rng.randf() < 0.30 else 1
		var run: float = span * (RUN_MIN + rng.randf() * (RUN_MAX - RUN_MIN))
		if i == count / 2:
			run = span * RUNNER * (0.8 + rng.randf() * 0.4)
		# alpha jitter is PRECOMPUTED per block: rolling it in _draw() would make the drip
		# crawl with static every frame instead of sitting there drying.
		var jitter: Array = []
		for k in int(run / _block) + 3:
			jitter.append(0.72 + rng.randf() * 0.28)
		var d := {
			"x": snappedf(at.x, _block),
			"y": snappedf(at.y, _block) - _block,   # start just inside the paint
			"w": wide,
			"run": run,
			"delay": rng.randf() * 0.9,
			"dur": 0.9 + rng.randf() * 1.7 + run / span * 0.6,
			"jitter": jitter,
			# a quarter of the runs shed a droplet that keeps going after the run stalls
			"drop": rng.randf() < 0.28,
			"drop_gap": span * (0.04 + rng.randf() * 0.10),
			"drop_fall": span * (0.10 + rng.randf() * 0.35),
		}
		_drips.append(d)
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	var live := false
	for d in _drips:
		if _t < float(d["delay"]) + float(d["dur"]) + 1.2:
			live = true
			break
	queue_redraw()
	if not live:
		set_process(false)   # the paint has dried; stop burning a frame on it

func _draw() -> void:
	for d in _drips:
		var p: float = clampf((_t - float(d["delay"])) / float(d["dur"]), 0.0, 1.0)
		if p <= 0.0:
			continue
		# ease-out: paint leaves the edge fast and slows as it runs out of itself
		var eased: float = 1.0 - pow(1.0 - p, 3.0)
		var len: float = float(d["run"]) * eased
		var w: float = float(d["w"]) * _block
		var x: float = float(d["x"])
		var y0: float = float(d["y"])
		var jitter: Array = d["jitter"]
		var n := int(len / _block)
		for k in n:
			var a: float = float(jitter[mini(k, jitter.size() - 1)])
			draw_rect(Rect2(x, y0 + float(k) * _block, w, _block),
				Color(_paint.r, _paint.g, _paint.b, a), true)
		# the bead: paint pools at the tip, which is why a drip is fatter at the bottom
		if n > 0:
			var bw: float = w + BEAD_BULGE * _block
			draw_rect(Rect2(x - BEAD_BULGE * _block * 0.5, y0 + float(n) * _block, bw, _block * 1.5),
				Color(_paint.r, _paint.g, _paint.b, 0.94), true)
		if not bool(d["drop"]):
			continue
		# the shed droplet, falling on its own clock once the run has all but stalled
		var dp: float = clampf((_t - float(d["delay"]) - float(d["dur"]) * 0.75) / 0.9, 0.0, 1.0)
		if dp <= 0.0:
			continue
		var dy: float = y0 + len + float(d["drop_gap"]) + float(d["drop_fall"]) * (dp * dp)
		draw_rect(Rect2(snappedf(x, _block), snappedf(dy, _block), _block, _block),
			Color(_paint.r, _paint.g, _paint.b, 0.90), true)
