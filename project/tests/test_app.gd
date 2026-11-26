extends SceneTree
## Runs the whole editor without a window and checks that its parts work together: the first visit,
## Seat everyone, the status badge, toasts, the menu, dialogs, pasting, the guest limit, saving and
## opening files, and the phone layout. The plan is kept in a test file, never in the real one.
## Run from the repository root: godot --headless --path project --script res://tests/test_app.gd
## Exits with 1 when a check fails.

const TEST_PLAN := "user://test-app-plan.json"
const BIG_FILE := "user://test-app-big.csv"

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, what: String) -> void:
	checks += 1
	if condition:
		print("  ok  ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


func _run() -> void:
	DirAccess.remove_absolute(TEST_PLAN)
	root.size = Vector2i(1440, 900)
	var main := await _open_editor()
	_first_visit(main)
	await _seat_everyone(main)
	await _status_badge(main)
	await _toast(main)
	await _menu(main)
	await _new_event(main)
	await _paste(main)
	_guest_limit(main)
	await _selection(main)
	_files(main)
	await _phone_layout(main)
	main.queue_free()
	await process_frame
	await _unreadable_plan()
	DirAccess.remove_absolute(TEST_PLAN)
	DirAccess.remove_absolute(BIG_FILE)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _open_editor() -> Control:
	var main: Control = load("res://main.tscn").instantiate()
	main._files.plan_path = TEST_PLAN
	root.add_child(main)
	await _frames(3)
	return main


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## The buttons with this text anywhere under a node.
func _buttons(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == text and b.is_visible_in_tree())


func _press(node: Node, text: String) -> bool:
	var found := _buttons(node, text)
	if found.is_empty():
		return false
	(found[0] as Button).pressed.emit()
	return true


func _first_visit(main: Control) -> void:
	print("first visit")
	var plan: Seating = main.seating
	check(plan.guests.size() == 38 and plan.title == "Wedding dinner (example)", "a first visit opens the example wedding")
	check(main._panel.toast.visible and main._panel.toast.text.begins_with("An example wedding"), "and says so in a toast")
	check(main._panel.status.text == "36 waiting for a seat", "the badge counts who waits (%s)" % main._panel.status.text)
	check(main._side.guests.visible and not main._side.tables.visible, "the Guests tab is open")


func _seat_everyone(main: Control) -> void:
	print("seat everyone")
	var plan: Seating = main.seating
	await main._seat_everyone()
	check(plan.unseated().is_empty() and plan.wish_problems().is_empty(), "Seat everyone seats the example with every wish kept")
	check(main._panel.status.text == "Everyone seated, every wish kept", "the badge says so")
	check(main._panel.seat_button.text == "Seat everyone" and not main._panel.seat_button.disabled and not main._view.busy, "the button is back when done")
	check(plan.can_undo() and not main._undo_button.disabled, "it can be undone")
	check(main._panel.toast.text.begins_with("Done."), "a toast says it is done")


func _status_badge(main: Control) -> void:
	print("status badge")
	var plan: Seating = main.seating
	plan.checkpoint()
	var karl := plan.find_guest("Karl Lindqvist")
	var henrik := plan.find_guest("Henrik Weber")
	var where := plan.seat_of(henrik)
	plan.seat(karl, where.table, (where.seat + 2) % plan.get_table(where.table).seats)
	main._changed()
	await _frames(2)
	var badge: Button = main._panel.status
	check(badge.text.ends_with("to look at"), "a broken wish turns the badge into \"... to look at\" (%s)" % badge.text)
	var margins := {}
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := badge.get_theme_stylebox(state)
		margins[Vector2(box.content_margin_left, box.content_margin_right)] = true
	check(margins.size() == 1, "every state of the badge has the same padding, so pressing it never clips the text")
	check(badge.size.x >= badge.get_minimum_size().x, "the badge is as wide as its text")
	badge.pressed.emit()
	await _frames(1)
	check(main._view.selected_guest != -1 and main._side.inspector.visible, "pressing it selects someone involved")
	check(badge.size.x >= badge.get_minimum_size().x, "and the badge still fits its text")
	main._undo()


func _toast(main: Control) -> void:
	print("toast")
	main._panel.show_toast("A long message that does not fit on one line on a phone, so it wraps onto a second line and grows upwards above the zoom buttons.", 3.0)
	await _frames(2)
	var toast: Label = main._panel.toast
	var zoom: Control = main._panel.zoom_box
	check(toast.get_rect().end.y <= zoom.get_rect().position.y - 8.0, "the toast sits above the zoom buttons (%s, %s)" % [toast.get_rect(), zoom.get_rect()])
	check(toast.get_rect().position.x >= 0.0 and toast.get_rect().end.x <= main._view.size.x, "the toast stays inside the plan")


func _menu(main: Control) -> void:
	print("menu")
	main._menu.open()
	await _frames(1)
	var menu: PopupMenu = main._menu.popup
	var button := Rect2(main._menu.get_screen_position(), main._menu.size)
	check(menu.visible, "the menu opens")
	check(menu.position.x + menu.size.x == int(button.end.x), "its right edge lines up with the Menu button")
	check(menu.position.x + menu.size.x <= main.size.x - 8, "and keeps 8 px from the window edge")
	menu.hide()


func _new_event(main: Control) -> void:
	print("new event")
	var plan: Seating = main.seating
	main._on_menu("new")
	await _frames(1)
	check(main._sheets.visible and plan.guests.size() == 38, "New event asks first and changes nothing yet")
	check(_press(main._sheets, "Cancel") and not main._sheets.visible and plan.guests.size() == 38, "Cancel keeps the plan")
	main._on_menu("new")
	await _frames(1)
	check(_press(main._sheets, "Start a new event"), "the dialog has a button to go ahead")
	check(plan.guests.is_empty() and plan.tables.size() == 2, "a new event has no guests and two tables")
	main._undo()
	check(plan.guests.size() == 38, "undo brings the plan back")


func _paste(main: Control) -> void:
	print("paste")
	var plan: Seating = main.seating
	main._open_paste_sheet()
	await _frames(1)
	var boxes: Array = main._sheets.find_children("*", "TextEdit", true, false)
	check(boxes.size() == 1, "the paste dialog has a text box")
	check(_buttons(main._sheets, "Paste from clipboard").is_empty(), "outside a browser there is no clipboard button")
	(boxes[0] as TextEdit).text = "Name,Group,Diet\n\"Lee, Ann\",Work,vegan\nTom & Lisa Meyer"
	_press(main._sheets, "Add guests")
	await _frames(1)
	check(not main._sheets.visible and plan.guests.size() == 41, "Add guests adds a quoted CSV row and a couple")
	check(plan.get_guest(plan.find_guest("Lee, Ann")).diet == "vegan", "the quoted name keeps its comma")
	check(main._panel.toast.text.begins_with("Added 3 guests."), "a toast counts them (%s)" % main._panel.toast.text)
	main._undo()


func _guest_limit(main: Control) -> void:
	print("guest limit")
	var plan: Seating = main.seating
	plan.checkpoint()
	while plan.room_for_guests() > 0:
		plan.add_guest("Extra")
	main._add_one_guest()
	check(plan.guests.size() == Seating.MAX_GUESTS and main._panel.toast.text.contains("at most 600"), "Add a guest stops at the limit and says why")
	main._open_text("Ann Lee\nBo Kim", "more.csv")
	check(plan.guests.size() == Seating.MAX_GUESTS and main._panel.toast.text.contains("limit is 600"), "an opened list stops at the limit and says why")
	main._undo()
	main._undo()
	check(plan.guests.size() == 38, "and undo goes back")


func _selection(main: Control) -> void:
	print("selection")
	var plan: Seating = main.seating
	var amira := plan.find_guest("Amira Haddad")
	main._pick_guest(amira)
	await _frames(1)
	var fields: Array = main._side.inspector.find_children("*", "LineEdit", true, false)
	check(main._side.guests.visible or main._side.inspector.visible, "picking a guest in the list shows them")
	main._side.show_page("piece")
	check(not fields.is_empty() and (fields[0] as LineEdit).text == "Amira Haddad", "the Selected tab shows the guest's name")
	var meals := _buttons(main._side.inspector, "Vegan")
	check(not meals.is_empty() and (meals[0] as Button).size.y >= Ui.TAP, "meal buttons are big enough to tap")
	_press(main._side.inspector, "Vegan")
	check(plan.get_guest(amira).diet == "vegan", "a meal button sets the meal")
	main._undo()
	var table: Dictionary = plan.tables[1]
	main._view.select_table(table.id)
	await _frames(1)
	check(not _buttons(main._side.inspector, "Clear this table").is_empty(), "selecting a table shows the table")
	main._view.select_guest(-1)


func _files(main: Control) -> void:
	print("files")
	var plan: Seating = main.seating
	main._save_now()
	check(FileAccess.file_exists(TEST_PLAN) and not main._save_failed, "the plan is saved")
	var copy := Seating.new()
	check(copy.from_json(FileAccess.get_file_as_string(TEST_PLAN)) == "" and copy.guests.size() == plan.guests.size(), "the saved plan reads back")
	main._files.plan_path = "user://no/such/folder/plan.json"
	main._save_now()
	check(main._save_failed and main._panel.toast.text.begins_with("Could not save in this browser"), "a failed save is reported")
	main._files.plan_path = TEST_PLAN
	main._save_now()
	check(not main._save_failed, "and clears when saving works again")
	main._open_text("{\"app\": \"other\"}", "x.json")
	check(main._panel.toast.text == "This is not a Seatwise plan." and plan.guests.size() == 38, "a foreign JSON file is refused")
	var big := FileAccess.open(BIG_FILE, FileAccess.WRITE)
	big.store_string("x".repeat(FileIO.MAX_FILE_BYTES + 10))
	big.close()
	main._files.read_dropped(ProjectSettings.globalize_path(BIG_FILE))
	check(main._panel.toast.text == "That file is too big for a guest list" and plan.guests.size() == 38, "a dropped file over 2 MB is refused")
	var saved := plan.to_json()
	plan.checkpoint()
	plan.clear()
	main._open_text(saved, "wedding.seatwise.json")
	check(plan.guests.size() == 38 and main._panel.toast.text == "Opened wedding.seatwise.json", "opening a saved plan loads it")


func _phone_layout(main: Control) -> void:
	print("phone layout")
	root.size = Vector2i(390, 844)
	await _frames(3)
	check(main._body.vertical, "a phone puts the side panel under the plan")
	var padding: MarginContainer = main._side.scroll.get_child(0)
	check(padding.get_theme_constant("margin_bottom") >= 56, "the lists end with room for the corner button")
	main._panel.show_toast("Done. Couples sit together, groups share tables, and every wish is kept.", 3.0)
	await _frames(2)
	var toast: Rect2 = main._panel.toast.get_rect()
	check(toast.end.y <= main._panel.zoom_box.get_rect().position.y - 8.0, "on a phone the toast wraps and stays above the zoom buttons")
	check(toast.position.x >= 0.0 and toast.end.x <= main._view.size.x, "and inside the plan")
	main._menu.open()
	await _frames(1)
	var button := Rect2(main._menu.get_screen_position(), main._menu.size)
	check(main._menu.popup.position.x + main._menu.popup.size.x == int(button.end.x) and main._menu.popup.position.x >= 0, "on a phone the menu lines up with its button too")
	main._menu.popup.hide()
	root.size = Vector2i(1440, 900)
	await _frames(3)
	check(not main._body.vertical, "a wide window puts it beside the plan")


func _unreadable_plan() -> void:
	print("unreadable saved plan")
	var file := FileAccess.open(TEST_PLAN, FileAccess.WRITE)
	file.store_string("{ broken")
	file.close()
	var main := await _open_editor()
	check(main.seating.guests.size() == 38, "an unreadable saved plan opens the example instead")
	check(main._panel.toast.text.begins_with("Your saved plan could not be read"), "and says so")
	main.queue_free()
	await process_frame
