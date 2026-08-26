extends RefCounted

## Make a hint line's bracketed keys CLICKABLE.
##
## Raves' screens all print their controls — "[Esc] Back", "[Space] select", "[R] Randomize
## Selection" — and a named key printed on screen is something a player reaches for with the
## mouse. This turns those words into hit targets without giving each screen its own copy of the
## plumbing, and without a second implementation of the ACTION: the caller passes the same
## Callable its key handler already runs, so the two cannot drift apart.
##
## Usage: wrap the words in [url=id] in the bbcode, then
##     UiHint.clickable(label, {"esc": _go_back, "del": _delete_selected})
##
## NO `class_name`: a newly added global class only exists once the editor has rebuilt its cache,
## and a headless build must not depend on that having happened. Callers preload this file.
static func clickable(rich: RichTextLabel, actions: Dictionary) -> void:
	if rich == null or not is_instance_valid(rich):
		return
	# a RichTextLabel only reports [url] clicks when it can feel the mouse at all
	rich.mouse_filter = Control.MOUSE_FILTER_STOP
	rich.meta_clicked.connect(func(meta: Variant) -> void:
		var cb: Variant = actions.get(String(meta), null)
		if cb is Callable:
			(cb as Callable).call())

## The same thing for a hint that is DRAWN rather than laid out as a label — Control Mapping
## paints its footer into a static texture, so the only way to click it is a box over the words.
## `rect` is in the parent's coordinates.
static func hit_box(parent: Control, rect: Rect2, action: Callable) -> Control:
	var b := Control.new()
	b.position = rect.position
	b.size = rect.size
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			action.call())
	parent.add_child(b)
	return b
