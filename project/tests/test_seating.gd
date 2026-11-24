extends SceneTree
## Run with: godot --headless --path project --script res://tests/test_seating.gd
## Exits with 1 when a check fails.

var failures := 0


func check(condition: bool, what: String) -> void:
	if condition:
		print("  ok  ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


func names(s: Seating, ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: int in ids:
		out.append(s.get_guest(id).name)
	return out


func same_table(s: Seating, a: int, b: int) -> bool:
	var x := s.seat_of(a)
	var y := s.seat_of(b)
	return not x.is_empty() and not y.is_empty() and x.table == y.table


func adjacent(s: Seating, a: int, b: int) -> bool:
	if not same_table(s, a, b):
		return false
	var t := s.get_table(s.seat_of(a).table)
	for pair in Seating.neighbours(t):
		var x: int = t.guests[pair.x]
		var y: int = t.guests[pair.y]
		if (x == a and y == b) or (x == b and y == a):
			return true
	return false


func _init() -> void:
	# Tables and seats
	var s := Seating.new()
	var round_id := s.add_table("round", 8, 0, 0)
	var round_table := s.get_table(round_id)
	var seats := Seating.seat_positions(round_table)
	check(seats.size() == 8, "a round table for 8 has 8 seats")
	var radius := seats[0].length()
	var even := true
	for p in seats:
		even = even and absf(p.length() - radius) < 0.01
	check(even and radius > Seating.table_size(round_table).x / 2.0, "round seats sit evenly around the table, outside its edge")
	check(seats[0].distance_to(seats[1]) >= 50.0, "there is elbow room between round seats")
	check(Seating.neighbours(round_table).size() == 8, "round seats wrap around: 8 pairs of neighbours")
	var head := s.get_table(s.add_table("head", 5, 0, 0))
	check(Seating.neighbours(head).size() == 4 and Seating.seat_positions(head).size() == 5, "a head table is one row: 4 pairs for 5 seats")
	var long := s.get_table(s.add_table("rect", 10, 0, 0))
	var long_seats := Seating.seat_positions(long)
	check(long_seats.size() == 10, "a long table for 10 has 10 seats")
	var ends := 0
	for p in long_seats:
		if absf(p.y) < 0.01:
			ends += 1
	check(ends == 2, "a long table for 10 has a seat at each end")
	var small_ends := 0
	for p in Seating.seat_positions(s.get_table(s.add_table("rect", 6, 0, 0))):
		if absf(p.y) < 0.01:
			small_ends += 1
	check(small_ends == 0, "a small rectangular table has no end seats")
	check(s.capacity() == 8 + 5 + 10 + 6, "capacity counts every seat")
	long.rot = 90.0
	var turned := Seating.seat_positions(long)
	check(absf(turned[0].x - (-long_seats[0].y)) < 0.01 and absf(turned[0].y - long_seats[0].x) < 0.01, "turning a table turns its seats")
	check(s.get_table(s.add_table("round", 99, 0, 0)).seats == Seating.MAX_SEATS, "tables have at most 24 seats")

	# Guests, seats and households
	var e := Seating.new()
	var t1 := e.add_table("round", 4, 0, 0)
	var t2 := e.add_table("round", 4, 300, 0)
	var anna := e.add_guest("Anna Berg", "Family")
	var ben := e.add_guest("Ben Berg", "Family")
	var cleo := e.add_guest("Cleo Diaz", "Work")
	check(e.unseated().size() == 3, "new guests are unseated")
	e.seat(anna, t1, 0)
	check(e.seat_of(anna) == {"table": t1, "seat": 0}, "seating a guest")
	e.seat(ben, t1, 0)
	check(e.seat_of(ben).seat == 0 and e.seat_of(anna).is_empty(), "taking a seat from someone unseated leaves them without one")
	e.seat(anna, t2, 1)
	e.seat(anna, t1, 0)
	check(e.seat_of(anna).seat == 0 and e.seat_of(ben) == {"table": t2, "seat": 1}, "moving onto a taken seat swaps the two guests")
	e.join_party(anna, ben)
	check(e.party_members(e.get_guest(anna).party).size() == 2, "joining makes a household")
	check(e.problems().any(func(p: Dictionary) -> bool: return p.text.contains("split across 2 tables")), "a split household is reported")
	e.leave_party(ben)
	check(e.party_members(e.get_guest(anna).party).size() == 1, "leaving a household")
	e.set_apart(anna, cleo)
	e.seat(cleo, t1, 2)
	check(e.problems().any(func(p: Dictionary) -> bool: return p.text == "Anna Berg and Cleo Diaz should not sit at Table 1 together"), "people who should be apart are reported in words")
	e.set_apart(cleo, anna, false)
	check(e.problems().is_empty(), "removing the wish clears the problem")
	e.remove_guest(cleo)
	check(e.get_guest(cleo).is_empty() and e.get_table(t1).guests.count(cleo) == 0, "removing a guest frees their seat")
	e.set_seats(t1, 1)
	check(e.get_table(t1).guests == [anna], "fewer seats keep who was seated first")
	e.add_guest("Dan Eze")
	e.add_guest("Eva Fox")
	e.add_guest("Finn Gale")
	e.add_guest("Gus Hill")
	check(e.problems().any(func(p: Dictionary) -> bool: return p.text.contains("no seat: add 1 more seat")), "too few seats are reported with how many are missing")
	check(e.diet_counts().is_empty(), "no diets, no counts")

	# Pasted lists
	var p := Seating.new()
	var added := p.import_text("Name,Group,Diet\nFamily:\nTom & Lisa Meyer\nAnna Berg, Friends, Vegetarian\n\n# a comment\nJo Kim +1\nSam and Alex\n\"Lee, Ann\"\tWork\tvegan\n")
	check(added.size() == 8, "a pasted list adds every guest, households included")
	check(names(p, added).slice(0, 3) == ["Tom Meyer", "Lisa Meyer", "Anna Berg"], "\"Tom & Lisa Meyer\" becomes two guests with the shared surname")
	check(p.get_guest(added[0]).party == p.get_guest(added[1]).party, "a couple on one line is one household")
	check(p.get_guest(added[0]).group == "Family" and p.get_guest(added[2]).group == "Friends", "\"Group:\" lines set the group; a group on the line wins")
	check(p.get_guest(added[2]).diet == "vegetarian", "diets are read and kept in lower case")
	check(p.get_guest(added[4]).name == "Guest of Jo Kim" and p.get_guest(added[4]).party == p.get_guest(added[3]).party, "\"+1\" adds a guest in the same household")
	check(names(p, added).slice(5, 7) == ["Sam", "Alex"], "\"Sam and Alex\" without a surname")
	check(p.get_guest(added[7]).name == "Lee, Ann" and p.get_guest(added[7]).group == "Work" and p.get_guest(added[7]).diet == "vegan", "tab-separated rows from a spreadsheet")
	check(p.diet_counts() == {"vegetarian": 1, "vegan": 1}, "diet counts across the event")
	check(Seating.sort_key("Lisa Meyer") < Seating.sort_key("Tom Meyer") and Seating.sort_key("Anna Berg") < Seating.sort_key("Lisa Meyer"), "lists sort by last name")
	check(Seating.csv_cell("=1+1") == "'=1+1" and Seating.csv_cell("a, b") == "\"a, b\"" and Seating.csv_cell("say \"hi\"") == "\"say \"\"hi\"\"\"", "CSV cells are quoted, and formulas are written as text")

	# The solver
	var w := Seating.new()
	w.load_example()
	var guest_count := w.guests.size()
	check(guest_count == 38 and w.capacity() >= guest_count, "the example has 38 guests and enough seats")
	var mara := w._find("Mara Lindqvist")
	var mara_seat := w.seat_of(mara)
	var score := w.auto_seat(7)
	check(w.unseated().is_empty(), "seat everyone: nobody is left without a seat")
	check(w.problems().is_empty(), "seat everyone: no wish is broken (%s)" % ", ".join(w.problems().map(func(x: Dictionary) -> String: return x.text)))
	check(w.seat_of(mara) == mara_seat, "locked guests stay where they are")
	var couples_together := true
	var parties := w._parties()
	for party: int in parties:
		var members: Array = parties[party]
		if members.size() == 2:
			couples_together = couples_together and adjacent(w, members[0], members[1])
	check(couples_together, "every couple sits side by side")
	check(not same_table(w, w._find("Karl Lindqvist"), w._find("Henrik Weber")), "the two fathers sit at different tables")
	var head_table: Dictionary = w.tables[0]
	var party_at_head := true
	for g in w.guests:
		if g.group == "Wedding party":
			party_at_head = party_at_head and w.seat_of(g.id).get("table", -1) == head_table.id
	check(party_at_head, "the whole wedding party sits at the head table")
	var groups_ok := 0
	for t in w.tables:
		var seen := {}
		for g: int in t.guests:
			if g != 0:
				seen[w.get_guest(g).group] = true
		if seen.size() <= 2:
			groups_ok += 1
	check(groups_ok >= w.tables.size() - 1, "tables mostly keep groups together (%d of %d tables have at most 2 groups)" % [groups_ok, w.tables.size()])
	var again := Seating.new()
	again.load_example()
	check(is_equal_approx(again.auto_seat(7), score), "the same seed gives the same seating")
	var better := Seating.new()
	better.load_example()
	better.place_unseated()
	var greedy := better.score()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var improved := better.improve(4000, rng, 0.0)
	check(improved <= greedy, "improving never makes it worse at temperature 0")
	var tight := Seating.new()
	tight.add_table("round", 2, 0, 0)
	tight.add_table("round", 2, 200, 0)
	var x := tight.add_guest("X")
	var y := tight.add_guest("Y")
	tight.add_guest("Z")
	tight.join_party(x, y)
	tight.auto_seat(1)
	check(same_table(tight, x, y) and tight.unseated().is_empty(), "a household is kept together when it fits")
	var over := Seating.new()
	over.add_table("round", 2, 0, 0)
	for i in 3:
		over.add_guest("G%d" % i)
	over.auto_seat(1)
	check(over.unseated().size() == 1, "with too few seats, the rest wait unseated")
	var empty := Seating.new()
	check(empty.auto_seat(1) == 0.0 and empty.problems().is_empty(), "an empty plan is fine")

	# Lists, files and history
	var csv := w.to_csv()
	check(csv.begins_with("Name,Table,Seat,Group,Diet\n") and csv.split("\n", false).size() == guest_count + 1, "the CSV has a header and one row per guest")
	var rows := w.seat_list()
	check(rows[0][0] == "Hanna Berg" and rows[0][1] != "", "the find-your-seat list is alphabetical by last name, with tables")
	var json := w.to_json()
	var copy := Seating.new()
	check(copy.from_json(json) == "" and copy.to_json() == json, "a plan saves and loads unchanged")
	check(copy.from_json("{\"app\":\"other\"}") != "" and copy.from_json("nope") != "" and copy.to_json() == json, "other files are refused and change nothing")
	var messy := "{\"app\":\"seatwise\",\"guests\":[{\"id\":5,\"name\":\"A\"},{\"id\":5,\"name\":\"B\"},{\"id\":6,\"name\":\"C\",\"party\":99}],\"tables\":[{\"id\":5,\"seats\":3,\"guests\":[5,5,77]}],\"apart\":[[5,5],[5,6]]}"
	check(copy.from_json(messy) == "" and copy.guests.size() == 2 and copy.get_guest(6).party == 6, "repeated or broken guests in a file are cleaned up")
	check(copy.tables[0].guests == [5, 0, 0] and copy.tables[0].id != 5 and copy.apart.size() == 1, "seats point only at real guests, ids are unique, broken wishes are dropped")
	var h := Seating.new()
	h.checkpoint()
	h.add_guest("A")
	check(h.undo() and h.guests.is_empty() and h.redo() and h.guests.size() == 1, "undo and redo")
	h.checkpoint()
	h.drop_checkpoint_if_unchanged()
	check(h.can_undo() and h.undo() and h.guests.is_empty() and not h.can_undo(), "an unchanged step leaves no extra undo")

	print("%d failures" % failures)
	quit(1 if failures > 0 else 0)
