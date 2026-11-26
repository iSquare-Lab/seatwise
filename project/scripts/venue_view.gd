class_name VenueView
extends Control
## Draws the tables and seats of a Seating plan and lets people drag guests between seats,
## move and turn tables, pan and zoom (mouse wheel, or two fingers on touch screens).

signal selection_changed
signal edited
signal seat_tapped(table_id: int, seat: int)

const SEAT_RADIUS := 24.0
const HANDLE := 13.0
const MIN_SCALE := 0.12
const MAX_SCALE := 4.0

const C_BACK := Color("13161d")
const C_PAPER := Color("f4f1ea")
const C_DOT := Color(0.3, 0.27, 0.2, 0.18)
const C_TABLE := Color("e2d6c2")
const C_TABLE_LINE := Color("a8957a")
const C_INK := Color("2b2721")
const C_EMPTY := Color(1, 1, 1, 0.7)
const C_ACCENT := Color("3f6df2")
const C_BAD := Color("e0443e")
const C_LOCK := Color("6b5e4b")
const GROUP_COLORS := [
	Color("8fb3e8"), Color("f0a98c"), Color("9ed4a8"), Color("d9a7e0"), Color("f2d27a"),
	Color("8fd6d0"), Color("e89bb0"), Color("b8c47a"), Color("c6b3a0"), Color("a7a3e8"),
]

var seating: Seating
var selected_guest := -1
var selected_table := -1
## A guest waiting to be put on a seat (picked in the list): the next tapped empty seat gets them.
var placing_guest := -1
var export_mode := false
## True while "Seat everyone" runs: the plan only shows, it takes no edits.
var busy := false
var text_scale := 1.0
var view_scale := 0.6
var offset := Vector2.ZERO

var _problem_guests := {}
var _group_colors := {}
var _drag := ""
var _drag_start_point := Vector2.ZERO
var _drag_start := Vector2.ZERO
var _drag_point := Vector2.ZERO
var _drop_target := Vector2i(-1, -1)
var _touches := {}
var _gesture := false
var _pinch_distance := 0.0
var _pinch_center := Vector2.ZERO
var _follow := true


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE if export_mode else Control.FOCUS_ALL
	resized.connect(func() -> void:
		if _follow:
			fit()
		queue_redraw())


func refresh() -> void:
	if seating == null:
		return
	_problem_guests.clear()
	for p in seating.wish_problems():
		for g: int in p.guests:
			_problem_guests[g] = true
	_group_colors.clear()
	for g in seating.guests:
		if g.group != "" and not _group_colors.has(g.group):
			_group_colors[g.group] = GROUP_COLORS[_group_colors.size() % GROUP_COLORS.size()]
	if selected_guest != -1 and seating.get_guest(selected_guest).is_empty():
		selected_guest = -1
	if selected_table != -1 and seating.get_table(selected_table).is_empty():
		selected_table = -1
	queue_redraw()


func group_color(group: String) -> Color:
	return _group_colors.get(group, Color("cfc8bb"))


## The area every table and seat covers, in cm.
func content_rect() -> Rect2:
	return plan_rect(seating)


## The area every table and seat of a plan covers, in cm, with room for the names.
static func plan_rect(plan: Seating) -> Rect2:
	if plan == null or plan.tables.is_empty():
		return Rect2(0, 0, 800, 600)
	var r := Rect2()
	var first := true
	for t in plan.tables:
		var top := Seating.table_size(t)
		var corners := [-top / 2.0, top / 2.0]
		var points := Seating.seat_positions(t)
		var xf := Transform2D(deg_to_rad(t.rot), Vector2(t.x, t.y))
		for c: Vector2 in corners:
			points.append(xf * c)
		for p in points:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			r = r.expand(p)
	return r.grow(SEAT_RADIUS + 75.0)


func fit() -> void:
	if seating == null or size.x < 8.0 or size.y < 8.0:
		return
	var area := content_rect()
	var margin := 24.0
	view_scale = clampf(minf((size.x - margin * 2.0) / area.size.x, (size.y - margin * 2.0) / area.size.y), MIN_SCALE, MAX_SCALE)
	offset = (size / 2.0 - area.get_center() * view_scale).round()
	_follow = true
	queue_redraw()


