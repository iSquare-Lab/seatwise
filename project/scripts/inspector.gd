class_name Inspector
extends VBoxContainer
## The Selected tab: everything about the guest or the table picked in the plan or a list.
## A guest: name, group, meal, who they sit with or apart from, lock, take off seat, remove.
## A table: name, shape, seats, turn, who sits there, clear, remove.

## The plan changed (after a checkpoint); the editor redraws and saves.
signal edited
signal toast_requested(text: String)
## Asks the editor to let the user pick another guest; chosen gets their id.
signal pick_requested(title: String, exclude: int, chosen: Callable)

const DIETS := ["vegetarian", "vegan", "gluten-free", "kids"]
const MAX_GROUP_CHIPS := 8

var seating: Seating
var view: VenueView


func _init(plan: Seating, plan_view: VenueView) -> void:
	seating = plan
	view = plan_view
	add_theme_constant_override("separation", 10)


## Builds the page again, unless someone is typing in one of its fields.
func refresh() -> void:
	for child in find_children("*", "LineEdit", true, false):
		if (child as LineEdit).has_focus():
			return
	Ui.clear(self)
	if view.selected_guest != -1:
		_build_guest(seating.get_guest(view.selected_guest))
	elif view.selected_table != -1:
		_build_table(seating.get_table(view.selected_table))
	else:
		add_child(Ui.label("Tap a guest or a table to change it. Drag a guest onto another seat to move them; drop them on someone to swap.", 15, UiTheme.MUTED))


## Puts the cursor in the first field (the name), e.g. after "Add a guest".
func focus_first_field() -> void:
	var edits := find_children("*", "LineEdit", true, false)
	if not edits.is_empty():
		(edits[0] as LineEdit).grab_focus.call_deferred()


## Runs a change as one undo step and tells the editor.
func _change(action: Callable, drop_if_unchanged := false) -> void:
	seating.checkpoint()
	action.call()
	if drop_if_unchanged:
		seating.drop_checkpoint_if_unchanged()
	edited.emit()


# ------------------------------------------------------------------ A guest

func _build_guest(g: Dictionary) -> void:
	var id: int = g.id
	add_child(Ui.labelled("Name", Ui.field(g.name, "Name", func(value: String) -> void:
		var clean := value.strip_edges().left(60)
		var current := seating.get_guest(id)
		if clean != "" and not current.is_empty() and clean != current.name:
			_change(func() -> void: current.name = clean))))
	var s := seating.seat_of(id)
	if s.is_empty():
		add_child(Ui.label("Waiting for a seat: tap an empty seat in the plan.", 15, UiTheme.FOCUS))
	else:
		add_child(Ui.label("Seat %d at %s" % [s.seat + 1, seating.get_table(s.table).name], 15))
	add_child(Ui.labelled("Group", Ui.field(g.group, "e.g. Family, Work", func(value: String) -> void:
		var current := seating.get_guest(id)
		var clean := value.strip_edges().left(40)
		if not current.is_empty() and clean != current.group:
			_change(func() -> void: current.group = clean))))
	_add_group_chips(g)
	_add_meals(g)
	_add_household(g)
	_add_apart(g)
	var lock := Ui.button("Seat locked" if g.locked else "Lock this seat", func() -> void:
		_change(func() -> void: seating.get_guest(id).locked = not seating.get_guest(id).locked))
	lock.toggle_mode = true
	lock.set_pressed_no_signal(g.locked)
	lock.tooltip_text = "Seat everyone never moves a locked guest."
	lock.disabled = s.is_empty()
	var unseat := Ui.button("Take off seat", func() -> void:
		_change(func() -> void:
			seating.unseat(id)
			seating.get_guest(id).locked = false))
	unseat.disabled = s.is_empty()
	add_child(Ui.row(Ui.expand([lock, unseat])))
	var remove := Ui.button("Remove guest", func() -> void:
		_change(func() -> void: seating.remove_guest(id))
		view.select_guest(-1))
	remove.add_theme_color_override("font_color", UiTheme.BAD)
	add_child(remove)
	for p in seating.wish_problems():
		if p.guests.has(id):
			add_child(Ui.label(p.text, 15, UiTheme.BAD))


## Buttons for the groups other guests are in, to move this guest into one with a tap.
func _add_group_chips(g: Dictionary) -> void:
	var id: int = g.id
	var groups := {}
	for other in seating.guests:
		if other.group != "" and other.group != g.group:
			groups[other.group] = true
	if groups.is_empty():
		return
	var chips := Ui.flow()
	for group_name: String in groups.keys().slice(0, MAX_GROUP_CHIPS):
		var b := Ui.chip(group_name, func() -> void: _change(func() -> void: seating.get_guest(id).group = group_name))
		b.icon = UiTheme.dot(view.group_color(group_name))
		b.add_theme_constant_override("icon_max_width", 12)
		chips.add_child(b)
	add_child(chips)


