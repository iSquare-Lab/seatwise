class_name Seating
extends RefCounted
## An event seating plan: tables (with their seats), guests, households that sit together,
## pairs that must sit apart, and the undo history. Positions are in centimetres.
## No nodes here, so the logic tests run it headless. The solver lives in SeatingSolver,
## pasted lists in GuestImport, and files in PlanFile.

const SEAT_WIDTH := 60.0
const MAX_SEATS := 24
const MAX_GUESTS := 600
const MAX_UNDO := 120

const SHAPES := ["round", "rect", "head"]

## What a problem is about (the "kind" of each entry of problems()).
const PROBLEM_APART := "apart"
const PROBLEM_SPLIT := "split"
const PROBLEM_NO_ROOM := "no-room"
const PROBLEM_WAITING := "waiting"

var title := "Our event"
var tables: Array[Dictionary] = []
var guests: Array[Dictionary] = []
## Pairs of guest ids that must not share a table.
var apart: Array[Vector2i] = []
var _next_id := 1
var _undo: Array[String] = []
var _redo: Array[String] = []


# ------------------------------------------------------------------ Tables

func clear() -> void:
	title = "Our event"
	tables.clear()
	guests.clear()
	apart.clear()
	_next_id = 1


func add_table(shape: String, seats: int, x: float, y: float, name: String = "") -> int:
	var table := {
		"id": _next_id, "shape": shape if shape in SHAPES else "round",
		"seats": clampi(seats, 1, MAX_SEATS), "x": x, "y": y, "rot": 0.0,
		"name": name if name != "" else "Table %d" % (tables.size() + 1),
		"guests": [],
	}
	_next_id += 1
	table.guests.resize(table.seats)
	table.guests.fill(0)
	tables.append(table)
	return table.id


func get_table(id: int) -> Dictionary:
	for t in tables:
		if t.id == id:
			return t
	return {}


func remove_table(id: int) -> void:
	tables = tables.filter(func(t: Dictionary) -> bool: return t.id != id)


## Changes the number of seats. Guests on seats that disappear become unseated.
func set_seats(id: int, seats: int) -> void:
	var t := get_table(id)
	if t.is_empty():
		return
	seats = clampi(seats, 1, MAX_SEATS)
	var kept: Array = t.guests.filter(func(g: int) -> bool: return g != 0)
	t.seats = seats
	t.guests = []
	t.guests.resize(seats)
	t.guests.fill(0)
	for i in mini(seats, kept.size()):
		t.guests[i] = kept[i]


func capacity() -> int:
	var total := 0
	for t in tables:
		total += t.seats
	return total


## The size of a table's top in cm (width, depth) before rotation.
static func table_size(table: Dictionary) -> Vector2:
	var n: int = table.seats
	match table.shape:
		"round":
			var d := maxf(90.0, n * SEAT_WIDTH / PI)
			return Vector2(d, d)
		"head":
			return Vector2(maxf(120.0, n * SEAT_WIDTH), 80.0)
		_:
			# Seats on both long sides, plus one at each end from 8 seats up.
			var ends := 2 if n >= 8 else 0
			var per_side := ceili((n - ends) / 2.0)
			return Vector2(maxf(120.0, per_side * SEAT_WIDTH), 90.0)