## Where a new table goes: the middle of the view when nothing stands there, otherwise right of everything.
func spot_for_new_table(shape: String, seats: int) -> Vector2:
	var center := to_venue(size / 2.0)
	var probe := {"shape": shape, "seats": seats, "x": center.x, "y": center.y, "rot": 0.0}
	var reach := Seating.table_size(probe).length() / 2.0 + 90.0
	for t in seating.tables:
		if Vector2(t.x, t.y).distance_to(center) < reach + Seating.table_size(t).length() / 2.0:
			var area := content_rect()
			return Vector2(area.end.x + 60.0, area.get_center().y).snapped(Vector2(10, 10))
	return center.snapped(Vector2(10, 10))


func to_screen(cm: Vector2) -> Vector2:
	return offset + cm * view_scale


func to_venue(point: Vector2) -> Vector2:
	return (point - offset) / view_scale


func zoom_at(point: Vector2, new_scale: float) -> void:
	_follow = false
	var at := to_venue(point)
	view_scale = clampf(new_scale, MIN_SCALE, MAX_SCALE)
	offset = point - at * view_scale
	queue_redraw()


func zoom_center(factor: float) -> void:
	zoom_at(size / 2.0, view_scale * factor)


func select_guest(id: int) -> void:
	selected_guest = id
	selected_table = -1
	selection_changed.emit()
	queue_redraw()


func select_table(id: int) -> void:
	selected_table = id
	selected_guest = -1
	selection_changed.emit()
	queue_redraw()


## Centres the view on a guest's seat or a table.
func show_guest(id: int) -> void:
	var s := seating.seat_of(id)
	if s.is_empty():
		return
	var p := Seating.seat_positions(seating.get_table(s.table))[s.seat]
	if not Rect2(Vector2.ZERO, size).grow(-40.0).has_point(to_screen(p)):
		offset = size / 2.0 - p * view_scale
		_follow = false
	queue_redraw()


# ------------------------------------------------------------------ Drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE if export_mode else C_BACK)
	if seating == null:
		return
	if not export_mode:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), C_PAPER)
		_draw_dots()
	for t in seating.tables:
		_draw_table(t)
	var name_size := roundi(12 * text_scale)
	for label in name_labels():
		_text(label.text, (label.rect as Rect2).get_center(), name_size, C_INK)
	if _drag == "guest" and selected_guest != -1:
		var g := seating.get_guest(selected_guest)
		_draw_seat_disc(_drag_point, g, true, 1.0)


func _draw_dots() -> void:
	var step := 50.0 * view_scale
	if step < 10.0:
		step *= 4.0
	var start := Vector2(fposmod(offset.x, step), fposmod(offset.y, step))
	var y := start.y
	while y < size.y:
		var x := start.x
		while x < size.x:
			draw_rect(Rect2(x - 1.0, y - 1.0, 2.0, 2.0), C_DOT)
			x += step
		y += step


func _font() -> Font:
	return get_theme_default_font()


