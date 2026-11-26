extends Control
## Seatwise: the editor screen. Builds the interface in code, keeps the plan in user:// (IndexedDB in the
## browser), and opens and downloads files through the browser on the web.

const PLAN_PATH := "user://seatwise.json"
const WIDE_MIN := 760.0

const C_BG := Color("13161d")
const C_PANEL := Color("1b1f28")
const C_BUTTON := Color("262b37")
const C_BUTTON_HOVER := Color("313848")
const C_ON := Color("2f4378")
const C_ACCENT := Color("3f6df2")
const C_TEXT := Color("eef0f6")
const C_MUTED := Color("9aa3b5")
const C_GOOD := Color("5fd39a")
const C_BAD := Color("ff7a73")
const C_FOCUS := Color("ffd166")
const DIETS := ["vegetarian", "vegan", "gluten-free", "kids"]

const SVG_HEAD := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='#eef0f6' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
const ICONS := {
	"undo": "<path d='M9 14L4 9l5-5'/><path d='M4 9h10a6 6 0 0 1 0 12h-3'/>",
	"redo": "<path d='M15 14l5-5-5-5'/><path d='M20 9H10a6 6 0 0 0 0 12h3'/>",
	"menu": "<path d='M4 6h16M4 12h16M4 18h16'/>",
	"fit": "<path d='M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5'/>",
	"plus": "<path d='M12 5v14M5 12h14'/>",
	"minus": "<path d='M5 12h14'/>",
	"turn": "<path d='M20 4v6h-6'/><path d='M19.5 10A8 8 0 1 0 18 17'/>",
	"spark": "<path d='M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z'/><path d='M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z'/>",
}

var seating := Seating.new()
var _view: VenueView
var _body: BoxContainer
var _side: VBoxContainer
var _tab_buttons := {}
var _pages := {}
var _scroll: ScrollContainer
var _status: Button
var _seat_button: Button
var _undo_button: Button
var _redo_button: Button
var _toast: Label
var _toast_timer: Timer
var _save_timer: Timer
var _overlay: Control
var _sheet_box: VBoxContainer
var _icons := {}
var _wide := false
var _laid_out := false
var _file_callback: JavaScriptObject
var _menu_ids := {}
var _solving := false

var _summary: Label
var _search: LineEdit
var _guest_list: VBoxContainer
var _title_edit: LineEdit
var _table_list: VBoxContainer
var _catering: Label
var _piece_box: VBoxContainer


func _ready() -> void:
	get_tree().root.theme = _make_theme()
	var first_visit := not _load_plan()
	_build()
	_view.seating = seating
	resized.connect(_layout)
	_layout()
	get_window().files_dropped.connect(_on_files_dropped)
	_changed(false)
	_show_page("guests")
	await get_tree().process_frame
	_view.fit()
	if first_visit:
		_show_toast("An example wedding with 38 guests. Press Seat everyone, then drag people around.", 6.0)


# ------------------------------------------------------------------ Theme and widgets

func _box(color: Color, radius: int = 10, margin: int = 10, border: Color = Color.TRANSPARENT, border_width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.7
	box.content_margin_bottom = margin * 0.7
	if border.a > 0.0:
		box.set_border_width_all(border_width)
		box.border_color = border
	box.anti_aliasing = true
	return box


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	for type in ["Label", "Button", "MenuButton", "LineEdit", "TextEdit", "PopupMenu"]:
		t.set_color("font_color", type, C_TEXT)
	for type in ["Button", "MenuButton"]:
		t.set_color("font_hover_color", type, C_TEXT)
		t.set_color("font_pressed_color", type, C_TEXT)
		t.set_color("font_focus_color", type, C_TEXT)
		t.set_color("font_hover_pressed_color", type, C_TEXT)
		t.set_color("font_disabled_color", type, Color(C_MUTED, 0.5))
		t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.3))
		t.set_stylebox("normal", type, _box(C_BUTTON))
		t.set_stylebox("hover", type, _box(C_BUTTON_HOVER))
		t.set_stylebox("pressed", type, _box(C_ON))
		t.set_stylebox("hover_pressed", type, _box(C_ON.lightened(0.08)))
		t.set_stylebox("disabled", type, _box(Color(C_BUTTON, 0.5)))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, 10, 10, C_FOCUS))
		t.set_constant("icon_max_width", type, 22)
	t.set_stylebox("panel", "PanelContainer", _box(C_PANEL, 16, 18))
	t.set_stylebox("panel", "PopupMenu", _box(C_PANEL, 10, 8, C_BUTTON, 1))
	t.set_stylebox("hover", "PopupMenu", _box(C_BUTTON_HOVER, 6))
	t.set_color("font_hover_color", "PopupMenu", C_TEXT)
	t.set_color("font_separator_color", "PopupMenu", C_MUTED)
	t.set_constant("v_separation", "PopupMenu", 10)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, _box(Color("0f1217"), 8, 10, Color("323846"), 1))
		t.set_stylebox("focus", type, _box(Color("0f1217"), 8, 10, C_FOCUS))
		t.set_color("caret_color", type, C_TEXT)
		t.set_color("font_placeholder_color", type, Color(C_MUTED, 0.7))
	t.set_color("font_color", "TooltipLabel", C_TEXT)
	t.set_stylebox("panel", "TooltipPanel", _box(Color("2c3140"), 6, 8))
	t.set_font_size("font_size", "TooltipLabel", 14)
	return t


func _icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var image := Image.new()
	var texture: Texture2D = null
	if image.load_svg_from_string(SVG_HEAD + ICONS[name] + "</svg>", 2.0) == OK:
		texture = ImageTexture.create_from_image(image)
	_icons[name] = texture
	return texture


func _dot(color: Color) -> Texture2D:
	var key := "dot" + color.to_html()
	if _icons.has(key):
		return _icons[key]
	var image := Image.create_empty(28, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 28:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(14, 14))
			image.set_pixel(x, y, Color(color, clampf(13.5 - d, 0.0, 1.0)))
	_icons[key] = ImageTexture.create_from_image(image)
	return _icons[key]


