class_name GuestPage
extends VBoxContainer
## The Guests tab: a summary, "Paste a guest list" and "Add a guest", a search box, and every guest,
## those waiting for a seat first.

signal paste_requested
signal add_requested
signal guest_picked(id: int)

var seating: Seating
var view: VenueView
var _summary: Label
var _search: LineEdit
var _list: VBoxContainer


func _init(plan: Seating, plan_view: VenueView) -> void:
	seating = plan
	view = plan_view
	add_theme_constant_override("separation", 8)
	_summary = Ui.label("", 15, UiTheme.MUTED)
	add_child(_summary)
	add_child(Ui.row(Ui.expand([Ui.button("Paste a guest list", paste_requested.emit), Ui.button("Add a guest", add_requested.emit)])))
	_search = LineEdit.new()
	_search.placeholder_text = "Find a guest"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 42)
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	add_child(_search)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)


func refresh() -> void:
	var seated := seating.guests.size() - seating.unseated().size()
	_summary.text = "%d guests · %d seated · %d seats at %d tables" % [seating.guests.size(), seated, seating.capacity(), seating.tables.size()]
	Ui.clear(_list)
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
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Seating.sort_key(a.name) < Seating.sort_key(b.name))
	if not waiting.is_empty():
		_list.add_child(Ui.heading("Waiting for a seat (%d)" % waiting.size()))
		for g in waiting:
			_list.add_child(_row(g))
	if not placed.is_empty():
		_list.add_child(Ui.heading("Seated (%d)" % placed.size()))
		for g in placed:
			_list.add_child(_row(g))
	if seating.guests.is_empty():
		_list.add_child(Ui.label("No guests yet. Paste your list: one guest per line, or \"Tom & Lisa Meyer\" for a couple.", 15, UiTheme.MUTED))
	elif waiting.is_empty() and placed.is_empty():
		_list.add_child(Ui.label("Nobody matches \"%s\"." % _search.text, 15, UiTheme.MUTED))


## Where a guest sits, in a word: the table's name, or "waiting".
static func seat_text(plan: Seating, guest_id: int) -> String:
	var s := plan.seat_of(guest_id)
	return "waiting" if s.is_empty() else plan.get_table(s.table).name


func _row(g: Dictionary) -> Button:
	var id: int = g.id
	var chosen: bool = id == view.selected_guest or id == view.placing_guest
	var row := Ui.list_row(g.name, seat_text(seating, id), view.group_color(g.group), func() -> void: guest_picked.emit(id), chosen)
	row.tooltip_text = ("%s · %s" % [g.group, g.diet]).strip_edges().trim_prefix("·").trim_suffix("·").strip_edges()
	return row
