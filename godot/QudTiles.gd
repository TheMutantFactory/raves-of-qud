extends RefCounted

## Shared Qud tile recolouring + colour resolution, so views don't each re-inline it. Exported tiles are
## GRAYSCALE MASKS; recolour per pixel via main.lerp(detail, luminance), mirroring ZoneRenderer._recolor_rgb.
## Colours resolve from an object's fgHex/tilecolor/color (+ the snapshot palette, else the COLORS
## fallback). Create one per view (`load("res://QudTiles.gd").new()`); the caches are per-instance.
##
## (NearbyObjects still inlines the same logic; it can migrate onto this later.)

# Fallback colour table (mirrors ZoneRenderer.COLORS) for when the palette lacks a code.
const COLORS := {
	"r": Color(0.60, 0.20, 0.15), "R": Color(1.00, 0.30, 0.30),
	"g": Color(0.00, 0.50, 0.00), "G": Color(0.20, 0.90, 0.20),
	"b": Color(0.00, 0.00, 0.60), "B": Color(0.25, 0.45, 1.00),
	"c": Color(0.00, 0.55, 0.55), "C": Color(0.40, 1.00, 1.00),
	"m": Color(0.55, 0.00, 0.55), "M": Color(1.00, 0.40, 1.00),
	"w": Color(0.60, 0.40, 0.10), "W": Color(1.00, 0.82, 0.00),
	"o": Color(0.70, 0.35, 0.00), "O": Color(1.00, 0.55, 0.00),
	"y": Color(0.70, 0.70, 0.70), "Y": Color(1.00, 1.00, 1.00),
	"k": Color(0.10, 0.10, 0.10), "K": Color(0.10, 0.10, 0.10),
}

var tiles_dir := ""
var palette := {}
var _mask_cache := {}   # fname -> Image (raw grayscale mask)
var _tex_cache := {}    # "fname|main|detail" -> ImageTexture (recoloured)
var _img_cache := {}    # ...and the same recolour as an Image, for callers that composite
const IMG_CACHE_MAX := 512   # tiles are small; 512 of them is a few MB and covers a busy zone

## Recoloured icon for a serialized object dict, honouring the global perceived/full toggle. When NOT
## full and the object carries a perceived override (tileP/colorP/detailP — present only for unidentified
## items), use that (Qud's "unknown" icon); otherwise the full/known tile.
func texture_for(obj: Dictionary, full: bool) -> Texture2D:
	if not full and obj.has("tileP"):
		return texture(String(obj.get("tileP", "")),
			color_of(String(obj.get("colorP", ""))), color_of(String(obj.get("detailP", ""))))
	return texture(String(obj.get("tile", "")), main_color(obj), detail_color(obj))

## Glyph fallback for a serialized object dict, matching texture_for's perceived/full choice.
func glyph_for(obj: Dictionary, full: bool) -> String:
	if not full and obj.has("glyphP"):
		return String(obj.get("glyphP", ""))
	return String(obj.get("glyph", ""))

# ══ FRAME-DRIVEN MATERIALS ══════════════════════════════════════════════════════════════
# An object carrying AnimatedMaterialFire has no fixed detail colour: the part overrides it on
# every render from (XRLCore.CurrentFrame + FrameOffset) % 60. The export's `dt` is therefore one
# arbitrary frame, and the mod now ships `anim` naming the part instead of pretending otherwise.
#
# Transcribed from ConsoleLib's own branch table, in its own order — gold owns TWO of the four
# quarters, which is why an unsuspecting sample came up gold half the time:
#     n < 15 -> &R    n < 30 -> &W    n >= 45 -> &W    else -> &r
const ANIM_PERIOD := 60
## Qud runs this at one cycle per 60 render frames; at 60fps that is 1s round, 250ms a step.
const ANIM_FRAME_MS := 1000.0 / 60.0
## The phase 1:1 mode pins to. Qud's own paper doll freezes ONE arbitrary frame per screen open
## (EquipmentLine.setData samples RenderForUI once and keeps it), so there is no phase that
## matches it -- but the two gold quarters make &W the single likeliest thing Qud is showing:
## pinning here agrees with Qud 50% of the time against 37.5% for a fresh sample each open.
const ANIM_PIN_PHASE := 20

## Detail colour CODE for a frame-driven material at `phase`, or "" when the kind is one we do
## not model (the caller then keeps whatever the export sampled, which is what we did before).
func anim_code(kind: String, phase: int) -> String:
	if kind != "fire":
		return ""
	var n := phase % ANIM_PERIOD
	if n < 15:
		return "R"
	if n < 30:
		return "W"
	if n >= 45:
		return "W"
	return "r"

## Phase for right now — pinned in 1:1 mode, running off the wall clock otherwise. Deliberately
## NOT the frame counter: Godot's frame rate is not Qud's, and the cycle is defined in Qud frames.
func anim_phase() -> int:
	if Settings.clone_of_qud():
		return ANIM_PIN_PHASE
	return int(Time.get_ticks_msec() / ANIM_FRAME_MS) % ANIM_PERIOD

