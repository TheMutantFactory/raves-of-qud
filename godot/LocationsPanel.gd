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
## NAME PLATES ON OR OFF — the signpost in this panel's heading. Separate from the beacons
## themselves on purpose: which places stand on the horizon is the row checkboxes' business, and
## this only decides whether they are LABELLED. Daniel: "it toggles the visibility of name of
## locations. The sprites for the locations still show. That's controlled by the location list item
## checkbox."
signal plates_changed(on: bool)
signal refresh_requested                 # -> the bridge's `journal` command
signal lost_changed(lost: bool)          # -> MainFrame: dress (and disable) the nav pin

const REFRESH_S := 6.0        # how often to ask Qud to re-export the journal
const MAX_ROWS := 60          # a late-game journal is long; the list scrolls past this
const ROW_LIMIT_H := 260.0    # ...and the panel stops growing here
const SETTINGS_KEY := "location_beacons"
const OPEN_KEY := "locations_expanded"
const CAT_KEY := "locations_categories"   # which category trees are open, by name
## The category Raves files a place under when QUD has no note for it — see the grouping in _rebuild.
const VISITED_CAT := "Visited"
## Qud's own gold, for the category headers: they are furniture, not entries, and the rows below
## them are the things you can act on.
const SEL_GOLD := Color8(0xcf, 0xc0, 0x41)
const ARMED_KEY := "locations_beacons_on"
const PLATES_KEY := "locations_plates_on"

## The beacon colours, cycled in tick order. Qud's own palette codes — a beacon is a light in Qud's
## world and has no business being a colour the world cannot contain.
const BEACON_CODES := ["C", "W", "M", "G", "O", "B"]

var _title: Label
var _toggle: Button
var _body: VBoxContainer
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _expanded := false        # the panel's own ▾/▸ toggle; the column keeps its height until then
## THE MASTER SWITCH, which is what the nav pin is. Daniel: "Clicking the location button toggles
## the beacons on and off. Clicking the panel toggles the expand/collapse." Two different questions
## — WHICH places are marked (the checkboxes) and WHETHER any of them are showing right now — and
## the pin answers the second, so a player who wants a clear view for one fight does not have to
## untick four rows and remember to tick them back.
var _armed := true
var _plates_on := true
var _signpost: Button
## LOST is QUD'S state, not a mode of this panel: XRL.World.Effects.Lost, shipped in the snapshot.
## Daniel: "When you're lost, the map button should be turned off and disabled. The locations tab
## stays collapsed with a lock symbol. When the player becomes unlost, the locations reverts to the
## previous state." So the lock SUSPENDS the panel rather than changing it — nothing is persisted
## while it holds, and both switches come back exactly as they were.
var _lost := false
var _pre_expanded := false
var _sorted := false          # the list has been ordered against a real player position
var _row_count := 0           # headers + rows actually built, which is what the panel sizes to
var _sig := ""                # what the last rebuild was built from — see _reload
var _one_to_one := false
var _mtime := 0
var _since := 0.0
var _journal: Array = []       # [{id, name, category, mx, my}] — the journal's Locations tab
## PLACES YOU HAVE BEEN, which is not the same list and never was. Daniel, standing in Red Rock:
## "I'm at Red Rock, but for some reason, It's not discovered, and I can't add it as a beacon. Same
## with Joppa. I'd like to be able to return to Joppa by following the beacon."
##
## Qud's journal files a map note when the game TELLS you about somewhere — gossip, a water ritual,
## a quest. Walking into a place is not one of those, so Red Rock and Joppa can be homes you have
## slept in and still not be in the journal. That is Qud being consistent about what a journal is;
## it is no use at all to someone who wants to walk back.
##
## So the panel shows both lists. The travel log is QUD'S OWN — ZoneManager.VisitedTime, exported as
## places.json — not a record Raves keeps as you walk: a log that only started when this feature did
## would have been empty of every place Daniel had already been, which is the entire request.
## A beacon does not care which list a place came from.
var _visited: Array = []       # [{name, mx, my, tile, color, detail}] — places.json
var _pmtime := 0
## A visited row shows the world-map sprite Qud draws for that place — the row IS the place, and a
## line of text is a poorer thing to recognise than the pictograph you saw on the map.
var _tiles: RefCounted         # QudTiles; built in _ready
var _entries: Array = []       # the two, merged and deduped by parasang
var _on := {}                  # id -> true, the ticked rows (persisted per game)
var _game := ""
var _zone := {}
var _player := Vector2i(-1, -1)
## Set by MainFrame: (mx, my) -> {"para": float, "dir": String}. The distance/bearing shown beside a
## row is computed by the BEACON node, so the number in the list and the column on the horizon can
## never disagree about which way a place is.
var metrics_cb: Callable = Callable()

