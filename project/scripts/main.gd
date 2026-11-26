extends Control
## Seatwise: the editor screen. Lays out the top bar, the plan (PlanPanel) and the side panel
## (SidePanel), and wires them to the plan: every change goes through _changed(), which redraws,
## updates the lists and saves a moment later.
##
## The other parts: Sheets (the dialogs), MainMenu, SeatingSolver (Seat everyone), PictureExport
## (the PNGs) and FileIO (files and the browser). The model is Seating.

## From this width (and a landscape window) the side panel sits beside the plan instead of below it.
const WIDE_MIN := 760.0

var seating := Seating.new()
var _files := FileIO.new()
var _panel: PlanPanel
var _view: VenueView
var _side: SidePanel
var _body: BoxContainer
var _undo_button: Button
var _redo_button: Button
var _menu: MainMenu
var _sheets: Sheets
var _save_timer: Timer
var _wide := false
var _laid_out := false
var _solving := false
var _save_failed := false


func _ready() -> void:
	get_tree().root.theme = UiTheme.make_theme()
	var notice := _load_plan()
	_build()
	_files.file_opened.connect(_open_text)
	_files.failed.connect(_panel.show_toast)
	resized.connect(_layout)
	_layout()
	get_window().files_dropped.connect(func(files: PackedStringArray) -> void:
		if not files.is_empty():
			_files.read_dropped(files[0]))
	_changed(false)
	_side.show_page("guests")
	await get_tree().process_frame
	_view.fit()
	_panel.show_toast(notice, 6.0)


# ------------------------------------------------------------------ Building

func _build() -> void:
	var back := ColorRect.new()
	back.color = UiTheme.BG
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
	root.add_child(_build_top_bar())
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	root.add_child(_body)

	_panel = PlanPanel.new(seating)
	_panel.seat_everyone_pressed.connect(_seat_everyone)
	_panel.status_pressed.connect(_show_first_problem)
	_view = _panel.view
	_view.selection_changed.connect(_on_selection_changed)
	_view.edited.connect(func() -> void: _changed())
	_view.seat_tapped.connect(_on_seat_tapped)
	_body.add_child(_panel)

	_side = SidePanel.new(seating, _view)
	_side.guests.paste_requested.connect(_open_paste_sheet)
	_side.guests.add_requested.connect(_add_one_guest)
	_side.guests.guest_picked.connect(_pick_guest)
	_side.tables.edited.connect(func() -> void: _changed())
	_side.tables.add_table_requested.connect(_add_table)
	_side.inspector.edited.connect(func() -> void: _changed())
	_side.inspector.toast_requested.connect(_panel.show_toast)
	_side.inspector.pick_requested.connect(func(title: String, exclude: int, chosen: Callable) -> void:
		_sheets.pick_guest(title, seating, _view, exclude, chosen))
	_body.add_child(_side)

	_sheets = Sheets.new()
	_sheets.closed.connect(_view.grab_focus)
	add_child(_sheets)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_now)
	add_child(_save_timer)


func _build_top_bar() -> HBoxContainer:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(30, 30)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(logo)
	var name_label := Ui.label("Seatwise", 20)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	_undo_button = Ui.icon_button("undo", "Undo (Ctrl+Z)", _undo)
	_redo_button = Ui.icon_button("redo", "Redo (Ctrl+Y)", _redo)
	top.add_child(_undo_button)
	top.add_child(_redo_button)
	_menu = MainMenu.new()
	_menu.chosen.connect(_on_menu)
	top.add_child(_menu)
	return top


# ------------------------------------------------------------------ Layout and state

func _layout() -> void:
	var wide := size.x >= WIDE_MIN and size.x > size.y * 1.05
	if wide == _wide and _laid_out:
		return
	_wide = wide
	_laid_out = true
	_body.vertical = not wide
	_side.set_wide(wide, size.y)
	_view.fit.call_deferred()


## Loads the saved plan, or the example on a first visit. Returns a message to show.
func _load_plan() -> String:
	var saved := _files.load_plan()
	if saved.found and seating.from_json(saved.text) == "":
		return ""
	seating.load_example()
	if saved.found:
		return "Your saved plan could not be read, so the example wedding is open instead."
	return "An example wedding with 38 guests. Press Seat everyone, then drag people around."


func _save_now() -> void:
	var ok := _files.save_plan(seating.to_json())
	if not ok and not _save_failed:
		_panel.show_toast("Could not save in this browser. Use Menu > Save the plan as a file to keep a copy.", 6.0)
	_save_failed = not ok


