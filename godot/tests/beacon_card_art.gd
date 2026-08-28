extends Node

## THE BEACON CARD'S RELATIONSHIP WITH ITS SPRITE, headless.
##
##   Godot --headless --path godot/ --quit-after 200 res://tests/beacon_card_art.tscn
##
## WHY IT EXISTS. A beacon that sits too high is not a crash and not a wrong number — it is a
## picture that looks slightly wrong from four parasangs away, which is the kind of thing that gets
## noticed once and then argued about from screenshots. It took a validated projection probe to
## establish that the card had been planted correctly the whole time and it was the TILE'S OWN
## PADDING lifting the art: Red Rock's massif ends five rows early inside its 16x24 box, and on a
## card a zone wide that is twenty-five cells of nothing under the mountain.
##
## Both halves of the fix are pure functions of an image, so they can be asked directly rather than
## measured off the screen. The fixtures are the shape a Qud tile actually has: a 16x24 box with the
## art inset, and colours that come from Qud's palette rather than a gradient.

var _failed: Array[String] = []

const RED_DARK := Color8(0xa4, 0x1c, 0x1c)
const RED_BRIGHT := Color8(0xd8, 0x39, 0x00)
const BLACK := Color8(0x0a, 0x0a, 0x0a)


func _ready() -> void:
	var lb = load("res://LocationBeacons.gd").new()
	add_child(lb)

	# A tile shaped like Red Rock's: 16x24, art in rows 5..18, nothing above or below it.
	var tex := _tile(Rect2i(2, 5, 12, 14))
	var ink: Rect2i = lb._ink_rect(tex)
	_check("the ink rect is the art, not the box", ink == Rect2i(2, 5, 12, 14), "got %s" % ink)

	var cropped: Texture2D = lb._crop(tex, ink)
	_check("cropping leaves only the art",
		cropped.get_width() == 12 and cropped.get_height() == 14,
		"got %dx%d" % [cropped.get_width(), cropped.get_height()])

	# THE MEASUREMENT THAT MATTERS. A card is sized so the WHOLE tile spans the regime's footprint,
	# so with a zone 80 cells across one tile pixel is 5 cells. The art starts 5 rows from the
	# bottom of a 24-row box, so a card built from the raw texture stands its picture 25 cells in
	# the air; built from the ink it stands on the ground.
	var cell := 80.0 / 16.0
	var lift_before := cell * float(tex.get_height() - ink.end.y)
	_check("the raw box would hang the art 25 cells up", is_equal_approx(lift_before, 25.0),
		"got %.1f" % lift_before)
	# The cropped card's own bottom edge IS the bottom of the art — nothing left to hang.
	_check("the cropped card has nothing under the art",
		lb._ink_rect(cropped).position == Vector2i.ZERO and
		lb._ink_rect(cropped).size == Vector2i(12, 14), "padding survived the crop")

	# ...and it must not shrink art that already fills its box, or every full-bleed tile would be
	# quietly resized. A tile with no padding crops to itself.
	var full := _tile(Rect2i(0, 0, 16, 24))
	_check("a full-bleed tile is left alone", lb._ink_rect(full) == Rect2i(0, 0, 16, 24),
		"got %s" % lb._ink_rect(full))

	# THE PLATE'S COLOUR IS ONE THE SPRITE CONTAINS. The fixture is deliberately mostly DARK red
	# with less of the bright: the commonest colour is the wrong answer (a name in the shading
	# colour disappears), the average is worse still (it is a colour in neither), and the brightest
	# of what the art is made of is the one that reads.
	var plate: Color = lb._plate_color(cropped, Color.MAGENTA)
	_check("the plate takes a colour out of the sprite",
		_same(plate, RED_BRIGHT), "got %s" % plate)
	_check("...and not the palette colour it was handed", not _same(plate, Color.MAGENTA),
		"fell through to the fallback")
	# A tile with nothing opaque in it has no colour to give, and the caller's own is the answer.
	_check("an empty tile falls back to the caller's colour",
		_same(lb._plate_color(_blank(), Color.MAGENTA), Color.MAGENTA), "invented a colour")

	print("\n%s (%d checks failed)" % ["all good" if _failed.is_empty() else "FAILED", _failed.size()])
	get_tree().quit(0 if _failed.is_empty() else 1)


## A 16x24 Qud tile with its art confined to `ink` — mostly the dark shading colour, with a bright
## ridge through it and a few black pixels, which is how these tiles are actually built.
func _tile(ink: Rect2i) -> Texture2D:
	var img := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(ink.position.y, ink.end.y):
		for x in range(ink.position.x, ink.end.x):
			var c := RED_DARK
			if y == ink.position.y + 2:
				c = RED_BRIGHT          # the lit ridge: present, but not the commonest colour
			elif (x + y) % 7 == 0:
				c = BLACK
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _blank() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  ok   %s" % name)
	else:
		_failed.append(name)
		print("  FAIL %s   %s" % [name, detail])