func _ready() -> void:
	_tiles = load("res://QudTiles.gd").new()
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
	# The signpost sits between the heading and the expander — "to the right of Locations" — because
	# it belongs to the LIST, not to the panel's own open/shut state.
	_signpost = Button.new()
	_signpost.flat = true
	_signpost.focus_mode = Control.FOCUS_NONE
	_signpost.tooltip_text = "Show location names on the horizon"
	_signpost.pressed.connect(_toggle_plates)
	head.add_child(_signpost)
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
	_armed = bool(Settings.get_value(ARMED_KEY, true))
	_plates_on = bool(Settings.get_value(PLATES_KEY, true))
	_refresh_signpost()
	_refresh_toggle()
	_refresh_title()
	_apply_height()
	_reload(true)
	_reload_places(true)
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
		_reload_places(true)
	_zone = data.get("zone", {})
	var p: Dictionary = data.get("player", {})
	_player = Vector2i(int(p.get("x", -1)), int(p.get("y", -1)))
	_set_lost(bool(p.get("lost", false)))
	if _tiles != null:
		_tiles.tiles_dir = String(data.get("tilesDir", _tiles.tiles_dir))
		_tiles.palette = data.get("palette", _tiles.palette)
	_refresh_metrics()

## THE POLL RUNS WHILE COLLAPSED. The beacons are armed from this list, and they stand in the world
## whether or not the panel that armed them is open — a collapsed panel that stopped noticing new
## places would leave the list a character-hour out of date the moment you expanded it again.
func _process(dt: float) -> void:
	if _lost or _one_to_one or not visible:
		return
	_since += dt
	if _since < REFRESH_S:
		return
	_since = 0.0
	refresh_requested.emit()
	_reload()
	_reload_places()

## 1:1 is Qud's screen, and Qud has no locations panel — so this one is simply not there.
func set_one_to_one(on: bool) -> void:
	_one_to_one = on
	visible = not on
	_apply_panel_box()
	_emit()

func set_expanded(on: bool) -> void:
	if _lost or on == _expanded:
		return
	_expanded = on
	Settings.set_value(OPEN_KEY, on)
	Settings.save()
	_refresh_toggle()
	if on:
		_since = REFRESH_S      # ask for fresh data the moment it opens, not one tick later
	_apply_height()

## Qud says the player is (or is no longer) lost. SUSPEND, don't overwrite: the collapse is not a
## choice the player made, so it is not written to Settings and the previous state is what comes back.
func _set_lost(on: bool) -> void:
	if on == _lost:
		return
	_lost = on
	if on:
		_pre_expanded = _expanded
		_expanded = false
	else:
		_expanded = _pre_expanded
	_refresh_toggle()
	_refresh_title()
	_apply_height()
	_emit()
	lost_changed.emit(on)

func is_lost() -> bool:
	return _lost

## The nav pin: arm or disarm every beacon at once. Returns the new state so the caller can dress
## its icon and say which way it went.
func toggle_beacons() -> bool:
	if _lost:
		return _armed          # the pin is disabled while lost; nothing to flip and nothing to save
	_armed = not _armed
	Settings.set_value(ARMED_KEY, _armed)
	Settings.save()
	_refresh_title()
	_emit()
	return _armed

