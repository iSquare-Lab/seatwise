class_name Seating
extends RefCounted
## An event seating plan: tables (with their seats), guests, households that sit together,
## pairs that must sit apart, and the solver that seats everyone. Positions are in centimetres.
## No nodes here, so the logic tests run it headless.

const SEAT_WIDTH := 60.0
const MAX_SEATS := 24
const MAX_GUESTS := 600
const MAX_UNDO := 120

## Costs the solver minimises. Keeping people apart and households together matter most.
const COST_APART := 400.0
const COST_PARTY_SPLIT := 120.0
const BONUS_PARTY_NEIGHBOUR := 10.0
const BONUS_SAME_GROUP := 3.0
const COST_MIXED_GROUP := 1.0
const COST_LONELY := 6.0

const SHAPES := ["round", "rect", "head"]

var title := "Our event"
var tables: Array[Dictionary] = []
var guests: Array[Dictionary] = []
## Pairs of guest ids that must not share a table.
var apart: Array[Vector2i] = []
var _next_id := 1
var _undo: Array[String] = []
var _redo: Array[String] = []
# Solver state (see improve()): packed arrays indexed by guest position, kept as members so the
# helper methods share them by reference.
var _sv_n := 0
var _sv_tcount := 0
var _sv_group := PackedInt32Array()
var _sv_party := PackedInt32Array()
var _sv_avoid := PackedByteArray()
var _sv_seats: Array[PackedInt32Array] = []
var _sv_pairs: Array[PackedInt32Array] = []
var _sv_lonely := PackedByteArray()
var _sv_ptc := PackedInt32Array()
var _sv_mt := PackedInt32Array()
var _sv_ms := PackedInt32Array()
var _sv_costs := PackedFloat64Array()


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
	var n: int = table.seats
	var size := table_size(table)
	var out := PackedVector2Array()
	var t := Transform2D(deg_to_rad(table.rot), Vector2(table.x, table.y))
	match table.shape:
		"round":
			var r := size.x / 2.0 + 28.0
			for i in n:
				var a := -PI / 2.0 + TAU * i / n
				out.append(t * (Vector2(cos(a), sin(a)) * r))
		"head":
			for i in n:
				out.append(t * Vector2(-size.x / 2.0 + SEAT_WIDTH * (i + 0.5) + (size.x - n * SEAT_WIDTH) / 2.0, size.y / 2.0 + 28.0))
		_:
			var ends := 2 if n >= 8 else 0
			var top := ceili((n - ends) / 2.0)
			var bottom := n - ends - top
			# Clockwise: along the top, the right end, back along the bottom, the left end.
			for i in top:
				out.append(t * Vector2(-size.x / 2.0 + size.x * (i + 0.5) / top, -size.y / 2.0 - 28.0))
			if ends > 0:
				out.append(t * Vector2(size.x / 2.0 + 28.0, 0))
			for i in bottom:
				out.append(t * Vector2(size.x / 2.0 - size.x * (i + 0.5) / bottom, size.y / 2.0 + 28.0))
			if ends > 0:
				out.append(t * Vector2(-size.x / 2.0 - 28.0, 0))
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

func add_guest(name: String, group: String = "", diet: String = "", party: int = 0) -> int:
	var guest := {
		"id": _next_id, "name": name.strip_edges().left(60), "group": group.strip_edges().left(40),
		"diet": diet.strip_edges().to_lower().left(30), "party": party, "locked": false,
	}
	_next_id += 1
	if guest.party == 0:
		guest.party = guest.id
	guests.append(guest)
	return guest.id


func get_guest(id: int) -> Dictionary:
	for g in guests:
		if g.id == id:
			return g
	return {}


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
	if other != 0 and other != guest_id:
		if before.is_empty():
			pass
		else:
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


# ------------------------------------------------------------------ Checks