func _icon_button(icon_name: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = _icon(icon_name)
	if button.icon == null:
		button.text = tip.substr(0, 1)
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(46, 46)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	return button


func _button(text: String, action: Callable, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	if accent:
		_make_accent(button)
	return button


func _make_accent(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(C_ACCENT))
	button.add_theme_stylebox_override("hover", _box(C_ACCENT.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _box(C_ACCENT.darkened(0.15)))
	button.add_theme_stylebox_override("disabled", _box(Color(C_ACCENT, 0.45)))


func _label(text: String, size_px: int = 16, color: Color = C_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _heading(text: String) -> Label:
	var label := _label(text, 13, C_MUTED)
	label.uppercase = true
	return label


func _field(text: String, placeholder: String, apply: Callable) -> LineEdit:
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


func _row(children: Array, separation := 8) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	for child: Control in children:
		row.add_child(child)
	return row


func _expand(controls: Array) -> Array:
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return controls


func _labelled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_label(text, 14, C_MUTED))
	box.add_child(control)
	return box


## A list row: a coloured dot, the main text, and a quieter text on the right.
func _list_row(text: String, right: String, color: Color, action: Callable, chosen := false) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = _dot(color)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_constant_override("icon_max_width", 14)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _box(C_ON if chosen else Color(C_BUTTON, 0.55), 8, 10))
	b.pressed.connect(action)
	if right != "":
		var tag := _label(right, 13, C_MUTED)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		b.add_child(tag)
		b.add_theme_constant_override("h_separation", 8)
	return b


# ------------------------------------------------------------------ Building

func _build() -> void:
	var back := ColorRect.new()
	back.color = C_BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(30, 30)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(logo)
	var name_label := _label("Seatwise", 20)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	_undo_button = _icon_button("undo", "Undo (Ctrl+Z)", _undo)
	_redo_button = _icon_button("redo", "Redo (Ctrl+Y)", _redo)
	top.add_child(_undo_button)
	top.add_child(_redo_button)
	var menu := MenuButton.new()
	menu.icon = _icon("menu")
	menu.text = "Menu"
	menu.flat = false
	menu.focus_mode = Control.FOCUS_ALL
	menu.custom_minimum_size = Vector2(46, 46)
	top.add_child(menu)
	_build_menu(menu.get_popup())

	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	root.add_child(_body)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(C_BG, 12, 0, Color("232836"), 1))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.7
	_body.add_child(frame)
	_view = VenueView.new()
	_view.custom_minimum_size = Vector2(160, 220)
	_view.selection_changed.connect(_on_selection_changed)
	_view.edited.connect(func() -> void: _changed())
	_view.seat_tapped.connect(_on_seat_tapped)
	frame.add_child(_view)

	_status = Button.new()
	_status.focus_mode = Control.FOCUS_ALL
	_status.position = Vector2(10, 10)
	_status.add_theme_font_size_override("font_size", 14)
	_status.pressed.connect(_show_first_problem)
	_view.add_child(_status)
	_seat_button = Button.new()
	_seat_button.text = "Seat everyone"
	_seat_button.icon = _icon("spark")
	_seat_button.tooltip_text = "Seats every guest who has no seat yet and improves the whole plan. Locked seats stay."
	_seat_button.focus_mode = Control.FOCUS_ALL
	_seat_button.custom_minimum_size = Vector2(0, 46)
	_make_accent(_seat_button)
	_seat_button.pressed.connect(_seat_everyone)
	_seat_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	_seat_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_view.add_child(_seat_button)
	var zoom_box := HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 4)
	zoom_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	zoom_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for spec in [["minus", "Zoom out (-)", func() -> void: _view.zoom_center(1.0 / 1.25)], ["plus", "Zoom in (+)", func() -> void: _view.zoom_center(1.25)], ["fit", "Show every table (0)", func() -> void: _view.fit()]]:
		var b := _icon_button(spec[0], spec[1], spec[2])
		b.custom_minimum_size = Vector2(40, 40)
		zoom_box.add_child(b)
	_view.add_child(zoom_box)
	_toast = _label("", 14)
	_toast.add_theme_stylebox_override("normal", _box(Color("2c3140"), 8, 12))
	_toast.visible = false
	_view.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast.visible = false)
	add_child(_toast_timer)

	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	_body.add_child(_side)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_side.add_child(tabs)
	for spec in [["guests", "Guests"], ["tables", "Tables"], ["piece", "Selected"]]:
		var page_id: String = spec[0]
		var tab := Button.new()
		tab.text = spec[1]
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_ALL
		tab.custom_minimum_size = Vector2(0, 42)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void: _show_page(page_id))
		tabs.add_child(tab)
		_tab_buttons[page_id] = tab
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	_pages["guests"] = _build_guest_page()
	_pages["tables"] = _build_table_page()
	_piece_box = VBoxContainer.new()
	_piece_box.add_theme_constant_override("separation", 10)
	_pages["piece"] = _piece_box
	for key: String in _pages:
		pages.add_child(_pages[key])

	_build_overlay()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)


func _build_guest_page() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_summary = _label("", 15, C_MUTED)
	box.add_child(_summary)
	box.add_child(_row(_expand([_button("Paste a guest list", _open_paste_sheet), _button("Add a guest", _add_one_guest)])))
	_search = LineEdit.new()
	_search.placeholder_text = "Find a guest"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 42)
	_search.text_changed.connect(func(_t: String) -> void: _refresh_guest_list())
	box.add_child(_search)
	_guest_list = VBoxContainer.new()
	_guest_list.add_theme_constant_override("separation", 4)
	box.add_child(_guest_list)
	return box


