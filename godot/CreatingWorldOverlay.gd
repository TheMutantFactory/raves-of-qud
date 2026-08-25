extends CanvasLayer

## CREATING WORLD (docs/new-game-plan.md slice 4): the staged progress screen between "the
## player confirmed the build" and "the first snapshot landed", plus the embark modal. Added to
## the ROOT (not the title scene) so it survives the title -> viewer scene switch, and freed by
## its own Space press after the modal. Main calls `game_live()` via the "creating_world" group
## on the first snapshot; until then the dot strip sweeps and the stage lines tick on a timer
## (our own functional wording — the real worldgen progress is not bridged).
##
## The QUOTE is read from the player's OWN install at runtime (Books.xml, leniently — the file
## is entity-hostile to strict parsers), exactly as Qud's loading screen draws from its own
## data. Nothing is stored or shipped; failure to parse simply omits the block.

const BG := Color8(0x04, 0x21, 0x20)
const GOLD := Color8(0xAC, 0xA3, 0x36)
const MUTED := Color8(0x61, 0x7C, 0x78)
const DIM := Color8(0x3A, 0x55, 0x53)
const SEL_GOLD := Color8(0xCF, 0xC0, 0x41)

var _live := false
var _t := 0.0
var _stage := 0
var _stage_labels: Array = []
var _dots: Array = []
var _modal: Control = null
var _root: Control = null