## What breaks a wish, in words: people who should be apart sharing a table, split households,
## unseated guests.
func problems() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for pair in apart:
		var a := seat_of(pair.x)
		var b := seat_of(pair.y)
		if not a.is_empty() and not b.is_empty() and a.table == b.table:
			found.append({"guests": [pair.x, pair.y], "text": "%s and %s should not sit at %s together" % [get_guest(pair.x).name, get_guest(pair.y).name, get_table(a.table).name]})
	var parties := {}
	for g in guests:
		parties[g.party] = true
	for party: int in parties:
		var members := party_members(party)
		if members.size() < 2:
			continue
		var where := {}
		for m in members:
			var s := seat_of(m)
			if not s.is_empty():
				where[s.table] = true
		if where.size() > 1:
			found.append({"guests": members, "text": "%s are split across %d tables" % [_names(members), where.size()]})
	var missing := unseated()
	if not missing.is_empty() and not tables.is_empty():
		var room := capacity() - (guests.size() - missing.size())
		if missing.size() > room:
			found.append({"guests": missing, "text": "%d %s no seat: add %d more %s" % [missing.size(), "guest has" if missing.size() == 1 else "guests have", missing.size() - room, "seat" if missing.size() - room == 1 else "seats"]})
		else:
			found.append({"guests": missing, "text": "%d %s not seated yet" % [missing.size(), "guest is" if missing.size() == 1 else "guests are"]})
	return found


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


# ------------------------------------------------------------------ The solver

## A score for one table: lower is better. Used by the solver and shown nowhere else.
func _table_cost(t: Dictionary, lookup: Dictionary) -> float:
	var cost := 0.0
	var seated: Array[int] = []
	for g: int in t.guests:
		if g != 0:
			seated.append(g)
	for i in seated.size():
		var a: Dictionary = lookup[seated[i]]
		for j in range(i + 1, seated.size()):
			var b: Dictionary = lookup[seated[j]]
			if is_apart(a.id, b.id):
				cost += COST_APART
			if a.group != "" and b.group != "":
				cost += -BONUS_SAME_GROUP if a.group == b.group else COST_MIXED_GROUP
	for pair in neighbours(t):
		var x: int = t.guests[pair.x]
		var y: int = t.guests[pair.y]
		if x != 0 and y != 0 and lookup[x].party == lookup[y].party:
			cost -= BONUS_PARTY_NEIGHBOUR
	if seated.size() == 1 and t.seats > 2:
		cost += COST_LONELY
	return cost


func _party_cost(party: int, members: Array, table_of: Dictionary) -> float:
	var where := {}
	for m: int in members:
		if table_of.has(m):
			where[table_of[m]] = true
	return COST_PARTY_SPLIT * maxi(0, where.size() - 1)


## The total score of the current seating (lower is better).
func score() -> float:
	var lookup := _lookup()
	var table_of := _table_of()
	var total := 0.0
	for t in tables:
		total += _table_cost(t, lookup)
	var parties := _parties()
	for p: int in parties:
		total += _party_cost(p, parties[p], table_of)
	return total


func _lookup() -> Dictionary:
	var lookup := {}
	for g in guests:
		lookup[g.id] = g
	return lookup


func _table_of() -> Dictionary:
	var out := {}
	for ti in tables.size():
		for g: int in tables[ti].guests:
			if g != 0:
				out[g] = ti
	return out


func _parties() -> Dictionary:
	var parties := {}
	for g in guests:
		if not parties.has(g.party):
			parties[g.party] = []
		parties[g.party].append(g.id)
	return parties


## Seats everyone who is not seated yet, household by household, at the table that suits them best
## (room for the whole household, people from their group, nobody they must avoid).
func place_unseated() -> void:
	var lookup := _lookup()
	var parties := _parties()
	var waiting := unseated()
	var done := {}
	# Biggest households first: they are the hardest to fit.
	var order: Array = []
	for id in waiting:
		var p: int = lookup[id].party
		if not done.has(p):
			done[p] = true
			order.append(p)
	order.sort_custom(func(a: int, b: int) -> bool: return parties[a].size() > parties[b].size() or (parties[a].size() == parties[b].size() and a < b))
	for p: int in order:
		var members: Array = parties[p].filter(func(m: int) -> bool: return waiting.has(m))
		var best := -1
		var best_score := INF
		for ti in tables.size():
			var t := tables[ti]
			var free: int = t.guests.count(0)
			if free == 0:
				continue
			var s := 0.0
			if free < members.size():
				s += 1000.0 * (members.size() - free)
			for g: int in t.guests:
				if g == 0:
					continue
				for m: int in members:
					if is_apart(g, m):
						s += COST_APART
					if lookup[g].group != "" and lookup[g].group == lookup[m].group:
						s -= BONUS_SAME_GROUP
					elif lookup[g].group != "" and lookup[m].group != "":
						s += COST_MIXED_GROUP
			# Prefer emptier tables a little, so groups get room to grow.
			s -= free * 0.2
			if s < best_score:
				best_score = s
				best = ti
		if best == -1:
			return
		var t := tables[best]
		# Fill the longest run of empty seats, so the household sits side by side.
		for m: int in members:
			var slot: int = _free_seat_near(t, members)
			if slot == -1:
				break
			t.guests[slot] = m