func _build_table_page() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_title_edit = _field(seating.title, "Event name", func(value: String) -> void:
		var clean := value.strip_edges().left(60)
		if clean != "" and clean != seating.title:
			seating.checkpoint()
			seating.title = clean
			_changed()
		_title_edit.text = seating.title)
	box.add_child(_labelled("Event name", _title_edit))
	box.add_child(_heading("Add a table"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for spec in [["Round, 8", "round", 8], ["Round, 10", "round", 10], ["Long, 10", "rect", 10], ["Long, 12", "rect", 12], ["Head table, 6", "head", 6], ["Small, 4", "rect", 4]]:
		var shape: String = spec[1]
		var count: int = spec[2]
		var b := _button(spec[0], func() -> void: _add_table(shape, count))
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(0, 40)
		flow.add_child(b)
	box.add_child(flow)
	box.add_child(_heading("Tables"))
	_table_list = VBoxContainer.new()
	_table_list.add_theme_constant_override("separation", 4)
	box.add_child(_table_list)
	box.add_child(_heading("For the caterer"))
	_catering = _label("", 15)
	box.add_child(_catering)
	return box


func _build_menu(popup: PopupMenu) -> void:
	var items := [
		["new", "New event"], ["example", "Load the example wedding"], [],
		["open", "Open a plan or a guest list…"], ["save", "Save the plan as a file"],
		["chart", "Download the seating chart (PNG)"], ["list", "Download the seat list (PNG)"], ["csv", "Download the guest list (CSV)"], [],
		["clear", "Take everyone off their seats"], ["help", "How to use Seatwise"],
	]
	var id := 0
	for item: Array in items:
		if item.is_empty():
			popup.add_separator()
			continue
		popup.add_item(item[1], id)
		_menu_ids[id] = item[0]
		id += 1
	popup.id_pressed.connect(func(pressed: int) -> void: _on_menu(_menu_ids[pressed]))


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_sheet())
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)
	_sheet_box = VBoxContainer.new()
	_sheet_box.add_theme_constant_override("separation", 12)
	panel.add_child(_sheet_box)


# ------------------------------------------------------------------ Layout

func _layout() -> void:
	var wide := size.x >= WIDE_MIN and size.x > size.y * 1.05
	if wide == _wide and _laid_out:
		return
	_wide = wide
	_laid_out = true
	_body.vertical = not wide
	if wide:
		_side.custom_minimum_size = Vector2(330, 0)
		_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size = Vector2(0, 0)
	else:
		_side.custom_minimum_size = Vector2(0, 0)
		_side.size_flags_vertical = Control.SIZE_FILL
		_scroll.custom_minimum_size = Vector2(0, clampf(size.y * 0.36, 230.0, 400.0))
	_view.fit.call_deferred()


func _show_page(page: String) -> void:
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).set_pressed_no_signal(key == page)
	_scroll.scroll_vertical = 0


# ------------------------------------------------------------------ State

func _load_plan() -> bool:
	if FileAccess.file_exists(PLAN_PATH):
		if seating.from_json(FileAccess.get_file_as_string(PLAN_PATH)) == "":
			return true
	seating.load_example()
	return false


func _save_now() -> void:
	var file := FileAccess.open(PLAN_PATH, FileAccess.WRITE)
	if file:
		file.store_string(seating.to_json())
		file.close()


func _changed(save := true) -> void:
	_view.refresh()
	_undo_button.disabled = not seating.can_undo()
	_redo_button.disabled = not seating.can_redo()
	_refresh_status()
	_refresh_guest_list()
	_refresh_table_page()
	_refresh_piece_page()
	if save:
		_save_timer.start()


func _refresh_status() -> void:
	var real := seating.wish_problems()
	var waiting := seating.unseated().size()
	var good := real.is_empty() and waiting == 0 and not seating.guests.is_empty()
	if good:
		_status.text = "Everyone seated, every wish kept"
	elif not real.is_empty():
		_status.text = "%d %s to look at" % [real.size(), "thing" if real.size() == 1 else "things"]
	else:
		_status.text = "%d waiting for a seat" % waiting
	var color := Color("173a2b") if good else (Color("4a1f22") if not real.is_empty() else Color("2c3140"))
	_status.add_theme_stylebox_override("normal", _box(color, 16, 12))
	_status.add_theme_stylebox_override("hover", _box(color.lightened(0.06), 16, 12))
	_status.add_theme_color_override("font_color", C_GOOD if good else (Color("ffd2cf") if not real.is_empty() else C_TEXT))
	_status.reset_size()


func _seat_text(guest_id: int) -> String:
	var s := seating.seat_of(guest_id)
	if s.is_empty():
		return "waiting"
	return seating.get_table(s.table).name


func _refresh_guest_list() -> void:
	var seated := seating.guests.size() - seating.unseated().size()
	_summary.text = "%d guests · %d seated · %d seats at %d tables" % [seating.guests.size(), seated, seating.capacity(), seating.tables.size()]
	for child in _guest_list.get_children():
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var waiting: Array[Dictionary] = []
	var placed: Array[Dictionary] = []
	for g in seating.guests:
		if query != "" and not (g.name.to_lower().contains(query) or g.group.to_lower().contains(query)):
			continue
		if seating.seat_of(g.id).is_empty():
			waiting.append(g)
		else:
			placed.append(g)
	var by_name := func(a: Dictionary, b: Dictionary) -> bool: return Seating.sort_key(a.name) < Seating.sort_key(b.name)
	placed.sort_custom(by_name)
	if not waiting.is_empty():
		_guest_list.add_child(_heading("Waiting for a seat (%d)" % waiting.size()))
		for g in waiting:
			_guest_list.add_child(_guest_row(g))
	if not placed.is_empty():
		_guest_list.add_child(_heading("Seated (%d)" % placed.size()))
		for g in placed:
			_guest_list.add_child(_guest_row(g))
	if seating.guests.is_empty():
		_guest_list.add_child(_label("No guests yet. Paste your list: one guest per line, or \"Tom & Lisa Meyer\" for a couple.", 15, C_MUTED))
	elif waiting.is_empty() and placed.is_empty():
		_guest_list.add_child(_label("Nobody matches \"%s\"." % _search.text, 15, C_MUTED))