## Which of the four quarters `phase` falls in. Redrawing is worth doing when this changes and
## pointless otherwise — four repaints a second, not one per frame.
func anim_step(phase: int) -> int:
	return (phase % ANIM_PERIOD) / 15

## Recoloured tile texture for a tile path + main/detail colours, or null if there's no tile/mask.
## The recoloured tile as an IMAGE, cached. Split out because the minimap composites two thousand
## tiles a turn and needs PIXELS, not a GPU handle: it was calling get_image() on each returned
## texture — a readback per cell — and the panel cost 545ms a turn, five times the whole live 3D
## render. Images are CPU-side and free to hand out.
## WHICH OBJECT'S COLOURS THIS CELL IS PAINTED IN — itself, or its remembered repaint.
##
## Its own function because it is the whole of the decision, and because a test that stubs QudTiles
## (which every minimap check does — there are no tile files under a headless run) never reaches
## image_for at all: deleting the repaint from there broke nothing that was being checked.
##
## REMEMBERED IS A REPAINT, NOT A DIM, and the recipe is the world's rather than a second one
## written here — see ZoneRenderer.ghost_obj.
func paint_obj(obj: Dictionary, ghost: bool) -> Dictionary:
	return ZoneRenderer.ghost_obj(obj) if ghost else obj


## The two colours a remembered tile is recoloured with, pulled toward the field. Its own function
## so it can be asked directly: every minimap check stubs QudTiles, so a test that renders cannot
## reach the arithmetic, and the blend could be dropped from image_for with the suite green.
func ghost_colors(o: Dictionary, field_blend: float) -> Array:
	var f := field_color()
	return [main_color(o).lerp(f, field_blend), detail_color(o).lerp(f, field_blend)]


## QUD'S FIELD COLOUR — the 'k' every cell is painted with before anything is drawn on it.
func field_color() -> Color:
	return color_of("k", Color(0.06, 0.23, 0.23))


func image_for(obj: Dictionary, full: bool, ghost := false, field_blend := 0.0) -> Image:
	var o: Dictionary = paint_obj(obj, ghost)
	# TOWARD THE FIELD, BY COLOUR RATHER THAN BY PIXEL. A remembered cell in Qud is overwhelmingly
	# field with a sparse glyph on it — a histogram of a remembered-only region of Qud's screen is
	# FLAT field, its glyphs too sparse to reach the top five colours. Raves recolours the whole
	# tile, so its remembered cell is a dense picture where Qud's is a nearly-flat square.
	#
	# The ghost is a FLAT two-colour recolour (main K, detail k), so pulling those two colours
	# toward the field pulls the whole tile toward it — no per-pixel pass, and image() already
	# caches by (tile, main, detail), so each blended variant is built once like any other.
	if ghost and field_blend > 0.0:
		var gc := ghost_colors(o, field_blend)
		return image(String(o.get("tile", "")), gc[0], gc[1])
	if not full and o.has("tileP"):
		return image(String(o.get("tileP", "")),
			color_of(String(o.get("colorP", ""))) if not ghost else main_color(o),
			color_of(String(o.get("detailP", ""))) if not ghost else detail_color(o))
	return image(String(o.get("tile", "")), main_color(o), detail_color(o))




func image(tile: String, main: Color, detail: Color) -> Image:
	if tile == "":
		return null
	var fname := tile.replace("/", "_").replace("\\", "_").replace(":", "_")
	var key := "%s|%s|%s" % [fname, main.to_html(), detail.to_html()]
	if _img_cache.has(key):
		return _img_cache[key]
	var custom := _custom_path(fname)
	if custom != "":
		var cimg := _load_image(custom)
		if cimg != null:
			_bound(_img_cache)
			_img_cache[key] = cimg
			return cimg
	var mask := _mask(fname)
	if mask == null:
		return null
	var w := mask.get_width()
	var h := mask.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var pix := mask.get_pixel(x, y)
			if pix.a < 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var lum := (pix.r + pix.g + pix.b) / 3.0
				var c := main.lerp(detail, lum)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, pix.a))
	_bound(_img_cache)
	_img_cache[key] = img
	return img


## BOUNDED BY EVICTION, NOT BY WIPE. The texture cache clears itself wholesale when it tips over,
## so a zone with more distinct tile-and-colour pairs than the bound rebuilds EVERYTHING each time
## it does — worst exactly when the zone is busiest. Dropping the oldest quarter keeps the common
## tiles resident.
static func _bound(cache: Dictionary) -> void:
	if cache.size() <= IMG_CACHE_MAX:
		return
	var keys := cache.keys()
	for i in int(IMG_CACHE_MAX / 4):
		cache.erase(keys[i])