func _free_seat_near(t: Dictionary, members: Array) -> int:
	var n: int = t.seats
	for i in n:
		if t.guests[i] == 0:
			# Next to someone of the same household, when possible.
			var left: int = t.guests[(i - 1 + n) % n]
			var right: int = t.guests[(i + 1) % n]
			if members.has(left) or members.has(right):
				return i
	return t.guests.find(0)


## Improves the seating by swapping seats (simulated annealing). Locked guests never move.
## Call it repeatedly with a share of the work so the screen stays responsive; returns the score.
## The inner loop works on packed arrays of guest indexes (not dictionaries) so it is fast in the browser.
func improve(steps: int, rng: RandomNumberGenerator, temperature: float, exhaustive: bool = false) -> float:
	var n := guests.size()
	var tcount := tables.size()
	if n < 1 or tcount < 1:
		return score()
	var index := {}
	var group := PackedInt32Array()
	var party := PackedInt32Array()
	var locked := PackedByteArray()
	var group_ids := {}
	var party_ids := {}
	group.resize(n)
	party.resize(n)
	locked.resize(n)
	for i in n:
		var g := guests[i]
		index[g.id] = i
		if g.group == "":
			group[i] = -1
		else:
			if not group_ids.has(g.group):
				group_ids[g.group] = group_ids.size()
			group[i] = group_ids[g.group]
		if not party_ids.has(g.party):
			party_ids[g.party] = party_ids.size()
		party[i] = party_ids[g.party]
		locked[i] = 1 if g.locked else 0
	var party_count := party_ids.size()
	var avoid := PackedByteArray()
	avoid.resize(n * n)
	for pair in apart:
		if index.has(pair.x) and index.has(pair.y):
			avoid[index[pair.x] * n + index[pair.y]] = 1
			avoid[index[pair.y] * n + index[pair.x]] = 1
	# seats[t] holds guest indexes, -1 for an empty seat; pairs[t] the neighbouring seat pairs, flattened.
	var seats: Array[PackedInt32Array] = []
	var pairs: Array[PackedInt32Array] = []
	var lonely_ok := PackedByteArray()
	_sv_ptc = PackedInt32Array()
	_sv_ptc.resize(party_count * tcount)
	var movable_t := PackedInt32Array()
	var movable_s := PackedInt32Array()
	for ti in tcount:
		var t := tables[ti]
		var row := PackedInt32Array()
		row.resize(t.seats)
		for si in t.seats:
			var id: int = t.guests[si]
			var gi: int = index.get(id, -1) if id != 0 else -1
			row[si] = gi
			if gi != -1:
				_sv_ptc[party[gi] * tcount + ti] += 1
			if gi == -1 or locked[gi] == 0:
				movable_t.append(ti)
				movable_s.append(si)
		seats.append(row)
		var flat := PackedInt32Array()
		for p in neighbours(t):
			flat.append(p.x)
			flat.append(p.y)
		pairs.append(flat)
		lonely_ok.append(1 if t.seats <= 2 else 0)
	var movable := movable_t.size()
	_sv_n = n
	_sv_tcount = tcount
	_sv_group = group
	_sv_party = party
	_sv_avoid = avoid
	_sv_seats = seats
	_sv_pairs = pairs
	_sv_lonely = lonely_ok
	if movable < 2:
		return score()

	_sv_mt = movable_t
	_sv_ms = movable_s
	_sv_costs = PackedFloat64Array()
	_sv_costs.resize(tcount)
	for ti in tcount:
		_sv_costs[ti] = _sv_table_cost(ti)
	if exhaustive and movable <= 160:
		# Polish: try every pair of seats, keep each swap that helps, until a full pass finds none.
		for pass_index in 4:
			var better := false
			for ia in movable:
				for ib in range(ia + 1, movable):
					if _sv_try(ia, ib, 0.0, rng):
						better = true
			if not better:
				break
	else:
		for step in steps:
			var ia := rng.randi() % movable
			var ib := rng.randi() % movable
			if ia != ib:
				_sv_try(ia, ib, temperature, rng)
	for ti in tcount:
		var row: PackedInt32Array = _sv_seats[ti]
		for si in row.size():
			tables[ti].guests[si] = guests[row[si]].id if row[si] != -1 else 0
	return score()