func _guest_row(g: Dictionary) -> Button:
	var id: int = g.id
	var chosen: bool = id == _view.selected_guest or id == _view.placing_guest
	var row := _list_row(g.name, _seat_text(id), _view.group_color(g.group), func() -> void: _pick_guest(id), chosen)
	row.tooltip_text = ("%s · %s" % [g.group, g.diet]).strip_edges().trim_prefix("·").trim_suffix("·").strip_edges()
	return row


func _refresh_table_page() -> void:
	if not _title_edit.has_focus():
		_title_edit.text = seating.title
	for child in _table_list.get_children():
		child.queue_free()
	for t in seating.tables:
		var id: int = t.id
		var seated: int = t.guests.size() - t.guests.count(0)
		var diets := _diet_text(seating.diet_counts(id))
		var row := _list_row(t.name, "%d / %d" % [seated, t.seats], Color("e2d6c2"), func() -> void:
			_view.select_table(id), id == _view.selected_table)
		row.tooltip_text = ("Meals: " + diets) if diets != "" else "No special meals"
		_table_list.add_child(row)
	if seating.tables.is_empty():
		_table_list.add_child(_label("No tables yet. Add one above, then drag it into place.", 15, C_MUTED))
	var totals := seating.diet_counts()
	_catering.text = "%d guests in all%s." % [seating.guests.size(), (": " + _diet_text(totals, true)) if not totals.is_empty() else ", no special meals"]


func _diet_text(counts: Dictionary, long := false) -> String:
	var parts: Array[String] = []
	var keys := counts.keys()
	keys.sort()
	for k: String in keys:
		parts.append("%d %s" % [counts[k], k])
	return ", ".join(parts) if long or parts.size() <= 2 else "%d special" % counts.values().reduce(func(a: int, b: int) -> int: return a + b, 0)


func _refresh_piece_page() -> void:
	var typing := false
	for child in _piece_box.find_children("*", "LineEdit", true, false):
		typing = typing or (child as LineEdit).has_focus()
	if typing:
		return
	for child in _piece_box.get_children():
		_piece_box.remove_child(child)
		child.queue_free()
	if _view.selected_guest != -1:
		_build_guest_inspector(seating.get_guest(_view.selected_guest))
	elif _view.selected_table != -1:
		_build_table_inspector(seating.get_table(_view.selected_table))
	else:
		_piece_box.add_child(_label("Tap a guest or a table to change it. Drag a guest onto another seat to move them; drop them on someone to swap.", 15, C_MUTED))


func _build_guest_inspector(g: Dictionary) -> void:
	var id: int = g.id
	var name_edit := _field(g.name, "Name", func(value: String) -> void:
		var clean := value.strip_edges().left(60)
		var current := seating.get_guest(id)
		if clean != "" and not current.is_empty() and clean != current.name:
			seating.checkpoint()
			current.name = clean
			_changed())
	_piece_box.add_child(_labelled("Name", name_edit))
	var s := seating.seat_of(id)
	_piece_box.add_child(_label("Seat %d at %s" % [s.seat + 1, seating.get_table(s.table).name] if not s.is_empty() else "Waiting for a seat: tap an empty seat in the plan.", 15, C_TEXT if not s.is_empty() else C_FOCUS))
	var group_edit := _field(g.group, "e.g. Family, Work", func(value: String) -> void:
		var current := seating.get_guest(id)
		var clean := value.strip_edges().left(40)
		if not current.is_empty() and clean != current.group:
			seating.checkpoint()
			current.group = clean
			_changed())
	_piece_box.add_child(_labelled("Group", group_edit))
	var groups := {}
	for other in seating.guests:
		if other.group != "" and other.group != g.group:
			groups[other.group] = true
	if not groups.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for group_name: String in groups.keys().slice(0, 8):
			var b := _button(group_name, func() -> void:
				seating.checkpoint()
				seating.get_guest(id).group = group_name
				_changed())
			b.icon = _dot(_view.group_color(group_name))
			b.add_theme_constant_override("icon_max_width", 12)
			b.add_theme_font_size_override("font_size", 13)
			b.custom_minimum_size = Vector2(0, 34)
			flow.add_child(b)
		_piece_box.add_child(flow)
	_piece_box.add_child(_heading("Meal"))
	var diets := HFlowContainer.new()
	diets.add_theme_constant_override("h_separation", 6)
	diets.add_theme_constant_override("v_separation", 6)
	for diet in [""] + DIETS:
		var value: String = diet
		var b := _button("No special meal" if value == "" else value.capitalize(), func() -> void:
			seating.checkpoint()
			seating.get_guest(id).diet = value
			seating.drop_checkpoint_if_unchanged()
			_changed())
		b.toggle_mode = true
		b.set_pressed_no_signal(g.diet == value)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 34)
		diets.add_child(b)
	if g.diet != "" and not (g.diet in DIETS):
		var other := _button(g.diet.capitalize(), func() -> void: pass)
		other.toggle_mode = true
		other.set_pressed_no_signal(true)
		diets.add_child(other)
	_piece_box.add_child(diets)

	_piece_box.add_child(_heading("Sits together with"))
	var mates := seating.party_members(g.party).filter(func(m: int) -> bool: return m != id)
	if mates.is_empty():
		_piece_box.add_child(_label("Nobody yet. A household or a couple always gets seats side by side.", 14, C_MUTED))
	else:
		_piece_box.add_child(_label(", ".join(mates.map(func(m: int) -> String: return seating.get_guest(m).name)), 15))
	var together := [_button("Add someone", func() -> void: _pick_other("Sits together with %s" % g.name, id, func(other: int) -> void:
		seating.checkpoint()
		seating.join_party(id, other)
		_changed()))]
	if not mates.is_empty():
		together.append(_button("Sit alone", func() -> void:
			seating.checkpoint()
			seating.leave_party(id)
			_changed()))
	_piece_box.add_child(_row(_expand(together)))

	_piece_box.add_child(_heading("Keep apart from"))
	var avoid: Array[int] = []
	for pair in seating.apart:
		if pair.x == id:
			avoid.append(pair.y)
		elif pair.y == id:
			avoid.append(pair.x)
	for other_id in avoid:
		var other: int = other_id
		var row := _list_row(seating.get_guest(other).name, "remove", Color("ff7a73"), func() -> void:
			seating.checkpoint()
			seating.set_apart(id, other, false)
			_changed())
		row.tooltip_text = "Allow them at the same table again"
		_piece_box.add_child(row)
	_piece_box.add_child(_button("Keep apart from someone", func() -> void: _pick_other("Not at the same table as %s" % g.name, id, func(other: int) -> void:
		seating.checkpoint()
		seating.set_apart(id, other, true)
		_changed())))

	var lock := _button("Seat locked" if g.locked else "Lock this seat", func() -> void:
		seating.checkpoint()
		seating.get_guest(id).locked = not seating.get_guest(id).locked
		_changed())
	lock.toggle_mode = true
	lock.set_pressed_no_signal(g.locked)
	lock.tooltip_text = "Seat everyone never moves a locked guest."
	lock.disabled = s.is_empty()
	var unseat := _button("Take off seat", func() -> void:
		seating.checkpoint()
		seating.unseat(id)
		seating.get_guest(id).locked = false
		_changed())
	unseat.disabled = s.is_empty()
	_piece_box.add_child(_row(_expand([lock, unseat])))
	var remove := _button("Remove guest", func() -> void:
		seating.checkpoint()
		seating.remove_guest(id)
		_view.select_guest(-1)
		_changed())
	remove.add_theme_color_override("font_color", C_BAD)
	_piece_box.add_child(remove)
	var own := seating.wish_problems().filter(func(p: Dictionary) -> bool: return p.guests.has(id))
	for p: Dictionary in own:
		_piece_box.add_child(_label(p.text, 15, C_BAD))