func _add_meals(g: Dictionary) -> void:
	var id: int = g.id
	add_child(Ui.heading("Meal"))
	var meals := Ui.flow()
	for diet in [""] + DIETS:
		var value: String = diet
		var b := Ui.chip("No special meal" if value == "" else value.capitalize(), func() -> void:
			_change(func() -> void: seating.get_guest(id).diet = value, true))
		b.toggle_mode = true
		b.set_pressed_no_signal(g.diet == value)
		meals.add_child(b)
	if g.diet != "" and not (g.diet in DIETS):
		# A meal from a pasted list that is not one of the usual ones.
		var other := Ui.chip(g.diet.capitalize(), func() -> void: pass)
		other.toggle_mode = true
		other.set_pressed_no_signal(true)
		meals.add_child(other)
	add_child(meals)


func _add_household(g: Dictionary) -> void:
	var id: int = g.id
	add_child(Ui.heading("Sits together with"))
	var mates := seating.party_members(g.party).filter(func(m: int) -> bool: return m != id)
	if mates.is_empty():
		add_child(Ui.label("Nobody yet. A household or a couple always gets seats side by side.", 14, UiTheme.MUTED))
	else:
		add_child(Ui.label(", ".join(mates.map(func(m: int) -> String: return seating.get_guest(m).name)), 15))
	var buttons := [Ui.button("Add someone", func() -> void:
		pick_requested.emit("Sits together with %s" % g.name, id, func(other: int) -> void:
			_change(func() -> void: seating.join_party(id, other))))]
	if not mates.is_empty():
		buttons.append(Ui.button("Sit alone", func() -> void: _change(func() -> void: seating.leave_party(id))))
	add_child(Ui.row(Ui.expand(buttons)))


func _add_apart(g: Dictionary) -> void:
	var id: int = g.id
	add_child(Ui.heading("Keep apart from"))
	for pair in seating.apart:
		if pair.x != id and pair.y != id:
			continue
		var other: int = pair.y if pair.x == id else pair.x
		var row := Ui.list_row(seating.get_guest(other).name, "remove", UiTheme.BAD, func() -> void:
			_change(func() -> void: seating.set_apart(id, other, false)))
		row.tooltip_text = "Allow them at the same table again"
		add_child(row)
	add_child(Ui.button("Keep apart from someone", func() -> void:
		pick_requested.emit("Not at the same table as %s" % g.name, id, func(other: int) -> void:
			_change(func() -> void: seating.set_apart(id, other, true)))))


# ------------------------------------------------------------------ A table

func _build_table(t: Dictionary) -> void:
	var id: int = t.id
	add_child(Ui.labelled("Table name", Ui.field(t.name, "Name", func(value: String) -> void:
		var clean := value.strip_edges().left(40)
		var current := seating.get_table(id)
		if clean != "" and not current.is_empty() and clean != current.name:
			_change(func() -> void: current.name = clean))))
	var shapes := []
	for spec in [["round", "Round"], ["rect", "Long"], ["head", "Head table"]]:
		var shape: String = spec[0]
		var b := Ui.button(spec[1], func() -> void: _change(func() -> void: seating.get_table(id).shape = shape, true))
		b.toggle_mode = true
		b.set_pressed_no_signal(t.shape == shape)
		shapes.append(b)
	add_child(Ui.row(Ui.expand(shapes), 4))
	var count := Ui.label("%d seats" % t.seats, 16)
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fewer := Ui.icon_button("minus", "One seat fewer", func() -> void: _change_seats(id, -1))
	var more := Ui.icon_button("plus", "One seat more", func() -> void: _change_seats(id, 1))
	fewer.disabled = t.seats <= 1
	more.disabled = t.seats >= Seating.MAX_SEATS
	var seats_row := Ui.row([fewer, count, more])
	if t.shape != "round":
		seats_row.add_child(Ui.icon_button("turn", "Turn a quarter", func() -> void:
			_change(func() -> void:
				var current := seating.get_table(id)
				current.rot = fposmod(current.rot + 90.0, 360.0))))
	add_child(seats_row)
	add_child(Ui.heading("At this table"))
	var seated := 0
	for i in t.seats:
		var g: int = t.guests[i]
		if g == 0:
			continue
		seated += 1
		var guest := seating.get_guest(g)
		add_child(Ui.list_row("%d. %s" % [i + 1, guest.name], guest.diet, view.group_color(guest.group), func() -> void: view.select_guest(g)))
	if seated == 0:
		add_child(Ui.label("Nobody yet.", 15, UiTheme.MUTED))
	var clear := Ui.button("Clear this table", func() -> void:
		_change(func() -> void:
			var current := seating.get_table(id)
			for i in current.seats:
				if current.guests[i] != 0:
					seating.get_guest(current.guests[i]).locked = false
					current.guests[i] = 0))
	var remove := Ui.button("Remove table", func() -> void:
		_change(func() -> void: seating.remove_table(id))
		view.select_table(-1))
	remove.add_theme_color_override("font_color", UiTheme.BAD)
	add_child(Ui.row(Ui.expand([clear, remove])))


func _change_seats(id: int, delta: int) -> void:
	var t := seating.get_table(id)
	if t.is_empty():
		return
	var before := seating.unseated().size()
	_change(func() -> void: seating.set_seats(id, t.seats + delta))
	if seating.unseated().size() > before:
		toast_requested.emit("Someone lost their seat and is waiting again.")