## Shortens a text with a "." until it fits max_width (no limit when max_width <= 0).
func _fit_text(text: String, font_size: int, max_width: float) -> String:
	var font := _font()
	if max_width <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var shown := text
	while shown.length() > 2 and font.get_string_size(shown + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		shown = shown.left(shown.length() - 1)
	return shown.strip_edges() + "."


func _text(text: String, center: Vector2, font_size: int, color: Color, max_width: float = -1.0) -> void:
	var font := _font()
	var shown := _fit_text(text, font_size, max_width)
	var width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	draw_string(font, center + Vector2(-width / 2.0, (ascent - descent) / 2.0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func initials(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].left(2)
	return parts[0].left(1) + parts[-1].left(1)


func _table_outline(t: Dictionary) -> PackedVector2Array:
	var top := Seating.table_size(t)
	var xf := Transform2D(deg_to_rad(t.rot), Vector2(t.x, t.y))
	var points := PackedVector2Array()
	if t.shape == "round":
		for i in 40:
			var a := TAU * i / 40.0
			points.append(xf * (Vector2(cos(a), sin(a)) * top.x / 2.0))
	else:
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			points.append(xf * (c * top / 2.0))
	return points


func _draw_table(t: Dictionary) -> void:
	var outline := _table_outline(t)
	var screen := PackedVector2Array()
	for p in outline:
		screen.append(to_screen(p))
	var chosen: bool = t.id == selected_table and not export_mode
	draw_colored_polygon(screen, C_TABLE)
	var closed := screen.duplicate()
	closed.append(screen[0])
	draw_polyline(closed, C_ACCENT if chosen else C_TABLE_LINE, 3.0 if chosen else 1.5, true)
	var center := to_screen(Vector2(t.x, t.y))
	var k := text_scale
	var top := Seating.table_size(t) * view_scale
	var seated: int = t.guests.size() - t.guests.count(0)
	var label_width := (top.x if t.shape == "round" else maxf(top.x, top.y)) * 0.9
	if top.y >= 26.0 * k:
		var name_size := roundi(15 * k)
		while name_size > roundi(10 * k) and _font().get_string_size(t.name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > label_width:
			name_size -= 1
		_text(t.name, center - Vector2(0, 8.0 * k), name_size, C_INK, label_width)
		_text("%d / %d" % [seated, t.seats], center + Vector2(0, 10.0 * k), roundi(12 * k), Color(C_INK, 0.6), label_width)
	elif top.y >= 12.0:
		_text(t.name, center, roundi(11 * k), C_INK, label_width)
	var seats := Seating.seat_positions(t)
	for i in seats.size():
		var g: int = t.guests[i]
		var target := _drag == "guest" and _drop_target == Vector2i(t.id, i)
		if g == 0:
			var r := SEAT_RADIUS * view_scale
			var p := to_screen(seats[i])
			draw_circle(p, r, C_EMPTY)
			draw_arc(p, r, 0, TAU, 24, C_ACCENT if target or placing_guest != -1 else C_TABLE_LINE, 2.5 if target else 1.2, true)
			if target:
				draw_circle(p, r * 0.45, Color(C_ACCENT, 0.5))
		else:
			_draw_seat_disc(to_screen(seats[i]), seating.get_guest(g), false, 1.0, target)
	if chosen and t.shape != "round":
		var handle := _rotate_handle(t)
		draw_line(center, handle, C_ACCENT, 2.0)
		draw_circle(handle, HANDLE, Color.WHITE)
		draw_circle(handle, HANDLE - 2.5, C_ACCENT)
		draw_arc(handle, HANDLE * 0.45, -PI * 0.9, PI * 0.55, 12, Color.WHITE, 2.0, true)


## A seated guest: a coloured disc with initials. Their names are drawn afterwards, see name_labels().
func _draw_seat_disc(p: Vector2, g: Dictionary, floating: bool, alpha: float, target := false) -> void:
	if g.is_empty():
		return
	var r := SEAT_RADIUS * view_scale * (1.15 if floating else 1.0)
	var k := text_scale
	var fill := group_color(g.group)
	var dragged_away: bool = _drag == "guest" and g.id == selected_guest and not floating
	if dragged_away:
		fill = Color(fill, 0.3)
	if floating:
		draw_circle(p + Vector2(2, 3), r, Color(0, 0, 0, 0.2))
	draw_circle(p, r, Color(fill, alpha))
	var ring := Color.TRANSPARENT
	var ring_width := 2.0
	if g.id == selected_guest and not export_mode:
		ring = C_ACCENT
		ring_width = 3.5
	elif _problem_guests.has(g.id) and not export_mode:
		ring = C_BAD
		ring_width = 3.0
	elif selected_guest != -1 and not export_mode and seating.get_guest(selected_guest).get("party", -1) == g.party:
		ring = Color(C_ACCENT, 0.6)
	elif target:
		ring = C_ACCENT
	if ring.a > 0.0:
		draw_arc(p, r + 1.5, 0, TAU, 28, ring, ring_width, true)
	else:
		draw_arc(p, r, 0, TAU, 28, Color(C_INK, 0.25), 1.0, true)
	if r >= 9.0 * k:
		_text(initials(g.name), p, roundi(clampf(r * 0.75, 9.0, 20.0 * k)), C_INK)
	if g.locked and not export_mode and r >= 8.0:
		draw_circle(p + Vector2(r * 0.72, -r * 0.72), maxf(3.5, r * 0.22), C_LOCK)


## The names to draw beside the seats, when zoomed in enough to read them: [{"text", "rect"}] in screen
## pixels. LabelLayout keeps every name clear of the seats, the tables and the other names, and leaves
## out the ones that do not fit. The selected guest goes first and shows their full name.
func name_labels() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	var k := text_scale
	var r := SEAT_RADIUS * view_scale
	if seating == null or r < 13.0 * k:
		return shown
	var font := _font()
	var font_size := roundi(12 * k)
	var max_width := r * 3.4
	var items: Array[Dictionary] = []
	var texts: Array[String] = []
	var discs := PackedVector3Array()
	var blocks: Array[Rect2] = []
	for t in seating.tables:
		var center := to_screen(Vector2(t.x, t.y))
		if t.shape == "round":
			discs.append(Vector3(center.x, center.y, Seating.table_size(t).x / 2.0 * view_scale))
		else:
			var outline := _table_outline(t)
			var top := Rect2(to_screen(outline[0]), Vector2.ZERO)
			for p in outline:
				top = top.expand(to_screen(p))
			blocks.append(top)
		var seats := Seating.seat_positions(t)
		var outward := Seating.seat_outward(t)
		for i in seats.size():
			var p := to_screen(seats[i])
			discs.append(Vector3(p.x, p.y, r + 1.0))
			var id: int = t.guests[i]
			if id == 0:
				continue
			var chosen := id == selected_guest and not export_mode
			var text := _fit_text(label_text(seating.get_guest(id), chosen, export_mode), font_size, -1.0 if chosen else max_width)
			var item := {"anchor": p, "radius": r, "dir": outward[i], "size": font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(4, 0)}
			if chosen:
				items.push_front(item)
				texts.push_front(text)
			else:
				items.append(item)
				texts.append(text)
	var rects := LabelLayout.place(items, discs, blocks, 3.0 * k)
	for i in rects.size():
		if rects[i].has_area():
			shown.append({"text": texts[i], "rect": rects[i]})
	return shown


## What a seat's name label says: the first name ("First L." on the downloaded chart), the full name
## when chosen, and "Guest" for an unnamed +1.
static func label_text(g: Dictionary, full: bool, for_print: bool) -> String:
	var full_name: String = g.get("name", "")
	if full:
		return full_name
	if full_name.begins_with("Guest of"):
		return "Guest"
	var parts := full_name.split(" ", false)
	if parts.is_empty():
		return ""
	if for_print and parts.size() > 1:
		return parts[0] + " " + parts[-1].left(1) + "."
	return parts[0]


func _rotate_handle(t: Dictionary) -> Vector2:
	var top := Seating.table_size(t)
	var up := Vector2(0, -1).rotated(deg_to_rad(t.rot))
	return to_screen(Vector2(t.x, t.y) + up * (top.y / 2.0 + SEAT_RADIUS * 2.0 + 24.0))


# ------------------------------------------------------------------ Hit testing

## The seat under a point: Vector2i(table id, seat index), or (-1, -1).
func seat_at(point: Vector2) -> Vector2i:
	var at := to_venue(point)
	var best := Vector2i(-1, -1)
	var best_distance := SEAT_RADIUS * 1.25
	for t in seating.tables:
		var seats := Seating.seat_positions(t)
		for i in seats.size():
			var d := seats[i].distance_to(at)
			if d < best_distance:
				best_distance = d
				best = Vector2i(t.id, i)
	# Small on screen: give fingers a little more room.
	if best.x == -1 and SEAT_RADIUS * view_scale < 16.0:
		var reach := 16.0 / view_scale
		for t in seating.tables:
			var seats := Seating.seat_positions(t)
			for i in seats.size():
				var d := seats[i].distance_to(at)
				if d < reach:
					reach = d
					best = Vector2i(t.id, i)
	return best


func table_at(point: Vector2) -> int:
	var at := to_venue(point)
	for i in range(seating.tables.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(at, _table_outline(seating.tables[i])):
			return seating.tables[i].id
	return -1


# ------------------------------------------------------------------ Editing

func _press(point: Vector2) -> void:
	grab_focus()
	if selected_table != -1:
		var t := seating.get_table(selected_table)
		if not t.is_empty() and t.shape != "round" and _rotate_handle(t).distance_to(point) <= HANDLE + 6.0:
			seating.checkpoint()
			_drag = "rotate"
			return
	var seat := seat_at(point)
	if seat.x != -1:
		var g: int = seating.get_table(seat.x).guests[seat.y]
		if g == 0:
			seat_tapped.emit(seat.x, seat.y)
			return
		select_guest(g)
		if not seating.get_guest(g).locked:
			_drag = "guest-pending"
			_drag_start_point = point
			_drag_point = point
		return
	var table := table_at(point)
	if table != -1:
		select_table(table)
		seating.checkpoint()
		var t := seating.get_table(table)
		_drag = "table"
		_drag_start_point = point
		_drag_start = Vector2(t.x, t.y)
		return
	if selected_guest != -1 or selected_table != -1:
		select_guest(-1)
	_drag = "pan"
	_drag_start_point = point


func _move(point: Vector2, relative: Vector2) -> void:
	match _drag:
		"pan":
			offset += relative
			_follow = false
		"guest-pending":
			if point.distance_to(_drag_start_point) > 8.0:
				_drag = "guest"
				_drag_point = point
		"guest":
			_drag_point = point
			_drop_target = seat_at(point)
			if _drop_target.x != -1:
				var occupant: int = seating.get_table(_drop_target.x).guests[_drop_target.y]
				if occupant != 0 and seating.get_guest(occupant).locked:
					_drop_target = Vector2i(-1, -1)
		"table":
			var t := seating.get_table(selected_table)
			var delta := (point - _drag_start_point) / view_scale
			t.x = snappedf(_drag_start.x + delta.x, 10.0)
			t.y = snappedf(_drag_start.y + delta.y, 10.0)
		"rotate":
			var t := seating.get_table(selected_table)
			var angle := rad_to_deg((point - to_screen(Vector2(t.x, t.y))).angle()) + 90.0
			t.rot = fposmod(angle if Input.is_key_pressed(KEY_SHIFT) else snappedf(angle, 15.0), 360.0)
	queue_redraw()


func _release() -> void:
	match _drag:
		"guest":
			if _drop_target.x != -1:
				seating.checkpoint()
				seating.seat(selected_guest, _drop_target.x, _drop_target.y)
				seating.drop_checkpoint_if_unchanged()
				refresh()
				edited.emit()
		"table", "rotate":
			seating.drop_checkpoint_if_unchanged()
			refresh()
			edited.emit()
	_drag = ""
	_drop_target = Vector2i(-1, -1)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if export_mode or seating == null or (busy and not (event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN))):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, view_scale * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15))
			MOUSE_BUTTON_MIDDLE:
				_drag = "pan" if mb.pressed else ""
			MOUSE_BUTTON_LEFT:
				if _gesture:
					pass
				elif mb.pressed:
					_press(mb.position)
				else:
					_release()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag != "" and not _gesture:
			_move(mm.position, mm.relative)
			accept_event()
		else:
			var over := seat_at(mm.position).x != -1 or table_at(mm.position) != -1
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).position, view_scale * (event as InputEventMagnifyGesture).factor)
		accept_event()
	elif event is InputEventPanGesture:
		offset -= (event as InputEventPanGesture).delta * 8.0
		_follow = false
		queue_redraw()
		accept_event()


