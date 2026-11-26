class_name Sheets
extends Control
## The dialogs: a panel in the middle of a dimmed screen. Paste a guest list, pick a guest, confirm,
## help, and the licences. Esc or a tap on the dimmed screen closes them.

signal closed

const SOURCE_URL := "https://github.com/iSquare-Lab/seatwise"
const GODOT_NOTICES_URL := "https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt"
const MAX_PICK_ROWS := 80

var _box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)


## Opens an empty sheet with a title and returns the box to fill.
func open(title: String) -> VBoxContainer:
	Ui.clear(_box)
	_box.add_child(Ui.label(title, 21))
	visible = true
	return _box


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## The widest a sheet's content may be on this screen.
func _width(most: float) -> float:
	return minf(most, get_viewport_rect().size.x - 80.0)


## "Paste a guest list". add gets the text. read_clipboard, when valid, is offered as a button
## (for browsers where pasting into the box is awkward): it takes a Callable that receives the text.
func paste(add: Callable, read_clipboard: Callable) -> void:
	var box := open("Paste a guest list")
	box.add_child(Ui.label("One guest per line. Add a group and a meal after commas, or copy the columns straight from a spreadsheet.", 14, UiTheme.MUTED))
	var text := TextEdit.new()
	text.placeholder_text = "Family:\nTom & Lisa Meyer\nAnna Berg, Friends, vegetarian\nJo Kim +1"
	text.custom_minimum_size = Vector2(_width(520.0), clampf(get_viewport_rect().size.y * 0.35, 160.0, 320.0))
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(text)
	box.add_child(Ui.label("\"Tom & Lisa Meyer\" adds a couple who sit together. \"+1\" adds a guest. A line like \"Family:\" sets the group for the lines below it.", 13, UiTheme.MUTED))
	var buttons := [Ui.button("Cancel", close)]
	if read_clipboard.is_valid():
		# In the browser Godot only learns the clipboard after Ctrl+V, so the first Ctrl+V would paste
		# what was copied before. Reading the clipboard here pastes the right text the first time.
		text.gui_input.connect(func(event: InputEvent) -> void:
			var key := event as InputEventKey
			if key != null and key.pressed and key.keycode == KEY_V and (key.ctrl_pressed or key.meta_pressed) and not key.shift_pressed:
				text.accept_event()
				read_clipboard.call(func(pasted: String) -> void:
					if is_instance_valid(text):
						text.insert_text_at_caret(pasted)))
		buttons.append(Ui.button("Paste from clipboard", func() -> void:
			read_clipboard.call(func(pasted: String) -> void:
				if is_instance_valid(text) and pasted != "":
					text.text = pasted if text.text.strip_edges() == "" else text.text.rstrip("\n") + "\n" + pasted
					text.grab_focus())))
	buttons.append(Ui.button("Add guests", func() -> void:
		var pasted := text.text
		close()
		add.call(pasted), true))
	box.add_child(Ui.row(Ui.expand(buttons)))
	text.grab_focus.call_deferred()


## Lets the user pick a guest other than `exclude` (search as you type). chosen gets their id.
func pick_guest(title: String, plan: Seating, view: VenueView, exclude: int, chosen: Callable) -> void:
	var box := open(title)
	var search := LineEdit.new()
	search.placeholder_text = "Type a name"
	search.custom_minimum_size = Vector2(_width(440.0), 42)
	box.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, clampf(get_viewport_rect().size.y * 0.4, 160.0, 360.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	box.add_child(scroll)
	var sorted := plan.guests.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Seating.sort_key(a.name) < Seating.sort_key(b.name))
	var fill := func(query: String) -> void:
		Ui.clear(list)
		var q := query.strip_edges().to_lower()
		var shown := 0
		for g: Dictionary in sorted:
			if g.id == exclude or (q != "" and not g.name.to_lower().contains(q)):
				continue
			var gid: int = g.id
			list.add_child(Ui.list_row(g.name, GuestPage.seat_text(plan, gid), view.group_color(g.group), func() -> void:
				close()
				chosen.call(gid)))
			shown += 1
			if shown >= MAX_PICK_ROWS:
				break
		if shown == 0:
			list.add_child(Ui.label("Nobody matches." if q != "" else "There is nobody else on the list yet.", 15, UiTheme.MUTED))
	search.text_changed.connect(fill)
	fill.call("")
	box.add_child(Ui.button("Cancel", close))
	search.grab_focus.call_deferred()


