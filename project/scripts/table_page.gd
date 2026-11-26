class_name TablePage
extends VBoxContainer
## The Tables tab: the event name, buttons that add a table, the list of tables, and the meals to
## tell the caterer.

signal edited
signal add_table_requested(shape: String, seats: int)

const DEFAULT_TABLES := [
	["Round, 8", "round", 8], ["Round, 10", "round", 10], ["Long, 10", "rect", 10],
	["Long, 12", "rect", 12], ["Head table, 6", "head", 6], ["Small, 4", "rect", 4],
]

var seating: Seating
var view: VenueView
var _title_edit: LineEdit
var _list: VBoxContainer
var _catering: Label


func _init(plan: Seating, plan_view: VenueView) -> void:
	seating = plan
	view = plan_view
	add_theme_constant_override("separation", 10)
	_title_edit = Ui.field(seating.title, "Event name", _rename_event)
	add_child(Ui.labelled("Event name", _title_edit))
	add_child(Ui.heading("Add a table"))
	var adders := Ui.flow()
	for spec in DEFAULT_TABLES:
		var shape: String = spec[1]
		var count: int = spec[2]
		var b := Ui.button(spec[0], func() -> void: add_table_requested.emit(shape, count))
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(0, Ui.TAP)
		adders.add_child(b)
	add_child(adders)
	add_child(Ui.heading("Tables"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	add_child(Ui.heading("For the caterer"))
	_catering = Ui.label("", 15)
	add_child(_catering)


func refresh() -> void:
	if not _title_edit.has_focus():
		_title_edit.text = seating.title
	Ui.clear(_list)
	for t in seating.tables:
		var id: int = t.id
		var seated: int = t.guests.size() - t.guests.count(0)
		var diets := diet_text(seating.diet_counts(id))
		var row := Ui.list_row(t.name, "%d / %d" % [seated, t.seats], VenueView.C_TABLE, func() -> void: view.select_table(id), id == view.selected_table)
		row.tooltip_text = ("Meals: " + diets) if diets != "" else "No special meals"
		_list.add_child(row)
	if seating.tables.is_empty():
		_list.add_child(Ui.label("No tables yet. Add one above, then drag it into place.", 15, UiTheme.MUTED))
	var totals := seating.diet_counts()
	_catering.text = "%d guests in all%s." % [seating.guests.size(), (": " + diet_text(totals, true)) if not totals.is_empty() else ", no special meals"]


## Meal counts in words: "2 vegan, 3 vegetarian". Short form: "5 special" when there are more than two kinds.
static func diet_text(counts: Dictionary, long := false) -> String:
	var parts: Array[String] = []
	var keys := counts.keys()
	keys.sort()
	for k: String in keys:
		parts.append("%d %s" % [counts[k], k])
	if long or parts.size() <= 2:
		return ", ".join(parts)
	return "%d special" % counts.values().reduce(func(a: int, b: int) -> int: return a + b, 0)


func _rename_event(value: String) -> void:
	var clean := value.strip_edges().left(60)
	if clean != "" and clean != seating.title:
		seating.checkpoint()
		seating.title = clean
		edited.emit()
	_title_edit.text = seating.title