func _build_table_inspector(t: Dictionary) -> void:
	var id: int = t.id
	var name_edit := _field(t.name, "Name", func(value: String) -> void:
		var clean := value.strip_edges().left(40)
		var current := seating.get_table(id)
		if clean != "" and not current.is_empty() and clean != current.name:
			seating.checkpoint()
			current.name = clean
			_changed())
	_piece_box.add_child(_labelled("Table name", name_edit))
	var shapes := []
	for spec in [["round", "Round"], ["rect", "Long"], ["head", "Head table"]]:
		var shape: String = spec[0]
		var b := _button(spec[1], func() -> void:
			seating.checkpoint()
			seating.get_table(id).shape = shape
			seating.drop_checkpoint_if_unchanged()
			_changed())
		b.toggle_mode = true
		b.set_pressed_no_signal(t.shape == shape)
		shapes.append(b)
	_piece_box.add_child(_row(_expand(shapes), 4))
	var count := _label("%d seats" % t.seats, 16)
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fewer := _icon_button("minus", "One seat fewer", func() -> void: _change_seats(id, -1))
	var more := _icon_button("plus", "One seat more", func() -> void: _change_seats(id, 1))
	fewer.disabled = t.seats <= 1
	more.disabled = t.seats >= Seating.MAX_SEATS
	var row := _row([fewer, count, more])
	if t.shape != "round":
		row.add_child(_icon_button("turn", "Turn a quarter", func() -> void:
			seating.checkpoint()
			var current := seating.get_table(id)
			current.rot = fposmod(current.rot + 90.0, 360.0)
			_changed()))
	_piece_box.add_child(row)
	_piece_box.add_child(_heading("At this table"))
	var seated := 0
	for i in t.seats:
		var g: int = t.guests[i]
		if g == 0:
			continue
		seated += 1
		var guest := seating.get_guest(g)
		var gid := g
		_piece_box.add_child(_list_row("%d. %s" % [i + 1, guest.name], guest.diet, _view.group_color(guest.group), func() -> void: _view.select_guest(gid)))
	if seated == 0:
		_piece_box.add_child(_label("Nobody yet.", 15, C_MUTED))
	var clear := _button("Clear this table", func() -> void:
		seating.checkpoint()
		var current := seating.get_table(id)
		for i in current.seats:
			if current.guests[i] != 0:
				seating.get_guest(current.guests[i]).locked = false
				current.guests[i] = 0
		_changed())
	var remove := _button("Remove table", func() -> void:
		seating.checkpoint()
		seating.remove_table(id)
		_view.select_table(-1)
		_changed())
	remove.add_theme_color_override("font_color", C_BAD)
	_piece_box.add_child(_row(_expand([clear, remove])))


# ------------------------------------------------------------------ Actions

func _pick_guest(id: int) -> void:
	_view.select_guest(id)
	if seating.seat_of(id).is_empty():
		_view.placing_guest = id
		_show_toast("Tap an empty seat for %s." % seating.get_guest(id).name)
	else:
		_view.placing_guest = -1
		_view.show_guest(id)
	_changed(false)


func _on_seat_tapped(table_id: int, index: int) -> void:
	var guest := _view.placing_guest
	if guest == -1 and _view.selected_guest != -1:
		guest = _view.selected_guest
	if guest == -1:
		_show_toast("Pick a guest first: in the list, or by tapping someone at a table.")
		return
	seating.checkpoint()
	seating.seat(guest, table_id, index)
	_view.placing_guest = -1
	_view.selected_guest = guest
	var next := seating.unseated()
	_changed()
	_show_toast("%s: seat %d at %s." % [seating.get_guest(guest).name, index + 1, seating.get_table(table_id).name])
	# Keep going with whoever is next in their household, so couples are quick to seat.
	for m in seating.party_members(seating.get_guest(guest).party):
		if next.has(m):
			_view.placing_guest = m
			_view.selected_guest = m
			_show_toast("Now tap a seat for %s." % seating.get_guest(m).name)
			_changed(false)
			break