## Redraws and refreshes everything after a change, and saves it a moment later.
func _changed(save := true) -> void:
	_view.refresh()
	_undo_button.disabled = not seating.can_undo()
	_redo_button.disabled = not seating.can_redo()
	_files.announce(_panel.update_status(seating))
	_side.refresh()
	if save:
		_save_timer.start()


# ------------------------------------------------------------------ Actions

func _pick_guest(id: int) -> void:
	_view.select_guest(id)
	if seating.seat_of(id).is_empty():
		_view.placing_guest = id
		_panel.show_toast("Tap an empty seat for %s." % seating.get_guest(id).name)
	else:
		_view.placing_guest = -1
		_view.show_guest(id)
	_changed(false)


func _on_seat_tapped(table_id: int, index: int) -> void:
	var guest := _view.placing_guest if _view.placing_guest != -1 else _view.selected_guest
	if guest == -1:
		_panel.show_toast("Pick a guest first: in the list, or by tapping someone at a table.")
		return
	seating.checkpoint()
	seating.seat(guest, table_id, index)
	_view.placing_guest = -1
	_view.selected_guest = guest
	var next := seating.unseated()
	_changed()
	_panel.show_toast("%s: seat %d at %s." % [seating.get_guest(guest).name, index + 1, seating.get_table(table_id).name])
	# Keep going with whoever is next in their household, so couples are quick to seat.
	for m in seating.party_members(seating.get_guest(guest).party):
		if next.has(m):
			_view.placing_guest = m
			_view.selected_guest = m
			_panel.show_toast("Now tap a seat for %s." % seating.get_guest(m).name)
			_changed(false)
			break


func _on_selection_changed() -> void:
	if _view.selected_guest != _view.placing_guest:
		_view.placing_guest = -1
	_changed(false)
	if _view.selected_guest != -1 or _view.selected_table != -1:
		_side.show_page("piece")


func _show_first_problem() -> void:
	var wishes := seating.wish_problems()
	if wishes.is_empty():
		if not seating.unseated().is_empty():
			_side.show_page("guests")
		return
	var first: Dictionary = wishes[0]
	_panel.show_toast(first.text, 4.0)
	if not first.guests.is_empty():
		_view.select_guest(first.guests[0])
		_view.show_guest(first.guests[0])


func _add_one_guest() -> void:
	if seating.room_for_guests() == 0:
		_panel.show_toast("A plan holds at most %d guests." % Seating.MAX_GUESTS)
		return
	seating.checkpoint()
	var id := seating.add_guest("New guest")
	_view.select_guest(id)
	_changed()
	_side.show_page("piece")
	_side.inspector.focus_first_field()


func _add_table(shape: String, seats: int) -> void:
	seating.checkpoint()
	var at := _view.spot_for_new_table(shape, seats)
	var id := seating.add_table(shape, seats, at.x, at.y, "Head table" if shape == "head" else "")
	_view.select_table(id)
	_changed()
	_view.fit()


func _seat_everyone() -> void:
	if _solving:
		return
	if seating.tables.is_empty():
		_panel.show_toast("Add tables first, under Tables.")
		_side.show_page("tables")
		return
	if seating.guests.is_empty():
		_panel.show_toast("Add guests first: paste your list.")
		return
	_solving = true
	seating.checkpoint()
	# The solver's steps, spread over frames (about 25 ms of work each) so the screen stays smooth.
	var solver := SeatingSolver.new(seating, Time.get_ticks_usec())
	var more := true
	while more:
		var started := Time.get_ticks_msec()
		while more and Time.get_ticks_msec() - started < 25:
			more = solver.step()
		_panel.show_progress(solver.progress())
		_view.refresh()
		await get_tree().process_frame
	seating.drop_checkpoint_if_unchanged()
	_panel.show_progress(-1.0)
	_solving = false
	_changed()
	var wishes := seating.wish_problems()
	var waiting := seating.unseated().size()
	if waiting > 0 and seating.capacity() < seating.guests.size():
		_panel.show_toast("Not enough seats: %d still waiting. Add a table or more seats." % waiting, 5.0)
	elif wishes.is_empty():
		_panel.show_toast("Done. Couples sit together, groups share tables, and every wish is kept.", 5.0)
	else:
		_panel.show_toast("Done, but %d %s could not be kept. Tap the red box to see." % [wishes.size(), "wish" if wishes.size() == 1 else "wishes"], 5.0)


func _undo() -> void:
	if not _solving and seating.undo():
		_changed()


func _redo() -> void:
	if not _solving and seating.redo():
		_changed()


