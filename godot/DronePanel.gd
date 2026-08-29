extends PanelContainer

## THE DRONE'S SHOT LIST — the side panel half of drone-cam. Daniel: "The user can use a + button
## to add a scroll-point or hit the delete (trash) button on the list item. The user can drag the
## scroll point list items ... Add an invert scroll direction checkbox."
##
## THE ARITHMETIC IS NOT HERE. Every edit goes through Drone.gd's pure functions and comes back as
## a new array plus a playhead, which is what makes the awkward cases (deleting the shot under the
## playhead, reordering mid-drag) testable without a viewport. This file owns rows, drags and
## clicks; it owns no rules.

signal points_changed(points: Array)   # -> Main: the path the drone flies
signal scrub_changed(t: float)         # -> Main: where along it the drone is right now
signal capture_requested                # -> Main: "+" — take a shot from wherever the rig stands

const OPEN_KEY := "drone_open"
const INVERT_KEY := "drone_invert_scroll"
const POINTS_KEY := "drone_points"

const D = preload("res://Drone.gd")

var _title: Label
var _toggle: Button
var _add: Button
var _body: VBoxContainer
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _invert_box: CheckBox
var _expanded := false
var _one_to_one := false
var _points: Array = []
var _t := 0.0
var _invert := false
## The row being dragged, or -1. Held here rather than on the row so that a row destroyed by a
## rebuild mid-drag cannot take the drag state with it.
var _drag_from := -1
## WRITE-THROUGH TO Settings, off in tests. A headless run builds this panel for real and every
## edit persists — which put a fixture's three shots into the developer's own settings.json the
## first time this file was tested. A test that damages the machine it runs on is not a test, and
## the alternative (snapshot and restore around the run) leaks the moment a check fails early.
var persist := true


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.text = "Drone"
	_title.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "title"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	# "+" SITS IN THE HEADING, not at the foot of the list: it acts on the RIG (take a shot from
	# where the drone is now), not on any row, and a control that belongs to no row should not
	# live among them.
	_add = Button.new()
	_add.text = "+"
	_add.tooltip_text = "Add a shot here — the drone's position, its target and the zoom"
	_add.focus_mode = Control.FOCUS_NONE
	_add.pressed.connect(func() -> void: capture_requested.emit())
	head.add_child(_add)
	_toggle = Button.new()
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(func() -> void: set_expanded(not _expanded))
	head.add_child(_toggle)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	v.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_empty = Label.new()
	# The panel's own voice: an empty list is a thing you can fix with the button above it.
	_empty.text = "No shots yet — press + to take one."
	_empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_body.add_child(_empty)

	_invert_box = CheckBox.new()
	_invert_box.text = "Invert scroll"
	_invert_box.focus_mode = Control.FOCUS_NONE
	_invert_box.toggled.connect(_set_invert)
	_body.add_child(_invert_box)

	_expanded = bool(Settings.get_value(OPEN_KEY, false))
	_invert = bool(Settings.get_value(INVERT_KEY, false))
	_invert_box.button_pressed = _invert
	_points = _load_points()
	_refresh_toggle()
	_rebuild()
	_apply_height()


## Uniform panel entry — MainFrame feeds every side panel the same way.
func set_snapshot(_data: Dictionary) -> void:
	pass


## 1:1 is Qud's screen, and Qud has no drone. Same rule the Locations panel follows.
func set_one_to_one(on: bool) -> void:
	_one_to_one = on
	visible = not on


func set_expanded(on: bool) -> void:
	if on == _expanded:
		return
	_expanded = on
	if persist:
		Settings.set_value(OPEN_KEY, on)
		Settings.save()
	_refresh_toggle()
	_apply_height()


func expanded() -> bool:
	return _expanded


func points() -> Array:
	return _points


func scrub_t() -> float:
	return _t


func invert() -> bool:
	return _invert


## One wheel notch over the playfield while drone-cam is up. The panel owns this because the
## checkbox that reverses it does, and splitting "how far a notch goes" from "which way" is how
## the two end up disagreeing.
func scroll_by(notches: float) -> float:
	_t = D.scrub(_t, notches, _points.size(), _invert)
	scrub_changed.emit(_t)
	_paint_playhead()
	return _t


## Take a shot. Main hands us the live rig because Main is what knows where the drone is.
func add_point(drone: Vector3i, target: Vector3i, zoom: float) -> void:
	_points.append(D.make_point(drone, target, zoom, _points.size()))
	_commit()


func remove_point(i: int) -> void:
	var r := D.remove(_points, i, _t)
	_points = r["points"]
	_t = r["t"]
	_commit()
	scrub_changed.emit(_t)


func move_point(from_i: int, to_i: int) -> void:
	_points = D.reorder(_points, from_i, to_i)
	_commit()