func _on_selection_changed() -> void:
	if _view.selected_guest != _view.placing_guest:
		_view.placing_guest = -1
	_changed(false)
	if _view.selected_guest != -1 or _view.selected_table != -1:
		_show_page("piece")


func _show_first_problem() -> void:
	var real := seating.wish_problems()
	if real.is_empty():
		if not seating.unseated().is_empty():
			_show_page("guests")
		return
	var first: Dictionary = real[0]
	_show_toast(first.text, 4.0)
	if not first.guests.is_empty():
		_view.select_guest(first.guests[0])
		_view.show_guest(first.guests[0])


func _add_one_guest() -> void:
	seating.checkpoint()
	var id := seating.add_guest("New guest")
	_view.select_guest(id)
	_changed()
	_show_page("piece")
	var edits := _piece_box.find_children("*", "LineEdit", true, false)
	if not edits.is_empty():
		(edits[0] as LineEdit).grab_focus.call_deferred()


func _add_table(shape: String, seats: int) -> void:
	seating.checkpoint()
	var area := _view.content_rect() if not seating.tables.is_empty() else Rect2(0, 0, 0, 0)
	var pos := Vector2(area.end.x + 60.0, area.get_center().y) if not seating.tables.is_empty() else Vector2(300, 300)
	var center := _view.to_venue(_view.size / 2.0)
	if seating.tables.is_empty():
		pos = center
	else:
		# The middle of the view when it is free, otherwise to the right of everything.
		var probe := {"shape": shape, "seats": seats, "x": center.x, "y": center.y, "rot": 0.0}
		var free := true
		var reach := Seating.table_size(probe).length() / 2.0 + 90.0
		for t in seating.tables:
			if Vector2(t.x, t.y).distance_to(center) < reach + Seating.table_size(t).length() / 2.0:
				free = false
		if free:
			pos = center
	var id := seating.add_table(shape, seats, snappedf(pos.x, 10.0), snappedf(pos.y, 10.0), "Head table" if shape == "head" else "")
	_view.select_table(id)
	_changed()
	_view.fit()


func _change_seats(id: int, delta: int) -> void:
	var t := seating.get_table(id)
	if t.is_empty():
		return
	seating.checkpoint()
	var before := seating.unseated().size()
	seating.set_seats(id, t.seats + delta)
	_changed()
	if seating.unseated().size() > before:
		_show_toast("Someone lost their seat and is waiting again.")


func _seat_everyone() -> void:
	if _solving:
		return
	if seating.tables.is_empty():
		_show_toast("Add tables first, under Tables.")
		_show_page("tables")
		return
	if seating.guests.is_empty():
		_show_toast("Add guests first: paste your list.")
		return
	_solving = true
	_seat_button.disabled = true
	_view.busy = true
	seating.checkpoint()
	# The solver's steps, spread over frames (about 25 ms of work each) so the screen stays smooth.
	var solver := SeatingSolver.new(seating, Time.get_ticks_usec())
	var more := true
	while more:
		var started := Time.get_ticks_msec()
		while more and Time.get_ticks_msec() - started < 25:
			more = solver.step()
		_seat_button.text = "Seating… %d%%" % roundi(100.0 * solver.progress())
		_view.refresh()
		await get_tree().process_frame
	seating.drop_checkpoint_if_unchanged()
	_seat_button.text = "Seat everyone"
	_seat_button.disabled = false
	_view.busy = false
	_solving = false
	_changed()
	var real := seating.wish_problems()
	var waiting := seating.unseated().size()
	if waiting > 0 and seating.capacity() < seating.guests.size():
		_show_toast("Not enough seats: %d still waiting. Add a table or more seats." % waiting, 5.0)
	elif real.is_empty():
		_show_toast("Done. Couples sit together, groups share tables, and every wish is kept.", 5.0)
	else:
		_show_toast("Done, but %d %s could not be kept. Tap the red box to see." % [real.size(), "wish" if real.size() == 1 else "wishes"], 5.0)


func _undo() -> void:
	if not _solving and seating.undo():
		_changed()


func _redo() -> void:
	if not _solving and seating.redo():
		_changed()


func _on_menu(id: String) -> void:
	if _solving:
		return
	match id:
		"new":
			seating.checkpoint()
			seating.clear()
			seating.add_table("round", 8, 200, 200, "Table 1")
			seating.add_table("round", 8, 600, 200, "Table 2")
			_view.select_guest(-1)
			_changed()
			_view.fit()
			_show_page("guests")
			_show_toast("A new event with two tables. Paste your guest list to start.", 4.0)
		"example":
			seating.checkpoint()
			seating.load_example()
			_view.select_guest(-1)
			_changed()
			_view.fit()
		"open": _open_file()
		"save": _download(seating.to_json().to_utf8_buffer(), "%s.seatwise.json" % _file_base(), "application/json")
		"chart": _download_chart()
		"list": _download_seat_list()
		"csv": _download(seating.to_csv().to_utf8_buffer(), "%s-guests.csv" % _file_base(), "text/csv")
		"clear":
			seating.checkpoint()
			seating.clear_seats(true)
			seating.drop_checkpoint_if_unchanged()
			_changed()
			_show_toast("Everyone is off their seat, except locked seats.")
		"help": _open_help()


func _show_toast(text: String, seconds := 2.8) -> void:
	_toast.text = text
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.custom_minimum_size = Vector2.ZERO
	_toast.reset_size()
	if _toast.size.x > _view.size.x - 24.0:
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast.custom_minimum_size = Vector2(_view.size.x - 24.0, 0)
		_toast.reset_size()
	_toast.visible = true
	_toast.position = Vector2(maxf(12.0, (_view.size.x - _toast.size.x) / 2.0), _view.size.y - _toast.size.y - 62.0)
	_toast_timer.start(seconds)


