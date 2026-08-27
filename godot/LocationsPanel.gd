extends PanelContainer

## LOCATIONS — the side column's navigation panel, under the message log.
##
## Daniel: "The location button opens a new panel on the right-hand side, under the message log. It
## has a toggle to expand/collapse. The location menu is a list of locations. If you enable the
## location (checkbox), it will show up on the game like a 'google maps' navigation beacon on the
## horizon."
##
## THE LIST IS QUD'S, not ours. Every row is a JOURNAL MAP NOTE — the entries Qud's own Journal
## screen files under "Locations" — read from the mod's journal.json. So a place appears here the
## moment the game learns about it, with Qud's wording and Qud's category, and nothing has to be
## kept in step by hand.
##
## THE CHECKBOX IS RAVES', though. It arms a BEACON, which is a camera affordance in a 3D world Qud
## does not have; Qud's own `tracked` flag on a map note is a different feature (it marks the entry
## in the journal) and is left alone rather than quietly reused for this. Ticks persist per GAME —
## note ids belong to a save, so one character's beacons must not light up in another's world.
##
## POLLED, because a location is DISCOVERED. The file only changes when the journal does, so the
## panel asks the mod to re-export it (the cheap journal-only command, not the full `export`) while
## it is open, and rebuilds when the file's mtime moves. A panel that only refreshed when something
## else happened to open a status screen would sit there missing the place you just walked into.

signal beacons_changed(targets: Array)   # -> Main's LocationBeacons: what to stand on the horizon
signal refresh_requested                 # -> the bridge's `journal` command

const REFRESH_S := 6.0        # how often to ask Qud to re-export the journal
const MAX_ROWS := 60          # a late-game journal is long; the list scrolls past this
const ROW_LIMIT_H := 260.0    # ...and the panel stops growing here
const SETTINGS_KEY := "location_beacons"
const OPEN_KEY := "locations_expanded"

## The beacon colours, cycled in tick order. Qud's own palette codes — a beacon is a light in Qud's
## world and has no business being a colour the world cannot contain.
const BEACON_CODES := ["C", "W", "M", "G", "O", "B"]

var _title: Label
var _toggle: Button
var _body: VBoxContainer
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _expanded := false        # the nav pin is what opens it; the column keeps its height until then
var _sorted := false          # the list has been ordered against a real player position
var _sig := ""                # what the last rebuild was built from — see _reload
var _one_to_one := false
var _mtime := 0
var _since := 0.0
var _entries: Array = []       # [{id, name, category, mx, my}] — the journal's Locations tab
var _on := {}                  # id -> true, the ticked rows (persisted per game)
var _game := ""
var _zone := {}
var _player := Vector2i(-1, -1)
## Set by MainFrame: (mx, my) -> {"para": float, "dir": String}. The distance/bearing shown beside a
## row is computed by the BEACON node, so the number in the list and the column on the horizon can
## never disagree about which way a place is.
var metrics_cb: Callable = Callable()

func _ready() -> void:
	_apply_panel_box()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.text = "Locations"
	_title.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "title"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
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
	# Said in the panel's own voice, not Qud's "No entries found.": this is a list you can act on,
	# and an empty one is a fact about the character, not a broken panel.
	_empty.text = "Nowhere noted yet."
	_empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_body.add_child(_empty)

	_expanded = bool(Settings.get_value(OPEN_KEY, false))
	_refresh_toggle()
	_apply_height()
	_reload(true)
	set_process(true)

## Uniform panel entry — MainFrame feeds every side panel the same way.
func set_snapshot(data: Dictionary) -> void:
	var gid := String(data.get("gameId", ""))
	if gid != "" and gid != _game:
		# A DIFFERENT SAVE IS A DIFFERENT WORLD. Note ids are per-game, so carrying the ticks over
		# would arm beacons pointing at places this character has never heard of — the same rule the
		# camera heading follows (Main._check_camera_game).
		_game = gid
		_on = _load_ticks()
		_rebuild()
	_zone = data.get("zone", {})
	var p: Dictionary = data.get("player", {})
	_player = Vector2i(int(p.get("x", -1)), int(p.get("y", -1)))
	_refresh_metrics()

## THE POLL RUNS WHILE COLLAPSED. The beacons are armed from this list, and they stand in the world
## whether or not the panel that armed them is open — a collapsed panel that stopped noticing new
## places would leave the list a character-hour out of date the moment you expanded it again.
func _process(dt: float) -> void:
	if _one_to_one or not visible:
		return
	_since += dt
	if _since < REFRESH_S:
		return
	_since = 0.0
	refresh_requested.emit()
	_reload()

## 1:1 is Qud's screen, and Qud has no locations panel — so this one is simply not there.
func set_one_to_one(on: bool) -> void:
	_one_to_one = on
	visible = not on
	_apply_panel_box()
	_emit()