## Say the beacons again. THE FIRST EMIT IS LOST: this panel is built with the side column, which is
## long before the Holodeck exists, so the beacons_changed that follows the first load reaches a
## MainFrame whose _holo is still null and goes nowhere. Nothing re-emitted afterwards either — the
## poll only rebuilds when the journal file actually changes — so a character whose beacons were
## already ticked came back from a launch with none of them showing until something was toggled.
func refresh_beacons() -> void:
	_emit()

func beacons_on() -> bool:
	return _armed

## How many places are ticked — the pin's tooltip says so, because arming an empty list looks
## exactly like a broken button.
func armed_count() -> int:
	var n := 0
	for e in _entries:
		if _on.has(String(e["id"])):
			n += 1
	return n

func expanded() -> bool:
	return _expanded

## True while parity mode has taken the panel away — the nav button asks before trying to open it.
func parity_hidden() -> bool:
	return _one_to_one

## The heading carries the master state, because the pin that flips it is across the window and the
## checkboxes stay ticked either way — without this, disarmed beacons read as beacons that broke.
func _refresh_title() -> void:
	if _title == null:
		return
	if _lost:
		# THE HEADING SAYS WHY. A panel that just went empty and stopped opening reads as broken;
		# one that says "lost" is the game speaking, and the player already knows what it means.
		_title.text = "Locations 🔒 lost"
		_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		return
	_title.text = "Locations" if _armed else "Locations (beacons off)"
	_title.add_theme_color_override("font_color",
		QudPalette.TEXT if _armed else Color(1, 1, 1, 0.45))