## Where each seat is, in order around the table (centres, in cm, rotation applied).
static func seat_positions(table: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var t := Transform2D(deg_to_rad(table.rot), Vector2(table.x, table.y))
	for p in _seat_layout(table, false):
		out.append(t * p)
	return out


## The direction each seat faces away from the table (unit vectors, rotation applied): straight out
## from a round table, and square to the side a seat is on for long and head tables.
static func seat_outward(table: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for d in _seat_layout(table, true):
		out.append(d.rotated(deg_to_rad(table.rot)))
	return out


## Seat centres (or their outward directions) before the table is moved and turned.
static func _seat_layout(table: Dictionary, directions: bool) -> PackedVector2Array:
	var n: int = table.seats
	var size := table_size(table)
	var out := PackedVector2Array()
	match table.shape:
		"round":
			var r := size.x / 2.0 + 28.0
			for i in n:
				var a := -PI / 2.0 + TAU * i / n
				var dir := Vector2(cos(a), sin(a))
				out.append(dir if directions else dir * r)
		"head":
			for i in n:
				out.append(Vector2.DOWN if directions else Vector2(-size.x / 2.0 + SEAT_WIDTH * (i + 0.5) + (size.x - n * SEAT_WIDTH) / 2.0, size.y / 2.0 + 28.0))
		_:
			var ends := 2 if n >= 8 else 0
			var top := ceili((n - ends) / 2.0)
			var bottom := n - ends - top
			# Clockwise: along the top, the right end, back along the bottom, the left end.
			for i in top:
				out.append(Vector2.UP if directions else Vector2(-size.x / 2.0 + size.x * (i + 0.5) / top, -size.y / 2.0 - 28.0))
			if ends > 0:
				out.append(Vector2.RIGHT if directions else Vector2(size.x / 2.0 + 28.0, 0))
			for i in bottom:
				out.append(Vector2.DOWN if directions else Vector2(size.x / 2.0 - size.x * (i + 0.5) / bottom, size.y / 2.0 + 28.0))
			if ends > 0:
				out.append(Vector2.LEFT if directions else Vector2(-size.x / 2.0 - 28.0, 0))
	return out


## Seats that sit next to each other: around the table for round and rectangular tables, in a row for a head table.
static func neighbours(table: Dictionary) -> Array[Vector2i]:
	var n: int = table.seats
	var pairs: Array[Vector2i] = []
	if n < 2:
		return pairs
	for i in n - 1:
		pairs.append(Vector2i(i, i + 1))
	if table.shape != "head" and n > 2:
		pairs.append(Vector2i(n - 1, 0))
	return pairs


# ------------------------------------------------------------------ Guests

## Adds a guest and returns their id, or 0 when the plan already has MAX_GUESTS guests.
func add_guest(name: String, group: String = "", diet: String = "", party: int = 0) -> int:
	if guests.size() >= MAX_GUESTS:
		return 0
	var guest := {
		"id": _next_id, "name": name.strip_edges().left(60), "group": group.strip_edges().left(40),
		"diet": diet.strip_edges().to_lower().left(30), "party": party, "locked": false,
	}
	_next_id += 1
	if guest.party == 0:
		guest.party = guest.id
	guests.append(guest)
	return guest.id


## How many more guests fit under MAX_GUESTS.
func room_for_guests() -> int:
	return maxi(0, MAX_GUESTS - guests.size())


func get_guest(id: int) -> Dictionary:
	for g in guests:
		if g.id == id:
			return g
	return {}


## The id of the first guest with exactly this name, or 0.
func find_guest(name: String) -> int:
	for g in guests:
		if g.name == name:
			return g.id
	return 0


func remove_guest(id: int) -> void:
	unseat(id)
	guests = guests.filter(func(g: Dictionary) -> bool: return g.id != id)
	apart = apart.filter(func(p: Vector2i) -> bool: return p.x != id and p.y != id)


## Puts two guests in one household (they sit together). Joins their whole households.
func join_party(a: int, b: int) -> void:
	var ga := get_guest(a)
	var gb := get_guest(b)
	if ga.is_empty() or gb.is_empty():
		return
	var old: int = gb.party
	for g in guests:
		if g.party == old:
			g.party = ga.party


## Takes a guest out of their household.
func leave_party(id: int) -> void:
	var g := get_guest(id)
	if not g.is_empty():
		var others := party_members(g.party).filter(func(m: int) -> bool: return m != id)
		if g.party == id and not others.is_empty():
			for m in others:
				get_guest(m).party = others[0]
		g.party = id


func party_members(party: int) -> Array[int]:
	var ids: Array[int] = []
	for g in guests:
		if g.party == party:
			ids.append(g.id)
	return ids


## Every household: {party id: [guest ids]}.
func parties() -> Dictionary:
	var found := {}
	for g in guests:
		if not found.has(g.party):
			found[g.party] = []
		found[g.party].append(g.id)
	return found


func set_apart(a: int, b: int, on: bool = true) -> void:
	if a == b:
		return
	var pair := Vector2i(mini(a, b), maxi(a, b))
	apart = apart.filter(func(p: Vector2i) -> bool: return p != pair)
	if on:
		apart.append(pair)


func is_apart(a: int, b: int) -> bool:
	return apart.has(Vector2i(mini(a, b), maxi(a, b)))


## Where a guest sits: {"table": id, "seat": index}, or empty when unseated.
func seat_of(guest_id: int) -> Dictionary:
	for t in tables:
		var i: int = t.guests.find(guest_id)
		if i != -1:
			return {"table": t.id, "seat": i}
	return {}


func unseat(guest_id: int) -> void:
	for t in tables:
		var i: int = t.guests.find(guest_id)
		if i != -1:
			t.guests[i] = 0


## Seats a guest. Whoever sat there before swaps to the guest's old seat (or becomes unseated).
func seat(guest_id: int, table_id: int, index: int) -> void:
	var t := get_table(table_id)
	if t.is_empty() or index < 0 or index >= t.seats:
		return
	var before := seat_of(guest_id)
	var other: int = t.guests[index]
	unseat(guest_id)
	t.guests[index] = guest_id
	if other != 0 and other != guest_id and not before.is_empty():
		get_table(before.table).guests[before.seat] = other


func unseated() -> Array[int]:
	var seated := {}
	for t in tables:
		for g: int in t.guests:
			if g != 0:
				seated[g] = true
	var out: Array[int] = []
	for g in guests:
		if not seated.has(g.id):
			out.append(g.id)
	return out


func clear_seats(keep_locked: bool = true) -> void:
	for t in tables:
		for i in t.seats:
			var g: int = t.guests[i]
			if g != 0 and not (keep_locked and get_guest(g).get("locked", false)):
				t.guests[i] = 0


## Seats everyone in one go with the same solver "Seat everyone" runs in the App. Returns the score.
func auto_seat(seed_value: int = 1) -> float:
	return SeatingSolver.new(self, seed_value).run()


# ------------------------------------------------------------------ Checks

## What breaks a wish, in words: people who should be apart sharing a table, split households,
## unseated guests. Each entry: {"kind": one of the PROBLEM_ constants, "guests": [ids], "text": String}.
func problems() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for pair in apart:
		var a := seat_of(pair.x)
		var b := seat_of(pair.y)
		if not a.is_empty() and not b.is_empty() and a.table == b.table:
			found.append({"kind": PROBLEM_APART, "guests": [pair.x, pair.y], "text": "%s and %s should not sit at %s together" % [get_guest(pair.x).name, get_guest(pair.y).name, get_table(a.table).name]})
	var households := parties()
	for party: int in households:
		var members: Array[int] = []
		members.assign(households[party])
		if members.size() < 2:
			continue
		var where := {}
		for m in members:
			var s := seat_of(m)
			if not s.is_empty():
				where[s.table] = true
		if where.size() > 1:
			found.append({"kind": PROBLEM_SPLIT, "guests": members, "text": "%s are split across %d tables" % [_names(members), where.size()]})
	var missing := unseated()
	if not missing.is_empty() and not tables.is_empty():
		var room := capacity() - (guests.size() - missing.size())
		if missing.size() > room:
			var short := missing.size() - room
			found.append({"kind": PROBLEM_NO_ROOM, "guests": missing, "text": "%d %s no seat: add %d more %s" % [missing.size(), "guest has" if missing.size() == 1 else "guests have", short, "seat" if short == 1 else "seats"]})
		else:
			found.append({"kind": PROBLEM_WAITING, "guests": missing, "text": "%d %s not seated yet" % [missing.size(), "guest is" if missing.size() == 1 else "guests are"]})
	return found


## The problems worth a red mark: every problem except guests simply waiting for a seat that is free.
func wish_problems() -> Array[Dictionary]:
	return problems().filter(func(p: Dictionary) -> bool: return p.kind != PROBLEM_WAITING)


func _names(ids: Array[int]) -> String:
	var names: Array[String] = []
	for id in ids:
		names.append(get_guest(id).name)
	if names.size() <= 2:
		return " and ".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]


## Counts per diet at a table (or across the event with table_id = -1), e.g. {"vegetarian": 3}.
func diet_counts(table_id: int = -1) -> Dictionary:
	var counts := {}
	for g in guests:
		if g.diet == "":
			continue
		if table_id != -1:
			var s := seat_of(g.id)
			if s.is_empty() or s.table != table_id:
				continue
		counts[g.diet] = counts.get(g.diet, 0) + 1
	return counts


## Last name first, for alphabetical lists ("Meyer, Lisa").
static func sort_key(name: String) -> String:
	var parts := name.strip_edges().split(" ", false)
	if parts.size() < 2:
		return name.to_lower()
	return (parts[-1] + " " + " ".join(parts.slice(0, parts.size() - 1))).to_lower()


## "Find your seat" rows, sorted by last name: [name, table name, seat number, group, diet].
func seat_list() -> Array[PackedStringArray]:
	var sorted := guests.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return sort_key(a.name) < sort_key(b.name))
	var rows: Array[PackedStringArray] = []
	for g: Dictionary in sorted:
		var s := seat_of(g.id)
		rows.append(PackedStringArray([g.name, get_table(s.table).name if not s.is_empty() else "", str(s.seat + 1) if not s.is_empty() else "", g.group, g.diet]))
	return rows