func _unhandled_input(event: InputEvent) -> void:
	if _overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_close_sheet()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var key := event as InputEventKey
	var command := key.ctrl_pressed or key.meta_pressed
	var handled := true
	if command and key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
	elif command and key.keycode == KEY_Y:
		_redo()
	elif command and key.keycode == KEY_S:
		_on_menu("save")
	elif command and key.keycode == KEY_O:
		_open_file()
	elif command or key.alt_pressed:
		handled = false
	else:
		match key.keycode:
			KEY_DELETE:
				if _view.selected_guest != -1:
					seating.checkpoint()
					seating.unseat(_view.selected_guest)
					seating.drop_checkpoint_if_unchanged()
					_changed()
			KEY_ESCAPE:
				_view.placing_guest = -1
				_view.select_guest(-1)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _view.zoom_center(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT: _view.zoom_center(1.0 / 1.25)
			KEY_0, KEY_KP_0: _view.fit()
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ Sheets

func _open_sheet(title: String) -> VBoxContainer:
	for child in _sheet_box.get_children():
		_sheet_box.remove_child(child)
		child.queue_free()
	_sheet_box.add_child(_label(title, 21))
	_overlay.visible = true
	return _sheet_box


func _close_sheet() -> void:
	_overlay.visible = false
	_view.grab_focus()


func _open_paste_sheet() -> void:
	var box := _open_sheet("Paste a guest list")
	box.add_child(_label("One guest per line. Add a group and a meal after commas, or copy the columns straight from a spreadsheet.", 14, C_MUTED))
	var text := TextEdit.new()
	text.placeholder_text = "Family:\nTom & Lisa Meyer\nAnna Berg, Friends, vegetarian\nJo Kim +1"
	text.custom_minimum_size = Vector2(minf(520.0, size.x - 80.0), clampf(size.y * 0.35, 160.0, 320.0))
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(text)
	box.add_child(_label("\"Tom & Lisa Meyer\" adds a couple who sit together. \"+1\" adds a guest. A line like \"Family:\" sets the group for the lines below it.", 13, C_MUTED))
	var add := _button("Add guests", func() -> void:
		seating.checkpoint()
		var before := seating.guests.size()
		var added := seating.import_text(text.text)
		seating.drop_checkpoint_if_unchanged()
		_close_sheet()
		_changed()
		_show_page("guests")
		if added.is_empty():
			_show_toast("No guests found in that text.")
		else:
			var note := " (the limit is %d guests)" % Seating.MAX_GUESTS if seating.guests.size() >= Seating.MAX_GUESTS and before + added.size() >= Seating.MAX_GUESTS else ""
			_show_toast("Added %d guests%s. Press Seat everyone when you are ready." % [added.size(), note], 4.0), true)
	var cancel := _button("Cancel", _close_sheet)
	box.add_child(_row(_expand([cancel, add])))
	text.grab_focus.call_deferred()


## A sheet to pick another guest (search as you type).
func _pick_other(title: String, exclude: int, chosen: Callable) -> void:
	var box := _open_sheet(title)
	var search := LineEdit.new()
	search.placeholder_text = "Type a name"
	search.custom_minimum_size = Vector2(minf(440.0, size.x - 80.0), 42)
	box.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, clampf(size.y * 0.4, 160.0, 360.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	box.add_child(scroll)
	var fill := func(query: String) -> void:
		for child in list.get_children():
			child.queue_free()
		var q := query.strip_edges().to_lower()
		var shown := 0
		var sorted := seating.guests.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Seating.sort_key(a.name) < Seating.sort_key(b.name))
		for g: Dictionary in sorted:
			if g.id == exclude or (q != "" and not g.name.to_lower().contains(q)):
				continue
			var gid: int = g.id
			list.add_child(_list_row(g.name, _seat_text(gid), _view.group_color(g.group), func() -> void:
				_close_sheet()
				chosen.call(gid)))
			shown += 1
			if shown >= 80:
				break
	search.text_changed.connect(fill)
	fill.call("")
	box.add_child(_button("Cancel", _close_sheet))
	search.grab_focus.call_deferred()


func _open_help() -> void:
	var box := _open_sheet("How to use Seatwise")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_color_override("default_color", C_TEXT)
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.custom_minimum_size = Vector2(minf(540.0, size.x - 70.0), 0)
	text.text = "\n".join([
		"[b]1. Guests.[/b] Paste your list under Guests. \"Tom & Lisa Meyer\" is a couple, \"+1\" brings a guest, and \"Family:\" lines set groups. Add meals after a comma.",
		"[b]2. Tables.[/b] Add round, long or head tables under Tables, drag them where they stand in the room, and set how many seats each has.",
		"[b]3. Wishes.[/b] Tap a guest to say who they sit with and who they should not share a table with. Lock a seat to keep someone exactly where they are.",
		"[b]4. Seat everyone.[/b] Seatwise fills the tables for you: households side by side, groups together, everyone you keep apart at different tables. Run it again for another good option, or drag people to fine-tune. Drop someone on a taken seat to swap.",
		"[b]5. Share it.[/b] The menu downloads the seating chart and an alphabetical seat list as pictures, and the guest list as CSV for a spreadsheet.",
		"",
		"Mouse wheel or + and - zoom, drag the floor to move around, two fingers on touch screens. Ctrl+Z undoes.",
		"Your plan stays in this browser and nothing is uploaded. Save it as a file to keep a copy.",
		"[color=#9aa3b5]Seatwise 1.0 · made with Godot 4.7 · MIT licence[/color]",
	])
	box.add_child(text)
	var close := _button("Close", _close_sheet)
	box.add_child(close)
	close.grab_focus.call_deferred()


# ------------------------------------------------------------------ Files

func _file_base() -> String:
	var base := seating.title.to_lower().validate_filename().replace(" ", "-").replace("(", "").replace(")", "")
	return base if base != "" else "seating"


func _download(bytes: PackedByteArray, file_name: String, mime: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, file_name, mime)
		_show_toast("Downloaded %s" % file_name)
	else:
		DirAccess.make_dir_recursive_absolute("user://exports")
		var path := "user://exports/" + file_name
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out:
			out.store_buffer(bytes)
			out.close()
		_show_toast("Saved " + ProjectSettings.globalize_path(path))


func _picture_header(frame: Control, width: float, subtitle: String) -> void:
	var title := Label.new()
	title.text = seating.title
	title.position = Vector2(48, 26)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("2b2721"))
	frame.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	sub.position = Vector2(50, 80)
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color("6b6355"))
	frame.add_child(sub)