## Seats everyone in one go (used by tests; the app runs the same steps across frames).
func auto_seat(seed_value: int = 1, rounds: int = 40, steps_per_round: int = 400) -> float:
	place_unseated()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result := score()
	for r in rounds:
		result = improve(steps_per_round, rng, temperature_for(r, rounds))
	result = improve(0, rng, 0.0, true)
	return result


static func temperature_for(round_index: int, rounds: int) -> float:
	var progress := float(round_index) / maxf(1.0, rounds - 1.0)
	return lerpf(20.0, 0.0, progress)


# ------------------------------------------------------------------ Guest lists

## Reads a pasted guest list. One guest per line: "Name, group, diet" (tabs work too, as from a
## spreadsheet). "Group:" on its own line sets the group for the lines below it. A line with
## "&" or "and" between first names ("Tom & Lisa Meyer") or ending in "+1" adds a household.
## Returns the ids added.
func import_text(text: String) -> Array[int]:
	var added: Array[int] = []
	var group := ""
	var header_skipped := false
	for raw in text.replace("\r", "").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.ends_with(":") and not line.contains(","):
			group = line.trim_suffix(":").strip_edges()
			continue
		var parts := line.split("\t") if line.contains("\t") else line.split(",")
		var cells: Array[String] = []
		for p in parts:
			cells.append(p.strip_edges().trim_prefix("\"").trim_suffix("\""))
		if not header_skipped and cells[0].to_lower() in ["name", "guest", "guests", "names"]:
			header_skipped = true
			continue
		header_skipped = true
		if cells[0] == "":
			continue
		var line_group := cells[1] if cells.size() > 1 and cells[1] != "" else group
		var diet := cells[2] if cells.size() > 2 else ""
		for id in _add_household(cells[0], line_group, diet):
			added.append(id)
		if guests.size() >= MAX_GUESTS:
			break
	return added


func _add_household(text: String, group: String, diet: String) -> Array[int]:
	var ids: Array[int] = []
	var plus_one := false
	var name := text
	var plus := RegEx.create_from_string("\\s*\\+\\s*1\\s*$")
	if plus.search(name):
		plus_one = true
		name = plus.sub(name, "")
	var pair := RegEx.create_from_string("^(\\S+)\\s+(?:&|and|und|et|y)\\s+(\\S+)(?:\\s+(.+))?$")
	var m := pair.search(name)
	if m:
		var surname := m.get_string(3) if m else ""
		var first := m.get_string(1) + ("" if surname == "" else " " + surname)
		var second := m.get_string(2) + ("" if surname == "" else " " + surname)
		var a := add_guest(first, group, diet)
		ids.append(a)
		ids.append(add_guest(second, group, diet, get_guest(a).party))
	else:
		ids.append(add_guest(name, group, diet))
	if plus_one:
		ids.append(add_guest("Guest of %s" % get_guest(ids[0]).name, group, "", get_guest(ids[0]).party))
	return ids


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