func _set_invert(on: bool) -> void:
	_invert = on
	if persist:
		Settings.set_value(INVERT_KEY, on)
		Settings.save()


func _commit() -> void:
	_save_points()
	_rebuild()
	_apply_height()
	points_changed.emit(_points)


func _refresh_toggle() -> void:
	if _toggle == null:
		return
	_toggle.text = "▾" if _expanded else "▸"
	_toggle.tooltip_text = "Collapse the shot list" if _expanded else "Expand the shot list"


func _apply_height() -> void:
	if _body != null:
		_body.visible = _expanded
	if not _expanded:
		custom_minimum_size.y = 0
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return
	var line: float = float(UiFont.px(get_viewport(), "body")) * 1.9
	if _scroll != null:
		_scroll.visible = not _points.is_empty()
		_scroll.custom_minimum_size.y = minf(line * float(maxi(_points.size(), 1)), 200.0)
	custom_minimum_size.y = 0
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
		_rows.remove_child(c)
	for i in _points.size():
		_rows.add_child(_make_row(i))
	if _empty != null:
		_empty.visible = _points.is_empty()
	_paint_playhead()


func _make_row(i: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Shot%d" % i
	row.add_theme_constant_override("separation", 4)

	# THE WHOLE ROW IS THE HANDLE. Daniel: "The user can drag the scroll point list items." A
	# dedicated grip column would cost a fifth of a narrow panel's width to say what the row
	# already says by being draggable.
	var grip := Label.new()
	grip.name = "Grip"
	grip.text = "⠿"
	grip.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	row.add_child(grip)

	var name_l := Label.new()
	name_l.name = "Name"
	name_l.text = String(_points[i].get("name", "shot %d" % (i + 1)))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var bin := Button.new()
	bin.name = "Bin"
	bin.text = "🗑"
	bin.focus_mode = Control.FOCUS_NONE
	bin.tooltip_text = "Delete this shot"
	bin.pressed.connect(func() -> void: remove_point(i))
	row.add_child(bin)

	row.gui_input.connect(func(e: InputEvent) -> void: _row_input(i, e))
	return row


## Drag-reorder, by index rather than by node. A rebuild between press and release frees every row
## in the list, so a drag that remembered its Control would be holding a dead one by the time it
## was dropped.
func _row_input(i: int, e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag_from = i
		elif _drag_from >= 0:
			var to_i := _row_at(get_global_mouse_position())
			if to_i >= 0 and to_i != _drag_from:
				move_point(_drag_from, to_i)
			_drag_from = -1


## Which row is under a screen point, or -1. Asked of the live rects rather than computed from a
## row height, because the rows are font-sized and the panel is resizable.
func _row_at(p: Vector2) -> int:
	if _rows == null:
		return -1
	for i in _rows.get_child_count():
		var c := _rows.get_child(i) as Control
		if c != null and c.get_global_rect().has_point(p):
			return i
	return -1


## Which shot the playhead is on, lit in the list. WITHOUT THIS the glide is invisible from the
## panel: the camera moves and no row says which shot it is moving toward.
func _paint_playhead() -> void:
	if _rows == null:
		return
	var cur := int(roundf(_t))
	for i in _rows.get_child_count():
		var c := _rows.get_child(i)
		var l := c.get_node_or_null("Name") as Label
		if l != null:
			l.add_theme_color_override("font_color",
				QudPalette.TEXT if i == cur else Color(1, 1, 1, 0.55))


func _load_points() -> Array:
	var raw: Variant = Settings.get_value(POINTS_KEY, [])
	var out: Array = []
	if raw is Array:
		for e in raw:
			if e is Dictionary and e.has("drone") and e.has("target"):
				# SETTINGS ROUND-TRIP THROUGH JSON, which has no Vector3i — they come back as
				# arrays. Rebuilding them here keeps every other reader working in vectors.
				out.append({
					"name": String(e.get("name", "shot")),
					"drone": _vec(e["drone"]),
					"target": _vec(e["target"]),
					"zoom": float(e.get("zoom", 1.0)),
				})
	return out


func _save_points() -> void:
	if not persist:
		return
	var raw: Array = []
	for p in _points:
		raw.append({
			"name": String(p.get("name", "shot")),
			"drone": [p["drone"].x, p["drone"].y, p["drone"].z],
			"target": [p["target"].x, p["target"].y, p["target"].z],
			"zoom": float(p.get("zoom", 1.0)),
		})
	Settings.set_value(POINTS_KEY, raw)
	Settings.save()


static func _vec(v: Variant) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Array and v.size() >= 3:
		return Vector3i(int(v[0]), int(v[1]), int(v[2]))
	return Vector3i.ZERO