func _refresh_toggle() -> void:
	if _toggle == null:
		return
	_toggle.disabled = _lost
	if _lost:
		_toggle.text = "🔒"
		_toggle.tooltip_text = "You are lost — Qud does not know where you are, so neither does this"
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
	var want: float = minf(line * float(maxi(_row_count, _entries.size())), ROW_LIMIT_H)
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
			# The place's own sprite, when the mod could find one for that parasang — the beacon is
			# drawn from it, so a location you have only heard of still looks like itself.
			var art := {}
			if String(e.get("tile", "")) != "":
				art = {"tile": String(e.get("tile", "")), "color": String(e.get("color", "")),
					"tilecolor": String(e.get("tilecolor", "")), "detail": String(e.get("detail", ""))}
			found.append({
				"id": _key(e, mx, my, full),
				"art": art,
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
	_journal = found
	_merge()

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

## One list out of two. The journal wins a tie: it carries Qud's own wording and its category, and a
## place you have BOTH been told about and stood in should read as the game describes it.
func _merge() -> void:
	var out: Array = _journal.duplicate()
	var taken := {}
	for e in out:
		taken["%d,%d" % [int(e["mx"]), int(e["my"])]] = true
	for v in _visited:
		var nm := String(v["name"])
		var k := "%d,%d" % [int(v["mx"]), int(v["my"])]
		if taken.has(k):
			continue
		taken[k] = true
		out.append({
			"id": "v:" + k,               # keyed on the PARASANG, which is what a beacon points at
			"name": String(nm),
			"note": "somewhere you have been",
			"category": VISITED_CAT,
			"mx": int(v["mx"]), "my": int(v["my"]),
			"art": v,
		})
	if out.size() > MAX_ROWS:
		out.resize(MAX_ROWS)
	_entries = out
	_sorted = false
	_rebuild()

## Qud's travel log, from places.json. Same shape as the journal read below it: the file only moves
## when the export runs, and the export runs because this panel asked.
func _reload_places(force := false) -> void:
	var path := InputModel.support_dir().path_join("places.json")
	if not FileAccess.file_exists(path):
		return
	var mt := FileAccess.get_modified_time(path)
	if not force and mt == _pmtime:
		return
	_pmtime = mt
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		return
	var found: Array = []
	for pl in (raw as Dictionary).get("places", []):
		var nm := _plain(String(pl.get("name", "")))
		if nm == "":
			continue
		found.append({"name": nm, "mx": int(pl.get("mx", 0)), "my": int(pl.get("my", 0)),
			"tile": String(pl.get("tile", "")), "color": String(pl.get("color", "")),
			"tilecolor": String(pl.get("tilecolor", "")), "detail": String(pl.get("detail", ""))})
	_visited = found
	_merge()

# ── the rows ───────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)      # off the tree NOW: queue_free only lands at end of frame, and
		c.queue_free()             # until then the old rows are still in get_children()
	_sort_entries()
	# GROUPED THE WAY QUD GROUPS THEM. Its Locations tab sets UsesCategories and SortCategoriesAZ,
	# and every map note carries the Category the game filed it under — Settlements, Ruins,
	# Oddities. Daniel: "add category trees. Use the same categories as Quest-locations." So the
	# headers are not ours to invent: they are whatever the journal says, in the order the journal
	# says, and a category appears here exactly when Qud has something in it.
	var by_cat := {}
	var order: Array = []
	for e in _entries:
		var cat := String(e.get("category", ""))
		if cat == "":
			cat = "Unknown"
		if not by_cat.has(cat):
			by_cat[cat] = []
			order.append(cat)
		by_cat[cat].append(e)
	order.sort()
	# ...except OURS, which goes last. "Visited" is Raves' own answer for a place Qud has no note
	# for, and sorting it in among Qud's categories would claim it is one of them.
	if order.has(VISITED_CAT):
		order.erase(VISITED_CAT)
		order.append(VISITED_CAT)
	_row_count = 0
	for cat in order:
		var rows: Array = by_cat[cat]
		_rows.add_child(_make_cat_row(cat, rows.size()))
		_row_count += 1
		if not _cat_open(cat):
			continue
		for e in rows:
			_rows.add_child(_make_row(e))
			_row_count += 1
	if _empty != null:
		_empty.visible = _entries.is_empty()
	_apply_height()
	_paint_metrics()   # now, not on the next turn — see _paint_metrics
	_emit()

## Is this category expanded? Open by default — a tree that starts shut hides the thing the panel is
## for, and the ones a player collapses are the ones they have finished with.
func _cat_open(cat: String) -> bool:
	var all = Settings.get_value(CAT_KEY, {})
	if typeof(all) != TYPE_DICTIONARY:
		return true
	return bool(all.get(cat, true))

func _set_cat_open(cat: String, on: bool) -> void:
	var all = Settings.get_value(CAT_KEY, {})
	if typeof(all) != TYPE_DICTIONARY:
		all = {}
	all[cat] = on
	Settings.set_value(CAT_KEY, all)
	Settings.save()
	_rebuild()

## One category header: a disclosure caret, the name Qud uses, and how many are under it.
func _make_cat_row(cat: String, n: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s %s  (%d)" % ["▾" if _cat_open(cat) else "▸", cat, n]
	b.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "body"))
	b.add_theme_color_override("font_color", SEL_GOLD)
	b.tooltip_text = "Collapse %s" % cat if _cat_open(cat) else "Expand %s" % cat
	b.pressed.connect(func() -> void: _set_cat_open(cat, not _cat_open(cat)))
	return b

## Nearest first — a navigation list is read from the top, and the place you can reach is the one
## worth reading first. Unknown distance (no snapshot yet) keeps the file's order.
func _sort_entries() -> void:
	if not metrics_cb.is_valid() or _player.x < 0:
		return
	var keyed: Array = []
	for e in _entries:
		keyed.append([float(metrics_cb.call(int(e["mx"]), int(e["my"])).get("para", 0.0)), e])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	# ONE ROW PER NAME, once the distances are known — and the NEAREST one, which is why this waits
	# for the sort. A walk across a marsh visits five parasangs all called "salt marsh"; five rows
	# for it is five ways to say the same thing, and the useful one is the nearest. Journal entries
	# are never collapsed: Qud wrote those, and two notes sharing a name are still two notes.
	var out: Array = []
	var named := {}
	for k in keyed:
		var e: Dictionary = k[1]
		var nm := String(e["name"])
		# THE CATEGORY SAYS WHICH LIST IT CAME FROM, not the presence of art. This used to test
		# has("art"), which meant "is a travel-log row" only for as long as journal notes had no
		# sprite of their own — they carry one now, and the test would have started collapsing Qud's
		# own notes by name.
		if String(e.get("category", "")) == VISITED_CAT:
			if named.has(nm):
				continue
			named[nm] = true
		out.append(e)
	_entries = out

func _make_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	# Indented, so the tree reads as a tree rather than as a flat list with headings in it.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(10, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	var id := String(e["id"])
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = _on.has(id)
	cb.text = String(e["name"])
	cb.clip_text = true
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_font_size_override("font_size", UiFont.px(get_viewport(), "body"))
	var art: Dictionary = e.get("art", {})
	if not art.is_empty() and String(art.get("tile", "")) != "":
		var tex: Texture2D = _tiles.texture_for(art, true)
		if tex != null:
			cb.icon = tex
			cb.expand_icon = false
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
	# THE DISTANCE KEEPS ITS COLUMN. The name is EXPAND_FILL and clipped, so without a floor here it
	# takes the whole row and pushes "NE 7.4" off the panel — which is what the category indent did
	# the moment it was added, and what a long place name does on its own. Reserved for the widest
	# reading this column can hold.
	# Sized to the widest reading this column holds ("NE 12.3") and no wider — every pixel reserved
	# here is a pixel clipped off a place name in a panel this narrow.
	far.custom_minimum_size.x = float(UiFont.px(get_viewport(), "body")) * 3.7
	far.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_paint_metrics()

## Write the distance/bearing into every row that has the column. SPLIT OUT of _refresh_metrics so
## _rebuild can call it directly: the metrics used to be painted only on the next SNAPSHOT, and a
## snapshot only arrives when a turn passes — so every rebuild left the column blank until the
## player moved, which on an idle game is forever. That is why it kept looking like the distances
## had gone away.
func _paint_metrics() -> void:
	if _rows == null or not metrics_cb.is_valid():
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
	if _armed and not _lost and not _one_to_one:
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
				# The place's own art rides along; the palette colour is only the fallback for a
				# location the mod could find no sprite for.
				"art": e.get("art", {}),
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

## The signpost: are the beacons LABELLED? Persisted like the pin, and announced on its own signal
## so the beacons can hide their plates without anything being rebuilt — the cards are unaffected.
func _toggle_plates() -> void:
	_plates_on = not _plates_on
	Settings.set_value(PLATES_KEY, _plates_on)
	# set_value only writes MEMORY — save() is what reaches disk, and every other toggle in this
	# panel pairs the two. Without it the signpost came back on at every launch while the pin and
	# the category folds remembered themselves, which reads as the signpost not working rather than
	# as a missing flush.
	Settings.save()
	_refresh_signpost()
	plates_changed.emit(_plates_on)

## The panel's own answer, for a listener that connects after the first emit — the same late-bind
## problem refresh_beacons already solves for the cards.
func plates_on() -> bool:
	return _plates_on

func _refresh_signpost() -> void:
	if _signpost == null:
		return
	var tex := _signpost_tex()
	if tex != null:
		_signpost.icon = tex
		_signpost.text = ""
	else:
		# NO ART, STILL A CONTROL. A toggle that renders as nothing is one nobody can find.
		_signpost.text = "N" if _plates_on else "n"
	# ON is the panel's own text colour; OFF is the same dimming a unticked row gets, so the
	# signpost reads the way every other off thing in this panel does.
	_signpost.modulate = Color(1, 1, 1, 1) if _plates_on else Color(1, 1, 1, 0.4)
	_signpost.tooltip_text = ("Hide location names" if _plates_on else "Show location names")

var _signpost_icon: Texture2D
func _signpost_tex() -> Texture2D:
	if _signpost_icon != null:
		return _signpost_icon
	if not ResourceLoader.exists("res://art/signpost.svg"):
		return null
	_signpost_icon = load("res://art/signpost.svg") as Texture2D
	return _signpost_icon