static func csv_cell(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"" + value.replace("\"", "\"\"") + "\""
	# Cells that a spreadsheet would run as a formula are written as text.
	if value.length() > 0 and value[0] in ["=", "+", "-", "@"]:
		return "'" + value
	return value


func to_csv() -> String:
	var lines: Array[String] = ["Name,Table,Seat,Group,Diet"]
	for row in seat_list():
		var cells: Array[String] = []
		for c in row:
			cells.append(csv_cell(c))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ Saving and history

func to_dict() -> Dictionary:
	var pairs: Array = []
	for p in apart:
		pairs.append([p.x, p.y])
	return {"app": "seatwise", "version": 1, "title": title, "tables": tables.duplicate(true), "guests": guests.duplicate(true), "apart": pairs}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")


## Loads a saved plan. Returns an empty string, or why it could not.
func from_json(text: String) -> String:
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary) or parser.data.get("app", "") != "seatwise":
		return "This is not a Seatwise plan."
	var data: Dictionary = parser.data
	var new_tables: Array[Dictionary] = []
	var new_guests: Array[Dictionary] = []
	var top := 0
	var guest_ids := {}
	for raw: Variant in data.get("guests", []):
		if raw is Dictionary and guest_ids.size() < MAX_GUESTS:
			var g := {
				"id": int(raw.get("id", 0)), "name": str(raw.get("name", "Guest")).left(60), "group": str(raw.get("group", "")).left(40),
				"diet": str(raw.get("diet", "")).left(30), "party": int(raw.get("party", 0)), "locked": bool(raw.get("locked", false)),
			}
			if g.id <= 0 or guest_ids.has(g.id):
				continue
			guest_ids[g.id] = true
			new_guests.append(g)
			top = maxi(top, g.id)
	for g in new_guests:
		if not guest_ids.has(g.party):
			g.party = g.id
	var seated := {}
	for raw: Variant in data.get("tables", []):
		if not (raw is Dictionary):
			continue
		var t := {
			"id": int(raw.get("id", 0)), "shape": str(raw.get("shape", "round")), "seats": clampi(int(raw.get("seats", 8)), 1, MAX_SEATS),
			"x": float(raw.get("x", 0)), "y": float(raw.get("y", 0)), "rot": fposmod(float(raw.get("rot", 0)), 360.0),
			"name": str(raw.get("name", "Table")).left(40), "guests": [],
		}
		if not (t.shape in SHAPES):
			t.shape = "round"
		var list: Array = raw.get("guests", []) if raw.get("guests") is Array else []
		for i in t.seats:
			var g := int(list[i]) if i < list.size() else 0
			if g != 0 and (not guest_ids.has(g) or seated.has(g)):
				g = 0
			if g != 0:
				seated[g] = true
			t.guests.append(g)
		new_tables.append(t)
		top = maxi(top, t.id)
	var new_apart: Array[Vector2i] = []
	for raw: Variant in data.get("apart", []):
		if raw is Array and raw.size() == 2 and guest_ids.has(int(raw[0])) and guest_ids.has(int(raw[1])) and int(raw[0]) != int(raw[1]):
			new_apart.append(Vector2i(mini(int(raw[0]), int(raw[1])), maxi(int(raw[0]), int(raw[1]))))
	title = str(data.get("title", "Our event")).strip_edges().left(60)
	if title == "":
		title = "Our event"
	tables = new_tables
	guests = new_guests
	apart = new_apart
	_next_id = top + 1
	var seen := {}
	for t in tables:
		if seen.has(t.id) or t.id <= 0 or guest_ids.has(t.id):
			t.id = _next_id
			_next_id += 1
		seen[t.id] = true
	return ""


func checkpoint() -> void:
	_undo.push_back(to_json())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func drop_checkpoint_if_unchanged() -> void:
	if not _undo.is_empty() and _undo.back() == to_json():
		_undo.pop_back()


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


## The example a first visit opens: a wedding dinner of 38 made-up guests at five tables,
## not seated yet, so "Seat everyone" has something to do.
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
	set_apart(_find("Karl Lindqvist"), _find("Henrik Weber"))
	set_apart(_find("Ben Carter"), _find("Hanna Berg"))
	# The couple sits in the middle of the head table and stays there.
	var head := tables[0]
	head.guests[2] = _find("Mara Lindqvist")
	head.guests[3] = _find("Jonas Lindqvist")
	get_guest(_find("Mara Lindqvist")).locked = true
	get_guest(_find("Jonas Lindqvist")).locked = true