func set_expanded(on: bool) -> void:
	if on == _expanded:
		return
	_expanded = on
	Settings.set_value(OPEN_KEY, on)
	Settings.save()
	_refresh_toggle()
	if on:
		_since = REFRESH_S      # ask for fresh data the moment it opens, not one tick later
	_apply_height()

## The nav-bar button: open the panel if it is shut, shut it if it is already open.
func toggle_panel() -> void:
	set_expanded(not _expanded)

func expanded() -> bool:
	return _expanded

## True while parity mode has taken the panel away — the nav button asks before trying to open it.
func parity_hidden() -> bool:
	return _one_to_one

func _refresh_toggle() -> void:
	if _toggle == null:
		return
	_toggle.text = "▾" if _expanded else "▸"
	_toggle.tooltip_text = "Collapse the locations list" if _expanded else "Expand the locations list"

func _apply_height() -> void:
	if _body != null:
		_body.visible = _expanded
	if not _expanded:
		custom_minimum_size.y = 0
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return
	var line: float = float(UiFont.px(get_viewport(), "body")) * 1.9
	var want: float = minf(line * float(_entries.size()), ROW_LIMIT_H)
	if _scroll != null:
		# An empty list reserves NOTHING. Reserving a row's worth left a blank band above "Nowhere
		# noted yet.", which reads as a list that failed to draw rather than one with no places in it.
		_scroll.visible = not _entries.is_empty()
		_scroll.custom_minimum_size.y = want
	custom_minimum_size.y = 0
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

# ── the journal file ───────────────────────────────────────────────────────────

func _reload(force := false) -> void:
	var path := InputModel.support_dir().path_join("journal.json")
	if not FileAccess.file_exists(path):
		return
	var mt := FileAccess.get_modified_time(path)
	if not force and mt == _mtime:
		return
	_mtime = mt
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		return
	var found: Array = []
	for tab in (raw as Dictionary).get("tabs", []):
		if String(tab.get("id", "")) != "Locations":
			continue
		for e in tab.get("entries", []):
			# A note with no map target cannot be aimed at, so it is not a location for this panel's
			# purposes even though the journal files it under Locations.
			if not (e.has("mx") and e.has("my")):
				continue
			var mx := int(e.get("mx", 0))
			var my := int(e.get("my", 0))
			# QUD'S OWN TEXT IS TWO LINES: the place, then the way there ("Bethesda Susa\n3
			# parasangs west of Joppa"). The first is the name a row and a beacon want; the second is
			# Qud already answering "which way", so it rides along as the row's tooltip rather than
			# being thrown away.
			var full := _plain(String(e.get("text", "")))
			var nl := full.find("\n")
			found.append({
				"id": _key(e, mx, my, full),
				"name": full.substr(0, nl) if nl > 0 else full,
				"note": full.substr(nl + 1).strip_edges() if nl > 0 else "",
				"category": String(e.get("category", "")),
				"mx": mx,
				"my": my,
			})
	if found.size() > MAX_ROWS:
		found.resize(MAX_ROWS)
	# THE EXPORT REWRITES THE FILE EVERY POLL, so the mtime always moves and it is the CONTENT that
	# has to decide. Rebuilding regardless would replace every checkbox in the list twice a minute —
	# and a checkbox replaced under the pointer eats the click that was landing on it.
	var sig := ""
	for e in found:
		sig += "%s|%d,%d;" % [e["id"], e["mx"], e["my"]]
	if sig == _sig:
		return
	_sig = sig
	_entries = found
	_sorted = false
	_rebuild()

## A STABLE KEY FOR A ROW — which the entry's own id would be, if it had one. Measured: every map
## note Qud files comes back with ID = "", so keying the ticks and the beacon nodes on it would give
## the whole list one shared identity (tick one, tick them all). The place and its words are what
## actually identifies a note, so that is the fallback.
func _key(e: Dictionary, mx: int, my: int, text: String) -> String:
	var id := String(e.get("id", ""))
	return id if id != "" else "%d,%d|%s" % [mx, my, text]

