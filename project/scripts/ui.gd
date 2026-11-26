class_name Ui
extends RefCounted
## Small builders for the editor's widgets, so the pages read as a list of what is on them.

## The smallest height of anything you tap (40 px or more works for fingers).
const TAP := 40


static func button(text: String, action: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(action)
	if accent:
		make_accent(b)
	return b


## A smaller button for choices that sit in a row (meals, groups, table shapes).
static func chip(text: String, action: Callable) -> Button:
	var b := button(text, action)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, TAP)
	return b


static func icon_button(icon_name: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.icon = UiTheme.icon(icon_name)
	if b.icon == null:
		b.text = tip.substr(0, 1)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(46, 46)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	return b


static func make_accent(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ACCENT))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.ACCENT.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.ACCENT.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", UiTheme.box(Color(UiTheme.ACCENT, 0.45)))


static func label(text: String, size_px: int = 16, color: Color = UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func heading(text: String) -> Label:
	var l := label(text, 13, UiTheme.MUTED)
	l.uppercase = true
	return l


## A one-line text field that applies its text on Enter and when it loses focus.
static func field(text: String, placeholder: String, apply: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 42)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.select_all_on_focus = true
	edit.text_submitted.connect(func(value: String) -> void:
		apply.call(value)
		edit.release_focus())
	edit.focus_exited.connect(func() -> void: apply.call(edit.text))
	return edit


static func row(children: Array, separation := 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	for child: Control in children:
		box.add_child(child)
	return box


## Buttons that wrap onto more lines when they do not fit.
static func flow(children: Array = []) -> HFlowContainer:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 6)
	box.add_theme_constant_override("v_separation", 6)
	for child: Control in children:
		box.add_child(child)
	return box


static func expand(controls: Array) -> Array:
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return controls


static func labelled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label(text, 14, UiTheme.MUTED))
	box.add_child(control)
	return box


## A list row: a coloured dot, the main text, and a quieter text on the right.
static func list_row(text: String, right: String, color: Color, action: Callable, chosen := false) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UiTheme.dot(color)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, TAP)
	b.add_theme_constant_override("icon_max_width", 14)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.ON if chosen else Color(UiTheme.BUTTON, 0.55), 8, 10))
	b.pressed.connect(action)
	if right != "":
		var tag := label(right, 13, UiTheme.MUTED)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		b.add_child(tag)
		b.add_theme_constant_override("h_separation", 8)
	return b


## Removes and frees every child of a container.
static func clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