func _find(name: String) -> int:
	for g in guests:
		if g.name == name:
			return g.id
	return 0


## Throws away everything since the last checkpoint (a drag cancelled by a second finger), leaving no redo step.
func discard_to_checkpoint() -> void:
	if not _undo.is_empty():
		from_json(_undo.pop_back())


func _sv_table_cost(ti: int) -> float:
	var row: PackedInt32Array = _sv_seats[ti]
	var n := _sv_n
	var cost := 0.0
	var seated := 0
	var size := row.size()
	for i in size:
		var a := row[i]
		if a == -1:
			continue
		seated += 1
		var ga := _sv_group[a]
		var base := a * n
		for j in range(i + 1, size):
			var b := row[j]
			if b == -1:
				continue
			if _sv_avoid[base + b] == 1:
				cost += COST_APART
			var gb := _sv_group[b]
			if ga != -1 and gb != -1:
				cost += -BONUS_SAME_GROUP if ga == gb else COST_MIXED_GROUP
	var flat: PackedInt32Array = _sv_pairs[ti]
	for k in range(0, flat.size(), 2):
		var x := row[flat[k]]
		var y := row[flat[k + 1]]
		if x != -1 and y != -1 and _sv_party[x] == _sv_party[y]:
			cost -= BONUS_PARTY_NEIGHBOUR
	if seated == 1 and _sv_lonely[ti] == 0:
		cost += COST_LONELY
	return cost


func _sv_party_cost(p: int) -> float:
	var used := 0
	var base := p * _sv_tcount
	for ti in _sv_tcount:
		if _sv_ptc[base + ti] > 0:
			used += 1
	return COST_PARTY_SPLIT * maxi(0, used - 1)


## Swaps two movable seats when that lowers the score (or, while hot, sometimes when it does not).
## Returns true when the swap made the plan strictly better.
func _sv_try(ia: int, ib: int, temperature: float, rng: RandomNumberGenerator) -> bool:
	var tcount := _sv_tcount
	var ta := _sv_mt[ia]
	var sa := _sv_ms[ia]
	var tb := _sv_mt[ib]
	var sb := _sv_ms[ib]
	var ga: int = _sv_seats[ta][sa]
	var gb: int = _sv_seats[tb][sb]
	if ga == gb:
		return false
	var same_table := ta == tb
	var pa := _sv_party[ga] if ga != -1 else -1
	var pb := _sv_party[gb] if gb != -1 else -1
	var before := _sv_costs[ta] + (0.0 if same_table else _sv_costs[tb])
	if not same_table:
		if pa != -1:
			before += _sv_party_cost(pa)
		if pb != -1 and pb != pa:
			before += _sv_party_cost(pb)
	_sv_seats[ta][sa] = gb
	_sv_seats[tb][sb] = ga
	if not same_table:
		if pa != -1:
			_sv_ptc[pa * tcount + ta] -= 1
			_sv_ptc[pa * tcount + tb] += 1
		if pb != -1:
			_sv_ptc[pb * tcount + tb] -= 1
			_sv_ptc[pb * tcount + ta] += 1
	var cost_a: float = _sv_table_cost(ta)
	var cost_b: float = cost_a if same_table else _sv_table_cost(tb)
	var after := cost_a + (0.0 if same_table else cost_b)
	if not same_table:
		if pa != -1:
			after += _sv_party_cost(pa)
		if pb != -1 and pb != pa:
			after += _sv_party_cost(pb)
	var delta := after - before
	if delta < -0.0001 or (delta <= 0.0 and temperature > 0.0) or (temperature > 0.0 and rng.randf() < exp(-delta / temperature)):
		_sv_costs[ta] = cost_a
		_sv_costs[tb] = cost_b
		return delta < -0.0001
	_sv_seats[ta][sa] = ga
	_sv_seats[tb][sb] = gb
	if not same_table:
		if pa != -1:
			_sv_ptc[pa * tcount + ta] += 1
			_sv_ptc[pa * tcount + tb] -= 1
		if pb != -1:
			_sv_ptc[pb * tcount + tb] += 1
			_sv_ptc[pb * tcount + ta] -= 1
	return false