func _ready() -> void:
	layer = 127                     # above the CRT layer (100) and the HUD; under only the wish console (128)
	add_to_group("creating_world")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiFont.scaled_theme(get_viewport(), 1.0)   # the app's mono face for every child
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var vp := _root.get_viewport_rect().size
	var em := QudChrome.emblem()
	if em != null:
		var er := TextureRect.new()
		er.texture = em
		er.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		er.stretch_mode = TextureRect.STRETCH_SCALE
		er.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var eh := int(vp.y * 0.042)
		er.size = Vector2(eh * em.get_width() / float(em.get_height()), eh)
		er.position = Vector2(vp.x * 0.5 - er.size.x * 0.5, vp.y * 0.215)
		_root.add_child(er)
	var title := Label.new()
	title.text = "Creating World"
	title.add_theme_color_override("font_color", GOLD)
	title.theme_type_variation = "Big"
	# the Big variation carries a background StyleBox in the app theme — on a full-width
	# anchored label it painted a darker band across the whole screen behind the title
	title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.position.y = vp.y * 0.258
	_root.add_child(title)
	# the dotted progress strip: dots with square milestones, an arrowhead at the far end
	var y := vp.y * 0.42
	var x0 := vp.x * 0.175
	var x1 := vp.x * 0.825
	var n := 56
	for i in n:
		var d := ColorRect.new()
		var mile := (i % 14 == 12)
		var sz: float = (vp.y * 0.008) if mile else (vp.y * 0.004)
		d.size = Vector2(sz, sz)
		d.position = Vector2(x0 + (x1 - x0) * i / float(n - 1) - sz * 0.5, y - sz * 0.5)
		d.color = DIM
		_root.add_child(d)
		_dots.append(d)
	var arrow := Label.new()
	arrow.text = ">"
	arrow.add_theme_color_override("font_color", DIM)
	arrow.position = Vector2(x1 + vp.x * 0.008, y - vp.y * 0.012)
	_root.add_child(arrow)
	# stage lines (functional wording of ours; the last goes gold when the game is live)
	var sy := vp.y * 0.615
	for line in ["Generating the world...", "Placing you in it...", "Starting game!"]:
		var l := Label.new()
		l.text = line
		l.add_theme_color_override("font_color", DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.anchor_left = 0.0; l.anchor_right = 1.0
		l.position.y = sy
		l.visible = false
		_root.add_child(l)
		_stage_labels.append(l)
		sy += vp.y * 0.0215
	_deco(vp, 0.588)
	_deco(vp, 0.688)
	_add_quote(vp)

func _deco(vp: Vector2, fy: float) -> void:
	var ks: int = maxi(3, int(round(vp.y * 0.0046)))
	var dx: int = maxi(2, int(round(vp.x * 0.0047)))
	var dy: int = maxi(1, int(round(vp.y * 0.0037)))
	for off in [Vector2(0, -dy), Vector2(-dx, dy), Vector2(dx, dy)]:
		var k := ColorRect.new()
		k.color = MUTED
		k.position = Vector2(vp.x * 0.5 + off.x - ks * 0.5, vp.y * fy + off.y - ks * 0.5)
		k.size = Vector2(ks, ks)
		_root.add_child(k)

## A random short passage from the player's own Books.xml, markup stripped, drawn dim with its
## book title as attribution. Lenient by design; any failure just leaves the block out.
func _add_quote(vp: Vector2) -> void:
	var path := OS.get_environment("HOME").path_join(
		"Library/Application Support/Steam/steamapps/common/Caves of Qud/CoQ.app/Contents/Resources/Data/StreamingAssets/Base/Books.xml")
	if not FileAccess.file_exists(path):
		return   # non-standard install: the quote block simply stays out
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		return
	var re := RegEx.new()
	re.compile("(?s)<page[^>]*>(.*?)</page>")
	var pages := re.search_all(txt)
	if pages.is_empty():
		return
	var pick: RegExMatch = pages[randi() % pages.size()]
	var body := pick.get_string(1)
	# nearest preceding book title, for the attribution line
	var upto := txt.substr(0, pick.get_start(1))
	var tre := RegEx.new()
	tre.compile("<book[^>]*Title=\\\"([^\\\"]+)\\\"")
	var last_title := ""
	for m in tre.search_all(upto):
		last_title = m.get_string(1)
	# strip Qud markup + entities + collapse whitespace
	var mre := RegEx.new()
	mre.compile("\\{\\{[^|}]*\\|([^}]*)\\}\\}")
	body = mre.sub(body, "$1", true)
	var ere := RegEx.new()
	ere.compile("&[#a-zA-Z0-9]+;")
	body = ere.sub(body, " ", true)
	var wre := RegEx.new()
	wre.compile("\\s+")
	body = wre.sub(body.strip_edges(), " ", true)
	if body.length() < 60:
		return
	if body.length() > 200:
		var cut := body.find(" ", 180)
		body = body.substr(0, cut if cut > 0 else 200)
	var q := Label.new()
	q.text = "\"" + body + "\""
	if last_title != "":
		# attribution INSIDE the same label — a separately-positioned line collided with the
		# quote whenever it wrapped taller than the fixed offset guessed
		q.text += "\n\n-" + QudText.strip(last_title)
	q.add_theme_color_override("font_color", DIM)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.anchor_left = 0.33; q.anchor_right = 0.67
	q.position.y = vp.y * 0.725
	_root.add_child(q)

func _process(dt: float) -> void:
	_t += dt
	# indeterminate sweep along the strip until live; solid gold after
	for i in _dots.size():
		var d: ColorRect = _dots[i]
		if _live:
			d.color = GOLD
		else:
			var ph := fposmod(_t * 18.0 - i, float(_dots.size()))
			d.color = GOLD if ph < 6.0 else DIM
	# stages tick on time until live forces the last
	var want := 0
	if _live:
		want = 3
	elif _t > 6.0:
		want = 2
	elif _t > 2.0:
		want = 1
	else:
		want = 1
	for i in _stage_labels.size():
		_stage_labels[i].visible = i < want
	if _live and _stage_labels[2].visible:
		_stage_labels[2].add_theme_color_override("font_color", GOLD)

## Main calls this (group "creating_world") when the first snapshot lands.
func game_live() -> void:
	if _live:
		return
	_live = true
	_show_modal()

func _show_modal() -> void:
	var vp := _root.get_viewport_rect().size
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_modal)
	var w := vp.x * 0.24
	var h := vp.y * 0.092
	var box := ColorRect.new()
	box.color = Color8(0x0A, 0x2E, 0x2D)
	box.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.455)
	box.size = Vector2(w, h)
	_modal.add_child(box)
	for edge in [[0, 0, w, 2], [0, h - 2, w, 2], [0, 0, 2, h], [w - 2, 0, 2, h]]:
		var b := ColorRect.new()
		b.color = MUTED
		b.position = box.position + Vector2(edge[0], edge[1])
		b.size = Vector2(edge[2], edge[3])
		_modal.add_child(b)
	var msg := Label.new()
	msg.text = "You embark for the caves of Qud."
	msg.add_theme_color_override("font_color", Color8(0xC5, 0xCE, 0xC6))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.anchor_left = 0.0; msg.anchor_right = 1.0
	msg.position.y = box.position.y + h * 0.28
	_modal.add_child(msg)
	var pr := Label.new()
	pr.text = "> press [Space]"
	pr.add_theme_color_override("font_color", SEL_GOLD)
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.anchor_left = 0.0; pr.anchor_right = 1.0
	pr.position.y = box.position.y + h * 0.62
	_modal.add_child(pr)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") and _live:
		queue_free()               # the world is already rendering beneath
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel") and _t > 20.0 and not _live:
		# the escape hatch: never trap the player on a screen that cannot progress
		queue_free()
		get_viewport().set_input_as_handled()