func _render(viewport_size: Vector2i, build: Callable) -> Image:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var frame := Control.new()
	frame.size = Vector2(viewport_size)
	frame.theme = get_tree().root.theme
	var white := ColorRect.new()
	white.color = Color.WHITE
	white.size = Vector2(viewport_size)
	frame.add_child(white)
	viewport.add_child(frame)
	build.call(frame)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


func _download_chart() -> void:
	var area := _view.content_rect()
	var scale := clampf(2200.0 / maxf(area.size.x, area.size.y), 0.6, 1.6)
	var header := 130.0
	var size_px := Vector2i(Vector2(area.size.x * scale + 80.0, area.size.y * scale + header + 40.0))
	var seated := seating.guests.size() - seating.unseated().size()
	var image: Image = await _render(size_px, func(frame: Control) -> void:
		_picture_header(frame, size_px.x, "%d guests at %d tables" % [seated, seating.tables.size()])
		var picture := VenueView.new()
		picture.export_mode = true
		picture.text_scale = 1.5
		picture.seating = seating
		picture.position = Vector2(40, header)
		picture.size = Vector2(size_px) - Vector2(80, header + 40.0)
		frame.add_child(picture)
		picture.refresh()
		picture.fit())
	_download(image.save_png_to_buffer(), "%s-seating-chart.png" % _file_base(), "image/png")


## An alphabetical "find your seat" list in columns, ready to print for the entrance.
func _download_seat_list() -> void:
	var rows := seating.seat_list()
	var columns := 1 if rows.size() <= 25 else (2 if rows.size() <= 70 else 3)
	var per_column := ceili(rows.size() / float(columns))
	var line := 40.0
	var header := 150.0
	var size_px := Vector2i(int(560 * columns + 80), int(header + per_column * line + 60))
	var image: Image = await _render(size_px, func(frame: Control) -> void:
		_picture_header(frame, size_px.x, "Find your seat")
		for i in rows.size():
			var col := i / per_column
			var row := i % per_column
			var name := Label.new()
			name.text = rows[i][0]
			name.position = Vector2(48 + col * 560, header + row * line)
			name.size = Vector2(360, line)
			name.clip_text = true
			name.add_theme_font_size_override("font_size", 24)
			name.add_theme_color_override("font_color", Color("2b2721"))
			frame.add_child(name)
			var where := Label.new()
			where.text = rows[i][1] if rows[i][1] != "" else "-"
			where.position = Vector2(48 + col * 560 + 370, header + row * line)
			where.size = Vector2(160, line)
			where.clip_text = true
			where.add_theme_font_size_override("font_size", 24)
			where.add_theme_color_override("font_color", Color("3f6df2"))
			frame.add_child(where))
	_download(image.save_png_to_buffer(), "%s-seat-list.png" % _file_base(), "image/png")


func _open_file() -> void:
	if not OS.has_feature("web"):
		_show_toast("Drop a .seatwise.json plan or a .csv guest list onto the window")
		return
	if _file_callback == null:
		_file_callback = JavaScriptBridge.create_callback(_on_web_file)
		JavaScriptBridge.eval("""
			window.seatwiseOpen = function (done) {
				const input = document.createElement('input');
				input.type = 'file';
				input.accept = '.json,.csv,.txt,.tsv,application/json,text/csv,text/plain';
				input.addEventListener('change', function () {
					const file = input.files && input.files[0];
					if (!file) { return; }
					if (file.size > 2 * 1024 * 1024) { done('', file.name, 'too-big'); return; }
					file.text().then(function (text) { done(text, file.name, ''); }, function () { done('', file.name, 'read-error'); });
				});
				input.click();
			};
		""", true)
	var window := JavaScriptBridge.get_interface("window")
	window.seatwiseOpen(_file_callback)


func _on_web_file(args: Array) -> void:
	var problem: String = str(args[2]) if args.size() > 2 else ""
	if problem == "too-big":
		_show_toast("That file is too big for a guest list")
	elif problem != "":
		_show_toast("The browser could not read that file")
	else:
		_open_text(str(args[0]), str(args[1]))


func _on_files_dropped(files: PackedStringArray) -> void:
	if not files.is_empty():
		_open_text(FileAccess.get_file_as_string(files[0]), files[0].get_file())


## Opens a saved plan, or adds the guests of a CSV or text list.
func _open_text(text: String, file_name: String) -> void:
	if text.strip_edges().begins_with("{"):
		var trial := Seating.new()
		var error := trial.from_json(text)
		if error != "":
			_show_toast(error)
			return
		seating.checkpoint()
		seating.from_json(text)
		_view.select_guest(-1)
		_changed()
		_view.fit()
		_show_toast("Opened %s" % file_name)
		return
	seating.checkpoint()
	var added := seating.import_text(text)
	seating.drop_checkpoint_if_unchanged()
	_changed()
	_show_page("guests")
	_show_toast("Added %d guests from %s" % [added.size(), file_name] if not added.is_empty() else "No guests found in %s" % file_name)


func _notification(what: int) -> void:
	# Save at once when the tab is left or closed, instead of waiting for the timer.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _save_timer and not _save_timer.is_stopped():
			_save_timer.stop()
			_save_now()