## Replaces the whole plan as one undo step: a new event, or the example.
func _replace_plan(fill: Callable, message: String) -> void:
	seating.checkpoint()
	fill.call()
	_view.select_guest(-1)
	_changed()
	_view.fit()
	_side.show_page("guests")
	_panel.show_toast(message, 4.0)


func _new_event() -> void:
	_replace_plan(func() -> void:
		seating.clear()
		seating.add_table("round", 8, 200, 200, "Table 1")
		seating.add_table("round", 8, 600, 200, "Table 2"), "A new event with two tables. Paste your guest list to start.")


func _open_example() -> void:
	_replace_plan(seating.load_example, "The example wedding: press Seat everyone.")


func _on_menu(action: String) -> void:
	if _solving:
		return
	var has_plan := not seating.guests.is_empty()
	match action:
		"new" when has_plan:
			_sheets.confirm("Start a new event?", "This takes every guest and table off the plan. Undo brings them back.", "Start a new event", _new_event)
		"new":
			_new_event()
		"example" when has_plan:
			_sheets.confirm("Open the example wedding?", "It replaces your plan. Undo brings yours back.", "Open the example", _open_example)
		"example":
			_open_example()
		"open":
			_files.pick_file()
		"save", "chart", "list", "csv":
			_download(action)
		"clear":
			seating.checkpoint()
			seating.clear_seats(true)
			seating.drop_checkpoint_if_unchanged()
			_changed()
			_panel.show_toast("Everyone is off their seat, except locked seats.")
		"help":
			_sheets.help(DisplayServer.is_touchscreen_available())


## Downloads the plan as a file, the seating chart or the seat list (PNG), or the guest list (CSV).
func _download(kind: String) -> void:
	var base := PlanFile.file_base(seating.title)
	var message := ""
	match kind:
		"save": message = _files.download(seating.to_json().to_utf8_buffer(), base + ".seatwise.json", "application/json")
		"chart": message = _files.download(await PictureExport.chart(self, seating), base + "-seating-chart.png", "image/png")
		"list": message = _files.download(await PictureExport.seat_list(self, seating), base + "-seat-list.png", "image/png")
		"csv": message = _files.download(seating.to_csv().to_utf8_buffer(), base + "-guests.csv", "text/csv")
	_panel.show_toast(message)


func _open_paste_sheet() -> void:
	var clipboard := _files.read_clipboard if _files.has_browser() else Callable()
	_sheets.paste(func(text: String) -> void: _add_guest_list(text, "that text"), clipboard)


## Opens a saved plan, or adds the guests of a CSV or text list.
func _open_text(text: String, file_name: String) -> void:
	if not text.strip_edges().begins_with("{"):
		_add_guest_list(text, file_name)
		return
	var data := PlanFile.parse(text)
	if data.error != "":
		_panel.show_toast(data.error)
		return
	seating.checkpoint()
	seating.apply(data)
	_view.select_guest(-1)
	_changed()
	_view.fit()
	_panel.show_toast("Opened %s" % file_name)


func _add_guest_list(text: String, source: String) -> void:
	seating.checkpoint()
	var result := GuestImport.read(seating, text)
	seating.drop_checkpoint_if_unchanged()
	_changed()
	_side.show_page("guests")
	var added: int = result.added.size()
	if added == 0 and not result.full:
		_panel.show_toast("No guests found in %s." % source)
		return
	var limit := " The limit is %d guests, so the rest were left out." % Seating.MAX_GUESTS if result.full else ""
	_panel.show_toast("Added %d %s.%s Press Seat everyone when you are ready." % [added, "guest" if added == 1 else "guests", limit], 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if _sheets.visible:
		if event.is_action_pressed("ui_cancel"):
			_sheets.close()
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	var focus := get_viewport().gui_get_focus_owner()
	if key == null or not key.pressed or key.echo or focus is LineEdit or focus is TextEdit:
		return
	if _shortcut(key):
		get_viewport().set_input_as_handled()


## Runs a keyboard shortcut. False when the key is not one.
func _shortcut(key: InputEventKey) -> bool:
	if key.ctrl_pressed or key.meta_pressed:
		match key.keycode:
			KEY_Z when key.shift_pressed: _redo()
			KEY_Z: _undo()
			KEY_Y: _redo()
			KEY_S: _on_menu("save")
			KEY_O: _on_menu("open")
			_: return false
		return true
	if key.alt_pressed:
		return false
	match key.keycode:
		KEY_DELETE when _view.selected_guest != -1:
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
		_: return false
	return true


func _notification(what: int) -> void:
	# Save at once when the tab is left or closed, instead of waiting for the timer.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _save_timer and not _save_timer.is_stopped():
			_save_timer.stop()
			_save_now()