# Touch is read here so a second finger anywhere still counts as a pinch.
func _input(event: InputEvent) -> void:
	if export_mode or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local := (make_input_local(touch) as InputEventScreenTouch).position
		if touch.pressed:
			if not Rect2(Vector2.ZERO, size).has_point(local) and _touches.is_empty():
				return
			_touches[touch.index] = local
			if _touches.size() >= 2 and not _gesture:
				_gesture = true
				if _drag in ["table", "rotate"]:
					seating.discard_to_checkpoint()
					refresh()
				_drag = ""
				_drop_target = Vector2i(-1, -1)
				_pinch_distance = 0.0
		else:
			_touches.erase(touch.index)
			if _touches.is_empty():
				_gesture = false
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return
		_touches[drag.index] = (make_input_local(drag) as InputEventScreenDrag).position
		if _gesture and _touches.size() >= 2:
			var keys := _touches.keys()
			keys.sort()
			var a: Vector2 = _touches[keys[0]]
			var b: Vector2 = _touches[keys[1]]
			var distance := a.distance_to(b)
			var center := (a + b) / 2.0
			if _pinch_distance > 0.0:
				offset += center - _pinch_center
				_follow = false
				if distance > 8.0:
					zoom_at(center, view_scale * distance / _pinch_distance)
			_pinch_distance = distance
			_pinch_center = center
			queue_redraw()