## Qud's {{colour|text}} markup, stripped to the words. The rows are checkbox labels, not the
## journal's own rendering, and a half-parsed brace in a checkbox reads as a bug.
func _plain(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "{" and i + 1 < s.length() and s[i + 1] == "{":
			var bar := s.find("|", i)
			if bar >= 0:
				i = bar + 1
				continue
		if s[i] == "}" and i + 1 < s.length() and s[i + 1] == "}":
			i += 2
			continue
		out += s[i]
		i += 1
	return out.strip_edges()

# ── the rows ───────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)      # off the tree NOW: queue_free only lands at end of frame, and
		c.queue_free()             # until then the old rows are still in get_children()
	_sort_entries()
	for e in _entries:
		_rows.add_child(_make_row(e))
	if _empty != null:
		_empty.visible = _entries.is_empty()
	_apply_height()
	_emit()

## Nearest first — a navigation list is read from the top, and the place you can reach is the one
## worth reading first. Unknown distance (no snapshot yet) keeps the file's order.
func _sort_entries() -> void:
	if not metrics_cb.is_valid() or _player.x < 0:
		return
	var keyed: Array = []
	for e in _entries:
		keyed.append([float(metrics_cb.call(int(e["mx"]), int(e["my"])).get("para", 0.0)), e])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for k in keyed:
		out.append(k[1])
	_entries = out

func _make_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var id := String(e["id"])
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = _on.has(id)
	cb.text = String(e["name"])
	cb.clip_text = true
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "body"))
	var note := String(e.get("note", ""))
	cb.tooltip_text = "%s\n%s\nTick to stand a beacon on the horizon" % [
		String(e.get("category", "Location")), note] if note != "" \
		else "%s — tick to stand a beacon on the horizon" % String(e.get("category", "Location"))
	cb.toggled.connect(func(on: bool) -> void: _set_tick(id, on))
	row.add_child(cb)
	var far := Label.new()
	far.name = "Far"
	far.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "body"))
	far.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	row.add_child(far)
	row.set_meta("mx", int(e["mx"]))
	row.set_meta("my", int(e["my"]))
	return row

## The distance/bearing column, refreshed off the live snapshot rather than rebuilt — the rows carry
## checkboxes, and rebuilding a checkbox under the pointer eats the click that was landing on it.
func _refresh_metrics() -> void:
	if _rows == null or not metrics_cb.is_valid():
		return
	# The list is ordered by distance, but distance is not known until the first snapshot lands —
	# so the ordering happens ONCE, here, rather than on every frame the player takes a step. A list
	# that re-sorted live would move the row you were reaching for.
	if not _sorted and _player.x >= 0 and not _entries.is_empty():
		_sorted = true
		_rebuild()
		return
	for row in _rows.get_children():
		var far: Label = row.get_node_or_null("Far")
		if far == null:
			continue
		var m: Dictionary = metrics_cb.call(int(row.get_meta("mx", 0)), int(row.get_meta("my", 0)))
		var para := float(m.get("para", 0.0))
		far.text = "%s %.1f" % [String(m.get("dir", "?")), para]
		far.tooltip_text = "%.1f parasangs %s" % [para, String(m.get("dir", ""))]

# ── the ticks ──────────────────────────────────────────────────────────────────

func _set_tick(id: String, on: bool) -> void:
	if on:
		_on[id] = true
	else:
		_on.erase(id)
	_save_ticks()
	_emit()

## What the beacons are aimed at, in TICK ORDER so a beacon keeps its colour as other rows come and
## go. Colour by position in the list would repaint every column whenever a nearer place appeared.
func _emit() -> void:
	var out: Array = []
	if not _one_to_one:
		# COLOUR BY TICK ORDER, not by row order. `_on` is a Dictionary and Godot keeps its insertion
		# order (and JSON preserves it across a save), so its keys ARE the order the player armed
		# them in. Numbering off `_entries` instead — which is sorted by distance — would repaint
		# every column the moment a nearer place was ticked, or the moment you walked past one.
		var order: Array = _on.keys()
		for e in _entries:
			var id := String(e["id"])
			if not _on.has(id):
				continue
			out.append({
				"id": id,
				"name": String(e["name"]),
				"mx": int(e["mx"]),
				"my": int(e["my"]),
				"color": QudPalette.of(BEACON_CODES[maxi(order.find(id), 0) % BEACON_CODES.size()]),
			})
	beacons_changed.emit(out)

func _load_ticks() -> Dictionary:
	var all = Settings.get_value(SETTINGS_KEY, {})
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var mine = all.get(_game, {})
	if typeof(mine) != TYPE_DICTIONARY:
		return {}
	return mine.duplicate()

func _save_ticks() -> void:
	if _game == "":
		return          # nothing to key it to; a tick with no game would leak into the next one
	var all = Settings.get_value(SETTINGS_KEY, {})
	if typeof(all) != TYPE_DICTIONARY:
		all = {}
	all[_game] = _on.duplicate()
	Settings.set_value(SETTINGS_KEY, all)
	Settings.save()

# ── chrome ─────────────────────────────────────────────────────────────────────

func _apply_panel_box() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = QudPalette.CHROME
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", sb)

## The column's reorder handle (MainFrame._make_reorderable) — the heading, as every other panel.
func drag_handle() -> Control:
	return _title