func texture(tile: String, main: Color, detail: Color) -> Texture2D:
	if tile == "":
		return null
	var fname := tile.replace("/", "_").replace("\\", "_").replace(":", "_")
	var key := "%s|%s|%s" % [fname, main.to_html(), detail.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	# CUSTOM ART RENDERS AS-AUTHORED, here too. This loader feeds the Nearby-objects icons, the
	# message-log pictographs and every other side-panel tile, and it never knew tiles_custom
	# existed — so the playfield showed Daniel's edit while the panels showed stock, which reads as
	# "my change reverted" from one glance at the panel. Same contract as ZoneRenderer's
	# _colored_tex_rgb: finished pixels, no recolour lerp, mtime in the key so edits invalidate.
	var custom := _custom_path(fname)
	if custom != "":
		var ckey := "%s|custom|%d" % [fname, FileAccess.get_modified_time(custom)]
		if _tex_cache.has(ckey):
			return _tex_cache[ckey]
		var cimg := _load_image(custom)
		if cimg != null:
			var ctex := ImageTexture.create_from_image(cimg)
			if _tex_cache.size() > 96:
				_tex_cache.clear()
			_tex_cache[ckey] = ctex
			return ctex
	var mask := _mask(fname)
	if mask == null:
		return null
	var w := mask.get_width()
	var h := mask.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var pix := mask.get_pixel(x, y)
			if pix.a < 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var lum := (pix.r + pix.g + pix.b) / 3.0
				var c := main.lerp(detail, lum)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, pix.a))
	var tex := ImageTexture.create_from_image(img)
	if _tex_cache.size() > 96:
		_tex_cache.clear()   # bound GPU memory: painted colours shift with lighting, so keys accumulate
	_tex_cache[key] = tex
	return tex

## The tiles_custom counterpart of an exported tile name, or "" when none exists.
func _custom_path(fname: String) -> String:
	if tiles_dir == "":
		return ""
	var p := tiles_dir.get_base_dir().path_join("tiles_custom").path_join(fname)
	return p if FileAccess.file_exists(p) else ""

func _load_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:   # exported tiles are PNG despite the .bmp name
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func _mask(fname: String) -> Image:
	if _mask_cache.has(fname):
		return _mask_cache[fname]
	if tiles_dir == "":
		return null
	var img := _load_image(tiles_dir.path_join(fname))
	if img == null:
		return null
	_mask_cache[fname] = img
	return img

## Main (foreground) colour of a serialized object/tile dict. `fallback` is used when the object carries
## no resolvable colour (the minimap passes its background so colourless cells recede; tiles use white).
func main_color(obj: Dictionary, fallback := Color.WHITE) -> Color:
	var hex := String(obj.get("fgHex", ""))
	if hex != "":
		return Color(hex)
	# Qud's tiles rule with the custom-render exception: a COMPOUND color string (second '&',
	# e.g. a liquid's '&Y^y&b') overrides the static tilecolor — see ZoneRenderer._pick_color_string.
	var full := String(obj.get("color", ""))
	var c := String(obj.get("tilecolor", ""))
	if full.count("&") >= 2 or c == "":
		c = full
	return color_of(c, fallback)

## Detail (secondary) colour of a serialized object/tile dict. Empty DetailColor is NOT
## white: Qud draws the detail-mask pixels in the FG colour then (measured on painted-ground
## flowers). Mirrors ZoneRenderer._obj_detail — keep the copies in sync.
func detail_color(obj: Dictionary, fallback := Color.WHITE) -> Color:
	var hex := String(obj.get("detailHex", ""))
	if hex != "":
		return Color(hex)
	var d := String(obj.get("detail", "")).strip_edges()
	if d == "":
		return main_color(obj, fallback)
	return color_of(d, fallback)

func color_of(code: String, fallback := Color.WHITE) -> Color:
	var ch := _fg_letter(code)
	if ch == "":
		return fallback
	if palette.has(ch):
		return Color(String(palette[ch]))
	return COLORS.get(ch, fallback)

## Foreground letter of a Qud colour code: drop the ^background half and the &, take the last char.
func _fg_letter(code: String) -> String:
	# QUD'S OWN RULE (RenderEvent.GetForegroundColor): the char after the LAST '&' anywhere in
	# the string — '^' sets the background and does NOT stop the search. A liquid's custom
	# render writes compounds like '&Y^y&b': Qud draws that fg 'b' (the blue puddle), and the
	# old first-caret truncation read 'Y' instead. A bare letter code stays itself.
	var c := code.strip_edges()
	var amp := c.rfind("&")
	if amp >= 0:
		return c.substr(amp + 1, 1) if amp + 1 < c.length() else ""
	var caret := c.find("^")
	if caret >= 0:
		c = c.substr(0, caret)
	if c.is_empty():
		return ""
	return c.substr(c.length() - 1, 1)