## Asks before something big happens (it can still be undone).
func confirm(title: String, text: String, ok_text: String, action: Callable) -> void:
	var box := open(title)
	var message := Ui.label(text, 15, UiTheme.MUTED)
	message.custom_minimum_size = Vector2(_width(420.0), 0)
	box.add_child(message)
	var ok := Ui.button(ok_text, func() -> void:
		close()
		action.call(), true)
	box.add_child(Ui.row(Ui.expand([Ui.button("Cancel", close), ok])))
	ok.grab_focus.call_deferred()


func help(touch: bool) -> void:
	var box := open("How to use Seatwise")
	var how_to_move := "Drag the floor to move around, and pinch with two fingers to zoom." if touch else "Mouse wheel or + and - zoom, 0 shows every table, and dragging the floor moves around. Ctrl+Z undoes, Ctrl+S saves the plan as a file."
	var text := _rich_text(540.0, [
		"[b]1. Guests.[/b] Paste your list under Guests. \"Tom & Lisa Meyer\" is a couple, \"+1\" brings a guest, and \"Family:\" lines set groups. Add meals after a comma.",
		"[b]2. Tables.[/b] Add round, long or head tables under Tables, drag them where they stand in the room, and set how many seats each has.",
		"[b]3. Wishes.[/b] Tap a guest to say who they sit with and who they should not share a table with. Lock a seat to keep someone exactly where they are.",
		"[b]4. Seat everyone.[/b] Seatwise fills the tables for you: households side by side, groups together, everyone you keep apart at different tables. Run it again for another good option, or drag people to fine-tune. Drop someone on a taken seat to swap.",
		"[b]5. Share it.[/b] The menu downloads the seating chart and an alphabetical seat list as pictures, and the guest list as CSV for a spreadsheet.",
		"",
		how_to_move,
		"Your plan stays in this browser and nothing is uploaded. Save it as a file to keep a copy.",
		"[color=#9aa3b5]Seatwise 1.0 · © 2026 iSquare Lab · MIT licence · [url=%s]Source on GitHub[/url] · [url=licences]Licences[/url][/color]" % SOURCE_URL,
	])
	box.add_child(text)
	var close_button := Ui.button("Close", close)
	box.add_child(close_button)
	close_button.grab_focus.call_deferred()


## The licences of what ships in the App: Seatwise itself, and the Godot Engine with its parts.
func licences() -> void:
	var box := open("Licences")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(_width(560.0), clampf(get_viewport_rect().size.y * 0.5, 200.0, 460.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var text := _rich_text(0.0, [
		"[b]Seatwise[/b] · © 2026 iSquare Lab · MIT licence · [url=%s]source[/url]" % SOURCE_URL,
		"",
		"[b]Godot Engine[/b] (this App runs on it)",
		Engine.get_license_text().strip_edges(),
		"",
		"The engine includes code and fonts by others under their own licences (MIT, BSD, Apache 2.0, zlib, OFL 1.1 and others), among them FreeType, HarfBuzz, ICU, Brotli, Zstandard, libpng, ThorVG and the Open Sans font. Portions of this software are copyright © The FreeType Project (www.freetype.org). All rights reserved. The full notices are in [url=%s]Godot's COPYRIGHT.txt[/url]." % GODOT_NOTICES_URL,
	])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	box.add_child(scroll)
	var close_button := Ui.button("Close", close)
	box.add_child(close_button)
	close_button.grab_focus.call_deferred()


func _rich_text(width: float, lines: Array) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_color_override("default_color", UiTheme.TEXT)
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	if width > 0.0:
		text.custom_minimum_size = Vector2(_width(width), 0)
	text.text = "\n".join(lines)
	text.meta_clicked.connect(func(meta: Variant) -> void:
		if str(meta) == "licences":
			licences()
		else:
			OS.shell_open(str(meta)))
	return text