# ------------------------------------------------------------------ Lists and files

## Adds the guests of a pasted list (see GuestImport). Returns the ids added.
func import_text(text: String) -> Array[int]:
	return GuestImport.import_text(self, text)


func to_csv() -> String:
	return PlanFile.to_csv(self)


func to_json() -> String:
	return PlanFile.to_json(self)


## Loads a saved plan. Returns an empty string, or why it could not (and then changes nothing).
func from_json(text: String) -> String:
	var data := PlanFile.parse(text)
	if data.error != "":
		return data.error
	apply(data)
	return ""


## Takes over a plan read by PlanFile.parse().
func apply(data: Dictionary) -> void:
	title = data.title
	tables = data.tables
	guests = data.guests
	apart = data.apart
	_next_id = data.next_id


# ------------------------------------------------------------------ History

func checkpoint() -> void:
	_undo.push_back(to_json())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func drop_checkpoint_if_unchanged() -> void:
	if not _undo.is_empty() and _undo.back() == to_json():
		_undo.pop_back()


## Throws away everything since the last checkpoint (a drag cancelled by a second finger), leaving no redo step.
func discard_to_checkpoint() -> void:
	if not _undo.is_empty():
		from_json(_undo.pop_back())


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.push_back(to_json())
	from_json(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.push_back(to_json())
	from_json(_redo.pop_back())
	return true


# ------------------------------------------------------------------ The example

## The example a first visit opens: a wedding dinner of 38 made-up guests at six tables,
## not seated yet (except the couple), so "Seat everyone" has something to do.
func load_example() -> void:
	clear()
	title = "Wedding dinner (example)"
	add_table("head", 6, 600, 110, "Head table")
	add_table("round", 8, 230, 360, "Table 1")
	add_table("round", 8, 600, 380, "Table 2")
	add_table("round", 8, 970, 360, "Table 3")
	add_table("rect", 10, 320, 660, "Table 4")
	add_table("rect", 10, 880, 660, "Table 5")
	import_text("\n".join([
		"Wedding party:",
		"Mara & Jonas Lindqvist",
		"Ines Okafor", "Paul Okafor", "Sofia Reyes", "Theo Brandt",
		"Mara's family:",
		"Elin and Karl Lindqvist", "Astrid Lindqvist, , vegetarian", "Nils Lindqvist +1", "Greta & Ove Holm", "Liv Holm, , kids",
		"Jonas's family:",
		"Ruth and Henrik Weber", "Lena Weber, , vegan", "Max Weber", "Clara & Felix Hartmann", "Jana Hartmann, , kids", "Otto Hartmann, , kids",
		"University friends:",
		"Amira Haddad, , vegetarian", "Leo Fischer", "Noor & Sam Patel", "Yuki Tanaka, , gluten-free", "Ben Carter", "Hanna Berg",
		"Work:",
		"Dana Moore", "Raj Iyer, , vegetarian", "Eva Novak", "Tom Ellis +1", "Kim Seo",
		"Neighbours:",
		"Rosa & Luis García", "Agnes Kovač",
	]))
	# Two pairs who should not share a table, as happens at real weddings.
	set_apart(find_guest("Karl Lindqvist"), find_guest("Henrik Weber"))
	set_apart(find_guest("Ben Carter"), find_guest("Hanna Berg"))
	# The couple sits in the middle of the head table and stays there.
	var head := tables[0]
	head.guests[2] = find_guest("Mara Lindqvist")
	head.guests[3] = find_guest("Jonas Lindqvist")
	get_guest(find_guest("Mara Lindqvist")).locked = true
	get_guest(find_guest("Jonas Lindqvist")).locked = true
